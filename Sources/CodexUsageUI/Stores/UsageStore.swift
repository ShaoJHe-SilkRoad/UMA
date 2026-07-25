import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var providerSnapshots: [AgentUsageSnapshot] = []
    @Published public private(set) var presentationCards: [SharedUsageCardPresentation] = []
    @Published private(set) var providerLoginOptions: [ProviderLoginOption] = []
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
    private let performsLaunchScan: Bool
    private let consentDefaults: UserDefaults?
    private var registrySubscription: Task<Void, Never>?
    private var activeScanTask: Task<Void, Never>?
    private var activeScanTrigger: ProviderEligibilityScanTrigger?
    private var activeScanGeneration: UInt64 = 0

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

    public convenience init(
        autoRefresh: Bool = true,
        previewOnly: Bool,
        language: AppLanguage? = nil
    ) {
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
        language: AppLanguage = .simplifiedChinese,
        presentationCards: [SharedUsageCardPresentation] = [],
        chineseLoginProviderName: String? = nil
    ) -> UsageStore {
        let loginOptions: [ProviderLoginOption]
        if let chineseLoginProviderName,
           let officialApplicationURL = URL(string: "agent-preview://login"),
           let id = AgentConnectorID(rawValue: "kimi.preview") {
            loginOptions = [
                ProviderLoginOption(
                    id: id,
                    providerName: chineseLoginProviderName,
                    officialApplicationURL: officialApplicationURL
                )
            ]
        } else {
            loginOptions = []
        }
        return UsageStore(
            autoRefresh: false,
            previewOnly: true,
            language: language,
            registry: nil,
            primaryConnectorID: nil,
            consentDefaults: nil,
            previewScenario: scenario,
            previewPresentationCards: presentationCards,
            previewLoginOptions: loginOptions
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
        previewPresentationCards: [SharedUsageCardPresentation] = [],
        previewLoginOptions: [ProviderLoginOption] = [],
        visibleRefreshInterval: Duration = .seconds(120),
        backgroundRefreshInterval: Duration = .seconds(900)
    ) {
        _ = visibleRefreshInterval
        _ = backgroundRefreshInterval
        let selectedLanguage = language ?? AppLanguage.resolveAndPersist()
        self.registry = registry
        self.primaryConnectorID = primaryConnectorID
        self.previewOnly = previewOnly
        self.previewDisplaysFixtureData =
            previewOnly && previewScenario.displaysFixtureData
        self.performsLaunchScan = autoRefresh
        self.consentDefaults = consentDefaults
        self.language = selectedLanguage
        self.presentationCards = previewPresentationCards
        self.providerLoginOptions = previewLoginOptions
        self.snapshot = previewOnly && previewScenario.displaysFixtureData
            ? .preview(language: selectedLanguage)
            : .empty(language: selectedLanguage)
        self.connectionState = previewOnly
            ? previewScenario.connectionState
            : .notAuthorizedByMonitor
        self.isRefreshing = previewOnly && previewScenario == .refreshing
        let decision = previewOnly
            ? .granted
            : CodexMonitorConsentDecision.load(from: consentDefaults)
        self.monitorConsentDecision = decision
        self.monitorConsentGranted = decision == .granted
        if !previewOnly, decision == .granted {
            self.connectionState = .idle
        }
        self.freshness = previewOnly ? .fixture : .noRealData
        beginRegistryObservation()
    }

    public var menuPercent: Int? {
        if let primaryID = primaryConnectorID?.rawValue,
           let primaryCard = presentationCards.first(where: {
               $0.id == primaryID
           }) {
            return primaryCard.remaining.displayPercent
        }
        return previewOnly
            ? snapshot.periods.first(where: { !$0.isUnlimited })?.remainingPercent
            : nil
    }

    public var assistantPresentationCards: [SharedUsageCardPresentation] {
        SharedUsagePresentationPolicy.assistantCards(from: presentationCards)
    }

    public var statusText: String {
        if previewOnly, connectionState == .ready {
            return language.demoStatus
        }
        return connectionState.statusText(language: language)
    }

    public var currentState: CodexConnectionState { connectionState }

    public var hasPriorRealSnapshot: Bool {
        guard let primaryConnectorID else {
            return previewDisplaysFixtureData
        }
        return providerSnapshots.contains {
            $0.id == primaryConnectorID
                && $0.state == .ready
                && $0.freshness == .fresh
        } || previewDisplaysFixtureData
    }

    public var allowsManualRefresh: Bool {
        !previewOnly && !isRefreshing
    }

    var admittedProviderIDs: [AgentConnectorID] {
        providerSnapshots.map(\.id)
    }

    public func grantMonitorConsent() {
        guard !previewOnly, monitorConsentDecision != .granted else { return }
        monitorConsentDecision = .granted
        monitorConsentDecision.persist(to: consentDefaults)
        monitorConsentGranted = true
        connectionState = .idle
        freshness = .noRealData
        lastError = nil
        lastFailure = nil
    }

    public func declineMonitorConsent() async {
        await disconnectPrimary(clearConsent: true, decision: .declined)
    }

    public func handleLocalAccessDecision(_ accepted: Bool) {
        guard accepted else {
            monitorConsentGranted = false
            monitorConsentDecision = .declined
            monitorConsentDecision.persist(to: consentDefaults)
            receive([], loginOptions: [])
            Task { @MainActor [weak self] in
                await self?.disconnectPrimary(clearConsent: false)
            }
            return
        }
        let wasGranted = monitorConsentDecision == .granted
        grantMonitorConsent()
        guard !wasGranted else { return }
        Task { @MainActor [weak self] in
            await self?.performEligibilityScan(trigger: .manualRefresh)
        }
    }

    public func requestReconnect() {
        Task { @MainActor [weak self] in
            await self?.performEligibilityScan(trigger: .manualRefresh)
        }
    }

    public func refresh() async {
        await performEligibilityScan(trigger: .manualRefresh)
    }

    /// Non-user triggers are display/lifecycle events and never initiate
    /// eligibility discovery. Accepted connector event streams remain owned by
    /// their connector and flow through the registry independently.
    public func refresh(trigger: CodexRefreshTrigger) async {
        guard trigger == .manual else { return }
        await performEligibilityScan(trigger: .manualRefresh)
    }

    public func connectToLocalSession() async {
        await performEligibilityScan(trigger: .manualRefresh)
    }

    public func checkLocalSessionAgain() async {
        await performEligibilityScan(trigger: .checkAgain)
    }

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
        await performEligibilityScan(trigger: .manualRefresh)
    }

    /// Wake is intentionally not a discovery trigger.
    public func handleApplicationWake() async {}

    public func stopAllConnectors() async {
        guard !previewOnly, let registry else { return }
        activeScanGeneration &+= 1
        activeScanTask?.cancel()
        activeScanTask = nil
        activeScanTrigger = nil
        registrySubscription?.cancel()
        await registry.stopAll()
        receive([], loginOptions: [])
    }

    public func setPanelVisible(_ isVisible: Bool) {
        guard !previewOnly else { return }
        isPanelVisible = isVisible
    }

    public func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        UserDefaults.standard.set(
            newLanguage.rawValue,
            forKey: AppLanguage.storageKey
        )
        rebuildPresentation()
    }

    private func beginRegistryObservation() {
        guard let registry else { return }
        registrySubscription = Task { [weak self] in
            let stream = await registry.snapshots()
            await registry.restorePersistedSnapshots()
            if self?.performsLaunchScan == true {
                await self?.performEligibilityScan(trigger: .applicationLaunch)
            }
            for await snapshots in stream {
                guard !Task.isCancelled else { return }
                guard let admissionSet = await registry.surfaceAdmissionSet(),
                      snapshots == admissionSet.admittedSnapshots
                else { continue }
                self?.receive(
                    snapshots,
                    loginOptions: admissionSet.loginOptions
                )
            }
        }
    }

    private func performEligibilityScan(
        trigger: ProviderEligibilityScanTrigger
    ) async {
        guard !previewOnly, let registry else { return }
        if let activeScanTask {
            let activeTrigger = activeScanTrigger
            await activeScanTask.value
            if activeTrigger == trigger { return }
        }

        let excluded: Set<AgentConnectorID>
        if !monitorConsentGranted, let primaryConnectorID {
            excluded = [primaryConnectorID]
        } else {
            excluded = []
        }
        isRefreshing = true
        activeScanTrigger = trigger
        activeScanGeneration &+= 1
        let generation = activeScanGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await registry.scanSurfaceAdmissions(
                trigger: trigger,
                excludedProviderIDs: excluded
            )
            self.receive(
                result.admittedSnapshots,
                loginOptions: result.loginOptions
            )
        }
        activeScanTask = task
        await task.value
        if activeScanGeneration == generation {
            activeScanTask = nil
            activeScanTrigger = nil
            isRefreshing = false
        }
    }

    private func receive(
        _ snapshots: [AgentUsageSnapshot],
        loginOptions: [ProviderLoginOption]
    ) {
        guard !previewOnly else { return }
        providerSnapshots = snapshots
        providerLoginOptions = loginOptions
        rebuildPresentation()
    }

    private func rebuildPresentation() {
        presentationCards = SharedUsagePresentationPolicy.makeCards(
            snapshots: providerSnapshots,
            previousCards: presentationCards,
            language: language
        )
        guard let primary = primarySnapshot else {
            snapshot = previewDisplaysFixtureData
                ? .preview(language: language)
                : .empty(language: language)
            connectionState = monitorConsentGranted
                ? .idle
                : .notAuthorizedByMonitor
            freshness = previewDisplaysFixtureData ? .fixture : .noRealData
            lastFailure = nil
            lastError = nil
            return
        }
        snapshot = UsageSnapshot(agentSnapshot: primary, language: language)
        connectionState = Self.presentationState(
            primary.state,
            failure: primary.safeFailure
        )
        freshness = Self.presentationFreshness(primary.freshness)
        lastFailure = primary.safeFailure.map(Self.codexFailure)
        lastError = codexFailureDescription(lastFailure)
    }

    private var primarySnapshot: AgentUsageSnapshot? {
        guard let primaryConnectorID else { return nil }
        return providerSnapshots.first(where: {
            $0.id == primaryConnectorID
        })
    }

    private func disconnectPrimary(
        clearConsent: Bool,
        decision: CodexMonitorConsentDecision = .unknown
    ) async {
        guard !previewOnly else { return }
        activeScanGeneration &+= 1
        activeScanTask?.cancel()
        activeScanTask = nil
        activeScanTrigger = nil
        if let registry, let id = primaryConnectorID {
            try? await registry.perform(.disconnect, for: id)
        }
        if clearConsent {
            monitorConsentGranted = false
            monitorConsentDecision = decision
            monitorConsentDecision.persist(to: consentDefaults)
        }
        receive([], loginOptions: [])
    }

    static func cardsByUpdatingPrimaryConnection(
        _ cards: [SharedUsageCardPresentation],
        primaryConnectorID: AgentConnectorID?,
        status: SharedConnectionStatus,
        freshness overrideFreshness: SharedUsageFreshness? = nil
    ) -> [SharedUsageCardPresentation] {
        guard let primaryID = primaryConnectorID?.rawValue else { return cards }
        return cards.map { card in
            guard card.id == primaryID else { return card }
            return SharedUsageCardPresentation(
                id: card.id,
                providerName: card.providerName,
                planLabel: card.planLabel,
                connectionStatus: status,
                freshness: overrideFreshness ?? card.freshness,
                windows: card.windows,
                selectedWindowID: card.selectedWindowID,
                remaining: card.remaining,
                availability: card.availability,
                availabilityLifecycle: card.availabilityLifecycle,
                isVisibleInDesktopAssistant: card.isVisibleInDesktopAssistant,
                severity: card.severity,
                isRetainingLastValidValue: card.isRetainingLastValidValue,
                capturedAt: card.capturedAt
            )
        }
    }

    private static func presentationState(
        _ state: AgentConnectorState,
        failure: AgentSafeFailure?
    ) -> CodexConnectionState {
        switch state {
        case .inactive: .idle
        case .authenticationRequired: .officialCodexSignInRequired
        case .waitingForFirstResponse: .checkingAccount
        case .ready: .ready
        case .stale:
            .staleWithPreviousRealData(codexFailure(failure ?? .unknown))
        case .unsupported: .blockedFailure(.protocolIncompatible)
        case .failed:
            .recoverableFailure(codexFailure(failure ?? .unknown))
        }
    }

    private static func presentationFreshness(
        _ freshness: AgentConnectorFreshness
    ) -> UsageFreshness {
        switch freshness {
        case .fresh: .fresh
        case .stale: .stale
        case .unavailable: .noRealData
        }
    }

    private static func codexFailure(
        _ failure: AgentSafeFailure
    ) -> CodexUsageClientFailure {
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

    private func codexFailureDescription(
        _ failure: CodexUsageClientFailure?
    ) -> String? {
        failure.map {
            CodexUsageClientError($0).description(language: language)
        }
    }

    deinit {
        registrySubscription?.cancel()
        activeScanTask?.cancel()
    }
}
