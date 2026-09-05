import AppKit
import SwiftUI

public enum DesktopAssistantMetrics {
    public static let regularWidth: CGFloat = 210
    public static let regularHeight: CGFloat = 60
    public static var minimalistWidth: CGFloat {
        DesktopAssistantMinimalistTypography.metrics().size.width
    }
    public static let minimalistHeight: CGFloat = 30
    public static let minimalistCornerRadius: CGFloat = 15
    public static let minimalistConnectionDiameter: CGFloat = 18
    public static let minimalistGap: CGFloat = 3
    public static let minimalistReservedWindowWidth: CGFloat = 0
    public static let percentageFontSize: CGFloat = 13
    public static let tintFeatherWidth: CGFloat = 6
    public static let rowSpacing: CGFloat = 4

    public static func size(
        for density: DesktopAssistantResolvedDensity,
        valueTexts: [String] = []
    ) -> CGSize {
        switch density {
        case .regular:
            CGSize(width: regularWidth, height: regularHeight)
        case .minimalist:
            DesktopAssistantMinimalistTypography.metrics(valueTexts: valueTexts).size
        }
    }

    public static func stackSize(
        for density: DesktopAssistantResolvedDensity,
        rowCount: Int,
        valueTexts: [String] = []
    ) -> CGSize {
        let row = size(for: density, valueTexts: valueTexts)
        let count = max(0, rowCount)
        let gaps = max(0, count - 1)
        return CGSize(
            width: row.width,
            height: row.height * CGFloat(count) + rowSpacing * CGFloat(gaps)
        )
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
    case stale
    case disconnected
    case unavailable
    case failed
}

public enum DesktopAssistantUsageValue: Equatable, Sendable {
    case finite(Int)
    case estimated(Int)
    case credits(String)
    case unlimited
    case unavailable

    public var finitePercent: Int? {
        switch self {
        case let .finite(value), let .estimated(value):
            return min(100, max(0, value))
        default:
            return nil
        }
    }

    public var displayText: String {
        switch self {
        case .finite(let value):
            "\(min(100, max(0, value)))%"
        case .estimated(let value):
            "≈\(min(100, max(0, value)))%"
        case .credits(let value):
            value
        case .unlimited:
            "∞"
        case .unavailable:
            "—"
        }
    }
}

public enum DesktopAssistantSourceMark: Equatable, Sendable {
    case connection
    case accountWeb
    case manual
}

public enum DesktopAssistantFreshnessState: String, Equatable, Sendable {
    case fresh
    case cached
    case stale
    case waiting
    case failed
    case unavailable
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
    public let sourceMark: DesktopAssistantSourceMark
    public let providerMarkText: String
    public let freshnessState: DesktopAssistantFreshnessState
    public let sourceDescription: String?
    public let observationAgeText: String?
    public let selectedWindowShortLabel: String
    public let selectedWindowAccessibilityLabel: String
    public let selectedWindowResetAt: Date?
    public let resetText: String
    public let detailText: String?
    public let usageValue: DesktopAssistantUsageValue
    public let regularUsageText: String?
    public let tintFraction: Double?
    public let remainingPercent: Double?
    public let availableCredits: Decimal?
    public let severity: DesktopAssistantUsageSeverity
    public let isStale: Bool
    public let language: AppLanguage
    public let accessibilityLabel: String

