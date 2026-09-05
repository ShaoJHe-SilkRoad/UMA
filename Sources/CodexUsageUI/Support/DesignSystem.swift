import AppKit
import SwiftUI

public struct UsagePanelAppearanceOverride: Equatable, Sendable {
    public let reduceTransparency: Bool
    public let increaseContrast: Bool
    public let reduceMotion: Bool

    public init(
        reduceTransparency: Bool,
        increaseContrast: Bool,
        reduceMotion: Bool
    ) {
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.reduceMotion = reduceMotion
    }
}

public struct UsagePanelCardVisibility: Equatable, Sendable {
    public let showUsageSummary: Bool
    public let showRecentTasks: Bool
    public let showAPICost: Bool

    public init(
        showUsageSummary: Bool,
        showRecentTasks: Bool,
        showAPICost: Bool
    ) {
        self.showUsageSummary = showUsageSummary
        self.showRecentTasks = showRecentTasks
        self.showAPICost = showAPICost
    }
}

public enum UsagePanelMetrics {
    public static let width: CGFloat = 370
    public static let height: CGFloat = 776
    public static let minimumHeight: CGFloat = 125
    public static let settingsMinimumHeight: CGFloat = 430
    public static let outerHorizontalInset: CGFloat = 16
    public static let outerTopInset: CGFloat = 12
    public static let outerBottomInset: CGFloat = 12
    public static let cardSpacing: CGFloat = 8
    public static let providerToolbarHeight: CGFloat = 22
    public static let collapsedProviderCardHeight: CGFloat = 74
    public static let headerHeight: CGFloat = 64

    public static var collapsedProviderContribution: CGFloat {
        collapsedProviderCardHeight + cardSpacing
    }

    public static func resolvedContentHeight(_ measuredHeight: CGFloat?) -> CGFloat {
        let measuredHeight = measuredHeight.map(ceil) ?? minimumHeight
        return min(height, max(minimumHeight, measuredHeight))
    }

    public static func preferredHeight(
        showUsageSummary: Bool,
        showRecentTasks: Bool,
        showAPICost: Bool
    ) -> CGFloat {
        var result = minimumHeight
        if showUsageSummary {
            result += 271
        }
        if showRecentTasks {
            result += 223
        }
        if showAPICost {
            result += 147
        }
        return result
    }
}

enum UsageSettingsSizing {
    static let cardHorizontalPadding: CGFloat = 14
    static let cardVerticalPadding: CGFloat = 14
    static let panelTopOffset: CGFloat = UsagePanelMetrics.headerHeight + 12
    static let panelBottomInset: CGFloat = 16
    static let minimumViewportHeight: CGFloat = 120

    static func cardHeight(
        contentHeight: CGFloat?,
        maximumHeight: CGFloat
    ) -> CGFloat {
        let availableViewport = max(
            0,
            maximumHeight - (cardVerticalPadding * 2)
        )
        let naturalViewport = max(
            minimumViewportHeight,
            contentHeight ?? availableViewport
        )
        return min(maximumHeight, naturalViewport + (cardVerticalPadding * 2))
    }

    static func panelHeight(cardHeight: CGFloat) -> CGFloat {
        UsagePanelMetrics.resolvedContentHeight(
            panelTopOffset + cardHeight + panelBottomInset
        )
    }
}

enum AppTypographyFamily: Equatable {
    case serif
    case system
    case monospaced
}

enum AppTypographyRole {
    case display
    case sectionTitle
    case cardTitle
    case body
    case secondary
    case caption
    case action
    case largeValue
    case regularValue
    case compactValue
    case menuBarValue
    case technicalMono
    case assistantProvider
    case assistantPlan
    case assistantDetail
    case assistantAccountDetail
    case assistantValue

    var size: CGFloat {
        switch self {
        case .display: 25
        case .sectionTitle: 15
        case .cardTitle: 13
        case .body: 11
        case .secondary: 10.5
        case .caption: 9
        case .action: 10.5
        case .largeValue: 21
        case .regularValue: 13
        case .compactValue: 13
        case .menuBarValue: 13
        case .technicalMono: 10
        case .assistantProvider: 12
        case .assistantPlan: 8.5
        case .assistantDetail: 9
        case .assistantAccountDetail: 8.2
        case .assistantValue: 13
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display: .bold
        case .sectionTitle: .bold
        case .cardTitle: .semibold
        case .body: .regular
        case .secondary: .regular
        case .caption: .regular
        case .action: .medium
        case .largeValue: .bold
        case .regularValue: .medium
        case .compactValue: .medium
        case .menuBarValue: .semibold
        case .technicalMono: .regular
        case .assistantProvider: .semibold
        case .assistantPlan: .medium
        case .assistantDetail, .assistantAccountDetail: .medium
        case .assistantValue: .medium
        }
    }

    var usesMonospacedDesign: Bool {
        self == .technicalMono
    }

