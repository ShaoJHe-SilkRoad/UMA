import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.11-G1 provider cards")
struct UMA011G1ProviderCardTests {
    @Test
    func expansionStateStartsCollapsedAndSupportsIndependentProviders() {
        var state = MainPanelProviderExpansionState()

        #expect(!state.isExpanded("codex.local"))
        #expect(!state.isExpanded("workbuddy.accountWeb"))

        state.setExpanded(true, providerID: "codex.local")
        #expect(state.isExpanded("codex.local"))
        #expect(!state.isExpanded("workbuddy.accountWeb"))

        state.setExpanded(true, providerID: "workbuddy.accountWeb")
        #expect(state.areAllExpanded(
            providerIDs: ["codex.local", "workbuddy.accountWeb"]
        ))

        state.setExpanded(false, providerID: "codex.local")
        #expect(!state.isExpanded("codex.local"))
        #expect(state.isExpanded("workbuddy.accountWeb"))
    }

    @Test
    func showAllHideAllAndAdmissionPruningAreDeterministic() {
        var state = MainPanelProviderExpansionState()
        let visible = [
            "codex.local",
            "claude.local",
            "workbuddy.accountWeb"
        ]

        state.expandAll(providerIDs: visible)
        #expect(state.areAllExpanded(providerIDs: visible))
        #expect(state.isShowAllModeActive)

        let newlyVisible = [
            "codex.local",
            "workbuddy.accountWeb",
            "manus.local",
        ]
        state.retain(providerIDs: Set(newlyVisible))
        #expect(state.isExpanded("codex.local"))
        #expect(!state.isExpanded("claude.local"))
        #expect(state.isExpanded("workbuddy.accountWeb"))
        #expect(state.isExpanded("manus.local"))

        state.collapseAll()
        #expect(!state.isShowAllModeActive)
        #expect(!state.areAllExpanded(providerIDs: visible))
        #expect(visible.allSatisfy { !state.isExpanded($0) })
    }

    @Test
    func emptyProviderSetIsNeverReportedAsExpanded() {
        var state = MainPanelProviderExpansionState()
        state.expandAll(providerIDs: [String]())
        #expect(!state.areAllExpanded(providerIDs: [String]()))
    }

    @Test
    func roadmapOrderScalesDeterministicallyFromThreeToEightProviders() throws {
        let rawIDs = [
            "emerging.local",
            "doubao.local",
            "kimi.local",
            "cursor.local",
            "manus.local",
            "workbuddy.accountWeb",
            "claude.local",
            "codex.local",
        ]
        let ids = try rawIDs.map {
            try #require(AgentConnectorID(rawValue: $0))
        }
        let ordered = ids.sorted(by: AgentProviderOrder.precedes)
        #expect(ordered.map(\.rawValue) == [
            "codex.local",
            "claude.local",
            "workbuddy.accountWeb",
            "manus.local",
            "cursor.local",
            "kimi.local",
            "doubao.local",
            "emerging.local",
        ])
        for count in 3...8 {
            let subset = Array(ids.suffix(count))
            let first = subset.sorted(by: AgentProviderOrder.precedes)
            let second = subset.reversed().sorted(by: AgentProviderOrder.precedes)
            #expect(first == second)
        }
    }

    @Test
    func panelUsesOneNeutralOrderedProviderCardPath() throws {
        let panel = try source(
            "Sources/CodexUsageUI/Views/UsagePanelView.swift"
        )
        let panelContent = try #require(
            panel.slice(
                from: "private var panelContent: some View",
                to: "private func expansionBinding"
            )
        )

        #expect(panelContent.contains("MonitorHeaderView"))
        #expect(panelContent.contains("ForEach(store.presentationCards)"))
        #expect(
            panelContent.occurrenceCount(
                of: "LocalLiveProviderCard("
            ) == 1
        )
        #expect(!panelContent.contains("additionalProviderCards"))
        #expect(!panelContent.contains("if presentation.showsRealData"))
    }

    @Test
    func neutralHeaderContainsNoCodexPlanOrConnectionCopy() throws {
        let panel = try source(
            "Sources/CodexUsageUI/Views/UsagePanelView.swift"
        )
        let header = try #require(
            panel.slice(
                from: "private struct MonitorHeaderView",
                to: "private struct RecoveryActionButton"
            )
        )

        #expect(header.contains("Text(\"UMA\")"))
        #expect(header.contains("active Agents"))
        #expect(!header.contains("store.snapshot.planLabel"))
        #expect(!header.contains("store.statusText"))
        #expect(!header.contains("Codex"))
    }

    @Test
    func everyProviderCardExposesDetailsAndAgentSettings() throws {
        let panel = try source(
            "Sources/CodexUsageUI/Views/UsagePanelView.swift"
        )
        let card = try #require(
            panel.slice(
                from: "private struct LocalLiveProviderCard",
                to: "private struct UsagePanelContentHeightPreferenceKey"
            )
        )

        #expect(card.contains("Button(action: openAgentSettings)"))
        #expect(card.contains("isExpanded.toggle()"))
        #expect(card.contains("selectedWindowCompactLabel"))
        #expect(
            card.contains(
                ".frame(minHeight: UsagePanelMetrics.collapsedProviderCardHeight)"
            )
        )
        #expect(card.occurrenceCount(of: "GlassCardBackground(tuning: tuning)") >= 1)
    }

    @Test
    func codexAndWorkBuddyDetailsRemainProviderOwned() throws {
        let panel = try source(
            "Sources/CodexUsageUI/Views/UsagePanelView.swift"
        )
        let card = try #require(
            panel.slice(
                from: "private struct LocalLiveProviderCard",
                to: "private struct UsagePanelContentHeightPreferenceKey"
            )
        )

        #expect(card.contains("UsageSummaryCard("))
        #expect(card.contains("selectedWindowID: card.selectedWindowID"))
        #expect(card.contains("CodexSourceHealthDetails("))
        #expect(card.contains("RecentTasksCard("))
        #expect(card.contains("APICostEstimateCard("))
        #expect(card.contains("FooterView("))
        #expect(card.contains("workBuddySubscriptionRemaining"))
        #expect(card.contains("workBuddyAddOnRemaining"))
        #expect(card.contains("workBuddyBenefitGiftRemaining"))
        #expect(card.contains("CreditFormatter.exactTwoDecimal"))
    }

    @Test
    func selectedCodexWindowOwnsDetailEmphasisAndFiveHourRemainsSecondary()
        throws
    {
        let panel = try source(
            "Sources/CodexUsageUI/Views/UsagePanelView.swift"
        )
        let summary = try #require(
            panel.slice(
                from: "private struct UsageSummaryCard",
                to: "private struct RecentTasksCard"
            )
        )
        #expect(summary.contains("let selectedWindowID: String?"))
        #expect(summary.contains("isPrimary: period.id == selectedWindowID"))
        #expect(
            summary.contains(
                "UsageQuotaVisualMetrics.primaryValueSize"
            )
        )
        #expect(
            summary.contains(
                "UsageQuotaVisualMetrics.secondaryValueSize"
            )
        )
        #expect(summary.contains("isPrimary ? 10 : 5"))
        #expect(summary.contains("CodexSourceHealthDetails"))
    }

    private func source(_ relativePath: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

private extension String {
    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound..<endIndex)
        else { return nil }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }

    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
