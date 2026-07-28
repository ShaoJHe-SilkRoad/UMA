import Foundation

enum ManusCreditsDecodingError: Error, Equatable, Sendable {
    case unsuccessfulEnvelope
    case invalidCredit
    case invalidRefreshInterval
    case invalidRefreshTimestamp
}

enum ManusRefreshInterval: String, Codable, Equatable, Sendable {
    case daily
    case weekly
    case none = ""
}

struct ManusCreditsSnapshot: Equatable, Sendable {
    let totalCredits: Int64
    let freeCredits: Int64?
    let periodicCredits: Int64?
    let addOnCredits: Int64?
    let proMonthlyCredits: Int64?
    let eventCredits: Int64?
    let refreshCredits: Int64?
    let maxRefreshCredits: Int64?
    let nextRefreshAt: Date?
    let refreshInterval: ManusRefreshInterval?

    var creditDetails: AgentCreditDetailsSnapshot {
        let values: [(AgentCreditDetailKind, Int64?)] = [
            (.free, freeCredits),
            (.periodic, periodicCredits),
            (.addOn, addOnCredits),
            (.event, eventCredits),
            (.refresh, refreshCredits),
            (.monthlyQuota, proMonthlyCredits),
            (.maximumRefresh, maxRefreshCredits),
        ]
        return AgentCreditDetailsSnapshot(
            details: values.compactMap { kind, value in
                value.map { AgentCreditDetail(kind: kind, credits: $0) }
            },
            nextRefreshAt: nextRefreshAt,
            refreshInterval: refreshInterval?.rawValue
        )
    }
}

enum ManusCreditsDecoder {
    static let maximumDocumentedCredit = Int64(Int32.max)
    static let earliestPlausibleRefresh = Date(
        timeIntervalSince1970: 1_577_836_800
    )
    static let latestPlausibleRefresh = Date(
        timeIntervalSince1970: 4_102_444_800
    )

    static func decode(_ data: Data) throws -> ManusCreditsSnapshot {
        let envelope = try JSONDecoder().decode(SuccessEnvelope.self, from: data)
        guard envelope.ok else {
            throw ManusCreditsDecodingError.unsuccessfulEnvelope
        }
        return try envelope.data.validated()
    }

    static func safeProviderFailure(in data: Data) -> ManusCreditsClientFailure? {
        guard let envelope = try? JSONDecoder().decode(
            ErrorEnvelope.self,
            from: data
        ), !envelope.ok else {
            return nil
        }
        return switch envelope.error.code {
        case "permission_denied", "unauthorized", "invalid_api_key":
            .authentication
        case "rate_limited":
            .rateLimited
        default:
            .server
        }
    }

    private struct SuccessEnvelope: Decodable {
        let ok: Bool
        let data: Payload
    }

    private struct ErrorEnvelope: Decodable {
        let ok: Bool
        let error: ErrorPayload
    }

    private struct ErrorPayload: Decodable {
        let code: String
    }

    private struct Payload: Decodable {
        let totalCredits: Int64
        let freeCredits: Int64?
        let periodicCredits: Int64?
        let addOnCredits: Int64?
        let proMonthlyCredits: Int64?
        let eventCredits: Int64?
        let refreshCredits: Int64?
        let maxRefreshCredits: Int64?
        let nextRefreshTime: Int64?
        let refreshInterval: String?

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case freeCredits = "free_credits"
            case periodicCredits = "periodic_credits"
            case addOnCredits = "addon_credits"
            case proMonthlyCredits = "pro_monthly_credits"
            case eventCredits = "event_credits"
            case refreshCredits = "refresh_credits"
            case maxRefreshCredits = "max_refresh_credits"
            case nextRefreshTime = "next_refresh_time"
            case refreshInterval = "refresh_interval"
        }

        func validated() throws -> ManusCreditsSnapshot {
            let documentedCredits = [
                totalCredits,
                freeCredits,
                periodicCredits,
                addOnCredits,
                proMonthlyCredits,
                eventCredits,
                refreshCredits,
                maxRefreshCredits,
            ].compactMap { $0 }
            guard documentedCredits.allSatisfy({
                (0...ManusCreditsDecoder.maximumDocumentedCredit).contains($0)
            }) else {
                throw ManusCreditsDecodingError.invalidCredit
            }

            let interval: ManusRefreshInterval?
            if let refreshInterval {
                guard let accepted = ManusRefreshInterval(
                    rawValue: refreshInterval
                ) else {
                    throw ManusCreditsDecodingError.invalidRefreshInterval
                }
                interval = accepted
            } else {
                interval = nil
            }

            let refreshDate: Date?
            if let nextRefreshTime, nextRefreshTime != 0 {
                let candidate = Date(
                    timeIntervalSince1970: TimeInterval(nextRefreshTime)
                )
                guard nextRefreshTime > 0,
                      candidate
                        >= ManusCreditsDecoder.earliestPlausibleRefresh,
                      candidate
                        <= ManusCreditsDecoder.latestPlausibleRefresh else {
                    throw ManusCreditsDecodingError.invalidRefreshTimestamp
                }
                refreshDate = candidate
            } else {
                refreshDate = nil
            }

            return ManusCreditsSnapshot(
                totalCredits: totalCredits,
                freeCredits: freeCredits,
                periodicCredits: periodicCredits,
                addOnCredits: addOnCredits,
                proMonthlyCredits: proMonthlyCredits,
                eventCredits: eventCredits,
                refreshCredits: refreshCredits,
                maxRefreshCredits: maxRefreshCredits,
                nextRefreshAt: refreshDate,
                refreshInterval: interval
            )
        }
    }
}
