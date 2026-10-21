import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("UMA 0.14 M4 interaction and accessibility hardening")
@MainActor
struct UMA014M4InteractionHardeningTests {
    @Test("Every Settings entry point routes through the one retained controller")
    func canonicalSettingsRouting() throws {
        let coordinator = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        let menus = try source("Sources/CodexUsageMonitor/App/ApplicationMenuController.swift")
        let main = try source("Sources/CodexUsageMonitor/App/NativeShellViews.swift")
        let quick = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")

        #expect(coordinator.contains("private let settingsWindowController"))
        #expect(coordinator.contains("settingsWindowController.showCanonicalWindow()"))
        #expect(menus.contains("coordinator?.showSettingsWindow()"))
        let settingsEntry = try #require(main.components(separatedBy: "identifier: \"uma.main.settings\"").dropFirst().first)
        #expect(settingsEntry.components(separatedBy: ".frame").first?.contains("action: openSettings") == true)
        #expect(quick.contains("headerButton(localized(\"Settings\""))
        #expect(!main.contains("SettingsWindowController()"))
        #expect(!quick.contains("SettingsWindowController()"))
    }

    @Test("Global controls are real, typed, localized, and provider-free")
    func settingsControlContract() throws {
        let settings = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let preferences = try source(
            "Sources/CodexUsageUI/Preferences/ApplicationPreferences.swift"
        )

        for identifier in [
            "uma.settings.general.launch-at-login",
            "uma.settings.general.language",
            "uma.settings.appearance.theme",
            "uma.settings.appearance.menu-value",
        ] {
            #expect(settings.contains(identifier))
        }
        #expect(settings.contains("Keep monitoring when windows close"))
        #expect(settings.contains("关闭窗口后继续监控"))
        #expect(settings.contains("setKeepMonitoringWhenWindowsClose"))
        #expect(!settings.contains("Window close behavior"))
        #expect(!settings.contains("Monitoring continues until you choose Quit UMA."))
        #expect(!settings.contains("isOn: .constant(true)"))
        #expect(preferences.contains("UMAApplicationAppearance"))
        #expect(preferences.contains("menuBarShowsRemaining"))
        #expect(!settings.contains("case .providers:"))
        #expect(!settings.contains("WorkBuddySettingsSection"))
    }

    @Test("Review fixtures expose coherent source authority for current provider state")
    func reviewFixtureSourceAuthorityContract() throws {
        let productState = try source(
            "Sources/CodexUsageUI/Models/ProviderProductState.swift"
        )

        #expect(productState.contains("sourceSummary: previewSourceSummary("))
        #expect(productState.contains("return .officialLocal"))
        #expect(productState.contains("return isEstimated ? .localSmartEstimate : .accuracySync"))
    }

    @Test("Appearance and menu value are application-owned, not view-local truth")
    func sharedAppearanceAndMenuBarContract() throws {
        let shell = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        let status = try source("Sources/CodexUsageMonitor/App/StatusBarController.swift")

        #expect(shell.contains("observeAppearance(in: runtime.preferences)"))
        #expect(shell.contains("NSApp.appearance = switch value"))
        #expect(status.contains("UMAApplicationPreferenceKeys.menuBarShowsRemaining"))
        #expect(status.contains("showsRemainingValue"))
    }

    @Test("Visible Quick Panel resizes when its shared reset-time preference changes")
    func quickPanelDisplayPreferenceUpdatesLayout() throws {
        let controller = try source(
            "Sources/CodexUsageMonitor/App/QuickPanelPopoverController.swift"
        )

        #expect(controller.contains("displayPreferenceObservation = preferences.observe"))
        #expect(controller.contains("UMAApplicationPreferenceKeys.quickPanelShowsReset.name"))
        #expect(controller.contains("updateContentSize(repositionIfVisible: true)"))
        #expect(controller.contains("displayPreferenceObservation?.cancel()"))
    }

