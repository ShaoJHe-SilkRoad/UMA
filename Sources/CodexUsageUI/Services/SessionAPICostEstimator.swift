import CryptoKit
import Foundation

/// A deliberately narrow, local-only summary.  It is independent from the
/// provider account channel: no value here is presented as provider-reported
/// usage or as a bill.
struct CodexLocalActivitySnapshot: Sendable {
    enum Availability: Equatable, Sendable {
        case available
        case unavailable
    }

    struct Task: Sendable {
        let stableID: String
        let modifiedAt: Date
        let totalTokens: Int64
    }

    let availability: Availability
    let source: String
    let scope: String
    let capturedAt: Date
    let discoveredFileCount: Int
    let readableFileCount: Int
    let excludedFileCount: Int
    let tasks: [Task]
    let apiEquivalentCost: CodexAPICostEstimate?
    /// Connector-owned historical analytics are attached after this local
    /// metadata read. The reader never opens a ThreadOS source itself.
    let threadOSAnalytics: ThreadOSUsageAnalytics?

    init(
        availability: Availability,
        source: String,
        scope: String,
        capturedAt: Date,
        discoveredFileCount: Int,
        readableFileCount: Int,
        excludedFileCount: Int,
        tasks: [Task],
        apiEquivalentCost: CodexAPICostEstimate?,
        threadOSAnalytics: ThreadOSUsageAnalytics? = nil
    ) {
        self.availability = availability
        self.source = source
        self.scope = scope
        self.capturedAt = capturedAt
        self.discoveredFileCount = discoveredFileCount
        self.readableFileCount = readableFileCount
        self.excludedFileCount = excludedFileCount
        self.tasks = tasks
        self.apiEquivalentCost = apiEquivalentCost
        self.threadOSAnalytics = threadOSAnalytics
    }

    static func unavailable(now: Date) -> Self {
        Self(
            availability: .unavailable,
            source: "This Mac: Codex session metadata",
            scope: "No readable local session metadata",
            capturedAt: now,
            discoveredFileCount: 0,
            readableFileCount: 0,
            excludedFileCount: 0,
            tasks: [],
            apiEquivalentCost: nil
        )
    }
}

protocol CodexLocalActivityReading: Sendable {
    func read(now: Date) -> CodexLocalActivitySnapshot
}

/// Lets the connector acquire the bounded historical export before the sole
/// ledger mutation, while keeping injected test readers and other consumers
/// on the existing read-only protocol.
protocol CodexLocalActivityHistoricalAttributionReading: CodexLocalActivityReading {
    func read(now: Date, threadOSAnalytics: ThreadOSUsageAnalytics) -> CodexLocalActivitySnapshot
}

/// Optional capability for the built-in local metadata reader. Consumers that
/// need near-real-time local estimates can subscribe without teaching the
/// account connector anything about session files or their contents.
protocol CodexLocalActivityObservationProviding: CodexLocalActivityReading {
    func makeLocalActivityObserver(
        onChange: @escaping @Sendable () -> Void
    ) -> CodexLocalActivityObserver
}

/// Reads only the local Codex session metadata required to count tokens.  It
/// never reads account files, credentials, prompts, tool input/output, or
/// arbitrary JSON values.  Files outside the two declared roots, symlinks,
/// non-regular files, and oversized frames are excluded before opening.
struct CodexLocalActivityReader: CodexLocalActivityObservationProviding, CodexLocalActivityHistoricalAttributionReading, @unchecked Sendable {
    let sessionRoots: [URL]
    let ledgerURL: URL
    private let fileManager: FileManager
    /// In-memory metadata checkpoints prevent unchanged JSONL tails from
    /// being decoded again during the monitor's periodic refresh. The cache
    /// is intentionally process-local and contains no message content.
    private let checkpointCache = SessionMetadataCheckpointCache()
    /// Discovery is cached separately from tail summaries. An unchanged root
    /// signature plus unchanged known-file metadata reuses the prior manifest
    /// without walking either session directory again.
    private let discoveryCache = SessionMetadataDiscoveryCache()

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        ledgerURL: URL = APICostLedgerStore.defaultURL,
        fileManager: FileManager = .default
    ) {
        let codexRoot = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        self.init(
            sessionRoots: [
                codexRoot.appendingPathComponent("sessions", isDirectory: true),
                codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
            ],
            ledgerURL: ledgerURL,
            fileManager: fileManager
        )
    }

    init(
        sessionRoots: [URL],
        ledgerURL: URL,
        fileManager: FileManager = .default
    ) {
        self.sessionRoots = sessionRoots.map { $0.standardizedFileURL }
        self.ledgerURL = ledgerURL
        self.fileManager = fileManager
    }

    func read(now: Date = Date()) -> CodexLocalActivitySnapshot {
        read(now: now, threadOSAnalytics: .sourceGap(now: now))
    }

    func read(now: Date, threadOSAnalytics: ThreadOSUsageAnalytics) -> CodexLocalActivitySnapshot {
        let scan = discoveryCache.scan(roots: sessionRoots, fileManager: fileManager)
        checkpointCache.prune(keeping: Set(scan.files.map(\.stableID)))
        guard !scan.files.isEmpty else {
            return CodexLocalActivitySnapshot(
                availability: scan.rootsExist ? .available : .unavailable,
                source: "This Mac: Codex session metadata",
                scope: "sessions + archived_sessions; metadata-only tail scan",
                capturedAt: now,
                discoveredFileCount: scan.discoveredFileCount,
                readableFileCount: 0,
                excludedFileCount: scan.excludedFileCount,
                tasks: [],
                apiEquivalentCost: nil,
                threadOSAnalytics: threadOSAnalytics
            )
        }

        let parsedFiles = deduplicatedSessionFiles(scan.files.compactMap { file in
            checkpointCache.summary(for: file).map { ParsedSessionFile(file: file, summary: $0) }
        })

        let calendar = Calendar.current
        let parentSummaries = ParentSummaryIndex(parsedFiles: parsedFiles)
        var observations: [SessionFileObservation] = []
        var directTaskTotals: [String: Int64] = [:]
        for parsed in parsedFiles {
            // A session may be rotated from the live root into the archive,
            // or renamed, after a previous read.  Its admitted native ID is
            // the only identity that survives that operation.  Keep the
            // opaque path-derived ID exclusively as the compatibility
            // fallback for old metadata without a native ID.
            let ledgerSessionID = stableLedgerSessionID(
                nativeSessionIdentifier: parsed.summary.sessionIdentifier,
                legacyPathIdentifier: parsed.file.stableID
            )
            let inheritedBaseline = parentSummaries.baseline(for: parsed.summary)
            let requiresInheritedBaseline = parsed.summary.parentSessionIdentifier != nil
            let rawCounts = TokenCounts(summary: parsed.summary)
            let directCounts: TokenCounts?
            if let inheritedBaseline {
                directCounts = rawCounts.delta(since: inheritedBaseline)
            } else {
                directCounts = requiresInheritedBaseline ? nil : rawCounts
            }
            if let directCounts {
                directTaskTotals[parsed.file.stableID] = directCounts.totalTokens
            }
            let fallbackDate = parsed.file.createdAt ?? parsed.file.modifiedAt
            observations.append(SessionFileObservation(
                ledgerSessionID: ledgerSessionID,
                legacySessionID: parsed.file.stableID,
                taskStableID: parsed.file.stableID,
                summary: parsed.summary,
                initialUsageDay: usageDay(for: parsed.summary.observedAt ?? fallbackDate, calendar: calendar),
                incrementalUsageDay: usageDay(for: parsed.summary.observedAt ?? parsed.file.modifiedAt, calendar: calendar),
                priceDate: parsed.summary.observedAt,
                localTransitionEvidence: localTransitionEvidence(for: parsed.summary),
                inheritedBaseline: inheritedBaseline,
                requiresInheritedBaseline: requiresInheritedBaseline,
                intervalPartitions: matchedIntervalPartitions(
                    sessionID: ledgerSessionID,
                    summary: parsed.summary,
                    inheritedBaseline: inheritedBaseline,
                    analytics: threadOSAnalytics
                )
            ))
        }

        let recording = SessionAPICostEstimator.record(
            observations: observations,
            now: now,
            ledgerURL: ledgerURL
        )
        let displayedAnalytics = recording == nil ? threadOSAnalytics : ledgerBackedAnalytics(
            threadOSAnalytics,
            ledger: recording!.ledger
        )
        var tasks: [CodexLocalActivitySnapshot.Task] = []
        for parsed in parsedFiles {
            guard let totalTokens = recording?.currentTokenTotals[parsed.file.stableID]
                ?? directTaskTotals[parsed.file.stableID]
            else { continue }
            tasks.append(.init(
                stableID: parsed.file.stableID,
                modifiedAt: parsed.file.modifiedAt,
                totalTokens: totalTokens
            ))
        }
        let recentTasks = tasks.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(3)
        return CodexLocalActivitySnapshot(
            availability: .available,
            source: "This Mac: Codex session metadata",
            scope: "sessions + archived_sessions; metadata-only tail scan",
            capturedAt: now,
            discoveredFileCount: scan.discoveredFileCount,
            readableFileCount: observations.count,
            excludedFileCount: scan.excludedFileCount,
            tasks: Array(recentTasks),
            apiEquivalentCost: recording?.estimate,
            threadOSAnalytics: displayedAnalytics
        )
    }

    /// The observer shares only transient path/signature invalidations with
    /// this reader. It never forwards a JSONL frame or any unallowlisted
    /// content to its callback.
    func makeLocalActivityObserver(
        onChange: @escaping @Sendable () -> Void
    ) -> CodexLocalActivityObserver {
        CodexLocalActivityObserver(
            sessionRoots: sessionRoots,
            onFilesystemChange: { [discoveryCache] change in
                discoveryCache.recordFilesystemChange(change)
            },
            onChange: onChange
        )
    }
}

