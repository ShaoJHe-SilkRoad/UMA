import Foundation

/// The complete, versioned data contract that may cross the browser/native
/// boundary. It intentionally contains no URL, page text, identity, cookie, or
/// credential field.
public enum ClaudeBrowserBridgeContract {
    public static let messageKind = "claudeUsageObservation"
    public static let sourceID = "claude-browser-usage"
    public static let schemaVersion = 2
    public static let extractorSchemaVersion = 2
    public static let sourceLayoutVersion = 1
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
    public static let safariExtensionIdentifier =
        "com.silkrd.uma.ClaudeBrowserCompanion"
#if !UMA_PRODUCTION_RELEASE
    public static let safariTestApplicationIdentifier = "com.silkrd.uma.test"
    public static let safariTestExtensionIdentifier =
        "com.silkrd.uma.test.ClaudeBrowserCompanion"
    public static let safariHostTestApplicationIdentifier =
        "com.silkrd.uma.test.safarihost"
    public static let safariHostTestExtensionIdentifier =
        "com.silkrd.uma.test.safarihost.ClaudeBrowserCompanion"
    public static let safariHostTestAppGroupIdentifier =
        "group.com.silkrd.uma.test.bridge"
#endif
    public static let safariHostProductionApplicationIdentifier =
        "com.silkrd.uma.safarihost"
    public static let safariHostProductionExtensionIdentifier =
        safariExtensionIdentifier
    public static let safariHostProductionAppGroupIdentifier =
        "group.com.silkrd.uma.bridge"
    public static let safariExtensionVersion = "1.4.0"
    public static let safariExtensionBuild = "10"
    public static let automationMessageKind = "claudeBrowserAutomationEvent"
    public static let terminalMessageKind = "claudeBrowserTerminalPacket"
    public static let automaticRefreshMessageName = "umaClaudeAutomaticRefresh"
    public static let wakeBridgeMessageName = "umaClaudeWakeBridge"
    public static let runtimeQualificationMessageName =
        "umaClaudeRuntimeQualification"
    public static let closeOwnedTabMessageName = "umaClaudeCloseOwnedUsageTab"
    public static let exactUsageHostPermission = "https://claude.ai/new*"
    public static let runtimeQualificationMessageKind =
        "claudeBrowserRuntimeQualificationRequest"
    public static let runtimeQualificationReplyKind =
        "claudeBrowserRuntimeQualificationReply"
    public static let runtimeQualificationAcknowledgementKind =
        "claudeBrowserRuntimeQualificationAcknowledgement"
    public static let runtimeGenerationInfoKey = "UMARuntimeGenerationID"
    public static let containingApplicationInfoKey =
        "UMAContainingApplicationIdentifier"
    public static let teamIdentifierInfoKey = "UMATeamIdentifier"
    public static let runtimeChannelInfoKey = "UMARuntimeChannel"
    public static let extensionIdentifierInfoKey = "UMAExtensionBundleIdentifier"
    public static let appVersionInfoKey = "UMAAppVersion"
    public static let appBuildInfoKey = "UMAAppBuild"
    public static let extensionVersionInfoKey = "UMAExtensionVersion"
    public static let extensionBuildInfoKey = "UMAExtensionBuild"
    public static let appGroupIdentifierInfoKey = "UMAAppGroupIdentifier"
    public static let expectedTeamIdentifier = "C6TUZVJ6SJ"
}

/// A runtime channel is an identity boundary, not a packaging label. The Test
/// channel never shares a LaunchServices, PlugInKit, native-message, or local
/// handoff identity with a production UMA installation.
public enum ClaudeBrowserRuntimeChannel: String, Codable, CaseIterable, Sendable {
    case production
    case productionSafariHost = "production-safari-host"
    case test
    case testSafariHost = "test-safari-host"
}

public struct ClaudeBrowserRuntimeIdentity: Codable, Equatable, Sendable {
    public let channel: ClaudeBrowserRuntimeChannel
    public let containingApplicationIdentifier: String
    public let extensionIdentifier: String
    public let nativeApplicationIdentifier: String
    public let handoffDirectoryRelativePath: String

    public init(
        channel: ClaudeBrowserRuntimeChannel,
        containingApplicationIdentifier: String,
        extensionIdentifier: String,
        nativeApplicationIdentifier: String,
        handoffDirectoryRelativePath: String
    ) {
        self.channel = channel
        self.containingApplicationIdentifier = containingApplicationIdentifier
        self.extensionIdentifier = extensionIdentifier
        self.nativeApplicationIdentifier = nativeApplicationIdentifier
        self.handoffDirectoryRelativePath = handoffDirectoryRelativePath
    }

