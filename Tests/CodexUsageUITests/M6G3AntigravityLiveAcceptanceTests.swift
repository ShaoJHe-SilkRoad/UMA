import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M6-G3 Antigravity live acceptance", .serialized)
struct M6G3AntigravityLiveAcceptanceTests {
    @Test
    func liveHarnessAndFinalPackageStayWithinTheG3Boundary() throws {
        let source = try repositorySource(
            "Tests/CodexUsageUITests/M6G3AntigravityLiveAcceptanceTests.swift"
        )
        let package = try repositorySource("script/package_uma_m6.sh")

        #expect(source.contains("UMA_M6_G3_LIVE"))
        #expect(source.contains("AntigravityReadOnlyCLIClient()"))
        #expect(source.contains("maximumReadCount: 6"))
        #expect(source.contains("GoogleAntigravityUsageConnector("))
        #expect(source.contains("UsageStore("))
        #expect(source.contains("scheduledCycleCount"))
        #expect(source.contains("coalescedReadCount"))
        let forbiddenCreditsRoute = "/" + "credits"
        let forbiddenRawPayloadName = "raw" + "JSON"
        #expect(!source.contains(forbiddenCreditsRoute))
        #expect(!source.contains(forbiddenRawPayloadName))
        #expect(package.contains("g3-preflight"))
        #expect(package.contains("g3-final"))
        #expect(package.contains("uma-m6-g3-${phase#g3-}-$commit/UMA.app"))
    }

