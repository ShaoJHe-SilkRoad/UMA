import AppKit
import SwiftUI

/// A review sheet of the unified usage gauge on every surface, with fixed
/// sample readings. It is drawn by PreviewRendererTool for design approval
/// and is not used by the app.
public struct UsageGaugePreviewSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let isChinese: Bool

    public init(isChinese: Bool) {
        self.isChinese = isChinese
    }

    struct Sample: Identifiable {
        let id: String
        let providerID: String
        let name: String
        let plan: String
        let caption: String
        let reading: UsageGaugeReading
    }

    private static let now = Date(timeIntervalSince1970: 1_795_600_000)

    private static func window(_ remaining: Double?, hours: Double) -> UsageGaugeWindow {
        UsageGaugeWindow(remainingPercent: remaining, resetsAt: now.addingTimeInterval(hours * 3600))
    }

    private var samples: [Sample] {
        let both = { (five: Double, seven: Double) in
            UsageGaugeReading.make(fiveHour: Self.window(five, hours: 4), sevenDay: Self.window(seven, hours: 80))
        }
        return [
            Sample(id: "claude", providerID: "claude", name: "Claude", plan: "max",
                   caption: t("5H 89% · 7D 63%", "5H 89% · 7D 63%"), reading: both(89, 63)),
            Sample(id: "codex", providerID: "codex", name: "Codex", plan: "plus",
                   caption: t("5H 100% · 7D 100%", "5H 100% · 7D 100%"), reading: both(100, 100)),
            Sample(id: "caution", providerID: "claude", name: "Claude", plan: "max",
                   caption: t("5H 35% · 7D 15%", "5H 35% · 7D 15%"), reading: both(35, 15)),
            Sample(id: "low", providerID: "codex", name: "Codex", plan: "plus",
                   caption: t("5H 12% · 7D 45%", "5H 12% · 7D 45%"), reading: both(12, 45)),
            Sample(id: "gemini", providerID: "gemini", name: "Gemini", plan: "pro",
                   caption: t("No 5H · 7D 95%", "没有 5H · 7D 95%"),
                   reading: .make(fiveHour: nil, sevenDay: Self.window(95, hours: 145))),
            Sample(id: "api", providerID: "codex", name: "Codex", plan: "API",
                   caption: t("No limit (API)", "没有上限（API）"),
                   reading: .make(fiveHour: nil, sevenDay: nil, isUnlimited: true)),
            Sample(id: "outdated", providerID: "claude", name: "Claude", plan: "max",
                   caption: t("Reading outdated", "读数已过期"),
                   reading: .make(fiveHour: Self.window(70, hours: 4), sevenDay: Self.window(40, hours: 80),
                                  isOutdated: true)),
        ]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(t("AUV · Unified usage gauge", "AUV · 统一用量条")).font(.system(size: 17, weight: .bold))
                Spacer()
                Text(t("Sample data · for approval", "示例数据 · 待确认")).font(.caption).foregroundStyle(.secondary)
            }
            legend
            section(t("Menu bar", "菜单栏")) {
                HStack(spacing: 14) {
                    ForEach(["claude", "gemini", "codex"], id: \.self) { id in
                        MenuBarMock(providerID: id, value: id == "gemini" ? "95%" : id == "codex" ? "100%" : "89%")
                    }
                }
            }
            section(t("Desktop Assistant · Minimal", "浮窗 · 极简")) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(samples) { sample in
                        VStack(spacing: 6) {
                            MinimalGaugeMock(sample: sample)
                            captionText(sample.caption)
                        }
                    }
                }
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 4) {
                        MinimalGaugeMock(sample: samples[0])
                        MinimalGaugeMock(sample: samples[1])
                        MinimalGaugeMock(sample: samples[4])
                    }
                    captionText(t("Stacked", "叠放"))
                }
            }
            section(t("Reference size (matches the image)", "对照效果图的大尺寸")) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(470), spacing: 24), count: 2),
                          alignment: .leading, spacing: 16) {
                    ForEach([(60.0, 10.0, "A"), (10, 90, "B"), (80, 70, "C"), (5, 15, "D")], id: \.2) { five, seven, tag in
                        VStack(alignment: .leading, spacing: 6) {
                            BandGaugeMock(sample: UsageGaugePreviewSheet.Sample(
                                id: tag, providerID: "codex", name: "Codex", plan: "plus", caption: "",
                                reading: .make(fiveHour: Self.window(five, hours: 4), sevenDay: Self.window(seven, hours: 80))
                            ), isChinese: false, size: CGSize(width: 470, height: 112), showsName: false)
                            captionText("\(tag). 5H \(Int(five))% · 7D \(Int(seven))%")
                        }
                    }
                }
            }
            section(t("Desktop Assistant · Regular", "浮窗 · 常规")) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(300), spacing: 18), count: 3),
                          alignment: .leading, spacing: 14) {
                    ForEach(samples) { sample in
                        VStack(alignment: .leading, spacing: 6) {
                            BandGaugeMock(sample: sample, isChinese: isChinese, size: CGSize(width: 300, height: 72), showsName: false)
                            captionText(sample.caption)
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 30) {
                section(t("Quick Panel (drop-down)", "下拉页")) {
                    VStack(spacing: 4) {
                        ForEach([samples[0], samples[1], samples[4]]) { sample in
                            BandGaugeMock(sample: sample, isChinese: isChinese, size: CGSize(width: 300, height: 72), showsName: true)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
                }
                section(t("Main window list", "主窗口列表")) {
                    VStack(spacing: 6) {
                        ForEach([samples[0], samples[1], samples[4]]) { sample in
                            BandGaugeMock(sample: sample, isChinese: isChinese, size: CGSize(width: 232, height: 60), showsName: true)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 1080, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var legend: some View {
        let isDark = colorScheme == .dark
        return HStack(spacing: 16) {
            ForEach([
                (UsageGaugeTier.plenty, t("> 50% left", "剩余 > 50%")),
                (.caution, t("20–50% left", "剩余 20–50%")),
                (.low, t("< 20% left", "剩余 < 20%")),
                (.unlimited, t("No limit / 7D in the big block", "没有上限 / 大块显示 7D 时的细条")),
                (.outdated, t("Outdated reading", "读数已过期")),
            ], id: \.1) { tier, label in
                HStack(spacing: 6) {
                    Circle().fill(UsageGaugePalette.color(tier, isDark: isDark)).frame(width: 9, height: 9)
                    Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content()
        }
    }

    private func captionText(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }
}

// MARK: - Mocks

private struct GaugeLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    let providerID: String
    let diameter: CGFloat

    var body: some View {
        DesktopAgentLogo(
            providerID: providerID,
            tint: AgentConnectionIndicatorPalette.connected(isDark: colorScheme == .dark,
                                                            increasedLightContrast: true),
            diameter: diameter
        )
    }
}

private struct GaugeGlass: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Rectangle().fill(.ultraThinMaterial)
            .overlay { colorScheme == .light ? Color.black.opacity(0.07) : Color.clear }
    }
}

private func gaugeFillOpacity(_ scheme: ColorScheme) -> Double {
    DesktopAssistantTintOpacity.value(isDark: scheme == .dark, reduceTransparency: false, increaseContrast: false)
}

private struct MenuBarMock: View {
    let providerID: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            DesktopAgentLogo(providerID: providerID, tint: .primary, diameter: 15)
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
    }
}

private struct MinimalGaugeMock: View {
    @Environment(\.colorScheme) private var colorScheme
    let sample: UsageGaugePreviewSheet.Sample
    private let height: CGFloat = 30
    private let left: CGFloat = 15
    private let right: CGFloat = 7

    var body: some View {
        HStack(spacing: 3) {
            GaugeLogo(providerID: sample.providerID, diameter: 18)
            Text(sample.reading.primaryValueText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: height)
        .background {
            GaugeGlass().overlay {
                UsageGaugeBackground(reading: sample.reading, leftRadius: left, rightRadius: right,
                                     barWidth: 2.5, fillOpacity: gaugeFillOpacity(colorScheme))
            }
        }
        .clipShape(UsageGaugeShape(leftRadius: left, rightRadius: right))
    }
}

private struct BandGaugeMock: View {
    let sample: UsageGaugePreviewSheet.Sample
    let isChinese: Bool
    let size: CGSize
    let showsName: Bool
    var valueColumnWidth: CGFloat? = nil

    var body: some View {
        let language: AppLanguage = isChinese ? .simplifiedChinese : .english
        UsageGaugeCard(
            reading: sample.reading,
            providerID: sample.providerID,
            size: size,
            title: showsName ? "\(sample.name) · \(sample.plan)" : nil,
            primaryResetText: UsageGaugeText.primaryReset(sample.reading, language: language),
            secondaryText: UsageGaugeText.secondary(sample.reading, language: language),
            statusColor: AgentConnectionIndicatorPalette.connected(isDark: true)
        )
    }
}
