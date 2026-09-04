import ClaudeStatusLineCore
import Darwin
import Foundation

enum ClaudeSmartSourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case exactLocalStatusLine = "EXACT_LOCAL_STATUSLINE"
    case exactSafariAccuracy = "EXACT_SAFARI_ACCURACY"
    case estimatedLocal = "ESTIMATED_LOCAL"
    case estimatedDesktopCache = "ESTIMATED_DESKTOP_CACHE"
    case staleExact = "STALE_EXACT"
    case missing = "MISSING"

    var rank: Int {
        switch self {
        case .exactLocalStatusLine: 0
        case .exactSafariAccuracy: 1
        case .estimatedLocal, .estimatedDesktopCache: 2
        case .staleExact: 3
        case .missing: 4
        }
    }
}

enum ClaudeSmartConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case insufficient
}

struct ClaudeSanitizedLocalActivity: Codable, Equatable, Sendable {
    let observedAt: Date
    let totalTokens: Int64
    let latestActivityAt: Date?
    let modelFamilyKey: String?
    let coveragePercent: Int?
    let observedSurfaces: [ClaudeLocalActivitySurface]
    let deduplicationConfidence: ClaudeLocalDeduplicationConfidence

    init(
        observedAt: Date,
        totalTokens: Int64,
        latestActivityAt: Date?,
        modelFamilyKey: String?,
        coveragePercent: Int?,
        observedSurfaces: [ClaudeLocalActivitySurface] = [],
        deduplicationConfidence: ClaudeLocalDeduplicationConfidence = .exact
    ) {
        self.observedAt = observedAt
        self.totalTokens = totalTokens
        self.latestActivityAt = latestActivityAt
        self.modelFamilyKey = modelFamilyKey
        self.coveragePercent = coveragePercent
        self.observedSurfaces = observedSurfaces
        self.deduplicationConfidence = deduplicationConfidence
    }

    static func project(
        _ snapshot: ClaudeLocalActivitySnapshot
    ) -> ClaudeSanitizedLocalActivity? {
        guard snapshot.availability == .available,
              let estimate = snapshot.apiEquivalentCost,
              estimate.observedTokens >= 0
        else { return nil }
        let families = estimate.modelNames
            .map { $0.lowercased() }
            .filter { $0.range(of: "^[a-z0-9 -]{1,24}$", options: .regularExpression) != nil }
            .sorted()
        let key = families.isEmpty ? nil : families.joined(separator: "+")
        let coverage: Int? = estimate.observedTokens > 0
            ? Int((Double(estimate.pricedTokens) / Double(estimate.observedTokens) * 100).rounded())
            : nil
        return ClaudeSanitizedLocalActivity(
            observedAt: snapshot.capturedAt,
            totalTokens: estimate.observedTokens,
            latestActivityAt: snapshot.tasks.map(\.modifiedAt).max(),
            modelFamilyKey: key,
            coveragePercent: coverage.map { min(100, max(0, $0)) },
            observedSurfaces: snapshot.observedSurfaces.sorted {
                $0.rawValue < $1.rawValue
            },
            deduplicationConfidence: snapshot.deduplicationConfidence
        )
    }
}

struct ClaudeSmartWindowAnchor: Codable, Equatable, Sendable {
    let windowKind: AgentRateLimitWindow.Kind
    let usedPercent: Double
    let resetsAt: Date?
    let observedAt: Date
    let activityTotalTokens: Int64?
    let source: ClaudeSmartSourceKind
    let modelFamilyKey: String?
    let sourceSchema: String
    let continuityGeneration: UInt64

