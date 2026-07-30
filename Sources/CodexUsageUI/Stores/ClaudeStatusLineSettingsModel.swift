import ClaudeStatusLineCore
import Combine
import Foundation

enum ClaudeSettingsPresentationState: Equatable, Sendable {
    case unconfigured
    case ready
    case waiting
    case fresh(Date)
    case stale(Date?)
    case unsupported
    case failed
    case repairRequired
}

struct ClaudeSourceTransparency: Equatable, Sendable {
    let credentialsAccessed = false
    let networkRequestsMade = false
    let transcriptRead = false
    let rawProviderPayloadStored = false
    let authenticationManager = "Claude Code"
}

@MainActor
public final class ClaudeStatusLineSettingsModel: ObservableObject {
    @Published private(set) var state: ClaudeSettingsPresentationState
    @Published private(set) var actionInProgress = false
    @Published private(set) var safeError: String?

    let sourceTransparency = ClaudeSourceTransparency()
    private let manager: ClaudeStatusLineConfigurationManager
    private let connector: ClaudeCodeUsageConnector
    private var observationTask: Task<Void, Never>?

    init(
        manager: ClaudeStatusLineConfigurationManager,
        connector: ClaudeCodeUsageConnector,
        initialState: ClaudeSettingsPresentationState = .unconfigured
    ) {
        self.manager = manager
        self.connector = connector
        state = initialState
        observationTask = Task { [weak self] in
            let stream = await connector.snapshots()
            for await snapshot in stream {
                guard !Task.isCancelled, let self else { return }
                let check = await Task.detached {
                    manager.check()
                }.value
                self.updatePresentation(
                    check: check,
                    connectorState: await connector.lifecycleState(),
                    snapshot: snapshot
                )
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    static func production(
        connector: ClaudeCodeUsageConnector
    ) -> ClaudeStatusLineSettingsModel {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let applicationSupport = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(
                "Application Support",
                isDirectory: true
            )
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(
                "ClaudeStatusLineRelay",
                isDirectory: false
            )
        let command = "'"
            + helper.path.replacingOccurrences(
                of: "'",
                with: "'\"'\"'"
            )
            + "'"
        return ClaudeStatusLineSettingsModel(
            manager: ClaudeStatusLineConfigurationManager(
                paths: ClaudeStatusLineConfigurationPaths(
                    homeDirectory: home,
                    applicationSupportDirectory: applicationSupport
                ),
                relayCommand: command
            ),
            connector: connector
        )
    }

    func checkClaudeCode() {
        run(.check)
    }

    func enableIntegration() {
        run(.enable)
    }

    func repairRelay() {
        run(.repair)
    }

    func disableIntegration() {
        run(.disable)
    }

    private enum Action: Sendable {
        case check
        case enable
        case repair
        case disable
    }

    private func run(_ action: Action) {
        guard !actionInProgress else { return }
        actionInProgress = true
        safeError = nil
        let manager = self.manager
        let connector = self.connector
        Task {
            do {
                switch action {
                case .check:
                    _ = await connector.probe()
                case .enable:
                    try await Task.detached {
                        try manager.enable()
                    }.value
                    await connector.perform(.connect)
                case .repair:
                    try await Task.detached {
                        try manager.repair()
                    }.value
                    await connector.perform(.reconnect)
                case .disable:
                    try await Task.detached {
                        try manager.disable()
                    }.value
                    await connector.perform(.disconnect)
                }
                updatePresentation(
                    check: await Task.detached {
                        manager.check()
                    }.value,
                    connectorState: await connector.lifecycleState(),
                    snapshot: await connector.currentSnapshot()
                )
            } catch {
                state = .failed
                safeError = "Claude integration action could not be completed."
            }
            actionInProgress = false
        }
    }

    private func updatePresentation(
        check: ClaudeStatusLineConfigurationCheck,
        connectorState: ClaudeConnectorLifecycleState,
        snapshot: AgentUsageSnapshot
    ) {
        switch check.state {
        case .unconfigured:
            state = .unconfigured
        case .ready:
            state = .ready
        case .repairRequired:
            state = .repairRequired
        case .unsupported:
            state = .unsupported
        case .failed:
            state = .failed
        case .installed:
            state = switch connectorState {
            case .fresh:
                .fresh(snapshot.lastSuccessfulAt ?? snapshot.capturedAt)
            case .stale:
                .stale(snapshot.lastSuccessfulAt)
            case .repairRequired:
                .repairRequired
            case .unsupported:
                .unsupported
            case .failed:
                .failed
            case .notInstalled:
                .ready
            case .installedWaiting:
                .waiting
            }
        }
    }
}
