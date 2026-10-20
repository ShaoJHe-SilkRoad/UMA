import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#endif

/// Equality means the lightweight inputs were unchanged, not that an operation
/// is safe. A missing stamp requires invalidation and a fresh full observation.
public struct SectoriumConsistencyStamp: Equatable, Sendable {
    public let fingerprint: String
    public init(fingerprint: String) { self.fingerprint = fingerprint }
}

/// Kernel mount-table metadata only. No file names, contents, capacity or I/O
/// counters are read. Flags catch read-only remounts at an unchanged mount path.
public struct SectoriumMountMetadata: Equatable, Sendable {
    public let filesystemID: String
    public let mountPoint: String
    public let filesystemType: String
    public let flags: UInt32
    public init(filesystemID: String, mountPoint: String, filesystemType: String, flags: UInt32) {
        self.filesystemID = filesystemID; self.mountPoint = mountPoint
        self.filesystemType = filesystemType; self.flags = flags
    }
}

public protocol SectoriumMountMetadataProviding: AnyObject {
    func observeMountMetadata() -> [SectoriumMountMetadata]?
}

final class SystemSectoriumMountMetadataProvider: SectoriumMountMetadataProviding {
    func observeMountMetadata() -> [SectoriumMountMetadata]? {
        #if canImport(Darwin)
        // NOWAIT requests the kernel mount table without waiting for refreshed
        // per-filesystem statistics. Bound allocation and never retry a growing table.
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count >= 0, count < 4096 else { return nil }
        let capacity = min(4096, Int(count) + 16)
        // A type-position annotation disambiguates Darwin's struct from the
        // same-named C function imported into Swift.
        var records: [Darwin.statfs] = .init(repeating: .init(), count: capacity)
        let readCount = records.withUnsafeMutableBufferPointer {
            getfsstat($0.baseAddress, Int32(capacity * MemoryLayout<Darwin.statfs>.stride), MNT_NOWAIT)
        }
        guard readCount >= 0, Int(readCount) < capacity else { return nil }
        // The aggregate C MNT_VISFLAGMASK macro is not imported by Swift.
        // These public mount-option flags capture changes to read/write and
        // access behavior without including transient filesystem state flags.
        let relevantFlags = [MNT_RDONLY, MNT_NOEXEC, MNT_NOSUID, MNT_NODEV,
            MNT_IGNORE_OWNERSHIP, MNT_NOFOLLOW].reduce(UInt32(0)) {
                $0 | UInt32(truncatingIfNeeded: $1)
            }
        var result: [SectoriumMountMetadata] = []
        for index in 0..<Int(readCount) {
            var record = records[index]
            guard let mount = Self.text(&record.f_mntonname), mount.hasPrefix("/"),
                  let type = Self.text(&record.f_fstypename), !type.isEmpty else { return nil }
            result.append(.init(filesystemID: "\(record.f_fsid.val.0):\(record.f_fsid.val.1)",
                mountPoint: mount, filesystemType: type, flags: record.f_flags & relevantFlags))
        }
        return result
        #else
        return nil
        #endif
    }
    private static func text<T>(_ value: inout T) -> String? {
        withUnsafeBytes(of: &value) { bytes in
            guard let end = bytes.firstIndex(of: 0) else { return nil }
            return String(bytes: bytes[..<end], encoding: .utf8)
        }
    }
}

final class SectoriumConsistencyProbe {
    private let paths: HESectoriumPaths
    private let runner: SectoriumObservationCommandRunner
    private let mounts: SectoriumMountMetadataProviding
    private static let maximumBytes = 1_048_576
    private enum Invalid: Error { case metadata, managedFile }

    init(paths: HESectoriumPaths, runner: HESectoriumCommandRunning,
         mounts: SectoriumMountMetadataProviding,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.paths = paths; self.mounts = mounts
        self.runner = SectoriumObservationCommandRunner(runner, duration: 3, now: now)
    }

