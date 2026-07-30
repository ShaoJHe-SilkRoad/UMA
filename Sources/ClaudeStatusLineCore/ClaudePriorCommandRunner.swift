import Foundation

public enum ClaudePriorCommandPolicyResult: Equatable, Sendable {
    case safe
    case unsafeLiteralSecret
    case recursive
    case malformed
}

public enum ClaudePriorCommandPolicy {
    public static let maximumCommandBytes = 16 * 1_024
    public static let recursionEnvironmentKey =
        "UMA_CLAUDE_STATUSLINE_RELAY_ACTIVE"

    private static let secretMarkers = [
        "_api_key",
        "_auth_token",
        "oauth_token",
        "secret_access_key",
        "client_secret",
        "password=",
        "password =",
        "token=",
        "token =",
        "x-api-key",
        "--api-key",
        "--token",
        "authorization:",
        "bearer ",
    ]

    public static func classify(
        _ command: String,
        relayExecutableName: String = "ClaudeStatusLineRelay"
    ) -> ClaudePriorCommandPolicyResult {
        guard !command.isEmpty,
              command.utf8.count <= maximumCommandBytes,
              !command.unicodeScalars.contains(where: {
                  $0.value == 0
                      || CharacterSet.controlCharacters.contains($0)
              })
        else {
            return .malformed
        }

        let folded = command.lowercased()
        let relayName = relayExecutableName.lowercased()
        if folded.contains("claudestatuslinerelay")
            || (!relayName.isEmpty && folded.contains(relayName))
        {
            return .recursive
        }
        if secretMarkers.contains(where: folded.contains) {
            return .unsafeLiteralSecret
        }
        return .safe
    }
}

public struct ClaudePriorCommandExecution: Equatable, Sendable {
    public let stdout: Data
    public let terminationStatus: Int32
    public let publicationSucceeded: Bool

    public init(
        stdout: Data,
        terminationStatus: Int32,
        publicationSucceeded: Bool
    ) {
        self.stdout = stdout
        self.terminationStatus = terminationStatus
        self.publicationSucceeded = publicationSucceeded
    }
}

/// Runs a previously configured status-line command without interpolating the
/// provider payload into shell text. The command is supplied to `sh -c` as one
/// argument and the exact raw payload is delivered through a pipe.
public struct ClaudePriorCommandRunner: Sendable {
    public typealias OutputSink = @Sendable (Data) throws -> Void

    public static let maximumInputBytes = 64 * 1_024
    public static let maximumOutputBytes = 256 * 1_024

    public init() {}

    public func runAndPublish(
        command: String?,
        rawInput: Data,
        relayExecutableName: String = "ClaudeStatusLineRelay",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        outputSink: OutputSink? = nil,
        publication: @escaping @Sendable () async -> Bool
    ) async throws -> ClaudePriorCommandExecution {
        guard rawInput.count <= Self.maximumInputBytes else {
            throw ClaudeStatusLineConfigurationError.recordTooLarge
        }

        guard let command else {
            return ClaudePriorCommandExecution(
                stdout: Data(),
                terminationStatus: 0,
                publicationSucceeded: await publication()
            )
        }

        guard environment[
            ClaudePriorCommandPolicy.recursionEnvironmentKey
        ] != "1" else {
            throw ClaudeStatusLineConfigurationError.recursivePriorCommand
        }
        switch ClaudePriorCommandPolicy.classify(
            command,
            relayExecutableName: relayExecutableName
        ) {
        case .safe:
            break
        case .unsafeLiteralSecret:
            throw ClaudeStatusLineConfigurationError.unsafeLiteralSecret
        case .recursive:
            throw ClaudeStatusLineConfigurationError.recursivePriorCommand
        case .malformed:
            throw ClaudeStatusLineConfigurationError.unsupportedFutureSchema
        }

        async let publicationSucceeded = publication()
        let cancellation = ClaudePriorCommandCancellation()
        let child = Task.detached(priority: .utility) {
            try await Self.execute(
                command: command,
                rawInput: rawInput,
                environment: environment,
                outputSink: outputSink,
                cancellation: cancellation
            )
        }
        let processResult: (stdout: Data, terminationStatus: Int32)
        do {
            processResult = try await withTaskCancellationHandler {
                let value = try await child.value
                try Task.checkCancellation()
                return value
            } onCancel: {
                cancellation.cancel()
            }
        } catch {
            _ = await publicationSucceeded
            throw error
        }
        return ClaudePriorCommandExecution(
            stdout: processResult.stdout,
            terminationStatus: processResult.terminationStatus,
            publicationSucceeded: await publicationSucceeded
        )
    }

    private static func execute(
        command: String,
        rawInput: Data,
        environment: [String: String],
        outputSink: OutputSink?,
        cancellation: ClaudePriorCommandCancellation
    ) async throws -> (stdout: Data, terminationStatus: Int32) {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        var childEnvironment = environment
        childEnvironment[
            ClaudePriorCommandPolicy.recursionEnvironmentKey
        ] = "1"
        process.environment = childEnvironment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.standardError

        do {
            try process.run()
        } catch {
            throw ClaudeStatusLineConfigurationError.persistenceUnavailable
        }
        cancellation.install(process)
        defer { cancellation.clear(process) }

        let inputWriter = inputPipe.fileHandleForWriting
        let writeTask = Task.detached(priority: .utility) {
            do {
                try inputWriter.write(contentsOf: rawInput)
                try inputWriter.close()
            } catch {
                try? inputWriter.close()
            }
        }

        var output = Data()
        let outputReader = outputPipe.fileHandleForReading
        do {
            while let chunk = try outputReader.read(upToCount: 8 * 1_024),
                  !chunk.isEmpty {
                if let outputSink {
                    try outputSink(chunk)
                } else {
                    output.append(chunk)
                    guard output.count <= Self.maximumOutputBytes else {
                        process.terminate()
                        process.waitUntilExit()
                        await writeTask.value
                        throw ClaudeStatusLineConfigurationError
                            .recordTooLarge
                    }
                }
                try Task.checkCancellation()
            }
        } catch {
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            await writeTask.value
            throw error
        }
        await writeTask.value
        process.waitUntilExit()
        try Task.checkCancellation()
        return (output, process.terminationStatus)
    }
}

private final class ClaudePriorCommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    func install(_ process: Process) {
        lock.lock()
        if cancellationRequested {
            lock.unlock()
            process.terminate()
            return
        }
        self.process = process
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }
}
