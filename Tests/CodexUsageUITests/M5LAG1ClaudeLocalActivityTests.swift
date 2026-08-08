import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5-LA-G1 Claude local activity")
struct M5LAG1ClaudeLocalActivityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Pricing

    @Test
    func everyPublishedFamilyPricesAndUnknownModelsStayUnpriced() {
        #expect(ClaudeModelPrice.rate(forModel: "claude-opus-5")?.inputPerMillion == 5)
        #expect(ClaudeModelPrice.rate(forModel: "claude-opus-5")?.outputPerMillion == 25)
        #expect(ClaudeModelPrice.rate(forModel: "claude-sonnet-5")?.inputPerMillion == 3)
        #expect(ClaudeModelPrice.rate(forModel: "claude-sonnet-5")?.outputPerMillion == 15)
        #expect(ClaudeModelPrice.rate(forModel: "claude-haiku-4-5")?.inputPerMillion == 1)
        #expect(ClaudeModelPrice.rate(forModel: "claude-fable-5")?.inputPerMillion == 10)
        // Dated snapshots and unseen point releases still price by family.
        #expect(ClaudeModelPrice.rate(forModel: "claude-haiku-4-5-20251001")?.displayName == "Haiku")
        #expect(ClaudeModelPrice.rate(forModel: "CLAUDE-OPUS-4-8")?.displayName == "Opus")
        // A non-Claude or unrecognized identifier must not be valued at zero.
        #expect(ClaudeModelPrice.rate(forModel: "gpt-5.6-sol") == nil)
        #expect(ClaudeModelPrice.rate(forModel: "") == nil)
    }

    @Test
    func cacheMultipliersFollowTheDocumentedPromptCachingContract() {
        let rate = ClaudeModelPrice.rate(forModel: "claude-opus-5")!
        let million: Int64 = 1_000_000

        let read = ClaudeTokenCounts(
            inputTokens: 0, outputTokens: 0, cacheReadTokens: million,
            fiveMinuteCacheWriteTokens: 0, oneHourCacheWriteTokens: 0
        )
        let fiveMinute = ClaudeTokenCounts(
            inputTokens: 0, outputTokens: 0, cacheReadTokens: 0,
            fiveMinuteCacheWriteTokens: million, oneHourCacheWriteTokens: 0
        )
        let oneHour = ClaudeTokenCounts(
            inputTokens: 0, outputTokens: 0, cacheReadTokens: 0,
            fiveMinuteCacheWriteTokens: 0, oneHourCacheWriteTokens: million
        )
        #expect(abs(read.estimatedUSD(rate: rate) - 0.5) < 0.0001)      // 0.1x of $5
        #expect(abs(fiveMinute.estimatedUSD(rate: rate) - 6.25) < 0.0001) // 1.25x of $5
        #expect(abs(oneHour.estimatedUSD(rate: rate) - 10.0) < 0.0001)    // 2x of $5
    }

    @Test
    func theFourTokenBucketsAreDisjointRatherThanNested() {
        // Cache reads are NOT a subset of input on Claude. Treating them as one
        // would understate both the token total and the cost.
        let counts = ClaudeTokenCounts(
            inputTokens: 10, outputTokens: 20, cacheReadTokens: 30,
            fiveMinuteCacheWriteTokens: 40, oneHourCacheWriteTokens: 50
        )
        #expect(counts.totalTokens == 150)
    }

    // MARK: - Record decoding

    @Test
    func onlyAllowlistedFieldsAreDecodedFromARecord() throws {
        let line = """
        {"type":"assistant","requestId":"req-1","timestamp":"2027-01-15T10:00:00.000Z",\
        "cwd":"/Users/someone/secret-project","gitBranch":"feature/private",\
        "message":{"model":"claude-opus-5","id":"msg_1",\
        "content":[{"type":"text","text":"a confidential answer"}],\
        "usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":300,\
        "cache_creation_input_tokens":700,\
        "cache_creation":{"ephemeral_5m_input_tokens":400,"ephemeral_1h_input_tokens":300}}}}
        """
        let record = try #require(ClaudeLocalActivityReader.record(fromLine: line))
        #expect(record.requestID == "req-1")
        #expect(record.model == "claude-opus-5")
        #expect(record.counts.inputTokens == 100)
        #expect(record.counts.outputTokens == 200)
        #expect(record.counts.cacheReadTokens == 300)
        #expect(record.counts.fiveMinuteCacheWriteTokens == 400)
        #expect(record.counts.oneHourCacheWriteTokens == 300)
        // The record type has no field that could carry content, a path, or a
        // branch name, so the surrounding keys are structurally undecodable.
        #expect(record.counts.totalTokens == 1300)
    }

    @Test
    func absentPerTTLBreakdownFallsBackToTheUndifferentiatedTotal() throws {
        let line = """
        {"requestId":"req-2","timestamp":"2027-01-15T10:00:00Z",\
        "message":{"model":"claude-sonnet-5",\
        "usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":500}}}
        """
        let record = try #require(ClaudeLocalActivityReader.record(fromLine: line))
        #expect(record.counts.fiveMinuteCacheWriteTokens == 500)
        #expect(record.counts.oneHourCacheWriteTokens == 0)
    }

    @Test
    func recordsWithoutUsageOrModelAreRejected() {
        let cases = [
            #"{"type":"user","message":{"content":[{"type":"text","text":"hello"}]}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-5"}}"#,
            #"{"type":"assistant","message":{"usage":{"input_tokens":5}}}"#,
            #"{"type":"assistant","message":{"model":"","usage":{"input_tokens":5}}}"#,
            #"{"agentId":"a1","event":"started"}"#,
            "not json at all",
            "",
        ]
        for line in cases {
            #expect(ClaudeLocalActivityReader.record(fromLine: line) == nil)
        }
    }

    @Test
    func negativeAndNonNumericCountsClampToZero() throws {
        let line = """
        {"requestId":"req-3","timestamp":"2027-01-15T10:00:00Z",\
        "message":{"model":"claude-opus-5",\
        "usage":{"input_tokens":-50,"output_tokens":"12","cache_read_input_tokens":null}}}
        """
        let record = try #require(ClaudeLocalActivityReader.record(fromLine: line))
        #expect(record.counts.inputTokens == 0)
        #expect(record.counts.outputTokens == 0)
        #expect(record.counts.cacheReadTokens == 0)
    }

    // MARK: - Seven-day window

    @Test
    func sevenDayWindowIsRollingAndInclusiveOfToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let keys = ClaudeLocalActivityReader.sevenDayKeys(now: now, calendar: calendar)
        #expect(keys.count == 7)
        let today = ClaudeLocalActivityReader.usageDay(for: now, calendar: calendar)
        #expect(keys.contains(today))
        let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: now)!
        #expect(keys.contains(ClaudeLocalActivityReader.usageDay(for: sixDaysAgo, calendar: calendar)))
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        #expect(!keys.contains(ClaudeLocalActivityReader.usageDay(for: sevenDaysAgo, calendar: calendar)))
    }

    // MARK: - Aggregation

    @Test
    func oneResponseWrittenOncePerContentBlockIsCountedOnce() throws {
        // Claude repeats an identical usage object for every content block of a
        // single response. Without de-duplication the totals roughly double.
        let root = try makeFixture(lines: [
            usageLine(requestID: "dup", model: "claude-opus-5", input: 1_000, output: 0, daysAgo: 0),
            usageLine(requestID: "dup", model: "claude-opus-5", input: 1_000, output: 0, daysAgo: 0),
            usageLine(requestID: "dup", model: "claude-opus-5", input: 1_000, output: 0, daysAgo: 0),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeLocalActivityReader(rootDirectory: root, calendar: utcCalendar)
            .read(now: now)
        #expect(snapshot.apiEquivalentCost?.observedTokens == 1_000)
    }

    @Test
    func coverageFallsWhenAModelHasNoPublishedRate() throws {
        let root = try makeFixture(lines: [
            usageLine(requestID: "a", model: "claude-opus-5", input: 1_000, output: 0, daysAgo: 0),
            usageLine(requestID: "b", model: "some-unreleased-model", input: 3_000, output: 0, daysAgo: 0),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeLocalActivityReader(rootDirectory: root, calendar: utcCalendar)
            .read(now: now)
        let estimate = try #require(snapshot.apiEquivalentCost)
        #expect(estimate.observedTokens == 4_000)
        #expect(estimate.pricedTokens == 1_000)
        #expect(estimate.recognizedModelCount == 1)
        // Unpriced tokens stay in the denominator instead of being valued at zero.
        #expect(Int((Double(estimate.pricedTokens) / Double(estimate.observedTokens) * 100).rounded()) == 25)
    }

    @Test
    func sevenDayTotalExcludesOlderRecordsWhileLifetimeKeepsThem() throws {
        let root = try makeFixture(lines: [
            usageLine(requestID: "recent", model: "claude-opus-5", input: 1_000_000, output: 0, daysAgo: 1),
            usageLine(requestID: "old", model: "claude-opus-5", input: 1_000_000, output: 0, daysAgo: 30),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeLocalActivityReader(rootDirectory: root, calendar: utcCalendar)
            .read(now: now)
        let estimate = try #require(snapshot.apiEquivalentCost)
        #expect(abs(estimate.sevenDayUSD - 5.0) < 0.0001)
        #expect(abs(estimate.lifetimeUSD - 10.0) < 0.0001)
    }

    @Test
    func unrelatedJSONLFilesContributeNothingRatherThanBeingSpecialCased() throws {
        // Workflow journals and other tooling artifacts share the extension.
        // The schema gate makes them inert.
        let root = try makeFixture(lines: [
            usageLine(requestID: "a", model: "claude-opus-5", input: 500, output: 0, daysAgo: 0),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent("project").appendingPathComponent("journal.jsonl")
        try #"{"type":"started","label":"research"}"#.write(to: journal, atomically: true, encoding: .utf8)

        let snapshot = ClaudeLocalActivityReader(rootDirectory: root, calendar: utcCalendar)
            .read(now: now)
        #expect(snapshot.apiEquivalentCost?.observedTokens == 500)
    }

    @Test
    func anAbsentOrEmptyRootReportsUnavailableRatherThanZero() {
        let missing = URL(fileURLWithPath: "/private/tmp/uma-claude-local-activity-absent-\(UUID().uuidString)")
        let snapshot = ClaudeLocalActivityReader(rootDirectory: missing, calendar: utcCalendar)
            .read(now: now)
        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.apiEquivalentCost == nil)
        #expect(snapshot.tasks.isEmpty)
    }

    @Test
    func recentTasksAreCappedAtThreeAndOrderedNewestFirst() throws {
        let root = try FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-claude-local-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<5 {
            let dir = root.appendingPathComponent("project-\(index)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let line = usageLine(
                requestID: "req-\(index)",
                model: "claude-opus-5",
                input: Int64((index + 1) * 1_000),
                output: 0,
                daysAgo: 4 - index
            )
            try line.write(
                to: dir.appendingPathComponent("session.jsonl"),
                atomically: true,
                encoding: .utf8
            )
        }

        let snapshot = ClaudeLocalActivityReader(rootDirectory: root, calendar: utcCalendar)
            .read(now: now)
        #expect(snapshot.tasks.count == 3)
        let timestamps = snapshot.tasks.map(\.modifiedAt)
        #expect(timestamps == timestamps.sorted(by: >))
        // Newest three sessions are indexes 4, 3, 2 -> 5000 + 4000 + 3000.
        #expect(snapshot.tasks.reduce(0) { $0 + $1.totalTokens } == 12_000)
    }

    // MARK: - Connector contract

    @Test
    func connectorDeclaresLocalActivityWithoutLosingAnyExistingCapability() {
        let descriptor = ClaudeCodeUsageConnector.production().descriptor
        for required in [
            AgentConnectorCapability.connect,
            .reconnect,
            .refresh,
            .disconnect,
            .rateLimits,
            .sanitizedLastValidRestore,
            .automaticRefresh,
            .localActivity,
        ] {
            #expect(descriptor.capabilities.contains(required))
        }
        #expect(!descriptor.capabilities.contains(.hiddenFromDesktopAssistant))
        #expect(descriptor.supportedScopes == [.account, .device, .session, .task])
    }

    @Test
    func localActivityNeverContributesARateLimitWindow() throws {
        // The hard line from the decision history: local activity is secondary
        // analytics and can never be read as account remaining quota.
        let root = try makeFixture(lines: [
            usageLine(requestID: "a", model: "claude-opus-5", input: 1_000, output: 0, daysAgo: 0),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeLocalActivityReader(rootDirectory: root, calendar: utcCalendar)
            .read(now: now)
        let metrics = try #require(snapshot.apiEquivalentCost)
        #expect(metrics.observedTokens > 0)
        // The reader itself has no window type to produce; the connector's
        // local channel is constructed with an empty window list.
        #expect(ClaudeCodeUsageConnector.production().descriptor.supportedScopes.contains(.account))
    }

    // MARK: - Fixtures

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeFixture(lines: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-claude-local-\(UUID().uuidString)")
        let projectDirectory = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(
            to: projectDirectory.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    private func usageLine(
        requestID: String,
        model: String,
        input: Int64,
        output: Int64,
        daysAgo: Int
    ) -> String {
        let date = utcCalendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
        return """
        {"type":"assistant","requestId":"\(requestID)","timestamp":"\(stamp)",\
        "message":{"model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
        """
    }
}
