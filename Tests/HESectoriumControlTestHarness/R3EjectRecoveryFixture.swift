import Foundation
import Darwin
import HESectoriumCore
import HESectoriumRuntime

private final class R3FixtureObserver: SectoriumDeviceObserving {
    var devices: [SectoriumPhysicalDevice]
    init(_ devices: [SectoriumPhysicalDevice]) { self.devices = devices }
    func observeDevices() throws -> [SectoriumPhysicalDevice] { devices }
}

private final class R3FixtureRunner: HESectoriumTimedCommandRunning {
    let observer: R3FixtureObserver
    let root: URL
    let support: URL
    let managed: Bool
    var stateURL: URL?
    var failBSD: String?
    var crashAfterBSD: String?
    var busyAfterEffectBSD: String?
    var noEffectBSD: String?
    var ejectHasNoEffect = false
    var inventoryUnknown = false
    private(set) var calls: [[String]] = []
    private(set) var mutationRecords: [[String: Any]] = []
    var diskInfo: [String: [String: Any]] = [:]
    var images: [[String: Any]] = []
    var apfsContainers: [[String: Any]] = []

    init(observer: R3FixtureObserver, root: URL, support: URL, managed: Bool) {
        self.observer = observer; self.root = root; self.support = support; self.managed = managed
        diskInfo = [
            "disk1": ["DeviceIdentifier": "disk1", "VirtualOrPhysical": "Physical"],
            "disk1s1": ["DeviceIdentifier": "disk1s1", "VirtualOrPhysical": "Physical", "PartOfWhole": "disk1"],
            "disk81": ["DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical"],
            "disk81s1": ["DeviceIdentifier": "disk81s1", "VirtualOrPhysical": "Physical", "PartOfWhole": "disk81"],
            "disk81s2": ["DeviceIdentifier": "disk81s2", "VirtualOrPhysical": "Physical", "PartOfWhole": "disk81"],
            "disk30": ["DeviceIdentifier": "disk30", "VirtualOrPhysical": "Virtual"],
            "disk31s1": ["DeviceIdentifier": "disk31s1", "VirtualOrPhysical": "Virtual", "APFSContainerReference": "disk31"]
        ]
        if managed {
            apfsContainers = [["ContainerReference": "disk31", "PhysicalStores": [["DeviceIdentifier": "disk30"]]]]
        }
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        run(executable, arguments, cwd: cwd)
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        calls.append([executable] + arguments)
        if executable == "/bin/df", arguments.count == 2, arguments[0] == "-P" {
            guard !inventoryUnknown else { return .init(exitCode: 1, detail: "fixture observation unavailable") }
            let path = arguments[1]
            let target = root.appendingPathComponent("external", isDirectory: true).path
            let source = path == target || path.hasPrefix(target + "/") ? "/dev/disk81s1" : "/dev/disk1s1"
            return .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity Mounted on\n\(source) 1000 10 990 1% /fixture\n")
        }
        if executable == "/usr/sbin/diskutil", arguments.count == 3,
           arguments[0] == "info", arguments[1] == "-plist", arguments[2].hasPrefix("/dev/") {
            let bsd = String(arguments[2].dropFirst(5))
            return diskInfo[bsd].map(plist) ?? .init(exitCode: 127, detail: "unknown fixture disk")
        }
        if executable == "/usr/sbin/diskutil", arguments == ["apfs", "list", "-plist"] {
            return plist(["Containers": apfsContainers])
        }
        if executable == "/usr/bin/hdiutil", arguments == ["info", "-plist"] {
            return plist(["images": images])
        }
        if executable == "/usr/sbin/diskutil", arguments.count == 2,
           arguments[0] == "unmount", arguments[1].hasPrefix("/dev/disk31s") {
            let node = arguments[1]
            if let failBSD, node == "/dev/\(failBSD)" { return .init(exitCode: 1, detail: "Resource busy") }
            images = images.map { row in
                var row = row
                row["system-entities"] = (row["system-entities"] as? [[String: Any]] ?? []).map { entity in
                    var entity = entity
                    if entity["dev-entry"] as? String == node { entity.removeValue(forKey: "mount-point") }
                    return entity
                }
                return row
            }
            return .success
        }
        if executable == "/usr/bin/hdiutil", arguments.count == 2,
           arguments[0] == "detach", arguments[1] == "/dev/disk30" {
            images.removeAll()
            observer.devices.removeAll { $0.bsdName == "disk30" }
            return .success
        }
        if executable == "/usr/sbin/diskutil", arguments.count == 2,
           arguments[0] == "unmount", arguments[1].hasPrefix("/dev/disk81s") {
            recordMutation([executable] + arguments)
            let bsd = String(arguments[1].dropFirst(5))
            if let failBSD, bsd == failBSD { return .init(exitCode: 1, detail: "Resource busy") }
            if bsd != noEffectBSD { setMounted(bsd, false) }
            if bsd == crashAfterBSD { FileHandle.standardOutput.write(Data("fixture interrupted after injected unmount\n".utf8)); Darwin.exit(86) }
            if bsd == busyAfterEffectBSD { return .init(exitCode: 1, detail: "Resource busy after exact member became unmounted") }
            return .success
        }
        if executable == "/usr/sbin/diskutil", arguments == ["eject", "/dev/disk81"] {
            recordMutation([executable] + arguments)
            if !ejectHasNoEffect { observer.devices.removeAll { $0.bsdName == "disk81" } }
            return .success
        }
        return .init(exitCode: 127, detail: "unconfigured R3 fixture command")
    }

