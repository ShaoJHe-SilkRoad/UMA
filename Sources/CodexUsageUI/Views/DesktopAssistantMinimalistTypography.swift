import AppKit
import CoreText
import SwiftUI

/// One native type role and one measured slot geometry for every Minimalist row.
/// Both native font-width APIs are available from macOS 13 (UMA targets 14).
public enum DesktopAssistantMinimalistTypography {
    public struct Measurement {
        public let size: CGSize
        public let prefixWidth: CGFloat
        public let valueWidth: CGFloat
        public let pointSize: CGFloat
    }

    static var font: Font {
        .system(size: AppTypographyRole.assistantValue.size * AppTypography.currentPointSizeScale,
                weight: AppTypographyRole.assistantValue.weight)
        .width(.condensed)
        .monospacedDigit()
    }

    public static func parts(_ text: String) -> (prefix: String, value: String) {
        text.hasPrefix("≈") ? ("≈", String(text.dropFirst())) : ("", text)
    }

    public static func resolvedFont(scale: CGFloat = 1) -> NSFont {
        let size = AppTypographyRole.assistantValue.size * scale
        let base = NSFont.systemFont(ofSize: size, weight: .medium, width: .condensed)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    public static func measuredWidth(_ text: String, scale: CGFloat = 1) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: resolvedFont(scale: scale)]).width
    }

    public static func metrics(valueTexts: [String] = [], scale: CGFloat? = nil) -> Measurement {
        let scale = scale ?? AppTypography.currentPointSizeScale
        let font = resolvedFont(scale: scale)
        // Measure complete formatted strings so fallback symbols and punctuation
        // are included. Percent formatting currently emits integral 0...100.
        let supportedValues = (0...100).map { "\($0)%" } + ["∞", "—"]
        let values = supportedValues + valueTexts.map { parts($0).value }
        let width = values.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // Whole-point slack also covers SwiftUI/AppKit shaping and Retina rounding.
        let valueWidth = ceil(width) + 1
        let prefixWidth = ceil(("≈" as NSString).size(withAttributes: [.font: font]).width) + 1
        let horizontalInset: CGFloat = 5 // rounded edge and the existing logo glow
        let total = horizontalInset * 2 + DesktopAssistantMetrics.minimalistConnectionDiameter
            + DesktopAssistantMetrics.minimalistGap + prefixWidth + valueWidth
        let height = max(DesktopAssistantMetrics.minimalistHeight,
                         ceil(font.ascender - font.descender + font.leading) + 10)
        return Measurement(size: CGSize(width: ceil(total), height: height),
                           prefixWidth: prefixWidth, valueWidth: valueWidth,
                           pointSize: font.pointSize)
    }
}