    public init(
        id: String,
        providerName: String,
        planLabel: String? = nil,
        connectionState: DesktopAssistantConnectionState,
        sourceMark: DesktopAssistantSourceMark = .connection,
        providerMarkText: String? = nil,
        freshnessState: DesktopAssistantFreshnessState? = nil,
        sourceDescription: String? = nil,
        observationAgeText: String? = nil,
        selectedWindowShortLabel: String,
        selectedWindowAccessibilityLabel: String,
        selectedWindowResetAt: Date? = nil,
        resetText: String = "",
        detailText: String? = nil,
        usageValue: DesktopAssistantUsageValue,
        regularUsageText: String? = nil,
        tintFraction: Double? = nil,
        remainingPercent: Double? = nil,
        availableCredits: Decimal? = nil,
        severity: DesktopAssistantUsageSeverity,
        isStale: Bool,
        language: AppLanguage = .english,
        accessibilityLabel: String? = nil
    ) {
        self.id = id
        self.providerName = providerName
        self.planLabel = planLabel
        self.connectionState = connectionState
        self.sourceMark = sourceMark
        self.providerMarkText = providerMarkText
            ?? Self.providerMarkText(for: providerName)
        self.freshnessState = freshnessState
            ?? Self.inferredFreshnessState(
                connectionState: connectionState,
                usageValue: usageValue,
                isStale: isStale
            )
        self.sourceDescription = sourceDescription
        self.observationAgeText = observationAgeText
        self.selectedWindowShortLabel = selectedWindowShortLabel
        self.selectedWindowAccessibilityLabel = selectedWindowAccessibilityLabel
        self.selectedWindowResetAt = selectedWindowResetAt
        self.resetText = resetText
        self.detailText = detailText
        self.usageValue = usageValue
        self.regularUsageText = regularUsageText
        self.availableCredits = availableCredits
        let representedPercent: Double? = switch usageValue {
        case let .finite(value), let .estimated(value):
            remainingPercent ?? tintFraction.map { $0 * 100 } ?? Double(value)
        case .credits, .unlimited, .unavailable:
            nil
        }
        self.remainingPercent = representedPercent.flatMap {
            $0.isFinite && (0...100).contains($0) ? $0 : nil
        }
        self.tintFraction = self.remainingPercent.map { $0 / 100 }
        self.severity = severity
        self.isStale = isStale
        self.language = language
        self.accessibilityLabel = accessibilityLabel ?? Self.makeAccessibilityLabel(
            providerName: providerName,
            connectionState: connectionState,
            selectedWindowAccessibilityLabel: selectedWindowAccessibilityLabel,
            usageValue: usageValue,
            freshnessState: self.freshnessState,
            resetText: resetText,
            sourceDescription: sourceDescription,
            observationAgeText: observationAgeText,
            language: language
        )
    }

    public var toolTip: String { accessibilityLabel }

    public func usageText(for density: DesktopAssistantResolvedDensity) -> String {
        if density == .regular, let regularUsageText {
            return regularUsageText
        }
        return usageValue.displayText
    }

