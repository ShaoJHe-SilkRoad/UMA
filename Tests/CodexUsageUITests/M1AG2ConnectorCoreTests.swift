import Foundation
import Testing
@testable import CodexUsageUI

struct M1AG2ConnectorCoreTests {
    @Test
    func registryOrdersConnectorsAndKeepsAHealthyProviderWhenAnotherFails() async throws {
        let healthy = TestConnector(id: "alpha.agent", snapshot: Self.snapshot(id: "alpha.agent", state: .ready, failure: nil))
        let failed = TestConnector(id: "zeta.agent", snapshot: Self.snapshot(id: "zeta.agent", state: .failed, failure: .unavailable))
        let registry = try AgentConnectorRegistry(connectors: [failed, healthy])

        await registry.startAll()
        let snapshots = await registry.orderedSnapshots()

        #expect(snapshots.map(\.id.rawValue) == ["alpha.agent", "zeta.agent"])
        #expect(snapshots[0].hasValidData)
        #expect(snapshots[1].safeFailure == .unavailable)
    }

    @Test
    func registryRejectsDuplicateIDsAndUnsupportedDescriptors() async throws {
        let connector = TestConnector(id: "codex.local", snapshot: Self.snapshot(id: "codex.local", state: .inactive, failure: nil))
        let registry = try AgentConnectorRegistry(connectors: [connector])
        do {
            try await registry.register(connector)
            Issue.record("The registry accepted a duplicate connector ID")
        } catch let error as AgentConnectorRegistryError {
            #expect(error == .duplicateConnector(connector.id))
        }
        #expect(AgentConnectorDescriptor(
            id: AgentConnectorID(rawValue: "unsupported.agent")!,
            providerName: "Unsupported",
            officialSource: "fixture",
            sourceTier: .unsupported,
            sourceVersion: "v1",
            supportedScopes: [.account],
            capabilities: [],
            privacyAllowlist: [],
            supportsRestore: false,
            supportsUninstall: true,
            unsupportedFields: []
        ) == nil)
    }

    @Test
    func persistedSnapshotsRestoreAsStaleAndExcludeRuntimeTaskArrays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("connector-snapshots.json")
        let store = AgentConnectorSnapshotStore(url: url)
        let snapshot = Self.snapshot(id: "codex.local", state: .ready, failure: nil)

        try await store.save([snapshot])
        let serialized = try String(decoding: Data(contentsOf: url), as: UTF8.self)
        let restored = await store.load()

        #expect(!serialized.contains("recentTaskTokens"))
        #expect(!serialized.contains("recentTaskCapturedAt"))
        #expect(restored.count == 1)
        #expect(restored[0].state == .stale)
        #expect(restored[0].channels.first(where: { $0.id == .account })?.freshness == .stale)
        #expect(restored[0].channels.first(where: { $0.id == .localActivity })?.localActivityMetrics?.recentTaskTokens.isEmpty == true)
    }

    @Test
    func persistencePreservesUnknownProviderEntriesForLaterRestore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AgentConnectorSnapshotStore(url: directory.appendingPathComponent("connector-snapshots.json"))
        try await store.save([
            Self.snapshot(id: "alpha.agent", state: .ready, failure: nil),
            Self.snapshot(id: "zeta.agent", state: .ready, failure: nil)
        ])
        try await store.save([Self.snapshot(id: "alpha.agent", state: .ready, failure: nil)])

        #expect((await store.load()).map(\.id.rawValue) == ["alpha.agent", "zeta.agent"])
    }

    private static func snapshot(id rawID: String, state: AgentConnectorState, failure: AgentSafeFailure?) -> AgentUsageSnapshot {
        let now = Date(timeIntervalSince1970: 1_784_332_800)
        return AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: rawID)!,
            providerName: "Codex",
            state: state,
            capturedAt: now,
            lastSuccessfulAt: state == .ready ? now : nil,
            freshness: state == .ready ? .fresh : .unavailable,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialLocalService,
                    sourceVersion: "app-server",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: state == .ready ? .fresh : .unavailable,
                    capturedAt: now,
                    coverageNote: "not persisted",
                    rateLimitWindows: [.init(id: "five-hour", kind: .fiveHour, usedPercent: 25, isUnlimited: false, resetsAt: now)],
                    accountMetrics: .init(planLabel: "PRO", availableResets: 1, lifetimeTokens: 100, sevenDayTokens: 10),
                    localActivityMetrics: nil,
                    safeFailure: failure
                ),
                AgentUsageChannel(
                    id: .localActivity,
                    sourceTier: .officialCLIOrMetadata,
                    sourceVersion: "metadata-tail-v1",
                    scopes: [.device, .session],
                    provenance: .locallyEstimated,
                    freshness: .fresh,
                    capturedAt: now,
                    coverageNote: "never persisted",
                    rateLimitWindows: [],
                    accountMetrics: nil,
                    localActivityMetrics: .init(
                        recentTaskCount: 1,
                        recentTaskTokens: [777],
                        recentTaskCapturedAt: [now],
                        sessionTokens: 777,
                        estimatedSevenDayUSD: 1.25,
                        estimatedLifetimeUSD: 3.50,
                        coveragePercent: 100,
                        recognizedModelCount: 1
                    ),
                    safeFailure: nil
                )
            ],
            capabilities: [.connect, .refresh, .disconnect],
            safeFailure: failure
        )
    }
}

private actor TestConnector: AgentUsageConnector {
    nonisolated let id: AgentConnectorID
    nonisolated let descriptor: AgentConnectorDescriptor
    private var snapshot: AgentUsageSnapshot
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?

    init(id rawID: String, snapshot: AgentUsageSnapshot) {
        self.id = AgentConnectorID(rawValue: rawID)!
        self.snapshot = snapshot
        self.descriptor = AgentConnectorDescriptor(
            id: self.id,
            providerName: "Fixture",
            officialSource: "fixture",
            sourceTier: .officialStructuredHook,
            sourceVersion: "v1",
            supportedScopes: [.account],
            capabilities: [.connect, .refresh, .disconnect],
            privacyAllowlist: ["aggregate"],
            supportsRestore: true,
            supportsUninstall: true,
            unsupportedFields: ["raw"]
        )!
    }

    func probe() async -> AgentConnectorProbe { .init(state: snapshot.state, safeFailure: snapshot.safeFailure) }
    func start() async { continuation?.yield(snapshot) }
    func refresh() async { continuation?.yield(snapshot) }
    func perform(_ command: AgentConnectorCommand) async { continuation?.yield(snapshot) }
    func stop() async { continuation?.yield(snapshot) }
    func currentSnapshot() async -> AgentUsageSnapshot { snapshot }
    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(snapshot)
        }
    }
}
