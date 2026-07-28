import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2WACCOUNT-R1 WorkBuddy account auto-refresh")
struct WorkBuddyAccountAutoRefreshTests {
    @Test @MainActor
    func absentPreferenceDefaultsOnAndExplicitChoicePersists() async {
        let suite = "WorkBuddyAccountAutoRefreshTests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = WorkBuddyAccountWebSessionController(
            defaults: defaults,
            websiteDataClearer: { true }
        )
        #expect(fresh.autoRefreshEnabled)
        #expect(
            defaults.object(
                forKey: WorkBuddyAccountWebSessionController
                    .autoRefreshEnabledKey
            ) == nil
        )

        fresh.autoRefreshEnabled = false
        let restoredOff = WorkBuddyAccountWebSessionController(
            defaults: defaults,
            websiteDataClearer: { true }
        )
        #expect(!restoredOff.autoRefreshEnabled)

        restoredOff.autoRefreshEnabled = true
        let restoredOn = WorkBuddyAccountWebSessionController(
            defaults: defaults,
            websiteDataClearer: { true }
        )
        #expect(restoredOn.autoRefreshEnabled)
        await restoredOn.disconnectAndClearOwnedWebsiteData()
        #expect(
            defaults.bool(
                forKey: WorkBuddyAccountWebSessionController
                    .autoRefreshEnabledKey
            )
        )
    }

    @Test @MainActor
    func schedulerOwnsExactlyOneSixtySecondTimerAndNeverCatchesUp() async {
        let sleeper = AutoRefreshTestSleeper()
        let probe = AutoRefreshFireProbe()
        let scheduler = WorkBuddyAccountSyncScheduler(
            sleeper: { duration in
                try await sleeper.sleep(for: duration)
            },
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )
        scheduler.configure { [weak scheduler] in
            probe.record()
            scheduler?.readWillStart()
            scheduler?.readDidFinish()
        }

        scheduler.update(enabled: true, eligible: false)
        #expect(scheduler.diagnostics().timerCount == 0)
        scheduler.update(enabled: true, eligible: true)
        #expect(await sleeper.waitForSleepCount(1))
        #expect(scheduler.diagnostics().timerCount == 1)
        #expect(await sleeper.recordedDurations == [.seconds(60)])

        scheduler.update(enabled: true, eligible: true)
        #expect(scheduler.diagnostics().timerCount == 1)
        #expect(await sleeper.recordedDurations == [.seconds(60)])

        await sleeper.releaseOne()
        #expect(await probe.waitForCount(1))
        #expect(await sleeper.waitForSleepCount(2))
        #expect(
            await sleeper.recordedDurations
                == [.seconds(60), .seconds(60)]
        )
        #expect(scheduler.diagnostics().timerCount == 1)

        await sleeper.releaseOne()
        #expect(await probe.waitForCount(2))
        #expect(await sleeper.waitForSleepCount(3))
        #expect(scheduler.diagnostics().scheduledReadCount == 2)
        #expect(scheduler.diagnostics().timerCount == 1)
        scheduler.cancel()
        #expect(scheduler.diagnostics().timerCount == 0)
    }

    @Test @MainActor
    func manualReadResetsPendingTimerAndManualOnlyCancelsIt() async {
        let sleeper = AutoRefreshTestSleeper()
        let probe = AutoRefreshFireProbe()
        let scheduler = WorkBuddyAccountSyncScheduler(
            sleeper: { duration in
                try await sleeper.sleep(for: duration)
            }
        )
        scheduler.configure {
            probe.record()
        }
        scheduler.update(enabled: true, eligible: true)
        #expect(await sleeper.waitForSleepCount(1))

        scheduler.readWillStart()
        #expect(scheduler.diagnostics().timerCount == 0)
        scheduler.readDidFinish()
        #expect(await sleeper.waitForSleepCount(2))
        #expect(scheduler.diagnostics().timerCount == 1)

        scheduler.update(enabled: false, eligible: true)
        #expect(scheduler.diagnostics().timerCount == 0)
        await sleeper.releaseOne()
        await Task.yield()
        #expect(probe.count == 0)
    }

    @Test @MainActor
    func authExpirySuspendsAndExtractionFailureUsesOnlyNormalCadence()
        async throws
    {
        let suite = "WorkBuddyAccountAutoRefreshTests.auth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try establishAcceptedPersistentSession(in: defaults)

        let authSleeper = AutoRefreshTestSleeper()
        let authController = WorkBuddyAccountWebSessionController(
            defaults: defaults,
            websiteDataClearer: { true },
            autoRefreshSleeper: { duration in
                try await authSleeper.sleep(for: duration)
            },
            readOverride: { .authenticationRequired }
        )
        authController.configureAutoRefresh {}
        #expect(await authController.readCurrentCredits() == .authenticationRequired)
        #expect(authController.flowState != .connected)
        #expect(authController.autoRefreshDiagnostics().timerCount == 0)
        #expect(await authSleeper.recordedDurations.isEmpty)

        try establishAcceptedPersistentSession(in: defaults)
        let failureSleeper = AutoRefreshTestSleeper()
        let failureController = WorkBuddyAccountWebSessionController(
            defaults: defaults,
            websiteDataClearer: { true },
            autoRefreshSleeper: { duration in
                try await failureSleeper.sleep(for: duration)
            },
            readOverride: { .failure(.incompletePoolSections) }
        )
        failureController.configureAutoRefresh {}
        #expect(
            await failureController.readCurrentCredits()
                == .failure(.incompletePoolSections)
        )
        #expect(await failureSleeper.waitForSleepCount(1))
        #expect(
            await failureSleeper.recordedDurations == [.seconds(60)]
        )
        #expect(failureController.autoRefreshDiagnostics().timerCount == 1)
        failureController.tearDown()

        defaults.removeObject(
            forKey: WorkBuddyAccountWebSessionController
                .sessionEstablishedKey
        )
        let freshFailureSleeper = AutoRefreshTestSleeper()
        let freshFailureController = WorkBuddyAccountWebSessionController(
            defaults: defaults,
            websiteDataClearer: { true },
            autoRefreshSleeper: { duration in
                try await freshFailureSleeper.sleep(for: duration)
            },
            readOverride: { .failure(.malformedCredits) }
        )
        freshFailureController.configureAutoRefresh {}
        #expect(
            await freshFailureController.readCurrentCredits()
                == .failure(.malformedCredits)
        )
        #expect(await freshFailureSleeper.waitForSleepCount(1))
        #expect(
            await freshFailureSleeper.recordedDurations == [.seconds(60)]
        )
        freshFailureController.tearDown()
    }

    @Test @MainActor
    func concurrentTriggersPublishOneCoalescedResult() async {
        let source = BlockingAccountReader()
        let connector = WorkBuddyAccountWebCreditsConnector(
            hasConsent: { true },
            reader: { await source.next() },
            disconnectOwnedSession: {}
        )

        let first = Task { await connector.refresh(trigger: .timer) }
        #expect(await source.waitUntilActive())
        let second = Task { await connector.refresh(trigger: .manual) }
        let third = Task { await connector.perform(.refresh) }
        await Task.yield()
        await source.release()
        await first.value
        await second.value
        await third.value

        let diagnostics = await connector.readDiagnostics()
        #expect(await source.readCount == 1)
        #expect(await source.maximumActiveCount == 1)
        #expect(diagnostics.active == 0)
        #expect(diagnostics.completed == 1)
        #expect(diagnostics.coalesced == 2)
        #expect(diagnostics.publications == 1)
    }

    @Test @MainActor
    func disconnectInvalidatesAnInFlightReadBeforeItCanPublish() async {
        let source = BlockingAccountReader()
        let connector = WorkBuddyAccountWebCreditsConnector(
            hasConsent: { true },
            reader: { await source.next() },
            disconnectOwnedSession: {}
        )

        let read = Task { await connector.refresh(trigger: .timer) }
        #expect(await source.waitUntilActive())
        await connector.perform(.disconnect)
        let disconnected = await connector.currentSnapshot()
        #expect(disconnected.state == .authenticationRequired)

        await source.release()
        await read.value
        let afterStaleCompletion = await connector.currentSnapshot()
        #expect(afterStaleCompletion.state == .authenticationRequired)
        let diagnostics = await connector.readDiagnostics()
        #expect(diagnostics.active == 0)
        #expect(diagnostics.completed == 0)
        #expect(diagnostics.publications == 1)
    }

    @Test @MainActor
    func disconnectInvalidatesTheSessionControllersInFlightRead() async {
        let suite =
            "WorkBuddyAccountAutoRefreshTests.disconnect-race."
                + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = BlockingAccountReader()
        let controller = WorkBuddyAccountWebSessionController(
            defaults: defaults,
            websiteDataClearer: { true },
            readOverride: { await source.next() }
        )
        controller.grantConsent()

        let read = Task { await controller.readCurrentCredits() }
        #expect(await source.waitUntilActive())
        await controller.disconnectAndClearOwnedWebsiteData()
        await source.release()

        #expect(
            await read.value == .failure(.webContentUnavailable)
        )
        #expect(!controller.consentGranted)
        #expect(controller.flowState == .idle)
        #expect(controller.lastSynchronizedAt == nil)
        #expect(controller.latestCreditSnapshot == nil)
        #expect(controller.autoRefreshDiagnostics().timerCount == 0)
        #expect(controller.accountReadDiagnostics.active == 0)
        #expect(controller.accountReadDiagnostics.completed == 0)
    }

    @Test
    func schedulerAndWebViewOwnershipStayInTheAccountSourceLayer() throws {
        let root = packageRoot()
        let scheduler = try source(
            "Sources/CodexUsageUI/Services/WorkBuddyAccountSyncScheduler.swift",
            root: root
        )
        let controller = try source(
            "Sources/CodexUsageUI/Services/WorkBuddyAccountWebSessionController.swift",
            root: root
        )
        let settings = try source(
            "Sources/CodexUsageUI/Views/UsageSettingsCard.swift",
            root: root
        )
        let assistant = try source(
            "Sources/CodexUsageUI/Views/DesktopAssistantView.swift",
            root: root
        )
        let panel = try source(
            "Sources/CodexUsageUI/Views/UsagePanelView.swift",
            root: root
        )

        #expect(scheduler.contains("static let interval = Duration.seconds(60)"))
        #expect(scheduler.contains("private var task: Task<Void, Never>?"))
        #expect(scheduler.contains("guard enabled, eligible"))
        #expect(!scheduler.contains("while true"))
        #expect(controller.components(separatedBy: "private var webView:").count == 2)
        for forbiddenOwner in [settings, assistant, panel] {
            #expect(!forbiddenOwner.contains("WorkBuddyAccountSyncScheduler("))
            #expect(!forbiddenOwner.contains("readCurrentCredits()"))
        }
        #expect(!assistant.contains("autoRefresh"))

        let connectStart = try #require(
            controller.range(of: "public func connect()")
        )
        let openUsageStart = try #require(
            controller.range(
                of: "public func openAccountUsage()",
                range: connectStart.upperBound..<controller.endIndex
            )
        )
        let connectImplementation = controller[
            connectStart.lowerBound..<openUsageStart.lowerBound
        ]
        let release = try #require(
            connectImplementation.range(of: "releaseBrowser()")
        )
        let ensure = try #require(
            connectImplementation.range(of: "ensureBrowser()")
        )
        #expect(release.lowerBound < ensure.lowerBound)
    }

    @Test
    func conciseSettingsAndRequiredLocalizationsArePresent() throws {
        let root = packageRoot()
        let settings = try source(
            "Sources/CodexUsageUI/Views/UsageSettingsCard.swift",
            root: root
        )
        #expect(settings.contains("$controller.autoRefreshEnabled"))
        #expect(settings.contains("workBuddyAccountManualOnly"))
        #expect(settings.contains("controller.nextAutoRefreshAt"))
        #expect(settings.contains("workBuddyAccountNextRefresh"))
        #expect(settings.contains("TimelineView(.periodic(from: .now, by: 1))"))
        #expect(settings.contains("secondaryActions"))
        #expect(settings.contains("sourceAndPrivacyDetails"))

        #expect(AppLanguage.english.workBuddyAccountAutoRefresh == "Auto Refresh")
        #expect(AppLanguage.english.workBuddyAccountEveryMinute == "Every minute")
        #expect(AppLanguage.english.workBuddyAccountManualOnly == "Manual only")
        #expect(
            AppLanguage.english.workBuddyAccountNextRefresh(
                AppLanguage.english.workBuddyAccountRefreshInterval(seconds: 42)
            ) == "Next refresh in 42s"
        )
        #expect(AppLanguage.english.workBuddyAccountWebSyncNow == "Sync Now")
        #expect(
            AppLanguage.english.workBuddyAccountUpdatedJustNow
                == "Updated just now"
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        #expect(
            AppLanguage.english.workBuddyAccountUpdated(
                at: now.addingTimeInterval(-125),
                now: now
            ) == "Updated 2m ago"
        )
        #expect(
            AppLanguage.english.workBuddyAccountSignInRequired
                == "Sign in required"
        )
        #expect(
            AppLanguage.english.workBuddyAccountCouldNotReadCredits
                == "Could not read current Credits"
        )
        #expect(AppLanguage.english.workBuddyExperimentalLabel == "Experimental")

        #expect(AppLanguage.simplifiedChinese.workBuddyAccountAutoRefresh == "自动刷新")
        #expect(AppLanguage.simplifiedChinese.workBuddyAccountEveryMinute == "每分钟")
        #expect(AppLanguage.simplifiedChinese.workBuddyAccountManualOnly == "仅手动")
        #expect(
            AppLanguage.simplifiedChinese.workBuddyAccountNextRefresh(
                AppLanguage.simplifiedChinese
                    .workBuddyAccountRefreshInterval(seconds: 42)
            ) == "下次刷新：42 秒"
        )
        #expect(AppLanguage.simplifiedChinese.workBuddyAccountWebSyncNow == "立即同步")
        #expect(
            AppLanguage.simplifiedChinese.workBuddyAccountUpdatedJustNow
                == "刚刚更新"
        )
        #expect(
            AppLanguage.simplifiedChinese.workBuddyAccountUpdated(
                at: now.addingTimeInterval(-125),
                now: now
            ) == "2 分钟前更新"
        )
        #expect(
            AppLanguage.simplifiedChinese.workBuddyAccountSignInRequired
                == "需要重新登录"
        )
        #expect(
            AppLanguage.simplifiedChinese.workBuddyAccountCouldNotReadCredits
                == "无法读取当前积分"
        )
        #expect(
            AppLanguage.simplifiedChinese.workBuddyExperimentalLabel == "实验性"
        )
    }

    @Test @MainActor
    func connectedRendererPreviewShowsCountdownOnlyWhenAutomatic() {
        let observedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let automatic = WorkBuddyAccountWebSessionController.previewConnected(
            autoRefreshEnabled: true,
            observedAt: observedAt
        )
        #expect(
            automatic.nextAutoRefreshAt
                == observedAt.addingTimeInterval(60)
        )

        let manual = WorkBuddyAccountWebSessionController.previewConnected(
            autoRefreshEnabled: false,
            observedAt: observedAt
        )
        #expect(manual.nextAutoRefreshAt == nil)
    }

    @Test
    func packageContractTargetsTheR1CommitExactPath() throws {
        let script = try source(
            "script/package_uma_workbuddy_account.sh",
            root: packageRoot()
        )
        #expect(script.contains("DEFAULT_BUILD=\"202607260001\""))
        #expect(
            script.contains(
                "/private/tmp/uma-workbuddy-autorefresh-final-$short_commit/UMA.app"
            )
        )
        #expect(script.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(script.contains("codesign --verify --deep --strict"))
    }

    @MainActor
    private func establishAcceptedPersistentSession(
        in defaults: UserDefaults
    ) throws {
        let record = WorkBuddyAccountWebConsentRecord(
            disclosureVersion:
                WorkBuddyAccountWebConsentRecord.currentDisclosureVersion,
            acceptedAt: Date(),
            sessionMode: .persistent
        )
        defaults.set(
            try JSONEncoder().encode(record),
            forKey: "workbuddy.accountWebSync.consent.v1"
        )
        defaults.set(
            true,
            forKey: WorkBuddyAccountWebSessionController.sessionEstablishedKey
        )
    }

    private func source(_ path: String, root: URL) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private actor AutoRefreshTestSleeper {
    private(set) var recordedDurations: [Duration] = []
    private var releases = 0

    func sleep(for duration: Duration) async throws {
        recordedDurations.append(duration)
        while releases == 0 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(1))
        }
        releases -= 1
    }

    func releaseOne() {
        releases += 1
    }

    func waitForSleepCount(_ expected: Int) async -> Bool {
        for _ in 0..<5_000 {
            if recordedDurations.count >= expected { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

@MainActor
private final class AutoRefreshFireProbe {
    private(set) var count = 0

    func record() {
        count += 1
    }

    func waitForCount(_ expected: Int) async -> Bool {
        for _ in 0..<5_000 {
            if count >= expected { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private actor BlockingAccountReader {
    private(set) var readCount = 0
    private(set) var maximumActiveCount = 0
    private var activeCount = 0
    private var isReleased = false

    func next() async -> WorkBuddyAccountWebReadResult {
        readCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        while !isReleased {
            try? await Task.sleep(for: .milliseconds(1))
        }
        activeCount -= 1
        return .authenticationRequired
    }

    func release() {
        isReleased = true
    }

    func waitUntilActive() async -> Bool {
        for _ in 0..<5_000 {
            if activeCount == 1 { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}
