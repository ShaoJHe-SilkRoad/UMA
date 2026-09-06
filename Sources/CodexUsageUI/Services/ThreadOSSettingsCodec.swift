import Foundation

public enum ThreadOSSettingsCodecError: Error, Equatable {
    case invalidProject, invalidIdentity, invalidWorkers, unsupportedPreset, unsupportedTier, invalidRoleConfiguration, unsupportedModel, invalidMode, catalogUnavailable, unsupportedReceipt, duplicateJSONKey, invalidRequestFields, invalidApply, invalidRevision
    case invalidProtocolPrefix, invalidJSON, requestObjectRequired, invalidCodingWorkers, invalidReviewWorkers
    /// Exact pinned Python parser error correspondence; runtime ledger errors are not codec errors.
    public var protocolCode: String {
        switch self {
        case .invalidProject: "INVALID_PROJECT"
        case .invalidIdentity: "INVALID_ID"
        case .invalidWorkers, .invalidCodingWorkers: "INVALID_CODING_WORKERS"
        case .invalidReviewWorkers: "INVALID_REVIEW_WORKERS"
        case .unsupportedPreset: "UNSUPPORTED_CATALOG_OR_PRESET"
        case .unsupportedTier: "UNSUPPORTED_TIER"
        case .invalidRoleConfiguration: "INVALID_ROLE_CONFIGURATION"
        case .unsupportedModel: "UNSUPPORTED_MODEL"
        case .invalidMode: "INVALID_MODE_REQUEST"
        case .catalogUnavailable: "CATALOG_UNAVAILABLE"
        case .unsupportedReceipt: "UNSUPPORTED_RECEIPT_SHAPE"
        case .duplicateJSONKey: "DUPLICATE_JSON_KEY"
        case .invalidRequestFields: "INVALID_REQUEST_FIELDS"
        case .invalidApply: "INVALID_APPLY"
        case .invalidRevision: "INVALID_REVISION"
        case .invalidProtocolPrefix: "INVALID_PROTOCOL_PREFIX"
        case .invalidJSON: "INVALID_JSON"
        case .requestObjectRequired: "REQUEST_OBJECT_REQUIRED"
        }
    }
}

/// The UI may present only this local acknowledgement interpretation.  It is
/// deliberately not a model-selection or execution result.
public enum ThreadOSSettingsAcknowledgementPresentation: Equatable, Sendable {
    case pendingNativeSelection, modeOnObservedLocalOnly, modeOffObservedLocalOnly
    case modeOffQueuedUntilIdle, waveStartedConfiguredModelUnobserved
    case waveFinishedLocalOnly, statusLocalOnly, settingsError, unsupported
}

public enum ThreadOSSelectionObservation: Equatable, Sendable { case pendingNativeSelection, notApplicable }
public enum ThreadOSEffectiveModelObservation: String, Codable, Equatable, Sendable { case unknown }
public struct ThreadOSSettingsReceiptView: Codable, Equatable, Sendable {
    public struct Role: Codable, Equatable, Sendable {
        public let requestedModel: String
        public let configuredModel: String
        public let reasoningEffort: String
        public let effectiveObserved: ThreadOSEffectiveModelObservation
        public let nativeStatus: String
        enum CodingKeys: String, CodingKey {
            case requestedModel = "requested_model", configuredModel = "configured_model", reasoningEffort = "reasoning_effort", effectiveObserved = "effective_observed", nativeStatus = "native_status"
        }
    }
    public let catalogRevision: String
    public let preset: String
    public let roles: [String: Role]
    public let codingWorkers: Int
    public let reviewWorkers: Int
    public let tier: String
    public let apply: String
    enum CodingKeys: String, CodingKey {
        case catalogRevision = "catalog_revision", preset, roles, codingWorkers = "coding_workers", reviewWorkers = "review_workers", tier, apply
    }
}

/// Manual, unauthenticated ACK content. Equality with a draft establishes only value agreement.
public struct ThreadOSSettingsReceiptProjection: Equatable, Sendable {
    public let presentation: ThreadOSSettingsAcknowledgementPresentation
    public let selection: ThreadOSSelectionObservation
    public let effectiveModel: ThreadOSEffectiveModelObservation
    public let id: String?
    public let revision: Int?
    public let preset: String?
    public let requested: ThreadOSSettingsReceiptView?
    public let configured: ThreadOSSettingsReceiptView?
    public var authenticatesProject: Bool { false }
    public func matches(draft: ThreadOSSettingsDraft, catalog: ThreadOSModelCatalog) -> Bool {
        guard presentation == .pendingNativeSelection, id == draft.id, revision == draft.revision, preset == draft.preset,
              let expected = try? ThreadOSSettingsCodec.configurationView(draft, catalog: catalog) else { return false }
        return requested == expected && configured == expected
    }
}

