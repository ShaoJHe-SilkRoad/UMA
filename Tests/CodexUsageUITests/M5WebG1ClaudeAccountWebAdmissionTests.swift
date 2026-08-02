import Foundation
import Testing

@Suite("M5-WEB-G1 Claude account-web NO-GO")
struct M5WebG1ClaudeAccountWebAdmissionTests {
    @Test
    func navigationPolicyAllowsOnlyExactHttpsHostsAndRejectsLocalFiles() {
        let allowed = [
            "https://claude.ai/",
            "https://www.claude.ai/login",
            "https://accounts.google.com/o/oauth2/v2/auth",
            "https://accounts.googleusercontent.com/",
        ]
        let rejected = [
            "http://claude.ai/",
            "https://evil.example/",
            "https://claude.ai.evil.example/",
            "file:///tmp/private",
            "uma://callback",
            "javascript:alert(1)",
        ]

        #expect(allowed.allSatisfy { SyntheticRoutePolicy.permits($0) })
        #expect(rejected.allSatisfy { !SyntheticRoutePolicy.permits($0) })
    }

    @Test
    func onlyVerifiedUsagePageCanProduceObservation() {
        let login = SyntheticPage(
            origin: "https://claude.ai",
            route: "/login",
            kind: .login,
            metrics: []
        )
        let chat = SyntheticPage(
            origin: "https://claude.ai",
            route: "/chat/synthetic",
            kind: .chat,
            metrics: []
        )
        let billing = SyntheticPage(
            origin: "https://claude.ai",
            route: "/settings/billing",
            kind: .billing,
            metrics: []
        )
        let unrelated = SyntheticPage(
            origin: "https://evil.example",
            route: "/settings/usage",
            kind: .usage,
            metrics: validMetrics
        )

        for page in [login, chat, billing, unrelated] {
            #expect(SyntheticExtractor.observe(page) == .rejected)
        }
    }

