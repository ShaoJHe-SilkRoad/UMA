import Foundation

public enum SharedConnectionStatus: String, Codable, Sendable {
    case connected
    case transitional
    case authenticationRequired
    case stale
    case disconnected
    case unavailable
    case failed

    public var isHealthy: Bool { self == .connected }
}

public enum SharedUsageFreshness: String, Codable, Sendable {
    case fresh
    case stale
    case unavailable
}

public enum SharedUsageSeverity: String, Codable, Sendable {
    case normal
    case warning
    case critical
    case neutral
}

public enum SharedRemainingValue: Codable, Equatable, Sendable {
    case finite(Double)
    case unlimited
    case unavailable

    public var finitePercent: Double? {
        guard case let .finite(value) = self else { return nil }
        return value
    }

    public var displayPercent: Int? {
        finitePercent.map { Int($0.rounded()) }
    }

    public var tintFraction: Double? {
        finitePercent.map { $0 / 100 }
    }

    public var displayText: String {
        switch self {
        case .finite: "\(displayPercent ?? 0)%"
        case .unlimited: "∞"
        case .unavailable: "—"
        }
    }
}

public enum SharedUsageWindowKind: String, Codable, Sendable {
    case fiveHour
    case sevenDay
    case other
}

public struct SharedUsageWindowPresentation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: SharedUsageWindowKind
    public let compactLabel: String
    public let accessibilityLabel: String
    public let remaining: SharedRemainingValue
    public let resetsAt: Date?
    public let resetText: String

    public init(
        id: String,
        kind: SharedUsageWindowKind,
        compactLabel: String,
        accessibilityLabel: String,
        remaining: SharedRemainingValue,
        resetsAt: Date?,
        resetText: String
    ) {
        self.id = id
        self.kind = kind
        self.compactLabel = compactLabel
        self.accessibilityLabel = accessibilityLabel
        self.remaining = remaining
        self.resetsAt = resetsAt
        self.resetText = resetText
    }
}

public struct SharedUsageCardPresentation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let providerName: String
    public let planLabel: String?
    public let connectionStatus: SharedConnectionStatus
    public let freshness: SharedUsageFreshness
    public let windows: [SharedUsageWindowPresentation]
    public let selectedWindowID: String?
    public let remaining: SharedRemainingValue
    public let severity: SharedUsageSeverity
    public let isRetainingLastValidValue: Bool
    public let capturedAt: Date

    public init(
        id: String,
        providerName: String,
        planLabel: String? = nil,
        connectionStatus: SharedConnectionStatus,
        freshness: SharedUsageFreshness,
        windows: [SharedUsageWindowPresentation],
        selectedWindowID: String?,
        remaining: SharedRemainingValue,
        severity: SharedUsageSeverity,
        isRetainingLastValidValue: Bool = false,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.planLabel = planLabel
        self.connectionStatus = connectionStatus
        self.freshness = freshness
        self.windows = windows
        self.selectedWindowID = selectedWindowID
        self.remaining = remaining
        self.severity = severity
        self.isRetainingLastValidValue = isRetainingLastValidValue
        self.capturedAt = capturedAt
    }

    public var selectedWindow: SharedUsageWindowPresentation? {
        guard let selectedWindowID else { return nil }
        return windows.first(where: { $0.id == selectedWindowID })
    }

    public var selectedWindowCompactLabel: String? {
        selectedWindow?.compactLabel
    }

    public var tooltipText: String {
        let window = selectedWindow?.accessibilityLabel ?? "usage window unavailable"
        let value: String
        switch remaining {
        case .finite: value = "\(remaining.displayPercent ?? 0) percent remaining"
        case .unlimited: value = "unlimited"
        case .unavailable: value = "usage unavailable"
        }
        return "\(providerName), \(connectionStatus.accessibilityText), \(window), \(value)."
    }

    public var accessibilityLabel: String { tooltipText }
}

public enum SharedUsagePresentationPolicy {
    public static func severity(for remaining: SharedRemainingValue) -> SharedUsageSeverity {
        switch remaining {
        case let .finite(percent):
            switch max(0, min(100, percent)) {
            case 0...10: .critical
            case 11..<26: .warning
            default: .normal
            }
        case .unlimited, .unavailable:
            .neutral
        }
    }

