import Foundation

/// Provider adapter for the accepted G1 Codex implementation. All Codex
/// transport, child-process ownership, and local metadata reading remain here;
/// the registry and shared presentation store see only `AgentUsageSnapshot`.
actor CodexUsageConnector: AgentUsageConnector {
    static let connectorID = AgentConnectorID(rawValue: "codex.local")!

    nonisolated let id = CodexUsageConnector.connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: CodexUsageConnector.connectorID,
        providerName: "Codex",
        officialSource: "Codex app-server and privacy-safe local metadata",
        sourceTier: .officialLocalService,
        sourceVersion: "m1a-g1",
        supportedScopes: [.account, .device, .session, .task],
        capabilities: [.connect, .reconnect, .refresh, .disconnect, .localActivity, .rateLimits, .accountUsage, .sanitizedLastValidRestore],
        configurationRequirements: [.userAuthorization, .officialManagedSession, .privacySafeLocalMetadataAccess],
        privacyAllowlist: ["account availability", "rate limits", "aggregate account usage", "metadata-only local aggregates"],
        supportsRestore: true,
        supportsUninstall: true,
        unsupportedFields: ["account identity", "credentials", "conversation content", "source code", "raw payload"],
        expectedRuntime: .activeOfficialApplicationCLIOrService,
        localSourceClass: .admittedStructuredLocal,
        authenticationMethod: .existingLocalSession,
        usageReadContract: .currentStructuredLocalRead,
        loginAssistance: .existingSessionOnly
    )!

    private let client: any CodexUsageClient
    private let localActivityReader: any CodexLocalActivityReading
    private let beforeProviderRefresh: @Sendable () async -> Void
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var latestProvider: CodexLiveUsage?
    private var latestLocal: CodexLocalActivitySnapshot?
    private var latestFailure: AgentSafeFailure?
    private var lastSuccessfulAt: Date?
    private var state: AgentConnectorState = .inactive
    private var activeCommand = false
    private var pendingTransportRecovery = false
    private var lifecycleGeneration: UInt64 = 0
    private var localActivityPublicationTask: Task<Void, Never>?
    private var localReadGeneration = 0
    /// Exactly one observer is retained for the built-in local metadata
    /// reader. It emits only debounced invalidations; it cannot initiate an
    /// account or app-server request.
    private var localActivityObserver: CodexLocalActivityObserver?
    private var localActivityRefreshTask: Task<Void, Never>?
    /// The connector owns the one consumer of the client's sanitized
    /// notification stream. A provider event is an invalidation only; it
    /// routes through the same serialized refresh path as every other cause.
    private var providerEventTask: Task<Void, Never>?
    private var providerRefreshTask: Task<Void, Never>?
    private var providerRefreshToken: UUID?
    private var stoppedProviderEventTask: Task<Void, Never>?
    /// Identifies the retained provider-event consumer. An older cancelled
    /// consumer can finish after reconnect has installed its replacement, so
    /// its cleanup must not clear the replacement task.
    private var providerEventObservationGeneration: UInt64 = 0

    init(
        client: any CodexUsageClient = CodexAppServerClient(),
        localActivityReader: any CodexLocalActivityReading = CodexLocalActivityReader(),
        beforeProviderRefresh: @escaping @Sendable () async -> Void = {}
    ) {
        self.client = client
        self.localActivityReader = localActivityReader
        self.beforeProviderRefresh = beforeProviderRefresh
    }

    func probe() async -> AgentConnectorProbe {
        let current = await client.connectionState()
        if state == .inactive { state = Self.normalizedState(current) }
        return AgentConnectorProbe(state: state, safeFailure: latestFailure)
    }

    func start() async {
        startLocalActivityObservationIfNeeded()
        startProviderEventObservationIfNeeded()
        publish()
    }

    func refresh() async { await run(kind: .refresh(trigger: .manual)) }

    func refresh(trigger: CodexRefreshTrigger) async {
        await run(kind: .refresh(trigger: trigger))
    }

    func perform(_ command: AgentConnectorCommand) async {
        switch command {
        case .connect: await run(kind: .connect(trigger: .reconnect))
        case .reconnect:
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            activeCommand = false
            pendingTransportRecovery = false
            stopLocalActivityObservation()
            stopProviderEventObservation()
            await client.disconnect()
            guard generation == lifecycleGeneration else { return }
            await run(kind: .connect(trigger: .reconnect))
        case .refresh: await run(kind: .refresh(trigger: .manual))
        case .disconnect: await stop()
        }
    }

    func stop() async {
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        activeCommand = false
        pendingTransportRecovery = false
        stopLocalActivityObservation()
        stopProviderEventObservation()
        state = .inactive
        latestFailure = nil
        publish()
        await client.disconnect()
        guard generation == lifecycleGeneration else { return }
        state = .inactive
        latestFailure = nil
        publish()
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(makeSnapshot())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation() }
            }
        }
    }

    func currentSnapshot() async -> AgentUsageSnapshot { makeSnapshot() }

    private enum RunKind {
        case connect(trigger: CodexRefreshTrigger)
        case refresh(trigger: CodexRefreshTrigger)
    }

    private func run(kind: RunKind) async {
        guard !activeCommand else { return }
        activeCommand = true
        let lifecycle = lifecycleGeneration
        defer {
            if lifecycle == lifecycleGeneration {
                activeCommand = false
                pendingTransportRecovery = false
            }
        }
        startLocalActivityObservationIfNeeded()
        startProviderEventObservationIfNeeded()
        var nextKind = kind
        repeat {
            pendingTransportRecovery = false
            await performRead(kind: nextKind, lifecycle: lifecycle)
            guard lifecycle == lifecycleGeneration,
                  pendingTransportRecovery,
                  latestFailure == nil || latestFailure == .processExited || latestFailure == .timedOut
            else { return }
            // A recovered child invalidates the interrupted read. Coalesce
            // its notifications into one serial follow-up owned by this run;
            // another attempt requires another external recovery event.
            nextKind = .refresh(trigger: .providerEvent)
        } while true
    }

    private func performRead(kind: RunKind, lifecycle: UInt64) async {
        state = .waitingForFirstResponse
        publish()

        let reader = localActivityReader
        let now = Date()
        localReadGeneration += 1
        let generation = localReadGeneration
        let local = Task.detached(priority: .utility) {
            reader.read(now: now)
        }

        do {
            let provider: CodexLiveUsage
            switch kind {
            case .connect:
                let available = try await client.checkLocalAccountAvailability()
                guard lifecycle == lifecycleGeneration else { return }
                guard available else {
                    latestFailure = .authorizationRequired
                    state = .authenticationRequired
                    latestLocal = await local.value
                    guard lifecycle == lifecycleGeneration else { return }
                    publish()
                    return
                }
                provider = try await client.fetchUsageAfterVerifiedAccount()
            case .refresh(let trigger):
                do {
                    provider = try await client.fetchUsage(trigger: trigger)
                } catch let error as CodexUsageClientError {
                    guard lifecycle == lifecycleGeneration else { return }
                    guard error.failure == .processExited,
                          !pendingTransportRecovery,
                          await client.supportsOwnedProcessRecovery()
                    else { throw error }
                    guard lifecycle == lifecycleGeneration else { return }
                    guard !pendingTransportRecovery else { throw error }
                    // A retained stdio child can disappear between otherwise
                    // valid refreshes.  Its session has already been closed
                    // by the client, so one fresh account-first read can
                    // safely recreate only that owned local child.
                    await client.disconnect()
                    guard lifecycle == lifecycleGeneration else { return }
                    provider = try await client.fetchUsage(trigger: .reconnect)
                }
            }
            guard lifecycle == lifecycleGeneration else { return }
            latestProvider = provider
            latestFailure = nil
            lastSuccessfulAt = provider.providerCapturedAt
            state = .ready
            publish()
            let previousPublication = localActivityPublicationTask
            localActivityPublicationTask = Task { [weak self] in
                let activity = await local.value
                await self?.acceptLocalActivity(activity, generation: generation)
                await previousPublication?.value
            }
        } catch {
            guard lifecycle == lifecycleGeneration else { return }
            latestLocal = await local.value
            guard lifecycle == lifecycleGeneration else { return }
            let currentState = await client.connectionState()
            guard lifecycle == lifecycleGeneration else { return }
            latestFailure = Self.safeFailure(from: error)
            state = latestProvider == nil ? Self.normalizedState(currentState) : .stale
            if state == .ready { state = .stale }
            publish()
        }
    }

    private func acceptLocalActivity(_ activity: CodexLocalActivitySnapshot, generation: Int) {
        guard generation == localReadGeneration else { return }
        latestLocal = activity
        publish()
    }

    /// Joins only the owned local-result publication, never a provider read.
    func awaitPendingLocalActivityPublication() async {
        await localActivityPublicationTask?.value
    }

    private func startLocalActivityObservationIfNeeded() {
        guard localActivityObserver == nil,
              let provider = localActivityReader as? any CodexLocalActivityObservationProviding
        else { return }
        let observer = provider.makeLocalActivityObserver { [weak self] in
            Task { await self?.scheduleObservedLocalActivityRefresh() }
        }
        localActivityObserver = observer
        observer.start()
    }

    private func stopLocalActivityObservation() {
        localReadGeneration &+= 1
        localActivityRefreshTask?.cancel()
        localActivityRefreshTask = nil
        localActivityObserver?.stop()
        localActivityObserver = nil
    }

    private func startProviderEventObservationIfNeeded() {
        guard providerEventTask == nil else { return }
        let client = client
        providerEventObservationGeneration &+= 1
        let generation = providerEventObservationGeneration
        providerEventTask = Task { [weak self] in
            let stream = await client.eventStream()
            for await event in stream {
                guard !Task.isCancelled else { return }
                await self?.receiveProviderEvent(event, observationGeneration: generation)
            }
            await self?.clearProviderEventObservation(generation: generation)
        }
    }

    private func stopProviderEventObservation() {
        providerEventObservationGeneration &+= 1
        let refresh = providerRefreshTask
        refresh?.cancel()
        providerRefreshTask = nil
        providerRefreshToken = nil
        let task = providerEventTask
        task?.cancel()
        if task != nil || refresh != nil {
            let previous = stoppedProviderEventTask
            stoppedProviderEventTask = Task {
                await previous?.value
                await task?.value
                await refresh?.value
            }
        }
        providerEventTask = nil
    }

    /// Teardown join after disconnect: both the consumer and its owned read.
    func awaitPendingProviderEventObservationTermination() async {
        await stoppedProviderEventTask?.value
    }

    /// Joins the currently reserved event read, without initiating work.
    func awaitPendingProviderEventRefresh() async {
        await providerRefreshTask?.value
    }

    private func clearProviderEventObservation(generation: UInt64) {
        guard generation == providerEventObservationGeneration else { return }
        providerEventTask = nil
    }

    private func receiveProviderEvent(_ event: CodexAppServerEvent, observationGeneration: UInt64) async {
        guard observationGeneration == providerEventObservationGeneration else { return }
        if case .transportUnavailable(let failure) = event {
            latestFailure = Self.safeFailure(from: CodexUsageClientError(failure))
            state = latestProvider == nil ? .failed : .stale
            publish()
            return
        }
        if case .transportRecovered = event, activeCommand {
            pendingTransportRecovery = true
            return
        }
        // Ordinary notification bursts still collapse into the current read.
        // Recovery alone must survive an interrupted in-flight request.
        guard !activeCommand else { return }
        if providerRefreshTask != nil {
            if case .transportRecovered = event { pendingTransportRecovery = true }
            return
        }
        scheduleProviderRefresh(observationGeneration: observationGeneration)
    }

    private func scheduleProviderRefresh(observationGeneration: UInt64) {
        guard providerRefreshTask == nil else { return }
        let token = UUID()
        let lifecycle = lifecycleGeneration
        let beforeProviderRefresh = beforeProviderRefresh
        providerRefreshToken = token
        providerRefreshTask = Task { [weak self] in
            await beforeProviderRefresh()
            await self?.runProviderRefresh(token: token, lifecycle: lifecycle, observationGeneration: observationGeneration)
        }
    }

    private func runProviderRefresh(token: UUID, lifecycle: UInt64, observationGeneration: UInt64) async {
        guard !Task.isCancelled, lifecycle == lifecycleGeneration,
              observationGeneration == providerEventObservationGeneration,
              providerRefreshToken == token else { return }
        guard !activeCommand else {
            // A manual command can acquire the lane while this task is queued.
            // Its pending recovery belongs to that command and must survive.
            providerRefreshTask = nil
            providerRefreshToken = nil
            return
        }
        await run(kind: .refresh(trigger: .providerEvent))
        guard lifecycle == lifecycleGeneration, providerRefreshToken == token else { return }
        providerRefreshTask = nil
        providerRefreshToken = nil
        // A recovery arriving after run completes but before this task clears
        // its ownership still gets one serial read, never an error-only retry.
        if pendingTransportRecovery,
           latestFailure == nil || latestFailure == .processExited || latestFailure == .timedOut {
            pendingTransportRecovery = false
            scheduleProviderRefresh(observationGeneration: observationGeneration)
        }
    }

    /// A filesystem event refreshes the local aggregate only. The one task is
    /// deliberately coalesced across a debounced event burst, never touches
    /// the provider client, and is invalidated on connector stop.
    private func scheduleObservedLocalActivityRefresh() {
        guard localActivityRefreshTask == nil else { return }
        localReadGeneration &+= 1
        let generation = localReadGeneration
        let reader = localActivityReader
        localActivityRefreshTask = Task { [weak self] in
            let activity = await Task.detached(priority: .utility) {
                reader.read(now: Date())
            }.value
            await self?.acceptObservedLocalActivity(activity, generation: generation)
        }
    }

    private func acceptObservedLocalActivity(
        _ activity: CodexLocalActivitySnapshot,
        generation: Int
    ) {
        localActivityRefreshTask = nil
        guard generation == localReadGeneration else { return }
        latestLocal = activity
        publish()
    }

    private func makeSnapshot() -> AgentUsageSnapshot {
        let now = Date()
        var channels: [AgentUsageChannel] = []
        if let provider = latestProvider {
            channels.append(Self.accountChannel(from: provider, freshness: state == .stale ? .stale : .fresh, safeFailure: latestFailure))
        } else if latestFailure != nil || state == .authenticationRequired {
            channels.append(AgentUsageChannel(
                id: .account,
                sourceTier: .officialLocalService,
                sourceVersion: descriptor.sourceVersion,
                scopes: [.account],
                provenance: .providerReported,
                freshness: .unavailable,
                capturedAt: nil,
                coverageNote: nil,
                rateLimitWindows: [],
                accountMetrics: nil,
                localActivityMetrics: nil,
                safeFailure: latestFailure
            ))
        }
        if let activity = latestLocal {
            channels.append(Self.localChannel(from: activity, freshness: .fresh))
        }
        // Account data is authoritative for the monitor's overall freshness.
        // A current local aggregate can remain useful while the last account
        // read is stale, but it must not make the account-backed monitor look
        // freshly verified.
        let overallFreshness: AgentConnectorFreshness
        if let account = channels.first(where: { $0.id == .account }) {
            overallFreshness = account.freshness
        } else if channels.contains(where: { $0.freshness == .fresh }) {
            overallFreshness = .fresh
        } else if channels.contains(where: { $0.freshness == .stale }) {
            overallFreshness = .stale
        } else {
            overallFreshness = .unavailable
        }
        return AgentUsageSnapshot(
            id: id,
            providerName: descriptor.providerName,
            state: state,
            capturedAt: now,
            lastSuccessfulAt: lastSuccessfulAt,
            freshness: overallFreshness,
            channels: channels,
            capabilities: descriptor.capabilities,
            safeFailure: latestFailure
        )
    }

    private func publish() { continuation?.yield(makeSnapshot()) }
    private func clearContinuation() { continuation = nil }

    private static func accountChannel(
        from usage: CodexLiveUsage,
        freshness: AgentConnectorFreshness,
        safeFailure: AgentSafeFailure?
    ) -> AgentUsageChannel {
        var windows = usage.rateLimits.displayWindows.map { window in
            AgentRateLimitWindow(
                // Preserve the provider's stable window identity. The
                // normalized kind is a classification, not an identifier.
                id: window.id,
                kind: window.kind == .fiveHour ? .fiveHour : (window.kind == .sevenDay ? .sevenDay : .other),
                usedPercent: window.usedPercent.isFinite ? window.usedPercent : nil,
                isUnlimited: window.kind == .fiveHour && (window.creditsUnlimited == true || usage.rateLimits.creditsUnlimited == true),
                resetsAt: window.resetsAt
            )
        }
        // Preserve the accepted G1 account contract: an authoritative weekly
        // window without a five-hour window represents the special unlimited
        // five-hour state.  The account-level credits grant is an additional
        // explicit source of that same state.
        if !windows.contains(where: { $0.kind == .fiveHour }),
           (usage.rateLimits.creditsUnlimited == true || windows.contains(where: { $0.kind == .sevenDay })) {
            windows.insert(
                AgentRateLimitWindow(
                    id: "five-hour-unlimited",
                    kind: .fiveHour,
                    usedPercent: nil,
                    isUnlimited: true,
                    resetsAt: nil
                ),
                at: 0
            )
        }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: usage.providerCapturedAt)) ?? usage.providerCapturedAt
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let sevenDayTokens = usage.dailyUsage.map { buckets in
            buckets.reduce(Int64(0)) { total, bucket in
                guard let day = formatter.date(from: bucket.startDate), day >= cutoff else { return total }
                return total + bucket.tokens
            }
        }
        return AgentUsageChannel(
            id: .account,
            sourceTier: .officialLocalService,
            sourceVersion: "app-server",
            scopes: [.account],
            provenance: .providerReported,
            freshness: freshness,
            capturedAt: usage.providerCapturedAt,
            coverageNote: nil,
            rateLimitWindows: windows,
            accountMetrics: AgentAccountMetrics(
                planLabel: usage.rateLimits.planType,
                availableResets: usage.availableResetCount,
                lifetimeTokens: usage.lifetimeTokens,
                sevenDayTokens: sevenDayTokens
            ),
            localActivityMetrics: nil,
            safeFailure: safeFailure
        )
    }

    private static func localChannel(
        from activity: CodexLocalActivitySnapshot,
        freshness: AgentConnectorFreshness
    ) -> AgentUsageChannel {
        let availability = activity.availability == .available
        let estimate = activity.apiEquivalentCost
        let observed = estimate?.observedTokens ?? 0
        let coverage = observed > 0 ? Int((Double(estimate?.pricedTokens ?? 0) / Double(observed) * 100).rounded()) : nil
        return AgentUsageChannel(
            id: .localActivity,
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "metadata-tail-v1",
            scopes: [.device, .session, .task],
            provenance: .locallyEstimated,
            freshness: availability ? freshness : .unavailable,
            capturedAt: activity.capturedAt,
            coverageNote: availability ? "aggregate metadata coverage" : nil,
            rateLimitWindows: [],
            accountMetrics: nil,
            localActivityMetrics: AgentLocalActivityMetrics(
                recentTaskCount: availability ? activity.tasks.count : nil,
                recentTaskTokens: availability ? activity.tasks.map(\.totalTokens) : [],
                recentTaskCapturedAt: availability ? activity.tasks.map(\.modifiedAt) : [],
                sessionTokens: availability ? activity.tasks.reduce(0) { $0 + $1.totalTokens } : nil,
                estimatedSevenDayUSD: estimate?.sevenDayUSD,
                estimatedLifetimeUSD: estimate?.lifetimeUSD,
                coveragePercent: coverage,
                recognizedModelCount: estimate?.modelNames.count
            ),
            safeFailure: nil
        )
    }

    private static func normalizedState(_ state: CodexConnectionState) -> AgentConnectorState {
        switch state {
        case .notAuthorizedByMonitor, .idle: .inactive
        case .authorizationRequired, .officialCodexSignInRequired: .authenticationRequired
        case .ready: .ready
        case .staleWithPreviousRealData: .stale
        case .recoverableFailure, .blockedFailure: .failed
        default: .waitingForFirstResponse
        }
    }

    private static func safeFailure(from error: Error) -> AgentSafeFailure {
        if error is CodexTransportReplacementInterrupted { return .processExited }
        guard let failure = (error as? CodexUsageClientError)?.failure else { return .unknown }
        switch failure {
        case .accountAuthorizationRequired, .accountAuthorizationCanceled, .accountAuthorizationFailed:
            return .authorizationRequired
        case .processExited, .processLaunchFailed: return .processExited
        case .initializationTimedOut, .accountCheckTimedOut, .requestTimedOut: return .timedOut
        case .protocolIncompatible: return .unsupported
        case .malformedResponse: return .malformedResponse
        case .codexApplicationNotFound, .codexExecutableNotFound, .codexExecutableNotExecutable:
            return .unavailable
        default: return .unknown
        }
    }
}
