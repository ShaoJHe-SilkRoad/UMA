import Foundation

public enum WorkBuddyManualSourceLifecycle: String, Equatable, Sendable {
    case disabled
    case unconfigured
    case manualConfirmed
    case invalidSavedData
}

struct WorkBuddyManualSourceState: Equatable, Sendable {
    let lifecycle: WorkBuddyManualSourceLifecycle
    let enabled: Bool
    let observation: WorkBuddyManualObservation?
    let changedAt: Date

    static let initial = WorkBuddyManualSourceState(
        lifecycle: .unconfigured,
        enabled: false,
        observation: nil,
        changedAt: .distantPast
    )
}

actor ManualWorkBuddyAvailabilitySource {
    private let store: WorkBuddyManualAvailabilityStore
    private let now: @Sendable () -> Date
    private var state = WorkBuddyManualSourceState.initial
    private var didLoad = false
    private var continuations: [
        UUID: AsyncStream<WorkBuddyManualSourceState>.Continuation
    ] = [:]
    private(set) var publicationCount = 0

    init(
        store: WorkBuddyManualAvailabilityStore = WorkBuddyManualAvailabilityStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    func load() async -> WorkBuddyManualSourceState {
        guard !didLoad else { return state }
        didLoad = true
        switch await store.load() {
        case .missing:
            state = .initial
        case let .valid(record):
            state = Self.state(for: record, changedAt: record.observation?.balance.observedAt ?? .distantPast)
        case .invalid:
            state = WorkBuddyManualSourceState(
                lifecycle: .invalidSavedData,
                enabled: false,
                observation: nil,
                changedAt: now()
            )
        }
        publish()
        return state
    }

    func currentState() -> WorkBuddyManualSourceState { state }

    func states() -> AsyncStream<WorkBuddyManualSourceState> {
        let token = UUID()
        return AsyncStream { continuation in
            continuations[token] = continuation
            continuation.yield(state)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(token) }
            }
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) async throws -> Bool {
        _ = await load()
        guard state.enabled != enabled else { return false }
        let record = WorkBuddyManualPersistenceRecord(
            enabled: enabled,
            observation: state.observation
        )
        _ = try await store.save(record)
        state = Self.state(for: record, changedAt: now())
        publish()
        return true
    }

    @discardableResult
    func save(_ observation: WorkBuddyManualObservation) async throws -> Bool {
        _ = await load()
        if let existing = state.observation, Self.sameValues(existing, observation), state.enabled {
            // A value-identical Save must not advance confirmation time or
            // publish again, but it still repairs a missing/corrupt persistence
            // copy so the primary/recovery pair cannot silently degrade.
            _ = try await store.save(
                WorkBuddyManualPersistenceRecord(
                    enabled: true,
                    observation: existing
                )
            )
            return false
        }
        let record = WorkBuddyManualPersistenceRecord(enabled: true, observation: observation)
        _ = try await store.save(record)
        state = Self.state(for: record, changedAt: observation.balance.observedAt)
        publish()
        return true
    }

    @discardableResult
    func confirmUnchanged(at date: Date? = nil) async throws -> Bool {
        _ = await load()
        guard state.enabled, let observation = state.observation else {
            throw WorkBuddyManualValidationError.noConfirmedValue
        }
        let confirmed = try observation.confirming(at: date ?? now())
        let record = WorkBuddyManualPersistenceRecord(enabled: true, observation: confirmed)
        _ = try await store.save(record)
        state = Self.state(for: record, changedAt: confirmed.balance.observedAt)
        publish()
        return true
    }

    @discardableResult
    func clear() async throws -> Bool {
        _ = await load()
        let removed = try await store.clear()
        guard removed
                || state.lifecycle != .unconfigured
                || state.enabled
                || state.observation != nil
        else {
            return false
        }
        let next = WorkBuddyManualSourceState(
            lifecycle: .unconfigured,
            enabled: false,
            observation: nil,
            changedAt: now()
        )
        state = next
        publish()
        return true
    }

    private static func state(
        for record: WorkBuddyManualPersistenceRecord,
        changedAt: Date
    ) -> WorkBuddyManualSourceState {
        WorkBuddyManualSourceState(
            lifecycle: record.enabled
                ? (record.observation == nil ? .unconfigured : .manualConfirmed)
                : .disabled,
            enabled: record.enabled,
            observation: record.observation,
            changedAt: changedAt
        )
    }

    nonisolated static func sameValues(
        _ lhs: WorkBuddyManualObservation,
        _ rhs: WorkBuddyManualObservation
    ) -> Bool {
        lhs.scope == rhs.scope
            && lhs.tier == rhs.tier
            && lhs.resolvedEntryMode == rhs.resolvedEntryMode
            && lhs.balance.remaining == rhs.balance.remaining
            && lhs.balance.used == rhs.balance.used
            && lhs.balance.total == rhs.balance.total
            && lhs.balance.unit == rhs.balance.unit
            && lhs.balance.scope == rhs.balance.scope
            && lhs.balance.planTier == rhs.balance.planTier
            && lhs.balance.nextExpiryAt == rhs.balance.nextExpiryAt
    }

    private func publish() {
        publicationCount += 1
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    private func removeContinuation(_ token: UUID) {
        continuations[token] = nil
    }
}
