import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M6-G2 Antigravity connector and scheduler")
struct M6G2AntigravityConnectorSchedulerTests {
    @Test
    func launchReadAndImmediateConnectCoalesceIntoOneRead() async {
        let reader = BlockingQuotaReader()
        let connector = makeConnector(reader: { try await reader.read() })

        await connector.start()
        let connect = Task { await connector.perform(.connect) }
        await waitUntil { await reader.count == 1 }
        await reader.release()
        await connect.value

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.completedReadCount == 1)
        #expect(await reader.maximumConcurrent == 1)
        await connector.stop()
    }

    @Test
    func concurrentManualRefreshesShareOneInFlightRead() async {
        let reader = BlockingQuotaReader()
        let connector = makeConnector(reader: { try await reader.read() })
        await connector.start()
        await waitUntil { await reader.count == 1 }
        await reader.release()
        await connector.perform(.connect)

        await reader.setBlocking(true)
        async let first: Void = connector.refresh()
        async let second: Void = connector.refresh(trigger: .timer)
        await waitUntil { await reader.count == 2 }
        await reader.release()
        _ = await (first, second)

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.completedReadCount == 2)
        #expect(diagnostics.coalescedReadCount >= 1)
        #expect(await reader.maximumConcurrent == 1)
        await connector.stop()
    }

    @Test
    func normalCadenceIsFiveMinutesAfterCompletion() async {
        let reader = CountingQuotaReader()
        let sleeper = RecordingSleeper(returnOnce: true)
        let connector = makeConnector(
            reader: { try await reader.read() },
            sleeper: { try await sleeper.sleep($0) }
        )
        await connector.start()
        await connector.perform(.connect)
        await waitUntil { await reader.count == 2 }

        #expect(await sleeper.intervals.first == 300)
        #expect(await reader.maximumConcurrent == 1)
        #expect((await connector.diagnostics()).scheduledCycleCount == 1)
        await connector.stop()
    }

    @Test
    func configuredCadenceCannotGoBelowThreeMinutes() async {
        let reader = CountingQuotaReader()
        let sleeper = RecordingSleeper(returnOnce: false)
        let connector = makeConnector(
            reader: { try await reader.read() },
            sleeper: { try await sleeper.sleep($0) },
            interval: 1
        )
        await connector.start()
        await connector.perform(.connect)
        await waitUntil { !(await sleeper.intervals).isEmpty }
        #expect(await sleeper.intervals.first == 180)
        await connector.stop()
    }

    @Test
    func authenticationFailureSuspendsSchedulerAndClearsQuota() async {
        let sleeper = RecordingSleeper(returnOnce: true)
        let connector = makeConnector(
            reader: { throw AntigravityCLIClientError.loginRequired },
            sleeper: { try await sleeper.sleep($0) }
        )
        await connector.start()
        await connector.perform(.connect)

        let snapshot = await connector.currentSnapshot()
        let diagnostics = await connector.diagnostics()
        #expect(snapshot.state == .authenticationRequired)
        #expect(snapshot.channels.isEmpty)
        #expect(diagnostics.automaticRefreshSuspended)
        #expect(!diagnostics.schedulerActive)
        #expect(await sleeper.intervals.isEmpty)
        await connector.stop()
    }

    @Test
    func autoRefreshOffAtDueTimeCanBeExplicitlyReenabled() async {
        let reader = CountingQuotaReader()
        let preference = MutableAutoRefreshPreference(false)
        let sleeper = RecordingSleeper(returnCount: 2)
        let connector = makeConnector(
            reader: { try await reader.read() },
            autoRefreshEnabled: { await preference.value },
            sleeper: { try await sleeper.sleep($0) }
        )

        await connector.start()
        await connector.perform(.connect)
        await waitUntil { !(await connector.diagnostics()).schedulerActive }
        #expect(await reader.count == 1)

        await preference.set(true)
        await connector.setAutomaticRefreshEnabled(true)
        await waitUntil { await reader.count == 2 }

        let intervals = await sleeper.intervals
        #expect(Array(intervals.prefix(2)) == [300, 300])
        #expect(await reader.maximumConcurrent == 1)
        await connector.stop()
    }

    @Test
    func missingExecutableHasAStableBoundedCapabilityClassification() async {
        let connector = makeConnector(
            reader: { quota() },
            verifier: { throw AntigravityCLIClientError.notInstalled }
        )

        let probe = await connector.probe()
        #expect(probe.state == .unsupported)
        #expect(probe.safeFailure == .unavailable)
        #expect((await connector.currentSnapshot()).channels.isEmpty)
    }

    @Test
    func transientFailureRetainsOnlySameSessionCachedOrStaleData() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let reader = SequenceQuotaReader(results: [
            .success(quota(at: clock.current)),
            .failure(.timedOut),
        ])
        let connector = makeConnector(
            reader: { try await reader.read() },
            now: { clock.current }
        )
        await connector.start()
        await connector.perform(.connect)
        clock.advance(by: 6 * 60)
        await connector.refresh()
        var snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .ready)
        #expect(snapshot.freshness == .cached)
        #expect(snapshot.safeFailure == .timedOut)
        #expect(snapshot.channels.first?.freshness == .cached)

        clock.advance(by: 30 * 60)
        snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .stale)
        #expect(snapshot.freshness == .stale)
        await connector.stop()
    }

    @Test
    func disconnectCancelsReadClearsStateAndScheduler() async {
        let connector = makeConnector(reader: {
            do {
                try await Task.sleep(for: .seconds(60))
                return quota()
            } catch {
                throw AntigravityCLIClientError.cancelled
            }
        })
        await connector.start()
        await Task.yield()
        await connector.perform(.disconnect)

        let snapshot = await connector.currentSnapshot()
        let diagnostics = await connector.diagnostics()
        #expect(snapshot.state == .inactive)
        #expect(snapshot.channels.isEmpty)
        #expect(!diagnostics.processReadInFlight)
        #expect(!diagnostics.schedulerActive)
    }

    @Test
    func descriptorIsProviderFourReadOnlyAndAssistantHidden() {
        let connector = makeConnector(reader: { quota() })
        let descriptor = connector.descriptor
        #expect(descriptor.id.rawValue == "antigravity.cli")
        #expect(descriptor.sourceTier == .officialCLIOrMetadata)
        #expect(descriptor.localSourceClass == .admittedStructuredLocal)
        #expect(descriptor.usageReadContract == .currentStructuredLocalRead)
        #expect(descriptor.authenticationMethod == .officialApplicationOwnedSession)
        #expect(!descriptor.supportsRestore)
        #expect(descriptor.capabilities.contains(.hiddenFromDesktopAssistant))
        #expect(descriptor.unsupportedFields.contains("credits"))
        #expect(AgentProviderOrder.priority(for: descriptor.id) == 250)
    }

    @Test
    func registryAndSettingsObserversReceiveTheSameSnapshot() async {
        let connector = makeConnector(reader: { quota() })
        let registryStream = await connector.snapshots()
        let settingsStream = await connector.snapshots()
        let registryObservation = Task { await nextReady(from: registryStream) }
        let settingsObservation = Task { await nextReady(from: settingsStream) }

        await connector.start()
        await connector.perform(.connect)

        #expect(await registryObservation.value?.state == .ready)
        #expect(await settingsObservation.value?.state == .ready)
        await connector.stop()
    }

    private func makeConnector(
        reader: @escaping GoogleAntigravityUsageConnector.QuotaReader,
        verifier: @escaping GoogleAntigravityUsageConnector.CapabilityVerifier = {},
        autoRefreshEnabled:
            @escaping GoogleAntigravityUsageConnector.PreferenceReader = { true },
        now: @escaping GoogleAntigravityUsageConnector.Now = Date.init,
        sleeper: @escaping GoogleAntigravityUsageConnector.Sleeper = { _ in
            throw CancellationError()
        },
        interval: TimeInterval = 300
    ) -> GoogleAntigravityUsageConnector {
        GoogleAntigravityUsageConnector(
            readQuota: reader,
            verifyCapability: verifier,
            autoRefreshEnabled: autoRefreshEnabled,
            now: now,
            sleep: sleeper,
            refreshInterval: interval
        )
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await predicate() { return }
            await Task.yield()
        }
        Issue.record("Condition was not reached")
    }

    private func nextReady(
        from stream: AsyncStream<AgentUsageSnapshot>
    ) async -> AgentUsageSnapshot? {
        for await snapshot in stream where snapshot.state == .ready {
            return snapshot
        }
        return nil
    }
}

