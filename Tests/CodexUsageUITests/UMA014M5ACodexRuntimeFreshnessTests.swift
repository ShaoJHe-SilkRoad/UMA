import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.14 M5-A Codex runtime freshness", .timeLimit(.minutes(1)))
struct UMA014M5ACodexRuntimeFreshnessTests {
    @Test
    func queuedEventTaskCannotConsumeManualCommandsPendingRecovery() async throws {
        let gate = M5AProviderRefreshGate()
        let client = M5AActiveRecoveryClient()
        let connector = CodexUsageConnector(client: client, localActivityReader: M5ACodexEmptyReader(),
            beforeProviderRefresh: { await gate.wait() })
        let registry = try AgentConnectorRegistry(connectors: [connector], snapshotStore: nil)
        try await withTaskCancellationHandler {
            _ = await registry.scanSurfaceAdmissions(trigger: .applicationLaunch)
            await client.events.started.wait(for: 1)
            await client.events.send(.rateLimitsUpdated)
            await gate.started.wait(for: 1)
            let manual = Task { try await registry.refresh(connector.id) }
            await client.refreshStarted.wait(for: 1)
            await client.events.send(.transportRecovered)
            await client.events.consumed.wait(for: 2)
            await gate.release()
            await connector.awaitPendingProviderEventRefresh()
            await client.releaseInterruptedRead()
            try await manual.value
            #expect(await client.refreshCount == 2)
            #expect((await connector.currentSnapshot()).state == .ready)
            #expect(await registry.orderedSnapshots().count == 1)
            #expect(await client.disconnectCount == 0)
            await registry.stopAll()
        } onCancel: {
            Task { await gate.release(); await client.cancelFixture(); await registry.stopAll() }
        }
    }

    @Test(arguments: [false, true])
    func realSessionReplacementReasonSurvivesClientSanitization(transportAlreadyRestarted: Bool) async throws {
        let transport = M5ACodexTransport()
        let session = CodexAppServerSession(transportFactory: { transport })
        let client = CodexAppServerClient(resolver: M5ACodexResolver(), session: session,
            ownedProcessMonitorInterval: .seconds(3_600))
        _ = try await client.fetchUsage()
        await transport.readerWaiting.wait(for: 1)
        transport.holdNextRequest()
        let interrupted = Task { () -> Bool in
            do { _ = try await client.fetchUsage(); return false }
            catch is CodexTransportReplacementInterrupted { return true }
            catch { return false }
        }
        await transport.pendingRequestStarted.wait(for: 1)
        if transportAlreadyRestarted {
            transport.replaceWithoutOldEOF()
        } else {
            transport.exitWithoutOldEOF()
        }
        #expect(try await session.maintainTransportIfNeeded())
        #expect(await interrupted.value)
        #expect(transport.isRunning)
        transport.releaseOldEOF()
        _ = try await client.fetchUsage()
        #expect(await client.connectionState() == .ready)
        await client.disconnect()
    }

    @Test
    func unrelatedUnknownFailureRemainsTerminalDespitePendingRecovery() async throws {
        let client = M5AActiveRecoveryClient(replacementInterruption: false)
        let connector = CodexUsageConnector(client: client, localActivityReader: M5ACodexEmptyReader())
        let registry = try AgentConnectorRegistry(connectors: [connector], snapshotStore: nil)
        try await withTaskCancellationHandler {
            _ = await registry.scanSurfaceAdmissions(trigger: .applicationLaunch)
            await client.events.started.wait(for: 1)
            let oldRefresh = Task { try await registry.refresh(connector.id) }
            await client.refreshStarted.wait(for: 1)
            await client.events.send(.transportRecovered)
            await client.events.consumed.wait(for: 1)
            await client.releaseInterruptedRead()
            try await oldRefresh.value
            #expect(await client.refreshCount == 1)
            #expect(await registry.orderedSnapshots().isEmpty)
            await registry.stopAll()
        } onCancel: {
            Task { await client.cancelFixture(); await registry.stopAll() }
        }
    }

