import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Balanced shared usage presentation")
struct BalancedUsagePresentationTests {
    @Test("Projection preserves quota resets and marks partial local pricing coverage")
    func projectionPreservesAccountAndLocalBoundaries() {
        var snapshot = UsageSnapshot.preview(language: .english)
        snapshot.apiCostEstimate = APICostEstimateSnapshot(
            sevenDayUSD: 12.5,
            lifetimeUSD: 42,
            coveragePercent: 67,
            modelNames: ["GPT"]
        )

        let projection = BasicSharedUsagePresentation.make(snapshot: snapshot, provider: nil)

        #expect(projection.windows.count == 2)
        #expect(projection.windows.allSatisfy { !$0.resetText.isEmpty })
        #expect(projection.metrics.map(\.id).contains("week"))
        #expect(projection.metrics.map(\.id).contains("total"))
        #expect(projection.recentActivity.count == 3)
        #expect(projection.apiEquivalentEstimate?.coveragePercent == 67)
        #expect(projection.apiEquivalentEstimate?.isPartialCoverage == true)
    }

    @Test("Projection does not manufacture unavailable cost or token values")
    func projectionDoesNotInventUnavailableValues() {
        var snapshot = UsageSnapshot.empty(language: .english)
        snapshot.metrics = [UsageMetric(id: "week", value: "—", label: "7 days")]

        let projection = BasicSharedUsagePresentation.make(snapshot: snapshot, provider: nil)

        #expect(projection.metrics.isEmpty)
        #expect(projection.apiEquivalentEstimate == nil)
        #expect(projection.recentActivity.isEmpty)
    }

    @Test("Local estimate provenance remains distinct from a fresh account source")
    func localSourceTruthIsRetainedIndependently() {
        for localSource in [
            UsageSourceStatus(label: "Local", scope: "local", capturedAt: Date(), isAvailable: true, freshness: .stale),
            UsageSourceStatus(label: "Local", scope: "local", capturedAt: Date(), isAvailable: false, freshness: .unavailable),
            nil,
        ] {
            var snapshot = UsageSnapshot.preview(language: .english)
            snapshot.providerSource = UsageSourceStatus(label: "Account", scope: "account", capturedAt: Date(), isAvailable: true, freshness: .fresh)
            snapshot.localSource = localSource
            let projection = BasicSharedUsagePresentation.make(snapshot: snapshot, provider: nil)
            #expect(projection.providerSource?.freshness == .fresh)
            #expect(projection.localSource?.freshness == localSource?.freshness)
            #expect(projection.apiEquivalentEstimate?.sevenDayUSD == snapshot.apiCostEstimate?.sevenDayUSD)
            #expect(projection.metrics.isEmpty == false)
        }
    }

    @Test("Agent safe summaries are direct modules at both supported grid widths")
    func agentDetailKeepsSafeSummariesDirect() throws {
        let url = repositoryRoot().appendingPathComponent(
            "Sources/CodexUsageUI/Views/AgentSurfaceViews.swift"
        )
        let source = try String(contentsOf: url)

        #expect(AgentWorkspaceLayoutPolicy.columnCount(for: 900) == 2)
        #expect(AgentWorkspaceLayoutPolicy.columnCount(for: 500) == 1)
        #expect(source.contains("SharedBasicUsageSummaryView("))
        #expect(!source.contains("DisclosureGroup(localized(\"Recent Activity\""))
        #expect(!source.contains("DisclosureGroup(localized(\"Privacy & Advanced Diagnostics\""))
        #expect(!source.contains("threadOSAnalytics"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
