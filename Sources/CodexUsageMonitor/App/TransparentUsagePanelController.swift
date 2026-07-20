import AppKit
import CodexUsageUI
import SwiftUI

private final class TransparentUsagePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum UsagePanelFrameGeometry {
    static func clampedHeight(_ proposedHeight: CGFloat) -> CGFloat {
        min(
            UsagePanelMetrics.height,
            max(UsagePanelMetrics.minimumHeight, proposedHeight.rounded())
        )
    }

    static func targetFrame(
        from currentFrame: NSRect,
        height: CGFloat,
        visibleTopEdge: CGFloat?,
        visibleFrame: NSRect? = nil,
        screenMargin: CGFloat = 0
    ) -> NSRect {
        var frame = currentFrame
        frame.size.height = clampedHeight(height)
        if let visibleTopEdge {
            frame.origin.y = visibleTopEdge - frame.height
        }
        if let visibleFrame {
            let boundedFrame = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
            frame.size.height = min(frame.height, boundedFrame.height)
            frame.origin.y = min(
                boundedFrame.maxY - frame.height,
                max(boundedFrame.minY, frame.origin.y)
            )
        }
        return frame
    }
}

@MainActor
final class TransparentUsagePanelController {
    private enum Layout {
        static let width = UsagePanelMetrics.width
        static let height = UsagePanelMetrics.height
        static let cornerRadius: CGFloat = 28
        static let statusBarGap: CGFloat = 8
        static let screenMargin: CGFloat = 8
    }

    private let panel: TransparentUsagePanel
    private let tuning: GlassTuning
    private weak var statusItem: NSStatusItem?
    private let visibilityDidChange: (Bool) -> Void
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var frameAnimationGeneration: UInt = 0
    private var visibleTopEdge: CGFloat?
    private var pendingResizeHeight: CGFloat?
    private var resizeIsScheduled = false

    init(
        store: UsageStore,
        statusItem: NSStatusItem,
        visibilityDidChange: @escaping (Bool) -> Void
    ) {
        self.statusItem = statusItem
        self.visibilityDidChange = visibilityDidChange
        tuning = .final
        panel = TransparentUsagePanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel(store: store)
    }

    func toggle() {
        panel.isVisible ? close() : show()
    }

    func tearDown() {
        pendingResizeHeight = nil
        resizeIsScheduled = false
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

    private func configurePanel(store: UsageStore) {
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The macOS 26 glass host owns the exterior rim. AppKit's panel
        // shadow would create a second perimeter and can briefly retain stale
        // geometry while the disclosure animation resizes the window.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        let rootView = AdaptivePanelMaterialHostView(
            frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            cornerRadius: Layout.cornerRadius,
            // Keep the exact established macOS 14–25 material intensity
            // without coupling the frozen panel geometry to M1-G3 tuning WIP.
            fallbackMaterialOpacity: 0.44
        )

        let hostingView = NSHostingView(
            rootView: UsagePanelView(
                store: store,
                tuning: tuning,
                onHeightChange: { [weak self] height in
                    self?.resizePanel(to: height)
                },
                localAccessConfirmationAction: NativeLocalCodexAccessConfirmation.action(for: store)
            )
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        rootView.installContentView(hostingView)
        panel.hasShadow = UsagePanelExteriorContract.windowShadowEnabled(
            materialOwnsExteriorContour: rootView.ownsExteriorContour
        )
        panel.contentView = rootView
    }

    private func resizePanel(to height: CGFloat) {
        pendingResizeHeight = height
        guard !resizeIsScheduled else { return }
        resizeIsScheduled = true
        // SwiftUI reports its first semantic height while NSHostingView may
        // still be inside a layout pass. Defer and coalesce frame work onto
        // the next main-loop turn so AppKit never lays the host out reentrantly.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeIsScheduled = false
            guard let height = self.pendingResizeHeight else { return }
            self.pendingResizeHeight = nil
            self.applyResizePanel(to: height)
        }
    }

    private func applyResizePanel(to height: CGFloat) {
        let targetFrame = UsagePanelFrameGeometry.targetFrame(
            from: panel.frame,
            height: height,
            visibleTopEdge: panel.isVisible ? visibleTopEdge ?? panel.frame.maxY : nil,
            visibleFrame: panel.isVisible ? panel.screen?.visibleFrame : nil,
            screenMargin: Layout.screenMargin
        )
        guard
            abs(panel.frame.height - targetFrame.height) > 0.5
                || abs(panel.frame.minY - targetFrame.minY) > 0.5
        else { return }

        if panel.isVisible, visibleTopEdge == nil {
            visibleTopEdge = panel.frame.maxY
        }
        replaceFrameAnimation(with: targetFrame)
    }

    private func replaceFrameAnimation(with targetFrame: NSRect) {
        frameAnimationGeneration &+= 1
        let generation = frameAnimationGeneration
        let shouldAnimate = panel.isVisible
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        guard shouldAnimate else {
            // A zero-duration animator assignment replaces any in-flight frame
            // animation and applies the final geometry immediately.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().setFrame(targetFrame, display: panel.isVisible)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.frameAnimationGeneration == generation else { return }
                    self.panel.invalidateShadow()
                }
            }
            return
        }

        // NSAnimatablePropertyContainer replaces the existing frame animation
        // from its current presentation value when the same property receives
        // a new target. The generation prevents an obsolete completion from
        // finalizing geometry or invalidating the shadow.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.frameAnimationGeneration == generation else { return }
                self.panel.setFrame(targetFrame, display: true)
                self.panel.invalidateShadow()
            }
        }
    }

    private func show() {
        positionPanel()
        visibleTopEdge = panel.frame.maxY
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        visibilityDidChange(true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.installEventMonitors()
        }
    }

    private func close() {
        frameAnimationGeneration &+= 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().setFrame(panel.frame, display: false)
        }
        visibleTopEdge = nil
        if panel.isVisible {
            panel.orderOut(nil)
            visibilityDidChange(false)
        }
        removeEventMonitors()
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
