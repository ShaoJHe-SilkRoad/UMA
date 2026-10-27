import AppKit
import CodexUsageUI
import Combine

enum AppShellDiagnosticStage: String, Codable, Sendable {
    case shellCreated
    case statusItemExists
    case statusItemEnabled
    case statusItemButtonExists
    case mouseDownReceived
    case mouseUpReceived
    case targetPresent
    case actionPresent
    case actionInvoked
    case mainActorEntered
    case toggleRequested
    case panelControllerExists
    case panelWindowExists
    case panelWindowOrderedFront
    case panelWindowKeyState
    case panelVisible
    case hitTestingEnabled
    case panelClosed
    case staleGenerationRejected
    case shellTornDown
    case runtimeAttached
    case runtimeAttachmentFailed
    case mainWindowGeometryObserved
}

struct AppShellDiagnosticReceipt: Codable, Sendable {
    let stage: AppShellDiagnosticStage
    let reached: Bool
    let lifecycleGeneration: String
    let statusItemCount: Int
    let panelWindowCount: Int
    let eventMonitorCount: Int
    let mainThreadStallMilliseconds: Int
    let activeModalWindow: Bool
    let activeSheetWindow: Bool
    let eventMonitorOwners: [String]
    let applicationIsHidden: Bool
    let frontmostApplicationBundleIdentifier: String?
    let panelLevel: Int?
    let panelAlpha: Double?
    let panelFrame: String?
    let panelIgnoresMouseEvents: Bool?
    /// Bounded native-window facts for installed-runtime geometry evidence.
    /// They contain no screen image, content, provider, or task data.
    let mainWindowFrame: String?
    let mainWindowContentRect: String?
    let mainWindowBackingScale: Double?
    let mainWindowIsZoomed: Bool?
    let mainWindowIsFullScreen: Bool?
    let detail: String?
    let timestamp: Date
}

struct AppShellMachineDiagnosticResult: Codable, Sendable {
    let requestedToggleCount: Int
    let completedToggleCount: Int
    let statusItemCount: Int
    let panelWindowCount: Int
    let eventMonitorCount: Int
    let applicationIsHidden: Bool
    let finalPanelVisible: Bool
    let providerStartupEnabled: Bool
    let passed: Bool
    let firstFailure: String?
}

struct NativeShellLifecycleDiagnosticResult: Codable, Sendable {
    let activationPolicyRegular: Bool
    let mainWindowSingleton: Bool
    let settingsWindowSingleton: Bool
    let mainWindowReopened: Bool
    let mainWindowStatePreserved: Bool
    let settingsNavigationPreserved: Bool
    let settingsContentReadyOnFirstShow: Bool
    let windowClosePreservedShell: Bool
    let statusItemSurvivedWindowClose: Bool
    let assistantSurvivedWindowClose: Bool
    let sharedRuntimeStore: Bool
    let nativeCommandRoutesPresent: Bool
    let threadOSRuntimeActivityCount: Int
    let requestedMainWindowCycles: Int
    let completedMainWindowCycles: Int
    let requestedSettingsWindowCycles: Int
    let completedSettingsWindowCycles: Int
    let requestedAgentSwitches: Int
    let completedAgentSwitches: Int
    let passed: Bool
}

struct UMA014M1MachineDiagnosticResult: Codable, Sendable {
    let nativeShell: NativeShellLifecycleDiagnosticResult
    let quickPanel: AppShellMachineDiagnosticResult
    let runtimeAttached: Bool
    let passed: Bool
    let firstFailure: String?
}

