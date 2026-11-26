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
        case ("codex", "pro"), ("codex", "plus"), ("claude", "pro"), ("claude", "max"),
             ("gemini", "free"), ("gemini", "plus"), ("gemini", "pro"), ("gemini", "ultra"):
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
        guard let threshold = lowThresholdPercent(providerID: providerID, admittedPlan: admittedPlan) else {
            // Unknown plan/provider is intentionally neutral, never guessed as Pro/Plus/Max.
            return .unknownPlan
        }
        return remainingPercent < threshold ? .low : .normal
    }

    /// The remaining percentage below which an admitted plan reads as low, or
    /// nil when the plan is unknown. Views may mark it; they must not guess one.
    public static func lowThresholdPercent(providerID: String, admittedPlan: String?) -> Double? {
        let provider = providerID.lowercased().split(separator: ".").first.map(String.init)
        switch (provider, admittedPlanIdentifier(providerID: providerID, label: admittedPlan)) {
        case ("codex", "pro"), ("claude", "max"), ("gemini", "ultra"): return 10
        case ("codex", "plus"), ("claude", "pro"), ("gemini", "pro"): return 20
        case ("gemini", "free"), ("gemini", "plus"): return 25
        default: return nil
        }
    }

    public static func color(for assessment: LowRemainingAssessment) -> Color {
        switch (AUVLook.current, assessment) {
        case (.standard, .low): .red
        case (.standard, .normal): .green
        // Wabi-sabi's rust and moss; Brutalist's system red, and plain ink
        // for a normal level.
        case (.wabiSabi, .low): AUVLookPalette.dynamic(0x8A4129, 0xC0694A)
        case (.wabiSabi, .normal): AUVLookPalette.dynamic(0x5A7040, 0x93A86A)
        case (.brutalist, .low): AUVLookPalette.dynamic(0xFF3B30, 0xFF453A)
        case (.brutalist, .normal): AUVLookPalette.dynamic(0x000000, 0xF0F0EE)
        case (_, .unknownPlan), (_, .unavailable): .secondary
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
