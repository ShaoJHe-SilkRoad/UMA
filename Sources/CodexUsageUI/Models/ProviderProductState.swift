import Foundation

/// Stable product identities. They are never account, session, or transport IDs.
public enum ProviderProductID: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case workBuddy
    case antigravity

    public var id: String { rawValue }
    public var settingsProviderID: String {
        switch self {
        case .codex: AgentPreferenceRecord.codexProviderID.rawValue
        case .claude: AgentPreferenceRecord.claudeProviderID.rawValue
        case .workBuddy: AgentPreferenceRecord.workBuddyProviderID.rawValue
        case .antigravity: AgentPreferenceRecord.antigravityProviderID.rawValue
        }
    }
    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .workBuddy: "WorkBuddy"
        case .antigravity: "Google Antigravity"
        }
    }
}

public enum ProviderProductPrecision: Equatable, Sendable {
    case exact, estimated, unavailable
}

public enum ProviderProductFreshness: Equatable, Sendable {
    case fresh, cached, stale, unavailable
}

public enum ProviderProductAvailability: Equatable, Sendable {
    case available, setupRequired, disabled, unavailable, unsupported
}

public enum ProviderProductConnection: Equatable, Sendable {
    case connected, transitional, authenticationRequired, disconnected, unavailable, failed
}

public enum ProviderProductHealth: Equatable, Sendable {
    case healthy, degraded, needsAttention, error
}

public enum ProviderProductAction: Int, CaseIterable, Equatable, Sendable {
    case authenticate, configure, enableMonitoring, accuracySync, retry, refresh, openSettings
}

/// A closed, content-free classification. Connector source strings cannot enter
/// the product model.
public enum ProviderProductSourceSummary: Equatable, Sendable {
    case officialLocal
    case localSmartExact
    case localSmartEstimate
    case accuracySync
    case combinedSanitized
    case authenticatedAccountWeb
    case officialCLI
    case unavailable
}

/// Closed failure taxonomy; paths, payloads, process arguments, and protocol
/// receipts are deliberately not representable.
public enum ProviderProductDiagnosticReason: Equatable, Sendable {
    case authorizationRequired
    case setupRequired
    case sourceUnavailable
    case timedOut
    case unsupported
    case invalidData
    case processUnavailable
    case staleData
    case unknown
}

public enum ProviderProductQuotaValue: Equatable, Sendable {
    case remainingPercent(Double)
    case remainingCredits(Decimal, unit: CreditUnit)
    case unlimited
    case unavailable

    public var remainingPercent: Double? {
        guard case let .remainingPercent(value) = self else { return nil }
        return value
    }

    public var displayText: String {
        switch self {
        case let .remainingPercent(value): "\(Int(value.rounded()))%"
        case let .remainingCredits(value, _): CreditFormatter.compact(value)
        case .unlimited: "∞"
        case .unavailable: "—"
        }
    }
}

public enum ProviderProductComparisonIneligibility: Equatable, Sendable {
    case missing, stale, nativeUnit, unlimited, invalid
}

public enum ProviderProductQuotaComparison: Equatable, Sendable {
    case eligibleRemainingPercent(Double)
    case ineligible(ProviderProductComparisonIneligibility)

    public var eligibleRemainingPercent: Double? {
        guard case let .eligibleRemainingPercent(value) = self else { return nil }
        return value
    }
}

public enum ProviderProductQuotaKind: Hashable, Sendable {
    case fiveHour, sevenDay, other, credits
}

/// Explicit product truth for the short Codex quota window. `absent` means
/// that the admitted snapshot did not report a short window at all; `unknown`
/// means that it reported the window but did not supply a valid finite or
/// unlimited value. Neither state may be promoted to infinity.
public enum ProviderProductFiveHourStatus: Equatable, Sendable {
    case finite, unlimited, unknown, absent
}

public struct ProviderProductQuotaState: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: ProviderProductQuotaKind
    public let compactLabel: String
    public let value: ProviderProductQuotaValue
    public let precision: ProviderProductPrecision
    public let freshness: ProviderProductFreshness
    public let comparison: ProviderProductQuotaComparison
    public let resetsAt: Date?

    init(
        id: String,
        kind: ProviderProductQuotaKind,
        compactLabel: String,
        value: ProviderProductQuotaValue,
        precision: ProviderProductPrecision,
        freshness: ProviderProductFreshness,
        comparison: ProviderProductQuotaComparison,
        resetsAt: Date?
    ) {
        self.id = id
        self.kind = kind
        self.compactLabel = compactLabel
        self.value = value
        self.precision = precision
        self.freshness = freshness
        self.comparison = comparison
        self.resetsAt = resetsAt
    }

    public var displayText: String {
        precision == .estimated && value.remainingPercent != nil
            ? "≈\(value.displayText)"
            : value.displayText
    }
}

