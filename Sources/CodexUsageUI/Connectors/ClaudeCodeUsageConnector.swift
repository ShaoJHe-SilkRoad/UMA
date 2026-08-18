import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation

enum ClaudeConnectorLifecycleState: Equatable, Sendable {
    case disconnected
    case checking
    case waitingForUsagePage
    case websiteAccessRequired
    case signInRequired
    case waitingForSafari
    case fresh(Date)
    case cached(Date)
    case stale(Date)
    case companionDisabled
    case companionOutdated
    case unsupportedBrowser
    case browserUnavailable
    case nativeHostMissing
    case nativeHostMismatched
    case routeChanged
    case failed
}

enum ClaudeBrowserCompanionHealth: Equatable, Sendable {
    case ready
    case disabled
    case outdated
    case unsupportedBrowser
    case browserUnavailable
    case nativeHostMissing
    case nativeHostMismatched
}

enum ClaudeBrowserInboundEvent: Sendable {
    case observation(Result<ClaudeBrowserObservationEnvelope, ClaudeBrowserBridgeError>)
    case automation(ClaudeBrowserAutomationEvent)
}

enum ClaudeBrowserAutomaticDispatchResult: Equatable, Sendable {
    case dispatched
    case browserUnavailable
    case unsupportedBrowser
    case companionUnavailable
}

struct ClaudeBrowserProductionIntegration: Sendable {
    typealias MessageHandler = @Sendable (ClaudeBrowserInboundEvent) async -> Void

    let startListening: @Sendable (@escaping MessageHandler) async -> Void
    let stopListening: @Sendable () async -> Void
    let checkHealth: @Sendable () async -> ClaudeBrowserCompanionHealth
    let openUsagePage: @Sendable () async -> Bool
    let repairCompanion: @Sendable () async -> ClaudeBrowserCompanionHealth
    let requestAutomaticRefresh: @Sendable (String, Bool) async -> ClaudeBrowserAutomaticDispatchResult
    let closeOwnedUsageTab: @Sendable (String) async -> Void

    init(
        startListening: @escaping @Sendable (@escaping MessageHandler) async -> Void,
        stopListening: @escaping @Sendable () async -> Void,
        checkHealth: @escaping @Sendable () async -> ClaudeBrowserCompanionHealth,
        openUsagePage: @escaping @Sendable () async -> Bool,
        repairCompanion: @escaping @Sendable () async -> ClaudeBrowserCompanionHealth,
        requestAutomaticRefresh: @escaping @Sendable (String, Bool) async -> ClaudeBrowserAutomaticDispatchResult = { _, _ in .unsupportedBrowser },
        closeOwnedUsageTab: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.startListening = startListening
        self.stopListening = stopListening
        self.checkHealth = checkHealth
        self.openUsagePage = openUsagePage
        self.repairCompanion = repairCompanion
        self.requestAutomaticRefresh = requestAutomaticRefresh
        self.closeOwnedUsageTab = closeOwnedUsageTab
    }

    static func unavailable() -> Self {
        Self(
            startListening: { _ in },
            stopListening: {},
            checkHealth: { .nativeHostMissing },
            openUsagePage: { false },
            repairCompanion: { .nativeHostMissing },
            requestAutomaticRefresh: { _, _ in .companionUnavailable },
            closeOwnedUsageTab: { _ in }
        )
    }
}

struct ClaudeBrowserConnectorDiagnostics: Equatable, Sendable {
    let acceptedObservationCount: Int
    let rejectedObservationCount: Int
    let pageOpenCount: Int
    let coalescedActionCount: Int
    let listenerStartCount: Int
    let automaticDispatchCount: Int
    let scheduledCycleCount: Int
    let automaticRefreshInFlight: Bool
    let schedulerActive: Bool
}

