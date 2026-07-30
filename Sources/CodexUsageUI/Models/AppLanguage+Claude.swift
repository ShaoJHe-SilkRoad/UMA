import Foundation

extension AppLanguage {
    var claudeCodeName: String { "Claude Code" }

    var claudeOfficialLocalStatusLine: String {
        switch self {
        case .simplifiedChinese: "官方本地状态栏"
        case .english: "Official local status line"
        }
    }

    var claudeCheckCode: String {
        switch self {
        case .simplifiedChinese: "检查 Claude Code"
        case .english: "Check Claude Code"
        }
    }

    var claudeDetected: String {
        switch self {
        case .simplifiedChinese: "已检测到 Claude Code"
        case .english: "Claude Code detected"
        }
    }

    var claudeNoCredentialsRequired: String {
        switch self {
        case .simplifiedChinese: "无需凭据"
        case .english: "No credentials required"
        }
    }

    var claudeEnableIntegration: String {
        switch self {
        case .simplifiedChinese: "启用集成"
        case .english: "Enable Integration"
        }
    }

    var claudeWaitingForActivity: String {
        switch self {
        case .simplifiedChinese: "等待 Claude 活动"
        case .english: "Waiting for Claude activity"
        }
    }

    var claudeConnected: String {
        switch self {
        case .simplifiedChinese: "已连接"
        case .english: "Connected"
        }
    }

    var claudeRepairRelay: String {
        switch self {
        case .simplifiedChinese: "修复中继"
        case .english: "Repair Relay"
        }
    }

    var claudeDisableIntegration: String {
        switch self {
        case .simplifiedChinese: "停用集成"
        case .english: "Disable Integration"
        }
    }

    var claudeSourceTransparency: String {
        switch self {
        case .simplifiedChinese: "来源透明度"
        case .english: "Source Transparency"
        }
    }

    var claudeCredentialsTransparency: String {
        switch self {
        case .simplifiedChinese: "UMA 访问的凭据：无"
        case .english: "Credentials accessed by UMA: None"
        }
    }

    var claudeNetworkTransparency: String {
        switch self {
        case .simplifiedChinese: "UMA 发出的网络请求：无"
        case .english: "Network requests made by UMA: None"
        }
    }

    var claudeTranscriptTransparency: String {
        switch self {
        case .simplifiedChinese: "读取对话记录：否"
        case .english: "Transcript read: No"
        }
    }

    var claudeRawPayloadTransparency: String {
        switch self {
        case .simplifiedChinese: "存储原始提供方载荷：否"
        case .english: "Raw provider payload stored: No"
        }
    }

    var claudeAuthenticationTransparency: String {
        switch self {
        case .simplifiedChinese: "身份验证管理方：Claude Code"
        case .english: "Authentication managed by: Claude Code"
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
