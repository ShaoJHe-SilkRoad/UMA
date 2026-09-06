import Foundation

/// Presentation-safe output of the admitted historical attribution exporter.
/// It is separate from account usage and never represents a current platform
/// admission or effective-model observation.
public struct ThreadOSUsageAnalytics: Sendable, Equatable, Codable {
    public enum SourceStatus: String, Sendable, Equatable, Codable {
        case available = "AVAILABLE", sourceGap = "SOURCE_GAP", unavailable = "UNAVAILABLE", truncated = "TRUNCATED", malformed = "MALFORMED"
    }
    public struct Row: Sendable, Equatable, Identifiable, Codable {
        public let projectKey: String
        public let projectRootDigest: String
        public let taskID: String
        public let localRole: String
        public let threadDigest: String
        public let turnDigest: String
        public let observation: String
        public let waveID: String?
        /// Values are populated only after a COMPLETE exporter row uniquely
        /// matches a local ledger interval. Export-only rows leave them nil.
        public let model: String?
        public let inputTokens: Int64?
        public let cachedInputTokens: Int64?
        public let outputTokens: Int64?
        public let totalTokens: Int64?
        public let observedStart: Date?
        public let observedEnd: Date?
        public let apiEquivalentUSD: Double?
        public let isPriceKnown: Bool
        public let intervalID: String?
        public var id: String { intervalID ?? "\(projectKey):\(projectRootDigest):\(taskID):\(turnDigest)" }
        public init(projectKey: String, projectRootDigest: String, taskID: String, localRole: String, threadDigest: String, turnDigest: String, observation: String, waveID: String?, model: String? = nil, inputTokens: Int64? = nil, cachedInputTokens: Int64? = nil, outputTokens: Int64? = nil, totalTokens: Int64? = nil, observedStart: Date? = nil, observedEnd: Date? = nil, apiEquivalentUSD: Double? = nil, isPriceKnown: Bool = false, intervalID: String? = nil) {
            self.projectKey = projectKey; self.taskID = taskID; self.localRole = localRole
            self.projectRootDigest = projectRootDigest
            self.threadDigest = threadDigest; self.turnDigest = turnDigest
            self.observation = observation; self.waveID = waveID
            self.model = model; self.inputTokens = inputTokens; self.cachedInputTokens = cachedInputTokens; self.outputTokens = outputTokens; self.totalTokens = totalTokens
            self.intervalID = intervalID
            self.observedStart = observedStart; self.observedEnd = observedEnd; self.apiEquivalentUSD = apiEquivalentUSD; self.isPriceKnown = isPriceKnown
        }
    }

    /// A bounded total from the local immutable ledger. This is deliberately
    /// separate from exporter availability and from account usage: it says
    /// only how much already-observed local usage is or is not backed by an
    /// accepted ThreadOS interval projection.
    public struct LocalLedgerCoverage: Sendable, Equatable, Codable {
        public let knownLocalTokens: Int64
        public let matchedLocalTokens: Int64
        public let localUnassignedTokens: Int64

        public init(knownLocalTokens: Int64, matchedLocalTokens: Int64) {
            self.knownLocalTokens = knownLocalTokens
            self.matchedLocalTokens = matchedLocalTokens
            self.localUnassignedTokens = knownLocalTokens - matchedLocalTokens
        }
    }

    public let sourceStatus: SourceStatus
    public let rows: [Row]
    /// `nil` for snapshots produced before the local ledger projection was
    /// available. It must never be inferred from `unavailableCount`, which is
    /// solely an exporter-side producer-row count.
    public let localLedgerCoverage: LocalLedgerCoverage?
    public let unavailableCount: Int
    public let capturedAt: Date
    public init(sourceStatus: SourceStatus, rows: [Row], unavailableCount: Int, capturedAt: Date, localLedgerCoverage: LocalLedgerCoverage? = nil) {
        self.sourceStatus = sourceStatus; self.rows = rows
        self.localLedgerCoverage = localLedgerCoverage
        self.unavailableCount = unavailableCount; self.capturedAt = capturedAt
    }
    public static func sourceGap(now: Date = Date()) -> Self { .init(sourceStatus: .sourceGap, rows: [], unavailableCount: 0, capturedAt: now) }
}
