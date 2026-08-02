import Combine
import Foundation

enum ClaudeSettingsPresentationState: Equatable, Sendable {
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
        static let consent = "ClaudeBrowserSyncConsent.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var consentGranted: Bool {
        get { defaults.bool(forKey: Key.consent) }
        set { defaults.set(newValue, forKey: Key.consent) }
    }
}

@MainActor
public final class ClaudeBrowserSettingsModel: ObservableObject {
    @Published private(set) var state: ClaudeSettingsPresentationState
    @Published private(set) var actionInProgress = false
    @Published private(set) var safeError: String?
    @Published private(set) var consentGranted: Bool

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
        run { connector in await connector.checkCompanion() }
    }

    func connectWithConsent() {
        consentStore.consentGranted = true
        consentGranted = true
        run { connector in await connector.connect(openUsagePage: true) }
    }

    func syncNow() {
        run { connector in await connector.syncNow() }
    }

    func openUsagePage() {
        run { connector in await connector.openUsagePage() }
    }

    func repairCompanion() {
        run { connector in await connector.repairCompanion() }
    }

    func disconnect() {
        run { connector in await connector.disconnect() }
    }

    private func run(
        _ operation: @escaping @Sendable (ClaudeCodeUsageConnector) async -> Void
    ) {
        guard !actionInProgress else { return }
        actionInProgress = true
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
            actionInProgress = false
        }
    }

    private func updatePresentation(
        lifecycle: ClaudeConnectorLifecycleState,
        snapshot: AgentUsageSnapshot
    ) {
        state = switch lifecycle {
        case .disconnected: .disconnected
        case .checking: .checking
        case .waitingForUsagePage: .waitingForUsagePage
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
            safeError = "Claude's Usage page changed. Browser Sync stopped safely."
        } else if snapshot.safeFailure == .timedOut {
            safeError = "Claude Browser Sync timed out."
        } else if snapshot.safeFailure == .malformedResponse {
            safeError = "Claude Browser Sync rejected an ambiguous Usage page."
        }
    }
}
