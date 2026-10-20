import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

/// Native service acceptance, deliberately separate from a physical-HE/UI test.
/// Only a newly created ExFAT parent image is classified as external/physical by
/// this fixture. All UUIDs, mounts, image/APFS relationships, commands and results
/// are native. No installed state, user image, LaunchAgent or real disk is changed.
@Suite("Native service lifecycle", .serialized)
struct SectoriumNativeServiceLifecycleTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUV_NATIVE_SERVICE_FIXTURE"] == "1"))
    func serviceLoadUnloadRecoveryAndReloadOnDisposableImage() throws {
        let fixture = try NativeServiceFixture()
        defer { fixture.cleanup() }
        try fixture.prepare()
        let profile = try #require(fixture.profile)
        let service = fixture.service()
        let beforeFirstLoad = fixture.runner.commands.count
        let firstLoad = service.startDevelopmentDisk(profileID: profile.id)
        try #require(firstLoad.succeeded, "\(firstLoad)")
        try #require(fixture.runner.commands.dropFirst(beforeFirstLoad).contains {
            $0 == ["/usr/sbin/diskutil", "mount", "-mountPoint", profile.devMountPoint, "/dev/\(fixture.childVolumeBSD)"] })
        try #require(service.profileReadiness(profileID: profile.id) == .ready)
        try #require(service.pendingSectoriumOperation() == nil)
        let checkpoint = try #require(service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        let beforeUnload = fixture.runner.commands.count
        let unload = service.unloadDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint)
        try #require(unload.succeeded, "\(unload)")
        try #require(unload.steps.contains { $0.step == "verifyDevelopmentVolumeUnloaded"
            && $0.status == .succeeded && $0.detail == profile.id })
        try #require(service.profileReadiness(profileID: profile.id) == .notStarted)
        try #require(service.verifiedLoadedState(profileID: profile.id) == false)
        try #require(service.pendingSectoriumOperation() == nil)
        try #require(fixture.runner.commands.dropFirst(beforeUnload).filter { $0.contains("unmount") }.count == 1)
        try #require(!fixture.runner.commands.dropFirst(beforeUnload).contains { $0.contains("detach") || $0.contains("eject") })
        let parent = try fixture.info(fixture.parentMount.path)
        try #require(parent["VolumeUUID"] as? String == profile.backingVolumeUUID.uuidString)
        try #require(parent["MountPoint"] as? String == fixture.parentMount.path)
        let unloaded = try fixture.info("/dev/\(fixture.childVolumeBSD)")
        try #require(unloaded["MountPoint"] as? String == "")
        try #require(unloaded["VolumeUUID"] as? String == profile.devUUID?.uuidString)
        print("NATIVE_SERVICE unload=success parent=connected image=attached nativeMountPoint=empty pending=nil")

        // Reproduce the retained successful-unmount record in an isolated durable
        // store, then reconstruct the service. This is fault injection, not a
        // claim that a real process was killed or a host operation was recovered.
        let state = try fixture.store.load()
        var retained = StoragePersistentStateCodable(state: state)
        retained.revision += 1
        retained.workbenchOperation = "unload:\(unload.operationID)"
        retained.workbenchPhase = "mutating"
        retained.workbenchTarget = profile.imagePath
        retained.workbenchCompletedStep = "unmountDEV"
        retained.workbenchTerminalResult = nil
        try #require(try fixture.store.compareAndSwap(expectedRevision: state.revision, newState: retained.state))
        let freshService = fixture.service()
        let beforeRecovery = fixture.runner.commands.count
        try #require(freshService.reconcileCompletedUnload())
        try #require(freshService.pendingSectoriumOperation() == nil)
        try #require(freshService.profileReadiness(profileID: profile.id) == .notStarted)
        try #require(try fixture.store.load().suppressedProfileIDs.contains(profile.id))
        try #require(!fixture.runner.commands.dropFirst(beforeRecovery).contains { $0.contains("mount")
            || $0.contains("unmount") || $0.contains("attach") || $0.contains("detach") || $0.contains("eject") })
        let beforeReload = fixture.runner.commands.count
        let reload = freshService.startDevelopmentDisk(profileID: profile.id)
        try #require(reload.succeeded, "\(reload)")
        try #require(reload.steps.contains { $0.step == "validateImageChain" && $0.status == .succeeded })
        try #require(freshService.profileReadiness(profileID: profile.id) == .ready)
        try #require(freshService.verifiedLoadedState(profileID: profile.id) == true)
        try #require(freshService.pendingSectoriumOperation() == nil)
        try #require(!(try fixture.store.load()).suppressedProfileIDs.contains(profile.id))
        try #require(fixture.runner.commands.dropFirst(beforeReload).contains {
            $0 == ["/usr/sbin/diskutil", "mount", "-mountPoint", profile.devMountPoint, "/dev/\(fixture.childVolumeBSD)"] })
        try #require(!fixture.runner.commands.dropFirst(beforeReload).contains { $0.contains("attach") })
        let nativeReloaded = try fixture.info(profile.devMountPoint)
        try #require(nativeReloaded["VolumeUUID"] as? String == profile.devUUID?.uuidString)
        try #require(nativeReloaded["MountPoint"] as? String == profile.devMountPoint)
        try #require(fixture.runner.deniedCommands.isEmpty, "\(fixture.runner.deniedCommands)")
        print("NATIVE_SERVICE load-unload-load=passed recovery=fresh-service pending=nil physical-classification=simulated documentation=pending")
    }
}

