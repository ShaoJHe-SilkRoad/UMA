import AppKit
import SwiftUI

enum UsageSettingsDestination: Equatable {
    case workBuddy
    case agent(String)
}

struct UsageSettingsCard: View {
    @Binding var showUsageSummary: Bool
    @Binding var showRecentTasks: Bool
    @Binding var showAPICost: Bool
    @Binding var language: AppLanguage
    let claudeSettings: ClaudeBrowserSettingsModel?
    var antigravitySettings: AntigravitySettingsModel? = nil
    let workBuddySettings: WorkBuddySettingsModel?
    let workBuddyLogin: WorkBuddyLoginCoordinator?
    let workBuddyAccountWebSync: WorkBuddyAccountWebSessionController?
    let providerLoginOptions: [ProviderLoginOption]
    let providerPresentations: [SharedUsageCardPresentation]
    var agentSettings: AgentSettingsCoordinator? = nil
    var searchForAgents: (() -> Void)? = nil
    let destination: UsageSettingsDestination?
    let tuning: GlassTuning
    let maximumHeight: CGFloat
    let onResolvedHeightChange: (CGFloat) -> Void
    let checkAgain: () -> Void
    let syncWorkBuddyAccount: () -> Void
    let disconnectWorkBuddyAccount: () -> Void
    let close: () -> Void

    @State private var launchAtLoginState = LaunchAtLoginService.state
    @State private var launchAtLoginError: String?
    @State private var selectedAgentID: String?
    @State private var measuredContentHeight: CGFloat?
    @AppStorage(DesktopAssistantPreferences.Keys.isEnabled)
    private var assistantEnabled = true
    @AppStorage(DesktopAssistantPreferences.Keys.isAlwaysOnTop)
    private var assistantAlwaysOnTop = true
    @AppStorage(DesktopAssistantPreferences.Keys.density)
    private var assistantDensityRaw = DesktopAssistantDensity.automatic.rawValue

    private var resolvedCardHeight: CGFloat {
        UsageSettingsSizing.cardHeight(
            contentHeight: measuredContentHeight,
            maximumHeight: maximumHeight
        )
    }

    private var resolvedViewportHeight: CGFloat {
        max(
            0,
            resolvedCardHeight - (UsageSettingsSizing.cardVerticalPadding * 2)
        )
    }

    var body: some View {
        adaptiveContent
            .frame(
                width: 278,
                height: resolvedViewportHeight,
                alignment: .top
            )
            .padding(UsageSettingsSizing.cardVerticalPadding)
            .frame(width: 306, height: resolvedCardHeight)
            .background {
                GlassCardBackground(
                    tuning: tuning,
                    readabilityFillOpacity: AppGlass.settingsReadabilityFillOpacity
                )
            }
            .onAppear {
                launchAtLoginState = LaunchAtLoginService.state
                onResolvedHeightChange(resolvedCardHeight)
            }
            .onChange(of: resolvedCardHeight) { _, height in
                onResolvedHeightChange(height)
            }
    }

    private var adaptiveContent: some View {
        ScrollView(.vertical) {
            settingsContent
                .frame(width: 278, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityLabel(language.settingsTitle)
        .accessibilityIdentifier("usage.settings.scroll")
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader

            if let agentSettings,
               let selectedAgentID,
               let providerID = AgentConnectorID(rawValue: selectedAgentID) {
                AgentSpecificSettingsContent(
                    coordinator: agentSettings,
                    providerID: providerID,
                    language: language,
                    showAPICost: $showAPICost,
                    claudeSettings: claudeSettings,
                    antigravitySettings: antigravitySettings,
                    workBuddySettings: workBuddySettings,
                    workBuddyLogin: workBuddyLogin,
                    workBuddyAccountWebSync: workBuddyAccountWebSync,
                    presentation: providerPresentations.first {
                        $0.id == selectedAgentID
                    },
                    checkAgain: checkAgain,
                    syncWorkBuddyAccount: syncWorkBuddyAccount,
                    disconnectWorkBuddyAccount:
                        disconnectWorkBuddyAccount
                )
            } else {
                globalSettingsContent
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SettingsContentHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(SettingsContentHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            measuredContentHeight = ceil(height)
        }
        .onAppear {
            guard selectedAgentID == nil else { return }
            switch destination {
            case .workBuddy:
                selectedAgentID =
                    AgentPreferenceRecord.workBuddyProviderID.rawValue
            case let .agent(providerID):
                selectedAgentID = providerID
            case nil:
                break
            }
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 7) {
            if selectedAgentID != nil {
                Button {
                    selectedAgentID = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(language.backToSettings)
                .accessibilityLabel(language.backToSettings)
            } else {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(UsageDesign.blue)
            }
            Text(
                selectedAgentID == nil
                    ? language.settingsTitle
                    : language.agentSettings
            )
            .font(AppTypography.font(15, weight: .bold, language: language))
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.secondary.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .help(language.closeSettings)
            .accessibilityLabel(language.closeSettings)
        }
    }

    @ViewBuilder
    private var globalSettingsContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(language.globalSettingsSection)
                .font(AppTypography.font(10.5, weight: .medium, language: language))
                .foregroundStyle(.secondary)

            LanguageSettingRow(language: $language)

            SettingsToggleRow(
                title: language.launchAtLogin,
                systemImage: "power",
                language: language,
                isOn: launchAtLoginBinding
            )

            SettingsToggleRow(
                title: language.desktopAssistantEnabled,
                systemImage: "macwindow",
                language: language,
                isOn: $assistantEnabled
            )
            SettingsToggleRow(
                title: language.desktopAssistantAlwaysOnTop,
                systemImage: "pin",
                language: language,
                isOn: $assistantAlwaysOnTop
            )
            .disabled(!assistantEnabled)
            .opacity(assistantEnabled ? 1 : 0.55)

            AssistantDensitySettingRow(
                language: language,
                selection: Binding(
                    get: {
                        DesktopAssistantDensity(rawValue: assistantDensityRaw)
                            ?? .automatic
                    },
                    set: { assistantDensityRaw = $0.rawValue }
                )
            )
            .disabled(!assistantEnabled)
            .opacity(assistantEnabled ? 1 : 0.55)

            launchAtLoginMessage

            if let agentSettings {
                AgentDiscoverySettingsSection(
                    coordinator: agentSettings,
                    language: language,
                    search: searchForAgents ?? checkAgain
                )
            }
        }

        if !providerLoginOptions.isEmpty {
            Divider().opacity(0.35)
            ProviderLoginAssistanceSection(
                options: providerLoginOptions,
                language: language,
                checkAgain: checkAgain
            )
        }

        if let agentSettings {
            Divider().opacity(0.35)
            AgentSettingsList(
                coordinator: agentSettings,
                language: language,
                select: { selectedAgentID = $0.rawValue }
            )
        }
    }

    @ViewBuilder
    private var launchAtLoginMessage: some View {
        if launchAtLoginState == .requiresApproval {
            HStack(spacing: 6) {
                Text(language.approvalRequired)
                Spacer()
                Button(language.openSettings) {
                    LaunchAtLoginService.openSystemSettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(UsageDesign.blue)
            }
            .font(AppTypography.font(9.5, weight: .medium, language: language))
            .foregroundStyle(.secondary)
        }

        if let launchAtLoginError {
            Text(launchAtLoginError)
                .font(AppTypography.font(9.5, language: language))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginState.isOn },
            set: { newValue in
                do {
                    launchAtLoginState = try LaunchAtLoginService.setEnabled(newValue)
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginState = LaunchAtLoginService.state
                    launchAtLoginError = language.settingsFailure(error.localizedDescription)
                }
            }
        )
    }
}

private struct AgentDiscoverySettingsSection: View {
    @ObservedObject var coordinator: AgentSettingsCoordinator
    let language: AppLanguage
    let search: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SettingsToggleRow(
                title: language.autoSearchForAgents,
                systemImage: "magnifyingglass",
                language: language,
                isOn: Binding(
                    get: { coordinator.autoSearchEnabled },
                    set: { coordinator.setAutoSearchEnabled($0) }
                )
            )
            if !coordinator.initialScanCompleted {
                Text(language.autoSearchOnboardingHint)
                    .font(AppTypography.font(9, language: language))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(language.scanForAgents, action: search)
                .buttonStyle(.bordered)
                .accessibilityHint(language.autoSearchOnboardingHint)
        }
    }
}

private struct AgentSettingsList: View {
    @ObservedObject var coordinator: AgentSettingsCoordinator
    let language: AppLanguage
    let select: (AgentConnectorID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(language.agentsSettingsSection)
                .font(AppTypography.font(10.5, weight: .medium, language: language))
                .foregroundStyle(.secondary)

            ForEach(coordinator.entries) { entry in
                Button {
                    select(entry.providerID)
                } label: {
                    HStack(spacing: 8) {
                        Text(entry.displayName)
                            .font(
                                AppTypography.font(
                                    11.5,
                                    weight: .medium,
                                    language: language
                                )
                            )
                        Spacer()
                        if entry.requiresSetup {
                            Text(language.agentSetupRequired)
                                .font(AppTypography.font(8.5, language: language))
                                .foregroundStyle(.orange)
                        } else if !entry.isActive && entry.hasBeenDetected {
                            Text(language.notCurrentlyRunning)
                                .font(AppTypography.font(8.5, language: language))
                                .foregroundStyle(.secondary)
                        }
                        Text(language.agentSettings)
                            .font(AppTypography.font(9.5, language: language))
                            .foregroundStyle(UsageDesign.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(entry.displayName), \(language.agentSettings)"
                )
            }
        }
    }
}

/// Claude reports no plan over any transport, so `LowRemainingUsagePolicy`
/// grades it as `.unknownPlan` and every Claude quota bar renders grey — a 3%
/// reading looks exactly like a 90% one. The plan is asked for here rather than
/// inferred: the app must never guess an account tier, and the value is still
/// filtered through the policy allowlist before it reaches any threshold.
private struct ClaudePlanSelectionRow: View {
    let language: AppLanguage
    @AppStorage("claude.declaredPlan") private var declaredPlan = ""

