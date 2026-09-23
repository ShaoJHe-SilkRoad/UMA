import Combine
import CryptoKit
import Foundation

public enum FactoriumV2Role: String, CaseIterable, Codable, Sendable {
    case leader, qa, coder, repair, reviewer

    public var title: String {
        switch self {
        case .leader: "Leader"
        case .qa: "QA"
        case .coder: "Coder"
        case .repair: "Repair"
        case .reviewer: "Reviewer"
        }
    }

    public var supportsWorkers: Bool { self == .coder || self == .reviewer }
}

public struct FactoriumV2Selection: Codable, Equatable, Sendable {
    public var model: String
    public var effort: String
    public var speed: String

    public init(model: String, effort: String, speed: String) {
        self.model = model
        self.effort = effort
        self.speed = speed
    }
}

public struct FactoriumV2RoleSetting: Codable, Equatable, Sendable {
    public var preserve: Bool
    public var selection: FactoriumV2Selection

    public init(preserve: Bool = false, selection: FactoriumV2Selection) {
        self.preserve = preserve
        self.selection = selection
    }
}

public struct FactoriumV2WorkerSlot: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var inherits: Bool
    public var selection: FactoriumV2Selection
    public var hasCustomSelection: Bool

    public init(enabled: Bool = true, inherits: Bool = true, selection: FactoriumV2Selection, hasCustomSelection: Bool = false) {
        self.enabled = enabled
        self.inherits = inherits
        self.selection = selection
        self.hasCustomSelection = hasCustomSelection
    }
}

public enum FactoriumV2SettingsError: Error, Equatable {
    case invalidProject, invalidID, invalidRevision, invalidRole, invalidWorkerSlots, invalidSelection
    case legacyWorkerConfirmationRequired
    case legacyFastConversionRequired
}

/// A copied local artifact. `artifactSHA256` identifies the completed bytes and is deliberately not embedded in them.
public struct FactoriumV2GeneratedRequest: Equatable, Sendable {
    public let settingsLine: String
    public let text: String
    public let artifactSHA256: String
}

/// Local V2 request data only. It is not a native role selection or task control state.
public struct FactoriumV2SettingsDraft: Codable, Equatable, Sendable {
    public static var catalogRevision: String { ThreadOSSettingsCodec.latestCatalogRevision }
    public static let apply = "next-wave"
    public static let preset = "custom"

    public var project: String
    public var catalogRevision: String
    public var id: String
    public var revision: Int
    public var roles: [FactoriumV2Role: FactoriumV2RoleSetting]
    public var coderWorkers: [FactoriumV2WorkerSlot]
    public var reviewerWorkers: [FactoriumV2WorkerSlot]

    public init(
        project: String = "",
        catalogRevision: String? = nil,
        id: String = "cfg-" + UUID().uuidString.lowercased(),
        revision: Int = 1,
        roles: [FactoriumV2Role: FactoriumV2RoleSetting] = Self.defaultRoles,
        coderWorkers: [FactoriumV2WorkerSlot]? = nil,
        reviewerWorkers: [FactoriumV2WorkerSlot]? = nil
    ) {
        self.project = project
        self.catalogRevision = catalogRevision ?? Self.catalogRevision
        self.id = id
        self.revision = revision
        self.roles = roles
        let coder = roles[.coder]?.selection ?? Self.defaultRoles[.coder]!.selection
        let reviewer = roles[.reviewer]?.selection ?? Self.defaultRoles[.reviewer]!.selection
        self.coderWorkers = coderWorkers ?? Array(repeating: .init(selection: coder), count: 3)
        self.reviewerWorkers = reviewerWorkers ?? Array(repeating: .init(selection: reviewer), count: 3)
    }

    public static let defaultRoles: [FactoriumV2Role: FactoriumV2RoleSetting] = [
        .leader: .init(preserve: true, selection: .init(model: "gpt-6-astra", effort: "high", speed: "standard")),
        .qa: .init(selection: .init(model: "gpt-6-sol", effort: "high", speed: "standard")),
        .coder: .init(selection: .init(model: "gpt-6-luna", effort: "medium", speed: "standard")),
        .repair: .init(selection: .init(model: "gpt-5.6-terra", effort: "medium", speed: "standard")),
        .reviewer: .init(selection: .init(model: "gpt-6-luna", effort: "medium", speed: "standard")),
    ]

    public var isValidProject: Bool { ThreadOSSettingsDraft.isToken(project) }
    public var isLocallyValid: Bool { (try? canonicalRequest()) != nil }

