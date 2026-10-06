import Foundation
import CryptoKit
import Dispatch
import Darwin
import Testing
import HESectoriumCore
import HESectoriumRuntime

private final class ChildPipeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func drain(_ handle: FileHandle) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(handle.fileDescriptor, bytes.baseAddress, bytes.count)
            }
            if count <= 0 { break }
            lock.lock()
            storage.append(contentsOf: buffer.prefix(count))
            lock.unlock()
        }
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private func candidateIdentity(at packageRoot: URL) throws -> String {
    let fileManager = FileManager.default
    var files = [packageRoot.appendingPathComponent("Package.swift")]
    for directory in ["Sources", "Tests"] {
        let root = packageRoot.appendingPathComponent(directory, isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw NSError(domain: "HESectorium test identity", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not enumerate candidate directory: \(root.path)"])
        }
        for case let fileURL as URL in enumerator {
            if try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files.append(fileURL)
            }
        }
    }

    let sortedFiles = files.sorted {
        String($0.path.dropFirst(packageRoot.path.count + 1)) < String($1.path.dropFirst(packageRoot.path.count + 1))
    }
    var candidateHasher = SHA256()
    for fileURL in sortedFiles {
        let relativePath = String(fileURL.path.dropFirst(packageRoot.path.count + 1))
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue else {
            throw NSError(domain: "HESectorium test identity", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not read candidate file mode: \(relativePath)"])
        }
        let modeToken = String(format: "0o%03o", permissions & 0o777)
        let contentDigest = SHA256.hash(data: try Data(contentsOf: fileURL))
        candidateHasher.update(data: Data(relativePath.utf8))
        candidateHasher.update(data: Data([0]))
        candidateHasher.update(data: Data(modeToken.utf8))
        candidateHasher.update(data: Data([0]))
        candidateHasher.update(data: Data(contentDigest))
    }
    return candidateHasher.finalize().map { String(format: "%02x", Int($0)) }.joined()
}

private func sha256(at url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", Int($0)) }.joined()
}

private func isWithin(_ child: URL, root: URL) -> Bool {
    let resolvedChild = child.standardizedFileURL.resolvingSymlinksInPath().path
    let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
    return resolvedChild.hasPrefix(resolvedRoot + "/")
}

private struct ChildResult {
    let status: Int32?
    let terminationKind: String
    let captureComplete: Bool
    let directChildTerminated: Bool
    let pid: pid_t
    let stdout: String
    let stderr: String
}

private final class CancellationOutcome: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stored: ChildResult?
    private var storedError: Error?

    func finish(_ value: ChildResult) {
        lock.lock(); stored = value; lock.unlock(); done.signal()
    }

    func fail(_ error: Error) {
        lock.lock(); storedError = error; lock.unlock(); done.signal()
    }

    func value() throws -> ChildResult {
        lock.lock(); defer { lock.unlock() }
        if let storedError { throw storedError }
        return try #require(stored)
    }
}

