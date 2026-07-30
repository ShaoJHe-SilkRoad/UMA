import CryptoKit
import Darwin
import Foundation

public struct ClaudeStatusLineConfigurationManager: Sendable {
    public static let maximumSettingsBytes = 512 * 1_024

    public let paths: ClaudeStatusLineConfigurationPaths
    private let relayCommand: String
    private let authority: ClaudeSettingsAuthority
    private let expectedOwnerID: uid_t

    public init(
        paths: ClaudeStatusLineConfigurationPaths,
        relayCommand: String,
        authority: ClaudeSettingsAuthority = .userWritable,
        expectedOwnerID: uid_t = getuid()
    ) {
        self.paths = paths
        self.relayCommand = relayCommand
        self.authority = authority
        self.expectedOwnerID = expectedOwnerID
    }

    public func check() -> ClaudeStatusLineConfigurationCheck {
        do {
            try validateAuthority()
            let current = try loadCurrentSettings()
            let priorPresent = try current.root.statusLineObject() != nil
            guard FileManager.default.fileExists(
                atPath: paths.metadataURL.path
            ) else {
                _ = try safePriorCommand(from: current.root)
                return ClaudeStatusLineConfigurationCheck(
                    state: .ready(
                        priorStatusLinePresent: priorPresent
                    ),
                    priorStatusLinePresent: priorPresent
                )
            }
            let metadata = try loadMetadata()
            _ = try loadBackup(metadata: metadata)
            guard metadata.schemaVersion
                    == ClaudeStatusLineConfigurationMetadata
                        .currentSchemaVersion
            else {
                return .init(
                    state: .unsupported,
                    priorStatusLinePresent: metadata.priorStatusLinePresent
                )
            }
            let currentHash = Self.sha256(current.bytes)
            let state: ClaudeStatusLineConfigurationState
            if currentHash == metadata.installedSHA256,
               try current.root.isRelayInstalled(
                relayCommand: relayCommand
               ) {
                state = .installed
            } else {
                state = .repairRequired
            }
            return .init(
                state: state,
                priorStatusLinePresent: metadata.priorStatusLinePresent
            )
        } catch let error as ClaudeStatusLineConfigurationError {
            return .init(
                state: Self.state(for: error),
                priorStatusLinePresent: false
            )
        } catch {
            return .init(state: .failed, priorStatusLinePresent: false)
        }
    }

    public func enable() throws {
        try validateAuthority()
        let current = try loadCurrentSettings()
        let existingMetadata = try? loadMetadata()
        if let existingMetadata {
            if current.bytes.isEmpty == false,
               Self.sha256(current.bytes)
                    == existingMetadata.installedSHA256,
               try current.root.isRelayInstalled(
                relayCommand: relayCommand
               ) {
                return
            }
            try repair()
            return
        }

        let priorCommand = try safePriorCommand(from: current.root)
        if let priorCommand {
            switch ClaudePriorCommandPolicy.classify(priorCommand) {
            case .safe:
                break
            case .unsafeLiteralSecret:
                throw ClaudeStatusLineConfigurationError.unsafeLiteralSecret
            case .recursive:
                throw ClaudeStatusLineConfigurationError
                    .recursivePriorCommand
            case .malformed:
                throw ClaudeStatusLineConfigurationError
                    .unsupportedFutureSchema
            }
        }

        try prepareIntegrationDirectory()
        let originalMode = current.mode
        try writeFile(
            current.bytes,
            to: paths.backupURL,
            mode: 0o600,
            replacing: false
        )

        var installedRoot = current.root
        try installedRoot.installRelay(command: relayCommand)
        let installedBytes = try encodeRoot(installedRoot)
        let metadata = ClaudeStatusLineConfigurationMetadata(
            originalSettingsExisted: current.existed,
            originalParentExisted: current.parentExisted,
            originalByteCount: current.bytes.count,
            originalSHA256: current.existed
                ? Self.sha256(current.bytes)
                : nil,
            originalMode: current.existed ? originalMode : nil,
            originalOwnerID: current.existed
                ? UInt32(expectedOwnerID)
                : nil,
            priorStatusLinePresent: priorCommand != nil,
            installedSHA256: Self.sha256(installedBytes)
        )
        do {
            try verifyCurrentSettingsUnchanged(current)
            try writeSettings(installedBytes)
            try writeFile(
                try encodeMetadata(metadata),
                to: paths.metadataURL,
                mode: 0o600,
                replacing: false
            )
        } catch {
            try? restoreOriginal(
                bytes: current.bytes,
                metadata: metadata
            )
            try? FileManager.default.removeItem(at: paths.backupURL)
            try? FileManager.default.removeItem(at: paths.metadataURL)
            throw error
        }
    }

