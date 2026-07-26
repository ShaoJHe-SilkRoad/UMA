import Foundation

enum ProviderEligibilityScanTrigger: String, CaseIterable, Hashable, Sendable {
    case applicationLaunch
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

/// The one provider-neutral discovery owner. It scans only registered
/// descriptors, coalesces concurrent requests, and produces the sole admitted
/// provider set consumed by both product surfaces.
actor LocalProviderEligibilityScanner {
    private struct ActiveScan {
        let generation: UInt64
        let task: Task<ProviderSurfaceAdmissionSet, Never>
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
        if let active {
            coalescedRequestCount += 1
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
                    )
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
        guard descriptor.hasSurfaceAdmissibleReadContract else {
            return descriptor.localSourceClass == .unsupported
                ? .hiddenUnsupported
                : .hiddenNoAdmittedLocalSource
        }
        guard await candidate.connector.permitsRead(for: trigger) else {
            return .hiddenNotAuthenticated
        }

        let probe = await candidate.connector.probe()
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
        switch probe.state {
        case .ready, .stale:
            await candidate.connector.refresh(trigger: .manual)
        case .inactive, .waitingForFirstResponse, .failed:
            await candidate.connector.perform(.connect)
        case .authenticationRequired, .unsupported:
            break
        }

        let snapshot = await candidate.connector.currentSnapshot()
        return admission(
            for: snapshot,
            descriptor: descriptor
        )
    }

    static func admission(
        for snapshot: AgentUsageSnapshot,
        descriptor: AgentConnectorDescriptor
    ) -> ProviderSurfaceAdmission {
        switch snapshot.state {
        case .inactive:
            return .hiddenNotRunning
        case .authenticationRequired:
            return .hiddenNotAuthenticated
        case .unsupported:
            return .hiddenUnsupported
        case .waitingForFirstResponse, .stale, .failed:
            return .hiddenCurrentReadFailed
        case .ready:
            break
        }

        guard descriptor.hasSurfaceAdmissibleReadContract,
              snapshot.safeFailure == nil,
              snapshot.freshness == .fresh,
              let account = snapshot.channels.first(where: { $0.id == .account }),
              account.sourceTier != .manualUserConfirmed,
              account.provenance == .providerReported,
              account.freshness == .fresh,
              account.safeFailure == nil,
              validatesCurrentUsage(account)
        else {
            return .hiddenCurrentReadFailed
        }
        return .admitted(LocalLiveProviderSnapshot(snapshot: snapshot))
    }

    private static func validatesCurrentUsage(
        _ channel: AgentUsageChannel
    ) -> Bool {
        if channel.availabilitySourceState == .officialStructured
            || channel.availabilitySourceState == .authenticatedAccountWeb {
            return true
        }
        if channel.rateLimitWindows.isEmpty {
            return channel.accountMetrics != nil
        }
        return channel.rateLimitWindows.allSatisfy { window in
            if window.isUnlimited { return true }
            guard let used = window.usedPercent else { return false }
            return used.isFinite && (0...100).contains(used)
        }
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
             (.authenticatedAccountWeb, .currentAuthenticatedAccountWebRead):
            true
        default:
            false
        }
    }
}
