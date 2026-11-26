import AppKit
import SwiftUI

/// An appearance pack: purely visual. Structure, data and actions stay the
/// same in every look (design/auv-usage-gauge-20261125/THEMES-NOTES.md).
///
/// - Standard: glass, system type, the gauge's own tier colours.
/// - Wabi-sabi: quiet stone, no boxes; each tier a natural dye (moss, ochre,
///   rust, indigo); an outdated reading fades instead of turning grey.
/// - Brutalist: concrete, square corners and 1 pt rules; structure drawn,
///   fills in monochrome with the tier as a solid block of system colour
///   where the level ends.
public enum AUVLook: String, CaseIterable, Identifiable, Sendable {
    case standard
    case wabiSabi
    case brutalist

    public var id: String { rawValue }

    /// The look every view draws with. Set only through `AUVLookState`, which
    /// also redraws the windows; previews set it directly before rendering.
    public nonisolated(unsafe) static var current: AUVLook = .standard

    public var isStandard: Bool { self == .standard }
}

/// Brutalist's formwork. macOS draws every window's corner round, so the
/// concrete is cast in that mould: one family of radii taken from the
/// window's own corner, heavy outer rules, and a gutter so no slab meets the
/// window's edge.
public enum AUVFormwork {
    /// Modules, sections, the drop-down's frame.
    public static let slab: CGFloat = 12
    /// Gauge cards (never more than 30% of the card's height).
    public static let card: CGFloat = 10
    /// Buttons, chosen rows, capsules.
    public static let control: CGFloat = 6
    /// The outer rule of a slab or card.
    public static let rule: CGFloat = 2
}

/// Publishes the current look so each window's root can redraw with it.
@MainActor
public final class AUVLookState: ObservableObject {
    public static let shared = AUVLookState()
    @Published public private(set) var look: AUVLook = AUVLook.current

    public func apply(_ look: AUVLook) {
        guard AUVLook.current != look || self.look != look else { return }
        AUVLook.current = look
        self.look = look
    }
}

private struct AUVLookRoot: ViewModifier {
    @ObservedObject private var state = AUVLookState.shared

    func body(content: Content) -> some View {
        content
            .modifier(AUVLookToggleStyle(look: state.look))
            // Static tokens read the look; a new identity redraws them all.
            .id(state.look)
    }
}

private struct AUVLookToggleStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let look: AUVLook

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        switch look {
        case .standard: content
        case .wabiSabi:
            content.toggleStyle(AUVQuietSwitchStyle())
                .buttonStyle(AUVLookButtonStyle())
                .tint(AUVLookPalette.ink(.wabiSabi, isDark: isDark))
                .font(AUVLookType.text(13))
        // Raw controls: the system's own checkbox, in ink.
        case .brutalist:
            content.toggleStyle(.checkbox)
                .buttonStyle(AUVLookButtonStyle())
                .tint(AUVLookPalette.ink(.brutalist, isDark: isDark))
                .font(AUVLookType.text(13))
        }
    }
}

public extension View {
    /// Put on each window's root view so a change of look redraws it.
    func auvLookRoot() -> some View { modifier(AUVLookRoot()) }
}

// MARK: - Palette

