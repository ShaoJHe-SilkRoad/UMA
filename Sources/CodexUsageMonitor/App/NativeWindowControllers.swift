import AppKit
import CodexUsageUI
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private enum Layout {
        static let defaultFrame = NSRect(x: 0, y: 0, width: 920, height: 640)
        static let minimumSize = NSSize(width: 720, height: 500)
        static let autosaveName = "UMA014.MainWindow"
    }

    private var attachedStore: UsageStore?

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

    func attach(store: UsageStore) {
        guard attachedStore == nil else { return }
        attachedStore = store
        window?.contentViewController = NSHostingController(
            rootView: MainWindowRootView(store: store)
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
        static let defaultFrame = NSRect(x: 0, y: 0, width: 560, height: 390)
        static let minimumSize = NSSize(width: 480, height: 320)
        static let autosaveName = "UMA014.SettingsWindow"
    }

    private var attachedStore: UsageStore?

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

    func attach(store: UsageStore) {
        guard attachedStore == nil else { return }
        attachedStore = store
        window?.contentViewController = NSHostingController(
            rootView: SettingsWindowRootView(store: store)
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