    init?(
        windowKind: AgentRateLimitWindow.Kind,
        usedPercent: Double,
        resetsAt: Date?,
        observedAt: Date,
        activityTotalTokens: Int64?,
        source: ClaudeSmartSourceKind,
        modelFamilyKey: String?,
        sourceSchema: String,
        continuityGeneration: UInt64
    ) {
        guard usedPercent.isFinite,
              (0...100).contains(usedPercent),
              resetsAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              resetsAt != nil || source == .exactSafariAccuracy,
              observedAt.timeIntervalSince1970.isFinite,
              activityTotalTokens.map({ $0 >= 0 }) ?? true,
              source == .exactLocalStatusLine || source == .exactSafariAccuracy,
              sourceSchema.range(of: "^[A-Za-z0-9._-]{1,32}$", options: .regularExpression) != nil,
              modelFamilyKey.map({
                  $0.range(of: "^[a-z0-9 +_-]{1,64}$", options: .regularExpression) != nil
              }) ?? true
        else { return nil }
        self.windowKind = windowKind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.activityTotalTokens = activityTotalTokens
        self.source = source
        self.modelFamilyKey = modelFamilyKey
        self.sourceSchema = sourceSchema
        self.continuityGeneration = continuityGeneration
    }
}

struct ClaudeSmartWindowValue: Equatable, Sendable {
    let windowKind: AgentRateLimitWindow.Kind
    let remainingPercent: Double
    let resetsAt: Date?
    let observedAt: Date
    let source: ClaudeSmartSourceKind
    let confidence: ClaudeSmartConfidence

    var isEstimated: Bool {
        source == .estimatedLocal || source == .estimatedDesktopCache
    }
}

enum ClaudeSmartUsageEstimator {
    static let maximumAnchorCountPerWindow = 12
    static let highConfidenceAge: TimeInterval = 30 * 60
    static let mediumConfidenceAge: TimeInterval = 2 * 60 * 60
    static let maximumEstimateAge: TimeInterval = 6 * 60 * 60

    static func estimate(
        windowKind: AgentRateLimitWindow.Kind,
        anchors: [ClaudeSmartWindowAnchor],
        activity: ClaudeSanitizedLocalActivity?,
        previousEstimatedRemaining: Double?,
        now: Date
    ) -> ClaudeSmartWindowValue? {
        guard let activity,
              let activityModel = activity.modelFamilyKey
        else { return nil }
        // A provider percentage without a reset is exact display truth only.
        // It cannot identify a cycle, continuity generation, or calibration
        // pair, even if sanitized activity counters happen to be present.
        let calibrationAnchors = anchors.filter { $0.resetsAt != nil }
        let currentGeneration = calibrationAnchors
            .filter { $0.windowKind == windowKind }
            .map(\.continuityGeneration)
            .max()
        let eligible = calibrationAnchors.filter {
            $0.windowKind == windowKind
                && $0.continuityGeneration == currentGeneration
                && ($0.resetsAt.map { $0 > now } ?? false)
                && $0.activityTotalTokens != nil
        }.sorted { $0.observedAt < $1.observedAt }
        guard eligible.count >= 2,
              let last = eligible.last,
              let lastTokens = last.activityTotalTokens,
              let lastReset = last.resetsAt,
              activity.totalTokens >= lastTokens,
              now.timeIntervalSince(last.observedAt) >= 0,
              now.timeIntervalSince(last.observedAt) <= maximumEstimateAge,
              let lastModel = last.modelFamilyKey,
              lastModel == activityModel
        else { return nil }

        let pair = zip(eligible.dropLast(), eligible.dropFirst()).reversed().first { pair in
            let (prior, newer) = pair
            guard prior.resetsAt == newer.resetsAt,
                  prior.source == newer.source,
                  prior.sourceSchema == newer.sourceSchema,
                  newer.source == last.source,
                  newer.sourceSchema == last.sourceSchema,
                  let priorModel = prior.modelFamilyKey,
                  let newerModel = newer.modelFamilyKey,
                  priorModel == newerModel,
                  newerModel == lastModel,
                  prior.modelFamilyKey == newer.modelFamilyKey,
                  let priorTokens = prior.activityTotalTokens,
                  let newerTokens = newer.activityTotalTokens
            else { return false }
            let tokenDelta = newerTokens - priorTokens
            let usedDelta = newer.usedPercent - prior.usedPercent
            return tokenDelta > 0 && usedDelta >= 0 && usedDelta <= 100
        }
        guard let pair,
              let priorTokens = pair.0.activityTotalTokens,
              let newerTokens = pair.1.activityTotalTokens
        else { return nil }
        let tokenDelta = newerTokens - priorTokens
        let usedDelta = pair.1.usedPercent - pair.0.usedPercent
        let coefficient = usedDelta / Double(tokenDelta)
        guard coefficient.isFinite, coefficient >= 0 else { return nil }

        let projectedUsed = min(
            100,
            max(last.usedPercent, last.usedPercent
                + coefficient * Double(activity.totalTokens - lastTokens))
        )
        var remaining = max(0, 100 - projectedUsed)
        if let previousEstimatedRemaining,
           previousEstimatedRemaining.isFinite,
           (0...100).contains(previousEstimatedRemaining) {
            remaining = min(remaining, previousEstimatedRemaining)
        }

        let age = now.timeIntervalSince(last.observedAt)
        var confidence: ClaudeSmartConfidence
        if eligible.count >= 3, age <= highConfidenceAge {
            confidence = .high
        } else if age <= mediumConfidenceAge {
            confidence = .medium
        } else {
            confidence = .low
        }
        // Locally visible activity cannot prove that another browser, device,
        // or computer was idle. A structural fallback digest also deliberately
        // undercounts ambiguous duplicates. Both facts cap confidence instead
        // of presenting invented precision.
        if confidence == .high {
            confidence = .medium
        }
        if activity.deduplicationConfidence == .conservative {
            confidence = .low
        }
        return ClaudeSmartWindowValue(
            windowKind: windowKind,
            remainingPercent: remaining,
            resetsAt: lastReset,
            observedAt: activity.observedAt,
            source: .estimatedLocal,
            confidence: confidence
        )
    }
}

