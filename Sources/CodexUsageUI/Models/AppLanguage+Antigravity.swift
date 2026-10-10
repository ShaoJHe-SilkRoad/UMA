import Foundation

extension AppLanguage {
    var antigravitySection: String { "Google Antigravity" }

    var antigravitySourceLabel: String {
        self == .english
            ? "Official Antigravity CLI · Read-only Usage"
            : "Antigravity 官方 CLI · 只读用量"
    }

    var antigravityCheck: String {
        self == .english ? "Check Antigravity" : "检查 Antigravity"
    }

    var antigravityInstallOrOpen: String {
        self == .english ? "Install / Open Official Setup" : "安装 / 打开官方设置"
    }

    var antigravitySyncNow: String {
        self == .english ? "Sync Now" : "立即同步"
    }

    var antigravityAutoRefresh: String {
        self == .english ? "Auto Refresh" : "自动刷新"
    }

    var antigravityDisable: String {
        self == .english ? "Disable" : "停用"
    }

    var antigravitySourceTransparency: String {
        self == .english ? "Source and privacy" : "来源与隐私"
    }

    var antigravityPrivacySummary: String {
        self == .english
            ? "Reads normalized remaining quota from the official CLI. AUV does not receive credentials, browser data, conversations, prompts, responses, or raw provider output."
            : "通过官方 CLI 读取标准化剩余额度。AUV 不接收凭据、浏览器数据、对话、提示、回复或原始提供商输出。"
    }

    func antigravityState(
        _ state: AntigravitySettingsPresentationState
    ) -> String {
        switch (self, state) {
        case (.english, .disabled): "Disabled"
        case (.english, .checking): "Checking Antigravity"
        case (.english, .notInstalled): "Official CLI not found"
        case (.english, .openingOfficialSetup): "Opening official setup"
        case (.english, .loginRequired): "Sign in through Antigravity"
        case (.english, .connected): "Connected through Antigravity CLI"
        case (.english, .refreshing): "Refreshing"
        case (.english, .fresh): "Fresh"
        case (.english, .cached): "Cached"
        case (.english, .stale): "Stale"
        case (.english, .failed): "Antigravity usage unavailable"
        case (.simplifiedChinese, .disabled): "已停用"
        case (.simplifiedChinese, .checking): "正在检查 Antigravity"
        case (.simplifiedChinese, .notInstalled): "未找到官方 CLI"
        case (.simplifiedChinese, .openingOfficialSetup): "正在打开官方设置"
        case (.simplifiedChinese, .loginRequired): "请通过 Antigravity 登录"
        case (.simplifiedChinese, .connected): "已通过 Antigravity CLI 连接"
        case (.simplifiedChinese, .refreshing): "正在刷新"
        case (.simplifiedChinese, .fresh): "最新"
        case (.simplifiedChinese, .cached): "缓存"
        case (.simplifiedChinese, .stale): "已过期"
        case (.simplifiedChinese, .failed): "Antigravity 用量不可用"
        }
    }

    func antigravityAction(_ action: AntigravitySettingsAction) -> String {
        switch (self, action) {
        case (.english, .checking): "Checking"
        case (.english, .openingOfficialSetup): "Opening"
        case (.english, .openingProvider): "Opening Antigravity"
        case (.english, .refreshing): "Refreshing"
        case (.english, .changingAutoRefresh): "Updating"
        case (.english, .disabling): "Disabling"
        case (.simplifiedChinese, .checking): "正在检查"
        case (.simplifiedChinese, .openingOfficialSetup): "正在打开"
        case (.simplifiedChinese, .openingProvider): "正在打开 Antigravity"
        case (.simplifiedChinese, .refreshing): "正在刷新"
        case (.simplifiedChinese, .changingAutoRefresh): "正在更新"
        case (.simplifiedChinese, .disabling): "正在停用"
        }
    }

    func antigravityError(_ error: AntigravitySettingsSafeError) -> String {
        switch (self, error) {
        case (.english, .executableMissing): "Official Antigravity CLI not found"
        case (.english, .authenticationRequired): "Sign in through Antigravity"
        case (.english, .unsupportedVersion): "Antigravity CLI update required"
        case (.english, .unsupportedSchema): "Usage format is not supported"
        case (.english, .timedOut): "Antigravity did not respond in time"
        case (.english, .unavailable): "Antigravity usage is unavailable"
        case (.simplifiedChinese, .executableMissing): "未找到 Antigravity 官方 CLI"
        case (.simplifiedChinese, .authenticationRequired): "请通过 Antigravity 登录"
        case (.simplifiedChinese, .unsupportedVersion): "需要更新 Antigravity CLI"
        case (.simplifiedChinese, .unsupportedSchema): "不支持当前用量格式"
        case (.simplifiedChinese, .timedOut): "Antigravity 未及时响应"
        case (.simplifiedChinese, .unavailable): "Antigravity 用量不可用"
        }
    }
}
