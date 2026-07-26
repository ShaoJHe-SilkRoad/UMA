import Foundation

public enum AgentAvailabilityValidationError: String, Error, Codable, Equatable, Sendable {
    case nonFiniteNumber
    case nonIntegralCredits
    case negativeCredits
    case creditsOutOfRange
    case totalMustBePositive
    case remainingExceedsTotal
    case usedExceedsTotal
    case inconsistentCreditValues
    case arithmeticOverflow
    case percentageOutOfRange
    case unsupportedSchema
}

public struct AgentRemainingPercentage: Codable, Equatable, Sendable {
    public let value: Double

    public init(validating value: Double) throws {
        guard value.isFinite else {
            throw AgentAvailabilityValidationError.nonFiniteNumber
        }
        guard (0...100).contains(value) else {
            throw AgentAvailabilityValidationError.percentageOutOfRange
        }
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(Double.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Remaining percentage must be finite and within 0...100."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public enum CreditUnit: String, Codable, Equatable, Sendable {
    case credits

    public var displayName: String { "Credits" }
}

public struct CreditPoolIdentity: RawRepresentable, Codable, Hashable, Sendable {
    public static let maximumLength = 64

    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.utf8.count <= Self.maximumLength,
              rawValue.range(
            of: "^[a-z][A-Za-z0-9]*(?:\\.[a-z][A-Za-z0-9]*)+$",
            options: .regularExpression
        ) != nil else {
            return nil
        }
        self.rawValue = rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .rawValue)
        guard let validated = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .rawValue,
                in: container,
                debugDescription: "Credit pool identity is malformed or exceeds the length limit."
            )
        }
        self = validated
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }

    public static let buddyAISharedCredits = CreditPoolIdentity(
        rawValue: "buddyAI.sharedCredits"
    )!
}

public enum CreditScopeKind: String, Codable, Equatable, Sendable {
    case buddyAISharedPersonal
    case buddyAIEnterpriseShared
    case buddyAIUnknown
    case other
}

public struct CreditScope: Codable, Equatable, Sendable {
    public let kind: CreditScopeKind
    public let poolIdentity: CreditPoolIdentity

    public init?(kind: CreditScopeKind, poolIdentity: CreditPoolIdentity) {
        switch kind {
        case .buddyAISharedPersonal, .buddyAIEnterpriseShared, .buddyAIUnknown:
            guard poolIdentity == .buddyAISharedCredits else { return nil }
        case .other:
            guard poolIdentity != .buddyAISharedCredits else { return nil }
        }
        self.kind = kind
        self.poolIdentity = poolIdentity
    }

    public static let buddyAISharedPersonal = CreditScope(
        kind: .buddyAISharedPersonal,
        poolIdentity: .buddyAISharedCredits
    )!
    public static let buddyAIEnterpriseShared = CreditScope(
        kind: .buddyAIEnterpriseShared,
        poolIdentity: .buddyAISharedCredits
    )!
    public static let buddyAIUnknown = CreditScope(
        kind: .buddyAIUnknown,
        poolIdentity: .buddyAISharedCredits
    )!

    private enum CodingKeys: String, CodingKey {
        case kind
        case poolIdentity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(CreditScopeKind.self, forKey: .kind)
        let poolIdentity = try container.decode(
            CreditPoolIdentity.self,
            forKey: .poolIdentity
        )
        guard let validated = Self(kind: kind, poolIdentity: poolIdentity) else {
            throw DecodingError.dataCorruptedError(
                forKey: .poolIdentity,
                in: container,
                debugDescription: "Credit scope kind and pool identity do not match."
            )
        }
        self = validated
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(poolIdentity, forKey: .poolIdentity)
    }
}

public enum CreditPlanTier: String, Codable, Equatable, Sendable {
    case personal
    case enterprise
}

public enum AvailabilityProvenance: Codable, Equatable, Sendable {
    case manualConfirmed(at: Date)
    case officialStructured(observedAt: Date)
    case authenticatedAccountWeb(observedAt: Date)

