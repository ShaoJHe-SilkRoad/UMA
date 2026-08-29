import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M6DBG four-provider main-app acceptance", .serialized)
struct M6DBGFourProviderMainAppTests {
    @Test
    func everyProviderSubsetHasStableOrderAndNoPlaceholder() throws {
        let all = try M6DBGFixture.allSnapshots()
        let orderedIDs = M6DBGProvider.allCases.map(\.id)

        for mask in 0..<(1 << M6DBGProvider.allCases.count) {
            let snapshots = all.enumerated().compactMap { index, snapshot in
                mask & (1 << index) == 0 ? nil : snapshot
            }.reversed()
            let cards = SharedUsagePresentationPolicy.makeCards(
                snapshots: Array(snapshots),
                previousCards: [],
                language: .english,
                now: M6DBGFixture.now
            )
            let expected = orderedIDs.enumerated().compactMap { index, id in
                mask & (1 << index) == 0 ? nil : id
            }
            #expect(cards.map(\.id) == expected)
            #expect(Set(cards.map(\.id)).count == cards.count)
        }
    }

    @Test
    func failedProvidersNeverBlankOrContaminateHealthyProviders() throws {
        let providers = M6DBGProvider.allCases
        for failedMask in 0..<(1 << providers.count) {
            let snapshots = try providers.enumerated().map { index, provider in
                if failedMask & (1 << index) != 0 {
                    return M6DBGFixture.failedSnapshot(provider)
                }
                return try M6DBGFixture.snapshot(provider)
            }
            let cards = SharedUsagePresentationPolicy.makeCards(
                snapshots: snapshots.reversed(),
                previousCards: [],
                language: .english,
                now: M6DBGFixture.now
            )
            let expected = providers.enumerated().compactMap { index, provider in
                failedMask & (1 << index) == 0 ? provider.id : nil
            }
            #expect(cards.map(\.id) == expected)
            #expect(cards.allSatisfy { $0.connectionStatus == .connected })
            #expect(!cards.contains { $0.remaining == .finite(0) })
        }
    }

