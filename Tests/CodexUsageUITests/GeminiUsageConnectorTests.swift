import ClaudeBrowserBridgeProtocol
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Gemini web usage connector")
struct GeminiUsageConnectorTests {
    private static let observedAt = "2026-11-24T05:45:00.000Z"

    private static func observation(
        current: Double = 0,
        weekly: Double = 4,
        plan: String? = "pro"
    ) -> GeminiBrowserObservation {
        GeminiBrowserObservation(
            buckets: [
                GeminiBrowserBucket(
                    bucketID: "current", period: .unknown, usedPercentage: current,
                    resetAt: "2026-11-24T10:18:00.000Z"
                ),
                GeminiBrowserBucket(
                    bucketID: "weekly", period: .weekly, usedPercentage: weekly,
                    resetAt: "2026-11-26T01:18:00.000Z"
                ),
            ],
            planLabel: plan,
            observedAt: observedAt
        )
    }

    private actor Script {
        var results: [Result<GeminiBrowserObservation, GeminiBrowserReadError>]
        var reads = 0
        init(_ results: [Result<GeminiBrowserObservation, GeminiBrowserReadError>]) {
            self.results = results
        }
        func next() throws -> GeminiBrowserObservation {
            reads += 1
            let result = results.isEmpty ? .failure(.timedOut) : results.removeFirst()
            return try result.get()
        }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_795_000_000)
        func now() -> Date { lock.withLock { value } }
        func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
    }

    @Test("The page's two rows become 5H and 7D, used percentages, resets and plan")
    func snapshotMapping() throws {
        let snapshot = try #require(GeminiUsageConnector.makeSnapshot(
            Self.observation(current: 12, weekly: 4), capturedAt: Date()
        ))
        #expect(snapshot.state == .ready)
        let account = try #require(snapshot.channels.first { $0.id == .account })
        #expect(account.provenance == .providerReported)
        #expect(account.sourceVersion == GeminiUsageConnector.sourceVersion)
        #expect(account.rateLimitWindows.map(\.kind) == [.fiveHour, .sevenDay])
        #expect(account.rateLimitWindows.map(\.usedPercent) == [12, 4])
        #expect(account.rateLimitWindows[0].resetsAt != nil)
        #expect(account.accountMetrics?.planLabel == "pro")
    }

    @Test("A Gemini read is no Antigravity read")
    func distinctIdentity() {
        #expect(GeminiUsageConnector.connectorID.rawValue == "gemini.browserUsage")
        #expect(ProviderProductStatePolicy.productID(for: GeminiUsageConnector.connectorID) == .gemini)
        #expect(ProviderProductStatePolicy.productID(for: GoogleAntigravityUsageConnector.connectorID) == .antigravity)
        #expect(ProviderProductID.gemini.displayName == "Gemini")
        #expect(ProviderProductID.gemini.settingsProviderID == "gemini")
    }

    @Test("Gemini starts off and is listed in Settings")
    @MainActor
    func startsOff() {
        let defaults = AgentProviderSettingsPayload.defaults(for: AgentPreferenceRecord.geminiProviderID)
        #expect(defaults.monitoring.monitoringEnabled == false)
        #expect(AgentProviderSettingsPayload.defaults(for: AgentPreferenceRecord.claudeProviderID)
            .monitoring.monitoringEnabled)
    }

    @Test("Only Gemini's own plan words are admitted")
    func planAdmission() {
        #expect(LowRemainingUsagePolicy.admittedPlanIdentifier(providerID: "gemini.browserUsage", label: "Pro") == "pro")
        #expect(LowRemainingUsagePolicy.admittedPlanIdentifier(providerID: "gemini.browserUsage", label: "max") == nil)
        #expect(LowRemainingUsagePolicy.lowThresholdPercent(providerID: "gemini", admittedPlan: "ultra") == 10)
        #expect(DesktopAgentLogoAsset.resolve(providerID: "gemini.browserUsage") == .gemini)
    }

    @Test("Without consent nothing is read")
    func consentGatesReads() async {
        let script = Script([.success(Self.observation())])
        let connector = GeminiUsageConnector(
            readUsage: { try await script.next() },
            hasConsent: { false }
        )
        #expect(await connector.permitsRead(for: .applicationLaunch) == false)
        await connector.start()
        await connector.perform(.refresh)
        #expect(await script.reads == 0)
        #expect(await connector.probe().state == .authenticationRequired)
    }

    @Test("A read publishes a fresh snapshot; a failed read keeps it, never as fresh")
    func retainsLastGood() async {
        let clock = Clock()
        let script = Script([.success(Self.observation()), .failure(.timedOut)])
        let connector = GeminiUsageConnector(
            readUsage: { try await script.next() },
            hasConsent: { true },
            now: { clock.now() }
        )
        await connector.start()
        await connector.perform(.refresh)
        var snapshot = await connector.currentSnapshot()
        #expect(snapshot.freshness == .fresh)
        #expect(snapshot.hasValidData)

        clock.advance(60)
        await connector.refresh(trigger: .manual)
        snapshot = await connector.currentSnapshot()
        #expect(snapshot.freshness == .cached)
        #expect(snapshot.safeFailure == .timedOut)
        #expect(snapshot.hasValidData)
        #expect(await connector.lastReadError() == .timedOut)
    }

    @Test("Sign-in and site access stop timer reads until the person acts")
    func authenticationSuspendsTimer() async {
        let clock = Clock()
        let script = Script([.failure(.signInRequired), .success(Self.observation())])
        let connector = GeminiUsageConnector(
            readUsage: { try await script.next() },
            hasConsent: { true },
            now: { clock.now() }
        )
        await connector.start()
        await connector.perform(.refresh)
        #expect(await connector.currentSnapshot().state == .authenticationRequired)
        clock.advance(3_600)
        await connector.refresh(trigger: .timer)
        #expect(await script.reads == 1)
        await connector.refresh(trigger: .manual)
        #expect(await script.reads == 2)
        #expect(await connector.currentSnapshot().state == .ready)
    }

    @Test("Timer reads are at least five minutes apart")
    func timerReadsAreSpaced() async {
        let clock = Clock()
        let script = Script([.success(Self.observation()), .success(Self.observation())])
        let connector = GeminiUsageConnector(
            readUsage: { try await script.next() },
            hasConsent: { true },
            now: { clock.now() }
        )
        await connector.start()
        await connector.refresh(trigger: .timer)
        clock.advance(60)
        await connector.refresh(trigger: .timer)
        #expect(await script.reads == 1)
        clock.advance(5 * 60)
        await connector.refresh(trigger: .timer)
        #expect(await script.reads == 2)
    }

    @Test("Settings says what the person has to do")
    func settingsState() throws {
        let fresh = try #require(GeminiUsageConnector.makeSnapshot(Self.observation(), capturedAt: Date()))
        #expect(GeminiSettingsModel.state(for: fresh, lastError: nil, enabled: false) == .off)
        if case .fresh = GeminiSettingsModel.state(for: fresh, lastError: nil, enabled: true) {} else {
            Issue.record("expected fresh")
        }
        let auth = AgentUsageSnapshot(
            id: GeminiUsageConnector.connectorID, providerName: "Gemini",
            state: .authenticationRequired, capturedAt: Date(), lastSuccessfulAt: nil,
            freshness: .unavailable, channels: [], capabilities: GeminiUsageConnector.capabilities,
            safeFailure: .authorizationRequired
        )
        #expect(GeminiSettingsModel.state(for: auth, lastError: .signInRequired, enabled: true) == .needsSignIn)
        #expect(GeminiSettingsModel.state(for: auth, lastError: .permissionRequired, enabled: true) == .needsSiteAccess)
    }
}

