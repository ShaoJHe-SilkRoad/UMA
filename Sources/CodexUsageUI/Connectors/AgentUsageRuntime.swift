import Foundation

enum UsageMonitorRuntimeError: Error, Equatable {
    case invalidM2WDBGStoreConfiguration
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
    public let workBuddySettings: WorkBuddySettingsModel

    public static func live(
        workBuddyStoreURL: URL? = nil,
        snapshotStoreURL: URL? = nil
    ) -> UsageMonitorRuntime {
        let manualStore = workBuddyStoreURL.map {
            WorkBuddyManualAvailabilityStore(fileURL: $0)
        } ?? WorkBuddyManualAvailabilityStore()
        let manualSource = ManualWorkBuddyAvailabilitySource(store: manualStore)
        let workBuddyConnector = WorkBuddyAvailabilityConnector(source: manualSource)
        let registry = AgentUsageRuntime.makeCodexRegistry(
            snapshotStore: snapshotStoreURL.map { AgentConnectorSnapshotStore(url: $0) }
                ?? AgentConnectorSnapshotStore(),
            additionalConnectors: [workBuddyConnector]
        )
        let usageStore = UsageStore(
            registry: registry,
            primaryConnectorID: CodexUsageConnector.connectorID
        )
        let settings = WorkBuddySettingsModel(source: manualSource)
        return UsageMonitorRuntime(store: usageStore, workBuddySettings: settings)
    }

    /// Production uses the ordinary stores. A task-owned M2WDBG bundle must
    /// provide both valid isolated stores or startup fails before either
    /// ordinary user store is constructed.
    public static func live(
        bundleIdentifier: String?,
        environment: [String: String]
    ) throws -> UsageMonitorRuntime {
        try live(
            bundleIdentifier: bundleIdentifier,
            environment: environment,
            allowedRoot: URL(
                fileURLWithPath: "/private/tmp/uma-m2wdbg-runtime",
                isDirectory: true
            )
        )
    }

    static func live(
        bundleIdentifier: String?,
        environment: [String: String],
        allowedRoot: URL
    ) throws -> UsageMonitorRuntime {
        guard bundleIdentifier?.hasPrefix(
            "com.kevinchen.CodexUsageMonitor.m2wdbg."
        ) == true
        else {
            return live()
        }
        guard let workBuddyStoreURL = m2wdbgStoreURL(
            bundleIdentifier: bundleIdentifier,
            environment: environment,
            variable: "UMA_M2WDBG_MANUAL_STORE",
            allowedRoot: allowedRoot
        ),
              let snapshotStoreURL = m2wdbgStoreURL(
                bundleIdentifier: bundleIdentifier,
                environment: environment,
                variable: "UMA_M2WDBG_SNAPSHOT_STORE",
                allowedRoot: allowedRoot
              )
        else {
            throw UsageMonitorRuntimeError.invalidM2WDBGStoreConfiguration
        }
        return live(
            workBuddyStoreURL: workBuddyStoreURL,
            snapshotStoreURL: snapshotStoreURL
        )
    }

    /// A packaged debug candidate may opt into an isolated synthetic store.
    /// Production bundle identifiers and paths outside the task-owned root are
    /// deliberately ignored.
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