/// API-equivalent pricing is a local estimate only.  The ledger records only
/// monotonically increasing token deltas and preserves the price snapshot that
/// was used for each delta; it never changes provider account usage.
enum SessionAPICostEstimator {
    private static let ledgerLock = NSLock()

    static func estimate(
        now: Date = Date(),
        ledgerURL: URL = APICostLedgerStore.defaultURL
    ) -> CodexAPICostEstimate? {
        CodexLocalActivityReader(ledgerURL: ledgerURL).read(now: now).apiEquivalentCost
    }

    static func estimatedUSD(
        model: String,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64
    ) -> Double? {
        guard let price = APIModelPrice.price(for: model) else { return nil }
        return estimatedUSD(
            price: price,
            counts: TokenCounts(
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens,
                totalTokens: max(0, inputTokens) + max(0, outputTokens)
            )
        )
    }

    static func estimatedUSD(price: APIModelPrice, counts: TokenCounts) -> Double {
        let cachedInput = min(counts.cachedInputTokens, counts.inputTokens)
        let uncachedInput = max(0, counts.inputTokens - cachedInput)
        return Double(uncachedInput) / 1_000_000 * price.inputPerMillion
            + Double(cachedInput) / 1_000_000 * price.cachedInputPerMillion
            + Double(counts.outputTokens) / 1_000_000 * price.outputPerMillion
    }

    fileprivate static func record(
        observations: [SessionFileObservation],
        now: Date,
        ledgerURL: URL
    ) -> CostRecording? {
        ledgerLock.lock()
        defer { ledgerLock.unlock() }
        do {
            let store = APICostLedgerStore(url: ledgerURL)
            var ledger = try store.load()
            var didChange = false
            var currentTokenTotals: [String: Int64] = [:]
            for observation in observations {
                if let outcome = ledger.observeDetailed(
                    sessionID: observation.ledgerSessionID,
                    legacySessionID: observation.legacySessionID,
                    summary: observation.summary,
                    initialUsageDay: observation.initialUsageDay,
                    incrementalUsageDay: observation.incrementalUsageDay,
                    price: APIModelPrice.price(
                        for: observation.summary.model,
                        observedAt: observation.priceDate
                    ),
                    inheritedBaseline: observation.inheritedBaseline,
                    requiresInheritedBaseline: observation.requiresInheritedBaseline,
                    intervalPartitions: observation.intervalPartitions,
                    localTransitionEvidence: observation.localTransitionEvidence
                ) {
                    currentTokenTotals[observation.taskStableID] = outcome.current.totalTokens
                    didChange = didChange || outcome.didChange
                }
            }
            if didChange { try store.save(ledger) }
            return CostRecording(
                estimate: ledger.estimate(sevenDayKeys: sevenDayKeys(now: now, calendar: .current)),
                currentTokenTotals: currentTokenTotals,
                ledger: ledger
            )
        } catch {
            return nil
        }
    }
}

private struct SessionFileObservation {
    let ledgerSessionID: String
    /// Exact TU2-compatible key for this currently observed file. It is used
    /// only to adopt its direct checkpoint, never to infer a cross-path alias.
    let legacySessionID: String
    let taskStableID: String
    let summary: SessionTokenSummary
    let initialUsageDay: String
    let incrementalUsageDay: String
    let priceDate: Date?
    /// Independently decoded, bounded local model state for the aggregate
    /// remainder. Producer matching cannot add, remove, or alter this proof.
    let localTransitionEvidence: APICostLedger.LocalTransitionEvidence
    let inheritedBaseline: TokenCounts?
    let requiresInheritedBaseline: Bool
    let intervalPartitions: [APICostLedger.IntervalPartition]
}

/// Persists only a domain-separated native identity for newly observed
/// sessions. Path-derived IDs remain the compatibility lane for historical
/// metadata that never contained a native session ID; existing ledger records
/// are deliberately left immutable.
private func stableLedgerSessionID(
    nativeSessionIdentifier: String?,
    legacyPathIdentifier: String
) -> String {
    guard let nativeSessionIdentifier else { return legacyPathIdentifier }
    return domainSeparatedDigest(
        domain: "uma.api-cost-ledger.v1:session",
        value: nativeSessionIdentifier
    )
}

