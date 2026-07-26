import Foundation

public enum WorkBuddyAccountWebSessionMode:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable {
    case persistent
    case nonpersistent

    public var id: String { rawValue }
}

public enum WorkBuddyAccountWebFlowState: Equatable, Sendable {
    case idle
    case consentRequired
    case opening
    case signInRequired
    case readyToSync
    case synchronizing
    case connected
    case failed(WorkBuddyAccountWebFailure)
}

public enum WorkBuddyAccountWebFailure: String, Error, Equatable, Sendable {
    case consentRequired
    case invalidNavigation
    case authenticationRequired
    case unexpectedPage
    case pageNotStabilized
    case incompletePoolSections
    case malformedCredits
    case ambiguousCredits
    case invalidCreditPool
    case duplicateCreditPool
    case ambiguousAccountBalance
    case accountBalanceReconciliationFailed
    case timedOut
    case webContentUnavailable
    case websiteDataClearFailed
}

struct WorkBuddyAccountWebConsentRecord: Codable, Equatable, Sendable {
    static let currentDisclosureVersion = 1

    let disclosureVersion: Int
    let acceptedAt: Date
    let sessionMode: WorkBuddyAccountWebSessionMode
}

enum WorkBuddyCreditPoolKind: String, Codable, CaseIterable, Sendable {
    case subscriptionBase
    case subscriptionBonus
    case addOn
    case benefitGift
}

enum WorkBuddyCreditPoolSection: String, Codable, CaseIterable, Sendable {
    case subscription
    case addOn
    case benefitGift
}

enum WorkBuddyCreditPoolSafeStatus: String, Codable, Sendable {
    case available
    case active
    case exhausted
    case expired
    case future
    case unavailable
    case historical
    case ambiguous
}

enum WorkBuddyAccountSource: String, Codable, Sendable {
    case authenticatedAccountWeb
}

enum WorkBuddyAccountCreditRules {
    static let maximum = Decimal(string: "999999999999.99")!
    static let reconciliationTolerance = Decimal(string: "0.01")!

    static func parseCanonical(_ text: String) -> Decimal? {
        guard text.range(
            of: "^(?:0|[1-9][0-9]*)(?:\\.[0-9]{1,2})?$",
            options: .regularExpression
        ) != nil,
        let value = CreditDecimalCodec.parseCanonical(text),
        isValid(value)
        else {
            return nil
        }
        return value
    }

    static func isValid(_ value: Decimal) -> Bool {
        guard !value.isNaN, value >= 0, value <= maximum else { return false }
        let canonical = CreditDecimalCodec.canonicalString(value)
        guard canonical.range(
            of: "^(?:0|[1-9][0-9]*)(?:\\.[0-9]{1,2})?$",
            options: .regularExpression
        ) != nil else {
            return false
        }
        return true
    }

    static func absoluteDifference(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }
}

struct WorkBuddyAccountWebSanitizedPool: Codable, Equatable, Sendable {
    let stablePageID: String?
    let kind: WorkBuddyCreditPoolKind
    let used: String
    let total: String
    let displayedRemaining: String?
    let effectiveAtMilliseconds: Int64?
    let expiresAtMilliseconds: Int64?
    let pageStatus: WorkBuddyCreditPoolSafeStatus
}

struct WorkBuddyAccountWebExtractionPayload: Codable, Equatable, Sendable {
    let extractorVersion: Int
    let discoveredSections: [WorkBuddyCreditPoolSection]
    let subscriptionPools: [WorkBuddyAccountWebSanitizedPool]
    let addOnPools: [WorkBuddyAccountWebSanitizedPool]
    let benefitGiftPools: [WorkBuddyAccountWebSanitizedPool]
    let authoritativePageBalances: [String]
}

struct WorkBuddyCreditPool: Equatable, Sendable, Codable {
    let stablePageID: String?
    let kind: WorkBuddyCreditPoolKind
    let used: Decimal
    let total: Decimal
    let displayedRemaining: Decimal?
    let calculatedRemaining: Decimal
    let effectiveAt: Date?
    let expiresAt: Date?
    let pageStatus: WorkBuddyCreditPoolSafeStatus

    private enum CodingKeys: String, CodingKey {
        case stablePageID
        case kind
        case used
        case total
        case displayedRemaining
        case calculatedRemaining
        case effectiveAt
        case expiresAt
        case pageStatus
    }

