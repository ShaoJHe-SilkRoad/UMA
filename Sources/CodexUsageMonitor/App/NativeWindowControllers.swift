import AppKit
import CodexUsageUI
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private enum Layout {
        static let defaultFrame = NSRect(x: 0, y: 0, width: 840, height: 590)
        static let minimumSize = NSSize(width: 760, height: 520)
        static let autosaveName = "UMA014.MainWindow"
    }

    private var attachedStore: UsageStore?
    private let navigation = MainSurfaceNavigationState()

    init() {
        let window = NSWindow(
            contentRect: Layout.defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "UMA"
        window.minSize = Layout.minimumSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameUsingName(Layout.autosaveName)
        window.setFrameAutosaveName(Layout.autosaveName)
        window.contentViewController = NSHostingController(
            rootView: NativeShellStartingView(title: "UMA")
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func attach(
        store: UsageStore,
        openSettings: @escaping () -> Void,
        scanAll: @escaping () -> Void,
        refreshAll: @escaping () -> Void,
        connectCodex: @escaping () -> Void,
        disconnectCodex: @escaping () -> Void,
        claudeControlState: @escaping () -> ClaudeAgentControlState,
        connectClaude: @escaping () -> Void,
        accuracySyncClaude: @escaping () -> Void
    ) {
        guard attachedStore == nil else { return }
        attachedStore = store
        window?.contentViewController = NSHostingController(
            rootView: MainWindowRootView(
                store: store,
                navigation: navigation,
                openSettings: openSettings,
                scanAll: scanAll,
                refreshAll: refreshAll,
                connectCodex: connectCodex,
                disconnectCodex: disconnectCodex,
                claudeControlState: claudeControlState,
                connectClaude: connectClaude,
                accuracySyncClaude: accuracySyncClaude
            )
        )
    }

    func showAgent(_ providerID: ProviderProductID) {
        navigation.destination = .agents
        navigation.selectedAgent = providerID
        showCanonicalWindow()
    }

    func showDestination(_ destination: MainSurfaceDestination) {
        navigation.destination = destination
        showCanonicalWindow()
    }

    func showCanonicalWindow() {
        guard let window else { return }
        repairFrameIfNeeded(window)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func tearDown() {
        window?.orderOut(nil)
        window?.contentViewController = nil
        close()
    }

    func closeCanonicalWindow() {
        window?.close()
    }

    var windowIdentityForTesting: ObjectIdentifier? {
        window.map(ObjectIdentifier.init)
    }

    var attachedStoreIdentityForTesting: ObjectIdentifier? {
        attachedStore.map(ObjectIdentifier.init)
    }

    var isVisibleForTesting: Bool { window?.isVisible == true }

    var selectedAgentForTesting: ProviderProductID { navigation.selectedAgent }

    var destinationForTesting: MainSurfaceDestination { navigation.destination }

    var hasReadyContentForTesting: Bool {
        attachedStore != nil
            && window?.contentViewController is NSHostingController<MainWindowRootView>
    }

    private func repairFrameIfNeeded(_ window: NSWindow) {
        let intersectsVisibleScreen = NSScreen.screens.contains { screen in
            window.frame.intersection(screen.visibleFrame).width >= 120
                && window.frame.intersection(screen.visibleFrame).height >= 80
        }
        guard !intersectsVisibleScreen else { return }
        window.setFrame(Layout.defaultFrame, display: false)
        window.center()
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private enum Layout {
        static let defaultFrame = NSRect(x: 0, y: 0, width: 640, height: 460)
        static let minimumSize = NSSize(width: 560, height: 400)
        static let autosaveName = "UMA014.SettingsWindow"
    }

    private var attachedStore: UsageStore?
    private var preferences: ApplicationPreferences?
    private let navigation = GlobalSettingsNavigationState()

    init() {
        let window = NSWindow(
            contentRect: Layout.defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "UMA Settings"
        window.minSize = Layout.minimumSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameUsingName(Layout.autosaveName)
        window.setFrameAutosaveName(Layout.autosaveName)
        window.contentViewController = NSHostingController(
            rootView: NativeShellStartingView(title: "Settings")
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func attach(store: UsageStore, preferences: ApplicationPreferences) {
        guard attachedStore == nil else { return }
        attachedStore = store
        self.preferences = preferences
        window?.contentViewController = NSHostingController(
            rootView: SettingsWindowRootView(
                preferences: preferences,
                store: store,
                navigation: navigation
            )
        )
    }

    func showCanonicalWindow() {
        guard let window else { return }
        repairFrameIfNeeded(window)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func tearDown() {
        window?.orderOut(nil)
        window?.contentViewController = nil
        close()
    }

    func closeCanonicalWindow() {
        window?.close()
    }

    var windowIdentityForTesting: ObjectIdentifier? {
        window.map(ObjectIdentifier.init)
    }

    var attachedStoreIdentityForTesting: ObjectIdentifier? {
        attachedStore.map(ObjectIdentifier.init)
    }

    var isVisibleForTesting: Bool { window?.isVisible == true }

    var selectedPaneForTesting: GlobalSettingsPane { navigation.pane }

    var hasReadyContentForTesting: Bool {
        attachedStore != nil
            && preferences != nil
            && window?.contentViewController is NSHostingController<SettingsWindowRootView>
    }

    func selectPaneForTesting(_ pane: GlobalSettingsPane) {
        navigation.pane = pane
    }

    private func repairFrameIfNeeded(_ window: NSWindow) {
        let intersectsVisibleScreen = NSScreen.screens.contains { screen in
            window.frame.intersection(screen.visibleFrame).width >= 120
                && window.frame.intersection(screen.visibleFrame).height >= 80
        }
        guard !intersectsVisibleScreen else { return }
        window.setFrame(Layout.defaultFrame, display: false)
        window.center()
    }
}

struct NativeShellStartingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("\(title) is starting…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
