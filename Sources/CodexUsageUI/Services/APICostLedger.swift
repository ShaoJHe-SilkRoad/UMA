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
    /// Full-file local intervals are transient only. They remain outside the
    /// durable ledger until a COMPLETE producer export uniquely matches one.
    let localIntervals: [ThreadOSLocalIntervalCandidate]
    /// A locally validated, domain-separated identity for the token interval.
    /// It is intentionally opaque: the ledger uses it only to avoid
    /// coalescing independently attributable history. It does not by itself
    /// establish producer attribution.
    let attributionIntervalID: String?

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
        tokenCheckpoints: [TokenCountCheckpoint] = [],
        localIntervals: [ThreadOSLocalIntervalCandidate] = [],
        attributionIntervalID: String? = nil
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
        self.localIntervals = localIntervals
        self.attributionIntervalID = attributionIntervalID
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
        legacySessionID: String? = nil,
        summary: SessionTokenSummary,
        initialUsageDay: String,
        incrementalUsageDay: String,
        price: APIModelPrice?,
        aggregateModel: String? = nil,
        aggregatePrice: APIModelPrice? = nil,
        residualPricing: ResidualPricing? = nil,
        inheritedBaseline: TokenCounts? = nil,
        requiresInheritedBaseline: Bool = false,
        intervalPartitions: [IntervalPartition] = [],
        localTransitionEvidence: LocalTransitionEvidence? = nil
    ) -> Bool {
        observeDetailed(
            sessionID: sessionID,
            legacySessionID: legacySessionID,
            summary: summary,
            initialUsageDay: initialUsageDay,
            incrementalUsageDay: incrementalUsageDay,
            price: price,
            aggregateModel: aggregateModel,
            aggregatePrice: aggregatePrice,
            residualPricing: residualPricing,
            inheritedBaseline: inheritedBaseline,
            requiresInheritedBaseline: requiresInheritedBaseline,
            intervalPartitions: intervalPartitions,
            localTransitionEvidence: localTransitionEvidence
        )?.didChange ?? false
    }

    /// Returns the safe, baseline-adjusted current total even when there is no
    /// new delta. This lets the local channel render a child task without
    /// counting parent context as child work. `nil` is intentionally
    /// conservative: the baseline was missing, malformed, or lower than an
    /// established checkpoint.
    mutating func observeDetailed(
        sessionID: String,
        legacySessionID: String? = nil,
        summary: SessionTokenSummary,
        initialUsageDay: String,
        incrementalUsageDay: String,
        price: APIModelPrice?,
        aggregateModel: String? = nil,
        aggregatePrice: APIModelPrice? = nil,
        residualPricing: ResidualPricing? = nil,
        inheritedBaseline: TokenCounts?,
        requiresInheritedBaseline: Bool,
        intervalPartitions: [IntervalPartition] = [],
        localTransitionEvidence: LocalTransitionEvidence? = nil
    ) -> Observation? {
        // TU2 keyed checkpoints by the allowlisted root-relative path even
        // when a native session ID was present. Adopt only an exact current
        // path key supplied by the reader: no counter/model similarity search
        // may infer aliases between independent sessions. A mismatched exact
        // alias fails closed rather than rebilling under a new key.
        var adoptedLegacyCheckpoint = false
        if checkpoints[sessionID] == nil,
           let legacySessionID,
           legacySessionID != sessionID,
           let legacyCheckpoint = checkpoints[legacySessionID] {
            guard legacyCheckpoint.model == summary.model else { return nil }
            checkpoints[sessionID] = legacyCheckpoint
            checkpoints.removeValue(forKey: legacySessionID)
            adoptedLegacyCheckpoint = true
        }

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
                    inheritedBaseline: baseline,
                    attributionIntervalID: summary.attributionIntervalID
                )
                return Observation(current: current, didChange: true)
            }
            // Persist the unchanged-value migration; otherwise a later
            // archive/rename would treat the native key as a fresh lifetime.
            return Observation(current: current, didChange: adoptedLegacyCheckpoint)
        }
        // Session tails are reread as a whole. Retained identities represent
        // already-accounted intervals, so only novel interval counters may
        // consume the newly observed high-water delta.
        let recordedIntervalIDs = Set(records.compactMap(\.attributionIntervalID))
        // A delayed COMPLETE export can describe an interval which was
        // already accepted in an earlier aggregate-only read.  Such an
        // interval is not eligible to consume a later delta merely because
        // its *size* happens to fit.  Admit only an entire interval whose
        // adjusted counters lie inside this exact high-water window.
        let windowStart = previous ?? .zero
        let novelPartitions = intervalPartitions.filter {
            !recordedIntervalIDs.contains($0.attributionIntervalID)
                && $0.isWhollyContained(from: windowStart, through: current)
        }
        // Legacy partitions predate per-interval pricing. Their omitted
        // model/price therefore retain the caller's original summary values;
        // a residual classification must never become their validation
        // default. Production callers pass a distinct residual policy based
        // on bounded local model evidence and the prior checkpoint.
        let defaultResidual = residualPricing ?? ResidualPricing(
            model: aggregateModel ?? summary.model,
            price: aggregatePrice ?? price,
            hasExplicitPrice: aggregatePrice != nil
        )
        // A trailing summary is not evidence that a new append continued the
        // same model.  Resolve the aggregate lane from the persisted
        // high-water model and independently decoded local turn evidence;
        // producer matching affects partitions only.
        let residual = localTransitionEvidence.map {
            Self.residualPricing(
                defaultResidual: defaultResidual,
                summary: summary,
                previousModel: existing?.model,
                evidence: $0
            )
        } ?? defaultResidual
        guard let partitioned = Self.partition(
            delta,
            legacyDefaultModel: summary.model,
            legacyDefaultPrice: price,
            residual: residual,
            by: novelPartitions
        ) else {
            // Do not advance the high-water checkpoint unless every explicit
            // interval is bounded by this exact newly observed delta.
            return nil
        }
        for partition in partitioned {
            append(sessionID: sessionID, usageDay: usageDay, model: partition.model, counts: partition.counts, price: partition.price, attributionIntervalID: partition.attributionIntervalID, projection: partition.projection)
        }
        checkpoints[sessionID] = Checkpoint(
            model: summary.model,
            counts: current,
            inheritedBaseline: baseline,
            attributionIntervalID: nil
        )
        return Observation(current: current, didChange: true)
    }

    /// Records a finite set of producer-matched intervals plus one aggregate
    /// remainder. Every identity must be unique and fit this new high-water
    /// delta; the remainder remains unattributed.
    struct IntervalPartition: Sendable {
        let attributionIntervalID: String
        let counts: TokenCounts
        /// Exact, baseline-adjusted counters surrounding this delta. They
        /// let the ledger reject late historical attribution without relying
        /// on a token-count coincidence.
        let preceding: TokenCounts
        let ending: TokenCounts
        /// This is captured only after the exporter row and local delta have
        /// both been accepted into the ledger. It deliberately contains no
        /// session path, source JSON, or producer message content.
        let projection: AccountingProjection?
        /// The validated model and immutable price snapshot for this exact
        /// counter window. Nil is retained only for legacy test construction;
        /// production partitions always provide both independently.
        let model: String?
        let price: APIModelPrice?
        /// Distinguishes an explicitly validated-but-unpriced interval from a
        /// legacy caller that did not provide interval pricing at all.
        let hasValidatedPrice: Bool

        init(
            attributionIntervalID: String,
            counts: TokenCounts,
            preceding: TokenCounts,
            ending: TokenCounts,
            projection: AccountingProjection? = nil,
            model: String? = nil,
            price: APIModelPrice? = nil,
            hasValidatedPrice: Bool = false
        ) {
            self.attributionIntervalID = attributionIntervalID
            self.counts = counts
            self.preceding = preceding
            self.ending = ending
            self.projection = projection
            self.model = model
            self.price = price
            self.hasValidatedPrice = hasValidatedPrice
        }

        fileprivate func isWhollyContained(from lowerBound: TokenCounts, through upperBound: TokenCounts) -> Bool {
            guard ending.delta(since: preceding) == counts else { return false }
            return preceding.isAtLeast(lowerBound) && ending.isAtMost(upperBound)
        }
    }

    /// Transient policy for the unattributed portion of one newly observed
    /// high-water delta. This is deliberately separate from the summary
    /// compatibility defaults used for legacy partitions. `hasExplicitPrice`
    /// preserves the material distinction between a supplied nil price and
    /// an omitted policy.
    struct ResidualPricing: Sendable {
        let model: String
        let price: APIModelPrice?
        let hasExplicitPrice: Bool

        init(model: String, price: APIModelPrice?, hasExplicitPrice: Bool) {
            self.model = model
            self.price = price
            self.hasExplicitPrice = hasExplicitPrice
        }
    }

    /// Bounded local model evidence retained independently of producer
    /// matching.  It is transient and deliberately carries no partition ID,
    /// task identity, or counter-placement inference.
    struct LocalTransitionEvidence: Sendable {
        let models: [String]
        let hasUnknownOrAmbiguousInterval: Bool

        init(models: [String], hasUnknownOrAmbiguousInterval: Bool) {
            self.models = models
            self.hasUnknownOrAmbiguousInterval = hasUnknownOrAmbiguousInterval
        }
    }

    private static func residualPricing(
        defaultResidual: ResidualPricing,
        summary: SessionTokenSummary,
        previousModel: String?,
        evidence: LocalTransitionEvidence
    ) -> ResidualPricing {
        let models = Set(evidence.models)
        let evidenceModel = models.first ?? previousModel ?? summary.model
        guard !evidence.hasUnknownOrAmbiguousInterval,
              models.count <= 1,
              evidenceModel == summary.model,
              previousModel == nil || previousModel == evidenceModel
        else {
            return .init(model: "UNKNOWN", price: nil, hasExplicitPrice: true)
        }
        return .init(
            model: evidenceModel,
            // The reader has already bound this observation's catalog date.
            // Retain that exact snapshot for a same-model aggregate lane.
            price: defaultResidual.model == evidenceModel
                ? defaultResidual.price
                : APIModelPrice.price(for: evidenceModel, observedAt: summary.observedAt),
            hasExplicitPrice: true
        )
    }

    private static func partition(
        _ delta: TokenCounts,
        legacyDefaultModel: String,
        legacyDefaultPrice: APIModelPrice?,
        residual: ResidualPricing,
        by partitions: [IntervalPartition]
    ) -> [(attributionIntervalID: String?, model: String, price: APIModelPrice?, counts: TokenCounts, projection: AccountingProjection?)]? {
        var remaining = delta
        var identities = Set<String>()
        var result: [(attributionIntervalID: String?, model: String, price: APIModelPrice?, counts: TokenCounts, projection: AccountingProjection?)] = []
        for partition in partitions {
            let model = partition.model ?? legacyDefaultModel
            let price = partition.hasValidatedPrice ? partition.price : legacyDefaultPrice
            guard !partition.attributionIntervalID.isEmpty,
                  identities.insert(partition.attributionIntervalID).inserted,
                  partition.counts.totalTokens > 0,
                  let projection = partition.projection,
                  projection.counts == partition.counts,
                  projection.model == model,
                  let nextRemaining = remaining.subtracting(partition.counts)
            else { return nil }
            result.append((partition.attributionIntervalID, model, price, partition.counts, projection))
            remaining = nextRemaining
        }
        if remaining.totalTokens > 0 {
            // A residual's nil is authoritative when its policy explicitly
            // says it is unpriced. Do not coalesce it with the summary price.
            let residualPrice = residual.hasExplicitPrice ? residual.price : legacyDefaultPrice
            result.append((nil, residual.model, residualPrice, remaining, nil))
        }
        return result
    }

    private mutating func append(sessionID: String, usageDay: String, model: String, counts: TokenCounts, price: APIModelPrice?, attributionIntervalID: String?, projection: AccountingProjection?) {
        let usd = price.map { SessionAPICostEstimator.estimatedUSD(price: $0, counts: counts) } ?? 0
        if let index = records.firstIndex(where: {
            $0.sessionID == sessionID && $0.usageDay == usageDay && $0.model == model && $0.price == price && $0.attributionIntervalID == attributionIntervalID
        }) {
            records[index].add(counts, usd: usd)
        } else {
            records.append(Record(sessionID: sessionID, usageDay: usageDay, model: model, counts: counts, price: price, attributionIntervalID: attributionIntervalID, projection: projection, usd: usd))
        }
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
    /// Immutable, presentation-safe attribution captured with an accepted
    /// partition. Legacy records and aggregate remainders intentionally have
    /// no projection and therefore can never be retroactively attributed.
    struct AccountingProjection: Codable, Equatable, Sendable {
        let projectKey: String
        let projectRootDigest: String?
        let taskID: String
        let localRole: String
        let threadDigest: String?
        let turnDigest: String?
        let intervalID: String?
        let model: String
        let counts: TokenCounts
        let observedStart: Date
        let observedEnd: Date

        init(projectKey: String, projectRootDigest: String? = nil, taskID: String, localRole: String, threadDigest: String? = nil, turnDigest: String? = nil, intervalID: String? = nil, model: String, counts: TokenCounts, observedStart: Date, observedEnd: Date) {
            self.projectKey = projectKey; self.projectRootDigest = projectRootDigest; self.taskID = taskID; self.localRole = localRole; self.threadDigest = threadDigest; self.turnDigest = turnDigest; self.intervalID = intervalID; self.model = model; self.counts = counts; self.observedStart = observedStart; self.observedEnd = observedEnd
        }
    }

    struct Checkpoint: Codable, Sendable {
        let model: String
        let counts: TokenCounts
        /// Persisted counters only; this is deliberately not a parent ID or
        /// session path. It freezes a previously reconstructed baseline so a
        /// later parent-tail eviction cannot reintroduce inherited context.
        let inheritedBaseline: TokenCounts?
        /// Optional for compatibility with older persisted checkpoints.
        let attributionIntervalID: String?

        init(model: String, counts: TokenCounts, inheritedBaseline: TokenCounts? = nil, attributionIntervalID: String? = nil) {
            self.model = model
            self.counts = counts
            self.inheritedBaseline = inheritedBaseline
            self.attributionIntervalID = attributionIntervalID
        }

        enum CodingKeys: String, CodingKey { case model, counts, inheritedBaseline, attributionIntervalID }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            model = try values.decode(String.self, forKey: .model)
            counts = try values.decode(TokenCounts.self, forKey: .counts)
            inheritedBaseline = try values.decodeIfPresent(TokenCounts.self, forKey: .inheritedBaseline)
            attributionIntervalID = try values.decodeIfPresent(String.self, forKey: .attributionIntervalID)
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
        /// `nil` is the legacy aggregate lane. New values are opaque stable
        /// interval identities, not task labels or local source locations.
        let attributionIntervalID: String?
        /// Present only for a producer-matched partition accepted by this
        /// ledger. Missing means legacy or aggregate, never "unknown row".
        let projection: AccountingProjection?
        private(set) var usd: Double

        enum CodingKeys: String, CodingKey {
            case sessionID, usageDay, model, counts, price, attributionIntervalID, projection, usd
        }

        init(
            sessionID: String,
            usageDay: String,
            model: String,
            counts: TokenCounts,
            price: APIModelPrice?,
            attributionIntervalID: String? = nil,
            projection: AccountingProjection? = nil,
            usd: Double
        ) {
            self.sessionID = sessionID
            self.usageDay = usageDay
            self.model = model
            self.counts = counts
            self.price = price
            self.attributionIntervalID = attributionIntervalID
            self.projection = projection
            self.usd = usd
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessionID = try container.decode(String.self, forKey: .sessionID)
            usageDay = try container.decode(String.self, forKey: .usageDay)
            model = try container.decode(String.self, forKey: .model)
            counts = try container.decode(TokenCounts.self, forKey: .counts)
            price = try container.decodeIfPresent(APIModelPrice.self, forKey: .price)
            attributionIntervalID = try container.decodeIfPresent(String.self, forKey: .attributionIntervalID)
            projection = try container.decodeIfPresent(AccountingProjection.self, forKey: .projection)
            usd = try container.decode(Double.self, forKey: .usd)
        }

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

    func subtracting(_ other: TokenCounts) -> TokenCounts? {
        guard inputTokens >= other.inputTokens,
              cachedInputTokens >= other.cachedInputTokens,
              outputTokens >= other.outputTokens,
              totalTokens >= other.totalTokens
        else { return nil }
        return TokenCounts(inputTokens: inputTokens - other.inputTokens, cachedInputTokens: cachedInputTokens - other.cachedInputTokens, outputTokens: outputTokens - other.outputTokens, totalTokens: totalTokens - other.totalTokens)
    }

    mutating func add(_ other: TokenCounts) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        totalTokens += other.totalTokens
    }

    static let zero = TokenCounts(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, totalTokens: 0)

    fileprivate func isAtLeast(_ other: TokenCounts) -> Bool {
        inputTokens >= other.inputTokens
            && cachedInputTokens >= other.cachedInputTokens
            && outputTokens >= other.outputTokens
            && totalTokens >= other.totalTokens
    }

    fileprivate func isAtMost(_ other: TokenCounts) -> Bool {
        inputTokens <= other.inputTokens
            && cachedInputTokens <= other.cachedInputTokens
            && outputTokens <= other.outputTokens
            && totalTokens <= other.totalTokens
    }
}

