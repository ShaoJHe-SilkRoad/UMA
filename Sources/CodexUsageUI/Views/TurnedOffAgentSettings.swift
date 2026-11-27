import SwiftUI

/// Something that has to reconnect an agent once its monitoring is turned
/// back on from Settings, because turning it off disconnected it.
@MainActor
public protocol AgentReconnecting: AnyObject {
    /// `agentID` is the agent's connector identifier, such as "claude".
    func reconnectAfterMonitoringTurnedOn(agentID: String)
}

extension AntigravitySettingsModel: AgentReconnecting {
    /// As the switch on Antigravity's page: turning it off disconnected it,
    /// so turning it on checks the official tool again.
    public func reconnectAfterMonitoringTurnedOn(agentID: String) {
        guard agentID == AgentPreferenceRecord.antigravityProviderID.rawValue else { return }
        checkAntigravity()
    }
}

/// Agents whose monitoring is off. Turning monitoring off removes an agent
/// from every surface, its own page included, so this is where it comes back.
/// Gemini is not listed: its switch is under Web Usage.
struct TurnedOffAgentSettingsRows: View {
    let providerIDs: [AgentConnectorID]
    let coordinator: AgentSettingsCoordinator
    let reconnection: (any AgentReconnecting)?
    let language: AppLanguage

    static let listedProviderIDs: [AgentConnectorID] = [
        AgentPreferenceRecord.codexProviderID,
        AgentPreferenceRecord.claudeProviderID,
        AgentPreferenceRecord.antigravityProviderID,
    ]

    static func turnedOffProviderIDs(
        in coordinator: AgentSettingsCoordinator
    ) -> [AgentConnectorID] {
        listedProviderIDs.filter { !coordinator.isMonitoringEnabled(for: $0) }
    }

    static func rowIdentifier(_ providerID: AgentConnectorID) -> String {
        "uma.settings.agents.turned-off.\(providerID.rawValue)"
    }

    var body: some View {
        ForEach(providerIDs, id: \.rawValue) { providerID in
            row(providerID)
        }
    }

    private func row(_ providerID: AgentConnectorID) -> some View {
        let name = ProviderProductID(rawValue: providerID.rawValue)?.displayName
            ?? providerID.rawValue
        return HStack(spacing: 8) {
            DesktopAgentLogo(
                providerID: providerID.rawValue,
                tint: .secondary,
                diameter: 18
            )
            .accessibilityHidden(true)
            Text(name)
            Spacer()
            Button(localized("Turn On", "打开")) {
                Self.turnOn(
                    providerID,
                    coordinator: coordinator,
                    reconnection: reconnection
                )
            }
                .accessibilityLabel(localized("Turn on \(name)", "打开 \(name)"))
        }
        .accessibilityIdentifier(Self.rowIdentifier(providerID))
    }

    static func turnOn(
        _ providerID: AgentConnectorID,
        coordinator: AgentSettingsCoordinator,
        reconnection: (any AgentReconnecting)?
    ) {
        coordinator.setMonitoringEnabled(true, for: providerID)
        reconnection?.reconnectAfterMonitoringTurnedOn(agentID: providerID.rawValue)
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
