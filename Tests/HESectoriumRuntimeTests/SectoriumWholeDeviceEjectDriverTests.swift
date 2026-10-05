import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

private final class EjectFixtureObserver: SectoriumDeviceObserving {
    var devices: [SectoriumPhysicalDevice]
    init(_ devices: [SectoriumPhysicalDevice]) { self.devices = devices }
    func observeDevices() throws -> [SectoriumPhysicalDevice] { devices }
}

private final class EjectFixtureRunner: HESectoriumTimedCommandRunning {
    let observer: EjectFixtureObserver
    private(set) var calls: [[String]] = []
    var imageInventory: [[String: Any]] = []
    var dfSourceByPath: [String: String] = [:]
    var diskInfoByBSD: [String: [String: Any]] = [:]
    var apfsContainers: [[String: Any]] = []
    var dfAvailable = true
    var failVolumeBSD: String?
    var addUnexpectedMemberAfterUnmount = false
    var timeoutArguments: [String]?
    init(observer: EjectFixtureObserver) {
        self.observer = observer
        diskInfoByBSD = [
            "disk1": ["DeviceIdentifier": "disk1", "VirtualOrPhysical": "Physical"],
            "disk1s1": ["DeviceIdentifier": "disk1s1", "VirtualOrPhysical": "Physical", "PartOfWhole": "disk1"],
            "disk81": ["DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical"],
            "disk81s1": ["DeviceIdentifier": "disk81s1", "VirtualOrPhysical": "Physical", "PartOfWhole": "disk81"]
        ]
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        if arguments == timeoutArguments {
            calls.append([executable] + arguments)
            return .init(exitCode: -1, detail: "fixture command timed out")
        }
        return run(executable, arguments, cwd: cwd)
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        calls.append([executable] + arguments)
        if executable == "/usr/bin/hdiutil", arguments == ["info", "-plist"] {
            return plist(["images": imageInventory])
        }
        if executable == "/usr/bin/hdiutil", arguments.count == 2,
           arguments[0] == "detach", arguments[1].hasPrefix("/dev/disk") {
            let bsd = String(arguments[1].dropFirst("/dev/".count))
            imageInventory.removeAll { row in
                (row["system-entities"] as? [[String: Any]])?.contains {
                    ($0["dev-entry"] as? String) == "/dev/\(bsd)"
                } == true
            }
            observer.devices.removeAll { $0.bsdName == bsd }
            return .success
        }
        if executable == "/usr/sbin/diskutil", arguments.first == "unmount",
           arguments.count == 2, arguments[1].hasPrefix("/dev/disk90s") {
            let bsd = arguments[1]
            imageInventory = imageInventory.map { row in
                var copy = row
                copy["system-entities"] = (row["system-entities"] as? [[String: Any]])?.map { entity in
                    var value = entity
                    if value["dev-entry"] as? String == bsd { value.removeValue(forKey: "mount-point") }
                    return value
                }
                return copy
            }
            return .success
        }
        if executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", "/"] {
            return plist(["DeviceIdentifier": "disk1s1"])
        }
        if executable == "/usr/sbin/diskutil", arguments.count == 3,
           arguments[0] == "info", arguments[1] == "-plist", arguments[2].hasPrefix("/dev/") {
            let bsd = String(arguments[2].dropFirst("/dev/".count))
            return diskInfoByBSD[bsd].map(plist) ?? .init(exitCode: 127, detail: "missing fixture disk identity")
        }
        if executable == "/usr/sbin/diskutil", arguments == ["apfs", "list", "-plist"] {
            return plist(["Containers": apfsContainers])
        }
        if executable == "/bin/df", arguments.count == 2, arguments[0] == "-P" {
            guard dfAvailable else { return .init(exitCode: 1, detail: "fixture volume observation unavailable") }
            let path = arguments[1]
            let source = dfSourceByPath.first(where: { path == $0.key || path.hasPrefix($0.key + "/") })?.value ?? "/dev/disk1s1"
            return .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity Mounted on\n\(source) 1000 10 990 1% /fixture\n")
        }
        if executable == "/usr/sbin/diskutil", arguments.first == "unmount",
           arguments.count == 2, arguments[1].hasPrefix("/dev/disk81s") {
            let bsd = String(arguments[1].dropFirst("/dev/".count))
            if bsd == failVolumeBSD { return .init(exitCode: 1, detail: "Resource busy") }
            updateMember(bsd, mounted: false)
            return .success
        }
        if executable == "/usr/sbin/diskutil", arguments == ["eject", "/dev/disk81"] {
            observer.devices = []
            return .success
        }
        return .init(exitCode: 127, detail: "unconfigured isolated fixture command")
    }

    private func updateMember(_ bsd: String, mounted: Bool) {
        observer.devices = observer.devices.map { device in
            guard device.bsdName == "disk81" else { return device }
            var members = device.volumeMembers.map { member in
                member.bsdName == bsd ? SectoriumPhysicalVolumeMember(bsdName: member.bsdName,
                    volumeUUID: member.volumeUUID, mounted: mounted, mountPoint: mounted ? member.mountPoint : nil) : member
            }
            var volumeUUIDs = device.volumeUUIDs
            if addUnexpectedMemberAfterUnmount {
                addUnexpectedMemberAfterUnmount = false
                let addedUUID = UUID()
                volumeUUIDs.append(addedUUID)
                members.append(.init(bsdName: "disk81s9", volumeUUID: addedUUID, mounted: true, mountPoint: "/Volumes/New"))
            }
            return SectoriumPhysicalDevice(id: device.id, bsdName: device.bsdName, name: device.name,
                isExternal: device.isExternal, identityVerified: device.identityVerified,
                wholeDeviceBytes: device.wholeDeviceBytes, mountedVolumePaths: [],
                volumeUUIDs: volumeUUIDs, readBytes: nil, writtenBytes: nil,
                volumeMembers: members, topologyComplete: device.topologyComplete, isVirtual: device.isVirtual,
                identityBasis: device.identityBasis, wholeMediaUUID: device.wholeMediaUUID,
                requiresFreshParentCheck: device.requiresFreshParentCheck,
                apfsContainers: device.apfsContainers,
                hasAmbiguousPhysicalStores: device.hasAmbiguousPhysicalStores)
        }
    }

    private func plist(_ value: [String: Any]) -> CommandOutcome {
        let data = try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
    }

}

