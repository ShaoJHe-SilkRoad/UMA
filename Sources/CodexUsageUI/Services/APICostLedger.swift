import Foundation

struct APIModelPrice: Codable, Equatable, Sendable {
    let version: String
    let displayName: String
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let outputPerMillion: Double

    // Standard API prices active when this app version was released.
    // When a price changes, keep the old version in existing ledger records and
    // return a new version here. Never edit persisted records in place.
    /// Returns the catalog entry that was known to apply at `observedAt`.
    ///
    /// The catalog deliberately has a bounded historical start rather than
    /// silently applying today's price to an older local session. Ledger
    /// records encode the selected price in full, so later catalog changes do
    /// not alter an already-recorded delta.
    static func price(for rawModel: String, observedAt: Date?) -> APIModelPrice? {
        guard let observedAt, observedAt >= catalogEffectiveDate else { return nil }
        let model = rawModel.lowercased()
        if model == "gpt-5.6-sol" || model.hasPrefix("gpt-5.6-sol-") {
            return APIModelPrice(
                version: "2026-07-13-standard",
                displayName: "GPT-5.6 Sol",
                inputPerMillion: 5,
                cachedInputPerMillion: 0.5,
                outputPerMillion: 30
            )
        }
        if model == "gpt-5.6-terra" || model.hasPrefix("gpt-5.6-terra-") {
            return APIModelPrice(
                version: "2026-07-13-standard",
                displayName: "GPT-5.6 Terra",
                inputPerMillion: 2.5,
                cachedInputPerMillion: 0.25,
                outputPerMillion: 15
            )
        }
        if model == "gpt-5.6-luna" || model.hasPrefix("gpt-5.6-luna-") {
            return APIModelPrice(
                version: "2026-07-13-standard",
                displayName: "GPT-5.6 Luna",
                inputPerMillion: 1,
                cachedInputPerMillion: 0.1,
                outputPerMillion: 6
            )
        }
        if model == "gpt-5.5" || model.hasPrefix("gpt-5.5-") {
            return APIModelPrice(
                version: "2026-07-13-standard",
                displayName: "GPT-5.5",
                inputPerMillion: 5,
                cachedInputPerMillion: 0.5,
                outputPerMillion: 30
            )
        }
        if model == "gpt-5.4" || model.hasPrefix("gpt-5.4-") {
            return APIModelPrice(
                version: "2026-07-13-standard",
                displayName: "GPT-5.4",
                inputPerMillion: 2.5,
                cachedInputPerMillion: 0.25,
                outputPerMillion: 15
            )
        }
        return nil
    }

    /// Convenience for callers that are calculating a prospective estimate
    /// rather than replaying a timestamped session event.
    static func price(for rawModel: String) -> APIModelPrice? {
        price(for: rawModel, observedAt: Date())
    }

    private static let catalogEffectiveDate: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 7
        components.day = 13
        return components.date ?? .distantFuture
    }()
}

struct SessionTokenSummary: Sendable {
    let model: String
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let outputTokens: Int64
    let totalTokens: Int64
    /// Metadata-only values used in memory for a conservative fork baseline.
    /// They are never written to the durable ledger, which keeps only opaque
    /// local IDs, token counters, and price snapshots.
    let sessionIdentifier: String?
    let parentSessionIdentifier: String?
    let forkedAt: Date?
    let observedAt: Date?
    let tokenCheckpoints: [TokenCountCheckpoint]

    init(
        model: String,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        totalTokens: Int64,
        sessionIdentifier: String? = nil,
        parentSessionIdentifier: String? = nil,
        forkedAt: Date? = nil,
        observedAt: Date? = nil,
        tokenCheckpoints: [TokenCountCheckpoint] = []
    ) {
        self.model = model
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.sessionIdentifier = sessionIdentifier
        self.parentSessionIdentifier = parentSessionIdentifier
        self.forkedAt = forkedAt
        self.observedAt = observedAt
        self.tokenCheckpoints = tokenCheckpoints
    }

    func inheritedBaseline() -> TokenCounts? {
        guard let forkedAt else { return nil }
        return tokenCheckpoints
            .filter { $0.capturedAt <= forkedAt }
            .max { $0.capturedAt < $1.capturedAt }?
            .counts
    }
}

