import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.11-G1 Agent preferences and compact Settings")
struct UMA011G1AgentPreferencesTests {
    @MainActor
    @Test("Legacy Codex visibility migrates once without resetting values")
    func legacyMigrationIsIdempotent() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            false,
            forKey: AgentPreferenceStore.LegacyKeys.showUsageSummary
        )
        defaults.set(
            true,
            forKey: AgentPreferenceStore.LegacyKeys.showRecentTasks
        )
        defaults.set(
            true,
            forKey: AgentPreferenceStore.LegacyKeys.showAPICost
        )

        let store = AgentPreferenceStore(defaults: defaults)
        let first = store.loadOrMigrateLegacyPreferences()
        let second = store.loadOrMigrateLegacyPreferences()
        let codex = try #require(
            first.record(for: AgentPreferenceRecord.codexProviderID)
        )

        #expect(first == second)
        #expect(store.writeCount == 1)
        #expect(codex.hasBeenDetected == false)
        #expect(codex.hasNonDefaultSettings)
        #expect(codex.providerSettings.codexDetails?.showUsageSummary == false)
        #expect(codex.providerSettings.codexDetails?.showRecentTasks == true)
        #expect(codex.providerSettings.codexDetails?.showAPICost == true)
        #expect(
            defaults.bool(
                forKey: AgentPreferenceStore.LegacyKeys.showRecentTasks
            )
        )

        let relaunched = AgentPreferenceStore(defaults: defaults)
        #expect(relaunched.loadOrMigrateLegacyPreferences() == first)
        #expect(relaunched.writeCount == 0)
    }

    @MainActor
    @Test("Canonical records are sorted, deduplicated, and semantically stable")
    func canonicalDeterministicEnvelope() throws {
        let codexConnector = try #require(
            AgentConnectorID(rawValue: "codex.liveUsage")
        )
        let workBuddyManual = try #require(
            AgentConnectorID(rawValue: "workbuddy.manualAvailability")
        )
        let workBuddyWeb = try #require(
            AgentConnectorID(rawValue: "workbuddy.accountWebCredits")
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var envelope = AgentPreferencesEnvelope(
            records: [
                AgentPreferenceRecord(
                    providerID: workBuddyManual,
                    hasBeenDetected: true,
                    lastSafeDetectionAt: now
                ),
                AgentPreferenceRecord(providerID: codexConnector),
                AgentPreferenceRecord(
                    providerID: workBuddyWeb,
                    providerSettings: AgentProviderSettingsPayload(
                        monitoring: AgentMonitoringPreferences(
                            monitoringEnabled: false
                        )
                    )
                ),
            ]
        )
        envelope.normalize()

        #expect(envelope.records.map(\.providerID.rawValue) == [
            "codex", "workbuddy",
        ])
        let workBuddy = try #require(
            envelope.record(for: workBuddyWeb)
        )
        #expect(workBuddy.hasBeenDetected)
        #expect(workBuddy.lastSafeDetectionAt == now)
        #expect(!workBuddy.providerSettings.monitoring.monitoringEnabled)
        #expect(workBuddy.hasNonDefaultSettings)
    }

    @MainActor
    @Test("No-op writes are suppressed and settings survive inactivity")
    func restartPersistenceAndNoOpWrites() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgentPreferenceStore(defaults: defaults)
        let coordinator = AgentSettingsCoordinator(store: store)
        let workBuddyConnector = try #require(
            AgentConnectorID(rawValue: "workbuddy.accountWebCredits")
        )
        let detectedAt = Date(timeIntervalSince1970: 2_000_000_000)

        coordinator.completeFirstManualScan(
            detectedConnectorIDs: [workBuddyConnector],
            detectedAt: detectedAt
        )
        coordinator.setMonitoringEnabled(
            false,
            for: workBuddyConnector
        )
        let writes = store.writeCount
        coordinator.setMonitoringEnabled(
            false,
            for: workBuddyConnector
        )
        coordinator.recordSafeDetections(
            [workBuddyConnector],
            detectedAt: detectedAt
        )

        #expect(store.writeCount == writes)
        #expect(coordinator.initialScanCompleted)
        #expect(coordinator.autoSearchEnabled)
        #expect(coordinator.shouldAutoSearchAtLaunch)

        let restored = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: defaults)
        )
        restored.setActiveConnectorIDs([])
        let entry = try #require(
            restored.entries.first { $0.providerID.rawValue == "workbuddy" }
        )
        #expect(entry.hasBeenDetected)
        #expect(!entry.isActive)
        #expect(entry.hasNonDefaultSettings)
        #expect(!restored.isMonitoringEnabled(for: workBuddyConnector))
    }

    @MainActor
    @Test("Explicit onboarding OFF is retained after first manual scan")
    func explicitAutoSearchChoiceWins() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgentPreferenceStore(defaults: defaults)
        let coordinator = AgentSettingsCoordinator(store: store)

        #expect(!coordinator.initialScanCompleted)
        #expect(!coordinator.shouldAutoSearchAtLaunch)
        coordinator.setAutoSearchEnabled(false)
        coordinator.completeFirstManualScan(
            detectedConnectorIDs: [],
            detectedAt: Date()
        )

        #expect(coordinator.initialScanCompleted)
        #expect(!coordinator.autoSearchEnabled)
        #expect(!coordinator.shouldAutoSearchAtLaunch)
        #expect(
            AgentSettingsCoordinator(
                store: AgentPreferenceStore(defaults: defaults)
            ).autoSearchEnabled == false
        )
    }

    @MainActor
    @Test("Corrupt, oversized, and future records fail closed without rewrite")
    func invalidRecordsFailClosed() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            Data("{not-json".utf8),
            forKey: AgentPreferenceStore.key
        )
        let corrupt = AgentPreferenceStore(defaults: defaults)
        #expect(corrupt.loadResult == .corrupt)
        #expect(!corrupt.loadOrMigrateLegacyPreferences().initialScanCompleted)
        #expect(!corrupt.save(AgentPreferencesEnvelope()))
        #expect(
            defaults.data(forKey: AgentPreferenceStore.key)
                == Data("{not-json".utf8)
        )

        let oversizedData = Data(
            repeating: 0x41,
            count: AgentPreferenceStore.maximumRecordBytes + 1
        )
        defaults.set(oversizedData, forKey: AgentPreferenceStore.key)
        let oversized = AgentPreferenceStore(defaults: defaults)
        #expect(oversized.loadResult == .corrupt)
        #expect(!oversized.save(AgentPreferencesEnvelope()))
        #expect(
            defaults.data(forKey: AgentPreferenceStore.key)
                == oversizedData
        )

        let futureData = try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion":
                    AgentPreferencesEnvelope.currentSchemaVersion + 1,
                "initialScanCompleted": true,
                "autoSearchEnabled": true,
                "autoSearchExplicitlySet": true,
                "records": [],
            ],
            options: [.sortedKeys]
        )
        defaults.set(futureData, forKey: AgentPreferenceStore.key)
        let future = AgentPreferenceStore(defaults: defaults)
        #expect(
            future.loadResult
                == .futureSchema(
                    AgentPreferencesEnvelope.currentSchemaVersion + 1
                )
        )
        #expect(!future.save(AgentPreferencesEnvelope()))
        #expect(defaults.data(forKey: AgentPreferenceStore.key) == futureData)
    }

    @MainActor
    @Test("Provider count, record size, and privacy boundaries are enforced")
    func boundsAndPrivacy() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgentPreferenceStore(defaults: defaults)
        let records = try (0...AgentPreferenceStore.maximumProviderCount)
            .map { index in
                AgentPreferenceRecord(
                    providerID: try #require(
                        AgentConnectorID(rawValue: "provider\(index)")
                    )
                )
            }
        #expect(
            !store.save(AgentPreferencesEnvelope(records: records))
        )

        let coordinator = AgentSettingsCoordinator(store: store)
        coordinator.setMonitoringEnabled(
            false,
            for: AgentPreferenceRecord.workBuddyProviderID
        )
        let data = try #require(
            defaults.data(forKey: AgentPreferenceStore.key)
        )
        #expect(data.count <= AgentPreferenceStore.maximumRecordBytes)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in [
            "credential", "cookie", "authorizationheader", "localstorage",
            "sessionstorage", "token", "creditbalance", "email",
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @MainActor
    @Test("WorkBuddy session, refresh, login, and manual owners remain separate")
    func workBuddyStoresRemainSeparate() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = Data("isolated-consent-marker".utf8)
        let login = Data("isolated-login-marker".utf8)
        defaults.set(
            consent,
            forKey: "workbuddy.accountWebSync.consent.v1"
        )
        defaults.set(
            false,
            forKey:
                WorkBuddyAccountWebSessionController.autoRefreshEnabledKey
        )
        defaults.set(login, forKey: WorkBuddyLoginPersistenceStore.key)

        let coordinator = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: defaults)
        )
        coordinator.setMonitoringEnabled(
            false,
            for: AgentPreferenceRecord.workBuddyProviderID
        )

        #expect(
            defaults.data(
                forKey: "workbuddy.accountWebSync.consent.v1"
            ) == consent
        )
        #expect(
            defaults.bool(
                forKey:
                    WorkBuddyAccountWebSessionController
                        .autoRefreshEnabledKey
            ) == false
        )
        #expect(
            defaults.data(forKey: WorkBuddyLoginPersistenceStore.key)
                == login
        )
    }

    @Test("Settings keeps one scroll owner and routes provider controls on demand")
    func settingsSourceContract() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
            ),
            encoding: .utf8
        )
        #expect(source.occurrenceCount(of: "ScrollView(.vertical)") == 1)
        #expect(source.contains("case agent(String)"))
        #expect(source.contains("AgentSettingsList"))
        #expect(source.contains("AgentSpecificSettingsContent"))
        #expect(source.contains("AgentDiscoverySettingsSection"))
        #expect(source.contains("language.notCurrentlyRunning"))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "uma-011-g1-agent-prefs-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
