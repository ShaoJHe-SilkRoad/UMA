import AppKit
import SwiftUI

struct WorkBuddyMainPanelCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let card: SharedUsageCardPresentation
    let language: AppLanguage
    let tuning: GlassTuning
    let settings: WorkBuddySettingsModel?
    @Binding var isExpanded: Bool
    let openSettings: () -> Void
    let now: Date
    let appearanceOverride: UsagePanelAppearanceOverride?

    init(
        card: SharedUsageCardPresentation,
        language: AppLanguage,
        tuning: GlassTuning,
        settings: WorkBuddySettingsModel?,
        isExpanded: Binding<Bool>,
        openSettings: @escaping () -> Void,
        now: Date = Date(),
        appearanceOverride: UsagePanelAppearanceOverride? = nil
    ) {
        self.card = card
        self.language = language
        self.tuning = tuning
        self.settings = settings
        self._isExpanded = isExpanded
        self.openSettings = openSettings
        self.now = now
        self.appearanceOverride = appearanceOverride
    }

    var body: some View {
        if let presentation = WorkBuddyMainPanelPresentation.make(
            card: card,
            language: language,
            now: now
        ) {
            VStack(alignment: .leading, spacing: 0) {
                collapsedHeader(presentation)
                if isExpanded {
                    Divider()
                        .opacity(0.32)
                        .padding(.horizontal, 14)
                    expandedDetails(presentation)
                        .transition(
                            usesReduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .top))
                        )
                }
            }
            .background {
                GlassCardBackground(
                    tuning: tuning,
                    appearanceOverride: appearanceOverride
                )
            }
            .animation(
                usesReduceMotion ? nil : .easeInOut(duration: 0.18),
                value: isExpanded
            )
        }
    }

    private func collapsedHeader(
        _ presentation: WorkBuddyMainPanelPresentation
    ) -> some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 9) {
                providerMark
                    .fixedSize()
                    .layoutPriority(2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.providerName)
                        .font(AppTypography.font(15, weight: .bold, language: language))
                        .lineLimit(1)
                    Text(presentation.scopeTitle)
                        .font(AppTypography.font(10.5, weight: .medium, language: language))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Label(
                        presentation.compactManualStatus,
                        systemImage: "hand.raised.fill"
                    )
                        .font(AppTypography.font(9.5, language: language))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(2)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(presentation.compactValue)
                        .font(AppTypography.font(19, weight: .bold, language: language))
                        .monospacedDigit()
                    Label(
                        presentation.severityText,
                        systemImage: severitySymbol(presentation.severity)
                    )
                    .font(AppTypography.font(8.5, weight: .medium, language: language))
                    .foregroundStyle(severityColor(presentation.severity))
                    .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: UsagePanelMetrics.collapsedProviderCardHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(
            isExpanded ? language.workBuddyExpanded : language.workBuddyCollapsed
        )
    }

    private var providerMark: some View {
        ZStack {
            Circle()
                .fill(UsageDesign.blue.opacity(0.14))
            Image(systemName: "w.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(UsageDesign.blue)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private func expandedDetails(
        _ presentation: WorkBuddyMainPanelPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.availableText)
                    .font(AppTypography.font(17, weight: .bold, language: language))
                    .foregroundStyle(severityColor(presentation.severity))
                    .fixedSize(horizontal: false, vertical: true)
                if let balanceDetail = presentation.balanceDetail {
                    Text(balanceDetail)
                        .font(AppTypography.font(11, weight: .medium, language: language))
                        .foregroundStyle(.secondary)
                }
            }

            if let fraction = presentation.remainingFraction {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.14))
                        Capsule()
                            .fill(severityColor(presentation.severity))
                            .frame(width: proxy.size.width * CGFloat(fraction))
                    }
                }
                .frame(height: 8)
                .accessibilityLabel(
                    "\(presentation.availableText), \(presentation.balanceDetail ?? "")"
                )
            }

            detailRow(
                language.workBuddyScope,
                value: "\(presentation.scopeTitle) · \(presentation.scopeDetail)"
            )
            detailRow(language.workBuddySource, value: language.workBuddyManualConfirmation)
            detailRow(language.workBuddyLastConfirmed, value: presentation.manualStatus)
            if let exactConfirmation = presentation.exactConfirmation {
                detailRow(language.workBuddyExactConfirmation, value: exactConfirmation)
            }
            if let tierText = presentation.tierText {
                detailRow(language.workBuddyTier, value: tierText)
            }
            if let expiryText = presentation.expiryText {
                detailRow(language.workBuddyNextExpiryLabel, value: expiryText)
            }

            Text(presentation.limitationText)
                .font(AppTypography.font(9.5, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                Button(language.workBuddyUpdateCredits, action: openSettings)
                Button(language.workBuddyOpenOfficialUsagePage) {
                    _ = settings?.openOfficialUsagePage()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 7) {
                Button(language.workBuddyConfirmUnchanged) {
                    settings?.confirmUnchanged(language: language)
                }
                .disabled(settings?.canConfirmUnchanged != true)

                Button(language.workBuddyClearData, role: .destructive, action: openSettings)
                    .accessibilityHint(language.workBuddyClearInSettingsHint)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var usesReduceMotion: Bool {
        appearanceOverride?.reduceMotion ?? reduceMotion
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
        .accessibilityElement(children: .combine)
    }

    private func severityColor(_ severity: AgentAvailabilitySeverity) -> Color {
        switch severity {
        case .available: UsageDesign.green
        case .warning: .orange
        case .critical, .exhausted, .invalid: .red
        case .neutral: .secondary
        }
    }

    private func severitySymbol(_ severity: AgentAvailabilitySeverity) -> String {
        switch severity {
        case .available: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .critical, .exhausted: "exclamationmark.octagon"
        case .invalid: "xmark.octagon"
        case .neutral: "questionmark.circle"
        }
    }
}