/// Only COMPLETE exporter rows can become ledger partitions. A partition ID
/// binds this local session file, exact producer thread/turn, and the ending
/// counter so refreshes and archived/live duplicates cannot coalesce.
private func matchedIntervalPartitions(
    sessionID: String,
    summary: SessionTokenSummary,
    inheritedBaseline: TokenCounts?,
    analytics: ThreadOSUsageAnalytics
) -> [APICostLedger.IntervalPartition] {
    guard analytics.sourceStatus == .available else { return [] }
    return summary.localIntervals.compactMap { interval in
        guard let intervalModel = interval.model,
              let row = ThreadOSHistoricalAttributionMatcher.uniquelyMatchedRow(for: interval, in: analytics),
              let preceding = interval.preceding,
              let ending = interval.ending,
              let adjustedPreceding = adjustedCounter(preceding, by: inheritedBaseline),
              let adjustedEnding = adjustedCounter(ending, by: inheritedBaseline),
              let delta = adjustedEnding.delta(since: adjustedPreceding),
              let observedStart = interval.startedAt,
              let observedEnd = interval.endedAt,
              observedEnd >= observedStart,
              delta.totalTokens > 0
        else { return nil }
        let counter = "\(ending.inputTokens):\(ending.cachedInputTokens):\(ending.outputTokens):\(ending.totalTokens)"
        let identity = stableAttributionIntervalID(sessionID: sessionID, thread: row.threadDigest, turn: row.turnDigest, counter: counter)
        let price = APIModelPrice.price(for: intervalModel, observedAt: observedEnd)
        return .init(
            attributionIntervalID: identity,
            counts: delta,
            preceding: adjustedPreceding,
            ending: adjustedEnding,
            projection: .init(
                projectKey: row.projectKey,
                projectRootDigest: row.projectRootDigest,
                taskID: row.taskID,
                localRole: row.localRole,
                threadDigest: row.threadDigest,
                turnDigest: row.turnDigest,
                intervalID: identity,
                model: intervalModel,
                counts: delta,
                observedStart: observedStart,
                observedEnd: observedEnd
            ),
            model: intervalModel,
            price: price,
            hasValidatedPrice: true
        )
    }
}

/// Preserve local turn-transition evidence before producer matching. The
/// ledger uses this alongside its existing checkpoint model; it never assigns
/// a residual by partition position or counter-size coincidence.
private func localTransitionEvidence(for summary: SessionTokenSummary) -> APICostLedger.LocalTransitionEvidence {
    .init(
        models: summary.localIntervals.compactMap { interval in
            // A source gap cannot form a producer partition, but a bounded
            // local turn model remains transition evidence. Retaining it
            // prevents a later matching interval from masking A→B→A as a
            // same-model aggregate continuation.
            interval.disposition == .ambiguous ? nil : interval.model
        },
        hasUnknownOrAmbiguousInterval: summary.localIntervals.contains {
            $0.disposition == .ambiguous
                || $0.model == nil
        }
    )
}

/// Partition bounds and ledger checkpoints must use the same coordinate
/// system. A child session's raw counters include inherited parent history;
/// convert both interval ends before asking the ledger whether an interval is
/// inside the newly observed child high-water window.
private func adjustedCounter(
    _ counter: TokenCounts,
    by inheritedBaseline: TokenCounts?
) -> TokenCounts? {
    guard let inheritedBaseline else { return counter }
    return counter.delta(since: inheritedBaseline)
}