/// Content-free shell receipts make one physical menu-bar click diagnosable
/// without coupling the shell to any provider or browser subsystem.
final class AppShellDiagnosticRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.silkrd.uma.shell-diagnostics")
    private let destination: URL?
    private var boundedReceipts: [AppShellDiagnosticReceipt] = []

    init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        guard let bundleIdentifier else {
            destination = nil
            return
        }
        destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("ShellDiagnostics", isDirectory: true)
            .appendingPathComponent("latest.json")
    }

    func record(_ receipt: AppShellDiagnosticReceipt) {
        guard let destination else { return }
        queue.async {
            do {
                let directory = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                self.boundedReceipts.append(receipt)
                self.boundedReceipts = Array(self.boundedReceipts.suffix(64))
                let data = try JSONEncoder().encode(self.boundedReceipts)
                try data.write(to: destination, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: destination.path
                )
            } catch {
                // Diagnostics must never impede the product shell.
            }
        }
    }

    @MainActor
    func recordMainWindowGeometry(
        lifecycleGeneration: UUID,
        geometry: MainWindowGeometrySnapshot
    ) {
        record(
            AppShellDiagnosticReceipt(
                stage: .mainWindowGeometryObserved,
                reached: true,
                lifecycleGeneration: lifecycleGeneration.uuidString,
                statusItemCount: 0,
                panelWindowCount: 0,
                eventMonitorCount: 0,
                mainThreadStallMilliseconds: 0,
                activeModalWindow: NSApp.modalWindow != nil,
                activeSheetWindow: NSApp.windows.contains { $0.attachedSheet != nil },
                eventMonitorOwners: [],
                applicationIsHidden: NSApp.isHidden,
                frontmostApplicationBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                panelLevel: nil,
                panelAlpha: nil,
                panelFrame: nil,
                panelIgnoresMouseEvents: nil,
                mainWindowFrame: NSStringFromRect(geometry.frame),
                mainWindowContentRect: NSStringFromRect(geometry.contentRect),
                mainWindowBackingScale: geometry.backingScaleFactor,
                mainWindowIsZoomed: geometry.isZoomed,
                mainWindowIsFullScreen: geometry.isFullScreen,
                detail: "main-window read-only geometry",
                timestamp: Date()
            )
        )
    }
}

@MainActor
final class AppShellCoordinator {
    private static weak var activeCoordinator: AppShellCoordinator?

    let lifecycleGeneration = UUID()
    private let diagnostics: AppShellDiagnosticRecorder
    private let statusBarController: StatusBarController
    private let mainWindowController: MainWindowController
    private let settingsWindowController: SettingsWindowController
    private let assistantController: DesktopAssistantPanelController
    private var commandRouter: ApplicationMenuController!
    private var runtime: UsageMonitorRuntime?
    private var assistantStoreObserver: AnyCancellable?
    private var appearancePreferenceObservation: ApplicationPreferences.Observation?
    private var lifecyclePreferenceObservation: ApplicationPreferences.Observation?
    private var windowCloseObservations: [NSObjectProtocol] = []
    private var hasStarted = false
    private var isTornDown = false

