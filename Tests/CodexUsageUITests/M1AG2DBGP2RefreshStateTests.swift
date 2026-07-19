import Foundation
import Testing
@testable import CodexUsageUI

struct M1AG2DBGP2RefreshStateTests {
    @Test @MainActor
    func productionCadenceAndPanelOpenAgeGateAreStable() {
        #expect(UsageStore.productionVisibleRefreshInterval == .seconds(15))
        #expect(UsageStore.productionBackgroundRefreshInterval == .seconds(30))
        #expect(UsageStore.productionPanelOpenRefreshMinimumAge == 15)

        let now = Date(timeIntervalSince1970: 1_784_332_800)
        #expect(!UsageStore.shouldRefreshOnPanelOpen(
            lastSuccessfulAt: nil,
            now: now,
            minimumAge: 15
        ))
        #expect(!UsageStore.shouldRefreshOnPanelOpen(
            lastSuccessfulAt: now.addingTimeInterval(-14.999),
            now: now,
            minimumAge: 15
        ))
        #expect(UsageStore.shouldRefreshOnPanelOpen(
            lastSuccessfulAt: now.addingTimeInterval(-15),
            now: now,
            minimumAge: 15
        ))
    }

    @Test @MainActor
    func falseToTruePanelOpenRefreshesOldProviderDataAndRetainsValuesWhileRefreshing() async throws {
        let providerTime = Date(timeIntervalSince1970: 1_784_332_700)
        let now = Date(timeIntervalSince1970: 1_784_332_800)
        let connector = P2RefreshConnector(snapshot: Self.snapshot(capturedAt: providerTime, usedPercent: 25))
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let store = Self.store(registry: registry, now: now)

        store.grantMonitorConsent()
        await store.refresh()
        #expect(await connector.refreshCount == 1)
        #expect(store.snapshot.periods.first?.remainingPercent == 75)
        #expect(store.snapshot.providerSource?.capturedAt == providerTime)

        await connector.publishWaitingStateDuringNextOperation()
        await connector.blockNextOperation()
        store.setPanelVisible(true)
        await connector.waitUntilOperationStarts(count: 2)

        #expect(store.isRefreshing)
        #expect(store.currentState == .refreshingWithPreviousRealData)
        #expect(store.snapshot.periods.first?.remainingPercent == 75)
        #expect(store.snapshot.providerSource?.capturedAt == providerTime)

        let refreshedAt = now.addingTimeInterval(1)
        await connector.finishBlockedOperation(
            with: Self.snapshot(capturedAt: refreshedAt, usedPercent: 30)
        )
        for _ in 0..<50 where store.isRefreshing {
            await Task.yield()
        }

        #expect(await connector.refreshCount == 2)
        #expect(await connector.refreshTriggers == [.manual, .timer])
        #expect(store.snapshot.periods.first?.remainingPercent == 70)
        #expect(store.snapshot.providerSource?.capturedAt == refreshedAt)
        await store.stopAllConnectors()
    }

    @Test @MainActor
    func ownedChildRecoveryRetainsValuesDuringUncoordinatedWaitingPublication() async throws {
        let now = Date(timeIntervalSince1970: 1_784_332_800)
        let connector = P2RefreshConnector(snapshot: Self.snapshot(capturedAt: now, usedPercent: 25))
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let store = Self.store(registry: registry, now: now)

        store.grantMonitorConsent()
        await store.refresh()
        #expect(store.currentState == .ready)
        #expect(store.snapshot.periods.first?.remainingPercent == 75)

        await connector.publishWaitingState()
        for _ in 0..<20 where store.currentState == .ready {
            await Task.yield()
        }

        #expect(!store.isRefreshing)
        #expect(store.currentState == .refreshingWithPreviousRealData)
        #expect(store.snapshot.periods.first?.remainingPercent == 75)
        #expect(store.snapshot.providerSource?.capturedAt == now)
        await store.stopAllConnectors()
    }

    @Test @MainActor
    func freshPanelOpenDoesNotRefreshAndConcurrentCausesJoinOneOperation() async throws {
        let now = Date(timeIntervalSince1970: 1_784_332_800)
        let connector = P2RefreshConnector(snapshot: Self.snapshot(capturedAt: now, usedPercent: 40))
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let store = Self.store(registry: registry, now: now)

        store.grantMonitorConsent()
        await store.refresh()
        store.setPanelVisible(true)
        for _ in 0..<20 { await Task.yield() }
        #expect(await connector.refreshCount == 1)

        await connector.blockNextOperation()
        let manual = Task { await store.refresh() }
        await connector.waitUntilOperationStarts(count: 2)
        let wake = Task { await store.handleApplicationWake() }
        let reconnect = Task { await store.reconnectMonitor() }
        for _ in 0..<20 { await Task.yield() }

        #expect(await connector.maximumConcurrentOperationCount == 1)
        #expect(await connector.refreshCount == 2)
        #expect(await connector.reconnectCount == 0)

        await connector.finishBlockedOperation(
            with: Self.snapshot(capturedAt: now.addingTimeInterval(1), usedPercent: 41)
        )
        await manual.value
        await wake.value
        await reconnect.value

        #expect(await connector.maximumConcurrentOperationCount == 1)
        #expect(await connector.refreshCount == 2)
        #expect(await connector.reconnectCount == 0)

        await store.reconnectMonitor()
        #expect(await connector.reconnectCount == 1)
        #expect(await connector.maximumConcurrentOperationCount == 1)
        await store.stopAllConnectors()
    }

    @MainActor
    private static func store(
        registry: AgentConnectorRegistry,
        now: Date
    ) -> UsageStore {
        UsageStore(
            autoRefresh: true,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: P2RefreshConnector.connectorID,
            consentDefaults: UserDefaults(suiteName: "m1a-g2-dbg-p2-refresh-\(UUID().uuidString)"),
            visibleRefreshInterval: .seconds(3_600),
            backgroundRefreshInterval: .seconds(3_600),
            panelOpenRefreshMinimumAge: 15,
            now: { now }
        )
    }

    private static func snapshot(capturedAt: Date, usedPercent: Double) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: P2RefreshConnector.connectorID,
            providerName: "Codex",
            state: .ready,
            capturedAt: capturedAt,
            lastSuccessfulAt: capturedAt,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialLocalService,
                    sourceVersion: "fixture",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: capturedAt,
                    coverageNote: nil,
                    rateLimitWindows: [
                        .init(
                            id: "five-hour",
                            kind: .fiveHour,
                            usedPercent: usedPercent,
                            isUnlimited: false,
                            resetsAt: nil
                        )
                    ],
                    accountMetrics: .init(
                        planLabel: "PRO",
                        availableResets: nil,
                        lifetimeTokens: nil,
                        sevenDayTokens: nil
                    ),
                    localActivityMetrics: nil,
                    safeFailure: nil
                )
            ],
            capabilities: [.reconnect, .refresh],
            safeFailure: nil
        )
    }
}

