import Foundation

/// Describes why the single provider-refresh lane was requested.  The value is
/// diagnostic only: every path still uses the same serialized operation.
public enum CodexRefreshTrigger: String, CaseIterable, Sendable {
    case timer
    case providerEvent
    case reconnect
    case wake
    case manual

    fileprivate var priority: Int {
        switch self {
        case .timer: 0
        case .providerEvent: 1
        case .reconnect: 2
        case .wake: 3
        case .manual: 4
        }
    }
}

/// Runtime-only, privacy-safe state for the refresh lane.  It deliberately
/// contains no provider data or account metadata.
struct CodexRefreshCoordinatorDiagnostics: Sendable, Equatable {
    let activeGeneration: UInt64?
    let activeTrigger: CodexRefreshTrigger?
    let highestCoalescedTrigger: CodexRefreshTrigger?
    let coalescedRequestCount: Int
    let completedGeneration: UInt64
    let consecutiveOverloads: Int
    let isBackoffActive: Bool
}

/// One serial lane for provider usage reads.
///
/// A caller joining an active read receives that exact result rather than
/// starting another account/rate-limit/usage sequence.  Explicit cancellation
/// invalidates the active generation, so a late completion cannot clear or
/// overwrite a later generation.  An overload records bounded backoff for the
/// next request; it never creates an automatic retry loop.
actor CodexRefreshCoordinator<Value: Sendable> {
    typealias Operation = @Sendable () async throws -> Value
    typealias Now = @Sendable () -> Date
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private struct ActiveRefresh {
        let generation: UInt64
        let trigger: CodexRefreshTrigger
        let task: Task<Value, Error>
    }

    private let initialBackoff: TimeInterval
    private let maximumBackoff: TimeInterval
    private let now: Now
    private let sleeper: Sleeper
    private let onRequestCoalesced: @Sendable () -> Void

    private var active: ActiveRefresh?
    private var nextGeneration: UInt64 = 0
    private var completedGeneration: UInt64 = 0
    private var highestCoalescedTrigger: CodexRefreshTrigger?
    private var coalescedRequestCount = 0
    private var consecutiveOverloads = 0
    private var retryNotBefore: Date?

    init(
        initialBackoff: TimeInterval = 30,
        maximumBackoff: TimeInterval = 300,
        now: @escaping Now = { Date() },
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(for: .seconds(max(0, seconds)))
        },
        onRequestCoalesced: @escaping @Sendable () -> Void = {}
    ) {
        self.initialBackoff = max(0, initialBackoff)
        self.maximumBackoff = max(initialBackoff, maximumBackoff)
        self.now = now
        self.sleeper = sleeper
        self.onRequestCoalesced = onRequestCoalesced
    }

    func refresh(
        trigger: CodexRefreshTrigger,
        operation: @escaping Operation
    ) async throws -> Value {
        if let active {
            coalescedRequestCount += 1
            if trigger.priority > (highestCoalescedTrigger ?? active.trigger).priority {
                highestCoalescedTrigger = trigger
            }
            onRequestCoalesced()
            return try await awaitResult(of: active)
        }

        nextGeneration &+= 1
        let generation = nextGeneration
        let backoffDelay = delayBeforeNextRefresh()
        let sleeper = self.sleeper
        let task = Task<Value, Error> {
            if backoffDelay > 0 {
                try await sleeper(backoffDelay)
            }
            try Task.checkCancellation()
            return try await operation()
        }
        let started = ActiveRefresh(generation: generation, trigger: trigger, task: task)
        active = started
        highestCoalescedTrigger = trigger
        coalescedRequestCount = 0
        return try await awaitResult(of: started)
    }

    /// Cancels and invalidates the current generation.  The underlying task is
    /// cooperative; a task that ignores cancellation is still unable to
    /// modify coordinator state after this call.
    func cancelOutstandingRefresh() {
        guard let active else { return }
        self.active = nil
        highestCoalescedTrigger = nil
        coalescedRequestCount = 0
        active.task.cancel()
    }

    func diagnostics() async -> CodexRefreshCoordinatorDiagnostics {
        let now = now()
        return CodexRefreshCoordinatorDiagnostics(
            activeGeneration: active?.generation,
            activeTrigger: active?.trigger,
            highestCoalescedTrigger: highestCoalescedTrigger,
            coalescedRequestCount: coalescedRequestCount,
            completedGeneration: completedGeneration,
            consecutiveOverloads: consecutiveOverloads,
            isBackoffActive: (retryNotBefore?.timeIntervalSince(now) ?? 0) > 0
        )
    }

    private func awaitResult(of refresh: ActiveRefresh) async throws -> Value {
        do {
            let value = try await refresh.task.value
            completeSuccess(generation: refresh.generation)
            return value
        } catch {
            completeFailure(generation: refresh.generation, error: error)
            throw error
        }
    }

    private func completeSuccess(generation: UInt64) {
        guard active?.generation == generation else { return }
        completedGeneration = generation
        active = nil
        highestCoalescedTrigger = nil
        coalescedRequestCount = 0
        consecutiveOverloads = 0
        retryNotBefore = nil
    }

    private func completeFailure(generation: UInt64, error: Error) {
        guard active?.generation == generation else { return }
        completedGeneration = generation
        active = nil
        highestCoalescedTrigger = nil
        coalescedRequestCount = 0
        if isOverload(error) {
            consecutiveOverloads += 1
            let exponent = max(0, consecutiveOverloads - 1)
            let delay = min(maximumBackoff, initialBackoff * pow(2, Double(exponent)))
            retryNotBefore = now().addingTimeInterval(delay)
        } else {
            retryNotBefore = nil
        }
    }

    private func delayBeforeNextRefresh() -> TimeInterval {
        guard let retryNotBefore else { return 0 }
        return min(maximumBackoff, max(0, retryNotBefore.timeIntervalSince(now())))
    }

    private func isOverload(_ error: Error) -> Bool {
        (error as? CodexUsageClientError)?.failure == .serverOverloaded
    }
}
