import Foundation
import HESectoriumCore

/// One refresh is one bounded observation, not a sequence of independent
/// 15-second waits. Nothing survives its synchronous, thread-local scope.
final class SectoriumObservationCommandRunner: HESectoriumTimedCommandRunning, HESectoriumSecureCommandRunning {
    private struct Key: Hashable {
        let executable: String
        let arguments: [String]
        let cwd: String
    }
    private final class Batch {
        let started: TimeInterval
        let deadline: TimeInterval
        let reuse: Bool
        var commands: [Key: CommandOutcome] = [:]
        var values: [String: Any] = [:]
        init(started: TimeInterval, duration: TimeInterval, reuse: Bool) {
            self.started = started; deadline = started + duration; self.reuse = reuse
        }
    }
    private let base: HESectoriumCommandRunning
    private let now: () -> TimeInterval
    private let duration: TimeInterval
    private let threadKey = "AUV.Sectorium.observationBatch." + UUID().uuidString

    init(_ base: HESectoriumCommandRunning, duration: TimeInterval = 8,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.base = base; self.duration = duration; self.now = now
    }

    private var batch: Batch? { Thread.current.threadDictionary[threadKey] as? Batch }
    private func remaining(_ batch: Batch) -> TimeInterval {
        let time = now()
        return time >= batch.started ? max(0, batch.deadline - time) : 0
    }

    func withObservation<T>(_ body: () throws -> T) rethrows -> T {
        if batch != nil { return try body() }
        return try withBatch(reuse: true, body)
    }

    /// A button click starts its own coherent metadata snapshot and deadline.
    /// It never inherits the background snapshot or a previous click's results.
    /// Repeated reads within this read-only preflight share the new observation;
    /// occupancy still executes every time, and mutations remain prohibited.
    func withFreshObservation<T>(_ body: () throws -> T) rethrows -> T {
        try withBatch(reuse: true, body)
    }

    /// Strict non-reuse mode for independent before/after host verification and
    /// diagnostic comparisons. Ordinary foreground preflight uses the fresh
    /// coherent observation above to avoid multiplying the same metadata work.
    func withFreshDeadline<T>(_ body: () throws -> T) rethrows -> T {
        try withBatch(reuse: false, body)
    }

    private func withBatch<T>(reuse: Bool, _ body: () throws -> T) rethrows -> T {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[threadKey]
        dictionary[threadKey] = Batch(started: now(), duration: duration, reuse: reuse)
        defer {
            if let previous { dictionary[threadKey] = previous }
            else { dictionary.removeObject(forKey: threadKey) }
        }
        return try body()
    }

    func observationValue<Value>(_ key: String, _ make: () -> Value) -> Value {
        guard let batch, batch.reuse, remaining(batch) > 0 else { return make() }
        if let value = batch.values[key] as? Value { return value }
        let value = make()
        batch.values[key] = value
        return value
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        guard batch != nil else { return base.run(executable, arguments, cwd: cwd) }
        return observed(executable, arguments, cwd: cwd, requestedTimeout: nil)
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        guard timeout.isFinite, timeout > 0 else {
            return .init(exitCode: -1, detail: "command timeout must be finite and positive")
        }
        if batch != nil { return observed(executable, arguments, cwd: cwd, requestedTimeout: timeout) }
        guard let timed = base as? HESectoriumTimedCommandRunning else {
            return .init(exitCode: -1, detail: "bounded command execution is unavailable")
        }
        return timed.run(executable, arguments, cwd: cwd, timeout: timeout)
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL, standardInput: Data) -> CommandOutcome {
        guard batch == nil, let secure = base as? HESectoriumSecureCommandRunning else {
            return .init(exitCode: -1, detail: "secure command execution is unavailable in a read-only observation")
        }
        return secure.run(executable, arguments, cwd: cwd, standardInput: standardInput)
    }

    private func observed(_ executable: String, _ arguments: [String], cwd: URL,
                          requestedTimeout: TimeInterval?) -> CommandOutcome {
        guard let batch, Self.isMetadata(executable, arguments) else {
            return .init(exitCode: -1, detail: "command is not allowed in a read-only observation")
        }
        let allowance = remaining(batch)
        guard allowance > 0 else { return Self.expired }
        let key = Key(executable: executable, arguments: arguments, cwd: cwd.path)
        // Occupancy is a foreground safety check, never reusable evidence.
        let reusable = batch.reuse && executable != "/usr/sbin/lsof"
        if reusable, let outcome = batch.commands[key] { return outcome }
        guard !reusable || batch.commands.count < 512 else { return Self.expired }
        let timeout = min(allowance, requestedTimeout ?? 15)
        let outcome: CommandOutcome
        if let timed = base as? HESectoriumTimedCommandRunning {
            outcome = timed.run(executable, arguments, cwd: cwd, timeout: timeout)
        } else {
            // Non-timed runners are injected fixtures. The production runner
            // always supports the clipped deadline above.
            outcome = base.run(executable, arguments, cwd: cwd)
        }
        guard remaining(batch) > 0 else { return Self.expired }
        if reusable {
            // A failed read stays unknown for this refresh; do not repeat a
            // timeout through every row, document, and dependency traversal.
            batch.commands[key] = outcome
        }
        return outcome
    }

    private static var expired: CommandOutcome {
        .init(exitCode: -1, detail: "read-only observation deadline exceeded; refresh to retry")
    }

    private static func isMetadata(_ executable: String, _ arguments: [String]) -> Bool {
        ProcessCommandRunner.isReadOnlyPropertyList(executable: executable, arguments: arguments)
            || (executable == "/bin/df" && arguments.count == 2 && arguments[0] == "-P" && arguments[1].hasPrefix("/"))
            || (executable == "/usr/bin/hdiutil" && arguments.count == 3 && arguments[0] == "imageinfo"
                && arguments[1].hasPrefix("/") && arguments[2] == "-format")
            || (executable == "/usr/bin/hdiutil" && arguments.count == 2 && arguments[0] == "isencrypted"
                && arguments[1].hasPrefix("/"))
            || (executable == "/usr/sbin/lsof" && arguments.count == 4
                && Array(arguments.prefix(3)) == ["-nP", "+f", "--"] && arguments[3].hasPrefix("/"))
            || (executable == "/usr/sbin/lsof" && arguments.count == 5
                && Array(arguments.prefix(4)) == ["-nP", "-Fpcf", "+f", "--"] && arguments[4].hasPrefix("/"))
            || (executable == "/bin/ps" && arguments.count == 4
                && arguments[0] == "-p" && Int32(arguments[1]).map({ $0 > 0 }) == true
                && Array(arguments.suffix(2)) == ["-o", "ppid="])
    }
}
