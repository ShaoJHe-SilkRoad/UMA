import Foundation

/// The monitor's public, credential-free view of the local Codex connection.
///
/// These cases deliberately describe lifecycle state rather than account
/// identity.  They can therefore be rendered or tested without retaining an
/// email address, account ID, token, or authorization URL.
public enum CodexConnectionState: Equatable, Sendable {
    case notAuthorizedByMonitor
    case idle
    case resolvingExecutable
    case startingServer
    case initializing
    case checkingAccount
    case accountAvailable
    case authorizationRequired
    /// The local app-server did not report an available account. The Human
    /// completes official CLI sign-in outside this monitor before retrying.
    case officialCodexSignInRequired
    case loadingRateLimits
    case loadingUsage
    case loadingOptionalActivity
    case ready
    case refreshingWithPreviousRealData
    case staleWithPreviousRealData(CodexUsageClientFailure)
    case recoverableFailure(CodexUsageClientFailure)
    case blockedFailure(CodexUsageClientFailure)

    var isFailure: Bool {
        switch self {
        case .staleWithPreviousRealData, .recoverableFailure, .blockedFailure:
            true
        default:
            false
        }
    }

    func statusText(language: AppLanguage) -> String {
        switch self {
        case .notAuthorizedByMonitor:
            language == .simplifiedChinese ? "等待你的连接授权" : "Waiting for your connection permission"
        case .idle:
            language == .simplifiedChinese ? "等待连接 Codex" : "Ready to connect to Codex"
        case .resolvingExecutable, .startingServer, .initializing, .checkingAccount:
            language == .simplifiedChinese ? "正在连接本机 Codex" : "Connecting to local Codex"
        case .accountAvailable, .loadingRateLimits, .loadingUsage, .loadingOptionalActivity:
            language == .simplifiedChinese ? "正在读取本机 Codex 用量" : "Reading local Codex usage"
        case .authorizationRequired:
            language == .simplifiedChinese ? "需要 Codex 授权" : "Codex authorization required"
        case .officialCodexSignInRequired:
            language == .simplifiedChinese ? "等待本机 Codex 登录" : "Waiting for local Codex sign-in"
        case .ready:
            language == .simplifiedChinese ? "本机 Codex 用量已更新" : "Local Codex usage updated"
        case .refreshingWithPreviousRealData:
            language == .simplifiedChinese ? "正在刷新已保存的真实用量" : "Refreshing saved live usage"
        case .staleWithPreviousRealData:
            language == .simplifiedChinese ? "显示上次真实用量，刷新未完成" : "Showing previous live usage; refresh did not finish"
        case .recoverableFailure, .blockedFailure:
            language.failureStatus
        }
    }
}

/// A safe, stable failure vocabulary for the UI and tests.  The associated
/// strings are protocol method names or a fixed product message, never raw
/// server stderr, response bodies, account identifiers, or authorization URLs.
public enum CodexUsageClientFailure: Equatable, Sendable {
    case monitorConsentMissing
    case codexApplicationNotFound
    case codexExecutableNotFound
    case codexExecutableNotExecutable
    case processLaunchFailed
    case initializationTimedOut
    case initializationRejected
    case protocolIncompatible
    case accountCheckTimedOut
    case accountAuthorizationRequired
    case accountAuthorizationCanceled
    case accountAuthorizationFailed
    case requestTimedOut(method: String)
    case serverOverloaded
    case serverError(method: String, safeMessage: String)
    case processExited
    case malformedResponse(method: String)
    case requiredDataMissing
    case optionalDataUnavailable
    case unknownSafeError

    var blocksConnection: Bool {
        switch self {
        case .monitorConsentMissing, .codexApplicationNotFound,
             .codexExecutableNotFound, .codexExecutableNotExecutable,
             .initializationRejected, .protocolIncompatible,
             .accountAuthorizationRequired, .accountAuthorizationCanceled,
             .accountAuthorizationFailed, .requiredDataMissing:
            true
        default:
            false
        }
    }
}

/// A privacy-safe record of a JSON-RPC error.  It retains only the protocol
/// code, the monitor-issued method name, and a product-controlled message;
/// upstream message text and `data` are deliberately never carried forward.
public struct CodexSafeJSONRPCError: Equatable, Sendable {
    public enum Category: Equatable, Sendable {
        case serverOverloaded
        case unauthorizedOrAuthorizationRequired
        case methodUnavailableOrProtocolIncompatible
        case invalidRequestOrMalformedResponse
        case safeGenericServerError
    }

    public let code: Int
    public let category: Category
    public let method: String
    public let safeMessage: String
    public let isRetryable: Bool

    init(
        code: Int,
        category: Category,
        method: String,
        safeMessage: String,
        isRetryable: Bool
    ) {
        self.code = code
        self.category = category
        self.method = method
        self.safeMessage = safeMessage
        self.isRetryable = isRetryable
    }
}

/// Sanitized freshness only; it never carries usage values, thread data,
/// account identity, login identifiers, or authorization URLs.
public enum UsageFreshness: Equatable, Sendable {
    case fixture
    case noRealData
    case fresh
    case refreshRequired
    case stale
}
