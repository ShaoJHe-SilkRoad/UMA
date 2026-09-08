import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Factorium V2 frozen producer parity")
struct FactoriumV2GoldenParityTests {
    @Test func frozenFixtureHasTheProducerBoundDigestAndDeclaredCoverage() throws {
        let fixture = try object()
        let vectors = try #require(fixture["vectors"] as? [[String: Any]])
        let sequences = try #require(fixture["sequences"] as? [[String: Any]])
        #expect(vectors.count == 71)
        #expect(vectors.filter { $0["canonical_expected"] != nil }.count == 7)
        #expect(vectors.filter { $0["expected_error"] != nil }.count == 64)
        // Ordered ledger/wave sequences are producer-runtime behavior. UMA
        // reads their frozen shape but does not emulate ThreadOS persistence.
        #expect(sequences.count == 4)
    }

    @Test func swiftCanonicalizesEveryApplicableFrozenRequestAndValidatesEveryFrozenAck() throws {
        let vectors = try #require(object()["vectors"] as? [[String: Any]])
        let successful = vectors.filter { $0["canonical_expected"] != nil }
        for vector in successful {
            let name = vector["name"] as? String ?? "unnamed"
            let input = try #require(vector["input"] as? String)
            let expected = try #require(vector["canonical_expected"] as? String)
            let ack = try #require(vector["canonical_ack"] as? String)
            let draft: FactoriumV2SettingsDraft
            do { draft = try FactoriumV2SettingsCodec.draft(fromWire: input) }
            catch { Issue.record("request parse mismatch: \(name): \(error)"); continue }
            #expect(try draft.canonicalRequest() == expected, "canonical request mismatch: \(name)")
            let projection: FactoriumV2ReceiptProjection
            do { projection = try FactoriumV2SettingsCodec.receiptProjection(ack, matching: draft) }
            catch { Issue.record("receipt mismatch: \(name): \(error)"); continue }
            #expect(projection.project == draft.project && projection.id == draft.id && projection.revision == draft.revision && projection.effectiveObserved == "unknown", "receipt mismatch: \(name)")
        }
    }

    @Test func swiftRejectsEveryProducerNegativeRequestVectorBeforeLocalReceiptState() throws {
        let vectors = try #require(object()["vectors"] as? [[String: Any]])
        for vector in vectors.filter({ $0["expected_error"] != nil }) {
            let name = vector["name"] as? String ?? "unnamed"
            let input = try #require(vector["input"] as? String)
            #expect(throws: (any Error).self, "negative request accepted: \(name)") {
                try FactoriumV2SettingsCodec.draft(fromWire: input, expectedProject: "PROJECT_DEMO")
            }
        }
    }

    @Test @MainActor func foreignOrStaleAcknowledgementsDoNotReplaceTheCurrentLocalDraft() throws {
        let vectors = try #require(object()["vectors"] as? [[String: Any]])
        let value = try #require(vectors.first { $0["name"] as? String == "default_inheritance" })
        let input = try #require(value["input"] as? String)
        let ack = try #require(value["canonical_ack"] as? String)
        let preferences = ApplicationPreferences.inMemory()
        let current = try FactoriumV2SettingsCodec.draft(fromWire: input)
        ThreadOSSettingsPreferences.saveFactoriumV2(current, to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        form.rawAcknowledgement = ack.replacingOccurrences(of: "\"rev\":1", with: "\"rev\":2")
        form.receiveReceipt(language: .english)
        #expect(form.receipt == nil && form.receiptInputIsInvalid)
        #expect(form.draft == current)
    }

    @Test func rejectsUnknownFieldsInEveryExplicitConfiguredRole() throws {
        let vectors = try #require(object()["vectors"] as? [[String: Any]])
        let ordinary = try #require(vectors.first { $0["name"] as? String == "default_inheritance" })
        let explicitLeader = try #require(vectors.first { $0["name"] as? String == "leader_explicit_ultra" })
        for role in ["coder", "qa", "repair", "reviewer"] {
            let input = try #require(ordinary["input"] as? String)
            let ack = try #require(ordinary["canonical_ack"] as? String)
            let draft = try FactoriumV2SettingsCodec.draft(fromWire: input)
            #expect(throws: (any Error).self, "unexpected configured role field accepted: \(role)") {
                try FactoriumV2SettingsCodec.receiptProjection(try acknowledgement(ack, mutate: { object in
                    var configured = try #require(object["configured"] as? [String: Any])
                    var roles = try #require(configured["roles"] as? [String: Any])
                    var selection = try #require(roles[role] as? [String: Any])
                    selection["unexpected"] = true
                    roles[role] = selection; configured["roles"] = roles; object["configured"] = configured
                }), matching: draft)
            }
        }
        let input = try #require(explicitLeader["input"] as? String)
        let ack = try #require(explicitLeader["canonical_ack"] as? String)
        let draft = try FactoriumV2SettingsCodec.draft(fromWire: input)
        #expect(throws: (any Error).self, "unexpected explicit leader field accepted") {
            try FactoriumV2SettingsCodec.receiptProjection(try acknowledgement(ack, mutate: { object in
                var configured = try #require(object["configured"] as? [String: Any])
                var roles = try #require(configured["roles"] as? [String: Any])
                var selection = try #require(roles["leader"] as? [String: Any])
                selection["unexpected"] = true
                roles["leader"] = selection; configured["roles"] = roles; object["configured"] = configured
            }), matching: draft)
        }
    }

    @Test @MainActor func malformedAcknowledgementsNeverMutateTheCurrentDraft() throws {
        let vectors = try #require(object()["vectors"] as? [[String: Any]])
        let value = try #require(vectors.first { $0["name"] as? String == "default_inheritance" })
        let input = try #require(value["input"] as? String)
        let baselineAcknowledgement = try #require(value["canonical_ack"] as? String)
        let current = try FactoriumV2SettingsCodec.draft(fromWire: input)
        for mutation in ["status", "rev", "p"] {
            let preferences = ApplicationPreferences.inMemory()
            ThreadOSSettingsPreferences.saveFactoriumV2(current, to: preferences)
            let form = FactoriumV2FormState(preferences: preferences)
            form.rawAcknowledgement = try acknowledgement(baselineAcknowledgement, mutate: { object in
                if mutation == "rev" { object[mutation] = 2 }
                else { object[mutation] = "spoofed" }
            })
            form.receiveReceipt(language: .english)
            #expect(form.receipt == nil && form.receiptInputIsInvalid, "invalid \(mutation) acknowledgement was accepted")
            #expect(form.draft == current, "invalid \(mutation) acknowledgement mutated draft")
        }
    }

    private func object() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Tests/CodexUsageUITests/Fixtures/ThreadOS/settings-v2-golden.json")
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func acknowledgement(_ text: String, mutate: (inout [String: Any]) throws -> Void) throws -> String {
        let json = String(text.dropFirst("TOSACK/2 ".count))
        var object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        try mutate(&object)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return "TOSACK/2 " + (try #require(String(data: data, encoding: .utf8)))
    }
}
