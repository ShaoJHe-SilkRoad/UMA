import Foundation
import AppKit
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

/// Opt-in, read-only host acceptance. Installed management metadata is copied
/// into a temporary root; native commands can only read identity and open-reference metadata.
private final class ActivityProbeRunner: HESectoriumTimedCommandRunning {
    let base = ProcessCommandRunner()
    var commands = 0
    var refused = 0
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        run(executable, arguments, cwd: cwd, timeout: 8)
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        let allowed = ProcessCommandRunner.isReadOnlyPropertyList(executable: executable, arguments: arguments)
            || (executable == "/bin/df" && arguments.count == 2 && arguments[0] == "-P" && arguments[1].hasPrefix("/"))
            || (executable == "/usr/sbin/lsof" && arguments.count == 5
                && Array(arguments.prefix(4)) == ["-nP", "-Fpcf", "+f", "--"] && arguments[4].hasPrefix("/"))
            || (executable == "/bin/ps" && arguments.count == 4 && arguments[0] == "-p"
                && Int32(arguments[1]).map({ $0 > 0 }) == true && Array(arguments.suffix(2)) == ["-o", "ppid="])
        guard allowed else { refused += 1; return .init(exitCode: 127, detail: "Excluded from read-only activity probe") }
        commands += 1
        return base.run(executable, arguments, cwd: cwd, timeout: timeout)
    }
}

@Suite("Opt-in named native occupancy", .serialized)
struct SectoriumNativeActivityProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AUV_SECTORIUM_ACTIVITY_PROBE"] == "1"))
    func installedProfileReportsActualBlockingApplicationsWithoutMutations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-activity-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HESectoriumPaths(root: root.resolvingSymlinksInPath())
        var originals: [URL: Data] = [:]
        for name in ["sectorium-profiles.json", "storage-identity.json", "state.json"] {
            let origin = HESectoriumPaths.user.root.appendingPathComponent(name)
            let data = try Data(contentsOf: origin)
            originals[origin] = data
            try data.write(to: paths.root.appendingPathComponent(name))
        }
        let runner = ActivityProbeRunner()
        let service = HESectoriumService(paths: paths,
            installer: HESectoriumInstaller(paths: paths, home: root.appendingPathComponent("fixture-home")), runner: runner)
        let profiles = try #require(service.sectoriumProfilesObservation(resolvePaths: false))
        let profile = try #require(profiles.first { $0.devVolumeName == "DEV_APFS" })
        for wholeDrive in [false, true] {
            let start = ProcessInfo.processInfo.systemUptime
            let report = wholeDrive ? service.wholeDeviceActivityReport(physicalIdentity: profile.deviceID)
                : service.profileActivityReport(profileID: profile.id)
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            print("NATIVE_ACTIVITY wholeDrive=\(wholeDrive) seconds=\(elapsed) assessment=\(report.assessment) commands=\(runner.commands) refused=\(runner.refused)")
            for process in report.processes {
                print("NATIVE_BLOCKER pid=\(process.processID) command=\(process.command) app=\(process.applicationName ?? "unknown") appPID=\(process.owningApplicationProcessID ?? 0) descriptors=\(process.references.map(\.descriptor))")
                #expect(process.references.allSatisfy { $0.path.isEmpty })
            }
            #expect(!report.processes.isEmpty)
            // Codex helpers may belong to the Codex app or the ChatGPT host.
            // Assert live process attribution rather than a hardcoded brand.
            let codex = try #require(report.processes.first { $0.command == "codex" })
            let ownerPID = try #require(codex.owningApplicationProcessID)
            let owner = try #require(NSRunningApplication(processIdentifier: ownerPID))
            #expect(codex.bundleIdentifier == owner.bundleIdentifier)
            #expect(codex.applicationName == owner.localizedName)
            #expect(codex.applicationName?.isEmpty == false)
            #expect(runner.refused == 0)
            #expect(elapsed < 10)
        }
        for (origin, bytes) in originals { #expect(try Data(contentsOf: origin) == bytes) }
    }
}
