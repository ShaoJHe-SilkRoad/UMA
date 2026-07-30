import AppKit
import SwiftUI

@MainActor
public final class UsagePanelNavigationCoordinator: ObservableObject {
    public struct ProviderSelection: Equatable, Sendable {
        public let providerID: String
        public let revision: UInt64
    }

    @Published public private(set) var providerSelection: ProviderSelection?
    private var revision: UInt64 = 0

    public init() {}

    public func selectProvider(_ providerID: String) {
        revision &+= 1
        providerSelection = ProviderSelection(
            providerID: providerID,
            revision: revision
        )
    }
}

public struct UsagePanelView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var navigation: UsagePanelNavigationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usagePanelOuterContourOwner) private var outerContourOwner
    @AppStorage("display.showUsageSummaryCard") private var storedShowUsageSummary = true
    @AppStorage("display.showRecentTasksCard") private var storedShowRecentTasks = false
    @AppStorage("display.showAPICostCard") private var storedShowAPICost = false
    @State private var isShowingSettings: Bool
    @State private var providerExpansion: MainPanelProviderExpansionState
    @State private var settingsDestination: UsageSettingsDestination?
    @State private var measuredContentHeight: CGFloat?
    @State private var measuredSettingsCardHeight: CGFloat?

    let tuning: GlassTuning
    private let preferencesEnabled: Bool
    private let onHeightChange: ((CGFloat) -> Void)?
    private let localAccessConfirmationAction: CodexLocalAccessConfirmationAction?
    private let claudeSettings: ClaudeStatusLineSettingsModel?
    private let workBuddySettings: WorkBuddySettingsModel?
    private let workBuddyLogin: WorkBuddyLoginCoordinator?
    private let workBuddyAccountWebSync: WorkBuddyAccountWebSessionController?
    private let appearanceOverride: UsagePanelAppearanceOverride?
    private let renderedHeightOverride: CGFloat?
    private let cardVisibilityOverride: UsagePanelCardVisibility?

    public init(
        store: UsageStore,
        tuning: GlassTuning,
        preferencesEnabled: Bool = true,
        settingsInitiallyPresented: Bool = false,
        settingsDestinationProviderID: String? = nil,
        expandedProviderIDs: Set<String> = [],
        navigation: UsagePanelNavigationCoordinator? = nil,
        onHeightChange: ((CGFloat) -> Void)? = nil,
        localAccessConfirmationAction: CodexLocalAccessConfirmationAction? = nil,
        claudeSettings: ClaudeStatusLineSettingsModel? = nil,
        workBuddySettings: WorkBuddySettingsModel? = nil,
        workBuddyLogin: WorkBuddyLoginCoordinator? = nil,
        workBuddyAccountWebSync: WorkBuddyAccountWebSessionController? = nil,
        appearanceOverride: UsagePanelAppearanceOverride? = nil,
        renderedHeightOverride: CGFloat? = nil,
        cardVisibilityOverride: UsagePanelCardVisibility? = nil
    ) {
        self.store = store
        _navigation = ObservedObject(
            wrappedValue: navigation ?? UsagePanelNavigationCoordinator()
        )
        self.tuning = tuning
        self.preferencesEnabled = preferencesEnabled
        self.onHeightChange = onHeightChange
        self.localAccessConfirmationAction = localAccessConfirmationAction
        self.claudeSettings = claudeSettings
        self.workBuddySettings = workBuddySettings
        self.workBuddyLogin = workBuddyLogin
        self.workBuddyAccountWebSync = workBuddyAccountWebSync
        self.appearanceOverride = appearanceOverride
        self.renderedHeightOverride = renderedHeightOverride
        self.cardVisibilityOverride = cardVisibilityOverride
        _isShowingSettings = State(initialValue: settingsInitiallyPresented)
        _settingsDestination = State(
            initialValue: settingsDestinationProviderID.map {
                $0 == AgentPreferenceRecord.workBuddyProviderID.rawValue
                    ? .workBuddy
                    : .agent($0)
            }
        )
        _providerExpansion = State(
            initialValue: MainPanelProviderExpansionState(
                expandedProviderIDs: expandedProviderIDs
            )
        )
    }

    private var showUsageSummary: Bool {
        cardVisibilityOverride?.showUsageSummary
            ?? (preferencesEnabled ? storedShowUsageSummary : true)
    }

    private var showRecentTasks: Bool {
        cardVisibilityOverride?.showRecentTasks
            ?? (preferencesEnabled ? storedShowRecentTasks : true)
    }

    private var showAPICost: Bool {
        cardVisibilityOverride?.showAPICost
            ?? (preferencesEnabled ? storedShowAPICost : true)
    }

    private var presentation: CodexConnectionPresentation {
        .make(
            state: store.currentState,
            decision: store.monitorConsentDecision,
            hasPriorRealSnapshot: store.hasPriorRealSnapshot,
            language: store.language
        )
    }

    private var retainedSnapshotRecovery: RetainedSnapshotRecoveryPresentation? {
        RetainedSnapshotRecoveryPresentation(
            presentation: presentation,
            language: store.language
        )
    }

    private var preferredHeight: CGFloat {
        if let renderedHeightOverride {
            return UsagePanelMetrics.resolvedContentHeight(renderedHeightOverride)
        }
        return UsagePanelMetrics.resolvedContentHeight(measuredContentHeight)
    }

    private var displayedHeight: CGFloat {
        guard isShowingSettings else { return preferredHeight }
        guard let measuredSettingsCardHeight else {
            return UsagePanelMetrics.settingsMinimumHeight
        }
        return UsageSettingsSizing.panelHeight(
            cardHeight: measuredSettingsCardHeight
        )
    }

    private var visibleProviderIDs: [String] {
        store.presentationCards.map(\.id)
    }

    private var areAllProvidersExpanded: Bool {
        providerExpansion.areAllExpanded(providerIDs: visibleProviderIDs)
    }

    public var body: some View {
        Group {
            if isShowingSettings {
                settingsBackdrop
                    .frame(maxHeight: displayedHeight, alignment: .top)
                    .clipped()
                    .allowsHitTesting(false)
            } else {
                ScrollView(.vertical) {
                    panelContent
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: UsagePanelMetrics.width, height: displayedHeight)
        .background {
            BalancedPanelTint(tuning: tuning)
                .ignoresSafeArea()
        }
        .overlay {
            if outerContourOwner == .swiftUI {
                RoundedRectangle(
                    cornerRadius: AppGlass.panelCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    AppBorders.panelStroke(
                        colorScheme: colorScheme,
                        increaseContrast: usesIncreasedContrast
                    ),
                    lineWidth: AppBorders.panelLineWidth(
                        increaseContrast: usesIncreasedContrast
                    )
                )
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if isShowingSettings {
                    UsageSettingsCard(
                        showUsageSummary: $storedShowUsageSummary,
                        showRecentTasks: $storedShowRecentTasks,
                        showAPICost: $storedShowAPICost,
                        language: Binding(
                            get: { store.language },
                            set: { store.setLanguage($0) }
                        ),
                        claudeSettings: claudeSettings,
                        workBuddySettings: workBuddySettings,
                        workBuddyLogin: workBuddyLogin,
                        workBuddyAccountWebSync: workBuddyAccountWebSync,
                        providerLoginOptions: store.providerLoginOptions,
                        agentSettings: store.agentSettings,
                        searchForAgents: {
                            Task { await store.searchForAgents() }
                        },
                        destination: settingsDestination,
                        tuning: tuning,
                        maximumHeight:
                            UsagePanelMetrics.height
                                - UsageSettingsSizing.panelTopOffset
                                - UsageSettingsSizing.panelBottomInset,
                        onResolvedHeightChange: {
                            measuredSettingsCardHeight = $0
                        },
                        checkAgain: {
                            Task { await store.checkLocalSessionAgain() }
                        },
                        syncWorkBuddyAccount: {
                            Task { await store.syncWorkBuddyAccountNow() }
                        },
                        disconnectWorkBuddyAccount: {
                            Task { await store.disconnectWorkBuddyAccount() }
                        },
                        close: {
                            isShowingSettings = false
                            settingsDestination = nil
                        }
                    )
                    .padding(.top, UsageSettingsSizing.panelTopOffset)
                    .padding(.trailing, 16)
                    .transition(
                        usesReduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .zIndex(10)
                }
            }
        }
        .animation(
            usesReduceMotion ? nil : .easeInOut(duration: 0.18),
            value: isShowingSettings
        )
        .animation(
            usesReduceMotion ? nil : .easeInOut(duration: 0.18),
            value: displayedHeight
        )
        .onAppear {
            applyNavigation(navigation.providerSelection)
            onHeightChange?(displayedHeight)
        }
        .onChange(of: navigation.providerSelection) { _, selection in
            applyNavigation(selection)
        }
        .onChange(of: visibleProviderIDs) { _, providerIDs in
            providerExpansion.retain(providerIDs: Set(providerIDs))
        }
        .onChange(of: displayedHeight) { _, newHeight in
            onHeightChange?(newHeight)
        }
        .onChange(of: isShowingSettings) { _, isShowing in
            if !isShowing {
                measuredSettingsCardHeight = nil
            }
        }
        .environment(\.usagePanelAppearanceOverride, appearanceOverride)
    }

    private var settingsBackdrop: some View {
        VStack(spacing: 0) {
            MonitorHeaderView(
                store: store,
                tuning: tuning,
                isShowingSettings: $isShowingSettings,
                settingsDestination: $settingsDestination
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, UsagePanelMetrics.outerHorizontalInset)
        .padding(.top, UsagePanelMetrics.outerTopInset)
        .padding(.bottom, UsagePanelMetrics.outerBottomInset)
    }

    private var panelContent: some View {
        VStack(spacing: UsagePanelMetrics.cardSpacing) {
            MonitorHeaderView(
                store: store,
                tuning: tuning,
                isShowingSettings: $isShowingSettings,
                settingsDestination: $settingsDestination
            )

            if !store.presentationCards.isEmpty {
                ProviderExpansionToolbar(
                    language: store.language,
                    allExpanded: areAllProvidersExpanded,
                    setAllExpanded: setAllProvidersExpanded
                )
                ForEach(store.presentationCards) { card in
                    LocalLiveProviderCard(
                        card: card,
                        language: store.language,
                        tuning: tuning,
                        codexSnapshot: card.id
                            == CodexUsageConnector.connectorID.rawValue
                            ? store.snapshot
                            : nil,
                        codexRecovery: card.id
                            == CodexUsageConnector.connectorID.rawValue
                            ? retainedSnapshotRecovery
                            : nil,
                        showUsageSummary: showUsageSummary,
                        showRecentTasks: showRecentTasks,
                        showAPICost: showAPICost,
                        openAgentSettings: {
                            openAgentSettings(card.id)
                        },
                        performCodexAction: perform,
                        isExpanded: expansionBinding(for: card.id)
                    )
                }
            } else {
                LocalLiveEmptyStateView(
                    language: store.language,
                    isRefreshing: store.isRefreshing,
                    refresh: refreshFromEmptyState
                )
            }
        }
        .padding(.horizontal, UsagePanelMetrics.outerHorizontalInset)
        .padding(.top, UsagePanelMetrics.outerTopInset)
        .padding(.bottom, UsagePanelMetrics.outerBottomInset)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: UsagePanelContentHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(UsagePanelContentHeightPreferenceKey.self) { height in
            guard renderedHeightOverride == nil, height > 0 else { return }
            if measuredContentHeight.map({ abs($0 - height) > 0.5 }) ?? true {
                measuredContentHeight = height
            }
        }
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { providerExpansion.isExpanded(id) },
            set: { expanded in
                providerExpansion.setExpanded(expanded, providerID: id)
            }
        )
    }

    private func applyNavigation(
        _ selection: UsagePanelNavigationCoordinator.ProviderSelection?
    ) {
        guard let selection else { return }
        providerExpansion.setExpanded(true, providerID: selection.providerID)
    }

    private func setAllProvidersExpanded(_ expanded: Bool) {
        if expanded {
            providerExpansion.expandAll(providerIDs: visibleProviderIDs)
        } else {
            providerExpansion.collapseAll()
        }
    }

    private func openAgentSettings(_ providerID: String) {
        let canonicalProviderID = AgentConnectorID(rawValue: providerID)
            .map(AgentPreferenceRecord.canonicalProviderID)?
            .rawValue
            ?? providerID
        settingsDestination = .agent(canonicalProviderID)
        isShowingSettings = true
    }

    @MainActor
    private func refreshFromEmptyState() async {
        if !store.monitorConsentGranted {
            guard localAccessConfirmationAction?.request() == true else {
                return
            }
            store.grantMonitorConsent()
        }
        await store.refresh()
    }

    private var usesReduceMotion: Bool {
        appearanceOverride?.reduceMotion ?? reduceMotion
    }

    private var usesIncreasedContrast: Bool {
        appearanceOverride?.increaseContrast ?? (colorSchemeContrast == .increased)
    }

    @MainActor
    private func perform(_ action: CodexConnectionAction) async {
        switch action {
        case .connect:
            store.handleLocalAccessDecision(localAccessConfirmationAction?.request() == true)
        case .notNow:
            await store.declineMonitorConsent()
        case .checkLocalSession:
            await store.checkLocalSessionAgain()
        case .cancelLocalSessionReconciliation:
            await store.cancelLocalSessionReconciliation()
        case .retry:
            await store.refresh()
        case .reconnect:
            store.requestReconnect()
        case .disconnect:
            await store.disconnectAndForgetConsent()
        case .openCodex, .updateCodex, .dismiss:
            break
        }
    }
}

private struct LocalLiveEmptyStateView: View {
    let language: AppLanguage
    let isRefreshing: Bool
    let refresh: @MainActor () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(UsageDesign.blue)
                .accessibilityHidden(true)
            Text(language.noLocalLiveAgentsTitle)
                .font(AppTypography.font(13, weight: .semibold, language: language))
                .multilineTextAlignment(.center)
            Text(language.noLocalLiveAgentsGuidance)
                .font(AppTypography.font(10.5, language: language))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(language.refreshUsage) {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshing)
            .accessibilityHint(language.noLocalLiveAgentsGuidance)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background {
            GlassCardBackground(tuning: .final, cornerRadius: 22)
        }
    }
}

private struct LocalLiveProviderCard: View {
    let card: SharedUsageCardPresentation
    let language: AppLanguage
    let tuning: GlassTuning
    let codexSnapshot: UsageSnapshot?
    let codexRecovery: RetainedSnapshotRecoveryPresentation?
    let showUsageSummary: Bool
    let showRecentTasks: Bool
    let showAPICost: Bool
    let openAgentSettings: () -> Void
    let performCodexAction: @MainActor (CodexConnectionAction) async -> Void
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.providerName)
                        .font(AppTypography.font(13, weight: .semibold, language: language))
                        .lineLimit(1)
                    Text(providerSubtitle)
                        .font(AppTypography.font(9.5, language: language))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    if let selectedWindowLabel {
                        Text(selectedWindowLabel)
                            .font(AppTypography.font(9, weight: .medium, language: language))
                            .foregroundStyle(.secondary)
                    }
                    Text(primaryValue)
                        .font(AppTypography.font(.regularValue, language: language))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(minWidth: 46, alignment: .trailing)

                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.secondary.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help(detailsLabel)
                .accessibilityLabel(detailsLabel)

                Button(action: openAgentSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.secondary.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help(agentSettingsLabel)
                .accessibilityLabel(agentSettingsLabel)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: UsagePanelMetrics.collapsedProviderCardHeight)

            if isExpanded {
                Divider()
                    .opacity(0.32)
                    .padding(.horizontal, 14)
                expandedDetails
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            GlassCardBackground(tuning: tuning)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.accessibilityLabel)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    private var isAccountWebCredits: Bool {
        card.availability?.sourceState == .authenticatedAccountWeb
    }

    private var isClaudeCode: Bool {
        card.id == ClaudeCodeUsageConnector.connectorID.rawValue
    }

    private var selectedWindowLabel: String? {
        card.selectedWindowCompactLabel
    }

    private var providerSubtitle: String {
        if isClaudeCode {
            switch card.freshness {
            case .cached:
                return "\(language.claudeCached) · \(language.claudeUpdated(card.capturedAt))"
            case .stale:
                return "\(language.claudeStale) · \(language.claudeUpdated(card.capturedAt))"
            case .fresh, .unavailable:
                break
            }
        }
        if isAccountWebCredits {
            return "\(language.workBuddyAccountWebSource) · \(connectionLabel)"
        }
        if let plan = card.planLabel, !plan.isEmpty {
            return "\(plan) · \(connectionLabel)"
        }
        return connectionLabel
    }

    private var connectionLabel: String {
        switch (language, card.connectionStatus) {
        case (.english, .connected): "Connected"
        case (.english, .transitional): "Connecting"
        case (.english, .authenticationRequired): "Sign-in required"
        case (.english, .stale): "Reconnecting"
        case (.english, .disconnected): "Disconnected"
        case (.english, .unavailable): "Unavailable"
        case (.english, .failed): "Connection failed"
        case (.simplifiedChinese, .connected): "已连接"
        case (.simplifiedChinese, .transitional): "正在连接"
        case (.simplifiedChinese, .authenticationRequired): "需要登录"
        case (.simplifiedChinese, .stale): "正在重新连接"
        case (.simplifiedChinese, .disconnected): "已断开"
        case (.simplifiedChinese, .unavailable): "不可用"
        case (.simplifiedChinese, .failed): "连接失败"
        }
    }

    private var connectionColor: Color {
        switch card.connectionStatus {
        case .connected: UsageDesign.green
        case .transitional, .stale: .orange
        case .authenticationRequired, .disconnected, .unavailable: .secondary
        case .failed: .red
        }
    }

    private var primaryValue: String {
        if let availability = card.availability,
           availability.displayUnit == .credits {
            return availability.compactText
        }
        return card.remaining.displayText
    }

    private func exactValue(_ value: Decimal) -> String {
        isAccountWebCredits
            ? CreditFormatter.exactTwoDecimal(value, language: language)
            : CreditFormatter.exact(value, language: language)
    }

    @ViewBuilder
    private var expandedDetails: some View {
        if let codexSnapshot {
            VStack(spacing: UsagePanelMetrics.cardSpacing) {
                if let codexRecovery {
                    HStack(spacing: 6) {
                        Text(codexRecovery.statusText)
                            .font(AppTypography.font(10.5, language: language))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if let action = codexRecovery.primaryAction {
                            RecoveryActionButton(
                                action: action,
                                perform: performCodexAction
                            )
                        }
                        if let action = codexRecovery.secondaryAction {
                            RecoveryActionButton(
                                action: action,
                                perform: performCodexAction
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 11)
                }
                if showUsageSummary {
                    UsageSummaryCard(
                        snapshot: codexSnapshot,
                        selectedWindowID: card.selectedWindowID,
                        language: language,
                        tuning: tuning,
                        showsBackground: false
                    )
                }
                CodexSourceHealthDetails(
                    snapshot: codexSnapshot,
                    language: language
                )
                if showRecentTasks {
                    RecentTasksCard(
                        tasks: codexSnapshot.recentTasks,
                        language: language,
                        tuning: tuning,
                        showsBackground: false
                    )
                }
                if showAPICost {
                    APICostEstimateCard(
                        estimate: codexSnapshot.apiCostEstimate,
                        language: language,
                        tuning: tuning,
                        showsBackground: false
                    )
                }
                FooterView(snapshot: codexSnapshot, language: language)
            }
            .padding(10)
        } else if let balance = card.availability?.value.creditBalance {
            creditDetails(balance)
        } else {
            percentageDetails
        }
    }

    private func creditDetails(_ balance: CreditBalance) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let snapshot = card.accountCreditBreakdown {
                detailRow(
                    language.workBuddySubscriptionRemaining,
                    value: CreditFormatter.exactTwoDecimal(
                        snapshot.subscriptionRemaining,
                        language: language
                    )
                )
                detailRow(
                    language.workBuddyAddOnRemaining,
                    value: CreditFormatter.exactTwoDecimal(
                        snapshot.addOnRemaining,
                        language: language
                    )
                )
                detailRow(
                    language.workBuddyBenefitGiftRemaining,
                    value: CreditFormatter.exactTwoDecimal(
                        snapshot.benefitGiftRemaining,
                        language: language
                    )
                )
            }
            detailRow(
                language.workBuddyAvailableCredits,
                value: exactValue(balance.remaining)
            )
            if let used = balance.used {
                detailRow(
                    language.workBuddyCompanionName(.used),
                    value: CreditFormatter.exact(used, language: language)
                )
            }
            if let total = balance.total {
                detailRow(
                    language.workBuddyCompanionName(.total),
                    value: CreditFormatter.exact(total, language: language)
                )
            }
            detailRow(
                language.workBuddySource,
                value: isAccountWebCredits
                    ? language.workBuddyAccountWebSource
                    : "Official structured source"
            )
            detailRow(
                language.workBuddyScope,
                value: language.workBuddySharedWithCodeBuddy
            )
            detailRow(
                language.workBuddyLastConfirmed,
                value: language.workBuddyConfirmedAt(balance.observedAt)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var percentageDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isClaudeCode {
                detailRow(
                    language == .english ? "Source" : "来源",
                    value: language.claudeOfficialLocalStatusLine
                )
                detailRow(
                    language == .english ? "State" : "状态",
                    value: claudeFreshnessLabel
                )
                detailRow(
                    language == .english ? "Observation" : "观测时间",
                    value: language.claudeUpdated(card.capturedAt)
                )
            }
            ForEach(card.windows) { window in
                detailRow(
                    window.accessibilityLabel,
                    value: window.remaining.displayText
                )
            }
            if card.windows.isEmpty {
                detailRow(connectionLabel, value: card.remaining.displayText)
            }
            if isClaudeCode {
                Text(language.claudeUpdatesAutomatically)
                    .font(AppTypography.font(9.5, language: language))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var claudeFreshnessLabel: String {
        switch card.freshness {
        case .fresh: language.claudeFresh
        case .cached: language.claudeCached
        case .stale: language.claudeStale
        case .unavailable:
            language == .english ? "Unavailable" : "不可用"
        }
    }

    private var detailsLabel: String {
        language == .english
            ? (isExpanded ? "Hide \(card.providerName) Details" : "Show \(card.providerName) Details")
            : (isExpanded ? "收起 \(card.providerName) 详情" : "显示 \(card.providerName) 详情")
    }

    private var agentSettingsLabel: String {
        language == .english
            ? "\(card.providerName) Agent Settings"
            : "\(card.providerName) Agent 设置"
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(AppTypography.font(10, weight: .medium, language: language))
    }
}

private struct UsagePanelContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct APICostEstimateCard: View {
    let estimate: APICostEstimateSnapshot?
    let language: AppLanguage
    let tuning: GlassTuning
    var showsBackground = true

    private var displayableEstimate: APICostEstimateSnapshot? {
        APICostVisualPolicy.displayableEstimate(estimate)
    }

    private var sevenDayValue: String {
        guard let estimate = displayableEstimate else { return "—" }
        return Self.currency(estimate.sevenDayUSD)
    }

    private var lifetimeValue: String {
        guard let value = displayableEstimate?.lifetimeUSD else { return "—" }
        return Self.currency(value)
    }

    private var modelText: String {
        guard let names = displayableEstimate?.modelNames, !names.isEmpty else {
            return language.noPricedModel
        }
        return names.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 15, weight: .semibold))
                Text(language.apiCostTitle)
                    .font(AppTypography.font(15, weight: .bold, language: language))
                Spacer()
                Text(language.standardAPIRates)
                    .font(AppTypography.font(10.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(sevenDayValue)
                    .font(AppTypography.numericFont(25, weight: .bold))
                    .foregroundStyle(UsageDesign.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(language.metricSevenDays)
                    .font(AppTypography.font(11.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(lifetimeValue)
                        .font(AppTypography.numericFont(15, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(language.lifetimeCost)
                        .font(AppTypography.font(10.5, language: language))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .opacity(0.32)

            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .medium))
                Text(modelText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                Text(
                    language.pricedCoverage(
                        displayableEstimate?.coveragePercent ?? 0
                    )
                )
                    .font(AppTypography.numericFont(10.5, weight: .medium))
                    .lineLimit(1)
            }
            .font(AppTypography.font(.secondary, language: language))
            .foregroundStyle(.secondary)

            Text(language.costDisclaimer)
                .font(AppTypography.font(9.5, language: language))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if showsBackground {
                GlassCardBackground(tuning: tuning)
            }
        }
    }

    private static func currency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.2fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "$%.2fK", value / 1_000)
        }
        return String(format: "$%.2f", value)
    }
}

enum APICostVisualPolicy {
    static func displayableEstimate(
        _ estimate: APICostEstimateSnapshot?
    ) -> APICostEstimateSnapshot? {
        guard let estimate,
              estimate.coveragePercent > 0,
              estimate.coveragePercent <= 100,
              estimate.sevenDayUSD.isFinite,
              estimate.sevenDayUSD >= 0,
              estimate.lifetimeUSD.isFinite,
              estimate.lifetimeUSD >= 0
        else {
            return nil
        }
        return estimate
    }
}

private struct ProviderExpansionToolbar: View {
    let language: AppLanguage
    let allExpanded: Bool
    let setAllExpanded: (Bool) -> Void

    var body: some View {
        HStack {
            Text(language == .english ? "Agents" : "Agent")
                .font(AppTypography.font(11, weight: .semibold, language: language))
                .foregroundStyle(.secondary)
            Spacer()
            Button(
                language == .english
                    ? (allExpanded ? "Hide All" : "Show All")
                    : (allExpanded ? "全部收起" : "全部显示")
            ) {
                setAllExpanded(!allExpanded)
            }
            .buttonStyle(.plain)
            .font(AppTypography.font(10.5, weight: .semibold, language: language))
            .foregroundStyle(UsageDesign.blue)
            .accessibilityIdentifier("usage.providers.toggleAll")
        }
        .padding(.horizontal, 4)
        .frame(height: UsagePanelMetrics.providerToolbarHeight)
    }
}

private struct MonitorHeaderView: View {
    @ObservedObject var store: UsageStore
    let tuning: GlassTuning
    @Binding var isShowingSettings: Bool
    @Binding var settingsDestination: UsageSettingsDestination?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(UsageDesign.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(UsageDesign.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("UMA")
                    .font(AppTypography.font(20, weight: .bold, language: store.language))
                    .lineLimit(1)
                    .layoutPriority(UsagePanelHeaderLayout.titleLayoutPriority)

                HStack(spacing: 6) {
                    Circle()
                        .fill(store.presentationCards.isEmpty ? Color.secondary : UsageDesign.green)
                        .frame(width: 8, height: 8)
                    Text(monitorStatus)
                        .font(AppTypography.font(13, language: store.language))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 34, height: 34)
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(store.language.refreshUsage)
                .accessibilityLabel(store.language.refreshUsage)
                .accessibilityHint(store.lastError ?? store.language.refreshFromAccountHint)

                Button {
                    settingsDestination = nil
                    isShowingSettings.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(isShowingSettings ? 0.25 : 0.14))
                            .frame(width: 30, height: 30)
                        Image(systemName: isShowingSettings ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isShowingSettings ? UsageDesign.blue : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(store.language.showSettings)
                .accessibilityLabel(store.language.showSettings)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: UsagePanelMetrics.headerHeight)
        .background(GlassCardBackground(tuning: tuning))
    }

    private var monitorStatus: String {
        let count = store.presentationCards.count
        return switch (store.language, count) {
        case (.english, 0): "No active Agents"
        case (.english, 1): "1 active Agent"
        case (.english, _): "\(count) active Agents"
        case (.simplifiedChinese, 0): "没有活跃 Agent"
        case (.simplifiedChinese, _): "\(count) 个活跃 Agent"
        }
    }
}

private struct RecoveryActionButton: View {
    let action: CodexPresentedAction
    let perform: @MainActor (CodexConnectionAction) async -> Void

    var body: some View {
        Button(action.title) {
            Task { await perform(action.action) }
        }
        .buttonStyle(.plain)
        .font(AppTypography.font(.action))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 7)
        .frame(maxWidth: 82, minHeight: 30)
        .background(Capsule().fill(Color.orange.opacity(0.16)))
        .accessibilityLabel(action.title)
    }
}

private struct UsageSummaryCard: View {
    let snapshot: UsageSnapshot
    let selectedWindowID: String?
    let language: AppLanguage
    let tuning: GlassTuning
    var showsBackground = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(snapshot.periods.enumerated()), id: \.element.id) { index, period in
                    QuotaRow(
                        period: period,
                        language: language,
                        isPrimary: UsageQuotaVisualPolicy.isPrimary(
                            period: period,
                            selectedWindowID: selectedWindowID
                        )
                    )
                    if index < snapshot.periods.count - 1 {
                        Divider()
                            .opacity(0.32)
                            .padding(.horizontal, 14)
                    }
                }
            }

            Divider()
                .opacity(0.38)

            HStack(spacing: 0) {
                ForEach(snapshot.metrics) { metric in
                    VStack(spacing: 4) {
                        Text(metric.value)
                            .font(AppTypography.numericFont(19, weight: .bold))
                        Text(metric.label)
                            .font(AppTypography.font(12, weight: .medium, language: language))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 79)
        }
        .background {
            if showsBackground {
                GlassCardBackground(tuning: tuning)
            }
        }
    }
}

enum UsageQuotaVisualPolicy {
    static func isPrimary(
        period: UsagePeriod,
        selectedWindowID: String?
    ) -> Bool {
        guard period.id == selectedWindowID else { return false }
        return !(period.isFiveHour == true && period.isUnlimited)
    }
}

private struct QuotaRow: View {
    let period: UsagePeriod
    let language: AppLanguage
    let isPrimary: Bool

    var body: some View {
        VStack(spacing: isPrimary ? 10 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(period.title)
                    .font(
                        AppTypography.font(
                            isPrimary
                                ? UsageQuotaVisualMetrics.primaryTitleSize
                                : UsageQuotaVisualMetrics.secondaryTitleSize,
                            weight: isPrimary ? .bold : .regular,
                            language: language
                        )
                    )
                Spacer()
                Text(period.isUnlimited ? "♾️" : "\(period.remainingPercent)%")
                    .font(
                        AppTypography.numericFont(
                            isPrimary
                                ? UsageQuotaVisualMetrics.primaryValueSize
                                : UsageQuotaVisualMetrics.secondaryValueSize,
                            weight: isPrimary ? .bold : .medium
                        )
                    )
                    .foregroundStyle(
                        UsageDesign.blue.opacity(isPrimary ? 1 : 0.48)
                    )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(isPrimary ? 0.14 : 0.08))
                    Capsule()
                        .fill(UsageDesign.blue.opacity(isPrimary ? 1 : 0.34))
                        .frame(width: proxy.size.width * CGFloat(period.isUnlimited ? 100 : period.remainingPercent) / 100)
                }
            }
            .frame(
                height: isPrimary
                    ? UsageQuotaVisualMetrics.primaryBarHeight
                    : UsageQuotaVisualMetrics.secondaryBarHeight
            )

            HStack {
                Text(language.remaining)
                Spacer()
                Text(period.resetText)
            }
            .font(
                AppTypography.font(
                    isPrimary ? 11.5 : 8.5,
                    language: language
                )
            )
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(
            .vertical,
            isPrimary
                ? UsageQuotaVisualMetrics.primaryVerticalInset
                : UsageQuotaVisualMetrics.secondaryVerticalInset
        )
        .accessibilityElement(children: .combine)
    }
}