    var family: AppTypographyFamily {
        if usesMonospacedDesign {
            return .monospaced
        }
        if usesTabularDigits {
            return .system
        }
        return .serif
    }

    var usesTabularDigits: Bool {
        switch self {
        case .largeValue, .regularValue, .compactValue, .menuBarValue, .assistantValue:
            true
        default:
            false
        }
    }
}

/// Package-safe serif-led application typography. Anthropic Serif is not
/// system-registered and UMA has no redistribution authority for private app
/// assets, so public macOS system-serif design resolution supplies the visual
/// identity and native CJK cascade. Exact values stay in system tabular sans;
/// SF Mono remains restricted to technical content.
public enum AppTypography {
    /// PreviewRendererTool uses this to exercise large-text layout without
    /// mutating the user's system accessibility preferences. Production UMA
    /// cannot activate the override.
    nonisolated(unsafe) private static var previewPointSizeScale: CGFloat = 1

    /// Shared by measured native layouts and the existing preview typography.
    static var currentPointSizeScale: CGFloat { previewPointSizeScale }

    public static func configurePreviewPointSizeScale(_ scale: CGFloat) {
        let processName = ProcessInfo.processInfo.processName
        guard processName == "PreviewRendererTool"
                || processName == "UMA-G2-Review"
        else {
            return
        }
        previewPointSizeScale = min(1.5, max(1, scale))
    }

    static func font(
        _ role: AppTypographyRole,
        language: AppLanguage = .english
    ) -> Font {
        let font = switch role.family {
        case .serif:
            font(role.size, weight: role.weight, language: language)
        case .system:
            systemFont(role.size, weight: role.weight)
        case .monospaced:
            technicalFont(role.size, weight: role.weight)
        }
        return role.usesTabularDigits ? font.monospacedDigit() : font
    }

    static func font(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        language _: AppLanguage = .simplifiedChinese,
        design: Font.Design = .serif
    ) -> Font {
        .system(
            size: size * previewPointSizeScale,
            weight: weight,
            design: design
        )
    }