    @Test
    func eventTriggeredReadInterruptedBeforeRecoveryRetainsAdmissionAndThenRefreshes() async throws {
        let client = M5AActiveRecoveryClient()
        let connector = CodexUsageConnector(client: client, localActivityReader: M5ACodexEmptyReader())
        let registry = try AgentConnectorRegistry(connectors: [connector], snapshotStore: nil)
        try await withTaskCancellationHandler {
            do {
                let admission = await registry.scanSurfaceAdmissions(trigger: .applicationLaunch)
                #expect(admission.admittedProviderIDs == [connector.id])
                let publications = await registry.snapshots()
                var iterator = publications.makeAsyncIterator()
                await client.events.started.wait(for: 1)

                // The provider event starts this owned held read. No manual
                // refresh owns it, and recovery has not
                // yet been emitted when replacement interrupts the request.
                await client.events.send(.rateLimitsUpdated)
                await client.refreshStarted.wait(for: 1)
                await client.releaseInterruptedRead()

                var interruptedPublication: [AgentUsageSnapshot]?
                while let snapshots = await iterator.next() {
                    if snapshots.isEmpty || snapshots.first?.state == .stale {
                        interruptedPublication = snapshots
                        break
                    }
                }
                let interrupted = try #require(interruptedPublication)
                // Require retained admission before emitting recovery. Failure
                // ends the test promptly rather than waiting for a listener
                // which the broken path has already stopped.
                let retained = try #require(interrupted.first)
                #expect(retained.state == .stale)
                #expect(retained.safeFailure == .processExited)
                #expect(retained.lastSuccessfulAt == m5aCodexUsage.providerCapturedAt)
                #expect(await client.disconnectCount == 0)

                await client.events.send(.transportRecovered)
                var recovered: AgentUsageSnapshot?
                while let snapshots = await iterator.next() {
                    if let snapshot = snapshots.first, snapshot.state == .ready {
                        recovered = snapshot
                        break
                    }
                    if snapshots.isEmpty { break }
                }
                let current = try #require(recovered)
                #expect(current.freshness == .fresh)
                #expect(current.lastSuccessfulAt == m5aCodexUsage.providerCapturedAt.addingTimeInterval(900))
                #expect(await client.refreshCount == 2)
                #expect(await client.disconnectCount == 0)
                await registry.stopAll()
            } catch {
                await client.cancelFixture()
                await registry.stopAll()
                throw error
            }
        } onCancel: {
            Task {
                await client.cancelFixture()
                await registry.stopAll()
            }
        }
    }

    @Test(arguments: [false, true])
    func recoveredEventDuringActiveReadIsDrainedUnlessExplicitlyStopped(stopBeforeCompletion: Bool) async throws {
        let client = M5AActiveRecoveryClient()
        let connector = CodexUsageConnector(client: client, localActivityReader: M5ACodexEmptyReader())
        let registry = try AgentConnectorRegistry(connectors: [connector], snapshotStore: nil)
        try await withTaskCancellationHandler {
            let admission = await registry.scanSurfaceAdmissions(trigger: .applicationLaunch)
            #expect(admission.admittedProviderIDs == [connector.id])
            await client.events.started.wait(for: 1)
            let oldRefresh = Task { try await registry.refresh(connector.id) }
            await client.refreshStarted.wait(for: 1)

            await client.events.send(.transportUnavailable(.processExited))
            await client.events.consumed.wait(for: 1)
            #expect((await connector.currentSnapshot()).freshness == .stale)
            #expect((await connector.currentSnapshot()).lastSuccessfulAt == m5aCodexUsage.providerCapturedAt)
            // Each ACK is the consumer asking for its next event after handling
            // the prior one, so all recovered events hit the held active read.
            for count in 2...4 {
                await client.events.send(.transportRecovered)
                await client.events.consumed.wait(for: count)
            }
            if stopBeforeCompletion { try await registry.perform(.disconnect, for: connector.id) }
            await client.releaseInterruptedRead()
            try await oldRefresh.value

            if stopBeforeCompletion {
                #expect(await client.refreshCount == 1)
                #expect((await connector.currentSnapshot()).state == .inactive)
                #expect(await registry.orderedSnapshots().isEmpty)
            } else {
                // A missing recovery lane must fail immediately; do not await an
                // event that the unfixed implementation never schedules.
                #expect(await client.refreshCount == 2)
                let recovered = await connector.currentSnapshot()
                #expect(recovered.state == .ready)
                #expect(recovered.freshness == .fresh)
                #expect(recovered.lastSuccessfulAt == m5aCodexUsage.providerCapturedAt.addingTimeInterval(900))
                #expect(await registry.orderedSnapshots().count == 1)
                #expect(await client.disconnectCount == 0)
            }
            await registry.stopAll()
        } onCancel: {
            Task {
                await client.cancelFixture()
                await registry.stopAll()
            }
        }
    }

