import Foundation
import Testing
@testable import CodexUsageUI

@Suite("When AUV asks about Safari")
struct ClaudeSafariPromptPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The timer asks to open Safari once until Safari has run again")
    func launchAsksOncePerClosedStretch() {
        var policy = ClaudeSafariPromptPolicy()
        #expect(policy.asksToLaunch(trigger: .automatic, automaticPromptsOff: false))
        policy.didAsk(.launch)
        #expect(!policy.asksToLaunch(trigger: .automatic, automaticPromptsOff: false))
        policy.safariWasRunning()
        #expect(policy.asksToLaunch(trigger: .automatic, automaticPromptsOff: false))
    }

    @Test("A person who pressed something is always asked")
    func userAlwaysAsked() {
        var policy = ClaudeSafariPromptPolicy()
        policy.didAsk(.launch)
        #expect(policy.asksToLaunch(trigger: .user, automaticPromptsOff: true))
        policy.companionWasSilent(at: start)
        policy.companionWasSilent(at: start.addingTimeInterval(200))
        policy.didAsk(.restart)
        #expect(policy.asksToRestart(
            at: start.addingTimeInterval(200), trigger: .user, automaticPromptsOff: true
        ))
    }

    @Test("Turning prompts off silences only the timer")
    func promptsOff() {
        var policy = ClaudeSafariPromptPolicy()
        #expect(!policy.asksToLaunch(trigger: .automatic, automaticPromptsOff: true))
        policy.companionWasSilent(at: start)
        policy.companionWasSilent(at: start.addingTimeInterval(200))
        #expect(!policy.asksToRestart(
            at: start.addingTimeInterval(200), trigger: .automatic, automaticPromptsOff: true
        ))
    }

    /// One silent handshake is what a cold start looks like, and the page's own
    /// recovery takes about two minutes.
    @Test("A restart is offered only after two silent syncs over three minutes")
    func restartNeedsLastingSilence() {
        var policy = ClaudeSafariPromptPolicy()
        policy.companionWasSilent(at: start)
        #expect(!policy.asksToRestart(
            at: start.addingTimeInterval(600), trigger: .automatic, automaticPromptsOff: false
        ))
        policy.companionWasSilent(at: start.addingTimeInterval(30))
        #expect(!policy.asksToRestart(
            at: start.addingTimeInterval(30), trigger: .automatic, automaticPromptsOff: false
        ))
        policy.companionWasSilent(at: start.addingTimeInterval(180))
        #expect(policy.asksToRestart(
            at: start.addingTimeInterval(180), trigger: .automatic, automaticPromptsOff: false
        ))
    }

    @Test("An answer ends the silent stretch and the timer may ask again later")
    func answerResets() {
        var policy = ClaudeSafariPromptPolicy()
        policy.companionWasSilent(at: start)
        policy.companionWasSilent(at: start.addingTimeInterval(200))
        policy.didAsk(.restart)
        #expect(!policy.asksToRestart(
            at: start.addingTimeInterval(200), trigger: .automatic, automaticPromptsOff: false
        ))
        policy.companionAnswered()
        #expect(!policy.asksToRestart(
            at: start.addingTimeInterval(300), trigger: .automatic, automaticPromptsOff: false
        ))
        policy.companionWasSilent(at: start.addingTimeInterval(400))
        policy.companionWasSilent(at: start.addingTimeInterval(600))
        #expect(policy.asksToRestart(
            at: start.addingTimeInterval(600), trigger: .automatic, automaticPromptsOff: false
        ))
    }

    /// If a restart did not help, the timer must not ask for another every cycle.
    @Test("After a restart that did not help, the timer stays quiet")
    func restartDoesNotRepeat() {
        var policy = ClaudeSafariPromptPolicy()
        policy.companionWasSilent(at: start)
        policy.companionWasSilent(at: start.addingTimeInterval(200))
        policy.didAsk(.restart)
        policy.restartAttempted()
        policy.companionWasSilent(at: start.addingTimeInterval(800))
        policy.companionWasSilent(at: start.addingTimeInterval(1_400))
        #expect(!policy.asksToRestart(
            at: start.addingTimeInterval(1_400), trigger: .automatic, automaticPromptsOff: false
        ))
    }

    @Test("Both prompts warn in both languages what will happen")
    @MainActor
    func copyIsComplete() {
        for language in AppLanguage.allCases {
            let launch = ClaudeSafariPromptCopy.text(for: .launch, language: language)
            let restart = ClaudeSafariPromptCopy.text(for: .restart, language: language)
            #expect(launch.title.contains("Safari"))
            #expect(restart.title.contains("Safari"))
            #expect(!launch.stopAsking.isEmpty)
        }
        #expect(ClaudeSafariPromptCopy.text(for: .restart, language: .english).body
            .contains("save your work"))
        #expect(ClaudeSafariPromptCopy.text(for: .restart, language: .simplifiedChinese).body
            .contains("保存"))
    }
}

