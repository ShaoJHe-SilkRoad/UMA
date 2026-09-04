import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5 Local Smart connector and Settings", .timeLimit(.minutes(1)))
struct M5G2ClaudeConnectorSettingsTests {
    @Test
    func descriptorLocksLocalSmartSourceAndPrivacyBoundary() {
        let descriptor = BrowserConnectorFixture(consent: false).connector().descriptor
        #expect(descriptor.id.rawValue == "claude.browserSync")
        #expect(descriptor.localSourceClass == .admittedStructuredLocal)
        #expect(descriptor.authenticationMethod == .officialApplicationOwnedSession)
        #expect(descriptor.usageReadContract == .currentStructuredLocalRead)
        #expect(descriptor.sourceTier == .officialStructuredHook)
        #expect(descriptor.officialSource.contains("Local Smart Mode"))
        #expect(descriptor.capabilities.contains(.localActivity))
        #expect(!descriptor.capabilities.contains(.automaticRefresh))
        #expect(!descriptor.capabilities.contains(.sanitizedLastValidRestore))
        #expect(!descriptor.supportsRestore)
        #expect(descriptor.expectedRuntime == .none)
        #expect(descriptor.privacyAllowlist.contains("fiveHourUsedPercentage"))
        for forbidden in [
            "tokens", "cookies", "accountIdentity", "rawHTML", "rawDOM",
            "prompt", "response", "project", "sourceCode",
        ] {
            #expect(descriptor.unsupportedFields.contains(forbidden))
        }
    }

    @Test
    func noConsentCannotReadOrOpenBrowser() async {
        let fixture = BrowserConnectorFixture(consent: false)
        let connector = fixture.connector()
        #expect(!(await connector.permitsRead(for: .applicationLaunch)))
        await connector.start()
        await connector.syncNow()
        #expect(await fixture.bridge.startCount == 0)
        #expect(await fixture.bridge.openCount == 0)
        let snapshot = await connector.currentSnapshot()
        #expect(!snapshot.hasValidData)
        #expect(snapshot.channels.isEmpty)
    }

