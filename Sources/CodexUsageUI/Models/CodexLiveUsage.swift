import Foundation

struct CodexLiveUsage: Sendable {
    let rateLimits: CodexRateLimitSnapshot
    let availableResetCount: Int?
    let lifetimeTokens: Int64?
    let dailyUsage: [CodexDailyUsage]?
    let recentActivityCount: Int
    let apiCostEstimate: CodexAPICostEstimate?
    /// Account values originate only from the official local app-server.
    /// Local session metadata is deliberately a separate optional channel.
    let providerCapturedAt: Date
    let localActivity: CodexLocalActivitySnapshot?

    init(
        rateLimits: CodexRateLimitSnapshot,
        availableResetCount: Int?,
        lifetimeTokens: Int64?,
        dailyUsage: [CodexDailyUsage]?,
        recentActivityCount: Int,
        apiCostEstimate: CodexAPICostEstimate?,
        providerCapturedAt: Date = Date(),
        localActivity: CodexLocalActivitySnapshot? = nil
    ) {
        self.rateLimits = rateLimits
        self.availableResetCount = availableResetCount
        self.lifetimeTokens = lifetimeTokens
        self.dailyUsage = dailyUsage
        self.recentActivityCount = recentActivityCount
        self.apiCostEstimate = apiCostEstimate
        self.providerCapturedAt = providerCapturedAt
        self.localActivity = localActivity
    }
}

struct CodexAPICostEstimate: Sendable {
    let sevenDayUSD: Double
    let lifetimeUSD: Double
    let pricedTokens: Int64
    let observedTokens: Int64
    let modelNames: [String]
}

struct CodexRateLimitSnapshot: Sendable {
    let planType: String?
    let windows: [CodexRateLimitWindow]
    let sourceLimitIDs: [String]
    let serverLimitID: String?
    let creditsUnlimited: Bool?

    init(
        planType: String?,
        windows: [CodexRateLimitWindow],
        sourceLimitIDs: [String] = [],
        serverLimitID: String? = nil,
        creditsUnlimited: Bool? = nil
    ) {
        self.planType = planType
        self.windows = windows
        self.sourceLimitIDs = sourceLimitIDs
        self.serverLimitID = serverLimitID
        self.creditsUnlimited = creditsUnlimited
    }

    // Compatibility accessors for callers that have not yet moved to the
    // stable server-provided limit identifiers.
    var primary: CodexRateLimitWindow? { windows.first }
    var secondary: CodexRateLimitWindow? { windows.dropFirst().first }

    /// The panel has one row for each standard account window. The local
    /// app-server can report several source limits for a standard duration;
    /// retain the most restrictive real window so an unused duplicate cannot
    /// incorrectly reassure the Human with a second 100% row.
    var displayWindows: [CodexRateLimitWindow] {
        var selected: [CodexRateLimitWindow.Kind: CodexRateLimitWindow] = [:]
        var passthrough: [CodexRateLimitWindow] = []
        for window in windows {
            guard window.kind == .fiveHour || window.kind == .sevenDay else {
                passthrough.append(window)
                continue
            }
            guard let current = selected[window.kind] else {
                selected[window.kind] = window
                continue
            }
            selected[window.kind] = Self.isMoreRestrictive(window, than: current) ? window : current
        }
        return (selected.values + passthrough).sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.id < $1.id
        }
    }

    private static func isMoreRestrictive(
        _ candidate: CodexRateLimitWindow,
        than current: CodexRateLimitWindow
    ) -> Bool {
        // `credits.unlimited` is an authoritative provider grant, not an
        // optimistic percentage.  Prefer it over a duplicate ordinary window
        // so a zero-percent fallback cannot erase the special five-hour
        // state during normalized selection.
        if candidate.creditsUnlimited != current.creditsUnlimited {
            return candidate.creditsUnlimited == true
        }
        let candidateUsed = candidate.usedPercent.isFinite ? candidate.usedPercent : -.infinity
        let currentUsed = current.usedPercent.isFinite ? current.usedPercent : -.infinity
        if candidateUsed != currentUsed { return candidateUsed > currentUsed }
        return candidate.id < current.id
    }
}

