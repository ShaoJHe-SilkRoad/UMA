import Foundation

struct WorkBuddyAccountSyncSchedulerDiagnostics: Sendable, Equatable {
    let timerCount: Int
    let scheduledReadCount: Int
    let nextRefreshAt: Date?
}

/// One WorkBuddy-only monotonic scheduling lane. It never performs a read on
/// its own: the session controller supplies the single source-owned callback.
@MainActor
final class WorkBuddyAccountSyncScheduler {
    static let interval = Duration.seconds(60)

    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias Now = @Sendable () -> Date

    private let interval: Duration
    private let sleeper: Sleeper
    private let now: Now
    private var enabled = false
    private var eligible = false
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var onFire: (@MainActor @Sendable () async -> Void)?
    private(set) var scheduledReadCount = 0
    private(set) var nextRefreshAt: Date?

    init(
        interval: Duration = WorkBuddyAccountSyncScheduler.interval,
        sleeper: @escaping Sleeper = { duration in
            try await Task.sleep(for: duration)
        },
        now: @escaping Now = { Date() }
    ) {
        self.interval = interval
        self.sleeper = sleeper
        self.now = now
    }

    func configure(
        onFire: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.onFire = onFire
        reconcile()
    }

    func update(enabled: Bool, eligible: Bool) {
        self.enabled = enabled
        self.eligible = eligible
        reconcile()
    }

    func readWillStart() {
        invalidateTimer()
    }

    func readDidFinish() {
        scheduleIfNeeded()
    }

    func cancel() {
        enabled = false
        eligible = false
        onFire = nil
        invalidateTimer()
    }

    func diagnostics() -> WorkBuddyAccountSyncSchedulerDiagnostics {
        WorkBuddyAccountSyncSchedulerDiagnostics(
            timerCount: task == nil ? 0 : 1,
            scheduledReadCount: scheduledReadCount,
            nextRefreshAt: nextRefreshAt
        )
    }

    private func reconcile() {
        guard enabled, eligible, onFire != nil else {
            invalidateTimer()
            return
        }
        scheduleIfNeeded()
    }

    private func scheduleIfNeeded() {
        guard enabled, eligible, onFire != nil, task == nil else { return }
        generation &+= 1
        let scheduledGeneration = generation
        let sleeper = self.sleeper
        let interval = self.interval
        nextRefreshAt = now().addingTimeInterval(interval.timeInterval)
        task = Task { @MainActor [weak self] in
            do {
                try await sleeper(interval)
            } catch {
                return
            }
            guard let self,
                  generation == scheduledGeneration,
                  enabled,
                  eligible,
                  let onFire
            else {
                return
            }
            task = nil
            nextRefreshAt = nil
            scheduledReadCount += 1
            await onFire()
        }
    }

    private func invalidateTimer() {
        generation &+= 1
        task?.cancel()
        task = nil
        nextRefreshAt = nil
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
