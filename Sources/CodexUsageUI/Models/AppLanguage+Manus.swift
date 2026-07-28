import Foundation

extension AppLanguage {
    var manusTitle: String { "Manus" }

    var manusOfficialAPIV2: String {
        self == .simplifiedChinese ? "官方 API v2" : "Official API v2"
    }

    var manusNotConnected: String {
        self == .simplifiedChinese ? "未连接" : "Not connected"
    }

    var manusConnect: String {
        self == .simplifiedChinese ? "连接 Manus" : "Connect Manus"
    }

    var manusDisclosure: String {
        self == .simplifiedChinese
            ? "UMA 会将 API 密钥仅保存在本机钥匙串，并只读取官方 API v2 的当前 Credits 余额。不会读取任务、历史或账号身份。"
            : "UMA stores the API key only in this Mac's Keychain and reads only the current Credits balance from the official API v2. Tasks, history, and account identity are never requested."
    }

    var manusAPIKey: String {
        self == .simplifiedChinese ? "Manus API 密钥" : "Manus API key"
    }

    var manusSaveAndVerify: String {
        self == .simplifiedChinese ? "保存并验证" : "Save and Verify"
    }

    var manusCancel: String {
        self == .simplifiedChinese ? "取消" : "Cancel"
    }

    var manusConnected: String {
        self == .simplifiedChinese ? "已连接" : "Connected"
    }

    var manusConfigured: String {
        self == .simplifiedChinese ? "已配置，等待验证" : "Configured, awaiting verification"
    }

    var manusVerifying: String {
        self == .simplifiedChinese ? "正在验证" : "Verifying"
    }

    var manusConnectionFailed: String {
        self == .simplifiedChinese ? "无法读取当前 Credits" : "Could not read current Credits"
    }

    var manusAutoRefresh: String {
        self == .simplifiedChinese ? "自动刷新" : "Auto Refresh"
    }

    var manusEveryMinute: String {
        self == .simplifiedChinese ? "最快每分钟" : "No faster than every minute"
    }

    var manusManualOnly: String {
        self == .simplifiedChinese ? "仅手动刷新" : "Manual refresh only"
    }

    var manusSyncNow: String {
        self == .simplifiedChinese ? "立即同步" : "Sync Now"
    }

    var manusDisconnect: String {
        self == .simplifiedChinese ? "断开 Manus" : "Disconnect Manus"
    }

    func manusUpdated(at date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return self == .simplifiedChinese ? "刚刚更新" : "Updated just now"
        }
        let minutes = seconds / 60
        return self == .simplifiedChinese
            ? "\(minutes) 分钟前更新"
            : "Updated \(minutes)m ago"
    }

    func manusFailure(_ failure: ManusSettingsSafeFailure) -> String {
        switch (self, failure) {
        case (.english, .missingCredential): "Enter an API key."
        case (.english, .credentialUnavailable): "Keychain is unavailable."
        case (.english, .authentication): "The API key was not accepted."
        case (.english, .rateLimited): "Manus is rate limiting requests."
        case (.english, .network): "The network request failed."
        case (.english, .server): "The Manus service is unavailable."
        case (.english, .invalidResponse): "Manus returned an unsupported response."
        case (.english, .cancelled): "The request was cancelled."
        case (.english, .unknown): "Manus could not be connected."
        case (.simplifiedChinese, .missingCredential): "请输入 API 密钥。"
        case (.simplifiedChinese, .credentialUnavailable): "钥匙串不可用。"
        case (.simplifiedChinese, .authentication): "API 密钥未被接受。"
        case (.simplifiedChinese, .rateLimited): "Manus 正在限制请求频率。"
        case (.simplifiedChinese, .network): "网络请求失败。"
        case (.simplifiedChinese, .server): "Manus 服务不可用。"
        case (.simplifiedChinese, .invalidResponse): "Manus 返回了不支持的响应。"
        case (.simplifiedChinese, .cancelled): "请求已取消。"
        case (.simplifiedChinese, .unknown): "无法连接 Manus。"
        }
    }

    func manusCreditDetail(_ kind: AgentCreditDetailKind) -> String {
        switch (self, kind) {
        case (.english, .free): "Free Credits"
        case (.english, .periodic): "Periodic Credits"
        case (.english, .addOn): "Add-on Credits"
        case (.english, .event): "Event Credits"
        case (.english, .refresh): "Refresh Credits"
        case (.english, .monthlyQuota): "Monthly quota"
        case (.english, .maximumRefresh): "Maximum refresh"
        case (.simplifiedChinese, .free): "免费 Credits"
        case (.simplifiedChinese, .periodic): "周期 Credits"
        case (.simplifiedChinese, .addOn): "加购 Credits"
        case (.simplifiedChinese, .event): "活动 Credits"
        case (.simplifiedChinese, .refresh): "刷新 Credits"
        case (.simplifiedChinese, .monthlyQuota): "每月配额"
        case (.simplifiedChinese, .maximumRefresh): "最大刷新额度"
        }
    }

    var manusAvailableCredits: String {
        self == .simplifiedChinese ? "可用 Credits" : "Available Credits"
    }

    var manusAccountScope: String {
        self == .simplifiedChinese ? "API 密钥账号范围" : "API-key account scope"
    }
}