    @Test
    func applicationStartKeepsBrowserListenerDormant() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await connector.start()
        #expect(await fixture.bridge.startCount == 0)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
    }

    @Test
    func explicitAccuracySyncCreatesExactlyOneBoundedUsageRead() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.accuracySync()
        #expect(await fixture.bridge.startCount == 1)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect((await connector.diagnostics()).automaticDispatchCount == 1)
        #expect((await connector.diagnostics()).scheduledCycleCount == 0)
        #expect(!(await connector.diagnostics()).schedulerActive)
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(requestID: requestID, status: .ownedTabClosed)
        await connector.disconnect()
    }

    @Test
    func registryKeepsBrowserListenerDormantUntilExplicitAccuracySync() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let registry = try AgentConnectorRegistry(connectors: [connector])
        #expect(await fixture.consent.get())
        #expect(await connector.permitsRead(for: .applicationLaunch))

        let initial = await registry.scanSurfaceAdmissions(
            trigger: .applicationLaunch
        )
        #expect(initial.records.first?.admission == .hiddenCurrentReadFailed)
        #expect(await fixture.bridge.startCount == 0)
        #expect(await fixture.bridge.stopCount == 0)

        await connector.accuracySync()
        #expect(await fixture.bridge.startCount == 1)
        await fixture.bridge.send(browserEnvelope(five: 9, seven: 71))
        try await registry.refresh(ClaudeCodeUsageConnector.connectorID)

        let admitted = try #require(await registry.orderedSnapshots().first)
        #expect(admitted.id == ClaudeCodeUsageConnector.connectorID)
        #expect(admitted.freshness == .fresh)
        #expect(await fixture.bridge.stopCount == 0)
    }

    @Test
    func registryKeepsConsentOwnedListenerAliveAfterAHiddenFailedCycle() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let registry = try AgentConnectorRegistry(connectors: [connector])

        _ = await registry.scanSurfaceAdmissions(trigger: .applicationLaunch)
        await connector.accuracySync()
        await fixture.bridge.reject()
        // refresh awaits the registry's receive boundary for the completed failure.
        try await registry.refresh(ClaudeCodeUsageConnector.connectorID)
        #expect(await registry.surfaceAdmissionSet()?.records.first?.admission
            == .hiddenCurrentReadFailed)

        #expect(await registry.orderedSnapshots().isEmpty)
        #expect(await fixture.bridge.stopCount == 0)

        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 9, seven: 71))
        try await registry.refresh(ClaudeCodeUsageConnector.connectorID)

        #expect(await registry.orderedSnapshots().first?.freshness == .fresh)
        #expect(await fixture.bridge.stopCount == 0)
    }

    @Test
    func acceptedObservationPublishesIndependentAccountWindows() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 9, seven: 71))

        let snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .ready)
        #expect(snapshot.freshness == .fresh)
        #expect(snapshot.safeFailure == nil)
        let channel = try #require(snapshot.channels.first)
        let windows = channel.rateLimitWindows
        #expect(windows.count == 2)
        #expect(windows.first { $0.kind == .fiveHour }?.normalizedRemainingPercent == 91)
        #expect(windows.first { $0.kind == .sevenDay }?.normalizedRemainingPercent == 29)
        #expect(await connector.lifecycleState() == .fresh(snapshot.lastSuccessfulAt!))
        #expect(LocalProviderEligibilityScanner.admission(
            for: snapshot,
            descriptor: connector.descriptor
        ).admittedSnapshot == snapshot)
    }

    @Test
    func malformedAccuracyFollowUpCannotInvalidateExistingExactTruth() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        await connector.accuracySync()
        await fixture.bridge.reject()

        let snapshot = await connector.currentSnapshot()
        #expect(snapshot.hasValidData)
        #expect(snapshot.freshness == .fresh)
        #expect(snapshot.safeFailure == nil)
        #expect(LocalProviderEligibilityScanner.admission(
            for: snapshot,
            descriptor: connector.descriptor
        ).admittedSnapshot == snapshot)
    }

    @Test
    func exactSnapshotStalesThenWithdrawsAtProviderReset() async {
        let clock = BrowserTestClock()
        let fixture = BrowserConnectorFixture(consent: true, clock: clock)
        let connector = fixture.connector()
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))

        clock.advance(ClaudeCodeUsageConnector.freshnessInterval + 1)
        #expect((await connector.currentSnapshot()).freshness == .stale)
        clock.advance(8 * 24 * 60 * 60)
        let expired = await connector.currentSnapshot()
        #expect(!expired.hasValidData)
        #expect(expired.state == .waitingForFirstResponse)
    }

    @Test
    func legacyBrowserCacheIsIgnoredNeverRewrittenAndClearedOnlyOnDisconnect() async throws {
        let clock = BrowserTestClock()
        let persisted = try ClaudeBrowserMessageDecoder.encode(
            browserEnvelope(five: 20, seven: 40)
        )
        let cache = BrowserTestCache(persisted)
        let fixture = BrowserConnectorFixture(
            consent: true,
            clock: clock,
            cache: cache
        )
        let connector = fixture.connector()

        await connector.start()
        let beforeLocalTruth = await connector.currentSnapshot()
        #expect(!beforeLocalTruth.hasValidData)
        #expect(await cache.read() == persisted)
        #expect(await cache.writeCount == 0)
        #expect(await cache.clearCount == 0)

        await connector.syncNow()
        #expect(await cache.read() == persisted)
        #expect(await cache.writeCount == 0)
        #expect(await cache.clearCount == 0)

        await connector.disconnect()
        #expect(await cache.clearCount == 1)
        #expect(await cache.read() == nil)
    }

    @Test
    func timerAndManualRefreshStayLocalWhileAccuracySyncUsesOneShotGate() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.refresh(trigger: .timer)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        await connector.refresh(trigger: .manual)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        await connector.accuracySync()
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect((await connector.diagnostics()).scheduledCycleCount == 0)
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(requestID: requestID, status: .ownedTabClosed)
        await connector.disconnect()
    }

    @Test
    func disconnectStopsListenerClearsConsentAndWithdraws() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        await connector.disconnect()

        #expect(!(await fixture.consent.get()))
        #expect(await fixture.bridge.stopCount == 1)
        #expect((await connector.diagnostics()).acceptedObservationCount == 1)
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        #expect(!(await connector.diagnostics()).schedulerActive)
    }

    @Test @MainActor
    func settingsTransparencyNamesLocalSmartAndOnDemandAccuracyContract() {
        let transparency = ClaudeSourceTransparency()
        #expect(transparency.source.contains("Local Smart Mode"))
        #expect(transparency.source.contains("one-shot Safari exact"))
        #expect(transparency.login == "Claude Code provider-owned session")
        #expect(!transparency.passwordAccessed)
        #expect(!transparency.apiKeyRequired)
        #expect(!transparency.keychainAccessed)
        #expect(!transparency.cookiesReadOrExported)
        #expect(transparency.pageData.contains("Sanitized rate-limit fields"))
        #expect(transparency.storedLocally.contains("exact anchors"))
    }
}
