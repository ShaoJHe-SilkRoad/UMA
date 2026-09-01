import AppKit
import CodexUsageUI
import SwiftUI

private final class TransparentUsagePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct UsagePanelNavigationRequest: Equatable {
    let expandedProviderIDs: Set<String>
    let settingsInitiallyPresented: Bool
    let requestsRefresh: Bool

    static func assistantSelection(providerID: String) -> Self {
        Self(
            expandedProviderIDs: [providerID],
            settingsInitiallyPresented: false,
            requestsRefresh: false
        )
    }
}

@MainActor
final class TransparentUsagePanelController {
    struct DiagnosticState: Equatable {
        let isVisible: Bool
        let isEffectivelyOpen: Bool
        let isResponsive: Bool
        let eventMonitorCount: Int
        let level: Int
        let alpha: Double
        let frame: String
        let ignoresMouseEvents: Bool
    }

    private enum Layout {
        static let width = UsagePanelMetrics.width
        static let initialHeight = UsagePanelMetrics.minimumHeight
        static let cornerRadius: CGFloat = 28
        static let statusBarGap: CGFloat = 8
        static let screenMargin: CGFloat = 8
    }

    private let panel: TransparentUsagePanel
    private let tuning: GlassTuning
    private weak var statusItem: NSStatusItem?
    private let visibilityDidChange: (Bool) -> Void
    private let navigation = UsagePanelNavigationCoordinator()
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var diagnosticEvent: ((AppShellDiagnosticStage, Bool, String?) -> Void)?
    private var hasAttachedContent = false
    private weak var placeholderLabel: NSTextField?

    var diagnosticState: DiagnosticState {
        DiagnosticState(
            isVisible: panel.isVisible,
            isEffectivelyOpen: isEffectivelyOpen,
            isResponsive: panel.contentView?.hitTest(
                NSPoint(x: panel.contentView?.bounds.midX ?? 0, y: panel.contentView?.bounds.midY ?? 0)
            ) != nil,
            eventMonitorCount: [globalEventMonitor, localEventMonitor].compactMap { $0 }.count,
            level: Int(panel.level.rawValue),
            alpha: panel.alphaValue,
            frame: NSStringFromRect(panel.frame),
            ignoresMouseEvents: panel.ignoresMouseEvents
        )
    }

    init(
        statusItem: NSStatusItem,
        visibilityDidChange: @escaping (Bool) -> Void
    ) {
        self.statusItem = statusItem
        self.visibilityDidChange = visibilityDidChange
        tuning = .final
        panel = TransparentUsagePanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Layout.width,
                height: Layout.initialHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanelShell()
    }

    func attachContent(
        store: UsageStore,
        claudeSettings: ClaudeBrowserSettingsModel,
        antigravitySettings: AntigravitySettingsModel,
        workBuddySettings: WorkBuddySettingsModel,
        workBuddyLogin: WorkBuddyLoginCoordinator,
        workBuddyAccountWebSync: WorkBuddyAccountWebSessionController
    ) {
        guard !hasAttachedContent else { return }
        hasAttachedContent = true
        configurePanel(
            store: store,
            claudeSettings: claudeSettings,
            antigravitySettings: antigravitySettings,
            workBuddySettings: workBuddySettings,
            workBuddyLogin: workBuddyLogin,
            workBuddyAccountWebSync: workBuddyAccountWebSync,
            expandedProviderIDs: []
        )
    }

    func toggle() {
        diagnosticEvent?(.panelControllerExists, true, nil)
        diagnosticEvent?(.panelWindowExists, true, nil)
        isEffectivelyOpen ? close() : show()
    }

    func present() {
        show()
    }

    func setDiagnosticEventHandler(
        _ handler: @escaping (AppShellDiagnosticStage, Bool, String?) -> Void
    ) {
        diagnosticEvent = handler
    }

    func show(expandingProviderID providerID: String) {
        let request = UsagePanelNavigationRequest.assistantSelection(
            providerID: providerID
        )
        for expandedProviderID in request.expandedProviderIDs {
            navigation.selectProvider(expandedProviderID)
        }
        show()
    }

    func tearDown() {
        close()
        removeEventMonitors()
    }

