import ClaudeBrowserBridgeProtocol
import ClaudeSafariHostIPC
import ClaudeStatusLineCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA014 M5-B isolated installation compatibility", .timeLimit(.minutes(1)))
struct UMA014M5BInstallCompatibilityTests {
    @Test(arguments: [ClaudeStatusLineConfigurationIssue.requiresInstalledApp, .developmentIsolation])
    @MainActor
    func unavailableStatusLineRefusesConsentAndRepair(_ issue: ClaudeStatusLineConfigurationIssue) async throws {
        let suite = "UMA014M5B-helper-refusal-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let model = ClaudeBrowserSettingsModel(connector: connector, consentStore: consent,
            statusLineConfigurationIssue: issue)
        let before = await connector.diagnostics()
        model.connectWithConsent()
        model.repairCompanion()
        #expect(!consent.consentGranted)
        #expect(!model.hasLocalSmartConsent)
        #expect(!model.actionInProgress)
        #expect(!model.canConnectLocalSmartMode)
        #expect(!model.canRepairStatusLineConfiguration)
        #expect(model.agentControlState == .statusLineConfigurationUnavailable(issue))
        #expect((await connector.diagnostics()).desktopPlanUsageReadCount == before.desktopPlanUsageReadCount)
        #expect(await fixture.bridge.startCount == 0)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
    }

    @Test @MainActor
    func statusLineLimitationPreservesDesktopConsentAndIndependentAccuracy() async throws {
        let suite = "UMA014M5B-helper-desktop-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = ClaudeBrowserConsentStore(defaults: defaults)
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let model = ClaudeBrowserSettingsModel(connector: connector, consentStore: consent,
            statusLineConfigurationIssue: .requiresInstalledApp, permitsDesktopLocalSmart: true)
        #expect(model.canConnectLocalSmartMode)
        #expect(!model.canRepairStatusLineConfiguration)
        model.connectWithConsent()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        #expect(consent.consentGranted)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        model.accuracySync()
        try await fixture.bridge.waitForAutomaticRequest()
        #expect(await fixture.bridge.automaticRequests.count == 1)
        await connector.stop()
    }

    @Test
    func movedAppNeedsExplicitRepairAndRestoresPriorSettings() throws {
        let fixture = try InstallFixture()
        defer { fixture.cleanup() }
        let first = try fixture.app("UMA old.app")
        let second = fixture.applications.appendingPathComponent("UMA new's copy.app")
        let paths = fixture.paths
        try FileManager.default.createDirectory(at: paths.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original: [String: Any] = [
            "theme": "dark", "statusLine": ["type": "command", "command": "prior-status --compact", "padding": 2],
            "hooks": ["Stop": [["matcher": "human", "hooks": [["type": "command", "command": "human-stop"]]]]],
        ]
        try fixture.write(original)
        let firstRelay = try #require(BundledClaudeRelay.executableURL(bundleURL: first, installedApplicationRoots: [fixture.applications]))
        let firstManager = ClaudeStatusLineConfigurationManager(paths: paths, relayCommand: BundledClaudeRelay.command(executableURL: firstRelay, paths: paths))
        try firstManager.enable()
        let backup = try Data(contentsOf: paths.backupURL)

        // Simulate installation at a new stable path and removal of the old app.
        try FileManager.default.moveItem(at: first, to: second)
        let secondRelay = try #require(BundledClaudeRelay.executableURL(bundleURL: second, installedApplicationRoots: [fixture.applications]))
        let command = BundledClaudeRelay.command(executableURL: secondRelay, paths: paths)
        let secondManager = ClaudeStatusLineConfigurationManager(paths: paths, relayCommand: command)
        var settings = try fixture.read()
        settings["theme"] = "light"
        try fixture.write(settings)
        let beforeCheck = try Data(contentsOf: paths.settingsURL)
        #expect(secondManager.check().state == .repairRequired)
        #expect(try Data(contentsOf: paths.settingsURL) == beforeCheck)
        try secondManager.repair()
        #expect(secondManager.check().state == .installed)
        #expect(try Data(contentsOf: paths.backupURL) == backup)
        #expect(!FileManager.default.fileExists(atPath: first.path))

        // Execute only the task-owned content-free fixture helper through the
        // exact persisted shell command to verify spaces/apostrophes and args.
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
            == ["--state", paths.stateURL.path, "--prior-status-line", paths.backupURL.path])
        try secondManager.restore()
        let restored = try fixture.read()
        #expect(restored["theme"] as? String == "light")
        #expect((restored["statusLine"] as? [String: Any])?["command"] as? String == "prior-status --compact")
        #expect(try JSONSerialization.data(withJSONObject: restored["hooks"]!, options: [.sortedKeys])
            == JSONSerialization.data(withJSONObject: original["hooks"]!, options: [.sortedKeys]))
        #expect(!FileManager.default.fileExists(atPath: paths.metadataURL.path))
    }

    @Test
    func transientMissingAndEscapingHelpersAreRefusedWithoutWrites() throws {
        let fixture = try InstallFixture()
        defer { fixture.cleanup() }
        let app = try fixture.app("UMA.app")
        let helper = app.appendingPathComponent("Contents/Helpers/ClaudeStatusLineRelay")
        #expect(BundledClaudeRelay.executableURL(bundleURL: app) == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: helper.path)
        #expect(BundledClaudeRelay.executableURL(bundleURL: app, installedApplicationRoots: [fixture.applications]) == nil)
        try FileManager.default.removeItem(at: helper)
        #expect(BundledClaudeRelay.executableURL(bundleURL: app, installedApplicationRoots: [fixture.applications]) == nil)
        let external = fixture.root.appendingPathComponent("outside-helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: external)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: external.path)
        try FileManager.default.createSymbolicLink(at: helper, withDestinationURL: external)
        #expect(BundledClaudeRelay.executableURL(bundleURL: app, installedApplicationRoots: [fixture.applications]) == nil)
        for component in ["AppTranslocation", "Worktrees", ".build", "Build", "DerivedData"] {
            let root = fixture.root.appendingPathComponent(component)
            let transient = try fixture.app("UMA.app", under: root)
            #expect(BundledClaudeRelay.executableURL(bundleURL: transient, installedApplicationRoots: [root]) == nil)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.settingsURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.metadataURL.path))
    }

    @Test
    func mutable014AcceptsImmutable013HostAndRejectsMixedMetadata() throws {
        let fixture = try InstallFixture()
        defer { fixture.cleanup() }
        let generation = "6f345b28-783f-4e85-b424-3e1c883f8fcb"
        var info: [String: Any] = [
            "CFBundleIdentifier": "com.silkrd.uma", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.14.0", "CFBundleVersion": "202609040001",
            "UMASafariHostBundleIdentifier": "com.silkrd.uma.safarihost",
            "UMASafariHostExtensionBundleIdentifier": "com.silkrd.uma.ClaudeBrowserCompanion",
            "UMAAppGroupIdentifier": "group.com.silkrd.uma.bridge",
            "UMASafariHostRuntimeGenerationID": generation,
            "UMASafariHostExtensionVersion": "0.13.0", "UMASafariHostExtensionBuild": "202608300146",
        ]
        func context(_ info: [String: Any]) throws -> ClaudeBrowserRuntimeContext? {
            let app = try fixture.app("Metadata-\(UUID().uuidString).app")
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            return ClaudeBrowserRuntimeContext.current(bundle: try #require(Bundle(url: app)))
        }
        let acceptedContext = try context(info)
        let accepted = try #require(acceptedContext)
        #expect(accepted.appVersion == "0.14.0")
        #expect(accepted.extensionVersion == "0.13.0")
        #expect(accepted.runtimeGenerationID == generation)
        let descriptor = ClaudeSafariHostIPCRuntimeDescriptor(
            hostApplicationIdentifier: accepted.identity.containingApplicationIdentifier,
            extensionIdentifier: accepted.identity.extensionIdentifier,
            teamIdentifier: accepted.teamIdentifier, hostVersion: "0.13.0", hostBuild: "202608300146",
            runtimeGenerationID: generation, bridgeProtocolVersion: 2)
        #expect(descriptor.isStructurallyValid)
        for (key, value) in [
            ("UMASafariHostBundleIdentifier", "com.silkrd.uma.test.safarihost"),
            ("UMAAppGroupIdentifier", "group.com.silkrd.uma.test.bridge"),
            ("UMASafariHostRuntimeGenerationID", "invalid-generation"),
            ("CFBundleIdentifier", "com.silkrd.uma.dev.fixture"),
        ] {
            var mixed = info
            mixed[key] = value
            #expect(try context(mixed) == nil)
        }
        let event = ClaudeBrowserAutomationEvent(
            requestID: UUID().uuidString, status: .bridgeReady, occurredAt: "2026-09-04T00:00:00Z",
            companionVersion: "0.13.0", companionBuild: "202608300146", protocolSchemaVersion: 2,
            containingApplicationIdentifier: descriptor.hostApplicationIdentifier,
            extensionIdentifier: descriptor.extensionIdentifier, teamIdentifier: descriptor.teamIdentifier,
            runtimeGenerationID: generation)
        #expect(accepted.matches(event))
        info["UMASafariHostRuntimeGenerationID"] = UUID().uuidString
        #expect(try context(info)?.matches(event) == false)
    }
}

private struct InstallFixture {
    let root: URL
    let configurationRoot: URL
    let applications: URL
    let paths: ClaudeStatusLineConfigurationPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("UMA014M5B-helper-\(UUID().uuidString)").resolvingSymlinksInPath()
        // The configuration manager rejects symlink ancestors. macOS temporary
        // directory aliases are unsuitable for that fixture; keep its synthetic
        // user files on the checkout's real filesystem, as existing manager
        // tests do. App relocation itself remains isolated in temporary space.
        configurationRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".uma014-m5b-config-\(UUID().uuidString)")
        applications = root.appendingPathComponent("User's Applications")
        paths = ClaudeStatusLineConfigurationPaths(homeDirectory: configurationRoot.appendingPathComponent("home"), applicationSupportDirectory: configurationRoot.appendingPathComponent("Support"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func app(_ name: String, under parent: URL? = nil) throws -> URL {
        let app = (parent ?? applications).appendingPathComponent(name)
        let helper = app.appendingPathComponent("Contents/Helpers/ClaudeStatusLineRelay")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\"\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        return app
    }

    func write(_ object: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: paths.settingsURL)
    }

    func read() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: paths.settingsURL)) as? [String: Any])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: configurationRoot)
    }
}
