import Foundation

public enum SharedConnectionStatus: String, Codable, Sendable {
    case connected
    case transitional
    case authenticationRequired
    case stale
    case disconnected
    case unavailable
    case failed

    public var isHealthy: Bool { self == .connected }
}

public enum SharedUsageFreshness: String, Codable, Sendable {
    case fresh
    case cached
    case stale
    case unavailable
}

public enum SharedUsageSeverity: String, Codable, Sendable {
    case normal
    case warning
    case critical
    case neutral
}

public enum SharedAvailabilityLifecycle: String, Codable, Equatable, Sendable {
    case configured
    case unconfigured
    case invalid
    case unavailable
}

public enum SharedRemainingValue: Codable, Equatable, Sendable {
    case finite(Double)
    case unlimited
    case unavailable

    public var finitePercent: Double? {
        guard case let .finite(value) = self else { return nil }
        return value
    }

    public var displayPercent: Int? {
        finitePercent.map { Int($0.rounded()) }
    }

    public var tintFraction: Double? {
        finitePercent.map { $0 / 100 }
    }

    public var displayText: String {
        switch self {
        case .finite: "\(displayPercent ?? 0)%"
        case .unlimited: "∞"
        case .unavailable: "—"
        }
    }
}

public struct SharedAvailabilityPresentation: Codable, Equatable, Sendable {
    public let value: AgentAvailabilityValue
    public let displayUnit: CreditUnit?
    public let exactCreditValue: Decimal?
    public let normalizedRemainingFraction: Double?
    public let severity: AgentAvailabilitySeverity
    public let provenance: AvailabilityProvenance?
    public let scope: CreditScope?
    public let planTier: CreditPlanTier?
    public let nextExpiryAt: Date?
    public let compactText: String
    public let accessibilityText: String

    public var sourceState: AgentAvailabilitySourceState {
        value.sourceState
    }

    public init(
        value: AgentAvailabilityValue,
        displayUnit: CreditUnit?,
        exactCreditValue: Decimal?,
        normalizedRemainingFraction: Double?,
        severity: AgentAvailabilitySeverity,
        provenance: AvailabilityProvenance?,
        scope: CreditScope?,
        planTier: CreditPlanTier?,
        nextExpiryAt: Date?,
        compactText: String,
        accessibilityText: String
    ) {
        self.value = value
        self.displayUnit = displayUnit
        self.exactCreditValue = exactCreditValue
        self.normalizedRemainingFraction = normalizedRemainingFraction
        self.severity = severity
        self.provenance = provenance
        self.scope = scope
        self.planTier = planTier
        self.nextExpiryAt = nextExpiryAt
        self.compactText = compactText
        self.accessibilityText = accessibilityText
    }
}

public enum SharedUsageWindowKind: String, Codable, Sendable {
    case fiveHour
    case sevenDay
    case other
}

public struct SharedUsageWindowPresentation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: SharedUsageWindowKind
    public let compactLabel: String
    public let accessibilityLabel: String
    public let remaining: SharedRemainingValue
    public let resetsAt: Date?
    public let resetText: String

    public init(
        id: String,
        kind: SharedUsageWindowKind,
        compactLabel: String,
        accessibilityLabel: String,
        remaining: SharedRemainingValue,
        resetsAt: Date?,
        resetText: String
    ) {
        self.id = id
        self.kind = kind
        self.compactLabel = compactLabel
        self.accessibilityLabel = accessibilityLabel
        self.remaining = remaining
        self.resetsAt = resetsAt
        self.resetText = resetText
    }
}

public struct SharedAccountCreditBreakdown: Codable, Equatable, Sendable {
    public let subscriptionRemaining: Decimal
    public let addOnRemaining: Decimal
    public let benefitGiftRemaining: Decimal
    public let calculatedTotalRemaining: Decimal
    public let observedAt: Date

