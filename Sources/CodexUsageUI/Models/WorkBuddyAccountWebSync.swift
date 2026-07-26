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
    case malformedCredits
    case ambiguousCredits
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

struct WorkBuddyAccountWebSanitizedRow: Codable, Equatable, Sendable {
    let remaining: String
    let used: String?
    let total: String?
}

struct WorkBuddyAccountWebExtractionPayload: Codable, Equatable, Sendable {
    let extractorVersion: Int
    let rows: [WorkBuddyAccountWebSanitizedRow]
}

struct WorkBuddyAccountWebReading: Equatable, Sendable {
    static let extractorVersion = 1

    let balance: CreditBalance
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
        guard payload.extractorVersion == WorkBuddyAccountWebReading.extractorVersion,
              (1...8).contains(payload.rows.count)
        else {
            return .failure(.malformedCredits)
        }

        let tuples = payload.rows.map {
            [$0.remaining, $0.used ?? "", $0.total ?? ""].joined(separator: "|")
        }
        guard Set(tuples).count == tuples.count else {
            return .failure(.ambiguousCredits)
        }

        var remaining = Decimal.zero
        var used = Decimal.zero
        var total = Decimal.zero
        var everyRowHasUsed = true
        var everyRowHasTotal = true

        for row in payload.rows {
            guard let rowRemaining = CreditDecimalCodec.parseCanonical(row.remaining)
            else {
                return .failure(.malformedCredits)
            }
            remaining += rowRemaining

            if let usedText = row.used,
               let rowUsed = CreditDecimalCodec.parseCanonical(usedText) {
                used += rowUsed
            } else if row.used == nil {
                everyRowHasUsed = false
            } else {
                return .failure(.malformedCredits)
            }

            if let totalText = row.total,
               let rowTotal = CreditDecimalCodec.parseCanonical(totalText) {
                total += rowTotal
            } else if row.total == nil {
                everyRowHasTotal = false
            } else {
                return .failure(.malformedCredits)
            }

            if (row.used == nil) != (row.total == nil) {
                return .failure(.ambiguousCredits)
            }
        }

        do {
            let balance = try CreditBalance(
                validatingDecimalRemaining: remaining,
                used: everyRowHasUsed ? used : nil,
                total: everyRowHasTotal ? total : nil,
                scope: .buddyAIUnknown,
                observedAt: observedAt,
                provenance: .authenticatedAccountWeb(observedAt: observedAt)
            )
            return .success(
                WorkBuddyAccountWebReading(
                    balance: balance,
                    extractorVersion: payload.extractorVersion
                )
            )
        } catch {
            return .failure(.ambiguousCredits)
        }
    }
}
