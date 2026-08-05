import Combine
import Foundation

enum ClaudeSettingsPresentationState: Equatable, Sendable {
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

enum ClaudeSettingsAction: Equatable, Sendable {
    case checking
    case connecting
    case refreshing
    case openingUsage
    case repairing
    case grantingAccess
    case openingAccessSettings
    case disconnecting
}

enum ClaudeSettingsSafeError: Equatable, Sendable {
    case routeChanged
    case timedOut
    case ambiguousUsagePage
}

struct ClaudeSourceTransparency: Equatable, Sendable {
    let source = "Claude official Usage page · Browser Sync · Experimental"
    let login = "System default browser"
    let passwordAccessed = false
    let apiKeyRequired = false
    let keychainAccessed = false
    let cookiesReadOrExported = false
    let pageData = "Normalized quota percentages and reset times only"
    let privateContentAccessed = false
    let storedLocally = "Consent plus an owner-only sanitized quota cache"
}

@MainActor
final class ClaudeBrowserConsentStore {
    private enum Key {
        // v2 is a deliberate migration gate: the previous v1 consent covered
        // only a user-triggered, one-tab read and cannot silently authorize
        // persistent website access or recurring browser automation.
        static let consent = "ClaudeBrowserSyncConsent.v2"
        static let autoRefresh = "ClaudeBrowserSyncAutoRefresh.v1"
        static let allowSafariLaunch = "ClaudeBrowserSyncAllowSafariLaunch.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var consentGranted: Bool {
        get { defaults.bool(forKey: Key.consent) }
        set { defaults.set(newValue, forKey: Key.consent) }
    }

    var autoRefreshEnabled: Bool {
        get { defaults.bool(forKey: Key.autoRefresh) }
        set { defaults.set(newValue, forKey: Key.autoRefresh) }
    }

    var allowSafariLaunch: Bool {
        get { defaults.bool(forKey: Key.allowSafariLaunch) }
        set { defaults.set(newValue, forKey: Key.allowSafariLaunch) }
    }
}

@MainActor
public final class ClaudeBrowserSettingsModel: ObservableObject {
    @Published private(set) var state: ClaudeSettingsPresentationState
    @Published private(set) var actionInProgress = false
    @Published private(set) var activeAction: ClaudeSettingsAction?
    @Published private(set) var safeError: ClaudeSettingsSafeError?
    @Published private(set) var consentGranted: Bool
    @Published private(set) var autoRefreshEnabled: Bool
    @Published private(set) var allowSafariLaunch: Bool

    let sourceTransparency = ClaudeSourceTransparency()
    private let connector: ClaudeCodeUsageConnector
    private let consentStore: ClaudeBrowserConsentStore
    private let refreshAdmissions: @MainActor @Sendable () async -> Void
    private var observationTask: Task<Void, Never>?

    init(
        connector: ClaudeCodeUsageConnector,
        consentStore: ClaudeBrowserConsentStore,
        refreshAdmissions: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.connector = connector
        self.consentStore = consentStore
        self.refreshAdmissions = refreshAdmissions
        consentGranted = consentStore.consentGranted
        autoRefreshEnabled = consentStore.autoRefreshEnabled
        allowSafariLaunch = consentStore.allowSafariLaunch
        state = consentStore.consentGranted ? .checking : .disconnected
        observationTask = Task { [weak self] in
            let stream = await connector.snapshots()
            for await snapshot in stream {
                guard !Task.isCancelled, let self else { return }
                self.updatePresentation(
                    lifecycle: await connector.lifecycleState(),
                    snapshot: snapshot
                )
                if snapshot.freshness == .fresh, snapshot.hasValidData {
                    await self.refreshAdmissions()
                }
            }
        }
    }

    deinit { observationTask?.cancel() }

    func checkCompanion() {
        run(.checking) { connector in await connector.checkCompanion() }
    }

    func connectWithConsent() {
        // The Continue control is the explicit in-product opt-in. Recurring
        // automation becomes On only at this boundary, never by migration or
        // by merely launching a previously connected build.
        consentStore.autoRefreshEnabled = true
        autoRefreshEnabled = true
        consentStore.consentGranted = true
        consentGranted = true
        run(.connecting) { connector in await connector.connect(openUsagePage: true) }
    }

    func syncNow() {
        run(.refreshing) { connector in await connector.syncNow() }
    }

    func openUsagePage() {
        run(.openingUsage) { connector in await connector.openUsagePage() }
    }

    func repairCompanion() {
        run(.repairing) { connector in await connector.repairCompanion() }
    }

    func grantWebsiteAccess() {
        run(.grantingAccess) { connector in
            await connector.openUsagePage()
            await connector.repairCompanion()
        }
    }

    func openSafariAccessSettings() {
        run(.openingAccessSettings) { connector in
            await connector.repairCompanion()
        }
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        autoRefreshEnabled = enabled
        consentStore.autoRefreshEnabled = enabled
        Task { await connector.automationPreferenceChanged() }
    }

    func setAllowSafariLaunch(_ allowed: Bool) {
        allowSafariLaunch = allowed
        consentStore.allowSafariLaunch = allowed
        Task { await connector.automationPreferenceChanged() }
    }

    func disconnect() {
        run(.disconnecting) { connector in await connector.disconnect() }
    }

    private func run(
        _ action: ClaudeSettingsAction,
        _ operation: @escaping @Sendable (ClaudeCodeUsageConnector) async -> Void
    ) {
        guard !actionInProgress else { return }
        actionInProgress = true
        activeAction = action
        safeError = nil
        let connector = self.connector
        Task {
            await operation(connector)
            consentGranted = consentStore.consentGranted
            let snapshot = await connector.currentSnapshot()
            updatePresentation(
                lifecycle: await connector.lifecycleState(),
                snapshot: snapshot
            )
            await refreshAdmissions()
            activeAction = nil
            actionInProgress = false
        }
    }

    private func updatePresentation(
        lifecycle: ClaudeConnectorLifecycleState,
        snapshot: AgentUsageSnapshot
    ) {
        safeError = nil
        state = switch lifecycle {
        case .disconnected: .disconnected
        case .checking: .checking
        case .waitingForUsagePage: .waitingForUsagePage
        case .websiteAccessRequired: .websiteAccessRequired
        case .signInRequired: .signInRequired
        case .waitingForSafari: .waitingForSafari
        case let .fresh(date): .fresh(date)
        case let .cached(date): .cached(date)
        case let .stale(date): .stale(date)
        case .companionDisabled: .companionDisabled
        case .companionOutdated: .companionOutdated
        case .unsupportedBrowser: .unsupportedBrowser
        case .browserUnavailable: .browserUnavailable
        case .nativeHostMissing: .nativeHostMissing
        case .nativeHostMismatched: .nativeHostMismatched
        case .routeChanged: .routeChanged
        case .failed: .failed
        }
        if lifecycle == .routeChanged {
            safeError = .routeChanged
        } else if snapshot.safeFailure == .timedOut {
            safeError = .timedOut
        } else if snapshot.safeFailure == .malformedResponse {
            safeError = .ambiguousUsagePage
        }
    }
}