    public init(
        subscriptionRemaining: Decimal,
        addOnRemaining: Decimal,
        benefitGiftRemaining: Decimal,
        calculatedTotalRemaining: Decimal,
        observedAt: Date
    ) {
        self.subscriptionRemaining = subscriptionRemaining
        self.addOnRemaining = addOnRemaining
        self.benefitGiftRemaining = benefitGiftRemaining
        self.calculatedTotalRemaining = calculatedTotalRemaining
        self.observedAt = observedAt
    }

    private enum CodingKeys: String, CodingKey {
        case subscriptionRemaining
        case addOnRemaining
        case benefitGiftRemaining
        case calculatedTotalRemaining
        case observedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decimal(_ key: CodingKeys) throws -> Decimal {
            let text = try container.decode(String.self, forKey: key)
            guard let value = WorkBuddyAccountCreditRules.parseCanonical(text)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Invalid canonical Credit value."
                )
            }
            return value
        }
        let subscription = try decimal(.subscriptionRemaining)
        let addOn = try decimal(.addOnRemaining)
        let benefitGift = try decimal(.benefitGiftRemaining)
        let total = try decimal(.calculatedTotalRemaining)
        guard subscription + addOn + benefitGift == total else {
            throw DecodingError.dataCorruptedError(
                forKey: .calculatedTotalRemaining,
                in: container,
                debugDescription: "Inconsistent Credit breakdown."
            )
        }
        self.init(
            subscriptionRemaining: subscription,
            addOnRemaining: addOn,
            benefitGiftRemaining: benefitGift,
            calculatedTotalRemaining: total,
            observedAt: try container.decode(Date.self, forKey: .observedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            CreditDecimalCodec.canonicalString(subscriptionRemaining),
            forKey: .subscriptionRemaining
        )
        try container.encode(
            CreditDecimalCodec.canonicalString(addOnRemaining),
            forKey: .addOnRemaining
        )
        try container.encode(
            CreditDecimalCodec.canonicalString(benefitGiftRemaining),
            forKey: .benefitGiftRemaining
        )
        try container.encode(
            CreditDecimalCodec.canonicalString(calculatedTotalRemaining),
            forKey: .calculatedTotalRemaining
        )
        try container.encode(observedAt, forKey: .observedAt)
    }
}

public struct SharedUsageCardPresentation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let providerName: String
    public let planLabel: String?
    public let connectionStatus: SharedConnectionStatus
    public let freshness: SharedUsageFreshness
    public let windows: [SharedUsageWindowPresentation]
    public let selectedWindowID: String?
    public let remaining: SharedRemainingValue
    public let availability: SharedAvailabilityPresentation?
    public let accountCreditBreakdown: SharedAccountCreditBreakdown?
    public let availabilityLifecycle: SharedAvailabilityLifecycle?
    public let sourceDescription: String?
    public let isVisibleInDesktopAssistant: Bool
    public let severity: SharedUsageSeverity
    public let isRetainingLastValidValue: Bool
    public let capturedAt: Date

    public init(
        id: String,
        providerName: String,
        planLabel: String? = nil,
        connectionStatus: SharedConnectionStatus,
        freshness: SharedUsageFreshness,
        windows: [SharedUsageWindowPresentation],
        selectedWindowID: String?,
        remaining: SharedRemainingValue,
        availability: SharedAvailabilityPresentation? = nil,
        accountCreditBreakdown: SharedAccountCreditBreakdown? = nil,
        availabilityLifecycle: SharedAvailabilityLifecycle? = nil,
        sourceDescription: String? = nil,
        isVisibleInDesktopAssistant: Bool = true,
        severity: SharedUsageSeverity,
        isRetainingLastValidValue: Bool = false,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.planLabel = planLabel
        self.connectionStatus = connectionStatus
        self.freshness = freshness
        self.windows = windows
        self.selectedWindowID = selectedWindowID
        self.remaining = remaining
        self.availability = availability
        self.accountCreditBreakdown = accountCreditBreakdown
        self.availabilityLifecycle = availabilityLifecycle
        self.sourceDescription = sourceDescription
        self.isVisibleInDesktopAssistant = isVisibleInDesktopAssistant
        self.severity = severity
        self.isRetainingLastValidValue = isRetainingLastValidValue
        self.capturedAt = capturedAt
    }

    public var selectedWindow: SharedUsageWindowPresentation? {
        guard let selectedWindowID else { return nil }
        return windows.first(where: { $0.id == selectedWindowID })
    }

    public var selectedWindowCompactLabel: String? {
        selectedWindow?.compactLabel
    }

    public var tooltipText: String {
        if let availability {
            if availability.sourceState == .authenticatedAccountWeb {
                return "\(providerName), \(connectionStatus.accessibilityText), "
                    + "\(availability.accessibilityText), "
                    + "\(sourceDescription ?? "Account web sync")."
            }
            return availability.accessibilityText
        }
        let window = selectedWindow?.accessibilityLabel ?? "usage window unavailable"
        let value: String
        switch remaining {
        case .finite: value = "\(remaining.displayPercent ?? 0) percent remaining"
        case .unlimited: value = "unlimited"
        case .unavailable: value = "usage unavailable"
        }
        let sourceState = switch freshness {
        case .fresh: ""
        case .cached: "cached, "
        case .stale: "stale, "
        case .unavailable: ""
        }
        return "\(providerName), \(connectionStatus.accessibilityText), \(sourceState)\(window), \(value)."
    }

    public var accessibilityLabel: String { tooltipText }
}

