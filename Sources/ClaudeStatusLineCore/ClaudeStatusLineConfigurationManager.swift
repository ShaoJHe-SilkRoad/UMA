import CryptoKit
import Darwin
import Foundation

public final class ClaudeStatusLineConfigurationManager: @unchecked Sendable {
    private struct Metadata: Codable {
        static let schemaVersion = 4
        static let legacySchemaVersion = 2
        static let diagnosticHookSchemaVersion = 3
        let schemaVersion: Int
        let settingsWereAbsent: Bool
        let priorStatusLineWasAbsent: Bool
        let originalMode: UInt16?
        let originalWholeHash: String?
        let priorStatusLineHash: String?
        let installedHash: String
        let installedStatusLineHash: String
        let installedCommandHash: String
        let priorHooksWereAbsent: Bool?
        let priorHooksHash: String?
        let installedHooksHash: String?
        let installedStopHookHash: String?

        var hasDiagnosticHookContract: Bool {
            schemaVersion == Self.diagnosticHookSchemaVersion
                && priorHooksWereAbsent != nil
                && installedHooksHash != nil
                && installedStopHookHash != nil
        }
    }

    public static let maximumSettingsBytes = 512 * 1_024
    public static let maximumStatusLineBackupBytes = 64 * 1_024
    private let paths: ClaudeStatusLineConfigurationPaths
    private let relayCommand: String
    private let fileManager: FileManager

    public init(
        paths: ClaudeStatusLineConfigurationPaths = ClaudeStatusLineConfigurationPaths(),
        relayCommand: String,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.relayCommand = relayCommand
        self.fileManager = fileManager
    }

    public func check() -> ClaudeStatusLineConfigurationCheck {
        do {
            try validatePaths()
            let settings = try loadSettingsIfPresent()
            let currentStatusLinePresent = try settings.map(Self.priorStatusLinePresent) ?? false
            let metadataExists = fileManager.fileExists(atPath: paths.metadataURL.path)
            let backupExists = fileManager.fileExists(atPath: paths.backupURL.path)
            guard metadataExists || backupExists else {
                return ClaudeStatusLineConfigurationCheck(
                    state: .ready,
                    priorStatusLinePresent: currentStatusLinePresent
                )
            }
            guard metadataExists,
                  let metadata = try? loadMetadata(),
                  [
                    Metadata.legacySchemaVersion,
                    Metadata.diagnosticHookSchemaVersion,
                    Metadata.schemaVersion,
                  ]
                    .contains(metadata.schemaVersion),
                  backupExists == !metadata.priorStatusLineWasAbsent
            else {
                return ClaudeStatusLineConfigurationCheck(
                    state: .repairRequired,
                    priorStatusLinePresent: currentStatusLinePresent
                )
            }
            guard settings != nil else {
                return ClaudeStatusLineConfigurationCheck(
                    state: .repairRequired,
                    priorStatusLinePresent: !metadata.priorStatusLineWasAbsent
                )
            }
            let currentData = try currentData(at: paths.settingsURL)
            let currentRoot = try decodeRoot(currentData)
            let exactInstall = Self.digest(currentData) == metadata.installedHash
            let exactStatusLine = try statusLineDigest(in: currentRoot)
                == metadata.installedStatusLineHash
            let sameCommand = Self.digest(Data(relayCommand.utf8)) == metadata.installedCommandHash
            guard metadata.schemaVersion == Metadata.schemaVersion else {
                return ClaudeStatusLineConfigurationCheck(
                    state: .repairRequired,
                    priorStatusLinePresent: !metadata.priorStatusLineWasAbsent
                )
            }
            return ClaudeStatusLineConfigurationCheck(
                state: exactInstall && exactStatusLine && sameCommand
                    ? .installed : .repairRequired,
                priorStatusLinePresent: !metadata.priorStatusLineWasAbsent
            )
        } catch ClaudeStatusLineConfigurationError.unsupportedSettings {
            return ClaudeStatusLineConfigurationCheck(state: .unsupported)
        } catch {
            return ClaudeStatusLineConfigurationCheck(state: .failed)
        }
    }

