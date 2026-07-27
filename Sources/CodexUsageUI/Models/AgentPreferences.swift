import Foundation

/// A deliberately small provider-safe payload. Provider authentication,
/// account values, browser state, and manual records have separate owners and
/// are never represented here.
struct AgentMonitoringPreferences: Codable, Equatable, Sendable {
    var monitoringEnabled: Bool

    init(monitoringEnabled: Bool = true) {
        self.monitoringEnabled = monitoringEnabled
    }
}

struct CodexDetailPreferences: Codable, Equatable, Sendable {
    var showUsageSummary: Bool
    var showRecentTasks: Bool
    var showAPICost: Bool

    static let defaults = Self(
        showUsageSummary: true,
        showRecentTasks: false,
        showAPICost: false
    )
}

struct AgentProviderSettingsPayload: Codable, Equatable, Sendable {
    var monitoring = AgentMonitoringPreferences()
    var codexDetails: CodexDetailPreferences?

    static func defaults(for providerID: AgentConnectorID) -> Self {
        Self(
            monitoring: AgentMonitoringPreferences(),
            codexDetails: providerID == AgentPreferenceRecord.codexProviderID
                ? .defaults
                : nil
        )
    }
}

struct AgentPreferenceRecord: Codable, Equatable, Identifiable, Sendable {
    static let currentSourceConfigurationVersion = 1
    static let codexProviderID = AgentConnectorID(rawValue: "codex")!
    static let workBuddyProviderID = AgentConnectorID(rawValue: "workbuddy")!

    let providerID: AgentConnectorID
    var hasBeenDetected: Bool
    var hasNonDefaultSettings: Bool
    var sourceConfigurationVersion: Int
    var providerSettings: AgentProviderSettingsPayload
    var lastSafeDetectionAt: Date?

    var id: String { providerID.rawValue }

    init(
        providerID: AgentConnectorID,
        hasBeenDetected: Bool = false,
        sourceConfigurationVersion: Int = currentSourceConfigurationVersion,
        providerSettings: AgentProviderSettingsPayload? = nil,
        lastSafeDetectionAt: Date? = nil
    ) {
        let canonicalID = Self.canonicalProviderID(for: providerID)
        let settings = providerSettings ?? .defaults(for: canonicalID)
        self.providerID = canonicalID
        self.hasBeenDetected = hasBeenDetected
        self.hasNonDefaultSettings =
            settings != .defaults(for: canonicalID)
        self.sourceConfigurationVersion = sourceConfigurationVersion
        self.providerSettings = settings
        self.lastSafeDetectionAt = lastSafeDetectionAt
    }

    static func canonicalProviderID(
        for connectorID: AgentConnectorID
    ) -> AgentConnectorID {
        let namespace = connectorID.rawValue.split(
            separator: ".",
            maxSplits: 1
        ).first.map(String.init) ?? connectorID.rawValue
        return AgentConnectorID(rawValue: namespace) ?? connectorID
    }

    mutating func normalize() {
        hasNonDefaultSettings =
            providerSettings != .defaults(for: providerID)
    }
}

struct AgentPreferencesEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var initialScanCompleted: Bool
    var autoSearchEnabled: Bool
    var autoSearchExplicitlySet: Bool
    var records: [AgentPreferenceRecord]

    init(
        schemaVersion: Int = currentSchemaVersion,
        initialScanCompleted: Bool = false,
        autoSearchEnabled: Bool = true,
        autoSearchExplicitlySet: Bool = false,
        records: [AgentPreferenceRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.initialScanCompleted = initialScanCompleted
        self.autoSearchEnabled = autoSearchEnabled
        self.autoSearchExplicitlySet = autoSearchExplicitlySet
        self.records = records
        normalize()
    }

    mutating func normalize() {
        var canonicalRecords: [AgentConnectorID: AgentPreferenceRecord] = [:]
        for record in records {
            let canonicalID = AgentPreferenceRecord.canonicalProviderID(
                for: record.providerID
            )
            var normalized = AgentPreferenceRecord(
                providerID: canonicalID,
                hasBeenDetected: record.hasBeenDetected,
                sourceConfigurationVersion:
                    record.sourceConfigurationVersion,
                providerSettings: record.providerSettings,
                lastSafeDetectionAt: record.lastSafeDetectionAt
            )
            normalized.normalize()
            if let prior = canonicalRecords[canonicalID] {
                normalized.hasBeenDetected =
                    prior.hasBeenDetected || normalized.hasBeenDetected
                normalized.lastSafeDetectionAt = [
                    prior.lastSafeDetectionAt,
                    normalized.lastSafeDetectionAt,
                ].compactMap { $0 }.max()
                if normalized.providerSettings
                    == .defaults(for: canonicalID),
                   prior.providerSettings != .defaults(for: canonicalID) {
                    normalized.providerSettings = prior.providerSettings
                }
                normalized.normalize()
            }
            canonicalRecords[canonicalID] = normalized
        }
        records = canonicalRecords.values.sorted {
            AgentProviderOrder.precedes($0.providerID, $1.providerID)
        }
    }

    func record(for connectorID: AgentConnectorID) -> AgentPreferenceRecord? {
        let canonicalID = AgentPreferenceRecord.canonicalProviderID(
            for: connectorID
        )
        return records.first { $0.providerID == canonicalID }
    }
}
