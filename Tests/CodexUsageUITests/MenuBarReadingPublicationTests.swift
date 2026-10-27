import Combine
import Foundation
import Testing
@testable import CodexUsageUI

/// The menu bar renders whatever `menuReadingPublisher` delivers. It used to
/// read the store back from inside a `@Published` sink, which runs before the
/// property is assigned, so it showed the previous reading; and it did not
/// watch the user's arrangement at all, so a drag left the menu bar on the
/// old agent until some usage update arrived.
@Suite("Menu bar reading publication", .timeLimit(.minutes(1)))
@MainActor
struct MenuBarReadingPublicationTests {
    private struct Harness {
        let store: UsageStore
        let codex: ReadingConnector
        let claude: ReadingConnector
        let defaultsSuite: String
    }

    private func harness() async throws -> Harness {
        let codex = ReadingConnector(id: CodexUsageConnector.connectorID, name: "Codex", remaining: 70)
        let claude = ReadingConnector(id: ClaudeCodeUsageConnector.connectorID, name: "Claude Code", remaining: 40)
        let registry = try AgentConnectorRegistry(connectors: [codex, claude])
        let suite = "auv-menu-reading-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: codex.id,
            consentDefaults: defaults,
            preferences: ApplicationPreferences(userDefaults: defaults)
        )
        store.grantMonitorConsent()
        await store.searchForAgents()
        try await waitUntil {
            store.productInventory.provider(.codex)?.primaryQuota?.value.remainingPercent == 70
                && store.productInventory.provider(.claude)?.primaryQuota?.value.remainingPercent == 40
        }
        return Harness(store: store, codex: codex, claude: claude, defaultsSuite: suite)
    }

    private func tearDown(_ harness: Harness) async {
        await harness.store.stopAllConnectors()
        UserDefaults().removePersistentDomain(forName: harness.defaultsSuite)
    }

    @Test("The reading delivered is the one the store has just published, not the one before")
    func deliveredReadingIsCurrent() async throws {
        let harness = try await harness()
        var received: [UsageStore.MenuReading] = []
        let subscription = harness.store.menuReadingPublisher.sink { received.append($0) }
        defer { subscription.cancel() }
        #expect(received.last?.provider == .codex)
        #expect(received.last?.percent == 70)

        await harness.codex.setRemaining(55)
        try await waitUntil { harness.store.menuPercent == 55 }
        #expect(received.last?.percent == 55)

        await harness.codex.setRemaining(31)
        try await waitUntil { harness.store.menuPercent == 31 }
        #expect(received.last?.percent == 31)
        await tearDown(harness)
    }

    @Test("Rearranging the list moves the reading at once, with no usage update")
    func rearrangingMovesTheReading() async throws {
        let harness = try await harness()
        var received: [UsageStore.MenuReading] = []
        let subscription = harness.store.menuReadingPublisher.sink { received.append($0) }
        defer { subscription.cancel() }
        #expect(received.last?.provider == .codex)

        harness.store.moveAgent(.claude, onto: .codex)
        #expect(received.last?.provider == .claude)
        #expect(received.last?.percent == 40)

        harness.store.moveAgent(.codex, onto: .claude)
        #expect(received.last?.provider == .codex)
        #expect(received.last?.percent == 70)
        await tearDown(harness)
    }

    @Test("When the top agent has no reading, the menu bar falls back down the order")
    func fallsBackDownTheOrder() async throws {
        let harness = try await harness()
        var received: [UsageStore.MenuReading] = []
        let subscription = harness.store.menuReadingPublisher.sink { received.append($0) }
        defer { subscription.cancel() }
        harness.store.moveAgent(.claude, onto: .codex)
        #expect(received.last?.provider == .claude)

        await harness.claude.setRemaining(nil)
        try await waitUntil {
            harness.store.productInventory.provider(.claude)?.primaryQuota?.value.remainingPercent == nil
        }
        #expect(received.last?.provider == .codex)
        #expect(received.last?.percent == 70)
        await tearDown(harness)
    }

    @Test("An unchanged reading is not delivered again")
    func unchangedReadingIsNotRedelivered() async throws {
        let harness = try await harness()
        var received: [UsageStore.MenuReading] = []
        let subscription = harness.store.menuReadingPublisher.sink { received.append($0) }
        defer { subscription.cancel() }
        let before = received.count

        // Claude's figure changes, but the menu bar shows Codex's, so nothing
        // the menu bar renders has changed.
        await harness.claude.setRemaining(35)
        try await waitUntil {
            harness.store.productInventory.provider(.claude)?.primaryQuota?.value.remainingPercent == 35
        }
        #expect(received.count == before)
        await tearDown(harness)
    }

    @Test("A chosen agent keeps the menu bar, with a dash while it has no reading")
    func pinnedAgentKeepsTheMenuBar() async throws {
        let harness = try await harness()
        var received: [UsageStore.MenuReading] = []
        let subscription = harness.store.menuReadingPublisher.sink { received.append($0) }
        defer { subscription.cancel() }
        #expect(received.last?.provider == .codex)

        harness.store.setMenuBarAgent(.claude)
        #expect(received.last?.provider == .claude)
        #expect(received.last?.percent == 40)
        let saved = ApplicationPreferences(userDefaults: try #require(UserDefaults(suiteName: harness.defaultsSuite)))
        #expect(saved.value(for: UMAApplicationPreferenceKeys.menuBarAgent) == "claude")

        await harness.claude.setRemaining(nil)
        try await waitUntil {
            harness.store.productInventory.provider(.claude)?.primaryQuota?.value.remainingPercent == nil
        }
        #expect(received.last?.provider == .claude)
        #expect(received.last?.percent == nil)

        harness.store.setMenuBarAgent(nil)
        #expect(received.last?.provider == .codex)
        #expect(received.last?.percent == 70)
        await tearDown(harness)
    }

    @Test("The Desktop Assistant and overview cards follow the arrangement")
    func cardsFollowTheArrangement() async throws {
        let harness = try await harness()
        let store = harness.store
        let claudeID = ClaudeCodeUsageConnector.connectorID.rawValue
        let codexID = CodexUsageConnector.connectorID.rawValue
        try await waitUntil { store.assistantPresentationCards.count == 2 }

        store.moveAgent(.claude, onto: .codex)
        #expect(store.assistantPresentationCards.map(\.id) == [claudeID, codexID])
        #expect(store.overviewPresentationCards.first?.id == claudeID)
        #expect(store.assistantPresentationCards(arrangedBy: ["codex", "claude"]).map(\.id)
            == [codexID, claudeID])

        store.moveAgent(.claude, by: 1)
        #expect(store.orderedWorkspaceProviders.map(\.id) == [.codex, .claude])
        store.moveAgent(.claude, by: 1)
        #expect(store.orderedWorkspaceProviders.map(\.id) == [.codex, .claude])
        store.moveAgent(.claude, by: -1)
        #expect(store.orderedWorkspaceProviders.map(\.id) == [.claude, .codex])

        store.resetAgentOrder()
        #expect(store.agentOrder.isEmpty)
        let saved = ApplicationPreferences(userDefaults: try #require(UserDefaults(suiteName: harness.defaultsSuite)))
        #expect(saved.value(for: UMAApplicationPreferenceKeys.agentOrder) == [])
        #expect(store.orderedWorkspaceProviders.map(\.id) == [.codex, .claude])
        await tearDown(harness)
    }

    private func waitUntil(
        timeout: TimeInterval = 10,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Condition not met within \(timeout)s")
    }
}