private final class EjectFixtureBackend: StorageBackend {
    func observeOuter() -> VolumeIdentity? { nil }
    func observe() -> StorageObservation? { nil }
    func attachImage() -> CommandOutcome { .init(exitCode: 127) }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { .incomplete(reason: "not used") }
    func perform(_ step: EjectStep) -> CommandOutcome { .init(exitCode: 127) }
    func finalOuterState() -> FinalOuterState { .unknown("not used") }
}

private func confirmed(_ topology: WholeDeviceTopology) -> WholeDeviceEjectCheckpoint {
    .init(confirmedExactTargetAndScope: true, knownWritersClosed: true,
          dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: topology.physicalIdentity,
          confirmedMemberKey: topology.memberKey, confirmedAt: Date())
}

private enum DependencyFixtureCase: Equatable { case internalDisk, samePhysicalStore, imageBackedByTarget, symlinkToTarget, unknownIdentity, ambiguousStores }

private func dependencyServiceFixture(_ scenario: DependencyFixtureCase) throws
    -> (confirmationSafe: Bool, mutationCalls: [[String]]) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-dependency-\(UUID().uuidString)", isDirectory: true)
    let targetMount = root.appendingPathComponent("external", isDirectory: true)
    try FileManager.default.createDirectory(at: targetMount, withIntermediateDirectories: true)
    let support: URL
    if scenario == .symlinkToTarget {
        support = root.appendingPathComponent("support-link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: support, withDestinationURL: targetMount)
    } else if scenario == .imageBackedByTarget {
        support = root.appendingPathComponent("virtual-dev", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetMount.appendingPathComponent("dev.sparsebundle"), withIntermediateDirectories: true)
    } else {
        support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    let memberUUID = UUID(), mediaUUID = UUID(), imageVolumeUUID = UUID()
    let target = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture external",
        isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [targetMount.path],
        volumeUUIDs: [memberUUID], readBytes: nil, writtenBytes: nil,
        volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: memberUUID, mounted: true, mountPoint: targetMount.path)],
        topologyComplete: true, isVirtual: false)
    let imageMember = SectoriumPhysicalVolumeMember(bsdName: "disk90s1", volumeUUID: imageVolumeUUID,
        mounted: true, mountPoint: support.path)
    let imageDevice = SectoriumPhysicalDevice(id: "virtual-image", bsdName: "disk90", name: "Fixture image",
        isExternal: false, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [support.path],
        volumeUUIDs: [imageVolumeUUID], readBytes: nil, writtenBytes: nil,
        volumeMembers: [imageMember], topologyComplete: true, isVirtual: true)
    let observer = EjectFixtureObserver(scenario == .imageBackedByTarget ? [target, imageDevice] : [target])
    let runner = EjectFixtureRunner(observer: observer)
    let dependencyPath = support.path
    switch scenario {
    case .internalDisk:
        break
    case .samePhysicalStore:
        runner.dfSourceByPath[dependencyPath] = "/dev/disk90s1"
        runner.diskInfoByBSD["disk90s1"] = ["DeviceIdentifier": "disk90s1", "VirtualOrPhysical": "Physical",
            "APFSContainerReference": "container-on-target"]
        runner.apfsContainers = [["ContainerReference": "container-on-target",
            "PhysicalStores": [["DeviceIdentifier": "disk81s1"]]]]
    case .imageBackedByTarget:
        runner.dfSourceByPath[support.path] = "/dev/disk90s1"
        runner.dfSourceByPath[targetMount.path] = "/dev/disk81s1"
        runner.diskInfoByBSD["disk90s1"] = ["DeviceIdentifier": "disk90s1", "VirtualOrPhysical": "Physical",
            "APFSContainerReference": "container-image"]
        runner.diskInfoByBSD["disk90"] = ["DeviceIdentifier": "disk90", "VirtualOrPhysical": "Virtual"]
        runner.apfsContainers = [["ContainerReference": "container-image",
            "PhysicalStores": [["DeviceIdentifier": "disk90"]]]]
        runner.imageInventory = [["image-path": targetMount.appendingPathComponent("dev.sparsebundle").path,
            "system-entities": [["dev-entry": "/dev/disk90"],
                                ["dev-entry": "/dev/disk90s1", "volume-uuid": imageVolumeUUID.uuidString,
                                 "mount-point": support.path]]]]
    case .symlinkToTarget:
        runner.dfSourceByPath[targetMount.path] = "/dev/disk81s1"
    case .unknownIdentity:
        runner.dfSourceByPath[dependencyPath] = "/dev/disk999s1"
    case .ambiguousStores:
        runner.dfSourceByPath[dependencyPath] = "/dev/disk90s1"
        runner.diskInfoByBSD["disk90s1"] = ["DeviceIdentifier": "disk90s1", "VirtualOrPhysical": "Physical",
            "APFSContainerReference": "container-ambiguous"]
        runner.apfsContainers = [["ContainerReference": "container-ambiguous",
            "PhysicalStores": [["DeviceIdentifier": "disk81s1"], ["DeviceIdentifier": "disk1s1"]]]]
    }

    let service = HESectoriumService(paths: HESectoriumPaths(root: support), backend: EjectFixtureBackend(),
        store: JSONStateStore(url: support.appendingPathComponent("state.json")),
        operationLock: KernelOperationLock(url: support.appendingPathComponent("lock")),
        runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer)
    service.selectSectoriumDevice(mediaUUID.uuidString)
    guard let confirmation = service.prepareWholeDeviceEjectConfirmation() else {
        try? FileManager.default.removeItem(at: root)
        throw NSError(domain: "DependencyFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Runtime confirmation could not observe fixture topology"])
    }
    if !confirmation.dependenciesCanFinishOffTarget {
        _ = service.ejectSelectedExternalDevice(checkpoint: confirmation.checkpoint(knownWritersClosed: true))
    }
    let mutationCalls = runner.calls.filter { call in
        call.first == "/usr/sbin/lsof"
            || (call.first == "/usr/sbin/diskutil" && ["unmount", "eject", "mount"].contains(call.dropFirst().first ?? ""))
            || (call.first == "/usr/bin/hdiutil" && ["attach", "detach", "create"].contains(call.dropFirst().first ?? ""))
    }
    try? FileManager.default.removeItem(at: root)
    return (confirmation.dependenciesCanFinishOffTarget, mutationCalls)
}

