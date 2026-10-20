import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Checks only a selected mount directory. Never enumerates names or reads files.
/// Load follows native mount semantics: existing directory contents are overlaid,
/// never removed or moved. Directory counts are only used by mountpoint settings.
struct SectoriumMountPointDirectory {
    enum CountObservation: Equatable {
        case count(UInt32)
        case unsupported
        case unavailable(Int32)
    }

    static func nativeCount(_ descriptor: Int32) -> CountObservation {
        #if canImport(Darwin)
        var requested = attrlist()
        requested.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        requested.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        requested.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)
        // All returned values are 32-bit, including the five attribute bitmaps.
        var response = [UInt32](repeating: 0, count: 7)
        let result = response.withUnsafeMutableBytes {
            fgetattrlist(descriptor, &requested, $0.baseAddress, $0.count, 0)
        }
        guard result == 0 else { return .unavailable(errno) }
        guard response[0] >= 24,
              response[1] & UInt32(ATTR_CMN_RETURNED_ATTRS) != 0 else { return .unavailable(EIO) }
        guard response[3] & UInt32(ATTR_DIR_ENTRYCOUNT) != 0 else { return .unsupported }
        guard response[0] >= 28 else { return .unavailable(EIO) }
        return .count(response[6])
        #else
        return .unavailable(ENOTSUP)
        #endif
    }

    static func entryCount(at path: String) -> UInt32? {
        #if canImport(Darwin)
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        if case .count(let value) = nativeCount(descriptor) { return value }
        #endif
        return nil
    }

    /// Caller must have freshly verified the backing volume and unmounted target.
    /// Returns an actionable refusal; nil authorizes only the following Load.
    /// A nonempty directory is valid: macOS hides its contents while mounted and
    /// makes them visible again after unmount. Do not enumerate or recreate it.
    func validateForMount(at path: String) -> String? {
        #if canImport(Darwin)
        let requestedTarget = URL(fileURLWithPath: path)
        guard path.hasPrefix("/"), requestedTarget.standardizedFileURL.path == path,
              path != "/", requestedTarget.resolvingSymlinksInPath().path == path else {
            return "The mount location is not a plain directory; no Load command was run"
        }
        // Expand only fixed macOS system aliases. Resolving the whole path would
        // follow a user-created link swapped in between validation and the walk.
        var physicalPath = path
        for alias in ["/var", "/tmp", "/etc"] where path.hasPrefix(alias + "/") {
            physicalPath = "/private" + path
            break
        }
        let target = URL(fileURLWithPath: physicalPath)
        // Open each ancestor without following links, retaining the exact parent.
        var parent = open("/", O_EVTONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { return failure("open the mount location", errno) }
        defer { close(parent) }
        for component in target.deletingLastPathComponent().pathComponents.dropFirst() {
            let next = openat(parent, component, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { return failure("open the mount location", errno) }
            close(parent); parent = next
        }
        let name = target.lastPathComponent
        let descriptor = openat(parent, name, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { return failure("open the mount directory", errno) }
        defer { close(descriptor) }
        var original = stat(); var parentInfo = stat()
        guard fstat(descriptor, &original) == 0, fstat(parent, &parentInfo) == 0,
              original.st_dev == parentInfo.st_dev,
              (original.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            return "The mount location is already mounted or changed; no Load command was run"
        }
        var current = stat(); var currentParent = stat()
        guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              lstat(target.deletingLastPathComponent().path, &currentParent) == 0,
              current.st_dev == original.st_dev, current.st_ino == original.st_ino,
              current.st_mode == original.st_mode,
              currentParent.st_dev == parentInfo.st_dev, currentParent.st_ino == parentInfo.st_ino else {
            return "The mount directory changed during validation; no Load command was run"
        }
        return nil
        #else
        return "Mount-directory validation is unavailable on this platform"
        #endif
    }

    private func failure(_ action: String, _ code: Int32) -> String {
        "Could not \(action): \(String(cString: strerror(code))) (\(code)). No Load command was run"
    }
}
