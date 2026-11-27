import AppKit
import Combine
import SwiftUI

enum RemainingUsageVisualPolicy {
    static func visibleFraction(for percent: Double, width: CGFloat) -> Double {
        let fraction = min(1, max(0, percent / 100))
        return max(fraction, min(1, 2 / max(1, width)))
    }
}

// Compact rows own their clipping; this is only an internal, full-height fill.
// Keep legacy preference names stable while restoring their usage visualization.
enum CompactUsageFillPolicy {
    static func fraction(for percent: Double?) -> Double? {
        guard let percent, percent.isFinite, (0...100).contains(percent) else { return nil }
        return percent / 100
    }
}

struct CompactUsageFill: View {
    @Environment(\.colorScheme) private var colorScheme
    let remainingPercent: Double?
    let reduceTransparency: Bool
    let increaseContrast: Bool
    var providerID: String = "unknown"
    var admittedPlan: String? = nil
    /// A reading that is no longer current is drawn grey, whatever its level.
    var isOutdated = false

    var body: some View {
        if let fraction = CompactUsageFillPolicy.fraction(for: remainingPercent) {
            GeometryReader { proxy in
                (isOutdated ? Color.secondary : LowRemainingUsagePolicy.color(
                    for: LowRemainingUsagePolicy.assessment(
                        providerID: providerID, admittedPlan: admittedPlan,
                        remainingPercent: remainingPercent
                    )
                ))
                    .opacity(DesktopAssistantTintOpacity.value(
                        isDark: colorScheme == .dark,
                        reduceTransparency: reduceTransparency,
                        increaseContrast: increaseContrast
                    ))
                    .frame(width: proxy.size.width * fraction, height: proxy.size.height)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}

/// The main window's agent rail: the row itself is the gauge, as before, and
/// the fill now reads as a level. Its body deepens toward the level, and a
/// crisp edge marks exactly where the remaining share ends. The Desktop
/// Assistant keeps `CompactUsageFill` unchanged.
struct AgentRailLevelFill: View {
    @Environment(\.colorScheme) private var colorScheme
    let remainingPercent: Double?
    let reduceTransparency: Bool
    let increaseContrast: Bool
    var providerID: String = "unknown"
    var admittedPlan: String? = nil

    var body: some View {
        if let fraction = CompactUsageFillPolicy.fraction(for: remainingPercent) {
            GeometryReader { proxy in
                let tint = LowRemainingUsagePolicy.color(for: LowRemainingUsagePolicy.assessment(
                    providerID: providerID, admittedPlan: admittedPlan, remainingPercent: remainingPercent
                ))
                let strength = DesktopAssistantTintOpacity.value(
                    isDark: colorScheme == .dark,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast
                )
                let width = proxy.size.width * fraction
                ZStack(alignment: .trailing) {
                    switch AUVLook.current {
                    case .standard:
                        LinearGradient(
                            colors: [tint.opacity(strength * 0.62), tint.opacity(strength * 1.12)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    // A flat dye; flat concrete. No gradient in either pack.
                    case .wabiSabi: tint.opacity(strength * 1.1)
                    case .brutalist: tint.opacity(strength * 0.7)
                    }
                    // The level edge: a tick at the top and bottom, fading out
                    // through the middle so it never cuts through the name or
                    // the value. At 0% and 100% it would sit on the row's own
                    // border, where it only reads as a stray line.
                    if AUVLook.current == .brutalist, fraction > 0.01, fraction < 0.99 {
                        // The level's end as a solid block.
                        Rectangle().fill(tint.opacity(0.9)).frame(width: 4)
                    } else if AUVLook.current == .standard, fraction > 0.01, fraction < 0.99 {
                        let edge = tint.opacity(min(1, strength * 3.2))
                        Rectangle()
                            .fill(LinearGradient(stops: [
                                .init(color: edge, location: 0),
                                .init(color: edge, location: 0.2),
                                .init(color: edge.opacity(0), location: 0.36),
                                .init(color: edge.opacity(0), location: 0.64),
                                .init(color: edge, location: 0.8),
                                .init(color: edge, location: 1)
                            ], startPoint: .top, endPoint: .bottom))
                            .frame(width: 2)
                    }
                }
                .frame(width: width, height: proxy.size.height)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}

/// The same truthful remaining-use visual for the selected agent and other
/// providers. A missing limit has a visible outline, never a fabricated fill.
private struct AgentRemainingQuotaBar: View {
    let remainingPercent: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.primary.opacity(0.09))
                .overlay(alignment: .leading) {
                    // One flat colour, as the usage gauge is.
                    if let fraction = CompactUsageFillPolicy.fraction(for: remainingPercent) {
                        Capsule()
                            .fill(tint.opacity(0.85))
                            .frame(width: geometry.size.width * fraction)
                    }
                }
                .overlay {
                    if remainingPercent == nil {
                        Capsule().strokeBorder(.secondary.opacity(0.55),
                                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

enum AgentGlanceStatus: Equatable, Sendable {
    case connected
    case reconnecting
    case stale
    case cached
    case needsAttention
    case authenticationRequired
    case disconnected
    case unavailable
    case error
}

enum AgentGlancePresentationPolicy {
    static func status(for provider: ProviderProductState) -> AgentGlanceStatus {
        if provider.health == .error || provider.connection == .failed {
            return .error
        }
        if provider.health == .needsAttention {
            return .needsAttention
        }
        if provider.freshness == .stale {
            return .stale
        }
        if provider.freshness == .cached {
            return .cached
        }
        return switch provider.connection {
        case .connected: .connected
        case .transitional: .reconnecting
        case .authenticationRequired: .authenticationRequired
        case .disconnected: .disconnected
        case .unavailable: .unavailable
        case .failed: .error
        }
    }
}

public enum AgentGlanceRowStyle: Sendable {
    case quickPanel
    case mainList
}

enum AgentWorkspaceLayoutPolicy {
    static let horizontalPadding: CGFloat = 24
    static var moduleSpacing: CGFloat { AUVShape.cardSpacing }
    static let minimumTwoColumnWidth: CGFloat = 660

    static func columnCount(for availableWidth: CGFloat) -> Int {
        availableWidth >= minimumTwoColumnWidth ? 2 : 1
    }
}

private struct AgentWorkspaceModuleSurface: ViewModifier {
    func body(content: Content) -> some View {
        // The usage card's own surface, so the agent page has only one.
        // Wabi-sabi has no box, so nothing to pad inside: modules line up
        // with the usage card and stand apart by space alone.
        content
            .padding(AUVLook.current == .wabiSabi ? 0 : 14)
            .usageGaugeSurface()
    }
}

private extension View {
    func moduleSurface() -> some View {
        modifier(AgentWorkspaceModuleSurface())
    }
}

/// A layout-only native anchor for bounded source-hosted geometry checks.
/// It renders no content and does not replace the actual SwiftUI control.
final class AgentWorkspaceDailyPlotBoundsView: NSView {}

private struct AgentWorkspaceGeometryAnchor: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let view: NSView = identifier == "uma015.codex.plot-bounds"
            ? AgentWorkspaceDailyPlotBoundsView(frame: .zero) : NSView(frame: .zero)
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.setAccessibilityIdentifier(identifier)
    }
}

public struct AgentGlanceRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let provider: ProviderProductState
    public let style: AgentGlanceRowStyle
    public let selected: Bool
    public let language: AppLanguage
    public let showsReset: Bool
    public let showsConnectivity: Bool
    public let showsRemainingRail: Bool
    private let referenceDate: Date?
    private let displayNameOverride: String?

    public init(
        provider: ProviderProductState,
        style: AgentGlanceRowStyle,
        selected: Bool = false,
        language: AppLanguage = .english,
        showsReset: Bool = true,
        showsConnectivity: Bool = true,
        showsRemainingRail: Bool = true,
        referenceDate: Date? = nil,
        displayNameOverride: String? = nil
    ) {
        self.provider = provider
        self.style = style
        self.selected = selected
        self.language = language
        self.showsReset = showsReset
        self.showsConnectivity = showsConnectivity
        self.showsRemainingRail = showsRemainingRail
        self.referenceDate = referenceDate
        self.displayNameOverride = displayNameOverride
    }

    public var body: some View {
        if style == .mainList {
            navigationRow
        } else if showsRemainingRail, let gauge = gaugeReading {
            gaugeRow(gauge)
        } else {
            legacyRow
        }
    }

    /// The main window's list only navigates: the agent page shows all of
    /// its usage. Icon in the connection colour, the name, and a status word
    /// only when something is wrong.
    private var navigationRow: some View {
        let look = AUVLook.current
        let isDark = colorScheme == .dark
        let ink = AUVLookPalette.ink(look, isDark: isDark)
        // Brutalist inverts the chosen row: ink ground, concrete text.
        let inverted = look == .brutalist && selected
        let textColor: Color = switch look {
        case .standard: Color.primary
        case .wabiSabi: ink.opacity(selected ? 0.92 : 0.6)
        case .brutalist: inverted ? (AUVLookPalette.canvas(.brutalist, isDark: isDark) ?? .white) : ink
        }
        return HStack(spacing: 8) {
            if look == .wabiSabi {
                // A short ink mark beside the chosen one, nothing more.
                Capsule().fill(ink.opacity(selected ? 0.7 : 0)).frame(width: 2, height: 14)
            }
            DesktopAgentLogo(providerID: provider.id.rawValue,
                             tint: inverted ? textColor : gaugeLogoColor, diameter: 18)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(displayName)
                .font(look == .standard
                      ? .system(size: 13, weight: selected ? .semibold : .regular)
                      : AUVLookType.text(13, strong: look == .brutalist && selected))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if AgentGlancePresentationPolicy.status(for: provider) != .connected {
                Text(statusLabel)
                    .font(AUVLookType.text(11))
                    .foregroundStyle(textColor.opacity(look == .brutalist ? 0.85 : 0.45))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, look == .wabiSabi ? 4 : 8)
        .frame(height: 32)
        .background {
            switch look {
            case .standard:
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isDark ? 0.12 : 0.09))
                }
            case .wabiSabi:
                EmptyView()
            case .brutalist:
                // The chosen row is cast solid; rows stand apart by a gutter.
                RoundedRectangle(cornerRadius: AUVFormwork.control, style: .continuous)
                    .fill(selected ? ink : Color.clear)
            }
        }
        .contentShape(Rectangle())
        .help(displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The unified usage gauge, for agents with a remaining share to show.
    /// Rows without a reading keep their text, which says what is wrong.
    private var gaugeReading: UsageGaugeReading? {
        guard let reading = UsageGaugeReading.from(provider: provider),
              reading.lead != .unavailable else { return nil }
        return reading
    }

    private var gaugeHeight: CGFloat { 72 }

    private func gaugeRow(_ gauge: UsageGaugeReading) -> some View {
        GeometryReader { proxy in
            UsageGaugeCard(
                reading: gauge,
                providerID: provider.id.rawValue,
                size: CGSize(width: proxy.size.width, height: gaugeHeight),
                title: [displayName, provider.planLabel].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                primaryResetText: UsageGaugeText.primaryReset(gauge, language: language),
                secondaryText: UsageGaugeText.secondary(gauge, language: language),
                statusColor: showsConnectivity ? gaugeLogoColor : nil
            )
        }
        .frame(height: gaugeHeight)
        .overlay {
            if selected {
                let radius = UsageGaugeCardGeometry(size: CGSize(width: 300, height: gaugeHeight)).cornerRadius
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AUVLook.current.isStandard
                                  ? Color(nsColor: .controlAccentColor)
                                  : AUVLookPalette.accent(isDark: colorScheme == .dark), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .help(displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var legacyRow: some View {
        standardContent
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background { rowBackground }
        .clipShape(RoundedRectangle(cornerRadius: rowRadius, style: .continuous))
        .overlay {
            // The remaining-use fill tints the whole row once usage is high,
            // which a 7.5% selection tint cannot show through. An outline in
            // the accent colour marks the selected row at any fill.
            if selected {
                RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .controlAccentColor), lineWidth: 2)
                    .allowsHitTesting(false)
            } else if style == .mainList {
                RoundedRectangle(cornerRadius: rowRadius, style: .continuous)
                    .strokeBorder(UMAVisualStyle.separator.opacity(0.45), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .help(displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: verticalContentSpacing) {
            HStack(alignment: style == .mainList ? .center : .top, spacing: 9) {
                if showsConnectivity { providerMark }
                VStack(alignment: .leading, spacing: style == .mainList ? 2 : 1) {
                    Text(displayName)
                        .font(AUVType.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(secondaryLine)
                        .font(.system(size: secondaryFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let resetLine {
                        Text(resetLine)
                            .font(.system(size: secondaryFontSize - 1))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !usesFullWidthName {
                    Text(primaryDisplayText)
                        .font(valueFont)
                        .monospacedDigit()
                        .foregroundStyle(valueColor)
                }
            }
            if usesFullWidthName {
                Text(primaryDisplayText)
                    .font(valueFont)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
        }
    }

    // Keep the complete canonical label visible in the narrow rail; long
    // names get the full text width while the remaining value stays visible.
    private var usesFullWidthName: Bool { displayName.count > 32 }

    private var horizontalPadding: CGFloat { 10 }
    private var verticalContentSpacing: CGFloat { 7 }
    private var secondaryFontSize: CGFloat { style == .quickPanel ? 12 : 11 }
    private var verticalPadding: CGFloat { style == .quickPanel ? 8 : 10 }
    private var rowRadius: CGFloat { style == .quickPanel ? 9 : AUVShape.rowRadius }
    private var valueFont: Font {
        style == .quickPanel
            ? .system(size: 16, weight: .semibold, design: .rounded)
            : AUVType.railValue
    }

    private var secondaryLine: String {
        // In the rail the status dot already says "connected"; the word is
        // kept for every other state, where it is news.
        var components: [String] = style == .mainList
            && AgentGlancePresentationPolicy.status(for: provider) == .connected
            ? [] : [statusLabel]
        if let plan = provider.planLabel, !plan.isEmpty {
            components.append(plan)
        }
        if let quota = provider.primaryQuota {
            components.append(quota.compactLabel)
        } else {
            components.append(localized("No quota reading", "无额度读数"))
        }
        return components.joined(separator: " · ")
    }

    private var statusLabel: String {
        return switch AgentGlancePresentationPolicy.status(for: provider) {
        case .connected: localized("Connected", "已连接")
        case .reconnecting: localized("Reconnecting", "正在重新连接")
        case .stale: localized("Stale", "数据已过期")
        case .cached: localized("Cached", "缓存数据")
        case .needsAttention: localized("Needs attention", "需要处理")
        case .authenticationRequired:
            provider.id == .claude
                ? localized("Setup required", "需要设置")
                : localized("Sign in required", "需要登录")
        case .disconnected: localized("Disconnected", "已断开")
        case .unavailable: localized("Unavailable", "不可用")
        case .error: localized("Error", "错误")
        }
    }

    private var statusColor: Color {
        return switch AgentGlancePresentationPolicy.status(for: provider) {
        case .connected: AgentConnectionIndicatorPalette.connected(
            isDark: colorScheme == .dark, increasedLightContrast: style == .quickPanel
        )
        case .reconnecting, .stale, .cached, .needsAttention,
             .authenticationRequired: .orange
        case .disconnected, .unavailable: .secondary
        case .error: .red
        }
    }

    /// The gauge logo carries the connection state itself, on a tinted
    /// column, so "connected" uses the deeper green in light mode everywhere.
    private var gaugeLogoColor: Color {
        if AgentGlancePresentationPolicy.status(for: provider) == .connected {
            return AgentConnectionIndicatorPalette.connected(isDark: colorScheme == .dark,
                                                             increasedLightContrast: true)
        }
        return statusColor
    }

    private var valueColor: Color {
        provider.health == .error ? .red : .primary
    }

    /// The single gate for showing a reset time. The row body and the
    /// accessibility label both read this, so a reset that is hidden on screen
    /// can never still be announced to VoiceOver, and one that is shown is
    /// never silently dropped from the label.
    static func resetLine(
        quota: ProviderProductQuotaState?,
        showsReset: Bool,
        language: AppLanguage,
        now: Date
    ) -> String? {
        guard showsReset, let resetsAt = quota?.resetsAt else { return nil }
        return language.resetDescription(for: resetsAt, now: now)
    }

    private var displayNow: Date { referenceDate ?? Date() }

    private var resetLine: String? {
        Self.resetLine(
            quota: provider.primaryQuota,
            showsReset: showsReset,
            language: language,
            now: displayNow
        )
    }

    private var accessibilityLabel: String {
        let quota = provider.primaryQuota.map {
            "\($0.compactLabel), \($0.displayText) \(localized("remaining", "剩余"))"
        }
            ?? localized("usage unavailable", "用量不可用")
        var label = "\(displayName), \(statusLabel), \(quota)"
        if let resetLine { label += ", \(resetLine)" }
        return label
    }

    private var displayName: String {
        displayNameOverride ?? provider.displayName
    }

    private var primaryDisplayText: String {
        provider.primaryDisplayText
    }

    private var remainingPercent: Double? {
        provider.primaryQuota?.value.remainingPercent
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }

    private var providerMark: some View {
        DesktopAgentLogo(providerID: provider.id.rawValue, tint: statusColor,
                         diameter: style == .mainList ? 22 : 24)
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1)
                }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var rowBackground: some View {
        ZStack {
            (style == .mainList ? UMAVisualStyle.surface : Color(nsColor: .controlBackgroundColor))
                .opacity(
                    reduceTransparency
                        ? 0.94
                        : (style == .quickPanel ? 0.34 : 0.52)
                )
            if selected {
                Color(nsColor: .controlAccentColor).opacity(0.075)
            }
            if showsRemainingRail, style == .mainList {
                AgentRailLevelFill(
                    remainingPercent: remainingPercent,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: colorSchemeContrast == .increased,
                    providerID: provider.id.rawValue,
                    admittedPlan: provider.planLabel
                )
            } else if showsRemainingRail {
                CompactUsageFill(
                    remainingPercent: remainingPercent,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: colorSchemeContrast == .increased,
                    providerID: provider.id.rawValue,
                    admittedPlan: provider.planLabel
                )
            }
        }
    }

}

/// The panel's ground in an appearance pack: stone or concrete instead of
/// glass; Brutalist adds its 1 pt rule. Standard keeps the panel's glass.
private struct QuickPanelLookGround: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        if let canvas = AUVLookPalette.canvas(isDark: isDark) {
            canvas.overlay {
                if AUVLook.current == .brutalist {
                    // The panel's own corner is the formwork.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AUVLookPalette.ink(isDark: isDark), lineWidth: AUVFormwork.rule)
                }
            }
        }
    }
}

public struct QuickPanelSurface: View {
    @ObservedObject private var store: UsageStore
    @StateObject private var displayPreferences: QuickPanelDisplayPreferences
    private let openMain: () -> Void
    private let scanAll: () -> Void
    private let refreshAll: () -> Void
    private let toggleWizard: () -> Void
    private let openSettings: () -> Void
    private let selectAgent: (ProviderProductID) -> Void
    private let referenceDate: Date?

    public init(
        store: UsageStore,
        preferences: ApplicationPreferences,
        openMain: @escaping () -> Void,
        scanAll: @escaping () -> Void,
        refreshAll: @escaping () -> Void,
        toggleWizard: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        selectAgent: @escaping (ProviderProductID) -> Void,
        referenceDate: Date? = nil
    ) {
        self.store = store
        _displayPreferences = StateObject(
            wrappedValue: QuickPanelDisplayPreferences(preferences: preferences)
        )
        self.openMain = openMain
        self.scanAll = scanAll
        self.refreshAll = refreshAll
        self.toggleWizard = toggleWizard
        self.openSettings = openSettings
        self.selectAgent = selectAgent
        self.referenceDate = referenceDate
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if providers.isEmpty {
                VStack(spacing: 10) {
                    Text(localized("No active agents", "没有活跃的智能体"))
                        .font(.system(size: 13, weight: .medium))
                    Text(localized(
                        "Connect an agent in AUV or scan this Mac again.",
                        "请在 AUV 中连接智能体，或重新扫描这台 Mac。"
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Button(localized("Open AUV", "打开 AUV"), action: openMain)
                        Button(localized("Scan for Agents", "扫描智能体"), action: scanAll)
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            } else {
                VStack(spacing: AUVLook.current == .standard ? 2 : (AUVLook.current == .wabiSabi ? 10 : 8)) {
                    ForEach(providers) { provider in
                        Button {
                            selectAgent(provider.id)
                        } label: {
                            AgentGlanceRow(
                                provider: provider,
                                style: .quickPanel,
                                language: store.language,
                                showsReset: displayPreferences.showsReset,
                                showsConnectivity: displayPreferences.showsConnectivity,
                                showsRemainingRail: displayPreferences.showsRemainingRail,
                                referenceDate: referenceDate
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background { QuickPanelLookGround() }
        .environment(\.auvCardOnCanvas, true)
        .environment(\.locale, store.language.locale)
        .accessibilityIdentifier("uma.quick.surface")
        .auvLookRoot()
    }

    private var providers: [ProviderProductState] {
        store.orderedQuickPanelProviders
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: openMain) {
                Label("AUV", systemImage: "gauge.with.dots.needle.67percent")
                    .font(AUVLook.current == .brutalist
                          ? .system(size: 14, weight: .heavy)
                          : AUVLookType.text(13, strong: AUVLook.current == .standard))
            }
            .buttonStyle(.plain)
            .help(localized("Open AUV", "打开 AUV"))
            .accessibilityLabel(localized("Open AUV", "打开 AUV"))
            Spacer()
            headerButton(localized("Scan for Agents", "扫描智能体"), "magnifyingglass", scanAll)
            headerButton(localized("Refresh All", "全部刷新"), "arrow.clockwise", refreshAll)
                .disabled(!store.allowsManualRefresh)
            headerButton(localized("Desktop Assistant", "桌面助手"), "macwindow", toggleWizard)
            headerButton(localized("Global Settings", "全局设置"), "gearshape", openSettings)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    private func headerButton(
        _ label: String,
        _ symbol: String,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                // Thin in Wabi-sabi, bold in Brutalist, as the text is.
                .fontWeight(AUVLook.current == .wabiSabi ? .ultraLight
                            : (AUVLook.current == .brutalist ? .bold : nil))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        store.language == .simplifiedChinese ? chinese : english
    }
}

@MainActor
private final class QuickPanelDisplayPreferences: ObservableObject {
    @Published private(set) var showsReset: Bool
    @Published private(set) var showsConnectivity: Bool
    @Published private(set) var showsRemainingRail: Bool
    private let preferences: ApplicationPreferences
    private var observation: ApplicationPreferences.Observation?

    init(preferences: ApplicationPreferences) {
        self.preferences = preferences
        showsReset = preferences.value(for: UMAApplicationPreferenceKeys.quickPanelShowsReset)
        showsConnectivity = preferences.value(
            for: UMAApplicationPreferenceKeys.quickPanelShowsConnectivity
        )
        showsRemainingRail = preferences.value(
            for: UMAApplicationPreferenceKeys.quickPanelShowsRemainingRails
        )
        observation = preferences.observe { [weak self] change in
            guard let self else { return }
            switch change.key {
            case UMAApplicationPreferenceKeys.quickPanelShowsReset.name:
                showsReset = preferences.value(
                    for: UMAApplicationPreferenceKeys.quickPanelShowsReset
                )
            case UMAApplicationPreferenceKeys.quickPanelShowsConnectivity.name:
                showsConnectivity = preferences.value(
                    for: UMAApplicationPreferenceKeys.quickPanelShowsConnectivity
                )
            case UMAApplicationPreferenceKeys.quickPanelShowsRemainingRails.name:
                showsRemainingRail = preferences.value(
                    for: UMAApplicationPreferenceKeys.quickPanelShowsRemainingRails
                )
            default:
                break
            }
        }
    }
}

enum CodexDashboardMetricSourceState: Equatable {
    case current, stale, unavailable
}

enum CodexDashboardActivityState: Equatable {
    case current, empty, stale, unavailable
}

/// Copy and channel-validity rules used by the rendered Codex dashboard.
/// Keeping them beside the view lets isolated regressions verify the exact
/// labels and values that the production view displays.
enum CodexDashboardPresentation {
    static func localEstimateTitle(language: AppLanguage) -> String {
        language == .simplifiedChinese
            ? "按 API 价格估算 · 7 天"
            : "At API prices · 7D"
    }

    static func accountState(snapshot: UsageSnapshot, provider: ProviderProductState?) -> CodexDashboardMetricSourceState {
        guard let provider, provider.freshness != .unavailable,
              let source = snapshot.providerSource,
              source.isAvailable, source.freshness != .unavailable else { return .unavailable }
        guard provider.freshness == .fresh, source.freshness == .fresh else { return .stale }
        return .current
    }

    static func localEstimateState(snapshot: UsageSnapshot) -> CodexDashboardMetricSourceState {
        guard let source = snapshot.localSource, source.isAvailable,
              source.freshness != .unavailable else { return .unavailable }
        return source.freshness == .fresh ? .current : .stale
    }

    static func activityState(snapshot: UsageSnapshot) -> CodexDashboardActivityState {
        guard let source = snapshot.localSource, source.isAvailable,
              source.freshness != .unavailable else { return .unavailable }
        guard source.freshness == .fresh else { return .stale }
        return snapshot.recentTasks.isEmpty ? .empty : .current
    }

    static func metricValue(_ metric: CodexDashboardProjection.Metric?, state: CodexDashboardMetricSourceState) -> String {
        state == .current ? (metric?.value ?? "—") : "—"
    }

    static func historySourceLine(_ history: CodexDashboardProjection.HistoryAvailability, language: AppLanguage) -> String {
        let english: String
        let chinese: String
        switch history {
        case .accountDailyBuckets:
            english = "Local calendar days · tokens · source: account history"
            chinese = "本地日历日 · 令牌 · 来源：账户历史"
        case .aggregateOnly:
            english = "Local aggregate available · daily token history unavailable"
            chinese = "本地汇总数据可用 · 每日令牌历史不可用"
        case .staleWithoutDailyBuckets:
            english = "Retained local source is stale · daily token history unavailable"
            chinese = "保留的本地来源已过期 · 每日令牌历史不可用"
        case .unavailable:
            english = "Daily token history unavailable · no local aggregate admitted"
            chinese = "每日令牌历史不可用 · 未接纳本地汇总数据"
        }
        return language == .simplifiedChinese ? chinese : english
    }

    static func historyDetail(_ history: CodexDashboardProjection.HistoryAvailability, language: AppLanguage) -> String {
        let english: String
        let chinese: String
        switch history {
        case .accountDailyBuckets:
            english = "Provider-reported daily values are shown without AUV day reallocation."
            chinese = "按提供方报告显示每日数值，AUV 不重新分配日期。"
        case .aggregateOnly:
            english = "Known local aggregates are kept separate, not divided into invented daily usage."
            chinese = "已知本地汇总值保持独立，不拆分为虚构的每日用量。"
        case .staleWithoutDailyBuckets:
            english = "Retained local data is stale; no current daily values are shown."
            chinese = "保留的本地数据已过期；不显示当前每日数值。"
        case .unavailable:
            english = "No eligible account daily history or local aggregate was admitted."
            chinese = "未接纳合格的账户每日历史或本地汇总数据。"
        }
        return language == .simplifiedChinese ? chinese : english
    }

    static func historyFootnote(_ history: CodexDashboardProjection.HistoryAvailability, language: AppLanguage) -> String {
        let english: String
        let chinese: String
        switch history {
        case .accountDailyBuckets:
            english = "Period: local calendar days; provider timezone unavailable · Unit: tokens · missing days unknown; zero means provider-reported zero · no AUV day reallocation"
            chinese = "周期：本地日历日；提供方时区未知 · 单位：令牌 · 缺失日期未知；零表示提供方报告为零 · AUV 不重新分配日期"
        case .aggregateOnly:
            english = "Period: local aggregate snapshot · No daily token buckets; aggregates retain their own units"
            chinese = "周期：本地汇总快照 · 无每日令牌分桶；汇总值保留原单位"
        case .staleWithoutDailyBuckets:
            english = "Period: stale retained local observation · No current daily token buckets"
            chinese = "周期：已过期的保留本地观测 · 无当前每日令牌分桶"
        case .unavailable:
            english = "Period: unavailable · No daily token series or local aggregate admitted for this panel"
            chinese = "周期：不可用 · 此区域未接纳每日令牌序列或本地汇总数据"
        }
        return language == .simplifiedChinese ? chinese : english
    }
}

public struct AgentWorkspaceSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    /// The same key the agent settings sheet writes for the Claude cost toggle.
    /// Without reading it the module ignored a preference that exists to hide
    /// exactly this card.
    @AppStorage("display.showAPICostCard") private var showsAPICostCard = false
    @ObservedObject private var store: UsageStore
    public let providerID: ProviderProductID
    /// This agent's settings, shown in the page's last module: the one way
    /// to them from the main window.
    private let settingsContent: AnyView?
    private let connectCodex: () -> Void
    private let disconnectCodex: () -> Void
    private let claudeControlState: () -> ClaudeAgentControlState
    private let connectClaude: () -> Void
    /// Unused by the page since Refresh All took over Accuracy Sync; kept in
    /// the initializer so the window and its tests wire the same actions.
    private let claudeAccuracySync: () -> Void
    private let referenceDate: Date?
    @State private var showingClaudeConsent = false

    public init(
        store: UsageStore,
        providerID: ProviderProductID,
        settingsContent: AnyView? = nil,
        connectCodex: @escaping () -> Void,
        disconnectCodex: @escaping () -> Void,
        claudeControlState: @escaping () -> ClaudeAgentControlState,
        connectClaude: @escaping () -> Void,
        claudeAccuracySync: @escaping () -> Void,
        referenceDate: Date? = nil
    ) {
        self.store = store
        self.providerID = providerID
        self.settingsContent = settingsContent
        self.connectCodex = connectCodex
        self.disconnectCodex = disconnectCodex
        self.claudeControlState = claudeControlState
        self.connectClaude = connectClaude
        self.claudeAccuracySync = claudeAccuracySync
        self.referenceDate = referenceDate
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: AUVShape.cardSpacing) {
                    header
                    if providerID != .codex { claudeActionCallout }
                    // One way to show the remaining share on this page: the
                    // usage card. Without a reading, the module says why.
                    if let gauge = pageGauge {
                        pageGaugeCard(gauge, width: min(Self.maxContentWidth, geometry.size.width
                                      - AgentWorkspaceLayoutPolicy.horizontalPadding * 2
                                      - (AUVLook.current == .wabiSabi ? 76 : 0)))
                    } else {
                        usageModule
                    }
                    if providerID == .codex {
                        codexDashboard(for: geometry.size.width)
                    } else {
                        standardWorkspace(for: geometry.size.width)
                    }
                    settingsModule
                }
                // One column; on a very wide window it stops at 760 pt and
                // centres, so a value stays near its label. Wabi-sabi keeps
                // it to the left, with a wide quiet margin on the right.
                .frame(maxWidth: Self.maxContentWidth)
                .frame(maxWidth: .infinity, alignment: AUVLook.current == .wabiSabi ? .leading : .center)
                .padding(.horizontal, AgentWorkspaceLayoutPolicy.horizontalPadding)
                // Wabi-sabi: a deeper margin on both sides, widest on the right.
                .padding(.leading, AUVLook.current == .wabiSabi ? 20 : 0)
                .padding(.trailing, AUVLook.current == .wabiSabi ? 56 : 0)
                .padding(.vertical, AUVLook.current == .wabiSabi ? 30 : 18)
            }
        }
        .background(UMAVisualStyle.canvas)
        .environment(\.auvCardOnCanvas, true)
        .accessibilityIdentifier("uma.agent.workspace.\(providerID.rawValue)")
        .alert(
            localized("Enable Claude Local Smart?", "启用 Claude 本地智能？"),
            isPresented: $showingClaudeConsent
        ) {
            Button(localized("Cancel", "取消"), role: .cancel) {}
            Button(localized("Enable", "启用"), action: connectClaude)
        } message: {
            // This is the only place consent is asked, so it carries the
            // full disclosure rather than a summary of it.
            Text(store.language.claudeConsentDisclosure)
        }
    }

    private var provider: ProviderProductState? { store.productInventory.provider(providerID) }

    static let maxContentWidth: CGFloat = 760

    private var codexProjection: CodexDashboardProjection {
        CodexDashboardProjection(snapshot: store.snapshot, provider: provider)
    }

    /// One column: the connection, then the cost estimate below it when on.
    @ViewBuilder private func standardWorkspace(for width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AgentWorkspaceLayoutPolicy.moduleSpacing) {
            connectionModule
            if showsAPICostCard, localCostEstimate != nil { localCostModule }
        }
    }

    /// Below the usage card: account metrics, the dated trend, and the
    /// connection with recent local activity folded into it.
    private func codexDashboard(for width: CGFloat) -> some View {
        // Wabi-sabi has no boxes, so only space separates the modules: the
        // same breath as between every other module on the page.
        VStack(alignment: .leading,
               spacing: AUVLook.current == .wabiSabi ? AgentWorkspaceLayoutPolicy.moduleSpacing : 12) {
            metricRow(for: width)
            // The trend only when there are days to draw; otherwise the
            // connection module says so in one row.
            if hasDailyHistory { trendGapCard }
            connectionModule
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("uma.agent.codex.dashboard")
    }

    private var hasDailyHistory: Bool {
        if case .accountDailyBuckets = codexProjection.historyAvailability { return true }
        return false
    }

    private var dailyTrendRowValue: String {
        switch codexProjection.historyAvailability {
        case .accountDailyBuckets: return ""
        case .aggregateOnly: return localized("None yet; only totals are kept locally", "暂无，本地只有汇总值")
        case .staleWithoutDailyBuckets: return localized("The kept data is out of date", "保留的数据已过期")
        case .unavailable: return localized("Unavailable", "不可用")
        }
    }

    private var isCodexConnected: Bool {
        provider?.connection == .connected || provider?.connection == .transitional
    }

    // MARK: Usage card

    private var pageGauge: UsageGaugeReading? {
        guard let provider, let reading = UsageGaugeReading.from(provider: provider),
              reading.lead != .unavailable else { return nil }
        return reading
    }

    private var pageLogoColor: Color {
        guard let provider else { return .secondary }
        if AgentGlancePresentationPolicy.status(for: provider) == .connected {
            return AgentConnectionIndicatorPalette.connected(isDark: colorScheme == .dark,
                                                             increasedLightContrast: true)
        }
        return workspaceLogoColor
    }

    /// The same card as the Quick Panel's, taller, with the time to each reset.
    private func pageGaugeCard(_ gauge: UsageGaugeReading, width: CGFloat) -> some View {
        let language = store.language
        let now = displayNow
        func dayAndTime(_ date: Date) -> String {
            "\(UsageGaugeText.day(date, language: language)) \(UsageGaugeText.time(date, language: language))"
        }
        let primary: String
        let secondary: String
        switch gauge.lead {
        case .fiveHour:
            primary = gauge.primary?.resetsAt.map {
                UsageGaugeText.withRelative(UsageGaugeText.time($0, language: language),
                                            resetsAt: $0, now: now, language: language)
            } ?? ""
            secondary = gauge.secondary?.resetsAt.map {
                UsageGaugeText.withRelative(dayAndTime($0), resetsAt: $0, now: now, language: language)
            } ?? ""
        case .sevenDay:
            primary = gauge.primary?.resetsAt.map {
                UsageGaugeText.withRelative(dayAndTime($0), resetsAt: $0, now: now, language: language)
            } ?? ""
            secondary = UsageGaugeText.secondary(gauge, language: language)
        case .unlimited, .unavailable:
            primary = UsageGaugeText.primaryReset(gauge, language: language)
            secondary = UsageGaugeText.secondary(gauge, language: language)
        }
        return UsageGaugeCard(
            reading: gauge,
            providerID: providerID.rawValue,
            size: CGSize(width: max(240, width), height: 88),
            primaryResetText: primary,
            secondaryText: secondary,
            statusColor: pageLogoColor,
            showsLogo: false
        )
        .frame(height: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pageGaugeAccessibilityLabel(gauge, primary: primary, secondary: secondary))
        .accessibilityIdentifier("uma.agent.usage-card")
    }

    private func pageGaugeAccessibilityLabel(_ gauge: UsageGaugeReading, primary: String, secondary: String) -> String {
        switch gauge.lead {
        case .fiveHour:
            var label = localized("5 hours: \(gauge.primaryValueText) left, resets \(primary)",
                                  "5 小时剩余 \(gauge.primaryValueText)，\(primary) 重置")
            if let seven = gauge.secondaryValueText {
                label += localized("; 7 days: \(seven) left, resets \(secondary)",
                                   "；7 天剩余 \(seven)，\(secondary) 重置")
                if gauge.barTier == .low { label += localized(", 7-day quota low", "，7 天额度偏低") }
            }
            return gauge.isEstimate
                ? label.replacingOccurrences(of: "≈", with: localized("about ", "约 "))
                : label
        case .sevenDay:
            return localized("7 days: \(gauge.primaryValueText) left, resets \(primary)",
                             "7 天剩余 \(gauge.primaryValueText)，\(primary) 重置")
        case .unlimited:
            return localized("No limit", "没有上限")
        case .unavailable:
            return localized("No quota reading", "无额度读数")
        }
    }

    // MARK: Settings

    /// The agent's settings, last on its page: the only way to them from the
    /// main window. Codex's connection is the module's last row.
    @ViewBuilder private var settingsModule: some View {
        // An agent with no settings of its own shows no settings module;
        // Codex keeps it for Disconnect.
        if (settingsContent != nil && store.agentSettings != nil) || providerID == .codex {
            module(localized("\(providerID.displayName) Settings", "\(providerID.displayName) 设置"),
                   systemImage: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 10) {
                    let hasSettings = settingsContent != nil && store.agentSettings != nil
                    if hasSettings, let settingsContent { settingsContent }
                    if providerID == .codex {
                        if hasSettings { Divider().accessibilityHidden(true) }
                        codexConnectionRow
                    }
                }
            }
            .accessibilityIdentifier("uma.agent.settings.\(providerID.rawValue)")
        }
    }

    private var codexConnectionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("Connection", "连接"))
                    .font(.system(size: 13, weight: .medium))
                Text(isCodexConnected
                     ? localized("After disconnecting, AUV stops reading this agent's usage.",
                                 "断开后 AUV 不再读取此智能体的用量。")
                     : localized("Connect to read this agent's usage.", "连接后读取此智能体的用量。"))
                    .font(AUVLook.current.isStandard ? .system(size: 11.5) : AUVLookType.text(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isCodexConnected {
                Button(action: disconnectCodex) {
                    // Rust in wabi-sabi; an underlined red link in Brutalist.
                    Text(localized("Disconnect", "断开连接"))
                        .underline(AUVLook.current == .brutalist)
                }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AUVLookPalette.destructive(isDark: colorScheme == .dark))
                    .accessibilityIdentifier("uma.agent.codex.disconnect")
            } else {
                Button(localized("Connect", "连接"), action: connectCodex)
                    .accessibilityIdentifier("uma.agent.codex.connect")
            }
        }
    }

    @State private var showsHistoryCaveat = false
    @State private var showsTrendNote = false

    /// No daily history: one row of the connection module, with the caveat
    /// one click away.
    private var dailyTrendRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(localized("Daily trend", "每日趋势")).foregroundStyle(.secondary)
            Spacer(minLength: 18)
            Text(dailyTrendRowValue).multilineTextAlignment(.trailing).lineLimit(2)
            Button { showsTrendNote.toggle() } label: {
                Text(localized("About", "说明")).underline(!AUVLook.current.isStandard)
            }
                .auvLinkStyle()
                .popover(isPresented: $showsTrendNote, arrowEdge: .bottom) {
                    Text(historyFootnote)
                        .font(AUVType.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 300, alignment: .leading)
                        .padding(14)
                }
                .accessibilityIdentifier("uma.agent.codex.history-details")
        }
        .accessibilityIdentifier("uma.agent.codex.daily-trend-row")
    }

    private var trendGapCard: some View {
        module(historyModuleTitle, systemImage: "chart.bar") {
            VStack(alignment: .leading, spacing: 7) {
                if case let .accountDailyBuckets(buckets, _) = codexProjection.historyAvailability {
                    accountDailyBars(buckets)
                } else {
                    Text(historyHeading)
                        .font(AUVType.headline)
                    Text(historyDetail)
                        .font(AUVType.secondary).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(historySourceLine)
                    .font(AUVType.secondary).foregroundStyle(.secondary)
                DisclosureGroup(
                    localized("Period and data caveats", "周期与数据说明"),
                    isExpanded: $showsHistoryCaveat
                ) {
                    Text(historyFootnote)
                        .font(AUVType.secondary).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(AUVType.secondary)
                .accessibilityIdentifier("uma.agent.codex.history-details")
            }
        }
        .accessibilityIdentifier("uma.agent.codex.daily-trend")
        .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.history-bounds"))
    }

    private var historySourceLine: String {
        CodexDashboardPresentation.historySourceLine(codexProjection.historyAvailability, language: store.language)
    }

    private var historyHeading: String {
        switch codexProjection.historyAvailability {
        case .accountDailyBuckets:
            localized("Account daily token history", "账户每日令牌历史")
        case .aggregateOnly:
            localized("Daily history is not projected for this snapshot.", "此快照未投影每日历史。")
        case .staleWithoutDailyBuckets:
            localized("The retained local history is stale.", "保留的本地历史已过期。")
        case .unavailable:
            localized("Local history is unavailable.", "本地历史不可用。")
        }
    }

    private var historyModuleTitle: String {
        if case .accountDailyBuckets = codexProjection.historyAvailability {
            return localized("Account daily token trend", "账户每日令牌趋势")
        }
        return localized("Local daily token trend", "本地每日令牌趋势")
    }

    private var historyFootnote: String {
        CodexDashboardPresentation.historyFootnote(codexProjection.historyAvailability, language: store.language)
    }

    private func accountDailyBars(_ buckets: [AgentAccountUsageDay]) -> some View {
        let shown = codexProjection.dailySlots()
        let maximum = max(Int64(1), shown.compactMap(\.tokens).max() ?? 1)
        // Neutral bars: colour on this page belongs to the usage card, and blue
        // there means "no limit". The latest day with a value is a step deeper.
        let latest = shown.last(where: { ($0.tokens ?? 0) > 0 })?.id
        let isDark = colorScheme == .dark
        return HStack(alignment: .bottom, spacing: 7) {
            ForEach(shown) { bucket in
                VStack(spacing: 4) {
                    Text(bucket.tokens.map { $0.formatted(.number.notation(.compactName)) } ?? "—")
                        .font(UsageGaugeTypography.number(size: 12))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(bucket.tokens == nil
                              ? Color.primary.opacity(0.08)
                              : Color.primary.opacity(bucket.id == latest
                                                      ? (isDark ? 0.55 : 0.50)
                                                      : (isDark ? 0.26 : 0.20)))
                        .frame(height: bucket.tokens == 0 ? 0 : max(4, 84 * CGFloat(Double(bucket.tokens ?? 0) / Double(maximum))))
                    Text(String(bucket.day.suffix(5)))
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(bucket.tokens.map { "\(bucket.day): \($0) tokens" } ?? "\(bucket.day): unknown tokens")
            }
        }
        .frame(height: 124, alignment: .bottom)
        .accessibilityIdentifier("uma.agent.codex.daily-plot")
        .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.plot-bounds"))
    }

    private var historyDetail: String {
        CodexDashboardPresentation.historyDetail(codexProjection.historyAvailability, language: store.language)
    }

    private func metricRow(for width: CGFloat) -> some View {
        let metrics = codexProjection.metrics
        let week = dashboardMetric(metrics.first(where: { $0.id == "week" }), title: localized("Account 7D tokens", "账户7天令牌"), anchor: "uma015.codex.metric-week")
        let total = dashboardMetric(metrics.first(where: { $0.id == "total" }), title: localized("Account lifetime tokens", "账户累计令牌"), anchor: "uma015.codex.metric-total")
        let local = dashboardMetric(metrics.first(where: { $0.id == "api-cost-seven-days" }), title: CodexDashboardPresentation.localEstimateTitle(language: store.language), anchor: "uma015.codex.metric-local", isLocalEstimate: true)
        // Three equal blocks in a row; one column only in a very narrow page.
        // Where the figures come from is said once, under the row.
        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if width >= 520 {
                    // Brutalist: one grid, neighbours share a rule.
                    HStack(alignment: .top, spacing: 8) { week; total; local }
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 8) { week; total; local }
                }
            }
            Text(metricSourceLine)
                .font(AUVType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // Wabi tiles have no inset, so the line starts where the figures do.
                .padding(.leading, AUVLook.current == .wabiSabi ? 0 : 2)
                .accessibilityIdentifier("uma.agent.codex.metric-source")
        }
        .accessibilityIdentifier("uma.agent.codex.metrics")
        .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.metric-bounds"))
    }

    private var metricSourceLine: String {
        let local = codexProjection.metrics.first(where: { $0.id == "api-cost-seven-days" })
        if CodexDashboardPresentation.localEstimateState(snapshot: store.snapshot) == .current,
           let coverage = local?.coveragePercent {
            return localized(
                "Token counts come from the account report; the cost is estimated locally at API prices and covers \(coverage)% of sessions.",
                "令牌数来自账户报告；费用按 API 价格在本地估算，覆盖 \(coverage)% 的会话。")
        }
        return localized("Token counts come from the account report.", "令牌数来自账户报告。")
    }

    private func dashboardMetric(_ metric: CodexDashboardProjection.Metric?, title: String, anchor: String, isLocalEstimate: Bool = false) -> some View {
        let sourceState = isLocalEstimate
            ? CodexDashboardPresentation.localEstimateState(snapshot: store.snapshot)
            : CodexDashboardPresentation.accountState(snapshot: store.snapshot, provider: provider)
        let status: String = {
            switch sourceState {
            case .unavailable:
                return isLocalEstimate
                    ? localized("Local estimate source unavailable", "本地估算来源不可用")
                    : localized("Account source unavailable", "账户来源不可用")
            case .stale:
                return isLocalEstimate
                    ? localized("Local estimate observation is stale", "本地估算观测已过期")
                    : localized("Account observation is stale", "账户观测已过期")
            case .current where metric?.value == nil:
                return isLocalEstimate
                    ? localized("Local estimate unavailable", "本地估算不可用")
                    : localized("No value from current source", "当前来源未提供数值")
            case .current:
                return isLocalEstimate
                    ? localized("Local estimate · 7D", "本地估算 · 7天")
                    : localized("Account reported", "账户报告")
            }
        }()
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AUVType.secondary).foregroundStyle(.secondary)
                .lineLimit(isLocalEstimate ? 2 : 1)
                .fixedSize(horizontal: false, vertical: isLocalEstimate)
                .help(title)
                .accessibilityIdentifier("\(anchor)-title")
            Text(CodexDashboardPresentation.metricValue(metric, state: sourceState))
                .font(UsageGaugeTypography.number(size: 24))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .background(AgentWorkspaceGeometryAnchor(identifier: "\(anchor)-value"))
            if sourceState == .current, metric?.value != nil {
                // A current figure needs no caption; the row's footnote says
                // where it comes from.
                EmptyView()
            } else {
                Text(status)
                    .font(AUVType.secondary).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(status)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Wabi-sabi's stats are plain text, flush with the card above.
        .padding(.horizontal, AUVLook.current == .wabiSabi ? 0 : 12)
        .padding(.vertical, 12)
        .usageGaugeSurface()
        .background(AgentWorkspaceGeometryAnchor(identifier: anchor))
    }

    /// Recent local activity, as rows of the connection module rather than a
    /// card of its own that mostly said "unavailable".
    @ViewBuilder private var recentActivityRows: some View {
        let activity = store.snapshot.recentTasks
        let state = CodexDashboardPresentation.activityState(snapshot: store.snapshot)
        factRow(localized("Recent local activity", "最近本地活动"), {
            switch state {
            case .unavailable: return localized("Source unavailable", "来源不可用")
            case .empty: return localized("None yet", "暂无")
            case .stale: return localized("Stale", "已过期")
            case .current:
                let n = min(4, activity.count)
                let hidden = activity.prefix(4).allSatisfy { !$0.tokenText.contains(where: \.isNumber) }
                return hidden
                    ? localized("\(n), details hidden", "\(n) 条，内容已隐藏")
                    : localized("\(n) recent", "最近 \(n) 条")
            }
        }())
        let shown = Array(activity.prefix(4))
        // When every item is hidden for privacy, the count row says so once.
        let allHidden = !shown.isEmpty && shown.allSatisfy { !$0.tokenText.contains(where: \.isNumber) }
        if (state == .stale || state == .current), !allHidden {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(item.title)
                            Text(item.time).font(AUVType.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Text(item.tokenText).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, 12)
            .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.activity-bounds"))
        }
    }

    private func workspaceColumns(for width: CGFloat) -> [GridItem] {
        let usableWidth = max(0, width - (AgentWorkspaceLayoutPolicy.horizontalPadding * 2))
        return Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: AgentWorkspaceLayoutPolicy.moduleSpacing, alignment: .top),
            count: AgentWorkspaceLayoutPolicy.columnCount(for: usableWidth)
        )
    }

    private var workspaceLogoColor: Color {
        guard let provider else { return .secondary }
        switch AgentGlancePresentationPolicy.status(for: provider) {
        case .connected: return AgentConnectionIndicatorPalette.connected(isDark: colorScheme == .dark)
        case .reconnecting, .stale, .cached, .needsAttention, .authenticationRequired: return .orange
        case .error: return .red
        case .disconnected, .unavailable: return .secondary
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            DesktopAgentLogo(providerID: providerID.rawValue,
                             tint: pageLogoColor, diameter: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(providerID.displayName)
                    .font(AUVLookType.display(22, standard: .system(size: 22, weight: .semibold)))
                HStack(spacing: 6) {
                    Circle().fill(workspaceLogoColor).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(headerSubtitle)
                        .font(AUVType.secondary)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            // Nothing else up here: usage is the card below, settings the last
            // module. Connecting is the page's one action while disconnected.
            if providerID == .codex, !isCodexConnected {
                Button(localized("Connect", "连接"), action: connectCodex)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("uma.agent.codex.header-connect")
            }
        }
        .padding(.bottom, 2)
    }

    /// Status and plan on one line under the name, so neither needs a card.
    private var headerSubtitle: String {
        [connectionLabel, planLabel].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var usageModule: some View {
        module(localized("Usage", "用量"), systemImage: "gauge.with.dots.needle.50percent") {
            if let provider, !provider.quotas.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(provider.quotas.enumerated()), id: \.element.id) { index, quota in
                        quotaRow(quota)
                        if index < provider.quotas.count - 1 { Divider().accessibilityHidden(true) }
                    }
                    if providerID == .codex, provider.fiveHourStatus == .absent {
                        Divider().accessibilityHidden(true)
                        missingFiveHourMessage
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("No quota reading", "无额度读数")).font(AUVType.headline)
                    // Claude earns its own explanation: "connect or refresh"
                    // cannot produce a percentage here, so saying it misleads.
                    Text(providerID == .claude
                        ? store.language.claudeMissingQuotaGuidance
                        : localized(
                            "Connect or refresh this agent to retrieve qualified usage data.",
                            "连接或刷新此智能体以获取合格的用量数据。"
                        ))
                        .font(AUVType.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private var missingFiveHourMessage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("5H")
                .font(AUVType.headline)
            Spacer(minLength: 12)
            Text(localized("Limit not reported", "未报告限额"))
                .font(AUVType.secondary)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func quotaRow(_ quota: ProviderProductQuotaState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(quota.compactLabel).font(AUVType.headline)
                    Text(quotaDetailLabel(quota))
                        .font(AUVType.label)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.primary.opacity(0.07)))
                }
                Spacer()
                Text(quota.displayText)
                    .font(AUVType.metric)
                    .monospacedDigit()
            }
            AgentRemainingQuotaBar(
                remainingPercent: quota.value.remainingPercent,
                tint: UsageGaugePalette.dynamicColor(forRemaining: quota.value.remainingPercent))
            if let reset = Self.detailResetLine(
                kind: quota.kind, resetsAt: quota.resetsAt,
                language: store.language, now: displayNow
            ) {
                resetText(reset)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// The full page shows every reset that is known, whatever the Quick
    /// Panel's own reset setting says. A credit balance's next expiry is not a
    /// reset, and an unknown reset is left out rather than spelled out.
    static func detailResetLine(
        kind: ProviderProductQuotaKind,
        resetsAt: Date?,
        language: AppLanguage,
        now: Date
    ) -> String? {
        guard kind != .credits, let resetsAt else { return nil }
        return language.resetDescription(for: resetsAt, now: now)
    }

    /// Every reset line keeps the same type size: a long line wraps instead of
    /// shrinking (0.18.8 shrank Claude's 5H line next to its 7D line).
    private func resetText(_ text: String) -> some View {
        Label(text, systemImage: "arrow.clockwise")
            .labelStyle(.titleAndIcon)
            .font(AUVType.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `store.snapshot` is the primary provider's only, so a workspace that is
    /// not the primary had no way to read its own local metrics.
    private var localCostEstimate: APICostEstimateSnapshot? {
        store.snapshot(for: providerID)?.apiCostEstimate
    }

    /// Aggregate API-equivalent estimate, published under the connector privacy
    /// allowlist. Derived from the already-allowlisted local token total and a
    /// frozen public price list: never a bill, never per task.
    private var localCostModule: some View {
        module(
            localized("Local Cost Estimate", "本地费用估算"),
            systemImage: "dollarsign.circle"
        ) {
            VStack(spacing: 7) {
                if let estimate = localCostEstimate {
                    factRow(
                        localized("Last 7 days", "近 7 天"),
                        estimate.sevenDayUSD.formatted(.currency(code: "USD"))
                    )
                    factRow(
                        localized("Lifetime", "累计"),
                        estimate.lifetimeUSD.formatted(.currency(code: "USD"))
                    )
                    factRow(
                        localized("Priced coverage", "计价覆盖率"),
                        "\(estimate.coveragePercent)%"
                    )
                }
                Text(localized(
                    "API-equivalent, from local token totals and public list prices. Not a bill; no billing data is read.",
                    "按本地令牌总量与公开价目表折算的 API 等效金额。并非账单，不读取任何账单信息。"
                ))
                .font(AUVType.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            }
            .font(AUVType.secondary)
        }
    }

    private var connectionModule: some View {
        module(localized("Connection & Source", "连接与来源"), systemImage: "link") {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(workspaceLogoColor).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    factRow(localized("Status", "状态"), connectionLabel)
                }
                factRow(localized("Source", "来源"), sourceLabel)
                // Only when the reading is not current: "current" says nothing.
                if provider?.freshness != .fresh {
                    factRow(localized("Freshness", "新鲜度"), freshnessLabel)
                }
                if let capturedAt = provider?.capturedAt {
                    HStack {
                        Text(localized("Updated", "更新于")).foregroundStyle(.secondary)
                        Spacer()
                        Text(relativeUpdateDescription(since: capturedAt)).monospacedDigit()
                    }
                }
                // Source health only when there is something to act on.
                if provider?.diagnosticReason != nil {
                    factRow(localized("Source health", "来源健康状态"), diagnosticLabel)
                }
                if pageGauge?.lead == .sevenDay {
                    factRow(localized("Limit period", "限额周期"), localized("7 days only", "只有 7 天"))
                }
                if providerID == .codex {
                    if !hasDailyHistory { dailyTrendRow }
                    recentActivityRows
                }
                if providerID == .claude, case .onlineVerificationUnavailable = claudeControlState() {
                    factRow(localized("Online verification", "在线验证"), localized("Unavailable", "不可用"))
                        .accessibilityIdentifier("uma.agent.claude.accuracy-unavailable")
                }
                if providerID == .claude {
                    Divider().padding(.vertical, 2).accessibilityHidden(true)
                    // The one place this page says how Claude syncs.
                    Text(localized(
                        "Exact figures sync when you choose Refresh All, and on schedule with automatic refresh while Safari is open. Only usage figures are kept; prompts, responses and credentials never enter AUV.",
                        "点“全部刷新”时同步精确读数；开启自动刷新后，Safari 开着时也会定时同步。只保留用量数据，提示、回复和凭据不会进入 AUV。"
                    ))
                    .font(AUVType.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("uma.agent.claude.sync-route")
                }
            }
            .font(AUVType.secondary)
        }
        .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.source-bounds"))
    }

    /// What Claude needs from you, or what it is doing, above its cards.
    /// Nothing shows while all is well: its exact figures come with Refresh
    /// All, so Accuracy Sync has no button of its own.
    @ViewBuilder private var claudeActionCallout: some View {
        if providerID == .claude {
            switch claudeControlState() {
            case .consentRequired:
                callout(systemImage: "sparkles", tint: .accentColor, message: localized(
                    "Turn on Local Smart to read Claude's usage.", "启用本地智能以读取 Claude 用量。")) {
                    Button(localized("Enable Local Smart", "启用本地智能")) {
                        showingClaudeConsent = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("uma.agent.claude.enable-local-smart")
                }
            case .localSmartRepairRequired:
                callout(systemImage: "wrench.and.screwdriver", tint: .orange, message: localized(
                    "Local Smart stopped working and needs a repair.", "本地智能已停止工作，需要修复。")) {
                    Button(localized("Repair Local Smart", "修复本地智能"), action: connectClaude)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("uma.agent.claude.repair-local-smart")
                }
            case .statusLineConfigurationUnavailable(let issue):
                callout(systemImage: "exclamationmark.triangle", tint: .orange, message: issue == .developmentIsolation
                    ? localized("Claude Code setup is unavailable in this development build.", "此开发版本不配置 Claude Code。")
                    : localized("Install AUV in Applications or Desktop to connect Claude Code.", "请将 AUV 安装到 Applications 或桌面后连接 Claude Code。")) {
                    EmptyView()
                }
            case .accuracyReady:
                EmptyView()
            case .accuracyInProgress:
                callout(progress: true, tint: .accentColor, message: localized(
                    "Syncing exact figures…", "正在同步精确读数…")) { EmptyView() }
                    .accessibilityIdentifier("uma.agent.claude.accuracy-in-progress")
            case .companionStarting:
                callout(progress: true, tint: .secondary, message: localized(
                    "Browser Companion is starting…", "浏览器伴侣正在启动…")) { EmptyView() }
                    .accessibilityIdentifier("uma.agent.claude.accuracy-unavailable")
            case .companionUpdateRequired:
                callout(systemImage: "arrow.down.circle", tint: .orange, message: localized(
                    "Browser Companion needs an update. Open Claude Settings to repair it.",
                    "浏览器伴侣需要更新，请在 Claude 设置中修复。")) { EmptyView() }
                    .accessibilityIdentifier("uma.agent.claude.accuracy-unavailable")
            case .onlineVerificationUnavailable:
                // A state, not an action: it is a row of the connection module.
                EmptyView()
            case .safariSetupIncomplete(let step):
                safariSetupCallout(step)
            }
        }
    }

    /// Claude's exact figures come through Safari. Until that is set up, the
    /// page shows the next step and one button for it; `connectClaude` takes
    /// whichever step this is. Claude Settings lists all of them.
    @ViewBuilder private func safariSetupCallout(_ step: ClaudeSafariSetup.Step) -> some View {
        let copy = ClaudeSafariSetupCopy.step(step, language: store.language)
        callout(systemImage: copy.symbol, tint: copy.urgent ? .orange : .accentColor, message: copy.message) {
            if let button = copy.button {
                Button(button, action: connectClaude)
                    .buttonStyle(.borderedProminent)
            }
        }
        .accessibilityIdentifier("uma.agent.claude.safari-setup")
    }

    private func callout<Action: View>(
        systemImage: String? = nil,
        progress: Bool = false,
        tint: Color,
        message: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 10) {
            if progress {
                ProgressView().controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(message)
                .font(AUVType.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action().controlSize(.regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AUVShape.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AUVShape.cardRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func module<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch AUVLook.current {
            case .standard:
                Label {
                    Text(title).font(AUVType.headline)
                } icon: {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            case .wabiSabi:
                // A quiet Mincho title, no icon.
                Text(title).font(.custom("HiraMinProN-W3", size: 14)).tracking(1)
                    .foregroundStyle(AUVLookPalette.ink(isDark: colorScheme == .dark).opacity(0.78))
            case .brutalist:
                // A table head over a rule.
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .heavy))
                    Rectangle().fill(UMAVisualStyle.separator).frame(height: 1).padding(.horizontal, -14)
                }
            }
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .moduleSurface()
    }

    @ViewBuilder
    private func module<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .moduleSurface()
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 18)
            Text(value).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .font(AUVLook.current.isStandard ? nil : AUVLookType.text(13))
    }

    private var connectionLabel: String {
        guard let provider else { return localized("Unavailable", "不可用") }
        return switch provider.connection {
        case .connected: localized("Connected", "已连接")
        case .transitional: localized("Reconnecting", "正在重新连接")
        case .authenticationRequired:
            providerID == .claude
                ? localized("Setup required", "需要设置")
                : localized("Sign in required", "需要登录")
        case .disconnected: localized("Disconnected", "已断开")
        case .unavailable: localized("Unavailable", "不可用")
        case .failed: localized("Error", "错误")
        }
    }

    private var planLabel: String? {
        guard provider?.freshness != .unavailable else { return nil }
        if let plan = provider?.planLabel, !plan.isEmpty { return plan }
        if providerID == .codex, store.snapshot.planLabel != "—" {
            return store.snapshot.planLabel
        }
        return nil
    }

    private var sourceLabel: String {
        guard provider?.freshness != .unavailable else {
            return localized("Unavailable", "不可用")
        }
        guard let source = provider?.sourceSummary else {
            return localized("Unavailable", "不可用")
        }
        return switch source {
        case .officialLocal: localized("Official local account source", "官方本地账户来源")
        case .localSmartExact: localized("Local Smart exact observation", "本地智能精确观测")
        case .localSmartEstimate: localized("Local Smart estimate", "本地智能估算")
        case .accuracySync: localized("One-shot Accuracy Sync", "一次性精确同步")
        case .combinedSanitized: localized("Combined sanitized sources", "组合脱敏来源")
        case .authenticatedAccountWeb: localized("Authenticated provider account", "已认证的提供方账户")
        case .officialCLI: localized("Official command-line source", "官方命令行来源")
        case .geminiWebUsage: localized("Gemini web Usage page (Gemini App quota)", "Gemini 网页用量页（Gemini App 额度）")
        case .unavailable: localized("Unavailable", "不可用")
        }
    }

    private var freshnessLabel: String {
        guard let freshness = provider?.freshness else {
            return localized("Unavailable", "不可用")
        }
        return switch freshness {
        case .fresh: localized("Current", "当前")
        case .cached: localized("Recent cached value", "近期缓存值")
        case .stale: localized("Stale", "已过期")
        case .unavailable: localized("Unavailable", "不可用")
        }
    }

    private var diagnosticLabel: String {
        guard let reason = provider?.diagnosticReason else {
            return localized("No action required", "无需操作")
        }
        return switch reason {
        case .authorizationRequired: localized("Authorization required", "需要授权")
        case .setupRequired: localized("Setup required", "需要设置")
        case .sourceUnavailable: localized("Source unavailable", "来源不可用")
        case .timedOut: localized("Timed out", "已超时")
        case .unsupported: localized("Unsupported", "不受支持")
        case .invalidData: localized("Usage data was rejected", "用量数据被拒绝")
        case .processUnavailable: localized("Local process unavailable", "本地进程不可用")
        case .staleData: localized("Last value is stale", "最近数据已过期")
        case .unknown: localized("Unknown status", "未知状态")
        }
    }

    private func precisionLabel(_ precision: ProviderProductPrecision) -> String {
        switch precision {
        case .exact: localized("Exact", "精确")
        case .estimated: localized("Estimated", "估算")
        case .unavailable: localized("Unavailable", "不可用")
        }
    }

    private func quotaDetailLabel(_ quota: ProviderProductQuotaState) -> String {
        if quota.value == .unavailable {
            return localized("Limit not reported", "未报告限额")
        }
        if quota.value == .unlimited {
            return localized("Unlimited", "不限量")
        }
        return precisionLabel(quota.precision)
    }

    private var displayNow: Date { referenceDate ?? Date() }

    private func relativeUpdateDescription(since date: Date) -> String {
        let interval = date.timeIntervalSince(displayNow)
        if interval > 60 {
            // A clock that runs ahead: say when, not "in the future".
            let formatter = DateFormatter(); formatter.locale = store.language.locale; formatter.dateStyle = .none; formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        if abs(interval) <= 60 { return localized("just now", "刚刚") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = store.language.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: displayNow)
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        store.language == .simplifiedChinese ? chinese : english
    }
}

@MainActor
final class GlobalSettingsViewModel: ObservableObject {
    @Published private(set) var language: AppLanguage
    @Published private(set) var appearance: UMAApplicationAppearance
    @Published private(set) var look: AUVLook
    @Published private(set) var menuBarShowsRemaining: Bool
    @Published private(set) var quickPanelShowsReset: Bool
    @Published private(set) var quickPanelShowsConnectivity: Bool
    @Published private(set) var quickPanelShowsRemainingRails: Bool
    @Published private(set) var keepMonitoringWhenWindowsClose: Bool
    @Published private(set) var automaticBackgroundRefresh: Bool
    @Published private(set) var backgroundRefreshInterval: UMABackgroundRefreshInterval
    @Published private(set) var refreshOnWake: Bool
    @Published private(set) var assistantEnabled: Bool
    @Published private(set) var assistantAlwaysOnTop: Bool
    @Published private(set) var assistantDensity: DesktopAssistantDensity
    @Published private(set) var assistantShowsStatusIndicator: Bool
    @Published private(set) var assistantShowsPercentageRail: Bool
    @Published private(set) var launchAtLoginState: LaunchAtLoginState
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var dataActionStatus: String?

    private let retainedDataService: SettingsRetainedDataService
    private let preferences: ApplicationPreferences
    private let store: UsageStore
    private var observation: ApplicationPreferences.Observation?
    /// Agents whose monitoring is off, for Settings › Agents › Turned Off.
    @Published private(set) var turnedOffAgentIDs: [AgentConnectorID] = []
    private var agentSettingsSubscription: AnyCancellable?

    init(
        preferences: ApplicationPreferences,
        store: UsageStore,
        dataPaths: ApplicationDataPaths = .current()
    ) {
        retainedDataService = SettingsRetainedDataService(dataPaths: dataPaths)
        self.preferences = preferences
        self.store = store
        language = preferences.value(for: UMAApplicationPreferenceKeys.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
        appearance = UMAApplicationAppearance(
            rawValue: preferences.value(for: UMAApplicationPreferenceKeys.appearance)
        ) ?? .system
        look = AUVLook(rawValue: preferences.value(for: UMAApplicationPreferenceKeys.look)) ?? .standard
        menuBarShowsRemaining = preferences.value(
            for: UMAApplicationPreferenceKeys.menuBarShowsRemaining
        )
        quickPanelShowsReset = preferences.value(
            for: UMAApplicationPreferenceKeys.quickPanelShowsReset
        )
        quickPanelShowsConnectivity = preferences.value(
            for: UMAApplicationPreferenceKeys.quickPanelShowsConnectivity
        )
        quickPanelShowsRemainingRails = preferences.value(
            for: UMAApplicationPreferenceKeys.quickPanelShowsRemainingRails
        )
        keepMonitoringWhenWindowsClose = preferences.value(
            for: UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose
        )
        automaticBackgroundRefresh = preferences.value(
            for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh
        )
        backgroundRefreshInterval = UMABackgroundRefreshInterval(
            rawValue: preferences.value(
                for: UMAApplicationPreferenceKeys.backgroundRefreshInterval
            )
        ) ?? .fifteenMinutes
        refreshOnWake = preferences.value(for: UMAApplicationPreferenceKeys.refreshOnWake)
        assistantEnabled = preferences.value(
            for: UMAApplicationPreferenceKeys.assistantEnabled
        )
        assistantAlwaysOnTop = preferences.value(
            for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop
        )
        assistantDensity = DesktopAssistantDensity(
            rawValue: preferences.value(
                for: UMAApplicationPreferenceKeys.assistantDensity
            )
        ) ?? .automatic
        assistantShowsStatusIndicator = preferences.value(
            for: UMAApplicationPreferenceKeys.assistantShowsStatusIndicator
        )
        assistantShowsPercentageRail = preferences.value(
            for: UMAApplicationPreferenceKeys.assistantShowsPercentageRail
        )
        launchAtLoginState = LaunchAtLoginService.state
        launchAtLoginError = nil
        dataActionStatus = nil
        observation = preferences.observe { [weak self] change in
            self?.synchronize(changedKey: change.key)
        }
        if let coordinator = store.agentSettings {
            turnedOffAgentIDs = TurnedOffAgentSettingsRows.turnedOffProviderIDs(in: coordinator)
            // The envelope publishes before it changes; read it on the next turn.
            agentSettingsSubscription = coordinator.$envelope
                .receive(on: RunLoop.main)
                .sink { @MainActor [weak self, weak coordinator] _ in
                    guard let self, let coordinator else { return }
                    let ids = TurnedOffAgentSettingsRows.turnedOffProviderIDs(in: coordinator)
                    if ids != self.turnedOffAgentIDs { self.turnedOffAgentIDs = ids }
                }
        }
    }

    func setLanguage(_ value: AppLanguage) {
        guard language != value else { return }
        preferences.set(value.rawValue, for: UMAApplicationPreferenceKeys.language)
        store.setLanguage(value)
        language = value
    }

    func setAppearance(_ value: UMAApplicationAppearance) {
        guard appearance != value else { return }
        appearance = value
        preferences.set(value.rawValue, for: UMAApplicationPreferenceKeys.appearance)
    }

    func setLook(_ value: AUVLook) {
        guard look != value else { return }
        look = value
        preferences.set(value.rawValue, for: UMAApplicationPreferenceKeys.look)
        // Each look has its own welcome sound; choosing one plays it.
        AUVWelcomeSound.play(language, style: AUVWelcomeSound.Style(rawValue: value.rawValue))
    }

    func setMenuBarShowsRemaining(_ value: Bool) {
        guard menuBarShowsRemaining != value else { return }
        menuBarShowsRemaining = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.menuBarShowsRemaining)
    }

    func setQuickPanelShowsReset(_ value: Bool) {
        guard quickPanelShowsReset != value else { return }
        quickPanelShowsReset = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.quickPanelShowsReset)
    }

    func setQuickPanelShowsConnectivity(_ value: Bool) {
        quickPanelShowsConnectivity = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.quickPanelShowsConnectivity)
    }

    func setQuickPanelShowsRemainingRails(_ value: Bool) {
        quickPanelShowsRemainingRails = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.quickPanelShowsRemainingRails)
    }

    func setKeepMonitoringWhenWindowsClose(_ value: Bool) {
        keepMonitoringWhenWindowsClose = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose)
    }

    func setAutomaticBackgroundRefresh(_ value: Bool) {
        automaticBackgroundRefresh = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh)
    }

    func setBackgroundRefreshInterval(_ value: UMABackgroundRefreshInterval) {
        backgroundRefreshInterval = value
        preferences.set(value.rawValue, for: UMAApplicationPreferenceKeys.backgroundRefreshInterval)
    }

    func setRefreshOnWake(_ value: Bool) {
        refreshOnWake = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.refreshOnWake)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            launchAtLoginState = try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginState = LaunchAtLoginService.state
            launchAtLoginError = error.localizedDescription
        }
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginState = LaunchAtLoginService.state
        launchAtLoginError = nil
    }

    func openLoginItemSettings() {
        LaunchAtLoginService.openSystemSettings()
    }

    deinit {
        let retainedObservation = observation
        Task { @MainActor in
            retainedObservation?.cancel()
        }
    }

    func setAssistantEnabled(_ value: Bool) {
        guard assistantEnabled != value else { return }
        assistantEnabled = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.assistantEnabled)
    }

    func setAssistantAlwaysOnTop(_ value: Bool) {
        guard assistantAlwaysOnTop != value else { return }
        assistantAlwaysOnTop = value
        preferences.set(
            value,
            for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop
        )
    }

    func setAssistantDensity(_ value: DesktopAssistantDensity) {
        guard assistantDensity != value else { return }
        assistantDensity = value
        preferences.set(
            value.rawValue,
            for: UMAApplicationPreferenceKeys.assistantDensity
        )
    }

    func setAssistantShowsStatusIndicator(_ value: Bool) {
        assistantShowsStatusIndicator = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.assistantShowsStatusIndicator)
    }

    func setAssistantShowsPercentageRail(_ value: Bool) {
        assistantShowsPercentageRail = value
        preferences.set(value, for: UMAApplicationPreferenceKeys.assistantShowsPercentageRail)
    }

    func resetAssistantPosition() {
        preferences.remove(UMAApplicationPreferenceKeys.assistantPosition)
        dataActionStatus = language == .simplifiedChinese
            ? "桌面助手位置已重置。"
            : "Desktop Assistant position reset."
    }

    func clearRetainedUsageData() {
        dataActionStatus = language == .simplifiedChinese ? "正在清除…" : "Clearing…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.retainedDataService.clear()
                self.dataActionStatus = self.language == .simplifiedChinese
                    ? "已清除保留的本地用量数据。"
                    : "Retained local usage data cleared."
            } catch {
                self.dataActionStatus = self.language == .simplifiedChinese
                    ? "无法安全清除保留数据。"
                    : "Retained data could not be cleared safely."
            }
        }
    }

    func exportSanitizedDiagnostics() {
        let panel = NSSavePanel()
        // The name a user sees in the save panel, so it carries the
        // product name. Nothing reads the file back, so renaming it
        // strands no existing data — unlike the Application Support
        // directory, which keeps its UMA path for that reason.
        panel.nameFieldStringValue = "AUV-sanitized-diagnostics.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let activeCount = store.productInventory.providers.filter(\.isActive).count
            let data = try SettingsDiagnosticsExporter.data(
                activeProviderCount: activeCount,
                preferences: preferences
            )
            try SettingsDiagnosticsExporter.write(data, to: destination)
            dataActionStatus = language == .simplifiedChinese
                ? "已导出不含内容的诊断信息。"
                : "Sanitized diagnostics exported."
        } catch {
            dataActionStatus = language == .simplifiedChinese
                ? "无法安全导出诊断信息。"
                : "Diagnostics could not be exported safely."
        }
    }

    private func synchronize(changedKey: String) {
        switch changedKey {
        case UMAApplicationPreferenceKeys.language.name:
            language = preferences.value(for: UMAApplicationPreferenceKeys.language)
                .flatMap(AppLanguage.init(rawValue:)) ?? .english
        case UMAApplicationPreferenceKeys.appearance.name:
            appearance = UMAApplicationAppearance(
                rawValue: preferences.value(for: UMAApplicationPreferenceKeys.appearance)
            ) ?? .system
        case UMAApplicationPreferenceKeys.look.name:
            look = AUVLook(rawValue: preferences.value(for: UMAApplicationPreferenceKeys.look)) ?? .standard
        case UMAApplicationPreferenceKeys.menuBarShowsRemaining.name:
            menuBarShowsRemaining = preferences.value(
                for: UMAApplicationPreferenceKeys.menuBarShowsRemaining
            )
        case UMAApplicationPreferenceKeys.quickPanelShowsReset.name:
            quickPanelShowsReset = preferences.value(
                for: UMAApplicationPreferenceKeys.quickPanelShowsReset
            )
        case UMAApplicationPreferenceKeys.quickPanelShowsConnectivity.name:
            quickPanelShowsConnectivity = preferences.value(
                for: UMAApplicationPreferenceKeys.quickPanelShowsConnectivity
            )
        case UMAApplicationPreferenceKeys.quickPanelShowsRemainingRails.name:
            quickPanelShowsRemainingRails = preferences.value(
                for: UMAApplicationPreferenceKeys.quickPanelShowsRemainingRails
            )
        case UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose.name:
            keepMonitoringWhenWindowsClose = preferences.value(
                for: UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose
            )
        case UMAApplicationPreferenceKeys.automaticBackgroundRefresh.name:
            automaticBackgroundRefresh = preferences.value(
                for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh
            )
        case UMAApplicationPreferenceKeys.backgroundRefreshInterval.name:
            backgroundRefreshInterval = UMABackgroundRefreshInterval(
                rawValue: preferences.value(
                    for: UMAApplicationPreferenceKeys.backgroundRefreshInterval
                )
            ) ?? .fifteenMinutes
        case UMAApplicationPreferenceKeys.refreshOnWake.name:
            refreshOnWake = preferences.value(for: UMAApplicationPreferenceKeys.refreshOnWake)
        case UMAApplicationPreferenceKeys.assistantEnabled.name:
            assistantEnabled = preferences.value(
                for: UMAApplicationPreferenceKeys.assistantEnabled
            )
        case UMAApplicationPreferenceKeys.assistantAlwaysOnTop.name:
            assistantAlwaysOnTop = preferences.value(
                for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop
            )
        case UMAApplicationPreferenceKeys.assistantDensity.name:
            assistantDensity = DesktopAssistantDensity(
                rawValue: preferences.value(
                    for: UMAApplicationPreferenceKeys.assistantDensity
                )
            ) ?? .automatic
        case UMAApplicationPreferenceKeys.assistantShowsStatusIndicator.name:
            assistantShowsStatusIndicator = preferences.value(
                for: UMAApplicationPreferenceKeys.assistantShowsStatusIndicator
            )
        case UMAApplicationPreferenceKeys.assistantShowsPercentageRail.name:
            assistantShowsPercentageRail = preferences.value(
                for: UMAApplicationPreferenceKeys.assistantShowsPercentageRail
            )
        default:
            break
        }
    }
}

/// The agent arrangement as Settings shows it. Rows drag onto each other the
/// way the main window's list does, and the arrows do the same one step at a
/// time. Every change is saved at once and kept until the next one.
/// Agents read from a web page through the Safari Bridge. Each row's switch
/// is that agent's monitoring switch.
struct WebUsageAgentSettingsRows: View {
    @ObservedObject var coordinator: AgentSettingsCoordinator
    @ObservedObject var gemini: GeminiSettingsModel
    let language: AppLanguage

    static let geminiToggleIdentifier = "uma.settings.agents.web-usage.gemini"

    var body: some View {
        Toggle(isOn: Binding(
            get: { coordinator.isMonitoringEnabled(for: AgentPreferenceRecord.geminiProviderID) },
            set: { $0 ? gemini.enable() : gemini.disable() }
        )) {
            HStack(spacing: 8) {
                DesktopAgentLogo(
                    providerID: ProviderProductID.gemini.rawValue,
                    tint: .secondary,
                    diameter: 18
                )
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ProviderProductID.gemini.displayName)
                    Text(detail)
                        .font(AUVType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier(Self.geminiToggleIdentifier)
    }

    private var detail: String {
        coordinator.isMonitoringEnabled(for: AgentPreferenceRecord.geminiProviderID)
            ? language.geminiState(gemini.state)
            : language.geminiSourceLabel
    }
}

/// One titled group of a Settings pane, in the current look.
struct SettingsPaneSection<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content

    init(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        if !AUVLook.current.isStandard {
            AUVLookSection(title: title, footer: footer) { content }
        } else {
            Section {
                content
            } header: {
                Text(title)
                    .font(AUVType.label)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            } footer: {
                if let footer {
                    Text(footer)
                        .font(AUVType.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct AgentOrderSettingsRows: View {
    @ObservedObject var store: UsageStore
    let language: AppLanguage

    private var providers: [ProviderProductState] { store.orderedWorkspaceProviders }

    var body: some View {
        if providers.isEmpty {
            Text(localized("No agents are available yet.", "暂无可用的智能体。"))
                .foregroundStyle(.secondary)
        }
        ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                DesktopAgentLogo(
                    providerID: provider.id.rawValue,
                    tint: .secondary,
                    diameter: 18
                )
                .accessibilityHidden(true)
                Text(provider.id.displayName)
                Spacer()
                Button {
                    store.moveAgent(provider.id, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help(localized("Move up", "上移"))
                .accessibilityLabel(localized("Move \(provider.id.displayName) up", "上移 \(provider.id.displayName)"))
                Button {
                    store.moveAgent(provider.id, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == providers.count - 1)
                .help(localized("Move down", "下移"))
                .accessibilityLabel(localized("Move \(provider.id.displayName) down", "下移 \(provider.id.displayName)"))
            }
            .contentShape(Rectangle())
            .onDrag {
                NSItemProvider(object: provider.id.rawValue as NSString)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let dropped = items.first,
                      let moved = ProviderProductID(rawValue: dropped)
                else { return false }
                store.moveAgent(moved, onto: provider.id)
                return true
            }
            .accessibilityIdentifier("uma.settings.agents.order.\(provider.id.rawValue)")
        }
        HStack {
            Spacer()
            Button(localized("Restore Default Order", "恢复默认顺序"), action: store.resetAgentOrder)
                .disabled(store.agentOrder.isEmpty)
                .accessibilityIdentifier("uma.settings.agents.order.reset")
        }
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}

/// Which agent the menu bar reads. Automatic follows the arrangement; a
/// chosen agent stays there, showing a dash while it has no reading.
private struct MenuBarAgentSettingsPicker: View {
    @ObservedObject var store: UsageStore
    let language: AppLanguage

    var body: some View {
        Picker(
            localized("Agent shown in the menu bar", "菜单栏显示的智能体"),
            selection: Binding(
                get: { ProviderProductID(rawValue: store.menuBarAgent) },
                set: store.setMenuBarAgent
            )
        ) {
            Text(localized("Automatic: first agent in the order with a reading", "自动：顺序中第一个有读数的智能体"))
                .tag(ProviderProductID?.none)
            ForEach(store.menuBarCandidates) { provider in
                Text(provider.id.displayName).tag(Optional(provider.id))
            }
        }
        .pickerStyle(.radioGroup)
        .accessibilityIdentifier("uma.settings.menu-bar.agent")
        if let pinned = ProviderProductID(rawValue: store.menuBarAgent),
           !store.menuBarCandidates.contains(where: { $0.id == pinned }) {
            Text(localized(
                "\(pinned.displayName) is not available, so the menu bar is following the order for now.",
                "\(pinned.displayName) 当前不可用，菜单栏暂时按顺序显示。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}

public enum GlobalSettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    // Refreshing gets a pane of its own: it is the setting people come back
    // to, and since Claude's exact sync follows it, it says what it covers.
    case refresh = "Refresh"
    case agents = "Agents"
    case menuBar = "Menu Bar"
    case desktopWizard = "Desktop Wizard"
    case privacy = "Privacy & Data"
    // Sectorium's settings are on the Sectorium tab, beside the drive they act
    // on; a second copy here ran on its own store and never saw that drive.
    // Appearance, a single control, sits under General with the language.
    public var id: String { rawValue }
}

@MainActor
public final class GlobalSettingsNavigationState: ObservableObject {
    @Published public var pane: GlobalSettingsPane

    public init(pane: GlobalSettingsPane = .general) {
        self.pane = pane
    }
}

public struct GlobalSettingsSurface: View {
    @ObservedObject private var navigation: GlobalSettingsNavigationState
    @StateObject private var model: GlobalSettingsViewModel
    private let store: UsageStore
    private let geminiSettings: GeminiSettingsModel?
    private let agentReconnection: (any AgentReconnecting)?
    /// The window's title bar height when the surface runs under it: the
    /// sidebar and the pane's title start below the traffic lights' row.
    /// Zero keeps the surface below a title bar.
    private let titlebarHeight: CGFloat

    public init(
        preferences: ApplicationPreferences,
        store: UsageStore,
        navigation: GlobalSettingsNavigationState,
        dataPaths: ApplicationDataPaths = .current(),
        geminiSettings: GeminiSettingsModel? = nil,
        agentReconnection: (any AgentReconnecting)? = nil,
        titlebarHeight: CGFloat = 0
    ) {
        self.titlebarHeight = titlebarHeight
        self.navigation = navigation
        self.store = store
        self.geminiSettings = geminiSettings
        self.agentReconnection = agentReconnection
        _model = StateObject(
            wrappedValue: GlobalSettingsViewModel(
                preferences: preferences, store: store, dataPaths: dataPaths
            )
        )
    }

    public var body: some View {
        GeometryReader { viewport in
            HStack(spacing: 0) {
                Group {
                    if AUVLook.current.isStandard {
                        List(GlobalSettingsPane.allCases, selection: $navigation.pane) { item in
                            HStack(spacing: 8) {
                                GlobalSettingsPaneIcon(symbol: symbol(item), tint: tint(item))
                                Text(paneTitle(item))
                                    .font(AUVType.body)
                            }
                            .padding(.vertical, 1)
                            .tag(item)
                        }
                        .listStyle(.sidebar)
                        // Under the title bar the window is one colour.
                        .scrollContentBackground(titlebarHeight > 0 ? .hidden : .automatic)
                    } else {
                        GlobalSettingsLookSidebar(
                            selection: $navigation.pane,
                            title: paneTitle,
                            symbol: symbol
                        )
                    }
                }
                .padding(.top, titlebarHeight)
                .frame(width: 180)
                .accessibilityIdentifier("uma.settings.sidebar")

                if AUVLook.current.isStandard {
                    Divider().frame(width: 1)
                } else {
                    Rectangle().fill(UMAVisualStyle.separator).frame(width: 1)
                }

                // Bound the detail to the actual window viewport. Intrinsic
                // form widths must never push the sidebar out of the window.
                settingsDetail
                    .frame(width: max(0, viewport.size.width - 181), height: viewport.size.height)
                    .accessibilityIdentifier("uma.settings.detail.\(navigation.pane.id)")
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
        }
        .environment(\.locale, model.language.locale)
        .onAppear(perform: model.refreshLaunchAtLoginState)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.refreshLaunchAtLoginState()
        }
        .accessibilityIdentifier("uma.settings.surface")
    }

    /// The pane's name once, at the top, then its groups: no subtitle that
    /// only repeats the sidebar.
    private var settingsDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(paneTitle(navigation.pane))
                .font(AUVLookType.heading(AUVLook.current == .brutalist ? 30 : 24, standard: AUVType.title))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 30)
                // Below the title bar, which keeps only the traffic lights.
                .padding(.top, titlebarHeight > 0 ? titlebarHeight + 6 : 20)
                .padding(.bottom, 2)
            settingsForm
        }
        .background(AUVLook.current.isStandard ? Color.clear : UMAVisualStyle.canvas)
    }

    @ViewBuilder private var settingsForm: some View {
        if AUVLook.current.isStandard {
            Form { settingsFormContent }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        } else {
            // A pack draws its own sections: no rounded system groups.
            ScrollView {
                VStack(alignment: .leading, spacing: AUVLook.current == .wabiSabi ? 30 : 18) {
                    settingsFormContent
                }
                .padding(.horizontal, 30)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            // Kept out of the safe area: under the title bar it would cover
            // the pane's title above it.
            .background(UMAVisualStyle.canvas, ignoresSafeAreaEdges: [])
        }
    }

    @ViewBuilder private var settingsFormContent: some View {
            switch navigation.pane {
            case .general:
                settingsSection(localized("Startup", "启动")) {
                    Toggle(
                        localized("Launch AUV at login", "登录时启动 AUV"),
                        isOn: Binding(
                            get: { model.launchAtLoginState.isOn },
                            set: model.setLaunchAtLogin
                        )
                    )
                    .accessibilityIdentifier("uma.settings.general.launch-at-login")
                    if model.launchAtLoginState == .requiresApproval {
                        HStack {
                            Text(localized(
                                "macOS approval is required before AUV can open at login.",
                                "需要 macOS 批准后，AUV 才能在登录时启动。"
                            ))
                            .font(AUVType.caption)
                            .foregroundStyle(.secondary)
                            Spacer()
                            Button(
                                localized("Open Login Items", "打开登录项"),
                                action: model.openLoginItemSettings
                            )
                        }
                    }
                    if let error = model.launchAtLoginError {
                        Text(error)
                            .font(AUVType.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel(localized("Launch at login error", "登录启动错误"))
                    }
                    Toggle(
                        localized("Keep monitoring when windows close", "关闭窗口后继续监控"),
                        isOn: Binding(
                            get: { model.keepMonitoringWhenWindowsClose },
                            set: model.setKeepMonitoringWhenWindowsClose
                        )
                    )
                    .accessibilityIdentifier("uma.settings.general.keep-monitoring")
                }
                settingsSection(
                    localized("Language & Appearance", "语言与外观"),
                    footer: localized(
                        "Reduce Transparency and Increase Contrast are followed automatically. A look changes only how AUV is drawn.",
                        "自动遵循“降低透明度”和“增强对比度”。外观包只改变 AUV 的样子，不改变功能。"
                    )
                ) {
                    AUVLookMenuPicker(
                        title: localized("Language", "语言"),
                        options: AppLanguage.allCases.map { ($0, $0.displayName) },
                        selection: Binding(
                            get: { model.language },
                            set: model.setLanguage
                        )
                    )
                    .accessibilityIdentifier("uma.settings.general.language")
                    Picker(
                        localized("Appearance", "外观"),
                        selection: Binding(
                            get: { model.appearance },
                            set: model.setAppearance
                        )
                    ) {
                        Text(localized("System", "跟随系统"))
                            .tag(UMAApplicationAppearance.system)
                        Text(localized("Light", "浅色"))
                            .tag(UMAApplicationAppearance.light)
                        Text(localized("Dark", "深色"))
                            .tag(UMAApplicationAppearance.dark)
                    }
                    .auvSegmentedStyle()
                    .accessibilityIdentifier("uma.settings.appearance.theme")
                    Picker(
                        localized("Look", "外观包"),
                        selection: Binding(
                            get: { model.look },
                            set: model.setLook
                        )
                    ) {
                        Text(localized("Standard", "标准")).tag(AUVLook.standard)
                        Text(localized("Wabi-sabi", "侘寂")).tag(AUVLook.wabiSabi)
                        Text("Brutalist").tag(AUVLook.brutalist)
                    }
                    .auvSegmentedStyle()
                    .accessibilityIdentifier("uma.settings.appearance.look")
                }
            case .refresh:
                settingsSection(
                    localized("Schedule", "定时"),
                    footer: localized(
                        "Covers every agent, Claude Code included: its exact figures sync at the same interval while Safari is open. If Safari is closed or stops responding, AUV asks before opening or restarting it.",
                        "涵盖所有智能体，包括 Claude Code：Safari 已打开时，其精确读数按同一间隔同步。Safari 未运行或停止响应时，AUV 会先询问，再打开或重启它。"
                    )
                ) {
                    Toggle(
                        localized("Refresh automatically", "自动刷新"),
                        isOn: Binding(
                            get: { model.automaticBackgroundRefresh },
                            set: model.setAutomaticBackgroundRefresh
                        )
                    )
                    .accessibilityIdentifier("uma.settings.general.background-refresh")
                    Picker(
                        localized("Every", "间隔"),
                        selection: Binding(
                            get: { model.backgroundRefreshInterval },
                            set: model.setBackgroundRefreshInterval
                        )
                    ) {
                        ForEach(UMABackgroundRefreshInterval.allCases) { interval in
                            Text(intervalTitle(interval)).tag(interval)
                        }
                    }
                    .disabled(!model.automaticBackgroundRefresh)
                    .accessibilityIdentifier("uma.settings.general.refresh-interval")
                }
                settingsSection(
                    localized("Also Refresh", "其他时机"),
                    footer: localized(
                        "Refresh All in the main window refreshes every agent at once, Claude's exact figures included.",
                        "主窗口的“全部刷新”会立即刷新所有智能体，包括 Claude 的精确读数。"
                    )
                ) {
                    Toggle(
                        localized("After the Mac wakes", "Mac 唤醒后"),
                        isOn: Binding(
                            get: { model.refreshOnWake },
                            set: model.setRefreshOnWake
                        )
                    )
                    .accessibilityIdentifier("uma.settings.general.refresh-on-wake")
                }
            case .agents:
                settingsSection(
                    localized("Order", "顺序"),
                    footer: localized(
                        "Drag to arrange. The order applies to the main window, Quick Panel, Desktop Assistant and menu bar. Each agent's own settings open from its page.",
                        "拖动以排列。顺序用于主窗口、快速面板、桌面助手和菜单栏。各智能体自己的设置在其页面中打开。"
                    )
                ) {
                    AgentOrderSettingsRows(store: store, language: model.language)
                }
                // Turning monitoring off removes an agent from every surface,
                // its own page with its switch included; it comes back here.
                if let coordinator = store.agentSettings, !model.turnedOffAgentIDs.isEmpty {
                    settingsSection(
                        localized("Turned Off", "已关闭"),
                        footer: localized(
                            "These agents are not monitored, so the main window, Quick Panel, Desktop Assistant and menu bar leave them out. Turn one on to bring it back.",
                            "这些智能体没有在监控，主窗口、快速面板、桌面助手和菜单栏都不显示它们。打开后会重新显示。"
                        )
                    ) {
                        TurnedOffAgentSettingsRows(
                            providerIDs: model.turnedOffAgentIDs,
                            coordinator: coordinator,
                            reconnection: agentReconnection,
                            language: model.language
                        )
                    }
                }
                // Web-only agents have no app on this Mac for Scan Agents to
                // find, so this switch is the only way to add one. Turning it
                // on is the person's consent to the Safari read.
                if let coordinator = store.agentSettings, let geminiSettings {
                    settingsSection(
                        localized("Web Usage", "网页用量"),
                        footer: localized(
                            "These agents have no app on this Mac, so Scan Agents cannot find them. Turning one on lets AUV open its usage page in Safari in a temporary tab, read only the usage, and close the tab. Its other settings then open from its page.",
                            "这些智能体在本机没有应用，“扫描智能体”找不到它们。打开后，AUV 会在 Safari 的临时标签页打开它的用量页，只读取用量，读完即关闭。其他设置随后在它的页面中打开。"
                        )
                    ) {
                        WebUsageAgentSettingsRows(
                            coordinator: coordinator,
                            gemini: geminiSettings,
                            language: model.language
                        )
                    }
                }
            case .menuBar:
                settingsSection(localized("Menu Bar Item", "菜单栏项目")) {
                    Toggle(
                        localized("Show remaining percentage", "显示剩余百分比"),
                        isOn: Binding(
                            get: { model.menuBarShowsRemaining },
                            set: model.setMenuBarShowsRemaining
                        )
                    )
                    .accessibilityIdentifier("uma.settings.appearance.menu-value")
                    MenuBarAgentSettingsPicker(store: store, language: model.language)
                        .disabled(!model.menuBarShowsRemaining)
                }
                // These only ever changed the Quick Panel, which opens from
                // the menu bar item, so they sit with it rather than under a
                // general Appearance heading.
                settingsSection(
                    localized("Quick Panel", "快速面板"),
                    footer: localized("Opens when you click AUV in the menu bar.", "点按菜单栏中的 AUV 时打开。")
                ) {
                    Toggle(
                        localized("Show connectivity indicators", "显示连接状态指示器"),
                        isOn: Binding(
                            get: { model.quickPanelShowsConnectivity },
                            set: model.setQuickPanelShowsConnectivity
                        )
                    )
                    .accessibilityIdentifier("uma.settings.appearance.quick-connectivity")
                    Toggle(
                        localized("Show remaining-percentage rails", "显示剩余百分比用量条"),
                        isOn: Binding(
                            get: { model.quickPanelShowsRemainingRails },
                            set: model.setQuickPanelShowsRemainingRails
                        )
                    )
                    .accessibilityIdentifier("uma.settings.appearance.quick-rails")
                }
            case .desktopWizard:
                settingsSection(localized("Display", "显示")) {
                    Toggle(
                        localized("Show Desktop Assistant", "显示桌面助手"),
                        isOn: Binding(
                            get: { model.assistantEnabled },
                            set: model.setAssistantEnabled
                        )
                    )
                    Toggle(
                        localized("Keep above other windows", "始终置于其他窗口上方"),
                        isOn: Binding(
                            get: { model.assistantAlwaysOnTop },
                            set: model.setAssistantAlwaysOnTop
                        )
                    )
                    .disabled(!model.assistantEnabled)
                }
                settingsSection(localized("Content", "内容")) {
                    Picker(
                        localized("Density", "密度"),
                        selection: Binding(
                            get: { model.assistantDensity },
                            set: model.setAssistantDensity
                        )
                    ) {
                        Text(localized("Automatic", "自动")).tag(DesktopAssistantDensity.automatic)
                        Text(localized("Regular", "常规")).tag(DesktopAssistantDensity.regular)
                        Text(localized("Minimalist", "极简")).tag(DesktopAssistantDensity.minimalist)
                    }
                    .auvSegmentedStyle()
                    Toggle(
                        localized("Show status indicator", "显示状态指示器"),
                        isOn: Binding(
                            get: { model.assistantShowsStatusIndicator },
                            set: model.setAssistantShowsStatusIndicator
                        )
                    )
                    .accessibilityIdentifier("uma.settings.wizard.status-indicator")
                    Toggle(
                        localized("Show remaining-percentage rail", "显示剩余百分比用量条"),
                        isOn: Binding(
                            get: { model.assistantShowsPercentageRail },
                            set: model.setAssistantShowsPercentageRail
                        )
                    )
                    .accessibilityIdentifier("uma.settings.wizard.percentage-rail")
                }
                settingsSection(localized("Position", "位置")) {
                    LabeledContent(localized("Moved off screen or lost?", "移出屏幕或找不到了？")) {
                        Button(
                            localized("Reset Position", "重置位置"),
                            action: model.resetAssistantPosition
                        )
                        .accessibilityIdentifier("uma.settings.wizard.reset-position")
                    }
                }
            case .privacy:
                settingsSection(localized("What AUV Keeps", "AUV 保留的内容")) {
                    settingFact(
                        localized("Usage data", "用量数据"),
                        localized("Allowlisted usage figures only", "仅限允许范围内的用量数据")
                    )
                    settingFact(
                        localized("Credentials", "凭据"),
                        localized("Passwords, tokens, cookies and conversations are never kept", "从不保留密码、令牌、Cookie 或对话")
                    )
                    settingFact(
                        localized("Old values", "旧数据"),
                        localized("Stale and unsupported values stay labelled", "过期和不支持的值会明确标注")
                    )
                }
                settingsSection(localized("Data", "数据")) {
                    // Side by side these two need more width than the default
                    // Settings window gives English titles, so they stack when
                    // they would not fit at full length instead of truncating.
                    ViewThatFits(in: .horizontal) {
                        HStack { privacyDataActions }
                        VStack(alignment: .leading, spacing: 8) { privacyDataActions }
                    }
                    if let status = model.dataActionStatus {
                        Text(status)
                            .font(AUVType.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("uma.settings.privacy.action-status")
                    }
                }
            }
    }

    @ViewBuilder private var privacyDataActions: some View {
        Button(
            localized("Clear Retained Local Data", "清除保留的本地数据"),
            action: model.clearRetainedUsageData
        )
        .accessibilityIdentifier("uma.settings.privacy.clear-retained-data")
        Button(
            localized("Export Sanitized Diagnostics…", "导出已净化诊断信息…"),
            action: model.exportSanitizedDiagnostics
        )
        .accessibilityIdentifier("uma.settings.privacy.export-diagnostics")
    }

    private func settingsSection<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsPaneSection(title: title, footer: footer, content: content)
    }

    private func settingFact(_ title: String, _ detail: String) -> some View {
        LabeledContent(title) {
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func intervalTitle(_ interval: UMABackgroundRefreshInterval) -> String {
        switch interval {
        case .fiveMinutes: localized("5 minutes", "5 分钟")
        case .tenMinutes: localized("10 minutes", "10 分钟")
        case .fifteenMinutes: localized("15 minutes", "15 分钟")
        case .thirtyMinutes: localized("30 minutes", "30 分钟")
        case .sixtyMinutes: localized("60 minutes", "60 分钟")
        }
    }

    private func symbol(_ pane: GlobalSettingsPane) -> String {
        switch pane {
        case .general: "gearshape.fill"
        case .refresh: "arrow.clockwise"
        case .agents: "square.stack.3d.up.fill"
        case .menuBar: "menubar.rectangle"
        case .desktopWizard: "capsule.fill"
        case .privacy: "hand.raised.fill"
        }
    }

    private func tint(_ pane: GlobalSettingsPane) -> Color {
        switch pane {
        case .general: Color(nsColor: .systemGray)
        case .refresh: Color(nsColor: .systemBlue)
        case .agents: Color(nsColor: .systemPurple)
        case .menuBar: Color(nsColor: .systemTeal)
        case .desktopWizard: Color(nsColor: .systemOrange)
        case .privacy: Color(nsColor: .systemIndigo)
        }
    }

    private func paneTitle(_ pane: GlobalSettingsPane) -> String {
        switch pane {
        case .general: localized("General", "通用")
        case .refresh: localized("Refresh", "刷新")
        case .agents: localized("Agents", "智能体")
        case .menuBar: localized("Menu Bar", "菜单栏")
        case .desktopWizard: localized("Desktop Assistant", "桌面助手")
        case .privacy: localized("Privacy & Data", "隐私与数据")
        }
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        model.language == .simplifiedChinese ? chinese : english
    }
}

/// The Settings sidebar in a pack. Wabi-sabi: a thin ink glyph, a short ink
/// mark beside the chosen pane. Brutalist: rows on rules, the chosen one
/// inverted, glyphs in ink.
private struct GlobalSettingsLookSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: GlobalSettingsPane
    let title: (GlobalSettingsPane) -> String
    let symbol: (GlobalSettingsPane) -> String

    var body: some View {
        let isDark = colorScheme == .dark
        let look = AUVLook.current
        let ink = AUVLookPalette.ink(look, isDark: isDark)
        let canvas = AUVLookPalette.canvas(look, isDark: isDark) ?? .white
        VStack(alignment: .leading, spacing: look == .wabiSabi ? 4 : 0) {
            ForEach(GlobalSettingsPane.allCases, id: \.self) { pane in
                let chosen = pane == selection
                let inverted = look == .brutalist && chosen
                Button { selection = pane } label: {
                    HStack(spacing: 10) {
                        if look == .wabiSabi {
                            Capsule().fill(ink.opacity(chosen ? 0.7 : 0)).frame(width: 2, height: 14)
                        }
                        Image(systemName: symbol(pane).replacingOccurrences(of: ".fill", with: ""))
                            .font(.system(size: 13, weight: look == .wabiSabi ? .ultraLight : .bold))
                            .frame(width: 18)
                        Text(title(pane))
                            .font(AUVLookType.text(13, strong: inverted))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(inverted ? canvas : ink.opacity(look == .wabiSabi ? (chosen ? 0.92 : 0.6) : 1))
                    .padding(.horizontal, look == .wabiSabi ? 6 : 12)
                    .frame(height: 32)
                    .background(inverted ? ink : Color.clear,
                                in: RoundedRectangle(cornerRadius: AUVFormwork.control, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .padding(.horizontal, look == .wabiSabi ? 10 : 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(UMAVisualStyle.canvas)
    }
}

/// A pane's symbol on a small coloured tile, as System Settings sets them.
private struct GlobalSettingsPaneIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}
