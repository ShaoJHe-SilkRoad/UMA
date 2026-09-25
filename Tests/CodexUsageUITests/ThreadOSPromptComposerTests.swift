import Testing
@testable import CodexUsageUI

struct ThreadOSPromptComposerTests {
    @MainActor
    private func loadCatalog() throws -> ThreadOSModelCatalog {
        try ThreadOSSettingsCodec.loadCatalog(revision: ThreadOSSettingsCodec.latestCatalogRevision)
    }

    @MainActor
    @Test func generatesAndCopiesTheValidatedLeaderPromptExactlyOnce() throws {
        let catalog = try loadCatalog()
        let form = ThreadOSPromptComposerForm(catalog: catalog, preferences: .inMemory())
        let clipboard = ClipboardSpy()

        let result = form.generateAndCopy(language: .simplifiedChinese, to: clipboard)
        let expected = try ThreadOSLeaderPrompt.make(
            model: form.selectedModel,
            effort: form.selectedEffort,
            language: .simplifiedChinese,
            catalog: catalog
        )

        #expect(result == .copied)
        #expect(clipboard.writes == [expected])
        #expect(expected.contains("接收 Leader"))
        #expect(!expected.contains("TOSCFG/2"))
    }

    @MainActor
    @Test func unavailableSelectionDoesNotTouchClipboard() {
        let form = ThreadOSPromptComposerForm(catalog: nil, preferences: .inMemory())
        let clipboard = ClipboardSpy()

        #expect(form.generateAndCopy(language: .english, to: clipboard) == .unavailable)
        #expect(clipboard.writes.isEmpty)
    }

    @MainActor
    @Test func changingModelReplacesUnsupportedEffortWithCatalogChoice() throws {
        let preferences = ApplicationPreferences.inMemory()
        let catalog = try loadCatalog()
        let form = ThreadOSPromptComposerForm(catalog: catalog, preferences: preferences)
        form.selectModel("gpt-5.6-terra")
        form.selectEffort("ultra")

        form.selectModel("gpt-6-luna")

        #expect(form.selectedModel == "gpt-6-luna")
        #expect(form.effortOptions.contains(form.selectedEffort))
        #expect(form.selectedEffort == "medium")
        #expect(preferences.value(for: ThreadOSPromptComposerPreferences.model) == "gpt-6-luna")
        #expect(preferences.value(for: ThreadOSPromptComposerPreferences.effort) == "medium")
    }

    @MainActor
    @Test func newGlobalPreferencesDoNotReadOrModifySelectedProjectDrafts() throws {
        let preferences = ApplicationPreferences.inMemory()
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject("old-project", to: preferences)
        let oldDraft = FactoriumV2SettingsDraft(project: "old-project")
        ThreadOSSettingsPreferences.saveFactoriumV2(oldDraft, to: preferences)
        let savedDraft = try #require(
            ThreadOSSettingsPreferences.loadFactoriumV2(project: "old-project", from: preferences)
        )

        let form = ThreadOSPromptComposerForm(catalog: try loadCatalog(), preferences: preferences)
        #expect(form.selectedModel == "gpt-6-luna")
        form.selectModel("gpt-5.6-terra")
        form.selectEffort("ultra")

        #expect(form.selectedModel == "gpt-5.6-terra")
        #expect(ThreadOSSettingsPreferences.selectedFactoriumV2Project(from: preferences) == "old-project")
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: "old-project", from: preferences) == savedDraft)
    }

    @MainActor
    private final class ClipboardSpy: ThreadOSSettingsClipboard {
        private(set) var writes: [String] = []
        var succeeds = true

        func write(_ string: String) -> Bool {
            writes.append(string)
            return succeeds
        }
    }
}
