import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import ClaudeStatusLineCore
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
    case extensionNotInstalled
    case inventoryRestartRequired
    case inventoryLoading
    case companionStarting
    case protocolMismatch
    case companionUnavailable
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
    case extensionNotInstalled
    case inventoryRestartRequired
    case inventoryLoading
    case companionStarting
    case protocolMismatch
    case companionUnavailable
}

extension ClaudeBrowserCompanionHealth {
    var allowsAuthoritativeHandshakeAttempt: Bool {
        switch self {
        case .ready, .inventoryRestartRequired, .inventoryLoading:
            return true
        case .disabled, .outdated, .unsupportedBrowser, .browserUnavailable,
             .nativeHostMissing, .nativeHostMismatched, .extensionNotInstalled,
             .companionStarting, .protocolMismatch, .companionUnavailable:
            return false
        }
    }
}

enum ClaudeBrowserInboundEvent: Sendable {
    case observation(Result<ClaudeBrowserObservationEnvelope, ClaudeBrowserBridgeError>)
    case automation(ClaudeBrowserAutomationEvent)
    /// A mutable-app classification of a terminal Host IPC failure. This is
    /// deliberately outside the browser protocol so Host/Companion bytes do
    /// not need to change merely to preserve an exact product-state reason.
    case dispatchFailure(ClaudeBrowserAutomaticDispatchResult)
}

enum ClaudeBrowserAutomaticDispatchResult: Equatable, Sendable {
    case dispatched
    case browserUnavailable
    case unsupportedBrowser
    case companionUnavailable
    case companionStarting
    case protocolMismatch
    case workDispatchFailed
}

/// Local Smart and Browser Accuracy are independent product channels. These
/// states intentionally do not share a failure case or a single connection
/// boolean: a degraded browser companion cannot erase healthy local truth.
enum ClaudeLocalSmartState: Equatable, Sendable {
    case exactLocal(Date)
    case estimated(Date)
    case staleUnsupported(Date?)
    case unavailable
    case error
}

enum ClaudeBrowserAccuracyState: Equatable, Sendable {
    case notConfigured
    case consentRequired
    case ready
    case companionUnavailable
    case updatePendingRestart
    case syncing
    case exactAnchorAvailable(Date)
    case error
}

enum ClaudeLiveLinkStageReason: String, Equatable, Sendable {
    case localStatusLinePending
    case localStatusLineRejected
    case localActivityDetectedAwaitingExactAnchor
    case localCodeActivityDetectedDesktopUnavailable
    case localCallbackWithoutQuotaWindows
    case localExactReceived
    case desktopActivitySignalUnavailable
    case accuracyHandshakeUnavailable
    case accuracyInventoryRestartRequired
    case accuracyInventoryLoading
    case accuracyCompanionStarting
    case accuracyProtocolMismatch
    case accuracyCompanionUnavailable
    case accuracyBrowserUnavailable
    case accuracyWorkDispatchFailed
    case accuracyRequestMismatch
    case accuracyPermissionRequired
    case accuracySignInRequired
    case accuracyRouteRejected
    case accuracyUsageUnavailable
    case accuracyTabUnavailable
    case accuracyOwnedTabLost
    case accuracyExactReceived

    var isAccuracyFailure: Bool {
        switch self {
        case .accuracyHandshakeUnavailable,
             .accuracyInventoryRestartRequired,
             .accuracyInventoryLoading,
             .accuracyCompanionStarting,
             .accuracyProtocolMismatch,
             .accuracyCompanionUnavailable,
             .accuracyBrowserUnavailable,
             .accuracyWorkDispatchFailed,
             .accuracyRequestMismatch,
             .accuracyPermissionRequired,
             .accuracySignInRequired,
             .accuracyRouteRejected,
             .accuracyUsageUnavailable,
             .accuracyTabUnavailable,
             .accuracyOwnedTabLost:
            true
        case .localStatusLinePending,
             .localStatusLineRejected,
             .localActivityDetectedAwaitingExactAnchor,
             .localCodeActivityDetectedDesktopUnavailable,
             .localCallbackWithoutQuotaWindows,
             .localExactReceived,
             .desktopActivitySignalUnavailable,
             .accuracyExactReceived:
            false
        }
    }
}


/// Claude Desktop's authorized plan cache is a quota estimate, not a
/// per-response event stream. This contract prevents an estimate-only Desktop
/// installation from being presented as though UMA can detect Desktop actions.
enum ClaudeDesktopActivityContract: Equatable, Sendable {
    case notApplicable
    case estimateOnlyNoActivitySignal
}

struct ClaudeBrowserProductionIntegration: Sendable {
    typealias MessageHandler = @Sendable (ClaudeBrowserInboundEvent) async -> Void

    let startListening: @Sendable (@escaping MessageHandler) async -> Void
    let stopListening: @Sendable () async -> Void
    let checkHealth: @Sendable () async -> ClaudeBrowserCompanionHealth
    let openUsagePage: @Sendable () async -> Bool
    let repairCompanion: @Sendable () async -> ClaudeBrowserCompanionHealth
    let verifyHandshake: @Sendable () async -> ClaudeBrowserCompanionVerification
    let requestAutomaticRefresh: @Sendable (String, Bool) async -> ClaudeBrowserAutomaticDispatchResult
    let closeOwnedUsageTab: @Sendable (String) async -> Void

