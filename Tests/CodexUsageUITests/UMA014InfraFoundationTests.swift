import Foundation
import Testing
import ClaudeBrowserBridgeProtocol
@testable import CodexUsageUI

@Suite("UMA014 Infra application foundation", .serialized)
@MainActor
struct UMA014InfraFoundationTests {
    @Test
    func typedPreferencesRoundTripDefaultsAndObservation() {
        let preferences = ApplicationPreferences.inMemory()
        var changes: [ApplicationPreferences.Change] = []
        let observation = preferences.observe { changes.append($0) }

        #expect(preferences.value(for: UMAApplicationPreferenceKeys.assistantEnabled))
        #expect(
            preferences.value(for: UMAApplicationPreferenceKeys.appearance)
                == UMAApplicationAppearance.system.rawValue
        )
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.menuBarShowsRemaining))
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.quickPanelShowsReset))
        #expect(
            preferences.value(for: UMAApplicationPreferenceKeys.assistantDensity)
                == DesktopAssistantDensity.automatic.rawValue
        )

        preferences.set(false, for: UMAApplicationPreferenceKeys.assistantEnabled)
        preferences.set(false, for: UMAApplicationPreferenceKeys.assistantEnabled)
        preferences.set(
            DesktopAssistantDensity.minimalist.rawValue,
            for: UMAApplicationPreferenceKeys.assistantDensity
        )

        #expect(!preferences.value(for: UMAApplicationPreferenceKeys.assistantEnabled))
        #expect(changes.map(\.key) == [
            DesktopAssistantPreferences.Keys.isEnabled,
            DesktopAssistantPreferences.Keys.density,
        ])
        #expect(changes.map(\.revision) == [1, 2])
        observation.cancel()
    }

    @Test
    func m4GlobalDisplayPreferencesRoundTripWithoutChangingLegacyDefaults() {
        let preferences = ApplicationPreferences.inMemory()
        preferences.set(
            UMAApplicationAppearance.light.rawValue,
            for: UMAApplicationPreferenceKeys.appearance
        )
        preferences.set(false, for: UMAApplicationPreferenceKeys.menuBarShowsRemaining)
        preferences.set(false, for: UMAApplicationPreferenceKeys.quickPanelShowsReset)

        #expect(
            UMAApplicationAppearance(
                rawValue: preferences.value(for: UMAApplicationPreferenceKeys.appearance)
            ) == .light
        )
        #expect(!preferences.value(for: UMAApplicationPreferenceKeys.menuBarShowsRemaining))
        #expect(!preferences.value(for: UMAApplicationPreferenceKeys.quickPanelShowsReset))
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.assistantEnabled))
    }

    @Test
    func languageAndAssistantPreserveLegacyKeysAndEncodings() throws {
        let legacyPosition = DesktopAssistantPosition(
            displayIdentifier: 7,
            horizontalFraction: 0.25,
            verticalFraction: 0.75
        )
        let encodedPosition = try JSONEncoder().encode(legacyPosition)
        let preferences = ApplicationPreferences.inMemory(seed: [
            AppLanguage.storageKey: AppLanguage.english.rawValue,
            DesktopAssistantPreferences.Keys.isEnabled: false,
            DesktopAssistantPreferences.Keys.isAlwaysOnTop: true,
            DesktopAssistantPreferences.Keys.density:
                DesktopAssistantDensity.minimalist.rawValue,
            DesktopAssistantPreferences.Keys.position: encodedPosition,
        ])

        #expect(
            AppLanguage.resolveAndPersist(
                preferences: preferences,
                preferredLanguages: ["zh-Hans"]
            ) == .english
        )
        let assistant = DesktopAssistantPreferences.load(from: preferences)
        #expect(!assistant.isEnabled)
        #expect(assistant.isAlwaysOnTop)
        #expect(assistant.density == .minimalist)
        #expect(assistant.position == legacyPosition)

        DesktopAssistantPreferences(
            isEnabled: true,
            isAlwaysOnTop: false,
            density: .regular,
            position: nil
        ).save(to: preferences)
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.assistantEnabled))
        #expect(!preferences.value(for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop))
        #expect(
            preferences.value(for: UMAApplicationPreferenceKeys.assistantDensity)
                == DesktopAssistantDensity.regular.rawValue
        )
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.assistantPosition) == nil)
    }

    @Test
    func agentLegacyMigrationIsAdditiveAndFutureSchemaFailsClosed() throws {
        let legacy = ApplicationPreferences.inMemory(seed: [
            AgentPreferenceStore.LegacyKeys.showUsageSummary: false,
            AgentPreferenceStore.LegacyKeys.showRecentTasks: true,
        ])
        let store = AgentPreferenceStore(preferences: legacy)
        let envelope = store.loadOrMigrateLegacyPreferences()
        let codex = try #require(
            envelope.record(for: AgentPreferenceRecord.codexProviderID)
        )
        let details = try #require(codex.providerSettings.codexDetails)
        #expect(!details.showUsageSummary)
        #expect(details.showRecentTasks)
        #expect(details.showAPICost == false)
        #expect(legacy.contains(UMAApplicationPreferenceKeys.agentPreferences))
        #expect(
            legacy.value(for: UMAApplicationPreferenceKeys.legacyShowRecentTasks)
                == true
        )

        let futureRecord = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 9_999,
            "records": [],
        ])
        let future = ApplicationPreferences.inMemory(seed: [
            AgentPreferenceStore.key: futureRecord,
        ])
        let futureStore = AgentPreferenceStore(preferences: future)
        #expect(futureStore.loadResult == .futureSchema(9_999))
        #expect(!futureStore.save(AgentPreferencesEnvelope()))
        #expect(
            future.value(for: UMAApplicationPreferenceKeys.agentPreferences)
                == futureRecord
        )
    }

    @Test
    func nilInternalPreferenceInputCannotWriteStandardDomain() {
        let standard = UserDefaults.standard
        let beforeLanguage = standard.object(forKey: AppLanguage.storageKey)
        let beforeAgent = standard.object(forKey: AgentPreferenceStore.key)
        let beforeAssistant = standard.object(
            forKey: DesktopAssistantPreferences.Keys.isEnabled
        )

        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: nil,
            primaryConnectorID: nil,
            consentDefaults: nil,
            preferences: nil,
            agentSettings: nil
        )
        store.setLanguage(.simplifiedChinese)
        store.agentSettings?.setAutoSearchEnabled(true)

        #expect(Self.objectsEqual(
            beforeLanguage,
            standard.object(forKey: AppLanguage.storageKey)
        ))
        #expect(Self.objectsEqual(
            beforeAgent,
            standard.object(forKey: AgentPreferenceStore.key)
        ))
        #expect(Self.objectsEqual(
            beforeAssistant,
            standard.object(forKey: DesktopAssistantPreferences.Keys.isEnabled)
        ))
    }

    @Test
    func isolatedSuiteIsExplicitAndNeverFallsBack() throws {
        #expect(throws: ApplicationPreferenceError.invalidSuiteName) {
            _ = try ApplicationPreferences.isolatedSuite(named: "")
        }
        let name = "com.silkrd.uma.tests.infra.\(UUID().uuidString)"
        let preferences = try ApplicationPreferences.isolatedSuite(named: name)
        #expect(preferences.persistenceIdentifier == name)
        #expect(!preferences.isEphemeral)
        preferences.set(
            AppLanguage.english.rawValue,
            for: UMAApplicationPreferenceKeys.language
        )
        #expect(
            preferences.value(for: UMAApplicationPreferenceKeys.language)
                == AppLanguage.english.rawValue
        )
    }

    @Test
    func isolatedRuntimeConstructionLeavesProductionDomainUntouched() throws {
        let productionDomain = "com.silkrd.uma"
        let standard = UserDefaults.standard
        let before = standard.persistentDomain(forName: productionDomain) ?? [:]
        let suiteName = "com.silkrd.uma.tests.runtime.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "uma014-infra-runtime-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let runtime = UsageMonitorRuntime.live(
            workBuddyStoreURL: root.appendingPathComponent("workbuddy.json"),
            snapshotStoreURL: root.appendingPathComponent("snapshots.json"),
            startProviders: false,
            preferenceDefaults: suite
        )

        #expect(runtime.preferences.persistenceIdentifier == nil)
        #expect(!suite.dictionaryRepresentation().isEmpty)
        let after = standard.persistentDomain(forName: productionDomain) ?? [:]
        #expect(NSDictionary(dictionary: before).isEqual(to: after))
    }

    @Test
    func versionAuthorityAndActivePackagerCannotDrift() throws {
        let root = Self.repositoryRoot
        let authority = root.appendingPathComponent(
            "Configuration/UMAProductVersion.plist"
        )
        let data = try Data(contentsOf: authority)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
        #expect(plist["SchemaVersion"] as? Int == 1)

        let development = try #require(plist["Development"] as? [String: Any])
        let frozen = try #require(plist["FrozenProduction"] as? [String: Any])
        let safari = try #require(plist["SafariCompatibility"] as? [String: Any])
        #expect(development["MarketingVersion"] as? String == "0.18.1")
        #expect(development["BundleIdentifier"] as? String == "com.silkrd.uma.dev.uma014")
        #expect(frozen["MarketingVersion"] as? String == "0.14.0")
        #expect(
            frozen["SourceCommit"] as? String
                == "db93a7419e1533e68595d449afde5545c41051f2"
        )
        #expect(safari["HostMarketingVersion"] as? String == "0.14.0")
        #expect(safari["CompanionMarketingVersion"] as? String == "1.4.0")
        #expect(safari["ProtocolVersion"] as? String == "2")
        #expect(
            safari["CompanionMarketingVersion"] as? String
                == ClaudeBrowserBridgeContract.safariExtensionVersion
        )
        #expect(
            safari["HostMarketingVersion"] as? String
                == frozen["MarketingVersion"] as? String
        )
        #expect(
            Int(safari["ProtocolVersion"] as? String ?? "")
                == ClaudeBrowserBridgeContract.schemaVersion
        )

        let reader = try String(
            contentsOf: root.appendingPathComponent(
                "script/read_uma_product_version.sh"
            ),
            encoding: .utf8
        )
        let packager = try String(
            contentsOf: root.appendingPathComponent(
                "script/package_uma014_m1_dev.sh"
            ),
            encoding: .utf8
        )
        #expect(reader.contains("UMA_VERSION_AUTHORITY_KEY_UNSUPPORTED"))
        #expect(packager.contains("Development.MarketingVersion"))
        #expect(packager.contains("Development.BundleIdentifier"))
        #expect(packager.contains("Development.DefaultBuildNumber"))
        #expect(packager.contains("UMA014_M1_BUILD_NUMBER"))
        #expect(packager.contains("UMA014_M1_PACKAGE_ROOT"))
        #expect(packager.contains("UMA014_APPLICATION_NAME"))
        #expect(packager.contains("UMA014_BUNDLE_IDENTIFIER"))
        #expect(!packager.contains("CFBundleShortVersionString -string \"0.14.0\""))

        let reviewPackager = try String(
            contentsOf: root.appendingPathComponent(
                "script/package_uma014_m3r_review.sh"
            ),
            encoding: .utf8
        )
        #expect(reviewPackager.contains("com.silkrd.uma.dev.uma014.surface-rebuild"))
        #expect(reviewPackager.contains("package_uma014_m1_dev.sh"))

        // The host is now built on its own, with its version passed in, so the
        // pins above are what tie a given AUV build to one host build.
        let hostPackager = try String(
            contentsOf: root.appendingPathComponent(
                "script/package_uma_safari_host_production.sh"
            ),
            encoding: .utf8
        )
        #expect(hostPackager.contains("--version) version="))
        #expect(!hostPackager.contains("readonly VERSION="))
        #expect(!hostPackager.contains("CodexUsageMonitor"))
    }

    @Test
    func strictVersionReaderReturnsOnlyAllowlistedAuthorityValues() throws {
        let script = Self.repositoryRoot.appendingPathComponent(
            "script/read_uma_product_version.sh"
        )
        #expect(try Self.run(script, "Development.MarketingVersion") == "0.18.1")
        #expect(try Self.run(script, "SafariCompatibility.ProtocolVersion") == "2")
        #expect(throws: VersionReaderFailure.self) {
            _ = try Self.run(script, "Development.Unknown")
        }
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func run(_ script: URL, _ key: String) throws -> String {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, key]
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw VersionReaderFailure() }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func objectsEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs as NSObject, rhs as NSObject): lhs == rhs
        default: false
        }
    }
}

private struct VersionReaderFailure: Error {}