    @Test
    func observationAndRefreshCompletionOrderCannotMoveOrCrossWireCards() throws {
        let permutations = permutations(of: M6DBGProvider.allCases)
        for order in permutations {
            var snapshots = try M6DBGFixture.allSnapshots()
            var previous: [SharedUsageCardPresentation] = []
            for (revision, provider) in order.enumerated() {
                let index = try #require(
                    snapshots.firstIndex { $0.id.rawValue == provider.id }
                )
                snapshots[index] = try M6DBGFixture.snapshot(
                    provider,
                    remaining: provider.remaining - Double(revision + 1),
                    capturedAt: M6DBGFixture.now.addingTimeInterval(
                        Double(revision + 1)
                    )
                )
                var generator = M6DBGDeterministicRandom()
                previous = SharedUsagePresentationPolicy.makeCards(
                    snapshots: snapshots.shuffled(using: &generator),
                    previousCards: previous,
                    language: .english,
                    now: M6DBGFixture.now
                )
                #expect(previous.map(\.id) == M6DBGProvider.allCases.map(\.id))
                for card in previous where card.id != M6DBGProvider.workBuddy.id {
                    let owner = try #require(
                        M6DBGProvider.allCases.first { $0.id == card.id }
                    )
                    let ownerRevision = order.firstIndex(of: owner)
                    let expected = ownerRevision.map {
                        $0 <= revision
                            ? owner.remaining - Double($0 + 1)
                            : owner.remaining
                    } ?? owner.remaining
                    #expect(card.remaining == .finite(expected))
                }
            }
        }
    }

    @Test
    func antigravityDisappearsReappearsAndWorkBuddyRemainsExactCredits() throws {
        let all = try M6DBGFixture.allSnapshots()
        let initial = SharedUsagePresentationPolicy.makeCards(
            snapshots: all,
            previousCards: [],
            language: .english,
            now: M6DBGFixture.now
        )
        let without = SharedUsagePresentationPolicy.makeCards(
            snapshots: all.filter { $0.id.rawValue != M6DBGProvider.antigravity.id },
            previousCards: initial,
            language: .english,
            now: M6DBGFixture.now
        )
        let restored = SharedUsagePresentationPolicy.makeCards(
            snapshots: all,
            previousCards: without,
            language: .english,
            now: M6DBGFixture.now
        )

        #expect(!without.contains { $0.id == M6DBGProvider.antigravity.id })
        #expect(restored.map(\.id) == M6DBGProvider.allCases.map(\.id))
        let workBuddy = try #require(
            restored.first { $0.id == M6DBGProvider.workBuddy.id }
        )
        #expect(workBuddy.remaining == .unavailable)
        #expect(workBuddy.availability?.exactCreditValue == Decimal(string: "2099.47"))
        #expect(workBuddy.availability?.displayUnit == .credits)
    }

    @Test
    func antigravityTransientFailureRecoversAndSchemaFailureClearsOnlyIt() async throws {
        let reader = M6DBGSequenceReader(results: [
            .success(M6DBGFixture.quota(remaining: 58)),
            .failure(.timedOut),
            .success(M6DBGFixture.quota(remaining: 57)),
            .failure(.unsupportedSchema),
        ])
        let connector = M6DBGFixture.connector { try await reader.read() }

        await connector.start()
        await M6DBGWait.until {
            (await connector.diagnostics()).completedReadCount == 1
        }
        await connector.refresh(trigger: .manual)
        var snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .ready)
        #expect(snapshot.freshness == .cached)
        #expect(snapshot.safeFailure == .timedOut)
        #expect(snapshot.channels.first?.rateLimitWindows.first?.remainingPercent == 58)

        await connector.refresh(trigger: .manual)
        snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .ready)
        #expect(snapshot.freshness == .fresh)
        #expect(snapshot.channels.first?.rateLimitWindows.first?.remainingPercent == 57)

        await connector.refresh(trigger: .manual)
        snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .unsupported)
        #expect(snapshot.channels.isEmpty)
        #expect(snapshot.safeFailure == .unsupported)
        await connector.stop()
    }

    @Test
    func reorderedBucketsAndMissingResetRemainProviderScoped() async {
        let first = M6DBGFixture.quota(
            remaining: 58,
            includeSecondBucket: true,
            reverseBuckets: false
        )
        let second = M6DBGFixture.quota(
            remaining: 58,
            includeSecondBucket: true,
            reverseBuckets: true,
            missingReset: true
        )
        let reader = M6DBGSequenceReader(results: [.success(first), .success(second)])
        let connector = M6DBGFixture.connector { try await reader.read() }
        await connector.start()
        await M6DBGWait.until {
            (await connector.diagnostics()).completedReadCount == 1
        }
        await connector.refresh(trigger: .manual)
        let snapshot = await connector.currentSnapshot()
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .english,
            now: M6DBGFixture.now
        )

        #expect(Set(card.windows.map(\.id)) == ["pool-a", "pool-b"])
        #expect(card.selectedWindowID == "pool-a")
        #expect(card.remaining == .finite(58))
        #expect(card.windows.allSatisfy { $0.resetsAt == nil })
        await connector.stop()
    }

    @Test
    func manualTimerAndWakeCollisionOwnOneAntigravityRead() async {
        let reader = M6DBGCollisionReader()
        let connector = M6DBGFixture.connector { await reader.read() }
        await connector.start()
        await M6DBGWait.until {
            (await connector.diagnostics()).completedReadCount == 1
        }
        await reader.blockFutureReads()

        let tasks = (0..<60).map { index in
            Task {
                let trigger: CodexRefreshTrigger = switch index % 3 {
                case 0: .manual
                case 1: .timer
                default: .providerEvent
                }
                await connector.refresh(trigger: trigger)
            }
        }
        await M6DBGWait.until { await reader.readCount == 2 }
        await reader.release()
        for task in tasks { await task.value }

        let diagnostics = await connector.diagnostics()
        #expect(await reader.maximumConcurrentReadCount == 1)
        #expect(diagnostics.completedReadCount == 2)
        #expect(diagnostics.coalescedReadCount >= 59)
        await connector.stop()
    }

    @Test
    func twentyRuntimeCyclesAndObserverTeardownLeaveNoOwnedWork() async {
        for _ in 0..<20 {
            let reader = M6DBGCountingReader()
            let connector = M6DBGFixture.connector { await reader.read() }
            await connector.start()
            await M6DBGWait.until {
                (await connector.diagnostics()).completedReadCount == 1
            }
            await connector.stop()
            let diagnostics = await connector.diagnostics()
            #expect(!diagnostics.processReadInFlight)
            #expect(!diagnostics.schedulerActive)
            #expect(diagnostics.snapshotObserverCount == 0)
        }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func fiftyPanelAndThirtySettingsCyclesDoNotAccumulateState() async throws {
        let all = try M6DBGFixture.allSnapshots()
        var cards: [SharedUsageCardPresentation] = []
        for _ in 0..<50 {
            cards = SharedUsagePresentationPolicy.makeCards(
                snapshots: all,
                previousCards: cards,
                language: .english,
                now: M6DBGFixture.now
            )
            #expect(cards.count == 4)
            cards = SharedUsagePresentationPolicy.makeCards(
                snapshots: [],
                previousCards: cards,
                language: .english,
                now: M6DBGFixture.now
            )
            #expect(cards.isEmpty)
        }

        let connector = M6DBGFixture.connector { M6DBGFixture.quota() }
        for _ in 0..<30 {
            var model: AntigravitySettingsModel? = AntigravitySettingsModel(
                checkAgain: { AntigravitySettingsObservation(state: .checking) },
                syncNow: { AntigravitySettingsObservation(state: .checking) },
                disable: {}
            )
            weak var weakModel = model
            model?.observe(
                from: connector,
                map: UsageMonitorRuntime.antigravityObservation
            )
            await M6DBGWait.until {
                (await connector.diagnostics()).snapshotObserverCount == 1
            }
            model = nil
            await M6DBGWait.until {
                (await connector.diagnostics()).snapshotObserverCount == 0
            }
            #expect(weakModel == nil)
        }
        await connector.stop()
    }

    @Test
    func unchangedObservationDoesNotRewriteSanitizedSnapshotFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "uma-m6dbg-store-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("connector-snapshots.json")
        let store = AgentConnectorSnapshotStore(url: url)
        let codex = try M6DBGFixture.snapshot(.codex)

        try await store.save([codex])
        let first = try FileManager.default.attributesOfItem(atPath: url.path)
        try await store.save([codex])
        let second = try FileManager.default.attributesOfItem(atPath: url.path)

        #expect(
            first[.systemFileNumber] as? NSNumber
                == second[.systemFileNumber] as? NSNumber
        )
        #expect((await store.load()).map(\.id.rawValue) == [M6DBGProvider.codex.id])
    }

    @Test
    func rendererPackageAndPrivacyContractsRemainM6DBGScoped() throws {
        let renderer = try M6DBGFixture.source("Sources/PreviewRendererTool/main.swift")
        let package = try M6DBGFixture.source("script/package_uma_m6.sh")
        let production = try [
            "Sources/CodexUsageUI/Services/AntigravityReadOnlyCLIClient.swift",
            "Sources/CodexUsageUI/Models/AntigravityQuotaSnapshot.swift",
            "Sources/CodexUsageUI/Connectors/GoogleAntigravityUsageConnector.swift",
        ].map(M6DBGFixture.source).joined(separator: "\n")

        #expect(renderer.contains("--antigravity"))
        #expect(renderer.contains("antigravity.cli"))
        #expect(package.contains("m6dbg-preflight"))
        #expect(package.contains("m6dbg-final"))
        #expect(package.contains("commit-exact"))
        for forbidden in [
            "/credits", "SecItemCopyMatching", "WKWebView", "Cookie",
            "Authorization: Bearer",
        ] {
            #expect(!production.contains(forbidden))
        }
        #expect(production.contains("\"rawJSON\","))
        #expect(production.contains("normalizedConversationID"))
    }

    private func permutations<T>(of values: [T]) -> [[T]] {
        guard let first = values.first else { return [[]] }
        return permutations(of: Array(values.dropFirst())).flatMap { suffix in
            (0...suffix.count).map { index in
                var copy = suffix
                copy.insert(first, at: index)
                return copy
            }
        }
    }
}

