import Foundation

enum ProviderEligibilityScanTrigger: String, CaseIterable, Hashable, Sendable {
    case applicationLaunch
    case manualSearch
    case manualRefresh
    case checkAgain
    case syncNow
}

struct LocalLiveProviderSnapshot: Sendable, Equatable {
    let snapshot: AgentUsageSnapshot
}

enum ProviderSurfaceAdmission: Sendable, Equatable {
    case admitted(LocalLiveProviderSnapshot)
    case hiddenNotRunning
    case hiddenNotAuthenticated
    case hiddenNoAdmittedLocalSource
    case hiddenCurrentReadFailed
    case hiddenUnsupported

    var admittedSnapshot: AgentUsageSnapshot? {
        guard case let .admitted(value) = self else { return nil }
        return value.snapshot
    }
}

struct ProviderSurfaceAdmissionRecord: Sendable, Equatable, Identifiable {
    let id: AgentConnectorID
    let providerName: String
    let priority: Int
    let admission: ProviderSurfaceAdmission
    let loginOption: ProviderLoginOption?
    /// Closed error classification only; failed reads never become quota cards.
    var safeFailure: AgentSafeFailure? = nil
}

struct ProviderLoginOption: Sendable, Equatable, Identifiable {
    let id: AgentConnectorID
    let providerName: String
    let officialApplicationURL: URL
}

struct ProviderSurfaceAdmissionSet: Sendable, Equatable {
    let trigger: ProviderEligibilityScanTrigger
    let scanGeneration: UInt64
    let records: [ProviderSurfaceAdmissionRecord]

    var admittedSnapshots: [AgentUsageSnapshot] {
        records.compactMap(\.admission.admittedSnapshot)
    }

    var admittedProviderIDs: [AgentConnectorID] {
        admittedSnapshots.map(\.id)
    }

    var loginOptions: [ProviderLoginOption] {
        records.compactMap(\.loginOption)
    }

    /// A provider becomes known only after a bounded registered-provider scan
    /// either reads current admissible data or proves that authentication is
    /// the sole remaining blocker. Other hidden states are not detection.
    var safelyDetectedProviderIDs: [AgentConnectorID] {
        records.compactMap { record in
            switch record.admission {
            case .admitted, .hiddenNotAuthenticated:
                record.id
            case .hiddenNotRunning,
                 .hiddenNoAdmittedLocalSource,
                 .hiddenCurrentReadFailed,
                 .hiddenUnsupported:
                nil
            }
        }
    }
}

struct RegisteredProviderCandidate: Sendable {
    let connector: any AgentUsageConnector
    let descriptor: AgentConnectorDescriptor
}

struct LocalProviderEligibilityScannerDiagnostics: Sendable, Equatable {
    let completedScanCount: Int
    let coalescedRequestCount: Int
    let countsByTrigger: [ProviderEligibilityScanTrigger: Int]
    let activeGeneration: UInt64?
}

/// One provider-neutral admission contract shared by discovery and every
/// product surface. Claude's explicitly authorized local estimate is the only
/// non-provider-reported account provenance admitted here; it remains visibly
/// estimated and must still contain bounded, validated quota windows.
enum ProviderUsageSurfacePolicy {
    static func permitsRetainedValue(
        snapshot: AgentUsageSnapshot,
        capabilities: Set<AgentConnectorCapability>
    ) -> Bool {
        capabilities.contains(.sanitizedLastValidRestore)
            || isAuthorizedClaudeEstimate(snapshot)
    }

    static func hasAdmissibleAccountProvenance(
        snapshot: AgentUsageSnapshot,
        account: AgentUsageChannel
    ) -> Bool {
        account.provenance == .providerReported
            || (snapshot.id == ClaudeCodeUsageConnector.connectorID
                && account.provenance == .locallyEstimated
                && account.rateLimitWindows.contains(where: { $0.isEstimated == true }))
    }