    init(
        diagnostics: AppShellDiagnosticRecorder = AppShellDiagnosticRecorder()
    ) {
        precondition(Self.activeCoordinator == nil, "Only one AppShellCoordinator may be active")
        self.diagnostics = diagnostics
        let statusBarController = StatusBarController(
            lifecycleGeneration: lifecycleGeneration,
            diagnostics: diagnostics
        )
        let assistantController = DesktopAssistantPanelController()
        self.statusBarController = statusBarController
        self.assistantController = assistantController
        mainWindowController = MainWindowController()
        settingsWindowController = SettingsWindowController()
        Self.activeCoordinator = self
        assistantController.setSelectionHandler { [weak self] rawProviderID in
            guard let providerID = ProviderProductID(rawValue: rawProviderID) else { return }
            self?.showAgent(providerID)
        }
        statusBarController.bindAssistant(assistantController)
        commandRouter = ApplicationMenuController(coordinator: self)
        statusBarController.recordShellCreated()
        windowCloseObservations = [
            mainWindowController.window,
            settingsWindowController.window,
        ].compactMap { window in
            guard let window else { return nil }
            return NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            self?.applicationWindowDidClose()
                        }
                    }
                }
            }
        }
    }

    func start(presentMainWindow: Bool) {
        guard !hasStarted, !isTornDown else { return }
        hasStarted = true
        commandRouter.installMainMenu()
        if presentMainWindow { showMainWindow() }
    }

    func attach(runtime: UsageMonitorRuntime) {
        guard self.runtime == nil, !isTornDown else { return }
        self.runtime = runtime
        assistantController.bind(preferences: runtime.preferences)
        let quickActions = QuickPanelActions(
            openMain: { [weak self] in self?.showMainWindow() },
            scanAll: { [weak self] in self?.scanAllProviders() },
            refreshAll: { [weak self] in self?.refreshAllProviders() },
            toggleWizard: { [weak self] in self?.toggleDesktopAssistant() },
            openSettings: { [weak self] in self?.showSettingsWindow() },
            selectAgent: { [weak self] providerID in self?.showAgent(providerID) }
        )
        statusBarController.attach(runtime: runtime, actions: quickActions)
        mainWindowController.attach(
            store: runtime.store,
            openSettings: { [weak self] in self?.showSettingsWindow() },
            scanAll: { [weak self] in self?.scanAllProviders() },
            refreshAll: { [weak self] in self?.refreshAllProviders() },
            connectCodex: { [weak self] in self?.connectCodex() },
            disconnectCodex: { [weak self] in self?.disconnectCodex() },
            claudeControlState: { [weak self] in
                self?.runtime?.claudeSettings.agentControlState ?? .onlineVerificationUnavailable
            },
            connectClaude: { [weak self] in self?.connectClaude() },
            accuracySyncClaude: { [weak self] in self?.accuracySyncClaude() },
            claudeSettings: runtime.claudeSettings
        )
        settingsWindowController.attach(
            store: runtime.store, preferences: runtime.preferences, dataPaths: runtime.dataPaths
        )
        observeAppearance(in: runtime.preferences)
        observeLifecyclePreference(in: runtime.preferences)
        applyAppearance(from: runtime.preferences)
        observeAssistantCards(in: runtime.store)
        updateAssistant(using: runtime.store)
    }

    func recordRuntimeAttachmentFailure() {
        statusBarController.recordRuntimeAttachmentFailure()
    }

    func runMachineDiagnostic(
        toggleCount: Int,
        runtimeAttached: Bool = true
    ) async -> UMA014M1MachineDiagnosticResult {
        let nativeShell = runNativeLifecycleDiagnostic(
            mainWindowCycleCount: 25,
            settingsWindowCycleCount: 100,
            agentSwitchCount: 100
        )
        let quickPanel = await statusBarController.runMachineDiagnostic(toggleCount: toggleCount)
        return UMA014M1MachineDiagnosticResult(
            nativeShell: nativeShell,
            quickPanel: quickPanel,
            runtimeAttached: runtimeAttached,
            passed: runtimeAttached
                && nativeShell.activationPolicyRegular
                && nativeShell.passed
                && quickPanel.passed,
            firstFailure: runtimeAttached ? nil : "RUNTIME_COMPOSITION_FAILED"
        )
    }

    func runNativeLifecycleDiagnostic(
        mainWindowCycleCount: Int = 1,
        settingsWindowCycleCount: Int = 1,
        agentSwitchCount: Int = 2
    ) -> NativeShellLifecycleDiagnosticResult {
        let coordinatorIdentity = ObjectIdentifier(self)
        let statusIdentity = ObjectIdentifier(statusBarController)
        let assistantIdentity = ObjectIdentifier(assistantController)
        let runtimeStoreIdentity = runtime.map { ObjectIdentifier($0.store) }

        showAgent(.claude)
        let mainWindowIdentity = mainWindowController.windowIdentityForTesting
        let expectedMainAgent = mainWindowController.selectedAgentForTesting
        let expectedMainDestination = mainWindowController.destinationForTesting
        var completedMainWindowCycles = 0
        for _ in 0..<max(0, mainWindowCycleCount) {
            showMainWindow()
            guard mainWindowController.windowIdentityForTesting == mainWindowIdentity,
                  mainWindowController.isVisibleForTesting,
                  mainWindowController.selectedAgentForTesting == expectedMainAgent,
                  mainWindowController.destinationForTesting == expectedMainDestination else { break }
            mainWindowController.closeCanonicalWindow()
            guard !mainWindowController.isVisibleForTesting else { break }
            completedMainWindowCycles += 1
        }
        let mainWindowSingleton = completedMainWindowCycles == max(0, mainWindowCycleCount)
        let mainWindowStatePreserved = mainWindowController.selectedAgentForTesting == expectedMainAgent
            && mainWindowController.destinationForTesting == expectedMainDestination

        settingsWindowController.selectPaneForTesting(.appearance)
        showSettingsWindow()
        let settingsWindowIdentity = settingsWindowController.windowIdentityForTesting
        let requiresAttachedSettingsContent = runtime != nil
        let settingsContentReadyOnFirstShow = !requiresAttachedSettingsContent
            || settingsWindowController.hasReadyContentForTesting
        var completedSettingsWindowCycles = 0
        var settingsNavigationPreserved = true
        for index in 0..<max(0, settingsWindowCycleCount) {
            let expectedPane = GlobalSettingsPane.allCases[index % GlobalSettingsPane.allCases.count]
            settingsWindowController.selectPaneForTesting(expectedPane)
            showSettingsWindow()
            guard settingsWindowController.windowIdentityForTesting == settingsWindowIdentity,
                  settingsWindowController.isVisibleForTesting,
                  settingsWindowController.selectedPaneForTesting == expectedPane,
                  (!requiresAttachedSettingsContent
                    || settingsWindowController.hasReadyContentForTesting) else {
                settingsNavigationPreserved = false
                break
            }
            settingsWindowController.closeCanonicalWindow()
            guard !settingsWindowController.isVisibleForTesting,
                  settingsWindowController.selectedPaneForTesting == expectedPane else {
                settingsNavigationPreserved = false
                break
            }
            completedSettingsWindowCycles += 1
        }
        let settingsWindowSingleton =
            completedSettingsWindowCycles == max(0, settingsWindowCycleCount)

        var completedAgentSwitches = 0
        for index in 0..<max(0, agentSwitchCount) {
            let providerID: ProviderProductID = index.isMultiple(of: 2) ? .codex : .claude
            showAgent(providerID)
            guard mainWindowController.selectedAgentForTesting == providerID,
                  mainWindowController.windowIdentityForTesting == mainWindowIdentity else { break }
            completedAgentSwitches += 1
        }

        mainWindowController.closeCanonicalWindow()
        settingsWindowController.closeCanonicalWindow()
        let windowClosePreservedShell =
            !isTornDown && ObjectIdentifier(self) == coordinatorIdentity
        let statusItemSurvivedWindowClose =
            ObjectIdentifier(statusBarController) == statusIdentity
                && statusBarController.isActiveForDiagnostic
        let assistantSurvivedWindowClose =
            ObjectIdentifier(assistantController) == assistantIdentity

        showMainWindow()
        let mainWindowReopened =
            mainWindowController.windowIdentityForTesting == mainWindowIdentity
                && mainWindowController.isVisibleForTesting
        mainWindowController.closeCanonicalWindow()

        let sharedRuntimeStore = runtimeStoreIdentity != nil
            && mainWindowController.attachedStoreIdentityForTesting == runtimeStoreIdentity
            && settingsWindowController.attachedStoreIdentityForTesting == runtimeStoreIdentity
        let menu = commandRouter.diagnosticState
        let passed = mainWindowSingleton
            && settingsWindowSingleton
            && mainWindowReopened
            && mainWindowStatePreserved
            && settingsNavigationPreserved
            && settingsContentReadyOnFirstShow
            && windowClosePreservedShell
            && statusItemSurvivedWindowClose
            && assistantSurvivedWindowClose
            && completedAgentSwitches == max(0, agentSwitchCount)
            && (runtime == nil || sharedRuntimeStore)
            && menu.requiredRoutesPresent
            && menu.threadOSRuntimeActivityCount == 0

        return NativeShellLifecycleDiagnosticResult(
            activationPolicyRegular: NSApp.activationPolicy() == .regular,
            mainWindowSingleton: mainWindowSingleton,
            settingsWindowSingleton: settingsWindowSingleton,
            mainWindowReopened: mainWindowReopened,
            mainWindowStatePreserved: mainWindowStatePreserved,
            settingsNavigationPreserved: settingsNavigationPreserved,
            settingsContentReadyOnFirstShow: settingsContentReadyOnFirstShow,
            windowClosePreservedShell: windowClosePreservedShell,
            statusItemSurvivedWindowClose: statusItemSurvivedWindowClose,
            assistantSurvivedWindowClose: assistantSurvivedWindowClose,
            sharedRuntimeStore: sharedRuntimeStore,
            nativeCommandRoutesPresent: menu.requiredRoutesPresent,
            threadOSRuntimeActivityCount: menu.threadOSRuntimeActivityCount,
            requestedMainWindowCycles: max(0, mainWindowCycleCount),
            completedMainWindowCycles: completedMainWindowCycles,
            requestedSettingsWindowCycles: max(0, settingsWindowCycleCount),
            completedSettingsWindowCycles: completedSettingsWindowCycles,
            requestedAgentSwitches: max(0, agentSwitchCount),
            completedAgentSwitches: completedAgentSwitches,
            passed: passed
        )
    }

    func showMainWindow() {
        guard !isTornDown else { return }
        resumeMonitoringForWindowPresentation()
        mainWindowController.showCanonicalWindow()
        recordMainWindowGeometry()
    }

    func showAgent(_ providerID: ProviderProductID) {
        guard !isTornDown else { return }
        resumeMonitoringForWindowPresentation()
        mainWindowController.showAgent(providerID)
        recordMainWindowGeometry()
    }

    func showMainWindow(destination: MainSurfaceDestination) {
        guard !isTornDown else { return }
        resumeMonitoringForWindowPresentation()
        mainWindowController.showDestination(destination)
        recordMainWindowGeometry()
    }

    func showSettingsWindow() {
        guard !isTornDown else { return }
        resumeMonitoringForWindowPresentation()
        settingsWindowController.showCanonicalWindow()
    }

    private func recordMainWindowGeometry() {
        guard let geometry = mainWindowController.geometryForTesting else { return }
        diagnostics.recordMainWindowGeometry(lifecycleGeneration: lifecycleGeneration, geometry: geometry)
    }

    func showQuickPanel() {
        guard !isTornDown else { return }
        statusBarController.showQuickPanel()
    }

    func refreshAll() async {
        guard let store = runtime?.store, store.allowsManualRefresh else { return }
        await store.refresh()
    }

    func refreshAllProviders() {
        Task { [weak self] in await self?.refreshAll() }
    }

    func scanAllProviders() {
        guard let store = runtime?.store else { return }
        Task { await store.searchForAgents() }
    }

    func connectCodex() {
        guard let store = runtime?.store else { return }
        guard store.currentState == .notAuthorizedByMonitor else {
            store.requestReconnect()
            return
        }
        store.handleLocalAccessDecision(NativeLocalCodexAccessConfirmation.action(for: store).request())
    }

    func disconnectCodex() {
        guard let store = runtime?.store else { return }
        Task { await store.disconnectMonitor() }
    }

    func connectClaude() {
        runtime?.claudeSettings.connectWithConsent()
    }

    func accuracySyncClaude() {
        runtime?.claudeSettings.accuracySync()
    }

    func toggleDesktopAssistant() {
        guard !isTornDown else { return }
        if !assistantController.isEnabled {
            assistantController.setEnabled(true)
            return
        }
        assistantController.toggleVisibility()
    }

    var canRefreshAll: Bool {
        runtime?.store.allowsManualRefresh == true
    }

    var assistantIsEnabled: Bool { assistantController.isEnabled }

    private func observeAssistantCards(in store: UsageStore) {
        assistantStoreObserver = Publishers.CombineLatest3(
            store.$productInventory,
            store.$language,
            store.$agentOrder
        ).sink { [weak self, weak store] _, language, order in
            guard let self, let store else { return }
            self.assistantController.update(
                cards: store.assistantPresentationCards(arrangedBy: order).map {
                    DesktopAssistantCard(shared: $0, language: language)
                }
            )
        }
    }

    private func updateAssistant(using store: UsageStore) {
        assistantController.update(
            cards: store.assistantPresentationCards.map {
                DesktopAssistantCard(shared: $0, language: store.language)
            }
        )
    }

    private func observeAppearance(in preferences: ApplicationPreferences) {
        appearancePreferenceObservation = preferences.observe { [weak self, weak preferences] change in
            guard change.key == UMAApplicationPreferenceKeys.appearance.name,
                  let self,
                  let preferences else { return }
            self.applyAppearance(from: preferences)
        }
    }

    private func observeLifecyclePreference(in preferences: ApplicationPreferences) {
        lifecyclePreferenceObservation = preferences.observe { [weak self] change in
            guard change.key == UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose.name
            else { return }
            self?.reconcileWindowMonitoringPolicy()
        }
    }

    private func applicationWindowDidClose() {
        reconcileWindowMonitoringPolicy()
    }

    private func reconcileWindowMonitoringPolicy() {
        guard let runtime else { return }
        let hasVisibleApplicationWindow = mainWindowController.isVisibleForTesting
            || settingsWindowController.isVisibleForTesting
        if hasVisibleApplicationWindow
            || runtime.preferences.value(
                for: UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose
            ) {
            resumeMonitoringForWindowPresentation()
        } else {
            Task { @MainActor [weak store = runtime.store] in
                await store?.suspendMonitoringForWindowClosure()
            }
        }
    }

    private func resumeMonitoringForWindowPresentation() {
        guard let store = runtime?.store else { return }
        Task { @MainActor [weak store] in
            await store?.resumeMonitoringForWindowPresentation()
        }
    }

    private func applyAppearance(from preferences: ApplicationPreferences) {
        let value = UMAApplicationAppearance(
            rawValue: preferences.value(for: UMAApplicationPreferenceKeys.appearance)
        ) ?? .system
        NSApp.appearance = switch value {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        assistantStoreObserver?.cancel()
        appearancePreferenceObservation?.cancel()
        appearancePreferenceObservation = nil
        lifecyclePreferenceObservation?.cancel()
        lifecyclePreferenceObservation = nil
        for windowCloseObservation in windowCloseObservations {
            NotificationCenter.default.removeObserver(windowCloseObservation)
        }
        windowCloseObservations.removeAll()
        mainWindowController.tearDown()
        settingsWindowController.tearDown()
        assistantController.tearDown()
        statusBarController.tearDown()
        commandRouter.tearDown()
        if Self.activeCoordinator === self {
            Self.activeCoordinator = nil
        }
    }
}
