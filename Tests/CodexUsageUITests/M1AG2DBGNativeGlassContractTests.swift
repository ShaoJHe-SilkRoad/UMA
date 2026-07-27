import AppKit
import Testing

#if canImport(CodexUsageAppShell)
@testable import CodexUsageAppShell
#else
@testable import CodexUsageMonitor
#endif

/// Contract for the Task-B material host.  It deliberately checks only the
/// public AppKit relationship and frozen geometry, never pixels or private
/// backdrop state.
struct M1AG2DBGNativeGlassContractTests {
    @Test @MainActor
    func materialHostKeepsFrozenPanelGeometryInItsActivePublicBranch() throws {
        let expectedFrame = NSRect(
            x: 0,
            y: 0,
            width: 370,
            height: 776
        )
        let host = AdaptivePanelMaterialHostView(
            frame: expectedFrame,
            cornerRadius: 28,
            fallbackMaterialOpacity: 0.44
        )
        let content = NSView(frame: host.bounds)
        host.installContentView(content)

        #expect(host.frame == expectedFrame)
        #expect(host.bounds.size == expectedFrame.size)
        #expect(host.layer?.cornerRadius == 28)

        let clipper = try #require(descendant(containing: content, in: host))
        #expect(clipper.frame == host.bounds)
        #expect(clipper.layer?.cornerRadius == 28)
        #expect(clipper.layer?.cornerCurve == .continuous)
        #expect(clipper.layer?.masksToBounds == true)
        #expect(content.frame == clipper.bounds)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            #expect(host.subviews.count == 1)
            #expect(host.subviews.first === clipper)
            #expect((host.layer?.borderWidth ?? 0) > 0)
            #expect(host.subviews.contains(where: { $0 is NSVisualEffectView }) == false)
            if #available(macOS 26.0, *) {
                #expect(host.subviews.contains(where: { $0 is NSGlassEffectView }) == false)
            }
        } else if #available(macOS 26.0, *) {
            let glass = try #require(host.subviews.first as? NSGlassEffectView)
            #expect(host.subviews.count == 1)
            #expect(host.layer?.masksToBounds == false)
            #expect(host.layer?.borderWidth == 0)
            #expect(glass.frame == host.bounds)
            #expect(glass.cornerRadius == 28)
            #expect(glass.style == .regular)
            #expect(glass.contentView === clipper)
        } else {
            let effect = try #require(host.subviews.first as? NSVisualEffectView)
            #expect(host.subviews.count == 2)
            #expect(host.layer?.masksToBounds == true)
            #expect((host.layer?.borderWidth ?? 0) > 0)
            #expect(effect.frame == host.bounds)
            #expect(effect.material == .underWindowBackground)
            #expect(effect.blendingMode == .behindWindow)
            #expect(effect.state == .active)
            #expect(effect.alphaValue == 0.44)
        }
    }

    @MainActor
    private func descendant(containing content: NSView, in root: NSView) -> NSView? {
        for view in root.subviews {
            if view.subviews.contains(where: { $0 === content }) { return view }
            if let match = descendant(containing: content, in: view) { return match }
        }
        return nil
    }
}