    @Test
    func autonomousTransportReplacementCancelsOldPendingAndQueuedRequests() async throws {
        let queued = M5AEventCounter()
        let transport = M5ACodexTransport()
        let session = CodexAppServerSession(transportFactory: { transport }, requestSlotQueued: { queued.signal() })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        try await session.initializeIfNeeded()
        await transport.readerWaiting.wait(for: 1)
        transport.holdNextRequest()
        let pending = Task { () -> Bool in
            do {
                let _: M5ACodexEmptyResult = try await session.request(method: "account/read", params: M5ACodexEmptyParameters())
                return false
            } catch is CodexTransportReplacementInterrupted { return true }
            catch { return false }
        }
        await transport.pendingRequestStarted.wait(for: 1)
        let waiting = Task { () -> Bool in
            do {
                let _: M5ACodexEmptyResult = try await session.request(method: "account/read", params: M5ACodexEmptyParameters())
                return false
            } catch is CodexTransportReplacementInterrupted { return true }
            catch { return false }
        }
        await queued.wait(for: 1)
        transport.replaceWithoutOldEOF()
        #expect(try await session.maintainTransportIfNeeded())
        #expect(await pending.value)
        #expect(await waiting.value)
        #expect(transport.isRunning)
        #expect(!transport.needsInitialization)
        #expect(await session.requestLaneState().owner == nil)
        #expect(await session.requestLaneState().waitingCount == 0)
        transport.releaseOldEOF()
        let _: M5ACodexEmptyResult = try await session.request(method: "account/read", params: M5ACodexEmptyParameters())
        #expect(transport.isRunning)
        await session.shutdown()
    }

    @Test
    func lateRecoveryCapabilityCannotDisconnectReplacementSession() async {
        let client = M5ALateRecoveryCapabilityClient()
        let connector = CodexUsageConnector(client: client, localActivityReader: M5ACodexEmptyReader())
        await connector.perform(.connect)
        let obsoleteRefresh = Task { await connector.refresh() }
        await client.capabilityStarted.wait(for: 1)
        await connector.perform(.reconnect)
        #expect(await client.disconnectCount == 1)
        #expect(await client.isSessionActive)
        await client.releaseCapability(true)
        await obsoleteRefresh.value
        #expect(await client.disconnectCount == 1)
        #expect(await client.isSessionActive)
        #expect(await client.verifiedFetchCount == 2)
        #expect((await connector.currentSnapshot()).state == .ready)
        await connector.stop()
    }

