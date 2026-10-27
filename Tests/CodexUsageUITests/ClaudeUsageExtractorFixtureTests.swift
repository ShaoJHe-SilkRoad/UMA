import Foundation
import Testing
import WebKit

/// Runs the shipped extractor against saved Usage page fixtures in a real DOM.
/// The JavaScriptCore tests elsewhere use hand-built stand-ins with no
/// `closest`, `parentElement` or selector semantics, so they cannot tell
/// whether a row is isolated on an actual page.
@Suite("Claude Usage extractor on page fixtures", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ClaudeUsageExtractorFixtureTests {
    private struct Outcome: Equatable {
        var status: String
        var fiveHour: Double?
        var weekly: Double?
        var fiveHourReset: String?
        var weeklyReset: String?
        var modelSpecific: String?
    }

    private static let usageLocation =
        "{protocol:'https:',origin:'https://claude.ai',pathname:'/new',search:'',hash:'#settings/usage'}"

    @Test("Redesigned page: both rows read from one shared section")
    func redesignedPageReadsBothRows() async throws {
        let outcome = try await extract(fixture: "redesign-2026-10")
        #expect(outcome == Outcome(status: "success", fiveHour: 8, weekly: 14))
    }

    /// The live page showed both rows at the same value, which hid a missed
    /// weekly label: the 5-hour row then spread over both rows unnoticed.
    @Test("Equal values in both rows: each row is still found on its own")
    func equalValuesStillFindBothRows() async throws {
        let outcome = try await extract(fixture: "redesign-2026-10-equal-values")
        #expect(outcome == Outcome(status: "success", fiveHour: 14, weekly: 14))
    }

    @Test("A model-specific weekly row is not taken as all models")
    func modelSpecificWeeklyRowIsNotAllModels() async throws {
        let outcome = try await extract(fixture: "redesign-2026-10-model-rows")
        #expect(outcome == Outcome(status: "success", fiveHour: 8, weekly: 14))
    }

    @Test("Pre-redesign page still reads, resets included")
    func legacyPageStillReads() async throws {
        let outcome = try await extract(fixture: "legacy-2026-08")
        #expect(outcome == Outcome(
            status: "success",
            fiveHour: 44,
            weekly: 61,
            fiveHourReset: "2026-08-01T16:00:00.000Z",
            weeklyReset: "2026-08-05T09:00:00.000Z"
        ))
    }

    @Test("Two weekly rows: the weekly value is not guessed")
    func twoWeeklyRowsLeaveWeeklyUnread() async throws {
        let outcome = try await extract(fixture: "negative-two-weekly-rows")
        #expect(outcome == Outcome(status: "success", fiveHour: 8, weekly: nil))
    }

    @Test("A row holding two percentages is not read")
    func sharedRowIsNotRead() async throws {
        let outcome = try await extract(fixture: "negative-shared-row")
        #expect(outcome == Outcome(status: "success", fiveHour: nil, weekly: 14))
    }

    @Test("A remaining share is never read as used")
    func remainingShareIsNotRead() async throws {
        let outcome = try await extract(fixture: "negative-remaining-share")
        #expect(outcome.status == "usageUnavailable")
        #expect(outcome.fiveHour == nil && outcome.weekly == nil)
    }

    @Test("A sign-in form wins over any visible row")
    func signInFormIsReported() async throws {
        let outcome = try await extract(fixture: "negative-login")
        #expect(outcome.status == "signInRequired")
    }

    @Test("Any other route is rejected before the page is read")
    func otherRouteIsRejected() async throws {
        let outcome = try await extract(
            fixture: "redesign-2026-10",
            location: "{protocol:'https:',origin:'https://claude.ai',pathname:'/new',search:'',hash:'#settings/account'}"
        )
        #expect(outcome.status == "routeRejected")
    }

    private func extract(fixture: String, location: String = usageLocation) async throws -> Outcome {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let html = try String(
            contentsOf: root.appendingPathComponent("Tests/Fixtures/ClaudeUsage/\(fixture).html"),
            encoding: .utf8
        )
        let extractor = try String(
            contentsOf: root.appendingPathComponent("BrowserExtension/Shared/claude-usage-extractor.js"),
            encoding: .utf8
        )
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let loaded = FixtureLoadObserver()
        webView.navigationDelegate = loaded
        webView.loadHTMLString(html, baseURL: nil)
        try await loaded.wait()
        _ = try await webView.evaluateJavaScript(extractor + "\n;true")
        let script = """
        JSON.stringify((() => {
          const r = UMAClaudeUsageExtractor.extractResult(document, \(location), new Date("2026-10-27T12:00:00Z"));
          const o = r.observation || {};
          return {
            status: r.status,
            fiveHour: o.fiveHour ? o.fiveHour.usedPercentage : null,
            weekly: o.weeklyAllModels ? o.weeklyAllModels.usedPercentage : null,
            fiveHourReset: o.fiveHour ? o.fiveHour.resetAt : null,
            weeklyReset: o.weeklyAllModels ? o.weeklyAllModels.resetAt : null,
            modelSpecific: o.modelSpecificWeekly ? o.modelSpecificWeekly.modelFamily : null,
          };
        })())
        """
        let json = try #require(try await webView.evaluateJavaScript(script) as? String)
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        return Outcome(
            status: object["status"] as? String ?? "",
            fiveHour: object["fiveHour"] as? Double,
            weekly: object["weekly"] as? Double,
            fiveHourReset: object["fiveHourReset"] as? String,
            weeklyReset: object["weeklyReset"] as? String,
            modelSpecific: object["modelSpecific"] as? String
        )
    }
}

@MainActor
private final class FixtureLoadObserver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    func wait() async throws {
        if finished { return }
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finished = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