    static func systemFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        .system(
            size: size * previewPointSizeScale,
            weight: weight,
            design: .default
        )
    }

    static func numericFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        systemFont(size, weight: weight).monospacedDigit()
    }

    static func technicalFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        .system(
            size: size * previewPointSizeScale,
            weight: weight,
            design: .monospaced
        )
    }

    static func nsFont(_ role: AppTypographyRole) -> NSFont {
        if role.usesMonospacedDesign {
            return .monospacedSystemFont(
                ofSize: role.size,
                weight: nsFontWeight(role.weight)
            )
        }
        if role.usesTabularDigits {
            return .monospacedDigitSystemFont(
                ofSize: role.size,
                weight: nsFontWeight(role.weight)
            )
        }
        let systemFont = NSFont.systemFont(
            ofSize: role.size,
            weight: nsFontWeight(role.weight)
        )
        guard role.family == .serif,
              let descriptor = systemFont.fontDescriptor.withDesign(.serif),
              let serifFont = NSFont(descriptor: descriptor, size: role.size) else {
            return systemFont
        }
        return serifFont
    }

    public static func menuBarNSFont() -> NSFont {
        nsFont(.menuBarValue)
    }

    private static func nsFontWeight(_ weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

enum UsageDesign {
    static let blue = Color(red: 0.0, green: 0.43, blue: 0.94)
    static let green = Color(red: 0.05, green: 0.72, blue: 0.34)
}

enum UsagePanelOuterContourOwner: Sendable {
    case swiftUI
    case nativeHost
}

private struct UsagePanelOuterContourOwnerKey: EnvironmentKey {
    static let defaultValue = UsagePanelOuterContourOwner.swiftUI
}

private struct UsagePanelAppearanceOverrideKey: EnvironmentKey {
    static let defaultValue: UsagePanelAppearanceOverride? = nil
}

extension EnvironmentValues {
    var usagePanelOuterContourOwner: UsagePanelOuterContourOwner {
        get { self[UsagePanelOuterContourOwnerKey.self] }
        set { self[UsagePanelOuterContourOwnerKey.self] = newValue }
    }

    var usagePanelAppearanceOverride: UsagePanelAppearanceOverride? {
        get { self[UsagePanelAppearanceOverrideKey.self] }
        set { self[UsagePanelAppearanceOverrideKey.self] = newValue }
    }
}

public extension View {
    func usagePanelOuterContourOwnedByNativeHost() -> some View {
        environment(\.usagePanelOuterContourOwner, .nativeHost)
    }
}

enum AppGlass {
    static let cardCornerRadius: CGFloat = 20
    static let panelCornerRadius: CGFloat = 28
    static let settingsReadabilityFillOpacity: Double = 0.24
    static let cardShadowOpacity: Double = 0.035
    static let cardShadowRadius: CGFloat = 3
    static let cardShadowY: CGFloat = 1
}

enum UsageQuotaVisualMetrics {
    static let primaryTitleSize: CGFloat = 16
    static let secondaryTitleSize: CGFloat = 10.5
    static let primaryValueSize: CGFloat = 20
    static let secondaryValueSize: CGFloat = 11
    static let primaryBarHeight: CGFloat = 10
    static let secondaryBarHeight: CGFloat = 2.5
    static let primaryVerticalInset: CGFloat = 13
    static let secondaryVerticalInset: CGFloat = 8
}

enum AppBorders {
    static func cardLineWidth(increaseContrast: Bool) -> CGFloat {
        increaseContrast ? 1.25 : 0.7
    }

    static func panelLineWidth(increaseContrast: Bool) -> CGFloat {
        increaseContrast ? 1.4 : 0.8
    }

    static func assistantLineWidth(increaseContrast: Bool) -> CGFloat {
        increaseContrast ? 1 : 0.75
    }

    static func cardStroke(
        colorScheme: ColorScheme,
        tuning: GlassTuning,
        increaseContrast: Bool
    ) -> LinearGradient {
        let contrastMultiplier = increaseContrast ? 1.65 : 1
        return LinearGradient(
            colors: [
                Color.white.opacity(
                    min(
                        0.72,
                        (colorScheme == .dark ? 0.18 : 0.32)
                            * tuning.cardBorderPercent / 100
                            * contrastMultiplier
                    )
                ),
                Color.white.opacity(
                    min(
                        0.32,
                        0.05 * tuning.cardBorderPercent / 100 * contrastMultiplier
                    )
                ),
                Color.black.opacity(
                    min(
                        0.52,
                        (colorScheme == .dark ? 0.16 : 0.07)
                            * tuning.cardBorderPercent / 100
                            * contrastMultiplier
                    )
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func panelStroke(
        colorScheme: ColorScheme,
        increaseContrast: Bool
    ) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(increaseContrast ? 0.64 : 0.38),
                Color.white.opacity(increaseContrast ? 0.18 : 0.08),
                Color.black.opacity(
                    increaseContrast
                        ? (colorScheme == .dark ? 0.52 : 0.34)
                        : 0.12
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct GlassCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.usagePanelAppearanceOverride) private var inheritedAppearanceOverride
    let tuning: GlassTuning
    var appearanceOverride: UsagePanelAppearanceOverride? = nil
    var cornerRadius: CGFloat = AppGlass.cardCornerRadius
    var readabilityFillOpacity: Double = 0

    private var usesReducedTransparency: Bool {
        appearanceOverride?.reduceTransparency
            ?? inheritedAppearanceOverride?.reduceTransparency
            ?? reduceTransparency
    }

    private var usesIncreasedContrast: Bool {
        appearanceOverride?.increaseContrast
            ?? inheritedAppearanceOverride?.increaseContrast
            ?? (colorSchemeContrast == .increased)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                usesReducedTransparency
                    ? AnyShapeStyle(
                        colorScheme == .dark
                            ? Color(nsColor: .windowBackgroundColor)
                            : Color(nsColor: .controlBackgroundColor)
                    )
                    : AnyShapeStyle(.thinMaterial)
            )
            .opacity(usesReducedTransparency ? 1 : tuning.cardMaterialPercent / 100)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        usesReducedTransparency
                            ? Color.clear
                            : Color(nsColor: .controlBackgroundColor)
                                .opacity(readabilityFillOpacity)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        usesReducedTransparency
                            ? Color.clear
                            : Color.white.opacity(
                                tuning.cardWhiteLayerPercent / 100
                                    * (colorScheme == .dark ? 0.43 : 1)
                            )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        AppBorders.cardStroke(
                            colorScheme: colorScheme,
                            tuning: tuning,
                            increaseContrast: usesIncreasedContrast
                        ),
                        lineWidth: AppBorders.cardLineWidth(
                            increaseContrast: usesIncreasedContrast
                        )
                    )
            }
            .shadow(
                color: Color.black.opacity(
                    usesReducedTransparency
                        ? 0.03
                        : (usesIncreasedContrast ? 0.08 : AppGlass.cardShadowOpacity)
                ),
                radius: usesReducedTransparency
                    ? 1
                    : (usesIncreasedContrast ? 4 : AppGlass.cardShadowRadius),
                y: AppGlass.cardShadowY
            )
    }
}

struct BalancedPanelTint: View {
    @Environment(\.colorScheme) private var colorScheme
    let tuning: GlassTuning

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .opacity(
                    tuning.panelTintPercent / 100 * (colorScheme == .dark ? 1.5 : 1)
                )
            LinearGradient(
                colors: [
                    UsageDesign.blue.opacity(0.03 * tuning.panelGradientPercent / 100),
                    Color.clear,
                    Color.black.opacity(
                        (colorScheme == .dark ? 0.07 : 0.04)
                            * tuning.panelGradientPercent / 100
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