    @Test
    func obsoleteSlotReleaseCannotUnlockNewSessionRequest() async throws {
        let queued = M5AEventCounter()
        let session = CodexAppServerSession(requestSlotQueued: { queued.signal() })
        let oldGeneration = await session.requestLaneState().generation
        let oldOwner = try await session.acquireRequestSlot(expectedGeneration: oldGeneration)
        await session.shutdown()
        let newGeneration = await session.requestLaneState().generation
        let currentOwner = try await session.acquireRequestSlot(expectedGeneration: newGeneration)
        let next = Task { try await session.acquireRequestSlot(expectedGeneration: newGeneration) }
        await queued.wait(for: 1)
        await session.releaseRequestSlot(oldOwner)
        #expect(await session.requestLaneState().owner == currentOwner)
        #expect(await session.requestLaneState().waitingCount == 1)
        await session.releaseRequestSlot(currentOwner)
        let nextOwner = try await next.value
        #expect(await session.requestLaneState().owner == nextOwner)
        await session.releaseRequestSlot(nextOwner)
        await session.shutdown()
    }

    @Test
    func queuedOldRequestCannotEnterReplacementSession() async throws {
        let queued = M5AEventCounter()
        let transport = M5ACodexTransport()
        let session = CodexAppServerSession(transportFactory: { transport }, requestSlotQueued: { queued.signal() })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        let generation = await session.requestLaneState().generation
        _ = try await session.acquireRequestSlot(expectedGeneration: generation)
        let obsolete = Task { () -> Bool in
            do {
                let _: M5ACodexEmptyResult = try await session.request(method: "account/read", params: M5ACodexEmptyParameters())
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        await queued.wait(for: 1)
        await session.shutdown()
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/replacement-codex"))
        #expect(await obsolete.value)
        #expect(transport.writeCount == 0)
        await session.shutdown()
    }
    @Test
    func retainedPublicationPreservesRealSuccessfulUpdateTime() async throws {
        let connector = CodexUsageConnector(client: M5ACodexBlockedClient(), localActivityReader: M5ACodexEmptyReader())
        await connector.perform(.connect)
        let snapshot = await connector.currentSnapshot()
        let reduced = ProviderProductStatePolicy.reduce(
            snapshots: [snapshot], admissions: [],
            monitoringEnabledIDs: [connector.id], previousCards: [], language: .english
        )
        #expect(snapshot.lastSuccessfulAt == m5aCodexUsage.providerCapturedAt)
        #expect(reduced.inventory.provider(.codex)?.capturedAt == m5aCodexUsage.providerCapturedAt)
        await connector.stop()
    }

    @Test(arguments: [false, true])
    func explicitDisconnectInvalidatesLateProviderCompletion(failing: Bool) async {
        let client = M5ACodexBlockedClient()
        let connector = CodexUsageConnector(client: client, localActivityReader: M5ACodexEmptyReader())
        await connector.perform(.connect)
        let refresh = Task { await connector.refresh() }
        await client.started.wait(for: 1)
        await connector.stop()
        await client.complete(failing: failing)
        await refresh.value
        let stopped = await connector.currentSnapshot()
        #expect(stopped.state == .inactive)
        #expect(stopped.lastSuccessfulAt == m5aCodexUsage.providerCapturedAt)
    }

    @Test
    func refreshFailureRetainsDateAndNewSnapshotAdvancesFreshness() async {
        let client = M5ACodexBlockedClient()
        let connector = CodexUsageConnector(client: client, localActivityReader: M5ACodexEmptyReader())
        await connector.perform(.connect)
        let original = await connector.currentSnapshot()
        #expect(original.state == .ready)
        #expect(original.freshness == .fresh)
        let failedRefresh = Task { await connector.refresh() }
        await client.started.wait(for: 1)
        let waiting = await connector.currentSnapshot()
        #expect(waiting.state == .waitingForFirstResponse)
        #expect(waiting.lastSuccessfulAt == original.lastSuccessfulAt)
        await client.complete(failing: true)
        await failedRefresh.value
        let stale = await connector.currentSnapshot()
        #expect(stale.state == .stale)
        #expect(stale.freshness == .stale)
        #expect(stale.lastSuccessfulAt == original.lastSuccessfulAt)
        #expect(stale.channels.first(where: { $0.id == .account })?.rateLimitWindows == original.channels.first(where: { $0.id == .account })?.rateLimitWindows)
        let recovery = Task { await connector.refresh() }
        await client.started.wait(for: 2)
        let nextDate = m5aCodexUsage.providerCapturedAt.addingTimeInterval(300)
        await client.complete(failing: false, capturedAt: nextDate)
        await recovery.value
        let recovered = await connector.currentSnapshot()
        #expect(recovered.state == .ready)
        #expect(recovered.freshness == .fresh)
        #expect(recovered.lastSuccessfulAt == nextDate)
        let reduced = ProviderProductStatePolicy.reduce(snapshots: [recovered], admissions: [], monitoringEnabledIDs: [connector.id], previousCards: [], language: .english)
        #expect(reduced.inventory.provider(.codex)?.capturedAt == nextDate)
        await connector.stop()
        #expect((await connector.currentSnapshot()).state == .inactive)
    }

    @Test
    func transportLossPublishesStaleWithoutReadingAndRecoveryPublishesNewTruth() async {
        let client = M5ACodexBlockedClient()
        let connector = CodexUsageConnector(client: client, localActivityReader: M5ACodexEmptyReader())
        await connector.perform(.connect)
        await client.listenerStarted.wait(for: 1)
        let stream = await connector.snapshots()
        var snapshots = stream.makeAsyncIterator()
        await client.emit(.transportUnavailable(.processExited))
        while let snapshot = await snapshots.next() {
            if snapshot.state == .stale {
                #expect(snapshot.freshness == .stale)
                #expect(snapshot.lastSuccessfulAt == m5aCodexUsage.providerCapturedAt)
                break
            }
        }
        #expect(await client.refreshCount == 0)
        await client.emit(.transportRecovered)
        await client.started.wait(for: 1)
        let recoveredDate = m5aCodexUsage.providerCapturedAt.addingTimeInterval(600)
        await client.complete(failing: false, capturedAt: recoveredDate)
        while let snapshot = await snapshots.next() {
            if snapshot.lastSuccessfulAt == recoveredDate {
                #expect(snapshot.freshness == .fresh)
                #expect(snapshot.state == .ready)
                break
            }
        }
        #expect(await client.refreshCount == 1)
        await connector.stop()
    }

    @Test
    func idleFailedTransportReplacementCannotRemainConnected() async throws {
        let transport = M5ACodexTransport()
        let session = CodexAppServerSession(transportFactory: { transport })
        let client = CodexAppServerClient(resolver: M5ACodexResolver(), session: session, ownedProcessMonitorInterval: .seconds(3600))
        _ = try await client.fetchUsage()
        transport.failReplacement()
        do {
            _ = try await session.maintainTransportIfNeeded()
            Issue.record("Fixture replacement must fail")
        } catch {}
        #expect(await client.connectionState() != .ready)
        await client.disconnect()
    }

    @Test
    func syntheticOwnedChildRemainsSingleAndActuallyTerminates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("uma-m5a-owned-child-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("synthetic-codex")
        // This child implements fixed fixture replies only. HOME points to
        // this empty task directory, never an installed provider.
        let script = #"""
        #!/bin/sh
        printf '%s\n' "$$" > "$HOME/child.pid"
        IFS= read -r request || exit 0
        printf '%s\n' '{"id":1,"result":{"codexHome":"/synthetic","platformFamily":"unix","platformOs":"macos","userAgent":"fixture"}}'
        IFS= read -r initialized || exit 0
        IFS= read -r request || exit 0
        printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}}'
        IFS= read -r request || exit 0
        printf '%s\n' '{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300}}}}'
        IFS= read -r request || exit 0
        printf '%s\n' '{"id":4,"result":{"summary":{"lifetimeTokens":1},"dailyUsageBuckets":[]}}'
        while IFS= read -r request; do :; done
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let exits = M5AEventCounter()
        let transport = ProcessCodexAppServerTransport(
            launchConfiguration: .init(homeDirectory: directory.path),
            onProcessExit: { _ in exits.signal() }
        )
        let session = CodexAppServerSession(transportFactory: { transport })
        let client = CodexAppServerClient(resolver: M5ACodexResolver(executableURL: executable), session: session, ownedProcessMonitorInterval: .seconds(3600))
        do {
            let usage = try await client.fetchUsage()
            #expect(usage.rateLimits.displayWindows.first?.usedPercent == 20)
            let pidURL = directory.appendingPathComponent("child.pid")
            let originalPID = try String(contentsOf: pidURL, encoding: .utf8)
            try await session.start(executableURL: executable)
            try await session.start(executableURL: executable)
            #expect(try String(contentsOf: pidURL, encoding: .utf8) == originalPID)
            #expect(transport.isRunning)
            await client.disconnect()
            await exits.wait(for: 1)
            #expect(!transport.isRunning)
        } catch {
            await client.disconnect()
            throw error
        }
    }
}

