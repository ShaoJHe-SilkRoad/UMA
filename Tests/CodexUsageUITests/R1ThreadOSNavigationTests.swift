import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("R1 ThreadOS existing navigation")
@MainActor struct R1ThreadOSNavigationTests {
    @Test("Codex detail callback reuses navigation without changing the saved draft")
    func codexDetailCallbackPreservesDraft() throws {
        let preferences = ApplicationPreferences.inMemory()
        let draft = FactoriumV2SettingsDraft(project: "R1_NAV")
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)
        let navigation = MainSurfaceNavigationState()
        navigation.destination = .threadOS
        navigation.selectedAgent = .claude
        let callback = {
            navigation.selectedAgent = .codex
            navigation.destination = .agents
        }
        let settings = ThreadOSSettingsView(language: .english, basicUsage: .make(snapshot: .preview(language: .english), provider: nil), showCodexDetail: callback, preferences: preferences)

        settings.showCodexDetailForTesting()

        #expect(navigation.destination == .agents)
        #expect(navigation.selectedAgent == .codex)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: "R1_NAV", from: preferences) == draft)
    }
}
