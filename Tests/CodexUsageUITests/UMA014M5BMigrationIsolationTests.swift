import Combine
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA014 M5-B migration and application isolation")
@MainActor
struct UMA014M5BMigrationIsolationTests {
    @Test
    func productionKeepsReleasedPathsWhileAllOtherIdentitiesAreIsolated() {
        let support = URL(fileURLWithPath: "/fixture/Library/Application Support", isDirectory: true)
        let home = URL(fileURLWithPath: "/fixture", isDirectory: true)
        let production = ApplicationDataPaths.current(
            bundleIdentifier: "com.silkrd.uma", applicationSupportDirectory: support, homeDirectory: home
        )
        #expect(production.rootURL == support.appendingPathComponent("CodexUsageMonitor", isDirectory: true))
        #expect(production.supportsProviderConfiguration)
        #expect(production.statusLinePaths.settingsURL.path == "/fixture/.claude/settings.json")
        #expect(production.snapshotURL.lastPathComponent == "connector-snapshots.json")
        #expect(production.codexLedgerURL.lastPathComponent == "token-cost-ledger.json")
        for identifier in ["com.silkrd.uma.dev.uma014", "com.silkrd.uma.test", "../unsafe", nil] as [String?] {
            let dev = ApplicationDataPaths.current(
                bundleIdentifier: identifier, applicationSupportDirectory: support, homeDirectory: home
            )
            #expect(!dev.supportsProviderConfiguration)
            #expect(dev.rootURL != production.rootURL)
            for path in [dev.snapshotURL, dev.browserCacheURL, dev.smartAnchorsURL, dev.codexLedgerURL,
                         dev.statusLinePaths.stateURL, dev.statusLinePaths.settingsURL,
                         dev.statusLinePaths.backupURL, dev.statusLinePaths.metadataURL] {
                #expect(path.path.hasPrefix(dev.rootURL.path + "/"))
                #expect(!path.path.hasPrefix(production.rootURL.path + "/"))
            }
        }
    }

