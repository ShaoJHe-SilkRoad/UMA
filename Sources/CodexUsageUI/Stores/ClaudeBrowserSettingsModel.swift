import Combine
import ClaudeBrowserNativeHostCore
import ClaudeSafariHostIPC
import ClaudeStatusLineCore
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
    case extensionNotInstalled
    case inventoryRestartRequired
    case inventoryLoading
    case companionStarting
    case protocolMismatch
    case companionUnavailable
    case routeChanged
    case failed
}

enum ClaudeSettingsAction: Equatable, Sendable {
    case checking
    case connecting
    case refreshing
    case checkingCompanion
    case repairing
    case requestingSiteAccess
    case retryingSiteAccess
    case disconnecting
}

enum ClaudeSettingsSafeError: Equatable, Sendable {
    case routeChanged
    case timedOut
    case ambiguousUsagePage
}

struct ClaudeSourceTransparency: Equatable, Sendable {
    let source = "Claude Local Smart Mode · official status line · version-pinned Desktop estimate · one-shot Safari exact"
    let login = "Claude Code provider-owned session"
    let passwordAccessed = false
    let apiKeyRequired = false
    let keychainAccessed = false
    let cookiesReadOrExported = false
    let pageData = "Sanitized rate-limit fields, current Desktop estimates, and local usage aggregates only"
    let privateContentAccessed = false
    let storedLocally = "Owner-only exact anchors and sanitized calibration metadata"
}

/// Provider-specific state projected into the shared Agent workspace without
/// leaking browser/runtime implementation types into the application shell.
public enum ClaudeAgentControlState: Equatable, Sendable {
    case consentRequired
    case localSmartRepairRequired
    case accuracyReady
    case accuracyInProgress
    case companionStarting
    case companionUpdateRequired
    case onlineVerificationUnavailable

    static func classify(
        consentGranted: Bool,
        localSmartState: ClaudeLocalSmartState,
        companionRuntime: ClaudeCompanionRuntimeState,
        browserAccuracyState: ClaudeBrowserAccuracyState
    ) -> Self {
        guard consentGranted else { return .consentRequired }
        switch localSmartState {
        case .unavailable, .error:
            return .localSmartRepairRequired
        case .exactLocal, .estimated, .staleUnsupported:
            break
        }
        switch companionRuntime {
        case .ready:
            return browserAccuracyState == .syncing ? .accuracyInProgress : .accuracyReady
        case .starting:
            return .companionStarting
        case .updatePendingSafariRestart, .protocolMismatch:
            return .companionUpdateRequired
        case .notConfigured, .unavailable:
            return .onlineVerificationUnavailable
        }
    }
}

@MainActor
final class ClaudeBrowserConsentStore {
    private enum Key {
        static let consent = "ClaudeLocalSmartModeConsent.v1"
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
        get { false }
        set { defaults.set(false, forKey: Key.autoRefresh) }
    }

    var allowSafariLaunch: Bool {
        get { false }
        set { defaults.set(false, forKey: Key.allowSafariLaunch) }
    }