/// A timestamped, metadata-only token checkpoint used transiently while a
/// child session establishes its inherited baseline. It is never Codable and
/// is not persisted by `APICostLedger`.
struct TokenCountCheckpoint: Sendable {
    let capturedAt: Date
    let counts: TokenCounts
}

struct APICostLedger: Codable, Sendable {
    private static let currentSchemaVersion = 1

    private(set) var schemaVersion: Int
    private(set) var checkpoints: [String: Checkpoint]
    private(set) var records: [Record]

    init() {
        schemaVersion = Self.currentSchemaVersion
        checkpoints = [:]
        records = []
    }

    @discardableResult
    mutating func observe(
        sessionID: String,
        summary: SessionTokenSummary,
        initialUsageDay: String,
        incrementalUsageDay: String,
        price: APIModelPrice?,
        inheritedBaseline: TokenCounts? = nil,
        requiresInheritedBaseline: Bool = false
    ) -> Bool {
        observeDetailed(
            sessionID: sessionID,
            summary: summary,
            initialUsageDay: initialUsageDay,
            incrementalUsageDay: incrementalUsageDay,
            price: price,
            inheritedBaseline: inheritedBaseline,
            requiresInheritedBaseline: requiresInheritedBaseline
        )?.didChange ?? false
    }

    /// Returns the safe, baseline-adjusted current total even when there is no
    /// new delta. This lets the local channel render a child task without
    /// counting parent context as child work. `nil` is intentionally
    /// conservative: the baseline was missing, malformed, or lower than an
    /// established checkpoint.
    mutating func observeDetailed(
        sessionID: String,
        summary: SessionTokenSummary,
        initialUsageDay: String,
        incrementalUsageDay: String,
        price: APIModelPrice?,
        inheritedBaseline: TokenCounts?,
        requiresInheritedBaseline: Bool
    ) -> Observation? {
        let rawCurrent = TokenCounts(summary: summary)
        let existing = checkpoints[sessionID]
        let baseline: TokenCounts?
        if let existing {
            baseline = existing.inheritedBaseline
        } else {
            guard !requiresInheritedBaseline || inheritedBaseline != nil else {
                return nil
            }
            baseline = inheritedBaseline
        }

        let current: TokenCounts
        if let baseline {
            guard let adjusted = rawCurrent.delta(since: baseline) else {
                return nil
            }
            current = adjusted
        } else {
            current = rawCurrent
        }

        let previous = existing?.counts

        let delta: TokenCounts
        let usageDay: String
        if let previous {
            guard let incremental = current.delta(since: previous) else {
                // A rewritten or truncated log must not subtract or reprice
                // costs that were already frozen in the ledger. Crucially, do
                // not lower the checkpoint: a later healthy file must be
                // compared with the last accepted high-water mark.
                return nil
            }
            delta = incremental
            usageDay = incrementalUsageDay
        } else {
            delta = current
            usageDay = initialUsageDay
        }

        guard delta.totalTokens > 0 else {
            if previous == nil {
                checkpoints[sessionID] = Checkpoint(
                    model: summary.model,
                    counts: current,
                    inheritedBaseline: baseline
                )
                return Observation(current: current, didChange: true)
            }
            return Observation(current: current, didChange: false)
        }
        let usd = price.map {
            SessionAPICostEstimator.estimatedUSD(price: $0, counts: delta)
        } ?? 0

        if let index = records.firstIndex(where: {
            $0.sessionID == sessionID
                && $0.usageDay == usageDay
                && $0.model == summary.model
                && $0.price == price
        }) {
            records[index].add(delta, usd: usd)
        } else {
            records.append(Record(
                sessionID: sessionID,
                usageDay: usageDay,
                model: summary.model,
                counts: delta,
                price: price,
                usd: usd
            ))
        }
        checkpoints[sessionID] = Checkpoint(
            model: summary.model,
            counts: current,
            inheritedBaseline: baseline
        )
        return Observation(current: current, didChange: true)
    }

