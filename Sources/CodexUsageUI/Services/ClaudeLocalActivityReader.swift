import CryptoKit
import Darwin
import Foundation
import CoreServices

/// Published Claude list prices in US dollars per one million tokens.
///
/// These are list prices only. No billing, invoice, payment, or account
/// information is read to obtain or apply them. The catalogue is a frozen
/// snapshot; `catalogueVersion` records which snapshot produced an estimate.
enum ClaudeModelPrice: Sendable {
    enum Family: String, Sendable, Equatable {
        case opus
        case sonnet
        case haiku
        case fable
        case unknown
    }

    struct Rate: Sendable, Equatable {
        let displayName: String
        let inputPerMillion: Double
        let outputPerMillion: Double
    }

    static let catalogueVersion = "2026-08-08-list"

    /// Documented prompt-caching multipliers applied to the base input rate.
    static let cacheReadMultiplier = 0.1
    static let fiveMinuteCacheWriteMultiplier = 1.25
    static let oneHourCacheWriteMultiplier = 2.0

    private static let opus = Rate(displayName: "Opus", inputPerMillion: 5, outputPerMillion: 25)
    private static let sonnet = Rate(displayName: "Sonnet", inputPerMillion: 3, outputPerMillion: 15)
    private static let haiku = Rate(displayName: "Haiku", inputPerMillion: 1, outputPerMillion: 5)
    private static let fable = Rate(displayName: "Fable", inputPerMillion: 10, outputPerMillion: 50)

    /// Exact identifiers first, then family prefixes so a dated snapshot such
    /// as `claude-haiku-4-5-20251001` still prices. An unrecognized identifier
    /// returns nil on purpose: its tokens stay in the observed total and lower
    /// reported coverage rather than being valued at zero.
    static func rate(forModel identifier: String) -> Rate? {
        rate(forFamily: family(forModel: identifier))
    }

    static func family(forModel identifier: String) -> Family {
        let id = identifier.lowercased()
        switch id {
        case "claude-fable-5", "claude-mythos-5": return .fable
        case "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7",
             "claude-opus-4-6", "claude-opus-4-5": return .opus
        case "claude-sonnet-5", "claude-sonnet-4-6", "claude-sonnet-4-5": return .sonnet
        case "claude-haiku-4-5": return .haiku
        default: break
        }
        if id.hasPrefix("claude-fable") || id.hasPrefix("claude-mythos") { return .fable }
        if id.hasPrefix("claude-opus") { return .opus }
        if id.hasPrefix("claude-sonnet") { return .sonnet }
        if id.hasPrefix("claude-haiku") { return .haiku }
        return .unknown
    }

    static func rate(forFamily family: Family) -> Rate? {
        switch family {
        case .opus: opus
        case .sonnet: sonnet
        case .haiku: haiku
        case .fable: fable
        case .unknown: nil
        }
    }
}

/// Four independent, non-negative token buckets.
///
/// Claude reports these as disjoint values on each assistant message, unlike
/// the nested input/cached-input shape used elsewhere in this app. Modelling
/// cache reads as a subset of input here would be arithmetically wrong.
struct ClaudeTokenCounts: Sendable, Equatable {
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let fiveMinuteCacheWriteTokens: Int64
    let oneHourCacheWriteTokens: Int64

    var totalTokens: Int64 {
        inputTokens + outputTokens + cacheReadTokens
            + fiveMinuteCacheWriteTokens + oneHourCacheWriteTokens
    }

    func estimatedUSD(rate: ClaudeModelPrice.Rate) -> Double {
        let million = 1_000_000.0
        return Double(inputTokens) / million * rate.inputPerMillion
            + Double(outputTokens) / million * rate.outputPerMillion
            + Double(cacheReadTokens) / million * rate.inputPerMillion
                * ClaudeModelPrice.cacheReadMultiplier
            + Double(fiveMinuteCacheWriteTokens) / million * rate.inputPerMillion
                * ClaudeModelPrice.fiveMinuteCacheWriteMultiplier
            + Double(oneHourCacheWriteTokens) / million * rate.inputPerMillion
                * ClaudeModelPrice.oneHourCacheWriteMultiplier
    }
}

