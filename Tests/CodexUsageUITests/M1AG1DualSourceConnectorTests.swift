import Foundation
import Testing
@testable import CodexUsageUI

struct M1AG1DualSourceConnectorTests {
    @Test
    func panelBudgetIncludesBothSourceRowsWithoutClippingTheExistingFooter() {
        #expect(
            UsagePanelMetrics.height >= UsagePanelMetrics.preferredHeight(
                showUsageSummary: true,
                showRecentTasks: true,
                showAPICost: true
            )
        )
    }

    @Test
    func appServerUsesBoundedJSONLineFraming() throws {
        let body = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#.utf8)
        let framed = JSONLineJSONRPCFraming.encode(body)
        #expect(framed.last == 0x0A)

        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("message.bin")
        try framed.write(to: path)
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }
        #expect(JSONLineJSONRPCFraming.readMessage(from: handle) == body)

        let second = Data(#"{"jsonrpc":"2.0","id":2}"#.utf8)
        try (JSONLineJSONRPCFraming.encode(body) + JSONLineJSONRPCFraming.encode(second)).write(to: path)
        let multiFrameHandle = try FileHandle(forReadingFrom: path)
        defer { try? multiFrameHandle.close() }
        #expect(JSONLineJSONRPCFraming.readMessage(from: multiFrameHandle) == body)
        #expect(JSONLineJSONRPCFraming.readMessage(from: multiFrameHandle) == second)

        try (Data(repeating: 0x61, count: JSONLineJSONRPCFraming.maximumMessageBytes + 1) + Data([0x0A])).write(to: path)
        let oversizedHandle = try FileHandle(forReadingFrom: path)
        defer { try? oversizedHandle.close() }
        #expect(JSONLineJSONRPCFraming.readMessage(from: oversizedHandle) == nil)

        try Data(#"{"jsonrpc":"2.0"}"#.utf8).write(to: path)
        let truncatedHandle = try FileHandle(forReadingFrom: path)
        defer { try? truncatedHandle.close() }
        #expect(JSONLineJSONRPCFraming.readMessage(from: truncatedHandle) == nil)
    }

    @Test
    func localReaderUsesOnlyMetadataAndExcludesSymlinks() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let ledger = directory.appendingPathComponent("ledger.json")
        let session = sessions.appendingPathComponent("2026-07-16-session.jsonl")
        try sessionFixture(input: 100, cached: 20, output: 40, total: 140).write(to: session)

        let outside = directory.appendingPathComponent("outside.jsonl")
        try sessionFixture(input: 9_999, cached: 0, output: 0, total: 9_999).write(to: outside)
        let link = sessions.appendingPathComponent("linked.jsonl")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: outside.path)

        let reader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: ledger)
        let first = reader.read(now: fixedDate())
        #expect(first.availability == .available)
        #expect(first.discoveredFileCount == 2)
        #expect(first.readableFileCount == 1)
        #expect(first.excludedFileCount == 1)
        #expect(first.tasks.count == 1)
        #expect(first.tasks[0].totalTokens == 140)
        #expect(first.apiEquivalentCost?.observedTokens == 140)
        #expect(first.source == "This Mac: Codex session metadata")
        #expect(first.scope.contains("metadata-only"))

        let linkedRoot = directory.appendingPathComponent("linked-root", isDirectory: true)
        try FileManager.default.createSymbolicLink(atPath: linkedRoot.path, withDestinationPath: sessions.path)
        let rootLinkResult = CodexLocalActivityReader(sessionRoots: [linkedRoot], ledgerURL: ledger).read(now: fixedDate())
        #expect(rootLinkResult.readableFileCount == 0)

        // The reader persists only a high-water token checkpoint. Replacing a
        // tail with less data cannot lower it or cause a later double-charge.
        try sessionFixture(input: 80, cached: 10, output: 20, total: 100).write(to: session)
        #expect(reader.read(now: fixedDate()).apiEquivalentCost?.observedTokens == 140)
        try sessionFixture(input: 150, cached: 25, output: 60, total: 210).write(to: session)
        #expect(reader.read(now: fixedDate()).apiEquivalentCost?.observedTokens == 210)
    }

    @Test
    func ledgerRestoresValidBackupWithoutResettingHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = APICostLedgerStore(url: directory.appendingPathComponent("ledger.json"))
        let summary = SessionTokenSummary(model: "gpt-5.6-terra", inputTokens: 100, cachedInputTokens: 0, outputTokens: 10, totalTokens: 110)
        var ledger = APICostLedger()
        _ = ledger.observe(sessionID: "safe", summary: summary, initialUsageDay: "2026-07-16", incrementalUsageDay: "2026-07-16", price: APIModelPrice.price(for: summary.model))
        try store.save(ledger)
        _ = ledger.observe(sessionID: "safe", summary: .init(model: summary.model, inputTokens: 200, cachedInputTokens: 0, outputTokens: 20, totalTokens: 220), initialUsageDay: "2026-07-16", incrementalUsageDay: "2026-07-16", price: APIModelPrice.price(for: summary.model))
        try store.save(ledger)
        try Data("corrupt".utf8).write(to: store.url)
        let recovered = try store.load()
        #expect(recovered.estimate(sevenDayKeys: ["2026-07-16"])?.observedTokens == 110)
        #expect((try? JSONDecoder().decode(APICostLedger.self, from: Data(contentsOf: store.url))) != nil)

        try Data("corrupt".utf8).write(to: store.url)
        try Data("corrupt".utf8).write(to: store.url.appendingPathExtension("backup"))
        #expect(throws: APICostLedgerStore.StoreError.self) { try store.load() }
    }

    @Test @MainActor
    func unavailableAccountHidesTheProviderDespiteLocalMetadata() async {
        let local = CodexLocalActivitySnapshot(
            availability: .available,
            source: "This Mac: Codex session metadata",
            scope: "sessions + archived_sessions; metadata-only tail scan",
            capturedAt: fixedDate(),
            discoveredFileCount: 1,
            readableFileCount: 1,
            excludedFileCount: 0,
            tasks: [.init(stableID: "fixture", modifiedAt: fixedDate(), totalTokens: 321)],
            apiEquivalentCost: nil
        )
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            client: UnauthorizedClient(),
            localActivityReader: FixedLocalReader(snapshot: local),
            consentDefaults: UserDefaults(suiteName: "m1a-g1-\(UUID().uuidString)")
        )
        store.grantMonitorConsent()
        await store.refresh()
        for _ in 0..<40 where store.isRefreshing {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(store.providerSnapshots.isEmpty)
        #expect(store.presentationCards.isEmpty)
        #expect(store.snapshot.providerSource == nil)
        #expect(store.snapshot.localSource == nil)
        #expect(!store.hasPriorRealSnapshot)
    }

    @Test @MainActor
    func providerRefreshFailureRemovesStaleAndIndependentLocalPresentation() async {
        let firstLocal = localSnapshot(tokenCount: 10)
        let secondLocal = localSnapshot(tokenCount: 20)
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            client: SequencedProviderClient(results: [.success(liveUsage()), .failure(CodexUsageClientError(.processExited))]),
            localActivityReader: SequenceLocalReader(snapshots: [firstLocal, secondLocal]),
            consentDefaults: UserDefaults(suiteName: "m1a-g1-stale-\(UUID().uuidString)")
        )
        store.grantMonitorConsent()
        await store.refresh()
        await store.refresh()
        for _ in 0..<40 where store.isRefreshing {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(store.providerSnapshots.isEmpty)
        #expect(store.presentationCards.isEmpty)
        #expect(store.snapshot.providerSource == nil)
        #expect(store.snapshot.localSource == nil)
    }

    @Test @MainActor
    func firstProviderFailureHidesIndependentLocalActivity() async {
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            client: SequencedProviderClient(results: [.failure(CodexUsageClientError(.processExited))]),
            localActivityReader: FixedLocalReader(snapshot: localSnapshot(tokenCount: 77)),
            consentDefaults: UserDefaults(suiteName: "m1a-g1-first-failure-\(UUID().uuidString)")
        )
        store.grantMonitorConsent()
        await store.refresh()
        for _ in 0..<40 where store.isRefreshing {
            try? await Task.sleep(for: .milliseconds(5))
        }

        let presentation = CodexConnectionPresentation.make(
            state: store.currentState,
            decision: store.monitorConsentDecision,
            hasPriorRealSnapshot: store.hasPriorRealSnapshot,
            language: store.language
        )
        #expect(store.providerSnapshots.isEmpty)
        #expect(store.presentationCards.isEmpty)
        #expect(store.snapshot.localSource == nil)
        #expect(!presentation.showsRealData)
    }

    @Test @MainActor
    func disconnectDuringLocalReadRetainsNoDataAfterTheIndependentProviderStarts() async {
        let localReader = BlockingLocalReader(snapshot: localSnapshot(tokenCount: 88))
        let client = RecordingProviderClient()
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            client: client,
            localActivityReader: localReader,
            consentDefaults: UserDefaults(suiteName: "m1a-g1-cancel-refresh-\(UUID().uuidString)")
        )
        store.grantMonitorConsent()

        let refresh = Task { @MainActor in await store.refresh() }
        await localReader.waitUntilReading()
        await store.disconnectAndForgetConsent()
        localReader.resume()
        await refresh.value

        #expect(client.fetchUsageCallCount == 1)
        #expect(client.disconnectCallCount == 1)
        #expect(store.hasPriorRealSnapshot == false)
        #expect(store.currentState == .notAuthorizedByMonitor)
    }

    @Test @MainActor
    func disconnectDuringLocalReadDoesNotRetainAnIndependentAccountCheck() async {
        let localReader = BlockingLocalReader(snapshot: localSnapshot(tokenCount: 89))
        let client = RecordingProviderClient()
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            client: client,
            localActivityReader: localReader,
            consentDefaults: UserDefaults(suiteName: "m1a-g1-cancel-account-\(UUID().uuidString)")
        )
        store.handleLocalAccessDecision(true)
        await localReader.waitUntilReading()
        await store.disconnectAndForgetConsent()
        localReader.resume()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(client.accountReadCallCount == 1)
        #expect(client.fetchUsageCallCount == 1)
        #expect(client.disconnectCallCount == 1)
        #expect(store.hasPriorRealSnapshot == false)
        #expect(store.currentState == .notAuthorizedByMonitor)
    }

    @Test @MainActor
    func rejectedLocalAccessDecisionRemainsDisconnectedWithoutAnAccountRead() async {
        let client = RecordingProviderClient()
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            client: client,
            localActivityReader: FixedLocalReader(snapshot: localSnapshot(tokenCount: 91)),
            consentDefaults: UserDefaults(suiteName: "m1a-g1-declined-\(UUID().uuidString)")
        )

        store.handleLocalAccessDecision(false)
        try? await Task.sleep(for: .milliseconds(20))

        #expect(store.currentState == .notAuthorizedByMonitor)
        #expect(store.monitorConsentGranted == false)
        #expect(client.accountReadCallCount == 0)
        #expect(client.fetchUsageCallCount == 0)
    }

    @Test @MainActor
    func acceptedLocalAccessDecisionRetainsOneConnectionTaskAcrossThePanelBoundary() async {
        let localReader = BlockingLocalReader(snapshot: localSnapshot(tokenCount: 92))
        let client = RecordingProviderClient()
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            client: client,
            localActivityReader: localReader,
            consentDefaults: UserDefaults(suiteName: "m1a-g1-approved-\(UUID().uuidString)")
        )

        store.handleLocalAccessDecision(true)
        await localReader.waitUntilReading()
        // A second accepted callback while the first task is suspended must
        // not create another account read or child session.
        store.handleLocalAccessDecision(true)
        localReader.resume()

        for _ in 0..<40 where store.currentState != .ready {
            try? await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<40 where !store.allowsManualRefresh {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(store.monitorConsentGranted)
        #expect(client.accountReadCallCount == 1)
        #expect(client.fetchUsageCallCount == 1)
        #expect(store.currentState == .ready)
        #expect(store.allowsManualRefresh)
    }

    @Test @MainActor
    func connectionStartsAccountReadBeforeSlowIndependentLocalMetadata() async {
        let localReader = BlockingLocalReader(snapshot: localSnapshot(tokenCount: 93))
        let client = RecordingProviderClient()
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            client: client,
            localActivityReader: localReader,
            consentDefaults: UserDefaults(suiteName: "m1a-g1-independent-local-\(UUID().uuidString)")
        )

        store.handleLocalAccessDecision(true)
        await localReader.waitUntilReading()
        for _ in 0..<40 where client.accountReadCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<40 where store.isRefreshing {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(client.accountReadCallCount == 1)
        #expect(client.fetchUsageCallCount == 1)
        #expect(store.currentState == .ready)
        #expect(store.allowsManualRefresh)

        await store.disconnectAndForgetConsent()
        localReader.resume()
    }

    @Test
    func standardRateLimitPresentationKeepsTheMostRestrictiveWeeklyWindow() {
        let usage = CodexLiveUsage(
            rateLimits: .init(
                planType: "pro",
                windows: [
                    .init(id: "weekly-unused", usedPercent: 0, windowDurationMinutes: 10_080, resetsAt: nil),
                    .init(id: "weekly-active", usedPercent: 96, windowDurationMinutes: 10_080, resetsAt: nil),
                    .init(id: "five-hour", usedPercent: 12, windowDurationMinutes: 300, resetsAt: nil)
                ]
            ),
            availableResetCount: nil,
            lifetimeTokens: nil,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        )

        let snapshot = UsageSnapshot(live: usage, language: .english)
        #expect(snapshot.periods.map(\.title) == ["5-Hour Limit", "7-Day Limit"])
        #expect(snapshot.periods.map(\.remainingPercent) == [88, 4])
    }

    @Test
    func unlimitedFiveHourWindowRetainsItsBarAndUsesTheExplicitUnlimitedStatus() {
        let usage = CodexLiveUsage(
            rateLimits: .init(
                planType: "pro",
                windows: [
                    .init(id: "five-hour-special", creditsUnlimited: true, usedPercent: 33, windowDurationMinutes: 300, resetsAt: nil),
                    .init(id: "weekly", usedPercent: 96, windowDurationMinutes: 10_080, resetsAt: nil)
                ]
            ),
            availableResetCount: nil,
            lifetimeTokens: nil,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        )

        let snapshot = UsageSnapshot(live: usage, language: .english)
        #expect(snapshot.periods.map(\.title) == ["5-Hour Limit", "7-Day Limit"])
        #expect(snapshot.periods.first?.remainingPercent == 67)
        #expect(snapshot.periods.first?.isUnlimited == true)
        #expect(snapshot.periods.last?.isUnlimited == false)
    }

    @Test
    func authoritativeUnlimitedFiveHourWinsOverDuplicateOrdinaryWindow() {
        let usage = CodexLiveUsage(
            rateLimits: .init(
                planType: "pro",
                windows: [
                    .init(id: "ordinary-five-hour", usedPercent: 0, windowDurationMinutes: 300, resetsAt: nil),
                    .init(id: "special-five-hour", creditsUnlimited: true, usedPercent: 0, windowDurationMinutes: 300, resetsAt: nil),
                    .init(id: "weekly", usedPercent: 96, windowDurationMinutes: 10_080, resetsAt: nil)
                ]
            ),
            availableResetCount: nil,
            lifetimeTokens: nil,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        )

        let snapshot = UsageSnapshot(live: usage, language: .english)
        #expect(snapshot.periods.map(\.title) == ["5-Hour Limit", "7-Day Limit"])
        #expect(snapshot.periods.first?.isUnlimited == true)
        #expect(snapshot.periods.first?.remainingPercent == 100)
    }

    @Test
    func authoritativeWeeklyWindowRetainsTheUnlimitedFiveHourRowWhenTheProviderOmitsIt() {
        let usage = CodexLiveUsage(
            rateLimits: .init(
                planType: "pro",
                windows: [.init(id: "weekly", usedPercent: 2, windowDurationMinutes: 10_080, resetsAt: nil)]
            ),
            availableResetCount: nil,
            lifetimeTokens: nil,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        )

        let snapshot = UsageSnapshot(live: usage, language: .english)
        #expect(snapshot.periods.map(\.title) == ["5-Hour Limit", "7-Day Limit"])
        #expect(snapshot.periods.first?.isUnlimited == true)
        #expect(snapshot.periods.first?.remainingPercent == 100)
        #expect(snapshot.periods.last?.remainingPercent == 98)
    }

    @Test @MainActor
    func overlappingManualRefreshesCoalesceIntoOneProviderRequest() async {
        let client = CoalescingProviderClient()
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            client: client,
            localActivityReader: FixedLocalReader(snapshot: localSnapshot(tokenCount: 90)),
            consentDefaults: UserDefaults(suiteName: "m1a-g1-coalescing-\(UUID().uuidString)")
        )
        store.grantMonitorConsent()

        let firstRefresh = Task { @MainActor in await store.refresh() }
        await client.waitUntilFirstFetchStarts()
        let secondRefresh = Task { @MainActor in await store.refresh() }
        await Task.yield()
        #expect(await client.fetchUsageCallCount == 1)

        await client.finishFirstFetch()
        await firstRefresh.value
        await secondRefresh.value

        #expect(await client.fetchUsageCallCount == 1)
        #expect(store.currentState == .ready)
        #expect(store.snapshot.providerSource?.isAvailable == true)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func fixedDate() -> Date {
        Date(timeIntervalSince1970: 1_784_332_800)
    }

    private func sessionFixture(input: Int64, cached: Int64, output: Int64, total: Int64) -> Data {
        Data("""
        {"type":"turn_context","payload":{"model":"gpt-5.6-terra","message":"never retained"}}
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"total_tokens":\(total)}}}}
        """.utf8)
    }

    private func localSnapshot(tokenCount: Int64) -> CodexLocalActivitySnapshot {
        .init(
            availability: .available,
            source: "This Mac: Codex session metadata",
            scope: "sessions + archived_sessions; metadata-only tail scan",
            capturedAt: fixedDate(),
            discoveredFileCount: 1,
            readableFileCount: 1,
            excludedFileCount: 0,
            tasks: [.init(stableID: "fixture-\(tokenCount)", modifiedAt: fixedDate(), totalTokens: tokenCount)],
            apiEquivalentCost: nil
        )
    }

    private func liveUsage() -> CodexLiveUsage {
        .init(
            rateLimits: .init(planType: "pro", windows: []),
            availableResetCount: nil,
            lifetimeTokens: 123,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        )
    }
}

