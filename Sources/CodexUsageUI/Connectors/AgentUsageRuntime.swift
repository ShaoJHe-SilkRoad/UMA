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
            clearCache: { try? await claudeCache.clear() }
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
        let registry = AgentUsageRuntime.makeCodexRegistry(
            snapshotStore: snapshotStore,
            additionalConnectors: [
                claudeConnector,
                workBuddyConnector,
                accountWebConnector,
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
        Task {
            await registry.startPassiveConnectors()
            guard claudeConsent.consentGranted else { return }
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
            workBuddySettings: settings,
            workBuddyLogin: login,
            workBuddyAccountWebSync: accountWebSync
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
            guard bundleIdentifier == "com.kevinchen.CodexUsageMonitor",
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
            "com.kevinchen.CodexUsageMonitor.m2wdbg."
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
            "com.kevinchen.CodexUsageMonitor.m2wdbg."
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
        guard bundleIdentifier == "com.kevinchen.CodexUsageMonitor",
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
