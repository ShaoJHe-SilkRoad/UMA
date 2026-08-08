import Foundation

/// Published Claude list prices in US dollars per one million tokens.
///
/// These are list prices only. No billing, invoice, payment, or account
/// information is read to obtain or apply them. The catalogue is a frozen
/// snapshot; `catalogueVersion` records which snapshot produced an estimate.
enum ClaudeModelPrice: Sendable {
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
        let id = identifier.lowercased()
        switch id {
        case "claude-fable-5", "claude-mythos-5": return fable
        case "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7",
             "claude-opus-4-6", "claude-opus-4-5": return opus
        case "claude-sonnet-5", "claude-sonnet-4-6", "claude-sonnet-4-5": return sonnet
        case "claude-haiku-4-5": return haiku
        default: break
        }
        if id.hasPrefix("claude-fable") || id.hasPrefix("claude-mythos") { return fable }
        if id.hasPrefix("claude-opus") { return opus }
        if id.hasPrefix("claude-sonnet") { return sonnet }
        if id.hasPrefix("claude-haiku") { return haiku }
        return nil
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

/// One de-duplicated assistant response worth of accounting. Only the fields
/// below are ever decoded. Prompts, responses, thinking, tool names, tool
/// inputs, file paths, working directories, git branches, titles, and account
/// identity are never read.
struct ClaudeLocalUsageRecord: Sendable, Equatable {
    let requestID: String
    let model: String
    let observedAt: Date
    let counts: ClaudeTokenCounts
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

/// Bounded, allowlisted reader over Claude Code's own local session records.
///
/// This is secondary local analytics. It never establishes, replaces, or
/// influences the account quota shown for Claude, which comes only from the
/// admitted Browser Sync observation. Unlike the Codex reader there is no
/// persisted ledger: Claude writes per-message incremental usage, so summing
/// the records is already correct and no delta state has to be kept on disk.
struct ClaudeLocalActivityReader: ClaudeLocalActivityReading {
    enum Bounds {
        static let maximumFileCount = 256
        static let maximumBytesPerFile = 64 * 1_024 * 1_024
        static let maximumTotalBytes = 512 * 1_024 * 1_024
        static let maximumRecordCount = 200_000
        static let recentTaskCount = 3
    }

    private let rootDirectory: URL
    private let calendar: Calendar

    init(rootDirectory: URL? = nil, calendar: Calendar = .current) {
        self.rootDirectory = rootDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
        self.calendar = calendar
    }

    func read(now: Date = Date()) -> ClaudeLocalActivitySnapshot {
        let discovered = sessionFiles()
        guard !discovered.isEmpty else { return .unavailable(capturedAt: now) }

        var seenRequestIDs = Set<String>()
        var recognizedModels = Set<String>()
        var modelTokenTotals: [String: Int64] = [:]
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

        for file in discovered {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= Bounds.maximumBytesPerFile,
                  totalBytes + size <= Bounds.maximumTotalBytes
            else {
                excludedFileCount += 1
                continue
            }
            guard let records = Self.records(inFileAt: file) else {
                excludedFileCount += 1
                continue
            }
            totalBytes += size
            readableFileCount += 1

            var fileTokens: Int64 = 0
            var fileModifiedAt: Date?

            for record in records {
                guard recordCount < Bounds.maximumRecordCount else { break }
                // A single API response is written once per content block,
                // each copy carrying an identical usage object. Without this
                // gate the totals roughly double.
                guard seenRequestIDs.insert(record.requestID).inserted else { continue }
                recordCount += 1

                let tokens = record.counts.totalTokens
                observedTokens += tokens
                fileTokens += tokens
                if fileModifiedAt.map({ record.observedAt > $0 }) ?? true {
                    fileModifiedAt = record.observedAt
                }

                guard let rate = ClaudeModelPrice.rate(forModel: record.model) else { continue }
                let usd = record.counts.estimatedUSD(rate: rate)
                pricedTokens += tokens
                lifetimeUSD += usd
                if recentDays.contains(Self.usageDay(for: record.observedAt, calendar: calendar)) {
                    sevenDayUSD += usd
                }
                recognizedModels.insert(rate.displayName)
                modelTokenTotals[rate.displayName, default: 0] += tokens
            }

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
            source: "This Mac: Claude Code session metadata",
            scope: "projects; metadata-only aggregate scan",
            capturedAt: now,
            discoveredFileCount: discovered.count,
            readableFileCount: readableFileCount,
            excludedFileCount: excludedFileCount,
            tasks: tasks,
            apiEquivalentCost: estimate
        )
    }

    /// Every `.jsonl` beneath the projects root. Records that do not match the
    /// assistant-usage shape contribute nothing, so unrelated files that share
    /// the extension are inert rather than special-cased.
    ///
    /// The directory names under the root encode absolute project paths and are
    /// therefore used only to open files. No name is retained or published.
    private func sessionFiles() -> [URL] {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = manager.enumerator(
                  at: rootDirectory,
                  includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants]
              )
        else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard files.count < Bounds.maximumFileCount else { break }
            guard url.pathExtension == "jsonl",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            files.append(url)
        }
        return files
    }

    /// Nil when the file cannot be read at all, so the caller can count it as
    /// excluded rather than silently treating it as empty.
    static func records(inFileAt url: URL) -> [ClaudeLocalUsageRecord]? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var records: [ClaudeLocalUsageRecord] = []
        contents.enumerateLines { line, _ in
            if let record = Self.record(fromLine: line) { records.append(record) }
        }
        return records
    }

    /// Decodes only allowlisted numeric and identifier fields. The record body
    /// is never materialized into a model that could carry content.
    static func record(fromLine line: String) -> ClaudeLocalUsageRecord? {
        guard !line.isEmpty, let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, !model.isEmpty
        else { return nil }

        let requestID = (root["requestId"] as? String)
            ?? (message["id"] as? String)
            ?? UUID().uuidString
        let observedAt = (root["timestamp"] as? String).flatMap(Self.parseTimestamp)
            ?? Date(timeIntervalSince1970: 0)

        let creation = usage["cache_creation"] as? [String: Any]
        let fiveMinute = Self.nonNegativeInt(creation?["ephemeral_5m_input_tokens"])
        let oneHour = Self.nonNegativeInt(creation?["ephemeral_1h_input_tokens"])
        let creationTotal = Self.nonNegativeInt(usage["cache_creation_input_tokens"])
        // Fall back to the undifferentiated total priced at the five-minute
        // rate when the per-TTL breakdown is absent.
        let hasBreakdown = creation != nil && (fiveMinute + oneHour) > 0

        return ClaudeLocalUsageRecord(
            requestID: requestID,
            model: model,
            observedAt: observedAt,
            counts: ClaudeTokenCounts(
                inputTokens: Self.nonNegativeInt(usage["input_tokens"]),
                outputTokens: Self.nonNegativeInt(usage["output_tokens"]),
                cacheReadTokens: Self.nonNegativeInt(usage["cache_read_input_tokens"]),
                fiveMinuteCacheWriteTokens: hasBreakdown ? fiveMinute : creationTotal,
                oneHourCacheWriteTokens: hasBreakdown ? oneHour : 0
            )
        )
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
