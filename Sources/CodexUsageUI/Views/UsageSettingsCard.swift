import SwiftUI

enum UsageSettingsDestination: Equatable {
    case workBuddy
}

struct UsageSettingsCard: View {
    @Binding var showUsageSummary: Bool
    @Binding var showRecentTasks: Bool
    @Binding var showAPICost: Bool
    @Binding var language: AppLanguage
    let workBuddySettings: WorkBuddySettingsModel?
    let workBuddyLogin: WorkBuddyLoginCoordinator?
    let workBuddyAccountWebSync: WorkBuddyAccountWebSessionController?
    let providerLoginOptions: [ProviderLoginOption]
    let destination: UsageSettingsDestination?
    let tuning: GlassTuning
    let maximumHeight: CGFloat
    let checkAgain: () -> Void
    let syncWorkBuddyAccount: () -> Void
    let disconnectWorkBuddyAccount: () -> Void
    let close: () -> Void

    @State private var launchAtLoginState = LaunchAtLoginService.state
    @State private var launchAtLoginError: String?
    @AppStorage(DesktopAssistantPreferences.Keys.isEnabled)
    private var assistantEnabled = true
    @AppStorage(DesktopAssistantPreferences.Keys.isAlwaysOnTop)
    private var assistantAlwaysOnTop = true
    @AppStorage(DesktopAssistantPreferences.Keys.density)
    private var assistantDensityRaw = DesktopAssistantDensity.automatic.rawValue