/// A connector whose single remaining-percent reading the test sets.
private actor ReadingConnector: AgentUsageConnector {
    nonisolated let id: AgentConnectorID
    nonisolated let descriptor: AgentConnectorDescriptor
    private let name: String
    private var remaining: Double?
    private var revision = 0
    private var continuations: [AsyncStream<AgentUsageSnapshot>.Continuation] = []

    init(id: AgentConnectorID, name: String, remaining: Double?) {
        self.id = id
        self.name = name
        self.remaining = remaining
        descriptor = AgentConnectorDescriptor(
            id: id,
            providerName: name,
            officialSource: "menu reading fixture",
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "menu-reading-fixture",
            supportedScopes: [.account],
            capabilities: [.rateLimits],
            configurationRequirements: [.officialManagedSession],
            privacyAllowlist: ["syntheticReading"],
            supportsRestore: false,
            supportsUninstall: false,
            unsupportedFields: [],
            expectedRuntime: .none,
            localSourceClass: .admittedStructuredLocal,
            usageReadContract: .currentStructuredLocalRead
        )!
    }

    func setRemaining(_ value: Double?) {
        remaining = value
        revision += 1
        let current = snapshot()
        continuations.forEach { $0.yield(current) }
    }

    private func snapshot() -> AgentUsageSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000 + Double(revision))
        let windows = remaining.map {
            [AgentRateLimitWindow(
                id: "seven-day",
                kind: .sevenDay,
                displayLabel: "7D",
                usedPercent: nil,
                remainingPercent: $0,
                isUnlimited: false,
                resetsAt: nil
            )]
        } ?? []
        return AgentUsageSnapshot(
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
                    sourceVersion: "menu-reading-fixture",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: now,
                    coverageNote: nil,
                    rateLimitWindows: windows,
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                ),
            ],
            capabilities: [.rateLimits],
            safeFailure: nil
        )
    }

    func probe() async -> AgentConnectorProbe { AgentConnectorProbe(state: .ready, safeFailure: nil) }
    func start() async {}
    func refresh() async {}
    func perform(_ command: AgentConnectorCommand) async {}
    func stop() async {}
    func currentSnapshot() async -> AgentUsageSnapshot { snapshot() }
    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            continuation.yield(snapshot())
            continuations.append(continuation)
        }
    }
}