@Test func cliFixtureChildProcessesReportFailuresAndExitStatusTruthfully() throws {
    let sourceFile = URL(fileURLWithPath: #filePath)
    let packageRoot = sourceFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    // A QA runnable copy lives one level below its private run directory.
    // Otherwise the candidate package itself owns the isolated run directory.
    let authorizedRunRoot = packageRoot.lastPathComponent == "runnable"
        ? packageRoot.deletingLastPathComponent() : packageRoot
    let actualCandidateID = try candidateIdentity(at: packageRoot)
    if let expectedCandidateID = ProcessInfo.processInfo.environment["TOSUMA_HES_TEST_CANDIDATE_ID"] {
        try #require(expectedCandidateID == actualCandidateID,
                "The test package bytes must match the candidate identity supplied by the isolated runner.")
    }
    let evidence = packageRoot.appendingPathComponent("outputs/runs/R3-process-recovery-\(UUID().uuidString)", isDirectory: true)
    try #require(isWithin(evidence, root: authorizedRunRoot),
            "Test evidence must remain inside this candidate's private run root.")
    let suppliedHarness = ProcessInfo.processInfo.environment["TOSUMA_HES_TEST_HARNESS_PATH"]
    let suppliedScratch = ProcessInfo.processInfo.environment["TOSUMA_HES_TEST_SCRATCH_PATH"]
    let suppliedReceipt = ProcessInfo.processInfo.environment["TOSUMA_HES_TEST_BUILD_RECEIPT_PATH"]
    let externallyBuiltHarness = suppliedHarness != nil || suppliedScratch != nil || suppliedReceipt != nil
    try #require(!externallyBuiltHarness || (suppliedHarness != nil && suppliedScratch != nil && suppliedReceipt != nil),
            "Externally built fixture harness requires its candidate-bound build receipt and scratch root.")
    let scratch = externallyBuiltHarness
        ? URL(fileURLWithPath: try #require(suppliedScratch), isDirectory: true).standardizedFileURL
        : evidence.appendingPathComponent("swift-scratch", isDirectory: true)

    func runTool(_ name: String, executableURL: URL, arguments: [String], cwd: URL,
                 timeoutSeconds: Int = 600, captureTimeoutSeconds: Int = 3) throws -> ChildResult {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        let started = ISO8601DateFormatter().string(from: Date())
        try process.run()
        let pid = process.processIdentifier
        let stdoutCapture = ChildPipeCapture()
        let stderrCapture = ChildPipeCapture()
        let outputGroup = DispatchGroup()
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutCapture.drain(stdoutPipe.fileHandleForReading)
            outputGroup.leave()
        }
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrCapture.drain(stderrPipe.fileHandleForReading)
            outputGroup.leave()
        }
        let deadline = DispatchTime.now() + .seconds(timeoutSeconds)
        var stopReason: String?
        while exited.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            if Thread.current.isCancelled { stopReason = "interrupted"; break }
            if DispatchTime.now() >= deadline { stopReason = "timeout"; break }
        }
        if stopReason != nil && process.isRunning {
            process.terminate()
            if exited.wait(timeout: .now() + .seconds(3)) == .timedOut && process.isRunning {
                process.interrupt()
                _ = exited.wait(timeout: .now() + .seconds(3))
            }
        }
        let captureComplete = outputGroup.wait(timeout: .now() + .seconds(captureTimeoutSeconds)) == .success
        if !captureComplete {
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
        }
        let terminated = !process.isRunning
        let status: Int32? = stopReason == nil && terminated ? process.terminationStatus : nil
        let terminationKind = terminated
            ? (stopReason ?? (process.terminationReason == .exit ? "exit" : "signal"))
            : "stillRunningAfter\(stopReason ?? "wait")"
        let stdoutData = stdoutCapture.data()
        let stderrData = stderrCapture.data()
        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrData, as: UTF8.self)
        let record: [String: Any] = [
            "argv": [executableURL.path] + arguments,
            "cwd": cwd.path,
            "candidate_id": actualCandidateID,
            "executable_sha256": try sha256(at: executableURL),
            "pid": Int(pid),
            "started_at": started,
            "ended_at": ISO8601DateFormatter().string(from: Date()),
            "exit_code": status as Any? ?? NSNull(),
            "termination_kind": terminationKind,
            "direct_child_terminated": terminated,
            "capture_complete": captureComplete,
            "capture_state": captureComplete ? "complete" : "inheritedPipeOpenOrReadIncomplete",
            "stdout_bytes_captured": stdoutData.count,
            "stderr_bytes_captured": stderrData.count,
            "stdout": stdout,
            "stderr": stderr
        ]
        let encoded = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try FileHandle.standardError.write(contentsOf: encoded + Data([0x0A]))
        return .init(status: status, terminationKind: terminationKind,
                     captureComplete: captureComplete, directChildTerminated: terminated,
                     pid: pid, stdout: stdout, stderr: stderr)
    }

    let executable: URL
    if let suppliedHarness, let suppliedReceipt {
        executable = URL(fileURLWithPath: suppliedHarness).standardizedFileURL
        let receiptFile = URL(fileURLWithPath: suppliedReceipt).standardizedFileURL
        try #require(isWithin(receiptFile, root: authorizedRunRoot),
                "A supplied build receipt must reside inside this candidate's private run root.")
        let receiptData = try Data(contentsOf: receiptFile)
        let decodedReceipt = try JSONSerialization.jsonObject(with: receiptData)
        let receipt = try #require(decodedReceipt as? [String: Any])
        let receiptScratch = URL(fileURLWithPath: try #require(suppliedScratch), isDirectory: true).standardizedFileURL
        let receiptRoot = URL(fileURLWithPath: try #require(receipt["package_root"] as? String), isDirectory: true).standardizedFileURL
        let receiptExecutable = URL(fileURLWithPath: try #require(receipt["harness_path"] as? String)).standardizedFileURL
        try #require(receipt["candidate_id"] as? String == actualCandidateID,
                "Prebuilt harness receipt must bind to this exact candidate source identity.")
        try #require(receipt["build_exit_code"] as? Int == 0)
        try #require(receiptRoot == packageRoot.standardizedFileURL)
        try #require(URL(fileURLWithPath: try #require(receipt["scratch_path"] as? String), isDirectory: true).standardizedFileURL == receiptScratch)
        try #require(receiptExecutable == executable)
        let actualHarnessSHA256 = try sha256(at: executable)
        try #require(receipt["harness_sha256"] as? String == actualHarnessSHA256,
                "Prebuilt harness bytes must match the candidate-bound build receipt.")
        let buildArguments = try #require(receipt["build_argv"] as? [String])
        try #require(buildArguments.contains(packageRoot.standardizedFileURL.path))
        try #require(buildArguments.contains(receiptScratch.path))
        try #require(buildArguments.contains("HESectoriumControlTestHarness"))
        try #require(isWithin(scratch, root: receiptFile.deletingLastPathComponent()) &&
                     isWithin(scratch, root: authorizedRunRoot),
                "Supplied scratch must resolve inside its authorized private run directory.")
        try #require(isWithin(executable, root: scratch),
                "A supplied harness must resolve inside the receipt-bound isolated scratch directory.")
        var scratchIsDirectory: ObjCBool = false
        try #require(FileManager.default.fileExists(atPath: scratch.path, isDirectory: &scratchIsDirectory) &&
                     scratchIsDirectory.boolValue,
                "Externally built harness scratch must already exist as a directory.")
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        // The supplied paths remain read-only; all fixture outputs use this task's run root.
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
    } else {
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
        let build = try runTool("build-harness", executableURL: xcrun,
                                arguments: ["swift", "build", "--package-path", packageRoot.path, "--scratch-path", scratch.path,
                                            "--target", "HESectoriumControlTestHarness", "--disable-sandbox", "--disable-keychain", "--disable-netrc"], cwd: packageRoot)
        try #require(build.status == 0 && build.captureComplete && build.directChildTerminated,
                     "fixture harness build incomplete: \(build.stdout)\n\(build.stderr)")
        let bin = try runTool("resolve-harness-bin", executableURL: xcrun,
                              arguments: ["swift", "build", "--package-path", packageRoot.path, "--scratch-path", scratch.path,
                                          "--show-bin-path", "--disable-sandbox", "--disable-keychain", "--disable-netrc"], cwd: packageRoot)
        try #require(bin.status == 0 && bin.captureComplete && bin.directChildTerminated,
                     "could not fully resolve harness bin path: \(bin.stderr)")
        executable = URL(fileURLWithPath: bin.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            .appendingPathComponent("HESectoriumControlTestHarness")
    }
    try #require(isWithin(executable, root: scratch),
            "Child scenarios must execute the harness built in this test's isolated candidate scratch directory.")
    try #require(FileManager.default.isExecutableFile(atPath: executable.path))

    func run(_ scenario: String, extraArguments: [String] = [], timeoutSeconds: Int = 30,
             captureTimeoutSeconds: Int = 3, requireCompleteCapture: Bool = true) throws -> ChildResult {
        let result = try runTool("child-\(scenario)", executableURL: executable,
                           arguments: [scenario] + extraArguments, cwd: scratch,
                           timeoutSeconds: timeoutSeconds, captureTimeoutSeconds: captureTimeoutSeconds)
        guard result.directChildTerminated && (!requireCompleteCapture || result.captureComplete) else {
            throw NSError(domain: "HESectorium fixture child", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Fixture child or output capture remained incomplete: \(scenario)"])
        }
        return result
    }

    let large = try run("large-output")
    #expect(large.status == 17 && large.terminationKind == "exit")
    #expect(large.stdout.utf8.count == 262_144 && large.stderr.utf8.count == 262_144)
    let normal15 = try run("exit-15")
    let signal15 = try run("signal-15")
    #expect(normal15.status == 15 && normal15.terminationKind == "exit")
    #expect(signal15.status == 15 && signal15.terminationKind == "signal")
    let timedOut = try run("sleep-for-timeout", timeoutSeconds: 1)
    #expect(timedOut.status == nil && timedOut.terminationKind == "timeout" && timedOut.directChildTerminated)
    let pipeMarker = evidence.appendingPathComponent("bounded-descendant-completed.txt")
    let inheritedPipe = try run("hold-pipe-descendant", extraArguments: [pipeMarker.path],
                                captureTimeoutSeconds: 1, requireCompleteCapture: false)
    #expect(inheritedPipe.status == 0 && inheritedPipe.directChildTerminated)
    #expect(!inheritedPipe.captureComplete)
    #expect(inheritedPipe.stdout.contains("parent exited") && inheritedPipe.stdout.contains("descendant opened pipe"))
    let markerDeadline = DispatchTime.now() + .seconds(6)
    while !FileManager.default.fileExists(atPath: pipeMarker.path) && DispatchTime.now() < markerDeadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    #expect(FileManager.default.fileExists(atPath: pipeMarker.path),
            "The deliberately short-lived fixture descendant must finish before the test completes.")

    let expectedFailedActionDiagnostic = "Sectorium: operation did not complete. Keep the drive connected, refresh its identity, and review the operation details before retrying.\n"

    func object(_ result: ChildResult, expectedStatus: Int32, succeeded: Bool,
                expectsFailedActionDiagnostic: Bool = false) throws -> [String: Any] {
        #expect(result.status == expectedStatus)
        if expectsFailedActionDiagnostic {
            #expect(!succeeded)
            #expect(result.stderr == expectedFailedActionDiagnostic)
            #expect(result.stderr.split(whereSeparator: \.isNewline).count == 1)
        } else {
            #expect(result.stderr.isEmpty)
        }
        let data = try #require(result.stdout.data(using: .utf8))
        let value = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((value["succeeded"] as? Bool) == succeeded)
        return value
    }

    let refusedMountChild = try run("refused-mount")
    let refusedMount = try object(refusedMountChild, expectedStatus: 1, succeeded: false, expectsFailedActionDiagnostic: true)
    #expect(refusedMount["failure"] is String)

    let postcheckMountChild = try run("postcheck-mount")
    let postcheckMount = try object(postcheckMountChild, expectedStatus: 1, succeeded: false, expectsFailedActionDiagnostic: true)
    #expect(postcheckMount["failure"] is String)
    let postcheckSteps = try #require(postcheckMount["steps"] as? [[String: Any]])
    #expect(postcheckSteps.contains { ($0["step"] as? String)?.localizedCaseInsensitiveContains("attach") == true && ($0["status"] as? String) == "succeeded" })

    let failedEjectChild = try run("failed-eject")
    let failedEject = try object(failedEjectChild, expectedStatus: 1, succeeded: false, expectsFailedActionDiagnostic: true)
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

    let requestedWorkbenchRoot = evidence.appendingPathComponent("fresh-process-workbench", isDirectory: true)
    try FileManager.default.createDirectory(at: requestedWorkbenchRoot, withIntermediateDirectories: true)
    let workbenchRoot = requestedWorkbenchRoot.resolvingSymlinksInPath()
    let seed = try run("seed-interrupted-start", extraArguments: [workbenchRoot.path])
    #expect(seed.status == 0)
    let recovered = try run("recover-interrupted-start", extraArguments: [workbenchRoot.path])
    #expect(recovered.pid != seed.pid, "Recovery must run in a distinct process from the durable-state seed.")
    #expect(recovered.status == 0)
    #expect(recovered.stderr.isEmpty)
    let recoveredData = try #require(recovered.stdout.data(using: .utf8))
    let recoveredObject = try #require(JSONSerialization.jsonObject(with: recoveredData) as? [String: Any])
    #expect(recoveredObject["succeeded"] as? Bool == false)
    #expect(recoveredObject["pending"] as? String == "start:fixture-start")
    #expect(recoveredObject["phase"] as? String == "mutating:attachImage")
    let recoveryCommands = try #require(recoveredObject["commands"] as? [[String]])
    #expect(!recoveryCommands.contains { $0.first == "/usr/bin/hdiutil" && $0.dropFirst().first == "attach" })
    let backingMount = workbenchRoot.appendingPathComponent("outer", isDirectory: true).path
    let devMount = workbenchRoot.appendingPathComponent("outer/DEV", isDirectory: true).path
    #expect(recoveryCommands.contains(["/usr/sbin/diskutil", "info", "-plist", backingMount]), "Fixture binding: \(String(describing: recoveredObject))")
    #expect(recoveryCommands.contains(["/usr/sbin/diskutil", "info", "-plist", devMount]))
    #expect(recoveryCommands.contains(["/usr/bin/hdiutil", "info", "-plist"]))

    for suffix in ["nil", "known"] {
        let root = evidence.appendingPathComponent("validation-eject-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let seedEject = try run("seed-validation-eject-\(suffix)", extraArguments: [root.path])
        #expect(seedEject.status == 0)
        let resumedEject = try run("recover-validation-eject-\(suffix)", extraArguments: [root.path])
        #expect(resumedEject.pid != seedEject.pid, "Validation recovery must use a fresh process")
        let result = try object(resumedEject, expectedStatus: 0, succeeded: true)
        #expect(result["pending"] is NSNull)
        let commands = try #require(result["commands"] as? [[String]])
        #expect(!commands.contains { $0.contains("attach") || $0.contains("unmount") || $0.contains("eject") })
        if suffix == "nil" { #expect(commands.isEmpty) }
        else {
            let canonicalOuter = evidence.appendingPathComponent("validation-eject-known/outer", isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL.path
            #expect(commands.contains(["/usr/sbin/diskutil", "info", "-plist", canonicalOuter]))
        }
    }

    let ambiguousRoot = evidence.appendingPathComponent("validation-eject-ambiguous", isDirectory: true)
    try FileManager.default.createDirectory(at: ambiguousRoot, withIntermediateDirectories: true)
    let seedAmbiguous = try run("seed-validation-eject-known", extraArguments: [ambiguousRoot.path])
    #expect(seedAmbiguous.status == 0)
    let ambiguous = try run("recover-validation-eject-ambiguous", extraArguments: [ambiguousRoot.path])
    #expect(ambiguous.pid != seedAmbiguous.pid)
    let ambiguousResult = try object(ambiguous, expectedStatus: 0, succeeded: false)
    #expect(ambiguousResult["pending"] as? String == "eject:6A84E2D9-E928-4D4B-BD12-32A604B2925D")
    #expect((ambiguousResult["commands"] as? [[String]])?.isEmpty == true)

    func runR3(_ record: String, scenario: String, root: URL) throws -> ChildResult {
        try runTool(record, executableURL: executable, arguments: ["r3-eject-\(scenario)", root.path], cwd: scratch)
    }
    func json(_ child: ChildResult) throws -> [String: Any] {
        let data = try #require(child.stdout.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    let crashCases = [
        (label: "first-issued-crash", seed: "first-issued", recover: "first-issued"),
        (label: "second-issued-crash", seed: "second-issued", recover: "second-issued")
    ]
    for crashCase in crashCases {
        let root = evidence.appendingPathComponent("r3-\(crashCase.label)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let seed = try runR3("R3-seed-\(crashCase.label)", scenario: "seed-\(crashCase.seed)", root: root)
        #expect(seed.status == 86, "Injected command/receipt crash boundary: \(seed.stdout) \(seed.stderr)")
        let saved = try JSONStateStore(url: root.appendingPathComponent("support/state.json")).load()
        #expect(saved.ejectIntent)
        let encoded = try #require(saved.workbenchTarget)
        let journal = try JSONDecoder().decode(WholeDeviceEjectJournalRecord.self,
            from: try #require(Data(base64Encoded: encoded)))
        #expect(journal.phase == .physicalVolumesUnmountIssued)
        #expect(journal.lastIssuedAction == .physicalVolumesUnmount)
        #expect(journal.lastReceipt == nil)

        let recovered = try runR3("R3-recover-\(crashCase.label)", scenario: "recover-\(crashCase.recover)", root: root)
        #expect(recovered.pid != seed.pid)
        #expect(recovered.status == 0, "\(recovered.stderr)\n\(recovered.stdout)")
        let value = try json(recovered)
        #expect(value["confirmationAvailable"] as? Bool == true, "\(crashCase.label): \(value)")
        #expect(value["succeeded"] as? Bool == true, "\(crashCase.label): \(value)")
        #expect(value["genericResumeSucceeded"] as? Bool == false)
        #expect(value["returnSucceeded"] as? Bool == false)
        #expect(value["durableBeforeEveryMutation"] as? Bool == true)
    }

    let unexpectedAbsentRoot = evidence.appendingPathComponent("r3-second-unexpected-absent", isDirectory: true)
    try FileManager.default.createDirectory(at: unexpectedAbsentRoot, withIntermediateDirectories: true)
    let absentSeed = try runR3("R3-seed-second-unexpected-absent", scenario: "seed-second-unexpected-absent", root: unexpectedAbsentRoot)
    #expect(absentSeed.status == 0, "unexpected-absent seed: \(absentSeed.stderr)\n\(absentSeed.stdout)")
    let absentSaved = try JSONStateStore(url: unexpectedAbsentRoot.appendingPathComponent("support/state.json")).load()
    #expect(absentSaved.ejectIntent)
    let absentEncoded = try #require(absentSaved.workbenchTarget)
    let absentJournal = try JSONDecoder().decode(WholeDeviceEjectJournalRecord.self,
        from: try #require(Data(base64Encoded: absentEncoded)))
    #expect(absentJournal.phase == .interrupted)
    #expect(absentJournal.lastIssuedAction == .physicalVolumesUnmount)
    let firstMemberUUID = "148CC6E1-CB27-4C60-BB27-B61C0A5A4002"
    let secondMemberUUID = "148CC6E1-CB27-4C60-BB27-B61C0A5A4003"
    let normalizedFirstMemberUUID = try #require(UUID(uuidString: firstMemberUUID)).uuidString.lowercased()
    let normalizedSecondMemberUUID = try #require(UUID(uuidString: secondMemberUUID)).uuidString.lowercased()
    let firstMemberIdentity = "unmountPhysicalVolume:\(normalizedFirstMemberUUID)|disk81s1"
    let secondMemberIdentity = "unmountPhysicalVolume:\(normalizedSecondMemberUUID)|disk81s2"
    #expect(absentJournal.completedSteps.contains(firstMemberIdentity))
    #expect(!absentJournal.completedSteps.contains(secondMemberIdentity))
    if case .partial? = absentJournal.lastReceipt {} else { Issue.record("second exact member became unmounted without a durable member completion receipt") }
    let absentRecovery = try runR3("R3-recover-second-unexpected-absent", scenario: "recover-second-unexpected-absent", root: unexpectedAbsentRoot)
    #expect(absentRecovery.pid != absentSeed.pid)
    #expect(absentRecovery.status == 0, "unexpected-absent recovery: \(absentRecovery.stderr)\n\(absentRecovery.stdout)")
    let absentValue = try json(absentRecovery)
    #expect(absentValue["confirmationAvailable"] as? Bool == true, "\(absentValue)")
    #expect(absentValue["succeeded"] as? Bool == true, "\(absentValue)")
    #expect(absentValue["durableBeforeEveryMutation"] as? Bool == true)
    let absentMutations = try #require(absentValue["mutations"] as? [[String: Any]])
    #expect(absentMutations.count == 1, "only the whole-device eject should remain: \(absentMutations)")
    #expect((absentMutations.first?["command"] as? [String])?.contains("eject") == true)

    let managedRoot = evidence.appendingPathComponent("r3-managed-second", isDirectory: true)
    try FileManager.default.createDirectory(at: managedRoot, withIntermediateDirectories: true)
    let managedSeed = try runR3("R3-seed-managed-second", scenario: "seed-managed-second", root: managedRoot)
    #expect(managedSeed.status == 0, "\(managedSeed.stderr)\n\(managedSeed.stdout)")
    let seedValue = try json(managedSeed)
    #expect(seedValue["succeeded"] as? Bool == false)
    #expect(seedValue["intent"] as? Bool == true)
    #expect(seedValue["phase"] as? String == "eject:interrupted")
    let managedRecovery = try runR3("R3-recover-managed-second", scenario: "recover-managed-second", root: managedRoot)
    #expect(managedRecovery.pid != managedSeed.pid)
    #expect(managedRecovery.status == 0, "\(managedRecovery.stderr)\n\(managedRecovery.stdout)")
    let managedValue = try json(managedRecovery)
    #expect(managedValue["confirmationAvailable"] as? Bool == true, "\(managedValue)")
    #expect(managedValue["succeeded"] as? Bool == true, "\(managedValue)")
    #expect(managedValue["durableBeforeEveryMutation"] as? Bool == true)

    for negative in ["busy-again", "postcheck", "new-member", "missing-member", "replacement", "unknown",
                     "no-ack", "stale", "wrong-checkpoint", "held-lock", "eject-present"] {
        let root = evidence.appendingPathComponent("r3-negative-\(negative)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let seed = try runR3("R3-seed-negative-\(negative)", scenario: "seed-managed-second", root: root)
        #expect(seed.status == 0, "negative seed \(negative): \(seed.stderr)")
        let recovered = try runR3("R3-recover-negative-\(negative)",
            scenario: "recover-managed-second-\(negative)", root: root)
        #expect(recovered.pid != seed.pid)
        #expect(recovered.status == 0, "\(negative): \(recovered.stderr)\n\(recovered.stdout)")
        let value = try json(recovered)
        #expect(value["succeeded"] as? Bool == false, "\(negative): \(value)")
        #expect(value["intent"] as? Bool == true, "\(negative): intent must remain durable")
        #expect(value["durableBeforeEveryMutation"] as? Bool == true)
    }

    let repeatRoot = evidence.appendingPathComponent("r3-repeat", isDirectory: true)
    try FileManager.default.createDirectory(at: repeatRoot, withIntermediateDirectories: true)
    let repeatSeed = try runR3("R3-seed-repeat", scenario: "seed-first-issued", root: repeatRoot)
    let repeatRecovery = try runR3("R3-recover-repeat", scenario: "recover-first-issued-repeat", root: repeatRoot)
    #expect(repeatRecovery.pid != repeatSeed.pid)
    #expect(repeatRecovery.status == 0, "\(repeatRecovery.stderr)\n\(repeatRecovery.stdout)")
    let repeatValue = try json(repeatRecovery)
    #expect(repeatValue["succeeded"] as? Bool == true)
    #expect(repeatValue["repeatSucceeded"] as? Bool == false)

    let cancellation = CancellationOutcome()
    let cancellationThread = Thread {
        do { cancellation.finish(try run("sleep-for-timeout", timeoutSeconds: 10)) }
        catch { cancellation.fail(error) }
    }
    cancellationThread.start()
    Thread.sleep(forTimeInterval: 0.25)
    cancellationThread.cancel()
    try #require(cancellation.done.wait(timeout: .now() + .seconds(6)) == .success,
                 "Cancelled fixture child must stop within the bounded test deadline.")
    let interrupted = try cancellation.value()
    #expect(interrupted.status == nil && interrupted.terminationKind == "interrupted")
    #expect(interrupted.directChildTerminated && interrupted.captureComplete)
}