    private var title: String {
        language == .simplifiedChinese ? "Claude 方案" : "Claude plan"
    }

    private var notStated: String {
        language == .simplifiedChinese ? "未说明" : "Not stated"
    }

    private var guidance: String {
        language == .simplifiedChinese
            ? "Claude 不报告方案。选择后，额度偏低时以颜色提醒。"
            : "Claude does not report its plan. Choose one to get low-remaining colour warnings."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: "person.badge.shield.checkmark")
                    .labelStyle(SettingsRowLabelStyle())
                    .font(AppTypography.systemFont(13))
                Spacer()
                Picker(title, selection: $declaredPlan) {
                    Text(notStated).tag("")
                    Text("Pro").tag("pro")
                    Text("Max").tag("max")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
            }
            Text(guidance)
                .font(AUVType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 26)
        }
        .accessibilityIdentifier("uma.agent.settings.claude.plan")
    }
}

private struct AgentSpecificSettingsContent: View {
    @ObservedObject var coordinator: AgentSettingsCoordinator
    let providerID: AgentConnectorID
    let language: AppLanguage
    /// Shows Claude's Local Cost Estimate module on its page.
    @Binding var showAPICost: Bool
    let claudeSettings: ClaudeBrowserSettingsModel?
    let antigravitySettings: AntigravitySettingsModel?
    let workBuddySettings: WorkBuddySettingsModel?
    let workBuddyLogin: WorkBuddyLoginCoordinator?
    let workBuddyAccountWebSync: WorkBuddyAccountWebSessionController?
    let presentation: SharedUsageCardPresentation?
    let checkAgain: () -> Void
    let syncWorkBuddyAccount: () -> Void
    let disconnectWorkBuddyAccount: () -> Void

    private var entry: AgentSettingsEntry? {
        coordinator.entries.first { $0.providerID == providerID }
    }

    private var displayName: String {
        entry?.displayName ?? providerID.rawValue
    }

    var body: some View {
        if providerID == AgentPreferenceRecord.claudeProviderID {
            claudeBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(displayName)
                .font(AppTypography.font(13, weight: .semibold, language: language))

            if let presentation {
                ResolvedProviderUsageSummary(
                    presentation: presentation,
                    language: language
                )
            }

            availabilityNotice()

            SettingsToggleRow(
                title: language.monitoringEnabled,
                systemImage: "waveform.path.ecg",
                language: language,
                isOn: monitoringBinding
            )
            .accessibilityIdentifier("uma.agent.settings.monitoring.\(providerID.rawValue)")

            if providerID == AgentPreferenceRecord.antigravityProviderID,
               let antigravitySettings {
                Divider().opacity(0.35)
                AntigravitySettingsSection(
                    model: antigravitySettings,
                    language: language
                )
            }

            if providerID == AgentPreferenceRecord.workBuddyProviderID,
               let workBuddySettings {
                Divider().opacity(0.35)
                WorkBuddySettingsSection(
                    model: workBuddySettings,
                    login: workBuddyLogin,
                    accountWebSync: workBuddyAccountWebSync,
                    language: language,
                    expandOnAppear: true,
                    checkAgain: checkAgain,
                    syncNow: syncWorkBuddyAccount,
                    disconnectAccount: disconnectWorkBuddyAccount
                )
            }
        }
    }

    /// Claude reads top to bottom as what it reports now, what you can do,
    /// its settings, then how it works on demand. Every control and statement
    /// of the earlier single column is still here; only order and type moved.
    private var claudeBody: some View {
        VStack(alignment: .leading, spacing: ClaudeSettingsMetrics.sectionSpacing) {
            // The sheet's own title already names Claude.
            availabilityNotice(refined: true)

            if let claudeSettings {
                ClaudeBrowserSettingsSection(
                    model: claudeSettings,
                    language: language,
                    presentation: presentation
                ) {
                    claudeSettingsGroup
                }
            } else {
                if let presentation {
                    ResolvedProviderUsageSummary(
                        presentation: presentation,
                        language: language,
                        style: .quotaBar
                    )
                    .modifier(ClaudeSettingsCardSurface())
                }
                claudeSettingsGroup
            }
        }
    }

    private var claudeSettingsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClaudeSettingsGroupTitle(text: language.claudeSettingsSectionTitle)
            VStack(alignment: .leading, spacing: 10) {
                SettingsToggleRow(
                    title: language.monitoringEnabled,
                    systemImage: "waveform.path.ecg",
                    language: language,
                    isOn: monitoringBinding,
                    refined: true
                )
                .accessibilityIdentifier("uma.agent.settings.monitoring.\(providerID.rawValue)")
                SettingsToggleRow(
                    title: language.costCard,
                    systemImage: "dollarsign.circle",
                    language: language,
                    isOn: $showAPICost,
                    refined: true
                )
                Divider().opacity(0.5)
                ClaudePlanSelectionRow(language: language)
            }
            .modifier(ClaudeSettingsCardSurface())
        }
    }

    /// Claude's refined layout sets these in system type; the other agents
    /// keep the type they had.
    @ViewBuilder
    private func availabilityNotice(refined: Bool = false) -> some View {
        let title = refined
            ? AppTypography.systemFont(12, weight: .semibold)
            : AppTypography.font(10, weight: .semibold, language: language)
        let detail = refined
            ? AppTypography.systemFont(12)
            : AppTypography.font(9, language: language)
        if entry?.requiresSetup == true {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.agentSetupRequired).font(title)
                Text(language.agentSetupRequiredGuidance).font(detail)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        } else if entry?.isActive == false,
                  entry?.hasBeenDetected == true {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.notCurrentlyRunning).font(title)
                Text(language.savedSettingsApplyWhenDetected).font(detail)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: {
                coordinator.isMonitoringEnabled(for: providerID)
            },
            set: {
                if providerID
                    == AgentPreferenceRecord.antigravityProviderID,
                   let antigravitySettings {
                    if $0 {
                        coordinator.setMonitoringEnabled(true, for: providerID)
                        antigravitySettings.checkAntigravity()
                    } else {
                        antigravitySettings.disable()
                    }
                } else {
                    coordinator.setMonitoringEnabled($0, for: providerID)
                }
            }
        )
    }
}