public enum SharedUsagePresentationPolicy {
    private enum RemainingThresholdBand {
        case available
        case warning
        case critical
        case exhausted
    }

    public static func severity(for remaining: SharedRemainingValue) -> SharedUsageSeverity {
        switch remaining {
        case let .finite(percent):
            switch thresholdBand(forPercent: percent) {
            case .available: .normal
            case .warning: .warning
            case .critical, .exhausted: .critical
            }
        case .unlimited, .unavailable:
            .neutral
        }
    }

    public static func availabilitySeverity(
        for value: AgentAvailabilityValue
    ) -> AgentAvailabilitySeverity {
        switch value {
        case let .percentage(percentage):
            return availabilitySeverity(forFraction: percentage.value / 100)
        case let .credits(balance):
            if let fraction = balance.normalizedRemainingFraction {
                return availabilitySeverity(forFraction: fraction)
            }
            return balance.isExhausted ? .exhausted : .neutral
        case .unlimited, .unavailable:
            return .neutral
        case .invalid:
            return .invalid
        }
    }

    public static func makeAvailabilityPresentation(
        value: AgentAvailabilityValue,
        language: AppLanguage
    ) -> SharedAvailabilityPresentation {
        let compactText: String
        let accessibilityText: String
        let displayUnit: CreditUnit?
        let exactCreditValue: Decimal?
        let provenance: AvailabilityProvenance?
        let scope: CreditScope?
        let planTier: CreditPlanTier?
        let nextExpiryAt: Date?

        switch value {
        case let .percentage(percentage):
            let rounded = Int(percentage.value.rounded())
            compactText = "\(rounded)%"
            accessibilityText = language == .english
                ? "\(rounded) percent remaining"
                : "剩余 \(rounded)%"
            displayUnit = nil
            exactCreditValue = nil
            provenance = nil
            scope = nil
            planTier = nil
            nextExpiryAt = nil
        case let .credits(balance):
            compactText = CreditFormatter.compact(balance.remaining)
            if case .authenticatedAccountWeb = balance.provenance {
                accessibilityText = CreditFormatter.accessibilityAvailable(
                    balance.remaining,
                    language: language
                )
            } else {
                accessibilityText = CreditFormatter.accessibilityRemaining(
                    balance.remaining,
                    language: language
                )
            }
            displayUnit = balance.unit
            exactCreditValue = balance.remaining
            provenance = balance.provenance
            scope = balance.scope
            planTier = balance.planTier
            nextExpiryAt = balance.nextExpiryAt
        case .unlimited:
            compactText = "∞"
            accessibilityText = language == .english ? "unlimited" : "无限"
            displayUnit = nil
            exactCreditValue = nil
            provenance = nil
            scope = nil
            planTier = nil
            nextExpiryAt = nil
        case .unavailable:
            compactText = "—"
            accessibilityText = language == .english ? "usage unavailable" : "额度不可用"
            displayUnit = nil
            exactCreditValue = nil
            provenance = nil
            scope = nil
            planTier = nil
            nextExpiryAt = nil
        case .invalid:
            compactText = "—"
            accessibilityText = language == .english ? "invalid usage data" : "额度数据无效"
            displayUnit = nil
            exactCreditValue = nil
            provenance = nil
            scope = nil
            planTier = nil
            nextExpiryAt = nil
        }

        return SharedAvailabilityPresentation(
            value: value,
            displayUnit: displayUnit,
            exactCreditValue: exactCreditValue,
            normalizedRemainingFraction: value.normalizedRemainingFraction,
            severity: availabilitySeverity(for: value),
            provenance: provenance,
            scope: scope,
            planTier: planTier,
            nextExpiryAt: nextExpiryAt,
            compactText: compactText,
            accessibilityText: accessibilityText
        )
    }

