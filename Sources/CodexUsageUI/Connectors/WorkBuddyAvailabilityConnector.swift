import Foundation

actor WorkBuddyAvailabilityConnector: AgentUsageConnector {
    static let connectorID = AgentConnectorID(rawValue: "workbuddy.manualAvailability")!

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "WorkBuddy",
        officialSource: "Manual confirmation",
        sourceTier: .manualUserConfirmed,
        sourceVersion: "1",
        supportedScopes: [.account],
        capabilities: [
            .passiveLocalAvailability,
            .hiddenFromDesktopAssistant
        ],
        configurationRequirements: [],
        privacyAllowlist: [
            "enabled",
            "remainingCredits",
            "usedCredits",
            "totalCredits",
            "tier",
            "scope",
            "nextExpiryAt",
            "confirmedAt",
            "manualSourceMode"
        ],
        supportsRestore: false,
        supportsUninstall: false,
        unsupportedFields: [
            "accountIdentity",
            "providerPayload",
            "browserState",
            "credentials",
            "taskContent",
            "conversationContent"
        ]
    )!

    private let source: ManualWorkBuddyAvailabilitySource
    private var state = WorkBuddyManualSourceState.initial
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var sourceTask: Task<Void, Never>?

    init(source: ManualWorkBuddyAvailabilitySource) {
        self.source = source
    }

    func probe() async -> AgentConnectorProbe {
        _ = await source.load()
        return AgentConnectorProbe(state: .inactive, safeFailure: nil)
    }

    func start() async {
        guard sourceTask == nil else { return }
        state = await source.load()
        sourceTask = Task { [weak self, source] in
            let stream = await source.states()
            for await nextState in stream {
                guard !Task.isCancelled else { return }
                await self?.receive(nextState)
            }
        }
    }

    func refresh() async {}

    func refresh(trigger: CodexRefreshTrigger) async {}

    func perform(_ command: AgentConnectorCommand) async {}

    func stop() async {
        sourceTask?.cancel()
        sourceTask = nil
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        makeSnapshot(from: state)
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(makeSnapshot(from: state))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation() }
            }
        }
    }

    private func receive(_ state: WorkBuddyManualSourceState) {
        guard self.state != state else { return }
        self.state = state
        continuation?.yield(makeSnapshot(from: state))
    }

    private func makeSnapshot(from state: WorkBuddyManualSourceState) -> AgentUsageSnapshot {
        let observation = state.enabled ? state.observation : nil
        let safeFailure: AgentSafeFailure? = switch state.lifecycle {
        case .invalidSavedData: .malformedResponse
        case .unconfigured: .unavailable
        case .disabled, .manualConfirmed: nil
        }
        let channel = AgentUsageChannel(
            id: .account,
            sourceTier: .manualUserConfirmed,
            sourceVersion: "1",
            scopes: [.account],
            provenance: .manualConfirmed,
            freshness: .unavailable,
            capturedAt: observation?.balance.observedAt,
            coverageNote: "Manual snapshot · Shared with CodeBuddy",
            rateLimitWindows: [],
            accountMetrics: observation.map {
                AgentAccountMetrics(
                    planLabel: $0.tier.rawValue,
                    availableResets: nil,
                    lifetimeTokens: nil,
                    sevenDayTokens: nil
                )
            },
            localActivityMetrics: nil,
            safeFailure: safeFailure,
            availability: observation.map { .credits($0.balance) } ?? .unavailable
        )
        return AgentUsageSnapshot(
            id: id,
            providerName: descriptor.providerName,
            state: .inactive,
            capturedAt: observation?.balance.observedAt ?? state.changedAt,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [channel],
            capabilities: descriptor.capabilities,
            safeFailure: safeFailure
        )
    }

    private func clearContinuation() { continuation = nil }
}
