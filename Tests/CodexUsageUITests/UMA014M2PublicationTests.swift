import Foundation
import Testing
@testable import CodexUsageUI

struct UMA014M2PublicationTests {
    @Test
    func applicationSurfacesConsumeTheSharedProductInventoryBoundary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ relativePath: String) throws -> String {
            try String(
                contentsOf: root.appendingPathComponent(relativePath),
                encoding: .utf8
            )
        }

        let main = try source("Sources/CodexUsageMonitor/App/NativeShellViews.swift")
        let quick = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let shell = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        let status = try source("Sources/CodexUsageMonitor/App/StatusBarController.swift")
        let store = try source("Sources/CodexUsageUI/Stores/UsageStore.swift")

        // Narrowed deliberately. The contract is that every surface consumes
        // one shared inventory boundary instead of assembling its own list.
        // That boundary moved into the store when the list became something
        // the user can arrange: the surfaces now read the store's ordered
        // accessors, and the store is the single place that derives them from
        // the inventory. Asserting it this way is stricter than before — a
        // surface reading the raw accessor would bypass the arrangement, and
        // is now forbidden rather than merely unmentioned.
        #expect(main.contains("store.orderedWorkspaceProviders"))
        #expect(!main.contains("store.productInventory.agentWorkspaceProviders"))
        #expect(main.contains("ForEach(workspaceProviders)"))
        #expect(quick.contains("store.orderedQuickPanelProviders"))
        #expect(!quick.contains("store.productInventory.quickPanelProviders"))
        #expect(store.contains("productInventory.agentWorkspaceProviders"))
        #expect(store.contains("productInventory.quickPanelProviders"))
        #expect(quick.contains("AgentGlanceRow"))
        #expect(shell.contains("store.$productInventory"))
        // The status item reaches the inventory through the store's reading
        // publisher, which subscribes to `$productInventory` itself.
        #expect(status.contains("store.menuReadingPublisher"))
        #expect(store.contains("$productInventory"))
        #expect(!shell.contains("store.objectWillChange"))
        #expect(!status.contains("store?.objectWillChange"))
        #expect(store.contains("let subscription = await registry.subscribe()"))
        #expect(!store.contains("let stream = await registry.snapshots()"))
    }

    @Test
    func registryMulticastsCoherentRevisionsAndReplaysCurrentState() async throws {
        let connector = M2PublicationConnector()
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let first = await registry.subscribe()
        let second = await registry.subscribe()
        var firstIterator = first.updates.makeAsyncIterator()
        var secondIterator = second.updates.makeAsyncIterator()

        let firstInitial = try #require(await firstIterator.next())
        let secondInitial = try #require(await secondIterator.next())
        #expect(firstInitial == secondInitial)
        #expect(firstInitial.revision == 0)
        #expect(firstInitial.snapshots.isEmpty)
        #expect(await registry.publicationObserverCount() == 2)

        let admission = await registry.scanSurfaceAdmissions(trigger: .manualRefresh)
        let firstAdmitted = try #require(await firstIterator.next())
        let secondAdmitted = try #require(await secondIterator.next())

        #expect(firstAdmitted == secondAdmitted)
        #expect(firstAdmitted.revision == 1)
        #expect(firstAdmitted.snapshots == admission.admittedSnapshots)
        #expect(firstAdmitted.admissionSet == admission)

        await registry.detach(first)
        #expect(await registry.publicationObserverCount() == 1)

        let refreshed = Self.snapshot(remainingPercent: 61)
        await connector.replaceSnapshot(refreshed)
        try await registry.refresh(M2PublicationConnector.connectorID)
        let secondRefreshed = try #require(await secondIterator.next())
        #expect(secondRefreshed.revision == 2)
        #expect(secondRefreshed.snapshots.first?.channels.first?
            .rateLimitWindows.first?.normalizedRemainingPercent == 61)

        let late = await registry.subscribe()
        var lateIterator = late.updates.makeAsyncIterator()
        #expect(await lateIterator.next() == secondRefreshed)

        await registry.detach(first)
        await registry.detach(second)
        await registry.detach(late)
        await registry.stopAll()
        #expect(await registry.publicationObserverCount() == 0)
    }

    @Test
    func stoppedRegistryPublishesOneEmptyCoherentRevisionToEverySubscriber() async throws {
        let registry = try AgentConnectorRegistry(connectors: [M2PublicationConnector()])
        let first = await registry.subscribe()
        let second = await registry.subscribe()
        var firstIterator = first.updates.makeAsyncIterator()
        var secondIterator = second.updates.makeAsyncIterator()
        _ = await firstIterator.next()
        _ = await secondIterator.next()
        _ = await registry.scanSurfaceAdmissions(trigger: .manualRefresh)
        _ = await firstIterator.next()
        _ = await secondIterator.next()

        await registry.stopAll()
        let firstStopped = try #require(await firstIterator.next())
        let secondStopped = try #require(await secondIterator.next())

        #expect(firstStopped == secondStopped)
        #expect(firstStopped.snapshots.isEmpty)
        #expect(firstStopped.admissionSet == nil)
        #expect(await registry.publicationObserverCount() == 2)

        await registry.detach(first)
        await registry.detach(second)
    }

    fileprivate static func snapshot(remainingPercent: Double) -> AgentUsageSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_788_134_400)
        return AgentUsageSnapshot(
            id: M2PublicationConnector.connectorID,
            providerName: "Fixture",
            state: .ready,
            capturedAt: capturedAt,
            lastSuccessfulAt: capturedAt,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialStructuredHook,
                    sourceVersion: "v1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: capturedAt,
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: "five-hour",
                            kind: .fiveHour,
                            usedPercent: 100 - remainingPercent,
                            isEstimated: false,
                            isUnlimited: false,
                            resetsAt: capturedAt.addingTimeInterval(3_600)
                        )
                    ],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                )
            ],
            capabilities: [.connect, .refresh, .disconnect],
            safeFailure: nil
        )
    }
}

private actor M2PublicationConnector: AgentUsageConnector {
    static let connectorID = AgentConnectorID(rawValue: "m2.publication.fixture")!

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "Fixture",
        officialSource: "fixture",
        sourceTier: .officialStructuredHook,
        sourceVersion: "v1",
        supportedScopes: [.account],
        capabilities: [.connect, .refresh, .disconnect],
        configurationRequirements: [],
        privacyAllowlist: ["remaining percentage"],
        supportsRestore: false,
        supportsUninstall: true,
        unsupportedFields: ["identity"]
    )!

    private var snapshot = UMA014M2PublicationTests.snapshot(remainingPercent: 72)
    func probe() async -> AgentConnectorProbe {
        AgentConnectorProbe(state: .ready, safeFailure: nil)
    }

    func start() async {}
    func refresh() async {}
    func perform(_ command: AgentConnectorCommand) async {}
    func stop() async {}
    func currentSnapshot() async -> AgentUsageSnapshot { snapshot }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { _ in }
    }

    func replaceSnapshot(_ next: AgentUsageSnapshot) {
        snapshot = next
    }
}