/// One immediately projected assistant response worth of accounting. Dedupe
/// derives only from allowlisted timestamp, closed model family, and token counts.
/// Provider identifiers and the raw model identifier cannot cross the transient
/// JSON parsing boundary.
struct ClaudeLocalUsageRecord: Sendable, Equatable {
    enum DedupeConfidence: String, Sendable, Equatable {
        case conservativeStructural
    }

    let dedupeDigest: String
    let dedupeConfidence: DedupeConfidence
    let modelFamily: ClaudeModelPrice.Family
    let observedAt: Date
    let counts: ClaudeTokenCounts
}

enum ClaudeLocalActivitySurface: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case claudeDesktop = "claude-desktop"

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .claudeDesktop: "Claude Desktop"
        }
    }
}

enum ClaudeLocalDeduplicationConfidence: String, Codable, Sendable {
    case exact
    case conservative
}

/// Aggregate-only per-session value. Carries no identifier and no path.
struct ClaudeLocalActivityTask: Sendable, Equatable {
    let totalTokens: Int64
    let modifiedAt: Date
}

struct ClaudeAPICostEstimate: Sendable, Equatable {
    let sevenDayUSD: Double
    let lifetimeUSD: Double
    let pricedTokens: Int64
    let observedTokens: Int64
    let recognizedModelCount: Int
    /// Catalogue display names, never a raw model identifier echoed from a log.
    let modelNames: [String]
}

struct ClaudeLocalActivitySnapshot: Sendable {
    enum Availability: Sendable, Equatable { case available, unavailable }

    let availability: Availability
    let source: String
    let scope: String
    let capturedAt: Date
    let discoveredFileCount: Int
    let readableFileCount: Int
    let excludedFileCount: Int
    /// At most three, most recently written first.
    let tasks: [ClaudeLocalActivityTask]
    let apiEquivalentCost: ClaudeAPICostEstimate?
    let observedSurfaces: Set<ClaudeLocalActivitySurface>
    let deduplicationConfidence: ClaudeLocalDeduplicationConfidence

    init(
        availability: Availability,
        source: String,
        scope: String,
        capturedAt: Date,
        discoveredFileCount: Int,
        readableFileCount: Int,
        excludedFileCount: Int,
        tasks: [ClaudeLocalActivityTask],
        apiEquivalentCost: ClaudeAPICostEstimate?,
        observedSurfaces: Set<ClaudeLocalActivitySurface> = [],
        deduplicationConfidence: ClaudeLocalDeduplicationConfidence = .exact
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
        self.observedSurfaces = observedSurfaces
        self.deduplicationConfidence = deduplicationConfidence
    }

    static func unavailable(capturedAt: Date) -> ClaudeLocalActivitySnapshot {
        ClaudeLocalActivitySnapshot(
            availability: .unavailable,
            source: "No readable local Claude session metadata",
            scope: "unavailable",
            capturedAt: capturedAt,
            discoveredFileCount: 0,
            readableFileCount: 0,
            excludedFileCount: 0,
            tasks: [],
            apiEquivalentCost: nil
        )
    }
}

protocol ClaudeLocalActivityReading: Sendable {
    func read(now: Date) -> ClaudeLocalActivitySnapshot
}

protocol ClaudeLocalActivityObservationProviding: ClaudeLocalActivityReading {
    func makeLocalActivityObserver(
        onChange: @escaping @Sendable () -> Void
    ) -> CodexLocalActivityObserver
}

