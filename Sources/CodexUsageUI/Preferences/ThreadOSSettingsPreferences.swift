import Foundation

/// Local drafts are partitioned by project. They remain requests only and do
/// not record, infer, or grant native ThreadOS selection authority.
@MainActor public enum ThreadOSSettingsPreferences {
    private static let draftsKey = ApplicationPreferenceKey<Data?>(optionalData: "threados.settings.drafts.v2")
    private static let legacyDraftKey = ApplicationPreferenceKey<Data?>(optionalData: "threados.settings.draft.v1")

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
    private static func drafts(from preferences: ApplicationPreferences) -> [String: ThreadOSSettingsDraft] {
        guard let data = preferences.value(for: draftsKey), let values = try? JSONDecoder().decode([String: ThreadOSSettingsDraft].self, from: data) else { return [:] }
        // A corrupted or incomplete record must never become a selectable
        // project, nor overwrite the user's last valid local draft.
        return values.filter { $0.key == $0.value.project && $0.value.isLocallyValid }
    }
}
