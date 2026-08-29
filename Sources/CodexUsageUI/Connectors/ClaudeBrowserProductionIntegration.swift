import ClaudeBrowserBridgeProtocol
import ClaudeSafariHostIPC
import Foundation

enum ClaudeBrowserCompanionVerification: Equatable, Sendable {
    case verified
    case disabled
    case companionStarting
    case protocolMismatch
    case browserUnavailable
    case unavailable
}

/// Diagnostic only. Mutable UMA never uses Safari inventory as an authority;
/// the immutable Host proves actual Companion reachability.
enum ClaudeSafariExtensionAdvisoryState: Equatable, Sendable {
    case enabled
    case disabled
    case unknown
    case stateError

    var permitsDirectHandshake: Bool { true }
}

/// Signed Host metadata mirrored into an app-only UMA package. Mutable UMA has
/// no embedded extension and therefore never qualifies one from its own bundle.
struct ClaudeBrowserRuntimeContext: Equatable, Sendable {
    let identity: ClaudeBrowserRuntimeIdentity
    let canonicalAppPath: String
    let appVersion: String
    let appBuild: String
    let extensionVersion: String
    let extensionBuild: String
    let teamIdentifier: String
    let runtimeGenerationID: String
    let appGroupIdentifier: String

    init(
        identity: ClaudeBrowserRuntimeIdentity,
        canonicalAppPath: String,
        appVersion: String,
        appBuild: String,
        extensionVersion: String,
        extensionBuild: String,
        teamIdentifier: String,
        runtimeGenerationID: String,
        appGroupIdentifier: String =
            ClaudeBrowserBridgeContract.safariHostTestAppGroupIdentifier
    ) {
        self.identity = identity
        self.canonicalAppPath = canonicalAppPath
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.extensionVersion = extensionVersion
        self.extensionBuild = extensionBuild
        self.teamIdentifier = teamIdentifier
        self.runtimeGenerationID = runtimeGenerationID
        self.appGroupIdentifier = appGroupIdentifier
    }

    static func current(bundle: Bundle = .main) -> Self? {
        guard let profile = ClaudeSafariHostRuntimeProfile
                .matchingMutableApplicationIdentifier(bundle.bundleIdentifier),
              let generation = bundle.object(
                forInfoDictionaryKey: "UMASafariHostRuntimeGenerationID"
              ) as? String,
              UUID(uuidString: generation) != nil,
              bundle.object(forInfoDictionaryKey: "UMASafariHostBundleIdentifier") as? String
                == profile.identity.containingApplicationIdentifier,
              bundle.object(forInfoDictionaryKey: "UMASafariHostExtensionBundleIdentifier") as? String
                == profile.identity.extensionIdentifier,
              bundle.object(forInfoDictionaryKey: "UMAAppGroupIdentifier") as? String
                == profile.appGroupIdentifier
        else { return nil }
        return Self(
            identity: profile.identity,
            canonicalAppPath: bundle.bundleURL.resolvingSymlinksInPath().path,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            extensionVersion: bundle.object(forInfoDictionaryKey: "UMASafariHostExtensionVersion") as? String ?? "0",
            extensionBuild: bundle.object(forInfoDictionaryKey: "UMASafariHostExtensionBuild") as? String ?? "0",
            teamIdentifier: ClaudeBrowserBridgeContract.expectedTeamIdentifier,
            runtimeGenerationID: generation.lowercased(),
            appGroupIdentifier: profile.appGroupIdentifier
        )
    }

    /// Historical helper retained for already-authored regression fixtures.
    /// It is not used to qualify the immutable Host.
    static func extensionAppMetadataMatches(
        packagingMode: String,
        appVersion: String,
        appBuild: String,
        extensionAppVersion: String,
        extensionAppBuild: String,
        extensionBuild: String
    ) -> Bool {
        guard extensionAppVersion == appVersion else { return false }
        return packagingMode == "APP_ONLY"
            ? extensionAppBuild == extensionBuild
            : extensionAppBuild == appBuild
    }

    func matches(_ event: ClaudeBrowserAutomationEvent) -> Bool {
        event.status == .bridgeReady
            && event.protocolSchemaVersion == ClaudeBrowserBridgeContract.schemaVersion
            && event.containingApplicationIdentifier == identity.containingApplicationIdentifier
            && event.extensionIdentifier == identity.extensionIdentifier
            && event.companionVersion == extensionVersion
            && event.companionBuild == extensionBuild
            && event.teamIdentifier == teamIdentifier
            && event.runtimeGenerationID?.lowercased() == runtimeGenerationID
    }
}

