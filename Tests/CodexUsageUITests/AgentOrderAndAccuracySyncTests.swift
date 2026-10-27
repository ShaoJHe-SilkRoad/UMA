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
