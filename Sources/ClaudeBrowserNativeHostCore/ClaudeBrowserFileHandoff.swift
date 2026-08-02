import ClaudeBrowserBridgeProtocol
import Darwin
import Dispatch
import Foundation

public struct ClaudeBrowserFileHandoffEndpoint: Equatable, Sendable {
    public static let privateDirectoryRelativePath =
        "Library/Application Support/CodexUsageMonitor/ClaudeBrowserCompanion"

    public let directoryPath: String

    public init(directoryPath: String) {
        self.directoryPath = directoryPath
    }

    public static func production(uid: uid_t = getuid()) -> Self {
        let home: String
        if let record = getpwuid(uid), let path = record.pointee.pw_dir {
            home = String(cString: path)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser.path
        }
        return Self(directoryPath: home + "/" + privateDirectoryRelativePath)
    }

    public var pendingPath: String { directoryPath + "/observation.pending" }
    public var temporaryPath: String { directoryPath + "/observation.pending.tmp" }
    public var listenerLockPath: String { directoryPath + "/listener.lock" }
    public var legacySocketPath: String { directoryPath + "/usage.sock" }
}

public enum ClaudeBrowserFileHandoffWriter {
    /// Writes one already-normalized observation into the exact owner-only
    /// handoff directory. The active-listener lock proves a live UMA process
    /// owns the destination; no network capability or alternate path exists.
    public static func write(
        _ payload: Data,
        endpoint: ClaudeBrowserFileHandoffEndpoint = .production(),
        uid: uid_t = getuid()
    ) throws {
        _ = try ClaudeBrowserMessageDecoder.decode(payload)
        guard hasNoSymlinkTraversal(endpoint.directoryPath) else {
            throw ClaudeBrowserBridgeError.socketUnsafe
        }
        try validatePrivateDirectory(endpoint.directoryPath, uid: uid)
        try requireActiveListener(endpoint.listenerLockPath, uid: uid)
        try removeOwnedRegularFileIfPresent(endpoint.temporaryPath, uid: uid)

        let descriptor = open(
            endpoint.temporaryPath,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw ClaudeBrowserBridgeError.socketUnavailable }
        var shouldRemoveTemporary = true
        defer {
            Darwin.close(descriptor)
            if shouldRemoveTemporary { unlink(endpoint.temporaryPath) }
        }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == uid,
              fchmod(descriptor, 0o600) == 0
        else { throw ClaudeBrowserBridgeError.socketUnsafe }
        try writeAllBytes(payload, to: descriptor)
        guard fsync(descriptor) == 0 else { throw ClaudeBrowserBridgeError.socketWriteFailed }
        // Publish without replacing an unread observation. This keeps rapid
        // toolbar actions bounded to one in-flight native handoff instead of
        // silently overwriting an earlier message.
        guard renamex_np(
            endpoint.temporaryPath,
            endpoint.pendingPath,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw ClaudeBrowserBridgeError.socketWriteFailed
        }
        shouldRemoveTemporary = false
    }

    private static func requireActiveListener(_ path: String, uid: uid_t) throws {
        let descriptor = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ClaudeBrowserBridgeError.socketUnavailable }
        defer { Darwin.close(descriptor) }
        try validateOwnedRegularFile(descriptor: descriptor, uid: uid)

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN)
            throw ClaudeBrowserBridgeError.socketUnavailable
        }
        guard errno == EWOULDBLOCK else {
            throw ClaudeBrowserBridgeError.socketUnsafe
        }
    }
}

public final class ClaudeBrowserFileHandoffServer: @unchecked Sendable {
    public typealias ObservationHandler = @Sendable (ClaudeBrowserObservationEnvelope) -> Void

    private let endpoint: ClaudeBrowserFileHandoffEndpoint
    private let uid: uid_t
    private let handler: ObservationHandler
    private let queue = DispatchQueue(label: "com.silkrd.uma.claude-browser.file-handoff")
    private let stateLock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var listenerLockDescriptor: Int32 = -1
    private var running = false

    public init(
        endpoint: ClaudeBrowserFileHandoffEndpoint = .production(),
        uid: uid_t = getuid(),
        handler: @escaping ObservationHandler
    ) {
        self.endpoint = endpoint
        self.uid = uid
        self.handler = handler
    }

