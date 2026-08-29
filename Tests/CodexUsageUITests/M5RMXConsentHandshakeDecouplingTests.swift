import Foundation
import Testing
import ClaudeBrowserBridgeProtocol
import ClaudeSafariHostIPC
@testable import CodexUsageUI

@Suite("M5RMX content-free Companion qualification")
struct M5RMXConsentHandshakeDecouplingTests {
    @Test
    func noConsentQualificationStartsListenerCreatesRequestAndTouchesNoProvider() async {
        let recorder = QualificationRecorder(verification: .verified)
        let result = await ClaudeBrowserCompanionMachineVerifier.run(
            using: integration(recorder)
        )

        #expect(result == .verified)
        #expect(await recorder.events == [.listenerStarted, .requestCreated, .listenerStopped])
        #expect(await recorder.providerAccessCount == 0)
    }

    @Test(arguments: [
        ClaudeBrowserCompanionVerification.verified,
        .disabled,
        .companionStarting,
        .protocolMismatch,
        .unavailable,
    ])
    func everyQualificationResultStopsTheContentFreeListener(
        _ verification: ClaudeBrowserCompanionVerification
    ) async {
        let recorder = QualificationRecorder(verification: verification)

        let result = await ClaudeBrowserCompanionMachineVerifier.run(
            using: integration(recorder)
        )

        #expect(result == verification)
        #expect(await recorder.events == [.listenerStarted, .requestCreated, .listenerStopped])
        #expect(await recorder.providerAccessCount == 0)
    }