private actor P2RefreshConnector: AgentUsageConnector {
    nonisolated static let connectorID = AgentConnectorID(rawValue: "codex.p2-refresh")!
    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "Codex",
        officialSource: "fixture",
        sourceTier: .officialLocalService,
        sourceVersion: "fixture",
        supportedScopes: [.account],
        capabilities: [.reconnect, .refresh],
        configurationRequirements: [.userAuthorization],
        privacyAllowlist: ["aggregate"],
        supportsRestore: false,
        supportsUninstall: true,
        unsupportedFields: []
    )!

    private var snapshot: AgentUsageSnapshot
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var shouldBlockNextOperation = false
    private var shouldPublishWaitingStateOnNextOperation = false
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var activeOperationCount = 0
    private(set) var maximumConcurrentOperationCount = 0
    private(set) var refreshCount = 0
    private(set) var reconnectCount = 0
    private(set) var refreshTriggers: [CodexRefreshTrigger] = []

    init(snapshot: AgentUsageSnapshot) {
        self.snapshot = snapshot
    }

    func probe() async -> AgentConnectorProbe {
        .init(state: snapshot.state, safeFailure: snapshot.safeFailure)
    }

    func start() async {}
    func refresh() async { await refresh(trigger: .manual) }

    func refresh(trigger: CodexRefreshTrigger) async {
        refreshCount += 1
        refreshTriggers.append(trigger)
        await runOperation()
    }

    func perform(_ command: AgentConnectorCommand) async {
        if command == .reconnect {
            reconnectCount += 1
            await runOperation()
        }
    }

    func stop() async {
        blockedContinuation?.resume()
        blockedContinuation = nil
        continuation?.finish()
        continuation = nil
    }

    func currentSnapshot() async -> AgentUsageSnapshot { snapshot }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(snapshot)
        }
    }

    func blockNextOperation() {
        shouldBlockNextOperation = true
    }

    func publishWaitingStateDuringNextOperation() {
        shouldPublishWaitingStateOnNextOperation = true
    }

    func publishWaitingState() {
        snapshot = snapshot.replacingState(.waitingForFirstResponse)
        continuation?.yield(snapshot)
    }

    func waitUntilOperationStarts(count: Int) async {
        guard refreshCount + reconnectCount < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func finishBlockedOperation(with snapshot: AgentUsageSnapshot) {
        self.snapshot = snapshot
        continuation?.yield(snapshot)
        blockedContinuation?.resume()
        blockedContinuation = nil
    }

    private func runOperation() async {
        activeOperationCount += 1
        maximumConcurrentOperationCount = max(maximumConcurrentOperationCount, activeOperationCount)
        resumeSatisfiedStartWaiters()
        if shouldPublishWaitingStateOnNextOperation {
            shouldPublishWaitingStateOnNextOperation = false
            snapshot = snapshot.replacingState(.waitingForFirstResponse)
            continuation?.yield(snapshot)
        }
        if shouldBlockNextOperation {
            shouldBlockNextOperation = false
            await withCheckedContinuation { continuation in
                blockedContinuation = continuation
            }
        }
        continuation?.yield(snapshot)
        activeOperationCount -= 1
    }

    private func resumeSatisfiedStartWaiters() {
        var pending: [(Int, CheckedContinuation<Void, Never>)] = []
        for (count, continuation) in startWaiters {
            if refreshCount + reconnectCount >= count {
                continuation.resume()
            } else {
                pending.append((count, continuation))
            }
        }
        startWaiters = pending
    }
}

private extension AgentUsageSnapshot {
    func replacingState(_ state: AgentConnectorState) -> Self {
        AgentUsageSnapshot(
            id: id,
            providerName: providerName,
            state: state,
            capturedAt: capturedAt,
            lastSuccessfulAt: lastSuccessfulAt,
            freshness: freshness,
            channels: channels,
            capabilities: capabilities,
            safeFailure: safeFailure
        )
    }
}
