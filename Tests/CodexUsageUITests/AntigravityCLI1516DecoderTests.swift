import Foundation
import Testing
@testable import CodexUsageUI

/// The `--output-format json -p /usage` output of the official Antigravity
/// CLI 1.5.16 (2026-11-25), unedited. It holds group and bucket labels, model
/// names and numbers; no account, prompt or workspace data.
@Suite("Antigravity CLI 1.5.16 usage output")
struct AntigravityCLI1516DecoderTests {
    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Antigravity/agy-1.5.16-usage.json")
    }

    private let observedAt = Date(timeIntervalSince1970: 1_795_000_000)

    @Test("Both groups' five-hour and weekly buckets decode with their windows")
    func decodesCurrentOutput() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let decoded = try AntigravityQuotaDecoder.decode(
            data, sourceVersion: AntigravityReadOnlyCLIClient.sourceVersion, observedAt: observedAt
        )
        #expect(decoded.buckets.map(\.id) == ["gemini-weekly", "gemini-5h", "3p-weekly", "3p-5h"])
        #expect(decoded.buckets.map(\.window) == [.weekly, .fiveHour, .weekly, .fiveHour])
        #expect(decoded.buckets.map(\.groupLabel) == [
            "Gemini Models", "Gemini Models", "Claude and GPT models", "Claude and GPT models",
        ])
        #expect(abs(decoded.buckets[0].remainingPercent - 85.813307762146) < 0.0001)
        #expect(abs(decoded.buckets[1].remainingPercent - 87.99333572387695) < 0.0001)
        #expect(decoded.buckets[2].remainingPercent == 100)
        // A used limit has a reset; an untouched one reports the epoch, which
        // is no reset at all.
        #expect(decoded.buckets[0].resetsAt == ISO8601DateFormatter().date(from: "2026-12-01T03:06:45Z"))
        #expect(decoded.buckets[1].resetsAt == ISO8601DateFormatter().date(from: "2026-11-26T03:41:23Z"))
        #expect(decoded.buckets[2].resetsAt == nil)
        #expect(decoded.buckets[3].resetsAt == nil)
        // The descriptive sentences are checked, never kept.
        #expect(!String(reflecting: decoded).contains("fully refresh"))
    }

    @Test("The connector shows them as 5H and 7D windows named by group")
    func connectorWindows() async throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        let decoded = try AntigravityQuotaDecoder.decode(
            data, sourceVersion: AntigravityReadOnlyCLIClient.sourceVersion, observedAt: observedAt
        )
        let connector = GoogleAntigravityUsageConnector(
            readQuota: { decoded },
            verifyCapability: {},
            now: { self.observedAt }
        )
        await connector.start()
        await connector.refresh()
        let snapshot = await connector.currentSnapshot()
        let windows = try #require(snapshot.channels.first?.rateLimitWindows)
        #expect(windows.map(\.kind) == [.sevenDay, .fiveHour, .sevenDay, .fiveHour])
        #expect(windows.map(\.displayLabel) == [
            "Gemini Models", "Gemini Models", "Claude and GPT models", "Claude and GPT models",
        ])
        await connector.stop()
    }

    @Test(
        "An installed agy passes the trust gate by its Google signature",
        .enabled(if: FileManager.default.isExecutableFile(
            atPath: AntigravityReadOnlyCLIClient.executablePath
        ))
    )
    func installedCLIIsAdmitted() throws {
        let identity = try AntigravityReadOnlyCLIClient().verifyCapability()
        #expect(identity.signingTeamIdentifier == AntigravityReadOnlyCLIClient.admittedTeamIdentifier)
    }
}