struct CodexRateLimitWindow: Sendable {
    enum Kind: Int, Sendable {
        case fiveHour = 0
        case sevenDay = 1
        case custom = 2
        case unknown = 3
    }

    let id: String
    let sourceLimitID: String
    let serverLimitID: String?
    let creditsUnlimited: Bool?
    let kind: Kind
    let usedPercent: Double
    let windowDurationMinutes: Int?
    let resetsAt: Date?

    init(
        id: String,
        sourceLimitID: String? = nil,
        serverLimitID: String? = nil,
        creditsUnlimited: Bool? = nil,
        usedPercent: Double,
        windowDurationMinutes: Int?,
        resetsAt: Date?
    ) {
        self.id = id
        self.sourceLimitID = sourceLimitID ?? id
        self.serverLimitID = serverLimitID
        self.creditsUnlimited = creditsUnlimited
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
        switch windowDurationMinutes {
        case 300: kind = .fiveHour
        case 10_080: kind = .sevenDay
        case .some: kind = .custom
        case nil: kind = .unknown
        }
    }
}

struct CodexDailyUsage: Codable, Sendable {
    let startDate: String
    let tokens: Int64
}

extension CodexLiveUsage {
    func replacingLocalActivity(_ activity: CodexLocalActivitySnapshot) -> CodexLiveUsage {
        CodexLiveUsage(
            rateLimits: rateLimits,
            availableResetCount: availableResetCount,
            lifetimeTokens: lifetimeTokens,
            dailyUsage: dailyUsage,
            recentActivityCount: recentActivityCount,
            apiCostEstimate: apiCostEstimate,
            providerCapturedAt: providerCapturedAt,
            localActivity: activity
        )
    }
}