@Suite("Claude sync with Safari closed or silent", .timeLimit(.minutes(1)))
@MainActor
struct ClaudeSafariRecoveryModelTests {
    /// Everything a model needs, with Safari and its prompts under test control.
    @MainActor
    private final class Rig {
        let fixture = BrowserConnectorFixture(consent: true)
        let ticker = RecoveryTicker()
        let defaults: UserDefaults
        let suite = "auv-safari-recovery-\(UUID().uuidString)"
        var safariRunning = false
        var asked: [(ClaudeSafariPrompt, ClaudeSafariPromptTrigger)] = []
        var answer = ClaudeSafariPromptAnswer(accepted: false)
        var launches = 0
        var restarts = 0
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var model: ClaudeBrowserSettingsModel!

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            let consent = ClaudeBrowserConsentStore(defaults: defaults)
            consent.consentGranted = true
            let ticker = ticker
            let bridge = fixture.bridge
            model = ClaudeBrowserSettingsModel(
                connector: fixture.connector(),
                consentStore: consent,
                periodicSleep: { _ in await ticker.sleep() },
                safariIsRunning: { [weak self] in self?.safariRunning ?? false }
            )
            model.useSafariRecovery(ClaudeSafariRecovery(
                ask: { [weak self] prompt, trigger in
                    self?.asked.append((prompt, trigger))
                    return self?.answer ?? ClaudeSafariPromptAnswer(accepted: false)
                },
                launch: { [weak self] in
                    self?.launches += 1
                    self?.safariRunning = true
                    return true
                },
                restart: { [weak self] in
                    self?.restarts += 1
                    return true
                },
                now: { [weak self] in self?.now ?? Date() },
                // The wait between attempts is Safari's page coming up.
                sleep: { _ in await bridge.setHealth(.ready) }
            ))
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        func connect() async throws {
            model.connectWithConsent()
            try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
            try await waitForClaudeValue(model.$state, matching: { [model] _ in model!.offersAccuracySync })
        }

        /// A timer tick starts its sync on its own schedule, so this waits for
        /// that handshake to have happened and its sync to have finished.
        func waitForHandshake(_ count: Int) async throws {
            let deadline = Date().addingTimeInterval(30)
            while await fixture.bridge.healthChecks < count, Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(await fixture.bridge.healthChecks >= count)
            try await settle()
        }

        func waitForPrompt(_ count: Int) async throws {
            let deadline = Date().addingTimeInterval(30)
            while asked.count < count, Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
        }