private func stableAttributionIntervalID(sessionID: String, thread: String, turn: String, counter: String) -> String {
    let material = "threados.apicost.interval.v1:\(sessionID):\(thread):\(turn):\(counter)"
    return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// This projection is intentionally reconstructed only from accepted frozen
/// exporter identities plus an exact local interval. It never labels a whole
/// session lifetime with the latest task or role.
private func ledgerBackedAnalytics(
    _ analytics: ThreadOSUsageAnalytics,
    ledger: APICostLedger
) -> ThreadOSUsageAnalytics {
    guard analytics.sourceStatus == .available else { return analytics }
    let rows = ledger.records.compactMap { record -> ThreadOSUsageAnalytics.Row? in
        guard let projection = record.projection
        else { return nil }
        guard let root = projection.projectRootDigest, let thread = projection.threadDigest, let turn = projection.turnDigest else { return nil }
        let sources = analytics.rows.filter { $0.projectKey == projection.projectKey && $0.projectRootDigest == root && $0.taskID == projection.taskID && $0.localRole == projection.localRole && $0.threadDigest == thread && $0.turnDigest == turn }
        guard sources.count == 1, let source = sources.first else { return nil }
        return .init(projectKey: projection.projectKey, projectRootDigest: source.projectRootDigest, taskID: projection.taskID, localRole: projection.localRole, threadDigest: source.threadDigest, turnDigest: source.turnDigest, observation: source.observation, waveID: nil, model: projection.model, inputTokens: projection.counts.inputTokens, cachedInputTokens: projection.counts.cachedInputTokens, outputTokens: projection.counts.outputTokens, totalTokens: projection.counts.totalTokens, observedStart: projection.observedStart, observedEnd: projection.observedEnd, apiEquivalentUSD: record.price == nil ? nil : record.usd, isPriceKnown: record.price != nil, intervalID: projection.intervalID)
    }
    let knownLocalTokens = ledger.records.reduce(Int64(0)) { $0 + $1.counts.totalTokens }
    let matchedLocalTokens = ledger.records.reduce(Int64(0)) { partial, record in
        record.projection == nil ? partial : partial + record.counts.totalTokens
    }
    let coverage = knownLocalTokens > 0
        ? ThreadOSUsageAnalytics.LocalLedgerCoverage(
            knownLocalTokens: knownLocalTokens,
            matchedLocalTokens: matchedLocalTokens
        )
        : nil
    return .init(
        sourceStatus: analytics.sourceStatus,
        rows: rows,
        unavailableCount: analytics.unavailableCount,
        capturedAt: analytics.capturedAt,
        localLedgerCoverage: coverage
    )
}

private struct CostRecording {
    let estimate: CodexAPICostEstimate?
    let currentTokenTotals: [String: Int64]
    let ledger: APICostLedger
}

private struct ParsedSessionFile {
    let file: SessionMetadataFile
    let summary: SessionTokenSummary
}

/// A session can briefly exist in both live and archived roots during local
/// rotation. The session identifier is metadata already admitted by the
/// reader, so retain one deterministic high-water representative instead of
/// charging the same logical session twice.
private func deduplicatedSessionFiles(_ files: [ParsedSessionFile]) -> [ParsedSessionFile] {
    var anonymous: [ParsedSessionFile] = []
    var bySessionIdentifier: [String: ParsedSessionFile] = [:]
    for file in files {
        guard let identifier = file.summary.sessionIdentifier else {
            anonymous.append(file)
            continue
        }
        guard let existing = bySessionIdentifier[identifier] else {
            bySessionIdentifier[identifier] = file
            continue
        }
        let existingDate = existing.summary.observedAt ?? .distantPast
        let candidateDate = file.summary.observedAt ?? .distantPast
        if file.summary.totalTokens > existing.summary.totalTokens
            || (file.summary.totalTokens == existing.summary.totalTokens
                && (candidateDate > existingDate
                    || (candidateDate == existingDate && file.file.stableID < existing.file.stableID))) {
            bySessionIdentifier[identifier] = file
        }
    }
    return anonymous + bySessionIdentifier.values
}

private struct ParentSummaryIndex {
    private let summaries: [String: SessionTokenSummary]
    private let ambiguousIdentifiers: Set<String>

    init(parsedFiles: [ParsedSessionFile]) {
        var summaries: [String: SessionTokenSummary] = [:]
        var ambiguousIdentifiers = Set<String>()
        for parsed in parsedFiles {
            guard let identifier = parsed.summary.sessionIdentifier else { continue }
            if summaries[identifier] != nil {
                ambiguousIdentifiers.insert(identifier)
                summaries.removeValue(forKey: identifier)
            } else if !ambiguousIdentifiers.contains(identifier) {
                summaries[identifier] = parsed.summary
            }
        }
        self.summaries = summaries
        self.ambiguousIdentifiers = ambiguousIdentifiers
    }

    func baseline(for child: SessionTokenSummary) -> TokenCounts? {
        guard let parentIdentifier = child.parentSessionIdentifier,
              !ambiguousIdentifiers.contains(parentIdentifier),
              let parent = summaries[parentIdentifier]
        else { return nil }
        return parent.inheritedBaseline()
    }
}

struct SessionMetadataFile {
    let url: URL
    let stableID: String
    let size: Int
    let modifiedAt: Date
    let createdAt: Date?
    let signature: SessionFileSignature
}

struct SessionFileSignature: Equatable, Sendable {
    let size: Int
    let modifiedAt: Date
}

struct SessionMetadataScan {
    let rootsExist: Bool
    let discoveredFileCount: Int
    let excludedFileCount: Int
    let files: [SessionMetadataFile]
}

/// The cache payload is intentionally transient and contains no source text.
/// A continuation is admitted only after its boundary digest proves the file
/// still contains the exact previously consumed bytes.
struct SessionMetadataRead {
    let summary: SessionTokenSummary
    let continuation: ThreadOSLocalIntervalDecoder.Continuation?
    /// Test-visible accounting for this one read path. It is never persisted
    /// and contains only byte counts, not session text.
    let bytesRead: Int
    let bytesDecoded: Int
    let fileIdentity: UInt64?
}

enum SessionMetadataScanner {
    private static let tailBytes = 1_048_576
    private static let checkpointBytes = 64 * 1024

    static func scan(roots: [URL], fileManager: FileManager) -> SessionMetadataScan {
        var rootsExist = false
        var discovered = 0
        var excluded = 0
        var files: [SessionMetadataFile] = []
        var seenStableIDs = Set<String>()

        for (rootIndex, candidateRoot) in roots.enumerated() {
            let root = candidateRoot.standardizedFileURL
            let rootCategory = SessionRootCategory(root: root, ordinal: rootIndex)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            rootsExist = true
            guard let rootValues = try? root.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  rootValues.isSymbolicLink != true,
                  isDirectory.boolValue,
                  let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  )
            else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
                discovered += 1
                let standardized = url.standardizedFileURL
                guard standardized.path.hasPrefix(root.path + "/"),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      let size = values.fileSize,
                      let modifiedAt = values.contentModificationDate
                else {
                    excluded += 1
                    continue
                }
                let stableID = stableID(
                    for: standardized,
                    beneath: root,
                    rootCategory: rootCategory
                )
                guard seenStableIDs.insert(stableID).inserted else { continue }
                files.append(.init(
                    url: standardized,
                    stableID: stableID,
                    size: size,
                    modifiedAt: modifiedAt,
                    createdAt: values.creationDate,
                    signature: SessionFileSignature(size: size, modifiedAt: modifiedAt)
                ))
            }
        }
        return SessionMetadataScan(rootsExist: rootsExist, discoveredFileCount: discovered, excludedFileCount: excluded, files: files)
    }

    /// Returns only allowlisted regular JSONL paths. This is used solely to
    /// attach filesystem watches; it neither opens files nor decodes content.
    static func watchableFileURLs(
        roots: [URL],
        fileManager: FileManager,
        limit: Int = CodexLocalActivityObserver.maximumFileWatchCount
    ) -> [URL] {
        watchableFileURLs(
            in: scan(roots: roots, fileManager: fileManager),
            limit: limit
        )
    }

    static func watchableFileURLs(
        in scan: SessionMetadataScan,
        limit: Int = CodexLocalActivityObserver.maximumFileWatchCount
    ) -> [URL] {
        let files = scan.files
            .sorted { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt {
                    return lhs.modifiedAt > rhs.modifiedAt
                }
                return lhs.url.path < rhs.url.path
            }
        return files.prefix(max(0, limit)).map(\.url)
    }

    static func stableID(
        for file: URL,
        beneath root: URL,
        rootCategory: SessionRootCategory
    ) -> String {
        let relative = file.path.dropFirst(root.path.count)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in (rootCategory.value + "\u{0}" + String(relative)).utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        // The category prefix is intentional: two identically named files in
        // `sessions` and `archived_sessions` must never share a ledger
        // checkpoint, while the path itself remains opaque.
        return "\(rootCategory.value):\(String(format: "%016llx", hash))"
    }

    static func readSummary(from url: URL, fileSize: Int) -> SessionMetadataRead? {
        guard fileSize > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            let amount = min(fileSize, tailBytes)
            try handle.seek(toOffset: UInt64(max(0, fileSize - amount)))
            // `fileSize` may be a proven continuation boundary rather than
            // the physical EOF. Never let an unterminated suffix alter the
            // aggregate counters that accompany a decoder-bounded append.
            let data = try handle.read(upToCount: amount) ?? Data()
            let completeData = completedJSONLData(data)
            let orderedLines = completeData.split(separator: 0x0A).map(Data.init)
            // A tail that starts after byte zero has no independently proven
            // header/baseline. It may still support aggregate accounting, but
            // cannot manufacture an interval attribution context.
            let decoded = fileSize <= tailBytes
                ? ThreadOSLocalIntervalDecoder.decodeContinuing(lines: orderedLines)
                : nil
            let localIntervals = decoded?.candidates ?? []
            var tokenUsage: SessionTokenUsage?
            var tokenObservedAt: Date?
            var tokenCheckpoints: [TokenCountCheckpoint] = []
            var model: String?
            var sessionIdentifier: String?
            var parentSessionIdentifier: String?
            var forkedAt: Date?
            for rawLine in data.split(separator: 0x0A).reversed() {
                guard let line = try? JSONDecoder().decode(SessionMetadataLine.self, from: Data(rawLine)) else { continue }
                let timestamp = line.timestamp?.date ?? line.payload?.timestamp?.date
                if line.type == "event_msg",
                   line.payload?.type == "token_count",
                   let usage = line.payload?.info?.totalTokenUsage {
                    if tokenUsage == nil {
                        tokenUsage = usage
                        tokenObservedAt = timestamp
                    }
                    if let timestamp, tokenCheckpoints.count < 256 {
                        tokenCheckpoints.append(.init(
                            capturedAt: timestamp,
                            counts: TokenCounts(
                                inputTokens: usage.inputTokens,
                                cachedInputTokens: usage.cachedInputTokens,
                                outputTokens: usage.outputTokens,
                                totalTokens: usage.totalTokens
                            )
                        ))
                    }
                }
                if model == nil,
                   line.type == "turn_context" {
                    model = line.payload?.model
                }
                if sessionIdentifier == nil,
                   line.type == "session_meta" || line.type == "turn_context" {
                    sessionIdentifier = allowedIdentifier(line.payload?.sessionIdentifier ?? line.identifier)
                }
                if parentSessionIdentifier == nil,
                   let parent = allowedIdentifier(line.payload?.parentOrForkIdentifier ?? line.parentOrForkIdentifier) {
                    parentSessionIdentifier = parent
                    forkedAt = timestamp
                }
            }
            guard let tokenUsage, tokenUsage.totalTokens > 0 else { return nil }
            // A tail may legitimately omit the turn context that preceded it.
            // Keep aggregate accounting available, but never borrow an older
            // model to price that unknown crossing.
            let resolvedModel = model ?? "UNKNOWN"
            // A local candidate is not producer attribution. Until an
            // admitted producer row uniquely matches the same interval under
            // the frozen contract, the ledger must retain aggregate costs
            // without an attribution identity.
            let summary = SessionTokenSummary(
                model: resolvedModel,
                inputTokens: tokenUsage.inputTokens,
                cachedInputTokens: tokenUsage.cachedInputTokens,
                outputTokens: tokenUsage.outputTokens,
                totalTokens: tokenUsage.totalTokens,
                sessionIdentifier: sessionIdentifier,
                parentSessionIdentifier: parentSessionIdentifier,
                forkedAt: forkedAt,
                observedAt: tokenObservedAt,
                tokenCheckpoints: tokenCheckpoints,
                localIntervals: localIntervals,
                attributionIntervalID: nil
            )
            var continuation = decoded?.continuation
            var checkpointRead = 0
            if continuation != nil {
                // The continuation stops before an unterminated final frame.
                // A later append replays that frame together with its newline.
                continuation?.byteOffset = fileSize - data.count + completeData.count
                let checkpoint = boundaryDigest(from: url, endingAt: continuation?.byteOffset ?? 0)
                continuation?.boundaryDigest = checkpoint?.value
                checkpointRead = checkpoint?.bytesRead ?? 0
                if var decodedContinuation = continuation {
                    decodedContinuation.contextWitnesses = contextWitnesses(
                        in: completeData,
                        baseOffset: fileSize - data.count,
                        continuation: decodedContinuation,
                        retaining: []
                    )
                    continuation = decodedContinuation
                }
            }
            return SessionMetadataRead(
                summary: summary,
                continuation: continuation,
                bytesRead: data.count + checkpointRead,
                bytesDecoded: completeData.count,
                fileIdentity: fileIdentity(for: url)
            )
        } catch { return nil }
    }

    /// Continues only a proven contiguous append. A changed file with an
    /// unknown prefix, a shrink, a replaced boundary, or an incomplete frame
    /// is deliberately re-read without interval attribution.
    static func readAppendedSummary(
        from url: URL,
        fileSize: Int,
        previous: SessionMetadataRead
    ) -> SessionMetadataRead? {
        guard var continuation = previous.continuation,
              continuation.byteOffset > 0,
              continuation.byteOffset < fileSize,
              fileSize - continuation.byteOffset <= tailBytes,
              let previousIdentity = previous.fileIdentity,
              previousIdentity == fileIdentity(for: url),
              let previousCheckpoint = boundaryDigest(from: url, endingAt: continuation.byteOffset),
              continuation.boundaryDigest == previousCheckpoint.value,
              (continuation.contextWitnesses.isEmpty || contextWitnessesMatch(continuation.contextWitnesses, in: url)),
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(continuation.byteOffset))
            let appended = try handle.readToEnd() ?? Data()
            // A trailing partial frame is retained only as an offset; it is
            // never decoded until a later append terminates it with a newline.
            guard let newline = appended.lastIndex(of: 0x0A), newline > appended.startIndex else {
                return SessionMetadataRead(
                    // A valid JSON object without a newline is still an
                    // uncommitted append frame on this continuation path.
                    // Keep the admitted aggregate stable until its terminator
                    // arrives, even though a cold read may inspect it.
                    summary: previous.summary,
                    continuation: continuation,
                    bytesRead: previousCheckpoint.bytesRead + appended.count,
                    bytesDecoded: 0,
                    fileIdentity: previousIdentity
                )
            }
            let complete = appended.prefix(through: newline)
            // The aggregate summary and local decoder must stop at the same
            // committed JSONL boundary. A syntactically valid but
            // unterminated final frame stays outside both until its newline
            // arrives on a later contiguous append.
            let aggregateBoundary = continuation.byteOffset + complete.count
            guard let aggregateRead = readSummary(from: url, fileSize: aggregateBoundary) else {
                return nil
            }
            let decoded = ThreadOSLocalIntervalDecoder.decodeContinuing(
                lines: complete.split(separator: 0x0A).map(Data.init),
                continuation: continuation
            )
            let previousContinuation = continuation
            continuation = decoded.continuation
            continuation.byteOffset += complete.count
            let nextCheckpoint = boundaryDigest(from: url, endingAt: continuation.byteOffset)
            continuation.boundaryDigest = nextCheckpoint?.value
            continuation.contextWitnesses = contextWitnesses(
                in: Data(complete),
                baseOffset: previousContinuation.byteOffset,
                continuation: continuation,
                retaining: previousContinuation.contextWitnesses,
                contextChanged: previousContinuation.activeTurnDigest != continuation.activeTurnDigest
                    || previousContinuation.activeModel != continuation.activeModel
            )
            let summary = SessionTokenSummary(
                model: aggregateRead.summary.model,
                inputTokens: aggregateRead.summary.inputTokens,
                cachedInputTokens: aggregateRead.summary.cachedInputTokens,
                outputTokens: aggregateRead.summary.outputTokens,
                totalTokens: aggregateRead.summary.totalTokens,
                sessionIdentifier: aggregateRead.summary.sessionIdentifier ?? previous.summary.sessionIdentifier,
                parentSessionIdentifier: aggregateRead.summary.parentSessionIdentifier ?? previous.summary.parentSessionIdentifier,
                forkedAt: aggregateRead.summary.forkedAt ?? previous.summary.forkedAt,
                observedAt: aggregateRead.summary.observedAt,
                tokenCheckpoints: aggregateRead.summary.tokenCheckpoints,
                localIntervals: decoded.candidates,
                attributionIntervalID: nil
            )
            return SessionMetadataRead(
                summary: summary,
                continuation: continuation,
                bytesRead: previousCheckpoint.bytesRead + appended.count + aggregateRead.bytesRead + (nextCheckpoint?.bytesRead ?? 0),
                bytesDecoded: complete.count + aggregateRead.bytesDecoded,
                fileIdentity: previousIdentity
            )
        } catch { return nil }
    }

    /// This fixed checkpoint plus an unchanged filesystem identity proves the
    /// local append boundary without rescanning historical bytes. A missing
    /// identity or changed checkpoint is unproven and therefore rejected.
    private static func boundaryDigest(from url: URL, endingAt offset: Int) -> (value: String, bytesRead: Int)? {
        guard offset >= 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let width = min(checkpointBytes, offset)
        do {
            try handle.seek(toOffset: UInt64(offset - width))
            let data = try handle.read(upToCount: width) ?? Data()
            guard data.count == width else { return nil }
            let value = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return (value, data.count)
        } catch { return nil }
    }

    private static func fileIdentity(for url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    private static func contextWitnessesMatch(_ witnesses: [SessionContextWitness], in url: URL) -> Bool {
        guard !witnesses.isEmpty, let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        for witness in witnesses {
            guard witness.offset >= 0, witness.length > 0,
                  (try? handle.seek(toOffset: UInt64(witness.offset))) != nil,
                  let data = try? handle.read(upToCount: witness.length),
                  data.count == witness.length,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == witness.digest
            else { return false }
        }
        return true
    }

    private static func contextWitnesses(
        in data: Data,
        baseOffset: Int,
        continuation: ThreadOSLocalIntervalDecoder.Continuation,
        retaining existing: [SessionContextWitness],
        contextChanged: Bool = true
    ) -> [SessionContextWitness] {
        var found: [SessionContextWitnessKind: SessionContextWitness] = [:]
        var offset = 0
        for rawLine in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
            defer { offset += rawLine.count + 1 }
            guard !rawLine.isEmpty,
                  let line = try? JSONDecoder().decode(SessionMetadataLine.self, from: Data(rawLine))
            else { continue }
            let payload = line.payload
            let lifecycleType = line.type == "event_msg" ? payload?.type : line.type
            let kind: SessionContextWitnessKind?
            if line.type == "session_meta",
               let identifier = allowedIdentifier(payload?.id),
               domainSeparatedDigest(domain: "threados.usage-attribution.v1:thread", value: identifier) == continuation.nativeThreadDigest {
                kind = .header
            } else if lifecycleType == "task_started",
                      let turn = allowedIdentifier(payload?.turnID),
                      domainSeparatedDigest(domain: "threados.usage-attribution.v1:turn", value: turn) == continuation.activeTurnDigest {
                kind = .activeStart
            } else if lifecycleType == "turn_context",
                      let turn = allowedIdentifier(payload?.turnID),
                      domainSeparatedDigest(domain: "threados.usage-attribution.v1:turn", value: turn) == continuation.activeTurnDigest,
                      allowedModel(payload?.model) == continuation.activeModel {
                kind = .activeContext
            } else {
                kind = nil
            }
            if let kind {
                let raw = Data(rawLine)
                found[kind] = .init(
                    kind: kind,
                    offset: baseOffset + offset,
                    length: raw.count,
                    digest: SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
                )
            }
        }
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.kind, $0) })
        if contextChanged {
            merged.removeValue(forKey: .activeStart)
            merged.removeValue(forKey: .activeContext)
        }
        for (kind, witness) in found { merged[kind] = witness }
        if continuation.activeTurnDigest == nil {
            merged.removeValue(forKey: .activeStart)
            merged.removeValue(forKey: .activeContext)
        }
        return [.header, .activeStart, .activeContext].compactMap { merged[$0] }
    }

    private static func completedJSONLData(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        guard data.last != 0x0A else { return data }
        // JSONL writers commonly leave their final complete record without a
        // newline. Admit it only when this narrow metadata decoder can prove
        // it is a complete allowlisted frame; otherwise retain it for a later
        // append that supplies the terminator.
        let finalFrame: Data
        if let newline = data.lastIndex(of: 0x0A) {
            finalFrame = Data(data[data.index(after: newline)...])
        } else {
            finalFrame = data
        }
        if (try? JSONDecoder().decode(SessionMetadataLine.self, from: finalFrame)) != nil {
            return data
        }
        guard let newline = data.lastIndex(of: 0x0A) else { return Data() }
        return Data(data[...newline])
    }
}

