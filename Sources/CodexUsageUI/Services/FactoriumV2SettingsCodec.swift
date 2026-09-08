import Foundation

/// Local V2 wire validation only. It neither sends a request nor establishes
/// native model, speed, or task-control state.
public enum FactoriumV2SettingsCodecError: Error, Equatable {
    case invalidPrefix, invalidJSON, invalidFields, invalidSelection, invalidReceipt, identityMismatch
}

public struct FactoriumV2ReceiptProjection: Equatable, Sendable {
    public let project: String
    public let id: String
    public let revision: Int
    public let status: String
    public let effectiveObserved: String
    public let manualRequired: Bool
}

public enum FactoriumV2SettingsCodec {
    public static func draft(fromWire input: String, catalog: ThreadOSModelCatalog? = nil, expectedProject: String? = nil) throws -> FactoriumV2SettingsDraft {
        guard input.hasPrefix("TOSCFG/2 ") else { throw FactoriumV2SettingsCodecError.invalidPrefix }
        let object = try strictObject(String(input.dropFirst("TOSCFG/2 ".count)))
        guard Set(object.keys) == Set(["apply", "cat", "id", "p", "preset", "rev", "roles", "workers"]),
              object["apply"] as? String == FactoriumV2SettingsDraft.apply,
              object["preset"] as? String == FactoriumV2SettingsDraft.preset,
              let project = object["p"] as? String,
              let id = object["id"] as? String,
              let revision = strictInt(object["rev"]),
              let rolesValue = object["roles"] as? [String: Any],
              let workersValue = object["workers"] as? [String: Any]
        else { throw FactoriumV2SettingsCodecError.invalidFields }
        let catalog = try catalog ?? ThreadOSSettingsCodec.loadCatalog()
        guard object["cat"] as? String == catalog.revision else { throw FactoriumV2SettingsCodecError.invalidPrefix }
        guard ThreadOSSettingsDraft.isToken(project), ThreadOSSettingsDraft.isToken(id), (1...1_000_000).contains(revision) else { throw FactoriumV2SettingsCodecError.invalidJSON }
        guard expectedProject == nil || expectedProject == project else { throw FactoriumV2SettingsCodecError.identityMismatch }
        guard Set(rolesValue.keys) == Set(FactoriumV2Role.allCases.map(\.rawValue)) else { throw FactoriumV2SettingsCodecError.invalidReceipt }
        guard workersValue.count == 2, workersValue["coder"] != nil, workersValue["reviewer"] != nil else { throw FactoriumV2SettingsCodecError.invalidSelection }

        var roles: [FactoriumV2Role: FactoriumV2RoleSetting] = [:]
        for role in FactoriumV2Role.allCases {
            guard let value = rolesValue[role.rawValue] as? [String: Any] else { throw FactoriumV2SettingsCodecError.invalidJSON }
            if role == .leader, Set(value.keys) == Set(["preserve"]), strictBool(value["preserve"]) == true {
                roles[role] = .init(preserve: true, selection: FactoriumV2SettingsDraft.defaultRoles[.leader]!.selection)
            } else {
                roles[role] = .init(selection: try selection(value, leader: role == .leader, catalog: catalog))
            }
        }
        func slots(_ role: FactoriumV2Role) throws -> [FactoriumV2WorkerSlot] {
            guard let values = workersValue[role.rawValue] as? [Any], values.count == 3, let parent = roles[role]?.selection else { throw FactoriumV2SettingsCodecError.invalidReceipt }
            return try values.map { item in
                guard let value = item as? [String: Any], Set(value.keys) == Set(["enabled", "model", "effort", "speed"]), let enabled = strictBool(value["enabled"]), let model = value["model"] as? String, let effort = value["effort"] as? String, let speed = value["speed"] as? String else { throw FactoriumV2SettingsCodecError.invalidFields }
                let inherited = model == "inherit" && effort == "inherit" && speed == "inherit"
                guard inherited || (![model, effort, speed].contains("inherit")) else { throw FactoriumV2SettingsCodecError.invalidSelection }
                return inherited
                    ? .init(enabled: enabled, inherits: true, selection: parent)
                    : .init(enabled: enabled, inherits: false, selection: try selection(["model": model, "effort": effort, "speed": speed], leader: false, catalog: catalog), hasCustomSelection: true)
            }
        }
        let draft = FactoriumV2SettingsDraft(project: project, id: id, revision: revision, roles: roles, coderWorkers: try slots(.coder), reviewerWorkers: try slots(.reviewer))
        guard draft.isLocallyValid else { throw FactoriumV2SettingsCodecError.invalidSelection }
        return draft
    }

    /// Accepts only a complete V2 pending-selection receipt for the currently
    /// displayed local draft. A valid receipt remains local acknowledgement;
    /// it never upgrades effective native observation.
    public static func receiptProjection(_ text: String, matching draft: FactoriumV2SettingsDraft) throws -> FactoriumV2ReceiptProjection {
        let json = text.hasPrefix("TOSACK/2 ") ? String(text.dropFirst("TOSACK/2 ".count)) : text
        let object = try strictObject(json)
        let required: Set<String> = ["schema", "protocol", "authority", "status", "effective_from", "p", "id", "rev", "requested", "configured", "effective_observed", "manual_required"]
        guard Set(object.keys) == required,
              object["schema"] as? String == "threados.settings-receipt.v2",
              object["protocol"] as? String == "TOSACK/2",
              object["authority"] as? String == "settings_do_not_grant_authority",
              object["status"] as? String == "pending_native_selection",
              object["effective_from"] as? String == "next-wave",
              object["effective_observed"] as? String == "unknown",
              strictBool(object["manual_required"]) == true,
              let project = object["p"] as? String, let id = object["id"] as? String, let revision = strictInt(object["rev"]),
              project == draft.project, id == draft.id, revision == draft.revision,
              let requested = object["requested"] as? [String: Any], let configured = object["configured"] as? [String: Any]
        else { throw FactoriumV2SettingsCodecError.identityMismatch }
        guard "TOSCFG/2 " + canonicalJSON(requested) == (try draft.canonicalRequest()) else { throw FactoriumV2SettingsCodecError.identityMismatch }
        try validateConfigured(configured, draft: draft, requested: requested)
        return .init(project: project, id: id, revision: revision, status: "pending_native_selection", effectiveObserved: "unknown", manualRequired: true)
    }

