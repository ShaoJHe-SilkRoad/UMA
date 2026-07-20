import Foundation

extension AppLanguage {
    private func c(_ english: String, _ chinese: String) -> String {
        self == .simplifiedChinese ? chinese : english
    }

    var connectionConsentTitle: String { c("Connect to Codex on this Mac", "连接到这台 Mac 上的 Codex") }
    var connectionReconnectTitle: String { c("Reconnect to Codex", "重新连接 Codex") }
    var connectionConsentBody: String {
        c(
            "UMA connects to the local Codex service to request account status, usage limits, and a token-usage summary. Local session metadata is collected separately. It does not read or store your password or authentication tokens. Codex manages sign-in.",
            "UMA 会连接本机 Codex 服务，请求账户状态、用量限额和 Token 用量摘要。本机会话元数据会单独收集。它不会读取或存储你的密码或身份验证令牌。登录由 Codex 管理。"
        )
    }
    var connectionConsentAnnouncement: String { c("Permission is required before connecting.", "连接前需要你的许可。") }
    var connectionReconnectAnnouncement: String { c("The monitor is disconnected. You can reconnect.", "监视器已断开，你可以重新连接。") }
    var connectionNotNow: String { c("Not Now", "暂不") }
    var connectionConnect: String { c("Connect", "连接") }
    var connectionLocatingTitle: String { c("Locating Codex", "正在查找 Codex") }
    var connectionLocatingBody: String { c("Looking for Codex on this Mac.", "正在这台 Mac 上查找 Codex。") }
    var connectionStartingTitle: String { c("Starting local service", "正在启动本机服务") }
    var connectionStartingBody: String { c("Preparing the local Codex connection.", "正在准备本机 Codex 连接。") }
    var connectionConnectingTitle: String { c("Connecting", "正在连接") }
    var connectionConnectingBody: String { c("Establishing the local Codex connection.", "正在建立本机 Codex 连接。") }
    var connectionCheckingTitle: String { c("Checking account", "正在检查账户") }
    var connectionCheckingBody: String { c("Asking Codex whether sign-in is ready.", "正在询问 Codex 登录是否就绪。") }
    var connectionAccountConnectedTitle: String { c("Account connected", "账户已连接") }
    var connectionAccountConnectedBody: String { c("Preparing your usage limits.", "正在准备用量限额。") }
    var connectionAuthorizationRequiredTitle: String { c("Codex sign-in required", "需要登录 Codex") }
    var connectionAuthorizationRequiredBody: String {
        c(
            "Sign in through the official Codex CLI outside this monitor, then choose Check again. The monitor never opens a browser or another app for sign-in.",
            "请在本监控器之外通过官方 Codex CLI 登录，然后选择“再次检查”。本监控器不会为登录打开浏览器或其他应用。"
        )
    }
    var connectionCheckAgain: String { c("Check Again", "再次检查") }
    var connectionCancel: String { c("Cancel", "取消") }
    var connectionLoadingLimitsTitle: String { c("Loading limits", "正在加载限额") }
    var connectionLoadingLimitsBody: String { c("Reading your current Codex limits.", "正在读取你当前的 Codex 限额。") }
    var connectionLoadingUsageTitle: String { c("Loading usage", "正在加载用量") }
    var connectionLoadingUsageBody: String { c("Reading your token summary.", "正在读取 Token 用量摘要。") }
    var connectionLoadingActivityTitle: String { c("Loading optional activity", "正在加载可选活动") }
    var connectionLoadingActivityBody: String { c("Usage is ready while recent activity finishes.", "用量已就绪，最近活动仍在加载。") }
    var connectionReadyBody: String { c("Current Codex usage is ready.", "当前 Codex 用量已就绪。") }
    var connectionRefreshingTitle: String { c("Refreshing", "正在刷新") }
    var connectionRefreshingBody: String { c("Keeping the previous verified values visible.", "继续显示先前已验证的数值。") }
    var connectionStaleTitle: String { c("Showing earlier data", "正在显示较早的数据") }
    var connectionStaleBody: String { c("Refresh failed; showing last values.", "刷新失败；显示上次数据。") }
    var connectionStaleAnnouncement: String { c("Earlier data is displayed and marked stale.", "当前显示的是较早数据，并已标记为过期。") }
    var connectionRetry: String { c("Retry", "重试") }
    var connectionDisconnect: String { c("Disconnect Monitor", "断开监视器") }
    var connectionReconnect: String { c("Reconnect", "重新连接") }
    var connectionDisconnectNote: String { c("Disconnecting the monitor does not sign you out of Codex.", "断开监视器不会退出你的 Codex 登录。") }
    var connectionTechnicalDetail: String { c("Diagnostic code", "诊断代码") }