    @Test @MainActor
    func productionConnectorSchedulerAndMainPanelPath() async throws {
        guard ProcessInfo.processInfo.environment["UMA_M6_G3_LIVE"] == "1"
        else {
            return
        }

        let evidencePath = try #require(
            ProcessInfo.processInfo.environment["UMA_M6_G3_EVIDENCE_PATH"]
        )
        let client = AntigravityReadOnlyCLIClient()
        let reader = M6G3LiveQuotaReader(
            client: client,
            maximumReadCount: 6,
            postReadHold: .seconds(3)
        )
        let connector = GoogleAntigravityUsageConnector(
            readQuota: { try await reader.read() },
            verifyCapability: { _ = try client.verifyCapability() },
            autoRefreshEnabled: { true }
        )
        let sentinels = [
            M6G3SentinelConnector(id: "codex.local", name: "Codex"),
            M6G3SentinelConnector(id: "claude.local", name: "Claude Code"),
            M6G3SentinelConnector(
                id: "workbuddy.accountWeb",
                name: "WorkBuddy"
            ),
        ]
        let registry = try AgentConnectorRegistry(
            connectors: sentinels.map { $0 as any AgentUsageConnector }
                + [connector]
        )
        let suiteName = "m6-g3-live-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: sentinels[0].id,
            consentDefaults: defaults
        )

        await store.refresh()
        let initialReady = await waitUntil(iterations: 300, delay: .milliseconds(100)) {
            await reader.status().readCount == 1
                && store.presentationCards.contains {
                    $0.id == GoogleAntigravityUsageConnector.connectorID.rawValue
                }
        }
        guard initialReady else {
            let status = await reader.status()
            let observationCount = await reader.observations().count
            let snapshot = await connector.currentSnapshot()
            await store.stopAllConnectors()
            let stateDescription = String(describing: snapshot.state)
            let failureDescription = String(describing: snapshot.safeFailure)
            let detail = [
                "reads=\(status.readCount)",
                "normalized=\(observationCount)",
                "state=\(stateDescription)",
                "failure=\(failureDescription)",
                "readerFailure=\(String(describing: status.lastFailure))",
            ].joined(separator: ", ")
            Issue.record(
                "Initial production Antigravity read was not admitted: \(detail)."
            )
            return
        }

        let initialObservations = await reader.observations()
        guard let first = initialObservations.first else {
            await store.stopAllConnectors()
            Issue.record("Initial normalized observation was unavailable.")
            return
        }
        let initialCard = store.presentationCards.first {
            $0.id == GoogleAntigravityUsageConnector.connectorID.rawValue
        }

        let scheduledStarted = await waitUntil(
            iterations: 3_300,
            delay: .milliseconds(100)
        ) {
            let status = await reader.status()
            return status.readCount == 2 && status.concurrentReadCount == 1
        }
        guard scheduledStarted else {
            await store.stopAllConnectors()
            Issue.record("The production five-minute scheduled read did not start.")
            return
        }

        let manual = Task { await connector.refresh(trigger: .manual) }
        await manual.value
        let postSchedule = await reader.observations()
        let diagnostics = await connector.diagnostics()
        let finalSnapshot = await connector.currentSnapshot()
        let finalCardReady = await waitUntil(
            iterations: 200,
            delay: .milliseconds(50)
        ) {
            store.presentationCards.first {
                $0.id == GoogleAntigravityUsageConnector.connectorID.rawValue
            }?.capturedAt == finalSnapshot.capturedAt
        }
        let finalCard = store.presentationCards.first {
            $0.id == GoogleAntigravityUsageConnector.connectorID.rawValue
        }
        let status = await reader.status()

        let multipleBuckets = first.buckets.count > 1
        let uniqueBucketIdentity = Set(first.buckets.map(\.id)).count
            == first.buckets.count
        let allResetsScoped = first.buckets.allSatisfy { $0.resetsAt != nil }
        let identityStable: Bool
        let noAttributableDecrease: Bool
        if let second = postSchedule.last, postSchedule.count == 2 {
            let firstByID = Dictionary(
                uniqueKeysWithValues: first.buckets.map { ($0.id, $0) }
            )
            let secondByID = Dictionary(
                uniqueKeysWithValues: second.buckets.map { ($0.id, $0) }
            )
            identityStable = Set(firstByID.keys) == Set(secondByID.keys)
            noAttributableDecrease = identityStable && secondByID.allSatisfy {
                guard let previous = firstByID[$0.key] else { return false }
                return $0.value.remainingPercent + 0.000_001
                    >= previous.remainingPercent
            }
        } else {
            identityStable = false
            noAttributableDecrease = false
        }
        let mainPanelParity = initialCard.map {
            M6G3SanitizedComparison.matches(first, card: $0)
        } ?? false
        let finalMainPanelParity = finalCard.map {
            M6G3SanitizedComparison.matches(finalSnapshot, card: $0)
        } ?? false
        let providerOrder = store.presentationCards.map(\.id) == [
            "codex.local",
            "claude.local",
            "workbuddy.accountWeb",
            GoogleAntigravityUsageConnector.connectorID.rawValue,
        ]
        let assistantExcluded = !store.assistantPresentationCards.contains {
            $0.id == GoogleAntigravityUsageConnector.connectorID.rawValue
        }
        let evidence = M6G3SanitizedLiveEvidence(
            liveReadCount: status.readCount,
            liveReadCap: 6,
            maximumConcurrentReadCount: status.maximumConcurrentReadCount,
            multipleIndependentBuckets: multipleBuckets,
            stableBucketIdentity: uniqueBucketIdentity && identityStable,
            remainingNormalizationParity: mainPanelParity
                && finalMainPanelParity,
            bucketScopedResetValid: allResetsScoped,
            mainPanelAdmission: initialCard != nil && finalCardReady,
            providerOrderValid: providerOrder,
            desktopAssistantExcluded: assistantExcluded,
            scheduledRefreshCompleted: diagnostics.scheduledCycleCount == 1
                && diagnostics.completedReadCount == 2,
            manualScheduledCoalescing: diagnostics.coalescedReadCount >= 1,
            noDuplicateProcess: status.maximumConcurrentReadCount == 1,
            noAttributableQuotaDecrease: noAttributableDecrease,
            processAndSchedulerStopped: false
        )

        await store.stopAllConnectors()
        let stoppedDiagnostics = await connector.diagnostics()
        let stoppedEvidence = evidence.withStoppedState(
            !stoppedDiagnostics.processReadInFlight
                && !stoppedDiagnostics.schedulerActive
        )
        try stoppedEvidence.write(to: URL(fileURLWithPath: evidencePath))

        #expect(stoppedEvidence.liveReadCount == 2)
        #expect(stoppedEvidence.maximumConcurrentReadCount == 1)
        #expect(stoppedEvidence.multipleIndependentBuckets)
        #expect(stoppedEvidence.stableBucketIdentity)
        #expect(stoppedEvidence.remainingNormalizationParity)
        #expect(stoppedEvidence.bucketScopedResetValid)
        #expect(stoppedEvidence.mainPanelAdmission)
        #expect(stoppedEvidence.providerOrderValid)
        #expect(stoppedEvidence.desktopAssistantExcluded)
        #expect(stoppedEvidence.scheduledRefreshCompleted)
        #expect(stoppedEvidence.manualScheduledCoalescing)
        #expect(stoppedEvidence.noDuplicateProcess)
        #expect(stoppedEvidence.noAttributableQuotaDecrease)
        #expect(stoppedEvidence.processAndSchedulerStopped)
    }

    private func repositorySource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    @MainActor
    private func waitUntil(
        iterations: Int,
        delay: Duration,
        _ predicate: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        for _ in 0..<iterations {
            if await predicate() { return true }
            try? await Task.sleep(for: delay)
        }
        return false
    }
}