    public var observedAt: Date {
        switch self {
        case let .manualConfirmed(at): at
        case let .officialStructured(observedAt): observedAt
        case let .authenticatedAccountWeb(observedAt): observedAt
        }
    }

    public var isLiveStructuredSource: Bool {
        switch self {
        case .manualConfirmed: false
        case .officialStructured, .authenticatedAccountWeb: true
        }
    }
}

public enum AgentAvailabilitySourceState: String, Codable, Equatable, Sendable {
    case manualConfirmed
    case officialStructured
    case authenticatedAccountWeb
    case unspecified
}

enum CreditDecimalCodec {
    static let maximumPrecision = 38

    static func parseEditable(_ text: String) -> Decimal? {
        guard text.range(
            of: "^[0-9]+(?:\\.[0-9]+)?$",
            options: .regularExpression
        ) != nil,
        precision(of: text) <= maximumPrecision,
        let value = Decimal(
            string: text,
            locale: Locale(identifier: "en_US_POSIX")
        ),
        !value.isNaN else {
            return nil
        }
        return value
    }

    static func parseCanonical(_ text: String) -> Decimal? {
        guard let value = parseEditable(text), canonicalString(value) == text else {
            return nil
        }
        return value
    }

    static func canonicalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func hasSupportedPrecision(_ value: Decimal) -> Bool {
        precision(of: canonicalString(value)) <= maximumPrecision
    }

    private static func precision(of text: String) -> Int {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerDigits = parts[0].drop { $0 == "0" }.count
        let fractionalDigits = parts.count == 2 ? parts[1].count : 0
        return max(1, integerDigits + fractionalDigits)
    }
}

public struct CreditBalance: Codable, Equatable, Sendable {
    public static let schemaVersion = 2
    public static let legacyIntegerSchemaVersion = 1
    public static let maximumDecimalPrecision = CreditDecimalCodec.maximumPrecision
    private static let maximumValue = Decimal(Int64.max)

    public let remaining: Decimal
    public let used: Decimal?
    public let total: Decimal?
    public let unit: CreditUnit
    public let scope: CreditScope
    public let planTier: CreditPlanTier?
    public let nextExpiryAt: Date?
    public let observedAt: Date
    public let provenance: AvailabilityProvenance

    public init(
        validatingRemaining remaining: Int64,
        used: Int64? = nil,
        total: Int64? = nil,
        unit: CreditUnit = .credits,
        scope: CreditScope,
        planTier: CreditPlanTier? = nil,
        nextExpiryAt: Date? = nil,
        observedAt: Date,
        provenance: AvailabilityProvenance
    ) throws {
        try self.init(
            validatingDecimalRemaining: Decimal(remaining),
            used: used.map(Decimal.init),
            total: total.map(Decimal.init),
            unit: unit,
            scope: scope,
            planTier: planTier,
            nextExpiryAt: nextExpiryAt,
            observedAt: observedAt,
            provenance: provenance
        )
    }

