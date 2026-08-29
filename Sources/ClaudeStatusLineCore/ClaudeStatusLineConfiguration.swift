import Foundation

public struct ClaudeStatusLineConfigurationPaths: Sendable {
    public let settingsURL: URL
    public let integrationDirectoryURL: URL
    public let backupURL: URL
    public let metadataURL: URL
    public let stateURL: URL
    public let receiptURL: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    ) {
        settingsURL = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
        integrationDirectoryURL = ClaudeStatusLinePaths.integrationDirectory(
            applicationSupportDirectory: applicationSupportDirectory
        )
        backupURL = integrationDirectoryURL.appendingPathComponent("settings-before-uma.json")
        metadataURL = integrationDirectoryURL.appendingPathComponent("restore-metadata.json")
        stateURL = integrationDirectoryURL.appendingPathComponent("status-line.json")
        receiptURL = integrationDirectoryURL.appendingPathComponent("stop-receipt.json")
    }

    public init(
        settingsURL: URL,
        integrationDirectoryURL: URL,
        backupURL: URL,
        metadataURL: URL,
        stateURL: URL,
        receiptURL: URL? = nil
    ) {
        self.settingsURL = settingsURL
        self.integrationDirectoryURL = integrationDirectoryURL
        self.backupURL = backupURL
        self.metadataURL = metadataURL
        self.stateURL = stateURL
        self.receiptURL = receiptURL
            ?? integrationDirectoryURL.appendingPathComponent("stop-receipt.json")
    }
}

public enum ClaudeStatusLineConfigurationState: String, Codable, Sendable {
    case unconfigured
    case ready
    case installed
    case repairRequired
    case unsupported
    case failed
}

public struct ClaudeStatusLineConfigurationCheck: Equatable, Sendable {
    public let state: ClaudeStatusLineConfigurationState
    public let priorStatusLinePresent: Bool

    public init(
        state: ClaudeStatusLineConfigurationState,
        priorStatusLinePresent: Bool = false
    ) {
        self.state = state
        self.priorStatusLinePresent = priorStatusLinePresent
    }
}

public enum ClaudeStatusLineConfigurationError: Error, Equatable, Sendable {
    case unsafePath
    case recordTooLarge
    case malformedSettings
    case unsupportedSettings
    case integrationAlreadyExists
    case integrationMissing
    case concurrentModification
    case recursivePriorCommand
    case unsafeLiteralSecret
    case invalidMetadata
}
