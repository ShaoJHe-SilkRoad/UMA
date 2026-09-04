import Combine
import Foundation

private struct UsageEligibilityScanOutcome: Sendable {
    let safelyDetectedProviderIDs: [AgentConnectorID]
    let completedAt: Date
}

@MainActor
public final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var providerSnapshots: [AgentUsageSnapshot] = []
    @Published public private(set) var presentationCards: [SharedUsageCardPresentation] = []
    @Published public private(set) var productInventory: ProviderProductInventory
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
    private let previewDisplaysFixtureData: Bool
    private let allowsLaunchScan: Bool
    private let consentDefaults: UserDefaults?
    private let preferences: ApplicationPreferences?
    private var registrySubscription: Task<Void, Never>?
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
    private let backgroundRefreshSleeper: @Sendable (Duration) async throws -> Void

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
        return UsageStore(
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
        }
    ) {
        _ = visibleRefreshInterval
        _ = backgroundRefreshInterval
        self.backgroundRefreshSleeper = backgroundRefreshSleeper
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

    public var menuPercent: Int? {
        if let remaining = productInventory.provider(.codex)?
            .primaryQuota?.value.remainingPercent {
            return Int(remaining.rounded())
        }
        return previewOnly
            ? snapshot.periods.first(where: { !$0.isUnlimited })?.remainingPercent
            : nil
    }

    public var assistantPresentationCards: [SharedUsageCardPresentation] {
        let assistantIDs = Set(productInventory.assistantProviders.map(\.id))
        return presentationCards.filter {
            ProviderProductStatePolicy.productID(
                forRawConnectorID: $0.id
            ).map(assistantIDs.contains) == true
        }
    }

    public var overviewPresentationCards: [SharedUsageCardPresentation] {
        let overviewIDs = Set(productInventory.overviewProviders.map(\.id))
        return presentationCards.filter {
            ProviderProductStatePolicy.productID(
                forRawConnectorID: $0.id
            ).map(overviewIDs.contains) == true
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
            Task { @MainActor [weak self] in
                await self?.disconnectPrimary(clearConsent: false)
            }
            return
        }
        let wasGranted = monitorConsentDecision == .granted
        grantMonitorConsent()
        guard !wasGranted else { return }
        Task { @MainActor [weak self] in
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
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        await registry.suspendAllPreservingState()
    }

    public func resumeMonitoringForWindowPresentation() async {
        guard !previewOnly, monitoringSuspendedForWindowClosure, let registry else { return }
        monitoringSuspendedForWindowClosure = false
        await registry.resumeCurrentAdmissions()
        reconcileBackgroundRefreshPolicy()
    }

    public func stopAllConnectors() async {
        guard !previewOnly, let registry else { return }
        activeScanGeneration &+= 1
        activeScanTask?.cancel()
        activeScanTask = nil
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
            let subscription = await registry.subscribe()
            defer {
                Task { await registry.detach(subscription) }
            }
            self?.registryStreamSubscription = subscription
            await registry.restorePersistedSnapshots()
            if self?.allowsLaunchScan == true,
               self?.agentSettings?.shouldAutoSearchAtLaunch == true {
                _ = await self?.performEligibilityScan(
                    trigger: .applicationLaunch
                )
            }
            for await publication in subscription.updates {
                guard !Task.isCancelled else { return }
                self?.receive(publication)
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
        guard !previewOnly, !backgroundRefreshInFlight, let registry else { return }
        let ids = providerSnapshots.map(\.id).filter {
            agentSettings?.isMonitoringEnabled(for: $0) ?? true
        }
        guard !ids.isEmpty else { return }
        backgroundRefreshInFlight = true
        defer { backgroundRefreshInFlight = false }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    try? await registry.refresh(id, trigger: trigger)
                }
            }
        }
        receive(await registry.latestPublication())
    }

    private func applyMonitoringPreferences() {
        guard agentSettings != nil else { return }
        rebuildPresentation()
    }

    private func performEligibilityScan(
        trigger: ProviderEligibilityScanTrigger
    ) async -> UsageEligibilityScanOutcome? {
        guard !previewOnly, let registry else { return nil }
        if let activeScanTask {
            return await activeScanTask.value
        }

        var excluded: Set<AgentConnectorID>
        if !monitorConsentGranted, let primaryConnectorID {
            excluded = [primaryConnectorID]
        } else {
            excluded = []
        }
        var monitoringDisabledIDs: Set<AgentConnectorID> = []
        if let agentSettings {
            let descriptors = await registry.orderedDescriptors()
            monitoringDisabledIDs = agentSettings.disabledConnectorIDs(
                from: descriptors.map(\.id)
            )
            excluded.formUnion(monitoringDisabledIDs)
        }
        isRefreshing = true
        activeScanGeneration &+= 1
        let generation = activeScanGeneration
        let task = Task<UsageEligibilityScanOutcome?, Never> {
            @MainActor [weak self] in
            guard let self else { return nil }
            let result = await registry.scanSurfaceAdmissions(
                trigger: trigger,
                excludedProviderIDs: excluded
            )
            self.receive(await registry.latestPublication())
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
        guard !previewOnly else { return }
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
        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: providerSnapshots,
            admissions: currentAdmissionRecords,
            monitoringEnabledIDs: Set(monitoringEnabledIDs),
            configuredOrDetectedIDs: configuredOrDetectedIDs,
            pendingInitialAdmissionIDs: pendingInitialAdmissionProviderIDs,
            previousCards: presentationCards,
            language: language,
            publicationRevision: currentRegistryRevision
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
        activeScanGeneration &+= 1
        activeScanTask?.cancel()
        activeScanTask = nil
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
        activeScanTask?.cancel()
    }
}
