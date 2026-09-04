@preconcurrency import AppKit

/// Hosts exactly one panel material with one branch-specific contour owner.
/// Native glass owns both the clip and contour on macOS 26, while the host owns
/// both on earlier or reduced-transparency appearances.
final class AdaptivePanelMaterialHostView: NSView {
    private let cornerRadius: CGFloat
    private let fallbackMaterialOpacity: CGFloat
    private weak var hostedContentView: NSView?
    private var displayOptionsObserver: NSObjectProtocol?

    init(frame frameRect: NSRect, cornerRadius: CGFloat, fallbackMaterialOpacity: Double) {
        self.cornerRadius = cornerRadius
        self.fallbackMaterialOpacity = fallbackMaterialOpacity
        super.init(frame: frameRect)

        wantsLayer = true
        configureTransparentGeometryCarrier()
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildMaterial()
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
        hostedContentView = contentView
        rebuildMaterial()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuildMaterial()
    }

    private func rebuildMaterial() {
        guard let contentView = hostedContentView else { return }
        contentView.removeFromSuperview()
        subviews.forEach { $0.removeFromSuperview() }
        configureTransparentGeometryCarrier()

        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            configureFallbackContour()
            installOpaqueBackground(contentView)
            return
        }
        if #available(macOS 26.0, *) {
            installNativeGlass(contentView)
        } else {
            configureFallbackContour()
            installFallbackMaterial(contentView)
        }
    }

    private func configureTransparentGeometryCarrier() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil
        layer?.cornerRadius = 0
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
    }

    private func configureFallbackContour() {
        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = increasedContrast ? 1.4 : 0.8
        layer?.borderColor = NSColor.separatorColor
            .withAlphaComponent(increasedContrast ? 0.72 : 0.34)
            .cgColor
    }

    private func installOpaqueBackground(_ contentView: NSView) {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        prepareContentView(contentView)
        addSubview(contentView)
    }

    @available(macOS 26.0, *)
    private func installNativeGlass(_ contentView: NSView) {
        let glassView = NSGlassEffectView(frame: bounds)
        glassView.autoresizingMask = [.width, .height]
        glassView.cornerRadius = cornerRadius
        glassView.style = .regular
        prepareContentView(contentView)
        glassView.contentView = contentView
        addSubview(glassView)
    }

    private func installFallbackMaterial(_ contentView: NSView) {
        let blurView = NSVisualEffectView(frame: bounds)
        blurView.autoresizingMask = [.width, .height]
        blurView.material = .underWindowBackground
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.isEmphasized = false
        blurView.alphaValue = fallbackMaterialOpacity
        addSubview(blurView)
        prepareContentView(contentView)
        addSubview(contentView)
    }

    private func prepareContentView(_ contentView: NSView) {
        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
    }
}