    static func validatesUsage(_ channel: AgentUsageChannel) -> Bool {
        if channel.availabilitySourceState == .officialStructured
            || channel.availabilitySourceState == .authenticatedAccountWeb {
            return true
        }
        if channel.rateLimitWindows.isEmpty {
            return channel.accountMetrics != nil
        }
        return channel.rateLimitWindows.allSatisfy { window in
            if window.isUnlimited { return true }
            return window.normalizedRemainingPercent != nil
        }
    }

    static func isAdmissibleRetainedFailure(
        _ failure: AgentSafeFailure?,
        providerID: AgentConnectorID
    ) -> Bool {
        switch failure {
        case nil, .unavailable, .timedOut, .malformedResponse:
            true
        case .processExited:
            providerID == CodexUsageConnector.connectorID
        default:
            false
        }
    }

    private static func isAuthorizedClaudeEstimate(
        _ snapshot: AgentUsageSnapshot
    ) -> Bool {
        guard snapshot.id == ClaudeCodeUsageConnector.connectorID,
              let account = snapshot.channels.first(where: { $0.id == .account })
        else { return false }
        return account.sourceTier == .authorizedLocalEstimate
            && account.provenance == .locallyEstimated
            && !account.rateLimitWindows.isEmpty
            && account.rateLimitWindows.allSatisfy { $0.isEstimated == true }
    }
}