    public func repair() throws {
        try validateAuthority()
        let metadata = try loadMetadata()
        let backup = try loadBackup(metadata: metadata)
        let current = try loadCurrentSettings()
        guard current.existed,
              Self.sha256(current.bytes) == metadata.installedSHA256,
              try current.root.nonStatusLineObject()
                == backup.root.nonStatusLineObject()
        else {
            throw ClaudeStatusLineConfigurationError.concurrentModification
        }
        var repaired = backup.root
        try repaired.installRelay(command: relayCommand)
        let repairedBytes = try encodeRoot(repaired)
        let repairedMetadata = ClaudeStatusLineConfigurationMetadata(
            originalSettingsExisted: metadata.originalSettingsExisted,
            originalParentExisted: metadata.originalParentExisted,
            originalByteCount: metadata.originalByteCount,
            originalSHA256: metadata.originalSHA256,
            originalMode: metadata.originalMode,
            originalOwnerID: metadata.originalOwnerID,
            priorStatusLinePresent: metadata.priorStatusLinePresent,
            installedSHA256: Self.sha256(repairedBytes)
        )
        try verifyCurrentSettingsUnchanged(current)
        try writeSettings(repairedBytes)
        try writeFile(
            try encodeMetadata(repairedMetadata),
            to: paths.metadataURL,
            mode: 0o600,
            replacing: true
        )
    }

    public func disable() throws {
        try restore()
    }

    public func restore() throws {
        try validateAuthority()
        let metadata = try loadMetadata()
        let backup = try loadBackup(metadata: metadata)
        let current = try loadCurrentSettings()
        let currentHash = Self.sha256(current.bytes)
        guard current.existed,
              currentHash == metadata.installedSHA256,
              try current.root.isRelayInstalled(relayCommand: relayCommand)
        else {
            throw ClaudeStatusLineConfigurationError.concurrentModification
        }
        try verifyCurrentSettingsUnchanged(current)
        try restoreOriginal(bytes: backup.bytes, metadata: metadata)
        try removeIntegrationArtifacts()
    }

    public func uninstall() throws {
        if FileManager.default.fileExists(
            atPath: paths.metadataURL.path
        ) {
            try restore()
        } else if FileManager.default.fileExists(
            atPath: paths.integrationDirectoryURL.path
        ) {
            let contents = try FileManager.default.contentsOfDirectory(
                atPath: paths.integrationDirectoryURL.path
            )
            guard contents.isEmpty || Set(contents) == ["usage.sock"] else {
                throw ClaudeStatusLineConfigurationError
                    .backupUnavailable
            }
            if contents.isEmpty {
                try FileManager.default.removeItem(
                    at: paths.integrationDirectoryURL
                )
            }
        }
    }

    public func priorCommandFromBackup() throws -> String? {
        let metadata = try loadMetadata()
        let backup = try loadBackup(metadata: metadata)
        return try safePriorCommand(from: backup.root)
    }

    private func validateAuthority() throws {
        switch authority {
        case .userWritable:
            break
        case .managed:
            throw ClaudeStatusLineConfigurationError.managedConfiguration
        case .unknown:
            throw ClaudeStatusLineConfigurationError.authorityUnverified
        }
        guard ClaudePriorCommandPolicy.classify(
            relayCommand,
            relayExecutableName: ""
        ) == .safe else {
            if relayCommand.contains("ClaudeStatusLineRelay") {
                return
            }
            throw ClaudeStatusLineConfigurationError.relayUnavailable
        }
    }