    public init(
        shared card: SharedUsageCardPresentation,
        language: AppLanguage = .english,
        now: Date = Date()
    ) {
        let connectionState: DesktopAssistantConnectionState = if card.freshness == .stale {
            .stale
        } else {
            switch card.connectionStatus {
            case .connected:
                .connected
            case .transitional:
                .reconnecting
            case .authenticationRequired, .disconnected:
                .disconnected
            case .stale:
                .stale
            case .unavailable:
                .unavailable
            case .failed:
                .failed
            }
        }
        let percentageUsageValue: DesktopAssistantUsageValue = switch card.remaining {
        case .finite:
            card.isEstimated == true
                ? .estimated(card.remaining.displayPercent ?? 0)
                : .finite(card.remaining.displayPercent ?? 0)
        case .unlimited:
            .unlimited
        case .unavailable:
            .unavailable
        }
        let percentageSeverity: DesktopAssistantUsageSeverity = switch card.severity {
        case .normal:
            .normal
        case .warning:
            .warning
        case .critical:
            .critical
        case .neutral:
            .neutral
        }
        let freshnessState = Self.freshnessState(
            freshness: card.freshness,
            connectionState: connectionState,
            usageValue: percentageUsageValue,
            isRetainingLastValidValue: card.isRetainingLastValidValue
        )
        let observationAgeText = card.sourceDescription.map { _ in
            Self.observationAgeText(
                capturedAt: card.capturedAt,
                now: now,
                language: language
            )
        }
        let isManualAvailability = card.availabilityLifecycle != nil
            || card.availability?.sourceState == .manualConfirmed
        if isManualAvailability {
            let availability = card.availability
            let availabilitySeverity: DesktopAssistantUsageSeverity = switch availability?.severity {
            case .available:
                .normal
            case .warning:
                .warning
            case .critical, .exhausted:
                .critical
            case .neutral, .invalid, nil:
                .neutral
            }
            let presentation = WorkBuddyMainPanelPresentation.make(
                card: card,
                language: language
            )
            let hasManualSnapshot =
                availability?.sourceState == .manualConfirmed
            self.init(
                id: card.id,
                providerName: card.providerName,
                planLabel: card.planLabel,
                connectionState: connectionState,
                sourceMark: .manual,
                freshnessState: freshnessState,
                selectedWindowShortLabel: "",
                selectedWindowAccessibilityLabel: "",
                detailText: hasManualSnapshot
                    ? language.workBuddyManualSnapshot
                    : presentation?.severityText,
                usageValue: availability?.displayUnit == .credits
                    ? .credits(availability?.compactText ?? "—")
                    : .unavailable,
                regularUsageText: availability?.exactCreditValue.map {
                    CreditFormatter.exact($0, language: language)
                },
                availableCredits: availability?.exactCreditValue,
                severity: availabilitySeverity,
                isStale: card.isRetainingLastValidValue,
                language: language,
                accessibilityLabel: presentation?.accessibilityLabel
                    ?? card.tooltipText
            )
            return
        }
        if let availability = card.availability,
           availability.displayUnit == .credits {
            let availabilitySeverity: DesktopAssistantUsageSeverity = switch availability.severity {
            case .available:
                .normal
            case .warning:
                .warning
            case .critical, .exhausted:
                .critical
            case .neutral, .invalid:
                .neutral
            }
            self.init(
                id: card.id,
                providerName: card.providerName,
                planLabel: card.planLabel,
                connectionState: connectionState,
                sourceMark: availability.sourceState == .authenticatedAccountWeb
                    ? .accountWeb
                    : .connection,
                freshnessState: freshnessState,
                selectedWindowShortLabel: "",
                selectedWindowAccessibilityLabel: "",
                detailText: availability.sourceState == .authenticatedAccountWeb
                    ? language.workBuddyAccountWebSource
                    : nil,
                usageValue: .credits(availability.compactText),
                regularUsageText: availability.exactCreditValue.map {
                    availability.sourceState == .authenticatedAccountWeb
                        ? CreditFormatter.exactTwoDecimal(
                            $0,
                            language: language
                        )
                        : CreditFormatter.exact($0, language: language)
                },
                availableCredits: availability.exactCreditValue,
                severity: availabilitySeverity,
                isStale: card.freshness == .stale || card.isRetainingLastValidValue,
                language: language,
                accessibilityLabel: Self.makeStructuredCreditAccessibilityLabel(
                    providerName: card.providerName,
                    connectionState: connectionState,
                    availability: availability,
                    isStale: card.freshness == .stale || card.isRetainingLastValidValue,
                    language: language
                )
            )
            return
        }

        self.init(
            id: card.id,
            providerName: card.providerName,
            planLabel: card.planLabel,
            connectionState: connectionState,
            freshnessState: freshnessState,
            sourceDescription: card.sourceDescription,
            observationAgeText: observationAgeText,
            selectedWindowShortLabel: card.selectedWindow?.compactLabel ?? "",
            selectedWindowAccessibilityLabel: card.selectedWindow?.accessibilityLabel
                ?? "usage window unavailable",
            selectedWindowResetAt: card.selectedWindow?.resetsAt,
            resetText: card.selectedWindow?.resetText ?? "",
            detailText: Self.percentageDetailText(
                card: card,
                freshnessState: freshnessState,
                language: language
            ),
            usageValue: percentageUsageValue,
            remainingPercent: {
                if case let .finite(value) = card.remaining { return value }
                return nil
            }(),
            severity: percentageSeverity,
            isStale: card.freshness == .stale,
            language: language
        )
    }