    public init(
        validatingDecimalRemaining remaining: Decimal,
        used: Decimal? = nil,
        total: Decimal? = nil,
        unit: CreditUnit = .credits,
        scope: CreditScope,
        planTier: CreditPlanTier? = nil,
        nextExpiryAt: Date? = nil,
        observedAt: Date,
        provenance: AvailabilityProvenance
    ) throws {
        guard !remaining.isNaN,
              used.map({ !$0.isNaN }) ?? true,
              total.map({ !$0.isNaN }) ?? true else {
            throw AgentAvailabilityValidationError.creditsOutOfRange
        }
        guard CreditDecimalCodec.hasSupportedPrecision(remaining),
              used.map(CreditDecimalCodec.hasSupportedPrecision) ?? true,
              total.map(CreditDecimalCodec.hasSupportedPrecision) ?? true else {
            throw AgentAvailabilityValidationError.creditsOutOfRange
        }
        guard remaining >= 0, used.map({ $0 >= 0 }) ?? true else {
            throw AgentAvailabilityValidationError.negativeCredits
        }
        guard remaining <= Self.maximumValue,
              used.map({ $0 <= Self.maximumValue }) ?? true,
              total.map({ $0 <= Self.maximumValue }) ?? true else {
            throw AgentAvailabilityValidationError.creditsOutOfRange
        }
        if let total {
            guard total > 0 else {
                throw AgentAvailabilityValidationError.totalMustBePositive
            }
            guard remaining <= total else {
                throw AgentAvailabilityValidationError.remainingExceedsTotal
            }
            if let used {
                guard used <= total else {
                    throw AgentAvailabilityValidationError.usedExceedsTotal
                }
            }
        }

        if let used {
            let sum = remaining + used
            guard Self.isSupported(sum) else {
                throw AgentAvailabilityValidationError.arithmeticOverflow
            }
            if let total, sum != total {
                throw AgentAvailabilityValidationError.inconsistentCreditValues
            }
        }

        self.remaining = remaining
        self.used = used
        self.total = total
        self.unit = unit
        self.scope = scope
        self.planTier = planTier
        self.nextExpiryAt = nextExpiryAt
        self.observedAt = observedAt
        self.provenance = provenance
    }

    public init(
        validatingRemaining remaining: Double,
        used: Double? = nil,
        total: Double? = nil,
        unit: CreditUnit = .credits,
        scope: CreditScope,
        planTier: CreditPlanTier? = nil,
        nextExpiryAt: Date? = nil,
        observedAt: Date,
        provenance: AvailabilityProvenance
    ) throws {
        try self.init(
            validatingDecimalRemaining: Self.exactCredits(remaining),
            used: try used.map(Self.exactCredits),
            total: try total.map(Self.exactCredits),
            unit: unit,
            scope: scope,
            planTier: planTier,
            nextExpiryAt: nextExpiryAt,
            observedAt: observedAt,
            provenance: provenance
        )
    }

    public var derivedTotal: Decimal? {
        if let total { return total }
        guard let used else { return nil }
        let sum = remaining + used
        guard Self.isSupported(sum), sum > 0 else { return nil }
        return sum
    }

    public var normalizedRemainingFraction: Double? {
        guard let denominator = derivedTotal, denominator > 0 else { return nil }
        return NSDecimalNumber(decimal: remaining).doubleValue
            / NSDecimalNumber(decimal: denominator).doubleValue
    }

