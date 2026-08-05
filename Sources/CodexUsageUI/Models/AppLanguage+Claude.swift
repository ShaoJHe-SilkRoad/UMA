import Foundation

extension AppLanguage {
    var claudeCodeName: String { "Claude Code" }

    var claudeBrowserSourceLabel: String {
        switch self {
        case .simplifiedChinese: "Claude 官方使用量页面 · 浏览器同步 · 实验性"
        case .english: "Claude official Usage page · Browser Sync · Experimental"
        }
    }

    var claudeEnableIntegration: String {
        switch self {
        case .simplifiedChinese: "连接 Claude"
        case .english: "Connect Claude"
        }
    }

    var claudeNotConfigured: String {
        switch self {
        case .simplifiedChinese: "未连接"
        case .english: "Disconnected"
        }
    }

    var claudeConnected: String {
        switch self {
        case .simplifiedChinese: "浏览器同步已连接"
        case .english: "Browser Sync connected"
        }
    }

    var claudeCached: String {
        switch self {
        case .simplifiedChinese: "已缓存"
        case .english: "Cached"
        }
    }

    var claudeStale: String {
        switch self {
        case .simplifiedChinese: "较早数据"
        case .english: "Stale"
        }
    }

    var claudeFresh: String {
        switch self {
        case .simplifiedChinese: "新鲜"
        case .english: "Fresh"
        }
    }

    var claudeUpdatesPageDriven: String {
        switch self {
        case .simplifiedChinese: "自动刷新会在 Safari 可用时安全重试。"
        case .english: "Auto Refresh will retry safely when Safari is available."
        }
    }

    var claudeDisableIntegration: String {
        switch self {
        case .simplifiedChinese: "断开 Claude"
        case .english: "Disconnect Claude"
        }
    }

    var claudeSourceTransparency: String {
        switch self {
        case .simplifiedChinese: "来源透明度"
        case .english: "Source Transparency"
        }
    }

    var claudeConsentDisclosure: String {
        switch self {
        case .simplifiedChinese:
            "UMA 会在 Safari 中打开 Claude 官方使用量页面。登录始终保留在浏览器中；UMA 不接收密码、通行密钥、验证码、OAuth 令牌、Cookie、聊天、项目、身份或账单信息。按下“继续”会启用每五分钟一次的自动刷新，并请求仅限 https://claude.ai/new* 的持久网站访问；每次读取都必须先验证精确的 #settings/usage 路由。浏览器伴侣最多保留一个非活动专用标签页，并在各轮之间安全复用；断开 Claude 时会关闭该标签页。Safari 后台启动仍默认关闭。由于网页结构可能发生变化，此来源标记为“实验性”。"
        case .english:
            "UMA opens Claude's official Usage page in Safari. Login remains inside the browser; UMA does not receive passwords, passkeys, verification codes, OAuth tokens, cookies, chats, projects, identity, or billing information. Continue explicitly enables five-minute Auto Refresh and requests persistent website access only to https://claude.ai/new*; every read first verifies the exact #settings/usage route. The Browser Companion keeps at most one inactive dedicated tab and safely reuses it across cycles; Disconnect Claude closes it. Background Safari launch remains Off by default. This source is Experimental because webpage structure can change."
        }
    }

    func claudeBrowserActionStatus(_ action: ClaudeSettingsAction) -> String {
        switch (self, action) {
        case (.english, .checking): "Checking Browser Companion…"
        case (.english, .connecting): "Opening Claude Usage…"
        case (.english, .refreshing): "Refreshing…"
        case (.english, .openingUsage): "Opening Claude Usage…"
        case (.english, .repairing): "Repairing Browser Companion…"
        case (.english, .grantingAccess): "Opening Safari access settings…"
        case (.english, .openingAccessSettings): "Opening Safari access settings…"
        case (.english, .disconnecting): "Disconnecting…"
        case (.simplifiedChinese, .checking): "正在检查浏览器伴侣…"
        case (.simplifiedChinese, .connecting): "正在打开 Claude 使用量页面…"
        case (.simplifiedChinese, .refreshing): "正在刷新…"
        case (.simplifiedChinese, .openingUsage): "正在打开 Claude 使用量页面…"
        case (.simplifiedChinese, .repairing): "正在修复浏览器伴侣…"
        case (.simplifiedChinese, .grantingAccess): "正在打开 Safari 访问设置…"
        case (.simplifiedChinese, .openingAccessSettings): "正在打开 Safari 访问设置…"
        case (.simplifiedChinese, .disconnecting): "正在断开…"
        }
    }

    func claudeBrowserError(_ error: ClaudeSettingsSafeError) -> String {
        switch (self, error) {
        case (.english, .routeChanged):
            "Claude's Usage page changed. Browser Sync stopped safely."
        case (.english, .timedOut):
            "Claude Browser Sync timed out."
        case (.english, .ambiguousUsagePage):
            "Claude Browser Sync rejected an ambiguous Usage page."
        case (.simplifiedChinese, .routeChanged):
            "Claude 使用量页面已更改；浏览器同步已安全停止。"
        case (.simplifiedChinese, .timedOut):
            "Claude 浏览器同步已超时。"
        case (.simplifiedChinese, .ambiguousUsagePage):
            "Claude 浏览器同步已拒绝含糊的使用量页面。"
        }
    }

    func claudeUpdated(_ date: Date?) -> String {
        guard let date else {
            return switch self {
            case .simplifiedChinese: "尚未收到当前用量"
            case .english: "No current usage received"
            }
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        let value = formatter.localizedString(
            for: date,
            relativeTo: Date()
        )
        return switch self {
        case .simplifiedChinese: "更新于\(value)"
        case .english: "Updated \(value)"
        }
    }
}
