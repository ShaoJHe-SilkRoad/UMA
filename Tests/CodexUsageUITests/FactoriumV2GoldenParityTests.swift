import Foundation
import CryptoKit
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

    @Test func solLunaCatalogSupportsAllFourRequestedEffortsAndRejectsMalformedValues() throws {
        let catalog = try ThreadOSSettingsCodec.loadCatalog(revision: "sol-luna-20260922.1")
        for model in ["gpt-6-sol", "gpt-6-luna"] {
            #expect(catalog.models[model]?.reasoningEfforts == ["low", "medium", "high", "xhigh"])
            for effort in ["low", "medium", "high", "xhigh"] {
                var draft = FactoriumV2SettingsDraft(project: "SAGE_CATALOG", catalogRevision: catalog.revision)
                draft.setSelection(.init(model: model, effort: effort, speed: "standard"), for: .coder)
                #expect(draft.isLocallyValid, "\(model)/\(effort) should be valid")
            }
            for effort in ["", "ultra", "HIGH", "fast", "unknown"] {
                var draft = FactoriumV2SettingsDraft(project: "SAGE_CATALOG", catalogRevision: catalog.revision)
                draft.setSelection(.init(model: model, effort: effort, speed: "standard"), for: .coder)
                #expect(!draft.isLocallyValid, "malformed effort \(effort) should be rejected")
            }
        }
    }

    @Test func persistedDraftWithoutCatalogRevisionRemainsPinnedToTheLegacyCatalog() throws {
        // Built from the legacy catalog's own defaults. Using the current
        // ones left `.leader` and `.repair` on models that catalog never had,
        // so the draft was invalid before the test asserted anything.
        var legacyRoles = FactoriumV2SettingsDraft.defaultRoles(
            for: ThreadOSSettingsCodec.legacyCatalogRevision
        )
        legacyRoles[.qa] = .init(selection: .init(model: "gpt-6-astra", effort: "medium", speed: "standard"))
        legacyRoles[.coder] = .init(selection: .init(model: "gpt-5.6-terra", effort: "medium", speed: "standard"))
        legacyRoles[.reviewer] = .init(selection: .init(model: "gpt-5.6-terra", effort: "low", speed: "standard"))
        let draft = FactoriumV2SettingsDraft(project: "OLD_DRAFT", catalogRevision: ThreadOSSettingsCodec.legacyCatalogRevision, roles: legacyRoles)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        object.removeValue(forKey: "catalogRevision")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(FactoriumV2SettingsDraft.self, from: data)
        #expect(decoded.catalogRevision == ThreadOSSettingsCodec.legacyCatalogRevision)
        #expect(try decoded.canonicalRequest().contains("astra-20260904.1"))
    }

    @Test @MainActor func v2ModelSwitchPersistsAnExplicitEffortChoiceForRolesAndCustomChildren() throws {
        var draft = FactoriumV2SettingsDraft(project: "EXPLICIT_EFFORT")
        draft.setSelection(.init(model: "gpt-5.6-terra", effort: "ultra", speed: "standard"), for: .qa)
        draft.setSlotInheritance(false, at: 0, for: .coder)
        draft.setSlotSelection(.init(model: "gpt-5.6-terra", effort: "ultra", speed: "standard"), at: 0, for: .coder)
        #expect(draft.isLocallyValid)
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(draft.project, to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        form.select(project: draft.project)

        // Was gpt-6-sol, which the current catalog retires, so the edit was
        // correctly refused and the role never moved. The point here is what a
        // model switch does to an explicit effort, not which model it is.
        form.selectRoleModel("gpt-6-luna", role: .qa)
        form.selectSlotModel("gpt-6-luna", at: 0, for: .coder)
        #expect(form.draft.roles[.qa]?.selection == .init(model: "gpt-6-luna", effort: "", speed: "standard"))
        #expect(form.draft.coderWorkers[0].selection == .init(model: "gpt-6-luna", effort: "", speed: "standard"))
        #expect(throws: (any Error).self) { try form.generatedRequest() }

        form.edit(allowIncompleteEffort: true) { $0.roles[.qa]?.selection.effort = "high" }
        form.edit(allowIncompleteEffort: true) { $0.coderWorkers[0].selection.effort = "xhigh" }
        #expect(form.draft.isLocallyValid)
        // A default-constructed draft pins to the current catalog, which has
        // moved on from sol-luna-20260922.1 since this was written.
        #expect(try form.generatedRequest().settingsLine
            .contains(ThreadOSSettingsCodec.latestCatalogRevision))
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


    @Test func sharedSolLunaV2CrossLanguageRequestReceiptVectors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Tests/CodexUsageUITests/Fixtures/ThreadOS/sol-luna-v2.json")
        let fixtureData = try Data(contentsOf: url)
        #expect(SHA256.hash(data: fixtureData).map { String(format: "%02x", $0) }.joined() ==
                "d794b1b2b728647580407c2b8a76a26f434e96648a8dbb4d91f751560f3c2d3d")
        let catalogURL = root.appendingPathComponent("Sources/CodexUsageUI/Resources/ThreadOS/models.v2.json")
        let catalogData = try Data(contentsOf: catalogURL)
        #expect(SHA256.hash(data: catalogData).map { String(format: "%02x", $0) }.joined() ==
                "74b3da41ebca8e0c35aaf98ca4cc4ea3c362d436d2fd71896a2191bd7b1ba160")
        let fixture = try #require(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        #expect(fixture["catalog_revision"] as? String == "sol-luna-20260922.1")
        let vectors = try #require(fixture["vectors"] as? [[String: Any]])
        #expect(vectors.count == 8)
        for vector in vectors {
            let name = try #require(vector["name"] as? String)
            let input = try #require(vector["input"] as? String)
            let expected = try #require(vector["canonical_expected"] as? String)
            let ack = try #require(vector["canonical_ack"] as? String)
            let draft = try FactoriumV2SettingsCodec.draft(fromWire: input, expectedProject: "PROJECT_DEMO")
            #expect(try draft.canonicalRequest() == expected, "request mismatch: \(name)")
            let receipt = try FactoriumV2SettingsCodec.receiptProjection(ack, matching: draft)
            #expect(receipt.id == draft.id && receipt.revision == draft.revision)
            #expect(receipt.effectiveObserved == "unknown" && receipt.manualRequired)
        }
        let negative = try #require(fixture["negative"] as? [[String: Any]])
        #expect(negative.count == 2)
        for vector in negative {
            let name = try #require(vector["name"] as? String)
            let input = try #require(vector["input"] as? String)
            #expect(throws: (any Error).self, "negative vector accepted: \(name)") {
                _ = try FactoriumV2SettingsCodec.draft(fromWire: input)
            }
        }
    }

    @Test @MainActor func v2GenerateAndCopyUsesOnlyInjectedLocalClipboard() throws {
        let empty = FactoriumV2FormState(preferences: .inMemory())
        let invalidClipboard = ClipboardSpy()
        #expect(empty.generateAndCopy(to: invalidClipboard, language: .english) == nil)
        #expect(invalidClipboard.writes.isEmpty)
        #expect(empty.copiedRevision == nil)

        let draft = FactoriumV2SettingsDraft(project: "COPY_V2", catalogRevision: "sol-luna-20260922.1")
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(draft.project, to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        let generated = try form.generatedRequest()
        form.edit { $0.roles[.qa]?.selection.effort = "xhigh" }
        form.reportCopy(generated, success: true, language: .english)
        #expect(form.copiedRevision == nil)
        #expect(form.message.contains("stale"))

        let failingClipboard = ClipboardSpy(success: false)
        let failed = try #require(form.generateAndCopy(to: failingClipboard, language: .english))
        #expect(failingClipboard.writes == [failed.text])
        #expect(form.copiedRevision == nil)
        #expect(form.message.contains("clipboard could not be written"))

        form.edit { $0.roles[.coder]?.selection.speed = "fast" }
        let clipboard = ClipboardSpy()
        let normalized = try #require(form.generateAndCopy(to: clipboard, language: .english))
        #expect(clipboard.writes == [normalized.text])
        #expect(normalized.settingsLine.hasPrefix("TOSCFG/2 "))
        let transferLines = normalized.text.components(separatedBy: "\n")
        #expect(transferLines == [normalized.settingsLine, FactoriumV2FormState.leaderTransferAuthorization])
        #expect(normalized.text.components(separatedBy: FactoriumV2FormState.leaderTransferAuthorization).count - 1 == 1)
        #expect(try FactoriumV2SettingsCodec.draft(fromWire: normalized.settingsLine) == form.draft)
        let settingsOnly = try form.generatedRequest()
        #expect(settingsOnly.settingsLine == normalized.settingsLine)
        #expect(settingsOnly.text == normalized.settingsLine)
        #expect(settingsOnly.artifactSHA256 == normalized.artifactSHA256)
        let settingsDigest = SHA256.hash(data: Data(normalized.settingsLine.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(normalized.artifactSHA256 == settingsDigest)
        #expect(form.copiedArtifactSHA256 == settingsOnly.artifactSHA256)
        #expect(form.draft.roles[.coder]?.selection.speed == "standard")
        #expect(form.copiedRevision == form.draft.revision)
        #expect(!normalized.text.contains("\"speed\":\"fast\""))

        let secondCopy = ClipboardSpy()
        let repeated = try #require(form.generateAndCopy(to: secondCopy, language: .english))
        #expect(secondCopy.writes == [repeated.text])
        #expect(repeated.text.components(separatedBy: FactoriumV2FormState.leaderTransferAuthorization).count - 1 == 1)

        let unrelatedPreferences = ApplicationPreferences.inMemory()
        let unrelatedDraft = FactoriumV2SettingsDraft(project: "UNRELATED_PROJECT", catalogRevision: "sol-luna-20260922.1")
        ThreadOSSettingsPreferences.saveFactoriumV2(unrelatedDraft, to: unrelatedPreferences)
        let unrelatedForm = FactoriumV2FormState(preferences: unrelatedPreferences)
        let unrelatedClipboard = ClipboardSpy()
        let unrelatedCopy = try #require(unrelatedForm.generateAndCopy(to: unrelatedClipboard, language: .english))
        #expect(try FactoriumV2SettingsCodec.draft(fromWire: unrelatedCopy.settingsLine).project == "UNRELATED_PROJECT")
        #expect(unrelatedCopy.text.components(separatedBy: "\n") == [unrelatedCopy.settingsLine, FactoriumV2FormState.leaderTransferAuthorization])
    }

    @MainActor private final class ClipboardSpy: ThreadOSSettingsClipboard {
        var writes: [String] = []
        let success: Bool
        init(success: Bool = true) { self.success = success }
        func write(_ string: String) -> Bool { writes.append(string); return success }
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
