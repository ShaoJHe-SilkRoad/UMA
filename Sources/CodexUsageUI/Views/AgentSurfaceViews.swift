import AppKit
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

    var body: some View {
        if let fraction = CompactUsageFillPolicy.fraction(for: remainingPercent) {
            GeometryReader { proxy in
                LowRemainingUsagePolicy.color(for: LowRemainingUsagePolicy.assessment(
                    providerID: providerID, admittedPlan: admittedPlan, remainingPercent: remainingPercent
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
                    if let fraction = CompactUsageFillPolicy.fraction(for: remainingPercent) {
                        Capsule()
                            .fill(tint.opacity(0.82))
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
        .frame(height: 11)
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
    static let horizontalPadding: CGFloat = 22
    static let moduleSpacing: CGFloat = 12
    static let minimumTwoColumnWidth: CGFloat = 660

    static func columnCount(for availableWidth: CGFloat) -> Int {
        availableWidth >= minimumTwoColumnWidth ? 2 : 1
    }
}

private struct AgentWorkspaceModuleSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(UMAVisualStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(UMAVisualStyle.separator.opacity(0.65), lineWidth: 0.5)
            }
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
        standardContent
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background { rowBackground }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .help(displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: verticalContentSpacing) {
            HStack(alignment: .top, spacing: 9) {
                if showsConnectivity { providerMark }
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(secondaryLine)
                        .font(.system(size: secondaryFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !usesFullWidthName {
                    Text(primaryDisplayText)
                        .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(valueColor)
                }
            }
            if usesFullWidthName {
                Text(primaryDisplayText)
                    .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
        }
    }

    // Keep the complete canonical label visible in the narrow rail; long
    // names get the full text width while the remaining value stays visible.
    private var usesFullWidthName: Bool { displayName.count > 32 }

    private var horizontalPadding: CGFloat { style == .quickPanel ? 10 : 9 }
    private var verticalContentSpacing: CGFloat { 7 }
    private var secondaryFontSize: CGFloat { 12 }
    private var verticalPadding: CGFloat { style == .quickPanel ? 8 : 7 }
    private var valueSize: CGFloat { 16 }

    private var secondaryLine: String {
        var components = [statusLabel]
        if let plan = provider.planLabel, !plan.isEmpty {
            components.append(plan)
        }
        if let quota = provider.primaryQuota {
            components.append(quota.compactLabel)
        } else {
            components.append(localized("No current usage", "暂无当前用量"))
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

    private var valueColor: Color {
        provider.health == .error ? .red : .primary
    }

    private var accessibilityLabel: String {
        let quota = provider.primaryQuota.map {
            "\($0.compactLabel), \($0.displayText) \(localized("remaining", "剩余"))"
        }
            ?? localized("usage unavailable", "用量不可用")
        return "\(displayName), \(statusLabel), \(quota)"
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
        DesktopAgentLogo(providerID: provider.id.rawValue, tint: statusColor, diameter: 24)
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
            if showsRemainingRail {
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
                VStack(spacing: 2) {
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
        .environment(\.locale, store.language.locale)
        .accessibilityIdentifier("uma.quick.surface")
    }

    private var providers: [ProviderProductState] {
        store.productInventory.quickPanelProviders
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: openMain) {
                Label("AUV", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(localized("Open AUV", "打开 AUV"))
            .accessibilityLabel(localized("Open AUV", "打开 AUV"))
            Spacer()
            headerButton(localized("Scan All", "全部扫描"), "sparkle.magnifyingglass", scanAll)
            headerButton(localized("Refresh All", "全部刷新"), "arrow.clockwise", refreshAll)
                .disabled(!store.allowsManualRefresh)
            headerButton(localized("Desktop Wizard", "桌面向导"), "wand.and.stars", toggleWizard)
            headerButton(localized("Settings", "设置"), "gearshape", openSettings)
            HESectoriumStatusControl(isChinese: store.language == .simplifiedChinese)
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
            ? "本地 API 等效估算 · 7天"
            : "Local API equivalent estimate · 7D"
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
    @ObservedObject private var store: UsageStore
    public let providerID: ProviderProductID
    private let refresh: () -> Void
    private let connectCodex: () -> Void
    private let disconnectCodex: () -> Void
    private let claudeControlState: () -> ClaudeAgentControlState
    private let connectClaude: () -> Void
    private let claudeAccuracySync: () -> Void
    private let referenceDate: Date?
    @State private var showingClaudeConsent = false

    public init(
        store: UsageStore,
        providerID: ProviderProductID,
        refresh: @escaping () -> Void,
        connectCodex: @escaping () -> Void,
        disconnectCodex: @escaping () -> Void,
        claudeControlState: @escaping () -> ClaudeAgentControlState,
        connectClaude: @escaping () -> Void,
        claudeAccuracySync: @escaping () -> Void,
        referenceDate: Date? = nil
    ) {
        self.store = store
        self.providerID = providerID
        self.refresh = refresh
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
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if providerID == .codex {
                        codexDashboard(for: geometry.size.width)
                    } else {
                        standardWorkspace(for: geometry.size.width)
                    }
                }
                .padding(.horizontal, AgentWorkspaceLayoutPolicy.horizontalPadding)
                .padding(.vertical, 12)
            }
        }
        .background(UMAVisualStyle.canvas)
        .accessibilityIdentifier("uma.agent.workspace.\(providerID.rawValue)")
        .alert(
            localized("Enable Claude Local Smart?", "启用 Claude 本地智能？"),
            isPresented: $showingClaudeConsent
        ) {
            Button(localized("Cancel", "取消"), role: .cancel) {}
            Button(localized("Enable", "启用"), action: connectClaude)
        } message: {
            Text(localized(
                "AUV reads only approved local usage metadata. Prompt, response, session, credential, cookie, token, and Keychain content is never retained or transmitted.",
                "AUV 仅读取已批准的本地用量元数据；不会保留或传输提示、回复、会话、凭据、Cookie、令牌或钥匙串内容。"
            ))
        }
    }

    private var provider: ProviderProductState? { store.productInventory.provider(providerID) }

    private var codexProjection: CodexDashboardProjection {
        CodexDashboardProjection(snapshot: store.snapshot, provider: provider)
    }

    @ViewBuilder private func standardWorkspace(for width: CGFloat) -> some View {
        LazyVGrid(
            columns: workspaceColumns(for: width),
            alignment: .leading,
            spacing: AgentWorkspaceLayoutPolicy.moduleSpacing
        ) {
            usageModule
            connectionModule
            controlsModule
            if providerID == .claude { claudeSmartModule }
            diagnosticsModule
        }
    }

    /// The rail owns the primary remaining fill; the detail view keeps quota
    /// states visible while giving the account metrics and dated trend priority.
    private func codexDashboard(for width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metricRow(for: width)
            quotaSummary(for: width)
            trendGapCard
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    connectionModule.frame(maxWidth: .infinity, alignment: .leading)
                    activityDashboardCard.frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: 10) { connectionModule; activityDashboardCard }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("uma.agent.codex.dashboard")
    }

    private var codexHeaderActions: some View {
        HStack(spacing: 8) {
            Button(localized("Refresh", "刷新"), action: refresh)
                .disabled(!store.allowsManualRefresh)
            if provider?.connection == .connected || provider?.connection == .transitional {
                Button(localized("Disconnect", "断开连接"), action: disconnectCodex)
            } else {
                Button(localized("Connect", "连接"), action: connectCodex)
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.small)
        .accessibilityIdentifier("uma.agent.codex.header-actions")
    }

    private func quotaSummary(for width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if width >= 560 {
                HStack(alignment: .top, spacing: 12) {
                    quotaSummarySegment(kind: .sevenDay, label: localized("7D", "7天"))
                    quotaSummarySegment(kind: .fiveHour, label: localized("5H", "5小时"))
                }
            } else {
                VStack(spacing: 7) {
                quotaSummarySegment(kind: .sevenDay, label: localized("7D", "7天"))
                quotaSummarySegment(kind: .fiveHour, label: localized("5H", "5小时"))
                }
            }
        }
        .accessibilityIdentifier("uma015.codex.quota-summary")
        .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.quota-bounds"))
    }

    private func quotaSummarySegment(kind: ProviderProductQuotaKind, label: String) -> some View {
        let quota = kind == .fiveHour ? codexProjection.fiveHour : codexProjection.sevenDay
        let percent = quota.state.ringPercent
        let quotaText = quota.displayText(language: store.language)
        let tint = LowRemainingUsagePolicy.color(for: LowRemainingUsagePolicy.assessment(
            providerID: providerID.rawValue, admittedPlan: provider?.planLabel,
            remainingPercent: percent))
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(label) \(localized("remaining", "剩余"))")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Text(quotaText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            AgentRemainingQuotaBar(remainingPercent: percent, tint: tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(localized("remaining", "剩余")): \(quotaText)")
        .accessibilityIdentifier("uma.agent.codex.quota.\(kind == .fiveHour ? "five-hour" : "seven-day")")
    }

    @State private var showsHistoryCaveat = false

    private var trendGapCard: some View {
        module(historyModuleTitle, systemImage: "chart.bar") {
            VStack(alignment: .leading, spacing: 7) {
                if case let .accountDailyBuckets(buckets, _) = codexProjection.historyAvailability {
                    accountDailyBars(buckets)
                } else {
                    Text(historyHeading)
                        .font(.system(size: 13, weight: .medium))
                    Text(historyDetail)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(historySourceLine)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                DisclosureGroup(
                    localized("Period and data caveats", "周期与数据说明"),
                    isExpanded: $showsHistoryCaveat
                ) {
                    Text(historyFootnote)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
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
        return HStack(alignment: .bottom, spacing: 7) {
            ForEach(shown) { bucket in
                VStack(spacing: 4) {
                    Text(bucket.tokens.map { $0.formatted(.number.notation(.compactName)) } ?? "—")
                        .font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(bucket.tokens == nil ? Color.secondary.opacity(0.22) : Color.accentColor.opacity(0.78))
                        .frame(height: bucket.tokens == 0 ? 0 : max(4, 128 * CGFloat(Double(bucket.tokens ?? 0) / Double(maximum))))
                    Text(String(bucket.day.suffix(5)))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(bucket.tokens.map { "\(bucket.day): \($0) tokens" } ?? "\(bucket.day): unknown tokens")
            }
        }
        .frame(height: 171, alignment: .bottom)
        .accessibilityIdentifier("uma.agent.codex.daily-plot")
        .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.plot-bounds"))
    }

    private var historyDetail: String {
        CodexDashboardPresentation.historyDetail(codexProjection.historyAvailability, language: store.language)
    }

    private func metricRow(for width: CGFloat) -> some View {
        let metrics = codexProjection.metrics
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8, alignment: .top), count: width >= 680 ? 3 : 1)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            dashboardMetric(metrics.first(where: { $0.id == "week" }), title: localized("Account 7D tokens", "账户7天令牌"), anchor: "uma015.codex.metric-week")
            dashboardMetric(metrics.first(where: { $0.id == "total" }), title: localized("Account lifetime tokens", "账户累计令牌"), anchor: "uma015.codex.metric-total")
            dashboardMetric(metrics.first(where: { $0.id == "api-cost-seven-days" }), title: CodexDashboardPresentation.localEstimateTitle(language: store.language), anchor: "uma015.codex.metric-local", isLocalEstimate: true)
        }
        .accessibilityIdentifier("uma.agent.codex.metrics")
        .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.metric-bounds"))
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
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(isLocalEstimate ? 2 : 1)
                .fixedSize(horizontal: false, vertical: isLocalEstimate)
                .help(title)
                .accessibilityIdentifier("\(anchor)-title")
            Text(CodexDashboardPresentation.metricValue(metric, state: sourceState))
                .font(.system(size: 18, weight: .semibold)).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .background(AgentWorkspaceGeometryAnchor(identifier: "\(anchor)-value"))
            if isLocalEstimate, sourceState == .current,
               let coverage = metric?.coveragePercent {
                DisclosureGroup(localized("Coverage \(coverage)% · details", "覆盖 \(coverage)% · 说明")) {
                    Text(localized(
                        "Local ledger API-equivalent estimate, 7D; lifetime priced-token coverage \(coverage)%. The 7D period may include a partial current day.",
                        "本地账本 API 等效估算，7天；累计已定价令牌覆盖率 \(coverage)%。7天周期可能包含当天的部分数据。"
                    ))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
                .lineLimit(1)
                .help(localized("Lifetime priced-token coverage \(coverage)%; 7D may include a partial current day", "累计已定价令牌覆盖 \(coverage)%；7天可能含未完结的今天"))
            } else {
                Text(status)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(UMAVisualStyle.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(UMAVisualStyle.separator.opacity(0.65), lineWidth: 0.5)
        }
        .background(AgentWorkspaceGeometryAnchor(identifier: anchor))
    }

    private var activityDashboardCard: some View {
        module(localized("Recent local activity", "最近本地活动"), systemImage: "clock.arrow.circlepath") {
            let activity = store.snapshot.recentTasks
            switch CodexDashboardPresentation.activityState(snapshot: store.snapshot) {
            case .unavailable:
                Text(localized("Local activity source unavailable.", "本地活动来源不可用。"))
                    .font(.callout).foregroundStyle(.secondary)
            case .empty:
                Text(localized("No recent allowlisted local activity metadata.", "暂无允许范围内的本地活动元数据。"))
                    .font(.callout).foregroundStyle(.secondary)
            case .stale, .current:
                if CodexDashboardPresentation.activityState(snapshot: store.snapshot) == .stale {
                    Text(localized("Retained local activity is stale.", "保留的本地活动已过期。"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(activity.prefix(4)) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(item.title)
                            Text(item.time).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Text(item.tokenText).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.activity-bounds"))
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            DesktopAgentLogo(providerID: providerID.rawValue,
                             tint: workspaceLogoColor, diameter: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(providerID.displayName)
                    .font(.title2.weight(.semibold))
                Text(connectionLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if providerID == .codex { codexHeaderActions }
            if providerID != .codex {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(provider?.primaryDisplayText ?? "—")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(provider?.primaryQuota?.compactLabel ?? localized("No current usage", "暂无当前用量"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.bottom, 3)
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
                    Text(localized("No current usage", "暂无当前用量")).font(.callout.weight(.medium))
                    Text(localized(
                        "Connect or refresh this agent to retrieve qualified usage data.",
                        "连接或刷新此智能体以获取合格的用量数据。"
                    ))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private var missingFiveHourMessage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("5H")
                .font(.callout.weight(.semibold))
            Spacer(minLength: 12)
            Text(localized("Limit not reported", "未报告限额"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func quotaRow(_ quota: ProviderProductQuotaState) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(quota.compactLabel).font(.headline)
                        Text(quotaDetailLabel(quota))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(quota.displayText)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            AgentRemainingQuotaBar(
                remainingPercent: quota.value.remainingPercent,
                tint: LowRemainingUsagePolicy.color(for: LowRemainingUsagePolicy.assessment(
                    providerID: providerID.rawValue, admittedPlan: provider?.planLabel,
                    remainingPercent: quota.value.remainingPercent)))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var connectionModule: some View {
        module(localized("Connection & Source", "连接与来源"), systemImage: "link") {
            VStack(spacing: 7) {
                HStack(spacing: 6) {
                    Circle().fill(workspaceLogoColor).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    factRow(localized("Status", "状态"), connectionLabel)
                }
                factRow(localized("Source", "来源"), sourceLabel)
                factRow(localized("Freshness", "新鲜度"), freshnessLabel)
                if let planLabel { factRow(localized("Plan", "方案"), planLabel) }
                if let capturedAt = provider?.capturedAt {
                    HStack {
                        Text(localized("Last successful update", "上次成功更新")).foregroundStyle(.secondary)
                        Spacer()
                        Text(relativeUpdateDescription(since: capturedAt)).monospacedDigit()
                    }
                }
            }
            .font(.callout)
        }
        .background(AgentWorkspaceGeometryAnchor(identifier: "uma015.codex.source-bounds"))
    }

    private var controlsModule: some View {
        module(localized("Agent Controls", "智能体控制"), systemImage: "slider.horizontal.3") {
            HStack(spacing: 8) {
                Button(localized("Refresh", "刷新"), action: refresh)
                    .disabled(!store.allowsManualRefresh)
                if providerID == .codex {
                    if provider?.connection == .connected || provider?.connection == .transitional {
                        Button(localized("Disconnect", "断开连接"), action: disconnectCodex)
                    } else {
                        Button(localized("Connect", "连接"), action: connectCodex)
                            .buttonStyle(.borderedProminent)
                    }
                } else if providerID == .claude {
                    switch claudeControlState() {
                    case .consentRequired:
                        Button(localized("Enable Local Smart", "启用本地智能")) {
                            showingClaudeConsent = true
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("uma.agent.claude.enable-local-smart")
                    case .localSmartRepairRequired:
                        Button(localized("Repair Local Smart", "修复本地智能"), action: connectClaude)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("uma.agent.claude.repair-local-smart")
                    case .statusLineConfigurationUnavailable(let issue):
                        VStack(alignment: .leading, spacing: 4) {
                            Button(localized("Connect Claude Code", "连接 Claude Code")) {}
                                .disabled(true)
                            Text(issue == .developmentIsolation
                                ? localized("Claude Code setup is unavailable in this development build.", "此开发版本不配置 Claude Code。")
                                : localized("Install AUV in Applications or Desktop to connect Claude Code.", "请将 AUV 安装到 Applications 或桌面后连接 Claude Code。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .accuracyReady:
                        Button(localized("Accuracy Sync", "精确同步"), action: claudeAccuracySync)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("uma.agent.claude.accuracy-sync")
                    case .accuracyInProgress:
                        Button(localized("Accuracy Syncing…", "正在精确同步…")) {}
                            .disabled(true)
                            .accessibilityIdentifier("uma.agent.claude.accuracy-in-progress")
                    case .companionStarting:
                        Button(localized("Companion starting…", "浏览器伴侣正在启动…")) {}
                            .disabled(true)
                            .accessibilityIdentifier("uma.agent.claude.accuracy-unavailable")
                    case .companionUpdateRequired:
                        Button(localized("Companion update required", "需要更新浏览器伴侣")) {}
                            .disabled(true)
                            .accessibilityIdentifier("uma.agent.claude.accuracy-unavailable")
                    case .onlineVerificationUnavailable:
                        Button(localized("Online verification unavailable", "在线验证不可用")) {}
                            .disabled(true)
                            .accessibilityIdentifier("uma.agent.claude.accuracy-unavailable")
                    }
                }
                Spacer()
            }
        }
    }

    private var codexActivityModule: some View {
        module(localized("Recent Local Activity", "最近本地活动"), systemImage: "clock.arrow.circlepath") {
            SharedBasicUsageSummaryView(
                presentation: .make(snapshot: store.snapshot, provider: provider),
                language: store.language,
                showsQuotaWindows: false
            )
        }
    }

    private var claudeSmartModule: some View {
        module(localized("Local Smart & Accuracy", "本地智能与精确同步"), systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 7) {
                Label(claudeSmartLabel, systemImage: "lock.shield")
                    .font(.callout.weight(.medium))
                Text(localized(
                    "Local Smart and one-shot Accuracy Sync retain only approved usage metadata. Prompts, responses, credentials, and raw page content do not enter AUV.",
                    "本地智能和一次性精确同步仅保留已批准的用量元数据；提示、回复、凭据和原始页面内容不会进入 AUV。"
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var diagnosticsModule: some View {
        module(localized("Privacy & Advanced Diagnostics", "隐私与高级诊断"), systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 6) {
                factRow(localized("Connection", "连接"), connectionLabel)
                factRow(localized("Source health", "来源健康状态"), diagnosticLabel)
                Text(localized("Diagnostics use bounded status classifications only.", "诊断仅使用有界状态分类。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func module<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.headline)
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

    private var claudeSmartLabel: String {
        switch provider?.sourceSummary {
        case .localSmartEstimate:
            localized("Estimated local usage is available", "已有本地用量估算")
        case .localSmartExact, .accuracySync, .combinedSanitized:
            localized("Exact usage anchor is available", "已有精确用量锚点")
        default:
            localized(
                "Accuracy Sync is available when the Companion is ready",
                "浏览器伴侣就绪后可使用精确同步"
            )
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
            let formatter = DateFormatter(); formatter.locale = store.language.locale; formatter.dateStyle = .medium; formatter.timeStyle = .short
            return localized("Future observation (\(formatter.string(from: date)))", "未来观测（\(formatter.string(from: date))）")
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
            ? "桌面向导位置已重置。"
            : "Desktop Wizard position reset."
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
        panel.nameFieldStringValue = "UMA-sanitized-diagnostics.json"
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

public enum GlobalSettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case appearance = "Appearance"
    case desktopWizard = "Desktop Wizard"
    case privacy = "Privacy & Data"
    case hesectorium = "HESectorium"
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
    private let hesectoriumStore: HESectoriumStore?

    public init(
        preferences: ApplicationPreferences,
        store: UsageStore,
        navigation: GlobalSettingsNavigationState,
        dataPaths: ApplicationDataPaths = .current(),
        hesectoriumStore: HESectoriumStore? = nil
    ) {
        self.navigation = navigation
        self.hesectoriumStore = hesectoriumStore
        _model = StateObject(
            wrappedValue: GlobalSettingsViewModel(
                preferences: preferences, store: store, dataPaths: dataPaths
            )
        )
    }

    public var body: some View {
        GeometryReader { viewport in
            HStack(spacing: 0) {
                List(GlobalSettingsPane.allCases, selection: $navigation.pane) { item in
                    HStack(spacing: 7) {
                        Image(systemName: symbol(item))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text(paneTitle(item))
                            .font(.system(size: 13))
                    }
                    .tag(item)
                }
                .listStyle(.sidebar)
                .frame(width: 180)
                .accessibilityIdentifier("uma.settings.sidebar")

                Divider().frame(width: 1)

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

    @ViewBuilder
    private var settingsDetail: some View {
        switch navigation.pane {
        case .hesectorium:
                HESectoriumSettingsView(isChinese: model.language == .simplifiedChinese, store: hesectoriumStore)
        default:
            standardSettingsDetail
        }
    }

    private var standardSettingsDetail: some View {
        Form {
            switch navigation.pane {
            case .general:
                settingsSection(
                    title: localized("General", "通用"),
                    subtitle: localized("Application behavior", "应用行为")
                ) {
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
                            .font(.caption)
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
                            .font(.caption)
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
                    Toggle(
                        localized("Automatic background refresh", "自动后台刷新"),
                        isOn: Binding(
                            get: { model.automaticBackgroundRefresh },
                            set: model.setAutomaticBackgroundRefresh
                        )
                    )
                    .accessibilityIdentifier("uma.settings.general.background-refresh")
                    Picker(
                        localized("Refresh interval", "刷新间隔"),
                        selection: Binding(
                            get: { model.backgroundRefreshInterval },
                            set: model.setBackgroundRefreshInterval
                        )
                    ) {
                        Text(localized("15 minutes", "15 分钟"))
                            .tag(UMABackgroundRefreshInterval.fifteenMinutes)
                        Text(localized("30 minutes", "30 分钟"))
                            .tag(UMABackgroundRefreshInterval.thirtyMinutes)
                        Text(localized("60 minutes", "60 分钟"))
                            .tag(UMABackgroundRefreshInterval.sixtyMinutes)
                    }
                    .disabled(!model.automaticBackgroundRefresh)
                    .accessibilityIdentifier("uma.settings.general.refresh-interval")
                    Toggle(
                        localized("Refresh after Mac wakes", "Mac 唤醒后刷新"),
                        isOn: Binding(
                            get: { model.refreshOnWake },
                            set: model.setRefreshOnWake
                        )
                    )
                    .accessibilityIdentifier("uma.settings.general.refresh-on-wake")
                    Picker(
                        localized("Language", "语言"),
                        selection: Binding(
                            get: { model.language },
                            set: model.setLanguage
                        )
                    ) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .accessibilityIdentifier("uma.settings.general.language")
                    settingFact(
                        localized("Agent setup", "智能体设置"),
                        localized("Setup and repair actions live in each Agent workspace.", "设置和修复操作位于各智能体工作区。")
                    )
                }
            case .appearance:
                settingsSection(
                    title: localized("Appearance", "外观"),
                    subtitle: localized("System appearance", "系统外观")
                ) {
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
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("uma.settings.appearance.theme")
                    Toggle(
                        localized("Show remaining percentage in menu bar", "在菜单栏显示剩余百分比"),
                        isOn: Binding(
                            get: { model.menuBarShowsRemaining },
                            set: model.setMenuBarShowsRemaining
                        )
                    )
                    .accessibilityIdentifier("uma.settings.appearance.menu-value")
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
                    settingFact(
                        localized("Accessibility", "辅助功能"),
                        localized("Reduce Transparency, Increase Contrast, and Reduce Motion are respected automatically.", "自动遵循降低透明度、提高对比度和减弱动态效果设置。")
                    )
                }
            case .desktopWizard:
                settingsSection(
                    title: localized("Desktop Wizard", "桌面向导"),
                    subtitle: localized("A compact usage surface that stays available on the desktop", "常驻桌面的紧凑用量视图")
                ) {
                    Toggle(
                        localized("Show Desktop Wizard", "显示桌面向导"),
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
                    .pickerStyle(.segmented)
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
                    Button(
                        localized("Reset Position", "重置位置"),
                        action: model.resetAssistantPosition
                    )
                    .accessibilityIdentifier("uma.settings.wizard.reset-position")
                }
            case .hesectorium:
                // This pane owns its own scrolling Form above.
                EmptyView()
            case .privacy:
                settingsSection(
                    title: localized("Privacy & Data", "隐私与数据"),
                    subtitle: localized("Usage data stays bounded to each approved source", "用量数据仅限于已批准的来源")
                ) {
                    settingFact(
                        localized("Usage data", "用量数据"),
                        localized("AUV retains only allowlisted usage metadata.", "AUV 仅保留允许范围内的用量元数据。")
                    )
                    settingFact(
                        localized("Retained state", "保留状态"),
                        localized(
                            "Only admitted bounded usage state is retained; stale and unsupported values remain explicitly labeled.",
                            "仅保留已批准的有限用量状态；过期和不支持的值会明确标注。"
                        )
                    )
                    settingFact(
                        localized("Agent access", "智能体访问"),
                        localized("Authentication and repair remain inside the selected Agent workspace.", "认证和修复操作仅位于所选智能体工作区。")
                    )
                    settingFact(
                        localized("Credentials", "凭据"),
                        localized("Passwords, tokens, cookies, and conversation content are not retained.", "不会保留密码、令牌、Cookie 或对话内容。")
                    )
                    HStack {
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
                    if let status = model.dataActionStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("uma.settings.privacy.action-status")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(14)
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
            .padding(.bottom, 6)
        }
    }

    private func settingFact(_ title: String, _ detail: String) -> some View {
        LabeledContent(title) {
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ pane: GlobalSettingsPane) -> String {
        switch pane {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .desktopWizard: "wand.and.stars"
        case .privacy: "hand.raised"
        case .hesectorium: "externaldrive"
        }
    }

    private func paneTitle(_ pane: GlobalSettingsPane) -> String {
        switch pane {
        case .general: localized("General", "通用")
        case .appearance: localized("Appearance", "外观")
        case .desktopWizard: localized("Desktop Wizard", "桌面向导")
        case .privacy: localized("Privacy & Data", "隐私与数据")
        case .hesectorium: "HESectorium"
        }
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        model.language == .simplifiedChinese ? chinese : english
    }
}
