import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5-A registry transition ownership", .timeLimit(.minutes(1)))
struct UMA014M5ARegistryConcurrencyTests {
    @Test(arguments: [false, true])
    func rapidReopenWaitsForSuspensionStop(blockBeforeStopRead: Bool) async throws {
        let resumeProgressed = M5AEventCounter()
        let connector = RegistryInterleavingConnector()
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            onResumeWaitingForStop: { resumeProgressed.signal() }
        )
        let admitted = await registry.scanSurfaceAdmissions(trigger: .manualRefresh)
        #expect(admitted.admittedProviderIDs == [connector.id])
        await connector.armSuspensionBoundary(beforeStopRead: blockBeforeStopRead)
        let pause = Task { await registry.suspendAllPreservingState() }
        await connector.suspensionBoundaryEntered.wait()
        let reopen = Task {
            await registry.resumeCurrentAdmissions()
            resumeProgressed.signal()
        }
        // Old behavior reaches start while the stop/read remains held; the
        // repaired path instead reports that it joined the owned suspension.
        await resumeProgressed.wait()
        connector.suspensionBoundaryReleased.signal()
        await pause.value
        await reopen.value

        #expect(await connector.lifecycleEvents == ["start", "stop", "start"])
        #expect(await connector.activeSessions == 1)
        #expect(await connector.maximumSessions == 1)
        #expect((await registry.orderedSnapshots()).count == 1)
        await registry.stopAll()
        await connector.finishAllStreams()
    }

    @Test
    func closeAfterReopenOwnsFreshSuspensionBeforeOriginalCallerReturns() async throws {
        let connector = RegistryInterleavingConnector()
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            afterSuspensionWait: { await connector.holdFirstSuspensionWait() }
        )
        _ = await registry.scanSurfaceAdmissions(trigger: .manualRefresh)
        let firstClose = Task { await registry.suspendAllPreservingState() }
        // The actual stop is complete, but its original caller cannot yet
        // return. Cleanup must belong to the transition, not that caller.
        await connector.firstSuspensionWaitEntered.wait()
        await connector.blockNextStartCompletion()
        let reopen = Task { await registry.resumeCurrentAdmissions() }
        await connector.startCompletionEntered.wait()
        await registry.suspendAllPreservingState()
        #expect(await connector.lifecycleEvents == ["start", "stop", "start", "stop"])
        #expect(await connector.activeSessions == 0)
        connector.startCompletionReleased.signal()
        connector.firstSuspensionWaitReleased.signal()
        await reopen.value
        await firstClose.value
        #expect(await connector.activeSessions == 0)
        await registry.stopAll()
        await connector.finishAllStreams()
    }

    @Test
    func concurrentRefreshesShareOnePendingSnapshotSubscription() async throws {
        let secondProgressed = M5AEventCounter()
        let connector = RegistryInterleavingConnector(secondSubscriptionStarted: secondProgressed)
        await connector.blockSubscriptionAcquisition()
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            onListenerReservationJoin: { secondProgressed.signal() }
        )
        let first = Task { try await registry.refresh(connector.id) }
        await connector.subscriptionEntered.wait()
        let second = Task { try await registry.refresh(connector.id) }
        // This is signalled by a second actual acquisition in the old code,
        // or by joining the first reserved acquisition after the repair.
        await secondProgressed.wait()
        connector.subscriptionReleased.signal()
        try await first.value
        try await second.value

        #expect(await connector.subscriptionCount == 1)
        #expect(await connector.maximumObservers == 1)
        #expect(await connector.refreshCount == 2)
        await registry.stopAll()
        await connector.subscriptionTerminated.wait()
        #expect(await connector.observerCount == 0)
        await connector.finishAllStreams()
    }
}