    deinit { stop() }

    public func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !running else { return }

        try preparePrivateDirectory(endpoint.directoryPath, uid: uid)
        let lockDescriptor = try openListenerLock(endpoint.listenerLockPath, uid: uid)
        do {
            guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                if errno == EWOULDBLOCK {
                    throw ClaudeBrowserBridgeError.socketUnavailable
                }
                throw ClaudeBrowserBridgeError.socketUnsafe
            }
            try removeOwnedRegularFileIfPresent(endpoint.pendingPath, uid: uid)
            try removeOwnedRegularFileIfPresent(endpoint.temporaryPath, uid: uid)
            try removeOwnedSocketIfPresent(endpoint.legacySocketPath, uid: uid)
        } catch {
            Darwin.close(lockDescriptor)
            throw error
        }

        let directoryDescriptor = open(endpoint.directoryPath, O_EVTONLY | O_CLOEXEC)
        guard directoryDescriptor >= 0 else {
            try? removeOwnedRegularFileMatching(
                endpoint.listenerLockPath,
                descriptor: lockDescriptor,
                uid: uid
            )
            flock(lockDescriptor, LOCK_UN)
            Darwin.close(lockDescriptor)
            throw ClaudeBrowserBridgeError.socketUnavailable
        }

        let nextSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .rename],
            queue: queue
        )
        nextSource.setEventHandler { [weak self] in self?.consumePendingObservation() }
        nextSource.setCancelHandler { Darwin.close(directoryDescriptor) }
        listenerLockDescriptor = lockDescriptor
        source = nextSource
        running = true
        nextSource.resume()
    }

    public func stop() {
        stateLock.lock()
        let activeSource = source
        source = nil
        let lockDescriptor = listenerLockDescriptor
        listenerLockDescriptor = -1
        running = false
        stateLock.unlock()

        activeSource?.cancel()
        if lockDescriptor >= 0 {
            try? removeOwnedRegularFileIfPresent(endpoint.pendingPath, uid: uid)
            try? removeOwnedRegularFileIfPresent(endpoint.temporaryPath, uid: uid)
            try? removeOwnedSocketIfPresent(endpoint.legacySocketPath, uid: uid)
            try? removeOwnedRegularFileMatching(
                endpoint.listenerLockPath,
                descriptor: lockDescriptor,
                uid: uid
            )
            flock(lockDescriptor, LOCK_UN)
            Darwin.close(lockDescriptor)
        }
    }

    private func consumePendingObservation() {
        stateLock.lock()
        let isRunning = running
        stateLock.unlock()
        guard isRunning,
              let payload = try? readAndRemovePendingPayload(),
              let envelope = try? ClaudeBrowserMessageDecoder.decode(payload)
        else { return }
        handler(envelope)
    }

    private func readAndRemovePendingPayload() throws -> Data {
        let descriptor = open(endpoint.pendingPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ClaudeBrowserBridgeError.socketUnavailable }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == uid,
              (metadata.st_mode & 0o777) == 0o600,
              metadata.st_size > 0,
              metadata.st_size <= ClaudeBrowserBridgeContract.maximumMessageBytes
        else { throw ClaudeBrowserBridgeError.socketUnsafe }
        let payload = try readExactly(Int(metadata.st_size), from: descriptor)
        try removeOwnedRegularFileMatching(
            endpoint.pendingPath,
            descriptor: descriptor,
            uid: uid
        )
        return payload
    }
}

