import Foundation
import Testing
@testable import CodexUsageUI

struct ThreadOSIntervalDecoderTests {
    @Test
    func acceptsNestedLifecycleEventsAndFailsClosedWithoutADeltaBaseline() throws {
        let intervals = ThreadOSLocalIntervalDecoder.decode(lines: try lines([
            #"{"type":"session_meta","payload":{"id":"native-thread-1"}}"#,
            #"{"type":"event_msg","timestamp":100,"payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            #"{"type":"event_msg","timestamp":101,"payload":{"type":"turn_context","turn_id":"turn-1","model":"gpt-5.6-terra"}}"#,
            #"{"type":"event_msg","timestamp":102,"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3,"total_tokens":13}}}}"#,
            #"{"type":"event_msg","timestamp":103,"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":15,"cached_input_tokens":3,"output_tokens":5,"total_tokens":20}}}}"#
        ]))

        #expect(intervals.map(\.disposition) == [.sourceGap, .candidate])
        #expect(intervals[1].preceding?.totalTokens == 13)
        #expect(intervals[1].ending?.totalTokens == 20)
    }

    @Test
    func projectsOnlyACompleteOrderedTurnInterval() throws {
        let intervals = ThreadOSLocalIntervalDecoder.decode(lines: try lines([
            #"{"type":"session_meta","payload":{"id":"native-thread-1"}}"#,
            #"{"type":"task_started","timestamp":100,"payload":{"turn_id":"turn-1"}}"#,
            #"{"type":"turn_context","timestamp":101,"payload":{"turn_id":"turn-1","model":"gpt-5.6-terra"}}"#,
            #"{"type":"event_msg","timestamp":102,"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3,"total_tokens":13}}}}"#,
            #"{"type":"event_msg","timestamp":103,"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":15,"cached_input_tokens":3,"output_tokens":5,"total_tokens":20}}}}"#
        ]))

        #expect(intervals.count == 2)
        #expect(intervals[0].disposition == .sourceGap)
        #expect(intervals[1].disposition == .candidate)
        #expect(intervals[1].model == "gpt-5.6-terra")
        #expect(intervals[1].preceding?.totalTokens == 13)
        #expect(intervals[1].ending?.totalTokens == 20)
        #expect(intervals[1].nativeThreadDigest?.contains("native-thread-1") == false)
        #expect(intervals[1].turnDigest?.contains("turn-1") == false)
    }

    @Test
    func rejectsDeltasThatCrossOrConflictWithTurnContext() throws {
        let intervals = ThreadOSLocalIntervalDecoder.decode(lines: try lines([
            #"{"type":"session_meta","payload":{"id":"native-thread-1"}}"#,
            #"{"type":"task_started","timestamp":100,"payload":{"turn_id":"turn-1"}}"#,
            #"{"type":"turn_context","timestamp":101,"payload":{"turn_id":"turn-1","model":"gpt-5.6-terra"}}"#,
            #"{"type":"event_msg","timestamp":102,"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"total_tokens":2}}}}"#,
            #"{"type":"turn_context","timestamp":103,"payload":{"turn_id":"turn-2","model":"gpt-5.6-sol"}}"#,
            #"{"type":"event_msg","timestamp":104,"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2,"cached_input_tokens":0,"output_tokens":2,"total_tokens":4}}}}"#
        ]))

        #expect(intervals.map(\.disposition) == [.sourceGap, .ambiguous])
        #expect(intervals[1].turnDigest != intervals[0].turnDigest)
    }

    private func lines(_ values: [String]) throws -> [Data] {
        try values.map { try #require($0.data(using: .utf8)) }
    }
}