private actor M6G3LiveQuotaReader {
    struct Status: Sendable {
        let readCount: Int
        let concurrentReadCount: Int
        let maximumConcurrentReadCount: Int
        let lastFailure: AntigravityCLIClientError?
    }

    private let client: AntigravityReadOnlyCLIClient
    private let maximumReadCount: Int
    private let postReadHold: Duration
    private var readCount = 0
    private var concurrentReadCount = 0
    private var maximumConcurrentReadCount = 0
    private var lastFailure: AntigravityCLIClientError?
    private var captured: [AntigravityQuotaSnapshot] = []

    init(
        client: AntigravityReadOnlyCLIClient,
        maximumReadCount: Int,
        postReadHold: Duration
    ) {
        self.client = client
        self.maximumReadCount = maximumReadCount
        self.postReadHold = postReadHold
    }

    func read() async throws -> AntigravityQuotaSnapshot {
        guard readCount < maximumReadCount else {
            throw AntigravityCLIClientError.providerUnavailable
        }
        readCount += 1
        concurrentReadCount += 1
        maximumConcurrentReadCount = max(
            maximumConcurrentReadCount,
            concurrentReadCount
        )
        defer { concurrentReadCount -= 1 }
        do {
            let snapshot = try await client.readCurrentQuota()
            lastFailure = nil
            captured.append(snapshot)
            try await Task.sleep(for: postReadHold)
            return snapshot
        } catch let error as AntigravityCLIClientError {
            lastFailure = error
            throw error
        }
    }

    func status() -> Status {
        Status(
                readCount: readCount,
                concurrentReadCount: concurrentReadCount,
                maximumConcurrentReadCount: maximumConcurrentReadCount,
                lastFailure: lastFailure
        )
    }

    func observations() -> [AntigravityQuotaSnapshot] { captured }
}

private enum M6G3SanitizedComparison {
    static func matches(
        _ quota: AntigravityQuotaSnapshot,
        card: SharedUsageCardPresentation
    ) -> Bool {
        guard card.providerName == "Google Antigravity",
              card.freshness == .fresh,
              card.connectionStatus == .connected,
              !card.isVisibleInDesktopAssistant,
              card.windows.count == quota.buckets.count
        else { return false }
        let quotaByID = Dictionary(
            uniqueKeysWithValues: quota.buckets.map { ($0.id, $0) }
        )
        return card.windows.allSatisfy { window in
            guard let source = quotaByID[window.id] else { return false }
            return window.remaining.finitePercent == source.remainingPercent
                && window.resetsAt == source.resetsAt
        }
    }

