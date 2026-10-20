import Foundation
import Testing
@testable import HESectoriumRuntime
#if canImport(Darwin)
import Darwin
#endif

private final class ConcurrentProcessResults: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = 0
    private var failures: [String] = []
    func record(_ detail: String, matches: Bool) {
        lock.lock(); defer { lock.unlock() }
        completed += 1
        if !matches { failures.append(detail) }
    }
    var snapshot: (count: Int, failures: [String]) {
        lock.lock(); defer { lock.unlock() }; return (completed, failures)
    }
}

/// Inert child processes only: no storage, occupancy, service, or installed-helper
/// command is executed by these regressions. Each delayed fixture also exits itself.
@Suite("Sectorium bounded process runner")
struct SectoriumProcessRunnerStabilityTests {
    private let cwd = FileManager.default.temporaryDirectory

    @Test func automaticDeadlinesAreLimitedToKnownReadOnlyCommands() {
        for command in [
            ["/usr/sbin/diskutil", "list", "-plist"],
            ["/usr/sbin/diskutil", "apfs", "list", "-plist"],
            ["/usr/sbin/diskutil", "info", "-plist", "/dev/disk81"],
            ["/usr/bin/hdiutil", "info", "-plist"],
            ["/usr/bin/hdiutil", "imageinfo", "/synthetic/image", "-format"],
            ["/usr/bin/hdiutil", "isencrypted", "/synthetic/image"],
            ["/bin/df", "-P", "/synthetic/path"],
            ["/usr/sbin/lsof", "-nP", "+f", "--", "/dev/disk81"],
            ["/usr/sbin/lsof", "-nP", "+f", "--", "/synthetic/mounted volume"]
        ] {
            #expect(ProcessCommandRunner.defaultTimeout(executable: command[0], arguments: Array(command.dropFirst())) == 15)
        }
        for command in [
            ["/usr/sbin/diskutil", "eject", "/dev/disk81"],
            ["/usr/bin/hdiutil", "attach", "/synthetic/image"],
            ["/usr/bin/hdiutil", "imageinfo", "-format"],
            ["/usr/bin/hdiutil", "isencrypted", "relative-image"],
            ["/usr/bin/hdiutil", "resize", "-limits", "/synthetic/image"],
            ["/usr/sbin/lsof", "+D", "/synthetic/path"],
            ["/usr/sbin/lsof", "-nP", "+f", "--", "relative-mount"],
            ["/bin/sh", "-c", "exit 0"]
        ] {
            #expect(ProcessCommandRunner.defaultTimeout(executable: command[0], arguments: Array(command.dropFirst())) == nil)
        }
    }

