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
    /// How long a read waits for the other provider's read to finish. It is
    /// longer than the Host's whole provider operation, so a read that ends
    /// normally always lets the waiting one start.
    static let crossProviderWaitDeadline: Duration = .seconds(45)

    private let client: ClaudeSafariHostIPCClient
    private let generation: String
    private let hostApplicationIdentifier: String
    private var listener: ClaudeSafariHostIPCResponseListener?
    private var consumer: ClaudeBrowserOrderedConsumer?
    private var geminiConsumer: SafariBridgeOrderedConsumer<GeminiBrowserInboundEvent>?
    /// The provider of each read in flight. Claude is every read without one.
    private var workProviders: [String: BrowserUsageProvider] = [:]
    private var readQueue = SafariBridgeReadQueue()
    private var idleWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var waiters: [String: CheckedContinuation<ClaudeSafariHostVerificationTrace, Never>] = [:]
    private var acceptedResponseIDs: Set<String> = []
    private var acceptedResponseIDOrder: [String] = []
    private var controlRequestIDs: Set<String> = []
    private var controlRequestIDOrder: [String] = []
    private var activeWorkRequestIDs: Set<String> = []
    /// The app that was in front when a read opened a temporary Safari window,
    /// so it can be brought back if Safari took the front while reading.
    private var focusReturnTargets: [String: pid_t] = [:]
    /// The placement each read in flight was sent with, and what decides the
    /// next one: after a silent background tab, one read in a temporary window.
    private var workPlacements: [String: ClaudeSafariHostIPCProviderPlacement] = [:]
    private var placementPolicy = ClaudeSafariReadPlacementPolicy()
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

    /// Gemini reads report to their own handler; Claude's stays as it was.
    func startGemini(_ handler: @escaping @Sendable (GeminiBrowserInboundEvent) async -> Void) -> Bool {
        geminiConsumer = SafariBridgeOrderedConsumer(processor: handler)
        return listen()
    }

    /// Claude's side stops. The adapter is shared with Gemini reads, so the
    /// response listener and the Bridge turn-taking stay up while Gemini
    /// still listens; only Claude's reads and waits are let go.
    func stop() {
        consumer = nil
        guard geminiConsumer == nil else {
            forgetWork(of: .claude)
            resumeVerificationWaiters()
            return
        }
        stopAll()
    }

    /// Gemini's side stops; Claude's listener, if any, keeps running.
    func stopGemini() {
        geminiConsumer = nil
        guard consumer == nil else {
            forgetWork(of: .gemini)
            return
        }
        stopAll()
    }

    private func stopAll() {
        listener?.stop()
        listener = nil
        consumer = nil
        geminiConsumer = nil
        controlRequestIDs.removeAll()
        controlRequestIDOrder.removeAll()
        activeWorkRequestIDs.removeAll()
        workProviders.removeAll()
        focusReturnTargets.removeAll()
        workPlacements.removeAll()
        for waiter in idleWaiters.values { waiter.resume(returning: false) }
        idleWaiters.removeAll()
        readQueue = SafariBridgeReadQueue()
        resumeVerificationWaiters()
    }

    private func resumeVerificationWaiters() {
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

    /// Lets go of one provider's reads in flight and waiting, so they no
    /// longer hold the Bridge for the other provider.
    private func forgetWork(of provider: BrowserUsageProvider) {
        for (requestID, owner) in workProviders where owner == provider {
            finishWork(requestID)
        }
        for ticket in readQueue.waiting where ticket.provider == provider {
            abandonWait(ticket.id)
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

    func submit(
        requestID: String,
        oneShot: Bool,
        provider: BrowserUsageProvider = .claude
    ) async -> ClaudeBrowserAutomaticDispatchResult {
        let normalizedRequestID = requestID.lowercased()
        guard UUID(uuidString: normalizedRequestID) != nil, listen() else {
            return .workDispatchFailed
        }
        switch SafariBridgeReadQueue.admission(
            for: provider, activeProviders: Array(workProviders.values)
        ) {
        case .start: break
        case .refuse: return .workDispatchFailed
        case .wait:
            guard await waitForIdleBridge(provider) else { return .workDispatchFailed }
        }
        // Another read may have started while this one waited.
        guard activeWorkRequestIDs.isEmpty else { return .workDispatchFailed }
        guard await wakeHost() else {
            wakeNextWaitingRead()
            return .browserUnavailable
        }
        guard activeWorkRequestIDs.isEmpty else { return .workDispatchFailed }
        let operation: ClaudeSafariHostIPCOperation = oneShot ? .accuracySync : .automaticRefresh
        let placement = placementPolicy.placementForNextRead(
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
        workPlacements[normalizedRequestID] = placement
        workProviders[normalizedRequestID] = provider
        do {
            try client.submit(.init(
                requestID: normalizedRequestID,
                runtimeGenerationID: generation,
                operation: operation,
                allowSafariLaunch: oneShot,
                providerPlacement: placement,
                // Claude is the absent default, so its request is unchanged.
                provider: provider == .claude ? nil : provider
            ))
            return .dispatched
        } catch {
            activeWorkRequestIDs.remove(normalizedRequestID)
            focusReturnTargets.removeValue(forKey: normalizedRequestID)
            workPlacements.removeValue(forKey: normalizedRequestID)
            workProviders.removeValue(forKey: normalizedRequestID)
            wakeNextWaitingRead()
            return .workDispatchFailed
        }
    }

    /// Waits, bounded, until the other provider's read has finished.
    private func waitForIdleBridge(_ provider: BrowserUsageProvider) async -> Bool {
        let ticket = SafariBridgeReadQueue.Ticket(id: UUID(), provider: provider)
        guard readQueue.enqueue(ticket) else { return false }
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: Self.crossProviderWaitDeadline)
            await self?.abandonWait(ticket.id)
        }
        let granted = await withCheckedContinuation { continuation in
            idleWaiters[ticket.id] = continuation
        }
        deadline.cancel()
        return granted
    }

    private func abandonWait(_ id: UUID) {
        guard readQueue.remove(id) else { return }
        idleWaiters.removeValue(forKey: id)?.resume(returning: false)
    }

    private func wakeNextWaitingRead() {
        guard activeWorkRequestIDs.isEmpty, let ticket = readQueue.next() else { return }
        idleWaiters.removeValue(forKey: ticket.id)?.resume(returning: true)
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

    /// Records how a read ended before it is forgotten, so the next read's
    /// placement can follow it.
    private func finishWork(_ requestID: String, endedWith status: ClaudeBrowserAutomationStatus) {
        placementPolicy.readEnded(status, placement: workPlacements[requestID])
        finishWork(requestID)
    }

    @discardableResult
    private func finishWork(_ requestID: String) -> Bool {
        workPlacements.removeValue(forKey: requestID)
        workProviders.removeValue(forKey: requestID)
        let wasActive = activeWorkRequestIDs.remove(requestID) != nil
        if let target = focusReturnTargets.removeValue(forKey: requestID) {
            Self.returnFocus(to: target)
        }
        wakeNextWaitingRead()
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
                  workProviders[response.requestID] == .gemini {
            receiveGemini(response)
        } else if activeWorkRequestIDs.contains(response.requestID),
                  response.geminiObservation != nil {
            // A Gemini page result can never complete a Claude read.
            finishWork(response.requestID)
            consumer?.submit(.dispatchFailure(.protocolMismatch))
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
            finishWork(response.requestID, endedWith: event.status)
            consumer?.submit(.observation(.success(observation)))
            consumer?.submit(.automation(event))
        } else if activeWorkRequestIDs.contains(response.requestID),
                  let observation = response.observation {
            consumer?.submit(.observation(.success(observation)))
        } else if activeWorkRequestIDs.contains(response.requestID),
                  let event = response.automationEvent {
            finishWork(response.requestID, endedWith: event.status)
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

    /// The Gemini counterpart of the Claude routing above, with the same
    /// order: the observation reaches its consumer before the terminal event.
    private func receiveGemini(_ response: ClaudeSafariHostIPCResponse) {
        let requestID = response.requestID
        guard response.runtimeGenerationID == generation, response.observation == nil else {
            finishWork(requestID)
            geminiConsumer?.submit(.dispatchFailure(.protocolMismatch))
            return
        }
        if response.outcome == .completed,
           let observation = response.geminiObservation,
           let event = response.automationEvent {
            finishWork(requestID, endedWith: event.status)
            geminiConsumer?.submit(.observation(observation))
            geminiConsumer?.submit(.automation(event))
        } else if let event = response.automationEvent {
            finishWork(requestID, endedWith: event.status)
            geminiConsumer?.submit(.automation(event))
        } else if response.outcome == .failed {
            finishWork(requestID)
            geminiConsumer?.submit(Self.inboundFailure(response))
        }
    }

    private static func inboundFailure(
        _ response: ClaudeSafariHostIPCResponse
    ) -> GeminiBrowserInboundEvent {
        switch response.failureReason {
        case .protocolMismatch, .runtimeGenerationMismatch:
            return .dispatchFailure(.protocolMismatch)
        case .safariUnavailable:
            return .dispatchFailure(.browserUnavailable)
        case .extensionUnavailable, .dispatchRejected,
             .dispatchCompletionUnavailable, .nativeResponseUnavailable,
             .extensionBackgroundNotAcknowledged:
            return .dispatchFailure(.companionUnavailable)
        default:
            return .automation(.init(
                requestID: response.requestID,
                status: .usageUnavailable,
                occurredAt: response.occurredAt
            ))
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
