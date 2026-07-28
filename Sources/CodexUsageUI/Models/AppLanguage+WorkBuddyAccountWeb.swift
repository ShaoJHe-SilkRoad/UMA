import Foundation

extension AppLanguage {
    var workBuddyAccountWebTitle: String {
        self == .simplifiedChinese
            ? "实验性账号网页同步"
            : "Experimental Account Web Sync"
    }

    var workBuddyExperimentalLabel: String {
        self == .simplifiedChinese ? "实验性" : "Experimental"
    }

    var workBuddyAccountWebDisclosure: String {
        self == .simplifiedChinese
            ? "UMA 将在隔离的 WorkBuddy 网页会话中打开官方网站，并只读取“套餐与用量”页上的 Credits 余额字段。UMA 不会导出 Cookie、令牌、身份、完整 HTML 或浏览器存储。启用自动刷新时，UMA 每分钟进行一次限定的官方账号页面读取。"
            : "UMA opens the official site in an isolated WorkBuddy web session and reads only Credit balance fields from Plan and Usage. UMA does not export cookies, tokens, identity, full HTML, or browser storage. When Auto Refresh is enabled, UMA performs one bounded official account-page read every minute."
    }

    var workBuddyAccountWebConsent: String {
        self == .simplifiedChinese
            ? "我同意实验性 WorkBuddy 账号网页同步"
            : "I consent to Experimental WorkBuddy Account Web Sync"
    }

    var workBuddyAccountWebSessionChoice: String {
        self == .simplifiedChinese ? "网页会话" : "Web session"
    }

    func workBuddyAccountWebSessionMode(
        _ mode: WorkBuddyAccountWebSessionMode
    ) -> String {
        switch (self, mode) {
        case (.english, .persistent): "Keep signed in"
        case (.english, .nonpersistent): "Private session"
        case (.simplifiedChinese, .persistent): "保持登录"
        case (.simplifiedChinese, .nonpersistent): "临时会话"
        }
    }

    var workBuddyAccountWebConnect: String {
        self == .simplifiedChinese ? "连接 WorkBuddy 账号" : "Connect WorkBuddy Account"
    }

    var workBuddyAccountWebSyncNow: String {
        self == .simplifiedChinese ? "立即同步" : "Sync Now"
    }

    var workBuddyAccountAutoRefresh: String {
        self == .simplifiedChinese ? "自动刷新" : "Auto Refresh"
    }

    var workBuddyAccountEveryMinute: String {
        self == .simplifiedChinese ? "每分钟" : "Every minute"
    }

    var workBuddyAccountManualOnly: String {
        self == .simplifiedChinese ? "仅手动" : "Manual only"
    }

    var workBuddyAccountUpdatedJustNow: String {
        self == .simplifiedChinese ? "刚刚更新" : "Updated just now"
    }

    func workBuddyAccountUpdated(at date: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        guard elapsed >= 60 else { return workBuddyAccountUpdatedJustNow }
        let minutes = elapsed / 60
        if minutes < 60 {
            return self == .simplifiedChinese
                ? "\(minutes) 分钟前更新"
                : "Updated \(minutes)m ago"
        }
        let hours = minutes / 60
        return self == .simplifiedChinese
            ? "\(hours) 小时前更新"
            : "Updated \(hours)h ago"
    }

    var workBuddyAccountSignInRequired: String {
        self == .simplifiedChinese ? "需要重新登录" : "Sign in required"
    }

    var workBuddyAccountCouldNotReadCredits: String {
        self == .simplifiedChinese
            ? "无法读取当前积分"
            : "Could not read current Credits"
    }

    var workBuddyAccountSignInAgain: String {
        self == .simplifiedChinese ? "重新登录" : "Sign In Again"
    }

    var workBuddyAccountSyncAgain: String {
        self == .simplifiedChinese ? "再次同步" : "Sync Again"
    }

    var workBuddyAccountPrivacyAndSourceDetails: String {
        self == .simplifiedChinese
            ? "隐私与来源详情"
            : "Privacy and Source Details"
    }

    var workBuddyAccountMoreActions: String {
        self == .simplifiedChinese ? "更多操作" : "More actions"
    }

    func workBuddyAccountNextRefresh(_ interval: String) -> String {
        self == .simplifiedChinese
            ? "下次刷新：\(interval)"
            : "Next refresh in \(interval)"
    }

    func workBuddyAccountRefreshInterval(seconds: Int) -> String {
        self == .simplifiedChinese
            ? "\(seconds) 秒"
            : "\(seconds)s"
    }

    var workBuddyAccountWebSubtitle: String {
        "\(workBuddyAccountWebSource) · \(workBuddyExperimentalLabel)"
    }

    var workBuddyAccountWebOpenUsage: String {
        self == .simplifiedChinese ? "打开账号用量" : "Open Account Usage"
    }

    var workBuddyAccountWebDisconnect: String {
        self == .simplifiedChinese
            ? "断开 WorkBuddy 账号"
            : "Disconnect WorkBuddy Account"
    }

