import Foundation

/// Read-only presentation adapter for the Codex detail dashboard. It consumes
/// the already-admitted UsageStore snapshot and product inventory only: it
/// neither starts collection nor reconstructs per-day history from totals.
struct CodexDashboardProjection: Equatable, Sendable {
    enum QuotaState: Equatable, Sendable {
        case finite(Double)
        case unlimited
        case unavailable
        case invalid
        case stale

        var ringPercent: Double? {
            guard case let .finite(value) = self else { return nil }
            return value
        }

        var ringFraction: Double? { ringPercent.map { $0 / 100 } }
    }

    struct Quota: Equatable, Sendable, Identifiable {
        let id: String
        let kind: ProviderProductQuotaKind
        let title: String
        let state: QuotaState
        let precision: ProviderProductPrecision
        let resetAt: Date?
        let capturedAt: Date?

        /// One source for the visible quota value and its accessibility text.
        func displayText(language: AppLanguage) -> String {
            switch state {
            case let .finite(value):
                let approximation = precision == .estimated ? "≈" : ""
                return "\(approximation)\(Int(value.rounded()))%"
            case .unlimited: return language == .simplifiedChinese ? "无限额" : "Unlimited"
            case .unavailable: return language == .simplifiedChinese ? "未报告" : "Not reported"
            case .invalid: return language == .simplifiedChinese ? "无效" : "Invalid"
            case .stale: return language == .simplifiedChinese ? "已过期" : "Stale"
            }
        }
    }

    enum HistoryAvailability: Equatable, Sendable {
        /// Explicit provider-reported account-day totals. The source owns day
        /// assignment; UMA only renders the admitted values as supplied.
        case accountDailyBuckets([AgentAccountUsageDay], capturedAt: Date?)
        /// No local source was admitted for the current snapshot.
        case unavailable
        /// The last local source is retained but is no longer current. It does
        /// not authorize a chart with inferred buckets.
        case staleWithoutDailyBuckets(capturedAt: Date?)
        /// Aggregate local metrics exist, but no timestamped daily series was
        /// admitted to this presentation boundary.
        case aggregateOnly(capturedAt: Date?)
    }

    enum MetricPeriod: Equatable, Sendable { case current, sevenDays, lifetime }
    enum MetricUnit: Equatable, Sendable { case tokens, usd }

    struct Metric: Equatable, Sendable, Identifiable {
        let id: String
        let value: String?
        let period: MetricPeriod
        let unit: MetricUnit
        /// Coverage is meaningful only for API-equivalent cost projections.
        let coveragePercent: Int?
        let capturedAt: Date?
    }

    struct DailySlot: Equatable, Sendable, Identifiable {
        let day: String
        let tokens: Int64?
        var id: String { day }
    }

    let fiveHour: Quota
    let sevenDay: Quota
    let historyAvailability: HistoryAvailability
    let metrics: [Metric]

    /// Seven explicit local-calendar slots ending at the captured snapshot
    /// day. `nil` is an unknown/provider-conflicted day, never a zero.
    func dailySlots(calendar: Calendar = .current) -> [DailySlot] {
        guard case let .accountDailyBuckets(days, capturedAt) = historyAvailability else { return [] }
        let anchor = calendar.startOfDay(for: capturedAt ?? Date())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let supplied = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0.tokens) })
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: anchor) else { return nil }
            let day = formatter.string(from: date)
            return DailySlot(day: day, tokens: supplied[day])
        }
    }

    init(snapshot: UsageSnapshot, provider: ProviderProductState?) {
        let quotas = provider?.quotas ?? []
        fiveHour = Self.quota(
            kind: .fiveHour,
            title: "5H remaining",
            quota: quotas.first(where: { $0.kind == .fiveHour }),
            providerCapturedAt: provider?.capturedAt
        )
        sevenDay = Self.quota(
            kind: .sevenDay,
            title: "7D remaining",
            quota: quotas.first(where: { $0.kind == .sevenDay }),
            providerCapturedAt: provider?.capturedAt
        )

        if let dailyUsage = snapshot.accountDailyUsage, !dailyUsage.isEmpty,
           provider?.freshness == .fresh,
           snapshot.providerSource?.isAvailable == true,
           snapshot.providerSource?.freshness == .fresh {
            historyAvailability = .accountDailyBuckets(
                dailyUsage,
                capturedAt: snapshot.providerSource?.capturedAt
            )
        } else if let local = snapshot.localSource, local.isAvailable {
            switch local.freshness {
            case .fresh where snapshot.apiCostEstimate != nil:
                historyAvailability = .aggregateOnly(capturedAt: local.capturedAt)
            case .stale:
                historyAvailability = .staleWithoutDailyBuckets(capturedAt: local.capturedAt)
            case .fresh, .unavailable:
                historyAvailability = .unavailable
            }
        } else {
            historyAvailability = .unavailable
        }

        let knownMetrics = snapshot.metrics.map { metric in
            Metric(
                id: metric.id,
                value: metric.value == "—" ? nil : metric.value,
                period: Self.period(for: metric.id),
                unit: .tokens,
                coveragePercent: nil,
                capturedAt: snapshot.providerSource?.capturedAt ?? snapshot.updatedAt
            )
        }
        if let estimate = snapshot.apiCostEstimate {
            metrics = knownMetrics + [
                Metric(
                    id: "api-cost-seven-days",
                    value: estimate.sevenDayUSD.formatted(.currency(code: "USD")),
                    period: .sevenDays,
                    unit: .usd,
                    coveragePercent: Self.validCoverage(estimate.coveragePercent),
                    capturedAt: snapshot.localSource?.capturedAt ?? snapshot.updatedAt
                ),
                Metric(
                    id: "api-cost-lifetime",
                    value: estimate.lifetimeUSD.formatted(.currency(code: "USD")),
                    period: .lifetime,
                    unit: .usd,
                    coveragePercent: Self.validCoverage(estimate.coveragePercent),
                    capturedAt: snapshot.localSource?.capturedAt ?? snapshot.updatedAt
                )
            ]
        } else {
            metrics = knownMetrics
        }
    }

    private static func quota(
        kind: ProviderProductQuotaKind,
        title: String,
        quota: ProviderProductQuotaState?,
        providerCapturedAt: Date?
    ) -> Quota {
        guard let quota else {
            return Quota(id: "missing-\(title)", kind: kind, title: title, state: .unavailable,
                         precision: .unavailable, resetAt: nil, capturedAt: providerCapturedAt)
        }

        let state: QuotaState
        if quota.freshness == .stale {
            state = .stale
        } else { switch quota.value {
        case let .remainingPercent(value):
            state = value.isFinite && (0...100).contains(value) ? .finite(value) : .invalid
        case .unlimited:
            state = quota.freshness == .stale ? .stale : .unlimited
        case .unavailable:
            if quota.freshness == .stale {
                state = .stale
            } else if quota.comparison == .ineligible(.invalid) {
                state = .invalid
            } else {
                state = .unavailable
            }
        case .remainingCredits:
            state = .unavailable
        } }
        return Quota(id: quota.id, kind: kind, title: quota.compactLabel, state: state,
                     precision: quota.precision, resetAt: quota.resetsAt,
                     capturedAt: providerCapturedAt)
    }

    private static func period(for id: String) -> MetricPeriod {
        switch id {
        case "week": .sevenDays
        case "total": .lifetime
        default: .current
        }
    }

    private static func validCoverage(_ value: Int) -> Int? {
        (0...100).contains(value) ? value : nil
    }
}