private enum M6DBGProvider: CaseIterable, Equatable {
    case codex
    case claude
    case workBuddy
    case antigravity

    var id: String {
        switch self {
        case .codex: "codex.local"
        case .claude: "claude.browserSync"
        case .workBuddy: "workbuddy.accountWeb"
        case .antigravity: "antigravity.cli"
        }
    }

    var name: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .workBuddy: "WorkBuddy"
        case .antigravity: "Google Antigravity"
        }
    }

    var remaining: Double {
        switch self {
        case .codex: 91
        case .claude: 72
        case .workBuddy: 0
        case .antigravity: 58
        }
    }
}

private enum M6DBGFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func allSnapshots() throws -> [AgentUsageSnapshot] {
        try M6DBGProvider.allCases.map { try snapshot($0) }
    }

    static func snapshot(
        _ provider: M6DBGProvider,
        remaining: Double? = nil,
        capturedAt: Date = now
    ) throws -> AgentUsageSnapshot {
        let id = AgentConnectorID(rawValue: provider.id)!
        let channel: AgentUsageChannel
        if provider == .workBuddy {
            let balance = try CreditBalance(
                validatingDecimalRemaining: Decimal(string: "2099.47")!,
                scope: .buddyAISharedPersonal,
                planTier: .personal,
                observedAt: capturedAt,
                provenance: .authenticatedAccountWeb(observedAt: capturedAt)
            )
            channel = AgentUsageChannel(
                id: .account,
                sourceTier: .authorizedReadOnlyRemote,
                sourceVersion: "account-web-1",
                scopes: [.account],
                provenance: .providerReported,
                freshness: .fresh,
                capturedAt: capturedAt,
                coverageNote: nil,
                rateLimitWindows: [],
                accountMetrics: nil,
                localActivityMetrics: nil,
                safeFailure: nil,
                availability: .credits(balance)
            )
        } else {
            let percent = remaining ?? provider.remaining
            channel = AgentUsageChannel(
                id: .account,
                sourceTier: provider == .antigravity
                    ? .officialCLIOrMetadata
                    : .officialLocalService,
                sourceVersion: provider == .antigravity ? "agy-1.1.11" : "fixture-1",
                scopes: [.account],
                provenance: .providerReported,
                freshness: .fresh,
                capturedAt: capturedAt,
                coverageNote: nil,
                rateLimitWindows: [
                    AgentRateLimitWindow(
                        id: "\(provider.id).window",
                        kind: provider == .antigravity ? .other : .sevenDay,
                        displayLabel: provider == .antigravity ? "Primary" : nil,
                        usedPercent: provider == .antigravity ? nil : 100 - percent,
                        remainingPercent: provider == .antigravity ? percent : nil,
                        isUnlimited: false,
                        resetsAt: capturedAt.addingTimeInterval(7_200)
                    ),
                ],
                accountMetrics: nil,
                localActivityMetrics: nil,
                safeFailure: nil
            )
        }
        return AgentUsageSnapshot(
            id: id,
            providerName: provider.name,
            state: .ready,
            capturedAt: capturedAt,
            lastSuccessfulAt: capturedAt,
            freshness: .fresh,
            channels: [channel],
            capabilities: provider == .antigravity
                ? [.sanitizedLastValidRestore, .hiddenFromDesktopAssistant]
                : [],
            safeFailure: nil
        )
    }

    static func failedSnapshot(_ provider: M6DBGProvider) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: provider.id)!,
            providerName: provider.name,
            state: .failed,
            capturedAt: now,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: provider == .antigravity
                ? [.sanitizedLastValidRestore, .hiddenFromDesktopAssistant]
                : [],
            safeFailure: .unavailable
        )
    }

    static func quota(
        remaining: Double = 58,
        includeSecondBucket: Bool = false,
        reverseBuckets: Bool = false,
        missingReset: Bool = false
    ) -> AntigravityQuotaSnapshot {
        var buckets = [
            AntigravityQuotaBucket(
                id: "pool-a",
                displayLabel: "Primary",
                remainingPercent: remaining,
                resetsAt: missingReset ? nil : now.addingTimeInterval(7_200)
            ),
        ]
        if includeSecondBucket {
            buckets.append(
                AntigravityQuotaBucket(
                    id: "pool-b",
                    displayLabel: "Secondary",
                    remainingPercent: 76,
                    resetsAt: missingReset ? nil : now.addingTimeInterval(86_400)
                )
            )
        }
        if reverseBuckets { buckets.reverse() }
        return AntigravityQuotaSnapshot(
            buckets: buckets,
            observedAt: now,
            sourceVersion: "agy-1.1.11"
        )
    }

    static func connector(
        reader: @escaping GoogleAntigravityUsageConnector.QuotaReader
    ) -> GoogleAntigravityUsageConnector {
        GoogleAntigravityUsageConnector(
            readQuota: reader,
            verifyCapability: {},
            autoRefreshEnabled: { true },
            now: { now },
            sleep: { _ in throw CancellationError() },
            refreshInterval: 300
        )
    }

    static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}

