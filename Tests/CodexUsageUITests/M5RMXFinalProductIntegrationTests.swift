import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5RMX final product integration")
struct M5RMXFinalProductIntegrationTests {
    @Test
    func discoveryAndPresentationShareOneAdmissionPolicy() throws {
        let scanner = try source("Sources/CodexUsageUI/Connectors/LocalProviderEligibilityScanner.swift")
        let presentation = try source("Sources/CodexUsageUI/Models/SharedUsagePresentation.swift")
        #expect(scanner.contains("enum ProviderUsageSurfacePolicy"))
        #expect(presentation.contains("ProviderUsageSurfacePolicy.permitsRetainedValue"))
        #expect(presentation.contains("ProviderUsageSurfacePolicy.hasAdmissibleAccountProvenance"))
        #expect(presentation.contains("ProviderUsageSurfacePolicy.validatesUsage"))
        #expect(presentation.contains("smart-1-desktop-estimate"))
        #expect(presentation.contains("smart-1-local-exact"))
        #expect(presentation.contains("smart-1-safari-exact"))
        #expect(presentation.contains("smart-1-mixed"))
        #expect(presentation.contains("claudeDesktopEstimateSourceLabel"))
        #expect(presentation.contains("claudeLocalSmartEstimateSourceLabel"))
        #expect(presentation.contains("claudeLocalExactSourceLabel"))
        #expect(presentation.contains("claudeBrowserSourceLabel"))
    }

    @Test
    func settingsConsumesTheSameResolvedCardsAsMainAndAssistant() throws {
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let settings = try source("Sources/CodexUsageUI/Views/UsageSettingsCard.swift")
        #expect(panel.contains("providerPresentations: store.presentationCards"))
        #expect(settings.contains("let providerPresentations: [SharedUsageCardPresentation]"))
        #expect(settings.contains("ResolvedProviderUsageSummary"))
        #expect(settings.contains("presentation.remainingDisplayText"))
        #expect(settings.contains("presentation.sourceDescription"))
        #expect(settings.contains("Text(language.remaining)"))
        #expect(!settings.contains("window.resetText"))
        #expect(!settings.contains("Current usage"))
        #expect(!settings.contains("当前用量"))
    }

    @Test
    func localDetailControlsAreAvailableFromClaudeSettings() throws {
        let settings = try source("Sources/CodexUsageUI/Views/UsageSettingsCard.swift")
        let clause = try #require(settings.range(
            of: "if providerID == AgentPreferenceRecord.claudeProviderID {"
        ))
        let tail = String(settings[clause.lowerBound...].prefix(1_200))
        #expect(tail.contains("title: language.recentTasks"))
        #expect(tail.contains("title: language.costCard"))
    }

    @Test
    func currentReleaseTruthIsThirteenAndFounderRemoteIsUMA() throws {
        let plan = try source("source/M5RMX_Plan.md")
        let goal = try source("source/M5RMX_Goal.md")
        for document in [plan, goal] {
            #expect(document.contains("`UMA_0.13.0.app`"))
            #expect(document.contains("https://github.com/ShaoJHe-SilkRoad/UMA"))
            #expect(document.contains("0.12") && document.contains("historical"))
        }
        #expect(plan.contains("last accepted rollback line\nis `0.11`"))
        #expect(goal.contains("`0.11` remains the rollback line"))
    }

    @Test
    func dailyRuntimeExcludesDormantAndRejectedProvidersWhileCatalogOrderRemainsStable() throws {
        let runtime = try source("Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift")
        let order = try source("Sources/CodexUsageUI/Connectors/AgentUsageConnector.swift")
        for connector in [
            "let connector = CodexUsageConnector(",
            "ClaudeCodeUsageConnector.production(",
        ] {
            #expect(runtime.contains(connector))
        }
        #expect(!runtime.contains("WorkBuddyAccountWebCreditsConnector("))
        #expect(!runtime.contains("GoogleAntigravityUsageConnector("))
        #expect(!runtime.contains("CursorUsageConnector"))
        #expect(!runtime.contains("KimiUsageConnector"))
        #expect(order.contains("case \"codex\": 0"))
        #expect(order.contains("case \"claude\": 100"))
        #expect(order.contains("case \"workbuddy\": 200"))
        #expect(order.contains("case \"antigravity\": 250"))
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
