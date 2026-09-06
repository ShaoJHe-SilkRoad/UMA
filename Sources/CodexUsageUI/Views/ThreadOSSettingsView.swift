import SwiftUI
import AppKit
import Combine

@MainActor public protocol ThreadOSSettingsClipboard { func write(_ string: String) -> Bool }
@MainActor public struct SystemThreadOSSettingsClipboard: ThreadOSSettingsClipboard {
    public init() {}
    public func write(_ string: String) -> Bool { let board = NSPasteboard.general; board.clearContents(); return board.setString(string, forType: .string) }
}

/// Local-only form actions: they do not send work or establish native state.
@MainActor public enum ThreadOSSettingsFormActions {
    public enum SemanticEditOutcome: Equatable { case applied, unchanged, rejectedMaximumRevision, rejectedInvalidDraft }
    @discardableResult public static func semanticEdit(_ draft: inout ThreadOSSettingsDraft, _ mutation: (inout ThreadOSSettingsDraft) -> Void) -> SemanticEditOutcome {
        let original = draft; var candidate = draft; mutation(&candidate); candidate.revision = original.revision
        guard candidate != original else { return .unchanged }
        guard original.revision < 1_000_000 else { return .rejectedMaximumRevision }
        guard candidate.isLocallyValid else { return .rejectedInvalidDraft }
        candidate.changed(); draft = candidate; return .applied
    }
    @discardableResult public static func edit(_ draft: inout ThreadOSSettingsDraft, _ mutation: (inout ThreadOSSettingsDraft) -> Void) -> Bool { semanticEdit(&draft, mutation) == .applied }
    public static func copy(_ draft: ThreadOSSettingsDraft, to clipboard: any ThreadOSSettingsClipboard) throws {
        guard draft.isLocallyValid else { throw ThreadOSSettingsFormError.invalidDraft }
        let request = try ThreadOSSettingsCodec.canonicalRequest(draft)
        guard clipboard.write(request) else { throw ThreadOSSettingsFormError.clipboardWriteFailed }
    }
}

public enum ThreadOSSettingsFormError: LocalizedError, Equatable {
    case invalidDraft, clipboardWriteFailed
    public var errorDescription: String? { switch self { case .invalidDraft: "The local draft is incomplete or invalid."; case .clipboardWriteFailed: "The local clipboard could not be written." } }
}

/// The selected role choices and catalog resolution consumed by the actual form.
/// A resolved model is local configuration, never an observed native model.
public struct ThreadOSSettingsRolePresentation: Identifiable, Equatable {
    public let role: ThreadOSRole
    public let selection: ThreadOSRoleSelection
    public let resolved: ThreadOSRoleSelection
    public let modelOptions: [String]
    public let effortOptions: [String]
    public let isEditable: Bool
    public var id: String { role.rawValue }
    public var summaryIdentifier: String { "uma.threados.role.\(id).summary" }
    public var modelIdentifier: String { "uma.threados.role.\(id).model" }
    public var effortIdentifier: String { "uma.threados.role.\(id).effort" }
    public func summary(language: AppLanguage) -> String {
        let choice = "\(selection.model) / \(selection.reasoningEffort)"
        if selection.model == "coder_auto" {
            return localized(language, "\(choice) — catalog fallback: \(resolved.model) / \(resolved.reasoningEffort); effective native model: UNKNOWN", "\(choice) — 目录回退：\(resolved.model) / \(resolved.reasoningEffort)；有效原生模型：UNKNOWN")
        }
        return localized(language, "\(choice); effective native model: UNKNOWN", "\(choice)；有效原生模型：UNKNOWN")
    }
}

