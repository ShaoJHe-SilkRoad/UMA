import AppKit
import SwiftUI

/// Presentation only. These colors do not change view metrics or action state.
@MainActor
public enum UMAVisualStyle {
    /// A colour for light and dark mode; an appearance pack other than
    /// Standard may draw it with its own value instead.
    private static func adaptive(
        _ name: String, light: UInt32, dark: UInt32,
        look: @escaping @Sendable (AUVLook, Bool) -> UInt32? = { _, _ in nil }
    ) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = look(AUVLook.current, isDark) ?? (isDark ? dark : light)
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }

    public static let canvasColor = adaptive("AUV.canvas", light: 0xF3F5F8, dark: 0x1C1F24) {
        AUVLookPalette.canvasHex($0, isDark: $1)
    }
    public static let surfaceColor = adaptive("AUV.surface", light: 0xFDFEFF, dark: 0x262A31) {
        AUVLookPalette.surfaceHex($0, isDark: $1)
    }
    public static let toolbarColor = adaptive("AUV.toolbar", light: 0xFFFFFF, dark: 0x22262C) {
        AUVLookPalette.canvasHex($0, isDark: $1)
    }
    public static let separatorColor = adaptive("AUV.separator", light: 0xCCD2DC, dark: 0x4A515D) { look, isDark in
        switch look {
        case .standard: nil
        case .wabiSabi: isDark ? 0x3A3835 : 0xCFCCC5
        // Brutalist rules are ink.
        case .brutalist: isDark ? 0xF0F0EE : 0x000000
        }
    }
    public static let editorColor = adaptive("AUV.editor", light: 0xFAFBFE, dark: 0x20242B) {
        AUVLookPalette.surfaceHex($0, isDark: $1)
    }
    public static var canvas: Color { Color(nsColor: canvasColor) }
    public static var surface: Color { Color(nsColor: surfaceColor) }
    public static var toolbar: Color { Color(nsColor: toolbarColor) }
    public static var separator: Color { Color(nsColor: separatorColor) }
}

/// One type scale for the main window and both kinds of Settings, on macOS's
/// own text sizes: 13 for reading, 12 and 11 for supporting text, one display
/// size for each kind of number. Numbers use rounded figures of equal width.
public enum AUVType {
    /// The selected agent's headline percentage.
    public static var display: Font { AUVLookType.number(34, standard: .system(size: 34, weight: .semibold, design: .rounded)) }
    /// A quota value in the Usage card.
    public static var metric: Font { AUVLookType.number(22, standard: .system(size: 22, weight: .semibold, design: .rounded)) }
    /// The value at the end of an agent rail row.
    public static var railValue: Font { AUVLookType.number(17, standard: .system(size: 17, weight: .semibold, design: .rounded)) }
    /// An agent's name on its page, a Settings pane's title.
    public static var title: Font { AUVLookType.display(20, standard: .system(size: 20, weight: .semibold)) }
    /// Card titles and row names.
    public static var headline: Font { AUVLookType.text(13, strong: true) }
    public static var body: Font { AUVLookType.text(13) }
    public static var secondary: Font { AUVLookType.text(12) }
    public static var caption: Font { AUVLookType.text(11) }
    /// Small labels set above content: section names, window badges.
    public static var label: Font { AUVLookType.text(11, strong: true) }
}

/// Corner radii and spacing shared by cards, rows and controls.
public enum AUVShape {
    public static var cardRadius: CGFloat {
        switch AUVLook.current { case .standard: 12; case .wabiSabi: 10; case .brutalist: AUVFormwork.slab }
    }
    public static var rowRadius: CGFloat {
        switch AUVLook.current { case .standard: 10; case .wabiSabi: 8; case .brutalist: AUVFormwork.control }
    }
    public static let cardPadding: CGFloat = 16
    /// Wabi-sabi separates modules with space (ma) instead of boxes.
    public static var cardSpacing: CGFloat {
        switch AUVLook.current { case .standard: 12; case .wabiSabi: 30; case .brutalist: 18 }
    }
}
