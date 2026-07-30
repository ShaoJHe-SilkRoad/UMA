import Darwin
import Foundation

public enum ClaudeStatusLineSocketError: Error, Equatable, Sendable {
    case pathTooLong
    case unsafeExistingPath
    case directoryUnavailable
    case socketUnavailable
    case permissionFailure
    case transportFailure
}

public enum ClaudeStatusLineSocketPaths {
    public static func integrationDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("CodexUsageMonitor", isDirectory: true)
            .appendingPathComponent(
                "ClaudeStatusLineIntegration",
                isDirectory: true
            )
    }

    public static func socketURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        integrationDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("usage.sock", isDirectory: false)
    }
}

public struct ClaudeStatusLineSocketClient: Sendable {
    public let socketURL: URL

    public init(socketURL: URL) {
        self.socketURL = socketURL.standardizedFileURL
    }

    /// A missing app-owned listener is an expected no-op.
    public func send(_ packet: ClaudeStatusLinePacket) -> Bool {
        guard Self.isOwnedSocket(at: socketURL) else {
            return false
        }
        guard let address = UnixSocketAddress(path: socketURL.path) else {
            return false
        }
        let descriptor = Darwin.socket(
            AF_UNIX,
            SOCK_STREAM,
            0
        )
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        configureSocketTimeout(descriptor)

        let connected = address.withSockAddr { pointer, length in
            Darwin.connect(descriptor, pointer, length)
        }
        guard connected == 0 else { return false }
        var peerOwner = uid_t()
        var peerGroup = gid_t()
        guard getpeereid(descriptor, &peerOwner, &peerGroup) == 0,
              peerOwner == getuid()
        else {
            return false
        }

        guard var data = try? packet.encoded() else { return false }
        data.append(0x0A)
        return data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    bytes.count - offset
                )
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    private static func isOwnedSocket(at url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(),
              (info.st_mode & 0o077) == 0
        else {
            return false
        }
        return true
    }
}

