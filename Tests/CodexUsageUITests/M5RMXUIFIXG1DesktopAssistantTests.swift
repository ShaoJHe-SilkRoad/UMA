import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("M5RMX-UIFIX-G1 Desktop Assistant interaction contract")
struct M5RMXUIFIXG1DesktopAssistantTests {
    @MainActor
    @Test("Native recognizer preserves clicks and moves only after a drag")
    func nativePanelMovement() throws {
        let panel = DesktopAssistantPanel(
            contentRect: NSRect(x: 100, y: 100, width: 210, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovable = true
        let counter = MouseEventCountingView(
            frame: NSRect(x: 0, y: 0, width: 210, height: 60)
        )
        let recognizer = DesktopAssistantDragGestureRecognizer(
            target: panel,
            action: #selector(DesktopAssistantPanel.handleAssistantDrag(_:))
        )
        recognizer.delaysPrimaryMouseButtonEvents = true
        counter.addGestureRecognizer(recognizer)
        panel.contentView = counter
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }

        panel.sendEvent(
            try mouseEvent(.leftMouseDown, at: NSPoint(x: 105, y: 30), in: panel, number: 1)
        )
        panel.sendEvent(
            try mouseEvent(.leftMouseUp, at: NSPoint(x: 105, y: 30), in: panel, number: 2)
        )
        #expect(counter.mouseDownCount == 1)
        #expect(counter.mouseDraggedCount == 0)
        #expect(counter.mouseUpCount == 1)
        #expect(panel.frame.origin == NSPoint(x: 100, y: 100))

        counter.reset()
        panel.sendEvent(
            try mouseEvent(.leftMouseDown, at: NSPoint(x: 105, y: 30), in: panel, number: 3)
        )
        panel.sendEvent(
            try mouseEvent(.leftMouseDragged, at: NSPoint(x: 106, y: 30), in: panel, number: 4)
        )
        panel.sendEvent(
            try mouseEvent(.leftMouseUp, at: NSPoint(x: 106, y: 30), in: panel, number: 5)
        )
        #expect(counter.mouseDownCount == 1)
        #expect(counter.mouseUpCount == 1)
        #expect(panel.frame.origin == NSPoint(x: 100, y: 100))

        counter.reset()
        panel.sendEvent(
            try mouseEvent(.leftMouseDown, at: NSPoint(x: 105, y: 30), in: panel, number: 6)
        )
        panel.sendEvent(
            try mouseEvent(.leftMouseDragged, at: NSPoint(x: 142, y: 12), in: panel, number: 7)
        )
        panel.sendEvent(
            try mouseEvent(.leftMouseUp, at: NSPoint(x: 142, y: 12), in: panel, number: 8)
        )
        #expect(counter.mouseDownCount == 0)
        #expect(counter.mouseDraggedCount == 0)
        #expect(counter.mouseUpCount == 0)
        #expect(panel.frame.origin != NSPoint(x: 100, y: 100))
    }

    @MainActor
    @Test("Real four-card Assistant stack is universally draggable in both densities")
    func actualAssistantCardEventArbitration() throws {
        try verifyActualAssistantCardEventArbitration(
            density: .regular,
            probes: regularInteractionProbes
        )
        try verifyActualAssistantCardEventArbitration(
            density: .minimalist,
            probes: minimalistInteractionProbes
        )
    }

    @MainActor
    @Test("Panel installs one native event drag owner and one contour owner")
    func runtimeOwnership() throws {
        let suite = "M5RMXUIFIXG1.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        DesktopAssistantPreferences(
            isEnabled: false,
            isAlwaysOnTop: true,
            density: .regular,
            position: nil
        ).save(to: defaults)

        var selected: [String] = []
        let controller = DesktopAssistantPanelController(
            defaults: defaults,
            onSelectProvider: { selected.append($0) }
        )
        controller.update(cards: [card])

        #expect(!controller.usesWindowBackgroundDragging)
        #expect(!controller.hasWindowShadow)
        #expect(controller.assistantDragRecognizerCount == 1)
        #expect(controller.assistantDragDelaysClicks)
        let panel = controller.assistantPanelForTesting
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor.alphaComponent == 0)
        #expect(panel.contentView?.layer?.borderWidth == 0)
        #expect(panel.contentView?.layer?.shadowOpacity == 0)
        #expect(panel.contentView?.gestureRecognizers.count == 1)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        controller.handleSelection(providerID: card.id)
        #expect(selected == [card.id])
        controller.setDensity(.minimalist)
        #expect(controller.assistantDragRecognizerCount == 1)
        #expect(controller.assistantDragDelaysClicks)
        controller.tearDown()
    }

    @Test("Assistant source keeps one material contour and one native drag owner")
    func sourceOwnership() throws {
        let repository = repositoryRoot()
        let view = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Views/DesktopAssistantView.swift"
            ),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageMonitor/App/DesktopAssistantPanelController.swift"
            ),
            encoding: .utf8
        )

        #expect(view.occurrenceCount(of: ".strokeBorder(") == 0)
        // The accepted fill is internal to the existing material row and is
        // clipped by that row's one boundary; whitespace is not the contract.
        let compactView = view.filter { !$0.isWhitespace }
        let backgroundStart = try #require(compactView.range(of: ".background{glassBackground.overlay{"))
        let rowClip = try #require(compactView.range(
            of: ".clipShape(RoundedRectangle(",
            range: backgroundStart.upperBound..<compactView.endIndex
        ))
        let rowBackground = String(compactView[backgroundStart.lowerBound..<rowClip.lowerBound])
        #expect(rowBackground.occurrenceCount(of: "glassBackground") == 1)
        #expect(rowBackground.occurrenceCount(of: ".background{") == 1)
        #expect(rowBackground.occurrenceCount(of: "CompactUsageFill(") == 1)
        #expect(!rowBackground.contains("NSVisualEffectView"))
        #expect(view.contains(".clipShape(RoundedRectangle("))
        #expect(view.contains(".accessibilityLabel(Text(card.accessibilityLabel))"))
        #expect(view.contains(".accessibilityAction"))
        #expect(!view.contains("DragGesture"))
        #expect(!controller.contains("DesktopAssistantDragHitPolicy"))
        #expect(!controller.contains("perimeterWidth"))
        #expect(
            controller.occurrenceCount(of: "DesktopAssistantDragGestureRecognizer(") == 1
        )
        #expect(controller.contains("static let movementThreshold: CGFloat = 4"))
        #expect(controller.contains("dragRecognizer.delaysPrimaryMouseButtonEvents = true"))
        #expect(controller.contains("hostingView.addGestureRecognizer(dragRecognizer)"))
        #expect(controller.contains("panel.hasShadow = false"))
        #expect(controller.contains("panel.isMovableByWindowBackground = false"))
        #expect(!controller.contains("performDrag(with:"))
        #expect(!controller.contains("DesktopAssistantDragOverlayView"))
    }

    @MainActor
    @Test("Task-owned physical review harness")
    func physicalReviewHarness() throws {
        guard ProcessInfo.processInfo.environment["UMA_M5RMX_UIFIX_REVIEW"] == "1" else {
            return
        }
        let harness = DesktopAssistantPhysicalReviewHarness()
        harness.start()
        NSApp.run()
        harness.stop()
    }

    private var card: DesktopAssistantCard {
        DesktopAssistantCard(
            id: "codex.local",
            providerName: "Codex",
            connectionState: .connected,
            selectedWindowShortLabel: "5H",
            selectedWindowAccessibilityLabel: "five-hour window",
            resetText: "Resets later",
            usageValue: .finite(44),
            severity: .normal,
            isStale: false
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @MainActor
    private func verifyActualAssistantCardEventArbitration(
        density: DesktopAssistantDensity,
        probes: [AssistantInteractionProbe]
    ) throws {
        let suite = "M5RMXUIFIXG1.Events.\(density).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        DesktopAssistantPreferences(
            isEnabled: false,
            isAlwaysOnTop: true,
            density: density,
            position: nil
        ).save(to: defaults)

        var selected: [String] = []
        let controller = DesktopAssistantPanelController(
            defaults: defaults,
            onSelectProvider: { selected.append($0) }
        )
        let cards = matrixCards
        controller.update(cards: cards)
        let panel = controller.assistantPanelForTesting
        panel.setFrameOrigin(NSPoint(x: 100, y: 100))
        panel.orderFrontRegardless()
        defer { controller.tearDown() }

        let originalOrigin = panel.frame.origin
        let expectedSize = DesktopAssistantMetrics.stackSize(
            for: density == .regular ? .regular : .minimalist,
            rowCount: cards.count
        )
        #expect(abs(panel.frame.width - expectedSize.width) < 1)
        #expect(panel.frame.height == expectedSize.height)

        var eventNumber = 100
        for probe in probes {
            if let expectedCardID = probe.expectedCardID {
                selected.removeAll()
                panel.setFrameOrigin(originalOrigin)
                try sendMouseSequence(
                    in: panel,
                    locations: [probe.location],
                    firstEventNumber: eventNumber
                )
                eventNumber += 10
                settleMainRunLoop()
                #expect(
                    selected == [expectedCardID],
                    "Stationary click failed at \(probe.name) in \(density)"
                )
                #expect(panel.frame.origin == originalOrigin)

                selected.removeAll()
                panel.setFrameOrigin(originalOrigin)
                try sendMouseSequence(
                    in: panel,
                    locations: [
                        probe.location,
                        NSPoint(x: probe.location.x + 3.5, y: probe.location.y),
                    ],
                    firstEventNumber: eventNumber
                )
                eventNumber += 10
                settleMainRunLoop()
                #expect(
                    selected == [expectedCardID],
                    "Sub-threshold wobble click failed at \(probe.name) in \(density)"
                )
                #expect(panel.frame.origin == originalOrigin)
            }

            selected.removeAll()
            panel.setFrameOrigin(originalOrigin)
            try sendMouseSequence(
                in: panel,
                locations: [
                    probe.location,
                    NSPoint(x: probe.location.x + 18, y: probe.location.y - 8),
                ],
                firstEventNumber: eventNumber
            )
            eventNumber += 10
            settleMainRunLoop()
            #expect(
                selected.isEmpty,
                "Drag leaked a click at \(probe.name) in \(density)"
            )
            #expect(
                panel.frame.origin != originalOrigin,
                "Panel did not move from \(probe.name) in \(density)"
            )
        }
    }

    @MainActor
    private func sendMouseSequence(
        in panel: NSWindow,
        locations: [NSPoint],
        firstEventNumber: Int
    ) throws {
        let start = try #require(locations.first)
        panel.sendEvent(
            try mouseEvent(
                .leftMouseDown,
                at: start,
                in: panel,
                number: firstEventNumber
            )
        )
        for (offset, location) in locations.dropFirst().enumerated() {
            panel.sendEvent(
                try mouseEvent(
                    .leftMouseDragged,
                    at: location,
                    in: panel,
                    number: firstEventNumber + offset + 1
                )
            )
        }
        panel.sendEvent(
            try mouseEvent(
                .leftMouseUp,
                at: locations.last ?? start,
                in: panel,
                number: firstEventNumber + locations.count
            )
        )
    }

    @MainActor
    private func settleMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }

    private var matrixCards: [DesktopAssistantCard] {
        [
            card("codex.local", "Codex", 71),
            card("claude.browserSync", "Claude Code", 44),
            card("workbuddy.accountWeb", "WorkBuddy", 32),
            card("antigravity.cli", "Google Antigravity", 18),
        ]
    }

    private var regularInteractionProbes: [AssistantInteractionProbe] {
        let topCardCenterY = DesktopAssistantMetrics.stackSize(
            for: .regular,
            rowCount: matrixCards.count
        ).height - DesktopAssistantMetrics.regularHeight / 2
        return [
            .init("outer edge", 1, topCardCenterY, "codex.local"),
            .init("row background gap", 105, 62, nil),
            .init("card center", 105, topCardCenterY, "codex.local"),
            .init("provider title", 60, topCardCenterY + 9, "codex.local"),
            .init("percentage value", 184, topCardCenterY, "codex.local"),
            .init("provider icon", 22, topCardCenterY, "codex.local"),
            .init("clickable lower card", 105, 30, "antigravity.cli"),
        ]
    }

    private var minimalistInteractionProbes: [AssistantInteractionProbe] {
        let width = DesktopAssistantMetrics.minimalistWidth
        let topCardCenterY = DesktopAssistantMetrics.stackSize(
            for: .minimalist,
            rowCount: matrixCards.count
        ).height - DesktopAssistantMetrics.minimalistHeight / 2
        return [
            .init("outer edge", 1, topCardCenterY, "codex.local"),
            .init("row background gap", width / 2, 32, nil),
            .init("card center", width / 2, topCardCenterY, "codex.local"),
            .init("provider-name equivalent mark", 12, topCardCenterY, "codex.local"),
            .init("percentage value", 44, topCardCenterY, "codex.local"),
            .init("provider icon", 12, topCardCenterY, "codex.local"),
            .init("clickable lower card", width / 2, 15, "antigravity.cli"),
        ]
    }

    private func card(
        _ id: String,
        _ providerName: String,
        _ remaining: Int
    ) -> DesktopAssistantCard {
        DesktopAssistantCard(
            id: id,
            providerName: providerName,
            connectionState: .connected,
            selectedWindowShortLabel: "5H",
            selectedWindowAccessibilityLabel: "five-hour window",
            resetText: "Resets later",
            usageValue: .finite(remaining),
            tintFraction: Double(remaining) / 100,
            severity: remaining <= 20 ? .critical : .normal,
            isStale: false
        )
    }

    @MainActor
    private func mouseEvent(
        _ type: NSEvent.EventType,
        at location: NSPoint,
        in window: NSWindow,
        number: Int
    ) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: 1
            )
        )
    }

}

