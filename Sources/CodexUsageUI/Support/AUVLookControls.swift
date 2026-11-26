import AppKit
import SwiftUI

// Controls in the appearance packs, for the whole app: SwiftUI buttons,
// segmented choices and sections, and AppKit buttons and segmented controls.
// Standard keeps the system's own controls untouched.

// MARK: - Fonts

extension AUVLookType {
    /// Wabi-sabi's headings: Hiragino Mincho, light. Brutalist: heavy system.
    public static func heading(_ size: CGFloat, look: AUVLook = .current, standard: Font) -> Font {
        switch look {
        case .standard: standard
        case .wabiSabi: .custom("HiraMinProN-W3", size: size)
        case .brutalist: .system(size: size, weight: .heavy)
        }
    }

    static func nsText(_ size: CGFloat, strong: Bool = false, look: AUVLook = .current) -> NSFont {
        switch look {
        case .standard:
            return .systemFont(ofSize: size, weight: strong ? .semibold : .regular)
        case .wabiSabi:
            return NSFont(name: strong ? "HiraginoSans-W6" : "HiraginoSans-W3", size: size)
                ?? .systemFont(ofSize: size)
        case .brutalist:
            return .systemFont(ofSize: size, weight: strong ? .bold : .regular)
        }
    }
}

// MARK: - SwiftUI buttons

/// The default button in a pack. Wabi-sabi: a thin ink outline with a soft
/// corner and Hiragino text. Brutalist: a square slab of concrete inside a
/// 1 pt rule, inverted while pressed.
struct AUVLookButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let look = AUVLook.current
        let ink = AUVLookPalette.ink(look, isDark: isDark)
        let small = controlSize == .small || controlSize == .mini
        let destructive = configuration.role == .destructive
        let textColor = destructive ? AUVLookPalette.destructive(isDark: isDark) : ink
        let pressed = configuration.isPressed
        return configuration.label
            .font(AUVLookType.text(small ? 11 : 13, strong: look == .brutalist && !small))
            .lineLimit(1)
            .padding(.horizontal, small ? 8 : 12)
            .padding(.vertical, small ? 3 : 5)
            .foregroundStyle(look == .brutalist && pressed
                             ? (AUVLookPalette.canvas(look, isDark: isDark) ?? .white) : textColor)
            .background {
                switch look {
                case .brutalist:
                    Rectangle().fill(pressed ? ink : (AUVLookPalette.surface(look, isDark: isDark) ?? .clear))
                        .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
                default:
                    // Frameless: ink text on stone, a faint wash while pressed.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ink.opacity(pressed ? 0.08 : 0))
                }
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - Segmented choices

public extension View {
    /// A segmented choice. Brutalist and Wabi-sabi use the system's radio
    /// buttons laid out in a row: raw controls as found, tinted by the pack.
    @ViewBuilder func auvSegmentedStyle() -> some View {
        if AUVLook.current.isStandard {
            pickerStyle(.segmented)
        } else {
            pickerStyle(.radioGroup).horizontalRadioGroupLayout()
        }
    }
}

// MARK: - Sections

/// A group of rows in a pack, outside a Form. Wabi-sabi: a quiet title and
/// rows on hairlines, no box. Brutalist: a table, a heavy head over a rule,
/// rules between rows, the whole inside a 1 pt frame.
struct AUVLookSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        let isDark = colorScheme == .dark
        let look = AUVLook.current
        let ink = AUVLookPalette.ink(look, isDark: isDark)
        let rule = look == .brutalist ? ink.opacity(0.5) : Color.clear
        VStack(alignment: .leading, spacing: look == .brutalist ? 0 : 8) {
            Group {
                if look == .brutalist {
                    Text(title).font(.system(size: 13, weight: .heavy))
                        .padding(.horizontal, 12).frame(height: 32)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(ink).frame(height: 1) }
                } else {
                    Text(title).font(.custom("HiraMinProN-W3", size: 14))
                        .tracking(1)
                        .foregroundStyle(ink.opacity(0.78))
                }
            }
            .accessibilityAddTraits(.isHeader)
            rows(rule: rule)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let footer, !footer.isEmpty, look == .brutalist {
                Text(footer).font(AUVLookType.text(11)).foregroundStyle(ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(rule).frame(height: 1) }
            }
        }
        .background { if look == .brutalist { AUVLookPalette.surface(look, isDark: isDark) } }
        .overlay { if look == .brutalist { Rectangle().strokeBorder(ink, lineWidth: 1) } }
        if let footer, !footer.isEmpty, look != .brutalist {
            Text(footer).font(AUVLookType.text(11)).foregroundStyle(ink.opacity(0.68))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -2)
        }
    }

    @ViewBuilder private func rows(rule: Color) -> some View {
        let brutal = AUVLook.current == .brutalist
        if #available(macOS 15.0, *) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(subviews: content) { row in
                    row
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, brutal ? 12 : 0)
                        .padding(.vertical, brutal ? 8 : 7)
                        .overlay(alignment: .top) { if brutal { Rectangle().fill(rule).frame(height: 1) } }
                }
            }
            // The head's rule already closes the top in Brutalist; in
            // Wabi-sabi the first hairline sits under the title.
            .padding(.top, brutal ? -1 : 0)
        } else {
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(brutal ? 12 : 0)
        }
    }
}

// MARK: - AppKit

/// An NSButton that draws itself in the current pack. Standard draws the
/// system bezel exactly as before.
open class AUVLookButton: NSButton {
    /// The filled, primary action.
    public var auvProminent = false { didSet { applyLook() } }
    /// Icon-only buttons keep no frame; they only take the ink colour.
    public var auvIconOnly = false { didSet { applyLook() } }
    private var savedBezel: (bordered: Bool, style: NSButton.BezelStyle)?
    private var isApplyingLook = false