    public static let production = Self(
        channel: .production,
        containingApplicationIdentifier: ClaudeBrowserBridgeContract.safariApplicationIdentifier,
        extensionIdentifier: ClaudeBrowserBridgeContract.safariExtensionIdentifier,
        nativeApplicationIdentifier: ClaudeBrowserBridgeContract.safariApplicationIdentifier,
        handoffDirectoryRelativePath:
            "Library/Application Support/CodexUsageMonitor/ClaudeBrowserCompanion"
    )

#if !UMA_PRODUCTION_RELEASE
    public static let test = Self(
        channel: .test,
        containingApplicationIdentifier:
            ClaudeBrowserBridgeContract.safariTestApplicationIdentifier,
        extensionIdentifier: ClaudeBrowserBridgeContract.safariTestExtensionIdentifier,
        nativeApplicationIdentifier:
            ClaudeBrowserBridgeContract.safariTestApplicationIdentifier,
        handoffDirectoryRelativePath:
            "Library/Application Support/CodexUsageMonitor/TestChannel/ClaudeBrowserCompanion"
    )

    /// The immutable Apple Development Safari containing Host. This identity
    /// is intentionally distinct from the frequently replaced mutable UMA
    /// Test application. Only this Host owns Safari dispatch, native callbacks,
    /// and durable owned-tab receipts for the Test channel.
    public static let testSafariHost = Self(
        channel: .testSafariHost,
        containingApplicationIdentifier:
            ClaudeBrowserBridgeContract.safariHostTestApplicationIdentifier,
        extensionIdentifier:
            ClaudeBrowserBridgeContract.safariHostTestExtensionIdentifier,
        nativeApplicationIdentifier:
            ClaudeBrowserBridgeContract.safariHostTestApplicationIdentifier,
        handoffDirectoryRelativePath:
            "Library/Group Containers/"
                + ClaudeBrowserBridgeContract.safariHostTestAppGroupIdentifier
                + "/ClaudeSafariHost/NativeInbox"
    )
#endif

    /// The immutable Developer ID Safari containing Host used by release UMA.
    /// The mutable product keeps `com.silkrd.uma`; the established production
    /// Companion identifier remains unchanged while its containing Host gains
    /// an independently versioned, stable identity.
    public static let productionSafariHost = Self(
        channel: .productionSafariHost,
        containingApplicationIdentifier:
            ClaudeBrowserBridgeContract.safariHostProductionApplicationIdentifier,
        extensionIdentifier:
            ClaudeBrowserBridgeContract.safariHostProductionExtensionIdentifier,
        nativeApplicationIdentifier:
            ClaudeBrowserBridgeContract.safariHostProductionApplicationIdentifier,
        handoffDirectoryRelativePath:
            "Library/Group Containers/"
                + ClaudeBrowserBridgeContract.safariHostProductionAppGroupIdentifier
                + "/ClaudeSafariHost/NativeInbox"
    )

    public static func matching(
        containingApplicationIdentifier: String
    ) -> Self? {
        switch containingApplicationIdentifier {
        case production.containingApplicationIdentifier: production
        case productionSafariHost.containingApplicationIdentifier: productionSafariHost
#if !UMA_PRODUCTION_RELEASE
        case test.containingApplicationIdentifier: test
        case testSafariHost.containingApplicationIdentifier: testSafariHost
#endif
        default: nil
        }
    }

    public static func matching(extensionIdentifier: String) -> Self? {
        switch extensionIdentifier {
        case production.extensionIdentifier: production
        // The established production Companion identifier is shared by the
        // retired combined runtime and the immutable production Host. Callers
        // that qualify a signed package must match both containing and
        // extension identifiers; extension-only matching remains historical.
#if !UMA_PRODUCTION_RELEASE
        case test.extensionIdentifier: test
        case testSafariHost.extensionIdentifier: testSafariHost
#endif
        default: nil
        }
    }
}

/// Exact signed-package identities for the immutable Safari Host boundary.
/// Selection is by the mutable or Host bundle identifier and every remaining
/// field is then compared as one unit. Unknown or mixed channel metadata has no
/// fallback and is rejected before IPC is opened.
public struct ClaudeSafariHostRuntimeProfile: Equatable, Sendable {
    public let mutableApplicationIdentifier: String
    public let identity: ClaudeBrowserRuntimeIdentity
    public let appGroupIdentifier: String

