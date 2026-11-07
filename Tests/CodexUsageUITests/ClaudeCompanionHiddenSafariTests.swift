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

    /// Live on macOS 27.2, removing a temporary window's only tab left the
    /// empty window open, so a finished read closes the window itself.
    @Test("A finished read closes its temporary window, not only the tab")
    func finishedReadClosesTheWholeWindow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let background = try String(
            contentsOf: root.appendingPathComponent("BrowserExtension/Shared/background-core.js"),
            encoding: .utf8
        )
        #expect(background.contains("""
                if (!await closeTemporaryProviderWindow(read)) {
                  await api.tabs.remove(read.providerOwnedTabID);
                }
        """))
        #expect(background.contains("const expectedTabID = read.providerOwnedTabID"))
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

/// On Nov 1 2026 the installed companion stopped answering wakes while Safari kept
/// running, and every sync then stopped at the handshake. Why it went quiet was
/// not established, so these cover each way the page can recover by itself.
@Suite("Claude companion self-recovery")
struct ClaudeCompanionSelfRecoveryTests {
    private static let firstWake = "11111111-1111-4111-8111-111111111111"
    private static let secondWake = "22222222-2222-4222-8222-222222222222"
    private static let read = "33333333-3333-4333-8333-333333333333"

    @Test("A native message that is never answered stops holding back later ones")
    func unansweredNativeMessageExpires() throws {
        let page = try CompanionPage()
        page.clearLog()
        page.setNativeAnswers(false)
        page.dispatchWake(Self.firstWake)
        page.advance(milliseconds: 7_000)
        page.setNativeAnswers(true)
        page.dispatchWake(Self.secondWake)
        #expect(!page.log.contains("automation extensionBackgroundReady"))
        page.advance(milliseconds: 1_000)
        #expect(page.log.contains("automation extensionBackgroundReady"))
    }

    @Test("A command releases an overdue native message when timers are held back")
    func commandReleasesOverdueMessage() throws {
        let page = try CompanionPage()
        page.setNativeAnswers(false)
        page.dispatchWake(Self.firstWake)
        page.suspendTimers(true)
        page.advance(milliseconds: 9_000)
        page.setNativeAnswers(true)
        page.clearLog()
        page.dispatchWake(Self.secondWake)
        #expect(page.log.contains("automation extensionBackgroundReady"))
    }

    @Test("Two missed liveness checks reload the page; one does not")
    func missedChecksReload() throws {
        let page = try CompanionPage()
        page.setNativeAnswers(false)
        page.advance(milliseconds: 68_000)
        #expect(!page.log.contains("runtime.reload"))
        page.advance(milliseconds: 68_000)
        #expect(page.log.contains("runtime.reload"))
    }

    @Test("An answered check clears a missed one")
    func answeredCheckClearsMiss() throws {
        let page = try CompanionPage()
        page.setNativeAnswers(false)
        page.advance(milliseconds: 68_000)
        page.setNativeAnswers(true)
        page.advance(milliseconds: 60_000)
        page.setNativeAnswers(false)
        page.advance(milliseconds: 60_000)
        #expect(!page.log.contains("runtime.reload"))
    }

    /// A native side that stays gone must not restart the page every two minutes.
    @Test("Reloads are at least 30 minutes apart")
    func reloadsAreSpaced() throws {
        let page = try CompanionPage()
        page.setNativeAnswers(false)
        page.advance(milliseconds: 136_000)
        #expect(page.log.filter { $0 == "runtime.reload" }.count == 1)
        page.advance(milliseconds: 20 * 60_000)
        #expect(page.log.filter { $0 == "runtime.reload" }.count == 1)
        page.advance(milliseconds: 12 * 60_000)
        #expect(page.log.filter { $0 == "runtime.reload" }.count == 2)
    }

    @Test("The liveness check leaves a read in progress alone")
    func checkSkipsARead() throws {
        let page = try CompanionPage()
        page.advance(milliseconds: 50_000)
        page.dispatchRead(Self.read, placement: nil)
        let loads = page.receiptLoads
        page.advance(milliseconds: 15_000)
        #expect(page.receiptLoads == loads)
        #expect(!page.log.contains("runtime.reload"))
    }

    @Test("A port with no commands for five minutes is replaced, without announcing itself")
    func idlePortIsRenewed() throws {
        let page = try CompanionPage()
        #expect(page.portCount == 1)
        page.advance(milliseconds: 4 * 60_000)
        page.dispatchWake(Self.firstWake)
        page.advance(milliseconds: 2 * 60_000)
        #expect(page.portCount == 1)
        page.clearLog()
        page.advance(milliseconds: 4 * 60_000)
        #expect(page.portCount == 2)
        #expect(page.log.contains("port.disconnect"))
        #expect(!page.log.contains("automation extensionBackgroundReady"))
        page.dispatchWake(Self.secondWake)
        #expect(page.log.contains("automation extensionBackgroundReady"))
    }

    /// A slow native reply can save a receipt after the page stopped waiting for
    /// it. Nothing else would ever settle that receipt without a reload.
    @Test("The check settles a receipt the page does not know about")
    func unknownReceiptIsSettled() throws {
        let page = try CompanionPage()
        page.plantExpiredReceipt(Self.read)
        page.advance(milliseconds: 60_000)
        #expect(page.log.contains("receipt-removed EXPIRED"))
    }

    /// Seen live after the native process was killed: each command arrived
    /// twice, both copies started a read, and the read was refused.
    /// Safari suspends a background tab's process when its page goes quiet, and
    /// the read used to wait out its whole deadline with nothing able to answer.
    @Test("A read ends early once its page stops answering, and leaves a trace")
    func silentPageEndsTheReadEarly() throws {
        let page = try CompanionPage()
        page.dispatchRead(Self.read, placement: nil)
        page.connectProvider(tabID: 71)
        page.providerSend("""
        { type: "umaClaudeProviderDocumentDiscoveredV2", ownershipNonce: "uma-v2-\(String(repeating: "a", count: 43))" }
        """)
        page.providerSendCorrelated(type: "umaClaudeProviderReadyV2", requestID: Self.read)
        let extract = "umaClaudeExtractProviderUsageV2"
        #expect(page.providerPosted.filter { $0 == extract }.count == 1)

        page.advance(milliseconds: 3_000)
        #expect(page.providerPosted.filter { $0 == extract }.count == 4)
        #expect(page.providerPosted.filter { $0 == "umaClaudeProviderRouteEventV2" }.count >= 3)
        #expect(page.providerPosted.filter { $0 == "umaClaudeProviderResendResultV2" }.count == 3)
        page.providerSendProgress("extractReceived", requestID: Self.read)
        page.providerSendProgress("not-a-step", requestID: Self.read)
        #expect(!page.log.contains { $0.hasPrefix("trace ") })

        // Six seconds after it was last heard from, at second nine.
        page.advance(milliseconds: 5_000)
        #expect(!page.log.contains { $0.hasPrefix("trace ") })
        page.advance(milliseconds: 1_000)
        let trace = try #require(page.log.first { $0.hasPrefix("trace ") })
        #expect(trace.contains("status=tabUnavailable"))
        #expect(trace.contains("ports=1"))
        #expect(trace.contains("extractSent+0"))
        #expect(trace.contains("extractReceived+3000"))
        #expect(trace.contains("pageSilent+9000"))
        #expect(!trace.contains("not-a-step"))
        #expect(page.log.contains("tabs.remove 71"))

        // Finishing stops the asking.
        page.providerClearPosted()
        page.advance(milliseconds: 5_000)
        #expect(!page.providerPosted.contains(extract))
    }

    @Test("A page that keeps answering is given the whole deadline")
    func answeringPageIsNotCutShort() throws {
        let page = try CompanionPage()
        page.dispatchRead(Self.read, placement: nil)
        page.connectProvider(tabID: 71)
        page.providerSend("""
        { type: "umaClaudeProviderDocumentDiscoveredV2", ownershipNonce: "uma-v2-\(String(repeating: "a", count: 43))" }
        """)
        page.providerSendCorrelated(type: "umaClaudeProviderReadyV2", requestID: Self.read)
        for _ in 0..<25 {
            page.advance(milliseconds: 1_000)
            page.providerSendCorrelated(type: "umaClaudeProviderAliveV2", requestID: Self.read)
        }
        #expect(!page.log.contains { $0.hasPrefix("trace ") })
        page.advance(milliseconds: 6_000)
        let trace = try #require(page.log.first { $0.hasPrefix("trace ") })
        #expect(trace.contains("status=tabUnavailable"))
        #expect(!trace.contains("pageSilent"))
    }

    @Test("A command delivered twice is handled once")
    func repeatedCommandsAreDropped() throws {
        let page = try CompanionPage()
        page.clearLog()
        page.dispatchWake(Self.firstWake)
        page.dispatchWake(Self.firstWake)
        #expect(page.log.filter { $0 == "automation extensionBackgroundReady" }.count == 1)
        page.dispatchRead(Self.read, placement: nil)
        page.dispatchRead(Self.read, placement: nil)
        #expect(page.log.filter { $0 == "automation refreshStarted" }.count == 1)
        #expect(page.log.filter { $0 == "tabs.create background" }.count == 1)
        #expect(!page.log.contains("automation ownedTabOwnershipLost"))
    }

    /// Both pass the first in-progress check while waiting on the receipt load.
    @Test("Two different read requests at once start only one read")
    func concurrentReadsStartOne() throws {
        let page = try CompanionPage()
        page.clearLog()
        page.dispatchReadsTogether(Self.firstWake, Self.secondWake)
        #expect(page.log.filter { $0 == "automation refreshStarted" }.count == 1)
        #expect(page.log.filter { $0 == "tabs.create background" }.count == 1)
        #expect(page.log.contains("automation usageUnavailable"))
    }

    @Test("A disconnected port whose reconnect timer was lost is restored by the check")
    func lostReconnectIsRestored() throws {
        let page = try CompanionPage()
        page.disconnectNewestPort()
        #expect(page.portCount == 2)
        page.disconnectNewestPort()
        page.suspendTimers(true)
        page.advance(milliseconds: 500)
        page.suspendTimers(false)
        page.advance(milliseconds: 60_000)
        #expect(page.portCount == 3)
    }

    /// With no answer the receipt's state is unknown, so reads are refused, but
    /// only until the native side answers.
    @Test("Reads resume once the native side answers after a silent start")
    func silentStartDoesNotBlockForever() throws {
        let page = try CompanionPage(nativeAnswersAtStart: false)
        page.advance(milliseconds: 8_000)
        page.dispatchRead(Self.read, placement: nil)
        page.advance(milliseconds: 8_000)
        #expect(!page.log.contains("tabs.create background"))
        page.setNativeAnswers(true)
        page.advance(milliseconds: 60_000)
        page.dispatchRead(Self.secondWake, placement: nil)
        #expect(page.log.contains("tabs.create background"))
    }
}

/// One background page in its own JavaScriptCore context. JavaScriptCore runs
/// every pending promise job when a script evaluation returns, so each call
/// here leaves the page settled.
private final class CompanionPage {
    private let context: JSContext

    init(nativeAnswersAtStart: Bool = true) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let context = try #require(JSContext())
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        context.evaluateScript("globalThis.UMACompanionHarnessNativeAnswersAtStart = \(nativeAnswersAtStart)")
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

    var receiptLoads: Int {
        Int(context.evaluateScript("UMACompanionHarness.receiptLoads()")?.toInt32() ?? 0)
    }

    func plantExpiredReceipt(_ requestID: String) {
        context.evaluateScript("UMACompanionHarness.plantExpiredReceipt(\"\(requestID)\")")
    }

    func setNativeAnswers(_ answers: Bool) {
        context.evaluateScript("UMACompanionHarness.setNativeAnswers(\(answers))")
    }

    func dispatchWake(_ requestID: String) {
        context.evaluateScript("""
        UMACompanionHarness.dispatch({ command: "umaClaudeWakeBridge", requestID: "\(requestID)" })
        """)
    }

    /// One script evaluation, so no promise job runs between the two commands.
    func dispatchReadsTogether(_ first: String, _ second: String) {
        context.evaluateScript("""
        UMACompanionHarness.dispatch({ command: "umaClaudeAutomaticRefresh", requestID: "\(first)" });
        UMACompanionHarness.dispatch({ command: "umaClaudeAutomaticRefresh", requestID: "\(second)" });
        """)
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

    func connectProvider(tabID: Int) {
        context.evaluateScript("UMACompanionHarness.connectProvider(\(tabID))")
    }

    func providerSend(_ message: String) {
        context.evaluateScript("UMACompanionHarness.providerSend(\(message))")
    }

    func providerSendCorrelated(type: String, requestID: String) {
        providerSend("""
        { type: "\(type)", requestID: "\(requestID)", runtimeGenerationID: UMA_BROWSER_CONFIG.runtimeGenerationID }
        """)
    }

    func providerSendProgress(_ step: String, requestID: String) {
        providerSend("""
        { type: "umaClaudeProviderProgressV2", step: "\(step)", requestID: "\(requestID)", runtimeGenerationID: UMA_BROWSER_CONFIG.runtimeGenerationID }
        """)
    }

    var providerPosted: [String] {
        context.evaluateScript("UMACompanionHarness.providerPosted()")?.toArray() as? [String] ?? []
    }

    func providerClearPosted() {
        context.evaluateScript("UMACompanionHarness.providerClearPosted()")
    }

    func suspendTimers(_ suspended: Bool) {
        context.evaluateScript("UMACompanionHarness.suspendTimers(\(suspended))")
    }

    func clearLog() {
        context.evaluateScript("UMACompanionHarness.clearLog()")
    }
}