/// Historical, content-free inventory evidence may still be decoded during
/// migration, but it cannot decide current Host readiness.
struct ClaudeSafariInventoryReceipt: Equatable, Sendable {
    enum LifecycleState: String, Sendable {
        case safariRestartRequired = "SAFARI_EXTENSION_UPDATE_PENDING_RESTART"
        case inventoryCurrent = "SAFARI_EXTENSION_CURRENT"
    }

    let canonicalAppPath: String
    let appBundleIdentifier: String
    let appVersion: String
    let appBuild: String
    let extensionBundleIdentifier: String
    let extensionVersion: String
    let extensionBuild: String
    let teamIdentifier: String
    let runtimeGenerationID: String
    let lifecycleState: LifecycleState
    let handshakeVerified: Bool
    let updatedAt: String
}

final class ClaudeBrowserOrderedConsumer: @unchecked Sendable {
    typealias Processor = @Sendable (ClaudeBrowserInboundEvent) async -> Void

    private let lock = NSLock()
    private let processor: Processor
    private var pending: [ClaudeBrowserInboundEvent] = []
    private var isDraining = false

    init(processor: @escaping Processor) { self.processor = processor }

    func submit(_ event: ClaudeBrowserInboundEvent) {
        let shouldStart = lock.withLock {
            pending.append(event)
            guard !isDraining else { return false }
            isDraining = true
            return true
        }
        guard shouldStart else { return }
        Task { await drain() }
    }

    private func drain() async {
        while let event = next() { await processor(event) }
    }

    private func next() -> ClaudeBrowserInboundEvent? {
        lock.withLock {
            guard !pending.isEmpty else {
                isDraining = false
                return nil
            }
            return pending.removeFirst()
        }
    }
}

extension ClaudeBrowserProductionIntegration {
    static func make() -> Self {
        guard let runtime = ClaudeSafariHostClientAdapter() else {
            return .unavailable()
        }
        let health: @Sendable () async -> ClaudeBrowserCompanionHealth = {
            switch await runtime.verify() {
            case .verified: .ready
            case .disabled: .disabled
            case .companionStarting: .companionStarting
            case .protocolMismatch: .protocolMismatch
            case .browserUnavailable: .browserUnavailable
            case .unavailable: .companionUnavailable
            }
        }
        return Self(
            startListening: { handler in _ = await runtime.start(handler) },
            stopListening: { await runtime.stop() },
            checkHealth: { await health() },
            openUsagePage: { await runtime.verify() == .verified },
            repairCompanion: { await health() },
            verifyHandshake: { await runtime.verify() },
            requestAutomaticRefresh: { requestID, allowSafariLaunch in
                await runtime.submit(requestID: requestID, oneShot: allowSafariLaunch)
            },
            closeOwnedUsageTab: { requestID in await runtime.close(requestID) }
        )
    }

    static func decodeInventoryReceipt(_ data: Data) -> ClaudeSafariInventoryReceipt? {
        guard data.count <= 8_192,
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = value as? [String: Any],
              Set(dictionary.keys) == [
                "schemaVersion", "canonicalAppPath", "appBundleIdentifier", "appVersion",
                "appBuild", "extensionBundleIdentifier", "extensionVersion", "extensionBuild",
                "teamIdentifier", "runtimeGenerationID", "lifecycleState",
                "handshakeVerified", "updatedAt",
              ],
              dictionary["schemaVersion"] as? Int == 2,
              let canonicalAppPath = dictionary["canonicalAppPath"] as? String,
              let appBundleIdentifier = dictionary["appBundleIdentifier"] as? String,
              let appVersion = dictionary["appVersion"] as? String,
              let appBuild = dictionary["appBuild"] as? String,
              let extensionBundleIdentifier = dictionary["extensionBundleIdentifier"] as? String,
              let extensionVersion = dictionary["extensionVersion"] as? String,
              let extensionBuild = dictionary["extensionBuild"] as? String,
              let teamIdentifier = dictionary["teamIdentifier"] as? String,
              let runtimeGenerationID = dictionary["runtimeGenerationID"] as? String,
              UUID(uuidString: runtimeGenerationID) != nil,
              let lifecycleRaw = dictionary["lifecycleState"] as? String,
              let lifecycleState = ClaudeSafariInventoryReceipt.LifecycleState(rawValue: lifecycleRaw),
              let handshakeVerified = dictionary["handshakeVerified"] as? Bool,
              let updatedAt = dictionary["updatedAt"] as? String,
              ISO8601DateFormatter().date(from: updatedAt) != nil
        else { return nil }
        return .init(
            canonicalAppPath: canonicalAppPath,
            appBundleIdentifier: appBundleIdentifier,
            appVersion: appVersion,
            appBuild: appBuild,
            extensionBundleIdentifier: extensionBundleIdentifier,
            extensionVersion: extensionVersion,
            extensionBuild: extensionBuild,
            teamIdentifier: teamIdentifier,
            runtimeGenerationID: runtimeGenerationID.lowercased(),
            lifecycleState: lifecycleState,
            handshakeVerified: handshakeVerified,
            updatedAt: updatedAt
        )
    }
}