        func settle() async throws {
            let deadline = Date().addingTimeInterval(30)
            while model.actionInProgress, Date() < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("Automatic refresh with Safari closed asks, and opens it only on yes")
    func timerAsksToLaunch() async throws {
        let rig = try Rig()
        try await rig.connect()
        rig.model.setAutomaticAccuracySync(every: 300)
        try await rig.ticker.waitForSleeper()

        await rig.ticker.tick()
        try await rig.ticker.waitForSleeper()
        #expect(rig.asked.map(\.0) == [.launch])
        #expect(rig.asked.first?.1 == .automatic)
        #expect(rig.launches == 0)
        #expect(await rig.fixture.bridge.automaticRequests.isEmpty)

        // "Not Now" holds for this closed stretch.
        await rig.ticker.tick()
        try await rig.ticker.waitForSleeper()
        #expect(rig.asked.count == 1)

        // Safari running and closed again is a new stretch.
        rig.safariRunning = true
        await rig.ticker.tick()
        try await rig.fixture.bridge.waitForAutomaticRequest()
        rig.safariRunning = false
        await rig.fixture.bridge.sendAutomation(
            requestID: try #require(await rig.fixture.bridge.automaticRequests.last?.requestID),
            status: .usageUnavailable
        )
        try await rig.settle()
        try await rig.ticker.waitForSleeper()
        rig.answer = ClaudeSafariPromptAnswer(accepted: true)
        await rig.ticker.tick()
        try await rig.fixture.bridge.waitForAutomaticRequest(count: 2)
        #expect(rig.asked.count == 2)
        #expect(rig.launches == 1)
        rig.model.setAutomaticAccuracySync(every: nil)
        await rig.ticker.tick()
    }

    @Test("The choice not to be asked silences the timer and survives a new model")
    func stopAskingSticks() async throws {
        let rig = try Rig()
        try await rig.connect()
        rig.answer = ClaudeSafariPromptAnswer(accepted: false, stopAskingDuringAutomaticRefresh: true)
        rig.model.setAutomaticAccuracySync(every: 300)
        try await rig.ticker.waitForSleeper()
        await rig.ticker.tick()
        try await rig.ticker.waitForSleeper()
        #expect(rig.asked.count == 1)
        #expect(ClaudeBrowserConsentStore(defaults: rig.defaults).automaticSafariPromptsOff)

        rig.safariRunning = true
        rig.safariRunning = false
        await rig.ticker.tick()
        try await rig.ticker.waitForSleeper()
        #expect(rig.asked.count == 1)

        // Refresh All is still the person's own request.
        #expect(rig.model.accuracySyncForRefreshAll())
        try await rig.settle()
        #expect(rig.asked.count == 2)
        #expect(rig.asked.last?.1 == .user)
        rig.model.setAutomaticAccuracySync(every: nil)
        await rig.ticker.tick()
    }

    @Test("Refresh All with Safari closed asks; no means no sync")
    func refreshAllAsks() async throws {
        let rig = try Rig()
        try await rig.connect()
        #expect(rig.model.accuracySyncForRefreshAll())
        try await rig.settle()
        #expect(rig.asked.map(\.0) == [.launch])
        #expect(rig.launches == 0)
        #expect(await rig.fixture.bridge.automaticRequests.isEmpty)

        rig.answer = ClaudeSafariPromptAnswer(accepted: true)
        #expect(rig.model.accuracySyncForRefreshAll())
        try await rig.fixture.bridge.waitForAutomaticRequest()
        #expect(rig.launches == 1)
    }

    /// Safari's background page takes a moment after launch, so one silent
    /// handshake then is not a failure yet.
    @Test("After opening Safari the sync is retried until the companion answers")
    func coldStartRetries() async throws {
        let rig = try Rig()
        try await rig.connect()
        await rig.fixture.bridge.setHealth(.companionStarting)
        rig.answer = ClaudeSafariPromptAnswer(accepted: true)
        #expect(rig.model.accuracySyncForRefreshAll())
        try await rig.fixture.bridge.waitForAutomaticRequest()
        #expect(rig.launches == 1)
        #expect(rig.asked.map(\.0) == [.launch])
    }

    @Test("A companion silent for minutes prompts a restart, once from the timer")
    func silentCompanionPromptsRestart() async throws {
        let rig = try Rig()
        rig.safariRunning = true
        try await rig.connect()
        await rig.fixture.bridge.setHealth(.companionStarting)
        rig.model.setAutomaticAccuracySync(every: 300)
        try await rig.ticker.waitForSleeper()

        await rig.ticker.tick()
        try await rig.waitForHandshake(1)
        try await rig.ticker.waitForSleeper()
        #expect(rig.asked.isEmpty)
        #expect(rig.model.offersAccuracySync)

        rig.now = rig.now.addingTimeInterval(300)
        await rig.ticker.tick()
        try await rig.waitForPrompt(1)
        try await rig.settle()
        try await rig.ticker.waitForSleeper()
        #expect(rig.asked.map(\.0) == [.restart])

        rig.now = rig.now.addingTimeInterval(300)
        await rig.ticker.tick()
        try await rig.waitForHandshake(3)
        try await rig.ticker.waitForSleeper()
        #expect(rig.asked.count == 1)
        #expect(rig.restarts == 0)

        // Once the companion answers, syncing carries on with no further prompt.
        await rig.fixture.bridge.setHealth(.ready)
        await rig.ticker.tick()
        try await rig.fixture.bridge.waitForAutomaticRequest()
        rig.model.setAutomaticAccuracySync(every: nil)
        await rig.ticker.tick()
    }

    @Test("Accepting the restart restarts Safari, then syncs")
    func acceptedRestartSyncs() async throws {
        let rig = try Rig()
        rig.safariRunning = true
        try await rig.connect()
        await rig.fixture.bridge.setHealth(.companionStarting)
        rig.answer = ClaudeSafariPromptAnswer(accepted: true)
        rig.model.accuracySync()
        try await rig.waitForHandshake(1)
        #expect(rig.asked.isEmpty)
        rig.now = rig.now.addingTimeInterval(200)
        rig.model.accuracySync()
        try await rig.fixture.bridge.waitForAutomaticRequest()
        #expect(rig.restarts == 1)
        #expect(rig.asked.map(\.0) == [.restart])
    }

    /// The timer and Refresh All only run from states that offer a sync, so a
    /// sync that cannot reach Safari must not leave one that stops the next.
    @Test("A sync that could not reach Safari does not stop the next one")
    func failedAttemptStatesStillSync() async throws {
        let rig = try Rig()
        rig.safariRunning = true
        try await rig.connect()
        for health: ClaudeBrowserCompanionHealth in [.companionStarting, .companionUnavailable, .browserUnavailable] {
            await rig.fixture.bridge.setHealth(health)
            let handshakes = await rig.fixture.bridge.healthChecks
            rig.model.accuracySync()
            try await rig.waitForHandshake(handshakes + 1)
            #expect(rig.model.offersAccuracySync, "after \(health)")
        }
        await rig.fixture.bridge.setHealth(.ready)
        #expect(rig.model.accuracySyncForRefreshAll())
        try await rig.fixture.bridge.waitForAutomaticRequest()
    }
}

/// Seen live on 0.18.4: with automatic refresh at ten minutes, Claude read
/// "Unavailable, no quota reading" from five minutes after each sync, with the
/// exact reading still stored, because a stale exact reading was not admitted.
@Suite("Claude's reading between syncs", .timeLimit(.minutes(1)))
struct ClaudeReadingBetweenSyncsTests {
    private func syncedConnector(
        _ fixture: BrowserConnectorFixture
    ) async throws -> ClaudeCodeUsageConnector {
        let connector = fixture.connector()
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 19, seven: 39))
        let deadline = Date().addingTimeInterval(30)
        while await connector.currentSnapshot().freshness != .fresh, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await connector.currentSnapshot().freshness == .fresh)
        return connector
    }

    @Test("A reading past five minutes stays on screen, marked stale")
    func staleReadingStaysVisible() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = try await syncedConnector(fixture)
        fixture.clock.advance(6 * 60)
        let snapshot = await connector.currentSnapshot()
        #expect(snapshot.freshness == .stale)
        #expect(LocalProviderEligibilityScanner.admission(
            for: snapshot, descriptor: connector.descriptor
        ).admittedSnapshot != nil)
        let provider = ProviderProductStatePolicy.reduce(
            snapshots: [snapshot],
            admissions: [],
            monitoringEnabledIDs: [ClaudeCodeUsageConnector.connectorID],
            previousCards: [],
            language: .english,
            now: fixture.clock.now()
        ).inventory.provider(.claude)
        #expect(provider?.primaryQuota != nil)
        #expect(provider?.connection == .connected)
        #expect(provider?.freshness == .stale)
    }

    @Test("A reading older than the limit is no longer shown")
    func oldReadingIsHidden() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = try await syncedConnector(fixture)
        fixture.clock.advance(ProviderUsageSurfacePolicy.claudeRetainedReadingLimit + 60)
        let snapshot = await connector.currentSnapshot()
        #expect(LocalProviderEligibilityScanner.admission(
            for: snapshot, descriptor: connector.descriptor
        ).admittedSnapshot == nil)
    }

    @Test("A sync that fails keeps the reading on screen")
    func failedSyncKeepsReading() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = try await syncedConnector(fixture)
        fixture.clock.advance(6 * 60)
        await fixture.bridge.setHealth(.companionStarting)
        await connector.accuracySync()
        let snapshot = await connector.currentSnapshot()
        #expect(LocalProviderEligibilityScanner.admission(
            for: snapshot, descriptor: connector.descriptor
        ).admittedSnapshot != nil)
    }

    /// Every automatic refresh interval must be covered, with one sync missed.
    @Test("The limit outlasts one missed sync at the longest interval")
    func limitCoversLongestInterval() {
        let longest = UMABackgroundRefreshInterval.allCases.map(\.seconds).max() ?? 0
        #expect(ProviderUsageSurfacePolicy.claudeRetainedReadingLimit >= 2 * longest)
    }
}