    private static func availabilitySeverity(
        forFraction fraction: Double
    ) -> AgentAvailabilitySeverity {
        switch thresholdBand(forPercent: fraction * 100) {
        case .available: .available
        case .warning: .warning
        case .critical: .critical
        case .exhausted: .exhausted
        }
    }

    private static func thresholdBand(forPercent percent: Double) -> RemainingThresholdBand {
        switch max(0, min(100, percent)) {
        case 0: .exhausted
        case 0...10: .critical
        case 10..<26: .warning
        default: .available
        }
    }

    static func makeCards(
        snapshots: [AgentUsageSnapshot],
        previousCards: [SharedUsageCardPresentation],
        language: AppLanguage,
        now: Date = Date()
    ) -> [SharedUsageCardPresentation] {
        let previousByID = Dictionary(uniqueKeysWithValues: previousCards.map { ($0.id, $0) })
        return snapshots
            .filter(isVisibleInMainPanel)
            .map {
                makeCard(
                    snapshot: $0,
                    previous: previousByID[$0.id.rawValue],
                    language: language,
                    now: now
                )
            }
            .sorted {
                AgentProviderOrder.precedes(raw: $0.id, $1.id)
            }
    }

    /// Desktop Assistant order is a presentation-identity contract. It never
    /// depends on quota value, source state, confirmation age, tier, or
    /// failure. The roadmap priority is Codex, Claude Code, WorkBuddy, Manus,
    /// Cursor, Kimi+, then Doubao without creating empty placeholders.
    public static func assistantCards(
        from cards: [SharedUsageCardPresentation]
    ) -> [SharedUsageCardPresentation] {
        cards
            .filter(\.isVisibleInDesktopAssistant)
            .sorted { lhs, rhs in
                AgentProviderOrder.precedes(raw: lhs.id, rhs.id)
            }
    }

    private static func isVisibleInMainPanel(_ snapshot: AgentUsageSnapshot) -> Bool {
        guard !snapshot.capabilities.contains(.hiddenFromProviderSurfaces) else {
            return false
        }
        let permitsSanitizedLastValid = snapshot.capabilities.contains(
            .sanitizedLastValidRestore
        )
        if permitsSanitizedLastValid,
           (snapshot.state == .ready || snapshot.state == .stale),
           [.cached, .stale].contains(snapshot.freshness),
           let account = snapshot.channels.first(where: { $0.id == .account }),
           account.provenance == .providerReported,
           account.freshness == snapshot.freshness,
           !account.rateLimitWindows.isEmpty,
           account.rateLimitWindows.allSatisfy({
               $0.isUnlimited || $0.normalizedRemainingPercent != nil
           }) {
            return true
        }
        guard snapshot.state == .ready,
              snapshot.freshness == .fresh,
              snapshot.safeFailure == nil,
              let account = snapshot.channels.first(where: { $0.id == .account }),
              account.sourceTier != .manualUserConfirmed,
              account.provenance == .providerReported,
              account.freshness == .fresh,
              account.safeFailure == nil
        else { return false }
        if account.availabilitySourceState == .officialStructured
            || account.availabilitySourceState == .authenticatedAccountWeb {
            return true
        }
        return !account.rateLimitWindows.isEmpty
    }

