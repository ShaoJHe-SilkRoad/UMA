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
        threadOSAttributionSource: any ThreadOSHistoricalAttributionReading = UnavailableThreadOSHistoricalAttributionSource(),
        additionalConnectors: [any AgentUsageConnector] = []
    ) -> AgentConnectorRegistry {
        let connector = CodexUsageConnector(
            client: client,
            localActivityReader: localActivityReader,
            threadOSAttributionSource: threadOSAttributionSource
        )
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
    /// Admitted usage connectors. Grok Bot is deliberately absent: presence is
    /// a fail-closed diagnostic (`GrokBotPresenceProbe`), not a usage provider.
    static let productionConnectorIDs: Set<AgentConnectorID> = [
        CodexUsageConnector.connectorID,
        ClaudeCodeUsageConnector.connectorID,
    ]

    public let preferences: ApplicationPreferences
    public let dataPaths: ApplicationDataPaths
    public let store: UsageStore
    public let claudeSettings: ClaudeBrowserSettingsModel
    private let startupTask: Task<Void, Never>?
    private let threadOSAttributionPreferenceObservation: ApplicationPreferences.Observation?

    init(
        preferences: ApplicationPreferences,
        store: UsageStore,
        claudeSettings: ClaudeBrowserSettingsModel,
        startupTask: Task<Void, Never>? = nil,
        threadOSAttributionPreferenceObservation: ApplicationPreferences.Observation? = nil,
        dataPaths: ApplicationDataPaths = .current()
    ) {
        self.preferences = preferences
        self.dataPaths = dataPaths
        self.store = store
        self.claudeSettings = claudeSettings
        self.startupTask = startupTask
        self.threadOSAttributionPreferenceObservation = threadOSAttributionPreferenceObservation
    }

    /// Drain application-owned startup before stopping connectors. A late
    /// admission scan must never restart monitoring after termination.
    public func shutdown() async {
        startupTask?.cancel()
        await startupTask?.value
        await store.stopAllConnectors()
    }

    public static func live(
        workBuddyStoreURL: URL? = nil,
        snapshotStoreURL: URL? = nil,
        startProviders: Bool = true,
        preferenceDefaults: UserDefaults = .standard,
        dataPaths: ApplicationDataPaths = .current()
    ) -> UsageMonitorRuntime {
        _ = workBuddyStoreURL
        let dataPaths = dataPaths.overridingSnapshotURL(snapshotStoreURL)
        let preferences = ApplicationPreferences(userDefaults: preferenceDefaults)
        let snapshotStore = AgentConnectorSnapshotStore(
            url: dataPaths.snapshotURL
        )
        let claudeConsent = ClaudeBrowserConsentStore(defaults: preferenceDefaults)
        let claudeCache = ClaudeBrowserSanitizedCacheStore(url: dataPaths.browserCacheURL)
        let claudeIntegration: ClaudeBrowserProductionIntegration = startProviders
            ? .make() : .unavailable()
        let claudeSurfaceDetector = ClaudeLocalSurfaceDetector()
        // A diagnostic/fixture runtime must not inspect installed provider
        // surfaces or establish an immutable-Host connection.
        let statusLineSurfaceInstalled = startProviders
            && claudeSurfaceDetector.statusLineCapableSurfaceInstalled
        let desktopInstalled = startProviders && claudeSurfaceDetector.claudeDesktopInstalled
        let claudePaths = dataPaths.statusLinePaths
        let relayURL = dataPaths.supportsProviderConfiguration && statusLineSurfaceInstalled
            ? BundledClaudeRelay.executableURL() : nil
        let claudeConfiguration = relayURL.map { relay in
            ClaudeStatusLineConfigurationManager(
                paths: claudePaths,
                relayCommand: BundledClaudeRelay.command(executableURL: relay, paths: claudePaths)
            )
        }
        let claudeLocalActivityReader: (any ClaudeLocalActivityReading)? =
            statusLineSurfaceInstalled ? ClaudeLocalActivityReader() : nil
        let claudeDesktopPlanUsageReader: (any ClaudeDesktopPlanUsageReading)? =
            desktopInstalled ? ClaudeDesktopPlanUsageReader() : nil
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
            desktopActivityContract: desktopInstalled
                ? .estimateOnlyNoActivitySignal
                : .notApplicable,
            anchorStore: ClaudeSmartAnchorStore(
                url: dataPaths.smartAnchorsURL,
                allowsOwnedDirectoryPermissionMigration: true
            )
        )
        let agentSettings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: preferences)
        )
        let threadOSAttributionSource = ReloadableThreadOSHistoricalAttributionSource(
            ThreadOSHistoricalAttributionPreferences.source(from: preferences)
        )
        let threadOSAttributionPreferenceObservation = preferences.observe { change in
            guard change.key == ThreadOSHistoricalAttributionPreferences.binding.name else { return }
            threadOSAttributionSource.replace(with: ThreadOSHistoricalAttributionPreferences.source(from: preferences))
        }
        let registry = AgentUsageRuntime.makeCodexRegistry(
            snapshotStore: snapshotStore,
            localActivityReader: CodexLocalActivityReader(ledgerURL: dataPaths.codexLedgerURL),
            threadOSAttributionSource: threadOSAttributionSource,
            additionalConnectors: [claudeConnector]
        )
        let claudeSettings = ClaudeBrowserSettingsModel(
            connector: claudeConnector,
            consentStore: claudeConsent,
            // Claude Desktop's hosted agent uses an isolated per-session
            // configuration root. Only a detected terminal/IDE surface may be
            // configured through the supported user-level statusLine scope.
            configurationManager: claudeConfiguration,
            statusLineConfigurationIssue: statusLineSurfaceInstalled && claudeConfiguration == nil
                ? (dataPaths.supportsProviderConfiguration ? .requiresInstalledApp : .developmentIsolation)
                : nil,
            permitsDesktopLocalSmart: desktopInstalled,
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
            autoRefresh: startProviders,
            registry: startProviders ? registry : nil,
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: preferenceDefaults,
            preferences: preferences,
            agentSettings: agentSettings
        )
        let startupTask: Task<Void, Never>?
        if startProviders {
            startupTask = Task { @MainActor in
                guard !Task.isCancelled else { return }
                let shouldStartClaude = claudeConsent.consentGranted
                // Local Smart Mode owns one local file monitor and no recurring
                // browser scheduler. Start it before passive admission so the next
                // official Claude Code status-line write is observed immediately.
                if shouldStartClaude {
                    await claudeConnector.start()
                }
                guard !Task.isCancelled else { return }
                await registry.startPassiveConnectors()
                guard !Task.isCancelled else { return }
                let descriptors = await registry.orderedDescriptors()
                guard !Task.isCancelled else { return }
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
        } else {
            startupTask = nil
        }
        return UsageMonitorRuntime(
            preferences: preferences,
            store: usageStore,
            claudeSettings: claudeSettings,
            startupTask: startupTask,
            threadOSAttributionPreferenceObservation: threadOSAttributionPreferenceObservation,
            dataPaths: dataPaths
        )
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
            preferenceDefaults: preferenceDefaults,
            dataPaths: .current(bundleIdentifier: bundleIdentifier)
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
            preferenceDefaults: preferenceDefaults,
            dataPaths: .current(
                bundleIdentifier: bundleIdentifier,
                applicationSupportDirectory: allowedRoot.appendingPathComponent("Library/Application Support", isDirectory: true),
                homeDirectory: allowedRoot
            )
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
