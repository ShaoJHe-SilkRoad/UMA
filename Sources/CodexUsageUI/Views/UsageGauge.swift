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

    /// In light mode the Minimalist capsule's glass follows the wallpaper, so
    /// on a dark desktop its green logo and 7D bar sank into it. A white wash
    /// keeps the capsule light whatever lies behind it.
    public static let minimalLightWash = 0.5
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
                    let height = fillHeight ?? proxy.size.height
                    // One flat colour; its end turns with the outline's right
                    // corner at the top, a solid tick marks it at the bottom.
                    UnevenRoundedRectangle(
                        topTrailingRadius: max(0, min(rightRadius, width, height)),
                        style: .continuous
                    )
                    .fill(color.opacity(fillOpacity))
                    .frame(width: width, height: height)
                    if fraction > 0.02, fraction < 0.995 {
                        Capsule().fill(color)
                            .frame(width: UsageGaugeLevelEdge.width, height: UsageGaugeLevelEdge.tickLength)
                            .offset(x: width - UsageGaugeLevelEdge.width,
                                    y: height - UsageGaugeLevelEdge.tickLength)
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

/// Where a level ends: a short solid tick at the top and at the bottom,
/// clear in between so it never cuts through text.
struct UsageGaugeLevelEdge: View {
    static let width: CGFloat = 2
    static let tickLength: CGFloat = 6
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(color).frame(width: Self.width, height: Self.tickLength)
            Spacer(minLength: 0)
            Capsule().fill(color).frame(width: Self.width, height: Self.tickLength)
        }
    }
}

// MARK: - Surface

/// The gauge card's own surface, for every module on the agent page, so the
/// page has one surface: glass with a light or dark wash, a 14 pt continuous
/// corner and the card's top-lit border.
struct UsageGaugeSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    (isDark ? Color(white: 0.08).opacity(0.62) : Color.white.opacity(0.55))
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(LinearGradient(
                    colors: [Color.white.opacity(isDark ? 0.12 : 0.75), Color.primary.opacity(isDark ? 0.06 : 0.08)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1)
            }
    }
}

