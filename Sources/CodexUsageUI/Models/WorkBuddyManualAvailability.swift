import Foundation

public enum WorkBuddyManualSourceMode: String, Codable, Sendable {
    case manualConfirmation
}

public enum WorkBuddyManualScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case personalShared
    case enterpriseShared
    case unknown

    public var id: String { rawValue }

    var creditScope: CreditScope {
        switch self {
        case .personalShared: .buddyAISharedPersonal
        case .enterpriseShared: .buddyAIEnterpriseShared
        case .unknown: .buddyAIUnknown
        }
    }

    var creditPlanTier: CreditPlanTier? {
        switch self {
        case .personalShared: .personal
        case .enterpriseShared: .enterprise
        case .unknown: nil
        }
    }
}

public enum WorkBuddyPlanTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case experience
    case standard
    case advanced
    case flagship
    case enterprise
    case unknown

    public var id: String { rawValue }
}

public enum WorkBuddyCreditCompanionField: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case used
    case total
    case usedAndTotal

    public var id: String { rawValue }
}

public struct WorkBuddyTierSuggestion: Equatable, Sendable {
    public static let catalogVersion = "1.0"
    public static let effectiveDate = "2026-07-24"

    public let tier: WorkBuddyPlanTier
    public let baseCredits: Int64
    public let temporaryBonusCredits: Int64

    public var suggestedTotal: Int64 { baseCredits + temporaryBonusCredits }

    public static let publishedJuly2026: [WorkBuddyTierSuggestion] = [
        .init(tier: .experience, baseCredits: 500, temporaryBonusCredits: 0),
        .init(tier: .standard, baseCredits: 2_000, temporaryBonusCredits: 2_000),
        .init(tier: .advanced, baseCredits: 4_000, temporaryBonusCredits: 5_000),
        .init(tier: .flagship, baseCredits: 20_000, temporaryBonusCredits: 30_000)
    ]
}

public struct WorkBuddyManualObservation: Codable, Equatable, Sendable {
    public let scope: WorkBuddyManualScope
    public let tier: WorkBuddyPlanTier
    public let balance: CreditBalance
    public let entryMode: WorkBuddyCreditCompanionField?

    public init(
        scope: WorkBuddyManualScope,
        tier: WorkBuddyPlanTier,
        balance: CreditBalance,
        entryMode: WorkBuddyCreditCompanionField? = nil
    ) throws {
        guard balance.scope == scope.creditScope,
              balance.planTier == scope.creditPlanTier,
              case let .manualConfirmed(confirmedAt) = balance.provenance,
              confirmedAt == balance.observedAt,
              Self.entryMode(entryMode, matches: balance) else {
            throw WorkBuddyManualValidationError.invalidManualRecord
        }
        self.scope = scope
        self.tier = tier
        self.balance = balance
        self.entryMode = entryMode
    }

    func confirming(at date: Date) throws -> WorkBuddyManualObservation {
        try WorkBuddyManualObservation(
            scope: scope,
            tier: tier,
            balance: CreditBalance(
                validatingDecimalRemaining: balance.remaining,
                used: balance.used,
                total: balance.total,
                scope: balance.scope,
                planTier: balance.planTier,
                nextExpiryAt: balance.nextExpiryAt,
                observedAt: date,
                provenance: .manualConfirmed(at: date)
            ),
            entryMode: entryMode
        )
    }

    var resolvedEntryMode: WorkBuddyCreditCompanionField {
        entryMode ?? Self.inferredEntryMode(for: balance)
    }

    private static func inferredEntryMode(
        for balance: CreditBalance
    ) -> WorkBuddyCreditCompanionField {
        if balance.used != nil { return .used }
        if balance.total != nil { return .total }
        return .none
    }

    private static func entryMode(
        _ mode: WorkBuddyCreditCompanionField?,
        matches balance: CreditBalance
    ) -> Bool {
        switch mode ?? inferredEntryMode(for: balance) {
        case .none:
            balance.used == nil && balance.total == nil
        case .used:
            balance.used != nil && balance.total != nil
        case .total:
            balance.used == nil && balance.total != nil
        case .usedAndTotal:
            balance.used != nil && balance.total != nil
        }
    }
}

public struct WorkBuddyManualPersistenceRecord: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let connectorID = "workbuddy.manualAvailability"

    public let schemaVersion: Int
    public let connectorID: String
    public let sourceMode: WorkBuddyManualSourceMode
    public let enabled: Bool
    public let observation: WorkBuddyManualObservation?

    public init(enabled: Bool, observation: WorkBuddyManualObservation?) {
        self.schemaVersion = Self.schemaVersion
        self.connectorID = Self.connectorID
        self.sourceMode = .manualConfirmation
        self.enabled = enabled
        self.observation = observation
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case connectorID
        case sourceMode
        case enabled
        case observation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.schemaVersion else {
            throw WorkBuddyManualValidationError.unsupportedSchema
        }
        let connectorID = try container.decode(String.self, forKey: .connectorID)
        guard connectorID == Self.connectorID else {
            throw WorkBuddyManualValidationError.invalidManualRecord
        }
        let sourceMode = try container.decode(WorkBuddyManualSourceMode.self, forKey: .sourceMode)
        guard sourceMode == .manualConfirmation else {
            throw WorkBuddyManualValidationError.invalidManualRecord
        }
        let observation = try container.decodeIfPresent(
            WorkBuddyManualObservation.self,
            forKey: .observation
        )
        if let observation {
            _ = try WorkBuddyManualObservation(
                scope: observation.scope,
                tier: observation.tier,
                balance: observation.balance
            )
        }
        self.schemaVersion = schemaVersion
        self.connectorID = connectorID
        self.sourceMode = sourceMode
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        self.observation = observation
    }
}