actor ClaudeCodeUsageConnector: AgentUsageConnector {
    typealias ConsentReader = @Sendable () async -> Bool
    typealias ConsentClearer = @Sendable () async -> Void
    typealias CacheReader = @Sendable () async -> Data?
    typealias CacheWriter = @Sendable (Data) async -> Void
    typealias CacheClearer = @Sendable () async -> Void
    typealias Now = @Sendable () -> Date
    typealias PreferenceReader = @Sendable () async -> Bool
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    static let connectorID = AgentConnectorID(rawValue: "claude.browserSync")!
    static let freshnessInterval: TimeInterval = 5 * 60
    static let automaticRefreshInterval: TimeInterval = 5 * 60
    static let minimumAutomaticRefreshInterval: TimeInterval = 3 * 60
    static let automaticRefreshTimeout: TimeInterval = 45
    static let maximumRetainedAge: TimeInterval = 30 * 60
    static let maximumFutureSkew: TimeInterval = 30

    private static let capabilities: Set<AgentConnectorCapability> = [
        .connect,
        .reconnect,
        .refresh,
        .disconnect,
        .rateLimits,
        .sanitizedLastValidRestore,
        .automaticRefresh,
        .localActivity,
    ]

    /// Local activity is secondary analytics and is rescanned at most this
    /// often. It never gates, delays, or influences an account observation.
    static let localActivityRefreshInterval: TimeInterval = 5 * 60

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "Claude Code",
        officialSource: "Claude official Usage page · Browser Sync · Experimental",
        sourceTier: .authorizedReadOnlyRemote,
        sourceVersion: "browser-2",
        supportedScopes: [.account, .device, .session, .task],
        capabilities: capabilities,
        configurationRequirements: [
            .userAuthorization,
            .officialManagedSession,
            .explicitlyAuthorizedReadOnlyRemoteAccess,
        ],
        privacyAllowlist: [
            "fiveHourUsedPercentage",
            "fiveHourResetAt",
            "sevenDayUsedPercentage",
            "sevenDayResetAt",
            "modelSpecificWeeklyUsedPercentage",
            "modelSpecificWeeklyResetAt",
            "observedAt",
            "localActivityTokenCounts",
            "localActivityModelIdentifier",
            "localActivityTimestamp",
        ],
        supportsRestore: false,
        supportsUninstall: false,
        unsupportedFields: [
            "accountIdentity",
            "billing",
            "payment",
            "credentials",
            "tokens",
            "cookies",
            "browserSession",
            "prompt",
            "response",
            "transcript",
            "project",
            "sourceCode",
            "rawHTML",
            "rawDOM",
            "rawJSON",
        ],
        expectedRuntime: .none,
        localSourceClass: .browserCompanionUsage,
        authenticationMethod: .systemBrowserSession,
        usageReadContract: .currentBrowserCompanionUsageRead,
        loginAssistance: .none
    )!

    private let integration: ClaudeBrowserProductionIntegration
    private let hasConsent: ConsentReader
    private let clearConsent: ConsentClearer
    private let readCache: CacheReader
    private let writeCache: CacheWriter
    private let clearCache: CacheClearer
    private let now: Now
    private let autoRefreshEnabled: PreferenceReader
    private let allowSafariLaunch: PreferenceReader
    private let sleep: Sleeper

    /// Nil in tests and wherever local analytics are not wanted, which keeps
    /// every other construction path off the filesystem.
    private let localActivityReader: (any ClaudeLocalActivityReading)?
    private var cachedLocalActivity: ClaudeLocalActivitySnapshot?
    private var localActivityRefreshedAt: Date?
    private var localActivityRefreshInFlight = false

    private var snapshot: AgentUsageSnapshot
    private var lastGood: AgentUsageSnapshot?
    private var priorSessionCache: AgentUsageSnapshot?
    private var currentSessionValidated = false
    private var lifecycle: ClaudeConnectorLifecycleState = .disconnected
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var listenerStarted = false
    private var cacheLoaded = false
    private var actionInFlight = false
    private var retentionTask: Task<Void, Never>?
    private var automaticRefreshTask: Task<Void, Never>?
    private var automaticTimeoutTask: Task<Void, Never>?
    private var automaticRequestID: String?
    private var automaticRefreshInFlight = false
    private var acceptedObservationCount = 0
    private var acceptedObservationIDs: Set<String> = []
    private var acceptedObservationIDOrder: [String] = []
    private var rejectedObservationCount = 0
    private var pageOpenCount = 0
    private var coalescedActionCount = 0
    private var listenerStartCount = 0
    private var automaticDispatchCount = 0
    private var scheduledCycleCount = 0

    init(
        integration: ClaudeBrowserProductionIntegration,
        hasConsent: @escaping ConsentReader,
        clearConsent: @escaping ConsentClearer = {},
        readCache: @escaping CacheReader = { nil },
        writeCache: @escaping CacheWriter = { _ in },
        clearCache: @escaping CacheClearer = {},
        now: @escaping Now = Date.init,
        autoRefreshEnabled: @escaping PreferenceReader = { false },
        allowSafariLaunch: @escaping PreferenceReader = { false },
        sleep: @escaping Sleeper = { interval in
            try await Task.sleep(for: .seconds(interval))
        },
        localActivityReader: (any ClaudeLocalActivityReading)? = nil
    ) {
        self.localActivityReader = localActivityReader
        self.integration = integration
        self.hasConsent = hasConsent
        self.clearConsent = clearConsent
        self.readCache = readCache
        self.writeCache = writeCache
        self.clearCache = clearCache
        self.now = now
        self.autoRefreshEnabled = autoRefreshEnabled
        self.allowSafariLaunch = allowSafariLaunch
        self.sleep = sleep
        snapshot = Self.unavailableSnapshot(
            state: .authenticationRequired,
            failure: .authorizationRequired,
            capturedAt: now()
        )
    }

    static func production(
        integration: ClaudeBrowserProductionIntegration = .unavailable(),
        hasConsent: @escaping ConsentReader = { false },
        clearConsent: @escaping ConsentClearer = {},
        readCache: @escaping CacheReader = { nil },
        writeCache: @escaping CacheWriter = { _ in },
        clearCache: @escaping CacheClearer = {},
        autoRefreshEnabled: @escaping PreferenceReader = { false },
        allowSafariLaunch: @escaping PreferenceReader = { false },
        localActivityReader: (any ClaudeLocalActivityReading)? = ClaudeLocalActivityReader()
    ) -> ClaudeCodeUsageConnector {
        ClaudeCodeUsageConnector(
            integration: integration,
            hasConsent: hasConsent,
            clearConsent: clearConsent,
            readCache: readCache,
            writeCache: writeCache,
            clearCache: clearCache,
            autoRefreshEnabled: autoRefreshEnabled,
            allowSafariLaunch: allowSafariLaunch,
            localActivityReader: localActivityReader
        )
    }

    func permitsRead(for trigger: ProviderEligibilityScanTrigger) async -> Bool {
        _ = trigger
        return await hasConsent()
    }

    func probe() async -> AgentConnectorProbe {
        guard await hasConsent() else {
            return AgentConnectorProbe(
                state: .authenticationRequired,
                safeFailure: .authorizationRequired
            )
        }
        await loadSanitizedCacheIfNeeded()
        await refreshAge()
        let health = await integration.checkHealth()
        guard health == .ready else {
            apply(health)
            if snapshot.hasValidData {
                return AgentConnectorProbe(
                    state: snapshot.state,
                    safeFailure: snapshot.safeFailure
                )
            }
            return AgentConnectorProbe(
                state: probeState(for: health),
                safeFailure: snapshot.safeFailure
            )
        }
        if snapshot.hasValidData {
            return AgentConnectorProbe(state: snapshot.state, safeFailure: snapshot.safeFailure)
        }
        apply(health)
        return AgentConnectorProbe(state: probeState(for: health), safeFailure: snapshot.safeFailure)
    }

    /// Starting the connector starts only the local listener. It never opens,
    /// focuses, reloads, or authenticates a browser page.
    func start() async {
        guard await hasConsent() else { return }
        await loadSanitizedCacheIfNeeded()
        guard !listenerStarted else { return }
        listenerStarted = true
        listenerStartCount += 1
        if !snapshot.hasValidData {
            lifecycle = .waitingForUsagePage
            replace(Self.unavailableSnapshot(
                state: .waitingForFirstResponse,
                failure: nil,
                capturedAt: now()
            ))
        }
        let connector = self
        await integration.startListening { event in
            await connector.receive(event)
        }
        if await autoRefreshEnabled() {
            scheduleAutomaticRefresh(after: 0)
        }
    }

    func refresh() async { await syncNow() }

    func refresh(trigger: CodexRefreshTrigger) async {
        switch trigger {
        case .timer:
            await refreshAge()
        case .wake:
            await refreshAge()
            if await autoRefreshEnabled() {
                scheduleAutomaticRefresh(after: Self.automaticRefreshInterval)
            }
        case .providerEvent, .reconnect, .manual:
            await syncNow()
        }
    }

    func perform(_ command: AgentConnectorCommand) async {
        switch command {
        case .connect:
            await start()
        case .reconnect:
            await connect(openUsagePage: true)
        case .refresh:
            await syncNow()
        case .disconnect:
            await disconnect()
        }
    }

    func checkCompanion() async {
        guard await hasConsent() else {
            transitionToDisconnected()
            return
        }
        lifecycle = .checking
        apply(await integration.checkHealth())
    }

    func connect(openUsagePage: Bool) async {
        guard await hasConsent() else {
            transitionToDisconnected()
            return
        }
        await start()
        await runCoalescedAction(openUsagePage: openUsagePage, repairing: false)
    }

    func syncNow() async {
        guard await hasConsent() else {
            transitionToDisconnected()
            return
        }
        await start()
        await requestBrowserRefresh()
    }

    func openUsagePage() async {
        guard await hasConsent() else {
            transitionToDisconnected()
            return
        }
        await start()
        await runCoalescedAction(openUsagePage: true, repairing: false)
    }

    func repairCompanion() async {
        guard await hasConsent() else {
            transitionToDisconnected()
            return
        }
        await start()
        await runCoalescedAction(openUsagePage: false, repairing: true)
    }

    func disconnect() async {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        automaticTimeoutTask?.cancel()
        automaticTimeoutTask = nil
        await integration.closeOwnedUsageTab(automaticRequestID ?? UUID().uuidString.lowercased())
        automaticRequestID = nil
        automaticRefreshInFlight = false
        retentionTask?.cancel()
        retentionTask = nil
        await integration.stopListening()
        listenerStarted = false
        cacheLoaded = false
        lastGood = nil
        priorSessionCache = nil
        currentSessionValidated = false
        await clearCache()
        await clearConsent()
        transitionToDisconnected()
    }

    func stop() async {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        automaticTimeoutTask?.cancel()
        automaticTimeoutTask = nil
        await integration.closeOwnedUsageTab(automaticRequestID ?? UUID().uuidString.lowercased())
        automaticRequestID = nil
        automaticRefreshInFlight = false
        retentionTask?.cancel()
        retentionTask = nil
        await integration.stopListening()
        listenerStarted = false
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        await refreshAge()
        return snapshot
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            continuation.yield(snapshot)
        }
    }

    func lifecycleState() async -> ClaudeConnectorLifecycleState {
        await refreshAge()
        return lifecycle
    }

    func diagnostics() -> ClaudeBrowserConnectorDiagnostics {
        ClaudeBrowserConnectorDiagnostics(
            acceptedObservationCount: acceptedObservationCount,
            rejectedObservationCount: rejectedObservationCount,
            pageOpenCount: pageOpenCount,
            coalescedActionCount: coalescedActionCount,
            listenerStartCount: listenerStartCount,
            automaticDispatchCount: automaticDispatchCount,
            scheduledCycleCount: scheduledCycleCount,
            automaticRefreshInFlight: automaticRefreshInFlight,
            schedulerActive: automaticRefreshTask != nil
        )
    }

    func hasHiddenPriorSessionCache() -> Bool {
        priorSessionCache != nil
    }

    func automationPreferenceChanged() async {
        guard await hasConsent() else { return }
        if await autoRefreshEnabled() {
            if listenerStarted {
                scheduleAutomaticRefresh(after: 0)
            } else {
                // The Settings toggle can race the composition-root launch
                // task. Starting here makes the preference boundary complete:
                // one listener exists before the immediate automatic cycle.
                await start()
            }
        } else {
            automaticRefreshTask?.cancel()
            automaticRefreshTask = nil
        }
    }

    private func requestBrowserRefresh() async {
        guard !actionInFlight, !automaticRefreshInFlight else {
            coalescedActionCount += 1
            return
        }
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        lifecycle = .checking
        let health = await integration.checkHealth()
        guard health == .ready else {
            apply(health)
            await finishAutomaticRefresh(scheduleNext: health == .browserUnavailable)
            return
        }

        let requestID = UUID().uuidString.lowercased()
        automaticRequestID = requestID
        automaticRefreshInFlight = true
        let result = await integration.requestAutomaticRefresh(
            requestID,
            await allowSafariLaunch()
        )
        switch result {
        case .dispatched:
            automaticDispatchCount += 1
            scheduleAutomaticTimeout(for: requestID)
        case .browserUnavailable:
            retainOrFail(.unavailable, routeChanged: false)
            lifecycle = snapshot.hasValidData
                ? lifecycleForCurrentSnapshot()
                : .waitingForSafari
            await finishAutomaticRefresh(scheduleNext: true)
        case .unsupportedBrowser:
            apply(.unsupportedBrowser)
            await finishAutomaticRefresh(scheduleNext: false)
        case .companionUnavailable:
            apply(.disabled)
            await finishAutomaticRefresh(scheduleNext: false)
        }
    }

    private func scheduleAutomaticRefresh(after interval: TimeInterval) {
        automaticRefreshTask?.cancel()
        let boundedInterval = interval == 0
            ? 0
            : max(Self.minimumAutomaticRefreshInterval, interval)
        let connector = self
        automaticRefreshTask = Task {
            do {
                try await sleep(boundedInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await connector.automaticRefreshTimerFired()
        }
    }

    private func automaticRefreshTimerFired() async {
        automaticRefreshTask = nil
        guard await hasConsent(), await autoRefreshEnabled() else { return }
        scheduledCycleCount += 1
        await requestBrowserRefresh()
    }

    private func scheduleAutomaticTimeout(for requestID: String) {
        automaticTimeoutTask?.cancel()
        let connector = self
        automaticTimeoutTask = Task {
            do {
                try await sleep(Self.automaticRefreshTimeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await connector.automaticRefreshTimedOut(requestID: requestID)
        }
    }

    private func automaticRefreshTimedOut(requestID: String) async {
        guard automaticRefreshInFlight, automaticRequestID == requestID else { return }
        await integration.closeOwnedUsageTab(requestID)
        retainOrFail(.timedOut, routeChanged: false)
        await finishAutomaticRefresh(scheduleNext: true)
    }

    private func finishAutomaticRefresh(scheduleNext: Bool) async {
        automaticTimeoutTask?.cancel()
        automaticTimeoutTask = nil
        automaticRequestID = nil
        automaticRefreshInFlight = false
        guard scheduleNext, await hasConsent(), await autoRefreshEnabled() else { return }
        scheduleAutomaticRefresh(after: Self.automaticRefreshInterval)
    }

    private func runCoalescedAction(openUsagePage: Bool, repairing: Bool) async {
        guard !actionInFlight else {
            coalescedActionCount += 1
            return
        }
        actionInFlight = true
        defer { actionInFlight = false }
        lifecycle = .checking
        let health = repairing
            ? await integration.repairCompanion()
            : await integration.checkHealth()
        guard health == .ready else {
            apply(health)
            return
        }
        guard openUsagePage else {
            lifecycle = snapshot.hasValidData
                ? lifecycleForCurrentSnapshot()
                : .waitingForUsagePage
            return
        }
        if await integration.openUsagePage() {
            pageOpenCount += 1
            lifecycle = snapshot.hasValidData
                ? lifecycleForCurrentSnapshot()
                : .waitingForUsagePage
        } else {
            apply(.browserUnavailable)
        }
    }

    private func receive(_ event: ClaudeBrowserInboundEvent) async {
        switch event {
        case let .observation(result):
            await receiveObservation(result)
        case let .automation(event):
            await receiveAutomation(event)
        }
    }

    private func receiveObservation(
        _ result: Result<ClaudeBrowserObservationEnvelope, ClaudeBrowserBridgeError>
    ) async {
        guard await hasConsent() else { return }
        switch result {
        case let .success(envelope):
            do {
                try ClaudeBrowserMessageDecoder.validate(envelope)
                guard acceptedObservationIDs.insert(envelope.observationID).inserted else {
                    throw ClaudeBrowserBridgeError.invalidContract
                }
                acceptedObservationIDOrder.append(envelope.observationID)
                if acceptedObservationIDOrder.count > 64 {
                    acceptedObservationIDs.remove(acceptedObservationIDOrder.removeFirst())
                }
                guard let observedAt = Self.parseTimestamp(envelope.observation.observedAt),
                      now().timeIntervalSince(observedAt) >= -Self.maximumFutureSkew,
                      now().timeIntervalSince(observedAt) <= Self.freshnessInterval
                else {
                    throw ClaudeBrowserBridgeError.invalidTimestamp
                }
                let next = try Self.snapshot(from: envelope, observedAt: observedAt)
                acceptedObservationCount += 1
                currentSessionValidated = true
                priorSessionCache = nil
                lastGood = next
                replace(next)
                lifecycle = .fresh(observedAt)
                if let data = try? ClaudeBrowserMessageDecoder.encode(envelope) {
                    await writeCache(data)
                }
                scheduleRetention(from: observedAt)
                await finishAutomaticRefresh(scheduleNext: true)
            } catch {
                rejectedObservationCount += 1
                retainOrFail(.malformedResponse, routeChanged: true)
            }
        case let .failure(error):
            rejectedObservationCount += 1
            switch error {
            case .socketUnavailable,
                 .socketConnectionFailed,
                 .socketWriteFailed,
                 .socketReadFailed:
                // A local-listener start failure must be recoverable on the
                // next explicit action; do not leave a phantom started flag.
                listenerStarted = false
                retainOrFail(.unavailable, routeChanged: false)
            case .messageEmpty,
                 .messageTooLarge,
                 .malformedJSON,
                 .invalidTopLevel,
                 .unexpectedField,
                 .missingField,
                 .invalidContract,
                 .invalidPercentage,
                 .invalidReset,
                 .invalidTimestamp,
                 .noAccountWindow,
                 .invalidBrowserOrigin,
                 .nativeMessagingFrameMalformed,
                 .socketUnsafe:
                invalidateCurrentSession(
                    failure: .malformedResponse,
                    routeChanged: true
                )
            }
        }
    }

    private func receiveAutomation(_ event: ClaudeBrowserAutomationEvent) async {
        guard await hasConsent(),
              automaticRefreshInFlight,
              event.requestID == automaticRequestID
        else { return }
        switch event.status {
        case .bridgeReady, .refreshStarted:
            return
        case .refreshCompleted:
            await finishAutomaticRefresh(scheduleNext: true)
        case .permissionRequired:
            invalidateCurrentSession(failure: .authorizationRequired, routeChanged: false)
            lifecycle = .websiteAccessRequired
            await finishAutomaticRefresh(scheduleNext: false)
        case .signInRequired:
            invalidateCurrentSession(failure: .authorizationRequired, routeChanged: false)
            lifecycle = .signInRequired
            await finishAutomaticRefresh(scheduleNext: false)
        case .routeRejected:
            invalidateCurrentSession(failure: .malformedResponse, routeChanged: true)
            await finishAutomaticRefresh(scheduleNext: false)
        case .usageUnavailable:
            // The exact route was admitted, but an inactive Safari tab may be
            // temporarily unable to render its SPA landmarks. Retain only the
            // last sanitized value and wait the normal cadence; never retry
            // immediately or admit an unavailable result as zero.
            retainOrFail(.unavailable, routeChanged: false)
            await finishAutomaticRefresh(scheduleNext: true)
        case .tabUnavailable, .ownedTabClosed:
            retainOrFail(.unavailable, routeChanged: false)
            await finishAutomaticRefresh(scheduleNext: true)
        case .ownedTabOwnershipLost:
            invalidateCurrentSession(failure: .malformedResponse, routeChanged: true)
            await finishAutomaticRefresh(scheduleNext: false)
        }
    }

    private func loadSanitizedCacheIfNeeded() async {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let data = await readCache(),
              let envelope = try? ClaudeBrowserMessageDecoder.decode(data),
              let observedAt = Self.parseTimestamp(envelope.observation.observedAt)
        else { return }
        let age = now().timeIntervalSince(observedAt)
        guard age >= -Self.maximumFutureSkew, age <= Self.maximumRetainedAge,
              let restored = try? Self.snapshot(
                from: envelope,
                observedAt: observedAt,
                freshness: age <= Self.freshnessInterval ? .cached : .stale
              )
        else {
            await clearCache()
            return
        }
        // A prior-session cache is decoded and retained internally only. It
        // cannot admit Claude or render quota until this process receives a
        // current verified Usage-page observation.
        priorSessionCache = restored
    }

    private func refreshAge() async {
        guard let lastGood, let lastSuccessfulAt = lastGood.lastSuccessfulAt else { return }
        let age = now().timeIntervalSince(lastSuccessfulAt)
        if age >= Self.maximumRetainedAge {
            self.lastGood = nil
            await clearCache()
            lifecycle = .failed
            replace(Self.unavailableSnapshot(
                state: .failed,
                failure: .unavailable,
                capturedAt: now()
            ))
        } else if age >= Self.freshnessInterval, snapshot.freshness != .stale {
            let stale = Self.retained(lastGood, freshness: .stale, failure: .unavailable, now: now())
            self.lastGood = stale
            lifecycle = .stale(lastSuccessfulAt)
            replace(stale)
            scheduleRetention(from: lastSuccessfulAt)
        }
    }

    private func scheduleRetention(from observedAt: Date) {
        retentionTask?.cancel()
        let connector = self
        let age = max(0, now().timeIntervalSince(observedAt))
        let nextBoundary = age < Self.freshnessInterval
            ? Self.freshnessInterval
            : Self.maximumRetainedAge
        let delay = max(0, nextBoundary - age)
        retentionTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await connector.retentionTimerFired()
        }
    }

    private func retentionTimerFired() async {
        retentionTask = nil
        await refreshAge()
    }

    private func retainOrFail(_ failure: AgentSafeFailure, routeChanged: Bool) {
        if currentSessionValidated, let lastGood {
            let freshness: AgentConnectorFreshness = (lastGood.lastSuccessfulAt.map {
                now().timeIntervalSince($0) >= Self.freshnessInterval
            } ?? true) ? .stale : .cached
            let retained = Self.retained(lastGood, freshness: freshness, failure: failure, now: now())
            self.lastGood = retained
            lifecycle = freshness == .stale
                ? .stale(lastGood.lastSuccessfulAt ?? now())
                : .cached(lastGood.lastSuccessfulAt ?? now())
            replace(retained)
        } else {
            lifecycle = routeChanged ? .routeChanged : .failed
            replace(Self.unavailableSnapshot(
                state: .failed,
                failure: failure,
                capturedAt: now()
            ))
        }
    }

    private func invalidateCurrentSession(
        failure: AgentSafeFailure,
        routeChanged: Bool
    ) {
        retentionTask?.cancel()
        retentionTask = nil
        lastGood = nil
        currentSessionValidated = false
        acceptedObservationIDs.removeAll(keepingCapacity: false)
        acceptedObservationIDOrder.removeAll(keepingCapacity: false)
        lifecycle = routeChanged ? .routeChanged : .failed
        replace(Self.unavailableSnapshot(
            state: .failed,
            failure: failure,
            capturedAt: now()
        ))
    }

    private func apply(_ health: ClaudeBrowserCompanionHealth) {
        switch health {
        case .ready:
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .waitingForUsagePage
        case .browserUnavailable:
            retainOrFail(.unavailable, routeChanged: false)
            lifecycle = snapshot.hasValidData
                ? lifecycleForCurrentSnapshot()
                : .browserUnavailable
        case .disabled:
            invalidateCurrentSession(failure: .unavailable, routeChanged: false)
            lifecycle = .companionDisabled
        case .outdated:
            invalidateCurrentSession(failure: .unavailable, routeChanged: false)
            lifecycle = .companionOutdated
        case .unsupportedBrowser:
            invalidateCurrentSession(failure: .unavailable, routeChanged: false)
            lifecycle = .unsupportedBrowser
        case .nativeHostMissing:
            invalidateCurrentSession(failure: .unavailable, routeChanged: false)
            lifecycle = .nativeHostMissing
        case .nativeHostMismatched:
            invalidateCurrentSession(failure: .unavailable, routeChanged: false)
            lifecycle = .nativeHostMismatched
        }
    }

    private func probeState(for health: ClaudeBrowserCompanionHealth) -> AgentConnectorState {
        switch health {
        case .ready: .waitingForFirstResponse
        case .disabled, .outdated, .nativeHostMissing, .nativeHostMismatched: .waitingForFirstResponse
        case .unsupportedBrowser: .unsupported
        case .browserUnavailable: .inactive
        }
    }

    private func lifecycleForCurrentSnapshot() -> ClaudeConnectorLifecycleState {
        let date = snapshot.lastSuccessfulAt ?? snapshot.capturedAt
        return switch snapshot.freshness {
        case .fresh: .fresh(date)
        case .cached: .cached(date)
        case .stale: .stale(date)
        case .unavailable: .failed
        }
    }

    private func transitionToDisconnected() {
        acceptedObservationIDs.removeAll(keepingCapacity: false)
        acceptedObservationIDOrder.removeAll(keepingCapacity: false)
        lifecycle = .disconnected
        replace(Self.unavailableSnapshot(
            state: .authenticationRequired,
            failure: .authorizationRequired,
            capturedAt: now()
        ))
    }

    private func replace(_ next: AgentUsageSnapshot) {
        let merged = Self.merging(next, localActivity: cachedLocalActivity)
        snapshot = merged
        continuation?.yield(merged)
        scheduleLocalActivityRefreshIfNeeded()
    }

    /// Rescans local session metadata off the actor so no published account
    /// observation ever waits on filesystem work.
    private func scheduleLocalActivityRefreshIfNeeded() {
        guard let reader = localActivityReader, !localActivityRefreshInFlight else { return }
        let current = now()
        if let last = localActivityRefreshedAt,
           current.timeIntervalSince(last) < Self.localActivityRefreshInterval {
            return
        }
        localActivityRefreshInFlight = true
        localActivityRefreshedAt = current
        Task.detached(priority: .utility) { [weak self] in
            let sample = reader.read(now: current)
            await self?.storeLocalActivity(sample)
        }
    }

    private func storeLocalActivity(_ sample: ClaudeLocalActivitySnapshot) {
        localActivityRefreshInFlight = false
        cachedLocalActivity = sample
        let merged = Self.merging(snapshot, localActivity: sample)
        guard merged != snapshot else { return }
        snapshot = merged
        continuation?.yield(merged)
    }

    /// Replaces any existing local channel so the operation is idempotent, and
    /// leaves the account channel untouched. Local activity never contributes a
    /// rate-limit window and therefore can never be read as account quota.
    private static func merging(
        _ base: AgentUsageSnapshot,
        localActivity: ClaudeLocalActivitySnapshot?
    ) -> AgentUsageSnapshot {
        let accountChannels = base.channels.filter { $0.id != .localActivity }
        guard let localActivity, localActivity.availability == .available else {
            guard accountChannels.count != base.channels.count else { return base }
            return replacing(base, channels: accountChannels)
        }
        return replacing(
            base,
            channels: accountChannels
                + [localChannel(from: localActivity, freshness: base.freshness)]
        )
    }

    private static func replacing(
        _ base: AgentUsageSnapshot,
        channels: [AgentUsageChannel]
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: base.id,
            providerName: base.providerName,
            state: base.state,
            capturedAt: base.capturedAt,
            lastSuccessfulAt: base.lastSuccessfulAt,
            freshness: base.freshness,
            channels: channels,
            capabilities: base.capabilities,
            safeFailure: base.safeFailure,
            selectedWindowID: base.selectedWindowID
        )
    }

    private static func localChannel(
        from activity: ClaudeLocalActivitySnapshot,
        freshness: AgentConnectorFreshness
    ) -> AgentUsageChannel {
        let estimate = activity.apiEquivalentCost
        let observed = estimate?.observedTokens ?? 0
        let coverage = observed > 0
            ? Int((Double(estimate?.pricedTokens ?? 0) / Double(observed) * 100).rounded())
            : nil
        return AgentUsageChannel(
            id: .localActivity,
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "claude-jsonl-v1",
            scopes: [.device, .session, .task],
            provenance: .locallyEstimated,
            freshness: freshness == .unavailable ? .unavailable : freshness,
            capturedAt: activity.capturedAt,
            coverageNote: "aggregate metadata coverage",
            rateLimitWindows: [],
            accountMetrics: nil,
            localActivityMetrics: AgentLocalActivityMetrics(
                recentTaskCount: activity.tasks.count,
                recentTaskTokens: activity.tasks.map(\.totalTokens),
                recentTaskCapturedAt: activity.tasks.map(\.modifiedAt),
                sessionTokens: activity.tasks.reduce(0) { $0 + $1.totalTokens },
                estimatedSevenDayUSD: estimate?.sevenDayUSD,
                estimatedLifetimeUSD: estimate?.lifetimeUSD,
                coveragePercent: coverage,
                recognizedModelCount: estimate?.recognizedModelCount
            ),
            safeFailure: nil
        )
    }

    private static func snapshot(
        from envelope: ClaudeBrowserObservationEnvelope,
        observedAt: Date,
        freshness: AgentConnectorFreshness = .fresh
    ) throws -> AgentUsageSnapshot {
        var windows: [AgentRateLimitWindow] = []
        if let five = envelope.observation.fiveHour {
            windows.append(AgentRateLimitWindow(
                id: "five-hour",
                kind: .fiveHour,
                usedPercent: five.usedPercentage,
                isUnlimited: false,
                resetsAt: try resetDate(five.resetAt)
            ))
        }
        if let seven = envelope.observation.weeklyAllModels {
            windows.append(AgentRateLimitWindow(
                id: "seven-day",
                kind: .sevenDay,
                usedPercent: seven.usedPercentage,
                isUnlimited: false,
                resetsAt: try resetDate(seven.resetAt)
            ))
        }
        if let model = envelope.observation.modelSpecificWeekly {
            windows.append(AgentRateLimitWindow(
                id: "weekly-\(model.modelFamily.rawValue)",
                kind: .other,
                usedPercent: model.window.usedPercentage,
                isUnlimited: false,
                resetsAt: try resetDate(model.window.resetAt)
            ))
        }
        guard !windows.isEmpty else { throw ClaudeBrowserBridgeError.noAccountWindow }
        let failure: AgentSafeFailure? = freshness == .fresh ? nil : .unavailable
        let channel = AgentUsageChannel(
            id: .account,
            sourceTier: .authorizedReadOnlyRemote,
            sourceVersion: "browser-2",
            scopes: [.account],
            provenance: .providerReported,
            freshness: freshness,
            capturedAt: observedAt,
            coverageNote: "Claude official Usage page · Browser Sync · Experimental",
            rateLimitWindows: windows,
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: failure
        )
        return AgentUsageSnapshot(
            id: connectorID,
            providerName: "Claude Code",
            state: freshness == .stale ? .stale : .ready,
            capturedAt: observedAt,
            lastSuccessfulAt: observedAt,
            freshness: freshness,
            channels: [channel],
            capabilities: capabilities,
            safeFailure: failure
        )
    }

    private static func retained(
        _ snapshot: AgentUsageSnapshot,
        freshness: AgentConnectorFreshness,
        failure: AgentSafeFailure,
        now: Date
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: snapshot.id,
            providerName: snapshot.providerName,
            state: freshness == .stale ? .stale : .ready,
            capturedAt: now,
            lastSuccessfulAt: snapshot.lastSuccessfulAt,
            freshness: freshness,
            channels: snapshot.channels.map { channel in
                AgentUsageChannel(
                    id: channel.id,
                    sourceTier: channel.sourceTier,
                    sourceVersion: channel.sourceVersion,
                    scopes: channel.scopes,
                    provenance: channel.provenance,
                    freshness: freshness,
                    capturedAt: channel.capturedAt,
                    coverageNote: channel.coverageNote,
                    rateLimitWindows: channel.rateLimitWindows,
                    accountMetrics: channel.accountMetrics,
                    localActivityMetrics: channel.localActivityMetrics,
                    safeFailure: failure,
                    availability: channel.availability,
                    accountCreditSnapshot: channel.accountCreditSnapshot
                )
            },
            capabilities: snapshot.capabilities,
            safeFailure: failure,
            selectedWindowID: snapshot.selectedWindowID
        )
    }

    private static func unavailableSnapshot(
        state: AgentConnectorState,
        failure: AgentSafeFailure?,
        capturedAt: Date
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: connectorID,
            providerName: "Claude Code",
            state: state,
            capturedAt: capturedAt,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: capabilities,
            safeFailure: failure
        )
    }

    private static func resetDate(_ raw: String?) throws -> Date? {
        guard let raw else { return nil }
        guard let date = parseTimestamp(raw) else { throw ClaudeBrowserBridgeError.invalidReset }
        return date
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: raw)
    }
}
