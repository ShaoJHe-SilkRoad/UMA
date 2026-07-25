import Foundation

public enum WorkBuddyMainPanelState: String, Equatable, Sendable {
    case configured
    case exhausted
    case unconfigured
    case invalid
    case unavailable
}

struct MainPanelProviderExpansionState: Equatable {
    private(set) var expandedProviderIDs: Set<String>

    init(expandedProviderIDs: Set<String> = []) {
        self.expandedProviderIDs = expandedProviderIDs
    }

    func isExpanded(_ providerID: String) -> Bool {
        expandedProviderIDs.contains(providerID)
    }

    mutating func setExpanded(_ expanded: Bool, providerID: String) {
        if expanded {
            expandedProviderIDs.insert(providerID)
        } else {
            expandedProviderIDs.remove(providerID)
        }
    }
}

public struct WorkBuddyMainPanelPresentation: Equatable, Sendable {
    public let state: WorkBuddyMainPanelState
    public let providerName: String
    public let scopeTitle: String
    public let scopeDetail: String
    public let compactValue: String
    public let availableText: String
    public let balanceDetail: String?
    public let manualStatus: String
    public let compactManualStatus: String
    public let exactConfirmation: String?
    public let tierText: String?
    public let expiryText: String?
    public let limitationText: String
    public let severity: AgentAvailabilitySeverity
    public let severityText: String
    public let remainingFraction: Double?
    public let accessibilityLabel: String

    public static func make(
        card: SharedUsageCardPresentation,
        language: AppLanguage,
        now: Date = Date()
    ) -> WorkBuddyMainPanelPresentation? {
        guard let lifecycle = card.availabilityLifecycle else { return nil }
        let availability = card.availability
        let balance = availability?.value.creditBalance
        let isExhausted = balance?.isExhausted == true
        let state: WorkBuddyMainPanelState = switch lifecycle {
        case .configured: isExhausted ? .exhausted : .configured
        case .unconfigured: .unconfigured
        case .invalid: .invalid
        case .unavailable: .unavailable
        }
        let exactRemaining = balance.map {
            CreditFormatter.exact($0.remaining, language: language)
        }
        let compactValue = exactRemaining ?? "—"
        let availableText: String = switch state {
        case .configured:
            language.workBuddyCreditsAvailable(exactRemaining ?? "—")
        case .exhausted:
            language.workBuddyConversationCreditsExhausted
        case .unconfigured:
            language.workBuddyMainPanelNotConfigured
        case .invalid:
            language.workBuddyInvalidSavedData
        case .unavailable:
            language.workBuddyMainPanelUnavailable
        }
        let balanceDetail: String? = balance.flatMap {
            if let used = $0.used, let total = $0.derivedTotal {
                return language.workBuddyUsedOfActive(
                    used: CreditFormatter.exact(used, language: language),
                    total: CreditFormatter.exact(total, language: language)
                )
            }
            if let total = $0.total {
                return language.workBuddyActiveTotalValue(
                    CreditFormatter.exact(total, language: language)
                )
            }
            return nil
        }
        let confirmedAt = availability?.provenance?.observedAt
        let relativeAge = confirmedAt.map {
            language.workBuddyRelativeConfirmationAge(from: $0, to: now)
        }
        let manualStatus = relativeAge.map {
            "\(language.workBuddyManualSnapshot) • \(language.workBuddyConfirmed) \($0)"
        } ?? language.workBuddyNotYetConfirmed
        let compactManualStatus = relativeAge.map {
            language == .english ? "Manual • \($0)" : "手动 • \($0)"
        } ?? language.workBuddyManualConfirmation
        let exactConfirmation = confirmedAt.map(language.workBuddyConfirmedAt)
        let tierText = card.planLabel
            .flatMap(WorkBuddyPlanTier.init(rawValue:))
            .map(language.workBuddyTierName)
        let expiryText = availability?.nextExpiryAt.map(language.workBuddyExpiryAt)
        let severity: AgentAvailabilitySeverity = switch state {
        case .invalid: .invalid
        case .exhausted: .exhausted
        case .unconfigured, .unavailable: .neutral
        case .configured:
            balance?.normalizedRemainingFraction == nil
                ? .neutral
                : (availability?.severity ?? .neutral)
        }
        let severityText: String = switch state {
        case .unconfigured:
            language.workBuddyNotConfiguredState
        case .unavailable:
            language.workBuddyUnavailableState
        case .configured, .exhausted, .invalid:
            language.workBuddyAvailabilityState(severity)
        }

        var accessibilityParts = [
            card.providerName,
            availableText
        ]
        if let balanceDetail { accessibilityParts.append(balanceDetail) }
        accessibilityParts.append(language.workBuddyBuddyAISharedCredits)
        accessibilityParts.append(language.workBuddySharedWithCodeBuddy)
        accessibilityParts.append(
            confirmedAt == nil ? language.workBuddyManualConfirmation : manualStatus
        )
        accessibilityParts.append(severityText)
        if let tierText {
            accessibilityParts.append("\(language.workBuddyTier): \(tierText)")
        }
        if let expiryText {
            accessibilityParts.append("\(language.workBuddyNextExpiryLabel): \(expiryText)")
        }

        return WorkBuddyMainPanelPresentation(
            state: state,
            providerName: card.providerName,
            scopeTitle: language.workBuddyBuddyAISharedCredits,
            scopeDetail: language.workBuddySharedWithCodeBuddy,
            compactValue: compactValue,
            availableText: availableText,
            balanceDetail: balanceDetail,
            manualStatus: manualStatus,
            compactManualStatus: compactManualStatus,
            exactConfirmation: exactConfirmation,
            tierText: tierText,
            expiryText: expiryText,
            limitationText: confirmedAt == nil
                ? language.workBuddyManualEntryNoSync
                : language.workBuddyAutomaticSyncUnavailable,
            severity: severity,
            severityText: severityText,
            remainingFraction: availability?.normalizedRemainingFraction,
            accessibilityLabel: accessibilityParts.joined(separator: ", ") + "."
        )
    }
}
