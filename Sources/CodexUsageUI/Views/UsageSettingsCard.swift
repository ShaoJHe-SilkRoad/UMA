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
    let workBuddySettings: WorkBuddySettingsModel?
    let workBuddyLogin: WorkBuddyLoginCoordinator?
    let workBuddyAccountWebSync: WorkBuddyAccountWebSessionController?
    let providerLoginOptions: [ProviderLoginOption]
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
                    showUsageSummary: $showUsageSummary,
                    showRecentTasks: $showRecentTasks,
                    showAPICost: $showAPICost,
                    claudeSettings: claudeSettings,
                    workBuddySettings: workBuddySettings,
                    workBuddyLogin: workBuddyLogin,
                    workBuddyAccountWebSync: workBuddyAccountWebSync,
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

private struct AgentSpecificSettingsContent: View {
    @ObservedObject var coordinator: AgentSettingsCoordinator
    let providerID: AgentConnectorID
    let language: AppLanguage
    @Binding var showUsageSummary: Bool
    @Binding var showRecentTasks: Bool
    @Binding var showAPICost: Bool
    let claudeSettings: ClaudeBrowserSettingsModel?
    let workBuddySettings: WorkBuddySettingsModel?
    let workBuddyLogin: WorkBuddyLoginCoordinator?
    let workBuddyAccountWebSync: WorkBuddyAccountWebSessionController?
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
        VStack(alignment: .leading, spacing: 9) {
            Text(displayName)
                .font(AppTypography.font(13, weight: .semibold, language: language))

            if entry?.requiresSetup == true {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.agentSetupRequired)
                        .font(
                            AppTypography.font(
                                10,
                                weight: .semibold,
                                language: language
                            )
                        )
                    Text(language.agentSetupRequiredGuidance)
                        .font(AppTypography.font(9, language: language))
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else if entry?.isActive == false,
                      entry?.hasBeenDetected == true {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.notCurrentlyRunning)
                        .font(
                            AppTypography.font(
                                10,
                                weight: .semibold,
                                language: language
                            )
                        )
                    Text(language.savedSettingsApplyWhenDetected)
                        .font(AppTypography.font(9, language: language))
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }

            SettingsToggleRow(
                title: language.monitoringEnabled,
                systemImage: "waveform.path.ecg",
                language: language,
                isOn: Binding(
                    get: {
                        coordinator.isMonitoringEnabled(for: providerID)
                    },
                    set: {
                        coordinator.setMonitoringEnabled(
                            $0,
                            for: providerID
                        )
                    }
                )
            )

            if providerID == AgentPreferenceRecord.codexProviderID {
                Divider().opacity(0.35)
                SettingsToggleRow(
                    title: language.usageSummaryCard,
                    systemImage: "gauge.with.dots.needle.67percent",
                    language: language,
                    isOn: codexDetailBinding(
                        keyPath: \.showUsageSummary,
                        legacy: $showUsageSummary
                    )
                )
                SettingsToggleRow(
                    title: language.recentTasks,
                    systemImage: "list.bullet.rectangle",
                    language: language,
                    isOn: codexDetailBinding(
                        keyPath: \.showRecentTasks,
                        legacy: $showRecentTasks
                    )
                )
                SettingsToggleRow(
                    title: language.costCard,
                    systemImage: "dollarsign.circle",
                    language: language,
                    isOn: codexDetailBinding(
                        keyPath: \.showAPICost,
                        legacy: $showAPICost
                    )
                )
            }