    init(
        stablePageID: String?,
        kind: WorkBuddyCreditPoolKind,
        used: Decimal,
        total: Decimal,
        displayedRemaining: Decimal?,
        calculatedRemaining: Decimal,
        effectiveAt: Date?,
        expiresAt: Date?,
        pageStatus: WorkBuddyCreditPoolSafeStatus
    ) {
        self.stablePageID = stablePageID
        self.kind = kind
        self.used = used
        self.total = total
        self.displayedRemaining = displayedRemaining
        self.calculatedRemaining = calculatedRemaining
        self.effectiveAt = effectiveAt
        self.expiresAt = expiresAt
        self.pageStatus = pageStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let usedText = try container.decode(String.self, forKey: .used)
        let totalText = try container.decode(String.self, forKey: .total)
        let displayedText = try container.decodeIfPresent(
            String.self,
            forKey: .displayedRemaining
        )
        let calculatedText = try container.decode(
            String.self,
            forKey: .calculatedRemaining
        )
        guard let used = WorkBuddyAccountCreditRules.parseCanonical(usedText),
              let total = WorkBuddyAccountCreditRules.parseCanonical(totalText),
              let calculated = WorkBuddyAccountCreditRules.parseCanonical(
                calculatedText
              )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .used,
                in: container,
                debugDescription: "Invalid canonical Credit value."
            )
        }
        let displayed: Decimal?
        if let displayedText {
            guard let value = WorkBuddyAccountCreditRules.parseCanonical(
                displayedText
            ) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .displayedRemaining,
                    in: container,
                    debugDescription: "Invalid canonical Credit value."
                )
            }
            displayed = value
        } else {
            displayed = nil
        }
        let stablePageID = try container.decodeIfPresent(
            String.self,
            forKey: .stablePageID
        )
        let effectiveAt = try container.decodeIfPresent(
            Date.self,
            forKey: .effectiveAt
        )
        let expiresAt = try container.decodeIfPresent(
            Date.self,
            forKey: .expiresAt
        )
        let hasInvalidDateRange: Bool
        if let effectiveAt, let expiresAt {
            hasInvalidDateRange = effectiveAt >= expiresAt
        } else {
            hasInvalidDateRange = false
        }
        guard stablePageID.map({
            $0.range(
                of: "^[a-z0-9][a-z0-9-]{0,63}$",
                options: .regularExpression
            ) != nil
        }) ?? true,
        total > 0,
        used <= total,
        calculated == total - used,
        displayed.map({
            WorkBuddyAccountCreditRules.absoluteDifference($0, calculated)
                <= WorkBuddyAccountCreditRules.reconciliationTolerance
        }) ?? true,
        !hasInvalidDateRange
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .calculatedRemaining,
                in: container,
                debugDescription: "Inconsistent sanitized Credit pool."
            )
        }
        self.init(
            stablePageID: stablePageID,
            kind: try container.decode(WorkBuddyCreditPoolKind.self, forKey: .kind),
            used: used,
            total: total,
            displayedRemaining: displayed,
            calculatedRemaining: calculated,
            effectiveAt: effectiveAt,
            expiresAt: expiresAt,
            pageStatus: try container.decode(
                WorkBuddyCreditPoolSafeStatus.self,
                forKey: .pageStatus
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(stablePageID, forKey: .stablePageID)
        try container.encode(kind, forKey: .kind)
        try container.encode(CreditDecimalCodec.canonicalString(used), forKey: .used)
        try container.encode(CreditDecimalCodec.canonicalString(total), forKey: .total)
        try container.encodeIfPresent(
            displayedRemaining.map(CreditDecimalCodec.canonicalString),
            forKey: .displayedRemaining
        )
        try container.encode(
            CreditDecimalCodec.canonicalString(calculatedRemaining),
            forKey: .calculatedRemaining
        )
        try container.encodeIfPresent(effectiveAt, forKey: .effectiveAt)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encode(pageStatus, forKey: .pageStatus)
    }
}

