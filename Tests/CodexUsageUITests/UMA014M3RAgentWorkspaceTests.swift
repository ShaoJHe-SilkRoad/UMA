import Foundation
import Testing
@testable import CodexUsageUI

struct UMA014M3RAgentWorkspaceTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("Main retains its two-column Agent workspace plus local ThreadOS settings")
    func mainUsesBoundedTwoLevelNavigation() throws {
        let source = try read("Sources/CodexUsageMonitor/App/NativeShellViews.swift")

        #expect(source.contains("case agents = \"UMA\""))
        #expect(source.contains("case threadOS = \"ThreadOS\""))
        #expect(!source.contains("case overview"))
        #expect(source.contains("HSplitView"))
        #expect(source.contains("AgentGlanceRow("))
        #expect(source.contains("AgentWorkspaceSurface("))
        #expect(source.contains("connectClaude: connectClaude"))
        // The workspace rail reads the store's ordered accessor rather than
        // the inventory directly, so the user's arrangement decides what it
        // shows. UMA014M2PublicationTests pins that boundary in full.
        #expect(source.contains("store.orderedWorkspaceProviders"))
        #expect(source.contains("basicUsage: store.basicUsagePresentation"))
        #expect(!source.contains("ThreadOSRuntime"))
        #expect(!source.contains("ThreadOSClient"))
    }

    @Test("Review packaging includes the official Claude status-line relay")
    func reviewPackageShipsClaudeStatusLineRelay() throws {
        let source = try read("script/package_uma014_m1_dev.sh")

        #expect(source.contains("STATUS_LINE_RELAY=\"ClaudeStatusLineRelay\""))
        #expect(source.contains("--product \"$STATUS_LINE_RELAY\""))
        #expect(source.contains("\"$HELPERS/$STATUS_LINE_RELAY\""))
        #expect(source.contains("/usr/bin/install -m 755"))
    }

    @Test("Claude setup is recoverable from its workspace without bypassing consent")
    func claudeWorkspaceOffersConsentFirstRecovery() throws {
        let source = try read("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let shell = try read("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")

        #expect(source.contains("showingClaudeConsent = true"))
        #expect(source.contains("uma.agent.claude.enable-local-smart"))
        #expect(source.contains("switch claudeControlState()"))
        #expect(source.contains("uma.agent.claude.repair-local-smart"))
        #expect(source.contains("case .accuracyReady:"))
        #expect(source.contains("uma.agent.claude.accuracy-unavailable"))
        #expect(source.contains("Online verification unavailable"))
        #expect(source.contains("Button(localized(\"Enable\", \"启用\"), action: connectClaude)"))
        #expect(source.contains("credential, cookie, token, and Keychain content is never retained or transmitted"))
        #expect(shell.contains("runtime?.claudeSettings.connectWithConsent()"))
        #expect(shell.contains("runtime?.claudeSettings.agentControlState"))
    }

    @Test("Claude Local Smart and online verification remain independent")
    func claudeControlStateSeparatesLocalAndBrowserChannels() {
        #expect(ClaudeAgentControlState.classify(
            consentGranted: false,
            localSmartState: .unavailable,
            companionRuntime: .unavailable,
            browserAccuracyState: .notConfigured
        ) == .consentRequired)
        #expect(ClaudeAgentControlState.classify(
            consentGranted: true,
            localSmartState: .error,
            companionRuntime: .ready,
            browserAccuracyState: .ready
        ) == .localSmartRepairRequired)
        #expect(ClaudeAgentControlState.classify(
            consentGranted: true,
            localSmartState: .estimated(.distantPast),
            companionRuntime: .unavailable,
            browserAccuracyState: .companionUnavailable
        ) == .onlineVerificationUnavailable)
        #expect(ClaudeAgentControlState.classify(
            consentGranted: true,
            localSmartState: .estimated(.distantPast),
            companionRuntime: .ready,
            browserAccuracyState: .ready
        ) == .accuracyReady)
    }

    @Test("Agent workspace renders shared product truth and existing Codex metadata")
    func workspaceUsesDenseRealDataWithoutConnectorAccess() throws {
        let source = try read("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")

        for required in [
            "ForEach(Array(provider.quotas.enumerated())",
            "primaryDisplayText",
            "provider?.sourceSummary",
            "provider?.freshness",
            "SharedBasicUsageSummaryView(",
            "BasicSharedUsagePresentation",
            "Accuracy Sync",
            "Advanced Diagnostics",
        ] {
            #expect(source.contains(required) || required == "BasicSharedUsagePresentation")
        }
        for forbidden in [
            "CodexUsageConnector(",
            "ClaudeCodeUsageConnector(",
            "AgentConnectorRegistry(",
            "WorkBuddy",
            "Antigravity",
            "String(describing:",
        ] {
            #expect(!source.contains(forbidden))
        }
    }

    @Test("Quick Panel is cached, content-driven, and has no competing material")
    func quickPanelHasOneOuterSurfaceOwner() throws {
        let source = try read("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")

        // Same boundary as the workspace rail: the quick panel follows the
        // arrangement instead of reading the inventory for itself.
        #expect(source.contains("store.orderedQuickPanelProviders"))
        #expect(source.contains(".frame(width: 320)"))
        #expect(source.contains("No active agents"))
        #expect(source.contains("Scan for Agents"))
        #expect(!source.contains(".background(.regularMaterial)"))
        #expect(!source.contains("limiting"))
        #expect(!source.contains("Hero"))
    }

    @Test("Global Settings has only four global panes and no provider controls")
    func settingsScopeIsGlobalOnly() throws {
        let source = try read("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let settings = try #require(source.split(separator: "public struct GlobalSettingsSurface").last)

        for pane in ["general", "appearance", "desktopWizard", "privacy"] {
            #expect(source.contains("case \(pane)"))
        }
        #expect(!settings.contains("case providers"))
        #expect(!settings.contains("Accuracy Sync"))
        for providerControl in [
            "connectCodex",
            "disconnectCodex",
            "connectClaude",
            "claudeAccuracySync",
            "uma.agent.",
        ] {
            #expect(!settings.contains(providerControl))
        }
        #expect(settings.contains("ApplicationPreferences"))
    }

    @Test("Glance row explains unavailable state and exposes non-color semantics")
    func glanceRowAccessibilityIsContentComplete() throws {
        let source = try read("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")

        #expect(source.contains("No current usage"))
        #expect(source.contains("accessibilityLabel"))
        #expect(source.contains("Connected"))
        #expect(source.contains("Reconnecting"))
        #expect(source.contains("Sign in required"))
        #expect(source.contains("Setup required"))
        #expect(source.contains("Stale"))
        #expect(source.contains("Cached"))
        #expect(source.contains("Needs attention"))
        #expect(source.contains("Error"))
        #expect(source.contains("remainingPercent"))
    }

    @Test("Glance status reports freshness and health without relying on color")
    func glanceStatusMakesRetainedAndActionableStateExplicit() {
        let stale = ProviderProductStatePolicy.previewInventory(
            cards: [previewCard(connection: .stale, freshness: .stale)],
            language: .english
        ).provider(.codex)
        let cached = ProviderProductStatePolicy.previewInventory(
            cards: [previewCard(connection: .connected, freshness: .cached)],
            language: .english
        ).provider(.codex)
        let failed = ProviderProductStatePolicy.previewInventory(
            cards: [previewCard(connection: .failed, freshness: .stale)],
            language: .english
        ).provider(.codex)

        #expect(stale.map(AgentGlancePresentationPolicy.status(for:)) == .stale)
        #expect(cached.map(AgentGlancePresentationPolicy.status(for:)) == .cached)
        #expect(failed.map(AgentGlancePresentationPolicy.status(for:)) == .error)
        #expect(stale?.inventory.quickPanel == true)
        #expect(cached?.inventory.quickPanel == true)
        #expect(failed?.inventory.quickPanel == false)
    }

    @Test("Remaining bars share plan-aware policy while preserving geometry")
    func remainingBarsUseApprovedThresholds() throws {
        let source = try read("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let wizard = try read("Sources/CodexUsageUI/Views/DesktopAssistantView.swift")

        #expect(RemainingUsageVisualPolicy.visibleFraction(for: 0, width: 200) == 0.01)
        #expect(RemainingUsageVisualPolicy.visibleFraction(for: 35, width: 200) == 0.35)
        #expect(source.contains("LowRemainingUsagePolicy.assessment("))
        #expect(wizard.contains("CompactUsageFill("))
    }

    @Test("Product projection preserves an admitted plan for the represented quota")
    func admittedPlanProjection() throws {
        let card = previewCard(connection: .connected, freshness: .fresh)
        let projected = try #require(ProviderProductStatePolicy.previewInventory(
            cards: [card], language: .english).provider(.codex))
        #expect(projected.planLabel == card.planLabel)
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func previewCard(
        connection: SharedConnectionStatus,
        freshness: SharedUsageFreshness
    ) -> SharedUsageCardPresentation {
        let remaining = SharedRemainingValue.finite(24)
        let window = SharedUsageWindowPresentation(
            id: "codex-preview-window",
            kind: .sevenDay,
            compactLabel: "7D",
            accessibilityLabel: "seven-day window",
            remaining: remaining,
            resetsAt: Date(timeIntervalSince1970: 1_800_003_600),
            resetText: "Resets later"
        )
        return SharedUsageCardPresentation(
            id: CodexUsageConnector.connectorID.rawValue,
            providerName: "Codex",
            planLabel: "plus",
            connectionStatus: connection,
            freshness: freshness,
            windows: [window],
            selectedWindowID: window.id,
            remaining: remaining,
            sourceDescription: "Synthetic review fixture",
            isVisibleInDesktopAssistant: true,
            severity: .normal,
            isRetainingLastValidValue: freshness != .fresh,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