struct SessionRootCategory {
    let value: String

    init(root: URL, ordinal: Int) {
        switch root.lastPathComponent {
        case "sessions": value = "sessions"
        case "archived_sessions": value = "archived_sessions"
        default: value = "custom-\(ordinal)"
        }
    }
}

/// Keeps directory discovery incremental without persisting local paths or
/// content. The first read walks allowlisted roots. Later reads reuse that
/// manifest when the roots and all known files retain the same metadata; a
/// changed root or known-file signature forces a fresh safe discovery pass.
private final class SessionMetadataDiscoveryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var rootSignatures: [SessionRootSignature]?
    private var cachedScan: SessionMetadataScan?
    private var pendingFilesystemChanges = Set<URL>()
    private var rootsNeedRescan = false

    func scan(roots: [URL], fileManager: FileManager) -> SessionMetadataScan {
        let signatures = roots.map { SessionRootSignature.make(for: $0, fileManager: fileManager) }
        lock.lock()
        let priorSignatures = rootSignatures
        let priorScan = cachedScan
        let pendingChanges = pendingFilesystemChanges
        let needsRescan = rootsNeedRescan
        pendingFilesystemChanges.removeAll()
        rootsNeedRescan = false
        lock.unlock()

        if !needsRescan,
           priorSignatures == signatures,
           let priorScan,
           !pendingChanges.isEmpty,
           let refreshed = refreshingOnlyChangedFiles(
               priorScan,
               changedPaths: pendingChanges,
               roots: roots,
               fileManager: fileManager
           ) {
            lock.lock()
            rootSignatures = signatures
            cachedScan = refreshed
            lock.unlock()
            return refreshed
        }

        if priorSignatures == signatures,
           let priorScan,
           pendingChanges.isEmpty,
           manifestIsCurrent(priorScan, fileManager: fileManager) {
            return priorScan
        }

        let fresh = SessionMetadataScanner.scan(roots: roots, fileManager: fileManager)
        lock.lock()
        rootSignatures = signatures
        cachedScan = fresh
        lock.unlock()
        return fresh
    }

    func recordFilesystemChange(_ change: CodexLocalActivityFilesystemChange) {
        lock.lock()
        switch change {
        case .file(let url):
            pendingFilesystemChanges.insert(url.standardizedFileURL)
        case .roots:
            rootsNeedRescan = true
        }
        lock.unlock()
    }

    /// Updates metadata for a file that a direct file watch identified. New,
    /// renamed, or deleted paths are deliberately escalated to a root rescan;
    /// ordinary appends and rewrites do not walk unchanged history.
    private func refreshingOnlyChangedFiles(
        _ scan: SessionMetadataScan,
        changedPaths: Set<URL>,
        roots: [URL],
        fileManager: FileManager
    ) -> SessionMetadataScan? {
        var filesByID = Dictionary(uniqueKeysWithValues: scan.files.map { ($0.stableID, $0) })
        for changed in changedPaths {
            guard changed.pathExtension.lowercased() == "jsonl",
                  let rootIndex = roots.firstIndex(where: { changed.path.hasPrefix($0.standardizedFileURL.path + "/") })
            else { return nil }
            let root = roots[rootIndex].standardizedFileURL
            let rootCategory = SessionRootCategory(root: root, ordinal: rootIndex)
            let stableID = SessionMetadataScanner.stableID(
                for: changed,
                beneath: root,
                rootCategory: rootCategory
            )
            guard let oldFile = filesByID[stableID],
                  fileManager.fileExists(atPath: changed.path),
                  let values = freshResourceValues(for: changed, keys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .creationDateKey
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  let modifiedAt = values.contentModificationDate
            else { return nil }
            filesByID[stableID] = SessionMetadataFile(
                url: changed,
                stableID: stableID,
                size: size,
                modifiedAt: modifiedAt,
                createdAt: values.creationDate ?? oldFile.createdAt,
                signature: SessionFileSignature(size: size, modifiedAt: modifiedAt)
            )
        }
        return SessionMetadataScan(
            rootsExist: scan.rootsExist,
            discoveredFileCount: scan.discoveredFileCount,
            excludedFileCount: scan.excludedFileCount,
            files: Array(filesByID.values)
        )
    }

    private func manifestIsCurrent(
        _ scan: SessionMetadataScan,
        fileManager: FileManager
    ) -> Bool {
        for file in scan.files {
            guard fileManager.fileExists(atPath: file.url.path),
                  let values = freshResourceValues(for: file.url, keys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  let modifiedAt = values.contentModificationDate,
                  SessionFileSignature(size: size, modifiedAt: modifiedAt) == file.signature
            else { return false }
        }
        return true
    }
}

private struct SessionRootSignature: Equatable {
    let root: URL
    let exists: Bool
    let modifiedAt: Date?
    let isDirectory: Bool
    let isSymbolicLink: Bool

    static func make(for candidate: URL, fileManager: FileManager) -> Self {
        let root = candidate.standardizedFileURL
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory)
        let values = freshResourceValues(for: root, keys: [
            .contentModificationDateKey,
            .isSymbolicLinkKey
        ])
        return Self(
            root: root,
            exists: exists,
            modifiedAt: values?.contentModificationDate,
            isDirectory: isDirectory.boolValue,
            isSymbolicLink: values?.isSymbolicLink == true
        )
    }
}

