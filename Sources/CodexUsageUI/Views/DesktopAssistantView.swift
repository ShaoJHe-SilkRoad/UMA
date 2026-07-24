import AppKit
import SwiftUI

public enum DesktopAssistantMetrics {
    public static let regularWidth: CGFloat = 210
    public static let regularHeight: CGFloat = 60
    public static let minimalistWidth: CGFloat = 58.333333
    public static let minimalistHeight: CGFloat = 30
    public static let minimalistCornerRadius: CGFloat = 15
    public static let minimalistConnectionDiameter: CGFloat = 18
    public static let minimalistGap: CGFloat = 3
    public static let minimalistReservedWindowWidth: CGFloat = 0
    public static let percentageFontSize: CGFloat = 13
    public static let tintFeatherWidth: CGFloat = 6

    public static func size(for density: DesktopAssistantResolvedDensity) -> CGSize {
        switch density {
        case .regular:
            CGSize(width: regularWidth, height: regularHeight)
        case .minimalist:
            CGSize(width: minimalistWidth, height: minimalistHeight)
        }
    }
}

public enum DesktopAssistantVisibleField: Equatable, Sendable {
    case providerConnectionMark
    case providerName
    case planTier
    case selectedWindow
    case percentage
    case reset
}

public enum DesktopAssistantContentContract {
    public static func visibleFields(
        for density: DesktopAssistantResolvedDensity
    ) -> [DesktopAssistantVisibleField] {
        switch density {
        case .regular:
            [
                .providerConnectionMark,
                .providerName,
                .planTier,
                .selectedWindow,
                .percentage,
                .reset
            ]
        case .minimalist:
            [.providerConnectionMark, .percentage]
        }
    }
}

public enum DesktopAssistantConnectionState: String, Equatable, Sendable {
    case connected
    case reconnecting
    case disconnected
    case unavailable
    case failed
}

public enum DesktopAssistantUsageValue: Equatable, Sendable {
    case finite(Int)
    case unlimited
    case unavailable

    public var finitePercent: Int? {
        guard case .finite(let value) = self else { return nil }
        return min(100, max(0, value))
    }

    public var displayText: String {
        switch self {
        case .finite(let value):
            "\(min(100, max(0, value)))%"
        case .unlimited:
            "∞"
        case .unavailable:
            "—"
        }
    }
}

public enum DesktopAssistantUsageSeverity: String, Equatable, Sendable {
    case normal
    case warning
    case critical
    case neutral
}

/// Immutable, transport-free input for the Assistant. The host adapts the
/// shared UsageStore presentation model into this value; the Assistant never
/// receives a connector, timer, provider process, refresh action, or cache.
public struct DesktopAssistantCard: Equatable, Sendable, Identifiable {
    public let id: String
    public let providerName: String
    public let planLabel: String?
    public let connectionState: DesktopAssistantConnectionState
    public let selectedWindowShortLabel: String
    public let selectedWindowAccessibilityLabel: String
    public let resetText: String
    public let usageValue: DesktopAssistantUsageValue
    public let tintFraction: Double?
    public let severity: DesktopAssistantUsageSeverity
    public let isStale: Bool
    public let accessibilityLabel: String

    public init(
        id: String,
        providerName: String,
        planLabel: String? = nil,
        connectionState: DesktopAssistantConnectionState,
        selectedWindowShortLabel: String,
        selectedWindowAccessibilityLabel: String,
        resetText: String = "",
        usageValue: DesktopAssistantUsageValue,
        tintFraction: Double? = nil,
        severity: DesktopAssistantUsageSeverity,
        isStale: Bool,
        language: AppLanguage = .english,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.providerName = providerName
        self.planLabel = planLabel
        self.connectionState = connectionState
        self.selectedWindowShortLabel = selectedWindowShortLabel
        self.selectedWindowAccessibilityLabel = selectedWindowAccessibilityLabel
        self.resetText = resetText
        self.usageValue = usageValue
        self.tintFraction = tintFraction.map { min(1, max(0, $0)) }
            ?? usageValue.finitePercent.map { Double($0) / 100 }
        self.severity = severity
        self.isStale = isStale
        self.accessibilityLabel = accessibilityLabel ?? Self.makeAccessibilityLabel(
            providerName: providerName,
            connectionState: connectionState,
            selectedWindowAccessibilityLabel: selectedWindowAccessibilityLabel,
            usageValue: usageValue,
            isStale: isStale,
            language: language
        )
    }

    public var toolTip: String { accessibilityLabel }