    public func workers(for role: FactoriumV2Role) -> [FactoriumV2WorkerSlot] {
        role == .coder ? coderWorkers : reviewerWorkers
    }

    public mutating func setWorkers(_ values: [FactoriumV2WorkerSlot], for role: FactoriumV2Role) {
        if role == .coder { coderWorkers = values }
        if role == .reviewer { reviewerWorkers = values }
    }

    public mutating func setSelection(_ selection: FactoriumV2Selection, for role: FactoriumV2Role) {
        guard var setting = roles[role] else { return }
        setting.selection = selection
        roles[role] = setting
    }

    public mutating func setSlotInheritance(_ inherits: Bool, at index: Int, for role: FactoriumV2Role) {
        guard role.supportsWorkers, workers(for: role).indices.contains(index), let parent = roles[role]?.selection else { return }
        var values = workers(for: role)
        if !inherits, values[index].inherits, !values[index].hasCustomSelection { values[index].selection = parent }
        values[index].inherits = inherits
        setWorkers(values, for: role)
    }

    public mutating func setSlotSelection(_ selection: FactoriumV2Selection, at index: Int, for role: FactoriumV2Role) {
        guard role.supportsWorkers, workers(for: role).indices.contains(index) else { return }
        var values = workers(for: role)
        values[index].selection = selection
        values[index].hasCustomSelection = true
        setWorkers(values, for: role)
    }

    public func resolvedSlot(_ slot: FactoriumV2WorkerSlot, parent: FactoriumV2Role) -> FactoriumV2Selection {
        slot.inherits ? (roles[parent]?.selection ?? slot.selection) : slot.selection
    }

    public func canonicalRequest() throws -> String {
        let catalog = try ThreadOSSettingsCodec.loadCatalog(revision: catalogRevision)
        try validate(catalog: catalog)
        let request = Request(draft: self, catalogRevision: catalog.revision)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(request)
        guard let json = String(data: data, encoding: .utf8) else { throw FactoriumV2SettingsError.invalidSelection }
        return "TOSCFG/2 \(json)"
    }

    public static func converted(from legacy: ThreadOSSettingsDraft, confirmedFourWorkerConversion: Bool, id: String = "cfg-" + UUID().uuidString.lowercased(), catalog: ThreadOSModelCatalog? = nil) throws -> Self {
        guard legacy.isValidProject else { throw FactoriumV2SettingsError.invalidProject }
        guard (legacy.codingWorkers <= 3 && legacy.reviewWorkers <= 3) || confirmedFourWorkerConversion else {
            throw FactoriumV2SettingsError.legacyWorkerConfirmationRequired
        }
        let catalog = try catalog ?? ThreadOSSettingsCodec.loadCatalog()
        var draft = Self(project: legacy.project, id: id, revision: 1)
        func resolved(_ role: ThreadOSRole) throws -> ThreadOSRoleSelection {
            let choice: ThreadOSRoleSelection
            if legacy.preset == "custom", let custom = legacy.customRoles[role] { choice = custom }
            else if let spec = catalog.presets[legacy.preset]?.roles[role.rawValue] { choice = .init(model: spec.selection ?? spec.model, reasoningEffort: spec.reasoningEffort) }
            else { throw FactoriumV2SettingsError.invalidRole }
            return try ThreadOSSettingsCodec.resolvedSelection(choice, role: role, catalog: catalog)
        }
        let qa = try resolved(.qa), foreman = try resolved(.foreman), codingWorker = try resolved(.codingWorker), reviewer = try resolved(.reviewer)
        draft.setSelection(.init(model: qa.model, effort: qa.reasoningEffort, speed: "standard"), for: .qa)
        draft.setSelection(.init(model: foreman.model, effort: foreman.reasoningEffort, speed: "standard"), for: .coder)
        draft.setSelection(.init(model: reviewer.model, effort: reviewer.reasoningEffort, speed: "standard"), for: .reviewer)
        draft.coderWorkers = (0..<3).map { index in .init(enabled: index < legacy.codingWorkers, inherits: false, selection: .init(model: codingWorker.model, effort: codingWorker.reasoningEffort, speed: "standard"), hasCustomSelection: true) }
        draft.reviewerWorkers = (0..<3).map { index in .init(enabled: index < legacy.reviewWorkers, inherits: true, selection: draft.roles[.reviewer]!.selection) }
        return draft
    }