private let m5aCodexUsage = CodexLiveUsage(
    rateLimits: .init(planType: "PRO", windows: [.init(id: "five-hour", usedPercent: 20, windowDurationMinutes: 300, resetsAt: nil)]),
    availableResetCount: nil, lifetimeTokens: 1, dailyUsage: nil, recentActivityCount: 0,
    apiCostEstimate: nil, providerCapturedAt: Date(timeIntervalSince1970: 1_784_332_800)
)

private struct M5ACodexEmptyParameters: Encodable {}
private struct M5ACodexEmptyResult: Decodable {}

private struct M5ACodexEmptyReader: CodexLocalActivityReading {
    func read(now: Date) -> CodexLocalActivitySnapshot { .unavailable(now: now) }
}

private actor M5ACodexBlockedClient: CodexUsageClient {
    nonisolated let started = M5AEventCounter()
    nonisolated let listenerStarted = M5AEventCounter()
    private var pending: CheckedContinuation<CodexLiveUsage, Error>?
    private var events: AsyncStream<CodexAppServerEvent>.Continuation?
    private(set) var refreshCount = 0
    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage { m5aCodexUsage }
    func fetchUsage() async throws -> CodexLiveUsage {
        refreshCount += 1
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                started.signal()
            }
        } onCancel: {
            Task { await self.cancelPending() }
        }
    }
    private func cancelPending() {
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
    func complete(failing: Bool, capturedAt: Date = m5aCodexUsage.providerCapturedAt) {
        let pending = pending
        self.pending = nil
        if failing { pending?.resume(throwing: CodexUsageClientError(.processExited)) }
        else {
            pending?.resume(returning: CodexLiveUsage(
                rateLimits: m5aCodexUsage.rateLimits,
                availableResetCount: nil, lifetimeTokens: 1, dailyUsage: nil,
                recentActivityCount: 0, apiCostEstimate: nil,
                providerCapturedAt: capturedAt
            ))
        }
    }
    func eventStream() async -> AsyncStream<CodexAppServerEvent> {
        AsyncStream { continuation in
            events = continuation
            listenerStarted.signal()
        }
    }
    func emit(_ event: CodexAppServerEvent) { events?.yield(event) }
    func disconnect() async { events?.finish(); events = nil }
    func connectionState() async -> CodexConnectionState { .idle }
    func takeUsageRefreshRequest() async -> Bool { false }
}

