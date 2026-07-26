import Foundation

extension AppLanguage {
    var workBuddyLoginForDataSync: String {
        self == .simplifiedChinese ? "登录以进行数据同步" : "Login for Data Sync"
    }

    var workBuddyLoginPrivacySummary: String {
        self == .simplifiedChinese
            ? "UMA 只会验证 WorkBuddy 应用身份、打开官方应用并记录此辅助流程的安全状态。UMA 不会读取账号、凭据、二维码、会话、浏览器内容或 Credits。"
            : "UMA only validates the WorkBuddy app identity, opens the official app, and records safe flow state. UMA does not read accounts, credentials, QR codes, sessions, browser content, or Credits."
    }

    var workBuddyLoginPrivacyConfirmation: String {
        self == .simplifiedChinese
            ? "我同意 UMA 打开官方 WorkBuddy 应用"
            : "I consent to UMA opening the official WorkBuddy app"
    }

    var workBuddyOfficialInstallWarning: String {
        self == .simplifiedChinese
            ? "macOS 无法验证此 WorkBuddy 安装。仅当您从 WorkBuddy 官方来源安装时才继续。"
            : "macOS could not verify this WorkBuddy installation. Continue only if you installed it from the official WorkBuddy source."
    }

    var workBuddyOfficialInstallConfirmation: String {
        self == .simplifiedChinese
            ? "我确认此应用来自 WorkBuddy 官方来源"
            : "I installed this app from the official WorkBuddy source"
    }

    var workBuddyAccountType: String {
        self == .simplifiedChinese ? "登录说明类型" : "Instruction type"
    }

    func workBuddyAccountMode(_ mode: WorkBuddyLoginAccountMode) -> String {
        switch (self, mode) {
        case (.english, .personal): "Personal"
        case (.english, .enterprise): "Enterprise"
        case (.simplifiedChinese, .personal): "个人版"
        case (.simplifiedChinese, .enterprise): "企业版"
        }
    }

    var workBuddyAccountModeHint: String {
        self == .simplifiedChinese
            ? "此选择仅更改说明，不会检测或更改您的账号类型。"
            : "This choice changes instructions only. It does not detect or change your account type."
    }

    var workBuddyOpenApplication: String {
        self == .simplifiedChinese ? "打开 WorkBuddy" : "Open WorkBuddy"
    }

    var workBuddyCancelLogin: String {
        self == .simplifiedChinese ? "取消登录" : "Cancel Login"
    }

    var workBuddyOpenOfficialLoginInstructions: String {
        self == .simplifiedChinese ? "打开官方登录说明" : "Open Official Login Instructions"
    }

    var workBuddyLoginStepsTitle: String {
        self == .simplifiedChinese ? "在官方 WorkBuddy 中完成" : "Complete in official WorkBuddy"
    }

    func workBuddyLoginSteps(_ mode: WorkBuddyLoginAccountMode) -> [String] {
        switch (self, mode) {
        case (.english, .personal):
            [
                "In WorkBuddy, choose the provider-owned sign-in control.",
                "Complete the provider-owned browser or WeChat sign-in yourself.",
                "Return to UMA and choose Check Again."
            ]
        case (.english, .enterprise):
            [
                "In WorkBuddy, choose your enterprise sign-in entry.",
                "Complete your organization’s provider-owned browser or WeChat sign-in yourself.",
                "Return to UMA and choose Check Again."
            ]
        case (.simplifiedChinese, .personal):
            [
                "在 WorkBuddy 中选择官方登录入口。",
                "请自行完成官方浏览器或微信登录。",
                "返回 UMA，然后选择“再次检查”。"
            ]
        case (.simplifiedChinese, .enterprise):
            [
                "在 WorkBuddy 中选择企业登录入口。",
                "请自行完成组织提供的官方浏览器或微信登录。",
                "返回 UMA，然后选择“再次检查”。"
            ]
        }
    }

    var workBuddyInstalled: String {
        self == .simplifiedChinese ? "WorkBuddy 已安装" : "WorkBuddy installed"
    }

    var workBuddyNotInstalled: String {
        self == .simplifiedChinese
            ? "未找到官方 WorkBuddy 应用。"
            : "The official WorkBuddy app was not found."
    }

    var workBuddyInvalidIdentity: String {
        self == .simplifiedChinese
            ? "找到的应用不是预期的 WorkBuddy 应用。"
            : "The found application does not have the expected WorkBuddy identity."
    }

    var workBuddyFlowLaunched: String {
        self == .simplifiedChinese
            ? "已打开官方登录流程；UMA 尚未验证登录。"
            : "The official login flow was opened. UMA has not verified authentication."
    }

    var workBuddyAwaitingCompletion: String {
        self == .simplifiedChinese
            ? "请在 WorkBuddy 中完成登录，然后返回此处。"
            : "Complete sign-in in WorkBuddy, then return here."
    }

    var workBuddySafeCompletionResult: String {
        self == .simplifiedChinese
            ? "登录流程已完成。UMA 无法安全验证身份验证或同步 Credits，因为没有受支持的本地 WorkBuddy Credits 来源。"
            : "Login flow completed. UMA cannot safely verify authentication or sync Credits because no supported local WorkBuddy Credits source is available."
    }

    func workBuddyLoginFailure(_ failure: WorkBuddyLoginFailure) -> String {
        switch (self, failure) {
        case (.english, .applicationNotInstalled): workBuddyNotInstalled
        case (.english, .invalidBundleIdentity): workBuddyInvalidIdentity
        case (.english, .privacyConfirmationRequired):
            "Confirm the privacy notice before opening WorkBuddy."
        case (.english, .officialInstallConfirmationRequired):
            "Confirm the official-vendor installation warning before continuing."
        case (.english, .launchDenied): "Opening WorkBuddy was cancelled."
        case (.english, .launchFailed): "WorkBuddy could not be opened."
        case (.english, .timedOut):
            "The login-assistance window timed out. Start again when ready."
        case (.simplifiedChinese, .applicationNotInstalled): workBuddyNotInstalled
        case (.simplifiedChinese, .invalidBundleIdentity): workBuddyInvalidIdentity
        case (.simplifiedChinese, .privacyConfirmationRequired):
            "请先确认隐私说明，再打开 WorkBuddy。"
        case (.simplifiedChinese, .officialInstallConfirmationRequired):
            "请先确认官方来源安装警告。"
        case (.simplifiedChinese, .launchDenied): "已取消打开 WorkBuddy。"
        case (.simplifiedChinese, .launchFailed): "无法打开 WorkBuddy。"
        case (.simplifiedChinese, .timedOut):
            "登录辅助已超时。准备好后请重新开始。"
        }
    }
}