struct WorkBuddyAccountCreditSnapshot: Equatable, Sendable, Codable {
    let subscriptionRemaining: Decimal
    let addOnRemaining: Decimal
    let benefitGiftRemaining: Decimal
    let calculatedTotalRemaining: Decimal
    let authoritativePageBalance: Decimal?
    let observedAt: Date
    let source: WorkBuddyAccountSource
    let extractorVersion: String
    let includedPoolCount: Int

    private enum CodingKeys: String, CodingKey {
        case subscriptionRemaining
        case addOnRemaining
        case benefitGiftRemaining
        case calculatedTotalRemaining
        case authoritativePageBalance
        case observedAt
        case source
        case extractorVersion
        case includedPoolCount
    }

    init(
        subscriptionRemaining: Decimal,
        addOnRemaining: Decimal,
        benefitGiftRemaining: Decimal,
        calculatedTotalRemaining: Decimal,
        authoritativePageBalance: Decimal?,
        observedAt: Date,
        source: WorkBuddyAccountSource,
        extractorVersion: String,
        includedPoolCount: Int
    ) {
        self.subscriptionRemaining = subscriptionRemaining
        self.addOnRemaining = addOnRemaining
        self.benefitGiftRemaining = benefitGiftRemaining
        self.calculatedTotalRemaining = calculatedTotalRemaining
        self.authoritativePageBalance = authoritativePageBalance
        self.observedAt = observedAt
        self.source = source
        self.extractorVersion = extractorVersion
        self.includedPoolCount = includedPoolCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decimal(_ key: CodingKeys) throws -> Decimal {
            let text = try container.decode(String.self, forKey: key)
            guard let value = WorkBuddyAccountCreditRules.parseCanonical(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Invalid canonical Credit value."
                )
            }
            return value
        }
        let authoritativeText = try container.decodeIfPresent(
            String.self,
            forKey: .authoritativePageBalance
        )
        let authoritative: Decimal?
        if let authoritativeText {
            guard let value = WorkBuddyAccountCreditRules.parseCanonical(
                authoritativeText
            ) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .authoritativePageBalance,
                    in: container,
                    debugDescription: "Invalid canonical Credit value."
                )
            }
            authoritative = value
        } else {
            authoritative = nil
        }
        let subscription = try decimal(.subscriptionRemaining)
        let addOn = try decimal(.addOnRemaining)
        let benefitGift = try decimal(.benefitGiftRemaining)
        let calculated = try decimal(.calculatedTotalRemaining)
        guard subscription + addOn + benefitGift == calculated,
              authoritative.map({
                  WorkBuddyAccountCreditRules.absoluteDifference($0, calculated)
                    <= WorkBuddyAccountCreditRules.reconciliationTolerance
              }) ?? true
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .calculatedTotalRemaining,
                in: container,
                debugDescription: "Inconsistent account Credit snapshot."
            )
        }
        self.init(
            subscriptionRemaining: subscription,
            addOnRemaining: addOn,
            benefitGiftRemaining: benefitGift,
            calculatedTotalRemaining: calculated,
            authoritativePageBalance: authoritative,
            observedAt: try container.decode(Date.self, forKey: .observedAt),
            source: try container.decode(WorkBuddyAccountSource.self, forKey: .source),
            extractorVersion: try container.decode(
                String.self,
                forKey: .extractorVersion
            ),
            includedPoolCount: try container.decode(
                Int.self,
                forKey: .includedPoolCount
            )
        )
    }

    func encode(to encoder: Encoder) throws {
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
        try container.encodeIfPresent(
            authoritativePageBalance.map(CreditDecimalCodec.canonicalString),
            forKey: .authoritativePageBalance
        )
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(source, forKey: .source)
        try container.encode(extractorVersion, forKey: .extractorVersion)
        try container.encode(includedPoolCount, forKey: .includedPoolCount)
    }
}

struct WorkBuddyAccountWebReading: Equatable, Sendable {
    static let extractorVersion = 2

    let balance: CreditBalance
    let creditSnapshot: WorkBuddyAccountCreditSnapshot
    let extractorVersion: Int

    var observedAt: Date { balance.observedAt }
}

enum WorkBuddyAccountWebReadResult: Equatable, Sendable {
    case success(WorkBuddyAccountWebReading)
    case authenticationRequired
    case failure(WorkBuddyAccountWebFailure)
}

enum WorkBuddyAccountWebNavigationDecision: Equatable, Sendable {
    case allow
    case confirmExternalHost(String)
    case cancel
}