private final class NativeServicePendingWriter: SectoriumPortableDocumentWriting {
    func update(profile: SectoriumDevelopmentProfile, event: String) -> SectoriumPortableDocumentResult {
        .pending("Intentional fixture: external documentation unavailable")
    }
}

/// Deny every mutation except the exact child volume's mount/unmount commands.
/// Setup and cleanup are separate, explicit operations on freshly created images.
private final class NativeServiceGuardRunner: HESectoriumTimedCommandRunning {
    let native = ProcessCommandRunner()
    let root: URL
    var parentWholeBSD = ""
    var childVolumeBSD = ""
    var childMount = ""
    var imagePath = ""
    var observedFixtureDeviceNodes = Set<String>()
    var commands: [[String]] = []
    var deniedCommands: [[String]] = []
    init(root: URL) { self.root = root }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        run(executable, arguments, cwd: cwd, timeout: 30)
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        let recorded = [executable] + arguments
        commands.append(recorded)
        let infoTarget = arguments.last ?? ""
        let fixtureTarget = infoTarget.hasPrefix(root.path + "/") || observedFixtureDeviceNodes.contains(infoTarget)
        let diskInfo = executable == "/usr/sbin/diskutil" && arguments.count == 3
            && Array(arguments.prefix(2)) == ["info", "-plist"] && fixtureTarget
        let metadata = diskInfo || (executable == "/usr/sbin/diskutil" && (arguments == ["list", "-plist"] || arguments == ["apfs", "list", "-plist"]))
            || (executable == "/usr/bin/hdiutil" && arguments == ["info", "-plist"])
            || (executable == "/usr/bin/hdiutil" && arguments.last == imagePath && ["imageinfo", "isencrypted"].contains(arguments.first ?? ""))
            || (executable == "/bin/df" && arguments.count == 2 && arguments[0] == "-P"
                && [imagePath, childMount, URL(fileURLWithPath: childMount).deletingLastPathComponent().path].contains(arguments[1]))
            || (executable == "/usr/sbin/lsof" && arguments == ["-nP", "-Fpcf", "+f", "--", childMount])
        let mutation = !childVolumeBSD.isEmpty && executable == "/usr/sbin/diskutil"
            && (arguments == ["unmount", childMount] || arguments == ["mount", "-mountPoint", childMount, "/dev/\(childVolumeBSD)"])
        guard cwd.standardizedFileURL.path.hasPrefix(root.path + "/"), metadata || mutation else {
            deniedCommands.append(recorded)
            return .init(exitCode: 97, detail: "Native service fixture denied an out-of-scope command: \(recorded)")
        }
        let began = ProcessInfo.processInfo.systemUptime
        let result = native.run(executable, arguments, cwd: cwd, timeout: min(timeout, 30))
        print("NATIVE_SERVICE command=\(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.joined(separator: " ")) exit=\(result.exitCode) seconds=\(ProcessInfo.processInfo.systemUptime - began)")
        // This sole metadata substitution allows a disposable parent image to
        // enter the service's physical-drive route. Never alter native identities,
        // mount results, image inventories or APFS container/volume relationships.
        if diskInfo, result.succeeded, arguments.last == "/dev/\(parentWholeBSD)",
           var info = try? nativeFixturePlist(result) {
            info["VirtualOrPhysical"] = "Physical"
            if let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0),
               let text = String(data: data, encoding: .utf8) { return .init(exitCode: 0, detail: text) }
        }
        return result
    }
}

