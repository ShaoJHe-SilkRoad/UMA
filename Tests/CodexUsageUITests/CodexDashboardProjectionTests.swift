import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Codex dashboard projection")
struct CodexDashboardProjectionTests {
    @Test("populated local money card visibly identifies its estimate in both languages")
    func localEstimateTitleIsExplicit() {
        #expect(CodexDashboardPresentation.localEstimateTitle(language: .english)
            == "Local API equivalent estimate · 7D")
        #expect(CodexDashboardPresentation.localEstimateTitle(language: .simplifiedChinese)
            == "本地 API 等效估算 · 7天")
    }

    @Test("finite zero and full quota remain valid ring values")
    func finiteBoundaryValues() {
        let projection = makeProjection(fiveHour: quota(id: "5h", kind: .fiveHour, value: .remainingPercent(0)), sevenDay: quota(id: "7d", kind: .sevenDay, value: .remainingPercent(100)))
        #expect(projection.fiveHour.state == .finite(0))
        #expect(projection.fiveHour.state.ringPercent == 0)
        #expect(projection.fiveHour.state.ringFraction == 0)
        #expect(projection.sevenDay.state == .finite(100))
        #expect(projection.sevenDay.state.ringPercent == 100)
        #expect(projection.fiveHour.precision == .exact)
        #expect(projection.fiveHour.displayText(language: .english) == "0%")
        #expect(projection.sevenDay.displayText(language: .simplifiedChinese) == "100%")
    }

    @Test("estimated finite quotas keep their approximation in value and accessibility text")
    func estimatedFiniteQuotaPrecision() {
        let boundaries = makeProjection(
            fiveHour: quota(id: "5h", kind: .fiveHour, value: .remainingPercent(0), precision: .estimated),
            sevenDay: quota(id: "7d", kind: .sevenDay, value: .remainingPercent(100), precision: .estimated)
        )
        #expect(boundaries.fiveHour.precision == .estimated)
        #expect(boundaries.fiveHour.state.ringPercent == 0)
        #expect(boundaries.fiveHour.displayText(language: .english) == "≈0%")
        #expect(boundaries.sevenDay.state.ringPercent == 100)
        #expect(boundaries.sevenDay.displayText(language: .simplifiedChinese) == "≈100%")

        let rounded = makeProjection(
            fiveHour: quota(id: "5h", kind: .fiveHour, value: .remainingPercent(37.6), precision: .estimated),
            sevenDay: quota(id: "7d", kind: .sevenDay, value: .remainingPercent(37.6))
        )
        #expect(rounded.fiveHour.state.ringPercent == 37.6)
        #expect(rounded.fiveHour.displayText(language: .english) == "≈38%")
        #expect(rounded.sevenDay.displayText(language: .english) == "38%")
    }

    @Test("invalid values and stale values never become rings")
    func invalidAndStaleQuotaStates() {
        let invalid = quota(id: "5h", kind: .fiveHour, value: .remainingPercent(.infinity), precision: .estimated)
        let stale = quota(id: "7d", kind: .sevenDay, value: .remainingPercent(74), precision: .estimated, freshness: .stale)
        let projection = makeProjection(fiveHour: invalid, sevenDay: stale)
        #expect(projection.fiveHour.state == .invalid)
        #expect(projection.fiveHour.state.ringPercent == nil)
        #expect(projection.sevenDay.state == .stale)
        #expect(projection.sevenDay.state.ringPercent == nil)
        #expect(projection.fiveHour.displayText(language: .english) == "Invalid")
        #expect(projection.sevenDay.displayText(language: .simplifiedChinese) == "已过期")
    }

    @Test("unlimited and unavailable remain separate truthful states")
    func unlimitedAndUnavailableQuotaStates() {
        let unlimited = quota(id: "5h", kind: .fiveHour, value: .unlimited, precision: .estimated)
        let unavailable = quota(id: "7d", kind: .sevenDay, value: .unavailable, precision: .estimated, freshness: .unavailable)
        let projection = makeProjection(fiveHour: unlimited, sevenDay: unavailable)
        #expect(projection.fiveHour.state == .unlimited)
        #expect(projection.sevenDay.state == .unavailable)
        #expect(projection.fiveHour.displayText(language: .english) == "Unlimited")
        #expect(projection.sevenDay.displayText(language: .simplifiedChinese) == "未报告")
        let missing = CodexDashboardProjection(
            snapshot: snapshot(localFreshness: .fresh, capturedAt: Date(timeIntervalSince1970: 1_800_000_000)),
            provider: provider(quotas: [])
        )
        #expect(missing.fiveHour.precision == .unavailable)
        #expect(missing.fiveHour.displayText(language: .english) == "Not reported")
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

    @Test("history copy distinguishes account, admitted aggregate, stale, and unavailable sources")
    func historyCopyIsSourceBound() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var account = snapshot(localFreshness: .fresh, capturedAt: capturedAt,
                               accountDailyUsage: [AgentAccountUsageDay(day: "2027-01-15", tokens: 0)])
        let current = CodexDashboardProjection(snapshot: account, provider: provider(quotas: []))
        #expect(CodexDashboardPresentation.historySourceLine(current.historyAvailability, language: .english).contains("account history"))
        #expect(CodexDashboardPresentation.historyFootnote(current.historyAvailability, language: .simplifiedChinese).contains("零表示提供方报告为零"))

        account.accountDailyUsage = nil
        let aggregate = CodexDashboardProjection(snapshot: account, provider: provider(quotas: []))
        #expect(aggregate.historyAvailability == .aggregateOnly(capturedAt: capturedAt))
        #expect(CodexDashboardPresentation.historySourceLine(aggregate.historyAvailability, language: .english).contains("Local aggregate available"))
        #expect(CodexDashboardPresentation.historyFootnote(aggregate.historyAvailability, language: .simplifiedChinese).contains("保留原单位"))

        account.localSource = UsageSourceStatus(label: "local", scope: "local", capturedAt: capturedAt,
                                                isAvailable: true, freshness: .stale)
        let stale = CodexDashboardProjection(snapshot: account, provider: provider(quotas: []))
        #expect(stale.historyAvailability == .staleWithoutDailyBuckets(capturedAt: capturedAt))
        #expect(CodexDashboardPresentation.historySourceLine(stale.historyAvailability, language: .english).contains("stale"))
        #expect(CodexDashboardPresentation.historyFootnote(stale.historyAvailability, language: .simplifiedChinese).contains("已过期"))

        account.localSource = nil
        let unavailable = CodexDashboardProjection(snapshot: account, provider: provider(quotas: []))
        #expect(unavailable.historyAvailability == .unavailable)
        #expect(CodexDashboardPresentation.historySourceLine(unavailable.historyAvailability, language: .english).contains("no local aggregate admitted"))
        #expect(CodexDashboardPresentation.historyFootnote(unavailable.historyAvailability, language: .simplifiedChinese).contains("不可用"))

        account.localSource = UsageSourceStatus(label: "local", scope: "local", capturedAt: capturedAt,
                                                isAvailable: true, freshness: .fresh)
        account.apiCostEstimate = nil
        let freshButEmpty = CodexDashboardProjection(snapshot: account, provider: provider(quotas: []))
        #expect(freshButEmpty.historyAvailability == .unavailable,
                "Source presence alone cannot certify an aggregate.")
    }

    @Test("account and local values retain independent validity including zero and missing")
    func independentMetricSources() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var mixed = snapshot(localFreshness: .fresh, capturedAt: capturedAt)
        mixed.metrics = [UsageMetric(id: "week", value: "0", label: "7D")]
        mixed.apiCostEstimate = APICostEstimateSnapshot(sevenDayUSD: 0, lifetimeUSD: 0,
                                                       coveragePercent: 100, modelNames: [])
        mixed.providerSource = UsageSourceStatus(label: "account", scope: "account", capturedAt: capturedAt,
                                                  isAvailable: false, freshness: .unavailable)
        let unavailableProvider = provider(quotas: [], freshness: .unavailable)
        let localOnly = CodexDashboardProjection(snapshot: mixed, provider: unavailableProvider)
        let accountMetric = localOnly.metrics.first { $0.id == "week" }
        let localMetric = localOnly.metrics.first { $0.id == "api-cost-seven-days" }
        #expect(CodexDashboardPresentation.accountState(snapshot: mixed, provider: unavailableProvider) == .unavailable)
        #expect(CodexDashboardPresentation.localEstimateState(snapshot: mixed) == .current)
        #expect(CodexDashboardPresentation.metricValue(accountMetric, state: .unavailable) == "—")
        #expect(localMetric?.value == 0.0.formatted(.currency(code: "USD")))
        #expect(CodexDashboardPresentation.metricValue(localMetric, state: .current) == 0.0.formatted(.currency(code: "USD")))
        #expect(localOnly.historyAvailability == .aggregateOnly(capturedAt: capturedAt))
        mixed.providerSource = UsageSourceStatus(label: "account", scope: "account", capturedAt: capturedAt,
                                                  isAvailable: true, freshness: .fresh)
        #expect(CodexDashboardPresentation.accountState(snapshot: mixed, provider: unavailableProvider) == .unavailable,
                "An unavailable product cannot label an account observation as current or merely stale.")

        mixed.providerSource = UsageSourceStatus(label: "account", scope: "account", capturedAt: capturedAt,
                                                  isAvailable: true, freshness: .fresh)
        mixed.localSource = UsageSourceStatus(label: "local", scope: "local", capturedAt: capturedAt,
                                               isAvailable: false, freshness: .unavailable)
        let accountOnly = CodexDashboardProjection(snapshot: mixed, provider: provider(quotas: []))
        #expect(CodexDashboardPresentation.accountState(snapshot: mixed, provider: provider(quotas: [])) == .current)
        #expect(CodexDashboardPresentation.localEstimateState(snapshot: mixed) == .unavailable)
        #expect(CodexDashboardPresentation.metricValue(accountOnly.metrics.first { $0.id == "week" }, state: .current) == "0")
        #expect(CodexDashboardPresentation.metricValue(accountOnly.metrics.first { $0.id == "api-cost-seven-days" }, state: .unavailable) == "—")
        #expect(accountOnly.historyAvailability == .unavailable)

        mixed.localSource = UsageSourceStatus(label: "local", scope: "local", capturedAt: capturedAt,
                                               isAvailable: true, freshness: .stale)
        #expect(CodexDashboardPresentation.localEstimateState(snapshot: mixed) == .stale)
        mixed.metrics = [UsageMetric(id: "week", value: "—", label: "7D")]
        let missing = CodexDashboardProjection(snapshot: mixed, provider: provider(quotas: []))
        #expect(CodexDashboardPresentation.metricValue(missing.metrics.first { $0.id == "week" }, state: .current) == "—")
    }

    @Test("local activity follows its own source across mixed account states")
    func localActivitySourceDoesNotFollowAccount() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var mixed = snapshot(localFreshness: .fresh, capturedAt: capturedAt)
        mixed.recentTasks = [RecentTask(id: "local-1", title: "Allowed metadata", time: "today", tokenText: "12", progress: 0)]
        mixed.providerSource = UsageSourceStatus(label: "account", scope: "account", capturedAt: nil,
                                                  isAvailable: false, freshness: .unavailable)
        #expect(CodexDashboardPresentation.activityState(snapshot: mixed) == .current)
        mixed.providerSource = UsageSourceStatus(label: "account", scope: "account", capturedAt: capturedAt,
                                                  isAvailable: true, freshness: .fresh)
        mixed.localSource = UsageSourceStatus(label: "local", scope: "local", capturedAt: capturedAt,
                                               isAvailable: false, freshness: .unavailable)
        #expect(CodexDashboardPresentation.activityState(snapshot: mixed) == .unavailable)
        mixed.localSource = UsageSourceStatus(label: "local", scope: "local", capturedAt: capturedAt,
                                               isAvailable: true, freshness: .stale)
        #expect(CodexDashboardPresentation.activityState(snapshot: mixed) == .stale)
        mixed.localSource = UsageSourceStatus(label: "local", scope: "local", capturedAt: capturedAt,
                                               isAvailable: false, freshness: .stale)
        #expect(CodexDashboardPresentation.activityState(snapshot: mixed) == .unavailable)
        mixed.localSource = UsageSourceStatus(label: "local", scope: "local", capturedAt: capturedAt,
                                               isAvailable: true, freshness: .fresh)
        mixed.recentTasks = []
        #expect(CodexDashboardPresentation.activityState(snapshot: mixed) == .empty)
    }

    @Test("unavailable stale local source cannot become admitted history")
    func unavailableStaleLocalHistoryIsRejected() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var mixed = snapshot(localFreshness: .stale, capturedAt: capturedAt)
        mixed.localSource = UsageSourceStatus(label: "local", scope: "local", capturedAt: capturedAt,
                                               isAvailable: false, freshness: .stale)
        let projection = CodexDashboardProjection(snapshot: mixed, provider: provider(quotas: []))
        #expect(projection.historyAvailability == .unavailable)
        #expect(CodexDashboardPresentation.localEstimateState(snapshot: mixed) == .unavailable)
        #expect(CodexDashboardPresentation.historySourceLine(projection.historyAvailability, language: .english)
                    .contains("no local aggregate admitted"))
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

    private func quota(id: String, kind: ProviderProductQuotaKind, value: ProviderProductQuotaValue, precision: ProviderProductPrecision = .exact, freshness: ProviderProductFreshness = .fresh) -> ProviderProductQuotaState {
        ProviderProductQuotaState(id: id, kind: kind, compactLabel: id, value: value, precision: precision, freshness: freshness, comparison: .ineligible(.missing), resetsAt: nil)
    }

    private func provider(quotas: [ProviderProductQuotaState], freshness: ProviderProductFreshness = .fresh) -> ProviderProductState {
        ProviderProductState(id: .codex, quotas: quotas, precision: .exact, freshness: freshness, availability: .available, connection: .connected, health: .healthy, inventory: ProviderProductInventoryDisposition(overview: true, assistant: true, agentWorkspace: true), isActive: true)
    }

    private func snapshot(
        localFreshness: UsageSourceStatus.Freshness,
        capturedAt: Date,
        accountDailyUsage: [AgentAccountUsageDay]? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(planLabel: "PRO", periods: [], metrics: [UsageMetric(id: "week", value: "9.0M", label: "7D")], recentTasks: [], apiCostEstimate: APICostEstimateSnapshot(sevenDayUSD: 29.16, lifetimeUSD: 808_278.51, coveragePercent: 89, modelNames: []), accountDailyUsage: accountDailyUsage, availableResets: nil, updatedAt: capturedAt, providerSource: UsageSourceStatus(label: "Codex account", scope: "account", capturedAt: capturedAt, isAvailable: true, freshness: .fresh), localSource: UsageSourceStatus(label: "Codex local activity", scope: "local", capturedAt: capturedAt, isAvailable: localFreshness != .unavailable, coverage: 89, freshness: localFreshness))
    }
}