    public var isExhausted: Bool { remaining == 0 }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case remaining
        case used
        case total
        case unit
        case scope
        case planTier
        case nextExpiryAt
        case observedAt
        case provenance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.legacyIntegerSchemaVersion || version == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported Credit balance schema."
            )
        }

        do {
            let unit = try container.decode(CreditUnit.self, forKey: .unit)
            let scope = try container.decode(CreditScope.self, forKey: .scope)
            let planTier = try container.decodeIfPresent(
                CreditPlanTier.self,
                forKey: .planTier
            )
            let nextExpiryAt = try container.decodeIfPresent(
                Date.self,
                forKey: .nextExpiryAt
            )
            let observedAt = try container.decode(Date.self, forKey: .observedAt)
            let provenance = try container.decode(
                AvailabilityProvenance.self,
                forKey: .provenance
            )

            if version == Self.legacyIntegerSchemaVersion {
                try self.init(
                    validatingRemaining: container.decode(Int64.self, forKey: .remaining),
                    used: container.decodeIfPresent(Int64.self, forKey: .used),
                    total: container.decodeIfPresent(Int64.self, forKey: .total),
                    unit: unit,
                    scope: scope,
                    planTier: planTier,
                    nextExpiryAt: nextExpiryAt,
                    observedAt: observedAt,
                    provenance: provenance
                )
            } else {
                let remainingText = try container.decode(String.self, forKey: .remaining)
                let usedText = try container.decodeIfPresent(String.self, forKey: .used)
                let totalText = try container.decodeIfPresent(String.self, forKey: .total)
                guard let remaining = CreditDecimalCodec.parseCanonical(remainingText) else {
                    throw AgentAvailabilityValidationError.creditsOutOfRange
                }
                let used: Decimal?
                if let usedText {
                    guard let parsed = CreditDecimalCodec.parseCanonical(usedText) else {
                        throw AgentAvailabilityValidationError.creditsOutOfRange
                    }
                    used = parsed
                } else {
                    used = nil
                }
                let total: Decimal?
                if let totalText {
                    guard let parsed = CreditDecimalCodec.parseCanonical(totalText) else {
                        throw AgentAvailabilityValidationError.creditsOutOfRange
                    }
                    total = parsed
                } else {
                    total = nil
                }
                try self.init(
                    validatingDecimalRemaining: remaining,
                    used: used,
                    total: total,
                    unit: unit,
                    scope: scope,
                    planTier: planTier,
                    nextExpiryAt: nextExpiryAt,
                    observedAt: observedAt,
                    provenance: provenance
                )
            }
        } catch let error as AgentAvailabilityValidationError {
            throw DecodingError.dataCorruptedError(
                forKey: .remaining,
                in: container,
                debugDescription: "Invalid Credit balance: \(error.rawValue)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(CreditDecimalCodec.canonicalString(remaining), forKey: .remaining)
        try container.encodeIfPresent(
            used.map(CreditDecimalCodec.canonicalString),
            forKey: .used
        )
        try container.encodeIfPresent(
            total.map(CreditDecimalCodec.canonicalString),
            forKey: .total
        )
        try container.encode(unit, forKey: .unit)
        try container.encode(scope, forKey: .scope)
        try container.encodeIfPresent(planTier, forKey: .planTier)
        try container.encodeIfPresent(nextExpiryAt, forKey: .nextExpiryAt)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(provenance, forKey: .provenance)
    }

    private static func exactCredits(_ value: Double) throws -> Decimal {
        guard value.isFinite else {
            throw AgentAvailabilityValidationError.nonFiniteNumber
        }
        guard value >= 0 else {
            throw AgentAvailabilityValidationError.negativeCredits
        }
        guard let exact = CreditDecimalCodec.parseEditable(String(value)),
              isSupported(exact) else {
            throw AgentAvailabilityValidationError.creditsOutOfRange
        }
        return exact
    }

    private static func isSupported(_ value: Decimal) -> Bool {
        !value.isNaN && value >= 0 && value <= maximumValue
    }
}