    static func makeCard(
        snapshot: AgentUsageSnapshot,
        previous: SharedUsageCardPresentation?,
        language: AppLanguage,
        now: Date = Date()
    ) -> SharedUsageCardPresentation {
        if let previous, snapshot.capturedAt < previous.capturedAt {
            return previous
        }
        let accountChannel = snapshot.channels.first(where: { $0.id == .account })
        let freshWindows = accountChannel?.rateLimitWindows.map {
            makeWindow($0, language: language, now: now)
        } ?? []
        let sourceIsCached = snapshot.freshness == .cached
            || accountChannel?.freshness == .cached
        let sourceIsStale = snapshot.freshness == .stale
            || accountChannel?.freshness == .stale
            || snapshot.state == .stale
        let sourceIsRetained = sourceIsCached || sourceIsStale
        let usesSanitizedLastValid = snapshot.capabilities.contains(
            .sanitizedLastValidRestore
        ) && sourceIsRetained
        let sourceIsUnavailable = accountChannel == nil
            || accountChannel?.freshness == .unavailable

        let windows: [SharedUsageWindowPresentation]
        let retainedWindows: Bool
        if usesSanitizedLastValid {
            windows = freshWindows
            retainedWindows = true
        } else if sourceIsRetained, let previous, !previous.windows.isEmpty {
            windows = previous.windows
            retainedWindows = true
        } else if sourceIsUnavailable,
                  freshWindows.allSatisfy({ $0.remaining == .unavailable }),
                  let previous,
                  !previous.windows.isEmpty {
            windows = previous.windows
            retainedWindows = true
        } else {
            windows = freshWindows
            retainedWindows = sourceIsRetained
        }

        let freshAvailability = accountChannel?.availability.map {
            makeAvailabilityPresentation(value: $0, language: language)
        }
        let availabilityLifecycle: SharedAvailabilityLifecycle? = {
            guard accountChannel?.provenance == .manualConfirmed else { return nil }
            if freshAvailability?.sourceState == .manualConfirmed {
                return .configured
            }
            switch accountChannel?.safeFailure ?? snapshot.safeFailure {
            case .malformedResponse:
                return .invalid
            case .unavailable:
                return .unconfigured
            case nil:
                return .unavailable
            default:
                return .unavailable
            }
        }()
        let receivedManualConfirmation =
            freshAvailability?.sourceState == .manualConfirmed
        let availability: SharedAvailabilityPresentation?
        let retainedAvailability: Bool
        if receivedManualConfirmation {
            availability = freshAvailability
            retainedAvailability = false
        } else if (
            sourceIsRetained
                || (sourceIsUnavailable && availabilityLifecycle == nil)
        ),
                  let previousAvailability = previous?.availability {
            availability = previousAvailability
            retainedAvailability = true
        } else {
            availability = freshAvailability
            retainedAvailability = false
        }
        let retained = retainedWindows || retainedAvailability
        let hasOnlyManualAvailability = freshWindows.isEmpty
            && availability?.sourceState == .manualConfirmed

        let selectedID = selectedWindowID(
            windows: windows,
            previous: previous,
            preferredID: snapshot.selectedWindowID,
            isStale: sourceIsRetained,
            now: now
        )
        let remaining: SharedRemainingValue
        if let selected = windows.first(where: { $0.id == selectedID }) {
            remaining = selected.remaining
        } else if retained, let previous {
            remaining = previous.remaining
        } else {
            remaining = .unavailable
        }
        let planLabel = accountChannel?.accountMetrics?.planLabel
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? (retainedAvailability ? previous?.planLabel : nil)
        let presentedConnectionStatus = connectionStatus(snapshot.state)
        let presentedFreshness = freshness(snapshot.freshness)

        return SharedUsageCardPresentation(
            id: snapshot.id.rawValue,
            providerName: snapshot.providerName,
            planLabel: planLabel,
            connectionStatus: hasOnlyManualAvailability && presentedConnectionStatus.isHealthy
                ? .disconnected
                : presentedConnectionStatus,
            freshness: hasOnlyManualAvailability && presentedFreshness == .fresh
                ? .unavailable
                : presentedFreshness,
            windows: windows,
            selectedWindowID: selectedID,
            remaining: remaining,
            availability: availability,
            accountCreditBreakdown: accountChannel?.accountCreditSnapshot.map {
                SharedAccountCreditBreakdown(
                    subscriptionRemaining: $0.subscriptionRemaining,
                    addOnRemaining: $0.addOnRemaining,
                    benefitGiftRemaining: $0.benefitGiftRemaining,
                    calculatedTotalRemaining: $0.calculatedTotalRemaining,
                    observedAt: $0.observedAt
                )
            },
            availabilityLifecycle: availabilityLifecycle,
            sourceDescription: availability?.sourceState == .authenticatedAccountWeb
                ? language.workBuddyAccountWebSource
                : snapshot.capabilities.contains(.sanitizedLastValidRestore)
                    ? accountChannel?.coverageNote
                    : nil,
            isVisibleInDesktopAssistant: !snapshot.capabilities.contains(
                .hiddenFromDesktopAssistant
            ),
            severity: sourceIsRetained ? .neutral : severity(for: remaining),
            isRetainingLastValidValue: retained || sourceIsRetained,
            capturedAt: snapshot.capturedAt
        )
    }