    private static func makeAccessibilityLabel(
        providerName: String,
        connectionState: DesktopAssistantConnectionState,
        selectedWindowAccessibilityLabel: String,
        usageValue: DesktopAssistantUsageValue,
        freshnessState: DesktopAssistantFreshnessState,
        resetText: String,
        sourceDescription: String?,
        observationAgeText: String?,
        language: AppLanguage
    ) -> String {
        let status: String = switch (language, connectionState) {
        case (.english, .connected): "connected"
        case (.english, .reconnecting): "reconnecting"
        case (.english, .stale): "stale value retained"
        case (.english, .disconnected): "disconnected"
        case (.english, .unavailable): "unavailable"
        case (.english, .failed): "failed"
        case (.simplifiedChinese, .connected): "已连接"
        case (.simplifiedChinese, .reconnecting): "正在重新连接"
        case (.simplifiedChinese, .stale): "保留较早值"
        case (.simplifiedChinese, .disconnected): "已断开"
        case (.simplifiedChinese, .unavailable): "不可用"
        case (.simplifiedChinese, .failed): "连接失败"
        }
        let usage: String = switch (language, usageValue) {
        case let (.english, .finite(value)):
            "\(min(100, max(0, value))) percent remaining"
        case let (.english, .estimated(value)):
            "approximately \(min(100, max(0, value))) percent remaining"
        case let (.english, .credits(value)):
            "\(value) Credits remaining"
        case (.english, .unlimited): "unlimited"
        case (.english, .unavailable): "usage unavailable"
        case let (.simplifiedChinese, .finite(value)):
            "剩余 \(min(100, max(0, value)))%"
        case let (.simplifiedChinese, .estimated(value)):
            "预计剩余 \(min(100, max(0, value)))%"
        case let (.simplifiedChinese, .credits(value)):
            "剩余 \(value) Credits"
        case (.simplifiedChinese, .unlimited): "无限额度"
        case (.simplifiedChinese, .unavailable): "额度不可用"
        }
        let freshness = if sourceDescription == nil
            && observationAgeText == nil
            && freshnessState == .stale {
            language == .english ? "stale" : "已过期"
        } else if sourceDescription != nil
            || observationAgeText != nil {
            localizedFreshness(
                freshnessState,
                language: language
            )
        } else {
            ""
        }
        let components: [String] = [
            providerName,
            status,
            freshness,
            selectedWindowAccessibilityLabel,
            usage,
            resetText,
            sourceDescription,
            observationAgeText,
        ].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        if language == .simplifiedChinese {
            return components.joined(separator: "，") + "。"
        }
        return components.joined(separator: ", ") + "."
    }

    private static func providerMarkText(for providerName: String) -> String {
        let words = providerName.split(whereSeparator: \.isWhitespace)
        if words.count > 1 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined()
        }
        return words.first?.first.map(String.init) ?? "?"
    }

    private static func inferredFreshnessState(
        connectionState: DesktopAssistantConnectionState,
        usageValue: DesktopAssistantUsageValue,
        isStale: Bool
    ) -> DesktopAssistantFreshnessState {
        if connectionState == .failed { return .failed }
        if connectionState == .stale { return .stale }
        if isStale { return .stale }
        if connectionState == .reconnecting,
           usageValue == .unavailable {
            return .waiting
        }
        if connectionState == .unavailable
            || connectionState == .disconnected
            || usageValue == .unavailable {
            return .unavailable
        }
        return .fresh
    }

    private static func freshnessState(
        freshness: SharedUsageFreshness,
        connectionState: DesktopAssistantConnectionState,
        usageValue: DesktopAssistantUsageValue,
        isRetainingLastValidValue: Bool
    ) -> DesktopAssistantFreshnessState {
        if connectionState == .failed { return .failed }
        if connectionState == .stale { return .stale }
        if freshness == .cached { return .cached }
        if freshness == .stale || isRetainingLastValidValue { return .stale }
        if connectionState == .reconnecting,
           usageValue == .unavailable {
            return .waiting
        }
        if freshness == .unavailable || usageValue == .unavailable {
            return .unavailable
        }
        return .fresh
    }