private actor RegistryInterleavingConnector: AgentUsageConnector {
    static let connectorID = AgentConnectorID(rawValue: "m5a.registry.fixture")!
    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "Fixture",
        officialSource: "isolated fixture",
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
    nonisolated let suspensionBoundaryEntered = M5AEventCounter()
    nonisolated let suspensionBoundaryReleased = M5AEventCounter()
    nonisolated let subscriptionEntered = M5AEventCounter()
    nonisolated let subscriptionReleased = M5AEventCounter()
    nonisolated let subscriptionTerminated = M5AEventCounter()
    private let secondSubscriptionStarted: M5AEventCounter?
    nonisolated let firstSuspensionWaitEntered = M5AEventCounter()
    nonisolated let firstSuspensionWaitReleased = M5AEventCounter()
    nonisolated let startCompletionEntered = M5AEventCounter()
    nonisolated let startCompletionReleased = M5AEventCounter()
    private var suspensionWaitCount = 0
    private var blocksNextStartCompletion = false
    private var blockStopRead = false
    private var blockStopCompletion = false
    private var blocksSubscription = false
    private var continuations: [UUID: AsyncStream<AgentUsageSnapshot>.Continuation] = [:]
    private(set) var lifecycleEvents: [String] = []
    private(set) var activeSessions = 0
    private(set) var maximumSessions = 0
    private(set) var subscriptionCount = 0
    private(set) var maximumObservers = 0
    private(set) var refreshCount = 0
    var observerCount: Int { continuations.count }

    init(secondSubscriptionStarted: M5AEventCounter? = nil) {
        self.secondSubscriptionStarted = secondSubscriptionStarted
    }

    func armSuspensionBoundary(beforeStopRead: Bool) {
        blockStopRead = beforeStopRead
        blockStopCompletion = !beforeStopRead
    }

    func blockSubscriptionAcquisition() { blocksSubscription = true }
    func blockNextStartCompletion() { blocksNextStartCompletion = true }
    func holdFirstSuspensionWait() async {
        suspensionWaitCount += 1
        guard suspensionWaitCount == 1 else { return }
        firstSuspensionWaitEntered.signal()
        await firstSuspensionWaitReleased.wait()
    }

    func probe() async -> AgentConnectorProbe { .init(state: .ready, safeFailure: nil) }
    func start() async {
        lifecycleEvents.append("start")
        activeSessions += 1
        maximumSessions = max(maximumSessions, activeSessions)
        if blocksNextStartCompletion {
            blocksNextStartCompletion = false
            startCompletionEntered.signal()
            await startCompletionReleased.wait()
        }
    }
    func refresh() async { refreshCount += 1 }
    func perform(_ command: AgentConnectorCommand) async { }
    func stop() async {
        if blockStopCompletion {
            blockStopCompletion = false
            suspensionBoundaryEntered.signal()
            await suspensionBoundaryReleased.wait()
        }
        lifecycleEvents.append("stop")
        activeSessions = 0
        // Streams belong to subscribers; transport stop must not substitute
        // for cancellation of an orphaned registry consumer.
    }
    func currentSnapshot() async -> AgentUsageSnapshot {
        if blockStopRead {
            blockStopRead = false
            suspensionBoundaryEntered.signal()
            await suspensionBoundaryReleased.wait()
        }
        return fixtureSnapshot
    }
    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        subscriptionCount += 1
        subscriptionEntered.signal()
        if subscriptionCount == 2 { secondSubscriptionStarted?.signal() }
        if blocksSubscription { await subscriptionReleased.wait() }
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[token] = continuation
            maximumObservers = max(maximumObservers, continuations.count)
            continuation.yield(fixtureSnapshot)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.terminated(token) }
            }
        }
    }
    private func terminated(_ token: UUID) {
        continuations[token] = nil
        subscriptionTerminated.signal()
    }
    func finishAllStreams() {
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }
    private var fixtureSnapshot: AgentUsageSnapshot {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return AgentUsageSnapshot(
            id: id, providerName: "Fixture", state: .ready,
            capturedAt: date, lastSuccessfulAt: date, freshness: .fresh,
            channels: [AgentUsageChannel(
                id: .account, sourceTier: .officialStructuredHook,
                sourceVersion: "v1", scopes: [.account], provenance: .providerReported,
                freshness: .fresh, capturedAt: date, coverageNote: nil,
                rateLimitWindows: [.init(
                    id: "five-hour", kind: .fiveHour, usedPercent: 28,
                    isUnlimited: false, resetsAt: nil
                )],
                accountMetrics: nil, localActivityMetrics: nil, safeFailure: nil
            )], capabilities: [.connect, .refresh, .disconnect], safeFailure: nil
        )
    }
}
