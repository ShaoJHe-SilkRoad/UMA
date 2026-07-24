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

    public init(
        scope: WorkBuddyManualScope,
        tier: WorkBuddyPlanTier,
        balance: CreditBalance
    ) throws {
        guard balance.scope == scope.creditScope,
              balance.planTier == scope.creditPlanTier,
              case let .manualConfirmed(confirmedAt) = balance.provenance,
              confirmedAt == balance.observedAt else {
            throw WorkBuddyManualValidationError.invalidManualRecord
        }
        self.scope = scope
        self.tier = tier
        self.balance = balance
    }

    func confirming(at date: Date) throws -> WorkBuddyManualObservation {
        try WorkBuddyManualObservation(
            scope: scope,
            tier: tier,
            balance: CreditBalance(
                validatingRemaining: balance.remaining,
                used: balance.used,
                total: balance.total,
                scope: balance.scope,
                planTier: balance.planTier,
                nextExpiryAt: balance.nextExpiryAt,
                observedAt: date,
                provenance: .manualConfirmed(at: date)
            )
        )
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
}

public struct WorkBuddyManualDraft: Equatable, Sendable {
    public var scope: WorkBuddyManualScope
    public var tier: WorkBuddyPlanTier
    public var remainingText: String
    public var companionField: WorkBuddyCreditCompanionField
    public var companionText: String
    public var includesExpiry: Bool
    public var expiry: Date

    public init(
        scope: WorkBuddyManualScope = .unknown,
        tier: WorkBuddyPlanTier = .unknown,
        remainingText: String = "",
        companionField: WorkBuddyCreditCompanionField = .used,
        companionText: String = "",
        includesExpiry: Bool = false,
        expiry: Date = Date().addingTimeInterval(30 * 24 * 60 * 60)
    ) {
        self.scope = scope
        self.tier = tier
        self.remainingText = remainingText
        self.companionField = companionField
        self.companionText = companionText
        self.includesExpiry = includesExpiry
        self.expiry = expiry
    }

    public func validated(at confirmationDate: Date) throws -> WorkBuddyManualObservation {
        let remaining = try Self.parseRequired(
            remainingText,
            missing: .requiredRemaining
        )
        let companion = try companionField == .none
            ? nil
            : Self.parseRequired(
                companionText,
                missing: companionField == .used ? .requiredUsed : .requiredTotal
            )
        if includesExpiry, expiry <= confirmationDate {
            throw WorkBuddyManualValidationError.expiryMustBeFuture
        }

        let used: Int64?
        let total: Int64?
        switch companionField {
        case .none:
            used = nil
            total = nil
        case .used:
            guard let companion else { throw WorkBuddyManualValidationError.requiredUsed }
            used = companion
            let result = remaining.addingReportingOverflow(companion)
            guard !result.overflow, result.partialValue > 0 else {
                throw WorkBuddyManualValidationError.integerOutOfRange
            }
            total = result.partialValue
        case .total:
            guard let companion else { throw WorkBuddyManualValidationError.requiredTotal }
            used = nil
            total = companion
        }

        do {
            let balance = try CreditBalance(
                validatingRemaining: remaining,
                used: used,
                total: total,
                scope: scope.creditScope,
                planTier: scope.creditPlanTier,
                nextExpiryAt: includesExpiry ? expiry : nil,
                observedAt: confirmationDate,
                provenance: .manualConfirmed(at: confirmationDate)
            )
            return try WorkBuddyManualObservation(scope: scope, tier: tier, balance: balance)
        } catch is AgentAvailabilityValidationError {
            throw WorkBuddyManualValidationError.invalidManualRecord
        }
    }

    public static func from(_ observation: WorkBuddyManualObservation) -> WorkBuddyManualDraft {
        WorkBuddyManualDraft(
            scope: observation.scope,
            tier: observation.tier,
            remainingText: String(observation.balance.remaining),
            companionField: observation.balance.used != nil
                ? .used
                : (observation.balance.total == nil ? .none : .total),
            companionText: observation.balance.used.map(String.init)
                ?? observation.balance.total.map(String.init)
                ?? "",
            includesExpiry: observation.balance.nextExpiryAt != nil,
            expiry: observation.balance.nextExpiryAt
                ?? observation.balance.observedAt.addingTimeInterval(30 * 24 * 60 * 60)
        )
    }

    private static func parseRequired(
        _ text: String,
        missing: WorkBuddyManualValidationError
    ) throws -> Int64 {
        guard !text.isEmpty else { throw missing }
        guard text.range(of: "^[0-9]+$", options: .regularExpression) != nil else {
            throw WorkBuddyManualValidationError.invalidInteger
        }
        guard let value = Int64(text) else {
            throw WorkBuddyManualValidationError.integerOutOfRange
        }
        return value
    }
}
