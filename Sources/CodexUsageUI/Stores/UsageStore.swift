import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    static let productionVisibleRefreshInterval: Duration = .seconds(15)
    static let productionBackgroundRefreshInterval: Duration = .seconds(30)
    static let productionPanelOpenRefreshMinimumAge: TimeInterval = 15

    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var providerSnapshots: [AgentUsageSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastFailure: CodexUsageClientFailure?
    @Published public private(set) var language: AppLanguage
    @Published private(set) var connectionState: CodexConnectionState
    @Published private(set) var monitorConsentGranted = false
    @Published public private(set) var monitorConsentDecision: CodexMonitorConsentDecision
    @Published public private(set) var freshness: UsageFreshness
    @Published public private(set) var isPanelVisible = false

    private let registry: AgentConnectorRegistry?
    private let primaryConnectorID: AgentConnectorID?
    private let previewOnly: Bool
    private let previewDisplaysFixtureData: Bool
    private let consentDefaults: UserDefaults?
    private let autoRefreshEnabled: Bool
    private let visibleRefreshInterval: Duration
    private let backgroundRefreshInterval: Duration
    private let panelOpenRefreshMinimumAge: TimeInterval
    private let now: () -> Date
    private let resumesPersistedAuthorizedConnection: Bool
    private var registrySubscription: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?
    private var periodicRefreshGeneration: UInt64 = 0
    private var periodicRefreshUsesVisibleInterval: Bool?
    /// Store callers join this task before reaching the registry. It keeps
    /// menu actions, lifecycle wake, timer, panel-open, and reconnect requests
    /// from creating parallel connector commands above the client-level
    /// coordinator.
    private var activeRefreshTask: Task<Void, Never>?
    private var activeRefreshGeneration: UInt64 = 0

    public convenience init(autoRefresh: Bool = true, language: AppLanguage? = nil) {
        self.init(
            autoRefresh: autoRefresh,
            previewOnly: false,
            language: language,
            registry: AgentUsageRuntime.makeCodexRegistry(),
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: .standard
        )
    }

    public convenience init(autoRefresh: Bool = true, previewOnly: Bool, language: AppLanguage? = nil) {
        self.init(
            autoRefresh: autoRefresh,
            previewOnly: previewOnly,
            language: language,
            registry: previewOnly ? nil : AgentUsageRuntime.makeCodexRegistry(),
            primaryConnectorID: previewOnly ? nil : CodexUsageConnector.connectorID,
            consentDefaults: previewOnly ? nil : .standard
        )
    }

    public static func preview(
        scenario: CodexPreviewScenario = .ready,
        language: AppLanguage = .simplifiedChinese
    ) -> UsageStore {
        UsageStore(
            autoRefresh: false,
            previewOnly: true,
            language: language,
            registry: nil,
            primaryConnectorID: nil,
            consentDefaults: nil,
            previewScenario: scenario
        )
    }

    init(
        autoRefresh: Bool = true,
        previewOnly: Bool = false,
        language: AppLanguage? = nil,
        registry: AgentConnectorRegistry?,
        primaryConnectorID: AgentConnectorID?,
        consentDefaults: UserDefaults? = nil,
        previewScenario: CodexPreviewScenario = .ready,
        visibleRefreshInterval: Duration = UsageStore.productionVisibleRefreshInterval,
        backgroundRefreshInterval: Duration = UsageStore.productionBackgroundRefreshInterval,
        panelOpenRefreshMinimumAge: TimeInterval = UsageStore.productionPanelOpenRefreshMinimumAge,
        now: @escaping () -> Date = { Date() }
    ) {
        let selectedLanguage = language ?? AppLanguage.resolveAndPersist()
        self.registry = registry
        self.primaryConnectorID = primaryConnectorID
        self.previewOnly = previewOnly
        self.previewDisplaysFixtureData = previewOnly && previewScenario.displaysFixtureData
        self.consentDefaults = consentDefaults
        self.autoRefreshEnabled = autoRefresh
        self.visibleRefreshInterval = visibleRefreshInterval
        self.backgroundRefreshInterval = backgroundRefreshInterval
        self.panelOpenRefreshMinimumAge = max(0, panelOpenRefreshMinimumAge)
        self.now = now
        self.language = selectedLanguage
        self.snapshot = previewOnly && previewScenario.displaysFixtureData ? .preview(language: selectedLanguage) : .empty(language: selectedLanguage)
        self.connectionState = previewOnly ? previewScenario.connectionState : .notAuthorizedByMonitor
        self.isRefreshing = previewOnly && previewScenario == .refreshing
        let decision = previewOnly ? .granted : CodexMonitorConsentDecision.load(from: consentDefaults)
        self.resumesPersistedAuthorizedConnection = !previewOnly && decision == .granted
        self.monitorConsentDecision = decision
        self.monitorConsentGranted = decision == .granted
        if !previewOnly, decision == .granted { self.connectionState = .idle }
        self.freshness = previewOnly ? .fixture : .noRealData
        beginRegistryObservation()
    }

    /// `nil` remains distinct from an actual 0% quota. An authoritative
    /// unlimited five-hour grant is rendered as ∞ in the panel, so it must
    /// not make the compact status item claim a misleading ordinary 100%.
    public var menuPercent: Int? {
        snapshot.periods.first(where: { !$0.isUnlimited })?.remainingPercent
    }

    public var statusText: String {
        if previewOnly, connectionState == .ready { return language.demoStatus }
        return connectionState.statusText(language: language)
    }

    public var currentState: CodexConnectionState { connectionState }

    public var hasPriorRealSnapshot: Bool {
        providerSnapshots.contains(where: \.hasValidData) || previewDisplaysFixtureData
    }

    public var allowsManualRefresh: Bool {
        let hasVisibleProviderData = snapshot.providerSource?.isAvailable == true
        guard monitorConsentGranted, hasPriorRealSnapshot || hasVisibleProviderData else { return false }
        return connectionState == .ready || connectionState.isFailure
    }

    public func grantMonitorConsent() {
        guard !previewOnly, monitorConsentDecision != .granted else { return }
        monitorConsentDecision = .granted
        monitorConsentDecision.persist(to: consentDefaults)
        monitorConsentGranted = true
        connectionState = .idle
        freshness = hasPriorRealSnapshot ? .stale : .noRealData
        lastError = nil
        lastFailure = nil
    }

    public func declineMonitorConsent() async {
        await disconnectPrimary(clearConsent: true, decision: .declined)
    }

    public func handleLocalAccessDecision(_ accepted: Bool) {
        guard accepted else {
            Task { @MainActor in await declineMonitorConsent() }
            return
        }
        let wasGranted = monitorConsentGranted
        grantMonitorConsent()
        if !wasGranted { beginConnection(.connect) }
    }

    public func requestReconnect() {
        Task { @MainActor [weak self] in
            await self?.reconnectMonitor()
        }
    }

    public func refresh() async { await refresh(trigger: .manual) }

    /// Every account-refresh cause enters the one registry/client refresh
    /// lane. Local display-age changes deliberately never call this method.
    public func refresh(trigger: CodexRefreshTrigger) async {
        guard !previewOnly, monitorConsentGranted, let registry, let id = primaryConnectorID else {
            if !previewOnly { setConsentMissingFailure() }
            return
        }
        await runCoordinatedRefresh { [weak self] in
            guard let self else { return }
            await self.performRefresh(trigger: trigger, registry: registry, id: id)
        }
    }

    private func runCoordinatedRefresh(
        _ operation: @escaping @MainActor () async -> Void
    ) async {
        if let activeRefreshTask {
            await activeRefreshTask.value
            return
        }
        activeRefreshGeneration &+= 1
        let generation = activeRefreshGeneration
        let task = Task { @MainActor in await operation() }
        activeRefreshTask = task
        await task.value
        guard activeRefreshGeneration == generation else { return }
        activeRefreshTask = nil
    }

    private func performRefresh(
        trigger: CodexRefreshTrigger,
        registry: AgentConnectorRegistry,
        id: AgentConnectorID
    ) async {
        isRefreshing = true
        connectionState = hasPriorRealSnapshot ? .refreshingWithPreviousRealData : .resolvingExecutable
        do {
            try await registry.refresh(id, trigger: trigger)
            guard !Task.isCancelled else { return }
            receive(await registry.orderedSnapshots())
        }
        catch {
            guard !Task.isCancelled else { return }
            applyRegistryFailure(.unknown)
        }
    }

    public func connectToLocalSession() async { await performPrimary(.connect) }
    public func checkLocalSessionAgain() async { await performPrimary(.connect) }

    public func cancelLocalSessionReconciliation() async {
        await disconnectPrimary(clearConsent: false)
    }

    public func disconnectMonitor() async {
        await disconnectPrimary(clearConsent: false)
    }

    public func disconnectAndForgetConsent() async {
        await disconnectPrimary(clearConsent: true)
    }

    public func reconnectMonitor() async {
        guard !previewOnly, monitorConsentGranted, let registry, let id = primaryConnectorID else {
            if !previewOnly { setConsentMissingFailure() }
            return
        }
        await runCoordinatedRefresh { [weak self] in
            await self?.performPrimary(.reconnect, registry: registry, id: id)
        }
    }

    /// Lifecycle code invokes this once after a system wake. It joins any
    /// existing provider read rather than starting another connector or child.
    public func handleApplicationWake() async { await refresh(trigger: .wake) }

    /// Called by the application lifecycle, not by a single provider view.
    public func stopAllConnectors() async {
        guard !previewOnly, let registry else { return }
        connectionTask?.cancel()
        cancelActiveRefresh()
        periodicRefreshGeneration &+= 1
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        periodicRefreshUsesVisibleInterval = nil
        await registry.stopAll()
    }

    public func setPanelVisible(_ isVisible: Bool) {
        guard !previewOnly else { return }
        guard isPanelVisible != isVisible else { return }
        isPanelVisible = isVisible
        updatePeriodicRefreshSchedule()
        guard isVisible, shouldRefreshOnPanelOpen else { return }
        Task { @MainActor [weak self] in
            await self?.refresh(trigger: .timer)
        }
    }

    static func shouldRefreshOnPanelOpen(
        lastSuccessfulAt: Date?,
        now: Date,
        minimumAge: TimeInterval
    ) -> Bool {
        guard let lastSuccessfulAt else { return false }
        return now.timeIntervalSince(lastSuccessfulAt) >= max(0, minimumAge)
    }

    public func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: AppLanguage.storageKey)
        if let primary = primarySnapshot {
            snapshot = UsageSnapshot(agentSnapshot: primary, language: newLanguage)
        } else if previewDisplaysFixtureData {
            snapshot = .preview(language: newLanguage)
        } else {
            snapshot = .empty(language: newLanguage)
        }
    }

    private func beginRegistryObservation() {
        guard let registry else { return }
        registrySubscription = Task { [weak self] in
            await registry.restorePersistedSnapshots()
            let stream = await registry.snapshots()
            self?.resumePersistedAuthorizedConnection()
            for await snapshots in stream {
                guard !Task.isCancelled else { return }
                self?.receive(snapshots)
            }
        }
    }

    /// A persisted monitor authorization is enough to resume the one owned
    /// Codex session after a restart.  The registry stream yields its stale
    /// snapshot first; the reconnect then replaces it with a fresh provider
    /// snapshot without requiring another Connect/Allow interaction.
    private func resumePersistedAuthorizedConnection() {
        guard resumesPersistedAuthorizedConnection, monitorConsentGranted else { return }
        beginConnection(.connect)
    }

    private func receive(_ snapshots: [AgentUsageSnapshot]) {
        guard !previewOnly, monitorConsentGranted else { return }
        // The registry stream is installed asynchronously. Its initial empty
        // yield can race a completed direct refresh; it must not erase the
        // newly verified primary snapshot or turn live values into an
        // apparent no-data state.
        guard !snapshots.isEmpty || providerSnapshots.isEmpty else { return }
        providerSnapshots = snapshots
        guard let primary = primarySnapshot else { return }
        snapshot = UsageSnapshot(agentSnapshot: primary, language: language)
        let nextConnectionState = Self.presentationState(
            primary.state,
            failure: primary.safeFailure
        )
        // The production connector publishes a waiting snapshot before every
        // read and while replacing an exited owned child. That snapshot
        // deliberately retains the last valid channels, so both coordinated
        // refreshes and transport recovery must keep presenting them instead
        // of briefly replacing the panel with the first-connection bridge.
        if primary.hasValidData,
           (primary.state == .waitingForFirstResponse || (isRefreshing && primary.state == .inactive)) {
            connectionState = .refreshingWithPreviousRealData
        } else {
            connectionState = nextConnectionState
        }
        freshness = Self.presentationFreshness(primary.freshness)
        lastFailure = primary.safeFailure.map(Self.codexFailure)
        lastError = codexFailureDescription(lastFailure)
        if primary.state == .ready || primary.state == .stale || primary.state == .authenticationRequired || primary.state == .failed {
            isRefreshing = false
        }
        updatePeriodicRefreshSchedule()
    }

    private var primarySnapshot: AgentUsageSnapshot? {
        guard let primaryConnectorID else { return nil }
        return providerSnapshots.first(where: { $0.id == primaryConnectorID })
    }

    private func beginConnection(_ command: AgentConnectorCommand) {
        guard !previewOnly, monitorConsentGranted, connectionTask == nil else { return }
        connectionTask = Task { @MainActor [weak self] in
            defer { self?.connectionTask = nil }
            await self?.performPrimary(command)
        }
    }

    private func performPrimary(_ command: AgentConnectorCommand) async {
        guard !previewOnly, monitorConsentGranted, let registry, let id = primaryConnectorID else {
            if !previewOnly { setConsentMissingFailure() }
            return
        }
        await performPrimary(command, registry: registry, id: id)
    }

    private func performPrimary(
        _ command: AgentConnectorCommand,
        registry: AgentConnectorRegistry,
        id: AgentConnectorID
    ) async {
        isRefreshing = true
        connectionState = .resolvingExecutable
        do {
            try await registry.perform(command, for: id)
            receive(await registry.orderedSnapshots())
        }
        catch { applyRegistryFailure(.unknown) }
    }

    private func disconnectPrimary(
        clearConsent: Bool,
        decision: CodexMonitorConsentDecision = .unknown
    ) async {
        guard !previewOnly else { return }
        connectionTask?.cancel()
        connectionTask = nil
        cancelActiveRefresh()
        isRefreshing = false
        if let registry, let id = primaryConnectorID {
            try? await registry.perform(.disconnect, for: id)
        }
        if clearConsent {
            monitorConsentGranted = false
            monitorConsentDecision = decision
            monitorConsentDecision.persist(to: consentDefaults)
            providerSnapshots = []
            snapshot = .empty(language: language)
            freshness = .noRealData
            connectionState = .notAuthorizedByMonitor
        } else {
            connectionState = monitorConsentGranted ? .idle : .notAuthorizedByMonitor
            freshness = hasPriorRealSnapshot ? .stale : .noRealData
        }
        lastError = nil
        lastFailure = nil
        updatePeriodicRefreshSchedule()
    }

    private func setConsentMissingFailure() {
        connectionState = .notAuthorizedByMonitor
        freshness = hasPriorRealSnapshot ? .stale : .noRealData
        lastFailure = .monitorConsentMissing
        lastError = codexFailureDescription(lastFailure)
    }

    private func applyRegistryFailure(_ failure: AgentSafeFailure) {
        isRefreshing = false
        lastFailure = Self.codexFailure(failure)
        lastError = codexFailureDescription(lastFailure)
        connectionState = hasPriorRealSnapshot ? .staleWithPreviousRealData(lastFailure!) : .recoverableFailure(lastFailure!)
        freshness = hasPriorRealSnapshot ? .stale : .noRealData
    }

    private func cancelActiveRefresh() {
        activeRefreshGeneration &+= 1
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
    }

    private var allowsPeriodicRefresh: Bool {
        autoRefreshEnabled && monitorConsentGranted && hasPriorRealSnapshot && connectionState == .ready
    }

    private var shouldRefreshOnPanelOpen: Bool {
        guard allowsManualRefresh else { return false }
        return Self.shouldRefreshOnPanelOpen(
            lastSuccessfulAt: primarySnapshot?.lastSuccessfulAt,
            now: now(),
            minimumAge: panelOpenRefreshMinimumAge
        )
    }

    private func updatePeriodicRefreshSchedule() {
        guard allowsPeriodicRefresh else {
            periodicRefreshGeneration &+= 1
            periodicRefreshTask?.cancel()
            periodicRefreshTask = nil
            periodicRefreshUsesVisibleInterval = nil
            return
        }
        let usesVisibleInterval = isPanelVisible
        if periodicRefreshTask != nil,
           periodicRefreshUsesVisibleInterval == usesVisibleInterval {
            return
        }
        periodicRefreshGeneration &+= 1
        periodicRefreshTask?.cancel()
        let generation = periodicRefreshGeneration
        periodicRefreshUsesVisibleInterval = usesVisibleInterval
        let interval = usesVisibleInterval ? visibleRefreshInterval : backgroundRefreshInterval
        periodicRefreshTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.periodicRefreshGeneration == generation {
                    self.periodicRefreshTask = nil
                    self.periodicRefreshUsesVisibleInterval = nil
                }
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self,
                      self.periodicRefreshGeneration == generation,
                      self.allowsPeriodicRefresh
                else { return }
                await self.refresh(trigger: .timer)
            }
        }
    }

    private static func presentationState(_ state: AgentConnectorState, failure: AgentSafeFailure?) -> CodexConnectionState {
        switch state {
        case .inactive: .idle
        case .authenticationRequired: .officialCodexSignInRequired
        case .waitingForFirstResponse: .checkingAccount
        case .ready: .ready
        case .stale: .staleWithPreviousRealData(codexFailure(failure ?? .unknown))
        case .unsupported: .blockedFailure(.protocolIncompatible)
        case .failed: .recoverableFailure(codexFailure(failure ?? .unknown))
        }
    }

    private static func presentationFreshness(_ freshness: AgentConnectorFreshness) -> UsageFreshness {
        switch freshness {
        case .fresh: .fresh
        case .stale: .stale
        case .unavailable: .noRealData
        }
    }

    private static func codexFailure(_ failure: AgentSafeFailure) -> CodexUsageClientFailure {
        switch failure {
        case .authorizationRequired: .accountAuthorizationRequired
        case .unavailable: .codexApplicationNotFound
        case .timedOut: .requestTimedOut(method: "connector")
        case .unsupported: .protocolIncompatible
        case .malformedResponse: .malformedResponse(method: "connector")
        case .processExited: .processExited
        case .unknown: .unknownSafeError
        }
    }

    private func codexFailureDescription(_ failure: CodexUsageClientFailure?) -> String? {
        failure.map { CodexUsageClientError($0).description(language: language) }
    }

    deinit {
        registrySubscription?.cancel()
        connectionTask?.cancel()
        periodicRefreshTask?.cancel()
    }
}
