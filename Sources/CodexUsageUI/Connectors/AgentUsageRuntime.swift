import AppKit
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
    public let store: UsageStore
    public let claudeSettings: ClaudeBrowserSettingsModel
    public let antigravitySettings: AntigravitySettingsModel
    public let workBuddySettings: WorkBuddySettingsModel
    public let workBuddyLogin: WorkBuddyLoginCoordinator
    public let workBuddyAccountWebSync: WorkBuddyAccountWebSessionController

    public static func live(
        workBuddyStoreURL: URL? = nil,
        snapshotStoreURL: URL? = nil
    ) -> UsageMonitorRuntime {
        let manualStore = workBuddyStoreURL.map {
            WorkBuddyManualAvailabilityStore(fileURL: $0)
        } ?? WorkBuddyManualAvailabilityStore()
        let manualSource = ManualWorkBuddyAvailabilitySource(store: manualStore)
        let snapshotStore = snapshotStoreURL.map {
            AgentConnectorSnapshotStore(url: $0)
        } ?? AgentConnectorSnapshotStore()
        let claudeConsent = ClaudeBrowserConsentStore()
        let claudeCache = ClaudeBrowserSanitizedCacheStore()
        let claudeIntegration = ClaudeBrowserProductionIntegration.make()
        let claudeConnector = ClaudeCodeUsageConnector.production(
            integration: claudeIntegration,
            hasConsent: { @MainActor in claudeConsent.consentGranted },
            clearConsent: { @MainActor in
                claudeConsent.consentGranted = false
            },
            readCache: { await claudeCache.load() },
            writeCache: { data in try? await claudeCache.save(data) },
            clearCache: { try? await claudeCache.clear() },
            autoRefreshEnabled: { @MainActor in
                claudeConsent.autoRefreshEnabled
            },
            allowSafariLaunch: { @MainActor in
                claudeConsent.allowSafariLaunch
            }
        )
        let workBuddyConnector = WorkBuddyAvailabilityConnector(source: manualSource)
        let accountWebSync = WorkBuddyAccountWebSessionController()
        let accountWebConnector = WorkBuddyAccountWebCreditsConnector(
            hasConsent: { @MainActor in
                accountWebSync.consentGranted
            },
            canReadOnApplicationLaunch: { @MainActor in
                accountWebSync.canReadOnApplicationLaunch
            },
            reader: { @MainActor in
                await accountWebSync.readCurrentCredits()
            },
            disconnectOwnedSession: { @MainActor in
                await accountWebSync.disconnectAndClearOwnedWebsiteData()
            }
        )
        let agentSettings = AgentSettingsCoordinator()
        let antigravityRefresh = AntigravityAutoRefreshPreference()
        let antigravityClient = AntigravityReadOnlyCLIClient()
        let antigravityConnector = GoogleAntigravityUsageConnector(
            client: antigravityClient,
            autoRefreshEnabled: { @MainActor in
                antigravityRefresh.isEnabled
            }
        )
        let registry = AgentUsageRuntime.makeCodexRegistry(
            snapshotStore: snapshotStore,
            additionalConnectors: [
                claudeConnector,
                workBuddyConnector,
                accountWebConnector,
                antigravityConnector,
            ]
        )
        let claudeSettings = ClaudeBrowserSettingsModel(
            connector: claudeConnector,
            consentStore: claudeConsent,
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
        accountWebSync.configureAutoRefresh {
            guard await MainActor.run(body: {
                agentSettings.isMonitoringEnabled(
                    for: WorkBuddyAccountWebCreditsConnector.connectorID
                )
            }) else {
                return
            }
            try? await registry.refresh(
                WorkBuddyAccountWebCreditsConnector.connectorID,
                trigger: .timer
            )
        }
        let usageStore = UsageStore(
            registry: registry,
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: .standard,
            agentSettings: agentSettings
        )
        let refreshAntigravityAdmissions:
            @MainActor @Sendable (ProviderEligibilityScanTrigger) async -> AntigravitySettingsObservation = {
                trigger in
                let descriptors = await registry.orderedDescriptors()
                let excluded = agentSettings.disabledConnectorIDs(
                    from: descriptors.map(\.id)
                )
                _ = await registry.scanSurfaceAdmissions(
                    trigger: trigger,
                    excludedProviderIDs: excluded
                )
                return Self.antigravityObservation(
                    await antigravityConnector.currentSnapshot()
                )
            }
        let antigravitySettings = AntigravitySettingsModel(
            initialState: .checking,
            autoRefreshEnabled: antigravityRefresh.isEnabled,
            checkAgain: {
                await refreshAntigravityAdmissions(.checkAgain)
            },
            syncNow: {
                await refreshAntigravityAdmissions(.syncNow)
            },
            disable: {
                antigravityRefresh.isEnabled = false
                await antigravityConnector.setAutomaticRefreshEnabled(false)
                try? await registry.perform(
                    .disconnect,
                    for: GoogleAntigravityUsageConnector.connectorID
                )
                agentSettings.setMonitoringEnabled(
                    false,
                    for: GoogleAntigravityUsageConnector.connectorID
                )
            },
            setAutoRefresh: { enabled in
                antigravityRefresh.isEnabled = enabled
                await antigravityConnector.setAutomaticRefreshEnabled(enabled)
            },
            openOfficialSetup: {
                if let url = URL(
                    string: "https://antigravity.google/docs/cli/install"
                ) {
                    NSWorkspace.shared.open(url)
                }
                return await refreshAntigravityAdmissions(.checkAgain)
            },
            openProvider: {
                if let url = URL(
                    string: "https://antigravity.google/docs/cli/install"
                ) {
                    NSWorkspace.shared.open(url)
                }
                return AntigravitySettingsObservation(state: .loginRequired)
            }
        )
        Task { @MainActor [weak antigravitySettings] in
            let stream = await antigravityConnector.snapshots()
            for await snapshot in stream {
                guard !Task.isCancelled else { return }
                antigravitySettings?.receive(
                    Self.antigravityObservation(snapshot)
                )
            }
        }
        Task {
            let shouldStartClaude = claudeConsent.consentGranted
            // Browser Sync is not a passive local-availability source, but a
            // previously consented session still owns a local listener and
            // automatic scheduler. Start it before awaiting any passive source
            // so a slow provider cannot delay the listener or first cycle.
            if shouldStartClaude {
                await claudeConnector.start()
            }
            await registry.startPassiveConnectors()
            guard shouldStartClaude else { return }
            let descriptors = await registry.orderedDescriptors()
            let excluded = agentSettings.disabledConnectorIDs(
                from: descriptors.map(\.id)
            )
            _ = await registry.scanSurfaceAdmissions(
                trigger: .applicationLaunch,
                excludedProviderIDs: excluded
            )
        }
        let settings = WorkBuddySettingsModel(source: manualSource)
        let login = WorkBuddyLoginCoordinator()
        return UsageMonitorRuntime(
            store: usageStore,
            claudeSettings: claudeSettings,
            antigravitySettings: antigravitySettings,
            workBuddySettings: settings,
            workBuddyLogin: login,
            workBuddyAccountWebSync: accountWebSync
        )
    }

    static func antigravityObservation(
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
        environment: [String: String]
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
            snapshotStoreURL: configuration.snapshotStoreURL
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
        allowedRoot: URL
    ) throws -> UsageMonitorRuntime {
        let configuration = try storeConfiguration(
            bundleIdentifier: bundleIdentifier,
            environment: environment,
            m2wdbgAllowedRoot: allowedRoot,
            r1AllowedRoot: allowedRoot
        )
        return live(
            workBuddyStoreURL: configuration.workBuddyStoreURL,
            snapshotStoreURL: configuration.snapshotStoreURL
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
    private static let key = "antigravity.autoRefreshEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.key) == nil {
            defaults.set(true, forKey: Self.key)
        }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}
