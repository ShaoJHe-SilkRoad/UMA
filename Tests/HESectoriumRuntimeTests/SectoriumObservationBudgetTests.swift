import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

private final class ObservationClock {
    var time: TimeInterval = 100
}

private final class SlowObservationRunner: HESectoriumTimedCommandRunning, HESectoriumSecureCommandRunning {
    let clock: ObservationClock
    var cost: TimeInterval = 0.25
    var unavailable = false
    var calls: [[String]] = []
    var allowances: [TimeInterval] = []
    init(_ clock: ObservationClock) { self.clock = clock }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        calls.append([executable] + arguments)
        clock.time += cost
        return .init(exitCode: unavailable ? 1 : 0, detail: "read-\(calls.count)")
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        allowances.append(timeout)
        calls.append([executable] + arguments)
        clock.time += min(cost, timeout)
        return .init(exitCode: cost >= timeout || unavailable ? 1 : 0, detail: "read-\(calls.count)")
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, standardInput: Data) -> CommandOutcome {
        run(executable, arguments, cwd: cwd)
    }
}

private final class CountingObservationDeviceSource: SectoriumDeviceObserving {
    enum Unavailable: Error { case fixture }
    var calls = 0
    var fails = false
    func observeDevices() throws -> [SectoriumPhysicalDevice] {
        calls += 1
        if fails { throw Unavailable.fixture }
        return []
    }
}

/// Blocks a disposable install before it can write anything, while the Service
/// owns its operation lock. No native command or installed path is involved.
private final class ObservationOperationGate: OperationLock, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    func acquire() -> Bool {
        entered.signal()
        _ = resume.wait(timeout: .now() + 5)
        return false
    }
    func release() {}
}

private func observationSignal(_ semaphore: DispatchSemaphore, seconds: Double) -> Bool {
    semaphore.wait(timeout: .now() + seconds) == .success
}

struct SectoriumObservationBudgetTests {
    private let cwd = URL(fileURLWithPath: "/synthetic/observation")

