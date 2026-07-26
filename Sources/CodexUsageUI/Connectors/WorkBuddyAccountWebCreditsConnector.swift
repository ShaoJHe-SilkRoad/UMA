import Foundation

actor WorkBuddyAccountWebCreditsConnector: AgentUsageConnector {
    static let connectorID = AgentConnectorID(
        rawValue: "workbuddy.accountWebCredits"
    )!
    private static let accountWebCapabilities: Set<AgentConnectorCapability> = [
        .connect, .reconnect, .refresh, .disconnect, .accountUsage
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
            "remainingCredits",
            "usedCredits",
            "totalCredits",
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
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?

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
            await disconnectOwnedSession()
            replace(
                Self.unavailableSnapshot(
                    state: .authenticationRequired,
                    failure: .authorizationRequired
                )
            )
        }
    }

    func stop() async {}

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
        replace(
            Self.unavailableSnapshot(
                state: .waitingForFirstResponse,
                failure: nil
            )
        )
        switch await reader() {
        case let .success(reading):
            replace(Self.snapshot(for: reading))
        case .authenticationRequired:
            replace(
                Self.unavailableSnapshot(
                    state: .authenticationRequired,
                    failure: .authorizationRequired
                )
            )
        case let .failure(failure):
            replace(
                Self.unavailableSnapshot(
                    state: .failed,
                    failure: Self.safeFailure(for: failure)
                )
            )
        }
    }

    private func replace(_ next: AgentUsageSnapshot) {
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
            availability: .credits(balance)
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

    private static func safeFailure(
        for failure: WorkBuddyAccountWebFailure
    ) -> AgentSafeFailure {
        switch failure {
        case .consentRequired, .authenticationRequired:
            .authorizationRequired
        case .timedOut:
            .timedOut
        case .unexpectedPage, .malformedCredits, .ambiguousCredits:
            .malformedResponse
        case .invalidNavigation, .webContentUnavailable,
             .websiteDataClearFailed:
            .unavailable
        }
    }
}
