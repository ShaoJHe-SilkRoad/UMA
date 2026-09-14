import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Codex dashboard projection")
struct CodexDashboardProjectionTests {
    @Test("finite zero and full quota remain valid ring values")
    func finiteBoundaryValues() {
        let projection = makeProjection(fiveHour: quota(id: "5h", kind: .fiveHour, value: .remainingPercent(0)), sevenDay: quota(id: "7d", kind: .sevenDay, value: .remainingPercent(100)))
        #expect(projection.fiveHour.state == .finite(0))
        #expect(projection.fiveHour.state.ringPercent == 0)
        #expect(projection.fiveHour.state.ringFraction == 0)
        #expect(projection.sevenDay.state == .finite(100))
        #expect(projection.sevenDay.state.ringPercent == 100)
    }

    @Test("invalid values and stale values never become rings")
    func invalidAndStaleQuotaStates() {
        let invalid = quota(id: "5h", kind: .fiveHour, value: .remainingPercent(.infinity))
        let stale = quota(id: "7d", kind: .sevenDay, value: .remainingPercent(74), freshness: .stale)
        let projection = makeProjection(fiveHour: invalid, sevenDay: stale)
        #expect(projection.fiveHour.state == .invalid)
        #expect(projection.fiveHour.state.ringPercent == nil)
        #expect(projection.sevenDay.state == .stale)
        #expect(projection.sevenDay.state.ringPercent == nil)
    }

    @Test("unlimited and unavailable remain separate truthful states")
    func unlimitedAndUnavailableQuotaStates() {
        let unlimited = quota(id: "5h", kind: .fiveHour, value: .unlimited)
        let unavailable = quota(id: "7d", kind: .sevenDay, value: .unavailable, freshness: .unavailable)
        let projection = makeProjection(fiveHour: unlimited, sevenDay: unavailable)
        #expect(projection.fiveHour.state == .unlimited)
        #expect(projection.sevenDay.state == .unavailable)
    }

    @Test("aggregate source states do not create daily history")
    func historyAvailabilityDoesNotInventBuckets() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let projection = CodexDashboardProjection(
            snapshot: snapshot(localFreshness: .stale, capturedAt: capturedAt),
            provider: provider(quotas: [])
        )
        #expect(projection.historyAvailability == .staleWithoutDailyBuckets(capturedAt: capturedAt))
        #expect(projection.metrics.first(where: { $0.id == "api-cost-seven-days" })?.coveragePercent == 89)
        #expect(projection.metrics.first(where: { $0.id == "api-cost-seven-days" })?.unit == .usd)
    }

    @Test("provider timestamped daily buckets remain account data rather than ledger reconstruction")
    func accountDailyBucketsRemainDistinct() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = snapshot(
            localFreshness: .fresh,
            capturedAt: capturedAt,
            accountDailyUsage: [
                AgentAccountUsageDay(day: "2026-09-12", tokens: 12),
                AgentAccountUsageDay(day: "2026-09-13", tokens: 24)
            ]
        )
        let projection = CodexDashboardProjection(snapshot: snapshot, provider: provider(quotas: []))
        #expect(projection.historyAvailability == .accountDailyBuckets(snapshot.accountDailyUsage ?? [], capturedAt: capturedAt))
    }

    @Test("daily presentation reserves explicit unknown and supplied-zero slots")
    func dailySlotsPreserveUnknownAndZero() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = snapshot(
            localFreshness: .fresh,
            capturedAt: capturedAt,
            accountDailyUsage: [
                AgentAccountUsageDay(day: "2027-01-13", tokens: 0),
                AgentAccountUsageDay(day: "2027-01-15", tokens: 24)
            ]
        )
        let projection = CodexDashboardProjection(snapshot: snapshot, provider: provider(quotas: []))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let slots = projection.dailySlots(calendar: calendar)
        #expect(slots.count == 7)
        #expect(slots.first(where: { $0.day == "2027-01-13" })?.tokens == 0)
        #expect(slots.first(where: { $0.day == "2027-01-14" })?.tokens == nil)
        #expect(slots.first(where: { $0.day == "2027-01-15" })?.tokens == 24)
    }

    @Test("schema-1 account metrics decode without runtime-only daily buckets")
    func legacyAccountMetricsDecodeWithoutDailyUsage() throws {
        let legacy = Data("""
        {"planLabel":"pro","availableResets":2,"lifetimeTokens":2319,"sevenDayTokens":989}
        """.utf8)
        let metrics = try JSONDecoder().decode(AgentAccountMetrics.self, from: legacy)
        #expect(metrics.dailyUsage.isEmpty)
        let encoded = try JSONEncoder().encode(metrics)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("dailyUsage"))
    }

    private func makeProjection(fiveHour: ProviderProductQuotaState, sevenDay: ProviderProductQuotaState) -> CodexDashboardProjection {
        CodexDashboardProjection(snapshot: snapshot(localFreshness: .fresh, capturedAt: Date(timeIntervalSince1970: 1_800_000_000)), provider: provider(quotas: [fiveHour, sevenDay]))
    }

    private func quota(id: String, kind: ProviderProductQuotaKind, value: ProviderProductQuotaValue, freshness: ProviderProductFreshness = .fresh) -> ProviderProductQuotaState {
        ProviderProductQuotaState(id: id, kind: kind, compactLabel: id, value: value, precision: .exact, freshness: freshness, comparison: .ineligible(.missing), resetsAt: nil)
    }

    private func provider(quotas: [ProviderProductQuotaState]) -> ProviderProductState {
        ProviderProductState(id: .codex, quotas: quotas, precision: .exact, freshness: .fresh, availability: .available, connection: .connected, health: .healthy, inventory: ProviderProductInventoryDisposition(overview: true, assistant: true, agentWorkspace: true), isActive: true)
    }

    private func snapshot(
        localFreshness: UsageSourceStatus.Freshness,
        capturedAt: Date,
        accountDailyUsage: [AgentAccountUsageDay]? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(planLabel: "PRO", periods: [], metrics: [UsageMetric(id: "week", value: "9.0M", label: "7D")], recentTasks: [], apiCostEstimate: APICostEstimateSnapshot(sevenDayUSD: 29.16, lifetimeUSD: 808_278.51, coveragePercent: 89, modelNames: []), accountDailyUsage: accountDailyUsage, availableResets: nil, updatedAt: capturedAt, providerSource: UsageSourceStatus(label: "Codex account", scope: "account", capturedAt: capturedAt, isAvailable: true, freshness: .fresh), localSource: UsageSourceStatus(label: "Codex local activity", scope: "local", capturedAt: capturedAt, isAvailable: localFreshness != .unavailable, coverage: 89, freshness: localFreshness))
    }
}