public struct ProviderProductInventoryDisposition: Equatable, Sendable {
    public let overview: Bool
    public let providers: Bool
    public let assistant: Bool
    public let quickPanel: Bool
    public let agentWorkspace: Bool

    init(
        overview: Bool,
        providers: Bool = true,
        assistant: Bool,
        quickPanel: Bool = false,
        agentWorkspace: Bool = false
    ) {
        self.overview = overview
        self.providers = providers
        self.assistant = assistant
        self.quickPanel = quickPanel
        self.agentWorkspace = agentWorkspace
    }
}

public struct ProviderProductState: Equatable, Identifiable, Sendable {
    public let id: ProviderProductID
    public let displayName: String
    public let planLabel: String?
    public let quotas: [ProviderProductQuotaState]
    public let primaryQuotaID: String?
    public let precision: ProviderProductPrecision
    public let freshness: ProviderProductFreshness
    public let availability: ProviderProductAvailability
    public let connection: ProviderProductConnection
    public let health: ProviderProductHealth
    public let requiredAction: ProviderProductAction?
    public let actions: [ProviderProductAction]
    public let sourceSummary: ProviderProductSourceSummary
    public let diagnosticReason: ProviderProductDiagnosticReason?
    public let inventory: ProviderProductInventoryDisposition
    public let isActive: Bool
    public let capturedAt: Date?

    init(
        id: ProviderProductID,
        planLabel: String? = nil,
        quotas: [ProviderProductQuotaState] = [],
        primaryQuotaID: String? = nil,
        precision: ProviderProductPrecision = .unavailable,
        freshness: ProviderProductFreshness = .unavailable,
        availability: ProviderProductAvailability,
        connection: ProviderProductConnection,
        health: ProviderProductHealth,
        requiredAction: ProviderProductAction? = nil,
        actions: [ProviderProductAction] = [],
        sourceSummary: ProviderProductSourceSummary = .unavailable,
        diagnosticReason: ProviderProductDiagnosticReason? = nil,
        inventory: ProviderProductInventoryDisposition,
        isActive: Bool,
        capturedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = id.displayName
        self.planLabel = planLabel
        self.quotas = quotas
        self.primaryQuotaID = primaryQuotaID
        self.precision = precision
        self.freshness = freshness
        self.availability = availability
        self.connection = connection
        self.health = health
        self.requiredAction = requiredAction
        self.actions = actions.sorted { $0.rawValue < $1.rawValue }
        self.sourceSummary = sourceSummary
        self.diagnosticReason = diagnosticReason
        self.inventory = inventory
        self.isActive = isActive
        self.capturedAt = capturedAt
    }

    public var primaryQuota: ProviderProductQuotaState? {
        guard let primaryQuotaID else { return nil }
        return quotas.first { $0.id == primaryQuotaID }
    }

    /// Compact surfaces show only qualified values. Unknown windows remain in
    /// `quotas` for optional detail messaging, but cannot appear as a fabricated
    /// percentage or infinity in glance surfaces.
    public var compactQuotas: [ProviderProductQuotaState] {
        quotas.filter { $0.value != .unavailable }
    }

    public var fiveHourStatus: ProviderProductFiveHourStatus {
        let shortWindows = quotas.filter { $0.kind == .fiveHour }
        if shortWindows.contains(where: {
            if case .remainingPercent = $0.value { return true }
            return false
        }) {
            return .finite
        }
        if shortWindows.contains(where: { $0.value == .unlimited }) {
            return .unlimited
        }
        return shortWindows.isEmpty ? .absent : .unknown
    }

    public var primaryDisplayText: String { primaryQuota?.displayText ?? "—" }
    public var primaryAction: ProviderProductAction? { requiredAction ?? actions.first }
}

public enum ProviderProductLimitingFactor: Equatable, Sendable {
    case quota(provider: ProviderProductID, quotaID: String, remainingPercent: Double)
}

public enum ProviderProductAttentionPriority: Equatable, Sendable {
    case actionRequired(provider: ProviderProductID, action: ProviderProductAction)
}

public struct ProviderProductInventory: Equatable, Sendable {
    public let providers: [ProviderProductState]
    public let publicationRevision: UInt64
    public let activeAgentCount: Int
    public let limitingFactor: ProviderProductLimitingFactor?
    public let attentionPriority: ProviderProductAttentionPriority?

    init(
        providers: [ProviderProductState],
        publicationRevision: UInt64 = 0,
        activeAgentCount: Int? = nil
    ) {
        self.providers = providers.sorted { Self.order($0.id) < Self.order($1.id) }
        self.publicationRevision = publicationRevision
        self.activeAgentCount = max(0, activeAgentCount ?? providers.filter(\.isActive).count)
        self.limitingFactor = Self.selectLimitingFactor(from: self.providers)
        self.attentionPriority = Self.selectAttentionPriority(from: self.providers)
    }

