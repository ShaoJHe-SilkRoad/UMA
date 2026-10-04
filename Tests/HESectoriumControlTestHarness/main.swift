import Foundation
import Darwin
import HESectoriumCore
import HESectoriumRuntime
import HESectoriumCLI

private final class FixtureStateStore: DurableStateStore {
    private var state = StoragePersistentState(ejectIntent: false)
    func load() throws -> StoragePersistentState { state }
    func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
        guard state.revision == expectedRevision else { return false }
        state = newState
        return true
    }
}

private final class FixtureOperationLock: OperationLock {
    private var held = false
    func acquire() -> Bool { guard !held else { return false }; held = true; return true }
    func release() { held = false }
}

private final class FixtureStorageBackend: StorageBackend {
    var outer: VolumeIdentity? = StorageObservation.expectedReady.outer
    var observation: StorageObservation? = .expectedReady
    var occupancy: [OccupancyScope: OccupancyAssessment] = [.dev: .noVisibleOccupancy, .outer: .noVisibleOccupancy]
    var failFlush = false
    var failPostAttachObservation = false

    func observeOuter() -> VolumeIdentity? { outer }
    func observe() -> StorageObservation? { observation }
    func attachImage() -> CommandOutcome {
        if failPostAttachObservation { observation = nil }
        return .success
    }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { occupancy[scope] ?? .incomplete(reason: "fixture not configured") }
    func perform(_ step: EjectStep) -> CommandOutcome {
        step == .flush && failFlush ? .init(exitCode: 73, detail: "fixture flush refused") : .success
    }
    func finalOuterState() -> FinalOuterState { .absent }
}

private final class FixtureCommandService: HESectoriumCommandServing {
    private let controller: StorageController
    private let backend: FixtureStorageBackend

    init(scenario: String) {
        backend = FixtureStorageBackend()
        if scenario == "refused-mount" {
            backend.outer = .init(uuid: UUID(), mountPoint: "/Volumes/HE", fileSystem: "ExFAT", writable: true,
                                  name: "HE", rootMatchesExpected: true)
        }
        backend.failPostAttachObservation = scenario == "postcheck-mount"
        backend.failFlush = scenario == "failed-eject"
        controller = StorageController(backend: backend, store: FixtureStateStore(), lock: FixtureOperationLock())
    }

    func refreshStatus() -> HESectoriumRuntimeSnapshot {
        .init(installed: .missing, automationEnabled: false, readiness: .ready,
              pendingEject: false, diagnostics: [], latestActionSummary: "fixture status")
    }
    func mountDEV() -> OperationResult { controller.mountDEV() }
    func safeEjectHE() -> OperationResult { controller.safeEjectHE() }
    func installRepair(_ action: HESectoriumInstallAction) -> HESectoriumInstallResult {
        .init(succeeded: false, summary: "fixture installer is not configured")
    }
    func setAutomationEnabled(_ enabled: Bool) -> HESectoriumInstallResult {
        .init(succeeded: false, summary: "fixture automation is not configured")
    }
    func runAgent() -> Int32 { 1 }
}

