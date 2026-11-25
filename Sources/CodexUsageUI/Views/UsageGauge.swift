import AppKit
import SwiftUI

// One usage gauge for every surface (design/auv-usage-gauge-20261125/SPEC.md):
// a big block for the leading window and a thin wrap bar for the weekly one.

/// The colour band of a remaining share.
public enum UsageGaugeTier: Equatable, Sendable {
    case plenty
    case caution
    case low
    case unlimited
    case outdated
    case unavailable

    /// More than 50% is plenty, 20% to 50% is caution, less than 20% is low.
    public static func forRemaining(_ percent: Double?) -> Self {
        guard let percent, percent.isFinite, (0...100).contains(percent) else {
            return .unavailable
        }
        if percent > 50 { return .plenty }
        if percent >= 20 { return .caution }
        return .low
    }
}

public enum UsageGaugePalette {
    /// Softer, deeper tones than the system colours, so a fill reads as a
    /// level rather than an alert, and the tiers still tell apart at a glance.
    public static func color(_ tier: UsageGaugeTier, isDark: Bool) -> Color {
        switch tier {
        case .plenty:
            isDark ? Color(red: 0.29, green: 0.85, blue: 0.62) : Color(red: 0.04, green: 0.58, blue: 0.40)
        case .caution:
            isDark ? Color(red: 1.00, green: 0.76, blue: 0.32) : Color(red: 0.84, green: 0.55, blue: 0.02)
        case .low:
            isDark ? Color(red: 1.00, green: 0.43, blue: 0.43) : Color(red: 0.84, green: 0.21, blue: 0.24)
        case .unlimited:
            isDark ? Color(red: 0.40, green: 0.67, blue: 1.00) : Color(red: 0.10, green: 0.45, blue: 0.94)
        case .outdated, .unavailable:
            isDark ? Color(white: 0.62) : Color(white: 0.50)
        }
    }
}

/// One usage window as the gauge needs it.
public struct UsageGaugeWindow: Equatable, Sendable {
    public let remainingPercent: Double?
    public let resetsAt: Date?

    public init(remainingPercent: Double?, resetsAt: Date? = nil) {
        self.remainingPercent = remainingPercent.flatMap {
            $0.isFinite && (0...100).contains($0) ? $0 : nil
        }
        self.resetsAt = resetsAt
    }
}

/// What an agent's gauge shows: which window leads the big block, and what
/// the wrap bar carries.
public struct UsageGaugeReading: Equatable, Sendable {
    public enum Lead: Equatable, Sendable {
        case fiveHour
        case sevenDay
        case unlimited
        case unavailable
    }

    public let lead: Lead
    /// The window in the big block: 5H when there is one, otherwise 7D.
    public let primary: UsageGaugeWindow?
    /// The window on the wrap bar: 7D under a 5H lead, otherwise nil.
    public let secondary: UsageGaugeWindow?
    public let isOutdated: Bool

    public static func make(
        fiveHour: UsageGaugeWindow?,
        sevenDay: UsageGaugeWindow?,
        isUnlimited: Bool = false,
        isOutdated: Bool = false
    ) -> Self {
        if isUnlimited {
            return Self(lead: .unlimited, primary: nil, secondary: nil, isOutdated: false)
        }
        if let fiveHour, fiveHour.remainingPercent != nil {
            return Self(lead: .fiveHour, primary: fiveHour, secondary: sevenDay, isOutdated: isOutdated)
        }
        if let sevenDay, sevenDay.remainingPercent != nil {
            return Self(lead: .sevenDay, primary: sevenDay, secondary: nil, isOutdated: isOutdated)
        }
        return Self(lead: .unavailable, primary: nil, secondary: nil, isOutdated: false)
    }

    public var primaryLabel: String {
        switch lead {
        case .fiveHour: "5H"
        case .sevenDay: "7D"
        case .unlimited, .unavailable: ""
        }
    }