    public static let production = Self(
        mutableApplicationIdentifier:
            ClaudeBrowserBridgeContract.safariApplicationIdentifier,
        identity: .productionSafariHost,
        appGroupIdentifier:
            ClaudeBrowserBridgeContract.safariHostProductionAppGroupIdentifier
    )

#if !UMA_PRODUCTION_RELEASE
    public static let test = Self(
        mutableApplicationIdentifier:
            ClaudeBrowserBridgeContract.safariTestApplicationIdentifier,
        identity: .testSafariHost,
        appGroupIdentifier:
            ClaudeBrowserBridgeContract.safariHostTestAppGroupIdentifier
    )
#endif

    public static func matchingMutableApplicationIdentifier(
        _ identifier: String?
    ) -> Self? {
        switch identifier {
        case production.mutableApplicationIdentifier: production
#if !UMA_PRODUCTION_RELEASE
        case test.mutableApplicationIdentifier: test
#endif
        default: nil
        }
    }

    public static func matchingHostApplicationIdentifier(
        _ identifier: String?
    ) -> Self? {
        switch identifier {
        case production.identity.containingApplicationIdentifier: production
#if !UMA_PRODUCTION_RELEASE
        case test.identity.containingApplicationIdentifier: test
#endif
        default: nil
        }
    }

    public static func matchingRuntimeChannel(
        _ channel: ClaudeBrowserRuntimeChannel?
    ) -> Self? {
        switch channel {
        case .productionSafariHost: production
#if !UMA_PRODUCTION_RELEASE
        case .testSafariHost: test
#endif
        default: nil
        }
    }
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
    public let sourceLayoutVersion: Int

    public init(
        fiveHour: ClaudeBrowserQuotaWindow?,
        weeklyAllModels: ClaudeBrowserQuotaWindow?,
        modelSpecificWeekly: ClaudeBrowserModelWindow? = nil,
        observedAt: String,
        extractorSchemaVersion: Int = ClaudeBrowserBridgeContract.extractorSchemaVersion,
        sourceLayoutVersion: Int = ClaudeBrowserBridgeContract.sourceLayoutVersion
    ) {
        self.fiveHour = fiveHour
        self.weeklyAllModels = weeklyAllModels
        self.modelSpecificWeekly = modelSpecificWeekly
        self.observedAt = observedAt
        self.extractorSchemaVersion = extractorSchemaVersion
        self.sourceLayoutVersion = sourceLayoutVersion
    }
}

public struct ClaudeBrowserObservationEnvelope: Codable, Equatable, Sendable {
    public let kind: String
    public let schemaVersion: Int
    public let sourceID: String
    public let browserFamily: ClaudeBrowserFamily
    public let routeState: ClaudeBrowserRouteState
    /// The exact one-shot request that authorized this observation. A packet
    /// from an older or parallel companion instance cannot satisfy a current
    /// Accuracy Sync merely by carrying a fresh observation nonce.
    public let requestID: String
    /// A per-observation nonce. The app rejects duplicates for the lifetime of
    /// the current listener, preventing a captured handoff from being replayed.
    public let observationID: String
    public let observation: ClaudeBrowserObservation

    public init(
        browserFamily: ClaudeBrowserFamily,
        observation: ClaudeBrowserObservation,
        kind: String = ClaudeBrowserBridgeContract.messageKind,
        schemaVersion: Int = ClaudeBrowserBridgeContract.schemaVersion,
        sourceID: String = ClaudeBrowserBridgeContract.sourceID,
        routeState: ClaudeBrowserRouteState = .verifiedUsage,
        requestID: String = UUID().uuidString.lowercased(),
        observationID: String = UUID().uuidString.lowercased()
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.browserFamily = browserFamily
        self.routeState = routeState
        self.requestID = requestID
        self.observationID = observationID
        self.observation = observation
    }
}

/// A content-free control result for one app-owned automatic refresh request.
/// It contains no URL, tab title, page text, account value, or browser identity.
public enum ClaudeBrowserAutomationStatus: String, Codable, CaseIterable, Sendable {
    case extensionBackgroundReady
    case nativeHandlerEntered
    case nativeRequestDecoded
    case runtimeGenerationValidated
    case nativeResponseCreated
    case nativeResponseSent
    case extensionResponseReceived
    case bridgeReady
    case refreshStarted
    case refreshCompleted
    case permissionRequired
    case signInRequired
    case routeRejected
    case browserUnavailable
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
    /// Present only on runtime lifecycle receipts. These fixed values prove
    /// that the responding companion matches the embedded candidate before
    /// qualification or provider work is dispatched.
    public let companionVersion: String?
    public let companionBuild: String?
    public let protocolSchemaVersion: Int?
    public let containingApplicationIdentifier: String?
    public let extensionIdentifier: String?
    public let teamIdentifier: String?
    public let runtimeGenerationID: String?