/// "Refresh every 5 minutes means to obtain the accurate data": between scheduled
/// syncs the last exact reading stands. Live, a local estimate read 48% six
/// minutes after an exact 74%.
@Suite("Exact readings under automatic refresh", .timeLimit(.minutes(1)))
struct ClaudeExactUnderAutomaticRefreshTests {
    private func syncedConnector(
        _ fixture: BrowserConnectorFixture,
        interval: TimeInterval?
    ) async throws -> ClaudeCodeUsageConnector {
        let connector = fixture.connector()
        await connector.setAutomaticAccuracySyncInterval(interval)
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 19, seven: 39))
        let deadline = Date().addingTimeInterval(30)
        while await connector.currentSnapshot().freshness != .fresh, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        return connector
    }

    @Test("A reading stays exact and current until the next sync has had its chance",
          arguments: [(300.0, 6.5), (600.0, 11.5), (3_600.0, 61.0)])
    func readingLastsThroughTheInterval(interval: TimeInterval, minutes: Double) async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = try await syncedConnector(fixture, interval: interval)
        fixture.clock.advance(minutes * 60)
        let snapshot = await connector.currentSnapshot()
        #expect(snapshot.freshness == .fresh)
        #expect(snapshot.channels.first { $0.id == .account }?.sourceConfidence == "exact")
    }

    @Test("Past that, or with automatic refresh off, the reading is no longer current",
          arguments: [(600.0 as TimeInterval?, 12.5), (nil, 6.0)])
    func readingEnds(interval: TimeInterval?, minutes: Double) async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = try await syncedConnector(fixture, interval: interval)
        fixture.clock.advance(minutes * 60)
        #expect(await connector.currentSnapshot().freshness == .stale)
    }

    @Test("Every interval's window covers it, and never shortens the base five minutes")
    func windows() {
        for interval in UMABackgroundRefreshInterval.allCases {
            #expect(ClaudeSmartSourceSelector.safariCurrentWindow(
                automaticSyncInterval: interval.seconds
            ) >= interval.seconds + ClaudeSettingsRetryExpectations.finishedRetry)
        }
        #expect(ClaudeSmartSourceSelector.safariCurrentWindow(automaticSyncInterval: nil)
            == ClaudeSmartSourceSelector.exactFreshnessInterval)
    }
}

