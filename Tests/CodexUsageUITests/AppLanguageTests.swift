import Foundation
import Testing
@testable import CodexUsageUI

struct AppLanguageTests {
    @Test(arguments: ["zh-Hans-CN", "zh-Hant-TW", "zh"])
    func matchesChineseSystemLanguages(_ identifier: String) {
        #expect(AppLanguage.systemMatch(preferredLanguages: [identifier]) == .simplifiedChinese)
    }

    @Test(arguments: ["en-US", "fr-FR", "ja-JP"])
    func fallsBackToEnglishForOtherSystemLanguages(_ identifier: String) {
        #expect(AppLanguage.systemMatch(preferredLanguages: [identifier]) == .english)
    }

    @Test @MainActor
    func persistsFirstLaunchMatchAndKeepsUserSelection() throws {
        let suiteName = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunch = AppLanguage.resolveAndPersist(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"]
        )
        #expect(firstLaunch == .simplifiedChinese)

        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        let laterLaunch = AppLanguage.resolveAndPersist(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"]
        )
        #expect(laterLaunch == .english)
    }

    @Test
    func createsAnEnglishPreviewSnapshot() {
        let snapshot = UsageSnapshot.preview(language: .english)

        #expect(snapshot.periods.first?.title == "5-Hour Limit")
        #expect(snapshot.metrics.map(\.label) == ["Current Task", "Last 7 Days", "Lifetime"])
        #expect(snapshot.recentTasks.first?.tokenText == "Hidden")
    }

    @Test
    func resetWordingDistinguishesElapsedNowAndFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(AppLanguage.english.resetDescription(for: now.addingTimeInterval(-61), now: now).contains("passed"))
        #expect(AppLanguage.english.resetDescription(for: now, now: now).contains("just now"))
        #expect(AppLanguage.english.resetDescription(for: now.addingTimeInterval(30), now: now).contains("just now"))
        #expect(AppLanguage.english.resetDescription(for: now.addingTimeInterval(61), now: now).contains("in 2 min"))
    }
}
