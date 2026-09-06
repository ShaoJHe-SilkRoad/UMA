import Foundation

struct UsagePeriod: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    var remainingPercent: Int
    /// Optional for compatibility with snapshots encoded before G2 recorded
    /// the provider window kind in this presentation model.
    var isFiveHour: Bool? = nil
    /// A special provider-granted five-hour credit window. The bar remains
    /// visible, but the numeric status must not imply an ordinary quota.
    var isUnlimited = false
    var isEstimated: Bool? = nil
    let resetText: String
}

struct UsageMetric: Identifiable, Codable, Sendable {
    let id: String
    let value: String
    let label: String
}

struct RecentTask: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let time: String
    let tokenText: String
    let progress: Double
}

struct APICostEstimateSnapshot: Codable, Sendable {
    let sevenDayUSD: Double
    let lifetimeUSD: Double
    let coveragePercent: Int
    let modelNames: [String]
}

/// Public presentation metadata for the two independent channels.  It contains
/// no account identity, session names, paths, prompt text, or raw payload.
struct UsageSourceStatus: Codable, Sendable {
    enum Freshness: String, Codable, Sendable {
        case fresh
        case stale
        case unavailable
    }

    let label: String
    let scope: String
    let capturedAt: Date?
    let isAvailable: Bool
    let coverage: Int?
    let freshness: Freshness

    init(
        label: String,
        scope: String,
        capturedAt: Date?,
        isAvailable: Bool,
        coverage: Int? = nil,
        freshness: Freshness? = nil
    ) {
        self.label = label
        self.scope = scope
        self.capturedAt = capturedAt
        self.isAvailable = isAvailable
        self.coverage = coverage
        self.freshness = freshness ?? (isAvailable ? .fresh : .unavailable)
    }
}

struct UsageSnapshot: Codable, Sendable {
    var planLabel: String
    var periods: [UsagePeriod]
    var metrics: [UsageMetric]
    var recentTasks: [RecentTask]
    var apiCostEstimate: APICostEstimateSnapshot?
    var threadOSAnalytics: ThreadOSUsageAnalytics? = nil
    /// `nil` means the provider did not supply reset-credit information. It
    /// must remain unavailable rather than being rendered as a fabricated 0.
    var availableResets: Int?
    var updatedAt: Date
    var providerSource: UsageSourceStatus?
    var localSource: UsageSourceStatus?

    /// The only production first-load value.  Preview data remains available
    /// exclusively to the explicit preview renderer path.
    static func empty(language: AppLanguage, now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            planLabel: "—",
            periods: [],
            metrics: [
                UsageMetric(id: "current", value: "—", label: language.metricCurrent),
                UsageMetric(id: "week", value: "—", label: language.metricSevenDays),
                UsageMetric(id: "total", value: "—", label: language.metricLifetime)
            ],
            recentTasks: [],
            apiCostEstimate: nil,
            availableResets: nil,
            updatedAt: now,
            providerSource: nil,
            localSource: nil
        )
    }

    static func preview(language: AppLanguage) -> UsageSnapshot {
        let taskCopy = language.previewTasks
        return UsageSnapshot(
            planLabel: "PRO",
            periods: [
                UsagePeriod(
                    id: "five-hour",
                    title: language.quotaTitle(durationMinutes: 300, index: 0),
                    remainingPercent: 78,
                    isFiveHour: true,
                    resetText: language == .simplifiedChinese
                        ? "重置 3 小时后 (7月12日 18:41)"
                        : "Resets in 3 hr (Jul 12, 18:41)"
                ),
                UsagePeriod(
                    id: "seven-day",
                    title: language.quotaTitle(durationMinutes: 10_080, index: 1),
                    remainingPercent: 72,
                    isFiveHour: false,
                    resetText: language == .simplifiedChinese
                        ? "重置 5 天后 (7月18日 14:45)"
                        : "Resets in 5 days (Jul 18, 14:45)"
                )
            ],
            metrics: [
                UsageMetric(id: "current", value: "24.80M", label: language.previewCurrentMetric),
                UsageMetric(id: "week", value: "1.26B", label: language.metricSevenDays),
                UsageMetric(id: "total", value: "3.84B", label: language.metricLifetime)
            ],
            recentTasks: [
                RecentTask(
                    id: "hidden-1",
                    title: taskCopy[0].title,
                    time: taskCopy[0].time,
                    tokenText: taskCopy[0].token,
                    progress: 0.88
                ),
                RecentTask(
                    id: "hidden-2",
                    title: taskCopy[1].title,
                    time: taskCopy[1].time,
                    tokenText: taskCopy[1].token,
                    progress: 0.62
                ),
                RecentTask(
                    id: "hidden-3",
                    title: taskCopy[2].title,
                    time: taskCopy[2].time,
                    tokenText: taskCopy[2].token,
                    progress: 0.35
                )
            ],
            apiCostEstimate: APICostEstimateSnapshot(
                sevenDayUSD: 186.42,
                lifetimeUSD: 1_980,
                coveragePercent: 94,
                modelNames: ["GPT-5.5", "GPT-5.6 Sol"]
            ),
            availableResets: 2,
            updatedAt: Date(),
            providerSource: UsageSourceStatus(label: "Preview fixture", scope: "preview only", capturedAt: Date(), isAvailable: true),
            localSource: UsageSourceStatus(label: "Preview fixture", scope: "preview only", capturedAt: Date(), isAvailable: true, coverage: 100)
        )
    }
}