private final class WorkbenchProcessRunner: HESectoriumCommandRunning {
    let backingMount: String
    let backingUUID: UUID
    let devMount: String
    let devUUID: UUID
    private(set) var commands: [[String]] = []
    init(backingMount: String, backingUUID: UUID, devMount: String, devUUID: UUID) {
        self.backingMount = backingMount; self.backingUUID = backingUUID
        self.devMount = devMount; self.devUUID = devUUID
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        commands.append([executable] + arguments)
        if executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", backingMount],
           let data = try? PropertyListSerialization.data(fromPropertyList: [
               "VolumeUUID": backingUUID.uuidString, "MountPoint": backingMount,
               "FilesystemType": "ExFAT", "WritableVolume": true, "VolumeName": "Fixture HE"
           ], format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        if executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", devMount],
           let data = try? PropertyListSerialization.data(fromPropertyList: [
               "VolumeUUID": devUUID.uuidString, "MountPoint": devMount,
               "FilesystemType": "APFS", "WritableVolume": true, "VolumeName": "Fixture",
               "DeviceIdentifier": "disk84s1", "APFSContainerReference": "disk84"
           ], format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        if executable == "/usr/bin/hdiutil", arguments == ["info", "-plist"],
           let data = try? PropertyListSerialization.data(fromPropertyList: ["images": []], format: .xml, options: 0) {
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        return .init(exitCode: 127, detail: "fresh-process fixture has no mutation command")
    }
}

private final class WorkbenchProcessObserver: SectoriumDeviceObserving {
    let devices: [SectoriumPhysicalDevice]
    init(devices: [SectoriumPhysicalDevice]) { self.devices = devices }
    func observeDevices() throws -> [SectoriumPhysicalDevice] { devices }
}

private func runWorkbenchProcessFixture(_ scenario: String, rootPath: String) -> Never {
    let root = URL(fileURLWithPath: rootPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    let backing = root.appendingPathComponent("outer", isDirectory: true)
    let image = backing.appendingPathComponent("Fixture.sparsebundle", isDirectory: true)
    let dev = backing.appendingPathComponent("DEV", isDirectory: true)
    let deviceID = UUID(uuidString: "1C3AEB51-192D-4A9C-A284-7D2C7716ACB1")!
    let volumeID = UUID(uuidString: "A5D98C49-1362-4CD6-9F0F-6A8BEB35E132")!
    let devID = UUID(uuidString: "D82AB1F4-54C6-4B0A-9391-2BDF0E2B9E10")!
    let paths = HESectoriumPaths(root: root.appendingPathComponent("support", isDirectory: true))
    do {
        try FileManager.default.createDirectory(at: backing, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: image, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dev, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let profile = SectoriumDevelopmentProfile(name: "Fixture", deviceID: deviceID.uuidString,
            backingVolumeUUID: volumeID, backingMountPoint: backing.path, imagePath: image.path,
            devVolumeName: "Fixture", devMountPoint: dev.path, devUUID: devID,
            encrypted: false, caseSensitive: true, logicalCapacityBytes: 1024,
            validation: .validated)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode([profile]).write(to: paths.sectoriumProfiles, options: .atomic)
        if scenario == "seed-interrupted-start" {
            let store = JSONStateStore(url: paths.state)
            guard try store.compareAndSwap(expectedRevision: 0, newState: StoragePersistentState(
                revision: 1, ejectIntent: false, operationID: "fixture-start",
                workbenchOperation: "start:fixture-start", workbenchPhase: "mutating:attachImage",
                workbenchTarget: image.path, workbenchCompletedStep: "prepareMountPoint")) else {
                throw RuntimeError.unsafePath("could not persist interrupted fixture state")
            }
            writeStdout("{\"seeded\":true}")
            exit(0)
        }
        let device = SectoriumPhysicalDevice(id: deviceID.uuidString, bsdName: "disk83", name: "Fixture HE",
            isExternal: true, identityVerified: true, wholeDeviceBytes: 1_000_000,
            mountedVolumePaths: [backing.path], volumeUUIDs: [volumeID], readBytes: nil, writtenBytes: nil)
        if scenario.hasPrefix("seed-validation-eject-") {
            let target = scenario.hasSuffix("-nil") ? nil : device.id
            let ejectID = "6A84E2D9-E928-4D4B-BD12-32A604B2925D"
            let store = JSONStateStore(url: paths.state)
            guard try store.compareAndSwap(expectedRevision: 0, newState: StoragePersistentState(
                revision: 1, ejectIntent: false, operationID: nil,
                workbenchOperation: "eject:\(ejectID)", workbenchPhase: "validating",
                workbenchTarget: target)) else {
                throw RuntimeError.unsafePath("could not persist validation-phase eject fixture state")
            }
            writeStdout("{\"seeded\":true}")
            exit(0)
        }
        guard scenario.hasPrefix("recover-validation-eject-") || scenario == "recover-interrupted-start" else {
            throw RuntimeError.unsafePath("unknown fixture scenario")
        }
        let runner = WorkbenchProcessRunner(backingMount: backing.path, backingUUID: volumeID,
                                            devMount: dev.path, devUUID: devID)
        let policy = StorageIdentityPolicy(outerUUID: volumeID, devUUID: devID, outerMountPoint: backing.path,
            devMountPoint: dev.path, devVolumeName: "Fixture", imagePath: image.path)
        let devices = scenario.hasSuffix("-ambiguous") ? [device, device] : [device]
        let service = HESectoriumService(paths: paths, runner: runner, identityPolicy: policy,
            sectoriumDeviceObserver: WorkbenchProcessObserver(devices: devices))
        service.selectSectoriumDevice(device.id)
        let result = scenario == "recover-interrupted-start"
            ? service.resumePendingSectoriumOperation()
            : service.returnToDevelopment()
        let state = try JSONStateStore(url: paths.state).load()
        let output: [String: Any] = ["succeeded": result.succeeded,
            "pending": state.workbenchOperation as Any? ?? NSNull(),
            "phase": state.workbenchPhase as Any? ?? NSNull(),
            "commands": runner.commands]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        writeStdout(String(decoding: data, as: UTF8.self))
        exit(0)
    } catch {
        writeStderr(String(describing: error) + "\n")
        exit(70)
    }
}

private func writeStdout(_ value: String) { print(value) }
private func writeStderr(_ value: String) { fputs(value, stderr) }

let scenario = CommandLine.arguments.dropFirst().first ?? "status"
if scenario == "hold-pipe-child" {
    guard CommandLine.arguments.count == 3 else { exit(64) }
    writeStdout("descendant opened pipe")
    writeStderr("descendant opened pipe\n")
    fflush(stdout); fflush(stderr)
    Thread.sleep(forTimeInterval: 3)
    try? Data("done".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
    exit(0)
}
if scenario == "hold-pipe-descendant" {
    guard CommandLine.arguments.count == 3 else { exit(64) }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["hold-pipe-child", CommandLine.arguments[2]]
    child.standardOutput = FileHandle.standardOutput
    child.standardError = FileHandle.standardError
    do { try child.run() }
    catch { writeStderr("could not start bounded fixture descendant: \(error)\n"); exit(70) }
    writeStdout("parent exited")
    fflush(stdout)
    exit(0)
}
if scenario == "large-output" {
    let out = Data(repeating: UInt8(ascii: "O"), count: 16_384)
    let err = Data(repeating: UInt8(ascii: "E"), count: 16_384)
    for _ in 0..<16 {
        FileHandle.standardOutput.write(out)
        FileHandle.standardError.write(err)
    }
    exit(17)
}
if scenario == "exit-15" { exit(15) }
if scenario == "signal-15" { raise(SIGTERM); exit(99) }
if scenario == "sleep-for-timeout" {
    writeStdout("fixture waiting")
    fflush(stdout)
    Thread.sleep(forTimeInterval: 10)
    exit(0)
}
if scenario.hasPrefix("r3-eject-") {
    guard CommandLine.arguments.count == 3 else { writeStderr("R3 fixture root required\n"); exit(64) }
    runR3EjectRecoveryFixture(String(scenario.dropFirst("r3-eject-".count)), rootPath: CommandLine.arguments[2])
}
if scenario == "seed-interrupted-start" || scenario == "recover-interrupted-start"
    || scenario.hasPrefix("seed-validation-eject-") || scenario.hasPrefix("recover-validation-eject-") {
    guard CommandLine.arguments.count == 3 else { writeStderr("fixture root required\n"); exit(64) }
    runWorkbenchProcessFixture(scenario, rootPath: CommandLine.arguments[2])
}
let command: String
switch scenario {
case "refused-mount", "postcheck-mount", "successful-mount": command = "mount"
case "failed-eject": command = "eject"
case "status": command = "status"
default:
    fputs("unknown fixture scenario\n", stderr)
    exit(64)
}

private let service = FixtureCommandService(scenario: scenario)
exit(HESectoriumCommandDispatcher.run(arguments: [command].dropFirst(0), service: service,
                                      writeStdout: writeStdout, writeStderr: writeStderr))
