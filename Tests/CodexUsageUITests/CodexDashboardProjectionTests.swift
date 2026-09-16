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

    @Test("complete daily statistics use exact sums and earliest tied peak")
    func completeDailyStatistics() throws {
        let values: [Int64?] = [0, 100, 200, 200, 0, 0, 0]
        let analysis = analysis(values)
        let summary = try #require(analysis.summary)
        #expect(analysis.unavailabilityReason == nil)
        #expect(summary.total == 500)
        #expect(summary.mean == 500.0 / 7)
        #expect(summary.peak.day == "2027-01-12")
        #expect(summary.cumulative["2027-01-12"] == 300)
        #expect(summary.cumulative["2027-01-16"] == 500)
        #expect(summary.shares["2027-01-12"] == 0.4)
        #expect(analysis.selected("2027-01-10")?.tokens == 0)
        #expect(analysis.selected(nil) == nil)
        let reversed = CodexDashboardProjection.DailyAnalysis(slots: analysis.slots.reversed())
        #expect(reversed.summary == summary)
    }

    @Test("partial series never yields statistics but retains known zero selection")
    func partialDailyStatistics() {
        for missing in 0..<7 {
            var values: [Int64?] = [0, 10, 20, 30, 40, 50, 60]
            values[missing] = nil
            let result = analysis(values)
            #expect(result.summary == nil)
            #expect(result.unavailabilityReason == .missingDays)
            #expect(result.knownSlots.count == 6)
            #expect(result.selected(result.slots[missing].day) == nil)
        }
        #expect(analysis(Array(repeating: nil, count: 7)).knownSlots.isEmpty)
        #expect(analysis([0]).summary == nil)
    }

    @Test("all zero daily series has zero sums and no undefined shares")
    func zeroDailyStatistics() throws {
        let result = analysis(Array(repeating: 0, count: 7))
        let summary = try #require(result.summary)
        #expect(result.unavailabilityReason == nil)
        #expect(summary.total == 0)
        #expect(summary.mean == 0)
        #expect(summary.shares.isEmpty)
        #expect(summary.cumulative.values.allSatisfy { $0 == 0 })
        #expect(summary.peak.day == "2027-01-10")
        #expect(result.knownSlots.count == 7)
    }

    @Test("overflow negative duplicate and noncontiguous series suppress all derived values")
    func invalidDailyStatistics() {
        let overflowing = analysis([Int64.max, 1, 0, 0, 0, 0, 0])
        #expect(overflowing.summary == nil)
        #expect(overflowing.unavailabilityReason == .overflow)
        #expect(overflowing.knownSlots.count == 7)
        #expect(overflowing.selected("2027-01-10")?.tokens == Int64.max)
        let negative = analysis([0, -1, 0, 0, 0, 0, 0])
        #expect(negative.summary == nil)
        #expect(negative.unavailabilityReason == .invalidSequence)
        #expect(negative.selected("2027-01-11") == nil)
        #expect(analysis([Int64.max, 0, 0, 0, 0, 0, 0]).summary?.total == Int64.max)
        var slots = analysis(Array(repeating: 1, count: 7)).slots
        slots[6] = slots[0]
        #expect(CodexDashboardProjection.DailyAnalysis(slots: slots).summary == nil)
        #expect(CodexDashboardProjection.DailyAnalysis(slots: slots).unavailabilityReason == .invalidSequence)
        slots[6] = .init(day: "2027-01-18", tokens: 1)
        #expect(CodexDashboardProjection.DailyAnalysis(slots: slots).summary == nil)
        #expect(CodexDashboardProjection.DailyAnalysis(slots: slots).unavailabilityReason == .invalidSequence)
    }

    @Test("conflicting duplicates remain unknown while identical duplicates count once")
    func duplicateAdmissionDefense() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let days = [AgentAccountUsageDay(day: "2027-01-13", tokens: 0),
                    AgentAccountUsageDay(day: "2027-01-13", tokens: 0),
                    AgentAccountUsageDay(day: "2027-01-14", tokens: 20),
                    AgentAccountUsageDay(day: "2027-01-14", tokens: 30),
                    AgentAccountUsageDay(day: "2027-01-14", tokens: 20),
                    AgentAccountUsageDay(day: "2027-01-15", tokens: -1)]
        let result = CodexDashboardProjection(
            snapshot: snapshot(localFreshness: .fresh, capturedAt: Date(timeIntervalSince1970: 1_800_000_000), accountDailyUsage: days),
            provider: provider(quotas: [])).dailyAnalysis(calendar: calendar)
        #expect(result.selected("2027-01-13")?.tokens == 0)
        #expect(result.selected("2027-01-14") == nil)
        #expect(result.selected("2027-01-15") == nil)
        #expect(result.summary == nil)
    }

    @Test("only admitted Codex pro gets presentation infinity and raw quota is unchanged")
    func proPresentationMapping() {
        let raw = ProviderProductQuotaState(id: "5h", kind: .fiveHour, compactLabel: "5H",
            value: .remainingPercent(42), precision: .exact, freshness: .fresh,
            comparison: .ineligible(.missing), resetsAt: Date(timeIntervalSince1970: 1_800_003_600))
        let cases: [(ProviderProductID, String?, Bool)] = [
            (.codex, "pro", true), (.codex, "plus", false), (.claude, "pro", false),
            (.claude, "max", false), (.codex, "unknown", false), (.codex, nil, false),
            (.codex, "", false), (.codex, "pro max", false), (.codex, "PRO", false)
        ]
        for (id, plan, infinity) in cases {
            let state = ProviderProductState(id: id, planLabel: plan, quotas: [raw],
                freshness: .fresh, availability: .available, connection: .connected, health: .healthy,
                inventory: .init(overview: true, assistant: true, agentWorkspace: true), isActive: true)
            let result = CodexDashboardProjection(snapshot: snapshot(localFreshness: .fresh, capturedAt: Date()), provider: state)
            #expect(result.fiveHour.state == (infinity ? .unlimited : .finite(42)))
            #expect(result.fiveHour.resetAt == (infinity ? nil : raw.resetsAt))
            #expect(state.quotas == [raw])
            #expect(state.planLabel == plan)
        }
        #expect(CodexDashboardProjection(snapshot: snapshot(localFreshness: .fresh, capturedAt: Date()), provider: nil).fiveHour.state == .unavailable)
    }

    @Test("Pro presentation retains stale and invalid observation state")
    func proObservationWarnings() {
        for raw in [quota(id: "5h", kind: .fiveHour, value: .remainingPercent(42), freshness: .stale),
                    quota(id: "5h", kind: .fiveHour, value: .remainingPercent(.nan))] {
            let state = ProviderProductState(id: .codex, planLabel: "pro", quotas: [raw],
                freshness: .stale, availability: .available, connection: .failed, health: .healthy,
                inventory: .init(overview: true, assistant: true, agentWorkspace: true), isActive: true)
            let result = CodexDashboardProjection(snapshot: snapshot(localFreshness: .fresh, capturedAt: Date()), provider: state)
            #expect(result.fiveHour.state == .unlimited)
            #expect(result.fiveHourObservationState == (raw.freshness == .stale ? .stale : .invalid))
            #expect(result.fiveHour.resetAt == nil)
        }
    }

    @Test("missing invalid and overflow diagnostics are distinct in both languages")
    func distinctAnalysisDiagnostics() {
        typealias Reason = CodexDashboardProjection.DailyAnalysis.UnavailabilityReason
        let missing = analysis([0, nil, 0, 0, 0, 0, 0])
        let invalid = analysis([0, -1, 0, 0, 0, 0, 0])
        let overflow = analysis([Int64.max, 1, 0, 0, 0, 0, 0])
        #expect(missing.unavailabilityReason == .missingDays)
        #expect(invalid.unavailabilityReason == .invalidSequence)
        #expect(overflow.unavailabilityReason == .overflow)
        for chinese in [false, true] {
            let messages = [Reason.missingDays, .invalidSequence, .overflow].map { $0.message(isChinese: chinese) }
            #expect(Set(messages).count == 3)
            #expect(!Reason.overflow.message(isChinese: chinese).contains(chinese ? "覆盖不完整" : "Incomplete"))
        }
        var slots = analysis(Array(repeating: 0, count: 7)).slots
        slots[0] = .init(day: "2027-02-30", tokens: 0)
        #expect(CodexDashboardProjection.DailyAnalysis(slots: slots).unavailabilityReason == .invalidSequence)
    }

    @Test("source conflicts and invalid values retain their diagnostic after unknown slot projection")
    func invalidInputProvenance() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let captured = Date(timeIntervalSince1970: 1_800_000_000)
        for extras in [
            [AgentAccountUsageDay(day: "2027-01-13", tokens: 1)],
            [AgentAccountUsageDay(day: "2027-01-14", tokens: -1)],
            [AgentAccountUsageDay(day: "2027-02-30", tokens: 3)]
        ] {
            let days = [AgentAccountUsageDay(day: "2027-01-13", tokens: 0)] + extras
            let result = CodexDashboardProjection(
                snapshot: snapshot(localFreshness: .fresh, capturedAt: captured, accountDailyUsage: days),
                provider: provider(quotas: [])).dailyAnalysis(calendar: calendar)
            #expect(result.summary == nil)
            #expect(result.unavailabilityReason == .invalidSequence)
        }
    }

    @Test("Pro with no raw 5H window keeps the specified infinity presentation")
    func proWithoutRawFiveHour() {
        let state = ProviderProductState(id: .codex, planLabel: "pro", quotas: [],
            freshness: .fresh, availability: .available, connection: .connected, health: .healthy,
            inventory: .init(overview: true, assistant: true, agentWorkspace: true), isActive: true)
        let result = CodexDashboardProjection(snapshot: snapshot(localFreshness: .fresh, capturedAt: Date()), provider: state)
        #expect(result.fiveHour.state == .unlimited)
        #expect(result.fiveHour.resetAt == nil)
        #expect(result.fiveHourObservationState == .unavailable)
        #expect(state.quotas.isEmpty)
    }

    @Test("extreme currency compact presentation is explicit and retains the full formatted amount")
    func compactCurrencyKeepsOriginal() throws {
        var source = snapshot(localFreshness: .fresh, capturedAt: Date())
        source.apiCostEstimate = APICostEstimateSnapshot(sevenDayUSD: Double.greatestFiniteMagnitude,
            lifetimeUSD: Double.greatestFiniteMagnitude, coveragePercent: 89, modelNames: [])
        let result = CodexDashboardProjection(snapshot: source, provider: provider(quotas: []))
        let cost = try #require(result.metrics.first { $0.id == "api-cost-seven-days" })
        #expect(cost.value == Double.greatestFiniteMagnitude.formatted(.currency(code: "USD")))
        #expect(cost.compactValue?.hasPrefix("≈ USD ") == true)
        #expect(cost.value != cost.compactValue)
        #expect(source.apiCostEstimate?.sevenDayUSD == Double.greatestFiniteMagnitude)
    }

    private func analysis(_ values: [Int64?]) -> CodexDashboardProjection.DailyAnalysis {
        CodexDashboardProjection.DailyAnalysis(slots: values.enumerated().map {
            .init(day: "2027-01-\(10 + $0.offset)", tokens: $0.element)
        })
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
