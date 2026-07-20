import AppKit
import CodexUsageUI
import Testing

#if canImport(CodexUsageAppShell)
@testable import CodexUsageAppShell
#else
@testable import CodexUsageMonitor
#endif

struct M1AG2DBGP2PanelGeometryContractTests {
    @Test
    func targetHeightUsesTheSharedSafeRange() {
        #expect(
            UsagePanelFrameGeometry.clampedHeight(-100)
                == UsagePanelMetrics.minimumHeight
        )
        #expect(
            UsagePanelFrameGeometry.clampedHeight(UsagePanelMetrics.height + 100)
                == UsagePanelMetrics.height
        )
        #expect(UsagePanelFrameGeometry.clampedHeight(542.6) == 543)
    }

    @Test
    func visibleResizeStaysInsideAShortScreensVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 24, width: 1280, height: 696)
        let current = NSRect(x: 800, y: 360, width: 370, height: 360)
        let target = UsagePanelFrameGeometry.targetFrame(
            from: current,
            height: UsagePanelMetrics.height,
            visibleTopEdge: current.maxY,
            visibleFrame: visibleFrame,
            screenMargin: 8
        )

        #expect(target.minY >= visibleFrame.minY + 8)
        #expect(target.maxY <= visibleFrame.maxY - 8)
        #expect(target.height == visibleFrame.height - 16)
    }

    @Test
    func visibleResizePreservesTheOriginalTopEdge() {
        let current = NSRect(x: 100, y: 200, width: 370, height: 600)
        let target = UsagePanelFrameGeometry.targetFrame(
            from: current,
            height: 430,
            visibleTopEdge: current.maxY
        )

        #expect(target.origin.x == current.origin.x)
        #expect(target.width == current.width)
        #expect(target.height == 430)
        #expect(target.maxY == current.maxY)
    }

    @Test
    func hiddenResizeLeavesTheOriginStable() {
        let current = NSRect(x: 100, y: 200, width: 370, height: 600)
        let target = UsagePanelFrameGeometry.targetFrame(
            from: current,
            height: UsagePanelMetrics.collapsedHeight,
            visibleTopEdge: nil
        )

        #expect(target.origin == current.origin)
        #expect(target.height == UsagePanelMetrics.collapsedHeight)
    }
}
