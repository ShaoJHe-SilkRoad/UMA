import Darwin
import Foundation

public enum ClaudeStatusLineStateError: Error, Equatable, Sendable {
    case unsafePath
    case invalidPermissions
    case invalidData
}

/// Owner-only storage for the already-sanitized packet. The full Claude
/// status-line payload is never accepted by this type and cannot be encoded by
/// `ClaudeStatusLinePacket`.
public struct ClaudeStatusLineStateStore: Sendable {
    public let stateURL: URL

    public init(stateURL: URL = ClaudeStatusLinePaths.stateURL()) {
        self.stateURL = stateURL
    }

    public func read() throws -> ClaudeStatusLinePacket? {
        let data: Data?
        do {
            data = try ClaudeOwnedFileReader.read(
                at: stateURL,
                maximumBytes: ClaudeStatusLinePacket.maximumEncodedBytes
            )
        } catch ClaudeOwnedFileReadError.invalidPermissions {
            throw ClaudeStatusLineStateError.invalidPermissions
        } catch ClaudeOwnedFileReadError.oversized {
            throw ClaudeStatusLineStateError.invalidData
        } catch {
            throw ClaudeStatusLineStateError.unsafePath
        }
        guard let data else { return nil }
        return try ClaudeStatusLinePacket.decodePacket(data)
    }

    public func write(_ packet: ClaudeStatusLinePacket) throws {
        let data = try packet.encoded()
        let directory = stateURL.deletingLastPathComponent()
        guard !Self.hasSymbolicLinkComponent(directory),
              !Self.isSymbolicLink(stateURL)
        else { throw ClaudeStatusLineStateError.unsafePath }
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try Self.validateOwnerOnlyRegularFile(stateURL)
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        try Self.validateOwnerOnlyDirectory(directory)
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stateURL.path
        )
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try Self.validateOwnerOnlyRegularFile(stateURL)
            try FileManager.default.removeItem(at: stateURL)
        }
    }

    private static func validateOwnerOnlyRegularFile(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        guard !hasSymbolicLinkComponent(parent), !isSymbolicLink(url) else {
            throw ClaudeStatusLineStateError.unsafePath
        }
        try validateOwnerOnlyDirectory(parent)
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1
        else { throw ClaudeStatusLineStateError.unsafePath }
        guard (info.st_mode & 0o077) == 0 else {
            throw ClaudeStatusLineStateError.invalidPermissions
        }
    }

    private static func validateOwnerOnlyDirectory(_ url: URL) throws {
        guard !hasSymbolicLinkComponent(url), !isSymbolicLink(url) else {
            throw ClaudeStatusLineStateError.unsafePath
        }
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(),
              (info.st_mode & 0o077) == 0
        else { throw ClaudeStatusLineStateError.invalidPermissions }
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

public enum ClaudeStatusLinePaths {
    public static func integrationDirectory(
        applicationSupportDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("CodexUsageMonitor", isDirectory: true)
            .appendingPathComponent("ClaudeLocalSmartMode", isDirectory: true)
    }

    public static func stateURL(
        applicationSupportDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    ) -> URL {
        integrationDirectory(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent("status-line.json")
    }
}

/// Watches only the task-owned state directory. It never observes Claude's
/// process arguments, environment, project paths, or provider files.
public final class ClaudeStatusLineStateMonitor: @unchecked Sendable {
    private let directoryURL: URL
    private let queue: DispatchQueue
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private let lock = NSLock()

    public init(
        directoryURL: URL = ClaudeStatusLinePaths.integrationDirectory(),
        queue: DispatchQueue = DispatchQueue(label: "uma.claude.status-state")
    ) {
        self.directoryURL = directoryURL
        self.queue = queue
    }

    public func start(_ handler: @escaping @Sendable () -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else { return }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard (try? directoryURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw ClaudeStatusLineStateError.unsafePath
        }
        let fd = open(directoryURL.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { throw ClaudeStatusLineStateError.unsafePath }
        let next = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        next.setEventHandler(handler: handler)
        next.setCancelHandler { close(fd) }
        descriptor = fd
        source = next
        next.resume()
    }

    public func stop() {
        lock.lock()
        let current = source
        source = nil
        descriptor = -1
        lock.unlock()
        current?.cancel()
    }

    deinit { stop() }
}
