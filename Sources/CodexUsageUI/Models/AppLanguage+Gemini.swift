import Foundation

extension AppLanguage {
    var geminiSourceLabel: String {
        self == .english
            ? "Gemini web Usage page · Safari Bridge"
            : "Gemini 网页用量页 · Safari Bridge"
    }

    /// What the numbers are, and what they are not.
    var geminiQuotaScope: String {
        self == .english
            ? "These are the Gemini App's own limits as gemini.google.com shows them. They are not Antigravity's quota, which Antigravity counts per model group."
            : "这是 gemini.google.com 显示的 Gemini App 自身额度，不是 Antigravity 的配额；Antigravity 按模型组分别计算。"
    }

    var geminiSyncNow: String {
        self == .english ? "Sync Now" : "立即同步"
    }

    var geminiOpenUsagePage: String {
        self == .english ? "Open Usage Page in Safari" : "在 Safari 打开用量页"
    }

    var geminiDisable: String {
        self == .english ? "Turn Off" : "关闭"
    }

    var geminiSourceTransparency: String {
        self == .english ? "Source and privacy" : "来源与隐私"
    }

    var geminiPrivacySummary: String {
        self == .english
            ? "Safari opens gemini.google.com/usage in a temporary tab and closes it after reading. Only the two usage percentages, their reset times and the plan word leave the page. Conversations, their titles and your account name are never read."
            : "Safari 会在临时标签页打开 gemini.google.com/usage，读完即关闭。只带出两项用量百分比、各自的重置时间和套餐名；不读取任何对话、对话标题或账号名。"
    }

    var geminiBridgeSetupHint: String {
        self == .english
            ? "Gemini uses the same Safari Bridge as Claude. Set it up in Claude's settings, then allow gemini.google.com for the AUV extension in Safari Settings › Websites."
            : "Gemini 与 Claude 共用同一个 Safari Bridge。请先在 Claude 设置里完成 Bridge 设置，再到 Safari 设置 › 网站，为 AUV 扩展允许 gemini.google.com。"
    }

    func geminiState(_ state: GeminiSettingsState) -> String {
        switch (self, state) {
        case (.english, .off): "Off. Turn on monitoring to read gemini.google.com/usage."
        case (_, .off): "已关闭。打开监控后才会读取 gemini.google.com/usage。"
        case (.english, .reading): "Reading the Gemini Usage page…"
        case (_, .reading): "正在读取 Gemini 用量页…"
        case let (.english, .fresh(date)): "Up to date · \(Self.geminiTime(date, english: true))"
        case let (_, .fresh(date)): "已是最新 · \(Self.geminiTime(date, english: false))"
        case let (.english, .cached(date)): "Last read \(Self.geminiTime(date, english: true)); the latest read failed"
        case let (_, .cached(date)): "上次读取于 \(Self.geminiTime(date, english: false))；最近一次读取失败"
        case let (.english, .stale(date)): "Out of date · last read \(Self.geminiTime(date, english: true))"
        case let (_, .stale(date)): "已过期 · 上次读取于 \(Self.geminiTime(date, english: false))"
        case (.english, .needsSiteAccess): "Safari has not allowed the AUV extension on gemini.google.com."
        case (_, .needsSiteAccess): "Safari 还没有允许 AUV 扩展访问 gemini.google.com。"
        case (.english, .needsSignIn): "Sign in to Gemini in Safari, then sync again."
        case (_, .needsSignIn): "请先在 Safari 登录 Gemini，再同步一次。"
        case (.english, .bridgeUnavailable): "The Safari Bridge is not answering. Check it in Claude's settings."
        case (_, .bridgeUnavailable): "Safari Bridge 没有响应，请在 Claude 设置里检查。"
        case (.english, .versionMismatch): "AUV and the Safari Bridge are different releases. Install them together."
        case (_, .versionMismatch): "AUV 与 Safari Bridge 版本不一致，请一起安装。"
        case (.english, .pageUnreadable): "The Usage page opened, but its usage could not be read."
        case (_, .pageUnreadable): "用量页打开了，但读不出用量。"
        case (.english, .failed): "The last read did not finish. AUV will try again."
        case (_, .failed): "上次读取没有完成，AUV 会再试。"
        }
    }

    private static func geminiTime(_ date: Date, english: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: english ? "en_US" : "zh_CN")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
