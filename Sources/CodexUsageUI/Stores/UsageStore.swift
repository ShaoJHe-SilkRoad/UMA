import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastFailure: CodexUsageClientFailure?
    @Published public private(set) var language: AppLanguage
    @Published private(set) var connectionState: CodexConnectionState
    @Published private(set) var monitorConsentGranted = false
    @Published public private(set) var monitorConsentDecision: CodexMonitorConsentDecision
    @Published public private(set) var freshness: UsageFreshness
    @Published public private(set) var isPanelVisible = false

    private let client: any CodexUsageClient
    private let localActivityReader: any CodexLocalActivityReading
    private let previewOnly: Bool
    private let previewDisplaysFixtureData: Bool
    private let consentDefaults: UserDefaults?
    private let periodicRefreshInterval: Duration
    private var lastLiveUsage: CodexLiveUsage?
    private var lastLocalActivity: CodexLocalActivitySnapshot?
    private var lastRefreshError: CodexUsageClientError?
    private var stateEpoch = 0
    private var activeOperationEpoch: Int?
    private var connectionProgressTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?

    public convenience init(
        autoRefresh: Bool = true,
        language: AppLanguage? = nil
    ) {
        self.init(
            autoRefresh: autoRefresh,
            previewOnly: false,
            language: language,
            client: CodexAppServerClient(),
            localActivityReader: CodexLocalActivityReader(),
            consentDefaults: .standard,
            periodicRefreshInterval: .seconds(240),
            localSessionReconciliationInterval: .seconds(5),
            localSessionReconciliationTimeout: .seconds(300)
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
            client: CodexAppServerClient(),
            localActivityReader: CodexLocalActivityReader(),
            consentDefaults: previewOnly ? nil : .standard,
            periodicRefreshInterval: .seconds(240),
            localSessionReconciliationInterval: .seconds(5),
            localSessionReconciliationTimeout: .seconds(300)
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
            client: CodexAppServerClient(),
            localActivityReader: CodexLocalActivityReader(),
            consentDefaults: nil,
            previewScenario: scenario,
            periodicRefreshInterval: .seconds(60),
            localSessionReconciliationInterval: .seconds(5),
            localSessionReconciliationTimeout: .seconds(300)
        )
    }

    init(
        autoRefresh: Bool = true,
        previewOnly: Bool = false,
        language: AppLanguage? = nil,
        client: any CodexUsageClient,
        localActivityReader: any CodexLocalActivityReading = CodexLocalActivityReader(),
        consentDefaults: UserDefaults? = nil,
        previewScenario: CodexPreviewScenario = .ready,
        periodicRefreshInterval: Duration = .seconds(240),
        localSessionReconciliationInterval: Duration = .seconds(5),
        localSessionReconciliationTimeout: Duration = .seconds(300)
    ) {
        let selectedLanguage = language ?? AppLanguage.resolveAndPersist()
        self.client = client
        self.localActivityReader = localActivityReader
        self.previewOnly = previewOnly
        self.previewDisplaysFixtureData = previewOnly && previewScenario.displaysFixtureData
        self.consentDefaults = consentDefaults
        self.periodicRefreshInterval = periodicRefreshInterval
        _ = localSessionReconciliationInterval
        _ = localSessionReconciliationTimeout
        self.language = selectedLanguage
        self.snapshot = previewOnly && previewScenario.displaysFixtureData
            ? .preview(language: selectedLanguage)
            : .empty(language: selectedLanguage)
        self.connectionState = previewOnly ? previewScenario.connectionState : .notAuthorizedByMonitor
        self.isRefreshing = previewOnly && previewScenario == .refreshing
        let decision = previewOnly ? .granted : CodexMonitorConsentDecision.load(from: consentDefaults)
        self.monitorConsentDecision = decision
        self.monitorConsentGranted = decision == .granted
        if !previewOnly, decision == .granted {
            self.connectionState = .idle
        }
        self.freshness = previewOnly ? .fixture : .noRealData
        self.lastFailure = nil

        // `autoRefresh` remains part of the preview/test API for compatibility,
        // but production starts with in-memory consent denied.  It cannot cause
        // any app-server or account request before a future consent UI opts in.
        _ = autoRefresh
    }

    /// `nil` means that no real quota window has been read.  It is distinct
    /// from a real 0% remaining value and prevents the menu bar from claiming
    /// an invented empty quota during first load or a first-load failure.
    public var menuPercent: Int? {
        snapshot.periods.first?.remainingPercent
    }

    public var statusText: String {
        if previewOnly, connectionState == .ready {
            return language.demoStatus
        }
        return connectionState.statusText(language: language)
    }

    /// Public, credential-free state intended for the future consent bridge.
    public var currentState: CodexConnectionState { connectionState }

    /// A boolean rather than the previous snapshot itself prevents this API
    /// from exposing user usage, thread, or cost details.
    public var hasPriorRealSnapshot: Bool {
        lastLiveUsage != nil
            || lastLocalActivity?.availability == .available
            || previewDisplaysFixtureData
    }

    /// This is an in-memory gate only.  M1-G2 supplies the user-facing
    /// explanation and control; no preference, credential, or account data is
    /// persisted by this method.
    public func grantMonitorConsent() {
        guard !previewOnly else { return }
        guard monitorConsentDecision != .granted else { return }
        monitorConsentDecision = .granted
        monitorConsentDecision.persist(to: consentDefaults)
        monitorConsentGranted = true
        connectionState = .idle
        freshness = lastLiveUsage == nil ? .noRealData : .stale
        lastError = nil
        lastFailure = nil
        lastRefreshError = nil
    }

    public func revokeMonitorConsent() async {
        await clearMonitorConsent(decision: .unknown)
    }

    private func clearMonitorConsent(decision: CodexMonitorConsentDecision) async {
        guard !previewOnly else { return }
        cancelConnectionProgressObservation()
        cancelPeriodicRefresh()
        stopLocalSessionReconciliation()
        let epoch = invalidateOperations()
        monitorConsentGranted = false
        monitorConsentDecision = decision
        monitorConsentDecision.persist(to: consentDefaults)
        lastLiveUsage = nil
        lastLocalActivity = nil
        snapshot = .empty(language: language)
        connectionState = .notAuthorizedByMonitor
        freshness = .noRealData
        lastError = nil
        lastFailure = nil
        lastRefreshError = nil
        await client.disconnect()
        guard stateEpoch == epoch else { return }
    }

    /// UI-facing M1-G1 handoff name. This forwards only to the existing
    /// in-memory consent revocation path; it does not inspect or revoke Codex
    /// authorization itself.
    public func declineMonitorConsent() async {
        await clearMonitorConsent(decision: .declined)
    }

    public func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: AppLanguage.storageKey)
        if let lastLiveUsage {
            snapshot = UsageSnapshot(live: lastLiveUsage, language: newLanguage)
        } else if let lastLocalActivity {
            snapshot = UsageSnapshot(localActivity: lastLocalActivity, language: newLanguage)
        } else if previewDisplaysFixtureData {
            snapshot = .preview(language: newLanguage)
        } else {
            snapshot = .empty(language: newLanguage)
        }
        if let lastRefreshError {
            lastError = lastRefreshError.description(language: newLanguage)
        }
    }

    public func refresh() async {
        guard !previewOnly, activeOperationEpoch == nil else { return }
        guard monitorConsentGranted else {
            connectionState = .notAuthorizedByMonitor
            freshness = lastLiveUsage == nil ? .noRealData : .stale
            lastRefreshError = CodexUsageClientError(.monitorConsentMissing)
            lastFailure = .monitorConsentMissing
            lastError = lastRefreshError?.description(language: language)
            return
        }

        let epoch = beginOperation()
        defer { finishOperation(epoch) }
        let localActivity = await readLocalActivity()
        guard isCurrentOperation(epoch), monitorConsentGranted else { return }
        lastLocalActivity = localActivity
        connectionState = lastLiveUsage == nil ? .resolvingExecutable : .refreshingWithPreviousRealData
        observeConnectionProgress(for: epoch)
        do {
            let providerUsage = try await client.fetchUsage()
            let liveUsage = providerUsage.replacingLocalActivity(localActivity)
            guard isCurrentOperation(epoch) else { return }
            let refreshRequired = await client.takeUsageRefreshRequest()
            guard isCurrentOperation(epoch), monitorConsentGranted else { return }
            lastLiveUsage = liveUsage
            snapshot = UsageSnapshot(live: liveUsage, language: language)
            connectionState = .ready
            freshness = refreshRequired ? .refreshRequired : .fresh
            lastRefreshError = nil
            lastFailure = nil
            lastError = nil
            updatePeriodicRefreshSchedule()
        } catch {
            guard isCurrentOperation(epoch) else { return }
            let safeError = Self.safeError(from: error)
            let priorUsage = lastLiveUsage
            let reportedConnectionState = priorUsage == nil
                ? await client.connectionState()
                : .staleWithPreviousRealData(safeError.failure)
            guard isCurrentOperation(epoch), monitorConsentGranted else { return }
            lastRefreshError = safeError
            lastFailure = safeError.failure
            lastError = safeError.description(language: language)
            connectionState = reportedConnectionState
            if let priorUsage {
                let preserved = priorUsage.replacingLocalActivity(localActivity)
                lastLiveUsage = preserved
                snapshot = UsageSnapshot(live: preserved, language: language)
                snapshot.providerSource = UsageSourceStatus(
                    label: "Codex account",
                    scope: "account/read, account/rateLimits/read, account/usage/read",
                    capturedAt: priorUsage.providerCapturedAt,
                    isAvailable: true,
                    freshness: .stale
                )
            } else if localActivity.availability == .available {
                snapshot = UsageSnapshot(localActivity: localActivity, language: language)
            }
            freshness = lastLiveUsage == nil ? .noRealData : .stale
            updatePeriodicRefreshSchedule()
        }
    }

    /// Starts the production dual-source refresh after monitor consent. The
    /// provider client performs exactly account/read before rate/usage reads;
    /// local metadata is refreshed independently and remains visible if that
    /// account channel is unavailable.
    public func connectToLocalSession() async {
        await checkLocalSession()
    }

    /// Exposes one explicit account/read retry after official CLI sign-in was
    /// completed outside this monitor.
    public func checkLocalSessionAgain() async {
        await checkLocalSession()
    }

    /// Stops only the monitor's reconciliation and local app-server. It never
    /// calls account/logout or otherwise affects the official app session.
    public func cancelLocalSessionReconciliation() async {
        guard !previewOnly else { return }
        stopLocalSessionReconciliation()
        let epoch = invalidateOperations()
        await client.disconnect()
        guard stateEpoch == epoch else { return }
        connectionState = monitorConsentGranted ? .idle : .notAuthorizedByMonitor
        lastError = nil
        lastFailure = nil
        lastRefreshError = nil
    }

    /// Stops the retained local process without revoking Codex authorization.
    /// Existing real usage remains internal and is marked stale until refreshed.
    public func disconnectMonitor() async {
        guard !previewOnly else { return }
        stopLocalSessionReconciliation()
        let epoch = invalidateOperations()
        await client.disconnect()
        guard stateEpoch == epoch else { return }
        connectionState = monitorConsentGranted ? .idle : .notAuthorizedByMonitor
        if lastLiveUsage != nil {
            freshness = .stale
        }
        updatePeriodicRefreshSchedule()
    }

    /// Stops only this monitor connection, clears its local consent decision
    /// and displayed data, and never signs the user out of Codex.
    public func disconnectAndForgetConsent() async {
        await clearMonitorConsent(decision: .unknown)
    }

    /// Creates an explicit shutdown/start boundary before one normal
    /// account-first refresh.  It never retries autonomously.
    public func reconnectMonitor() async {
        guard !previewOnly else { return }
        stopLocalSessionReconciliation()
        let epoch = invalidateOperations()
        await client.disconnect()
        guard stateEpoch == epoch else { return }
        connectionState = monitorConsentGranted ? .idle : .notAuthorizedByMonitor
        guard monitorConsentGranted else { return }
        await connectToLocalSession()
    }

    public func setPanelVisible(_ isVisible: Bool) {
        guard !previewOnly else { return }
        isPanelVisible = isVisible
        updatePeriodicRefreshSchedule()
    }

    public var allowsManualRefresh: Bool {
        guard monitorConsentGranted, hasPriorRealSnapshot else { return false }
        return switch connectionState {
        case .ready, .staleWithPreviousRealData:
            true
        default:
            false
        }
    }

    private static func safeError(from error: Error) -> CodexUsageClientError {
        (error as? CodexUsageClientError) ?? CodexUsageClientError(.unknownSafeError)
    }

    /// This helper is the only path that turns an absent account into the
    /// official-app state. It deliberately asks the client for account status
    /// before any rate-limit or usage request.
    private func checkLocalSession() async {
        guard !previewOnly, activeOperationEpoch == nil else { return }
        guard monitorConsentGranted else {
            connectionState = .notAuthorizedByMonitor
            return
        }

        let epoch = beginOperation()
        defer { finishOperation(epoch) }
        let localActivity = await readLocalActivity()
        guard isCurrentOperation(epoch), monitorConsentGranted else { return }
        lastLocalActivity = localActivity
        connectionState = .resolvingExecutable
        observeConnectionProgress(for: epoch)
        do {
            let accountAvailable = try await client.checkLocalAccountAvailability()
            guard isCurrentOperation(epoch) else { return }
            guard accountAvailable else {
                connectionState = .officialCodexSignInRequired
                lastRefreshError = nil
                lastFailure = nil
                lastError = nil
                if let priorUsage = lastLiveUsage {
                    preservePriorProviderUsage(priorUsage, localActivity: localActivity)
                } else if localActivity.availability == .available {
                    snapshot = UsageSnapshot(localActivity: localActivity, language: language)
                }
                // A usage-only monitor never retries sign-in automatically.
                // The Human completes official CLI sign-in outside this app,
                // then explicitly chooses Check Again.
                stopLocalSessionReconciliation()
                return
            }
            let providerUsage = try await client.fetchUsageAfterVerifiedAccount()
            let liveUsage = providerUsage.replacingLocalActivity(localActivity)
            guard isCurrentOperation(epoch) else { return }
            let refreshRequired = await client.takeUsageRefreshRequest()
            guard isCurrentOperation(epoch), monitorConsentGranted else { return }
            stopLocalSessionReconciliation()
            acceptLiveUsage(liveUsage, refreshRequired: refreshRequired)
        } catch {
            guard isCurrentOperation(epoch) else { return }
            let safeError = Self.safeError(from: error)
            let providerState = await client.connectionState()
            guard isCurrentOperation(epoch), monitorConsentGranted else { return }
            lastRefreshError = safeError
            lastFailure = safeError.failure
            lastError = safeError.description(language: language)
            connectionState = providerState
            if let priorUsage = lastLiveUsage {
                preservePriorProviderUsage(priorUsage, localActivity: localActivity)
            } else if localActivity.availability == .available {
                snapshot = UsageSnapshot(localActivity: localActivity, language: language)
            }
            if safeError.failure == .accountAuthorizationRequired {
                connectionState = .officialCodexSignInRequired
                stopLocalSessionReconciliation()
            } else if safeError.failure == .processExited {
                stopLocalSessionReconciliation()
            }
        }
    }

    /// Keeps an independently valid local channel current while making a
    /// failed or unavailable provider channel visibly stale.  This method
    /// never substitutes local totals for provider values.
    private func preservePriorProviderUsage(
        _ priorUsage: CodexLiveUsage,
        localActivity: CodexLocalActivitySnapshot
    ) {
        let preserved = priorUsage.replacingLocalActivity(localActivity)
        lastLiveUsage = preserved
        snapshot = UsageSnapshot(live: preserved, language: language)
        snapshot.providerSource = UsageSourceStatus(
            label: "Codex account",
            scope: "account/read, account/rateLimits/read, account/usage/read",
            capturedAt: priorUsage.providerCapturedAt,
            isAvailable: true,
            freshness: .stale
        )
        freshness = .stale
    }

    private func acceptLiveUsage(
        _ liveUsage: CodexLiveUsage,
        refreshRequired: Bool
    ) {
        let mergedUsage: CodexLiveUsage
        if let localActivity = lastLocalActivity, liveUsage.localActivity == nil {
            mergedUsage = liveUsage.replacingLocalActivity(localActivity)
        } else {
            mergedUsage = liveUsage
        }
        lastLiveUsage = mergedUsage
        snapshot = UsageSnapshot(live: mergedUsage, language: language)
        connectionState = .ready
        freshness = refreshRequired ? .refreshRequired : .fresh
        lastRefreshError = nil
        lastFailure = nil
        lastError = nil
        updatePeriodicRefreshSchedule()
    }

    private func readLocalActivity() async -> CodexLocalActivitySnapshot {
        let reader = localActivityReader
        let now = Date()
        let activity = await Task.detached(priority: .utility) {
            reader.read(now: now)
        }.value
        return activity
    }

    private func stopLocalSessionReconciliation() {
        // There is no automatic sign-in reconciliation. This no-op keeps the
        // disconnect path explicit while preserving its call sites.
    }

    private func beginOperation() -> Int {
        stateEpoch &+= 1
        activeOperationEpoch = stateEpoch
        isRefreshing = true
        return stateEpoch
    }

    private func finishOperation(_ epoch: Int) {
        guard activeOperationEpoch == epoch else { return }
        activeOperationEpoch = nil
        isRefreshing = false
        cancelConnectionProgressObservation()
    }

    private func isCurrentOperation(_ epoch: Int) -> Bool {
        stateEpoch == epoch && activeOperationEpoch == epoch
    }

    private func observeConnectionProgress(for epoch: Int) {
        connectionProgressTask?.cancel()
        let client = self.client
        connectionProgressTask = Task { @MainActor [weak self, client] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                guard let self, self.isCurrentOperation(epoch), self.lastLiveUsage == nil else { return }
                let state = await client.connectionState()
                guard self.isCurrentOperation(epoch), Self.isFirstLoadProgressState(state) else { continue }
                self.connectionState = state
            }
        }
    }

    private func cancelConnectionProgressObservation() {
        connectionProgressTask?.cancel()
        connectionProgressTask = nil
    }

    private static func isFirstLoadProgressState(_ state: CodexConnectionState) -> Bool {
        switch state {
        case .resolvingExecutable, .startingServer, .initializing, .checkingAccount,
             .accountAvailable, .authorizationRequired, .loadingRateLimits, .loadingUsage,
             .loadingOptionalActivity:
            true
        default:
            false
        }
    }

    private var allowsPeriodicRefresh: Bool {
        isPanelVisible && monitorConsentGranted && hasPriorRealSnapshot && connectionState == .ready
    }

    private func updatePeriodicRefreshSchedule() {
        guard allowsPeriodicRefresh else {
            cancelPeriodicRefresh()
            return
        }
        guard periodicRefreshTask == nil else { return }
        let interval = periodicRefreshInterval
        periodicRefreshTask = Task { @MainActor [weak self] in
            defer { self?.periodicRefreshTask = nil }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard let self, self.allowsPeriodicRefresh else { return }
                await self.refresh()
                guard self.connectionState == .ready else { return }
            }
        }
    }

    private func cancelPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }

    @discardableResult
    private func invalidateOperations() -> Int {
        stateEpoch &+= 1
        activeOperationEpoch = nil
        isRefreshing = false
        return stateEpoch
    }

    deinit {
        connectionProgressTask?.cancel()
        periodicRefreshTask?.cancel()
    }
}