/// The actual Settings view state and presentation path. Non-configuration ACKs
/// are displayed as provided local facts; only configuration ACKs require a full
/// local match, and none authenticate a project or prove an effective model.
@MainActor public final class ThreadOSSettingsFormState: ObservableObject {
    @Published public private(set) var draft: ThreadOSSettingsDraft
    @Published public private(set) var selectedProject: String
    @Published public var newProject = ""
    @Published public private(set) var message = ""
    @Published public private(set) var receipt = ""
    @Published public private(set) var acceptedReceipt: ThreadOSSettingsReceiptProjection?
    @Published public private(set) var receiptInputIsInvalid = false
    @Published public private(set) var copiedRevision: Int?
    private let preferences: ApplicationPreferences

    public init(preferences: ApplicationPreferences = .production) {
        self.preferences = preferences
        let saved = ThreadOSSettingsPreferences.load(from: preferences)
        draft = saved; selectedProject = saved.isValidProject ? saved.project : ""
    }
    public func semanticEdit(_ mutation: (inout ThreadOSSettingsDraft) -> Void, language: AppLanguage) {
        switch ThreadOSSettingsFormActions.semanticEdit(&draft, mutation) {
        case .applied: invalidateReceiptAndCopy(); ThreadOSSettingsPreferences.save(draft, to: preferences)
        case .unchanged: break
        case .rejectedMaximumRevision: message = localized(language, "Edit was not applied: this draft is already at the maximum revision.", "未应用编辑：此草稿已达到最大修订版本。")
        case .rejectedInvalidDraft: message = localized(language, "Edit was not applied: it would make the local draft invalid.", "未应用编辑：它会使本地草稿无效。")
        }
    }
    /// Prepare all dependent fields before a single semantic edit. Selecting the
    /// current preset is a no-op, so deliberate count overrides survive.
    public func selectPreset(_ preset: String, catalog: ThreadOSModelCatalog?, language: AppLanguage) {
        guard preset != draft.preset else { return }
        do {
            guard let catalog, let spec = catalog.presets[preset] else { throw ThreadOSSettingsCodecError.unsupportedPreset }
            var candidate = draft
            candidate.preset = preset
            if preset == "custom" {
                if candidate.customRoles.isEmpty {
                    candidate.customRoles = try Self.catalogRoles(preset: "astra-balanced", catalog: catalog)
                }
            } else {
                _ = try Self.catalogRoles(preset: preset, catalog: catalog)
                guard let coding = spec.codingWorkers, let review = spec.reviewWorkers else { throw ThreadOSSettingsCodecError.catalogUnavailable }
                candidate.codingWorkers = coding; candidate.reviewWorkers = review
            }
            // Tier is already an explicit draft field: retain standard or the
            // user's deliberate priority choice across every preset transition.
            _ = try ThreadOSSettingsCodec.canonicalRequest(candidate, catalog: catalog)
            semanticEdit({ $0 = candidate }, language: language)
        } catch { rejectConfigurationEdit(language: language) }
    }
    public func selectCustomModel(_ model: String, role: ThreadOSRole, catalog: ThreadOSModelCatalog?, language: AppLanguage) {
        do {
            guard let catalog, draft.preset == "custom", var choice = draft.customRoles[role], Self.modelOptions(role: role, catalog: catalog).contains(model) else { throw ThreadOSSettingsCodecError.unsupportedModel }
            guard choice.model != model else { return }
            let efforts = Self.effortOptions(model: model, catalog: catalog)
            choice.model = model
            if !efforts.contains(choice.reasoningEffort) {
                guard let effort = efforts.first else { throw ThreadOSSettingsCodecError.unsupportedModel }
                choice.reasoningEffort = effort
            }
            try applyCustomChoice(choice, role: role, catalog: catalog, language: language)
        } catch { rejectConfigurationEdit(language: language) }
    }
    public func selectCustomEffort(_ effort: String, role: ThreadOSRole, catalog: ThreadOSModelCatalog?, language: AppLanguage) {
        do {
            guard let catalog, draft.preset == "custom", var choice = draft.customRoles[role], Self.effortOptions(model: choice.model, catalog: catalog).contains(effort) else { throw ThreadOSSettingsCodecError.invalidRoleConfiguration }
            choice.reasoningEffort = effort
            try applyCustomChoice(choice, role: role, catalog: catalog, language: language)
        } catch { rejectConfigurationEdit(language: language) }
    }
    public func rolePresentations(catalog: ThreadOSModelCatalog) throws -> [ThreadOSSettingsRolePresentation] {
        _ = try ThreadOSSettingsCodec.canonicalRequest(draft, catalog: catalog)
        let choices = draft.preset == "custom" ? draft.customRoles : try Self.catalogRoles(preset: draft.preset, catalog: catalog)
        return try ThreadOSRole.allCases.map { role in
            guard let choice = choices[role] else { throw ThreadOSSettingsCodecError.invalidRoleConfiguration }
            return .init(role: role, selection: choice, resolved: try ThreadOSSettingsCodec.resolvedSelection(choice, role: role, catalog: catalog), modelOptions: Self.modelOptions(role: role, catalog: catalog), effortOptions: Self.effortOptions(model: choice.model, catalog: catalog), isEditable: draft.preset == "custom")
        }
    }
    private static func catalogRoles(preset: String, catalog: ThreadOSModelCatalog) throws -> [ThreadOSRole: ThreadOSRoleSelection] {
        guard let roles = catalog.presets[preset]?.roles, Set(roles.keys) == Set(ThreadOSRole.allCases.map(\.rawValue)) else { throw ThreadOSSettingsCodecError.invalidRoleConfiguration }
        return try Dictionary(uniqueKeysWithValues: ThreadOSRole.allCases.map { role in
            guard let spec = roles[role.rawValue] else { throw ThreadOSSettingsCodecError.invalidRoleConfiguration }
            let choice = ThreadOSRoleSelection(model: spec.selection ?? spec.model, reasoningEffort: spec.reasoningEffort)
            _ = try ThreadOSSettingsCodec.resolvedSelection(choice, role: role, catalog: catalog)
            return (role, choice)
        })
    }
    private static func modelOptions(role: ThreadOSRole, catalog: ThreadOSModelCatalog) -> [String] {
        (role == .foreman ? ["coder_auto"] : []) + catalog.models.keys.filter { $0 != "gpt-5.6-sol" }.sorted()
    }
    private static func effortOptions(model: String, catalog: ThreadOSModelCatalog) -> [String] {
        if model == "coder_auto" { return [catalog.selectionPolicy.coderAutoFallback.reasoningEffort] }
        return catalog.models[model]?.reasoningEfforts ?? []
    }
    private func applyCustomChoice(_ choice: ThreadOSRoleSelection, role: ThreadOSRole, catalog: ThreadOSModelCatalog, language: AppLanguage) throws {
        var candidate = draft; candidate.customRoles[role] = choice
        _ = try ThreadOSSettingsCodec.canonicalRequest(candidate, catalog: catalog)
        semanticEdit({ $0 = candidate }, language: language)
    }
    private func rejectConfigurationEdit(language: AppLanguage) {
        message = localized(language, "Edit was not applied: the catalog or role selection is invalid.", "未应用编辑：目录或角色选择无效。")
    }
    public func select(project: String) {
        selectedProject = project; invalidateReceiptAndCopy()
        draft = project.isEmpty ? ThreadOSSettingsDraft() : (ThreadOSSettingsPreferences.load(project: project, from: preferences) ?? ThreadOSSettingsDraft(project: project))
    }
    public func createProject() {
        guard ThreadOSSettingsDraft.isToken(newProject) else { return }
        let project = newProject; selectedProject = project
        draft = ThreadOSSettingsPreferences.load(project: project, from: preferences) ?? ThreadOSSettingsDraft(project: project)
        newProject = ""; invalidateReceiptAndCopy(); ThreadOSSettingsPreferences.save(draft, to: preferences)
    }
    public func copy(to clipboard: any ThreadOSSettingsClipboard, language: AppLanguage) {
        guard draft.isValidProject else { message = localized(language, "Cannot copy: select a valid project first.", "无法复制：请先选择有效项目。"); return }
        do {
            try ThreadOSSettingsFormActions.copy(draft, to: clipboard)
            copiedRevision = draft.revision
            message = localized(language, "Generated and copied a local settings request. It was not sent, applied, or accepted as native proof.", "已生成并复制本地设置请求；未发送、未应用，也不构成原生证明。")
        } catch ThreadOSSettingsFormError.clipboardWriteFailed {
            message = localized(language, "Local request was generated, but it could not be copied because the local clipboard write failed.", "本地设置请求已生成，但本地剪贴板写入失败，未能复制。")
        } catch {
            let code = (error as? ThreadOSSettingsCodecError)?.protocolCode ?? "LOCAL_VALIDATION_FAILED"
            message = localized(language, "Cannot generate local settings request (\(code)).", "无法生成本地设置请求（\(code)）。")
        }
    }
    public func receiveReceipt(_ text: String) {
        receipt = text
        guard let projection = ThreadOSSettingsCodec.receiptProjection(text) else { receiptInputIsInvalid = true; return }
        acceptedReceipt = projection; receiptInputIsInvalid = false
    }
    public func receiptStatus(catalog: ThreadOSModelCatalog?, language: AppLanguage) -> String {
        guard let projection = acceptedReceipt else { return localized(language, "Receipt is invalid or unsupported. Project identity remains unauthenticated and native model truth is unknown.", "回执无效或不受支持。项目身份仍未经认证，原生模型真相未知。") }
        if receiptInputIsInvalid { return localized(language, "Latest receipt is invalid or unsupported; retaining the prior valid local receipt. Project identity remains unauthenticated and native model truth is unknown.", "最新回执无效或不受支持；保留之前有效的本地回执。项目身份仍未经认证，原生模型真相未知。") }
        if projection.presentation == .pendingNativeSelection {
            guard let catalog, projection.matches(draft: draft, catalog: catalog) else { return localized(language, "Receipt does not fully match this local request and configured view. Project identity remains unauthenticated and native model truth is unknown.", "回执与此本地请求及配置视图不完全匹配。项目身份仍未经认证，原生模型真相未知。") }
            return localized(language, "Receipt fully matches the local request and configured view. Pending native selection; effective model: UNKNOWN. Project identity is not authenticated.", "回执与本地请求及配置视图完全匹配。等待原生选择；有效模型：UNKNOWN。项目身份未经认证。")
        }
        guard projection.presentation != .unsupported else { return localized(language, "Receipt is invalid or unsupported. Project identity remains unauthenticated and native model truth is unknown.", "回执无效或不受支持。项目身份仍未经认证，原生模型真相未知。") }
        return localized(language, "Receipt reports \(receiptToken(projection.presentation)) as a provided local fact. It does not authenticate project identity or prove an effective native model.", "回执将 \(receiptToken(projection.presentation)) 报告为提供的本地事实；它不认证项目身份，也不能证明有效原生模型。")
    }
    private func invalidateReceiptAndCopy() { copiedRevision = nil; message = ""; receipt = ""; acceptedReceipt = nil; receiptInputIsInvalid = false }
}

