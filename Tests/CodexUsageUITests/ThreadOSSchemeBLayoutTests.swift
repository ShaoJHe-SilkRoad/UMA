import AppKit
import SwiftUI
import Testing
@testable import CodexUsageUI
@testable import CodexUsageMonitor

@MainActor struct ThreadOSSchemeBLayoutTests {
    @Test func promptComposerFitsAttachedWindowsAcrossSizesLanguagesAndAppearances() throws {
        _ = NSApplication.shared
        for fixture in PromptComposerFixture.cases {
            let host = NSHostingView(rootView: ThreadOSSettingsView(
                language: fixture.language,
                preferences: .inMemory()
            ))
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.appearance = NSAppearance(named: fixture.appearance)
            window.setContentSize(fixture.contentSize)
            window.orderFront(nil)
            defer { window.orderOut(nil) }

            settle(host)
            #expect(window.contentView?.bounds.size == fixture.contentSize)
            #expect(host.bounds.size == fixture.contentSize)
            #expect(host.fittingSize.width.isFinite && host.fittingSize.height.isFinite)
            #expect(host.fittingSize.height <= fixture.contentSize.height + 1)

            let scroll = try #require(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
            let document = try #require(scroll.documentView)
            let viewport = scroll.contentView.bounds
            let viewportInHost = scroll.contentView.convert(viewport, to: host)
            #expect(scroll.window === window)
            #expect(host.bounds.contains(viewportInHost))
            #expect(!scroll.hasHorizontalScroller)
            #expect(viewport.width.isFinite && viewport.height.isFinite)
            #expect(viewport.width > 0 && viewport.height > 0)
            #expect(document.frame.width.isFinite && document.frame.height.isFinite)
            #expect(document.frame.width > 0 && document.frame.height > 0)
            #expect(document.frame.width <= viewport.width + 1)
            #expect(document.frame.height <= viewport.height + 1, "The compact composer must not force a tall blank document.")
        }
    }

    @Test func promptComposerMovesKeyboardFocusInAttachedWindow() throws {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        defer { NSApp.setActivationPolicy(previousPolicy) }
        #expect(NSApp.setActivationPolicy(.regular))
        let host = NSHostingView(rootView: ThreadOSPromptComposerView(
            language: .english,
            preferences: .inMemory()
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 552),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil) }
        settle(host)
        #expect(host.window === window)
        #expect(NSApp.isActive)
        #expect(window.isKeyWindow)

