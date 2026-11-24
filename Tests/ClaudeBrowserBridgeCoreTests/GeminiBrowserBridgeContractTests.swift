import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import ClaudeSafariHostIPC
import Foundation
import Testing

/// The Gemini observation crosses the same bridge as Claude's. Only fixed
/// identifiers, a period, a bounded percentage, a reset timestamp and an
/// allowlisted plan word are admitted, and a Claude packet is unchanged.
@Suite("Gemini browser bridge contract")
struct GeminiBrowserBridgeContractTests {
    private static let requestID = "44444444-4444-4444-8444-444444444444"
    private static let generation = "3828ea01-d15a-47dc-8d2b-9ee20967da71"

    private func bucketJSON(
        _ id: String = "weekly",
        period: String = "weekly",
        used: Double = 4,
        reset: String? = "2026-11-25T00:00:00Z",
        extra: String = ""
    ) -> String {
        let resetField = reset.map { "\"\($0)\"" } ?? "null"
        return """
        {"bucketID":"\(id)","period":"\(period)","usedPercentage":\(used),"resetAt":\(resetField)\(extra)}
        """
    }

    private func envelopeJSON(
        buckets: [String]? = nil,
        plan: String = "\"pro\"",
        kind: String = "geminiUsageObservation",
        sourceID: String = "gemini-browser-usage"
    ) -> Data {
        let list = (buckets ?? [bucketJSON()]).joined(separator: ",")
        return Data("""
        {"kind":"\(kind)","schemaVersion":1,"sourceID":"\(sourceID)","browserFamily":"safari",
         "routeState":"verifiedUsage","requestID":"\(Self.requestID)",
         "observationID":"66666666-6666-4666-8666-666666666666",
         "observation":{"buckets":[\(list)],"planLabel":\(plan),
           "observedAt":"2026-11-24T05:00:00.000Z","extractorSchemaVersion":1,"sourceLayoutVersion":1}}
        """.utf8)
    }

    private func envelope() throws -> GeminiBrowserObservationEnvelope {
        try GeminiBrowserMessageDecoder.decode(envelopeJSON())
    }