    private func loadCurrentSettings() throws -> SettingsDocument {
        let parent = paths.settingsURL.deletingLastPathComponent()
        let parentExisted = FileManager.default.fileExists(
            atPath: parent.path
        )
        guard FileManager.default.fileExists(
            atPath: paths.settingsURL.path
        ) else {
            return SettingsDocument(
                existed: false,
                parentExisted: parentExisted,
                bytes: Data(),
                mode: 0o600,
                root: .object([:])
            )
        }
        let file = try readValidatedRegularFile(
            at: paths.settingsURL,
            maximumBytes: Self.maximumSettingsBytes
        )
        return SettingsDocument(
            existed: true,
            parentExisted: parentExisted,
            bytes: file.bytes,
            mode: UInt16(file.mode & 0o777),
            root: try decodeRoot(file.bytes)
        )
    }

    private func loadBackup(
        metadata: ClaudeStatusLineConfigurationMetadata
    ) throws -> SettingsDocument {
        let file = try readValidatedRegularFile(
            at: paths.backupURL,
            maximumBytes: Self.maximumSettingsBytes
        )
        guard (file.mode & 0o777) == 0o600 else {
            throw ClaudeStatusLineConfigurationError.insecurePermissions
        }
        let bytes = file.bytes
        guard bytes.count == metadata.originalByteCount else {
            throw ClaudeStatusLineConfigurationError.backupMismatch
        }
        if metadata.originalSettingsExisted {
            guard metadata.originalSHA256 == Self.sha256(bytes) else {
                throw ClaudeStatusLineConfigurationError.backupMismatch
            }
        } else {
            guard bytes.isEmpty else {
                throw ClaudeStatusLineConfigurationError.backupMismatch
            }
        }
        return SettingsDocument(
            existed: metadata.originalSettingsExisted,
            parentExisted: metadata.originalParentExisted,
            bytes: bytes,
            mode: metadata.originalMode ?? 0o600,
            root: metadata.originalSettingsExisted
                ? try decodeRoot(bytes)
                : .object([:])
        )
    }

    private func loadMetadata()
    throws -> ClaudeStatusLineConfigurationMetadata {
        let file = try readValidatedRegularFile(
            at: paths.metadataURL,
            maximumBytes: 64 * 1_024
        )
        guard (file.mode & 0o777) == 0o600 else {
            throw ClaudeStatusLineConfigurationError.insecurePermissions
        }
        do {
            return try JSONDecoder().decode(
                ClaudeStatusLineConfigurationMetadata.self,
                from: file.bytes
            )
        } catch {
            throw ClaudeStatusLineConfigurationError.metadataMismatch
        }
    }

    private func decodeRoot(_ data: Data) throws -> ClaudeJSONValue {
        guard !data.isEmpty else { return .object([:]) }
        let root: ClaudeJSONValue
        do {
            root = try JSONDecoder().decode(
                ClaudeJSONValue.self,
                from: data
            )
        } catch {
            throw ClaudeStatusLineConfigurationError.malformedSettings
        }
        guard case let .object(object) = root else {
            throw ClaudeStatusLineConfigurationError.malformedSettings
        }
        if case let .number(version)? = object["schemaVersion"],
           version > 1 {
            throw ClaudeStatusLineConfigurationError
                .unsupportedFutureSchema
        }
        if object["disableAllHooks"] == .bool(true) {
            throw ClaudeStatusLineConfigurationError.hooksDisabled
        }
        if object["allowManagedHooksOnly"] == .bool(true) {
            throw ClaudeStatusLineConfigurationError.managedRestriction
        }
        return root
    }

    private func encodeRoot(_ value: ClaudeJSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        var data = try encoder.encode(value)
        data.append(0x0A)
        guard data.count <= Self.maximumSettingsBytes else {
            throw ClaudeStatusLineConfigurationError.recordTooLarge
        }
        return data
    }

    private func encodeMetadata(
        _ metadata: ClaudeStatusLineConfigurationMetadata
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(metadata)
    }

