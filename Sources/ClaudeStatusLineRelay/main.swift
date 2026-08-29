import ClaudeStatusLineCore
import Foundation

private struct Arguments {
    let stateURL: URL
    let priorStatusLineURL: URL?

    init?(_ values: [String]) {
        var state: URL?
        var prior: URL?
        var index = 1
        while index < values.count {
            switch values[index] {
            case "--state":
                guard index + 1 < values.count else { return nil }
                state = URL(fileURLWithPath: values[index + 1])
            case "--prior-status-line":
                guard index + 1 < values.count else { return nil }
                prior = URL(fileURLWithPath: values[index + 1])
            default:
                return nil
            }
            index += 2
        }
        guard let state else { return nil }
        stateURL = state
        priorStatusLineURL = prior
    }
}

private func boundedStandardInput() -> Data? {
    var result = Data()
    while true {
        let chunk: Data
        do {
            chunk = try FileHandle.standardInput.read(upToCount: 8 * 1_024) ?? Data()
        } catch {
            return nil
        }
        guard !chunk.isEmpty else { return result }
        result.append(chunk)
        guard result.count <= ClaudeStatusLineProjection.maximumInputBytes else {
            return nil
        }
    }
}

guard let arguments = Arguments(CommandLine.arguments) else { exit(0) }

guard let rawInput = boundedStandardInput() else { exit(0) }

// Project first. The broad provider payload exists only in this short-lived
// process and is never written or forwarded into UMA business logic.
if let packet = try? ClaudeStatusLineProjection.decode(rawInput) {
    try? ClaudeStatusLineStateStore(stateURL: arguments.stateURL).write(packet)
}

let priorData = arguments.priorStatusLineURL.flatMap {
    try? Data(contentsOf: $0, options: [.mappedIfSafe])
}
let priorCommand = ClaudePriorStatusLine.command(inFragmentData: priorData)
_ = try? ClaudePriorCommandRunner().run(
    command: priorCommand,
    rawInput: rawInput
)
