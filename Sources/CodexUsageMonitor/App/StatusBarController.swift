import AppKit
import CodexUsageUI
import Combine

@MainActor
final class StatusBarController: NSObject {
    private var store: UsageStore?
    private let lifecycleGeneration: UUID
    private let diagnostics: AppShellDiagnosticRecorder
    private let statusItem: NSStatusItem
    private var panelController: QuickPanelPopoverController?
    private var quickPanelActions: QuickPanelActions?
    private weak var assistantController: DesktopAssistantPanelController?
    private var storeObserver: AnyCancellable?
    private var menuReading: UsageStore.MenuReading?
    private var preferenceObservation: ApplicationPreferences.Observation?
    private var showsRemainingValue = true
    private var isTornDown = false
    private var statusEventMonitor: Any?
    private var statusEventBeganAt: TimeInterval?

    init(
        lifecycleGeneration: UUID = UUID(),
        diagnostics: AppShellDiagnosticRecorder = AppShellDiagnosticRecorder()
    ) {
        self.lifecycleGeneration = lifecycleGeneration
        self.diagnostics = diagnostics
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusButton()
        panelController = QuickPanelPopoverController(
            statusItem: statusItem,
            visibilityDidChange: { [weak self] isVisible in
                self?.statusItem.button?.highlight(isVisible)
                self?.store?.setPanelVisible(isVisible)
            }
        )
        panelController?.setDiagnosticEventHandler { [weak self] stage, reached, detail in
            self?.record(stage, reached: reached, detail: detail)
        }
        updateStatusButton()
        installStatusEventMonitor()
    }

    func attach(runtime: UsageMonitorRuntime, actions: QuickPanelActions) {
        guard store == nil, !isTornDown else { return }
        store = runtime.store
        quickPanelActions = actions
        showsRemainingValue = runtime.preferences.value(
            for: UMAApplicationPreferenceKeys.menuBarShowsRemaining
        )
        preferenceObservation = runtime.preferences.observe { [weak self, weak preferences = runtime.preferences] change in
            guard change.key == UMAApplicationPreferenceKeys.menuBarShowsRemaining.name,
                  let self,
                  let preferences else { return }
            self.showsRemainingValue = preferences.value(
                for: UMAApplicationPreferenceKeys.menuBarShowsRemaining
            )
            self.updateStatusButton()
        }
        panelController?.attachContent(
            store: runtime.store,
            preferences: runtime.preferences,
            actions: actions
        )
        observeUsageChanges()
        updateStatusButton()
        record(.runtimeAttached)
    }

    func recordRuntimeAttachmentFailure() {
        panelController?.markRuntimeAttachmentFailed()
        record(.runtimeAttachmentFailed, reached: false, detail: "compositionRejected")
    }

