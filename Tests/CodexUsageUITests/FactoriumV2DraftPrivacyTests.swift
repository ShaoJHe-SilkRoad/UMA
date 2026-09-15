import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Factorium V2 local draft privacy")
@MainActor
struct FactoriumV2DraftPrivacyTests {
    @Test func standardResetArtifactIsBoundDeterministicAndClearedAcrossCompositions() throws {
        let preferences = ApplicationPreferences.inMemory()
        let draft = FactoriumV2SettingsDraft(project: "RESET_ALPHA", id: "cfg-reset-alpha")
        #expect(FactoriumV2Role.allCases.allSatisfy { draft.roles[$0]?.selection.speed == "standard" })
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)

        #expect(!form.includesProjectStandardReset && !form.canIncludeProjectStandardReset)
        form.setLeaderRecipient("01a07317-57f9-7283-8cb2-81357a899560")
        form.setProjectStandardResetIncluded(true)
        let first = try form.generatedRequest()
        let second = try form.generatedRequest()
        #expect(first == second)
        #expect(first.settingsLine.hasPrefix("TOSCFG/2 "))
        #expect(first.text.hasPrefix(first.settingsLine + "\n\n--- TOSUMA PROJECT STANDARD RESET v1 ---"))
        #expect(first.text.contains("Recipient: 01a07317-57f9-7283-8cb2-81357a899560"))
        #expect(first.text.contains("Disposition: if no proven target-isolated primitive exists, return UNSUPPORTED_TARGETED_RESET without host mutation."))
        #expect(first.intentSHA256 != nil && first.artifactSHA256.count == 64)

