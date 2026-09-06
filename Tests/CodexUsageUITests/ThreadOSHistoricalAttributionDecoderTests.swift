import Foundation
import Testing
@testable import CodexUsageUI

struct ThreadOSHistoricalAttributionDecoderTests {
    @Test
    func hostileWireFieldsNeverEnterTypedThreadOSProjection() throws {
        let hostile = """
        {"schema":"threados.usage-attribution-export.v1","historical_only":true,"status":"COMPLETE","row_count":1,"unavailable_count":0,"rows":[{"schema":"threados.usage-attribution-wire.v1","status":"ELIGIBLE_HISTORICAL","observation":"validated historical journal observation","project_key":"TOSUMA","project_root_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","task_id":"TU3","local_role":"DEVELOPMENT","thread_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","turn_digest":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","correlation_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","attempt_digest":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","destination_readback_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","acknowledgement_digest":"1111111111111111111111111111111111111111111111111111111111111111","message_digest":"2222222222222222222222222222222222222222222222222222222222222222","prompt":"PRIVATE_PROMPT","tool_input":"PRIVATE_TOOL","account":"PRIVATE_ACCOUNT","path":"/PRIVATE_PATH"}]}
        """
        let analytics = ThreadOSHistoricalAttributionDecoder.decode(Data(hostile.utf8), now: .distantPast)
        let row = try #require(analytics.rows.first)
        let encoded = String(data: try JSONEncoder().encode(row), encoding: .utf8) ?? ""
        #expect(!encoded.contains("PRIVATE_"))
        #expect(row.projectKey == "TOSUMA")
    }
    @Test
    func admitsOnlyTheCanonicalHistoricalRolesAndRejectsUnknownRoles() throws {
        let data = Data("""
        {"schema":"threados.usage-attribution-export.v1","historical_only":true,"status":"COMPLETE","row_count":1,"unavailable_count":2,"rows":[{"schema":"threados.usage-attribution-wire.v1","status":"ELIGIBLE_HISTORICAL","observation":"validated historical journal observation","project_key":"TOSUMA","project_root_digest":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","task_id":"TU3","local_role":"DEVELOPMENT","thread_digest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","turn_digest":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","correlation_digest":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","attempt_digest":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","destination_readback_digest":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","acknowledgement_digest":"1111111111111111111111111111111111111111111111111111111111111111","message_digest":"2222222222222222222222222222222222222222222222222222222222222222"}]}
        """.utf8)
        let text = String(decoding: data, as: UTF8.self)
        for role in ThreadOSHistoricalAttributionDecoder.canonicalRoles {
            let value = ThreadOSHistoricalAttributionDecoder.decode(Data(text.replacingOccurrences(of: "DEVELOPMENT", with: role).utf8), now: Date(timeIntervalSince1970: 1))
            #expect(value.sourceStatus == .available)
            #expect(value.rows.count == 1)
            #expect(value.unavailableCount == 2)
            #expect(value.rows.first?.localRole == role)
        }
        let unknown = ThreadOSHistoricalAttributionDecoder.decode(Data(text.replacingOccurrences(of: "DEVELOPMENT", with: "UNKNOWN").utf8), now: Date(timeIntervalSince1970: 1))
        #expect(unknown.sourceStatus == .malformed)
        #expect(unknown.rows.isEmpty)
    }

    @Test
    func rejectsCurrentOrUnboundedAttribution() {
        let data = Data("""
        {"schema":"threados.usage-attribution-export.v1","historical_only":false,"status":"COMPLETE","row_count":0,"unavailable_count":0,"rows":[]}
        """.utf8)
        #expect(ThreadOSHistoricalAttributionDecoder.decode(data, now: Date()).sourceStatus == .malformed)
    }

    @Test
    func matchesOnlyOneCompleteLocalIntervalToOneProducerRow() {
        let thread = String(repeating: "a", count: 64)
        let turn = String(repeating: "b", count: 64)
        let row = ThreadOSUsageAnalytics.Row(projectKey: "TOSUMA", projectRootDigest: String(repeating: "c", count: 64), taskID: "TU3", localRole: "Coder", threadDigest: thread, turnDigest: turn, observation: "validated historical journal observation", waveID: nil)
        let interval = ThreadOSLocalIntervalCandidate(
            disposition: .candidate, nativeThreadDigest: thread, turnDigest: turn,
            model: "gpt-5.6-terra", preceding: .init(inputTokens: 1, cachedInputTokens: 0, outputTokens: 1, totalTokens: 2), ending: .init(inputTokens: 2, cachedInputTokens: 0, outputTokens: 2, totalTokens: 4), startedAt: Date(timeIntervalSince1970: 1), endedAt: Date(timeIntervalSince1970: 2)
        )
        let analytics = ThreadOSUsageAnalytics(sourceStatus: .available, rows: [row], unavailableCount: 0, capturedAt: Date())
        #expect(ThreadOSHistoricalAttributionMatcher.uniquelyMatchedRow(for: interval, in: analytics) == row)
        #expect(ThreadOSHistoricalAttributionMatcher.uniquelyMatchedRow(for: interval, in: .init(sourceStatus: .truncated, rows: [row], unavailableCount: 0, capturedAt: Date())) == nil)
        #expect(ThreadOSHistoricalAttributionMatcher.uniquelyMatchedRow(for: interval, in: .init(sourceStatus: .available, rows: [], unavailableCount: 0, capturedAt: Date())) == nil)
        #expect(ThreadOSHistoricalAttributionMatcher.uniquelyMatchedRow(for: interval, in: .init(sourceStatus: .available, rows: [row, row], unavailableCount: 0, capturedAt: Date())) == nil)
    }

    @Test
    func decodesFrozenR7CompleteAndWithholdsTruncatedEconomics() throws {
        let complete = try fixture("r7-48-complete-output.json")
        let truncated = try fixture("r7-49-truncated-output.json")
        let completeValue = ThreadOSHistoricalAttributionDecoder.decode(complete, now: Date(timeIntervalSince1970: 1))
        let truncatedValue = ThreadOSHistoricalAttributionDecoder.decode(truncated, now: Date(timeIntervalSince1970: 1))
        #expect(completeValue.sourceStatus == .available)
        #expect(!completeValue.rows.isEmpty)
        #expect(truncatedValue.sourceStatus == .truncated)
        let row = try #require(truncatedValue.rows.first)
        let interval = ThreadOSLocalIntervalCandidate(disposition: .candidate, nativeThreadDigest: row.threadDigest, turnDigest: row.turnDigest, model: "gpt-5.6-terra", preceding: .init(inputTokens: 1, cachedInputTokens: 0, outputTokens: 1, totalTokens: 2), ending: .init(inputTokens: 2, cachedInputTokens: 0, outputTokens: 2, totalTokens: 4), startedAt: Date(timeIntervalSince1970: 1), endedAt: Date(timeIntervalSince1970: 2))
        #expect(ThreadOSHistoricalAttributionMatcher.uniquelyMatchedRow(for: interval, in: truncatedValue) == nil)
    }

    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ThreadOS")
        return try Data(contentsOf: root.appendingPathComponent(name))
    }
}
