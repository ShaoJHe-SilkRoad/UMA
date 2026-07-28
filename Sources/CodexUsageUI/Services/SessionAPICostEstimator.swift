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
struct CodexLocalActivityReader: CodexLocalActivityObservationProviding, @unchecked Sendable {
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
                apiEquivalentCost: nil
            )
        }

        let parsedFiles = scan.files.compactMap { file in
            checkpointCache.summary(for: file).map { ParsedSessionFile(file: file, summary: $0) }
        }

        let calendar = Calendar.current
        let parentSummaries = ParentSummaryIndex(parsedFiles: parsedFiles)
        var observations: [SessionFileObservation] = []
        var directTaskTotals: [String: Int64] = [:]
        for parsed in parsedFiles {
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
                sessionID: parsed.file.stableID,
                summary: parsed.summary,
                initialUsageDay: usageDay(for: parsed.summary.observedAt ?? fallbackDate, calendar: calendar),
                incrementalUsageDay: usageDay(for: parsed.summary.observedAt ?? parsed.file.modifiedAt, calendar: calendar),
                priceDate: parsed.summary.observedAt,
                inheritedBaseline: inheritedBaseline,
                requiresInheritedBaseline: requiresInheritedBaseline
            ))
        }

        let recording = SessionAPICostEstimator.record(
            observations: observations,
            now: now,
            ledgerURL: ledgerURL
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
            apiEquivalentCost: recording?.estimate
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
                    sessionID: observation.sessionID,
                    summary: observation.summary,
                    initialUsageDay: observation.initialUsageDay,
                    incrementalUsageDay: observation.incrementalUsageDay,
                    price: APIModelPrice.price(
                        for: observation.summary.model,
                        observedAt: observation.priceDate
                    ),
                    inheritedBaseline: observation.inheritedBaseline,
                    requiresInheritedBaseline: observation.requiresInheritedBaseline
                ) {
                    currentTokenTotals[observation.sessionID] = outcome.current.totalTokens
                    didChange = didChange || outcome.didChange
                }
            }
            if didChange { try store.save(ledger) }
            return CostRecording(
                estimate: ledger.estimate(sevenDayKeys: sevenDayKeys(now: now, calendar: .current)),
                currentTokenTotals: currentTokenTotals
            )
        } catch {
            return nil
        }
    }
}

private struct SessionFileObservation {
    let sessionID: String
    let summary: SessionTokenSummary
    let initialUsageDay: String
    let incrementalUsageDay: String
    let priceDate: Date?
    let inheritedBaseline: TokenCounts?
    let requiresInheritedBaseline: Bool
}

private struct CostRecording {
    let estimate: CodexAPICostEstimate?
    let currentTokenTotals: [String: Int64]
}

private struct ParsedSessionFile {
    let file: SessionMetadataFile
    let summary: SessionTokenSummary
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

enum SessionMetadataScanner {
    private static let tailBytes = 1_048_576

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

    static func readSummary(from url: URL, fileSize: Int) -> SessionTokenSummary? {
        guard fileSize > 0, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            let amount = min(fileSize, tailBytes)
            try handle.seek(toOffset: UInt64(max(0, fileSize - amount)))
            let data = try handle.readToEnd() ?? Data()
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
            guard let tokenUsage, let model, tokenUsage.totalTokens > 0 else { return nil }
            return SessionTokenSummary(
                model: model,
                inputTokens: tokenUsage.inputTokens,
                cachedInputTokens: tokenUsage.cachedInputTokens,
                outputTokens: tokenUsage.outputTokens,
                totalTokens: tokenUsage.totalTokens,
                sessionIdentifier: sessionIdentifier,
                parentSessionIdentifier: parentSessionIdentifier,
                forkedAt: forkedAt,
                observedAt: tokenObservedAt,
                tokenCheckpoints: tokenCheckpoints
            )
        } catch { return nil }
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
                  let values = try? changed.resourceValues(forKeys: [
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
                  let values = try? file.url.resourceValues(forKeys: [
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
        let values = try? root.resourceValues(forKeys: [
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

/// Metadata checkpoints are in-memory only. A cache hit avoids reopening and
/// tail-decoding an unchanged session file, while a changed size or mtime is a
/// hard invalidation boundary. Negative parses are cached too, so malformed
/// unchanged tails do not turn into periodic main-thread I/O churn.
private final class SessionMetadataCheckpointCache: @unchecked Sendable {
    private struct Entry {
        let signature: SessionFileSignature
        let summary: SessionTokenSummary?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func summary(for file: SessionMetadataFile) -> SessionTokenSummary? {
        lock.lock()
        let cached = entries[file.stableID]
        lock.unlock()
        if cached?.signature == file.signature {
            return cached?.summary
        }

        let parsed = SessionMetadataScanner.readSummary(from: file.url, fileSize: file.size)
        lock.lock()
        entries[file.stableID] = Entry(signature: file.signature, summary: parsed)
        lock.unlock()
        return parsed
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
