import Foundation
import Testing
@testable import CodexUsageUI

/// Claude's Desktop Assistant percentage turns green only for an exact,
/// current reading, so a synced value can be told from an estimate.
@Suite("Desktop Assistant verified reading")
struct DesktopAssistantVerifiedReadingTests {
    private func card(
        id: String = "claude.browserSync",
        plan: String? = nil,
        value: DesktopAssistantUsageValue = .finite(60),
        connection: DesktopAssistantConnectionState = .connected,
        isStale: Bool = false
    ) -> DesktopAssistantCard {
        DesktopAssistantCard(
            id: id,
            providerName: "Claude",
            planLabel: plan,
            connectionState: connection,
            selectedWindowShortLabel: "5h",
            selectedWindowAccessibilityLabel: "five-hour window",
            usageValue: value,
            severity: .normal,
            isStale: isStale
        )
    }

    @Test("An exact, current Claude reading is shown as verified")
    func exactClaudeReadingIsVerified() {
        #expect(card().showsVerifiedReading)
        #expect(card(plan: "Max", value: .finite(40)).showsVerifiedReading)
    }

    @Test("Estimates, stale values, low readings and other agents are not")
    func everythingElseIsNot() {
        #expect(!card(value: .estimated(60)).showsVerifiedReading)
        #expect(!card(isStale: true).showsVerifiedReading)
        #expect(!card(connection: .stale).showsVerifiedReading)
        #expect(!card(value: .unavailable).showsVerifiedReading)
        #expect(!card(plan: "Max", value: .finite(5)).showsVerifiedReading)
        #expect(!card(id: "codex.appServer").showsVerifiedReading)
    }
}

/// The ten-minute Accuracy Sync is the user's choice, runs the same one-shot
/// sync as the button, and never runs without Safari or consent.
/// Claude's Accuracy Sync no longer has a timer switch of its own: it follows
/// the app's automatic refresh, on and off and at its interval.
@Suite("Automatic refresh includes Claude", .timeLimit(.minutes(1)))
@MainActor
struct PeriodicAccuracySyncTests {
    @Test("Automatic refresh off means no Claude timer; on means its interval")
    func intervalFollowsAutomaticRefresh() {
        let preferences = ApplicationPreferences.inMemory()
        #expect(UsageMonitorRuntime.claudeAutomaticSyncInterval(preferences: preferences) == nil)
        preferences.set(true, for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh)
        #expect(UsageMonitorRuntime.claudeAutomaticSyncInterval(preferences: preferences) == TimeInterval(900))
        preferences.set(UMABackgroundRefreshInterval.fiveMinutes.rawValue,
                        for: UMAApplicationPreferenceKeys.backgroundRefreshInterval)
        #expect(UsageMonitorRuntime.claudeAutomaticSyncInterval(preferences: preferences) == TimeInterval(300))
        preferences.set(false, for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh)
        #expect(UsageMonitorRuntime.claudeAutomaticSyncInterval(preferences: preferences) == nil)
    }

    @Test("Automatic refresh can run every five minutes")
    func fiveMinuteChoice() {
        #expect(UMABackgroundRefreshInterval.allCases.first == .fiveMinutes)
        #expect(UMABackgroundRefreshInterval.fiveMinutes.seconds == 300)
        #expect(UMABackgroundRefreshInterval.fiveMinutes.duration == .seconds(300))
    }