    public static func conversionPreview(language: AppLanguage) -> String {
        language == .simplifiedChinese
            ? "Leader 保持为保留；QA 映射到 QA；V1 Foreman 映射到 Coder；V1 Coding Worker 变为保留的 Coder 槽位；Repair 保持 V2 默认值；V1 Reviewer 映射到 Reviewer。"
            : "Leader stays Preserve; QA maps to QA; V1 Foreman maps to Coder; V1 Coding Worker becomes retained Coder slots; Repair keeps the V2 default; V1 Reviewer maps to Reviewer."
    }

    private func validate(catalog: ThreadOSModelCatalog) throws {
        guard isValidProject else { throw FactoriumV2SettingsError.invalidProject }
        guard ThreadOSSettingsDraft.isToken(id) else { throw FactoriumV2SettingsError.invalidID }
        guard (1...1_000_000).contains(revision) else { throw FactoriumV2SettingsError.invalidRevision }
        guard Set(roles.keys) == Set(FactoriumV2Role.allCases) else { throw FactoriumV2SettingsError.invalidRole }
        guard coderWorkers.count == 3, reviewerWorkers.count == 3 else { throw FactoriumV2SettingsError.invalidWorkerSlots }
        for role in FactoriumV2Role.allCases {
            guard let setting = roles[role] else { throw FactoriumV2SettingsError.invalidRole }
            if setting.preserve && role != .leader { throw FactoriumV2SettingsError.invalidRole }
            if !setting.preserve { try validate(setting.selection, leader: role == .leader, catalog: catalog) }
        }
        for (parent, slots) in [(FactoriumV2Role.coder, coderWorkers), (.reviewer, reviewerWorkers)] {
            for slot in slots {
                try validate(resolvedSlot(slot, parent: parent), leader: false, catalog: catalog)
            }
        }
    }

    private func validate(_ selection: FactoriumV2Selection, leader: Bool, catalog: ThreadOSModelCatalog) throws {
        guard Self.availableModels(catalog: catalog).contains(selection.model), Self.availableEfforts(model: selection.model, leader: leader, catalog: catalog).contains(selection.effort), ["fast", "standard"].contains(selection.speed) else { throw FactoriumV2SettingsError.invalidSelection }
    }

    public static func availableModels(catalog: ThreadOSModelCatalog? = try? ThreadOSSettingsCodec.loadCatalog(revision: catalogRevision)) -> [String] {
        guard let catalog else { return [] }
        return catalog.models.keys.filter { $0 != "gpt-5.6-sol" }.sorted()
    }

    public static func availableEfforts(model: String, leader: Bool, catalog: ThreadOSModelCatalog? = try? ThreadOSSettingsCodec.loadCatalog(revision: catalogRevision)) -> [String] {
        guard let values = catalog?.models[model]?.reasoningEfforts else { return [] }
        return model == "gpt-6-astra" && !leader ? values.filter(["low", "medium", "high"].contains) : values
    }

    private struct Request: Encodable {
        let apply: String
        let cat: String
        let id: String
        let p: String
        let preset: String
        let rev: Int
        let roles: [String: RoleRequest]
        let workers: [String: [WorkerRequest]]

        init(draft: FactoriumV2SettingsDraft, catalogRevision: String) {
            apply = Self.apply; cat = catalogRevision; id = draft.id; p = draft.project; preset = Self.preset; rev = draft.revision
            roles = Dictionary(uniqueKeysWithValues: FactoriumV2Role.allCases.map { role in
                let setting = draft.roles[role]!
                return (role.rawValue, .init(setting: setting, isLeader: role == .leader))
            })
            workers = [
                FactoriumV2Role.coder.rawValue: draft.coderWorkers.map { .init(slot: $0) },
                FactoriumV2Role.reviewer.rawValue: draft.reviewerWorkers.map { .init(slot: $0) },
            ]
        }

        private static let apply = FactoriumV2SettingsDraft.apply
        private static let preset = FactoriumV2SettingsDraft.preset
    }

    private struct RoleRequest: Encodable {
        let preserve: Bool?
        let model: String?
        let effort: String?
        let speed: String?

        init(setting: FactoriumV2RoleSetting, isLeader: Bool) {
            preserve = isLeader && setting.preserve ? true : nil
            model = preserve == nil ? setting.selection.model : nil
            effort = preserve == nil ? setting.selection.effort : nil
            speed = preserve == nil ? setting.selection.speed : nil
        }
    }

    private struct WorkerRequest: Encodable {
        let enabled: Bool
        let model: String
        let effort: String
        let speed: String