/// Content-free qualification of Host identity, Companion, native bridge, and
/// protocol generation. It deliberately constructs no Claude connector or consent store
/// and cannot open, read, or inspect a provider page.
public enum ClaudeBrowserCompanionMachineVerifier {
    public static let launchArgument = "--verify-claude-companion-handshake"
    public static let diagnosticLaunchArgument = "--diagnose-claude-companion-pipeline"
    public static let allowSafariLaunchArgument = "--allow-safari-launch"

    public static func recognizesLaunchArgument(_ argument: String) -> Bool {
        argument == launchArgument || argument == diagnosticLaunchArgument
    }

    public static func run(allowSafariLaunch: Bool = false) async -> Bool {
        guard let runtime = ClaudeSafariHostClientAdapter() else { return false }
        let result = await runtime.diagnose(allowSafariLaunch: allowSafariLaunch).verification
        await runtime.stop()
        return result == .verified
    }

    public static func runDiagnostic(
        allowSafariLaunch: Bool = false
    ) async -> ClaudeBrowserCompanionDiagnosticResult {
        guard let runtime = ClaudeSafariHostClientAdapter() else {
            return ClaudeBrowserCompanionDiagnosticResult(
                verification: .unavailable,
                firstFailureReason: .clientRuntimeContextUnavailable,
                context: .current()
            )
        }
        let trace = await runtime.diagnose(allowSafariLaunch: allowSafariLaunch)
        await runtime.stop()
        return ClaudeBrowserCompanionDiagnosticResult(
            trace: trace,
            context: .current()
        )
    }

    static func run(
        using integration: ClaudeBrowserProductionIntegration
    ) async -> ClaudeBrowserCompanionVerification {
        await integration.startListening { _ in }
        let result = await integration.verifyHandshake()
        await integration.stopListening()
        return result
    }
}

