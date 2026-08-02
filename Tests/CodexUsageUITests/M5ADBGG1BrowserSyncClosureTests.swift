import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5ADBG-G1 Browser Sync closure")
struct M5ADBGG1BrowserSyncClosureTests {
    @Test
    func exactFreshnessBoundariesBecomeStaleThenExpire() async {
        let clock = BrowserTestClock()
        let fixture = BrowserConnectorFixture(consent: true, clock: clock)
        let connector = fixture.connector()
        await connector.start()
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))

        clock.advance(ClaudeCodeUsageConnector.freshnessInterval)
        let stale = await connector.currentSnapshot()
        #expect(stale.freshness == .stale)
        #expect(stale.hasValidData)

        clock.advance(
            ClaudeCodeUsageConnector.maximumRetainedAge
                - ClaudeCodeUsageConnector.freshnessInterval
        )
        let expired = await connector.currentSnapshot()
        #expect(!expired.hasValidData)
        #expect(expired.freshness == .unavailable)
        #expect(await connector.lifecycleState() == .failed)
    }

    @Test
    func healthProbeWithdrawsUnsafeStatesButRetainsBrowserClosedSnapshot() async {
        let transient = BrowserConnectorFixture(consent: true)
        let transientConnector = transient.connector()
        await transientConnector.start()
        await transient.bridge.send(browserEnvelope(five: 20, seven: 40))
        await transient.bridge.setHealth(.browserUnavailable)
        _ = await transientConnector.probe()
        #expect((await transientConnector.currentSnapshot()).freshness == .cached)
        #expect((await transientConnector.currentSnapshot()).hasValidData)

        for unsafeHealth in [
            ClaudeBrowserCompanionHealth.disabled,
            .outdated,
            .nativeHostMissing,
            .nativeHostMismatched,
        ] {
            let fixture = BrowserConnectorFixture(consent: true)
            let connector = fixture.connector()
            await connector.start()
            await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
            await fixture.bridge.setHealth(unsafeHealth)
            _ = await connector.probe()
            #expect(!(await connector.currentSnapshot()).hasValidData)
        }
    }

    @Test
    func listenerStartFailureCanRecoverOnTheNextExplicitAction() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await fixture.bridge.setStartError(.socketUnavailable)
        await connector.start()
        #expect((await connector.diagnostics()).listenerStartCount == 1)
        #expect(!(await connector.currentSnapshot()).hasValidData)

        await fixture.bridge.setStartError(nil)
        await connector.start()
        #expect((await connector.diagnostics()).listenerStartCount == 2)
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        #expect((await connector.currentSnapshot()).freshness == .fresh)
    }

    @Test
    func repeatedSyntheticMessagesStaySingleListenerAndFailClosed() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        for index in 0..<20 {
            await fixture.bridge.send(browserEnvelope(
                five: Double(index),
                seven: Double(index + 20)
            ))
        }
        for _ in 0..<10 {
            await fixture.bridge.reject(.invalidContract)
        }

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.acceptedObservationCount == 20)
        #expect(diagnostics.rejectedObservationCount == 10)
        #expect(diagnostics.listenerStartCount == 1)
        #expect(!(await connector.currentSnapshot()).hasValidData)
    }

    @Test
    func tenConnectDisconnectCyclesDoNotAccumulateListeners() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        for _ in 0..<10 {
            await fixture.consent.set(true)
            await connector.connect(openUsagePage: true)
            await connector.disconnect()
        }
        #expect(await fixture.bridge.startCount == 10)
        #expect(await fixture.bridge.stopCount == 10)
        #expect(await fixture.bridge.openCount == 10)
        #expect(await connector.lifecycleState() == .disconnected)
    }

    @Test
    func cacheRejectsIntermediateAndDanglingSymlinks() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("uma-m5adbg-cache-\(UUID().uuidString)", isDirectory: true)
        let actual = root.appendingPathComponent("actual", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(
            at: actual,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)

        let data = try ClaudeBrowserMessageDecoder.encode(
            browserEnvelope(five: 20, seven: 40)
        )
        let traversingStore = ClaudeBrowserSanitizedCacheStore(
            url: alias.appendingPathComponent("sanitized-quota.json")
        )
        await #expect(throws: ClaudeBrowserSanitizedCacheStore.StoreError.invalidPath) {
            try await traversingStore.save(data)
        }

        let danglingURL = root.appendingPathComponent("dangling.json")
        try FileManager.default.createSymbolicLink(
            at: danglingURL,
            withDestinationURL: root.appendingPathComponent("missing.json")
        )
        let danglingStore = ClaudeBrowserSanitizedCacheStore(url: danglingURL)
        await #expect(throws: ClaudeBrowserSanitizedCacheStore.StoreError.wrongType) {
            try await danglingStore.clear()
        }
    }

    @Test @MainActor
    func settingsErrorClearsAfterAValidObservation() async throws {
        let suite = "uma-m5adbg-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let consentStore = ClaudeBrowserConsentStore(defaults: defaults)
        consentStore.consentGranted = true
        let model = ClaudeBrowserSettingsModel(
            connector: connector,
            consentStore: consentStore
        )

        await connector.start()
        await fixture.bridge.reject(.invalidContract)
        for _ in 0..<40 where model.safeError != .routeChanged {
            await Task.yield()
        }
        #expect(model.safeError == .routeChanged)

        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        for _ in 0..<40 {
            if model.safeError == nil, case .fresh = model.state { break }
            await Task.yield()
        }
        #expect(model.safeError == nil)
        if case .fresh = model.state {
            // Expected recovery state.
        } else {
            Issue.record("Settings did not recover to Fresh")
        }
    }

    @Test @MainActor
    func consentConfirmationPersistsAndStartsOneExplicitBrowserRead() async throws {
        let suite = "uma-m5adbg-consent-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let consentStore = ClaudeBrowserConsentStore(defaults: defaults)
        let model = ClaudeBrowserSettingsModel(
            connector: connector,
            consentStore: consentStore
        )

        model.connectWithConsent()
        for _ in 0..<80 where await fixture.bridge.openCount == 0 {
            await Task.yield()
        }

        #expect(consentStore.consentGranted)
        #expect(model.consentGranted)
        #expect(await fixture.bridge.startCount == 1)
        #expect(await fixture.bridge.openCount == 1)
        #expect(await connector.lifecycleState() == .waitingForUsagePage)
    }

    @Test
    func settingsUsesAnInlineConsentControlInsteadOfAPanelAlert() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "private struct ClaudeBrowserSettingsSection"))
        let end = try #require(source.range(of: "private struct WorkBuddySettingsSection"))
        let section = String(source[start.lowerBound..<end.lowerBound])

        #expect(section.contains("if showingConsent, !model.consentGranted"))
        #expect(section.contains("claude.browser.consent.continue"))
        #expect(section.contains("model.connectWithConsent()"))
        #expect(!section.contains(".alert("))
    }

    @Test
    func actionAndErrorCopyIsLocalizedWithoutAutomaticRefreshClaims() {
        #expect(AppLanguage.english.claudeBrowserActionStatus(.refreshing) == "Refreshing…")
        #expect(AppLanguage.simplifiedChinese.claudeBrowserActionStatus(.refreshing) == "正在刷新…")
        #expect(
            AppLanguage.english.claudeBrowserError(.routeChanged)
                == "Claude's Usage page changed. Browser Sync stopped safely."
        )
        #expect(AppLanguage.simplifiedChinese.claudeBrowserError(.timedOut) == "Claude 浏览器同步已超时。")
        for action in [
            ClaudeSettingsAction.checking,
            .connecting,
            .refreshing,
            .openingUsage,
            .repairing,
            .disconnecting,
        ] {
            #expect(!AppLanguage.english.claudeBrowserActionStatus(action).isEmpty)
            #expect(!AppLanguage.simplifiedChinese.claudeBrowserActionStatus(action).isEmpty)
        }
    }
}
