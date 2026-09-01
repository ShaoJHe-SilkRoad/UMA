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
    let windowClosePreservedShell: Bool
    let statusItemSurvivedWindowClose: Bool
    let assistantSurvivedWindowClose: Bool
    let sharedRuntimeStore: Bool
    let nativeCommandRoutesPresent: Bool
    let threadOSRuntimeActivityCount: Int
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
        let assistantController = DesktopAssistantPanelController(
            onSelectProvider: { [weak statusBarController] providerID in
                statusBarController?.showQuickPanel(expandingProviderID: providerID)
            }
        )
        self.statusBarController = statusBarController
        self.assistantController = assistantController
        mainWindowController = MainWindowController()
        settingsWindowController = SettingsWindowController()
        Self.activeCoordinator = self
        statusBarController.bindAssistant(assistantController)
        commandRouter = ApplicationMenuController(coordinator: self)
        statusBarController.recordShellCreated()
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
        statusBarController.attach(runtime: runtime)
        mainWindowController.attach(store: runtime.store)
        settingsWindowController.attach(store: runtime.store)
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
        let nativeShell = runNativeLifecycleDiagnostic()
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

    func runNativeLifecycleDiagnostic() -> NativeShellLifecycleDiagnosticResult {
        let coordinatorIdentity = ObjectIdentifier(self)
        let statusIdentity = ObjectIdentifier(statusBarController)
        let assistantIdentity = ObjectIdentifier(assistantController)
        let runtimeStoreIdentity = runtime.map { ObjectIdentifier($0.store) }

        showMainWindow()
        let mainWindowIdentity = mainWindowController.windowIdentityForTesting
        showMainWindow()
        let mainWindowSingleton = mainWindowController.windowIdentityForTesting == mainWindowIdentity

        showSettingsWindow()
        let settingsWindowIdentity = settingsWindowController.windowIdentityForTesting
        showSettingsWindow()
        let settingsWindowSingleton =
            settingsWindowController.windowIdentityForTesting == settingsWindowIdentity

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
            && windowClosePreservedShell
            && statusItemSurvivedWindowClose
            && assistantSurvivedWindowClose
            && (runtime == nil || sharedRuntimeStore)
            && menu.requiredRoutesPresent
            && menu.threadOSRuntimeActivityCount == 0

        return NativeShellLifecycleDiagnosticResult(
            activationPolicyRegular: NSApp.activationPolicy() == .regular,
            mainWindowSingleton: mainWindowSingleton,
            settingsWindowSingleton: settingsWindowSingleton,
            mainWindowReopened: mainWindowReopened,
            windowClosePreservedShell: windowClosePreservedShell,
            statusItemSurvivedWindowClose: statusItemSurvivedWindowClose,
            assistantSurvivedWindowClose: assistantSurvivedWindowClose,
            sharedRuntimeStore: sharedRuntimeStore,
            nativeCommandRoutesPresent: menu.requiredRoutesPresent,
            threadOSRuntimeActivityCount: menu.threadOSRuntimeActivityCount,
            passed: passed
        )
    }

    func showMainWindow() {
        guard !isTornDown else { return }
        mainWindowController.showCanonicalWindow()
    }

    func showSettingsWindow() {
        guard !isTornDown else { return }
        settingsWindowController.showCanonicalWindow()
    }

    func showQuickPanel() {
        guard !isTornDown else { return }
        statusBarController.showQuickPanel()
    }

    func refreshAll() async {
        guard let store = runtime?.store, store.allowsManualRefresh else { return }
        await store.refresh()
    }

    func toggleDesktopAssistant() {
        guard !isTornDown else { return }
        assistantController.toggleVisibility()
    }

    var canRefreshAll: Bool {
        runtime?.store.allowsManualRefresh == true
    }

    var assistantIsEnabled: Bool { assistantController.isEnabled }

    private func observeAssistantCards(in store: UsageStore) {
        assistantStoreObserver = Publishers.CombineLatest(
            store.$productInventory,
            store.$language
        ).sink { [weak self, weak store] _, language in
            guard let self, let store else { return }
            self.assistantController.update(
                cards: store.assistantPresentationCards.map {
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

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        assistantStoreObserver?.cancel()
        runtime?.workBuddyLogin.tearDown()
        runtime?.workBuddyAccountWebSync.tearDown()
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