    static func makeCards(
        snapshots: [AgentUsageSnapshot],
        previousCards: [SharedUsageCardPresentation],
        language: AppLanguage,
        now: Date = Date()
    ) -> [SharedUsageCardPresentation] {
        let previousByID = Dictionary(uniqueKeysWithValues: previousCards.map { ($0.id, $0) })
        return snapshots.map {
            makeCard(
                snapshot: $0,
                previous: previousByID[$0.id.rawValue],
                language: language,
                now: now
            )
        }
    }

    static func makeCard(
        snapshot: AgentUsageSnapshot,
        previous: SharedUsageCardPresentation?,
        language: AppLanguage,
        now: Date = Date()
    ) -> SharedUsageCardPresentation {
        if let previous, snapshot.capturedAt < previous.capturedAt {
            return previous
        }
        let accountChannel = snapshot.channels.first(where: { $0.id == .account })
        let freshWindows = accountChannel?.rateLimitWindows.map {
            makeWindow($0, language: language, now: now)
        } ?? []
        let sourceIsStale = snapshot.freshness == .stale
            || accountChannel?.freshness == .stale
            || snapshot.state == .stale
        let sourceIsUnavailable = accountChannel == nil
            || accountChannel?.freshness == .unavailable

        let windows: [SharedUsageWindowPresentation]
        let retained: Bool
        if sourceIsStale, let previous, !previous.windows.isEmpty {
            windows = previous.windows
            retained = true
        } else if sourceIsUnavailable,
                  freshWindows.allSatisfy({ $0.remaining == .unavailable }),
                  let previous,
                  !previous.windows.isEmpty {
            windows = previous.windows
            retained = true
        } else {
            windows = freshWindows
            retained = sourceIsStale
        }

        let selectedID = selectedWindowID(
            windows: windows,
            previous: previous,
            isStale: sourceIsStale
        )
        let remaining: SharedRemainingValue
        if let selected = windows.first(where: { $0.id == selectedID }) {
            remaining = selected.remaining
        } else if retained, let previous {
            remaining = previous.remaining
        } else {
            remaining = .unavailable
        }
        let planLabel = accountChannel?.accountMetrics?.planLabel
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? previous?.planLabel

        return SharedUsageCardPresentation(
            id: snapshot.id.rawValue,
            providerName: snapshot.providerName,
            planLabel: planLabel,
            connectionStatus: connectionStatus(snapshot.state),
            freshness: freshness(snapshot.freshness),
            windows: windows,
            selectedWindowID: selectedID,
            remaining: remaining,
            severity: severity(for: remaining),
            isRetainingLastValidValue: retained,
            capturedAt: snapshot.capturedAt
        )
    }

    private static func makeWindow(
        _ window: AgentRateLimitWindow,
        language: AppLanguage,
        now: Date
    ) -> SharedUsageWindowPresentation {
        let labels: (kind: SharedUsageWindowKind, compact: String, accessibility: String)
        switch window.kind {
        case .fiveHour:
            labels = (.fiveHour, "5H", language == .english ? "five-hour window" : "五小时额度窗口")
        case .sevenDay:
            labels = (.sevenDay, "7D", language == .english ? "seven-day window" : "七天额度窗口")
        case .other:
            labels = (.other, "—", language == .english ? "usage window" : "额度窗口")
        }

        let remaining: SharedRemainingValue
        if window.isUnlimited {
            remaining = .unlimited
        } else if let used = window.usedPercent, used.isFinite, (0...100).contains(used) {
            remaining = .finite(100 - used)
        } else {
            remaining = .unavailable
        }

        return SharedUsageWindowPresentation(
            id: window.id,
            kind: labels.kind,
            compactLabel: labels.compact,
            accessibilityLabel: labels.accessibility,
            remaining: remaining,
            resetsAt: window.resetsAt,
            resetText: language.resetDescription(for: window.resetsAt, now: now)
        )
    }

