import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

/// Explicit opt-in: metadata only. This cannot attach, detach, unmount, eject,
/// scan occupancy, read project contents, or change installed configuration.
private final class MetadataOnlyLatencyRunner: HESectoriumTimedCommandRunning {
    let base = ProcessCommandRunner()
    var commands = 0
    var refused = 0
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        run(executable, arguments, cwd: cwd, timeout: 8)
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        let allowed = ProcessCommandRunner.isReadOnlyPropertyList(executable: executable, arguments: arguments)
            || (executable == "/bin/df" && arguments.count == 2 && arguments[0] == "-P" && arguments[1].hasPrefix("/"))
        guard allowed else {
            refused += 1
            return .init(exitCode: 127, detail: "operation excluded by metadata-only probe")
        }
        commands += 1
        return base.run(executable, arguments, cwd: cwd, timeout: timeout)
    }
}

private final class NativeDiskHintCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var hints: [SectoriumDiskChange] = []
    func append(_ hint: SectoriumDiskChange) { lock.lock(); defer { lock.unlock() }; hints.append(hint) }
    var count: Int { lock.lock(); defer { lock.unlock() }; return hints.count }
}

@Suite("Opt-in read-only native latency probe", .serialized)
struct SectoriumReadOnlyLatencyProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUV_SECTORIUM_RECOVERY_PROBE"] == "1"))
    func actualEjectRecoveryUsesCopiedStateAndMetadataOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-recovery-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root.resolvingSymlinksInPath())
        var originals: [URL: Data] = [:]
        for name in ["sectorium-profiles.json", "storage-identity.json", "state.json"] {
            let origin = HESectoriumPaths.user.root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: origin.path) {
                let data = try Data(contentsOf: origin)
                originals[origin] = data
                try data.write(to: paths.root.appendingPathComponent(name))
            }
        }
        let store = JSONStateStore(url: paths.root.appendingPathComponent("state.json"))
        let before = try store.load()
        let runner = MetadataOnlyLatencyRunner()
        let service = HESectoriumService(paths: paths,
            installer: HESectoriumInstaller(paths: paths, home: paths.root.appendingPathComponent("fixture-home")),
            runner: runner)
        let start = ProcessInfo.processInfo.systemUptime
        let changed = service.reconcileWholeDeviceEjectRecovery()
        let after = try store.load()
        print("NATIVE_EJECT_RECOVERY changed=\(changed) pending_before=\(before.workbenchOperation ?? "none") pending_after=\(after.workbenchOperation ?? "none") result=\(after.workbenchTerminalResult ?? "none") commands=\(runner.commands) seconds=\(ProcessInfo.processInfo.systemUptime-start) refused=\(runner.refused)")
        #expect(before.workbenchOperation?.hasPrefix("eject:") == true)
        #expect(changed && !after.ejectIntent && after.workbenchOperation == nil)
        #expect(after.workbenchTerminalResult == "returned-to-development")
        #expect(runner.refused == 0)
        for (origin, bytes) in originals { #expect(try Data(contentsOf: origin) == bytes) }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUV_SECTORIUM_EVENT_PROBE"] == "1"))
    func nativeConsistencyAndInitialDiskNotificationsAreReadOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-event-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root.resolvingSymlinksInPath())
        var originals: [URL: Data] = [:]
        for name in ["sectorium-profiles.json", "storage-identity.json", "state.json"] {
            let origin = HESectoriumPaths.user.root.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: origin.path) {
                let data = try Data(contentsOf: origin)
                originals[origin] = data
                try data.write(to: paths.root.appendingPathComponent(name))
            }
        }
        let runner = MetadataOnlyLatencyRunner()
        let service = HESectoriumService(paths: paths,
            installer: HESectoriumInstaller(paths: paths, home: paths.root.appendingPathComponent("fixture-home")),
            runner: runner)
        var first: SectoriumConsistencyStamp?
        for round in 1...3 {
            let start = ProcessInfo.processInfo.systemUptime
            let previousCount = runner.commands
            let stamp = try #require(service.observeSectoriumConsistency())
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            if let first { #expect(stamp == first) } else { first = stamp }
            #expect(runner.commands - previousCount == 2)
            #expect(runner.refused == 0)
            print("NATIVE_CONSISTENCY round=\(round) commands=\(runner.commands - previousCount) seconds=\(elapsed) unchanged=\(stamp == first)")
        }
        let capture = NativeDiskHintCapture()
        let observer = try #require(makeSystemSectoriumDiskChangeObserver { capture.append($0) })
        observer.start()
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while capture.count == 0 && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        observer.stop()
        let stoppedCount = capture.count
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(stoppedCount > 0)
        #expect(capture.count == stoppedCount)
        print("NATIVE_DISK_NOTIFICATIONS initial_hints=\(stoppedCount) stopped_delivery=true disk_mutations=0")
        for (origin, before) in originals { #expect(try Data(contentsOf: origin) == before) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUV_SECTORIUM_READONLY_LATENCY_PROBE"] == "1"))
    func repeatedNativeTopologyAndDependencyObservations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-metadata-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = MetadataOnlyLatencyRunner()
        let scoped = SectoriumObservationCommandRunner(base)
        let observer = SystemSectoriumDeviceObserver(runner: scoped, workingDirectory: root)
        let driver = SectoriumWholeDeviceEjectDriver(observer: observer, runner: scoped, workingDirectory: root)
        for round in 1...4 {
            let started = ProcessInfo.processInfo.systemUptime
            let before = base.commands
            let observation = { () throws -> (Int, Bool, Bool) in
                let devices = try observer.observeDevices()
                var physicalCount = 0
                var external: SectoriumPhysicalDevice?
                for device in devices where device.isVirtual != true {
                    physicalCount += 1
                    if external == nil && device.isExternal && device.identityVerified { external = device }
                }
                let target = try #require(external)
                let topology = driver.observe(physicalIdentity: target.id)
                let dependencies = SectoriumOffTargetDependencyCheck.canFinishOffTarget(
                    paths: .init(root: root), targetBSDName: target.bsdName, runner: scoped)
                return (physicalCount, topology != nil, dependencies)
            }
            let result = try round == 4 ? scoped.withFreshObservation(observation) : scoped.withObservation(observation)
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            print("NATIVE_METADATA_LATENCY round=\(round) fresh_foreground=\(round == 4) physical_devices=\(result.0) topology_verified=\(result.1) dependencies_off_target=\(result.2) commands=\(base.commands - before) seconds=\(elapsed)")
            #expect(result.1)
            #expect(result.2)
            #expect(base.refused == 0)
        }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUV_SECTORIUM_READONLY_LATENCY_PROBE"] == "1"))
    func actualRegisteredExternalVolumeReadinessFromCopiedMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-registration-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root.resolvingSymlinksInPath())
        let installed = HESectoriumPaths.user.root
        var originals: [URL: Data] = [:]
        // Only known management metadata is copied; no development files,
        // directory enumeration, installed writes, or portable document access.
        for name in ["sectorium-profiles.json", "storage-identity.json", "state.json", "sectorium-document-journal.json"] {
            let origin = installed.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: origin.path) {
                let data = try Data(contentsOf: origin)
                originals[origin] = data
                try data.write(to: paths.root.appendingPathComponent(name))
            }
        }
        let runner = MetadataOnlyLatencyRunner()
        let service = HESectoriumService(paths: paths,
            installer: HESectoriumInstaller(paths: paths, home: paths.root.appendingPathComponent("fixture-home")),
            runner: runner)
        for round in 1...3 {
            let started = ProcessInfo.processInfo.systemUptime
            let before = runner.commands
            var selectedPhysicalIdentity: String?
            let result = try service.withReadOnlyObservation { () throws -> (Int, Int, Int) in
                let devices = try service.observeSectoriumDevices()
                let external = Set(devices.filter { $0.isExternal && $0.isVirtual == false && $0.identityVerified }.map(\.id))
                guard let saved = service.sectoriumProfilesObservation(resolvePaths: false) else {
                    throw NSError(domain: "ReadOnlyProbe", code: 1)
                }
                var seen = 0, ready = 0, pendingDocuments = 0
                for entry in saved where external.contains(entry.deviceID) {
                    guard let profile = service.sectoriumProfileObservation(profileID: entry.id) else { continue }
                    seen += 1
                    if selectedPhysicalIdentity == nil { selectedPhysicalIdentity = profile.deviceID }
                    if service.verifiedLoadedState(profileID: profile.id) == true
                        && service.canPrepareWholeDeviceEjectConfirmation(physicalIdentity: profile.deviceID) { ready += 1 }
                    if service.portableDocumentationPending(profileID: profile.id) { pendingDocuments += 1 }
                }
                return (seen, ready, pendingDocuments)
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            print("REGISTERED_VOLUME_LATENCY round=\(round) external_profiles=\(result.0) loaded_eject_qualified=\(result.1) pending_documents=\(result.2) commands=\(runner.commands-before) seconds=\(elapsed)")
            #expect(result.0 > 0)
            #expect(result.0 == result.1)
            #expect(runner.refused == 0)
            // Exercise the real button's read-only preparation as well as its
            // passive availability. No confirmation is submitted for execution.
            let selected = try #require(selectedPhysicalIdentity)
            let preflightStarted = ProcessInfo.processInfo.systemUptime
            let preflightCommands = runner.commands
            let confirmation = service.prepareWholeDeviceEjectConfirmation(physicalIdentity: selected)
            let preflightElapsed = ProcessInfo.processInfo.systemUptime - preflightStarted
            print("REGISTERED_EJECT_PREFLIGHT_LATENCY round=\(round) confirmed=\(confirmation != nil) dependencies_off_target=\(confirmation?.dependenciesCanFinishOffTarget == true) commands=\(runner.commands-preflightCommands) seconds=\(preflightElapsed)")
            #expect(confirmation?.physicalIdentity == selected)
            #expect(confirmation?.dependenciesCanFinishOffTarget == true)
            #expect(runner.refused == 0)
        }
        for (origin, before) in originals { #expect(try Data(contentsOf: origin) == before) }
    }

}
