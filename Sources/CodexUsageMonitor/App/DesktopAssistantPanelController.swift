import AppKit
import CodexUsageUI
import SwiftUI

final class DesktopAssistantDragGestureRecognizer: NSGestureRecognizer {
    static let movementThreshold: CGFloat = 4

    private(set) var initialPointerLocationInWindow: NSPoint?
    private(set) var pointerLocationInWindow: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        initialPointerLocationInWindow = event.locationInWindow
        pointerLocationInWindow = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        pointerLocationInWindow = event.locationInWindow
        guard let initialPointerLocationInWindow else {
            state = .failed
            return
        }
        switch state {
        case .possible:
            let deltaX = pointerLocationInWindow.x - initialPointerLocationInWindow.x
            let deltaY = pointerLocationInWindow.y - initialPointerLocationInWindow.y
            if hypot(deltaX, deltaY) >= Self.movementThreshold {
                state = .began
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        pointerLocationInWindow = event.locationInWindow
        switch state {
        case .possible:
            state = .failed
        case .began, .changed:
            state = .ended
        default:
            break
        }
    }

    override func reset() {
        super.reset()
        initialPointerLocationInWindow = nil
        pointerLocationInWindow = .zero
    }
}

final class DesktopAssistantPanel: NSPanel {
    private var dragStartPointer: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    var assistantContextMenuProvider: (() -> NSMenu?)?
    var assistantContextMenuPresenter: (NSMenu, NSEvent, NSView) -> Void = {
        NSMenu.popUpContextMenu($0, with: $1, for: $2)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard Self.isAssistantContextMenuEvent(event),
              let contentView,
              let menu = assistantContextMenuProvider?() else {
            super.sendEvent(event)
            return
        }

        // A borderless nonactivating panel does not reliably ask its SwiftUI
        // hosting view for a contextual menu. Route secondary clicks at the
        // AppKit window boundary so they cannot be swallowed by SwiftUI hit
        // testing or the primary-button drag recognizer.
        assistantContextMenuPresenter(menu, event, contentView)
    }

