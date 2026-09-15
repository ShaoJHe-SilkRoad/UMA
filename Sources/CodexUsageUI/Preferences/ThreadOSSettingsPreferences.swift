import Foundation

/// Local drafts are partitioned by project. They remain requests only and do
/// not record, infer, or grant native ThreadOS selection authority.
@MainActor public enum ThreadOSSettingsPreferences {
    private static let draftsKey = ApplicationPreferenceKey<Data?>(optionalData: "threados.settings.drafts.v2")
    private static let legacyDraftKey = ApplicationPreferenceKey<Data?>(optionalData: "threados.settings.draft.v1")
    private static let factoriumV2DraftsKey = ApplicationPreferenceKey<Data?>(optionalData: "threados.factorium.v2.drafts.v1")
    private static let factoriumV2LegacySnapshotsKey = ApplicationPreferenceKey<Data?>(optionalData: "threados.factorium.v2.legacy-snapshots.v1")
    private static let factoriumV2SelectedProjectKey = ApplicationPreferenceKey<String?>(optional: "threados.factorium.v2.selected-project.v1")
    private static let factoriumV2ExpandedGroupsKey = ApplicationPreferenceKey<Data?>(optionalData: "threados.factorium.v2.expanded-groups.v1")

    public static func projects(from preferences: ApplicationPreferences) -> [String] { drafts(from: preferences).keys.sorted() }
    public static func load(project: String, from preferences: ApplicationPreferences) -> ThreadOSSettingsDraft? { drafts(from: preferences)[project] }
    public static func load(from preferences: ApplicationPreferences) -> ThreadOSSettingsDraft {
        if let first = projects(from: preferences).first, let draft = load(project: first, from: preferences) { return draft }
        if let data = preferences.value(for: legacyDraftKey), let draft = try? JSONDecoder().decode(ThreadOSSettingsDraft.self, from: data), draft.isLocallyValid { return draft }
        return ThreadOSSettingsDraft()
    }
    public static func save(_ draft: ThreadOSSettingsDraft, to preferences: ApplicationPreferences) {
        guard draft.isLocallyValid else { return }
        var values = drafts(from: preferences); values[draft.project] = draft
        preferences.set(try? JSONEncoder().encode(values), for: draftsKey)
    }

    /// Factorium V2 drafts are isolated from the established V1 store. A V1
    /// draft remains intact until the user explicitly converts it.
    public static func factoriumV2Projects(from preferences: ApplicationPreferences) -> [String] {
        factoriumV2Drafts(from: preferences).keys.sorted()
    }

    public static func loadFactoriumV2(project: String, from preferences: ApplicationPreferences) -> FactoriumV2SettingsDraft? {
        factoriumV2Drafts(from: preferences)[project]
    }

    public static func selectedFactoriumV2Project(from preferences: ApplicationPreferences) -> String? {
        preferences.value(for: factoriumV2SelectedProjectKey)
    }

    public static func saveFactoriumV2SelectedProject(_ project: String?, to preferences: ApplicationPreferences) {
        preferences.set(project, for: factoriumV2SelectedProjectKey)
    }

    public static func factoriumV2ExpandedGroups(project: String, from preferences: ApplicationPreferences) -> Set<FactoriumV2Role>? {
        guard let data = preferences.value(for: factoriumV2ExpandedGroupsKey),
              let stored = try? JSONDecoder().decode([String: [String]].self, from: data),
              let values = stored[project]
        else { return nil }
        return Set(values.compactMap(FactoriumV2Role.init(rawValue:)))
    }

    public static func saveFactoriumV2ExpandedGroups(_ groups: Set<FactoriumV2Role>, project: String, to preferences: ApplicationPreferences) {
        guard ThreadOSSettingsDraft.isToken(project) else { return }
        var stored: [String: [String]] = [:]
        if let data = preferences.value(for: factoriumV2ExpandedGroupsKey) {
            stored = (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
        }
        stored[project] = groups.map(\.rawValue).sorted()
        preferences.set(try? JSONEncoder().encode(stored), for: factoriumV2ExpandedGroupsKey)
    }

    public static func saveFactoriumV2(_ draft: FactoriumV2SettingsDraft, to preferences: ApplicationPreferences) {
        guard draft.isLocallyValid else { return }
        var values = factoriumV2Drafts(from: preferences)
        values[draft.project] = draft
        preferences.set(try? JSONEncoder().encode(values), for: factoriumV2DraftsKey)
    }
    /// Retains the selected Fast-bearing V2 source before an explicit Standard conversion.
    public static func loadFactoriumV2LegacySnapshot(project: String, from preferences: ApplicationPreferences) -> FactoriumV2SettingsDraft? {
        factoriumV2LegacySnapshots(from: preferences)[project]
    }
    public static func saveFactoriumV2LegacySnapshot(_ draft: FactoriumV2SettingsDraft, to preferences: ApplicationPreferences) {
        guard draft.isLocallyValid else { return }
        var values = factoriumV2LegacySnapshots(from: preferences); values[draft.project] = draft
        preferences.set(try? JSONEncoder().encode(values), for: factoriumV2LegacySnapshotsKey)
    }
    private static func drafts(from preferences: ApplicationPreferences) -> [String: ThreadOSSettingsDraft] {
        guard let data = preferences.value(for: draftsKey), let values = try? JSONDecoder().decode([String: ThreadOSSettingsDraft].self, from: data) else { return [:] }
        // A corrupted or incomplete record must never become a selectable
        // project, nor overwrite the user's last valid local draft.
        return values.filter { $0.key == $0.value.project && $0.value.isLocallyValid }
    }

    private static func factoriumV2Drafts(from preferences: ApplicationPreferences) -> [String: FactoriumV2SettingsDraft] {
        guard let data = preferences.value(for: factoriumV2DraftsKey), let values = try? JSONDecoder().decode([String: FactoriumV2SettingsDraft].self, from: data) else { return [:] }
        return values.filter { $0.key == $0.value.project && $0.value.isLocallyValid }
    }
    private static func factoriumV2LegacySnapshots(from preferences: ApplicationPreferences) -> [String: FactoriumV2SettingsDraft] {
        guard let data = preferences.value(for: factoriumV2LegacySnapshotsKey), let values = try? JSONDecoder().decode([String: FactoriumV2SettingsDraft].self, from: data) else { return [:] }
        return values.filter { $0.key == $0.value.project && $0.value.isLocallyValid }
    }
}
