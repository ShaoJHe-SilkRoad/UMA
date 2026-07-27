@preconcurrency import AppKit

/// Hosts exactly one adaptive panel material: native glass on macOS 26 and the
/// established visual-effect fallback on supported earlier releases.
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
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
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

    private func rebuildMaterial() {
        guard let contentView = hostedContentView else { return }
        contentView.removeFromSuperview()
        subviews.forEach { $0.removeFromSuperview() }
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = nil

        let clippedContentView = makeRoundedContentClipper(containing: contentView)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            configureFallbackContour()
            installOpaqueBackground(clippedContentView)
            return
        }
        if #available(macOS 26.0, *) {
            // NSGlassEffectView owns the one visible rounded contour.
            layer?.masksToBounds = false
            installNativeGlass(clippedContentView)
        } else {
            configureFallbackContour()
            installFallbackMaterial(clippedContentView)
        }
    }

    private func configureFallbackContour() {
        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        layer?.masksToBounds = true
        layer?.borderWidth = increasedContrast ? 1.4 : 0.8
        layer?.borderColor = NSColor.separatorColor
            .withAlphaComponent(increasedContrast ? 0.72 : 0.34)
            .cgColor
    }

    /// macOS 26 glass owns the visible rounded rim and must remain unmasked so
    /// its native contour and the panel shadow are not clipped. The hosted
    /// SwiftUI plane is the only full-frame rectangle, so it is isolated in
    /// this clear, continuous clipper before it reaches the glass content.
    private func makeRoundedContentClipper(containing contentView: NSView) -> NSView {
        let clipper = NSView(frame: bounds)
        clipper.autoresizingMask = [.width, .height]
        clipper.wantsLayer = true
        clipper.layer?.backgroundColor = NSColor.clear.cgColor
        clipper.layer?.cornerRadius = cornerRadius
        clipper.layer?.cornerCurve = .continuous
        clipper.layer?.masksToBounds = true

        contentView.frame = clipper.bounds
        contentView.autoresizingMask = [.width, .height]
        clipper.addSubview(contentView)
        return clipper
    }

    private func installOpaqueBackground(_ contentView: NSView) {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        addSubview(contentView)
    }

    @available(macOS 26.0, *)
    private func installNativeGlass(_ contentView: NSView) {
        let glassView = NSGlassEffectView(frame: bounds)
        glassView.autoresizingMask = [.width, .height]
        glassView.cornerRadius = cornerRadius
        glassView.style = .regular
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
        addSubview(contentView)
    }
}