/// Foundation may retain URL resource values across rapid same-length writes.
/// Discovery signatures are an explicit filesystem boundary, so refresh only
/// the small metadata key set used by the existing cache before comparing it.
/// This neither adds a scanner nor changes the observer/refresh cadence.
private func freshResourceValues(
    for url: URL,
    keys: Set<URLResourceKey>
) -> URLResourceValues? {
    var refreshedURL = url
    for key in keys { try? refreshedURL.removeCachedResourceValue(forKey: key) }
    return try? refreshedURL.resourceValues(forKeys: keys)
}

/// Metadata checkpoints are in-memory only. A cache hit avoids reopening and
/// tail-decoding an unchanged session file, while a changed size or mtime is a
/// hard invalidation boundary. Negative parses are cached too, so malformed
/// unchanged tails do not turn into periodic main-thread I/O churn.
private final class SessionMetadataCheckpointCache: @unchecked Sendable {
    private struct Entry {
        let signature: SessionFileSignature
        let read: SessionMetadataRead?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func summary(for file: SessionMetadataFile) -> SessionTokenSummary? {
        lock.lock()
        let cached = entries[file.stableID]
        lock.unlock()
        if cached?.signature == file.signature {
            return cached?.read?.summary
        }

        let parsed = cached?.read.flatMap {
            SessionMetadataScanner.readAppendedSummary(from: file.url, fileSize: file.size, previous: $0)
        } ?? SessionMetadataScanner.readSummary(from: file.url, fileSize: file.size)
        lock.lock()
        entries[file.stableID] = Entry(signature: file.signature, read: parsed)
        lock.unlock()
        return parsed?.summary
    }

