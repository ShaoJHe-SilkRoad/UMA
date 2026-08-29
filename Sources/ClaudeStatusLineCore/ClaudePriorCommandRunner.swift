import Darwin
import Foundation

public enum ClaudePriorCommandResult: Sendable, Equatable {
    case notConfigured
    case skippedRecursiveInvocation
    case exited(Int32)
}

/// The single compatibility bridge for an existing Human status-line command.
/// Input is streamed directly to the original command and output is inherited
/// by Claude Code. Nothing is captured, logged, cached, or sent to UMA.
public struct ClaudePriorCommandRunner: Sendable {
    public static let recursionEnvironmentKey = "UMA_CLAUDE_STATUS_RELAY_ACTIVE"

    public init() {}

    public func run(
        command: String?,
        rawInput: Data,
        recursionMarkerPresent: Bool = getenv(Self.recursionEnvironmentKey) != nil
    ) throws -> ClaudePriorCommandResult {
        guard let command, !command.isEmpty else { return .notConfigured }
        guard !recursionMarkerPresent else {
            return .skippedRecursiveInvocation
        }
        let lower = command.lowercased()
        guard !lower.contains("claudestatuslinerelay"),
              !lower.contains("uma-claude-smart-relay")
        else { throw ClaudeStatusLineConfigurationError.recursivePriorCommand }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "export \(Self.recursionEnvironmentKey)=1\n" + command,
        ]
        // Leaving `environment` unset preserves the original command's normal
        // inherited shell environment without enumerating or copying it into
        // UMA-owned state. Only the one recursion marker above is added.
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        input.fileHandleForWriting.write(rawInput)
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        return .exited(process.terminationStatus)
    }
}

public enum ClaudePriorStatusLine {
    public static func command(inFragmentData data: Data?) -> String? {
        guard let data,
              data.count <= ClaudeStatusLineConfigurationManager.maximumStatusLineBackupBytes,
              let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (status["type"] as? String ?? "command") == "command"
        else { return nil }
        return status["command"] as? String
    }
}
