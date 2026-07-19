import AppKit
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
            configurationRequirements: [],
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

    @Test
    func persistedSnapshotsFailClosedOnCorruptionAndRecoverFromAtomicBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("connector-snapshots.json")
        let store = AgentConnectorSnapshotStore(url: url)
        try await store.save([Self.snapshot(id: "alpha.agent", state: .ready, failure: nil)])
        try await store.save([Self.snapshot(id: "zeta.agent", state: .ready, failure: nil)])

        try Data("not-json".utf8).write(to: url, options: .atomic)
        #expect((await store.load()).map(\.id.rawValue) == ["alpha.agent"])

        try Data("still-not-json".utf8).write(to: url.appendingPathExtension("backup"), options: .atomic)
        #expect(await store.load().isEmpty)
    }

    @Test
    func persistenceMigratesSchemaZeroOnlyWhenTheSnapshotIsNextSaved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("connector-snapshots.json")
        let store = AgentConnectorSnapshotStore(url: url)
        let snapshot = Self.snapshot(id: "alpha.agent", state: .ready, failure: nil)
        try await store.save([snapshot])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let saved = try decoder.decode(AgentConnectorSnapshotStore.Envelope.self, from: Data(contentsOf: url))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let legacy = AgentConnectorSnapshotStore.Envelope(schemaVersion: 0, entries: saved.entries)
        try encoder.encode(legacy).write(to: url, options: .atomic)

        #expect((await store.load()).map(\.id.rawValue) == ["alpha.agent"])
        let beforeResave = try decoder.decode(AgentConnectorSnapshotStore.Envelope.self, from: Data(contentsOf: url))
        #expect(beforeResave.schemaVersion == 0)

        try await store.save([snapshot])
        let migrated = try decoder.decode(AgentConnectorSnapshotStore.Envelope.self, from: Data(contentsOf: url))
        #expect(migrated.schemaVersion == AgentConnectorSnapshotStore.schemaVersion)
    }

    @Test
    func registryDeliversIndependentEventsAndStopsEveryOwnedConnector() async throws {
        let alpha = TestConnector(id: "alpha.agent", snapshot: Self.snapshot(id: "alpha.agent", state: .ready, failure: nil))
        let zeta = TestConnector(id: "zeta.agent", snapshot: Self.snapshot(id: "zeta.agent", state: .ready, failure: nil))
        let registry = try AgentConnectorRegistry(connectors: [zeta, alpha])
        await registry.startAll()

        for _ in 0..<10 {
            if await zeta.hasListener { break }
            await Task.yield()
        }
        #expect(await zeta.hasListener)

        await zeta.emit(Self.snapshot(id: "zeta.agent", state: .failed, failure: .processExited))
        for _ in 0..<10 {
            if (await registry.orderedSnapshots().first(where: { $0.id.rawValue == "zeta.agent" })?.safeFailure) == .processExited { break }
            await Task.yield()
        }
        let snapshots = await registry.orderedSnapshots()
        #expect(snapshots.map(\.id.rawValue) == ["alpha.agent", "zeta.agent"])
        #expect(snapshots.first(where: { $0.id.rawValue == "alpha.agent" })?.hasValidData == true)
        #expect(snapshots.first(where: { $0.id.rawValue == "zeta.agent" })?.safeFailure == .processExited)

        await registry.stopAll()
        #expect(await alpha.stopCount == 1)
        #expect(await zeta.stopCount == 1)
    }

    @Test
    func snapshotContractRetainsScopeAndProvenanceWithoutPrivateIdentitySerialization() throws {
        let snapshot = Self.snapshot(id: "alpha.agent", state: .ready, failure: nil)
        let account = try #require(snapshot.channels.first(where: { $0.id == .account }))
        let local = try #require(snapshot.channels.first(where: { $0.id == .localActivity }))
        #expect(account.scopes == [.account])
        #expect(account.provenance == .providerReported)
        #expect(local.scopes == [.device, .session])
        #expect(local.provenance == .locallyEstimated)
        #expect(account.accountMetrics?.planLabel == "PRO")
        #expect(local.localActivityMetrics?.estimatedSevenDayUSD == 1.25)

        let encoded = try JSONEncoder().encode(snapshot)
        let serialized = String(decoding: encoded, as: UTF8.self)
        #expect(!serialized.contains("email"))
        #expect(!serialized.contains("cookie"))
        #expect(!serialized.contains("token"))
    }

    @Test
    func refreshRecreatesOnlyAnExitedOwnedProcessOnce() async throws {
        let client = ProcessExitThenRecoveryClient(results: [
            .success(Self.liveUsage),
            .failure(CodexUsageClientError(.processExited)),
            .success(Self.liveUsage)
        ])
        let connector = CodexUsageConnector(client: client, localActivityReader: UnavailableLocalReader())

        await connector.perform(.connect)
        #expect((await connector.currentSnapshot()).state == .ready)

        await connector.refresh()
        let recovered = await connector.currentSnapshot()
        #expect(recovered.state == .ready)
        #expect(recovered.channels.first(where: { $0.id == .account })?.freshness == .fresh)
        #expect(await client.fetchCount == 3)
        #expect(await client.disconnectCount == 1)
    }

    @Test
    func adapterPreservesG1UnlimitedFiveHourWhenOnlyWeeklyWindowIsReported() async throws {
        let weeklyOnly = CodexLiveUsage(
            rateLimits: .init(
                planType: "PRO",
                windows: [.init(id: "weekly", usedPercent: 24, windowDurationMinutes: 10_080, resetsAt: nil)]
            ),
            availableResetCount: nil,
            lifetimeTokens: nil,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        )
        let client = ProcessExitThenRecoveryClient(results: [.success(weeklyOnly)])
        let connector = CodexUsageConnector(client: client, localActivityReader: UnavailableLocalReader())

        await connector.perform(.connect)
        let account = try #require((await connector.currentSnapshot()).channels.first(where: { $0.id == .account }))
        #expect(account.rateLimitWindows.map(\.kind) == [.fiveHour, .sevenDay])
        #expect(account.rateLimitWindows.first?.isUnlimited == true)
        #expect(account.rateLimitWindows.first?.usedPercent == nil)
    }

    @Test @MainActor
    func compactMenuPercentSkipsAnAuthoritativeUnlimitedFiveHourWindow() async throws {
        let usage = CodexLiveUsage(
            rateLimits: .init(
                planType: "PRO",
                windows: [
                    .init(
                        id: "five-hour-unlimited",
                        creditsUnlimited: true,
                        usedPercent: 0,
                        windowDurationMinutes: 300,
                        resetsAt: nil
                    ),
                    .init(
                        id: "seven-day",
                        usedPercent: 27,
                        windowDurationMinutes: 10_080,
                        resetsAt: nil
                    )
                ],
                creditsUnlimited: true
            ),
            availableResetCount: nil,
            lifetimeTokens: 100,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        )
        let client = EventRecordingClient(usage: usage)
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: AgentUsageRuntime.makeCodexRegistry(
                snapshotStore: nil,
                client: client,
                localActivityReader: UnavailableLocalReader()
            ),
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: UserDefaults(suiteName: "m1a-g2-dbg-b-menu-\(UUID().uuidString)")
        )

        store.grantMonitorConsent()
        await store.connectToLocalSession()

        #expect(store.snapshot.periods.last?.isUnlimited == true)
        #expect(store.menuPercent == 73)
        await store.stopAllConnectors()
    }

    @Test
    func providerNotificationUsesTheSingleCoalescedProviderEventLane() async throws {
        let client = EventRecordingClient(usage: Self.liveUsage)
        let connector = CodexUsageConnector(client: client, localActivityReader: UnavailableLocalReader())

        await connector.start()
        for _ in 0..<30 where !(await client.hasEventListener) {
            await Task.yield()
        }
        #expect(await client.hasEventListener)

        await connector.perform(.connect)
        #expect(await client.verifiedFetchCount == 1)

        await client.emit(.rateLimitsUpdated)
        for _ in 0..<30 where !(await client.triggers.contains(.providerEvent)) {
            await Task.yield()
        }
        #expect(await client.triggers == [.providerEvent])
        #expect((await connector.currentSnapshot()).state == .ready)

        await connector.stop()
        #expect(await client.disconnectCount == 1)
    }

    @Test @MainActor
    func adaptiveRefreshUsesVisibleCadenceThenAConservativeBackgroundFallback() async throws {
        let client = EventRecordingClient(usage: Self.liveUsage)
        let registry = AgentUsageRuntime.makeCodexRegistry(
            snapshotStore: nil,
            client: client,
            localActivityReader: UnavailableLocalReader()
        )
        let store = UsageStore(
            autoRefresh: true,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: UserDefaults(suiteName: "m1a-g2-dbg-b-cadence-\(UUID().uuidString)"),
            visibleRefreshInterval: .milliseconds(10),
            backgroundRefreshInterval: .milliseconds(70)
        )
        store.grantMonitorConsent()
        await store.refresh()
        store.setPanelVisible(true)

        for _ in 0..<50 where !(await client.triggers.contains(.timer)) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await client.triggers.contains(.timer))

        store.setPanelVisible(false)
        let timerCountAtBackgroundTransition = await client.timerTriggerCount
        try? await Task.sleep(for: .milliseconds(25))
        #expect(await client.timerTriggerCount == timerCountAtBackgroundTransition)

        for _ in 0..<30 where (await client.timerTriggerCount) == timerCountAtBackgroundTransition {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(await client.timerTriggerCount > timerCountAtBackgroundTransition)
        await store.stopAllConnectors()
    }

    @Test @MainActor
    func workspaceWakeUsesTheExistingWakeRefreshLane() async throws {
        let client = EventRecordingClient(usage: Self.liveUsage)
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: AgentUsageRuntime.makeCodexRegistry(
                snapshotStore: nil,
                client: client,
                localActivityReader: UnavailableLocalReader()
            ),
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: UserDefaults(suiteName: "m1a-g2-dbg-b-wake-\(UUID().uuidString)")
        )
        store.grantMonitorConsent()
        let wakeObserver = CodexWakeRefreshObserver(store: store)
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)

        for _ in 0..<30 where !(await client.triggers.contains(.wake)) {
            await Task.yield()
        }
        #expect(await client.triggers == [.wake])
        wakeObserver.invalidate()
        await store.stopAllConnectors()
    }

    /// Opt-in only: the Goal runner supplies the managed HOME for one
    /// bounded account-first connect and one explicit refresh. It emits only
    /// booleans/counts, never an account object or raw protocol payload.
    @Test
    func authorizedLiveRegistryCodexAdapterRetainsOneConnectorAndRecoversOnRefresh() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["M1A_G2_LIVE_EVIDENCE"] == "1",
              let realHome = environment["M1A_G2_REAL_HOME"],
              let evidencePath = environment["M1A_G2_LIVE_EVIDENCE_PATH"]
        else { return }

        let session = CodexAppServerSession(
            transportFactory: {
                ProcessCodexAppServerTransport(launchConfiguration: .init(homeDirectory: realHome))
            }
        )
        let client = CodexAppServerClient(session: session)
        let registry = AgentUsageRuntime.makeCodexRegistry(
            snapshotStore: nil,
            client: client,
            localActivityReader: UnavailableLocalReader()
        )
        let connectorID = CodexUsageConnector.connectorID
        #expect((await registry.orderedDescriptors()).map(\.id) == [connectorID])

        do {
            await registry.startAll()
            try await registry.perform(.connect, for: connectorID)
            let initial = try #require(await registry.orderedSnapshots().first)
            #expect(initial.state == .ready)
            #expect(initial.channels.first(where: { $0.id == .account })?.freshness == .fresh)
            #expect(initial.channels.first(where: { $0.id == .account })?.accountMetrics != nil)

            try await registry.perform(.refresh, for: connectorID)
            let refreshed = try #require(await registry.orderedSnapshots().first)
            #expect(refreshed.state == .ready)
            #expect(refreshed.channels.first(where: { $0.id == .account })?.freshness == .fresh)

            let evidence: [String: Any] = [
                "probe": "m1a-g2-live-registry-adapter",
                "connector_count": 1,
                "initial_account_fresh": initial.channels.first(where: { $0.id == .account })?.freshness == .fresh,
                "refreshed_account_fresh": refreshed.channels.first(where: { $0.id == .account })?.freshness == .fresh,
                "account_metrics_present": refreshed.channels.first(where: { $0.id == .account })?.accountMetrics != nil,
                "raw_response_persisted": false,
            ]
            let url = URL(fileURLWithPath: evidencePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]).write(to: url, options: .atomic)
        } catch {
            await registry.stopAll()
            throw error
        }
        await registry.stopAll()
        #expect(await client.connectionState() == .idle)
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

    private static let liveUsage = CodexLiveUsage(
        rateLimits: .init(
            planType: "PRO",
            windows: [.init(id: "five-hour", usedPercent: 20, windowDurationMinutes: 300, resetsAt: nil)]
        ),
        availableResetCount: nil,
        lifetimeTokens: 100,
        dailyUsage: nil,
        recentActivityCount: 0,
        apiCostEstimate: nil
    )
}

