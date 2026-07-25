import AppKit
import CodexUsageUI
import SwiftUI

private final class DesktopAssistantPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Host-owned presentation controller. It receives immutable display cards and
/// owns no provider component, refresh action, timer, scanner, or usage cache.
@MainActor
final class DesktopAssistantPanelController {
    private let panel: DesktopAssistantPanel
    private let defaults: UserDefaults
    private let onSelectProvider: ((String) -> Void)?
    private var preferences: DesktopAssistantPreferences
    private var cards: [DesktopAssistantCard] = []
    private var moveObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var isApplyingFrame = false
    private var shouldBeVisible: Bool
    private var positionSaveTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        onSelectProvider: ((String) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.onSelectProvider = onSelectProvider
        preferences = DesktopAssistantPreferences.load(from: defaults)
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
        configurePanel()
        installWindowObservers()
        installDefaultsObserver()
    }

    var isEnabled: Bool { preferences.isEnabled }
    var isVisible: Bool { panel.isVisible }
    var isAlwaysOnTop: Bool { preferences.isAlwaysOnTop }
    var density: DesktopAssistantDensity { preferences.density }

    func update(cards: [DesktopAssistantCard]) {
        self.cards = cards
        let resolvedDensity = preferences.density.resolvedDensity(
            visibleProviderCount: cards.count
        )
        installContent(density: resolvedDensity)
        repairFrame(for: resolvedDensity, preserveSavedPosition: true)
        if preferences.isEnabled, shouldBeVisible, !cards.isEmpty {
            show()
        } else {
            hide(savePosition: false)
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
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.level = preferences.isAlwaysOnTop ? .floating : .normal
    }

    private func installContent(density: DesktopAssistantResolvedDensity) {
        let hostingView = NSHostingView(
            rootView: DesktopAssistantView(
                cards: cards,
                density: density,
                onSelectCard: { [weak self] providerID in
                    self?.handleSelection(providerID: providerID)
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }

    func handleSelection(providerID: String) {
        onSelectProvider?(providerID)
    }

    private func show() {
        let resolvedDensity = preferences.density.resolvedDensity(
            visibleProviderCount: cards.count
        )
        repairFrame(for: resolvedDensity, preserveSavedPosition: true)
        panel.orderFrontRegardless()
    }

    private func hide(savePosition: Bool = true) {
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

    private func installDefaultsObserver() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyPreferencesFromDefaults()
            }
        }
    }

    private func applyPreferencesFromDefaults() {
        let updated = DesktopAssistantPreferences.load(from: defaults)
        guard updated != preferences else { return }
        let enabledChanged = updated.isEnabled != preferences.isEnabled
        let levelChanged = updated.isAlwaysOnTop != preferences.isAlwaysOnTop
        let densityChanged = updated.density != preferences.density
        let positionChanged = updated.position != preferences.position
        preferences = updated

        if enabledChanged {
            shouldBeVisible = updated.isEnabled
        }
        if levelChanged {
            panel.level = updated.isAlwaysOnTop ? .floating : .normal
        }
        if densityChanged {
            let density = updated.density.resolvedDensity(visibleProviderCount: cards.count)
            installContent(density: density)
            repairFrame(for: density, preserveSavedPosition: true)
        } else if positionChanged {
            let density = updated.density.resolvedDensity(visibleProviderCount: cards.count)
            repairFrame(for: density, preserveSavedPosition: true)
        }

        if updated.isEnabled, shouldBeVisible, !cards.isEmpty {
            show()
        } else {
            hide(savePosition: false)
        }
    }

    private func repairFrame(
        for density: DesktopAssistantResolvedDensity,
        preserveSavedPosition: Bool
    ) {
        let targetSize = DesktopAssistantMetrics.stackSize(
            for: density,
            rowCount: max(1, cards.count)
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
        isApplyingFrame = true
        panel.setFrame(clamped(proposed, to: visible), display: panel.isVisible)
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
        preferences.save(to: defaults)
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}
