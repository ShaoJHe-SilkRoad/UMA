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
        case .simplifiedChinese: "每次更新都需要在已验证的使用量页面点按一次 UMA 浏览器伴侣工具栏按钮。"
        case .english: "Each update requires one UMA Browser Companion toolbar click on the verified Usage page."
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
            "UMA 会在您的系统默认浏览器中打开 Claude 官方使用量页面。Google 或 Claude 凭据始终保留在浏览器中；UMA 不接收您的密码、通行密钥、验证码、OAuth 令牌、Cookie、聊天、项目、身份或账单信息。在已验证的使用量页面上，请点按一次 UMA 浏览器伴侣工具栏按钮，以授予仅限当前标签页的一次性临时访问。伴侣仅读取当前用量百分比与重置时间。由于网页结构可能发生变化，此来源标记为“实验性”。"
        case .english:
            "UMA opens Claude's official Usage page in your system default browser. Google or Claude credentials remain inside the browser; UMA does not receive your password, passkey, verification code, OAuth token, cookies, chats, projects, identity, or billing information. On the verified Usage page, choose the UMA Browser Companion toolbar button once to grant one-time temporary access to that tab. The companion reads only current usage percentages and reset times. This source is Experimental because webpage structure can change."
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
