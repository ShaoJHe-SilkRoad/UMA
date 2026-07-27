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

    let tuning: GlassTuning
    private let preferencesEnabled: Bool
    private let onHeightChange: ((CGFloat) -> Void)?
    private let localAccessConfirmationAction: CodexLocalAccessConfirmationAction?
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
        expandedProviderIDs: Set<String> = [],
        navigation: UsagePanelNavigationCoordinator? = nil,
        onHeightChange: ((CGFloat) -> Void)? = nil,
        localAccessConfirmationAction: CodexLocalAccessConfirmationAction? = nil,
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
        self.workBuddySettings = workBuddySettings
        self.workBuddyLogin = workBuddyLogin
        self.workBuddyAccountWebSync = workBuddyAccountWebSync
        self.appearanceOverride = appearanceOverride
        self.renderedHeightOverride = renderedHeightOverride
        self.cardVisibilityOverride = cardVisibilityOverride
        _isShowingSettings = State(initialValue: settingsInitiallyPresented)
        _settingsDestination = State(
            initialValue: settingsInitiallyPresented
                && (workBuddyLogin != nil || workBuddyAccountWebSync != nil)
                ? .workBuddy
                : nil
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
        isShowingSettings
            ? max(preferredHeight, UsagePanelMetrics.settingsMinimumHeight)
            : preferredHeight
    }

    private var additionalProviderCards: [SharedUsageCardPresentation] {
        store.presentationCards.filter {
            $0.id != CodexUsageConnector.connectorID.rawValue
        }
    }

    public var body: some View {
        Group {
            if isShowingSettings {
                panelContent
                    .frame(maxHeight: displayedHeight, alignment: .top)
                    .clipped()
                    .opacity(0.14)
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
                .stroke(
                    AppBorders.panelStroke(
                        colorScheme: colorScheme,
                        increaseContrast: usesIncreasedContrast
                    ),
                    lineWidth: AppBorders.panelLineWidth(
                        increaseContrast: usesIncreasedContrast
                    )
                )
                .padding(0.4)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if !presentation.showsRealData,
                   preferencesEnabled,
                   !isShowingSettings {
                    Button {
                        settingsDestination = nil
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(store.language.showSettings)
                    .accessibilityLabel(store.language.showSettings)
                    .padding(.top, 14)
                    .padding(.trailing, 16)
                }

                if isShowingSettings {
                    UsageSettingsCard(
                        showUsageSummary: $storedShowUsageSummary,
                        showRecentTasks: $storedShowRecentTasks,
                        showAPICost: $storedShowAPICost,
                        language: Binding(
                            get: { store.language },
                            set: { store.setLanguage($0) }
                        ),
                        workBuddySettings: workBuddySettings,
                        workBuddyLogin: workBuddyLogin,
                        workBuddyAccountWebSync: workBuddyAccountWebSync,
                        providerLoginOptions: store.providerLoginOptions,
                        destination: settingsDestination,
                        tuning: tuning,
                        maximumHeight: max(240, displayedHeight - 124),
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
                    .padding(.top, 96)
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
            value: preferredHeight
        )
        .onAppear {
            applyNavigation(navigation.providerSelection)
            onHeightChange?(displayedHeight)
        }
        .onChange(of: navigation.providerSelection) { _, selection in
            applyNavigation(selection)
        }
        .onChange(of: displayedHeight) { _, newHeight in
            onHeightChange?(newHeight)
        }
        .environment(\.usagePanelAppearanceOverride, appearanceOverride)
    }

    private var panelContent: some View {
        VStack(spacing: UsagePanelMetrics.cardSpacing) {
            if presentation.showsRealData {
                HeaderView(
                    store: store,
                    recovery: retainedSnapshotRecovery,
                    tuning: tuning,
                    isShowingSettings: $isShowingSettings,
                    perform: perform
                )
                if showUsageSummary {
                    UsageSummaryCard(
                        snapshot: store.snapshot,
                        language: store.language,
                        tuning: tuning
                    )
                }
                ForEach(additionalProviderCards) { card in
                    LocalLiveProviderCard(
                        card: card,
                        language: store.language,
                        tuning: tuning,
                        isExpanded: expansionBinding(for: card.id)
                    )
                }
                if showRecentTasks {
                    RecentTasksCard(
                        tasks: store.snapshot.recentTasks,
                        language: store.language,
                        tuning: tuning
                    )
                }
                if showAPICost {
                    APICostEstimateCard(
                        estimate: store.snapshot.apiCostEstimate,
                        language: store.language,
                        tuning: tuning
                    )
                }
                FooterView(snapshot: store.snapshot, language: store.language)
            } else if !store.presentationCards.isEmpty {
                ForEach(store.presentationCards) { card in
                    LocalLiveProviderCard(
                        card: card,
                        language: store.language,
                        tuning: tuning,
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

    private func openWorkBuddySettings() {
        settingsDestination = .workBuddy
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
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if card.availability?.displayUnit == .credits {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.providerName)
                            .font(AppTypography.font(13, weight: .semibold, language: language))
                        if isAccountWebCredits {
                            Text(language.workBuddyAccountWebSource)
                                .font(AppTypography.font(9, language: language))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(primaryValue)
                        .font(AppTypography.font(.regularValue, language: language))
                        .monospacedDigit()
                    if card.availability?.displayUnit == .credits {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let balance = card.availability?.value.creditBalance {
                Divider()
                    .opacity(0.32)
                    .padding(.horizontal, 14)
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
                            : (card.availability?.sourceState == .officialStructured
                                ? "Official structured source"
                                : "Provider source")
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            GlassCardBackground(tuning: tuning)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    private var isAccountWebCredits: Bool {
        card.availability?.sourceState == .authenticatedAccountWeb
    }

    private var primaryValue: String {
        guard let balance = card.availability?.value.creditBalance else {
            return card.remaining.displayText
        }
        let exact = exactValue(balance.remaining)
        return language.workBuddyCreditsAvailable(exact)
    }

    private func exactValue(_ value: Decimal) -> String {
        isAccountWebCredits
            ? CreditFormatter.exactTwoDecimal(value, language: language)
            : CreditFormatter.exact(value, language: language)
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

    private var sevenDayValue: String {
        guard let estimate else { return "—" }
        return Self.currency(estimate.sevenDayUSD)
    }

    private var lifetimeValue: String {
        guard let value = estimate?.lifetimeUSD else { return "—" }
        return Self.currency(value)
    }

    private var modelText: String {
        guard let names = estimate?.modelNames, !names.isEmpty else { return language.noPricedModel }
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
                    .font(AppTypography.font(25, weight: .bold, language: language))
                    .foregroundStyle(UsageDesign.blue)
                    .monospacedDigit()
                Text(language.metricSevenDays)
                    .font(AppTypography.font(11.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(lifetimeValue)
                        .font(AppTypography.font(15, weight: .bold, language: language))
                        .monospacedDigit()
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
                Spacer(minLength: 8)
                Text(language.pricedCoverage(estimate?.coveragePercent ?? 0))
                    .monospacedDigit()
            }
            .font(AppTypography.font(10.5, weight: .medium, language: language))
            .foregroundStyle(.secondary)

            Text(language.costDisclaimer)
                .font(AppTypography.font(9.5, language: language))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(GlassCardBackground(tuning: tuning))
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

private struct HeaderView: View {
    @ObservedObject var store: UsageStore
    let recovery: RetainedSnapshotRecoveryPresentation?
    let tuning: GlassTuning
    @Binding var isShowingSettings: Bool
    let perform: @MainActor (CodexConnectionAction) async -> Void

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
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(store.language.appTitle)
                        .font(AppTypography.font(20, weight: .bold, language: store.language))
                        .lineLimit(1)
                        .minimumScaleFactor(UsagePanelHeaderLayout.titleMinimumScaleFactor)
                        .layoutPriority(UsagePanelHeaderLayout.titleLayoutPriority)
                    if recovery == nil {
                        Text(store.snapshot.planLabel)
                            .font(AppTypography.font(11, weight: .bold, language: store.language))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(recovery == nil && store.lastError == nil ? UsageDesign.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(recovery?.statusText ?? store.statusText)
                        .font(AppTypography.font(13, language: store.language))
                        .foregroundStyle(.secondary)
                        .lineLimit(recovery == nil ? 1 : 2)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 8)

            if let recovery {
                HStack(spacing: 4) {
                    if let primaryAction = recovery.primaryAction {
                        RecoveryActionButton(action: primaryAction, perform: perform)
                    }
                    if let secondaryAction = recovery.secondaryAction {
                        RecoveryActionButton(action: secondaryAction, perform: perform)
                    }
                }
            } else {
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
        }
        .padding(.horizontal, 14)
        .frame(height: 70)
        .background(GlassCardBackground(tuning: tuning))
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
        .font(.system(size: 10.5, weight: .semibold))
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
    let language: AppLanguage
    let tuning: GlassTuning

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(snapshot.periods.enumerated()), id: \.element.id) { index, period in
                    QuotaRow(period: period, language: language)
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
                            .font(AppTypography.font(19, weight: .bold, language: language))
                            .monospacedDigit()
                        Text(metric.label)
                            .font(AppTypography.font(12, weight: .medium, language: language))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 79)
        }
        .background(GlassCardBackground(tuning: tuning))
    }
}

private struct QuotaRow: View {
    let period: UsagePeriod
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(period.title)
                    .font(AppTypography.font(16, weight: .bold, language: language))
                Spacer()
                Text(period.isUnlimited ? "♾️" : "\(period.remainingPercent)%")
                    .font(AppTypography.font(20, weight: .bold, language: language))
                    .foregroundStyle(UsageDesign.blue)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(UsageDesign.blue)
                        .frame(width: proxy.size.width * CGFloat(period.isUnlimited ? 100 : period.remainingPercent) / 100)
                }
            }
            .frame(height: 10)

            HStack {
                Text(language.remaining)
                Spacer()
                Text(period.resetText)
            }
            .font(AppTypography.font(11.5, language: language))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

private struct RecentTasksCard: View {
    let tasks: [RecentTask]
    let language: AppLanguage
    let tuning: GlassTuning

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
        .background(GlassCardBackground(tuning: tuning))
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
                    .font(AppTypography.font(14.5, weight: .bold, language: language))
                    .foregroundStyle(UsageDesign.blue)
                    .monospacedDigit()
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
