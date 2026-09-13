import AppKit
import Testing
@testable import CodexUsageMonitor

@Suite("Balanced main-window frame policy", .serialized)
struct BalancedWindowPolicyTests {
    private let display = NSRect(x: 100, y: 50, width: 1_440, height: 900)

    @Test("Fresh windows use the normal outer target when the display allows it")
    func freshWindowUsesNormalOuterTarget() {
        let frame = MainWindowFramePolicy.initialFrame(visibleFrames: [display])

        #expect(frame.size == NSSize(width: 1_040, height: 760))
        #expect(frame.midX == display.midX)
        #expect(frame.midY == display.midY)
    }

    @Test("Fresh windows are constrained to the usable display")
    func freshWindowFitsSmallDisplay() {
        let smallDisplay = NSRect(x: 0, y: 0, width: 900, height: 640)
        let frame = MainWindowFramePolicy.initialFrame(visibleFrames: [smallDisplay])

        #expect(frame.size == smallDisplay.size)
        #expect(frame == smallDisplay)
    }

    @Test("Valid saved normal, tiled, and user-resized frames are retained")
    func validSavedFramesAreNotRewritten() {
        for frame in [
            NSRect(x: 240, y: 120, width: 1_040, height: 760),
            display,
            NSRect(x: 180, y: 90, width: 820, height: 600),
        ] {
            #expect(MainWindowFramePolicy.repairedFrame(for: frame, visibleFrames: [display]) == nil)
        }
    }

    @Test("Offscreen and oversized saved frames are safely constrained")
    func invalidSavedFramesAreConstrained() throws {
        let titlebarOffscreen = NSRect(x: 100, y: 400, width: 1_040, height: 760)
        let repairedTitlebar = try #require(
            MainWindowFramePolicy.repairedFrame(for: titlebarOffscreen, visibleFrames: [display])
        )
        #expect(repairedTitlebar.maxY <= display.maxY)

        let offscreen = NSRect(x: -2_000, y: -2_000, width: 1_040, height: 760)
        let repairedOffscreen = try #require(
            MainWindowFramePolicy.repairedFrame(for: offscreen, visibleFrames: [display])
        )
        #expect(display.contains(repairedOffscreen))
        #expect(repairedOffscreen.size == offscreen.size)

        let oversized = NSRect(x: 80, y: 10, width: 3_000, height: 2_000)
        let repairedOversized = try #require(
            MainWindowFramePolicy.repairedFrame(for: oversized, visibleFrames: [display])
        )
        #expect(repairedOversized == display)

        let moderatelyOversized = NSRect(x: 120, y: 60, width: 1_500, height: 920)
        let repairedModerate = try #require(
            MainWindowFramePolicy.repairedFrame(for: moderatelyOversized, visibleFrames: [display])
        )
        #expect(repairedModerate == display)
    }

    @Test("The default frame survives both hosted main-surface installations")
    @MainActor func defaultFrameSurvivesFullHostingSequence() throws {
        let controller = MainWindowController(restoresSavedFrame: false)
        defer { controller.tearDown() }

        let expected = MainWindowFramePolicy.initialFrame(
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        let frameAfterStartingHost = try #require(controller.frameForTesting)
        #expect(frameAfterStartingHost.size == expected.size)
        attachPreviewStore(to: controller)
        #expect(controller.frameForTesting == frameAfterStartingHost)
    }

    @Test("A saved frame survives both hosted main-surface installations")
    @MainActor func savedFrameSurvivesFullHostingSequence() throws {
        let autosaveName = "UMA.BalancedWindowPolicyTests.\(UUID().uuidString)"
        let expected = NSRect(x: 100, y: 80, width: 1_040, height: 760)
        let seedWindow = NSWindow(
            contentRect: expected,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        seedWindow.setFrame(expected, display: false)
        seedWindow.saveFrame(usingName: autosaveName)
        defer { seedWindow.close() }

        let controller = MainWindowController(autosaveName: autosaveName)
        defer { controller.tearDown() }

        #expect(try #require(controller.frameForTesting) == expected)
        attachPreviewStore(to: controller)
        #expect(controller.frameForTesting == expected)
    }

    @MainActor private func attachPreviewStore(to controller: MainWindowController) {
        controller.attach(
            store: .preview(language: .english),
            openSettings: {},
            scanAll: {},
            refreshAll: {},
            connectCodex: {},
            disconnectCodex: {},
            claudeControlState: { .consentRequired },
            connectClaude: {},
            accuracySyncClaude: {}
        )
    }
}
