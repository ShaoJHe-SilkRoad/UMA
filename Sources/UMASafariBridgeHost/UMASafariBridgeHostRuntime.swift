import AppKit
import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import ClaudeSafariHostIPC
import Foundation
import OSLog
import SafariServices

struct UMASafariBridgeHostRuntimeContext: Equatable, Sendable {
    let runtimeGenerationID: String
    let containingApplicationIdentifier: String
    let extensionIdentifier: String
    let teamIdentifier: String
    let version: String
    let build: String
    let appGroupIdentifier: String

    var ipcDescriptor: ClaudeSafariHostIPCRuntimeDescriptor {
        .init(
            hostApplicationIdentifier: containingApplicationIdentifier,
            extensionIdentifier: extensionIdentifier,
            teamIdentifier: teamIdentifier,
            hostVersion: version,
            hostBuild: build,
            runtimeGenerationID: runtimeGenerationID,
            bridgeProtocolVersion: ClaudeBrowserBridgeContract.schemaVersion
        )
    }

    static func current(bundle: Bundle = .main) -> Self? {
        guard let channelRaw = bundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.runtimeChannelInfoKey
              ) as? String,
              let channel = ClaudeBrowserRuntimeChannel(rawValue: channelRaw),
              let profile = ClaudeSafariHostRuntimeProfile.matchingRuntimeChannel(channel),
              bundle.bundleIdentifier == profile.identity.containingApplicationIdentifier,
              let generation = bundle.object(
                forInfoDictionaryKey:
                    ClaudeBrowserBridgeContract.runtimeGenerationInfoKey
              ) as? String,
              UUID(uuidString: generation) != nil,
              bundle.object(
                forInfoDictionaryKey:
                    ClaudeBrowserBridgeContract.containingApplicationInfoKey
              ) as? String == profile.identity.containingApplicationIdentifier,
              bundle.object(
                forInfoDictionaryKey:
                    ClaudeBrowserBridgeContract.extensionIdentifierInfoKey
              ) as? String == profile.identity.extensionIdentifier,
              bundle.object(
                forInfoDictionaryKey:
                    ClaudeBrowserBridgeContract.appGroupIdentifierInfoKey
              ) as? String == profile.appGroupIdentifier,
              let team = bundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.teamIdentifierInfoKey
              ) as? String,
              team == ClaudeBrowserBridgeContract.expectedTeamIdentifier,
              let version = bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
              ) as? String,
              !version.isEmpty,
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty,
              build.allSatisfy(\.isNumber)
        else { return nil }
        return Self(
            runtimeGenerationID: generation.lowercased(),
            containingApplicationIdentifier: profile.identity.containingApplicationIdentifier,
            extensionIdentifier: profile.identity.extensionIdentifier,
            teamIdentifier: team,
            version: version,
            build: build,
            appGroupIdentifier: profile.appGroupIdentifier
        )
    }
}

private enum UMASafariBridgeHostPendingPhase: Equatable, Sendable {
    case awaitingBackgroundReady
    case qualificationDispatched
    case workDispatched
    case providerWorkStarted
    case observationBuffered
    case awaitingObservationAfterCompletion
    case cleanupDispatched
}

private struct UMASafariBridgeHostPendingRequest: Sendable {
    let request: ClaudeSafariHostIPCRequest
    var phase: UMASafariBridgeHostPendingPhase
    var observation: ClaudeBrowserObservationEnvelope?
    var completionEvent: ClaudeBrowserAutomationEvent?
    var deadlineToken: UUID
    var verificationStage: ClaudeSafariHostIPCVerificationStage
    var bufferedBackgroundReady: ClaudeBrowserAutomationEvent?
    var bufferedQualificationEvents: [ClaudeBrowserAutomationEvent]
}

