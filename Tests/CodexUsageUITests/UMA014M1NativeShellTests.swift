import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("UMA 0.14 M1 native shell", .serialized)
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
            "mainWindowController.attach(",
            "settingsWindowController.attach(",
            "store: runtime.store, preferences: runtime.preferences, dataPaths: runtime.dataPaths",
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
        main.attach(
            store: store,
            openSettings: {},
            scanAll: {},
            refreshAll: {},
                connectCodex: {},
                disconnectCodex: {},
                claudeControlState: { .consentRequired },
                connectClaude: {},
            accuracySyncClaude: {}
        )
        settings.attach(store: store, preferences: .inMemory())

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

        // The product is AUV. Its bundle filename (UMA.app), bundle
        // identifier (com.silkrd.uma) and CFBundleName stay UMA so existing
        // installs upgrade in place, so a stray "UMA" in this file is not
        // automatically wrong — but the chrome a user reads is AUV.
        #expect(windows.contains("window.title = \"AUV\""))
        #expect(!views.contains(".navigationTitle(\"Overview\")"))
        #expect(!views.contains(".navigationTitle(\"Providers\")"))
    }

    @Test("Main and Settings rely exclusively on native titlebar controls")
    @MainActor
    func canonicalWindowsUseNativeTrafficLights() {
        let main = MainWindowController()
        let settings = SettingsWindowController()
        defer {
            main.tearDown()
            settings.tearDown()
        }

        for window in [main.window, settings.window].compactMap({ $0 }) {
            #expect(window.styleMask.contains(.titled))
            #expect(window.styleMask.contains(.closable))
            #expect(window.styleMask.contains(.miniaturizable))
            #expect(window.styleMask.contains(.resizable))
            #expect(!window.styleMask.contains(.fullSizeContentView))
            #expect(window.titleVisibility == .visible)
            #expect(!window.titlebarAppearsTransparent)
            #expect(window.titlebarAccessoryViewControllers.isEmpty)

            for kind in [
                NSWindow.ButtonType.closeButton,
                .miniaturizeButton,
                .zoomButton,
            ] {
                let button = window.standardWindowButton(kind)
                #expect(button != nil)
                if let button {
                    #expect(button.window === window)
                    #expect(button.superview !== window.contentView)
                }
            }
        }
    }

    @Test("Coordinator executes close, reopen, singleton, and shell-survival lifecycle")
    @MainActor
    func coordinatorLifecycleIsExecutable() {
        let shell = AppShellCoordinator()
        defer { shell.tearDown() }
        shell.start(presentMainWindow: false)

        let result = shell.runNativeLifecycleDiagnostic(
            mainWindowCycleCount: 25,
            settingsWindowCycleCount: 100,
            agentSwitchCount: 100
        )

        #expect(result.mainWindowSingleton)
        #expect(result.settingsWindowSingleton)
        #expect(result.mainWindowReopened)
        #expect(result.windowClosePreservedShell)
        #expect(result.statusItemSurvivedWindowClose)
        #expect(result.assistantSurvivedWindowClose)
        #expect(result.nativeCommandRoutesPresent)
        #expect(result.threadOSRuntimeActivityCount == 0)
        #expect(result.completedMainWindowCycles == 25)
        #expect(result.completedSettingsWindowCycles == 100)
        #expect(result.completedAgentSwitches == 100)
        #expect(result.passed)
    }

    @Test("Native menus route shortcuts through shell actions without ThreadOS runtime control")
    func nativeMenuContract() throws {
        let menu = try source("Sources/CodexUsageMonitor/App/ApplicationMenuController.swift")
        for required in [
            "About AUV", "Settings…", "Quit AUV", "Refresh All",
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
        #expect(!menu.contains("return coordinator?.assistantIsEnabled == true"))
        #expect(menu.contains("action: #selector(toggleDesktopAssistant)"))
        for forbidden in ["ThreadOSRuntime", "ThreadOSClient", "UsageMonitorRuntime.live"] {
            #expect(!menu.contains(forbidden))
        }
    }

    @Test("Native Edit commands use the first responder chain")
    @MainActor
    func nativeEditMenuUsesStandardResponderActions() throws {
        let shell = AppShellCoordinator()
        defer { shell.tearDown() }
        shell.start(presentMainWindow: false)

        let editMenu = try #require(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu)
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            let item = try #require(editMenu.item(withTitle: title))
            #expect(item.target == nil)
            #expect(item.action == action)
            #expect(item.keyEquivalent == key)
            #expect(item.keyEquivalentModifierMask == [.command])
        }
    }

    @Test("Native Edit commands dispatch through the first responder into an AppKit editor")
    @MainActor
    func nativeEditMenuDispatchesCopyPasteAndSelectAllToFirstResponder() throws {
        let shell = AppShellCoordinator()
        defer { shell.tearDown() }
        shell.start(presentMainWindow: false)

        let pasteboard = NSPasteboard.general
        let originalPasteboardItems = (pasteboard.pasteboardItems ?? []).map { item in
            let preservedItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    preservedItem.setData(data, forType: type)
                }
            }
            return preservedItem
        }
        defer {
            pasteboard.clearContents()
            _ = pasteboard.writeObjects(originalPasteboardItems)
        }

        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 160))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = editor
        let activationPolicy = NSApp.activationPolicy()
        defer { NSApp.setActivationPolicy(activationPolicy) }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSApp.activate(ignoringOtherApps: true)
        let modalSession = NSApp.beginModalSession(for: window)
        defer { NSApp.endModalSession(modalSession) }
        let deadline = Date().addingTimeInterval(0.25)
        while NSApp.keyWindow !== window, Date() < deadline {
            _ = NSApp.runModalSession(modalSession)
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(editor))
        #expect(NSApp.modalWindow === window)
        #expect(window.firstResponder === editor)

        let editMenu = try #require(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu)
        func dispatch(_ title: String) throws {
            let item = try #require(editMenu.item(withTitle: title))
            let action = try #require(item.action)
            #expect((NSApp.target(forAction: action, to: item.target, from: item) as AnyObject?) === editor)
            #expect(NSApp.sendAction(action, to: item.target, from: item))
        }

        let request = "TOSCFG/1\n{\"project\":\"TOSUMA-TU4\"}"
        editor.string = request
        try dispatch("Select All")
        #expect(editor.selectedRange() == NSRange(location: 0, length: (request as NSString).length))

        try dispatch("Copy")
        #expect(pasteboard.string(forType: .string) == request)

        editor.string = ""
        #expect(window.makeFirstResponder(editor))
        try dispatch("Paste")
        #expect(editor.string == request)
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

    @Test("Agent workspace Connect preserves the established local-access consent boundary")
    func codexConnectRoutesThroughConsentBeforeReconnect() throws {
        let shell = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        let connect = try #require(
            shell.slice(from: "func connectCodex()", through: "func disconnectCodex()")
        )
        #expect(connect.contains("store.currentState == .notAuthorizedByMonitor"))
        #expect(connect.contains("NativeLocalCodexAccessConfirmation.action(for: store).request()"))
        #expect(connect.contains("store.handleLocalAccessDecision"))
        #expect(connect.contains("store.requestReconnect()"))
    }

    @Test("Codex consent owns application-launch recovery independently of Claude consent")
    func codexLaunchRecoveryIsIndependent() throws {
        let runtime = try source("Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift")
        #expect(runtime.contains("if !usageStore.monitorConsentGranted"))
        #expect(runtime.contains("excluded.insert(CodexUsageConnector.connectorID)"))
        #expect(runtime.contains("if !shouldStartClaude"))
        #expect(runtime.contains("excluded.insert(ClaudeCodeUsageConnector.connectorID)"))
        #expect(!runtime.contains("guard shouldStartClaude else { return }"))
    }

    @Test("M1 presentation consumes the shared provider product-state semantics")
    func presentationSemanticsAreShared() throws {
        let views = try source("Sources/CodexUsageMonitor/App/NativeShellViews.swift")
        let surfaces = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        let presentation = views + surfaces
        // The agent list is the shared inventory in the user's arranged
        // order (0.17.6). It must still be that inventory, not a list of the
        // shell's own: the store derives the ordered one from it.
        let store = try source("Sources/CodexUsageUI/Stores/UsageStore.swift")
        #expect(presentation.contains("store.orderedWorkspaceProviders"))
        #expect(store.filter { !$0.isWhitespace }
            .contains("AgentDisplayOrder.apply(productInventory.agentWorkspaceProviders,"))
        #expect(presentation.contains("primaryDisplayText"))
        #expect(presentation.contains("quota.displayText"))
        #expect(presentation.contains("No active agents"))
        #expect(!presentation.contains("?? \"0%\""))
        #expect(!presentation.localizedCaseInsensitiveContains("maximum decrement"))
    }

    @Test("M1 source changes do not import provider, Safari, or ThreadOS business logic")
    func m1ShellIsProviderInert() throws {
        for file in [
            "Sources/CodexUsageMonitor/App/ApplicationMenuController.swift",
            "Sources/CodexUsageMonitor/App/NativeWindowControllers.swift",
            "Sources/CodexUsageMonitor/App/NativeShellViews.swift",
        ] {
            // The shell threads the Claude settings model through to the
            // settings sheet that owns it (since 0.15 R16). That is a type it
            // passes along, not Claude logic it runs, so only that one name is
            // exempt; every other Claude browser type stays out.
            let text = try source(file).replacingOccurrences(of: "ClaudeBrowserSettingsModel", with: "")
            for forbidden in [
                "ClaudeCodeUsageConnector", "ClaudeBrowser", "SafariServices",
                "PlugInKit", "WorkBuddyConnector", "AntigravityConnector", "ThreadOSRuntime",
            ] {
                #expect(!text.contains(forbidden))
            }
        }
    }

    @Test("Dedicated Dev package is unsigned, Dock eligible, and isolated")
    func devPackageContract() throws {
        let script = try source("script/package_uma014_m1_dev.sh")
        let authorityData = try Data(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Configuration/UMAProductVersion.plist"
            )
        )
        let authority = try #require(
            PropertyListSerialization.propertyList(
                from: authorityData,
                format: nil
            ) as? [String: Any]
        )
        let development = try #require(authority["Development"] as? [String: Any])

        #expect(script.contains("Development.ApplicationName"))
        #expect(script.contains("Development.BundleIdentifier"))
        #expect(
            development["ApplicationName"] as? String == "UMA 0.18 Dev"
        )
        #expect(
            development["BundleIdentifier"] as? String
                == "com.silkrd.uma.dev.uma014"
        )
        #expect(!script.contains("LSUIElement"))
        #expect(!script.contains("codesign"))
        #expect(!script.contains("/Users/juliushe/Desktop/UMA_0.13.0.app"))
    }

    @Test("Dev package preserves the built SwiftPM ThreadOS resource bundle")
    func devPackageBundlesThreadOSCatalogWithoutCheckoutFallback() throws {
        let script = try source("script/package_uma014_m1_dev.sh")

        for required in [
            "CodexUsageMonitor_CodexUsageUI.bundle",
            "Contents/Resources/models.v1.json",
            "UMA014_SWIFTPM_RESOURCE_BUNDLE_MISSING",
            "UMA014_PACKAGED_THREADOS_CATALOG_MISSING",
            "UMA014_PACKAGED_THREADOS_CATALOG_MISMATCH",
            "/usr/bin/ditto \"$SWIFTPM_RESOURCE_BUNDLE\" \"$PACKAGED_RESOURCE_BUNDLE\"",
            "/usr/bin/cmp \"$SWIFTPM_THREADOS_CATALOG\" \"$PACKAGED_RESOURCE_BUNDLE/Contents/Resources/models.v1.json\"",
        ] {
            #expect(script.contains(required))
        }
        #expect(!script.contains("Sources/CodexUsageUI/Resources/ThreadOS/models.v1.json"))
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