public enum WorkBuddyManualValidationError: String, Error, Codable, Equatable, Sendable {
    case requiredRemaining
    case requiredUsed
    case requiredTotal
    case invalidInteger
    case integerOutOfRange
    case expiryMustBeFuture
    case invalidManualRecord
    case unsupportedSchema
    case recordTooLarge
    case persistenceUnavailable
    case corruptPersistence
    case noConfirmedValue
    case staleDraft
}

public struct WorkBuddyManualDraft: Equatable, Sendable {
    public var scope: WorkBuddyManualScope
    public var tier: WorkBuddyPlanTier
    public var remainingText: String
    public var companionField: WorkBuddyCreditCompanionField
    public var companionText: String
    public var explicitTotalText: String
    public var includesExpiry: Bool
    public var expiry: Date

    public init(
        scope: WorkBuddyManualScope = .unknown,
        tier: WorkBuddyPlanTier = .unknown,
        remainingText: String = "",
        companionField: WorkBuddyCreditCompanionField = .used,
        companionText: String = "",
        explicitTotalText: String = "",
        includesExpiry: Bool = false,
        expiry: Date = Date().addingTimeInterval(30 * 24 * 60 * 60)
    ) {
        self.scope = scope
        self.tier = tier
        self.remainingText = remainingText
        self.companionField = companionField
        self.companionText = companionText
        self.explicitTotalText = explicitTotalText
        self.includesExpiry = includesExpiry
        self.expiry = expiry
    }

    public func validated(at confirmationDate: Date) throws -> WorkBuddyManualObservation {
        let remaining = try Self.parseRequired(
            remainingText,
            missing: .requiredRemaining
        )
        if includesExpiry, expiry <= confirmationDate {
            throw WorkBuddyManualValidationError.expiryMustBeFuture
        }

        let used: Decimal?
        let total: Decimal?
        switch companionField {
        case .none:
            used = nil
            total = nil
        case .used:
            let companion = try Self.parseRequired(
                companionText,
                missing: .requiredUsed
            )
            used = companion
            let result = remaining + companion
            guard !result.isNaN, result <= Decimal(Int64.max), result > 0 else {
                throw WorkBuddyManualValidationError.integerOutOfRange
            }
            total = result
        case .total:
            used = nil
            total = try Self.parseRequired(
                companionText,
                missing: .requiredTotal
            )
        case .usedAndTotal:
            used = try Self.parseRequired(
                companionText,
                missing: .requiredUsed
            )
            total = try Self.parseRequired(
                explicitTotalText,
                missing: .requiredTotal
            )
        }

        do {
            let balance = try CreditBalance(
                validatingDecimalRemaining: remaining,
                used: used,
                total: total,
                scope: scope.creditScope,
                planTier: scope.creditPlanTier,
                nextExpiryAt: includesExpiry ? expiry : nil,
                observedAt: confirmationDate,
                provenance: .manualConfirmed(at: confirmationDate)
            )
            return try WorkBuddyManualObservation(
                scope: scope,
                tier: tier,
                balance: balance,
                entryMode: companionField
            )
        } catch is AgentAvailabilityValidationError {
            throw WorkBuddyManualValidationError.invalidManualRecord
        }
    }

    public static func from(_ observation: WorkBuddyManualObservation) -> WorkBuddyManualDraft {
        let entryMode = observation.resolvedEntryMode
        let companionText: String
        switch entryMode {
        case .none:
            companionText = ""
        case .used, .usedAndTotal:
            companionText = observation.balance.used.map(CreditFormatter.editable) ?? ""
        case .total:
            companionText = observation.balance.total.map(CreditFormatter.editable) ?? ""
        }
        return WorkBuddyManualDraft(
            scope: observation.scope,
            tier: observation.tier,
            remainingText: CreditFormatter.editable(observation.balance.remaining),
            companionField: entryMode,
            companionText: companionText,
            explicitTotalText: entryMode == .usedAndTotal
                ? observation.balance.total.map(CreditFormatter.editable) ?? ""
                : "",
            includesExpiry: observation.balance.nextExpiryAt != nil,
            expiry: observation.balance.nextExpiryAt
                ?? observation.balance.observedAt.addingTimeInterval(30 * 24 * 60 * 60)
        )
    }

    private static func parseRequired(
        _ text: String,
        missing: WorkBuddyManualValidationError
    ) throws -> Decimal {
        guard !text.isEmpty else { throw missing }
        guard text.range(
            of: "^[0-9]+(?:\\.[0-9]+)?$",
            options: .regularExpression
        ) != nil else {
            throw WorkBuddyManualValidationError.invalidInteger
        }
        guard let value = CreditDecimalCodec.parseEditable(text),
              value <= Decimal(Int64.max) else {
            throw WorkBuddyManualValidationError.integerOutOfRange
        }
        return value
    }
}
