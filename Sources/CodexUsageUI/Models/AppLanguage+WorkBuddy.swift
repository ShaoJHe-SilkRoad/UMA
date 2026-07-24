import Foundation

extension AppLanguage {
    var workBuddySection: String {
        self == .simplifiedChinese ? "WorkBuddy Credits" : "WorkBuddy Credits"
    }

    var workBuddyExpanded: String {
        self == .simplifiedChinese ? "已展开" : "Expanded"
    }

    var workBuddyCollapsed: String {
        self == .simplifiedChinese ? "已折叠" : "Collapsed"
    }

    var workBuddyEnable: String {
        self == .simplifiedChinese ? "启用 WorkBuddy 可用额度" : "Enable WorkBuddy availability"
    }

    var workBuddySource: String {
        self == .simplifiedChinese ? "来源" : "Source"
    }

    var workBuddyManualConfirmation: String {
        self == .simplifiedChinese ? "手动确认" : "Manual confirmation"
    }

    var workBuddyManualSnapshot: String {
        self == .simplifiedChinese ? "手动快照" : "Manual snapshot"
    }

    var workBuddySharedWithCodeBuddy: String {
        self == .simplifiedChinese ? "与 CodeBuddy 共享" : "Shared with CodeBuddy"
    }

    var workBuddyScope: String {
        self == .simplifiedChinese ? "范围" : "Scope"
    }

    func workBuddyScopeName(_ scope: WorkBuddyManualScope) -> String {
        switch (self, scope) {
        case (.english, .personalShared): "Personal shared"
        case (.english, .enterpriseShared): "Enterprise shared"
        case (.english, .unknown): "Unknown"
        case (.simplifiedChinese, .personalShared): "个人共享"
        case (.simplifiedChinese, .enterpriseShared): "企业共享"
        case (.simplifiedChinese, .unknown): "未知"
        }
    }

    var workBuddyTier: String {
        self == .simplifiedChinese ? "套餐" : "Tier"
    }

    func workBuddyTierName(_ tier: WorkBuddyPlanTier) -> String {
        switch (self, tier) {
        case (.english, .experience): "Experience"
        case (.english, .standard): "Standard"
        case (.english, .advanced): "Advanced"
        case (.english, .flagship): "Flagship"
        case (.english, .enterprise): "Enterprise"
        case (.english, .unknown): "Unknown"
        case (.simplifiedChinese, .experience): "体验版"
        case (.simplifiedChinese, .standard): "标准版"
        case (.simplifiedChinese, .advanced): "进阶版"
        case (.simplifiedChinese, .flagship): "旗舰版"
        case (.simplifiedChinese, .enterprise): "企业版"
        case (.simplifiedChinese, .unknown): "未知"
        }
    }

    var workBuddyAvailableCredits: String {
        self == .simplifiedChinese ? "可用 Credits" : "Available Credits"
    }

    func workBuddyCompanionName(_ field: WorkBuddyCreditCompanionField) -> String {
        switch (self, field) {
        case (.english, .none): "Absolute only"
        case (.english, .used): "Used Credits"
        case (.english, .total): "Active total"
        case (.simplifiedChinese, .none): "仅可用额"
        case (.simplifiedChinese, .used): "已用 Credits"
        case (.simplifiedChinese, .total): "当前总额"
        }
    }

    var workBuddyNextExpiry: String {
        self == .simplifiedChinese ? "下次到期（可选）" : "Next expiry (optional)"
    }

    var workBuddyOpenOfficialUsagePage: String {
        self == .simplifiedChinese ? "打开官方用量页面" : "Open official usage page"
    }

    var workBuddyOfficialPageHint: String {
        self == .simplifiedChinese
            ? "仅在默认浏览器打开官方页面；UMA 不会读取页面内容。"
            : "Opens the official page in your default browser. UMA does not read its contents."
    }

    var workBuddyPreview: String {
        self == .simplifiedChinese ? "预览" : "Preview"
    }

    var workBuddySaveUpdate: String {
        self == .simplifiedChinese ? "保存更新" : "Save update"
    }

    var workBuddyConfirmUnchanged: String {
        self == .simplifiedChinese ? "确认未变化" : "Confirm unchanged"
    }

    var workBuddyClearData: String {
        self == .simplifiedChinese ? "清除 WorkBuddy 数据" : "Clear WorkBuddy data"
    }

    var workBuddyConfirmClear: String {
        self == .simplifiedChinese ? "再次点击以确认清除" : "Click again to confirm clear"
    }