    public var overviewProviders: [ProviderProductState] {
        providers.filter(\.inventory.overview)
    }

    public var assistantProviders: [ProviderProductState] {
        providers.filter(\.inventory.assistant)
    }

    public var quickPanelProviders: [ProviderProductState] {
        providers.filter(\.inventory.quickPanel)
    }

    public var agentWorkspaceProviders: [ProviderProductState] {
        providers.filter(\.inventory.agentWorkspace)
    }

    public var usesAutomaticMinimalistMode: Bool { activeAgentCount > 4 }

    public func provider(_ id: ProviderProductID) -> ProviderProductState? {
        providers.first { $0.id == id }
    }

    private static func order(_ id: ProviderProductID) -> Int {
        switch id {
        case .codex: 0
        case .claude: 1
        case .workBuddy: 2
        case .antigravity: 3
        }
    }

    private static func selectLimitingFactor(
        from providers: [ProviderProductState]
    ) -> ProviderProductLimitingFactor? {
        providers.flatMap { provider in
            provider.quotas.compactMap { quota -> (ProviderProductID, String, Double)? in
                guard let value = quota.comparison.eligibleRemainingPercent else { return nil }
                return (provider.id, quota.id, value)
            }
        }
        .sorted {
            if $0.2 != $1.2 { return $0.2 < $1.2 }
            let lhsOrder = order($0.0), rhsOrder = order($1.0)
            return lhsOrder == rhsOrder ? $0.1 < $1.1 : lhsOrder < rhsOrder
        }
        .first
        .map { .quota(provider: $0.0, quotaID: $0.1, remainingPercent: $0.2) }
    }

    private static func selectAttentionPriority(
        from providers: [ProviderProductState]
    ) -> ProviderProductAttentionPriority? {
        for provider in providers {
            if provider.health == .error || provider.health == .needsAttention,
               let action = provider.requiredAction {
                return .actionRequired(provider: provider.id, action: action)
            }
        }
        return nil
    }
}

struct ProviderProductReduction: Equatable, Sendable {
    let inventory: ProviderProductInventory
    let presentationCards: [SharedUsageCardPresentation]
}

/// Strict adapter from sanitized connector snapshots into product truth. It
/// never retains the source snapshot, channel, descriptor, or arbitrary text.
enum ProviderProductStatePolicy {
    private static let currentSupportedProducts: Set<ProviderProductID> = [.codex, .claude]
    private struct CatalogEntry {
        let productID: ProviderProductID
        let connectorID: AgentConnectorID
    }

    private static let catalog = [
        CatalogEntry(productID: .codex, connectorID: CodexUsageConnector.connectorID),
        CatalogEntry(productID: .claude, connectorID: ClaudeCodeUsageConnector.connectorID),
        CatalogEntry(
            productID: .workBuddy,
            connectorID: WorkBuddyAccountWebCreditsConnector.connectorID
        ),
        CatalogEntry(
            productID: .antigravity,
            connectorID: GoogleAntigravityUsageConnector.connectorID
        ),
    ]

    static var catalogConnectorIDs: [AgentConnectorID] {
        catalog.map(\.connectorID)
    }

    static func connectorID(for productID: ProviderProductID) -> AgentConnectorID? {
        catalog.first { $0.productID == productID }?.connectorID
    }

    static func productID(forRawConnectorID rawValue: String) -> ProviderProductID? {
        guard let connectorID = AgentConnectorID(rawValue: rawValue) else { return nil }
        return productID(for: connectorID)
    }