    public init(
        requestID: String,
        status: ClaudeBrowserAutomationStatus,
        occurredAt: String,
        companionVersion: String? = nil,
        companionBuild: String? = nil,
        protocolSchemaVersion: Int? = nil,
        containingApplicationIdentifier: String? = nil,
        extensionIdentifier: String? = nil,
        teamIdentifier: String? = nil,
        runtimeGenerationID: String? = nil,
        kind: String = ClaudeBrowserBridgeContract.automationMessageKind,
        schemaVersion: Int = ClaudeBrowserBridgeContract.schemaVersion,
        sourceID: String = ClaudeBrowserBridgeContract.sourceID,
        browserFamily: ClaudeBrowserFamily = .safari
    ) {
        let carriesRuntimeIdentity: Bool
        switch status {
        case .extensionBackgroundReady, .nativeHandlerEntered,
             .nativeRequestDecoded, .runtimeGenerationValidated,
             .nativeResponseCreated, .nativeResponseSent,
             .extensionResponseReceived, .bridgeReady:
            carriesRuntimeIdentity = true
        default:
            carriesRuntimeIdentity = false
        }
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.browserFamily = browserFamily
        self.requestID = requestID
        self.status = status
        self.occurredAt = occurredAt
        // Runtime identity is package-authoritative. Never synthesize stale
        // production IDs, builds, or a random generation in this shared
        // protocol layer. Runtime-bearing events with missing fields fail
        // decoding instead of masquerading as another signed channel.
        self.companionVersion = carriesRuntimeIdentity ? companionVersion : nil
        self.companionBuild = carriesRuntimeIdentity ? companionBuild : nil
        self.protocolSchemaVersion = carriesRuntimeIdentity
            ? protocolSchemaVersion : nil
        self.containingApplicationIdentifier = carriesRuntimeIdentity
            ? containingApplicationIdentifier : nil
        self.extensionIdentifier = carriesRuntimeIdentity
            ? extensionIdentifier : nil
        self.teamIdentifier = carriesRuntimeIdentity ? teamIdentifier : nil
        self.runtimeGenerationID = carriesRuntimeIdentity
            ? runtimeGenerationID?.lowercased() : nil
    }
}

/// One generation-bound terminal result emitted only after the Companion has
/// completed its proven-tab and durable-receipt cleanup. A successful packet
/// carries the allowlisted observation; every failure is content-free. Close
/// acknowledgements bind their own command ID to the target operation so a
/// stale cancellation can never complete a newer request.
public enum ClaudeBrowserProviderFailureReason: String, Codable, CaseIterable, Sendable {
    case routeNotReady = "ROUTE_NOT_READY"
    case routeReadinessTimeout = "ROUTE_READINESS_TIMEOUT"
    case providerDocumentNotReady = "PROVIDER_DOCUMENT_NOT_READY"
    case targetDataNotReady = "TARGET_DATA_NOT_READY"
    case targetDataTimeout = "TARGET_DATA_TIMEOUT"
    case providerStructureUnsupported = "PROVIDER_STRUCTURE_UNSUPPORTED"
    case providerSessionUnavailable = "PROVIDER_SESSION_UNAVAILABLE"
    case sitePermissionMissing = "SITE_PERMISSION_MISSING"
    case extractionValidationFailed = "EXTRACTION_VALIDATION_FAILED"
    case requestCancelled = "REQUEST_CANCELLED"
    case providerTabClosed = "PROVIDER_TAB_CLOSED"
}

public struct ClaudeBrowserTerminalPacket: Codable, Equatable, Sendable {
    public let kind: String
    public let schemaVersion: Int
    public let sourceID: String
    public let browserFamily: ClaudeBrowserFamily
    public let requestID: String
    public let targetRequestID: String?
    public let runtimeGenerationID: String
    public let status: ClaudeBrowserAutomationStatus
    public let occurredAt: String
    public let observation: ClaudeBrowserObservationEnvelope?
    public let providerFailureReason: ClaudeBrowserProviderFailureReason?

    public init(
        requestID: String,
        targetRequestID: String? = nil,
        runtimeGenerationID: String,
        status: ClaudeBrowserAutomationStatus,
        occurredAt: String,
        observation: ClaudeBrowserObservationEnvelope? = nil,
        providerFailureReason: ClaudeBrowserProviderFailureReason? = nil,
        kind: String = ClaudeBrowserBridgeContract.terminalMessageKind,
        schemaVersion: Int = ClaudeBrowserBridgeContract.schemaVersion,
        sourceID: String = ClaudeBrowserBridgeContract.sourceID,
        browserFamily: ClaudeBrowserFamily = .safari
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.browserFamily = browserFamily
        self.requestID = requestID.lowercased()
        self.targetRequestID = targetRequestID?.lowercased()
        self.runtimeGenerationID = runtimeGenerationID.lowercased()
        self.status = status
        self.occurredAt = occurredAt
        self.observation = observation
        self.providerFailureReason = providerFailureReason
    }
}

