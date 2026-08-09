import Combine
import Foundation

public enum AntigravitySettingsSafeError: String, Equatable, Sendable {
    case executableMissing
    case authenticationRequired
    case unsupportedVersion
    case unsupportedSchema
    case timedOut
    case unavailable
}

public enum AntigravitySettingsPresentationState: Equatable, Sendable {
    case disabled
    case checking
    case notInstalled
    case openingOfficialSetup
    case loginRequired
    case connected(Date)
    case refreshing(Date?)
    case fresh(Date)
    case cached(Date)
    case stale(Date)
    case failed
}

public enum AntigravitySettingsAction: Equatable, Sendable {
    case checking
    case openingOfficialSetup
    case openingProvider
    case refreshing
    case changingAutoRefresh
    case disabling
}

public struct AntigravitySourceTransparency: Equatable, Sendable {
    public let source = "Official Antigravity CLI · read-only /usage"
    public let authentication = "Provider-managed Antigravity sign-in"
    public let executable = "$HOME/.local/bin/agy"
    public let credentialsAccessed = false
    public let browserDataAccessed = false
    public let rawProviderPayloadStored = false
    public let providerWorkSubmitted = false
    public let normalizedData = "Remaining fraction and scoped reset time only"

    public init() {}
}

public struct AntigravitySettingsObservation: Equatable, Sendable {
    public let state: AntigravitySettingsPresentationState
    public let safeError: AntigravitySettingsSafeError?

    public init(
        state: AntigravitySettingsPresentationState,
        safeError: AntigravitySettingsSafeError? = nil
    ) {
        self.state = state
        self.safeError = safeError
    }
}

struct AntigravitySettingsOperations: Sendable {
    let check: @MainActor @Sendable () async -> AntigravitySettingsObservation
    let openOfficialSetup:
        @MainActor @Sendable () async -> AntigravitySettingsObservation
    let openProvider:
        @MainActor @Sendable () async -> AntigravitySettingsObservation
    let syncNow: @MainActor @Sendable () async -> AntigravitySettingsObservation
    let setAutoRefresh: @MainActor @Sendable (Bool) async -> Void
    let disable: @MainActor @Sendable () async -> Void

    static let unavailable = AntigravitySettingsOperations(
        check: {
            AntigravitySettingsObservation(
                state: .notInstalled,
                safeError: .executableMissing
            )
        },
        openOfficialSetup: {
            AntigravitySettingsObservation(
                state: .notInstalled,
                safeError: .executableMissing
            )
        },
        openProvider: {
            AntigravitySettingsObservation(
                state: .loginRequired,
                safeError: .authenticationRequired
            )
        },
        syncNow: {
            AntigravitySettingsObservation(
                state: .failed,
                safeError: .unavailable
            )
        },
        setAutoRefresh: { _ in },
        disable: {}
    )
}

@MainActor
public final class AntigravitySettingsModel: ObservableObject {
    @Published public private(set) var state: AntigravitySettingsPresentationState
    @Published public private(set) var safeError: AntigravitySettingsSafeError?
    @Published public private(set) var activeAction: AntigravitySettingsAction?
    @Published public private(set) var actionInProgress = false
    @Published public private(set) var autoRefreshEnabled: Bool

    public let sourceTransparency = AntigravitySourceTransparency()
    private let operations: AntigravitySettingsOperations
    private var observationTask: Task<Void, Never>?

    init(
        operations: AntigravitySettingsOperations = .unavailable,
        initialState: AntigravitySettingsPresentationState = .disabled,
        autoRefreshEnabled: Bool = true
    ) {
        self.operations = operations
        state = initialState
        safeError = nil
        self.autoRefreshEnabled = autoRefreshEnabled
    }

    deinit {
        observationTask?.cancel()
    }