    /// The big block's share, 0...1, or nil for no fill.
    public var primaryFraction: Double? {
        switch lead {
        case .unlimited: 1
        case .unavailable: nil
        case .fiveHour, .sevenDay: primary?.remainingPercent.map { $0 / 100 }
        }
    }

    public var primaryTier: UsageGaugeTier {
        switch lead {
        case .unlimited: .unlimited
        case .unavailable: .unavailable
        case .fiveHour, .sevenDay:
            isOutdated ? .outdated : .forRemaining(primary?.remainingPercent)
        }
    }

    /// The wrap bar: 7D's own level under a 5H lead, and full bright blue
    /// when 7D already sits in the big block or there is no limit.
    public var barFraction: Double? {
        switch lead {
        case .fiveHour: secondary?.remainingPercent.map { $0 / 100 }
        case .sevenDay, .unlimited: 1
        case .unavailable: nil
        }
    }

    public var barTier: UsageGaugeTier {
        switch lead {
        case .fiveHour:
            isOutdated ? .outdated : .forRemaining(secondary?.remainingPercent)
        case .sevenDay, .unlimited: .unlimited
        case .unavailable: .unavailable
        }
    }

    public var primaryValueText: String {
        switch lead {
        case .unlimited: "∞"
        case .unavailable: "—"
        case .fiveHour, .sevenDay:
            primary?.remainingPercent.map { "\(Int($0.rounded()))%" } ?? "—"
        }
    }

    /// The small weekly value, shown only when the bar carries 7D.
    public var secondaryValueText: String? {
        guard lead == .fiveHour, let value = secondary?.remainingPercent else { return nil }
        return "\(Int(value.rounded()))%"
    }
}

// MARK: - Shape

/// The gauge outline: the left end rounds around the logo, the right end
/// keeps a small corner.
public struct UsageGaugeShape: Shape {
    public var leftRadius: CGFloat
    public var rightRadius: CGFloat

    public init(leftRadius: CGFloat, rightRadius: CGFloat) {
        self.leftRadius = leftRadius
        self.rightRadius = rightRadius
    }

    public func path(in rect: CGRect) -> Path {
        let left = min(leftRadius, rect.height / 2, rect.width / 2)
        let right = min(rightRadius, rect.height / 2, rect.width / 2)
        return UnevenRoundedRectangle(
            topLeadingRadius: left,
            bottomLeadingRadius: left,
            bottomTrailingRadius: right,
            topTrailingRadius: right,
            style: .circular
        ).path(in: rect)
    }
}

/// The wrap bar's track: from the top of the left end, around it and along
/// the bottom edge to the right corner, `inset` inside the outline.
struct UsageGaugeWrapPath: Shape {
    var leftRadius: CGFloat
    var rightRadius: CGFloat
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let geometry = Geometry(rect: rect, leftRadius: leftRadius,
                                rightRadius: rightRadius, inset: inset)
        var path = Path()
        path.move(to: CGPoint(x: geometry.minX + geometry.left, y: geometry.minY))
        path.addArc(tangent1End: CGPoint(x: geometry.minX, y: geometry.minY),
                    tangent2End: CGPoint(x: geometry.minX, y: geometry.maxY),
                    radius: geometry.left)
        path.addArc(tangent1End: CGPoint(x: geometry.minX, y: geometry.maxY),
                    tangent2End: CGPoint(x: geometry.maxX, y: geometry.maxY),
                    radius: geometry.left)
        path.addLine(to: CGPoint(x: geometry.maxX - geometry.right, y: geometry.maxY))
        return path
    }

    struct Geometry {
        let minX, minY, maxX, maxY, left, right: CGFloat

        init(rect: CGRect, leftRadius: CGFloat, rightRadius: CGFloat, inset: CGFloat) {
            minX = rect.minX + inset
            minY = rect.minY + inset
            maxX = rect.maxX - inset
            maxY = rect.maxY - inset
            let height = max(0, maxY - minY)
            left = max(0.5, min(leftRadius - inset, height / 2))
            right = max(0, rightRadius - inset)
        }

        /// Two quarter arcs, the straight part of the left end, and the bottom edge.
        var length: CGFloat {
            .pi * left + max(0, (maxY - minY) - 2 * left)
                + max(0, (maxX - right) - (minX + left))
        }
    }
}

