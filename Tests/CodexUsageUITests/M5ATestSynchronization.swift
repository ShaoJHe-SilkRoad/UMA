import Foundation
import Combine
import Testing
@testable import CodexUsageUI

/// A callback handshake with replay. Cancellation terminates the wait and
/// removes its continuation; no scheduler turns or elapsed readiness budgets.
final class M5AEventCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var listeners: [UUID: AsyncStream<Int>.Continuation] = [:]

    func signal() {
        lock.lock()
        count += 1
        let value = count
        // Registration/replay and concurrent callback deliveries share the
        // same order; bufferingNewest must never retain an older count.
        for listener in listeners.values { listener.yield(value) }
        lock.unlock()
    }

    func wait(for expected: Int = 1) async {
        let id = UUID()
        let pair = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        register(id, continuation: pair.continuation)
        defer {
            remove(id)
            pair.continuation.finish()
        }
        for await value in pair.stream {
            if value >= expected { return }
        }
        Issue.record("Event observation ended before the expected callback count")
    }

    private func register(_ id: UUID, continuation: AsyncStream<Int>.Continuation) {
        lock.lock()
        listeners[id] = continuation
        continuation.yield(count)
        lock.unlock()
    }

    private func remove(_ id: UUID) {
        lock.lock()
        listeners[id] = nil
        lock.unlock()
    }
}

@MainActor
func m5aWaitForPublished<P: Publisher>(
    _ publisher: P,
    matching predicate: (P.Output) -> Bool
) async where P.Failure == Never, P.Output: Sendable {
    for await value in publisher.values {
        if predicate(value) { return }
    }
    Issue.record("Published-state observation ended before the expected value")
}

func m5aWaitForPublication(
    _ updates: AsyncStream<AgentConnectorRegistryPublication>,
    matching predicate: (AgentConnectorRegistryPublication) -> Bool
) async {
    for await publication in updates {
        if predicate(publication) { return }
    }
    Issue.record("Registry observation ended before the expected publication")
}
