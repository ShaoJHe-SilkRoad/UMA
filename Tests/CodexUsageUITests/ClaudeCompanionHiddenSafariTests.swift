import ClaudeSafariHostIPC
import Foundation
import JavaScriptCore
import Testing
@testable import CodexUsageUI

/// Safari does not load a page in a window that is on another desktop or
/// minimized. These run the shipped background page against a stand-in for
/// Safari's API, the containing app and the clock
/// (Tests/Fixtures/ClaudeCompanion/background-harness.js).
@Suite("Claude companion with Safari hidden")
struct ClaudeCompanionHiddenSafariTests {
    private static let firstRead = "11111111-1111-4111-8111-111111111111"
    private static let secondRead = "22222222-2222-4222-8222-222222222222"

    @Test("A hidden Safari gets the read in a temporary, unfocused window")
    func temporaryPlacementOpensItsOwnWindow() throws {
        let page = try CompanionPage()
        page.dispatchRead(Self.firstRead, placement: "temporaryWindow")
        #expect(page.log.contains("windows.create focused=false 480x640"))
        #expect(!page.log.contains { $0.hasPrefix("tabs.create") })
    }

    @Test("A visible Safari keeps the read in a background tab", arguments: [nil, "existingWindow"])
    func existingPlacementKeepsABackgroundTab(placement: String?) throws {
        let page = try CompanionPage()
        page.dispatchRead(Self.firstRead, placement: placement)
        #expect(page.log.contains("tabs.create background"))
        #expect(!page.log.contains { $0.hasPrefix("windows.create") })
    }

    @Test("An unknown placement is not a read command")
    func unknownPlacementIsIgnored() throws {
        let page = try CompanionPage()
        page.dispatchRead(Self.firstRead, placement: "minimizedWindow")
        #expect(!page.log.contains("automation refreshStarted"))
    }

    /// A page that never loads gives no proof of ownership, so its tab is not
    /// closed. The temporary window the read itself made, still holding only
    /// that tab, is closed instead of being left on screen.
    @Test("A temporary window whose page never reports back is closed")
    func unansweredTemporaryWindowIsClosed() throws {
        let page = try CompanionPage()
        page.dispatchRead(Self.firstRead, placement: "temporaryWindow")
        page.advance(milliseconds: 31_000)
        #expect(page.log.contains("windows.remove 901"))
    }

    /// Before, one spent reconnect left the page deaf to every wake until
    /// Safari reloaded it, which AUV showed as "Companion starting" for hours.
    @Test("A lost native port keeps reconnecting with back-off")
    func lostPortKeepsReconnecting() throws {
        let page = try CompanionPage()
        #expect(page.portCount == 1)
        page.disconnectNewestPort()
        #expect(page.portCount == 2)
        page.disconnectNewestPort()
        #expect(page.portCount == 2)
        page.advance(milliseconds: 1_000)
        #expect(page.portCount == 3)
        page.disconnectNewestPort()
        page.advance(milliseconds: 4_000)
        #expect(page.portCount == 3)
        page.advance(milliseconds: 1_000)
        #expect(page.portCount == 4)
        for _ in 0..<3 {
            page.disconnectNewestPort()
            page.advance(milliseconds: 60_000)
        }
        #expect(page.portCount == 7)
    }

    /// Safari can hold back a background page's timers, so the receipt of a
    /// read whose page never loaded may outlive its expiry. The next read
    /// settles it instead of being refused as an ownership loss.
    @Test("An expired receipt does not block the next read when timers stalled")
    func expiredReceiptIsSettledByTheNextRead() throws {
        let page = try CompanionPage()
        page.dispatchRead(Self.firstRead, placement: nil)
        page.advance(milliseconds: 31_000)
        page.clearLog()
        page.suspendTimers(true)
        page.advance(milliseconds: 3 * 60_000)
        page.dispatchRead(Self.secondRead, placement: nil)
        #expect(page.log.contains("receipt-removed EXPIRED"))
        #expect(!page.log.contains("automation ownedTabOwnershipLost"))
        #expect(page.log.contains("tabs.create background"))
    }

    @Test("AUV asks for a temporary window only when Safari has none on screen")
    func placementFollowsSafariVisibility() {
        #expect(SafariWindowVisibility.placement(hasWindowOnCurrentDesktop: false) == .temporaryWindow)
        #expect(SafariWindowVisibility.placement(hasWindowOnCurrentDesktop: true) == .existingWindow)
        #expect(SafariWindowVisibility.placement(hasWindowOnCurrentDesktop: nil) == .existingWindow)
    }

