import Foundation
import Testing
@testable import CodexUsageUI

@MainActor
struct ThreadOSPromptComposerTests {
    private struct StoredSelection: Codable {
        let role: ThreadOSPromptRole
        let model: String
        let effort: String
    }
    private struct StoredSelections: Codable {
        let version: Int
        let selections: [StoredSelection]
    }
    private let expectedDefaults: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
        .leader: .init(model: "gpt-6.1-sol", effort: "high"),
        .coderCluster: .init(model: "gpt-6-luna", effort: "medium"),
        .reviewerCluster: .init(model: "gpt-6-luna", effort: "medium"),
        .qa: .init(model: "gpt-6.1-sol", effort: "high")
    ]

    @Test func roleSelectionsCanChangeIndependently() {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory())
        form.selectModel("gpt-6-astra", for: .leader)
        form.selectEffort("xhigh", for: .qa)

        #expect(form.selection(for: .leader) == .init(model: "gpt-6-astra", effort: "high"))
        #expect(form.selection(for: .coderCluster) == expectedDefaults[.coderCluster])
        #expect(form.selection(for: .reviewerCluster) == expectedDefaults[.reviewerCluster])
        #expect(form.selection(for: .qa) == .init(model: "gpt-6.1-sol", effort: "xhigh"))
        #expect(form.canGenerate)
    }

    @Test func summaryLinesReflectCurrentSelectionsInBothLanguages() {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory())
        form.selectModel("gpt-6-astra", for: .leader)
        form.selectEffort("low", for: .leader)
        form.selectModel("gpt-5.6-terra", for: .reviewerCluster)
        form.selectEffort("xhigh", for: .reviewerCluster)

        let english = ThreadOSPromptComposerSummary.lines(from: form.selections, language: .english)
        #expect(english == [
            "Leader · GPT-6 Astra / Low",
            "Coder Cluster · GPT-6 Luna / Medium",
            "Reviewer Cluster · GPT-5.6 Terra / Ex High",
            "QA · GPT-6.1 Sol / High"
        ])

        let chinese = ThreadOSPromptComposerSummary.lines(from: form.selections, language: .simplifiedChinese)
        #expect(chinese == [
            "Leader · GPT-6 Astra / 低",
            "Coder Cluster · GPT-6 Luna / 中",
            "Reviewer Cluster · GPT-5.6 Terra / 极高",
            "QA · GPT-6.1 Sol / 高"
        ])
    }

    @Test func preservesSavedSixSolSelectionsEffortsAndExistingRecoverySnapshotAcrossReopen() throws {
        let preferences = ApplicationPreferences.inMemory()
        let saved = StoredSelections(version: 1, selections: [
            .init(role: .leader, model: "gpt-6-sol", effort: "low"),
            .init(role: .coderCluster, model: "gpt-6-sol", effort: "medium"),
            .init(role: .reviewerCluster, model: "gpt-6-sol", effort: "high"),
            .init(role: .qa, model: "gpt-6-sol", effort: "xhigh")
        ])
        let original = try JSONEncoder().encode(saved)
        let oldSnapshot = Data("previous recovery snapshot".utf8)
        preferences.set(original as Data?, for: ThreadOSPromptComposerPreferences.selections)
        preferences.set(oldSnapshot as Data?, for: ThreadOSPromptComposerPreferences.legacySelections)

        let form = ThreadOSPromptComposerForm(preferences: preferences)
        #expect(form.selection(for: .leader) == .init(model: "gpt-6-sol", effort: "low"))
        #expect(form.selection(for: .coderCluster) == .init(model: "gpt-6-sol", effort: "medium"))
        #expect(form.selection(for: .reviewerCluster) == .init(model: "gpt-6-sol", effort: "high"))
        #expect(form.selection(for: .qa) == .init(model: "gpt-6-sol", effort: "xhigh"))
        #expect(form.canGenerate)
        #expect(form.statusMessage(language: .english) == nil)
        #expect(preferences.value(for: ThreadOSPromptComposerPreferences.selections) == original)
        #expect(preferences.value(for: ThreadOSPromptComposerPreferences.legacySelections) == oldSnapshot)

        let reopened = ThreadOSPromptComposerForm(preferences: preferences)
        #expect(reopened.selections == form.selections)
        #expect(reopened.canGenerate)
        #expect(preferences.value(for: ThreadOSPromptComposerPreferences.legacySelections) == oldSnapshot)
    }

    @Test func unsupportedSavedValuesRemainVisibleAndRequireExplicitCorrection() throws {
        let preferences = ApplicationPreferences.inMemory()
        let saved = StoredSelections(version: 1, selections: [
            .init(role: .leader, model: "gpt-6-sol", effort: "none"),
            .init(role: .coderCluster, model: "retired-unknown-model", effort: "none"),
            .init(role: .reviewerCluster, model: "gpt-6-astra", effort: "none"),
            .init(role: .qa, model: "gpt-6-sol", effort: "high")
        ])
        let original = try JSONEncoder().encode(saved)
        preferences.set(original as Data?, for: ThreadOSPromptComposerPreferences.selections)

        let form = ThreadOSPromptComposerForm(preferences: preferences)
        #expect(form.selection(for: .leader) == .init(model: "gpt-6-sol", effort: "none"))
        #expect(form.selection(for: .coderCluster) == .init(model: "retired-unknown-model", effort: "none"))
        #expect(form.selection(for: .reviewerCluster) == .init(model: "gpt-6-astra", effort: "none"))
        #expect(form.selection(for: .qa) == .init(model: "gpt-6-sol", effort: "high"))
        #expect(!form.canGenerate)
        #expect(form.statusMessage(language: .english)?.contains("Leader") == true)
        #expect(form.statusMessage(language: .english)?.contains("Coder Cluster") == true)
        #expect(form.statusMessage(language: .english)?.contains("Reviewer Cluster") == true)
        #expect(preferences.value(for: ThreadOSPromptComposerPreferences.selections) == original)

        let clipboard = ClipboardSpy()
        #expect(form.generateAndCopy(language: .english, to: clipboard) == .unavailable)
        #expect(clipboard.writes.isEmpty)

        form.selectModel("gpt-6-luna", for: .coderCluster)
        #expect(form.selection(for: .coderCluster) == .init(model: "gpt-6-luna", effort: "none"))
        #expect(!form.canGenerate)
        form.selectEffort("medium", for: .coderCluster)
        form.selectEffort("low", for: .leader)
        form.selectEffort("high", for: .reviewerCluster)
        #expect(form.canGenerate)
        #expect(form.selection(for: .qa) == .init(model: "gpt-6-sol", effort: "high"))
        #expect(preferences.value(for: ThreadOSPromptComposerPreferences.legacySelections) == nil)

        let reopened = ThreadOSPromptComposerForm(preferences: preferences)
        #expect(reopened.selections == form.selections)
        #expect(reopened.canGenerate)
    }

    @Test func sixSolSupportsEveryEffortForEachRoleInGeneratedCopiedPrompt() throws {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory())
        let clipboard = ClipboardSpy()
        let roles = ThreadOSPromptRole.allCases
        let efforts = ThreadOSLeaderPrompt.supportedEfforts

        for role in roles {
            for effort in efforts {
                form.selectModel("gpt-6-sol", for: role)
                form.selectEffort(effort, for: role)
                #expect(form.canGenerate)

                for language in [AppLanguage.simplifiedChinese, .english] {
                    #expect(form.generateAndCopy(language: language, to: clipboard) == .copied)
                    let copied = try #require(clipboard.writes.last)
                    let command = try #require(JSONSerialization.jsonObject(with: Data(copied.utf8)) as? [String: Any])
                    #expect(command["op"] as? String == "set_team_models")
                    #expect(command["scope"] as? String == "receiving_leader_bound_root")
                    let copiedRoles = try #require(command["roles"] as? [String: [String: String]])
                    for selectedRole in roles {
                        let selected = form.selection(for: selectedRole)
                        let values = try #require(copiedRoles[selectedRole.rawValue])
                        #expect(values["model"] == selected.model)
                        #expect(values["thinking"] == selected.effort)
                    }
                }
            }
        }
        #expect(clipboard.writes.count == roles.count * efforts.count * 2)
    }

    @Test func allFourRoleSelectionsPersistAcrossReconstruction() throws {
        let suiteName = "ThreadOSPromptComposerTests.\(UUID().uuidString)"
        let firstDefaults = try #require(UserDefaults(suiteName: suiteName))
        firstDefaults.removePersistentDomain(forName: suiteName)
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }

        let form = ThreadOSPromptComposerForm(preferences: ApplicationPreferences(userDefaults: firstDefaults))
        form.selectModel("gpt-6-sol", for: .leader)
        form.selectEffort("low", for: .leader)
        form.selectModel("gpt-6-sol", for: .coderCluster)
        form.selectEffort("xhigh", for: .coderCluster)
        form.selectModel("gpt-6-sol", for: .reviewerCluster)
        form.selectEffort("high", for: .reviewerCluster)
        form.selectModel("gpt-6-sol", for: .qa)
        form.selectEffort("medium", for: .qa)

        let data = try #require(firstDefaults.data(forKey: ThreadOSPromptComposerPreferences.selections.name))
        let stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(stored["version"] as? Int == 1)
        #expect((stored["selections"] as? [[String: Any]])?.count == 4)

        let reopenedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let reopened = ThreadOSPromptComposerForm(preferences: ApplicationPreferences(userDefaults: reopenedDefaults))
        #expect(reopened.selection(for: .leader) == .init(model: "gpt-6-sol", effort: "low"))
        #expect(reopened.selection(for: .coderCluster) == .init(model: "gpt-6-sol", effort: "xhigh"))
        #expect(reopened.selection(for: .reviewerCluster) == .init(model: "gpt-6-sol", effort: "high"))
        #expect(reopened.selection(for: .qa) == .init(model: "gpt-6-sol", effort: "medium"))
    }

    @Test func malformedStoredSelectionsFallBackToValidatedDefaults() {
        let invalidDocuments = [Data("not a role-selection document".utf8)]
        for invalid in invalidDocuments {
            let preferences = ApplicationPreferences.inMemory(seed: [
                ThreadOSPromptComposerPreferences.selections.name: invalid
            ])
            let form = ThreadOSPromptComposerForm(preferences: preferences)
            #expect(form.selections == expectedDefaults)
            #expect(form.canGenerate)
        }
    }

    @Test func newGlobalPreferencesDoNotReadOrModifySelectedProjectDrafts() throws {
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject("old-project", to: preferences)
        let oldDraft = FactoriumV2SettingsDraft(project: "old-project")
        ThreadOSSettingsPreferences.saveFactoriumV2(oldDraft, to: preferences)
        let savedDraft = try #require(
            ThreadOSSettingsPreferences.loadFactoriumV2(project: "old-project", from: preferences)
        )

        let form = ThreadOSPromptComposerForm(preferences: preferences)
        form.selectModel("gpt-5.6-terra", for: .reviewerCluster)
        form.selectEffort("xhigh", for: .qa)

        #expect(ThreadOSSettingsPreferences.selectedFactoriumV2Project(from: preferences) == "old-project")
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: "old-project", from: preferences) == savedDraft)
    }

    @Test func generatesAndCopiesOneValidatedFourRolePromptInBothLanguages() throws {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory())
        let clipboard = ClipboardSpy()
        for language in [AppLanguage.simplifiedChinese, .english] {
            let result = form.generateAndCopy(language: language, to: clipboard)
            let expected = try ThreadOSLeaderPrompt.make(selections: form.selections, language: language)
            #expect(result == .copied)
            #expect(clipboard.writes.last == expected)
        }
        #expect(clipboard.writes.count == 2)
    }

    @Test func clipboardFailureIsReportedAfterOneAttempt() {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory())
        let clipboard = ClipboardSpy()
        clipboard.succeeds = false

        #expect(form.generateAndCopy(language: .english, to: clipboard) == .clipboardFailure)
        #expect(clipboard.writes.count == 1)
    }

    @Test func previewAndCopyShareExactBytesAcrossEditsAndReopen() throws {
        let preferences = ApplicationPreferences.inMemory()
        let form = ThreadOSPromptComposerForm(preferences: preferences)
        let clipboard = ClipboardSpy()
        for role in ThreadOSPromptRole.allCases {
            for effort in ThreadOSLeaderPrompt.supportedEfforts {
                form.selectModel("gpt-5.6-terra", for: role)
                form.selectEffort(effort, for: role)
                #expect(form.copyResult == nil)
                let preview = try #require(form.generatedInstruction)
                #expect(form.generateAndCopy(language: .simplifiedChinese, to: clipboard) == .copied)
                #expect(clipboard.writes.last?.utf8.elementsEqual(preview.utf8) == true)
                #expect(form.copyResult == .copied)
                #expect(form.generateAndCopy(language: .english, to: clipboard) == .copied)
                #expect(clipboard.writes.last == preview)
                let reopened = ThreadOSPromptComposerForm(preferences: preferences)
                #expect(reopened.generatedInstruction == preview)
                #expect(reopened.copyResult == nil)
            }
        }
    }

    @Test func copyFailureClearsOnlyAfterAnActualSelectionChange() throws {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory())
        let clipboard = ClipboardSpy()
        clipboard.succeeds = false
        let before = try #require(form.generatedInstruction)
        #expect(form.generateAndCopy(language: .english, to: clipboard) == .clipboardFailure)
        #expect(form.copyResult == .clipboardFailure)
        form.selectModel("unsupported", for: .leader)
        #expect(form.copyResult == .clipboardFailure)
        #expect(form.generatedInstruction == before)
        form.selectEffort("low", for: .leader)
        #expect(form.copyResult == nil)
        #expect(form.generatedInstruction != before)
    }

    @Test func unsupportedSavedSelectionsNeverShowOrCopyAStaleInstruction() throws {
        let preferences = ApplicationPreferences.inMemory()
        let saved = StoredSelections(version: 1, selections: ThreadOSPromptRole.allCases.map { role in
            .init(role: role, model: role == .qa ? "saved-unknown" : "gpt-6-sol", effort: "medium")
        })
        preferences.set(try JSONEncoder().encode(saved) as Data?, for: ThreadOSPromptComposerPreferences.selections)
        let form = ThreadOSPromptComposerForm(preferences: preferences)
        let clipboard = ClipboardSpy()
        #expect(form.generatedInstruction == nil)
        #expect(form.generateAndCopy(language: .english, to: clipboard) == .unavailable)
        #expect(clipboard.writes.isEmpty)
        #expect(form.selection(for: .qa).model == "saved-unknown")
        form.selectModel("gpt-6-luna", for: .qa)
        #expect(form.copyResult == nil)
        let preview = try #require(form.generatedInstruction)
        #expect(form.generateAndCopy(language: .english, to: clipboard) == .copied)
        #expect(clipboard.writes == [preview])
    }

    private final class ClipboardSpy: ThreadOSSettingsClipboard {
        private(set) var writes: [String] = []
        var succeeds = true

        func write(_ string: String) -> Bool {
            writes.append(string)
            return succeeds
        }
    }
}