private struct UnavailableLocalReader: CodexLocalActivityReading {
    func read(now: Date) -> CodexLocalActivitySnapshot { .unavailable(now: now) }
}

private actor ProcessExitThenRecoveryClient: CodexUsageClient {
    private var results: [Result<CodexLiveUsage, Error>]
    private(set) var fetchCount = 0
    private(set) var disconnectCount = 0

    init(results: [Result<CodexLiveUsage, Error>]) { self.results = results }

    func checkLocalAccountAvailability() async throws -> Bool { true }
    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage { try nextUsage() }
    func fetchUsage() async throws -> CodexLiveUsage { try nextUsage() }
    func disconnect() async { disconnectCount += 1 }
    func takeUsageRefreshRequest() async -> Bool { false }
    func connectionState() async -> CodexConnectionState { .idle }
    func supportsOwnedProcessRecovery() async -> Bool { true }

    private func nextUsage() throws -> CodexLiveUsage {
        fetchCount += 1
        guard !results.isEmpty else { throw CodexUsageClientError(.unknownSafeError) }
        return try results.removeFirst().get()
    }
}

private actor EventRecordingClient: CodexUsageClient {
    private let usage: CodexLiveUsage
    private var eventContinuation: AsyncStream<CodexAppServerEvent>.Continuation?
    private(set) var verifiedFetchCount = 0
    private(set) var disconnectCount = 0
    private(set) var triggers: [CodexRefreshTrigger] = []

    init(usage: CodexLiveUsage) {
        self.usage = usage
    }

    var hasEventListener: Bool { eventContinuation != nil }
    var timerTriggerCount: Int { triggers.filter { $0 == .timer }.count }

    func checkLocalAccountAvailability() async throws -> Bool { true }

    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage {
        verifiedFetchCount += 1
        return usage
    }

    func fetchUsage() async throws -> CodexLiveUsage {
        triggers.append(.manual)
        return usage
    }

    func fetchUsage(trigger: CodexRefreshTrigger) async throws -> CodexLiveUsage {
        triggers.append(trigger)
        return usage
    }

    func disconnect() async {
        disconnectCount += 1
        eventContinuation?.finish()
        eventContinuation = nil
    }

    func takeUsageRefreshRequest() async -> Bool { false }

    func eventStream() async -> AsyncStream<CodexAppServerEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.eventContinuation?.finish()
            self.eventContinuation = continuation
        }
    }

    func connectionState() async -> CodexConnectionState { .idle }

    func emit(_ event: CodexAppServerEvent) {
        eventContinuation?.yield(event)
    }
}

private actor TestConnector: AgentUsageConnector {
    nonisolated let id: AgentConnectorID
    nonisolated let descriptor: AgentConnectorDescriptor
    private var snapshot: AgentUsageSnapshot
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private(set) var stopCount = 0

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
            configurationRequirements: [.userAuthorization],
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
    func stop() async {
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }
    func currentSnapshot() async -> AgentUsageSnapshot { snapshot }
    func emit(_ next: AgentUsageSnapshot) {
        snapshot = next
        continuation?.yield(next)
    }
    var hasListener: Bool { continuation != nil }
    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(snapshot)
        }
    }
}