private func quota(
    at date: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> AntigravityQuotaSnapshot {
    AntigravityQuotaSnapshot(
        buckets: [
            AntigravityQuotaBucket(
                id: "pool-a",
                displayLabel: "Primary",
                remainingPercent: 50,
                resetsAt: nil
            ),
        ],
        observedAt: date,
        sourceVersion: "agy-1.1.11"
    )
}

private actor BlockingQuotaReader {
    private(set) var count = 0
    private(set) var concurrent = 0
    private(set) var maximumConcurrent = 0
    private var blocking = true
    private var continuation: CheckedContinuation<Void, Never>?

    func read() async throws -> AntigravityQuotaSnapshot {
        count += 1
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        if blocking {
            await withCheckedContinuation { continuation = $0 }
        }
        concurrent -= 1
        return quota()
    }

    func release() {
        blocking = false
        continuation?.resume()
        continuation = nil
    }

    func setBlocking(_ value: Bool) {
        blocking = value
    }
}

private actor CountingQuotaReader {
    private(set) var count = 0
    private(set) var concurrent = 0
    private(set) var maximumConcurrent = 0

    func read() async throws -> AntigravityQuotaSnapshot {
        count += 1
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        await Task.yield()
        concurrent -= 1
        return quota()
    }
}

private actor SequenceQuotaReader {
    private var results: [Result<AntigravityQuotaSnapshot, AntigravityCLIClientError>]
    init(results: [Result<AntigravityQuotaSnapshot, AntigravityCLIClientError>]) {
        self.results = results
    }
    func read() async throws -> AntigravityQuotaSnapshot {
        guard !results.isEmpty else { throw AntigravityCLIClientError.providerUnavailable }
        return try results.removeFirst().get()
    }
}

private actor RecordingSleeper {
    private(set) var intervals: [TimeInterval] = []
    private var remainingReturns: Int
    init(returnOnce: Bool) { remainingReturns = returnOnce ? 1 : 0 }
    init(returnCount: Int) { remainingReturns = returnCount }

    func sleep(_ interval: TimeInterval) async throws {
        intervals.append(interval)
        if remainingReturns > 0 {
            remainingReturns -= 1
            return
        }
        throw CancellationError()
    }
}

private actor MutableAutoRefreshPreference {
    private(set) var value: Bool
    init(_ value: Bool) { self.value = value }
    func set(_ value: Bool) { self.value = value }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var current: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}
