import Foundation
import HESectoriumCore

/// Reuses successful metadata only inside one synchronous UI observation. Action
/// execution never enters this scope and therefore always asks the host afresh.
final class SectoriumReadOnlyObservationCache {
    private struct Key: Hashable {
        let executable: String
        let arguments: [String]
        let cwd: String
    }
    private struct Entry {
        let outcome: CommandOutcome
        let observedAt: TimeInterval
    }
    private final class Batch {
        var entries: [Key: Entry] = [:]
    }
    private let threadKey = "AUV.Sectorium.readOnlyObservation." + UUID().uuidString
    private let now: () -> TimeInterval
    private let maximumAge: TimeInterval

    init(maximumAge: TimeInterval = 2, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.maximumAge = maximumAge
        self.now = now
    }

    func withObservation<T>(_ body: () throws -> T) rethrows -> T {
        let dictionary = Thread.current.threadDictionary
        if dictionary[threadKey] is Batch { return try body() }
        dictionary[threadKey] = Batch()
        defer { dictionary.removeObject(forKey: threadKey) }
        return try body()
    }

    func invalidate() {
        (Thread.current.threadDictionary[threadKey] as? Batch)?.entries.removeAll()
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL,
             execute: () -> CommandOutcome) -> CommandOutcome {
        guard let batch = Thread.current.threadDictionary[threadKey] as? Batch else { return execute() }
        guard ProcessCommandRunner.isReadOnlyPropertyList(executable: executable, arguments: arguments) else {
            // Unknown commands, including every mutation, break the observation.
            invalidate()
            defer { invalidate() }
            return execute()
        }
        let key = Key(executable: executable, arguments: arguments, cwd: cwd.path)
        let started = now()
        if let entry = batch.entries[key], started >= entry.observedAt,
           started - entry.observedAt < maximumAge { return entry.outcome }
        batch.entries.removeValue(forKey: key)
        let outcome = execute()
        if outcome.succeeded {
            if batch.entries.count >= 128 { batch.entries.removeAll() }
            batch.entries[key] = Entry(outcome: outcome, observedAt: started)
        }
        return outcome
    }
}
