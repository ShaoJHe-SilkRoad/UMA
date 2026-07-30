import Foundation

/// Stable, provider-neutral identifier. It is intentionally not an account or
/// device identity and is safe to use as a persistence key.
struct AgentConnectorID: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    let rawValue: String

    init?(rawValue: String) {
        guard rawValue.range(
            of: "^[a-z][a-z0-9]*(?:[.-][A-Za-z][A-Za-z0-9]*)*$",
            options: .regularExpression
        ) != nil else {
            return nil
        }
        self.rawValue = rawValue
    }

    init?(_ rawValue: String) { self.init(rawValue: rawValue) }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Stable product ordering keyed only by provider identity. Missing providers
/// do not create placeholders, and runtime state can never move a row.
enum AgentProviderOrder {
    private static let fallbackPriority = 1_000

    static func priority(for id: AgentConnectorID) -> Int {
        let providerNamespace = id.rawValue.split(
            separator: ".",
            maxSplits: 1
        ).first.map(String.init) ?? id.rawValue
        return switch providerNamespace {
        case "codex": 0
        case "claude": 100
        case "workbuddy": 200
        case "manus": 300
        case "cursor": 400
        case "kimi": 500
        case "doubao": 600
        default: fallbackPriority
        }
    }

    static func precedes(_ lhs: AgentConnectorID, _ rhs: AgentConnectorID) -> Bool {
        let lhsPriority = priority(for: lhs)
        let rhsPriority = priority(for: rhs)
        return lhsPriority == rhsPriority ? lhs < rhs : lhsPriority < rhsPriority
    }

    static func precedes(raw lhs: String, _ rhs: String) -> Bool {
        guard let lhsID = AgentConnectorID(rawValue: lhs),
              let rhsID = AgentConnectorID(rawValue: rhs) else {
            return lhs < rhs
        }
        return precedes(lhsID, rhsID)
    }
}

enum AgentSourceTier: String, Codable, CaseIterable, Sendable {
    case officialLocalService = "A"
    case officialStructuredHook = "B"
    case officialCLIOrMetadata = "C"
    case authorizedReadOnlyRemote = "R"
    case manualUserConfirmed = "M"
    case unsupported = "U"

    var isAdmissible: Bool { self != .unsupported }
}

/// Surface admission is intentionally stricter than the historical source
/// tier. A source can remain supported for persistence or Settings while being
/// ineligible for production provider surfaces.
enum ProviderLocalSourceClass: String, Codable, Sendable {
    case admittedStructuredLocal
    case authenticatedAccountWeb
    case manualOnly
    case unsupported
}

enum ProviderRuntimeRequirement: String, Codable, Sendable {
    case activeOfficialApplicationCLIOrService
    case none
}

enum ProviderAuthenticationMethod: String, Codable, Sendable {
    case existingLocalSession
    case officialApplicationOwnedSession
    case umaOwnedAuthenticatedAccountWebSession
    case none
}

enum ProviderUsageReadContract: String, Codable, Sendable {
    case currentStructuredLocalRead
    case currentAuthenticatedAccountWebRead
    case none
}

enum ProviderLoginAssistance: String, Codable, Sendable {
    case none
    case existingSessionOnly
    case userInitiatedOfficialChineseAppLogin
}

enum AgentMetricScope: String, Codable, CaseIterable, Hashable, Sendable {
    case account
    case device
    case session
    case task
}

enum AgentMetricProvenance: String, Codable, Sendable {
    case providerReported
    case locallyEstimated
    case manualConfirmed
}

enum AgentConnectorFreshness: String, Codable, Sendable {
    case fresh
    case cached
    case stale
    case unavailable
}

enum AgentConnectorState: String, Codable, Sendable {
    case inactive
    case authenticationRequired
    case waitingForFirstResponse
    case ready
    case stale
    case unsupported
    case failed
}

enum AgentConnectorCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case connect
    case reconnect
    case refresh
    case disconnect
    case localActivity
    case rateLimits
    case accountUsage
    case passiveLocalAvailability
    case sanitizedLastValidRestore
    case hiddenFromProviderSurfaces
    case hiddenFromDesktopAssistant
}