    static func isAssistantContextMenuEvent(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    @objc func handleAssistantDrag(_ recognizer: DesktopAssistantDragGestureRecognizer) {
        let pointer = convertPoint(toScreen: recognizer.pointerLocationInWindow)
        switch recognizer.state {
        case .began:
            let initialPointer = recognizer.initialPointerLocationInWindow
                .map { convertPoint(toScreen: $0) }
                ?? pointer
            beginAssistantDrag(at: initialPointer)
            continueAssistantDrag(to: pointer)
        case .changed:
            continueAssistantDrag(to: pointer)
        case .ended, .cancelled, .failed:
            endAssistantDrag()
        default:
            break
        }
    }

    func beginAssistantDrag(at pointer: NSPoint) {
        dragStartPointer = pointer
        dragStartWindowOrigin = frame.origin
    }

    func continueAssistantDrag(to pointer: NSPoint) {
        guard isMovable,
              let dragStartPointer,
              let dragStartWindowOrigin else { return }
        setFrameOrigin(
            NSPoint(
                x: dragStartWindowOrigin.x + pointer.x - dragStartPointer.x,
                y: dragStartWindowOrigin.y + pointer.y - dragStartPointer.y
            )
        )
    }

    func endAssistantDrag() {
        dragStartPointer = nil
        dragStartWindowOrigin = nil
    }
}

/// Host-owned presentation controller. It receives immutable display cards and
/// owns no provider component, refresh action, timer, scanner, or usage cache.
@MainActor
final class DesktopAssistantPanelController: NSObject, NSMenuDelegate {
    private let panel: DesktopAssistantPanel
    private var preferenceStore: ApplicationPreferences
    private var onSelectProvider: ((String) -> Void)?
    private var preferences: DesktopAssistantPreferences
    private var showsStatusIndicator: Bool
    private var showsPercentageRail: Bool
    private var cards: [DesktopAssistantCard] = []
    private var renderedDensity: DesktopAssistantResolvedDensity?
    private var moveObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var preferencesObservation: ApplicationPreferences.Observation?
    private var isApplyingFrame = false
    private var shouldBeVisible: Bool
    private var positionSaveTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        onSelectProvider: ((String) -> Void)? = nil
    ) {
        let preferenceStore = ApplicationPreferences(userDefaults: defaults)
        self.preferenceStore = preferenceStore
        self.onSelectProvider = onSelectProvider
        preferences = DesktopAssistantPreferences.load(from: preferenceStore)
        showsStatusIndicator = preferenceStore.value(
            for: UMAApplicationPreferenceKeys.assistantShowsStatusIndicator
        )
        showsPercentageRail = preferenceStore.value(
            for: UMAApplicationPreferenceKeys.assistantShowsPercentageRail
        )
        shouldBeVisible = preferences.isEnabled
        panel = DesktopAssistantPanel(
            contentRect: NSRect(
                origin: .zero,
                size: DesktopAssistantMetrics.size(for: .regular)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        installWindowObservers()
        installPreferencesObserver()
    }

    /// Rebinds the Assistant to the application-owned preference authority.
    /// The default initializer remains available for isolated legacy tests, but
    /// production calls this once when the shared runtime is attached.
    func bind(preferences preferenceStore: ApplicationPreferences) {
        guard self.preferenceStore !== preferenceStore else { return }
        preferencesObservation?.cancel()
        self.preferenceStore = preferenceStore
        installPreferencesObserver()
        applyPreferencesFromStore()
    }

    func setSelectionHandler(_ handler: @escaping (String) -> Void) {
        onSelectProvider = handler
    }

    var isEnabled: Bool { preferences.isEnabled }
    var isVisible: Bool { panel.isVisible }
    var isAlwaysOnTop: Bool { preferences.isAlwaysOnTop }
    var density: DesktopAssistantDensity { preferences.density }
    var usesWindowBackgroundDragging: Bool { panel.isMovableByWindowBackground }
    var hasWindowShadow: Bool { panel.hasShadow }
    var assistantDragRecognizerCount: Int {
        panel.contentView?.gestureRecognizers.count {
            $0 is DesktopAssistantDragGestureRecognizer
        } ?? 0
    }
    var assistantDragDelaysClicks: Bool {
        panel.contentView?.gestureRecognizers
            .compactMap { $0 as? DesktopAssistantDragGestureRecognizer }
            .first?.delaysPrimaryMouseButtonEvents ?? false
    }
    var hasAssistantContextMenuEventRouter: Bool {
        panel.assistantContextMenuProvider != nil
    }
    var assistantPanelForTesting: DesktopAssistantPanel { panel }

    func update(cards: [DesktopAssistantCard]) {
        let cardsChanged = cards != self.cards
        let previousCount = self.cards.count
        self.cards = cards
        let resolvedDensity = preferences.density.resolvedDensity(
            visibleProviderCount: cards.count
        )
        let densityChanged = renderedDensity != resolvedDensity
        if cardsChanged || densityChanged {
            installContent(density: resolvedDensity)
        }
        if densityChanged || previousCount != cards.count {
            repairFrame(for: resolvedDensity, preserveSavedPosition: true)
        }
        if preferences.isEnabled, shouldBeVisible, !cards.isEmpty {
            if !panel.isVisible { show() }
        } else {
            if panel.isVisible { hide(savePosition: false) }
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        guard preferences.isEnabled != isEnabled else { return }
        preferences.isEnabled = isEnabled
        shouldBeVisible = isEnabled
        persist()
        if isEnabled, !cards.isEmpty {
            show()
        } else {
            hide(savePosition: false)
        }
    }

    func toggleVisibility() {
        guard preferences.isEnabled, !cards.isEmpty else { return }
        shouldBeVisible = !panel.isVisible
        shouldBeVisible ? show() : hide()
    }

    func setAlwaysOnTop(_ isAlwaysOnTop: Bool) {
        guard preferences.isAlwaysOnTop != isAlwaysOnTop else { return }
        preferences.isAlwaysOnTop = isAlwaysOnTop
        panel.level = isAlwaysOnTop ? .floating : .normal
        persist()
    }

    func setDensity(_ density: DesktopAssistantDensity) {
        guard preferences.density != density else { return }
        preferences.density = density
        persist()
        let resolvedDensity = density.resolvedDensity(visibleProviderCount: cards.count)
        installContent(density: resolvedDensity)
        repairFrame(for: resolvedDensity, preserveSavedPosition: true)
    }

    func tearDown() {
        positionSaveTask?.cancel()
        positionSaveTask = nil
        saveCurrentPosition()
        panel.orderOut(nil)
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        preferencesObservation?.cancel()
        preferencesObservation = nil
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The clipped material boundary is the Assistant's sole contour owner.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = true
        // The hosting view's one AppKit pan recognizer owns drag arbitration.
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.level = preferences.isAlwaysOnTop ? .floating : .normal
        panel.assistantContextMenuProvider = { [weak self] in
            guard let self else { return nil }
            let menu = self.makeContextMenu()
            self.panel.contentView?.menu = menu
            return menu
        }
    }

    private func installContent(density: DesktopAssistantResolvedDensity) {
        renderedDensity = density
        let hostingView = NSHostingView(
            rootView: DesktopAssistantView(
                cards: cards,
                density: density,
                showsStatusIndicator: showsStatusIndicator,
                showsPercentageRail: showsPercentageRail,
                onSelectCard: { [weak self] providerID in
                    self?.handleSelection(providerID: providerID)
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.menu = makeContextMenu()
        let dragRecognizer = DesktopAssistantDragGestureRecognizer(
            target: panel,
            action: #selector(DesktopAssistantPanel.handleAssistantDrag(_:))
        )
        dragRecognizer.delaysPrimaryMouseButtonEvents = true
        hostingView.addGestureRecognizer(dragRecognizer)
        panel.contentView = hostingView
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier?.rawValue == "uma.desktop-wizard.context" else { return }
        menu.removeAllItems()
        populateContextMenu(menu)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Desktop Assistant")
        menu.identifier = NSUserInterfaceItemIdentifier("uma.desktop-wizard.context")
        menu.autoenablesItems = false
        menu.delegate = self
        populateContextMenu(menu)
        return menu
    }

    private func populateContextMenu(_ menu: NSMenu) {
        let language = preferenceStore.value(for: UMAApplicationPreferenceKeys.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
        func localized(_ english: String, _ chinese: String) -> String {
            language == .simplifiedChinese ? chinese : english
        }

        let visibilityItem = NSMenuItem(
            title: panel.isVisible
                ? localized("Hide Desktop Assistant", "隐藏桌面助手")
                : localized("Show Desktop Assistant", "显示桌面助手"),
            action: #selector(toggleVisibilityFromContextMenu),
            keyEquivalent: ""
        )
        visibilityItem.target = self
        visibilityItem.isEnabled = preferences.isEnabled && !cards.isEmpty
        menu.addItem(visibilityItem)

        let enabledItem = NSMenuItem(
            title: localized("Enabled", "已启用"),
            action: #selector(toggleEnabledFromContextMenu),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = preferences.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        let alwaysOnTopItem = NSMenuItem(
            title: localized("Always on Top", "始终置顶"),
            action: #selector(toggleAlwaysOnTopFromContextMenu),
            keyEquivalent: ""
        )
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = preferences.isAlwaysOnTop ? .on : .off
        menu.addItem(alwaysOnTopItem)
        menu.addItem(.separator())

        let densityItem = NSMenuItem(
            title: localized("Density", "密度"),
            action: nil,
            keyEquivalent: ""
        )
        let densityMenu = NSMenu(title: localized("Density", "密度"))
        for density in DesktopAssistantDensity.allCases {
            let item = NSMenuItem(
                title: density.contextMenuTitle(language: language),
                action: #selector(selectDensityFromContextMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = density.rawValue
            item.state = preferences.density == density ? .on : .off
            densityMenu.addItem(item)
        }
        densityItem.submenu = densityMenu
        menu.addItem(densityItem)
    }

    @objc private func toggleVisibilityFromContextMenu() {
        toggleVisibility()
    }

    @objc private func toggleEnabledFromContextMenu() {
        setEnabled(!preferences.isEnabled)
    }

    @objc private func toggleAlwaysOnTopFromContextMenu() {
        setAlwaysOnTop(!preferences.isAlwaysOnTop)
    }

    @objc private func selectDensityFromContextMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let density = DesktopAssistantDensity(rawValue: rawValue) else { return }
        setDensity(density)
    }

    func handleSelection(providerID: String) {
        onSelectProvider?(providerID)
    }

    private func show() {
        guard !panel.isVisible else { return }
        let resolvedDensity = preferences.density.resolvedDensity(
            visibleProviderCount: cards.count
        )
        repairFrame(for: resolvedDensity, preserveSavedPosition: true)
        panel.orderFrontRegardless()
    }

    private func hide(savePosition: Bool = true) {
        guard panel.isVisible else { return }
        if savePosition {
            saveCurrentPosition()
        }
        panel.orderOut(nil)
    }

    private func installWindowObservers() {
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isApplyingFrame else { return }
                self.schedulePositionSave()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let density = self.preferences.density.resolvedDensity(
                    visibleProviderCount: self.cards.count
                )
                self.repairFrame(for: density, preserveSavedPosition: true)
            }
        }
    }

    private func installPreferencesObserver() {
        preferencesObservation = preferenceStore.observe { [weak self] change in
            let displayKeys = [
                UMAApplicationPreferenceKeys.assistantShowsStatusIndicator.name,
                UMAApplicationPreferenceKeys.assistantShowsPercentageRail.name,
            ]
            guard DesktopAssistantPreferences.Keys.all.contains(change.key)
                || displayKeys.contains(change.key) else { return }
            self?.applyPreferencesFromStore()
        }
    }

    private func applyPreferencesFromStore() {
        let updated = DesktopAssistantPreferences.load(from: preferenceStore)
        let updatedShowsStatusIndicator = preferenceStore.value(
            for: UMAApplicationPreferenceKeys.assistantShowsStatusIndicator
        )
        let updatedShowsPercentageRail = preferenceStore.value(
            for: UMAApplicationPreferenceKeys.assistantShowsPercentageRail
        )
        guard updated != preferences
            || updatedShowsStatusIndicator != showsStatusIndicator
            || updatedShowsPercentageRail != showsPercentageRail else { return }
        let enabledChanged = updated.isEnabled != preferences.isEnabled
        let levelChanged = updated.isAlwaysOnTop != preferences.isAlwaysOnTop
        let densityChanged = updated.density != preferences.density
        let positionChanged = updated.position != preferences.position
        let displayChanged = updatedShowsStatusIndicator != showsStatusIndicator
            || updatedShowsPercentageRail != showsPercentageRail
        preferences = updated
        showsStatusIndicator = updatedShowsStatusIndicator
        showsPercentageRail = updatedShowsPercentageRail

        if enabledChanged {
            shouldBeVisible = updated.isEnabled
        }
        if levelChanged {
            panel.level = updated.isAlwaysOnTop ? .floating : .normal
        }
        if densityChanged || displayChanged {
            let density = updated.density.resolvedDensity(visibleProviderCount: cards.count)
            installContent(density: density)
            if densityChanged {
                repairFrame(for: density, preserveSavedPosition: true)
            }
        } else if positionChanged {
            let density = updated.density.resolvedDensity(visibleProviderCount: cards.count)
            repairFrame(for: density, preserveSavedPosition: true)
        }

        if updated.isEnabled, shouldBeVisible, !cards.isEmpty {
            if !panel.isVisible { show() }
        } else {
            if panel.isVisible { hide(savePosition: false) }
        }
    }

    private func repairFrame(
        for density: DesktopAssistantResolvedDensity,
        preserveSavedPosition: Bool
    ) {
        let targetSize = DesktopAssistantMetrics.stackSize(
            for: density,
            rowCount: max(1, cards.count),
            valueTexts: cards.map { $0.usageText(for: density) }
        )
        let screen = screenForSavedPosition() ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin: CGPoint
        if preserveSavedPosition, let position = preferences.position {
            let travelX = max(0, visible.width - targetSize.width)
            let travelY = max(0, visible.height - targetSize.height)
            origin = CGPoint(
                x: visible.minX + travelX * position.horizontalFraction,
                y: visible.minY + travelY * position.verticalFraction
            )
        } else {
            origin = CGPoint(
                x: visible.maxX - targetSize.width - 18,
                y: visible.maxY - targetSize.height - 18
            )
        }
        let proposed = NSRect(origin: origin, size: targetSize)
        let targetFrame = clamped(proposed, to: visible)
        guard !NSEqualRects(panel.frame, targetFrame) else { return }
        isApplyingFrame = true
        panel.setFrame(targetFrame, display: panel.isVisible)
        isApplyingFrame = false
    }

    private func saveCurrentPosition() {
        guard let screen = panel.screen ?? screenContaining(panel.frame) else { return }
        let visible = screen.visibleFrame
        let travelX = max(0, visible.width - panel.frame.width)
        let travelY = max(0, visible.height - panel.frame.height)
        let horizontal = travelX > 0 ? (panel.frame.minX - visible.minX) / travelX : 0.5
        let vertical = travelY > 0 ? (panel.frame.minY - visible.minY) / travelY : 0.5
        let position = DesktopAssistantPosition(
            displayIdentifier: displayIdentifier(for: screen),
            horizontalFraction: horizontal,
            verticalFraction: vertical
        )
        guard preferences.position != position else { return }
        preferences.position = position
        persist()
    }

    private func schedulePositionSave() {
        positionSaveTask?.cancel()
        positionSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.saveCurrentPosition()
            self?.positionSaveTask = nil
        }
    }

    private func screenForSavedPosition() -> NSScreen? {
        guard let identifier = preferences.position?.displayIdentifier else { return nil }
        return NSScreen.screens.first { displayIdentifier(for: $0) == identifier }
    }

    private func screenContaining(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
    }

    private func displayIdentifier(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }

    private func clamped(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }

    private func persist() {
        preferences.save(to: preferenceStore)
    }
}

private extension DesktopAssistantDensity {
    func contextMenuTitle(language: AppLanguage) -> String {
        switch (language, self) {
        case (.english, .automatic): "Automatic"
        case (.english, .regular): "Regular"
        case (.english, .minimalist): "Minimalist"
        case (.simplifiedChinese, .automatic): "自动"
        case (.simplifiedChinese, .regular): "常规"
        case (.simplifiedChinese, .minimalist): "极简"
        }
    }
}

private extension DesktopAssistantPreferences.Keys {
    static let all: Set<String> = [isEnabled, isAlwaysOnTop, density, position]
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}
