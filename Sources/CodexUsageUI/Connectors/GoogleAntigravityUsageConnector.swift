import Foundation

struct GoogleAntigravityConnectorDiagnostics: Equatable, Sendable {
    let completedReadCount: Int
    let coalescedReadCount: Int
    let scheduledCycleCount: Int
    let processReadInFlight: Bool
    let schedulerActive: Bool
    let automaticRefreshSuspended: Bool
    let snapshotObserverCount: Int
}

actor GoogleAntigravityUsageConnector: AgentUsageConnector {
    typealias QuotaReader =
        @Sendable () async throws -> AntigravityQuotaSnapshot
    typealias CapabilityVerifier = @Sendable () throws -> Void
    typealias PreferenceReader = @Sendable () async -> Bool
    typealias InitialReadBarrier = @Sendable () async -> Void
    typealias Now = @Sendable () -> Date
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    static let connectorID = AgentConnectorID(rawValue: "antigravity.cli")!
    static let freshnessInterval: TimeInterval = 5 * 60
    static let staleInterval: TimeInterval = 30 * 60
    static let defaultRefreshInterval: TimeInterval = 5 * 60
    static let minimumRefreshInterval: TimeInterval = 3 * 60

    private static let capabilities: Set<AgentConnectorCapability> = [
        .connect,
        .reconnect,
        .refresh,
        .disconnect,
        .rateLimits,
        .sanitizedLastValidRestore,
        .automaticRefresh,
    ]

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "Google Antigravity",
        officialSource: "Official Antigravity CLI · read-only /usage",
        sourceTier: .officialCLIOrMetadata,
        sourceVersion: "agy-1.1.11",
        supportedScopes: [.account],
        capabilities: capabilities,
        configurationRequirements: [
            .officialManagedSession,
            .privacySafeLocalMetadataAccess,
        ],
        privacyAllowlist: [
            "bucketID",
            "safeBucketLabel",
            "remainingPercent",
            "bucketResetAt",
            "observedAt",
            "sourceVersion",
            "freshness",
        ],
        supportsRestore: false,
        supportsUninstall: false,
        unsupportedFields: [
            "credits",
            "accountIdentity",
            "credentials",
            "tokens",
            "cookies",
            "browserSession",
            "conversation",
            "prompt",
            "response",
            "task",
            "tool",
            "rawJSON",
            "workspace",
            "repository",
        ],
        expectedRuntime: .activeOfficialApplicationCLIOrService,
        localSourceClass: .admittedStructuredLocal,
        authenticationMethod: .officialApplicationOwnedSession,
        usageReadContract: .currentStructuredLocalRead,
        loginAssistance: .existingSessionOnly
    )!

    private struct ActiveRead {
        let generation: UInt64
        let task: Task<Result<AntigravityQuotaSnapshot, AntigravityCLIClientError>, Never>
    }

    private let readQuota: QuotaReader
    private let verifyCapability: CapabilityVerifier
    private let autoRefreshEnabled: PreferenceReader
    private let initialReadBarrier: InitialReadBarrier
    private let now: Now
    private let sleep: Sleeper
    private let refreshInterval: TimeInterval

    private var snapshot: AgentUsageSnapshot
    private var lastGood: AgentUsageSnapshot?
    private var continuations: [
        UUID: AsyncStream<AgentUsageSnapshot>.Continuation
    ] = [:]
    private var started = false
    private var activeRead: ActiveRead?
    private var initialReadTask: Task<Void, Never>?
    private var initialReadGeneration: UInt64 = 0
    private var schedulerTask: Task<Void, Never>?
    private var schedulerGeneration: UInt64 = 0
    private var readGeneration: UInt64 = 0
    private var automaticRefreshSuspended = false
    private var completedReadCount = 0
    private var coalescedReadCount = 0
    private var scheduledCycleCount = 0

    init(
        readQuota: @escaping QuotaReader,
        verifyCapability: @escaping CapabilityVerifier,
        autoRefreshEnabled: @escaping PreferenceReader = { true },
        initialReadBarrier: @escaping InitialReadBarrier = {},
        now: @escaping Now = Date.init,
        sleep: @escaping Sleeper = { interval in
            try await Task.sleep(for: .seconds(interval))
        },
        refreshInterval: TimeInterval = defaultRefreshInterval
    ) {
        self.readQuota = readQuota
        self.verifyCapability = verifyCapability
        self.autoRefreshEnabled = autoRefreshEnabled
        self.initialReadBarrier = initialReadBarrier
        self.now = now
        self.sleep = sleep
        self.refreshInterval = max(refreshInterval, Self.minimumRefreshInterval)
        snapshot = Self.unavailableSnapshot(
            state: .inactive,
            failure: nil,
            capturedAt: now()
        )
    }

    init(
        client: AntigravityReadOnlyCLIClient = AntigravityReadOnlyCLIClient(),
        autoRefreshEnabled: @escaping PreferenceReader = { true }
    ) {
        self.init(
            readQuota: { try await client.readCurrentQuota() },
            verifyCapability: { _ = try client.verifyCapability() },
            autoRefreshEnabled: autoRefreshEnabled
        )
    }

    func probe() async -> AgentConnectorProbe {
        do {
            try verifyCapability()
        } catch let error as AntigravityCLIClientError {
            applyCapabilityFailure(error)
            return AgentConnectorProbe(
                state: snapshot.state,
                safeFailure: snapshot.safeFailure
            )
        } catch {
            replace(Self.unavailableSnapshot(
                state: .failed,
                failure: .unavailable,
                capturedAt: now()
            ))
            return AgentConnectorProbe(state: .failed, safeFailure: .unavailable)
        }
        await refreshAge()
        return AgentConnectorProbe(
            state: snapshot.hasValidData ? snapshot.state : .inactive,
            safeFailure: snapshot.safeFailure
        )
    }

    func start() async {
        guard !started else { return }
        started = true
        automaticRefreshSuspended = false
        if !snapshot.hasValidData {
            replace(Self.unavailableSnapshot(
                state: .waitingForFirstResponse,
                failure: nil,
                capturedAt: now()
            ))
        }
        initialReadGeneration &+= 1
        let generation = initialReadGeneration
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performInitialRead(generation: generation)
        }
        initialReadTask = task
    }

    func refresh() async {
        await refresh(trigger: .manual)
    }

    func refresh(trigger: CodexRefreshTrigger) async {
        switch trigger {
        case .wake:
            await refreshAge()
            scheduleNextCycle()
        case .timer:
            await requestRead(reschedule: true)
        case .providerEvent, .reconnect, .manual:
            await consumeInitialReadOrRefresh()
        }
    }

    func perform(_ command: AgentConnectorCommand) async {
        switch command {
        case .connect:
            if !started { await start() }
            await consumeInitialReadOrRefresh()
        case .reconnect:
            automaticRefreshSuspended = false
            if !started { await start() }
            await consumeInitialReadOrRefresh()
        case .refresh:
            await consumeInitialReadOrRefresh()
        case .disconnect:
            await disconnect()
        }
    }

    func stop() async {
        await disconnect()
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        await refreshAge()
        return snapshot
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        let subscriptionID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[subscriptionID] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(subscriptionID) }
            }
        }
    }

    func diagnostics() -> GoogleAntigravityConnectorDiagnostics {
        GoogleAntigravityConnectorDiagnostics(
            completedReadCount: completedReadCount,
            coalescedReadCount: coalescedReadCount,
            scheduledCycleCount: scheduledCycleCount,
            processReadInFlight: activeRead != nil,
            schedulerActive: schedulerTask != nil,
            automaticRefreshSuspended: automaticRefreshSuspended,
            snapshotObserverCount: continuations.count
        )
    }

    func setAutomaticRefreshEnabled(_ enabled: Bool) {
        if enabled {
            scheduleNextCycle()
        } else {
            cancelScheduler()
        }
    }

    private func consumeInitialReadOrRefresh() async {
        if let launchTask = initialReadTask {
            let generation = initialReadGeneration
            let completedBeforeAwait = completedReadCount
            await launchTask.value
            guard started, initialReadGeneration == generation else { return }
            // Coalesce only when the launch read was still active when this
            // request arrived. A completed-but-not-yet-cleared launch task
            // must not swallow the first later manual refresh.
            if completedReadCount > completedBeforeAwait {
                return
            }
        }
        guard started else { return }
        await requestRead(reschedule: true)
    }

    private func performInitialRead(generation: UInt64) async {
        await initialReadBarrier()
        guard started,
              initialReadGeneration == generation,
              !Task.isCancelled else { return }
        await requestRead(reschedule: true)
        guard started,
              initialReadGeneration == generation,
              !Task.isCancelled else { return }
        initialReadTask = nil
    }

    private func requestRead(reschedule: Bool) async {
        cancelScheduler()
        if let activeRead {
            coalescedReadCount += 1
            _ = await activeRead.task.value
            return
        }

        readGeneration &+= 1
        let generation = readGeneration
        let reader = readQuota
        let task = Task<Result<AntigravityQuotaSnapshot, AntigravityCLIClientError>, Never> {
            do {
                return Result.success(try await reader())
            } catch let error as AntigravityCLIClientError {
                return Result.failure(error)
            } catch is CancellationError {
                return Result.failure(.cancelled)
            } catch {
                return Result.failure(.providerUnavailable)
            }
        }
        activeRead = ActiveRead(generation: generation, task: task)
        let result = await task.value
        guard activeRead?.generation == generation else { return }
        activeRead = nil
        completedReadCount += 1
        apply(result)
        if reschedule { scheduleNextCycle() }
    }

    private func apply(
        _ result: Result<AntigravityQuotaSnapshot, AntigravityCLIClientError>
    ) {
        switch result {
        case let .success(quota):
            automaticRefreshSuspended = false
            let next = Self.makeSnapshot(
                quota,
                freshness: .fresh,
                state: .ready,
                failure: nil,
                capturedAt: now()
            )
            lastGood = next
            replace(next)
        case let .failure(error):
            if [.loginRequired, .unsupportedVersion, .unsupportedSchema,
                .invalidOperationalEnvelope, .invalidBucket,
                .duplicateBucketIdentity,
                .notInstalled, .untrustedExecutable].contains(error) {
                automaticRefreshSuspended = true
                lastGood = nil
                let state: AgentConnectorState = switch error {
                case .loginRequired:
                    .authenticationRequired
                case .unsupportedVersion, .unsupportedSchema,
                     .invalidOperationalEnvelope, .invalidBucket,
                     .duplicateBucketIdentity,
                     .notInstalled, .untrustedExecutable:
                    .unsupported
                default:
                    .failed
                }
                replace(Self.unavailableSnapshot(
                    state: state,
                    failure: Self.safeFailure(for: error),
                    capturedAt: now()
                ))
            } else if let lastGood {
                replace(Self.retainedSnapshot(
                    lastGood,
                    at: now(),
                    failure: Self.safeFailure(for: error)
                ))
            } else {
                replace(Self.unavailableSnapshot(
                    state: .failed,
                    failure: Self.safeFailure(for: error),
                    capturedAt: now()
                ))
            }
        }
    }

    private func applyCapabilityFailure(_ error: AntigravityCLIClientError) {
        let state: AgentConnectorState = switch error {
        case .unsupportedVersion, .unsupportedSchema,
             .invalidOperationalEnvelope, .invalidBucket,
             .duplicateBucketIdentity, .notInstalled, .untrustedExecutable:
            .unsupported
        case .loginRequired:
            .authenticationRequired
        default:
            .failed
        }
        replace(Self.unavailableSnapshot(
            state: state,
            failure: Self.safeFailure(for: error),
            capturedAt: now()
        ))
    }

    private func refreshAge() async {
        guard let lastGood else { return }
        let retained = Self.retainedSnapshot(
            lastGood,
            at: now(),
            failure: snapshot.safeFailure
        )
        if retained.freshness != snapshot.freshness {
            replace(retained)
        }
    }

    private func scheduleNextCycle() {
        cancelScheduler()
        guard started, !automaticRefreshSuspended else { return }
        schedulerGeneration &+= 1
        let generation = schedulerGeneration
        let sleeper = sleep
        let interval = refreshInterval
        schedulerTask = Task { [weak self] in
            do {
                try await sleeper(interval)
            } catch {
                return
            }
            await self?.scheduledFire(generation: generation)
        }
    }

    private func scheduledFire(generation: UInt64) async {
        guard schedulerGeneration == generation, started else { return }
        schedulerTask = nil
        guard await autoRefreshEnabled() else { return }
        scheduledCycleCount += 1
        await requestRead(reschedule: true)
    }

    private func cancelScheduler() {
        schedulerGeneration &+= 1
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    private func disconnect() async {
        started = false
        automaticRefreshSuspended = false
        cancelScheduler()
        initialReadGeneration &+= 1
        initialReadTask?.cancel()
        initialReadTask = nil
        activeRead?.task.cancel()
        if let task = activeRead?.task { _ = await task.value }
        activeRead = nil
        lastGood = nil
        replace(Self.unavailableSnapshot(
            state: .inactive,
            failure: nil,
            capturedAt: now()
        ))
    }

    private func replace(_ next: AgentUsageSnapshot) {
        snapshot = next
        for continuation in continuations.values {
            continuation.yield(next)
        }
    }

    private func removeContinuation(_ subscriptionID: UUID) {
        continuations[subscriptionID] = nil
    }

    private static func makeSnapshot(
        _ quota: AntigravityQuotaSnapshot,
        freshness: AgentConnectorFreshness,
        state: AgentConnectorState,
        failure: AgentSafeFailure?,
        capturedAt: Date
    ) -> AgentUsageSnapshot {
        let windows = quota.buckets.map {
            AgentRateLimitWindow(
                id: $0.id,
                kind: .other,
                displayLabel: $0.displayLabel,
                usedPercent: nil,
                remainingPercent: $0.remainingPercent,
                isUnlimited: false,
                resetsAt: $0.resetsAt
            )
        }
        let account = AgentUsageChannel(
            id: .account,
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: quota.sourceVersion,
            scopes: [.account],
            provenance: .providerReported,
            freshness: freshness,
            capturedAt: quota.observedAt,
            coverageNote: nil,
            rateLimitWindows: windows,
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: failure
        )
        return AgentUsageSnapshot(
            id: connectorID,
            providerName: "Google Antigravity",
            state: state,
            capturedAt: capturedAt,
            lastSuccessfulAt: quota.observedAt,
            freshness: freshness,
            channels: [account],
            capabilities: capabilities,
            safeFailure: failure
        )
    }

    private static func retainedSnapshot(
        _ lastGood: AgentUsageSnapshot,
        at now: Date,
        failure: AgentSafeFailure?
    ) -> AgentUsageSnapshot {
        let age = now.timeIntervalSince(lastGood.lastSuccessfulAt ?? .distantPast)
        let freshness: AgentConnectorFreshness
        let state: AgentConnectorState
        if failure != nil, age <= staleInterval {
            // A failed current read can retain the last valid value, but it
            // must never continue to present that value as current/Fresh.
            freshness = .cached
            state = .ready
        } else if age <= freshnessInterval {
            freshness = .fresh
            state = .ready
        } else if age <= staleInterval {
            freshness = .cached
            state = .ready
        } else {
            freshness = .stale
            state = .stale
        }
        let channels = lastGood.channels.map {
            AgentUsageChannel(
                id: $0.id,
                sourceTier: $0.sourceTier,
                sourceVersion: $0.sourceVersion,
                scopes: $0.scopes,
                provenance: $0.provenance,
                freshness: freshness,
                capturedAt: $0.capturedAt,
                coverageNote: $0.coverageNote,
                rateLimitWindows: $0.rateLimitWindows,
                accountMetrics: nil,
                localActivityMetrics: nil,
                safeFailure: failure
            )
        }
        return AgentUsageSnapshot(
            id: connectorID,
            providerName: "Google Antigravity",
            state: state,
            capturedAt: now,
            lastSuccessfulAt: lastGood.lastSuccessfulAt,
            freshness: freshness,
            channels: channels,
            capabilities: capabilities,
            safeFailure: failure,
            selectedWindowID: lastGood.selectedWindowID
        )
    }

    private static func unavailableSnapshot(
        state: AgentConnectorState,
        failure: AgentSafeFailure?,
        capturedAt: Date
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: connectorID,
            providerName: "Google Antigravity",
            state: state,
            capturedAt: capturedAt,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: capabilities,
            safeFailure: failure
        )
    }

    private static func safeFailure(
        for error: AntigravityCLIClientError
    ) -> AgentSafeFailure {
        switch error {
        case .loginRequired:
            .authorizationRequired
        case .timedOut:
            .timedOut
        case .unsupportedVersion, .unsupportedSchema,
             .invalidOperationalEnvelope, .invalidBucket,
             .duplicateBucketIdentity, .untrustedExecutable:
            .unsupported
        case .malformedOutput, .noValidQuota:
            .malformedResponse
        case .processExited:
            .processExited
        case .notInstalled, .providerUnavailable, .cancelled, .outputTooLarge:
            .unavailable
        }
    }
}