    func estimate(sevenDayKeys: Set<String>) -> CodexAPICostEstimate? {
        var sevenDayUSD = 0.0
        var lifetimeUSD = 0.0
        var pricedTokens: Int64 = 0
        var observedTokens: Int64 = 0
        var modelTokenTotals: [String: Int64] = [:]

        for record in records {
            observedTokens += record.counts.totalTokens
            lifetimeUSD += record.usd
            if sevenDayKeys.contains(record.usageDay) {
                sevenDayUSD += record.usd
            }
            if let price = record.price {
                pricedTokens += record.counts.totalTokens
                modelTokenTotals[price.displayName, default: 0] += record.counts.totalTokens
            }
        }

        guard observedTokens > 0 else { return nil }
        return CodexAPICostEstimate(
            sevenDayUSD: sevenDayUSD,
            lifetimeUSD: lifetimeUSD,
            pricedTokens: pricedTokens,
            observedTokens: observedTokens,
            modelNames: modelTokenTotals
                .sorted { $0.value > $1.value }
                .prefix(2)
                .map(\.key)
        )
    }
}

extension APICostLedger {
    struct Checkpoint: Codable, Sendable {
        let model: String
        let counts: TokenCounts
        /// Persisted counters only; this is deliberately not a parent ID or
        /// session path. It freezes a previously reconstructed baseline so a
        /// later parent-tail eviction cannot reintroduce inherited context.
        let inheritedBaseline: TokenCounts?

        init(model: String, counts: TokenCounts, inheritedBaseline: TokenCounts? = nil) {
            self.model = model
            self.counts = counts
            self.inheritedBaseline = inheritedBaseline
        }
    }

    struct Observation: Sendable {
        let current: TokenCounts
        let didChange: Bool
    }

    struct Record: Codable, Sendable {
        let sessionID: String
        let usageDay: String
        let model: String
        private(set) var counts: TokenCounts
        let price: APIModelPrice?
        private(set) var usd: Double

        mutating func add(_ delta: TokenCounts, usd additionalUSD: Double) {
            counts.add(delta)
            usd += additionalUSD
        }
    }
}

struct TokenCounts: Codable, Equatable, Sendable {
    private(set) var inputTokens: Int64
    private(set) var cachedInputTokens: Int64
    private(set) var outputTokens: Int64
    private(set) var totalTokens: Int64

    init(summary: SessionTokenSummary) {
        inputTokens = max(0, summary.inputTokens)
        cachedInputTokens = min(max(0, summary.cachedInputTokens), inputTokens)
        outputTokens = max(0, summary.outputTokens)
        totalTokens = max(0, summary.totalTokens)
    }

    init(
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        totalTokens: Int64
    ) {
        self.inputTokens = max(0, inputTokens)
        self.cachedInputTokens = min(max(0, cachedInputTokens), self.inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.totalTokens = max(0, totalTokens)
    }

    func delta(since previous: TokenCounts) -> TokenCounts? {
        guard
            inputTokens >= previous.inputTokens,
            cachedInputTokens >= previous.cachedInputTokens,
            outputTokens >= previous.outputTokens,
            totalTokens >= previous.totalTokens
        else { return nil }

        return TokenCounts(
            inputTokens: inputTokens - previous.inputTokens,
            cachedInputTokens: cachedInputTokens - previous.cachedInputTokens,
            outputTokens: outputTokens - previous.outputTokens,
            totalTokens: totalTokens - previous.totalTokens
        )
    }

    mutating func add(_ other: TokenCounts) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        totalTokens += other.totalTokens
    }
}

struct APICostLedgerStore: Sendable {
    enum StoreError: Error {
        case corruptedLedger
    }

    let url: URL

    static var defaultURL: URL {
        ApplicationDataPaths.current().codexLedgerURL
    }

    func load() throws -> APICostLedger {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return APICostLedger() }

        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: url),
           let ledger = try? decoder.decode(APICostLedger.self, from: data) {
            return ledger
        }

        let backupURL = backupURL
        if let data = try? Data(contentsOf: backupURL),
           let ledger = try? decoder.decode(APICostLedger.self, from: data) {
            // A valid backup is the last known good state. Restore it
            // atomically so the next launch does not repeatedly parse the
            // corrupted primary file or silently restart lifetime accounting.
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try? data.write(to: url, options: .atomic)
            return ledger
        }
        throw StoreError.corruptedLedger
    }

    func save(_ ledger: APICostLedger) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        if fileManager.fileExists(atPath: url.path),
           let existingData = try? Data(contentsOf: url),
           (try? JSONDecoder().decode(APICostLedger.self, from: existingData)) != nil {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: url, to: backupURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: url, options: .atomic)
    }

    private var backupURL: URL {
        url.appendingPathExtension("backup")
    }
}
