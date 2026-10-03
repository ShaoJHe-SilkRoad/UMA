import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Creates a directory tree one descriptor-relative component at a time.
/// Existing symbolic links, including links inserted between preflight and mkdir, are rejected.
enum SecureDirectory {
    static func ensure(_ url: URL, mode: Int = 0o700) throws {
        let requestedPath = url.standardizedFileURL.path
        guard requestedPath.hasPrefix("/") else {
            throw RuntimeError.unsafePath("managed directory path must be absolute")
        }
        // Foundation may normalize /private/tmp back to the public /tmp alias. Map
        // these two documented macOS aliases explicitly, then walk the physical path
        // with openat(O_NOFOLLOW) so links below the trusted system root are rejected.
        let path: String
        if requestedPath == "/tmp" || requestedPath.hasPrefix("/tmp/") {
            path = "/private" + requestedPath
        } else if requestedPath == "/var" || requestedPath.hasPrefix("/var/") {
            path = "/private" + requestedPath
        } else {
            let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard requestedPath == resolvedPath else {
                throw RuntimeError.unsafePath("managed directory path traverses a symbolic link")
            }
            path = requestedPath
        }
        #if canImport(Darwin)
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw RuntimeError.unsafePath("cannot open filesystem root safely") }
        defer { close(descriptor) }
        let components = path.split(separator: "/").map(String.init)
        for (index, component) in components.enumerated() {
            guard component != ".", component != "..", !component.isEmpty else {
                throw RuntimeError.unsafePath("managed path contains an invalid component")
            }
            var next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if next < 0 && errno == ENOENT {
                let createMode = index == components.count - 1 ? mode_t(mode) : mode_t(0o700)
                guard mkdirat(descriptor, component, createMode) == 0 || errno == EEXIST else {
                    throw RuntimeError.unsafePath("could not create managed directory component")
                }
                next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            }
            guard next >= 0 else { throw RuntimeError.unsafePath("managed path component is not a plain directory: \(component) (errno \(errno))") }
            if index == components.count - 1 {
                var info = stat()
                guard fstat(next, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
                      info.st_uid == geteuid(), fchmod(next, mode_t(mode)) == 0 else {
                    close(next); throw RuntimeError.unsafePath("managed directory is not privately owned")
                }
            }
            close(descriptor); descriptor = next
        }
        if components.isEmpty { throw RuntimeError.unsafePath("filesystem root cannot be a managed directory") }
        #else
        let manager = FileManager.default
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for (index, component) in path.split(separator: "/").enumerated() {
            current.appendPathComponent(String(component), isDirectory: true)
            var isDirectory: ObjCBool = false
            if !manager.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                try manager.createDirectory(at: current, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: index == path.split(separator: "/").count - 1 ? mode : 0o700])
            }
            guard current.standardizedFileURL.path == current.resolvingSymlinksInPath().path,
                  manager.fileExists(atPath: current.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw RuntimeError.unsafePath("managed path contains a symbolic link or non-directory")
            }
        }
        #endif
    }
}
