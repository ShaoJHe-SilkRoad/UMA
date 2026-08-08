import Foundation

/// The complete, versioned data contract that may cross the browser/native
/// boundary. It intentionally contains no URL, page text, identity, cookie, or
/// credential field.
public enum ClaudeBrowserBridgeContract {
    public static let messageKind = "claudeUsageObservation"
    public static let sourceID = "claude-browser-usage"
    public static let schemaVersion = 1
    public static let extractorSchemaVersion = 1
    public static let maximumMessageBytes = 4_096
    public static let officialOrigin = "https://claude.ai"
    public static let officialUsagePath = "/new"
    public static let officialUsageFragment = "settings/usage"
    public static let officialUsageURL = URL(
        string: officialOrigin + officialUsagePath + "#" + officialUsageFragment
    )!
    public static let chromiumExtensionID = "jgoknghcplngcnldmfenkghcbommaalj"
    public static let chromiumExtensionOrigin = "chrome-extension://\(chromiumExtensionID)/"
    public static let chromiumNativeHostName = "com.silkrd.uma.claude_browser"
    public static let safariApplicationIdentifier = "com.silkrd.uma"
    public static let automationMessageKind = "claudeBrowserAutomationEvent"
    public static let automaticRefreshMessageName = "umaClaudeAutomaticRefresh"
    public static let closeOwnedTabMessageName = "umaClaudeCloseOwnedUsageTab"
    public static let exactUsageHostPermission = "https://claude.ai/new*"
}

public enum ClaudeBrowserFamily: String, Codable, CaseIterable, Sendable {
    case safari
    case chromium
}

public enum ClaudeBrowserRouteState: String, Codable, Sendable {
    /// HTTPS, exact host/path, expected Usage landmarks, and no login form.
    case verifiedUsage
}

public enum ClaudeBrowserModelFamily: String, Codable, CaseIterable, Sendable {
    case sonnet
    case opus
    case haiku
}

public struct ClaudeBrowserQuotaWindow: Codable, Equatable, Sendable {
    /// Browser Companion reports provider-displayed usage. UMA converts used
    /// to remaining exactly once in the shared presentation layer.
    public let usedPercentage: Double
    /// An RFC 3339/ISO 8601 timestamp when the page exposes a machine-readable
    /// reset. Human page copy is never forwarded.
    public let resetAt: String?

    public init(usedPercentage: Double, resetAt: String? = nil) {
        self.usedPercentage = usedPercentage
        self.resetAt = resetAt
    }
}

public struct ClaudeBrowserModelWindow: Codable, Equatable, Sendable {
    public let modelFamily: ClaudeBrowserModelFamily
    public let window: ClaudeBrowserQuotaWindow

    public init(modelFamily: ClaudeBrowserModelFamily, window: ClaudeBrowserQuotaWindow) {
        self.modelFamily = modelFamily
        self.window = window
    }
}

public struct ClaudeBrowserObservation: Codable, Equatable, Sendable {
    public let fiveHour: ClaudeBrowserQuotaWindow?
    public let weeklyAllModels: ClaudeBrowserQuotaWindow?
    public let modelSpecificWeekly: ClaudeBrowserModelWindow?
    public let observedAt: String
    public let extractorSchemaVersion: Int

    public init(
        fiveHour: ClaudeBrowserQuotaWindow?,
        weeklyAllModels: ClaudeBrowserQuotaWindow?,
        modelSpecificWeekly: ClaudeBrowserModelWindow? = nil,
        observedAt: String,
        extractorSchemaVersion: Int = ClaudeBrowserBridgeContract.extractorSchemaVersion
    ) {
        self.fiveHour = fiveHour
        self.weeklyAllModels = weeklyAllModels
        self.modelSpecificWeekly = modelSpecificWeekly
        self.observedAt = observedAt
        self.extractorSchemaVersion = extractorSchemaVersion
    }
}

public struct ClaudeBrowserObservationEnvelope: Codable, Equatable, Sendable {
    public let kind: String
    public let schemaVersion: Int
    public let sourceID: String
    public let browserFamily: ClaudeBrowserFamily
    public let routeState: ClaudeBrowserRouteState
    public let observation: ClaudeBrowserObservation

    public init(
        browserFamily: ClaudeBrowserFamily,
        observation: ClaudeBrowserObservation,
        kind: String = ClaudeBrowserBridgeContract.messageKind,
        schemaVersion: Int = ClaudeBrowserBridgeContract.schemaVersion,
        sourceID: String = ClaudeBrowserBridgeContract.sourceID,
        routeState: ClaudeBrowserRouteState = .verifiedUsage
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.browserFamily = browserFamily
        self.routeState = routeState
        self.observation = observation
    }
}

/// A content-free control result for one app-owned automatic refresh request.
/// It contains no URL, tab title, page text, account value, or browser identity.
public enum ClaudeBrowserAutomationStatus: String, Codable, CaseIterable, Sendable {
    case bridgeReady
    case refreshStarted
    case refreshCompleted
    case permissionRequired
    case signInRequired
    case routeRejected
    case usageUnavailable
    case tabUnavailable
    case ownedTabClosed
    case ownedTabOwnershipLost
}

public struct ClaudeBrowserAutomationEvent: Codable, Equatable, Sendable {
    public let kind: String
    public let schemaVersion: Int
    public let sourceID: String
    public let browserFamily: ClaudeBrowserFamily
    public let requestID: String
    public let status: ClaudeBrowserAutomationStatus
    public let occurredAt: String

    public init(
        requestID: String,
        status: ClaudeBrowserAutomationStatus,
        occurredAt: String,
        kind: String = ClaudeBrowserBridgeContract.automationMessageKind,
        schemaVersion: Int = ClaudeBrowserBridgeContract.schemaVersion,
        sourceID: String = ClaudeBrowserBridgeContract.sourceID,
        browserFamily: ClaudeBrowserFamily = .safari
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.browserFamily = browserFamily
        self.requestID = requestID
        self.status = status
        self.occurredAt = occurredAt
    }
}