    @Test("A retired ten-minute choice that was on turns automatic refresh on, once")
    func legacyChoiceCarriesOver() throws {
        let suite = "auv-periodic-sync-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        let preferences = ApplicationPreferences.inMemory()
        UsageMonitorRuntime.migrateLegacyClaudePeriodicSync(consent: consent, preferences: preferences)
        #expect(!preferences.value(for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh))

        consent.legacyPeriodicAccuracySyncEnabled = true
        UsageMonitorRuntime.migrateLegacyClaudePeriodicSync(consent: consent, preferences: preferences)
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh))
        #expect(!ClaudeBrowserConsentStore(defaults: defaults).legacyPeriodicAccuracySyncEnabled)
    }

    @Test("A tick runs one one-shot Accuracy Sync, and only while Safari is running")
    func tickRunsOneShotSync() async throws {
        let suite = "auv-periodic-sync-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let fixture = BrowserConnectorFixture(consent: true)
        let ticker = PeriodicTicker()
        var safariRunning = false
        let model = ClaudeBrowserSettingsModel(
            connector: fixture.connector(),
            consentStore: consent,
            periodicSleep: { _ in await ticker.sleep() },
            safariIsRunning: { safariRunning }
        )
        model.connectWithConsent()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        try await waitForClaudeValue(model.$state, matching: { _ in model.offersAccuracySync })
        #expect(await fixture.bridge.automaticRequests.isEmpty)

        model.setAutomaticAccuracySync(every: 300)
        #expect(!model.periodicAccuracySyncIsDue)
        try await ticker.waitForSleeper()
        await ticker.tick()
        try await ticker.waitForSleeper()
        #expect(await fixture.bridge.automaticRequests.isEmpty)

        safariRunning = true
        #expect(model.periodicAccuracySyncIsDue)
        await ticker.tick()
        try await fixture.bridge.waitForAutomaticRequest()
        let requests = await fixture.bridge.automaticRequests
        #expect(requests.count == 1)
        #expect(requests.first?.allowSafariLaunch == true)

        model.setAutomaticAccuracySync(every: nil)
        #expect(!model.periodicAccuracySyncIsDue)
        await ticker.tick()
    }
}

/// Refresh All includes Accuracy Sync when Claude is in the list. It is the
/// user's own action and replaced the Accuracy Sync button, so, unlike
/// automatic refresh, it does not wait for Safari to be open.
@Suite("Refresh All Accuracy Sync", .timeLimit(.minutes(1)))
@MainActor
struct RefreshAllAccuracySyncTests {
    @Test("Refresh All starts one sync with consent, whether or not Safari is open")
    func refreshAllStartsSync() async throws {
        let suite = "auv-refresh-sync-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        let fixture = BrowserConnectorFixture(consent: true)
        var safariRunning = true
        let model = ClaudeBrowserSettingsModel(
            connector: fixture.connector(),
            consentStore: consent,
            safariIsRunning: { safariRunning }
        )
        #expect(!model.accuracySyncForRefreshAll())
        #expect(await fixture.bridge.automaticRequests.isEmpty)

        model.connectWithConsent()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        try await waitForClaudeValue(model.$state, matching: { _ in model.offersAccuracySync })

        safariRunning = false
        #expect(!model.periodicAccuracySyncIsDue)
        #expect(model.accuracySyncForRefreshAll())
        try await fixture.bridge.waitForAutomaticRequest()
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect(await fixture.bridge.automaticRequests.first?.allowSafariLaunch == true)
    }

    @Test("The coordinator runs it after the store refresh, only for a listed Claude")
    func coordinatorWiring() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift"),
            encoding: .utf8
        )
        let body = try #require(source.range(of: "func refreshAll() async {")
            .flatMap { start in source.range(of: "func refreshAllProviders()", range: start.upperBound..<source.endIndex)
                .map { source[start.lowerBound..<$0.lowerBound] } })
        let refresh = try #require(body.range(of: "await runtime.store.refresh()"))
        let sync = try #require(body.range(of: "runtime.claudeSettings.accuracySyncForRefreshAll()"))
        #expect(refresh.upperBound <= sync.lowerBound)
        #expect(body.contains("$0.id == .claude"))
    }
}