    private func removeEventMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        globalEventMonitor = nil
        localEventMonitor = nil
    }

    private func configurePanel(
        store: UsageStore,
        claudeSettings: ClaudeBrowserSettingsModel,
        antigravitySettings: AntigravitySettingsModel,
        workBuddySettings: WorkBuddySettingsModel,
        workBuddyLogin: WorkBuddyLoginCoordinator,
        workBuddyAccountWebSync: WorkBuddyAccountWebSessionController,
        expandedProviderIDs: Set<String>
    ) {
        let rootView = AdaptivePanelMaterialHostView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: Layout.width,
                height: Layout.initialHeight
            ),
            cornerRadius: Layout.cornerRadius,
            // Keep the exact established macOS 14–25 material intensity
            // without coupling the frozen panel geometry to M1-G3 tuning WIP.
            fallbackMaterialOpacity: 0.44
        )

        let panelView = UsagePanelView(
                store: store,
                tuning: tuning,
                expandedProviderIDs: expandedProviderIDs,
                navigation: navigation,
                onHeightChange: { [weak self] height in
                    DispatchQueue.main.async { [weak self] in
                        self?.resizePanel(to: height)
                    }
                },
                localAccessConfirmationAction: NativeLocalCodexAccessConfirmation.action(for: store),
                claudeSettings: claudeSettings,
                antigravitySettings: antigravitySettings,
                workBuddySettings: workBuddySettings,
                workBuddyLogin: workBuddyLogin,
                workBuddyAccountWebSync: workBuddyAccountWebSync
            )
            .usagePanelOuterContourOwnedByNativeHost()
        let hostingView = NSHostingView(
            rootView: panelView
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: Layout.width,
            height: Layout.initialHeight
        )
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        rootView.installContentView(hostingView)
        panel.contentView = rootView
    }

    func markRuntimeAttachmentFailed() {
        placeholderLabel?.stringValue = "UMA shell ready — usage data unavailable"
    }

    private func configurePanelShell() {
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        let placeholder = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.initialHeight)
        )
        placeholder.material = .popover
        placeholder.blendingMode = .behindWindow
        placeholder.state = .active
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = Layout.cornerRadius
        let label = NSTextField(labelWithString: "UMA is starting…")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(
            x: 24,
            y: (Layout.initialHeight - 24) / 2,
            width: Layout.width - 48,
            height: 24
        )
        label.autoresizingMask = [.minYMargin, .maxYMargin, .width]
        placeholder.addSubview(label)
        placeholderLabel = label
        panel.contentView = placeholder
    }

    private func resizePanel(to height: CGFloat) {
        let height = min(
            UsagePanelMetrics.height,
            max(UsagePanelMetrics.minimumHeight, height.rounded())
        )
        guard abs(panel.frame.height - height) > 0.5 else { return }

        var frame = panel.frame
        if panel.isVisible {
            frame.origin.y += frame.height - height
        }
        frame.size.height = height
        panel.setFrame(
            frame,
            display: panel.isVisible,
            animate: panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        panel.invalidateShadow()
    }

    private func show() {
        // Converge from any stale/invisible-open window state before ordering.
        NSApp.unhide(nil)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        if !panel.isVisible { panel.orderFrontRegardless() }
        panel.invalidateShadow()
        diagnosticEvent?(.panelWindowOrderedFront, panel.isVisible, nil)
        diagnosticEvent?(.panelWindowKeyState, panel.isKeyWindow, nil)
        diagnosticEvent?(.panelVisible, panel.isVisible, nil)
        diagnosticEvent?(
            .hitTestingEnabled,
            !panel.ignoresMouseEvents && panel.alphaValue > 0.01,
            nil
        )
        visibilityDidChange(true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.installEventMonitors()
        }
    }

    private func close() {
        if panel.isVisible {
            panel.orderOut(nil)
            visibilityDidChange(false)
        }
        removeEventMonitors()
        diagnosticEvent?(.panelClosed, !panel.isVisible, nil)
    }

    private var isEffectivelyOpen: Bool {
        guard panel.isVisible,
              panel.alphaValue > 0.01,
              !panel.ignoresMouseEvents,
              panel.frame.width > 1,
              panel.frame.height > 1 else { return false }
        return NSScreen.screens.contains { screen in
            screen.frame.intersects(panel.frame)
        }
    }

    private func positionPanel() {
        guard
            let button = statusItem?.button,
            let buttonWindow = button.window
        else { return }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
        let screen = buttonWindow.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        var x = buttonFrameOnScreen.midX - Layout.width / 2
        x = max(visibleFrame.minX + Layout.screenMargin, x)
        x = min(visibleFrame.maxX - Layout.width - Layout.screenMargin, x)

        var y = buttonFrameOnScreen.minY - panel.frame.height - Layout.statusBarGap
        if y < visibleFrame.minY + Layout.screenMargin {
            y = buttonFrameOnScreen.maxY + Layout.statusBarGap
        }
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private func installEventMonitors() {
        guard globalEventMonitor == nil, localEventMonitor == nil else { return }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.close()
                return nil
            }
            if event.window !== self.panel, event.window !== self.statusItem?.button?.window {
                self.close()
            }
            return event
        }
    }
}