private final class NativeServiceFixtureObserver: SectoriumDeviceObserving {
    let fixture: NativeServiceFixture
    init(_ fixture: NativeServiceFixture) { self.fixture = fixture }
    func observeDevices() throws -> [SectoriumPhysicalDevice] {
        let info = try fixture.info(fixture.parentMount.path)
        let uuid = try #require((info["VolumeUUID"] as? String).flatMap(UUID.init(uuidString:)))
        let member = try #require(info["DeviceIdentifier"] as? String)
        let mount = try #require(info["MountPoint"] as? String)
        try #require(mount == fixture.parentMount.path)
        return [.init(id: uuid.uuidString, bsdName: fixture.runner.parentWholeBSD,
            name: "Disposable parent (simulated external classification)", isExternal: true, identityVerified: true,
            wholeDeviceBytes: (info["TotalSize"] as? NSNumber)?.uint64Value,
            mountedVolumePaths: [mount], volumeUUIDs: [uuid], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: uuid, bsdName: member, mountPoint: mount)],
            topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
            requiresFreshParentCheck: true)]
    }
}

private final class NativeServiceFixture {
    let root: URL
    let parentMount: URL
    let parentImage: URL
    let childImage: URL
    let childMount: URL
    let paths: HESectoriumPaths
    let runner: NativeServiceGuardRunner
    let store: JSONStateStore
    var childVolumeBSD = ""
    var profile: SectoriumDevelopmentProfile?
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp/auv-native-service-\(UUID().uuidString)")
        parentMount = root.appendingPathComponent("Parent")
        parentImage = root.appendingPathComponent("Parent.sparsebundle")
        childMount = parentMount.appendingPathComponent("DEV")
        childImage = parentMount.appendingPathComponent("Development.sparsebundle")
        paths = .init(root: root.appendingPathComponent("support"))
        runner = .init(root: root)
        store = .init(url: paths.state)
        for directory in [root, parentMount, paths.root] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        print("NATIVE_SERVICE fixture=\(root.path) native-failure-limit=1-per-run physical-eject=NOT_RUN")
    }
    private func command(_ executable: String, _ arguments: [String]) throws -> CommandOutcome {
        let began = ProcessInfo.processInfo.systemUptime
        let result = runner.native.run(executable, arguments, cwd: root, timeout: 30)
        print("NATIVE_SERVICE_SETUP command=\(executable) \(arguments.joined(separator: " ")) exit=\(result.exitCode) seconds=\(ProcessInfo.processInfo.systemUptime - began)")
        try #require(result.succeeded, Comment(rawValue: result.detail))
        return result
    }
    func info(_ path: String) throws -> [String: Any] {
        try nativeFixturePlist(command("/usr/sbin/diskutil", ["info", "-plist", path]))
    }
    private var modernImages: Bool { ProcessInfo.processInfo.environment["AUV_NATIVE_MODERN_IMAGES"] == "1" }
    private func create(_ image: URL, size: String, fs: String, name: String) throws {
        if modernImages {
            _ = try command("/usr/sbin/diskutil", ["image", "create", "blank", "--size", size,
                "--fs", fs, "--volumeName", name, "--format", "UDSB", image.path])
        } else {
            _ = try command("/usr/bin/hdiutil", ["create", "-size", size, "-fs", fs,
                "-volname", name, "-type", "SPARSEBUNDLE", image.path])
        }
    }
    private func attach(_ image: URL, at mount: URL) throws -> String {
        let result = modernImages
            ? try command("/usr/sbin/diskutil", ["image", "attach", "--plist", "--nobrowse", "--mountPoint", mount.path, image.path])
            : try command("/usr/bin/hdiutil", ["attach", "-plist", "-nobrowse", "-mountpoint", mount.path, image.path])
        let plist = try nativeFixturePlist(result)
        let entities = try #require(plist["system-entities"] as? [[String: Any]])
        let nodes = entities.compactMap { $0["dev-entry"] as? String }
        try #require(nodes.count == entities.count && nodes.allSatisfy {
            $0.range(of: #"^/dev/disk[0-9]+(?:s[0-9]+)?$"#, options: .regularExpression) != nil })
        runner.observedFixtureDeviceNodes.formUnion(nodes)
        let whole = try #require(entities.compactMap { $0["dev-entry"] as? String }
            .first { $0.range(of: #"^/dev/disk[0-9]+$"#, options: .regularExpression) != nil })
        return String(whole.dropFirst(5))
    }
    func prepare() throws {
        try create(parentImage, size: "768M", fs: "ExFAT", name: "AUV_PARENT_FIXTURE")
        runner.parentWholeBSD = try attach(parentImage, at: parentMount)
        let parent = try info(parentMount.path)
        let parentUUID = try #require((parent["VolumeUUID"] as? String).flatMap(UUID.init(uuidString:)))
        try create(childImage, size: "256M", fs: "APFS", name: "AUV_DEV_FIXTURE")
        try FileManager.default.createDirectory(at: childMount, withIntermediateDirectories: true)
        _ = try attach(childImage, at: childMount)
        let child = try info(childMount.path)
        let childUUID = try #require((child["VolumeUUID"] as? String).flatMap(UUID.init(uuidString:)))
        childVolumeBSD = try #require(child["DeviceIdentifier"] as? String)
        try #require(childVolumeBSD.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil)
        runner.childVolumeBSD = childVolumeBSD; runner.childMount = childMount.path; runner.imagePath = childImage.path
        profile = .init(name: "Native fixture", deviceID: parentUUID.uuidString, backingVolumeUUID: parentUUID,
            backingMountPoint: parentMount.path, imagePath: childImage.path, devVolumeName: "AUV_DEV_FIXTURE",
            devMountPoint: childMount.path, devUUID: childUUID, encrypted: false, caseSensitive: false,
            logicalCapacityBytes: (child["TotalSize"] as? NSNumber)?.uint64Value, imageFormat: "UDSB",
            validation: .validated, filesystem: .apfs, autoLoad: false)
        try JSONEncoder().encode([try #require(profile)]).write(to: paths.sectoriumProfiles, options: .atomic)
        // Start with attached but unloaded APFS so both service Load calls must
        // perform a native mount rather than just report an already loaded volume.
        _ = try command("/usr/sbin/diskutil", ["unmount", childMount.path])
    }
    func service() -> HESectoriumService {
        let observer = NativeServiceFixtureObserver(self)
        return HESectoriumService(paths: paths, store: store,
            installer: HESectoriumInstaller(paths: paths, home: root.appendingPathComponent("fake-home")),
            runner: runner, sectoriumDeviceObserver: observer,
            portableDocumentWriter: NativeServicePendingWriter())
    }
    func cleanup() {
        var allDetached = true
        for image in [childImage, parentImage] {
            // Resolve only our two exact image paths anew. This also handles an
            // attach that succeeded before receipt parsing/another assertion failed.
            let inventory = runner.native.run("/usr/bin/hdiutil", ["info", "-plist"], cwd: root, timeout: 30)
            guard inventory.succeeded, let plist = try? nativeFixturePlist(inventory),
                  let images = plist["images"] as? [[String: Any]] else {
                allDetached = false
                Issue.record("Fixture cleanup inventory unavailable; retained \(root.path)")
                break
            }
            let matches = images.filter { $0["image-path"] as? String == image.path }
            if matches.isEmpty { continue }
            guard matches.count == 1, let entities = matches.first?["system-entities"] as? [[String: Any]],
                  let device = entities.compactMap({ $0["dev-entry"] as? String })
                    .first(where: { $0.range(of: #"^/dev/disk[0-9]+$"#, options: .regularExpression) != nil }) else {
                allDetached = false
                Issue.record("Fixture cleanup image identity ambiguous; retained \(root.path)")
                break
            }
            let result = runner.native.run("/usr/bin/hdiutil", ["detach", device], cwd: root, timeout: 30)
            print("NATIVE_SERVICE_CLEANUP image=\(image.lastPathComponent) target=\(device) exit=\(result.exitCode)")
            if !result.succeeded {
                allDetached = false
                Issue.record("Fixture cleanup failed; retained \(root.path): \(result.detail)")
                break // Never detach a parent while its child remains attached.
            }
        }
        if allDetached { try? FileManager.default.removeItem(at: root) }
    }
}

private func nativeFixturePlist(_ outcome: CommandOutcome) throws -> [String: Any] {
    let start = try #require(outcome.detail.range(of: "<?xml"))
    let end = try #require(outcome.detail.range(of: "</plist>", range: start.lowerBound..<outcome.detail.endIndex))
    return try #require(PropertyListSerialization.propertyList(from: Data(outcome.detail[start.lowerBound..<end.upperBound].utf8), format: nil) as? [String: Any])
}