        init(slot: FactoriumV2WorkerSlot) {
            enabled = slot.enabled
            model = slot.inherits ? "inherit" : slot.selection.model
            effort = slot.inherits ? "inherit" : slot.selection.effort
            speed = slot.inherits ? "inherit" : slot.selection.speed
        }
    }

    private enum CodingKeys: String, CodingKey {
        case project, catalogRevision, id, revision, roles, coderWorkers, reviewerWorkers
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        project = try values.decode(String.self, forKey: .project)
        // Existing saved drafts lacked a catalog marker. Keep them on the
        // immutable catalog they were created against.
        catalogRevision = try values.decodeIfPresent(String.self, forKey: .catalogRevision) ?? ThreadOSSettingsCodec.legacyCatalogRevision
        id = try values.decode(String.self, forKey: .id)
        revision = try values.decode(Int.self, forKey: .revision)
        roles = try values.decode([FactoriumV2Role: FactoriumV2RoleSetting].self, forKey: .roles)
        coderWorkers = try values.decode([FactoriumV2WorkerSlot].self, forKey: .coderWorkers)
        reviewerWorkers = try values.decode([FactoriumV2WorkerSlot].self, forKey: .reviewerWorkers)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(project, forKey: .project)
        try values.encode(catalogRevision, forKey: .catalogRevision)
        try values.encode(id, forKey: .id)
        try values.encode(revision, forKey: .revision)
        try values.encode(roles, forKey: .roles)
        try values.encode(coderWorkers, forKey: .coderWorkers)
        try values.encode(reviewerWorkers, forKey: .reviewerWorkers)
    }
}

@MainActor public final class FactoriumV2FormState: ObservableObject {
    @Published public private(set) var draft: FactoriumV2SettingsDraft
    @Published public private(set) var selectedProject: String
    @Published public var newProject = ""
    @Published public var rawAcknowledgement = ""
    @Published public private(set) var message = ""
    @Published public private(set) var copiedRevision: Int?
    @Published public private(set) var copiedArtifactSHA256: String?
    @Published public private(set) var receipt: FactoriumV2ReceiptProjection?
    @Published public private(set) var receiptInputIsInvalid = false
    private let preferences: ApplicationPreferences

    public init(preferences: ApplicationPreferences = .production) {
        self.preferences = preferences
        let available = Array(Set(ThreadOSSettingsPreferences.factoriumV2Projects(from: preferences) + ThreadOSSettingsPreferences.projects(from: preferences))).sorted()
        let remembered = ThreadOSSettingsPreferences.selectedFactoriumV2Project(from: preferences)
        let project = remembered.flatMap { available.contains($0) ? $0 : nil } ?? available.first ?? ""
        let saved = project.isEmpty ? nil : ThreadOSSettingsPreferences.loadFactoriumV2(project: project, from: preferences)
        draft = saved ?? FactoriumV2SettingsDraft()
        selectedProject = project
    }

    public var projects: [String] { Array(Set(ThreadOSSettingsPreferences.factoriumV2Projects(from: preferences) + ThreadOSSettingsPreferences.projects(from: preferences))).sorted() }
    public var selectedLegacyDraft: ThreadOSSettingsDraft? {
        guard ThreadOSSettingsPreferences.loadFactoriumV2(project: selectedProject, from: preferences) == nil else { return nil }
        return ThreadOSSettingsPreferences.load(project: selectedProject, from: preferences)
    }
    public var isShowingV2Draft: Bool { draft.isValidProject && ThreadOSSettingsPreferences.loadFactoriumV2(project: selectedProject, from: preferences) != nil }

    public func select(project: String) {
        selectedProject = project
        draft = ThreadOSSettingsPreferences.loadFactoriumV2(project: project, from: preferences) ?? .init()
        invalidateTransferState()
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(project.isEmpty ? nil : project, to: preferences)
    }

    public func createProject() {
        guard ThreadOSSettingsDraft.isToken(newProject) else { return }
        let project = newProject
        guard ThreadOSSettingsPreferences.load(project: project, from: preferences) == nil || ThreadOSSettingsPreferences.loadFactoriumV2(project: project, from: preferences) != nil else {
            message = "This project has a V1 draft. Use explicit V2 conversion; the V1 draft will not be replaced."
            return
        }
        selectedProject = project
        draft = ThreadOSSettingsPreferences.loadFactoriumV2(project: project, from: preferences) ?? .init(project: project)
        newProject = ""
        saveCurrent()
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(project, to: preferences)
        invalidateTransferState()
    }