        form.reportCopy(first, success: true, language: .english)
        #expect(form.copiedArtifactSHA256 == first.artifactSHA256)
        form.setLeaderRecipient("LEADER_CHANGED")
        #expect(!form.includesProjectStandardReset && form.copiedRevision == nil)
        form.reportCopy(first, success: true, language: .english)
        #expect(form.copiedRevision == nil && form.message.contains("stale"))
        form.setProjectStandardResetIncluded(true)
        form.edit { $0.roles[.repair]?.selection.effort = "low" }
        #expect(form.copiedRevision == nil && form.copiedArtifactSHA256 == nil)
        form.select(project: "")
        #expect(!form.includesProjectStandardReset && form.leaderRecipient.isEmpty)
    }

    @Test func partialNumericUUIDCanBeEditedButCannotEnableResetUntilComplete() {
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(.init(project: "UUID_ALPHA", id: "cfg-uuid-alpha"), to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        form.setLeaderRecipient("01a0")
        #expect(form.leaderRecipientInput == "01a0" && !form.canIncludeProjectStandardReset && form.leaderRecipient.isEmpty)
        form.setLeaderRecipient("01a07317-57f9-7283-8cb2-81357a899560")
        #expect(form.canIncludeProjectStandardReset && form.leaderRecipient == "01a07317-57f9-7283-8cb2-81357a899560")
    }

    @Test func newCompositionClearsResetAndRejectsSameLineForgedCopy() throws {
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2(.init(project: "COMPOSE_ALPHA", id: "cfg-compose-alpha"), to: preferences)
        let form = FactoriumV2FormState(preferences: preferences)
        let first = try form.generatedRequest()
        form.reportCopy(first, success: true, language: .english)
        form.reportCopy(first, success: true, language: .english)
        #expect(form.copiedArtifactSHA256 == first.artifactSHA256)
        let forged = FactoriumV2GeneratedRequest(settingsLine: first.settingsLine, text: first.text + "\nforged", intentSHA256: first.intentSHA256, artifactSHA256: first.artifactSHA256)
        form.reportCopy(forged, success: true, language: .english)
        #expect(form.copiedRevision == nil)
        form.beginNewComposition()
        #expect(!form.includesProjectStandardReset && form.leaderRecipientInput.isEmpty && form.draft.revision == 2)
    }

    @Test func generatedV2RequestUsesOnlyTheConfigurationAllowlistAndCopyStateIsLocal() throws {
        let preferences = ApplicationPreferences.inMemory()
        var draft = FactoriumV2SettingsDraft(project: "PRIVACY_ALPHA", id: "cfg-privacy-alpha")
        draft.setSlotInheritance(false, at: 0, for: .coder)
        var slot = draft.coderWorkers[0].selection
        slot.effort = "high"
        draft.setSlotSelection(slot, at: 0, for: .coder)
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)

        let form = FactoriumV2FormState(preferences: preferences)
        let request = try form.generatedRequest()
        #expect(request.text.hasPrefix("TOSCFG/2 "))
        let data = try #require(request.text.dropFirst("TOSCFG/2 ".count).data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["apply", "cat", "id", "p", "preset", "rev", "roles", "workers"])
        #expect(object["p"] as? String == "PRIVACY_ALPHA")
        #expect(object["id"] as? String == "cfg-privacy-alpha")

        let roles = try #require(object["roles"] as? [String: [String: Any]])
        #expect(Set(roles.keys) == Set(FactoriumV2Role.allCases.map(\.rawValue)))
        #expect(Set(try #require(roles["leader"]).keys) == ["preserve"])
        for role in ["qa", "coder", "repair", "reviewer"] {
            #expect(Set(try #require(roles[role]).keys) == ["model", "effort", "speed"])
        }
        let workers = try #require(object["workers"] as? [String: [[String: Any]]])
        #expect(Set(workers.keys) == ["coder", "reviewer"])
        for slots in workers.values {
            #expect(slots.count == 3)
            #expect(slots.allSatisfy { Set($0.keys) == ["enabled", "model", "effort", "speed"] })
        }
        for excluded in ["rawAcknowledgement", "receipt", "copiedRevision", "message", "selectedProject", "expandedGroups"] {
            #expect(!request.text.contains(excluded))
        }

        form.reportCopy(success: true, language: .english)
        #expect(form.copiedRevision == form.draft.revision)
        form.rawAcknowledgement = "TOSACK/2 local-only-test-input"
        form.edit { $0.roles[.repair]?.selection.effort = "low" }
        #expect(form.copiedRevision == nil && form.rawAcknowledgement.isEmpty && form.receipt == nil)
        let saved = try #require(ThreadOSSettingsPreferences.loadFactoriumV2(project: "PRIVACY_ALPHA", from: preferences))
        #expect(saved == form.draft)
        #expect(try saved.canonicalRequest().contains("TOSACK/2") == false)
    }

    @Test func v2DraftsAndWorkerExpansionRemainPerProjectAcrossSwitchAndReopen() throws {
        let preferences = ApplicationPreferences.inMemory()
        let alpha = FactoriumV2SettingsDraft(project: "PRIVACY_ALPHA", id: "cfg-privacy-alpha")
        var beta = FactoriumV2SettingsDraft(project: "PRIVACY_BETA", id: "cfg-privacy-beta")
        beta.setSlotInheritance(false, at: 1, for: .reviewer)
        var betaSlot = beta.reviewerWorkers[1].selection
        betaSlot.effort = "medium"
        beta.setSlotSelection(betaSlot, at: 1, for: .reviewer)
        ThreadOSSettingsPreferences.saveFactoriumV2(alpha, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2(beta, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2ExpandedGroups([.coder], project: "PRIVACY_ALPHA", to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2ExpandedGroups([.repair, .reviewer], project: "PRIVACY_BETA", to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject("PRIVACY_ALPHA", to: preferences)

        let form = FactoriumV2FormState(preferences: preferences)
        #expect(form.selectedProject == "PRIVACY_ALPHA" && form.draft == alpha)
        form.edit { $0.roles[.coder]?.selection.effort = "low" }
        let editedAlpha = form.draft
        #expect(editedAlpha.revision == alpha.revision + 1)

        form.select(project: "PRIVACY_BETA")
        #expect(form.draft == beta)
        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "PRIVACY_ALPHA", from: preferences) == [.coder])
        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "PRIVACY_BETA", from: preferences) == [.repair, .reviewer])
        form.select(project: "PRIVACY_ALPHA")
        #expect(form.draft == editedAlpha)

        let reopened = FactoriumV2FormState(preferences: preferences)
        #expect(reopened.selectedProject == "PRIVACY_ALPHA" && reopened.draft == editedAlpha)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: "PRIVACY_BETA", from: preferences) == beta)
    }
}
