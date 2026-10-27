import AppKit
import CodexUsageUI
import SwiftUI

enum MainWindowFramePolicy {
    /// The recommended working area.  This is content size, not the frame
    /// reported by AppKit (which also includes title-bar chrome).
    static let normalContentSize = NSSize(width: 1_040, height: 760)
    static let titlebarRecommendedOuterSize = NSSize(width: 1_040, height: 762)
    private static let visibleIntersection = NSSize(width: 120, height: 80)

    static func initialFrame(visibleFrames: [NSRect], outerSize: NSSize) -> NSRect {
        guard let visibleFrame = visibleFrames.first else {
            return NSRect(origin: .zero, size: outerSize)
        }

        let size = NSSize(
            width: min(outerSize.width, visibleFrame.width),
            height: min(outerSize.height, visibleFrame.height)
        )
        return NSRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    static func titlebarToggleFrame(currentFrame: NSRect, visibleFrame: NSRect) -> NSRect {
        let recommended = initialFrame(visibleFrames: [visibleFrame], outerSize: titlebarRecommendedOuterSize)
        return isAppKitRoundedRecommendedFrame(currentFrame, recommended: recommended) ? visibleFrame : recommended
    }

    /// AppKit may round a half-point centered origin to the nearest rendered
    /// window coordinate. Treat only that bounded representation difference as
    /// the recommended frame, so the next titlebar double-click can fill the
    /// usable screen rather than repeating the recommendation.
    private static func isAppKitRoundedRecommendedFrame(_ frame: NSRect, recommended: NSRect) -> Bool {
        let roundingTolerance: CGFloat = 0.5
        return abs(frame.origin.x - recommended.origin.x) <= roundingTolerance
            && abs(frame.origin.y - recommended.origin.y) <= roundingTolerance
            && abs(frame.size.width - recommended.size.width) <= roundingTolerance
            && abs(frame.size.height - recommended.size.height) <= roundingTolerance
    }

    /// Returns nil when the restored frame is already a valid user choice.
    static func repairedFrame(
        for savedFrame: NSRect,
        visibleFrames: [NSRect],
        fallbackOuterSize: NSSize = normalContentSize
    ) -> NSRect? {
        guard !visibleFrames.isEmpty else { return nil }
        guard savedFrame.width > 0, savedFrame.height > 0 else {
            return initialFrame(visibleFrames: visibleFrames, outerSize: fallbackOuterSize)
        }

        let visibleFrame = visibleFrames.max { lhs, rhs in
            intersectionArea(lhs, savedFrame) < intersectionArea(rhs, savedFrame)
        }!
        let intersection = savedFrame.intersection(visibleFrame)
        let hasUsableIntersection = intersection.width >= visibleIntersection.width
            && intersection.height >= visibleIntersection.height
        let titlebar = NSRect(x: savedFrame.minX, y: savedFrame.maxY - 28, width: savedFrame.width, height: 28)
        let hasReachableTitlebar = titlebar.intersection(visibleFrame).width >= visibleIntersection.width
            && titlebar.intersection(visibleFrame).height >= 12
        let isOversized = savedFrame.width > visibleFrame.width * 1.05
            || savedFrame.height > visibleFrame.height * 1.05
        guard !hasUsableIntersection || !hasReachableTitlebar || isOversized else { return nil }

        let size = NSSize(
            width: min(savedFrame.width, visibleFrame.width),
            height: min(savedFrame.height, visibleFrame.height)
        )
        return NSRect(
            x: min(max(savedFrame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(savedFrame.minY, visibleFrame.minY), visibleFrame.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return max(0, intersection.width) * max(0, intersection.height)
    }
}

enum MainWindowTitlebarDoubleClickPolicy {
    static func shouldHandle(
        clickCount: Int,
        isFullScreen: Bool,
        point: NSPoint,
        contentLayoutRect: NSRect,
        excludedControlFrames: [NSRect]
    ) -> Bool {
        clickCount == 2
            && !isFullScreen
            && point.y >= contentLayoutRect.maxY
            && !excludedControlFrames.contains(where: { $0.contains(point) })
    }
}

@MainActor
final class MainWindow: NSWindow {
    var titlebarBackgroundDoubleClick: (() -> Void)?
    var delegatedEventObserver: ((NSEvent) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 48,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let responder = firstResponder as? NSView,
           isPromptRouteControl(responder) {
            if event.modifierFlags.contains(.shift) {
                selectPreviousKeyView(nil)
            } else {
                selectNextKeyView(nil)
            }
            return
        }
        guard event.type == .leftMouseUp,
              event.window === self,
              MainWindowTitlebarDoubleClickPolicy.shouldHandle(
                clickCount: event.clickCount,
                isFullScreen: styleMask.contains(.fullScreen),
                point: event.locationInWindow,
                contentLayoutRect: contentLayoutRect,
                excludedControlFrames: standardWindowButtons.map { $0.convert($0.bounds, to: nil) }
        ) else {
            delegatedEventObserver?(event)
            super.sendEvent(event)
            return
        }
        titlebarBackgroundDoubleClick?()
    }

    private func isPromptRouteControl(_ view: NSView) -> Bool {
        let identifier = view.accessibilityIdentifier()
        guard identifier == "uma.main.navigation" || identifier == "uma.main.settings"
                || identifier.hasPrefix("uma.threados.prompt.role.")
                || identifier == "uma.threados.prompt.generate-copy" else { return false }
        func containsCopy(_ candidate: NSView) -> Bool {
            candidate.accessibilityIdentifier() == "uma.threados.prompt.generate-copy"
                || candidate.subviews.contains(where: containsCopy)
        }
        return contentView.map(containsCopy) ?? false
    }

    private var standardWindowButtons: [NSButton] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
    }
}

struct MainWindowGeometrySnapshot: Equatable {
    let frame: NSRect
    let contentRect: NSRect
    let minimumOuterSize: NSSize
    let isZoomed: Bool
    let isFullScreen: Bool
    let backingScaleFactor: Double
}

@MainActor
final class MainWindowController: NSWindowController {
    private enum Layout {
        static let minimumOuterSize = NSSize(width: 760, height: 520)
        static let autosaveName = "UMA014.MainWindow"
    }

    private var attachedStore: UsageStore?
    private let navigation = MainSurfaceNavigationState()

    init(
        autosaveName: String = Layout.autosaveName,
        restoresSavedFrame: Bool = true
    ) {
        let window = MainWindow(
            contentRect: NSRect(origin: .zero, size: MainWindowFramePolicy.normalContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AUV"
        window.minSize = Layout.minimumOuterSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        let restoredSavedFrame = restoresSavedFrame && window.setFrameUsingName(autosaveName)
        if restoresSavedFrame {
            window.setFrameAutosaveName(autosaveName)
        }
        if !restoredSavedFrame {
            window.setFrame(
                MainWindowFramePolicy.initialFrame(
                    visibleFrames: NSScreen.screens.map(\.visibleFrame),
                    outerSize: window.frameRect(
                        forContentRect: NSRect(
                            origin: .zero,
                            size: MainWindowFramePolicy.normalContentSize
                        )
                    ).size
                ),
                display: false
            )
        }
        // The starting host may negotiate its minimum content size as it is
        // installed. Keep the selected default or restored outer frame intact
        // before the ready host replaces it during attachment.
        let frameBeforeStartingHost = window.frame
        window.contentViewController = NSHostingController(
            rootView: NativeShellStartingView(title: "AUV")
        )
        window.setFrame(frameBeforeStartingHost, display: false)
        super.init(window: window)
        window.titlebarBackgroundDoubleClick = { [weak self, weak window] in
            guard let self, let window else { return }
            self.toggleTitlebarFrame(window)
        }
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
        accuracySyncClaude: @escaping () -> Void,
        hesectoriumStore: HESectoriumStore? = nil,
        promptClipboard: (any ThreadOSSettingsClipboard)? = nil,
        promptPreferences: ApplicationPreferences = .production,
        appStorageDefaults: UserDefaults = .standard,
        claudeSettings: ClaudeBrowserSettingsModel? = nil
    ) {
        guard attachedStore == nil else { return }
        // NSHostingController may negotiate its minimum content size while it
        // is installed. Preserve a restored/user-resized outer frame across
        // that hosting transition rather than letting it collapse to minimum.
        let frameBeforeHosting = window?.frame
        attachedStore = store
        let root = MainWindowRootView(
            store: store,
            navigation: navigation,
            openSettings: openSettings,
            scanAll: scanAll,
            refreshAll: refreshAll,
            connectCodex: connectCodex,
            disconnectCodex: disconnectCodex,
            claudeControlState: claudeControlState,
            connectClaude: connectClaude,
            accuracySyncClaude: accuracySyncClaude,
            hesectoriumStore: hesectoriumStore,
            promptClipboard: promptClipboard,
            promptPreferences: promptPreferences,
            claudeSettings: claudeSettings
        )
        if appStorageDefaults === UserDefaults.standard {
            // Preserve the production hosting type and its existing diagnostics.
            window?.contentViewController = NSHostingController(rootView: root)
        } else {
            window?.contentViewController = NSHostingController(
                rootView: root.defaultAppStorage(appStorageDefaults)
            )
        }
        if let frameBeforeHosting {
            window?.setFrame(frameBeforeHosting, display: false)
        }
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

    var frameForTesting: NSRect? { window?.frame }

    private func toggleTitlebarFrame(_ window: NSWindow) {
        let visibleFrame = window.screen?.visibleFrame ?? window.frame
        window.setFrame(MainWindowFramePolicy.titlebarToggleFrame(currentFrame: window.frame, visibleFrame: visibleFrame), display: true)
    }

    /// Read-only native-window facts for focused lifecycle tests and bounded
    /// diagnostics.  It does not alter frame autosave or user preferences.
    var geometryForTesting: MainWindowGeometrySnapshot? {
        guard let window else { return nil }
        return MainWindowGeometrySnapshot(
            frame: window.frame,
            contentRect: window.contentRect(forFrameRect: window.frame),
            minimumOuterSize: window.minSize,
            isZoomed: window.isZoomed,
            isFullScreen: window.styleMask.contains(.fullScreen),
            backingScaleFactor: window.backingScaleFactor
        )
    }

    private func repairFrameIfNeeded(_ window: NSWindow) {
        guard let repairedFrame = MainWindowFramePolicy.repairedFrame(
            for: window.frame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            fallbackOuterSize: window.frameRect(
                forContentRect: NSRect(
                    origin: .zero,
                    size: MainWindowFramePolicy.normalContentSize
                )
            ).size
        ) else { return }
        window.setFrame(repairedFrame, display: false)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    enum Layout {
        static let defaultFrame = NSRect(x: 0, y: 0, width: 640, height: 460)
        static let minimumSize = NSSize(width: 560, height: 400)
        static let autosaveName = "UMA014.SettingsWindow"
    }

    private var attachedStore: UsageStore?
    private var preferences: ApplicationPreferences?
    private let navigation = GlobalSettingsNavigationState()

    init(autosaveName: String = Layout.autosaveName) {
        let window = NSWindow(
            contentRect: Layout.defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AUV Settings"
        window.minSize = Layout.minimumSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameUsingName(autosaveName)
        window.setFrameAutosaveName(autosaveName)
        // Installing a hosting controller sizes the window to its content,
        // and the autosave name then records that size: the starting view
        // collapsed the window to its minimum, or below it before the window
        // was shown (released builds saved 32 x 76). Keep the frame across
        // it, as the main window does.
        let frameBeforeStartingHost = window.frame
        window.contentViewController = Self.hostingController(
            rootView: NativeShellStartingView(title: "Settings")
        )
        window.setFrame(frameBeforeStartingHost, display: false)
        super.init(window: window)
        // The window controller applies the saved frame once more, without
        // the minimum that `setFrameUsingName` enforces, so this is where an
        // undersized saved frame is corrected; the correction is then saved.
        window.setFrame(
            Self.restorableFrame(
                window.frame,
                minimum: Layout.minimumSize,
                fallback: window.frameRect(forContentRect: Layout.defaultFrame)
            ),
            display: false
        )
    }

    /// A restored frame smaller than the minimum is one the window was
    /// forced into, never one a user chose, since `minSize` stops a user
    /// going smaller. `NSWindowController` restores it as saved, so the
    /// installed 0.17.7 brought back its 32 x 76 frame on every launch. Such a frame is
    /// replaced by the default size, kept at the saved position.
    static func restorableFrame(_ frame: NSRect, minimum: NSSize, fallback: NSRect) -> NSRect {
        guard frame.width < minimum.width || frame.height < minimum.height else { return frame }
        return NSRect(
            x: frame.minX,
            y: frame.maxY - fallback.height,
            width: fallback.width,
            height: fallback.height
        )
    }

    /// The window's size belongs to the user. Without this the hosting
    /// controller resized it to each pane's ideal size, so opening Privacy &
    /// Data grew the window from 640 x 460 to 1055 x 576, and it stayed.
    private static func hostingController<Content: View>(
        rootView: Content
    ) -> NSHostingController<Content> {
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = []
        return controller
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func attach(
        store: UsageStore,
        preferences: ApplicationPreferences,
        dataPaths: ApplicationDataPaths = .current()
    ) {
        guard attachedStore == nil else { return }
        attachedStore = store
        self.preferences = preferences
        let frameBeforeHosting = window?.frame
        window?.contentViewController = Self.hostingController(
            rootView: SettingsWindowRootView(
                preferences: preferences,
                store: store,
                navigation: navigation,
                dataPaths: dataPaths
            )
        )
        if let frameBeforeHosting {
            window?.setFrame(frameBeforeHosting, display: false)
        }
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