    func prune(keeping stableIDs: Set<String>) {
        lock.lock()
        entries = entries.filter { stableIDs.contains($0.key) }
        lock.unlock()
    }
}

/// Intentionally narrow Decodable shapes. Unknown fields (including prompts,
/// messages, tool calls, paths, and account data) are skipped by the decoder.
private struct SessionMetadataLine: Decodable {
    let type: String?
    let id: String?
    let parentID: String?
    let forkID: String?
    let forkedFromID: String?
    let timestamp: SessionTimestamp?
    let payload: Payload?

    enum CodingKeys: String, CodingKey {
        case type, id, timestamp
        case parentID = "parent_id"
        case forkID = "fork_id"
        case forkedFromID = "forked_from_id"
        case payload
    }

    var identifier: String? { id }
    var parentOrForkIdentifier: String? { parentID ?? forkID ?? forkedFromID }

    struct Payload: Decodable {
        let type: String?
        let model: String?
        let id: String?
        let turnID: String?
        let sessionID: String?
        let parentID: String?
        let parentSessionID: String?
        let forkID: String?
        let forkSessionID: String?
        let forkedFromID: String?
        let forkedFromSessionID: String?
        let timestamp: SessionTimestamp?
        let info: Info?

        enum CodingKeys: String, CodingKey {
            case type, model, id, timestamp, info
            case turnID = "turn_id"
            case sessionID = "session_id"
            case parentID = "parent_id"
            case parentSessionID = "parent_session_id"
            case forkID = "fork_id"
            case forkSessionID = "fork_session_id"
            case forkedFromID = "forked_from_id"
            case forkedFromSessionID = "forked_from_session_id"
        }

        var sessionIdentifier: String? { sessionID ?? id }
        var parentOrForkIdentifier: String? {
            parentSessionID ?? parentID ?? forkSessionID ?? forkID
                ?? forkedFromSessionID ?? forkedFromID
        }
    }

    struct Info: Decodable {
        let totalTokenUsage: SessionTokenUsage?
        enum CodingKeys: String, CodingKey { case totalTokenUsage = "total_token_usage" }
    }
}

/// A local, transient projection of one token delta whose enclosing native
/// thread and turn are both present in the admitted session metadata.  The
/// projection deliberately exposes only versioned digests, counters, and the
/// model recorded by that turn.  It is not durable attribution and cannot
/// establish ThreadOS execution or model admission on its own.
struct ThreadOSLocalIntervalCandidate: Equatable, Sendable {
    enum Disposition: Equatable, Sendable {
        case candidate
        case sourceGap
        case ambiguous
    }

    let disposition: Disposition
    let nativeThreadDigest: String?
    let turnDigest: String?
    let model: String?
    let preceding: TokenCounts?
    let ending: TokenCounts?
    let startedAt: Date?
    let endedAt: Date?
}

enum SessionContextWitnessKind: Hashable, Sendable {
    case header
    case activeStart
    case activeContext
}

/// An opaque, bounded proof of each source record that supplies retained
/// decoder context. It records a byte range and its digest, never the record.
struct SessionContextWitness: Sendable {
    let kind: SessionContextWitnessKind
    let offset: Int
    let length: Int
    let digest: String
}

/// Decodes only the narrowly allowlisted session metadata needed to form
/// ordered token intervals.  It accepts complete JSONL records in file order;
/// callers must never use it as a general session-record decoder.  A missing
/// header, lifecycle boundary, or preceding checkpoint fails closed as a
/// SOURCE_GAP. Conflicting local context never gets assigned to either turn.
enum ThreadOSLocalIntervalDecoder {
    /// Process-local continuation deliberately retains only allowlisted
    /// identity digests, lifecycle/counter state, and an exact byte offset.
    /// It never holds JSON text, prompts, tool data, paths, or account data.
    struct Continuation: Sendable {
        var nativeThreadDigest: String?
        var activeTurnDigest: String?
        var activeModel: String?
        var activeStartedAt: Date?
        var previousCheckpoint: TokenCountCheckpoint?
        var contextIsAmbiguous = false
        var byteOffset = 0
        var boundaryDigest: String?
        var contextWitnesses: [SessionContextWitness] = []
    }

