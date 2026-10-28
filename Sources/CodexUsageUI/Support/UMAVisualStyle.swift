import AppKit
import SwiftUI

/// Presentation only. These colors do not change view metrics or action state.
@MainActor
public enum UMAVisualStyle {
    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }

    public static let canvasColor = adaptive("AUV.canvas", light: 0xF3F5F8, dark: 0x1C1F24)
    public static let surfaceColor = adaptive("AUV.surface", light: 0xFDFEFF, dark: 0x262A31)
    public static let toolbarColor = adaptive("AUV.toolbar", light: 0xFFFFFF, dark: 0x22262C)
    public static let separatorColor = adaptive("AUV.separator", light: 0xCCD2DC, dark: 0x4A515D)
    public static let editorColor = adaptive("AUV.editor", light: 0xFAFBFE, dark: 0x20242B)
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
    public static let display = Font.system(size: 34, weight: .semibold, design: .rounded)
    /// A quota value in the Usage card.
    public static let metric = Font.system(size: 22, weight: .semibold, design: .rounded)
    /// The value at the end of an agent rail row.
    public static let railValue = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// An agent's name on its page, a Settings pane's title.
    public static let title = Font.system(size: 20, weight: .semibold)
    /// Card titles and row names.
    public static let headline = Font.system(size: 13, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let secondary = Font.system(size: 12)
    public static let caption = Font.system(size: 11)
    /// Small labels set above content: section names, window badges.
    public static let label = Font.system(size: 11, weight: .semibold)
}

/// Corner radii and spacing shared by cards, rows and controls.
public enum AUVShape {
    public static let cardRadius: CGFloat = 12
    public static let rowRadius: CGFloat = 10
    public static let cardPadding: CGFloat = 16
    public static let cardSpacing: CGFloat = 12
}