/// App-owned, single-instance listener. It keeps events in memory only and
/// removes its socket file on shutdown.
public final class ClaudeStatusLineSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ClaudeStatusLinePacket) async -> Void
    public typealias InvalidHandler = @Sendable () async -> Void

    private let socketURL: URL
    private let stateLock = NSLock()
    private var listeningDescriptor: Int32 = -1
    private var listeningIdentity: UnixSocketIdentity?
    private var running = false
    private var handler: Handler?
    private var invalidHandler: InvalidHandler?
    private let queue = DispatchQueue(
        label: "com.kevinchen.uma.claude-status-line.socket",
        qos: .utility
    )

    public init(socketURL: URL) {
        self.socketURL = socketURL.standardizedFileURL
    }

    deinit {
        stop()
    }

    public func start(
        handler: @escaping Handler,
        invalidHandler: InvalidHandler? = nil
    ) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !running else { return }
        let socket = try Self.makeListeningSocket(socketURL: socketURL)
        self.handler = handler
        self.invalidHandler = invalidHandler
        listeningDescriptor = socket.descriptor
        listeningIdentity = socket.identity
        running = true
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    public func stop() {
        stateLock.lock()
        let descriptor = listeningDescriptor
        let identity = listeningIdentity
        listeningDescriptor = -1
        listeningIdentity = nil
        running = false
        handler = nil
        invalidHandler = nil
        stateLock.unlock()
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            if let identity,
               Self.unlinkSocketIfOwned(
                at: socketURL,
                expectedIdentity: identity
               ) {
                let directory = socketURL.deletingLastPathComponent()
                if (try? FileManager.default.contentsOfDirectory(
                    atPath: directory.path
                ).isEmpty) == true {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }
    }

    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    private func acceptLoop() {
        while true {
            stateLock.lock()
            let descriptor = listeningDescriptor
            let shouldContinue = running && descriptor >= 0
            stateLock.unlock()
            guard shouldContinue else { return }

            let client = Darwin.accept(descriptor, nil, nil)
            guard client >= 0 else {
                if errno == EINTR { continue }
                return
            }
            configureSocketTimeout(client)
            var peerOwner = uid_t()
            var peerGroup = gid_t()
            guard getpeereid(client, &peerOwner, &peerGroup) == 0,
                  peerOwner == getuid()
            else {
                Darwin.close(client)
                continue
            }
            let data = Self.readBoundedPacket(from: client)
            Darwin.close(client)
            guard let data,
                  let packet = try? ClaudeStatusLinePacket.decodePacket(data)
            else {
                stateLock.lock()
                let currentInvalidHandler = invalidHandler
                stateLock.unlock()
                if let currentInvalidHandler {
                    Task {
                        await currentInvalidHandler()
                    }
                }
                continue
            }
            stateLock.lock()
            let currentHandler = handler
            stateLock.unlock()
            guard let currentHandler else { continue }
            Task {
                await currentHandler(packet)
            }
        }
    }

    private static func readBoundedPacket(from descriptor: Int32) -> Data? {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while result.count <= ClaudeStatusLinePacket.maximumEncodedBytes {
            let count = Darwin.read(
                descriptor,
                &buffer,
                buffer.count
            )
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                return nil
            }
            result.append(buffer, count: count)
            if let newline = result.firstIndex(of: 0x0A) {
                result = result.prefix(upTo: newline)
                break
            }
        }
        guard !result.isEmpty,
              result.count <= ClaudeStatusLinePacket.maximumEncodedBytes
        else {
            return nil
        }
        return result
    }

    private static func makeListeningSocket(
        socketURL: URL
    ) throws -> ListeningSocket {
        let directory = socketURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ClaudeStatusLineSocketError.directoryUnavailable
        }
        var directoryInfo = stat()
        guard lstat(directory.path, &directoryInfo) == 0,
              (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
              directoryInfo.st_uid == getuid()
        else {
            throw ClaudeStatusLineSocketError.directoryUnavailable
        }
        guard chmod(directory.path, 0o700) == 0 else {
            throw ClaudeStatusLineSocketError.permissionFailure
        }

        var info = stat()
        if lstat(socketURL.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK,
                  info.st_uid == getuid(),
                  (info.st_mode & 0o077) == 0
            else {
                throw ClaudeStatusLineSocketError.unsafeExistingPath
            }
            guard let existingAddress = UnixSocketAddress(
                path: socketURL.path
            ) else {
                throw ClaudeStatusLineSocketError.pathTooLong
            }
            let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard probe >= 0 else {
                throw ClaudeStatusLineSocketError.socketUnavailable
            }
            configureSocketTimeout(probe)
            let connected = existingAddress.withSockAddr {
                Darwin.connect(probe, $0, $1)
            }
            let connectionError = errno
            Darwin.close(probe)
            if connected == 0 {
                throw ClaudeStatusLineSocketError.socketUnavailable
            }
            guard connectionError == ECONNREFUSED
                    || connectionError == ENOENT
            else {
                throw ClaudeStatusLineSocketError.socketUnavailable
            }
            let staleIdentity = UnixSocketIdentity(
                device: info.st_dev,
                inode: info.st_ino
            )
            guard unlinkSocketIfOwned(
                at: socketURL,
                expectedIdentity: staleIdentity
            ) else {
                throw ClaudeStatusLineSocketError.socketUnavailable
            }
        } else if errno != ENOENT {
            throw ClaudeStatusLineSocketError.socketUnavailable
        }

        guard let address = UnixSocketAddress(path: socketURL.path) else {
            throw ClaudeStatusLineSocketError.pathTooLong
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ClaudeStatusLineSocketError.socketUnavailable
        }
        configureSocketTimeout(descriptor)
        var succeeded = false
        var boundIdentity: UnixSocketIdentity?
        defer {
            if !succeeded {
                Darwin.close(descriptor)
                if let boundIdentity {
                    _ = unlinkSocketIfOwned(
                        at: socketURL,
                        expectedIdentity: boundIdentity
                    )
                }
            }
        }
        guard address.withSockAddr({
            Darwin.bind(descriptor, $0, $1)
        }) == 0 else {
            throw ClaudeStatusLineSocketError.socketUnavailable
        }
        guard let identity = ownedSocketIdentity(at: socketURL) else {
            throw ClaudeStatusLineSocketError.permissionFailure
        }
        boundIdentity = identity
        guard chmod(socketURL.path, 0o600) == 0 else {
            throw ClaudeStatusLineSocketError.permissionFailure
        }
        // Claude can emit closely spaced post-response callbacks. Keep enough
        // bounded backlog to absorb a short burst without making the helper
        // block or retry.
        guard Darwin.listen(descriptor, 32) == 0 else {
            throw ClaudeStatusLineSocketError.socketUnavailable
        }
        succeeded = true
        return ListeningSocket(descriptor: descriptor, identity: identity)
    }

    private static func ownedSocketIdentity(
        at socketURL: URL
    ) -> UnixSocketIdentity? {
        var info = stat()
        guard lstat(socketURL.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid()
        else {
            return nil
        }
        return UnixSocketIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private static func unlinkSocketIfOwned(
        at socketURL: URL,
        expectedIdentity: UnixSocketIdentity
    ) -> Bool {
        guard ownedSocketIdentity(at: socketURL) == expectedIdentity else {
            return false
        }
        return unlink(socketURL.path) == 0
    }
}

private struct ListeningSocket {
    let descriptor: Int32
    let identity: UnixSocketIdentity
}

private struct UnixSocketIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}

private func configureSocketTimeout(_ descriptor: Int32) {
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    _ = withUnsafePointer(to: &timeout) {
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            $0,
            socklen_t(MemoryLayout<timeval>.size)
        )
    }
    _ = withUnsafePointer(to: &timeout) {
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            $0,
            socklen_t(MemoryLayout<timeval>.size)
        )
    }
}

private struct UnixSocketAddress {
    private var address: sockaddr_un
    private let length: socklen_t

    init?(path: String) {
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(
            ofValue: sockaddr_un().sun_path
        ) else {
            return nil
        }
        var value = sockaddr_un()
        value.sun_family = sa_family_t(AF_UNIX)
        let maximumPathBytes = MemoryLayout.size(
            ofValue: value.sun_path
        )
        path.withCString { source in
            withUnsafeMutablePointer(to: &value.sun_path.0) { destination in
                _ = Darwin.strlcpy(
                    destination,
                    source,
                    maximumPathBytes
                )
            }
        }
        address = value
        length = socklen_t(MemoryLayout<sockaddr_un>.size)
        address.sun_len = UInt8(length)
    }

    func withSockAddr<T>(
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> T
    ) -> T {
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, length)
            }
        }
    }
}
