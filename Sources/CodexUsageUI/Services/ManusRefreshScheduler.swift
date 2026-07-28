import Foundation

actor ManusRefreshScheduler {
    typealias Refresh = @Sendable () async -> Void
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void
    typealias Now = @Sendable () -> Date

    static let minimumCadence: TimeInterval = 60

    private let cadence: TimeInterval
    private let sleeper: Sleeper
    private let now: Now
    private var refresh: Refresh?
    private var timerTask: Task<Void, Never>?
    private var isEnabled = false
    private var isAuthenticationSuspended = false
    private var generation: UInt64 = 0
    private var lastReadCompletedAt: Date?

    init(
        cadence: TimeInterval = minimumCadence,
        now: @escaping Now = Date.init,
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(for: .seconds(max(0, seconds)))
        }
    ) {
        self.cadence = max(Self.minimumCadence, cadence)
        self.now = now
        self.sleeper = sleeper
    }

    func configure(refresh: @escaping Refresh) {
        self.refresh = refresh
        if isEnabled, !isAuthenticationSuspended {
            scheduleAfterCompletion()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            scheduleAfterCompletion()
        } else {
            cancelTimer()
        }
    }

    func readDidComplete(
        trigger: CodexRefreshTrigger,
        authenticationFailed: Bool
    ) {
        lastReadCompletedAt = now()
        if authenticationFailed {
            isAuthenticationSuspended = true
            cancelTimer()
            return
        }
        guard isEnabled else { return }
        scheduleAfterCompletion()
    }

    func waitUntilReadIsAllowed() async throws {
        guard let lastReadCompletedAt else { return }
        let delay = cadence - now().timeIntervalSince(lastReadCompletedAt)
        if delay > 0 {
            try await sleeper(delay)
        }
    }

    func resumeAfterCredentialChange() {
        isAuthenticationSuspended = false
        if isEnabled {
            scheduleAfterCompletion()
        }
    }

    func cancel() {
        isEnabled = false
        isAuthenticationSuspended = false
        cancelTimer()
    }

    func tearDown() {
        cancel()
        refresh = nil
    }

    func diagnostics() -> (
        enabled: Bool,
        authenticationSuspended: Bool,
        timerCount: Int,
        cadence: TimeInterval
    ) {
        (
            isEnabled,
            isAuthenticationSuspended,
            timerTask == nil ? 0 : 1,
            cadence
        )
    }

    private func scheduleAfterCompletion() {
        cancelTimer()
        guard isEnabled, !isAuthenticationSuspended, refresh != nil else {
            return
        }
        generation &+= 1
        let scheduledGeneration = generation
        let cadence = self.cadence
        let sleeper = self.sleeper
        timerTask = Task { [weak self] in
            do {
                try await sleeper(cadence)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.fire(generation: scheduledGeneration)
        }
    }

    private func fire(generation: UInt64) async {
        guard generation == self.generation,
              isEnabled,
              !isAuthenticationSuspended,
              let refresh else {
            return
        }
        timerTask = nil
        await refresh()
    }

    private func cancelTimer() {
        generation &+= 1
        timerTask?.cancel()
        timerTask = nil
    }
}
