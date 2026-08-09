import CoreFoundation
import Foundation

struct AntigravityQuotaSnapshot: Equatable, Sendable {
    let buckets: [AntigravityQuotaBucket]
    let observedAt: Date
    let sourceVersion: String
}

struct AntigravityQuotaBucket: Equatable, Sendable, Identifiable {
    let id: String
    let displayLabel: String?
    let remainingPercent: Double
    let resetsAt: Date?
}

enum AntigravityQuotaDecodingError: Error, Equatable, Sendable {
    case malformedJSON
    case unsupportedVersion
    case unsupportedSchema
    case invalidOperationalEnvelope
    case invalidBucket
    case duplicateBucketIdentity
    case noValidQuota
}

enum AntigravityQuotaDecoder {
    static let admittedCLIVersion = "1.1.11"
    static let maximumGroups = 32
    static let maximumBuckets = 64

    private static let admittedRootKeys: Set<String> = [
        "command", "conversation_id", "duration_seconds", "num_turns",
        "response", "status", "usage",
    ]
    private static let prohibitedOperationalRootKeys: Set<String> = [
        "task", "tasks", "task_id", "taskid", "tool_call", "tool_calls",
        "tool_use", "tool_uses",
    ]
    private static let admittedCommandKeys: Set<String> = ["data", "name"]
    private static let admittedCommandDataKeys: Set<String> = [
        "description", "groups",
    ]
    private static let admittedGroupKeys: Set<String> = [
        "buckets", "description", "name",
    ]
    private static let admittedBucketKeys: Set<String> = [
        "id", "name", "remaining_fraction", "reset_time", "window",
    ]

    static func decode(
        _ data: Data,
        cliVersion: String,
        observedAt: Date
    ) throws -> AntigravityQuotaSnapshot {
        guard cliVersion == admittedCLIVersion else {
            throw AntigravityQuotaDecodingError.unsupportedVersion
        }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AntigravityQuotaDecodingError.malformedJSON
        }

        guard let object = root as? [String: Any] else {
            throw AntigravityQuotaDecodingError.unsupportedSchema
        }

        let rootKeys = Set(object.keys)
        guard rootKeys.isDisjoint(with: prohibitedOperationalRootKeys) else {
            throw AntigravityQuotaDecodingError.invalidOperationalEnvelope
        }
        guard rootKeys.isSubset(of: admittedRootKeys),
              let command = object["command"] as? [String: Any],
              Set(command.keys) == admittedCommandKeys,
              command["name"] as? String == "usage",
              let commandData = command["data"] as? [String: Any],
              Set(commandData.keys) == admittedCommandDataKeys,
              commandData["description"] is String,
              let groups = commandData["groups"] as? [[String: Any]],
              groups.count <= maximumGroups
        else {
            throw AntigravityQuotaDecodingError.unsupportedSchema
        }

        try validateNoProviderWork(in: object)

        var identities = Set<String>()
        var buckets: [AntigravityQuotaBucket] = []
        buckets.reserveCapacity(min(groups.count * 2, maximumBuckets))

        for group in groups {
            guard Set(group.keys) == admittedGroupKeys,
                  safeIdentifier(group["name"]) != nil,
                  group["description"] is String,
                  let rawBuckets = group["buckets"] as? [[String: Any]],
                  buckets.count + rawBuckets.count <= maximumBuckets
            else {
                throw AntigravityQuotaDecodingError.invalidBucket
            }

            for rawBucket in rawBuckets {
                guard Set(rawBucket.keys).isSubset(of: admittedBucketKeys),
                      admittedBucketKeys.subtracting(["reset_time"])
                        .isSubset(of: Set(rawBucket.keys)),
                      let bucketID = safeIdentifier(rawBucket["id"]),
                      safeIdentifier(rawBucket["window"]) != nil,
                      let displayLabel = safeDisplayLabel(rawBucket["name"]),
                      let number = rawBucket["remaining_fraction"] as? NSNumber,
                      !isBoolean(number)
                else {
                    throw AntigravityQuotaDecodingError.invalidBucket
                }

                let remainingFraction = number.doubleValue
                guard remainingFraction.isFinite,
                      (0...1).contains(remainingFraction)
                else {
                    throw AntigravityQuotaDecodingError.invalidBucket
                }

                let resetsAt: Date?
                if let rawReset = rawBucket["reset_time"] {
                    guard let resetString = rawReset as? String,
                          let reset = iso8601Date(resetString)
                    else {
                        throw AntigravityQuotaDecodingError.invalidBucket
                    }
                    resetsAt = reset
                } else {
                    resetsAt = nil
                }

                guard identities.insert(bucketID).inserted else {
                    throw AntigravityQuotaDecodingError.duplicateBucketIdentity
                }
                buckets.append(
                    AntigravityQuotaBucket(
                        id: bucketID,
                        displayLabel: displayLabel,
                        remainingPercent: remainingFraction * 100,
                        resetsAt: resetsAt
                    )
                )
            }
        }

        guard !buckets.isEmpty else {
            throw AntigravityQuotaDecodingError.noValidQuota
        }

        return AntigravityQuotaSnapshot(
            buckets: buckets,
            observedAt: observedAt,
            sourceVersion: "agy-\(cliVersion)"
        )
    }

    private static func validateNoProviderWork(
        in object: [String: Any]
    ) throws {
        guard let numTurns = object["num_turns"] as? NSNumber,
              !isBoolean(numTurns),
              numTurns.doubleValue == 0,
              numTurns.int64Value == 0,
              normalizedConversationID(object["conversation_id"]) == "",
              let usage = object["usage"] as? [String: Any],
              !usage.isEmpty,
              usage.count <= 32,
              usage.keys.allSatisfy({ safeIdentifier($0) != nil }),
              usage.values.allSatisfy(isNumericZero)
        else {
            throw AntigravityQuotaDecodingError.invalidOperationalEnvelope
        }
    }

    private static func normalizedConversationID(_ value: Any?) -> String? {
        guard let value else { return "" }
        guard let string = value as? String else { return nil }
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNumericZero(_ value: Any) -> Bool {
        guard let number = value as? NSNumber, !isBoolean(number) else {
            return false
        }
        return number.doubleValue == 0
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func safeIdentifier(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.count <= 64,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && (
                      CharacterSet.alphanumerics.contains(scalar)
                          || "-_.:".unicodeScalars.contains(scalar)
                  )
              })
        else {
            return nil
        }
        return value
    }

    private static func safeDisplayLabel(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= 48,
              !trimmed.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              })
        else {
            return nil
        }
        return trimmed
    }

    private static func iso8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let ordinary = ISO8601DateFormatter()
        ordinary.formatOptions = [.withInternetDateTime]
        return ordinary.date(from: value)
    }
}
