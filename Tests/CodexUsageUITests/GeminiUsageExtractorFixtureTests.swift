import Foundation
import Testing
import WebKit

/// Runs the shipped Gemini extractor in a real DOM. The fixtures are written
/// by hand from a screenshot of the signed-in Usage page, not captured from
/// it; they pin what must hold on any layout, above all that nothing outside
/// the Usage region, such as a conversation title in the sidebar, is read.
@Suite("Gemini Usage extractor", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct GeminiUsageExtractorFixtureTests {
    private static let usageLocation =
        "{protocol:'https:',origin:'https://gemini.google.com',pathname:'/usage',search:'',hash:''}"

    /// The page shows resets as text in the viewer's own time zone, so the
    /// clock and the expected resets are local times: Nov 24 at 1:45 AM.
    private static let pageNow = localDate(day: 24, hour: 1, minute: 45)
    /// "Resets at 6:18 AM" the same day.
    private static let currentReset = isoString(localDate(day: 24, hour: 6, minute: 18))
    /// "Resets Nov 25 at 9:18 PM".
    private static let weeklyReset = isoString(localDate(day: 25, hour: 21, minute: 18))

    @Test("Both rows, their resets and the plan are read; the sidebar never is")
    func screenshotLayout() async throws {
        let result = try await run(fixture: "synthetic-framework")
        #expect(result["status"] as? String == "success")
        let observation = try #require(result["observation"] as? [String: Any])
        let buckets = try #require(observation["buckets"] as? [[String: Any]])
        #expect(buckets.map { $0["bucketID"] as? String } == ["current", "weekly"])
        #expect(buckets[0]["usedPercentage"] as? Double == 0)
        #expect(buckets[0]["period"] as? String == "unknown")
        #expect(buckets[0]["resetAt"] as? String == Self.currentReset)
        #expect(buckets[1]["usedPercentage"] as? Double == 4)
        #expect(buckets[1]["period"] as? String == "weekly")
        #expect(buckets[1]["resetAt"] as? String == Self.weeklyReset)
        #expect(observation["planLabel"] as? String == "pro")
        // The sidebar's "Weekly limit … 73%" is a conversation title.
        let serialized = String(
            decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self
        )
        #expect(!serialized.contains("73"))
    }

    @Test("A label sharing its element with an icon is still read, and the plan badge inside the heading")
    func iconLabelLayout() async throws {
        let result = try await run(fixture: "synthetic-icon-label")
        #expect(result["status"] as? String == "success")
        let observation = try #require(result["observation"] as? [String: Any])
        let buckets = try #require(observation["buckets"] as? [[String: Any]])
        #expect(buckets.map { $0["usedPercentage"] as? Double } == [12, 30])
        #expect(buckets[0]["resetAt"] as? String == Self.currentReset)
        #expect(buckets[1]["resetAt"] is NSNull)
        #expect(observation["planLabel"] as? String == "ultra")
    }

    @Test("Two rows for one bucket report neither")
    func ambiguousRowsFailClosed() async throws {
        let result = try await run(fixture: "synthetic-ambiguous")
        #expect(result["status"] as? String == "usageUnavailable")
        #expect(result["reasonCode"] as? String == "PROVIDER_STRUCTURE_UNSUPPORTED")
    }

    @Test("A sign-in form on the Usage route asks for sign-in")
    func signedOut() async throws {
        let result = try await run(fixture: "synthetic-signed-out")
        #expect(result["status"] as? String == "signInRequired")
    }

    @Test("Only the exact Usage route is read")
    func otherRoutesAreRejected() async throws {
        for location in [
            "{protocol:'https:',origin:'https://gemini.google.com',pathname:'/app',search:'',hash:''}",
            "{protocol:'https:',origin:'https://gemini.google.com',pathname:'/usage',search:'?hl=en',hash:''}",
            "{protocol:'https:',origin:'https://gemini.google.com',pathname:'/usage',search:'',hash:'#uma_ot=x'}",
            "{protocol:'https:',origin:'https://claude.ai',pathname:'/usage',search:'',hash:''}",
        ] {
            let result = try await run(fixture: "synthetic-framework", location: location)
            #expect(result["status"] as? String == "routeRejected")
        }
    }

    private static func localDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func run(
        fixture: String,
        location: String = usageLocation
    ) async throws -> [String: Any] {
        let root = Self.repositoryRoot
        let html = try String(
            contentsOf: root.appendingPathComponent("Tests/Fixtures/GeminiUsage/\(fixture).html"),
            encoding: .utf8
        )
        // As on the page: the Claude extractor supplies the shared reset reader.
        var scripts = ""
        for file in ["claude-usage-extractor.js", "gemini-usage-extractor.js"] {
            scripts += try String(
                contentsOf: root.appendingPathComponent("BrowserExtension/Shared/\(file)"),
                encoding: .utf8
            ) + "\n;"
        }
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let loaded = GeminiFixtureLoadObserver()
        webView.navigationDelegate = loaded
        webView.loadHTMLString(html, baseURL: nil)
        try await loaded.wait()
        _ = try await webView.evaluateJavaScript(scripts + "true")
        let now = "new Date(\(Int64(Self.pageNow.timeIntervalSince1970 * 1000)))"
        let script = """
        JSON.stringify(UMAGeminiUsageExtractor.extractResult(document, \(location), \(now)))
        """
        let json = try #require(try await webView.evaluateJavaScript(script) as? String)
        return try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
    }
}

@MainActor
private final class GeminiFixtureLoadObserver: NSObject, WKNavigationDelegate {
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