/// Colours of the current look. Standard returns nil or the system's own
/// colours where the existing views keep their own.
public enum AUVLookPalette {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: alpha)
    }

    static func nsHex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// A colour that follows light and dark mode by itself.
    public static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsHex(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    /// The window's ground: stone or charcoal; dry or wet concrete.
    public static func canvasHex(_ look: AUVLook, isDark: Bool) -> UInt32? {
        switch look {
        case .standard: nil
        case .wabiSabi: isDark ? 0x1D1C1A : 0xE6E4DF
        case .brutalist: isDark ? 0x262625 : 0xCFCECA
        }
    }

    /// A raised surface: a faint ink wash on stone; a lighter pour of concrete.
    public static func surfaceHex(_ look: AUVLook, isDark: Bool) -> UInt32? {
        switch look {
        case .standard: nil
        case .wabiSabi: isDark ? 0x232220 : 0xDEDCD7
        case .brutalist: isDark ? 0x30302F : 0xDDDCD8
        }
    }

    public static func canvas(_ look: AUVLook = .current, isDark: Bool) -> Color? {
        canvasHex(look, isDark: isDark).map { hex($0) }
    }

    public static func surface(_ look: AUVLook = .current, isDark: Bool) -> Color? {
        surfaceHex(look, isDark: isDark).map { hex($0) }
    }

    /// The text colour: sumi ink; black on concrete. Standard keeps `.primary`.
    public static func ink(_ look: AUVLook = .current, isDark: Bool) -> Color {
        switch look {
        case .standard: Color.primary
        case .wabiSabi: hex(isDark ? 0xD8D4CC : 0x272523)
        case .brutalist: isDark ? hex(0xF0F0EE) : Color.black
        }
    }

    // Wabi-sabi's four dyes: 苔 moss, 黄土 ochre, 錆 rust, 藍 indigo.
    public static func moss(isDark: Bool) -> Color { hex(isDark ? 0x93A86A : 0x5A7040) }
    public static func ochre(isDark: Bool) -> Color { hex(isDark ? 0xC49A55 : 0x9C7A3C) }
    public static func rust(isDark: Bool) -> Color { hex(isDark ? 0xC0694A : 0x8A4129) }
    public static func indigo(isDark: Bool) -> Color { hex(isDark ? 0x7F97B0 : 0x3B4F66) }

    /// Brutalist's colours as found: the system's own.
    public static func system(_ tier: UsageGaugeTier, isDark: Bool) -> Color {
        switch tier {
        case .plenty: hex(isDark ? 0x30D158 : 0x34C759)
        case .caution: hex(isDark ? 0xFFD60A : 0xFFCC00)
        case .low: hex(isDark ? 0xFF453A : 0xFF3B30)
        case .unlimited: hex(isDark ? 0x0A84FF : 0x007AFF)
        case .outdated, .unavailable: Color(white: isDark ? 0.55 : 0.5)
        }
    }

    /// The dye for a tier.
    public static func dye(_ tier: UsageGaugeTier, isDark: Bool) -> Color {
        switch tier {
        case .plenty: moss(isDark: isDark)
        case .caution: ochre(isDark: isDark)
        case .low: rust(isDark: isDark)
        case .unlimited: indigo(isDark: isDark)
        case .outdated, .unavailable: ink(.wabiSabi, isDark: isDark).opacity(0.5)
        }
    }

    /// A destructive action's colour ("断开连接").
    public static func destructive(_ look: AUVLook = .current, isDark: Bool) -> Color {
        switch look {
        case .standard: Color.red
        case .wabiSabi: rust(isDark: isDark)
        case .brutalist: system(.low, isDark: isDark)
        }
    }

    /// The accent: the system accent; indigo; plain ink.
    public static func accent(_ look: AUVLook = .current, isDark: Bool) -> Color {
        switch look {
        case .standard: Color.accentColor
        // Ink: the dyes are kept for the tiers.
        case .wabiSabi: ink(.wabiSabi, isDark: isDark)
        case .brutalist: ink(.brutalist, isDark: isDark)
        }
    }

    /// The colour a low value's figure takes.
    public static func lowFigure(_ look: AUVLook = .current, isDark: Bool) -> Color {
        switch look {
        case .standard: UsageGaugePalette.color(.low, isDark: isDark)
        case .wabiSabi: rust(isDark: isDark)
        case .brutalist: system(.low, isDark: isDark)
        }
    }

    /// A tier colour for the rest of the app (rail fills, small bars) in the
    /// current look.
    public static func tier(_ tier: UsageGaugeTier, isDark: Bool, look: AUVLook = .current) -> Color {
        switch look {
        case .standard: UsageGaugePalette.color(tier, isDark: isDark)
        case .wabiSabi: dye(tier, isDark: isDark)
        // Monochrome concrete; the system colour only marks a level's end.
        case .brutalist: ink(.brutalist, isDark: isDark).opacity(0.55)
        }
    }
}

// MARK: - Type

/// Type of the current look. Standard returns the existing system fonts.
public enum AUVLookType {
    /// A text face: a quiet humanist sans (Hiragino Sans W3/W6); the system
    /// font as found, regular and bold.
    public static func text(_ size: CGFloat, strong: Bool = false, look: AUVLook = .current,
                            standardWeight: Font.Weight = .regular) -> Font {
        switch look {
        case .standard: .system(size: size, weight: strong ? .semibold : standardWeight)
        case .wabiSabi: .custom(strong ? "HiraginoSans-W6" : "HiraginoSans-W3", size: size)
        case .brutalist: .system(size: size, weight: strong ? .bold : .regular)
        }
    }

    /// Figures: a light serif, small and quiet; heavy, tight and monumental.
    public static func number(_ size: CGFloat, look: AUVLook = .current, standard: Font) -> Font {
        switch look {
        case .standard: standard
        case .wabiSabi: .system(size: size, weight: .light, design: .serif).monospacedDigit()
        case .brutalist: .system(size: size, weight: .heavy).monospacedDigit()
        }
    }

    /// A display headline (an agent's name on its page).
    public static func display(_ size: CGFloat, look: AUVLook = .current, standard: Font) -> Font {
        switch look {
        case .standard: standard
        // Headlines in Hiragino Mincho: the one place a serif speaks.
        case .wabiSabi: .custom("HiraMinProN-W3", size: size + 2)
        case .brutalist: .system(size: size + 8, weight: .heavy)
        }
    }
}

// MARK: - Controls

/// Wabi-sabi's switch: a thin outline, an indigo wash when on.
struct AUVQuietSwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        let ink = AUVLookPalette.ink(.wabiSabi, isDark: isDark)
        let on = configuration.isOn
        HStack {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? ink.opacity(0.14) : Color.clear)
                    .overlay(Capsule().strokeBorder(on ? ink.opacity(0.55) : ink.opacity(0.35), lineWidth: 0.8))
                    .frame(width: 30, height: 16)
                Circle()
                    .fill(on ? ink : ink.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .padding(3)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? Text("On") : Text("Off"))
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

// MARK: - Surfaces

