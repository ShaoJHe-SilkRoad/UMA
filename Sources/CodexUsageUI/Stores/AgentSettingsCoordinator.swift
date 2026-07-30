import Combine
import Foundation

struct AgentSettingsEntry: Equatable, Identifiable, Sendable {
    let providerID: AgentConnectorID
    let displayName: String
    let hasBeenDetected: Bool
    let isActive: Bool
    let requiresSetup: Bool
    let hasNonDefaultSettings: Bool

    var id: String { providerID.rawValue }
}

@MainActor
final class AgentSettingsCoordinator: ObservableObject {
    @Published private(set) var envelope: AgentPreferencesEnvelope
    @Published private(set) var activeProviderIDs: Set<AgentConnectorID> = []
    @Published private(set) var setupRequiredProviderIDs:
        Set<AgentConnectorID> = []

    private let store: AgentPreferenceStore
    private let shippedProviders: [(AgentConnectorID, String)]

    init(
        store: AgentPreferenceStore = AgentPreferenceStore(),
        shippedProviders: [(AgentConnectorID, String)] = [
            (AgentPreferenceRecord.codexProviderID, "Codex"),
            (AgentPreferenceRecord.claudeProviderID, "Claude Code"),
            (AgentPreferenceRecord.workBuddyProviderID, "WorkBuddy"),
        ]
    ) {
        self.store = store
        self.shippedProviders = shippedProviders
        envelope = store.loadOrMigrateLegacyPreferences()
    }

    var initialScanCompleted: Bool { envelope.initialScanCompleted }
    var autoSearchEnabled: Bool { envelope.autoSearchEnabled }
    var shouldAutoSearchAtLaunch: Bool {
        envelope.initialScanCompleted && envelope.autoSearchEnabled
    }

    var entries: [AgentSettingsEntry] {
        var names = Dictionary(
            uniqueKeysWithValues: shippedProviders
        )
        for record in envelope.records where names[record.providerID] == nil {
            names[record.providerID] = Self.fallbackName(
                for: record.providerID
            )
        }
        return names.map { providerID, displayName in
            let record = envelope.record(for: providerID)
            return AgentSettingsEntry(
                providerID: providerID,
                displayName: displayName,
                hasBeenDetected: record?.hasBeenDetected ?? false,
                isActive: activeProviderIDs.contains(providerID),
                requiresSetup:
                    setupRequiredProviderIDs.contains(providerID),
                hasNonDefaultSettings:
                    record?.hasNonDefaultSettings ?? false
            )
        }.sorted {
            AgentProviderOrder.precedes($0.providerID, $1.providerID)
        }
    }

    func record(for providerID: AgentConnectorID) -> AgentPreferenceRecord {
        envelope.record(for: providerID)
            ?? AgentPreferenceRecord(providerID: providerID)
    }

    func isMonitoringEnabled(for connectorID: AgentConnectorID) -> Bool {
        record(for: connectorID)
            .providerSettings.monitoring.monitoringEnabled
    }

    func disabledConnectorIDs(
        from connectorIDs: [AgentConnectorID]
    ) -> Set<AgentConnectorID> {
        Set(connectorIDs.filter { !isMonitoringEnabled(for: $0) })
    }

    func setAutoSearchEnabled(_ enabled: Bool) {
        guard envelope.autoSearchEnabled != enabled
                || !envelope.autoSearchExplicitlySet
        else {
            return
        }
        envelope.autoSearchEnabled = enabled
        envelope.autoSearchExplicitlySet = true
        persist()
    }

    func completeFirstManualScan(
        detectedConnectorIDs: [AgentConnectorID],
        detectedAt: Date
    ) {
        guard !envelope.initialScanCompleted else {
            recordSafeDetections(
                detectedConnectorIDs,
                detectedAt: detectedAt
            )
            return
        }
        envelope.initialScanCompleted = true
        if !envelope.autoSearchExplicitlySet {
            envelope.autoSearchEnabled = true
        }
        applyDetections(detectedConnectorIDs, detectedAt: detectedAt)
        persist()
    }

    func recordSafeDetections(
        _ connectorIDs: [AgentConnectorID],
        detectedAt: Date
    ) {
        applyDetections(connectorIDs, detectedAt: detectedAt)
        persist()
    }

    func setActiveConnectorIDs(_ connectorIDs: [AgentConnectorID]) {
        setProviderRuntimeState(
            activeConnectorIDs: connectorIDs,
            setupRequiredConnectorIDs:
                Array(setupRequiredProviderIDs)
        )
    }

    func setProviderRuntimeState(
        activeConnectorIDs: [AgentConnectorID],
        setupRequiredConnectorIDs: [AgentConnectorID]
    ) {
        let canonical = Set(
            activeConnectorIDs.map(AgentPreferenceRecord.canonicalProviderID)
        )
        let setupRequired = Set(
            setupRequiredConnectorIDs.map(
                AgentPreferenceRecord.canonicalProviderID
            )
        ).subtracting(canonical)
        guard canonical != activeProviderIDs
                || setupRequired != setupRequiredProviderIDs
        else {
            return
        }
        activeProviderIDs = canonical
        setupRequiredProviderIDs = setupRequired
    }

    func setMonitoringEnabled(
        _ enabled: Bool,
        for providerID: AgentConnectorID
    ) {
        mutateRecord(for: providerID) {
            $0.providerSettings.monitoring.monitoringEnabled = enabled
        }
    }

    func setCodexDetails(
        _ details: CodexDetailPreferences,
        for providerID: AgentConnectorID =
            AgentPreferenceRecord.codexProviderID
    ) {
        mutateRecord(for: providerID) {
            $0.providerSettings.codexDetails = details
        }
    }

    private func mutateRecord(
        for providerID: AgentConnectorID,
        _ mutation: (inout AgentPreferenceRecord) -> Void
    ) {
        let canonicalID = AgentPreferenceRecord.canonicalProviderID(
            for: providerID
        )
        var record = envelope.record(for: canonicalID)
            ?? AgentPreferenceRecord(providerID: canonicalID)
        let before = record
        mutation(&record)
        record.normalize()
        guard record != before else { return }
        upsert(record)
        persist()
    }

    private func applyDetections(
        _ connectorIDs: [AgentConnectorID],
        detectedAt: Date
    ) {
        for connectorID in connectorIDs {
            let canonicalID = AgentPreferenceRecord.canonicalProviderID(
                for: connectorID
            )
            var record = envelope.record(for: canonicalID)
                ?? AgentPreferenceRecord(providerID: canonicalID)
            record.hasBeenDetected = true
            record.lastSafeDetectionAt = max(
                record.lastSafeDetectionAt ?? .distantPast,
                detectedAt
            )
            upsert(record)
        }
    }

    private func upsert(_ record: AgentPreferenceRecord) {
        envelope.records.removeAll {
            $0.providerID == record.providerID
        }
        envelope.records.append(record)
        envelope.normalize()
    }

    private func persist() {
        guard store.save(envelope) else {
            envelope = store.loadOrMigrateLegacyPreferences()
            return
        }
        envelope.normalize()
    }

    private static func fallbackName(for providerID: AgentConnectorID) -> String {
        providerID.rawValue.prefix(1).uppercased()
            + providerID.rawValue.dropFirst()
    }
}