    public convenience init(
        initialState: AntigravitySettingsPresentationState = .disabled,
        autoRefreshEnabled: Bool = true,
        checkAgain:
            @escaping @MainActor @Sendable () async -> AntigravitySettingsObservation,
        syncNow:
            @escaping @MainActor @Sendable () async -> AntigravitySettingsObservation,
        disable: @escaping @MainActor @Sendable () async -> Void,
        setAutoRefresh:
            @escaping @MainActor @Sendable (Bool) async -> Void = { _ in },
        openOfficialSetup:
            (@MainActor @Sendable () async -> AntigravitySettingsObservation)? = nil,
        openProvider:
            (@MainActor @Sendable () async -> AntigravitySettingsObservation)? = nil
    ) {
        self.init(
            operations: AntigravitySettingsOperations(
                check: checkAgain,
                openOfficialSetup: openOfficialSetup ?? checkAgain,
                openProvider: openProvider ?? checkAgain,
                syncNow: syncNow,
                setAutoRefresh: setAutoRefresh,
                disable: disable
            ),
            initialState: initialState,
            autoRefreshEnabled: autoRefreshEnabled
        )
    }

    public func checkAntigravity() {
        run(.checking, pendingState: .checking, operation: operations.check)
    }

    public func openOfficialSetup() {
        run(
            .openingOfficialSetup,
            pendingState: .openingOfficialSetup,
            operation: operations.openOfficialSetup
        )
    }

    public func openProvider() {
        run(
            .openingProvider,
            pendingState: .openingOfficialSetup,
            operation: operations.openProvider
        )
    }

    public func syncNow() {
        run(
            .refreshing,
            pendingState: .refreshing(state.capturedAt),
            operation: operations.syncNow
        )
    }

    public func setAutoRefreshEnabled(_ enabled: Bool) {
        guard !actionInProgress, enabled != autoRefreshEnabled else { return }
        actionInProgress = true
        activeAction = .changingAutoRefresh
        let operations = self.operations
        Task { @MainActor [weak self] in
            await operations.setAutoRefresh(enabled)
            guard let self else { return }
            autoRefreshEnabled = enabled
            activeAction = nil
            actionInProgress = false
        }
    }

    public func disable() {
        guard !actionInProgress else { return }
        actionInProgress = true
        activeAction = .disabling
        safeError = nil
        let operations = self.operations
        Task { @MainActor [weak self] in
            await operations.setAutoRefresh(false)
            await operations.disable()
            guard let self else { return }
            state = .disabled
            autoRefreshEnabled = false
            activeAction = nil
            actionInProgress = false
        }
    }

    func receive(_ observation: AntigravitySettingsObservation) {
        guard !actionInProgress else { return }
        state = observation.state
        safeError = observation.safeError
    }

    func observe(
        from connector: GoogleAntigravityUsageConnector,
        map: @escaping @Sendable (AgentUsageSnapshot) -> AntigravitySettingsObservation
    ) {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            let stream = await connector.snapshots()
            for await snapshot in stream {
                guard !Task.isCancelled, self != nil else { return }
                self?.receive(map(snapshot))
            }
        }
    }

    private func run(
        _ action: AntigravitySettingsAction,
        pendingState: AntigravitySettingsPresentationState,
        operation:
            @escaping @MainActor @Sendable () async -> AntigravitySettingsObservation
    ) {
        guard !actionInProgress else { return }
        actionInProgress = true
        activeAction = action
        safeError = nil
        state = pendingState
        Task { @MainActor [weak self] in
            let observation = await operation()
            guard let self else { return }
            state = observation.state
            safeError = observation.safeError
            activeAction = nil
            actionInProgress = false
        }
    }
}

private extension AntigravitySettingsPresentationState {
    var capturedAt: Date? {
        switch self {
        case let .connected(date), let .fresh(date), let .cached(date),
             let .stale(date):
            date
        case let .refreshing(date):
            date
        case .disabled, .checking, .notInstalled, .openingOfficialSetup,
             .loginRequired, .failed:
            nil
        }
    }
}