enum WorkBuddyAccountWebPolicy {
    static let officialHost = "www.workbuddy.cn"
    static let usagePath = "/profile/plans-usage"
    static let usageURL = URL(
        string: "https://www.workbuddy.cn/profile/plans-usage"
    )!

    static func isExactUsagePage(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == officialHost,
              url.path == usagePath,
              url.query == nil,
              url.fragment == nil
        else { return false }
        return true
    }

    static func navigationDecision(
        for url: URL?,
        isMainFrame: Bool
    ) -> WorkBuddyAccountWebNavigationDecision {
        _ = isMainFrame
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return .cancel
        }
        if host == officialHost {
            return .allow
        }
        return .confirmExternalHost(host)
    }
}

enum WorkBuddyAccountWebExtractor {
    static func validate(
        _ payload: WorkBuddyAccountWebExtractionPayload,
        observedAt: Date
    ) -> WorkBuddyAccountWebReadResult {
        guard payload.extractorVersion == WorkBuddyAccountWebReading.extractorVersion
        else {
            return .failure(.malformedCredits)
        }

        guard payload.discoveredSections.count
                == WorkBuddyCreditPoolSection.allCases.count,
              Set(payload.discoveredSections)
                == Set(WorkBuddyCreditPoolSection.allCases),
              !payload.subscriptionPools.isEmpty,
              payload.subscriptionPools.count <= 16,
              payload.addOnPools.count <= 32,
              payload.benefitGiftPools.count <= 64
        else {
            return .failure(.incompletePoolSections)
        }

        guard payload.authoritativePageBalances.count <= 1 else {
            return .failure(.ambiguousAccountBalance)
        }

        let sections: [
            (WorkBuddyCreditPoolSection, [WorkBuddyAccountWebSanitizedPool])
        ] = [
            (.subscription, payload.subscriptionPools),
            (.addOn, payload.addOnPools),
            (.benefitGift, payload.benefitGiftPools)
        ]

        var pools: [WorkBuddyCreditPool] = []
        var identities = Set<String>()
        for (section, rows) in sections {
            for row in rows {
                guard kind(row.kind, belongsTo: section) else {
                    return .failure(.invalidCreditPool)
                }
                guard let pool = validatedPool(row, observedAt: observedAt)
                else {
                    return .failure(.invalidCreditPool)
                }
                let identity = stableIdentity(for: pool)
                guard identities.insert(identity).inserted else {
                    return .failure(.duplicateCreditPool)
                }
                if isEligible(pool, observedAt: observedAt) {
                    pools.append(pool)
                }
            }
        }

        let subscription = sum(
            pools.filter {
                $0.kind == .subscriptionBase || $0.kind == .subscriptionBonus
            }.map(\.calculatedRemaining)
        )
        let addOn = sum(
            pools.filter { $0.kind == .addOn }.map(\.calculatedRemaining)
        )
        let benefitGift = sum(
            pools.filter { $0.kind == .benefitGift }.map(\.calculatedRemaining)
        )
        guard let subscription,
              let addOn,
              let benefitGift,
              let total = sum([subscription, addOn, benefitGift])
        else {
            return .failure(.invalidCreditPool)
        }

        let authoritative: Decimal?
        if let text = payload.authoritativePageBalances.first {
            guard let parsed = WorkBuddyAccountCreditRules.parseCanonical(text) else {
                return .failure(.malformedCredits)
            }
            guard WorkBuddyAccountCreditRules.absoluteDifference(parsed, total)
                    <= WorkBuddyAccountCreditRules.reconciliationTolerance
            else {
                return .failure(.accountBalanceReconciliationFailed)
            }
            authoritative = parsed
        } else {
            authoritative = nil
        }

        do {
            let balance = try CreditBalance(
                validatingDecimalRemaining: total,
                used: nil,
                total: nil,
                scope: .buddyAIUnknown,
                observedAt: observedAt,
                provenance: .authenticatedAccountWeb(observedAt: observedAt)
            )
            let snapshot = WorkBuddyAccountCreditSnapshot(
                subscriptionRemaining: subscription,
                addOnRemaining: addOn,
                benefitGiftRemaining: benefitGift,
                calculatedTotalRemaining: total,
                authoritativePageBalance: authoritative,
                observedAt: observedAt,
                source: .authenticatedAccountWeb,
                extractorVersion: String(payload.extractorVersion),
                includedPoolCount: pools.count
            )
            return .success(
                WorkBuddyAccountWebReading(
                    balance: balance,
                    creditSnapshot: snapshot,
                    extractorVersion: payload.extractorVersion
                )
            )
        } catch {
            return .failure(.invalidCreditPool)
        }
    }