/// A module's surface in the current look. Standard keeps the gauge's glass;
/// wabi-sabi has no box at all, space separates modules; brutalist is a
/// square slab of concrete inside a 1 pt rule.
struct AUVLookModuleSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        switch AUVLook.current {
        case .standard:
            content.modifier(UsageGaugeSurface(cornerRadius: cornerRadius))
        case .wabiSabi:
            content
        case .brutalist:
            let slab = RoundedRectangle(cornerRadius: AUVFormwork.slab, style: .continuous)
            content
                .background(AUVLookPalette.surface(.brutalist, isDark: isDark))
                .clipShape(slab)
                .overlay(slab.strokeBorder(AUVLookPalette.ink(.brutalist, isDark: isDark), lineWidth: AUVFormwork.rule))
        }
    }
}

/// A text link: the system link style; an underlined ink link in the packs.
private struct AUVLinkStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if AUVLook.current.isStandard {
            content.buttonStyle(.link)
        } else {
            content
                .buttonStyle(.plain)
                .foregroundStyle(AUVLookPalette.ink(isDark: colorScheme == .dark)
                    .opacity(AUVLook.current == .wabiSabi ? 0.65 : 1))
        }
    }
}

extension View {
    func auvLinkStyle() -> some View { modifier(AUVLinkStyle()) }
}

// MARK: - Minimalist capsule

/// The Minimalist capsule in an appearance pack: an opaque ground, the lead
/// level, and the 7D bar as a thin line along the bottom. Wabi-sabi keeps the
/// capsule's round end; Brutalist is a square slab in a 1 pt rule with the
/// tier as a block where the level ends.
struct AUVLookMinimalCapsule<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let reading: UsageGaugeReading
    let size: CGSize
    let showsLevel: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if AUVLook.current == .brutalist { brutalist } else { wabiSabi }
    }

    private var isDark: Bool { colorScheme == .dark }
    private var lead: Double { reading.primaryFraction ?? 0 }
    private var bar: Double { reading.barFraction ?? 0 }
    private func live(_ tier: UsageGaugeTier, _ percent: Double?) -> UsageGaugeTier {
        tier == .outdated ? .forRemaining(percent) : tier
    }

    /// Wabi-sabi: the lead level in its dye, the 7D bar as a thin line, the
    /// capsule's round end kept.
    private var wabiSabi: some View {
        let w = size.width, h = size.height
        let patina = reading.isOutdated ? 0.7 : 1
        return ZStack(alignment: .topLeading) {
            AUVLookPalette.surface(.wabiSabi, isDark: isDark)
            if showsLevel {
                Group {
                    Rectangle()
                        .fill(AUVLookPalette.dye(live(reading.primaryTier, reading.primary?.remainingPercent),
                                                 isDark: isDark).opacity(isDark ? 0.40 : 0.36))
                        .frame(width: w * lead, height: h - 4)
                    Rectangle()
                        .fill(AUVLookPalette.dye(live(reading.barTier, reading.secondary?.remainingPercent),
                                                 isDark: isDark).opacity(isDark ? 0.62 : 0.56))
                        .frame(width: w * bar, height: 3)
                        .offset(y: h - 3)
                }
                .opacity(patina)
            }
            content()
                .frame(width: w, height: h - 3)
                .opacity(max(0.85, patina))
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .compositingGroup()
        .clipShape(UsageGaugeShape(leftRadius: h / 2, rightRadius: 7))
    }

    /// Brutalist: the figure stands on clean concrete. Under it, inside the
    /// 2 pt rule, the lead level is a 4 pt bar in its system colour (hollow
    /// when not current) and the 7D level a 2 pt ink line.
    private var brutalist: some View {
        let w = size.width, h = size.height
        let ink = AUVLookPalette.ink(.brutalist, isDark: isDark)
        let rule = AUVFormwork.rule
        let inner = w - rule * 2
        let tier = live(reading.primaryTier, reading.primary?.remainingPercent)
        let tierColor = AUVLookPalette.system(tier, isDark: isDark)
        let form = RoundedRectangle(cornerRadius: AUVFormwork.control, style: .continuous)
        return ZStack(alignment: .topLeading) {
            AUVLookPalette.surface(.brutalist, isDark: isDark)
            content()
                .frame(width: w, height: h - 6)
            if showsLevel {
                Group {
                    if reading.isOutdated {
                        Rectangle().strokeBorder(tierColor, lineWidth: 1)
                            .frame(width: max(2, inner * lead), height: 4)
                    } else {
                        Rectangle().fill(tierColor)
                            .frame(width: inner * lead, height: 4)
                    }
                }
                .offset(x: rule, y: h - rule - 6)
                // The 7D line only when 5H leads; where 7D leads, the
                // level above is already 7D and a full line would read 100%.
                if reading.lead == .fiveHour {
                    Rectangle().fill(ink.opacity(0.7))
                        .frame(width: inner * bar, height: 2)
                        .offset(x: rule, y: h - rule - 2)
                }
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .compositingGroup()
        .clipShape(form)
        .overlay(form.strokeBorder(ink, lineWidth: rule))
    }
}
