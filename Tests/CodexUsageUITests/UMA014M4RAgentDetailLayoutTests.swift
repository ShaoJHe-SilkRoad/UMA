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

    @Test("Compact rows retain proportional full-height fill inside their existing container")
    func glanceRowVisualContract() throws {
        let source = try sourceText()
        let glance = source.components(separatedBy: "public struct QuickPanelSurface")[0]
        #expect(glance.contains("CompactUsageFill("))
        #expect(!glance.contains("private var remainingRail:"))
        #expect(!glance.contains(".frame(height: 2)"))
        #expect(glance.contains("if showsConnectivity { providerMark }"))
        #expect(glance.contains("if showsRemainingRail"))
    }

    @Test("Compact fill uses remaining usage exactly and never fabricates unavailable or infinite fill")
    func compactFillGeometry() {
        for percent in [0.0, 14, 50, 77, 90, 100] {
            #expect(CompactUsageFillPolicy.fraction(for: percent) == percent / 100)
        }
        let invalid: [Double?] = [nil, .nan, .infinity, -.infinity, -1, 101]
        for percent in invalid {
            #expect(CompactUsageFillPolicy.fraction(for: percent) == nil)
        }
    }

    @Test("Agent detail keeps safe activity and diagnostics directly visible")
    func directSummaryContract() throws {
        let source = try sourceText()

        #expect(source.contains("LazyVGrid("))
        #expect(source.contains("usageModule"))
        #expect(source.contains("connectionModule"))
        #expect(source.contains("controlsModule"))
        #expect(source.contains("SharedBasicUsageSummaryView("))
        #expect(source.contains("module(localized(\"Local Smart & Accuracy\""))
        #expect(source.contains("module(localized(\"Privacy & Advanced Diagnostics\""))
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