    public func edit(allowIncompleteEffort: Bool = false, _ mutation: (inout FactoriumV2SettingsDraft) -> Void) {
        var candidate = draft
        mutation(&candidate)
        guard candidate != draft, candidate.revision < 1_000_000 else { return }
        candidate.revision += 1
        guard candidate.isLocallyValid || (allowIncompleteEffort && validatesWithExplicitEffortPlaceholders(candidate)) else {
            message = "Edit was not applied because the current catalog does not allow that local selection."
            return
        }
        draft = candidate
        saveCurrent()
        invalidateTransferState()
    }

    public func convert(legacy: ThreadOSSettingsDraft, confirmedFourWorkerConversion: Bool) throws {
        let converted = try FactoriumV2SettingsDraft.converted(from: legacy, confirmedFourWorkerConversion: confirmedFourWorkerConversion)
        draft = converted
        selectedProject = converted.project
        saveCurrent()
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(converted.project, to: preferences)
        invalidateTransferState()
    }

    public func selectRoleModel(_ model: String, role: FactoriumV2Role) {
        edit(allowIncompleteEffort: true) { draft in
            guard var setting = draft.roles[role] else { return }
            setting.selection.model = model
            let catalog = try? ThreadOSSettingsCodec.loadCatalog(revision: draft.catalogRevision)
            if !FactoriumV2SettingsDraft.availableEfforts(model: model, leader: role == .leader, catalog: catalog).contains(setting.selection.effort) {
                setting.selection.effort = ""
            }
            draft.roles[role] = setting
        }
    }

    public func selectSlotModel(_ model: String, at index: Int, for role: FactoriumV2Role) {
        edit(allowIncompleteEffort: true) { draft in
            guard draft.workers(for: role).indices.contains(index) else { return }
            var selection = draft.workers(for: role)[index].selection
            selection.model = model
            let catalog = try? ThreadOSSettingsCodec.loadCatalog(revision: draft.catalogRevision)
            if !FactoriumV2SettingsDraft.availableEfforts(model: model, leader: false, catalog: catalog).contains(selection.effort) {
                selection.effort = ""
            }
            draft.setSlotSelection(selection, at: index, for: role)
        }
    }

    private func validatesWithExplicitEffortPlaceholders(_ candidate: FactoriumV2SettingsDraft) -> Bool {
        var completed = candidate
        guard let catalog = try? ThreadOSSettingsCodec.loadCatalog(revision: candidate.catalogRevision) else { return false }
        for role in FactoriumV2Role.allCases {
            guard var setting = completed.roles[role], !setting.preserve, setting.selection.effort.isEmpty else { continue }
            guard let effort = FactoriumV2SettingsDraft.availableEfforts(model: setting.selection.model, leader: role == .leader, catalog: catalog).first else { return false }
            setting.selection.effort = effort
            completed.roles[role] = setting
        }
        for role in [FactoriumV2Role.coder, .reviewer] {
            var slots = completed.workers(for: role)
            for index in slots.indices where !slots[index].inherits && slots[index].selection.effort.isEmpty {
                guard let effort = FactoriumV2SettingsDraft.availableEfforts(model: slots[index].selection.model, leader: false, catalog: catalog).first else { return false }
                slots[index].selection.effort = effort
            }
            completed.setWorkers(slots, for: role)
        }
        return completed.isLocallyValid
    }

    public var requiresStandardConversion: Bool {
        draft.roles.values.contains { !$0.preserve && $0.selection.speed == "fast" }
            || (draft.coderWorkers + draft.reviewerWorkers).contains { !$0.inherits && $0.selection.speed == "fast" }
    }

    public func generatedRequest() throws -> FactoriumV2GeneratedRequest {
        guard draft.isValidProject else { throw FactoriumV2SettingsError.invalidProject }
        guard !requiresStandardConversion else { throw FactoriumV2SettingsError.legacyFastConversionRequired }
        let settingsLine = try draft.canonicalRequest()
        return .init(settingsLine: settingsLine, text: settingsLine, artifactSHA256: sha256(settingsLine))
    }

    /// The explicit transfer action is the only path that may normalize a retained Fast draft.
    public func generatedRequestForTransfer() throws -> FactoriumV2GeneratedRequest {
        if requiresStandardConversion {
            guard draft.revision < 1_000_000 else { throw FactoriumV2SettingsError.invalidRevision }
            convertSelectedFastDraftToStandard()
        }
        return try generatedRequest()
    }

