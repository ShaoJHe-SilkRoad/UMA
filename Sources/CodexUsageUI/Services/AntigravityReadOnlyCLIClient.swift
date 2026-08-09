import CryptoKit
import Darwin
import Foundation

struct AntigravityCLIInvocation: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectoryURL: URL
    let environment: [String: String]
    let timeout: TimeInterval
    let hardTimeout: TimeInterval
    let stdoutLimit: Int
    let stderrLimit: Int
}

struct AntigravityCLIProcessResult: Equatable, Sendable {
    let stdout: Data
    let stderr: Data
    let terminationStatus: Int32
}

struct AntigravityExecutableIdentity: Equatable, Sendable {
    let canonicalURL: URL
    let sha256: String
    let architecture: String
    let ownerUID: uid_t
    let mode: mode_t
}

enum AntigravityCLIClientError: Error, Equatable, Sendable {
    case notInstalled
    case untrustedExecutable
    case unsupportedVersion
    case loginRequired
    case timedOut
    case cancelled
    case outputTooLarge
    case processExited
    case malformedOutput
    case unsupportedSchema
    case invalidOperationalEnvelope
    case invalidBucket
    case duplicateBucketIdentity
    case noValidQuota
    case providerUnavailable
}

struct AntigravityCLIClientDependencies: Sendable {
    let inspectExecutable:
        @Sendable (URL) throws -> AntigravityExecutableIdentity
    let makeWorkingDirectory: @Sendable () throws -> URL
    let removeWorkingDirectory: @Sendable (URL) -> Void
    let run:
        @Sendable (AntigravityCLIInvocation) async throws
            -> AntigravityCLIProcessResult
    let now: @Sendable () -> Date
}

struct AntigravityReadOnlyCLIClient: Sendable {
    static let executablePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/agy", isDirectory: false).path
    static let admittedSHA256 =
        "198ff7c3f6d173daa510b0814aa70c6ce14c94035bcd4707a3c0e79fa38a7bc3"
    static let admittedVersion = "1.1.11"
    static let usageArguments = ["--output-format", "json", "-p", "/usage"]
    static let timeout: TimeInterval = 15
    static let hardResourceTimeout: TimeInterval = 20
    static let stdoutLimit = 64 * 1_024
    static let stderrLimit = 16 * 1_024

    private let executableURL: URL
    private let dependencies: AntigravityCLIClientDependencies

    init(
        executableURL: URL = URL(fileURLWithPath: executablePath),
        dependencies: AntigravityCLIClientDependencies = .production()
    ) {
        self.executableURL = executableURL
        self.dependencies = dependencies
    }

    func verifyCapability() throws -> AntigravityExecutableIdentity {
        let identity: AntigravityExecutableIdentity
        do {
            identity = try dependencies.inspectExecutable(executableURL)
        } catch let error as AntigravityCLIClientError {
            throw error
        } catch {
            throw AntigravityCLIClientError.untrustedExecutable
        }
        guard identity.canonicalURL.path == Self.executablePath,
              identity.sha256 == Self.admittedSHA256,
              identity.architecture == "arm64",
              identity.ownerUID == getuid(),
              (identity.mode & 0o100) != 0
        else {
            throw AntigravityCLIClientError.untrustedExecutable
        }
        return identity
    }

    func readCurrentQuota() async throws -> AntigravityQuotaSnapshot {
        _ = try verifyCapability()
        let workingDirectory: URL
        do {
            workingDirectory = try dependencies.makeWorkingDirectory()
        } catch {
            throw AntigravityCLIClientError.providerUnavailable
        }
        defer { dependencies.removeWorkingDirectory(workingDirectory) }

        let home = executableURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().path
        let invocation = AntigravityCLIInvocation(
            executableURL: executableURL,
            arguments: Self.usageArguments,
            workingDirectoryURL: workingDirectory,
            environment: [
                "HOME": home,
                "TMPDIR": workingDirectory.path,
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8",
            ],
            timeout: Self.timeout,
            hardTimeout: Self.hardResourceTimeout,
            stdoutLimit: Self.stdoutLimit,
            stderrLimit: Self.stderrLimit
        )

        let result: AntigravityCLIProcessResult
        do {
            result = try await dependencies.run(invocation)
        } catch let error as AntigravityCLIClientError {
            throw error
        } catch is CancellationError {
            throw AntigravityCLIClientError.cancelled
        } catch {
            throw AntigravityCLIClientError.providerUnavailable
        }

        guard result.terminationStatus == 0 else {
            if Self.looksLikeAuthenticationFailure(result.stderr) {
                throw AntigravityCLIClientError.loginRequired
            }
            throw AntigravityCLIClientError.processExited
        }

        do {
            return try AntigravityQuotaDecoder.decode(
                result.stdout,
                cliVersion: Self.admittedVersion,
                observedAt: dependencies.now()
            )
        } catch let error as AntigravityQuotaDecodingError {
            throw Self.map(error)
        } catch {
            throw AntigravityCLIClientError.malformedOutput
        }
    }