private actor M5ALateRecoveryCapabilityClient: CodexUsageClient {
    nonisolated let capabilityStarted = M5AEventCounter()
    private var capability: CheckedContinuation<Bool, Never>?
    private(set) var disconnectCount = 0
    private(set) var verifiedFetchCount = 0
    private(set) var isSessionActive = false
    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage {
        verifiedFetchCount += 1
        isSessionActive = true
        return m5aCodexUsage
    }
    func fetchUsage() async throws -> CodexLiveUsage { throw CodexUsageClientError(.processExited) }
    func supportsOwnedProcessRecovery() async -> Bool {
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                capability = continuation
                capabilityStarted.signal()
            }
        } onCancel: {
            Task { await self.releaseCapability(false) }
        }
    }
    func releaseCapability(_ allowed: Bool) { capability?.resume(returning: allowed); capability = nil }
    func disconnect() async { disconnectCount += 1; isSessionActive = false }
    func connectionState() async -> CodexConnectionState { isSessionActive ? .ready : .idle }
    func takeUsageRefreshRequest() async -> Bool { false }
}

private actor M5AProviderRefreshGate {
    nonisolated let started = M5AEventCounter()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released, !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            guard !released, !Task.isCancelled else { return }
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started.signal()
            }
        } onCancel: { Task { await self.release() } }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor M5AActiveRecoveryClient: CodexUsageClient {
    nonisolated let events = M5AAcknowledgedEventQueue()
    nonisolated let refreshStarted = M5AEventCounter()
    private var interrupted: CheckedContinuation<CodexLiveUsage, Error>?
    private var isSessionActive = false
    private var fixtureCancelled = false
    private let replacementInterruption: Bool
    init(replacementInterruption: Bool = true) { self.replacementInterruption = replacementInterruption }
    private(set) var refreshCount = 0
    private(set) var disconnectCount = 0
    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage {
        guard !fixtureCancelled else { throw CancellationError() }
        isSessionActive = true
        return m5aCodexUsage
    }
    func fetchUsage() async throws -> CodexLiveUsage {
        guard !fixtureCancelled else { throw CancellationError() }
        refreshCount += 1
        if refreshCount > 1 {
            return CodexLiveUsage(rateLimits: m5aCodexUsage.rateLimits, availableResetCount: nil,
                lifetimeTokens: 2, dailyUsage: nil, recentActivityCount: 0, apiCostEstimate: nil,
                providerCapturedAt: m5aCodexUsage.providerCapturedAt.addingTimeInterval(900))
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                interrupted = continuation
                refreshStarted.signal()
            }
        } onCancel: {
            Task { await self.releaseInterruptedRead() }
        }
    }
    func releaseInterruptedRead() {
        let error: Error = replacementInterruption
            ? CodexTransportReplacementInterrupted()
            : CodexUsageClientError(.unknownSafeError)
        interrupted?.resume(throwing: error)
        interrupted = nil
    }
    func cancelFixture() async {
        fixtureCancelled = true
        releaseInterruptedRead()
        await events.finish()
    }
    func eventStream() async -> AsyncStream<CodexAppServerEvent> {
        let queue = events
        return AsyncStream(unfolding: { await queue.next() }, onCancel: {
            Task { await queue.finish() }
        })
    }
    func disconnect() async { disconnectCount += 1; isSessionActive = false; await events.finish() }
    func connectionState() async -> CodexConnectionState { isSessionActive ? .ready : .idle }
    func takeUsageRefreshRequest() async -> Bool { false }
}