struct ClaudeLocalSurfaceDetector: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let applicationsDirectory: URL
    private let registeredApplicationPaths: @Sendable () -> [String]
    private let bundleIdentifier: @Sendable (String) -> String?

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        registeredApplicationPaths: (@Sendable () -> [String])? = nil,
        bundleIdentifier: @escaping @Sendable (String) -> String? = { Bundle(path: $0)?.bundleIdentifier }
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.applicationsDirectory = applicationsDirectory
        self.bundleIdentifier = bundleIdentifier
        self.registeredApplicationPaths = registeredApplicationPaths ?? {
            // Fixture roots must not fall through to the host's registry.
            guard applicationsDirectory.path == "/Applications",
                  homeDirectory == FileManager.default.homeDirectoryForCurrentUser else { return [] }
            let urls = LSCopyApplicationURLsForBundleIdentifier("com.anthropic.claudefordesktop" as CFString, nil)?
                .takeRetainedValue() as? [URL] ?? []
            return urls.map(\.path)
        }
    }

    var claudeDesktopInstalled: Bool {
        [applicationsDirectory.appendingPathComponent("Claude.app"),
         homeDirectory.appendingPathComponent("Applications/Claude.app")]
            .contains { fileManager.fileExists(atPath: $0.path) }
            || registeredApplicationPaths().contains {
                bundleIdentifier($0) == "com.anthropic.claudefordesktop"
                    && fileManager.fileExists(atPath: $0)
            }
    }

    var statusLineCapableSurfaceInstalled: Bool {
        cliCandidates.contains { fileManager.isExecutableFile(atPath: $0.path) }
            || ideExtensionRoots.contains { containsClaudeCodeExtension(in: $0) }
    }

    var detectedSurfaces: Set<ClaudeLocalActivitySurface> {
        var surfaces: Set<ClaudeLocalActivitySurface> = []
        if claudeDesktopInstalled { surfaces.insert(.claudeDesktop) }
        if statusLineCapableSurfaceInstalled { surfaces.insert(.claudeCode) }
        return surfaces
    }

    private var cliCandidates: [URL] {
        [
            homeDirectory.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
    }

    private var ideExtensionRoots: [URL] {
        [
            homeDirectory.appendingPathComponent(".vscode/extensions", isDirectory: true),
            homeDirectory.appendingPathComponent(".cursor/extensions", isDirectory: true),
            homeDirectory.appendingPathComponent(".windsurf/extensions", isDirectory: true),
        ]
    }

    private func containsClaudeCodeExtension(in root: URL) -> Bool {
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        return children.contains {
            $0.lastPathComponent.lowercased().hasPrefix("anthropic.claude-code-")
        }
    }
}

/// Bounded, allowlisted reader over Claude Code's own local session records.
///
/// Local Smart Mode invokes this reader only for an explicit local refresh and
/// immediately projects its result to aggregate token/model/time coverage.
/// Prompt, response, tool, path, project and session content are neither
/// represented nor retained. Account truth still comes only from an exact
/// official status-line or one-shot Accuracy anchor; local activity can only
/// calibrate a visibly estimated value. No raw-record ledger is persisted.
struct ClaudeLocalActivityReader: ClaudeLocalActivityObservationProviding {
    struct Source: Sendable, Equatable {
        enum Layout: Sendable, Equatable {
            case projectsRoot
        }

        let surface: ClaudeLocalActivitySurface
        let rootDirectory: URL
        let layout: Layout
    }

    enum Bounds {
        static let maximumFileCount = 256
        static let maximumBytesPerFile = 64 * 1_024 * 1_024
        static let maximumBytesPerLine = 1 * 1_024 * 1_024
        static let maximumTotalBytes = 512 * 1_024 * 1_024
        static let maximumRecordCount = 200_000
        static let recentTaskCount = 3
    }

    private let sources: [Source]
    private let calendar: Calendar
    private let afterFileReadForTesting: (@Sendable (URL) -> Void)?

