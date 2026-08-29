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
        runtime(.production, uid: uid)
    }

    public static func runtime(
        _ identity: ClaudeBrowserRuntimeIdentity,
        uid: uid_t = getuid()
    ) -> Self {
        let home: String
        if let record = getpwuid(uid), let path = record.pointee.pw_dir {
            home = String(cString: path)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser.path
        }
        return Self(
            directoryPath: home + "/" + identity.handoffDirectoryRelativePath
        )
    }

    /// Native Safari-extension output is delivered to the immutable Host's
    /// App Group inbox. The mutable UMA application never listens here and is
    /// therefore not a surrogate Safari containing application.
    public static func safariHostAppGroup(containerDirectoryPath: String) -> Self {
        Self(
            directoryPath: containerDirectoryPath
                + "/ClaudeSafariHost/NativeInbox"
        )
    }

    /// Durable owned-tab receipts are Host-owned lifecycle evidence and are
    /// intentionally separated from both native output and UMA responses.
    public static func safariHostOwnedTab(containerDirectoryPath: String) -> Self {
        Self(
            directoryPath: containerDirectoryPath
                + "/ClaudeSafariHost/OwnedTab"
        )
    }

    public var pendingPath: String { directoryPath + "/observation.pending" }
    public var temporaryPath: String { directoryPath + "/observation.pending.tmp" }
    public var listenerLockPath: String { directoryPath + "/listener.lock" }
    public var legacySocketPath: String { directoryPath + "/usage.sock" }
}

public enum ClaudeBrowserAutomationRejectionReason: Equatable, Sendable {
    case protocolMismatch
}

public struct ClaudeBrowserAutomationRejection: Equatable, Sendable {
    public let requestID: String
    public let reason: ClaudeBrowserAutomationRejectionReason

    public init(requestID: String, reason: ClaudeBrowserAutomationRejectionReason) {
        self.requestID = requestID
        self.reason = reason
    }
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
        guard (try? ClaudeBrowserMessageDecoder.decode(payload)) != nil
            || (try? ClaudeBrowserAutomationEventDecoder.decode(payload)) != nil
            || (try? ClaudeBrowserTerminalPacketDecoder.decode(payload)) != nil
        else {
            throw ClaudeBrowserBridgeError.invalidContract
        }
        guard hasNoSymlinkTraversal(endpoint.directoryPath) else {
            throw ClaudeBrowserBridgeError.socketUnsafe
        }
        try validatePrivateDirectory(endpoint.directoryPath, uid: uid)
        try requireActiveListener(endpoint.listenerLockPath, uid: uid)
        try removeOwnedRegularFileIfPresent(endpoint.temporaryPath, uid: uid)
        try waitForPendingSlot(endpoint.pendingPath, uid: uid)

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

/// Native-message replies can arrive faster than the app's directory event
/// handler consumes the prior file. Keep the local bridge lossless without
/// overwriting or retrying a provider read: each writer waits only for the
/// preceding validated handoff slot to drain.
private func waitForPendingSlot(_ path: String, uid: uid_t) throws {
    for _ in 0..<200 {
        var metadata = stat()
        if lstat(path, &metadata) != 0 {
            guard errno == ENOENT else { throw ClaudeBrowserBridgeError.socketUnsafe }
            return
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == uid,
              (metadata.st_mode & 0o777) == 0o600,
              metadata.st_size > 0,
              metadata.st_size <= ClaudeBrowserBridgeContract.maximumMessageBytes
        else { throw ClaudeBrowserBridgeError.socketUnsafe }
        usleep(10_000)
    }
    throw ClaudeBrowserBridgeError.socketWriteFailed
}

public final class ClaudeBrowserFileHandoffServer: @unchecked Sendable {
    public typealias ObservationHandler = @Sendable (ClaudeBrowserObservationEnvelope) -> Void
    public typealias AutomationHandler = @Sendable (ClaudeBrowserAutomationEvent) -> Void
    public typealias AutomationRejectionHandler = @Sendable (ClaudeBrowserAutomationRejection) -> Void
    public typealias TerminalHandler = @Sendable (ClaudeBrowserTerminalPacket) -> Void

    private let endpoint: ClaudeBrowserFileHandoffEndpoint
    private let uid: uid_t
    private let handler: ObservationHandler
    private let automationHandler: AutomationHandler?
    private let automationRejectionHandler: AutomationRejectionHandler?
    private let terminalHandler: TerminalHandler?
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
        automationHandler = nil
        automationRejectionHandler = nil
        terminalHandler = nil
    }

    public init(
        endpoint: ClaudeBrowserFileHandoffEndpoint = .production(),
        uid: uid_t = getuid(),
        observationHandler: @escaping ObservationHandler,
        automationHandler: @escaping AutomationHandler,
        automationRejectionHandler: AutomationRejectionHandler? = nil,
        terminalHandler: TerminalHandler? = nil
    ) {
        self.endpoint = endpoint
        self.uid = uid
        handler = observationHandler
        self.automationHandler = automationHandler
        self.automationRejectionHandler = automationRejectionHandler
        self.terminalHandler = terminalHandler
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
        // A native reply may land after the listener lock is acquired but
        // before the directory source is resumed. Drain once explicitly so a
        // cold-start packet is consumed instead of being deleted or stranded.
        queue.async { [weak self] in self?.consumePendingObservation() }
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
              let payload = try? readAndRemovePendingPayload()
        else { return }
        if let envelope = try? ClaudeBrowserMessageDecoder.decode(payload) {
            handler(envelope)
        } else if let event = try? ClaudeBrowserAutomationEventDecoder.decode(payload) {
            automationHandler?(event)
        } else if let terminal = try? ClaudeBrowserTerminalPacketDecoder.decode(payload) {
            terminalHandler?(terminal)
        } else if let rejection = Self.protocolMismatchRejection(payload) {
            automationRejectionHandler?(rejection)
        }
    }

    static func protocolMismatchRejection(
        _ payload: Data
    ) -> ClaudeBrowserAutomationRejection? {
        guard let object = try? JSONSerialization.jsonObject(with: payload),
              let dictionary = object as? [String: Any],
              dictionary["kind"] as? String
                == ClaudeBrowserBridgeContract.automationMessageKind,
              dictionary["status"] as? String
                == ClaudeBrowserAutomationStatus.bridgeReady.rawValue,
              let requestID = dictionary["requestID"] as? String,
              UUID(uuidString: requestID) != nil,
              (try? ClaudeBrowserAutomationEventDecoder.decode(payload)) == nil
        else { return nil }
        return ClaudeBrowserAutomationRejection(
            requestID: requestID,
            reason: .protocolMismatch
        )
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