    @Test("Display inventory is independent of an active Service operation and never establishes readiness")
    func displayInventoryDoesNotWaitForServiceOperation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-display-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root.resolvingSymlinksInPath())
        let gate = ObservationOperationGate(), source = CountingObservationDeviceSource()
        let base = SlowObservationRunner(ObservationClock())
        let service = HESectoriumService(paths: paths, operationLock: gate,
            installer: HESectoriumInstaller(paths: paths, home: root.appendingPathComponent("home")),
            runner: base, sectoriumDeviceObserver: source)
        let operation = Task.detached { service.installRepair(.repair) }
        let held = await Task.detached { observationSignal(gate.entered, seconds: 3) }.value
        guard held else { gate.resume.signal(); _ = await operation.value; Issue.record("Fixture gate unavailable"); return }
        let displayed = DispatchSemaphore(value: 0)
        let display = Task.detached {
            defer { displayed.signal() }
            return try service.observeSectoriumInventoryForDisplay()
        }
        let completedBeforeRelease = await Task.detached { observationSignal(displayed, seconds: 1) }.value
        gate.resume.signal()
        #expect(completedBeforeRelease)
        #expect(try await display.value.isEmpty)
        #expect(!(await operation.value).succeeded)
        #expect(source.calls == 1 && base.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: paths.sectoriumProfiles.path))
    }

    @Test("A passive observation starts its budget after the active Service operation releases its lock")
    func serviceObservationWaitsBeforeStartingItsScope() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-observation-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root.resolvingSymlinksInPath())
        let gate = ObservationOperationGate()
        let source = CountingObservationDeviceSource()
        let base = SlowObservationRunner(ObservationClock())
        let service = HESectoriumService(paths: paths, operationLock: gate,
            installer: HESectoriumInstaller(paths: paths, home: root.appendingPathComponent("home")),
            runner: base, sectoriumDeviceObserver: source)
        let operation = Task.detached { service.installRepair(.repair) }
        let held = await Task.detached { observationSignal(gate.entered, seconds: 3) }.value
        guard held else {
            gate.resume.signal(); _ = await operation.value
            Issue.record("The isolated operation did not acquire the Service lock")
            return
        }
        let requested = DispatchSemaphore(value: 0), observing = DispatchSemaphore(value: 0)
        let observation = Task.detached {
            requested.signal()
            return try service.withReadOnlyObservation {
                observing.signal()
                let first = try service.observeSectoriumDevices()
                // Nested calls retain one cache/deadline and the recursive lock.
                let nested = try service.withReadOnlyObservation { try service.observeSectoriumDevices() }
                return first.isEmpty && nested.isEmpty
            }
        }
        let queued = await Task.detached { observationSignal(requested, seconds: 3) }.value
        let startedWhileBlocked = await Task.detached { observationSignal(observing, seconds: 0.05) }.value
        gate.resume.signal()
        #expect(queued && !startedWhileBlocked)
        #expect(!(await operation.value).succeeded)
        #expect(try await observation.value)
        #expect(source.calls == 1 && base.calls.isEmpty)
        // A new scope must observe a new failure, never reuse the earlier result.
        source.fails = true
        service.withReadOnlyObservation { () -> Void in
            #expect(throws: CountingObservationDeviceSource.Unavailable.self) { try service.observeSectoriumDevices() }
        }
        #expect(source.calls == 2)
    }

    @Test("Throwing from a nested observation releases its Service lock and cached result")
    func throwingObservationReleasesLockForAnotherThread() async throws {
        enum EndObservation: Error { case fixture }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-observation-throw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root.resolvingSymlinksInPath())
        let source = CountingObservationDeviceSource()
        let service = HESectoriumService(paths: paths,
            installer: HESectoriumInstaller(paths: paths, home: root.appendingPathComponent("home")),
            runner: SlowObservationRunner(ObservationClock()), sectoriumDeviceObserver: source)
        #expect(throws: EndObservation.self) {
            try service.withReadOnlyObservation {
                _ = try service.observeSectoriumDevices()
                try service.withReadOnlyObservation { throw EndObservation.fixture }
            }
        }
        source.fails = true
        let completed = DispatchSemaphore(value: 0)
        let next = Task.detached {
            defer { completed.signal() }
            service.withReadOnlyObservation { () -> Void in
                #expect(throws: CountingObservationDeviceSource.Unavailable.self) { try service.observeSectoriumDevices() }
            }
        }
        let released = await Task.detached { observationSignal(completed, seconds: 3) }.value
        #expect(released)
        if released { await next.value }
        #expect(source.calls == 2)
    }

    @Test func oneSlowRefreshHasOneBudgetInsteadOfOneTimeoutPerProbe() {
        let clock = ObservationClock()
        let base = SlowObservationRunner(clock)
        base.cost = 3
        let runner = SectoriumObservationCommandRunner(base, now: { clock.time })
        runner.withObservation {
            #expect(runner.run("/usr/sbin/diskutil", ["list", "-plist"], cwd: cwd).succeeded)
            #expect(runner.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"], cwd: cwd).succeeded)
            let exhausted = runner.run("/usr/bin/hdiutil", ["info", "-plist"], cwd: cwd)
            #expect(!exhausted.succeeded && exhausted.detail.contains("deadline exceeded"))
            for index in 0..<40 {
                #expect(!runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/disk\(index)"], cwd: cwd).succeeded)
            }
        }
        #expect(clock.time == 108)
        #expect(base.calls.count == 3)
        #expect(base.allowances == [8, 5, 2])
        // The next observation gets a fresh budget, not the prior timeout.
        runner.withObservation {
            #expect(runner.run("/usr/bin/hdiutil", ["info", "-plist"], cwd: cwd).succeeded)
        }
        #expect(base.calls.count == 4 && base.allowances.last == 8)
    }

    @Test func dependencyDFAndTimedMetadataDoNotRestartTheSameGraph() {
        let clock = ObservationClock()
        let base = SlowObservationRunner(clock)
        let runner = SectoriumObservationCommandRunner(base, now: { clock.time })
        runner.withObservation {
            let first = runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/disk4"], cwd: cwd)
            for _ in 0..<20 {
                _ = runner.run("/bin/df", ["-P", "/synthetic/image.sparsebundle"], cwd: cwd)
                #expect(runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/disk4"], cwd: cwd, timeout: 15) == first)
            }
            base.unavailable = true
            for _ in 0..<20 {
                #expect(!runner.run("/usr/bin/hdiutil", ["info", "-plist"], cwd: cwd).succeeded)
            }
        }
        #expect(base.calls.count == 3)
        #expect(clock.time == 100.75)
        base.unavailable = false
        #expect(runner.run("/usr/bin/hdiutil", ["info", "-plist"], cwd: cwd).succeeded)
        #expect(base.calls.count == 4)
    }

    @Test func foregroundDeadlineCannotBorrowPassiveEvidenceAndOccupancyIsNeverReused() {
        let clock = ObservationClock()
        let base = SlowObservationRunner(clock)
        let runner = SectoriumObservationCommandRunner(base, now: { clock.time })
        runner.withObservation {
            _ = runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/disk4"], cwd: cwd)
            runner.withFreshDeadline {
                for expected in ["read-2", "read-3"] {
                    #expect(runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/disk4"], cwd: cwd).detail == expected)
                }
            }
            for _ in 0..<2 {
                _ = runner.run("/usr/sbin/lsof", ["-nP", "+f", "--", "/synthetic/mount"], cwd: cwd)
            }
        }
        #expect(base.calls.count == 5)
        _ = runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/disk4"], cwd: cwd)
        #expect(base.calls.count == 6)
    }

    @Test func coherentForegroundObservationIsFreshPerClickAndNeverCrossesMutation() {
        let clock = ObservationClock()
        let base = SlowObservationRunner(clock)
        let runner = SectoriumObservationCommandRunner(base, now: { clock.time })
        let arguments = ["info", "-plist", "/dev/disk4"]
        runner.withObservation {
            let passive = runner.run("/usr/sbin/diskutil", arguments, cwd: cwd)
            #expect(passive.detail == "read-1")
            runner.withFreshObservation {
                let foreground = runner.run("/usr/sbin/diskutil", arguments, cwd: cwd)
                #expect(foreground.detail == "read-2")
                #expect(runner.run("/usr/sbin/diskutil", arguments, cwd: cwd) == foreground)
                for expected in ["read-3", "read-4"] {
                    #expect(runner.run("/usr/sbin/lsof", ["-nP", "+f", "--", "/synthetic/mount"], cwd: cwd).detail == expected)
                }
                #expect(!runner.run("/usr/sbin/diskutil", ["eject", "/dev/disk4"], cwd: cwd, timeout: 30).succeeded)
            }
            // A second click must see newly unavailable metadata, even while
            // the outer passive observation still owns its earlier snapshot.
            base.unavailable = true
            runner.withFreshObservation {
                let changed = runner.run("/usr/sbin/diskutil", arguments, cwd: cwd)
                #expect(!changed.succeeded && changed.detail == "read-5")
                #expect(runner.run("/usr/sbin/diskutil", arguments, cwd: cwd) == changed)
            }
            #expect(runner.run("/usr/sbin/diskutil", arguments, cwd: cwd) == passive)
        }
        #expect(base.calls.count == 5)
        base.unavailable = false
        // This is only the recording fixture's mutation, never a native action.
        #expect(runner.run("/usr/sbin/diskutil", ["eject", "/dev/disk4"], cwd: cwd, timeout: 30).succeeded)
        runner.withFreshObservation {
            #expect(runner.run("/usr/sbin/diskutil", arguments, cwd: cwd).detail == "read-7")
        }
        #expect(base.calls.count == 7)
    }

    @Test func repeatedForegroundDependencyReadsFitTheUnchangedAggregateBudget() {
        let clock = ObservationClock()
        let base = SlowObservationRunner(clock)
        let runner = SectoriumObservationCommandRunner(base, now: { clock.time })
        for round in 1...2 {
            runner.withFreshObservation {
                for _ in 0..<2 {
                    for location in 0..<11 {
                        #expect(runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/disk0"], cwd: cwd).succeeded)
                        #expect(runner.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"], cwd: cwd).succeeded)
                        #expect(runner.run("/usr/bin/hdiutil", ["info", "-plist"], cwd: cwd).succeeded)
                        #expect(runner.run("/bin/df", ["-P", "/synthetic/dependency-\(location)"], cwd: cwd).succeeded)
                    }
                }
            }
            // 88 requested reads become 14 native-fixture calls, 3.5 seconds
            // on the deterministic clock. Every new click repeats those 14.
            #expect(base.calls.count == round * 14)
            #expect(clock.time == 100 + Double(round) * 3.5)
            #expect(base.allowances[(round - 1) * 14] == 8)
        }
    }

    @Test func readOnlyScopeRejectsMutationAndDoesNotChangeOutsideActionContract() {
        let clock = ObservationClock()
        let base = SlowObservationRunner(clock)
        let runner = SectoriumObservationCommandRunner(base, now: { clock.time })
        runner.withObservation {
            #expect(!runner.run("/usr/sbin/diskutil", ["eject", "/dev/disk4"], cwd: cwd).succeeded)
            #expect(!runner.run("/usr/sbin/diskutil", ["unmount", "/dev/disk4s1"], cwd: cwd, timeout: 30).succeeded)
            #expect(!runner.run("/usr/bin/hdiutil", ["attach", "/synthetic/image"], cwd: cwd, standardInput: Data([1])).succeeded)
            #expect(!runner.run("/usr/sbin/diskutil", ["image", "info", "/synthetic/image"], cwd: cwd).succeeded)
        }
        #expect(base.calls.isEmpty)
        #expect(runner.run("/usr/sbin/diskutil", ["eject", "/dev/disk4"], cwd: cwd, timeout: 30).succeeded)
        #expect(base.calls.count == 1 && base.allowances == [30])
    }

    @Test func namedOccupancyAndParentIdentityAreBoundedWithoutReadingFileNames() {
        let clock = ObservationClock()
        let base = SlowObservationRunner(clock)
        let runner = SectoriumObservationCommandRunner(base, now: { clock.time })
        runner.withFreshObservation {
            for _ in 0..<2 {
                #expect(runner.run("/usr/sbin/lsof", ["-nP", "-Fpcf", "+f", "--", "/synthetic/dev"], cwd: cwd).succeeded)
            }
            #expect(runner.run("/bin/ps", ["-p", "123", "-o", "ppid="], cwd: cwd, timeout: 2).succeeded)
            #expect(!runner.run("/usr/sbin/lsof", ["-nP", "-Fpcfn", "+f", "--", "/synthetic/dev"], cwd: cwd).succeeded)
            #expect(!runner.run("/bin/ps", ["-p", "123", "-o", "command="], cwd: cwd).succeeded)
            #expect(!runner.run("/bin/ps", ["-p", "-1", "-o", "ppid="], cwd: cwd).succeeded)
            #expect(!runner.run("/bin/kill", ["123"], cwd: cwd).succeeded)
        }
        #expect(base.calls.count == 3)
        #expect(base.allowances == [8, 7.75, 2])
    }

    @Test func serviceInventoryIsOneObservationIncludingFailureAndProvidedReadinessDoesNotProbe() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-observation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root.resolvingSymlinksInPath())
        let clock = ObservationClock()
        let base = SlowObservationRunner(clock)
        let source = CountingObservationDeviceSource()
        let service = HESectoriumService(paths: paths,
            installer: HESectoriumInstaller(paths: paths, home: paths.root.appendingPathComponent("home")),
            runner: base, sectoriumDeviceObserver: source)
        try service.withReadOnlyObservation { () throws -> Void in
            let first = try service.observeSectoriumDevices()
            let repeated = try service.observeSectoriumDevices()
            #expect(first.isEmpty)
            #expect(repeated.isEmpty)
            #expect(service.refreshStatus(observedReadiness: .noDevelopmentDisk).readiness
                == .notReady("no verified development volume selected"))
        }
        #expect(source.calls == 1 && base.calls.isEmpty)
        source.fails = true
        service.withReadOnlyObservation {
            #expect(throws: CountingObservationDeviceSource.Unavailable.self) { try service.observeSectoriumDevices() }
            #expect(throws: CountingObservationDeviceSource.Unavailable.self) { try service.observeSectoriumDevices() }
        }
        #expect(source.calls == 2)
        source.fails = false
        #expect(try service.observeSectoriumDevices().isEmpty)
        #expect(source.calls == 3)
    }

    @Test func registryObservationDistinguishesMissingEmptyInvalidAndDisconnectedProfiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-registry-observation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root.resolvingSymlinksInPath())
        let base = SlowObservationRunner(ObservationClock())
        let observer = CountingObservationDeviceSource()
        let service = HESectoriumService(paths: paths,
            installer: HESectoriumInstaller(paths: paths, home: paths.root.appendingPathComponent("home")),
            runner: base, sectoriumDeviceObserver: observer)
        #expect(service.sectoriumProfilesObservation() == [])
        try Data("[]".utf8).write(to: paths.sectoriumProfiles)
        #expect(service.sectoriumProfilesObservation() == [])
        try Data("{broken registry".utf8).write(to: paths.sectoriumProfiles)
        #expect(service.sectoriumProfilesObservation() == nil)
        #expect(service.sectoriumProfiles().isEmpty) // compatibility API only
        try FileManager.default.removeItem(at: paths.sectoriumProfiles)
        try FileManager.default.createDirectory(at: paths.sectoriumProfiles, withIntermediateDirectories: false)
        #expect(service.sectoriumProfilesObservation() == nil)
        try FileManager.default.removeItem(at: paths.sectoriumProfiles)
        let backing = paths.root.appendingPathComponent("absent-backing").path
        let saved = SectoriumDevelopmentProfile(name: "Disconnected", deviceID: UUID().uuidString,
            backingVolumeUUID: UUID(), backingMountPoint: backing,
            imagePath: backing + "/Development.sparsebundle", devVolumeName: "Development",
            devMountPoint: backing + "/Development", encrypted: false, caseSensitive: false,
            logicalCapacityBytes: nil)
        let encoded = try JSONEncoder().encode([saved])
        try encoded.write(to: paths.sectoriumProfiles)
        #expect(service.sectoriumProfilesObservation(resolvePaths: false) == [saved])
        #expect(observer.calls == 0 && base.calls.isEmpty)
        service.selectSectoriumDevice(saved.deviceID)
        service.selectSectoriumProfile(saved.id)
        #expect(observer.calls == 0 && base.calls.isEmpty)
        #expect(service.sectoriumProfilesObservation() == [saved])
        #expect(observer.calls == 1) // compatibility path still resolves the saved parent
        #expect(service.sectoriumProfileObservation(profileID: saved.id) == saved)
        #expect(observer.calls == 2)
        #expect(service.sectoriumProfileObservation(profileID: UUID().uuidString) == nil)
        #expect(observer.calls == 2)
        #expect(try Data(contentsOf: paths.sectoriumProfiles) == encoded)
        #expect(base.calls.isEmpty)
    }
}
