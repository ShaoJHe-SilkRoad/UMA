import Foundation
import SwiftUI

/// Quota color only: connection, precision and freshness remain independent.
public enum LowRemainingAssessment: Equatable, Sendable {
    case low
    case normal
    case unknownPlan
    case unavailable
}

/// Apply only to an admitted value for the quota actually represented by the view.
/// Plan labels are the existing connector-projected identifiers (case-insensitive),
/// not display-name substring matches or inferred account capabilities.
public enum LowRemainingUsagePolicy {
    /// Allowlist publication boundary: never forward arbitrary account text.
    public static func admittedPlanIdentifier(providerID: String, label: String?) -> String? {
        let provider = providerID.lowercased().split(separator: ".").first.map(String.init)
        let plan = label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch (provider, plan) {
        case ("codex", "pro"), ("codex", "plus"), ("claude", "pro"), ("claude", "max"):
            return plan
        default: return nil
        }
    }

    public static func assessment(
        providerID: String,
        admittedPlan: String?,
        remainingPercent: Double?,
        availableCredits: Decimal? = nil
    ) -> LowRemainingAssessment {
        let provider = providerID.lowercased().split(separator: ".").first.map(String.init)
        if provider == "workbuddy" {
            // Credits have no percentage denominator. Never substitute the percent input.
            guard let availableCredits, !availableCredits.isNaN, availableCredits >= 0 else {
                return .unavailable
            }
            return availableCredits < 500 ? .low : .normal
        }
        guard let remainingPercent, remainingPercent.isFinite,
              (0...100).contains(remainingPercent) else { return .unavailable }
        let plan = admittedPlanIdentifier(providerID: providerID, label: admittedPlan)
        let threshold: Double
        switch (provider, plan) {
        case ("codex", "pro"), ("claude", "max"):
            threshold = 10
        case ("codex", "plus"), ("claude", "pro"):
            threshold = 20
        default:
            // Unknown plan/provider is intentionally neutral, never guessed as Pro/Plus/Max.
            return .unknownPlan
        }
        return remainingPercent < threshold ? .low : .normal
    }

    public static func color(for assessment: LowRemainingAssessment) -> Color {
        switch assessment {
        case .low: .red
        case .normal: .green
        case .unknownPlan, .unavailable: .secondary
        }
    }

    public static func color(
        providerID: String,
        admittedPlan: String?,
        remainingPercent: Double?,
        availableCredits: Decimal? = nil
    ) -> Color {
        color(for: assessment(providerID: providerID, admittedPlan: admittedPlan,
                              remainingPercent: remainingPercent, availableCredits: availableCredits))
    }
}
