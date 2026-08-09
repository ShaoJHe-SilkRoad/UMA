import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M6-G2 Antigravity Settings and main-panel contract")
struct M6G2AntigravitySettingsMainPanelTests {
    @MainActor
    @Test
    func injectedOperationsDriveStatesWithoutCredentialInputs() async {
        let probe = AntigravitySettingsProbe()
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AntigravitySettingsModel(
            checkAgain: {
                await probe.recordCheck()
                return AntigravitySettingsObservation(state: .loginRequired)
            },
            syncNow: {
                await probe.recordSync()
                return AntigravitySettingsObservation(state: .fresh(capturedAt))
            },
            disable: {
                await probe.recordDisable()
            },
            setAutoRefresh: { enabled in
                await probe.recordAutoRefresh(enabled)
            },
            openOfficialSetup: {
                await probe.recordOpen()
                return AntigravitySettingsObservation(state: .notInstalled)
            },
            openProvider: {
                await probe.recordOpen()
                return AntigravitySettingsObservation(state: .loginRequired)
            }
        )

        model.checkAntigravity()
        await waitUntil { !model.actionInProgress }
        #expect(model.state == .loginRequired)
        #expect(await probe.checkCount == 1)

        model.openOfficialSetup()
        await waitUntil { !model.actionInProgress }
        #expect(model.state == .notInstalled)

        model.openProvider()
        await waitUntil { !model.actionInProgress }
        #expect(model.state == .loginRequired)
        #expect(await probe.openCount == 2)

        model.syncNow()
        model.syncNow()
        await waitUntil { !model.actionInProgress }
        #expect(model.state == .fresh(capturedAt))
        #expect(await probe.syncCount == 1)

        model.setAutoRefreshEnabled(false)
        await waitUntil { !model.actionInProgress }
        #expect(!model.autoRefreshEnabled)
        #expect(await probe.autoRefreshValues == [false])

        model.disable()
        await waitUntil { !model.actionInProgress }
        #expect(model.state == .disabled)
        #expect(await probe.disableCount == 1)
        #expect(await probe.autoRefreshValues == [false, false])
    }

    @MainActor
    @Test
    func safeFailuresExposeOnlyBoundedClassification() async {
        let model = AntigravitySettingsModel(
            operations: AntigravitySettingsOperations(
                check: {
                    AntigravitySettingsObservation(
                        state: .notInstalled,
                        safeError: .executableMissing
                    )
                },
                openOfficialSetup: {
                    AntigravitySettingsObservation(
                        state: .failed,
                        safeError: .unsupportedVersion
                    )
                },
                openProvider: {
                    AntigravitySettingsObservation(state: .loginRequired)
                },
                syncNow: {
                    AntigravitySettingsObservation(
                        state: .failed,
                        safeError: .unsupportedSchema
                    )
                },
                setAutoRefresh: { _ in },
                disable: {}
            )
        )

        model.checkAntigravity()
        await waitUntil { !model.actionInProgress }
        #expect(model.safeError == .executableMissing)

        model.openOfficialSetup()
        await waitUntil { !model.actionInProgress }
        #expect(model.safeError == .unsupportedVersion)

        model.syncNow()
        await waitUntil { !model.actionInProgress }
        #expect(model.safeError == .unsupportedSchema)
    }

    @MainActor
    @Test
    func sourceObservationsKeepIdleSettingsFresh() {
        let observedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AntigravitySettingsModel()
        model.receive(AntigravitySettingsObservation(state: .fresh(observedAt)))
        #expect(model.state == .fresh(observedAt))
        #expect(model.safeError == nil)

        model.receive(AntigravitySettingsObservation(
            state: .stale(observedAt),
            safeError: .timedOut
        ))
        #expect(model.state == .stale(observedAt))
        #expect(model.safeError == .timedOut)
    }

