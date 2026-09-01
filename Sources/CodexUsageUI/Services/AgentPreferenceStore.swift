import Foundation

enum AgentPreferenceLoadResult: Equatable {
    case missing
    case loaded(AgentPreferencesEnvelope)
    case corrupt
    case futureSchema(Int)
}

@MainActor
final class AgentPreferenceStore {
    static let key = "uma.agent-preferences.v1"
    static let maximumRecordBytes = 64 * 1_024
    static let maximumProviderCount = 32

    enum LegacyKeys {
        static let showUsageSummary = "display.showUsageSummaryCard"
        static let showRecentTasks = "display.showRecentTasksCard"
        static let showAPICost = "display.showAPICostCard"
    }

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    private let preferences: ApplicationPreferences
    private(set) var writeCount = 0
    private(set) var loadResult: AgentPreferenceLoadResult
    private var cachedEnvelope: AgentPreferencesEnvelope?
    private var blocksWritesForUnreadableRecord = false

    convenience init(defaults: UserDefaults = .standard) {
        self.init(preferences: ApplicationPreferences(userDefaults: defaults))
    }

    init(preferences: ApplicationPreferences) {
        self.preferences = preferences
        let result = Self.read(from: preferences)
        loadResult = result
        switch result {
        case let .loaded(envelope):
            cachedEnvelope = envelope
        case .missing:
            cachedEnvelope = nil
        case .corrupt:
            cachedEnvelope = nil
            blocksWritesForUnreadableRecord = true
        case .futureSchema:
            cachedEnvelope = nil
            blocksWritesForUnreadableRecord = true
        }
    }

    func loadOrMigrateLegacyPreferences() -> AgentPreferencesEnvelope {
        if let cachedEnvelope {
            return cachedEnvelope
        }
        guard !blocksWritesForUnreadableRecord else {
            return AgentPreferencesEnvelope()
        }

        let migrated = migratedLegacyEnvelope()
        if migrated.records.isEmpty {
            cachedEnvelope = migrated
            return migrated
        }
        _ = save(migrated)
        return cachedEnvelope ?? migrated
    }

    @discardableResult
    func save(_ envelope: AgentPreferencesEnvelope) -> Bool {
        guard !blocksWritesForUnreadableRecord else { return false }
        var normalized = envelope
        normalized.normalize()
        guard Self.isValid(normalized),
              normalized != cachedEnvelope,
              let data = try? Self.encoder.encode(normalized),
              data.count <= Self.maximumRecordBytes
        else {
            return false
        }
        preferences.set(data, for: UMAApplicationPreferenceKeys.agentPreferences)
        cachedEnvelope = normalized
        loadResult = .loaded(normalized)
        writeCount += 1
        return true
    }

    private func migratedLegacyEnvelope() -> AgentPreferencesEnvelope {
        let summary = preferences.value(
            for: UMAApplicationPreferenceKeys.legacyShowUsageSummary
        )
        let tasks = preferences.value(
            for: UMAApplicationPreferenceKeys.legacyShowRecentTasks
        )
        let cost = preferences.value(
            for: UMAApplicationPreferenceKeys.legacyShowAPICost
        )
        guard summary != nil || tasks != nil || cost != nil else {
            return AgentPreferencesEnvelope()
        }

        let details = CodexDetailPreferences(
            showUsageSummary:
                summary ?? CodexDetailPreferences.defaults.showUsageSummary,
            showRecentTasks:
                tasks ?? CodexDetailPreferences.defaults.showRecentTasks,
            showAPICost:
                cost ?? CodexDetailPreferences.defaults.showAPICost
        )
        return AgentPreferencesEnvelope(
            records: [
                AgentPreferenceRecord(
                    providerID: AgentPreferenceRecord.codexProviderID,
                    providerSettings: AgentProviderSettingsPayload(
                        monitoring: AgentMonitoringPreferences(),
                        codexDetails: details
                    )
                )
            ]
        )
    }

    private static func read(
        from preferences: ApplicationPreferences
    ) -> AgentPreferenceLoadResult {
        guard let data = preferences.value(
            for: UMAApplicationPreferenceKeys.agentPreferences
        ) else { return .missing }
        guard data.count <= maximumRecordBytes,
              let header = try? decoder.decode(SchemaHeader.self, from: data)
        else {
            return .corrupt
        }
        guard header.schemaVersion <= AgentPreferencesEnvelope.currentSchemaVersion
        else {
            return .futureSchema(header.schemaVersion)
        }
        guard header.schemaVersion == AgentPreferencesEnvelope.currentSchemaVersion,
              let envelope = try? decoder.decode(
                AgentPreferencesEnvelope.self,
                from: data
              )
        else {
            return .corrupt
        }
        guard isValid(envelope) else { return .corrupt }
        return .loaded(envelope)
    }

    private static func isValid(_ envelope: AgentPreferencesEnvelope) -> Bool {
        guard envelope.schemaVersion
                == AgentPreferencesEnvelope.currentSchemaVersion,
              envelope.records.count <= maximumProviderCount
        else {
            return false
        }
        var seen = Set<AgentConnectorID>()
        for record in envelope.records {
            guard record.providerID
                    == AgentPreferenceRecord.canonicalProviderID(
                        for: record.providerID
                    ),
                  seen.insert(record.providerID).inserted,
                  record.sourceConfigurationVersion
                    == AgentPreferenceRecord.currentSourceConfigurationVersion,
                  record.hasNonDefaultSettings
                    == (
                        record.providerSettings
                            != .defaults(for: record.providerID)
                    ),
                  record.lastSafeDetectionAt?.timeIntervalSinceReferenceDate
                    .isFinite != false
            else {
                return false
            }
        }
        return true
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
