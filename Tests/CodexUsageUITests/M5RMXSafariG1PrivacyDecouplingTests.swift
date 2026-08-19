import Foundation
import Testing
import ClaudeBrowserNativeHostCore
@testable import CodexUsageUI

@Suite("M5RMX-SAFARI-G1 Browser Sync privacy decoupling")
struct M5RMXSafariG1PrivacyDecouplingTests {
    @Test
    func productionCallGraphHasNoLocalActivityConstructionOrPublicationPath() throws {
        let connector = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeCodeUsageConnector.swift"
        )
        let runtime = try source(
            "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
        )

        #expect(runtime.contains("ClaudeCodeUsageConnector.production("))
        #expect(!runtime.contains("ClaudeLocalActivityReader"))
        #expect(!runtime.contains("localActivityReader: ClaudeLocalActivityReader"))
        for forbidden in [
            "ClaudeLocalActivityReader(",
            "any ClaudeLocalActivityReading",
            "scheduleLocalActivityRefreshIfNeeded",
            "storeLocalActivity(",
            "cachedLocalActivity",
            "reader.read(now:",
        ] {
            #expect(!connector.contains(forbidden))
        }

        let descriptor = ClaudeCodeUsageConnector.production().descriptor
        #expect(descriptor.supportedScopes == [.account])
        #expect(!descriptor.capabilities.contains(.localActivity))
        #expect(!descriptor.privacyAllowlist.contains("localActivityTokenCounts"))
        #expect(!descriptor.privacyAllowlist.contains("localActivityModelIdentifier"))
        #expect(!descriptor.privacyAllowlist.contains("localActivityTimestamp"))
    }

    @Test
    func connectCallbackCacheManualReconnectAndRecoveryStayQuotaOnly() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()

        // Initial production-equivalent Browser Sync connect.
        await connector.connect(openUsagePage: false)
        await expectPrivacyZeros(connector)

        // Successful native callback and sanitized cache publication.
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        #expect(await fixture.cache.writeCount == 1)
        #expect((await connector.currentSnapshot()).channels.map(\.id) == [.account])
        await expectPrivacyZeros(connector)

        // Manual refresh/coalescing.
        await connector.syncNow()
        await connector.syncNow()
        #expect((await connector.diagnostics()).coalescedActionCount == 1)
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(
            requestID: requestID,
            status: .usageUnavailable
        )
        await expectPrivacyZeros(connector)

        // Reconnect is a browser action only.
        await connector.connect(openUsagePage: true)
        #expect(await fixture.bridge.openCount == 1)
        await expectPrivacyZeros(connector)

        // Failure followed by a valid callback cannot enable a hidden fallback.
        await fixture.bridge.reject(.malformedJSON)
        await expectPrivacyZeros(connector)
        await fixture.bridge.send(browserEnvelope(five: 25, seven: 45))
        #expect(await fixture.cache.writeCount == 2)
        #expect((await connector.currentSnapshot()).channels.map(\.id) == [.account])
        await expectPrivacyZeros(connector)

        await connector.disconnect()
        await expectPrivacyZeros(connector)
    }

    @Test
    func scheduledBrowserRefreshStaysQuotaOnly() async {
        let sleeper = BrowserTestSleeper()
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector { interval in
            try await sleeper.sleep(interval)
        }

        await connector.start()
        await waitForIntervals(sleeper, count: 1)
        #expect(await sleeper.intervals == [0])
        await expectPrivacyZeros(connector)

        await sleeper.resumeNext()
        await waitForRequests(fixture.bridge, count: 1)
        #expect((await connector.diagnostics()).scheduledCycleCount == 1)
        await expectPrivacyZeros(connector)

        await fixture.bridge.send(browserEnvelope(five: 30, seven: 50))
        #expect(await fixture.cache.writeCount == 1)
        #expect((await connector.currentSnapshot()).channels.map(\.id) == [.account])
        await expectPrivacyZeros(connector)

        await connector.disconnect()
        await expectPrivacyZeros(connector)
    }

    @Test
    func preseededSanitizedCacheLoadAndDisconnectClearStayQuotaOnly() async throws {
        let encoded = try ClaudeBrowserMessageDecoder.encode(
            browserEnvelope(five: 35, seven: 55)
        )
        let clock = BrowserTestClock()
        let cache = BrowserTestCache(encoded)
        let fixture = BrowserConnectorFixture(
            consent: true,
            clock: clock,
            cache: cache
        )
        let connector = fixture.connector()

        await connector.start()
        #expect(await connector.hasHiddenPriorSessionCache())
        #expect(!(await connector.currentSnapshot()).hasValidData)
        await expectPrivacyZeros(connector)

        await connector.disconnect()
        #expect(await cache.clearCount == 1)
        #expect(!(await fixture.consent.get()))
        #expect(!(await connector.hasHiddenPriorSessionCache()))
        await expectPrivacyZeros(connector)
    }

    private func expectPrivacyZeros(_ connector: ClaudeCodeUsageConnector) async {
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.localActivityReaderInvocationCount == 0)
        #expect(diagnostics.claudeProjectsAccessCount == 0)
    }

    private func waitForIntervals(_ sleeper: BrowserTestSleeper, count: Int) async {
        for _ in 0..<200 {
            if await sleeper.intervals.count >= count { return }
            await Task.yield()
        }
    }

    private func waitForRequests(_ bridge: BrowserTestBridge, count: Int) async {
        for _ in 0..<200 {
            if await bridge.automaticRequests.count >= count { return }
            await Task.yield()
        }
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