    @Test
    func completeAtomicSyntheticObservationKeepsScopesIndependent() {
        let result = SyntheticExtractor.observe(.init(
            origin: "https://claude.ai",
            route: "/settings/usage",
            kind: .usage,
            metrics: validMetrics
        ))

        #expect(result == .accepted(.init(
            fiveHourRemaining: 75,
            weeklyRemaining: 37.5,
            modelSpecificRemaining: ["synthetic-model": 50]
        )))
    }

    @Test
    func percentagesConvertExactlyOnceAtZeroHundredAndFractionalValues() {
        let matrix = [
            (used: 0.0, remaining: 100.0),
            (used: 37.5, remaining: 62.5),
            (used: 100.0, remaining: 0.0),
        ]

        for example in matrix {
            #expect(
                SyntheticExtractor.remaining(fromUsed: example.used)
                    == example.remaining
            )
        }
    }

    @Test
    func malformedOutOfRangeAmbiguousAndMissingDataFailClosed() {
        let invalid: [Double] = [
            -0.01,
            100.01,
            .infinity,
            -.infinity,
            .nan,
        ]
        for value in invalid {
            #expect(SyntheticExtractor.remaining(fromUsed: value) == nil)
        }

        let missingWeekly = SyntheticPage(
            origin: "https://claude.ai",
            route: "/settings/usage",
            kind: .usage,
            metrics: [.init(scope: .fiveHour, used: 25, resetPresent: true)]
        )
        let duplicated = SyntheticPage(
            origin: "https://claude.ai",
            route: "/settings/usage",
            kind: .usage,
            metrics: validMetrics + [
                .init(scope: .fiveHour, used: 25, resetPresent: true)
            ]
        )
        let missingReset = SyntheticPage(
            origin: "https://claude.ai",
            route: "/settings/usage",
            kind: .usage,
            metrics: [
                .init(scope: .fiveHour, used: 25, resetPresent: false),
                .init(scope: .weekly, used: 62.5, resetPresent: true),
            ]
        )

        #expect(SyntheticExtractor.observe(missingWeekly) == .rejected)
        #expect(SyntheticExtractor.observe(duplicated) == .rejected)
        #expect(SyntheticExtractor.observe(missingReset) == .rejected)
    }

    @Test
    func normalizedOutputContainsNoRawPageIdentityBillingOrCredentials() {
        let observation = SyntheticObservation(
            fiveHourRemaining: 75,
            weeklyRemaining: 37.5,
            modelSpecificRemaining: ["synthetic-model": 50]
        )
        let reflection = String(reflecting: observation)

        for forbidden in [
            "html", "dom", "cookie", "token", "password", "email",
            "identity", "billing", "chat", "project",
        ] {
            #expect(!reflection.lowercased().contains(forbidden))
        }
        #expect(reflection.utf8.count < 4096)
    }

    @Test
    func durableRecordsLockNoGoPrivacyAndCleanup() throws {
        let records = try [
            source("source/UMA M5 Claude Account Web Dossier.md"),
            source("source/UMA M5 Claude Account Web Admission Decision.md"),
            source("source/UMA M5 Claude Account Web Privacy Contract.md"),
            source("source/UMA M5 Web Scope Lock.md"),
            source("source/UMA M5 Web QA Issue Ledger.md"),
        ]
        let combined = records.joined(separator: "\n")

        #expect(
            combined.contains(
                "NO-GO — SAFE ACCOUNT-WEB AUTHENTICATION NOT AVAILABLE"
            )
        )
        #expect(combined.contains("WKWebsiteDataStore.nonPersistent()"))
        #expect(combined.contains("zero retained data records"))
        #expect(combined.contains("App Sandbox"))
        #expect(combined.contains("evaluateJavaScript"))
        #expect(combined.contains("login-page DOM"))
        #expect(combined.contains("ASWebAuthenticationSession"))
        #expect(combined.contains("No production runtime"))
        #expect(!combined.contains("CLAUDE USAGE PAGE READY"))
    }

    @Test
    func productRuntimeContainsNoAccountWebImplementation() throws {
        let sourceRoot = repositoryRoot().appendingPathComponent("Sources")
        let sources = try FileManager.default
            .enumerator(at: sourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter {
                $0.pathExtension == "swift"
                    && $0.lastPathComponent.localizedCaseInsensitiveContains(
                        "claude"
                    )
            }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n") ?? ""

        #expect(!sources.contains("WKWebView"))
        #expect(!sources.contains("ASWebAuthenticationSession"))
        #expect(!sources.contains("isolatedAccountWeb"))
        #expect(!sources.contains("accounts.google.com"))
    }

    private var validMetrics: [SyntheticMetric] {
        [
            .init(scope: .fiveHour, used: 25, resetPresent: true),
            .init(scope: .weekly, used: 62.5, resetPresent: true),
            .init(
                scope: .model("synthetic-model"),
                used: 50,
                resetPresent: true
            ),
        ]
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum SyntheticRoutePolicy {
    private static let hosts = Set([
        "claude.ai",
        "www.claude.ai",
        "accounts.google.com",
        "accounts.googleusercontent.com",
    ])

    static func permits(_ raw: String) -> Bool {
        guard let url = URL(string: raw),
              url.scheme == "https",
              let host = url.host?.lowercased()
        else { return false }
        return hosts.contains(host)
    }
}

private struct SyntheticPage {
    enum Kind: Equatable {
        case login
        case usage
        case chat
        case billing
    }

    let origin: String
    let route: String
    let kind: Kind
    let metrics: [SyntheticMetric]
}

private struct SyntheticMetric {
    enum Scope: Hashable {
        case fiveHour
        case weekly
        case model(String)
    }

    let scope: Scope
    let used: Double
    let resetPresent: Bool
}

private struct SyntheticObservation: Equatable {
    let fiveHourRemaining: Double
    let weeklyRemaining: Double
    let modelSpecificRemaining: [String: Double]
}

private enum SyntheticObservationResult: Equatable {
    case accepted(SyntheticObservation)
    case rejected
}

private enum SyntheticExtractor {
    static func remaining(fromUsed value: Double) -> Double? {
        guard value.isFinite, (0...100).contains(value) else { return nil }
        return 100 - value
    }

    static func observe(_ page: SyntheticPage) -> SyntheticObservationResult {
        guard page.origin == "https://claude.ai",
              page.route == "/settings/usage",
              page.kind == .usage
        else { return .rejected }

        let grouped = Dictionary(grouping: page.metrics, by: \.scope)
        guard grouped.values.allSatisfy({ $0.count == 1 }),
              let five = grouped[.fiveHour]?.first,
              let weekly = grouped[.weekly]?.first,
              five.resetPresent,
              weekly.resetPresent,
              let fiveRemaining = remaining(fromUsed: five.used),
              let weeklyRemaining = remaining(fromUsed: weekly.used)
        else { return .rejected }

        var modelSpecific: [String: Double] = [:]
        for metric in page.metrics {
            guard metric.resetPresent,
                  let remaining = remaining(fromUsed: metric.used)
            else { return .rejected }
            if case let .model(label) = metric.scope {
                guard !label.isEmpty else { return .rejected }
                modelSpecific[label] = remaining
            }
        }

        return .accepted(.init(
            fiveHourRemaining: fiveRemaining,
            weeklyRemaining: weeklyRemaining,
            modelSpecificRemaining: modelSpecific
        ))
    }
}
