import Foundation

public enum ThreadOSRole: String, CaseIterable, Codable, Sendable {
    case leader = "LEADER", qa = "QA", foreman = "FOREMAN", codingWorker = "CODING_WORKER", reviewer = "REVIEWER"
    public var requestKey: String { switch self { case .leader: "l"; case .qa: "q"; case .foreman: "f"; case .codingWorker: "w"; case .reviewer: "r" } }
}

public struct ThreadOSRoleSelection: Codable, Equatable, Sendable {
    public var model: String
    public var reasoningEffort: String
    public init(model: String, reasoningEffort: String) { self.model = model; self.reasoningEffort = reasoningEffort }
}

/// A local settings request. It is intentionally a draft: it has no native-selection authority.
public struct ThreadOSSettingsDraft: Codable, Equatable, Sendable {
    public var project: String
    public var id: String
    public var revision: Int
    public var preset: String
    public var codingWorkers: Int
    public var reviewWorkers: Int
    public var tier: String
    public var customRoles: [ThreadOSRole: ThreadOSRoleSelection]
    private enum CodingKeys: String, CodingKey { case project, id, revision, preset, codingWorkers, reviewWorkers, tier, customRoles }
    public static var defaultCustomRoles: [ThreadOSRole: ThreadOSRoleSelection] {
        guard let catalog = try? ThreadOSSettingsCodec.loadCatalog(), let preset = catalog.presets["astra-balanced"] else { return [:] }
        return Dictionary(uniqueKeysWithValues: ThreadOSRole.allCases.compactMap { role in
            guard let spec = preset.roles[role.rawValue] else { return nil }
            return (role, .init(model: spec.selection ?? spec.model, reasoningEffort: spec.reasoningEffort))
        })
    }
    public init(project: String = "", id: String = "cfg-" + UUID().uuidString.lowercased(), revision: Int = 1, preset: String = "astra-balanced", codingWorkers: Int = 3, reviewWorkers: Int = 3, tier: String = "standard", customRoles: [ThreadOSRole: ThreadOSRoleSelection] = [:]) {
        self.project = project; self.id = id; self.revision = revision; self.preset = preset; self.codingWorkers = codingWorkers; self.reviewWorkers = reviewWorkers; self.tier = tier; self.customRoles = customRoles
    }
    public var isValidProject: Bool { Self.isToken(project) }
    public var isLocallyValid: Bool { (try? ThreadOSSettingsCodec.canonicalRequest(self)) != nil }
    public static func isToken(_ value: String) -> Bool { value.range(of: "\\A[A-Za-z][A-Za-z0-9_-]{0,63}\\z", options: .regularExpression) != nil }
    public var canAdvanceRevision: Bool { (1..<1_000_000).contains(revision) }
    /// Failed advancement leaves the last valid identity untouched.
    @discardableResult public mutating func changed() -> Bool {
        guard canAdvanceRevision else { return false }
        revision += 1
        return true
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        project = try c.decode(String.self, forKey: .project); id = try c.decode(String.self, forKey: .id)
        revision = try c.decode(Int.self, forKey: .revision); preset = try c.decode(String.self, forKey: .preset)
        codingWorkers = try c.decode(Int.self, forKey: .codingWorkers); reviewWorkers = try c.decode(Int.self, forKey: .reviewWorkers)
        tier = try c.decode(String.self, forKey: .tier); customRoles = try c.decodeIfPresent([ThreadOSRole: ThreadOSRoleSelection].self, forKey: .customRoles) ?? [:]
    }
}