    public init(
        shared card: SharedUsageCardPresentation,
        language: AppLanguage = .english
    ) {
        let connectionState: DesktopAssistantConnectionState = switch card.connectionStatus {
        case .connected:
            .connected
        case .transitional:
            .reconnecting
        case .authenticationRequired, .disconnected:
            .disconnected
        case .stale:
            .reconnecting
        case .unavailable:
            .unavailable
        case .failed:
            .failed
        }
        let usageValue: DesktopAssistantUsageValue = switch card.remaining {
        case .finite:
            .finite(card.remaining.displayPercent ?? 0)
        case .unlimited:
            .unlimited
        case .unavailable:
            .unavailable
        }
        let severity: DesktopAssistantUsageSeverity = switch card.severity {
        case .normal:
            .normal
        case .warning:
            .warning
        case .critical:
            .critical
        case .neutral:
            .neutral
        }
        self.init(
            id: card.id,
            providerName: card.providerName,
            planLabel: card.planLabel,
            connectionState: connectionState,
            selectedWindowShortLabel: card.selectedWindow?.compactLabel ?? "",
            selectedWindowAccessibilityLabel: card.selectedWindow?.accessibilityLabel
                ?? "usage window unavailable",
            resetText: card.selectedWindow?.resetText ?? "",
            usageValue: usageValue,
            tintFraction: card.remaining.tintFraction,
            severity: severity,
            isStale: card.freshness == .stale || card.isRetainingLastValidValue,
            language: language
        )
    }

    private static func makeAccessibilityLabel(
        providerName: String,
        connectionState: DesktopAssistantConnectionState,
        selectedWindowAccessibilityLabel: String,
        usageValue: DesktopAssistantUsageValue,
        isStale: Bool,
        language: AppLanguage
    ) -> String {
        let status: String = switch (language, connectionState) {
        case (.english, .connected): "connected"
        case (.english, .reconnecting): "reconnecting"
        case (.english, .disconnected): "disconnected"
        case (.english, .unavailable): "unavailable"
        case (.english, .failed): "failed"
        case (.simplifiedChinese, .connected): "已连接"
        case (.simplifiedChinese, .reconnecting): "正在重新连接"
        case (.simplifiedChinese, .disconnected): "已断开"
        case (.simplifiedChinese, .unavailable): "不可用"
        case (.simplifiedChinese, .failed): "连接失败"
        }
        let usage: String = switch (language, usageValue) {
        case let (.english, .finite(value)):
            "\(min(100, max(0, value))) percent remaining"
        case (.english, .unlimited): "unlimited"
        case (.english, .unavailable): "usage unavailable"
        case let (.simplifiedChinese, .finite(value)):
            "剩余 \(min(100, max(0, value)))%"
        case (.simplifiedChinese, .unlimited): "无限额度"
        case (.simplifiedChinese, .unavailable): "额度不可用"
        }
        let freshness: String
        switch (language, isStale) {
        case (.english, true): freshness = ", stale"
        case (.simplifiedChinese, true): freshness = "，数据已过期"
        default: freshness = ""
        }
        if language == .simplifiedChinese {
            return "\(providerName)，\(status)，\(selectedWindowAccessibilityLabel)，\(usage)\(freshness)。"
        }
        return "\(providerName), \(status), \(selectedWindowAccessibilityLabel), \(usage)\(freshness)."
    }
}

public enum DesktopAssistantTintGeometry {
    public struct Stops: Equatable, Sendable {
        public let solidEnd: Double
        public let midpoint: Double
        public let clearStart: Double
    }

    public static func stops(
        remainingFraction: Double,
        width: CGFloat,
        featherWidth: CGFloat = DesktopAssistantMetrics.tintFeatherWidth
    ) -> Stops {
        let fraction = min(1, max(0, remainingFraction))
        guard width > 0, featherWidth > 0 else {
            return Stops(solidEnd: fraction, midpoint: fraction, clearStart: fraction)
        }
        let halfFeather = Double(featherWidth / width) / 2
        return Stops(
            solidEnd: max(0, fraction - halfFeather),
            midpoint: fraction,
            clearStart: min(1, fraction + halfFeather)
        )
    }

    public static func midpointX(remainingFraction: Double, width: CGFloat) -> CGFloat {
        CGFloat(min(1, max(0, remainingFraction))) * width
    }
}

public enum DesktopAssistantTintOpacity {
    public static let light = 0.3042
    public static let dark = 0.24336
    public static let reducedTransparencyLight = 0.36504
    public static let reducedTransparencyDark = 0.32448
    public static let increasedContrastLight = 0.48672
    public static let increasedContrastDark = 0.36504

    public static func value(
        isDark: Bool,
        reduceTransparency: Bool,
        increaseContrast: Bool
    ) -> Double {
        if increaseContrast {
            return isDark ? increasedContrastDark : increasedContrastLight
        }
        if reduceTransparency {
            return isDark ? reducedTransparencyDark : reducedTransparencyLight
        }
        return isDark ? dark : light
    }
}

public struct DesktopAssistantAppearanceOverride: Equatable, Sendable {
    public let reduceTransparency: Bool
    public let increaseContrast: Bool

    public init(reduceTransparency: Bool, increaseContrast: Bool) {
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}

public struct DesktopAssistantView: View {
    public let cards: [DesktopAssistantCard]
    public let density: DesktopAssistantResolvedDensity
    public let appearanceOverride: DesktopAssistantAppearanceOverride?