struct APICostLedgerStore: Sendable {
    enum StoreError: Error, Equatable {
        case corruptedLedger
        case unsupportedSchema
    }

    private struct VersionHeader: Decodable {
        let schemaVersion: Int
    }

    let url: URL

    static var defaultURL: URL {
        ApplicationDataPaths.current().codexLedgerURL
    }

    func load() throws -> APICostLedger {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return APICostLedger() }

        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: url) {
            try validateSupportedSchema(in: data)
            if let ledger = try? decoder.decode(APICostLedger.self, from: data) {
                return ledger
            }
        }

        let backupURL = backupURL
        if let data = try? Data(contentsOf: backupURL) {
            try validateSupportedSchema(in: data)
            guard let ledger = try? decoder.decode(APICostLedger.self, from: data) else {
                throw StoreError.corruptedLedger
            }
            // A valid backup is the last known good state. Restore it
            // atomically so the next launch does not repeatedly parse the
            // corrupted primary file or silently restart lifetime accounting.
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            // Restore the typed projection, never unknown fields from the
            // original backup JSON. The existing backup remains untouched.
            try? encoded(ledger).write(to: url, options: .atomic)
            return ledger
        }
        throw StoreError.corruptedLedger
    }

    func save(_ ledger: APICostLedger) throws {
        let fileManager = FileManager.default
        guard ledger.schemaVersion == APICostLedger().schemaVersion else {
            throw StoreError.unsupportedSchema
        }
        // Refuse an unsupported main or backup before any filesystem write.
        // Its newer representation must survive a rollback unchanged.
        let existingData = try? Data(contentsOf: url)
        if let existingData { try validateSupportedSchema(in: existingData) }
        if let backupData = try? Data(contentsOf: backupURL) {
            try validateSupportedSchema(in: backupData)
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        if let existingData,
           let existing = try? JSONDecoder().decode(APICostLedger.self, from: existingData) {
            try encoded(existing).write(to: backupURL, options: .atomic)
        }

        try encoded(ledger).write(to: url, options: .atomic)
    }

    private func validateSupportedSchema(in data: Data) throws {
        if let header = try? JSONDecoder().decode(VersionHeader.self, from: data),
           header.schemaVersion != APICostLedger().schemaVersion {
            throw StoreError.unsupportedSchema
        }
    }

    private func encoded(_ ledger: APICostLedger) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ledger)
    }

    private var backupURL: URL {
        url.appendingPathExtension("backup")
    }
}
