import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.14 M4R agent detail presentation")
struct UMA014M4RAgentDetailLayoutTests {
    @Test("Agent detail uses one column when narrow and two when space permits")
    func responsiveModuleColumns() {
        #expect(AgentWorkspaceLayoutPolicy.columnCount(for: 420) == 1)
        #expect(AgentWorkspaceLayoutPolicy.columnCount(for: 659) == 1)
        #expect(AgentWorkspaceLayoutPolicy.columnCount(for: 660) == 2)
        #expect(AgentWorkspaceLayoutPolicy.columnCount(for: 1_200) == 2)
    }

    @Test("Glance rows use a thin rail and optional connectivity mark without a full tint wash")
    func glanceRowVisualContract() throws {
        let source = try sourceText()

        #expect(source.contains("private var remainingRail: some View"))
        #expect(source.contains(".frame(height: 2)"))
        #expect(source.contains("if showsConnectivity { providerMark }"))
        #expect(source.contains("if showsRemainingRail"))
        #expect(!source.contains("private var remainingTint: some View"))
    }

    @Test("Agent detail remains modular and collapses activity and privacy diagnostics")
    func modularDisclosureContract() throws {
        let source = try sourceText()

        #expect(source.contains("LazyVGrid("))
        #expect(source.contains("usageModule"))
        #expect(source.contains("connectionModule"))
        #expect(source.contains("controlsModule"))
        #expect(source.contains("DisclosureGroup(localized(\"Recent Activity\""))
        #expect(source.contains("DisclosureGroup(localized(\"Local Smart & Accuracy\""))
        #expect(source.contains("DisclosureGroup(localized(\"Privacy & Advanced Diagnostics\""))
    }

    @Test("Detailed quota surface shows admitted windows and reports an absent Codex 5H limit honestly")
    func quotaDetailTruthContract() throws {
        let source = try sourceText()

        #expect(source.contains("ForEach(Array(provider.quotas.enumerated())"))
        #expect(source.contains("provider.fiveHourStatus == .absent"))
        #expect(source.contains("Limit not reported"))
        #expect(source.contains("quota.value == .unlimited"))
    }

    private func sourceText() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "Sources/CodexUsageUI/Views/AgentSurfaceViews.swift"
            ),
            encoding: .utf8
        )
    }
}