public enum AgentAvailabilityValue: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    case percentage(AgentRemainingPercentage)
    case credits(CreditBalance)
    case unlimited
    case unavailable
    case invalid(reason: AgentAvailabilityValidationError)

    public static func validatingPercentage(_ value: Double) -> AgentAvailabilityValue {
        do {
            return .percentage(try AgentRemainingPercentage(validating: value))
        } catch let error as AgentAvailabilityValidationError {
            return .invalid(reason: error)
        } catch {
            return .invalid(reason: .percentageOutOfRange)
        }
    }

    public static func validatingCredits(
        remaining: Double,
        used: Double? = nil,
        total: Double? = nil,
        unit: CreditUnit = .credits,
        scope: CreditScope,
        planTier: CreditPlanTier? = nil,
        nextExpiryAt: Date? = nil,
        observedAt: Date,
        provenance: AvailabilityProvenance
    ) -> AgentAvailabilityValue {
        do {
            return .credits(
                try CreditBalance(
                    validatingRemaining: remaining,
                    used: used,
                    total: total,
                    unit: unit,
                    scope: scope,
                    planTier: planTier,
                    nextExpiryAt: nextExpiryAt,
                    observedAt: observedAt,
                    provenance: provenance
                )
            )
        } catch let error as AgentAvailabilityValidationError {
            return .invalid(reason: error)
        } catch {
            return .invalid(reason: .creditsOutOfRange)
        }
    }

    public var normalizedRemainingFraction: Double? {
        switch self {
        case let .percentage(percentage): percentage.value / 100
        case let .credits(balance): balance.normalizedRemainingFraction
        case .unlimited, .unavailable, .invalid: nil
        }
    }

    public var creditBalance: CreditBalance? {
        guard case let .credits(balance) = self else { return nil }
        return balance
    }

    public var sourceState: AgentAvailabilitySourceState {
        guard case let .credits(balance) = self else { return .unspecified }
        switch balance.provenance {
        case .manualConfirmed: return .manualConfirmed
        case .officialStructured: return .officialStructured
        case .authenticatedAccountWeb: return .authenticatedAccountWeb
        }
    }

    private enum Kind: String, Codable {
        case percentage
        case credits
        case unlimited
        case unavailable
        case invalid
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case percentage
        case balance
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported availability value schema."
            )
        }

        switch try container.decode(Kind.self, forKey: .kind) {
        case .percentage:
            self = .percentage(try container.decode(AgentRemainingPercentage.self, forKey: .percentage))
        case .credits:
            self = .credits(try container.decode(CreditBalance.self, forKey: .balance))
        case .unlimited:
            self = .unlimited
        case .unavailable:
            self = .unavailable
        case .invalid:
            self = .invalid(
                reason: try container.decode(AgentAvailabilityValidationError.self, forKey: .reason)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        switch self {
        case let .percentage(percentage):
            try container.encode(Kind.percentage, forKey: .kind)
            try container.encode(percentage, forKey: .percentage)
        case let .credits(balance):
            try container.encode(Kind.credits, forKey: .kind)
            try container.encode(balance, forKey: .balance)
        case .unlimited:
            try container.encode(Kind.unlimited, forKey: .kind)
        case .unavailable:
            try container.encode(Kind.unavailable, forKey: .kind)
        case let .invalid(reason):
            try container.encode(Kind.invalid, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

public enum AgentAvailabilitySeverity: String, Codable, Equatable, Sendable {
    case available
    case warning
    case critical
    case exhausted
    case neutral
    case invalid
}

public enum CreditFormatter {
    public static func compact(_ value: Int64) -> String {
        compact(Decimal(value))
    }

    public static func compact(_ value: Decimal) -> String {
        if value < 1_000 {
            let rounded = roundHalfUp(value, scale: 0)
            if rounded >= 1_000 {
                return "1k"
            }
            return decimalString(rounded)
        }

        if value < 1_000_000 {
            let roundedThousands = roundHalfUp(value / 1_000, scale: 1)
            if roundedThousands >= 1_000 {
                return "1M"
            }
            return "\(decimalString(roundedThousands))k"
        }

        let roundedMillions = roundHalfUp(value / 1_000_000, scale: 1)
        return "\(decimalString(roundedMillions))M"
    }

    public static func exact(_ value: Int64, language: AppLanguage) -> String {
        exact(Decimal(value), language: language)
    }

    public static func exact(_ value: Decimal, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 38
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? decimalString(value)
    }

    public static func accessibilityRemaining(_ value: Int64, language: AppLanguage) -> String {
        accessibilityRemaining(Decimal(value), language: language)
    }

    public static func accessibilityRemaining(_ value: Decimal, language: AppLanguage) -> String {
        let exactValue = exact(value, language: language)
        switch language {
        case .english:
            return "\(exactValue) Credits remaining"
        case .simplifiedChinese:
            return "剩余 \(exactValue) Credits"
        }
    }

    public static func editable(_ value: Decimal) -> String {
        decimalString(value)
    }

    private static func roundHalfUp(_ value: Decimal, scale: Int) -> Decimal {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, scale, .plain)
        return rounded
    }

    private static func decimalString(_ value: Decimal) -> String {
        CreditDecimalCodec.canonicalString(value)
    }
}