/// A sleeper the test advances by hand.
private actor PeriodicTicker {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    func tick() {
        let resumed = waiters
        waiters = []
        resumed.forEach { $0.resume() }
    }

    func waitForSleeper() async throws {
        let deadline = Date().addingTimeInterval(10)
        while waiters.isEmpty {
            guard Date() < deadline else {
                Issue.record("No sleeper within 10s")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// One entry for each kind of setting: the app's own in Global Settings, an
/// agent's on that agent's page, and Sectorium's on its tab.
@Suite("Settings entry points")
struct SettingsEntryPointTests {
    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(path),
            encoding: .utf8
        )
    }

    @Test("Agent settings open from the agent's page, under the agent's name")
    func agentSettingsLiveOnThePage() throws {
        let shell = try source("Sources/CodexUsageMonitor/App/NativeShellViews.swift")
        let sidebar = try #require(shell.range(of: "private var agentsWorkspace: some View {"))
        let list = try #require(shell.range(of: "if workspaceProviders.isEmpty {", range: sidebar.upperBound..<shell.endIndex))
        #expect(!shell[sidebar.upperBound..<list.lowerBound].contains("MainAgentSettingsButton("))
        #expect(shell.contains("settingsButton: workspaceProviders.isEmpty ? nil : AnyView(agentSettingsButton)"))
        #expect(shell.contains("\"\\(selectedProviderID.displayName) Settings…\""))
        let page = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        // The page's own Refresh read as this agent only but refreshed all.
        #expect(!page.contains("Button(localized(\"Refresh\", \"刷新\"), action: refresh)"))
        #expect(page.components(separatedBy: "if let settingsButton { settingsButton }").count == 3)
    }

    @Test("The sheet drops toggles nothing reads and actions the page already has")
    func sheetHoldsNoDuplicates() throws {
        let sheet = try source("Sources/CodexUsageUI/Views/UsageSettingsCard.swift")
        let content = try #require(sheet.range(of: "private struct AgentSpecificSettingsContent"))
        let end = try #require(sheet.range(of: "/// Settings renders the exact same", range: content.upperBound..<sheet.endIndex))
        let body = sheet[content.lowerBound..<end.lowerBound]
        #expect(!body.contains("language.usageSummaryCard"))
        #expect(!body.contains("language.recentTasks"))
        #expect(!body.contains("codexDetailBinding"))
        #expect(body.contains("language.costCard"))
        #expect(AppLanguage.english.costCard == "Local Cost Estimate")
    }

    @Test("Global Settings holds the Quick Panel with the menu bar, and no Sectorium copy")
    func globalSettingsGrouping() throws {
        #expect(!GlobalSettingsPane.allCases.map(\.rawValue).contains("HESectorium"))
        let page = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let menuBar = try #require(page.range(of: "case .menuBar:\n                settingsSection(localized(\"Menu Bar Item\""))
        let wizard = try #require(page.range(of: "case .desktopWizard:", range: menuBar.upperBound..<page.endIndex))
        #expect(page[menuBar.upperBound..<wizard.lowerBound].contains("uma.settings.appearance.quick-rails"))
        #expect(!page.contains("live in each Agent workspace"))
    }

    @Test("The consent names every way a sync can use Safari")
    func consentNamesEverySyncRoute() {
        let english = AppLanguage.english.claudeConsentDisclosure
        #expect(english.contains("when you choose Refresh All"))
        #expect(english.contains("if you turn on automatic refresh in Settings, at the interval you choose"))
        #expect(english.contains("Refresh All may start Safari in the background"))
        #expect(english.contains("automatic refresh runs only while Safari is already open and never starts it"))
        #expect(!english.contains("every 10 minutes"))
        #expect(!english.contains("when you choose Accuracy Sync"))
        let chinese = AppLanguage.simplifiedChinese.claudeConsentDisclosure
        #expect(chinese.contains("您点按“全部刷新”时"))
        #expect(chinese.contains("开启“自动刷新”后，按所选间隔运行"))
        #expect(chinese.contains("“全部刷新”可能为此在后台启动 Safari"))
        #expect(chinese.contains("自动刷新只在 Safari 已打开时运行，绝不会启动 Safari"))
        #expect(!chinese.contains("每 10 分钟"))
    }

    @Test("Claude's page has no Accuracy Sync button of its own, and no timer switch")
    func noSeparateSyncButton() throws {
        let page = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        #expect(!page.contains("uma.agent.claude.accuracy-sync\""))
        #expect(!page.contains("action: claudeAccuracySync"))
        let sheet = try source("Sources/CodexUsageUI/Views/UsageSettingsCard.swift")
        #expect(!sheet.contains("claude.browser.periodic-sync"))
        #expect(sheet.contains("language.claudeAccuracySyncRoute"))
    }
}

/// Claude used to drop off the Desktop Assistant once its exact reading was
/// 30 minutes old, and, being in a failed state then, no later sync ran.
@Suite("Desktop Assistant keeps Claude")
struct DesktopAssistantKeepsClaudeTests {
    private let epoch = Date(timeIntervalSince1970: 1_788_134_400)

    @Test("A detected Claude whose reading lapsed stays on the assistant, not the Quick Panel")
    func lapsedClaudeStays() {
        let lapsed = AgentUsageSnapshot(
            id: ClaudeCodeUsageConnector.connectorID,
            providerName: "Claude Code",
            state: .failed,
            capturedAt: epoch,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: [.refresh],
            safeFailure: .unavailable
        )
        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: [lapsed],
            admissions: [],
            monitoringEnabledIDs: [ClaudeCodeUsageConnector.connectorID],
            configuredOrDetectedIDs: [ClaudeCodeUsageConnector.connectorID],
            previousCards: [],
            language: .english,
            now: epoch
        )
        let claude = reduction.inventory.provider(.claude)
        #expect(claude?.primaryDisplayText == "—")
        #expect(claude?.inventory.assistant == true)
        #expect(claude?.inventory.quickPanel == false)
    }

    @Test("A monitored agent that was never found does not appear")
    func undetectedAgentStaysOff() {
        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: [],
            admissions: [],
            monitoringEnabledIDs: [GoogleAntigravityUsageConnector.connectorID],
            configuredOrDetectedIDs: [],
            previousCards: [],
            language: .english,
            now: epoch
        )
        #expect(reduction.inventory.assistantProviders.isEmpty)
    }

    @Test("Unprompted syncs may run from the state a lapsed reading lands in")
    func failedStateStillOffersSync() throws {
        let model = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/CodexUsageUI/Stores/ClaudeBrowserSettingsModel.swift"),
            encoding: .utf8
        )
        let offers = try #require(model.range(of: "var offersAccuracySync: Bool {"))
        #expect(model[offers.upperBound...].prefix(160).contains(".stale, .failed:"))
    }
}

