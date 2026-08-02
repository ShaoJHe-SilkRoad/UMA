import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2WLOGIN-G1 official WorkBuddy login assistance")
struct WorkBuddyLoginAssistanceTests {
    @Test
    func installationDiscoveryMatrixIsIdentityFirstAndDeterministic() {
        let fallback = URL(fileURLWithPath: "/Applications/WorkBuddy.app")
        let renamed = URL(fileURLWithPath: "/Applications/Official Buddy.app")
        let duplicate = URL(fileURLWithPath: "/Applications/WorkBuddy Copy.app")

        #expect(
            WorkBuddyApplicationAccess.resolve(candidates: []) == .notInstalled
        )
        #expect(
            WorkBuddyApplicationAccess.resolve(
                candidates: [
                    candidate(
                        fallback,
                        id: "not.workbuddy",
                        trust: .trusted
                    )
                ]
            ) == .invalidBundleIdentity(found: "not.workbuddy")
        )

        for (url, trust) in [
            (fallback, WorkBuddySignatureTrust.trusted),
            (renamed, .unverifiable),
            (duplicate, .rejected)
        ] {
            let status = WorkBuddyApplicationAccess.resolve(
                candidates: [candidate(url, trust: trust)]
            )
            let application = status.application
            #expect(application?.url == url)
            #expect(application?.bundleIdentifier == "com.workbuddy.workbuddy")
            #expect(application?.signatureTrust == trust)
        }

        let preferred = WorkBuddyApplicationAccess.resolve(
            candidates: [
                candidate(
                    URL(fileURLWithPath: "/Applications/Fake.app"),
                    id: "fake.id",
                    trust: .trusted
                ),
                candidate(renamed, trust: .trusted),
                candidate(fallback, trust: .trusted)
            ]
        )
        #expect(preferred.application?.url == renamed)
    }

    @MainActor
    @Test
    func privacyAndUnverifiedSignatureRequireSeparateExplicitConsent() {
        let access = FakeWorkBuddyApplicationAccess(
            status: .available(application(trust: .unverifiable))
        )
        let persistence = InMemoryWorkBuddyLoginPersistence()
        let coordinator = WorkBuddyLoginCoordinator(
            applicationAccess: access,
            persistence: persistence
        )
        defer { coordinator.tearDown() }

        coordinator.startLogin()
        #expect(coordinator.flowState == .confirmationRequired)
        #expect(!coordinator.canOpenOfficialApplication)
        coordinator.openOfficialApplication()
        #expect(coordinator.flowState == .failed(.privacyConfirmationRequired))

        coordinator.setPrivacyConfirmed(true)
        coordinator.openOfficialApplication()
        #expect(
            coordinator.flowState
                == .failed(.officialInstallConfirmationRequired)
        )

        coordinator.setOfficialInstallConfirmed(true)
        #expect(coordinator.flowState == .readyToOpen)
        #expect(coordinator.canOpenOfficialApplication)
        #expect(persistence.record?.privacyConfirmedAt != nil)
        #expect(persistence.record?.officialInstallConfirmedAt != nil)
        #expect(persistence.record?.officialInstallIdentity == "install-a")
        #expect(persistence.record?.warningDismissed == true)
    }

    @MainActor
    @Test(arguments: [
        (
            WorkBuddyInstallationStatus.notInstalled,
            WorkBuddyLoginFlowState.failed(.applicationNotInstalled)
        ),
        (
            .invalidBundleIdentity(found: "wrong.bundle"),
            .failed(.invalidBundleIdentity)
        )
    ])
    func missingAndWrongIdentityFailClosed(
        status: WorkBuddyInstallationStatus,
        expected: WorkBuddyLoginFlowState
    ) {
        let coordinator = WorkBuddyLoginCoordinator(
            applicationAccess: FakeWorkBuddyApplicationAccess(status: status),
            persistence: InMemoryWorkBuddyLoginPersistence()
        )
        defer { coordinator.tearDown() }
        coordinator.startLogin()
        #expect(coordinator.flowState == expected)
        #expect(!coordinator.canOpenOfficialApplication)
    }

    @MainActor
    @Test
    func relaunchRestoresOnlyConfirmationBoundToTheSameInstallation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistence = InMemoryWorkBuddyLoginPersistence()
        let installed = application(
            trust: .unverifiable,
            identity: "install-a"
        )
        persistence.record = WorkBuddyLoginPersistenceRecord(
            accountMode: .enterprise,
            privacyConfirmedAt: now,
            officialInstallConfirmedAt: now,
            officialInstallIdentity: installed.installationIdentity,
            flowStartedAt: now,
            userCompletedAt: now,
            safeResult: .unsupportedLocalCreditsSource,
            installState: .installedNeedsConfirmation,
            warningDismissed: true
        )
        let coordinator = WorkBuddyLoginCoordinator(
            applicationAccess: FakeWorkBuddyApplicationAccess(
                status: .available(installed)
            ),
            persistence: persistence
        )
        defer { coordinator.tearDown() }
        #expect(coordinator.accountMode == .enterprise)
        #expect(coordinator.privacyConfirmed)
        #expect(coordinator.officialInstallConfirmed)
        #expect(coordinator.flowWasLaunched)
        #expect(coordinator.userConfirmedCompleted)
        #expect(!coordinator.machineVerifiedAuthentication)
        #expect(coordinator.safeResult == .unsupportedLocalCreditsSource)
        #expect(coordinator.flowState == .idle)

        coordinator.tearDown()
        let replaced = WorkBuddyLoginCoordinator(
            applicationAccess: FakeWorkBuddyApplicationAccess(
                status: .available(
                    application(
                        trust: .unverifiable,
                        identity: "install-b"
                    )
                )
            ),
            persistence: persistence
        )
        defer { replaced.tearDown() }
        #expect(!replaced.officialInstallConfirmed)
        #expect(!replaced.canOpenOfficialApplication)
        #expect(persistence.record?.officialInstallConfirmedAt == nil)
        #expect(persistence.record?.officialInstallIdentity == nil)
    }

    @Test
    func runningApplicationMatchingUsesTheExactReviewedBundleURL() {
        let reviewed = URL(fileURLWithPath: "/Applications/WorkBuddy.app")
        #expect(
            WorkBuddyApplicationAccess.applicationURLsMatch(
                reviewed,
                reviewed
            )
        )
        #expect(
            !WorkBuddyApplicationAccess.applicationURLsMatch(
                URL(fileURLWithPath: "/private/tmp/WorkBuddy.app"),
                reviewed
            )
        )
        #expect(
            !WorkBuddyApplicationAccess.applicationURLsMatch(nil, reviewed)
        )
    }

    @MainActor
    @Test
    func trustedLaunchCheckAgainAndConcurrentCoalescingStayHonest() async {
        let access = FakeWorkBuddyApplicationAccess(
            status: .available(application(trust: .trusted)),
            launchResult: .launched
        )
        let checker = CountingWorkBuddyLoginChecker(delay: .milliseconds(25))
        let coordinator = WorkBuddyLoginCoordinator(
            applicationAccess: access,
            persistence: InMemoryWorkBuddyLoginPersistence(),
            eligibilityChecker: checker
        )
        defer { coordinator.tearDown() }

        coordinator.startLogin()
        coordinator.setPrivacyConfirmed(true)
        coordinator.openOfficialApplication()
        await settle()
        #expect(access.openCount == 1)
        #expect(coordinator.flowState == .awaitingUserCompletion)
        #expect(coordinator.safeResult == .flowLaunched)
        #expect(coordinator.flowWasLaunched)
        #expect(!coordinator.userConfirmedCompleted)
        #expect(!coordinator.machineVerifiedAuthentication)

        coordinator.checkAgain()
        coordinator.checkAgain()
        await settle(milliseconds: 60)
        #expect(await checker.count == 1)
        #expect(coordinator.completedEligibilityCheckCount == 1)
        #expect(coordinator.flowState == .completed)
        #expect(coordinator.safeResult == .unsupportedLocalCreditsSource)
        #expect(coordinator.userConfirmedCompleted)
        #expect(!coordinator.machineVerifiedAuthentication)
    }

    @MainActor
    @Test(arguments: [
        (WorkBuddyApplicationLaunchResult.activated, WorkBuddyLoginFlowState.awaitingUserCompletion),
        (.denied, .failed(.launchDenied)),
        (.failed, .failed(.launchFailed))
    ])
    func launchOutcomesAreExplicit(
        result: WorkBuddyApplicationLaunchResult,
        expected: WorkBuddyLoginFlowState
    ) async {
        let access = FakeWorkBuddyApplicationAccess(
            status: .available(application(trust: .trusted)),
            launchResult: result
        )
        let coordinator = WorkBuddyLoginCoordinator(
            applicationAccess: access,
            persistence: InMemoryWorkBuddyLoginPersistence()
        )
        defer { coordinator.tearDown() }
        coordinator.startLogin()
        coordinator.setPrivacyConfirmed(true)
        coordinator.openOfficialApplication()
        await settle()
        #expect(coordinator.flowState == expected)
    }

    @MainActor
    @Test
    func cancelTimeoutLifecycleAndObserverCleanupAreBounded() async {
        let access = FakeWorkBuddyApplicationAccess(
            status: .available(application(trust: .trusted))
        )
        let coordinator = WorkBuddyLoginCoordinator(
            applicationAccess: access,
            persistence: InMemoryWorkBuddyLoginPersistence(),
            timeout: .milliseconds(15),
            timeoutSleeper: { _ in }
        )
        coordinator.startLogin()
        coordinator.setPrivacyConfirmed(true)
        coordinator.openOfficialApplication()
        for _ in 0..<100
        where coordinator.flowState != .failed(.timedOut) {
            await Task.yield()
        }
        #expect(coordinator.flowState == .failed(.timedOut))

        coordinator.startLogin()
        coordinator.cancel()
        #expect(coordinator.flowState == .cancelled)

        access.status = .notInstalled
        access.postLifecycle()
        #expect(coordinator.installation == .notInstalled)
        #expect(access.observerCount == 1)
        coordinator.tearDown()
        #expect(access.observerCount == 0)
    }

    @MainActor
    @Test
    func persistenceIsVersionedBoundedAndContainsNoSensitiveFields() throws {
        let suiteName = "m2wlogin-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WorkBuddyLoginPersistenceStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = WorkBuddyLoginPersistenceRecord(
            accountMode: .enterprise,
            privacyConfirmedAt: now,
            officialInstallConfirmedAt: now,
            officialInstallIdentity: "install-a",
            flowStartedAt: now,
            userCompletedAt: now,
            safeResult: .unsupportedLocalCreditsSource,
            installState: .installedNeedsConfirmation,
            warningDismissed: true
        )
        store.save(record)
        #expect(store.load() == record)

        let encoded = try #require(defaults.data(
            forKey: WorkBuddyLoginPersistenceStore.key
        ))
        let text = String(decoding: encoded, as: UTF8.self)
        for forbidden in [
            "credential", "cookie", "token", "accountIdentity", "authState",
            "qrCode", "rawLog", "/Applications/WorkBuddy.app"
        ] {
            #expect(!text.contains(forbidden))
        }

        let future = WorkBuddyLoginPersistenceRecord(
            schemaVersion:
                WorkBuddyLoginPersistenceRecord.currentSchemaVersion + 1
        )
        let encoder = JSONEncoder()
        defaults.set(
            try encoder.encode(future),
            forKey: WorkBuddyLoginPersistenceStore.key
        )
        #expect(store.load() == nil)

        defaults.set(
            Data(repeating: 0x41, count:
                WorkBuddyLoginPersistenceStore.maximumRecordBytes + 1),
            forKey: WorkBuddyLoginPersistenceStore.key
        )
        #expect(store.load() == nil)
    }

    @Test
    func localizedGuidanceNeverRequestsSecretsAndStatesUnsupportedResult() {
        for language in AppLanguage.allCases {
            let copy = (
                [language.workBuddyLoginPrivacySummary]
                    + language.workBuddyLoginSteps(.personal)
                    + language.workBuddyLoginSteps(.enterprise)
                    + [language.workBuddySafeCompletionResult]
            ).joined(separator: " ")
            #expect(copy.contains("UMA"))
            #expect(
                copy.contains("Credits")
                    || copy.contains("Credits")
            )
            for forbidden in [
                "paste your password", "paste token", "send QR",
                "粘贴密码", "粘贴令牌", "发送二维码"
            ] {
                #expect(!copy.localizedCaseInsensitiveContains(forbidden))
            }
        }
        #expect(
            AppLanguage.english.workBuddyOfficialInstallWarning
                == "macOS could not verify this WorkBuddy installation. Continue only if you installed it from the official WorkBuddy source."
        )
    }

    @Test
    func productBoundaryAndSettingsControlsRemainNarrow() throws {
        let root = repositoryRoot()
        let manualConnector = try text(
            root,
            "Sources/CodexUsageUI/Connectors/WorkBuddyAvailabilityConnector.swift"
        )
        #expect(manualConnector.contains("localSourceClass: .manualOnly"))
        #expect(manualConnector.contains(".hiddenFromProviderSurfaces"))
        #expect(manualConnector.contains(".hiddenFromDesktopAssistant"))

        let runtime = try text(
            root,
            "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
        )
        #expect(!runtime.contains("WorkBuddyLocalLiveConnector"))

        let settings = try text(
            root,
            "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
        )
        let workBuddyStart = try #require(
            settings.range(of: "private struct WorkBuddyLoginAssistanceSection")
        )
        let workBuddyEnd = settings[workBuddyStart.upperBound...].range(
            of: "private struct"
        )?.lowerBound ?? settings.endIndex
        let workBuddySettings = String(
            settings[workBuddyStart.lowerBound..<workBuddyEnd]
        )
        for required in [
            "workBuddyLoginForDataSync",
            "workBuddyOpenApplication",
            "checkAgain()",
            "workBuddyCancelLogin",
            "workBuddyOpenOfficialLoginInstructions"
        ] {
            #expect(workBuddySettings.contains(required))
        }
        for forbidden in [
            "WKWebView", "AXUIElement", "CGWindowListCreateImage",
            "Keychain", "URLSession", "OCR"
        ] {
            #expect(!workBuddySettings.contains(forbidden))
        }
    }

    @Test
    func packageHelperIsCommitExactAndFixtureFree() throws {
        let script = try text(
            repositoryRoot(),
            "script/package_uma_workbuddy_login.sh"
        )
        for required in [
            "MARKETING_VERSION=\"0.10.1\"",
            "DEFAULT_BUILD=\"202607250005\"",
            "BUNDLE_ID=\"com.kevinchen.CodexUsageMonitor\"",
            "/private/tmp/uma-workbuddy-login-final-$short_commit/UMA.app",
            "git -C \"$REPO_ROOT\" archive",
            "UMA-WorkBuddy-Login-Provenance.plist",
            "codesign --verify --deep --strict"
        ] {
            #expect(script.contains(required))
        }
        for forbidden in [
            "workbuddy-manual-availability.json",
            "connector-snapshots.json",
            "PreviewRendererTool",
            "Tests/",
            "source/",
            "Desktop/",
            "xattr -cr"
        ] {
            #expect(!script.contains(forbidden))
        }
    }

    private func candidate(
        _ url: URL,
        id: String? = "com.workbuddy.workbuddy",
        trust: WorkBuddySignatureTrust
    ) -> WorkBuddyApplicationCandidate {
        WorkBuddyApplicationCandidate(
            url: url,
            bundleIdentifier: id,
            displayName: "WorkBuddy",
            version: "5.3.5",
            build: "5.3.5",
            signatureTrust: trust,
            installationIdentity: "test:\(url.path)"
        )
    }

    private func application(
        trust: WorkBuddySignatureTrust,
        identity: String = "install-a"
    ) -> WorkBuddyInstalledApplication {
        WorkBuddyInstalledApplication(
            url: URL(fileURLWithPath: "/Applications/WorkBuddy.app"),
            bundleIdentifier: "com.workbuddy.workbuddy",
            displayName: "WorkBuddy",
            version: "5.3.5",
            build: "5.3.5",
            signatureTrust: trust,
            installationIdentity: identity
        )
    }

    private func settle(milliseconds: Int = 15) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}