    func retirePersistentBrowserAutomation() {
        defaults.set(false, forKey: Key.autoRefresh)
        defaults.set(false, forKey: Key.allowSafariLaunch)
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
    @Published private(set) var estimateConfidence: String?
    @Published private(set) var lastExactAt: Date?
    @Published private(set) var liveLinkStage: ClaudeLiveLinkStageReason?
    @Published private(set) var currentQuotaIncludesSafariAccuracy: Bool
    @Published private(set) var localSmartState: ClaudeLocalSmartState
    @Published private(set) var browserAccuracyState: ClaudeBrowserAccuracyState
    @Published private(set) var localSmartStage: ClaudeLiveLinkStageReason?
    @Published private(set) var browserAccuracyStage: ClaudeLiveLinkStageReason?

    let sourceTransparency = ClaudeSourceTransparency()

    /// Product surfaces may use this to distinguish first-time consent from a
    /// recoverable Local Smart startup failure. The consent value remains owned
    /// by this model; views must still route mutations through its actions.
    public var hasLocalSmartConsent: Bool { consentGranted }

    public var agentControlState: ClaudeAgentControlState {
        ClaudeAgentControlState.classify(
            consentGranted: consentGranted,
            localSmartState: localSmartState,
            companionRuntime: productState.companionRuntime,
            browserAccuracyState: browserAccuracyState
        )
    }

    var productState: ClaudeProductStateMatrix {
        ClaudeProductStateMatrix.classify(
            presentationState: state,
            consentGranted: consentGranted,
            localSmartState: localSmartState,
            browserAccuracyState: browserAccuracyState,
            browserAccuracyStage: browserAccuracyStage
        )
    }

    private let connector: ClaudeCodeUsageConnector
    private let consentStore: ClaudeBrowserConsentStore
    private let configurationManager: ClaudeStatusLineConfigurationManager?
    private let refreshAdmissions: @MainActor @Sendable () async -> Void
    private var observationTask: Task<Void, Never>?
    private var configurationRestoreFailure: ClaudeSettingsPresentationState?

    init(
        connector: ClaudeCodeUsageConnector,
        consentStore: ClaudeBrowserConsentStore,
        configurationManager: ClaudeStatusLineConfigurationManager? = nil,
        refreshAdmissions: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.connector = connector
        self.consentStore = consentStore
        self.configurationManager = configurationManager
        self.refreshAdmissions = refreshAdmissions
        consentGranted = consentStore.consentGranted
        autoRefreshEnabled = false
        allowSafariLaunch = false
        estimateConfidence = nil
        lastExactAt = nil
        liveLinkStage = nil
        currentQuotaIncludesSafariAccuracy = false
        localSmartState = .unavailable
        browserAccuracyState = .notConfigured
        localSmartStage = nil
        browserAccuracyStage = nil
        consentStore.retirePersistentBrowserAutomation()
        state = consentStore.consentGranted ? .checking : .disconnected
        observationTask = Task { [weak self] in
            let stream = await connector.snapshots()
            for await snapshot in stream {
                guard !Task.isCancelled, let self else { return }
                self.updatePresentation(
                    lifecycle: await connector.lifecycleState(),
                    snapshot: snapshot,
                    diagnostics: await connector.diagnostics()
                )
            }
        }
    }

    deinit { observationTask?.cancel() }

    func checkCompanion() {
        guard let configurationManager else {
            run(.checking) { connector in await connector.syncNow() }
            return
        }
        let check = configurationManager.check()
        switch check.state {
        case .installed:
            switch state {
            case .fresh, .cached, .stale:
                state = snapshotReadyState()
            default:
                run(.checking) { connector in await connector.checkCompanion() }
            }
        case .ready, .unconfigured:
            state = .disconnected
        case .repairRequired:
            state = .companionOutdated
        case .unsupported:
            state = .unsupportedBrowser
        case .failed:
            state = .failed
        }
    }

    public func connectWithConsent() {
        guard !actionInProgress else { return }
        actionInProgress = true
        activeAction = .connecting
        safeError = nil
        let connector = connector
        let manager = configurationManager
        Task {
            do {
                if let manager {
                    switch manager.check().state {
                    case .installed: break
                    case .repairRequired: try manager.repair()
                    default: try manager.enable()
                    }
                }
                configurationRestoreFailure = nil
                consentStore.retirePersistentBrowserAutomation()
                consentStore.consentGranted = true
                consentGranted = true
                await connector.connect(openUsagePage: false)
                let snapshot = await connector.currentSnapshot()
                updatePresentation(
                    lifecycle: await connector.lifecycleState(),
                    snapshot: snapshot,
                    diagnostics: await connector.diagnostics()
                )
            } catch {
                state = .failed
            }
            activeAction = nil
            actionInProgress = false
            await refreshAdmissions()
        }
    }

    public func syncNow() {
        run(.refreshing) { connector in await connector.syncNow() }
    }

    public func accuracySync() {
        run(.refreshing) { connector in await connector.accuracySync() }
    }

    func runOneShotAccuracySyncDiagnostic(
        maximumTerminalPolls: Int = 400,
        maximumCleanupPolls: Int = 50,
        sleep: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(100))
        },
        receiptProbe: @escaping @Sendable () -> Bool? =
            ClaudeAccuracySyncMachineVerifier.hostOwnedTabReceiptAbsent
    ) async -> ClaudeAccuracySyncMachineResult {
        let initial = await connector.diagnostics()
        guard consentStore.consentGranted else {
            return ClaudeAccuracySyncMachineResult(
                status: .consentRequired,
                exactAnchorReceived: false,
                tempTabReceiptAbsent: receiptProbe(),
                localSmartState: .classify(initial.localSmartState)
            )
        }

        await connector.accuracySync()
        var terminal = await connector.diagnostics()
        var remaining = maximumTerminalPolls
        while remaining > 0,
              terminal.automaticRefreshInFlight
                || terminal.browserAccuracyState == .syncing {
            remaining -= 1
            await sleep()
            terminal = await connector.diagnostics()
        }

        let timedOut = terminal.automaticRefreshInFlight
            || terminal.browserAccuracyState == .syncing
        let exactAnchorReceived = terminal.acceptedObservationCount
                > initial.acceptedObservationCount
            && terminal.currentQuotaIncludesSafariAccuracy
            && terminal.browserAccuracyState.isExactAnchorAvailable

        var receiptAbsent = receiptProbe()
        var cleanupRemaining = maximumCleanupPolls
        while exactAnchorReceived,
              receiptAbsent == false,
              cleanupRemaining > 0 {
            cleanupRemaining -= 1
            await sleep()
            receiptAbsent = receiptProbe()
        }

        await connector.stop()
        return ClaudeAccuracySyncMachineResult(
            status: ClaudeAccuracySyncMachineResult.Status.classify(
                diagnostics: terminal,
                exactAnchorReceived: exactAnchorReceived,
                timedOut: timedOut,
                receiptAbsent: receiptAbsent
            ),
            exactAnchorReceived: exactAnchorReceived,
            tempTabReceiptAbsent: receiptAbsent,
            localSmartState: .classify(terminal.localSmartState)
        )
    }

    func verifyCompanion() {
        run(.checkingCompanion) { connector in await connector.checkCompanion() }
    }

    func repairCompanion() {
        guard let configurationManager else {
            run(.repairing) { connector in await connector.syncNow() }
            return
        }
        guard !actionInProgress else { return }
        actionInProgress = true
        activeAction = .repairing
        Task {
            do {
                try configurationManager.repair()
                configurationRestoreFailure = nil
                await connector.syncNow()
            } catch {
                state = .failed
            }
            activeAction = nil
            actionInProgress = false
        }
    }

    func requestSafariSiteAccess() {
        run(.requestingSiteAccess) { connector in await connector.accuracySync() }
    }

    func retrySafariSiteAccess() {
        run(.retryingSiteAccess) { connector in await connector.accuracySync() }
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        _ = enabled
        autoRefreshEnabled = false
        consentStore.autoRefreshEnabled = false
    }

    func setAllowSafariLaunch(_ allowed: Bool) {
        _ = allowed
        allowSafariLaunch = false
        consentStore.allowSafariLaunch = false
    }

    public func disconnect() {
        guard !actionInProgress else { return }
        actionInProgress = true
        activeAction = .disconnecting
        Task {
            await connector.prepareForConfigurationRestore()
            do {
                try configurationManager?.disable()
                configurationRestoreFailure = nil
                consentStore.consentGranted = false
                consentGranted = false
                state = .disconnected
            } catch {
                consentGranted = consentStore.consentGranted
                let failureState: ClaudeSettingsPresentationState = configurationManager?.check().state == .repairRequired
                    ? .companionOutdated
                    : .failed
                configurationRestoreFailure = failureState
                state = failureState
            }
            activeAction = nil
            actionInProgress = false
            await refreshAdmissions()
        }
    }

    private func snapshotReadyState() -> ClaudeSettingsPresentationState {
        switch state {
        case let .fresh(date): .fresh(date)
        case let .cached(date): .cached(date)
        case let .stale(date): .stale(date)
        default: .checking
        }
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
                snapshot: snapshot,
                diagnostics: await connector.diagnostics()
            )
            activeAction = nil
            actionInProgress = false
            await refreshAdmissions()
        }
    }

    private func updatePresentation(
        lifecycle: ClaudeConnectorLifecycleState,
        snapshot: AgentUsageSnapshot,
        diagnostics: ClaudeBrowserConnectorDiagnostics
    ) {
        if let configurationRestoreFailure {
            state = configurationRestoreFailure
            return
        }
        let account = snapshot.channels.first(where: { $0.id == .account })
        estimateConfidence = account?.sourceConfidence
        lastExactAt = account?.lastExactAt
        liveLinkStage = diagnostics.lastLiveLinkStage
        currentQuotaIncludesSafariAccuracy = diagnostics.currentQuotaIncludesSafariAccuracy
        localSmartState = diagnostics.localSmartState
        browserAccuracyState = diagnostics.browserAccuracyState
        localSmartStage = diagnostics.localSmartStage
        browserAccuracyStage = diagnostics.browserAccuracyStage
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
        case .extensionNotInstalled: .extensionNotInstalled
        case .inventoryRestartRequired: .inventoryRestartRequired
        case .inventoryLoading: .inventoryLoading
        case .companionStarting: .companionStarting
        case .protocolMismatch: .protocolMismatch
        case .companionUnavailable: .companionUnavailable
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

private extension ClaudeBrowserAccuracyState {
    var isExactAnchorAvailable: Bool {
        if case .exactAnchorAvailable = self { return true }
        return false
    }
}

public struct ClaudeAccuracySyncMachineResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case exactAnchorReceived
        case consentRequired
        case browserUnavailable
        case companionUnavailable
        case updatePendingRestart
        case protocolMismatch
        case permissionRequired
        case signInRequired
        case routeRejected
        case usageUnavailable
        case tabCleanupFailed
        case timedOut
        case failed

        fileprivate static func classify(
            diagnostics: ClaudeBrowserConnectorDiagnostics,
            exactAnchorReceived: Bool,
            timedOut: Bool,
            receiptAbsent: Bool?
        ) -> Self {
            if timedOut { return .timedOut }
            if exactAnchorReceived {
                return receiptAbsent == false ? .tabCleanupFailed : .exactAnchorReceived
            }
            switch diagnostics.browserAccuracyStage {
            case .accuracyInventoryRestartRequired: return .updatePendingRestart
            case .accuracyProtocolMismatch: return .protocolMismatch
            case .accuracyPermissionRequired: return .permissionRequired
            case .accuracySignInRequired: return .signInRequired
            case .accuracyRequestMismatch, .accuracyRouteRejected: return .routeRejected
            case .accuracyUsageUnavailable: return .usageUnavailable
            case .accuracyTabUnavailable, .accuracyOwnedTabLost: return .tabCleanupFailed
            case .accuracyBrowserUnavailable: return .browserUnavailable
            case .accuracyHandshakeUnavailable, .accuracyInventoryLoading,
                 .accuracyCompanionStarting, .accuracyCompanionUnavailable,
                 .accuracyWorkDispatchFailed:
                return .companionUnavailable
            case .accuracyExactReceived:
                return .failed
            case .none, .localStatusLinePending, .localStatusLineRejected,
                 .localActivityDetectedAwaitingExactAnchor,
                 .localCodeActivityDetectedDesktopUnavailable,
                 .localCallbackWithoutQuotaWindows, .localExactReceived,
                 .desktopActivitySignalUnavailable:
                return .failed
            }
        }
    }

    public enum LocalSmartState: String, Codable, Equatable, Sendable {
        case exact
        case estimated
        case staleUnsupported
        case unavailable
        case error

        fileprivate static func classify(_ state: ClaudeLocalSmartState) -> Self {
            switch state {
            case .exactLocal: .exact
            case .estimated: .estimated
            case .staleUnsupported: .staleUnsupported
            case .unavailable: .unavailable
            case .error: .error
            }
        }
    }

    public let schemaVersion: Int
    public let status: Status
    public let exactAnchorReceived: Bool
    public let tempTabReceiptAbsent: Bool?
    public let localSmartState: LocalSmartState

    init(
        status: Status,
        exactAnchorReceived: Bool,
        tempTabReceiptAbsent: Bool?,
        localSmartState: LocalSmartState
    ) {
        schemaVersion = 1
        self.status = status
        self.exactAnchorReceived = exactAnchorReceived
        self.tempTabReceiptAbsent = tempTabReceiptAbsent
        self.localSmartState = localSmartState
    }

    public var processExitCode: Int32 {
        switch status {
        case .exactAnchorReceived: 0
        case .consentRequired: 2
        case .browserUnavailable: 13
        case .companionUnavailable: 3
        case .updatePendingRestart: 4
        case .protocolMismatch: 5
        case .permissionRequired: 6
        case .signInRequired: 7
        case .routeRejected: 8
        case .usageUnavailable: 9
        case .tabCleanupFailed: 10
        case .timedOut: 11
        case .failed: 12
        }
    }

    public func encodedJSONLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}

