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

    @Test("Account strip preserves exact 5H and 7D slots and normalizes their states")
    func accountStripUsesTypedSlotsAndTruthfulStates() {
        let five = BasicSharedUsagePresentation.Window(id: "five", title: "5H", remainingText: "0%", remainingPercent: 0, isUnlimited: false, isEstimated: false, resetText: "soon", isFiveHour: true, kind: .fiveHour)
        let seven = BasicSharedUsagePresentation.Window(id: "seven", title: "7D", remainingText: "72%", remainingPercent: 72, isUnlimited: false, isEstimated: false, resetText: "later", isFiveHour: false, kind: .sevenDay)
        let custom = BasicSharedUsagePresentation.Window(id: "custom", title: "Custom", remainingText: "66%", remainingPercent: 66, isUnlimited: false, isEstimated: false, resetText: "later", isFiveHour: false, kind: .other)
        let slots = BasicSharedUsagePresentation.accountStripWindows(from: [custom, seven, five])
        #expect(slots.map(\.kind) == [.fiveHour, .sevenDay])
        let missingSlots = BasicSharedUsagePresentation.accountStripWindows(from: [custom])
        #expect(missingSlots.map(\.remainingPercent) == [nil, nil])
        let fresh = UsageSourceStatus(label: "Account", scope: "account", capturedAt: Date(), isAvailable: true, freshness: .fresh)
        #expect(BasicSharedUsagePresentation.accountStripQuotaState(five, source: fresh) == .finite(0))
        #expect(BasicSharedUsagePresentation.accountStripQuotaState(seven, source: UsageSourceStatus(label: "Account", scope: "account", capturedAt: Date(), isAvailable: true, freshness: .stale)) == .stale(72))
        let estimated = BasicSharedUsagePresentation.Window(id: "estimated", title: "7D", remainingText: "52%", remainingPercent: 52, isUnlimited: false, isEstimated: true, resetText: "later", isFiveHour: false, kind: .sevenDay)
        #expect(BasicSharedUsagePresentation.accountStripQuotaState(estimated, source: fresh) == .estimated(52))
        #expect(BasicSharedUsagePresentation.accountStripQuotaState(missingSlots[0], source: fresh) == .unavailable)
        #expect(BasicSharedUsagePresentation.accountStripQuotaState(seven, source: nil) == .unavailable)
        let unlimited = BasicSharedUsagePresentation.Window(id: "unlimited", title: "5H", remainingText: "∞", remainingPercent: nil, isUnlimited: true, isEstimated: false, resetText: "—", isFiveHour: true, kind: .fiveHour)
        #expect(BasicSharedUsagePresentation.accountStripQuotaState(unlimited, source: fresh) == .unlimited)
    }

    @Test("Account-strip coverage keeps a compact visible percentage and complete accessibility definition")
    func accountStripCoverageCopyIsScoped() throws {
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent("Sources/CodexUsageUI/Views/ThreadOSSettingsView.swift"))
        #expect(source.contains("Priced coverage \\(coverage)%"))
        #expect(source.contains("Local API equivalent, 7D"))
        #expect(source.contains("Priced tokens divided by observed ledger tokens; not account or 7D coverage."))
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