private struct FixedLocalReader: CodexLocalActivityReading, Sendable {
    let snapshot: CodexLocalActivitySnapshot
    func read(now: Date) -> CodexLocalActivitySnapshot { snapshot }
}

private final class SequenceLocalReader: CodexLocalActivityReading, @unchecked Sendable {
    private var snapshots: [CodexLocalActivitySnapshot]
    init(snapshots: [CodexLocalActivitySnapshot]) { self.snapshots = snapshots }
    func read(now: Date) -> CodexLocalActivitySnapshot {
        snapshots.isEmpty ? .unavailable(now: now) : snapshots.removeFirst()
    }
}

private final class SequencedProviderClient: CodexUsageClient, @unchecked Sendable {
    private var results: [Result<CodexLiveUsage, Error>]
    init(results: [Result<CodexLiveUsage, Error>]) { self.results = results }
    func checkLocalAccountAvailability() async throws -> Bool { true }
    func fetchUsage() async throws -> CodexLiveUsage { try results.removeFirst().get() }
    func beginManagedLogin() async throws {}
    func cancelManagedLogin() async throws {}
    func disconnect() async {}
    func takeUsageRefreshRequest() async -> Bool { false }
    func takeLocalAccountUpdateSignal() async -> Bool { false }
    func connectionState() async -> CodexConnectionState { .recoverableFailure(.processExited) }
    func managedAuthorizationWaitTime() async -> TimeInterval? { nil }
}

