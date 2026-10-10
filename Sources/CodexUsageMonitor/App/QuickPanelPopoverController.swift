import AppKit
import CodexUsageUI
import Combine
import SwiftUI

struct QuickPanelActions {
    let openMain: () -> Void
    let scanAll: () -> Void
    let refreshAll: () -> Void
    let toggleWizard: () -> Void
    let openSettings: () -> Void
    let selectAgent: (ProviderProductID) -> Void
}

/// Owns the Quick Panel's single transient AppKit surface. The window is only
/// a clear presentation shell: AdaptivePanelMaterialHostView exclusively owns
/// the rounded backing and clipping. The panel deliberately adds no material,
/// second rim, or shadow outside that exact-bounds layer-backed surface.
@MainActor
final class QuickPanelPopoverController: NSObject, NSWindowDelegate {
    static let contentWidth: CGFloat = 320
    static let minimumContentHeight: CGFloat = 72
    static let maximumContentHeight: CGFloat = 640

    struct DiagnosticState: Equatable {
        let isVisible: Bool
        let isEffectivelyOpen: Bool
        let isResponsive: Bool
        let eventMonitorCount: Int
        let level: Int
        let alpha: Double
        let frame: String
        let ignoresMouseEvents: Bool
        let contentSize: NSSize
        let usesSingleSurfacePanel: Bool
        let anchorAttachedToWindow: Bool
        let anchorWindowVisible: Bool
        let anchorBounds: NSRect
    }

    private static let cornerRadius: CGFloat = 14
    private static let anchorSpacing: CGFloat = 6

    private let panel = QuickPanelWindow()
    private let materialHost = AdaptivePanelMaterialHostView(
        frame: NSRect(x: 0, y: 0, width: contentWidth, height: minimumContentHeight),
        cornerRadius: cornerRadius,
        fallbackMaterialOpacity: 0.92
    )
    private weak var statusItem: NSStatusItem?
    private let visibilityDidChange: (Bool) -> Void
    private var diagnosticEvent: ((AppShellDiagnosticStage, Bool, String?) -> Void)?
    private var hostedContentView: NSView?
    private var contentObserver: AnyCancellable?
    private var displayPreferenceObservation: ApplicationPreferences.Observation?
    private var hasAttachedContent = false
    private var isClosing = false
    private var expectedDiagnosticVisibility: Bool?
    private var diagnosticTransitionContinuation: CheckedContinuation<Bool, Never>?
    private var diagnosticTransitionTimer: Timer?

    init(statusItem: NSStatusItem, visibilityDidChange: @escaping (Bool) -> Void) {
        self.statusItem = statusItem
        self.visibilityDidChange = visibilityDidChange
        super.init()
        configurePanel()
        installContent(
            Text("AUV is starting…")
                .frame(width: Self.contentWidth, height: Self.minimumContentHeight)
        )
    }

    var diagnosticState: DiagnosticState {
        let contentSize = panel.contentView?.bounds.size ?? .zero
        let hitPoint = NSPoint(x: contentSize.width / 2, y: contentSize.height / 2)
        return DiagnosticState(
            isVisible: panel.isVisible,
            isEffectivelyOpen: panel.isVisible && panel.contentView?.window === panel,
            isResponsive: panel.isVisible
                && panel.ignoresMouseEvents == false
                && panel.contentView?.hitTest(hitPoint) != nil,
            eventMonitorCount: 0,
            level: Int(panel.level.rawValue),
            alpha: Double(panel.alphaValue),
            frame: NSStringFromRect(panel.frame),
            ignoresMouseEvents: panel.ignoresMouseEvents,
            contentSize: contentSize,
            usesSingleSurfacePanel: panel.styleMask.contains(.borderless)
                && panel.contentView === materialHost
                && panel.isOpaque == false
                && panel.backgroundColor == .clear
                && panel.hasShadow == false,
            anchorAttachedToWindow: statusItem?.button?.window != nil,
            anchorWindowVisible: statusItem?.button?.window?.isVisible == true,
            anchorBounds: statusItem?.button?.bounds ?? .zero
        )
    }

