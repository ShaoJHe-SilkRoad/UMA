import AppKit
import ClaudeStatusLineCore
import Foundation

enum UsageMonitorRuntimeError: Error, Equatable {
    case invalidM2WDBGStoreConfiguration
    case invalidM2WDBGR1StoreConfiguration
}

struct UsageMonitorStoreConfiguration: Equatable {
    let workBuddyStoreURL: URL?
    let snapshotStoreURL: URL?
}

/// Composition root for the built-in providers. Adding a future connector
/// changes this registration list, not the shared store, UI, or Codex files.
enum AgentUsageRuntime {
    static func makeCodexRegistry(
        snapshotStore: AgentConnectorSnapshotStore? = AgentConnectorSnapshotStore(),
        client: any CodexUsageClient = CodexAppServerClient(),
        localActivityReader: any CodexLocalActivityReading = CodexLocalActivityReader(),
        additionalConnectors: [any AgentUsageConnector] = []
    ) -> AgentConnectorRegistry {
        let connector = CodexUsageConnector(client: client, localActivityReader: localActivityReader)
        // The composition is static and internally controlled, so duplicate
        // registration here is a programmer error rather than runtime input.
        return try! AgentConnectorRegistry(
            connectors: [connector] + additionalConnectors,
            snapshotStore: snapshotStore
        )
    }
}

@MainActor
public struct UsageMonitorRuntime {
    static let productionConnectorIDs: Set<AgentConnectorID> = [
        CodexUsageConnector.connectorID,
        ClaudeCodeUsageConnector.connectorID,
    ]

    public let preferences: ApplicationPreferences
    public let store: UsageStore
    public let claudeSettings: ClaudeBrowserSettingsModel