    init(
        startListening: @escaping @Sendable (@escaping MessageHandler) async -> Void,
        stopListening: @escaping @Sendable () async -> Void,
        checkHealth: @escaping @Sendable () async -> ClaudeBrowserCompanionHealth,
        openUsagePage: @escaping @Sendable () async -> Bool,
        repairCompanion: @escaping @Sendable () async -> ClaudeBrowserCompanionHealth,
        verifyHandshake: @escaping @Sendable () async -> ClaudeBrowserCompanionVerification = { .unavailable },
        requestAutomaticRefresh: @escaping @Sendable (String, Bool) async -> ClaudeBrowserAutomaticDispatchResult = { _, _ in .unsupportedBrowser },
        closeOwnedUsageTab: @escaping @Sendable (String) async -> Void = { _ in }
    ) {
        self.startListening = startListening
        self.stopListening = stopListening
        self.checkHealth = checkHealth
        self.openUsagePage = openUsagePage
        self.repairCompanion = repairCompanion
        self.verifyHandshake = verifyHandshake
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
            verifyHandshake: { .unavailable },
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
    /// Counts explicit Local Smart metadata projections. Accuracy callbacks do
    /// not increment this counter.
    let localActivityReaderInvocationCount: Int
    /// Counts bounded Local Smart reader invocations that may inspect the
    /// Claude-owned projects directory before immediate aggregate projection.
    let claudeProjectsAccessCount: Int
    /// Counts reads of the one exact Founder-authorized Claude Desktop cache.
    let desktopPlanUsageReadCount: Int
    /// Counts strict v2 cache samples accepted after all integrity gates.
    let desktopPlanUsageAcceptedCount: Int
    /// Content-free, bounded stage evidence for Local Smart and one-shot
    /// Accuracy Sync. It never includes provider values or page/session data.
    let lastLiveLinkStage: ClaudeLiveLinkStageReason?
    /// True only while the published exact account window set includes a
    /// still-current one-shot Safari Accuracy anchor. This is source metadata,
    /// not evidence that a new local status-line callback was received.
    let currentQuotaIncludesSafariAccuracy: Bool
    /// Independent Local Smart quota state. Browser health never mutates it.
    let localSmartState: ClaudeLocalSmartState
    /// Independent one-shot Browser Accuracy state. Local input failures never
    /// mutate it or invalidate an already admitted browser anchor.
    let browserAccuracyState: ClaudeBrowserAccuracyState
    let localSmartStage: ClaudeLiveLinkStageReason?
    let browserAccuracyStage: ClaudeLiveLinkStageReason?
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
    /// Historical M5-AUTO cadence retained only so superseded fixtures compile.
    /// Local Smart Mode never schedules this interval.
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
        .localActivity,
        .rateLimits,
        .passiveLocalAvailability,
    ]

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "Claude Code",
        officialSource: "Claude Local Smart Mode · official status line · version-pinned Desktop estimate · on-demand Accuracy Sync",
        sourceTier: .officialStructuredHook,
        sourceVersion: "smart-1",
        supportedScopes: [.account, .session],
        capabilities: capabilities,
        configurationRequirements: [
            .userAuthorization,
            .officialManagedSession,
            .privacySafeLocalMetadataAccess,
        ],
        privacyAllowlist: [
            "fiveHourUsedPercentage",
            "fiveHourResetAt",
            "sevenDayUsedPercentage",
            "sevenDayResetAt",
            "observedAt",
            "localActivityTotalTokens",
            "localActivityLatestActivityAt",
            "localActivityModelFamilyKey",
            "localActivityCoveragePercent",
            "desktopPlanFiveHourRemainingEstimate",
            "desktopPlanSevenDayRemainingEstimate",
            "desktopPlanObservedAt",
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
        localSourceClass: .admittedStructuredLocal,
        authenticationMethod: .officialApplicationOwnedSession,
        usageReadContract: .currentStructuredLocalRead,
        loginAssistance: .none
    )!

    private let integration: ClaudeBrowserProductionIntegration
    private let hasConsent: ConsentReader
    private let clearConsent: ConsentClearer
    private let clearCache: CacheClearer
    private let now: Now
    private let sleep: Sleeper
    private let statusStateStore: ClaudeStatusLineStateStore?
    private let statusStateMonitor: ClaudeStatusLineStateMonitor?
    private let localActivityReader: (any ClaudeLocalActivityReading)?
    private let desktopPlanUsageReader: (any ClaudeDesktopPlanUsageReading)?
    private let desktopActivityContract: ClaudeDesktopActivityContract
    private let anchorStore: (any ClaudeSmartAnchorStoring)?
    private var localActivityObserver: CodexLocalActivityObserver?
    private var desktopPlanUsageMonitor: ClaudeDesktopPlanUsageMonitor?