    private static func looksLikeAuthenticationFailure(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(4_096), encoding: .utf8) else {
            return false
        }
        let lowercased = text.lowercased()
        return lowercased.contains("login")
            || lowercased.contains("sign in")
            || lowercased.contains("authentication")
    }

    private static func map(
        _ error: AntigravityQuotaDecodingError
    ) -> AntigravityCLIClientError {
        switch error {
        case .malformedJSON:
            .malformedOutput
        case .unsupportedVersion:
            .unsupportedVersion
        case .unsupportedSchema:
            .unsupportedSchema
        case .invalidOperationalEnvelope:
            .invalidOperationalEnvelope
        case .invalidBucket:
            .invalidBucket
        case .duplicateBucketIdentity:
            .duplicateBucketIdentity
        case .noValidQuota:
            .noValidQuota
        }
    }
}

extension AntigravityCLIClientDependencies {
    static func production() -> Self {
        let runner = FoundationAntigravityProcessRunner()
        return Self(
            inspectExecutable: AntigravityExecutableInspector.inspect,
            makeWorkingDirectory: AntigravityWorkingDirectory.make,
            removeWorkingDirectory: AntigravityWorkingDirectory.remove,
            run: { invocation in
                try await runner.run(invocation)
            },
            now: Date.init
        )
    }
}

private enum AntigravityExecutableInspector {
    static func inspect(_ url: URL) throws -> AntigravityExecutableIdentity {
        guard url.path == AntigravityReadOnlyCLIClient.executablePath else {
            throw AntigravityCLIClientError.untrustedExecutable
        }
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw AntigravityCLIClientError.notInstalled
        }
        guard (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              (info.st_mode & S_IXUSR) != 0
        else {
            throw AntigravityCLIClientError.untrustedExecutable
        }
        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalURL.path == url.standardizedFileURL.path else {
            throw AntigravityCLIClientError.untrustedExecutable
        }
        return AntigravityExecutableIdentity(
            canonicalURL: canonicalURL,
            sha256: try sha256(url),
            architecture: try architecture(url),
            ownerUID: info.st_uid,
            mode: info.st_mode & 0o7777
        )
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func architecture(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 8) ?? Data()
        guard header.count == 8 else {
            throw AntigravityCLIClientError.untrustedExecutable
        }
        let values = [UInt8](header)
        let magic = UInt32(values[0])
            | UInt32(values[1]) << 8
            | UInt32(values[2]) << 16
            | UInt32(values[3]) << 24
        let cpuType = UInt32(values[4])
            | UInt32(values[5]) << 8
            | UInt32(values[6]) << 16
            | UInt32(values[7]) << 24
        guard magic == 0xfeedfacf, cpuType == 0x0100000c else {
            throw AntigravityCLIClientError.untrustedExecutable
        }
        return "arm64"
    }
}