@MainActor
private enum ClaudeSettingsRetryExpectations {
    /// The retry's delay plus the connector's own limit on its read.
    nonisolated static let finishedRetry: TimeInterval = 20 + 45
}

@Suite("Retrying a timed sync", .timeLimit(.minutes(1)))
@MainActor
struct ClaudeAutomaticRetryTests {
    private func model(
        fixture: BrowserConnectorFixture,
        ticker: RecoveryTicker,
        retries: RecoveryTicker,
        defaults: UserDefaults
    ) async throws -> ClaudeBrowserSettingsModel {
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let model = ClaudeBrowserSettingsModel(
            connector: fixture.connector(),
            consentStore: consent,
            periodicSleep: { _ in await ticker.sleep() },
            safariIsRunning: { true },
            automaticRetrySleep: { _ in await retries.sleep() }
        )
        model.connectWithConsent()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        try await waitForClaudeValue(model.$state, matching: { _ in model.offersAccuracySync })
        return model
    }

    @Test("A timed read whose page never answered is tried once more")
    func failedReadRetriesOnce() async throws {
        let suite = "auv-retry-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = BrowserConnectorFixture(consent: true)
        let ticker = RecoveryTicker()
        let retries = RecoveryTicker()
        let model = try await model(
            fixture: fixture, ticker: ticker, retries: retries, defaults: defaults
        )
        model.setAutomaticAccuracySync(every: 600)
        try await ticker.waitForSleeper()
        await ticker.tick()
        try await fixture.bridge.waitForAutomaticRequest()
        let first = try #require(await fixture.bridge.automaticRequests.first?.requestID)
        await fixture.bridge.sendAutomation(requestID: first, status: .tabUnavailable)
        try await retries.waitForSleeper()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        await retries.tick()
        try await fixture.bridge.waitForAutomaticRequest(count: 2)
        // The retry does not set up another retry of its own.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await retries.hasSleeper == false)
        model.setAutomaticAccuracySync(every: nil)
        await ticker.tick()
    }