    // Reset times are shown again, so the guard no longer asserts that the
    // rendering code is absent. It asserts the invariant that absence used to
    // buy: one gate decides whether a reset is shown, the row body and the
    // accessibility label both read it, and a hidden reset is therefore never
    // announced to VoiceOver while invisible on screen.
    @Test("Hidden reset times stay hidden from VoiceOver and login-item state refreshes on return")
    func accessibilityAndSystemSettingsReturnStaySynchronized() throws {
        let surfaces = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let quota = ProviderProductQuotaState(
            id: "fiveHour",
            kind: .fiveHour,
            compactLabel: "5H",
            value: .remainingPercent(42),
            precision: .exact,
            freshness: .fresh,
            comparison: .eligibleRemainingPercent(42),
            resetsAt: now.addingTimeInterval(7_200)
        )

        for language in [AppLanguage.english, .simplifiedChinese] {
            // Hidden means hidden everywhere, including the spoken label.
            #expect(
                AgentGlanceRow.resetLine(
                    quota: quota, showsReset: false, language: language, now: now
                ) == nil
            )
            // Shown only when the provider actually reported a reset.
            #expect(
                AgentGlanceRow.resetLine(
                    quota: quota, showsReset: true, language: language, now: now
                ) != nil
            )
            #expect(
                AgentGlanceRow.resetLine(
                    quota: nil, showsReset: true, language: language, now: now
                ) == nil
            )
        }

        // The spoken label must read the same gate the body does.
        #expect(surfaces.contains("if let resetLine { label += \", \\(resetLine)\" }"))
        #expect(surfaces.contains("guard showsReset, let resetsAt = quota?.resetsAt else { return nil }"))

        #expect(surfaces.contains("NSApplication.didBecomeActiveNotification"))
        #expect(surfaces.contains("model.refreshLaunchAtLoginState()"))
        #expect(surfaces.contains("launchAtLoginError = nil"))
    }

    @Test("Deterministic review surfaces use one injected reference date")
    func deterministicReviewClockContract() throws {
        let surfaces = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let renderer = try source("Sources/PreviewRendererTool/main.swift")

        #expect(surfaces.contains("private let referenceDate: Date?"))
        #expect(surfaces.contains("private var displayNow: Date { referenceDate ?? Date() }"))
        #expect(renderer.contains("referenceDate: M3RFixture.fixedNow"))
    }

    @Test("Wizard remains one shared-preference surface through repeated density cycles")
    func wizardDensityStress() {
        let preferences = ApplicationPreferences.inMemory()
        let suite = "uma014.m4.wizard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = DesktopAssistantPanelController(defaults: defaults)
        defer {
            controller.tearDown()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.bind(preferences: preferences)
        controller.update(cards: [wizardCard])

        for index in 0..<100 {
            let density: DesktopAssistantDensity = index.isMultiple(of: 3)
                ? .automatic
                : (index.isMultiple(of: 2) ? .regular : .minimalist)
            controller.setDensity(density)
            #expect(controller.density == density)
            #expect(
                preferences.value(for: UMAApplicationPreferenceKeys.assistantDensity)
                    == density.rawValue
            )
        }
        #expect(controller.assistantDragRecognizerCount == 1)
        #expect(controller.hasAssistantContextMenuEventRouter)
        #expect(!controller.hasWindowShadow)
    }

    @Test("Wizard display-relative position remains safe across missing displays")
    func wizardPositionFallbackContract() throws {
        let controller = try source(
            "Sources/CodexUsageMonitor/App/DesktopAssistantPanelController.swift"
        )
        let preferences = DesktopAssistantPosition(
            displayIdentifier: UInt32.max,
            horizontalFraction: -3,
            verticalFraction: 4
        )

        #expect(preferences.horizontalFraction == 0)
        #expect(preferences.verticalFraction == 1)
        #expect(controller.contains("screenForSavedPosition() ?? panel.screen"))
        #expect(controller.contains("clamped(proposed, to: visible)"))
        #expect(controller.contains("NSApplication.didChangeScreenParametersNotification"))
    }

    @Test("Accessible state is not color-only and motion/transparency remain system-driven")
    func accessibilityContract() throws {
        let surfaces = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let wizard = try source("Sources/CodexUsageUI/Views/DesktopAssistantView.swift")

        #expect(surfaces.contains(".accessibilityLabel(accessibilityLabel)"))
        #expect(surfaces.contains("case .needsAttention: localized(\"Needs attention\""))
        #expect(surfaces.contains("@Environment(\\.accessibilityReduceTransparency)"))
        #expect(wizard.contains("@Environment(\\.accessibilityReduceTransparency)"))
        #expect(wizard.contains(".accessibilityAction"))
        #expect(!wizard.contains("withAnimation"))
    }

    @Test("M4 review package is durable, runtime-enabled, and provider-free while rendering")
    func reviewPackageContract() throws {
        let script = try source("script/package_uma014_m4_review.sh")
        #expect(script.contains("UMA 0.14 M4 Review"))
        #expect(script.contains("/Volumes/HE/DEV/UMA/Packages/uma-0.14-m4-review-"))
        #expect(script.components(separatedBy: "render \"").count - 1 == 24)
        for scenario in [
            "settings-appearance",
            "settings-wizard",
            "settings-privacy",
            "wizard-context-menu",
            "main-narrow",
            "--reduce-transparency",
            "--increase-contrast",
            "--reduce-motion",
        ] {
            #expect(script.contains(scenario))
        }
        for prohibited in ["curl ", "notarytool", "security find", "osascript"] {
            #expect(!script.contains(prohibited))
        }
    }

    private var wizardCard: DesktopAssistantCard {
        DesktopAssistantCard(
            id: "codex.local",
            providerName: "Codex",
            connectionState: .connected,
            selectedWindowShortLabel: "5H",
            selectedWindowAccessibilityLabel: "five-hour window",
            resetText: "Resets later",
            usageValue: .finite(64),
            tintFraction: 0.64,
            severity: .normal,
            isStale: false
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