/// The one provider-neutral discovery owner. It scans only registered
/// descriptors, coalesces concurrent requests, and produces the sole admitted
/// provider set consumed by both product surfaces.
actor LocalProviderEligibilityScanner {
    private struct ActiveScan {
        let generation: UInt64
        let task: Task<ProviderSurfaceAdmissionSet, Never>
    }

    private let onRequestCoalesced: @Sendable () -> Void

    init(onRequestCoalesced: @escaping @Sendable () -> Void = {}) {
        self.onRequestCoalesced = onRequestCoalesced
    }

    private var active: ActiveScan?
    private var nextGeneration: UInt64 = 0
    private var completedScanCount = 0
    private var coalescedRequestCount = 0
    private var countsByTrigger: [ProviderEligibilityScanTrigger: Int] = [:]

    func scan(
        candidates: [RegisteredProviderCandidate],
        excludedProviderIDs: Set<AgentConnectorID> = [],
        trigger: ProviderEligibilityScanTrigger
    ) async -> ProviderSurfaceAdmissionSet {
        guard !Task.isCancelled else {
            return ProviderSurfaceAdmissionSet(trigger: trigger, scanGeneration: nextGeneration, records: [])
        }
        if let active {
            coalescedRequestCount += 1
            onRequestCoalesced()
            return await active.task.value
        }

        nextGeneration &+= 1
        let generation = nextGeneration
        countsByTrigger[trigger, default: 0] += 1
        let task = Task {
            await Self.evaluate(
                candidates: candidates,
                excludedProviderIDs: excludedProviderIDs,
                trigger: trigger,
                generation: generation
            )
        }
        active = ActiveScan(generation: generation, task: task)
        let result = await task.value
        if active?.generation == generation {
            active = nil
            completedScanCount += 1
        }
        return result
    }

    /// Invalidate the owned evaluation without waiting for a noncooperative
    /// provider. Its cancellation checks prevent later connector starts/reads.
    func cancelOutstandingScan() {
        active?.task.cancel()
        active = nil
    }

    func diagnostics() -> LocalProviderEligibilityScannerDiagnostics {
        LocalProviderEligibilityScannerDiagnostics(
            completedScanCount: completedScanCount,
            coalescedRequestCount: coalescedRequestCount,
            countsByTrigger: countsByTrigger,
            activeGeneration: active?.generation
        )
    }

    private static func evaluate(
        candidates: [RegisteredProviderCandidate],
        excludedProviderIDs: Set<AgentConnectorID>,
        trigger: ProviderEligibilityScanTrigger,
        generation: UInt64
    ) async -> ProviderSurfaceAdmissionSet {
        var records: [ProviderSurfaceAdmissionRecord] = []
        for candidate in candidates.sorted(by: {
            if $0.descriptor.providerPriority == $1.descriptor.providerPriority {
                return $0.descriptor.id < $1.descriptor.id
            }
            return $0.descriptor.providerPriority < $1.descriptor.providerPriority
        }) {
            guard !Task.isCancelled else { break }
            let admission: ProviderSurfaceAdmission
            if excludedProviderIDs.contains(candidate.descriptor.id) {
                admission = .hiddenNotAuthenticated
            } else {
                admission = await evaluate(candidate, trigger: trigger)
            }
            records.append(
                ProviderSurfaceAdmissionRecord(
                    id: candidate.descriptor.id,
                    providerName: candidate.descriptor.providerName,
                    priority: candidate.descriptor.providerPriority,
                    admission: admission,
                    loginOption: loginOption(
                        for: candidate.descriptor,
                        admission: admission
                    ),
                    safeFailure: excludedProviderIDs.contains(candidate.descriptor.id)
                        ? nil : await candidate.connector.currentSnapshot().safeFailure
                )
            )
        }
        return ProviderSurfaceAdmissionSet(
            trigger: trigger,
            scanGeneration: generation,
            records: records
        )
    }

    private static func evaluate(
        _ candidate: RegisteredProviderCandidate,
        trigger: ProviderEligibilityScanTrigger
    ) async -> ProviderSurfaceAdmission {
        let descriptor = candidate.descriptor
        guard !Task.isCancelled else { return .hiddenCurrentReadFailed }
        guard descriptor.hasSurfaceAdmissibleReadContract else {
            return descriptor.localSourceClass == .unsupported
                ? .hiddenUnsupported
                : .hiddenNoAdmittedLocalSource
        }
        guard await candidate.connector.permitsRead(for: trigger) else {
            return .hiddenNotAuthenticated
        }

        guard !Task.isCancelled else { return .hiddenCurrentReadFailed }
        let probe = await candidate.connector.probe()
        guard !Task.isCancelled else { return .hiddenCurrentReadFailed }
        switch probe.state {
        case .unsupported:
            return .hiddenUnsupported
        case .authenticationRequired:
            return .hiddenNotAuthenticated
        case .failed where probe.safeFailure == .unavailable:
            return .hiddenNotRunning
        default:
            break
        }

        await candidate.connector.start()
        guard !Task.isCancelled else { return .hiddenCurrentReadFailed }
        if !descriptor.capabilities.contains(.passiveLocalAvailability) {
            if descriptor.localSourceClass == .browserCompanionUsage,
               (await candidate.connector.currentSnapshot()).freshness == .fresh {
                // A consent-driven Settings connection already completed the
                // current read. Admission must not multiply that provider
                // request merely to publish the same immutable snapshot.
            } else {
                guard !Task.isCancelled else { return .hiddenCurrentReadFailed }
                switch probe.state {
                case .ready, .stale:
                    await candidate.connector.refresh(trigger: .manual)
                case .inactive, .waitingForFirstResponse, .failed:
                    await candidate.connector.perform(.connect)
                case .authenticationRequired, .unsupported:
                    break
                }
            }
        }

        guard !Task.isCancelled else { return .hiddenCurrentReadFailed }
        let snapshot = await candidate.connector.currentSnapshot()
        guard !Task.isCancelled else { return .hiddenCurrentReadFailed }
        return admission(
            for: snapshot,
            descriptor: descriptor
        )
    }

    static func admission(
        for snapshot: AgentUsageSnapshot,
        descriptor: AgentConnectorDescriptor
    ) -> ProviderSurfaceAdmission {
        let permitsRetainedValue = ProviderUsageSurfacePolicy.permitsRetainedValue(
            snapshot: snapshot,
            capabilities: descriptor.capabilities
        )
        switch snapshot.state {
        case .inactive:
            return .hiddenNotRunning
        case .authenticationRequired:
            return .hiddenNotAuthenticated
        case .unsupported:
            return .hiddenUnsupported
        case .waitingForFirstResponse, .failed:
            return .hiddenCurrentReadFailed
        case .stale where !permitsRetainedValue:
            return .hiddenCurrentReadFailed
        case .stale:
            break
        case .ready:
            break
        }

        // A provider can observe real local activity long before any exact
        // quota anchor exists. The connector publishes that channel on purpose
        // — "without manufacturing a remaining percentage" — but requiring an
        // account channel hid the whole provider, discarding measured usage
        // and stopping the connector that produced it.
        //
        // Admit it only when nothing here can be read as a quota: no account
        // channel to weaken, and no rate-limit window anywhere in the snapshot,
        // so every percentage surface keeps rendering its existing unknown
        // state rather than inventing a number. Stale local data stays hidden,
        // matching the conservatism of the account path above.
        if snapshot.channels.allSatisfy({ $0.id != .account }),
           let local = snapshot.channels.first(where: { $0.id == .localActivity }),
           descriptor.hasSurfaceAdmissibleReadContract,
           snapshot.safeFailure == nil,
           local.safeFailure == nil,
           snapshot.channels.allSatisfy({ $0.rateLimitWindows.isEmpty }),
           [.fresh, .cached].contains(local.freshness),
           [.fresh, .cached].contains(snapshot.freshness) {
            return .admitted(LocalLiveProviderSnapshot(snapshot: snapshot))
        }

        guard descriptor.hasSurfaceAdmissibleReadContract,
              let account = snapshot.channels.first(where: { $0.id == .account }),
              account.sourceTier != .manualUserConfirmed,
              ProviderUsageSurfacePolicy.hasAdmissibleAccountProvenance(
                snapshot: snapshot,
                account: account
              ),
              ProviderUsageSurfacePolicy.validatesUsage(account)
        else {
            return .hiddenCurrentReadFailed
        }
        if permitsRetainedValue,
           [.cached, .stale].contains(snapshot.freshness),
           account.freshness == snapshot.freshness,
           ProviderUsageSurfacePolicy.isAdmissibleRetainedFailure(
               snapshot.safeFailure,
               providerID: snapshot.id
           ),
           ProviderUsageSurfacePolicy.isAdmissibleRetainedFailure(
               account.safeFailure,
               providerID: snapshot.id
           ) {
            return .admitted(LocalLiveProviderSnapshot(snapshot: snapshot))
        }
        guard snapshot.safeFailure == nil,
              snapshot.freshness == .fresh,
              account.freshness == .fresh,
              account.safeFailure == nil
        else {
            return .hiddenCurrentReadFailed
        }
        return .admitted(LocalLiveProviderSnapshot(snapshot: snapshot))
    }

    static func loginOption(
        for descriptor: AgentConnectorDescriptor,
        admission: ProviderSurfaceAdmission
    ) -> ProviderLoginOption? {
        if admission == .hiddenNotAuthenticated,
           descriptor.isRegisteredChineseAgent,
           descriptor.localSourceClass == .admittedStructuredLocal,
           descriptor.usageReadContract == .currentStructuredLocalRead,
           descriptor.authenticationMethod == .officialApplicationOwnedSession,
           descriptor.loginAssistance == .userInitiatedOfficialChineseAppLogin,
           let url = descriptor.officialLoginApplicationURL {
            return ProviderLoginOption(
                id: descriptor.id,
                providerName: descriptor.providerName,
                officialApplicationURL: url
            )
        }
        return nil
    }
}

extension AgentConnectorDescriptor {
    var hasSurfaceAdmissibleReadContract: Bool {
        switch (localSourceClass, usageReadContract) {
        case (.admittedStructuredLocal, .currentStructuredLocalRead),
             (.authenticatedAccountWeb, .currentAuthenticatedAccountWebRead),
             (.browserCompanionUsage, .currentBrowserCompanionUsageRead):
            true
        default:
            false
        }
    }
}