    var workBuddyNotConfigured: String {
        self == .simplifiedChinese ? "尚未配置" : "Not configured"
    }

    var workBuddyLastConfirmed: String {
        self == .simplifiedChinese ? "上次确认" : "Last confirmed"
    }

    func workBuddyConfirmedAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var workBuddyInvalidSavedData: String {
        self == .simplifiedChinese ? "已保存数据无效，请清除或替换。" : "Saved data is invalid. Clear or replace it."
    }

    var workBuddyConversationCreditsExhausted: String {
        self == .simplifiedChinese ? "对话 Credits 已耗尽" : "Conversation Credits exhausted"
    }

    var workBuddyUseSuggestion: String {
        self == .simplifiedChinese ? "使用建议总额" : "Use suggested total"
    }

    func workBuddySuggestion(_ suggestion: WorkBuddyTierSuggestion) -> String {
        switch self {
        case .english:
            "Published \(WorkBuddyTierSuggestion.effectiveDate): base \(suggestion.baseCredits), temporary bonus \(suggestion.temporaryBonusCredits)."
        case .simplifiedChinese:
            "发布于 \(WorkBuddyTierSuggestion.effectiveDate)：基础 \(suggestion.baseCredits)，临时赠送 \(suggestion.temporaryBonusCredits)。"
        }
    }

    func workBuddyValidationMessage(_ error: WorkBuddyManualValidationError) -> String {
        switch (self, error) {
        case (.english, .requiredRemaining): "Enter available Credits."
        case (.english, .requiredUsed): "Enter used Credits."
        case (.english, .requiredTotal): "Enter the active total."
        case (.english, .invalidInteger): "Use whole nonnegative Credits only."
        case (.english, .integerOutOfRange): "The Credit value is outside the supported range."
        case (.english, .expiryMustBeFuture): "Expiry must be later than the confirmation time."
        case (.english, .noConfirmedValue): "Save a valid manual snapshot first."
        case (.english, .unsupportedSchema): "This saved record uses an unsupported future version."
        case (.english, .recordTooLarge), (.english, .persistenceUnavailable):
            "The local WorkBuddy record could not be saved."
        case (.english, .invalidManualRecord), (.english, .corruptPersistence):
            "The Credit values are inconsistent or the saved record is invalid."
        case (.simplifiedChinese, .requiredRemaining): "请输入可用 Credits。"
        case (.simplifiedChinese, .requiredUsed): "请输入已用 Credits。"
        case (.simplifiedChinese, .requiredTotal): "请输入当前总额。"
        case (.simplifiedChinese, .invalidInteger): "只能输入非负整数 Credits。"
        case (.simplifiedChinese, .integerOutOfRange): "Credit 数值超出支持范围。"
        case (.simplifiedChinese, .expiryMustBeFuture): "到期时间必须晚于确认时间。"
        case (.simplifiedChinese, .noConfirmedValue): "请先保存有效的手动快照。"
        case (.simplifiedChinese, .unsupportedSchema): "保存记录使用了不支持的未来版本。"
        case (.simplifiedChinese, .recordTooLarge), (.simplifiedChinese, .persistenceUnavailable):
            "无法保存本机 WorkBuddy 记录。"
        case (.simplifiedChinese, .invalidManualRecord), (.simplifiedChinese, .corruptPersistence):
            "Credit 数值不一致或保存记录无效。"
        }
    }

    func workBuddyStatusMessage(_ key: String) -> String {
        switch (self, key) {
        case (.english, "saved"): "Manual snapshot saved."
        case (.english, "unchanged"): "Values already match the saved snapshot."
        case (.english, "confirmed"): "Manual snapshot confirmed unchanged."
        case (.english, "cleared"): "WorkBuddy data cleared."
        case (.english, "officialPageOpened"): "Official usage page opened."
        case (.english, "officialPageFailed"): "The official usage page could not be opened."
        case (.simplifiedChinese, "saved"): "手动快照已保存。"
        case (.simplifiedChinese, "unchanged"): "当前数值与已保存快照相同。"
        case (.simplifiedChinese, "confirmed"): "已确认手动快照未变化。"
        case (.simplifiedChinese, "cleared"): "WorkBuddy 数据已清除。"
        case (.simplifiedChinese, "officialPageOpened"): "已打开官方用量页面。"
        case (.simplifiedChinese, "officialPageFailed"): "无法打开官方用量页面。"
        default: key
        }
    }
}