/// Declarative, privacy-safe prerequisites.  Deliberately no free-form
/// credential, cookie, filesystem-path, or automation requirement exists.
enum AgentConnectorConfigurationRequirement: String, Codable, CaseIterable, Hashable, Sendable {
    case userAuthorization
    case officialManagedSession
    case privacySafeLocalMetadataAccess
    case explicitlyAuthorizedReadOnlyRemoteAccess
}

enum AgentConnectorCommand: String, Codable, Sendable {
    case connect
    case reconnect
    case refresh
    case disconnect
}

enum AgentSafeFailure: String, Codable, Sendable {
    case authorizationRequired
    case unavailable
    case timedOut
    case unsupported
    case malformedResponse
    case processExited
    case unknown
}

struct AgentConnectorDescriptor: Codable, Sendable, Equatable {
    let id: AgentConnectorID
    let providerName: String
    let officialSource: String
    let sourceTier: AgentSourceTier
    let sourceVersion: String
    let supportedScopes: Set<AgentMetricScope>
    let capabilities: Set<AgentConnectorCapability>
    let configurationRequirements: Set<AgentConnectorConfigurationRequirement>
    let privacyAllowlist: Set<String>
    let supportsRestore: Bool
    let supportsUninstall: Bool
    let unsupportedFields: Set<String>
    let providerPriority: Int
    let expectedRuntime: ProviderRuntimeRequirement
    let localSourceClass: ProviderLocalSourceClass
    let authenticationMethod: ProviderAuthenticationMethod
    let usageReadContract: ProviderUsageReadContract
    let loginAssistance: ProviderLoginAssistance
    let isRegisteredChineseAgent: Bool
    let officialLoginApplicationURL: URL?

    init?(
        id: AgentConnectorID,
        providerName: String,
        officialSource: String,
        sourceTier: AgentSourceTier,
        sourceVersion: String,
        supportedScopes: Set<AgentMetricScope>,
        capabilities: Set<AgentConnectorCapability>,
        configurationRequirements: Set<AgentConnectorConfigurationRequirement>,
        privacyAllowlist: Set<String>,
        supportsRestore: Bool,
        supportsUninstall: Bool,
        unsupportedFields: Set<String>,
        providerPriority: Int? = nil,
        expectedRuntime: ProviderRuntimeRequirement = .activeOfficialApplicationCLIOrService,
        localSourceClass: ProviderLocalSourceClass? = nil,
        authenticationMethod: ProviderAuthenticationMethod = .existingLocalSession,
        usageReadContract: ProviderUsageReadContract? = nil,
        loginAssistance: ProviderLoginAssistance = .existingSessionOnly,
        isRegisteredChineseAgent: Bool = false,
        officialLoginApplicationURL: URL? = nil
    ) {
        let resolvedLocalSourceClass = localSourceClass
            ?? Self.defaultLocalSourceClass(for: sourceTier)
        guard sourceTier.isAdmissible,
              !providerName.isEmpty,
              !officialSource.isEmpty,
              !sourceVersion.isEmpty,
              !supportedScopes.isEmpty,
              loginAssistance != .userInitiatedOfficialChineseAppLogin
                || (
                    isRegisteredChineseAgent
                        && officialLoginApplicationURL != nil
                        && resolvedLocalSourceClass == .admittedStructuredLocal
                )
        else { return nil }
        self.id = id
        self.providerName = providerName
        self.officialSource = officialSource
        self.sourceTier = sourceTier
        self.sourceVersion = sourceVersion
        self.supportedScopes = supportedScopes
        self.capabilities = capabilities
        self.configurationRequirements = configurationRequirements
        self.privacyAllowlist = privacyAllowlist
        self.supportsRestore = supportsRestore
        self.supportsUninstall = supportsUninstall
        self.unsupportedFields = unsupportedFields
        self.providerPriority = providerPriority ?? AgentProviderOrder.priority(for: id)
        self.expectedRuntime = expectedRuntime
        self.localSourceClass = resolvedLocalSourceClass
        self.authenticationMethod = authenticationMethod
        let resolvedUsageReadContract: ProviderUsageReadContract
        if let usageReadContract {
            resolvedUsageReadContract = usageReadContract
        } else {
            resolvedUsageReadContract = switch resolvedLocalSourceClass {
            case .admittedStructuredLocal:
                .currentStructuredLocalRead
            case .authenticatedAccountWeb:
                .currentAuthenticatedAccountWebRead
            case .manualOnly, .unsupported:
                .none
            }
        }
        self.usageReadContract = resolvedUsageReadContract
        self.loginAssistance = loginAssistance
        self.isRegisteredChineseAgent = isRegisteredChineseAgent
        self.officialLoginApplicationURL = officialLoginApplicationURL
    }