    private static func localizedFreshness(
        _ state: DesktopAssistantFreshnessState,
        language: AppLanguage
    ) -> String {
        switch (language, state) {
        case (.english, .fresh): "Fresh"
        case (.english, .cached): "Cached"
        case (.english, .stale): "Stale"
        case (.english, .waiting): "Waiting"
        case (.english, .failed): "Failed"
        case (.english, .unavailable): "Unavailable"
        case (.simplifiedChinese, .fresh): "新鲜"
        case (.simplifiedChinese, .cached): "已缓存"
        case (.simplifiedChinese, .stale): "较早数据"
        case (.simplifiedChinese, .waiting): "等待中"
        case (.simplifiedChinese, .failed): "失败"
        case (.simplifiedChinese, .unavailable): "不可用"
        }
    }

    private static func observationAgeText(
        capturedAt: Date,
        now: Date,
        language: AppLanguage
    ) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(capturedAt)))
        return switch (language, seconds) {
        case (.english, 0..<60): "Updated just now"
        case (.english, 60..<3_600): "Updated \(seconds / 60) min ago"
        case (.english, 3_600..<86_400): "Updated \(seconds / 3_600) hr ago"
        case (.english, _): "Updated \(seconds / 86_400) d ago"
        case (.simplifiedChinese, 0..<60): "刚刚更新"
        case (.simplifiedChinese, 60..<3_600): "\(seconds / 60) 分钟前更新"
        case (.simplifiedChinese, 3_600..<86_400): "\(seconds / 3_600) 小时前更新"
        case (.simplifiedChinese, _): "\(seconds / 86_400) 天前更新"
        }
    }

    private static func percentageDetailText(
        card: SharedUsageCardPresentation,
        freshnessState: DesktopAssistantFreshnessState,
        language: AppLanguage
    ) -> String? {
        guard card.sourceDescription != nil else { return nil }
        let values: [String] = [
            card.selectedWindow?.compactLabel,
            (card.selectedWindow?.resetText).map {
                compactResetText($0, language: language)
            },
            freshnessState == .stale && card.isEstimated != true
                ? localizedRetainedExactFreshness(language: language)
                : localizedFreshness(freshnessState, language: language),
        ].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return values.joined(separator: " · ")
    }

    private static func compactResetText(
        _ resetText: String,
        language: AppLanguage
    ) -> String {
        switch language {
        case .english:
            return resetText
                .replacingOccurrences(of: "Resets in ", with: "")
                .replacingOccurrences(of: " hours", with: "h")
                .replacingOccurrences(of: " hour", with: "h")
                .replacingOccurrences(of: " hrs", with: "h")
                .replacingOccurrences(of: " hr", with: "h")
                .replacingOccurrences(of: " days", with: "d")
                .replacingOccurrences(of: " day", with: "d")
                .replacingOccurrences(of: " minutes", with: "m")
                .replacingOccurrences(of: " minute", with: "m")
                .replacingOccurrences(of: " mins", with: "m")
                .replacingOccurrences(of: " min", with: "m")
        case .simplifiedChinese:
            return resetText
                .replacingOccurrences(of: "后重置", with: "")
                .replacingOccurrences(of: " ", with: "")
        }
    }

    private static func makeStructuredCreditAccessibilityLabel(
        providerName: String,
        connectionState: DesktopAssistantConnectionState,
        availability: SharedAvailabilityPresentation,
        isStale: Bool,
        language: AppLanguage
    ) -> String {
        let status: String = switch (language, connectionState) {
        case (.english, .connected): "connected"
        case (.english, .reconnecting): "reconnecting"
        case (.english, .stale): "stale value retained"
        case (.english, .disconnected): "disconnected"
        case (.english, .unavailable): "unavailable"
        case (.english, .failed): "failed"
        case (.simplifiedChinese, .connected): "已连接"
        case (.simplifiedChinese, .reconnecting): "正在重新连接"
        case (.simplifiedChinese, .stale): "保留较早值"
        case (.simplifiedChinese, .disconnected): "已断开"
        case (.simplifiedChinese, .unavailable): "不可用"
        case (.simplifiedChinese, .failed): "连接失败"
        }
        let stale = switch (language, isStale) {
        case (.english, true): ", stale"
        case (.simplifiedChinese, true): "，数据已过期"
        default: ""
        }
        let provenance = availability.sourceState == .authenticatedAccountWeb
            ? (language == .simplifiedChinese ? "，账号网页同步" : ", Account web sync")
            : ""
        if language == .simplifiedChinese {
            return "\(providerName)，\(status)，\(availability.accessibilityText)\(provenance)\(stale)。"
        }
        return "\(providerName), \(status), \(availability.accessibilityText)\(provenance)\(stale)."
    }

    private static func localizedRetainedExactFreshness(
        language: AppLanguage
    ) -> String {
        switch language {
        case .english: "Stale exact retained"
        case .simplifiedChinese: "保留的较早精确值"
        }
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
    public let showsStatusIndicator: Bool
    public let showsPercentageRail: Bool
    public let onSelectCard: ((String) -> Void)?

    public init(
        cards: [DesktopAssistantCard],
        density: DesktopAssistantResolvedDensity,
        appearanceOverride: DesktopAssistantAppearanceOverride? = nil,
        showsStatusIndicator: Bool = true,
        showsPercentageRail: Bool = true,
        onSelectCard: ((String) -> Void)? = nil
    ) {
        self.cards = cards
        self.density = density
        self.appearanceOverride = appearanceOverride
        self.showsStatusIndicator = showsStatusIndicator
        self.showsPercentageRail = showsPercentageRail
        self.onSelectCard = onSelectCard
    }

    public var body: some View {
        let valueTexts = cards.map { $0.usageText(for: density) }
        let measured = DesktopAssistantMinimalistTypography.metrics(valueTexts: valueTexts)
        let sharedSize = density == .minimalist
            ? measured.size : DesktopAssistantMetrics.size(for: .regular)
        return VStack(spacing: DesktopAssistantMetrics.rowSpacing) {
            ForEach(cards) { card in
                DesktopAssistantCardView(
                    card: card,
                    density: density,
                    sharedSize: sharedSize,
                    minimalistMetrics: measured,
                    appearanceOverride: appearanceOverride,
                    showsStatusIndicator: showsStatusIndicator,
                    showsPercentageRail: showsPercentageRail,
                    onSelect: onSelectCard
                )
            }
        }
    }
}

