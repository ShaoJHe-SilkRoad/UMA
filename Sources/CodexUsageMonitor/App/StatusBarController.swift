import AppKit
import CodexUsageUI
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let store: UsageStore
    private let workBuddyLogin: WorkBuddyLoginCoordinator
    private let workBuddyAccountWebSync: WorkBuddyAccountWebSessionController
    private let statusItem: NSStatusItem
    private var panelController: TransparentUsagePanelController!
    private var assistantController: DesktopAssistantPanelController!
    private var storeObserver: AnyCancellable?
    private var statusUpdateScheduled = false

    init(
        store: UsageStore,
        workBuddySettings: WorkBuddySettingsModel,
        workBuddyLogin: WorkBuddyLoginCoordinator,
        workBuddyAccountWebSync: WorkBuddyAccountWebSessionController
    ) {
        self.store = store
        self.workBuddyLogin = workBuddyLogin
        self.workBuddyAccountWebSync = workBuddyAccountWebSync
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        panelController = TransparentUsagePanelController(
            store: store,
            statusItem: statusItem,
            workBuddySettings: workBuddySettings,
            workBuddyLogin: workBuddyLogin,
            workBuddyAccountWebSync: workBuddyAccountWebSync,
            visibilityDidChange: { [weak self] isVisible in
                self?.statusItem.button?.highlight(isVisible)
                self?.store.setPanelVisible(isVisible)
            }
        )
        assistantController = DesktopAssistantPanelController(
            onSelectProvider: { [weak self] providerID in
                self?.panelController.show(expandingProviderID: providerID)
            }
        )
        configureStatusButton()
        observeUsageChanges()
        updateStatusButton()
    }

    func tearDown() {
        panelController.tearDown()
        workBuddyLogin.tearDown()
        workBuddyAccountWebSync.tearDown()
        assistantController.tearDown()
        storeObserver?.cancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func setDesktopAssistantEnabled(_ isEnabled: Bool) {
        assistantController.setEnabled(isEnabled)
    }

    func setDesktopAssistantAlwaysOnTop(_ isAlwaysOnTop: Bool) {
        assistantController.setAlwaysOnTop(isAlwaysOnTop)
    }

    func setDesktopAssistantDensity(_ density: DesktopAssistantDensity) {
        assistantController.setDensity(density)
    }

    func toggleDesktopAssistantVisibility() {
        assistantController.toggleVisibility()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.67percent",
            accessibilityDescription: store.language.appTitle
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.font = AppTypography.menuBarNSFont()
        button.target = self
        button.action = #selector(handleStatusItemAction)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = store.language.appTitle
    }

    private func observeUsageChanges() {
        storeObserver = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.statusUpdateScheduled else { return }
                self.statusUpdateScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.statusUpdateScheduled = false
                    self.updateStatusButton()
                }
            }
        }
    }

    private func updateStatusButton() {
        statusItem.button?.title = store.menuPercent.map { " " + String($0) + "%" } ?? " —"
        statusItem.button?.toolTip = store.language.appTitle
        statusItem.button?.setAccessibilityLabel(
            store.menuPercent.map { store.language.remainingAccessibilityLabel(percent: $0) } ?? store.language.appTitle
        )
        assistantController.update(
            cards: store.assistantPresentationCards.map {
                DesktopAssistantCard(shared: $0, language: store.language)
            }
        )
    }

    @objc
    private func handleStatusItemAction() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            panelController.toggle()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let refresh = NSMenuItem(
            title: store.language.refreshUsage,
            action: #selector(refreshUsage),
            keyEquivalent: "r"
        )
        refresh.target = self
        refresh.isEnabled = store.allowsManualRefresh
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(desktopAssistantMenuItem())
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: store.language.quitApplication,
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func desktopAssistantMenuItem() -> NSMenuItem {
        let root = NSMenuItem(
            title: assistantText(english: "Desktop Assistant", chinese: "桌面助手"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu(title: root.title)

        let visibility = NSMenuItem(
            title: assistantController.isVisible
                ? assistantText(english: "Hide", chinese: "隐藏")
                : assistantText(english: "Show", chinese: "显示"),
            action: #selector(toggleDesktopAssistantFromMenu),
            keyEquivalent: ""
        )
        visibility.target = self
        visibility.isEnabled = assistantController.isEnabled
        submenu.addItem(visibility)

        let enabled = NSMenuItem(
            title: assistantText(english: "Enabled", chinese: "启用"),
            action: #selector(toggleDesktopAssistantEnabledFromMenu),
            keyEquivalent: ""
        )
        enabled.target = self
        enabled.state = assistantController.isEnabled ? .on : .off
        submenu.addItem(enabled)

        let alwaysOnTop = NSMenuItem(
            title: assistantText(english: "Always on Top", chinese: "始终置顶"),
            action: #selector(toggleDesktopAssistantAlwaysOnTopFromMenu),
            keyEquivalent: ""
        )
        alwaysOnTop.target = self
        alwaysOnTop.state = assistantController.isAlwaysOnTop ? .on : .off
        submenu.addItem(alwaysOnTop)
        submenu.addItem(.separator())

        let densityRoot = NSMenuItem(
            title: assistantText(english: "Density", chinese: "密度"),
            action: nil,
            keyEquivalent: ""
        )
        let densityMenu = NSMenu(title: densityRoot.title)
        for density in DesktopAssistantDensity.allCases {
            let item = NSMenuItem(
                title: densityTitle(density),
                action: #selector(selectDesktopAssistantDensityFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = density.rawValue
            item.state = assistantController.density == density ? .on : .off
            densityMenu.addItem(item)
        }
        densityRoot.submenu = densityMenu
        submenu.addItem(densityRoot)

        root.submenu = submenu
        return root
    }

    private func assistantText(english: String, chinese: String) -> String {
        store.language == .simplifiedChinese ? chinese : english
    }

    private func densityTitle(_ density: DesktopAssistantDensity) -> String {
        switch density {
        case .automatic:
            assistantText(english: "Automatic", chinese: "自动")
        case .regular:
            assistantText(english: "Regular", chinese: "常规")
        case .minimalist:
            assistantText(english: "Minimalist", chinese: "极简")
        }
    }

    @objc
    private func toggleDesktopAssistantFromMenu() {
        assistantController.toggleVisibility()
    }

    @objc
    private func toggleDesktopAssistantEnabledFromMenu() {
        assistantController.setEnabled(!assistantController.isEnabled)
    }

    @objc
    private func toggleDesktopAssistantAlwaysOnTopFromMenu() {
        assistantController.setAlwaysOnTop(!assistantController.isAlwaysOnTop)
    }

    @objc
    private func selectDesktopAssistantDensityFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let density = DesktopAssistantDensity(rawValue: rawValue) else {
            return
        }
        assistantController.setDensity(density)
    }

    @objc
    private func refreshUsage() {
        guard store.allowsManualRefresh else { return }
        Task { await store.refresh() }
    }

    @objc
    private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}
