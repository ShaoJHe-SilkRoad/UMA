import AppKit
import SwiftUI

// MARK: - Unified title bar

/// AUV's windows draw their own bar inside the title bar: the content runs
/// under a transparent title bar, beside the traffic lights, in the window's
/// one colour. An empty compact toolbar sets the bar's height (40 pt on
/// macOS 27) with the traffic lights centred in it; the full unified style
/// is 66 pt there with the lights above centre. Views take the height from
/// the safe area, not from a constant.
@MainActor
public enum AUVWindowChrome {

    public static func unify(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "auv.window.unified-titlebar")
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unifiedCompact
    }
}

/// A window that handles a double-click on its bar itself (the main window
/// toggles its recommended frame), so the drag area leaves that to it.
@MainActor
public protocol AUVTitlebarDoubleClickHandling: AnyObject {}

/// The empty part of a bar drawn into the title bar: it moves the window
/// like the title bar it covers, and a double-click does what the user chose
/// in System Settings (zoom by default), unless the window handles it.
public struct AUVTitlebarDragArea: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> AUVTitlebarDragView { AUVTitlebarDragView() }
    public func updateNSView(_ nsView: AUVTitlebarDragView, context: Context) {}
}

public final class AUVTitlebarDragView: NSView {
    public override var mouseDownCanMoveWindow: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        guard let window else { return super.mouseDown(with: event) }
        if event.clickCount == 2 {
            guard !(window is AUVTitlebarDoubleClickHandling) else { return }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
            return
        }
        window.performDrag(with: event)
    }
}

/// The room the traffic lights need at the bar's leading edge, measured from
/// the window's own zoom button; none in full screen, where they are hidden.
public struct AUVTrafficLightClearance: NSViewRepresentable {
    /// The bar's own leading padding, already outside this view.
    let leadingPadding: CGFloat
    var spacing: CGFloat = 14

    public init(leadingPadding: CGFloat, spacing: CGFloat = 14) {
        self.leadingPadding = leadingPadding
        self.spacing = spacing
    }

    public func makeNSView(context: Context) -> AUVTrafficLightClearanceView {
        AUVTrafficLightClearanceView(leadingPadding: leadingPadding, spacing: spacing)
    }

    public func updateNSView(_ nsView: AUVTrafficLightClearanceView, context: Context) {
        nsView.update()
    }
}

public final class AUVTrafficLightClearanceView: NSView {
    private let leadingPadding: CGFloat
    private let spacing: CGFloat
    private var clearance: CGFloat = 64
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(leadingPadding: CGFloat, spacing: CGFloat) {
        self.leadingPadding = leadingPadding
        self.spacing = spacing
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: clearance, height: NSView.noIntrinsicMetric)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.willEnterFullScreenNotification,
            NSWindow.didResizeNotification,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        update()
    }

    func update() {
        guard let window else { return }
        let next: CGFloat
        if window.styleMask.contains(.fullScreen) {
            next = 0
        } else if let zoom = window.standardWindowButton(.zoomButton), let container = zoom.superview, !zoom.isHidden {
            let frame = container.convert(zoom.frame, to: nil)
            next = max(0, ceil(frame.maxX + spacing - leadingPadding))
        } else {
            next = 64
        }
        guard abs(next - clearance) > 0.5 else { return }
        clearance = next
        invalidateIntrinsicContentSize()
    }
}
