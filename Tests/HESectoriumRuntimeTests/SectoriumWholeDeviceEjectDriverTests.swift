import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

private final class EjectFixtureObserver: SectoriumDeviceObserving {
    var devices: [SectoriumPhysicalDevice]
    var unavailable = false
    var observationCount = 0
    init(_ devices: [SectoriumPhysicalDevice]) { self.devices = devices }
    func observeDevices() throws -> [SectoriumPhysicalDevice] {
        observationCount += 1
        if unavailable { throw SectoriumDeviceCatalogError.malformedDeviceInventory }
        return devices
    }
}

private final class EjectFixturePortableWriter: SectoriumPortableDocumentWriting {
    func update(profile: SectoriumDevelopmentProfile, event: String) -> SectoriumPortableDocumentResult {
        .pending("fixture withholds portable writes")
    }
}

private func ejectFixtureInstaller(_ paths: HESectoriumPaths) -> HESectoriumInstaller {
    HESectoriumInstaller(paths: paths, home: paths.root.appendingPathComponent("fixture-home", isDirectory: true))
}

private final class EjectFixtureRunner: HESectoriumTimedCommandRunning {
    let observer: EjectFixtureObserver
    private(set) var calls: [[String]] = []
    var imageInventory: [[String: Any]] = []
    var diskListRows: [[String: Any]]?
    var externalPhysicalInventory: CommandOutcome?
    var dfSourceByPath: [String: String] = [:]
    var diskInfoByBSD: [String: [String: Any]] = [:]
    var diskInfoByPath: [String: [String: Any]] = [:]
    var apfsContainers: [[String: Any]] = []
    var dfAvailable = true
    var failVolumeBSD: String?
    var addUnexpectedMemberAfterUnmount = false
    var afterEjectDevices: [SectoriumPhysicalDevice]?
    var timeoutArguments: [String]?
    var occupancyOutcome = CommandOutcome(exitCode: 1, detail: "")
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
        if executable == "/usr/sbin/lsof", arguments.count == 5,
           Array(arguments.prefix(4)) == ["-nP", "-Fpcf", "+f", "--"], arguments[4].hasPrefix("/dev/disk") {
            return occupancyOutcome
        }
        if executable == "/usr/bin/hdiutil", arguments == ["info", "-plist"] {
            return plist(["images": imageInventory])
        }
        if executable == "/usr/sbin/diskutil", arguments == ["list", "-plist"] {
            let rows = diskListRows ?? observer.devices.map { ["DeviceIdentifier": $0.bsdName] }
            return plist(["AllDisksAndPartitions": rows])
        }
        if executable == "/usr/sbin/diskutil", arguments == ["list", "-plist", "external", "physical"] {
            return externalPhysicalInventory ?? .init(exitCode: 127, detail: "filtered inventory not configured in fixture")
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
        if executable == "/usr/sbin/diskutil", arguments.count == 3,
           arguments[0] == "info", arguments[1] == "-plist",
           let info = diskInfoByPath[arguments[2]] { return plist(info) }
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
            observer.devices = afterEjectDevices ?? []
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

private func anchoredPhysicalDevice(_ anchor: UUID, bsd: String = "disk81", extraMember: UUID? = nil,
                                    verified: Bool = true, external: Bool = true,
                                    complete: Bool = true, mounted: Bool = true) -> SectoriumPhysicalDevice {
    let uuids = [anchor] + (extraMember.map { [$0] } ?? [])
    let members = uuids.enumerated().map { index, uuid in
        SectoriumPhysicalVolumeMember(bsdName: "\(bsd)s\(index + 1)", volumeUUID: uuid,
            mounted: mounted, mountPoint: mounted ? "/Volumes/Fixture\(index + 1)" : nil)
    }
    return SectoriumPhysicalDevice(id: verified ? anchor.uuidString : "unverified-\(bsd)",
        bsdName: bsd, name: "Fixture external", isExternal: external, identityVerified: verified,
        wholeDeviceBytes: nil, mountedVolumePaths: mounted ? members.compactMap(\.mountPoint) : [],
        volumeUUIDs: uuids, readBytes: nil, writtenBytes: nil, volumeMembers: members,
        topologyComplete: complete, isVirtual: false,
        identityBasis: verified ? .uniqueBackingVolumeUUID : .unavailable,
        wholeMediaUUID: nil, requiresFreshParentCheck: true)
}

private func isUnknownPresence(_ presence: WholeDevicePresence) -> Bool {
    if case .unknown = presence { return true }
    return false
}

/// Synthetic BSD numbers, preserving the captured macOS snapshot -> synthesized APFS
/// container -> physical partition -> internal Unknown whole-disk metadata shape.
private func configureSnapshotSystemFixture(_ runner: EjectFixtureRunner, physicalBSD: String = "disk72") {
    runner.dfSourceByPath["/"] = "/dev/disk73s1s1"
    runner.diskInfoByBSD["disk73s1s1"] = ["DeviceIdentifier": "disk73s1s1", "ParentWholeDisk": "disk73",
        "WholeDisk": false, "APFSContainerReference": "disk73"]
    runner.diskInfoByBSD["disk73"] = ["DeviceIdentifier": "disk73", "ParentWholeDisk": "disk73",
        "WholeDisk": true, "VirtualOrPhysical": "Virtual", "APFSContainerReference": "disk73",
        "APFSPhysicalStores": [["APFSPhysicalStore": "\(physicalBSD)s2"]]]
    runner.diskInfoByBSD["\(physicalBSD)s2"] = ["DeviceIdentifier": "\(physicalBSD)s2",
        "ParentWholeDisk": physicalBSD, "WholeDisk": false, "APFSContainerReference": "disk73"]
    runner.diskInfoByBSD[physicalBSD] = ["DeviceIdentifier": physicalBSD, "ParentWholeDisk": physicalBSD,
        "VirtualOrPhysical": "Unknown", "Internal": true, "WholeDisk": true, "Content": "GUID_partition_scheme"]
    runner.apfsContainers = [["ContainerReference": "disk73",
        "PhysicalStores": [["DeviceIdentifier": "\(physicalBSD)s2"]]]]
}

private func onlyReadOnlyMetadataCalls(_ calls: [[String]]) -> Bool {
    calls.allSatisfy { call in
        if call == ["/usr/sbin/diskutil", "list", "-plist"]
            || call == ["/usr/sbin/diskutil", "list", "-plist", "external", "physical"]
            || call == ["/usr/sbin/diskutil", "apfs", "list", "-plist"]
            || call == ["/usr/bin/hdiutil", "info", "-plist"] { return true }
        if call.count == 4, Array(call.prefix(3)) == ["/usr/sbin/diskutil", "info", "-plist"] { return true }
        return call.count == 3 && Array(call.prefix(2)) == ["/bin/df", "-P"]
    }
}

private enum DependencyFixtureCase: Equatable { case internalDisk, samePhysicalStore, imageBackedByTarget, symlinkToTarget, unknownIdentity, ambiguousStores }

/// Simulated command time, not a host-speed measurement. Every result still
/// passes through the real topology and eleven-path dependency resolvers.
private final class DependencyLatencyFixture: HESectoriumTimedCommandRunning {
    let base: EjectFixtureRunner
    var elapsed: TimeInterval = 0
    var delay: TimeInterval = 0.02
    init(_ base: EjectFixtureRunner) { self.base = base }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        run(executable, arguments, cwd: cwd, timeout: 15)
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        elapsed += min(delay, timeout)
        guard delay < timeout else { return .init(exitCode: -1, detail: "isolated simulated timeout") }
        if executable == "/bin/df", arguments.count == 2 {
            base.dfSourceByPath[arguments[1]] = "/dev/disk73s1s1"
        }
        return base.run(executable, arguments, cwd: cwd)
    }
}

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
        installer: ejectFixtureInstaller(HESectoriumPaths(root: support)),
        runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer,
        portableDocumentWriter: EjectFixturePortableWriter())
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
    @Test("A successful native eject completes while the exact USB node remains enumerated and unmounted")
    func logicalEjectDoesNotWaitForCableRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whole-eject-logical-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let anchor = UUID(), device = anchoredPhysicalDevice(anchor)
        let observer = EjectFixtureObserver([device]), runner: EjectFixtureRunner
        runner = EjectFixtureRunner(observer: observer)
        runner.afterEjectDevices = [anchoredPhysicalDevice(anchor, mounted: false)]
        runner.diskInfoByPath["/Volumes/Fixture1"] = ["DeviceIdentifier": "disk81s1",
            "VolumeUUID": anchor.uuidString, "MountPoint": "/Volumes/Fixture1", "ParentWholeDisk": "disk81"]
        let store = JSONStateStore(url: root.appendingPathComponent("state.json"))
        let service = HESectoriumService(paths: HESectoriumPaths(root: root), backend: EjectFixtureBackend(),
            store: store, operationLock: KernelOperationLock(url: root.appendingPathComponent("lock")),
            installer: ejectFixtureInstaller(HESectoriumPaths(root: root)), runner: runner,
            identityPolicy: .expected, sectoriumDeviceObserver: observer,
            portableDocumentWriter: EjectFixturePortableWriter())
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let target = try #require(driver.observe(physicalIdentity: device.id))
        let result = service.ejectSelectedExternalDevice(physicalIdentity: device.id,
            checkpoint: confirmed(target))
        #expect(result.succeeded, "The production service and documented driver must preserve terminal verification")
        #expect(observer.devices.count == 1, "The USB node remains physically enumerated")
        let state = try store.load()
        #expect(!state.ejectIntent && state.workbenchOperation == nil)
        #expect(state.workbenchPhase == "eject:completed")
        #expect(state.workbenchTerminalResult == "safe-to-unplug")
        #expect(runner.calls.filter { $0 == ["/usr/sbin/diskutil", "eject", "/dev/disk81"] }.count == 1)
    }

    @Test("Native catalog preserves an ejected USB target identity without any mountpoint")
    func nativeObserverRecognizesUnmountedEnumeratedUSBNode() throws {
        let anchor = UUID()
        let runner = EjectFixtureRunner(observer: EjectFixtureObserver([]))
        runner.diskListRows = [["DeviceIdentifier": "disk81", "Partitions": [
            ["DeviceIdentifier": "disk81s1", "VolumeUUID": anchor.uuidString, "VolumeName": "Fixture"]]]]
        runner.diskInfoByBSD["disk81"] = ["DeviceIdentifier": "disk81", "WholeDisk": true,
            "VirtualOrPhysical": "Physical", "Internal": false, "DeviceLocation": "External"]
        runner.diskInfoByBSD["disk81s1"] = ["DeviceIdentifier": "disk81s1",
            "ParentWholeDisk": "disk81", "VolumeUUID": anchor.uuidString, "VolumeName": "Fixture"]
        let observer = SystemSectoriumDeviceObserver(runner: runner)
        let devices = try observer.observeDevices()
        let device = try #require(devices.first)
        #expect(devices.count == 1 && device.id == anchor.uuidString)
        #expect(device.identityVerified && device.topologyComplete)
        #expect(device.identityBasis == .uniqueBackingVolumeUUID && device.wholeMediaUUID == nil)
        #expect(device.mountedVolumePaths.isEmpty && device.volumeMembers.allSatisfy { !$0.mounted })
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory)
        let current = try #require(driver.observe(physicalIdentity: anchor.uuidString))
        let original = WholeDeviceTopology(physicalIdentity: current.physicalIdentity, bsdName: current.bsdName,
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: current.volumes.map { .init(identity: $0.identity, mounted: true) }, images: [])
        #expect(driver.presence(of: original) == .present)
        #expect(driver.successfulEjectHasUnmountedPostcondition(of: original))
        #expect(runner.calls.allSatisfy { call in
            !["unmount", "mount", "eject", "attach", "detach"].contains(call.dropFirst().first ?? "")
        })
    }

    @Test("Post-eject verification rejects mounted, changed, duplicate or unavailable target metadata")
    func logicalEjectPostconditionRequiresExactUnmountedTopology() throws {
        let anchor = UUID(), device = anchoredPhysicalDevice(anchor)
        let observer = EjectFixtureObserver([device]), runner: EjectFixtureRunner
        runner = EjectFixtureRunner(observer: observer)
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory)
        let target = try #require(driver.observe(physicalIdentity: device.id))
        #expect(!driver.successfulEjectHasUnmountedPostcondition(of: target), "Mounted is not ejected")
        observer.devices = [anchoredPhysicalDevice(anchor, mounted: false)]
        #expect(driver.successfulEjectHasUnmountedPostcondition(of: target))
        observer.devices = [anchoredPhysicalDevice(UUID(), mounted: false)]
        #expect(!driver.successfulEjectHasUnmountedPostcondition(of: target), "Reused BSD node is not the target")
        observer.devices = [anchoredPhysicalDevice(anchor, extraMember: UUID(), mounted: false)]
        #expect(!driver.successfulEjectHasUnmountedPostcondition(of: target), "Changed members cannot be ignored")
        observer.devices = [anchoredPhysicalDevice(anchor, mounted: false), anchoredPhysicalDevice(anchor, mounted: false)]
        #expect(!driver.successfulEjectHasUnmountedPostcondition(of: target), "Duplicate identity is ambiguous")
        observer.unavailable = true
        #expect(!driver.successfulEjectHasUnmountedPostcondition(of: target))
        #expect(runner.calls.allSatisfy { call in
            !["unmount", "mount", "eject", "attach", "detach"].contains(call.dropFirst().first ?? "")
        }, "The terminal verification never dispatches another storage action")
    }

    @Test("Native absence avoids unavailable internal catalog work")
    func emptyNativeExternalListCompletesWithoutFullCatalog() throws {
        let target = anchoredPhysicalDevice(UUID())
        let observer = EjectFixtureObserver([target])
        let runner = EjectFixtureRunner(observer: observer)
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory)
        let topology = try #require(driver.observe(physicalIdentity: target.id))
        let empty = try PropertyListSerialization.data(fromPropertyList:
            ["AllDisksAndPartitions": [], "AllDisks": []], format: .xml, options: 0)
        runner.externalPhysicalInventory = .init(exitCode: 0, detail: String(decoding: empty, as: UTF8.self))
        observer.unavailable = true
        let beforeCalls = runner.calls.count, beforeObservations = observer.observationCount
        #expect(driver.presence(of: topology) == .absent)
        #expect(observer.observationCount == beforeObservations)
        #expect(Array(runner.calls.dropFirst(beforeCalls)) == [["/usr/sbin/diskutil", "list", "-plist", "external", "physical"]])
    }

    @Test("Malformed filtered inventory cannot turn an unavailable device observation into absence")
    func malformedNativeExternalListRemainsUnknown() throws {
        let target = anchoredPhysicalDevice(UUID())
        let observer = EjectFixtureObserver([target])
        let runner = EjectFixtureRunner(observer: observer)
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory)
        let topology = try #require(driver.observe(physicalIdentity: target.id))
        observer.unavailable = true
        for value: [String: Any] in [[:], ["AllDisksAndPartitions": "bad"],
                                    ["AllDisksAndPartitions": [], "AllDisks": ["disk81"]]] {
            let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
            runner.externalPhysicalInventory = .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
            #expect(isUnknownPresence(driver.presence(of: topology)))
        }
        runner.externalPhysicalInventory = .init(exitCode: -1, detail: "timed out")
        #expect(isUnknownPresence(driver.presence(of: topology)))
    }

    @Test("Issued eject lost its callback but a verified remounted connection can return without another eject")
    func missingEjectReceiptDoesNotPermanentlyBlockFreshReconnect() throws {
        let anchor = UUID(), observer = EjectFixtureObserver([])
        observer.devices = [anchoredPhysicalDevice(anchor)]
        let runner = EjectFixtureRunner(observer: observer)
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory, independentReturnValidator: { _ in true })
        let topology = try #require(driver.observe(physicalIdentity: anchor.uuidString))
        let journal = WholeDeviceEjectJournalRecord(operationID: "lost-callback", target: topology,
            phase: .interrupted, completedSteps: ["unmountAllPhysicalVolumes"],
            lastReceipt: .timedOut, lastIssuedAction: .ejectWholeDevice)
        observer.devices = [anchoredPhysicalDevice(anchor, bsd: "disk82")]
        runner.diskInfoByBSD["disk82"] = ["DeviceIdentifier": "disk82", "VirtualOrPhysical": "Physical"]
        #expect(driver.freshReturnIdentityMatches(journal))
        observer.devices = [anchoredPhysicalDevice(anchor, bsd: "disk82", mounted: false)]
        #expect(!driver.freshReturnIdentityMatches(journal), "Still-unmounted state cannot be mistaken for a new usable connection")
        observer.devices = [anchoredPhysicalDevice(UUID(), bsd: "disk82")]
        #expect(!driver.freshReturnIdentityMatches(journal), "Another drive cannot release the target's operation")
        #expect(onlyReadOnlyMetadataCalls(runner.calls))
    }

    @Test("Confirmed eject scans each mounted member once and reobserves after every mutation")
    func confirmedEjectUsesOneOccupancyScanPerMember() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("eject-activity-once-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = UUID(), second = UUID()
        let target = SectoriumPhysicalDevice(id: UUID().uuidString, bsdName: "disk81", name: "Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil,
            mountedVolumePaths: ["/Volumes/A", "/Volumes/B"], volumeUUIDs: [first, second],
            readBytes: nil, writtenBytes: nil, volumeMembers: [
                .init(bsdName: "disk81s1", volumeUUID: first, mounted: true, mountPoint: "/Volumes/A"),
                .init(bsdName: "disk81s2", volumeUUID: second, mounted: true, mountPoint: "/Volumes/B")
            ], topologyComplete: true, isVirtual: false)
        let observer = EjectFixtureObserver([target])
        let runner = EjectFixtureRunner(observer: observer)
        runner.diskInfoByBSD["disk81s2"] = ["DeviceIdentifier": "disk81s2", "VirtualOrPhysical": "Physical", "PartOfWhole": "disk81"]
        let paths = HESectoriumPaths(root: root)
        let service = HESectoriumService(paths: paths, backend: EjectFixtureBackend(),
            store: JSONStateStore(url: paths.state), operationLock: KernelOperationLock(url: paths.lock),
            installer: ejectFixtureInstaller(paths), runner: runner, identityPolicy: .expected,
            sectoriumDeviceObserver: observer, portableDocumentWriter: EjectFixturePortableWriter())
        let confirmation = try #require(service.prepareWholeDeviceEjectConfirmation(physicalIdentity: target.id))
        let result = service.ejectExternalDevice(physicalIdentity: target.id, confirmation: confirmation)
        #expect(result.succeeded, "\(String(describing: result.failure))")
        let occupancy = runner.calls.filter { $0.first == "/usr/sbin/lsof" }
        #expect(occupancy.count == 2 && Set(occupancy.map { $0.last! }).count == 2)
        #expect(runner.calls.filter { $0 == ["/usr/sbin/diskutil", "eject", "/dev/disk81"] }.count == 1)
        #expect(service.pendingSectoriumOperation() == nil)
    }

    @Test("Passive recovery clears an absent target and remains metadata-only across a fresh Service")
    func passiveServiceRecoveryArchivesAbsenceWithoutConfirmation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("eject-passive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = anchoredPhysicalDevice(UUID())
        let observer = EjectFixtureObserver([target]), runner: EjectFixtureRunner
        runner = EjectFixtureRunner(observer: observer)
        let topology = try #require(SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root).observe(physicalIdentity: target.id))
        let journal = WholeDeviceEjectJournalRecord(operationID: "callback", target: topology,
            phase: .ejectCallbackSucceeded, completedSteps: ["unmountAllPhysicalVolumes", "ejectWholeDevice"],
            lastReceipt: .completed("ejected"), lastIssuedAction: .ejectWholeDevice)
        let paths = HESectoriumPaths(root: root), store = JSONStateStore(url: root.appendingPathComponent("state.json"))
        #expect(try store.compareAndSwap(expectedRevision: 0, newState: StoragePersistentState(revision: 1,
            ejectIntent: true, operationID: journal.operationID, workbenchOperation: "eject:" + journal.operationID,
            workbenchTarget: JSONEncoder().encode(journal).base64EncodedString())))
        observer.devices = []; runner.dfAvailable = false
        let service = HESectoriumService(paths: paths, backend: EjectFixtureBackend(), store: store,
            operationLock: KernelOperationLock(url: paths.lock), installer: ejectFixtureInstaller(paths),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer,
            portableDocumentWriter: EjectFixturePortableWriter())
        #expect(service.reconcileWholeDeviceEjectRecovery())
        #expect(service.pendingSectoriumOperation() == nil)
        #expect(!service.reconcileWholeDeviceEjectRecovery(), "Repeated absent observations do not rewrite state")
        #expect(try store.load().workbenchTerminalResult == "safe-to-unplug")
        #expect(onlyReadOnlyMetadataCalls(runner.calls))
    }
    @Test("Startup automation reconciles a successful eject while holding its recursive Service lock")
    func automationEntryReconcilesDurableCallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("eject-automation-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = anchoredPhysicalDevice(UUID()), observer = EjectFixtureObserver([])
        observer.devices = [target]
        let runner = EjectFixtureRunner(observer: observer)
        let topology = try #require(SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root).observe(physicalIdentity: target.id))
        let journal = WholeDeviceEjectJournalRecord(operationID: "automation-callback", target: topology,
            phase: .ejectCallbackSucceeded, completedSteps: ["unmountAllPhysicalVolumes", "ejectWholeDevice"],
            lastReceipt: .completed("ejected"), lastIssuedAction: .ejectWholeDevice)
        let paths = HESectoriumPaths(root: root), store = JSONStateStore(url: root.appendingPathComponent("state.json"))
        #expect(try store.compareAndSwap(expectedRevision: 0, newState: StoragePersistentState(revision: 1,
            ejectIntent: true, operationID: journal.operationID, workbenchOperation: "eject:" + journal.operationID,
            workbenchTarget: JSONEncoder().encode(journal).base64EncodedString())))
        observer.devices = []
        let service = HESectoriumService(paths: paths, backend: EjectFixtureBackend(), store: store,
            operationLock: KernelOperationLock(url: paths.lock), installer: ejectFixtureInstaller(paths),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer,
            portableDocumentWriter: EjectFixturePortableWriter())
        let result = service.runApplicationAutomationAtStartup()
        #expect(result.succeeded)
        #expect(service.pendingSectoriumOperation() == nil)
        #expect(try store.load().workbenchTerminalResult == "safe-to-unplug")
        #expect(onlyReadOnlyMetadataCalls(runner.calls))
    }

    @Test("Unrelated internal identity gaps do not hold an absent external drive in recovery")
    func externalAbsenceIgnoresOnlyProvenUnrelatedInternalMedia() throws {
        let target = anchoredPhysicalDevice(UUID())
        let observer = EjectFixtureObserver([target])
        let runner = EjectFixtureRunner(observer: observer)
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory)
        let topology = try #require(driver.observe(physicalIdentity: target.id))
        observer.devices = [.init(id: "unverified:disk1", bsdName: "disk1", name: "Apple storage",
            isExternal: false, identityVerified: false, wholeDeviceBytes: nil,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil)]
        #expect(isUnknownPresence(driver.presence(of: topology)), "Unknown internal/external location is not absence")
        runner.diskInfoByBSD["disk1"]?["Internal"] = true
        #expect(driver.presence(of: topology) == .absent)
        runner.diskInfoByBSD["disk1"]?["DeviceLocation"] = "External"
        #expect(isUnknownPresence(driver.presence(of: topology)), "Contradictory native location remains unknown")
        #expect(onlyReadOnlyMetadataCalls(runner.calls))
    }

    @Test("Fresh reloaded registered image recovers a completed eject even after disk numbers change")
    func completedCallbackAcceptsExactAlreadyReloadedImageOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("eject-reloaded-\(UUID().uuidString)")
        let outer = root.appendingPathComponent("external")
        let imagePath = outer.appendingPathComponent("Dev.sparsebundle")
        try FileManager.default.createDirectory(at: imagePath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let member = UUID(), imageUUID = UUID()
        let target = anchoredPhysicalDevice(member)
        let imageDevice = SectoriumPhysicalDevice(id: "virtual", bsdName: "disk90", name: "DEV",
            isExternal: false, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [imageUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk90s1", volumeUUID: imageUUID, mounted: true, mountPoint: "/private/tmp/DEV")],
            topologyComplete: true, isVirtual: true)
        let observer = EjectFixtureObserver([target, imageDevice])
        let runner = EjectFixtureRunner(observer: observer)
        runner.dfSourceByPath[imagePath.resolvingSymlinksInPath().path] = "/dev/disk81s1"
        runner.imageInventory = [["image-path": imagePath.path, "system-entities": [
            ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk90"],
            ["mount-point": "/private/tmp/DEV", "volume-uuid": imageUUID.uuidString, "dev-entry": "/dev/disk90s1"]
        ]]]
        var registeredChainMatches = true
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root,
            independentReturnValidator: { _ in true },
            independentLoadedReturnValidator: { _ in registeredChainMatches })
        let observed = try #require(driver.observe(physicalIdentity: target.id))
        let old = WholeDeviceTopology(physicalIdentity: observed.physicalIdentity, bsdName: "disk84",
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(member.uuidString.lowercased())|disk84s1", mounted: true)],
            images: [.init(identity: "image:disk85", attached: true,
                volumeIdentities: ["\(imageUUID.uuidString.lowercased())|disk86s1"],
                mountedVolumeIdentities: ["\(imageUUID.uuidString.lowercased())|disk86s1"])])
        let journal = WholeDeviceEjectJournalRecord(operationID: "callback", target: old,
            phase: .ejectCallbackSucceeded,
            completedSteps: ["detachImage:image:disk85", "unmountAllPhysicalVolumes", "ejectWholeDevice"],
            lastReceipt: .completed("ejected"), lastIssuedAction: .ejectWholeDevice)
        #expect(driver.freshReturnIdentityMatches(journal))
        registeredChainMatches = false
        #expect(!driver.freshReturnIdentityMatches(journal), "Same APFS UUID alone cannot replace registered file and path verification")
        #expect(onlyReadOnlyMetadataCalls(runner.calls))
    }
    @Test("A scoped refresh deduplicates the complete dependency graph and never carries evidence to a new check")
    func completeDependencyGraphLatencyAndFreshness() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-latency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root)
        let target = anchoredPhysicalDevice(UUID())
        let observer = EjectFixtureObserver([target])

        func graph(_ runner: HESectoriumCommandRunning) -> Bool {
            let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
            return driver.observe(physicalIdentity: target.id) != nil
                && SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths, targetBSDName: target.bsdName, runner: runner)
        }
        let oldBase = EjectFixtureRunner(observer: observer)
        configureSnapshotSystemFixture(oldBase)
        let old = DependencyLatencyFixture(oldBase)
        #expect(graph(old) && graph(old))

        let newBase = EjectFixtureRunner(observer: observer)
        configureSnapshotSystemFixture(newBase)
        let clock = DependencyLatencyFixture(newBase)
        let scoped = SectoriumObservationCommandRunner(clock, now: { clock.elapsed })
        #expect(scoped.withObservation { graph(scoped) && graph(scoped) })
        let optimizedCount = newBase.calls.count
        let optimizedTime = clock.elapsed
        #expect(optimizedCount * 3 < oldBase.calls.count)
        #expect(optimizedTime * 3 < old.elapsed)
        #expect(onlyReadOnlyMetadataCalls(oldBase.calls + newBase.calls))
        print("DEPENDENCY_GRAPH_BENCHMARK baseline_commands=\(oldBase.calls.count) scoped_commands=\(optimizedCount) simulated_baseline_seconds=\(old.elapsed) simulated_scoped_seconds=\(optimizedTime)")

        // A new round observes a real failure, rather than accepting cached success.
        newBase.dfAvailable = false
        #expect(!scoped.withObservation { graph(scoped) })
        #expect(newBase.calls.count > optimizedCount)
        newBase.dfAvailable = true
        #expect(scoped.withObservation {
            guard graph(scoped) else { return false }
            newBase.dfAvailable = false
            return !scoped.withFreshObservation { graph(scoped) }
        })
        // A button starts from fresh evidence and deduplicates only within its
        // own read-only preflight; it cannot inherit the background snapshot.
        newBase.dfAvailable = true
        let preflightBefore = newBase.calls.count
        #expect(scoped.withFreshObservation { graph(scoped) && graph(scoped) })
        let preflightCount = newBase.calls.count - preflightBefore
        #expect(preflightCount == optimizedCount)
        newBase.dfAvailable = false
        #expect(!scoped.withFreshObservation { graph(scoped) })
        print("DEPENDENCY_PREFLIGHT_BENCHMARK fresh_commands=\(preflightCount) inherited_background=false")

        // Slow commands share one deadline across the complete graph.
        newBase.dfAvailable = true
        clock.delay = 1
        let started = clock.elapsed
        #expect(!scoped.withObservation { graph(scoped) })
        #expect(clock.elapsed - started <= 8.001)
        #expect(onlyReadOnlyMetadataCalls(newBase.calls))
    }

    @Test("Physical whole disks accept exact self-parent metadata without treating disk's s as a partition")
    func physicalWholeDiskSelfParentIsAccepted() throws {
        let target = anchoredPhysicalDevice(UUID())
        let observer = EjectFixtureObserver([target])
        let runner = EjectFixtureRunner(observer: observer)
        runner.diskInfoByBSD["disk1"] = ["DeviceIdentifier": "disk1", "ParentWholeDisk": "disk1",
            "PartOfWhole": "disk1", "WholeDisk": true, "VirtualOrPhysical": "Physical"]
        runner.diskInfoByBSD["disk1s1"] = ["DeviceIdentifier": "disk1s1", "ParentWholeDisk": "disk1", "WholeDisk": false]
        runner.diskInfoByBSD["disk81"] = ["DeviceIdentifier": "disk81", "ParentWholeDisk": "disk81",
            "WholeDisk": true, "Internal": false, "VirtualOrPhysical": "Physical"]
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory)

        let topology = try #require(driver.observe(physicalIdentity: target.id))
        #expect(topology.bsdName == "disk81")
        #expect(!topology.isSystemDevice)
        #expect(runner.calls.contains(["/usr/sbin/diskutil", "info", "-plist", "/dev/disk1"]))
        #expect(onlyReadOnlyMetadataCalls(runner.calls))
    }

    @Test("Snapshot and APFS self-parent chain resolves a proven internal Unknown physical whole disk")
    func snapshotAPFSChainWithInternalUnknownRootIsAccepted() throws {
        let target = anchoredPhysicalDevice(UUID())
        let observer = EjectFixtureObserver([target])
        let runner = EjectFixtureRunner(observer: observer)
        configureSnapshotSystemFixture(runner)
        runner.diskInfoByBSD["disk81"]?["ParentWholeDisk"] = "disk81"
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory)

        #expect(driver.observe(physicalIdentity: target.id) != nil)
        for node in ["disk73s1s1", "disk73", "disk72s2", "disk72", "disk81"] {
            #expect(runner.calls.contains(["/usr/sbin/diskutil", "info", "-plist", "/dev/\(node)"]))
        }
        // The physical partition's container reference must not send traversal back
        // into disk73; a single APFS query proves the parent edge took precedence.
        #expect(runner.calls.filter { $0 == ["/usr/sbin/diskutil", "apfs", "list", "-plist"] }.count == 1)
        #expect(onlyReadOnlyMetadataCalls(runner.calls))
    }

    @Test("Unknown is not a generic physical fallback when required evidence is missing or contradictory")
    func unknownPhysicalRootRequiresCompleteInternalWholeDiskEvidence() {
        let changes: [(String, String, Any?)] = [
            ("missing kind", "VirtualOrPhysical", nil), ("virtual", "VirtualOrPhysical", "Virtual"),
            ("unrecognized kind", "VirtualOrPhysical", "Other"),
            ("missing internal", "Internal", nil), ("external", "Internal", false),
            ("missing whole", "WholeDisk", nil), ("partition", "WholeDisk", false),
            ("missing scheme", "Content", nil), ("APFS content", "Content", "Apple_APFS"),
            ("missing self-parent", "ParentWholeDisk", nil), ("different parent", "ParentWholeDisk", "disk74"),
            ("contradictory parents", "PartOfWhole", "disk74"), ("malformed parent", "ParentWholeDisk", 72),
            ("external location", "DeviceLocation", "External"),
            ("APFS backing declaration", "APFSPhysicalStores", [["APFSPhysicalStore": "disk81s1"]]),
            ("unresolved APFS container", "APFSContainerReference", "missing-container")
        ]
        for (name, key, value) in changes {
            let target = anchoredPhysicalDevice(UUID())
            let observer = EjectFixtureObserver([target])
            let runner = EjectFixtureRunner(observer: observer)
            configureSnapshotSystemFixture(runner)
            runner.diskInfoByBSD["disk72"]?[key] = value
            let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
                workingDirectory: FileManager.default.temporaryDirectory)
            #expect(driver.observe(physicalIdentity: target.id) == nil, "\(name) must remain unresolved")
            #expect(onlyReadOnlyMetadataCalls(runner.calls))
        }
    }

    @Test("Whole and partition ownership claims must agree with their exact BSD shape")
    func physicalOwnershipContradictionsAreRejected() {
        let changes: [(String, [String: Any])] = [
            ("disk81", ["ParentWholeDisk": "disk82"]),
            ("disk81", ["ParentWholeDisk": "disk81", "PartOfWhole": "disk82"]),
            ("disk81", ["ParentWholeDisk": 81]),
            ("disk81", ["WholeDisk": false]),
            ("disk1s1", ["ParentWholeDisk": "disk11", "PartOfWhole": "disk11"]),
            ("disk1s1", ["ParentWholeDisk": "disk1", "PartOfWhole": "disk11"]),
            ("disk1s1", ["ParentWholeDisk": "disk1s1"]),
            ("disk1s1", ["WholeDisk": true])
        ]
        for (bsd, changes) in changes {
            let target = anchoredPhysicalDevice(UUID())
            let observer = EjectFixtureObserver([target])
            let runner = EjectFixtureRunner(observer: observer)
            runner.diskInfoByBSD[bsd]?.merge(changes) { _, new in new }
            let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
                workingDirectory: FileManager.default.temporaryDirectory)
            #expect(driver.observe(physicalIdentity: target.id) == nil, "\(bsd): \(changes)")
            #expect(onlyReadOnlyMetadataCalls(runner.calls))
        }
    }

    @Test("APFS self-parent support still rejects ambiguous stores, cycles, and the system physical root")
    func snapshotAPFSChainStillRefusesAmbiguousOrSystemTargets() {
        for scenario in ["multiple stores", "duplicate container", "cycle", "same physical root"] {
            let target = anchoredPhysicalDevice(UUID())
            let observer = EjectFixtureObserver([target])
            let runner = EjectFixtureRunner(observer: observer)
            configureSnapshotSystemFixture(runner, physicalBSD: scenario == "same physical root" ? "disk81" : "disk72")
            switch scenario {
            case "multiple stores":
                runner.apfsContainers[0]["PhysicalStores"] = [["DeviceIdentifier": "disk72s2"], ["DeviceIdentifier": "disk81s1"]]
            case "duplicate container": runner.apfsContainers.append(runner.apfsContainers[0])
            case "cycle": runner.apfsContainers[0]["PhysicalStores"] = [["DeviceIdentifier": "disk73s1s1"]]
            default: break
            }
            let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
                workingDirectory: FileManager.default.temporaryDirectory)
            #expect(driver.observe(physicalIdentity: target.id) == nil, "\(scenario) must refuse eject topology")
            #expect(onlyReadOnlyMetadataCalls(runner.calls))
        }
    }

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
        let unmountedTarget = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [outerUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(bsdName: "disk81s1", volumeUUID: outerUUID, mounted: false, mountPoint: nil)],
            topologyComplete: true, isVirtual: false)
        observer.devices = [unmountedTarget, imageDevice]
        let stillAttached = try #require(driver.observe(physicalIdentity: mediaUUID.uuidString))
        #expect(stillAttached.volumes.allSatisfy { !$0.mounted })
        #expect(!stillAttached.images.isEmpty)
        #expect(!driver.successfulEjectHasUnmountedPostcondition(of: topology),
            "An attached image still prevents safe completion even when the physical volume is unmounted")
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
        #expect(!saved.ejectIntent)
        #expect(saved.workbenchOperation == nil)
        #expect(saved.workbenchTerminalResult == "safe-to-unplug")
        #expect(saved.workbenchTarget == nil)
        #expect(saved.terminalEjectJournals[mediaUUID.uuidString] != nil)

        // Simulate a later device reconnect at a different BSD number and a new process.
        // Return matches the stable physical/member UUIDs, not the former disk81 names.
        runner.diskInfoByBSD["disk82"] = ["DeviceIdentifier": "disk82", "VirtualOrPhysical": "Physical"]
        runner.diskInfoByBSD["disk82s1"] = ["DeviceIdentifier": "disk82s1", "VirtualOrPhysical": "Physical", "PartOfWhole": "disk82"]
        runner.diskInfoByBSD["disk82s2"] = ["DeviceIdentifier": "disk82s2", "VirtualOrPhysical": "Physical", "PartOfWhole": "disk82"]
        observer.devices = [SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk82", name: "External Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [firstUUID, secondUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [
                .init(bsdName: "disk82s1", volumeUUID: firstUUID, mounted: true, mountPoint: "/Volumes/A"),
                .init(bsdName: "disk82s2", volumeUUID: secondUUID, mounted: true, mountPoint: "/Volumes/B")
            ], topologyComplete: true, isVirtual: false)]
        let returningDriver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root, independentReturnValidator: { _ in true })
        let freshController = StorageController(backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        let wrongMemberUUID = UUID()
        observer.devices[0] = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk82", name: "External Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [firstUUID, wrongMemberUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [
                .init(bsdName: "disk82s1", volumeUUID: firstUUID, mounted: true, mountPoint: "/Volumes/A"),
                .init(bsdName: "disk82s2", volumeUUID: wrongMemberUUID, mounted: true, mountPoint: "/Volumes/B")
            ], topologyComplete: true, isVirtual: false)
        #expect(!freshController.returnFromWholeDeviceEject(
            physicalIdentity: mediaUUID.uuidString, driver: returningDriver),
            "A changed APFS UUID must not be accepted as BSD renumbering")
        observer.devices[0] = SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk82", name: "External Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [firstUUID, secondUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [
                .init(bsdName: "disk82s1", volumeUUID: firstUUID, mounted: true, mountPoint: "/Volumes/A"),
                .init(bsdName: "disk82s2", volumeUUID: secondUUID, mounted: true, mountPoint: "/Volumes/B")
            ], topologyComplete: true, isVirtual: false)
        #expect(freshController.returnFromWholeDeviceEject(
            physicalIdentity: mediaUUID.uuidString, driver: returningDriver))
        let returned = try JSONStateStore(url: stateURL).load()
        #expect(!returned.ejectIntent)
        #expect(returned.terminalEjectJournals[mediaUUID.uuidString] == nil)

        // Any later command must use its new, freshly observed BSD name. This fixture
        // deliberately has no disk82 eject handler; the fake runner only records dispatch.
        observer.devices = [SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk82", name: "External Fixture",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [firstUUID, secondUUID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [
                .init(bsdName: "disk82s1", volumeUUID: firstUUID, mounted: false, mountPoint: nil),
                .init(bsdName: "disk82s2", volumeUUID: secondUUID, mounted: false, mountPoint: nil)
            ], topologyComplete: true, isVirtual: false)]
        let freshTopology = try #require(returningDriver.observe(physicalIdentity: mediaUUID.uuidString))
        let beforeDispatch = runner.calls.count
        _ = returningDriver.ejectWholeDeviceNonForce(freshTopology)
        #expect(runner.calls.dropFirst(beforeDispatch).contains(["/usr/sbin/diskutil", "eject", "/dev/disk82"]))
        #expect(!runner.calls.dropFirst(beforeDispatch).contains(["/usr/sbin/diskutil", "eject", "/dev/disk81"]))
    }

    @Test("No-whole-media anchored eject archives its target and returns through a fresh controller")
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
        let saved = try JSONStateStore(url: stateURL).load()
        #expect(!saved.ejectIntent)
        #expect(saved.terminalEjectJournals[backing.uuidString] != nil)
        #expect(runner.calls.contains(["/usr/sbin/diskutil", "eject", "/dev/disk81"]))
        observer.devices = [physical(mounted: true)]
        let freshDriver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root, independentReturnValidator: { _ in true })
        let freshController = StorageController(backend: EjectFixtureBackend(), store: JSONStateStore(url: stateURL),
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        #expect(freshController.returnFromWholeDeviceEject(
            physicalIdentity: backing.uuidString, driver: freshDriver))
        let returned = try JSONStateStore(url: stateURL).load()
        #expect(!returned.ejectIntent)
        #expect(returned.terminalEjectJournals[backing.uuidString] == nil)
    }

    @Test("Pre-action topology drift permits explicit cancellation only on verified original members")
    func unissuedTopologyDriftReturnValidation() throws {
        let mediaUUID = UUID(), originalUUID = UUID(), addedUUID = UUID()
        let target = WholeDeviceTopology(physicalIdentity: mediaUUID.uuidString, bsdName: "disk81",
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(originalUUID.uuidString.lowercased())|disk81s1", mounted: true)],
            images: [])
        let journal = WholeDeviceEjectJournalRecord(operationID: "pre-action-drift", target: target,
            phase: .interrupted)
        func device(original: UUID, addedMounted: Bool = true) -> SectoriumPhysicalDevice {
            SectoriumPhysicalDevice(id: mediaUUID.uuidString, bsdName: "disk81", name: "Fixture external",
                isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
                volumeUUIDs: [original, addedUUID], readBytes: nil, writtenBytes: nil,
                volumeMembers: [
                    .init(bsdName: "disk81s1", volumeUUID: original, mounted: true, mountPoint: "/Volumes/Original"),
                    .init(bsdName: "disk81s2", volumeUUID: addedUUID, mounted: addedMounted,
                          mountPoint: addedMounted ? "/Volumes/New" : nil)
                ], topologyComplete: true, isVirtual: false)
        }
        let observer = EjectFixtureObserver([device(original: originalUUID)])
        let runner = EjectFixtureRunner(observer: observer)
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory,
            independentReturnValidator: { _ in true })
        #expect(driver.freshReturnIdentityMatches(journal),
            "A new member can be included in a read-only cancellation after original identity revalidation")
        observer.devices = [device(original: UUID())]
        #expect(!driver.freshReturnIdentityMatches(journal), "Losing the original APFS UUID is not member growth")
        observer.devices = [device(original: originalUUID, addedMounted: false)]
        #expect(!driver.freshReturnIdentityMatches(journal), "An unmounted new member is not a clean cancellation boundary")
        #expect(!runner.calls.contains { $0.first == "/usr/sbin/diskutil"
            && ["unmount", "eject"].contains($0.dropFirst().first ?? "") })
    }

    @Test("Presence keeps identity-degraded or conflicting original media uncertain")
    func targetAwarePresenceRequiresPhysicalAbsence() throws {
        let anchor = UUID(), added = UUID()
        let observer = EjectFixtureObserver([anchoredPhysicalDevice(anchor)])
        let runner = EjectFixtureRunner(observer: observer)
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: FileManager.default.temporaryDirectory)
        let target = try #require(driver.observe(physicalIdentity: anchor.uuidString))
        #expect(driver.presence(of: target) == .present)

        observer.devices = [anchoredPhysicalDevice(anchor, extraMember: added, verified: false)]
        #expect(isUnknownPresence(driver.presence(of: target)),
            "An added member must not make the original anchored disk appear absent")
        observer.devices = [anchoredPhysicalDevice(anchor, bsd: "disk82", extraMember: added, verified: false)]
        #expect(isUnknownPresence(driver.presence(of: target)),
            "A changed BSD name with the original APFS UUID remains plausible media")
        observer.devices = [anchoredPhysicalDevice(anchor, extraMember: added, verified: false),
            anchoredPhysicalDevice(anchor, bsd: "disk82", verified: false)]
        #expect(isUnknownPresence(driver.presence(of: target)),
            "Conflicting physical rows cannot establish absence")
        observer.devices = [anchoredPhysicalDevice(UUID(), verified: true)]
        #expect(isUnknownPresence(driver.presence(of: target)),
            "Reuse of the original BSD name is not proof that the old media left")
        observer.unavailable = true
        #expect(isUnknownPresence(driver.presence(of: target)),
            "An unavailable or malformed inventory cannot establish absence")
        observer.unavailable = false

        observer.devices = [anchoredPhysicalDevice(UUID(), bsd: "disk1", external: false),
            anchoredPhysicalDevice(UUID(), bsd: "disk99")]
        runner.diskListRows = [["DeviceIdentifier": "disk1"], ["DeviceIdentifier": "disk99"],
            ["DeviceIdentifier": "disk81"]]
        #expect(isUnknownPresence(driver.presence(of: target)),
            "A raw whole disk omitted by parsed inventory prevents absence")
        runner.diskListRows = [["DeviceIdentifier": "disk1"], ["DeviceIdentifier": "disk99"],
            ["DeviceIdentifier": "malformed-whole-disk"]]
        #expect(isUnknownPresence(driver.presence(of: target)),
            "A malformed whole-disk row prevents absence")
        runner.diskListRows = nil
        #expect(driver.presence(of: target) == .absent,
            "Complete unrelated system and verified external rows allow a scoped absence result")
        #expect(!runner.calls.contains { call in
            call.first == "/usr/sbin/diskutil" && ["unmount", "eject"].contains(call.dropFirst().first ?? "")
        })
    }

    @Test("Successful callback cannot mark a still-present identity-degraded disk safe to unplug")
    func callbackWithDegradedIdentityStaysPendingUntilAbsence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("whole-eject-degraded-presence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let anchor = UUID(), added = UUID()
        let observer = EjectFixtureObserver([anchoredPhysicalDevice(anchor)])
        let runner = EjectFixtureRunner(observer: observer)
        runner.afterEjectDevices = [anchoredPhysicalDevice(anchor, extraMember: added, verified: false)]
        let store = JSONStateStore(url: root.appendingPathComponent("state.json"))
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner, workingDirectory: root)
        let target = try #require(driver.observe(physicalIdentity: anchor.uuidString))
        let controller = StorageController(backend: EjectFixtureBackend(), store: store,
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        let first = controller.ejectWholeExternalDevice(physicalIdentity: anchor.uuidString,
            checkpoint: confirmed(target), driver: driver)
        #expect(!first.canUnplug)
        #expect(first.failure != nil)
        #expect(try store.load().ejectIntent)
        #expect(runner.calls.filter { $0 == ["/usr/sbin/diskutil", "eject", "/dev/disk81"] }.count == 1)

        let rechecked = controller.continueWholeExternalDeviceEject(checkpoint: confirmed(target), driver: driver)
        #expect(!rechecked.canUnplug)
        #expect(try store.load().ejectIntent)
        #expect(runner.calls.filter { $0 == ["/usr/sbin/diskutil", "eject", "/dev/disk81"] }.count == 1,
            "A callback recheck must never send a second eject")

        observer.devices = [anchoredPhysicalDevice(UUID(), bsd: "disk1", external: false)]
        let absent = controller.continueWholeExternalDeviceEject(checkpoint: confirmed(target), driver: driver)
        #expect(absent.canUnplug)
        #expect(try !store.load().ejectIntent)
        #expect(runner.calls.filter { $0 == ["/usr/sbin/diskutil", "eject", "/dev/disk81"] }.count == 1)
    }

    @Test("No-action Return can revalidate a degraded anchor without any disk mutation")
    func degradedAnchorNoActionReturnIsReadOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("whole-eject-anchor-return-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let anchor = UUID(), added = UUID()
        let observer = EjectFixtureObserver([anchoredPhysicalDevice(anchor)])
        let runner = EjectFixtureRunner(observer: observer)
        let initialDriver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root)
        let target = try #require(initialDriver.observe(physicalIdentity: anchor.uuidString))
        let journal = WholeDeviceEjectJournalRecord(operationID: "no-action-anchor-drift", target: target,
            phase: .interrupted)
        let degraded = anchoredPhysicalDevice(anchor, extraMember: added, verified: false)
        observer.devices = [degraded]
        runner.diskInfoByBSD["disk81s1"]?["VolumeUUID"] = anchor.uuidString
        runner.diskInfoByBSD["disk81s2"] = ["DeviceIdentifier": "disk81s2", "VirtualOrPhysical": "Physical",
            "PartOfWhole": "disk81", "VolumeUUID": added.uuidString]
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root, independentReturnValidator: { _ in true })
        #expect(driver.freshReturnIdentityMatches(journal))
        #expect(SectoriumWholeDeviceEjectDriver.freshUnissuedCancellationCandidate(
            journal: journal, devices: observer.devices, runner: runner, workingDirectory: root) != nil)

        observer.devices = [anchoredPhysicalDevice(UUID(), extraMember: added, verified: false)]
        #expect(!driver.freshReturnIdentityMatches(journal), "The original anchor UUID must still be present")
        observer.devices = [anchoredPhysicalDevice(anchor, bsd: "disk82", extraMember: added, verified: false)]
        #expect(!driver.freshReturnIdentityMatches(journal), "A changed whole BSD is not no-action cancellation")
        observer.devices = [degraded, anchoredPhysicalDevice(anchor, bsd: "disk82", verified: false)]
        #expect(!driver.freshReturnIdentityMatches(journal), "Duplicate anchors cannot authorize cancellation")
        observer.devices = [anchoredPhysicalDevice(anchor, extraMember: added, verified: false, mounted: false)]
        #expect(!driver.freshReturnIdentityMatches(journal), "All current members must remain mounted")
        observer.devices = [degraded]
        runner.diskListRows = [["DeviceIdentifier": "disk81"], ["DeviceIdentifier": "disk82"]]
        #expect(!driver.freshReturnIdentityMatches(journal),
            "A raw disk omitted by parsed inventory prevents cancellation")
        runner.diskListRows = nil
        runner.diskInfoByBSD["disk81s2"]?["PartOfWhole"] = "disk1"
        #expect(!driver.freshReturnIdentityMatches(journal), "Direct parent proof must match the old whole disk")
        runner.diskInfoByBSD["disk81s2"]?["PartOfWhole"] = "disk81"
        observer.unavailable = true
        #expect(!driver.freshReturnIdentityMatches(journal), "Observation failure cannot cancel intent")
        observer.unavailable = false

        let encoded = try JSONEncoder().encode(journal).base64EncodedString()
        let store = JSONStateStore(url: root.appendingPathComponent("state.json"))
        let active = StoragePersistentState(revision: 1, ejectIntent: true,
            operationID: journal.operationID, workbenchOperation: "eject:\(journal.operationID)",
            workbenchPhase: "eject:interrupted", workbenchTarget: encoded)
        #expect(try store.compareAndSwap(expectedRevision: 0, newState: active))
        let controller = StorageController(backend: EjectFixtureBackend(), store: store,
            lock: KernelOperationLock(url: root.appendingPathComponent("lock")))
        #expect(controller.returnFromWholeDeviceEject(physicalIdentity: anchor.uuidString, driver: driver))
        #expect(try !store.load().ejectIntent)
        #expect(!runner.calls.contains { call in
            call.first == "/usr/sbin/diskutil" && ["unmount", "eject"].contains(call.dropFirst().first ?? "")
        })
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
            installer: ejectFixtureInstaller(HESectoriumPaths(root: root)),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer,
            portableDocumentWriter: EjectFixturePortableWriter())
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

    @Test("Successful eject callback with unknown absence offers a presence-only recovery")
    func callbackRecoveryNeedsOnlyPresenceObservation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("whole-eject-callback-recheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let physicalID = UUID().uuidString, volumeID = UUID().uuidString.lowercased()
        let topology = WholeDeviceTopology(physicalIdentity: physicalID, bsdName: "disk81",
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(volumeID)|disk81s1", mounted: true)], images: [])
        let journal = WholeDeviceEjectJournalRecord(operationID: "callback-recheck", target: topology,
            phase: .ejectCallbackSucceeded,
            completedSteps: ["unmountAllPhysicalVolumes", "ejectWholeDevice"],
            lastReceipt: .completed("fixture callback"), lastIssuedAction: .ejectWholeDevice)
        let encoded = try JSONEncoder().encode(journal).base64EncodedString()
        let stateStore = JSONStateStore(url: root.appendingPathComponent("state.json"))
        let state = StoragePersistentState(revision: 1, ejectIntent: true,
            operationID: journal.operationID, workbenchOperation: "eject:\(journal.operationID)",
            workbenchPhase: "eject:callback-succeeded", workbenchTarget: encoded)
        #expect(try stateStore.compareAndSwap(expectedRevision: 0, newState: state))
        let observer = EjectFixtureObserver([])
        let runner = EjectFixtureRunner(observer: observer)
        runner.dfAvailable = false // Off-target mutation cannot be proven; presence-only recovery remains valid.
        let paths = HESectoriumPaths(root: root)
        let service = HESectoriumService(paths: paths, backend: EjectFixtureBackend(), store: stateStore,
            operationLock: KernelOperationLock(url: root.appendingPathComponent("lock")),
            installer: ejectFixtureInstaller(paths), runner: runner, identityPolicy: .expected,
            sectoriumDeviceObserver: observer, portableDocumentWriter: EjectFixturePortableWriter())
        #expect(service.pendingWholeDeviceEjectPhysicalIdentity() == physicalID)
        let prompt = try #require(service.prepareContinueWholeDeviceEjectConfirmation(physicalIdentity: physicalID))
        #expect(prompt.isContinuation && prompt.isObservationOnly)
        #expect(!prompt.dependenciesCanFinishOffTarget)
        let before = runner.calls.count
        let result = service.continueWholeDeviceEject(physicalIdentity: physicalID,
            checkpoint: prompt.checkpoint(knownWritersClosed: false))
        #expect(result.succeeded, "\(String(describing: result.failure))")
        #expect(service.pendingWholeDeviceEjectPhysicalIdentity() == nil)
        #expect(try stateStore.load().terminalEjectJournals[physicalID] != nil)
        #expect(!runner.calls.dropFirst(before).contains { call in
            call.first == "/usr/sbin/diskutil" && ["unmount", "eject"].contains(call.dropFirst().first ?? "")
        })
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
            installer: ejectFixtureInstaller(HESectoriumPaths(root: root)),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer,
            portableDocumentWriter: EjectFixturePortableWriter())
        service.selectSectoriumDevice(mediaUUID.uuidString)
        let topology = try #require(SectoriumWholeDeviceEjectDriver(observer: observer, runner: runner,
            workingDirectory: root).observe(physicalIdentity: mediaUUID.uuidString))
        let result = service.ejectSelectedExternalDevice(checkpoint: confirmed(topology))
        #expect(result.succeeded)
        let archived = try JSONStateStore(url: stateURL).load()
        #expect(!archived.ejectIntent)
        #expect(archived.workbenchOperation == nil)
        #expect(archived.terminalEjectJournals[mediaUUID.uuidString] != nil)
        observer.devices = [device]
        let freshService = HESectoriumService(paths: HESectoriumPaths(root: root), backend: EjectFixtureBackend(),
            store: JSONStateStore(url: stateURL), operationLock: KernelOperationLock(url: root.appendingPathComponent("lock")),
            installer: ejectFixtureInstaller(HESectoriumPaths(root: root)),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer,
            portableDocumentWriter: EjectFixturePortableWriter())
        freshService.selectSectoriumDevice(UUID().uuidString)
        #expect(!freshService.canReturnFromWholeDeviceEject())
        #expect(try JSONStateStore(url: stateURL).load().terminalEjectJournals[mediaUUID.uuidString] != nil)
        freshService.selectSectoriumDevice(mediaUUID.uuidString)
        #expect(freshService.pendingSectoriumOperation() == nil)
        #expect(freshService.canReturnFromWholeDeviceEject())
        let returned = freshService.returnToDevelopment()
        #expect(returned.succeeded, "\(String(describing: returned.failure))")
        #expect(try JSONStateStore(url: stateURL).load().ejectIntent == false)
        #expect(try JSONStateStore(url: stateURL).load().terminalEjectJournals[mediaUUID.uuidString] == nil)
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
            installer: ejectFixtureInstaller(HESectoriumPaths(root: root)),
            runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer,
            portableDocumentWriter: EjectFixturePortableWriter())
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
        let checkpoint = WholeDeviceEjectCheckpoint(
            confirmedExactTargetAndScope: true, knownWritersClosed: true, dependenciesCanFinishOffTarget: true,
            confirmedPhysicalIdentity: topology.physicalIdentity, confirmedMemberKey: topology.memberKey,
            confirmedAt: Date())
        for unsafeActivity in [CommandOutcome(exitCode: 0, detail: "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nEditor 123 user 3r REG fixture\n"),
                               CommandOutcome(exitCode: 1, detail: "fixture inspection denied")] {
            runner.occupancyOutcome = unsafeActivity
            let refused = service.ejectSelectedExternalDevice(checkpoint: checkpoint)
            #expect(!refused.succeeded)
            #expect(!runner.calls.contains { $0.first == "/usr/sbin/diskutil" && ["unmount", "eject"].contains($0.dropFirst().first ?? "") })
        }
        runner.occupancyOutcome = .init(exitCode: 1, detail: "")
        let result = service.ejectSelectedExternalDevice(checkpoint: checkpoint)
        #expect(result.succeeded)
        #expect(result.steps.contains { $0.step == "ejectWholeDevice" })
        #expect(runner.calls.contains(["/usr/sbin/lsof", "-nP", "-Fpcf", "+f", "--", "/dev/disk81s1"]))
        #expect(!runner.calls.contains(["/usr/bin/hdiutil", "detach", "/dev/disk90"]))
    }
}
