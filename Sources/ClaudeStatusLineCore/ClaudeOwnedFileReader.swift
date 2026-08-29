import Darwin
import Foundation

public enum ClaudeOwnedFileReadError: Error, Equatable, Sendable {
    case unsafePath
    case invalidPermissions
    case oversized
    case changedDuringRead
    case unreadable
}

/// Reads a small UMA-owned file through one `O_NOFOLLOW` descriptor.
///
/// The descriptor, the path after the read, and all security-relevant metadata
/// must still identify the same owner-only regular file. The byte limit is
/// enforced before allocation and again against bytes actually read.
public enum ClaudeOwnedFileReader {
    public static func read(
        at url: URL,
        maximumBytes: Int
    ) throws -> Data? {
        try read(
            at: url,
            maximumBytes: maximumBytes,
            afterOpen: nil,
            afterRead: nil
        )
    }

    static func read(
        at url: URL,
        maximumBytes: Int,
        afterOpen: (() throws -> Void)?,
        afterRead: (() throws -> Void)?
    ) throws -> Data? {
        guard maximumBytes >= 0 else { throw ClaudeOwnedFileReadError.oversized }
        let standardized = url.standardizedFileURL
        try validateOwnerOnlyParent(of: standardized)

        let descriptor = open(standardized.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw ClaudeOwnedFileReadError.unsafePath }
        defer { close(descriptor) }

        var before = stat()
        guard fstat(descriptor, &before) == 0 else {
            throw ClaudeOwnedFileReadError.unreadable
        }
        try validate(before)
        guard before.st_size >= 0,
              UInt64(before.st_size) <= UInt64(maximumBytes)
        else { throw ClaudeOwnedFileReadError.oversized }

        try afterOpen?()
        var data = Data()
        data.reserveCapacity(Int(before.st_size))
        var buffer = [UInt8](repeating: 0, count: min(16 * 1_024, maximumBytes + 1))
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw ClaudeOwnedFileReadError.unreadable }
            if count == 0 { break }
            guard data.count + count <= maximumBytes else {
                throw ClaudeOwnedFileReadError.oversized
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        try afterRead?()

        var after = stat()
        var path = stat()
        guard fstat(descriptor, &after) == 0,
              lstat(standardized.path, &path) == 0,
              stable(before, after),
              sameIdentity(after, path),
              Int64(data.count) == after.st_size
        else { throw ClaudeOwnedFileReadError.changedDuringRead }
        try validate(after)
        return data
    }

    private static func validate(_ info: stat) throws {
        guard (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1
        else { throw ClaudeOwnedFileReadError.unsafePath }
        guard (info.st_mode & 0o077) == 0 else {
            throw ClaudeOwnedFileReadError.invalidPermissions
        }
    }

    private static func validateOwnerOnlyParent(of url: URL) throws {
        let parent = url.deletingLastPathComponent()
        var current = parent.standardizedFileURL
        while current.path != "/" {
            var info = stat()
            guard lstat(current.path, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFDIR
            else { throw ClaudeOwnedFileReadError.unsafePath }
            if current.path == parent.path {
                guard info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else {
                    throw ClaudeOwnedFileReadError.invalidPermissions
                }
            }
            current.deleteLastPathComponent()
        }
    }

    private static func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_uid == rhs.st_uid
            && (lhs.st_mode & S_IFMT) == (rhs.st_mode & S_IFMT)
            && lhs.st_nlink == rhs.st_nlink
    }

    private static func stable(_ lhs: stat, _ rhs: stat) -> Bool {
        sameIdentity(lhs, rhs)
            && lhs.st_mode == rhs.st_mode
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}