public enum ClaudeAccuracySyncMachineVerifier {
    public static let launchArgument = "--qualify-claude-accuracy-sync"

    @MainActor
    public static func runLive(
        bundleIdentifier: String?,
        environment: [String: String]
    ) async -> ClaudeAccuracySyncMachineResult {
        guard let runtime = try? UsageMonitorRuntime.live(
            bundleIdentifier: bundleIdentifier,
            environment: environment,
            startProviders: false
        ) else {
            return ClaudeAccuracySyncMachineResult(
                status: .failed,
                exactAnchorReceived: false,
                tempTabReceiptAbsent: hostOwnedTabReceiptAbsent(),
                localSmartState: .unavailable
            )
        }
        return await runtime.claudeSettings.runOneShotAccuracySyncDiagnostic()
    }

    static func hostOwnedTabReceiptAbsent() -> Bool? {
        guard let context = ClaudeBrowserRuntimeContext.current(),
              let endpoint = try? ClaudeSafariHostIPCEndpoint.appGroup(
                identifier: context.appGroupIdentifier
              ) else {
            return nil
        }
        let containerPath = URL(fileURLWithPath: endpoint.rootDirectoryPath)
            .deletingLastPathComponent().path
        do {
            return try ClaudeBrowserOwnedTabReceiptStore.load(
                endpoint: .safariHostOwnedTab(
                    containerDirectoryPath: containerPath
                )
            ) == nil
        } catch {
            return nil
        }
    }
}