extension View {
    func usageGaugeSurface(cornerRadius: CGFloat = 14) -> some View {
        modifier(UsageGaugeSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - Typography

/// The gauge's numbers: SF Pro Medium Condensed with even digits, the same
/// recipe as the Minimalist assistant's value.
enum UsageGaugeTypography {
    static func number(size: CGFloat) -> Font {
        .system(size: size, weight: .medium).width(.condensed).monospacedDigit()
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
    /// False on the agent's own page, where the page header already shows the
    /// logo: no logo column, the bands start at the left edge.
    public let showsLogo: Bool

    public init(size: CGSize, isSingleBand: Bool = false, showsLogo: Bool = true) {
        self.size = size
        self.isSingleBand = isSingleBand
        self.showsLogo = showsLogo
    }

    var h: CGFloat { size.height }
    public var cornerRadius: CGFloat { min(14, h * 0.3) }
    public var bandHeight: CGFloat { isSingleBand ? h : (h * 0.72).rounded() }

    /// The logo's column at the left end, which is also the 7D bar's first tenth.
    public var capWidth: CGFloat { showsLogo ? (h * 0.62).rounded() : 0 }
    public var logoCenter: CGPoint { CGPoint(x: capWidth / 2, y: h / 2) }
    /// The bare logo on the column: no disc; it takes the connection colour.
    public var logoGlyphSize: CGFloat { (h * 0.36).rounded() }
    /// The card-surface gap between colour blocks.
    public let seamGap: CGFloat = 2
    /// The inner corner where the 7D column turns into the bottom band.
    public var filletRadius: CGFloat { (h * 0.11).rounded() }
    /// The right edge of the logo column, before the gap.
    public var columnWidth: CGFloat { showsLogo ? capWidth - seamGap / 2 : 0 }
    public var textX: CGFloat { showsLogo ? capWidth + h * 0.13 : h * 0.2 }
    /// Where the 5H (or single) level starts: after the column's gap, or the left edge.
    public var levelX: CGFloat { showsLogo ? capWidth + seamGap / 2 : 0 }
    public var trailingInset: CGFloat { h * 0.2 }

    public func fillEndX(fraction: Double) -> CGFloat {
        capWidth + (size.width - capWidth) * min(1, max(0, fraction))
    }

    /// The 5H fill: from the gap after the logo column to the remaining share,
    /// above the gap over the 7D band; its inner corner follows the L's turn.
    /// Its end turns with the card's own corner at the top right.
    public func fillPath(fraction: Double) -> Path {
        let x = levelX
        let rect = CGRect(x: x, y: 0, width: max(0, fillEndX(fraction: fraction) - x),
                          height: bandHeight - seamGap / 2)
        let inner = showsLogo ? min(filletRadius, rect.width / 2, rect.height / 2) : 0
        return UnevenRoundedRectangle(bottomLeadingRadius: inner,
                                      topTrailingRadius: endRadius(rect),
                                      style: .continuous).path(in: rect)
    }

    /// The radius a level's end takes: the card's corner, never more than the
    /// level itself allows.
    public func endRadius(_ rect: CGRect) -> CGFloat {
        max(0, min(cornerRadius, rect.width, rect.height))
    }

    /// The single level: the whole height, both right corners turning with
    /// the card's corner.
    public func singlePath(fraction: Double) -> Path {
        let end = size.width * CGFloat(min(1, max(0, fraction)))
        var path = Path()
        if showsLogo {
            path.addRect(CGRect(x: 0, y: 0, width: min(end, columnWidth), height: h))
        }
        let rect = CGRect(x: levelX, y: 0, width: max(0, end - levelX), height: h)
        let r = min(endRadius(rect), h / 2)
        path.addPath(UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r,
                                            style: .continuous).path(in: rect))
        return path
    }

    /// The whole 7D bar as one shape, so it is filled once in one colour:
    /// the logo column filled top down (its first tenth), then, past a tenth,
    /// the inner turn and the bottom band.
    public func sevenDayPath(fraction: Double) -> Path {
        var path = Path()
        let column = columnWidth
        let top = bandHeight + seamGap / 2
        let end = capWidth + bottomFillWidth(fraction: fraction)
        guard showsLogo else {
            // Two plain bands: the 7D bar runs along the bottom from the left edge.
            let rect = CGRect(x: 0, y: top, width: max(0, end), height: size.height - top)
            path.addPath(UnevenRoundedRectangle(bottomTrailingRadius: endRadius(rect),
                                                style: .continuous).path(in: rect))
            return path
        }
        path.addRect(CGRect(x: 0, y: 0, width: column, height: capFill(fraction: fraction)))
        guard fraction >= 0.1 else { return path }
        // The band's end turns with the card's corner at the bottom right.
        let band = CGRect(x: column, y: top, width: max(0, end - column), height: size.height - top)
        path.addPath(UnevenRoundedRectangle(bottomTrailingRadius: endRadius(band),
                                            style: .continuous).path(in: band))
        // The turn: the corner between the column and the band, cut by an arc
        // that keeps one gap's distance from the 5H block's rounded corner.
        let center = CGPoint(x: capWidth + seamGap / 2 + filletRadius,
                             y: bandHeight - seamGap / 2 - filletRadius)
        var turn = Path()
        turn.move(to: CGPoint(x: column, y: center.y))
        turn.addLine(to: CGPoint(x: column, y: top))
        turn.addLine(to: CGPoint(x: center.x, y: top))
        turn.addArc(center: center, radius: filletRadius + seamGap,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        turn.closeSubpath()
        path.addPath(turn)
        return path
    }

    /// How much of the logo column is filled, top down: the 7D bar's first tenth.
    public func capFill(fraction: Double) -> CGFloat {
        h * CGFloat(min(1, max(0, fraction) / 0.1))
    }

    /// How far the 7D bar reaches along the bottom band after the logo column.
    public func bottomFillWidth(fraction: Double) -> CGFloat {
        guard showsLogo else { return size.width * CGFloat(min(1, max(0, fraction))) }
        return (size.width - capWidth) * CGFloat(min(1, max(0, fraction - 0.1) / 0.9))
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
    /// The logo's connection colour; nil draws the logo in ink.
    public let statusColor: Color?
    /// False on the agent's own page: two plain bands, no logo column.
    public let showsLogo: Bool

    public init(
        reading: UsageGaugeReading,
        providerID: String,
        size: CGSize,
        title: String? = nil,
        primaryResetText: String,
        secondaryText: String,
        statusColor: Color? = nil,
        showsLogo: Bool = true
    ) {
        self.reading = reading
        self.providerID = providerID
        self.size = size
        self.title = title
        self.primaryResetText = primaryResetText
        self.secondaryText = secondaryText
        self.statusColor = statusColor
        self.showsLogo = showsLogo
    }

    private var isDark: Bool { colorScheme == .dark }
    private var isSingleBand: Bool { reading.lead == .sevenDay || reading.lead == .unlimited }
    private var h: CGFloat { size.height }
    /// Text never drops below 10 points, whatever the card's height.
    private func points(_ ratio: CGFloat, minimum: CGFloat = 10) -> CGFloat { max(minimum, h * ratio) }

    public var body: some View {
        let g = UsageGaugeCardGeometry(size: size, isSingleBand: isSingleBand, showsLogo: showsLogo)
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
            }
            if showsLogo { logo(geometry: g) }
            if isSingleBand {
                singleBandText(geometry: g)
            } else {
                twoBandText(geometry: g)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // Composite first: without it, fills that start at the card's own
        // edge (no logo column) can be drawn outside the rounded clip.
        .compositingGroup()
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: [Color.white.opacity(isDark ? 0.12 : 0.75), Color.primary.opacity(isDark ? 0.06 : 0.08)],
                startPoint: .top, endPoint: .bottom
            ), lineWidth: 1)
        }
    }

    // MARK: Surfaces

    /// Flat fills: the big 5H (or single) level one step lighter than the
    /// thinner 7D bar, so the big value stays clear and the two never merge.
    private enum Band { case level, bar }

    private func levelFill(_ color: Color, _ band: Band) -> Color {
        switch band {
        case .level: color.opacity(isDark ? 0.24 : 0.18)
        case .bar: color.opacity(isDark ? 0.32 : 0.28)
        }
    }

    /// The 5H level's end: its top turns with the card's corner, a short
    /// solid tick marks the straight end at the bottom.
    private func bottomTick(_ color: Color, at x: CGFloat, bottom: CGFloat) -> some View {
        Capsule().fill(color)
            .frame(width: UsageGaugeLevelEdge.width, height: UsageGaugeLevelEdge.tickLength)
            .offset(x: x - UsageGaugeLevelEdge.width, y: bottom - UsageGaugeLevelEdge.tickLength)
    }

    private func fiveHourLevel(geometry g: UsageGaugeCardGeometry) -> some View {
        let color = UsageGaugePalette.color(reading.primaryTier, isDark: isDark)
        let fraction = reading.primaryFraction ?? 0
        let end = g.fillEndX(fraction: fraction)
        return ZStack(alignment: .topLeading) {
            if reading.primaryFraction != nil {
                g.fillPath(fraction: fraction).fill(levelFill(color, .level))
                if fraction > 0.02, fraction < 0.995 {
                    bottomTick(color, at: end, bottom: g.bandHeight - g.seamGap / 2)
                }
            }
        }
    }

    /// The 7D bar: one L-shaped block in one flat colour. Only the column's
    /// unfilled part (7D under a tenth) shows a quiet track, never under the fill.
    private func sevenDayBar(geometry g: UsageGaugeCardGeometry) -> some View {
        let color = UsageGaugePalette.color(reading.barTier, isDark: isDark)
        let fraction = reading.barFraction ?? 0
        let filled = g.capFill(fraction: fraction)
        return ZStack(alignment: .topLeading) {
            if g.showsLogo, filled < h {
                color.opacity(isDark ? 0.08 : 0.06)
                    .frame(width: g.columnWidth, height: h - filled)
                    .offset(y: filled)
            }
            g.sevenDayPath(fraction: fraction).fill(levelFill(color, .bar))
        }
    }

    /// One band: the logo column, a gap, then the level; one flat colour.
    /// Its end turns with the card's corners at the top and bottom right.
    private func singleBandLevel(geometry g: UsageGaugeCardGeometry) -> some View {
        let color = UsageGaugePalette.color(reading.primaryTier, isDark: isDark)
        return ZStack(alignment: .topLeading) {
            if let fraction = reading.primaryFraction {
                g.singlePath(fraction: fraction).fill(levelFill(color, .level))
            }
        }
    }

    /// The logo straight on the column, no disc and no separate dot: it takes
    /// the connection colour itself (or the ink colour where none is shown).
    private func logo(geometry g: UsageGaugeCardGeometry) -> some View {
        let size = g.logoGlyphSize
        return DesktopAgentLogo(providerID: providerID,
                                tint: statusColor ?? Color.primary.opacity(0.88),
                                diameter: size)
            .frame(width: size, height: size)
            .offset(x: g.logoCenter.x - size / 2, y: g.logoCenter.y - size / 2)
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
                    resetText(primaryResetText, size: points(0.153))
                }
                Spacer(minLength: 4)
                labelledValue(label: "5H", value: reading.primaryValueText,
                              size: showsLogo ? points(0.31, minimum: 18) : points(0.39, minimum: 18),
                              tint: reading.primaryTier == .low ? primaryColor : nil)
            }
            .padding(.leading, g.textX)
            .padding(.trailing, g.trailingInset)
            .frame(width: size.width, height: g.bandHeight)

            // Bottom band: the 7D reset on the left; "7D" and its value on the right.
            HStack(alignment: .center, spacing: 6) {
                resetText(secondaryText, size: points(0.146))
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
                resetText(primaryResetText, size: points(0.153), mark: reading.lead == .sevenDay)
                if reading.lead == .sevenDay {
                    Text(secondaryText)
                        .font(.system(size: points(0.146), weight: .medium))
                        .foregroundStyle(.primary.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            labelledValue(label: label, value: reading.primaryValueText,
                          size: showsLogo ? points(0.33, minimum: 20) : points(0.417, minimum: 20),
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
        .font(.system(size: points(0.18, minimum: 11), weight: .semibold))
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
                .font(.system(size: points, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(isDark ? 0.72 : 0.62))
        }
        .lineLimit(1)
    }

    /// The number in SF Pro Medium Condensed; its percent sign half the size
    /// (never under 10 pt) and quieter, unless the value is tinted (low).
    private func numberText(_ value: String, size points: CGFloat, color: Color, tinted: Bool) -> Text {
        let hasPercent = value.hasSuffix("%")
        let number = hasPercent ? String(value.dropLast()) : value
        let percentColor = tinted ? color : Color.primary.opacity(0.6)
        return Text(number).font(UsageGaugeTypography.number(size: points)).foregroundColor(color)
            + Text(hasPercent ? "%" : "")
                .font(UsageGaugeTypography.number(size: max(10, points * 0.5)))
                .foregroundColor(percentColor)
    }

    /// "5H", "7D", "API": small, standard width, widely spaced.
    private func periodLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.primary.opacity(isDark ? 0.70 : 0.60))
    }

    /// The big value with its period label just above it, right-aligned.
    private func labelledValue(label: String, value: String, size points: CGFloat, tint: Color?) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            periodLabel(label)
            Group {
                if value == "∞" {
                    Image(systemName: "infinity")
                        .font(.system(size: points * 0.78, weight: .medium))
                        .foregroundStyle(tint ?? Color.primary)
                        .frame(height: points)
                } else {
                    numberText(value, size: points, color: tint ?? Color.primary, tinted: tint != nil)
                }
            }
            .padding(.top, -points * 0.14)
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// "7D 71%": the period beside the small value.
    private func inlineValue(label: String, value: String, size points: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: points * 0.25) {
            periodLabel(label)
            numberText(value, size: points, color: Color.primary.opacity(0.9), tinted: false)
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

    /// "20:20 · 4 小时后": a reset with how far off it is, for the agent page.
    public static func withRelative(_ text: String, resetsAt: Date?, now: Date, language: AppLanguage) -> String {
        guard !text.isEmpty, let resetsAt, resetsAt > now else { return text }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language == .simplifiedChinese ? "zh_CN" : "en_US")
        formatter.unitsStyle = .full
        return "\(text) · \(formatter.localizedString(for: resetsAt, relativeTo: now))"
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
