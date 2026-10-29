import AppKit
import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import ClaudeSafariHostIPC
import Foundation

actor ClaudeSafariHostClientAdapter {
    /// The Host owns two explicit ten-second verification phases. This outer
    /// deadline bounds the complete transaction and mailbox delivery only;
    /// acknowledgements, not elapsed time, synchronize phase progress.
    static let verificationTransactionDeadline: Duration = .seconds(23)

    private let client: ClaudeSafariHostIPCClient
    private let generation: String
    private let hostApplicationIdentifier: String
    private var listener: ClaudeSafariHostIPCResponseListener?
    private var consumer: ClaudeBrowserOrderedConsumer?
    private var waiters: [String: CheckedContinuation<ClaudeSafariHostVerificationTrace, Never>] = [:]
    private var acceptedResponseIDs: Set<String> = []
    private var acceptedResponseIDOrder: [String] = []
    private var controlRequestIDs: Set<String> = []
    private var controlRequestIDOrder: [String] = []
    private var activeWorkRequestIDs: Set<String> = []
    /// The app that was in front when a read opened a temporary Safari window,
    /// so it can be brought back if Safari took the front while reading.
    private var focusReturnTargets: [String: pid_t] = [:]
    private let safariWindowVisibility: @Sendable () -> Bool?

    init?(
        bundle: Bundle = .main,
        safariWindowVisibility: @escaping @Sendable () -> Bool? = {
            SafariWindowVisibility.hasWindowOnCurrentDesktop()
        }
    ) {
        guard let context = ClaudeBrowserRuntimeContext.current(bundle: bundle),
              let endpoint = try? ClaudeSafariHostIPCEndpoint.appGroup(
                identifier: context.appGroupIdentifier
              )
        else { return nil }
        client = ClaudeSafariHostIPCClient(endpoint: endpoint)
        generation = context.runtimeGenerationID
        hostApplicationIdentifier = context.identity.containingApplicationIdentifier
        self.safariWindowVisibility = safariWindowVisibility
    }

    func start(_ handler: @escaping ClaudeBrowserProductionIntegration.MessageHandler) -> Bool {
        consumer = ClaudeBrowserOrderedConsumer(processor: handler)
        return listen()
    }

    func stop() {
        listener?.stop()
        listener = nil
        consumer = nil
        controlRequestIDs.removeAll()
        controlRequestIDOrder.removeAll()
        activeWorkRequestIDs.removeAll()
        focusReturnTargets.removeAll()
        let active = waiters.values
        waiters.removeAll()
        for waiter in active {
            waiter.resume(returning: .init(
                verification: .unavailable,
                requestID: nil,
                runtimeGenerationID: generation,
                occurredAt: ISO8601DateFormatter().string(from: Date()),
                reachedStages: [],
                firstFailureReason: .listenerStopped,
                runtimeDescriptor: nil
            ))
        }
    }

    func verify() async -> ClaudeBrowserCompanionVerification {
        await diagnose().verification
    }

    func diagnose(
        allowSafariLaunch: Bool = false
    ) async -> ClaudeSafariHostVerificationTrace {
        guard listen() else {
            return localFailure(reason: .responseListenerUnavailable)
        }
        let request = ClaudeSafariHostIPCRequest(
            runtimeGenerationID: generation,
            operation: .verifyCompanion,
            allowSafariLaunch: allowSafariLaunch
        )
        let initialStages: [ClaudeBrowserCompanionDiagnosticResult.Stage] = [
            .testAppRunning,
            .testRuntimeIdentityVerified,
            .listenerReady,
            .requestCreated,
            .wakeDispatchStarted,
        ]
        guard await wakeHost() else {
            return localFailure(
                requestID: request.requestID,
                stages: initialStages,
                reason: .hostApplicationUnavailable
            )
        }
        return await withCheckedContinuation { continuation in
            waiters[request.requestID] = continuation
            do {
                try client.submit(request)
            }
            catch {
                waiters.removeValue(forKey: request.requestID)?.resume(returning:
                    localFailure(
                        requestID: request.requestID,
                        stages: initialStages,
                        reason: .requestSubmissionFailed
                    )
                )
                return
            }
            Task {
                try? await Task.sleep(for: Self.verificationTransactionDeadline)
                self.expire(request.requestID)
            }
        }
    }

    func submit(requestID: String, oneShot: Bool) async -> ClaudeBrowserAutomaticDispatchResult {
        let normalizedRequestID = requestID.lowercased()
        guard UUID(uuidString: normalizedRequestID) != nil,
              activeWorkRequestIDs.isEmpty,
              listen()
        else { return .workDispatchFailed }
        guard await wakeHost() else { return .browserUnavailable }
        let operation: ClaudeSafariHostIPCOperation = oneShot ? .accuracySync : .automaticRefresh
        let placement = SafariWindowVisibility.placement(
            hasWindowOnCurrentDesktop: safariWindowVisibility()
        )
        if placement == .temporaryWindow,
           let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != SafariWindowVisibility.bundleIdentifier {
            focusReturnTargets[normalizedRequestID] = front.processIdentifier
        }
        // Register before publishing the request file. The Host may consume and
        // answer immediately on a warm App Group listener; no valid terminal
        // response may arrive before the adapter recognizes its request ID.
        activeWorkRequestIDs.insert(normalizedRequestID)
        do {
            try client.submit(.init(
                requestID: normalizedRequestID,
                runtimeGenerationID: generation,
                operation: operation,
                allowSafariLaunch: oneShot,
                providerPlacement: placement
            ))
            return .dispatched
        } catch {
            activeWorkRequestIDs.remove(normalizedRequestID)
            focusReturnTargets.removeValue(forKey: normalizedRequestID)
            return .workDispatchFailed
        }
    }

    func close(_ requestID: String) async {
        // Once AUV gives up on a read it is no longer in flight here, even if
        // its answer never arrives; otherwise every later read is refused.
        finishWork(requestID.lowercased())
        guard UUID(uuidString: requestID) != nil, listen(), await wakeHost() else { return }
        let commandID = UUID().uuidString.lowercased()
        rememberControlRequest(commandID)
        do {
            try client.submit(.init(
                requestID: commandID,
                runtimeGenerationID: generation,
                operation: .closeOwnedTab,
                targetRequestID: requestID
            ))
        } catch {
            forgetControlRequest(commandID)
        }
    }

    @discardableResult
    private func finishWork(_ requestID: String) -> Bool {
        let wasActive = activeWorkRequestIDs.remove(requestID) != nil
        if let target = focusReturnTargets.removeValue(forKey: requestID) {
            Self.returnFocus(to: target)
        }
        return wasActive
    }

    /// Brings back the app that was in front before a temporary Safari window
    /// opened, but only if Safari is in front now: anything the person switched
    /// to in the meantime is left alone.
    private static func returnFocus(to processIdentifier: pid_t) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                == SafariWindowVisibility.bundleIdentifier,
              let target = NSRunningApplication(processIdentifier: processIdentifier),
              !target.isTerminated
        else { return }
        target.activate()
    }

    private func listen() -> Bool {
        if listener != nil { return true }
        let next = client.makeResponseListener { [weak self] response in
            Task { await self?.receive(response) }
        }
        do { try next.start(); listener = next; return true }
        catch { return false }
    }

    private func receive(_ response: ClaudeSafariHostIPCResponse) {
        guard response.isStructurallyValid else {
            waiters.removeValue(forKey: response.requestID)?.resume(returning:
                localFailure(
                    requestID: response.requestID,
                    stages: [
                        .testAppRunning, .testRuntimeIdentityVerified,
                        .listenerReady, .requestCreated, .wakeDispatchStarted,
                        .requestSubmitted,
                    ],
                    reason: .invalidHostTerminalResponse,
                    verification: .protocolMismatch
                )
            )
            return
        }
        guard acceptedResponseIDs.insert(response.responseID).inserted else { return }
        acceptedResponseIDOrder.append(response.responseID)
        if acceptedResponseIDOrder.count > 64 {
            acceptedResponseIDs.remove(acceptedResponseIDOrder.removeFirst())
        }
        if controlRequestIDs.contains(response.requestID) {
            forgetControlRequest(response.requestID)
            return
        }
        if let waiter = waiters.removeValue(forKey: response.requestID) {
            let value: ClaudeBrowserCompanionVerification
            switch (response.outcome, response.failureReason) {
            case (.companionVerified, _): value = .verified
            case (_, .runtimeGenerationMismatch), (_, .protocolMismatch): value = .protocolMismatch
            case (_, .extensionUnavailable): value = .disabled
            case (_, .safariUnavailable): value = .browserUnavailable
            case (_, .timedOut), (_, .nativeResponseUnavailable),
                 (_, .extensionBackgroundNotAcknowledged), (_, .requestInFlight):
                value = .companionStarting
            default: value = .unavailable
            }
            var stages: [ClaudeBrowserCompanionDiagnosticResult.Stage] = [
                .testAppRunning,
                .testRuntimeIdentityVerified,
                .listenerReady,
                .requestCreated,
                .wakeDispatchStarted,
                .requestSubmitted,
            ]
            if let stage = response.verificationStage {
                stages.append(contentsOf: diagnosticStages(through: stage))
            }
            stages.append(.containingAppCallbackReceived)
            if response.runtimeGenerationID == generation {
                stages.append(.callbackValidated)
            }
            let generationMatches = response.runtimeGenerationID == generation
            waiter.resume(returning: .init(
                verification: generationMatches ? value : .protocolMismatch,
                requestID: response.requestID,
                runtimeGenerationID: generation,
                occurredAt: response.occurredAt,
                reachedStages: stages,
                firstFailureReason: generationMatches
                    ? response.failureReason.flatMap {
                        ClaudeBrowserCompanionDiagnosticResult.FirstFailureReason(
                            rawValue: $0.rawValue
                        )
                    }
                    : .runtimeGenerationMismatch,
                runtimeDescriptor: response.runtimeDescriptor
            ))
        } else if activeWorkRequestIDs.contains(response.requestID),
                  response.runtimeGenerationID != generation {
            finishWork(response.requestID)
            consumer?.submit(.dispatchFailure(.protocolMismatch))
        } else if activeWorkRequestIDs.contains(response.requestID),
                  response.outcome == .completed,
                  let observation = response.observation,
                  let event = response.automationEvent {
            // A single IPC file establishes causal ordering. The ordered
            // consumer still receives the observation before the terminal
            // cleanup receipt so publication cannot race ahead of the anchor.
            finishWork(response.requestID)
            consumer?.submit(.observation(.success(observation)))
            consumer?.submit(.automation(event))
        } else if activeWorkRequestIDs.contains(response.requestID),
                  let observation = response.observation {
            consumer?.submit(.observation(.success(observation)))
        } else if activeWorkRequestIDs.contains(response.requestID),
                  let event = response.automationEvent {
            finishWork(response.requestID)
            consumer?.submit(.automation(event))
        } else if activeWorkRequestIDs.contains(response.requestID),
                  response.outcome == .failed {
            finishWork(response.requestID)
            let status: ClaudeBrowserAutomationStatus
            switch response.failureReason {
            case .protocolMismatch, .runtimeGenerationMismatch:
                consumer?.submit(.dispatchFailure(.protocolMismatch))
                return
            case .safariUnavailable:
                consumer?.submit(.dispatchFailure(.browserUnavailable))
                return
            case .extensionUnavailable, .dispatchRejected,
                 .dispatchCompletionUnavailable, .nativeResponseUnavailable,
                 .extensionBackgroundNotAcknowledged:
                consumer?.submit(.dispatchFailure(.companionUnavailable))
                return
            default:
                status = .usageUnavailable
            }
            consumer?.submit(.automation(.init(
                requestID: response.requestID,
                status: status,
                occurredAt: response.occurredAt
            )))
        }
    }

    private func expire(_ id: String) {
        waiters.removeValue(forKey: id)?.resume(returning:
            localFailure(
                requestID: id,
                stages: [
                    .testAppRunning, .testRuntimeIdentityVerified,
                    .listenerReady, .requestCreated, .wakeDispatchStarted,
                    .requestSubmitted,
                ],
                reason: .clientTransactionDeadlineExceeded,
                verification: .companionStarting
            )
        )
    }

    private func diagnosticStages(
        through stage: ClaudeSafariHostIPCVerificationStage
    ) -> [ClaudeBrowserCompanionDiagnosticResult.Stage] {
        let hostStages = ClaudeSafariHostIPCVerificationStage.allCases
        guard let terminal = hostStages.firstIndex(of: stage) else { return [] }
        return hostStages[...terminal].flatMap {
            stage -> [ClaudeBrowserCompanionDiagnosticResult.Stage] in
            switch stage {
            case .hostRequestAccepted:
                [.hostRequestAccepted]
            case .wakeDispatchAccepted:
                [.wakeDispatchAccepted]
            case .extensionBackgroundAcknowledged:
                // The signed background publishes this acknowledgement only
                // after connectNative returned a retained Port with both
                // message and disconnect listeners installed. These are
                // causally proven transitions, not elapsed-time inference.
                [
                    .extensionBackgroundAlive,
                    .nativePortOpenRequested,
                    .nativePortOpened,
                    .extensionBackgroundAcknowledged,
                ]
            case .nativeQualificationDispatched:
                [.nativeQualificationDispatched]
            case .nativeHandlerEntered:
                [.nativeHandlerEntered]
            case .nativeRequestDecoded:
                [.nativeRequestDecoded]
            case .runtimeGenerationValidated:
                [.runtimeGenerationValidated]
            case .nativeResponseCreated:
                [.nativeResponseCreated]
            case .nativeResponseSent:
                [.nativeResponseSent]
            case .extensionResponseReceived:
                [.extensionResponseReceived]
            case .nativeQualificationReceived:
                [.nativeQualificationReceived]
            case .companionVerified:
                [.companionVerified]
            }
        }
    }

    private func localFailure(
        requestID: String? = nil,
        stages: [ClaudeBrowserCompanionDiagnosticResult.Stage] = [],
        reason: ClaudeBrowserCompanionDiagnosticResult.FirstFailureReason,
        verification: ClaudeBrowserCompanionVerification = .unavailable
    ) -> ClaudeSafariHostVerificationTrace {
        .init(
            verification: verification,
            requestID: requestID,
            runtimeGenerationID: generation,
            occurredAt: ISO8601DateFormatter().string(from: Date()),
            reachedStages: stages,
            firstFailureReason: reason,
            runtimeDescriptor: nil
        )
    }

    private func rememberControlRequest(_ id: String) {
        controlRequestIDs.insert(id)
        controlRequestIDOrder.append(id)
        if controlRequestIDOrder.count > 64 {
            controlRequestIDs.remove(controlRequestIDOrder.removeFirst())
        }
    }

    private func forgetControlRequest(_ id: String) {
        controlRequestIDs.remove(id)
        controlRequestIDOrder.removeAll { $0 == id }
    }

    @MainActor
    private func wakeHost() async -> Bool {
        let id = hostApplicationIdentifier
        if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            return true
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) {
                app, error in continuation.resume(returning: app != nil && error == nil)
            }
        }
    }
}

struct ClaudeSafariHostVerificationTrace: Equatable, Sendable {
    let verification: ClaudeBrowserCompanionVerification
    let requestID: String?
    let runtimeGenerationID: String
    let occurredAt: String
    let reachedStages: [ClaudeBrowserCompanionDiagnosticResult.Stage]
    let firstFailureReason: ClaudeBrowserCompanionDiagnosticResult.FirstFailureReason?
    let runtimeDescriptor: ClaudeSafariHostIPCRuntimeDescriptor?
}