private actor M5AAcknowledgedEventQueue {
    nonisolated let started = M5AEventCounter()
    nonisolated let consumed = M5AEventCounter()
    private var waiter: CheckedContinuation<CodexAppServerEvent?, Never>?
    private var pending: [CodexAppServerEvent] = []
    private var previousWasDelivered = false
    private var finished = false
    func next() async -> CodexAppServerEvent? {
        if previousWasDelivered { consumed.signal(); previousWasDelivered = false }
        started.signal()
        guard !finished, !Task.isCancelled else { return nil }
        if !pending.isEmpty { previousWasDelivered = true; return pending.removeFirst() }
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in waiter = continuation }
        } onCancel: {
            Task { await self.finish() }
        }
    }
    func send(_ event: CodexAppServerEvent) {
        guard !finished else { return }
        if let waiter {
            self.waiter = nil
            previousWasDelivered = true
            waiter.resume(returning: event)
        } else { pending.append(event) }
    }
    func finish() {
        finished = true
        waiter?.resume(returning: nil)
        waiter = nil
        pending.removeAll()
    }
}

private struct M5ACodexResolver: CodexExecutableResolving {
    var executableURL = URL(fileURLWithPath: "/synthetic/uma-m5a-codex")
    func resolve() throws -> URL { executableURL }
}

