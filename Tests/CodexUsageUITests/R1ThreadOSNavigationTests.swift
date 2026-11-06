import Foundation
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

    @Test("ThreadOS is not in the toolbar; it opens from Codex's settings")
    func threadOSLivesUnderCodexSettings() throws {
        #expect(MainSurfaceDestination.toolbarDestinations == [.agents, .sectorium])
        #expect(MainSurfaceDestination.allCases.contains(.threadOS))
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexUsageMonitor/App/NativeShellViews.swift"),
            encoding: .utf8
        )
        #expect(shell.contains("openThreadOS: {"))
        #expect(shell.contains("navigation.destination = .threadOS"))
        #expect(shell.contains("uma.main.threados.back"))
        let settings = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexUsageUI/Views/UsageSettingsCard.swift"),
            encoding: .utf8
        )
        #expect(settings.contains("providerID == AgentPreferenceRecord.codexProviderID, let openThreadOS"))
    }
}
