import Foundation

actor ManusUsageConnector: AgentUsageConnector {
    static let connectorID = AgentConnectorID(rawValue: "manus.apiV2")!
    private static let connectorCapabilities:
        Set<AgentConnectorCapability> = [
            .connect,
            .reconnect,
            .refresh,
            .disconnect,
            .accountUsage,
            .hiddenFromDesktopAssistant,
        ]

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "Manus",
        officialSource: "Official API v2",
        sourceTier: .authorizedReadOnlyRemote,
        sourceVersion: "2",
        supportedScopes: [.account],
        capabilities: connectorCapabilities,
        configurationRequirements: [
            .userAuthorization,
            .explicitlyAuthorizedReadOnlyRemoteAccess,
        ],
        privacyAllowlist: [
            "totalCredits",
            "freeCredits",
            "periodicCredits",
            "addOnCredits",
            "eventCredits",
            "refreshCredits",
            "proMonthlyCredits",
            "maxRefreshCredits",
            "nextRefreshAt",
            "refreshInterval",
            "observedAt",
        ],
        supportsRestore: false,
        supportsUninstall: false,
        unsupportedFields: [
            "accountIdentity",
            "task",
            "taskHistory",
            "project",
            "file",
            "prompt",
            "response",
            "browserSession",
            "cookie",
            "token",
            "rawResponse",
            "requestID",
        ],
        expectedRuntime: .none,
        localSourceClass: .officialRemoteUsageAPI,
        authenticationMethod: .umaOwnedKeychainCredential,
        usageReadContract: .currentOfficialRemoteRead,
        loginAssistance: .none,
        isRegisteredChineseAgent: true
    )!

    private enum ReadOutcome: Sendable {
        case success(ManusCreditsReading)
        case keychain(ManusAPIKeyStoreError)
        case client(ManusCreditsClientFailure)
    }

    private let keyStore: any ManusAPIKeyStoring
    private let client: any ManusCreditsReadingClient
    private let scheduler: ManusRefreshScheduler
    private var snapshot: AgentUsageSnapshot
    private var continuations: [
        UUID: AsyncStream<AgentUsageSnapshot>.Continuation
    ] = [:]
    private var activeRead: (generation: UInt64, task: Task<ReadOutcome, Never>)?
    private var followUpRequested = false
    private var generation: UInt64 = 0
    private var completedReadCount = 0
    private var coalescedReadCount = 0
    private var droppedScheduledReadCount = 0
    private var settingsFailure: ManusSettingsSafeFailure?

    init(
        keyStore: any ManusAPIKeyStoring,
        client: any ManusCreditsReadingClient,
        scheduler: ManusRefreshScheduler
    ) {
        self.keyStore = keyStore
        self.client = client
        self.scheduler = scheduler
        snapshot = Self.unavailableSnapshot(
            state: .authenticationRequired,
            failure: .authorizationRequired
        )
    }

    func permitsRead(for trigger: ProviderEligibilityScanTrigger) async -> Bool {
        switch await keyStore.configurationState() {
        case .notConfigured:
            false
        case .configured, .unavailable:
            true
        }
    }

    func probe() async -> AgentConnectorProbe {
        do {
            _ = try await keyStore.read()
            return AgentConnectorProbe(
                state: snapshot.state == .ready
                    ? .ready
                    : .waitingForFirstResponse,
                safeFailure: nil
            )
        } catch let error as ManusAPIKeyStoreError {
            let failure = Self.safeFailure(for: error)
            return AgentConnectorProbe(
                state: failure == .authorizationRequired
                    ? .authenticationRequired
                    : .failed,
                safeFailure: failure
            )
        } catch {
            return AgentConnectorProbe(
                state: .failed,
                safeFailure: .unavailable
            )
        }
    }

    func start() async {}

    func refresh() async {
        await read(trigger: .manual)
    }

    func refresh(trigger: CodexRefreshTrigger) async {
        await read(trigger: trigger)
    }

    func perform(_ command: AgentConnectorCommand) async {
        switch command {
        case .connect, .reconnect, .refresh:
            await read(trigger: .manual)
        case .disconnect:
            generation &+= 1
            activeRead?.task.cancel()
            activeRead = nil
            followUpRequested = false
            await scheduler.cancel()
            do {
                try await keyStore.delete()
                settingsFailure = nil
                replace(
                    Self.unavailableSnapshot(
                        state: .authenticationRequired,
                        failure: .authorizationRequired
                    )
                )
            } catch let error as ManusAPIKeyStoreError {
                settingsFailure = Self.settingsSafeFailure(for: error)
                replace(
                    Self.unavailableSnapshot(
                        state: .failed,
                        failure: Self.safeFailure(for: error)
                    )
                )
            } catch {
                settingsFailure = .credentialUnavailable
                replace(
                    Self.unavailableSnapshot(
                        state: .failed,
                        failure: .unavailable
                    )
                )
            }
        }
    }

    func stop() async {
        generation &+= 1
        activeRead?.task.cancel()
        activeRead = nil
        followUpRequested = false
        await scheduler.cancel()
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        snapshot
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation(id: id) }
            }
        }
    }

    func diagnostics() -> (
        activeReads: Int,
        completedReads: Int,
        coalescedReads: Int,
        droppedScheduledReads: Int,
        followUpQueued: Bool
    ) {
        (
            activeRead == nil ? 0 : 1,
            completedReadCount,
            coalescedReadCount,
            droppedScheduledReadCount,
            followUpRequested
        )
    }

    func currentSettingsFailure() -> ManusSettingsSafeFailure? {
        settingsFailure
    }

    private func read(trigger: CodexRefreshTrigger) async {
        if let activeRead {
            coalescedReadCount += 1
            if trigger == .timer {
                droppedScheduledReadCount += 1
            } else {
                followUpRequested = true
            }
            _ = await activeRead.task.value
            return
        }

        var readTrigger = trigger
        repeat {
            followUpRequested = false
            generation &+= 1
            let readGeneration = generation
            let keyStore = self.keyStore
            let client = self.client
            let scheduler = self.scheduler
            let task = Task<ReadOutcome, Never> {
                do {
                    try await scheduler.waitUntilReadIsAllowed()
                    try Task.checkCancellation()
                } catch {
                    return .client(.cancelled)
                }
                do {
                    let credential = try await keyStore.read()
                    switch await client.read(apiKey: credential) {
                    case let .success(reading):
                        return .success(reading)
                    case let .failure(failure):
                        return .client(failure)
                    }
                } catch let error as ManusAPIKeyStoreError {
                    return .keychain(error)
                } catch {
                    return .keychain(.unavailable)
                }
            }
            activeRead = (readGeneration, task)
            settingsFailure = nil
            replace(
                Self.unavailableSnapshot(
                    state: .waitingForFirstResponse,
                    failure: nil
                )
            )
            let outcome = await task.value
            guard activeRead?.generation == readGeneration else { return }
            activeRead = nil
            completedReadCount += 1
            let authenticationFailed = apply(outcome)
            await scheduler.readDidComplete(
                trigger: readTrigger,
                authenticationFailed: authenticationFailed
            )
            let readSucceeded: Bool
            if case .success = outcome {
                readSucceeded = true
            } else {
                readSucceeded = false
            }
            if !readSucceeded {
                followUpRequested = false
            }
            readTrigger = .manual
        } while followUpRequested
    }

    @discardableResult
    private func apply(_ outcome: ReadOutcome) -> Bool {
        switch outcome {
        case let .success(reading):
            settingsFailure = nil
            replace(Self.snapshot(for: reading))
            return false
        case let .keychain(error):
            let failure = Self.safeFailure(for: error)
            settingsFailure = Self.settingsSafeFailure(for: error)
            replace(
                Self.unavailableSnapshot(
                    state: failure == .authorizationRequired
                        ? .authenticationRequired
                        : .failed,
                    failure: failure
                )
            )
            return failure == .authorizationRequired
        case let .client(error):
            let failure = Self.safeFailure(for: error)
            settingsFailure = Self.settingsSafeFailure(for: error)
            replace(
                Self.unavailableSnapshot(
                    state: failure == .authorizationRequired
                        ? .authenticationRequired
                        : .failed,
                    failure: failure
                )
            )
            return failure == .authorizationRequired
        }
    }

    private func replace(_ next: AgentUsageSnapshot) {
        snapshot = next
        for continuation in continuations.values {
            continuation.yield(next)
        }
    }

    private func clearContinuation(id: UUID) {
        continuations[id] = nil
    }

    private static func snapshot(
        for reading: ManusCreditsReading
    ) -> AgentUsageSnapshot {
        let value: AgentAvailabilityValue
        do {
            value = .credits(
                try CreditBalance(
                    validatingRemaining: reading.snapshot.totalCredits,
                    scope: .manusAccount,
                    observedAt: reading.observedAt,
                    provenance: .officialRemoteUsageAPI(
                        observedAt: reading.observedAt
                    )
                )
            )
        } catch {
            value = .invalid(reason: .creditsOutOfRange)
        }
        let channel = AgentUsageChannel(
            id: .account,
            sourceTier: .authorizedReadOnlyRemote,
            sourceVersion: "2",
            scopes: [.account],
            provenance: .providerReported,
            freshness: .fresh,
            capturedAt: reading.observedAt,
            coverageNote: "Official API v2",
            rateLimitWindows: [],
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: nil,
            availability: value,
            creditDetails: reading.snapshot.creditDetails
        )
        return AgentUsageSnapshot(
            id: connectorID,
            providerName: "Manus",
            state: .ready,
            capturedAt: reading.observedAt,
            lastSuccessfulAt: reading.observedAt,
            freshness: .fresh,
            channels: [channel],
            capabilities: connectorCapabilities,
            safeFailure: nil
        )
    }

    private static func unavailableSnapshot(
        state: AgentConnectorState,
        failure: AgentSafeFailure?
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: connectorID,
            providerName: "Manus",
            state: state,
            capturedAt: Date(),
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: connectorCapabilities,
            safeFailure: failure
        )
    }

    private static func safeFailure(
        for error: ManusAPIKeyStoreError
    ) -> AgentSafeFailure {
        switch error {
        case .missingCredential, .invalidCredential:
            .authorizationRequired
        case .keychainLocked, .accessDenied, .unavailable:
            .unavailable
        case .invalidStoredCredential:
            .malformedResponse
        }
    }

    private static func settingsSafeFailure(
        for error: ManusAPIKeyStoreError
    ) -> ManusSettingsSafeFailure {
        switch error {
        case .missingCredential, .invalidCredential:
            .missingCredential
        case .keychainLocked, .accessDenied, .unavailable:
            .credentialUnavailable
        case .invalidStoredCredential:
            .invalidResponse
        }
    }

    private static func safeFailure(
        for error: ManusCreditsClientFailure
    ) -> AgentSafeFailure {
        switch error {
        case .missingCredential, .authentication:
            .authorizationRequired
        case .rateLimited:
            .unavailable
        case .network:
            .unavailable
        case .server:
            .unavailable
        case .schema, .unsupportedResponse:
            .malformedResponse
        case .cancelled:
            .unavailable
        }
    }

    private static func settingsSafeFailure(
        for error: ManusCreditsClientFailure
    ) -> ManusSettingsSafeFailure {
        switch error {
        case .missingCredential:
            .missingCredential
        case .authentication:
            .authentication
        case .rateLimited:
            .rateLimited
        case .network:
            .network
        case .server:
            .server
        case .schema, .unsupportedResponse:
            .invalidResponse
        case .cancelled:
            .cancelled
        }
    }
}
