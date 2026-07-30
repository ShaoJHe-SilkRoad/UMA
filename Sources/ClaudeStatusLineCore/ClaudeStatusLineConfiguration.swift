import Foundation

/// A lossless-enough JSON value used only while editing Claude's settings
/// object. The original bytes remain the restoration authority.
public enum ClaudeJSONValue: Codable, Equatable, Sendable {
    case object([String: ClaudeJSONValue])
    case array([ClaudeJSONValue])
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ClaudeJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(
            [String: ClaudeJSONValue].self
        ) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public enum ClaudeSettingsAuthority: Equatable, Sendable {
    case userWritable
    case managed
    case unknown
}

public enum ClaudeStatusLineConfigurationState: Equatable, Sendable {
    case unconfigured
    case ready(priorStatusLinePresent: Bool)
    case installed
    case repairRequired
    case unsupported
    case failed
}

public enum ClaudeStatusLineConfigurationError: Error, Equatable, Sendable {
    case authorityUnverified
    case managedConfiguration
    case malformedSettings
    case unsupportedFutureSchema
    case hooksDisabled
    case managedRestriction
    case insecurePath
    case nonRegularFile
    case wrongOwner
    case hardLinkedFile
    case insecurePermissions
    case recordTooLarge
    case unsafeLiteralSecret
    case recursivePriorCommand
    case backupUnavailable
    case backupMismatch
    case metadataMismatch
    case concurrentModification
    case relayUnavailable
    case persistenceUnavailable
}

public struct ClaudeStatusLineConfigurationPaths: Equatable, Sendable {
    public let homeDirectory: URL
    public let applicationSupportDirectory: URL
    public let settingsURL: URL
    public let integrationDirectoryURL: URL
    public let backupURL: URL
    public let metadataURL: URL

    public init(
        homeDirectory: URL,
        applicationSupportDirectory: URL
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.applicationSupportDirectory =
            applicationSupportDirectory.standardizedFileURL
        settingsURL = self.homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
        integrationDirectoryURL = self.applicationSupportDirectory
            .appendingPathComponent(
                "CodexUsageMonitor",
                isDirectory: true
            )
            .appendingPathComponent(
                "ClaudeStatusLineIntegration",
                isDirectory: true
            )
        backupURL = integrationDirectoryURL
            .appendingPathComponent("settings.backup", isDirectory: false)
        metadataURL = integrationDirectoryURL
            .appendingPathComponent("metadata.json", isDirectory: false)
    }
}

public struct ClaudeStatusLineConfigurationMetadata:
    Codable,
    Equatable,
    Sendable
{
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let originalSettingsExisted: Bool
    public let originalParentExisted: Bool
    public let originalByteCount: Int
    public let originalSHA256: String?
    public let originalMode: UInt16?
    public let originalOwnerID: UInt32?
    public let priorStatusLinePresent: Bool
    public let installedSHA256: String

    public init(
        schemaVersion: Int = currentSchemaVersion,
        originalSettingsExisted: Bool,
        originalParentExisted: Bool,
        originalByteCount: Int,
        originalSHA256: String?,
        originalMode: UInt16?,
        originalOwnerID: UInt32?,
        priorStatusLinePresent: Bool,
        installedSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.originalSettingsExisted = originalSettingsExisted
        self.originalParentExisted = originalParentExisted
        self.originalByteCount = originalByteCount
        self.originalSHA256 = originalSHA256
        self.originalMode = originalMode
        self.originalOwnerID = originalOwnerID
        self.priorStatusLinePresent = priorStatusLinePresent
        self.installedSHA256 = installedSHA256
    }
}

public struct ClaudeStatusLineConfigurationCheck: Equatable, Sendable {
    public let state: ClaudeStatusLineConfigurationState
    public let priorStatusLinePresent: Bool

    public init(
        state: ClaudeStatusLineConfigurationState,
        priorStatusLinePresent: Bool
    ) {
        self.state = state
        self.priorStatusLinePresent = priorStatusLinePresent
    }
}