@MainActor
private final class FakeWorkBuddyApplicationAccess:
    WorkBuddyApplicationAccessing {
    var status: WorkBuddyInstallationStatus
    var launchResult: WorkBuddyApplicationLaunchResult
    private(set) var openCount = 0
    private(set) var observerCount = 0
    private var action: (@MainActor () -> Void)?

    init(
        status: WorkBuddyInstallationStatus,
        launchResult: WorkBuddyApplicationLaunchResult = .launched
    ) {
        self.status = status
        self.launchResult = launchResult
    }

    func discover() -> WorkBuddyInstallationStatus { status }

    func openOrActivate(
        _ application: WorkBuddyInstalledApplication
    ) async -> WorkBuddyApplicationLaunchResult {
        openCount += 1
        return launchResult
    }

    func observeLifecycle(
        _ action: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        self.action = action
        observerCount += 1
        return NSObject()
    }

    func removeLifecycleObserver(_ observer: NSObjectProtocol) {
        action = nil
        observerCount -= 1
    }

    func postLifecycle() {
        action?()
    }
}

@MainActor
private final class InMemoryWorkBuddyLoginPersistence:
    WorkBuddyLoginPersistenceStoring {
    var record: WorkBuddyLoginPersistenceRecord?

    func load() -> WorkBuddyLoginPersistenceRecord? { record }
    func save(_ record: WorkBuddyLoginPersistenceRecord) {
        self.record = record
    }
}

private actor CountingWorkBuddyLoginChecker:
    WorkBuddyLoginEligibilityChecking {
    private(set) var count = 0
    let delay: Duration

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    func check() async -> WorkBuddyLoginSafeResult {
        count += 1
        try? await Task.sleep(for: delay)
        return .unsupportedLocalCreditsSource
    }
}
