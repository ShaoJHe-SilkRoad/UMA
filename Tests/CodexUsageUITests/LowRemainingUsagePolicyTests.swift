import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Shared admitted low-remaining quota colors")
struct LowRemainingUsagePolicyTests {
    @Test("All percentage boundaries use unrounded strict less-than comparisons")
    func percentageBoundaries() {
        let values = [0.0, 9, 9.99, 10, 14, 19.99, 20, 99, 100]
        for (provider, plan, threshold) in [
            ("codex.local", "pro", 10.0), ("codex", "plus", 20.0),
            ("claude.code", "pro", 20.0), ("claude.browserSync", "max", 10.0)
        ] {
            for value in values + [threshold.nextDown, threshold.nextUp] {
                #expect(LowRemainingUsagePolicy.assessment(
                    providerID: provider, admittedPlan: plan, remainingPercent: value
                ) == (value < threshold ? .low : .normal))
            }
        }
    }

    @Test("Connector plan identifiers accept case and whitespace without marketing guesses")
    func admittedAliases() {
        #expect(LowRemainingUsagePolicy.assessment(providerID: "CODEX.local", admittedPlan: " PRO ", remainingPercent: 9.99) == .low)
        #expect(LowRemainingUsagePolicy.assessment(providerID: "claude", admittedPlan: "MAX", remainingPercent: 10) == .normal)
        for plan in [nil, "", "unknown", "team", "enterprise", "ChatGPT Pro", "max_5x", "not-pro"] as [String?] {
            #expect(LowRemainingUsagePolicy.assessment(providerID: "codex", admittedPlan: plan, remainingPercent: 0) == .unknownPlan)
        }
        #expect(LowRemainingUsagePolicy.assessment(providerID: "unsupported", admittedPlan: "pro", remainingPercent: 0) == .unknownPlan)
    }

    @Test("Missing invalid and unlimited percentage values are never low quota")
    func unavailableValues() {
        for percent in [nil, .nan, .infinity, -.infinity, -1, 100.01] as [Double?] {
            #expect(LowRemainingUsagePolicy.assessment(providerID: "codex", admittedPlan: "plus", remainingPercent: percent) == .unavailable)
        }
    }

    @Test("WorkBuddy compares actual Decimal credits, never percentage normalization")
    func creditBoundaries() {
        for (credits, expected) in [(499, LowRemainingAssessment.low), (500, .normal), (501, .normal)] {
            #expect(LowRemainingUsagePolicy.assessment(providerID: "workBuddy", admittedPlan: nil, remainingPercent: 0, availableCredits: Decimal(credits)) == expected)
            #expect(LowRemainingUsagePolicy.assessment(providerID: "workbuddy.manualAvailability", admittedPlan: nil, remainingPercent: 100, availableCredits: Decimal(credits)) == expected)
        }
        for credits in [nil, Decimal.nan, Decimal(-1)] as [Decimal?] {
            #expect(LowRemainingUsagePolicy.assessment(providerID: "workbuddy", admittedPlan: nil, remainingPercent: 14, availableCredits: credits) == .unavailable)
        }
    }

    @Test("Qualified estimates retain their precision and use the same underlying quota")
    func estimatesAndSameQuota() {
        let exact = SharedUsageWindowPresentation(id: "7d", kind: .sevenDay, compactLabel: "7D", accessibilityLabel: "Seven days", remaining: .finite(19.99), resetsAt: nil, resetText: "")
        let estimate = SharedUsageWindowPresentation(id: "5h", kind: .fiveHour, compactLabel: "5H", accessibilityLabel: "Five hours", remaining: .finite(20), isEstimated: true, resetsAt: nil, resetText: "")
        #expect(LowRemainingUsagePolicy.assessment(providerID: "claude", admittedPlan: "pro", remainingPercent: exact.remaining.finitePercent) == .low)
        #expect(LowRemainingUsagePolicy.assessment(providerID: "claude", admittedPlan: "pro", remainingPercent: estimate.remaining.finitePercent) == .normal)
        #expect(estimate.isEstimated == true)
        #expect(exact.remaining.displayPercent == 20) // Color deliberately differs from rounded display.
        let shared = SharedUsageCardPresentation(
            id: "claude.browserSync", providerName: "Claude", planLabel: "pro",
            connectionStatus: .connected, freshness: .fresh, windows: [exact],
            selectedWindowID: exact.id, remaining: exact.remaining,
            severity: .normal
        )
        let wizard = DesktopAssistantCard(shared: shared)
        #expect(wizard.remainingPercent == 19.99)
        #expect(LowRemainingUsagePolicy.assessment(providerID: wizard.id,
            admittedPlan: wizard.planLabel, remainingPercent: wizard.remainingPercent) == .low)
    }
}