    @MainActor
    @Test
    func productionObservationMapsMissingExecutableToInstallState() {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = AgentUsageSnapshot(
            id: GoogleAntigravityUsageConnector.connectorID,
            providerName: "Google Antigravity",
            state: .unsupported,
            capturedAt: capturedAt,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: [],
            safeFailure: .unavailable
        )

        let observation = UsageMonitorRuntime.antigravityObservation(snapshot)
        #expect(observation.state == .notInstalled)
        #expect(observation.safeError == .executableMissing)
    }

    @Test
    func englishAndSimplifiedChineseCoverEveryRequiredStateAndAction() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let states: [AntigravitySettingsPresentationState] = [
            .disabled, .checking, .notInstalled, .openingOfficialSetup,
            .loginRequired, .connected(date), .refreshing(date), .fresh(date),
            .cached(date), .stale(date), .failed,
        ]
        let actions: [AntigravitySettingsAction] = [
            .checking, .openingOfficialSetup, .openingProvider, .refreshing,
            .changingAutoRefresh, .disabling,
        ]

        for state in states {
            let english = AppLanguage.english.antigravityState(state)
            let chinese = AppLanguage.simplifiedChinese.antigravityState(state)
            #expect(!english.isEmpty)
            #expect(!chinese.isEmpty)
            #expect(english != chinese)
        }
        for action in actions {
            #expect(!AppLanguage.english.antigravityAction(action).isEmpty)
            #expect(!AppLanguage.simplifiedChinese.antigravityAction(action).isEmpty)
        }

        #expect(AppLanguage.english.antigravityCheck == "Check Antigravity")
        #expect(AppLanguage.english.antigravitySyncNow == "Sync Now")
        #expect(AppLanguage.english.antigravityAutoRefresh == "Auto Refresh")
        #expect(AppLanguage.simplifiedChinese.antigravityDisable == "停用")
    }

    @Test
    func sourceTransparencyIsReadOnlyAndCredentialFree() {
        let transparency = AntigravitySourceTransparency()
        #expect(transparency.source.contains("read-only /usage"))
        #expect(transparency.authentication.contains("Provider-managed"))
        #expect(transparency.executable == "$HOME/.local/bin/agy")
        #expect(!transparency.credentialsAccessed)
        #expect(!transparency.browserDataAccessed)
        #expect(!transparency.rawProviderPayloadStored)
        #expect(!transparency.providerWorkSubmitted)

        let english = AppLanguage.english.antigravityPrivacySummary
        let chinese = AppLanguage.simplifiedChinese.antigravityPrivacySummary
        for forbidden in ["API key", "OAuth token", "Keychain read"] {
            #expect(!english.contains(forbidden))
            #expect(!chinese.contains(forbidden))
        }
    }

    @Test
    func assignedSourcesContainNoProviderCredentialOrBrowserMechanism() throws {
        let model = try source(
            "Sources/CodexUsageUI/Stores/AntigravitySettingsModel.swift"
        )
        for forbidden in [
            "Security.framework", "SecItemCopyMatching", "WKWebView",
            "ASWebAuthenticationSession", "Cookie", "Authorization: Bearer",
            "ANTHROPIC_API_KEY",
        ] {
            #expect(!model.contains(forbidden))
        }
        #expect(model.contains("AntigravitySettingsOperations"))
        #expect(model.contains("@MainActor @Sendable"))
        #expect(!model.contains("Process("))
        #expect(!model.contains("FileManager"))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if predicate() { return }
            await Task.yield()
        }
    }
}

private actor AntigravitySettingsProbe {
    private(set) var checkCount = 0
    private(set) var openCount = 0
    private(set) var syncCount = 0
    private(set) var autoRefreshValues: [Bool] = []
    private(set) var disableCount = 0

    func recordCheck() { checkCount += 1 }
    func recordOpen() { openCount += 1 }
    func recordSync() { syncCount += 1 }
    func recordAutoRefresh(_ enabled: Bool) { autoRefreshValues.append(enabled) }
    func recordDisable() { disableCount += 1 }
}