enum ClaudeSmartSourceSelector {
    static let exactFreshnessInterval: TimeInterval = 5 * 60

    static func select(
        windowKind: AgentRateLimitWindow.Kind,
        statusLineAnchors: [ClaudeSmartWindowAnchor],
        safariAnchors: [ClaudeSmartWindowAnchor],
        estimate: ClaudeSmartWindowValue?,
        desktopEstimate: ClaudeSmartWindowValue? = nil,
        staleExact: ClaudeSmartWindowAnchor?,
        now: Date
    ) -> ClaudeSmartWindowValue? {
        if let anchor = latestCurrent(statusLineAnchors, kind: windowKind, now: now) {
            return exactValue(anchor)
        }
        if let anchor = latestCurrent(safariAnchors, kind: windowKind, now: now) {
            return exactValue(anchor)
        }
        if let estimated = [estimate, desktopEstimate]
            .compactMap({ $0 })
            .max(by: { $0.observedAt < $1.observedAt }) {
            return estimated
        }
        if let staleExact,
           let staleReset = staleExact.resetsAt,
           staleReset > now {
            return ClaudeSmartWindowValue(
                windowKind: staleExact.windowKind,
                remainingPercent: max(0, min(100, 100 - staleExact.usedPercent)),
                resetsAt: staleReset,
                observedAt: staleExact.observedAt,
                source: .staleExact,
                confidence: .insufficient
            )
        }
        return nil
    }

    private static func latestCurrent(
        _ anchors: [ClaudeSmartWindowAnchor],
        kind: AgentRateLimitWindow.Kind,
        now: Date
    ) -> ClaudeSmartWindowAnchor? {
        anchors.filter {
            $0.windowKind == kind
                && ($0.resetsAt.map { $0 > now }
                    ?? ($0.source == .exactSafariAccuracy))
                && now.timeIntervalSince($0.observedAt) >= 0
                && now.timeIntervalSince($0.observedAt) <= exactFreshnessInterval
        }
            .max { $0.observedAt < $1.observedAt }
    }