    func observe() -> SectoriumConsistencyStamp? {
        // This runner is independent of Service refresh/preflight scopes. Timed
        // production calls bypass ProcessCommandRunner's short-lived UI cache.
        runner.withFreshDeadline {
            do {
                let before = try ownMetadata()
                let mountedBefore = try mountMetadata()
                let disks = try plist("/usr/sbin/diskutil", ["list", "-plist"])
                let images = try plist("/usr/bin/hdiutil", ["info", "-plist"])
                guard let diskRecords = disks["AllDisksAndPartitions"] as? [[String: Any]],
                      let imageRecords = images["images"] as? [[String: Any]],
                      diskRecords.allSatisfy({ ($0["DeviceIdentifier"] as? String)?.isEmpty == false }),
                      imageRecords.allSatisfy({ ($0["image-path"] as? String)?.isEmpty == false
                          && $0["system-entities"] is [[String: Any]] }) else { return nil }
                let after = try ownMetadata()
                let mountedAfter = try mountMetadata()
                guard before == after, mountedBefore == mountedAfter else { return nil }
                let projection: [String: Any] = ["managed": before.base64EncodedString(),
                    "mounts": mountedBefore.base64EncodedString(),
                    "disks": try diskRecords.map { try Self.project($0, keys: Self.diskKeys) },
                    "images": try imageRecords.map { try Self.project($0, keys: Self.imageKeys) }]
                let data = try Self.canonical(projection)
                return SectoriumConsistencyStamp(fingerprint: SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }.joined())
            } catch { return nil }
        }
    }

    private func mountMetadata() throws -> Data {
        guard let records = mounts.observeMountMetadata(), records.count <= 4096,
              records.allSatisfy({ !$0.filesystemID.isEmpty && $0.mountPoint.hasPrefix("/")
                  && !$0.filesystemType.isEmpty }) else { throw Invalid.metadata }
        return try Self.canonical(records.map { record -> [String: Any] in
            ["filesystemID": record.filesystemID, "mountPoint": record.mountPoint,
             "filesystemType": record.filesystemType, "flags": record.flags]
        })
    }

    private func plist(_ executable: String, _ arguments: [String]) throws -> [String: Any] {
        // A missing private support directory must not prevent a read-only probe.
        let outcome = runner.run(executable, arguments, cwd: FileManager.default.temporaryDirectory)
        guard outcome.succeeded, let data = outcome.detail.data(using: .utf8),
              data.count <= Self.maximumBytes,
              let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw Invalid.metadata }
        return value
    }

    // Deliberately excludes sizes/free space, counters, agent process ids and
    // image access timestamps. Their changes do not invalidate identity/mounts.
    private static let diskKeys: Set<String> = [
        "DeviceIdentifier", "ParentWholeDisk", "PartOfWhole", "APFSContainerReference",
        "DiskUUID", "MediaUUID", "VolumeUUID", "APFSVolumeUUID", "MountPoint",
        "Content", "VolumeName", "FilesystemType", "FileSystemPersonality",
        "ReadOnly", "ReadOnlyMedia", "ReadOnlyVolume", "Writable", "WritableMedia", "WritableVolume",
        "Internal", "VirtualOrPhysical", "Partitions", "APFSVolumes", "APFSPhysicalStores",
        "PhysicalStores", "Volumes", "ContainerReference", "APFSContainerUUID"
    ]
    private static let imageKeys: Set<String> = [
        "image-path", "system-entities", "dev-entry", "mount-point",
        "volume-uuid", "volume-UUID", "content-hint", "writeable", "writable", "read-only"
    ]

    private static func project(_ value: Any, keys: Set<String>) throws -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, item) in dictionary where keys.contains(key) { result[key] = try project(item, keys: keys) }
            return result
        }
        if let array = value as? [Any] { return try array.map { try project($0, keys: keys) } }
        if let data = value as? Data { return data.base64EncodedString() }
        guard value is String || value is NSNumber || value is NSNull else { throw Invalid.metadata }
        return value
    }

    /// Canonical dictionary keys and unordered metadata collections; command
    /// serialization or enumeration order alone must not cause a deep refresh.
    private static func canonical(_ value: Any) throws -> Data {
        func normalized(_ value: Any) throws -> Any {
            if let dictionary = value as? [String: Any] {
                return try dictionary.mapValues { try normalized($0) }
            }
            if let array = value as? [Any] {
                return try array.map { try normalized($0) }.sorted {
                    let lhs = try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed])
                    let rhs = try JSONSerialization.data(withJSONObject: $1, options: [.sortedKeys, .fragmentsAllowed])
                    return lhs.lexicographicallyPrecedes(rhs)
                }
            }
            return value
        }
        return try JSONSerialization.data(withJSONObject: normalized(value), options: [.sortedKeys, .fragmentsAllowed])
    }

    private func ownMetadata() throws -> Data {
        var result: [String: Any] = [:]
        if let data = try readManagedFile("sectorium-profiles.json") {
            guard var profiles = HESectoriumService.decodeSectoriumProfiles(data) else { throw Invalid.managedFile }
            for index in profiles.indices {
                profiles[index].createdAt = nil; profiles[index].modifiedAt = nil
                profiles[index].lastVerifiedLoadedAt = nil
            }
            result["profiles"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profiles))
        } else { result["profiles"] = NSNull() }
        if let data = try readManagedFile("state.json") {
            // Decode with the same schema as the durable store, without invoking
            // JSONStateStore.load (which creates/chmods its parent directory).
            var state = try JSONDecoder().decode(StoragePersistentStateCodable.self, from: data)
            state.revision = 0
            result["state"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        } else { result["state"] = NSNull() }
        if let data = try readManagedFile("storage-identity.json") {
            guard let identity = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Invalid.managedFile
            }
            let keys = ["outerUUID", "devUUID", "outerMountPoint", "devMountPoint", "devVolumeName", "imagePath"]
            guard keys.allSatisfy({ identity[$0] is String }) else { throw Invalid.managedFile }
            result["identity"] = identity.filter { keys.contains($0.key) }
        } else { result["identity"] = NSNull() }
        return try Self.canonical(result)
    }

    /// Opens only three known private files, descriptor-relative and no-follow.
    /// No directory enumeration, creation, permission changes, or external paths.
    private func readManagedFile(_ name: String) throws -> Data? {
        #if canImport(Darwin)
        var root = paths.root.standardizedFileURL.path
        if root == "/tmp" || root.hasPrefix("/tmp/") || root == "/var" || root.hasPrefix("/var/") {
            root = "/private" + root
        }
        guard root.hasPrefix("/") else { throw Invalid.managedFile }
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw Invalid.managedFile }
        defer { close(directory) }
        for component in root.split(separator: "/") {
            let next = openat(directory, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0 {
                if errno == ENOENT { return nil }
                throw Invalid.managedFile
            }
            close(directory); directory = next
        }
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if file < 0 {
            if errno == ENOENT { return nil }
            throw Invalid.managedFile
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= Self.maximumBytes else { throw Invalid.managedFile }
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = read(file, &bytes, bytes.count)
            if count < 0 { if errno == EINTR { continue }; throw Invalid.managedFile }
            if count == 0 { return data }
            guard data.count + count <= Self.maximumBytes else { throw Invalid.managedFile }
            data.append(contentsOf: bytes.prefix(count))
        }
        #else
        throw Invalid.managedFile
        #endif
    }
}