    static func matches(
        _ snapshot: AgentUsageSnapshot,
        card: SharedUsageCardPresentation
    ) -> Bool {
        guard snapshot.id.rawValue == card.id,
              let channel = snapshot.channels.first(where: { $0.id == .account }),
              channel.rateLimitWindows.count == card.windows.count
        else { return false }
        let sourceByID = Dictionary(
            uniqueKeysWithValues: channel.rateLimitWindows.map { ($0.id, $0) }
        )
        return card.windows.allSatisfy { window in
            guard let source = sourceByID[window.id] else { return false }
            return window.remaining.finitePercent
                    == source.normalizedRemainingPercent
                && window.resetsAt == source.resetsAt
        }
    }
}

private struct M6G3SanitizedLiveEvidence: Codable {
    let liveReadCount: Int
    let liveReadCap: Int
    let maximumConcurrentReadCount: Int
    let multipleIndependentBuckets: Bool
    let stableBucketIdentity: Bool
    let remainingNormalizationParity: Bool
    let bucketScopedResetValid: Bool
    let mainPanelAdmission: Bool
    let providerOrderValid: Bool
    let desktopAssistantExcluded: Bool
    let scheduledRefreshCompleted: Bool
    let manualScheduledCoalescing: Bool
    let noDuplicateProcess: Bool
    let noAttributableQuotaDecrease: Bool
    let processAndSchedulerStopped: Bool

    func withStoppedState(_ value: Bool) -> Self {
        Self(
            liveReadCount: liveReadCount,
            liveReadCap: liveReadCap,
            maximumConcurrentReadCount: maximumConcurrentReadCount,
            multipleIndependentBuckets: multipleIndependentBuckets,
            stableBucketIdentity: stableBucketIdentity,
            remainingNormalizationParity: remainingNormalizationParity,
            bucketScopedResetValid: bucketScopedResetValid,
            mainPanelAdmission: mainPanelAdmission,
            providerOrderValid: providerOrderValid,
            desktopAssistantExcluded: desktopAssistantExcluded,
            scheduledRefreshCompleted: scheduledRefreshCompleted,
            manualScheduledCoalescing: manualScheduledCoalescing,
            noDuplicateProcess: noDuplicateProcess,
            noAttributableQuotaDecrease: noAttributableQuotaDecrease,
            processAndSchedulerStopped: value
        )
    }

    func write(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}

private actor M6G3SentinelConnector: AgentUsageConnector {
    nonisolated let id: AgentConnectorID
    nonisolated let descriptor: AgentConnectorDescriptor
    private let snapshot: AgentUsageSnapshot

    init(id rawID: String, name: String) {
        let id = AgentConnectorID(rawValue: rawID)!
        self.id = id
        descriptor = AgentConnectorDescriptor(
            id: id,
            providerName: name,
            officialSource: "M6-G3 isolation sentinel",
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "m6-g3-sentinel",
            supportedScopes: [.account],
            capabilities: [.rateLimits],
            configurationRequirements: [.officialManagedSession],
            privacyAllowlist: ["syntheticSentinel"],
            supportsRestore: false,
            supportsUninstall: false,
            unsupportedFields: []
        )!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        snapshot = AgentUsageSnapshot(
            id: id,
            providerName: name,
            state: .ready,
            capturedAt: now,
            lastSuccessfulAt: now,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialCLIOrMetadata,
                    sourceVersion: "m6-g3-sentinel",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: now,
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: "synthetic",
                            kind: .other,
                            displayLabel: "Synthetic",
                            usedPercent: nil,
                            remainingPercent: 50,
                            isUnlimited: false,
                            resetsAt: nil
                        ),
                    ],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                ),
            ],
            capabilities: [.rateLimits],
            safeFailure: nil
        )
    }

    func probe() async -> AgentConnectorProbe {
        AgentConnectorProbe(state: .ready, safeFailure: nil)
    }
    func start() async {}
    func refresh() async {}
    func perform(_ command: AgentConnectorCommand) async {}
    func stop() async {}
    func currentSnapshot() async -> AgentUsageSnapshot { snapshot }
    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            continuation.yield(snapshot)
        }
    }
}
