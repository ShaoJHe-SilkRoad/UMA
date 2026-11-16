import Foundation
import Testing
@testable import HESectoriumRuntime

@Suite("Sectorium step timing", .serialized)
struct SectoriumTimingTraceTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sectorium-timing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A traced action records its commands, marks and result; other commands are not recorded")
    func recordsCommandsMarksAndResult() throws {
        let logs = try directory(); defer { try? FileManager.default.removeItem(at: logs) }
        let trace = SectoriumTimingTrace(); trace.configure(logDirectory: logs)
        let token = trace.startCommand()
        #expect(token == nil) // nothing traced yet
        trace.begin("Load DEV_APFS")
        let started = trace.startCommand()
        trace.finishCommand(started, executable: "/usr/bin/hdiutil",
                            arguments: ["attach", "-nomount", "-nobrowse", "/Volumes/X/a.sparsebundle"], exitCode: 0)
        trace.mark("load: attach and mount returned")
        let failed = trace.startCommand()
        trace.finishCommand(failed, executable: "/usr/sbin/diskutil", arguments: ["mount", "disk9s1"], exitCode: 1)
        trace.end("shown: completed")
        trace.flush()
        let text = try String(contentsOf: logs.appendingPathComponent("sectorium-timing.log"), encoding: .utf8)
        #expect(text.contains("## Load DEV_APFS"))
        #expect(text.contains("hdiutil attach -nomount -nobrowse /Volumes/X/a.sparsebundle"))
        #expect(text.contains("· load: attach and mount returned"))
        #expect(text.contains("diskutil mount disk9s1  exit 1"))
        #expect(text.contains("= shown: completed"))
        #expect(text.contains("2 commands"))
    }

    @Test("A new action writes an unfinished one first")
    func supersededTraceIsWritten() throws {
        let logs = try directory(); defer { try? FileManager.default.removeItem(at: logs) }
        let trace = SectoriumTimingTrace(); trace.configure(logDirectory: logs)
        trace.begin("Unload DEV_APFS")
        trace.begin("Load DEV_APFS")
        trace.flush()
        let text = try String(contentsOf: logs.appendingPathComponent("sectorium-timing.log"), encoding: .utf8)
        #expect(text.contains("## Unload DEV_APFS"))
        #expect(text.contains("not finished: superseded by Load DEV_APFS"))
        #expect(text.contains("## Load DEV_APFS"))
    }

    @Test("The command runner reports real process runs to the shared trace")
    func runnerIsTraced() throws {
        let logs = try directory(); defer { try? FileManager.default.removeItem(at: logs) }
        let shared = SectoriumTimingTrace.shared
        shared.configure(logDirectory: logs)
        shared.begin("Runner check")
        _ = ProcessCommandRunner(hostCache: nil).run("/usr/bin/true", [], cwd: logs, timeout: 5)
        shared.flush()
        let text = try String(contentsOf: logs.appendingPathComponent("sectorium-timing.log"), encoding: .utf8)
        #expect(text.contains("## Runner check"))
        #expect(text.contains("true"))
        #expect(text.contains(" commands, "))
    }
}