@Suite("Whole-device Runtime adapter fixtures")
struct SectoriumWholeDeviceEjectDriverTests {
    @Test("System volume APFS backing rejects a different synthesized BSD name on the target disk")
    func systemVolumeSharingTargetPhysicalStoreIsRejected() throws {
        let mediaUUID = UUID(), memberUUID = UUID()
        let target = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture external",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: ["/Volumes/Target"],
            volumeUUIDs: [memberUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: memberUUID, mounted: true, mountPoint: "/Volumes/Target")],
            topologyComplete: true, isVirtual: false)
        let observer = EjectFixtureObserver([target])
        let runner = EjectFixtureRunner(observer: observer)
        runner.dfSourceByPath["/"] = "/dev/disk90s1"
        runner.diskInfoByBSD["disk90s1"] = ["DeviceIdentifier": "disk90s1", "VirtualOrPhysical": "Physical",
            "APFSContainerReference": "root-container"]
        runner.apfsContainers = [["ContainerReference": "root-container",
            "PhysicalStores": [["DeviceIdentifier": "disk81s1"]]]]

        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory)
        #expect(driver.observe(physicalIdentity: mediaUUID.uuidString) == nil)
        runner.diskInfoByBSD["disk90s1"] = ["DeviceIdentifier": "disk90s1",
            "VirtualOrPhysical": "Physical", "ParentWholeDisk": "disk90", "PartOfWhole": "disk91",
            "APFSContainerReference": "root-container"]
        #expect(driver.observe(physicalIdentity: mediaUUID.uuidString) == nil)
        #expect(!runner.calls.contains { $0.first == "/usr/sbin/diskutil" && $0.dropFirst().first == "eject" })
    }

    @Test("Dependency check resolves physical APFS and image backing at the actual confirmation/eject entry")
    func runtimeDependencySafetyUsesPhysicalAncestry() throws {
        let internalDisk = try dependencyServiceFixture(.internalDisk)
        #expect(internalDisk.confirmationSafe, "A complete dependency chain on a separate built-in disk should be accepted")
        for scenario: DependencyFixtureCase in [.samePhysicalStore, .imageBackedByTarget, .symlinkToTarget,
                                                  .unknownIdentity, .ambiguousStores] {
            let fixture = try dependencyServiceFixture(scenario)
            #expect(!fixture.confirmationSafe, "\(scenario) must refuse confirmation when it shares or cannot prove ancestry")
            #expect(fixture.mutationCalls.isEmpty, "\(scenario) must refuse before any mutating dispatch")
        }
    }

    @Test("Attached image metadata maps only the exact backing volume without persisting its path")
    func imageTopologyUsesPrivateAttachedImageMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whole-eject-image-map-\(UUID().uuidString)", isDirectory: true)
        let outer = root.appendingPathComponent("external", isDirectory: true)
        let physicalImagePath = outer.appendingPathComponent("Work.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: physicalImagePath, withIntermediateDirectories: true)
        let imageAlias = root.appendingPathComponent("alias.sparsebundle")
        try FileManager.default.createSymbolicLink(at: imageAlias, withDestinationURL: physicalImagePath)
        let imagePath = imageAlias
        defer { try? FileManager.default.removeItem(at: root) }
        let outerUUID = UUID(), imageUUID = UUID(), mediaUUID = UUID()
        let target = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [outer.path],
            volumeUUIDs: [outerUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: outerUUID, mounted: true, mountPoint: outer.path)],
            topologyComplete: true, isVirtual: false)
        let imageDevice = SectoriumPhysicalDevice(id: "virtual-image", bsdName: "disk90", name: "Private Image",
            isExternal: false, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [imageUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk90s1", volumeUUID: imageUUID, mounted: true, mountPoint: "/private/tmp/DEV")],
            topologyComplete: true, isVirtual: true)
        let observer = EjectFixtureObserver([target, imageDevice])
        let runner = EjectFixtureRunner(observer: observer)
        runner.imageInventory = [["image-path": imagePath.path, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk90"],
            ["mount-point": "/private/tmp/DEV", "volume-uuid": imageUUID.uuidString, "dev-entry": "/dev/disk90s1"]
        ]]]
        runner.dfSourceByPath[physicalImagePath.path] = "/dev/disk81s1"
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let topology = try #require(driver.observe(physicalIdentity: mediaUUID.uuidString))
        #expect(topology.images == [.init(identity: "image:disk90", attached: true,
            volumeIdentities: ["\(imageUUID.uuidString.lowercased())|disk90s1"],
            mountedVolumeIdentities: ["\(imageUUID.uuidString.lowercased())|disk90s1"])])
        #expect(!topology.memberKey.contains(imagePath.path))
        #expect(!String(describing: topology).contains("Work.sparsebundle"))
        #expect(runner.calls.contains(["/usr/bin/hdiutil", "info", "-plist"]))
    }

    @Test("An image on the selected physical root refuses mismatched or ambiguous virtual topology")
    func imageTopologyRejectsMismatchedAndAmbiguousChains() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whole-eject-image-mismatch-\(UUID().uuidString)", isDirectory: true)
        let outer = root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: outer, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outerUUID = UUID(), reportedImageUUID = UUID(), actualImageUUID = UUID(), mediaUUID = UUID()
        let target = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [outer.path],
            volumeUUIDs: [outerUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: outerUUID, mounted: true, mountPoint: outer.path)],
            topologyComplete: true, isVirtual: false)
        let imageDevice = SectoriumPhysicalDevice(id: "virtual-image", bsdName: "disk90", name: "Private Image",
            isExternal: false, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [actualImageUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk90s1", volumeUUID: actualImageUUID, mounted: true, mountPoint: "/private/tmp/DEV")],
            topologyComplete: true, isVirtual: true)
        let imagePath = outer.appendingPathComponent("Work.sparsebundle", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: imagePath, withIntermediateDirectories: true)
        let mismatchedRow: [String: Any] = ["image-path": imagePath, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk90"],
            ["mount-point": "/private/tmp/DEV", "volume-uuid": reportedImageUUID.uuidString, "dev-entry": "/dev/disk90s1"]
        ]]
        let observer = EjectFixtureObserver([target, imageDevice])
        let runner = EjectFixtureRunner(observer: observer)
        runner.imageInventory = [mismatchedRow]
        runner.dfSourceByPath[imagePath] = "/dev/disk81s1"
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        #expect(driver.observe(physicalIdentity: mediaUUID.uuidString) == nil,
            "An image rooted on the selected physical volume cannot trust a different APFS volume identity")

        let matchingRow: [String: Any] = ["image-path": imagePath, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk90"],
            ["mount-point": "/private/tmp/DEV", "volume-uuid": actualImageUUID.uuidString, "dev-entry": "/dev/disk90s1"]
        ]]
        runner.imageInventory = [matchingRow, matchingRow]
        #expect(driver.observe(physicalIdentity: mediaUUID.uuidString) == nil,
            "Duplicate image-path entries make the selected physical-to-image relation ambiguous")

        let unresolvablePath = outer.appendingPathComponent("unresolvable.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: unresolvablePath, withIntermediateDirectories: true)
        runner.imageInventory = [["image-path": unresolvablePath.path, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk90"],
            ["mount-point": "/private/tmp/DEV", "volume-uuid": actualImageUUID.uuidString,
             "dev-entry": "/dev/disk90s1"]
        ]]]
        runner.dfSourceByPath[unresolvablePath.path] = "/dev/disk999s1"
        #expect(driver.observe(physicalIdentity: mediaUUID.uuidString) == nil,
            "An image whose physical backing cannot be resolved must make the whole inventory unknown")
    }

    @Test("A mounted APFS image volume without hdiutil UUID needs an exact image-store chain")
    func apfsImageChainWithMissingHdiutilUUID() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("r3-image-chain-\(UUID().uuidString)")
        let outer = root.appendingPathComponent("outer", isDirectory: true)
        let image = outer.appendingPathComponent("Fixture.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let physicalID = UUID(), backingID = UUID(), devID = UUID()
        let physical = SectoriumPhysicalDevice(id: physicalID.uuidString, bsdName: "disk81", name: "Physical",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [outer.path],
            volumeUUIDs: [backingID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: backingID, mounted: true, mountPoint: outer.path)],
            topologyComplete: true, isVirtual: false)
        let virtual = SectoriumPhysicalDevice(id: "unverified-disk90", bsdName: "disk90", name: "Image",
            isExternal: false, identityVerified: false, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [], readBytes: nil, writtenBytes: nil, topologyComplete: false, isVirtual: true)
        let observer = EjectFixtureObserver([physical, virtual])
        let runner = EjectFixtureRunner(observer: observer)
        runner.dfSourceByPath[image.path] = "/dev/disk81s1"
        runner.imageInventory = [["image-path": image.path, "system-entities": [
            ["dev-entry": "/dev/disk90"], ["dev-entry": "/dev/disk90s2"],
            ["dev-entry": "/dev/disk91"],
            ["dev-entry": "/dev/disk91s1", "mount-point": "/Volumes/Fixture-DEV"]]]]
        runner.diskInfoByBSD["disk91s1"] = ["DeviceIdentifier": "disk91s1",
            "MountPoint": "/Volumes/Fixture-DEV", "VolumeUUID": devID.uuidString,
            "APFSContainerReference": "disk91"]
        runner.apfsContainers = [["ContainerReference": "disk91",
            "PhysicalStores": [["DeviceIdentifier": "disk90s2"]]]]
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let topology = try #require(driver.observe(physicalIdentity: physicalID.uuidString))
        #expect(topology.images.count == 1)
        #expect(topology.images[0].volumeIdentities == ["\(devID.uuidString.lowercased())|disk91s1"])
        var detachedRow = runner.imageInventory[0]
        var detachedEntities = try #require(detachedRow["system-entities"] as? [[String: Any]])
        detachedEntities[detachedEntities.count - 1].removeValue(forKey: "mount-point")
        detachedRow["system-entities"] = detachedEntities
        runner.imageInventory = [detachedRow]
        runner.diskInfoByBSD["disk91s1"]?.removeValue(forKey: "MountPoint")
        let unmounted = try #require(driver.observe(physicalIdentity: physicalID.uuidString))
        #expect(unmounted.images[0].volumeIdentities == topology.images[0].volumeIdentities)
        #expect(unmounted.images[0].mountedVolumeIdentities == [])
        runner.apfsContainers = [["ContainerReference": "disk91",
            "PhysicalStores": [["DeviceIdentifier": "disk99s2"]]]]
        #expect(driver.observe(physicalIdentity: physicalID.uuidString) == nil)
    }

    @Test("After Stop, profile-free multi-volume external eject persists and returns in a fresh controller")
    func profileFreeMultiVolumeEjectAndReturn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whole-eject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let externalRoot = root.appendingPathComponent("external", isDirectory: true)
        let imagePath = externalRoot.appendingPathComponent("Work.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: imagePath, withIntermediateDirectories: true)
        let firstUUID = UUID(), secondUUID = UUID(), mediaUUID = UUID()
        let imageUUID = UUID()
        let device = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "External Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil,
            mountedVolumePaths: [externalRoot.path], volumeUUIDs: [firstUUID, secondUUID],
            readBytes: nil, writtenBytes: nil,
            volumeMembers: [
                .init(bsdName: "disk81s1", volumeUUID: firstUUID, mounted: true, mountPoint: externalRoot.path),
                .init(bsdName: "disk81s2", volumeUUID: secondUUID, mounted: true, mountPoint: externalRoot.path)
            ], topologyComplete: true, isVirtual: false)
        let imageDevice = SectoriumPhysicalDevice(id: "virtual-image", bsdName: "disk90", name: "Fixture image",
            isExternal: false, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: ["/Volumes/DEV"],
            volumeUUIDs: [imageUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk90s1", volumeUUID: imageUUID, mounted: true, mountPoint: "/Volumes/DEV")],
            topologyComplete: true, isVirtual: true)
        let observer = EjectFixtureObserver([device, imageDevice])
        let runner = EjectFixtureRunner(observer: observer)
        runner.imageInventory = [["image-path": imagePath.path, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk90"],
            ["mount-point": "/Volumes/DEV", "volume-uuid": imageUUID.uuidString, "dev-entry": "/dev/disk90s1"]
        ]]]
        runner.dfSourceByPath[imagePath.path] = "/dev/disk81s1"
        let stateURL = root.appendingPathComponent("state.json")
        let controller = StorageController(backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let topology = try #require(driver.observe(physicalIdentity: mediaUUID.uuidString))
        let result = controller.ejectWholeExternalDevice(physicalIdentity: mediaUUID.uuidString,
            checkpoint: confirmed(topology), driver: driver)

        #expect(result.succeeded)
        #expect(result.completedSteps.contains("ejectWholeDevice"))
        #expect(runner.calls.filter { $0.first == "/usr/sbin/diskutil" && $0.dropFirst().first == "unmount" }.count == 3)
        #expect(runner.calls.contains(["/usr/sbin/diskutil", "unmount", "/dev/disk90s1"]))
        #expect(runner.calls.contains(["/usr/bin/hdiutil", "detach", "/dev/disk90"]))
        #expect(runner.calls.contains(["/usr/sbin/diskutil", "eject", "/dev/disk81"]))
        #expect(!runner.calls.contains { $0.first == "/usr/sbin/lsof" })
        let saved = try JSONStateStore(url: stateURL).load()
        #expect(saved.ejectIntent)
        #expect(saved.workbenchTerminalResult == "safe-to-unplug")
        #expect(saved.workbenchTarget != nil)

        // Simulate a later device reconnect and a new process/controller. Return is separate
        // and requires both the exact physical member set and the Runtime APFS validator.
        observer.devices = [SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "External Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [firstUUID, secondUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [
                .init(bsdName: "disk81s1", volumeUUID: firstUUID, mounted: true, mountPoint: "/Volumes/A"),
                .init(bsdName: "disk81s2", volumeUUID: secondUUID, mounted: true, mountPoint: "/Volumes/B")
            ], topologyComplete: true, isVirtual: false)]
        let returningDriver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root, independentReturnValidator: { _ in true })
        let freshController = StorageController(backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        #expect(freshController.returnFromWholeDeviceEject(driver: returningDriver))
        #expect(try JSONStateStore(url: stateURL).load().ejectIntent == false)
    }

    @Test("No-whole-media anchored eject retains intent and returns through a fresh controller")
    func anchoredEjectAndFreshReturn() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("anchored-eject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backing = UUID()
        func physical(mounted: Bool) -> SectoriumPhysicalDevice {
            SectoriumPhysicalDevice(id: backing.uuidString, bsdName: "disk81", name: "Anchored Fixture",
                isExternal: true, identityVerified: true, wholeDeviceBytes: nil,
                mountedVolumePaths: mounted ? ["/Volumes/Fixture"] : [], volumeUUIDs: [backing],
                readBytes: nil, writtenBytes: nil,
                volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: backing,
                                      mounted: mounted, mountPoint: mounted ? "/Volumes/Fixture" : nil)],
                topologyComplete: true, isVirtual: false,
                identityBasis: .uniqueBackingVolumeUUID, wholeMediaUUID: nil,
                requiresFreshParentCheck: true)
        }
        let observer = EjectFixtureObserver([physical(mounted: true)])
        let runner = EjectFixtureRunner(observer: observer)
        let stateURL = root.appendingPathComponent("state.json")
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let topology = try #require(driver.observe(physicalIdentity: backing.uuidString))
        let controller = StorageController(backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        let result = controller.ejectWholeExternalDevice(physicalIdentity: backing.uuidString,
            checkpoint: confirmed(topology), driver: driver)
        #expect(result.succeeded)
        #expect(try JSONStateStore(url: stateURL).load().ejectIntent)
        #expect(runner.calls.contains(["/usr/sbin/diskutil", "eject", "/dev/disk81"]))
        observer.devices = [physical(mounted: true)]
        let freshDriver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root, independentReturnValidator: { _ in true })
        let freshController = StorageController(backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        #expect(freshController.returnFromWholeDeviceEject(driver: freshDriver))
        #expect(try !JSONStateStore(url: stateURL).load().ejectIntent)
    }

    @Test("Missing virtual topology, local targets and dependency uncertainty fail closed before mutation")
    func unsafeTargetsAndUnknownDependenciesAreRefused() throws {
        let uuid = UUID()
        let local = SectoriumPhysicalDevice(id: uuid.uuidString, bsdName: "disk81", name: "Local",
            isExternal: false, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [UUID()], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: UUID(), mounted: true, mountPoint: "/Volumes/L")],
            topologyComplete: true, isVirtual: false)
        let observer = EjectFixtureObserver([local])
        let runner = EjectFixtureRunner(observer: observer)
        runner.dfAvailable = false
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: FileManager.default.temporaryDirectory)
        #expect(driver.observe(physicalIdentity: uuid.uuidString) == nil)
        observer.devices = [SectoriumPhysicalDevice(id: uuid.uuidString, bsdName: "disk81", name: "External Unknown",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [UUID()], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: UUID(), mounted: true, mountPoint: "/Volumes/U")],
            topologyComplete: true, isVirtual: nil)]
        #expect(driver.observe(physicalIdentity: uuid.uuidString) == nil)
        #expect(!SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: HESectoriumPaths(root: URL(fileURLWithPath: "/missing/fixture")),
            targetBSDName: "disk81", runner: runner))
        let physicalTarget = SectoriumPhysicalDevice(id: uuid.uuidString, bsdName: "disk81", name: "External Known",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [UUID()], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: UUID(), mounted: false, mountPoint: nil)],
            topologyComplete: true, isVirtual: false)
        let unrelatedVirtual = SectoriumPhysicalDevice(id: UUID().uuidString, bsdName: "disk90", name: "Unrelated Virtual",
            isExternal: false, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [UUID()], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk90s1", volumeUUID: UUID(), mounted: false, mountPoint: nil)],
            topologyComplete: true, isVirtual: true)
        observer.devices = [physicalTarget, unrelatedVirtual]
        runner.dfAvailable = true // Restore a complete independent system-volume ancestry observation.
        #expect(driver.observe(physicalIdentity: uuid.uuidString) != nil,
            "An unrelated virtual disk must not veto an otherwise exact external physical target")
        #expect(!runner.calls.contains { $0.first == "/usr/sbin/diskutil" && $0.dropFirst().first == "eject" })
    }

    @Test("Busy second member records first member partial completion and stops before whole eject")
    func partialUnmountIsDurable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whole-eject-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstUUID = UUID(), secondUUID = UUID(), mediaUUID = UUID()
        let device = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [firstUUID, secondUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [
                .init(bsdName: "disk81s1", volumeUUID: firstUUID, mounted: true, mountPoint: "/Volumes/A"),
                .init(bsdName: "disk81s2", volumeUUID: secondUUID, mounted: true, mountPoint: "/Volumes/B")
            ], topologyComplete: true, isVirtual: false)
        let observer = EjectFixtureObserver([device])
        let runner = EjectFixtureRunner(observer: observer); runner.failVolumeBSD = "disk81s2"
        let stateURL = root.appendingPathComponent("state.json")
        let controller = StorageController(backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let topology = try #require(driver.observe(physicalIdentity: mediaUUID.uuidString))
        let result = controller.ejectWholeExternalDevice(physicalIdentity: mediaUUID.uuidString,
            checkpoint: confirmed(topology), driver: driver)
        #expect(!result.succeeded)
        #expect(result.completedSteps == ["unmountPhysicalVolume:\(firstUUID.uuidString.lowercased())|disk81s1"])
        #expect(!runner.calls.contains { $0.first == "/usr/sbin/diskutil" && $0.dropFirst().first == "eject" })
        let saved = try JSONStateStore(url: stateURL).load()
        #expect(saved.ejectIntent)
        #expect(saved.workbenchPhase == "eject:interrupted")
        #expect(saved.workbenchCompletedStep == "unmountPhysicalVolume:\(firstUUID.uuidString.lowercased())|disk81s1")

        // A new explicit checkpoint may continue only the exact durable physical-unmount
        // boundary. Fresh Runtime observation skips disk81s1 because its receipt is durable
        // and it is already unmounted; only disk81s2 is dispatched on continuation.
        try JSONEncoder().encode([SectoriumDevelopmentProfile]()).write(
            to: root.appendingPathComponent("sectorium-profiles.json"), options: .atomic)
        let service = HESectoriumService(paths: HESectoriumPaths(root: root),
            backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            operationLock: KernelOperationLock(url: root.appendingPathComponent("lock")),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer)
        service.selectSectoriumDevice(mediaUUID.uuidString)
        let continuationPrompt = try #require(service.prepareContinueWholeDeviceEjectConfirmation())
        #expect(continuationPrompt.isContinuation)
        #expect(continuationPrompt.physicalIdentity == mediaUUID.uuidString)
        #expect(continuationPrompt.dependenciesCanFinishOffTarget)
        runner.failVolumeBSD = nil
        let beforeContinuation = runner.calls.count
        let continuation = service.continueWholeDeviceEject(
            checkpoint: continuationPrompt.checkpoint(knownWritersClosed: true))
        #expect(continuation.succeeded)
        let resumedCalls = Array(runner.calls.dropFirst(beforeContinuation))
        #expect(resumedCalls.contains(["/usr/sbin/diskutil", "unmount", "/dev/disk81s2"]))
        #expect(!resumedCalls.contains(["/usr/sbin/diskutil", "unmount", "/dev/disk81s1"]))
        #expect(resumedCalls.contains(["/usr/sbin/diskutil", "eject", "/dev/disk81"]))
    }

    @Test("Timed-out non-force member unmount retains intent and never issues whole-device eject")
    func timedOutUnmountStopsAndPersistsIntent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whole-eject-timeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let memberUUID = UUID(), mediaUUID = UUID()
        let device = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [memberUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: memberUUID, mounted: true, mountPoint: "/Volumes/A")],
            topologyComplete: true, isVirtual: false)
        let observer = EjectFixtureObserver([device])
        let runner = EjectFixtureRunner(observer: observer)
        runner.timeoutArguments = ["unmount", "/dev/disk81s1"]
        let stateURL = root.appendingPathComponent("state.json")
        let controller = StorageController(backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let topology = try #require(driver.observe(physicalIdentity: mediaUUID.uuidString))
        let result = controller.ejectWholeExternalDevice(physicalIdentity: mediaUUID.uuidString,
            checkpoint: confirmed(topology), driver: driver)
        #expect(!result.succeeded)
        #expect(runner.calls.contains(["/usr/sbin/diskutil", "unmount", "/dev/disk81s1"]))
        #expect(!runner.calls.contains(["/usr/sbin/diskutil", "eject", "/dev/disk81"]))
        #expect(try JSONStateStore(url: stateURL).load().ejectIntent)
    }

    @Test("A newly observed member after the unmount stops before eject and is durably reflected")
    func memberDriftStopsEject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whole-eject-drift-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let memberUUID = UUID(), mediaUUID = UUID()
        let device = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [memberUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: memberUUID, mounted: true, mountPoint: "/Volumes/A")],
            topologyComplete: true, isVirtual: false)
        let observer = EjectFixtureObserver([device])
        let runner = EjectFixtureRunner(observer: observer); runner.addUnexpectedMemberAfterUnmount = true
        let stateURL = root.appendingPathComponent("state.json")
        let controller = StorageController(backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let topology = try #require(driver.observe(physicalIdentity: mediaUUID.uuidString))
        let result = controller.ejectWholeExternalDevice(physicalIdentity: mediaUUID.uuidString,
            checkpoint: confirmed(topology), driver: driver)
        #expect(!result.succeeded)
        #expect(!runner.calls.contains { $0.first == "/usr/sbin/diskutil" && $0.dropFirst().first == "eject" })
        let saved = try JSONStateStore(url: stateURL).load()
        #expect(saved.ejectIntent)
        #expect(saved.workbenchPhase == "eject:interrupted")
        #expect(saved.workbenchCompletedStep == "unmountAllPhysicalVolumes")
    }

    @Test("A fresh service can Return a profile-free eject after exact physical identity reconnects")
    func profileFreeReturnUsesFreshPhysicalIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whole-eject-profile-free-return-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let memberUUID = UUID(), mediaUUID = UUID()
        let device = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: ["/Volumes/A"],
            volumeUUIDs: [memberUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: memberUUID, mounted: true, mountPoint: "/Volumes/A")],
            topologyComplete: true, isVirtual: false)
        let observer = EjectFixtureObserver([device])
        let runner = EjectFixtureRunner(observer: observer)
        let stateURL = root.appendingPathComponent("state.json")
        let service = HESectoriumService(paths: HESectoriumPaths(root: root), backend: EjectFixtureBackend(),
            store: JSONStateStore(url: stateURL), operationLock: KernelOperationLock(url: root.appendingPathComponent("lock")),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer)
        service.selectSectoriumDevice(mediaUUID.uuidString)
        let topology = try #require(SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root).observe(physicalIdentity: mediaUUID.uuidString))
        let result = service.ejectSelectedExternalDevice(checkpoint: confirmed(topology))
        #expect(result.succeeded)
        observer.devices = [device]
        let freshService = HESectoriumService(paths: HESectoriumPaths(root: root), backend: EjectFixtureBackend(),
            store: JSONStateStore(url: stateURL), operationLock: KernelOperationLock(url: root.appendingPathComponent("lock")),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer)
        freshService.selectSectoriumDevice(mediaUUID.uuidString)
        let returned = freshService.returnToDevelopment()
        #expect(returned.succeeded, "\(String(describing: returned.failure))")
        #expect(try JSONStateStore(url: stateURL).load().ejectIntent == false)
    }

    @Test("Service supports explicit profile-free external eject and rejects the unconfirmed compatibility route")
    func serviceProfileFreeRouteRequiresCheckpoint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whole-eject-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let memberUUID = UUID(), mediaUUID = UUID()
        let device = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: ["/Volumes/A"],
            volumeUUIDs: [memberUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: memberUUID, mounted: true, mountPoint: "/Volumes/A")],
            topologyComplete: true, isVirtual: false)
        let observer = EjectFixtureObserver([device])
        let runner = EjectFixtureRunner(observer: observer)
        let service = HESectoriumService(paths: HESectoriumPaths(root: root), backend: EjectFixtureBackend(),
            store: JSONStateStore(url: root.appendingPathComponent("state.json")),
            operationLock: KernelOperationLock(url: root.appendingPathComponent("lock")),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer)
        service.selectSectoriumDevice(mediaUUID.uuidString)
        #expect(!service.ejectSelectedExternalDevice().succeeded)
        #expect(!runner.calls.contains { $0.first == "/usr/sbin/diskutil" && $0.dropFirst().first == "unmount" })
        let confirmation = try #require(service.prepareWholeDeviceEjectConfirmation())
        #expect(confirmation.physicalIdentity == mediaUUID.uuidString)
        #expect(confirmation.bsdName == "disk81")
        #expect(confirmation.affectedMembers.count == 1)
        #expect(confirmation.dependenciesCanFinishOffTarget)
        #expect(confirmation.checkpoint(knownWritersClosed: false).knownWritersClosed == false)
        let previewDriver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let topology = try #require(previewDriver.observe(physicalIdentity: mediaUUID.uuidString))
        let staleDisplay = SectoriumWholeDeviceEjectConfirmation(topology: topology,
            observedAt: Date().addingTimeInterval(-300), dependenciesCanFinishOffTarget: true)
        #expect(staleDisplay.checkpoint(knownWritersClosed: true).confirmedAt == staleDisplay.observedAt)
        let result = service.ejectSelectedExternalDevice(checkpoint: .init(
            confirmedExactTargetAndScope: true, knownWritersClosed: true, dependenciesCanFinishOffTarget: true,
            confirmedPhysicalIdentity: topology.physicalIdentity, confirmedMemberKey: topology.memberKey,
            confirmedAt: Date()))
        #expect(result.succeeded)
        #expect(result.steps.contains { $0.step == "ejectWholeDevice" })
        #expect(!runner.calls.contains { $0.first == "/usr/sbin/lsof" })
        #expect(!runner.calls.contains(["/usr/bin/hdiutil", "detach", "/dev/disk90"]))
    }
}
