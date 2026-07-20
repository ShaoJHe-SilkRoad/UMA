import AppKit
import SwiftUI

public struct UsagePanelView: View {
    @ObservedObject var store: UsageStore
    @State private var isShowingSettings: Bool
    @State private var isShowingMoreInfo = false

    let tuning: GlassTuning
    private let preferencesEnabled: Bool
    private let appKitAccessibilityEnabled: Bool
    private let scrollingEnabled: Bool
    private let onHeightChange: ((CGFloat) -> Void)?
    private let localAccessConfirmationAction: CodexLocalAccessConfirmationAction?

    public init(
        store: UsageStore,
        tuning: GlassTuning,
        preferencesEnabled: Bool = true,
        appKitAccessibilityEnabled: Bool = true,
        scrollingEnabled: Bool = true,
        settingsInitiallyPresented: Bool = false,
        moreInfoInitiallyPresented: Bool = false,
        onHeightChange: ((CGFloat) -> Void)? = nil,
        localAccessConfirmationAction: CodexLocalAccessConfirmationAction? = nil
    ) {
        self.store = store
        self.tuning = tuning
        self.preferencesEnabled = preferencesEnabled
        self.appKitAccessibilityEnabled = appKitAccessibilityEnabled
        self.scrollingEnabled = scrollingEnabled
        self.onHeightChange = onHeightChange
        self.localAccessConfirmationAction = localAccessConfirmationAction
        _isShowingSettings = State(initialValue: settingsInitiallyPresented)
        _isShowingMoreInfo = State(initialValue: moreInfoInitiallyPresented)
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
        UsagePanelMetrics.targetHeight(
            showsRealData: presentation.showsRealData,
            moreInfoExpanded: isShowingMoreInfo,
            settingsPresented: false
        )
    }

    private var displayedHeight: CGFloat {
        UsagePanelMetrics.presentedHeight(
            showsRealData: presentation.showsRealData,
            moreInfoExpanded: isShowingMoreInfo,
            recentTaskCount: store.snapshot.recentTasks.count,
            meteredPeriodCount: store.snapshot.periods.filter { !$0.isUnlimited }.count,
            settingsPresented: isShowingSettings
        )
    }

    public var body: some View {
        viewportContent
        .frame(width: UsagePanelMetrics.width)
        .onAppear {
            onHeightChange?(displayedHeight)
        }
        .onChange(of: displayedHeight) { _, newHeight in
            onHeightChange?(newHeight)
        }
    }

