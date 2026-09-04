import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("UMA 0.14 M3R global Settings rebuild")
@MainActor
struct UMA014M3RSettingsRebuildTests {
    @Test("Settings and other surfaces observe one typed preference truth")
    func settingsSynchronizesBidirectionally() {
        let preferences = ApplicationPreferences.inMemory(seed: [
            DesktopAssistantPreferences.Keys.isEnabled: true,
            DesktopAssistantPreferences.Keys.isAlwaysOnTop: false,
            DesktopAssistantPreferences.Keys.density:
                DesktopAssistantDensity.regular.rawValue,
        ])
        let settings = GlobalSettingsViewModel(preferences: preferences)
        let secondSurface = GlobalSettingsViewModel(preferences: preferences)

        #expect(settings.assistantEnabled)
        #expect(!settings.assistantAlwaysOnTop)
        #expect(settings.assistantDensity == .regular)

        settings.setAssistantEnabled(false)
        settings.setAssistantAlwaysOnTop(true)
        settings.setAssistantDensity(.minimalist)

        #expect(!preferences.value(for: UMAApplicationPreferenceKeys.assistantEnabled))
        #expect(preferences.value(for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop))
        #expect(
            preferences.value(for: UMAApplicationPreferenceKeys.assistantDensity)
                == DesktopAssistantDensity.minimalist.rawValue
        )
        #expect(!secondSurface.assistantEnabled)
        #expect(secondSurface.assistantAlwaysOnTop)
        #expect(secondSurface.assistantDensity == .minimalist)

        preferences.set(true, for: UMAApplicationPreferenceKeys.assistantEnabled)
        preferences.set(
            DesktopAssistantDensity.automatic.rawValue,
            for: UMAApplicationPreferenceKeys.assistantDensity
        )

        #expect(settings.assistantEnabled)
        #expect(settings.assistantDensity == .automatic)
        #expect(secondSurface.assistantEnabled)
        #expect(secondSurface.assistantDensity == .automatic)
    }

    @Test("Settings fails closed to Automatic for an unknown legacy density")
    func invalidDensityUsesSafeDefault() {
        let preferences = ApplicationPreferences.inMemory(seed: [
            DesktopAssistantPreferences.Keys.density: "future-layout",
        ])
        let settings = GlobalSettingsViewModel(preferences: preferences)

        #expect(settings.assistantDensity == .automatic)

        preferences.set(
            DesktopAssistantDensity.regular.rawValue,
            for: UMAApplicationPreferenceKeys.assistantDensity
        )
        #expect(settings.assistantDensity == .regular)
    }

    @Test("Settings root is stable global navigation with no provider controls")
    func globalSurfaceContract() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageUI/Views/AgentSurfaceViews.swift"
            ),
            encoding: .utf8
        )
        let settings = try #require(
            source.split(separator: "public struct GlobalSettingsSurface").last
        )

        #expect(settings.contains("HStack(spacing: 0)"))
        #expect(settings.contains(".listStyle(.sidebar)"))
        #expect(settings.contains("uma.settings.surface"))
        #expect(settings.contains("uma.settings.detail.\\(navigation.pane.id)"))
        #expect(!settings.contains("NavigationSplitView"))
        #expect(!settings.contains("case providers"))
        #expect(!settings.contains("Accuracy Sync"))
        #expect(!settings.contains("Button(\"Connect\""))
    }

    @Test("Canonical Settings controller keeps one window across repeated routes")
    func settingsWindowIsStableAcrossOneHundredCycles() {
        let store = UsageStore.preview(language: .english)
        let controller = SettingsWindowController()
        controller.attach(store: store, preferences: .inMemory())
        let identity = controller.windowIdentityForTesting

        for index in 0..<100 {
            let pane = GlobalSettingsPane.allCases[index % GlobalSettingsPane.allCases.count]
            controller.selectPaneForTesting(pane)
            controller.showCanonicalWindow()
            #expect(controller.hasReadyContentForTesting)
            #expect(controller.selectedPaneForTesting == pane)
            controller.closeCanonicalWindow()
            #expect(controller.selectedPaneForTesting == pane)
        }

        #expect(controller.windowIdentityForTesting == identity)
        #expect(controller.attachedStoreIdentityForTesting == ObjectIdentifier(store))
        controller.tearDown()
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
