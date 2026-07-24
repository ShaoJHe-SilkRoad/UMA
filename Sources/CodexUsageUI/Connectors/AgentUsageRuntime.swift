import Foundation

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

    public static func live() -> UsageMonitorRuntime {
        let manualStore = WorkBuddyManualAvailabilityStore()
        let manualSource = ManualWorkBuddyAvailabilitySource(store: manualStore)
        let workBuddyConnector = WorkBuddyAvailabilityConnector(source: manualSource)
        let registry = AgentUsageRuntime.makeCodexRegistry(
            additionalConnectors: [workBuddyConnector]
        )
        let usageStore = UsageStore(
            registry: registry,
            primaryConnectorID: CodexUsageConnector.connectorID
        )
        let settings = WorkBuddySettingsModel(source: manualSource)
        return UsageMonitorRuntime(store: usageStore, workBuddySettings: settings)
    }
}
