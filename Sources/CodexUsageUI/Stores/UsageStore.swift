import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
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
    private let periodicRefreshInterval: Duration
    private var registrySubscription: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?

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
        periodicRefreshInterval: Duration = .seconds(240)
    ) {
        let selectedLanguage = language ?? AppLanguage.resolveAndPersist()
        self.registry = registry
        self.primaryConnectorID = primaryConnectorID
        self.previewOnly = previewOnly
        self.previewDisplaysFixtureData = previewOnly && previewScenario.displaysFixtureData
        self.consentDefaults = consentDefaults
        self.periodicRefreshInterval = periodicRefreshInterval
        self.language = selectedLanguage
        self.snapshot = previewOnly && previewScenario.displaysFixtureData ? .preview(language: selectedLanguage) : .empty(language: selectedLanguage)
        self.connectionState = previewOnly ? previewScenario.connectionState : .notAuthorizedByMonitor
        self.isRefreshing = previewOnly && previewScenario == .refreshing
        let decision = previewOnly ? .granted : CodexMonitorConsentDecision.load(from: consentDefaults)
        self.monitorConsentDecision = decision
        self.monitorConsentGranted = decision == .granted
        if !previewOnly, decision == .granted { self.connectionState = .idle }
        self.freshness = previewOnly ? .fixture : .noRealData
        _ = autoRefresh
        beginRegistryObservation()
    }

    /// `nil` remains distinct from an actual 0% quota.
    public var menuPercent: Int? { snapshot.periods.first?.remainingPercent }

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

    public func requestReconnect() { beginConnection(.reconnect) }

    public func refresh() async {
        guard !previewOnly, monitorConsentGranted, let registry, let id = primaryConnectorID else {
            if !previewOnly { setConsentMissingFailure() }
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        connectionState = hasPriorRealSnapshot ? .refreshingWithPreviousRealData : .resolvingExecutable
        do {
            try await registry.perform(.refresh, for: id)
            receive(await registry.orderedSnapshots())
        }
        catch { applyRegistryFailure(.unknown) }
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

    public func reconnectMonitor() async { await performPrimary(.reconnect) }

    /// Called by the application lifecycle, not by a single provider view.
    public func stopAllConnectors() async {
        guard !previewOnly, let registry else { return }
        connectionTask?.cancel()
        periodicRefreshTask?.cancel()
        await registry.stopAll()
    }

    public func setPanelVisible(_ isVisible: Bool) {
        guard !previewOnly else { return }
        isPanelVisible = isVisible
        updatePeriodicRefreshSchedule()
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
            for await snapshots in stream {
                guard !Task.isCancelled else { return }
                self?.receive(snapshots)
            }
        }
    }

    private func receive(_ snapshots: [AgentUsageSnapshot]) {
        guard !previewOnly, monitorConsentGranted else { return }
        providerSnapshots = snapshots
        guard let primary = primarySnapshot else { return }
        snapshot = UsageSnapshot(agentSnapshot: primary, language: language)
        connectionState = Self.presentationState(primary.state, failure: primary.safeFailure)
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

    private var allowsPeriodicRefresh: Bool {
        isPanelVisible && monitorConsentGranted && hasPriorRealSnapshot && connectionState == .ready
    }

    private func updatePeriodicRefreshSchedule() {
        guard allowsPeriodicRefresh else {
            periodicRefreshTask?.cancel()
            periodicRefreshTask = nil
            return
        }
        guard periodicRefreshTask == nil else { return }
        let interval = periodicRefreshInterval
        periodicRefreshTask = Task { @MainActor [weak self] in
            defer { self?.periodicRefreshTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, self.allowsPeriodicRefresh else { return }
                await self.refresh()
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