private struct DesktopAssistantCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let card: DesktopAssistantCard
    let density: DesktopAssistantResolvedDensity
    let sharedSize: CGSize
    let minimalistMetrics: DesktopAssistantMinimalistTypography.Measurement
    let appearanceOverride: DesktopAssistantAppearanceOverride?
    let showsStatusIndicator: Bool
    let showsPercentageRail: Bool
    let onSelect: ((String) -> Void)?

    private var size: CGSize { sharedSize }
    private var radius: CGFloat {
        density == .minimalist ? DesktopAssistantMetrics.minimalistCornerRadius : size.height / 2
    }
    private var fraction: Double? { card.tintFraction }
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
        .background {
            glassBackground
                .overlay {
                    if showsPercentageRail {
                        CompactUsageFill(
                            remainingPercent: card.remainingPercent,
                            reduceTransparency: usesReduceTransparency,
                            increaseContrast: hasIncreasedContrast,
                            providerID: card.id,
                            admittedPlan: card.planLabel
                        )
                    }
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .opacity(card.isStale ? 0.78 : 1)
        .help(card.toolTip)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?(card.id)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(card.accessibilityLabel))
        .accessibilityAction {
            onSelect?(card.id)
        }
    }

    private var minimalistContent: some View {
        HStack(spacing: DesktopAssistantMetrics.minimalistGap) {
            if showsStatusIndicator {
                sourceMark(diameter: DesktopAssistantMetrics.minimalistConnectionDiameter)
            }
            minimalistValueLabel
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var minimalistValueLabel: some View {
        Text(card.usageText(for: .minimalist))
            .frame(width: minimalistMetrics.prefixWidth + minimalistMetrics.valueWidth,
                   alignment: .trailing)
        .font(DesktopAssistantMinimalistTypography.font)
        .foregroundStyle(valueColor)
        .lineLimit(1)
        .fixedSize()
        // Precision stays adjacent to its number; the whole value is right-aligned.
        .accessibilityHidden(true)
    }

    private var regularContent: some View {
        HStack(spacing: 6) {
            if showsStatusIndicator {
                sourceMark(diameter: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(card.providerName)
                        .font(AppTypography.font(.assistantProvider))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                    if card.sourceMark == .connection,
                       let planLabel = card.planLabel,
                       !planLabel.isEmpty {
                        Text(planLabel)
                            .font(AppTypography.font(.assistantPlan))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Text(
                    card.detailText
                        ?? (card.resetText.isEmpty
                        ? card.selectedWindowShortLabel
                        : "\(card.selectedWindowShortLabel) · \(card.resetText)")
                )
                .font(
                    AppTypography.font(
                        card.sourceMark == .accountWeb
                            ? .assistantAccountDetail
                            : .assistantDetail
                    )
                )
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(card.sourceMark == .accountWeb ? 0.85 : 1)
                .truncationMode(.tail)
            }
            Spacer(minLength: 2)
            valueLabel
        }
        .padding(.horizontal, 10)
    }

    private var valueLabel: some View {
        Group {
            switch card.usageValue {
            case let .finite(value):
                precisionValue(prefix: " ", value: value)
            case let .estimated(value):
                precisionValue(prefix: "≈", value: value)
            default:
                Text(card.usageText(for: density))
                    .monospacedDigit()
            }
        }
        .font(AppTypography.font(.assistantValue))
        .foregroundStyle(valueColor)
        .lineLimit(1)
        .fixedSize()
    }

    private func precisionValue(prefix: String, value: Int) -> some View {
        Text("\(prefix.trimmingCharacters(in: .whitespaces))\(min(100, max(0, value)))%")
            .monospacedDigit()
        .accessibilityHidden(true)
    }

    private func sourceMark(diameter: CGFloat) -> some View {
        DesktopAgentLogo(
            providerID: card.id,
            tint: card.sourceMark == .manual ? .secondary : connectionColor,
            diameter: diameter,
            silhouetteScale: density == .minimalist ? 1.1 : 1
        )
        // The containing card already announces the agent and connection state.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glassBackground: some View {
        Group {
            if usesReduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                    .overlay {
                        if colorScheme == .light {
                            Color.black.opacity(0.07)
                        }
                    }
            }
        }
    }

    private var connectionColor: Color {
        switch card.connectionState {
        case .connected:
            AgentConnectionIndicatorPalette.connected(isDark: colorScheme == .dark, increasedLightContrast: true)
        case .reconnecting:
            .orange
        case .stale:
            .orange
        case .disconnected, .unavailable:
            .secondary
        case .failed:
            .red
        }
    }

    private var valueColor: Color {
        // Credits have no percentage surface: only their native-unit value is
        // colored. Connectivity retains its independent status palette.
        if case .credits = card.usageValue {
            return LowRemainingUsagePolicy.color(for: LowRemainingUsagePolicy.assessment(
                providerID: card.id, admittedPlan: card.planLabel,
                remainingPercent: nil, availableCredits: card.availableCredits
            ))
        }
        return .primary
    }
}
