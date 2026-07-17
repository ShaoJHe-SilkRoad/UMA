import Foundation

/// Composition root for the built-in providers. Adding a future connector
/// changes this registration list, not the shared store, UI, or Codex files.
enum AgentUsageRuntime {
    static func makeCodexRegistry(
        snapshotStore: AgentConnectorSnapshotStore? = AgentConnectorSnapshotStore(),
        client: any CodexUsageClient = CodexAppServerClient(),
        localActivityReader: any CodexLocalActivityReading = CodexLocalActivityReader()
    ) -> AgentConnectorRegistry {
        let connector = CodexUsageConnector(client: client, localActivityReader: localActivityReader)
        // The composition is static and internally controlled, so duplicate
        // registration here is a programmer error rather than runtime input.
        return try! AgentConnectorRegistry(connectors: [connector], snapshotStore: snapshotStore)
    }
}
