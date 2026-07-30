import CoreFoundation
import Foundation

public enum ClaudeStatusLineProtocolError: Error, Equatable, Sendable {
    case inputTooLarge
    case outputTooLarge
    case malformedJSON
    case malformedVersion
    case malformedWindow
    case invalidPercentage
    case invalidReset
    case unsupportedSchema
}

public struct ClaudeStatusLineWindowPacket: Codable, Equatable, Sendable {
    public let usedPercentage: Double
    public let resetsAtEpochSeconds: Int64

    public init(usedPercentage: Double, resetsAtEpochSeconds: Int64) throws {
        guard usedPercentage.isFinite,
              (0...100).contains(usedPercentage)
        else {
            throw ClaudeStatusLineProtocolError.invalidPercentage
        }
        guard ClaudeStatusLineProjection.isValidResetEpoch(
            resetsAtEpochSeconds
        ) else {
            throw ClaudeStatusLineProtocolError.invalidReset
        }
        self.usedPercentage = usedPercentage
        self.resetsAtEpochSeconds = resetsAtEpochSeconds
    }
}

/// The complete cross-process allowlist. This type intentionally cannot
/// represent a session, prompt, transcript, path, account, task, or raw
/// provider object.
public struct ClaudeStatusLinePacket: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumEncodedBytes = 4 * 1_024

    public let schemaVersion: Int
    public let claudeVersion: String?
    public let fiveHour: ClaudeStatusLineWindowPacket?
    public let sevenDay: ClaudeStatusLineWindowPacket?
    public let observedAt: Date

    public init(
        schemaVersion: Int = currentSchemaVersion,
        claudeVersion: String?,
        fiveHour: ClaudeStatusLineWindowPacket?,
        sevenDay: ClaudeStatusLineWindowPacket?,
        observedAt: Date
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ClaudeStatusLineProtocolError.unsupportedSchema
        }
        if let claudeVersion {
            guard ClaudeStatusLineProjection.isValidVersion(claudeVersion)
            else {
                throw ClaudeStatusLineProtocolError.malformedVersion
            }
        }
        guard observedAt.timeIntervalSince1970.isFinite else {
            throw ClaudeStatusLineProtocolError.malformedJSON
        }
        self.schemaVersion = schemaVersion
        self.claudeVersion = claudeVersion
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.observedAt = observedAt
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw ClaudeStatusLineProtocolError.outputTooLarge
        }
        return data
    }

    public static func decodePacket(_ data: Data) throws -> Self {
        guard data.count <= maximumEncodedBytes else {
            throw ClaudeStatusLineProtocolError.outputTooLarge
        }
        try validatePacketShape(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let packet: Self
        do {
            packet = try decoder.decode(Self.self, from: data)
        } catch {
            throw ClaudeStatusLineProtocolError.malformedJSON
        }
        guard packet.schemaVersion == currentSchemaVersion else {
            throw ClaudeStatusLineProtocolError.unsupportedSchema
        }
        let fiveHour = try packet.fiveHour.map {
            try ClaudeStatusLineWindowPacket(
                usedPercentage: $0.usedPercentage,
                resetsAtEpochSeconds: $0.resetsAtEpochSeconds
            )
        }
        let sevenDay = try packet.sevenDay.map {
            try ClaudeStatusLineWindowPacket(
                usedPercentage: $0.usedPercentage,
                resetsAtEpochSeconds: $0.resetsAtEpochSeconds
            )
        }
        return try Self(
            schemaVersion: packet.schemaVersion,
            claudeVersion: packet.claudeVersion,
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            observedAt: packet.observedAt
        )
    }

    private static func validatePacketShape(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ClaudeStatusLineProtocolError.malformedJSON
        }
        guard let root = object as? [String: Any],
              Set(root.keys).isSubset(
                of: [
                    "schemaVersion",
                    "claudeVersion",
                    "fiveHour",
                    "sevenDay",
                    "observedAt",
                ]
              )
        else {
            throw ClaudeStatusLineProtocolError.unsupportedSchema
        }
        for key in ["fiveHour", "sevenDay"] {
            guard let value = root[key], !(value is NSNull) else { continue }
            guard let window = value as? [String: Any],
                  Set(window.keys) == [
                    "usedPercentage",
                    "resetsAtEpochSeconds",
                  ]
            else {
                throw ClaudeStatusLineProtocolError.unsupportedSchema
            }
        }
    }
}

public enum ClaudeStatusLineProjection {
    public static let maximumInputBytes = 64 * 1_024
    public static let maximumVersionBytes = 128
    public static let earliestResetEpoch: Int64 = 0
    public static let latestResetEpoch: Int64 = 4_102_444_800

    public static func decode(
        _ rawInput: Data,
        observedAt: Date = Date()
    ) throws -> ClaudeStatusLinePacket {
        guard rawInput.count <= maximumInputBytes else {
            throw ClaudeStatusLineProtocolError.inputTooLarge
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(
                with: rawInput,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw ClaudeStatusLineProtocolError.malformedJSON
        }
        guard let root = object as? [String: Any] else {
            throw ClaudeStatusLineProtocolError.malformedJSON
        }

        let version = try decodeVersion(root["version"])
        let rateLimits: [String: Any]?
        switch root["rate_limits"] {
        case nil, is NSNull:
            rateLimits = nil
        case let value as [String: Any]:
            rateLimits = value
        default:
            throw ClaudeStatusLineProtocolError.malformedWindow
        }

        return try ClaudeStatusLinePacket(
            claudeVersion: version,
            fiveHour: try decodeWindow(
                rateLimits?["five_hour"]
            ),
            sevenDay: try decodeWindow(
                rateLimits?["seven_day"]
            ),
            observedAt: observedAt
        )
    }

    public static func isValidVersion(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= maximumVersionBytes
            && !value.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }

    public static func isValidResetEpoch(_ value: Int64) -> Bool {
        (earliestResetEpoch...latestResetEpoch).contains(value)
    }

    private static func decodeVersion(_ value: Any?) throws -> String? {
        switch value {
        case nil, is NSNull:
            return nil
        case let value as String where isValidVersion(value):
            return value
        default:
            throw ClaudeStatusLineProtocolError.malformedVersion
        }
    }

    private static func decodeWindow(
        _ value: Any?
    ) throws -> ClaudeStatusLineWindowPacket? {
        switch value {
        case nil, is NSNull:
            return nil
        case let value as [String: Any]:
            guard let used = strictDouble(value["used_percentage"]),
                  let reset = strictInt64(value["resets_at"])
            else {
                throw ClaudeStatusLineProtocolError.malformedWindow
            }
            return try ClaudeStatusLineWindowPacket(
                usedPercentage: used,
                resetsAtEpochSeconds: reset
            )
        default:
            throw ClaudeStatusLineProtocolError.malformedWindow
        }
    }

    private static func strictDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite, (0...100).contains(double) else {
            return nil
        }
        return double
    }

    private static func strictInt64(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded(.towardZero) == double,
              double >= Double(Int64.min),
              double <= Double(Int64.max)
        else {
            return nil
        }
        let integer = Int64(double)
        return isValidResetEpoch(integer) ? integer : nil
    }
}