    private static func defaultLocalSourceClass(
        for sourceTier: AgentSourceTier
    ) -> ProviderLocalSourceClass {
        switch sourceTier {
        case .officialLocalService, .officialStructuredHook, .officialCLIOrMetadata:
            .admittedStructuredLocal
        case .manualUserConfirmed:
            .manualOnly
        case .authorizedReadOnlyRemote, .unsupported:
            .unsupported
        }
    }
}

struct AgentConnectorProbe: Sendable, Equatable {
    let state: AgentConnectorState
    let safeFailure: AgentSafeFailure?
}

struct AgentRateLimitWindow: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case fiveHour
        case sevenDay
        case other
    }

    let id: String
    let kind: Kind
    let usedPercent: Double?
    /// A normalized provider value restored from UMA's sanitized last-valid
    /// cache. Live providers continue to publish `usedPercent`; exactly one of
    /// these percentage fields may be populated.
    let remainingPercent: Double?
    let isUnlimited: Bool
    let resetsAt: Date?

    init(
        id: String,
        kind: Kind,
        usedPercent: Double?,
        remainingPercent: Double? = nil,
        isUnlimited: Bool,
        resetsAt: Date?
    ) {
        self.id = id
        self.kind = kind
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.isUnlimited = isUnlimited
        self.resetsAt = resetsAt
    }

    /// One normalization owner for both live presentation and sanitized
    /// persistence. Restored remaining values are returned directly and are
    /// never converted a second time.
    var normalizedRemainingPercent: Double? {
        if let remainingPercent,
           remainingPercent.isFinite,
           (0...100).contains(remainingPercent),
           usedPercent == nil {
            return remainingPercent
        }
        if let usedPercent,
           usedPercent.isFinite,
           (0...100).contains(usedPercent),
           remainingPercent == nil {
            return 100 - usedPercent
        }
        return nil
    }
}

struct AgentAccountMetrics: Codable, Sendable, Equatable {
    let planLabel: String?
    let availableResets: Int?
    let lifetimeTokens: Int64?
    let sevenDayTokens: Int64?
}

struct AgentLocalActivityMetrics: Codable, Sendable, Equatable {
    let recentTaskCount: Int?
    /// Runtime-only aggregate task values. The persistence allowlist omits
    /// these timestamps and per-task values entirely.
    let recentTaskTokens: [Int64]
    let recentTaskCapturedAt: [Date]
    let sessionTokens: Int64?
    let estimatedSevenDayUSD: Double?
    let estimatedLifetimeUSD: Double?
    let coveragePercent: Int?
    let recognizedModelCount: Int?
}