            if providerID == AgentPreferenceRecord.claudeProviderID,
               let claudeSettings {
                Divider().opacity(0.35)
                ClaudeBrowserSettingsSection(
                    model: claudeSettings,
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

    private func codexDetailBinding(
        keyPath: WritableKeyPath<CodexDetailPreferences, Bool>,
        legacy: Binding<Bool>
    ) -> Binding<Bool> {
        Binding(
            get: {
                coordinator.record(for: providerID)
                    .providerSettings.codexDetails?[keyPath: keyPath]
                    ?? legacy.wrappedValue
            },
            set: { newValue in
                var details = coordinator.record(for: providerID)
                    .providerSettings.codexDetails ?? .defaults
                details[keyPath: keyPath] = newValue
                legacy.wrappedValue = newValue
                coordinator.setCodexDetails(details, for: providerID)
            }
        )
    }
}

private struct ClaudeBrowserSettingsSection: View {
    @ObservedObject var model: ClaudeBrowserSettingsModel
    let language: AppLanguage
    @State private var showingConsent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language == .simplifiedChinese ? "浏览器同步 · 实验性" : "Browser Sync · Experimental")
                .font(
                    AppTypography.font(
                        10.5,
                        weight: .semibold,
                        language: language
                    )
                )
            Text(
                language == .simplifiedChinese
                    ? "通过 Claude 官方使用量页面自动读取套餐配额。登录保留在 Safari 中。无需 API 密钥、钥匙串或 Cookie 访问。"
                    : "Automatic plan quota from Claude's official Usage page. Login stays in Safari. No API key, Keychain, or Cookie access."
            )
            .font(AppTypography.font(9, language: language))
            .foregroundStyle(.secondary)
            stateSummary

            if model.consentGranted {
                SettingsToggleRow(
                    title: language == .simplifiedChinese ? "自动刷新" : "Auto Refresh",
                    systemImage: "arrow.clockwise",
                    language: language,
                    isOn: Binding(
                        get: { model.autoRefreshEnabled },
                        set: { model.setAutoRefreshEnabled($0) }
                    )
                )
                Text(
                    model.autoRefreshEnabled
                        ? (language == .simplifiedChinese ? "每 5 分钟" : "Every 5 minutes")
                        : (language == .simplifiedChinese ? "仅手动" : "Manual only")
                )
                .font(AppTypography.font(9, language: language))
                .foregroundStyle(.secondary)

                SettingsToggleRow(
                    title: language == .simplifiedChinese
                        ? "需要时允许 UMA 启动 Safari"
                        : "Allow UMA to launch Safari when needed",
                    systemImage: "safari",
                    language: language,
                    isOn: Binding(
                        get: { model.allowSafariLaunch },
                        set: { model.setAllowSafariLaunch($0) }
                    )
                )
                Text(
                    language == .simplifiedChinese
                        ? "默认关闭。关闭时，Safari 不可用会保留已缓存或较早状态。"
                        : "Off by default. When Off, unavailable Safari leaves only Cached or Stale data."
                )
                .font(AppTypography.font(9, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                primaryAction
                if model.consentGranted, showsSecondaryOpenUsage {
                    Button(language == .simplifiedChinese ? "打开使用量页面" : "Open Usage Page") {
                        model.openUsagePage()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(
                        "claude.browser.open-usage"
                    )
                }
                if model.consentGranted {
                    Button(language.claudeDisableIntegration) {
                        model.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(
                        "claude.browser.disconnect"
                    )
                }
            }
            .disabled(model.actionInProgress)

            if showingConsent, !model.consentGranted {
                consentConfirmation
            }

            if let safeError = model.safeError {
                Text(language.claudeBrowserError(safeError))
                    .font(AppTypography.font(9, language: language))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(
                language == .simplifiedChinese
                    ? "经您授权后，UMA 浏览器伴侣最多保留一个非活动专用标签页，在各轮之间安全复用；每次读取都会先验证精确的 Claude 使用量路由，并且断开 Claude 时会关闭该标签页。网站访问可在 Safari 设置中撤销。"
                    : "After you grant access, the UMA Browser Companion keeps at most one inactive dedicated tab and safely reuses it across cycles; every read first verifies the exact Claude Usage route, and Disconnect Claude closes that tab. Website access can be revoked in Safari Settings."
            )
            .font(AppTypography.font(9, language: language))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if model.consentGranted {
                Button(
                    language == .simplifiedChinese
                        ? "打开 Safari 访问设置"
                        : "Open Safari Access Settings",
                    action: model.openSafariAccessSettings
                )
                .buttonStyle(.plain)
                .foregroundStyle(UsageDesign.blue)
                .accessibilityIdentifier("claude.browser.open-access-settings")
            }

            Divider().opacity(0.35)
            Text(language.claudeSourceTransparency)
                .font(
                    AppTypography.font(
                        10,
                        weight: .semibold,
                        language: language
                    )
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(language == .simplifiedChinese ? "来源：Claude 官方使用量页面 · 浏览器同步 · 实验性" : "Source: Claude official Usage page · Browser Sync · Experimental")
                Text(language == .simplifiedChinese ? "登录：系统默认浏览器" : "Login: System default browser")
                Text(language == .simplifiedChinese ? "Google / Claude 密码：未访问" : "Google / Claude password: Not accessed")
                Text(language == .simplifiedChinese ? "API 密钥：不需要" : "API key: Not required")
                Text(language == .simplifiedChinese ? "钥匙串：未访问" : "Keychain: Not accessed")
                Text(language == .simplifiedChinese ? "Cookie：保留在浏览器中；UMA 不读取或导出" : "Cookies: Remain inside the browser; not read or exported by UMA")
                Text(language == .simplifiedChinese ? "页面数据：仅规范化配额百分比与重置时间" : "Page data: Normalized quota percentages and reset times only")
                Text(language == .simplifiedChinese ? "聊天、项目、身份与账单：未访问" : "Chats, projects, identity, and billing: Not accessed")
            }
            .font(AppTypography.font(9, language: language))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(
                "claude.browser.source-transparency"
            )
        }
        .onAppear {
            model.checkCompanion()
        }
    }

    private var showsSecondaryOpenUsage: Bool {
        switch model.state {
        case .fresh, .cached, .stale:
            true
        default:
            false
        }
    }

    private var consentConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                language == .simplifiedChinese
                    ? "启用 Claude 浏览器同步？"
                    : "Enable Claude Browser Sync?"
            )
            .font(AppTypography.font(10.5, weight: .semibold, language: language))

            Text(language.claudeConsentDisclosure)
                .font(AppTypography.font(9, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(language == .simplifiedChinese ? "取消" : "Cancel") {
                    showingConsent = false
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("claude.browser.consent.cancel")

                Button(language == .simplifiedChinese ? "继续" : "Continue") {
                    showingConsent = false
                    model.connectWithConsent()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("claude.browser.consent.continue")
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.quaternary.opacity(0.7))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.45),
                    lineWidth: 0.5
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claude.browser.consent")
    }

    @ViewBuilder
    private var stateSummary: some View {
        if let action = model.activeAction {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(language.claudeBrowserActionStatus(action))
            }
            .accessibilityElement(children: .combine)
        } else {
            stateSummaryContent
        }
    }

    @ViewBuilder
    private var stateSummaryContent: some View {
        switch model.state {
        case .disconnected:
            Text(language.claudeNotConfigured)
        case .checking:
            Text(language == .simplifiedChinese ? "正在检查浏览器伴侣…" : "Checking Browser Companion…")
        case .waitingForUsagePage:
            Text(language == .simplifiedChinese ? "正在等待第一次自动使用量读取" : "Waiting for the first automatic Usage read")
        case .websiteAccessRequired:
            Text(language == .simplifiedChinese ? "需要网站访问权限" : "Website access required")
        case .signInRequired:
            Text(language == .simplifiedChinese ? "需要登录" : "Sign in required")
        case .waitingForSafari:
            Text(language == .simplifiedChinese ? "正在等待 Safari" : "Waiting for Safari")
        case let .fresh(updated):
            VStack(alignment: .leading, spacing: 2) {
                Text(language.claudeConnected)
                Text(language.claudeUpdated(updated))
            }
        case let .cached(updated):
            VStack(alignment: .leading, spacing: 2) {
                Text(language.claudeCached)
                Text(language.claudeUpdated(updated))
                Text(language.claudeUpdatesPageDriven)
            }
        case let .stale(updated):
            VStack(alignment: .leading, spacing: 2) {
                Text(language.claudeStale)
                Text(language.claudeUpdated(updated))
                Text(language.claudeUpdatesPageDriven)
            }
        case .companionDisabled:
            Text(language == .simplifiedChinese ? "浏览器伴侣未启用" : "Browser Companion is disabled")
        case .companionOutdated:
            Text(language == .simplifiedChinese ? "浏览器伴侣需要更新" : "Browser Companion needs an update")
        case .unsupportedBrowser:
            Text(language == .simplifiedChinese ? "默认浏览器暂不受支持" : "The default browser is not supported")
        case .browserUnavailable:
            Text(language == .simplifiedChinese ? "默认浏览器不可用" : "The default browser is unavailable")
        case .nativeHostMissing:
            Text(language == .simplifiedChinese ? "浏览器伴侣需要修复" : "Browser Companion needs repair")
        case .nativeHostMismatched:
            Text(language == .simplifiedChinese ? "浏览器伴侣版本不匹配" : "Browser Companion version mismatch")
        case .routeChanged:
            Text(language == .simplifiedChinese ? "Claude 使用量页面已更改；同步已安全停止" : "Claude's Usage page changed; sync stopped safely")
        case .failed:
            Text(language.failureStatus)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.state {
        case .disconnected:
            Button(
                language.claudeEnableIntegration,
                action: { showingConsent = true }
            )
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("claude.browser.connect")
        case .fresh, .cached, .stale:
            Button(
                language == .simplifiedChinese ? "立即同步" : "Sync Now",
                action: model.syncNow
            )
            .buttonStyle(.bordered)
            .accessibilityIdentifier("claude.browser.sync-now")
        case .waitingForUsagePage:
            Button(
                language == .simplifiedChinese ? "立即同步" : "Sync Now",
                action: model.syncNow
            )
            .buttonStyle(.bordered)
            .accessibilityIdentifier("claude.browser.sync-now")
        case .websiteAccessRequired:
            Button(
                language == .simplifiedChinese ? "授予访问权限" : "Grant Access",
                action: model.grantWebsiteAccess
            )
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("claude.browser.grant-access")
        case .signInRequired, .waitingForSafari:
            Button(
                language == .simplifiedChinese ? "打开 Claude 使用量" : "Open Claude Usage",
                action: model.openUsagePage
            )
            .buttonStyle(.bordered)
            .accessibilityIdentifier("claude.browser.open-usage")
        case .companionDisabled, .companionOutdated,
             .nativeHostMissing, .nativeHostMismatched:
            Button(
                language == .simplifiedChinese ? "修复伴侣" : "Repair Companion",
                action: model.repairCompanion
            )
            .buttonStyle(.bordered)
            .accessibilityIdentifier("claude.browser.repair")
        case .unsupportedBrowser, .browserUnavailable, .routeChanged, .failed:
            Button(
                language == .simplifiedChinese ? "重新检查" : "Check Again",
                action: model.checkCompanion
            )
            .buttonStyle(.bordered)
            .accessibilityIdentifier("claude.browser.check-again")
        case .checking:
            ProgressView().controlSize(.small)
        }
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

private struct SettingsToggleRow: View {
    let title: String
    let systemImage: String
    let language: AppLanguage
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(AppTypography.font(12.5, weight: .medium, language: language))
                Spacer()
                ZStack {
                    Capsule()
                        .fill(isOn ? UsageDesign.blue : Color.secondary.opacity(0.24))
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