/// A content-free request from the Safari background page to its signed native
/// extension handler. The handler, rather than JavaScript configuration,
/// creates the authoritative runtime identity receipt.
public struct ClaudeBrowserRuntimeQualificationRequest: Codable, Equatable, Sendable {
    public let kind: String
    public let schemaVersion: Int
    public let sourceID: String
    public let browserFamily: ClaudeBrowserFamily
    public let requestID: String
    public let runtimeGenerationID: String

    public init(
        requestID: String,
        runtimeGenerationID: String,
        kind: String = ClaudeBrowserBridgeContract.runtimeQualificationMessageKind,
        schemaVersion: Int = ClaudeBrowserBridgeContract.schemaVersion,
        sourceID: String = ClaudeBrowserBridgeContract.sourceID,
        browserFamily: ClaudeBrowserFamily = .safari
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.browserFamily = browserFamily
        self.requestID = requestID
        self.runtimeGenerationID = runtimeGenerationID
    }
}

/// The signed native handler's content-free answer to one qualification
/// request. JavaScript must validate every field and echo the reply ID in a
/// separate acknowledgement before the handler may publish `bridgeReady`.
public struct ClaudeBrowserRuntimeQualificationReply: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Equatable, Sendable {
        case accepted
        case runtimeGenerationMismatch
    }

    public let kind: String
    public let schemaVersion: Int
    public let sourceID: String
    public let browserFamily: ClaudeBrowserFamily
    public let requestID: String
    public let replyID: String
    public let runtimeGenerationID: String
    public let companionVersion: String
    public let companionBuild: String
    public let protocolSchemaVersion: Int
    public let containingApplicationIdentifier: String
    public let extensionIdentifier: String
    public let teamIdentifier: String
    public let accepted: Bool
    public let reason: Reason

    public init(
        requestID: String,
        replyID: String,
        runtimeGenerationID: String,
        companionVersion: String,
        companionBuild: String,
        containingApplicationIdentifier: String,
        extensionIdentifier: String,
        teamIdentifier: String,
        accepted: Bool,
        reason: Reason,
        kind: String = ClaudeBrowserBridgeContract.runtimeQualificationReplyKind,
        schemaVersion: Int = ClaudeBrowserBridgeContract.schemaVersion,
        sourceID: String = ClaudeBrowserBridgeContract.sourceID,
        browserFamily: ClaudeBrowserFamily = .safari,
        protocolSchemaVersion: Int = ClaudeBrowserBridgeContract.schemaVersion
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.browserFamily = browserFamily
        self.requestID = requestID
        self.replyID = replyID
        self.runtimeGenerationID = runtimeGenerationID
        self.companionVersion = companionVersion
        self.companionBuild = companionBuild
        self.protocolSchemaVersion = protocolSchemaVersion
        self.containingApplicationIdentifier = containingApplicationIdentifier
        self.extensionIdentifier = extensionIdentifier
        self.teamIdentifier = teamIdentifier
        self.accepted = accepted
        self.reason = reason
    }
}

/// A content-free proof that the WebExtension received and accepted the exact
/// native reply. The native handler consumes each reply ID at most once.
public struct ClaudeBrowserRuntimeQualificationAcknowledgement: Codable, Equatable, Sendable {
    public let kind: String
    public let schemaVersion: Int
    public let sourceID: String
    public let browserFamily: ClaudeBrowserFamily
    public let requestID: String
    public let replyID: String
    public let runtimeGenerationID: String
    public let accepted: Bool

    public init(
        requestID: String,
        replyID: String,
        runtimeGenerationID: String,
        accepted: Bool = true,
        kind: String = ClaudeBrowserBridgeContract.runtimeQualificationAcknowledgementKind,
        schemaVersion: Int = ClaudeBrowserBridgeContract.schemaVersion,
        sourceID: String = ClaudeBrowserBridgeContract.sourceID,
        browserFamily: ClaudeBrowserFamily = .safari
    ) {
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.browserFamily = browserFamily
        self.requestID = requestID
        self.replyID = replyID
        self.runtimeGenerationID = runtimeGenerationID
        self.accepted = accepted
    }
}
