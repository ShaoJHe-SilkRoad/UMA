import AppKit

struct ApplicationMenuDiagnosticState: Sendable {
    let requiredRoutesPresent: Bool
    let threadOSRuntimeActivityCount: Int
}

@MainActor
final class ApplicationMenuController: NSObject, NSMenuItemValidation {
    private weak var installedMenu: NSMenu?
    private let routes: IsolatedRoutes

    /// In-memory menu actions for a source-hosted acceptance window. Production
    /// construction continues to use the bound AppShellCoordinator below.
    struct IsolatedRoutes {
        let canRefreshAll: () -> Bool
        let openSettings: () -> Void
        let openMainWindow: () -> Void
        let showQuickPanel: () -> Void
        let toggleDesktopAssistant: () -> Void
        let refreshAll: () -> Void
    }

    init(coordinator: AppShellCoordinator) {
        routes = IsolatedRoutes(
            canRefreshAll: { [weak coordinator] in coordinator?.canRefreshAll == true },
            openSettings: { [weak coordinator] in coordinator?.showSettingsWindow() },
            openMainWindow: { [weak coordinator] in coordinator?.showMainWindow() },
            showQuickPanel: { [weak coordinator] in coordinator?.showQuickPanel() },
            toggleDesktopAssistant: { [weak coordinator] in coordinator?.toggleDesktopAssistant() },
            refreshAll: { [weak coordinator] in
                Task { @MainActor in await coordinator?.refreshAll() }
            }
        )
        super.init()
    }

    init(isolatedRoutes: IsolatedRoutes) {
        routes = isolatedRoutes
        super.init()
    }

    func installMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(refreshMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(threadOSMenuItem())
        NSApp.mainMenu = mainMenu
        installedMenu = mainMenu
    }

    func tearDown() {
        if NSApp.mainMenu === installedMenu {
            NSApp.mainMenu = nil
        }
        installedMenu = nil
    }

    var diagnosticState: ApplicationMenuDiagnosticState {
        let appMenu = installedMenu?.item(withTitle: "UMA")?.submenu
        let refreshMenu = installedMenu?.item(withTitle: "Refresh")?.submenu
        let viewMenu = installedMenu?.item(withTitle: "View")?.submenu
        let threadOSRoot = installedMenu?.item(withTitle: "ThreadOS")
        let threadOSItems = threadOSRoot?.submenu?.items ?? []
        let threadOSIsInert = threadOSRoot?.isEnabled == false
            && threadOSItems.allSatisfy { !$0.isEnabled && $0.action == nil && $0.target == nil }
        let requiredRoutesPresent = [
            route(in: appMenu, title: "Settings…", action: #selector(openSettings), key: ","),
            route(in: appMenu, title: "Quit UMA", action: #selector(quit), key: "q"),
            route(in: refreshMenu, title: "Refresh All", action: #selector(refreshAll), key: "r"),
            route(in: viewMenu, title: "Open Main Window", action: #selector(openMainWindow), key: "1"),
            route(in: viewMenu, title: "Show Menu Bar Panel", action: #selector(showQuickPanel), key: "2"),
            actionRoute(
                in: viewMenu,
                title: "Show or Hide Desktop Wizard",
                action: #selector(toggleDesktopAssistant)
            ),
        ].allSatisfy { $0 }
        return ApplicationMenuDiagnosticState(
            requiredRoutesPresent: requiredRoutesPresent && threadOSIsInert,
            threadOSRuntimeActivityCount: threadOSIsInert ? 0 : 1
        )
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(refreshAll) {
            return routes.canRefreshAll()
        }
        return menuItem.isEnabled
    }

    private func appMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "UMA", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "UMA")
        menu.addItem(actionItem(title: "About UMA", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit UMA", action: #selector(quit), key: "q"))
        root.submenu = menu
        return root
    }

    private func refreshMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Refresh", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Refresh")
        menu.addItem(actionItem(title: "Refresh All", action: #selector(refreshAll), key: "r"))
        root.submenu = menu
        return root
    }

    private func editMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Edit")
        menu.addItem(responderItem(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(responderItem(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(.separator())
        menu.addItem(responderItem(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(responderItem(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a"))
        root.submenu = menu
        return root
    }

    private func viewMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "View")
        menu.addItem(actionItem(title: "Open Main Window", action: #selector(openMainWindow), key: "1"))
        menu.addItem(actionItem(title: "Show Menu Bar Panel", action: #selector(showQuickPanel), key: "2"))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Show or Hide Desktop Wizard", action: #selector(toggleDesktopAssistant)))
        root.submenu = menu
        return root
    }

    private func threadOSMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "ThreadOS", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "ThreadOS")
        let future = NSMenuItem(title: "Coming in a future milestone", action: nil, keyEquivalent: "")
        future.isEnabled = false
        menu.addItem(future)
        root.submenu = menu
        root.isEnabled = false
        return root
    }

    private func actionItem(
        title: String,
        action: Selector,
        key: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = key.isEmpty ? [] : [.command]
        return item
    }

    private func responderItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = nil
        item.keyEquivalentModifierMask = [.command]
        return item
    }

    private func route(
        in menu: NSMenu?,
        title: String,
        action: Selector,
        key: String
    ) -> Bool {
        guard let item = menu?.item(withTitle: title) else { return false }
        return item.target === self
            && item.action == action
            && item.keyEquivalent == key
            && item.keyEquivalentModifierMask.contains(.command)
    }

    private func actionRoute(in menu: NSMenu?, title: String, action: Selector) -> Bool {
        guard let item = menu?.item(withTitle: title) else { return false }
        return item.target === self && item.action == action
    }

    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
    @objc private func openSettings() { routes.openSettings() }
    @objc private func openMainWindow() { routes.openMainWindow() }
    @objc private func showQuickPanel() { routes.showQuickPanel() }
    @objc private func toggleDesktopAssistant() { routes.toggleDesktopAssistant() }
    @objc private func refreshAll() { routes.refreshAll() }
    @objc private func quit() { NSApp.terminate(nil) }
}