/// The complete stdout contract for the content-free Companion diagnostic.
/// It intentionally contains no provider, browser-page, account, or payload
/// field. Distinct exit codes make every non-verified state machine-readable
/// even when stdout capture is unavailable.
public struct ClaudeBrowserCompanionDiagnosticResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case verified
        case disabled
        case starting
        case protocolMismatch
        case unavailable
    }

    public enum Stage: String, Codable, Equatable, Sendable {
        case testAppRunning
        case testRuntimeIdentityVerified
        case listenerReady
        case requestCreated
        case wakeDispatchStarted
        case requestSubmitted
        case hostRequestAccepted
        case wakeDispatchAccepted
        case extensionBackgroundAlive
        case nativePortOpenRequested
        case nativePortOpened
        case extensionBackgroundAcknowledged
        case nativeQualificationDispatched
        case nativeHandlerEntered
        case nativeRequestDecoded
        case runtimeGenerationValidated
        case nativeResponseCreated
        case nativeResponseSent
        case extensionResponseReceived
        case nativeQualificationReceived
        case companionVerified
        case containingAppCallbackReceived
        case callbackValidated
    }

    public enum FirstFailureReason: String, Codable, Equatable, Sendable {
        case clientRuntimeContextUnavailable
        case responseListenerUnavailable
        case hostApplicationUnavailable
        case requestSubmissionFailed
        case invalidHostTerminalResponse
        case clientTransactionDeadlineExceeded
        case listenerStopped
        case invalidRequest
        case duplicateRequest
        case requestInFlight
        case cancellationTargetUnavailable
        case runtimeGenerationMismatch
        case safariUnavailable
        case extensionUnavailable
        case dispatchRejected
        case dispatchCompletionUnavailable
        case nativeResponseUnavailable
        case protocolMismatch
        case extensionBackgroundNotAcknowledged
        case providerOperationTimedOut
        case observationMissing
        case duplicateNativeResponse
        case unexpectedNativeResponse
        case timedOut
        case cancelled
    }

    public let schemaVersion: Int
    public let status: Status
    public let requestID: String?
    public let runtimeGenerationID: String?
    public let hostRuntimeGenerationID: String?
    public let occurredAt: String
    public let reachedStages: [Stage]
    public let firstFailureReason: FirstFailureReason?
    public let clientApplicationIdentifier: String?
    public let clientVersion: String?
    public let clientBuild: String?
    public let hostApplicationIdentifier: String?
    public let extensionIdentifier: String?
    public let teamIdentifier: String?
    public let hostVersion: String?
    public let hostBuild: String?
    public let expectedExtensionVersion: String?
    public let expectedExtensionBuild: String?
    public let bridgeProtocolVersion: Int?

    init(verification: ClaudeBrowserCompanionVerification) {
        self.init(
            verification: verification,
            firstFailureReason: nil,
            context: nil
        )
    }

    init(
        verification: ClaudeBrowserCompanionVerification,
        firstFailureReason: FirstFailureReason?,
        context: ClaudeBrowserRuntimeContext?
    ) {
        schemaVersion = 2
        status = Self.status(for: verification)
        requestID = nil
        runtimeGenerationID = context?.runtimeGenerationID
        hostRuntimeGenerationID = nil
        occurredAt = ISO8601DateFormatter().string(from: Date())
        reachedStages = []
        self.firstFailureReason = firstFailureReason
        clientApplicationIdentifier = context.map {
            $0.identity.channel == .productionSafariHost
                ? ClaudeBrowserBridgeContract.safariApplicationIdentifier
                : ClaudeBrowserBridgeContract.safariTestApplicationIdentifier
        }
        clientVersion = context?.appVersion
        clientBuild = context?.appBuild
        hostApplicationIdentifier = context?.identity.containingApplicationIdentifier
        extensionIdentifier = context?.identity.extensionIdentifier
        teamIdentifier = context?.teamIdentifier
        hostVersion = nil
        hostBuild = nil
        expectedExtensionVersion = context?.extensionVersion
        expectedExtensionBuild = context?.extensionBuild
        bridgeProtocolVersion = context.map { _ in
            ClaudeBrowserBridgeContract.schemaVersion
        }
    }

    init(
        trace: ClaudeSafariHostVerificationTrace,
        context: ClaudeBrowserRuntimeContext?
    ) {
        schemaVersion = 2
        status = Self.status(for: trace.verification)
        requestID = trace.requestID
        runtimeGenerationID = trace.runtimeGenerationID
        hostRuntimeGenerationID = trace.runtimeDescriptor?.runtimeGenerationID
        occurredAt = trace.occurredAt
        reachedStages = trace.reachedStages
        firstFailureReason = trace.firstFailureReason
        clientApplicationIdentifier = context.map {
            $0.identity.channel == .productionSafariHost
                ? ClaudeBrowserBridgeContract.safariApplicationIdentifier
                : ClaudeBrowserBridgeContract.safariTestApplicationIdentifier
        }
        clientVersion = context?.appVersion
        clientBuild = context?.appBuild
        hostApplicationIdentifier = trace.runtimeDescriptor?.hostApplicationIdentifier
            ?? context?.identity.containingApplicationIdentifier
        extensionIdentifier = trace.runtimeDescriptor?.extensionIdentifier
            ?? context?.identity.extensionIdentifier
        teamIdentifier = trace.runtimeDescriptor?.teamIdentifier ?? context?.teamIdentifier
        hostVersion = trace.runtimeDescriptor?.hostVersion
        hostBuild = trace.runtimeDescriptor?.hostBuild
        expectedExtensionVersion = context?.extensionVersion
        expectedExtensionBuild = context?.extensionBuild
        bridgeProtocolVersion = trace.runtimeDescriptor?.bridgeProtocolVersion
            ?? context.map { _ in ClaudeBrowserBridgeContract.schemaVersion }
    }

    private static func status(
        for verification: ClaudeBrowserCompanionVerification
    ) -> Status {
        switch verification {
        case .verified: .verified
        case .disabled: .disabled
        case .companionStarting: .starting
        case .protocolMismatch: .protocolMismatch
        case .browserUnavailable: .unavailable
        case .unavailable: .unavailable
        }
    }

    public var processExitCode: Int32 {
        switch status {
        case .verified: 0
        case .disabled: 2
        case .starting: 3
        case .protocolMismatch: 4
        case .unavailable: 5
        }
    }

    public func encodedJSONLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