    var body: some View {
        adaptiveContent
        .padding(14)
        .frame(width: 306)
        .frame(maxHeight: maximumHeight)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
            GlassCardBackground(tuning: tuning)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 14, y: 8)
        .onAppear {
            launchAtLoginState = LaunchAtLoginService.state
        }
    }

    @ViewBuilder
    private var adaptiveContent: some View {
        if workBuddyLogin != nil || workBuddyAccountWebSync != nil {
            ScrollView(.vertical) {
                settingsContent
                    .frame(width: 278, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .accessibilityLabel(language.settingsTitle)
        } else {
            ViewThatFits(in: .vertical) {
                settingsContent
                ScrollView(.vertical) {
                    settingsContent
                }
                .scrollIndicators(.automatic)
                .accessibilityLabel(language.settingsTitle)
            }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(UsageDesign.blue)
                Text(language.settingsTitle)
                    .font(UsageDesign.font(15, weight: .bold, language: language))
                Spacer()
                Button(language.showAll) {
                    showUsageSummary = true
                    showRecentTasks = true
                    showAPICost = true
                }
                .buttonStyle(.plain)
                .font(UsageDesign.font(10.5, weight: .medium, language: language))
                .foregroundStyle(UsageDesign.blue)

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

            VStack(alignment: .leading, spacing: 8) {
                Text(language.cardsSection)
                    .font(UsageDesign.font(10.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)

                SettingsToggleRow(
                    title: language.usageSummaryCard,
                    systemImage: "gauge.with.dots.needle.67percent",
                    language: language,
                    isOn: $showUsageSummary
                )
                SettingsToggleRow(
                    title: language.recentTasks,
                    systemImage: "list.bullet.rectangle",
                    language: language,
                    isOn: $showRecentTasks
                )
                SettingsToggleRow(
                    title: language.costCard,
                    systemImage: "dollarsign.circle",
                    language: language,
                    isOn: $showAPICost
                )
            }

            Divider()
                .opacity(0.35)

            if !providerLoginOptions.isEmpty {
                ProviderLoginAssistanceSection(
                    options: providerLoginOptions,
                    language: language,
                    checkAgain: checkAgain
                )

                Divider()
                    .opacity(0.35)
            }

            if let workBuddySettings {
                WorkBuddySettingsSection(
                    model: workBuddySettings,
                    login: workBuddyLogin,
                    accountWebSync: workBuddyAccountWebSync,
                    language: language,
                    expandOnAppear: destination == .workBuddy,
                    checkAgain: checkAgain,
                    syncNow: syncWorkBuddyAccount,
                    disconnectAccount: disconnectWorkBuddyAccount
                )

                Divider()
                    .opacity(0.35)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(language.desktopAssistantSection)
                    .font(UsageDesign.font(10.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)

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
            }

            Divider()
                .opacity(0.35)

            VStack(alignment: .leading, spacing: 7) {
                Text(language.generalSection)
                    .font(UsageDesign.font(10.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)

                LanguageSettingRow(language: $language)

                SettingsToggleRow(
                    title: language.launchAtLogin,
                    systemImage: "power",
                    language: language,
                    isOn: launchAtLoginBinding
                )

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
                    .font(UsageDesign.font(9.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(UsageDesign.font(9.5, language: language))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                        .font(UsageDesign.font(12.5, weight: .semibold, language: language))
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
                        .font(UsageDesign.font(9.5, weight: .medium, language: language))
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
                            .font(UsageDesign.font(9, language: language))
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
                            Text(language.workBuddyCompanionName($0)).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!model.isEnabled)

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
                            .font(UsageDesign.font(9.5, weight: .medium, language: language))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(language.workBuddyValidationMessage(validationError))
                    }

                    if model.lifecycle == .invalidSavedData {
                        Text(language.workBuddyInvalidSavedData)
                            .font(UsageDesign.font(9.5, weight: .medium, language: language))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !model.isEnabled || model.savedObservation == nil {
                        Text(language.workBuddyNotConfigured)
                            .font(UsageDesign.font(9.5, language: language))
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
                            .font(UsageDesign.font(9.5, weight: .medium, language: language))
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
        .font(UsageDesign.font(10, weight: .medium, language: language))
        .accessibilityElement(children: .combine)
    }

    private func previewView(_ preview: WorkBuddyManualPreview) -> some View {
        let balance = preview.observation.balance
        return VStack(alignment: .leading, spacing: 3) {
            Text(language.workBuddyManualSnapshot)
                .font(UsageDesign.font(10.5, weight: .semibold, language: language))
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
        .font(UsageDesign.font(9.5, language: language))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(
                    language.workBuddyAccountWebTitle,
                    systemImage: "safari"
                )
                .font(UsageDesign.font(12, weight: .semibold, language: language))
                Spacer()
                Text(language.workBuddyExperimentalLabel)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            Text(language.workBuddyAccountWebDisclosure)
                .font(UsageDesign.font(9.5, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            WorkBuddyLoginConfirmationRow(
                title: language.workBuddyAccountWebConsent,
                isOn: controller.consentGranted,
                language: language,
                action: {
                    if controller.consentGranted {
                        disconnectAccount()
                    } else {
                        controller.grantConsent()
                    }
                }
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(language.workBuddyAccountWebSessionChoice)
                    .font(UsageDesign.font(9.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)
                Picker(
                    "",
                    selection: $controller.sessionMode
                ) {
                    ForEach(WorkBuddyAccountWebSessionMode.allCases) { mode in
                        Text(language.workBuddyAccountWebSessionMode(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(!controller.consentGranted)
                .accessibilityLabel(language.workBuddyAccountWebSessionChoice)
            }

            VStack(alignment: .leading, spacing: 6) {
                Button(language.workBuddyAccountWebConnect) {
                    controller.connect()
                }
                .disabled(!controller.consentGranted)

                Button(language.workBuddyAccountWebSyncNow, action: syncNow)
                    .disabled(
                        !controller.consentGranted
                            || controller.flowState == .synchronizing
                    )
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 6) {
                Button(language.workBuddyAccountWebOpenUsage) {
                    controller.openAccountUsage()
                }
                .disabled(!controller.consentGranted)

                Button(language.checkAgain, action: checkAgain)
                    .disabled(!controller.consentGranted)
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 6) {
                Button(language.workBuddyCancelLogin, role: .cancel) {
                    controller.cancel()
                }
                Button(
                    language.workBuddyAccountWebDisconnect,
                    role: .destructive,
                    action: disconnectAccount
                )
                .disabled(!controller.consentGranted)
            }
            .buttonStyle(.borderless)

            HStack(spacing: 6) {
                if controller.flowState == .opening
                    || controller.flowState == .synchronizing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(language.workBuddyAccountWebState(controller.flowState))
                    .font(UsageDesign.font(9.5, weight: .medium, language: language))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if let safeDiagnosticCode = controller.safeDiagnosticCode {
                Text(
                    "\(language.workBuddyAccountWebSafeDiagnostic): "
                        + safeDiagnosticCode
                )
                .font(UsageDesign.font(8.5, language: language))
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "\(language.workBuddyAccountWebSafeDiagnostic), "
                        + safeDiagnosticCode
                )
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
                    Text(
                        "\(language.workBuddySource): "
                            + language.workBuddyAccountWebSource
                    )
                    Text(
                        "\(language.workBuddySupportStatus): "
                            + language.workBuddyExperimentalLabel
                    )
                    Text(language.workBuddyConfirmedAt(snapshot.observedAt))
                }
                .font(UsageDesign.font(9.5, weight: .medium, language: language))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountCreditRow(_ label: String, value: Decimal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
            Spacer(minLength: 8)
            Text(
                CreditFormatter.exactTwoDecimal(value, language: language)
            )
            .monospacedDigit()
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
            .font(UsageDesign.font(12, weight: .semibold, language: language))

            Text(language.workBuddyLoginPrivacySummary)
                .font(UsageDesign.font(9.5, language: language))
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
                    .font(UsageDesign.font(9.5, weight: .medium, language: language))
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
                    .font(UsageDesign.font(9, language: language))
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
                        .font(UsageDesign.font(9.5, weight: .medium, language: language))
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
                        .font(UsageDesign.font(10, weight: .semibold, language: language))
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
                .font(UsageDesign.font(9.5, language: language))
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
                .font(UsageDesign.font(10.5, weight: .medium, language: language))
                .foregroundStyle(.secondary)

            ForEach(options) { option in
                VStack(alignment: .leading, spacing: 7) {
                    Label(option.providerName, systemImage: "person.crop.circle.badge.checkmark")
                        .font(UsageDesign.font(12.5, weight: .semibold, language: language))

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
                .font(UsageDesign.font(12.5, weight: .medium, language: language))

            HStack(spacing: 4) {
                ForEach(DesktopAssistantDensity.allCases, id: \.rawValue) { density in
                    Button {
                        selection = density
                    } label: {
                        Text(language.desktopAssistantDensityName(density))
                            .font(UsageDesign.font(9.5, weight: .medium, language: language))
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
                    .font(UsageDesign.font(12.5, weight: .medium, language: language))
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

private struct LanguageSettingRow: View {
    @Binding var language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Label(language.languageSetting, systemImage: "globe")
                .font(UsageDesign.font(12.5, weight: .medium, language: language))
            Spacer(minLength: 6)
            HStack(spacing: 3) {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        language = option
                    } label: {
                        Text(option.displayName)
                            .font(UsageDesign.font(9.5, weight: .medium, language: option))
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