    private static func selectedWindowID(
        windows: [SharedUsageWindowPresentation],
        previous: SharedUsageCardPresentation?,
        isStale: Bool
    ) -> String? {
        let previousID = previous?.selectedWindowID
        let finite = windows.compactMap { window -> (SharedUsageWindowPresentation, Double)? in
            guard case let .finite(value) = window.remaining else { return nil }
            return (window, value)
        }

        if isStale,
           let previousID,
           windows.contains(where: { $0.id == previousID }) {
            return previousID
        }

        if let depleted = finite
            .filter({ $0.1 == 0 })
            .sorted(by: deterministicWindowOrder)
            .first {
            return depleted.0.id
        }

        if let critical = finite
            .filter({ $0.1 > 0 && $0.1 <= 10 })
            .sorted(by: { lhs, rhs in
                lhs.1 == rhs.1 ? deterministicWindowOrder(lhs, rhs) : lhs.1 < rhs.1
            })
            .first {
            return critical.0.id
        }

        if let previous {
            let previousPairs: [(String, (Double, Date?))] = previous.windows.compactMap {
                guard case let .finite(value) = $0.remaining else { return nil }
                return ($0.id, (value, $0.resetsAt))
            }
            let previousValues: [String: (Double, Date?)] = Dictionary(
                uniqueKeysWithValues: previousPairs
            )
            let positiveDecrements = finite.compactMap {
                current -> (window: SharedUsageWindowPresentation, decrement: Double, remaining: Double)? in
                guard let old = previousValues[current.0.id] else { return nil }
                guard old.1 == current.0.resetsAt else { return nil }
                let decrement = max(0, old.0 - current.1)
                return decrement > 0 ? (current.0, decrement, current.1) : nil
            }
            if let winner = positiveDecrements.sorted(by: { lhs, rhs in
                if lhs.decrement != rhs.decrement {
                    return lhs.decrement > rhs.decrement
                }
                if lhs.remaining != rhs.remaining {
                    return lhs.remaining < rhs.remaining
                }
                return deterministicWindowOrder((lhs.window, 0), (rhs.window, 0))
            }).first {
                return winner.window.id
            }
            if let previousID,
               windows.contains(where: { $0.id == previousID && $0.remaining != .unavailable }) {
                return previousID
            }
        }

        if let coldStart = finite.sorted(by: { lhs, rhs in
            lhs.1 == rhs.1 ? deterministicWindowOrder(lhs, rhs) : lhs.1 < rhs.1
        }).first {
            return coldStart.0.id
        }
        if let unlimited = windows.first(where: { $0.remaining == .unlimited }) {
            return unlimited.id
        }
        return windows.first?.id
    }

    private static func deterministicWindowOrder(
        _ lhs: (SharedUsageWindowPresentation, Double),
        _ rhs: (SharedUsageWindowPresentation, Double)
    ) -> Bool {
        let rank: (SharedUsageWindowPresentation) -> Int = {
            switch $0.kind {
            case .fiveHour: 0
            case .sevenDay: 1
            default: 2
            }
        }
        let lhsRank = rank(lhs.0)
        let rhsRank = rank(rhs.0)
        return lhsRank == rhsRank ? lhs.0.id < rhs.0.id : lhsRank < rhsRank
    }

    private static func connectionStatus(_ state: AgentConnectorState) -> SharedConnectionStatus {
        switch state {
        case .ready: .connected
        case .waitingForFirstResponse: .transitional
        case .authenticationRequired: .authenticationRequired
        case .stale: .stale
        case .inactive: .disconnected
        case .unsupported: .unavailable
        case .failed: .failed
        }
    }

    private static func freshness(_ value: AgentConnectorFreshness) -> SharedUsageFreshness {
        switch value {
        case .fresh: .fresh
        case .stale: .stale
        case .unavailable: .unavailable
        }
    }
}

private extension SharedConnectionStatus {
    var accessibilityText: String {
        switch self {
        case .connected: "connected"
        case .transitional: "connecting"
        case .authenticationRequired: "authentication required"
        case .stale: "connection stale"
        case .disconnected: "disconnected"
        case .unavailable: "unavailable"
        case .failed: "connection failed"
        }
    }
}