private final class M5ACodexTransport: CodexAppServerTransport, @unchecked Sendable {
    let readerWaiting = M5AEventCounter()
    let pendingRequestStarted = M5AEventCounter()
    private let lock = NSLock()
    private var running = true
    private var rejectsStart = false
    private var writes = 0
    private var messages: [Data] = []
    private var reader: CheckedContinuation<Data?, Error>?
    private var obsoleteReaders: [CheckedContinuation<Data?, Error>] = []
    private var requiresInitialization = false
    private var holdRequest = false
    var isRunning: Bool { lock.withLock { running } }
    var writeCount: Int { lock.withLock { writes } }
    var needsInitialization: Bool { lock.withLock { requiresInitialization } }
    func markInitialized() { lock.withLock { requiresInitialization = false } }
    func holdNextRequest() { lock.withLock { holdRequest = true } }
    func replaceWithoutOldEOF() {
        lock.withLock {
            requiresInitialization = true
            if let reader { obsoleteReaders.append(reader); self.reader = nil }
        }
    }
    func exitWithoutOldEOF() {
        lock.withLock {
            running = false
            if let reader { obsoleteReaders.append(reader); self.reader = nil }
        }
    }
    func releaseOldEOF() {
        let readers = lock.withLock { () -> [CheckedContinuation<Data?, Error>] in
            defer { obsoleteReaders.removeAll() }
            return obsoleteReaders
        }
        readers.forEach { $0.resume(returning: nil) }
    }
    func start(executableURL: URL) throws {
        if lock.withLock({ rejectsStart }) { throw CodexUsageClientError(.processLaunchFailed) }
        lock.withLock { running = true }
    }
    func failReplacement() { lock.withLock { running = false; rejectsStart = true } }
    func write(_ data: Data) throws {
        lock.withLock { writes += 1 }
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        guard let id = object["id"] else { return }
        let held = lock.withLock { () -> Bool in
            defer { holdRequest = false }
            return holdRequest
        }
        if held { pendingRequestStarted.signal(); return }
        let result: [String: Any]
        switch object["method"] as? String {
        case "initialize": result = ["codexHome": "/synthetic", "platformFamily": "unix", "platformOs": "macos", "userAgent": "fixture"]
        case "account/read": result = ["account": ["type": "chatgpt"], "requiresOpenaiAuth": true]
        case "account/rateLimits/read": result = ["rateLimits": ["planType": "PRO", "primary": ["usedPercent": 20, "windowDurationMins": 300]]]
        default: result = ["summary": ["lifetimeTokens": 1], "dailyUsageBuckets": []]
        }
        let response = try JSONSerialization.data(withJSONObject: ["id": id, "result": result])
        let waiting = lock.withLock { () -> CheckedContinuation<Data?, Error>? in
            if let reader { self.reader = nil; return reader }
            messages.append(response)
            return nil
        }
        waiting?.resume(returning: response)
    }
    func readLine() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !messages.isEmpty {
                let data = messages.removeFirst()
                lock.unlock()
                continuation.resume(returning: data)
            } else if !running {
                lock.unlock()
                continuation.resume(returning: nil)
            } else {
                reader = continuation
                lock.unlock()
                readerWaiting.signal()
            }
        }
    }
    func stop() {
        let waiting = lock.withLock { () -> CheckedContinuation<Data?, Error>? in
            running = false
            defer { reader = nil }
            return reader
        }
        waiting?.resume(returning: nil)
        releaseOldEOF()
    }
}
