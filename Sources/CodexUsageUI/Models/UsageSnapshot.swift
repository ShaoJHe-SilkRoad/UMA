import Foundation

struct UsagePeriod: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    var remainingPercent: Int
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
                    resetText: language == .simplifiedChinese
                        ? "重置 3 小时后 (7月12日 18:41)"
                        : "Resets in 3 hr (Jul 12, 18:41)"
                ),
                UsagePeriod(
                    id: "seven-day",
                    title: language.quotaTitle(durationMinutes: 10_080, index: 1),
                    remainingPercent: 72,
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