    private static func kind(
        _ kind: WorkBuddyCreditPoolKind,
        belongsTo section: WorkBuddyCreditPoolSection
    ) -> Bool {
        switch section {
        case .subscription:
            kind == .subscriptionBase || kind == .subscriptionBonus
        case .addOn:
            kind == .addOn
        case .benefitGift:
            kind == .benefitGift
        }
    }

    private static func validatedPool(
        _ row: WorkBuddyAccountWebSanitizedPool,
        observedAt: Date
    ) -> WorkBuddyCreditPool? {
        if let stablePageID = row.stablePageID,
           stablePageID.range(
               of: "^[a-z0-9][a-z0-9-]{0,63}$",
               options: .regularExpression
           ) == nil {
            return nil
        }
        guard row.pageStatus != .ambiguous,
              let used = WorkBuddyAccountCreditRules.parseCanonical(row.used),
              let total = WorkBuddyAccountCreditRules.parseCanonical(row.total),
              total > 0,
              used <= total
        else {
            return nil
        }
        let remaining = total - used
        guard WorkBuddyAccountCreditRules.isValid(remaining) else { return nil }

        let displayed: Decimal?
        if let displayedText = row.displayedRemaining {
            guard let parsed = WorkBuddyAccountCreditRules.parseCanonical(
                displayedText
            ), WorkBuddyAccountCreditRules.absoluteDifference(parsed, remaining)
                <= WorkBuddyAccountCreditRules.reconciliationTolerance
            else {
                return nil
            }
            displayed = parsed
        } else {
            displayed = nil
        }

        let effectiveAt = row.effectiveAtMilliseconds.map {
            Date(timeIntervalSince1970: TimeInterval($0) / 1_000)
        }
        let expiresAt = row.expiresAtMilliseconds.map {
            Date(timeIntervalSince1970: TimeInterval($0) / 1_000)
        }
        if let effectiveAt, let expiresAt, effectiveAt >= expiresAt {
            return nil
        }
        _ = observedAt
        return WorkBuddyCreditPool(
            stablePageID: row.stablePageID,
            kind: row.kind,
            used: used,
            total: total,
            displayedRemaining: displayed,
            calculatedRemaining: remaining,
            effectiveAt: effectiveAt,
            expiresAt: expiresAt,
            pageStatus: row.pageStatus
        )
    }

    private static func isEligible(
        _ pool: WorkBuddyCreditPool,
        observedAt: Date
    ) -> Bool {
        switch pool.pageStatus {
        case .available, .active, .exhausted:
            break
        case .expired, .future, .unavailable, .historical:
            return false
        case .ambiguous:
            return false
        }
        if let effectiveAt = pool.effectiveAt, effectiveAt > observedAt {
            return false
        }
        if let expiresAt = pool.expiresAt, expiresAt <= observedAt {
            return false
        }
        return true
    }

    private static func stableIdentity(for pool: WorkBuddyCreditPool) -> String {
        if let stablePageID = pool.stablePageID {
            return "\(pool.kind.rawValue)|id:\(stablePageID)"
        }
        return [
            pool.kind.rawValue,
            CreditDecimalCodec.canonicalString(pool.used),
            CreditDecimalCodec.canonicalString(pool.total),
            pool.effectiveAt.map { String(Int64($0.timeIntervalSince1970 * 1_000)) }
                ?? "",
            pool.expiresAt.map { String(Int64($0.timeIntervalSince1970 * 1_000)) }
                ?? "",
            pool.pageStatus.rawValue
        ].joined(separator: "|")
    }

    private static func sum(_ values: [Decimal]) -> Decimal? {
        var total = Decimal.zero
        for value in values {
            let next = total + value
            guard WorkBuddyAccountCreditRules.isValid(next) else { return nil }
            total = next
        }
        return total
    }
}
