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

    /// The page shows resets as text in the viewer's own time zone, so the
    /// clock and the expected resets are local times: a Tuesday at 3 PM.
    private static let pageNow = localDate(day: 27, hour: 15)
    /// "Resets at 6:40 PM" on the same day.
    private static let sessionReset = isoString(localDate(day: 27, hour: 18, minute: 40))
    /// "Resets Saturday 9:00 AM" that week.
    private static let weeklyReset = isoString(localDate(day: 31, hour: 9))

    @Test("Redesigned page: both rows read from one shared section, resets included")
    func redesignedPageReadsBothRows() async throws {
        let outcome = try await extract(fixture: "redesign-2026-10")
        #expect(outcome == Outcome(
            status: "success",
            fiveHour: 8,
            weekly: 14,
            fiveHourReset: Self.sessionReset,
            weeklyReset: Self.weeklyReset
        ))
    }

    /// A 5-hour reset can be at most five hours away. "Resets at 6:40 PM"
    /// read at 9 AM would be nearly ten hours ahead, so it is left unknown
    /// rather than shown as a wrong time.
    @Test("A text reset beyond its window's length is not reported")
    func textResetBeyondWindowIsNotReported() async throws {
        let outcome = try await extract(
            fixture: "redesign-2026-10",
            now: Self.localDate(day: 27, hour: 9)
        )
        #expect(outcome == Outcome(
            status: "success",
            fiveHour: 8,
            weekly: 14,
            fiveHourReset: nil,
            weeklyReset: Self.weeklyReset
        ))
    }

    @Test("Each reset wording Claude shows is read in local time")
    func resetWordings() async throws {
        let cases: [(String, Date?)] = [
            ("Resets at 6:40 PM", Self.localDate(day: 27, hour: 18, minute: 40)),
            ("Resets 4 PM", Self.localDate(day: 27, hour: 16)),
            ("Resets at 2:00 PM", Self.localDate(day: 28, hour: 14)),
            ("Resets at 18:40", Self.localDate(day: 27, hour: 18, minute: 40)),
            ("Resets Saturday 9:00 AM", Self.localDate(day: 31, hour: 9)),
            ("Resets Sat 9:00 AM", Self.localDate(day: 31, hour: 9)),
            ("Resets on Saturday at 9:00 AM", Self.localDate(day: 31, hour: 9)),
            ("Resets Tuesday 2:00 PM", Self.localDate(month: 11, day: 3, hour: 14)),
            ("Resets tomorrow at 9:00 AM", Self.localDate(day: 28, hour: 9)),
            ("Resets Nov 2, 9:00 AM", Self.localDate(month: 11, day: 2, hour: 9)),
            ("Resets in 2 hr 5 min", nil),
            ("Resets in 45 min", nil),
            ("Resets soon", nil),
            ("Resets Aug 5", nil),
            ("Resets at 13:00 PM", nil),
        ]
        for (text, expected) in cases {
            let read = try await readResetText(text)
            #expect(read == expected.map(Self.isoString), "\(text)")
        }
    }

    /// The live page showed both rows at the same value, which hid a missed
    /// weekly label: the 5-hour row then spread over both rows unnoticed.
    @Test("Equal values in both rows: each row is still found on its own")
    func equalValuesStillFindBothRows() async throws {
        let outcome = try await extract(fixture: "redesign-2026-10-equal-values")
        #expect(outcome == Outcome(
            status: "success",
            fiveHour: 14,
            weekly: 14,
            fiveHourReset: Self.sessionReset,
            weeklyReset: Self.weeklyReset
        ))
    }

    @Test("A model-specific weekly row is not taken as all models")
    func modelSpecificWeeklyRowIsNotAllModels() async throws {
        let outcome = try await extract(fixture: "redesign-2026-10-model-rows")
        #expect(outcome == Outcome(
            status: "success",
            fiveHour: 8,
            weekly: 14,
            fiveHourReset: Self.sessionReset,
            weeklyReset: Self.weeklyReset
        ))
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

    private static func localDate(month: Int = 10, day: Int, hour: Int, minute: Int = 0) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: .current, year: 2026, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func jsDate(_ date: Date) -> String {
        "new Date(\(Int64(date.timeIntervalSince1970 * 1000)))"
    }

    private func readResetText(_ text: String) async throws -> String? {
        let extractor = try String(contentsOf: Self.extractorURL, encoding: .utf8)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let literal = String(
            data: try JSONSerialization.data(withJSONObject: [text]),
            encoding: .utf8
        )!
        let script = extractor + """

        ;(() => {
          const d = UMAClaudeUsageExtractor.textResetDate(\(literal)[0], \(Self.jsDate(Self.pageNow)));
          return d ? d.toISOString() : "";
        })()
        """
        let result = try await webView.evaluateJavaScript(script) as? String
        return result?.isEmpty == false ? result : nil
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var extractorURL: URL {
        repositoryRoot.appendingPathComponent("BrowserExtension/Shared/claude-usage-extractor.js")
    }

    private func extract(
        fixture: String,
        location: String = usageLocation,
        now: Date = pageNow
    ) async throws -> Outcome {
        let root = Self.repositoryRoot
        let html = try String(
            contentsOf: root.appendingPathComponent("Tests/Fixtures/ClaudeUsage/\(fixture).html"),
            encoding: .utf8
        )
        let extractor = try String(contentsOf: Self.extractorURL, encoding: .utf8)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let loaded = FixtureLoadObserver()
        webView.navigationDelegate = loaded
        webView.loadHTMLString(html, baseURL: nil)
        try await loaded.wait()
        _ = try await webView.evaluateJavaScript(extractor + "\n;true")
        let script = """
        JSON.stringify((() => {
          const r = UMAClaudeUsageExtractor.extractResult(document, \(location), \(Self.jsDate(now)));
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
