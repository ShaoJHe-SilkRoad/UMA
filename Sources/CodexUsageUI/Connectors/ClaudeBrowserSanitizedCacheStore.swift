import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Darwin
import Foundation

/// Owner-only persistence for the strict browser-companion quota envelope.
/// The bridge decoder rejects every field outside the normalized allowlist
/// before bytes may be written.
actor ClaudeBrowserSanitizedCacheStore {
    enum StoreError: Error, Equatable {
        case invalidPath
        case wrongType
        case wrongOwner
        case wrongPermissions
        case rejectedPayload
    }

    static let directoryPermissions = 0o700
    static let filePermissions = 0o600
    static let defaultURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodexUsageMonitor", isDirectory: true)
        .appendingPathComponent("ClaudeBrowserIntegration", isDirectory: true)
        .appendingPathComponent("sanitized-quota.json", isDirectory: false)

    private let url: URL
    private let fileManager: FileManager
    private let ownerID: uid_t

    init(
        url: URL = ClaudeBrowserSanitizedCacheStore.defaultURL,
        fileManager: FileManager = .default,
        ownerID: uid_t = geteuid()
    ) {
        self.url = url.standardizedFileURL
        self.fileManager = fileManager
        self.ownerID = ownerID
    }

    func load() -> Data? {
        guard validateNoSymlinkTraversal(to: url),
              (try? validateItem(
                  at: url,
                  expectedType: .typeRegular,
                  permissions: Self.filePermissions
              )) != nil,
              let data = try? Data(contentsOf: url),
              data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes,
              let envelope = try? ClaudeBrowserMessageDecoder.decode(data),
              let canonical = try? ClaudeBrowserMessageDecoder.encode(envelope)
        else { return nil }
        return canonical
    }

    func save(_ data: Data) throws {
        guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes,
              let envelope = try? ClaudeBrowserMessageDecoder.decode(data),
              let canonical = try? ClaudeBrowserMessageDecoder.encode(envelope),
              canonical.count <= ClaudeBrowserBridgeContract.maximumMessageBytes
        else { throw StoreError.rejectedPayload }

        let directory = url.deletingLastPathComponent()
        guard validateNoSymlinkTraversal(to: directory) else {
            throw StoreError.invalidPath
        }
        if fileManager.fileExists(atPath: directory.path) {
            try validateItem(
                at: directory,
                expectedType: .typeDirectory,
                permissions: Self.directoryPermissions
            )
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: Self.directoryPermissions]
            )
            try fileManager.setAttributes(
                [.posixPermissions: Self.directoryPermissions],
                ofItemAtPath: directory.path
            )
            try validateItem(
                at: directory,
                expectedType: .typeDirectory,
                permissions: Self.directoryPermissions
            )
        }

        if fileManager.fileExists(atPath: url.path) {
            try validateItem(
                at: url,
                expectedType: .typeRegular,
                permissions: Self.filePermissions
            )
        }
        try canonical.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: url.path
        )
        try validateItem(
            at: url,
            expectedType: .typeRegular,
            permissions: Self.filePermissions
        )
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard validateNoSymlinkTraversal(to: url) else {
            throw StoreError.invalidPath
        }
        try validateItem(
            at: url,
            expectedType: .typeRegular,
            permissions: Self.filePermissions
        )
        try fileManager.removeItem(at: url)
    }

    private func validateItem(
        at location: URL,
        expectedType: FileAttributeType,
        permissions: Int
    ) throws {
        var metadata = stat()
        let result = location.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &metadata)
        }
        guard result == 0 else {
            throw StoreError.invalidPath
        }
        let expectedMode: mode_t = expectedType == .typeDirectory ? S_IFDIR : S_IFREG
        guard metadata.st_mode & S_IFMT == expectedMode else {
            throw StoreError.wrongType
        }
        guard metadata.st_uid == ownerID else {
            throw StoreError.wrongOwner
        }
        guard Int(metadata.st_mode & 0o777) == permissions else {
            throw StoreError.wrongPermissions
        }
    }

    private func validateNoSymlinkTraversal(to location: URL) -> Bool {
        var current = "/"
        for component in (location.path as NSString).pathComponents.dropFirst() {
            current = (current as NSString).appendingPathComponent(component)
            var metadata = stat()
            let result = current.withCString { Darwin.lstat($0, &metadata) }
            if result == 0 {
                guard metadata.st_mode & S_IFMT != S_IFLNK else { return false }
            } else if errno != ENOENT {
                return false
            }
        }
        return true
    }
}