    private var snapshot: AgentUsageSnapshot
    private var lastGood: AgentUsageSnapshot?
    private var lifecycle: ClaudeConnectorLifecycleState = .disconnected
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var listenerStarted = false
    private var localSmartStarted = false
    private var actionInFlight = false
    private var retentionTask: Task<Void, Never>?
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
    private var anchors: [ClaudeSmartWindowAnchor] = []
    private var anchorsLoaded = false
    private var latestActivity: ClaudeSanitizedLocalActivity?
    private var latestDesktopPlanUsage: ClaudeDesktopPlanUsageSnapshot?
    private var previousEstimates: [AgentRateLimitWindow.Kind: Double] = [:]
    private var continuityGeneration: [AgentRateLimitWindow.Kind: UInt64] = [
        .fiveHour: 0,
        .sevenDay: 0,
    ]
    private var localActivityReaderInvocationCount = 0
    private var claudeProjectsAccessCount = 0
    private var desktopPlanUsageReadCount = 0
    private var desktopPlanUsageAcceptedCount = 0
    private var lastLiveLinkStage: ClaudeLiveLinkStageReason?
    private var currentQuotaIncludesSafariAccuracy = false
    private var localSmartState: ClaudeLocalSmartState = .unavailable
    private var browserAccuracyState: ClaudeBrowserAccuracyState = .notConfigured
    private var localSmartStage: ClaudeLiveLinkStageReason?
    private var browserAccuracyStage: ClaudeLiveLinkStageReason?
    private var localSmartReadError = false

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
        statusStateStore: ClaudeStatusLineStateStore? = nil,
        statusStateMonitor: ClaudeStatusLineStateMonitor? = nil,
        localActivityReader: (any ClaudeLocalActivityReading)? = nil,
        desktopPlanUsageReader: (any ClaudeDesktopPlanUsageReading)? = nil,
        desktopActivityContract: ClaudeDesktopActivityContract = .notApplicable,
        anchorStore: (any ClaudeSmartAnchorStoring)? = nil
    ) {
        self.integration = integration
        self.hasConsent = hasConsent
        self.clearConsent = clearConsent
        // Legacy Browser Sync cache reads/writes are intentionally retired.
        // Keep these arguments source-compatible for historical fixtures;
        // Disconnect still clears the old cache through `clearCache`.
        _ = readCache
        _ = writeCache
        self.clearCache = clearCache
        self.now = now
        _ = autoRefreshEnabled
        _ = allowSafariLaunch
        self.sleep = sleep
        self.statusStateStore = statusStateStore
        self.statusStateMonitor = statusStateMonitor
        self.localActivityReader = localActivityReader
        self.desktopActivityContract = desktopActivityContract
        self.desktopPlanUsageReader = desktopActivityContract == .estimateOnlyNoActivitySignal
            ? desktopPlanUsageReader
            : nil
        self.anchorStore = anchorStore
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
        statusStateURL: URL? = nil,
        localActivityReader: (any ClaudeLocalActivityReading)? = nil,
        desktopPlanUsageReader: (any ClaudeDesktopPlanUsageReading)? = nil,
        desktopActivityContract: ClaudeDesktopActivityContract = .notApplicable,
        anchorStore: (any ClaudeSmartAnchorStoring)? = nil
    ) -> ClaudeCodeUsageConnector {
        let stateStore = statusStateURL.map(ClaudeStatusLineStateStore.init(stateURL:))
        let stateMonitor = statusStateURL.map {
            ClaudeStatusLineStateMonitor(directoryURL: $0.deletingLastPathComponent())
        }
        return ClaudeCodeUsageConnector(
            integration: integration,
            hasConsent: hasConsent,
            clearConsent: clearConsent,
            readCache: readCache,
            writeCache: writeCache,
            clearCache: clearCache,
            autoRefreshEnabled: autoRefreshEnabled,
            allowSafariLaunch: allowSafariLaunch,
            statusStateStore: stateStore,
            statusStateMonitor: stateMonitor,
            localActivityReader: localActivityReader,
            desktopPlanUsageReader: desktopPlanUsageReader,
            desktopActivityContract: desktopActivityContract,
            anchorStore: anchorStore
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
        await loadSmartStateIfNeeded()
        await refreshLocalInputs()
        return AgentConnectorProbe(
            state: snapshot.hasValidData
                ? snapshot.state
                : (desktopActivityContract == .estimateOnlyNoActivitySignal
                    ? .unsupported
                    : .waitingForFirstResponse),
            safeFailure: snapshot.safeFailure
        )
    }

    /// Explicitly starts Local Smart observation. Browser-only actions use the
    /// narrower listener boundary below and must never reach local project or
    /// Desktop inputs as an incidental side effect.
    func start() async {
        guard await hasConsent() else { return }
        guard !localSmartStarted else { return }
        localSmartStarted = true
        if let statusStateMonitor {
            try? statusStateMonitor.start {
                Task { await self.statusStateChanged() }
            }
        }
        startLocalActivityObservationIfNeeded()
        startDesktopPlanUsageObservationIfNeeded()
        await refreshLocalInputs()
    }

    func refresh() async { await syncNow() }

    func refresh(trigger: CodexRefreshTrigger) async {
        switch trigger {
        case .timer, .wake:
            await refreshLocalInputs()
        case .providerEvent, .reconnect, .manual:
            await syncNow()
        }
    }

    func perform(_ command: AgentConnectorCommand) async {
        switch command {
        case .connect:
            await connect(openUsagePage: false)
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
        await startBrowserListenerIfNeeded()
        lifecycle = .checking
        let health = await integration.checkHealth()
        guard health.allowsAuthoritativeHandshakeAttempt else {
            apply(health)
            return
        }
        switch await integration.verifyHandshake() {
        case .verified:
            browserAccuracyStage = nil
            browserAccuracyState = currentSafariAccuracyState(or: .ready)
            lifecycle = lifecycleForCurrentSnapshot()
        case .disabled:
            apply(.disabled)
        case .companionStarting:
            apply(.companionStarting)
        case .protocolMismatch:
            apply(.protocolMismatch)
        case .browserUnavailable:
            apply(.browserUnavailable)
        case .unavailable:
            // An advisory inventory result is allowed one authoritative
            // handshake attempt. If that attempt cannot prove the companion,
            // retain the more specific inventory state instead of collapsing
            // it into a generic Browser Accuracy failure.
            switch health {
            case .inventoryRestartRequired, .inventoryLoading:
                apply(health)
            default:
                apply(.companionUnavailable)
            }
        }
    }

    func connect(openUsagePage: Bool) async {
        guard await hasConsent() else {
            transitionToDisconnected()
            return
        }
        if openUsagePage {
            await accuracySync()
        } else {
            await start()
        }
    }

    func syncNow() async {
        guard await hasConsent() else {
            transitionToDisconnected()
            return
        }
        await start()
        await refreshLocalInputs()
    }

    /// A single explicitly requested account-truth correction. No timer,
    /// automatic retry, or persistent browser ownership can reach this path.
    func accuracySync() async {
        guard await hasConsent() else {
            browserAccuracyState = .consentRequired
            transitionToDisconnected()
            return
        }
        await startBrowserListenerIfNeeded()
        await requestBrowserRefresh()
    }

    func openUsagePage() async {
        guard await hasConsent() else {
            transitionToDisconnected()
            return
        }
        await startBrowserListenerIfNeeded()
        await runCoalescedAction(openUsagePage: true, repairing: false)
    }

    func repairCompanion() async {
        guard await hasConsent() else {
            transitionToDisconnected()
            return
        }
        await startBrowserListenerIfNeeded()
        await runCoalescedAction(openUsagePage: false, repairing: true)
    }

    func disconnect() async {
        await disconnectInternal(clearStoredConsent: true)
    }

    /// Stops every UMA-owned Claude source and clears sanitized state while
    /// retaining consent/configuration metadata until exact statusLine restore
    /// succeeds. Settings uses this transactional boundary for Disconnect.
    func prepareForConfigurationRestore() async {
        await disconnectInternal(clearStoredConsent: false)
    }

    private func disconnectInternal(clearStoredConsent: Bool) async {
        automaticTimeoutTask?.cancel()
        automaticTimeoutTask = nil
        if let automaticRequestID {
            await integration.closeOwnedUsageTab(automaticRequestID)
        }
        automaticRequestID = nil
        automaticRefreshInFlight = false
        retentionTask?.cancel()
        retentionTask = nil
        await integration.stopListening()
        listenerStarted = false
        localSmartStarted = false
        statusStateMonitor?.stop()
        localActivityObserver?.stop()
        desktopPlanUsageMonitor?.stop()
        lastGood = nil
        await clearCache()
        try? await anchorStore?.clear()
        anchors.removeAll()
        anchorsLoaded = false
        latestActivity = nil
        latestDesktopPlanUsage = nil
        previousEstimates.removeAll()
        lastLiveLinkStage = nil
        currentQuotaIncludesSafariAccuracy = false
        localSmartState = .unavailable
        browserAccuracyState = .notConfigured
        localSmartStage = nil
        browserAccuracyStage = nil
        localSmartReadError = false
        if clearStoredConsent { await clearConsent() }
        transitionToDisconnected()
    }

    func stop() async {
        automaticTimeoutTask?.cancel()
        automaticTimeoutTask = nil
        if let automaticRequestID {
            await integration.closeOwnedUsageTab(automaticRequestID)
        }
        automaticRequestID = nil
        automaticRefreshInFlight = false
        retentionTask?.cancel()
        retentionTask = nil
        await integration.stopListening()
        listenerStarted = false
        localSmartStarted = false
        statusStateMonitor?.stop()
        localActivityObserver?.stop()
        desktopPlanUsageMonitor?.stop()
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        await publishSmartSnapshot()
        return snapshot
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            continuation.yield(snapshot)
        }
    }

    func lifecycleState() async -> ClaudeConnectorLifecycleState {
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
            scheduledCycleCount: 0,
            automaticRefreshInFlight: automaticRefreshInFlight,
            schedulerActive: false,
            localActivityReaderInvocationCount: localActivityReaderInvocationCount,
            claudeProjectsAccessCount: claudeProjectsAccessCount,
            desktopPlanUsageReadCount: desktopPlanUsageReadCount,
            desktopPlanUsageAcceptedCount: desktopPlanUsageAcceptedCount,
            lastLiveLinkStage: lastLiveLinkStage,
            currentQuotaIncludesSafariAccuracy: currentQuotaIncludesSafariAccuracy,
            localSmartState: localSmartState,
            browserAccuracyState: browserAccuracyState,
            localSmartStage: localSmartStage,
            browserAccuracyStage: browserAccuracyStage
        )
    }

    func automationPreferenceChanged() async {
        // Legacy preference callback retained for source compatibility only.
        // Recurring Safari automation is retired and cannot be restarted here.
    }

    private func requestBrowserRefresh() async {
        guard !actionInFlight, !automaticRefreshInFlight else {
            coalescedActionCount += 1
            return
        }
        actionInFlight = true
        defer { actionInFlight = false }
        browserAccuracyState = .syncing
        browserAccuracyStage = nil
        lifecycle = .checking
        let health = await integration.checkHealth()
        guard health.allowsAuthoritativeHandshakeAttempt else {
            apply(health)
            await finishAccuracySync()
            return
        }

        let requestID = UUID().uuidString.lowercased()
        automaticRequestID = requestID
        automaticRefreshInFlight = true
        let result = await integration.requestAutomaticRefresh(
            requestID,
            true
        )
        switch result {
        case .dispatched:
            automaticDispatchCount += 1
            scheduleAutomaticTimeout(for: requestID)
        case .browserUnavailable:
            setBrowserAccuracyStage(.accuracyBrowserUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            lifecycle = snapshot.hasValidData
                ? lifecycleForCurrentSnapshot()
                : .waitingForSafari
            await finishAccuracySync()
        case .unsupportedBrowser:
            apply(.unsupportedBrowser)
            await finishAccuracySync()
        case .companionUnavailable:
            apply(.companionUnavailable)
            await finishAccuracySync()
        case .companionStarting:
            apply(.companionStarting)
            await finishAccuracySync()
        case .protocolMismatch:
            apply(.protocolMismatch)
            await finishAccuracySync()
        case .workDispatchFailed:
            setBrowserAccuracyStage(.accuracyWorkDispatchFailed)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .failed
            await finishAccuracySync()
        }
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
        setBrowserAccuracyStage(.accuracyHandshakeUnavailable)
        browserAccuracyState = currentSafariAccuracyState(or: .error)
        lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .failed
        await finishAccuracySync()
    }

    private func finishAccuracySync() async {
        automaticTimeoutTask?.cancel()
        automaticTimeoutTask = nil
        automaticRequestID = nil
        automaticRefreshInFlight = false
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
        guard health.allowsAuthoritativeHandshakeAttempt else {
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
            browserAccuracyState = currentSafariAccuracyState(or: .ready)
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
        case let .dispatchFailure(result):
            await receiveDispatchFailure(result)
        }
    }

    private func receiveDispatchFailure(
        _ result: ClaudeBrowserAutomaticDispatchResult
    ) async {
        guard await hasConsent(), automaticRefreshInFlight else { return }
        switch result {
        case .protocolMismatch:
            setBrowserAccuracyStage(.accuracyProtocolMismatch)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .protocolMismatch
        case .browserUnavailable:
            setBrowserAccuracyStage(.accuracyBrowserUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .waitingForSafari
        case .companionUnavailable, .companionStarting:
            setBrowserAccuracyStage(
                result == .companionStarting
                    ? .accuracyCompanionStarting
                    : .accuracyCompanionUnavailable
            )
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            lifecycle = snapshot.hasValidData
                ? lifecycleForCurrentSnapshot()
                : (result == .companionStarting ? .companionStarting : .companionUnavailable)
        case .unsupportedBrowser:
            apply(.unsupportedBrowser)
        case .workDispatchFailed, .dispatched:
            setBrowserAccuracyStage(.accuracyWorkDispatchFailed)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .failed
        }
        await finishAccuracySync()
    }

    private func receiveObservation(
        _ result: Result<ClaudeBrowserObservationEnvelope, ClaudeBrowserBridgeError>
    ) async {
        guard await hasConsent(), automaticRefreshInFlight else {
            rejectedObservationCount += 1
            return
        }
        switch result {
        case let .success(envelope):
            do {
                try ClaudeBrowserMessageDecoder.validate(envelope)
                guard envelope.requestID == automaticRequestID else {
                    setBrowserAccuracyStage(.accuracyRequestMismatch)
                    throw ClaudeBrowserBridgeError.invalidContract
                }
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
                try await acceptSafariAccuracy(envelope, observedAt: observedAt)
                acceptedObservationCount += 1
                setBrowserAccuracyStage(.accuracyExactReceived)
                browserAccuracyState = .exactAnchorAvailable(observedAt)
                await finishAccuracySync()
            } catch {
                rejectedObservationCount += 1
                if browserAccuracyStage != .accuracyRequestMismatch {
                    setBrowserAccuracyStage(.accuracyRouteRejected)
                }
                browserAccuracyState = currentSafariAccuracyState(or: .error)
                lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .routeChanged
                await finishAccuracySync()
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
                setBrowserAccuracyStage(.accuracyCompanionUnavailable)
                browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
                lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .failed
                await finishAccuracySync()
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
                setBrowserAccuracyStage(.accuracyRouteRejected)
                browserAccuracyState = currentSafariAccuracyState(or: .error)
                lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .routeChanged
                await finishAccuracySync()
            }
        }
    }

    private func receiveAutomation(_ event: ClaudeBrowserAutomationEvent) async {
        guard await hasConsent(),
              automaticRefreshInFlight,
              event.requestID == automaticRequestID
        else { return }
        switch event.status {
        case .extensionBackgroundReady, .nativeHandlerEntered,
             .nativeRequestDecoded, .runtimeGenerationValidated,
             .nativeResponseCreated, .nativeResponseSent,
             .extensionResponseReceived, .bridgeReady, .refreshStarted:
            return
        case .refreshCompleted:
            await finishAccuracySync()
        case .permissionRequired:
            setBrowserAccuracyStage(.accuracyPermissionRequired)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .websiteAccessRequired
            await finishAccuracySync()
        case .signInRequired:
            setBrowserAccuracyStage(.accuracySignInRequired)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .signInRequired
            await finishAccuracySync()
        case .routeRejected:
            setBrowserAccuracyStage(.accuracyRouteRejected)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .routeChanged
            await finishAccuracySync()
        case .browserUnavailable:
            setBrowserAccuracyStage(.accuracyBrowserUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .waitingForSafari
            await finishAccuracySync()
        case .usageUnavailable:
            setBrowserAccuracyStage(.accuracyUsageUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .failed
            await finishAccuracySync()
        case .tabUnavailable, .ownedTabClosed:
            setBrowserAccuracyStage(.accuracyTabUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .failed
            await finishAccuracySync()
        case .ownedTabOwnershipLost:
            setBrowserAccuracyStage(.accuracyOwnedTabLost)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            lifecycle = snapshot.hasValidData ? lifecycleForCurrentSnapshot() : .routeChanged
            await finishAccuracySync()
        }
    }

    func receiveEncodedStatusLinePacket(_ data: Data) async {
        guard let packet = try? ClaudeStatusLinePacket.decodePacket(data) else {
            rejectedObservationCount += 1
            return
        }
        await acceptStatusLine(packet)
    }

    private func statusStateChanged() async {
        await refreshLocalInputs()
    }

    /// Starts only the sanitized Browser Accuracy callback boundary. This is
    /// deliberately independent from Local Smart observers/readers so a cold
    /// Companion check or Accuracy Sync cannot touch Claude project sessions.
    private func startBrowserListenerIfNeeded() async {
        guard await hasConsent() else { return }
        await loadSmartStateIfNeeded()
        guard !listenerStarted else { return }
        listenerStarted = true
        listenerStartCount += 1
        if !snapshot.hasValidData {
            lifecycle = .waitingForUsagePage
            replace(Self.unavailableSnapshot(
                state: desktopActivityContract == .estimateOnlyNoActivitySignal
                    ? .unsupported
                    : .waitingForFirstResponse,
                failure: nil,
                capturedAt: now()
            ))
        }
        let connector = self
        await integration.startListening { event in
            await connector.receive(event)
        }
    }

    private func startLocalActivityObservationIfNeeded() {
        if let localActivityObserver {
            localActivityObserver.start()
            return
        }
        guard let provider = localActivityReader
            as? any ClaudeLocalActivityObservationProviding
        else { return }
        let observer = provider.makeLocalActivityObserver { [weak self] in
            Task { await self?.refreshLocalInputs() }
        }
        localActivityObserver = observer
        observer.start()
    }

    private func startDesktopPlanUsageObservationIfNeeded() {
        if let desktopPlanUsageMonitor {
            desktopPlanUsageMonitor.start()
            return
        }
        guard let provider = desktopPlanUsageReader
            as? any ClaudeDesktopPlanUsageObservationProviding
        else { return }
        let monitor = provider.makeMonitor { [weak self] in
            Task { await self?.refreshLocalInputs() }
        }
        desktopPlanUsageMonitor = monitor
        monitor.start()
    }

    private func loadSmartStateIfNeeded() async {
        guard !anchorsLoaded else { return }
        anchorsLoaded = true
        if let anchorStore {
            anchors = await anchorStore.load()
            for kind in [AgentRateLimitWindow.Kind.fiveHour, .sevenDay] {
                continuityGeneration[kind] = anchors
                    .filter { $0.windowKind == kind }
                    .map(\.continuityGeneration)
                    .max() ?? 0
            }
        }
    }

    private func refreshLocalInputs() async {
        guard await hasConsent() else { return }
        await loadSmartStateIfNeeded()
        localSmartReadError = false
        if let localActivityReader {
            localActivityReaderInvocationCount += 1
            claudeProjectsAccessCount += 1
            latestActivity = ClaudeSanitizedLocalActivity.project(
                localActivityReader.read(now: now())
            )
        }
        if let desktopPlanUsageReader {
            desktopPlanUsageReadCount += 1
            latestDesktopPlanUsage = desktopPlanUsageReader.read(now: now())
            if latestDesktopPlanUsage != nil {
                desktopPlanUsageAcceptedCount += 1
            }
        }
        if let statusStateStore {
            do {
                if let packet = try statusStateStore.read() {
                    await acceptStatusLine(packet, publish: false)
                } else if latestActivity != nil {
                    setLocalSmartStage(desktopActivityContract == .estimateOnlyNoActivitySignal
                        ? .localCodeActivityDetectedDesktopUnavailable
                        : .localActivityDetectedAwaitingExactAnchor)
                } else if desktopActivityContract == .estimateOnlyNoActivitySignal {
                    setLocalSmartStage(.desktopActivitySignalUnavailable)
                } else if localSmartStage == nil {
                    setLocalSmartStage(.localStatusLinePending)
                }
            } catch {
                // Unsafe or malformed state is rejected without replacing the
                // failure with private filesystem or provider detail.
                rejectedObservationCount += 1
                localSmartReadError = true
                setLocalSmartStage(.localStatusLineRejected)
            }
        }
        if desktopActivityContract == .estimateOnlyNoActivitySignal {
            if latestActivity != nil,
               localSmartStage == nil || localSmartStage == .localStatusLinePending
                    || localSmartStage == .desktopActivitySignalUnavailable {
                setLocalSmartStage(.localCodeActivityDetectedDesktopUnavailable)
            } else if latestActivity == nil,
                      localSmartStage == nil || localSmartStage == .localStatusLinePending {
                setLocalSmartStage(.desktopActivitySignalUnavailable)
            }
        }
        await publishSmartSnapshot()
    }

    private func acceptStatusLine(
        _ packet: ClaudeStatusLinePacket,
        publish: Bool = true
    ) async {
        let current = now()
        guard packet.observedAt <= current.addingTimeInterval(Self.maximumFutureSkew) else {
            rejectedObservationCount += 1
            return
        }
        guard packet.fiveHour != nil || packet.sevenDay != nil else {
            // The official callback ran, but this response did not expose
            // Pro/Max rate-limit fields. This is valid content-free receipt
            // evidence, not a malformed or rejected provider observation.
            acceptedObservationCount += 1
            setLocalSmartStage(.localCallbackWithoutQuotaWindows)
            if publish { await publishSmartSnapshot() }
            return
        }
        let priorAnchors = anchors
        let priorContinuityGeneration = continuityGeneration
        if let window = packet.fiveHour {
            addExactAnchor(
                kind: .fiveHour,
                usedPercent: window.usedPercentage,
                resetsAt: Date(timeIntervalSince1970: TimeInterval(window.resetsAtEpochSeconds)),
                observedAt: packet.observedAt,
                source: .exactLocalStatusLine,
                schema: "status-\(packet.schemaVersion)"
            )
        }
        if let window = packet.sevenDay {
            addExactAnchor(
                kind: .sevenDay,
                usedPercent: window.usedPercentage,
                resetsAt: Date(timeIntervalSince1970: TimeInterval(window.resetsAtEpochSeconds)),
                observedAt: packet.observedAt,
                source: .exactLocalStatusLine,
                schema: "status-\(packet.schemaVersion)"
            )
        }
        let requiredCommit = anchors.filter { !priorAnchors.contains($0) }
        do {
            try await commitAnchors(required: requiredCommit)
        } catch {
            anchors = priorAnchors
            continuityGeneration = priorContinuityGeneration
            rejectedObservationCount += 1
            localSmartReadError = true
            setLocalSmartStage(.localStatusLineRejected)
            if publish { await publishSmartSnapshot() }
            return
        }
        acceptedObservationCount += 1
        setLocalSmartStage(.localExactReceived)
        if publish { await publishSmartSnapshot() }
    }

    private func acceptSafariAccuracy(
        _ envelope: ClaudeBrowserObservationEnvelope,
        observedAt: Date
    ) async throws {
        let priorAnchors = anchors
        let priorContinuityGeneration = continuityGeneration
        var admitted = 0
        if let window = envelope.observation.fiveHour {
            let reset = try Self.resetDate(window.resetAt)
            addExactAnchor(
                kind: .fiveHour,
                usedPercent: window.usedPercentage,
                resetsAt: reset,
                observedAt: observedAt,
                source: .exactSafariAccuracy,
                schema: "safari-2"
            )
            admitted += 1
        }
        if let window = envelope.observation.weeklyAllModels {
            let reset = try Self.resetDate(window.resetAt)
            addExactAnchor(
                kind: .sevenDay,
                usedPercent: window.usedPercentage,
                resetsAt: reset,
                observedAt: observedAt,
                source: .exactSafariAccuracy,
                schema: "safari-2"
            )
            admitted += 1
        }
        guard admitted > 0 else { throw ClaudeBrowserBridgeError.noAccountWindow }
        let requiredCommit = anchors.filter { !priorAnchors.contains($0) }
        do {
            // Optional-reset Safari observations are sanitized exact state and
            // survive app relaunch. Estimation independently requires a real
            // reset, so durability never turns them into calibration anchors.
            try await commitAnchors(required: requiredCommit)
        } catch {
            anchors = priorAnchors
            continuityGeneration = priorContinuityGeneration
            throw error
        }
        await publishSmartSnapshot()
    }

    /// Exact truth is visible only after the owner-only store has atomically
    /// replaced its prior generation and a fresh read proves that the exact
    /// records being acknowledged are present. Production never treats a
    /// missing store or a write-only test double as a successful commit.
    private func commitAnchors(
        required: [ClaudeSmartWindowAnchor]
    ) async throws {
        guard let anchorStore else {
            throw ClaudeSmartAnchorStore.StoreError.commitVerificationFailed
        }
        try await anchorStore.save(anchors)
        let committed = await anchorStore.load()
        guard required.allSatisfy(committed.contains) else {
            throw ClaudeSmartAnchorStore.StoreError.commitVerificationFailed
        }
        anchors = committed
        for kind in [AgentRateLimitWindow.Kind.fiveHour, .sevenDay] {
            continuityGeneration[kind] = committed
                .filter { $0.windowKind == kind }
                .map(\.continuityGeneration)
                .max() ?? 0
        }
    }

    private func addExactAnchor(
        kind: AgentRateLimitWindow.Kind,
        usedPercent: Double,
        resetsAt: Date?,
        observedAt: Date,
        source: ClaudeSmartSourceKind,
        schema: String
    ) {
        if anchors.contains(where: {
            $0.windowKind == kind
                && $0.source == source
                && $0.observedAt == observedAt
                && $0.usedPercent == usedPercent
                && $0.resetsAt == resetsAt
        }) { return }

        let latest = anchors
            .filter { $0.windowKind == kind && $0.resetsAt != nil }
            .max { $0.observedAt < $1.observedAt }
        var generation = continuityGeneration[kind, default: 0]
        let modelChanged = latest.map {
            $0.modelFamilyKey == nil
                || latestActivity?.modelFamilyKey == nil
                || $0.modelFamilyKey != latestActivity?.modelFamilyKey
        } ?? false
        let sourceContractChanged = latest.map {
            $0.source != source || $0.sourceSchema != schema
        } ?? false
        let discontinuity = resetsAt != nil && (latest.map {
            $0.resetsAt != resetsAt
                || (observedAt >= $0.observedAt && usedPercent + 0.000_001 < $0.usedPercent)
                || modelChanged
                || sourceContractChanged
        } ?? false)
        if discontinuity {
            generation &+= 1
            continuityGeneration[kind] = generation
            previousEstimates[kind] = nil
        }
        guard let anchor = ClaudeSmartWindowAnchor(
            windowKind: kind,
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            observedAt: observedAt,
            activityTotalTokens: resetsAt == nil ? nil : latestActivity?.totalTokens,
            source: source,
            modelFamilyKey: resetsAt == nil ? nil : latestActivity?.modelFamilyKey,
            sourceSchema: schema,
            continuityGeneration: generation
        ) else { return }
        anchors.append(anchor)
        anchors = Array(anchors.sorted { $0.observedAt < $1.observedAt }.suffix(24))
    }

    private func publishSmartSnapshot() async {
        let current = now()
        var values: [ClaudeSmartWindowValue] = []
        var localEstimateDates: [Date] = []
        for kind in [AgentRateLimitWindow.Kind.fiveHour, .sevenDay] {
            let estimate = ClaudeSmartUsageEstimator.estimate(
                windowKind: kind,
                anchors: anchors,
                activity: latestActivity,
                previousEstimatedRemaining: previousEstimates[kind],
                now: current
            )
            if let estimate {
                previousEstimates[kind] = estimate.remainingPercent
                localEstimateDates.append(estimate.observedAt)
            }
            let matching = anchors.filter { $0.windowKind == kind }
            let selected = ClaudeSmartSourceSelector.select(
                windowKind: kind,
                statusLineAnchors: matching.filter { $0.source == .exactLocalStatusLine },
                safariAnchors: matching.filter { $0.source == .exactSafariAccuracy },
                estimate: estimate,
                desktopEstimate: latestDesktopPlanUsage?.value(for: kind),
                staleExact: matching.max { $0.observedAt < $1.observedAt },
                now: current
            )
            if let selected { values.append(selected) }
        }

        currentQuotaIncludesSafariAccuracy = values.contains {
            $0.source == .exactSafariAccuracy
        }
        refreshIndependentSourceStates(
            now: current,
            localEstimateDates: localEstimateDates
        )

        guard !values.isEmpty else {
            lifecycle = .waitingForUsagePage
            if let activity = latestActivity {
                // Local usage was safely projected even though no exact quota
                // anchor exists yet. Publish that truthful channel without
                // manufacturing a remaining percentage or claiming that no
                // Claude response has been observed.
                let activityDate = activity.latestActivityAt ?? activity.observedAt
                let activityFreshness = Self.localActivityFreshness(
                    observedAt: activityDate,
                    now: current
                )
                lifecycle = activityFreshness == .fresh
                    ? .fresh(activityDate)
                    : (activityFreshness == .cached
                        ? .cached(activityDate)
                        : .stale(activityDate))
                replace(AgentUsageSnapshot(
                    id: Self.connectorID,
                    providerName: "Claude Code",
                    state: activityFreshness == .stale ? .stale : .ready,
                    capturedAt: current,
                    lastSuccessfulAt: activityDate,
                    freshness: activityFreshness,
                    channels: [localActivityChannel(activity, now: current)],
                    capabilities: Self.capabilities,
                    safeFailure: nil
                ))
                return
            }
            if localSmartStage == .localCallbackWithoutQuotaWindows {
                // The official callback ran, but exact Pro/Max windows were
                // absent. Keep quota empty while distinguishing this verified
                // receipt from a never-invoked status-line integration.
                replace(AgentUsageSnapshot(
                    id: Self.connectorID,
                    providerName: "Claude Code",
                    state: .ready,
                    capturedAt: current,
                    lastSuccessfulAt: nil,
                    freshness: .unavailable,
                    channels: [],
                    capabilities: Self.capabilities,
                    safeFailure: nil
                ))
                return
            }
            replace(Self.unavailableSnapshot(
                state: desktopActivityContract == .estimateOnlyNoActivitySignal
                    ? .unsupported
                    : .waitingForFirstResponse,
                failure: nil,
                capturedAt: current
            ))
            return
        }
        let containsEstimate = values.contains(where: \.isEstimated)
        let containsCurrentExact = values.contains {
            $0.source == .exactLocalStatusLine || $0.source == .exactSafariAccuracy
        }
        let containsOnlyStale = values.allSatisfy { $0.source == .staleExact }
        let freshness: AgentConnectorFreshness = containsCurrentExact
            ? .fresh
            : (containsOnlyStale ? .stale : .cached)
        let estimatedValues = values.filter(\.isEstimated)
        let containsDesktopEstimate = values.contains {
            $0.source == .estimatedDesktopCache
        }
        let confidence = estimatedValues.map(\.confidence).min(by: {
            Self.confidenceRank($0) < Self.confidenceRank($1)
        }) ?? .high
        let lastExactAt = values.filter {
            $0.source == .exactLocalStatusLine || $0.source == .exactSafariAccuracy
        }.map(\.observedAt).max()
        let account = AgentUsageChannel(
            id: .account,
            sourceTier: containsEstimate
                ? .authorizedLocalEstimate
                : .officialStructuredHook,
            sourceVersion: "smart-1",
            scopes: [.account],
            provenance: containsEstimate ? .locallyEstimated : .providerReported,
            freshness: freshness,
            capturedAt: values.map(\.observedAt).max(),
            coverageNote: containsDesktopEstimate
                ? "Claude Desktop plan usage · estimated"
                : "Claude Local Smart Mode",
            sourceConfidence: containsEstimate ? confidence.rawValue : "exact",
            lastExactAt: lastExactAt,
            rateLimitWindows: values.map {
                AgentRateLimitWindow(
                    id: $0.windowKind == .fiveHour ? "five-hour" : "seven-day",
                    kind: $0.windowKind,
                    usedPercent: nil,
                    remainingPercent: $0.remainingPercent,
                    isEstimated: $0.isEstimated,
                    isUnlimited: false,
                    resetsAt: $0.resetsAt
                )
            },
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: freshness == .stale ? .unavailable : nil
        )
        var channels = [account]
        if let activity = latestActivity {
            channels.append(localActivityChannel(activity, now: current))
        }
        let next = AgentUsageSnapshot(
            id: Self.connectorID,
            providerName: "Claude Code",
            state: freshness == .stale ? .stale : .ready,
            capturedAt: current,
            lastSuccessfulAt: values.map(\.observedAt).max(),
            freshness: freshness,
            channels: channels,
            capabilities: Self.capabilities,
            safeFailure: freshness == .stale ? .unavailable : nil
        )
        lastGood = next
        lifecycle = freshness == .fresh
            ? .fresh(next.lastSuccessfulAt ?? current)
            : (freshness == .cached
                ? .cached(next.lastSuccessfulAt ?? current)
                : .stale(next.lastSuccessfulAt ?? current))
        replace(next)
    }

    private func refreshIndependentSourceStates(
        now current: Date,
        localEstimateDates: [Date]
    ) {
        let currentLocalExact = anchors.filter {
            $0.source == .exactLocalStatusLine
                && ($0.resetsAt.map { $0 > current } ?? false)
                && current.timeIntervalSince($0.observedAt) >= 0
                && current.timeIntervalSince($0.observedAt)
                    <= ClaudeSmartSourceSelector.exactFreshnessInterval
        }.max { $0.observedAt < $1.observedAt }
        let latestLocalAnchor = anchors.filter {
            $0.source == .exactLocalStatusLine
        }.max { $0.observedAt < $1.observedAt }

        if let currentLocalExact {
            localSmartState = .exactLocal(currentLocalExact.observedAt)
        } else if let estimatedAt = (
            localEstimateDates + [latestDesktopPlanUsage?.observedAt].compactMap { $0 }
        ).max() {
            localSmartState = .estimated(estimatedAt)
        } else if localSmartReadError {
            localSmartState = .error
        } else if let latestLocalAnchor {
            localSmartState = .staleUnsupported(latestLocalAnchor.observedAt)
        } else if desktopActivityContract == .estimateOnlyNoActivitySignal {
            localSmartState = .staleUnsupported(nil)
        } else {
            localSmartState = .unavailable
        }

        guard browserAccuracyState != .syncing else { return }
        if let exactAt = currentSafariAccuracyObservedAt() {
            browserAccuracyState = .exactAnchorAvailable(exactAt)
        } else if case .exactAnchorAvailable = browserAccuracyState {
            browserAccuracyState = .ready
        }
    }

    private func localActivityChannel(
        _ activity: ClaudeSanitizedLocalActivity,
        now: Date
    ) -> AgentUsageChannel {
        let surfaces = activity.observedSurfaces.map(\.displayName)
        let coverageNote = surfaces.isEmpty
            ? "Sanitized local usage metadata"
            : "Observed surfaces: " + surfaces.joined(separator: ", ")
        return AgentUsageChannel(
            id: .localActivity,
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "local-sanitized-1",
            scopes: [.session],
            provenance: .locallyEstimated,
            freshness: Self.localActivityFreshness(
                observedAt: activity.latestActivityAt ?? activity.observedAt,
                now: now
            ),
            capturedAt: activity.latestActivityAt ?? activity.observedAt,
            coverageNote: coverageNote,
            sourceConfidence: activity.deduplicationConfidence == .exact
                ? "medium" : "low",
            rateLimitWindows: [],
            accountMetrics: nil,
            localActivityMetrics: AgentLocalActivityMetrics(
                recentTaskCount: nil,
                recentTaskTokens: [],
                recentTaskCapturedAt: [],
                sessionTokens: activity.totalTokens,
                estimatedSevenDayUSD: nil,
                estimatedLifetimeUSD: nil,
                coveragePercent: activity.coveragePercent,
                recognizedModelCount: activity.modelFamilyKey == nil ? 0 : 1
            ),
            safeFailure: nil
        )
    }

    private static func localActivityFreshness(
        observedAt: Date,
        now: Date
    ) -> AgentConnectorFreshness {
        let age = now.timeIntervalSince(observedAt)
        if age < 0 || age >= maximumRetainedAge { return .stale }
        if age >= freshnessInterval { return .cached }
        return .fresh
    }

    private static func confidenceRank(_ value: ClaudeSmartConfidence) -> Int {
        switch value {
        case .high: 3
        case .medium: 2
        case .low: 1
        case .insufficient: 0
        }
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

    private func setLocalSmartStage(_ stage: ClaudeLiveLinkStageReason) {
        localSmartStage = stage
        lastLiveLinkStage = stage
    }

    private func setBrowserAccuracyStage(_ stage: ClaudeLiveLinkStageReason) {
        browserAccuracyStage = stage
        lastLiveLinkStage = stage
    }

    private func currentSafariAccuracyObservedAt() -> Date? {
        let current = now()
        return anchors.filter {
            $0.source == .exactSafariAccuracy
                && ($0.resetsAt.map { $0 > current } ?? true)
                && current.timeIntervalSince($0.observedAt) >= 0
                && current.timeIntervalSince($0.observedAt)
                    <= ClaudeSmartSourceSelector.exactFreshnessInterval
        }.map(\.observedAt).max()
    }

    private func currentSafariAccuracyState(
        or fallback: ClaudeBrowserAccuracyState
    ) -> ClaudeBrowserAccuracyState {
        currentSafariAccuracyObservedAt().map(ClaudeBrowserAccuracyState.exactAnchorAvailable)
            ?? fallback
    }

    /// Browser health is source-scoped. It updates only the one-shot Accuracy
    /// state and a compatibility lifecycle used by older settings surfaces;
    /// it never clears anchors, Local Smart inputs, or the effective snapshot.
    private func apply(_ health: ClaudeBrowserCompanionHealth) {
        let unavailableLifecycle: ClaudeConnectorLifecycleState
        switch health {
        case .ready:
            browserAccuracyStage = nil
            browserAccuracyState = currentSafariAccuracyState(or: .ready)
            unavailableLifecycle = .waitingForUsagePage
        case .inventoryRestartRequired:
            setBrowserAccuracyStage(.accuracyInventoryRestartRequired)
            browserAccuracyState = .updatePendingRestart
            unavailableLifecycle = .inventoryRestartRequired
        case .inventoryLoading:
            setBrowserAccuracyStage(.accuracyInventoryLoading)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            unavailableLifecycle = .inventoryLoading
        case .companionStarting:
            setBrowserAccuracyStage(.accuracyCompanionStarting)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            unavailableLifecycle = .companionStarting
        case .protocolMismatch:
            setBrowserAccuracyStage(.accuracyProtocolMismatch)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            unavailableLifecycle = .protocolMismatch
        case .companionUnavailable:
            setBrowserAccuracyStage(.accuracyCompanionUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            unavailableLifecycle = .companionUnavailable
        case .browserUnavailable:
            setBrowserAccuracyStage(.accuracyBrowserUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            unavailableLifecycle = .browserUnavailable
        case .disabled:
            setBrowserAccuracyStage(.accuracyCompanionUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            unavailableLifecycle = .companionDisabled
        case .outdated:
            setBrowserAccuracyStage(.accuracyProtocolMismatch)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            unavailableLifecycle = .companionOutdated
        case .unsupportedBrowser:
            setBrowserAccuracyStage(.accuracyCompanionUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            unavailableLifecycle = .unsupportedBrowser
        case .nativeHostMissing:
            setBrowserAccuracyStage(.accuracyCompanionUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            unavailableLifecycle = .nativeHostMissing
        case .nativeHostMismatched:
            setBrowserAccuracyStage(.accuracyProtocolMismatch)
            browserAccuracyState = currentSafariAccuracyState(or: .error)
            unavailableLifecycle = .nativeHostMismatched
        case .extensionNotInstalled:
            setBrowserAccuracyStage(.accuracyCompanionUnavailable)
            browserAccuracyState = currentSafariAccuracyState(or: .companionUnavailable)
            unavailableLifecycle = .extensionNotInstalled
        }
        lifecycle = snapshot.hasValidData
            ? lifecycleForCurrentSnapshot()
            : unavailableLifecycle
    }

    private func probeState(for health: ClaudeBrowserCompanionHealth) -> AgentConnectorState {
        switch health {
        case .ready: .waitingForFirstResponse
        case .disabled, .outdated, .nativeHostMissing, .nativeHostMismatched,
             .extensionNotInstalled, .inventoryRestartRequired, .inventoryLoading,
             .companionStarting, .protocolMismatch, .companionUnavailable:
            .waitingForFirstResponse
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
            coverageNote: "Claude official Usage page · one-shot Accuracy Sync",
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
