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
    public static let minimumHeight: CGFloat = 135
    public static let settingsMinimumHeight: CGFloat = 430
    public static let outerHorizontalInset: CGFloat = 16
    public static let outerTopInset: CGFloat = 14
    public static let outerBottomInset: CGFloat = 12
    public static let cardSpacing: CGFloat = 12
    public static let collapsedProviderCardHeight: CGFloat = 82

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

    var usesTabularDigits: Bool {
        switch self {
        case .largeValue, .regularValue, .compactValue, .menuBarValue, .assistantValue:
            true
        default:
            false
        }
    }
}

/// Package-safe application typography. Claude Desktop's bundled Anthropic
/// fonts are not system-installed and do not carry redistribution authority,
/// so UMA uses the native macOS UI families: SF Pro with the system CJK
/// cascade (including PingFang SC) and SF Mono only for technical content.
public enum AppTypography {
    static func font(
        _ role: AppTypographyRole,
        language: AppLanguage = .english
    ) -> Font {
        font(
            role.size,
            weight: role.weight,
            language: language,
            design: role.usesMonospacedDesign ? .monospaced : .default
        )
    }

    static func font(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        language _: AppLanguage = .simplifiedChinese,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size, weight: weight, design: design)
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
        return .systemFont(
            ofSize: role.size,
            weight: nsFontWeight(role.weight)
        )
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
                    : AnyShapeStyle(.ultraThinMaterial)
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
                    .stroke(
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
                    usesReducedTransparency ? 0.04 : (usesIncreasedContrast ? 0.10 : 0.07)
                ),
                radius: usesReducedTransparency ? 2 : 5,
                y: usesReducedTransparency ? 1 : 2
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
