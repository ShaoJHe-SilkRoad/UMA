import CoreGraphics
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Unified usage gauge")
struct UsageGaugeTests {
    @Test("Tiers follow the remaining share: more than 50 green, 20 to 50 yellow, under 20 red")
    func tiers() {
        #expect(UsageGaugeTier.forRemaining(100) == .plenty)
        #expect(UsageGaugeTier.forRemaining(50.5) == .plenty)
        #expect(UsageGaugeTier.forRemaining(50) == .caution)
        #expect(UsageGaugeTier.forRemaining(20) == .caution)
        #expect(UsageGaugeTier.forRemaining(19.9) == .low)
        #expect(UsageGaugeTier.forRemaining(0) == .low)
        #expect(UsageGaugeTier.forRemaining(nil) == .unavailable)
        #expect(UsageGaugeTier.forRemaining(120) == .unavailable)
    }

    @Test("5H leads the big block and 7D rides the bar, each in its own tier")
    func fiveHourLeads() {
        let reading = UsageGaugeReading.make(
            fiveHour: UsageGaugeWindow(remainingPercent: 60),
            sevenDay: UsageGaugeWindow(remainingPercent: 10)
        )
        #expect(reading.lead == .fiveHour)
        #expect(reading.primaryTier == .plenty)
        #expect(reading.barTier == .low)
        #expect(reading.primaryValueText == "60%")
        #expect(reading.secondaryValueText == "10%")
        #expect(reading.barFraction == 0.1)
    }

    @Test("Without 5H, 7D takes the big block and the bar is full and blue")
    func sevenDayLeads() {
        let reading = UsageGaugeReading.make(fiveHour: nil, sevenDay: UsageGaugeWindow(remainingPercent: 95))
        #expect(reading.lead == .sevenDay)
        #expect(reading.primaryTier == .plenty)
        #expect(reading.barTier == .unlimited)
        #expect(reading.barFraction == 1)
        #expect(reading.secondaryValueText == nil)
    }

    @Test("No limit shows infinity with both parts full and blue")
    func unlimited() {
        let reading = UsageGaugeReading.make(fiveHour: nil, sevenDay: nil, isUnlimited: true)
        #expect(reading.primaryValueText == "∞")
        #expect(reading.primaryTier == .unlimited)
        #expect(reading.barTier == .unlimited)
        #expect(reading.primaryFraction == 1)
    }

    @Test("An outdated reading is grey at any level")
    func outdated() {
        let reading = UsageGaugeReading.make(
            fiveHour: UsageGaugeWindow(remainingPercent: 10),
            sevenDay: UsageGaugeWindow(remainingPercent: 90)
        ).markingOutdated(true)
        #expect(reading.primaryTier == .outdated)
        #expect(reading.barTier == .outdated)
    }

    @Test("The 7D bar runs from the top of the left end, around it and along the bottom")
    func wrapPathLength() {
        let geometry = UsageGaugeWrapPath.Geometry(
            rect: CGRect(x: 0, y: 0, width: 300, height: 72),
            leftRadius: 16, rightRadius: 16, inset: 3.5
        )
        // Two quarter arcs, the straight left side, and the bottom edge.
        let left: CGFloat = 12.5
        let expected = CGFloat.pi * left + (65 - 2 * left) + ((296.5 - 12.5) - (3.5 + left))
        #expect(abs(geometry.length - expected) < 0.001)
    }

    @Test("The 7D bar fills the logo column as its first tenth, then the bottom band")
    func barFillsLogoColumnFirst() {
        let geometry = UsageGaugeCardGeometry(size: CGSize(width: 300, height: 72))
        #expect(geometry.capFill(fraction: 0.05) == 36)
        #expect(geometry.capFill(fraction: 0.1) == 72)
        #expect(geometry.bottomFillWidth(fraction: 0.1) == 0)
        let span = 300 - geometry.capWidth
        #expect(abs(geometry.bottomFillWidth(fraction: 0.55) - span / 2) < 0.001)
        #expect(geometry.bottomFillWidth(fraction: 1) == span)
        #expect(geometry.bandHeight > (72 - geometry.bandHeight) * 2)
    }
}
