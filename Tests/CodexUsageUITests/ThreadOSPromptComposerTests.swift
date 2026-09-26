import Foundation
import Testing
@testable import CodexUsageUI

@MainActor
struct ThreadOSPromptComposerTests {
    private let expectedDefaults: [ThreadOSPromptRole: ThreadOSPromptSelection] = [
        .leader: .init(model: "gpt-6-luna", effort: "medium"),
        .coderCluster: .init(model: "gpt-6-luna", effort: "medium"),
        .reviewerCluster: .init(model: "gpt-6-luna", effort: "medium"),
        .qa: .init(model: "gpt-6-sol", effort: "high")
    ]

    @Test func roleSelectionsCanChangeIndependently() {
        let form = ThreadOSPromptComposerForm(preferences: .inMemory())
        form.selectModel("gpt-6-astra", for: .leader)
        form.selectEffort("xhigh", for: .qa)

        #expect(form.selection(for: .leader) == .init(model: "gpt-6-astra", effort: "medium"))
        #expect(form.selection(for: .coderCluster) == expectedDefaults[.coderCluster])
        #expect(form.selection(for: .reviewerCluster) == expectedDefaults[.reviewerCluster])
        #expect(form.selection(for: .qa) == .init(model: "gpt-6-sol", effort: "xhigh"))
        #expect(form.canGenerate)
    }

    @Test func allFourRoleSelectionsPersistAcrossReconstruction() throws {
        let suiteName = "ThreadOSPromptComposerTests.\(UUID().uuidString)"
        let firstDefaults = try #require(UserDefaults(suiteName: suiteName))
        firstDefaults.removePersistentDomain(forName: suiteName)
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }

        let form = ThreadOSPromptComposerForm(preferences: ApplicationPreferences(userDefaults: firstDefaults))
        form.selectModel("gpt-6-astra", for: .leader)
        form.selectEffort("low", for: .leader)
        form.selectModel("gpt-5.6-sol", for: .coderCluster)
        form.selectEffort("xhigh", for: .coderCluster)
        form.selectModel("gpt-6-sol", for: .reviewerCluster)
        form.selectEffort("high", for: .reviewerCluster)
        form.selectModel("gpt-5.6-terra", for: .qa)
        form.selectEffort("medium", for: .qa)

        let data = try #require(firstDefaults.data(forKey: ThreadOSPromptComposerPreferences.selections.name))
        let stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(stored["version"] as? Int == 1)
        #expect((stored["selections"] as? [[String: Any]])?.count == 4)

        let reopenedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let reopened = ThreadOSPromptComposerForm(preferences: ApplicationPreferences(userDefaults: reopenedDefaults))
        #expect(reopened.selection(for: .leader) == .init(model: "gpt-6-astra", effort: "low"))
        #expect(reopened.selection(for: .coderCluster) == .init(model: "gpt-5.6-sol", effort: "xhigh"))
        #expect(reopened.selection(for: .reviewerCluster) == .init(model: "gpt-6-sol", effort: "high"))
        #expect(reopened.selection(for: .qa) == .init(model: "gpt-5.6-terra", effort: "medium"))
    }

    @Test func malformedStoredSelectionsFallBackToValidatedDefaults() {
        let invalidDocuments = [
            Data("not a role-selection document".utf8),
            Data(#"{"version":1,"selections":[{"role":"leader","model":"unsupported","effort":"low"},{"role":"coderCluster","model":"gpt-6-sol","effort":"medium"},{"role":"reviewerCluster","model":"gpt-6-luna","effort":"high"},{"role":"qa","model":"gpt-6-astra","effort":"xhigh"}]}"#.utf8)
        ]
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

    private final class ClipboardSpy: ThreadOSSettingsClipboard {
        private(set) var writes: [String] = []
        var succeeds = true

        func write(_ string: String) -> Bool {
            writes.append(string)
            return succeeds
        }
    }
}
