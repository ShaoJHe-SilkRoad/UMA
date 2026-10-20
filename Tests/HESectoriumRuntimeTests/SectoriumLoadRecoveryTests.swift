import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

/// Safe native-command fixtures: no storage command in this suite reaches the host.
struct SectoriumLoadRecoveryTests {
    private typealias Fixture = (root: URL, mount: URL, device: SectoriumPhysicalDevice,
        runner: WorkbenchFixtureRunner, store: WorkbenchMemoryStore,
        observer: WorkbenchFixtureObserver, portableWriter: WorkbenchPortableWriter,
        service: HESectoriumService)

    private func loadedFixture() throws -> Fixture {
        let fixture = try SectoriumWorkbenchRuntimeTests().makeWorkbenchFixture()
        fixture.runner.simulateLifecycle = true
        fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true
        let result = fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Load Recovery", capacityGiB: 1, filesystem: .apfs, autoLoad: false))
        try #require(result.succeeded, "\(result)")
        return fixture
    }

    private func unload(_ fixture: Fixture, _ profile: SectoriumDevelopmentProfile) throws {
        let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        let result = fixture.service.unloadDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint)
        try #require(result.succeeded, "\(result)")
        try #require(fixture.service.verifiedLoadedState(profileID: profile.id) == false)
    }

    private func markInterruptedLoad(_ fixture: Fixture, _ profile: SectoriumDevelopmentProfile,
                                     phase: String = "mutating:attachImage",
                                     completed: String? = "prepareMountPoint") {
        var state = fixture.store.value.advancingRevision()
        state.workbenchOperation = "start:interrupted-load-fixture"
        state.workbenchPhase = phase
        state.workbenchTarget = profile.imagePath
        state.workbenchCompletedStep = completed
        state.workbenchTerminalResult = nil
        state.suppressedProfileIDs.insert(profile.id)
        fixture.store.value = state
    }

    private func containsStorageMutation(_ commands: ArraySlice<[String]>) -> Bool {
        commands.contains { command in
            guard command.count > 1, !command.contains("--help") else { return false }
            if command.count > 2, command[1] == "image", command[2] == "attach" { return true }
            return ["attach", "mount", "unmount", "detach", "eject", "create", "resize"].contains(command[1])
        }
    }

    @Test("Unload to ordinary directory reloads the attached APFS volume despite native diskutil info rejection")
    func unloadedDirectoryMetadataIsResolvedByContainingFilesystem() throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        try unload(fixture, profile)
        let ordinaryDirectory = fixture.runner.run("/usr/sbin/diskutil", ["info", "-plist", profile.devMountPoint], cwd: fixture.root)
        #expect(!ordinaryDirectory.succeeded)
        #expect(ordinaryDirectory.detail.contains("Could not find disk:"))
        let startIndex = fixture.runner.commands.count
        let result = fixture.service.startDevelopmentDisk(profileID: profile.id)
        #expect(result.succeeded, "\(result)")
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        let commands = fixture.runner.commands.dropFirst(startIndex)
        #expect(commands.contains(["/bin/df", "-P", profile.devMountPoint]))
        #expect(commands.contains(["/usr/sbin/diskutil", "mount", "-mountPoint", profile.devMountPoint, "/dev/disk31s1"]))
        #expect(!commands.contains { $0.contains("attach") || $0.contains("eject") || $0.contains("detach") })
        #expect(!fixture.store.value.suppressedProfileIDs.contains(profile.id))
        #expect(fixture.store.value.workbenchOperation == nil)
    }

    @Test("Reload reaches exactly one native diskutil mount without directory-count metadata or another attach")
    func reloadDispatch() throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        try unload(fixture, profile)
        let policy = StorageIdentityPolicy(outerUUID: profile.backingVolumeUUID,
            devUUID: profile.devUUID, outerMountPoint: profile.backingMountPoint,
            devMountPoint: profile.devMountPoint, devVolumeName: profile.devVolumeName,
            imagePath: profile.imagePath)
        let backend = MacStorageBackend(paths: .init(root: fixture.root), runner: fixture.runner, policy: policy)
        let before = fixture.runner.commands.count
        let result = backend.attachImage()
        #expect(result.succeeded, "\(result)")
        let commands = fixture.runner.commands.dropFirst(before)
        #expect(commands.filter { $0 == ["/usr/sbin/diskutil", "mount", "-mountPoint", profile.devMountPoint, "/dev/disk31s1"] }.count == 1)
        #expect(!commands.contains { $0.contains("attach") || $0.contains("detach") || $0.contains("eject") })
    }

    @Test("Nonempty Load target preserves files and dispatches exactly one native action",
          arguments: ["attached", "diskutil-image", "hdiutil"])
    func nonemptyDirectoryUsesNativeMount(mode: String) throws {
        let fixture = try loadedFixture()
        fixture.runner.modernImageAttachSupported = mode == "diskutil-image"
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        try unload(fixture, profile)
        if mode != "attached" { fixture.runner.imageInventory = [] }
        let saved = URL(fileURLWithPath: profile.devMountPoint).appendingPathComponent("preserve.txt")
        try Data("unchanged".utf8).write(to: saved)
        try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: profile.devMountPoint)
        let inode = try FileManager.default.attributesOfItem(atPath: profile.devMountPoint)[.systemFileNumber] as? UInt64
        let before = fixture.runner.commands.count
        let result = fixture.service.startDevelopmentDisk(profileID: profile.id)
        #expect(result.succeeded, "\(result)")
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        #expect(fixture.store.value.workbenchOperation == nil)
        let actions = fixture.runner.commands.dropFirst(before).filter {
            !$0.contains("--help") && ($0.contains("attach") || $0.contains("mount"))
        }
        let expected = mode == "attached"
            ? ["/usr/sbin/diskutil", "mount", "-mountPoint", profile.devMountPoint, "/dev/disk31s1"]
            : mode == "diskutil-image"
                ? ["/usr/sbin/diskutil", "image", "attach", "--nobrowse", "--mountPoint", profile.devMountPoint, profile.imagePath]
                : ["/usr/bin/hdiutil", "attach", "-nobrowse", "-mountpoint", profile.devMountPoint, profile.imagePath]
        #expect(actions == [expected])
        #expect(try String(contentsOf: saved, encoding: .utf8) == "unchanged")
        #expect((try FileManager.default.attributesOfItem(atPath: profile.devMountPoint)[.systemFileNumber] as? UInt64) == inode)
        #expect((try FileManager.default.attributesOfItem(atPath: profile.devMountPoint)[.posixPermissions] as? Int) == 0o750)
        try unload(fixture, profile)
        #expect(try String(contentsOf: saved, encoding: .utf8) == "unchanged")
    }

    @Test("A missing custom mountpoint is recreated beneath verified containing storage before Load")
    func missingCustomMountpointCanReload() throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        try unload(fixture, profile)
        try FileManager.default.removeItem(atPath: profile.devMountPoint)
        let startIndex = fixture.runner.commands.count
        let result = fixture.service.startDevelopmentDisk(profileID: profile.id)
        #expect(result.succeeded, "\(result)")
        #expect(FileManager.default.fileExists(atPath: profile.devMountPoint))
        #expect(fixture.runner.commands.dropFirst(startIndex).contains(
            ["/usr/sbin/diskutil", "mount", "-mountPoint", profile.devMountPoint, "/dev/disk31s1"]))
    }

    @Test("Fresh exact loaded evidence completes interrupted Load without repeating native operations",
          arguments: ["mutating:prepareMountPoint", "mutating:attachImage", "mutating:saveValidatedProfile", "mutating"])
    func interruptedLoadedStateReconciles(phase: String) throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        markInterruptedLoad(fixture, profile, phase: phase)
        let startIndex = fixture.runner.commands.count
        #expect(fixture.service.reconcileInterruptedLoad())
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.workbenchTerminalResult == "load-completed-verified")
        #expect(!fixture.store.value.suppressedProfileIDs.contains(profile.id))
        #expect(!containsStorageMutation(fixture.runner.commands.dropFirst(startIndex)))
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
    }

    @Test("An interrupted Load proven unloaded clears its marker, keeps suppression, and accepts a deliberate retry",
          arguments: [false, true])
    func interruptedUnloadedStateCanRetry(detached: Bool) throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        try unload(fixture, profile)
        if detached { fixture.runner.imageInventory = [] }
        markInterruptedLoad(fixture, profile)
        let beforeRecovery = fixture.runner.commands.count
        #expect(fixture.service.reconcileInterruptedLoad())
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.workbenchTerminalResult == "load-not-completed-retry-available")
        #expect(fixture.store.value.suppressedProfileIDs.contains(profile.id))
        #expect(!containsStorageMutation(fixture.runner.commands.dropFirst(beforeRecovery)))
        let beforeRetry = fixture.runner.commands.count
        let retry = fixture.service.startDevelopmentDisk(profileID: profile.id)
        #expect(retry.succeeded, "\(retry)")
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        #expect(!fixture.store.value.suppressedProfileIDs.contains(profile.id))
        let actions = fixture.runner.commands.dropFirst(beforeRetry)
        #expect(actions.filter { $0.count > 1 && $0[1] == "attach" }.count == (detached ? 1 : 0))
        #expect(actions.filter { $0.count > 1 && $0[1] == "mount" }.count == (detached ? 0 : 1))
    }

    @Test("Unknown or wrong APFS image-chain evidence cannot clear an interrupted Load",
          arguments: ["wrong-volume", "unknown-inventory", "wrong-image-store"])
    func interruptedLoadRetainsUnverifiedIdentity(reason: String) throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        try unload(fixture, profile)
        markInterruptedLoad(fixture, profile)
        switch reason {
        case "wrong-volume":
            fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["VolumeUUID"] = UUID().uuidString
        case "unknown-inventory":
            fixture.runner.imageInventory = nil
        default:
            fixture.runner.apfsContainers?[0]["PhysicalStores"] = [["DeviceIdentifier": "disk99s2"]]
        }
        let stateBefore = fixture.store.value
        let commandsBefore = fixture.runner.commands.count
        #expect(!fixture.service.reconcileInterruptedLoad())
        #expect(fixture.store.value == stateBefore)
        #expect(!containsStorageMutation(fixture.runner.commands.dropFirst(commandsBefore)))
    }

    @Test("Reconciliation does not clear another operation or unsupported Load mutation boundary",
          arguments: ["mutating:createImage", "mutating:resizeImage", "validating"])
    func unsupportedMutationBoundaryRemainsPending(phase: String) throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        markInterruptedLoad(fixture, profile, phase: phase)
        let before = fixture.store.value
        #expect(!fixture.service.reconcileInterruptedLoad())
        #expect(fixture.store.value == before)
    }

    @Test("Native mount permission errors remain visible and a verified unloaded failure can be retried")
    func nativeMountFailureDetailsArePreserved() throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        try unload(fixture, profile)
        let message = "Mount failed: permission denied by native authorization (-69842)"
        fixture.runner.mountOutcome = .init(exitCode: 1, detail: message)
        let before = fixture.runner.commands.count
        let failed = fixture.service.startDevelopmentDisk(profileID: profile.id)
        #expect(!failed.succeeded)
        #expect(String(describing: failed.failure).contains(message))
        #expect(failed.steps.contains { $0.step == "attachImage" && $0.detail == message && $0.status == .failed })
        #expect(fixture.runner.commands.dropFirst(before).contains(
            ["/usr/sbin/diskutil", "mount", "-mountPoint", profile.devMountPoint, "/dev/disk31s1"]))
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == false)
        #expect(fixture.service.reconcileInterruptedLoad())
        #expect(fixture.store.value.suppressedProfileIDs.contains(profile.id))
        fixture.runner.mountOutcome = nil
        #expect(fixture.service.startDevelopmentDisk(profileID: profile.id).succeeded)
    }

    @Test("Supported native diskutil image attach is selected and cancellation never falls back to a second action",
          arguments: [false, true])
    func modernImageAttachUsesNativeCommandWithoutActionFallback(cancelled: Bool) throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        try unload(fixture, profile)
        fixture.runner.imageInventory = []
        fixture.runner.modernImageAttachSupported = true
        let cancellation = "User cancelled native authorization (-128)"
        if cancelled { fixture.runner.modernImageAttachOutcome = .init(exitCode: 1, detail: cancellation) }
        let before = fixture.runner.commands.count
        let result = fixture.service.startDevelopmentDisk(profileID: profile.id)
        #expect(result.succeeded == !cancelled, "\(result)")
        let actions = fixture.runner.commands.dropFirst(before)
        #expect(actions.contains(["/usr/sbin/diskutil", "image", "attach", "--help"]))
        #expect(actions.filter { $0 == ["/usr/sbin/diskutil", "image", "attach", "--nobrowse",
                                      "--mountPoint", profile.devMountPoint, profile.imagePath] }.count == 1)
        #expect(!actions.contains { $0.count > 1 && $0[0] == "/usr/bin/hdiutil" && $0[1] == "attach" })
        if cancelled {
            #expect(String(describing: result.failure).contains(cancellation))
            #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == false)
        } else {
            #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        }
    }

    @Test("Containing-filesystem fallback does not accept a symlink as the mountpoint")
    func symlinkMountpointRemainsRejected() throws {
        let fixture = try loadedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        try unload(fixture, profile)
        try FileManager.default.removeItem(atPath: profile.devMountPoint)
        let replacement = fixture.mount.appendingPathComponent("unrelated-empty-directory")
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(atPath: profile.devMountPoint, withDestinationPath: replacement.path)
        let before = fixture.runner.commands.count
        #expect(!fixture.service.startDevelopmentDisk(profileID: profile.id).succeeded)
        #expect(!containsStorageMutation(fixture.runner.commands.dropFirst(before)))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: profile.devMountPoint) == replacement.path)
    }
}