/// Settings renders the exact same provider-neutral presentation object as
/// the Main Panel and Desktop Assistant. It must never reinterpret quota or
/// provenance independently.
private struct ResolvedProviderUsageSummary: View {
    enum Style {
        case standard
        /// Direction D: system type and the quota bar, inside a card the
        /// caller supplies.
        case quotaBar
    }

    let presentation: SharedUsageCardPresentation
    let language: AppLanguage
    var style: Style = .standard
    @AppStorage("claude.declaredPlan") private var declaredClaudePlan = ""

    var body: some View {
        switch style {
        case .standard:
            standardBody
        case .quotaBar:
            quotaBarBody
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(language.remaining)
                    .font(AppTypography.font(9.5, weight: .semibold, language: language))
                Spacer()
                Text(primaryValue)
                    .font(AppTypography.font(11, weight: .bold, language: language))
                    .monospacedDigit()
            }
            if let window = presentation.selectedWindow {
                Text(window.compactLabel)
                    .font(AppTypography.font(8.5, language: language))
                    .foregroundStyle(.secondary)
            }
            if let source = presentation.sourceDescription {
                Text(source)
                    .font(AppTypography.font(8.5, language: language))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier("settings.provider.resolved-usage")
    }

    private var quotaBarBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(language.remaining)
                    .font(AppTypography.systemFont(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let window = presentation.selectedWindow {
                    Text(window.compactLabel)
                        .font(AppTypography.systemFont(11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(primaryValue)
                    .font(AppTypography.numericFont(20, weight: .semibold))
                    .foregroundStyle(
                        presentation.remaining.finitePercent == nil ? .secondary : .primary
                    )
            }
            SettingsQuotaBar(
                remainingPercent: presentation.remaining.finitePercent,
                tone: LowRemainingUsagePolicy.color(for: assessment),
                lowThresholdPercent: LowRemainingUsagePolicy.lowThresholdPercent(
                    providerID: presentation.id, admittedPlan: admittedPlan
                )
            )
            if let source = presentation.sourceDescription {
                Text(source)
                    .font(AppTypography.systemFont(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier("settings.provider.resolved-usage")
    }

    /// The same allowlisted plan the main window grades with: the reported
    /// label first, then the plan the user declared for Claude.
    private var admittedPlan: String? {
        let isClaude = ProviderProductStatePolicy.productID(
            forRawConnectorID: presentation.id
        ) == .claude
        return presentation.planLabel
            ?? (isClaude && !declaredClaudePlan.isEmpty ? declaredClaudePlan : nil)
    }

    private var assessment: LowRemainingAssessment {
        LowRemainingUsagePolicy.assessment(
            providerID: presentation.id,
            admittedPlan: admittedPlan,
            remainingPercent: presentation.remaining.finitePercent
        )
    }

    private var primaryValue: String {
        presentation.availability?.compactText
            ?? presentation.remainingDisplayText
    }
}

/// Direction D's quota bar: the remaining share in the policy's tone, a notch
/// at the plan's low line when the plan is known, and a dashed empty track
/// when there is no reading. It never draws a fill it was not given.
private struct SettingsQuotaBar: View {
    let remainingPercent: Double?
    let tone: Color
    let lowThresholdPercent: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))
                if let fraction = CompactUsageFillPolicy.fraction(for: remainingPercent) {
                    Capsule()
                        .fill(tone)
                        .frame(width: proxy.size.width * RemainingUsageVisualPolicy.visibleFraction(
                            for: fraction * 100, width: proxy.size.width
                        ))
                } else {
                    Capsule()
                        .strokeBorder(
                            Color.secondary.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                }
                if let lowThresholdPercent, remainingPercent != nil {
                    Rectangle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 1, height: proxy.size.height + 4)
                        .offset(x: proxy.size.width * lowThresholdPercent / 100)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct AntigravitySettingsSection: View {
    @ObservedObject var model: AntigravitySettingsModel
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.antigravitySourceLabel)
                .font(
                    AppTypography.font(
                        10.5,
                        weight: .semibold,
                        language: language
                    )
                )
            Text(language.antigravityState(model.state))
                .font(AppTypography.font(9.5, language: language))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("antigravity.settings.state")

            if showsAutoRefresh {
                SettingsToggleRow(
                    title: language.antigravityAutoRefresh,
                    systemImage: "arrow.clockwise",
                    language: language,
                    isOn: Binding(
                        get: { model.autoRefreshEnabled },
                        set: { model.setAutoRefreshEnabled($0) }
                    )
                )
            }

            HStack(spacing: 8) {
                primaryAction
                if showsCheckAgain {
                    Button(language.antigravityCheck) {
                        model.checkAntigravity()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("antigravity.settings.check")
                }
                if showsDisable {
                    Button(language.antigravityDisable) {
                        model.disable()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("antigravity.settings.disable")
                }
            }
            .disabled(model.actionInProgress)

            if let action = model.activeAction {
                Text(language.antigravityAction(action))
                    .font(AppTypography.font(9, language: language))
                    .foregroundStyle(.secondary)
            }
            if let error = model.safeError {
                Text(language.antigravityError(error))
                    .font(AppTypography.font(9, language: language))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup(language.antigravitySourceTransparency) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.sourceTransparency.source)
                    Text(model.sourceTransparency.authentication)
                    Text(language.antigravityPrivacySummary)
                }
                .font(AppTypography.font(8.5, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.state {
        case .notInstalled:
            Button(language.antigravityInstallOrOpen) {
                model.openOfficialSetup()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("antigravity.settings.setup")
        case .loginRequired:
            Button(language.antigravityInstallOrOpen) {
                model.openProvider()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("antigravity.settings.open-provider")
        default:
            Button(language.antigravitySyncNow) {
                model.syncNow()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("antigravity.settings.sync")
        }
    }

    private var showsAutoRefresh: Bool {
        switch model.state {
        case .connected, .fresh, .cached, .stale, .refreshing:
            true
        default:
            false
        }
    }

    private var showsCheckAgain: Bool {
        switch model.state {
        case .notInstalled, .loginRequired, .failed:
            true
        default:
            false
        }
    }

    private var showsDisable: Bool {
        switch model.state {
        case .disabled, .notInstalled:
            false
        default:
            true
        }
    }
}

private enum ClaudeSettingsMetrics {
    static let sectionSpacing: CGFloat = 18
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = AUVShape.cardRadius
}

/// The small label above each group of the Claude sheet, set like the
/// section headers in Global Settings.
private struct ClaudeSettingsGroupTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AUVType.label)
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The main window's module surface (radius 10, one hairline), shared by the
/// Claude settings cards so the sheet reads as part of today's app.
private struct ClaudeSettingsCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(ClaudeSettingsMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UMAVisualStyle.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClaudeSettingsMetrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ClaudeSettingsMetrics.cardRadius, style: .continuous)
                    .strokeBorder(UMAVisualStyle.separator.opacity(0.65), lineWidth: 0.5)
            }
    }
}

private struct ClaudeBrowserSettingsSection<Settings: View>: View {
    @ObservedObject var model: ClaudeBrowserSettingsModel
    let language: AppLanguage
    let presentation: SharedUsageCardPresentation?
    @ViewBuilder let settings: () -> Settings
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: ClaudeSettingsMetrics.sectionSpacing) {
            statusCard
            settings()
            actions
            details
        }
    }

    // MARK: What Claude reports now

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let presentation {
                ResolvedProviderUsageSummary(
                    presentation: presentation,
                    language: language,
                    style: .quotaBar
                )
                Divider().opacity(0.5)
            }
            stateSummary
            VStack(alignment: .leading, spacing: 3) {
                Text(language.claudeLastExact(model.lastExactAt))
                Text(language.claudeAccuracySyncRoute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(AUVType.caption)
            .foregroundStyle(.secondary)
        }
        .modifier(ClaudeSettingsCardSurface())
    }

    @ViewBuilder
    private var stateSummary: some View {
        if let action = model.activeAction {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(language.claudeBrowserActionStatus(action))
                    .font(AUVType.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            stateSummaryContent
        }
    }

    @ViewBuilder
    private var stateSummaryContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            statusRow(
                language == .simplifiedChinese ? "本地智能" : "Local Smart",
                language.claudeLocalSmartStatus(
                    model.localSmartState,
                    stage: model.localSmartStage
                )
            )
            statusRow(
                language == .simplifiedChinese ? "浏览器伴侣" : "Companion",
                language.claudeCompanionRuntimeStatus(
                    runtime: model.productState.companionRuntime,
                    accuracyState: model.browserAccuracyState
                )
            )
            statusRow(
                language == .simplifiedChinese ? "浏览器精确同步" : "Browser Accuracy",
                language.claudeBrowserAccuracyStatus(
                    model.browserAccuracyState,
                    stage: model.browserAccuracyStage
                )
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("claude.source-state-summary")
    }

    private func statusRow(_ title: String, _ status: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(AUVType.headline)
            Text(status)
                .font(AUVType.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    /// Enabling Local Smart is on Claude's page, and Accuracy Sync runs with
    /// Refresh All and automatic refresh; here are only the repair step for
    /// the current state and the connection itself.
    @ViewBuilder
    private var actions: some View {
        if model.consentGranted || model.safeError != nil || model.state != .disconnected {
            VStack(alignment: .leading, spacing: 8) {
                ClaudeSettingsGroupTitle(text: language == .simplifiedChinese ? "连接" : "Connection")
                connectionActions
                    .modifier(ClaudeSettingsCardSurface())
            }
        }
    }

    private var connectionActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            primaryAction
                .disabled(model.actionInProgress)

            // Disconnect and Retry take their own lines, so the first row fits
            // the 278-point Quick Panel settings column in both languages.
            if model.consentGranted {
                ClaudeSettingsActionButton(
                    title: language.claudeDisableIntegration,
                    identifier: "claude.browser.disconnect",
                    isEnabled: !model.actionInProgress,
                    action: model.disconnect
                )
                .disabled(model.actionInProgress)
                ClaudeSettingsActionButton(
                    title: language == .simplifiedChinese
                        ? "重试 Safari 网站访问权限"
                        : "Retry Safari Site Access",
                    identifier: "claude.browser.retry-site-access",
                    role: .link,
                    action: model.retrySafariSiteAccess
                )
            }

            if let safeError = model.safeError {
                Text(language.claudeBrowserError(safeError))
                    .font(AUVType.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.state {
        case .disconnected:
            // Enable Local Smart, with its consent, is on Claude's page.
            EmptyView()
        case .fresh, .cached, .stale:
            ClaudeSettingsActionButton(
                title: language == .simplifiedChinese ? "刷新本地数据" : "Refresh Local",
                identifier: "claude.browser.sync-now",
                isEnabled: !model.actionInProgress,
                action: model.syncNow
            )
        case .waitingForUsagePage:
            ClaudeSettingsActionButton(
                title: language == .simplifiedChinese ? "刷新本地数据" : "Refresh Local",
                identifier: "claude.browser.sync-now",
                isEnabled: !model.actionInProgress,
                action: model.syncNow
            )
        case .websiteAccessRequired:
            ClaudeSettingsActionButton(
                title: language == .simplifiedChinese ? "请求 Safari 网站访问权限" : "Request Safari Site Access",
                identifier: "claude.browser.request-site-access",
                role: .primary,
                isEnabled: !model.actionInProgress,
                action: model.requestSafariSiteAccess
            )
        case .signInRequired, .waitingForSafari:
            ClaudeSettingsActionButton(
                title: language == .simplifiedChinese ? "检查浏览器伴侣" : "Check Browser Companion",
                identifier: "claude.browser.check-companion",
                isEnabled: !model.actionInProgress,
                action: model.verifyCompanion
            )
        case .companionDisabled, .companionOutdated,
             .nativeHostMissing, .nativeHostMismatched:
            ClaudeSettingsActionButton(
                title: language == .simplifiedChinese ? "修复伴侣" : "Repair Companion",
                identifier: "claude.browser.repair",
                isEnabled: !model.actionInProgress,
                action: model.repairCompanion
            )
        case .extensionNotInstalled, .inventoryRestartRequired, .inventoryLoading,
             .companionStarting, .protocolMismatch, .companionUnavailable,
             .unsupportedBrowser, .browserUnavailable, .routeChanged, .failed:
            ClaudeSettingsActionButton(
                title: language == .simplifiedChinese ? "重新检查" : "Check Again",
                identifier: "claude.browser.check-again",
                isEnabled: !model.actionInProgress,
                action: model.checkCompanion
            )
        case .checking:
            ProgressView().controlSize(.small)
        }
    }

    // MARK: How it works, on demand

    /// The two explanations and the full Source Transparency list, word for
    /// word, behind one native disclosure button on the Tab route.
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClaudeSettingsActionButton(
                title: language.claudeHowItWorks,
                identifier: "claude.settings.details",
                role: .disclosure(expanded: showsDetails),
                action: { showsDetails.toggle() }
            )

            if showsDetails {
                VStack(alignment: .leading, spacing: 10) {
                    detailHeading(language == .simplifiedChinese ? "Claude 本地智能模式" : "Claude Local Smart Mode")
                    detailText(
                        language == .simplifiedChinese
                            ? "Claude Code 正常使用时由官方状态栏字段自动更新；Claude Desktop 的版本锁定计划缓存仅提供以 ≈ 标记、无重置时间的估算值。Safari 仅由精确同步临时使用，精确同步随“全部刷新”及自动刷新运行。"
                            : "Updates from Claude Code's official status-line fields during normal use. Claude Desktop's version-pinned plan cache provides only ≈-labeled estimates without reset times. Safari is used only, and only briefly, by Accuracy Sync, which runs with Refresh All and automatic refresh."
                    )
                    detailText(
                        language == .simplifiedChinese
                            ? "每次精确同步创建一个绑定请求的临时非活动标签页，验证精确使用量路由，读取一次净化后的配额并关闭该标签页。浏览器中不会留下定时器或长期标签页。"
                            : "Each Accuracy Sync creates one request-bound temporary inactive tab, verifies the exact Usage route, returns one sanitized quota snapshot, and closes that tab. No scheduler or long-lived tab remains in the browser."
                    )

                    Divider().opacity(0.5)
                    detailHeading(language.claudeSourceTransparency)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(language == .simplifiedChinese ? "来源：Claude 官方本地状态栏；版本锁定的桌面端计划缓存估算；按需 Safari 精确同步" : "Sources: Claude official local status line; version-pinned Desktop plan-cache estimate; on-demand Safari Accuracy Sync")
                        Text(language == .simplifiedChinese ? "估算：仅保留当前 5 小时/7 天剩余量与时间戳，以 ≈ 标记且不推测重置时间" : "Desktop estimate: Current five-hour/seven-day remaining values and timestamp only, labeled ≈ with no inferred reset")
                        Text(language == .simplifiedChinese ? "本地活动估算：一次处理一条有界 JSONL 记录；立即丢弃提示、回复与会话内容，仅保留允许的用量计数、模型系列和活动时间戳；结果以 ≈ 标记，不是官方精确配额" : "Local-activity estimate: One bounded JSONL record is processed at a time; prompts, responses, and session content are discarded immediately; only allowlisted usage counts, model family, and activity timestamp are retained; ≈ is not official exact quota")
                        Text(language.claudeEstimateConfidence(model.estimateConfidence))
                        Text(language.claudeLastExact(model.lastExactAt))
                        Text(language == .simplifiedChinese ? "Google / Claude 密码：未访问" : "Google / Claude password: Not accessed")
                        Text(language == .simplifiedChinese ? "API 密钥：不需要" : "API key: Not required")
                        Text(language == .simplifiedChinese ? "钥匙串：未访问" : "Keychain: Not accessed")
                        Text(language == .simplifiedChinese ? "Cookie：保留在浏览器中；AUV 不读取或导出" : "Cookies: Remain inside the browser; not read or exported by AUV")
                        Text(language == .simplifiedChinese ? "状态栏/页面/缓存数据：仅净化后的配额字段；缓存组织信息与历史立即丢弃" : "Status-line/page/cache data: Sanitized quota fields only; cache organization and history are discarded")
                        Text(language == .simplifiedChinese ? "提示、回复、项目内容、身份与账单：不保留" : "Prompts, responses, project content, identity, and billing: Not retained")
                    }
                    .font(AUVType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "claude.browser.source-transparency"
                    )
                }
                .modifier(ClaudeSettingsCardSurface())
            }
        }
    }

    private func detailHeading(_ text: String) -> some View {
        Text(text)
            .font(AUVType.headline)
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(AUVType.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WorkBuddySettingsSection: View {
    @ObservedObject var model: WorkBuddySettingsModel
    let login: WorkBuddyLoginCoordinator?
    let accountWebSync: WorkBuddyAccountWebSessionController?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let language: AppLanguage
    let expandOnAppear: Bool
    @State private var isExpanded = false
    @State private var clearIsArmed = false
    let checkAgain: () -> Void
    let syncNow: () -> Void
    let disconnectAccount: () -> Void

    init(
        model: WorkBuddySettingsModel,
        login: WorkBuddyLoginCoordinator?,
        accountWebSync: WorkBuddyAccountWebSessionController?,
        language: AppLanguage,
        expandOnAppear: Bool,
        checkAgain: @escaping () -> Void,
        syncNow: @escaping () -> Void,
        disconnectAccount: @escaping () -> Void
    ) {
        self.model = model
        self.login = login
        self.accountWebSync = accountWebSync
        self.language = language
        self.expandOnAppear = expandOnAppear
        self.checkAgain = checkAgain
        self.syncNow = syncNow
        self.disconnectAccount = disconnectAccount
        _isExpanded = State(initialValue: expandOnAppear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Label(language.workBuddySection, systemImage: "w.circle")
                        .font(AppTypography.font(12.5, weight: .semibold, language: language))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.workBuddySection)
            .accessibilityValue(
                isExpanded ? language.workBuddyExpanded : language.workBuddyCollapsed
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    if let accountWebSync {
                        WorkBuddyAccountWebSyncSection(
                            controller: accountWebSync,
                            language: language,
                            checkAgain: checkAgain,
                            syncNow: syncNow,
                            disconnectAccount: disconnectAccount
                        )

                        Divider()
                            .opacity(0.35)
                    } else if let login {
                        WorkBuddyLoginAssistanceSection(
                            coordinator: login,
                            language: language
                        )

                        Divider()
                            .opacity(0.35)
                    }

                    Text(language.workBuddyLegacyManualRecord)
                        .font(AppTypography.font(9.5, weight: .medium, language: language))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsToggleRow(
                        title: language.workBuddyEnable,
                        systemImage: "checkmark.circle",
                        language: language,
                        isOn: Binding(
                            get: { model.isEnabled },
                            set: { model.setEnabled($0) }
                        )
                    )

                    labeledValue(
                        language.workBuddySource,
                        value: language.workBuddyManualConfirmation
                    )
                    labeledValue(
                        language.workBuddyScope,
                        value: language.workBuddySharedWithCodeBuddy
                    )

                    Picker(language.workBuddyScope, selection: $model.draft.scope) {
                        ForEach(WorkBuddyManualScope.allCases) {
                            Text(language.workBuddyScopeName($0)).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!model.isEnabled)
                    .accessibilityLabel(language.workBuddyScope)

                    Picker(language.workBuddyTier, selection: $model.draft.tier) {
                        ForEach(WorkBuddyPlanTier.allCases) {
                            Text(language.workBuddyTierName($0)).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!model.isEnabled)
                    .accessibilityLabel(language.workBuddyTier)

                    if let suggestion = model.selectedTierSuggestion {
                        Text(language.workBuddySuggestion(suggestion))
                            .font(AppTypography.font(9, language: language))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(language.workBuddyUseSuggestion) {
                            model.applySelectedTierSuggestion()
                        }
                        .buttonStyle(.borderless)
                        .disabled(!model.isEnabled)
                        .accessibilityHint(language.workBuddySuggestion(suggestion))
                    }

                    TextField(
                        language.workBuddyAvailableCredits,
                        text: $model.draft.remainingText
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!model.isEnabled)
                    .accessibilityLabel(language.workBuddyAvailableCredits)

                    Picker(
                        language.workBuddyCompanionName(model.draft.companionField),
                        selection: $model.draft.companionField
                    ) {
                        ForEach(WorkBuddyCreditCompanionField.allCases) {
                            Text(language.workBuddyCompanionCompactName($0))
                                .tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(!model.isEnabled)
                    .accessibilityLabel(
                        language.workBuddyCompanionName(
                            model.draft.companionField
                        )
                    )

                    if model.draft.companionField != .none {
                        TextField(
                            language.workBuddyCompanionName(
                                model.draft.companionField == .usedAndTotal
                                    ? .used
                                    : model.draft.companionField
                            ),
                            text: $model.draft.companionText
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(!model.isEnabled)
                        .accessibilityLabel(
                            language.workBuddyCompanionName(
                                model.draft.companionField == .usedAndTotal
                                    ? .used
                                    : model.draft.companionField
                            )
                        )
                    }

                    if model.draft.companionField == .usedAndTotal {
                        TextField(
                            language.workBuddyCompanionName(.total),
                            text: $model.draft.explicitTotalText
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(!model.isEnabled)
                        .accessibilityLabel(
                            language.workBuddyCompanionName(.total)
                        )
                    }

                    Toggle(language.workBuddyNextExpiry, isOn: $model.draft.includesExpiry)
                        .toggleStyle(.checkbox)
                        .disabled(!model.isEnabled)
                        .accessibilityLabel(language.workBuddyNextExpiry)

                    if model.draft.includesExpiry {
                        DatePicker(
                            language.workBuddyNextExpiry,
                            selection: $model.draft.expiry,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .disabled(!model.isEnabled)
                        .accessibilityLabel(language.workBuddyNextExpiry)
                    }

                    if let validationError = model.validationError {
                        Text(language.workBuddyValidationMessage(validationError))
                            .font(AppTypography.font(9.5, weight: .medium, language: language))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(language.workBuddyValidationMessage(validationError))
                    }

                    if model.lifecycle == .invalidSavedData {
                        Text(language.workBuddyInvalidSavedData)
                            .font(AppTypography.font(9.5, weight: .medium, language: language))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !model.isEnabled || model.savedObservation == nil {
                        Text(language.workBuddyNotConfigured)
                            .font(AppTypography.font(9.5, language: language))
                            .foregroundStyle(.secondary)
                    }

                    if let confirmedAt = model.savedObservation?.balance.observedAt {
                        labeledValue(
                            language.workBuddyLastConfirmed,
                            value: language.workBuddyConfirmedAt(confirmedAt)
                        )
                    }

                    if let preview = model.preview {
                        previewView(preview)
                    }

                    Button(language.workBuddyOpenOfficialUsagePage) {
                        model.openOfficialUsagePage()
                    }
                    .buttonStyle(.borderless)
                    .help(language.workBuddyOfficialPageHint)
                    .accessibilityHint(language.workBuddyOfficialPageHint)

                    HStack(spacing: 6) {
                        Button(language.workBuddyPreview) {
                            model.makePreview()
                        }
                        .disabled(!model.isEnabled)

                        Button(language.workBuddySaveUpdate) {
                            model.save(language: language)
                        }
                        .disabled(!model.canSave)
                    }
                    .buttonStyle(.bordered)

                    Button(language.workBuddyConfirmUnchanged) {
                        model.confirmUnchanged(language: language)
                    }
                    .disabled(!model.canConfirmUnchanged)
                    .buttonStyle(.bordered)

                    Button(
                        clearIsArmed
                            ? language.workBuddyConfirmClear
                            : language.workBuddyClearData,
                        role: .destructive
                    ) {
                        if clearIsArmed {
                            model.clear(language: language)
                            clearIsArmed = false
                        } else {
                            clearIsArmed = true
                        }
                    }
                    .buttonStyle(.borderless)

                    if let statusMessage = model.statusMessage {
                        Text(language.workBuddyStatusMessage(statusMessage))
                            .font(AppTypography.font(9.5, weight: .medium, language: language))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(language.workBuddyStatusMessage(statusMessage))
                    }
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: .top))
                )
            }
        }
        .onAppear {
            model.start()
            if expandOnAppear {
                isExpanded = true
            }
        }
        .onChange(of: expandOnAppear) {
            if expandOnAppear {
                isExpanded = true
            }
        }
        .onChange(of: model.draft) {
            model.updateValidation()
            clearIsArmed = false
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.16),
            value: isExpanded
        )
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(AppTypography.font(10, weight: .medium, language: language))
        .accessibilityElement(children: .combine)
    }

    private func previewView(_ preview: WorkBuddyManualPreview) -> some View {
        let balance = preview.observation.balance
        return VStack(alignment: .leading, spacing: 3) {
            Text(language.workBuddyManualSnapshot)
                .font(AppTypography.font(10.5, weight: .semibold, language: language))
            Text("\(CreditFormatter.exact(balance.remaining, language: language)) Credits")
            if let used = balance.used {
                Text("\(language.workBuddyCompanionName(.used)): \(CreditFormatter.exact(used, language: language))")
            }
            if let total = balance.total {
                Text("\(language.workBuddyCompanionName(.total)): \(CreditFormatter.exact(total, language: language))")
            }
            if let fraction = preview.remainingFraction {
                Text("\(Int((fraction * 100).rounded()))%")
            }
            if balance.isExhausted {
                Text(language.workBuddyConversationCreditsExhausted)
            }
            Text(language.workBuddyScopeName(preview.observation.scope))
            Text(language.workBuddyTierName(preview.observation.tier))
            Text(language.workBuddySharedWithCodeBuddy)
            Text(language.workBuddyManualSnapshot)
        }
        .font(AppTypography.font(9.5, language: language))
        .foregroundStyle(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}

private struct WorkBuddyAccountWebSyncSection: View {
    @ObservedObject var controller: WorkBuddyAccountWebSessionController
    let language: AppLanguage
    let checkAgain: () -> Void
    let syncNow: () -> Void
    let disconnectAccount: () -> Void
    @State private var isShowingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "w.circle")
                    .foregroundStyle(UsageDesign.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.workBuddySection)
                    Text(language.workBuddyAccountWebSubtitle)
                        .font(AppTypography.font(9, language: language))
                        .foregroundStyle(.secondary)
                }
                .font(AppTypography.font(12, weight: .semibold, language: language))
                Spacer()
            }

            if !controller.consentGranted {
                firstConnectionContent
            } else {
                currentSessionContent
            }

            if isShowingDetails {
                sourceAndPrivacyDetails
                    .transition(.opacity)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var firstConnectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.workBuddyAccountWebState(.idle))
                .font(AppTypography.font(10, weight: .medium, language: language))
                .foregroundStyle(.secondary)

            Text(language.workBuddyAccountWebDisclosure)
                .font(AppTypography.font(9.5, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            WorkBuddyLoginConfirmationRow(
                title: language.workBuddyAccountWebConsent,
                isOn: false,
                language: language,
                action: controller.grantConsent
            )

            sessionChoice

            Button(language.workBuddyAccountWebConnect) {
                controller.connect()
            }
            .buttonStyle(.bordered)
            .disabled(!controller.consentGranted)
        }
    }

    @ViewBuilder
    private var currentSessionContent: some View {
        switch controller.flowState {
        case .connected:
            connectedContent
        case .signInRequired:
            Text(language.workBuddyAccountSignInRequired)
                .font(AppTypography.font(10, weight: .medium, language: language))
            Button(language.workBuddyAccountSignInAgain) {
                controller.connect()
            }
            .buttonStyle(.bordered)
            secondaryActions
        case .failed:
            Text(language.workBuddyAccountCouldNotReadCredits)
                .font(AppTypography.font(10, weight: .medium, language: language))
            Button(language.workBuddyAccountSyncAgain, action: syncNow)
                .buttonStyle(.bordered)
            if controller.lastSynchronizedAt != nil {
                autoRefreshControls
            }
            secondaryActions
        case .opening, .synchronizing, .readyToSync:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(language.workBuddyAccountWebState(controller.flowState))
                    .font(AppTypography.font(9.5, weight: .medium, language: language))
            }
            Button(language.checkAgain, action: checkAgain)
                .buttonStyle(.bordered)
            Button(language.workBuddyCancelLogin, role: .cancel) {
                controller.cancel()
            }
            .buttonStyle(.borderless)
        case .idle, .consentRequired:
            Text(language.workBuddyAccountWebState(.idle))
                .font(AppTypography.font(10, weight: .medium, language: language))
                .foregroundStyle(.secondary)
            sessionChoice
            Button(language.workBuddyAccountWebConnect) {
                controller.connect()
            }
            .buttonStyle(.bordered)
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(language.workBuddyAccountWebState(.connected))
                    .font(AppTypography.font(10.5, weight: .semibold, language: language))
                if let lastSynchronizedAt = controller.lastSynchronizedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(
                            language.workBuddyAccountUpdated(
                                at: lastSynchronizedAt,
                                now: context.date
                            )
                        )
                    }
                    .font(AppTypography.font(9.5, language: language))
                    .foregroundStyle(.secondary)
                }
            }
            autoRefreshControls
            HStack(spacing: 8) {
                Button(language.workBuddyAccountWebSyncNow, action: syncNow)
                    .buttonStyle(.bordered)
                    .disabled(controller.flowState == .synchronizing)
                Spacer()
                secondaryActions
            }
        }
    }

    private var autoRefreshControls: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(
                language.workBuddyAccountAutoRefresh,
                isOn: $controller.autoRefreshEnabled
            )
            .toggleStyle(.switch)
            .tint(UsageDesign.blue)
            .font(AppTypography.font(10, weight: .medium, language: language))
            Text(
                controller.autoRefreshEnabled
                    ? language.workBuddyAccountEveryMinute
                    : language.workBuddyAccountManualOnly
            )
            .font(AppTypography.font(9, language: language))
            .foregroundStyle(.secondary)
            if controller.autoRefreshEnabled,
               let nextRefreshAt = controller.nextAutoRefreshAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(
                        0,
                        Int(ceil(nextRefreshAt.timeIntervalSince(context.date)))
                    )
                    Text(
                        language.workBuddyAccountNextRefresh(
                            language.workBuddyAccountRefreshInterval(
                                seconds: seconds
                            )
                        )
                    )
                }
                .font(AppTypography.font(9, language: language))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var secondaryActions: some View {
        Menu {
            Button(language.workBuddyAccountWebOpenUsage) {
                controller.openAccountUsage()
            }
            Button(language.workBuddyAccountSignInAgain) {
                controller.connect()
            }
            Button(language.workBuddyAccountPrivacyAndSourceDetails) {
                isShowingDetails.toggle()
            }
            Divider()
            Button(
                language.workBuddyAccountWebDisconnect,
                role: .destructive,
                action: disconnectAccount
            )
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 24, height: 20)
        }
        .menuStyle(.borderlessButton)
        .help(language.workBuddyAccountMoreActions)
        .accessibilityLabel(language.workBuddyAccountMoreActions)
    }

    private var sessionChoice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.workBuddyAccountWebSessionChoice)
                .font(AppTypography.font(9.5, weight: .medium, language: language))
                .foregroundStyle(.secondary)
            Picker("", selection: $controller.sessionMode) {
                ForEach(WorkBuddyAccountWebSessionMode.allCases) { mode in
                    Text(language.workBuddyAccountWebSessionMode(mode)).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel(language.workBuddyAccountWebSessionChoice)
        }
    }

    private var sourceAndPrivacyDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .opacity(0.35)
            Text(language.workBuddyAccountWebDisclosure)
                .font(AppTypography.font(9, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            sessionChoice
            if let safeDiagnosticCode = controller.safeDiagnosticCode {
                Text(
                    "\(language.workBuddyAccountWebSafeDiagnostic): "
                        + safeDiagnosticCode
                )
                .font(AppTypography.font(8.5, language: language))
                .foregroundStyle(.secondary)
            }
            if let snapshot = controller.latestCreditSnapshot {
                VStack(alignment: .leading, spacing: 4) {
                    accountCreditRow(
                        language.workBuddySubscriptionRemaining,
                        value: snapshot.subscriptionRemaining
                    )
                    accountCreditRow(
                        language.workBuddyAddOnRemaining,
                        value: snapshot.addOnRemaining
                    )
                    accountCreditRow(
                        language.workBuddyBenefitGiftRemaining,
                        value: snapshot.benefitGiftRemaining
                    )
                    accountCreditRow(
                        language.workBuddyTotalAvailable,
                        value: snapshot.calculatedTotalRemaining
                    )
                    Text(language.workBuddyConfirmedAt(snapshot.observedAt))
                }
                .font(AppTypography.font(9, weight: .medium, language: language))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func accountCreditRow(_ label: String, value: Decimal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
            Spacer(minLength: 8)
            Text(
                CreditFormatter.exactTwoDecimal(value, language: language)
            )
            .font(AppTypography.numericFont(9, weight: .medium))
        }
    }
}

private struct WorkBuddyLoginAssistanceSection: View {
    @ObservedObject var coordinator: WorkBuddyLoginCoordinator
    let language: AppLanguage

    private let officialInstructionsURL = URL(
        string: "https://www.workbuddy.cn/docs/workbuddy/Usage"
    )!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                language.workBuddyLoginForDataSync,
                systemImage: "person.crop.circle.badge.checkmark"
            )
            .font(AppTypography.font(12, weight: .semibold, language: language))

            Text(language.workBuddyLoginPrivacySummary)
                .font(AppTypography.font(9.5, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            installationStatus

            Button(language.workBuddyLoginForDataSync) {
                coordinator.startLogin()
            }
            .buttonStyle(.bordered)
            .accessibilityHint(language.workBuddyLoginPrivacySummary)

            if coordinator.flowState.isActive
                || coordinator.flowState == .completed
                || {
                    if case .failed = coordinator.flowState { return true }
                    return false
                }() {
                Text(language.workBuddyAccountType)
                    .font(AppTypography.font(9.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)

                Picker("", selection: $coordinator.accountMode) {
                    ForEach(WorkBuddyLoginAccountMode.allCases) { mode in
                        Text(language.workBuddyAccountMode(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(language.workBuddyAccountType)
                .accessibilityHint(language.workBuddyAccountModeHint)

                Text(language.workBuddyAccountModeHint)
                    .font(AppTypography.font(9, language: language))
                    .foregroundStyle(.secondary)

                WorkBuddyLoginConfirmationRow(
                    title: language.workBuddyLoginPrivacyConfirmation,
                    isOn: coordinator.privacyConfirmed,
                    language: language,
                    action: {
                        coordinator.setPrivacyConfirmed(
                            !coordinator.privacyConfirmed
                        )
                    }
                )

                if coordinator.installation.application?
                    .signatureTrust.requiresOfficialInstallConfirmation == true {
                    Text(language.workBuddyOfficialInstallWarning)
                        .font(AppTypography.font(9.5, weight: .medium, language: language))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(language.workBuddyOfficialInstallWarning)

                    WorkBuddyLoginConfirmationRow(
                        title: language.workBuddyOfficialInstallConfirmation,
                        isOn: coordinator.officialInstallConfirmed,
                        language: language,
                        action: {
                            coordinator.setOfficialInstallConfirmed(
                                !coordinator.officialInstallConfirmed
                            )
                        }
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(language.workBuddyLoginStepsTitle)
                        .font(AppTypography.font(10, weight: .semibold, language: language))
                    ForEach(
                        Array(
                            language.workBuddyLoginSteps(
                                coordinator.accountMode
                            ).enumerated()
                        ),
                        id: \.offset
                    ) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
                .font(AppTypography.font(9.5, language: language))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)

                HStack(spacing: 6) {
                    Button(language.workBuddyOpenApplication) {
                        coordinator.openOfficialApplication()
                    }
                    .disabled(!coordinator.canOpenOfficialApplication)

                    Button(language.checkAgain) {
                        coordinator.checkAgain()
                    }
                    .disabled(
                        coordinator.flowState != .awaitingUserCompletion
                            && coordinator.flowState != .completed
                    )
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 5) {
                    Button(
                        language.workBuddyCancelLogin,
                        role: .cancel
                    ) {
                        coordinator.cancel()
                    }
                    .buttonStyle(.borderless)

                    Link(
                        language.workBuddyOpenOfficialLoginInstructions,
                        destination: officialInstructionsURL
                    )
                    .accessibilityHint(language.workBuddyLoginPrivacySummary)
                }

                flowStatus
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var installationStatus: some View {
        switch coordinator.installation {
        case .notInstalled:
            Text(language.workBuddyNotInstalled)
                .foregroundStyle(.red)
        case .invalidBundleIdentity:
            Text(language.workBuddyInvalidIdentity)
                .foregroundStyle(.red)
        case let .available(application):
            Text(
                [
                    language.workBuddyInstalled,
                    application.version
                ].compactMap { $0 }.joined(separator: " · ")
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var flowStatus: some View {
        switch coordinator.flowState {
        case .awaitingUserCompletion:
            Text(language.workBuddyAwaitingCompletion)
        case .completed:
            Text(language.workBuddySafeCompletionResult)
        case let .failed(failure):
            Text(language.workBuddyLoginFailure(failure))
        case .opening:
            ProgressView()
                .controlSize(.small)
        case .idle, .confirmationRequired, .readyToOpen, .checking, .cancelled:
            EmptyView()
        }
    }
}

private struct WorkBuddyLoginConfirmationRow: View {
    let title: String
    let isOn: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? UsageDesign.blue : Color.secondary)
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(
            isOn
                ? language.enabledAccessibilityValue
                : language.disabledAccessibilityValue
        )
    }
}

private struct ProviderLoginAssistanceSection: View {
    let options: [ProviderLoginOption]
    let language: AppLanguage
    let checkAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.localLiveProvidersSection)
                .font(AppTypography.font(10.5, weight: .medium, language: language))
                .foregroundStyle(.secondary)

            ForEach(options) { option in
                VStack(alignment: .leading, spacing: 7) {
                    Label(option.providerName, systemImage: "person.crop.circle.badge.checkmark")
                        .font(AppTypography.font(12.5, weight: .semibold, language: language))

                    Link(destination: option.officialApplicationURL) {
                        Label(language.loginForDataSync, systemImage: "arrow.up.forward.app")
                    }
                    .help(language.loginForDataSyncHint)
                    .accessibilityHint(language.loginForDataSyncHint)

                    Button(language.checkAgain, action: checkAgain)
                        .buttonStyle(.bordered)
                        .accessibilityHint(language.noLocalLiveAgentsGuidance)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
        }
    }
}

private struct AssistantDensitySettingRow: View {
    let language: AppLanguage
    @Binding var selection: DesktopAssistantDensity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(language.desktopAssistantDensity, systemImage: "rectangle.3.group")
                .labelStyle(SettingsRowLabelStyle())
                .font(AppTypography.font(12.5, weight: .medium, language: language))

            HStack(spacing: 4) {
                ForEach(DesktopAssistantDensity.allCases, id: \.rawValue) { density in
                    Button {
                        selection = density
                    } label: {
                        Text(language.desktopAssistantDensityName(density))
                            .font(AppTypography.font(9.5, weight: .medium, language: language))
                            .foregroundStyle(selection == density ? Color.white : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background {
                                Capsule()
                                    .fill(
                                        selection == density
                                            ? UsageDesign.blue
                                            : Color.secondary.opacity(0.10)
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == density ? .isSelected : [])
                }
            }
        }
    }
}

/// Settings rows put their symbol in a fixed-width column, so the titles
/// start at one edge whatever each symbol's own width. A plain `Label` sizes
/// the icon to the glyph: "globe", "power" and "pin" left the titles at three
/// different offsets.
private struct SettingsRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: 18, alignment: .center)
            configuration.title
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    let language: AppLanguage
    @Binding var isOn: Bool
    /// Direction D, used by Claude: system type and the system accent.
    var refined = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .labelStyle(SettingsRowLabelStyle())
                    .font(
                        refined
                            ? AppTypography.systemFont(13)
                            : AppTypography.font(12.5, weight: .medium, language: language)
                    )
                Spacer()
                ZStack {
                    Capsule()
                        .fill(isOn ? onColor : Color.secondary.opacity(0.24))
                        .frame(width: 34, height: 19)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 15, height: 15)
                        .shadow(color: Color.black.opacity(0.16), radius: 1, y: 0.5)
                        .offset(x: isOn ? 7.5 : -7.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(
            isOn ? language.enabledAccessibilityValue : language.disabledAccessibilityValue
        )
        .animation(.easeInOut(duration: 0.16), value: isOn)
    }

    private var onColor: Color {
        refined ? Color.accentColor : UsageDesign.blue
    }
}

/// Claude's actions are native buttons, like Sectorium's and Settings', so
/// they sit on the Tab route even with Full Keyboard Access off. The enabled
/// state is set here every update: SwiftUI's `.disabled` does not reach an
/// AppKit control on its own.
private struct ClaudeSettingsActionButton: NSViewRepresentable {
    enum Role: Equatable {
        case primary
        case secondary
        case link
        case disclosure(expanded: Bool)
    }

    let title: String
    let identifier: String
    var role: Role = .secondary
    var isEnabled = true
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = ClaudeSettingsFocusableButton(
            title: title,
            target: context.coordinator,
            action: #selector(Coordinator.activate(_:))
        )
        button.refusesFirstResponder = false
        button.focusRingType = .exterior
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        configure(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        configure(button)
    }

    private func configure(_ button: NSButton) {
        switch role {
        case .primary, .secondary:
            button.isBordered = true
            button.bezelStyle = .push
            button.controlSize = .regular
            button.bezelColor = role == .primary ? .controlAccentColor : nil
            button.keyEquivalent = ""
            button.image = nil
            button.title = title
        case .link, .disclosure:
            button.isBordered = false
            button.bezelStyle = .inline
            button.controlSize = .regular
            button.bezelColor = nil
            let color: NSColor = role == .link ? .controlAccentColor : .labelColor
            let font = role == .link
                ? NSFont.systemFont(ofSize: 12)
                : NSFont.systemFont(ofSize: 12, weight: .semibold)
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: color, .font: font]
            )
            if case let .disclosure(expanded) = role {
                button.image = NSImage(
                    systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                    accessibilityDescription: nil
                )?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
                button.imagePosition = .imageLeading
                button.contentTintColor = .secondaryLabelColor
                button.setAccessibilityValue(expanded ? "expanded" : "collapsed")
            } else {
                button.image = nil
            }
        }
        (button as? ClaudeSettingsFocusableButton)?.setSettingsEnabled(isEnabled)
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        button.invalidateIntrinsicContentSize()
    }

    @MainActor final class Coordinator: NSObject {
        var action: @MainActor () -> Void
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        @objc func activate(_ sender: NSButton) {
            guard sender.isEnabled else { return }
            action()
        }
    }
}

private final class ClaudeSettingsFocusableButton: NSButton {
    private var settingsEnabled = true

    override var isEnabled: Bool {
        get { settingsEnabled && super.isEnabled }
        set { super.isEnabled = settingsEnabled && newValue }
    }

    func setSettingsEnabled(_ enabled: Bool) {
        settingsEnabled = enabled
        super.isEnabled = enabled
    }

    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHidden && alphaValue > 0 }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds.insetBy(dx: -6, dy: -6)) }
        return accepted
    }
}

private struct SettingsContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LanguageSettingRow: View {
    @Binding var language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Label(language.languageSetting, systemImage: "globe")
                .labelStyle(SettingsRowLabelStyle())
                .font(AppTypography.font(12.5, weight: .medium, language: language))
            Spacer(minLength: 6)
            HStack(spacing: 3) {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        language = option
                    } label: {
                        Text(option.displayName)
                            .font(AppTypography.font(9.5, weight: .medium, language: option))
                            .foregroundStyle(language == option ? Color.white : Color.secondary)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background {
                                Capsule()
                                    .fill(language == option ? UsageDesign.blue : Color.secondary.opacity(0.10))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(language == option ? .isSelected : [])
                }
            }
        }
    }
}


/// Native main-window entry into the existing provider-specific settings
/// content. The coordinator and preference keys are shared with UsageSettingsCard.
public struct AgentSpecificSettingsSheet: View {
    @ObservedObject private var store: UsageStore
    private let providerID: String
    private let close: () -> Void
    private let claudeSettings: ClaudeBrowserSettingsModel?
    private let antigravitySettings: AntigravitySettingsModel?
    private let workBuddySettings: WorkBuddySettingsModel?
    private let workBuddyLogin: WorkBuddyLoginCoordinator?
    private let workBuddyAccountWebSync: WorkBuddyAccountWebSessionController?
    @AppStorage("display.showAPICostCard") private var showAPICost = false

    public init(
        store: UsageStore, providerID: String,
        claudeSettings: ClaudeBrowserSettingsModel? = nil,
        antigravitySettings: AntigravitySettingsModel? = nil,
        workBuddySettings: WorkBuddySettingsModel? = nil,
        workBuddyLogin: WorkBuddyLoginCoordinator? = nil,
        workBuddyAccountWebSync: WorkBuddyAccountWebSessionController? = nil,
        close: @escaping () -> Void
    ) {
        self.store = store
        self.providerID = providerID
        self.claudeSettings = claudeSettings
        self.antigravitySettings = antigravitySettings
        self.workBuddySettings = workBuddySettings
        self.workBuddyLogin = workBuddyLogin
        self.workBuddyAccountWebSync = workBuddyAccountWebSync
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(store.language == .simplifiedChinese ? "完成" : "Done", action: close)
                    .keyboardShortcut(.cancelAction)
            }
            if let coordinator = store.agentSettings,
               let id = AgentConnectorID(rawValue: providerID) {
                ScrollView {
                    AgentSpecificSettingsContent(
                        coordinator: coordinator,
                        providerID: id,
                        language: store.language,
                        showAPICost: $showAPICost,
                        claudeSettings: self.claudeSettings,
                        antigravitySettings: self.antigravitySettings,
                        workBuddySettings: self.workBuddySettings,
                        workBuddyLogin: self.workBuddyLogin,
                        workBuddyAccountWebSync: self.workBuddyAccountWebSync,
                        presentation: store.presentationCards.first { card in
                            ProviderProductID.allCases.first { $0.settingsProviderID == providerID }
                                .flatMap(ProviderProductStatePolicy.connectorID(for:))?.rawValue == card.id
                        },
                        checkAgain: { Task { await store.checkLocalSessionAgain() } },
                        syncWorkBuddyAccount: { Task { await store.syncWorkBuddyAccountNow() } },
                        disconnectWorkBuddyAccount: { Task { await store.disconnectWorkBuddyAccount() } }
                    )
                }
            } else {
                Text(store.language == .simplifiedChinese ? "此智能体的设置不可用。" : "Settings for this agent are unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 340, idealWidth: 420, minHeight: 300, idealHeight: 520)
        .accessibilityIdentifier("uma.agent.settings-sheet")
    }

    /// Matches the button that opened it, "Claude Settings…".
    private var title: String {
        guard let name = ProviderProductID.allCases
            .first(where: { $0.settingsProviderID == providerID })?.displayName
        else { return store.language.agentSettings }
        return store.language == .simplifiedChinese ? "\(name) 设置" : "\(name) Settings"
    }
}
