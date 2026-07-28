import Combine
import Foundation

public enum ManusSettingsConnectionState: String, Equatable, Sendable {
    case disconnected
    case configured
    case verifying
    case connected
    case failed
}

public enum ManusSettingsSafeFailure: String, Equatable, Sendable {
    case missingCredential
    case credentialUnavailable
    case authentication
    case rateLimited
    case network
    case server
    case invalidResponse
    case cancelled
    case unknown
}

@MainActor
public final class ManusSettingsModel: ObservableObject {
    static let autoRefreshKey = "manus.apiV2.autoRefresh"

    @Published public var draftCredential = ""
    @Published public private(set) var connectionState:
        ManusSettingsConnectionState = .disconnected
    @Published public private(set) var lastUpdatedAt: Date?
    @Published public private(set) var safeFailure: ManusSettingsSafeFailure?
    @Published public private(set) var autoRefreshEnabled: Bool
    @Published public private(set) var credentialConfigured = false

    private let keyStore: any ManusAPIKeyStoring
    private let connector: ManusUsageConnector
    private let registry: AgentConnectorRegistry
    private let scheduler: ManusRefreshScheduler
    private let defaults: UserDefaults
    private var observationTask: Task<Void, Never>?

    init(
        keyStore: any ManusAPIKeyStoring,
        connector: ManusUsageConnector,
        registry: AgentConnectorRegistry,
        scheduler: ManusRefreshScheduler,
        defaults: UserDefaults = .standard
    ) {
        self.keyStore = keyStore
        self.connector = connector
        self.registry = registry
        self.scheduler = scheduler
        self.defaults = defaults
        autoRefreshEnabled = defaults.bool(forKey: Self.autoRefreshKey)
    }

    public var canSaveAndVerify: Bool {
        !draftCredential.isEmpty
            && draftCredential.utf8.count <= 4_096
            && !draftCredential.contains(where: \.isNewline)
            && connectionState != .verifying
    }

    public var isConfigured: Bool {
        credentialConfigured
    }

    public func start() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            switch await keyStore.configurationState() {
            case .configured:
                credentialConfigured = true
                connectionState = .configured
                safeFailure = nil
                await scheduler.setEnabled(autoRefreshEnabled)
            case .notConfigured:
                credentialConfigured = false
                connectionState = .disconnected
                safeFailure = nil
                await scheduler.setEnabled(false)
            case let .unavailable(error):
                credentialConfigured = true
                connectionState = .failed
                safeFailure = Self.safeFailure(for: error)
                await scheduler.setEnabled(false)
            }

            let stream = await connector.snapshots()
            for await snapshot in stream {
                guard !Task.isCancelled else { return }
                await apply(snapshot)
            }
        }
    }

    public func cancelConnection() {
        discardDraft()
        safeFailure = nil
    }

    public func discardDraft() {
        draftCredential = ""
    }

    public func saveAndVerify() {
        guard canSaveAndVerify else {
            safeFailure = .missingCredential
            return
        }
        let credential = draftCredential
        draftCredential = ""
        connectionState = .verifying
        safeFailure = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let previousCredential: String?
                switch await keyStore.configurationState() {
                case .notConfigured:
                    previousCredential = nil
                case .configured:
                    previousCredential = try await keyStore.read()
                case let .unavailable(error):
                    throw error
                }
                try await keyStore.save(credential)
                credentialConfigured = true
                await scheduler.resumeAfterCredentialChange()
                _ = await registry.scanSurfaceAdmissions(
                    trigger: .checkAgain
                )
                await receiveCurrentSnapshot()
                guard connectionState == .connected else {
                    let verificationFailure = safeFailure ?? .unknown
                    do {
                        if let previousCredential {
                            try await keyStore.save(previousCredential)
                            credentialConfigured = true
                        } else {
                            try await keyStore.delete()
                            credentialConfigured = false
                        }
                    } catch {
                        credentialConfigured = true
                        safeFailure = .credentialUnavailable
                        connectionState = .failed
                        return
                    }
                    safeFailure = verificationFailure
                    connectionState = .failed
                    return
                }
            } catch let error as ManusAPIKeyStoreError {
                connectionState = .failed
                safeFailure = Self.safeFailure(for: error)
            } catch {
                connectionState = .failed
                safeFailure = .unknown
            }
        }
    }

    public func syncNow() {
        guard isConfigured, connectionState != .verifying else { return }
        connectionState = .verifying
        safeFailure = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await registry.scanSurfaceAdmissions(trigger: .syncNow)
            await receiveCurrentSnapshot()
        }
    }

    public func tearDown() {
        observationTask?.cancel()
        observationTask = nil
        Task { [scheduler] in
            await scheduler.tearDown()
        }
    }

    public func setAutoRefreshEnabled(_ enabled: Bool) {
        autoRefreshEnabled = enabled
        defaults.set(enabled, forKey: Self.autoRefreshKey)
        Task { [scheduler] in
            await scheduler.setEnabled(enabled)
        }
    }

    public func disconnect() {
        draftCredential = ""
        autoRefreshEnabled = false
        defaults.set(false, forKey: Self.autoRefreshKey)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await registry.perform(
                    .disconnect,
                    for: ManusUsageConnector.connectorID
                )
            } catch {
                await scheduler.cancel()
                connectionState = .failed
                credentialConfigured = true
                safeFailure = .unknown
                return
            }
            if let failure = await connector.currentSettingsFailure() {
                connectionState = .failed
                credentialConfigured = true
                lastUpdatedAt = nil
                safeFailure = failure
                return
            }
            connectionState = .disconnected
            credentialConfigured = false
            lastUpdatedAt = nil
            safeFailure = nil
        }
    }

    private func receiveCurrentSnapshot() async {
        let snapshot = await connector.currentSnapshot()
        await apply(snapshot)
    }

    private func apply(_ snapshot: AgentUsageSnapshot) async {
        if snapshot.state == .authenticationRequired,
           connectionState == .failed,
           safeFailure == .credentialUnavailable,
           await connector.currentSettingsFailure() == nil {
            return
        }
        if snapshot.state == .ready,
           snapshot.freshness == .fresh,
           snapshot.safeFailure == nil {
            connectionState = .connected
            lastUpdatedAt = snapshot.lastSuccessfulAt
            safeFailure = nil
            await scheduler.setEnabled(autoRefreshEnabled)
            return
        }
        if snapshot.state == .waitingForFirstResponse {
            connectionState = .verifying
            safeFailure = nil
            return
        }
        guard credentialConfigured else {
            connectionState = .disconnected
            safeFailure = nil
            return
        }
        connectionState = snapshot.state == .authenticationRequired
            ? .configured
            : .failed
        safeFailure = await connector.currentSettingsFailure()
            ?? Self.safeFailure(for: snapshot.safeFailure ?? .unknown)
    }

    private static func safeFailure(
        for error: ManusAPIKeyStoreError
    ) -> ManusSettingsSafeFailure {
        switch error {
        case .invalidCredential, .missingCredential:
            .missingCredential
        case .keychainLocked, .accessDenied, .unavailable:
            .credentialUnavailable
        case .invalidStoredCredential:
            .invalidResponse
        }
    }

    private static func safeFailure(
        for failure: AgentSafeFailure
    ) -> ManusSettingsSafeFailure {
        switch failure {
        case .authorizationRequired:
            .authentication
        case .timedOut:
            .network
        case .malformedResponse:
            .invalidResponse
        case .unavailable:
            .credentialUnavailable
        case .unsupported, .processExited, .unknown:
            .unknown
        }
    }
}