public struct ThreadOSModelCatalog: Codable, Equatable, Sendable {
    public struct Model: Codable, Equatable, Sendable { public let reasoningEfforts: [String]; enum CodingKeys: String, CodingKey { case reasoningEfforts = "reasoning_efforts" } }
    public struct RoleSpec: Codable, Equatable, Sendable { public let model: String; public let reasoningEffort: String; public let selection: String?; enum CodingKeys: String, CodingKey { case model, selection; case reasoningEffort = "reasoning_effort" } }
    public struct Preset: Codable, Equatable, Sendable { public let roles: [String: RoleSpec]; public let codingWorkers: Int?; public let reviewWorkers: Int?; public let serviceTier: String; enum CodingKeys: String, CodingKey { case roles; case codingWorkers = "coding_workers"; case reviewWorkers = "review_workers"; case serviceTier = "service_tier" } }
    public struct SelectionPolicy: Codable, Equatable, Sendable {
        public let coderAutoFallback: RoleSpec
        enum CodingKeys: String, CodingKey { case coderAutoFallback = "coder_auto_fallback" }
    }
    public let schema: String; public let revision: String; public let models: [String: Model]; public let presets: [String: Preset]
    public let selectionPolicy: SelectionPolicy
    enum CodingKeys: String, CodingKey { case schema, revision, models, presets; case selectionPolicy = "selection_policy" }
}