    func attachContent(
        store: UsageStore,
        preferences: ApplicationPreferences,
        actions: QuickPanelActions
    ) {
        guard !hasAttachedContent else { return }
        hasAttachedContent = true
        installContent(
            QuickPanelSurface(
                store: store,
                preferences: preferences,
                openMain: { [weak self] in
                    self?.close()
                    actions.openMain()
                },
                scanAll: actions.scanAll,
                refreshAll: actions.refreshAll,
                toggleWizard: actions.toggleWizard,
                openSettings: { [weak self] in
                    self?.close()
                    actions.openSettings()
                },
                selectAgent: { [weak self] providerID in
                    self?.close()
                    actions.selectAgent(providerID)
                }
            )
        )
        contentObserver = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.updateContentSize(repositionIfVisible: true)
            }
        }
        displayPreferenceObservation = preferences.observe { [weak self] change in
            guard change.key == UMAApplicationPreferenceKeys.quickPanelShowsReset.name else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.updateContentSize(repositionIfVisible: true)
            }
        }
    }

    func toggle() { panel.isVisible ? close() : present() }

    func present() {
        guard let button = statusItem?.button, button.window != nil else { return }
        guard !panel.isVisible else { return }
        updateContentSize(repositionIfVisible: false)
        positionPanel(relativeTo: button)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        visibilityDidChange(true)
        let state = diagnosticState
        diagnosticEvent?(.panelControllerExists, true, "singleSurfaceNSPanel")
        diagnosticEvent?(.panelWindowExists, state.isEffectivelyOpen, nil)
        diagnosticEvent?(.panelWindowOrderedFront, panel.isVisible, "singleSurfaceNSPanel")
        diagnosticEvent?(.panelWindowKeyState, panel.isKeyWindow, nil)
        diagnosticEvent?(.hitTestingEnabled, state.isResponsive, nil)
        diagnosticEvent?(.panelVisible, state.isVisible, nil)
        completeDiagnosticTransition(state.isEffectivelyOpen && state.isResponsive)
    }

    func show(selecting _: ProviderProductID? = nil) { present() }

    func close() {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        panel.orderOut(nil)
        isClosing = false
        visibilityDidChange(false)
        diagnosticEvent?(.panelClosed, !panel.isVisible, "singleSurfaceNSPanel")
        completeDiagnosticTransition(!panel.isVisible)
    }

    func tearDown() {
        completeDiagnosticTransition(false)
        contentObserver?.cancel()
        contentObserver = nil
        displayPreferenceObservation?.cancel()
        displayPreferenceObservation = nil
        close()
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        hostedContentView = nil
    }

    func markRuntimeAttachmentFailed() {
        installContent(
            Text("AUV could not start its shared runtime.")
                .foregroundStyle(.secondary)
                .frame(width: Self.contentWidth, height: Self.minimumContentHeight)
        )
    }

    func setDiagnosticEventHandler(_ handler: @escaping (AppShellDiagnosticStage, Bool, String?) -> Void) {
        diagnosticEvent = handler
    }

    func performDiagnosticTransition(
        expecting expectedVisibility: Bool,
        action: () -> Bool
    ) async -> Bool {
        guard diagnosticTransitionContinuation == nil else { return false }
        return await withCheckedContinuation { continuation in
            expectedDiagnosticVisibility = expectedVisibility
            diagnosticTransitionContinuation = continuation
            diagnosticTransitionTimer = Timer.scheduledTimer(
                timeInterval: 2,
                target: self,
                selector: #selector(diagnosticTransitionTimedOut),
                userInfo: nil,
                repeats: false
            )
            if !action() {
                completeDiagnosticTransition(false)
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        // Defer one run-loop turn so a click on the status item can execute its
        // normal toggle first. A genuine outside click leaves the panel visible
        // but non-key and is then dismissed without a global event monitor.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.close()
        }
    }

    @objc
    private func diagnosticTransitionTimedOut() {
        completeDiagnosticTransition(false)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.closeHandler = { [weak self] in self?.close() }
        materialHost.autoresizingMask = [.width, .height]
        panel.contentView = materialHost
    }

    private func installContent<Content: View>(_ content: Content) {
        let view = NSHostingView(rootView: content)
        view.frame = NSRect(
            x: 0,
            y: 0,
            width: Self.contentWidth,
            height: Self.minimumContentHeight
        )
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        hostedContentView = view
        materialHost.installContentView(view)
        updateContentSize(repositionIfVisible: true)
    }

    private func updateContentSize(repositionIfVisible: Bool) {
        guard let view = hostedContentView else { return }
        view.layoutSubtreeIfNeeded()
        let measuredHeight = view.fittingSize.height
        let finiteHeight = measuredHeight.isFinite ? measuredHeight : Self.minimumContentHeight
        let size = NSSize(
            width: Self.contentWidth,
            height: min(
                Self.maximumContentHeight,
                max(Self.minimumContentHeight, finiteHeight)
            )
        )
        guard panel.contentView?.frame.size != size else { return }
        panel.setContentSize(size)
        materialHost.frame = NSRect(origin: .zero, size: size)
        view.frame = materialHost.bounds
        if repositionIfVisible, panel.isVisible, let button = statusItem?.button {
            positionPanel(relativeTo: button)
        }
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let anchorWindow = button.window else { return }
        let anchorFrame = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = anchorWindow.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? anchorFrame
        let panelSize = panel.frame.size
        var origin = NSPoint(
            x: anchorFrame.midX - panelSize.width / 2,
            y: anchorFrame.minY - panelSize.height - Self.anchorSpacing
        )
        if origin.y < screenFrame.minY {
            origin.y = anchorFrame.maxY + Self.anchorSpacing
        }
        origin.x = min(
            max(origin.x, screenFrame.minX + Self.anchorSpacing),
            screenFrame.maxX - panelSize.width - Self.anchorSpacing
        )
        panel.setFrameOrigin(origin)
    }

    private func completeDiagnosticTransition(_ succeeded: Bool) {
        guard diagnosticTransitionContinuation != nil else { return }
        let matchesExpectation = expectedDiagnosticVisibility.map {
            $0 ? panel.isVisible : !panel.isVisible
        } ?? false
        diagnosticTransitionTimer?.invalidate()
        diagnosticTransitionTimer = nil
        expectedDiagnosticVisibility = nil
        let continuation = diagnosticTransitionContinuation
        diagnosticTransitionContinuation = nil
        continuation?.resume(returning: succeeded && matchesExpectation)
    }
}

@MainActor
private final class QuickPanelWindow: NSPanel {
    var closeHandler: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: QuickPanelPopoverController.contentWidth,
                height: QuickPanelPopoverController.minimumContentHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        closeHandler?()
    }
}