    var workBuddyAccountWebSource: String {
        self == .simplifiedChinese ? "账号网页同步" : "Account web sync"
    }

    var workBuddyAccountWebSafeDiagnostic: String {
        self == .simplifiedChinese ? "安全结构代码" : "Safe structure code"
    }

    var workBuddySubscriptionRemaining: String {
        self == .simplifiedChinese
            ? "订阅套餐剩余"
            : "Subscription plan remaining"
    }

    var workBuddyAddOnRemaining: String {
        self == .simplifiedChinese
            ? "加量包剩余"
            : "Add-on packages remaining"
    }

    var workBuddyBenefitGiftRemaining: String {
        self == .simplifiedChinese
            ? "权益/赠送包剩余"
            : "Benefit/gift packages remaining"
    }

    var workBuddyTotalAvailable: String {
        self == .simplifiedChinese
            ? "可用 Credits 总计"
            : "Total available Credits"
    }

    var workBuddySupportStatus: String {
        self == .simplifiedChinese ? "支持状态" : "Support status"
    }

    var workBuddyLegacyManualRecord: String {
        self == .simplifiedChinese
            ? "旧版手动记录（单独保留，不用于 WorkBuddy 显示或网页同步回退）"
            : "Legacy manual record (kept separately; never used for WorkBuddy visibility or account-web fallback)"
    }

    func workBuddyAccountWebState(
        _ state: WorkBuddyAccountWebFlowState
    ) -> String {
        switch (self, state) {
        case (.english, .idle): "Not connected"
        case (.english, .consentRequired): "Consent required"
        case (.english, .opening): "Opening isolated session"
        case (.english, .signInRequired): workBuddyAccountSignInRequired
        case (.english, .readyToSync): "Plan and Usage is ready"
        case (.english, .synchronizing): "Syncing"
        case (.english, .connected): "Connected"
        case (.english, .failed): workBuddyAccountCouldNotReadCredits
        case (.simplifiedChinese, .idle): "未连接"
        case (.simplifiedChinese, .consentRequired): "需要同意"
        case (.simplifiedChinese, .opening): "正在打开隔离会话"
        case (.simplifiedChinese, .signInRequired): workBuddyAccountSignInRequired
        case (.simplifiedChinese, .readyToSync): "“套餐与用量”页面已就绪"
        case (.simplifiedChinese, .synchronizing): "正在同步"
        case (.simplifiedChinese, .connected): "已连接"
        case (.simplifiedChinese, .failed):
            workBuddyAccountCouldNotReadCredits
        }
    }

    private func workBuddyAccountWebFailure(
        _ failure: WorkBuddyAccountWebFailure
    ) -> String {
        switch (self, failure) {
        case (.english, .consentRequired): "consent required"
        case (.english, .invalidNavigation): "navigation not allowed"
        case (.english, .authenticationRequired): "sign-in required"
        case (.english, .unexpectedPage): "unexpected page"
        case (.english, .pageNotStabilized): "usage page did not stabilize"
        case (.english, .incompletePoolSections):
            "required Credit sections are incomplete"
        case (.english, .malformedCredits): "invalid Credit fields"
        case (.english, .ambiguousCredits): "ambiguous Credit fields"
        case (.english, .invalidCreditPool): "invalid Credit pool"
        case (.english, .duplicateCreditPool): "ambiguous duplicate Credit pool"
        case (.english, .ambiguousAccountBalance):
            "ambiguous account balance"
        case (.english, .accountBalanceReconciliationFailed):
            "account balance reconciliation failed"
        case (.english, .timedOut): "request timed out"
        case (.english, .webContentUnavailable): "page unavailable"
        case (.english, .websiteDataClearFailed):
            "owned website data could not be cleared"
        case (.simplifiedChinese, .consentRequired): "需要同意"
        case (.simplifiedChinese, .invalidNavigation): "不允许的网页导航"
        case (.simplifiedChinese, .authenticationRequired): "需要登录"
        case (.simplifiedChinese, .unexpectedPage): "页面不符合预期"
        case (.simplifiedChinese, .pageNotStabilized): "用量页面未稳定"
        case (.simplifiedChinese, .incompletePoolSections):
            "Credits 资源区不完整"
        case (.simplifiedChinese, .malformedCredits): "Credits 字段无效"
        case (.simplifiedChinese, .ambiguousCredits): "Credits 字段不明确"
        case (.simplifiedChinese, .invalidCreditPool): "Credits 资源池无效"
        case (.simplifiedChinese, .duplicateCreditPool):
            "Credits 资源池重复且不明确"
        case (.simplifiedChinese, .ambiguousAccountBalance):
            "账号 Credits 余额不明确"
        case (.simplifiedChinese, .accountBalanceReconciliationFailed):
            "账号余额核对失败"
        case (.simplifiedChinese, .timedOut): "请求超时"
        case (.simplifiedChinese, .webContentUnavailable): "页面不可用"
        case (.simplifiedChinese, .websiteDataClearFailed):
            "无法清除 UMA 自有网页数据"
        }
    }
}
