import Foundation
import Testing

private struct ChildResult {
    let status: Int32
    let stdout: String
    let stderr: String
    let recordPath: URL
}

@Test func cliFixtureChildProcessesReportFailuresAndExitStatusTruthfully() throws {
    let sourceFile = URL(fileURLWithPath: #filePath)
    let packageRoot = sourceFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let scratch = URL(fileURLWithPath: "/private/tmp/hesectorium-cli-subprocess-build", isDirectory: true)
    let evidence = URL(fileURLWithPath: "/private/tmp/hesectorium-cli-subprocess-tests/run-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)

    func runTool(_ name: String, executableURL: URL, arguments: [String], cwd: URL) throws -> ChildResult {
        let stdoutURL = evidence.appendingPathComponent("\(name).stdout.txt")
        let stderrURL = evidence.appendingPathComponent("\(name).stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutFile = try FileHandle(forWritingTo: stdoutURL)
        let stderrFile = try FileHandle(forWritingTo: stderrURL)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardOutput = stdoutFile
        process.standardError = stderrFile
        let started = ISO8601DateFormatter().string(from: Date())
        try process.run()
        process.waitUntilExit()
        let status = process.terminationStatus
        try stdoutFile.close(); try stderrFile.close()
        let stdout = try String(contentsOf: stdoutURL, encoding: .utf8)
        let stderr = try String(contentsOf: stderrURL, encoding: .utf8)
        let record: [String: Any] = [
            "argv": [executableURL.path] + arguments,
            "cwd": cwd.path,
            "started_at": started,
            "ended_at": ISO8601DateFormatter().string(from: Date()),
            "exit_code": status,
            "stdout_path": stdoutURL.path,
            "stderr_path": stderrURL.path
        ]
        let recordPath = evidence.appendingPathComponent("\(name).json")
        let encoded = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        try encoded.write(to: recordPath, options: .atomic)
        return .init(status: status, stdout: stdout, stderr: stderr, recordPath: recordPath)
    }

    let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
    let build = try runTool("build-harness", executableURL: xcrun,
                            arguments: ["swift", "build", "--package-path", packageRoot.path, "--scratch-path", scratch.path,
                                        "--target", "HESectoriumControlTestHarness", "--disable-sandbox", "--disable-keychain", "--disable-netrc"], cwd: packageRoot)
    #expect(build.status == 0, "fixture harness build failed: \(build.stdout)\n\(build.stderr)")

    let bin = try runTool("resolve-harness-bin", executableURL: xcrun,
                          arguments: ["swift", "build", "--package-path", packageRoot.path, "--scratch-path", scratch.path,
                                      "--show-bin-path", "--disable-sandbox", "--disable-keychain", "--disable-netrc"], cwd: packageRoot)
    #expect(bin.status == 0, "could not resolve harness bin path: \(bin.stderr)")
    let executable = URL(fileURLWithPath: bin.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        .appendingPathComponent("HESectoriumControlTestHarness")
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))

    func run(_ scenario: String) throws -> ChildResult {
        return try runTool("child-\(scenario)", executableURL: executable, arguments: [scenario], cwd: scratch)
    }

    func object(_ result: ChildResult, expectedStatus: Int32, succeeded: Bool) throws -> [String: Any] {
        #expect(result.status == expectedStatus)
        #expect(result.stderr.isEmpty)
        let data = try #require(result.stdout.data(using: .utf8))
        let value = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((value["succeeded"] as? Bool) == succeeded)
        return value
    }

    let refusedMountChild = try run("refused-mount")
    let refusedMount = try object(refusedMountChild, expectedStatus: 1, succeeded: false)
    #expect(refusedMount["failure"] is String)

    let postcheckMountChild = try run("postcheck-mount")
    let postcheckMount = try object(postcheckMountChild, expectedStatus: 1, succeeded: false)
    #expect(postcheckMount["failure"] is String)
    let postcheckSteps = try #require(postcheckMount["steps"] as? [[String: Any]])
    #expect(postcheckSteps.contains { ($0["step"] as? String)?.localizedCaseInsensitiveContains("attach") == true && ($0["status"] as? String) == "succeeded" })

    let failedEjectChild = try run("failed-eject")
    let failedEject = try object(failedEjectChild, expectedStatus: 1, succeeded: false)
    #expect(failedEject["failure"] is String)
    let ejectSteps = try #require(failedEject["steps"] as? [[String: Any]])
    #expect(ejectSteps.contains { ($0["status"] as? String) == "failed" })

    let successfulMountChild = try run("successful-mount")
    let successfulMount = try object(successfulMountChild, expectedStatus: 0, succeeded: true)
    #expect(successfulMount["failure"] is NSNull)

    let status = try run("status")
    #expect(status.status == 0)
    #expect(status.stderr.isEmpty)
    let statusData = try #require(status.stdout.data(using: .utf8))
    let statusJSON = try JSONSerialization.jsonObject(with: statusData)
    let statusObject = try #require(statusJSON as? [String: Any])
    #expect(statusObject["readiness"] as? String == "ready")
    #expect(FileManager.default.fileExists(atPath: refusedMountChild.recordPath.path))
    #expect(FileManager.default.fileExists(atPath: postcheckMountChild.recordPath.path))
    #expect(FileManager.default.fileExists(atPath: failedEjectChild.recordPath.path))
    #expect(FileManager.default.fileExists(atPath: successfulMountChild.recordPath.path))
    #expect(FileManager.default.fileExists(atPath: status.recordPath.path))
}