private func openListenerLock(_ path: String, uid: uid_t) throws -> Int32 {
    var descriptor = open(
        path,
        O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        mode_t(0o600)
    )
    if descriptor < 0, errno == EEXIST {
        descriptor = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else { throw ClaudeBrowserBridgeError.socketUnavailable }
    do {
        try validateOwnedRegularFile(descriptor: descriptor, uid: uid)
    } catch {
        Darwin.close(descriptor)
        throw error
    }
    return descriptor
}

private func preparePrivateDirectory(_ path: String, uid: uid_t) throws {
    guard hasNoSymlinkTraversal(path) else {
        throw ClaudeBrowserBridgeError.socketUnsafe
    }
    var existing = stat()
    if lstat(path, &existing) == 0 {
        guard (existing.st_mode & S_IFMT) == S_IFDIR, existing.st_uid == uid else {
            throw ClaudeBrowserBridgeError.socketUnsafe
        }
    } else if errno == ENOENT {
        do {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ClaudeBrowserBridgeError.socketUnavailable
        }
    } else {
        throw ClaudeBrowserBridgeError.socketUnsafe
    }
    guard chmod(path, 0o700) == 0 else { throw ClaudeBrowserBridgeError.socketUnsafe }
    try validatePrivateDirectory(path, uid: uid)
}

private func validatePrivateDirectory(_ path: String, uid: uid_t) throws {
    var metadata = stat()
    guard lstat(path, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == S_IFDIR,
          metadata.st_uid == uid,
          (metadata.st_mode & 0o777) == 0o700
    else { throw ClaudeBrowserBridgeError.socketUnsafe }
}

private func hasNoSymlinkTraversal(_ path: String) -> Bool {
    guard path.hasPrefix("/") else { return false }
    var current = "/"
    for component in (path as NSString).pathComponents.dropFirst() {
        current = (current as NSString).appendingPathComponent(component)
        var metadata = stat()
        if lstat(current, &metadata) == 0 {
            if (metadata.st_mode & S_IFMT) == S_IFLNK { return false }
        } else if errno != ENOENT {
            return false
        }
    }
    return true
}

private func validateOwnedRegularFile(descriptor: Int32, uid: uid_t) throws {
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == S_IFREG,
          metadata.st_uid == uid,
          (metadata.st_mode & 0o777) == 0o600,
          metadata.st_size == 0
    else { throw ClaudeBrowserBridgeError.socketUnsafe }
}

private func removeOwnedRegularFileMatching(
    _ path: String,
    descriptor: Int32,
    uid: uid_t
) throws {
    var descriptorMetadata = stat()
    var pathMetadata = stat()
    guard fstat(descriptor, &descriptorMetadata) == 0,
          lstat(path, &pathMetadata) == 0,
          (descriptorMetadata.st_mode & S_IFMT) == S_IFREG,
          (pathMetadata.st_mode & S_IFMT) == S_IFREG,
          descriptorMetadata.st_uid == uid,
          pathMetadata.st_uid == uid,
          (descriptorMetadata.st_mode & 0o777) == 0o600,
          (pathMetadata.st_mode & 0o777) == 0o600,
          descriptorMetadata.st_dev == pathMetadata.st_dev,
          descriptorMetadata.st_ino == pathMetadata.st_ino,
          unlink(path) == 0
    else { throw ClaudeBrowserBridgeError.socketUnsafe }
}

private func removeOwnedRegularFileIfPresent(_ path: String, uid: uid_t) throws {
    var metadata = stat()
    if lstat(path, &metadata) != 0 {
        guard errno == ENOENT else { throw ClaudeBrowserBridgeError.socketUnsafe }
        return
    }
    guard (metadata.st_mode & S_IFMT) == S_IFREG,
          metadata.st_uid == uid,
          (metadata.st_mode & 0o777) == 0o600,
          unlink(path) == 0
    else { throw ClaudeBrowserBridgeError.socketUnsafe }
}

private func removeOwnedSocketIfPresent(_ path: String, uid: uid_t) throws {
    var metadata = stat()
    if lstat(path, &metadata) != 0 {
        guard errno == ENOENT else { throw ClaudeBrowserBridgeError.socketUnsafe }
        return
    }
    guard (metadata.st_mode & S_IFMT) == S_IFSOCK,
          metadata.st_uid == uid,
          (metadata.st_mode & 0o777) == 0o600,
          unlink(path) == 0
    else { throw ClaudeBrowserBridgeError.socketUnsafe }
}

private func writeAllBytes(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { throw ClaudeBrowserBridgeError.socketWriteFailed }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
            guard count > 0 else { throw ClaudeBrowserBridgeError.socketWriteFailed }
            offset += count
        }
    }
}

private func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
    var data = Data(count: count)
    let result = data.withUnsafeMutableBytes { bytes -> Int in
        guard let base = bytes.baseAddress else { return -1 }
        var offset = 0
        while offset < count {
            let current = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
            guard current > 0 else { return -1 }
            offset += current
        }
        return offset
    }
    guard result == count else { throw ClaudeBrowserBridgeError.socketReadFailed }
    return data
}