    @Test("A read right after Safari starts is retried, even with automatic refresh off")
    func readAfterStartingSafariRetries() async throws {
        let suite = "auv-retry-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = BrowserConnectorFixture(consent: true)
        let ticker = RecoveryTicker()
        let retries = RecoveryTicker()
        let running = RecoverySafariState(false)
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let model = ClaudeBrowserSettingsModel(
            connector: fixture.connector(),
            consentStore: consent,
            periodicSleep: { _ in await ticker.sleep() },
            safariIsRunning: { running.value },
            automaticRetrySleep: { _ in await retries.sleep() }
        )
        model.connectWithConsent()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        try await waitForClaudeValue(model.$state, matching: { _ in model.offersAccuracySync })
        model.useSafariRecovery(ClaudeSafariRecovery(
            ask: { _, _ in ClaudeSafariPromptAnswer(accepted: true, stopAskingDuringAutomaticRefresh: false) },
            launch: { running.value = true; return true },
            restart: { true },
            now: { Date() },
            sleep: { _ in }
        ))
        #expect(model.accuracySyncForRefreshAll())
        try await fixture.bridge.waitForAutomaticRequest()
        let first = try #require(await fixture.bridge.automaticRequests.first?.requestID)
        await fixture.bridge.sendAutomation(requestID: first, status: .tabUnavailable)
        try await retries.waitForSleeper()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        await retries.tick()
        try await fixture.bridge.waitForAutomaticRequest(count: 2)
    }

    @Test("A timed read that brought a reading is not repeated")
    func successfulReadDoesNotRetry() async throws {
        let suite = "auv-retry-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = BrowserConnectorFixture(consent: true)
        let ticker = RecoveryTicker()
        let retries = RecoveryTicker()
        let model = try await model(
            fixture: fixture, ticker: ticker, retries: retries, defaults: defaults
        )
        model.setAutomaticAccuracySync(every: 600)
        try await ticker.waitForSleeper()
        await ticker.tick()
        try await fixture.bridge.waitForAutomaticRequest()
        try await retries.waitForSleeper()
        await fixture.bridge.send(browserEnvelope(five: 19, seven: 39))
        try await waitForClaudeValue(model.$browserAccuracyStage, matching: { $0 == .accuracyExactReceived })
        await retries.tick()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await fixture.bridge.automaticRequests.count == 1)
        model.setAutomaticAccuracySync(every: nil)
        await ticker.tick()
    }

    @Test("Turning automatic refresh off cancels a pending retry")
    func turningOffCancelsRetry() async throws {
        let suite = "auv-retry-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = BrowserConnectorFixture(consent: true)
        let ticker = RecoveryTicker()
        let retries = RecoveryTicker()
        let model = try await model(
            fixture: fixture, ticker: ticker, retries: retries, defaults: defaults
        )
        model.setAutomaticAccuracySync(every: 600)
        try await ticker.waitForSleeper()
        await ticker.tick()
        try await fixture.bridge.waitForAutomaticRequest()
        let first = try #require(await fixture.bridge.automaticRequests.first?.requestID)
        await fixture.bridge.sendAutomation(requestID: first, status: .tabUnavailable)
        try await retries.waitForSleeper()
        model.setAutomaticAccuracySync(every: nil)
        await retries.tick()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await fixture.bridge.automaticRequests.count == 1)
        await ticker.tick()
    }
}

/// A sleeper the test advances by hand. The deadlines in this file allow for the
/// main actor being queued for 25 seconds and more during a full-suite run.
private actor RecoveryTicker {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    func tick() {
        let resumed = waiters
        waiters = []
        resumed.forEach { $0.resume() }
    }

    var hasSleeper: Bool { !waiters.isEmpty }

    func waitForSleeper() async throws {
        let deadline = Date().addingTimeInterval(30)
        while waiters.isEmpty {
            guard Date() < deadline else {
                Issue.record("No sleeper within 30s")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class RecoverySafariState {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

@Suite("Safari prompt safety")
struct ClaudeSafariPromptSafetyTests {
    @Test("Accepting a restart waits longer than the stray click that was seen")
    func restartWaitsPastTheSeenClick() {
        #expect(ClaudeSafariPromptSafety.acceptButtonDelay(for: .restart) > 3.2)
        #expect(ClaudeSafariPromptSafety.acceptButtonDelay(for: .launch) >= 1)
    }

    @Test("Return never restarts Safari")
    func returnDoesNotRestart() {
        #expect(!ClaudeSafariPromptSafety.returnKeyAccepts(.restart))
        #expect(ClaudeSafariPromptSafety.returnKeyAccepts(.launch))
    }
}