    private func safePriorCommand(
        from root: ClaudeJSONValue
    ) throws -> String? {
        guard let statusLine = try root.statusLineObject() else {
            return nil
        }
        guard case let .string(type)? = statusLine["type"],
              type == "command",
              case let .string(command)? = statusLine["command"]
        else {
            throw ClaudeStatusLineConfigurationError
                .unsupportedFutureSchema
        }
        switch ClaudePriorCommandPolicy.classify(command) {
        case .safe:
            break
        case .unsafeLiteralSecret:
            throw ClaudeStatusLineConfigurationError.unsafeLiteralSecret
        case .recursive:
            throw ClaudeStatusLineConfigurationError.recursivePriorCommand
        case .malformed:
            throw ClaudeStatusLineConfigurationError
                .unsupportedFutureSchema
        }
        return command
    }

    private func prepareIntegrationDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: paths.integrationDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ClaudeStatusLineConfigurationError.persistenceUnavailable
        }
        try validateOwnedDirectory(at: paths.integrationDirectoryURL)
        guard chmod(paths.integrationDirectoryURL.path, 0o700) == 0 else {
            throw ClaudeStatusLineConfigurationError.insecurePermissions
        }
    }

    private func writeSettings(_ data: Data) throws {
        let parent = paths.settingsURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ClaudeStatusLineConfigurationError.persistenceUnavailable
        }
        try validateOwnedDirectory(at: parent)
        try writeFile(
            data,
            to: paths.settingsURL,
            mode: 0o600,
            replacing: true
        )
    }

    private func writeFile(
        _ data: Data,
        to url: URL,
        mode: mode_t,
        replacing: Bool
    ) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".uma-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            guard chmod(temporary.path, mode) == 0 else {
                throw ClaudeStatusLineConfigurationError
                    .insecurePermissions
            }
            if replacing {
                guard rename(temporary.path, url.path) == 0 else {
                    throw ClaudeStatusLineConfigurationError
                        .persistenceUnavailable
                }
            } else {
                guard link(temporary.path, url.path) == 0 else {
                    throw errno == EEXIST
                        ? ClaudeStatusLineConfigurationError
                            .concurrentModification
                        : ClaudeStatusLineConfigurationError
                            .persistenceUnavailable
                }
                guard unlink(temporary.path) == 0 else {
                    throw ClaudeStatusLineConfigurationError
                        .persistenceUnavailable
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            if let typed = error as? ClaudeStatusLineConfigurationError {
                throw typed
            }
            throw ClaudeStatusLineConfigurationError.persistenceUnavailable
        }
    }

    private func restoreOriginal(
        bytes: Data,
        metadata: ClaudeStatusLineConfigurationMetadata
    ) throws {
        if metadata.originalSettingsExisted {
            try writeFile(
                bytes,
                to: paths.settingsURL,
                mode: mode_t(metadata.originalMode ?? 0o600),
                replacing: true
            )
        } else {
            if FileManager.default.fileExists(
                atPath: paths.settingsURL.path
            ) {
                try FileManager.default.removeItem(at: paths.settingsURL)
            }
            if !metadata.originalParentExisted {
                let parent = paths.settingsURL.deletingLastPathComponent()
                if (try? FileManager.default.contentsOfDirectory(
                    atPath: parent.path
                ).isEmpty) == true {
                    try FileManager.default.removeItem(at: parent)
                }
            }
        }
    }

    private func removeIntegrationArtifacts() throws {
        for url in [paths.metadataURL, paths.backupURL] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        if FileManager.default.fileExists(
            atPath: paths.integrationDirectoryURL.path
        ) {
            let contents = try FileManager.default.contentsOfDirectory(
                atPath: paths.integrationDirectoryURL.path
            )
            guard contents.isEmpty || Set(contents) == ["usage.sock"] else {
                throw ClaudeStatusLineConfigurationError
                    .persistenceUnavailable
            }
            if contents.isEmpty {
                try FileManager.default.removeItem(
                    at: paths.integrationDirectoryURL
                )
            }
        }
    }

    private func readValidatedRegularFile(
        at url: URL,
        maximumBytes: Int
    ) throws -> (mode: mode_t, bytes: Data) {
        let descriptor = open(
            url.path,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw errno == ELOOP
                ? ClaudeStatusLineConfigurationError.insecurePath
                : ClaudeStatusLineConfigurationError.backupUnavailable
        }
        defer { Darwin.close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw ClaudeStatusLineConfigurationError.backupUnavailable
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw ClaudeStatusLineConfigurationError.nonRegularFile
        }
        guard info.st_uid == expectedOwnerID else {
            throw ClaudeStatusLineConfigurationError.wrongOwner
        }
        guard info.st_nlink == 1 else {
            throw ClaudeStatusLineConfigurationError.hardLinkedFile
        }
        guard info.st_size >= 0, info.st_size <= maximumBytes else {
            throw ClaudeStatusLineConfigurationError.recordTooLarge
        }

        var bytes = Data()
        bytes.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 8 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw ClaudeStatusLineConfigurationError.backupUnavailable
            }
            bytes.append(buffer, count: count)
            guard bytes.count <= maximumBytes else {
                throw ClaudeStatusLineConfigurationError.recordTooLarge
            }
        }

        var finalInfo = stat()
        guard fstat(descriptor, &finalInfo) == 0,
              finalInfo.st_dev == info.st_dev,
              finalInfo.st_ino == info.st_ino,
              finalInfo.st_size == info.st_size,
              finalInfo.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
              finalInfo.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec,
              bytes.count == Int(finalInfo.st_size)
        else {
            throw ClaudeStatusLineConfigurationError.concurrentModification
        }
        return (info.st_mode, bytes)
    }

    private func validateOwnedDirectory(at url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR
        else {
            throw ClaudeStatusLineConfigurationError.insecurePath
        }
        guard info.st_uid == expectedOwnerID else {
            throw ClaudeStatusLineConfigurationError.wrongOwner
        }
    }

    private func verifyCurrentSettingsUnchanged(
        _ expected: SettingsDocument
    ) throws {
        let current = try loadCurrentSettings()
        guard current.existed == expected.existed,
              current.bytes == expected.bytes,
              current.mode == expected.mode
        else {
            throw ClaudeStatusLineConfigurationError.concurrentModification
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }
            .joined()
    }

    private static func state(
        for error: ClaudeStatusLineConfigurationError
    ) -> ClaudeStatusLineConfigurationState {
        switch error {
        case .authorityUnverified,
             .managedConfiguration,
             .unsupportedFutureSchema,
             .hooksDisabled,
             .managedRestriction:
            .unsupported
        case .backupUnavailable,
             .backupMismatch,
             .metadataMismatch,
             .concurrentModification:
            .repairRequired
        default:
            .failed
        }
    }
}

