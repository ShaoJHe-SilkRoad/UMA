import Foundation

enum QuotaBarTone: Sendable, Equatable {
    case normal
    case low
}

struct QuotaBarSegment: Sendable, Equatable {
    let relativeWidth: Double
    let fillFraction: Double
}

/// Pure geometry and threshold model for a five-segment quota bar.
///
/// Every segment represents 20 percentage points. Width emphasis is kept
/// deliberately small, then normalized so the five segments always occupy
/// exactly the same total available width.
struct QuotaBarModel: Sendable, Equatable {
    let segments: [QuotaBarSegment]
    let tone: QuotaBarTone

    init(remainingPercent: Int, planLabel: String?, isUnlimited: Bool) {
        self.init(
            remainingPercent: Double(remainingPercent),
            planLabel: planLabel,
            isUnlimited: isUnlimited
        )
    }

    init(remainingPercent: Double?, planLabel: String?, isUnlimited: Bool) {
        let normalizedRemaining = Self.normalizedRemaining(
            remainingPercent,
            isUnlimited: isUnlimited
        )
        let fillFractions = (0..<5).map { index in
            min(1, max(0, (normalizedRemaining - Double(index * 20)) / 20))
        }
        let weights = fillFractions.map { fraction in
            if fraction > 0, fraction < 1 { return 1.08 }
            if fraction == 0 { return 0.98 }
            return 1.0
        }
        let totalWeight = weights.reduce(0, +)
        segments = zip(weights, fillFractions).map { weight, fillFraction in
            QuotaBarSegment(
                relativeWidth: weight / totalWeight,
                fillFraction: fillFraction
            )
        }
        tone = Self.tone(
            remainingPercent: remainingPercent,
            planLabel: planLabel,
            isUnlimited: isUnlimited
        )
    }

    private static func normalizedRemaining(
        _ remainingPercent: Double?,
        isUnlimited: Bool
    ) -> Double {
        guard !isUnlimited, let remainingPercent else { return isUnlimited ? 100 : 0 }
        if remainingPercent == .infinity { return 100 }
        guard remainingPercent.isFinite else { return 0 }
        return min(100, max(0, remainingPercent))
    }

    private static func tone(
        remainingPercent: Double?,
        planLabel: String?,
        isUnlimited: Bool
    ) -> QuotaBarTone {
        guard !isUnlimited,
              let remainingPercent,
              remainingPercent.isFinite else {
            return .normal
        }
        let normalizedPlan = (planLabel ?? "")
            .lowercased()
            .filter(\.isLetter)
        let threshold: Double?
        switch normalizedPlan {
        case "pro", "prolite": threshold = 10
        case "plus": threshold = 20
        default: threshold = nil
        }
        guard let threshold, remainingPercent < threshold else { return .normal }
        return .low
    }
}