    public static func live(
        workBuddyStoreURL: URL? = nil,
        snapshotStoreURL: URL? = nil,
        startProviders: Bool = true,
        preferenceDefaults: UserDefaults = .standard
    ) -> UsageMonitorRuntime {
        _ = workBuddyStoreURL
        let preferences = ApplicationPreferences(userDefaults: preferenceDefaults)
        let snapshotStore = snapshotStoreURL.map {
            AgentConnectorSnapshotStore(url: $0)
        } ?? AgentConnectorSnapshotStore()
        let claudeConsent = ClaudeBrowserConsentStore(defaults: preferenceDefaults)
        let claudeCache = ClaudeBrowserSanitizedCacheStore()
        let claudeIntegration = ClaudeBrowserProductionIntegration.make()
        let claudeSurfaceDetector = ClaudeLocalSurfaceDetector()
        let claudePaths = ClaudeStatusLineConfigurationPaths()
        let claudeRelay = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("ClaudeStatusLineRelay")
        let relayCommand = [
            claudeRelay.path,
            "--state",
            claudePaths.stateURL.path,
            "--prior-status-line",
            claudePaths.backupURL.path,
        ].map(Self.shellQuote).joined(separator: " ")
        let claudeLocalActivityReader: (any ClaudeLocalActivityReading)? =
            claudeSurfaceDetector.statusLineCapableSurfaceInstalled
                ? ClaudeLocalActivityReader()
                : nil
        let claudeDesktopPlanUsageReader: (any ClaudeDesktopPlanUsageReading)? =
            claudeSurfaceDetector.claudeDesktopInstalled
                ? ClaudeDesktopPlanUsageReader()
                : nil
        let claudeConfiguration = ClaudeStatusLineConfigurationManager(
            paths: claudePaths,
            relayCommand: relayCommand
        )
        let claudeConnector = ClaudeCodeUsageConnector.production(
            integration: claudeIntegration,
            hasConsent: { @MainActor in claudeConsent.consentGranted },
            clearConsent: { @MainActor in
                claudeConsent.consentGranted = false
            },
            readCache: { await claudeCache.load() },
            writeCache: { data in try? await claudeCache.save(data) },
            clearCache: { try? await claudeCache.clear() },
            statusStateURL: claudePaths.stateURL,
            localActivityReader: claudeLocalActivityReader,
            desktopPlanUsageReader: claudeDesktopPlanUsageReader,
            desktopActivityContract: claudeSurfaceDetector.claudeDesktopInstalled
                ? .estimateOnlyNoActivitySignal
                : .notApplicable,
            anchorStore: ClaudeSmartAnchorStore()
        )
        let agentSettings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: preferences)
        )
        let registry = AgentUsageRuntime.makeCodexRegistry(
            snapshotStore: snapshotStore,
            additionalConnectors: [claudeConnector]
        )
        let claudeSettings = ClaudeBrowserSettingsModel(
            connector: claudeConnector,
            consentStore: claudeConsent,
            // Claude Desktop's hosted agent uses an isolated per-session
            // configuration root. Only a detected terminal/IDE surface may be
            // configured through the supported user-level statusLine scope.
            configurationManager: claudeSurfaceDetector
                .statusLineCapableSurfaceInstalled ? claudeConfiguration : nil,
            refreshAdmissions: { @MainActor in
                let descriptors = await registry.orderedDescriptors()
                let excluded = agentSettings.disabledConnectorIDs(
                    from: descriptors.map(\.id)
                )
                _ = await registry.scanSurfaceAdmissions(
                    trigger: .manualRefresh,
                    excludedProviderIDs: excluded
                )
            }
        )
        let usageStore = UsageStore(
            registry: registry,
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: preferenceDefaults,
            preferences: preferences,
            agentSettings: agentSettings
        )
        if startProviders {
            Task {
                let shouldStartClaude = claudeConsent.consentGranted
                // Local Smart Mode owns one local file monitor and no recurring
                // browser scheduler. Start it before passive admission so the next
                // official Claude Code status-line write is observed immediately.
                if shouldStartClaude {
                    await claudeConnector.start()
                }
                await registry.startPassiveConnectors()
                let descriptors = await registry.orderedDescriptors()
                var excluded = agentSettings.disabledConnectorIDs(
                    from: descriptors.map(\.id)
                )
                if !usageStore.monitorConsentGranted {
                    excluded.insert(CodexUsageConnector.connectorID)
                }
                if !shouldStartClaude {
                    excluded.insert(ClaudeCodeUsageConnector.connectorID)
                }
                _ = await registry.scanSurfaceAdmissions(
                    trigger: .applicationLaunch,
                    excludedProviderIDs: excluded
                )
            }
        }
        return UsageMonitorRuntime(
            preferences: preferences,
            store: usageStore,
            claudeSettings: claudeSettings
        )
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    nonisolated static func antigravityObservation(
        _ snapshot: AgentUsageSnapshot
    ) -> AntigravitySettingsObservation {
        let observedAt = snapshot.lastSuccessfulAt ?? snapshot.capturedAt
        let state: AntigravitySettingsPresentationState = switch (
            snapshot.state,
            snapshot.freshness,
            snapshot.safeFailure
        ) {
        case (.inactive, _, _): .disabled
        case (.authenticationRequired, _, _): .loginRequired
        case (.waitingForFirstResponse, _, _): .refreshing(nil)
        case (.ready, .fresh, _): .fresh(observedAt)
        case (.ready, .cached, _): .cached(observedAt)
        case (.stale, _, _), (.ready, .stale, _): .stale(observedAt)
        case (.unsupported, _, .unavailable): .notInstalled
        case (.unsupported, _, _), (.failed, _, _): .failed
        default: .failed
        }
        let safeError: AntigravitySettingsSafeError? = switch (
            snapshot.state,
            snapshot.safeFailure
        ) {
        case (.unsupported, .unavailable): .executableMissing
        case (_, .authorizationRequired): .authenticationRequired
        case (_, .timedOut): .timedOut
        case (_, .unsupported): .unsupportedVersion
        case (_, .malformedResponse): .unsupportedSchema
        case (_, .unavailable), (_, .processExited), (_, .unknown): .unavailable
        case (_, nil): nil
        }
        return AntigravitySettingsObservation(
            state: state,
            safeError: safeError
        )
    }

    /// Production uses the ordinary stores. A task-owned M2WDBG bundle must
    /// provide both valid isolated stores or startup fails before either
    /// ordinary user store is constructed. The R1 review lane keeps the
    /// production bundle identity and ordinary Codex snapshot environment,
    /// while allowing only WorkBuddy's manual record to use a task-owned path.
    public static func live(
        bundleIdentifier: String?,
        environment: [String: String],
        startProviders: Bool = true,
        preferenceDefaults: UserDefaults = .standard
    ) throws -> UsageMonitorRuntime {
        let configuration = try storeConfiguration(
            bundleIdentifier: bundleIdentifier,
            environment: environment,
            m2wdbgAllowedRoot: URL(
                fileURLWithPath: "/private/tmp/uma-m2wdbg-runtime",
                isDirectory: true
            ),
            r1AllowedRoot: URL(
                fileURLWithPath: "/private/tmp/uma-m2wdbg-r1-runtime",
                isDirectory: true
            )
        )
        return live(
            workBuddyStoreURL: configuration.workBuddyStoreURL,
            snapshotStoreURL: configuration.snapshotStoreURL,
            startProviders: startProviders,
            preferenceDefaults: preferenceDefaults
        )
    }

    nonisolated static func storeConfiguration(
        bundleIdentifier: String?,
        environment: [String: String],
        m2wdbgAllowedRoot: URL,
        r1AllowedRoot: URL
    ) throws -> UsageMonitorStoreConfiguration {
        if environment.keys.contains("UMA_M2WDBG_R1_MANUAL_STORE") {
            guard bundleIdentifier == "com.silkrd.uma",
                  let workBuddyStoreURL = r1ManualStoreURL(
                bundleIdentifier: bundleIdentifier,
                environment: environment,
                allowedRoot: r1AllowedRoot
            ) else {
                throw UsageMonitorRuntimeError.invalidM2WDBGR1StoreConfiguration
            }
            return UsageMonitorStoreConfiguration(
                workBuddyStoreURL: workBuddyStoreURL,
                snapshotStoreURL: nil
            )
        }

        guard bundleIdentifier?.hasPrefix(
            "com.silkrd.uma.m2wdbg."
        ) == true
        else {
            return UsageMonitorStoreConfiguration(
                workBuddyStoreURL: nil,
                snapshotStoreURL: nil
            )
        }
        guard let workBuddyStoreURL = m2wdbgStoreURL(
            bundleIdentifier: bundleIdentifier,
            environment: environment,
            variable: "UMA_M2WDBG_MANUAL_STORE",
            allowedRoot: m2wdbgAllowedRoot
        ),
              let snapshotStoreURL = m2wdbgStoreURL(
                bundleIdentifier: bundleIdentifier,
                environment: environment,
                variable: "UMA_M2WDBG_SNAPSHOT_STORE",
                allowedRoot: m2wdbgAllowedRoot
              )
        else {
            throw UsageMonitorRuntimeError.invalidM2WDBGStoreConfiguration
        }
        return UsageMonitorStoreConfiguration(
            workBuddyStoreURL: workBuddyStoreURL,
            snapshotStoreURL: snapshotStoreURL
        )
    }

    static func live(
        bundleIdentifier: String?,
        environment: [String: String],
        allowedRoot: URL,
        startProviders: Bool = true,
        preferenceDefaults: UserDefaults = .standard
    ) throws -> UsageMonitorRuntime {
        let configuration = try storeConfiguration(
            bundleIdentifier: bundleIdentifier,
            environment: environment,
            m2wdbgAllowedRoot: allowedRoot,
            r1AllowedRoot: allowedRoot
        )
        return live(
            workBuddyStoreURL: configuration.workBuddyStoreURL,
            snapshotStoreURL: configuration.snapshotStoreURL,
            startProviders: startProviders,
            preferenceDefaults: preferenceDefaults
        )
    }

    /// A packaged debug candidate may opt into isolated synthetic stores.
    /// Paths outside the task-owned root are deliberately ignored.
    nonisolated public static func m2wdbgStoreURL(
        bundleIdentifier: String?,
        environment: [String: String],
        variable: String = "UMA_M2WDBG_MANUAL_STORE"
    ) -> URL? {
        m2wdbgStoreURL(
            bundleIdentifier: bundleIdentifier,
            environment: environment,
            variable: variable,
            allowedRoot: URL(
                fileURLWithPath: "/private/tmp/uma-m2wdbg-runtime",
                isDirectory: true
            )
        )
    }

    nonisolated static func m2wdbgStoreURL(
        bundleIdentifier: String?,
        environment: [String: String],
        variable: String,
        allowedRoot: URL
    ) -> URL? {
        guard bundleIdentifier?.hasPrefix(
            "com.silkrd.uma.m2wdbg."
        ) == true,
              let rawPath = environment[variable],
              rawPath.hasPrefix("/")
        else {
            return nil
        }
        return validatedJSONStoreURL(rawPath: rawPath, allowedRoot: allowedRoot)
    }

    nonisolated public static func r1ManualStoreURL(
        bundleIdentifier: String?,
        environment: [String: String]
    ) -> URL? {
        r1ManualStoreURL(
            bundleIdentifier: bundleIdentifier,
            environment: environment,
            allowedRoot: URL(
                fileURLWithPath: "/private/tmp/uma-m2wdbg-r1-runtime",
                isDirectory: true
            )
        )
    }

    nonisolated static func r1ManualStoreURL(
        bundleIdentifier: String?,
        environment: [String: String],
        allowedRoot: URL
    ) -> URL? {
        guard bundleIdentifier == "com.silkrd.uma",
              let rawPath = environment["UMA_M2WDBG_R1_MANUAL_STORE"],
              rawPath.hasPrefix("/")
        else {
            return nil
        }
        return validatedJSONStoreURL(rawPath: rawPath, allowedRoot: allowedRoot)
    }

    nonisolated private static func validatedJSONStoreURL(
        rawPath: String,
        allowedRoot: URL
    ) -> URL? {
        let fileManager = FileManager.default
        let lexicalRoot = allowedRoot.standardizedFileURL
        var rootIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: lexicalRoot.path,
            isDirectory: &rootIsDirectory
        ),
              rootIsDirectory.boolValue,
              (try? fileManager.destinationOfSymbolicLink(
                atPath: lexicalRoot.path
              )) == nil
        else {
            return nil
        }

        let lexicalURL = URL(fileURLWithPath: rawPath).standardizedFileURL
        let url = lexicalURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(lexicalURL.lastPathComponent)
        let resolvedRoot = lexicalRoot.resolvingSymlinksInPath()
        let allowedPrefix = resolvedRoot.path.hasSuffix("/")
            ? resolvedRoot.path
            : resolvedRoot.path + "/"
        guard url.path.hasPrefix(allowedPrefix),
              url.pathExtension == "json",
              (try? fileManager.destinationOfSymbolicLink(
                atPath: url.path
              )) == nil
        else {
            return nil
        }
        return url
    }
}

@MainActor
private final class AntigravityAutoRefreshPreference {
    private let preferences: ApplicationPreferences

    init(preferences: ApplicationPreferences = .production) {
        self.preferences = preferences
    }

    var isEnabled: Bool {
        get { preferences.value(for: UMAApplicationPreferenceKeys.antigravityAutoRefresh) }
        set { preferences.set(newValue, for: UMAApplicationPreferenceKeys.antigravityAutoRefresh) }
    }
}
