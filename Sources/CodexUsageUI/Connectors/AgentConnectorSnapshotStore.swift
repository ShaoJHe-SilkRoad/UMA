import Foundation

/// Small, allowlisted last-known snapshot store. This is intentionally
/// separate from the Codex local-cost checkpoint ledger.
actor AgentConnectorSnapshotStore {
    static let schemaVersion = 1
    static let maximumEntries = 8
    static let maximumWindowsPerChannel = 4
    static let maximumEncodedBytes = 32 * 1024
    struct PersistedWindow: Codable, Equatable {
        let kind: AgentRateLimitWindow.Kind
        let usedPercent: Double?
        let remainingPercent: Double?
        let isEstimated: Bool?
        let isUnlimited: Bool
        let resetsAt: Date?
    }

    struct PersistedChannel: Codable, Equatable {
        let kind: AgentUsageChannel.Kind
        let sourceTier: AgentSourceTier
        let sourceVersion: String
        let scopes: Set<AgentMetricScope>
        let provenance: AgentMetricProvenance
        let freshness: AgentConnectorFreshness
        let capturedAt: Date?
        let windows: [PersistedWindow]
        let account: AgentAccountMetrics?
        let local: PersistedLocalActivityMetrics?
        let safeFailure: AgentSafeFailure?
    }

    struct PersistedLocalActivityMetrics: Codable, Equatable {
        let recentTaskCount: Int?
        let sessionTokens: Int64?
        let estimatedSevenDayUSD: Double?
        let estimatedLifetimeUSD: Double?
        let coveragePercent: Int?
        let recognizedModelCount: Int?
    }

    struct PersistedEntry: Codable, Equatable {
        let id: AgentConnectorID
        let providerName: String
        let state: AgentConnectorState
        let capturedAt: Date
        let lastSuccessfulAt: Date?
        let channels: [PersistedChannel]
        let capabilities: Set<AgentConnectorCapability>
        let safeFailure: AgentSafeFailure?
    }

    struct Envelope: Codable, Equatable {
        let schemaVersion: Int
        let entries: [PersistedEntry]
    }

    /// Schema zero used the same allowlisted fields but did not distinguish
    /// the envelope as a connector snapshot. Decode it once and rewrite it as
    /// schema one on the next save; no raw legacy payload is ever retained.
    private struct LegacyEnvelopeV0: Codable {
        let schemaVersion: Int
        let entries: [PersistedEntry]
    }

    enum StoreError: Error, Equatable {
        case rejected
        case oversized
    }

    let url: URL
    let backupURL: URL
    private let fileManager: FileManager
    private var lastSavedData: Data?

    init(
        url: URL = AgentConnectorSnapshotStore.defaultURL,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.backupURL = url.appendingPathExtension("backup")
        self.fileManager = fileManager
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexUsageMonitor", isDirectory: true)
            .appendingPathComponent("connector-snapshots.json")
    }

    func load() -> [AgentUsageSnapshot] {
        if let entries = decodeEntries(at: url) ?? decodeEntries(at: backupURL) {
            return entries.compactMap(Self.restore)
        }
        return []
    }

    func save(_ snapshots: [AgentUsageSnapshot]) throws {
        let incoming = try snapshots.map(Self.persisted)
        let existing = decodeEntries(at: url) ?? decodeEntries(at: backupURL) ?? []
        let replacedIDs = Set(incoming.map(\.id))
        let entries = (existing.filter { !replacedIDs.contains($0.id) } + incoming)
            .sorted { $0.id < $1.id }
        try write(entries)
    }

    func replace(with snapshots: [AgentUsageSnapshot]) throws {
        let entries = try snapshots.map(Self.persisted).sorted { $0.id < $1.id }
        try write(entries)
    }

    private func write(_ entries: [PersistedEntry]) throws {
        guard entries.count <= Self.maximumEntries else { throw StoreError.rejected }
        let envelope = Envelope(schemaVersion: Self.schemaVersion, entries: entries)
        let data = try JSONEncoder.safeSnapshotEncoder.encode(envelope)
        guard data.count <= Self.maximumEncodedBytes else { throw StoreError.oversized }
        // Suppress only a true duplicate of the file currently on disk.  A
        // schema-zero envelope can represent the same snapshot data, but it
        // must be rewritten during the next save so lazy migration completes.
        if data == lastSavedData,
           let current = try? Data(contentsOf: url),
           current == data {
            return
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let current = try? Data(contentsOf: url), (try? JSONDecoder.safeSnapshotDecoder.decode(Envelope.self, from: current)) != nil {
            try current.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        lastSavedData = data
    }

    func remove(_ id: AgentConnectorID) throws {
        let existing = decodeEntries(at: url) ?? decodeEntries(at: backupURL) ?? []
        let entries = existing.filter { $0.id != id }
        let data = try JSONEncoder.safeSnapshotEncoder.encode(Envelope(schemaVersion: Self.schemaVersion, entries: entries))
        try data.write(to: url, options: .atomic)
        lastSavedData = data
    }

    private func decodeEntries(at location: URL) -> [PersistedEntry]? {
        guard let data = try? Data(contentsOf: location), data.count <= Self.maximumEncodedBytes else { return nil }
        if let envelope = try? JSONDecoder.safeSnapshotDecoder.decode(Envelope.self, from: data),
           envelope.schemaVersion == Self.schemaVersion,
           Self.areValid(entries: envelope.entries) {
            return envelope.entries
        }
        if let legacy = try? JSONDecoder.safeSnapshotDecoder.decode(LegacyEnvelopeV0.self, from: data),
           legacy.schemaVersion == 0,
           Self.areValid(entries: legacy.entries) {
            return legacy.entries
        }
        return nil
    }

    private static func persisted(_ snapshot: AgentUsageSnapshot) throws -> PersistedEntry {
        let channels = try snapshot.channels.map { channel in
            guard channel.rateLimitWindows.count <= maximumWindowsPerChannel,
                  channel.sourceTier.isAdmissible,
                  Self.isSafeLabel(channel.sourceVersion, maximumLength: 32),
                  channel.accountMetrics?.planLabel.map({ Self.isSafeLabel($0, maximumLength: 24) }) ?? true else { throw StoreError.rejected }
            let windows = channel.rateLimitWindows.map {
                PersistedWindow(
                    kind: $0.kind,
                    usedPercent: $0.usedPercent,
                    remainingPercent: $0.remainingPercent,
                    isEstimated: $0.isEstimated,
                    isUnlimited: $0.isUnlimited,
                    resetsAt: $0.resetsAt
                )
            }
            // Coverage notes and provider IDs are display/transport details,
            // so they deliberately have no persisted field.
            return PersistedChannel(
                kind: channel.id,
                sourceTier: channel.sourceTier,
                sourceVersion: channel.sourceVersion,
                scopes: channel.scopes,
                provenance: channel.provenance,
                freshness: channel.freshness,
                capturedAt: channel.capturedAt,
                windows: windows,
                account: channel.accountMetrics,
                local: channel.localActivityMetrics.map {
                    PersistedLocalActivityMetrics(
                        recentTaskCount: $0.recentTaskCount,
                        sessionTokens: $0.sessionTokens,
                        estimatedSevenDayUSD: $0.estimatedSevenDayUSD,
                        estimatedLifetimeUSD: $0.estimatedLifetimeUSD,
                        coveragePercent: $0.coveragePercent,
                        recognizedModelCount: $0.recognizedModelCount
                    )
                },
                safeFailure: channel.safeFailure
            )
        }
        guard Self.isSafeLabel(snapshot.providerName, maximumLength: 48), channels.count <= 2 else { throw StoreError.rejected }
        return PersistedEntry(
            id: snapshot.id,
            providerName: snapshot.providerName,
            state: snapshot.state,
            capturedAt: snapshot.capturedAt,
            lastSuccessfulAt: snapshot.lastSuccessfulAt,
            channels: channels,
            capabilities: snapshot.capabilities,
            safeFailure: snapshot.safeFailure
        )
    }

    private static func restore(_ entry: PersistedEntry) -> AgentUsageSnapshot? {
        guard isValid(entry) else { return nil }
        let channels = entry.channels.map {
            AgentUsageChannel(
                id: $0.kind,
                sourceTier: $0.sourceTier,
                sourceVersion: $0.sourceVersion,
                scopes: $0.scopes,
                provenance: $0.provenance,
                freshness: $0.freshness == .unavailable ? .unavailable : .stale,
                capturedAt: $0.capturedAt,
                coverageNote: nil,
                rateLimitWindows: $0.windows.map {
                    AgentRateLimitWindow(
                        id: $0.kind.rawValue,
                        kind: $0.kind,
                        usedPercent: $0.usedPercent,
                        remainingPercent: $0.remainingPercent,
                        isEstimated: $0.isEstimated ?? false,
                        isUnlimited: $0.isUnlimited,
                        resetsAt: $0.resetsAt
                    )
                },
                accountMetrics: $0.account,
                localActivityMetrics: $0.local.map {
                    AgentLocalActivityMetrics(
                        recentTaskCount: $0.recentTaskCount,
                        recentTaskTokens: [],
                        recentTaskCapturedAt: [],
                        sessionTokens: $0.sessionTokens,
                        estimatedSevenDayUSD: $0.estimatedSevenDayUSD,
                        estimatedLifetimeUSD: $0.estimatedLifetimeUSD,
                        coveragePercent: $0.coveragePercent,
                        recognizedModelCount: $0.recognizedModelCount
                    )
                },
                safeFailure: $0.safeFailure
            )
        }
        return AgentUsageSnapshot(
            id: entry.id,
            providerName: entry.providerName,
            state: entry.state == .ready ? .stale : entry.state,
            capturedAt: entry.capturedAt,
            lastSuccessfulAt: entry.lastSuccessfulAt,
            freshness: channels.contains(where: { $0.freshness == .stale }) ? .stale : .unavailable,
            channels: channels,
            capabilities: entry.capabilities,
            safeFailure: entry.safeFailure
        )
    }

    private static func areValid(entries: [PersistedEntry]) -> Bool {
        entries.count <= maximumEntries
            && Set(entries.map(\.id)).count == entries.count
            && entries.allSatisfy(isValid)
    }

    private static func isValid(_ entry: PersistedEntry) -> Bool {
        isSafeLabel(entry.providerName, maximumLength: 48)
            && entry.channels.count <= 2
            && entry.channels.allSatisfy { channel in
                channel.sourceTier.isAdmissible
                    && !channel.scopes.isEmpty
                    && isSafeLabel(channel.sourceVersion, maximumLength: 32)
                    && channel.windows.count <= maximumWindowsPerChannel
                    && channel.windows.allSatisfy { window in
                        (window.usedPercent.map { $0.isFinite && (0...100).contains($0) } ?? true)
                            && (window.remainingPercent.map { $0.isFinite && (0...100).contains($0) } ?? true)
                            && !(window.usedPercent != nil && window.remainingPercent != nil)
                    }
                    && (channel.account?.planLabel.map { isSafeLabel($0, maximumLength: 24) } ?? true)
                    && (channel.account?.availableResets.map { $0 >= 0 } ?? true)
                    && (channel.account?.lifetimeTokens.map { $0 >= 0 } ?? true)
                    && (channel.account?.sevenDayTokens.map { $0 >= 0 } ?? true)
                    && (channel.local?.recentTaskCount.map { $0 >= 0 } ?? true)
                    && (channel.local?.sessionTokens.map { $0 >= 0 } ?? true)
                    && (channel.local?.estimatedSevenDayUSD.map { $0.isFinite && $0 >= 0 } ?? true)
                    && (channel.local?.estimatedLifetimeUSD.map { $0.isFinite && $0 >= 0 } ?? true)
                    && (channel.local?.coveragePercent.map { (0...100).contains($0) } ?? true)
                    && (channel.local?.recognizedModelCount.map { $0 >= 0 } ?? true)
            }
    }

    private static func isSafeLabel(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        return value.range(of: "^[A-Za-z0-9 ._-]+$", options: .regularExpression) != nil
    }
}

private extension JSONEncoder {
    static var safeSnapshotEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var safeSnapshotDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