    static func previewInventory(
        cards: [SharedUsageCardPresentation],
        language: AppLanguage
    ) -> ProviderProductInventory {
        _ = language
        let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        return ProviderProductInventory(providers: catalog.map { entry in
            guard let card = cardsByID[entry.connectorID.rawValue] else {
                return ProviderProductState(
                    id: entry.productID,
                    availability: .unavailable,
                    connection: .unavailable,
                    health: .degraded,
                    actions: [.openSettings],
                    inventory: .init(
                        overview: false,
                        providers: false,
                        assistant: false,
                        quickPanel: false,
                        agentWorkspace: false
                    ),
                    isActive: false
                )
            }
            let quotas = makeQuotas(card: card, freshness: .fresh)
            let primaryQuotaID = primaryQuotaID(card: card, quotas: quotas)
            let freshness: ProviderProductFreshness = switch card.freshness {
            case .fresh: .fresh
            case .cached: .cached
            case .stale: .stale
            case .unavailable: .unavailable
            }
            // Preview fixtures must exercise the same visible state language as
            // live product state. A retained stale observation remains a
            // connected source with explicitly stale freshness, matching the
            // production reducer rather than pretending the data is current.
            let connection: ProviderProductConnection = switch card.connectionStatus {
            case .connected: .connected
            case .transitional: .transitional
            case .authenticationRequired: .authenticationRequired
            case .stale: .connected
            case .disconnected: .disconnected
            case .unavailable: .unavailable
            case .failed: .failed
            }
            let health: ProviderProductHealth = switch card.connectionStatus {
            case .failed: .error
            case .authenticationRequired: .needsAttention
            case .stale: .degraded
            default: freshness == .fresh ? .healthy : .degraded
            }
            let isSupported = currentSupportedProducts.contains(entry.productID)
            let hasUsableQuota = quotas.contains { $0.value != .unavailable }
            let isQuickEligible = isSupported && hasUsableQuota && [
                ProviderProductConnection.connected,
                .transitional,
            ].contains(connection)
            return ProviderProductState(
                id: entry.productID,
                planLabel: LowRemainingUsagePolicy.admittedPlanIdentifier(providerID: entry.productID.rawValue, label: card.planLabel),
                quotas: quotas,
                primaryQuotaID: primaryQuotaID,
                precision: quotas.first { $0.id == primaryQuotaID }?.precision ?? .unavailable,
                freshness: freshness,
                availability: .available,
                connection: connection,
                health: health,
                actions: entry.productID == .claude ? [.refresh, .accuracySync] : [.refresh],
                sourceSummary: previewSourceSummary(
                    productID: entry.productID,
                    isEstimated: card.isEstimated == true
                ),
                inventory: .init(
                    overview: true,
                    providers: isSupported,
                    assistant: isQuickEligible && card.isVisibleInDesktopAssistant,
                    quickPanel: isQuickEligible,
                    agentWorkspace: isSupported
                ),
                isActive: isQuickEligible,
                capturedAt: card.capturedAt
            )
        })
    }

    /// Keeps review fixtures semantically coherent without interpreting any
    /// connector-owned source text. Production state still uses the admitted
    /// snapshot provenance and version mapping in `sourceSummary` below.
    private static func previewSourceSummary(
        productID: ProviderProductID,
        isEstimated: Bool
    ) -> ProviderProductSourceSummary {
        switch productID {
        case .codex:
            return .officialLocal
        case .claude:
            return isEstimated ? .localSmartEstimate : .accuracySync
        case .workBuddy:
            return .authenticatedAccountWeb
        case .antigravity:
            return .officialCLI
        }
    }

