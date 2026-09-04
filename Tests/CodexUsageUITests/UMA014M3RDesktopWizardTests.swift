import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("UMA014 M3R Desktop Wizard")
struct UMA014M3RDesktopWizardTests {
    @Test("Regular restores the accepted Wizard composition and keeps Minimalist unchanged")
    func regularPresentationContract() throws {
        let regular = DesktopAssistantContentContract.visibleFields(for: .regular)
        #expect(regular.contains(.providerConnectionMark))
        #expect(regular.contains(.providerName))
        #expect(regular.contains(.planTier))
        #expect(regular.contains(.selectedWindow))
        #expect(regular.contains(.reset))
        #expect(regular.contains(.percentage))
        #expect(
            DesktopAssistantContentContract.visibleFields(for: .minimalist)
                == [.providerConnectionMark, .percentage]
        )
        let source = try sourceText("Sources/CodexUsageUI/Views/DesktopAssistantView.swift")
        #expect(source.contains("private var regularContent: some View"))
        #expect(source.contains("sourceMark(diameter: 24)"))
        #expect(!source.contains("style: .desktopWizardRegular"))
        #expect(!source.contains("case connectivityLight"))
        #expect(!source.contains("case remainingRail"))
    }

    @MainActor
    @Test("Desktop Wizard binds to the application preference authority")
    func typedPreferenceBinding() {
        let suite = "UMA014M3R.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suite)!
        let initialPreferences = ApplicationPreferences(userDefaults: isolatedDefaults)
        let applicationPreferences = ApplicationPreferences.inMemory(seed: [
            DesktopAssistantPreferences.Keys.isEnabled: true,
            DesktopAssistantPreferences.Keys.isAlwaysOnTop: true,
            DesktopAssistantPreferences.Keys.density: DesktopAssistantDensity.regular.rawValue,
        ])
        let controller = DesktopAssistantPanelController(defaults: isolatedDefaults)
        defer {
            controller.tearDown()
            isolatedDefaults.removePersistentDomain(forName: suite)
        }

        controller.bind(preferences: applicationPreferences)
        controller.setAlwaysOnTop(false)
        controller.setDensity(.minimalist)

        #expect(
            applicationPreferences.value(
                for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop
            ) == false
        )
        #expect(
            applicationPreferences.value(for: UMAApplicationPreferenceKeys.assistantDensity)
                == DesktopAssistantDensity.minimalist.rawValue
        )
        #expect(
            initialPreferences.value(for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop)
                == true
        )

        applicationPreferences.set(
            false,
            for: UMAApplicationPreferenceKeys.assistantEnabled
        )
        applicationPreferences.set(
            DesktopAssistantDensity.regular.rawValue,
            for: UMAApplicationPreferenceKeys.assistantDensity
        )

        #expect(!controller.isEnabled)
        #expect(controller.density == .regular)
    }

    @MainActor
    @Test("Context menu restores bounded Desktop Wizard controls")
    func contextMenuContract() throws {
        let suite = "UMA014M3R.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = DesktopAssistantPanelController(defaults: defaults)
        defer {
            controller.tearDown()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.update(cards: [card])

        let menu = try #require(controller.assistantPanelForTesting.contentView?.menu)

        #expect(menu.identifier?.rawValue == "uma.desktop-wizard.context")
        #expect(menu.items.map(\.title).contains("Enabled"))
        #expect(menu.items.map(\.title).contains("Always on Top"))
        #expect(menu.items.map(\.title).contains("Density"))
        #expect(
            ["Show Desktop Wizard", "Hide Desktop Wizard"]
                .contains(menu.items.first?.title ?? "")
        )
        let densityMenu = try #require(menu.item(withTitle: "Density")?.submenu)
        #expect(densityMenu.items.map(\.title) == ["Automatic", "Regular", "Minimalist"])
        #expect(densityMenu.item(withTitle: "Automatic")?.state == .on)
    }

    @MainActor
    @Test("Context menu actions update the shared Wizard preferences")
    func contextMenuActions() throws {
        let suite = "UMA014M3R.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = DesktopAssistantPanelController(defaults: defaults)
        defer {
            controller.tearDown()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.update(cards: [card])

        let menu = try #require(controller.assistantPanelForTesting.contentView?.menu)
        let alwaysOnTop = try #require(menu.item(withTitle: "Always on Top"))
        let previousAlwaysOnTop = controller.isAlwaysOnTop
        let alwaysOnTopAction = try #require(alwaysOnTop.action)
        #expect(NSApplication.shared.sendAction(
            alwaysOnTopAction,
            to: alwaysOnTop.target,
            from: alwaysOnTop
        ))
        #expect(controller.isAlwaysOnTop == !previousAlwaysOnTop)

        let densityMenu = try #require(menu.item(withTitle: "Density")?.submenu)
        let minimalist = try #require(densityMenu.item(withTitle: "Minimalist"))
        let minimalistAction = try #require(minimalist.action)
        #expect(NSApplication.shared.sendAction(
            minimalistAction,
            to: minimalist.target,
            from: minimalist
        ))
        #expect(controller.density == .minimalist)
        #expect(
            defaults.string(forKey: DesktopAssistantPreferences.Keys.density)
                == DesktopAssistantDensity.minimalist.rawValue
        )
    }

    @MainActor
    @Test("Context menu follows the shared Simplified Chinese preference")
    func localizedContextMenuContract() throws {
        let suite = "UMA014M3R.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = ApplicationPreferences(userDefaults: defaults)
        preferences.set(
            AppLanguage.simplifiedChinese.rawValue,
            for: UMAApplicationPreferenceKeys.language
        )
        let controller = DesktopAssistantPanelController(defaults: defaults)
        defer {
            controller.tearDown()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.update(cards: [card])

        let menu = try #require(controller.assistantPanelForTesting.contentView?.menu)
        #expect(["显示桌面向导", "隐藏桌面向导"].contains(menu.items.first?.title ?? ""))
        #expect(menu.item(withTitle: "已启用") != nil)
        #expect(menu.item(withTitle: "始终置顶") != nil)
        let densityMenu = try #require(menu.item(withTitle: "密度")?.submenu)
        #expect(densityMenu.items.map(\.title) == ["自动", "常规", "极简"])
    }

    @Test("Wizard selection routes directly to the canonical Agent workspace")
    func selectionUsesCanonicalMainNavigation() throws {
        let shell = try sourceText("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        #expect(shell.contains("assistantController.setSelectionHandler"))
        #expect(shell.contains("self?.showAgent(providerID)"))
        #expect(!shell.contains("showQuickPanel(expandingProviderID: providerID)"))
    }

    @Test("Desktop Wizard retains its localized card contract after visual restoration")
    func localizedCardContract() {
        let localizedCard = DesktopAssistantCard(
            id: "claude.browserSync",
            providerName: "Claude",
            connectionState: .connected,
            selectedWindowShortLabel: "5H",
            selectedWindowAccessibilityLabel: "五小时额度窗口",
            usageValue: .finite(62),
            severity: .normal,
            isStale: false,
            language: .simplifiedChinese
        )
        #expect(localizedCard.language == .simplifiedChinese)
    }

    @Test("Main, Quick, and Wizard share urgency rails without full-row tint washes")
    func sharedVisualLanguageContract() throws {
        let source = try sourceText("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let wizard = try sourceText("Sources/CodexUsageUI/Views/DesktopAssistantView.swift")
        #expect(source.contains("RemainingUsageVisualPolicy.color(for: percent)"))
        #expect(source.contains("Color(nsColor: .controlBackgroundColor)"))
        #expect(!source.contains("DesktopAssistantTintGeometry.stops("))
        #expect(!source.contains("DesktopAssistantTintOpacity.value("))
        #expect(!source.contains("Capsule()\n                        .fill(.primary.opacity(0.09))"))
        #expect(wizard.contains("private var valueColor: Color"))
        #expect(wizard.contains("Remaining urgency belongs to the shared bar palette"))
        #expect(!wizard.contains("case .warning, .critical:"))
    }

    @MainActor
    @Test("Context-menu controls preserve the accepted panel interaction architecture")
    func interactionArchitecture() {
        let suite = "UMA014M3R.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = DesktopAssistantPanelController(defaults: defaults)
        defer {
            controller.tearDown()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.update(cards: [card])

        #expect(controller.assistantDragRecognizerCount == 1)
        #expect(controller.assistantDragDelaysClicks)
        #expect(controller.hasAssistantContextMenuEventRouter)
        #expect(!controller.usesWindowBackgroundDragging)
        #expect(!controller.hasWindowShadow)
        #expect(controller.assistantPanelForTesting.contentView?.layer?.borderWidth == 0)
        #expect(controller.assistantPanelForTesting.contentView?.layer?.shadowOpacity == 0)
    }

    @MainActor
    @Test("Panel event routing presents the Wizard menu for right-click and Control-click")
    func secondaryClickEventRouting() throws {
        let suite = "UMA014M3R.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = DesktopAssistantPanelController(defaults: defaults)
        defer {
            controller.tearDown()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.update(cards: [card])

        let panel = controller.assistantPanelForTesting
        var presentedEventTypes: [NSEvent.EventType] = []
        var presentedMenus: [NSMenu] = []
        panel.assistantContextMenuPresenter = { menu, event, _ in
            presentedMenus.append(menu)
            presentedEventTypes.append(event.type)
        }

        let rightClick = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 1,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let controlClick = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [.control],
            timestamp: 2,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        ))
        let ordinaryClick = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 3,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 3,
            clickCount: 1,
            pressure: 1
        ))

        #expect(DesktopAssistantPanel.isAssistantContextMenuEvent(rightClick))
        #expect(DesktopAssistantPanel.isAssistantContextMenuEvent(controlClick))
        #expect(!DesktopAssistantPanel.isAssistantContextMenuEvent(ordinaryClick))

        panel.sendEvent(rightClick)
        panel.sendEvent(controlClick)

        #expect(presentedEventTypes == [.rightMouseDown, .leftMouseDown])
        #expect(presentedMenus.count == 2)
        #expect(presentedMenus.allSatisfy {
            $0.identifier?.rawValue == "uma.desktop-wizard.context"
                && $0.item(withTitle: "Always on Top") != nil
                && $0.item(withTitle: "Density")?.submenu != nil
        })
    }

    private var card: DesktopAssistantCard {
        DesktopAssistantCard(
            id: "codex.local",
            providerName: "Codex",
            planLabel: "Plus",
            connectionState: .connected,
            selectedWindowShortLabel: "5H",
            selectedWindowAccessibilityLabel: "five-hour window",
            resetText: "Resets later",
            usageValue: .estimated(64),
            tintFraction: 0.64,
            severity: .normal,
            isStale: false
        )
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