        let initialResponder = window.firstResponder
        let tab = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            isARepeat: false,
            keyCode: 48
        ))
        window.sendEvent(tab)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(window.firstResponder !== initialResponder)
        #expect(window.firstResponder !== window)
    }

    @Test func promptComposerNativeControlsAcceptAttachedWindowFocusAndHaveActions() throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: ThreadOSPromptComposerView(
            language: .english,
            preferences: .inMemory()
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 552),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)

        let descendants = descendants(of: host)
        let popups = descendants.compactMap { $0 as? NSPopUpButton }
        let copyButton = try #require(descendants.compactMap { $0 as? NSButton }.first)
        #expect(host.window === window)
        #expect(popups.count == 8)
        #expect(popups.allSatisfy { $0.window === window && !$0.refusesFirstResponder && $0.action != nil && $0.selectedItem != nil })
        #expect(copyButton.window === window)
        #expect(!copyButton.refusesFirstResponder)
        #expect(copyButton.action != nil)

        let controls: [NSControl] = popups.map { $0 as NSControl } + [copyButton]
        for control in controls {
            #expect(window.makeFirstResponder(control))
            #expect(window.firstResponder === control)
        }
    }

    @Test func promptComposerTraversesAttachedWindowKeyViewLoopInBothDirections() throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: ThreadOSPromptComposerView(
            language: .english,
            preferences: .inMemory()
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 552),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let copyIdentifier = "uma.threados.prompt.generate-copy"
        let prelinkCopy = try #require(descendants(of: host).first { $0.accessibilityIdentifier() == copyIdentifier })
        let originalCopyOutgoingKeyView = prelinkCopy.nextKeyView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let views = descendants(of: host)
        let identifiers = ThreadOSPromptRole.allCases.flatMap { role in
            ["uma.threados.prompt.role.\(role.rawValue).model", "uma.threados.prompt.role.\(role.rawValue).effort"]
        } + ["uma.threados.prompt.generate-copy"]
        let byIdentifier = Dictionary(uniqueKeysWithValues: views.compactMap { view in
            let identifier = view.accessibilityIdentifier()
            return identifiers.contains(identifier) ? (identifier, view) : nil
        })
        let controls = try identifiers.map { try #require(byIdentifier[$0]) }
        let anchor = try #require(window.initialFirstResponder)
        #expect(controls.count == 9)
        #expect(anchor.nextKeyView === controls[0])
        #expect(controls.allSatisfy {
            $0.window === window && $0.canBecomeKeyView && $0.focusRingType == .exterior
        })
        for (current, next) in zip(controls, controls.dropFirst()) {
            #expect(current.nextKeyView === next)
        }
        #expect(controls.last?.nextKeyView === originalCopyOutgoingKeyView)

        #expect(window.makeFirstResponder(window))
        for control in controls {
            window.selectNextKeyView(nil)
            #expect(window.firstResponder === control)
        }
        window.selectNextKeyView(nil)
        #expect(window.firstResponder === controls[0])
        window.selectPreviousKeyView(nil)
        #expect(window.firstResponder === controls.last)
        for control in controls.reversed().dropFirst() {
            window.selectPreviousKeyView(nil)
            #expect(window.firstResponder === control)
        }
        #expect(controls.count == 9)
    }

    @Test func promptComposerKeepsMainWindowToolbarInKeyViewRouteAndRestoresItWhenLeaving() throws {
        _ = NSApplication.shared
        let controller = MainWindowController(restoresSavedFrame: false)
        var scanActionCount = 0
        var refreshActionCount = 0
        var settingsActionCount = 0
        controller.attach(
            store: UsageStore.preview(language: .english),
            openSettings: { settingsActionCount += 1 },
            scanAll: { scanActionCount += 1 },
            refreshAll: { refreshActionCount += 1 },
            connectCodex: {},
            disconnectCodex: {},
            claudeControlState: { .consentRequired },
            connectClaude: {},
            accuracySyncClaude: {}
        )
        defer { controller.tearDown() }

        controller.showDestination(.threadOS)
        guard let window = controller.window, let contentView = window.contentView else {
            Issue.record("Main UMA window did not attach its content view")
            return
        }
        contentView.layoutSubtreeIfNeeded()
        let boundaryIdentifier = "uma.threados.prompt.key-view-boundary"
        let prelinkBoundary = try #require(descendants(of: contentView).first {
            $0.accessibilityIdentifier() == boundaryIdentifier
        })
        let prelinkPrevious = prelinkBoundary.previousKeyView
        let prelinkNext = prelinkBoundary.nextKeyView
        settle(contentView)
        let boundary = try #require(descendants(of: contentView).first {
            $0.accessibilityIdentifier() == boundaryIdentifier
        })
        let refreshButton = try #require(descendants(of: contentView).compactMap { $0 as? NSButton }.first {
            $0.accessibilityIdentifier() == "uma.main.refresh"
        })
        let scanButton = try #require(descendants(of: contentView).compactMap { $0 as? NSButton }.first {
            $0.accessibilityIdentifier() == "uma.main.scan"
        })
        let settingsButton = try #require(descendants(of: contentView).compactMap { $0 as? NSButton }.first {
            $0.accessibilityIdentifier() == "uma.main.settings"
        })
        #expect(!refreshButton.isEnabled)
        #expect(scanButton.isEnabled)
        #expect(settingsButton.isEnabled)
        scanButton.performClick(nil)
        refreshButton.performClick(nil)
        settingsButton.performClick(nil)
        #expect(scanActionCount == 1)
        #expect(refreshActionCount == 0)
        #expect(settingsActionCount == 1)
        let incomingBoundaryLink = descendants(of: contentView).first { $0.nextKeyView === boundary }
        let threadOSRoute = keyViewRoute(in: window)
        let threadOSIdentifiers = threadOSRoute.compactMap(accessibilityIdentifier(in:))
            + keyViewAccessibilityIdentifiers(in: window)
        let composerIdentifiers = ThreadOSPromptRole.allCases.flatMap { role in
            ["uma.threados.prompt.role.\(role.rawValue).model", "uma.threados.prompt.role.\(role.rawValue).effort"]
        } + ["uma.threados.prompt.generate-copy"]
        for identifier in composerIdentifiers {
            #expect(threadOSIdentifiers.contains(identifier))
        }
        for identifier in ["uma.main.scan", "uma.main.refresh", "uma.main.settings"] {
            #expect(threadOSIdentifiers.contains(identifier))
        }
        #expect(incomingBoundaryLink === boundary.previousKeyView)
        #expect(threadOSRoute.contains { accessibilityLabel(in: $0) == "UMA navigation" })

        controller.showDestination(.agents)
        guard let agentsContentView = window.contentView else {
            Issue.record("Main UMA window lost its content view after leaving ThreadOS")
            return
        }
        settle(agentsContentView)
        #expect(boundary.previousKeyView === prelinkPrevious)
        #expect(boundary.nextKeyView === prelinkNext)
        let agentsRoute = keyViewRoute(in: window)
        let agentsIdentifiers = agentsRoute.compactMap(accessibilityIdentifier(in:))
        for identifier in ["uma.main.scan", "uma.main.refresh", "uma.main.settings"] {
            #expect(agentsIdentifiers.contains(identifier))
        }
        #expect(agentsRoute.contains { accessibilityLabel(in: $0) == "UMA navigation" })
        #expect(!agentsIdentifiers.contains("uma.threados.prompt.generate-copy"))
    }

    @Test func workerExpansionIsPreservedIndependentlyForEachProjectAndAcrossReopen() {
        let preferences = ApplicationPreferences.inMemory()
        let alpha: Set<FactoriumV2Role> = [.coder]
        let beta: Set<FactoriumV2Role> = [.reviewer, .repair]
        ThreadOSSettingsPreferences.saveFactoriumV2ExpandedGroups(alpha, project: "ALPHA", to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2ExpandedGroups(beta, project: "BETA", to: preferences)

        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "ALPHA", from: preferences) == alpha)
        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "BETA", from: preferences) == beta)
        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "ALPHA", from: preferences) == alpha)
    }

    private func draft(for fixture: LayoutFixture) -> FactoriumV2SettingsDraft {
        var draft = FactoriumV2SettingsDraft(project: "SCHEME_B_LAYOUT")
        if !fixture.leaderPreserved {
            var leader = draft.roles[.leader]!
            leader.preserve = false
            draft.roles[.leader] = leader
        }
        for role in [FactoriumV2Role.coder, .reviewer] {
            var slots = draft.workers(for: role)
            slots[0].inherits = false; slots[0].hasCustomSelection = true; slots[0].selection.effort = "high"
            slots[1].enabled = false
            slots[2].inherits = false; slots[2].hasCustomSelection = true; slots[2].selection.speed = "standard"
            draft.setWorkers(slots, for: role)
        }
        return draft
    }

    private func settle(_ host: NSView) {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
    }

    private func keyViewRoute(in window: NSWindow) -> [NSView] {
        guard window.makeFirstResponder(window) else { return [] }
        var route: [NSView] = []
        var seen = Set<ObjectIdentifier>()
        for _ in 0..<160 {
            window.selectNextKeyView(nil)
            guard let view = window.firstResponder as? NSView else { continue }
            guard seen.insert(ObjectIdentifier(view)).inserted else { break }
            route.append(view)
        }
        return route
    }

    private func keyViewAccessibilityIdentifiers(in window: NSWindow) -> [String] {
        var identifiers: [String] = []
        var seenStates = Set<String>()
        for _ in 0..<160 {
            window.selectNextKeyView(nil)
            let focusedElement = window.accessibilityFocusedUIElement
            let focusedIdentifier = (focusedElement as? NSAccessibilityElement)?.accessibilityIdentifier()
                ?? (window.firstResponder as? NSView).flatMap(accessibilityIdentifier(in:))
            let state = "\(String(describing: window.firstResponder))|\(focusedIdentifier ?? "")"
            guard seenStates.insert(state).inserted else { break }
            if let focusedIdentifier, !focusedIdentifier.isEmpty {
                identifiers.append(focusedIdentifier)
            }
        }
        return identifiers
    }

    private func accessibilityIdentifier(in view: NSView) -> String? {
        var current: NSView? = view
        while let candidate = current {
            let identifier = candidate.accessibilityIdentifier()
            if !identifier.isEmpty { return identifier }
            current = candidate.superview
        }
        return nil
    }

    private func accessibilityLabel(in view: NSView) -> String? {
        var current: NSView? = view
        while let candidate = current {
            if let label = candidate.accessibilityLabel(), !label.isEmpty { return label }
            current = candidate.superview
        }
        return nil
    }

    private func descendants(of view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }

    private func emitEvidenceIfRequested(fixture: LayoutFixture, window: NSWindow, host: NSView, scroll: NSScrollView, document: NSView, initialFrames: [String: CGRect], endFrames: [String: CGRect], endOffset: CGFloat) {
        guard let root = ProcessInfo.processInfo.environment["TOSUMA_UI_B_EVIDENCE_DIR"], !root.isEmpty else { return }
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let metric = LayoutMetric(fixture: fixture.identifier, hostedRuntime: true, installedRuntime: false, mainShellToolbarHeightFromSource: 48, hostedShellReservation: MainShellReservedHostedView.reservedHeight, wholeWindow: .init(window.frame), content: .init(host.bounds), appKitScrollBoundsAtEnd: .init(scroll.contentView.bounds), document: .init(document.frame), endScrollOffsetY: endOffset, initialFrames: initialFrames.mapValues(Rect.init), endFrames: endFrames.mapValues(Rect.init))
        if let data = try? JSONEncoder.pretty.encode(metric) { try? data.write(to: directory.appendingPathComponent("\(fixture.identifier).json"), options: .atomic) }
        let bounds = host.bounds
        guard let image = host.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        host.cacheDisplay(in: bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(fixture.identifier)-end.png"), options: .atomic)
    }

    private func captureIfRequested(fixture: LayoutFixture, host: NSView, suffix: String) {
        guard let root = ProcessInfo.processInfo.environment["TOSUMA_UI_B_EVIDENCE_DIR"], !root.isEmpty else { return }
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bounds = host.bounds
        guard let image = host.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        host.cacheDisplay(in: bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(fixture.identifier)-\(suffix).png"), options: .atomic)
    }

    private struct LayoutFixture {
        let identifier: String; let contentSize: NSSize; let language: AppLanguage; let appearance: NSAppearance.Name; let groups: Set<FactoriumV2Role>; let leaderPreserved: Bool; let requiresInitialPrimaryContainment: Bool; let footerStatus: String?
        static let requiredCases = [
            LayoutFixture(identifier: "hosted-settings-1040x760-content-en-light-fresh-coder-reviewer-summary", contentSize: .init(width: 1_040, height: 760), language: .english, appearance: .aqua, groups: [.coder], leaderPreserved: true, requiresInitialPrimaryContainment: true, footerStatus: nil),
            LayoutFixture(identifier: "hosted-settings-1000x760-content-en-light-both", contentSize: .init(width: 1_000, height: 760), language: .english, appearance: .aqua, groups: [.coder, .reviewer], leaderPreserved: true, requiresInitialPrimaryContainment: true, footerStatus: nil),
            LayoutFixture(identifier: "hosted-settings-1000x760-content-en-light-copy-failure", contentSize: .init(width: 1_000, height: 760), language: .english, appearance: .aqua, groups: [.coder, .reviewer], leaderPreserved: true, requiresInitialPrimaryContainment: false, footerStatus: "Request was generated, but the local clipboard could not be written."),
            LayoutFixture(identifier: "hosted-settings-760x552-content-zh-dark-both", contentSize: .init(width: 760, height: 552), language: .simplifiedChinese, appearance: .darkAqua, groups: [.coder, .reviewer], leaderPreserved: false, requiresInitialPrimaryContainment: false, footerStatus: nil),
            LayoutFixture(identifier: "hosted-settings-1280x900-content-zh-light-both", contentSize: .init(width: 1_280, height: 900), language: .simplifiedChinese, appearance: .aqua, groups: [.coder, .reviewer], leaderPreserved: false, requiresInitialPrimaryContainment: false, footerStatus: nil),
            LayoutFixture(identifier: "hosted-settings-1280x900-content-en-dark-both", contentSize: .init(width: 1_280, height: 900), language: .english, appearance: .darkAqua, groups: [.coder, .reviewer], leaderPreserved: true, requiresInitialPrimaryContainment: false, footerStatus: nil),
        ]
    }


    private struct LayoutMetric: Codable {
        let fixture: String; let hostedRuntime: Bool; let installedRuntime: Bool; let mainShellToolbarHeightFromSource: CGFloat; let hostedShellReservation: CGFloat; let wholeWindow: Rect; let content: Rect; let appKitScrollBoundsAtEnd: Rect; let document: Rect; let endScrollOffsetY: CGFloat; let initialFrames: [String: Rect]; let endFrames: [String: Rect]
    }

    private struct Rect: Codable {
        let x: CGFloat; let y: CGFloat; let width: CGFloat; let height: CGFloat
        init(_ value: CGRect) { x = value.origin.x; y = value.origin.y; width = value.width; height = value.height }
    }

    private struct PromptComposerFixture {
        let contentSize: NSSize
        let language: AppLanguage
        let appearance: NSAppearance.Name

        static let cases = [
            PromptComposerFixture(contentSize: .init(width: 760, height: 552), language: .english, appearance: .aqua),
            PromptComposerFixture(contentSize: .init(width: 760, height: 552), language: .simplifiedChinese, appearance: .darkAqua),
            PromptComposerFixture(contentSize: .init(width: 823, height: 640), language: .english, appearance: .darkAqua),
            PromptComposerFixture(contentSize: .init(width: 823, height: 640), language: .simplifiedChinese, appearance: .aqua),
            PromptComposerFixture(contentSize: .init(width: 1_040, height: 760), language: .english, appearance: .aqua),
            PromptComposerFixture(contentSize: .init(width: 1_040, height: 760), language: .simplifiedChinese, appearance: .darkAqua),
            PromptComposerFixture(contentSize: .init(width: 1_440, height: 900), language: .english, appearance: .aqua),
            PromptComposerFixture(contentSize: .init(width: 1_440, height: 900), language: .simplifiedChinese, appearance: .darkAqua),
        ]
    }
}

/// Mirrors the actual main shell's 48-point toolbar plus divider without
/// claiming that an isolated settings host is a complete installed app.
private struct MainShellReservedHostedView: View {
    static let reservedHeight: CGFloat = 49
    let settings: ThreadOSSettingsView

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 48).accessibilityHidden(true)
            Divider()
            settings
        }
    }


}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }
}