private final class BlockingLocalReader: CodexLocalActivityReading, @unchecked Sendable {
    private let snapshot: CodexLocalActivitySnapshot
    private let condition = NSCondition()
    private var hasStarted = false
    private var isResumed = false

    init(snapshot: CodexLocalActivitySnapshot) {
        self.snapshot = snapshot
    }

    func read(now: Date) -> CodexLocalActivitySnapshot {
        condition.lock()
        hasStarted = true
        condition.broadcast()
        while !isResumed {
            condition.wait()
        }
        condition.unlock()
        return snapshot
    }

    func waitUntilReading() async {
        while true {
            if startedReading() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func resume() {
        condition.lock()
        isResumed = true
        condition.broadcast()
        condition.unlock()
    }

    private func startedReading() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return hasStarted
    }
}

private final class RecordingProviderClient: CodexUsageClient, @unchecked Sendable {
    private(set) var accountReadCallCount = 0
    private(set) var fetchUsageCallCount = 0
    private(set) var disconnectCallCount = 0

    func checkLocalAccountAvailability() async throws -> Bool {
        accountReadCallCount += 1
        return true
    }

    func fetchUsage() async throws -> CodexLiveUsage {
        fetchUsageCallCount += 1
        return .init(rateLimits: .init(planType: "test", windows: []), availableResetCount: nil, lifetimeTokens: nil, dailyUsage: nil, recentActivityCount: 0, apiCostEstimate: nil)
    }

