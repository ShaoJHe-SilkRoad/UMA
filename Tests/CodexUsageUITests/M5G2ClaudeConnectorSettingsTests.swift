import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5-BROWSER-G1 Claude connector and Settings")
struct M5G2ClaudeConnectorSettingsTests {
    @Test
    func descriptorLocksBrowserSourceAndPrivacyBoundary() {
        let descriptor = BrowserConnectorFixture(consent: false).connector().descriptor
        #expect(descriptor.id.rawValue == "claude.browserSync")
        #expect(descriptor.localSourceClass == .browserCompanionUsage)
        #expect(descriptor.authenticationMethod == .systemBrowserSession)
        #expect(descriptor.usageReadContract == .currentBrowserCompanionUsageRead)
        #expect(descriptor.sourceTier == .authorizedReadOnlyRemote)
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
        #expect((await connector.currentSnapshot()).state == .authenticationRequired)
    }

    @Test
    func applicationStartListensWithoutOpeningBrowser() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await connector.start()
        #expect(await fixture.bridge.startCount == 1)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await connector.lifecycleState() == .waitingForUsagePage)
        #expect((await connector.currentSnapshot()).state == .waitingForFirstResponse)
    }

    @Test
    func explicitConnectOpensExactUsageRouteOnceAndWaits() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.connect(openUsagePage: true)
        #expect(await fixture.bridge.startCount == 1)
        #expect(await fixture.bridge.openCount == 1)
        #expect(await connector.lifecycleState() == .waitingForUsagePage)
    }

    @Test
    func registryKeepsConsentOwnedListenerAliveUntilFirstToolbarRead() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let registry = try AgentConnectorRegistry(connectors: [connector])
        #expect(await fixture.consent.get())
        #expect(await connector.permitsRead(for: .applicationLaunch))

        let initial = await registry.scanSurfaceAdmissions(
            trigger: .applicationLaunch
        )
        #expect(initial.records.first?.admission == .hiddenCurrentReadFailed)
        #expect(await fixture.bridge.startCount == 1)
        #expect(await fixture.bridge.stopCount == 0)

        await fixture.bridge.send(browserEnvelope(five: 9, seven: 71))
        for _ in 0..<20 {
            if await registry.orderedSnapshots().first?.freshness == .fresh {
                break
            }
            await Task.yield()
        }

        let admitted = try #require(await registry.orderedSnapshots().first)
        #expect(admitted.id == ClaudeCodeUsageConnector.connectorID)
        #expect(admitted.freshness == .fresh)
        #expect(await fixture.bridge.stopCount == 0)
    }

    @Test
    func acceptedObservationPublishesIndependentAccountWindows() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await fixture.bridge.send(browserEnvelope(five: 9, seven: 71))

        let snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .ready)
        #expect(snapshot.freshness == .fresh)
        #expect(snapshot.safeFailure == nil)
        let windows = snapshot.channels[0].rateLimitWindows
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
    func malformedFollowUpHidesQuotaAndFailsClosed() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        await fixture.bridge.reject()

        let snapshot = await connector.currentSnapshot()
        #expect(!snapshot.hasValidData)
        #expect(snapshot.freshness == .unavailable)
        #expect(snapshot.safeFailure == .malformedResponse)
        #expect(LocalProviderEligibilityScanner.admission(
            for: snapshot,
            descriptor: connector.descriptor
        ).admittedSnapshot == nil)
    }

    @Test
    func retainedSnapshotStalesThenWithdraws() async {
        let clock = BrowserTestClock()
        let fixture = BrowserConnectorFixture(consent: true, clock: clock)
        let connector = fixture.connector()
        await connector.start()
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))

        clock.advance(ClaudeCodeUsageConnector.freshnessInterval + 1)
        #expect((await connector.currentSnapshot()).freshness == .stale)
        clock.advance(
            ClaudeCodeUsageConnector.maximumRetainedAge
                - ClaudeCodeUsageConnector.freshnessInterval
        )
        let expired = await connector.currentSnapshot()
        #expect(!expired.hasValidData)
        #expect(expired.state == .failed)
    }

    @Test
    func priorSessionCacheStaysHiddenUntilCurrentUsageObservation() async throws {
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
        #expect(await connector.hasHiddenPriorSessionCache())
        let beforeCurrentRead = await connector.currentSnapshot()
        #expect(!beforeCurrentRead.hasValidData)
        #expect(
            LocalProviderEligibilityScanner.admission(
                for: beforeCurrentRead,
                descriptor: connector.descriptor
            ).admittedSnapshot == nil
        )

        await fixture.bridge.send(browserEnvelope(five: 19, seven: 39))
        #expect(!(await connector.hasHiddenPriorSessionCache()))
        #expect((await connector.currentSnapshot()).freshness == .fresh)
        #expect(await cache.writeCount == 1)

        await fixture.bridge.reject(.socketUnavailable)
        let transient = await connector.currentSnapshot()
        #expect(transient.freshness == .cached)
        #expect(
            LocalProviderEligibilityScanner.admission(
                for: transient,
                descriptor: connector.descriptor
            ).admittedSnapshot != nil
        )

        await fixture.bridge.reject(.invalidContract)
        let uncertain = await connector.currentSnapshot()
        #expect(!uncertain.hasValidData)
        #expect(
            LocalProviderEligibilityScanner.admission(
                for: uncertain,
                descriptor: connector.descriptor
            ).admittedSnapshot == nil
        )

        await connector.disconnect()
        #expect(await cache.clearCount == 1)
        #expect(await cache.read() == nil)
    }

    @Test
    func timerRefreshNeverOpensBrowserButManualRefreshDoes() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.refresh(trigger: .timer)
        #expect(await fixture.bridge.openCount == 0)
        await connector.refresh(trigger: .manual)
        #expect(await fixture.bridge.openCount == 1)
    }

    @Test
    func disconnectStopsListenerClearsConsentAndWithdraws() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        await connector.disconnect()

        #expect(!(await fixture.consent.get()))
        #expect(await fixture.bridge.stopCount == 1)
        #expect((await connector.currentSnapshot()).state == .authenticationRequired)
        #expect(await connector.lifecycleState() == .disconnected)
    }

    @Test @MainActor
    func settingsTransparencyNamesOnlySystemBrowserContract() {
        let transparency = ClaudeSourceTransparency()
        #expect(transparency.login == "System default browser")
        #expect(!transparency.passwordAccessed)
        #expect(!transparency.apiKeyRequired)
        #expect(!transparency.keychainAccessed)
        #expect(!transparency.cookiesReadOrExported)
        #expect(transparency.pageData.contains("Normalized quota"))
        #expect(transparency.storedLocally.contains("sanitized quota cache"))
    }
}