// MARK: - Background

/// Draws a gauge behind content: the big block's fill and the wrap bar. The
/// caller clips to `UsageGaugeShape` with the same radii.
public struct UsageGaugeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public let reading: UsageGaugeReading
    public let leftRadius: CGFloat
    public let rightRadius: CGFloat
    /// Height of the fill from the top; nil fills the whole gauge.
    public let fillHeight: CGFloat?
    public let barWidth: CGFloat
    public let fillOpacity: Double

    public init(
        reading: UsageGaugeReading,
        leftRadius: CGFloat,
        rightRadius: CGFloat,
        fillHeight: CGFloat? = nil,
        barWidth: CGFloat = 2.5,
        fillOpacity: Double
    ) {
        self.reading = reading
        self.leftRadius = leftRadius
        self.rightRadius = rightRadius
        self.fillHeight = fillHeight
        self.barWidth = barWidth
        self.fillOpacity = fillOpacity
    }

    public var body: some View {
        GeometryReader { proxy in
            let isDark = colorScheme == .dark
            ZStack(alignment: .topLeading) {
                if let fraction = reading.primaryFraction {
                    let color = UsageGaugePalette.color(reading.primaryTier, isDark: isDark)
                    let width = proxy.size.width * min(1, max(0, fraction))
                    // Deepens toward the level, with a crisp edge where it ends.
                    LinearGradient(
                        colors: [color.opacity(fillOpacity * 0.45), color.opacity(fillOpacity * 1.35)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: width, height: fillHeight ?? proxy.size.height)
                    if fraction > 0.02, fraction < 0.995 {
                        UsageGaugeLevelEdge(color: color)
                            .frame(width: 1.5, height: fillHeight ?? proxy.size.height)
                            .offset(x: width - 1.5)
                    }
                }
                wrapBar(size: proxy.size, isDark: isDark)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func wrapBar(size: CGSize, isDark: Bool) -> some View {
        let inset = barWidth / 2 + 1.5
        let track = UsageGaugeWrapPath(leftRadius: leftRadius, rightRadius: rightRadius, inset: inset)
        // One continuous bar; its track is a lighter step of its own colour.
        let color = UsageGaugePalette.color(reading.barTier, isDark: isDark)
        let style = StrokeStyle(lineWidth: barWidth, lineCap: .round)
        ZStack {
            track.stroke(reading.barFraction == nil
                         ? Color.primary.opacity(isDark ? 0.14 : 0.10)
                         : color.opacity(isDark ? 0.20 : 0.18), style: style)
            if let fraction = reading.barFraction, fraction > 0 {
                track
                    .trim(from: 0, to: min(1, fraction))
                    .stroke(color, style: style)
            }
        }
    }
}

// MARK: - Level edge

/// Where a level ends: short ticks at the top and bottom, clear in between
/// so it never cuts through text.
struct UsageGaugeLevelEdge: View {
    let color: Color

    var body: some View {
        let lit = color.opacity(0.95)
        Rectangle().fill(LinearGradient(stops: [
            .init(color: lit, location: 0),
            .init(color: lit, location: 0.05),
            .init(color: lit.opacity(0), location: 0.09),
            .init(color: lit.opacity(0), location: 0.91),
            .init(color: lit, location: 0.95),
            .init(color: lit, location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Gauge card (regular window, Quick Panel, main window list)

/// The gauge card (design/auv-usage-gauge-20261125/SPEC.md). Sizes scale with
/// the card's height.
///
/// Two bands when 5H leads:
/// - Top band (5H, the larger): its fill runs from the logo column to the
///   remaining share; the name (lists) and the 5H reset time on the left; on
///   the right, "5H" above the big value.
/// - 7D bar: the logo column is its first tenth, then it runs along the
///   narrower bottom band; the 7D reset date on the left, "7D" and its value
///   on the right.
///
/// One band when 7D leads or there is no limit: the whole card is the level.
public struct UsageGaugeCardGeometry: Equatable, Sendable {
    public let size: CGSize
    public let isSingleBand: Bool

    public init(size: CGSize, isSingleBand: Bool = false) {
        self.size = size
        self.isSingleBand = isSingleBand
    }

    var h: CGFloat { size.height }
    public var cornerRadius: CGFloat { min(14, h * 0.3) }
    public var bandHeight: CGFloat { isSingleBand ? h : (h * 0.72).rounded() }
    public var logoDiameter: CGFloat { (h * 0.7).rounded() }
    /// The logo's column at the left end, which is also the 7D bar's first tenth.
    public var capWidth: CGFloat { (logoDiameter + h * 0.24).rounded() }
    public var logoCenter: CGPoint { CGPoint(x: capWidth / 2, y: h / 2) }
    public var logoGlyphDiameter: CGFloat { logoDiameter * 0.56 }
    public var textX: CGFloat { capWidth + h * 0.14 }
    public var trailingInset: CGFloat { h * 0.2 }

    public func fillEndX(fraction: Double) -> CGFloat {
        capWidth + (size.width - capWidth) * min(1, max(0, fraction))
    }

    /// The 5H fill: from the logo column to the remaining share.
    public func fillPath(fraction: Double) -> Path {
        Path(CGRect(x: capWidth, y: 0, width: fillEndX(fraction: fraction) - capWidth, height: bandHeight))
    }

    /// How much of the logo column is filled, top down: the 7D bar's first tenth.
    public func capFill(fraction: Double) -> CGFloat {
        h * CGFloat(min(1, max(0, fraction) / 0.1))
    }

    /// How far the 7D bar reaches along the bottom band after the logo column.
    public func bottomFillWidth(fraction: Double) -> CGFloat {
        (size.width - capWidth) * CGFloat(min(1, max(0, fraction - 0.1) / 0.9))
    }
}

/// The gauge card itself. Text comes in already formatted.
public struct UsageGaugeCard: View {
    @Environment(\.colorScheme) private var colorScheme

    public let reading: UsageGaugeReading
    public let providerID: String
    public let size: CGSize
    public let title: String?
    public let primaryResetText: String
    public let secondaryText: String
    /// The connection dot on the logo; nil draws none.
    public let statusColor: Color?

    public init(
        reading: UsageGaugeReading,
        providerID: String,
        size: CGSize,
        title: String? = nil,
        primaryResetText: String,
        secondaryText: String,
        statusColor: Color? = nil
    ) {
        self.reading = reading
        self.providerID = providerID
        self.size = size
        self.title = title
        self.primaryResetText = primaryResetText
        self.secondaryText = secondaryText
        self.statusColor = statusColor
    }

    private var isDark: Bool { colorScheme == .dark }
    private var isSingleBand: Bool { reading.lead == .sevenDay || reading.lead == .unlimited }
    private var h: CGFloat { size.height }
    /// Text never drops below 10 points, whatever the card's height.
    private func points(_ ratio: CGFloat, minimum: CGFloat = 10) -> CGFloat { max(minimum, h * ratio) }

    public var body: some View {
        let g = UsageGaugeCardGeometry(size: size, isSingleBand: isSingleBand)
        let shape = RoundedRectangle(cornerRadius: g.cornerRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                (isDark ? Color(white: 0.08).opacity(0.62) : Color.white.opacity(0.55))
            }
            if isSingleBand {
                singleBandLevel(geometry: g)
            } else {
                sevenDayBar(geometry: g)
                fiveHourLevel(geometry: g)
                Rectangle()
                    .fill(Color.primary.opacity(isDark ? 0.10 : 0.08))
                    .frame(width: size.width - g.capWidth, height: 0.5)
                    .offset(x: g.capWidth, y: g.bandHeight)
            }
            logo(geometry: g)
            if isSingleBand {
                singleBandText(geometry: g)
            } else {
                twoBandText(geometry: g)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: [Color.white.opacity(isDark ? 0.18 : 0.75), Color.primary.opacity(isDark ? 0.06 : 0.08)],
                startPoint: .top, endPoint: .bottom
            ), lineWidth: 1)
        }
    }

    // MARK: Surfaces

    private func levelGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(isDark ? 0.14 : 0.12), color.opacity(isDark ? 0.42 : 0.36)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private func edge(_ color: Color, at x: CGFloat, height: CGFloat, y: CGFloat = 0) -> some View {
        UsageGaugeLevelEdge(color: color)
            .frame(width: 1.5, height: height)
            .offset(x: x - 1.5, y: y)
    }

    private func fiveHourLevel(geometry g: UsageGaugeCardGeometry) -> some View {
        let color = UsageGaugePalette.color(reading.primaryTier, isDark: isDark)
        let fraction = reading.primaryFraction ?? 0
        let end = g.fillEndX(fraction: fraction)
        return ZStack(alignment: .topLeading) {
            if reading.primaryFraction != nil {
                g.fillPath(fraction: fraction).fill(levelGradient(color))
                if fraction > 0.02, fraction < 0.995 {
                    edge(color, at: end, height: g.bandHeight)
                }
            }
        }
    }

    private func sevenDayBar(geometry g: UsageGaugeCardGeometry) -> some View {
        let color = UsageGaugePalette.color(reading.barTier, isDark: isDark)
        let fraction = reading.barFraction ?? 0
        let bottomHeight = h - g.bandHeight
        let bottomWidth = g.bottomFillWidth(fraction: fraction)
        return ZStack(alignment: .topLeading) {
            // The logo column: a quiet track, filled top down.
            color.opacity(isDark ? 0.08 : 0.08)
                .frame(width: g.capWidth, height: h)
            color.opacity(isDark ? 0.34 : 0.30)
                .frame(width: g.capWidth, height: g.capFill(fraction: fraction))
            // The bottom band, filled left to right.
            levelGradient(color)
                .frame(width: bottomWidth, height: bottomHeight)
                .offset(x: g.capWidth, y: g.bandHeight)
        }
    }

    private func singleBandLevel(geometry g: UsageGaugeCardGeometry) -> some View {
        let color = UsageGaugePalette.color(reading.primaryTier, isDark: isDark)
        let fraction = reading.primaryFraction ?? 0
        let end = size.width * min(1, max(0, fraction))
        return ZStack(alignment: .topLeading) {
            if reading.primaryFraction != nil {
                levelGradient(color).frame(width: end, height: h)
                if fraction > 0.02, fraction < 0.995 {
                    edge(color, at: end, height: h)
                }
            }
        }
    }

    private func logo(geometry g: UsageGaugeCardGeometry) -> some View {
        let d = g.logoDiameter
        return ZStack {
            Circle().fill(isDark ? Color(white: 0.10) : Color.white)
            Circle().strokeBorder(Color.primary.opacity(isDark ? 0.22 : 0.12), lineWidth: 1)
            DesktopAgentLogo(providerID: providerID, tint: .primary, diameter: g.logoGlyphDiameter)
        }
        .frame(width: d, height: d)
        .overlay(alignment: .bottomTrailing) {
            if let statusColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: d * 0.2, height: d * 0.2)
                    .overlay { Circle().stroke(isDark ? Color(white: 0.10) : Color.white, lineWidth: 1.5) }
                    .offset(x: d * 0.02, y: d * 0.02)
            }
        }
        .shadow(color: .black.opacity(isDark ? 0.35 : 0.10), radius: h * 0.04, y: h * 0.015)
        .offset(x: g.logoCenter.x - d / 2, y: g.logoCenter.y - d / 2)
    }

    // MARK: Text

    private func twoBandText(geometry g: UsageGaugeCardGeometry) -> some View {
        let primaryColor = UsageGaugePalette.color(reading.primaryTier, isDark: isDark)
        return ZStack(alignment: .topLeading) {
            // Top band: name (lists) and the 5H reset on the left; "5H" above
            // the big value on the right.
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    if let title { titleText(title) }
                    resetText(primaryResetText, size: points(0.165))
                }
                Spacer(minLength: 4)
                labelledValue(label: "5H", value: reading.primaryValueText,
                              size: points(0.37, minimum: 18),
                              tint: reading.primaryTier == .low ? primaryColor : nil)
            }
            .padding(.leading, g.textX)
            .padding(.trailing, g.trailingInset)
            .frame(width: size.width, height: g.bandHeight)

            // Bottom band: the 7D reset on the left; "7D" and its value on the right.
            HStack(alignment: .center, spacing: 6) {
                resetText(secondaryText, size: points(0.145))
                Spacer(minLength: 4)
                if let small = reading.secondaryValueText {
                    inlineValue(label: "7D", value: small, size: points(0.18, minimum: 11))
                }
            }
            .padding(.leading, g.textX)
            .padding(.trailing, g.trailingInset)
            .frame(width: size.width, height: h - g.bandHeight)
            .offset(y: g.bandHeight)
        }
    }

    private func singleBandText(geometry g: UsageGaugeCardGeometry) -> some View {
        let primaryColor = UsageGaugePalette.color(reading.primaryTier, isDark: isDark)
        let label = reading.lead == .unlimited ? "API" : "7D"
        return HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if let title { titleText(title) }
                resetText(primaryResetText, size: points(0.165), mark: reading.lead == .sevenDay)
                if reading.lead == .sevenDay {
                    Text(secondaryText)
                        .font(.system(size: points(0.14), weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            labelledValue(label: label, value: reading.primaryValueText,
                          size: points(0.42, minimum: 20),
                          tint: reading.primaryTier == .low ? primaryColor : nil)
        }
        .padding(.leading, g.textX)
        .padding(.trailing, g.trailingInset)
        .frame(width: size.width, height: h)
    }

    /// The name line; where "Name · plan" does not fit, the name alone.
    private func titleText(_ text: String) -> some View {
        let name = text.components(separatedBy: " · ").first ?? text
        return ViewThatFits(in: .horizontal) {
            Text(text).fixedSize()
            Text(name)
        }
        .font(.system(size: points(0.17, minimum: 11), weight: .semibold))
        .foregroundStyle(.primary.opacity(0.92))
        .lineLimit(1)
    }

    /// A reset time or date behind a small reset mark.
    private func resetText(_ text: String, size points: CGFloat, mark: Bool = true) -> some View {
        HStack(spacing: points * 0.3) {
            if mark, !text.isEmpty {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: points * 0.72, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.45))
            }
            Text(text)
                .font(.system(size: points, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.72))
        }
        .lineLimit(1)
    }

    private func numberText(_ value: String, size points: CGFloat) -> Text {
        let hasPercent = value.hasSuffix("%")
        let number = hasPercent ? String(value.dropLast()) : value
        return Text(number).font(.system(size: points, weight: .semibold, design: .rounded))
            + Text(hasPercent ? "%" : "").font(.system(size: points * 0.56, weight: .semibold, design: .rounded))
    }

    private func periodLabel(_ text: String, size points: CGFloat) -> some View {
        Text(text)
            .font(.system(size: points, weight: .bold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(.primary.opacity(0.5))
    }

    /// The big value with its period label just above it, right-aligned.
    private func labelledValue(label: String, value: String, size points: CGFloat, tint: Color?) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            periodLabel(label, size: max(9.5, points * 0.32))
            numberText(value, size: points)
                .foregroundStyle(tint ?? Color.primary)
                .padding(.top, -points * 0.12)
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// "7D 71%": the period beside the small value.
    private func inlineValue(label: String, value: String, size points: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: points * 0.25) {
            periodLabel(label, size: max(9.5, points * 0.62))
            numberText(value, size: points)
                .foregroundStyle(.primary.opacity(0.9))
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - Readings from the app's models

public extension UsageGaugeReading {
    /// The same reading, drawn grey when it is no longer current.
    func markingOutdated(_ outdated: Bool) -> Self {
        guard outdated, lead == .fiveHour || lead == .sevenDay else { return self }
        return Self(lead: lead, primary: primary, secondary: secondary, isOutdated: true)
    }

    /// The gauge for a product row, or nil when the agent counts credits
    /// rather than a remaining share.
    static func from(provider: ProviderProductState) -> Self? {
        if provider.quotas.contains(where: { $0.kind == .credits }) { return nil }
        let five = provider.quotas.first { $0.kind == .fiveHour }
        let seven = provider.quotas.first { $0.kind == .sevenDay }
        let unlimited = provider.primaryQuota?.value == .unlimited
            || (five?.value == .unlimited && (seven == nil || seven?.value == .unlimited))
        // Claude's reading turns grey once it is retained, outdated or an estimate.
        let outdated = provider.id == .claude
            && (provider.freshness != .fresh || provider.precision != .exact)
        return .make(
            fiveHour: five.map { UsageGaugeWindow(remainingPercent: $0.value.remainingPercent, resetsAt: $0.resetsAt) },
            sevenDay: seven.map { UsageGaugeWindow(remainingPercent: $0.value.remainingPercent, resetsAt: $0.resetsAt) },
            isUnlimited: unlimited,
            isOutdated: outdated
        )
    }

    /// The gauge for a Desktop Assistant card's percentage windows.
    static func from(shared card: SharedUsageCardPresentation) -> Self {
        let five = card.windows.first { $0.kind == .fiveHour }
        let seven = card.windows.first { $0.kind == .sevenDay }
        let unlimited = card.remaining == .unlimited
            || (five?.remaining == .unlimited && (seven == nil || seven?.remaining == .unlimited))
        return .make(
            fiveHour: five.map { UsageGaugeWindow(remainingPercent: $0.remaining.finitePercent, resetsAt: $0.resetsAt) },
            sevenDay: seven.map { UsageGaugeWindow(remainingPercent: $0.remaining.finitePercent, resetsAt: $0.resetsAt) },
            isUnlimited: unlimited
        )
    }
}

// MARK: - Text

public enum UsageGaugeText {
    /// What sits in the top band: 5H's reset time, or 7D's reset date when
    /// 7D leads.
    public static func primaryReset(_ reading: UsageGaugeReading, language: AppLanguage) -> String {
        switch reading.lead {
        case .unlimited:
            return language == .simplifiedChinese ? "没有上限" : "No limit"
        case .unavailable:
            return ""
        case .fiveHour:
            return reading.primary?.resetsAt.map { time($0, language: language) } ?? ""
        case .sevenDay:
            return reading.primary?.resetsAt.map { day($0, language: language) } ?? ""
        }
    }

    /// What sits in the bottom band: 7D's reset date, or why there is none.
    public static func secondary(_ reading: UsageGaugeReading, language: AppLanguage) -> String {
        let zh = language == .simplifiedChinese
        switch reading.lead {
        case .fiveHour: return reading.secondary?.resetsAt.map { day($0, language: language) } ?? ""
        case .sevenDay: return zh ? "没有 5H 限额" : "No 5H limit"
        case .unlimited: return "API"
        case .unavailable: return ""
        }
    }

    public static func time(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .simplifiedChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    public static func day(_ date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        if language == .simplifiedChinese {
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M月d日"
            return formatter.string(from: date)
        }
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).uppercased()
    }
}

public extension UsageGaugePalette {
    /// The tier colour for a remaining share, following light and dark mode.
    static func dynamicColor(forRemaining percent: Double?) -> Color {
        let tier = UsageGaugeTier.forRemaining(percent)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(color(tier, isDark: isDark))
        })
    }
}