    static func reduce(
        snapshots: [AgentUsageSnapshot],
        admissions: [ProviderSurfaceAdmissionRecord],
        monitoringEnabledIDs: Set<AgentConnectorID>,
        configuredOrDetectedIDs: Set<AgentConnectorID> = [],
        pendingInitialAdmissionIDs: Set<AgentConnectorID> = [],
        previousCards: [SharedUsageCardPresentation],
        language: AppLanguage,
        publicationRevision: UInt64 = 0,
        activeAgentCount: Int? = nil,
        declaredPlans: [ProviderProductID: String] = [:],
        now: Date = Date()
    ) -> ProviderProductReduction {
        let admittedByID = Dictionary(uniqueKeysWithValues: admissions.map { ($0.id, $0) })
        let snapshotByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: snapshots.filter { monitoringEnabledIDs.contains($0.id) },
            previousCards: previousCards,
            language: language,
            now: now
        )
        let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let states = catalog.map { entry in
            makeState(
                entry: entry,
                snapshot: snapshotByID[entry.connectorID],
                admission: admittedByID[entry.connectorID]?.admission,
                admissionFailure: admittedByID[entry.connectorID]?.safeFailure,
                monitoringEnabled: monitoringEnabledIDs.contains(entry.connectorID),
                configuredOrDetected: configuredOrDetectedIDs.contains(entry.connectorID),
                pendingInitialAdmission: pendingInitialAdmissionIDs.contains(
                    entry.connectorID
                ),
                card: cardsByID[entry.connectorID.rawValue],
                declaredPlan: declaredPlans[entry.productID]
            )
        }
        return ProviderProductReduction(
            inventory: ProviderProductInventory(
                providers: states,
                publicationRevision: publicationRevision,
                activeAgentCount: activeAgentCount
            ),
            presentationCards: cards
        )
    }

    static func productID(for connectorID: AgentConnectorID) -> ProviderProductID? {
        catalog.first { $0.connectorID == connectorID }?.productID
    }

    private static func makeState(
        entry: CatalogEntry,
        snapshot: AgentUsageSnapshot?,
        admission: ProviderSurfaceAdmission?,
        admissionFailure: AgentSafeFailure?,
        monitoringEnabled: Bool,
        configuredOrDetected: Bool,
        pendingInitialAdmission: Bool,
        card: SharedUsageCardPresentation?,
        declaredPlan: String? = nil
    ) -> ProviderProductState {
        let freshness = freshness(snapshot?.freshness)
        let quotas = makeQuotas(
            card: card,
            freshness: freshness,
            snapshot: snapshot
        )
        let sourceSummary = sourceSummary(productID: entry.productID, snapshot: snapshot)
        let hasQualifiedClaudeLocalSmartUsage = entry.productID == .claude
            && [.localSmartExact, .localSmartEstimate].contains(sourceSummary)
            && quotas.contains { $0.value != .unavailable }
        let availability = availability(
            snapshot: snapshot,
            admission: admission,
            monitoringEnabled: monitoringEnabled,
            hasQualifiedClaudeLocalSmartUsage: hasQualifiedClaudeLocalSmartUsage
        )
        // Consent-granted startup is a real in-flight state, not a terminal
        // source failure. Keep quota/source fields unavailable until the first
        // admission completes; an actual admission result always wins.
        let isAwaitingFirstAdmission = pendingInitialAdmission
            && monitoringEnabled
            && snapshot == nil
            && admission == nil
        let connection = isAwaitingFirstAdmission
            ? ProviderProductConnection.transitional
            : connection(snapshot?.state, availability: availability)
        let health = health(
            snapshot: snapshot,
            availability: availability,
            freshness: freshness
        )
        let actions = actions(
            productID: entry.productID,
            availability: availability,
            health: health
        )
        let primaryQuotaID = primaryQuotaID(card: card, quotas: quotas)
        let precision = quotas.first { $0.id == primaryQuotaID }?.precision ?? .unavailable
        let isActive = monitoringEnabled && [
            ProviderProductConnection.connected,
            .transitional,
        ].contains(connection)
        let actionRequired = health == .error || health == .needsAttention
        let isSupported = currentSupportedProducts.contains(entry.productID)
        let hasUsableQuota = quotas.contains { $0.value != .unavailable }
        let retainedUsableState = hasUsableQuota && [
            ProviderProductConnection.connected,
            .transitional,
        ].contains(connection)
        let overview = isSupported && monitoringEnabled && (
            isActive || configuredOrDetected || retainedUsableState || actionRequired
        )
        let quickPanel = isSupported && monitoringEnabled && retainedUsableState
        let agentWorkspace = isSupported && monitoringEnabled && (
            entry.productID == .codex
                || entry.productID == .claude
                || retainedUsableState || configuredOrDetected || actionRequired
        )

        return ProviderProductState(
            id: entry.productID,
            // A provider-reported plan always wins. The declared plan is only a
            // fallback for providers that report none, and it is still filtered
            // through the policy allowlist rather than trusted as typed.
            planLabel: LowRemainingUsagePolicy.admittedPlanIdentifier(
                providerID: entry.productID.rawValue,
                label: card?.planLabel ?? declaredPlan
            ),
            quotas: quotas,
            primaryQuotaID: primaryQuotaID,
            precision: precision,
            freshness: freshness,
            availability: availability,
            connection: connection,
            health: health,
            requiredAction: requiredAction(
                availability: availability,
                health: health
            ),
            actions: actions,
            sourceSummary: sourceSummary,
            diagnosticReason: diagnosticReason(
                snapshot: snapshot,
                admissionFailure: admissionFailure,
                admission: admission,
                availability: availability,
                hasQualifiedClaudeLocalSmartUsage: hasQualifiedClaudeLocalSmartUsage
            ),
            inventory: ProviderProductInventoryDisposition(
                overview: overview,
                providers: agentWorkspace,
                // The Desktop Assistant stays on screen, so an agent must not
                // vanish from it when its reading lapses: Claude's exact value
                // is dropped after 30 minutes without a sync, and the card
                // went with it. It keeps the overview's agents and shows "—"
                // with its status until a reading returns.
                assistant: overview,
                quickPanel: quickPanel,
                agentWorkspace: agentWorkspace
            ),
            isActive: isActive,
            // A publication can contain retained account data or a local-only
            // update. The product labels this date Last successful update.
            capturedAt: snapshot?.channels.first(where: { $0.id == .account })?.capturedAt
                ?? snapshot?.lastSuccessfulAt
        )
    }

    private static func makeQuotas(
        card: SharedUsageCardPresentation?,
        freshness: ProviderProductFreshness,
        snapshot: AgentUsageSnapshot? = nil
    ) -> [ProviderProductQuotaState] {
        if let sourceQuotas = makeCodexSourceQuotas(
            snapshot: snapshot,
            freshness: freshness
        ) {
            return sourceQuotas.sorted(by: quotaPrecedes)
        }
        guard let card else { return [] }
        var counts: [ProviderProductQuotaKind: Int] = [:]
        var quotas = card.windows.compactMap { window -> ProviderProductQuotaState? in
            // Older Codex connector code manufactured this sentinel from the
            // mere presence of a weekly window. It is not provider evidence of
            // unlimited five-hour usage, so the product boundary must reject
            // it. A real, explicitly unlimited provider window keeps its own
            // stable identifier and passes through normally.
            if snapshot?.id == CodexUsageConnector.connectorID,
               window.kind == .fiveHour,
               window.remaining == .unlimited,
               window.id == "five-hour-unlimited" {
                return nil
            }
            let kind: ProviderProductQuotaKind = switch window.kind {
            case .fiveHour: .fiveHour
            case .sevenDay: .sevenDay
            case .other: .other
            }
            let index = counts[kind, default: 0]
            counts[kind] = index + 1
            let value = quotaValue(window.remaining)
            let precision: ProviderProductPrecision = window.isEstimated == true
                ? .estimated
                : value == .unavailable ? .unavailable : .exact
            return ProviderProductQuotaState(
                id: "\(stableName(kind))-\(index)",
                kind: kind,
                compactLabel: compactLabel(kind),
                value: value,
                precision: precision,
                freshness: freshness,
                comparison: comparison(value, freshness: freshness),
                resetsAt: window.resetsAt
            )
        }

        if quotas.isEmpty, let availability = card.availability {
            let value: ProviderProductQuotaValue = switch availability.value {
            case let .percentage(percentage): .remainingPercent(percentage.value)
            case let .credits(balance): .remainingCredits(balance.remaining, unit: balance.unit)
            case .unlimited: .unlimited
            case .unavailable, .invalid: .unavailable
            }
            let creditComparison: ProviderProductQuotaComparison
            if freshness == .stale || freshness == .unavailable {
                creditComparison = .ineligible(.stale)
            } else if case .remainingCredits = value {
                // Credits remain native provider balances even when a source
                // supplies a denominator. They never participate in limiting
                // order with percentage quota windows.
                creditComparison = .ineligible(.nativeUnit)
            } else {
                creditComparison = comparison(value, freshness: freshness)
            }
            quotas = [
                ProviderProductQuotaState(
                    id: "credits-0",
                    kind: .credits,
                    compactLabel: "Credits",
                    value: value,
                    precision: value == .unavailable ? .unavailable : .exact,
                    freshness: freshness,
                    comparison: creditComparison,
                    resetsAt: availability.nextExpiryAt
                )
            ]
        }
        return quotas.sorted(by: quotaPrecedes)
    }

    /// Codex quota truth is derived from the admitted typed account channel,
    /// one window at a time. This deliberately does not require every sibling
    /// window to be valid: an unknown 5H value must not hide an independently
    /// valid 7D value. Other providers continue through the shared card path.
    private static func makeCodexSourceQuotas(
        snapshot: AgentUsageSnapshot?,
        freshness: ProviderProductFreshness
    ) -> [ProviderProductQuotaState]? {
        guard let snapshot,
              snapshot.id == CodexUsageConnector.connectorID,
              let account = snapshot.channels.first(where: { $0.id == .account }),
              account.provenance == .providerReported,
              account.sourceTier == .officialLocalService,
              !account.rateLimitWindows.isEmpty
        else { return nil }

        var counts: [ProviderProductQuotaKind: Int] = [:]
        return account.rateLimitWindows.compactMap { window in
            // This identifier is created by the legacy connector when no 5H
            // window was reported. It represents absence, not provider-declared
            // infinity, and therefore cannot cross the product-truth boundary.
            if window.kind == .fiveHour,
               window.isUnlimited,
               window.id == "five-hour-unlimited" {
                return nil
            }

            let kind: ProviderProductQuotaKind = switch window.kind {
            case .fiveHour: .fiveHour
            case .sevenDay: .sevenDay
            case .other: .other
            }
            let index = counts[kind, default: 0]
            counts[kind] = index + 1
            let value: ProviderProductQuotaValue
            if window.isUnlimited {
                value = .unlimited
            } else if let remaining = window.normalizedRemainingPercent {
                value = .remainingPercent(remaining)
            } else {
                value = .unavailable
            }
            let precision: ProviderProductPrecision = window.isEstimated == true
                ? .estimated
                : value == .unavailable ? .unavailable : .exact
            let unavailableReason: ProviderProductComparisonIneligibility =
                window.usedPercent == nil && window.remainingPercent == nil
                    ? .missing
                    : .invalid
            return ProviderProductQuotaState(
                id: "\(stableName(kind))-\(index)",
                kind: kind,
                compactLabel: compactLabel(kind),
                value: value,
                precision: precision,
                freshness: freshness,
                comparison: comparison(
                    value,
                    freshness: freshness,
                    unavailableReason: unavailableReason
                ),
                resetsAt: window.resetsAt
            )
        }
    }

    private static func primaryQuotaID(
        card: SharedUsageCardPresentation?,
        quotas: [ProviderProductQuotaState]
    ) -> String? {
        guard !quotas.isEmpty else { return nil }
        guard let selectedID = card?.selectedWindowID,
              let selected = card?.windows.first(where: { $0.id == selectedID })
        else { return quotas.first?.id }
        let kind: ProviderProductQuotaKind = switch selected.kind {
        case .fiveHour: .fiveHour
        case .sevenDay: .sevenDay
        case .other: .other
        }
        let siblings = card?.windows.filter { $0.kind == selected.kind } ?? []
        let candidate = "\(stableName(kind))-\(siblings.firstIndex { $0.id == selected.id } ?? 0)"
        return quotas.contains(where: { $0.id == candidate }) ? candidate : quotas.first?.id
    }

    /// Finite percentage windows are actionable and lead. A lower remaining
    /// value leads another finite value; otherwise the weekly window wins a
    /// deterministic tie. Explicit infinity is secondary, and unknown detail
    /// rows are last. Native credit values never compare numerically with
    /// percentages.
    private static func quotaPrecedes(
        _ lhs: ProviderProductQuotaState,
        _ rhs: ProviderProductQuotaState
    ) -> Bool {
        let valueRank: (ProviderProductQuotaState) -> Int = { quota in
            switch (quota.kind, quota.value) {
            case (.fiveHour, .remainingPercent), (.sevenDay, .remainingPercent): 0
            case (.other, .remainingPercent): 1
            case (_, .remainingCredits): 2
            case (_, .unlimited): 3
            case (_, .unavailable), (_, .remainingPercent): 4
            }
        }
        let lhsRank = valueRank(lhs)
        let rhsRank = valueRank(rhs)
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        if case let .remainingPercent(lhsValue) = lhs.value,
           case let .remainingPercent(rhsValue) = rhs.value,
           lhsValue != rhsValue {
            return lhsValue < rhsValue
        }

        let kindRank: (ProviderProductQuotaKind) -> Int = { kind in
            switch kind {
            case .sevenDay: 0
            case .fiveHour: 1
            case .other: 2
            case .credits: 3
            }
        }
        let lhsKindRank = kindRank(lhs.kind)
        let rhsKindRank = kindRank(rhs.kind)
        return lhsKindRank == rhsKindRank ? lhs.id < rhs.id : lhsKindRank < rhsKindRank
    }

    private static func stableName(_ kind: ProviderProductQuotaKind) -> String {
        return switch kind {
        case .fiveHour: "five-hour"
        case .sevenDay: "seven-day"
        case .other: "other"
        case .credits: "credits"
        }
    }

    private static func compactLabel(_ kind: ProviderProductQuotaKind) -> String {
        return switch kind {
        case .fiveHour: "5H"
        case .sevenDay: "7D"
        case .credits: "Credits"
        case .other: "Other"
        }
    }

    private static func quotaValue(_ value: SharedRemainingValue) -> ProviderProductQuotaValue {
        switch value {
        case let .finite(percent) where percent.isFinite && (0...100).contains(percent):
            .remainingPercent(percent)
        case .unlimited: .unlimited
        case .finite, .unavailable: .unavailable
        }
    }

    private static func comparison(
        _ value: ProviderProductQuotaValue,
        freshness: ProviderProductFreshness,
        unavailableReason: ProviderProductComparisonIneligibility = .invalid
    ) -> ProviderProductQuotaComparison {
        if freshness == .stale || freshness == .unavailable { return .ineligible(.stale) }
        switch value {
        case let .remainingPercent(percent) where percent.isFinite && (0...100).contains(percent):
            return .eligibleRemainingPercent(percent)
        case .remainingCredits: return .ineligible(.nativeUnit)
        case .unlimited: return .ineligible(.unlimited)
        case .remainingPercent: return .ineligible(.invalid)
        case .unavailable: return .ineligible(unavailableReason)
        }
    }

    private static func availability(
        snapshot: AgentUsageSnapshot?,
        admission: ProviderSurfaceAdmission?,
        monitoringEnabled: Bool,
        hasQualifiedClaudeLocalSmartUsage: Bool
    ) -> ProviderProductAvailability {
        guard monitoringEnabled else { return .disabled }
        // Claude Local Smart and Safari Accuracy are independent channels. A
        // qualified local quota remains available when the browser channel is
        // unauthenticated or otherwise unavailable; the workspace reports the
        // browser condition separately instead of erasing usable local truth.
        if hasQualifiedClaudeLocalSmartUsage { return .available }
        switch admission {
        case .hiddenNotAuthenticated: return .setupRequired
        case .hiddenUnsupported: return .unsupported
        case .hiddenNotRunning, .hiddenNoAdmittedLocalSource, .hiddenCurrentReadFailed:
            return .unavailable
        case .admitted: return .available
        case nil: break
        }
        return switch snapshot?.state {
        case .ready, .stale: .available
        case .authenticationRequired: .setupRequired
        case .unsupported: .unsupported
        case .inactive, .waitingForFirstResponse, .failed, nil: .unavailable
        }
    }

    private static func connection(
        _ state: AgentConnectorState?,
        availability: ProviderProductAvailability
    ) -> ProviderProductConnection {
        if availability == .disabled { return .disconnected }
        if availability == .setupRequired { return .authenticationRequired }
        return switch state {
        case .ready, .stale: .connected
        case .waitingForFirstResponse: .transitional
        case .authenticationRequired: .authenticationRequired
        case .inactive: .disconnected
        case .unsupported, nil: .unavailable
        case .failed: .failed
        }
    }

    private static func freshness(_ value: AgentConnectorFreshness?) -> ProviderProductFreshness {
        switch value {
        case .fresh: .fresh
        case .cached: .cached
        case .stale: .stale
        case .unavailable, nil: .unavailable
        }
    }

    private static func health(
        snapshot: AgentUsageSnapshot?,
        availability: ProviderProductAvailability,
        freshness: ProviderProductFreshness
    ) -> ProviderProductHealth {
        if snapshot?.state == .failed { return .error }
        if availability == .setupRequired { return .needsAttention }
        if availability == .unsupported || availability == .disabled { return .degraded }
        if freshness == .stale || freshness == .cached || availability == .unavailable {
            return .degraded
        }
        return snapshot?.state == .ready ? .healthy : .degraded
    }

    private static func actions(
        productID: ProviderProductID,
        availability: ProviderProductAvailability,
        health: ProviderProductHealth
    ) -> [ProviderProductAction] {
        switch availability {
        case .setupRequired: return [.authenticate, .openSettings]
        case .disabled: return [.enableMonitoring]
        case .unsupported: return []
        case .unavailable: return [.retry, .openSettings]
        case .available:
            var result: [ProviderProductAction] = [.refresh]
            if productID == .claude { result.append(.accuracySync) }
            if health == .error { result.append(.retry) }
            return result
        }
    }

    private static func requiredAction(
        availability: ProviderProductAvailability,
        health: ProviderProductHealth
    ) -> ProviderProductAction? {
        switch availability {
        case .setupRequired: return .authenticate
        case .disabled: return nil
        case .unavailable where health == .error: return .retry
        case .available where health == .error: return .retry
        case .available, .unavailable, .unsupported: return nil
        }
    }

    private static func sourceSummary(
        productID: ProviderProductID,
        snapshot: AgentUsageSnapshot?
    ) -> ProviderProductSourceSummary {
        guard let account = snapshot?.channels.first(where: { $0.id == .account }) else {
            return .unavailable
        }
        switch productID {
        case .codex: return .officialLocal
        case .workBuddy: return .authenticatedAccountWeb
        case .antigravity: return .officialCLI
        case .claude:
            switch account.sourceVersion {
            case "smart-1-local-exact": return .localSmartExact
            case "smart-1-desktop-estimate", "smart-1-local-estimate":
                return .localSmartEstimate
            case "smart-1-safari-exact": return .accuracySync
            case "smart-1-mixed", "smart-1-stale": return .combinedSanitized
            default:
                return account.provenance == .locallyEstimated
                    ? .localSmartEstimate
                    : .combinedSanitized
            }
        }
    }

    private static func diagnosticReason(
        snapshot: AgentUsageSnapshot?,
        admissionFailure: AgentSafeFailure?,
        admission: ProviderSurfaceAdmission?,
        availability: ProviderProductAvailability,
        hasQualifiedClaudeLocalSmartUsage: Bool
    ) -> ProviderProductDiagnosticReason? {
        if availability == .disabled { return nil }
        if let failure = admissionFailure ?? snapshot?.safeFailure {
            switch failure {
            case .authorizationRequired: return .authorizationRequired
            case .unavailable: return .sourceUnavailable
            case .timedOut: return .timedOut
            case .unsupported: return .unsupported
            case .malformedResponse: return .invalidData
            case .processExited: return .processUnavailable
            case .unknown: return .unknown
            }
        }
        if !hasQualifiedClaudeLocalSmartUsage {
            switch admission {
            case .hiddenNotAuthenticated: return .setupRequired
            case .hiddenNotRunning: return .processUnavailable
            case .hiddenNoAdmittedLocalSource, .hiddenCurrentReadFailed: return .sourceUnavailable
            case .hiddenUnsupported: return .unsupported
            case .admitted, nil: break
            }
        }
        switch snapshot?.safeFailure {
        case .authorizationRequired: return .authorizationRequired
        case .unavailable: return .sourceUnavailable
        case .timedOut: return .timedOut
        case .unsupported: return .unsupported
        case .malformedResponse: return .invalidData
        case .processExited: return .processUnavailable
        case .unknown: return .unknown
        case nil: return snapshot?.freshness == .stale ? .staleData : nil
        }
    }

}