    static func decode(lines: [Data]) -> [ThreadOSLocalIntervalCandidate] {
        decodeContinuing(lines: lines).candidates
    }

    static func decodeContinuing(lines: [Data], continuation: Continuation = .init()) -> (candidates: [ThreadOSLocalIntervalCandidate], continuation: Continuation) {
        var results: [ThreadOSLocalIntervalCandidate] = []
        var state = continuation

        for rawLine in lines {
            guard let line = try? JSONDecoder().decode(SessionMetadataLine.self, from: rawLine) else {
                // A malformed record leaves the next delta without a proven
                // continuation rather than letting stale context bridge it.
                state.activeTurnDigest = nil
                state.previousCheckpoint = nil
                state.contextIsAmbiguous = true
                continue
            }
            let timestamp = line.timestamp?.date ?? line.payload?.timestamp?.date
            let payload = line.payload
            let lifecycleType = line.type == "event_msg" ? payload?.type : line.type

            if line.type == "session_meta", let identifier = allowedIdentifier(payload?.id) {
                let digest = threadDigest(identifier)
                if let nativeThreadDigest = state.nativeThreadDigest, nativeThreadDigest != digest {
                    state.contextIsAmbiguous = true
                } else {
                    state.nativeThreadDigest = digest
                }
            }

            if lifecycleType == "task_started", let turn = allowedIdentifier(payload?.turnID) {
                guard state.activeTurnDigest == nil else {
                    state.activeTurnDigest = nil
                    state.previousCheckpoint = nil
                    state.contextIsAmbiguous = true
                    continue
                }
                state.activeTurnDigest = turnDigest(turn)
                state.activeModel = nil
                state.activeStartedAt = timestamp
                // A turn boundary cannot inherit a preceding turn's token
                // counter. The first checkpoint is therefore intentionally
                // unattributable; only a subsequent delta can be considered.
                state.previousCheckpoint = nil
                state.contextIsAmbiguous = false
            }

            if lifecycleType == "turn_context", let turn = allowedIdentifier(payload?.turnID) {
                let model = allowedModel(payload?.model)
                let digest = turnDigest(turn)
                if state.activeTurnDigest == digest {
                    if let known = state.activeModel, let model, known != model {
                        state.contextIsAmbiguous = true
                    } else {
                        state.activeModel = state.activeModel ?? model
                    }
                } else if state.activeTurnDigest != nil {
                    // A checkpoint may not cross turn contexts.
                    state.contextIsAmbiguous = true
                    state.activeTurnDigest = digest
                    state.activeModel = model
                    state.activeStartedAt = nil
                } else {
                    // A context is not a lifecycle start. Keep it useful for
                    // diagnostics but fail closed until task_started exists.
                    state.activeTurnDigest = digest
                    state.activeModel = model
                    state.activeStartedAt = nil
                }
            }

            if lifecycleType == "task_complete", let turn = allowedIdentifier(payload?.turnID) {
                guard state.activeTurnDigest == turnDigest(turn) else {
                    state.contextIsAmbiguous = true
                    continue
                }
                state.activeTurnDigest = nil
                state.activeModel = nil
                state.activeStartedAt = nil
            }

            guard line.type == "event_msg", payload?.type == "token_count",
                  let usage = payload?.info?.totalTokenUsage,
                  let timestamp
            else { continue }
            let ending = TokenCountCheckpoint(capturedAt: timestamp, counts: TokenCounts(
                inputTokens: usage.inputTokens,
                cachedInputTokens: usage.cachedInputTokens,
                outputTokens: usage.outputTokens,
                totalTokens: usage.totalTokens
            ))
            defer { state.previousCheckpoint = ending }

            guard let previousCheckpoint = state.previousCheckpoint,
                  let nativeThreadDigest = state.nativeThreadDigest,
                  let turnDigest = state.activeTurnDigest,
                  let model = state.activeModel,
                  state.activeStartedAt != nil,
                  !state.contextIsAmbiguous,
                  ending.capturedAt > previousCheckpoint.capturedAt,
                  ending.counts.delta(since: previousCheckpoint.counts) != nil
            else {
                results.append(.init(
                    disposition: state.contextIsAmbiguous ? .ambiguous : .sourceGap,
                    nativeThreadDigest: state.nativeThreadDigest,
                    turnDigest: state.activeTurnDigest,
                    model: state.activeModel,
                    preceding: state.previousCheckpoint?.counts,
                    ending: ending.counts,
                    startedAt: state.activeStartedAt,
                    endedAt: timestamp
                ))
                continue
            }
            results.append(.init(
                disposition: .candidate,
                nativeThreadDigest: nativeThreadDigest,
                turnDigest: turnDigest,
                model: model,
                preceding: previousCheckpoint.counts,
                ending: ending.counts,
                startedAt: state.activeStartedAt,
                endedAt: timestamp
            ))
        }
        return (results, state)
    }

    private static func threadDigest(_ value: String) -> String {
        domainSeparatedDigest(domain: "threados.usage-attribution.v1:thread", value: value)
    }

    private static func turnDigest(_ value: String) -> String {
        domainSeparatedDigest(domain: "threados.usage-attribution.v1:turn", value: value)
    }
}

private func allowedModel(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value.utf8.count <= 128 else { return nil }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
    return value.unicodeScalars.allSatisfy { allowed.contains($0) } ? value : nil
}

/// SHA-256 is used only to avoid retaining raw local identifiers in the
/// projection. The domain strings are pinned to the frozen producer contract;
/// equality remains necessary but not sufficient for attribution.
private func domainSeparatedDigest(domain: String, value: String) -> String {
    SHA256.hash(data: Data("\(domain):\(value)".utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

/// Decodes only an event timestamp. Both ISO-8601 strings and numeric seconds
/// (or milliseconds) are supported because Codex session metadata has used
/// both encodings; invalid values are deliberately treated as unavailable.
private struct SessionTimestamp: Decodable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self), seconds.isFinite {
            let normalized = abs(seconds) > 10_000_000_000 ? seconds / 1_000 : seconds
            date = Date(timeIntervalSince1970: normalized)
            return
        }
        let raw = try container.decode(String.self)
        if let parsed = ISO8601DateFormatter().date(from: raw) {
            date = parsed
            return
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: raw) {
            date = parsed
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid metadata timestamp")
    }
}

private func allowedIdentifier(_ value: String?) -> String? {
    guard let value, !value.isEmpty, value.utf8.count <= 256 else { return nil }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
    guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
    return value
}

private struct SessionTokenUsage: Decodable {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try values.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try values.decodeIfPresent(Int64.self, forKey: .cachedInputTokens) ?? 0
        outputTokens = try values.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0
        totalTokens = try values.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? (inputTokens + outputTokens)
    }
}

private func sevenDayKeys(now: Date, calendar: Calendar) -> Set<String> {
    let today = calendar.startOfDay(for: now)
    return Set((0..<7).compactMap { offset in
        calendar.date(byAdding: .day, value: -offset, to: today).map { usageDay(for: $0, calendar: calendar) }
    })
}

private func usageDay(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
}
