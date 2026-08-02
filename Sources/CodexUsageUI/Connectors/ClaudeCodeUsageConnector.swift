import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation

enum ClaudeConnectorLifecycleState: Equatable, Sendable {
    case disconnected
    case checking
    case waitingForUsagePage
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

struct ClaudeBrowserProductionIntegration: Sendable {
    typealias ObservationHandler = @Sendable (
        Result<ClaudeBrowserObservationEnvelope, ClaudeBrowserBridgeError>
    ) async -> Void

    let startListening: @Sendable (@escaping ObservationHandler) async -> Void
    let stopListening: @Sendable () async -> Void
    let checkHealth: @Sendable () async -> ClaudeBrowserCompanionHealth
    let openUsagePage: @Sendable () async -> Bool
    let repairCompanion: @Sendable () async -> ClaudeBrowserCompanionHealth

    static func unavailable() -> Self {
        Self(
            startListening: { _ in },
            stopListening: {},
            checkHealth: { .nativeHostMissing },
            openUsagePage: { false },
            repairCompanion: { .nativeHostMissing }
        )
    }
}

struct ClaudeBrowserConnectorDiagnostics: Equatable, Sendable {
    let acceptedObservationCount: Int
    let rejectedObservationCount: Int
    let pageOpenCount: Int
    let coalescedActionCount: Int
    let listenerStartCount: Int
}

actor ClaudeCodeUsageConnector: AgentUsageConnector {
    typealias ConsentReader = @Sendable () async -> Bool
    typealias ConsentClearer = @Sendable () async -> Void
    typealias CacheReader = @Sendable () async -> Data?
    typealias CacheWriter = @Sendable (Data) async -> Void
    typealias CacheClearer = @Sendable () async -> Void
    typealias Now = @Sendable () -> Date

    static let connectorID = AgentConnectorID(rawValue: "claude.browserSync")!
    static let freshnessInterval: TimeInterval = 5 * 60
    static let maximumRetainedAge: TimeInterval = 30 * 60
    static let maximumFutureSkew: TimeInterval = 30

    private static let capabilities: Set<AgentConnectorCapability> = [
        .connect,
        .reconnect,
        .refresh,
        .disconnect,
        .rateLimits,
        .sanitizedLastValidRestore,
    ]

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "Claude Code",
        officialSource: "Claude official Usage page · Browser Sync · Experimental",
        sourceTier: .authorizedReadOnlyRemote,
        sourceVersion: "browser-1",
        supportedScopes: [.account],
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
    private var acceptedObservationCount = 0
    private var rejectedObservationCount = 0
    private var pageOpenCount = 0
    private var coalescedActionCount = 0
    private var listenerStartCount = 0

    init(
        integration: ClaudeBrowserProductionIntegration,
        hasConsent: @escaping ConsentReader,
        clearConsent: @escaping ConsentClearer = {},
        readCache: @escaping CacheReader = { nil },
        writeCache: @escaping CacheWriter = { _ in },
        clearCache: @escaping CacheClearer = {},
        now: @escaping Now = Date.init
    ) {
        self.integration = integration
        self.hasConsent = hasConsent
        self.clearConsent = clearConsent
        self.readCache = readCache
        self.writeCache = writeCache
        self.clearCache = clearCache
        self.now = now
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
        clearCache: @escaping CacheClearer = {}
    ) -> ClaudeCodeUsageConnector {
        ClaudeCodeUsageConnector(
            integration: integration,
            hasConsent: hasConsent,
            clearConsent: clearConsent,
            readCache: readCache,
            writeCache: writeCache,
            clearCache: clearCache
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
        await integration.startListening { result in
            await connector.receive(result)
        }
    }

    func refresh() async { await syncNow() }

    func refresh(trigger: CodexRefreshTrigger) async {
        // Page extraction is interaction-driven. Timer refreshes never open or
        // focus the browser and cannot multiply provider reads.
        guard trigger != .timer else {
            await refreshAge()
            return
        }
        await syncNow()
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
        await runCoalescedAction(openUsagePage: true, repairing: false)
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
            listenerStartCount: listenerStartCount
        )
    }

    func hasHiddenPriorSessionCache() -> Bool {
        priorSessionCache != nil
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

    private func receive(
        _ result: Result<ClaudeBrowserObservationEnvelope, ClaudeBrowserBridgeError>
    ) async {
        guard await hasConsent() else { return }
        switch result {
        case let .success(envelope):
            do {
                try ClaudeBrowserMessageDecoder.validate(envelope)
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
        lifecycle = .disconnected
        replace(Self.unavailableSnapshot(
            state: .authenticationRequired,
            failure: .authorizationRequired,
            capturedAt: now()
        ))
    }

    private func replace(_ next: AgentUsageSnapshot) {
        snapshot = next
        continuation?.yield(next)
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
            sourceVersion: "browser-1",
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
