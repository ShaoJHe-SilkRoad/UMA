import Foundation
import CryptoKit
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

private func waitForFixtureSignal(_ semaphore: DispatchSemaphore, seconds: Double) -> Bool {
    semaphore.wait(timeout: .now() + seconds) == .success
}

final class WorkbenchMemoryStore: DurableStateStore {
    var value = StoragePersistentState(ejectIntent: false)
    private(set) var history: [StoragePersistentState] = []
    var rejectNextCompletedStep: String?
    var rejectNextMarkerClear = false
    var onSavedState: ((StoragePersistentState) -> Void)?
    func load() throws -> StoragePersistentState { value }
    func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
        if let step = rejectNextCompletedStep, newState.workbenchCompletedStep == step {
            rejectNextCompletedStep = nil; return false
        }
        if rejectNextMarkerClear, value.workbenchOperation != nil, newState.workbenchOperation == nil {
            rejectNextMarkerClear = false; return false
        }
        guard value.revision == expectedRevision else { return false }
        value = newState
        history.append(newState)
        onSavedState?(newState)
        return true
    }
}

private final class WorkbenchMemoryLock: OperationLock {
    private(set) var held = false
    func acquire() -> Bool { guard !held else { return false }; held = true; return true }
    func release() { held = false }
}

final class WorkbenchFixtureObserver: SectoriumDeviceObserving {
    var device: SectoriumPhysicalDevice
    var otherDevices: [SectoriumPhysicalDevice] = []
    var isPresent = true
    init(device: SectoriumPhysicalDevice) { self.device = device }
    func observeDevices() throws -> [SectoriumPhysicalDevice] { (isPresent ? [device] : []) + otherDevices }
}

final class WorkbenchPortableWriter: SectoriumPortableDocumentWriting {
    private(set) var events: [String] = []
    var outcome: SectoriumPortableDocumentResult = .updated
    private(set) var contexts: [SectoriumPortableDocumentContext] = []
    var beforeUpdate: (() -> Void)?
    func update(context: SectoriumPortableDocumentContext, events incoming: [SectoriumPortableDocumentEvent]) -> SectoriumPortableDocumentResult {
        beforeUpdate?()
        contexts.append(context)
        events = incoming.filter { $0.phase == .completed }.map { "\($0.profileID):\($0.kind)" }
        return outcome
    }
    func update(profile: SectoriumDevelopmentProfile, event: String) -> SectoriumPortableDocumentResult {
        events.append("\(profile.id):\(event)")
        return outcome
    }
}

private func workbenchFixtureInstaller(_ paths: HESectoriumPaths) -> HESectoriumInstaller {
    HESectoriumInstaller(paths: paths, home: paths.root.appendingPathComponent("fixture-home", isDirectory: true))
}

private final class BusyImageReturnFixtureDriver: WholeDeviceEjectDriving {
    let topology: WholeDeviceTopology
    private(set) var calls: [String] = []
    var observedPresence: WholeDevicePresence = .present
    init(_ topology: WholeDeviceTopology) { self.topology = topology }
    func observe(physicalIdentity: String) -> WholeDeviceTopology? {
        calls.append("observe")
        return physicalIdentity == topology.physicalIdentity ? topology : nil
    }
    func unmountImageVolumesNonForce(_ imageIdentity: String, volumeIdentities: [String], from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .busy("not used") }
    func detachImageNonForce(_ imageIdentity: String, from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .busy("not used") }
    func unmountAllPhysicalVolumesNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .busy("not used") }
    func ejectWholeDeviceNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .busy("not used") }
    func presence(physicalIdentity: String) -> WholeDevicePresence {
        calls.append("presence")
        return observedPresence
    }
    func presence(of target: WholeDeviceTopology) -> WholeDevicePresence {
        calls.append("presence")
        return target.physicalIdentity == topology.physicalIdentity ? observedPresence
            : .unknown("fixture target mismatch")
    }
    func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool {
        calls.append("return-check")
        guard journal.target.matchesPhysicalIdentityAndVolumes(topology), topology.volumes.allSatisfy(\.mounted),
              topology.images.count == journal.target.images.count else { return false }
        let expected = Dictionary(uniqueKeysWithValues: journal.target.images.map { ($0.identity, Set($0.volumeIdentities)) })
        return topology.images.allSatisfy { image in
            image.attached && image.mountedVolumeIdentities.map(Set.init) == expected[image.identity]
                && Set(image.volumeIdentities) == expected[image.identity]
        }
    }
}

private final class TargetBindingFixtureDriver: WholeDeviceEjectDriving {
    var observations: [String: WholeDeviceTopology]
    private(set) var storageActions = 0
    init(_ observations: [String: WholeDeviceTopology]) { self.observations = observations }
    func observe(physicalIdentity: String) -> WholeDeviceTopology? { observations[physicalIdentity] }
    func unmountImageVolumesNonForce(_ imageIdentity: String, volumeIdentities: [String],
                                     from target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        storageActions += 1; return .busy("fixture action withheld")
    }
    func detachImageNonForce(_ imageIdentity: String, from target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        storageActions += 1; return .busy("fixture action withheld")
    }
    func unmountAllPhysicalVolumesNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        storageActions += 1; return .busy("fixture action withheld")
    }
    func ejectWholeDeviceNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        storageActions += 1; return .busy("fixture action withheld")
    }
    func presence(physicalIdentity: String) -> WholeDevicePresence { .present }
    func presence(of target: WholeDeviceTopology) -> WholeDevicePresence {
        observations[target.physicalIdentity] == nil ? .unknown("fixture target unavailable") : .present
    }
    func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool { false }
}

private final class CompletingEjectFixtureDriver: WholeDeviceEjectDriving {
    var topology: WholeDeviceTopology
    var absent = false
    var actions: [String] = []
    var afterEject: (() -> Void)?
    init(_ topology: WholeDeviceTopology) { self.topology = topology }
    func observe(physicalIdentity: String) -> WholeDeviceTopology? { physicalIdentity == topology.physicalIdentity && !absent ? topology : nil }
    func unmountImageVolumesNonForce(_ imageIdentity: String, volumeIdentities: [String], from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .failed("unexpected image") }
    func detachImageNonForce(_ imageIdentity: String, from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .failed("unexpected image") }
    func unmountAllPhysicalVolumesNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        actions.append("unmount")
        topology = .init(physicalIdentity: target.physicalIdentity, bsdName: target.bsdName,
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: target.volumes.map { .init(identity: $0.identity, mounted: false) }, images: [])
        return .completed("fixture unmounted")
    }
    func ejectWholeDeviceNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        actions.append("eject"); absent = true; afterEject?(); return .completed("fixture ejected")
    }
    func presence(physicalIdentity: String) -> WholeDevicePresence { absent ? .absent : .present }
    func presence(of target: WholeDeviceTopology) -> WholeDevicePresence { presence(physicalIdentity: target.physicalIdentity) }
    func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool { false }
}