    func beginManagedLogin() async throws {}
    func cancelManagedLogin() async throws {}

    func disconnect() async {
        disconnectCallCount += 1
    }

    func takeUsageRefreshRequest() async -> Bool { false }
    func takeLocalAccountUpdateSignal() async -> Bool { false }
    func connectionState() async -> CodexConnectionState { .idle }
    func managedAuthorizationWaitTime() async -> TimeInterval? { nil }
}

private actor CoalescingProviderClient: CodexUsageClient {
    private var fetchContinuation: CheckedContinuation<CodexLiveUsage, Never>?
    private var firstFetchWaiter: CheckedContinuation<Void, Never>?
    private(set) var fetchUsageCallCount = 0

    func checkLocalAccountAvailability() async throws -> Bool { true }

    func fetchUsage() async throws -> CodexLiveUsage {
        fetchUsageCallCount += 1
        firstFetchWaiter?.resume()
        firstFetchWaiter = nil
        return await withCheckedContinuation { continuation in
            fetchContinuation = continuation
        }
    }

    func waitUntilFirstFetchStarts() async {
        guard fetchUsageCallCount == 0 else { return }
        await withCheckedContinuation { continuation in
            firstFetchWaiter = continuation
        }
    }

    func finishFirstFetch() {
        let continuation = fetchContinuation
        fetchContinuation = nil
        continuation?.resume(returning: .init(
            rateLimits: .init(planType: "test", windows: []),
            availableResetCount: nil,
            lifetimeTokens: nil,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        ))
    }

    func beginManagedLogin() async throws {}
    func cancelManagedLogin() async throws {}
    func disconnect() async {}
    func takeUsageRefreshRequest() async -> Bool { false }
    func takeLocalAccountUpdateSignal() async -> Bool { false }
    func connectionState() async -> CodexConnectionState { .idle }
    func managedAuthorizationWaitTime() async -> TimeInterval? { nil }
}

private struct UnauthorizedClient: CodexUsageClient {
    func checkLocalAccountAvailability() async throws -> Bool { false }
    func fetchUsage() async throws -> CodexLiveUsage {
        throw CodexUsageClientError(.accountAuthorizationRequired)
    }
    func beginManagedLogin() async throws {}
    func cancelManagedLogin() async throws {}
    func disconnect() async {}
    func takeUsageRefreshRequest() async -> Bool { false }
    func takeLocalAccountUpdateSignal() async -> Bool { false }
    func connectionState() async -> CodexConnectionState { .officialCodexSignInRequired }
    func managedAuthorizationWaitTime() async -> TimeInterval? { nil }
}