@Suite("Gemini read through the shared Safari Bridge client")
struct GeminiBrowserReaderTests {
    private final class FakeBridge: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: GeminiBrowserIntegration.Handler?
        private(set) var requested: [String] = []
        private(set) var closed: [String] = []
        var dispatch: ClaudeBrowserAutomaticDispatchResult = .dispatched
        /// What the bridge answers the moment a read is requested.
        var answer: ((String) -> [GeminiBrowserInboundEvent])?

        var integration: GeminiBrowserIntegration {
            GeminiBrowserIntegration(
                startListening: { handler in
                    self.lock.withLock { self.handler = handler }
                    return true
                },
                stopListening: {},
                requestRead: { requestID in
                    let (result, events, handler) = self.lock.withLock {
                        self.requested.append(requestID)
                        return (self.dispatch, self.answer?(requestID) ?? [], self.handler)
                    }
                    for event in events { await handler?(event) }
                    return result
                },
                closeOwnedTab: { requestID in
                    self.lock.withLock { self.closed.append(requestID) }
                }
            )
        }
    }

    private static func envelope(_ requestID: String) -> GeminiBrowserObservationEnvelope {
        GeminiBrowserObservationEnvelope(
            observation: GeminiBrowserObservation(
                buckets: [GeminiBrowserBucket(bucketID: "weekly", period: .weekly, usedPercentage: 4)],
                planLabel: "pro",
                observedAt: "2026-11-24T05:45:00Z"
            ),
            requestID: requestID
        )
    }

    private static func event(_ requestID: String, _ status: ClaudeBrowserAutomationStatus) -> ClaudeBrowserAutomationEvent {
        ClaudeBrowserAutomationEvent(requestID: requestID, status: status, occurredAt: "2026-11-24T05:45:01Z")
    }

    @Test("An answer that arrives before the reader waits is not lost")
    func earlyAnswer() async throws {
        let bridge = FakeBridge()
        bridge.answer = { id in [.observation(Self.envelope(id)), .automation(Self.event(id, .refreshCompleted))] }
        let reader = GeminiBrowserReader(integration: bridge.integration)
        let observation = try await reader.read()
        #expect(observation.buckets.first?.usedPercentage == 4)
    }

    @Test("Safari's refusals become the errors Settings explains")
    func refusals() async {
        for (status, expected) in [
            (ClaudeBrowserAutomationStatus.permissionRequired, GeminiBrowserReadError.permissionRequired),
            (.signInRequired, .signInRequired),
            (.ownedTabOwnershipLost, .tabUnavailable),
            (.usageUnavailable, .usageUnavailable),
        ] {
            let bridge = FakeBridge()
            bridge.answer = { id in [.automation(Self.event(id, status))] }
            let reader = GeminiBrowserReader(integration: bridge.integration)
            await #expect(throws: expected) { try await reader.read() }
        }
    }

    @Test("Another request's answer does not complete this read")
    func otherRequestIgnored() async {
        let bridge = FakeBridge()
        let other = "99999999-9999-4999-8999-999999999999"
        bridge.answer = { _ in [.observation(Self.envelope(other)), .automation(Self.event(other, .refreshCompleted))] }
        let reader = GeminiBrowserReader(integration: bridge.integration, deadline: .milliseconds(200))
        await #expect(throws: GeminiBrowserReadError.timedOut) { try await reader.read() }
    }

    @Test("A read that never answers times out and closes its own tab")
    func timeoutClosesTab() async throws {
        let bridge = FakeBridge()
        let reader = GeminiBrowserReader(integration: bridge.integration, deadline: .milliseconds(100))
        await #expect(throws: GeminiBrowserReadError.timedOut) { try await reader.read() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(bridge.closed == bridge.requested)
    }

    @Test("A Bridge busy with Claude, or not set up, says so at once")
    func dispatchFailures() async {
        for (dispatch, expected) in [
            (ClaudeBrowserAutomaticDispatchResult.workDispatchFailed, GeminiBrowserReadError.busy),
            (.companionUnavailable, .companionUnavailable),
            (.protocolMismatch, .protocolMismatch),
        ] {
            let bridge = FakeBridge()
            bridge.dispatch = dispatch
            let reader = GeminiBrowserReader(integration: bridge.integration)
            await #expect(throws: expected) { try await reader.read() }
        }
    }
}