public enum ThreadOSSettingsCodec {
    public static let catalogRevision = "astra-20260904.1" // Compatibility constant; serialization reads Bundle.module.
    public static let roleOrder: [ThreadOSRole] = [.codingWorker, .foreman, .leader, .qa, .reviewer]
    public static func loadCatalog() throws -> ThreadOSModelCatalog { try loadCatalog(bundle: .module) }
    public static func loadCatalog(bundle: Bundle) throws -> ThreadOSModelCatalog {
        let url = bundle.url(forResource: "models.v1", withExtension: "json", subdirectory: "ThreadOS") ?? bundle.url(forResource: "models.v1", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(ThreadOSModelCatalog.self, from: data), catalog.schema == "threados.model-catalog.v1", Set(catalog.presets.keys).isSuperset(of: ["astra-economy", "astra-balanced", "astra-speed", "astra-deep", "custom"]) else { throw ThreadOSSettingsCodecError.catalogUnavailable }
        return catalog
    }
    public static func canonicalRequest(_ draft: ThreadOSSettingsDraft) throws -> String { try canonicalRequest(draft, catalog: loadCatalog()) }
    public static func configurationView(_ draft: ThreadOSSettingsDraft, catalog: ThreadOSModelCatalog) throws -> ThreadOSSettingsReceiptView {
        _ = try canonicalRequest(draft, catalog: catalog)
        var roles: [String: ThreadOSSettingsReceiptView.Role] = [:]
        for role in ThreadOSRole.allCases {
            let choice: ThreadOSRoleSelection
            if draft.preset == "custom", let custom = draft.customRoles[role] { choice = custom }
            else if let spec = catalog.presets[draft.preset]?.roles[role.rawValue] { choice = .init(model: spec.selection ?? spec.model, reasoningEffort: spec.reasoningEffort) }
            else { throw ThreadOSSettingsCodecError.invalidRoleConfiguration }
            let resolved = try resolvedSelection(choice, role: role, catalog: catalog)
            roles[role.rawValue] = .init(requestedModel: resolved.model, configuredModel: resolved.model, reasoningEffort: resolved.reasoningEffort, effectiveObserved: .unknown, nativeStatus: "pending_native_selection")
        }
        return .init(catalogRevision: catalog.revision, preset: draft.preset, roles: roles, codingWorkers: draft.codingWorkers, reviewWorkers: draft.reviewWorkers, tier: draft.tier, apply: "next-wave")
    }
    public static func canonicalRequest(_ draft: ThreadOSSettingsDraft, catalog: ThreadOSModelCatalog) throws -> String {
        guard draft.isValidProject else { throw ThreadOSSettingsCodecError.invalidProject }
        guard ThreadOSSettingsDraft.isToken(draft.id) else { throw ThreadOSSettingsCodecError.invalidIdentity }
        guard (1...1_000_000).contains(draft.revision) else { throw ThreadOSSettingsCodecError.invalidRevision }
        guard draft.tier == "standard" || draft.tier == "priority" else { throw ThreadOSSettingsCodecError.unsupportedTier }
        guard let preset = catalog.presets[draft.preset] else { throw ThreadOSSettingsCodecError.unsupportedPreset }
        guard (1...4).contains(draft.codingWorkers) else { throw ThreadOSSettingsCodecError.invalidCodingWorkers }
        guard (1...4).contains(draft.reviewWorkers) else { throw ThreadOSSettingsCodecError.invalidReviewWorkers }
        var value: [String: Any] = ["apply":"next-wave", "cat":catalog.revision, "id":draft.id, "p":draft.project, "preset":draft.preset, "rev":draft.revision, "tier":draft.tier, "cw":draft.codingWorkers, "rw":draft.reviewWorkers]
        if draft.preset == "custom" {
            guard Set(draft.customRoles.keys) == Set(ThreadOSRole.allCases) else { throw ThreadOSSettingsCodecError.invalidRoleConfiguration }
            for role in ThreadOSRole.allCases {
                guard let choice = draft.customRoles[role] else { throw ThreadOSSettingsCodecError.invalidRoleConfiguration }
                let resolved = try resolvedSelection(choice, role: role, catalog: catalog)
                value[role.requestKey] = [resolved.model, resolved.reasoningEffort]
            }
        } else {
            guard preset.roles.count == ThreadOSRole.allCases.count, let cw = preset.codingWorkers, let rw = preset.reviewWorkers, (1...4).contains(cw), (1...4).contains(rw) else { throw ThreadOSSettingsCodecError.catalogUnavailable }
            for role in ThreadOSRole.allCases {
                guard let spec = preset.roles[role.rawValue], (try? resolvedSelection(.init(model: spec.selection ?? spec.model, reasoningEffort: spec.reasoningEffort), role: role, catalog: catalog)) != nil else { throw ThreadOSSettingsCodecError.catalogUnavailable }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        guard let json = String(data: data, encoding: .utf8), json.unicodeScalars.allSatisfy({ $0.value < 128 }) else { throw ThreadOSSettingsCodecError.invalidIdentity }
        return "TOSCFG/1 " + json
    }
    /// Serializes the protocol's mode request without inferring any execution authority.
    public static func canonicalMode(mode: String, when: String? = nil) throws -> String {
        var value: [String: Any] = ["mode": mode]
        switch mode {
        case "on": guard when == nil else { throw ThreadOSSettingsCodecError.invalidMode }
        case "off": guard when == "idle" else { throw ThreadOSSettingsCodecError.invalidMode }; value["when"] = "idle"
        default: throw ThreadOSSettingsCodecError.invalidMode
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        guard let json = String(data: data, encoding: .utf8), json.unicodeScalars.allSatisfy({ $0.value < 128 }) else { throw ThreadOSSettingsCodecError.invalidMode }
        return "TOSMODE/1 " + json
    }
    public static func resolvedSelection(_ choice: ThreadOSRoleSelection, role: ThreadOSRole, catalog: ThreadOSModelCatalog) throws -> ThreadOSRoleSelection {
        var resolved = choice
        if choice.model == "coder_auto" {
            guard role == .foreman else { throw ThreadOSSettingsCodecError.unsupportedModel }
            resolved.model = catalog.selectionPolicy.coderAutoFallback.model
        }
        guard resolved.model != "gpt-5.6-sol", catalog.models[resolved.model]?.reasoningEfforts.contains(resolved.reasoningEffort) == true else { throw ThreadOSSettingsCodecError.unsupportedModel }
        return resolved
    }

    /// Strictly decodes a pinned `TOSCFG/1` input.  This is validation of a
    /// local request shape only; it neither dispatches it nor records receipt
    /// state. JSONSerialization accepts duplicate keys, so they are rejected
    /// before object parsing.
    public static func draft(fromFrozenInput input: String, catalog: ThreadOSModelCatalog? = nil) throws -> ThreadOSSettingsDraft {
        guard input.hasPrefix("TOSCFG/1 ") else { throw ThreadOSSettingsCodecError.invalidProtocolPrefix }
        let value = try strictObject(String(input.dropFirst("TOSCFG/1 ".count)))
        let catalog = try catalog ?? loadCatalog()
        let base: Set<String> = ["cat", "id", "p", "preset", "rev", "apply", "tier", "cw", "rw", "l", "q", "f", "w", "r"]
        guard Set(value.keys).isSubset(of: base), Set(value.keys).isSuperset(of: ["p", "id", "rev", "cat", "preset"]) else { throw ThreadOSSettingsCodecError.invalidRequestFields }
        guard strictString(value["cat"]) == catalog.revision, let presetName = strictString(value["preset"]), let preset = catalog.presets[presetName] else { throw ThreadOSSettingsCodecError.unsupportedPreset }
        let roleKeys = Set(ThreadOSRole.allCases.map(\.requestKey))
        let suppliedRoleKeys = Set(value.keys).intersection(roleKeys)
        guard presetName == "custom" ? suppliedRoleKeys == roleKeys : suppliedRoleKeys.isEmpty else { throw ThreadOSSettingsCodecError.invalidRoleConfiguration }
        guard let tier = value["tier"].map(strictString) ?? preset.serviceTier, ["standard", "priority"].contains(tier) else { throw ThreadOSSettingsCodecError.unsupportedTier }
        guard value["apply"] == nil || strictString(value["apply"]) == "next-wave" else { throw ThreadOSSettingsCodecError.invalidApply }
        guard let project = strictString(value["p"]), ThreadOSSettingsDraft.isToken(project) else { throw ThreadOSSettingsCodecError.invalidProject }
        guard let id = strictString(value["id"]), ThreadOSSettingsDraft.isToken(id) else { throw ThreadOSSettingsCodecError.invalidIdentity }
        guard let revision = strictInt(value["rev"]), (1...1_000_000).contains(revision) else { throw ThreadOSSettingsCodecError.invalidRevision }
        guard let cw = value["cw"].map(strictInt) ?? preset.codingWorkers, (1...4).contains(cw) else { throw ThreadOSSettingsCodecError.invalidCodingWorkers }
        guard let rw = value["rw"].map(strictInt) ?? preset.reviewWorkers, (1...4).contains(rw) else { throw ThreadOSSettingsCodecError.invalidReviewWorkers }
        if presetName != "custom" {
            return .init(project: project, id: id, revision: revision, preset: presetName, codingWorkers: cw, reviewWorkers: rw, tier: tier)
        }
        var roles: [ThreadOSRole: ThreadOSRoleSelection] = [:]
        for role in ThreadOSRole.allCases {
            guard let pair = value[role.requestKey] as? [Any], pair.count == 2 else { throw ThreadOSSettingsCodecError.invalidRoleConfiguration }
            guard let model = strictString(pair[0]), let effort = strictString(pair[1]) else { throw ThreadOSSettingsCodecError.unsupportedModel }
            let incoming = ThreadOSRoleSelection(model: model, reasoningEffort: effort)
            roles[role] = try resolvedSelection(incoming, role: role, catalog: catalog)
        }
        return .init(project: project, id: id, revision: revision, preset: presetName, codingWorkers: cw, reviewWorkers: rw, tier: tier, customRoles: roles)
    }
    private static func strictString(_ value: Any?) -> String? { value as? String }
    private static func strictInt(_ value: Any?) -> Int? { guard let value, type(of: value) == Int.self else { return nil }; return value as? Int }
    private static func strictObject(_ json: String) throws -> [String: Any] {
        var parser = StrictJSON(bytes: Array(json.utf8))
        let value = try parser.value()
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw ThreadOSSettingsCodecError.invalidJSON }
        guard let object = value as? [String: Any] else { throw ThreadOSSettingsCodecError.requestObjectRequired }
        return object
    }

    /// Receipt validation never treats a local configuration as observed native model evidence.
    public static func receiptProjection(_ text: String) -> ThreadOSSettingsReceiptProjection? {
        guard let object = try? strictObject(text), validReceipt(object) else { return nil }
        func view(_ key: String) -> ThreadOSSettingsReceiptView? {
            guard let value = object[key] as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return try? JSONDecoder().decode(ThreadOSSettingsReceiptView.self, from: data)
        }
        let presentation = receiptPresentation(text)
        return .init(presentation: presentation, selection: presentation == .pendingNativeSelection ? .pendingNativeSelection : .notApplicable, effectiveModel: .unknown, id: strictString(object["id"]), revision: strictInt(object["rev"]), preset: strictString(object["preset"]), requested: view("requested"), configured: view("configured"))
    }
    public static func receiptPresentation(_ text: String) -> ThreadOSSettingsAcknowledgementPresentation {
        guard let object = try? strictObject(text), validReceipt(object) else { return .unsupported }
        switch object["status"] as? String { case "pending_native_selection": return .pendingNativeSelection; case "mode_updated": return object["mode"] as? String == "on" ? .modeOnObservedLocalOnly : .modeOffObservedLocalOnly; case "mode_queued": return .modeOffQueuedUntilIdle; case "wave_started": return .waveStartedConfiguredModelUnobserved; case "wave_finished": return .waveFinishedLocalOnly; case "status": return .statusLocalOnly; case "error": return .settingsError; default: return .unsupported }
    }
    public static func receiptDisplay(_ text: String) -> String { switch receiptPresentation(text) { case .pendingNativeSelection: "PENDING_NATIVE_SELECTION"; case .modeOnObservedLocalOnly: "MODE_ON_OBSERVED_LOCAL_ONLY"; case .modeOffObservedLocalOnly: "MODE_OFF_OBSERVED_LOCAL_ONLY"; case .modeOffQueuedUntilIdle: "MODE_OFF_QUEUED_UNTIL_IDLE"; case .waveStartedConfiguredModelUnobserved: "WAVE_STARTED_CONFIGURED_MODEL_UNOBSERVED"; case .waveFinishedLocalOnly: "WAVE_FINISHED_LOCAL_ONLY"; case .statusLocalOnly: "STATUS_LOCAL_ONLY"; case .settingsError: "THREADOS_SETTINGS_ERROR"; case .unsupported: "UNSUPPORTED_RECEIPT_SHAPE" } }
    private static func validReceipt(_ v: [String: Any]) -> Bool {
        guard v["schema"] as? String == "threados.settings-receipt.v1", v["protocol"] as? String == "TOSACK/1", v["authority"] as? String == "settings_do_not_grant_authority", let status = v["status"] as? String else { return false }
        let base: Set<String> = ["schema", "protocol", "authority", "status"]
        switch status {
        case "pending_native_selection":
            guard Set(v.keys) == base.union(["effective_from","id","rev","preset","requested","configured","effective_observed","pending_native"]), v["effective_from"] as? String == "next-wave", ThreadOSSettingsDraft.isToken(v["id"] as? String ?? ""), let rev = strictInt(v["rev"]), (1...1_000_000).contains(rev), validPreset(v["preset"]), v["effective_observed"] as? String == "unknown", v["pending_native"] as? [String] == roleOrder.map(\.rawValue), let requested = v["requested"] as? [String:Any], let configured = v["configured"] as? [String:Any] else { return false }
            return validView(requested) && validView(configured)
        case "mode_updated": return Set(v.keys) == base.union(["mode","effective_from"]) && ["on","off"].contains(v["mode"] as? String ?? "") && v["effective_from"] as? String == "observed"
        case "mode_queued": return Set(v.keys) == base.union(["mode","effective_from"]) && v["mode"] as? String == "off" && v["effective_from"] as? String == "idle"
        case "wave_started": return Set(v.keys) == base.union(["wave_id","configured"]) && ThreadOSSettingsDraft.isToken(v["wave_id"] as? String ?? "") && validView(v["configured"] as? [String:Any] ?? [:])
        case "wave_finished": return Set(v.keys) == base.union(["wave_id","mode"]) && ThreadOSSettingsDraft.isToken(v["wave_id"] as? String ?? "") && ["on","off"].contains(v["mode"] as? String ?? "")
        case "status": return Set(v.keys) == base.union(["mode","pending_mode","active","pending","running_wave"]) && ["on","off"].contains(v["mode"] as? String ?? "") && (v["pending_mode"] is NSNull || v["pending_mode"] as? String == "off") && validOptionalView(v["active"]) && validOptionalView(v["pending"]) && validRunningWave(v["running_wave"])
        case "error": return Set(v.keys) == base.union(["error"]) && (v["error"] as? String).map { $0.range(of: "\\A[A-Z][A-Z0-9_]{0,63}\\z", options: .regularExpression) != nil } == true
        default: return false
        }
    }
    private static func validOptionalView(_ v: Any?) -> Bool { v is NSNull || validView(v as? [String:Any] ?? [:]) }
    private static func validRunningWave(_ v: Any?) -> Bool { guard v is NSNull || v is [String:Any] else { return false }; guard let wave = v as? [String:Any] else { return true }; return Set(wave.keys) == ["wave_id","config"] && ThreadOSSettingsDraft.isToken(wave["wave_id"] as? String ?? "") && validView(wave["config"] as? [String:Any] ?? [:]) }
    private static func validPreset(_ value: Any?) -> Bool { ["astra-economy","astra-balanced","astra-speed","astra-deep","custom"].contains(value as? String ?? "") }
    private static func validView(_ v: [String:Any]) -> Bool {
        guard Set(v.keys) == ["catalog_revision","preset","roles","coding_workers","review_workers","tier","apply"], v["catalog_revision"] as? String == catalogRevision, validPreset(v["preset"]), let cw = strictInt(v["coding_workers"]), let rw = strictInt(v["review_workers"]), (1...4).contains(cw), (1...4).contains(rw), ["standard","priority"].contains(v["tier"] as? String ?? ""), v["apply"] as? String == "next-wave", let roles = v["roles"] as? [String:Any], Set(roles.keys) == Set(ThreadOSRole.allCases.map(\.rawValue)) else { return false }
        return roles.values.allSatisfy(validRole)
    }
    private static func validRole(_ v: Any) -> Bool { guard let role = v as? [String:Any], Set(role.keys) == ["requested_model","configured_model","reasoning_effort","effective_observed","native_status"], ["gpt-5.6-terra","gpt-6-astra"].contains(role["requested_model"] as? String ?? ""), ["gpt-5.6-terra","gpt-6-astra"].contains(role["configured_model"] as? String ?? ""), ["low","medium","high","xhigh","max","ultra"].contains(role["reasoning_effort"] as? String ?? ""), role["effective_observed"] as? String == "unknown", ["pending_native_selection","unsupported"].contains(role["native_status"] as? String ?? "") else { return false }; return true }
}

/// Parses before Foundation can collapse object members or bridge booleans into integers.
/// Key identity uses the decoded JSON string, scoped independently to each object.
private struct StrictJSON {
    let bytes: [UInt8]
    var index = 0
    mutating func whitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func consume(_ byte: UInt8) -> Bool { whitespace(); guard index < bytes.count, bytes[index] == byte else { return false }; index += 1; return true }
    mutating func string() throws -> String {
        whitespace()
        let start = index
        guard consume(34) else { throw ThreadOSSettingsCodecError.invalidJSON }
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 92 { guard index < bytes.count else { throw ThreadOSSettingsCodecError.invalidJSON }; index += 1 }
            else if byte == 34 {
                guard let result = try? JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: .fragmentsAllowed) as? String else { throw ThreadOSSettingsCodecError.invalidJSON }
                return result
            }
        }
        throw ThreadOSSettingsCodecError.invalidJSON
    }
    mutating func value(depth: Int = 0) throws -> Any {
        whitespace()
        guard depth < 128, index < bytes.count else { throw ThreadOSSettingsCodecError.invalidJSON }
        switch bytes[index] {
        case 34: return try string()
        case 123:
            index += 1
            var object: [String: Any] = [:]
            if consume(125) { return object }
            while true {
                let key = try string()
                guard consume(58) else { throw ThreadOSSettingsCodecError.invalidJSON }
                let child = try value(depth: depth + 1)
                guard object[key] == nil else { throw ThreadOSSettingsCodecError.duplicateJSONKey }
                object[key] = child
                if consume(125) { return object }
                guard consume(44) else { throw ThreadOSSettingsCodecError.invalidJSON }
            }
        case 91:
            index += 1
            var array: [Any] = []
            if consume(93) { return array }
            while true {
                array.append(try value(depth: depth + 1))
                if consume(93) { return array }
                guard consume(44) else { throw ThreadOSSettingsCodecError.invalidJSON }
            }
        default:
            let start = index
            while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            switch token {
            case "true": return true
            case "false": return false
            case "null": return NSNull()
            default:
                guard token.range(of: "\\A-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?\\z", options: .regularExpression) != nil else { throw ThreadOSSettingsCodecError.invalidJSON }
                if !token.contains("."), !token.contains("e"), !token.contains("E"), let integer = Int(token) { return integer }
                // Keep noninteger syntax and out-of-range numbers distinct from JSON integers.
                return NonIntegerNumber()
            }
        }
    }
    private struct NonIntegerNumber {}
}