    @Test
    func frozen013PreferenceShapeSurvives014EditAndRollbackDecode() throws {
        // The schema and field spellings come from frozen 0.13's
        // AgentPreferences.swift (f6dd617), independently encoded here.
        let frozen = Data(#"{"schemaVersion":1,"initialScanCompleted":true,"autoSearchEnabled":false,"autoSearchExplicitlySet":true,"records":[{"providerID":"codex","hasBeenDetected":true,"hasNonDefaultSettings":true,"sourceConfigurationVersion":1,"providerSettings":{"monitoring":{"monitoringEnabled":false},"codexDetails":{"showUsageSummary":false,"showRecentTasks":true,"showAPICost":false}},"lastSafeDetectionAt":1700000000000}]}"#.utf8)
        let legacyPosition = Data(#"{"displayIdentifier":7,"horizontalFraction":0.25,"verticalFraction":0.75}"#.utf8)
        let preferences = ApplicationPreferences.inMemory(seed: [
            "uma.agent-preferences.v1": frozen,
            "desktopAssistant.isEnabled": false,
            "desktopAssistant.isAlwaysOnTop": true,
            "desktopAssistant.density": "minimalist",
            "desktopAssistant.position": legacyPosition,
            "display.showRecentTasksCard": true,
            "unrelated.sentinel": "preserve",
        ])
        let store = AgentPreferenceStore(preferences: preferences)
        var value = store.loadOrMigrateLegacyPreferences()
        #expect(value.initialScanCompleted)
        #expect(!value.autoSearchEnabled)
        #expect(value.record(for: AgentPreferenceRecord.codexProviderID)?.providerSettings.monitoring.monitoringEnabled == false)
        value.autoSearchEnabled = true
        #expect(store.save(value))
        let encoded = try #require(preferences.value(for: UMAApplicationPreferenceKeys.agentPreferences))
        let rollback = try JSONDecoder().decode(Frozen013AgentEnvelope.self, from: encoded)
        #expect(rollback.schemaVersion == 1)
        #expect(rollback.autoSearchEnabled)
        #expect(rollback.records.first?.providerSettings.monitoring.monitoringEnabled == false)
        let desktop = DesktopAssistantPreferences.load(from: preferences)
        #expect(!desktop.isEnabled && desktop.isAlwaysOnTop && desktop.density == .minimalist)
        desktop.save(to: preferences)
        let rollbackPosition = try JSONDecoder().decode(Frozen013Position.self, from:
            #require(preferences.value(for: UMAApplicationPreferenceKeys.assistantPosition)))
        #expect(rollbackPosition.horizontalFraction == 0.25 && rollbackPosition.verticalFraction == 0.75)
        #expect(preferences.value(for: ApplicationPreferenceKey<String>("unrelated.sentinel", default: "")) == "preserve")
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.legacyShowRecentTasks) == true)
        #expect(!preferences.contains(UMAApplicationPreferenceKeys.refreshOnWake))
        #expect(!preferences.value(for: UMAApplicationPreferenceKeys.refreshOnWake))
        #expect(!preferences.value(for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh))
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose))
    }

    @Test(arguments: [Data("invalid".utf8), Data(#"{"schemaVersion":9999,"records":[]}"#.utf8)])
    func unreadablePreferenceBytesRemainUnmodified(data: Data) {
        let preferences = ApplicationPreferences.inMemory(seed: [AgentPreferenceStore.key: data])
        let store = AgentPreferenceStore(preferences: preferences)
        _ = store.loadOrMigrateLegacyPreferences()
        #expect(!store.save(AgentPreferencesEnvelope()))
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.agentPreferences) == data)
    }

    @Test
    func consentKeysAreNotImportedAcrossApplicationDomains() throws {
        let productionName = "com.silkrd.uma.tests.m5b.production.\(UUID().uuidString)"
        let devName = "com.silkrd.uma.tests.m5b.dev.\(UUID().uuidString)"
        let production = try #require(UserDefaults(suiteName: productionName))
        let dev = try #require(UserDefaults(suiteName: devName))
        defer {
            production.removePersistentDomain(forName: productionName)
            dev.removePersistentDomain(forName: devName)
        }
        CodexMonitorConsentDecision.granted.persist(to: production)
        ClaudeBrowserConsentStore(defaults: production).consentGranted = true
        dev.set(true, forKey: "ClaudeBrowserSyncConsent.v1")
        dev.set(true, forKey: "ClaudeBrowserSyncAutoRefresh.v1")
        dev.set(true, forKey: "ClaudeBrowserSyncAllowSafariLaunch.v1")
        let before = production.persistentDomain(forName: productionName) ?? [:]
        let devConsent = ClaudeBrowserConsentStore(defaults: dev)
        #expect(!devConsent.consentGranted)
        #expect(CodexMonitorConsentDecision.load(from: dev) == .unknown)
        devConsent.retirePersistentBrowserAutomation()
        #expect(!devConsent.autoRefreshEnabled && !devConsent.allowSafariLaunch)
        #expect(!dev.bool(forKey: "ClaudeBrowserSyncAutoRefresh.v1"))
        #expect(!dev.bool(forKey: "ClaudeBrowserSyncAllowSafariLaunch.v1"))
        #expect(ClaudeBrowserConsentStore(defaults: production).consentGranted)
        #expect(CodexMonitorConsentDecision.load(from: production) == .granted)
        #expect(NSDictionary(dictionary: before).isEqual(to: production.persistentDomain(forName: productionName) ?? [:]))
    }

    @Test
    func isolatedRuntimeAndActualSettingsClearPreserveProductionFixtures() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".uma014-m5b-isolation-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "com.silkrd.uma.tests.m5b.runtime.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer {
            suite.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let production = ApplicationDataPaths.current(bundleIdentifier: "com.silkrd.uma", applicationSupportDirectory: support, homeDirectory: root)
        let dev = ApplicationDataPaths.current(bundleIdentifier: "com.silkrd.uma.dev.uma014", applicationSupportDirectory: support, homeDirectory: root)
        let protectedPaths = [production.snapshotURL, production.browserCacheURL, production.smartAnchorsURL,
                              production.codexLedgerURL, production.statusLinePaths.settingsURL,
                              production.statusLinePaths.stateURL]
        for path in protectedPaths { try writeOwned(Data("production-fixture".utf8), to: path) }
        // Granted fixture consent exercises the old disabled-runtime escape.
        CodexMonitorConsentDecision.granted.persist(to: suite)
        ClaudeBrowserConsentStore(defaults: suite).consentGranted = true
        let runtime = UsageMonitorRuntime.live(startProviders: false, preferenceDefaults: suite, dataPaths: dev)
        #expect(runtime.dataPaths == dev)
        await runtime.store.waitForInitialObservation()
        #expect(runtime.store.providerSnapshots.isEmpty)
        #expect(runtime.store.agentSettings?.envelope.initialScanCompleted == false)
        try await AgentConnectorSnapshotStore(url: dev.snapshotURL).replace(with: [])
        try await ClaudeSmartAnchorStore(url: dev.smartAnchorsURL).save([])
        try APICostLedgerStore(url: dev.codexLedgerURL).save(APICostLedger())
        _ = try APICostLedgerStore(url: dev.codexLedgerURL).load()
        try writeOwned(Data("dev-cache-fixture".utf8), to: dev.browserCacheURL)
        let ledgerBefore = try Data(contentsOf: dev.codexLedgerURL)
        let model = GlobalSettingsViewModel(preferences: runtime.preferences, store: runtime.store, dataPaths: runtime.dataPaths)
        model.clearRetainedUsageData()
        await m5aWaitForPublished(model.$dataActionStatus) {
            $0 == "Retained local usage data cleared." || $0 == "已清除保留的本地用量数据。"
        }
        for path in [dev.snapshotURL, dev.browserCacheURL, dev.smartAnchorsURL] {
            #expect(!FileManager.default.fileExists(atPath: path.path))
        }
        // Cost-ledger retention is intentionally outside the three-cache clear action.
        #expect(try Data(contentsOf: dev.codexLedgerURL) == ledgerBefore)
        for path in protectedPaths { #expect(try Data(contentsOf: path) == Data("production-fixture".utf8)) }
        await runtime.shutdown()
    }

    @Test(arguments: ["snapshot", "ledger"])
    func firstWriterCreatesAnOwnerOnlyRootForClaudeAnchors(writer: String) async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".uma014-m5b-first-writer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ApplicationDataPaths.current(
            bundleIdentifier: "com.silkrd.uma.dev.uma014",
            applicationSupportDirectory: root, homeDirectory: root
        )
        if writer == "snapshot" {
            try await AgentConnectorSnapshotStore(url: paths.snapshotURL).replace(with: [])
        } else {
            try APICostLedgerStore(url: paths.codexLedgerURL).save(APICostLedger())
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: paths.rootURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        try await ClaudeSmartAnchorStore(url: paths.smartAnchorsURL).save([])
        #expect(FileManager.default.fileExists(atPath: paths.smartAnchorsURL.path))
    }

    @Test
    func legacy0755ApplicationRootRequiresExplicitMigrationAndPreservesRollbackData() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".uma014-m5b-legacy-root-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ApplicationDataPaths.current(
            bundleIdentifier: "com.silkrd.uma",
            applicationSupportDirectory: root, homeDirectory: root
        )
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let anchor = try #require(ClaudeSmartWindowAnchor(
            windowKind: .fiveHour, usedPercent: 25, resetsAt: now.addingTimeInterval(3600),
            observedAt: now, activityTotalTokens: 1000, source: .exactLocalStatusLine,
            modelFamilyKey: "sonnet", sourceSchema: "status-1", continuityGeneration: 0
        ))
        let generic = ClaudeSmartAnchorStore(url: paths.smartAnchorsURL, now: { now })
        try await generic.save([anchor])
        try APICostLedgerStore(url: paths.codexLedgerURL).save(APICostLedger())
        let anchorBefore = try Data(contentsOf: paths.smartAnchorsURL)
        let ledgerBefore = try Data(contentsOf: paths.codexLedgerURL)
        // Reproduce the released snapshot/ledger first-writer directory mode.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.rootURL.path)
        #expect(await generic.load().isEmpty)
        await #expect(throws: ClaudeSmartAnchorStore.StoreError.unsafePath) {
            try await generic.save([anchor])
        }
        #expect((try FileManager.default.attributesOfItem(atPath: paths.rootURL.path)[.posixPermissions] as? NSNumber)?.intValue == 0o755)
        let applicationOwned = ClaudeSmartAnchorStore(
            url: paths.smartAnchorsURL, now: { now }, allowsOwnedDirectoryPermissionMigration: true
        )
        #expect(await applicationOwned.load() == [anchor])
        #expect((try FileManager.default.attributesOfItem(atPath: paths.rootURL.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(try Data(contentsOf: paths.smartAnchorsURL) == anchorBefore)
        try await applicationOwned.save([anchor])
        #expect(try Data(contentsOf: paths.codexLedgerURL) == ledgerBefore)
        // 0.13 has the same schema2 decoder and owner-only validation; the
        // generic reader still accepts the exact retained record after upgrade.
        #expect(await generic.load() == [anchor])
        _ = try APICostLedgerStore(url: paths.codexLedgerURL).load()
    }

    @Test
    func directoryMigrationRejectsSymlinkWithoutChangingTargetPermissions() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".uma014-m5b-migration-link-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let sentinel = target.appendingPathComponent("sentinel")
        try Data("preserved".utf8).write(to: sentinel)
        let link = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = ClaudeSmartAnchorStore(
            url: link.appendingPathComponent("anchors.json"),
            allowsOwnedDirectoryPermissionMigration: true
        )
        #expect(await store.load().isEmpty)
        await #expect(throws: ClaudeSmartAnchorStore.StoreError.unsafePath) {
            try await store.save([])
        }
        #expect((try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue == 0o755)
        #expect(try Data(contentsOf: sentinel) == Data("preserved".utf8))
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("anchors.json").path))
    }

    private func writeOwned(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

private struct Frozen013AgentEnvelope: Decodable {
    let schemaVersion: Int
    let initialScanCompleted: Bool
    let autoSearchEnabled: Bool
    let autoSearchExplicitlySet: Bool
    let records: [Record]
    struct Record: Decodable {
        let providerID: String
        let hasBeenDetected: Bool
        let hasNonDefaultSettings: Bool
        let sourceConfigurationVersion: Int
        let lastSafeDetectionAt: Double?
        let providerSettings: Settings
    }
    struct Settings: Decodable {
        let monitoring: Monitoring
        let codexDetails: Details?
    }
    struct Monitoring: Decodable { let monitoringEnabled: Bool }
    struct Details: Decodable {
        let showUsageSummary: Bool
        let showRecentTasks: Bool
        let showAPICost: Bool
    }
}
private struct Frozen013Position: Decodable {
    let displayIdentifier: UInt32?
    let horizontalFraction: Double
    let verticalFraction: Double
}
