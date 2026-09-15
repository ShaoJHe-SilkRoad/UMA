import SwiftUI
import AppKit
import Combine

@MainActor public protocol ThreadOSSettingsClipboard { func write(_ string: String) -> Bool }

@MainActor public protocol ThreadOSSettingsPasteboard: AnyObject {
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: ThreadOSSettingsPasteboard {}

@MainActor public struct SystemThreadOSSettingsClipboard: ThreadOSSettingsClipboard {
    private let board: any ThreadOSSettingsPasteboard

    public init(board: any ThreadOSSettingsPasteboard = NSPasteboard.general) { self.board = board }

    public func write(_ string: String) -> Bool {
        let previous = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        board.clearContents()
        guard board.setString(string, forType: .string) else {
            board.clearContents()
            if !previous.isEmpty {
                _ = board.writeObjects(previous)
            }
            return false
        }
        return true
    }
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

/// Editable, local preference fields for the application-owned historical
/// attribution binding. Saving validates the currently selected executables
/// and their hashes; it neither launches the exporter nor promotes a future
/// read into native or provider proof.
@MainActor public final class ThreadOSAttributionBindingFormState: ObservableObject {
    @Published public var interpreterPath = ""
    @Published public var helperPath = ""
    @Published public var runtimeRootPath = ""
    @Published public var journalPath = ""
    @Published public var projectKey = ""
    @Published public var projectRootDigest = ""
    @Published public var interpreterSHA256 = ""
    @Published public var helperSHA256 = ""
    @Published public var journalID = ""
    @Published public private(set) var message = ""
    @Published public private(set) var isSaved = false
    private let preferences: ApplicationPreferences

    public init(preferences: ApplicationPreferences = .production) {
        self.preferences = preferences
        guard let data = preferences.value(for: ThreadOSHistoricalAttributionPreferences.binding),
              let binding = try? JSONDecoder().decode(ThreadOSHistoricalAttributionBinding.self, from: data)
        else { return }
        interpreterPath = binding.interpreterPath; helperPath = binding.helperPath
        runtimeRootPath = binding.runtimeRootPath; journalPath = binding.journalPath
        projectKey = binding.projectKey; projectRootDigest = binding.projectRootDigest
        interpreterSHA256 = binding.interpreterSHA256; helperSHA256 = binding.helperSHA256
        journalID = binding.journalID ?? ""
        isSaved = binding.launchIfVerified() != nil
    }

    public func save(language: AppLanguage) {
        let binding = ThreadOSHistoricalAttributionBinding(
            interpreterPath: interpreterPath, helperPath: helperPath,
            runtimeRootPath: runtimeRootPath, journalPath: journalPath,
            projectKey: projectKey, projectRootDigest: projectRootDigest,
            interpreterSHA256: interpreterSHA256, helperSHA256: helperSHA256,
            journalID: journalID.isEmpty ? nil : journalID
        )
        guard binding.launchIfVerified() != nil else {
            message = localized(language, "Binding was not saved: paths, project scope, or current executable hashes are invalid. Any prior saved binding was left unchanged; no exporter was started.", "未保存绑定：路径、项目范围或当前可执行文件哈希无效。任何先前保存的绑定保持不变；未启动导出器。")
            return
        }
        ThreadOSHistoricalAttributionPreferences.save(binding, to: preferences)
        isSaved = true
        message = localized(language, "Trusted local binding saved. It can be read only by the normal application runtime; it does not prove coverage, native execution, or a model.", "已保存受信任的本地绑定。它只能由正常应用运行时读取；不证明覆盖范围、原生执行或模型。")
    }

    public func clear(language: AppLanguage) {
        ThreadOSHistoricalAttributionPreferences.save(nil, to: preferences)
        isSaved = false
        message = localized(language, "Trusted local binding cleared. Historical attribution will remain unavailable until a new verified local binding is saved.", "已清除受信任的本地绑定。在保存新的已验证本地绑定之前，历史归因将保持不可用。")
    }
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

/// Pure, local-only analytics presentation rules. Keeping these rules outside
/// the SwiftUI body makes their partial-coverage and unknown-value behavior
/// directly testable without launching a helper or rendering a window.
enum ThreadOSAnalyticsPresentation {
    struct Totals: Equatable {
        let input: Int64
        let cached: Int64
        let output: Int64
        let total: Int64
        let usd: Double
        let unknownPrice: Int64
        let knownRows: Int
        let pricedRows: Int
    }

    static func filteredRows(_ rows: [ThreadOSUsageAnalytics.Row], project: String, task: String, role: String, wave: String, model: String) -> [ThreadOSUsageAnalytics.Row] {
        rows.filter { row in
            contains(row.projectKey, project)
                && contains(row.taskID, task)
                && contains(row.localRole, role)
                && contains(row.waveID ?? "", wave)
                && contains(row.model ?? "UNKNOWN", model)
        }
    }

    static func totals(_ rows: [ThreadOSUsageAnalytics.Row]) -> Totals {
        rows.reduce(.init(input: 0, cached: 0, output: 0, total: 0, usd: 0, unknownPrice: 0, knownRows: 0, pricedRows: 0)) { result, row in
            guard let input = row.inputTokens, let cached = row.cachedInputTokens, let output = row.outputTokens, let total = row.totalTokens else { return result }
            return .init(input: result.input + input, cached: result.cached + cached, output: result.output + output, total: result.total + total, usd: result.usd + (row.apiEquivalentUSD ?? 0), unknownPrice: result.unknownPrice + (row.isPriceKnown ? 0 : total), knownRows: result.knownRows + 1, pricedRows: result.pricedRows + (row.isPriceKnown ? 1 : 0))
        }
    }

