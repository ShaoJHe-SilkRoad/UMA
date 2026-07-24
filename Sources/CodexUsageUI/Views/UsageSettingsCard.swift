import SwiftUI

struct UsageSettingsCard: View {
    @Binding var showUsageSummary: Bool
    @Binding var showRecentTasks: Bool
    @Binding var showAPICost: Bool
    @Binding var language: AppLanguage
    let workBuddySettings: WorkBuddySettingsModel?
    let tuning: GlassTuning
    let maximumHeight: CGFloat
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
        ViewThatFits(in: .vertical) {
            settingsContent
            ScrollView(.vertical) {
                settingsContent
            }
            .scrollIndicators(.automatic)
            .accessibilityLabel(language.settingsTitle)
        }
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

            if let workBuddySettings {
                WorkBuddySettingsSection(
                    model: workBuddySettings,
                    language: language
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
    let language: AppLanguage
    @State private var isExpanded = false
    @State private var clearIsArmed = false

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
                            language.workBuddyCompanionName(model.draft.companionField),
                            text: $model.draft.companionText
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(!model.isEnabled)
                        .accessibilityLabel(
                            language.workBuddyCompanionName(model.draft.companionField)
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear { model.start() }
        .onChange(of: model.draft) {
            model.updateValidation()
            clearIsArmed = false
        }
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
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