struct AgentUsageChannel: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Codable, Sendable { case account, localActivity }

    let id: Kind
    let sourceTier: AgentSourceTier
    let sourceVersion: String
    let scopes: Set<AgentMetricScope>
    let provenance: AgentMetricProvenance
    let freshness: AgentConnectorFreshness
    let capturedAt: Date?
    let coverageNote: String?
    let rateLimitWindows: [AgentRateLimitWindow]
    let accountMetrics: AgentAccountMetrics?
    let localActivityMetrics: AgentLocalActivityMetrics?
    let safeFailure: AgentSafeFailure?
    /// Optional provider-neutral availability. Existing percentage-based
    /// connectors continue to publish rate-limit windows unchanged.
    let availability: AgentAvailabilityValue?
    /// Sanitized WorkBuddy account-pool reconciliation. It is runtime-only:
    /// the connector snapshot store intentionally omits it.
    let accountCreditSnapshot: WorkBuddyAccountCreditSnapshot?

    var availabilitySourceState: AgentAvailabilitySourceState {
        availability?.sourceState ?? .unspecified
    }

    init(
        id: Kind,
        sourceTier: AgentSourceTier,
        sourceVersion: String,
        scopes: Set<AgentMetricScope>,
        provenance: AgentMetricProvenance,
        freshness: AgentConnectorFreshness,
        capturedAt: Date?,
        coverageNote: String?,
        rateLimitWindows: [AgentRateLimitWindow],
        accountMetrics: AgentAccountMetrics?,
        localActivityMetrics: AgentLocalActivityMetrics?,
        safeFailure: AgentSafeFailure?,
        availability: AgentAvailabilityValue? = nil,
        accountCreditSnapshot: WorkBuddyAccountCreditSnapshot? = nil
    ) {
        self.id = id
        self.sourceTier = sourceTier
        self.sourceVersion = sourceVersion
        self.scopes = scopes
        self.provenance = provenance
        self.freshness = freshness
        self.capturedAt = capturedAt
        self.coverageNote = coverageNote
        self.rateLimitWindows = rateLimitWindows
        self.accountMetrics = accountMetrics
        self.localActivityMetrics = localActivityMetrics
        self.safeFailure = safeFailure
        self.availability = availability
        self.accountCreditSnapshot = accountCreditSnapshot
    }
}

/// The core snapshot deliberately contains aggregates and typed availability
/// only. It has no account identity, local paths, task names, raw payload, or
/// provider transport fields.
struct AgentUsageSnapshot: Codable, Sendable, Equatable, Identifiable {
    let id: AgentConnectorID
    let providerName: String
    let state: AgentConnectorState
    let capturedAt: Date
    let lastSuccessfulAt: Date?
    let freshness: AgentConnectorFreshness
    let channels: [AgentUsageChannel]
    let capabilities: Set<AgentConnectorCapability>
    let safeFailure: AgentSafeFailure?
    /// Stable presentation hint used only when a sanitized last-valid
    /// snapshot is restored before any current-process provider event.
    let selectedWindowID: String?

    init(
        id: AgentConnectorID,
        providerName: String,
        state: AgentConnectorState,
        capturedAt: Date,
        lastSuccessfulAt: Date?,
        freshness: AgentConnectorFreshness,
        channels: [AgentUsageChannel],
        capabilities: Set<AgentConnectorCapability>,
        safeFailure: AgentSafeFailure?,
        selectedWindowID: String? = nil
    ) {
        self.id = id
        self.providerName = providerName
        self.state = state
        self.capturedAt = capturedAt
        self.lastSuccessfulAt = lastSuccessfulAt
        self.freshness = freshness
        self.channels = channels
        self.capabilities = capabilities
        self.safeFailure = safeFailure
        self.selectedWindowID = selectedWindowID
    }

    var hasValidData: Bool {
        channels.contains {
            $0.freshness == .fresh
                || $0.freshness == .cached
                || $0.freshness == .stale
        }
    }
}

/// Connectors own transport, process, and cleanup. The registry only routes
/// lifecycle commands and consumes their streams; it never polls providers.
protocol AgentUsageConnector: Sendable {
    var id: AgentConnectorID { get }
    var descriptor: AgentConnectorDescriptor { get }
    func permitsRead(for trigger: ProviderEligibilityScanTrigger) async -> Bool
    func probe() async -> AgentConnectorProbe
    func start() async
    func refresh() async
    func refresh(trigger: CodexRefreshTrigger) async
    func perform(_ command: AgentConnectorCommand) async
    func stop() async
    func currentSnapshot() async -> AgentUsageSnapshot
    func snapshots() async -> AsyncStream<AgentUsageSnapshot>
}

extension AgentUsageConnector {
    func permitsRead(for trigger: ProviderEligibilityScanTrigger) async -> Bool {
        true
    }

    /// Existing adapters retain their one refresh implementation until they
    /// opt into source-aware trigger attribution.
    func refresh(trigger: CodexRefreshTrigger) async {
        await refresh()
    }
}
