import Darwin
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

    // Read the version independently of the current entry shape: a future
    // writer may change that shape, and its bytes must survive a rollback.
    private struct VersionHeader: Decodable {
        let schemaVersion: Int
    }

    private enum StoredEnvelope {
        case missingOrCorrupt
        case unsupported
        case supported(entries: [PersistedEntry], data: Data)

        var entries: [PersistedEntry]? {
            if case let .supported(entries, _) = self { return entries }
            return nil
        }
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
        ApplicationDataPaths.current().snapshotURL
    }

    func load() -> [AgentUsageSnapshot] {
        guard (try? validatePaths()) != nil else { return [] }
        let entries = (try? readEnvelope(at: url))?.entries
            ?? (try? readEnvelope(at: backupURL))?.entries
        return entries?.compactMap(Self.restore) ?? []
    }

    func save(_ snapshots: [AgentUsageSnapshot]) throws {
        let incoming = try snapshots.map(Self.persisted)
        try validatePaths()
        let existing = try readEnvelope(at: url).entries ?? readEnvelope(at: backupURL).entries ?? []
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
        guard Self.areValid(entries: entries) else { throw StoreError.rejected }
        try validatePaths()
        let current = try readEnvelope(at: url)
        let backup = try readEnvelope(at: backupURL)
        // Routine refresh/removal must not downgrade a newer version's data,
        // including a newer backup beside an otherwise supported main file.
        if case .unsupported = current { throw StoreError.rejected }
        if case .unsupported = backup { throw StoreError.rejected }
        let envelope = Envelope(schemaVersion: Self.schemaVersion, entries: entries)
        let data = try JSONEncoder.safeSnapshotEncoder.encode(envelope)
        guard data.count <= Self.maximumEncodedBytes else { throw StoreError.oversized }
        if data == lastSavedData,
           case let .supported(_, currentData) = current,
           currentData == data {
            return
        }

        // This root is shared with the owner-only Claude anchor store. Whichever
        // cache writes first must create a compatible private directory.
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try validatePaths()
        // Only a supported, fully validated main may replace the recovery
        // backup. Corrupt/invalid main bytes never pollute a good backup.
        if case let .supported(currentEntries, currentData) = current {
            // Decoding ignores unknown fields. Never copy those raw fields
            // into a new backup. Preserve legitimate legacy bytes when their
            // entire field structure fits the same-schema typed projection.
            // Set order and numeric encoding can change during a round trip.
            let version = try JSONDecoder().decode(VersionHeader.self, from: currentData)
            let projected = try JSONEncoder.safeSnapshotEncoder.encode(
                Envelope(schemaVersion: version.schemaVersion, entries: currentEntries)
            )
            let originalObject = try JSONSerialization.jsonObject(with: currentData)
            let projectedObject = try JSONSerialization.jsonObject(with: projected)
            let backupData = Self.containsOnlyProjectedFields(originalObject, projection: projectedObject)
                ? currentData : projected
            try backupData.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        lastSavedData = data
    }

    func remove(_ id: AgentConnectorID) throws {
        try validatePaths()
        let existing = try readEnvelope(at: url).entries ?? readEnvelope(at: backupURL).entries ?? []
        try write(existing.filter { $0.id != id })
    }

    func clear() throws {
        // Validate both targets before deleting either, including dangling
        // symlinks (fileExists alone follows them and misses that case).
        try validatePaths()
        for location in [url, backupURL] where fileManager.fileExists(atPath: location.path) {
            try fileManager.removeItem(at: location)
        }
        lastSavedData = nil
    }

    private func readEnvelope(at location: URL) throws -> StoredEnvelope {
        var metadata = stat()
        guard lstat(location.path, &metadata) == 0 else {
            guard errno == ENOENT else { throw StoreError.rejected }
            return .missingOrCorrupt
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else { throw StoreError.rejected }
        guard metadata.st_size <= Self.maximumEncodedBytes else { throw StoreError.oversized }
        let data = try Data(contentsOf: location)
        guard data.count <= Self.maximumEncodedBytes else { throw StoreError.oversized }
        if let header = try? JSONDecoder().decode(VersionHeader.self, from: data),
           header.schemaVersion != 0, header.schemaVersion != Self.schemaVersion {
            return .unsupported
        }
        guard let envelope = try? JSONDecoder.safeSnapshotDecoder.decode(Envelope.self, from: data),
              (envelope.schemaVersion == 0 || envelope.schemaVersion == Self.schemaVersion),
              Self.areValid(entries: envelope.entries) else { return .missingOrCorrupt }
        return .supported(entries: envelope.entries, data: data)
    }

    private func validatePaths() throws {
        for location in [url, backupURL] {
            guard location.isFileURL, location.path.hasPrefix("/") else { throw StoreError.rejected }
            let components = (location.path as NSString).pathComponents.dropFirst()
            var current = "/"
            for (index, component) in components.enumerated() {
                guard component != ".", component != ".." else { throw StoreError.rejected }
                current = (current as NSString).appendingPathComponent(component)
                var metadata = stat()
                guard lstat(current, &metadata) == 0 else {
                    guard errno == ENOENT else { throw StoreError.rejected }
                    continue
                }
                let kind = metadata.st_mode & S_IFMT
                let isLeaf = index == components.count - 1
                // macOS owns these root aliases. Do not resolve arbitrary
                // caller-supplied symlinks, which would erase the boundary.
                if !isLeaf, kind == S_IFLNK,
                   (current == "/var" || current == "/tmp"), metadata.st_uid == 0,
                   (try? fileManager.destinationOfSymbolicLink(atPath: current)) == "private" + current {
                    continue
                }
                guard kind == (isLeaf ? S_IFREG : S_IFDIR) else { throw StoreError.rejected }
            }
        }
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

    private static func containsOnlyProjectedFields(_ original: Any, projection: Any) -> Bool {
        if let fields = original as? [String: Any] {
            guard let allowed = projection as? [String: Any],
                  Set(fields.keys).isSubset(of: Set(allowed.keys)) else { return false }
            return fields.allSatisfy { key, value in
                guard let projected = allowed[key] else { return false }
                return containsOnlyProjectedFields(value, projection: projected)
            }
        }
        if let values = original as? [Any] {
            guard let projected = projection as? [Any], values.count == projected.count else { return false }
            return zip(values, projected).allSatisfy {
                containsOnlyProjectedFields($0.0, projection: $0.1)
            }
        }
        // Scalar values have already passed the typed decoder and validators.
        return true
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
