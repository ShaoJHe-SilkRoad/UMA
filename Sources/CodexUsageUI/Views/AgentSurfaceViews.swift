import SwiftUI

enum RemainingUsageColorBand: Equatable, Sendable {
    case green
    case yellowGreen
    case red
}

enum RemainingUsageVisualPolicy {
    static func band(for percent: Double) -> RemainingUsageColorBand {
        if percent < 10 { return .red }
        if percent < 30 { return .yellowGreen }
        return .green
    }

    static func color(for percent: Double) -> Color {
        switch band(for: percent) {
        case .green:
            .green
        case .yellowGreen:
            // Keep the caution band visibly green. The slight warm shift is a
            // low-quota cue, not a provider/accent color or accuracy signal.
            Color(red: 0.31, green: 0.74, blue: 0.32)
        case .red:
            .red
        }
    }

    static func visibleFraction(for percent: Double, width: CGFloat) -> Double {
        let fraction = min(1, max(0, percent / 100))
        return max(fraction, min(1, 2 / max(1, width)))
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

public struct AgentGlanceRow: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let provider: ProviderProductState
    public let style: AgentGlanceRowStyle
    public let selected: Bool
    public let language: AppLanguage
    public let showsReset: Bool
    private let referenceDate: Date?

    public init(
        provider: ProviderProductState,
        style: AgentGlanceRowStyle,
        selected: Bool = false,
        language: AppLanguage = .english,
        showsReset: Bool = true,
        referenceDate: Date? = nil
    ) {
        self.provider = provider
        self.style = style
        self.selected = selected
        self.language = language
        self.showsReset = showsReset
        self.referenceDate = referenceDate
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
            HStack(spacing: 9) {
                providerMark
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(secondaryLine)
                        .font(.system(size: secondaryFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(primaryDisplayText)
                    .font(.system(size: valueSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
            if let reset = resetDate {
                Text(language.resetDescription(for: reset, now: displayNow))
                    .font(.system(size: resetFontSize))
                    .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
        }
    }

    private var horizontalPadding: CGFloat { style == .quickPanel ? 10 : 9 }
    private var verticalContentSpacing: CGFloat { 7 }
    private var secondaryFontSize: CGFloat { 10.5 }
    private var resetFontSize: CGFloat { 10 }
    private var verticalPadding: CGFloat { style == .quickPanel ? 8 : 7 }
    private var valueSize: CGFloat { 17 }

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
        case .connected: .green
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
        let reset = resetDate.map {
            ", \(language.resetDescription(for: $0, now: displayNow))"
        } ?? ""
        return "\(provider.displayName), \(statusLabel), \(quota)\(reset)"
    }

    private var displayName: String {
        provider.displayName
    }

    private var primaryDisplayText: String {
        provider.primaryDisplayText
    }

    private var remainingPercent: Double? {
        provider.primaryQuota?.value.remainingPercent
    }

    private var resetDate: Date? {
        guard showsReset else { return nil }
        return provider.primaryQuota?.resetsAt
    }

    private var displayNow: Date { referenceDate ?? Date() }

    private func localized(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }

    private var providerMarkText: String {
        let words = displayName.split(whereSeparator: \.isWhitespace)
        if words.count > 1 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined()
        }
        return words.first?.first.map(String.init) ?? "?"
    }

    private var providerMark: some View {
        ZStack {
            Circle()
                .stroke(statusColor, lineWidth: 1.5)
            Text(providerMarkText)
                .font(
                    .system(
                        size: providerMarkText.count > 1 ? 9 : 11,
                        weight: .semibold
                    )
                )
                .foregroundStyle(statusColor)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var rowBackground: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .opacity(style == .quickPanel ? 0.34 : 0.52)
            remainingTint
            if selected {
                Color.primary.opacity(0.055)
            }
        }
    }

    @ViewBuilder
    private var remainingTint: some View {
        if let percent = remainingPercent {
            GeometryReader { proxy in
                let visibleFraction = RemainingUsageVisualPolicy.visibleFraction(
                    for: percent,
                    width: proxy.size.width
                )
                let stops = DesktopAssistantTintGeometry.stops(
                    remainingFraction: visibleFraction,
                    width: proxy.size.width
                )
                let tint = RemainingUsageVisualPolicy.color(for: percent).opacity(
                    DesktopAssistantTintOpacity.value(
                        isDark: colorScheme == .dark,
                        reduceTransparency: reduceTransparency,
                        increaseContrast: colorSchemeContrast == .increased
                    )
                )
                if visibleFraction >= 1 {
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
            .accessibilityHidden(true)
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
                        "Connect an agent in UMA or scan this Mac again.",
                        "请在 UMA 中连接智能体，或重新扫描这台 Mac。"
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Button(localized("Open UMA", "打开 UMA"), action: openMain)
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
                Label("UMA", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(localized("Open UMA", "打开 UMA"))
            .accessibilityLabel(localized("Open UMA", "打开 UMA"))
            Spacer()
            headerButton(localized("Scan All", "全部扫描"), "sparkle.magnifyingglass", scanAll)
            headerButton(localized("Refresh All", "全部刷新"), "arrow.clockwise", refreshAll)
                .disabled(!store.allowsManualRefresh)
            headerButton(localized("Desktop Wizard", "桌面向导"), "wand.and.stars", toggleWizard)
            headerButton(localized("Settings", "设置"), "gearshape", openSettings)
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
    private let preferences: ApplicationPreferences
    private var observation: ApplicationPreferences.Observation?

    init(preferences: ApplicationPreferences) {
        self.preferences = preferences
        showsReset = preferences.value(for: UMAApplicationPreferenceKeys.quickPanelShowsReset)
        observation = preferences.observe { [weak self] change in
            guard change.key == UMAApplicationPreferenceKeys.quickPanelShowsReset.name,
                  let self else { return }
            showsReset = preferences.value(for: UMAApplicationPreferenceKeys.quickPanelShowsReset)
        }
    }
}

public struct AgentWorkspaceSurface: View {
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                sectionDivider
                usageSection
                sectionDivider
                connectionSection
                sectionDivider
                controlsSection
                if providerID == .codex {
                    sectionDivider
                    codexActivitySection
                } else if providerID == .claude {
                    sectionDivider
                    claudeSmartSection
                }
                sectionDivider
                diagnosticsSection
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("uma.agent.workspace.\(providerID.rawValue)")
        .alert(
            localized("Enable Claude Local Smart?", "启用 Claude 本地智能？"),
            isPresented: $showingClaudeConsent
        ) {
            Button(localized("Cancel", "取消"), role: .cancel) {}
            Button(localized("Enable", "启用"), action: connectClaude)
        } message: {
            Text(localized(
                "UMA reads only approved local usage metadata. Prompt, response, session, credential, cookie, token, and Keychain content is never retained or transmitted.",
                "UMA 仅读取已批准的本地用量元数据；不会保留或传输提示、回复、会话、凭据、Cookie、令牌或钥匙串内容。"
            ))
        }
    }

    private var provider: ProviderProductState? { store.productInventory.provider(providerID) }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(providerID.displayName)
                    .font(.title2.weight(.semibold))
                Text(connectionLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(provider?.primaryDisplayText ?? "—")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(provider?.primaryQuota?.compactLabel ?? localized("No current usage", "暂无当前用量"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 3)
    }

    @ViewBuilder private var usageSection: some View {
        section(localized("Usage", "用量")) {
            if let provider, !provider.quotas.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(provider.quotas.enumerated()), id: \.element.id) { index, quota in
                        quotaRow(quota)
                        if index < provider.quotas.count - 1 { Divider() }
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

    private func quotaRow(_ quota: ProviderProductQuotaState) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(quota.compactLabel).font(.headline)
                        Text(precisionLabel(quota.precision))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(resetLabel(quota.resetsAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(quota.displayText)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            if let percent = quota.value.remainingPercent {
                GeometryReader { geometry in
                    Capsule()
                        .fill(.primary.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(RemainingUsageVisualPolicy.color(for: percent).opacity(0.78))
                                .frame(width: geometry.size.width * RemainingUsageVisualPolicy.visibleFraction(
                                    for: percent,
                                    width: geometry.size.width
                                ))
                        }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var connectionSection: some View {
        section(localized("Connection & Source", "连接与来源")) {
            VStack(spacing: 7) {
                factRow(localized("Status", "状态"), connectionLabel)
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
    }

    private var controlsSection: some View {
        section(localized("Agent Controls", "智能体控制")) {
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

    private var codexActivitySection: some View {
        section(localized("Recent Activity", "最近活动")) {
            VStack(alignment: .leading, spacing: 10) {
                let metrics = store.snapshot.metrics.filter { $0.value != "—" }
                if !metrics.isEmpty {
                    HStack(spacing: 24) {
                        ForEach(metrics) { metric in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.value).font(.headline).monospacedDigit()
                                Text(metric.label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if store.snapshot.recentTasks.isEmpty {
                    Text(localized("No recent allowlisted local activity metadata.", "暂无允许范围内的本地活动元数据。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.snapshot.recentTasks) { task in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title).lineLimit(1)
                                Text(task.time).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(task.tokenText).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                if let estimate = store.snapshot.apiCostEstimate {
                    HStack {
                        Text(localized("API-equivalent estimate", "API 等效估算"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(estimate.sevenDayUSD, format: .currency(code: "USD"))
                            .monospacedDigit()
                        Text(localized("7 days", "7 天"))
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var claudeSmartSection: some View {
        section(localized("Local Smart & Accuracy", "本地智能与精确同步")) {
            VStack(alignment: .leading, spacing: 7) {
                Label(claudeSmartLabel, systemImage: "lock.shield")
                    .font(.callout.weight(.medium))
                Text(localized(
                    "Local Smart and one-shot Accuracy Sync retain only approved usage metadata. Prompts, responses, credentials, and raw page content do not enter UMA.",
                    "本地智能和一次性精确同步仅保留已批准的用量元数据；提示、回复、凭据和原始页面内容不会进入 UMA。"
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var diagnosticsSection: some View {
        DisclosureGroup(localized("Advanced Diagnostics", "高级诊断")) {
            VStack(alignment: .leading, spacing: 6) {
                    factRow(localized("Connection", "连接"), connectionLabel)
                    factRow(localized("Source health", "来源健康状态"), diagnosticLabel)
                    Text(localized("Diagnostics use bounded status classifications only.", "诊断仅使用有界状态分类。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .font(.callout)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 13)
    }

    private var sectionDivider: some View { Divider().accessibilityHidden(true) }

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
        if let plan = provider?.planLabel, !plan.isEmpty { return plan }
        if providerID == .codex, store.snapshot.planLabel != "—" {
            return store.snapshot.planLabel
        }
        return nil
    }

    private var sourceLabel: String {
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

    private func resetLabel(_ date: Date?) -> String {
        guard let date else { return localized("Reset not provided", "未提供重置时间") }
        return store.language.resetDescription(for: date, now: displayNow)
    }

    private var displayNow: Date { referenceDate ?? Date() }

    private func relativeUpdateDescription(since date: Date) -> String {
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
    @Published private(set) var assistantEnabled: Bool
    @Published private(set) var assistantAlwaysOnTop: Bool
    @Published private(set) var assistantDensity: DesktopAssistantDensity
    @Published private(set) var launchAtLoginState: LaunchAtLoginState
    @Published private(set) var launchAtLoginError: String?

    private let preferences: ApplicationPreferences
    private let store: UsageStore
    private var observation: ApplicationPreferences.Observation?

    init(preferences: ApplicationPreferences, store: UsageStore) {
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
        launchAtLoginState = LaunchAtLoginService.state
        launchAtLoginError = nil
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

    public init(
        preferences: ApplicationPreferences,
        store: UsageStore,
        navigation: GlobalSettingsNavigationState
    ) {
        self.navigation = navigation
        _model = StateObject(
            wrappedValue: GlobalSettingsViewModel(preferences: preferences, store: store)
        )
    }

    public var body: some View {
        HStack(spacing: 0) {
            List(GlobalSettingsPane.allCases, selection: $navigation.pane) { item in
                Label(paneTitle(item), systemImage: symbol(item))
                    .tag(item)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 170, idealWidth: 180, maxWidth: 200)
            .accessibilityIdentifier("uma.settings.sidebar")

            Divider()

            settingsDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("uma.settings.detail.\(navigation.pane.id)")
        }
        .frame(minWidth: 560, minHeight: 400)
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
        Form {
            switch navigation.pane {
            case .general:
                settingsSection(
                    title: localized("General", "通用"),
                    subtitle: localized("Application behavior", "应用行为")
                ) {
                    Toggle(
                        localized("Launch UMA at login", "登录时启动 UMA"),
                        isOn: Binding(
                            get: { model.launchAtLoginState.isOn },
                            set: model.setLaunchAtLogin
                        )
                    )
                    .accessibilityIdentifier("uma.settings.general.launch-at-login")
                    if model.launchAtLoginState == .requiresApproval {
                        HStack {
                            Text(localized(
                                "macOS approval is required before UMA can open at login.",
                                "需要 macOS 批准后，UMA 才能在登录时启动。"
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
                    settingFact(
                        localized("Window close behavior", "窗口关闭行为"),
                        localized(
                            "Monitoring continues until you choose Quit UMA.",
                            "监控会持续运行，直到您选择退出 UMA。"
                        )
                    )
                    settingFact(
                        localized("Refresh behavior", "刷新行为"),
                        localized(
                            "Background updates with manual Refresh All",
                            "后台更新，并可手动全部刷新"
                        )
                    )
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
                        localized("Window lifecycle", "窗口生命周期"),
                        localized("Closing a window keeps monitoring active.", "关闭窗口后监控仍会继续。")
                    )
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
                        localized("Show reset times in Quick Panel", "在快速面板显示重置时间"),
                        isOn: Binding(
                            get: { model.quickPanelShowsReset },
                            set: model.setQuickPanelShowsReset
                        )
                    )
                    .accessibilityIdentifier("uma.settings.appearance.quick-reset")
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
                }
            case .privacy:
                settingsSection(
                    title: localized("Privacy & Data", "隐私与数据"),
                    subtitle: localized("Usage data stays bounded to each approved source", "用量数据仅限于已批准的来源")
                ) {
                    settingFact(
                        localized("Usage data", "用量数据"),
                        localized("UMA retains only allowlisted usage metadata.", "UMA 仅保留允许范围内的用量元数据。")
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
        }
    }

    private func paneTitle(_ pane: GlobalSettingsPane) -> String {
        switch pane {
        case .general: localized("General", "通用")
        case .appearance: localized("Appearance", "外观")
        case .desktopWizard: localized("Desktop Wizard", "桌面向导")
        case .privacy: localized("Privacy & Data", "隐私与数据")
        }
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        model.language == .simplifiedChinese ? chinese : english
    }
}
