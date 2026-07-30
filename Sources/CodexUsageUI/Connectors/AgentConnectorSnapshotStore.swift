import CoreFoundation
import Foundation

/// Small, allowlisted last-known snapshot store. This is intentionally
/// separate from the Codex local-cost checkpoint ledger.
actor AgentConnectorSnapshotStore {
    static let schemaVersion = 1
    static let maximumEntries = 8
    static let maximumWindowsPerChannel = 4
    static let maximumEncodedBytes = 32 * 1024
    static let claudeSchemaVersion = 1
    static let maximumClaudeEncodedBytes = 4 * 1024
    static let claudeSourceIdentifier = "claude.statusLine"

    struct ClaudeSanitizedQuotaSnapshot: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let sourceIdentifier: String
        let fiveHourRemainingPercent: Double?
        let fiveHourResetEpoch: Int64?
        let sevenDayRemainingPercent: Double?
        let sevenDayResetEpoch: Int64?
        let selectedWindowIdentifier: String?
        let observationTimestamp: Date
        let sourceVersion: String?

        init(
            schemaVersion: Int = AgentConnectorSnapshotStore.claudeSchemaVersion,
            sourceIdentifier: String = AgentConnectorSnapshotStore.claudeSourceIdentifier,
            fiveHourRemainingPercent: Double?,
            fiveHourResetEpoch: Int64?,
            sevenDayRemainingPercent: Double?,
            sevenDayResetEpoch: Int64?,
            selectedWindowIdentifier: String?,
            observationTimestamp: Date,
            sourceVersion: String?
        ) {
            self.schemaVersion = schemaVersion
            self.sourceIdentifier = sourceIdentifier
            self.fiveHourRemainingPercent = fiveHourRemainingPercent
            self.fiveHourResetEpoch = fiveHourResetEpoch
            self.sevenDayRemainingPercent = sevenDayRemainingPercent
            self.sevenDayResetEpoch = sevenDayResetEpoch
            self.selectedWindowIdentifier = selectedWindowIdentifier
            self.observationTimestamp = observationTimestamp
            self.sourceVersion = sourceVersion
        }
    }

    struct PersistedWindow: Codable, Equatable {
        let kind: AgentRateLimitWindow.Kind
        let usedPercent: Double?
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
    let claudeSnapshotURL: URL
    private let fileManager: FileManager
    private var lastSavedData: Data?
    private var lastSavedClaudeData: Data?

    init(
        url: URL = AgentConnectorSnapshotStore.defaultURL,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.backupURL = url.appendingPathExtension("backup")
        self.claudeSnapshotURL = url.deletingLastPathComponent()
            .appendingPathComponent("claude-last-valid-quota.json")
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
        let changed = try snapshots.map(Self.persisted)
        let existing = decodeEntries(at: url) ?? decodeEntries(at: backupURL) ?? []
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for entry in changed { merged[entry.id] = entry }
        let entries = merged.values.sorted { $0.id < $1.id }
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

    /// Loads the one Claude-specific, normalized remaining-quota snapshot.
    /// Unknown fields, future schemas, unsafe metadata, and a future
    /// observation time fail closed. Invalid or expired windows are pruned
    /// independently and the bounded record is atomically rewritten.
    func loadClaudeSanitizedSnapshot(
        now: Date
    ) -> ClaudeSanitizedQuotaSnapshot? {
        guard let data = try? Data(contentsOf: claudeSnapshotURL) else {
            return nil
        }
        guard data.count <= Self.maximumClaudeEncodedBytes,
              Self.hasExactClaudeSchemaKeys(data),
              let decoded = Self.decodeClaudeSnapshot(data),
              decoded.schemaVersion == Self.claudeSchemaVersion,
              decoded.sourceIdentifier == Self.claudeSourceIdentifier,
              decoded.observationTimestamp.timeIntervalSince1970.isFinite,
              decoded.observationTimestamp <= now.addingTimeInterval(5),
              decoded.sourceVersion.map({
                  Self.isSafeLabel($0, maximumLength: 32)
              }) ?? true
        else {
            try? removeClaudeSanitizedSnapshot()
            return nil
        }

        guard let normalized = Self.validatedClaudeSnapshot(
            decoded,
            now: now
        ) else {
            try? removeClaudeSanitizedSnapshot()
            return nil
        }
        if normalized != decoded {
            try? saveClaudeSanitizedSnapshot(normalized, now: now)
        } else {
            lastSavedClaudeData = data
        }
        return normalized
    }

    func saveClaudeSanitizedSnapshot(
        _ snapshot: ClaudeSanitizedQuotaSnapshot,
        now: Date
    ) throws {
        guard snapshot.schemaVersion == Self.claudeSchemaVersion,
              snapshot.sourceIdentifier == Self.claudeSourceIdentifier,
              snapshot.observationTimestamp <= now.addingTimeInterval(5),
              snapshot.observationTimestamp.timeIntervalSince1970.isFinite,
              snapshot.sourceVersion.map({
                  Self.isSafeLabel($0, maximumLength: 32)
              }) ?? true,
              Self.validatedClaudeSnapshot(snapshot, now: now) == snapshot
        else {
            throw StoreError.rejected
        }
        let data = try JSONEncoder.safeSnapshotEncoder.encode(snapshot)
        guard data.count <= Self.maximumClaudeEncodedBytes else {
            throw StoreError.oversized
        }
        if data == lastSavedClaudeData,
           let current = try? Data(contentsOf: claudeSnapshotURL),
           current == data {
            return
        }

        let directory = claudeSnapshotURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(directoryValues)

        try data.write(to: claudeSnapshotURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: claudeSnapshotURL.path
        )
        var fileValues = URLResourceValues()
        fileValues.isExcludedFromBackup = true
        var mutableFile = claudeSnapshotURL
        try? mutableFile.setResourceValues(fileValues)
        lastSavedClaudeData = data
    }

    func removeClaudeSanitizedSnapshot() throws {
        if fileManager.fileExists(atPath: claudeSnapshotURL.path) {
            try fileManager.removeItem(at: claudeSnapshotURL)
        }
        lastSavedClaudeData = nil
    }

    private static func validatedClaudeSnapshot(
        _ snapshot: ClaudeSanitizedQuotaSnapshot,
        now: Date
    ) -> ClaudeSanitizedQuotaSnapshot? {
        let fiveHour = validatedClaudeWindow(
            remaining: snapshot.fiveHourRemainingPercent,
            resetEpoch: snapshot.fiveHourResetEpoch,
            now: now
        )
        let sevenDay = validatedClaudeWindow(
            remaining: snapshot.sevenDayRemainingPercent,
            resetEpoch: snapshot.sevenDayResetEpoch,
            now: now
        )
        guard fiveHour != nil || sevenDay != nil else { return nil }

        let validSelectedIDs = Set([
            fiveHour == nil ? nil : "claude-five-hour",
            sevenDay == nil ? nil : "claude-seven-day",
        ].compactMap { $0 })
        let selected = snapshot.selectedWindowIdentifier.flatMap {
            validSelectedIDs.contains($0) ? $0 : nil
        }
        return ClaudeSanitizedQuotaSnapshot(
            fiveHourRemainingPercent: fiveHour?.remaining,
            fiveHourResetEpoch: fiveHour?.resetEpoch,
            sevenDayRemainingPercent: sevenDay?.remaining,
            sevenDayResetEpoch: sevenDay?.resetEpoch,
            selectedWindowIdentifier: selected,
            observationTimestamp: snapshot.observationTimestamp,
            sourceVersion: snapshot.sourceVersion
        )
    }

    private static func validatedClaudeWindow(
        remaining: Double?,
        resetEpoch: Int64?,
        now: Date
    ) -> (remaining: Double, resetEpoch: Int64)? {
        guard let remaining,
              let resetEpoch,
              remaining.isFinite,
              (0...100).contains(remaining),
              resetEpoch > Int64(now.timeIntervalSince1970.rounded(.down))
        else {
            return nil
        }
        return (remaining, resetEpoch)
    }

    private static func hasExactClaudeSchemaKeys(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return false
        }
        let allowed: Set<String> = [
            "schemaVersion",
            "sourceIdentifier",
            "fiveHourRemainingPercent",
            "fiveHourResetEpoch",
            "sevenDayRemainingPercent",
            "sevenDayResetEpoch",
            "selectedWindowIdentifier",
            "observationTimestamp",
            "sourceVersion",
        ]
        let required: Set<String> = [
            "schemaVersion",
            "sourceIdentifier",
            "observationTimestamp",
        ]
        let keys = Set(dictionary.keys)
        return keys.isSubset(of: allowed) && required.isSubset(of: keys)
    }

    /// Decodes each quota window independently so one malformed or missing
    /// reset cannot hide the other valid window. Envelope ownership and
    /// observation metadata remain strict fail-closed boundaries.
    private static func decodeClaudeSnapshot(
        _ data: Data
    ) -> ClaudeSanitizedQuotaSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let schemaValue = integer(dictionary["schemaVersion"]),
              schemaValue >= 0,
              schemaValue <= Int64(Int.max),
              let source = dictionary["sourceIdentifier"] as? String,
              let observedMilliseconds = finiteNumber(
                dictionary["observationTimestamp"]
              )
        else {
            return nil
        }
        let sourceVersion: String?
        if let value = dictionary["sourceVersion"] {
            if value is NSNull {
                sourceVersion = nil
            } else if let value = value as? String {
                sourceVersion = value
            } else {
                return nil
            }
        } else {
            sourceVersion = nil
        }
        let selected: String?
        if let value = dictionary["selectedWindowIdentifier"] {
            if value is NSNull {
                selected = nil
            } else if let value = value as? String {
                selected = value
            } else {
                return nil
            }
        } else {
            selected = nil
        }
        return ClaudeSanitizedQuotaSnapshot(
            schemaVersion: Int(schemaValue),
            sourceIdentifier: source,
            fiveHourRemainingPercent: finiteNumber(
                dictionary["fiveHourRemainingPercent"]
            ),
            fiveHourResetEpoch: integer(
                dictionary["fiveHourResetEpoch"]
            ),
            sevenDayRemainingPercent: finiteNumber(
                dictionary["sevenDayRemainingPercent"]
            ),
            sevenDayResetEpoch: integer(
                dictionary["sevenDayResetEpoch"]
            ),
            selectedWindowIdentifier: selected,
            observationTimestamp: Date(
                timeIntervalSince1970: observedMilliseconds / 1_000
            ),
            sourceVersion: sourceVersion
        )
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            return nil
        }
        let result = number.doubleValue
        guard result.isFinite,
              result.rounded(.towardZero) == result,
              result >= Double(Int64.min),
              result <= Double(Int64.max)
        else {
            return nil
        }
        return Int64(result)
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
                PersistedWindow(kind: $0.kind, usedPercent: $0.usedPercent, isUnlimited: $0.isUnlimited, resetsAt: $0.resetsAt)
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
                    AgentRateLimitWindow(id: $0.kind.rawValue, kind: $0.kind, usedPercent: $0.usedPercent, isUnlimited: $0.isUnlimited, resetsAt: $0.resetsAt)
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
