import ClaudeStatusLineCore
import ClaudeBrowserBridgeProtocol
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5RMX Claude Local Smart Mode")
struct M5RMXClaudeSmartModeTests {
    @Test
    func statusLineProjectionDropsEveryBroadSessionField() throws {
        let observedAt = Date(timeIntervalSince1970: 1_898_596_800)
        let raw = Data(#"{"version":"2.1.0","session_id":"private-session","cwd":"/private/project","model":{"display_name":"private-model"},"workspace":{"project_dir":"/private/project"},"cost":{"total_cost_usd":99},"transcript_path":"/private/transcript","rate_limits":{"five_hour":{"used_percentage":28,"resets_at":1898600400},"seven_day":{"used_percentage":41.5,"resets_at":1899198000}}}"#.utf8)

        let packet = try ClaudeStatusLineProjection.decode(raw, observedAt: observedAt)
        #expect(packet.claudeVersion == "2.1.0")
        #expect(packet.fiveHour?.usedPercentage == 28)
        #expect(packet.sevenDay?.usedPercentage == 41.5)

        let encoded = try packet.encoded()
        let text = String(decoding: encoded, as: UTF8.self)
        for forbidden in [
            "session_id", "cwd", "workspace", "cost", "transcript",
            "private-session", "private-project", "private-model",
        ] {
            #expect(!text.contains(forbidden))
        }
        #expect(try ClaudeStatusLinePacket.decodePacket(encoded) == packet)
    }

    @Test
    func statusLineProjectionIsStrictAndBounded() {
        #expect(throws: ClaudeStatusLineProtocolError.invalidPercentage) {
            try ClaudeStatusLineProjection.decode(Data(#"{"rate_limits":{"five_hour":{"used_percentage":101,"resets_at":1898600400}}}"#.utf8))
        }
        #expect(throws: ClaudeStatusLineProtocolError.malformedWindow) {
            try ClaudeStatusLineProjection.decode(Data(#"{"rate_limits":{"five_hour":{"used_percentage":"28","resets_at":1898600400}}}"#.utf8))
        }
        #expect(throws: ClaudeStatusLineProtocolError.inputTooLarge) {
            try ClaudeStatusLineProjection.decode(
                Data(repeating: 0x20, count: ClaudeStatusLineProjection.maximumInputBytes + 1)
            )
        }
    }

    @Test
    func sanitizedStateStoreUsesOwnerOnlyPermissions() throws {
        let root = temporaryDirectory("state")
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("state/status-line.json")
        let store = ClaudeStatusLineStateStore(stateURL: stateURL)
        let packet = try smartPacket(observedAt: Date(timeIntervalSince1970: 1_898_596_800))

        try store.write(packet)
        #expect(try store.read() == packet)
        let fileMode = try FileManager.default.attributesOfItem(
            atPath: stateURL.path
        )[.posixPermissions] as? NSNumber
        let directoryMode = try FileManager.default.attributesOfItem(
            atPath: stateURL.deletingLastPathComponent().path
        )[.posixPermissions] as? NSNumber
        #expect(fileMode?.intValue == 0o600)
        #expect(directoryMode?.intValue == 0o700)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: stateURL.path
        )
        #expect(throws: ClaudeStatusLineStateError.invalidPermissions) {
            try store.read()
        }
        #expect(throws: ClaudeStatusLineStateError.invalidPermissions) {
            try store.clear()
        }
        #expect(FileManager.default.fileExists(atPath: stateURL.path))
    }

    @Test
    func configurationPersistsOnlyPriorStatusLineAndRestoresInPlace() throws {
        let fixture = try ConfigurationFixture(existingSettings: #"{"theme":"dark","statusLine":{"type":"command","command":"prior-status --compact","padding":2}}"#)
        defer { fixture.cleanup() }

        try fixture.manager.enable()
        #expect(fixture.manager.check().state == .installed)
        #expect(fixture.manager.check().priorStatusLinePresent)
        #expect(try fixture.manager.priorCommandFromBackup() == "prior-status --compact")
        let installed = try fixture.settingsObject()
        let installedStatus = try #require(installed["statusLine"] as? [String: Any])
        #expect(installedStatus["command"] as? String == fixture.relayCommand)
        #expect(installedStatus["padding"] as? Int == 2)
        let backupText = try String(contentsOf: fixture.paths.backupURL, encoding: .utf8)
        #expect(backupText.contains("prior-status --compact"))
        #expect(backupText.contains("padding"))
        #expect(!backupText.contains("theme"))

        try fixture.manager.restore()
        let restored = try fixture.settingsObject()
        #expect(restored["theme"] as? String == "dark")
        #expect((restored["statusLine"] as? [String: Any])?["command"] as? String
            == "prior-status --compact")
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.metadataURL.path))
    }

    @Test
    func statusLineIntegrationPreservesPriorHooksWithoutAddingMonitoringHook() throws {
        let original = #"{"theme":"dark","hooks":{"PreToolUse":[{"matcher":"Read","hooks":[{"type":"command","command":"prior-read"}]}],"Stop":[{"matcher":"legacy","hooks":[{"type":"command","command":"prior-stop"}]}]}}"#
        let fixture = try ConfigurationFixture(existingSettings: original)
        defer { fixture.cleanup() }
        let priorHooks = try #require(fixture.settingsObject()["hooks"])
        let priorHooksData = try JSONSerialization.data(
            withJSONObject: priorHooks,
            options: [.sortedKeys]
        )

        try fixture.manager.enable()
        try fixture.manager.repair()
        try fixture.manager.repair()
        #expect(fixture.manager.check().state == .installed)
        let installedHooks = try #require(fixture.settingsObject()["hooks"])
        #expect(try JSONSerialization.data(
            withJSONObject: installedHooks,
            options: [.sortedKeys]
        ) == priorHooksData)
        let settingsText = String(
            decoding: try Data(contentsOf: fixture.paths.settingsURL),
            as: UTF8.self
        )
        #expect(!settingsText.contains("ClaudeStatusLineRelay --receipt-only"))

        try fixture.manager.restore()
        let restoredHooks = try #require(fixture.settingsObject()["hooks"])
        #expect(try JSONSerialization.data(
            withJSONObject: restoredHooks,
            options: [.sortedKeys]
        ) == priorHooksData)
    }

    @Test
    func unrelatedHumanHookEditsRemainUntouchedDuringRepairAndRestore() throws {
        let fixture = try ConfigurationFixture(existingSettings: #"{"hooks":{"Stop":[{"matcher":"legacy","hooks":[{"type":"command","command":"prior-stop"}]}]}}"#)
        defer { fixture.cleanup() }
        try fixture.manager.enable()

        var drifted = try fixture.settingsObject()
        var hooks = try #require(drifted["hooks"] as? [String: Any])
        var stop = try #require(hooks["Stop"] as? [Any])
        stop.append(["matcher": "external", "hooks": [["type": "command", "command": "human-new"]]])
        hooks["Stop"] = stop
        drifted["hooks"] = hooks
        try fixture.writeSettings(drifted)

        #expect(fixture.manager.check().state == .repairRequired)
        try fixture.manager.repair()
        #expect(fixture.manager.check().state == .installed)
        try fixture.manager.restore()
        let retainedText = String(decoding: try Data(contentsOf: fixture.paths.settingsURL), as: UTF8.self)
        #expect(retainedText.contains("human-new"))
        #expect(retainedText.contains("prior-stop"))
        #expect(!retainedText.contains("--receipt-only"))
    }

    @Test
    func hookDisablingPoliciesFailClosedBeforeAnyConfigurationWrite() throws {
        for key in ["disableAllHooks", "allowManagedHooksOnly"] {
            let fixture = try ConfigurationFixture(existingSettings: "{\"\(key)\":true,\"theme\":\"dark\"}")
            defer { fixture.cleanup() }
            #expect(throws: ClaudeStatusLineConfigurationError.unsupportedSettings) {
                try fixture.manager.enable()
            }
            #expect(try Data(contentsOf: fixture.paths.settingsURL) == fixture.originalData)
            #expect(!FileManager.default.fileExists(atPath: fixture.paths.metadataURL.path))
        }
    }

    @Test
    func externalSettingsEditFailsClosedUntilExplicitRepair() throws {
        let fixture = try ConfigurationFixture(existingSettings: #"{"theme":"dark","statusLine":{"type":"command","command":"prior-status"}}"#)
        defer { fixture.cleanup() }
        try fixture.manager.enable()

        var externallyEdited = try fixture.settingsObject()
        externallyEdited["theme"] = "light"
        try fixture.writeSettings(externallyEdited)
        #expect(fixture.manager.check().state == .repairRequired)
        #expect(throws: ClaudeStatusLineConfigurationError.concurrentModification) {
            try fixture.manager.restore()
        }

        try fixture.manager.repair()
        #expect(fixture.manager.check().state == .installed)
        try fixture.manager.restore()
        let restored = try fixture.settingsObject()
        #expect(restored["theme"] as? String == "light")
        #expect((restored["statusLine"] as? [String: Any])?["command"] as? String
            == "prior-status")
    }

    @Test
    func externalStatusLineDriftCannotBeAdoptedByRepairOrRestore() throws {
        let fixture = try ConfigurationFixture(existingSettings: #"{"theme":"dark","statusLine":{"type":"command","command":"prior-status"}}"#)
        defer { fixture.cleanup() }
        try fixture.manager.enable()

        var externallyEdited = try fixture.settingsObject()
        externallyEdited["statusLine"] = ["type": "command", "command": "external-status"]
        try fixture.writeSettings(externallyEdited)
        #expect(fixture.manager.check().state == .repairRequired)
        #expect(throws: ClaudeStatusLineConfigurationError.concurrentModification) {
            try fixture.manager.repair()
        }
        #expect(throws: ClaudeStatusLineConfigurationError.concurrentModification) {
            try fixture.manager.restore()
        }
        let retained = try fixture.settingsObject()
        #expect((retained["statusLine"] as? [String: Any])?["command"] as? String
            == "external-status")
    }

    @Test @MainActor
    func settingsLifecycleNeverDispatchesSafariUntilExplicitAccuracySync() async throws {
        let suite = "M5RMXSettingsNoSafari-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let fixture = BrowserConnectorFixture(consent: true)
        let model = ClaudeBrowserSettingsModel(
            connector: fixture.connector(),
            consentStore: consent
        )

        await Task.yield()
        #expect(await fixture.bridge.automaticRequests.isEmpty)

        model.connectWithConsent()
        for _ in 0..<100 where model.actionInProgress {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await fixture.bridge.automaticRequests.isEmpty)

        model.repairCompanion()
        for _ in 0..<100 where model.actionInProgress {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await fixture.bridge.automaticRequests.isEmpty)

        model.syncNow()
        for _ in 0..<100 where model.actionInProgress {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await fixture.bridge.automaticRequests.isEmpty)

        model.accuracySync()
        for _ in 0..<100 where await fixture.bridge.automaticRequests.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await fixture.bridge.automaticRequests.count == 1)
    }

    @Test @MainActor
    func safariSiteAccessActionsDispatchOneShotAccuracyRequestsWithoutRepair() async throws {
        let suite = "M5RMXSettingsSiteAccess-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let model = ClaudeBrowserSettingsModel(
            connector: connector,
            consentStore: consent
        )

        model.requestSafariSiteAccess()
        for _ in 0..<100 where await fixture.bridge.automaticRequests.count < 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await fixture.bridge.automaticRequests.count == 1)
        let firstRequestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(
            requestID: firstRequestID,
            status: .ownedTabClosed
        )

        while model.actionInProgress {
            try await Task.sleep(for: .milliseconds(10))
        }
        model.retrySafariSiteAccess()
        for _ in 0..<100 where await fixture.bridge.automaticRequests.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await fixture.bridge.automaticRequests.count == 2)
        #expect(!(await connector.diagnostics()).schedulerActive)
    }

    @Test @MainActor
    func settingsDisconnectDoesNotClaimSuccessWhenRestoreFails() async throws {
        let configuration = try ConfigurationFixture(existingSettings: #"{"theme":"dark","statusLine":{"type":"command","command":"prior-status"}}"#)
        defer { configuration.cleanup() }
        try configuration.manager.enable()
        var drifted = try configuration.settingsObject()
        drifted["theme"] = "light"
        try configuration.writeSettings(drifted)

        let suite = "M5RMXClaudeSmartDisconnect-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let connectorFixture = BrowserConnectorFixture(consent: true)
        let model = ClaudeBrowserSettingsModel(
            connector: connectorFixture.connector(),
            consentStore: consent,
            configurationManager: configuration.manager
        )

        model.disconnect()
        for _ in 0..<100 where model.actionInProgress {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.actionInProgress)
        #expect(model.state == .companionOutdated)
        #expect(model.consentGranted)
        #expect(consent.consentGranted)
        #expect(FileManager.default.fileExists(atPath: configuration.paths.metadataURL.path))
    }

    @Test @MainActor
    func installedConfigurationChecksLocalTruthAndDoesNotWaitOnGlobalAdmissionRefresh() async throws {
        let configuration = try ConfigurationFixture(existingSettings: #"{"theme":"dark"}"#)
        defer { configuration.cleanup() }
        try configuration.manager.enable()

        let suite = "M5RMXClaudeSmartInstalledCheck-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let connectorFixture = BrowserConnectorFixture(consent: true)
        let admissionGate = MainActorAdmissionRefreshGate()
        defer { admissionGate.release() }
        let model = ClaudeBrowserSettingsModel(
            connector: connectorFixture.connector(),
            consentStore: consent,
            configurationManager: configuration.manager,
            refreshAdmissions: { await admissionGate.wait() }
        )

        model.checkCompanion()
        for _ in 0..<100 where !admissionGate.entered {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(admissionGate.entered)
        #expect(!model.actionInProgress)
        #expect(model.activeAction == nil)
        #expect(model.state != .checking)
    }

    @Test
    func configurationRestoresExactPreTaskAbsence() throws {
        let root = temporaryDirectory("absent-config")
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsURL = root.appendingPathComponent("home/.claude/settings.json")
        let integration = root.appendingPathComponent("app-support/ClaudeLocalSmartMode")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let paths = ClaudeStatusLineConfigurationPaths(
            settingsURL: settingsURL,
            integrationDirectoryURL: integration,
            backupURL: integration.appendingPathComponent("settings-before-uma.json"),
            metadataURL: integration.appendingPathComponent("restore-metadata.json"),
            stateURL: integration.appendingPathComponent("status-line.json")
        )
        let manager = ClaudeStatusLineConfigurationManager(
            paths: paths,
            relayCommand: "/Applications/UMA.app/Contents/Helpers/ClaudeStatusLineRelay --state safe"
        )

        try manager.enable()
        #expect(manager.check().state == .installed)
        #expect(FileManager.default.fileExists(atPath: settingsURL.path))
        try manager.restore()
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))
        #expect(!FileManager.default.fileExists(atPath: integration.path))
    }

    @Test
    func priorCommandBridgeRunsOnceWithoutCapturingOutputOrEnvironment() throws {
        let root = temporaryDirectory("prior-command")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let marker = root.appendingPathComponent("prior-output")
        let command = "/bin/cat > '\(marker.path)'"
        let input = Data("preserved-input".utf8)

        #expect(try ClaudePriorCommandRunner().run(
            command: command,
            rawInput: input,
            recursionMarkerPresent: false
        ) == .exited(0))
        #expect(try Data(contentsOf: marker) == input)
        try FileManager.default.removeItem(at: marker)
        #expect(try ClaudePriorCommandRunner().run(
            command: command,
            rawInput: input,
            recursionMarkerPresent: true
        ) == .skippedRecursiveInvocation)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test
    func relayExecutableProjectsThenRunsPriorFragmentExactlyOnce() throws {
        let root = temporaryDirectory("relay-integration")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = repositoryRoot()
            .appendingPathComponent(".build/out/Products/Debug/ClaudeStatusLineRelay")
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        let state = root.appendingPathComponent("state/status-line.json")
        let fragment = root.appendingPathComponent("prior-status-line.json")
        try #"{"type":"command","command":"/bin/cat"}"#.write(
            to: fragment, atomically: true, encoding: .utf8
        )
        let raw = Data(#"{"version":"2.1.0","session_id":"synthetic-private","workspace":{"path":"/synthetic/private"},"rate_limits":{"five_hour":{"used_percentage":28,"resets_at":1898600400},"seven_day":{"used_percentage":41,"resets_at":1899198000}}}"#.utf8)

        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "--state", state.path,
            "--prior-status-line", fragment.path,
        ]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(raw)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let visibleOutput = try output.fileHandleForReading.readToEnd() ?? Data()
        #expect(process.terminationStatus == 0)
        #expect(visibleOutput == raw)

        let stored = try ClaudeStatusLineStateStore(stateURL: state).read()
        let packet = try #require(stored)
        #expect(packet.fiveHour?.usedPercentage == 28)
        #expect(packet.sevenDay?.usedPercentage == 41)
        let stateText = try String(contentsOf: state, encoding: .utf8)
        #expect(!stateText.contains("synthetic-private"))
        #expect(!stateText.contains("workspace"))
        #expect(!stateText.contains("synthetic/private"))
    }

    @Test
    func recursiveOrLiteralSecretPriorCommandsAreRejected() throws {
        let recursive = try ConfigurationFixture(existingSettings: #"{"statusLine":{"type":"command","command":"ClaudeStatusLineRelay --again"}}"#)
        defer { recursive.cleanup() }
        #expect(throws: ClaudeStatusLineConfigurationError.recursivePriorCommand) {
            try recursive.manager.enable()
        }

        let secret = try ConfigurationFixture(existingSettings: #"{"statusLine":{"type":"command","command":"ANTHROPIC_API_KEY=literal prior"}}"#)
        defer { secret.cleanup() }
        #expect(throws: ClaudeStatusLineConfigurationError.unsafeLiteralSecret) {
            try secret.manager.enable()
        }
    }

    @Test
    func estimatorRequiresTwoCompatibleExactAnchorsAndNoFixedDenominator() throws {
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let reset = now.addingTimeInterval(4 * 60 * 60)
        let first = try #require(anchor(
            used: 20, tokens: 1_000, observedAt: now.addingTimeInterval(-120), reset: reset
        ))
        let second = try #require(anchor(
            used: 30, tokens: 2_000, observedAt: now.addingTimeInterval(-60), reset: reset
        ))
        let activity = ClaudeSanitizedLocalActivity(
            observedAt: now,
            totalTokens: 2_500,
            latestActivityAt: now,
            modelFamilyKey: "sonnet",
            coveragePercent: 100
        )

        #expect(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour,
            anchors: [first],
            activity: activity,
            previousEstimatedRemaining: nil,
            now: now
        ) == nil)
        let estimate = try #require(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour,
            anchors: [first, second],
            activity: activity,
            previousEstimatedRemaining: nil,
            now: now
        ))
        #expect(estimate.source == .estimatedLocal)
        #expect(estimate.remainingPercent == 65)
        #expect(estimate.confidence == .medium)
    }

    @Test
    func estimatorIsMonotonicAndInvalidatesContinuityDisagreement() throws {
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let reset = now.addingTimeInterval(4 * 60 * 60)
        let first = try #require(anchor(
            used: 20, tokens: 1_000, observedAt: now.addingTimeInterval(-120), reset: reset
        ))
        let second = try #require(anchor(
            used: 30, tokens: 2_000, observedAt: now.addingTimeInterval(-60), reset: reset
        ))
        let activity = ClaudeSanitizedLocalActivity(
            observedAt: now,
            totalTokens: 2_100,
            latestActivityAt: now,
            modelFamilyKey: "sonnet",
            coveragePercent: 100
        )
        let monotonic = try #require(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour,
            anchors: [first, second],
            activity: activity,
            previousEstimatedRemaining: 60,
            now: now
        ))
        #expect(monotonic.remainingPercent == 60)

        let changedReset = try #require(anchor(
            used: 30,
            tokens: 2_000,
            observedAt: now.addingTimeInterval(-60),
            reset: reset.addingTimeInterval(60)
        ))
        #expect(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour,
            anchors: [first, changedReset],
            activity: activity,
            previousEstimatedRemaining: nil,
            now: now
        ) == nil)
    }

    @Test
    func estimatorSplitsSourceSchemaAndRejectsUnknownOrChangedModelFamily() throws {
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let reset = now.addingTimeInterval(4 * 60 * 60)
        let first = try #require(anchor(
            used: 20, tokens: 1_000, observedAt: now.addingTimeInterval(-120), reset: reset
        ))
        let changedSchema = try #require(anchor(
            used: 30, tokens: 2_000, observedAt: now.addingTimeInterval(-60), reset: reset,
            schema: "status-2"
        ))
        let changedSource = try #require(anchor(
            used: 30, tokens: 2_000, observedAt: now.addingTimeInterval(-60), reset: reset,
            source: .exactSafariAccuracy, schema: "status-1"
        ))
        let compatible = try #require(anchor(
            used: 30, tokens: 2_000, observedAt: now.addingTimeInterval(-60), reset: reset
        ))
        let known = ClaudeSanitizedLocalActivity(
            observedAt: now, totalTokens: 2_500, latestActivityAt: now,
            modelFamilyKey: "sonnet", coveragePercent: 100
        )
        let unknown = ClaudeSanitizedLocalActivity(
            observedAt: now, totalTokens: 2_500, latestActivityAt: now,
            modelFamilyKey: nil, coveragePercent: 100
        )
        let changed = ClaudeSanitizedLocalActivity(
            observedAt: now, totalTokens: 2_500, latestActivityAt: now,
            modelFamilyKey: "opus", coveragePercent: 100
        )
        #expect(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour, anchors: [first, changedSchema], activity: known,
            previousEstimatedRemaining: nil, now: now
        ) == nil)
        #expect(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour, anchors: [first, changedSource], activity: known,
            previousEstimatedRemaining: nil, now: now
        ) == nil)
        #expect(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour, anchors: [first, compatible], activity: unknown,
            previousEstimatedRemaining: nil, now: now
        ) == nil)
        #expect(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour, anchors: [first, compatible], activity: changed,
            previousEstimatedRemaining: nil, now: now
        ) == nil)
    }

    @Test
    func anchorStoreRejectsUnsafeModeWithoutDeletingData() async throws {
        let root = temporaryDirectory("unsafe-anchor-store")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("owner/anchors.json")
        let store = ClaudeSmartAnchorStore(url: url)
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let value = try #require(anchor(
            used: 20, tokens: 1_000, observedAt: now,
            reset: now.addingTimeInterval(3_600)
        ))
        try await store.save([value])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: url.path
        )
        #expect(await store.load().isEmpty)
        await #expect(throws: ClaudeSmartAnchorStore.StoreError.unsafePath) {
            try await store.clear()
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func anchorStoreRoundTripsResetlessSafariAndLegacyResetBearingRecords() async throws {
        let root = temporaryDirectory("optional-reset-anchor-store")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("owner/anchors.json")
        let store = ClaudeSmartAnchorStore(url: url)
        let observedAt = Date(timeIntervalSince1970: 1_898_596_800)
        let resetless = try #require(anchor(
            used: 27, tokens: 1_000, observedAt: observedAt, reset: nil,
            source: .exactSafariAccuracy, model: nil, schema: "safari-2"
        ))
        let legacy = try #require(anchor(
            used: 30, tokens: 2_000, observedAt: observedAt.addingTimeInterval(1),
            reset: observedAt.addingTimeInterval(3_600)
        ))

        try await store.save([resetless, legacy])
        #expect(await store.load() == [resetless, legacy])
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[
            .posixPermissions
        ] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let encoded = try String(contentsOf: url, encoding: .utf8)
        #expect(!encoded.contains("resetAt"))
        #expect(!encoded.contains("null"))
        #expect(encoded.contains("resetsAt"))
    }

    @Test
    func anchorStoreRejectsSymlinksAndUnknownSchemaFields() async throws {
        let root = temporaryDirectory("anchor-store-adversarial")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let owner = root.appendingPathComponent("owner", isDirectory: true)
        try FileManager.default.createDirectory(
            at: owner,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let target = owner.appendingPathComponent("target.json")
        try Data("sentinel".utf8).write(to: target)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: target.path
        )
        let symlink = owner.appendingPathComponent("anchors.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        let value = try #require(anchor(
            used: 20, tokens: nil, observedAt: now, reset: nil,
            source: .exactSafariAccuracy, model: nil, schema: "safari-2"
        ))
        let symlinkStore = ClaudeSmartAnchorStore(url: symlink, now: { now })
        do {
            try await symlinkStore.save([value])
            Issue.record("Symlink-backed anchor store unexpectedly accepted a write")
        } catch {
            #expect(error as? ClaudeSmartAnchorStore.StoreError == .unsafePath)
        }
        #expect(String(data: try Data(contentsOf: target), encoding: .utf8) == "sentinel")

        try FileManager.default.removeItem(at: symlink)
        let regularURL = owner.appendingPathComponent("strict-anchors.json")
        let store = ClaudeSmartAnchorStore(url: regularURL, now: { now })
        try await store.save([value])
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: regularURL)) as? [String: Any]
        )
        var records = try #require(object["anchors"] as? [[String: Any]])
        records[0]["accountIdentity"] = "must-not-be-admitted"
        object["anchors"] = records
        try JSONSerialization.data(withJSONObject: object).write(to: regularURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: regularURL.path
        )
        #expect(await store.load().isEmpty)
    }

    @Test
    func anchorStoreAtomicCrashWindowsPreserveOneCompleteGeneration() async throws {
        let root = temporaryDirectory("anchor-store-crash-windows")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("owner/anchors.json")
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let old = try #require(anchor(
            used: 20, tokens: nil, observedAt: now, reset: nil,
            source: .exactSafariAccuracy, model: nil, schema: "safari-2"
        ))
        let new = try #require(anchor(
            used: 21, tokens: nil, observedAt: now.addingTimeInterval(1), reset: nil,
            source: .exactSafariAccuracy, model: nil, schema: "safari-2"
        ))
        let stable = ClaudeSmartAnchorStore(url: url, now: { now })
        try await stable.save([old])

        let beforeRename = ClaudeSmartAnchorStore(
            url: url,
            now: { now },
            commitFault: .beforeRename
        )
        await #expect(throws: ClaudeSmartAnchorStore.StoreError.simulatedCrashBeforeRename) {
            try await beforeRename.save([new])
        }
        #expect(await stable.load() == [old])
        let temporaryNames = try FileManager.default.contentsOfDirectory(atPath: url
            .deletingLastPathComponent().path)
        #expect(temporaryNames.allSatisfy { !$0.hasSuffix(".tmp") })

        let afterRename = ClaudeSmartAnchorStore(
            url: url,
            now: { now },
            commitFault: .afterRenameBeforeReadback
        )
        await #expect(throws: ClaudeSmartAnchorStore.StoreError.simulatedCrashAfterRename) {
            try await afterRename.save([new])
        }
        // A crash before rename preserves the old generation; a crash after
        // rename exposes the complete new generation, never a torn payload.
        #expect(await stable.load() == [new])
    }

    @Test
    func expiredResetlessAnchorIsPurgedFromDurableStore() async throws {
        let root = temporaryDirectory("anchor-store-expiry")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("owner/anchors.json")
        let clock = BrowserTestClock()
        let value = try #require(anchor(
            used: 27, tokens: nil, observedAt: clock.now(), reset: nil,
            source: .exactSafariAccuracy, model: nil, schema: "safari-2"
        ))
        let store = ClaudeSmartAnchorStore(url: url, now: clock.now)
        try await store.save([value])
        #expect(await store.load() == [value])

        clock.advance(ClaudeSmartSourceSelector.exactFreshnessInterval + 1)
        #expect(await store.load().isEmpty)
        let persisted = try String(contentsOf: url, encoding: .utf8)
        #expect(persisted.contains("\"anchors\":[]"))
    }

    @Test
    func sourceOrderIsFreshSafariThenExactLocalThenEstimateThenStale() throws {
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let reset = now.addingTimeInterval(3_600)
        let local = try #require(anchor(
            used: 18, tokens: 1_000, observedAt: now, reset: reset,
            source: .exactLocalStatusLine
        ))
        let safari = try #require(anchor(
            used: 19, tokens: 1_000, observedAt: now, reset: reset,
            source: .exactSafariAccuracy
        ))
        let estimate = ClaudeSmartWindowValue(
            windowKind: .fiveHour,
            remainingPercent: 79,
            resetsAt: reset,
            observedAt: now,
            source: .estimatedLocal,
            confidence: .medium
        )
        #expect(ClaudeSmartSourceSelector.select(
            windowKind: .fiveHour,
            statusLineAnchors: [local],
            safariAnchors: [safari],
            estimate: estimate,
            staleExact: safari,
            now: now
        )?.source == .exactSafariAccuracy)
        #expect(ClaudeSmartSourceSelector.select(
            windowKind: .fiveHour,
            statusLineAnchors: [],
            safariAnchors: [safari],
            estimate: estimate,
            staleExact: local,
            now: now
        )?.source == .exactSafariAccuracy)
        #expect(ClaudeSmartSourceSelector.select(
            windowKind: .fiveHour,
            statusLineAnchors: [],
            safariAnchors: [],
            estimate: estimate,
            staleExact: local,
            now: now
        )?.source == .estimatedLocal)
    }

    @Test
    func localRefreshNeverDispatchesSafariAndAccuracyIsOneShot() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await connector.syncNow()
        await connector.refresh(trigger: .timer)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect(!(await connector.diagnostics()).schedulerActive)

        await fixture.bridge.send(browserEnvelope(five: 22, seven: 44))
        #expect((await connector.diagnostics()).acceptedObservationCount == 0)

        await connector.accuracySync()
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect((await connector.diagnostics()).automaticRefreshInFlight)
        await fixture.bridge.send(browserEnvelope(five: 22, seven: 44))
        #expect((await connector.diagnostics()).acceptedObservationCount == 1)
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)

        await connector.syncNow()
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect((await connector.diagnostics()).scheduledCycleCount == 0)
        #expect(!(await connector.diagnostics()).schedulerActive)
    }

    @Test
    func missingStatusLineReportsPendingWithoutRestartOrHumanRetryRequirement() async {
        let root = temporaryDirectory("status-line-pending")
        defer { try? FileManager.default.removeItem(at: root) }
        let connector = ClaudeCodeUsageConnector.production(
            hasConsent: { true },
            statusStateURL: root.appendingPathComponent("status-line.json")
        )

        await connector.start()
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.lastLiveLinkStage == .localStatusLinePending)
        #expect(diagnostics.acceptedObservationCount == 0)
        #expect(await connector.lifecycleState() == .waitingForUsagePage)
        let status = AppLanguage.english.claudeLiveLinkStatus(diagnostics.lastLiveLinkStage)
        #expect(status.contains("official Claude Code status-line"))
        #expect(!status.localizedCaseInsensitiveContains("complete"))
        #expect(!status.localizedCaseInsensitiveContains("response"))
        #expect(!status.localizedCaseInsensitiveContains("restart"))
    }

    @Test
    func contentFreeOfficialStatusLineCallbackAdvancesExistingConnector() async throws {
        let fixture = try ConfigurationFixture(existingSettings: #"{"theme":"dark"}"#)
        defer { fixture.cleanup() }

        try fixture.manager.enable()
        #expect(fixture.manager.check().state == .installed)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.stateURL.path))

        let connector = ClaudeCodeUsageConnector.production(
            hasConsent: { true },
            statusStateURL: fixture.paths.stateURL
        )
        await connector.start()

        var diagnostics = await connector.diagnostics()
        #expect(diagnostics.lastLiveLinkStage == .localStatusLinePending)
        #expect(diagnostics.acceptedObservationCount == 0)
        #expect(await connector.lifecycleState() == .waitingForUsagePage)

        // Configuration presence is not proof. Only a packet written by the
        // official status-line command advances the live-link state.
        let receipt = try ClaudeStatusLinePacket(
            claudeVersion: "2.1.0",
            fiveHour: nil,
            sevenDay: nil,
            observedAt: Date()
        )
        try ClaudeStatusLineStateStore(stateURL: fixture.paths.stateURL).write(receipt)
        await connector.syncNow()

        diagnostics = await connector.diagnostics()
        #expect(diagnostics.lastLiveLinkStage == .localCallbackWithoutQuotaWindows)
        #expect(diagnostics.acceptedObservationCount > 0)
    }

    @Test
    func rejectedStatusLineRecoversWithExactQuotaState() async throws {
        let root = temporaryDirectory("status-line-recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let statusURL = root.appendingPathComponent("state/status-line.json")
        try FileManager.default.createDirectory(
            at: statusURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: statusURL.deletingLastPathComponent().path
        )
        try Data("not-a-packet".utf8).write(to: statusURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: statusURL.path
        )
        let connector = ClaudeCodeUsageConnector.production(
            hasConsent: { true },
            statusStateURL: statusURL,
            anchorStore: ClaudeSmartAnchorStore(
                url: root.appendingPathComponent("state/anchors.json")
            )
        )

        await connector.start()
        #expect((await connector.diagnostics()).lastLiveLinkStage == .localStatusLineRejected)
        #expect((await connector.diagnostics()).acceptedObservationCount == 0)

        let contentFreeStatusLine = try ClaudeStatusLinePacket(
            claudeVersion: nil,
            fiveHour: nil,
            sevenDay: nil,
            observedAt: Date()
        )
        try ClaudeStatusLineStateStore(stateURL: statusURL).write(contentFreeStatusLine)
        await connector.syncNow()
        #expect((await connector.diagnostics()).lastLiveLinkStage
            == .localCallbackWithoutQuotaWindows)

        let exact = try smartPacket(observedAt: Date())
        let store = ClaudeStatusLineStateStore(stateURL: statusURL)
        try store.write(exact)
        let storedExact = try #require(try store.read())
        #expect(storedExact.fiveHour == exact.fiveHour)
        #expect(storedExact.sevenDay == exact.sevenDay)
        await connector.syncNow()
        #expect((await connector.diagnostics()).lastLiveLinkStage == .localExactReceived)
        #expect(try store.read() == storedExact)
    }

    @Test @MainActor
    func persistedCurrentSafariAnchorRemainsExactWhileLocalStatusLineIsPending() async throws {
        let root = temporaryDirectory("retained-accuracy-relaunch")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let persisted = try #require(anchor(
            used: 23,
            tokens: 1_000,
            observedAt: now.addingTimeInterval(-60),
            reset: now.addingTimeInterval(3_600),
            source: .exactSafariAccuracy,
            model: nil,
            schema: "safari-2"
        ))
        let anchorStore = ClaudeSmartAnchorStore(
            url: root.appendingPathComponent("state/anchors.json")
        )
        try await anchorStore.save([persisted])
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            now: { now },
            statusStateStore: ClaudeStatusLineStateStore(
                stateURL: root.appendingPathComponent("state/status-line.json")
            ),
            anchorStore: anchorStore
        )

        await connector.start()
        let snapshot = await connector.currentSnapshot()
        let account = try #require(snapshot.channels.first(where: { $0.id == .account }))
        let quota = try #require(account.rateLimitWindows.first)
        let diagnostics = await connector.diagnostics()
        #expect(snapshot.freshness == .fresh)
        #expect(account.sourceConfidence == "exact")
        #expect(quota.remainingPercent == 77)
        #expect(quota.isEstimated == false)
        #expect(diagnostics.currentQuotaIncludesSafariAccuracy)
        #expect(diagnostics.lastLiveLinkStage == .localStatusLinePending)
        #expect(diagnostics.acceptedObservationCount == 0)

        let suite = "M5RMXRetainedAccuracy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        consent.consentGranted = true
        let model = ClaudeBrowserSettingsModel(connector: connector, consentStore: consent)
        for _ in 0..<100 where !model.currentQuotaIncludesSafariAccuracy {
            await Task.yield()
        }
        #expect(model.currentQuotaIncludesSafariAccuracy)
        #expect(model.liveLinkStage == .localStatusLinePending)
        if case .fresh = model.state {
            // The exact one-shot observation stays current while the
            // official local status-line remains unavailable in this surface.
        } else {
            Issue.record("Persisted current Accuracy anchor was downgraded after relaunch")
        }
        #expect(AppLanguage.english.claudeRetainedAccuracyAwaitingLocalReceipt
            .contains("exact Accuracy Sync value is retained"))
        #expect(AppLanguage.english.claudeRetainedAccuracyAwaitingLocalReceipt
            .contains("official local status-line anchor"))
    }

    @Test
    func callbackWithoutRateLimitWindowsIsReceiptNotMalformedData() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        let receipt = try ClaudeStatusLinePacket(
            claudeVersion: "2.1.0",
            fiveHour: nil,
            sevenDay: nil,
            observedAt: fixture.clock.now()
        )

        await connector.receiveEncodedStatusLinePacket(try receipt.encoded())
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.acceptedObservationCount == 1)
        #expect(diagnostics.rejectedObservationCount == 0)
        #expect(diagnostics.lastLiveLinkStage == .localCallbackWithoutQuotaWindows)
        let snapshot = await connector.currentSnapshot()
        #expect(!snapshot.hasValidData)
        #expect(snapshot.state == .ready)
        #expect(snapshot.channels.isEmpty)
        #expect(AppLanguage.english.claudeLiveLinkStatus(diagnostics.lastLiveLinkStage)
            .contains("Local activity received"))
    }

    @Test
    func localActivityAndNilWindowCallbackPublishActivityWithoutFabricatedQuota() async throws {
        let clock = BrowserTestClock()
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            now: clock.now,
            localActivityReader: SmartActivityReader(now: clock.now())
        )
        await connector.start()
        let receipt = try ClaudeStatusLinePacket(
            claudeVersion: "2.1.0",
            fiveHour: nil,
            sevenDay: nil,
            observedAt: clock.now()
        )

        await connector.receiveEncodedStatusLinePacket(try receipt.encoded())
        let snapshot = await connector.currentSnapshot()
        let local = snapshot.channels.first(where: { $0.id == .localActivity })
        #expect(snapshot.state == .ready)
        #expect(local?.localActivityMetrics?.sessionTokens == 1_234)
        #expect(snapshot.channels.flatMap(\.rateLimitWindows).isEmpty)
        #expect((await connector.diagnostics()).lastLiveLinkStage
            == .localCallbackWithoutQuotaWindows)
    }

    @Test
    func localActivityWithoutStatusLineUsesTruthfulAwaitingAnchorState() async {
        let clock = BrowserTestClock()
        let root = temporaryDirectory("activity-awaiting-anchor")
        defer { try? FileManager.default.removeItem(at: root) }
        let connector = ClaudeCodeUsageConnector.production(
            hasConsent: { true },
            statusStateURL: root.appendingPathComponent("status-line.json"),
            localActivityReader: SmartActivityReader(now: clock.now())
        )

        await connector.start()
        let diagnostics = await connector.diagnostics()
        let snapshot = await connector.currentSnapshot()
        #expect(diagnostics.lastLiveLinkStage == .localActivityDetectedAwaitingExactAnchor)
        #expect(snapshot.channels.contains(where: { $0.id == .localActivity }))
        #expect(snapshot.channels.flatMap(\.rateLimitWindows).isEmpty)
        let status = AppLanguage.english.claudeLiveLinkStatus(diagnostics.lastLiveLinkStage)
        #expect(status == "Activity detected — awaiting exact usage anchor.")
        #expect(!status.localizedCaseInsensitiveContains("first response"))
        #expect(!status.localizedCaseInsensitiveContains("complete"))
    }

    @Test
    func everyAccuracyFailureHasSpecificNontechnicalEnglishAndChineseCopy() {
        let stages: [ClaudeLiveLinkStageReason] = [
            .accuracyHandshakeUnavailable,
            .accuracyWorkDispatchFailed,
            .accuracyPermissionRequired,
            .accuracySignInRequired,
            .accuracyRouteRejected,
            .accuracyUsageUnavailable,
            .accuracyTabUnavailable,
            .accuracyOwnedTabLost,
            .accuracyRequestMismatch,
        ]
        let genericEnglish = AppLanguage.english.claudeLiveLinkStatus(nil)
        let genericChinese = AppLanguage.simplifiedChinese.claudeLiveLinkStatus(nil)

        for stage in stages {
            #expect(stage.isAccuracyFailure)
            let english = AppLanguage.english.claudeLiveLinkStatus(stage)
            let chinese = AppLanguage.simplifiedChinese.claudeLiveLinkStatus(stage)
            #expect(english != genericEnglish)
            #expect(chinese != genericChinese)
            #expect(!english.contains("Refresh Failed"))
            #expect(!chinese.contains("刷新失败"))
        }

        for stage in [
            ClaudeLiveLinkStageReason.localStatusLinePending,
            ClaudeLiveLinkStageReason.localStatusLineRejected,
            ClaudeLiveLinkStageReason.localActivityDetectedAwaitingExactAnchor,
            .localCallbackWithoutQuotaWindows,
            .localExactReceived,
            .accuracyExactReceived,
        ] {
            #expect(!stage.isAccuracyFailure)
        }

        let settingsSource = try? String(
            contentsOfFile: "Sources/CodexUsageUI/Views/UsageSettingsCard.swift",
            encoding: .utf8
        )
        #expect(settingsSource?.contains("model.localSmartState") == true)
        #expect(settingsSource?.contains("model.browserAccuracyState") == true)
        #expect(settingsSource?.contains("stage.isAccuracyFailure") == false)
    }

    @Test
    func accuracyObservationMustMatchTheActiveOneShotRequest() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.accuracySync()
        await fixture.bridge.sendUnbound(browserEnvelope(five: 22, seven: 44))

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.acceptedObservationCount == 0)
        #expect(diagnostics.rejectedObservationCount == 1)
        #expect(diagnostics.lastLiveLinkStage == .accuracyRequestMismatch)
        #expect(!diagnostics.automaticRefreshInFlight)
    }

    @Test
    func exactSafariPercentageWithoutResetSurvivesCleanupButNeverCalibrates() async throws {
        let store = ResetlessSafariAnchorStore()
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector(anchorStore: store)
        await connector.accuracySync()
        let requestID = try #require(await fixture.bridge.automaticRequests.last?.requestID)
        let observation = ClaudeBrowserObservationEnvelope(
            browserFamily: .safari,
            observation: .init(
                fiveHour: .init(usedPercentage: 27, resetAt: nil),
                weeklyAllModels: .init(usedPercentage: 43, resetAt: nil),
                observedAt: "2030-03-01T12:00:00Z"
            )
        )

        // OLD: acceptSafariAccuracy admitted only windows with resetAt and
        // collapsed this truthful observation into noAccountWindow/routeRejected.
        await fixture.bridge.send(observation)
        await fixture.bridge.sendAutomation(
            requestID: requestID,
            status: .refreshCompleted
        )

        let afterCleanup = await connector.currentSnapshot()
        let windows = try #require(afterCleanup.channels.first).rateLimitWindows
        #expect(windows.map(\.normalizedRemainingPercent) == [73, 57])
        #expect(windows.allSatisfy { $0.resetsAt == nil })
        #expect(windows.allSatisfy { $0.isEstimated != true })
        #expect((await connector.diagnostics()).acceptedObservationCount == 1)
        #expect((await connector.diagnostics()).rejectedObservationCount == 0)
        #expect((await connector.diagnostics()).lastLiveLinkStage == .accuracyExactReceived)
        #expect((await connector.diagnostics()).browserAccuracyState
            == .exactAnchorAvailable(fixture.clock.now()))
        #expect(await store.savedAnchorCount() == 2)
        #expect(await store.saveInvocationCount() == 1)

        // A fresh process loads the same sanitized optional-reset truth without
        // another provider read or a fabricated reset.
        await connector.stop()
        let relaunched = fixture.connector(anchorStore: store)
        await relaunched.start()
        let afterRelaunch = await relaunched.currentSnapshot()
        let relaunchedWindows = try #require(
            afterRelaunch.channels.first
        ).rateLimitWindows
        #expect(relaunchedWindows.map(\.normalizedRemainingPercent) == [73, 57])
        #expect(relaunchedWindows.allSatisfy { $0.resetsAt == nil })
        #expect((await relaunched.diagnostics()).currentQuotaIncludesSafariAccuracy)

        // A resetless percentage is exact only for the bounded observation
        // freshness window. It cannot become a stale/calibration anchor.
        fixture.clock.advance(ClaudeSmartSourceSelector.exactFreshnessInterval + 1)
        let expired = await relaunched.currentSnapshot()
        #expect(expired.channels.flatMap(\.rateLimitWindows).isEmpty)
        #expect((await relaunched.diagnostics()).currentQuotaIncludesSafariAccuracy == false)
        #expect(await store.savedAnchorCount() == 2)

        let loaded = await store.savedAnchors()
        #expect(loaded.allSatisfy { $0.resetsAt == nil })
        #expect(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour,
            anchors: loaded,
            activity: ClaudeSanitizedLocalActivity(
                observedAt: fixture.clock.now(),
                totalTokens: 10_000,
                latestActivityAt: fixture.clock.now(),
                modelFamilyKey: "sonnet",
                coveragePercent: 100
            ),
            previousEstimatedRemaining: nil,
            now: fixture.clock.now()
        ) == nil)
    }

    @Test
    func accuracyAnchorIsNotAcknowledgedOrPublishedBeforeDurableReadback() async throws {
        let store = WriteOnlyAnchorStore()
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector(anchorStore: store)
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 27, seven: 43))

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.acceptedObservationCount == 0)
        #expect(diagnostics.rejectedObservationCount == 1)
        #expect(!diagnostics.currentQuotaIncludesSafariAccuracy)
        #expect((await connector.currentSnapshot()).channels
            .flatMap(\.rateLimitWindows).isEmpty)
        #expect(await store.saveInvocationCount() == 1)
    }

    @Test
    func optionalSafariFailureCannotDestroyExactLocalStatusLineTruth() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        let packet = try smartPacket(observedAt: fixture.clock.now())
        await connector.receiveEncodedStatusLinePacket(try packet.encoded())
        let exact = await connector.currentSnapshot()
        #expect(exact.hasValidData)
        #expect(exact.state == .ready)

        await fixture.bridge.setHealth(.disabled)
        await connector.checkCompanion()
        let retained = await connector.currentSnapshot()
        let diagnostics = await connector.diagnostics()
        #expect(retained.hasValidData)
        #expect(retained.state == .ready)
        #expect(retained.lastSuccessfulAt == exact.lastSuccessfulAt)
        #expect(retained.safeFailure == nil)
        #expect(diagnostics.localSmartState == .exactLocal(packet.observedAt))
        #expect(diagnostics.browserAccuracyState == .companionUnavailable)
    }

    @Test
    func healthyDesktopEstimateSurvivesBrowserCompanionFailure() async throws {
        let clock = BrowserTestClock()
        let bridge = BrowserTestBridge()
        await bridge.setHealth(.disabled)
        let observedAt = clock.now().addingTimeInterval(-15)
        let connector = ClaudeCodeUsageConnector(
            integration: stateSeparationIntegration(bridge),
            hasConsent: { true },
            now: clock.now,
            desktopPlanUsageReader: StateSeparationDesktopReader(snapshot:
                ClaudeDesktopPlanUsageSnapshot(
                    observedAt: observedAt,
                    fiveHourRemainingPercent: 74,
                    sevenDayRemainingPercent: 63
                )
            ),
            desktopActivityContract: .estimateOnlyNoActivitySignal
        )

        await connector.start()
        let before = await connector.currentSnapshot()
        await connector.checkCompanion()
        let after = await connector.currentSnapshot()
        let diagnostics = await connector.diagnostics()

        #expect(before.channels.first(where: { $0.id == .account }) != nil)
        #expect(after.channels.first(where: { $0.id == .account })?.rateLimitWindows
            .allSatisfy { $0.isEstimated == true } == true)
        #expect(after.state == .ready)
        #expect(after.safeFailure == nil)
        #expect(diagnostics.localSmartState == .estimated(observedAt))
        #expect(diagnostics.localSmartStage == .desktopActivitySignalUnavailable)
        #expect(diagnostics.browserAccuracyState == .companionUnavailable)
        #expect(diagnostics.browserAccuracyStage == .accuracyCompanionUnavailable)
    }

    @Test
    func browserExactRemainsEffectiveWhileLocalSmartIsStaleUnsupported() async throws {
        let clock = BrowserTestClock()
        let bridge = BrowserTestBridge()
        let connector = ClaudeCodeUsageConnector(
            integration: stateSeparationIntegration(bridge),
            hasConsent: { true },
            now: clock.now,
            desktopPlanUsageReader: StateSeparationDesktopReader(snapshot: nil),
            desktopActivityContract: .estimateOnlyNoActivitySignal,
            anchorStore: ResetlessSafariAnchorStore()
        )

        await connector.start()
        #expect((await connector.diagnostics()).localSmartState == .staleUnsupported(nil))
        await connector.accuracySync()
        await bridge.send(browserEnvelope(five: 22, seven: 44))

        let snapshot = await connector.currentSnapshot()
        let diagnostics = await connector.diagnostics()
        let account = try #require(snapshot.channels.first(where: { $0.id == .account }))
        #expect(account.rateLimitWindows.count == 2)
        #expect(account.rateLimitWindows.allSatisfy { $0.isEstimated != true })
        #expect(diagnostics.localSmartState == .staleUnsupported(nil))
        #expect(diagnostics.browserAccuracyState == .exactAnchorAvailable(clock.now()))
        #expect(diagnostics.currentQuotaIncludesSafariAccuracy)
    }

    @Test
    func browserUpdatePendingRestartDoesNotReplaceHealthyLocalPresentation() async throws {
        let clock = BrowserTestClock()
        let bridge = BrowserTestBridge()
        let observedAt = clock.now().addingTimeInterval(-10)
        let connector = ClaudeCodeUsageConnector(
            integration: stateSeparationIntegration(bridge),
            hasConsent: { true },
            now: clock.now,
            desktopPlanUsageReader: StateSeparationDesktopReader(snapshot:
                ClaudeDesktopPlanUsageSnapshot(
                    observedAt: observedAt,
                    fiveHourRemainingPercent: 70,
                    sevenDayRemainingPercent: 60
                )
            ),
            desktopActivityContract: .estimateOnlyNoActivitySignal
        )

        await connector.start()
        // Set the browser-only lifecycle after local startup so this test
        // proves that a later inventory fault cannot overwrite the healthy
        // Local Smart layer.
        await bridge.setHealth(.inventoryRestartRequired)
        await bridge.setVerificationResult(.unavailable)
        await connector.checkCompanion()
        let snapshot = await connector.currentSnapshot()
        let diagnostics = await connector.diagnostics()
        #expect(snapshot.hasValidData)
        #expect(diagnostics.localSmartState == .estimated(observedAt))
        #expect(diagnostics.browserAccuracyState == .updatePendingRestart)
        #expect(AppLanguage.english.claudeLocalSmartStatus(
            diagnostics.localSmartState,
            stage: diagnostics.localSmartStage
        ).contains("≈ Local estimate available"))
        #expect(AppLanguage.english.claudeBrowserAccuracyStatus(
            diagnostics.browserAccuracyState,
            stage: diagnostics.browserAccuracyStage
        ) == "Browser Companion update ready — restart Safari once.")
    }

    @Test
    func exactAndEstimatedPresentationAreVisiblyDistinct() {
        let exact = SharedUsageWindowPresentation(
            id: "exact",
            kind: .fiveHour,
            compactLabel: "5h",
            accessibilityLabel: "Five-hour",
            remaining: .finite(72),
            resetsAt: nil,
            resetText: ""
        )
        let estimated = SharedUsageWindowPresentation(
            id: "estimated",
            kind: .fiveHour,
            compactLabel: "5h",
            accessibilityLabel: "Five-hour",
            remaining: .finite(72),
            isEstimated: true,
            resetsAt: nil,
            resetText: ""
        )
        #expect(exact.isEstimated != true)
        #expect(estimated.isEstimated == true)
    }

    @Test
    func estimatedAccessibilityIsTruthfulLocalizedAndHidesInternalSourceEnums() {
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let account = AgentUsageChannel(
            id: .account,
            sourceTier: .officialStructuredHook,
            sourceVersion: "smart-1",
            scopes: [.account],
            provenance: .locallyEstimated,
            freshness: .cached,
            capturedAt: now,
            coverageNote: "Claude Local Smart Mode · EXACT_LOCAL_STATUSLINE · high",
            sourceConfidence: "high",
            lastExactAt: now,
            rateLimitWindows: [
                AgentRateLimitWindow(
                    id: "five-hour",
                    kind: .fiveHour,
                    usedPercent: nil,
                    remainingPercent: 72,
                    isEstimated: true,
                    isUnlimited: false,
                    resetsAt: now.addingTimeInterval(3_600)
                )
            ],
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: nil
        )
        let snapshot = AgentUsageSnapshot(
            id: ClaudeCodeUsageConnector.connectorID,
            providerName: "Claude Code",
            state: .ready,
            capturedAt: now,
            lastSuccessfulAt: now,
            freshness: .cached,
            channels: [account],
            capabilities: [],
            safeFailure: nil,
            selectedWindowID: "five-hour"
        )

        let english = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .english,
            now: now
        )
        #expect(english.tooltipText.contains("approximately 72 percent remaining"))
        #expect(english.sourceDescription == "Claude Local Smart Mode · on-demand Accuracy Sync")
        #expect(!english.tooltipText.contains("EXACT_LOCAL_STATUSLINE"))

        let chinese = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .simplifiedChinese,
            now: now
        )
        #expect(chinese.tooltipText.contains("预计剩余 72%"))
        #expect(chinese.sourceDescription == "Claude 本地智能模式 · 按需精确同步")
        #expect(!chinese.tooltipText.contains("EXACT_LOCAL_STATUSLINE"))

        let panel = try? String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsagePanelView.swift"
            ),
            encoding: .utf8
        )
        #expect(panel?.contains("window.remainingAccessibilityText") == true)
        #expect(panel?.contains(".accessibilityElement(children: .ignore)") == true)
    }

    @Test
    func mixedExactAndEstimatedWindowsPreserveIndependentMarkers() throws {
        let now = Date(timeIntervalSince1970: 1_898_596_800)
        let account = AgentUsageChannel(
            id: .account,
            sourceTier: .officialStructuredHook,
            sourceVersion: "smart-1",
            scopes: [.account],
            provenance: .locallyEstimated,
            freshness: .cached,
            capturedAt: now,
            coverageNote: "Claude Local Smart Mode",
            sourceConfidence: "medium",
            lastExactAt: now.addingTimeInterval(-60),
            rateLimitWindows: [
                AgentRateLimitWindow(
                    id: "five-hour",
                    kind: .fiveHour,
                    usedPercent: nil,
                    remainingPercent: 71,
                    isEstimated: false,
                    isUnlimited: false,
                    resetsAt: now.addingTimeInterval(3_600)
                ),
                AgentRateLimitWindow(
                    id: "seven-day",
                    kind: .sevenDay,
                    usedPercent: nil,
                    remainingPercent: 62,
                    isEstimated: true,
                    isUnlimited: false,
                    resetsAt: now.addingTimeInterval(86_400)
                ),
            ],
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: nil
        )
        let snapshot = AgentUsageSnapshot(
            id: ClaudeCodeUsageConnector.connectorID,
            providerName: "Claude Code",
            state: .ready,
            capturedAt: now,
            lastSuccessfulAt: now,
            freshness: .cached,
            channels: [account],
            capabilities: ClaudeCodeUsageConnector.production().descriptor.capabilities,
            safeFailure: nil,
            selectedWindowID: "five-hour"
        )

        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .english,
            now: now
        )
        #expect(card.windows.first(where: { $0.id == "five-hour" })?.isEstimated != true)
        #expect(card.windows.first(where: { $0.id == "seven-day" })?.isEstimated == true)
        #expect(card.isEstimated != true)

        let usage = UsageSnapshot(agentSnapshot: snapshot, language: .english, now: now)
        #expect(usage.periods.first(where: { $0.id == "five-hour" })?.isEstimated != true)
        #expect(usage.periods.first(where: { $0.id == "seven-day" })?.isEstimated == true)
    }

    @Test
    func settingsExposeFirstAccuracyReadConfidenceAndLastExactTruth() throws {
        let settings = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
            ),
            encoding: .utf8
        )
        #expect(settings.contains("case .waitingForUsagePage, .fresh, .cached, .stale:"))
        #expect(settings.contains("claudeEstimateConfidence(model.estimateConfidence)"))
        #expect(settings.contains("claudeLastExact(model.lastExactAt)"))
        #expect(settings.contains("model.localSmartState"))
        #expect(settings.contains("model.browserAccuracyState"))
        #expect(settings.contains("claude.source-state-summary"))
        #expect(AppLanguage.english.claudeEstimateConfidence("medium")
            == "Estimate confidence: Medium")
        #expect(AppLanguage.english.claudeEstimateConfidence("exact")
            == "Estimate confidence: Exact value — estimate not active")
        #expect(AppLanguage.english.claudeLastExact(nil)
            == "Last exact observation: Not yet received")
        #expect(!AppLanguage.english.claudeBrowserError(.timedOut).contains("Browser Sync"))
        #expect(AppLanguage.english.claudeBrowserError(.timedOut).contains("Accuracy Sync"))
        #expect(AppLanguage.english.claudeBrowserActionStatus(.requestingSiteAccess)
            == "Requesting Safari Site Access…")
        #expect(AppLanguage.english.claudeBrowserActionStatus(.retryingSiteAccess)
            == "Retrying Safari Site Access…")
        #expect(AppLanguage.simplifiedChinese.claudeBrowserActionStatus(.requestingSiteAccess)
            == "正在请求 Safari 网站访问权限…")
        #expect(AppLanguage.english.claudeConsentDisclosure.contains(
            "one bounded local Claude Code JSONL record"
        ))
        #expect(AppLanguage.english.claudeConsentDisclosure.contains("allowlisted usage counts"))
        #expect(AppLanguage.english.claudeConsentDisclosure.contains(
            "≈ local-activity estimate distinct from official exact quota"
        ))
        #expect(AppLanguage.english.claudeConsentDisclosure.contains(
            "does not expose a stable local activity signal"
        ))
        #expect(AppLanguage.english.claudeConsentDisclosure.contains(
            "including a per-response signal"
        ))

        let settingsSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
            ),
            encoding: .utf8
        )
        #expect(settingsSource.contains("Request Safari Site Access"))
        #expect(settingsSource.contains("Retry Safari Site Access"))
        #expect(!settingsSource.contains("Open Safari Access Settings"))
    }

    private func smartPacket(observedAt: Date) throws -> ClaudeStatusLinePacket {
        try ClaudeStatusLinePacket(
            claudeVersion: "2.1.0",
            fiveHour: ClaudeStatusLineWindowPacket(
                usedPercentage: 28,
                resetsAtEpochSeconds: 1_898_600_400
            ),
            sevenDay: ClaudeStatusLineWindowPacket(
                usedPercentage: 41,
                resetsAtEpochSeconds: 1_899_198_000
            ),
            observedAt: observedAt
        )
    }

    private func anchor(
        used: Double,
        tokens: Int64?,
        observedAt: Date,
        reset: Date?,
        source: ClaudeSmartSourceKind = .exactLocalStatusLine,
        model: String? = "sonnet",
        schema: String = "status-1"
    ) -> ClaudeSmartWindowAnchor? {
        ClaudeSmartWindowAnchor(
            windowKind: .fiveHour,
            usedPercent: used,
            resetsAt: reset,
            observedAt: observedAt,
            activityTotalTokens: tokens,
            source: source,
            modelFamilyKey: model,
            sourceSchema: schema,
            continuityGeneration: 0
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("uma-m5rmx-smart-\(name)-\(UUID().uuidString)")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct StateSeparationDesktopReader: ClaudeDesktopPlanUsageReading {
    let snapshot: ClaudeDesktopPlanUsageSnapshot?

    func read(now: Date) -> ClaudeDesktopPlanUsageSnapshot? {
        _ = now
        return snapshot
    }
}

private func stateSeparationIntegration(
    _ bridge: BrowserTestBridge
) -> ClaudeBrowserProductionIntegration {
    ClaudeBrowserProductionIntegration(
        startListening: { handler in await bridge.start(handler) },
        stopListening: { await bridge.stop() },
        checkHealth: { await bridge.currentHealth() },
        openUsagePage: { await bridge.open() },
        repairCompanion: { await bridge.repair() },
        verifyHandshake: { await bridge.verifyHandshake() },
        requestAutomaticRefresh: { requestID, allowSafariLaunch in
            await bridge.requestAutomaticRefresh(
                requestID: requestID,
                allowSafariLaunch: allowSafariLaunch
            )
        },
        closeOwnedUsageTab: { requestID in
            await bridge.closeOwnedTab(requestID: requestID)
        }
    )
}

private struct SmartActivityReader: ClaudeLocalActivityReading {
    let now: Date

    func read(now _: Date) -> ClaudeLocalActivitySnapshot {
        ClaudeLocalActivitySnapshot(
            availability: .available,
            source: "sanitized-test-fixture",
            scope: "local",
            capturedAt: now,
            discoveredFileCount: 1,
            readableFileCount: 1,
            excludedFileCount: 0,
            tasks: [ClaudeLocalActivityTask(totalTokens: 1_234, modifiedAt: now)],
            apiEquivalentCost: ClaudeAPICostEstimate(
                sevenDayUSD: 0,
                lifetimeUSD: 0,
                pricedTokens: 1_234,
                observedTokens: 1_234,
                recognizedModelCount: 1,
                modelNames: ["Sonnet"]
            )
        )
    }
}

private actor ResetlessSafariAnchorStore: ClaudeSmartAnchorStoring {
    private var saved: [ClaudeSmartWindowAnchor] = []
    private var saveCount = 0

    func load() -> [ClaudeSmartWindowAnchor] { saved }

    func save(_ anchors: [ClaudeSmartWindowAnchor]) throws {
        saveCount += 1
        saved = anchors
    }

    func clear() {
        saved.removeAll()
    }

    func savedAnchorCount() -> Int { saved.count }
    func saveInvocationCount() -> Int { saveCount }
    func savedAnchors() -> [ClaudeSmartWindowAnchor] { saved }
}

private actor WriteOnlyAnchorStore: ClaudeSmartAnchorStoring {
    private var saveCount = 0

    func load() -> [ClaudeSmartWindowAnchor] { [] }

    func save(_: [ClaudeSmartWindowAnchor]) {
        saveCount += 1
    }

    func clear() {}

    func saveInvocationCount() -> Int { saveCount }
}

@MainActor
private final class MainActorAdmissionRefreshGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false

    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private final class ConfigurationFixture {
    let root: URL
    let paths: ClaudeStatusLineConfigurationPaths
    let relayCommand = "/Applications/UMA.app/Contents/Helpers/ClaudeStatusLineRelay --state safe"
    let manager: ClaudeStatusLineConfigurationManager
    let originalData: Data

    init(existingSettings: String) throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("uma-m5rmx-smart-config-\(UUID().uuidString)")
        let settingsURL = root
            .appendingPathComponent("home/.claude/settings.json")
        let integration = root.appendingPathComponent("app-support/ClaudeLocalSmartMode")
        paths = ClaudeStatusLineConfigurationPaths(
            settingsURL: settingsURL,
            integrationDirectoryURL: integration,
            backupURL: integration.appendingPathComponent("settings-before-uma.json"),
            metadataURL: integration.appendingPathComponent("restore-metadata.json"),
            stateURL: integration.appendingPathComponent("status-line.json")
        )
        originalData = Data(existingSettings.utf8)
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try originalData.write(to: settingsURL)
        manager = ClaudeStatusLineConfigurationManager(
            paths: paths,
            relayCommand: relayCommand
        )
    }

    func settingsObject() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: paths.settingsURL)
        ) as? [String: Any])
    }

    func writeSettings(_ value: [String: Any]) throws {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: paths.settingsURL, options: .atomic)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