    @discardableResult
    public func generateAndCopy(to clipboard: any ThreadOSSettingsClipboard, language: AppLanguage) -> FactoriumV2GeneratedRequest? {
        do {
            let generated = try generatedRequestForTransfer()
            reportCopy(generated, success: clipboard.write(generated.text), language: language)
            return generated
        } catch {
            reportTransferGenerationError(error, language: language)
            return nil
        }
    }

    public func reportCopy(_ generated: FactoriumV2GeneratedRequest, success: Bool, language: AppLanguage) {
        guard generated == (try? generatedRequest()) else {
            copiedRevision = nil
            copiedArtifactSHA256 = nil
            message = localized(language, "A stale generated request was not recorded as copied.", "过期的生成请求未被记录为已复制。")
            return
        }
        copiedRevision = success ? draft.revision : nil
        copiedArtifactSHA256 = success ? generated.artifactSHA256 : nil
        message = success
            ? localized(language, "Generated and copied a local request for manual Leader transfer. Native selection remains unconfirmed.", "已生成并复制本地请求，供手动粘贴给 Leader。原生选择仍未确认。")
            : localized(language, "Request was generated, but the local clipboard could not be written.", "请求已生成，但无法写入本地剪贴板。")
    }

    public func reportCopy(success: Bool, language: AppLanguage) {
        guard let generated = try? generatedRequest() else {
            copiedRevision = nil
            copiedArtifactSHA256 = nil
            return
        }
        reportCopy(generated, success: success, language: language)
    }

    public func reportTransferGenerationError(_ error: Error, language: AppLanguage) {
        let detail = (error as? FactoriumV2SettingsError) == .invalidRevision
            ? localized(language, "Cannot create a new Standard revision because this draft reached the local revision limit.", "此草稿已达到本地修订上限，无法创建新的标准修订版本。")
            : localized(language, "Cannot generate this local configuration request.", "无法生成此本地配置请求。")
        copiedRevision = nil
        copiedArtifactSHA256 = nil
        message = detail
    }

    public func receiveReceipt(language: AppLanguage) {
        do {
            receipt = try FactoriumV2SettingsCodec.receiptProjection(rawAcknowledgement, matching: draft)
            receiptInputIsInvalid = false
            message = localized(language, "ThreadOS receipt matched this local draft. Native selection remains pending and unknown.", "ThreadOS 回执与此本地草稿匹配。原生选择仍待处理且未知。")
        } catch {
            receiptInputIsInvalid = true
            message = localized(language, "Receipt was not accepted for this local draft; no settings were changed.", "此本地草稿未接受该回执；未更改任何设置。")
        }
    }

    public func roleStatus(language: AppLanguage) -> String {
        if receipt != nil { return localized(language, "ThreadOS received · pending native · UNKNOWN", "ThreadOS 已接收 · 原生待处理 · 未知") }
        if copiedRevision == draft.revision { return localized(language, "Copied local request · ThreadOS receipt unavailable", "已复制本地请求 · ThreadOS 回执不可用") }
        return localized(language, "Local draft · native selection unconfirmed", "本地草稿 · 原生选择未确认")
    }

    public func reportConversionError(language: AppLanguage) {
        message = localized(language, "V2 conversion was not created. The V1 draft remains unchanged.", "未创建 V2 转换。V1 草稿保持不变。")
    }

    public func convertSelectedFastDraftToStandard() {
        guard requiresStandardConversion, draft.revision < 1_000_000 else { return }
        let original = draft
        var converted = draft
        for role in FactoriumV2Role.allCases where !(converted.roles[role]?.preserve ?? false) {
            converted.roles[role]?.selection.speed = "standard"
        }
        for role in [FactoriumV2Role.coder, .reviewer] {
            var slots = converted.workers(for: role)
            for index in slots.indices where !slots[index].inherits { slots[index].selection.speed = "standard" }
            converted.setWorkers(slots, for: role)
        }
        converted.revision += 1
        ThreadOSSettingsPreferences.saveFactoriumV2LegacySnapshot(original, to: preferences)
        draft = converted
        saveCurrent()
        invalidateTransferState()
    }

    private func saveCurrent() {
        guard draft.isValidProject else { return }
        ThreadOSSettingsPreferences.saveFactoriumV2(draft, to: preferences)
    }

    private func invalidateTransferState() {
        copiedRevision = nil
        copiedArtifactSHA256 = nil
        receipt = nil
        receiptInputIsInvalid = false
        rawAcknowledgement = ""
        message = ""
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func localized(_ language: AppLanguage, _ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