    private static func makeWindow(
        _ window: AgentRateLimitWindow,
        language: AppLanguage,
        now: Date
    ) -> SharedUsageWindowPresentation {
        let labels: (kind: SharedUsageWindowKind, compact: String, accessibility: String)
        switch window.kind {
        case .fiveHour:
            labels = (.fiveHour, "5H", language == .english ? "five-hour window" : "五小时额度窗口")
        case .sevenDay:
            labels = (.sevenDay, "7D", language == .english ? "seven-day window" : "七天额度窗口")
        case .other:
            if let displayLabel = window.displayLabel {
                labels = (
                    .other,
                    displayLabel,
                    language == .english
                        ? "\(displayLabel) usage window"
                        : "\(displayLabel) 额度窗口"
                )
            } else {
                labels = (.other, "—", language == .english ? "usage window" : "额度窗口")
            }
        }

        let remaining: SharedRemainingValue
        if window.isUnlimited {
            remaining = .unlimited
        } else if let normalized = window.normalizedRemainingPercent {
            remaining = .finite(normalized)
        } else {
            remaining = .unavailable
        }

        return SharedUsageWindowPresentation(
            id: window.id,
            kind: labels.kind,
            compactLabel: labels.compact,
            accessibilityLabel: labels.accessibility,
            remaining: remaining,
            resetsAt: window.resetsAt,
            resetText: language.resetDescription(for: window.resetsAt, now: now)
        )
    }