    private func recordMutation(_ command: [String]) {
        let stateURL = support.appendingPathComponent("state.json")
        let raw = (try? Data(contentsOf: stateURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        var journal: [String: Any] = [:]
        if let encoded = raw?["workbenchTarget"] as? String,
           let data = Data(base64Encoded: encoded),
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { journal = value }
        mutationRecords.append(["command": command, "durableStateBeforeCommand": raw as Any? ?? NSNull(), "journalBeforeCommand": journal])
    }

    private func setMounted(_ bsd: String, _ mounted: Bool) {
        observer.devices = observer.devices.map { device in
            guard device.bsdName == "disk81" else { return device }
            let members = device.volumeMembers.map { member in
                member.bsdName == bsd ? SectoriumPhysicalVolumeMember(bsdName: member.bsdName,
                    volumeUUID: member.volumeUUID, mounted: mounted, mountPoint: mounted ? member.mountPoint : nil) : member
            }
            return SectoriumPhysicalDevice(id: device.id, bsdName: device.bsdName, name: device.name,
                isExternal: device.isExternal, identityVerified: device.identityVerified,
                wholeDeviceBytes: nil, mountedVolumePaths: members.compactMap(\.mountPoint),
                volumeUUIDs: members.map(\.volumeUUID), readBytes: nil, writtenBytes: nil,
                volumeMembers: members, topologyComplete: device.topologyComplete, isVirtual: false)
        }
    }

    private func plist(_ value: [String: Any]) -> CommandOutcome {
        let data = try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
    }
}

private final class R3UnusedBackend: StorageBackend {
    func observeOuter() -> VolumeIdentity? { nil }
    func observe() -> StorageObservation? { nil }
    func attachImage() -> CommandOutcome { .init(exitCode: 127, detail: "unused fixture backend") }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { .incomplete(reason: "unused") }
    func perform(_ step: EjectStep) -> CommandOutcome { .init(exitCode: 127, detail: "unused fixture backend") }
    func finalOuterState() -> FinalOuterState { .unknown("unused") }
}

private let r3MediaID = UUID(uuidString: "148CC6E1-CB27-4C60-BB27-B61C0A5A4001")!
private let r3FirstID = UUID(uuidString: "148CC6E1-CB27-4C60-BB27-B61C0A5A4002")!
private let r3SecondID = UUID(uuidString: "148CC6E1-CB27-4C60-BB27-B61C0A5A4003")!
private let r3ImageID = UUID(uuidString: "148CC6E1-CB27-4C60-BB27-B61C0A5A4004")!

private func r3Device(_ root: URL, members: [(UUID, String, Bool)], identity: String? = nil) -> SectoriumPhysicalDevice {
    let rows = members.map { uuid, bsd, mounted in
        SectoriumPhysicalVolumeMember(bsdName: bsd, volumeUUID: uuid, mounted: mounted,
            mountPoint: mounted ? root.appendingPathComponent(bsd == "disk81s1" ? "external" : "second").path : nil)
    }
    return SectoriumPhysicalDevice(id: identity ?? r3MediaID.uuidString, bsdName: "disk81", name: "R3 isolated fixture",
        isExternal: true, identityVerified: true, wholeDeviceBytes: nil,
        mountedVolumePaths: rows.compactMap(\.mountPoint), volumeUUIDs: rows.map(\.volumeUUID),
        readBytes: nil, writtenBytes: nil, volumeMembers: rows, topologyComplete: true, isVirtual: false)
}

private func r3Images(_ root: URL) -> [[String: Any]] {
    [["image-path": root.appendingPathComponent("external/Development.sparsebundle").path,
      "system-entities": [["dev-entry": "/dev/disk30"],
                          ["dev-entry": "/dev/disk31s1", "volume-uuid": r3ImageID.uuidString,
                           "mount-point": root.appendingPathComponent("DEV").path]]]]
}

private func r3Profile(_ root: URL) -> SectoriumDevelopmentProfile {
    SectoriumDevelopmentProfile(name: "Development", deviceID: r3MediaID.uuidString,
        backingVolumeUUID: r3FirstID, backingMountPoint: root.appendingPathComponent("external").path,
        imagePath: root.appendingPathComponent("external/Development.sparsebundle").path,
        devVolumeName: "DEV_APFS", devMountPoint: root.appendingPathComponent("DEV").path,
        devUUID: r3ImageID, encrypted: false, caseSensitive: false, logicalCapacityBytes: 1_073_741_824,
        imageFormat: "UDSB", validation: .validated)
}

private func r3MakeRuntime(_ root: URL, _ mode: String) throws -> (HESectoriumService, R3FixtureObserver, R3FixtureRunner, URL) {
    let support = root.appendingPathComponent("support", isDirectory: true)
    let external = root.appendingPathComponent("external", isDirectory: true)
    let second = root.appendingPathComponent("second", isDirectory: true)
    let dev = root.appendingPathComponent("DEV", isDirectory: true)
    for path in [support, external, second, dev, external.appendingPathComponent("Development.sparsebundle")] {
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }
    let managed = mode.contains("managed")
    let crashSeed = mode.hasPrefix("seed")
    let initial = crashSeed
        ? [(r3FirstID, "disk81s1", true), (r3SecondID, "disk81s2", true)].prefix(mode == "seed-first-issued" ? 1 : 2).map { $0 }
        : mode.contains("first-issued") ? [(r3FirstID, "disk81s1", false)]
        : mode.contains("second-issued") ? [(r3FirstID, "disk81s1", false), (r3SecondID, "disk81s2", false)]
        : mode.contains("second-unexpected-absent") ? [(r3FirstID, "disk81s1", false), (r3SecondID, "disk81s2", false)]
        : [(r3FirstID, "disk81s1", false), (r3SecondID, "disk81s2", true)]
    var device = r3Device(root, members: initial)
    if mode.contains("replacement") { device = r3Device(root, members: initial, identity: UUID().uuidString) }
    if mode.contains("missing-member") { device = r3Device(root, members: Array(initial.dropLast())) }
    if mode.contains("new-member") {
        device = r3Device(root, members: initial + [(UUID(uuidString: "148CC6E1-CB27-4C60-BB27-B61C0A5A4005")!, "disk81s3", true)])
    }
    let observer = R3FixtureObserver(managed ? [device, SectoriumPhysicalDevice(id: "virtual-image",
        bsdName: "disk30", name: "R3 virtual fixture", isExternal: false, identityVerified: true,
        wholeDeviceBytes: nil, mountedVolumePaths: [dev.path], volumeUUIDs: [r3ImageID], readBytes: nil,
        writtenBytes: nil, volumeMembers: [.init(bsdName: "disk31s1", volumeUUID: r3ImageID,
        mounted: true, mountPoint: dev.path)], topologyComplete: true, isVirtual: true)] : [device])
    let runner = R3FixtureRunner(observer: observer, root: root, support: support, managed: managed)
    if managed {
        runner.diskInfo["disk31s1"] = ["DeviceIdentifier": "disk31s1", "VirtualOrPhysical": "Virtual", "APFSContainerReference": "disk31"]
        runner.images = r3Images(root)
        try JSONEncoder().encode([r3Profile(root)]).write(to: HESectoriumPaths(root: support).sectoriumProfiles, options: .atomic)
    }
    if mode.hasPrefix("recover") {
        // The durable physical image-detach boundary exists, so the current process observes no attached image.
        runner.images = []
        observer.devices.removeAll { $0.bsdName == "disk30" }
    } else if mode == "seed-first-issued" { runner.crashAfterBSD = "disk81s1" }
    else if mode == "seed-second-issued" { runner.crashAfterBSD = "disk81s2" }
    else if mode == "seed-second-unexpected-absent" { runner.busyAfterEffectBSD = "disk81s2" }
    else if mode == "seed-managed-second" { runner.failBSD = "disk81s2" }
    runner.inventoryUnknown = mode.contains("unknown")
    runner.failBSD = mode.contains("busy-again") ? "disk81s2" : runner.failBSD
    runner.noEffectBSD = mode.contains("postcheck") ? "disk81s2" : nil
    runner.ejectHasNoEffect = mode.contains("eject-present")

    let service = HESectoriumService(paths: HESectoriumPaths(root: support),
        backend: R3UnusedBackend(), store: JSONStateStore(url: support.appendingPathComponent("state.json")),
        operationLock: KernelOperationLock(url: support.appendingPathComponent("operation.lock")),
        runner: runner, identityPolicy: .expected, sectoriumDeviceObserver: observer)
    service.selectSectoriumDevice(r3MediaID.uuidString)
    runner.stateURL = support.appendingPathComponent("state.json")
    return (service, observer, runner, support)
}

private func requireR3<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "R3 fixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "required isolated observation missing"]) }
    return value
}

func runR3EjectRecoveryFixture(_ scenario: String, rootPath: String) -> Never {
    do {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        let (service, _, runner, support) = try r3MakeRuntime(root, scenario)
        if scenario.hasPrefix("seed") {
            let prompt = try requireR3(service.prepareWholeDeviceEjectConfirmation())
            let result = service.ejectSelectedExternalDevice(checkpoint: prompt.checkpoint(knownWritersClosed: true))
            if scenario == "seed-managed-second" || scenario == "seed-second-unexpected-absent" {
                let state = try JSONStateStore(url: support.appendingPathComponent("state.json")).load()
                let output: [String: Any] = ["seeded": true, "succeeded": result.succeeded,
                    "intent": state.ejectIntent, "phase": state.workbenchPhase ?? "unknown",
                    "mutations": runner.mutationRecords]
                writeR3(output)
                exit(0)
            }
            throw NSError(domain: "R3 fixture", code: 3, userInfo: [NSLocalizedDescriptionKey: "crash boundary not reached"])
        }
        let generic = service.resumePendingSectoriumOperation()
        let returned = service.returnToDevelopment()
        let confirmation = service.prepareContinueWholeDeviceEjectConfirmation()
        var checkpoint = confirmation?.checkpoint(knownWritersClosed: !scenario.contains("no-ack"))
        if scenario.contains("stale"), let confirmation { checkpoint = confirmation.checkpoint(knownWritersClosed: true, confirmedAt: Date().addingTimeInterval(-121)) }
        if scenario.contains("wrong-checkpoint"), let confirmation {
            checkpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: true,
                dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: "wrong",
                confirmedMemberKey: confirmation.memberKey, confirmedAt: Date())
        }
        let held = scenario.contains("held-lock") ? KernelOperationLock(url: support.appendingPathComponent("operation.lock")) : nil
        let lockHeld = held?.acquire() ?? false
        runner.stateURL = support.appendingPathComponent("state.json")
        let before = runner.mutationRecords.count
        let result = checkpoint.map { service.continueWholeDeviceEject(checkpoint: $0) }
        if lockHeld { held?.release() }
        let repeated = scenario.contains("repeat") ? checkpoint.map { service.continueWholeDeviceEject(checkpoint: $0) } : nil
        let state = try JSONStateStore(url: support.appendingPathComponent("state.json")).load()
        let journal = state.workbenchTarget.flatMap { Data(base64Encoded: $0) }.flatMap { try? JSONDecoder().decode(WholeDeviceEjectJournalRecord.self, from: $0) }
        let mutations = runner.mutationRecords
        let durability = mutations.allSatisfy { row in
            guard let durable = row["durableStateBeforeCommand"] as? [String: Any],
                  durable["ejectIntent"] as? Bool == true,
                  let journal = row["journalBeforeCommand"] as? [String: Any],
                  let issued = journal["lastIssuedAction"] as? String,
                  let command = row["command"] as? [String] else { return false }
            return command.contains("eject") ? issued == "ejectWholeDevice" : issued == "physicalVolumesUnmount"
        }
        let output: [String: Any] = ["scenario": scenario, "succeeded": result?.succeeded ?? false,
            "confirmationAvailable": confirmation != nil, "genericResumeSucceeded": generic.succeeded,
            "returnSucceeded": returned.succeeded, "failure": result.map { String(describing: $0.failure) } ?? "no fresh confirmation",
            "pending": state.workbenchOperation ?? "none", "intent": state.ejectIntent,
            "phase": journal?.phase.rawValue ?? "unknown", "completedSteps": journal?.completedSteps ?? [],
            "repeatSucceeded": repeated?.succeeded ?? false, "durableBeforeEveryMutation": durability,
            "mutations": Array(mutations.dropFirst(before)), "commands": runner.calls]
        writeR3(output)
        exit(0)
    } catch {
        fputs("R3 fixture error: \(error)\n", stderr)
        exit(70)
    }
}

private func writeR3(_ value: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch { fputs("R3 fixture JSON error: \(error)\n", stderr) }
}
