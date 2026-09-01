import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("UMA 0.14 M1 native shell")
struct UMA014M1NativeShellTests {
    @Test("Ordinary app is Dock eligible while machine verifiers remain accessory")
    func activationPolicyIsPurposeScoped() throws {
        let app = try source("Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift")
        #expect(app.contains("application.setActivationPolicy(.regular)"))
        #expect(app.contains("NSApp.setActivationPolicy(.regular)"))
        #expect(app.components(separatedBy: "setActivationPolicy(.accessory)").count - 1 == 2)
        #expect(app.contains("applicationShouldTerminateAfterLastWindowClosed"))
        #expect(app.contains("false\n    }"))
        let shell = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        #expect(shell.contains("passed: runtimeAttached"))
        #expect(shell.contains("&& nativeShell.activationPolicyRegular"))
        #expect(shell.contains("runtimeAttached: Bool"))
        #expect(shell.contains("firstFailure: runtimeAttached ? nil : \"RUNTIME_COMPOSITION_FAILED\""))
        #expect(app.contains("await self.finishShellDiagnostic(runtimeAttached: false)"))
    }

    @Test("App shell is the sole owner of all four surfaces and one shared runtime")
    func coordinatorOwnsSurfacesAndRuntime() throws {
        let shell = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        for required in [
            "private let mainWindowController: MainWindowController",
            "private let settingsWindowController: SettingsWindowController",
            "private let statusBarController: StatusBarController",
            "private let assistantController: DesktopAssistantPanelController",
            "private var runtime: UsageMonitorRuntime?",
            "mainWindowController.attach(store: runtime.store)",
            "settingsWindowController.attach(store: runtime.store)",
        ] {
            #expect(shell.contains(required))
        }
        #expect(shell.components(separatedBy: "UsageMonitorRuntime.live(").count == 1)

        let app = try source("Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift")
        #expect(app.components(separatedBy: "UsageMonitorRuntime.live(").count - 1 == 1)
    }

    @Test("Retained Main and Settings controllers preserve window and store identity")
    @MainActor
    func nativeWindowsAreSingletons() {
        let store = UsageStore.preview(language: .english)
        let main = MainWindowController()
        let settings = SettingsWindowController()
        main.attach(store: store)
        settings.attach(store: store)

        let mainIdentity = main.windowIdentityForTesting
        let settingsIdentity = settings.windowIdentityForTesting
        main.showCanonicalWindow()
        main.window?.close()
        main.showCanonicalWindow()
        settings.showCanonicalWindow()
        settings.window?.close()
        settings.showCanonicalWindow()

        #expect(main.windowIdentityForTesting == mainIdentity)
        #expect(settings.windowIdentityForTesting == settingsIdentity)
        #expect(main.attachedStoreIdentityForTesting == ObjectIdentifier(store))
        #expect(settings.attachedStoreIdentityForTesting == ObjectIdentifier(store))

        main.tearDown()
        settings.tearDown()
    }

    @Test("Navigation changes content without replacing the canonical UMA window title")
    func canonicalMainWindowTitleIsStable() throws {
        let views = try source("Sources/CodexUsageMonitor/App/NativeShellViews.swift")
        let windows = try source("Sources/CodexUsageMonitor/App/NativeWindowControllers.swift")

        #expect(windows.contains("window.title = \"UMA\""))
        #expect(!views.contains(".navigationTitle(\"Overview\")"))
        #expect(!views.contains(".navigationTitle(\"Providers\")"))
    }

    @Test("Coordinator executes close, reopen, singleton, and shell-survival lifecycle")
    @MainActor
    func coordinatorLifecycleIsExecutable() {
        let shell = AppShellCoordinator()
        defer { shell.tearDown() }
        shell.start(presentMainWindow: false)

        let result = shell.runNativeLifecycleDiagnostic()

        #expect(result.mainWindowSingleton)
        #expect(result.settingsWindowSingleton)
        #expect(result.mainWindowReopened)
        #expect(result.windowClosePreservedShell)
        #expect(result.statusItemSurvivedWindowClose)
        #expect(result.assistantSurvivedWindowClose)
        #expect(result.nativeCommandRoutesPresent)
        #expect(result.threadOSRuntimeActivityCount == 0)
        #expect(result.passed)
    }