private struct CodexSourceHealthDetails: View {
    let snapshot: UsageSnapshot
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let provider = snapshot.providerSource {
                sourceRow(provider)
            }
            if let local = snapshot.localSource {
                sourceRow(local)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func sourceRow(_ source: UsageSourceStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(source.label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(
                "\(language.sourceFreshness(source.freshness)) · "
                    + language.sourceScope(source.scope)
            )
            .multilineTextAlignment(.trailing)
        }
        .font(AppTypography.font(9.5, weight: .medium, language: language))
        .accessibilityElement(children: .combine)
    }
}

private struct RecentTasksCard: View {
    let tasks: [RecentTask]
    let language: AppLanguage
    let tuning: GlassTuning
    var showsBackground = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                Text(language.recentTasks)
                    .font(AppTypography.font(15, weight: .bold, language: language))
                Spacer()
                Text(language.threadTotalTokens)
                    .font(AppTypography.font(11, language: language))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 9)

            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                RecentTaskRow(task: task, language: language)
                if index < tasks.count - 1 {
                    Divider()
                        .opacity(0.30)
                        .padding(.horizontal, 14)
                }
            }
        }
        .background {
            if showsBackground {
                GlassCardBackground(tuning: tuning)
            }
        }
    }
}

private struct RecentTaskRow: View {
    let task: RecentTask
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(AppTypography.font(14, weight: .bold, language: language))
                        .lineLimit(1)
                    Text(task.time)
                        .font(AppTypography.font(10.5, language: language))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(task.tokenText)
                    .font(AppTypography.numericFont(14.5, weight: .bold))
                    .foregroundStyle(UsageDesign.blue)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.10))
                    if task.progress > 0 {
                        Rectangle()
                            .fill(UsageDesign.blue.opacity(0.72))
                            .frame(width: proxy.size.width * task.progress)
                    }
                }
            }
            .frame(height: 2.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct FooterView: View {
    let snapshot: UsageSnapshot
    let language: AppLanguage

    private var updatedTime: String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: snapshot.updatedAt)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    var body: some View {
        HStack {
            Label(
                snapshot.availableResets.map(language.availableResets) ?? language.resetAvailabilityUnavailable,
                systemImage: "clock.arrow.circlepath"
            )
            Spacer()
            Text(language.updatedAt(updatedTime))
        }
        .font(AppTypography.font(11.5, weight: .medium, language: language))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .frame(height: 24)
        .contextMenu {
            Button(language.quitApplication) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