    private static func validateConfigured(_ configured: [String: Any], draft: FactoriumV2SettingsDraft, requested: [String: Any]) throws {
        let keys: Set<String> = ["protocol", "p", "id", "rev", "catalog_revision", "preset", "apply", "roles", "workers", "requested", "coding_workers", "review_workers", "coder_mode", "reviewer_mode", "effective_observed", "manual_required"]
        guard Set(configured.keys) == keys,
              configured["protocol"] as? String == "TOSCFG/2", configured["p"] as? String == draft.project,
              configured["id"] as? String == draft.id, strictInt(configured["rev"]) == draft.revision,
              configured["catalog_revision"] as? String == FactoriumV2SettingsDraft.catalogRevision,
              configured["preset"] as? String == "custom", configured["apply"] as? String == "next-wave",
              configured["effective_observed"] as? String == "unknown", strictBool(configured["manual_required"]) == true,
              let nestedRequested = configured["requested"] as? [String: Any], canonicalJSON(nestedRequested) == canonicalJSON(requested),
              let roles = configured["roles"] as? [String: Any], Set(roles.keys) == Set(FactoriumV2Role.allCases.map(\.rawValue)),
              let workers = configured["workers"] as? [String: Any], Set(workers.keys) == Set(["coder", "reviewer"])
        else { throw FactoriumV2SettingsCodecError.invalidReceipt }
        guard let leader = roles["leader"] as? [String: Any], let leaderSetting = draft.roles[.leader] else { throw FactoriumV2SettingsCodecError.invalidJSON }
        if leaderSetting.preserve {
            guard leader.count == 1, leader["configured"] as? String == "unchanged" else { throw FactoriumV2SettingsCodecError.invalidJSON }
        } else {
            guard isExactConfiguredSelection(leader, matching: leaderSetting.selection) else { throw FactoriumV2SettingsCodecError.invalidJSON }
        }
        for role in FactoriumV2Role.allCases where role != .leader {
            guard let expected = draft.roles[role]?.selection, let value = roles[role.rawValue] as? [String: Any], isExactConfiguredSelection(value, matching: expected) else { throw FactoriumV2SettingsCodecError.invalidFields }
        }
        for role in [FactoriumV2Role.coder, .reviewer] {
            guard let values = workers[role.rawValue] as? [Any], values.count == 3 else { throw FactoriumV2SettingsCodecError.invalidReceipt }
            for (index, value) in values.enumerated() {
                guard let item = value as? [String: Any], Set(item.keys) == Set(["enabled", "model", "effort", "speed"]), strictBool(item["enabled"]) == draft.workers(for: role)[index].enabled, selectionMatches(item, draft.resolvedSlot(draft.workers(for: role)[index], parent: role)) else { throw FactoriumV2SettingsCodecError.invalidSelection }
            }
            let enabled = draft.workers(for: role).filter(\.enabled).count
            let countKey = role == .coder ? "coding_workers" : "review_workers"
            let modeKey = role == .coder ? "coder_mode" : "reviewer_mode"
            guard strictInt(configured[countKey]) == enabled, configured[modeKey] as? String == (enabled == 0 ? "DIRECT" : "WORKERS") else { throw FactoriumV2SettingsCodecError.identityMismatch }
        }
    }

    private static func selection(_ value: [String: Any], leader: Bool, catalog: ThreadOSModelCatalog) throws -> FactoriumV2Selection {
        guard Set(value.keys) == Set(["model", "effort", "speed"]), let model = value["model"] as? String, let effort = value["effort"] as? String, let speed = value["speed"] as? String,
              FactoriumV2SettingsDraft.availableModels(catalog: catalog).contains(model),
              FactoriumV2SettingsDraft.availableEfforts(model: model, leader: leader, catalog: catalog).contains(effort), ["fast", "standard"].contains(speed)
        else { throw FactoriumV2SettingsCodecError.invalidSelection }
        return .init(model: model, effort: effort, speed: speed)
    }

    private static func selectionMatches(_ value: [String: Any], _ selection: FactoriumV2Selection) -> Bool {
        value["model"] as? String == selection.model && value["effort"] as? String == selection.effort && value["speed"] as? String == selection.speed
    }
    /// Configured roles are a distinct receipt shape from workers. Workers
    /// carry `enabled`; explicit roles must contain precisely these fields.
    private static func isExactConfiguredSelection(_ value: [String: Any], matching selection: FactoriumV2Selection) -> Bool {
        Set(value.keys) == Set(["model", "effort", "speed"]) && selectionMatches(value, selection)
    }
    private static func strictObject(_ json: String) throws -> [String: Any] {
        do { return try ThreadOSSettingsCodec.strictObject(json) }
        catch { throw FactoriumV2SettingsCodecError.invalidJSON }
    }
    private static func strictInt(_ value: Any?) -> Int? { guard let value, type(of: value) == Int.self else { return nil }; return value as? Int }
    private static func strictBool(_ value: Any?) -> Bool? { guard let value, type(of: value) == Bool.self else { return nil }; return value as? Bool }
    private static func canonicalJSON(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }
}
