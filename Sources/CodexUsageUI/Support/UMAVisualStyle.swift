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