    @Test(arguments: [ConsentCondition.notGranted, .granted, .revoked])
    fileprivate func qualificationIsIdenticalAcrossConsentStates(
        _ consent: ConsentCondition
    ) async {
        let recorder = QualificationRecorder(verification: .verified)
        await recorder.recordConsent(consent)

        let result = await ClaudeBrowserCompanionMachineVerifier.run(
            using: integration(recorder)
        )

        #expect(result == .verified)
        #expect(await recorder.events == [
            .consentObserved(consent), .listenerStarted, .requestCreated, .listenerStopped,
        ])
        #expect(await recorder.providerAccessCount == 0)
    }

    @Test
    func noConsentAccuracySyncIsConsentRequiredAndPerformsNoProviderAccess() async {
        let fixture = BrowserConnectorFixture(consent: false)
        let connector = browserConnector(fixture)

        await connector.accuracySync()

        #expect((await connector.diagnostics()).browserAccuracyState == .consentRequired)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
    }

    @Test
    func grantedConsentAllowsExistingAccuracyPathWithoutChangingQualification() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = browserConnector(fixture)

        await connector.accuracySync()

        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.automaticRequests.count == 1)
    }

    @MainActor
    @Test
    func productionAndTestPreferenceDomainsRemainIsolatedWithoutConsentCopy() {
        let productionName = "M5RMXConsentProduction-\(UUID().uuidString)"
        let testName = "M5RMXConsentTest-\(UUID().uuidString)"
        let productionDefaults = UserDefaults(suiteName: productionName)!
        let testDefaults = UserDefaults(suiteName: testName)!
        defer {
            productionDefaults.removePersistentDomain(forName: productionName)
            testDefaults.removePersistentDomain(forName: testName)
        }
        let production = ClaudeBrowserConsentStore(defaults: productionDefaults)
        let test = ClaudeBrowserConsentStore(defaults: testDefaults)

        production.consentGranted = true

        #expect(production.consentGranted)
        #expect(!test.consentGranted)
        #expect(testDefaults.dictionaryRepresentation().keys.allSatisfy {
            !$0.contains("ClaudeLocalSmartModeConsent")
        })
    }

    @Test
    func verifierEntrypointBypassesFullUsageRuntimeAndConsentConstruction() throws {
        let app = try source("Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift")
        let integration = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
        )

        let verifierBranch = try #require(app.range(
            of: "if CommandLine.arguments.contains("
        ))
        let runtimeConstruction = try #require(app.range(of: "let delegate = AppDelegate()"))
        let verifierBody = app[verifierBranch.lowerBound..<runtimeConstruction.lowerBound]
        #expect(verifierBranch.lowerBound < runtimeConstruction.lowerBound)
        #expect(verifierBody.contains("ClaudeBrowserCompanionMachineVerifier.run("))
        #expect(verifierBody.contains("allowSafariLaunch: allowSafariLaunch"))
        #expect(verifierBody.contains("recognizesLaunchArgument"))
        #expect(verifierBody.contains("application.terminate(nil)"))
        #expect(verifierBody.contains("application.run()"))
        #expect(verifierBody.contains("return"))
        #expect(integration.contains("It deliberately constructs no Claude connector or consent store"))
        #expect(!integration.contains("verifyHandshakeOnListenerStart"))
    }

    @Test
    func verifierEntrypointRecognizesBothContentFreeMachineModes() {
        #expect(ClaudeBrowserCompanionMachineVerifier.recognizesLaunchArgument(
            ClaudeBrowserCompanionMachineVerifier.launchArgument
        ))
        #expect(ClaudeBrowserCompanionMachineVerifier.recognizesLaunchArgument(
            ClaudeBrowserCompanionMachineVerifier.diagnosticLaunchArgument
        ))
        #expect(!ClaudeBrowserCompanionMachineVerifier.recognizesLaunchArgument(
            "--accuracy-sync"
        ))
    }

    @Test
    func diagnosticReportsMutableClientSeparatelyFromImmutableHost() throws {
        let integration = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
        )

        #expect(integration.contains(
            "clientApplicationIdentifier = context.map { _ in\n"
                + "            ClaudeBrowserBridgeContract.safariTestApplicationIdentifier"
        ))
        #expect(integration.contains(
            "hostApplicationIdentifier = trace.runtimeDescriptor?.hostApplicationIdentifier"
        ))
        #expect(
            ClaudeBrowserBridgeContract.safariTestApplicationIdentifier
                != ClaudeSafariHostIPCContract.hostApplicationIdentifier
        )
    }

    @Test(arguments: [
        (ClaudeBrowserCompanionVerification.verified, "verified", Int32(0)),
        (.disabled, "disabled", Int32(2)),
        (.companionStarting, "starting", Int32(3)),
        (.protocolMismatch, "protocolMismatch", Int32(4)),
        (.unavailable, "unavailable", Int32(5)),
    ])
    func diagnosticResultIsMachineReadableAndContentFree(
        _ fixture: (ClaudeBrowserCompanionVerification, String, Int32)
    ) throws {
        let result = ClaudeBrowserCompanionDiagnosticResult(
            verification: fixture.0
        )
        let data = try result.encodedJSONLine()
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(object.keys) == [
            "schemaVersion", "status", "occurredAt", "reachedStages",
        ])
        #expect(object["schemaVersion"] as? Int == 2)
        #expect(object["status"] as? String == fixture.1)
        #expect(object["reachedStages"] as? [String] == [])
        #expect(ISO8601DateFormatter().date(
            from: try #require(object["occurredAt"] as? String)
        ) != nil)
        #expect(result.processExitCode == fixture.2)
        for forbidden in [
            "provider", "url", "dom", "html", "quota", "account", "identity",
            "cookie", "token", "credential", "payload",
        ] {
            #expect(object[forbidden] == nil)
        }
    }

    @Test
    func detailedDiagnosticReportsOnlyCausalHostStagesAndRuntimeMetadata() throws {
        let generation = "60a06652-5f18-417d-849c-7533a9e28bb3"
        let result = ClaudeBrowserCompanionDiagnosticResult(
            trace: .init(
                verification: .verified,
                requestID: "ae60802e-2d87-4dd3-a2eb-c182c13f980a",
                runtimeGenerationID: generation,
                occurredAt: "2026-08-28T12:00:00Z",
                reachedStages: [
                    .listenerReady, .requestCreated, .requestSubmitted,
                    .hostRequestAccepted, .wakeDispatchAccepted,
                    .extensionBackgroundAlive, .nativePortOpenRequested,
                    .nativePortOpened, .extensionBackgroundAcknowledged,
                    .nativeQualificationDispatched,
                    .nativeHandlerEntered, .nativeRequestDecoded,
                    .runtimeGenerationValidated, .nativeResponseCreated,
                    .nativeResponseSent, .extensionResponseReceived,
                    .nativeQualificationReceived, .companionVerified,
                    .containingAppCallbackReceived, .callbackValidated,
                ],
                firstFailureReason: nil,
                runtimeDescriptor: .init(
                    hostApplicationIdentifier:
                        ClaudeSafariHostIPCContract.hostApplicationIdentifier,
                    extensionIdentifier: ClaudeSafariHostIPCContract.hostExtensionIdentifier,
                    teamIdentifier: ClaudeBrowserBridgeContract.expectedTeamIdentifier,
                    hostVersion: "0.13.0",
                    hostBuild: "202608280001",
                    runtimeGenerationID: generation,
                    bridgeProtocolVersion: ClaudeBrowserBridgeContract.schemaVersion
                )
            ),
            context: nil
        )
        let data = try result.encodedJSONLine()
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["schemaVersion"] as? Int == 2)
        #expect(object["status"] as? String == "verified")
        #expect(object["requestID"] as? String
            == "ae60802e-2d87-4dd3-a2eb-c182c13f980a")
        #expect(object["runtimeGenerationID"] as? String == generation)
        #expect(object["hostRuntimeGenerationID"] as? String == generation)
        #expect(object["hostApplicationIdentifier"] as? String
            == ClaudeSafariHostIPCContract.hostApplicationIdentifier)
        #expect(object["extensionIdentifier"] as? String
            == ClaudeSafariHostIPCContract.hostExtensionIdentifier)
        #expect(object["hostVersion"] as? String == "0.13.0")
        #expect(object["hostBuild"] as? String == "202608280001")
        #expect(object["firstFailureReason"] == nil)
        let stages = try #require(object["reachedStages"] as? [String])
        #expect(stages == [
            "listenerReady", "requestCreated", "requestSubmitted",
            "hostRequestAccepted", "wakeDispatchAccepted",
            "extensionBackgroundAlive", "nativePortOpenRequested",
            "nativePortOpened", "extensionBackgroundAcknowledged",
            "nativeQualificationDispatched", "nativeHandlerEntered",
            "nativeRequestDecoded", "runtimeGenerationValidated",
            "nativeResponseCreated", "nativeResponseSent",
            "extensionResponseReceived", "nativeQualificationReceived",
            "companionVerified", "containingAppCallbackReceived",
            "callbackValidated",
        ])
        for forbidden in [
            "provider", "url", "page", "dom", "html", "quota", "account",
            "identity", "cookie", "token", "credential", "payload",
        ] {
            #expect(object[forbidden] == nil)
        }
    }

    @Test
    func adapterExpandsOnlyCausallyProvenBackgroundAndNativeStages() throws {
        let adapter = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
        )

        for stage in [
            ".extensionBackgroundAlive",
            ".nativePortOpenRequested",
            ".nativePortOpened",
            ".nativeHandlerEntered",
            ".nativeRequestDecoded",
            ".runtimeGenerationValidated",
            ".nativeResponseCreated",
            ".nativeResponseSent",
            ".extensionResponseReceived",
        ] {
            #expect(adapter.contains(stage))
        }
        #expect(adapter.contains("case .extensionBackgroundAcknowledged:"))
        #expect(adapter.contains("case .nativeQualificationReceived:"))
        #expect(adapter.contains("diagnosticStages(through: stage)"))
        #expect(!adapter.contains("Task.sleep(for: .seconds(12))"))
    }

    @Test
    func clientVerificationDeadlineBoundsBothHostPhasesPlusDeliveryMargin() throws {
        let adapter = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
        )
        #expect(adapter.contains("verificationTransactionDeadline: Duration = .seconds(23)"))
        #expect(!adapter.contains("Task.sleep(for: .seconds(12))"))
        #expect(adapter.contains("Self.verificationTransactionDeadline"))
    }

    @Test
    func diagnosticEntrypointWritesJSONAndUsesItsBoundedExitCode() throws {
        let app = try source("Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift")

        #expect(app.contains("ClaudeBrowserCompanionMachineVerifier.runDiagnostic("))
        #expect(app.contains("result.encodedJSONLine()"))
        #expect(app.contains("FileHandle.standardOutput.write(data)"))
        #expect(app.contains("Darwin.exit(result.processExitCode)"))
    }

    @MainActor
    @Test
    func oneShotAccuracyQualificationRequiresExistingConsentAndReadsNothing() async {
        let fixture = BrowserConnectorFixture(consent: false)
        let domain = "M5RMXAccuracyNoConsent-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        let model = ClaudeBrowserSettingsModel(
            connector: browserConnector(fixture),
            consentStore: consent
        )

        let result = await model.runOneShotAccuracySyncDiagnostic(
            maximumTerminalPolls: 0,
            maximumCleanupPolls: 0,
            sleep: {},
            receiptProbe: { true }
        )

        #expect(result.status == .consentRequired)
        #expect(!result.exactAnchorReceived)
        #expect(result.tempTabReceiptAbsent == true)
        #expect(result.processExitCode == 2)
        #expect(await fixture.bridge.startCount == 0)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect(await fixture.bridge.openCount == 0)
    }

    @MainActor
    @Test
    func oneShotAccuracyQualificationUsesOneRealRequestAndReportsExactAnchor() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let domain = "M5RMXAccuracyGranted-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let model = ClaudeBrowserSettingsModel(
            connector: browserConnector(fixture),
            consentStore: consent
        )

        let qualification = Task { @MainActor in
            await model.runOneShotAccuracySyncDiagnostic(
                maximumTerminalPolls: 100,
                maximumCleanupPolls: 0,
                sleep: { await Task.yield() },
                receiptProbe: { true }
            )
        }
        await fixture.bridge.waitForAutomaticRequest()
        #expect(await fixture.bridge.automaticRequests.count == 1)
        await fixture.bridge.send(browserEnvelope(five: 9, seven: 71))

        let result = await qualification.value
        let data = try result.encodedJSONLine()
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(result.status == .exactAnchorReceived)
        #expect(result.exactAnchorReceived)
        #expect(result.tempTabReceiptAbsent == true)
        #expect(result.processExitCode == 0)
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect(await fixture.bridge.openCount == 0)
        #expect(Set(object.keys) == [
            "schemaVersion", "status", "exactAnchorReceived",
            "tempTabReceiptAbsent", "localSmartState",
        ])
        #expect(object["status"] as? String == "exactAnchorReceived")
        #expect(object["exactAnchorReceived"] as? Bool == true)
        #expect(object["tempTabReceiptAbsent"] as? Bool == true)
        for forbidden in [
            "url", "dom", "html", "quota", "value", "reset", "account",
            "identity", "cookie", "token", "credential", "payload",
        ] {
            #expect(object[forbidden] == nil)
        }
    }

    @MainActor
    @Test
    func oneShotAccuracyQualificationTimesOutWithoutRetryingProviderAccess() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let domain = "M5RMXAccuracyTimeout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let model = ClaudeBrowserSettingsModel(
            connector: browserConnector(fixture),
            consentStore: consent
        )

        let result = await model.runOneShotAccuracySyncDiagnostic(
            maximumTerminalPolls: 0,
            maximumCleanupPolls: 0,
            sleep: {},
            receiptProbe: { nil }
        )

        #expect(result.status == .timedOut)
        #expect(!result.exactAnchorReceived)
        #expect(result.tempTabReceiptAbsent == nil)
        #expect(result.processExitCode == 11)
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect(await fixture.bridge.closedRequestIDs.count == 1)
        #expect(await fixture.bridge.openCount == 0)
    }

    @MainActor
    @Test
    func oneShotAccuracyQualificationReportsSafariUnavailableTruthfully() async {
        let fixture = BrowserConnectorFixture(consent: true)
        await fixture.bridge.setAutomaticDispatchResult(.browserUnavailable)
        let domain = "M5RMXAccuracySafariUnavailable-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let model = ClaudeBrowserSettingsModel(
            connector: browserConnector(fixture),
            consentStore: consent
        )

        let result = await model.runOneShotAccuracySyncDiagnostic(
            maximumTerminalPolls: 1,
            maximumCleanupPolls: 0,
            sleep: {},
            receiptProbe: { nil }
        )

        #expect(result.status == .browserUnavailable)
        #expect(!result.exactAnchorReceived)
        #expect(result.processExitCode == 13)
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect(await fixture.bridge.openCount == 0)
    }

    @Test
    func accuracyQualificationEntrypointUsesSafariFreeRuntimeAndMachineJSON() throws {
        let app = try source("Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift")
        let settings = try source(
            "Sources/CodexUsageUI/Stores/ClaudeBrowserSettingsModel.swift"
        )

        let accuracyBranch = try #require(app.range(
            of: "ClaudeAccuracySyncMachineVerifier.launchArgument"
        ))
        let companionBranch = try #require(app.range(
            of: "ClaudeBrowserCompanionMachineVerifier.recognizesLaunchArgument"
        ))
        #expect(accuracyBranch.lowerBound < companionBranch.lowerBound)
        #expect(app.contains("ClaudeAccuracySyncMachineVerifier.runLive("))
        #expect(app.contains("result.encodedJSONLine()"))
        #expect(app.contains("Darwin.exit(result.processExitCode)"))
        #expect(settings.contains("startProviders: false"))
        #expect(settings.contains("await connector.accuracySync()"))
        #expect(!settings.contains("openUsagePage: true"))
        #expect(settings.contains("func verifyCompanion()"))
        #expect(settings.contains("run(.checkingCompanion)"))
    }

    @Test
    func settingsCopySeparatesCompanionRuntimeFromAccuracyAndLocalSmart() {
        #expect(AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .ready,
            accuracyState: .ready
        ) == "Companion ready.")
        #expect(AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .starting,
            accuracyState: .companionUnavailable
        ) == "Companion starting.")
        #expect(AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .starting,
            accuracyState: .companionUnavailable
        ) == "Companion starting.")
        #expect(AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .updatePendingSafariRestart,
            accuracyState: .updatePendingRestart
        ) == "Companion update pending Safari restart.")
        #expect(AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .unavailable,
            accuracyState: .companionUnavailable
        ) == "Native bridge unavailable.")
        #expect(AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .protocolMismatch,
            accuracyState: .error
        ) == "Companion protocol mismatch.")
        #expect(AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .ready,
            accuracyState: .consentRequired
        ) == "Companion ready · Claude consent required.")
        #expect(AppLanguage.english.claudeBrowserAccuracyStatus(
            .ready,
            stage: nil
        ) == "Accuracy Sync is ready.")

        let localState = AppLanguage.english.claudeLocalSmartStatus(
            .estimated(Date(timeIntervalSince1970: 1_700_000_000)),
            stage: .desktopActivitySignalUnavailable
        )
        let browserFailure = AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .unavailable,
            accuracyState: .companionUnavailable
        )
        #expect(localState.contains("≈ Local estimate available"))
        #expect(browserFailure == "Native bridge unavailable.")
    }

    @Test(arguments: [
        ClaudeSafariExtensionAdvisoryState.enabled,
        .disabled,
        .unknown,
        .stateError,
    ])
    func safariInventoryStateNeverBlocksTheRealContentFreeHandshake(
        _ state: ClaudeSafariExtensionAdvisoryState
    ) {
        #expect(state.permitsDirectHandshake)
    }

    @Test
    func mutableAppCannotRejectFromSafariInventoryBeforeHostRequest() throws {
        let integration = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
        )
        let adapter = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
        )

        #expect(integration.contains("ClaudeSafariHostClientAdapter"))
        #expect(adapter.contains("operation: .verifyCompanion"))
        #expect(!integration.contains("SafariServices"))
        #expect(!integration.contains("safariExtensionAdvisoryState"))
        #expect(!integration.contains("preflightRejected(extensionDisabled)"))
    }

    private func integration(
        _ recorder: QualificationRecorder
    ) -> ClaudeBrowserProductionIntegration {
        ClaudeBrowserProductionIntegration(
            startListening: { _ in await recorder.record(.listenerStarted) },
            stopListening: { await recorder.record(.listenerStopped) },
            checkHealth: { .ready },
            openUsagePage: {
                await recorder.recordProviderAccess()
                return true
            },
            repairCompanion: { .ready },
            verifyHandshake: {
                await recorder.record(.requestCreated)
                return recorder.verification
            }
        )
    }

    private func browserConnector(
        _ fixture: BrowserConnectorFixture
    ) -> ClaudeCodeUsageConnector {
        let bridge = fixture.bridge
        let consent = fixture.consent
        let cache = fixture.cache
        return ClaudeCodeUsageConnector(
            integration: ClaudeBrowserProductionIntegration(
                startListening: { handler in await bridge.start(handler) },
                stopListening: { await bridge.stop() },
                checkHealth: { await bridge.currentHealth() },
                openUsagePage: { await bridge.open() },
                repairCompanion: { await bridge.repair() },
                verifyHandshake: { await bridge.verifyHandshake() },
                requestAutomaticRefresh: { requestID, allowLaunch in
                    await bridge.requestAutomaticRefresh(
                        requestID: requestID,
                        allowSafariLaunch: allowLaunch
                    )
                },
                closeOwnedUsageTab: { requestID in
                    await bridge.closeOwnedTab(requestID: requestID)
                }
            ),
            hasConsent: { await consent.get() },
            clearConsent: { await consent.set(false) },
            readCache: { await cache.read() },
            writeCache: { data in await cache.write(data) },
            clearCache: { await cache.clear() },
            now: fixture.clock.now,
            autoRefreshEnabled: { false },
            allowSafariLaunch: { false },
            anchorStore: BrowserTestAnchorStore()
        )
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

private enum ConsentCondition: Sendable {
    case notGranted
    case granted
    case revoked
}

private enum QualificationEvent: Equatable, Sendable {
    case consentObserved(ConsentCondition)
    case listenerStarted
    case requestCreated
    case listenerStopped
}

private actor QualificationRecorder {
    private(set) var events: [QualificationEvent] = []
    private(set) var providerAccessCount = 0
    let verification: ClaudeBrowserCompanionVerification

    init(verification: ClaudeBrowserCompanionVerification) {
        self.verification = verification
    }

    func record(_ event: QualificationEvent) {
        events.append(event)
    }

    func recordConsent(_ consent: ConsentCondition) {
        events.append(.consentObserved(consent))
    }

    func recordProviderAccess() {
        providerAccessCount += 1
    }
}
