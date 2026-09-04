import AppKit
import Testing

#if canImport(CodexUsageAppShell)
@testable import CodexUsageAppShell
#else
@testable import CodexUsageMonitor
#endif

/// Runtime contract for the final layer-backed Quick Panel surface.
struct M1AG2DBGNativeGlassContractTests {
    @Test @MainActor
    func layerBackedHostKeepsFrozenPanelGeometry() {
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

        let snapshot = host.diagnosticSnapshot
        #expect(host.frame == expectedFrame)
        #expect(host.bounds.size == expectedFrame.size)
        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === content)
        #expect(content.frame == host.bounds)
        #expect(snapshot.subviewCount == 1)
        #expect(snapshot.contentFrameMatchesBounds)
        #expect(snapshot.cornerRadius == 28)
        #expect(snapshot.usesContinuousCorners)
        #expect(snapshot.masksToBounds)
        #expect(snapshot.borderWidth == 0)
        #expect(snapshot.shadowOpacity == 0)
        #expect(snapshot.hasBackground)
    }

    @Test @MainActor
    func oneHundredContentReplacementsKeepOneSurfaceAndOneContentRoot() {
        let host = AdaptivePanelMaterialHostView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 180),
            cornerRadius: 14,
            fallbackMaterialOpacity: 0.44
        )

        for _ in 0..<100 {
            let content = NSView(frame: host.bounds)
            host.installContentView(content)

            let snapshot = host.diagnosticSnapshot
            #expect(snapshot.subviewCount == 1)
            #expect(host.subviews.first === content)
            #expect(snapshot.contentFrameMatchesBounds)
            #expect(snapshot.cornerRadius == 14)
            #expect(snapshot.masksToBounds)
            #expect(snapshot.borderWidth == 0)
            #expect(snapshot.shadowOpacity == 0)
        }
    }

    @Test @MainActor
    func oneContourOwnerIsInvariantAtOneXAndTwoXBackingScales() throws {
        for contentsScale in [CGFloat(1), CGFloat(2)] {
            let host = AdaptivePanelMaterialHostView(
                frame: NSRect(x: 0, y: 0, width: 320, height: 180),
                cornerRadius: 14,
                fallbackMaterialOpacity: 0.44
            )
            host.layer?.contentsScale = contentsScale
            let content = NSView(frame: host.bounds)
            host.installContentView(content)

            let snapshot = host.diagnosticSnapshot
            #expect(host.layer?.contentsScale == contentsScale)
            #expect(snapshot.cornerRadius == 14)
            #expect(snapshot.masksToBounds)
            #expect(snapshot.borderWidth == 0)
            #expect(snapshot.shadowOpacity == 0)
            #expect(snapshot.subviewCount == 1)
            #expect(host.subviews.first === content)
            #expect(snapshot.contentFrameMatchesBounds)
        }
    }
}