private struct SettingsDocument {
    let existed: Bool
    let parentExisted: Bool
    let bytes: Data
    let mode: UInt16
    let root: ClaudeJSONValue
}

private extension ClaudeJSONValue {
    func statusLineObject() throws -> [String: ClaudeJSONValue]? {
        guard case let .object(root) = self else {
            throw ClaudeStatusLineConfigurationError.malformedSettings
        }
        switch root["statusLine"] {
        case nil, .null:
            return nil
        case let .object(object):
            return object
        default:
            throw ClaudeStatusLineConfigurationError
                .unsupportedFutureSchema
        }
    }

    func nonStatusLineObject() throws -> ClaudeJSONValue {
        guard case var .object(root) = self else {
            throw ClaudeStatusLineConfigurationError.malformedSettings
        }
        root["statusLine"] = nil
        return .object(root)
    }

    mutating func installRelay(command: String) throws {
        guard case var .object(root) = self else {
            throw ClaudeStatusLineConfigurationError.malformedSettings
        }
        var object = try statusLineObject() ?? [:]
        if let type = object["type"], type != .string("command") {
            throw ClaudeStatusLineConfigurationError
                .unsupportedFutureSchema
        }
        object["type"] = .string("command")
        object["command"] = .string(command)
        root["statusLine"] = .object(object)
        self = .object(root)
    }

    func isRelayInstalled(relayCommand: String) throws -> Bool {
        guard let statusLine = try statusLineObject(),
              statusLine["type"] == .string("command"),
              statusLine["command"] == .string(relayCommand)
        else {
            return false
        }
        return true
    }
}
