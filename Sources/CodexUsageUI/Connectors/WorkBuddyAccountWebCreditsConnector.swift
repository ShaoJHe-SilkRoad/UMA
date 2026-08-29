import Foundation

actor WorkBuddyAccountWebCreditsConnector: AgentUsageConnector {
    static let connectorID = AgentConnectorID(
        rawValue: "workbuddy.accountWebCredits"
    )!
    private static let accountWebCapabilities: Set<AgentConnectorCapability> = [
        .connect, .reconnect, .refresh, .disconnect, .accountUsage,
        .sanitizedLastValidRestore
    ]

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "WorkBuddy",
        officialSource: "Account web sync",
        sourceTier: .authorizedReadOnlyRemote,
        sourceVersion: "1",
        supportedScopes: [.account],
        capabilities: accountWebCapabilities,
        configurationRequirements: [
            .userAuthorization,
            .officialManagedSession,
            .explicitlyAuthorizedReadOnlyRemoteAccess
        ],
        privacyAllowlist: [
            "poolStableID",
            "poolKind",
            "poolUsedCredits",
            "poolTotalCredits",
            "poolDisplayedRemainingCredits",
            "poolEffectiveAt",
            "poolExpiresAt",
            "poolSafeStatus",
            "subscriptionRemainingCredits",
            "addOnRemainingCredits",
            "benefitGiftRemainingCredits",
            "calculatedTotalRemainingCredits",
            "authoritativePageBalanceCredits",
            "observedAt",
            "extractorVersion"
        ],
        supportsRestore: false,
        supportsUninstall: false,
        unsupportedFields: [
            "accountIdentity",
            "fullHTML",
            "fullDOM",
            "cookies",
            "localStorage",
            "sessionStorage",
            "credentials",
            "tokens",
            "billing",
            "orders",
            "taskContent",
            "conversationContent"
        ],
        expectedRuntime: .none,
        localSourceClass: .authenticatedAccountWeb,
        authenticationMethod: .umaOwnedAuthenticatedAccountWebSession,
        usageReadContract: .currentAuthenticatedAccountWebRead,
        loginAssistance: .none,
        isRegisteredChineseAgent: true
    )!

    private let hasConsent: @MainActor @Sendable () -> Bool
    private let canReadOnApplicationLaunch:
        @MainActor @Sendable () async -> Bool
    private let reader:
        @MainActor @Sendable () async -> WorkBuddyAccountWebReadResult
    private let disconnectOwnedSession: @MainActor @Sendable () async -> Void
    private var snapshot: AgentUsageSnapshot
    private var lastSuccessfulSnapshot: AgentUsageSnapshot?
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var inFlightRead:
        (generation: UInt64, task: Task<WorkBuddyAccountWebReadResult, Never>)?
    private var nextReadGeneration: UInt64 = 0
    private var completedReadCount = 0
    private var coalescedReadCount = 0
    private var publicationCount = 0

    init(
        hasConsent: @escaping @MainActor @Sendable () -> Bool,
        canReadOnApplicationLaunch:
            @escaping @MainActor @Sendable () async -> Bool = { false },
        reader: @escaping @MainActor @Sendable () async -> WorkBuddyAccountWebReadResult,
        disconnectOwnedSession: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.hasConsent = hasConsent
        self.canReadOnApplicationLaunch = canReadOnApplicationLaunch
        self.reader = reader
        self.disconnectOwnedSession = disconnectOwnedSession
        snapshot = Self.unavailableSnapshot(
            state: .authenticationRequired,
            failure: .authorizationRequired
        )
    }

    func permitsRead(for trigger: ProviderEligibilityScanTrigger) async -> Bool {
        guard trigger == .applicationLaunch else { return true }
        return await canReadOnApplicationLaunch()
    }

    func probe() async -> AgentConnectorProbe {
        let consent = await hasConsent()
        if !consent {
            return AgentConnectorProbe(
                state: .authenticationRequired,
                safeFailure: .authorizationRequired
            )
        }
        return AgentConnectorProbe(
            state: snapshot.state == .ready ? .ready : .inactive,
            safeFailure: nil
        )
    }

    func start() async {}

    func refresh() async {
        await read()
    }

    func refresh(trigger: CodexRefreshTrigger) async {
        await read()
    }

    func perform(_ command: AgentConnectorCommand) async {
        switch command {
        case .connect, .reconnect, .refresh:
            await read()
        case .disconnect:
            invalidateInFlightRead()
            await disconnectOwnedSession()
            lastSuccessfulSnapshot = nil
            replace(
                Self.unavailableSnapshot(
                    state: .authenticationRequired,
                    failure: .authorizationRequired
                )
            )
        }
    }

    func stop() async {}

    func readDiagnostics() -> (
        active: Int,
        completed: Int,
        coalesced: Int,
        publications: Int
    ) {
        (
            inFlightRead == nil ? 0 : 1,
            completedReadCount,
            coalescedReadCount,
            publicationCount
        )
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        snapshot
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation() }
            }
        }
    }

    private func read() async {
        if let inFlightRead {
            coalescedReadCount += 1
            _ = await inFlightRead.task.value
            return
        }
        nextReadGeneration &+= 1
        let generation = nextReadGeneration
        let reader = self.reader
        let task = Task { @MainActor in
            await reader()
        }
        inFlightRead = (generation, task)
        replace(
            Self.unavailableSnapshot(
                state: .waitingForFirstResponse,
                failure: nil
            )
        )
        let result = await task.value
        guard inFlightRead?.generation == generation else { return }
        inFlightRead = nil
        completedReadCount += 1
        switch result {
        case let .success(reading):
            let successful = Self.snapshot(for: reading)
            lastSuccessfulSnapshot = successful
            replace(successful)
        case .authenticationRequired:
            lastSuccessfulSnapshot = nil
            replace(
                Self.unavailableSnapshot(
                    state: .authenticationRequired,
                    failure: .authorizationRequired
                )
            )
        case let .failure(failure):
            let safeFailure = Self.safeFailure(for: failure)
            if safeFailure != .authorizationRequired,
               let lastSuccessfulSnapshot {
                replace(Self.retainedSnapshot(
                    from: lastSuccessfulSnapshot,
                    failure: safeFailure
                ))
            } else {
                if safeFailure == .authorizationRequired {
                    lastSuccessfulSnapshot = nil
                }
                replace(
                    Self.unavailableSnapshot(
                        state: safeFailure == .authorizationRequired
                            ? .authenticationRequired
                            : .failed,
                        failure: safeFailure
                    )
                )
            }
        }
    }

    private func invalidateInFlightRead() {
        nextReadGeneration &+= 1
        inFlightRead?.task.cancel()
        inFlightRead = nil
    }

    private func replace(_ next: AgentUsageSnapshot) {
        if next.state != .waitingForFirstResponse {
            publicationCount += 1
        }
        snapshot = next
        continuation?.yield(next)
    }

    private func clearContinuation() {
        continuation = nil
    }

    private static func snapshot(
        for reading: WorkBuddyAccountWebReading
    ) -> AgentUsageSnapshot {
        let balance = reading.balance
        let channel = AgentUsageChannel(
            id: .account,
            sourceTier: .authorizedReadOnlyRemote,
            sourceVersion: String(reading.extractorVersion),
            scopes: [.account],
            provenance: .providerReported,
            freshness: .fresh,
            capturedAt: balance.observedAt,
            coverageNote: "Account web sync",
            rateLimitWindows: [],
            accountMetrics: AgentAccountMetrics(
                planLabel: balance.planTier?.rawValue,
                availableResets: nil,
                lifetimeTokens: nil,
                sevenDayTokens: nil
            ),
            localActivityMetrics: nil,
            safeFailure: nil,
            availability: .credits(balance),
            accountCreditSnapshot: reading.creditSnapshot
        )
        return AgentUsageSnapshot(
            id: connectorID,
            providerName: "WorkBuddy",
            state: .ready,
            capturedAt: balance.observedAt,
            lastSuccessfulAt: balance.observedAt,
            freshness: .fresh,
            channels: [channel],
            capabilities: accountWebCapabilities,
            safeFailure: nil
        )
    }

    private static func unavailableSnapshot(
        state: AgentConnectorState,
        failure: AgentSafeFailure?
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: connectorID,
            providerName: "WorkBuddy",
            state: state,
            capturedAt: Date(),
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: accountWebCapabilities,
            safeFailure: failure
        )
    }

    private static func retainedSnapshot(
        from successful: AgentUsageSnapshot,
        failure: AgentSafeFailure
    ) -> AgentUsageSnapshot {
        let capturedAt = Date()
        let retainedChannels = successful.channels.map { channel in
            AgentUsageChannel(
                id: channel.id,
                sourceTier: channel.sourceTier,
                sourceVersion: channel.sourceVersion,
                scopes: channel.scopes,
                provenance: channel.provenance,
                freshness: .stale,
                capturedAt: channel.capturedAt,
                coverageNote: channel.coverageNote,
                sourceConfidence: channel.sourceConfidence,
                lastExactAt: channel.lastExactAt,
                rateLimitWindows: channel.rateLimitWindows,
                accountMetrics: channel.accountMetrics,
                localActivityMetrics: channel.localActivityMetrics,
                safeFailure: failure,
                availability: channel.availability,
                accountCreditSnapshot: channel.accountCreditSnapshot
            )
        }
        return AgentUsageSnapshot(
            id: successful.id,
            providerName: successful.providerName,
            state: .stale,
            capturedAt: capturedAt,
            lastSuccessfulAt: successful.lastSuccessfulAt,
            freshness: .stale,
            channels: retainedChannels,
            capabilities: accountWebCapabilities,
            safeFailure: failure,
            selectedWindowID: successful.selectedWindowID
        )
    }

    private static func safeFailure(
        for failure: WorkBuddyAccountWebFailure
    ) -> AgentSafeFailure {
        switch failure {
        case .consentRequired, .authenticationRequired:
            .authorizationRequired
        case .timedOut:
            .timedOut
        case .unexpectedPage, .pageNotStabilized, .incompletePoolSections,
             .malformedCredits, .ambiguousCredits, .invalidCreditPool,
             .duplicateCreditPool, .ambiguousAccountBalance,
             .accountBalanceReconciliationFailed:
            .malformedResponse
        case .invalidNavigation, .webContentUnavailable,
             .websiteDataClearFailed:
            .unavailable
        }
    }
}
