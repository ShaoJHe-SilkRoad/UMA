import ClaudeStatusLineCore
import Darwin
import Foundation

@main
enum ClaudeStatusLineRelay {
    static func main() async {
        let rawInput: Data
        do {
            rawInput = try readBoundedStandardInput()
        } catch {
            Foundation.exit(1)
        }

        let packet = try? ClaudeStatusLineProjection.decode(rawInput)
        let socketClient = ClaudeStatusLineSocketClient(
            socketURL: ClaudeStatusLineSocketPaths.socketURL()
        )
        let publication = Task.detached(priority: .utility) {
            guard let packet else { return false }
            return socketClient.send(packet)
        }

        let executable = URL(
            fileURLWithPath: CommandLine.arguments.first ?? ""
        ).standardizedFileURL.path
        let paths = ClaudeStatusLineConfigurationPaths(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            applicationSupportDirectory: FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent(
                    "Application Support",
                    isDirectory: true
                )
        )
        let manager = ClaudeStatusLineConfigurationManager(
            paths: paths,
            relayCommand: shellQuoted(executable)
        )
        let priorCommand: String?
        do {
            priorCommand = try manager.priorCommandFromBackup()
        } catch {
            _ = await publication.value
            Foundation.exit(1)
        }

        do {
            let execution = try await ClaudePriorCommandRunner()
                .runAndPublish(
                    command: priorCommand,
                    rawInput: rawInput,
                    outputSink: { chunk in
                        try writeStandardOutput(chunk)
                    },
                    publication: {
                        await publication.value
                    }
                )
            Foundation.exit(execution.terminationStatus)
        } catch {
            _ = await publication.value
            Foundation.exit(1)
        }
    }

    private static func readBoundedStandardInput() throws -> Data {
        let limit = ClaudeStatusLineProjection.maximumInputBytes
        var data = Data()
        while let chunk = try FileHandle.standardInput.read(
            upToCount: min(8 * 1_024, limit + 1 - data.count)
        ), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else {
                throw ClaudeStatusLineProtocolError.inputTooLarge
            }
        }
        return data
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func writeStandardOutput(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    STDOUT_FILENO,
                    base.advanced(by: offset),
                    bytes.count - offset
                )
                guard written > 0 else {
                    throw ClaudeStatusLineConfigurationError
                        .persistenceUnavailable
                }
                offset += written
            }
        }
    }
}