    public init(
        cards: [DesktopAssistantCard],
        density: DesktopAssistantResolvedDensity,
        appearanceOverride: DesktopAssistantAppearanceOverride? = nil
    ) {
        self.cards = cards
        self.density = density
        self.appearanceOverride = appearanceOverride
    }

    public var body: some View {
        VStack(spacing: 4) {
            ForEach(cards) { card in
                DesktopAssistantCardView(
                    card: card,
                    density: density,
                    appearanceOverride: appearanceOverride
                )
            }
        }
    }
}

private struct DesktopAssistantCardView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let card: DesktopAssistantCard
    let density: DesktopAssistantResolvedDensity
    let appearanceOverride: DesktopAssistantAppearanceOverride?

    private var size: CGSize { DesktopAssistantMetrics.size(for: density) }
    private var radius: CGFloat {
        density == .minimalist ? DesktopAssistantMetrics.minimalistCornerRadius : size.height / 2
    }
    private var fraction: Double? { card.tintFraction }
    private var isDark: Bool { colorScheme == .dark }
    private var usesReduceTransparency: Bool {
        appearanceOverride?.reduceTransparency ?? reduceTransparency
    }
    private var hasIncreasedContrast: Bool {
        appearanceOverride?.increaseContrast ?? (colorSchemeContrast == .increased)
    }

    var body: some View {
        Group {
            switch density {
            case .regular:
                regularContent
            case .minimalist:
                minimalistContent
            }
        }
        .frame(width: size.width, height: size.height)
        .background { glassBackground }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    Color.primary.opacity(hasIncreasedContrast ? 0.56 : 0.22),
                    lineWidth: hasIncreasedContrast ? 1 : 0.75
                )
                .allowsHitTesting(false)
        }
        .opacity(card.isStale ? 0.78 : 1)
        .help(card.toolTip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(card.accessibilityLabel))
    }

    private var minimalistContent: some View {
        HStack(spacing: DesktopAssistantMetrics.minimalistGap) {
            connectionMark(diameter: DesktopAssistantMetrics.minimalistConnectionDiameter)
            percentageLabel
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var regularContent: some View {
        HStack(spacing: 8) {
            connectionMark(diameter: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(card.providerName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    if let planLabel = card.planLabel, !planLabel.isEmpty {
                        Text(planLabel)
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Text(
                    card.resetText.isEmpty
                        ? card.selectedWindowShortLabel
                        : "\(card.selectedWindowShortLabel) · \(card.resetText)"
                )
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            percentageLabel
        }
        .padding(.horizontal, 12)
    }

    private var percentageLabel: some View {
        Text(card.usageValue.displayText)
            .font(.system(
                size: DesktopAssistantMetrics.percentageFontSize,
                weight: .medium,
                design: .rounded
            ))
            .monospacedDigit()
            .foregroundStyle(percentageColor)
            .lineLimit(1)
            .fixedSize()
    }

    private func connectionMark(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(connectionColor, lineWidth: 1.5)
            Text("C")
                .font(.system(size: diameter * 0.56, weight: .semibold, design: .rounded))
                .foregroundStyle(connectionColor)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glassBackground: some View {
        ZStack {
            if usesReduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
            tintLayer
        }
    }

    @ViewBuilder
    private var tintLayer: some View {
        if let fraction, fraction > 0 {
            GeometryReader { proxy in
                let stops = DesktopAssistantTintGeometry.stops(
                    remainingFraction: fraction,
                    width: proxy.size.width
                )
                let tint = tintColor.opacity(
                    DesktopAssistantTintOpacity.value(
                        isDark: isDark,
                        reduceTransparency: usesReduceTransparency,
                        increaseContrast: hasIncreasedContrast
                    )
                )
                if fraction >= 1 {
                    tint
                } else {
                    LinearGradient(
                        stops: [
                            .init(color: tint, location: 0),
                            .init(color: tint, location: stops.solidEnd),
                            .init(color: tint.opacity(0.5), location: stops.midpoint),
                            .init(color: tint.opacity(0), location: stops.clearStart),
                            .init(color: tint.opacity(0), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
    }

    private var connectionColor: Color {
        switch card.connectionState {
        case .connected:
            .green
        case .reconnecting:
            .orange
        case .disconnected, .unavailable:
            .secondary
        case .failed:
            .red
        }
    }

    private var tintColor: Color {
        switch card.severity {
        case .normal:
            .green
        case .warning, .critical:
            .red
        case .neutral:
            .clear
        }
    }

    private var percentageColor: Color {
        switch card.severity {
        case .normal, .neutral:
            .primary
        case .warning, .critical:
            isDark
                ? Color(red: 1, green: 0.58, blue: 0.58)
                : Color(red: 0.55, green: 0.08, blue: 0.10)
        }
    }
}