    @Test("Only a full-size, visible Safari window counts as on screen")
    func browserWindowDetection() {
        func window(pid: pid_t, layer: Int = 0, alpha: Double = 1, width: CGFloat = 1_200) -> [String: Any] {
            [
                kCGWindowOwnerPID as String: pid,
                kCGWindowLayer as String: layer,
                kCGWindowAlpha as String: alpha,
                kCGWindowBounds as String: CGRect(x: 0, y: 0, width: width, height: 800)
                    .dictionaryRepresentation,
            ]
        }
        let safari: Set<pid_t> = [707]
        #expect(SafariWindowVisibility.containsBrowserWindow([window(pid: 707)], ownedBy: safari))
        #expect(!SafariWindowVisibility.containsBrowserWindow([window(pid: 12)], ownedBy: safari))
        #expect(!SafariWindowVisibility.containsBrowserWindow([window(pid: 707, layer: 25)], ownedBy: safari))
        #expect(!SafariWindowVisibility.containsBrowserWindow([window(pid: 707, alpha: 0)], ownedBy: safari))
        #expect(!SafariWindowVisibility.containsBrowserWindow([window(pid: 707, width: 120)], ownedBy: safari))
        #expect(!SafariWindowVisibility.containsBrowserWindow([], ownedBy: safari))
    }

    @Test("A read request carries its placement; other requests cannot")
    func requestCarriesPlacement() throws {
        let read = ClaudeSafariHostIPCRequest(
            requestID: Self.firstRead,
            runtimeGenerationID: "3828ea01-d15a-47dc-8d2b-9ee20967da71",
            operation: .automaticRefresh,
            providerPlacement: .temporaryWindow
        )
        #expect(read.isStructurallyValid)
        let decoded = try JSONDecoder().decode(
            ClaudeSafariHostIPCRequest.self, from: JSONEncoder().encode(read)
        )
        #expect(decoded.providerPlacement == .temporaryWindow)
        let verify = ClaudeSafariHostIPCRequest(
            requestID: Self.secondRead,
            runtimeGenerationID: "3828ea01-d15a-47dc-8d2b-9ee20967da71",
            operation: .verifyCompanion,
            providerPlacement: .temporaryWindow
        )
        #expect(!verify.isStructurallyValid)
    }
}

/// One background page in its own JavaScriptCore context. JavaScriptCore runs
/// every pending promise job when a script evaluation returns, so each call
/// here leaves the page settled.
private final class CompanionPage {
    private let context: JSContext

    init() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let context = try #require(JSContext())
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        for file in [
            "BrowserExtension/Shared/claude-usage-extractor.js",
            "BrowserExtension/Shared/owned-provider-tab-v2-reducer.js",
            "Tests/Fixtures/ClaudeCompanion/background-harness.js",
            "BrowserExtension/Shared/background-core.js",
        ] {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            context.evaluateScript(source, withSourceURL: URL(string: "file:///\(file)"))
            #expect(failure == nil, "\(file): \(failure ?? "")")
        }
        self.context = context
    }

    var log: [String] {
        context.evaluateScript("UMACompanionHarness.entries()")?.toArray() as? [String] ?? []
    }

    var portCount: Int {
        Int(context.evaluateScript("UMACompanionHarness.portCount()")?.toInt32() ?? 0)
    }

    func dispatchRead(_ requestID: String, placement: String?) {
        let placementField = placement.map { ", placement: \"\($0)\"" } ?? ""
        context.evaluateScript("""
        UMACompanionHarness.dispatch({
          command: "umaClaudeAutomaticRefresh", requestID: "\(requestID)"\(placementField)
        })
        """)
    }

    /// Advances in one-second steps so promise jobs started by one timer run
    /// before the next timer is due.
    func advance(milliseconds: Int) {
        var remaining = milliseconds
        while remaining > 0 {
            let step = min(remaining, 1_000)
            context.evaluateScript("UMACompanionHarness.advance(\(step))")
            remaining -= step
        }
    }

    func disconnectNewestPort() {
        context.evaluateScript("UMACompanionHarness.disconnectNewestPort()")
    }

    func suspendTimers(_ suspended: Bool) {
        context.evaluateScript("UMACompanionHarness.suspendTimers(\(suspended))")
    }

    func clearLog() {
        context.evaluateScript("UMACompanionHarness.clearLog()")
    }
}
