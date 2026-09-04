import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5ADBG-G1 Local Smart and one-shot Accuracy closure", .timeLimit(.minutes(1)))
struct M5ADBGG1BrowserSyncClosureTests {
    @Test
    func exactSmartFreshnessBecomesStaleThenExpiresAtProviderReset() async {
        let clock = BrowserTestClock()
        let fixture = BrowserConnectorFixture(consent: true, clock: clock)
        let connector = fixture.connector()
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))

        clock.advance(ClaudeCodeUsageConnector.freshnessInterval)
        let boundary = await connector.currentSnapshot()
        #expect(boundary.freshness == .fresh)
        #expect(boundary.hasValidData)

        clock.advance(1)
        let stale = await connector.currentSnapshot()
        #expect(stale.freshness == .stale)
        #expect(stale.hasValidData)

        clock.advance(8 * 24 * 60 * 60)
        let expired = await connector.currentSnapshot()
        #expect(!expired.hasValidData)
        #expect(expired.freshness == .unavailable)
        #expect(await connector.lifecycleState() == .waitingForUsagePage)
    }

    @Test
    func browserCompanionHealthCannotWithdrawValidatedLocalSmartState() async {
        let transient = BrowserConnectorFixture(consent: true)
        let transientConnector = transient.connector()
        await transientConnector.start()
        await transientConnector.accuracySync()
        await transient.bridge.send(browserEnvelope(five: 20, seven: 40))
        await transient.bridge.setHealth(.browserUnavailable)
        _ = await transientConnector.probe()
        #expect((await transientConnector.currentSnapshot()).freshness == .fresh)
        #expect((await transientConnector.currentSnapshot()).hasValidData)

        for irrelevantBrowserHealth in [
            ClaudeBrowserCompanionHealth.disabled,
            .outdated,
            .nativeHostMissing,
            .nativeHostMismatched,
        ] {
            let fixture = BrowserConnectorFixture(consent: true)
            let connector = fixture.connector()
            await connector.start()
            await connector.accuracySync()
            await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
            await fixture.bridge.setHealth(irrelevantBrowserHealth)
            _ = await connector.probe()
            #expect((await connector.currentSnapshot()).hasValidData)
            #expect(!(await connector.diagnostics()).schedulerActive)
        }
    }

    @Test
    func localStartCannotCreateAListenerOrAcceptUnsolicitedAccuracyData() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await fixture.bridge.setStartError(.socketUnavailable)
        await connector.start()
        #expect((await connector.diagnostics()).listenerStartCount == 0)
        #expect(!(await connector.currentSnapshot()).hasValidData)

        await fixture.bridge.setStartError(nil)
        await connector.start()
        #expect((await connector.diagnostics()).listenerStartCount == 0)
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        #expect((await connector.diagnostics()).acceptedObservationCount == 0)
        #expect((await connector.diagnostics()).rejectedObservationCount == 0)
        #expect(!(await connector.currentSnapshot()).hasValidData)
    }

    @Test
    func repeatedSyntheticMessagesStaySingleListenerAndFailClosed() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        for index in 0..<20 {
            await connector.accuracySync()
            await fixture.bridge.send(browserEnvelope(
                five: Double(index),
                seven: Double(index + 20)
            ))
        }
        for _ in 0..<10 {
            await connector.accuracySync()
            await fixture.bridge.reject(.invalidContract)
        }

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.acceptedObservationCount == 20)
        #expect(diagnostics.rejectedObservationCount == 10)
        #expect(diagnostics.listenerStartCount == 1)
        #expect((await connector.currentSnapshot()).hasValidData)
        #expect(!(await connector.diagnostics()).schedulerActive)
    }

    @Test
    func tenConnectDisconnectCyclesDoNotAccumulateListeners() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        for _ in 0..<10 {
            await fixture.consent.set(true)
            await connector.accuracySync()
            await connector.disconnect()
        }
        #expect(await fixture.bridge.startCount == 10)
        #expect(await fixture.bridge.stopCount == 10)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.automaticRequests.count == 10)
        #expect((await connector.diagnostics()).scheduledCycleCount == 0)
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        #expect(!(await connector.diagnostics()).schedulerActive)
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
    func settingsKeepsLocalExactTruthWhenOneShotAccuracyFailsThenRecovers() async throws {
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
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 19, seven: 39))
        try await waitForClaudeValue(model.$state, matching: { $0 == .fresh(fixture.clock.now()) })
        await connector.accuracySync()
        await fixture.bridge.reject(.invalidContract)
        try await waitForClaudeValue(model.$browserAccuracyStage, matching: { $0 == .accuracyRouteRejected })
        #expect(model.state == .fresh(fixture.clock.now()))
        #expect(model.safeError == nil)

        fixture.clock.advance(1)
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(
            five: 20,
            seven: 40,
            observedAt: "2030-03-01T12:00:01Z"
        ))
        try await waitForClaudeValue(model.$state, matching: { $0 == .fresh(fixture.clock.now()) })
        #expect(model.safeError == nil)
        let retained = await connector.currentSnapshot()
        await connector.accuracySync()
        let requestID = try #require(await fixture.bridge.automaticRequests.last?.requestID)
        await fixture.bridge.sendAutomation(requestID: requestID, status: .permissionRequired)
        try await waitForClaudeValue(model.$browserAccuracyStage, matching: { $0 == .accuracyPermissionRequired })
        let afterFailure = await connector.currentSnapshot()
        #expect(afterFailure.channels == retained.channels)
        #expect(afterFailure.capturedAt == retained.capturedAt)
        #expect(afterFailure.lastSuccessfulAt == retained.lastSuccessfulAt)
        #expect(model.state == .fresh(fixture.clock.now()))
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        await connector.disconnect()
    }

    @Test @MainActor
    func consentConfirmationPersistsAndStartsLocalSmartWithoutBrowserRead() async throws {
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
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })

        #expect(consentStore.consentGranted)
        #expect(model.consentGranted)
        #expect(await fixture.bridge.startCount == 0)
        #expect((await connector.diagnostics()).listenerStartCount == 0)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect(!(await connector.diagnostics()).schedulerActive)
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
    func actionAndErrorCopyIsLocalizedForLocalSmartAndAccuracySync() {
        #expect(AppLanguage.english.claudeBrowserActionStatus(.refreshing) == "Refreshing…")
        #expect(AppLanguage.simplifiedChinese.claudeBrowserActionStatus(.refreshing) == "正在刷新…")
        #expect(
            AppLanguage.english.claudeBrowserError(.routeChanged)
                == "Claude's Usage page changed. Accuracy Sync stopped safely."
        )
        #expect(AppLanguage.simplifiedChinese.claudeBrowserError(.timedOut) == "Claude 精确同步已超时。")
        for action in [
            ClaudeSettingsAction.checking,
            .connecting,
            .refreshing,
            .checkingCompanion,
            .repairing,
            .requestingSiteAccess,
            .retryingSiteAccess,
            .disconnecting,
        ] {
            #expect(!AppLanguage.english.claudeBrowserActionStatus(action).isEmpty)
            #expect(!AppLanguage.simplifiedChinese.claudeBrowserActionStatus(action).isEmpty)
        }
    }

}
