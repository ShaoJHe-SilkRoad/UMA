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
        let resetAt: Date?
        let capturedAt: Date?
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
        /// Explicitly approximate scientific display, only for an amount too
        /// wide even for the full metric region. `value` retains full format.
        var compactValue: String? = nil
    }

    struct DailySlot: Equatable, Sendable, Identifiable {
        let day: String
        let tokens: Int64?
        var id: String { day }
    }

    /// Statistics describe only a complete, contiguous seven-day series.
    struct DailyAnalysis: Equatable, Sendable {
        struct Summary: Equatable, Sendable {
            let total: Int64
            let mean: Double
            let peak: DailySlot
            let cumulative: [String: Int64]
            let shares: [String: Double]
        }

        enum UnavailabilityReason: String, Equatable, Sendable {
            case missingDays
            case invalidSequence
            case overflow

            func message(isChinese: Bool) -> String {
                switch self {
                case .missingDays:
                    return isChinese ? "逐日覆盖不完整，区间统计不可用。" : "Incomplete daily coverage; interval statistics unavailable."
                case .invalidSequence:
                    return isChinese ? "逐日数据存在非法日期、冲突或无效数值，区间统计不可用。" : "Daily dates or values are invalid or conflicting; interval statistics unavailable."
                case .overflow:
                    return isChinese ? "区间总和超出可计算范围；已知逐日数值仍可查看。" : "Interval total exceeds the calculation range; known daily values remain available."
                }
            }
        }

        let slots: [DailySlot]
        let summary: Summary?
        let unavailabilityReason: UnavailabilityReason?

        var knownSlots: [DailySlot] { slots.filter { ($0.tokens ?? -1) >= 0 } }
        func selected(_ day: String?) -> DailySlot? {
            knownSlots.first { $0.day == day }
        }

        init(slots: [DailySlot], calendar: Calendar = .current, hasInvalidInput: Bool = false) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            let ordered = slots.sorted { $0.day < $1.day }
            self.slots = ordered
            guard !hasInvalidInput, ordered.count <= 7,
                  Set(ordered.map(\.day)).count == ordered.count,
                  ordered.allSatisfy({ slot in
                      guard let date = formatter.date(from: slot.day),
                            formatter.string(from: date) == slot.day else { return false }
                      return slot.tokens.map { $0 >= 0 } ?? true
                  }) else {
                summary = nil; unavailabilityReason = .invalidSequence; return
            }
            guard ordered.count == 7, let first = ordered.first,
                  let start = formatter.date(from: first.day) else {
                summary = nil; unavailabilityReason = .missingDays; return
            }
            guard ordered.enumerated().allSatisfy({ index, slot in
                guard let date = calendar.date(byAdding: .day, value: index, to: start) else { return false }
                return formatter.string(from: date) == slot.day
            }) else {
                summary = nil; unavailabilityReason = .invalidSequence; return
            }
            guard ordered.allSatisfy({ $0.tokens != nil }) else {
                summary = nil; unavailabilityReason = .missingDays; return
            }
            var total: Int64 = 0
            var cumulative: [String: Int64] = [:]
            var peak = first
            for slot in ordered {
                guard let tokens = slot.tokens else { summary = nil; unavailabilityReason = .missingDays; return }
                let sum = total.addingReportingOverflow(tokens)
                guard !sum.overflow else { summary = nil; unavailabilityReason = .overflow; return }
                total = sum.partialValue
                cumulative[slot.day] = total
                if tokens > (peak.tokens ?? 0) { peak = slot }
            }
            let shares = total == 0 ? [:] : Dictionary(uniqueKeysWithValues: ordered.map {
                ($0.day, Double($0.tokens!) / Double(total))
            })
            unavailabilityReason = nil
            summary = Summary(total: total, mean: Double(total) / 7, peak: peak,
                              cumulative: cumulative, shares: shares)
        }
    }

    func dailyAnalysis(calendar: Calendar = .current) -> DailyAnalysis {
        let input = dailyInput(calendar: calendar)
        return DailyAnalysis(slots: input.slots, calendar: calendar, hasInvalidInput: input.hasInvalidValues)
    }

    let fiveHour: Quota
    let fiveHourObservationState: QuotaState
    let sevenDay: Quota
    let historyAvailability: HistoryAvailability
    let metrics: [Metric]

    /// Seven explicit local-calendar slots ending at the captured snapshot
    /// day. `nil` is an unknown/provider-conflicted day, never a zero.
    func dailySlots(calendar: Calendar = .current) -> [DailySlot] {
        dailyInput(calendar: calendar).slots
    }

    private func dailyInput(calendar: Calendar) -> (slots: [DailySlot], hasInvalidValues: Bool) {
        guard case let .accountDailyBuckets(days, capturedAt) = historyAvailability else { return ([], false) }
        let anchor = calendar.startOfDay(for: capturedAt ?? Date())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        // Preserve conflicting or invalid days as unknown even for defensive
        // callers that have not passed through the normal admission boundary.
        var supplied: [String: Int64] = [:]
        var rejected: Set<String> = []
        formatter.isLenient = false
        var hasInvalidValues = false
        for value in days {
            guard let date = formatter.date(from: value.day),
                  formatter.string(from: date) == value.day else { hasInvalidValues = true; continue }
            if value.tokens < 0 || (supplied[value.day] != nil && supplied[value.day] != value.tokens) {
                rejected.insert(value.day)
                hasInvalidValues = true
            } else { supplied[value.day] = value.tokens }
        }
        for day in rejected { supplied.removeValue(forKey: day) }
        let slots: [DailySlot] = (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: anchor) else { return nil }
            let day = formatter.string(from: date)
            return DailySlot(day: day, tokens: supplied[day])
        }
        return (slots, hasInvalidValues)
    }

    init(snapshot: UsageSnapshot, provider: ProviderProductState?) {
        let quotas = provider?.quotas ?? []
        let rawFiveHour = Self.quota(
            kind: .fiveHour,
            title: "5H remaining",
            quota: quotas.first(where: { $0.kind == .fiveHour }),
            providerCapturedAt: provider?.capturedAt
        )
        fiveHourObservationState = rawFiveHour.state
        // Product presentation rule only. Membership is already admitted;
        // do not normalize labels here or mutate the provider quota payload.
        if provider?.id == .codex, provider?.planLabel == "pro" {
            fiveHour = Quota(id: rawFiveHour.id, kind: .fiveHour, title: "5H",
                             state: .unlimited, resetAt: nil, capturedAt: rawFiveHour.capturedAt)
        } else { fiveHour = rawFiveHour }
        sevenDay = Self.quota(
            kind: .sevenDay,
            title: "7D remaining",
            quota: quotas.first(where: { $0.kind == .sevenDay }),
            providerCapturedAt: provider?.capturedAt
        )

        if provider?.freshness == .unavailable {
            historyAvailability = .unavailable
        } else if let dailyUsage = snapshot.accountDailyUsage, !dailyUsage.isEmpty,
           snapshot.providerSource?.freshness == .fresh {
            historyAvailability = .accountDailyBuckets(
                dailyUsage,
                capturedAt: snapshot.providerSource?.capturedAt
            )
        } else {
            switch snapshot.localSource?.freshness {
        case .fresh:
            historyAvailability = .aggregateOnly(capturedAt: snapshot.localSource?.capturedAt)
        case .stale:
            historyAvailability = .staleWithoutDailyBuckets(capturedAt: snapshot.localSource?.capturedAt)
        case .unavailable, .none:
            historyAvailability = .unavailable
            }
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
                    capturedAt: snapshot.localSource?.capturedAt ?? snapshot.updatedAt,
                    compactValue: Self.compactUSD(estimate.sevenDayUSD)
                ),
                Metric(
                    id: "api-cost-lifetime",
                    value: estimate.lifetimeUSD.formatted(.currency(code: "USD")),
                    period: .lifetime,
                    unit: .usd,
                    coveragePercent: Self.validCoverage(estimate.coveragePercent),
                    capturedAt: snapshot.localSource?.capturedAt ?? snapshot.updatedAt,
                    compactValue: Self.compactUSD(estimate.lifetimeUSD)
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
            return Quota(id: "missing-\(title)", kind: kind, title: title, state: .unavailable, resetAt: nil, capturedAt: providerCapturedAt)
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
        return Quota(id: quota.id, kind: kind, title: quota.compactLabel, state: state, resetAt: quota.resetsAt, capturedAt: providerCapturedAt)
    }

    private static func period(for id: String) -> MetricPeriod {
        switch id {
        case "week": .sevenDays
        case "total": .lifetime
        default: .current
        }
    }

    private static func compactUSD(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        return "≈ USD " + value.formatted(.number.notation(.scientific).precision(.significantDigits(4)))
    }

    private static func validCoverage(_ value: Int) -> Int? {
        (0...100).contains(value) ? value : nil
    }
}