    private static func exactValue(
        _ anchor: ClaudeSmartWindowAnchor
    ) -> ClaudeSmartWindowValue {
        ClaudeSmartWindowValue(
            windowKind: anchor.windowKind,
            remainingPercent: max(0, min(100, 100 - anchor.usedPercent)),
            resetsAt: anchor.resetsAt,
            observedAt: anchor.observedAt,
            source: anchor.source,
            confidence: .high
        )
    }
}

protocol ClaudeSmartAnchorStoring: Sendable {
    func load() async -> [ClaudeSmartWindowAnchor]
    func save(_ anchors: [ClaudeSmartWindowAnchor]) async throws
    func clear() async throws
}

actor ClaudeSmartAnchorStore: ClaudeSmartAnchorStoring {
    private struct Envelope: Codable {
        static let schemaVersion = 2
        static let readableSchemaVersions: Set<Int> = [1, schemaVersion]
        let schemaVersion: Int
        let anchors: [ClaudeSmartWindowAnchor]
    }

    enum StoreError: Error, Equatable {
        case unsafePath
        case invalidData
        case oversized
        case writeFailed
        case commitVerificationFailed
        case simulatedCrashBeforeRename
        case simulatedCrashAfterRename
    }

    /// Deterministic fault points used to prove the two meaningful atomic
    /// replacement crash windows. Production always uses `.none`.
    enum CommitFault: Sendable {
        case none
        case beforeRename
        case afterRenameBeforeReadback
    }

    static let maximumEncodedBytes = 32 * 1_024
    private let url: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let commitFault: CommitFault
    private let allowsOwnedDirectoryPermissionMigration: Bool

    init(
        url: URL = ApplicationDataPaths.current().smartAnchorsURL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        commitFault: CommitFault = .none,
        allowsOwnedDirectoryPermissionMigration: Bool = false
    ) {
        self.url = url
        self.fileManager = fileManager
        self.now = now
        self.commitFault = commitFault
        self.allowsOwnedDirectoryPermissionMigration = allowsOwnedDirectoryPermissionMigration
    }

    func load() -> [ClaudeSmartWindowAnchor] {
        let loaded: Data?
        do {
            try prepareOwnedParentIfAuthorized()
            loaded = try ClaudeOwnedFileReader.read(
                at: url,
                maximumBytes: Self.maximumEncodedBytes
            )
        } catch {
            return []
        }
        guard let data = loaded,
              Self.hasStrictAllowlistedShape(data),
              let envelope = try? JSONDecoder.smart.decode(Envelope.self, from: data),
              Envelope.readableSchemaVersions.contains(envelope.schemaVersion),
              Self.validate(envelope.anchors)
        else { return [] }
        let active = Self.purgingExpired(envelope.anchors, now: now())
        if active != envelope.anchors || envelope.schemaVersion != Envelope.schemaVersion {
            do {
                try commit(active)
            } catch {
                // A stale or legacy file is never published unless its bounded
                // canonical replacement has itself committed and read back.
                return []
            }
        }
        return active
    }

    func save(_ anchors: [ClaudeSmartWindowAnchor]) throws {
        let bounded = Self.bounded(Self.purgingExpired(anchors, now: now()))
        guard Self.validate(bounded) else { throw StoreError.invalidData }
        try commit(bounded)
    }

    private func commit(_ bounded: [ClaudeSmartWindowAnchor]) throws {
        let envelope = Envelope(
            schemaVersion: Envelope.schemaVersion,
            anchors: bounded
        )
        let data = try JSONEncoder.smart.encode(envelope)
        guard data.count <= Self.maximumEncodedBytes else {
            throw StoreError.oversized
        }
        let parent = url.deletingLastPathComponent()
        guard !Self.hasSymlinkComponent(parent) else { throw StoreError.unsafePath }
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try prepareOwnedParentIfAuthorized()
        guard Self.isOwnerOnlyDirectory(parent), !Self.isSymlink(url) else {
            throw StoreError.unsafePath
        }
        if fileManager.fileExists(atPath: url.path), !Self.isOwnerOnlyRegularFile(url) {
            throw StoreError.unsafePath
        }

        let temporaryURL = parent.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        let descriptor = open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw StoreError.writeFailed }
        var shouldRemoveTemporary = true
        defer {
            close(descriptor)
            if shouldRemoveTemporary {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        do {
            try data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var written = 0
                while written < rawBuffer.count {
                    let count = Darwin.write(
                        descriptor,
                        base.advanced(by: written),
                        rawBuffer.count - written
                    )
                    guard count > 0 else { throw StoreError.writeFailed }
                    written += count
                }
            }
            guard fsync(descriptor) == 0,
                  Self.isOwnerOnlyRegularFile(temporaryURL),
                  let staged = try? Data(contentsOf: temporaryURL),
                  staged == data,
                  Self.decodesCanonicalEnvelope(staged, expected: bounded)
            else { throw StoreError.commitVerificationFailed }

            if case .beforeRename = commitFault {
                throw StoreError.simulatedCrashBeforeRename
            }
            guard rename(temporaryURL.path, url.path) == 0 else {
                throw StoreError.writeFailed
            }
            shouldRemoveTemporary = false

            let directoryDescriptor = open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard directoryDescriptor >= 0 else { throw StoreError.writeFailed }
            defer { close(directoryDescriptor) }
            guard fsync(directoryDescriptor) == 0 else { throw StoreError.writeFailed }

            if case .afterRenameBeforeReadback = commitFault {
                throw StoreError.simulatedCrashAfterRename
            }
            guard let committed = try? ClaudeOwnedFileReader.read(
                at: url,
                maximumBytes: Self.maximumEncodedBytes
            ),
                committed == data,
                Self.decodesCanonicalEnvelope(committed, expected: bounded)
            else { throw StoreError.commitVerificationFailed }
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.writeFailed
        }
    }

    func clear() throws {
        if fileManager.fileExists(atPath: url.path) {
            guard Self.isOwnerOnlyRegularFile(url) else { throw StoreError.unsafePath }
            try fileManager.removeItem(at: url)
        }
    }

    private static func bounded(
        _ anchors: [ClaudeSmartWindowAnchor]
    ) -> [ClaudeSmartWindowAnchor] {
        AgentRateLimitWindow.Kind.allSmartCases.flatMap { kind in
            anchors.filter { $0.windowKind == kind }
                .sorted { $0.observedAt > $1.observedAt }
                .prefix(ClaudeSmartUsageEstimator.maximumAnchorCountPerWindow)
        }.sorted { $0.observedAt < $1.observedAt }
    }

    private static func purgingExpired(
        _ anchors: [ClaudeSmartWindowAnchor],
        now: Date
    ) -> [ClaudeSmartWindowAnchor] {
        anchors.filter { anchor in
            let age = now.timeIntervalSince(anchor.observedAt)
            guard age >= 0 else { return true }
            if let reset = anchor.resetsAt {
                return reset > now
            }
            return anchor.source == .exactSafariAccuracy
                && age <= ClaudeSmartSourceSelector.exactFreshnessInterval
        }
    }

    private static func decodesCanonicalEnvelope(
        _ data: Data,
        expected: [ClaudeSmartWindowAnchor]
    ) -> Bool {
        guard hasStrictAllowlistedShape(data),
              let decoded = try? JSONDecoder.smart.decode(Envelope.self, from: data),
              decoded.schemaVersion == Envelope.schemaVersion,
              decoded.anchors == expected,
              validate(decoded.anchors)
        else { return false }
        return true
    }

    private static func hasStrictAllowlistedShape(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["schemaVersion", "anchors"],
              root["schemaVersion"] is NSNumber,
              let records = root["anchors"] as? [[String: Any]]
        else { return false }
        let required: Set<String> = [
            "windowKind", "usedPercent", "observedAt", "source",
            "sourceSchema", "continuityGeneration",
        ]
        let allowed = required.union([
            "resetsAt", "activityTotalTokens", "modelFamilyKey",
        ])
        return records.allSatisfy { record in
            required.isSubset(of: Set(record.keys))
                && Set(record.keys).isSubset(of: allowed)
        }
    }

    private static func validate(_ anchors: [ClaudeSmartWindowAnchor]) -> Bool {
        anchors.count <= ClaudeSmartUsageEstimator.maximumAnchorCountPerWindow * 2
            && anchors.allSatisfy {
                $0.usedPercent.isFinite
                    && (0...100).contains($0.usedPercent)
                    && ($0.resetsAt.map { $0.timeIntervalSince1970.isFinite } ?? true)
                    && ($0.resetsAt != nil || $0.source == .exactSafariAccuracy)
                    && $0.observedAt.timeIntervalSince1970.isFinite
                    && ($0.activityTotalTokens.map { $0 >= 0 } ?? true)
                    && ($0.source == .exactLocalStatusLine
                        || $0.source == .exactSafariAccuracy)
            }
    }

    /// Only the application composition opts into repairing its own legacy
    /// storage directory. Generic injected stores retain strict refusal.
    private func prepareOwnedParentIfAuthorized() throws {
        guard allowsOwnedDirectoryPermissionMigration else { return }
        let parent = url.deletingLastPathComponent()
        guard !Self.hasSymlinkComponent(parent), !Self.isSymlink(url) else {
            throw StoreError.unsafePath
        }
        guard fileManager.fileExists(atPath: parent.path) else { return }
        let descriptor = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StoreError.unsafePath }
        defer { close(descriptor) }
        var opened = stat()
        var named = stat()
        guard fstat(descriptor, &opened) == 0,
              lstat(parent.path, &named) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
              (opened.st_mode & S_IFMT) == S_IFDIR,
              opened.st_uid == getuid(), !Self.hasSymlinkComponent(parent)
        else { throw StoreError.unsafePath }
        if (opened.st_mode & 0o077) != 0 {
            guard fchmod(descriptor, 0o700) == 0 else { throw StoreError.unsafePath }
        }
        guard lstat(parent.path, &named) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
              Self.isOwnerOnlyDirectory(parent)
        else { throw StoreError.unsafePath }
    }

    private static func hasSymlinkComponent(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        while current.path != "/" {
            if isSymlink(current) { return true }
            current.deleteLastPathComponent()
        }
        return false
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func isOwnerOnlyRegularFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              !hasSymlinkComponent(url.deletingLastPathComponent()),
              !isSymlink(url)
        else { return false }
        var parent = stat()
        guard lstat(url.deletingLastPathComponent().path, &parent) == 0,
              (parent.st_mode & S_IFMT) == S_IFDIR,
              parent.st_uid == getuid(),
              (parent.st_mode & 0o077) == 0
        else { return false }
        var info = stat()
        return lstat(url.path, &info) == 0
            && (info.st_mode & S_IFMT) == S_IFREG
            && info.st_uid == getuid()
            && info.st_nlink == 1
            && (info.st_mode & 0o077) == 0
    }

    private static func isOwnerOnlyDirectory(_ url: URL) -> Bool {
        guard !hasSymlinkComponent(url), !isSymlink(url) else { return false }
        var info = stat()
        return lstat(url.path, &info) == 0
            && (info.st_mode & S_IFMT) == S_IFDIR
            && info.st_uid == getuid()
            && (info.st_mode & 0o077) == 0
    }
}

private extension AgentRateLimitWindow.Kind {
    static let allSmartCases: [Self] = [.fiveHour, .sevenDay]
}

private extension JSONEncoder {
    static var smart: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var smart: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