    public func enable() throws {
        try validatePaths()
        guard !fileManager.fileExists(atPath: paths.metadataURL.path),
              !fileManager.fileExists(atPath: paths.backupURL.path)
        else { throw ClaudeStatusLineConfigurationError.integrationAlreadyExists }
        let originalData = try dataIfPresent(at: paths.settingsURL)
        guard originalData.map({ $0.count <= Self.maximumSettingsBytes }) ?? true else {
            throw ClaudeStatusLineConfigurationError.recordTooLarge
        }
        let originalRoot = try decodeRoot(originalData ?? Data("{}".utf8))
        try validatePriorStatusLine(in: originalRoot)
        let originalMode = try originalData.map { _ in try mode(at: paths.settingsURL) }
        let priorStatusLine = originalRoot["statusLine"]
        let priorStatusLineData = try priorStatusLine.map(encodeStatusLineFragment)
        let installedData = try installedSettings(from: originalRoot)
        let installedRoot = try decodeRoot(installedData)
        try prepareIntegrationDirectory()
        if let priorStatusLineData {
            try writeOwnerOnly(priorStatusLineData, to: paths.backupURL)
        }
        do {
            try writeSettings(installedData)
            let metadata = Metadata(
                schemaVersion: Metadata.schemaVersion,
                settingsWereAbsent: originalData == nil,
                priorStatusLineWasAbsent: priorStatusLine == nil,
                originalMode: originalMode,
                originalWholeHash: originalData.map(Self.digest),
                priorStatusLineHash: priorStatusLineData.map(Self.digest),
                installedHash: Self.digest(installedData),
                installedStatusLineHash: try statusLineDigest(in: installedRoot),
                installedCommandHash: Self.digest(Data(relayCommand.utf8)),
                priorHooksWereAbsent: nil,
                priorHooksHash: nil,
                installedHooksHash: nil,
                installedStopHookHash: nil
            )
            try writeOwnerOnly(try encode(metadata), to: paths.metadataURL)
        } catch {
            try? restoreOriginal(
                originalData: originalData,
                originalMode: originalMode
            )
            try? removeIfPresent(paths.backupURL)
            try? removeIfPresent(paths.metadataURL)
            throw error
        }
    }

    /// Explicit repair may rebase unrelated settings edits or migrate UMA's
    /// relay path only while the exact UMA-owned statusLine remains unchanged.
    /// Any external statusLine edit fails closed and is never adopted.
    public func repair() throws {
        try validatePaths()
        let metadata = try loadMetadata()
        guard let currentData = try dataIfPresent(at: paths.settingsURL) else {
            throw ClaudeStatusLineConfigurationError.concurrentModification
        }
        let currentRoot = try decodeRoot(currentData)
        guard try statusLineDigest(in: currentRoot) == metadata.installedStatusLineHash,
              Self.command(in: currentRoot).map({
                  Self.digest(Data($0.utf8)) == metadata.installedCommandHash
              }) == true
        else { throw ClaudeStatusLineConfigurationError.concurrentModification }

        var repairedRoot = currentRoot
        if metadata.hasDiagnosticHookContract {
            guard let installedHooksHash = metadata.installedHooksHash,
                  try hooksDigest(in: currentRoot) == installedHooksHash,
                  try ownedStopHookCount(in: currentRoot) == 1
            else { throw ClaudeStatusLineConfigurationError.concurrentModification }
            try removeOwnedStopHook(from: &repairedRoot)
            let restoredHooks = repairedRoot["hooks"]
            guard (restoredHooks == nil) == (metadata.priorHooksWereAbsent == true),
                  try restoredHooks.map({ Self.digest(try encodeFragment($0)) })
                    == metadata.priorHooksHash
            else { throw ClaudeStatusLineConfigurationError.concurrentModification }
        } else if ![Metadata.legacySchemaVersion, Metadata.schemaVersion]
            .contains(metadata.schemaVersion) {
            throw ClaudeStatusLineConfigurationError.invalidMetadata
        }

        let installedData = try installedSettings(from: repairedRoot)
        let installedRoot = try decodeRoot(installedData)
        try writeSettings(installedData)
        let updated = Metadata(
            schemaVersion: Metadata.schemaVersion,
            settingsWereAbsent: metadata.settingsWereAbsent,
            priorStatusLineWasAbsent: metadata.priorStatusLineWasAbsent,
            originalMode: metadata.originalMode,
            originalWholeHash: metadata.originalWholeHash,
            priorStatusLineHash: metadata.priorStatusLineHash,
            installedHash: Self.digest(installedData),
            installedStatusLineHash: try statusLineDigest(in: installedRoot),
            installedCommandHash: Self.digest(Data(relayCommand.utf8)),
            priorHooksWereAbsent: nil,
            priorHooksHash: nil,
            installedHooksHash: nil,
            installedStopHookHash: nil
        )
        try writeOwnerOnly(try encode(updated), to: paths.metadataURL)
    }

