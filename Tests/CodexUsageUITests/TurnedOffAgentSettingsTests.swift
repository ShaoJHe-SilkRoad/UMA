import Foundation
import Testing
@testable import CodexUsageUI

/// Turning an agent's monitoring off removes it from every surface, its own
/// page included, and there was no way to turn it back on. Settings › Agents
/// now lists it under Turned Off with a Turn On button.
@Suite("A turned-off agent can be turned on again from Settings", .serialized)
@MainActor
struct TurnedOffAgentSettingsTests {
    @Test("Only the agents whose monitoring is off are listed, never Gemini")
    func listsTurnedOffAgentsOnly() {
        let coordinator = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: ApplicationPreferences.inMemory())
        )
        // Fresh preferences: Codex, Claude and Antigravity on; Gemini off.
        #expect(TurnedOffAgentSettingsRows.turnedOffProviderIDs(in: coordinator).isEmpty)

        coordinator.setMonitoringEnabled(false, for: AgentPreferenceRecord.claudeProviderID)
        coordinator.setMonitoringEnabled(false, for: AgentPreferenceRecord.antigravityProviderID)
        #expect(
            TurnedOffAgentSettingsRows.turnedOffProviderIDs(in: coordinator)
                == [AgentPreferenceRecord.claudeProviderID, AgentPreferenceRecord.antigravityProviderID]
        )

        coordinator.setMonitoringEnabled(true, for: AgentPreferenceRecord.claudeProviderID)
        #expect(
            TurnedOffAgentSettingsRows.turnedOffProviderIDs(in: coordinator)
                == [AgentPreferenceRecord.antigravityProviderID]
        )
    }

    @Test("Turn On turns the agent's monitoring on and empties Turned Off")
    func turnOnRestoresMonitoring() {
        let coordinator = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: ApplicationPreferences.inMemory())
        )
        coordinator.setMonitoringEnabled(false, for: AgentPreferenceRecord.claudeProviderID)
        #expect(
            TurnedOffAgentSettingsRows.turnedOffProviderIDs(in: coordinator)
                == [AgentPreferenceRecord.claudeProviderID]
        )

        TurnedOffAgentSettingsRows.turnOn(
            AgentPreferenceRecord.claudeProviderID,
            coordinator: coordinator,
            reconnection: nil
        )

        #expect(coordinator.isMonitoringEnabled(for: AgentPreferenceRecord.claudeProviderID))
        #expect(TurnedOffAgentSettingsRows.turnedOffProviderIDs(in: coordinator).isEmpty)
    }

    @Test("Settings › Agents follows monitoring: Turned Off appears and empties as agents go off and on")
    func settingsModelFollowsMonitoring() async throws {
        let preferences = ApplicationPreferences.inMemory()
        let coordinator = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: preferences)
        )
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: try AgentConnectorRegistry(connectors: []),
            primaryConnectorID: nil,
            preferences: preferences,
            agentSettings: coordinator,
            backgroundRefreshSleeper: { _ in throw CancellationError() }
        )
        let model = GlobalSettingsViewModel(
            preferences: preferences,
            store: store,
            dataPaths: .current(
                bundleIdentifier: "com.example.turned-off-fixture",
                applicationSupportDirectory: FileManager.default.temporaryDirectory,
                homeDirectory: FileManager.default.temporaryDirectory
            )
        )
        #expect(model.turnedOffAgentIDs.isEmpty)

        coordinator.setMonitoringEnabled(false, for: AgentPreferenceRecord.claudeProviderID)
        try await settle { model.turnedOffAgentIDs == [AgentPreferenceRecord.claudeProviderID] }
        #expect(model.turnedOffAgentIDs == [AgentPreferenceRecord.claudeProviderID])

        TurnedOffAgentSettingsRows.turnOn(
            AgentPreferenceRecord.claudeProviderID,
            coordinator: coordinator,
            reconnection: nil
        )
        try await settle { model.turnedOffAgentIDs.isEmpty }
        #expect(model.turnedOffAgentIDs.isEmpty)
    }

    private func settle(_ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !done(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