    @ViewBuilder
    private var viewportContent: some View {
        if scrollingEnabled {
            ScrollView(.vertical, showsIndicators: false) {
                panelContent
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            panelContent
        }
    }

    private var panelContent: some View {
        VStack(spacing: 10) {
            if presentation.showsRealData {
                HeaderView(
                    store: store,
                    recovery: retainedSnapshotRecovery,
                    tuning: tuning,
                    isShowingSettings: $isShowingSettings,
                    perform: perform
                )
                UsageSummaryCard(snapshot: store.snapshot, language: store.language, tuning: tuning)
                MoreInfoDisclosure(
                    language: store.language,
                    appKitAccessibilityEnabled: appKitAccessibilityEnabled,
                    isExpanded: $isShowingMoreInfo
                )
                if isShowingMoreInfo {
                    RecentTasksCard(tasks: store.snapshot.recentTasks, language: store.language, tuning: tuning)
                    APICostEstimateCard(
                        estimate: store.snapshot.apiCostEstimate,
                        language: store.language,
                        tuning: tuning
                    )
                }
            } else {
                CodexConnectionBridgeView(
                    presentation: presentation,
                    language: store.language,
                    perform: perform
                )
            }
        }
        .padding(UsagePanelMetrics.outerInset)
        .frame(
            width: UsagePanelMetrics.width,
            height: displayedHeight,
            alignment: .top
        )
        .overlay(alignment: .topTrailing) {
            if isShowingSettings {
                UsageSettingsCard(
                    language: Binding(
                        get: { store.language },
                        set: { store.setLanguage($0) }
                    ),
                    tuning: tuning,
                    close: { isShowingSettings = false }
                )
                .padding(.top, 96)
                .padding(.trailing, 16)
                .zIndex(10)
            }
        }
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

private struct MoreInfoDisclosure: View {
    let language: AppLanguage
    let appKitAccessibilityEnabled: Bool
    @Binding var isExpanded: Bool

    private var label: String {
        language.disclosureLabel(isExpanded: isExpanded)
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(UsageDesign.font(.disclosure, language: language))
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .contentShape(Rectangle())
        .accessibilityHidden(appKitAccessibilityEnabled)
        .overlay {
            if appKitAccessibilityEnabled {
                DisclosureAccessibilityButton(
                    label: label,
                    value: isExpanded
                        ? language.expandedAccessibilityValue
                        : language.collapsedAccessibilityValue,
                    isExpanded: $isExpanded
                )
            }
        }
    }
}

private struct DisclosureAccessibilityButton: NSViewRepresentable {
    let label: String
    let value: String
    @Binding var isExpanded: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isExpanded: $isExpanded)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.focusRingType = .none
        button.image = nil
        button.imagePosition = .noImage
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.toggle)
        configure(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.isExpanded = $isExpanded
        configure(button)
    }

    private func configure(_ button: NSButton) {
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(value)
        button.setAccessibilityIdentifier("usage.moreInfoDisclosure")
    }

    final class Coordinator: NSObject {
        var isExpanded: Binding<Bool>

        init(isExpanded: Binding<Bool>) {
            self.isExpanded = isExpanded
        }

        @objc
        func toggle() {
            isExpanded.wrappedValue.toggle()
        }
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
                    .font(UsageDesign.font(.sectionTitle, language: language))
                Spacer()
                Text(language.standardAPIRates)
                    .font(UsageDesign.font(.secondaryBody, language: language))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(sevenDayValue)
                    .font(UsageDesign.font(.priceMetric, language: language))
                    .foregroundStyle(UsageDesign.blue)
                    .monospacedDigit()
                Text(language.metricSevenDays)
                    .font(UsageDesign.font(.resetTime, language: language))
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(lifetimeValue)
                        .font(UsageDesign.font(.tokenMetric, language: language))
                        .monospacedDigit()
                    Text(language.lifetimeCost)
                        .font(UsageDesign.font(.secondaryBody, language: language))
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
            .font(UsageDesign.font(.secondaryBody, language: language))
            .foregroundStyle(.secondary)

            Text(language.costDisclaimer)
                .font(UsageDesign.font(.errorStatus, language: language))
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
                        .font(UsageDesign.font(.applicationTitle, language: store.language))
                        .lineLimit(1)
                        .minimumScaleFactor(UsagePanelHeaderLayout.titleMinimumScaleFactor)
                        .layoutPriority(UsagePanelHeaderLayout.titleLayoutPriority)
                    if recovery == nil {
                        Text(store.snapshot.planLabel)
                            .font(UsageDesign.font(.planLabel, language: store.language))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(syncIsCurrent ? UsageDesign.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(syncStatus)
                        .font(UsageDesign.font(.syncStatus, language: store.language))
                        .foregroundStyle(.secondary)
                        .lineLimit(recovery == nil ? 1 : 2)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 8)

            if let recovery {
                HStack(spacing: 4) {
                    if let primaryAction = recovery.primaryAction {
                        RecoveryActionButton(
                            action: primaryAction,
                            language: store.language,
                            perform: perform
                        )
                    }
                    if let secondaryAction = recovery.secondaryAction {
                        RecoveryActionButton(
                            action: secondaryAction,
                            language: store.language,
                            isCompact: true,
                            perform: perform
                        )
                    }
                }
                .layoutPriority(2)
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
                    .accessibilityLabel(Text(store.language.refreshUsage))
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
                    .accessibilityLabel(Text(store.language.showSettings))
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
        .background(GlassCardBackground(tuning: tuning))
    }

    private var syncIsCurrent: Bool {
        syncEligibleState
            && store.lastError == nil
            && store.snapshot.providerSource?.freshness == .fresh
            && store.snapshot.providerSource?.capturedAt != nil
    }

    private var syncStatus: String {
        if case .refreshingWithPreviousRealData = store.currentState {
            return store.language.connectionRefreshingTitle
        }
        if case .staleWithPreviousRealData = store.currentState {
            return store.language.outdated
        }
        if syncIsCurrent, let capturedAt = store.snapshot.providerSource?.capturedAt {
            return store.language.syncedAt(capturedAt)
        }
        if let recovery { return recovery.statusText }
        return store.language.outdated
    }

    private var syncEligibleState: Bool {
        switch store.currentState {
        case .ready, .refreshingWithPreviousRealData:
            true
        default:
            false
        }
    }
}

private struct RecoveryActionButton: View {
    let action: CodexPresentedAction
    let language: AppLanguage
    var isCompact = false
    let perform: @MainActor (CodexConnectionAction) async -> Void

    var body: some View {
        Button {
            Task { await perform(action.action) }
        } label: {
            if isCompact {
                Image(systemName: action.action == .disconnect ? "bolt.slash" : "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
            } else {
                Text(action.title)
                    .font(UsageDesign.font(.secondaryBody, language: language))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .frame(minHeight: 30)
            }
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(Color.orange.opacity(0.16)))
        .accessibilityLabel(action.title)
        .help(action.title)
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
                    QuotaRow(
                        period: period,
                        planLabel: snapshot.planLabel,
                        language: language
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
                            .font(
                                UsageDesign.font(
                                    .tokenMetric,
                                    language: language,
                                    sizeOverride: 18
                                )
                            )
                            .monospacedDigit()
                        Text(metric.label)
                            .font(
                                UsageDesign.font(
                                    .secondaryBody,
                                    language: language,
                                    sizeOverride: 12
                                )
                            )
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 68)
        }
        .background(GlassCardBackground(tuning: tuning))
    }
}

private struct QuotaRow: View {
    let period: UsagePeriod
    let planLabel: String
    let language: AppLanguage

    private var bar: QuotaBarModel {
        QuotaBarModel(
            remainingPercent: period.remainingPercent,
            planLabel: planLabel,
            isUnlimited: period.isUnlimited
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(period.title)
                    .font(UsageDesign.font(.quotaLabel, language: language))
                Spacer()
                Text(period.isUnlimited ? "∞" : "\(period.remainingPercent)%")
                    .font(
                        UsageDesign.font(
                            .primaryQuotaValue,
                            language: language,
                            sizeOverride: period.isUnlimited ? 16 : nil
                        )
                    )
                    .foregroundStyle(period.isUnlimited ? Color.secondary : bar.tone == .low ? Color.red : UsageDesign.blue)
                    .monospacedDigit()
            }

            if !period.isUnlimited {
                ProgressView(value: Double(period.remainingPercent), total: 100) {
                    Text(period.title)
                }
                .progressViewStyle(MacroQuotaProgressStyle(bar: bar))
                .accessibilityLabel(
                    Text(
                        language.quotaAccessibilityLabel(
                            title: period.title,
                            remainingPercent: period.remainingPercent
                        )
                    )
                )
                .accessibilityValue(
                    Text(language.remainingAccessibilityValue(period.remainingPercent))
                )
                .frame(height: 8)
            }

            HStack {
                Text(language.remaining)
                Spacer()
                Text(period.resetText)
            }
            .font(UsageDesign.font(.resetTime, language: language))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, period.isUnlimited ? 8 : 10)
    }
}

private struct MacroQuotaProgressStyle: ProgressViewStyle {
    let bar: QuotaBarModel

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 4) {
                ForEach(Array(bar.segments.enumerated()), id: \.offset) { _, segment in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.13))
                        Capsule()
                            .fill(bar.tone == .low ? Color.red : UsageDesign.blue)
                            .frame(
                                width: max(
                                    0,
                                    (proxy.size.width - 16)
                                        * CGFloat(segment.relativeWidth)
                                        * CGFloat(segment.fillFraction)
                                )
                            )
                    }
                    .frame(width: (proxy.size.width - 16) * CGFloat(segment.relativeWidth))
                }
            }
        }
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
                    .font(UsageDesign.font(.sectionTitle, language: language))
                Spacer()
                Text(language.threadTotalTokens)
                    .font(
                        UsageDesign.font(
                            .secondaryBody,
                            language: language,
                            sizeOverride: 11
                        )
                    )
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 7)

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
        VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(
                            UsageDesign.font(
                                .sectionTitle,
                                language: language,
                                sizeOverride: 14
                            )
                        )
                        .lineLimit(1)
                    Text(task.time)
                        .font(UsageDesign.font(.secondaryBody, language: language))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(task.tokenText)
                    .font(UsageDesign.font(.tokenMetric, language: language))
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
        .padding(.vertical, 6)
    }
}
