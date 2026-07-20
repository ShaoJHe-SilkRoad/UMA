import AppKit

enum UsagePanelExteriorContract {
    static func windowShadowEnabled(
        materialOwnsExteriorContour: Bool
    ) -> Bool {
        !materialOwnsExteriorContour
    }
}

/// Hosts exactly one adaptive panel material: native glass on macOS 26 and the
/// established visual-effect fallback on supported earlier releases.
final class AdaptivePanelMaterialHostView: NSView {
    private let cornerRadius: CGFloat
    private let fallbackMaterialOpacity: CGFloat
    private(set) var ownsExteriorContour = false

    init(frame frameRect: NSRect, cornerRadius: CGFloat, fallbackMaterialOpacity: Double) {
        self.cornerRadius = cornerRadius
        self.fallbackMaterialOpacity = fallbackMaterialOpacity
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        // The host is the sole exterior boundary. Clipping the native glass
        // removes its out-of-bounds halo, which otherwise reads as a second
        // perimeter in Light appearance.
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installContentView(_ contentView: NSView) {
        let clippedContentView = makeRoundedContentClipper(containing: contentView)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            installOpaqueBackground(clippedContentView)
            return
        }
        if #available(macOS 26.0, *) {
            ownsExteriorContour = true
            installNativeGlass(clippedContentView)
        } else {
            installFallbackMaterial(clippedContentView)
        }
    }

    /// The hosted SwiftUI plane is the only full-frame rectangle, so it is
    /// isolated in this clear, continuous clipper before it reaches the glass
    /// content.
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
        layer?.masksToBounds = true
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