extension UsageSnapshot {
    init(live: CodexLiveUsage, language: AppLanguage, now: Date = Date()) {
        let windows = live.rateLimits.displayWindows
        var periods = windows.enumerated().map { index, window in
            let remaining = max(0, min(100, Int((100 - window.usedPercent).rounded())))
            return UsagePeriod(
                id: window.id,
                title: language.quotaTitle(durationMinutes: window.windowDurationMinutes, index: index),
                remainingPercent: remaining,
                isFiveHour: window.kind == .fiveHour,
                isUnlimited: window.kind == .fiveHour
                    && (window.creditsUnlimited == true || live.rateLimits.creditsUnlimited == true),
                resetText: language.resetDescription(for: window.resetsAt, now: now)
            )
        }
        let hasFiveHourWindow = windows.contains(where: { $0.kind == .fiveHour })
        let hasValidatedWeeklyWindow = windows.contains(where: { $0.kind == .sevenDay })
        if !hasFiveHourWindow,
           (live.rateLimits.creditsUnlimited == true || hasValidatedWeeklyWindow) {
            periods.insert(
                UsagePeriod(
                    id: "provider.unlimited-five-hour",
                    title: language.quotaTitle(durationMinutes: 300, index: 0),
                    remainingPercent: 100,
                    isFiveHour: true,
                    isUnlimited: true,
                    resetText: language.resetDescription(for: nil, now: now)
                ),
                at: 0
            )
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let sevenDayCutoff = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd"
        let sevenDayTokens = live.dailyUsage.map { buckets in
            buckets.reduce(into: Int64(0)) { total, bucket in
                if let date = parser.date(from: bucket.startDate), date >= sevenDayCutoff {
                    total += bucket.tokens
                }
            }
        }

        let metrics = [
            UsageMetric(id: "current", value: "—", label: language.metricCurrent),
            UsageMetric(id: "week", value: Self.formatTokens(sevenDayTokens), label: language.metricSevenDays),
            UsageMetric(id: "total", value: Self.formatTokens(live.lifetimeTokens), label: language.metricLifetime)
        ]

        let recentTasks: [RecentTask]
        if let localActivity = live.localActivity, localActivity.availability == .available {
            recentTasks = localActivity.tasks.enumerated().map { index, task in
                RecentTask(
                    id: "local-\(index + 1)",
                    title: language.localMetadataTaskTitle,
                    time: language.localCaptureDescription(for: task.modifiedAt, now: now),
                    tokenText: Self.formatTokens(task.totalTokens),
                    progress: 0
                )
            }
        } else {
            recentTasks = (0..<min(3, max(0, live.recentActivityCount))).map { index in
                RecentTask(
                    id: "derived-activity-\(index + 1)",
                    title: language.derivedActivityTitle(index: index),
                    time: "—",
                    tokenText: "—",
                    progress: 0
                )
            }
        }

        self.init(
            planLabel: Self.planLabel(for: live.rateLimits.planType),
            periods: periods,
            metrics: metrics,
            recentTasks: recentTasks,
            apiCostEstimate: (live.localActivity?.apiEquivalentCost ?? live.apiCostEstimate).map { estimate in
                APICostEstimateSnapshot(
                    sevenDayUSD: estimate.sevenDayUSD,
                    lifetimeUSD: estimate.lifetimeUSD,
                    coveragePercent: estimate.observedTokens > 0
                        ? Int((Double(estimate.pricedTokens) / Double(estimate.observedTokens) * 100).rounded())
                        : 0,
                    modelNames: estimate.modelNames
                )
            },
            availableResets: live.availableResetCount,
            updatedAt: now,
            providerSource: UsageSourceStatus(
                label: "Codex account",
                scope: "account/read, account/rateLimits/read, account/usage/read",
                capturedAt: live.providerCapturedAt,
                isAvailable: true
            ),
            localSource: live.localActivity.map {
                UsageSourceStatus(
                    label: $0.source,
                    scope: $0.scope,
                    capturedAt: $0.capturedAt,
                    isAvailable: $0.availability == .available,
                    coverage: $0.discoveredFileCount == 0
                        ? 0
                        : Int((Double($0.readableFileCount) / Double($0.discoveredFileCount) * 100).rounded())
                )
            }
        )
    }

    init(localActivity: CodexLocalActivitySnapshot, language: AppLanguage, now: Date = Date()) {
        let tasks = localActivity.tasks.enumerated().map { index, task in
            RecentTask(
                id: "local-\(index + 1)",
                title: language.localMetadataTaskTitle,
                time: language.localCaptureDescription(for: task.modifiedAt, now: now),
                tokenText: Self.formatTokens(task.totalTokens),
                progress: 0
            )
        }
        self.init(
            planLabel: "—",
            periods: [],
            metrics: [
                UsageMetric(id: "current", value: "—", label: language.metricCurrent),
                UsageMetric(id: "week", value: "—", label: language.metricSevenDays),
                UsageMetric(id: "total", value: "—", label: language.metricLifetime)
            ],
            recentTasks: tasks,
            apiCostEstimate: localActivity.apiEquivalentCost.map {
                APICostEstimateSnapshot(
                    sevenDayUSD: $0.sevenDayUSD,
                    lifetimeUSD: $0.lifetimeUSD,
                    coveragePercent: $0.observedTokens > 0
                        ? Int((Double($0.pricedTokens) / Double($0.observedTokens) * 100).rounded())
                        : 0,
                    modelNames: $0.modelNames
                )
            },
            threadOSAnalytics: localActivity.threadOSAnalytics,
            availableResets: nil,
            updatedAt: now,
            providerSource: UsageSourceStatus(
                label: "Codex account",
                scope: "account/read, account/rateLimits/read, account/usage/read",
                capturedAt: nil,
                isAvailable: false,
                freshness: .unavailable
            ),
            localSource: UsageSourceStatus(
                label: localActivity.source,
                scope: localActivity.scope,
                capturedAt: localActivity.capturedAt,
                isAvailable: localActivity.availability == .available,
                coverage: localActivity.discoveredFileCount == 0
                    ? 0
                    : Int((Double(localActivity.readableFileCount) / Double(localActivity.discoveredFileCount) * 100).rounded())
            )
        )
    }

    private static func planLabel(for planType: String?) -> String {
        switch planType?.lowercased() {
        case "pro": "PRO"
        case "plus": "PLUS"
        case "team": "TEAM"
        case "business": "BUSINESS"
        case "enterprise": "ENTERPRISE"
        case .some(let value): value.uppercased()
        case nil: "CODEX"
        }
    }

    private static func formatTokens(_ tokens: Int64?) -> String {
        guard let tokens else { return "—" }
        let value = Double(tokens)
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(tokens)
    }

}