    private static func contains(_ value: String, _ filter: String) -> Bool {
        filter.isEmpty || value.localizedCaseInsensitiveContains(filter)
    }
}

public struct ThreadOSSettingsView: View {
    public let language: AppLanguage
    let analytics: ThreadOSUsageAnalytics?
    let basicUsage: BasicSharedUsagePresentation?
    let showCodexDetail: (() -> Void)?
    private let preferences: ApplicationPreferences
    private let layoutProbe: ThreadOSSchemeBLayoutProbe?
    private let footerStatusOverride: String?
    private let defaultExpandedWorkerGroups: Set<FactoriumV2Role>
    @StateObject private var form: ThreadOSSettingsFormState
    @StateObject private var attributionBinding: ThreadOSAttributionBindingFormState
    @StateObject private var factoriumV2: FactoriumV2FormState
    @State private var projectFilter = ""
    @State private var taskFilter = ""
    @State private var roleFilter = ""
    @State private var waveFilter = ""
    @State private var modelFilter = ""
    @State private var confirmLegacyFourWorkerConversion = false
    @State private var expandedWorkerGroups: Set<FactoriumV2Role> = []
    public init(
        language: AppLanguage,
        analytics: ThreadOSUsageAnalytics? = nil,
        basicUsage: BasicSharedUsagePresentation? = nil,
        showCodexDetail: (() -> Void)? = nil,
        preferences: ApplicationPreferences = .production,
        initiallyExpandedWorkerGroups: Set<FactoriumV2Role> = [.coder],
        layoutProbe: ThreadOSSchemeBLayoutProbe? = nil,
        footerStatusOverride: String? = nil
    ) {
        self.language = language; self.analytics = analytics; self.basicUsage = basicUsage; self.showCodexDetail = showCodexDetail; self.preferences = preferences; self.layoutProbe = layoutProbe; self.footerStatusOverride = footerStatusOverride; self.defaultExpandedWorkerGroups = initiallyExpandedWorkerGroups
        _form = StateObject(wrappedValue: ThreadOSSettingsFormState(preferences: preferences))
        _attributionBinding = StateObject(wrappedValue: ThreadOSAttributionBindingFormState(preferences: preferences))
        _factoriumV2 = StateObject(wrappedValue: FactoriumV2FormState(preferences: preferences))
        _expandedWorkerGroups = State(initialValue: initiallyExpandedWorkerGroups)
    }
    public var body: some View {
        VStack(spacing: 0) {
            factoriumV2Header
                .frame(maxWidth: 1_080, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 22)
                .padding(.vertical, 6)
                .background(ThreadOSSchemeBGeometryReporter(identifier: "project-draft-header", probe: layoutProbe))
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) { factoriumV2Content }
                    .frame(maxWidth: 1_080, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 6)
                    .background(ThreadOSSchemeBGeometryReporter(identifier: "scroll.document", probe: layoutProbe))
            }
            .background(ThreadOSSchemeBGeometryReporter(identifier: "scroll.viewport", probe: layoutProbe))
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(name: "uma.threados.scheme-b")
        .background(Color(nsColor: .windowBackgroundColor))
        .background(ThreadOSSchemeBGeometryReporter(identifier: "root", probe: layoutProbe))
        .onAppear { restoreWorkerExpansion() }
        .onChange(of: factoriumV2.selectedProject) { _, _ in restoreWorkerExpansion() }
    }
    func showCodexDetailForTesting() { showCodexDetail?() }
    private var footer: some View {
        HStack(spacing: 12) {
            Text(footerStatus)
                .font(.caption)
                .foregroundStyle(factoriumV2.message.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("uma.threados.v2.footer-status")
                .background(ThreadOSSchemeBGeometryReporter(identifier: "footer.status", probe: layoutProbe))
            Button(title("Generate and Copy for Leader", "生成并复制给 Leader"), action: copyFactoriumV2Request)
                .buttonStyle(.borderedProminent)
                .disabled(!factoriumV2.draft.isLocallyValid)
                .accessibilityIdentifier("uma.threados.v2.generate-copy")
                .frame(minHeight: 32)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(.bar)
        .background(ThreadOSSchemeBGeometryReporter(identifier: "footer.generate-copy", probe: layoutProbe))
    }
    private var footerStatus: String {
        footerStatusOverride ?? (factoriumV2.message.isEmpty ? factoriumV2.roleStatus(language: language) : factoriumV2.message)
    }
    @ViewBuilder private var factoriumV2Header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { Text(title("Role settings", "角色配置")).font(.headline); projectPicker }
            VStack(alignment: .leading, spacing: 2) { Text(title("Role settings", "角色配置")).font(.headline); projectPicker }
        }
        Text(title("Local draft; manual Leader transfer; native status UNKNOWN.", "本地草稿；手动交给 Leader；原生状态未知。"))
            .foregroundStyle(.secondary).font(.caption)
            .accessibilityIdentifier("uma.threados.v2.provenance")
    }
    @ViewBuilder private func settingsSection<Content: View>(_ heading: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var factoriumV2Content: some View {
        DisclosureGroup(title("New project", "新项目")) {
            HStack {
                TextField(title("New project key", "新项目键"), text: $factoriumV2.newProject)
                    .accessibilityIdentifier("uma.threados.v2.new-project")
                Button(title("Use project", "使用项目"), action: factoriumV2.createProject)
                    .disabled(!ThreadOSSettingsDraft.isToken(factoriumV2.newProject))
                    .accessibilityIdentifier("uma.threados.v2.use-project")
            }
        }
        .controlSize(.small)
        if let legacy = factoriumV2.selectedLegacyDraft {
            settingsSection(title("V1 conversion", "V1 转换")) {
                Text(FactoriumV2SettingsDraft.conversionPreview(language: language)).foregroundStyle(.secondary)
                if legacy.codingWorkers == 4 || legacy.reviewWorkers == 4 {
                    Toggle(title("I confirm that four legacy workers become three V2 slots", "我确认四个旧工作者将变为三个 V2 槽位"), isOn: $confirmLegacyFourWorkerConversion)
                        .accessibilityIdentifier("uma.threados.v2.convert-four-confirmation")
                }
                Button(title("Create separate V2 request", "创建独立的 V2 请求"), action: {
                    do { try factoriumV2.convert(legacy: legacy, confirmedFourWorkerConversion: confirmLegacyFourWorkerConversion) }
                    catch { factoriumV2.reportConversionError(language: language) }
                })
                .disabled((legacy.codingWorkers == 4 || legacy.reviewWorkers == 4) && !confirmLegacyFourWorkerConversion)
                .accessibilityIdentifier("uma.threados.v2.convert")
            }
        } else if factoriumV2.isShowingV2Draft {
        Text(title("This page generates configuration requests; it does not control Codex execution speed.", "此页面生成配置请求，不控制 Codex 的运行速度。"))
            .foregroundStyle(.secondary).font(.caption)
            .accessibilityIdentifier("uma.threados.v2.speed-boundary")
            RoleGridLayout {
                ForEach(FactoriumV2Role.allCases, id: \.self) { role in roleCard(role) }
            }
            .accessibilityIdentifier("uma.threados.v2.role-grid")
            workerCapacityNote
            workerGroups
            if let basicUsage {
                settingsSection(title("Codex account usage", "Codex 账户用量")) {
                    compactAccountStrip(basicUsage)
                    if let showCodexDetail {
                        Button(title("Open Codex details", "打开 Codex 详情"), action: showCodexDetail)
                            .accessibilityIdentifier("uma.threados.v2.codex-details")
                    }
                }
                .accessibilityIdentifier("uma.threados.v2.codex-basic-usage")
            }
            DisclosureGroup(title("Advanced details", "高级详情")) {
                LabeledContent(title("Request ID", "请求 ID"), value: factoriumV2.draft.id)
                LabeledContent(title("Revision", "修订版本"), value: "\(factoriumV2.draft.revision)")
                LabeledContent(title("Catalog revision", "目录版本"), value: FactoriumV2SettingsDraft.catalogRevision)
                Text(title("Raw acknowledgement preview", "原始回执预览"))
                TextEditor(text: $factoriumV2.rawAcknowledgement)
                    .frame(minHeight: 72)
                    .accessibilityIdentifier("uma.threados.v2.raw-ack")
                Button(title("Validate local receipt", "验证本地回执"), action: { factoriumV2.receiveReceipt(language: language) })
                    .accessibilityIdentifier("uma.threados.v2.validate-receipt")
                if factoriumV2.receiptInputIsInvalid { Text(title("Receipt does not match this local draft.", "回执与此本地草稿不匹配。")) .foregroundStyle(.orange) }
                Text(title("Usage and historical binding: Coming soon.", "用量和历史绑定：即将推出。"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("uma.threados.v2.coming-soon")
            }
            .background(ThreadOSSchemeBGeometryReporter(identifier: "advanced.details", probe: layoutProbe))
        } else {
            Text(title("Choose or create a project to edit local settings.", "请选择或新建项目后编辑本地设置。"))
                .foregroundStyle(.orange)
        }
    }
    @ViewBuilder private func compactAccountStrip(_ usage: BasicSharedUsagePresentation) -> some View {
        let windows = BasicSharedUsagePresentation.accountStripWindows(from: usage.windows)
        let metrics = usage.metrics.filter { $0.id == "week" || $0.id == "total" }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(windows) { window in accountStripQuota(window, source: usage.providerSource) }
                ForEach(metrics) { metric in accountStripFact(metric.value, metric.label, title("Account · not project", "账户 · 非项目")) }
                if let estimate = usage.apiEquivalentEstimate {
                    accountStripFact(estimate.sevenDayUSD.formatted(.currency(code: "USD")), title("Local API eq · 7D", "本地 API 等效 · 7天"), coverageText(estimate.coveragePercent), accessibility: coverageAccessibilityText(estimate.coveragePercent, value: estimate.sevenDayUSD.formatted(.currency(code: "USD"))))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(windows) { window in accountStripQuota(window, source: usage.providerSource) }
                ForEach(metrics) { metric in accountStripFact(metric.value, metric.label, title("Account · not project", "账户 · 非项目")) }
                if let estimate = usage.apiEquivalentEstimate {
                    accountStripFact(estimate.sevenDayUSD.formatted(.currency(code: "USD")), title("Local API eq · 7D", "本地 API 等效 · 7天"), coverageText(estimate.coveragePercent), accessibility: coverageAccessibilityText(estimate.coveragePercent, value: estimate.sevenDayUSD.formatted(.currency(code: "USD"))))
                }
            }
        }
        .accessibilityIdentifier("uma.threados.v2.codex-account-strip")
    }
    private func accountStripQuota(_ window: BasicSharedUsagePresentation.Window, source: UsageSourceStatus?) -> some View {
        let state = BasicSharedUsagePresentation.accountStripQuotaState(window, source: source)
        return HStack(spacing: 7) {
            ZStack {
                Circle().stroke(.primary.opacity(0.12), lineWidth: 5)
                if case let .finite(percent) = state {
                    Circle().trim(from: 0, to: CGFloat(percent) / 100).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                Text(accountStripRemainingText(state)).font(.caption.weight(.bold)).monospacedDigit()
            }.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title).font(.caption.weight(.medium)).lineLimit(1)
                Text(accountStripResetText(state, original: window.resetText)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.quaternary, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accountStripAccessibilityText(state, title: window.title, reset: window.resetText))
    }
    private func accountStripFact(_ value: String, _ label: String, _ detail: String, accessibility: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption.weight(.medium)).lineLimit(1)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.quaternary, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility ?? "\(value), \(label), \(detail)")
    }
    private func coverageText(_ coverage: Int) -> String {
        localized(language, "Priced coverage \(coverage)%", "计价覆盖 \(coverage)%")
    }
    private func coverageAccessibilityText(_ coverage: Int, value: String) -> String {
        localized(language, "\(value), Local API equivalent, 7D. Lifetime local-ledger priced-token coverage \(coverage)%. Priced tokens divided by observed ledger tokens; not account or 7D coverage.", "\(value)，本地 API 等效，7天。累计本地账本计价令牌覆盖 \(coverage)%；计价令牌除以已观察到账本令牌，不是账户或 7 天覆盖。")
    }
    private func accountStripRemainingText(_ state: BasicSharedUsagePresentation.AccountStripQuotaState) -> String {
        switch state { case let .finite(value): "\(value)%"; case .unlimited: "∞"; case let .stale(value), let .estimated(value): value.map { "\($0)%" } ?? "—"; case .unavailable: "—" }
    }
    private func accountStripResetText(_ state: BasicSharedUsagePresentation.AccountStripQuotaState, original: String) -> String {
        switch state { case .finite, .unlimited: original; case .stale: title("Stale retained data", "已过期保留数据"); case .estimated: title("Estimated quota", "估算配额"); case .unavailable: title("Unavailable", "不可用") }
    }
    private func accountStripAccessibilityText(_ state: BasicSharedUsagePresentation.AccountStripQuotaState, title: String, reset: String) -> String {
        switch state { case .finite, .unlimited: "\(title), \(accountStripRemainingText(state)), \(reset)"; case .stale: "\(title), \(accountStripRemainingText(state)), \(localized(language, "stale retained account quota", "已过期保留账户配额"))"; case .estimated: "\(title), \(accountStripRemainingText(state)), \(localized(language, "estimated account quota", "估算账户配额"))"; case .unavailable: "\(title), \(localized(language, "account quota unavailable", "账户配额不可用"))" }
    }
    private var projectPicker: some View {
        Picker(title("Project", "项目"), selection: Binding(get: { factoriumV2.selectedProject }, set: { factoriumV2.select(project: $0) })) {
            Text(title("No project selected", "未选择项目")).tag("")
            ForEach(factoriumV2.projects, id: \.self) { Text($0).tag($0) }
        }
        .accessibilityIdentifier("uma.threados.v2.project-selector")
    }
    @ViewBuilder private func roleCard(_ role: FactoriumV2Role) -> some View {
        let setting = factoriumV2.draft.roles[role] ?? FactoriumV2SettingsDraft.defaultRoles[role]!
        ThreadOSSchemeBCard(identifier: "role.\(role.rawValue).card", layoutProbe: layoutProbe) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(roleDisplayName(role)).font(.headline)
                        if let subtitle = roleSubtitle(role) { Text(subtitle).font(.caption2).foregroundStyle(.secondary) }
                    }
                } icon: {
                    Image(systemName: roleSymbol(role)).foregroundStyle(.purple)
                }
                .background(ThreadOSSchemeBGeometryReporter(identifier: "role.\(role.rawValue).header", probe: layoutProbe))
                .frame(height: 34, alignment: .topLeading)
                if role == .leader {
                    Text(title("Current Leader is retained by this local draft.", "当前 Leader 由此本地草稿保留。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(title("Preserve current Leader", "保留当前 Leader"), isOn: Binding(get: { setting.preserve }, set: { value in factoriumV2.edit { $0.roles[role]?.preserve = value } }))
                        .accessibilityIdentifier("uma.threados.v2.leader.preserve")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    selectionFields(role: role, selection: setting.selection)
                }
            }
        }
        .accessibilityIdentifier("uma.threados.v2.role.\(role.rawValue).card")
    }
    @ViewBuilder private func selectionFields(role: FactoriumV2Role, selection: FactoriumV2Selection) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) { roleSelectionPickers(role: role, selection: selection) }
            VStack(alignment: .leading, spacing: 8) { roleSelectionPickers(role: role, selection: selection) }
        }
    }
    @ViewBuilder private func roleSelectionPickers(role: FactoriumV2Role, selection: FactoriumV2Selection) -> some View {
        Picker("", selection: selectionBinding(role, \.model)) { ForEach(FactoriumV2SettingsDraft.availableModels(), id: \.self) { model in Text(model == "gpt-6-astra" ? "Astra" : "Terra").tag(model) } }
            .labelsHidden().frame(width: 118)
            .accessibilityLabel(title("Model for \(role.title)", "\(role.title) 的模型"))
            .accessibilityIdentifier("uma.threados.v2.role.\(role.rawValue).model")
            .background(ThreadOSSchemeBGeometryReporter(identifier: "role.\(role.rawValue).model", probe: layoutProbe))
        Picker("", selection: selectionBinding(role, \.effort)) { ForEach(FactoriumV2SettingsDraft.availableEfforts(model: selection.model, leader: role == .leader), id: \.self) { effort in Text(effortLabel(effort)).tag(effort) } }
            .labelsHidden().frame(width: 88)
            .accessibilityLabel(title("Thinking for \(role.title)", "\(role.title) 的推理"))
            .accessibilityIdentifier("uma.threados.v2.role.\(role.rawValue).effort")
            .background(ThreadOSSchemeBGeometryReporter(identifier: "role.\(role.rawValue).effort", probe: layoutProbe))
    }
    @ViewBuilder private func workerSlots(role: FactoriumV2Role) -> some View {
        DisclosureGroup(isExpanded: workerExpansionBinding(role)) {
            ThreadOSSchemeBChildPanel(identifier: "role.\(role.rawValue).workers", layoutProbe: layoutProbe) {
                VStack(alignment: .leading, spacing: 7) {
                workerColumnHeadings
                ForEach(Array(factoriumV2.draft.workers(for: role).enumerated()), id: \.offset) { index, slot in
                    workerRow(role: role, index: index, slot: slot)
                }
                }
            }
        } label: {
            HStack {
                Text(title("\(roleDisplayName(role)) children", "\(roleDisplayName(role)) 子工作者")).font(.subheadline.weight(.semibold))
                Spacer()
                Text(workerSummary(for: role)).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("uma.threados.v2.\(role.rawValue).workers")
    }
    private var workerCapacityNote: some View {
        Text(title("Three slots = configuration capacity, not live agents.", "三个槽位表示配置容量，不是实时代理数量。"))
            .foregroundStyle(.secondary).font(.caption)
            .help(title("Three stable slots are configuration capacity, not live-agent count. Disabled slots retain this saved draft and are not scheduled.", "三个稳定槽位表示配置容量，不是实时代理数量。已停用的槽位会保留此草稿，且不会被调度。"))
    }
    @ViewBuilder private var workerGroups: some View {
        WorkerGroupsLayout() { workerSlots(role: .coder); workerSlots(role: .reviewer) }
        .accessibilityIdentifier("uma.threados.v2.worker-groups")
    }
    private var workerColumnHeadings: some View {
        HStack(spacing: 8) {
            Text(title("Slot", "槽位")).frame(width: 28, alignment: .leading)
            Text(title("Enabled", "启用")).frame(width: 32, alignment: .leading)
            Text(title("Mode", "模式")).frame(width: 92, alignment: .leading)
            Text(title("Model · Thinking", "模型 · 推理")).frame(minWidth: 180, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
    }
    @ViewBuilder private func workerRow(role: FactoriumV2Role, index: Int, slot: FactoriumV2WorkerSlot) -> some View {
        let resolved = factoriumV2.draft.resolvedSlot(slot, parent: role)
        let workerName = title("\(roleDisplayName(role)) worker \(index + 1)", "\(roleDisplayName(role)) 工作者 \(index + 1)")
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text("\(index + 1)").frame(width: 28, alignment: .leading)
                Toggle("", isOn: slotEnabledBinding(role, index)).labelsHidden().frame(width: 32)
                    .accessibilityLabel(title("\(workerName) enabled", "\(workerName) 已启用"))
                    .accessibilityIdentifier("uma.threados.v2.\(role.rawValue).worker.\(index + 1).enabled")
                Picker("", selection: slotInheritanceBinding(role, index)) {
                    Text(title("Inherit", "继承")).tag(true)
                    Text(title("Custom", "自定义")).tag(false)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 92).disabled(!slot.enabled)
                .accessibilityLabel(title("\(workerName) configuration", "\(workerName) 配置"))
                .accessibilityIdentifier("uma.threados.v2.\(role.rawValue).worker.\(index + 1).inherit")
                if slot.inherits {
                    Text(title("Inherited: \(selectionSummary(resolved))", "继承：\(selectionSummary(resolved))"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(minWidth: 180, alignment: .leading)
                } else {
                    slotSelectionFields(role: role, index: index, selection: slot.selection).disabled(!slot.enabled)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(workerName).font(.subheadline); Spacer(); Toggle("", isOn: slotEnabledBinding(role, index)).labelsHidden().accessibilityLabel(title("\(workerName) enabled", "\(workerName) 已启用")) }
                Picker(title("\(workerName) configuration", "\(workerName) 配置"), selection: slotInheritanceBinding(role, index)) { Text(title("Inherit", "继承")).tag(true); Text(title("Custom", "自定义")).tag(false) }.pickerStyle(.segmented).disabled(!slot.enabled)
                if slot.inherits { Text(title("Inherited: \(selectionSummary(resolved))", "继承：\(selectionSummary(resolved))")).font(.caption).foregroundStyle(.secondary) }
                else { slotSelectionFields(role: role, index: index, selection: slot.selection).disabled(!slot.enabled) }
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 34)
        .opacity(slot.enabled ? 1 : 0.62)
        .background(ThreadOSSchemeBGeometryReporter(identifier: "role.\(role.rawValue).worker.\(index + 1)", probe: layoutProbe))
    }
    @ViewBuilder private func slotSelectionFields(role: FactoriumV2Role, index: Int, selection: FactoriumV2Selection) -> some View {
        let workerName = title("\(roleDisplayName(role)) worker \(index + 1)", "\(roleDisplayName(role)) 工作者 \(index + 1)")
        Picker("", selection: slotSelectionBinding(role, index, \.model)) { ForEach(FactoriumV2SettingsDraft.availableModels(), id: \.self) { model in Text(model == "gpt-6-astra" ? "Astra" : "Terra").tag(model) } }
            .labelsHidden().frame(width: 104)
            .accessibilityLabel(title("Model for \(workerName)", "\(workerName) 的模型"))
            .accessibilityIdentifier("uma.threados.v2.\(role.rawValue).worker.\(index + 1).model")
        Picker("", selection: slotSelectionBinding(role, index, \.effort)) { ForEach(FactoriumV2SettingsDraft.availableEfforts(model: selection.model, leader: false), id: \.self) { effort in Text(effortLabel(effort)).tag(effort) } }
            .labelsHidden().frame(width: 76)
            .accessibilityLabel(title("Thinking for \(workerName)", "\(workerName) 的推理"))
            .accessibilityIdentifier("uma.threados.v2.\(role.rawValue).worker.\(index + 1).effort")
    }
    private func workerSummary(for role: FactoriumV2Role) -> String {
        let slots = factoriumV2.draft.workers(for: role)
        let enabled = slots.filter(\.enabled).count
        let inherited = slots.filter(\.inherits).count
        let custom = slots.count - inherited
        let mode: String
        if inherited == slots.count { mode = title("inherited", "继承") }
        else if custom == slots.count { mode = title("custom", "自定义") }
        else { mode = title("mixed", "混合") }
        return title("\(enabled)/3 slots enabled · \(mode)", "已启用 \(enabled)/3 个槽位 · \(mode)")
    }
    private func workerExpansionBinding(_ role: FactoriumV2Role) -> Binding<Bool> {
        Binding(get: { expandedWorkerGroups.contains(role) }, set: { isExpanded in
            if isExpanded { expandedWorkerGroups.insert(role) }
            else { expandedWorkerGroups.remove(role) }
            ThreadOSSettingsPreferences.saveFactoriumV2ExpandedGroups(expandedWorkerGroups, project: factoriumV2.selectedProject, to: preferences)
        })
    }
    private func restoreWorkerExpansion() {
        expandedWorkerGroups = ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: factoriumV2.selectedProject, from: preferences) ?? defaultExpandedWorkerGroups
    }
    private func roleDisplayName(_ role: FactoriumV2Role) -> String {
        role == .repair ? title("Repair", "修复 Repair") : role.title
    }
    private func roleSubtitle(_ role: FactoriumV2Role) -> String? {
        switch role {
        case .qa: title("Quality synthesis", "质量综合")
        case .repair: title("Fixes issues found during review", "处理检查发现的问题")
        case .reviewer: title("Code inspection", "代码审查")
        default: nil
        }
    }
    private func roleSymbol(_ role: FactoriumV2Role) -> String {
        switch role {
        case .leader: "crown.fill"
        case .qa: "checkmark.shield.fill"
        case .coder: "chevron.left.forwardslash.chevron.right"
        case .repair: "wrench.and.screwdriver.fill"
        case .reviewer: "eye.fill"
        }
    }
    private func selectionSummary(_ selection: FactoriumV2Selection) -> String {
        let model = selection.model == "gpt-6-astra" ? "Astra" : "Terra"
        return "\(model) · \(effortLabel(selection.effort))"
    }
    private func selectionBinding(_ role: FactoriumV2Role, _ keyPath: WritableKeyPath<FactoriumV2Selection, String>) -> Binding<String> {
        Binding(get: { factoriumV2.draft.roles[role]?.selection[keyPath: keyPath] ?? "" }, set: { value in
            if keyPath == \.model { factoriumV2.selectRoleModel(value, role: role) }
            else { factoriumV2.edit { $0.roles[role]?.selection[keyPath: keyPath] = value } }
        })
    }
    private func slotSelectionBinding(_ role: FactoriumV2Role, _ index: Int, _ keyPath: WritableKeyPath<FactoriumV2Selection, String>) -> Binding<String> {
        Binding(get: { factoriumV2.draft.workers(for: role)[index].selection[keyPath: keyPath] }, set: { value in
            if keyPath == \.model { factoriumV2.selectSlotModel(value, at: index, for: role) }
            else { factoriumV2.edit { var selection = $0.workers(for: role)[index].selection; selection[keyPath: keyPath] = value; $0.setSlotSelection(selection, at: index, for: role) } }
        })
    }
    private func slotEnabledBinding(_ role: FactoriumV2Role, _ index: Int) -> Binding<Bool> {
        Binding(get: { factoriumV2.draft.workers(for: role)[index].enabled }, set: { value in factoriumV2.edit { var slots = $0.workers(for: role); slots[index].enabled = value; $0.setWorkers(slots, for: role) } })
    }
    private func slotInheritanceBinding(_ role: FactoriumV2Role, _ index: Int) -> Binding<Bool> {
        Binding(get: { factoriumV2.draft.workers(for: role)[index].inherits }, set: { value in factoriumV2.edit { $0.setSlotInheritance(value, at: index, for: role) } })
    }
    private func copyFactoriumV2Request() {
        do {
            let request = try factoriumV2.generatedRequestForTransfer()
            factoriumV2.reportCopy(request, success: SystemThreadOSSettingsClipboard().write(request.text), language: language)
        } catch {
            factoriumV2.reportTransferGenerationError(error, language: language)
        }
    }
    private func effortLabel(_ effort: String) -> String {
        guard language == .simplifiedChinese else { return effort }
        return ["low": "低", "medium": "中", "high": "高", "xhigh": "很高", "max": "最大", "ultra": "超高"][effort] ?? effort
    }
    @ViewBuilder private var analyticsSection: some View {
        let value = analytics ?? .sourceGap()
        Text(analyticsStatus(value)).foregroundStyle(.secondary).accessibilityIdentifier("uma.threados.analytics-status")
        adaptiveFilterPair(
            TextField(title("Project filter", "项目筛选"), text: $projectFilter),
            TextField(title("Task filter", "任务筛选"), text: $taskFilter)
        )
        adaptiveFilterPair(
            TextField(title("Role filter", "角色筛选"), text: $roleFilter),
            TextField(title("Wave filter", "波次筛选"), text: $waveFilter)
        )
        TextField(title("Model filter", "模型筛选"), text: $modelFilter)
            .accessibilityIdentifier("uma.threados.analytics-model-filter")
        LabeledContent(title("Observed interval range", "观察到的区间范围"), value: observedRange(value.rows))
            .accessibilityIdentifier("uma.threados.analytics-window")
        LabeledContent(title("Observed model", "观察到的模型"), value: title("Only matched local intervals", "仅限匹配的本地区间"))
            .accessibilityIdentifier("uma.threados.analytics-model-gap")
        Text(title("API estimate, token breakdown, duration, and unknown-price totals appear only after a unique interval match. They are never inferred from this historical export.", "API 估算、令牌明细、持续时间和未知价格总计仅在唯一的区间匹配后显示；绝不从此历史导出中推断。"))
            .foregroundStyle(.secondary).accessibilityIdentifier("uma.threados.analytics-economics-gap")
        if let coverage = value.localLedgerCoverage {
            LabeledContent(title("Global local-ledger coverage (matched / known)", "全局本地台账覆盖（已匹配 / 已知）"), value: "\(coverage.matchedLocalTokens) / \(coverage.knownLocalTokens)")
                .accessibilityIdentifier("uma.threados.analytics-local-ledger-coverage")
            LabeledContent(title("Global local-ledger remainder (unassigned)", "全局本地台账余量（未分配）"), value: "\(coverage.localUnassignedTokens)")
                .accessibilityIdentifier("uma.threados.analytics-local-ledger-unassigned")
            Text(title("These global local-ledger totals ignore the filters below and are not account coverage.", "这些全局本地台账总计不受下方筛选影响，也不是账户覆盖范围。"))
                .foregroundStyle(.secondary).accessibilityIdentifier("uma.threados.analytics-local-ledger-provenance")
        }
        let rows = ThreadOSAnalyticsPresentation.filteredRows(value.rows, project: projectFilter, task: taskFilter, role: roleFilter, wave: waveFilter, model: modelFilter)
        let totals = ThreadOSAnalyticsPresentation.totals(rows)
        if totals.knownRows > 0 {
            LabeledContent(title("Known token subtotal (input / cached / output)", "已知令牌小计（输入 / 缓存 / 输出）"), value: "\(totals.input) / \(totals.cached) / \(totals.output)").accessibilityIdentifier("uma.threados.analytics-token-totals")
            LabeledContent(title("Filtered matched local tokens", "筛选后的已匹配本地令牌"), value: "\(totals.total)").accessibilityIdentifier("uma.threados.analytics-coverage")
            LabeledContent(title("Known API-equivalent / unknown-price tokens", "已知 API 等价估算 / 未知价格令牌"), value: totals.pricedRows > 0 ? "$\(String(format: "%.4f", totals.usd)) / \(totals.unknownPrice)" : "UNKNOWN_PRICE / \(totals.unknownPrice)").accessibilityIdentifier("uma.threados.analytics-price")
        }
        if rows.isEmpty {
            Text(title("No eligible historical attribution is available. Aggregate local usage remains separate.", "没有可用的合格历史归因；本地汇总使用量仍独立显示。"))
                .foregroundStyle(.secondary).accessibilityIdentifier("uma.threados.analytics-empty")
        } else {
            ForEach(rows) { row in
                VStack(alignment: .leading) {
                    LabeledContent("\(row.projectKey) / \(row.taskID)", value: row.waveID.map { "\(row.localRole) · \($0)" } ?? "\(row.localRole) · \(title("wave unavailable", "波次不可用"))")
                    Text("\(row.model ?? title("model unavailable", "模型不可用")) · \(tokenText(row)) · \(row.isPriceKnown ? String(format: "$%.4f", row.apiEquivalentUSD ?? 0) : "UNKNOWN_PRICE")")
                    Text(row.observedStart.flatMap { start in row.observedEnd.map { "\(start.formatted()) – \($0.formatted())" } } ?? title("duration unavailable", "持续时间不可用")).foregroundStyle(.secondary)
                }
                    .accessibilityIdentifier("uma.threados.analytics-row-\(row.id)")
            }
        }
        if value.unavailableCount > 0 {
            Text(title("Producer observations unavailable (separate from local-ledger remainder): \(value.unavailableCount)", "生产者观察不可用（与本地台账余量分开）：\(value.unavailableCount)"))
                .foregroundStyle(.orange).accessibilityIdentifier("uma.threados.analytics-unattributed")
        }
    }
    @ViewBuilder private func adaptiveFilterPair<First: View, Second: View>(_ first: First, _ second: Second) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                first.frame(minWidth: 220, maxWidth: .infinity)
                second.frame(minWidth: 220, maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                first.frame(maxWidth: .infinity)
                second.frame(maxWidth: .infinity)
            }
        }
    }
    @ViewBuilder private var attributionBindingFields: some View {
        Text(title("Optional local setup for an application-owned historical export reader. Save verifies the selected executable bytes but does not run the exporter.", "应用自有历史导出读取器的可选本地设置。保存会验证所选可执行文件字节，但不会运行导出器。"))
            .foregroundStyle(.secondary).accessibilityIdentifier("uma.threados.attribution-binding-provenance")
        DisclosureGroup(title("Advanced binding details", "高级绑定详情")) {
            TextField(title("Interpreter path", "解释器路径"), text: $attributionBinding.interpreterPath).accessibilityIdentifier("uma.threados.attribution-binding-interpreter")
            TextField(title("Helper path", "辅助程序路径"), text: $attributionBinding.helperPath).accessibilityIdentifier("uma.threados.attribution-binding-helper")
            TextField(title("Runtime root path", "运行时根路径"), text: $attributionBinding.runtimeRootPath).accessibilityIdentifier("uma.threados.attribution-binding-runtime-root")
            TextField(title("Journal path", "日志路径"), text: $attributionBinding.journalPath).accessibilityIdentifier("uma.threados.attribution-binding-journal")
            TextField(title("Project key", "项目键"), text: $attributionBinding.projectKey).accessibilityIdentifier("uma.threados.attribution-binding-project")
            TextField(title("Project-root SHA-256", "项目根 SHA-256"), text: $attributionBinding.projectRootDigest).accessibilityIdentifier("uma.threados.attribution-binding-project-digest")
            TextField(title("Interpreter SHA-256", "解释器 SHA-256"), text: $attributionBinding.interpreterSHA256).accessibilityIdentifier("uma.threados.attribution-binding-interpreter-digest")
            TextField(title("Helper SHA-256", "辅助程序 SHA-256"), text: $attributionBinding.helperSHA256).accessibilityIdentifier("uma.threados.attribution-binding-helper-digest")
            TextField(title("Journal ID (optional)", "日志 ID（可选）"), text: $attributionBinding.journalID).accessibilityIdentifier("uma.threados.attribution-binding-journal-id")
        }
        .accessibilityIdentifier("uma.threados.attribution-binding-advanced")
        HStack {
            Button(title("Save verified binding", "保存已验证绑定"), action: { attributionBinding.save(language: language) }).accessibilityIdentifier("uma.threados.attribution-binding-save")
            Button(title("Clear binding", "清除绑定"), action: { attributionBinding.clear(language: language) }).accessibilityIdentifier("uma.threados.attribution-binding-clear")
        }
        if !attributionBinding.message.isEmpty { Text(attributionBinding.message).accessibilityIdentifier("uma.threados.attribution-binding-status") }
    }
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
    private func analyticsStatus(_ value: ThreadOSUsageAnalytics) -> String {
        switch value.sourceStatus {
        case .available: return title("Historical attribution coverage is partial and local.", "历史归因覆盖不完整且仅限本地。")
        case .truncated: return title("Historical attribution export was truncated; coverage is unknown.", "历史归因导出已截断；覆盖范围未知。")
        case .sourceGap: return title("Historical attribution source is unavailable (SOURCE_GAP).", "历史归因来源不可用（SOURCE_GAP）。")
        case .unavailable: return title("Historical attribution is unavailable.", "历史归因不可用。")
        case .malformed: return title("Historical attribution export was rejected.", "历史归因导出已被拒绝。")
        }
    }
    private func tokenText(_ row: ThreadOSUsageAnalytics.Row) -> String {
        guard let input = row.inputTokens, let cached = row.cachedInputTokens, let output = row.outputTokens else { return title("tokens UNKNOWN", "令牌 UNKNOWN") }
        return "\(input) / \(cached) / \(output)"
    }
    private func observedRange(_ rows: [ThreadOSUsageAnalytics.Row]) -> String {
        let starts = rows.compactMap(\.observedStart)
        let ends = rows.compactMap(\.observedEnd)
        guard let start = starts.min(), let end = ends.max() else { return title("unavailable", "不可用") }
        return "\(start.formatted()) – \(end.formatted())"
    }
}