    @Test func developmentVolumeLoadAndUnloadHaveBoundedNativeCommands() {
        #expect(ProcessCommandRunner.defaultTimeout(executable: "/usr/sbin/diskutil",
            arguments: ["image", "attach", "--help"]) == 5)
        #expect(ProcessCommandRunner.defaultTimeout(executable: "/usr/sbin/diskutil",
            arguments: ["image", "attach", "--nobrowse", "--mountPoint", "/synthetic/DEV", "/synthetic/image"]) == 90)
        #expect(ProcessCommandRunner.defaultTimeout(executable: "/usr/sbin/diskutil",
            arguments: ["unmount", "/dev/disk81s1"]) == 30)
        #expect(ProcessCommandRunner.defaultTimeout(executable: "/usr/sbin/diskutil",
            arguments: ["mount", "-mountPoint", "/synthetic/DEV", "/dev/disk31s1"]) == 30)
        #expect(ProcessCommandRunner.defaultTimeout(executable: "/bin/ps",
            arguments: ["-p", "123", "-o", "ppid="]) == 2)
    }

    @Test func commandPipeDescriptorsAreClosedOnUnrelatedExec() {
        #if canImport(Darwin)
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        #expect(ProcessCommandRunner.markCloseOnExec(pipe))
        for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
            let flags = fcntl(handle.fileDescriptor, F_GETFD)
            #expect(flags >= 0 && flags & FD_CLOEXEC != 0)
        }
        #endif
    }

    @Test func repeatedParallelShortOutputCompletesBesideSlowSiblingProcesses() {
        let results = ConcurrentProcessResults()
        let directory = cwd
        // These blocking callers exercise the dispatch pool which r1 also used
        // for readers. Slow siblings additionally expose accidentally inherited
        // pipe writers; no normal short output may be dropped or called timeout.
        DispatchQueue.concurrentPerform(iterations: 10) { worker in
            let runner = ProcessCommandRunner()
            if worker < 2 {
                let outcome = runner.run("/bin/sh", ["-c", "/bin/sleep 3; printf slow"], cwd: directory)
                results.record("slow \(worker): \(outcome)", matches: outcome.succeeded && outcome.detail == "slow")
                return
            }
            for iteration in 0..<6 {
                let token = "\(worker)-\(iteration)"
                let outcome = runner.run("/bin/sh", ["-c", "printf 'out:%s' \"$1\"; printf 'err:%s' \"$1\" >&2", "fixture", token], cwd: directory)
                results.record("short \(token): \(outcome)",
                    matches: outcome.succeeded && outcome.detail == "out:\(token)\nerr:\(token)")
            }
        }
        let observed = results.snapshot
        #expect(observed.count == 50)
        #expect(observed.failures.isEmpty, "\(observed.failures)")
    }

    @Test func invalidTimeoutFailsBeforeLaunchingACommand() {
        let runner = ProcessCommandRunner()
        for timeout: TimeInterval in [0, -1, .infinity, .nan] {
            let result = runner.run("/not/a/fixture/executable", [], cwd: cwd, timeout: timeout)
            #expect(!result.succeeded)
            #expect(result.detail == "command timeout must be finite and positive")
        }
    }

    @Test func timeoutTerminatesAnOrdinaryChildAndRunnerCanBeReused() {
        let runner = ProcessCommandRunner()
        let start = ProcessInfo.processInfo.systemUptime
        let result = runner.run("/bin/sh", ["-c", "exec /bin/sleep 4"], cwd: cwd, timeout: 0.2)
        #expect(!result.succeeded)
        #expect(result.detail.contains("command timed out"))
        #expect(ProcessInfo.processInfo.systemUptime - start < 3.5)
        #expect(runner.run("/bin/sh", ["-c", "printf reusable"], cwd: cwd).detail == "reusable")
    }

    @Test func timeoutRemainsBoundedWhenTheDirectChildIgnoresTermination() {
        let runner = ProcessCommandRunner()
        let start = ProcessInfo.processInfo.systemUptime
        // exec preserves the ignored SIGTERM disposition. The old runner waited
        // until this four-second sleep ended despite its 0.2-second deadline.
        let result = runner.run("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 4"], cwd: cwd, timeout: 0.2)
        #expect(!result.succeeded)
        #expect(result.detail.contains("command timed out"))
        #expect(ProcessInfo.processInfo.systemUptime - start < 3.5)
    }

    @Test func inheritedOutputPipeCannotTurnACompletedChildIntoAnUnboundedWait() {
        let runner = ProcessCommandRunner()
        let start = ProcessInfo.processInfo.systemUptime
        // Only the short-lived background sleep retains the pipes; the direct
        // child exits successfully. Incomplete output must not be called success.
        let result = runner.run("/bin/sh", ["-c", "/bin/sleep 3 & printf complete"], cwd: cwd, timeout: 0.5)
        #expect(!result.succeeded)
        #expect(result.detail == "command output did not close after process exit")
        #expect(ProcessInfo.processInfo.systemUptime - start < 2.5)
    }

    @Test func launchAndSignalFailuresDoNotBecomeSuccessfulResults() {
        let runner = ProcessCommandRunner()
        #expect(!runner.run("/not/a/fixture/executable", [], cwd: cwd).succeeded)
        let signalled = runner.run("/bin/sh", ["-c", "kill -KILL $$"], cwd: cwd, timeout: 1)
        #expect(!signalled.succeeded)
        let complete = runner.run("/bin/sh", ["-c", "printf stdout; printf stderr >&2"], cwd: cwd, timeout: 1)
        #expect(complete.succeeded)
        #expect(complete.detail.contains("stdout"))
        #expect(complete.detail.contains("stderr"))
    }
}