    @Test("A valid Gemini observation decodes and round-trips")
    func validObservationDecodes() throws {
        let decoded = try envelope()
        #expect(decoded.observation.buckets == [GeminiBrowserBucket(
            bucketID: "weekly", period: .weekly, usedPercentage: 4, resetAt: "2026-11-25T00:00:00Z"
        )])
        #expect(decoded.observation.planLabel == "pro")
        let again = try GeminiBrowserMessageDecoder.decode(GeminiBrowserMessageDecoder.encode(decoded))
        #expect(again == decoded)
    }

    @Test("Page text can never become a bucket, period or plan")
    func onlyAllowlistedValuesPass() {
        let rejected: [Data] = [
            envelopeJSON(buckets: [bucketJSON("My secret chat title")]),
            envelopeJSON(buckets: [bucketJSON(period: "monthly")]),
            envelopeJSON(plan: "\"Workspace Enterprise\""),
            envelopeJSON(buckets: [bucketJSON(extra: ",\"label\":\"Gemini 3 Pro\"")]),
            envelopeJSON(buckets: [bucketJSON(used: 140)]),
            envelopeJSON(buckets: [bucketJSON(reset: "tomorrow")]),
            envelopeJSON(buckets: []),
            envelopeJSON(buckets: [bucketJSON("weekly"), bucketJSON("weekly")]),
            envelopeJSON(buckets: [bucketJSON("pro")]),
            envelopeJSON(kind: "claudeUsageObservation"),
            envelopeJSON(sourceID: "claude-browser-usage"),
        ]
        for data in rejected {
            #expect(throws: ClaudeBrowserBridgeError.self) {
                try GeminiBrowserMessageDecoder.decode(data)
            }
        }
    }

    @Test("More buckets than the contract allows are refused")
    func bucketCountIsBounded() throws {
        let buckets = (0...GeminiBrowserContract.maximumBuckets).map { _ in
            GeminiBrowserBucket(bucketID: "current", period: .unknown, usedPercentage: 1)
        }
        let envelope = GeminiBrowserObservationEnvelope(
            observation: .init(buckets: buckets, observedAt: "2026-11-24T05:00:00Z"),
            requestID: Self.requestID
        )
        #expect(throws: ClaudeBrowserBridgeError.self) {
            try GeminiBrowserMessageDecoder.validate(envelope)
        }
    }

    @Test("A terminal packet completes with exactly one provider's observation")
    func terminalCarriesOneObservation() throws {
        let gemini = try envelope()
        let packet = ClaudeBrowserTerminalPacket(
            requestID: Self.requestID,
            runtimeGenerationID: Self.generation,
            status: .refreshCompleted,
            occurredAt: "2026-11-24T05:00:01Z",
            geminiObservation: gemini
        )
        let decoded = try ClaudeBrowserTerminalPacketDecoder.decode(
            ClaudeBrowserTerminalPacketDecoder.encode(packet)
        )
        #expect(decoded.geminiObservation == gemini)
        #expect(decoded.observation == nil)

        let none = ClaudeBrowserTerminalPacket(
            requestID: Self.requestID, runtimeGenerationID: Self.generation,
            status: .refreshCompleted, occurredAt: "2026-11-24T05:00:01Z"
        )
        #expect(throws: ClaudeBrowserBridgeError.self) {
            try ClaudeBrowserTerminalPacketDecoder.validate(none)
        }
        let failure = ClaudeBrowserTerminalPacket(
            requestID: Self.requestID, runtimeGenerationID: Self.generation,
            status: .usageUnavailable, occurredAt: "2026-11-24T05:00:01Z",
            geminiObservation: gemini
        )
        #expect(throws: ClaudeBrowserBridgeError.self) {
            try ClaudeBrowserTerminalPacketDecoder.validate(failure)
        }
    }

    @Test("A Claude terminal packet never encodes the Gemini field")
    func claudePacketBytesAreUnchanged() throws {
        let packet = ClaudeBrowserTerminalPacket(
            requestID: Self.requestID, runtimeGenerationID: Self.generation,
            status: .tabUnavailable, occurredAt: "2026-11-24T05:00:01Z"
        )
        let data = try ClaudeBrowserTerminalPacketDecoder.encode(packet)
        #expect(!String(decoding: data, as: UTF8.self).contains("geminiObservation"))
    }

    @Test("An IPC read names its provider; only reads may")
    func ipcRequestProvider() {
        let gemini = ClaudeSafariHostIPCRequest(
            runtimeGenerationID: Self.generation, operation: .automaticRefresh, provider: .gemini
        )
        #expect(gemini.isStructurallyValid)
        #expect(gemini.readProvider == .gemini)
        let claude = ClaudeSafariHostIPCRequest(
            runtimeGenerationID: Self.generation, operation: .automaticRefresh
        )
        #expect(claude.readProvider == .claude)
        #expect(!ClaudeSafariHostIPCRequest(
            runtimeGenerationID: Self.generation, operation: .verifyCompanion, provider: .gemini
        ).isStructurallyValid)
        #expect(!ClaudeSafariHostIPCRequest(
            runtimeGenerationID: Self.generation, operation: .closeOwnedTab,
            targetRequestID: Self.requestID, provider: .gemini
        ).isStructurallyValid)
    }

    @Test("An IPC response completes with a Gemini observation, never with both providers'")
    func ipcResponseObservation() throws {
        let gemini = try envelope()
        let event = ClaudeBrowserAutomationEvent(
            requestID: Self.requestID, status: .refreshCompleted, occurredAt: "2026-11-24T05:00:01Z"
        )
        #expect(ClaudeSafariHostIPCResponse(
            requestID: Self.requestID, runtimeGenerationID: Self.generation,
            outcome: .completed, geminiObservation: gemini, automationEvent: event
        ).isStructurallyValid)
        let claude = ClaudeBrowserObservationEnvelope(
            browserFamily: .safari,
            observation: .init(
                fiveHour: .init(usedPercentage: 10), weeklyAllModels: nil,
                observedAt: "2026-11-24T05:00:00Z"
            ),
            requestID: Self.requestID
        )
        #expect(!ClaudeSafariHostIPCResponse(
            requestID: Self.requestID, runtimeGenerationID: Self.generation,
            outcome: .completed, observation: claude, geminiObservation: gemini,
            automationEvent: event
        ).isStructurallyValid)
        #expect(!ClaudeSafariHostIPCResponse(
            requestID: Self.requestID, runtimeGenerationID: Self.generation,
            outcome: .automation, geminiObservation: gemini, automationEvent: event
        ).isStructurallyValid)
    }
}
