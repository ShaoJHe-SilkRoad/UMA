import Foundation
import Testing
@testable import CodexUsageUI

struct P2QuotaPresentationModelTests {
    @Test
    func unlimitedFiveHourFollowsValidatedWeeklyQuotaWithoutBar() {
        let usage = CodexLiveUsage(
            rateLimits: CodexRateLimitSnapshot(
                planType: "PRO",
                windows: [
                    CodexRateLimitWindow(
                        id: "five-hour",
                        creditsUnlimited: true,
                        usedPercent: 0,
                        windowDurationMinutes: 300,
                        resetsAt: nil
                    ),
                    CodexRateLimitWindow(
                        id: "seven-day",
                        usedPercent: 35,
                        windowDurationMinutes: 10_080,
                        resetsAt: nil
                    )
                ],
                creditsUnlimited: true
            ),
            availableResetCount: nil,
            lifetimeTokens: nil,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        )

        let snapshot = UsageSnapshot(live: usage, language: .english)

        #expect(snapshot.periods.map(\.id) == ["seven-day", "five-hour"])
        #expect(snapshot.periods[0].showsBar)
        #expect(!snapshot.periods[0].isSecondary)
        #expect(!snapshot.periods[1].showsBar)
        #expect(snapshot.periods[1].isSecondary)
    }

    @Test
    func weeklyOnlyFallbackAppendsUnlimitedFiveHourMetadata() {
        let usage = CodexLiveUsage(
            rateLimits: CodexRateLimitSnapshot(
                planType: "PLUS",
                windows: [
                    CodexRateLimitWindow(
                        id: "seven-day",
                        usedPercent: 25,
                        windowDurationMinutes: 10_080,
                        resetsAt: nil
                    )
                ]
            ),
            availableResetCount: nil,
            lifetimeTokens: nil,
            dailyUsage: nil,
            recentActivityCount: 0,
            apiCostEstimate: nil
        )

        let snapshot = UsageSnapshot(live: usage, language: .english)

        #expect(snapshot.periods.map(\.id) == ["seven-day", "provider.unlimited-five-hour"])
        #expect(snapshot.periods.last?.isUnlimited == true)
        #expect(snapshot.periods.last?.showsBar == false)
    }

    @Test
    func fiveSegmentsKeepStableWidthAndFractionalCurrentFill() {
        let model = QuotaBarModel(
            remainingPercent: 53,
            planLabel: "PRO",
            isUnlimited: false
        )

        #expect(model.segments.count == 5)
        #expect(abs(model.segments.map(\.relativeWidth).reduce(0, +) - 1) < 0.000_001)
        #expect(model.segments.map(\.fillFraction) == [1, 1, 0.65, 0, 0])
        #expect(model.segments[2].relativeWidth > model.segments[0].relativeWidth)
        #expect(model.segments[0].relativeWidth > model.segments[3].relativeWidth)
    }

    @Test(arguments: [
        ("PRO", 9.999, QuotaBarTone.low),
        ("PRO", 10, QuotaBarTone.normal),
        ("Prolite", 9.999, QuotaBarTone.low),
        ("PRO LITE", 10, QuotaBarTone.normal),
        ("PLUS", 19.999, QuotaBarTone.low),
        ("PLUS", 20, QuotaBarTone.normal),
        ("TEAM", 1, QuotaBarTone.normal)
    ])
    func planThresholdsAreStrict(
        plan: String,
        remaining: Double,
        expectedTone: QuotaBarTone
    ) {
        #expect(
            QuotaBarModel(
                remainingPercent: remaining,
                planLabel: plan,
                isUnlimited: false
            ).tone == expectedTone
        )
    }

    @Test
    func unknownAndUnlimitedValuesNeverUseThresholdRed() {
        #expect(
            QuotaBarModel(
                remainingPercent: nil,
                planLabel: "PRO",
                isUnlimited: false
            ).tone == .normal
        )
        #expect(
            QuotaBarModel(
                remainingPercent: .infinity,
                planLabel: "PLUS",
                isUnlimited: false
            ).tone == .normal
        )
        #expect(
            QuotaBarModel(
                remainingPercent: 0,
                planLabel: "PRO",
                isUnlimited: true
            ).tone == .normal
        )
    }
}