actor UMASafariBridgeHostCoordinator {
    /// Deadlines bound explicit lifecycle phases. They are not used as
    /// synchronization; each successful acknowledgement advances the phase and
    /// replaces the preceding deadline.
    private static let backgroundAcknowledgementDeadline: Duration = .seconds(10)
    private static let dispatchCompletionDeadline: Duration = .seconds(5)
    private static let safariLaunchReadinessDeadline: Duration = .seconds(5)
    private static let nativeQualificationDeadline: Duration = .seconds(10)
    private static let providerOperationDeadline: Duration = .seconds(35)
    private static let causalJoinDeadline: Duration = .seconds(2)
    private static let cleanupAcknowledgementDeadline: Duration = .seconds(10)

    private let runtime: UMASafariBridgeHostRuntimeContext
    private let responder: ClaudeSafariHostIPCResponder
    private var pending: [String: UMASafariBridgeHostPendingRequest] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private struct CleanupCommand: Sendable {
        let targetRequestID: String
        let terminalReason: ClaudeSafariHostIPCFailureReason
        let respondsToClient: Bool
    }
    private var cleanupCommands: [String: CleanupCommand] = [:]

    init(
        runtime: UMASafariBridgeHostRuntimeContext,
        responder: ClaudeSafariHostIPCResponder
    ) {
        self.runtime = runtime
        self.responder = responder
    }

    func receive(_ request: ClaudeSafariHostIPCRequest) async {
        guard request.isStructurallyValid else {
            sendFailure(request: request, reason: .invalidRequest)
            return
        }
        guard request.runtimeGenerationID == runtime.runtimeGenerationID else {
            sendFailure(request: request, reason: .runtimeGenerationMismatch)
            return
        }
        guard pending[request.requestID] == nil else {
            sendFailure(request: request, reason: .duplicateRequest)
            return
        }

        if request.operation == .closeOwnedTab {
            guard let targetRequestID = request.targetRequestID,
                  pending[targetRequestID] != nil,
                  pending.count == 1
            else {
                sendFailure(request: request, reason: .cancellationTargetUnavailable)
                return
            }
            await beginCleanup(
                targetRequestID: targetRequestID,
                commandID: request.requestID,
                terminalReason: .cancelled,
                respondsToClient: true
            )
            return
        } else if !pending.isEmpty {
            sendFailure(request: request, reason: .requestInFlight)
            return
        }

        await begin(request)
    }

    private func begin(_ request: ClaudeSafariHostIPCRequest) async {
        pending[request.requestID] = UMASafariBridgeHostPendingRequest(
            request: request,
            phase: .awaitingBackgroundReady,
            observation: nil,
            completionEvent: nil,
            deadlineToken: UUID(),
            verificationStage: .hostRequestAccepted,
            bufferedBackgroundReady: nil,
            bufferedQualificationEvents: []
        )
        // Establish Safari's application lifecycle before interpreting a
        // dispatch callback as a wake attempt. When launch is explicitly
        // permitted, the matching NSWorkspace launch event is the readiness
        // boundary; no delay, retry, Settings window, or provider page participates.
        guard await Self.prepareSafari(allowLaunch: request.allowSafariLaunch) else {
            completeFailure(requestID: request.requestID, reason: .safariUnavailable)
            return
        }
        guard pending[request.requestID] != nil else { return }
        armDeadline(
            requestID: request.requestID,
            duration: Self.backgroundAcknowledgementDeadline,
            failureReason: .extensionBackgroundNotAcknowledged
        )

        let dispatchResult = await Self.dispatch(
            name: ClaudeBrowserBridgeContract.wakeBridgeMessageName,
            requestID: request.requestID,
            targetRequestID: nil,
            extensionIdentifier: runtime.extensionIdentifier
        )
        switch dispatchResult {
        case .rejected:
            completeFailure(requestID: request.requestID, reason: .dispatchRejected)
        case .deadlineExpired:
            completeFailure(
                requestID: request.requestID,
                reason: .dispatchCompletionUnavailable
            )
        case .accepted:
            advanceVerificationStage(
                requestID: request.requestID,
                to: .wakeDispatchAccepted
            )
            if let buffered = pending[request.requestID]?.bufferedBackgroundReady {
                pending[request.requestID]?.bufferedBackgroundReady = nil
                await receive(buffered)
            }
        }
    }

    func receive(_ observation: ClaudeBrowserObservationEnvelope) {
        let requestID = observation.requestID.lowercased()
        guard var item = pending[requestID],
              [.workDispatched, .providerWorkStarted, .observationBuffered,
               .awaitingObservationAfterCompletion].contains(item.phase),
              item.request.operation == .accuracySync
                || item.request.operation == .automaticRefresh
        else { return }
        guard item.observation == nil else {
            completeFailure(requestID: requestID, reason: .duplicateNativeResponse)
            return
        }
        item.observation = observation
        if let completionEvent = item.completionEvent {
            pending[requestID] = item
            completeSuccess(
                requestID: requestID,
                observation: observation,
                event: completionEvent
            )
        } else {
            item.phase = .observationBuffered
            pending[requestID] = item
        }
    }

    func receive(_ event: ClaudeBrowserAutomationEvent) async {
        let requestID = event.requestID.lowercased()

        if event.status == .extensionBackgroundReady {
            // A warm background echoes the pending request ID. A cold
            // background cannot have observed the wake payload sent before its
            // port listener existed, so its signed startup receipt may advance
            // the sole waiting request. Qualification remains correlated.
            let candidate = pending[requestID]?.phase == .awaitingBackgroundReady
                ? requestID
                : pending.first(where: { $0.value.phase == .awaitingBackgroundReady })?.key
            guard let candidate else { return }
            guard runtimeIdentityMatches(event) else {
                completeFailure(requestID: candidate, reason: .runtimeGenerationMismatch)
                return
            }
            if pending[candidate]?.verificationStage == .hostRequestAccepted {
                // The extension may acknowledge before Safari invokes the
                // dispatch completion callback. Buffer the signed event rather
                // than dropping it or advancing across an unproved stage.
                pending[candidate]?.bufferedBackgroundReady = event
                return
            }
            advanceVerificationStage(
                requestID: candidate,
                to: .extensionBackgroundAcknowledged
            )
            await dispatchQualification(requestID: candidate)
            return
        }

        guard var item = pending[requestID] else { return }

        let qualificationStatuses: Set<ClaudeBrowserAutomationStatus> = [
            .nativeHandlerEntered, .nativeRequestDecoded,
            .runtimeGenerationValidated, .nativeResponseCreated,
            .nativeResponseSent, .extensionResponseReceived, .bridgeReady,
        ]
        if item.phase == .qualificationDispatched,
           item.verificationStage == .extensionBackgroundAcknowledged,
           qualificationStatuses.contains(event.status) {
            guard runtimeIdentityMatches(event),
                  item.bufferedQualificationEvents.count < 8
            else {
                completeFailure(requestID: requestID, reason: .unexpectedNativeResponse)
                return
            }
            item.bufferedQualificationEvents.append(event)
            pending[requestID] = item
            return
        }

        let diagnosticStage: ClaudeSafariHostIPCVerificationStage?
        switch event.status {
        case .nativeHandlerEntered: diagnosticStage = .nativeHandlerEntered
        case .nativeRequestDecoded: diagnosticStage = .nativeRequestDecoded
        case .runtimeGenerationValidated: diagnosticStage = .runtimeGenerationValidated
        case .nativeResponseCreated: diagnosticStage = .nativeResponseCreated
        case .nativeResponseSent: diagnosticStage = .nativeResponseSent
        case .extensionResponseReceived: diagnosticStage = .extensionResponseReceived
        default: diagnosticStage = nil
        }
        if let diagnosticStage {
            guard item.phase == .qualificationDispatched else {
                completeFailure(requestID: requestID, reason: .unexpectedNativeResponse)
                return
            }
            guard runtimeIdentityMatches(event) else {
                completeFailure(requestID: requestID, reason: .runtimeGenerationMismatch)
                return
            }
            advanceVerificationStage(requestID: requestID, to: diagnosticStage)
            return
        }

        if event.status == .bridgeReady {
            guard item.verificationStage == .extensionResponseReceived else {
                completeFailure(requestID: requestID, reason: .unexpectedNativeResponse)
                return
            }
            advanceVerificationStage(
                requestID: requestID,
                to: .nativeQualificationReceived
            )
            // The actor yielded while native qualification was in flight.
            // Reload the authoritative item so writing the next phase cannot
            // restore an older verification stage.
            guard var item = pending[requestID] else { return }
            guard runtimeIdentityMatches(event) else {
                completeFailure(requestID: requestID, reason: .runtimeGenerationMismatch)
                return
            }
            guard item.phase == .qualificationDispatched else {
                completeFailure(requestID: requestID, reason: .unexpectedNativeResponse)
                return
            }
            if item.request.operation == .verifyCompanion {
                complete(
                    ClaudeSafariHostIPCResponse(
                        requestID: requestID,
                        runtimeGenerationID: runtime.runtimeGenerationID,
                        outcome: .companionVerified,
                        verificationStage: .companionVerified,
                        runtimeDescriptor: runtime.ipcDescriptor
                    )
                )
                return
            }

            item.phase = .workDispatched
            pending[requestID] = item
            armDeadline(
                requestID: requestID,
                duration: Self.providerOperationDeadline,
                failureReason: .providerOperationTimedOut
            )
            let messageName = item.request.operation == .closeOwnedTab
                ? ClaudeBrowserBridgeContract.closeOwnedTabMessageName
                : ClaudeBrowserBridgeContract.automaticRefreshMessageName
            let dispatchResult = await Self.dispatch(
                name: messageName,
                requestID: requestID,
                targetRequestID: item.request.targetRequestID,
                providerPlacement: item.request.providerPlacement,
                extensionIdentifier: runtime.extensionIdentifier
            )
            switch dispatchResult {
            case .rejected:
                completeFailure(requestID: requestID, reason: .dispatchRejected)
            case .deadlineExpired:
                completeFailure(
                    requestID: requestID,
                    reason: .dispatchCompletionUnavailable
                )
            case .accepted:
                break
            }
            return
        }

        switch event.status {
        case .extensionBackgroundReady, .nativeHandlerEntered,
             .nativeRequestDecoded, .runtimeGenerationValidated,
             .nativeResponseCreated, .nativeResponseSent,
             .extensionResponseReceived, .bridgeReady:
            return
        case .refreshStarted:
            guard item.phase == .workDispatched
                    || item.phase == .providerWorkStarted
                    || item.phase == .observationBuffered
            else {
                completeFailure(requestID: requestID, reason: .unexpectedNativeResponse)
                return
            }
            if item.phase == .workDispatched {
                item.phase = .providerWorkStarted
                pending[requestID] = item
            }
        case .refreshCompleted:
            guard item.request.operation == .accuracySync
                    || item.request.operation == .automaticRefresh,
                  item.completionEvent == nil,
                  [.workDispatched, .providerWorkStarted, .observationBuffered]
                    .contains(item.phase)
            else {
                completeFailure(requestID: requestID, reason: .duplicateNativeResponse)
                return
            }
            if let observation = item.observation {
                completeSuccess(
                    requestID: requestID,
                    observation: observation,
                    event: event
                )
            } else {
                item.completionEvent = event
                item.phase = .awaitingObservationAfterCompletion
                pending[requestID] = item
                armDeadline(
                    requestID: requestID,
                    duration: Self.causalJoinDeadline,
                    failureReason: .observationMissing
                )
            }
        case .permissionRequired, .signInRequired, .routeRejected,
             .browserUnavailable,
             .usageUnavailable, .tabUnavailable, .ownedTabClosed,
             .ownedTabOwnershipLost:
            guard [.workDispatched, .providerWorkStarted, .observationBuffered]
                    .contains(item.phase)
            else {
                completeFailure(requestID: requestID, reason: .unexpectedNativeResponse)
                return
            }
            complete(
                ClaudeSafariHostIPCResponse(
                    requestID: requestID,
                    runtimeGenerationID: runtime.runtimeGenerationID,
                    outcome: .automation,
                    automationEvent: event
                )
            )
        }
    }

    private func dispatchQualification(requestID: String) async {
        guard var item = pending[requestID],
              item.phase == .awaitingBackgroundReady
        else { return }
        item.phase = .qualificationDispatched
        pending[requestID] = item
        armDeadline(
            requestID: requestID,
            duration: Self.nativeQualificationDeadline,
            failureReason: .nativeResponseUnavailable
        )
        let dispatchResult = await Self.dispatch(
            name: ClaudeBrowserBridgeContract.runtimeQualificationMessageName,
            requestID: requestID,
            targetRequestID: nil,
            extensionIdentifier: runtime.extensionIdentifier
        )
        switch dispatchResult {
        case .rejected:
            completeFailure(requestID: requestID, reason: .dispatchRejected)
        case .deadlineExpired:
            completeFailure(
                requestID: requestID,
                reason: .dispatchCompletionUnavailable
            )
        case .accepted:
            advanceVerificationStage(
                requestID: requestID,
                to: .nativeQualificationDispatched
            )
            let buffered = pending[requestID]?.bufferedQualificationEvents ?? []
            pending[requestID]?.bufferedQualificationEvents.removeAll()
            for event in buffered {
                await receive(event)
            }
        }
    }

    private func advanceVerificationStage(
        requestID: String,
        to stage: ClaudeSafariHostIPCVerificationStage
    ) {
        guard var item = pending[requestID] else { return }
        let stages = ClaudeSafariHostIPCVerificationStage.allCases
        guard let current = stages.firstIndex(of: item.verificationStage),
              let proposed = stages.firstIndex(of: stage),
              proposed == current + 1
        else { return }
        item.verificationStage = stage
        pending[requestID] = item
    }

    private func runtimeIdentityMatches(
        _ event: ClaudeBrowserAutomationEvent
    ) -> Bool {
        event.runtimeGenerationID?.lowercased() == runtime.runtimeGenerationID
            && event.containingApplicationIdentifier
                == runtime.containingApplicationIdentifier
            && event.extensionIdentifier == runtime.extensionIdentifier
            && event.teamIdentifier == runtime.teamIdentifier
            && event.protocolSchemaVersion == ClaudeBrowserBridgeContract.schemaVersion
    }

    func receiveProtocolMismatch(requestID: String) {
        completeFailure(
            requestID: requestID.lowercased(),
            reason: .protocolMismatch
        )
    }

    func receive(_ terminal: ClaudeBrowserTerminalPacket) {
        let requestID = terminal.requestID.lowercased()
        guard terminal.runtimeGenerationID.lowercased() == runtime.runtimeGenerationID
        else {
            if let target = terminal.targetRequestID?.lowercased() {
                completeFailure(requestID: target, reason: .runtimeGenerationMismatch)
            } else {
                completeFailure(requestID: requestID, reason: .runtimeGenerationMismatch)
            }
            return
        }

        if let targetRequestID = terminal.targetRequestID?.lowercased() {
            guard let cleanup = cleanupCommands[requestID],
                  cleanup.targetRequestID == targetRequestID,
                  pending[targetRequestID]?.phase == .cleanupDispatched,
                  terminal.status == .ownedTabClosed
                    || terminal.status == .ownedTabOwnershipLost
            else { return }
            cleanupCommands.removeValue(forKey: requestID)
            completeFailure(
                requestID: targetRequestID,
                reason: terminal.status == .ownedTabClosed
                    ? cleanup.terminalReason : .cancellationTargetUnavailable
            )
            if cleanup.respondsToClient {
                let event = ClaudeBrowserAutomationEvent(
                    requestID: requestID,
                    status: terminal.status,
                    occurredAt: terminal.occurredAt
                )
                try? responder.send(.init(
                    requestID: requestID,
                    runtimeGenerationID: runtime.runtimeGenerationID,
                    outcome: .automation,
                    automationEvent: event,
                    runtimeDescriptor: runtime.ipcDescriptor
                ))
            }
            return
        }

        guard let item = pending[requestID],
              item.phase != .cleanupDispatched,
              item.request.operation == .accuracySync
                || item.request.operation == .automaticRefresh
        else { return }
        if terminal.status == .refreshCompleted,
           let observation = terminal.observation {
            completeSuccess(
                requestID: requestID,
                observation: observation,
                event: .init(
                    requestID: requestID,
                    status: .refreshCompleted,
                    occurredAt: terminal.occurredAt
                )
            )
        } else {
            complete(.init(
                requestID: requestID,
                runtimeGenerationID: runtime.runtimeGenerationID,
                outcome: .automation,
                automationEvent: .init(
                    requestID: requestID,
                    status: terminal.status,
                    occurredAt: terminal.occurredAt
                ),
                providerFailureReason: terminal.providerFailureReason,
                runtimeDescriptor: runtime.ipcDescriptor
            ))
        }
    }

    private func armDeadline(
        requestID: String,
        duration: Duration,
        failureReason: ClaudeSafariHostIPCFailureReason
    ) {
        guard var item = pending[requestID] else { return }
        let token = UUID()
        item.deadlineToken = token
        pending[requestID] = item
        timeoutTasks.removeValue(forKey: requestID)?.cancel()
        timeoutTasks[requestID] = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await self?.timeout(
                requestID: requestID,
                deadlineToken: token,
                reason: failureReason
            )
        }
    }

    private func timeout(
        requestID: String,
        deadlineToken: UUID,
        reason: ClaudeSafariHostIPCFailureReason
    ) async {
        guard pending[requestID]?.deadlineToken == deadlineToken else { return }
        if reason == .providerOperationTimedOut || reason == .observationMissing {
            await beginCleanup(
                targetRequestID: requestID,
                commandID: UUID().uuidString.lowercased(),
                terminalReason: reason,
                respondsToClient: false
            )
            return
        }
        completeFailure(requestID: requestID, reason: reason)
    }

    private func beginCleanup(
        targetRequestID: String,
        commandID: String,
        terminalReason: ClaudeSafariHostIPCFailureReason,
        respondsToClient: Bool
    ) async {
        guard var item = pending[targetRequestID],
              item.phase != .cleanupDispatched,
              cleanupCommands[commandID] == nil
        else { return }
        item.phase = .cleanupDispatched
        pending[targetRequestID] = item
        cleanupCommands[commandID] = .init(
            targetRequestID: targetRequestID,
            terminalReason: terminalReason,
            respondsToClient: respondsToClient
        )
        armDeadline(
            requestID: targetRequestID,
            duration: Self.cleanupAcknowledgementDeadline,
            failureReason: .cancellationTargetUnavailable
        )
        let dispatchResult = await Self.dispatch(
            name: ClaudeBrowserBridgeContract.closeOwnedTabMessageName,
            requestID: commandID,
            targetRequestID: targetRequestID,
            extensionIdentifier: runtime.extensionIdentifier
        )
        switch dispatchResult {
        case .rejected:
            cleanupCommands.removeValue(forKey: commandID)
            completeFailure(requestID: targetRequestID, reason: .dispatchRejected)
        case .deadlineExpired:
            cleanupCommands.removeValue(forKey: commandID)
            completeFailure(
                requestID: targetRequestID,
                reason: .dispatchCompletionUnavailable
            )
        case .accepted:
            break
        }
    }

    private func completeSuccess(
        requestID: String,
        observation: ClaudeBrowserObservationEnvelope,
        event: ClaudeBrowserAutomationEvent
    ) {
        complete(
            ClaudeSafariHostIPCResponse(
                requestID: requestID,
                runtimeGenerationID: runtime.runtimeGenerationID,
                outcome: .completed,
                observation: observation,
                automationEvent: event,
                runtimeDescriptor: runtime.ipcDescriptor
            )
        )
    }

    private func completeFailure(
        requestID: String,
        reason: ClaudeSafariHostIPCFailureReason
    ) {
        guard let item = pending[requestID] else { return }
        complete(
            ClaudeSafariHostIPCResponse(
                requestID: item.request.requestID,
                runtimeGenerationID: runtime.runtimeGenerationID,
                outcome: .failed,
                failureReason: reason,
                verificationStage: item.verificationStage,
                runtimeDescriptor: runtime.ipcDescriptor
            )
        )
    }

    private func sendFailure(
        request: ClaudeSafariHostIPCRequest,
        reason: ClaudeSafariHostIPCFailureReason
    ) {
        guard UUID(uuidString: request.requestID) != nil else { return }
        try? responder.send(
            ClaudeSafariHostIPCResponse(
                requestID: request.requestID,
                runtimeGenerationID: runtime.runtimeGenerationID,
                outcome: .failed,
                failureReason: reason,
                runtimeDescriptor: runtime.ipcDescriptor
            )
        )
    }

    @discardableResult
    private func complete(_ response: ClaudeSafariHostIPCResponse) -> Bool {
        guard pending[response.requestID] != nil else { return false }
        do {
            // Keep the request authoritative until its terminal file is
            // durably published. A full mailbox must not silently erase the
            // only completion state.
            try responder.send(response)
        } catch {
            return false
        }
        pending.removeValue(forKey: response.requestID)
        timeoutTasks.removeValue(forKey: response.requestID)?.cancel()
        cleanupCommands = cleanupCommands.filter {
            $0.value.targetRequestID != response.requestID
        }
        return true
    }

    @MainActor
    private static func prepareSafari(allowLaunch: Bool) async -> Bool {
        let safariIdentifier = "com.apple.Safari"
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: safariIdentifier
        ).filter { !$0.isTerminated }
        let decision = ClaudeSafariHostColdStartPolicy.action(
            safariProcessPresent: !running.isEmpty,
            safariFinishedLaunching: running.contains(where: \.isFinishedLaunching),
            allowSafariLaunch: allowLaunch
        )
        switch decision {
        case .dispatch:
            return true
        case .failSafariUnavailable:
            return false
        case .launchSafari:
            let gate = ClaudeSafariHostApplicationReadinessGate()
            let center = NSWorkspace.shared.notificationCenter
            let observer = center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let application = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication,
                      ClaudeSafariHostColdStartPolicy.launchEventMatches(
                        expectedBundleIdentifier: safariIdentifier,
                        observedBundleIdentifier: application.bundleIdentifier,
                        applicationTerminated: application.isTerminated
                      )
                else { return }
                gate.resolve(.ready)
            }

            // Close the observer-registration race before deciding whether a
            // launch request is needed. A still-launching Safari is allowed to
            // finish through the matching workspace event.
            let afterObserver = NSRunningApplication.runningApplications(
                withBundleIdentifier: safariIdentifier
            ).filter { !$0.isTerminated }
            if afterObserver.contains(where: \.isFinishedLaunching) {
                gate.resolve(.ready)
            } else if afterObserver.isEmpty {
                guard let url = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: safariIdentifier
                ) else {
                    center.removeObserver(observer)
                    return false
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.addsToRecentItems = false
                configuration.promptsUserIfNeeded = false
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: configuration
                ) { application, error in
                    switch ClaudeSafariHostColdStartPolicy.openCallbackAction(
                        applicationPresent: application != nil,
                        applicationTerminated: application?.isTerminated ?? true,
                        applicationFinishedLaunching:
                            application?.isFinishedLaunching ?? false,
                        errorPresent: error != nil
                    ) {
                    case .ready:
                        gate.resolve(.ready)
                    case .waitForLaunchEvent:
                        break
                    case .unavailable:
                        gate.resolve(.unavailable)
                    }
                }
            }

            let deadline = Task {
                do {
                    try await Task.sleep(for: safariLaunchReadinessDeadline)
                    gate.resolve(.deadlineExpired)
                } catch {
                    // A real launch event or terminal callback won first.
                }
            }
            let result = await gate.wait()
            deadline.cancel()
            center.removeObserver(observer)
            return result == .ready
        }
    }

    @MainActor
    private static func dispatch(
        name: String,
        requestID: String,
        targetRequestID: String?,
        providerPlacement: ClaudeSafariHostIPCProviderPlacement? = nil,
        extensionIdentifier: String
    ) async -> ClaudeSafariHostDispatchCompletion {
        let gate = ClaudeSafariHostDispatchCompletionGate()
        let deadline = Task {
            do {
                try await Task.sleep(for: dispatchCompletionDeadline)
                gate.resolve(.deadlineExpired)
            } catch {
                // The real callback completed first and cancelled this bound.
            }
        }
        var userInfo = ["command": name, "requestID": requestID]
        if let targetRequestID { userInfo["targetRequestID"] = targetRequestID }
        if name == ClaudeBrowserBridgeContract.automaticRefreshMessageName,
           let providerPlacement {
            userInfo["placement"] = providerPlacement.rawValue
        }
        SFSafariApplication.dispatchMessage(
            withName: name,
            toExtensionWithIdentifier: extensionIdentifier,
            userInfo: userInfo
        ) { error in
            gate.resolve(error == nil ? .accepted : .rejected)
        }
        let result = await withTaskCancellationHandler {
            await gate.wait()
        } onCancel: {
            gate.resolve(.deadlineExpired)
        }
        deadline.cancel()
        return result
    }
}