    @Test("Native menus route shortcuts through shell actions and ThreadOS is inert")
    func nativeMenuContract() throws {
        let menu = try source("Sources/CodexUsageMonitor/App/ApplicationMenuController.swift")
        for required in [
            "About UMA", "Settings…", "Quit UMA", "Refresh All",
            "Open Main Window", "Show Menu Bar Panel", "ThreadOS",
            "key: \",\"", "key: \"r\"", "key: \"1\"", "key: \"2\"", "key: \"q\"",
            "coordinator?.showSettingsWindow()", "coordinator?.showMainWindow()",
            "coordinator?.showQuickPanel()", "await coordinator?.refreshAll()",
            "coordinator?.toggleDesktopAssistant()",
        ] {
            #expect(menu.contains(required))
        }
        #expect(menu.contains("root.isEnabled = false"))
        #expect(menu.contains("action: nil"))
        #expect(menu.contains("title: \"Show or Hide Desktop Assistant\""))
        #expect(menu.contains("action: #selector(toggleDesktopAssistant)"))
        for forbidden in ["ThreadOSRuntime", "ThreadOSClient", "UsageMonitorRuntime.live"] {
            #expect(!menu.contains(forbidden))
        }
    }

    @Test("Quick Panel opens instantly and Assistant remains coordinator-owned")
    func quickPanelAndAssistantSurviveWindowClosure() throws {
        let status = try source("Sources/CodexUsageMonitor/App/StatusBarController.swift")
        let shell = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        let quickPanelAction = try #require(
            status.slice(from: "func showQuickPanel", through: "func setDesktopAssistantEnabled")
        )
        #expect(quickPanelAction.contains("panelController?.present()"))
        #expect(!quickPanelAction.contains("refresh"))
        #expect(!status.contains("Task.yield()"))
        #expect(status.contains("private weak var assistantController"))
        #expect(!status.contains("assistantController?.tearDown()"))
        #expect(shell.contains("assistantController.tearDown()"))
        #expect(shell.contains("statusBarController.tearDown()"))
    }

    @Test("M1 presentation consumes the shared provider product-state semantics")
    func presentationSemanticsAreShared() throws {
        let views = try source("Sources/CodexUsageMonitor/App/NativeShellViews.swift")
        #expect(views.contains("store.productInventory.overviewProviders"))
        #expect(views.contains("store.productInventory.providers"))
        #expect(views.contains("provider.primaryDisplayText"))
        #expect(views.contains("quota.displayText"))
        #expect(views.contains("provider.quotas.isEmpty"))
        #expect(views.contains("Usage unavailable"))
        #expect(views.contains("Currently unavailable"))
        #expect(!views.contains("?? \"0%\""))
        #expect(!views.localizedCaseInsensitiveContains("maximum decrement"))
    }

    @Test("M1 source changes do not import provider, Safari, or ThreadOS business logic")
    func m1ShellIsProviderInert() throws {
        for file in [
            "Sources/CodexUsageMonitor/App/ApplicationMenuController.swift",
            "Sources/CodexUsageMonitor/App/NativeWindowControllers.swift",
            "Sources/CodexUsageMonitor/App/NativeShellViews.swift",
        ] {
            let text = try source(file)
            for forbidden in [
                "ClaudeCodeUsageConnector", "ClaudeBrowser", "SafariServices",
                "PlugInKit", "WorkBuddyConnector", "AntigravityConnector", "ThreadOSRuntime",
            ] {
                #expect(!text.contains(forbidden))
            }
        }
    }

    @Test("Dedicated 0.14 Dev package is unsigned, Dock eligible, and isolated")
    func devPackageContract() throws {
        let script = try source("script/package_uma014_m1_dev.sh")
        #expect(script.contains("UMA 0.14 Dev.app"))
        #expect(script.contains("com.silkrd.uma.dev.uma014"))
        #expect(!script.contains("LSUIElement"))
        #expect(!script.contains("codesign"))
        #expect(!script.contains("/Users/juliushe/Desktop/UMA_0.13.0.app"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension String {
    func slice(from start: String, through end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound..<endIndex)
        else { return nil }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
