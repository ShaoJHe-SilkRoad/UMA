import AppKit
import CoreText
import Testing
@testable import CodexUsageUI

@Suite("UMA014 native condensed Minimalist typography")
struct UMA014MinimalistTypographyTests {
    @Test("Native condensed font preserves size, weight, and tabular feature")
    func nativeFont() {
        for scale: CGFloat in [1, 1.35, 1.5] {
            let font = DesktopAssistantMinimalistTypography.resolvedFont(scale: scale)
            #expect(abs(font.pointSize - 13 * scale) < 0.001)
            #expect(font.fontName.localizedCaseInsensitiveContains("Condensed"))
            let features = font.fontDescriptor.object(forKey: .featureSettings)
                as? [[NSFontDescriptor.FeatureKey: Int]]
            #expect(features?.contains {
                $0[.typeIdentifier] == kNumberSpacingType
                    && $0[.selectorIdentifier] == kMonospacedNumbersSelector
            } == true)
        }
    }

    @Test("100 percent and estimated 100 reserve uniform slots at enlarged scale")
    func measuredSlots() {
        for scale: CGFloat in [1, 1.35, 1.5] {
            let base = DesktopAssistantMinimalistTypography.metrics(scale: scale)
            for value in (0...100).map({ "\($0)%" }) + ["∞", "—"] {
                for formatted in [value, "≈" + value] {
                    let parts = DesktopAssistantMinimalistTypography.parts(formatted)
                    #expect(DesktopAssistantMinimalistTypography.measuredWidth(parts.value, scale: scale) < base.valueWidth)
                    #expect(DesktopAssistantMinimalistTypography.measuredWidth(parts.prefix, scale: scale) < base.prefixWidth)
                    #expect(DesktopAssistantMinimalistTypography.metrics(valueTexts: [formatted], scale: scale).size == base.size)
                }
            }
            let slots = base.prefixWidth + base.valueWidth
            #expect(base.size.width >= 18 + 3 + slots + 10)
            #expect(base.size.height >= 30)
            #expect(DesktopAssistantMinimalistTypography.measuredWidth("≈100%", scale: scale) < slots)
        }
    }

    @Test("Fallback symbols and decimal credit output use measured common width")
    func symbolsAndCredits() {
        for scale: CGFloat in [1, 1.35, 1.5] {
            for value in ["499", "500", "501", "9.99%", "99.99%", "1,234.56", "∞", "—"] {
                let metrics = DesktopAssistantMinimalistTypography.metrics(valueTexts: [value], scale: scale)
                #expect(DesktopAssistantMinimalistTypography.measuredWidth(value, scale: scale) < metrics.valueWidth)
                #expect(metrics.size.width >= DesktopAssistantMinimalistTypography.metrics(scale: scale).size.width)
            }
        }
        #expect(DesktopAssistantMinimalistTypography.parts("100%").prefix.isEmpty)
        #expect(DesktopAssistantMinimalistTypography.parts("≈100%").prefix == "≈")
        #expect(DesktopAssistantMetrics.size(for: .regular) == CGSize(width: 210, height: 60))
    }

    @Test("Wizard keeps raw quota threshold values and never fills native credits")
    func rawUsage() {
        func card(_ value: DesktopAssistantUsageValue, raw: Double? = nil, credits: Decimal? = nil) -> DesktopAssistantCard {
            DesktopAssistantCard(id: "codex.local", providerName: "Codex", planLabel: "pro",
                connectionState: .connected, selectedWindowShortLabel: "5H", selectedWindowAccessibilityLabel: "5 hours",
                usageValue: value, remainingPercent: raw, availableCredits: credits,
                severity: .normal, isStale: false)
        }
        #expect(card(.estimated(10), raw: 9.99).remainingPercent == 9.99)
        #expect(card(.finite(10), raw: 10).remainingPercent == 10)
        for value in [Double.nan, .infinity, -1, 101] {
            #expect(card(.finite(10), raw: value).tintFraction == nil)
        }
        #expect(card(.unlimited, raw: 100).tintFraction == nil)
        #expect(card(.unavailable, raw: 0).tintFraction == nil)
        #expect(card(.credits("499"), raw: 49.9, credits: 499).tintFraction == nil)
        #expect(card(.credits("499"), credits: 499).availableCredits == 499)
    }
}
