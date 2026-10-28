import Combine
import Foundation

private struct UsageEligibilityScanOutcome: Sendable {
    let safelyDetectedProviderIDs: [AgentConnectorID]
    let completedAt: Date
}

@MainActor
public final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    /// Read-only presentation access; source acquisition remains connector-owned.
    public var threadOSAnalytics: ThreadOSUsageAnalytics? { snapshot.threadOSAnalytics }
    @Published private(set) var providerSnapshots: [AgentUsageSnapshot] = []
    @Published public private(set) var presentationCards: [SharedUsageCardPresentation] = []
    @Published public private(set) var productInventory: ProviderProductInventory
    /// The arrangement the user dragged the agent list into, as raw provider
    /// identifiers. Empty until they arrange it.
    @Published public private(set) var agentOrder: [String] = []
    /// The agent the user chose for the menu bar; empty is Automatic.
    @Published public private(set) var menuBarAgent: String = ""
    /// Frozen read-only presentation projection. Reading it does not trigger collection or refresh.
    public var basicUsagePresentation: BasicSharedUsagePresentation {
        .make(snapshot: snapshot, provider: productInventory.provider(.codex))
    }
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

    let agentSettings: AgentSettingsCoordinator?
    private let registry: AgentConnectorRegistry?
    private let primaryConnectorID: AgentConnectorID?
    private let previewOnly: Bool
    private let previewSeedCards: [SharedUsageCardPresentation]
    private let previewDisplaysFixtureData: Bool
    private let allowsLaunchScan: Bool
    private let consentDefaults: UserDefaults?
    private let preferences: ApplicationPreferences?
    private var registrySubscription: Task<Void, Never>?
    private var localAccessDecisionTask: Task<Void, Never>?
    private let initialObservationCompletion = CurrentValueSubject<Bool, Never>(false)
    let coalescedScanRequests = CurrentValueSubject<Int, Never>(0)

    var backgroundRefreshScheduled: Bool { backgroundRefreshTask != nil }

    func waitForInitialObservation() async {
        guard registry != nil else { return }
        for await completed in initialObservationCompletion.values {
            if completed { return }
        }
    }

    func waitForLocalAccessDecision() async {
        await localAccessDecisionTask?.value
    }
    private var registryStreamSubscription: AgentConnectorRegistrySubscription?
    private var agentSettingsSubscription: AnyCancellable?
    private var activeScanTask: Task<UsageEligibilityScanOutcome?, Never>?
    private var activeScanGeneration: UInt64 = 0
    private var currentAdmissionRecords: [ProviderSurfaceAdmissionRecord] = []
    private var currentRegistryRevision: UInt64 = 0
    private var pendingInitialAdmissionProviderIDs: Set<AgentConnectorID> = []
    private var applicationPreferenceObservation: ApplicationPreferences.Observation?
    private var backgroundRefreshTask: Task<Void, Never>?
    private var backgroundRefreshInFlight = false
    private var monitoringSuspendedForWindowClosure = false
    private var monitoringStopped = false
    private var monitoringGeneration: UInt64 = 0
    private let backgroundRefreshSleeper: @Sendable (Duration) async throws -> Void
    private let prepareEligibilityScan: @MainActor @Sendable () async -> Void

    public convenience init(autoRefresh: Bool = true, language: AppLanguage? = nil) {
        self.init(
            autoRefresh: autoRefresh,
            previewOnly: false,
            language: language,
            registry: AgentUsageRuntime.makeCodexRegistry(),
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: .standard,
            preferences: .production
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
            consentDefaults: previewOnly ? nil : .standard,
            preferences: previewOnly ? nil : .production
        )
    }

    public static func preview(
        scenario: CodexPreviewScenario = .ready,
        language: AppLanguage = .simplifiedChinese,
        presentationCards: [SharedUsageCardPresentation] = [],
        accountDailyUsage: [AgentAccountUsageDay] = [],
        previewCapturedAt: Date? = nil,
        chineseLoginProviderName: String? = nil,
        includesAgentSettings: Bool = false
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
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: true,
            language: language,
            registry: nil,
            primaryConnectorID: nil,
            consentDefaults: nil,
            agentSettings: includesAgentSettings
                ? AgentSettingsCoordinator(
                    store: AgentPreferenceStore(
                        defaults: UserDefaults(
                            suiteName:
                                "com.silkrd.uma.PreviewRenderer.AgentSettings.\(UUID().uuidString)"
                        )!
                    )
                )
                : nil,
            previewScenario: scenario,
            previewPresentationCards: presentationCards,
            previewLoginOptions: loginOptions
        )
        // Test/preview-only fixture data stays inside the existing preview
        // renderer path. Production snapshots are populated by connectors.
        if !accountDailyUsage.isEmpty {
            store.snapshot.accountDailyUsage = accountDailyUsage
        }
        if let previewCapturedAt, scenario.displaysFixtureData {
            store.snapshot.updatedAt = previewCapturedAt
            store.snapshot.providerSource = UsageSourceStatus(
                label: "Preview fixture", scope: "preview only",
                capturedAt: previewCapturedAt, isAvailable: true
            )
            store.snapshot.localSource = UsageSourceStatus(
                label: "Preview fixture", scope: "preview only",
                capturedAt: previewCapturedAt, isAvailable: true, coverage: 100
            )
        }
        return store
    }

    /// Test presentation input only. Ordinary preview and production callers
    /// retain their existing snapshot construction and connector ownership.
    func configureMatchedPreviewSnapshot(_ input: UsageSnapshot) {
        guard previewOnly else { return }
        snapshot = input
    }

    /// Isolated preview-only source-state fixture; production stores cannot
    /// receive a synthetic history channel through this method.
    func configurePreviewHistorySource(
        freshness: UsageSourceStatus.Freshness,
        includeAggregate: Bool
    ) {
        guard previewOnly else { return }
        snapshot.localSource = UsageSourceStatus(
            label: "Preview fixture", scope: "preview only",
            capturedAt: snapshot.updatedAt, isAvailable: freshness != .unavailable,
            coverage: includeAggregate ? 100 : nil, freshness: freshness
        )
        if !includeAggregate { snapshot.apiCostEstimate = nil }
    }

    /// Isolated preview-only activity-channel fixture. No production store can
    /// receive synthetic local tasks or freshness through this method.
    func configurePreviewActivitySource(
        freshness: UsageSourceStatus.Freshness,
        isAvailable: Bool,
        includeTasks: Bool,
        firstTaskTitle: String? = nil
    ) {
        guard previewOnly else { return }
        snapshot.localSource = UsageSourceStatus(
            label: "Preview local activity", scope: "preview only",
            capturedAt: snapshot.updatedAt, isAvailable: isAvailable,
            coverage: nil, freshness: freshness
        )
        if !includeTasks { snapshot.recentTasks = [] }
        if let firstTaskTitle, includeTasks, !snapshot.recentTasks.isEmpty {
            let original = snapshot.recentTasks[0]
            snapshot.recentTasks[0] = RecentTask(
                id: original.id, title: firstTaskTitle, time: original.time,
                tokenText: original.tokenText, progress: original.progress
            )
        }
    }

    init(
        autoRefresh: Bool = true,
        previewOnly: Bool = false,
        language: AppLanguage? = nil,
        registry: AgentConnectorRegistry?,
        primaryConnectorID: AgentConnectorID?,
        consentDefaults: UserDefaults? = nil,
        preferences: ApplicationPreferences? = nil,
        agentSettings: AgentSettingsCoordinator? = nil,
        previewScenario: CodexPreviewScenario = .ready,
        previewPresentationCards: [SharedUsageCardPresentation] = [],
        previewLoginOptions: [ProviderLoginOption] = [],
        visibleRefreshInterval: Duration = .seconds(120),
        backgroundRefreshInterval: Duration = .seconds(900),
        backgroundRefreshSleeper: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        prepareEligibilityScan: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        _ = visibleRefreshInterval
        _ = backgroundRefreshInterval
        self.backgroundRefreshSleeper = backgroundRefreshSleeper
        self.prepareEligibilityScan = prepareEligibilityScan
        // Internal/test construction with nil persistence remains ephemeral;
        // it must never silently escape into the production standard domain.
        let effectivePreferences = preferences
            ?? consentDefaults.map(ApplicationPreferences.init(userDefaults:))
            ?? (previewOnly ? nil : ApplicationPreferences.inMemory())
        let selectedLanguage = language
            ?? effectivePreferences.map {
                AppLanguage.resolveAndPersist(preferences: $0)
            }
            ?? AppLanguage.systemMatch()
        self.registry = registry
        self.primaryConnectorID = primaryConnectorID
        self.previewOnly = previewOnly
        self.previewDisplaysFixtureData =
            previewOnly && previewScenario.displaysFixtureData
        self.allowsLaunchScan = autoRefresh
        self.consentDefaults = consentDefaults
        self.preferences = effectivePreferences
        self.agentOrder = effectivePreferences?
            .value(for: UMAApplicationPreferenceKeys.agentOrder) ?? []
        self.menuBarAgent = effectivePreferences?
            .value(for: UMAApplicationPreferenceKeys.menuBarAgent) ?? ""
        self.agentSettings = previewOnly
            ? agentSettings
            : (
                agentSettings
                    ?? AgentSettingsCoordinator(
                        store: AgentPreferenceStore(
                            preferences: effectivePreferences
                                ?? ApplicationPreferences.inMemory()
                        )
                    )
            )
        self.language = selectedLanguage
        self.previewSeedCards = previewPresentationCards
        self.presentationCards = previewPresentationCards
        self.productInventory = ProviderProductStatePolicy.previewInventory(
            cards: previewPresentationCards,
            language: selectedLanguage
        )
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
            if autoRefresh,
               registry != nil,
               let primaryConnectorID,
               self.agentSettings?.isMonitoringEnabled(for: primaryConnectorID) ?? true {
                pendingInitialAdmissionProviderIDs.insert(primaryConnectorID)
            }
        }
        self.freshness = previewOnly ? .fixture : .noRealData
        if !(previewOnly && !previewPresentationCards.isEmpty) {
            rebuildPresentation()
        }
        beginAgentSettingsObservation()
        beginRegistryObservation()
        beginApplicationPreferenceObservation()
        reconcileBackgroundRefreshPolicy()
    }

    /// A normalized snapshot for one provider. `snapshot` is the primary
    /// provider's only, so an agent workspace that is not the primary had no
    /// way to read its own local metrics.
    func snapshot(for productID: ProviderProductID) -> UsageSnapshot? {
        guard let connectorID = ProviderProductStatePolicy.connectorID(for: productID),
              let agentSnapshot = providerSnapshots.first(where: { $0.id == connectorID })
        else { return nil }
        return UsageSnapshot(agentSnapshot: agentSnapshot, language: language)
    }

    /// The agent list in the order the user arranged it. Both the main
    /// workspace rail and the quick panel read these, so the two lists and the
    /// menu bar can never disagree about which agent is on top.
    public var orderedWorkspaceProviders: [ProviderProductState] {
        AgentDisplayOrder.apply(
            productInventory.agentWorkspaceProviders,
            order: agentOrder,
            id: { $0.id.rawValue }
        )
    }

    public var orderedQuickPanelProviders: [ProviderProductState] {
        AgentDisplayOrder.apply(
            productInventory.quickPanelProviders,
            order: agentOrder,
            id: { $0.id.rawValue }
        )
    }

    /// Records the agent list as the user just rearranged it, and keeps it
    /// until they rearrange it again. The whole visible order is written, not
    /// the one row that moved, so what they see is what is stored.
    public func moveAgent(_ moved: ProviderProductID, onto target: ProviderProductID) {
        let displayed = orderedWorkspaceProviders.map(\.id.rawValue)
        guard let updated = AgentDisplayOrder.moving(
            moved.rawValue,
            onto: target.rawValue,
            in: displayed
        ) else { return }
        agentOrder = updated
        preferences?.set(updated, for: UMAApplicationPreferenceKeys.agentOrder)
    }

    /// Moves an agent one or more places up (negative) or down (positive),
    /// for the Settings buttons that do what a drag does.
    public func moveAgent(_ moved: ProviderProductID, by offset: Int) {
        let displayed = orderedWorkspaceProviders.map(\.id.rawValue)
        guard let from = displayed.firstIndex(of: moved.rawValue) else { return }
        let to = min(max(0, from + offset), displayed.count - 1)
        guard to != from else { return }
        moveAgent(moved, onto: orderedWorkspaceProviders[to].id)
    }

    /// Forgets the arrangement, so every list goes back to the built-in order
    /// and the menu bar to its Codex-first default.
    public func resetAgentOrder() {
        agentOrder = []
        preferences?.set([], for: UMAApplicationPreferenceKeys.agentOrder)
    }

    /// Pins the menu bar to one agent, or returns it to Automatic with nil.
    public func setMenuBarAgent(_ provider: ProviderProductID?) {
        let value = provider?.rawValue ?? ""
        menuBarAgent = value
        preferences?.set(value, for: UMAApplicationPreferenceKeys.menuBarAgent)
    }

    /// The agents the menu bar can be pinned to, in the user's order: every
    /// agent the main window lists, including one with no reading right now.
    public var menuBarCandidates: [ProviderProductState] { orderedWorkspaceProviders }

    /// Which provider the menu bar reading belongs to.
    ///
    /// Until the list has been arranged, Codex keeps priority and any other
    /// quick-panel-eligible provider is used only when Codex reports no usable
    /// quota, which is exactly what existing installs already see. Once the
    /// list has been arranged, the arrangement decides: the reading belongs to
    /// the topmost agent that has one, so an agent pinned to the top with
    /// nothing to report hands the menu bar down the list rather than blanking
    /// it.
    public var menuProvider: ProviderProductID? {
        Self.menuProvider(inventory: productInventory, order: agentOrder, pinned: menuBarAgent)
    }

    public var menuPercent: Int? {
        Self.menuPercent(inventory: productInventory, order: agentOrder, pinned: menuBarAgent)
            ?? previewMenuPercent
    }

    /// What the menu bar shows: whose reading it is, and how much remains.
    public struct MenuReading: Equatable, Sendable {
        public let provider: ProviderProductID?
        public let percent: Int?
        public let language: AppLanguage
    }

    /// The menu bar reading, recomputed whenever the inventory, the user's
    /// arrangement or the language is published, and only delivered when it
    /// changes.
    ///
    /// It is computed from the values each publisher delivers, not by reading
    /// the store back: `@Published` emits before the property is assigned, so
    /// a reading taken from the store at that moment is the previous one. The
    /// arrangement is part of it, so a rearranged list moves the menu bar at
    /// once rather than when the next usage update happens to arrive.
    public var menuReadingPublisher: AnyPublisher<MenuReading, Never> {
        let previewPercent = previewMenuPercent
        return Publishers.CombineLatest4($productInventory, $agentOrder, $menuBarAgent, $language)
            .map { inventory, order, pinned, language in
                let provider = Self.menuProvider(inventory: inventory, order: order, pinned: pinned)
                return MenuReading(
                    provider: provider,
                    percent: Self.menuPercent(inventory: inventory, order: order, pinned: pinned)
                        ?? previewPercent,
                    language: language
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// A pinned agent keeps the menu bar even while it has no reading, which
    /// then shows a dash: handing it to another agent would put that agent's
    /// number where the user asked for this one's. A pin to an agent that is
    /// no longer available falls back to Automatic.
    private static func menuProvider(
        inventory: ProviderProductInventory,
        order: [String],
        pinned: String = ""
    ) -> ProviderProductID? {
        if let pinnedID = ProviderProductID(rawValue: pinned),
           inventory.agentWorkspaceProviders.contains(where: { $0.id == pinnedID }) {
            return pinnedID
        }
        return AgentDisplayOrder.menuReading(
            amongEligible: AgentDisplayOrder.apply(
                inventory.quickPanelProviders,
                order: order,
                id: { $0.id.rawValue }
            )
                .filter { $0.primaryQuota?.value.remainingPercent != nil }
                .map(\.id),
            isArranged: !order.isEmpty,
            preferred: .codex
        )
    }

    private static func menuPercent(
        inventory: ProviderProductInventory,
        order: [String],
        pinned: String = ""
    ) -> Int? {
        guard let provider = menuProvider(inventory: inventory, order: order, pinned: pinned),
              let remaining = inventory.provider(provider)?
                .primaryQuota?.value.remainingPercent
        else { return nil }
        return Int(remaining.rounded())
    }

    private var previewMenuPercent: Int? {
        previewOnly
            ? snapshot.periods.first(where: { !$0.isUnlimited })?.remainingPercent
            : nil
    }

    /// The Desktop Assistant's cards, in the order the user arranged the
    /// agents, so it stacks them the way every other list does.
    public var assistantPresentationCards: [SharedUsageCardPresentation] {
        assistantPresentationCards(arrangedBy: agentOrder)
    }

    /// The same cards arranged by `order`. An observer of `$agentOrder` passes
    /// the order it was delivered, because the store still holds the previous
    /// one while it publishes.
    public func assistantPresentationCards(
        arrangedBy order: [String]
    ) -> [SharedUsageCardPresentation] {
        Self.assistantCards(presentationCards, inventory: productInventory, order: order)
    }

    /// The Desktop Assistant's cards, built from the values each publication
    /// delivers. Read back from the store inside a sink, the inventory is the
    /// previous one, because a @Published sink runs before the property is
    /// set; an agent that had just become eligible, as Claude does after an
    /// Accuracy Sync, was left off until some later publication.
    public var assistantCardsPublisher: AnyPublisher<[SharedUsageCardPresentation], Never> {
        Publishers.CombineLatest3($presentationCards, $productInventory, $agentOrder)
            .map { cards, inventory, order in
                Self.assistantCards(cards, inventory: inventory, order: order)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private static func assistantCards(
        _ cards: [SharedUsageCardPresentation],
        inventory: ProviderProductInventory,
        order: [String]
    ) -> [SharedUsageCardPresentation] {
        // The plan travels with the provider state: Claude's comes from its
        // settings, not its readings, and without it the bar cannot be coloured.
        let plans = Dictionary(
            inventory.assistantProviders.map { ($0.id, $0.planLabel) },
            uniquingKeysWith: { first, _ in first }
        )
        return arranged(
            cards.compactMap { card in
                guard let productID = ProviderProductStatePolicy.productID(
                    forRawConnectorID: card.id
                ), let plan = plans[productID] else { return nil }
                return card.fillingPlanLabel(plan)
            },
            by: order
        )
    }

    public var overviewPresentationCards: [SharedUsageCardPresentation] {
        let overviewIDs = Set(productInventory.overviewProviders.map(\.id))
        return Self.arranged(
            presentationCards.filter {
                ProviderProductStatePolicy.productID(
                    forRawConnectorID: $0.id
                ).map(overviewIDs.contains) == true
            },
            by: agentOrder
        )
    }

    /// Cards carry connector identifiers; the arrangement holds product ones.
    private static func arranged(
        _ cards: [SharedUsageCardPresentation],
        by order: [String]
    ) -> [SharedUsageCardPresentation] {
        AgentDisplayOrder.apply(cards, order: order) { card in
            ProviderProductStatePolicy.productID(forRawConnectorID: card.id)?.rawValue
                ?? card.id
        }
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
            localAccessDecisionTask = Task { @MainActor [weak self] in
                await self?.disconnectPrimary(clearConsent: false)
            }
            return
        }
        let wasGranted = monitorConsentDecision == .granted
        grantMonitorConsent()
        guard !wasGranted else { return }
        localAccessDecisionTask = Task { @MainActor [weak self] in
            _ = await self?.performEligibilityScan(trigger: .manualRefresh)
        }
    }

    public func requestReconnect() {
        Task { @MainActor [weak self] in
            _ = await self?.performEligibilityScan(trigger: .manualRefresh)
        }
    }

    public func refresh() async {
        _ = await performEligibilityScan(trigger: .manualRefresh)
    }

    /// The only action that completes first-run Agent Search onboarding.
    /// Auto Search never bypasses this deliberate first manual scan.
    public func searchForAgents() async {
        guard let outcome = await performEligibilityScan(
            trigger: .manualSearch
        ) else {
            return
        }
        agentSettings?.completeFirstManualScan(
            detectedConnectorIDs: outcome.safelyDetectedProviderIDs,
            detectedAt: outcome.completedAt
        )
    }

    /// Non-user triggers are display/lifecycle events and never initiate
    /// eligibility discovery. Accepted connector event streams remain owned by
    /// their connector and flow through the registry independently.
    public func refresh(trigger: CodexRefreshTrigger) async {
        guard trigger == .manual else { return }
        _ = await performEligibilityScan(trigger: .manualRefresh)
    }

    public func connectToLocalSession() async {
        _ = await performEligibilityScan(trigger: .manualRefresh)
    }

    public func checkLocalSessionAgain() async {
        _ = await performEligibilityScan(trigger: .checkAgain)
    }

    public func syncWorkBuddyAccountNow() async {
        _ = await performEligibilityScan(trigger: .syncNow)
    }

    public func disconnectWorkBuddyAccount() async {
        guard !previewOnly, let registry else { return }
        try? await registry.perform(
            .disconnect,
            for: WorkBuddyAccountWebCreditsConnector.connectorID
        )
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
        _ = await performEligibilityScan(trigger: .manualRefresh)
    }

    /// Wake is never a discovery trigger. When explicitly enabled it refreshes
    /// only the providers already owned by the current admission publication.
    public func handleApplicationWake() async {
        guard preferences?.value(for: UMAApplicationPreferenceKeys.refreshOnWake) == true,
              !monitoringSuspendedForWindowClosure else { return }
        await refreshAdmittedProviders(trigger: .wake)
    }

    public func suspendMonitoringForWindowClosure() async {
        guard !previewOnly,
              preferences?.value(
                for: UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose
              ) == false,
              !monitoringSuspendedForWindowClosure,
              let registry else { return }
        monitoringSuspendedForWindowClosure = true
        invalidatePendingMonitoring()
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        await registry.suspendAllPreservingState()
    }

    public func resumeMonitoringForWindowPresentation() async {
        guard !previewOnly, !monitoringStopped, monitoringSuspendedForWindowClosure, let registry else { return }
        monitoringSuspendedForWindowClosure = false
        monitoringGeneration &+= 1
        await registry.resumeCurrentAdmissions()
        reconcileBackgroundRefreshPolicy()
    }

    public func stopAllConnectors() async {
        guard !previewOnly, let registry else { return }
        monitoringStopped = true
        invalidatePendingMonitoring()
        localAccessDecisionTask?.cancel()
        initialObservationCompletion.send(completion: .finished)
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        registrySubscription?.cancel()
        if let registryStreamSubscription {
            await registry.detach(registryStreamSubscription)
            self.registryStreamSubscription = nil
        }
        await registry.stopAll()
        receive([], loginOptions: [])
    }

    private func invalidatePendingMonitoring() {
        monitoringGeneration &+= 1
        activeScanGeneration &+= 1
        activeScanTask?.cancel()
        activeScanTask = nil
        isRefreshing = false
        backgroundRefreshInFlight = false
    }

    public func setPanelVisible(_ isVisible: Bool) {
        guard !previewOnly else { return }
        isPanelVisible = isVisible
    }

    public func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        preferences?.set(
            newLanguage.rawValue,
            for: UMAApplicationPreferenceKeys.language
        )
        rebuildPresentation()
    }

    private func beginRegistryObservation() {
        guard let registry else { return }
        registrySubscription = Task { [weak self] in
            guard !Task.isCancelled, self?.monitoringStopped == false else { return }
            let subscription = await registry.subscribe()
            defer {
                Task { await registry.detach(subscription) }
            }
            guard !Task.isCancelled, self?.monitoringStopped == false else { return }
            self?.registryStreamSubscription = subscription
            await registry.restorePersistedSnapshots()
            guard !Task.isCancelled, self?.monitoringStopped == false else { return }
            if self?.allowsLaunchScan == true,
               self?.agentSettings?.shouldAutoSearchAtLaunch == true {
                _ = await self?.performEligibilityScan(
                    trigger: .applicationLaunch
                )
            }
            for await publication in subscription.updates {
                guard !Task.isCancelled else { return }
                self?.receive(publication)
                if self?.initialObservationCompletion.value == false {
                    self?.initialObservationCompletion.send(true)
                }
            }
            self?.registryStreamSubscription = nil
        }
    }

    private func beginAgentSettingsObservation() {
        agentSettingsSubscription = agentSettings?.$envelope
            .dropFirst()
            .sink { @MainActor [weak self] _ in
                self?.applyMonitoringPreferences()
            }
    }

    private func beginApplicationPreferenceObservation() {
        applicationPreferenceObservation = preferences?.observe { [weak self] change in
            // The declared plan only changes how an existing reading is graded,
            // so rebuild presentation rather than waiting for the next refresh.
            if change.key == UMAApplicationPreferenceKeys.claudeDeclaredPlan.name {
                self?.rebuildPresentation()
                return
            }
            // The arrangement is process-global state; adopt an external write
            // rather than keeping a stale copy of it.
            if change.key == UMAApplicationPreferenceKeys.agentOrder.name {
                self?.agentOrder = self?.preferences?
                    .value(for: UMAApplicationPreferenceKeys.agentOrder) ?? []
                return
            }
            if change.key == UMAApplicationPreferenceKeys.menuBarAgent.name {
                self?.menuBarAgent = self?.preferences?
                    .value(for: UMAApplicationPreferenceKeys.menuBarAgent) ?? ""
                return
            }
            guard change.key == UMAApplicationPreferenceKeys.automaticBackgroundRefresh.name
                    || change.key == UMAApplicationPreferenceKeys.backgroundRefreshInterval.name
                    || change.key == UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose.name
            else { return }
            self?.reconcileBackgroundRefreshPolicy()
        }
    }

    private func reconcileBackgroundRefreshPolicy() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        guard !previewOnly,
              !monitoringStopped,
              !monitoringSuspendedForWindowClosure,
              preferences?.value(
                for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh
              ) == true else { return }
        let rawInterval = preferences?.value(
            for: UMAApplicationPreferenceKeys.backgroundRefreshInterval
        )
        let interval = rawInterval.flatMap(UMABackgroundRefreshInterval.init(rawValue:))
            ?? .fifteenMinutes
        let sleeper = backgroundRefreshSleeper
        backgroundRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleeper(interval.duration)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.refreshAdmittedProviders(trigger: .timer)
            }
        }
    }

    private func refreshAdmittedProviders(trigger: CodexRefreshTrigger) async {
        guard !previewOnly, !monitoringStopped, !monitoringSuspendedForWindowClosure,
              !backgroundRefreshInFlight, let registry else { return }
        let generation = monitoringGeneration
        let ids = providerSnapshots.map(\.id).filter {
            agentSettings?.isMonitoringEnabled(for: $0) ?? true
        }
        guard !ids.isEmpty else { return }
        backgroundRefreshInFlight = true
        defer {
            if generation == monitoringGeneration { backgroundRefreshInFlight = false }
        }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try? await registry.refresh(id, trigger: trigger)
                }
            }
        }
        let publication = await registry.latestPublication()
        guard generation == monitoringGeneration, !Task.isCancelled else { return }
        receive(publication)
    }

    private func applyMonitoringPreferences() {
        guard let agentSettings else { return }
        if previewOnly && !previewSeedCards.isEmpty {
            // A preview has no connector publication to rebuild from. Keep its
            // seeded data intact across a real settings-sheet off/on cycle.
            let visible = previewSeedCards.filter { card in
                guard let id = AgentConnectorID(rawValue: card.id) else { return false }
                return agentSettings.isMonitoringEnabled(for: id)
            }
            presentationCards = visible
            productInventory = ProviderProductStatePolicy.previewInventory(
                cards: visible, language: language)
            return
        }
        rebuildPresentation()
    }

    private func performEligibilityScan(
        trigger: ProviderEligibilityScanTrigger
    ) async -> UsageEligibilityScanOutcome? {
        guard !previewOnly, !monitoringStopped, !monitoringSuspendedForWindowClosure,
              !Task.isCancelled, let registry else { return nil }
        if let activeScanTask {
            coalescedScanRequests.send(coalescedScanRequests.value + 1)
            return await activeScanTask.value
        }

        // Install ownership before the first actor suspension. Concurrent
        // actions must join this generation even while descriptors are loading.
        isRefreshing = true
        activeScanGeneration &+= 1
        let generation = activeScanGeneration
        let task = Task<UsageEligibilityScanOutcome?, Never> {
            @MainActor [weak self] in
            guard let self else { return nil }
            await self.prepareEligibilityScan()
            guard self.acceptsScanCompletion(generation) else { return nil }
            var excluded: Set<AgentConnectorID> = []
            if !self.monitorConsentGranted, let primaryConnectorID = self.primaryConnectorID {
                excluded.insert(primaryConnectorID)
            }
            var monitoringDisabledIDs: Set<AgentConnectorID> = []
            if let agentSettings = self.agentSettings {
                let descriptors = await registry.orderedDescriptors()
                guard self.acceptsScanCompletion(generation) else { return nil }
                monitoringDisabledIDs = agentSettings.disabledConnectorIDs(
                    from: descriptors.map(\.id)
                )
                excluded.formUnion(monitoringDisabledIDs)
            }
            let result = await registry.scanSurfaceAdmissions(
                trigger: trigger,
                excludedProviderIDs: excluded
            )
            guard self.acceptsScanCompletion(generation) else { return nil }
            let publication = await registry.latestPublication()
            guard self.acceptsScanCompletion(generation) else { return nil }
            self.receive(publication)
            let outcome = UsageEligibilityScanOutcome(
                safelyDetectedProviderIDs:
                    result.safelyDetectedProviderIDs.filter {
                        !monitoringDisabledIDs.contains($0)
                    },
                completedAt: Date()
            )
            if trigger != .manualSearch {
                self.agentSettings?.recordSafeDetections(
                    outcome.safelyDetectedProviderIDs,
                    detectedAt: outcome.completedAt
                )
            }
            return outcome
        }
        activeScanTask = task
        let result = await task.value
        if activeScanGeneration == generation {
            activeScanTask = nil
            isRefreshing = false
        }
        return result
    }

    private func acceptsScanCompletion(_ generation: UInt64) -> Bool {
        !Task.isCancelled && !monitoringStopped && !monitoringSuspendedForWindowClosure
            && activeScanGeneration == generation
    }

    private func receive(
        _ snapshots: [AgentUsageSnapshot],
        loginOptions: [ProviderLoginOption],
        setupRequiredProviderIDs: [AgentConnectorID] = []
    ) {
        guard !previewOnly else { return }
        providerSnapshots = snapshots
        currentAdmissionRecords = []
        pendingInitialAdmissionProviderIDs.removeAll()
        providerLoginOptions = loginOptions.filter {
            agentSettings?.isMonitoringEnabled(for: $0.id) ?? true
        }
        _ = setupRequiredProviderIDs
        rebuildPresentation()
    }

    private func receive(_ publication: AgentConnectorRegistryPublication) {
        guard !previewOnly, !monitoringStopped, !monitoringSuspendedForWindowClosure else { return }
        guard publication.revision >= currentRegistryRevision else { return }
        if publication.revision == currentRegistryRevision,
           publication.snapshots == providerSnapshots,
           publication.admissionSet?.records == currentAdmissionRecords {
            return
        }
        currentRegistryRevision = publication.revision
        // Restored connector snapshots are internal recovery evidence until a
        // completed admission scan establishes the matching surface contract.
        providerSnapshots = publication.admissionSet == nil
            ? []
            : publication.snapshots
        currentAdmissionRecords = publication.admissionSet?.records ?? []
        if publication.admissionSet != nil {
            pendingInitialAdmissionProviderIDs.removeAll()
        }
        providerLoginOptions = (publication.admissionSet?.loginOptions ?? []).filter {
            agentSettings?.isMonitoringEnabled(for: $0.id) ?? true
        }
        rebuildPresentation()
    }

    private func rebuildPresentation() {
        let monitoringEnabledIDs = ProviderProductStatePolicy.catalogConnectorIDs.filter {
            agentSettings?.isMonitoringEnabled(for: $0) ?? true
        }
        let configuredOrDetectedIDs = Set(
            (agentSettings?.entries ?? []).compactMap {
                $0.hasBeenDetected || $0.hasNonDefaultSettings
                    ? $0.providerID
                    : nil
            }
        )
        let declaredClaudePlan = preferences?
            .value(for: UMAApplicationPreferenceKeys.claudeDeclaredPlan) ?? ""
        let declaredPlans: [ProviderProductID: String] = declaredClaudePlan.isEmpty
            ? [:] : [.claude: declaredClaudePlan]
        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: providerSnapshots,
            admissions: currentAdmissionRecords,
            monitoringEnabledIDs: Set(monitoringEnabledIDs),
            configuredOrDetectedIDs: configuredOrDetectedIDs,
            pendingInitialAdmissionIDs: pendingInitialAdmissionProviderIDs,
            previousCards: presentationCards,
            language: language,
            publicationRevision: currentRegistryRevision,
            declaredPlans: declaredPlans
        )
        presentationCards = reduction.presentationCards
        productInventory = reduction.inventory
        let activeIDs = productInventory.providers.compactMap {
            $0.isActive ? ProviderProductStatePolicy.connectorID(for: $0.id) : nil
        }
        let setupRequiredIDs = productInventory.providers.compactMap {
            $0.requiredAction == .authenticate
                ? ProviderProductStatePolicy.connectorID(for: $0.id)
                : nil
        }
        agentSettings?.setProviderRuntimeState(
            activeConnectorIDs: activeIDs,
            setupRequiredConnectorIDs: setupRequiredIDs
        )
        guard let primary = primarySnapshot else {
            snapshot = previewDisplaysFixtureData
                ? .preview(language: language)
                : .empty(language: language)
            connectionState = monitorConsentGranted
                ? .idle
                : .notAuthorizedByMonitor
            freshness = previewDisplaysFixtureData ? .fixture : .noRealData
            // Admission deliberately hides invalid quota values, but must not
            // erase the reason a first connection failed.
            lastFailure = currentAdmissionRecords.first(where: { $0.id == primaryConnectorID })?
                .safeFailure.map(Self.codexFailure)
            lastError = codexFailureDescription(lastFailure)
            if let lastFailure {
                connectionState = lastFailure.blocksConnection
                    ? .blockedFailure(lastFailure) : .recoverableFailure(lastFailure)
            }
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
        guard agentSettings?.isMonitoringEnabled(for: primaryConnectorID) ?? true else {
            return nil
        }
        return providerSnapshots.first(where: {
            $0.id == primaryConnectorID
        })
    }

    private func disconnectPrimary(
        clearConsent: Bool,
        decision: CodexMonitorConsentDecision = .unknown
    ) async {
        guard !previewOnly else { return }
        invalidatePendingMonitoring()
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
        case .cached, .stale: .stale
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
        localAccessDecisionTask?.cancel()
        activeScanTask?.cancel()
    }
}
