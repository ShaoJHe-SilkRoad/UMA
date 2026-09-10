import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Factorium V2 activation lifecycle")
struct FactoriumV2ActivationLifecycleTests {
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

    private func fixture() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/CodexUsageUITests/Fixtures/ThreadOS/activation-lifecycle-v2.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(data: data, encoding: .utf8)!
    }
}
