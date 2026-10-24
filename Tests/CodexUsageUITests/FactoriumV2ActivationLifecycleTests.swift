import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Factorium V2 activation lifecycle")
struct FactoriumV2ActivationLifecycleTests {
    @Test @MainActor func explicitStandardFastStandardTransitionRetainsChildSemanticsAndRejectsCollapsedSpeedValues() throws {
        let fixture = try transitionFixture()
        let valid = try #require(fixture["valid"] as? [String: String])
        let invalid = try #require(fixture["invalid"] as? [String: String])
        let standard = try #require(valid["standard"])
        let fast = try #require(valid["fast"])
        let standardAgain = try #require(valid["standard_again"])
        let standardDraft = try FactoriumV2SettingsCodec.draft(fromWire: standard)
        let fastDraft = try FactoriumV2SettingsCodec.draft(fromWire: fast)
        let standardAgainDraft = try FactoriumV2SettingsCodec.draft(fromWire: standardAgain)

        #expect(try standardDraft.canonicalRequest() == standard)
        #expect(try fastDraft.canonicalRequest() == fast)
        #expect(try standardAgainDraft.canonicalRequest() == standardAgain)
        #expect([standardDraft, fastDraft, standardAgainDraft].map(\.revision) == [1, 2, 3])
        #expect([standardDraft, fastDraft, standardAgainDraft].map { $0.roles[.coder]?.selection.speed } == ["standard", "fast", "standard"])
        #expect(standardDraft.coderWorkers[0].inherits && standardDraft.resolvedSlot(standardDraft.coderWorkers[0], parent: .coder).speed == "standard")
        #expect(fastDraft.coderWorkers[0].inherits && fastDraft.resolvedSlot(fastDraft.coderWorkers[0], parent: .coder).speed == "fast")
        #expect(standardAgainDraft.coderWorkers[0].inherits && standardAgainDraft.resolvedSlot(standardAgainDraft.coderWorkers[0], parent: .coder).speed == "standard")
        #expect(!standardAgainDraft.coderWorkers[1].enabled && !standardAgainDraft.coderWorkers[1].inherits && standardAgainDraft.coderWorkers[1].selection.speed == "standard")
        #expect(standardAgainDraft.coderWorkers[2].enabled && !standardAgainDraft.coderWorkers[2].inherits && standardAgainDraft.coderWorkers[2].selection.speed == "fast")

        for wire in invalid.values {
            #expect(removingCoderSpeed(from: wire) == removingCoderSpeed(from: standard))
            #expect(throws: (any Error).self) {
                try FactoriumV2SettingsCodec.draft(fromWire: wire)
            }
        }

        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(standardDraft, to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        form.reportCopy(success: true, language: .english)
        form.edit { $0.roles[.coder]?.selection.speed = "fast" }
        #expect(form.draft.revision == 2)
        #expect(form.requiresStandardConversion)
        #expect(throws: FactoriumV2SettingsError.legacyFastConversionRequired) { try form.generatedRequest() }
        #expect(form.copiedRevision == nil && form.receipt == nil && form.rawAcknowledgement.isEmpty)
        let generated = try form.generatedRequestForTransfer()
        #expect(form.draft.revision == 3)
        #expect(!form.requiresStandardConversion)
        // A transfer's text is the settings line plus the standing
        // authorization, which is what the Copy control says it produces.
        // Asserting equality predates that line being appended.
        #expect(generated.text == generated.settingsLine + "\n"
            + FactoriumV2FormState.leaderTransferAuthorization)
        #expect(try form.draft.canonicalRequest().contains("\"fast\"") == false)
        #expect(try ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: standardDraft.project, from: preferences)?.canonicalRequest() == fast)
    }

    @Test @MainActor func matchingPendingReceiptIsInvalidatedByEditAndCannotBeReused() throws {
        let fixture = try fixture()
        let request = try #require(fixture["request"] as? [String: Any])
        let receipt = try #require(fixture["receipt"] as? [String: Any])
        let draft = try FactoriumV2SettingsCodec.draft(fromWire: "TOSCFG/2 " + json(request))

        #expect(draft.project == "PROJECT_ACTIVATION" && draft.id == "cfg-activation-test")
        #expect(draft.roles[.leader]?.preserve == true)
        #expect(draft.roles[.coder]?.selection == .init(model: "gpt-5.6-terra", effort: "medium", speed: "fast"))
        #expect(draft.roles[.qa]?.selection == .init(model: "gpt-6-astra", effort: "high", speed: "standard"))
        #expect(draft.coderWorkers.allSatisfy { !$0.inherits && $0.selection == .init(model: "gpt-5.6-terra", effort: "low", speed: "fast") })
        #expect(draft.reviewerWorkers.allSatisfy { $0.inherits && draft.resolvedSlot($0, parent: .reviewer) == .init(model: "gpt-5.6-terra", effort: "medium", speed: "fast") })

        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        form.reportCopy(success: true, language: .english)
        form.rawAcknowledgement = "TOSACK/2 " + json(receipt)
        form.receiveReceipt(language: .english)
        #expect(form.receipt != nil && !form.receiptInputIsInvalid)
        #expect(form.roleStatus(language: .english).contains("pending native") && form.roleStatus(language: .english).contains("UNKNOWN"))

        let receiptBeforeEdit = form.receipt
        form.edit { $0.roles[.repair]?.selection.speed = "standard" }
        let edited = form.draft
        #expect(edited.revision == 2)
        #expect(form.copiedRevision == nil && form.rawAcknowledgement.isEmpty && form.receipt == nil && !form.receiptInputIsInvalid)
        #expect(form.roleStatus(language: .english).contains("Local draft"))

        form.rawAcknowledgement = "TOSACK/2 " + json(receipt)
        form.receiveReceipt(language: .english)
        #expect(receiptBeforeEdit != nil && form.receipt == nil && form.receiptInputIsInvalid)
        #expect(form.draft == edited)
        #expect(form.roleStatus(language: .english).contains("Local draft"))
    }

    @Test @MainActor func transferArchivesDistinctFastDraftsWithoutOverwritingHistoryOrReplayingConversion() throws {
        let preferences = ApplicationPreferences.inMemory()
        var historical = FactoriumV2SettingsDraft(project: "ARCHIVE_ALPHA", id: "cfg-history")
        historical.roles[.coder]?.selection.speed = "fast"
        var current = FactoriumV2SettingsDraft(project: "ARCHIVE_ALPHA", id: "cfg-current")
        current.roles[.repair]?.selection.speed = "fast"
        let v1Key = ApplicationPreferenceKey<Data?>(optionalData: "threados.factorium.v2.legacy-snapshots.v1")
        let v2Key = ApplicationPreferenceKey<Data?>(optionalData: "threados.factorium.v2.legacy-snapshots.v2")
        preferences.set(try JSONEncoder().encode(["ARCHIVE_ALPHA": historical]), for: v1Key)
        ThreadOSSettingsPreferences.saveFactoriumV2(current, to: preferences)

        let form = FactoriumV2FormState(preferences: preferences)
        let previewRevision = form.draft.revision
        #expect(throws: FactoriumV2SettingsError.legacyFastConversionRequired) { try form.generatedRequest() }
        #expect(form.draft == current && form.draft.revision == previewRevision)

        let first = try form.generatedRequestForTransfer()
        #expect(first.text == first.settingsLine + "\n"
            + FactoriumV2FormState.leaderTransferAuthorization)
        #expect(form.draft.revision == previewRevision + 1)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshots(project: "ARCHIVE_ALPHA", from: preferences) == [historical, current])

        let persistedHistory = preferences.value(for: v2Key)
        ThreadOSSettingsPreferences.saveFactoriumV2LegacySnapshot(current, to: preferences)
        #expect(preferences.value(for: v2Key) == persistedHistory)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshots(project: "ARCHIVE_ALPHA", from: preferences) == [historical, current])

        let repeatRequest = try form.generatedRequestForTransfer()
        #expect(repeatRequest == first && form.draft.revision == previewRevision + 1)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshots(project: "ARCHIVE_ALPHA", from: preferences) == [historical, current])
    }

    @Test @MainActor func transferAtRevisionLimitDoesNotArchiveOrMutate() throws {
        let preferences = ApplicationPreferences.inMemory()
        var draft = FactoriumV2SettingsDraft(project: "LIMIT_ALPHA", id: "cfg-limit", revision: 1_000_000)
        draft.roles[.coder]?.selection.speed = "fast"
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)

        #expect(throws: FactoriumV2SettingsError.invalidRevision) { try form.generatedRequestForTransfer() }
        #expect(form.draft == draft)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshots(project: "LIMIT_ALPHA", from: preferences).isEmpty)
    }

    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/CodexUsageUITests/Fixtures/ThreadOS/activation-lifecycle-v2.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func transitionFixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/CodexUsageUITests/Fixtures/ThreadOS/fast-on-off-transitions-v2.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func removingCoderSpeed(from wire: String) -> String {
        let prefix = "TOSCFG/2 "
        var request = try! JSONSerialization.jsonObject(with: Data(wire.dropFirst(prefix.count).utf8)) as! [String: Any]
        var roles = request["roles"] as! [String: Any]
        var coder = roles["coder"] as! [String: Any]
        coder.removeValue(forKey: "speed")
        roles["coder"] = coder
        request["roles"] = roles
        let data = try! JSONSerialization.data(withJSONObject: request, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }

    private func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }
}