extension UsageSnapshot {
    /// Presentation projection only. The connector core supplies normalized
    /// aggregates; this view model adds localized labels and no transport data.
    init(agentSnapshot: AgentUsageSnapshot, language: AppLanguage, now: Date = Date()) {
        let account = agentSnapshot.channels.first(where: { $0.id == .account })
        let local = agentSnapshot.channels.first(where: { $0.id == .localActivity })
        let windows = (account?.rateLimitWindows ?? []).sorted { $0.kind.rawValue < $1.kind.rawValue }
        let periods = windows.enumerated().compactMap { index, window -> UsagePeriod? in
            let remainingPercent: Int
            if window.isUnlimited {
                remainingPercent = 100
            } else if let normalized = window.normalizedRemainingPercent {
                remainingPercent = Int(normalized.rounded())
            } else {
                return nil
            }
            return UsagePeriod(
                id: window.id,
                title: language.quotaTitle(durationMinutes: window.kind == .fiveHour ? 300 : (window.kind == .sevenDay ? 10_080 : nil), index: index),
                remainingPercent: remainingPercent,
                isFiveHour: window.kind == .fiveHour,
                isUnlimited: window.isUnlimited,
                isEstimated: window.isEstimated == true,
                resetText: language.resetDescription(for: window.resetsAt, now: now)
            )
        }
        let localMetrics = local?.localActivityMetrics
        let derivedTasks = (0..<min(3, localMetrics?.recentTaskCount ?? 0)).map { index in
            RecentTask(
                id: "normalized-local-\(index + 1)",
                title: language.localMetadataTaskTitle,
                time: localMetrics?.recentTaskCapturedAt.indices.contains(index) == true
                    ? language.localCaptureDescription(for: localMetrics!.recentTaskCapturedAt[index], now: now)
                    : "—",
                tokenText: localMetrics?.recentTaskTokens.indices.contains(index) == true
                    ? Self.formatNormalizedTokens(localMetrics!.recentTaskTokens[index])
                    : "—",
                progress: 0
            )
        }
        self.init(
            planLabel: Self.normalizedPlanLabel(account?.accountMetrics?.planLabel),
            periods: periods,
            metrics: [
                UsageMetric(id: "current", value: "—", label: language.metricCurrent),
                UsageMetric(id: "week", value: Self.formatNormalizedTokens(account?.accountMetrics?.sevenDayTokens), label: language.metricSevenDays),
                UsageMetric(id: "total", value: Self.formatNormalizedTokens(account?.accountMetrics?.lifetimeTokens), label: language.metricLifetime)
            ],
            recentTasks: derivedTasks,
            apiCostEstimate: localMetrics.flatMap { local in
                guard let sevenDay = local.estimatedSevenDayUSD, let lifetime = local.estimatedLifetimeUSD else { return nil }
                return APICostEstimateSnapshot(sevenDayUSD: sevenDay, lifetimeUSD: lifetime, coveragePercent: local.coveragePercent ?? 0, modelNames: [])
            },
            threadOSAnalytics: localMetrics?.threadOSAnalytics,
            availableResets: account?.accountMetrics?.availableResets,
            updatedAt: agentSnapshot.capturedAt,
            providerSource: account.map {
                UsageSourceStatus(
                    label: "\(agentSnapshot.providerName) account",
                    scope: Self.presentationScope(for: agentSnapshot, channel: $0),
                    capturedAt: $0.capturedAt,
                    isAvailable: $0.freshness != .unavailable,
                    freshness: Self.presentationFreshness($0.freshness)
                )
            },
            localSource: local.map {
                UsageSourceStatus(
                    label: "\(agentSnapshot.providerName) local activity",
                    scope: $0.scopes.map(\.rawValue).sorted().joined(separator: ", "),
                    capturedAt: $0.capturedAt,
                    isAvailable: $0.freshness != .unavailable,
                    coverage: $0.localActivityMetrics?.coveragePercent,
                    freshness: Self.presentationFreshness($0.freshness)
                )
            }
        )
    }

    private static func normalizedPlanLabel(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value.uppercased()
    }

    private static func formatNormalizedTokens(_ value: Int64?) -> String {
        guard let value else { return "—" }
        if value >= 1_000_000_000 { return String(format: "%.2fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private static func presentationFreshness(_ freshness: AgentConnectorFreshness) -> UsageSourceStatus.Freshness {
        switch freshness {
        case .fresh: .fresh
        case .cached, .stale: .stale
        case .unavailable: .unavailable
        }
    }

    private static func presentationScope(for snapshot: AgentUsageSnapshot, channel: AgentUsageChannel) -> String {
        if snapshot.providerName == "Codex", channel.id == .account {
            return "account/read, account/rateLimits/read, account/usage/read"
        }
        return channel.scopes.map(\.rawValue).sorted().joined(separator: ", ")
    }
}