    func connectionFailureCopy(for failure: CodexUsageClientFailure) -> CodexFailureCopy {
        let english: (String, String, String, Bool)
        let chinese: (String, String)
        switch failure {
        case .monitorConsentMissing:
            english = ("Permission required", "Connect before the monitor requests Codex data.", "consent-required", false)
            chinese = ("需要许可", "连接后，监视器才能请求 Codex 数据。")
        case .codexApplicationNotFound:
            english = ("Codex not found", "Install or open the current Codex app, then try again.", "codex-app-missing", true)
            chinese = ("未找到 Codex", "请安装或打开当前 Codex 应用，然后重试。")
        case .codexExecutableNotFound:
            english = ("Codex component missing", "Update Codex, then try again.", "codex-component-missing", true)
            chinese = ("缺少 Codex 组件", "请更新 Codex，然后重试。")
        case .codexExecutableNotExecutable:
            english = ("Codex component unavailable", "Update or reinstall Codex, then try again.", "codex-component-unavailable", true)
            chinese = ("Codex 组件不可用", "请更新或重新安装 Codex，然后重试。")
        case .processLaunchFailed:
            english = ("Could not start Codex", "The local Codex service could not start.", "local-service-start-failed", true)
            chinese = ("无法启动 Codex", "本机 Codex 服务无法启动。")
        case .initializationTimedOut:
            english = ("Codex did not respond", "The local connection took too long to start.", "connection-start-timeout", true)
            chinese = ("Codex 未响应", "本机连接启动时间过长。")
        case .initializationRejected:
            english = ("Connection rejected", "This Codex version did not accept the connection.", "connection-rejected", false)
            chinese = ("连接被拒绝", "此 Codex 版本未接受连接。")
        case .protocolIncompatible:
            english = ("Update Codex", "This Codex version is not compatible with the monitor.", "codex-version-incompatible", false)
            chinese = ("请更新 Codex", "此 Codex 版本与监视器不兼容。")
        case .accountCheckTimedOut:
            english = ("Account check timed out", "Codex did not finish checking sign-in.", "account-check-timeout", true)
            chinese = ("账户检查超时", "Codex 未能完成登录检查。")
        case .accountAuthorizationRequired:
            english = ("Sign-in required", "Codex needs you to sign in before usage can load.", "sign-in-required", false)
            chinese = ("需要登录", "Codex 需要你登录后才能加载用量。")
        case .accountAuthorizationCanceled:
            english = ("Sign-in canceled", "No account data was loaded.", "sign-in-canceled", true)
            chinese = ("登录已取消", "未加载任何账户数据。")
        case .accountAuthorizationFailed:
            english = ("Sign-in did not finish", "Try the sign-in flow again.", "sign-in-failed", true)
            chinese = ("登录未完成", "请再次尝试登录流程。")
        case .requestTimedOut:
            english = ("Request timed out", "Codex did not return the requested data in time.", "request-timeout", true)
            chinese = ("请求超时", "Codex 未能及时返回所需数据。")
        case .serverOverloaded:
            english = ("Codex is busy", "Wait a moment, then retry.", "local-service-busy", true)
            chinese = ("Codex 正忙", "请稍后再重试。")
        case .serverError:
            english = ("Codex could not complete the request", "Try again when Codex is ready.", "safe-service-failure", true)
            chinese = ("Codex 无法完成请求", "请在 Codex 就绪后重试。")
        case .processExited:
            english = ("Codex connection ended", "The local service stopped before the request finished.", "local-service-ended", true)
            chinese = ("Codex 连接已结束", "请求完成前，本机服务已停止。")
        case .malformedResponse:
            english = ("Unexpected Codex response", "The monitor could not validate the returned data.", "invalid-response", true)
            chinese = ("Codex 响应异常", "监视器无法验证返回的数据。")
        case .requiredDataMissing:
            english = ("Usage data incomplete", "Required usage values were not available.", "required-data-missing", true)
            chinese = ("用量数据不完整", "缺少必要的用量数值。")
        case .optionalDataUnavailable:
            english = ("Recent activity unavailable", "Your usage limits remain available.", "optional-activity-unavailable", true)
            chinese = ("最近活动不可用", "你的用量限额仍然可用。")
        case .unknownSafeError:
            english = ("Could not load usage", "Try again when Codex is ready.", "unknown-safe-failure", true)
            chinese = ("无法加载用量", "请在 Codex 就绪后重试。")
        }
        return CodexFailureCopy(
            title: self == .simplifiedChinese ? chinese.0 : english.0,
            body: self == .simplifiedChinese ? chinese.1 : english.1,
            detail: english.2,
            canRetry: english.3
        )
    }
}