    private static func selectedWindowID(
        windows: [SharedUsageWindowPresentation],
        previous: SharedUsageCardPresentation?,
        preferredID: String?,
        isStale: Bool,
        now: Date
    ) -> String? {
        let previousID = previous?.selectedWindowID
        // Keep obsolete windows in `windows` for truthful detail disclosure,
        // but never allow an already-ended quota epoch to drive the compact
        // card, status item, or Desktop Assistant selection.
        let eligibleWindows = windows.filter { window in
            window.resetsAt.map { $0 > now } ?? true
        }
        let finite = eligibleWindows.compactMap { window -> (SharedUsageWindowPresentation, Double)? in
            guard case let .finite(value) = window.remaining else { return nil }
            return (window, value)
        }

        if isStale,
           let preferredID,
           eligibleWindows.contains(where: { $0.id == preferredID }) {
            return preferredID
        }

        if isStale,
           let previousID,
           eligibleWindows.contains(where: { $0.id == previousID }) {
            return previousID
        }

        if let depleted = finite
            .filter({ $0.1 == 0 })
            .sorted(by: deterministicWindowOrder)
            .first {
            return depleted.0.id
        }

        if let critical = finite
            .filter({ $0.1 > 0 && $0.1 <= 10 })
            .sorted(by: { lhs, rhs in
                lhs.1 == rhs.1 ? deterministicWindowOrder(lhs, rhs) : lhs.1 < rhs.1
            })
            .first {
            return critical.0.id
        }

        if let previous {
            let previousPairs: [(String, (Double, Date?))] = previous.windows.compactMap {
                guard case let .finite(value) = $0.remaining else { return nil }
                return ($0.id, (value, $0.resetsAt))
            }
            let previousValues: [String: (Double, Date?)] = Dictionary(
                uniqueKeysWithValues: previousPairs
            )
            let positiveDecrements = finite.compactMap {
                current -> (window: SharedUsageWindowPresentation, decrement: Double, remaining: Double)? in
                guard let old = previousValues[current.0.id] else { return nil }
                guard old.1 == current.0.resetsAt else { return nil }
                let decrement = max(0, old.0 - current.1)
                return decrement > 0 ? (current.0, decrement, current.1) : nil
            }
            if let winner = positiveDecrements.sorted(by: { lhs, rhs in
                if lhs.decrement != rhs.decrement {
                    return lhs.decrement > rhs.decrement
                }
                if lhs.remaining != rhs.remaining {
                    return lhs.remaining < rhs.remaining
                }
                return deterministicWindowOrder((lhs.window, 0), (rhs.window, 0))
            }).first {
                return winner.window.id
            }
            if let previousID,
               eligibleWindows.contains(where: { window in
                   guard window.id == previousID else { return false }
                   if case .finite = window.remaining { return true }
                   return false
               }) {
                return previousID
            }
        }

        if let coldStart = finite.sorted(by: { lhs, rhs in
            lhs.1 == rhs.1 ? deterministicWindowOrder(lhs, rhs) : lhs.1 < rhs.1
        }).first {
            return coldStart.0.id
        }
        if let unlimited = eligibleWindows.first(where: { $0.remaining == .unlimited }) {
            return unlimited.id
        }
        return eligibleWindows.first?.id
    }

    private static func deterministicWindowOrder(
        _ lhs: (SharedUsageWindowPresentation, Double),
        _ rhs: (SharedUsageWindowPresentation, Double)
    ) -> Bool {
        let rank: (SharedUsageWindowPresentation) -> Int = {
            switch $0.kind {
            // The seven-day account window is the stable deterministic
            // preference when otherwise-equal finite windows compete. A
            // five-hour window still wins when it is the only finite value,
            // depleted/critical with a stronger value, or has the strictly
            // greatest decrement.
            case .sevenDay: 0
            case .fiveHour: 1
            default: 2
            }
        }
        let lhsRank = rank(lhs.0)
        let rhsRank = rank(rhs.0)
        return lhsRank == rhsRank ? lhs.0.id < rhs.0.id : lhsRank < rhsRank
    }

    private static func connectionStatus(_ state: AgentConnectorState) -> SharedConnectionStatus {
        switch state {
        case .ready: .connected
        case .waitingForFirstResponse: .transitional
        case .authenticationRequired: .authenticationRequired
        case .stale: .stale
        case .inactive: .disconnected
        case .unsupported: .unavailable
        case .failed: .failed
        }
    }

    private static func freshness(_ value: AgentConnectorFreshness) -> SharedUsageFreshness {
        switch value {
        case .fresh: .fresh
        case .cached: .cached
        case .stale: .stale
        case .unavailable: .unavailable
        }
    }
}

private extension SharedConnectionStatus {
    var accessibilityText: String {
        switch self {
        case .connected: "connected"
        case .transitional: "connecting"
        case .authenticationRequired: "authentication required"
        case .stale: "connection stale"
        case .disconnected: "disconnected"
        case .unavailable: "unavailable"
        case .failed: "connection failed"
        }
    }
}
