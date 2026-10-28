import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public static let storageKey = "app.language"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .simplifiedChinese: "中文"
        case .english: "English"
        }
    }

    public static func systemMatch(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let preferredLanguage = preferredLanguages.first?.lowercased() else {
            return .english
        }
        return preferredLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    @MainActor
    public static func resolveAndPersist(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        resolveAndPersist(
            preferences: ApplicationPreferences(userDefaults: defaults),
            preferredLanguages: preferredLanguages
        )
    }

    @MainActor
    public static func resolveAndPersist(
        preferences: ApplicationPreferences,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        if let rawValue = preferences.value(for: UMAApplicationPreferenceKeys.language),
           let savedLanguage = AppLanguage(rawValue: rawValue) {
            return savedLanguage
        }

        let matchedLanguage = systemMatch(preferredLanguages: preferredLanguages)
        preferences.set(
            matchedLanguage.rawValue,
            for: UMAApplicationPreferenceKeys.language
        )
        return matchedLanguage
    }

    public var locale: Locale {
        Locale(identifier: rawValue)
    }

    public var appTitle: String {
        "AUV"
    }

    /// The menu bar is not Codex-only. The provider whose quota is shown must
    /// name itself, or a fallback reading is announced under the wrong agent.
    public func remainingAccessibilityLabel(provider: String, percent: Int) -> String {
        switch self {
        case .simplifiedChinese: "\(provider) 剩余额度 \(percent)%"
        case .english: "\(provider) usage, \(percent)% remaining"
        }
    }

    public var refreshUsage: String {
        switch self {
        case .simplifiedChinese: "刷新用量"
        case .english: "Refresh Usage"
        }
    }

    public var quitApplication: String {
        switch self {
        case .simplifiedChinese: "退出 AUV"
        case .english: "Quit AUV"
        }
    }

    var demoStatus: String {
        switch self {
        case .simplifiedChinese: "演示数据 · 隐私保护"
        case .english: "Demo · Privacy Protected"
        }
    }

    var liveStatus: String {
        switch self {
        case .simplifiedChinese: "真实账户 · 实时刷新"
        case .english: "Live Account · Auto Refresh"
        }
    }

    var failureStatus: String {
        switch self {
        case .simplifiedChinese: "刷新失败 · 点击重试"
        case .english: "Refresh Failed · Click to Retry"
        }
    }

    func quotaTitle(durationMinutes: Int?, index: Int) -> String {
        switch (self, durationMinutes) {
        case (.simplifiedChinese, 300): "5 小时额度"
        case (.english, 300): "5-Hour Limit"
        case (.simplifiedChinese, 10_080): "7 天额度"
        case (.english, 10_080): "7-Day Limit"
        case (.simplifiedChinese, .some(let minutes)) where minutes % 1_440 == 0:
            "\(minutes / 1_440) 天额度"
        case (.english, .some(let minutes)) where minutes % 1_440 == 0:
            "\(minutes / 1_440)-Day Limit"
        case (.simplifiedChinese, .some(let minutes)) where minutes % 60 == 0:
            "\(minutes / 60) 小时额度"
        case (.english, .some(let minutes)) where minutes % 60 == 0:
            "\(minutes / 60)-Hour Limit"
        case (.simplifiedChinese, _): "额度（时段未知）"
        case (.english, _): "Usage Limit (Window Unknown)"
        }
    }

    func resetDescription(for date: Date?, now: Date) -> String {
        guard let date else {
            switch self {
            case .simplifiedChinese: return "重置时间未知"
            case .english: return "Reset time unavailable"
            }
        }

        let signedInterval = date.timeIntervalSince(now)
        if signedInterval < -60 {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = self == .simplifiedChinese ? "M月d日 HH:mm" : "MMM d, HH:mm"
            return self == .simplifiedChinese
                ? "重置时间已过（\(formatter.string(from: date))）；需要刷新"
                : "Reset time passed (\(formatter.string(from: date))); refresh needed"
        }
        if abs(signedInterval) <= 60 {
            return self == .simplifiedChinese ? "即将重置" : "Resets just now"
        }
        let interval = signedInterval
        let relative: String
        if interval < 3_600 {
            let minutes = max(1, Int(ceil(interval / 60)))
            relative = self == .simplifiedChinese
                ? "\(minutes) 分钟后"
                : "in \(minutes) min"
        } else if interval < 86_400 {
            let hours = max(1, Int(interval / 3_600))
            relative = self == .simplifiedChinese
                ? "\(hours) 小时后"
                : "in \(hours) hr"
        } else {
            let days = max(1, Int(interval / 86_400))
            relative = self == .simplifiedChinese
                ? "\(days) 天后"
                : "in \(days) days"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = self == .simplifiedChinese ? "M月d日 HH:mm" : "MMM d, HH:mm"
        switch self {
        case .simplifiedChinese:
            return "重置 \(relative) (\(formatter.string(from: date)))"
        case .english:
            return "Resets \(relative) (\(formatter.string(from: date)))"
        }
    }

    var metricCurrent: String {
        switch self {
        case .simplifiedChinese: "最新线程"
        case .english: "Latest Thread"
        }
    }

    var metricSevenDays: String {
        switch self {
        case .simplifiedChinese: "近 7 天"
        case .english: "Last 7 Days"
        }
    }

    var metricLifetime: String {
        switch self {
        case .simplifiedChinese: "累计"
        case .english: "Lifetime"
        }
    }

    var previewCurrentMetric: String {
        switch self {
        case .simplifiedChinese: "本次任务"
        case .english: "Current Task"
        }
    }

    var remaining: String {
        switch self {
        case .simplifiedChinese: "剩余"
        case .english: "Remaining"
        }
    }

    var recentTasks: String {
        switch self {
        case .simplifiedChinese: "最近任务"
        case .english: "Recent Tasks"
        }
    }

    func derivedActivityTitle(index: Int) -> String {
        switch self {
        case .simplifiedChinese: "最近本机活动 \(index + 1)"
        case .english: "Recent local activity \(index + 1)"
        }
    }

    var threadTotalTokens: String {
        switch self {
        case .simplifiedChinese: "线程累计 token"
        case .english: "Thread total tokens"
        }
    }

    var apiCostTitle: String {
        switch self {
        case .simplifiedChinese: "已消耗 token 价值（估算）"
        case .english: "Token Cost (Est.)"
        }
    }

    var standardAPIRates: String {
        switch self {
        case .simplifiedChinese: "API 标准价"
        case .english: "Standard API rates"
        }
    }

    var localMetadataTaskTitle: String {
        switch self {
        case .simplifiedChinese: "本机 Codex 会话"
        case .english: "Local Codex session"
        }
    }

    func localCaptureDescription(for date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return switch self {
        case .simplifiedChinese: minutes == 0 ? "刚刚捕获" : "\(minutes) 分钟前捕获"
        case .english: minutes == 0 ? "Captured just now" : "Captured \(minutes)m ago"
        }
    }

    var providerChannel: String {
        switch self {
        case .simplifiedChinese: "账户来源"
        case .english: "Account source"
        }
    }

    var localChannel: String {
        switch self {
        case .simplifiedChinese: "本机来源"
        case .english: "This Mac source"
        }
    }

    var sourceAvailable: String {
        switch self {
        case .simplifiedChinese: "可用"
        case .english: "available"
        }
    }

    var sourceUnavailable: String {
        switch self {
        case .simplifiedChinese: "不可用"
        case .english: "unavailable"
        }
    }

    var sourceNotCaptured: String {
        switch self {
        case .simplifiedChinese: "尚未捕获"
        case .english: "not captured"
        }
    }

    func sourceCaptured(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = self == .simplifiedChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        switch self {
        case .simplifiedChinese: return "捕获 \(formatter.string(from: date))"
        case .english: return "captured \(formatter.string(from: date))"
        }
    }

    func sourceCoverage(_ percent: Int) -> String {
        switch self {
        case .simplifiedChinese: return "覆盖 \(percent)%"
        case .english: return "coverage \(percent)%"
        }
    }

    func sourceFreshness(_ freshness: UsageSourceStatus.Freshness) -> String {
        switch (self, freshness) {
        case (.simplifiedChinese, .fresh): "新鲜"
        case (.simplifiedChinese, .stale): "较早"
        case (.simplifiedChinese, .unavailable): "未提供"
        case (.english, .fresh): "fresh"
        case (.english, .stale): "stale"
        case (.english, .unavailable): "not provided"
        }
    }

    func sourceScope(_ scope: String) -> String {
        switch self {
        case .simplifiedChinese: "范围：\(scope)"
        case .english: "Scope: \(scope)"
        }
    }

    var lifetimeCost: String {
        switch self {
        case .simplifiedChinese: "生涯总费用"
        case .english: "Lifetime Cost"
        }
    }

    var noPricedModel: String {
        switch self {
        case .simplifiedChinese: "暂无公开 API 定价模型"
        case .english: "No public API-priced model"
        }
    }

    func pricedCoverage(_ percent: Int) -> String {
        switch self {
        case .simplifiedChinese: "可计价 \(percent)%"
        case .english: "Priced \(percent)%"
        }
    }

    var costDisclaimer: String {
        switch self {
        case .simplifiedChinese: "按输入 / 缓存输入 / 输出 token 分别估算，不含税费与长上下文加价"
        case .english: "Token types priced separately; excludes tax and surcharges."
        }
    }

    var refreshFromAccountHint: String {
        switch self {
        case .simplifiedChinese: "从 Codex 账户刷新真实用量"
        case .english: "Refresh live usage from your Codex account"
        }
    }

    var showSettings: String {
        switch self {
        case .simplifiedChinese: "显示设置"
        case .english: "Show Settings"
        }
    }

    func availableResets(_ count: Int) -> String {
        switch self {
        case .simplifiedChinese: "可用重置 \(count) 次"
        case .english: "\(count) resets available"
        }
    }

    var resetAvailabilityUnavailable: String {
        switch self {
        case .simplifiedChinese: "重置额度未提供"
        case .english: "Reset availability unavailable"
        }
    }

    func updatedAt(_ time: String) -> String {
        switch self {
        case .simplifiedChinese: "更新于 \(time)"
        case .english: "Updated \(time)"
        }
    }

    var settingsTitle: String {
        switch self {
        case .simplifiedChinese: "显示设置"
        case .english: "Display Settings"
        }
    }

    var showAll: String {
        switch self {
        case .simplifiedChinese: "全部显示"
        case .english: "Show All"
        }
    }

    var closeSettings: String {
        switch self {
        case .simplifiedChinese: "关闭设置"
        case .english: "Close Settings"
        }
    }

    var cardsSection: String {
        switch self {
        case .simplifiedChinese: "显示卡片"
        case .english: "Cards"
        }
    }

    var usageSummaryCard: String {
        switch self {
        case .simplifiedChinese: "额度与 Token 概览"
        case .english: "Usage & Token Summary"
        }
    }

    var costCard: String {
        switch self {
        case .simplifiedChinese: "本地费用估算"
        case .english: "Local Cost Estimate"
        }
    }

    var generalSection: String {
        switch self {
        case .simplifiedChinese: "通用"
        case .english: "General"
        }
    }

    var desktopAssistantSection: String {
        switch self {
        case .simplifiedChinese: "桌面助手"
        case .english: "Desktop Assistant"
        }
    }

    var desktopAssistantEnabled: String {
        switch self {
        case .simplifiedChinese: "显示桌面助手"
        case .english: "Show Desktop Assistant"
        }
    }

    var desktopAssistantAlwaysOnTop: String {
        switch self {
        case .simplifiedChinese: "始终置顶"
        case .english: "Always on Top"
        }
    }

    var desktopAssistantDensity: String {
        switch self {
        case .simplifiedChinese: "布局"
        case .english: "Layout"
        }
    }

    func desktopAssistantDensityName(_ density: DesktopAssistantDensity) -> String {
        switch (self, density) {
        case (.simplifiedChinese, .automatic): "自动"
        case (.simplifiedChinese, .regular): "常规"
        case (.simplifiedChinese, .minimalist): "极简"
        case (.english, .automatic): "Auto"
        case (.english, .regular): "Regular"
        case (.english, .minimalist): "Minimal"
        }
    }

    var languageSetting: String {
        switch self {
        case .simplifiedChinese: "语言"
        case .english: "Language"
        }
    }

    var launchAtLogin: String {
        switch self {
        case .simplifiedChinese: "开机时启动"
        case .english: "Launch at Login"
        }
    }

    var approvalRequired: String {
        switch self {
        case .simplifiedChinese: "需要在系统设置中允许"
        case .english: "Allow in System Settings"
        }
    }

    var openSettings: String {
        switch self {
        case .simplifiedChinese: "前往设置"
        case .english: "Open Settings"
        }
    }

    func settingsFailure(_ description: String) -> String {
        switch self {
        case .simplifiedChinese: "设置失败：\(description)"
        case .english: "Update failed: \(description)"
        }
    }

    var enabledAccessibilityValue: String {
        switch self {
        case .simplifiedChinese: "已开启"
        case .english: "On"
        }
    }

    var disabledAccessibilityValue: String {
        switch self {
        case .simplifiedChinese: "已关闭"
        case .english: "Off"
        }
    }

    var previewTasks: [(title: String, time: String, token: String)] {
        switch self {
        case .simplifiedChinese:
            [
                ("任务信息已隐藏", "隐私保护", "已隐藏"),
                ("本地线程已隐藏", "隐私保护", "已隐藏"),
                ("仅展示界面效果", "演示数据", "已隐藏")
            ]
        case .english:
            [
                ("Task details hidden", "Privacy protected", "Hidden"),
                ("Local thread hidden", "Privacy protected", "Hidden"),
                ("Interface preview only", "Demo data", "Hidden")
            ]
        }
    }
}
