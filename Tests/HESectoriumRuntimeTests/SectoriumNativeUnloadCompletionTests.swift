import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

/// Opt-in acceptance against a disposable image on the internal temporary volume.
/// No installed profiles, services, user images, or physical drives are modified.
@Suite("Native unload completion", .serialized)
struct SectoriumNativeUnloadCompletionTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUV_NATIVE_UNLOAD_FIXTURE"] == "1"))
    func realUnmountedMetadataSupportsUnloadAndReload() throws {
        let root = URL(fileURLWithPath: "/private/tmp/sectorium-native-unload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = root.appendingPathComponent("Fixture.sparsebundle")
        let mount = root.appendingPathComponent("DEV")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let runner = ProcessCommandRunner()
        func command(_ executable: String, _ arguments: [String]) throws -> CommandOutcome {
            let start = ProcessInfo.processInfo.systemUptime
            let result = runner.run(executable, arguments, cwd: root, timeout: 30)
            print("NATIVE_UNLOAD command=\(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.first ?? "") exit=\(result.exitCode) seconds=\(ProcessInfo.processInfo.systemUptime - start)")
            try #require(result.succeeded, Comment(rawValue: result.detail))
            return result
        }
        func dictionary(_ outcome: CommandOutcome) throws -> [String: Any] {
            try #require(PropertyListSerialization.propertyList(from: Data(outcome.detail.utf8), format: nil) as? [String: Any])
        }
        _ = try command("/usr/bin/hdiutil", ["create", "-size", "256m", "-fs", "APFS", "-volname", "AUV_STATUS_FIXTURE", "-type", "SPARSEBUNDLE", image.path])
        let attached = try dictionary(command("/usr/bin/hdiutil", ["attach", "-plist", "-nobrowse", "-mountpoint", mount.path, image.path]))
        let entities = try #require(attached["system-entities"] as? [[String: Any]])
        let imageDevice = try #require(entities.first?["dev-entry"] as? String)
        // Only this freshly created image is detached; never derive a physical target.
        defer {
            let result = runner.run("/usr/bin/hdiutil", ["detach", imageDevice], cwd: root, timeout: 30)
            #expect(result.succeeded, Comment(rawValue: result.detail))
            if result.succeeded { try? FileManager.default.removeItem(at: root) }
        }
        let loaded = try dictionary(command("/usr/sbin/diskutil", ["info", "-plist", mount.path]))
        let volumeUUID = try #require((loaded["VolumeUUID"] as? String).flatMap(UUID.init(uuidString:)))
        let paths = HESectoriumPaths(root: root)
        let policy = StorageIdentityPolicy(outerUUID: UUID(), devUUID: volumeUUID,
            outerMountPoint: root.path, devMountPoint: mount.path,
            devVolumeName: "AUV_STATUS_FIXTURE", imagePath: image.path)
        let backend = MacStorageBackend(paths: paths, runner: runner, policy: policy)
        #expect(backend.verifiedUnmountedImageVolumeInfo() == nil)
        for cycle in 1...2 {
            let unload = backend.perform(.unmountDEV)
            try #require(unload.succeeded, Comment(rawValue: unload.detail))
            let info = try #require(backend.verifiedUnmountedImageVolumeInfo())
            #expect(info["MountPoint"] as? String == "")
            #expect(info["VolumeUUID"] as? String == volumeUUID.uuidString)
            let device = try #require(info["DeviceIdentifier"] as? String)
            print("NATIVE_UNLOAD cycle=\(cycle) verified=true Mounted=\(String(describing: info["Mounted"])) MountPoint=\(String(describing: info["MountPoint"]))")
            // macOS may remove the empty mountpoint after a successful unmount.
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            _ = try command("/usr/sbin/diskutil", ["mount", "-mountPoint", mount.path, "/dev/\(device)"])
            let reloaded = try dictionary(command("/usr/sbin/diskutil", ["info", "-plist", mount.path]))
            #expect(reloaded["VolumeUUID"] as? String == volumeUUID.uuidString)
            #expect(reloaded["MountPoint"] as? String == mount.path)
            #expect(backend.verifiedUnmountedImageVolumeInfo() == nil)
        }
    }
}