@MainActor
final class UMASafariBridgeHostApplicationDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: "com.silkrd.uma.safarihost.runtime",
        category: "Host"
    )
    private var requestServer: ClaudeSafariHostIPCRequestServer?
    private var nativeServer: ClaudeBrowserFileHandoffServer?
    private var coordinator: UMASafariBridgeHostCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let runtime = UMASafariBridgeHostRuntimeContext.current(),
              let endpoint = try? ClaudeSafariHostIPCEndpoint.appGroup(
                identifier: runtime.appGroupIdentifier
              )
        else {
            logger.error("Safari Host startup rejected: signed-runtime-or-app-group")
            NSApplication.shared.terminate(nil)
            return
        }

        let nextCoordinator = UMASafariBridgeHostCoordinator(
            runtime: runtime,
            responder: ClaudeSafariHostIPCResponder(endpoint: endpoint)
        )
        let nextNativeServer = ClaudeBrowserFileHandoffServer(
            endpoint: .safariHostAppGroup(
                containerDirectoryPath: URL(fileURLWithPath: endpoint.rootDirectoryPath)
                    .deletingLastPathComponent().path
            ),
            observationHandler: { observation in
                Task { await nextCoordinator.receive(observation) }
            },
            automationHandler: { event in
                Task { await nextCoordinator.receive(event) }
            },
            automationRejectionHandler: { rejection in
                Task {
                    await nextCoordinator.receiveProtocolMismatch(
                        requestID: rejection.requestID
                    )
                }
            },
            terminalHandler: { terminal in
                Task { await nextCoordinator.receive(terminal) }
            }
        )
        let nextRequestServer = ClaudeSafariHostIPCRequestServer(
            endpoint: endpoint
        ) { request in
            Task { await nextCoordinator.receive(request) }
        }
        do {
            // The native callback authority is established before cold-start
            // requests are drained, so Safari can never reply into a missing
            // Host listener.
            let containerPath = URL(fileURLWithPath: endpoint.rootDirectoryPath)
                .deletingLastPathComponent().path
            try endpoint.prepareOwnerOnlyRoot()
            try ClaudeBrowserOwnedTabReceiptStore.prepare(
                endpoint: .safariHostOwnedTab(
                    containerDirectoryPath: containerPath
                )
            )
            try nextNativeServer.start()
            try nextRequestServer.start()
        } catch {
            nextNativeServer.stop()
            nextRequestServer.stop()
            logger.error("Safari Host startup rejected: bounded-listener")
            NSApplication.shared.terminate(nil)
            return
        }
        coordinator = nextCoordinator
        nativeServer = nextNativeServer
        requestServer = nextRequestServer
        logger.notice("Safari Host ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        requestServer?.stop()
        nativeServer?.stop()
    }
}