    open override var title: String { didSet { applyLook() } }
    open override var isEnabled: Bool { didSet { applyLook() } }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyLook()
    }

    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyLook()
    }

    open override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        guard !AUVLook.current.isStandard, !auvIconOnly else { return size }
        size.width += 20
        size.height = max(size.height + 6, 24)
        return size
    }

    open override func highlight(_ flag: Bool) {
        super.highlight(flag)
        guard !AUVLook.current.isStandard else { return }
        alphaValue = flag ? 0.7 : 1
    }

    public func applyLook() {
        // Setting the attributed title can set the title again.
        guard !isApplyingLook else { return }
        isApplyingLook = true
        defer { isApplyingLook = false }
        let look = AUVLook.current
        guard !look.isStandard else {
            if let savedBezel {
                isBordered = savedBezel.bordered
                bezelStyle = savedBezel.style
                layer?.borderWidth = 0
                layer?.backgroundColor = nil
                self.savedBezel = nil
            }
            return
        }
        if savedBezel == nil { savedBezel = (isBordered, bezelStyle) }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let ink = AUVLookPalette.nsHex(look == .wabiSabi ? (isDark ? 0xD8D4CC : 0x272523)
                                                          : (isDark ? 0xF0F0EE : 0x000000))
        let canvas = AUVLookPalette.nsHex(AUVLookPalette.canvasHex(look, isDark: isDark) ?? 0xFFFFFF)
        let surface = AUVLookPalette.nsHex(AUVLookPalette.surfaceHex(look, isDark: isDark) ?? 0xFFFFFF)
        isBordered = false
        wantsLayer = true
        contentTintColor = ink.withAlphaComponent(isEnabled ? 1 : 0.45)
        guard !auvIconOnly else {
            layer?.borderWidth = 0
            layer?.backgroundColor = nil
            return
        }
        let fill: NSColor
        let text: NSColor
        switch (look, auvProminent) {
        case (.brutalist, true): fill = ink; text = canvas
        case (.brutalist, false): fill = surface; text = ink
        case (_, true): fill = ink.withAlphaComponent(0.88); text = canvas
        default: fill = .clear; text = ink
        }
        layer?.cornerRadius = look == .brutalist ? 0 : 6
        layer?.borderWidth = look == .brutalist ? 1 : 0
        layer?.borderColor = ink.cgColor
        layer?.backgroundColor = fill.cgColor
        contentTintColor = text.withAlphaComponent(isEnabled ? 1 : 0.45)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: AUVLookType.nsText(13, strong: look == .brutalist && auvProminent),
            .foregroundColor: text.withAlphaComponent(isEnabled ? 1 : 0.45),
            .paragraphStyle: paragraph,
        ])
        invalidateIntrinsicContentSize()
    }
}

@MainActor
public enum AUVLookAppKit {
    /// A segmented control in the current pack: square segments with an ink
    /// selection in Brutalist; an indigo selection and Hiragino in Wabi-sabi.
    public static func style(_ control: NSSegmentedControl) {
        let look = AUVLook.current
        guard !look.isStandard else { return }
        let isDark = control.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        switch look {
        case .brutalist:
            control.segmentStyle = .smallSquare
            control.selectedSegmentBezelColor = AUVLookPalette.nsHex(isDark ? 0xF0F0EE : 0x000000)
            control.font = AUVLookType.nsText(13, strong: true)
        case .wabiSabi:
            control.selectedSegmentBezelColor = AUVLookPalette.nsHex(isDark ? 0xD8D4CC : 0x272523)
            control.font = AUVLookType.nsText(13)
        case .standard:
            break
        }
    }
}

// MARK: - Group surfaces

/// A group's surface: Standard keeps its own faint wash and corner;
/// Wabi-sabi a barely-there wash with a soft corner; Brutalist concrete in a
/// 1 pt rule, square.
struct AUVLookGroupSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let standardOpacity: Double
    let radius: CGFloat
    let standardStroke: Bool

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        switch AUVLook.current {
        case .standard:
            content
                .background(Color.primary.opacity(standardOpacity), in: RoundedRectangle(cornerRadius: radius))
                .overlay {
                    if standardStroke {
                        RoundedRectangle(cornerRadius: radius).strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
                    }
                }
        // No panel: the group stands on the stone, apart by space.
        case .wabiSabi:
            content
        case .brutalist:
            content
                .background(AUVLookPalette.surface(isDark: isDark))
                .overlay(Rectangle().strokeBorder(AUVLookPalette.ink(isDark: isDark), lineWidth: 1))
        }
    }
}

extension View {
    func auvGroupSurface(standardOpacity: Double, radius: CGFloat, standardStroke: Bool = false) -> some View {
        modifier(AUVLookGroupSurface(standardOpacity: standardOpacity, radius: radius, standardStroke: standardStroke))
    }
}

// MARK: - Ink foreground

private struct AUVInkForeground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if AUVLook.current.isStandard {
            content
        } else {
            content.foregroundStyle(AUVLookPalette.ink(isDark: colorScheme == .dark))
        }
    }
}

extension View {
    /// Text links and menus in ink in a pack; unchanged in Standard.
    func auvInkForeground() -> some View { modifier(AUVInkForeground()) }
}

// MARK: - Card ground

private struct AUVCardOnCanvasKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True where a gauge card sits on the window's own canvas (the
    /// drop-down, the agent page), so Wabi-sabi can leave its unused part
    /// empty instead of drawing a ground.
    var auvCardOnCanvas: Bool {
        get { self[AUVCardOnCanvasKey.self] }
        set { self[AUVCardOnCanvasKey.self] = newValue }
    }
}