final class WorkbenchFixtureRunner: HESectoriumCommandRunning, HESectoriumSecureCommandRunning {
    let mountPoint: String
    let volumeUUID: UUID
    private(set) var commands: [[String]] = []
    private(set) var commandDirectories: [String] = []
    private(set) var secureInputs: [Data] = []
    var imageInventory: [[String: Any]]?
    var diskInventory: [[String: Any]]?
    var additionalDiskInfos: [String: [String: Any]] = [:]
    var detachedDiskInfos: [String: [String: Any]] = [:]
    var apfsContainers: [[String: Any]]?
    var imageBackingDevice = "disk81s1"
    var systemBackingDevice: String?
    var mountParentWholeDisk: String?
    var mountPartOfWholeDisk: String?
    var imageFormatOutput = CommandOutcome(exitCode: 0, detail: "UDSB\n")
    var encryptionOutput = CommandOutcome(exitCode: 127, detail: "fixture encryption observation unavailable")
    var attachOutcome = CommandOutcome(exitCode: 127, detail: "fixture command not configured")
    var mountOutcome: CommandOutcome?
    var modernImageAttachSupported = false
    var modernImageAttachOutcome: CommandOutcome?
    var attachedImageInventory: [[String: Any]]?
    var ejectAfterUnmountEnabled = false
    var failNextImageEject = false
    var occupancyIsClear = false
    var simulateLifecycle = false
    var ignoreNativeModification = false
    var offTargetRuntime = false
    var beforeCreate: (() -> Void)?
    var afterNativeModification: (() -> Void)?
    var afterNativeUnmount: (() -> Void)?
    var unavailableInfoPaths: Set<String> = []
    private struct SimulatedImage { var name: String; var bytes: UInt64; let fs: String; let uuid: UUID }
    private var simulatedImages: [String: SimulatedImage] = [:]
    init(mountPoint: String, volumeUUID: UUID) { self.mountPoint = mountPoint; self.volumeUUID = volumeUUID }

    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        commands.append([executable] + arguments)
        commandDirectories.append(cwd.path)
        if executable == "/usr/sbin/diskutil", arguments.count == 3,
           arguments.prefix(2) == ["info", "-plist"], unavailableInfoPaths.contains(arguments[2]) {
            return .init(exitCode: 127, detail: "fixture postcheck observation unavailable")
        }
        if executable == "/usr/bin/hdiutil", arguments.first == "create" { beforeCreate?() }
        if executable == "/usr/sbin/diskutil", arguments == ["image", "attach", "--help"], modernImageAttachSupported {
            return .init(exitCode: 0, detail: "diskutil image attach --nobrowse --mountPoint path image")
        }
        if simulateLifecycle, let outcome = simulate(executable, arguments) { return outcome }
        if executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", mountPoint] {
            var info: [String: Any] = [
                "VolumeUUID": volumeUUID.uuidString, "MountPoint": mountPoint,
                "FilesystemType": "ExFAT", "WritableVolume": true, "VolumeName": "Fixture HE"
            ]
            if let mountParentWholeDisk {
                info["ParentWholeDisk"] = mountParentWholeDisk
                if let mountPartOfWholeDisk { info["PartOfWhole"] = mountPartOfWholeDisk }
                info["DeviceIdentifier"] = mountParentWholeDisk + "s1"
            }
            if let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0) {
                return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
            }
        }
        if executable == "/usr/sbin/diskutil", arguments.count == 3,
           arguments[0] == "info", arguments[1] == "-plist",
           let info = detachedDiskInfos[arguments[2]], imageInventory?.isEmpty != false,
           let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        if executable == "/usr/sbin/diskutil", arguments.count == 3,
           arguments[0] == "info", arguments[1] == "-plist",
           let info = additionalDiskInfos[arguments[2]],
           let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        if executable == "/usr/sbin/diskutil", arguments == ["list", "-plist"], let diskInventory,
           let data = try? PropertyListSerialization.data(fromPropertyList: [
               "AllDisksAndPartitions": diskInventory,
               "AllDisks": diskInventory.compactMap { $0["DeviceIdentifier"] as? String }
           ] as [String: Any], format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        if executable == "/usr/sbin/diskutil", arguments == ["apfs", "list", "-plist"],
           let apfsContainers,
           let data = try? PropertyListSerialization.data(fromPropertyList: ["Containers": apfsContainers], format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        if executable == "/bin/df", arguments.count == 2, arguments[0] == "-P" {
            let backing = offTargetRuntime && !arguments[1].hasPrefix(mountPoint) ? "disk0s1"
                : (arguments[1] == "/" ? (systemBackingDevice ?? imageBackingDevice) : imageBackingDevice)
            return .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on\n/dev/\(backing) 1000 100 900 10% 1 2 1% \(mountPoint)\n")
        }
        if executable == "/usr/bin/hdiutil", arguments == ["info", "-plist"], let imageInventory,
           let data = try? PropertyListSerialization.data(fromPropertyList: ["images": imageInventory], format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        if executable == "/usr/bin/hdiutil", arguments.first == "imageinfo", arguments.last == "-format" {
            return imageFormatOutput
        }
        if executable == "/usr/bin/hdiutil", arguments.first == "isencrypted" { return encryptionOutput }
        if executable == "/usr/bin/hdiutil", arguments.first == "attach" {
            if attachOutcome.succeeded, let attachedImageInventory { imageInventory = attachedImageInventory }
            return attachOutcome
        }
        if executable == "/usr/sbin/lsof", occupancyIsClear { return .init(exitCode: 1, detail: "") }
        if executable == "/bin/sync", arguments.isEmpty { return .success }
        if executable == "/usr/sbin/diskutil", arguments.first == "unmount", occupancyIsClear { return .success }
        if executable == "/usr/sbin/diskutil", arguments.first == "eject", occupancyIsClear {
            if failNextImageEject { failNextImageEject = false; return .init(exitCode: 1, detail: "fixture interrupted before image detach") }
            if ejectAfterUnmountEnabled { imageInventory = [] }
            return .success
        }
        if executable == "/usr/bin/hdiutil", arguments.first == "create", let path = arguments.last {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
                return .success
            } catch { return .init(exitCode: 1, detail: String(describing: error)) }
        }
        return .init(exitCode: 127, detail: "fixture command not configured")
    }
    private func simulate(_ executable: String, _ arguments: [String]) -> CommandOutcome? {
        func plist(_ value: [String: Any]) -> CommandOutcome {
            let data = try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        let parent: [String: Any] = ["VolumeUUID": volumeUUID.uuidString, "MountPoint": mountPoint,
            "FilesystemType": "ExFAT", "WritableVolume": true, "VolumeName": "Fixture HE",
            "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81", "TotalSize": UInt64(500) * 1_073_741_824]
        if executable == "/usr/sbin/diskutil", arguments.count == 3, arguments.prefix(2) == ["info", "-plist"] {
            let target = arguments[2]
            if target == "/dev/disk81s1" { return plist(parent) }
            if target == "/dev/disk81" { return plist(["DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical", "WholeDisk": true]) }
            // Native diskutil info accepts a mounted volume or device, not an
            // ordinary directory on a parent volume. Resolve containing storage
            // through df/native mount metadata instead of inventing this result.
            if target.hasPrefix(mountPoint + "/"), additionalDiskInfos[target] == nil {
                return .init(exitCode: 1, detail: "Could not find disk: \(target)")
            }
        }
        if executable == "/usr/sbin/diskutil", arguments.prefix(2) == ["image", "attach"],
           modernImageAttachSupported, let i = arguments.firstIndex(of: "--mountPoint"),
           arguments.indices.contains(i + 1), let path = arguments.last {
            if let modernImageAttachOutcome, !modernImageAttachOutcome.succeeded { return modernImageAttachOutcome }
            return simulate("/usr/bin/hdiutil", ["attach", "-mountpoint", arguments[i + 1], path])
        }
        if executable == "/usr/bin/hdiutil", arguments.first == "create", let path = arguments.last {
            func after(_ flag: String) -> String { arguments[arguments.firstIndex(of: flag)! + 1] }
            let gib = UInt64(after("-size").dropLast())!
            simulatedImages[path] = .init(name: after("-volname"), bytes: gib * 1_073_741_824,
                                          fs: after("-fs"), uuid: UUID())
            return nil // ordinary fixture creates only a disposable empty directory
        }
        if executable == "/usr/bin/hdiutil", arguments.first == "attach", let path = arguments.last,
           let image = simulatedImages[path], let i = arguments.firstIndex(of: "-mountpoint") {
            let mount = arguments[i + 1]
            let info: [String: Any] = ["VolumeUUID": image.uuid.uuidString, "MountPoint": mount, "Mounted": true,
                "FilesystemType": "APFS", "FileSystemPersonality": image.fs == "APFSX" ? "Case-sensitive APFS" : "APFS",
                "WritableVolume": true, "VolumeName": image.name, "DeviceIdentifier": "disk31s1",
                "APFSContainerReference": "disk31", "TotalSize": image.bytes]
            additionalDiskInfos[mount] = info; additionalDiskInfos["/dev/disk31s1"] = info
            imageInventory = [["image-path": path, "system-entities": [
                ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk30"],
                ["content-hint": "Apple_APFS", "dev-entry": "/dev/disk30s2"],
                ["mount-point": mount, "volume-uuid": image.uuid.uuidString, "dev-entry": "/dev/disk31s1"]]]]
            apfsContainers = [["ContainerReference": "disk31", "PhysicalStores": [["DeviceIdentifier": "disk30s2"]],
                               "Volumes": [["APFSVolumeUUID": image.uuid.uuidString, "DeviceIdentifier": "disk31s1"]]]]
            return .success
        }
        if executable == "/usr/sbin/diskutil", arguments.first == "mount", arguments.count == 4,
           arguments[1] == "-mountPoint", let info = additionalDiskInfos[arguments[3]],
           (info["Mounted"] as? Bool == false || info["MountPoint"] as? String == ""),
           let uuid = info["VolumeUUID"] as? String {
            if let mountOutcome, !mountOutcome.succeeded { return mountOutcome }
            var mounted = info; mounted["MountPoint"] = arguments[2]; mounted["Mounted"] = true
            additionalDiskInfos[arguments[3]] = mounted; additionalDiskInfos[arguments[2]] = mounted
            imageInventory = imageInventory?.map { image in
                var image = image
                if let entities = image["system-entities"] as? [[String: Any]] {
                    image["system-entities"] = entities.map { entity in
                        var entity = entity
                        if entity["volume-uuid"] as? String == uuid { entity["mount-point"] = arguments[2] }
                        return entity
                    }
                }
                return image
            }
            return .success
        }
        if executable == "/usr/sbin/diskutil", arguments.first == "unmount", arguments.count == 2,
           occupancyIsClear, let info = additionalDiskInfos[arguments[1]],
           let uuid = info["VolumeUUID"] as? String {
            additionalDiskInfos.removeValue(forKey: arguments[1])
            for key in Array(additionalDiskInfos.keys) where additionalDiskInfos[key]?["VolumeUUID"] as? String == uuid {
                additionalDiskInfos[key]?.removeValue(forKey: "MountPoint")
                additionalDiskInfos[key]?["Mounted"] = false
            }
            imageInventory = imageInventory?.map { image in
                var image = image
                if let entities = image["system-entities"] as? [[String: Any]] {
                    image["system-entities"] = entities.map { entity in
                        var entity = entity
                        if entity["volume-uuid"] as? String == uuid { entity.removeValue(forKey: "mount-point") }
                        return entity
                    }
                }
                return image
            }
            afterNativeUnmount?()
            return .success
        }
        if executable == "/usr/bin/hdiutil", arguments.first == "resize", let path = arguments.last,
           var image = simulatedImages[path], let i = arguments.firstIndex(of: "-size"),
           let gib = UInt64(arguments[i + 1].dropLast()) {
            if !ignoreNativeModification { image.bytes = gib * 1_073_741_824; simulatedImages[path] = image }
            afterNativeModification?(); return .success
        }
        if executable == "/usr/sbin/diskutil", arguments.first == "renameVolume", arguments.count == 3,
           let path = imageInventory?.first?["image-path"] as? String, var image = simulatedImages[path] {
            if !ignoreNativeModification { image.name = arguments[2]; simulatedImages[path] = image }
            for key in Array(additionalDiskInfos.keys) where additionalDiskInfos[key]?["VolumeUUID"] as? String == image.uuid.uuidString {
                additionalDiskInfos[key]?["VolumeName"] = image.name
            }
            afterNativeModification?()
            return .success
        }
        return nil
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, standardInput: Data) -> CommandOutcome {
        secureInputs.append(standardInput)
        return run(executable, arguments, cwd: cwd)
    }
}

@Suite("Sectorium workbench inventory fixtures")
struct SectoriumWorkbenchRuntimeTests {
    @Test("Explicit whole-eject target stays bound across another store's selection and rejects observation drift")
    func explicitWholeEjectTargetIsIndependentOfSharedSelection() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let aID = fixture.device.id
        let aVolume = try #require(fixture.device.volumeUUIDs.first)
        let bID = UUID().uuidString, bVolume = UUID()
        let bDevice = SectoriumPhysicalDevice(id: bID, bsdName: "disk82", name: "Other fixture drive",
            isExternal: true, identityVerified: true, wholeDeviceBytes: 64_000_000_000,
            mountedVolumePaths: [], volumeUUIDs: [bVolume], readBytes: nil, writtenBytes: nil)
        fixture.observer.otherDevices = [bDevice]
        let aTopology = WholeDeviceTopology(physicalIdentity: aID, bsdName: "disk81",
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(aVolume.uuidString.lowercased())|disk81s1", mounted: true)], images: [])
        let bTopology = WholeDeviceTopology(physicalIdentity: bID, bsdName: "disk82",
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(bVolume.uuidString.lowercased())|disk82s1", mounted: true)], images: [])
        let driver = TargetBindingFixtureDriver([aID: aTopology, bID: bTopology])
        let service = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy,
            sectoriumDeviceObserver: fixture.observer, wholeDeviceEjectDriverOverride: driver,
            portableDocumentWriter: fixture.portableWriter)
        service.selectSectoriumDevice(bID)

        let promptA = try #require(service.prepareWholeDeviceEjectConfirmation(physicalIdentity: aID))
        #expect(promptA.physicalIdentity == aID)
        #expect(service.prepareWholeDeviceEjectConfirmation(physicalIdentity: bID)?.physicalIdentity == bID)
        let checkpointA = promptA.checkpoint(knownWritersClosed: true)
        #expect(!service.ejectSelectedExternalDevice(physicalIdentity: bID, checkpoint: checkpointA).succeeded)
        driver.observations[aID] = bTopology
        #expect(service.prepareWholeDeviceEjectConfirmation(physicalIdentity: aID) == nil)
        #expect(!service.ejectSelectedExternalDevice(physicalIdentity: aID, checkpoint: checkpointA).succeeded)
        #expect(driver.storageActions == 0)
        #expect(fixture.store.value.ejectIntent == false)
    }

    @Test("Malformed registered-profile bytes fail closed without creating an image")
    func malformedProfileRegistryPreservesBytes() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.createDirectory(at: fixture.service.paths.root, withIntermediateDirectories: true)
        let original = Data("{invalid registered profile".utf8)
        try original.write(to: fixture.service.paths.sectoriumProfiles, options: .atomic)

        let created = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil)

        #expect(!created.succeeded)
        #expect(try Data(contentsOf: fixture.service.paths.sectoriumProfiles) == original)
        #expect(!fixture.runner.commands.contains { $0.first == "/usr/bin/hdiutil" && $0.dropFirst().first == "create" })
        #expect(!fixture.service.setAutomationEnabled(true).succeeded)
        #expect(!fixture.service.runAutomationAgentAtStartup().succeeded)
        #expect(fixture.service.sectoriumReadiness(deviceID: fixture.device.id,
            devices: [fixture.device], profiles: []) ==
            .unknown("Registered profile configuration is unavailable or invalid"))
    }

    @Test("Portable documentation can remain pending and retry without changing the disk operation")
    func portableDocumentPendingIsIndependent() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.portableWriter.outcome = .pending("fixture write withheld")

        let created = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil)

        #expect(created.succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        #expect(fixture.portableWriter.events == ["\(profile.id):registered"])
        #expect(fixture.service.refreshStatus().diagnostics.contains { $0.category == "portableDocumentPending" })

        fixture.portableWriter.outcome = .updated
        #expect(fixture.service.retryPortableDocumentation(profileID: profile.id) == .updated)
        #expect(fixture.portableWriter.events == ["\(profile.id):registered"], "Retry retains the original event instead of inventing validation history")
        #expect(!fixture.service.refreshStatus().diagnostics.contains { $0.category == "portableDocumentPending" })
    }

    @Test("Fresh service explicitly returns a busy mounted managed image without replaying eject")
    func freshProcessReturnsBusyManagedImage() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let devUUID = UUID()
        let mountedProfile = SectoriumDevelopmentProfile(id: profile.id, name: profile.name,
            deviceID: profile.deviceID, backingVolumeUUID: profile.backingVolumeUUID,
            backingMountPoint: profile.backingMountPoint, imagePath: profile.imagePath,
            devVolumeName: profile.devVolumeName, devMountPoint: profile.devMountPoint,
            devUUID: devUUID, encrypted: profile.encrypted, caseSensitive: profile.caseSensitive,
            logicalCapacityBytes: profile.logicalCapacityBytes, imageFormat: "UDSB", validation: .validated)
        try JSONEncoder().encode([mountedProfile]).write(to: fixture.service.paths.sectoriumProfiles, options: .atomic)
        let imageVolume = "\(devUUID.uuidString.lowercased())|disk31s1"
        let topology = WholeDeviceTopology(physicalIdentity: fixture.device.id, bsdName: fixture.device.bsdName,
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(profile.backingVolumeUUID.uuidString.lowercased())|disk81s1", mounted: true)],
            images: [.init(identity: "image:disk30", attached: true,
                volumeIdentities: [imageVolume], mountedVolumeIdentities: [imageVolume])])
        let journal = WholeDeviceEjectJournalRecord(operationID: "busy-managed-image", target: topology,
            phase: .interrupted, completedSteps: ["unmountImageVolumes:image:disk30"],
            lastReceipt: .busy("fixture reports a busy image; no detach issued"),
            lastIssuedAction: .imageVolumesUnmount)
        let support = fixture.service.paths
        let stateStore = JSONStateStore(url: support.state)
        let initial = try stateStore.load()
        let encoded = try JSONEncoder().encode(journal).base64EncodedString()
        #expect(try stateStore.compareAndSwap(expectedRevision: initial.revision,
            newState: StoragePersistentState(revision: initial.revision + 1, ejectIntent: true,
                operationID: journal.operationID, workbenchOperation: "eject:\(journal.operationID)",
                workbenchPhase: "eject:interrupted", workbenchTarget: encoded,
                workbenchCompletedStep: journal.completedSteps.last)))
        let driver = BusyImageReturnFixtureDriver(topology)
        let freshProcessService = HESectoriumService(paths: support, store: JSONStateStore(url: support.state),
            operationLock: WorkbenchMemoryLock(), installer: workbenchFixtureInstaller(support),
            runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy,
            wholeDeviceEjectDriverOverride: driver,
            portableDocumentWriter: WorkbenchPortableWriter())

        let genericRecovery = freshProcessService.resumePendingSectoriumOperation()
        #expect(!genericRecovery.succeeded)
        #expect(try JSONStateStore(url: support.state).load().ejectIntent)
        #expect(!fixture.runner.commands.contains { $0.contains("attach") || $0.contains("eject") })
        freshProcessService.selectSectoriumDevice(fixture.device.id)
        let returned = freshProcessService.returnToDevelopment()
        #expect(returned.succeeded, "\(String(describing: returned.failure))")
        #expect(try !JSONStateStore(url: support.state).load().ejectIntent)
        #expect(driver.calls == ["return-check"])
        #expect(!fixture.runner.commands.contains { $0.contains("attach") || $0.contains("eject") })
    }

    @Test("Refresh maps a previously returned eject to its registered profile and releases stale reconnect suppression")
    func returnedEjectRefreshMapsStaleSuppressionToRegisteredProfile() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let topology = WholeDeviceTopology(physicalIdentity: fixture.device.id, bsdName: fixture.device.bsdName,
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(profile.backingVolumeUUID.uuidString.lowercased())|disk81s1", mounted: true)], images: [])
        let journal = WholeDeviceEjectJournalRecord(operationID: "prior-verified-return", target: topology,
            phase: .verifiedAbsent, completedSteps: ["unmountAllPhysicalVolumes", "ejectWholeDevice"],
            lastReceipt: .completed("Disk /dev/disk81 ejected\n"), lastIssuedAction: .ejectWholeDevice)
        let unrelated = UUID().uuidString
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1, ejectIntent: false,
            operationID: journal.operationID, suppressedProfileIDs: [profile.id, unrelated],
            disconnectedProfileIDs: [profile.id, unrelated], reconnectAttemptedProfileIDs: [profile.id],
            workbenchPhase: "eject:return-validated", workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString(),
            workbenchTerminalResult: "returned-to-development")
        let driver = BusyImageReturnFixtureDriver(topology)
        let service = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy,
            sectoriumDeviceObserver: fixture.observer, wholeDeviceEjectDriverOverride: driver,
            portableDocumentWriter: fixture.portableWriter)
        let commandsBefore = fixture.runner.commands.count
        #expect(service.reconcileWholeDeviceEjectRecovery())
        #expect(fixture.store.value.suppressedProfileIDs == [unrelated])
        #expect(fixture.store.value.disconnectedProfileIDs == [unrelated])
        #expect(fixture.store.value.reconnectAttemptedProfileIDs.isEmpty)
        #expect(fixture.store.value.workbenchOperation == nil && !fixture.store.value.ejectIntent)
        #expect(!service.reconcileWholeDeviceEjectRecovery())
        #expect(fixture.runner.commands.count == commandsBefore)
    }

    @Test("An unissued whole eject exposes explicit Return and clears only its durable intent")
    func unissuedWholeEjectCanReturnWithoutStorageAction() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let volume = try #require(fixture.device.volumeUUIDs.first)
        let topology = WholeDeviceTopology(physicalIdentity: fixture.device.id, bsdName: fixture.device.bsdName,
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(volume.uuidString.lowercased())|disk81s1", mounted: true)], images: [])
        let journal = WholeDeviceEjectJournalRecord(operationID: UUID().uuidString, target: topology,
            phase: .interrupted)
        fixture.store.value = StoragePersistentState(revision: 1, ejectIntent: true,
            operationID: journal.operationID, workbenchOperation: "eject:\(journal.operationID)",
            workbenchPhase: "eject:interrupted", workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
        let driver = BusyImageReturnFixtureDriver(topology)
        let service = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy,
            sectoriumDeviceObserver: fixture.observer, wholeDeviceEjectDriverOverride: driver,
            portableDocumentWriter: fixture.portableWriter)
        let beforeCommands = fixture.runner.commands.count

        #expect(service.canReturnFromWholeDeviceEject(physicalIdentity: fixture.device.id))
        #expect(service.prepareContinueWholeDeviceEjectConfirmation(physicalIdentity: fixture.device.id) == nil)
        let returned = service.returnToDevelopment(physicalIdentity: fixture.device.id)
        #expect(returned.succeeded)
        #expect(!fixture.store.value.ejectIntent && fixture.store.value.workbenchOperation == nil)
        #expect(driver.calls == ["return-check", "return-check"])
        #expect(fixture.runner.commands.count == beforeCommands)
    }

    @Test("No-action Return revalidates an old backing UUID after a new physical member changes catalog identity")
    func unissuedReturnAcceptsOnlyFreshDirectParentAnchor() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil).succeeded)
        let created = try #require(fixture.service.sectoriumProfiles().first)
        let anchor = created.backingVolumeUUID
        let newVolume = UUID()
        let newMount = fixture.root.appendingPathComponent("new-physical-member", isDirectory: true)
        try FileManager.default.createDirectory(at: newMount, withIntermediateDirectories: true)
        let profile = SectoriumDevelopmentProfile(id: created.id, name: created.name,
            deviceID: anchor.uuidString, backingVolumeUUID: anchor,
            backingMountPoint: created.backingMountPoint, imagePath: created.imagePath,
            devVolumeName: created.devVolumeName, devMountPoint: created.devMountPoint,
            devUUID: created.devUUID, encrypted: created.encrypted,
            caseSensitive: created.caseSensitive, logicalCapacityBytes: created.logicalCapacityBytes,
            imageFormat: created.imageFormat, validation: created.validation)
        let paths = fixture.service.paths
        try JSONEncoder().encode([profile]).write(to: paths.sectoriumProfiles, options: .atomic)
        let degraded = SectoriumPhysicalDevice(id: "unverified-disk81", bsdName: "disk81",
            name: "Fixture Drive with a new member", isExternal: true, identityVerified: false,
            wholeDeviceBytes: fixture.device.wholeDeviceBytes,
            mountedVolumePaths: [fixture.mount.path, newMount.path],
            volumeUUIDs: [anchor, newVolume], readBytes: nil, writtenBytes: nil,
            volumeMembers: [
                .init(volumeUUID: anchor, bsdName: "disk81s1", mountPoint: fixture.mount.path),
                .init(volumeUUID: newVolume, bsdName: "disk81s2", mountPoint: newMount.path)
            ], topologyComplete: true, isVirtual: false, identityBasis: .unavailable,
            wholeMediaUUID: nil, requiresFreshParentCheck: true)
        fixture.observer.device = degraded
        fixture.runner.mountParentWholeDisk = "disk81"
        fixture.runner.systemBackingDevice = "disk0s1"
        fixture.runner.imageInventory = []
        fixture.runner.additionalDiskInfos = [
            "/dev/disk0s1": ["DeviceIdentifier": "disk0s1", "ParentWholeDisk": "disk0"],
            "/dev/disk0": ["DeviceIdentifier": "disk0", "VirtualOrPhysical": "Physical"],
            "/dev/disk81": ["DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical"],
            "/dev/disk81s1": ["DeviceIdentifier": "disk81s1", "ParentWholeDisk": "disk81",
                                "VolumeUUID": anchor.uuidString],
            "/dev/disk81s2": ["DeviceIdentifier": "disk81s2", "ParentWholeDisk": "disk81",
                                "VolumeUUID": newVolume.uuidString]
        ]
        fixture.runner.diskInventory = [["DeviceIdentifier": "disk81", "Partitions": [
            ["DeviceIdentifier": "disk81s1"], ["DeviceIdentifier": "disk81s2"]
        ]]]
        let original = WholeDeviceTopology(physicalIdentity: anchor.uuidString, bsdName: "disk81",
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(anchor.uuidString.lowercased())|disk81s1", mounted: true)], images: [])
        let journal = WholeDeviceEjectJournalRecord(operationID: "no-action-anchor-return",
            target: original, phase: .interrupted)
        let encodedJournal = try JSONEncoder().encode(journal).base64EncodedString()
        let durableStore = JSONStateStore(url: paths.state)
        let initial = try durableStore.load()
        #expect(try durableStore.compareAndSwap(expectedRevision: initial.revision,
            newState: StoragePersistentState(revision: initial.revision + 1, ejectIntent: true,
                operationID: journal.operationID, workbenchOperation: "eject:\(journal.operationID)",
                workbenchPhase: "eject:interrupted", workbenchTarget: encodedJournal)))
        let service = HESectoriumService(paths: paths, backend: WorkbenchNoopBackend(),
            store: JSONStateStore(url: paths.state), operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy,
            sectoriumDeviceObserver: fixture.observer, portableDocumentWriter: fixture.portableWriter)
        let commandsBeforeReturn = fixture.runner.commands.count

        let wrongAnchor = SectoriumPhysicalDevice(id: degraded.id, bsdName: degraded.bsdName,
            name: degraded.name, isExternal: true, identityVerified: false,
            wholeDeviceBytes: degraded.wholeDeviceBytes, mountedVolumePaths: [newMount.path],
            volumeUUIDs: [newVolume], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: newVolume, bsdName: "disk81s2", mountPoint: newMount.path)],
            topologyComplete: true, isVirtual: false, identityBasis: .unavailable,
            requiresFreshParentCheck: true)
        fixture.observer.device = wrongAnchor
        #expect(!service.canReturnFromWholeDeviceEject(physicalIdentity: anchor.uuidString))
        #expect(!service.returnToDevelopment(physicalIdentity: anchor.uuidString).succeeded)
        #expect(try durableStore.load().ejectIntent)

        fixture.observer.device = degraded
        fixture.runner.additionalDiskInfos["/dev/disk81s2"]?["ParentWholeDisk"] = "disk99"
        #expect(!service.canReturnFromWholeDeviceEject(physicalIdentity: anchor.uuidString))
        #expect(try durableStore.load().ejectIntent)
        fixture.runner.additionalDiskInfos["/dev/disk81s2"]?["ParentWholeDisk"] = "disk81"

        #expect(service.canReturnFromWholeDeviceEject(physicalIdentity: anchor.uuidString))
        #expect(service.prepareContinueWholeDeviceEjectConfirmation(physicalIdentity: anchor.uuidString) == nil)
        let returned = service.returnToDevelopment(physicalIdentity: anchor.uuidString)
        #expect(returned.succeeded, "\(String(describing: returned.failure))")
        #expect(try !durableStore.load().ejectIntent)
        #expect(try durableStore.load().workbenchOperation == nil)
        #expect(Array(fixture.runner.commands.dropFirst(commandsBeforeReturn)).allSatisfy { command in
            !command.contains("attach") && !command.contains("detach")
                && !command.contains("unmount") && !command.contains("eject")
        })
    }

    @Test("Successful eject callback with unknown presence offers a read-only Continue recheck")
    func postCallbackWholeEjectRequiresFreshAbsentObservation() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let volume = try #require(fixture.device.volumeUUIDs.first)
        let topology = WholeDeviceTopology(physicalIdentity: fixture.device.id, bsdName: fixture.device.bsdName,
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(volume.uuidString.lowercased())|disk81s1", mounted: false)], images: [])
        let journal = WholeDeviceEjectJournalRecord(operationID: UUID().uuidString, target: topology,
            phase: .interrupted, completedSteps: ["unmountAllPhysicalVolumes", "ejectWholeDevice"],
            lastReceipt: .completed("fixture callback succeeded"), lastIssuedAction: .ejectWholeDevice)
        fixture.store.value = StoragePersistentState(revision: 1, ejectIntent: true,
            operationID: journal.operationID, workbenchOperation: "eject:\(journal.operationID)",
            workbenchPhase: "eject:interrupted", workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
        let driver = BusyImageReturnFixtureDriver(topology)
        driver.observedPresence = .unknown("fixture observation unavailable")
        let service = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy,
            sectoriumDeviceObserver: fixture.observer, wholeDeviceEjectDriverOverride: driver,
            portableDocumentWriter: fixture.portableWriter)
        let prompt = try #require(service.prepareContinueWholeDeviceEjectConfirmation(
            physicalIdentity: fixture.device.id))
        #expect(prompt.isContinuation && prompt.isObservationOnly)
        #expect(service.prepareContinueWholeDeviceEjectConfirmation(physicalIdentity: UUID().uuidString) == nil)
        let beforeCommands = fixture.runner.commands.count
        let uncertain = service.continueWholeDeviceEject(physicalIdentity: fixture.device.id,
            checkpoint: prompt.checkpoint(knownWritersClosed: false))
        #expect(!uncertain.succeeded)
        #expect(!uncertain.steps.contains { $0.step == "verifyWholeDeviceEjected" && $0.status == .succeeded })
        #expect(fixture.store.value.ejectIntent)
        #expect(fixture.store.value.workbenchOperation == "eject:\(journal.operationID)")
        driver.observedPresence = .absent
        let refreshed = try #require(service.prepareContinueWholeDeviceEjectConfirmation(
            physicalIdentity: fixture.device.id))
        let complete = service.continueWholeDeviceEject(physicalIdentity: fixture.device.id,
            checkpoint: refreshed.checkpoint(knownWritersClosed: false))
        #expect(complete.steps.contains { $0.step == "verifyWholeDeviceEjected" && $0.status == .succeeded })
        #expect(complete.succeeded, "\(String(describing: complete.failure))")
        #expect(!fixture.store.value.ejectIntent && fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.terminalEjectJournals[fixture.device.id] != nil)
        #expect(driver.calls == ["presence", "presence"])
        let recoveryCommands = fixture.runner.commands.dropFirst(beforeCommands)
        #expect(!recoveryCommands.contains { command in
            let action = command.dropFirst().first ?? ""
            return (command.first == "/usr/sbin/diskutil" && ["unmount", "eject", "mount"].contains(action))
                || (command.first == "/usr/bin/hdiutil" && ["attach", "detach", "create"].contains(action))
        }, "Presence recovery may inspect dependencies but must not dispatch storage mutations")
    }

    @Test("Stop rejects legacy calls without checkpoint and never probes occupancy")
    func stopRequiresExplicitCheckpointWithoutLsof() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil).succeeded)
        let before = fixture.runner.commands.count

        let legacy = fixture.service.stopDevelopmentDisk()

        #expect(!legacy.succeeded)
        #expect(fixture.runner.commands.count == before)
        #expect(!fixture.runner.commands.contains { $0.first == "/usr/sbin/lsof" })
        #expect(!fixture.runner.commands.contains { $0.first == "/usr/sbin/diskutil" && ($0.contains("unmount") || $0.contains("eject")) })
        #expect(fixture.store.value.workbenchOperation == nil)
    }

    @Test("Selected whole media accepts exactly one matching storage-driver ancestor")
    func selectedWholeMediaIOProviderMapping() throws {
        let counters = SectoriumDeviceIOCounters(readBytes: 1024, writtenBytes: 512)
        let mediaID = UUID()
        let provider = WorkbenchIORegistryFixture(mappings: [
            .init(bsdName: "disk81", stableMediaID: mediaID, isWholeMedia: true, providerAncestors: [
                .init(className: "IOMedia", counters: nil),
                .init(className: "IOBlockStorageDriver", counters: counters)
            ])
        ])
        let sampler = SectoriumDeviceIOSampler(provider: provider)

        #expect(sampler.counters(forWholeBSDName: "disk81", expectedMediaID: mediaID) == counters)
        #expect(provider.requestedNames == ["disk81"])
        #expect(sampler.counters(forWholeBSDName: "disk81s1", expectedMediaID: mediaID) == nil)
    }

    @Test("A backing-volume anchor never invokes the whole-media I/O provider")
    func anchoredIdentityDoesNotSampleWholeMedia() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backing = try #require(fixture.device.volumeUUIDs.first)
        let anchored = SectoriumPhysicalDevice(id: backing.uuidString, bsdName: "disk81",
            name: "External Fixture", isExternal: true, identityVerified: true,
            wholeDeviceBytes: 1000, mountedVolumePaths: [fixture.mount.path], volumeUUIDs: [backing],
            readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: backing, bsdName: "disk81s1", mountPoint: fixture.mount.path)],
            topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
            wholeMediaUUID: nil, requiresFreshParentCheck: true)
        let provider = WorkbenchIORegistryFixture(mappings: [])
        let service = HESectoriumService(paths: fixture.service.paths,
            backend: WorkbenchNoopBackend(), store: WorkbenchMemoryStore(),
            operationLock: WorkbenchMemoryLock(), installer: workbenchFixtureInstaller(fixture.service.paths),
            runner: fixture.runner,
            identityPolicy: .expected, sectoriumDeviceObserver: fixture.observer,
            sectoriumDeviceIOSampler: SectoriumDeviceIOSampler(provider: provider),
            portableDocumentWriter: WorkbenchPortableWriter())
        let before = fixture.runner.commands.count
        #expect(service.sampleSectoriumDeviceCounters(for: anchored) == nil)
        #expect(provider.requestedNames.isEmpty)
        #expect(fixture.runner.commands.count == before)
    }

    @Test("BSD-name reuse cannot bind replacement media counters to selected media A")
    func reusedBSDNameRejectsReplacementMediaCounters() throws {
        let selectedA = UUID(), replacementB = UUID()
        let replacementCounters = SectoriumDeviceIOCounters(readBytes: 987_654, writtenBytes: 456_789)
        let provider = WorkbenchIORegistryFixture(mappings: [
            .init(bsdName: "disk81", stableMediaID: replacementB, isWholeMedia: true, providerAncestors: [
                .init(className: "IOBlockStorageDriver", counters: replacementCounters)
            ])
        ])
        let sampler = SectoriumDeviceIOSampler(provider: provider)

        #expect(sampler.counters(forWholeBSDName: "disk81", expectedMediaID: selectedA) == nil)
        #expect(provider.requestedNames == ["disk81"])
    }

    @Test("IO provider rejects partition media, missing or partial counters, and ambiguous mappings")
    func ambiguousOrIncompleteIOProviderMappingIsUnknown() {
        let full = SectoriumDeviceIOCounters(readBytes: 100, writtenBytes: 200)
        let cases: [[SectoriumIOMediaProviderMapping]] = [
            [.init(bsdName: "disk82", stableMediaID: UUID(), isWholeMedia: false, providerAncestors: [
                .init(className: "IOBlockStorageDriver", counters: full)
            ])],
            [.init(bsdName: "disk82", stableMediaID: UUID(), isWholeMedia: true, providerAncestors: [])],
            [.init(bsdName: "disk82", stableMediaID: UUID(), isWholeMedia: true, providerAncestors: [
                .init(className: "IOBlockStorageDriver", counters: nil)
            ])],
            [.init(bsdName: "disk82", stableMediaID: UUID(), isWholeMedia: true, providerAncestors: [
                .init(className: "IOBlockStorageDriver", counters: full),
                .init(className: "IOBlockStorageDriver", counters: full)
            ])],
            [.init(bsdName: "disk82", stableMediaID: UUID(), isWholeMedia: true, ancestryIsUnambiguous: false, providerAncestors: [
                .init(className: "IOBlockStorageDriver", counters: full)
            ])],
            [
                .init(bsdName: "disk82", stableMediaID: UUID(), isWholeMedia: true, providerAncestors: [
                    .init(className: "IOBlockStorageDriver", counters: full)
                ]),
                .init(bsdName: "disk82", stableMediaID: UUID(), isWholeMedia: true, providerAncestors: [
                    .init(className: "IOBlockStorageDriver", counters: full)
                ])
            ]
        ]

        for mappings in cases {
            #expect(SectoriumDeviceIOSampler(provider: WorkbenchIORegistryFixture(mappings: mappings))
                .counters(forWholeBSDName: "disk82", expectedMediaID: UUID()) == nil)
        }
    }

    @Test("hdiutil stdinpass bytes are NUL terminated and embedded NUL passphrases are refused")
    func securePassphraseProtocol() throws {
        #expect(hdiutilPassphraseInput("pāss") == Data(Array("pāss".utf8) + [0]))
        #expect(hdiutilPassphraseInput("") == nil)
        #expect(hdiutilPassphraseInput("bad\0pass") == nil)

        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let valid = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id, parentDirectory: fixture.mount,
            name: "Encrypted", capacityGiB: 1, caseSensitive: false, password: "pāss")
        #expect(valid.succeeded)
        #expect(fixture.runner.secureInputs.count == 1)
        #expect(fixture.runner.commands.contains { $0.first == "/usr/bin/hdiutil" && $0.contains("-stdinpass") })
        #expect(fixture.runner.secureInputs[0] == Data(Array("pāss".utf8) + [0]))
        #expect(!String(decoding: fixture.runner.secureInputs[0], as: UTF8.self).contains("pāss\n"))

        let rejected = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id, parentDirectory: fixture.mount,
            name: "Invalid", capacityGiB: 1, caseSensitive: false, password: "bad\0pass")
        #expect(!rejected.succeeded)
        #expect(fixture.runner.secureInputs.count == 1)
        #expect(!fixture.runner.commands.contains { $0.contains("Invalid.sparsebundle") })
        #expect(!rejected.steps.contains { $0.detail.contains("bad") || $0.detail.contains("pāss") })

        fixture.service.selectSectoriumDevice(fixture.device.id)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        fixture.service.selectSectoriumProfile(profile.id)
        let invalidUnlock = fixture.service.startDevelopmentDisk(password: "bad\0pass")
        #expect(!invalidUnlock.succeeded)
        #expect(!invalidUnlock.steps.contains { $0.detail.contains("bad") || $0.detail.contains("pāss") })
        #expect(!fixture.runner.commands.contains { $0.contains("attach") })
        #expect(fixture.runner.secureInputs.count == 1)
    }

    @Test("encrypted attach sends the exact NUL-terminated passphrase only through secure stdin")
    func encryptedAttachUsesSecureStdinFixture() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outer = fixture.mount
        let dev = fixture.root.appendingPathComponent("dev-mount", isDirectory: true)
        let image = outer.appendingPathComponent("Fixture.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
        let outerID = try #require(fixture.device.volumeUUIDs.first)
        let paths = fixture.service.paths
        let policy = StorageIdentityPolicy(outerUUID: outerID, devUUID: UUID(), outerMountPoint: outer.path,
            devMountPoint: dev.path, devVolumeName: "Fixture-DEV", imagePath: image.path)
        let runner = PassphraseStorageFixtureRunner(outerMountPoint: outer.path, outerUUID: outerID)
        runner.detachedDEVPath = dev.path
        let backend = MacStorageBackend(paths: paths, runner: runner, policy: policy)

        #expect(FileManager.default.fileExists(atPath: policy.imagePath))
        #expect(FileManager.default.fileExists(atPath: policy.devMountPoint))
        #expect(backend.canAttemptMount(), "Fixture did not satisfy the backend's read-only mount preflight: \(runner.allArguments)")
        let result = backend.attachImage(password: "pāss")
        #expect(result.succeeded)
        #expect(runner.secureInputs == [Data(Array("pāss".utf8) + [0])])
        #expect(runner.secureArguments.first?.contains("-stdinpass") == true)
        #expect(runner.allArguments.flatMap { $0 }.allSatisfy { !$0.contains("pāss") })

        let rejected = backend.attachImage(password: "bad\0pass")
        #expect(!rejected.succeeded)
        #expect(runner.secureInputs.count == 1)
    }

    @Test("Physical-device catalog binds identity and volume metadata but rejects unproven counters")
    func catalogBindsMetadataWithoutGuessingCounters() throws {
        let mediaID = "B3C2D2F0-87C0-4EC8-914E-68790E4602C0"
        let volumeID = "92C9FE34-2C3B-4D27-9FEA-9B6E55EB8CF0"
        let disk = try plistData(["AllDisksAndPartitions": [[
            "DeviceIdentifier": "disk8",
            "Partitions": [["DeviceIdentifier": "disk8s1"]]
        ]]])
        let io = try plistData([[
            "Whole": true, "BSD Name": "disk8",
            "Statistics": ["Bytes (Read)": NSNumber(value: 1000), "Bytes (Write)": NSNumber(value: 2500)]
        ]])
        let devices = try SectoriumDeviceCatalog().parse(diskInventory: disk, ioRegistry: io, deviceInformation: [
            "disk8": ["MediaUUID": mediaID, "DeviceLocation": "External", "VirtualOrPhysical": "Physical",
                      "MediaName": "Fixture", "TotalSize": 5000],
            "disk8s1": ["VolumeUUID": volumeID, "MountPoint": "/Volumes/Fixture"]
        ])

        let device = try #require(devices.first)
        #expect(device.id == mediaID)
        #expect(device.identityVerified)
        #expect(device.isExternal)
        #expect(device.wholeDeviceBytes == 5000)
        #expect(device.mountedVolumePaths == ["/Volumes/Fixture"])
        #expect(device.volumeUUIDs == [UUID(uuidString: volumeID)!])
        #expect(device.readBytes == nil)
        #expect(device.writtenBytes == nil)
    }

    @Test("Two physical roots and one observed DEV logical capacity survive virtual filtering")
    func actualDriveShapeAndMissingMetadata() throws {
        // Sanitized structural fixture; identifiers are synthetic while disk topology mirrors the recorded shape.
        let he = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let dev = UUID(uuidString: "66666666-7777-4888-8999-AAAAAAAAAAAA")!
        let rows: [[String: Any]] = [
            ["DeviceIdentifier": "disk0", "Partitions": [["DeviceIdentifier": "disk0s1"]]],
            ["DeviceIdentifier": "disk4", "Partitions": [["DeviceIdentifier": "disk4s2"]]],
            ["DeviceIdentifier": "disk5", "APFSVolumes": [["DeviceIdentifier": "disk5s1", "VolumeName": "DEV_APFS"]]],
            ["DeviceIdentifier": "disk6", "Partitions": [["DeviceIdentifier": "disk6s1"]]]
        ]
        var info: [String: [String: Any]] = [
            "disk0": ["VirtualOrPhysical": "Unknown", "WholeDisk": true, "Internal": true,
                      "Content": "GUID_partition_scheme", "MediaName": "APPLE SSD AP0256Z", "TotalSize": 251_000_193_024],
            "disk4": ["VirtualOrPhysical": "Virtual", "WholeDisk": true, "MediaName": "Disk Image"],
            "disk5": ["VirtualOrPhysical": "Virtual", "WholeDisk": true, "MediaName": "APFS Container",
                      "APFSPhysicalStores": [["APFSPhysicalStore": "disk4s2"]]],
            "disk6": ["VirtualOrPhysical": "Physical", "WholeDisk": true, "Internal": false,
                      "MediaName": "ES3", "TotalSize": 1_024_209_543_168],
            "disk6s1": ["DeviceIdentifier": "disk6s1", "ParentWholeDisk": "disk6",
                          "VolumeUUID": he.uuidString, "VolumeName": "HE", "MountPoint": "/Volumes/HE"],
            "disk5s1": ["DeviceIdentifier": "disk5s1", "ParentWholeDisk": "disk5",
                          "VolumeUUID": dev.uuidString, "VolumeName": "DEV_APFS",
                          "MountPoint": "/Volumes/HE/DEV", "TotalSize": 321_912_791_040]
        ]
        let catalog = SectoriumDeviceCatalog()
        let inventory = try plistData(["AllDisksAndPartitions": rows])
        let devices = try catalog.parse(diskInventory: inventory, ioRegistry: Data(), deviceInformation: info)
        #expect(devices.filter { $0.isVirtual == false }.map(\.bsdName).sorted() == ["disk0", "disk6"])
        let outer = try #require(devices.first { $0.bsdName == "disk6" })
        #expect(outer.name == "ES3" && outer.volumeMembers.first?.name == "HE")
        #expect(outer.identityBasis == .uniqueBackingVolumeUUID && outer.wholeMediaUUID == nil)
        let virtualDEV = try #require(devices.first { $0.bsdName == "disk5" })
        #expect(virtualDEV.volumeMembers.count == 1)
        #expect(virtualDEV.volumeMembers[0].capacityBytes == 321_912_791_040)
        #expect(virtualDEV.volumeMembers[0].mountPoint == "/Volumes/HE/DEV")
        info["disk5s1"]?["TotalSize"] = nil
        let missing = try catalog.parse(diskInventory: inventory, ioRegistry: Data(), deviceInformation: info)
        #expect(missing.first { $0.bsdName == "disk5" }?.volumeMembers.first?.capacityBytes == nil)
        info["disk5s1"]?["ParentWholeDisk"] = "disk6"
        let wrong = try catalog.parse(diskInventory: inventory, ioRegistry: Data(), deviceInformation: info)
        #expect(wrong.first { $0.bsdName == "disk5" }?.volumeMembers.isEmpty == true)
    }

    @Test("Physical picker groups synthesized APFS and image disks under the two hardware roots")
    func physicalRootsAndUniqueBackingAnchor() throws {
        let backing = UUID(uuidString: "63CB46D8-620B-48AF-9F23-C0129D692013")!
        let rows: [[String: Any]] = [
            ["DeviceIdentifier": "disk0", "Partitions": (1...3).map { ["DeviceIdentifier": "disk0s\($0)",
                "Content": $0 == 1 ? "Apple_APFS_ISC" : $0 == 3 ? "Apple_APFS_Recovery" : "Apple_APFS"] }],
            ["DeviceIdentifier": "disk1"], ["DeviceIdentifier": "disk2"], ["DeviceIdentifier": "disk3"],
            ["DeviceIdentifier": "disk4", "Partitions": [["DeviceIdentifier": "disk4s1"], ["DeviceIdentifier": "disk4s2"]]],
            ["DeviceIdentifier": "disk5", "Partitions": [["DeviceIdentifier": "disk5s1"]]],
            ["DeviceIdentifier": "disk6", "Partitions": [["DeviceIdentifier": "disk6s1"]]]
        ]
        var info: [String: [String: Any]] = [:]
        info["disk0"] = ["VirtualOrPhysical": "Unknown", "WholeDisk": true, "Internal": true,
                         "Content": "GUID_partition_scheme", "MediaName": "Internal SSD"]
        for n in 1...5 { info["disk\(n)"] = ["VirtualOrPhysical": "Virtual", "WholeDisk": true,
                                               "MediaName": n == 4 ? "Disk Image" : "APFS Container"] }
        for n in 1...3 { info["disk\(n)"]?["APFSPhysicalStores"] = [["APFSPhysicalStore": "disk0s\(n)"]] }
        info["disk6"] = ["VirtualOrPhysical": "Physical", "WholeDisk": true, "Internal": false,
                         "MediaName": "External Fixture", "TotalSize": 1_000_000]
        info["disk6s1"] = ["DeviceIdentifier": "disk6s1", "ParentWholeDisk": "disk6",
                           "VolumeUUID": backing.uuidString, "MountPoint": "/Volumes/Fixture"]
        let data = try plistData(["AllDisksAndPartitions": rows])
        let devices = try SectoriumDeviceCatalog().parse(diskInventory: data, ioRegistry: Data(), deviceInformation: info)
        let selectable = devices.filter { $0.isVirtual == false }
        #expect(selectable.map(\.bsdName).sorted() == ["disk0", "disk6"])
        #expect(selectable.first { $0.bsdName == "disk0" }?.apfsContainers.count == 3)
        let external = try #require(selectable.first { $0.bsdName == "disk6" })
        #expect(external.identityVerified)
        #expect(external.identityBasis == .uniqueBackingVolumeUUID)
        #expect(external.id == backing.uuidString)
        #expect(external.wholeMediaUUID == nil)
        #expect(external.volumeMembers.map(\.volumeUUID) == [backing])
        #expect(devices.filter { $0.isVirtual == true }.count == 5)
        let renumbered = [["DeviceIdentifier": "disk60", "Partitions": [["DeviceIdentifier": "disk60s1"]]]]
        let renumberedInfo: [String: [String: Any]] = [
            "disk60": ["VirtualOrPhysical": "Physical", "Internal": false],
            "disk60s1": ["DeviceIdentifier": "disk60s1", "ParentWholeDisk": "disk60",
                           "VolumeUUID": backing.uuidString, "MountPoint": "/Volumes/Fixture"]]
        let fresh = try SectoriumDeviceCatalog().parse(diskInventory: plistData(["AllDisksAndPartitions": renumbered]),
            ioRegistry: Data(), deviceInformation: renumberedInfo)
        #expect(fresh.first?.id == external.id)
        info["disk7"] = ["VirtualOrPhysical": "Physical", "Internal": false]
        info["disk7s1"] = ["DeviceIdentifier": "disk7s1", "ParentWholeDisk": "disk7", "VolumeUUID": backing.uuidString]
        let clonedRows = rows + [["DeviceIdentifier": "disk7", "Partitions": [["DeviceIdentifier": "disk7s1"]]]]
        let cloned = try SectoriumDeviceCatalog().parse(diskInventory: plistData(["AllDisksAndPartitions": clonedRows]),
            ioRegistry: Data(), deviceInformation: info)
        #expect(cloned.filter { ["disk6", "disk7"].contains($0.bsdName) }.allSatisfy { !$0.identityVerified })
        info["disk7s1"] = nil
        info["disk6s1"]?["ParentWholeDisk"] = "disk7"
        let wrongParent = try SectoriumDeviceCatalog().parse(diskInventory: data, ioRegistry: Data(), deviceInformation: info)
        #expect(wrongParent.first { $0.bsdName == "disk6" }?.identityVerified == false)
    }

    @Test("Contradictory ownership fields cannot verify a catalog anchor or cross the create gate")
    func conflictingParentClaimsRefuseBeforeCreate() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backing = try #require(fixture.device.volumeUUIDs.first)
        let inventoryRows: [[String: Any]] = [["DeviceIdentifier": "disk81",
            "Partitions": [["DeviceIdentifier": "disk81s1"]]]]
        let inventory = try plistData(["AllDisksAndPartitions": inventoryRows])
        let diskInfo: [String: [String: Any]] = [
            "disk81": ["VirtualOrPhysical": "Physical", "Internal": false],
            "disk81s1": ["DeviceIdentifier": "disk81s1", "ParentWholeDisk": "disk81",
                          "PartOfWhole": "disk82", "VolumeUUID": backing.uuidString,
                          "MountPoint": fixture.mount.path]]
        let catalog = try SectoriumDeviceCatalog().parse(diskInventory: inventory,
            ioRegistry: Data(), deviceInformation: diskInfo)
        #expect(catalog.first?.identityVerified == false)
        #expect(catalog.first?.identityBasis == .unavailable)
        #expect(catalog.first?.topologyComplete == false)
        #expect(SectoriumDeviceCatalog.verifiedParentWholeDisk(diskInfo["disk81s1"]!) == nil)

        let selected = SectoriumPhysicalDevice(id: backing.uuidString, bsdName: "disk81", name: "Fixture Drive",
            isExternal: true, identityVerified: true, wholeDeviceBytes: 64_000_000_000,
            mountedVolumePaths: [fixture.mount.path], volumeUUIDs: [backing],
            readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: backing, bsdName: "disk81s1", mountPoint: fixture.mount.path)],
            topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
            requiresFreshParentCheck: true)
        fixture.observer.device = selected
        fixture.service.selectSectoriumDevice(selected.id, observedBSDName: selected.bsdName, observedDevice: selected)
        fixture.runner.mountParentWholeDisk = "disk81"
        fixture.runner.mountPartOfWholeDisk = "disk82"
        let result = fixture.service.createDevelopmentDisk(deviceID: selected.id,
            parentDirectory: fixture.mount, name: "Contradiction", capacityGiB: 1,
            caseSensitive: false, password: nil)
        #expect(!result.succeeded)
        #expect(fixture.service.sectoriumProfiles().isEmpty)
        #expect(!fixture.runner.commands.contains { $0.first == "/usr/bin/hdiutil" && $0.contains("create") })
        #expect(!FileManager.default.fileExists(atPath: fixture.mount.appendingPathComponent("Contradiction.sparsebundle").path))
    }

    @Test("Legacy safe eject refuses conflicting parent fields before dispatch")
    func conflictingParentClaimsRefuseLegacyEject() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.mountParentWholeDisk = "disk81"
        fixture.runner.mountPartOfWholeDisk = "disk82"
        let backend = MacStorageBackend(paths: fixture.service.paths, runner: fixture.runner,
            policy: fixture.service.coreController.identityPolicy)
        let outcome = backend.perform(.ejectOuterHE)
        #expect(!outcome.succeeded)
        #expect(!fixture.runner.commands.contains { $0.first == "/usr/sbin/diskutil" && $0.contains("eject") })
    }

    @Test("Same-named physical roots remain distinct and unknown kind is unassigned")
    func sameNamedPhysicalRootsAndUnknownKind() throws {
        let first = UUID(), second = UUID()
        let rows: [[String: Any]] = [["DeviceIdentifier": "disk80"],
            ["DeviceIdentifier": "disk81"], ["DeviceIdentifier": "disk82"], ["DeviceIdentifier": "disk83"]]
        let devices = try SectoriumDeviceCatalog().parse(diskInventory: plistData(["AllDisksAndPartitions": rows]),
            ioRegistry: Data(), deviceInformation: [
                "disk80": ["VirtualOrPhysical": "Physical", "MediaName": "Same Name", "MediaUUID": first.uuidString],
                "disk81": ["VirtualOrPhysical": "Physical", "MediaName": "Same Name", "MediaUUID": second.uuidString],
                "disk82": ["VirtualOrPhysical": "Unknown", "MediaName": "Same Name",
                           "MediaUUID": UUID().uuidString],
                "disk83": ["VirtualOrPhysical": "Virtual", "MediaName": "Ambiguous APFS",
                           "APFSPhysicalStores": [["APFSPhysicalStore": "disk80s1"],
                                                   ["APFSPhysicalStore": "disk81s1"]]]])
        #expect(devices.filter { $0.isVirtual == false }.count == 2)
        #expect(Set(devices.filter { $0.isVirtual == false }.map(\.id)).count == 2)
        #expect(devices.first { $0.bsdName == "disk82" }?.isVirtual == nil)
        #expect(devices.first { $0.bsdName == "disk82" }?.identityVerified == false)
        #expect(devices.first { $0.bsdName == "disk83" }?.isVirtual == true)
        #expect(devices.first { $0.bsdName == "disk83" }?.hasAmbiguousPhysicalStores == true)
    }

    @Test("Only confirmed internal location can exclude an unrelated device from disappearance checks")
    func unknownAndContradictoryLocationsRemainUnconfirmed() throws {
        let duplicateIdentity = UUID().uuidString
        let info: [String: [String: Any]] = [
            "disk80": ["VirtualOrPhysical": "Physical", "Internal": true, "MediaUUID": duplicateIdentity],
            "disk81": ["VirtualOrPhysical": "Physical", "DeviceLocation": "Internal", "MediaUUID": duplicateIdentity],
            "disk82": ["VirtualOrPhysical": "Physical"],
            "disk83": ["VirtualOrPhysical": "Physical", "Internal": true, "DeviceLocation": "External"],
            "disk84": ["VirtualOrPhysical": "Physical", "Internal": false, "DeviceLocation": "Internal"]
        ]
        let rows = info.keys.sorted().map { ["DeviceIdentifier": $0] }
        let devices = try SectoriumDeviceCatalog().parse(
            diskInventory: plistData(["AllDisksAndPartitions": rows]), ioRegistry: Data(), deviceInformation: info)
        for bsd in ["disk80", "disk81"] {
            let device = try #require(devices.first { $0.bsdName == bsd })
            #expect(device.isInternalConfirmed)
            #expect(!device.identityVerified) // Duplicate-identity degradation preserves location evidence.
        }
        for bsd in ["disk82", "disk83", "disk84"] {
            #expect(devices.first { $0.bsdName == bsd }?.isInternalConfirmed == false)
        }
        #expect(devices.first { $0.bsdName == "disk82" }?.isExternal == false)
    }

    @Test("A selected backing-volume anchor refuses a fresh BSD attachment change")
    func anchoredSelectionRejectsReconnectBeforeCreate() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let volume = try #require(fixture.device.volumeUUIDs.first)
        func anchored(_ bsd: String) -> SectoriumPhysicalDevice {
            SectoriumPhysicalDevice(id: volume.uuidString, bsdName: bsd, name: "Fixture Drive",
                isExternal: true, identityVerified: true, wholeDeviceBytes: 64_000_000_000,
                mountedVolumePaths: [fixture.mount.path], volumeUUIDs: [volume],
                readBytes: nil, writtenBytes: nil,
                volumeMembers: [.init(volumeUUID: volume, bsdName: bsd + "s1", mountPoint: fixture.mount.path)],
                topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
                requiresFreshParentCheck: true)
        }
        let selected = anchored("disk81")
        fixture.observer.device = selected
        fixture.service.selectSectoriumDevice(selected.id, observedBSDName: selected.bsdName, observedDevice: selected)
        let changedTopology = SectoriumPhysicalDevice(id: selected.id, bsdName: selected.bsdName,
            name: selected.name, isExternal: true, identityVerified: true,
            wholeDeviceBytes: 63_000_000_000, mountedVolumePaths: selected.mountedVolumePaths,
            volumeUUIDs: selected.volumeUUIDs, readBytes: nil, writtenBytes: nil,
            volumeMembers: selected.volumeMembers, topologyComplete: true, isVirtual: false,
            identityBasis: .uniqueBackingVolumeUUID, requiresFreshParentCheck: true)
        fixture.observer.device = changedTopology
        #expect(fixture.service.sectoriumReadiness(deviceID: selected.id, devices: [changedTopology], profiles: [])
            == .unknown("Drive attachment or topology changed; reselect the physical drive before management"))
        let reattached = anchored("disk82")
        fixture.observer.device = reattached
        #expect(fixture.service.sectoriumReadiness(deviceID: selected.id, devices: [reattached], profiles: [])
            == .unknown("Drive attachment or topology changed; reselect the physical drive before management"))
        let result = fixture.service.createDevelopmentDisk(deviceID: selected.id,
            parentDirectory: fixture.mount, name: "AfterReconnect", capacityGiB: 1,
            caseSensitive: false, password: nil)
        #expect(!result.succeeded)
        #expect(fixture.service.sectoriumProfiles().isEmpty)
        #expect(!fixture.runner.commands.contains { $0.first == "/usr/bin/hdiutil" && $0.contains("create") })
    }

    @Test("Physical capacity drift refuses Create before command dispatch and preserves preimages")
    func capacityDriftRefusesCreateBeforeDispatch() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let volume = try #require(fixture.device.volumeUUIDs.first)
        func anchored(_ capacity: UInt64) -> SectoriumPhysicalDevice {
            SectoriumPhysicalDevice(id: volume.uuidString, bsdName: "disk81", name: "Fixture Drive",
                isExternal: true, identityVerified: true, wholeDeviceBytes: capacity,
                mountedVolumePaths: [fixture.mount.path], volumeUUIDs: [volume],
                readBytes: nil, writtenBytes: nil,
                volumeMembers: [.init(volumeUUID: volume, bsdName: "disk81s1", mountPoint: fixture.mount.path)],
                topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
                requiresFreshParentCheck: true)
        }
        let selected = anchored(64_000_000_000)
        fixture.observer.device = selected
        fixture.runner.mountParentWholeDisk = "disk81"
        fixture.service.selectSectoriumDevice(selected.id, observedBSDName: selected.bsdName, observedDevice: selected)
        let fresh = anchored(63_000_000_000)
        fixture.observer.device = fresh
        #expect(fixture.service.sectoriumReadiness(deviceID: selected.id, devices: [fresh], profiles: [])
            == .unknown("Drive attachment or topology changed; reselect the physical drive before management"))
        try FileManager.default.createDirectory(at: fixture.service.paths.root, withIntermediateDirectories: true)
        let profilePreimage = Data("[]".utf8)
        let configPreimage = Data("fixture-config-preimage".utf8)
        try profilePreimage.write(to: fixture.service.paths.sectoriumProfiles)
        try configPreimage.write(to: fixture.service.paths.config)
        let refusal = fixture.service.createDevelopmentDisk(deviceID: selected.id,
            parentDirectory: fixture.mount, name: "CapacityDrift", capacityGiB: 1,
            caseSensitive: false, password: nil)
        #expect(!refusal.succeeded)
        #expect(!fixture.runner.commands.contains { $0.first == "/usr/bin/hdiutil" && $0.contains("create") })
        #expect(fixture.service.sectoriumProfiles().isEmpty)
        #expect(try Data(contentsOf: fixture.service.paths.sectoriumProfiles) == profilePreimage)
        #expect(try Data(contentsOf: fixture.service.paths.config) == configPreimage)
        #expect(!FileManager.default.fileExists(atPath: fixture.mount.appendingPathComponent("CapacityDrift.sparsebundle").path))
    }

    @Test("An anchored drive permits create only after explicit fresh reselection following renumber")
    func freshReselectionAfterRenumberAllowsAnchoredCreate() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let volume = try #require(fixture.device.volumeUUIDs.first)
        func anchored(_ bsd: String) -> SectoriumPhysicalDevice {
            SectoriumPhysicalDevice(id: volume.uuidString, bsdName: bsd, name: "Fixture Drive",
                isExternal: true, identityVerified: true, wholeDeviceBytes: 64_000_000_000,
                mountedVolumePaths: [fixture.mount.path], volumeUUIDs: [volume],
                readBytes: nil, writtenBytes: nil,
                volumeMembers: [.init(volumeUUID: volume, bsdName: bsd + "s1", mountPoint: fixture.mount.path)],
                topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
                requiresFreshParentCheck: true)
        }
        let old = anchored("disk81"), current = anchored("disk82")
        fixture.observer.device = old
        fixture.service.selectSectoriumDevice(old.id, observedBSDName: old.bsdName, observedDevice: old)
        fixture.observer.device = current
        fixture.runner.mountParentWholeDisk = "disk82"
        let stale = fixture.service.createDevelopmentDisk(deviceID: current.id, parentDirectory: fixture.mount,
            name: "Stale", capacityGiB: 1, caseSensitive: false, password: nil)
        #expect(!stale.succeeded)
        #expect(fixture.service.sectoriumProfiles().isEmpty)
        #expect(fixture.service.resumePendingSectoriumOperation().succeeded)
        fixture.service.selectSectoriumDevice(current.id, observedBSDName: current.bsdName, observedDevice: current)
        let fresh = fixture.service.createDevelopmentDisk(deviceID: current.id, parentDirectory: fixture.mount,
            name: "Fresh", capacityGiB: 1, caseSensitive: false, password: nil)
        #expect(fresh.succeeded)
        #expect(fixture.service.sectoriumProfiles().count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.mount.appendingPathComponent("Stale.sparsebundle").path))
    }

    @Test("Duplicated whole-media identity cannot bind either physical drive")
    func duplicatedWholeMediaIdentityRefused() throws {
        let repeated = UUID().uuidString
        let inventory = try plistData(["AllDisksAndPartitions": [
            ["DeviceIdentifier": "disk8"], ["DeviceIdentifier": "disk9"]]])
        let devices = try SectoriumDeviceCatalog().parse(diskInventory: inventory, ioRegistry: Data(),
            deviceInformation: [
                "disk8": ["MediaUUID": repeated, "VirtualOrPhysical": "Physical", "Internal": false],
                "disk9": ["MediaUUID": repeated, "VirtualOrPhysical": "Physical", "Internal": false]
            ])
        #expect(devices.count == 2)
        #expect(devices.allSatisfy { !$0.identityVerified && $0.identityBasis == .unavailable })
        #expect(Set(devices.map(\.id)).count == 2)
    }

    @Test("Missing or malformed whole-device counters remain unknown")
    func unavailableCountersAreUnknown() throws {
        let disk = try plistData(["AllDisksAndPartitions": [["DeviceIdentifier": "disk9"]]])
        let devices = try SectoriumDeviceCatalog().parse(diskInventory: disk, ioRegistry: Data(), deviceInformation: [
            "disk9": ["MediaUUID": "4F0636A2-5A2E-4BAB-9B10-3D0BE8DD6B1D", "Internal": false,
                      "VirtualOrPhysical": "Physical"]
        ])
        let device = try #require(devices.first)
        #expect(device.identityVerified)
        #expect(device.isExternal)
        #expect(device.readBytes == nil)
        #expect(device.writtenBytes == nil)
    }

    @Test("Malformed inventory refuses to produce a guessed device")
    func malformedInventoryRefused() {
        #expect(throws: SectoriumDeviceCatalogError.malformedDeviceInventory) {
            try SectoriumDeviceCatalog().parse(diskInventory: Data("not a plist".utf8), ioRegistry: Data())
        }
    }

    @Test("Create records a fixture-only sparsebundle and clears its durable operation marker")
    func createDevelopmentDiskUsesIsolatedFixture() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let result = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 12,
            caseSensitive: true, password: nil)

        #expect(result.succeeded)
        #expect(result.steps.map(\.step) == ["recordProfile", "createSparsebundle", "verifyImageFormat"])
        #expect(FileManager.default.fileExists(atPath: fixture.mount.appendingPathComponent("Development.sparsebundle").path))
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.service.sectoriumProfiles().first?.logicalCapacityBytes == UInt64(12) * 1_073_741_824)
        #expect(fixture.service.sectoriumProfiles().first?.imageFormat == "UDSB")
        #expect(fixture.runner.commands.contains { $0.first == "/usr/bin/hdiutil" })
    }

    @Test("Create keeps its recovery marker when documented image format is unknown or conflicting")
    func createFailsClosedForUnknownImageFormat() throws {
        for format in ["UDSP", "", "UDSB\nextra"] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.runner.imageFormatOutput = .init(exitCode: 0, detail: format)
            let result = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
                parentDirectory: fixture.mount, name: "Format", capacityGiB: 1,
                caseSensitive: false, password: nil)
            #expect(!result.succeeded)
            #expect(fixture.store.value.workbenchOperation?.hasPrefix("create:") == true)
            #expect(fixture.service.sectoriumProfiles().first?.imageFormat == nil)
            #expect(result.steps.contains { $0.step == "verifyImageFormat" && $0.status == .failed })
        }
    }

    @Test("Adopt refuses an existing fixture image when required image metadata is unknown")
    func adoptDevelopmentDiskFailsClosedWithoutImageMetadata() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let image = fixture.mount.appendingPathComponent("Existing.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
        let result = fixture.service.adoptDevelopmentDisk(deviceID: fixture.device.id, imageURL: image)

        #expect(!result.succeeded)
        #expect(fixture.store.value.workbenchPhase == "validation-rejected")
        #expect(fixture.service.sectoriumProfiles().isEmpty)
        #expect(!fixture.runner.commands.contains {
            $0.first == "/usr/bin/hdiutil" && $0.dropFirst().first != "info"
        })
    }

    @Test("Mounted configured legacy DEV_APFS adopts observed identity while image facts remain unknown", arguments: [false, true])
    func adoptsOnlyMountedConfiguredLegacyIdentity(mountedFormatBusy: Bool) throws {
        let requestedRoot = URL(fileURLWithPath: "/private/tmp/sectorium-legacy-adoption-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: false)
        let root = requestedRoot.resolvingSymlinksInPath()
        let outer = root.appendingPathComponent("HE", isDirectory: true)
        let dev = outer.appendingPathComponent("DEV", isDirectory: true)
        let image = outer.appendingPathComponent(".DEV-APFS.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: requestedRoot) }
        let outerID = UUID(), devID = UUID()
        let policy = StorageIdentityPolicy(outerUUID: outerID, devUUID: devID, outerMountPoint: outer.path,
            devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
        let device = SectoriumPhysicalDevice(id: outerID.uuidString, bsdName: "disk91", name: "Fixture HE",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [outer.path],
            volumeUUIDs: [outerID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: outerID, bsdName: "disk91s1", mountPoint: outer.path)],
            topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
            requiresFreshParentCheck: true)
        let observation = StorageObservation(
            outer: .init(uuid: outerID, mountPoint: outer.path, fileSystem: "ExFAT", writable: true,
                         name: "HE", rootMatchesExpected: true),
            dev: .init(uuid: devID, mountPoint: dev.path, fileSystem: "APFS", writable: true,
                       name: "DEV_APFS", rootMatchesExpected: true),
            image: .init(backingVolumeUUID: outerID, attachedVolumeUUID: devID, path: image.path))
        let payload = image.appendingPathComponent("bands.dat")
        let paths = HESectoriumPaths(root: root.appendingPathComponent("support", isDirectory: true))
        let config = paths.config
        let profilesFile = paths.sectoriumProfiles
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture image payload".utf8).write(to: payload)
        let identityConfiguration: [String: String] = [
            "outerUUID": StorageIdentityPolicy.expected.outerUUID.uuidString,
            "devUUID": StorageIdentityPolicy.expected.devUUID!.uuidString,
            "outerMountPoint": "/Volumes/HE", "devMountPoint": "/Volumes/HE/DEV",
            "devVolumeName": "DEV_APFS", "imagePath": "/Volumes/HE/.DEV-APFS.sparsebundle"
        ]
        try JSONSerialization.data(withJSONObject: identityConfiguration, options: [.sortedKeys]).write(to: config)
        try Data("[]".utf8).write(to: profilesFile)
        for path in [payload, config, profilesFile] {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        }
        let protected = [payload, config, profilesFile]
        func preimages() throws -> [(String, NSNumber)] {
            try protected.map { path in
                let digest = SHA256.hash(data: try Data(contentsOf: path)).map { String(format: "%02x", $0) }.joined()
                let mode = try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber
                return (digest, mode ?? -1)
            }
        }
        let beforePreimages = try preimages()
        let runner = WorkbenchFixtureRunner(mountPoint: outer.path, volumeUUID: outerID)
        runner.imageInventory = [["image-path": image.path]]
        runner.mountParentWholeDisk = "disk92"
        let store = WorkbenchMemoryStore()
        let service = HESectoriumService(paths: HESectoriumPaths(root: root.appendingPathComponent("support")),
            backend: WorkbenchAdoptionBackend(observation: observation), store: store,
            operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(HESectoriumPaths(root: root.appendingPathComponent("support"))),
            runner: runner, identityPolicy: policy,
            sectoriumDeviceObserver: WorkbenchFixtureObserver(device: device),
            portableDocumentWriter: WorkbenchPortableWriter())
        service.selectSectoriumDevice(device.id, observedBSDName: device.bsdName, observedDevice: device)

        let originalImageChildren = try FileManager.default.contentsOfDirectory(atPath: image.path)
        let wrongParent = service.adoptDevelopmentDisk(deviceID: device.id, imageURL: image)
        #expect(!wrongParent.succeeded)
        #expect(service.sectoriumProfiles().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: image.path) == originalImageChildren)
        #expect(try preimages().map(\.0) == beforePreimages.map(\.0))
        #expect(try preimages().map(\.1) == beforePreimages.map(\.1))
        #expect(service.resumePendingSectoriumOperation().succeeded)
        runner.mountParentWholeDisk = "disk91"
        for (metadataUUID, metadataMount) in [(UUID(), dev.path), (devID, outer.path)] {
            runner.additionalDiskInfos[dev.path] = ["VolumeUUID": metadataUUID.uuidString,
                "MountPoint": metadataMount, "FilesystemType": "APFS", "VolumeSize": UInt64(321_912_791_040)]
            let mismatchedMetadata = service.adoptDevelopmentDisk(deviceID: device.id, imageURL: image)
            #expect(!mismatchedMetadata.succeeded)
            #expect(service.sectoriumProfiles().isEmpty)
            #expect(service.resumePendingSectoriumOperation().succeeded)
        }
        runner.additionalDiskInfos.removeValue(forKey: dev.path)
        if mountedFormatBusy {
            runner.imageFormatOutput = .init(exitCode: 1,
                detail: "hdiutil: WARNING: 'hdiutil imageinfo ...' is deprecated.\nhdiutil: imageinfo failed - Resource temporarily unavailable\n")
            let metadataURL = image.appendingPathComponent("Info.plist")
            try Data("invalid sparsebundle descriptor".utf8).write(to: metadataURL)
            let refusedFormat = service.adoptDevelopmentDisk(deviceID: device.id, imageURL: image)
            #expect(!refusedFormat.succeeded)
            #expect(service.sectoriumProfiles().isEmpty)
            #expect(!runner.commands.contains { $0.contains("attach") || $0.contains("create") })
            #expect(service.resumePendingSectoriumOperation().succeeded)
            try PropertyListSerialization.data(fromPropertyList: [
                "diskimage-bundle-type": "com.apple.diskimage.sparsebundle",
                "bundle-backingstore-version": 2, "band-size": 8_388_608, "size": UInt64(322_122_547_200)
            ], format: .xml, options: 0).write(to: metadataURL)
        }
        let result = service.adoptDevelopmentDisk(deviceID: device.id, imageURL: image)
        #expect(result.succeeded, "\(String(describing: result.failure))")
        let profile = try #require(service.sectoriumProfiles().first)
        #expect(result.succeeded)
        #expect(profile.imagePath == policy.imagePath)
        #expect(profile.backingVolumeUUID == outerID)
        #expect(profile.devUUID == devID)
        #expect(profile.encrypted == nil)
        #expect(profile.caseSensitive == nil)
        #expect(profile.logicalCapacityBytes == nil)
        #expect(!profile.hasVerifiedImageMetadata)
        #expect(service.sectoriumReadiness(deviceID: device.id, devices: [device], profiles: [profile])
            == .unknown("Development disk state could not be verified"))
        let startWithoutPassword = service.startDevelopmentDisk()
        #expect(!startWithoutPassword.succeeded)
        #expect(String(describing: startWithoutPassword.failure).lowercased().contains("encryption status could not be verified"))
        #expect(!runner.commands.contains { $0.first == "/usr/bin/hdiutil" && $0.contains("attach") })
        #expect(store.value.workbenchOperation != nil)
        #expect(service.resumePendingSectoriumOperation().succeeded)
        #expect(runner.commands.contains { $0 == ["/usr/bin/hdiutil", "imageinfo", policy.imagePath, "-format"] })
        #expect(!runner.commands.contains { $0.contains("attach") || $0.contains("create") })
        #expect(store.value.workbenchOperation == nil)
    }

    @Test("Configured legacy DEV_APFS adoption completes isolated Stop Start lifecycle", arguments: [false, true])
    func configuredLegacyAdoptionStopStartLifecycle(capacityAvailable: Bool) throws {
        let requestedRoot = URL(fileURLWithPath: "/private/tmp/sectorium-legacy-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: false)
        let root = requestedRoot.resolvingSymlinksInPath()
        let outer = root.appendingPathComponent("HE", isDirectory: true)
        let dev = outer.appendingPathComponent("DEV", isDirectory: true)
        let image = outer.appendingPathComponent(".DEV-APFS.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: requestedRoot) }

        let outerID = UUID(), devID = UUID(), mediaID = UUID()
        let identity = StorageIdentityPolicy(outerUUID: outerID, devUUID: devID, outerMountPoint: outer.path,
            devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
        let device = SectoriumPhysicalDevice(id: mediaID.uuidString, bsdName: "disk91", name: "Legacy Fixture HE",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [outer.path],
            volumeUUIDs: [outerID], readBytes: nil, writtenBytes: nil)
        let observation = StorageObservation(
            outer: .init(uuid: outerID, mountPoint: outer.path, fileSystem: "ExFAT", writable: true,
                         name: "HE", rootMatchesExpected: true),
            dev: .init(uuid: devID, mountPoint: dev.path, fileSystem: "APFS", writable: true,
                       name: "DEV_APFS", rootMatchesExpected: true),
            image: .init(backingVolumeUUID: outerID, attachedVolumeUUID: devID, path: image.path))
        let runner = WorkbenchFixtureRunner(mountPoint: outer.path, volumeUUID: outerID)
        runner.imageInventory = [["image-path": image.path, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk30"],
            ["mount-point": dev.path, "volume-uuid": devID.uuidString, "dev-entry": "/dev/disk31s1"]
        ]]]
        runner.imageFormatOutput = .init(exitCode: 0, detail: "UDSB\n")
        runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        runner.attachedImageInventory = runner.imageInventory
        runner.attachOutcome = .success
        runner.occupancyIsClear = true
        runner.ejectAfterUnmountEnabled = true
        runner.additionalDiskInfos = [
            "/dev/disk81s1": ["VolumeUUID": outerID.uuidString, "MountPoint": outer.path,
                "FilesystemType": "ExFAT", "WritableVolume": true, "DeviceIdentifier": "disk81s1",
                "PartOfWhole": "disk81"],
            "/dev/disk81": ["DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical"],
            dev.path: ["VolumeUUID": devID.uuidString, "MountPoint": dev.path, "FilesystemType": "APFS",
                "WritableVolume": true, "VolumeName": "DEV_APFS", "DeviceIdentifier": "disk31s1",
                "APFSContainerReference": "disk31", "VolumeSize": 0,
                "TotalSize": capacityAvailable ? UInt64(321_912_791_040) : 0],
            "/dev/disk31s1": ["VolumeUUID": devID.uuidString, "MountPoint": dev.path, "FilesystemType": "APFS",
                "WritableVolume": true, "VolumeName": "DEV_APFS", "DeviceIdentifier": "disk31s1",
                "APFSContainerReference": "disk31"]
        ]
        runner.detachedDiskInfos[dev.path] = ["VolumeUUID": outerID.uuidString, "MountPoint": outer.path,
            "FilesystemType": "ExFAT", "WritableVolume": true, "VolumeName": "Legacy Fixture HE",
            "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81"]
        runner.apfsContainers = [["ContainerReference": "disk31",
            "PhysicalStores": [["DeviceIdentifier": "disk30"]],
            "Volumes": [["APFSVolumeUUID": devID.uuidString, "DeviceIdentifier": "disk31s1"]]]]
        let store = WorkbenchMemoryStore()
        let service = HESectoriumService(paths: HESectoriumPaths(root: root.appendingPathComponent("support")),
            backend: WorkbenchAdoptionBackend(observation: observation), store: store,
            operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(HESectoriumPaths(root: root.appendingPathComponent("support"))),
            runner: runner, identityPolicy: identity,
            sectoriumDeviceObserver: WorkbenchFixtureObserver(device: device),
            portableDocumentWriter: WorkbenchPortableWriter())
        service.selectSectoriumDevice(device.id)

        let adoption = service.adoptDevelopmentDisk(deviceID: device.id, imageURL: image)
        #expect(adoption.succeeded, "\(String(describing: adoption.failure))")
        #expect(service.sectoriumProfiles().first?.imageFormat == "UDSB")
        #expect(service.sectoriumProfiles().first?.logicalCapacityBytes == (capacityAvailable ? 321_912_791_040 : nil))
        #expect(service.sectoriumProfiles().first?.filesystem == .apfs)
        #expect(service.sectoriumProfiles().first?.caseSensitive == false)
        let stopCheckpoint = try #require(service.prepareStopDevelopmentDiskConfirmation())
        let stop = service.stopDevelopmentDisk(checkpoint: stopCheckpoint, knownWritersClosed: true)
        #expect(stop.succeeded, "\(String(describing: stop.failure))")
        #expect(runner.imageInventory?.isEmpty == true)
        #expect(store.value.workbenchOperation == nil)
        #expect(runner.commands.contains { $0.first == "/usr/sbin/lsof" })
        #expect(!runner.commands.contains { $0.first == "/usr/sbin/diskutil" && $0.dropFirst().first == "eject" && $0.contains("/dev/\(device.bsdName)") })

        let start = service.startDevelopmentDisk()
        #expect(start.succeeded, "\(String(describing: start.failure))")
        #expect(runner.imageInventory?.first?["image-path"] as? String == image.path)
        #expect(service.sectoriumProfiles().first?.validation == .validated)
        #expect(runner.commands.filter { $0.first == "/usr/bin/hdiutil" && $0.contains("attach") }.count == 1)
    }

    @Test("Generic detached sparsebundle adoption records only verified identity and never attaches")
    func adoptsGenericDetachedSparsebundleWithoutAttaching() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let image = fixture.mount.appendingPathComponent("Project-Data.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
        fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")

        let result = fixture.service.adoptDevelopmentDisk(deviceID: fixture.device.id, imageURL: image)

        #expect(result.succeeded, "\(String(describing: result.failure))")
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        #expect(profile.name == "Project-Data")
        #expect(profile.imagePath == image.path)
        #expect(profile.backingVolumeUUID == fixture.service.coreController.identityPolicy.outerUUID)
        #expect(profile.devMountPoint == fixture.mount.appendingPathComponent(".AUV-Sectorium-Mounts/" + profile.id).path)
        #expect(profile.encrypted == false)
        #expect(profile.devUUID == nil)
        #expect(profile.validation == .pendingValidation)
        #expect(!fixture.runner.commands.contains { $0.contains("attach") || $0.contains("create") })
        #expect(fixture.store.value.workbenchOperation == nil)
    }

    @Test("Generic detached adoption completes isolated Start Stop Start lifecycle")
    func genericDetachedAdoptionStartStopStartLifecycle() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let archivedPhysicalID = UUID().uuidString
        let archivedTopology = WholeDeviceTopology(physicalIdentity: archivedPhysicalID, bsdName: "disk91",
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(UUID().uuidString.lowercased())|disk91s1", mounted: true)], images: [])
        let archivedJournal = WholeDeviceEjectJournalRecord(operationID: "completed-other-device",
            target: archivedTopology, phase: .verifiedAbsent, completedSteps: ["ejectWholeDevice"])
        let encodedArchive = try JSONEncoder().encode(archivedJournal).base64EncodedString()
        fixture.store.value = StoragePersistentState(ejectIntent: false,
            terminalEjectJournals: [archivedPhysicalID: encodedArchive])
        #expect(fixture.service.pendingSectoriumOperation() == nil)
        #expect(fixture.service.sectoriumReadiness(deviceID: fixture.device.id,
            devices: [fixture.device], profiles: []) != .operationInProgress("eject:completed-other-device"))
        let image = fixture.mount.appendingPathComponent("Lifecycle.sparsebundle", isDirectory: true)
        let devMount = fixture.root.appendingPathComponent("isolated-apfs-mount", isDirectory: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: devMount, withIntermediateDirectories: false)
        fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.attachOutcome = .success
        fixture.runner.occupancyIsClear = true
        fixture.runner.ejectAfterUnmountEnabled = true

        let volumeID = UUID()
        let attached = [["image-path": image.path, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk30"],
            ["mount-point": devMount.path, "volume-uuid": volumeID.uuidString, "dev-entry": "/dev/disk31s1"]
        ]]]
        fixture.runner.attachedImageInventory = attached
        fixture.runner.additionalDiskInfos = [
            "/dev/disk81s1": ["VolumeUUID": fixture.service.coreController.identityPolicy.outerUUID.uuidString,
                "MountPoint": fixture.mount.path, "FilesystemType": "ExFAT", "WritableVolume": true,
                "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81"],
            "/dev/disk81": ["DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical"],
            devMount.path: ["VolumeUUID": volumeID.uuidString, "MountPoint": devMount.path,
                "FilesystemType": "APFS", "WritableVolume": true, "VolumeName": "Lifecycle Data",
                "DeviceIdentifier": "disk31s1", "APFSContainerReference": "disk31"],
            "/dev/disk31s1": ["VolumeUUID": volumeID.uuidString, "MountPoint": devMount.path,
                "FilesystemType": "APFS", "WritableVolume": true, "VolumeName": "Lifecycle Data",
                "DeviceIdentifier": "disk31s1", "APFSContainerReference": "disk31"]
        ]
        fixture.runner.detachedDiskInfos[devMount.path] = [
            "VolumeUUID": fixture.service.coreController.identityPolicy.outerUUID.uuidString,
            "MountPoint": fixture.mount.path, "FilesystemType": "ExFAT", "WritableVolume": true,
            "VolumeName": "Fixture HE", "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81"
        ]
        fixture.runner.apfsContainers = [["ContainerReference": "disk31",
            "PhysicalStores": [["DeviceIdentifier": "disk30"]],
            "Volumes": [["APFSVolumeUUID": volumeID.uuidString, "DeviceIdentifier": "disk31s1"]]]]

        let adoption = fixture.service.adoptDevelopmentDisk(deviceID: fixture.device.id, imageURL: image)
        #expect(adoption.succeeded, "\(String(describing: adoption.failure))")
        #expect(fixture.runner.imageInventory?.isEmpty == true)

        let registry = HESectoriumPaths(root: fixture.root.appendingPathComponent("support")).sectoriumProfiles
        var profiles = try JSONDecoder().decode([SectoriumDevelopmentProfile].self, from: Data(contentsOf: registry))
        var profile = try #require(profiles.first)
        profile.devMountPoint = devMount.path
        profiles[0] = profile
        try JSONEncoder().encode(profiles).write(to: registry, options: .atomic)

        let firstStart = fixture.service.startDevelopmentDisk()
        #expect(firstStart.succeeded, "\(String(describing: firstStart.failure))")
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.terminalEjectJournals[archivedPhysicalID] == encodedArchive)
        #expect(fixture.runner.imageInventory?.first?["image-path"] as? String == image.path)
        #expect(fixture.service.sectoriumProfiles().first?.devUUID == volumeID)

        let stopCheckpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation())
        let stop = fixture.service.stopDevelopmentDisk(checkpoint: stopCheckpoint, knownWritersClosed: true)
        #expect(stop.succeeded, "\(String(describing: stop.failure))")
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.suppressedProfileIDs.contains(profile.id))
        #expect(fixture.runner.imageInventory?.isEmpty == true)
        #expect(fixture.runner.commands.contains { $0.first == "/usr/sbin/lsof" })
        #expect(!fixture.runner.commands.contains { $0.first == "/usr/sbin/diskutil" && $0.dropFirst().first == "eject" && $0.contains("/dev/\(fixture.device.bsdName)") })

        let secondStart = fixture.service.startDevelopmentDisk()
        #expect(secondStart.succeeded, "\(String(describing: secondStart.failure))")
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.terminalEjectJournals[archivedPhysicalID] == encodedArchive)
        #expect(fixture.runner.imageInventory?.first?["image-path"] as? String == image.path)
        #expect(fixture.runner.commands.filter { $0.first == "/usr/bin/hdiutil" && $0.contains("attach") }.count == 2)
        #expect(!fixture.store.value.suppressedProfileIDs.contains(profile.id))
        let reused = fixture.service.startDevelopmentDisk()
        #expect(reused.succeeded, "\(String(describing: reused.failure))")
        #expect(reused.steps.contains { $0.step == "reuseVerifiedImage" && $0.status == .succeeded })
        #expect(fixture.runner.commands.filter { $0.first == "/usr/bin/hdiutil" && $0.contains("attach") }.count == 2)
        #expect(!fixture.runner.commands.contains { $0.first == "/usr/sbin/lsof" && $0.contains("/Volumes") })
    }

    @Test("Generic adoption rejects unknown and duplicate hdiutil image identities")
    func genericAdoptionRejectsUnknownOrDuplicateImageInventory() throws {
        for inventory: [[String: Any]]? in [nil, [["image-path": "placeholder"], ["image-path": "placeholder"]]] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let image = fixture.mount.appendingPathComponent("Ambiguous.sparsebundle", isDirectory: true)
            try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
            fixture.runner.imageInventory = inventory
            if inventory != nil {
                fixture.runner.imageInventory = [["image-path": image.path], ["image-path": image.path]]
            }

            let result = fixture.service.adoptDevelopmentDisk(deviceID: fixture.device.id, imageURL: image)

            #expect(!result.succeeded)
            #expect(fixture.service.sectoriumProfiles().isEmpty)
            #expect(fixture.store.value.workbenchOperation != nil)
            #expect(!fixture.runner.commands.contains { $0.contains("attach") || $0.contains("create") })
        }
    }

    @Test("Adoption preserves an observed APFS name and mount point for an authorized local location")
    func adoptsLocalImageWithObservedVolumeIdentity() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let image = fixture.mount.appendingPathComponent("Workspace.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false)
        let actualMount = fixture.root.appendingPathComponent("mounted-as-existing-name", isDirectory: true).path
        let devUUID = UUID()
        fixture.runner.imageInventory = [["image-path": image.path, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk30"],
            ["mount-point": actualMount, "volume-uuid": devUUID.uuidString, "dev-entry": "/dev/disk31s1"]
        ]]]
        fixture.runner.additionalDiskInfos = [
            "/dev/disk81s1": ["VolumeUUID": fixture.service.coreController.identityPolicy.outerUUID.uuidString,
                "MountPoint": fixture.mount.path, "FilesystemType": "ExFAT", "WritableVolume": true,
                "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81"],
            "/dev/disk81": ["DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical"],
            actualMount: ["VolumeUUID": devUUID.uuidString, "MountPoint": actualMount,
                "FilesystemType": "APFS", "WritableVolume": true, "VolumeName": "Actual APFS Name",
                "DeviceIdentifier": "disk31s1", "APFSContainerReference": "disk31"],
            "/dev/disk31s1": ["VolumeUUID": devUUID.uuidString, "MountPoint": actualMount,
                "FilesystemType": "APFS", "WritableVolume": true, "VolumeName": "Actual APFS Name",
                "DeviceIdentifier": "disk31s1", "APFSContainerReference": "disk31"]
        ]
        fixture.runner.apfsContainers = [["ContainerReference": "disk31",
            "PhysicalStores": [["DeviceIdentifier": "disk30"]],
            "Volumes": [["APFSVolumeUUID": devUUID.uuidString, "DeviceIdentifier": "disk31s1"]]]]
        let localDevice = SectoriumPhysicalDevice(id: fixture.device.id, bsdName: fixture.device.bsdName,
            name: fixture.device.name, isExternal: false, identityVerified: true,
            wholeDeviceBytes: fixture.device.wholeDeviceBytes, mountedVolumePaths: fixture.device.mountedVolumePaths,
            volumeUUIDs: fixture.device.volumeUUIDs, readBytes: fixture.device.readBytes,
            writtenBytes: fixture.device.writtenBytes)
        let localService = HESectoriumService(paths: HESectoriumPaths(root: fixture.root.appendingPathComponent("local-support")),
            backend: WorkbenchNoopBackend(), store: WorkbenchMemoryStore(), operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(HESectoriumPaths(root: fixture.root.appendingPathComponent("local-support"))),
            runner: fixture.runner, identityPolicy: fixture.service.coreController.identityPolicy,
            sectoriumDeviceObserver: WorkbenchFixtureObserver(device: localDevice),
            portableDocumentWriter: WorkbenchPortableWriter())
        localService.selectSectoriumDevice(localDevice.id)

        let result = localService.adoptDevelopmentDisk(deviceID: localDevice.id, imageURL: image)

        #expect(result.succeeded, "\(String(describing: result.failure))")
        let profile = try #require(localService.sectoriumProfiles().first)
        #expect(profile.name == "Workspace")
        #expect(profile.devVolumeName == "Actual APFS Name")
        #expect(profile.devMountPoint == actualMount)
        #expect(profile.devUUID == devUUID)
        #expect(!fixture.runner.commands.contains { $0.contains("attach") || $0.contains("create") })
    }

    @Test("Generic sparsebundle adoption is distinct from a mismatched configured legacy chain")
    func genericAdoptionAndLegacyChainMismatchAreDistinguished() throws {
        let requestedRoot = URL(fileURLWithPath: "/private/tmp/sectorium-legacy-reject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: false)
        let root = requestedRoot.resolvingSymlinksInPath()
        let outer = root.appendingPathComponent("HE", isDirectory: true)
        let dev = outer.appendingPathComponent("DEV", isDirectory: true)
        let image = outer.appendingPathComponent(".DEV-APFS.sparsebundle", isDirectory: true)
        let wrongImage = outer.appendingPathComponent("Other.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wrongImage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: requestedRoot) }
        let outerID = UUID(), devID = UUID(), mediaID = UUID()
        let policy = StorageIdentityPolicy(outerUUID: outerID, devUUID: devID, outerMountPoint: outer.path,
            devMountPoint: dev.path, devVolumeName: "DEV_APFS", imagePath: image.path)
        let device = SectoriumPhysicalDevice(id: mediaID.uuidString, bsdName: "disk92", name: "Fixture HE",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [outer.path],
            volumeUUIDs: [outerID], readBytes: nil, writtenBytes: nil)
        let observation = StorageObservation(
            outer: .init(uuid: outerID, mountPoint: outer.path, fileSystem: "ExFAT", writable: true,
                         name: "HE", rootMatchesExpected: true),
            dev: .init(uuid: devID, mountPoint: dev.path, fileSystem: "APFS", writable: true,
                       name: "DEV_APFS", rootMatchesExpected: true),
            image: .init(backingVolumeUUID: outerID, attachedVolumeUUID: devID, path: image.path))
        let runner = WorkbenchFixtureRunner(mountPoint: outer.path, volumeUUID: outerID)
        let store = WorkbenchMemoryStore()
        let wrongPathService = HESectoriumService(paths: HESectoriumPaths(root: root.appendingPathComponent("wrong-path-support")),
            backend: WorkbenchAdoptionBackend(observation: observation), store: store,
            operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(HESectoriumPaths(root: root.appendingPathComponent("wrong-path-support"))),
            runner: runner, identityPolicy: policy,
            sectoriumDeviceObserver: WorkbenchFixtureObserver(device: device),
            portableDocumentWriter: WorkbenchPortableWriter())
        wrongPathService.selectSectoriumDevice(device.id)
        runner.imageInventory = []
        #expect(wrongPathService.adoptDevelopmentDisk(deviceID: device.id, imageURL: wrongImage).succeeded)
        #expect(wrongPathService.sectoriumProfiles().first?.name == "Other")
        #expect(wrongPathService.sectoriumProfiles().first?.imagePath == wrongImage.path)

        let wrongChain = StorageObservation(outer: observation.outer, dev: observation.dev,
            image: .init(backingVolumeUUID: UUID(), attachedVolumeUUID: devID, path: image.path))
        runner.imageInventory = [["image-path": image.path]]
        let wrongChainCommandStart = runner.commands.count
        let wrongChainService = HESectoriumService(paths: HESectoriumPaths(root: root.appendingPathComponent("wrong-chain-support")),
            backend: WorkbenchAdoptionBackend(observation: wrongChain), store: WorkbenchMemoryStore(),
            operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(HESectoriumPaths(root: root.appendingPathComponent("wrong-chain-support"))),
            runner: runner, identityPolicy: policy,
            sectoriumDeviceObserver: WorkbenchFixtureObserver(device: device),
            portableDocumentWriter: WorkbenchPortableWriter())
        wrongChainService.selectSectoriumDevice(device.id)
        #expect(!wrongChainService.adoptDevelopmentDisk(deviceID: device.id, imageURL: image).succeeded)
        #expect(wrongChainService.sectoriumProfiles().isEmpty)
        #expect(!runner.commands.dropFirst(wrongChainCommandStart).contains {
            $0.first == "/usr/bin/hdiutil" && $0.dropFirst().first == "imageinfo"
        })
    }

    @Test("Existing concrete profile facts decode while newly unknown facts stay nil")
    func profileImageFactsRemainBackwardCompatible() throws {
        let known = SectoriumDevelopmentProfile(name: "Old", deviceID: "disk1", backingVolumeUUID: UUID(),
            backingMountPoint: "/Volumes/HE", imagePath: "/Volumes/HE/Old.sparsebundle",
            devVolumeName: "Old", devMountPoint: "/Volumes/Old-DEV", encrypted: false,
            caseSensitive: true, logicalCapacityBytes: 4096, imageFormat: "UDSB", validation: .validated)
        let decodedKnown = try JSONDecoder().decode(SectoriumDevelopmentProfile.self, from: JSONEncoder().encode(known))
        #expect(decodedKnown.encrypted == false)
        #expect(decodedKnown.caseSensitive == true)
        #expect(decodedKnown.logicalCapacityBytes == 4096)
        #expect(decodedKnown.imageFormat == "UDSB")
        #expect(decodedKnown.hasVerifiedImageMetadata)

        let unknown = SectoriumDevelopmentProfile(name: "DEV_APFS", deviceID: "disk2", backingVolumeUUID: UUID(),
            backingMountPoint: "/Volumes/HE", imagePath: "/Volumes/HE/.DEV-APFS.sparsebundle",
            devVolumeName: "DEV_APFS", devMountPoint: "/Volumes/HE/DEV", encrypted: nil,
            caseSensitive: nil, logicalCapacityBytes: nil)
        let decodedUnknown = try JSONDecoder().decode(SectoriumDevelopmentProfile.self, from: JSONEncoder().encode(unknown))
        #expect(decodedUnknown.encrypted == nil)
        #expect(decodedUnknown.caseSensitive == nil)
        #expect(decodedUnknown.logicalCapacityBytes == nil)
        #expect(decodedUnknown.imageFormat == nil)
        #expect(!decodedUnknown.hasVerifiedImageMetadata)

        var legacyObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(known)) as? [String: Any])
        legacyObject.removeValue(forKey: "imageFormat")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let decodedLegacy = try JSONDecoder().decode(SectoriumDevelopmentProfile.self, from: legacyData)
        #expect(decodedLegacy.imageFormat == nil)
        #expect(!decodedLegacy.hasVerifiedImageMetadata)
    }

    @Test("Encryption observation accepts one documented result and rejects ambiguity")
    func documentedEncryptionObservationIsUnambiguous() {
        #expect(MacStorageBackend.documentedEncryptionState("encrypted: YES\nversion: 2\n") == true)
        #expect(MacStorageBackend.documentedEncryptionState("encrypted: no\n") == false)
        #expect(MacStorageBackend.documentedEncryptionState("encrypted: MAYBE\n") == nil)
        #expect(MacStorageBackend.documentedEncryptionState("encrypted: NO\nencrypted: MAYBE\n") == nil)
        #expect(MacStorageBackend.documentedEncryptionState("encrypted: yes\nencrypted: no\n") == nil)
        #expect(MacStorageBackend.documentedEncryptionState("not encrypted\n") == nil)
    }

    @Test("Pending workbench intent survives a fresh service read and empty profiles are distinct")
    func durableWorkbenchStateIsObservable() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.store.value = StoragePersistentState(ejectIntent: false, workbenchOperation: "start:interrupted")

        #expect(fixture.service.pendingSectoriumOperation() == "start:interrupted")
        #expect(fixture.service.sectoriumReadiness(deviceID: fixture.device.id,
            devices: [fixture.device], profiles: []) == .operationInProgress("start:interrupted"))
    }

    @Test("Readiness requires explicit selection when a device has multiple profiles")
    func readinessRequiresExplicitProfileWhenSeveralExist() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = SectoriumDevelopmentProfile(name: "First", deviceID: fixture.device.id,
            backingVolumeUUID: UUID(), backingMountPoint: "/Volumes/HE", imagePath: "/Volumes/HE/First.sparsebundle",
            devVolumeName: "First", devMountPoint: "/Volumes/First-DEV", encrypted: false,
            caseSensitive: false, logicalCapacityBytes: 1024, imageFormat: "UDSB")
        let second = SectoriumDevelopmentProfile(name: "Second", deviceID: fixture.device.id,
            backingVolumeUUID: UUID(), backingMountPoint: "/Volumes/HE", imagePath: "/Volumes/HE/Second.sparsebundle",
            devVolumeName: "Second", devMountPoint: "/Volumes/Second-DEV", encrypted: false,
            caseSensitive: false, logicalCapacityBytes: 2048, imageFormat: "UDSB")
        #expect(fixture.service.sectoriumReadiness(deviceID: fixture.device.id, devices: [fixture.device],
            profiles: [first, second]) == .unknown("Select a development profile to verify readiness"))
        #expect(fixture.service.sectoriumReadiness(deviceID: fixture.device.id, selectedProfileID: second.id,
            devices: [fixture.device], profiles: [first, second]) != .unknown("Select a development profile to verify readiness"))
    }

    @Test("Validation-only rejection remains durable until explicit matching recovery")
    func validationRejectionCanBeSafelyResolvedWithoutMutation() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let rejected = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 0,
            caseSensitive: false, password: nil)

        #expect(!rejected.succeeded)
        #expect(fixture.store.value.workbenchOperation != nil)
        #expect(fixture.store.value.workbenchPhase == "validation-rejected")
        #expect(fixture.store.value.workbenchCompletedStep == nil)
        #expect(fixture.store.value.workbenchTerminalResult != nil)
        #expect(fixture.runner.commands.isEmpty)

        let recovery = fixture.service.resumePendingSectoriumOperation()
        #expect(recovery.succeeded)
        #expect(recovery.steps.map(\.step) == ["resolveValidationRejection"])
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.workbenchPhase == "validation-rejection-resolved")
        #expect(fixture.store.value.workbenchTerminalResult != nil)
        #expect(fixture.runner.commands.isEmpty)
    }

    @Test("A fresh service resolves a durable validation-only rejection without replaying storage commands")
    func durableValidationRejectionSurvivesFreshService() throws {
        let requestedRoot = URL(fileURLWithPath: "/private/tmp/sectorium-fresh-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: false)
        let root = requestedRoot.resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: requestedRoot) }
        let mount = root.appendingPathComponent("mounted-volume", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false)
        let volumeID = UUID(), mediaID = UUID()
        let device = SectoriumPhysicalDevice(id: mediaID.uuidString, bsdName: "disk83", name: "Fixture Drive",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [mount.path],
            volumeUUIDs: [volumeID], readBytes: nil, writtenBytes: nil)
        let runner = WorkbenchFixtureRunner(mountPoint: mount.path, volumeUUID: volumeID)
        let paths = HESectoriumPaths(root: root.appendingPathComponent("support"))
        let policy = StorageIdentityPolicy(outerUUID: volumeID, devUUID: UUID(), outerMountPoint: mount.path,
            devMountPoint: "/Volumes/Fixture-DEV", devVolumeName: "Fixture-DEV",
            imagePath: mount.appendingPathComponent("Fixture.sparsebundle").path)
        let firstStore = JSONStateStore(url: paths.state)
        let firstService = HESectoriumService(paths: paths, backend: WorkbenchNoopBackend(), store: firstStore,
            operationLock: WorkbenchMemoryLock(), installer: workbenchFixtureInstaller(paths),
            runner: runner, identityPolicy: policy,
            sectoriumDeviceObserver: WorkbenchFixtureObserver(device: device),
            portableDocumentWriter: WorkbenchPortableWriter())
        firstService.selectSectoriumDevice(device.id)

        let rejected = firstService.createDevelopmentDisk(deviceID: device.id, parentDirectory: mount,
            name: "Invalid", capacityGiB: 0, caseSensitive: false, password: nil)
        #expect(!rejected.succeeded)
        #expect(try firstStore.load().workbenchPhase == "validation-rejected")
        #expect(runner.commands.isEmpty)

        let freshStore = JSONStateStore(url: paths.state)
        let freshService = HESectoriumService(paths: paths, backend: WorkbenchNoopBackend(), store: freshStore,
            operationLock: WorkbenchMemoryLock(), installer: workbenchFixtureInstaller(paths),
            runner: runner, identityPolicy: policy,
            sectoriumDeviceObserver: WorkbenchFixtureObserver(device: device),
            portableDocumentWriter: WorkbenchPortableWriter())
        #expect(freshService.pendingSectoriumOperation() != nil)
        let recovered = freshService.resumePendingSectoriumOperation()
        #expect(recovered.succeeded)
        #expect(recovered.steps.map(\.step) == ["resolveValidationRejection"])
        #expect(try freshStore.load().workbenchOperation == nil)
        #expect(runner.commands.isEmpty)
    }

    @Test("Generic recovery never attaches or clears a pending eject intent")
    func genericRecoveryNeverContinuesEject() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.store.value = StoragePersistentState(revision: 4, ejectIntent: true,
            operationID: "eject-operation", workbenchOperation: "eject:eject-operation",
            workbenchPhase: "mutating:detachImage", workbenchTarget: fixture.device.id,
            workbenchCompletedStep: "unmountDEV")

        let result = fixture.service.resumePendingSectoriumOperation()

        guard case .workbenchFailed(let message) = result.failure else {
            Issue.record("Expected pending eject recovery to fail closed")
            return
        }
        #expect(message.contains("generic workbench recovery route"))
        #expect(fixture.store.value.ejectIntent)
        #expect(fixture.store.value.workbenchOperation == "eject:eject-operation")
        #expect(fixture.store.value.workbenchPhase == "mutating:detachImage")
        #expect(fixture.runner.commands.isEmpty)
    }

    @Test("Fresh explicit recovery atomically cancels only validation-phase eject markers")
    func validationPhaseEjectCanBeCancelledWithoutMutation() throws {
        for target in [nil, "known"] as [String?] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            if target != nil {
                #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
                    parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
                    caseSensitive: false, password: nil).succeeded)
            }
            let operation = UUID().uuidString
            fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
                ejectIntent: false, operationID: nil, workbenchOperation: "eject:\(operation)",
                workbenchPhase: "validating", workbenchTarget: target == nil ? nil : fixture.device.id)
            let commandCount = fixture.runner.commands.count

            let recovered = fixture.service.resumePendingSectoriumOperation()

            #expect(recovered.succeeded, "target=\(String(describing: target)), failure=\(String(describing: recovered.failure))")
            #expect(recovered.steps.map(\.step) == ["cancelUncommittedEject"])
            #expect(fixture.store.value.workbenchOperation == nil)
            #expect(fixture.store.value.workbenchPhase == "pre-intent-eject-cancelled")
            #expect(fixture.store.value.ejectIntent == false)
            #expect(fixture.runner.commands.dropFirst(commandCount).allSatisfy { command in
                !command.contains("attach") && !command.contains("unmount") && !command.contains("eject")
            })
        }
    }

    @Test("Explicit Return cancels a nil-target validation marker without issuing storage commands")
    func returnCancelsNilTargetValidationPhaseEject() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.store.value = StoragePersistentState(revision: 1, ejectIntent: false,
            workbenchOperation: "eject:\(UUID().uuidString)", workbenchPhase: "validating")

        let returned = fixture.service.returnToDevelopment()

        #expect(returned.succeeded)
        #expect(returned.steps.map(\.step) == ["cancelUncommittedEject"])
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.ejectIntent == false)
        #expect(fixture.runner.commands.isEmpty)
    }

    @Test("Validation-phase eject cancellation preserves contradictory and drifted markers")
    func validationPhaseEjectCancellationRejectsContradictoryState() throws {
        for state in [
            StoragePersistentState(revision: 1, ejectIntent: false, operationID: "unexpected",
                workbenchOperation: "eject:\(UUID().uuidString)", workbenchPhase: "validating"),
            StoragePersistentState(revision: 1, ejectIntent: false,
                workbenchOperation: "eject:\(UUID().uuidString)", workbenchPhase: "validating",
                workbenchTarget: "disk-not-the-selected-device"),
            StoragePersistentState(revision: 1, ejectIntent: false,
                workbenchOperation: "eject:\(UUID().uuidString)", workbenchPhase: "validating",
                workbenchCompletedStep: "flush"),
            StoragePersistentState(revision: 1, ejectIntent: false,
                workbenchOperation: "eject:\(UUID().uuidString)", workbenchPhase: "mutating:flush")
        ] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
                parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
                caseSensitive: false, password: nil).succeeded)
            fixture.store.value = state
            let before = fixture.store.value
            let commands = fixture.runner.commands.count

            let result = fixture.service.returnToDevelopment()

            #expect(!result.succeeded)
            #expect(fixture.store.value == before)
            #expect(fixture.runner.commands.dropFirst(commands).allSatisfy { command in
                command.first == "/usr/sbin/diskutil" && command.dropFirst().first == "info"
            }, "Refusal may recheck identity but must not mutate storage")
        }
    }

    @Test("Explicit return-to-development revalidates the eject target and keeps intent on unknown observation")
    func returnToDevelopmentRequiresFreshObservation() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let created = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil)
        #expect(created.succeeded)
        let beforeReturn = fixture.runner.commands.count
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: true, operationID: "eject-operation", workbenchOperation: "eject:eject-operation",
            workbenchPhase: "mutating:detachImage", workbenchTarget: fixture.device.id,
            workbenchCompletedStep: "unmountDEV")

        let returned = fixture.service.returnToDevelopment()

        #expect(!returned.succeeded)
        #expect(fixture.store.value.ejectIntent)
        #expect(fixture.store.value.workbenchOperation == "eject:eject-operation")
        #expect(fixture.runner.commands.dropFirst(beforeReturn).allSatisfy { !$0.contains("attach") })
    }

    @Test("Return resolves only an exact pre-intent eject boundary after fresh mounted-chain validation")
    func resolvesUncommittedEjectIntentAtExactBoundary() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let created = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil)
        #expect(created.succeeded)
        let createdProfile = try #require(fixture.service.sectoriumProfiles().first)
        let devUUID = UUID()
        let profile = SectoriumDevelopmentProfile(id: createdProfile.id, name: createdProfile.name,
            deviceID: createdProfile.deviceID, backingVolumeUUID: createdProfile.backingVolumeUUID,
            backingMountPoint: createdProfile.backingMountPoint, imagePath: createdProfile.imagePath,
            devVolumeName: createdProfile.devVolumeName, devMountPoint: createdProfile.devMountPoint,
            devUUID: devUUID, encrypted: createdProfile.encrypted, caseSensitive: createdProfile.caseSensitive,
            logicalCapacityBytes: createdProfile.logicalCapacityBytes, imageFormat: createdProfile.imageFormat,
            validation: createdProfile.validation)
        let profileData = try JSONEncoder().encode([profile])
        try profileData.write(to: fixture.root.appendingPathComponent("support/sectorium-profiles.json"), options: .atomic)
        fixture.runner.imageInventory = [["image-path": profile.imagePath, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk30"],
            ["mount-point": profile.devMountPoint, "volume-uuid": devUUID.uuidString, "dev-entry": "/dev/disk31s1"]
        ]]]
        fixture.runner.additionalDiskInfos = [
            "/dev/disk81s1": ["VolumeUUID": profile.backingVolumeUUID.uuidString, "MountPoint": fixture.mount.path,
                               "FilesystemType": "ExFAT", "WritableVolume": true, "DeviceIdentifier": "disk81s1",
                               "PartOfWhole": "disk81"],
            "/dev/disk81": ["DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical"],
            profile.devMountPoint: ["VolumeUUID": devUUID.uuidString, "MountPoint": profile.devMountPoint,
                                    "FilesystemType": "APFS", "WritableVolume": true, "VolumeName": profile.devVolumeName,
                                    "DeviceIdentifier": "disk31s1",
                                    "APFSContainerReference": "disk31"],
            "/dev/disk31s1": ["VolumeUUID": devUUID.uuidString, "MountPoint": profile.devMountPoint,
                               "FilesystemType": "APFS", "WritableVolume": true, "VolumeName": profile.devVolumeName,
                               "DeviceIdentifier": "disk31s1",
                               "APFSContainerReference": "disk31"]
        ]
        fixture.runner.apfsContainers = [["ContainerReference": "disk31", "PhysicalStores": [["DeviceIdentifier": "disk30"]],
                                         "Volumes": [["APFSVolumeUUID": devUUID.uuidString, "DeviceIdentifier": "disk31s1"]]]]
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: false, operationID: "eject-operation", workbenchOperation: "eject:eject-operation",
            workbenchPhase: "mutating:persistEjectIntent", workbenchTarget: fixture.device.id)

        let exactInventory = try #require(fixture.runner.imageInventory)
        let conflictingImage: [String: Any] = ["image-path": profile.imagePath, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk30"],
            ["mount-point": profile.devMountPoint, "volume-uuid": UUID().uuidString, "dev-entry": "/dev/disk99s1"]
        ]]
        for inventory in [exactInventory + [conflictingImage], [conflictingImage] + exactInventory] {
            fixture.runner.imageInventory = inventory
            let ambiguous = fixture.service.returnToDevelopment()
            #expect(!ambiguous.succeeded, "Duplicate image-path records must be rejected regardless of order")
            #expect(fixture.store.value.workbenchOperation == "eject:eject-operation")
            #expect(fixture.store.value.workbenchPhase == "mutating:persistEjectIntent")
            #expect(fixture.runner.commands.allSatisfy { command in
                !command.contains("attach") && !command.contains("unmount") && !command.contains("eject")
            })
        }
        fixture.runner.imageInventory = exactInventory

        let recovered = fixture.service.returnToDevelopment()

        #expect(recovered.succeeded, "\(String(describing: recovered.failure)); commands=\(fixture.runner.commands)")
        #expect(recovered.steps.map(\.step) == ["verifyUncommittedEjectTarget", "validateMountedChain", "resolveUncommittedEjectIntent"])
        #expect(fixture.store.value.ejectIntent == false)
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.runner.commands.allSatisfy { command in
            !command.contains("attach") && !command.contains("unmount") && !command.contains("eject")
        })
    }

    @Test("Return preserves an eject marker outside the exact pre-intent recovery boundary")
    func mismatchedUncommittedEjectBoundaryRetainsMarker() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let created = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil)
        #expect(created.succeeded)
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: false, operationID: "eject-operation", workbenchOperation: "eject:eject-operation",
            workbenchPhase: "mutating:flush", workbenchTarget: fixture.device.id)
        let commandsBeforeReturn = fixture.runner.commands.count

        let returned = fixture.service.returnToDevelopment()

        #expect(!returned.succeeded)
        #expect(fixture.store.value.workbenchOperation == "eject:eject-operation")
        #expect(fixture.store.value.workbenchPhase == "mutating:flush")
        #expect(fixture.runner.commands.count == commandsBeforeReturn)
    }

    @Test("Pre-intent eject recovery refuses missing profiles, target drift, and stale backing identity")
    func uncommittedEjectRecoveryRequiresExactSavedProfileAndTarget() throws {
        let noProfileFixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: noProfileFixture.root) }
        noProfileFixture.store.value = StoragePersistentState(revision: 1, ejectIntent: false,
            operationID: "eject-operation", workbenchOperation: "eject:eject-operation",
            workbenchPhase: "mutating:persistEjectIntent", workbenchTarget: noProfileFixture.device.id)
        let noProfile = noProfileFixture.service.returnToDevelopment()
        #expect(!noProfile.succeeded)
        #expect(noProfileFixture.store.value.workbenchOperation == "eject:eject-operation")
        #expect(noProfileFixture.runner.commands.isEmpty)

        for mismatch in ["target", "backing"] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
                parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
                caseSensitive: false, password: nil).succeeded)
            if mismatch == "backing" {
                let original = try #require(fixture.service.sectoriumProfiles().first)
                let stale = SectoriumDevelopmentProfile(id: original.id, name: original.name,
                    deviceID: original.deviceID, backingVolumeUUID: UUID(),
                    backingMountPoint: original.backingMountPoint, imagePath: original.imagePath,
                    devVolumeName: original.devVolumeName, devMountPoint: original.devMountPoint,
                    devUUID: original.devUUID, encrypted: original.encrypted,
                    caseSensitive: original.caseSensitive, logicalCapacityBytes: original.logicalCapacityBytes,
                    imageFormat: original.imageFormat, validation: original.validation)
                try JSONEncoder().encode([stale]).write(to: fixture.root.appendingPathComponent("support/sectorium-profiles.json"), options: .atomic)
            }
            fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
                ejectIntent: false, operationID: "eject-operation", workbenchOperation: "eject:eject-operation",
                workbenchPhase: "mutating:persistEjectIntent",
                workbenchTarget: mismatch == "target" ? "replacement-device" : fixture.device.id)
            let before = fixture.runner.commands.count

            let refused = fixture.service.returnToDevelopment()

            #expect(!refused.succeeded)
            #expect(fixture.store.value.workbenchOperation == "eject:eject-operation")
            #expect(fixture.runner.commands.dropFirst(before).allSatisfy { command in
                command.first == "/usr/sbin/diskutil" && command.dropFirst().first == "info"
            }, "Refusal may recheck identity but must not mutate storage")
        }
    }

    @Test("Pre-intent eject recovery keeps its marker when the mounted chain is unknown")
    func uncommittedEjectRecoveryRetainsUnknownMountedChain() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil).succeeded)
        fixture.runner.imageInventory = []
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: false, operationID: "eject-operation", workbenchOperation: "eject:eject-operation",
            workbenchPhase: "mutating:persistEjectIntent", workbenchTarget: fixture.device.id)

        let returned = fixture.service.returnToDevelopment()

        #expect(!returned.succeeded)
        #expect(fixture.store.value.workbenchOperation == "eject:eject-operation")
        #expect(fixture.store.value.ejectIntent == false)
        #expect(fixture.runner.commands.allSatisfy { !$0.contains("attach") && !$0.contains("eject") })
    }

    @Test("Fresh recovery does not clear an interrupted start merely because the image is detached")
    func interruptedStartWithDetachedImageRetainsMarker() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let created = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil)
        #expect(created.succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        fixture.runner.imageInventory = []
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: false, operationID: "start-operation", workbenchOperation: "start:start-operation",
            workbenchPhase: "mutating:attachImage", workbenchTarget: profile.imagePath,
            workbenchCompletedStep: "prepareMountPoint")

        let recovered = fixture.service.resumePendingSectoriumOperation()

        #expect(!recovered.succeeded)
        #expect(fixture.store.value.workbenchOperation == "start:start-operation")
        #expect(fixture.store.value.workbenchPhase == "mutating:attachImage")
        #expect(fixture.store.value.workbenchCompletedStep == "prepareMountPoint")
        #expect(fixture.runner.commands.filter { $0.first == "/usr/bin/hdiutil" }.allSatisfy { !$0.contains("attach") })
    }

    @Test("Exact composite start validation is cancellable and legacy format registry mutation is reconcilable")
    func compositeStartAndImageFormatRecovery() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let otherBacking = fixture.root.appendingPathComponent("unrelated-backing")
        let other = SectoriumDevelopmentProfile(name: "Other", deviceID: UUID().uuidString,
            backingVolumeUUID: UUID(), backingMountPoint: otherBacking.path,
            imagePath: otherBacking.appendingPathComponent("Other.sparsebundle").path,
            devVolumeName: "Other", devMountPoint: fixture.root.appendingPathComponent("other-dev").path,
            encrypted: false, caseSensitive: false, logicalCapacityBytes: 1_073_741_824,
            imageFormat: "UDSB", validation: .validated)
        try JSONEncoder().encode([profile, other]).write(to: fixture.service.paths.sectoriumProfiles, options: .atomic)
        let target = "\(profile.deviceID):\(profile.imagePath)"
        let beforeCommands = fixture.runner.commands.count

        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: false, operationID: "start-validation", workbenchOperation: "start:start-validation",
            workbenchPhase: "validating", workbenchTarget: "other-device:\(profile.imagePath)")
        #expect(!fixture.service.resumePendingSectoriumOperation().succeeded)
        #expect(fixture.store.value.workbenchOperation == "start:start-validation")
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: false, operationID: "start-validation", workbenchOperation: "start:start-validation",
            workbenchPhase: "validating", workbenchTarget: target)
        let cancelled = fixture.service.resumePendingSectoriumOperation()
        #expect(cancelled.succeeded)
        #expect(cancelled.steps.contains { $0.step == "cancelUnmutatedStart" })
        #expect(fixture.store.value.workbenchOperation == nil)

        let legacy = SectoriumDevelopmentProfile(id: profile.id, name: profile.name,
            deviceID: profile.deviceID, backingVolumeUUID: profile.backingVolumeUUID,
            backingMountPoint: profile.backingMountPoint, imagePath: profile.imagePath,
            devVolumeName: profile.devVolumeName, devMountPoint: profile.devMountPoint,
            devUUID: profile.devUUID, encrypted: profile.encrypted,
            caseSensitive: profile.caseSensitive, logicalCapacityBytes: profile.logicalCapacityBytes,
            imageFormat: nil, validation: profile.validation)
        try JSONEncoder().encode([legacy, other]).write(to: fixture.service.paths.sectoriumProfiles, options: .atomic)
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: false, operationID: "start-format", workbenchOperation: "start:start-format",
            workbenchPhase: "mutating:saveImageFormat", workbenchTarget: target)
        let reconciled = fixture.service.resumePendingSectoriumOperation()
        #expect(reconciled.succeeded, "\(String(describing: reconciled.failure))")
        #expect(reconciled.steps.contains { $0.step == "reconcileImageFormat" })
        #expect(fixture.service.sectoriumProfiles().first(where: { $0.id == profile.id })?.imageFormat == "UDSB")
        #expect(fixture.store.value.workbenchOperation == nil)
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: false, operationID: "start-format-saved",
            workbenchOperation: "start:start-format-saved", workbenchPhase: "mutating",
            workbenchTarget: target, workbenchCompletedStep: "saveImageFormat")
        #expect(fixture.service.resumePendingSectoriumOperation().succeeded)
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(Array(fixture.runner.commands.dropFirst(beforeCommands)).allSatisfy { command in
            !command.contains("attach") && !command.contains("eject") && !command.contains("unmount")
        })
    }

    @Test("A fresh process recovers an exact registered backing-volume start without UI selection")
    func registeredBackingPendingStartRecoversHeadlessly() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil).succeeded)
        let created = try #require(fixture.service.sectoriumProfiles().first)
        let backing = created.backingVolumeUUID
        let anchored = SectoriumPhysicalDevice(id: backing.uuidString, bsdName: fixture.device.bsdName,
            name: fixture.device.name, isExternal: true, identityVerified: true,
            wholeDeviceBytes: fixture.device.wholeDeviceBytes,
            mountedVolumePaths: [fixture.mount.path], volumeUUIDs: [backing],
            readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: backing, bsdName: "disk81s1", mountPoint: fixture.mount.path)],
            topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
            wholeMediaUUID: nil, requiresFreshParentCheck: true)
        fixture.observer.device = anchored
        let legacy = SectoriumDevelopmentProfile(id: created.id, name: created.name,
            deviceID: anchored.id, backingVolumeUUID: backing,
            backingMountPoint: created.backingMountPoint, imagePath: created.imagePath,
            devVolumeName: created.devVolumeName, devMountPoint: created.devMountPoint,
            devUUID: created.devUUID, encrypted: created.encrypted,
            caseSensitive: created.caseSensitive, logicalCapacityBytes: created.logicalCapacityBytes,
            imageFormat: nil, validation: created.validation)
        let paths = fixture.service.paths
        try JSONEncoder().encode([legacy]).write(to: paths.sectoriumProfiles, options: .atomic)
        let durableStore = JSONStateStore(url: paths.state)
        let target = "\(anchored.id):\(legacy.imagePath)"
        func persist(_ operation: String, phase: String, target: String,
                     completedStep: String? = nil) throws {
            let previous = try durableStore.load()
            let pending = StoragePersistentState(revision: previous.revision + 1, ejectIntent: false,
                operationID: operation, workbenchOperation: "start:\(operation)",
                workbenchPhase: phase, workbenchTarget: target,
                workbenchCompletedStep: completedStep)
            #expect(try durableStore.compareAndSwap(expectedRevision: previous.revision, newState: pending))
        }
        func freshService() -> HESectoriumService {
            HESectoriumService(paths: paths, backend: WorkbenchNoopBackend(),
                store: JSONStateStore(url: paths.state), operationLock: WorkbenchMemoryLock(),
                installer: workbenchFixtureInstaller(paths), runner: fixture.runner,
                identityPolicy: fixture.service.coreController.identityPolicy,
                sectoriumDeviceObserver: fixture.observer,
                portableDocumentWriter: fixture.portableWriter)
        }
        let commandsBeforeRecovery = fixture.runner.commands.count

        try persist("wrong-target", phase: "validating", target: "unregistered:\(legacy.imagePath)")
        #expect(!freshService().resumePendingSectoriumOperation().succeeded)
        #expect(try durableStore.load().workbenchOperation == "start:wrong-target")

        try persist("validation", phase: "validating", target: target)
        fixture.runner.mountParentWholeDisk = "disk82"
        #expect(!freshService().resumePendingSectoriumOperation().succeeded)
        #expect(try durableStore.load().workbenchOperation == "start:validation")
        fixture.runner.mountParentWholeDisk = "disk81"
        let cancelled = freshService().resumePendingSectoriumOperation()
        #expect(cancelled.succeeded, "\(String(describing: cancelled.failure))")
        #expect(cancelled.steps.contains { $0.step == "cancelUnmutatedStart" })
        #expect(try durableStore.load().workbenchOperation == nil)

        try persist("format", phase: "mutating:saveImageFormat", target: target)
        let registryBeforeDrift = try Data(contentsOf: paths.sectoriumProfiles)
        fixture.runner.mountParentWholeDisk = "disk82"
        #expect(!freshService().resumePendingSectoriumOperation().succeeded)
        #expect(try durableStore.load().workbenchOperation == "start:format")
        #expect(try Data(contentsOf: paths.sectoriumProfiles) == registryBeforeDrift)
        fixture.runner.mountParentWholeDisk = "disk81"
        let reconciled = freshService().resumePendingSectoriumOperation()
        #expect(reconciled.succeeded, "\(String(describing: reconciled.failure))")
        #expect(reconciled.steps.contains { $0.step == "reconcileImageFormat" })
        #expect(freshService().sectoriumProfiles().first?.imageFormat == "UDSB")
        #expect(try durableStore.load().workbenchOperation == nil)

        try persist("format-saved", phase: "mutating", target: target,
                    completedStep: "saveImageFormat")
        #expect(freshService().resumePendingSectoriumOperation().succeeded)
        #expect(try durableStore.load().workbenchOperation == nil)
        #expect(Array(fixture.runner.commands.dropFirst(commandsBeforeRecovery)).allSatisfy { command in
            !command.contains("attach") && !command.contains("eject")
                && !command.contains("unmount") && !command.contains("create")
        })
    }

    @Test("Start records a durable registry boundary before upgrading a legacy image format")
    func startUpgradeJournalsImageFormatBeforeRegistrySave() throws {
        let fixture = try makeWorkbenchFixture(isolatedDevelopmentMount: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let isolatedDevMount = fixture.root.appendingPathComponent("isolated-dev-mount", isDirectory: true)
        let legacy = SectoriumDevelopmentProfile(id: profile.id, name: profile.name,
            deviceID: profile.deviceID, backingVolumeUUID: profile.backingVolumeUUID,
            backingMountPoint: profile.backingMountPoint, imagePath: profile.imagePath,
            devVolumeName: profile.devVolumeName, devMountPoint: isolatedDevMount.path,
            devUUID: profile.devUUID, encrypted: profile.encrypted,
            caseSensitive: profile.caseSensitive, logicalCapacityBytes: profile.logicalCapacityBytes,
            imageFormat: nil, validation: profile.validation)
        try JSONEncoder().encode([legacy]).write(to: fixture.service.paths.sectoriumProfiles, options: .atomic)
        fixture.runner.detachedDiskInfos[isolatedDevMount.path] = [
            "VolumeUUID": profile.backingVolumeUUID.uuidString,
            "MountPoint": fixture.mount.path, "FilesystemType": "ExFAT", "WritableVolume": true,
            "VolumeName": "Fixture HE", "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81"
        ]
        fixture.runner.imageInventory = [] // Explicit detached observation permits this fixture's attach.
        fixture.runner.attachOutcome = .init(exitCode: 130, detail: "fixture attach cancelled")
        let historyStart = fixture.store.history.count

        _ = fixture.service.startDevelopmentDisk()

        let states = Array(fixture.store.history.dropFirst(historyStart))
        let target = "\(profile.deviceID):\(profile.imagePath)"
        #expect(states.contains { $0.workbenchPhase == "mutating:saveImageFormat"
            && $0.workbenchTarget == target })
        #expect(states.contains { $0.workbenchCompletedStep == "saveImageFormat" })
        #expect(fixture.service.sectoriumProfiles().first?.imageFormat == "UDSB")
    }

    @Test("Interrupted completed create observes and durably records the documented image format before clearing intent")
    func interruptedCreateRecoversMissingImageFormat() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let created = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "RecoverFormat", capacityGiB: 1,
            caseSensitive: false, password: nil)
        #expect(created.succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let interrupted = SectoriumDevelopmentProfile(id: profile.id, name: profile.name, deviceID: profile.deviceID,
            backingVolumeUUID: profile.backingVolumeUUID, backingMountPoint: profile.backingMountPoint,
            imagePath: profile.imagePath, devVolumeName: profile.devVolumeName, devMountPoint: profile.devMountPoint,
            devUUID: profile.devUUID, encrypted: profile.encrypted, caseSensitive: profile.caseSensitive,
            logicalCapacityBytes: profile.logicalCapacityBytes, imageFormat: nil, validation: profile.validation)
        try JSONEncoder().encode([interrupted]).write(to: fixture.service.paths.sectoriumProfiles, options: .atomic)
        fixture.store.value = StoragePersistentState(revision: fixture.store.value.revision + 1,
            ejectIntent: false, operationID: "create-operation", workbenchOperation: "create:create-operation",
            workbenchPhase: "mutating:createSparsebundle", workbenchTarget: profile.imagePath,
            workbenchCompletedStep: "createSparsebundle")
        let commandCountBeforeRecovery = fixture.runner.commands.count

        let recovered = fixture.service.resumePendingSectoriumOperation()

        #expect(recovered.succeeded)
        #expect(fixture.service.sectoriumProfiles().first?.imageFormat == "UDSB")
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(Array(fixture.runner.commands.dropFirst(commandCountBeforeRecovery)).contains(
            ["/usr/bin/hdiutil", "imageinfo", profile.imagePath, "-format"]))
    }

    @Test("Cancelled Start retains the attach boundary and durable operation marker")
    func cancelledStartRetainsRecoveryBoundary() throws {
        let fixture = try makeWorkbenchFixture(isolatedDevelopmentMount: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let created = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
            parentDirectory: fixture.mount, name: "Development", capacityGiB: 1,
            caseSensitive: false, password: nil)
        #expect(created.succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let isolatedDevMount = fixture.root.appendingPathComponent("isolated-dev-mount", isDirectory: true)
        let isolatedProfile = SectoriumDevelopmentProfile(id: profile.id, name: profile.name,
            deviceID: profile.deviceID, backingVolumeUUID: profile.backingVolumeUUID,
            backingMountPoint: profile.backingMountPoint, imagePath: profile.imagePath,
            devVolumeName: profile.devVolumeName, devMountPoint: isolatedDevMount.path,
            devUUID: profile.devUUID, encrypted: profile.encrypted, caseSensitive: profile.caseSensitive,
            logicalCapacityBytes: profile.logicalCapacityBytes, validation: profile.validation)
        let profilesURL = HESectoriumPaths(root: fixture.root.appendingPathComponent("support")).sectoriumProfiles
        try JSONEncoder().encode([isolatedProfile]).write(to: profilesURL, options: .atomic)
        fixture.runner.detachedDiskInfos[isolatedDevMount.path] = [
            "VolumeUUID": fixture.service.coreController.identityPolicy.outerUUID.uuidString,
            "MountPoint": fixture.mount.path, "FilesystemType": "ExFAT", "WritableVolume": true,
            "VolumeName": "Fixture HE", "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81"
        ]
        fixture.runner.imageInventory = [] // Explicit detached observation permits this fixture's attach.
        fixture.runner.attachOutcome = .init(exitCode: 130, detail: "fixture attach cancelled")

        let start = fixture.service.startDevelopmentDisk()

        #expect(!start.succeeded)
        #expect(fixture.store.value.workbenchOperation?.hasPrefix("start:") == true)
        #expect(fixture.store.value.workbenchPhase == "mutating:attachImage")
        #expect(fixture.store.value.workbenchCompletedStep == "prepareMountPoint")
        #expect(start.steps.contains { $0.step == "attachImage" && $0.status == .failed })
        #expect(fixture.runner.commands.contains { $0.first == "/usr/bin/hdiutil" && $0.dropFirst().first == "attach" })
    }

    @Test("Quit refuses new work but drains an accepted create and first-load operation")
    func quitDrainsAcceptedCompositeOperation() async throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let drained = DispatchSemaphore(value: 0)
        fixture.runner.beforeCreate = { entered.signal(); release.wait() }
        let service = fixture.service, deviceID = fixture.device.id
        let creation = Task.detached {
            service.createDevelopmentDisk(.init(deviceID: deviceID, name: "Quit Check",
                capacityGiB: 1, filesystem: .apfs, autoLoad: true))
        }
        let didEnter = await Task.detached { waitForFixtureSignal(entered, seconds: 5) }.value
        guard didEnter else {
            release.signal(); _ = await creation.value
            Issue.record("Create did not reach the isolated blocking command"); return
        }
        service.stopAcceptingNewOperations()
        let waiter = Task { await service.waitForPendingOperations(); drained.signal() }
        let earlyDrain = await Task.detached { waitForFixtureSignal(drained, seconds: 0.05) }.value
        #expect(!earlyDrain)
        // Rejection must occur before the Service serial lock held by creation.
        #expect(!service.runApplicationAutomationAtStartup().succeeded)
        release.signal()
        let result = await creation.value
        await waiter.value
        #expect(result.succeeded, "\(result)")
        let profile = try #require(service.sectoriumProfiles().first)
        #expect(service.verifiedLoadedState(profileID: profile.id) == true)
        let commandCount = fixture.runner.commands.count
        #expect(!service.createDevelopmentDisk(.init(deviceID: deviceID, name: "After Quit",
            capacityGiB: 1, filesystem: .apfs)).succeeded)
        #expect(fixture.runner.commands.count == commandCount)
    }

    @Test("Quit also drains a documentation retry and rejects later retries")
    func quitDrainsDocumentationRetry() async throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Document Quit", capacityGiB: 1)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), drained = DispatchSemaphore(value: 0)
        fixture.portableWriter.beforeUpdate = { entered.signal(); release.wait() }
        let service = fixture.service, profileID = profile.id
        let retry = Task.detached { service.retryPortableDocumentation(profileID: profileID) }
        let didEnter = await Task.detached { waitForFixtureSignal(entered, seconds: 5) }.value
        guard didEnter else {
            release.signal(); _ = await retry.value
            Issue.record("Retry did not reach the isolated writer"); return
        }
        service.stopAcceptingNewOperations()
        let waiter = Task { await service.waitForPendingOperations(); drained.signal() }
        let earlyDrain = await Task.detached { waitForFixtureSignal(drained, seconds: 0.05) }.value
        #expect(!earlyDrain)
        #expect(service.retryPortableDocumentation(profileID: profileID) == .pending("AUV is closing; documentation remains pending"))
        release.signal(); _ = await retry.value; await waiter.value
        let writes = fixture.portableWriter.contexts.count
        #expect(service.retryPortableDocumentation(profileID: profileID) == .pending("AUV is closing; documentation remains pending"))
        #expect(fixture.portableWriter.contexts.count == writes)
    }

    @Test("Unload only keeps parent and image connected, then Load mounts the existing APFS volume without duplicate attach")
    func unloadOnlyThenLoadKeepsPhysicalParentAndAttachedImage() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Unload Fixture", capacityGiB: 1, filesystem: .apfs, autoLoad: false)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let check = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        let startIndex = fixture.runner.commands.count
        let unloaded = fixture.service.unloadDevelopmentDisk(profileID: profile.id, checkpoint: check)
        #expect(unloaded.succeeded, "\(unloaded)")
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == false)
        #expect(fixture.runner.imageInventory?.count == 1)
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.suppressedProfileIDs.contains(profile.id))
        #expect(fixture.observer.isPresent)
        #expect(!fixture.runner.commands.dropFirst(startIndex).contains { $0.contains("eject") || $0.contains("detach") })
        #expect(fixture.service.profileReadiness(profileID: profile.id) == .notStarted)
        #expect(fixture.service.sectoriumReadiness(deviceID: profile.deviceID, selectedProfileID: profile.id,
            devices: [fixture.device], profiles: [profile]) == .notStarted)
        // Native diskutil unmount removes its custom mountpoint; Load must restore
        // it beneath the verified parent before remounting the already-attached image.
        try FileManager.default.removeItem(atPath: profile.devMountPoint)
        let loaded = fixture.service.startDevelopmentDisk(profileID: profile.id)
        #expect(loaded.succeeded, "\(loaded)")
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        let commands = Array(fixture.runner.commands.dropFirst(startIndex))
        #expect(commands.contains(["/usr/sbin/diskutil", "mount", "-mountPoint", profile.devMountPoint, "/dev/disk31s1"]))
        #expect(!commands.contains { $0.contains("attach") || $0.contains("eject") || $0.contains("detach") })
        #expect(!fixture.store.value.suppressedProfileIDs.contains(profile.id))
    }

    @Test("Unload completion recovery is independent of external documentation and never repeats unmount")
    func unloadRecoveryDoesNotWaitForPortableDocument() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Unload Recovery", capacityGiB: 1, filesystem: .apfs, autoLoad: false)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let check = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        fixture.portableWriter.outcome = .pending("fixture external document unavailable")
        let writesBefore = fixture.portableWriter.contexts.count
        fixture.store.rejectNextMarkerClear = true
        #expect(!fixture.service.unloadDevelopmentDisk(profileID: profile.id, checkpoint: check).succeeded)
        #expect(fixture.store.value.workbenchOperation?.hasPrefix("unload:") == true)
        let commandsBefore = fixture.runner.commands.count
        let resumed = fixture.service.resumePendingSectoriumOperation()
        #expect(resumed.succeeded, "\(resumed)")
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.portableWriter.contexts.count == writesBefore)
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == false)
        #expect(!fixture.runner.commands.dropFirst(commandsBefore).contains { $0.contains("unmount") || $0.contains("eject") || $0.contains("detach") })
    }

    @Test("Native APFS empty MountPoint without Mounted completes Unload and enables Load")
    func nativeUnmountedMetadataCompletesUnloadWithoutMountedBoolean() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Native Unload", capacityGiB: 1, filesystem: .apfs, autoLoad: false)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        fixture.runner.afterNativeUnmount = {
            fixture.runner.additionalDiskInfos["/dev/disk31s1"]?.removeValue(forKey: "Mounted")
            fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["MountPoint"] = ""
            try? FileManager.default.removeItem(atPath: profile.devMountPoint)
        }
        let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        let before = fixture.runner.commands.count
        let result = fixture.service.unloadDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint)
        #expect(result.succeeded, "\(result)")
        #expect(result.steps.contains { $0.step == "verifyDevelopmentVolumeUnloaded" && $0.status == .succeeded })
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.service.profileReadiness(profileID: profile.id) == .notStarted)
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == false)
        #expect(!FileManager.default.fileExists(atPath: profile.devMountPoint))
        let mutations = fixture.runner.commands.dropFirst(before).filter { $0.contains("unmount") || $0.contains("eject") || $0.contains("detach") }
        #expect(mutations == [["/usr/sbin/diskutil", "unmount", profile.devMountPoint]])
        #expect(fixture.service.startDevelopmentDisk(profileID: profile.id).succeeded)
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(!fixture.store.value.suppressedProfileIDs.contains(profile.id))
    }

    @Test("Unload never trusts contradictory native fields or an ambiguous image/APFS chain", arguments:
        ["mountedTrue", "mountedInvalid", "mountPointPresent", "wrongContainer", "duplicateImage"])
    func nativeUnloadRejectsContradictoryOrAmbiguousEvidence(variant: String) throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Contradictory Unload", capacityGiB: 1, autoLoad: false)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        fixture.runner.afterNativeUnmount = {
            fixture.runner.additionalDiskInfos["/dev/disk31s1"]?.removeValue(forKey: "Mounted")
            fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["MountPoint"] = ""
            switch variant {
            case "mountedTrue": fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["Mounted"] = true
            case "mountedInvalid": fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["Mounted"] = "false"
            case "mountPointPresent": fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["MountPoint"] = profile.devMountPoint
            case "wrongContainer": fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["APFSContainerReference"] = "disk99"
            case "duplicateImage":
                if let image = fixture.runner.imageInventory?.first { fixture.runner.imageInventory?.append(image) }
            default: break
            }
        }
        let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        let result = fixture.service.unloadDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint)
        #expect(!result.succeeded)
        #expect(!result.steps.contains { $0.step == "verifyDevelopmentVolumeUnloaded" && $0.status == .succeeded })
        #expect(!fixture.service.reconcileCompletedUnload())
        #expect(fixture.store.value.workbenchOperation?.hasPrefix("unload:") == true)
    }

    @Test("Retained successful unmount reconciles only with explicit native unloaded identity")
    func retainedNativeUnloadMarkerNeedsExplicitUnmountedEvidence() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Unload Recovery Native", capacityGiB: 1, autoLoad: false)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        fixture.runner.afterNativeUnmount = {
            fixture.runner.additionalDiskInfos["/dev/disk31s1"]?.removeValue(forKey: "Mounted")
            fixture.runner.additionalDiskInfos["/dev/disk31s1"]?.removeValue(forKey: "MountPoint")
            try? FileManager.default.removeItem(atPath: profile.devMountPoint)
        }
        let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        let result = fixture.service.unloadDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint)
        #expect(!result.succeeded)
        let marker = try #require(fixture.store.value.workbenchOperation)
        #expect(fixture.store.value.workbenchCompletedStep == "unmountDEV")
        let before = fixture.runner.commands.count
        #expect(!fixture.service.reconcileCompletedUnload())
        #expect(fixture.store.value.workbenchOperation == marker)
        fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["MountPoint"] = ""
        let uuid = fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["VolumeUUID"]
        fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["VolumeUUID"] = UUID().uuidString
        #expect(!fixture.service.reconcileCompletedUnload())
        #expect(fixture.store.value.workbenchOperation == marker)
        fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["VolumeUUID"] = uuid
        let service = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy, sectoriumDeviceObserver: fixture.observer,
            portableDocumentWriter: fixture.portableWriter)
        #expect(service.reconcileCompletedUnload())
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.suppressedProfileIDs.contains(profile.id))
        #expect(service.profileReadiness(profileID: profile.id) == .notStarted)
        #expect(!fixture.runner.commands.dropFirst(before).contains { $0.contains("unmount") || $0.contains("attach") || $0.contains("eject") || $0.contains("detach") })
        #expect(service.startDevelopmentDisk(profileID: profile.id).succeeded)
    }

    @Test("An exact externally reloaded chain supersedes a retained successful Unload without claiming Unloaded")
    func retainedUnloadMarkerCanBeSupersededByVerifiedExternalLoad() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Externally Reloaded", capacityGiB: 1, autoLoad: false)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        fixture.store.rejectNextMarkerClear = true
        #expect(!fixture.service.unloadDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint).succeeded)
        #expect(fixture.runner.run("/usr/sbin/diskutil", ["mount", "-mountPoint", profile.devMountPoint, "/dev/disk31s1"], cwd: fixture.root).succeeded)
        let before = fixture.runner.commands.count
        #expect(fixture.service.reconcileCompletedUnload())
        #expect(fixture.store.value.workbenchOperation == nil)
        #expect(fixture.store.value.workbenchTerminalResult == "unload-superseded-by-verified-load")
        #expect(!fixture.store.value.suppressedProfileIDs.contains(profile.id))
        #expect(fixture.service.profileReadiness(profileID: profile.id) == .ready)
        #expect(!fixture.runner.commands.dropFirst(before).contains { $0.contains("unmount") || $0.contains("mount") || $0.contains("eject") || $0.contains("detach") })
    }

    @Test("Loaded state without a durable successful Unload receipt does not discard an interrupted operation")
    func interruptedUnloadWithoutReceiptRemainsPendingWhenLoaded() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Interrupted Unload", capacityGiB: 1, autoLoad: false)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        fixture.store.rejectNextCompletedStep = "unmountDEV"
        #expect(!fixture.service.unloadDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint).succeeded)
        #expect(fixture.store.value.workbenchCompletedStep == nil)
        #expect(fixture.runner.run("/usr/sbin/diskutil", ["mount", "-mountPoint", profile.devMountPoint, "/dev/disk31s1"], cwd: fixture.root).succeeded)
        let marker = fixture.store.value.workbenchOperation
        #expect(!fixture.service.reconcileCompletedUnload())
        #expect(fixture.store.value.workbenchOperation == marker)
        #expect(fixture.store.value.suppressedProfileIDs.contains(profile.id))
    }

    @Test("Activity report preserves process names, PID and working-directory references")
    func activityFieldOutputNamesBlockingProcessAndCWD() {
        let report = SectoriumActivityReport.parse(.init(exitCode: 0, detail:
            "p751\ncCodex\nfcwd\nf12r\np752\ncnode\nfcwd\n"))
        #expect(report.assessment == .busy(processIDs: [751, 752]))
        #expect(report.processes.first?.command == "Codex")
        #expect(report.processes.first?.references == [.init(descriptor: "cwd", path: ""),
            .init(descriptor: "12r", path: "")])
        #expect(SectoriumActivityReport.parse(.init(exitCode: 1, detail: "")).assessment == .noVisibleOccupancy)
        if case .incomplete = SectoriumActivityReport.parse(.init(exitCode: 1, detail: "permission denied")).assessment {} else { Issue.record("Failed scan must remain unknown") }
        if case .incomplete = SectoriumActivityReport.parse(.init(exitCode: 0, detail: "malformed")).assessment {} else { Issue.record("Malformed scan must remain unknown") }
    }

    @Test("Create's unchanged registered output loads, changes real settings, unloads and loads again")
    func createReturnedProfileCompletesNativeFixtureLifecycle() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
        let result = fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "开发 Disk", capacityGiB: 2, filesystem: .apfs, autoLoad: true))
        #expect(result.succeeded, "\(result)")
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        #expect(profile.devMountPoint.hasPrefix(fixture.mount.path + "/.AUV-Sectorium-Mounts/"))
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        #expect(profile.logicalCapacityBytes == 2 * 1_073_741_824)
        #expect(profile.autoLoad && profile.imageFileIdentity != nil)
        #expect(fixture.service.portableDocumentationPending(profileID: profile.id) == false)

        let rename = fixture.service.updateDevelopmentDisk(profileID: profile.id, change: .displayName("新开发 Disk"))
        #expect(rename.succeeded, "\(rename)")
        #expect(fixture.runner.commands.contains { $0.first == "/usr/sbin/diskutil" && $0.dropFirst().first == "renameVolume" })
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        let stop = fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint)
        #expect(stop.succeeded, "\(stop)")
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == false)
        let grow = fixture.service.updateDevelopmentDisk(profileID: profile.id, change: .capacityGiB(3))
        #expect(grow.succeeded, "\(grow)")
        #expect(fixture.service.sectoriumProfiles().first?.logicalCapacityBytes == 3 * 1_073_741_824)
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == false)
        let location = fixture.mount.appendingPathComponent("Custom Mount").path
        #expect(fixture.service.updateDevelopmentDisk(profileID: profile.id, change: .mountPoint(location)).succeeded)
        #expect(fixture.service.updateDevelopmentDisk(profileID: profile.id, change: .autoLoad(false)).succeeded)
        let start = fixture.service.startDevelopmentDisk(profileID: profile.id)
        #expect(start.succeeded, "\(start)")
        #expect(fixture.service.sectoriumProfiles().first?.devMountPoint == location)
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        let history = fixture.service.portableDocumentHistory(profileID: profile.id)
        #expect(history.contains { $0.kind == "capacityChanged" && $0.phase == .completed })
        #expect(history.contains { $0.kind == "displayNameChanged" && $0.phase == .completed })
        #expect(history.contains { $0.phase == .intended })
    }

    @Test("Documentation failure persists original events and retry does not repeat storage")
    func documentFailureIsDurableAndRetryPreservesHistory() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.portableWriter.outcome = .pending("fixture parent is read-only")
        let result = fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id, name: "Journal", capacityGiB: 2))
        #expect(result.succeeded, "\(result)")
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        #expect(fixture.service.portableDocumentationPending(profileID: profile.id))
        let journal = SectoriumPortableDocumentJournal(url: fixture.root.appendingPathComponent("support/sectorium-document-journal.json"))
        let before = try journal.events(parentID: profile.deviceID)
        #expect(!before.isEmpty)
        let commands = fixture.runner.commands.filter { $0.contains("create") || $0.contains("attach") }
        fixture.portableWriter.outcome = .updated
        #expect(fixture.service.retryPortableDocumentation(profileID: profile.id) == .updated)
        #expect(try journal.events(parentID: profile.deviceID) == before)
        #expect(fixture.runner.commands.filter { $0.contains("create") || $0.contains("attach") } == commands)
        #expect(!fixture.service.portableDocumentationPending(profileID: profile.id))
    }

    @Test("Native success without rename/resize postconditions never saves the requested value")
    func nativeModificationNeedsPostconditions() throws {
        for resize in [false, true] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
            fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
            fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
            #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id, name: "Original", capacityGiB: 2)).succeeded)
            let profile = try #require(fixture.service.sectoriumProfiles().first)
            if resize {
                let check = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
                #expect(fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: check).succeeded)
            }
            let original = try Data(contentsOf: fixture.service.paths.sectoriumProfiles)
            fixture.runner.ignoreNativeModification = true
            let result = fixture.service.updateDevelopmentDisk(profileID: profile.id,
                change: resize ? .capacityGiB(3) : .displayName("New name"))
            #expect(!result.succeeded)
            #expect(try Data(contentsOf: fixture.service.paths.sectoriumProfiles) == original)
            #expect(fixture.store.value.workbenchOperation?.hasPrefix("modify:") == true)
            #expect(fixture.service.portableDocumentHistory(profileID: profile.id).contains { $0.phase == .intended && $0.kind == "modificationIntended" })
        }
    }

    @Test("Fresh Service reconciles interrupted native changes or proven preimages without repeating modifications")
    func interruptedModificationReconcilesFromDurableIntent() throws {
        for resize in [false, true] {
            for nativeChanged in [false, true] {
                let fixture = try makeWorkbenchFixture()
                defer { try? FileManager.default.removeItem(at: fixture.root) }
                fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
                fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
                fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
                #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
                    name: "Recover Native", capacityGiB: 2)).succeeded)
                let profile = try #require(fixture.service.sectoriumProfiles().first)
                if resize {
                    let check = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
                    #expect(fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: check).succeeded)
                }
                fixture.runner.ignoreNativeModification = !nativeChanged
                if nativeChanged {
                    fixture.runner.afterNativeModification = { fixture.runner.unavailableInfoPaths.insert(profile.devMountPoint) }
                }
                #expect(!fixture.service.updateDevelopmentDisk(profileID: profile.id,
                    change: resize ? .capacityGiB(3) : .displayName("Recovered Name")).succeeded)
                fixture.runner.afterNativeModification = nil; fixture.runner.unavailableInfoPaths = []
                let originalMarker = try #require(fixture.store.value.workbenchOperation)
                let modificationCount = fixture.runner.commands.filter { $0.contains("resize") || $0.contains("renameVolume") }.count
                let restarted = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
                    store: fixture.store, operationLock: WorkbenchMemoryLock(),
                    installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
                    identityPolicy: fixture.service.coreController.identityPolicy,
                    sectoriumDeviceObserver: fixture.observer, portableDocumentWriter: fixture.portableWriter)
                let result = restarted.resumePendingSectoriumOperation()
                #expect(result.succeeded, "resize=\(resize), nativeChanged=\(nativeChanged): \(result)")
                #expect(fixture.store.value.workbenchOperation == nil)
                #expect(fixture.runner.commands.filter { $0.contains("resize") || $0.contains("renameVolume") }.count == modificationCount)
                let final = try #require(restarted.sectoriumProfiles().first)
                #expect(final.name == (!resize && nativeChanged ? "Recovered Name" : "Recover Native"))
                #expect(final.logicalCapacityBytes == UInt64(resize && nativeChanged ? 3 : 2) * 1_073_741_824)
                #expect(restarted.verifiedLoadedState(profileID: profile.id) == !resize)
                if resize { #expect(fixture.store.value.suppressedProfileIDs.contains(profile.id)) }
                let operationID = String(originalMarker.dropFirst("modify:".count))
                #expect(restarted.portableDocumentHistory(profileID: profile.id).contains {
                    $0.id == operationID + ":" + profile.id + ":completed"
                })
            }
        }
    }

    @Test("Saved mount and autoload changes recover after an interrupted completion record")
    func interruptedRegistryChangeReconcilesWithoutStorageMutation() throws {
        for mountChange in [false, true] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
            fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
            fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
            #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id, name: "Registry Recovery", capacityGiB: 1)).succeeded)
            let profile = try #require(fixture.service.sectoriumProfiles().first)
            let check = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
            #expect(fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: check).succeeded)
            let requestedPath = fixture.mount.appendingPathComponent("Recovered Mount").path
            fixture.store.rejectNextCompletedStep = "saveModifiedProfile"
            #expect(!fixture.service.updateDevelopmentDisk(profileID: profile.id,
                change: mountChange ? .mountPoint(requestedPath) : .autoLoad(false)).succeeded)
            let before = fixture.runner.commands.count
            let restarted = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
                store: fixture.store, operationLock: WorkbenchMemoryLock(),
                installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
                identityPolicy: fixture.service.coreController.identityPolicy,
                sectoriumDeviceObserver: fixture.observer, portableDocumentWriter: fixture.portableWriter)
            #expect(restarted.resumePendingSectoriumOperation().succeeded)
            #expect(fixture.store.value.workbenchOperation == nil)
            let final = try #require(restarted.sectoriumProfiles().first)
            #expect(mountChange ? final.devMountPoint == requestedPath : final.autoLoad == false)
            #expect(!fixture.runner.commands.dropFirst(before).contains { $0.contains("attach") || $0.contains("resize") || $0.contains("renameVolume") })
        }
    }

    @Test("Image detach accepts absent optional hdiutil UUID and rejects a conflicting value")
    func imageDetachResolvesActualPartitionedAPFSChain() throws {
        for contradictory in [false, true] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
            fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
            fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
            #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
                name: "Native Image Shape", capacityGiB: 1)).succeeded)
            let profile = try #require(fixture.service.sectoriumProfiles().first)
            let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
            fixture.runner.imageInventory = fixture.runner.imageInventory?.map { image in
                var image = image
                let entities = image["system-entities"] as! [[String: Any]]
                image["system-entities"] = entities.map { entity in
                    var entity = entity
                    if entity["dev-entry"] as? String == "/dev/disk31s1" {
                        if contradictory { entity["volume-uuid"] = UUID().uuidString }
                        else { entity.removeValue(forKey: "volume-uuid") }
                    }
                    return entity
                }
                return image
            }
            let commands = fixture.runner.commands.count
            let result = fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint)
            #expect(result.succeeded == !contradictory, "\(contradictory): \(result)")
            let ejects = fixture.runner.commands.dropFirst(commands).filter { $0.contains("eject") }
            #expect(ejects == (contradictory ? [] : [["/usr/sbin/diskutil", "eject", "/dev/disk30"]]))
        }
    }

    @Test("A profile stop never ejects an image containing an additional unregistered APFS volume")
    func imageDetachRefusesUnregisteredContainerMember() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Single Image Contract", capacityGiB: 1)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        let originalMembers = try #require(fixture.runner.apfsContainers?.first?["Volumes"] as? [[String: Any]])
        fixture.runner.apfsContainers?[0]["Volumes"] = originalMembers + [["APFSVolumeUUID": UUID().uuidString, "DeviceIdentifier": "disk31s2"]]
        let before = fixture.runner.commands.count
        #expect(!fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint).succeeded)
        #expect(!fixture.runner.commands.dropFirst(before).contains { $0.contains("eject") })
        #expect(fixture.store.value.workbenchOperation != nil)
    }

    @Test("Interrupted verification unload resumes only its remaining verified image detach")
    func interruptedVerificationUnloadFinishesWithoutRepeatingModification() throws {
        for resize in [false, true] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
            fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
            fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
            #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
                name: "Partial Unload", capacityGiB: 1)).succeeded)
            let profile = try #require(fixture.service.sectoriumProfiles().first)
            let check = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
            #expect(fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: check).succeeded)
            fixture.runner.failNextImageEject = true
            let modified = fixture.service.updateDevelopmentDisk(profileID: profile.id,
                change: resize ? .capacityGiB(2) : .displayName("Partial Renamed"))
            #expect(!modified.succeeded)
            #expect(fixture.store.value.workbenchPhase == "mutating:restoreUnloaded")
            let unmountedInfo = try #require(fixture.runner.additionalDiskInfos["/dev/disk31s1"])
            #expect(unmountedInfo["Mounted"] as? Bool == false)
            fixture.runner.imageInventory = fixture.runner.imageInventory?.map { image in
                var image = image
                image["system-entities"] = (image["system-entities"] as? [[String: Any]])?.map { entity in
                    var entity = entity; entity.removeValue(forKey: "volume-uuid"); return entity
                }
                return image
            }
            let restarted = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
                store: fixture.store, operationLock: WorkbenchMemoryLock(),
                installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
                identityPolicy: fixture.service.coreController.identityPolicy,
                sectoriumDeviceObserver: fixture.observer, portableDocumentWriter: fixture.portableWriter)
            // An ambiguous/replaced volume must not authorize even the final detach.
            let beforeRefusal = fixture.runner.commands.count
            fixture.runner.additionalDiskInfos["/dev/disk31s1"]?["VolumeUUID"] = UUID().uuidString
            #expect(!restarted.resumePendingSectoriumOperation().succeeded)
            #expect(!fixture.runner.commands.dropFirst(beforeRefusal).contains { $0.contains("eject") || $0.contains("attach") })
            fixture.runner.additionalDiskInfos["/dev/disk31s1"] = unmountedInfo
            let beforeRecovery = fixture.runner.commands.count
            let recovered = restarted.resumePendingSectoriumOperation()
            #expect(recovered.succeeded, "\(resize): \(recovered)")
            let mutations = fixture.runner.commands.dropFirst(beforeRecovery).filter {
                $0.contains("eject") || $0.contains("attach") || $0.contains("unmount") || $0.contains("resize") || $0.contains("renameVolume")
            }
            #expect(mutations == [["/usr/sbin/diskutil", "eject", "/dev/disk30"]])
            #expect(fixture.store.value.workbenchOperation == nil)
            #expect(fixture.store.value.suppressedProfileIDs.contains(profile.id))
            #expect(restarted.verifiedLoadedState(profileID: profile.id) == false)
        }
    }

    @Test("Fresh-process recovery records original create, load and unload completion before clearing its marker")
    func completedStorageCrashRecoversOriginalDocumentation() throws {
        for action in ["create", "start", "stop"] {
            let fixture = try makeWorkbenchFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
            fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
            fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
            if action != "create" {
                #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
                    parentDirectory: fixture.mount, name: "Crash History", capacityGiB: 1,
                    caseSensitive: false, password: nil).succeeded)
            }
            if action == "stop" {
                #expect(fixture.service.startDevelopmentDisk().succeeded)
            }
            let journalURL = fixture.service.paths.root.appendingPathComponent("sectorium-document-journal.json")
            let completedStep = action == "create" ? "createSparsebundle" : action == "start" ? "saveValidatedProfile" : "detachImage"
            var crashState: StoragePersistentState?
            var crashJournal: Data?
            // Capture the actual durable boundary before the completed event. Only
            // this disposable fixture is restored to emulate process termination.
            fixture.store.onSavedState = { state in
                if state.workbenchOperation?.hasPrefix(action + ":") == true,
                   state.workbenchCompletedStep == completedStep, crashState == nil {
                    crashState = state
                    crashJournal = try? Data(contentsOf: journalURL)
                }
            }
            let result: OperationResult
            if action == "create" {
                result = fixture.service.createDevelopmentDisk(deviceID: fixture.device.id,
                    parentDirectory: fixture.mount, name: "Crash History", capacityGiB: 1,
                    caseSensitive: false, password: nil)
            } else if action == "start" {
                result = fixture.service.startDevelopmentDisk()
            } else {
                let profile = try #require(fixture.service.sectoriumProfiles().first)
                let checkpoint = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
                result = fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: checkpoint)
            }
            #expect(result.succeeded, "\(action): \(result)")
            fixture.store.onSavedState = nil
            let preservedState = try #require(crashState)
            let preservedJournal = try #require(crashJournal)
            fixture.store.value = preservedState
            try preservedJournal.write(to: journalURL, options: .atomic)
            let profile = try #require(fixture.service.sectoriumProfiles().first)
            let original = try #require(preservedState.workbenchOperation?.split(separator: ":", maxSplits: 1).last.map(String.init))
            let intendedID = original + ":" + profile.id + ":intended"
            let completedID = original + ":" + profile.id + ":completed"
            let intended = try #require(fixture.service.portableDocumentHistory(profileID: profile.id).first { $0.id == intendedID })
            #expect(!fixture.service.portableDocumentHistory(profileID: profile.id).contains { $0.id == completedID })
            let commands = fixture.runner.commands.count
            fixture.portableWriter.outcome = .pending("fixture parent document temporarily unavailable")
            let restarted = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
                store: fixture.store, operationLock: WorkbenchMemoryLock(),
                installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
                identityPolicy: fixture.service.coreController.identityPolicy,
                sectoriumDeviceObserver: fixture.observer, portableDocumentWriter: fixture.portableWriter)
            let resumed = restarted.resumePendingSectoriumOperation()
            #expect(resumed.succeeded, "\(action): \(resumed)")
            #expect(fixture.store.value.workbenchOperation == nil)
            let recoveredHistory = restarted.portableDocumentHistory(profileID: profile.id)
            #expect(recoveredHistory.first { $0.id == intendedID } == intended)
            let completed = try #require(recoveredHistory.first { $0.id == completedID })
            #expect(completed.kind == (action == "create" ? "registered" : action == "start" ? "loaded" : "unloaded"))
            #expect(completed.occurredAt >= intended.occurredAt && completed.before == intended.before)
            #expect(!fixture.runner.commands.dropFirst(commands).contains {
                $0.contains("create") || $0.contains("attach") || $0.contains("detach") || $0.contains("unmount")
            })
            #expect(restarted.portableDocumentationPending(profileID: profile.id))
            fixture.portableWriter.outcome = .updated
            #expect(restarted.retryPortableDocumentation(profileID: profile.id) == .updated)
            #expect(restarted.portableDocumentHistory(profileID: profile.id) == recoveredHistory)
        }
    }

    @Test("A completion-marker write failure retains an already durable unload event across recovery")
    func markerClearFailureDoesNotDuplicateCompletionHistory() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Marker History", capacityGiB: 1)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let check = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        fixture.store.rejectNextMarkerClear = true
        #expect(!fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: check).succeeded)
        let marker = try #require(fixture.store.value.workbenchOperation)
        let operation = String(marker.dropFirst("stop:".count))
        let before = fixture.service.portableDocumentHistory(profileID: profile.id)
        #expect(before.contains { $0.id == operation + ":" + profile.id + ":completed" })
        let restarted = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy,
            sectoriumDeviceObserver: fixture.observer, portableDocumentWriter: fixture.portableWriter)
        #expect(restarted.resumePendingSectoriumOperation().succeeded)
        #expect(restarted.portableDocumentHistory(profileID: profile.id) == before)
    }

    @Test("Inventory and eject availability reuse one metadata graph, while a click observes identity changes")
    func inventoryAndEjectAvailabilityShareCommandContext() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backing = try #require(fixture.device.volumeUUIDs.first)
        try FileManager.default.createDirectory(at: fixture.service.paths.workingDirectory, withIntermediateDirectories: true)
        fixture.runner.diskInventory = [["DeviceIdentifier": "disk81",
            "Partitions": [["DeviceIdentifier": "disk81s1"]]]]
        fixture.runner.additionalDiskInfos["/dev/disk81"] = [
            "DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical", "WholeDisk": true,
            "DeviceLocation": "External", "MediaUUID": fixture.device.id, "MediaName": "Fixture Drive"]
        fixture.runner.additionalDiskInfos["/dev/disk81s1"] = [
            "DeviceIdentifier": "disk81s1", "VolumeUUID": backing.uuidString,
            "MountPoint": fixture.mount.path, "PartOfWhole": "disk81"]
        // Use the real metadata parser and driver with a disposable command
        // runner, rather than replacing the device observer under test.
        let service = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy)
        try service.withReadOnlyObservation {
            let devices = try service.observeSectoriumDevices()
            #expect(devices.count == 1 && devices.first?.identityVerified == true)
            #expect(!service.canPrepareWholeDeviceEjectConfirmation(physicalIdentity: fixture.device.id))
        }
        // The fixture deliberately places / on the same physical root: it must
        // remain ineligible. Reaching df proves the real driver read inventory.
        #expect(fixture.runner.commands.contains { $0 == ["/bin/df", "-P", "/"] })
        for arguments in [["list", "-plist"], ["info", "-plist", "/dev/disk81"],
                          ["info", "-plist", "/dev/disk81s1"]] {
            #expect(fixture.runner.commands.filter { $0 == ["/usr/sbin/diskutil"] + arguments }.count == 1)
        }
        #expect(Set(fixture.runner.commandDirectories) == [service.paths.workingDirectory.path])
        let previousReads = fixture.runner.commands.count
        fixture.runner.additionalDiskInfos["/dev/disk81"]?["MediaUUID"] = UUID().uuidString
        #expect(service.prepareWholeDeviceEjectConfirmation(physicalIdentity: fixture.device.id) == nil)
        #expect(fixture.runner.commands.count > previousReads)
        #expect(fixture.runner.commands.filter { $0 == ["/usr/sbin/diskutil", "list", "-plist"] }.count == 2)
        #expect(!fixture.runner.commands.contains { $0.contains("eject") || $0.contains("unmountDisk") })
    }

    @Test("Display inventory still works before the first support-directory installation")
    func inventoryDoesNotCreateSupportDirectory() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.diskInventory = [["DeviceIdentifier": "disk81", "Partitions": []]]
        fixture.runner.additionalDiskInfos["/dev/disk81"] = [
            "DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical", "WholeDisk": true,
            "DeviceLocation": "External", "MediaUUID": fixture.device.id, "MediaName": "Fixture Drive"]
        let paths = HESectoriumPaths(root: fixture.root.appendingPathComponent("not-installed"))
        let service = HESectoriumService(paths: paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy)
        #expect(try service.observeSectoriumInventoryForDisplay().count == 1)
        #expect(!FileManager.default.fileExists(atPath: paths.root.path))
        #expect(Set(fixture.runner.commandDirectories) == [FileManager.default.temporaryDirectory.path])
    }

    @Test("Startup qualifies an already loaded image without writing queued IMPORTANT history", arguments: [false, true])
    func startupDefersOptionalDocumentAndBoundsRepeatedMetadata(pending: Bool) throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.portableWriter.outcome = pending ? .pending("fixture IMPORTANT unavailable") : .updated
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Startup History", capacityGiB: 1, autoLoad: true)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        #expect(fixture.service.portableDocumentationPending(profileID: profile.id) == pending)
        let writes = fixture.portableWriter.contexts.count
        let history = fixture.service.portableDocumentHistory(profileID: profile.id)
        let commandsBefore = fixture.runner.commands.count
        fixture.portableWriter.beforeUpdate = { Issue.record("Startup must not invoke the external document writer") }

        let result = fixture.service.runApplicationAutomationAtStartup()

        #expect(result.succeeded, "\(result)")
        #expect(result.steps.contains { $0.step == "profile.\(profile.id).reuseVerifiedImage" })
        #expect(result.steps.contains { $0.step == "profile.\(profile.id).recordProfileReady" })
        #expect(fixture.portableWriter.contexts.count == writes)
        let newEvents = fixture.service.portableDocumentHistory(profileID: profile.id).filter { event in
            !history.contains(where: { $0.id == event.id })
        }
        #expect(newEvents.contains { $0.kind == "loaded" && $0.phase == .intended })
        #expect(newEvents.contains { $0.kind == "loaded" && $0.phase == .completed && $0.after?.lastVerifiedLoadedAt != nil })
        #expect(fixture.service.portableDocumentationPending(profileID: profile.id))
        let reads = Array(fixture.runner.commands.dropFirst(commandsBefore))
        let imageGraphs = reads.filter { $0 == ["/usr/bin/hdiutil", "info", "-plist"] }
        // Intent, Core qualification and fresh completion each observe once;
        // document records within the same phase reuse that phase's metadata.
        #expect(imageGraphs.count == 3, "Startup metadata: \(reads)")
        #expect(!reads.contains { $0.contains("attach") || $0.contains("unmount") || $0.contains("eject") })
        // Disk Arbitration also emits an initial appearance for the same
        // already-connected disk. That callback must not undo startup deferral.
        let beforeAppearanceReads = fixture.runner.commands.count
        let beforeAppearanceHistory = fixture.service.portableDocumentHistory(profileID: profile.id)
        let repeatedAppearance = fixture.service.runApplicationAutomation(.outerReappeared(uuid: profile.backingVolumeUUID))
        #expect(repeatedAppearance.succeeded)
        #expect(repeatedAppearance.steps.contains { $0.step == "profile.\(profile.id).ignoreEvent" })
        #expect(fixture.portableWriter.contexts.count == writes)
        #expect(fixture.service.portableDocumentationPending(profileID: profile.id))
        #expect(fixture.runner.commands.count == beforeAppearanceReads)
        #expect(fixture.service.portableDocumentHistory(profileID: profile.id) == beforeAppearanceHistory)

        // Unrelated system-volume appearances must not start registered-profile
        // recovery or write a new portable intent either.
        let unrelated = fixture.service.runApplicationAutomation(.outerReappeared(uuid: UUID()))
        #expect(unrelated.succeeded && unrelated.steps.contains { $0.step == "ignoreEvent" })
        #expect(fixture.runner.commands.count == beforeAppearanceReads)
        #expect(fixture.service.portableDocumentHistory(profileID: profile.id) == beforeAppearanceHistory)

        let restarted = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy,
            sectoriumDeviceObserver: fixture.observer, portableDocumentWriter: fixture.portableWriter)
        #expect(restarted.portableDocumentationPending(profileID: profile.id))
        #expect(newEvents.allSatisfy { restarted.portableDocumentHistory(profileID: profile.id).contains($0) })
        fixture.portableWriter.beforeUpdate = nil; fixture.portableWriter.outcome = .updated
        #expect(restarted.retryPortableDocumentation(profileID: profile.id) == .updated)
        #expect(!restarted.portableDocumentationPending(profileID: profile.id))
    }

    @Test("Disabled startup with no queued documentation does not probe image metadata")
    func disabledStartupSkipsUnneededPortableContext() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Manual Only", capacityGiB: 1, autoLoad: false)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        #expect(!fixture.service.portableDocumentationPending(profileID: profile.id))
        let before = fixture.runner.commands.count, writes = fixture.portableWriter.contexts.count
        let result = fixture.service.runApplicationAutomationAtStartup()
        #expect(result.succeeded)
        #expect(result.steps.contains { $0.step == "profile.\(profile.id).autoLoadDisabled" })
        #expect(fixture.runner.commands.count == before)
        #expect(fixture.portableWriter.contexts.count == writes)
    }

    @Test("Application startup honors per-volume preference and manual-unload suppression until physical reconnect")
    func applicationAutomationUsesDurablePerVolumeChoice() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.occupancyIsClear = true; fixture.runner.ejectAfterUnmountEnabled = true
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id, name: "Automatic", capacityGiB: 2)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let check = try #require(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id))
        #expect(fixture.service.stopDevelopmentDisk(profileID: profile.id, checkpoint: check).succeeded)
        let before = fixture.runner.commands.filter { $0.contains("attach") }.count
        #expect(fixture.service.runApplicationAutomationAtStartup().succeeded)
        #expect(fixture.runner.commands.filter { $0.contains("attach") }.count == before)
        #expect(fixture.store.value.suppressedProfileIDs.contains(profile.id))
        fixture.observer.isPresent = false
        fixture.runner.diskInventory = [["DeviceIdentifier": "disk0", "Partitions": []]]
        fixture.runner.additionalDiskInfos["/dev/disk0"] = ["DeviceIdentifier": "disk0", "VolumeUUID": UUID().uuidString]
        #expect(fixture.service.runApplicationAutomation(.outerDisappeared(uuid: profile.backingVolumeUUID)).succeeded)
        #expect(fixture.store.value.disconnectedProfileIDs.contains(profile.id))
        fixture.observer.isPresent = true
        let reconnected = fixture.service.runApplicationAutomation(.outerReappeared(uuid: profile.backingVolumeUUID))
        #expect(reconnected.succeeded, "\(reconnected)")
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
        #expect(!fixture.store.value.suppressedProfileIDs.contains(profile.id))
    }

    @Test("Whole-device eject records completion internally after absence and never writes the departed parent")
    func wholeEjectLeavesDurablePortableCompletionPending() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []; fixture.runner.occupancyIsClear = true
        #expect(fixture.service.createDevelopmentDisk(deviceID: fixture.device.id, parentDirectory: fixture.mount,
            name: "Offline history", capacityGiB: 2, caseSensitive: false, password: nil).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        fixture.runner.offTargetRuntime = true
        fixture.runner.additionalDiskInfos["/dev/disk0s1"] = ["DeviceIdentifier": "disk0s1", "PartOfWhole": "disk0"]
        fixture.runner.additionalDiskInfos["/dev/disk0"] = ["DeviceIdentifier": "disk0", "VirtualOrPhysical": "Physical", "WholeDisk": true]
        let topology = WholeDeviceTopology(physicalIdentity: profile.deviceID, bsdName: "disk81", isWholeDevice: true,
            isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(profile.backingVolumeUUID.uuidString.lowercased())|disk81s1", mounted: true)], images: [])
        let driver = CompletingEjectFixtureDriver(topology)
        var writesAtEject = 0
        driver.afterEject = { fixture.observer.isPresent = false; writesAtEject = fixture.portableWriter.contexts.count }
        let service = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(), store: fixture.store,
            operationLock: WorkbenchMemoryLock(), installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy, sectoriumDeviceObserver: fixture.observer,
            wholeDeviceEjectDriverOverride: driver, portableDocumentWriter: fixture.portableWriter)
        let confirmation = try #require(service.prepareWholeDeviceEjectConfirmation(physicalIdentity: profile.deviceID))
        let result = service.ejectExternalDevice(physicalIdentity: profile.deviceID, confirmation: confirmation)
        #expect(result.succeeded, "\(result)")
        #expect(driver.actions == ["unmount", "eject"])
        #expect(result.steps.contains { $0.step == "verifyWholeDeviceEjected" && $0.status == .succeeded })
        #expect(fixture.portableWriter.contexts.count == writesAtEject)
        let events = service.portableDocumentHistory(profileID: profile.id)
        #expect(events.contains { $0.phase == .intended && $0.kind == "ejected" })
        #expect(events.contains { $0.phase == .completed && $0.kind == "ejected" })
        #expect(service.portableDocumentationPending(profileID: profile.id))
        #expect(service.runApplicationAutomationAtStartup().succeeded)
        #expect(service.portableDocumentHistory(profileID: profile.id) == events)
        #expect(driver.actions == ["unmount", "eject"])
    }

    @Test("Eject history precondition refuses native mutation and runs only once on success")
    func ejectHistoryPreconditionIsEnforced() {
        let topology = WholeDeviceTopology(physicalIdentity: "fixture", bsdName: "disk81", isWholeDevice: true,
            isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "physical", mounted: true)], images: [])
        let base = CompletingEjectFixtureDriver(topology)
        let denied = SectoriumDocumentedEjectDriver(base: base, beforeMutation: { false })
        #expect(denied.unmountAllPhysicalVolumesNonForce(topology) == .failed("Portable operation history could not be durably recorded"))
        #expect(base.actions.isEmpty)
        var calls = 0
        let allowed = SectoriumDocumentedEjectDriver(base: base, beforeMutation: { calls += 1; return true })
        _ = allowed.unmountAllPhysicalVolumesNonForce(topology)
        _ = allowed.ejectWholeDeviceNonForce(topology)
        #expect(calls == 1)
        #expect(base.actions == ["unmount", "eject"])
    }

    @Test("A passive refresh shares loaded facts, keeps pending documentation separate, and the next action reads again")
    func passiveLoadedObservationDoesNotFanOutOrTurnDocumentPendingIntoReadiness() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.simulateLifecycle = true; fixture.runner.imageInventory = []
        fixture.runner.encryptionOutput = .init(exitCode: 0, detail: "encrypted: NO\n")
        fixture.portableWriter.outcome = .pending("fixture document is temporarily unavailable")
        #expect(fixture.service.createDevelopmentDisk(.init(deviceID: fixture.device.id,
            name: "Observed Development", capacityGiB: 1)).succeeded)
        let profile = try #require(fixture.service.sectoriumProfiles().first)
        let registry = try Data(contentsOf: fixture.service.paths.sectoriumProfiles)
        let before = fixture.runner.commands.count
        fixture.service.withReadOnlyObservation {
            #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
            let afterFirstRow = fixture.runner.commands.count
            #expect(afterFirstRow > before)
            for _ in 0..<12 {
                #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == true)
                #expect(fixture.service.portableDocumentationPending(profileID: profile.id))
                _ = fixture.service.portableDocumentHistory(profileID: profile.id)
            }
            #expect(fixture.service.refreshStatus(observedReadiness: .ready).readiness == .ready)
            #expect(fixture.runner.commands.count == afterFirstRow)
        }
        let beforeAction = fixture.runner.commands.count
        #expect(fixture.service.prepareStopDevelopmentDiskConfirmation(profileID: profile.id) != nil)
        #expect(fixture.runner.commands.count > beforeAction)
        fixture.runner.imageInventory = []
        #expect(fixture.service.verifiedLoadedState(profileID: profile.id) == false)
        #expect(try Data(contentsOf: fixture.service.paths.sectoriumProfiles) == registry)
    }

    @Test("Passive whole-drive availability is computed once, but confirmation refuses a newly missing target")
    func foregroundConfirmationNeverReusesPassiveAvailability() throws {
        let fixture = try makeWorkbenchFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let volume = try #require(fixture.device.volumeUUIDs.first)
        let topology = WholeDeviceTopology(physicalIdentity: fixture.device.id, bsdName: fixture.device.bsdName,
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(volume.uuidString.lowercased())|disk81s1", mounted: true)], images: [])
        let driver = TargetBindingFixtureDriver([fixture.device.id: topology])
        let service = HESectoriumService(paths: fixture.service.paths, backend: WorkbenchNoopBackend(),
            store: fixture.store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(fixture.service.paths), runner: fixture.runner,
            identityPolicy: fixture.service.coreController.identityPolicy,
            sectoriumDeviceObserver: fixture.observer, wholeDeviceEjectDriverOverride: driver,
            portableDocumentWriter: fixture.portableWriter)
        service.withReadOnlyObservation {
            #expect(service.canPrepareWholeDeviceEjectConfirmation(physicalIdentity: fixture.device.id))
            let count = fixture.runner.commands.count
            #expect(service.canPrepareWholeDeviceEjectConfirmation(physicalIdentity: fixture.device.id))
            #expect(fixture.runner.commands.count == count)
            #expect(!fixture.runner.commands.contains { $0.first == "/bin/df" })
            fixture.runner.additionalDiskInfos["/dev/disk81"] = ["DeviceIdentifier": "disk81",
                "ParentWholeDisk": "disk81", "WholeDisk": true, "VirtualOrPhysical": "Physical"]
            let confirmation = service.prepareWholeDeviceEjectConfirmation(physicalIdentity: fixture.device.id)
            #expect(confirmation != nil && confirmation?.dependenciesCanFinishOffTarget == false)
            #expect(fixture.runner.commands.contains { $0.first == "/bin/df" })
            driver.observations.removeValue(forKey: fixture.device.id)
            #expect(service.prepareWholeDeviceEjectConfirmation(physicalIdentity: fixture.device.id) == nil)
        }
        #expect(!service.canPrepareWholeDeviceEjectConfirmation(physicalIdentity: fixture.device.id))
        #expect(driver.storageActions == 0)
        #expect(fixture.store.history.isEmpty)
    }

    func makeWorkbenchFixture(isolatedDevelopmentMount: Bool = false) throws -> (root: URL, mount: URL, device: SectoriumPhysicalDevice,
                                                    runner: WorkbenchFixtureRunner, store: WorkbenchMemoryStore,
                                                    observer: WorkbenchFixtureObserver, portableWriter: WorkbenchPortableWriter,
                                                    service: HESectoriumService) {
        let requestedRoot = URL(fileURLWithPath: "/private/tmp/sectorium-workbench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: false)
        let root = requestedRoot.resolvingSymlinksInPath()
        let mount = root.appendingPathComponent("mounted-volume", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let mediaID = UUID()
        let volumeID = UUID()
        let device = SectoriumPhysicalDevice(id: mediaID.uuidString, bsdName: "disk81", name: "Fixture Drive",
            isExternal: true, identityVerified: true, wholeDeviceBytes: 64_000_000_000,
            mountedVolumePaths: [mount.path], volumeUUIDs: [volumeID], readBytes: 0, writtenBytes: 0)
        let runner = WorkbenchFixtureRunner(mountPoint: mount.path, volumeUUID: volumeID)
        let store = WorkbenchMemoryStore()
        let isolatedDEV = root.appendingPathComponent("isolated-dev-mount", isDirectory: true)
        let policy = StorageIdentityPolicy(outerUUID: volumeID, devUUID: isolatedDevelopmentMount ? nil : UUID(), outerMountPoint: mount.path,
            devMountPoint: isolatedDevelopmentMount ? isolatedDEV.path : "/Volumes/Fixture-DEV",
            devVolumeName: isolatedDevelopmentMount ? "Development" : "Fixture-DEV",
            imagePath: mount.appendingPathComponent(isolatedDevelopmentMount ? "Development.sparsebundle" : "Fixture.sparsebundle").path)
        let observer = WorkbenchFixtureObserver(device: device)
        let portableWriter = WorkbenchPortableWriter()
        let service = HESectoriumService(paths: HESectoriumPaths(root: root.appendingPathComponent("support")),
            backend: WorkbenchNoopBackend(), store: store, operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(HESectoriumPaths(root: root.appendingPathComponent("support"))),
            runner: runner, identityPolicy: policy, sectoriumDeviceObserver: observer,
            portableDocumentWriter: portableWriter)
        return (root, mount, device, runner, store, observer, portableWriter, service)
    }

    private func plistData(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }
}

private final class PassphraseStorageFixtureRunner: HESectoriumSecureCommandRunning {
    let outerMountPoint: String
    let outerUUID: UUID
    var detachedDEVPath: String?
    private(set) var secureInputs: [Data] = []
    private(set) var secureArguments: [[String]] = []
    private(set) var allArguments: [[String]] = []
    init(outerMountPoint: String, outerUUID: UUID) {
        self.outerMountPoint = outerMountPoint; self.outerUUID = outerUUID
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        allArguments.append([executable] + arguments)
        if executable == "/usr/bin/hdiutil", arguments == ["info", "-plist"],
           let data = try? PropertyListSerialization.data(fromPropertyList: ["images": []], format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        if executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", outerMountPoint],
           let data = try? PropertyListSerialization.data(fromPropertyList: [
               "VolumeUUID": outerUUID.uuidString, "MountPoint": outerMountPoint,
               "FilesystemType": "APFS", "WritableVolume": true, "VolumeName": "Fixture",
               "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81"
           ], format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        if executable == "/usr/sbin/diskutil", arguments.count == 3,
           arguments[0] == "info", arguments[1] == "-plist", arguments[2] == detachedDEVPath,
           let data = try? PropertyListSerialization.data(fromPropertyList: [
               "VolumeUUID": outerUUID.uuidString, "MountPoint": outerMountPoint,
               "FilesystemType": "APFS", "WritableVolume": true, "VolumeName": "Fixture",
               "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81"
           ], format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        return .init(exitCode: 1, detail: "fixture reports observation unavailable")
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, standardInput: Data) -> CommandOutcome {
        allArguments.append([executable] + arguments)
        secureArguments.append([executable] + arguments)
        secureInputs.append(standardInput)
        return .success
    }
}

private final class WorkbenchIORegistryFixture: SectoriumIORegistryProviding {
    let mappings: [SectoriumIOMediaProviderMapping]
    private(set) var requestedNames: [String] = []
    init(mappings: [SectoriumIOMediaProviderMapping]) { self.mappings = mappings }
    func providerMappings(forWholeBSDName bsdName: String) throws -> [SectoriumIOMediaProviderMapping] {
        requestedNames.append(bsdName)
        return mappings
    }
}

private final class WorkbenchNoopBackend: StorageBackend {
    func observeOuter() -> VolumeIdentity? { nil }
    func observe() -> StorageObservation? { nil }
    func attachImage() -> CommandOutcome { .init(exitCode: 1) }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { .incomplete(reason: "fixture") }
    func perform(_ step: EjectStep) -> CommandOutcome { .init(exitCode: 1) }
    func finalOuterState() -> FinalOuterState { .unknown("fixture") }
}

private final class WorkbenchAdoptionBackend: StorageBackend {
    let observation: StorageObservation?
    init(observation: StorageObservation?) { self.observation = observation }
    func observeOuter() -> VolumeIdentity? { observation?.outer }
    func observe() -> StorageObservation? { observation }
    func attachImage() -> CommandOutcome { .init(exitCode: 127, detail: "adoption fixture forbids attach") }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { .incomplete(reason: "not part of adoption") }
    func perform(_ step: EjectStep) -> CommandOutcome { .init(exitCode: 127, detail: "adoption fixture forbids mutation") }
    func finalOuterState() -> FinalOuterState { .unknown("adoption fixture") }
}

private final class SectoriumInventoryCommandFixture: HESectoriumCommandRunning {
    var inventory: CommandOutcome
    var calls: [[String]] = []
    init(_ inventory: CommandOutcome) { self.inventory = inventory }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        calls.append([executable] + arguments)
        return inventory
    }
}

@Suite("Sectorium read-only inventory repair")
struct SectoriumInventoryRepairTests {
    @Test func completeProductionSizedPropertyListIsPreserved() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "AllDisksAndPartitions": [], "Padding": String(repeating: "x", count: 14_000)
        ], format: .xml, options: 0)
        let outcome = ProcessCommandRunner.result(executable: "/usr/sbin/diskutil", arguments: ["list", "-plist"],
                                                  exitCode: 0, stdout: data, stderr: Data())
        #expect(outcome.succeeded)
        #expect(outcome.detail.utf8.count > 8_192)
        #expect((try PropertyListSerialization.propertyList(from: Data(outcome.detail.utf8), options: [], format: nil) as? [String: Any]) != nil)
        let action = ProcessCommandRunner.result(executable: "/usr/sbin/diskutil", arguments: ["eject", "disk90"],
                                                 exitCode: 0, stdout: data, stderr: Data())
        #expect(action.detail.utf8.count <= 8_192)
        let tooLarge = ProcessCommandRunner.result(executable: "/usr/sbin/diskutil", arguments: ["list", "-plist"],
                                                   exitCode: 0, stdout: Data(repeating: 65, count: 1_048_577), stderr: Data())
        #expect(!tooLarge.succeeded)
    }

    @Test func processPipesAreBoundedAndDrainedWithoutDeadlock() {
        let runner = ProcessCommandRunner()
        let cwd = FileManager.default.temporaryDirectory
        let normal = runner.run("/bin/sh", ["-c", "printf ok; printf warning >&2"], cwd: cwd)
        #expect(normal.succeeded)
        #expect(normal.detail.contains("ok"))
        for script in ["/usr/bin/head -c 32768 /dev/zero",
                       "/usr/bin/head -c 32768 /dev/zero >&2",
                       "/usr/bin/head -c 32768 /dev/zero; /usr/bin/head -c 32768 /dev/zero >&2"] {
            let outcome = runner.run("/bin/sh", ["-c", script], cwd: cwd)
            #expect(!outcome.succeeded)
            #expect(outcome.detail == "command output exceeded bounded capture limit")
        }
        let failed = runner.run("/bin/sh", ["-c", "printf refused >&2; exit 7"], cwd: cwd)
        #expect(failed.exitCode == 7)
        #expect(failed.detail.contains("refused"))
    }

    @Test func unavailableAndMalformedAreNotEmptyInventory() {
        for outcome in [CommandOutcome(exitCode: 1, detail: "permission denied"),
                        CommandOutcome(exitCode: 0, detail: "not plist")] {
            let runner = SectoriumInventoryCommandFixture(outcome)
            let observer = SystemSectoriumDeviceObserver(runner: runner)
            #expect(throws: SectoriumDeviceCatalogError.self) { try observer.observeDevices() }
            #expect(runner.calls == [["/usr/sbin/diskutil", "list", "-plist"]])
        }
    }
}

@Suite("Sectorium existing-installation discovery fixtures")
struct SectoriumLegacyDiscoveryRepairTests {
    @Test("A registered single-volume backing starts and reconnects headlessly after fresh parent verification")
    func registeredBackingAnchorWorksWithoutSelection() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backing = fixture.policy.outerUUID
        let device = SectoriumPhysicalDevice(id: backing.uuidString, bsdName: "disk90",
            name: "Registered external fixture", isExternal: true, identityVerified: true,
            wholeDeviceBytes: 1_000_000, mountedVolumePaths: [fixture.policy.outerMountPoint],
            volumeUUIDs: [backing], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: backing, bsdName: "disk90s1",
                                  mountPoint: fixture.policy.outerMountPoint)],
            topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
            wholeMediaUUID: nil, requiresFreshParentCheck: true)
        let profile = SectoriumDevelopmentProfile(name: "FixtureDEV", deviceID: device.id,
            backingVolumeUUID: backing, backingMountPoint: fixture.policy.outerMountPoint,
            imagePath: fixture.policy.imagePath, devVolumeName: fixture.policy.devVolumeName,
            devMountPoint: fixture.policy.devMountPoint, devUUID: fixture.policy.devUUID,
            encrypted: false, caseSensitive: false, logicalCapacityBytes: 1_073_741_824,
            imageFormat: "UDSB", validation: .validated)
        let paths = HESectoriumPaths(root: fixture.root.appendingPathComponent("support"))
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try JSONEncoder().encode([profile]).write(to: paths.sectoriumProfiles, options: .atomic)
        let store = WorkbenchMemoryStore(), lock = WorkbenchMemoryLock()
        let observer = WorkbenchFixtureObserver(device: device)
        let installer = workbenchFixtureInstaller(paths)
        let writer = WorkbenchPortableWriter()
        let service = HESectoriumService(paths: paths, backend: WorkbenchNoopBackend(), store: store,
            operationLock: lock, installer: installer, runner: fixture.runner,
            identityPolicy: fixture.policy, sectoriumDeviceObserver: observer,
            portableDocumentWriter: writer)
        #expect(service.setAutomationEnabled(true).succeeded)

        fixture.runner.mountParentWholeDisk = "disk91"
        let drifted = service.runAutomationAgentAtStartup()
        #expect(!drifted.succeeded)
        #expect(drifted.steps.contains { $0.step == "profile.\(profile.id).verifyPhysicalBacking" })
        #expect(!store.value.reconnectAttemptedProfileIDs.contains(profile.id))

        fixture.runner.mountParentWholeDisk = "disk90"
        let started = service.runAutomationAgentAtStartup()
        #expect(started.succeeded, "\(String(describing: started.failure))")
        #expect(started.steps.contains { $0.step == "profile.\(profile.id).reuseVerifiedImage" })
        #expect(writer.events.isEmpty, "Startup preserves history internally without an external IMPORTANT write")
        #expect(service.portableDocumentHistory(profileID: profile.id).contains { $0.kind == "loaded" && $0.phase == .completed })
        #expect(service.portableDocumentationPending(profileID: profile.id))

        let inventory = fixture.runner.diskInventory
        fixture.runner.diskInventory = [["DeviceIdentifier": "disk99", "Partitions": []]]
        fixture.runner.additionalDiskInfos["/dev/disk99"] = [
            "DeviceIdentifier": "disk99", "VolumeUUID": UUID().uuidString
        ]
        observer.isPresent = false
        let disappeared = service.runAutomationAgent(.outerDisappeared(uuid: backing))
        #expect(disappeared.succeeded)
        #expect(store.value.disconnectedProfileIDs.contains(profile.id))
        fixture.runner.diskInventory = inventory
        observer.isPresent = true
        let freshProcess = HESectoriumService(paths: paths, backend: WorkbenchNoopBackend(), store: store,
            operationLock: lock, installer: installer, runner: fixture.runner,
            identityPolicy: fixture.policy, sectoriumDeviceObserver: observer,
            portableDocumentWriter: writer)
        let returned = freshProcess.runAutomationAgent(.outerReappeared(uuid: backing))
        #expect(returned.succeeded, "\(String(describing: returned.failure))")
        #expect(returned.steps.contains { $0.step == "profile.\(profile.id).reuseVerifiedImage" })
        #expect(writer.events.contains("\(profile.id):reconnected"))
        #expect(fixture.runner.commands.allSatisfy { !$0.contains("attach") })
    }

    @Test func readOnlyLegacyChainAcceptsMissingEntityUUIDAndUniqueParentInventory() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(fixture.service.identityConfigurationReady)
        let directObservation = fixture.backend.observe()
        #expect(directObservation != nil, "Read-only commands: \(fixture.runner.commands)")
        let discovered = fixture.service.discoveredLegacyDevelopmentDisk()
        #expect(discovered, "Read-only commands: \(fixture.runner.commands)")
        #expect(fixture.service.sectoriumProfiles().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.service.paths.sectoriumProfiles.path))
        #expect(fixture.runner.commands.allSatisfy { command in
            !command.contains("attach") && !command.contains("eject") && !command.contains("unmount")
                && !command.contains("create") && !command.contains("install")
        })
    }

    @Test func legacyDiscoveryBelongsOnlyToSelectedVerifiedMotherDrive() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let mother = "disk90"
        fixture.runner.mountParentWholeDisk = mother
        let backing = SectoriumVolumeMember(volumeUUID: fixture.policy.outerUUID,
            bsdName: "disk90s1", mountPoint: fixture.policy.outerMountPoint)
        let device = SectoriumPhysicalDevice(id: fixture.policy.outerUUID.uuidString, bsdName: mother,
            name: "External Fixture", isExternal: true, identityVerified: true,
            wholeDeviceBytes: 1000, mountedVolumePaths: [fixture.policy.outerMountPoint],
            volumeUUIDs: [fixture.policy.outerUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [backing], topologyComplete: true, isVirtual: false,
            identityBasis: .uniqueBackingVolumeUUID)
        #expect(fixture.service.discoveredLegacyDevelopmentDisk(deviceID: device.id, devices: [device]))
        let observedDEV = try #require(fixture.backend.observe()?.dev)
        let devUUID = try #require(observedDEV.uuid)
        let virtualDEV = SectoriumPhysicalDevice(id: "virtual-disk93", bsdName: "disk93",
            name: "APFS container", isExternal: false, identityVerified: false,
            wholeDeviceBytes: nil, mountedVolumePaths: [observedDEV.mountPoint], volumeUUIDs: [devUUID],
            readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: devUUID, bsdName: "disk93s1",
                                  mountPoint: observedDEV.mountPoint, name: observedDEV.name,
                                  capacityBytes: 321_912_791_040)], isVirtual: true)
        #expect(fixture.service.legacyDevelopmentDisplay(deviceID: device.id,
            devices: [device, virtualDEV])?.logicalCapacityBytes == 321_912_791_040)
        let mountedInventory = try #require(fixture.runner.imageInventory)
        fixture.runner.imageInventory = []
        let detached = try #require(fixture.service.legacyDevelopmentDisplay(deviceID: device.id,
            devices: [device, virtualDEV]))
        #expect(detached.state == .unmounted && detached.mountPoint == nil && detached.logicalCapacityBytes == nil)
        #expect(fixture.service.sectoriumReadiness(deviceID: device.id,
            devices: [device, virtualDEV], profiles: []) == .notStarted)
        #expect(!fixture.service.discoveredLegacyDevelopmentDisk(deviceID: device.id, devices: [device, virtualDEV]))
        fixture.runner.imageInventory = nil
        let uncertain = try #require(fixture.service.legacyDevelopmentDisplay(deviceID: device.id,
            devices: [device, virtualDEV]))
        #expect(uncertain.state == .unknown && uncertain.mountPoint == nil && uncertain.logicalCapacityBytes == nil)
        #expect(fixture.service.sectoriumReadiness(deviceID: device.id,
            devices: [device, virtualDEV], profiles: [])
            == .unknown("Configured development disk state could not be verified"))
        fixture.runner.mountParentWholeDisk = "disk91"
        #expect(fixture.service.legacyDevelopmentDisplay(deviceID: device.id,
            devices: [device, virtualDEV]) == nil)
        fixture.runner.mountParentWholeDisk = mother
        fixture.runner.imageInventory = mountedInventory
        let duplicateVirtual = SectoriumPhysicalDevice(id: "virtual-disk94", bsdName: "disk94",
            name: "Unrelated container", isExternal: false, identityVerified: false,
            wholeDeviceBytes: nil, mountedVolumePaths: [observedDEV.mountPoint], volumeUUIDs: [devUUID],
            readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: devUUID, bsdName: "disk94s1",
                                  mountPoint: observedDEV.mountPoint, capacityBytes: 1)], isVirtual: true)
        #expect(fixture.service.legacyDevelopmentDisplay(deviceID: device.id,
            devices: [device, virtualDEV, duplicateVirtual])?.logicalCapacityBytes == nil)
        let wrongMount = SectoriumPhysicalDevice(id: "virtual-disk95", bsdName: "disk95",
            name: "Wrong mount", isExternal: false, identityVerified: false,
            wholeDeviceBytes: nil, mountedVolumePaths: ["/Volumes/Other"], volumeUUIDs: [devUUID],
            readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: devUUID, bsdName: "disk95s1",
                                  mountPoint: "/Volumes/Other", capacityBytes: 999)], isVirtual: true)
        #expect(fixture.service.legacyDevelopmentDisplay(deviceID: device.id,
            devices: [device, virtualDEV, wrongMount])?.logicalCapacityBytes == nil)
        #expect(fixture.service.sectoriumReadiness(deviceID: device.id, devices: [device], profiles: []) == .connected)
        let unrelated = (1...3).map { index in
            SectoriumDevelopmentProfile(name: "Other\(index)", deviceID: UUID().uuidString,
                backingVolumeUUID: UUID(), backingMountPoint: "/Volumes/Other",
                imagePath: "/Volumes/Other/Other\(index).sparsebundle",
                devVolumeName: "Other\(index)", devMountPoint: "/Volumes/Other\(index)-DEV",
                encrypted: nil, caseSensitive: nil, logicalCapacityBytes: nil)
        }
        try FileManager.default.createDirectory(at: fixture.service.paths.sectoriumProfiles.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(unrelated).write(to: fixture.service.paths.sectoriumProfiles, options: .atomic)
        #expect(fixture.service.discoveredLegacyDevelopmentDisk(deviceID: device.id, devices: [device]))
        #expect(fixture.service.sectoriumReadiness(deviceID: device.id, devices: [device], profiles: unrelated) == .connected)
        fixture.service.selectSectoriumDevice(device.id, observedBSDName: mother, observedDevice: device)
        let displayChanged = SectoriumPhysicalDevice(id: device.id, bsdName: mother,
            name: "Renamed external hardware", isExternal: true, identityVerified: true,
            wholeDeviceBytes: 1000, mountedVolumePaths: [fixture.policy.outerMountPoint],
            volumeUUIDs: [fixture.policy.outerUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: fixture.policy.outerUUID, bsdName: "disk90s1",
                                  mountPoint: fixture.policy.outerMountPoint, name: "HE renamed",
                                  capacityBytes: 1_000)], topologyComplete: true, isVirtual: false,
            identityBasis: .uniqueBackingVolumeUUID)
        #expect(fixture.service.discoveredLegacyDevelopmentDisk(deviceID: device.id, devices: [displayChanged]))
        let reattached = SectoriumPhysicalDevice(id: device.id, bsdName: "disk92", name: "External Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: 1000,
            mountedVolumePaths: [fixture.policy.outerMountPoint], volumeUUIDs: [fixture.policy.outerUUID],
            readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: fixture.policy.outerUUID, bsdName: "disk92s1",
                                  mountPoint: fixture.policy.outerMountPoint)],
            topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID)
        fixture.runner.mountParentWholeDisk = "disk92"
        #expect(!fixture.service.discoveredLegacyDevelopmentDisk(deviceID: device.id, devices: [reattached]))
        #expect(fixture.service.sectoriumReadiness(deviceID: device.id, devices: [reattached], profiles: [])
            == .unknown("Drive attachment or topology changed; reselect the physical drive before management"))
        fixture.runner.mountParentWholeDisk = mother
        let other = SectoriumPhysicalDevice(id: UUID().uuidString, bsdName: "disk91", name: "Other",
            isExternal: true, identityVerified: true, wholeDeviceBytes: 1000,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil, isVirtual: false)
        #expect(!fixture.service.discoveredLegacyDevelopmentDisk(deviceID: other.id, devices: [device, other]))
        #expect(fixture.service.sectoriumReadiness(deviceID: other.id, devices: [device, other], profiles: []) == .noDevelopmentDisk)
        fixture.runner.mountParentWholeDisk = "disk91"
        #expect(!fixture.service.discoveredLegacyDevelopmentDisk(deviceID: device.id, devices: [device]))
        #expect(Set(fixture.service.sectoriumProfiles().map(\.id)) == Set(unrelated.map(\.id)))
    }

    @Test("Partial image inventory cannot establish a detached legacy disk")
    func partialImageInventoryRemainsUnknown() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.runner.mountParentWholeDisk = "disk90"
        let backing = SectoriumVolumeMember(volumeUUID: fixture.policy.outerUUID,
            bsdName: "disk90s1", mountPoint: fixture.policy.outerMountPoint)
        let device = SectoriumPhysicalDevice(id: fixture.policy.outerUUID.uuidString, bsdName: "disk90",
            name: "External Fixture", isExternal: true, identityVerified: true, wholeDeviceBytes: 1000,
            mountedVolumePaths: [fixture.policy.outerMountPoint], volumeUUIDs: [fixture.policy.outerUUID],
            readBytes: nil, writtenBytes: nil, volumeMembers: [backing], topologyComplete: true,
            isVirtual: false, identityBasis: .uniqueBackingVolumeUUID)

        fixture.runner.imageInventory = []
        #expect(fixture.service.legacyDevelopmentDisplay(deviceID: device.id, devices: [device])?.state == .unmounted)
        #expect(fixture.service.sectoriumReadiness(deviceID: device.id, devices: [device], profiles: []) == .notStarted)
        fixture.runner.imageInventory = [["image-path": "/Volumes/Other/unrelated.sparsebundle"]]
        #expect(fixture.service.legacyDevelopmentDisplay(deviceID: device.id, devices: [device])?.state == .unmounted)
        fixture.runner.imageInventory = nil
        #expect(fixture.service.legacyDevelopmentDisplay(deviceID: device.id, devices: [device])?.state == .unknown)

        let partialRecords: [[String: Any]] = [
            [:], ["image-path": NSNumber(value: 123)], ["image-path": ""]
        ]
        for record in partialRecords {
            fixture.runner.imageInventory = [record]
            let display = try #require(fixture.service.legacyDevelopmentDisplay(deviceID: device.id, devices: [device]))
            #expect(display.state == .unknown)
            #expect(display.mountPoint == nil && display.logicalCapacityBytes == nil)
            #expect(fixture.service.sectoriumReadiness(deviceID: device.id, devices: [device], profiles: [])
                == .unknown("Configured development disk state could not be verified"))
        }
        fixture.runner.imageInventory = [["image-path": fixture.policy.imagePath], ["image-path": fixture.policy.imagePath]]
        #expect(fixture.service.legacyDevelopmentDisplay(deviceID: device.id, devices: [device])?.state == .unknown)
        #expect(fixture.service.sectoriumProfiles().isEmpty)
        #expect(fixture.runner.commands.allSatisfy {
            !$0.contains("create") && !$0.contains("attach") && !$0.contains("eject")
        })
    }

    @Test func conflictingOrAmbiguousReadOnlyChainCannotBecomeDiscovered() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let base = try #require(fixture.runner.imageInventory)
        var conflicting = base[0]
        var entities = try #require(conflicting["system-entities"] as? [[String: Any]])
        entities[entities.count - 1]["volume-uuid"] = UUID().uuidString
        conflicting["system-entities"] = entities
        fixture.runner.imageInventory = [conflicting]
        #expect(!fixture.service.discoveredLegacyDevelopmentDisk())
        fixture.runner.imageInventory = base + base
        #expect(!fixture.service.discoveredLegacyDevelopmentDisk())
        fixture.runner.imageInventory = base
        let inventory = try #require(fixture.runner.diskInventory)
        fixture.runner.diskInventory = inventory + inventory
        #expect(!fixture.service.discoveredLegacyDevelopmentDisk())
        fixture.runner.diskInventory = inventory
        let noConfig = HESectoriumService(paths: HESectoriumPaths(root: fixture.root.appendingPathComponent("no-config-support")),
            backend: MacStorageBackend(paths: fixture.service.paths, runner: fixture.runner, policy: fixture.policy),
            store: WorkbenchMemoryStore(), operationLock: WorkbenchMemoryLock(),
            installer: workbenchFixtureInstaller(HESectoriumPaths(root: fixture.root.appendingPathComponent("no-config-support"))),
            runner: fixture.runner, portableDocumentWriter: WorkbenchPortableWriter())
        #expect(!noConfig.discoveredLegacyDevelopmentDisk())
        #expect(fixture.service.sectoriumProfiles().isEmpty)
    }

    private func makeFixture() throws -> (root: URL, runner: WorkbenchFixtureRunner,
                                         service: HESectoriumService, policy: StorageIdentityPolicy,
                                         backend: MacStorageBackend) {
        let requestedRoot = URL(fileURLWithPath: "/private/tmp/sectorium-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: true)
        let root = requestedRoot.resolvingSymlinksInPath()
        let outer = root.appendingPathComponent("outer", isDirectory: true)
        let dev = outer.appendingPathComponent("dev", isDirectory: true)
        let image = outer.appendingPathComponent("fixture.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: true)
        let outerUUID = UUID(), devUUID = UUID()
        let policy = StorageIdentityPolicy(outerUUID: outerUUID, devUUID: devUUID,
            outerMountPoint: outer.path, devMountPoint: dev.path, devVolumeName: "Fixture DEV", imagePath: image.path)
        let runner = WorkbenchFixtureRunner(mountPoint: outer.path, volumeUUID: outerUUID)
        runner.imageBackingDevice = "disk90s1"
        runner.diskInventory = [["DeviceIdentifier": "disk90", "Partitions": [["DeviceIdentifier": "disk90s1"]]]]
        runner.additionalDiskInfos = [
            "/dev/disk90s1": ["DeviceIdentifier": "disk90s1", "VolumeUUID": outerUUID.uuidString,
                                "MountPoint": outer.path, "FilesystemType": "ExFAT", "WritableVolume": true],
            "/dev/disk90": ["DeviceIdentifier": "disk90", "VirtualOrPhysical": "Physical"],
            dev.path: ["DeviceIdentifier": "disk89s1", "VolumeUUID": devUUID.uuidString,
                       "MountPoint": dev.path, "FilesystemType": "APFS", "WritableVolume": true,
                       "VolumeName": "Fixture DEV", "APFSContainerReference": "disk89"],
            "/dev/disk89s1": ["DeviceIdentifier": "disk89s1", "VolumeUUID": devUUID.uuidString,
                                "MountPoint": dev.path, "FilesystemType": "APFS", "WritableVolume": true,
                                "VolumeName": "Fixture DEV", "APFSContainerReference": "disk89"]
        ]
        runner.imageInventory = [["image-path": image.path, "system-entities": [
            ["dev-entry": "/dev/disk88"], ["dev-entry": "/dev/disk88s2"],
            ["dev-entry": "/dev/disk89"],
            ["dev-entry": "/dev/disk89s1", "mount-point": dev.path]
        ]]]
        runner.apfsContainers = [["ContainerReference": "disk89",
            "PhysicalStores": [["DeviceIdentifier": "disk88s2"]],
            "Volumes": [["DeviceIdentifier": "disk89s1", "APFSVolumeUUID": devUUID.uuidString]]]]
        let paths = HESectoriumPaths(root: root.appendingPathComponent("support"))
        let backend = MacStorageBackend(paths: paths, runner: runner, policy: policy)
        let service = HESectoriumService(paths: paths, backend: backend, store: WorkbenchMemoryStore(),
            operationLock: WorkbenchMemoryLock(), installer: workbenchFixtureInstaller(paths),
            runner: runner, identityPolicy: policy, portableDocumentWriter: WorkbenchPortableWriter())
        return (root, runner, service, policy, backend)
    }
}
