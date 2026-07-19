import Foundation
import Testing
@testable import CodexUsageUI

struct M1AG2DBGP1FunctionalRepairTests {
    @Test
    func staleAccountChannelRemainsOverallStaleWhenLocalActivityIsFresh() async throws {
        let client = StaleAccountClient()
        let connector = CodexUsageConnector(
            client: client,
            localActivityReader: AvailableLocalReader()
        )

        await connector.perform(.connect)
        await connector.refresh()

        let snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .stale)
        #expect(snapshot.channels.first(where: { $0.id == .account })?.freshness == .stale)
        #expect(snapshot.channels.first(where: { $0.id == .localActivity })?.freshness == .fresh)
        #expect(snapshot.freshness == .stale)
    }

    @Test
    func reconnectKeepsReplacementEventObserverForTransportRecovery() async throws {
        let client = ReconnectEventClient()
        let connector = CodexUsageConnector(
            client: client,
            localActivityReader: AvailableLocalReader()
        )

        await connector.start()
        for _ in 0..<50 where await client.eventStreamCount < 1 {
            await Task.yield()
        }
        #expect(await client.eventStreamCount == 1)

        await connector.perform(.connect)
        await connector.perform(.reconnect)
        for _ in 0..<50 where await client.eventStreamCount < 2 {
            await Task.yield()
        }
        #expect(await client.eventStreamCount == 2)

        // Let the cancelled first consumer reach its delayed cleanup.  The
        // next invalidation must still be received by the replacement.
        for _ in 0..<50 { await Task.yield() }
        await client.emit(.transportRecovered)
        for _ in 0..<100 where !(await client.triggers.contains(.providerEvent)) {
            await Task.yield()
        }

        #expect(await client.triggers == [.providerEvent])
        #expect((await connector.currentSnapshot()).state == .ready)
        #expect((await connector.currentSnapshot()).freshness == .fresh)
        await connector.stop()
    }
}

private struct AvailableLocalReader: CodexLocalActivityReading {
    func read(now: Date) -> CodexLocalActivitySnapshot {
        CodexLocalActivitySnapshot(
            availability: .available,
            source: "fixture local metadata",
            scope: "metadata-only",
            capturedAt: now,
            discoveredFileCount: 1,
            readableFileCount: 1,
            excludedFileCount: 0,
            tasks: [.init(stableID: "fixture", modifiedAt: now, totalTokens: 1)],
            apiEquivalentCost: nil
        )
    }
}

private actor StaleAccountClient: CodexUsageClient {
    private var hasReturnedInitialUsage = false

    func checkLocalAccountAvailability() async throws -> Bool { true }

    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage {
        hasReturnedInitialUsage = true
        return fixtureUsage
    }

    func fetchUsage() async throws -> CodexLiveUsage {
        throw CodexUsageClientError(.processExited)
    }

    func fetchUsage(trigger: CodexRefreshTrigger) async throws -> CodexLiveUsage {
        guard hasReturnedInitialUsage else { return fixtureUsage }
        throw CodexUsageClientError(.processExited)
    }

    func disconnect() async {}
    func takeUsageRefreshRequest() async -> Bool { false }
    func connectionState() async -> CodexConnectionState { .recoverableFailure(.processExited) }
}

private actor ReconnectEventClient: CodexUsageClient {
    private var continuation: AsyncStream<CodexAppServerEvent>.Continuation?
    private(set) var eventStreamCount = 0
    private(set) var triggers: [CodexRefreshTrigger] = []

    func checkLocalAccountAvailability() async throws -> Bool { true }

    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage {
        fixtureUsage
    }

    func fetchUsage() async throws -> CodexLiveUsage { fixtureUsage }

    func fetchUsage(trigger: CodexRefreshTrigger) async throws -> CodexLiveUsage {
        triggers.append(trigger)
        return fixtureUsage
    }

    func disconnect() async {
        continuation?.finish()
        continuation = nil
    }

    func takeUsageRefreshRequest() async -> Bool { false }

    func eventStream() async -> AsyncStream<CodexAppServerEvent> {
        eventStreamCount += 1
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
        }
    }

    func connectionState() async -> CodexConnectionState { .idle }

    func emit(_ event: CodexAppServerEvent) {
        continuation?.yield(event)
    }
}

private let fixtureUsage = CodexLiveUsage(
    rateLimits: .init(
        planType: "PRO",
        windows: [.init(id: "five-hour", usedPercent: 20, windowDurationMinutes: 300, resetsAt: nil)]
    ),
    availableResetCount: nil,
    lifetimeTokens: 1,
    dailyUsage: nil,
    recentActivityCount: 0,
    apiCostEstimate: nil,
    providerCapturedAt: Date(timeIntervalSince1970: 1_784_332_800)
)