private enum AntigravityWorkingDirectory {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-antigravity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    static func remove(_ url: URL) {
        guard url.lastPathComponent.hasPrefix("uma-antigravity-"),
              url.deletingLastPathComponent().standardizedFileURL
                == FileManager.default.temporaryDirectory.standardizedFileURL
        else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}

actor FoundationAntigravityProcessRunner {
    private var active: AntigravityProcessBox?

    func run(
        _ invocation: AntigravityCLIInvocation
    ) async throws -> AntigravityCLIProcessResult {
        guard active == nil else {
            throw AntigravityCLIClientError.providerUnavailable
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectoryURL
        process.environment = invocation.environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe
        try? stdinPipe.fileHandleForWriting.close()

        let box = AntigravityProcessBox(
            process: process,
            stdout: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading,
            stdoutLimit: invocation.stdoutLimit,
            stderrLimit: invocation.stderrLimit
        )
        active = box
        defer { active = nil }

        return try await withTaskCancellationHandler {
            try await box.execute(
                timeout: invocation.timeout,
                hardTimeout: invocation.hardTimeout
            )
        } onCancel: {
            box.cancel()
        }
    }
}

private final class AntigravityProcessBox: @unchecked Sendable {
    private let process: Process
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let stdoutBuffer: AntigravityBoundedBuffer
    private let stderrBuffer: AntigravityBoundedBuffer
    private let lock = NSLock()
    private var timedOut = false
    private var cancelled = false

    init(
        process: Process,
        stdout: FileHandle,
        stderr: FileHandle,
        stdoutLimit: Int,
        stderrLimit: Int
    ) {
        self.process = process
        self.stdout = stdout
        self.stderr = stderr
        stdoutBuffer = AntigravityBoundedBuffer(limit: stdoutLimit)
        stderrBuffer = AntigravityBoundedBuffer(limit: stderrLimit)
    }

    func execute(
        timeout: TimeInterval,
        hardTimeout: TimeInterval
    ) async throws -> AntigravityCLIProcessResult {
        guard !terminalState().cancelled, !Task.isCancelled else {
            throw AntigravityCLIClientError.cancelled
        }
        stdout.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            if stdoutBuffer.append(handle.availableData) { terminate() }
        }
        stderr.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            if stderrBuffer.append(handle.availableData) { terminate() }
        }

        do {
            try process.run()
        } catch {
            cleanupHandles()
            throw AntigravityCLIClientError.providerUnavailable
        }
        if terminalState().cancelled { terminate() }

        let timeoutTask = Task { [weak self] in
            try await Task.sleep(for: .seconds(timeout))
            self?.timeout()
        }
        let hardTimeoutTask = Task { [weak self] in
            try await Task.sleep(for: .seconds(hardTimeout))
            self?.forceTimeout()
        }
        process.waitUntilExit()
        timeoutTask.cancel()
        hardTimeoutTask.cancel()
        cleanupHandles()

        let state = terminalState()
        if state.cancelled { throw AntigravityCLIClientError.cancelled }
        if state.timedOut { throw AntigravityCLIClientError.timedOut }
        if stdoutBuffer.exceeded || stderrBuffer.exceeded {
            throw AntigravityCLIClientError.outputTooLarge
        }
        return AntigravityCLIProcessResult(
            stdout: stdoutBuffer.data,
            stderr: stderrBuffer.data,
            terminationStatus: process.terminationStatus
        )
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        terminate()
    }

    private func timeout() {
        lock.lock()
        timedOut = true
        lock.unlock()
        terminate()
    }

    private func forceTimeout() {
        lock.lock()
        timedOut = true
        lock.unlock()
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
    }

    private func terminate() {
        if process.isRunning { process.terminate() }
    }

    private func terminalState() -> (timedOut: Bool, cancelled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (timedOut, cancelled)
    }

    private func cleanupHandles() {
        stdout.readabilityHandler = nil
        stderr.readabilityHandler = nil
        stdoutBuffer.appendFinal(try? stdout.readToEnd())
        stderrBuffer.appendFinal(try? stderr.readToEnd())
        try? stdout.close()
        try? stderr.close()
    }
}

private final class AntigravityBoundedBuffer: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var storage = Data()
    private(set) var exceeded = false

    init(limit: Int) { self.limit = limit }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    @discardableResult
    func append(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        let available = max(0, limit - storage.count)
        if data.count > available {
            storage.append(data.prefix(available))
            exceeded = true
        } else {
            storage.append(data)
        }
        return exceeded
    }

    func appendFinal(_ data: Data?) {
        guard let data else { return }
        _ = append(data)
    }
}