/// After a launch, Claude's page had no Accuracy Sync button (the companion
/// reads as not configured until something talks to it), and the timer's
/// first run was ten minutes away, so Claude sat without a reading.
@Suite("Accuracy Sync after launch", .timeLimit(.minutes(1)))
@MainActor
struct AccuracySyncAfterLaunchTests {
    @Test("The page offers Accuracy Sync wherever an unprompted sync would run")
    func pageOffersSync() throws {
        let unknownCompanion = ClaudeAgentControlState.classify(
            consentGranted: true,
            localSmartState: .estimated(Date()),
            companionRuntime: .notConfigured,
            browserAccuracyState: .companionUnavailable
        )
        #expect(unknownCompanion == .onlineVerificationUnavailable)
        #expect(unknownCompanion.offeringSync(when: true) == .accuracyReady)
        #expect(unknownCompanion.offeringSync(when: false) == .onlineVerificationUnavailable)
        // Every other state keeps its own control.
        for other in [ClaudeAgentControlState.consentRequired, .localSmartRepairRequired,
                      .companionStarting, .companionUpdateRequired, .accuracyInProgress] {
            #expect(other.offeringSync(when: true) == other)
        }
        let model = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/CodexUsageUI/Stores/ClaudeBrowserSettingsModel.swift"),
            encoding: .utf8
        )
        #expect(model.contains("return control.offeringSync(when: consentGranted && offersAccuracySync)"))
    }

    @Test("The timer's first run comes 15 seconds in, then at the refresh interval")
    func firstRunIsSoon() async throws {
        let suite = "auv-launch-sync-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        let ticker = PeriodicTicker()
        let recorder = IntervalRecorder()
        let model = ClaudeBrowserSettingsModel(
            connector: BrowserConnectorFixture(consent: true).connector(),
            consentStore: consent,
            periodicSleep: { interval in
                await recorder.record(interval)
                await ticker.sleep()
            },
            safariIsRunning: { false }
        )
        model.setAutomaticAccuracySync(every: 300)
        try await ticker.waitForSleeper()
        await ticker.tick()
        try await ticker.waitForSleeper()
        #expect(await recorder.intervals == [15, 300])
        // An unrelated preference change repeats the same interval: the
        // schedule is kept, not restarted.
        model.setAutomaticAccuracySync(every: 300)
        #expect(await recorder.intervals == [15, 300])
        model.setAutomaticAccuracySync(every: nil)
    }
}

private actor IntervalRecorder {
    private(set) var intervals: [TimeInterval] = []
    func record(_ interval: TimeInterval) { intervals.append(interval) }
}
