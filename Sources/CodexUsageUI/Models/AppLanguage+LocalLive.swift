import Foundation

public extension AppLanguage {
    var noLocalLiveAgentsTitle: String {
        switch self {
        case .english:
            "No locally accessible signed-in Agents detected."
        case .simplifiedChinese:
            "未检测到可在本机访问且已登录的 Agent。"
        }
    }

    var noLocalLiveAgentsGuidance: String {
        switch self {
        case .english:
            "Open a supported Agent, ensure it is signed in,\nthen choose Refresh."
        case .simplifiedChinese:
            "请打开受支持的 Agent 并确认已登录，\n然后选择“刷新”。"
        }
    }

    var loginForDataSync: String {
        switch self {
        case .english: "Login for Data Sync"
        case .simplifiedChinese: "登录以同步数据"
        }
    }

    var loginForDataSyncHint: String {
        switch self {
        case .english:
            "Opens the provider’s official desktop application. AUV never receives login credentials."
        case .simplifiedChinese:
            "打开提供商的官方桌面应用。AUV 不会接收登录凭据。"
        }
    }

    var checkAgain: String {
        switch self {
        case .english: "Check Again"
        case .simplifiedChinese: "再次检查"
        }
    }

    var localLiveProvidersSection: String {
        switch self {
        case .english: "Local Agent data"
        case .simplifiedChinese: "本机 Agent 数据"
        }
    }
}