    func runMachineDiagnostic(toggleCount: Int) async -> AppShellMachineDiagnosticResult {
        guard let button = statusItem.button else {
            return machineDiagnosticResult(
                requested: toggleCount,
                completed: 0,
                failure: "STATUS_ITEM_BUTTON_MISSING"
            )
        }
        guard button.target === self,
              button.action == #selector(handleStatusItemAction) else {
            return machineDiagnosticResult(
                requested: toggleCount,
                completed: 0,
                failure: "STATUS_ITEM_TARGET_ACTION_INVALID"
            )
        }
        var completed = 0
        for index in 0..<toggleCount {
            let expectsOpen = index.isMultiple(of: 2)
            guard let panelController else {
                return machineDiagnosticResult(
                    requested: toggleCount,
                    completed: completed,
                    failure: "PANEL_CONTROLLER_MISSING"
                )
            }
            if expectsOpen {
                let preflight = panelController.diagnosticState
                guard preflight.anchorAttachedToWindow else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "STATUS_ITEM_ANCHOR_NOT_ATTACHED"
                    )
                }
                guard preflight.anchorWindowVisible else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "STATUS_ITEM_ANCHOR_WINDOW_NOT_VISIBLE"
                    )
                }
                guard !preflight.anchorBounds.isEmpty else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "STATUS_ITEM_ANCHOR_BOUNDS_EMPTY"
                    )
                }
            }
            let transitioned = await panelController.performDiagnosticTransition(
                expecting: expectsOpen
            ) {
                guard let action = button.action else { return false }
                return NSApp.sendAction(action, to: button.target, from: button)
            }
            guard transitioned else {
                return machineDiagnosticResult(
                    requested: toggleCount,
                    completed: completed,
                    failure: expectsOpen
                        ? "PANEL_OPEN_TRANSITION_TIMED_OUT"
                        : "PANEL_CLOSE_TRANSITION_TIMED_OUT"
                )
            }
            let state = panelController.diagnosticState
            if expectsOpen {
                guard state.anchorAttachedToWindow else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "STATUS_ITEM_ANCHOR_NOT_ATTACHED"
                    )
                }
                guard state.anchorWindowVisible else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "STATUS_ITEM_ANCHOR_WINDOW_NOT_VISIBLE"
                    )
                }
                guard !state.anchorBounds.isEmpty else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "STATUS_ITEM_ANCHOR_BOUNDS_EMPTY"
                    )
                }
                guard state.usesSingleSurfacePanel else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "PANEL_NOT_SINGLE_SURFACE_HOST"
                    )
                }
                guard (300...330).contains(state.contentSize.width),
                      state.contentSize.height >= QuickPanelPopoverController.minimumContentHeight,
                      state.contentSize.height <= QuickPanelPopoverController.maximumContentHeight
                else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "PANEL_CONTENT_SIZE_OUT_OF_BOUNDS"
                    )
                }
                guard state.eventMonitorCount == 0, !state.ignoresMouseEvents else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "PANEL_INTERACTION_OWNERSHIP_INVALID"
                    )
                }
                guard state.isVisible else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "PANEL_NOT_SHOWN"
                    )
                }
                guard state.isEffectivelyOpen else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "PANEL_WINDOW_NOT_VISIBLE"
                    )
                }
                guard state.isResponsive else {
                    return machineDiagnosticResult(
                        requested: toggleCount,
                        completed: completed,
                        failure: "PANEL_HIT_TESTING_UNAVAILABLE"
                    )
                }
            }
            let converged = expectsOpen
                ? state.isEffectivelyOpen && state.isResponsive
                : !state.isVisible && state.eventMonitorCount == 0
            guard converged else {
                return machineDiagnosticResult(
                    requested: toggleCount,
                    completed: completed,
                    failure: expectsOpen
                        ? "PANEL_OPEN_CONVERGENCE_FAILED"
                        : "PANEL_CLOSE_CONVERGENCE_FAILED"
                )
            }
            completed += 1
        }
        return machineDiagnosticResult(
            requested: toggleCount,
            completed: completed,
            failure: nil
        )
    }

    private func machineDiagnosticResult(
        requested: Int,
        completed: Int,
        failure: String?
    ) -> AppShellMachineDiagnosticResult {
        let panel = panelController?.diagnosticState
        return AppShellMachineDiagnosticResult(
            requestedToggleCount: requested,
            completedToggleCount: completed,
            statusItemCount: isTornDown ? 0 : 1,
            panelWindowCount: panelController == nil ? 0 : 1,
            eventMonitorCount: panel?.eventMonitorCount ?? 0,
            applicationIsHidden: NSApp.isHidden,
            finalPanelVisible: panel?.isVisible ?? false,
            providerStartupEnabled: false,
            passed: failure == nil,
            firstFailure: failure
        )
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        panelController?.tearDown()
        quickPanelActions = nil
        storeObserver?.cancel()
        preferenceObservation?.cancel()
        preferenceObservation = nil
        if let statusEventMonitor { NSEvent.removeMonitor(statusEventMonitor) }
        statusEventMonitor = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func recordShellCreated() {
        record(.shellCreated)
        record(.statusItemExists)
        record(.statusItemButtonExists, reached: statusItem.button != nil)
        record(.statusItemEnabled, reached: statusItem.button?.isEnabled == true)
        record(.targetPresent, reached: statusItem.button?.target === self)
        record(.actionPresent, reached: statusItem.button?.action == #selector(handleStatusItemAction))
    }

    func bindAssistant(_ assistantController: DesktopAssistantPanelController) {
        self.assistantController = assistantController
    }

    func showQuickPanel(expandingProviderID providerID: String? = nil) {
        guard !isTornDown else { return }
        if let providerID {
            panelController?.show(
                selecting: ProviderProductID(rawValue: providerID)
            )
        } else {
            panelController?.present()
        }
    }

    var isActiveForDiagnostic: Bool {
        !isTornDown && statusItem.button != nil && panelController != nil
    }

    func setDesktopAssistantEnabled(_ isEnabled: Bool) {
        assistantController?.setEnabled(isEnabled)
    }

    func setDesktopAssistantAlwaysOnTop(_ isAlwaysOnTop: Bool) {
        assistantController?.setAlwaysOnTop(isAlwaysOnTop)
    }

    func setDesktopAssistantDensity(_ density: DesktopAssistantDensity) {
        assistantController?.setDensity(density)
    }

    func toggleDesktopAssistantVisibility() {
        assistantController?.toggleVisibility()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.67percent",
            accessibilityDescription: "AUV"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.font = AppTypography.menuBarNSFont()
        button.target = self
        button.action = #selector(handleStatusItemAction)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "AUV"
    }

    /// The reading is taken from what the store publishes, not read back from
    /// the store, which still holds the previous values while it publishes.
    private func observeUsageChanges() {
        guard let store else { return }
        storeObserver = store.menuReadingPublisher.sink { [weak self] reading in
            self?.menuReading = reading
            self?.updateStatusButton()
        }
    }

    private func updateStatusButton() {
        repairStatusButtonContractIfNeeded()
        statusItem.button?.title = showsRemainingValue
            ? (menuReading?.percent.map { " " + String($0) + "%" } ?? " —")
            : ""
        let language = menuReading?.language
        let providerName = menuReading?.provider?.displayName
        statusItem.button?.toolTip = providerName.map {
            "\($0) · " + (language?.appTitle ?? "AUV")
        } ?? language?.appTitle ?? "AUV"
        statusItem.button?.setAccessibilityLabel(
            menuReading?.percent.map { percent in
                language?.remainingAccessibilityLabel(
                    provider: providerName ?? "AUV",
                    percent: percent
                ) ?? "AUV"
            } ?? language?.appTitle ?? "AUV"
        )
    }

    private func installStatusEventMonitor() {
        guard statusEventMonitor == nil else { return }
        statusEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            guard let self,
                  event.window === self.statusItem.button?.window else { return event }
            switch event.type {
            case .leftMouseDown, .rightMouseDown:
                self.statusEventBeganAt = ProcessInfo.processInfo.systemUptime
                self.record(.mouseDownReceived)
            case .leftMouseUp, .rightMouseUp:
                self.record(.mouseUpReceived)
            default:
                break
            }
            return event
        }
    }

    @objc
    private func handleStatusItemAction() {
        guard !isTornDown else {
            record(.staleGenerationRejected, reached: false, detail: "tornDown")
            return
        }
        let eventType = NSApp.currentEvent?.type
        let eventLatencyMilliseconds = statusEventBeganAt.map {
            Int(max(0, (ProcessInfo.processInfo.systemUptime - $0) * 1_000))
        } ?? 0
        statusEventBeganAt = nil
        record(.actionInvoked)
        record(
            .mainActorEntered,
            detail: Thread.isMainThread ? "main" : "notMain",
            mainThreadStallMilliseconds: eventLatencyMilliseconds
        )
        record(.toggleRequested)
        if eventType == .rightMouseDown || eventType == .rightMouseUp {
            showContextMenu()
        } else {
            panelController?.toggle()
        }
    }

    private func repairStatusButtonContractIfNeeded() {
        guard let button = statusItem.button else {
            record(.statusItemButtonExists, reached: false)
            return
        }
        button.isEnabled = true
        if button.target !== self { button.target = self }
        if button.action != #selector(handleStatusItemAction) {
            button.action = #selector(handleStatusItemAction)
        }
    }

    private func record(
        _ stage: AppShellDiagnosticStage,
        reached: Bool = true,
        detail: String? = nil,
        mainThreadStallMilliseconds: Int = 0
    ) {
        let panel = panelController?.diagnosticState
        diagnostics.record(
            AppShellDiagnosticReceipt(
                stage: stage,
                reached: reached,
                lifecycleGeneration: lifecycleGeneration.uuidString,
                statusItemCount: isTornDown ? 0 : 1,
                panelWindowCount: panelController == nil ? 0 : 1,
                eventMonitorCount:
                    (panel?.eventMonitorCount ?? 0) + (statusEventMonitor == nil ? 0 : 1),
                mainThreadStallMilliseconds: mainThreadStallMilliseconds,
                activeModalWindow: NSApp.modalWindow != nil,
                activeSheetWindow: NSApp.windows.contains { $0.attachedSheet != nil },
                eventMonitorOwners: eventMonitorOwners(panelMonitorCount: panel?.eventMonitorCount ?? 0),
                applicationIsHidden: NSApp.isHidden,
                frontmostApplicationBundleIdentifier:
                    NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                panelLevel: panel?.level,
                panelAlpha: panel?.alpha,
                panelFrame: panel?.frame,
                panelIgnoresMouseEvents: panel?.ignoresMouseEvents,
                mainWindowFrame: nil,
                mainWindowContentRect: nil,
                mainWindowBackingScale: nil,
                mainWindowIsZoomed: nil,
                mainWindowIsFullScreen: nil,
                detail: detail,
                timestamp: Date()
            )
        )
    }

    private func eventMonitorOwners(panelMonitorCount: Int) -> [String] {
        var owners: [String] = []
        if statusEventMonitor != nil { owners.append("statusItem.local") }
        if panelMonitorCount > 0 { owners.append("usagePanel.bounded") }
        return owners
    }

    private func showContextMenu() {
        guard let store, assistantController != nil else { return }
        let menu = NSMenu()
        // Named as everywhere else: it is the same Refresh All.
        let refresh = NSMenuItem(
            title: store.language == .simplifiedChinese ? "全部刷新" : "Refresh All",
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
        guard let assistantController else { return NSMenuItem() }
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
        store?.language == .simplifiedChinese ? chinese : english
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
        assistantController?.toggleVisibility()
    }

    @objc
    private func toggleDesktopAssistantEnabledFromMenu() {
        guard let assistantController else { return }
        assistantController.setEnabled(!assistantController.isEnabled)
    }

    @objc
    private func toggleDesktopAssistantAlwaysOnTopFromMenu() {
        guard let assistantController else { return }
        assistantController.setAlwaysOnTop(!assistantController.isAlwaysOnTop)
    }

    @objc
    private func selectDesktopAssistantDensityFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let density = DesktopAssistantDensity(rawValue: rawValue) else {
            return
        }
        assistantController?.setDensity(density)
    }

    @objc
    private func refreshUsage() {
        guard let store, store.allowsManualRefresh else { return }
        quickPanelActions?.refreshAll()
    }

    @objc
    private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}