    public func disable() throws { try restore() }

    public func restore() throws {
        try validatePaths()
        let metadata = try loadMetadata()
        guard let currentData = try dataIfPresent(at: paths.settingsURL),
              Self.digest(currentData) == metadata.installedHash,
              let currentRoot = try? decodeRoot(currentData),
              try statusLineDigest(in: currentRoot) == metadata.installedStatusLineHash
        else { throw ClaudeStatusLineConfigurationError.concurrentModification }
        var restoredRoot = currentRoot
        if metadata.hasDiagnosticHookContract {
            guard let installedHooksHash = metadata.installedHooksHash,
                  try hooksDigest(in: currentRoot) == installedHooksHash,
                  try ownedStopHookCount(in: currentRoot) == 1
            else { throw ClaudeStatusLineConfigurationError.concurrentModification }
            try removeOwnedStopHook(from: &restoredRoot)
            let restoredHooks = restoredRoot["hooks"]
            guard (restoredHooks == nil) == (metadata.priorHooksWereAbsent == true),
                  try restoredHooks.map({ Self.digest(try encodeFragment($0)) })
                    == metadata.priorHooksHash
            else { throw ClaudeStatusLineConfigurationError.concurrentModification }
        } else if ![Metadata.legacySchemaVersion, Metadata.schemaVersion]
            .contains(metadata.schemaVersion) {
            throw ClaudeStatusLineConfigurationError.invalidMetadata
        }
        if let priorStatusLine = try verifiedPriorStatusLine(metadata) {
            restoredRoot["statusLine"] = priorStatusLine
        } else {
            restoredRoot.removeValue(forKey: "statusLine")
        }
        if metadata.settingsWereAbsent && restoredRoot.isEmpty {
            try removeIfPresent(paths.settingsURL)
        } else {
            try writeSettings(try encodeRoot(restoredRoot))
            if let originalMode = metadata.originalMode {
                try fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: originalMode)],
                    ofItemAtPath: paths.settingsURL.path
                )
            }
        }
        try removeIfPresent(paths.backupURL)
        try removeIfPresent(paths.metadataURL)
        try? ClaudeStatusLineStateStore(stateURL: paths.stateURL).clear()
        try? ClaudeStatusLineStateStore(stateURL: paths.receiptURL).clear()
        try pruneIntegrationDirectoryIfEmpty()
    }

    public func uninstall() throws {
        if fileManager.fileExists(atPath: paths.metadataURL.path) {
            try restore()
        } else {
            try? ClaudeStatusLineStateStore(stateURL: paths.stateURL).clear()
            try? ClaudeStatusLineStateStore(stateURL: paths.receiptURL).clear()
            try pruneIntegrationDirectoryIfEmpty()
        }
    }

    public func priorCommandFromBackup() throws -> String? {
        let metadata = try loadMetadata()
        guard let statusLine = try verifiedPriorStatusLine(metadata) else { return nil }
        return statusLine["command"] as? String
    }

    private func verifiedPriorStatusLine(_ metadata: Metadata) throws -> [String: Any]? {
        if metadata.priorStatusLineWasAbsent {
            guard metadata.priorStatusLineHash == nil,
                  !fileManager.fileExists(atPath: paths.backupURL.path)
            else { throw ClaudeStatusLineConfigurationError.invalidMetadata }
            return nil
        }
        guard let data = try dataIfPresent(at: paths.backupURL),
              data.count <= Self.maximumStatusLineBackupBytes,
              let expected = metadata.priorStatusLineHash,
              Self.digest(data) == expected,
              let object = try? JSONSerialization.jsonObject(with: data),
              let statusLine = object as? [String: Any]
        else { throw ClaudeStatusLineConfigurationError.invalidMetadata }
        try validatePriorStatusLine(in: ["statusLine": statusLine])
        return statusLine
    }

    private func loadMetadata() throws -> Metadata {
        guard let data = try dataIfPresent(at: paths.metadataURL),
              data.count <= 8 * 1_024,
              let metadata = try? JSONDecoder().decode(Metadata.self, from: data),
              [
                Metadata.legacySchemaVersion,
                Metadata.diagnosticHookSchemaVersion,
                Metadata.schemaVersion,
              ]
                .contains(metadata.schemaVersion)
        else { throw ClaudeStatusLineConfigurationError.invalidMetadata }
        return metadata
    }

    private func loadSettingsIfPresent() throws -> [String: Any]? {
        guard let data = try dataIfPresent(at: paths.settingsURL) else { return nil }
        guard data.count <= Self.maximumSettingsBytes else {
            throw ClaudeStatusLineConfigurationError.recordTooLarge
        }
        return try decodeRoot(data)
    }

    private func installedSettings(from root: [String: Any]) throws -> Data {
        var next = root
        var status = (root["statusLine"] as? [String: Any]) ?? [:]
        status["type"] = "command"
        status["command"] = relayCommand
        next["statusLine"] = status
        return try encodeRoot(next)
    }

    private func removeOwnedStopHook(from root: inout [String: Any]) throws {
        guard var hooks = root["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [Any]
        else { throw ClaudeStatusLineConfigurationError.concurrentModification }
        let ownedData = try encodeFragment(ownedStopHookEntry())
        let retained = try stop.filter { try encodeFragment($0) != ownedData }
        guard retained.count + 1 == stop.count else {
            throw ClaudeStatusLineConfigurationError.concurrentModification
        }
        if retained.isEmpty { hooks.removeValue(forKey: "Stop") }
        else { hooks["Stop"] = retained }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") }
        else { root["hooks"] = hooks }
    }

    private func ownedStopHookEntry() -> [String: Any] {
        let diagnosticCommand = relayCommand
            + " --receipt-only --receipt-state "
            + Self.shellQuote(paths.receiptURL.path)
        return [
            "matcher": "",
            "hooks": [[
                "type": "command",
                "command": diagnosticCommand,
            ]],
        ]
    }

    private func ownedStopHookCount(in root: [String: Any]) throws -> Int {
        guard let rawHooks = root["hooks"] else { return 0 }
        guard let hooks = rawHooks as? [String: Any] else {
            throw ClaudeStatusLineConfigurationError.unsupportedSettings
        }
        guard let rawStop = hooks["Stop"] else { return 0 }
        guard let stop = rawStop as? [Any] else {
            throw ClaudeStatusLineConfigurationError.unsupportedSettings
        }
        let ownedData = try encodeFragment(ownedStopHookEntry())
        return try stop.reduce(into: 0) { count, entry in
            if try encodeFragment(entry) == ownedData { count += 1 }
        }
    }

    private func hooksDigest(in root: [String: Any]) throws -> String {
        guard let hooks = root["hooks"] else {
            throw ClaudeStatusLineConfigurationError.invalidMetadata
        }
        return Self.digest(try encodeFragment(hooks))
    }

    private func encodeFragment(_ value: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(value) else {
            throw ClaudeStatusLineConfigurationError.unsupportedSettings
        }
        return try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func encodeStatusLineFragment(_ value: Any) throws -> Data {
        guard let statusLine = value as? [String: Any],
              JSONSerialization.isValidJSONObject(statusLine)
        else { throw ClaudeStatusLineConfigurationError.unsupportedSettings }
        let data = try JSONSerialization.data(
            withJSONObject: statusLine,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) + Data([0x0A])
        guard data.count <= Self.maximumStatusLineBackupBytes else {
            throw ClaudeStatusLineConfigurationError.recordTooLarge
        }
        return data
    }

    private func statusLineDigest(in root: [String: Any]) throws -> String {
        guard let statusLine = root["statusLine"] else {
            throw ClaudeStatusLineConfigurationError.invalidMetadata
        }
        return Self.digest(try encodeStatusLineFragment(statusLine))
    }

    private func validatePriorStatusLine(in root: [String: Any]) throws {
        guard let raw = root["statusLine"] else { return }
        guard let status = raw as? [String: Any],
              (status["type"] as? String ?? "command") == "command",
              let command = status["command"] as? String,
              !command.isEmpty,
              !command.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw ClaudeStatusLineConfigurationError.unsupportedSettings }
        let lower = command.lowercased()
        if lower.contains("claudestatuslinerelay") || lower.contains("uma-claude-smart-relay") {
            throw ClaudeStatusLineConfigurationError.recursivePriorCommand
        }
        for secret in ["anthropic_api_key=", "authorization: bearer", "oauth_token="] {
            if lower.contains(secret) {
                throw ClaudeStatusLineConfigurationError.unsafeLiteralSecret
            }
        }
    }

    private static func priorStatusLinePresent(_ root: [String: Any]) throws -> Bool {
        guard let raw = root["statusLine"] else { return false }
        guard raw is [String: Any] else {
            throw ClaudeStatusLineConfigurationError.unsupportedSettings
        }
        return true
    }

    private static func command(in root: [String: Any]) -> String? {
        (root["statusLine"] as? [String: Any])?["command"] as? String
    }

    private func decodeRoot(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else { throw ClaudeStatusLineConfigurationError.malformedSettings }
        if root["disableAllHooks"] as? Bool == true
            || root["allowManagedHooksOnly"] as? Bool == true {
            throw ClaudeStatusLineConfigurationError.unsupportedSettings
        }
        return root
    }

    private func encodeRoot(_ root: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw ClaudeStatusLineConfigurationError.malformedSettings
        }
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) + Data([0x0A])
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func prepareIntegrationDirectory() throws {
        guard !Self.hasSymbolicLinkComponent(paths.integrationDirectoryURL) else {
            throw ClaudeStatusLineConfigurationError.unsafePath
        }
        try fileManager.createDirectory(
            at: paths.integrationDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: paths.integrationDirectoryURL.path
        )
    }

    private func writeOwnerOnly(_ data: Data, to url: URL) throws {
        guard !Self.hasSymbolicLinkComponent(url.deletingLastPathComponent()),
              !Self.isSymbolicLink(url)
        else { throw ClaudeStatusLineConfigurationError.unsafePath }
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func writeSettings(_ data: Data) throws {
        let parent = paths.settingsURL.deletingLastPathComponent()
        guard !Self.hasSymbolicLinkComponent(parent), !Self.isSymbolicLink(paths.settingsURL) else {
            throw ClaudeStatusLineConfigurationError.unsafePath
        }
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: paths.settingsURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.settingsURL.path)
    }

    private func restoreOriginal(originalData: Data?, originalMode: UInt16?) throws {
        if let originalData {
            try originalData.write(to: paths.settingsURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: originalMode ?? 0o600)],
                ofItemAtPath: paths.settingsURL.path
            )
        } else {
            try removeIfPresent(paths.settingsURL)
        }
    }

    private func validatePaths() throws {
        for url in [paths.settingsURL, paths.integrationDirectoryURL, paths.backupURL, paths.metadataURL, paths.stateURL, paths.receiptURL] {
            guard !Self.hasSymbolicLinkComponent(url.deletingLastPathComponent()),
                  !Self.isSymbolicLink(url)
            else { throw ClaudeStatusLineConfigurationError.unsafePath }
        }
    }

    private func dataIfPresent(at url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1
        else { throw ClaudeStatusLineConfigurationError.unsafePath }
        return try Data(contentsOf: url)
    }

    private func currentData(at url: URL) throws -> Data {
        guard let data = try dataIfPresent(at: url) else {
            throw ClaudeStatusLineConfigurationError.integrationMissing
        }
        return data
    }

    private func mode(at url: URL) throws -> UInt16 {
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            throw ClaudeStatusLineConfigurationError.unsafePath
        }
        return UInt16(info.st_mode & 0o777)
    }

    private func removeIfPresent(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func pruneIntegrationDirectoryIfEmpty() throws {
        guard fileManager.fileExists(atPath: paths.integrationDirectoryURL.path) else { return }
        let entries = try fileManager.contentsOfDirectory(atPath: paths.integrationDirectoryURL.path)
        if entries.isEmpty { try fileManager.removeItem(at: paths.integrationDirectoryURL) }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func hasSymbolicLinkComponent(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        while current.path != "/" {
            if isSymbolicLink(current) { return true }
            current.deleteLastPathComponent()
        }
        return false
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
