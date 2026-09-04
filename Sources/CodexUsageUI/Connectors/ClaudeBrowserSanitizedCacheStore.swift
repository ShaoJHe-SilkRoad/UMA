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
    static var defaultURL: URL { ApplicationDataPaths.current().browserCacheURL }

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
        let directory = url.deletingLastPathComponent()
        guard validateNoSymlinkTraversal(to: url),
              (try? validateItem(
                  at: directory,
                  expectedType: .typeDirectory,
                  permissions: Self.directoryPermissions
              )) != nil
        else { return nil }

        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        guard let metadata = try? validateDescriptor(
            descriptor,
            expectedType: .typeRegular,
            permissions: Self.filePermissions
        ),
              metadata.st_size > 0,
              metadata.st_size <= ClaudeBrowserBridgeContract.maximumMessageBytes,
              let data = try? readExactly(Int(metadata.st_size), from: descriptor),
              (try? validateItemMatchesDescriptor(
                  at: url,
                  descriptorMetadata: metadata,
                  permissions: Self.filePermissions
              )) != nil,
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
        guard validateNoSymlinkTraversal(to: url) else {
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

        let temporaryURL = URL(fileURLWithPath: url.path + ".tmp")
        try removeOwnedRegularFileIfPresent(at: temporaryURL)
        let descriptor = open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(Self.filePermissions)
        )
        guard descriptor >= 0 else { throw StoreError.invalidPath }
        var removeTemporary = true
        defer {
            Darwin.close(descriptor)
            if removeTemporary { unlink(temporaryURL.path) }
        }
        _ = try validateDescriptor(
            descriptor,
            expectedType: .typeRegular,
            permissions: Self.filePermissions
        )
        try writeAll(canonical, to: descriptor)
        guard fsync(descriptor) == 0,
              rename(temporaryURL.path, url.path) == 0
        else { throw StoreError.invalidPath }
        removeTemporary = false
        try validateItem(
            at: url,
            expectedType: .typeRegular,
            permissions: Self.filePermissions
        )
    }

    func clear() throws {
        var initial = stat()
        if lstat(url.path, &initial) != 0 {
            guard errno == ENOENT else { throw StoreError.invalidPath }
            return
        }
        guard (initial.st_mode & S_IFMT) == S_IFREG else {
            throw StoreError.wrongType
        }
        let directory = url.deletingLastPathComponent()
        guard validateNoSymlinkTraversal(to: url) else {
            throw StoreError.invalidPath
        }
        try validateItem(
            at: directory,
            expectedType: .typeDirectory,
            permissions: Self.directoryPermissions
        )
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StoreError.invalidPath }
        defer { Darwin.close(descriptor) }
        let opened = try validateDescriptor(
            descriptor,
            expectedType: .typeRegular,
            permissions: Self.filePermissions
        )
        var current = stat()
        guard lstat(url.path, &current) == 0,
              (current.st_mode & S_IFMT) == S_IFREG,
              current.st_uid == ownerID,
              Int(current.st_mode & 0o777) == Self.filePermissions,
              current.st_dev == opened.st_dev,
              current.st_ino == opened.st_ino,
              unlink(url.path) == 0
        else { throw StoreError.invalidPath }
    }

    private func validateDescriptor(
        _ descriptor: Int32,
        expectedType: FileAttributeType,
        permissions: Int
    ) throws -> stat {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
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
        return metadata
    }

    private func removeOwnedRegularFileIfPresent(at location: URL) throws {
        var metadata = stat()
        if lstat(location.path, &metadata) != 0 {
            guard errno == ENOENT else { throw StoreError.invalidPath }
            return
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw StoreError.wrongType
        }
        guard metadata.st_uid == ownerID else { throw StoreError.wrongOwner }
        guard Int(metadata.st_mode & 0o777) == Self.filePermissions else {
            throw StoreError.wrongPermissions
        }
        guard unlink(location.path) == 0 else { throw StoreError.invalidPath }
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw StoreError.invalidPath }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    bytes.count - offset
                )
                guard written > 0 else { throw StoreError.invalidPath }
                offset += written
            }
        }
    }

    private func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
        var data = Data(count: count)
        let bytesRead = data.withUnsafeMutableBytes { bytes -> Int in
            guard let base = bytes.baseAddress else { return -1 }
            var offset = 0
            while offset < count {
                let current = Darwin.read(
                    descriptor,
                    base.advanced(by: offset),
                    count - offset
                )
                guard current > 0 else { return -1 }
                offset += current
            }
            return offset
        }
        guard bytesRead == count else { throw StoreError.invalidPath }
        return data
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

    private func validateItemMatchesDescriptor(
        at location: URL,
        descriptorMetadata: stat,
        permissions: Int
    ) throws {
        var pathMetadata = stat()
        let result = location.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &pathMetadata)
        }
        guard result == 0,
              (pathMetadata.st_mode & S_IFMT) == S_IFREG,
              pathMetadata.st_uid == ownerID,
              Int(pathMetadata.st_mode & 0o777) == permissions,
              pathMetadata.st_dev == descriptorMetadata.st_dev,
              pathMetadata.st_ino == descriptorMetadata.st_ino
        else { throw StoreError.invalidPath }
    }

    private func validateNoSymlinkTraversal(to location: URL) -> Bool {
        var current = "/"
        // Validate every parent component. The leaf is checked separately with
        // lstat/open(O_NOFOLLOW), which preserves the more precise wrongType
        // failure for a symlink placed at the cache file itself.
        for component in (location.path as NSString).pathComponents
            .dropFirst()
            .dropLast()
        {
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
