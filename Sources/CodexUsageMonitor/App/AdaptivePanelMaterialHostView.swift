@preconcurrency import AppKit

/// Owns the Quick Panel's only visible backing surface. The layer-backed host
/// clips one clear, exact-bounds content view; it deliberately uses no
/// backdrop material, contour, or shadow outside those rounded bounds.
final class AdaptivePanelMaterialHostView: NSView {
    struct DiagnosticSnapshot: Equatable {
        let subviewCount: Int
        let contentFrameMatchesBounds: Bool
        let cornerRadius: CGFloat
        let usesContinuousCorners: Bool
        let masksToBounds: Bool
        let borderWidth: CGFloat
        let shadowOpacity: Float
        let hasBackground: Bool
    }

    private let cornerRadius: CGFloat
    private weak var hostedContentView: NSView?
    private var displayOptionsObserver: NSObjectProtocol?

    init(frame frameRect: NSRect, cornerRadius: CGFloat, fallbackMaterialOpacity: Double) {
        self.cornerRadius = cornerRadius
        super.init(frame: frameRect)
        _ = fallbackMaterialOpacity

        wantsLayer = true
        configureSurface()
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDynamicBackground()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
    }

    func installContentView(_ contentView: NSView) {
        subviews.forEach { view in
            if view !== contentView { view.removeFromSuperview() }
        }
        hostedContentView = contentView
        prepareContentView(contentView)
        if contentView.superview !== self {
            contentView.removeFromSuperview()
            addSubview(contentView)
        }
        configureSurface()
    }

    var diagnosticSnapshot: DiagnosticSnapshot {
        DiagnosticSnapshot(
            subviewCount: subviews.count,
            contentFrameMatchesBounds: hostedContentView?.frame == bounds,
            cornerRadius: layer?.cornerRadius ?? 0,
            usesContinuousCorners: layer?.cornerCurve == .continuous,
            masksToBounds: layer?.masksToBounds ?? false,
            borderWidth: layer?.borderWidth ?? 0,
            shadowOpacity: layer?.shadowOpacity ?? 0,
            hasBackground: layer?.backgroundColor != nil
        )
    }

    override func layout() {
        super.layout()
        hostedContentView?.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDynamicBackground()
    }

    private func configureSurface() {
        guard let layer else { return }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 0
        layer.borderColor = nil
        layer.shadowOpacity = 0
        layer.shadowColor = nil
        layer.shadowPath = nil
        updateDynamicBackground()
    }

    private func updateDynamicBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            guard let self else { return }
            if self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            } else {
                // Darken the existing opaque surface, never add an outer layer.
                self.layer?.backgroundColor = NSColor.windowBackgroundColor
                    .blended(withFraction: 0.07, of: .black)?.cgColor
            }
        }
    }

    private func prepareContentView(_ contentView: NSView) {
        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