private func receiptToken(_ value: ThreadOSSettingsAcknowledgementPresentation) -> String {
    switch value {
    case .pendingNativeSelection: "PENDING_NATIVE_SELECTION"
    case .modeOnObservedLocalOnly: "MODE_ON_OBSERVED_LOCAL_ONLY"
    case .modeOffObservedLocalOnly: "MODE_OFF_OBSERVED_LOCAL_ONLY"
    case .modeOffQueuedUntilIdle: "MODE_OFF_QUEUED_UNTIL_IDLE"
    case .waveStartedConfiguredModelUnobserved: "WAVE_STARTED_CONFIGURED_MODEL_UNOBSERVED"
    case .waveFinishedLocalOnly: "WAVE_FINISHED_LOCAL_ONLY"
    case .statusLocalOnly: "STATUS_LOCAL_ONLY"
    case .settingsError: "THREADOS_SETTINGS_ERROR"
    case .unsupported: "UNSUPPORTED_RECEIPT_SHAPE"
    }
}
private func localized(_ language: AppLanguage, _ english: String, _ chinese: String) -> String { language == .simplifiedChinese ? chinese : english }

public struct ThreadOSSettingsView: View {
    public let language: AppLanguage
    private let preferences: ApplicationPreferences
    @StateObject private var form: ThreadOSSettingsFormState
    public init(language: AppLanguage, preferences: ApplicationPreferences = .production) {
        self.language = language; self.preferences = preferences
        _form = StateObject(wrappedValue: ThreadOSSettingsFormState(preferences: preferences))
    }
    public var body: some View { Form {
        Section(title("ThreadOS Settings", "ThreadOS 设置")) {
            Text(title("Complete project Setup with Leader first. This local-only page saves and copies a next-wave request; it never sends work, switches models, or proves native model selection.", "请先由 Leader 完成项目 Setup。本地专用页面只保存和复制下一波请求；不会发送工作、切换模型，也不能证明原生模型选择。")).foregroundStyle(.secondary).accessibilityIdentifier("uma.threados.provenance")
            Picker(title("Project", "项目"), selection: Binding(get: { form.selectedProject }, set: { form.select(project: $0) })) { Text(title("No project selected", "未选择项目")).tag(""); ForEach(ThreadOSSettingsPreferences.projects(from: preferences), id: \.self) { Text($0).tag($0) } }.accessibilityIdentifier("uma.threados.project-selector")
            HStack { TextField(title("New project key", "新项目键"), text: $form.newProject).accessibilityIdentifier("uma.threados.new-project"); Button(title("Use project", "使用项目"), action: form.createProject).disabled(!ThreadOSSettingsDraft.isToken(form.newProject)).accessibilityIdentifier("uma.threados.use-project") }
            if form.draft.isValidProject { settingsFields } else { Text(title("No valid project is selected. Choose an existing project or enter a project key to create a local draft.", "尚未选择有效项目。请选择现有项目，或输入项目键以创建本地草稿。")).foregroundStyle(.orange).accessibilityIdentifier("uma.threados.no-project") }
        }
        Section(title("Paste a ThreadOS receipt", "粘贴 ThreadOS 回执")) { TextEditor(text: Binding(get: { form.receipt }, set: form.receiveReceipt)).frame(minHeight: 90).accessibilityIdentifier("uma.threados.receipt"); Text(form.receiptStatus(catalog: catalog, language: language)).foregroundStyle(.secondary).accessibilityIdentifier("uma.threados.receipt-status") }
    }.padding().accessibilityIdentifier("uma.threados.settings") }
    @ViewBuilder private var settingsFields: some View {
        TextField(title("Request ID", "请求 ID"), text: stringBinding(\.id)).accessibilityIdentifier("uma.threados.request-id")
        LabeledContent(title("Revision", "修订版本"), value: "\(form.draft.revision)").accessibilityIdentifier("uma.threados.revision")
        Picker(title("Preset", "预设"), selection: presetBinding) { ForEach(["astra-economy", "astra-balanced", "astra-speed", "astra-deep", "custom"], id: \.self) { Text($0).tag($0) } }.accessibilityIdentifier("uma.threados.preset")
        Picker(title("Service tier", "服务层级"), selection: tierBinding) { Text(title("Standard", "标准")).tag("standard"); Text(title("Priority", "优先")).tag("priority") }.accessibilityIdentifier("uma.threados.service-tier")
        Text(title("Catalog revision: \(catalog?.revision ?? "unavailable")", "目录版本：\(catalog?.revision ?? "不可用")")).foregroundStyle(.secondary).accessibilityIdentifier("uma.threados.catalog-revision")
        roleFields
        Stepper(title("Coding workers: \(form.draft.codingWorkers)", "编码工作者：\(form.draft.codingWorkers)"), value: intBinding(\.codingWorkers), in: 1...4).accessibilityIdentifier("uma.threados.coding-workers")
        Stepper(title("Review workers: \(form.draft.reviewWorkers)", "审查工作者：\(form.draft.reviewWorkers)"), value: intBinding(\.reviewWorkers), in: 1...4).accessibilityIdentifier("uma.threados.review-workers")
        Button(title("Copy settings request", "复制设置请求"), action: { form.copy(to: SystemThreadOSSettingsClipboard(), language: language) }).accessibilityIdentifier("uma.threados.copy")
        if !form.message.isEmpty { Text(form.message).accessibilityIdentifier("uma.threados.copy-status") }
        if form.copiedRevision == form.draft.revision { Text(title("Copy confirmation is for revision \(form.draft.revision) only; any edit invalidates it.", "复制确认仅适用于修订版本 \(form.draft.revision)；任何编辑都会使其失效。")).foregroundStyle(.secondary).accessibilityIdentifier("uma.threados.copy-confirmation") }
    }
    @ViewBuilder private var roleFields: some View {
        if let catalog, let roles = try? form.rolePresentations(catalog: catalog) {
            ForEach(roles) { role in
                LabeledContent(role.id, value: role.summary(language: language)).accessibilityIdentifier(role.summaryIdentifier)
                if role.isEditable {
                    Picker(title("\(role.id) model", "\(role.id) 模型"), selection: customModelBinding(role.role)) {
                        ForEach(role.modelOptions, id: \.self) { model in
                            Text(model == "coder_auto" ? title("Automatic (coder_auto)", "自动（coder_auto）") : model).tag(model)
                        }
                    }.accessibilityIdentifier(role.modelIdentifier)
                    Picker(title("\(role.id) reasoning effort", "\(role.id) 推理强度"), selection: customEffortBinding(role.role)) {
                        ForEach(role.effortOptions, id: \.self) { Text($0).tag($0) }
                    }.accessibilityIdentifier(role.effortIdentifier)
                }
            }
        } else {
            Text(title("Role configuration is unavailable: the local catalog or selection is invalid.", "角色配置不可用：本地目录或选择无效。")).foregroundStyle(.orange).accessibilityIdentifier("uma.threados.roles-unavailable")
        }
    }
    private var catalog: ThreadOSModelCatalog? { try? ThreadOSSettingsCodec.loadCatalog() }
    private var presetBinding: Binding<String> { Binding(get: { form.draft.preset }, set: { form.selectPreset($0, catalog: catalog, language: language) }) }
    private func customModelBinding(_ role: ThreadOSRole) -> Binding<String> { Binding(get: { form.draft.customRoles[role]?.model ?? "" }, set: { form.selectCustomModel($0, role: role, catalog: catalog, language: language) }) }
    private func customEffortBinding(_ role: ThreadOSRole) -> Binding<String> { Binding(get: { form.draft.customRoles[role]?.reasoningEffort ?? "" }, set: { form.selectCustomEffort($0, role: role, catalog: catalog, language: language) }) }
    private var tierBinding: Binding<String> { Binding(get: { form.draft.tier }, set: { value in form.semanticEdit({ $0.tier = value }, language: language) }) }
    private func stringBinding(_ keyPath: WritableKeyPath<ThreadOSSettingsDraft, String>) -> Binding<String> { Binding(get: { form.draft[keyPath: keyPath] }, set: { value in form.semanticEdit({ $0[keyPath: keyPath] = value }, language: language) }) }
    private func intBinding(_ keyPath: WritableKeyPath<ThreadOSSettingsDraft, Int>) -> Binding<Int> { Binding(get: { form.draft[keyPath: keyPath] }, set: { value in form.semanticEdit({ $0[keyPath: keyPath] = value }, language: language) }) }
    private func title(_ english: String, _ chinese: String) -> String { localized(language, english, chinese) }
}