private struct AssistantInteractionProbe {
    let name: String
    let location: NSPoint
    let expectedCardID: String?

    init(_ name: String, _ x: CGFloat, _ y: CGFloat, _ expectedCardID: String?) {
        self.name = name
        location = NSPoint(x: x, y: y)
        self.expectedCardID = expectedCardID
    }
}

private final class MouseEventCountingView: NSView {
    private(set) var mouseDownCount = 0
    private(set) var mouseDraggedCount = 0
    private(set) var mouseUpCount = 0

    override func mouseDown(with event: NSEvent) {
        mouseDownCount += 1
    }

    override func mouseDragged(with event: NSEvent) {
        mouseDraggedCount += 1
    }

    override func mouseUp(with event: NSEvent) {
        mouseUpCount += 1
    }

    func reset() {
        mouseDownCount = 0
        mouseDraggedCount = 0
        mouseUpCount = 0
    }
}

@MainActor
private final class DesktopAssistantPhysicalReviewHarness: NSObject {
    private let suite: String
    private let defaults: UserDefaults
    private let controller: DesktopAssistantPanelController
    private let controlWindow: NSWindow
    private let selectionLabel = NSTextField(labelWithString: "Card clicks: 0")
    private var selectionCount = 0

    override init() {
        suite = "M5RMXUIFIXReview.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        DesktopAssistantPreferences(
            isEnabled: true,
            isAlwaysOnTop: true,
            density: .regular,
            position: DesktopAssistantPosition(
                displayIdentifier: nil,
                horizontalFraction: 0.72,
                verticalFraction: 0.68
            )
        ).save(to: defaults)
        controlWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 170),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        var selectionHandler: ((String) -> Void)?
        controller = DesktopAssistantPanelController(
            defaults: defaults,
            onSelectProvider: { providerID in selectionHandler?(providerID) }
        )
        super.init()
        selectionHandler = { [weak self] _ in
            guard let self else { return }
            self.selectionCount += 1
            self.selectionLabel.stringValue = "Card clicks: \(self.selectionCount)"
        }
        configureControlWindow()
    }

    func start() {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .aqua)
        controller.update(cards: Self.cards)
        controlWindow.center()
        controlWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func stop() {
        controller.tearDown()
        controlWindow.orderOut(nil)
        defaults.removePersistentDomain(forName: suite)
    }

    private func configureControlWindow() {
        controlWindow.title = "UMA Desktop Assistant UIFIX Review"
        controlWindow.isReleasedWhenClosed = false
        let instructions = NSTextField(
            wrappingLabelWithString:
                "Drag from the icon, text, percentage, center, edge, and row gaps. "
                + "A stationary click must still open the selected provider exactly once."
        )
        let buttons = NSStackView(views: [
            button("Regular", action: #selector(showRegular)),
            button("Minimalist", action: #selector(showMinimalist)),
            button("Light", action: #selector(showLight)),
            button("Dark", action: #selector(showDark)),
            button("Finish", action: #selector(finish)),
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [instructions, buttons, selectionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(frame: controlWindow.contentView?.bounds ?? .zero)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
        ])
        controlWindow.contentView = content
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func showRegular() {
        controller.setDensity(.regular)
    }

    @objc private func showMinimalist() {
        controller.setDensity(.minimalist)
    }

    @objc private func showLight() {
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    @objc private func showDark() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    @objc private func finish() {
        NSApp.stop(nil)
    }

    private static let cards = [
        card("codex.local", "Codex", 71),
        card("claude.browserSync", "Claude Code", 44),
        card("workbuddy.accountWeb", "WorkBuddy", 32),
        card("antigravity.cli", "Google Antigravity", 18),
    ]

    private static func card(
        _ id: String,
        _ providerName: String,
        _ remaining: Int
    ) -> DesktopAssistantCard {
        DesktopAssistantCard(
            id: id,
            providerName: providerName,
            connectionState: .connected,
            selectedWindowShortLabel: "5H",
            selectedWindowAccessibilityLabel: "five-hour window",
            resetText: "Resets later",
            usageValue: .finite(remaining),
            tintFraction: Double(remaining) / 100,
            severity: remaining <= 20 ? .critical : .normal,
            isStale: false
        )
    }
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
