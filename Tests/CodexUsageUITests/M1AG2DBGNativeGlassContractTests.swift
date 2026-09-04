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

        #expect(host.layer?.cornerCurve == .continuous)
        #expect(host.layer?.masksToBounds == true)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            #expect(host.subviews.count == 1)
            #expect(host.subviews.first === content)
            #expect((host.layer?.borderWidth ?? 0) > 0)
            #expect(host.subviews.contains(where: { $0 is NSVisualEffectView }) == false)
            if #available(macOS 26.0, *) {
                #expect(host.subviews.contains(where: { $0 is NSGlassEffectView }) == false)
            }
        } else if #available(macOS 26.0, *) {
            let glass = try #require(host.subviews.first as? NSGlassEffectView)
            #expect(host.subviews.count == 1)
            #expect(host.layer?.masksToBounds == true)
            #expect(host.layer?.borderWidth == 0)
            #expect(glass.frame == host.bounds)
            #expect(glass.cornerRadius == 28)
            #expect(glass.style == .regular)
            #expect(glass.contentView === content)
            #expect(content.frame == glass.bounds)
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
            #expect(host.subviews.last === content)
            #expect(content.frame == host.bounds)
        }
    }

    @Test @MainActor
    func oneHundredMaterialRebuildsKeepOneClipAndOneMaterialOwner() {
        let host = AdaptivePanelMaterialHostView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 180),
            cornerRadius: 14,
            fallbackMaterialOpacity: 0.44
        )

        for _ in 0..<100 {
            let content = NSView(frame: host.bounds)
            host.installContentView(content)

            #expect(host.layer?.masksToBounds == true)
            #expect(host.layer?.cornerRadius == 14)
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                #expect(host.subviews.count == 1)
                #expect(host.subviews.first === content)
            } else if #available(macOS 26.0, *) {
                #expect(host.subviews.count == 1)
                #expect(host.subviews.first is NSGlassEffectView)
                #expect((host.subviews.first as? NSGlassEffectView)?.contentView === content)
            } else {
                #expect(host.subviews.count == 2)
                #expect(host.subviews.first is NSVisualEffectView)
                #expect(host.subviews.last === content)
            }
        }
    }
}
