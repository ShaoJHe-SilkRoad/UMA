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
@Suite("Periodic Accuracy Sync", .timeLimit(.minutes(1)))
@MainActor
struct PeriodicAccuracySyncTests {
    @Test("The choice is off by default, persists, and survives retiring the old automation")
    func choicePersists() throws {
        let suite = "auv-periodic-sync-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ClaudeBrowserConsentStore(defaults: defaults)
        #expect(!store.periodicAccuracySyncEnabled)
        store.periodicAccuracySyncEnabled = true
        store.retirePersistentBrowserAutomation()
        #expect(ClaudeBrowserConsentStore(defaults: defaults).periodicAccuracySyncEnabled)
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

        model.setPeriodicAccuracySyncEnabled(true)
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

        model.setPeriodicAccuracySyncEnabled(false)
        #expect(!model.periodicAccuracySyncIsDue)
        await ticker.tick()
    }
}

/// Refresh All goes on to Accuracy Sync when Claude is in the list, under the
/// same rules as the timer: consent, an offered sync and Safari already open.
@Suite("Refresh All Accuracy Sync", .timeLimit(.minutes(1)))
@MainActor
struct RefreshAllAccuracySyncTests {
    @Test("Refresh All starts one sync only with consent and Safari open")
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
        #expect(!model.accuracySyncAfterRefreshAll())

        model.connectWithConsent()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        try await waitForClaudeValue(model.$state, matching: { _ in model.offersAccuracySync })

        safariRunning = false
        #expect(!model.accuracySyncAfterRefreshAll())
        #expect(await fixture.bridge.automaticRequests.isEmpty)

        safariRunning = true
        #expect(model.accuracySyncAfterRefreshAll())
        try await fixture.bridge.waitForAutomaticRequest()
        #expect(await fixture.bridge.automaticRequests.count == 1)
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
        let sync = try #require(body.range(of: "runtime.claudeSettings.accuracySyncAfterRefreshAll()"))
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
        let menuBar = try #require(page.range(of: "case .menuBar:\n                settingsSection("))
        let wizard = try #require(page.range(of: "case .desktopWizard:", range: menuBar.upperBound..<page.endIndex))
        #expect(page[menuBar.upperBound..<wizard.lowerBound].contains("uma.settings.appearance.quick-rails"))
        #expect(!page.contains("live in each Agent workspace"))
    }

    @Test("The consent names every way a sync can use Safari")
    func consentNamesEverySyncRoute() {
        let english = AppLanguage.english.claudeConsentDisclosure
        #expect(english.contains("Refresh All while Safari is already open"))
        #expect(english.contains("every 10 minutes"))
        #expect(!english.contains("no browser timer"))
        let chinese = AppLanguage.simplifiedChinese.claudeConsentDisclosure
        #expect(chinese.contains("全部刷新"))
        #expect(chinese.contains("每 10 分钟自动精确同步"))
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