private actor M6DBGSequenceReader {
    private var results: [Result<AntigravityQuotaSnapshot, AntigravityCLIClientError>]

    init(results: [Result<AntigravityQuotaSnapshot, AntigravityCLIClientError>]) {
        self.results = results
    }

    func read() throws -> AntigravityQuotaSnapshot {
        guard !results.isEmpty else {
            throw AntigravityCLIClientError.providerUnavailable
        }
        return try results.removeFirst().get()
    }
}

private actor M6DBGCountingReader {
    private(set) var readCount = 0

    func read() -> AntigravityQuotaSnapshot {
        readCount += 1
        return M6DBGFixture.quota()
    }
}

private actor M6DBGCollisionReader {
    private(set) var readCount = 0
    private(set) var maximumConcurrentReadCount = 0
    private var concurrentReadCount = 0
    private var blocksFutureReads = false
    private var continuation: CheckedContinuation<Void, Never>?

    func read() async -> AntigravityQuotaSnapshot {
        readCount += 1
        concurrentReadCount += 1
        maximumConcurrentReadCount = max(
            maximumConcurrentReadCount,
            concurrentReadCount
        )
        if blocksFutureReads {
            await withCheckedContinuation { continuation = $0 }
        }
        concurrentReadCount -= 1
        return M6DBGFixture.quota()
    }

    func blockFutureReads() {
        blocksFutureReads = true
    }

    func release() {
        blocksFutureReads = false
        continuation?.resume()
        continuation = nil
    }
}

private enum M6DBGWait {
    static func until(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async {
        while !(await predicate()) {
            if Task.isCancelled {
                Issue.record("M6DBG observable condition was cancelled")
                return
            }
            await Task.yield()
        }
    }
}

private struct M6DBGDeterministicRandom: RandomNumberGenerator {
    private var state: UInt64 = 0x6d36_6462_672d_6731

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