    init(rootDirectory: URL? = nil, calendar: Calendar = .current) {
        if let rootDirectory {
            sources = [Source(
                surface: .claudeCode,
                rootDirectory: rootDirectory,
                layout: .projectsRoot
            )]
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            sources = Self.defaultSources(homeDirectory: home)
        }
        self.calendar = calendar
        afterFileReadForTesting = nil
    }

    init(
        sources: [Source],
        calendar: Calendar = .current,
        afterFileReadForTesting: (@Sendable (URL) -> Void)? = nil
    ) {
        self.sources = sources
        self.calendar = calendar
        self.afterFileReadForTesting = afterFileReadForTesting
    }

    static func defaultSources(homeDirectory: URL) -> [Source] {
        [
            Source(
                surface: .claudeCode,
                rootDirectory: homeDirectory
                    .appendingPathComponent(".claude", isDirectory: true)
                    .appendingPathComponent("projects", isDirectory: true),
                layout: .projectsRoot
            ),
        ]
    }

    func makeLocalActivityObserver(
        onChange: @escaping @Sendable () -> Void
    ) -> CodexLocalActivityObserver {
        CodexLocalActivityObserver(
            sessionRoots: sources.map(\.rootDirectory),
            onChange: onChange
        )
    }

    func read(now: Date = Date()) -> ClaudeLocalActivitySnapshot {
        let discovered = sessionFiles()
        guard !discovered.isEmpty else { return .unavailable(capturedAt: now) }

        var seenRequestDigests = Set<String>()
        var recognizedModels = Set<String>()
        var modelTokenTotals: [String: Int64] = [:]
        var observedSurfaces = Set<ClaudeLocalActivitySurface>()
        var deduplicationConfidence = ClaudeLocalDeduplicationConfidence.exact
        var observedTokens: Int64 = 0
        var pricedTokens: Int64 = 0
        var lifetimeUSD = 0.0
        var sevenDayUSD = 0.0
        var perFile: [ClaudeLocalActivityTask] = []
        var totalBytes = 0
        var recordCount = 0
        var readableFileCount = 0
        var excludedFileCount = 0
        let recentDays = Self.sevenDayKeys(now: now, calendar: calendar)

        for discoveredFile in discovered {
            let file = discoveredFile.url
            let remainingBudget = Bounds.maximumTotalBytes - totalBytes
            guard remainingBudget > 0 else {
                excludedFileCount += 1
                continue
            }
            // Keep every per-file projection isolated until descriptor and
            // path integrity has passed. A failed file must not poison global
            // dedupe, surface, activity, token, model, or cost state.
            var pendingRecords: [ClaudeLocalUsageRecord] = []
            let streamResult = Self.streamRecordsBounded(
                inFileAt: file,
                maximumBytes: min(Bounds.maximumBytesPerFile, remainingBudget),
                afterRead: { afterFileReadForTesting?(file) }
            ) { record in
                guard pendingRecords.count < Bounds.maximumRecordCount else { return false }
                pendingRecords.append(record)
                return true
            }
            guard streamResult.succeeded else {
                excludedFileCount += 1
                continue
            }

            var fileTokens: Int64 = 0
            var fileModifiedAt: Date?
            for record in pendingRecords {
                guard recordCount < Bounds.maximumRecordCount else { break }
                observedSurfaces.insert(discoveredFile.surface)
                if record.dedupeConfidence == .conservativeStructural {
                    deduplicationConfidence = .conservative
                }
                guard seenRequestDigests.insert(record.dedupeDigest).inserted else {
                    continue
                }
                recordCount += 1
                let tokens = record.counts.totalTokens
                observedTokens += tokens
                fileTokens += tokens
                if fileModifiedAt.map({ record.observedAt > $0 }) ?? true {
                    fileModifiedAt = record.observedAt
                }
                guard let rate = ClaudeModelPrice.rate(forFamily: record.modelFamily) else {
                    continue
                }
                let usd = record.counts.estimatedUSD(rate: rate)
                pricedTokens += tokens
                lifetimeUSD += usd
                if recentDays.contains(Self.usageDay(for: record.observedAt, calendar: calendar)) {
                    sevenDayUSD += usd
                }
                recognizedModels.insert(rate.displayName)
                modelTokenTotals[rate.displayName, default: 0] += tokens
            }
            totalBytes += streamResult.bytesRead
            readableFileCount += 1


            if fileTokens > 0, let modifiedAt = fileModifiedAt {
                perFile.append(ClaudeLocalActivityTask(totalTokens: fileTokens, modifiedAt: modifiedAt))
            }
        }

        guard observedTokens > 0 else { return .unavailable(capturedAt: now) }

        let tasks = Array(
            perFile.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(Bounds.recentTaskCount)
        )
        let estimate = ClaudeAPICostEstimate(
            sevenDayUSD: sevenDayUSD,
            lifetimeUSD: lifetimeUSD,
            pricedTokens: pricedTokens,
            observedTokens: observedTokens,
            recognizedModelCount: recognizedModels.count,
            modelNames: modelTokenTotals.sorted { $0.value > $1.value }.prefix(2).map(\.key)
        )
        return ClaudeLocalActivitySnapshot(
            availability: .available,
            source: observedSurfaces
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.displayName)
                .joined(separator: " + "),
            scope: "provider-owned local activity; metadata-only aggregate scan",
            capturedAt: now,
            discoveredFileCount: discovered.count,
            readableFileCount: readableFileCount,
            excludedFileCount: excludedFileCount,
            tasks: tasks,
            apiEquivalentCost: estimate,
            observedSurfaces: observedSurfaces,
            deduplicationConfidence: deduplicationConfidence
        )
    }

    /// Every `.jsonl` beneath the projects root. Records that do not match the
    /// assistant-usage shape contribute nothing, so unrelated files that share
    /// the extension are inert rather than special-cased.
    ///
    /// The directory names under the root encode absolute project paths and are
    /// therefore used only to open files. No name is retained or published.
    private struct DiscoveredFile {
        let url: URL
        let surface: ClaudeLocalActivitySurface
    }

    private func sessionFiles() -> [DiscoveredFile] {
        var files: [DiscoveredFile] = []
        var seenPaths = Set<String>()
        for source in sources {
            guard files.count < Bounds.maximumFileCount else { break }
            files.append(contentsOf: sessionFiles(
                in: source,
                remainingLimit: Bounds.maximumFileCount - files.count,
                seenPaths: &seenPaths
            ))
        }
        return files
    }

    private func sessionFiles(
        in source: Source,
        remainingLimit: Int,
        seenPaths: inout Set<String>
    ) -> [DiscoveredFile] {
        let manager = FileManager.default
        let standardizedRoot = source.rootDirectory.standardizedFileURL
        guard standardizedRoot.resolvingSymlinksInPath().path == standardizedRoot.path,
              Self.isCurrentUserOwned(standardizedRoot, expectedType: S_IFDIR),
              let rootValues = try? standardizedRoot.resourceValues(
                  forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              let enumerator = manager.enumerator(
                  at: standardizedRoot,
                  includingPropertiesForKeys: [
                      .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
                  ],
                  // Desktop-hosted Claude Code stores its provider-owned
                  // records below a hidden `.claude/projects` component.
                  // The strict path predicate below admits only that subtree.
                  options: [.skipsPackageDescendants]
              )
        else { return [] }

        var files: [DiscoveredFile] = []
        for case let url as URL in enumerator {
            guard files.count < remainingLimit else { break }
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            let standardizedURL = url.standardizedFileURL
            guard url.pathExtension == "jsonl",
                  values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  standardizedURL.resolvingSymlinksInPath().path == standardizedURL.path,
                  standardizedURL.path.hasPrefix(standardizedRoot.path + "/"),
                  seenPaths.insert(standardizedURL.path).inserted
            else { continue }
            files.append(DiscoveredFile(url: standardizedURL, surface: source.surface))
        }
        return files
    }

    /// Nil when the file cannot be read at all, so the caller can count it as
    /// excluded rather than silently treating it as empty.
    static func streamRecords(
        inFileAt url: URL,
        consume: (ClaudeLocalUsageRecord) -> Bool
    ) -> Bool {
        streamRecordsBounded(
            inFileAt: url,
            maximumBytes: Bounds.maximumBytesPerFile,
            consume: consume
        ).succeeded
    }

    static func streamRecordsForTesting(
        inFileAt url: URL,
        afterOpen: (() -> Void)? = nil,
        afterRead: (() -> Void)? = nil,
        consume: (ClaudeLocalUsageRecord) -> Bool
    ) -> Bool {
        streamRecordsBounded(
            inFileAt: url,
            maximumBytes: Bounds.maximumBytesPerFile,
            afterOpen: afterOpen,
            afterRead: afterRead,
            consume: consume
        ).succeeded
    }

    private static func streamRecordsBounded(
        inFileAt url: URL,
        maximumBytes: Int,
        afterOpen: (() -> Void)? = nil,
        afterRead: (() -> Void)? = nil,
        consume: (ClaudeLocalUsageRecord) -> Bool
    ) -> (succeeded: Bool, bytesRead: Int) {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL.resolvingSymlinksInPath().path == standardizedURL.path,
              maximumBytes >= 0
        else { return (false, 0) }
        let descriptor = open(
            standardizedURL.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else { return (false, 0) }
        defer { close(descriptor) }

        var before = stat()
        guard fstat(descriptor, &before) == 0,
              safeLocalRecordFile(before),
              before.st_size >= 0,
              UInt64(before.st_size) <= UInt64(maximumBytes)
        else { return (false, 0) }
        afterOpen?()

        var lineBuffer = Data()
        var recordCount = 0
        var actualBytesRead = 0
        var consumeRecords = true
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { return (false, 0) }
            if count == 0 { break }
            guard actualBytesRead + count <= maximumBytes else {
                return (false, 0)
            }
            actualBytesRead += count
            lineBuffer.append(contentsOf: buffer.prefix(count))
            while let newline = lineBuffer.firstIndex(of: 0x0A) {
                var line = Data(lineBuffer[..<newline])
                lineBuffer.removeSubrange(...newline)
                if line.last == 0x0D { line.removeLast() }
                guard line.count <= Bounds.maximumBytesPerLine else { return (false, 0) }
                if consumeRecords, let record = record(fromData: line) {
                    recordCount += 1
                    guard recordCount <= Bounds.maximumRecordCount else { return (false, 0) }
                    if !consume(record) { consumeRecords = false }
                }
            }
            guard lineBuffer.count <= Bounds.maximumBytesPerLine else { return (false, 0) }
        }
        if !lineBuffer.isEmpty {
            guard lineBuffer.count <= Bounds.maximumBytesPerLine else { return (false, 0) }
            if consumeRecords, let record = record(fromData: lineBuffer) {
                recordCount += 1
                guard recordCount <= Bounds.maximumRecordCount else { return (false, 0) }
                _ = consume(record)
            }
        }
        afterRead?()
        var after = stat()
        var path = stat()
        guard fstat(descriptor, &after) == 0,
              lstat(standardizedURL.path, &path) == 0,
              stableLocalRecordFile(before, after),
              sameLocalRecordIdentity(after, path),
              Int64(actualBytesRead) == after.st_size
        else { return (false, 0) }
        return (true, actualBytesRead)
    }


    /// Parses one bounded record locally, projects only allowlisted numeric and
    /// identifier fields, and immediately discards the transient JSON object.
    /// Prompt-bearing fields may be present in that in-memory record, but are
    /// never copied into the returned model, logs, or durable state.
    static func record(fromLine line: String) -> ClaudeLocalUsageRecord? {
        guard let data = line.data(using: .utf8) else { return nil }
        return record(fromData: data)
    }

    private static func record(fromData data: Data) -> ClaudeLocalUsageRecord? {
        guard !data.isEmpty,
              data.count <= Bounds.maximumBytesPerLine,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, !model.isEmpty
        else { return nil }

        let timestamp = root["timestamp"] as? String
        guard let timestamp, let observedAt = Self.parseTimestamp(timestamp) else { return nil }

        let creation = usage["cache_creation"] as? [String: Any]
        let fiveMinute = Self.nonNegativeInt(creation?["ephemeral_5m_input_tokens"])
        let oneHour = Self.nonNegativeInt(creation?["ephemeral_1h_input_tokens"])
        let creationTotal = Self.nonNegativeInt(usage["cache_creation_input_tokens"])
        // Fall back to the undifferentiated total priced at the five-minute
        // rate when the per-TTL breakdown is absent.
        let hasBreakdown = creation != nil && (fiveMinute + oneHour) > 0

        let modelFamily = ClaudeModelPrice.family(forModel: model)
        let counts = ClaudeTokenCounts(
            inputTokens: Self.nonNegativeInt(usage["input_tokens"]),
            outputTokens: Self.nonNegativeInt(usage["output_tokens"]),
            cacheReadTokens: Self.nonNegativeInt(usage["cache_read_input_tokens"]),
            fiveMinuteCacheWriteTokens: hasBreakdown ? fiveMinute : creationTotal,
            oneHourCacheWriteTokens: hasBreakdown ? oneHour : 0
        )
        let dedupeMaterial = [
            "allowlisted-structural", timestamp, modelFamily.rawValue,
            String(counts.inputTokens), String(counts.outputTokens),
            String(counts.cacheReadTokens), String(counts.fiveMinuteCacheWriteTokens),
            String(counts.oneHourCacheWriteTokens),
        ].joined(separator: "\u{0}")
        return ClaudeLocalUsageRecord(
            dedupeDigest: Self.nonReversibleDigest(dedupeMaterial),
            dedupeConfidence: .conservativeStructural,
            modelFamily: modelFamily,
            observedAt: observedAt,
            counts: counts
        )
    }

    private static func nonReversibleDigest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isCurrentUserOwned(
        _ url: URL,
        expectedType: mode_t
    ) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
            && (info.st_mode & S_IFMT) == expectedType
            && info.st_uid == getuid()
    }

    private static func safeLocalRecordFile(_ info: stat) -> Bool {
        (info.st_mode & S_IFMT) == S_IFREG
            && info.st_uid == getuid()
            && info.st_nlink == 1
            && (info.st_mode & 0o077) == 0
    }

    private static func sameLocalRecordIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_uid == rhs.st_uid
            && (lhs.st_mode & S_IFMT) == (rhs.st_mode & S_IFMT)
            && lhs.st_nlink == rhs.st_nlink
    }

    private static func stableLocalRecordFile(_ lhs: stat, _ rhs: stat) -> Bool {
        sameLocalRecordIdentity(lhs, rhs)
            && lhs.st_mode == rhs.st_mode
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func nonNegativeInt(_ value: Any?) -> Int64 {
        guard let number = value as? NSNumber else { return 0 }
        return max(0, number.int64Value)
    }

    /// Rolling seven-day window in the local calendar: today plus the six
    /// preceding days, recomputed on every read.
    static func sevenDayKeys(now: Date, calendar: Calendar) -> Set<String> {
        let today = calendar.startOfDay(for: now)
        return Set((0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
                .map { usageDay(for: $0, calendar: calendar) }
        })
    }

    static func usageDay(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// Value-type format styles rather than `ISO8601DateFormatter`, which is a
    /// reference type and therefore not usable as shared state under strict
    /// concurrency.
    private static let fractionalTimestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainTimestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func parseTimestamp(_ value: String) -> Date? {
        (try? Date(value, strategy: fractionalTimestamp))
            ?? (try? Date(value, strategy: plainTimestamp))
    }
}
