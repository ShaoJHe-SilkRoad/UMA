import AppKit
import SwiftUI
import Testing
import HESectoriumCore
import HESectoriumRuntime
@testable import CodexUsageUI
@testable import CodexUsageMonitor

@Suite(.serialized)
@MainActor struct ThreadOSSchemeBLayoutTests {
    @Test func sectoriumCapacityInputIsBoundedAndRecommendationCannotOverflow() {
        let oneGiB: UInt64 = 1_073_741_824
        #expect(SectoriumCapacityInput.requestedBytes(gib: Int.min) == nil)
        #expect(SectoriumCapacityInput.requestedBytes(gib: 0) == nil)
        #expect(SectoriumCapacityInput.requestedBytes(gib: 1) == oneGiB)
        #expect(SectoriumCapacityInput.requestedBytes(gib: 16_384) == 16_384 * oneGiB)
        #expect(SectoriumCapacityInput.requestedBytes(gib: 16_385) == nil)
        #expect(SectoriumCapacityInput.requestedBytes(gib: Int.max) == nil)
        #expect(SectoriumCapacityInput.recommendedGiB(availableBytes: oneGiB) == nil)
        #expect(SectoriumCapacityInput.recommendedGiB(availableBytes: oneGiB * 10) == 8)
        #expect(SectoriumCapacityInput.recommendedGiB(availableBytes: UInt64.max) == 16_384)
    }

    @Test func promptRouteRetryStopsForAnIncompleteMountedRoute() {
        var attempts = 0
        let retry = ThreadOSPromptKeyViewRouteRetryController(
            interval: 0.005, maximumPolls: 3, requiredSuccesses: 2
        ) {
            attempts += 1
            return false
        }
        retry.start()
        waitForRetryToStop(retry)

        #expect(!retry.isActive)
        #expect(retry.pollCount == 3)
        #expect(attempts == 3)
        RunLoop.main.run(until: Date().addingTimeInterval(0.025))
        retry.start()
        #expect(retry.pollCount == 3, "A completed retry budget must not restart on an ordinary update.")
        #expect(attempts == 3)
    }

    @Test func promptRouteRetryRecoversWhenControlsArriveWithinItsBudget() {
        var attempts = 0
        let retry = ThreadOSPromptKeyViewRouteRetryController(
            interval: 0.005, maximumPolls: 8, requiredSuccesses: 4
        ) {
            attempts += 1
            return attempts >= 3
        }
        retry.start()
        waitForRetryToStop(retry)

        #expect(!retry.isActive)
        #expect(retry.pollCount == 6)
        #expect(attempts == 6)
    }

    @Test func promptRouteRetryGetsAFreshBudgetAfterWindowAttachmentChanges() {
        var routeIsAvailable = false
        let retry = ThreadOSPromptKeyViewRouteRetryController(
            interval: 0.005, maximumPolls: 2, requiredSuccesses: 2
        ) { routeIsAvailable }
        retry.start()
        waitForRetryToStop(retry)
        #expect(retry.pollCount == 2)
        #expect(!retry.isActive)

        routeIsAvailable = true
        retry.reset()
        waitForRetryToStop(retry)
        #expect(!retry.isActive)
        #expect(retry.pollCount == 2)
    }

    @Test func disabledHESettingsActionCoordinatorDoesNotInvokeItsAction() {
        var activations = 0
        let coordinator = HESectoriumSettingsControlCoordinator { _ in activations += 1 }
        let button = NSButton(title: "Refresh Status", target: nil, action: nil)
        button.isEnabled = false
        coordinator.activate(button)
        #expect(activations == 0)

        button.isEnabled = true
        coordinator.activate(button)
        #expect(activations == 1)
    }

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

    @Test func promptComposerUsesUsableContentWidthAt680PointBreakpoint() throws {
        _ = NSApplication.shared
        for (width, usesColumns) in [(720.0, true), (719.0, false)] {
            let host = NSHostingView(rootView: ThreadOSPromptComposerView(
                language: .english,
                preferences: .inMemory()
            ))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 720),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            settle(host)

            let views = descendants(of: host)
            let copy = try #require(views.first { $0.accessibilityIdentifier() == "uma.threados.prompt.generate-copy" })
            let qaEffort = try #require(views.first {
                $0.accessibilityIdentifier() == "uma.threados.prompt.role.qa.effort"
            })
            let copyY = copy.convert(copy.bounds, to: host).midY
            let qaEffortY = qaEffort.convert(qaEffort.bounds, to: host).midY
            if usesColumns {
                #expect(abs(copyY - qaEffortY) <= 2, "Copy and the QA selector must share a baseline at the two-column breakpoint.")
            } else {
                #expect(copyY > qaEffortY, "Below 680pt of usable content width, the summary and copy control should follow all four roles.")
            }
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
        #expect(controls.count == 9)
        let anchor = try #require(window.contentView)
        #expect(!window.autorecalculatesKeyViewLoop)
        #expect(window.initialFirstResponder === anchor)
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
            let current = window.firstResponder as? NSView
            #expect(current === control)
        }
        #expect(window.makeFirstResponder(controls[controls.count - 1]))
        for control in controls.reversed().dropFirst() {
            window.selectPreviousKeyView(nil)
            let current = window.firstResponder as? NSView
            #expect(current === control)
        }
        #expect(controls.count == 9)
    }

    @Test func stackedComposerKeyboardFocusKeepsControlsVisibleInShortScrollViewport() throws {
        _ = NSApplication.shared
        let contentView = NSHostingView(rootView: ThreadOSPromptComposerView(
            language: .english, preferences: .inMemory()
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 719, height: 320),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = contentView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(contentView)

        let identifiers = ThreadOSPromptRole.allCases.flatMap { role in
            ["uma.threados.prompt.role.\(role.rawValue).model", "uma.threados.prompt.role.\(role.rawValue).effort"]
        } + ["uma.threados.prompt.generate-copy"]
        let identifierSet = Set(identifiers)
        let scroll = try #require(descendants(of: contentView).compactMap { $0 as? NSScrollView }.first {
            descendants(of: $0).contains { identifierSet.contains($0.accessibilityIdentifier()) }
        })
        let controlsByIdentifier = Dictionary(uniqueKeysWithValues: descendants(of: scroll).compactMap { view in
            let identifier = view.accessibilityIdentifier()
            return identifierSet.contains(identifier) ? (identifier, view) : nil
        })
        let controls = try identifiers.map { try #require(controlsByIdentifier[$0]) }
        let copyControl = try #require(controlsByIdentifier["uma.threados.prompt.generate-copy"])
        let finalRoleControl = try #require(controlsByIdentifier["uma.threados.prompt.role.qa.effort"])
        func focusRectInViewport(_ view: NSView) -> NSRect {
            view.convert(view.bounds, to: scroll.contentView).insetBy(dx: -6, dy: -6)
        }

        #expect(controls.count == 9)
        #expect(controls.allSatisfy { $0.window === window && $0.canBecomeKeyView && $0.focusRingType == .exterior })
        let finalRoleStartsOutsideViewport = !scroll.contentView.bounds.contains(focusRectInViewport(finalRoleControl))
        #expect(finalRoleStartsOutsideViewport, "The final role control must start outside the visible viewport for this regression to be meaningful.")
        #expect(window.makeFirstResponder(window))

        var forwardVisible = Set<String>()
        for _ in 0..<40 {
            window.selectNextKeyView(nil)
            guard let focused = window.firstResponder as? NSView else { continue }
            let identifier = accessibilityIdentifier(in: focused) ?? ""
            guard identifierSet.contains(identifier), let focusedControl = controlsByIdentifier[identifier] else { continue }
            forwardVisible.insert(identifier)
            #expect(scroll.contentView.bounds.contains(focusRectInViewport(focusedControl)), "Forward focus \(identifier) must be visible without manual scrolling.")
            if forwardVisible.count == identifierSet.count { break }
        }
        #expect(forwardVisible == identifierSet)

        #expect(window.makeFirstResponder(copyControl))
        var reverseVisible: Set<String> = ["uma.threados.prompt.generate-copy"]
        #expect(scroll.contentView.bounds.contains(focusRectInViewport(copyControl)))
        for _ in 0..<40 {
            window.selectPreviousKeyView(nil)
            guard let focused = window.firstResponder as? NSView else { continue }
            let identifier = accessibilityIdentifier(in: focused) ?? ""
            guard identifierSet.contains(identifier), let focusedControl = controlsByIdentifier[identifier] else { continue }
            reverseVisible.insert(identifier)
            #expect(scroll.contentView.bounds.contains(focusRectInViewport(focusedControl)), "Reverse focus \(identifier) must be visible without manual scrolling.")
            if reverseVisible.count == identifierSet.count { break }
        }
        #expect(reverseVisible == identifierSet)
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

        let originalAutorecalculatesKeyViewLoop = try #require(controller.window).autorecalculatesKeyViewLoop
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
        settle(contentView)
        let boundary = try #require(descendants(of: contentView).first {
            $0.accessibilityIdentifier() == boundaryIdentifier
        })
        #expect(!window.autorecalculatesKeyViewLoop)
        let settingsButton = try #require(descendants(of: contentView).compactMap { $0 as? NSButton }.first {
            $0.accessibilityIdentifier() == "uma.main.settings"
        })
        #expect(settingsButton.isEnabled)
        settingsButton.performClick(nil)
        #expect(scanActionCount == 0)
        #expect(refreshActionCount == 0)
        #expect(settingsActionCount == 1)
        let threadOSRoute = keyViewRoute(in: window)
        let threadOSIdentifiers = threadOSRoute.compactMap(accessibilityIdentifier(in:))
            + keyViewAccessibilityIdentifiers(in: window)
        let composerIdentifiers = ThreadOSPromptRole.allCases.flatMap { role in
            ["uma.threados.prompt.role.\(role.rawValue).model", "uma.threados.prompt.role.\(role.rawValue).effort"]
        } + ["uma.threados.prompt.generate-copy"]
        for identifier in composerIdentifiers {
            #expect(threadOSIdentifiers.contains(identifier))
        }
        for identifier in ["uma.main.settings"] {
            #expect(threadOSIdentifiers.contains(identifier))
        }
        #expect(!threadOSIdentifiers.contains("uma.main.scan"))
        #expect(!threadOSIdentifiers.contains("uma.main.refresh"))
        #expect(settingsButton.nextKeyView === boundary)
        #expect(boundary.previousKeyView === settingsButton)
        #expect(threadOSRoute.contains { accessibilityLabel(in: $0) == "UMA navigation" })

        controller.showDestination(.agents)
        guard let agentsContentView = window.contentView else {
            Issue.record("Main UMA window lost its content view after leaving ThreadOS")
            return
        }
        settle(agentsContentView)
        #expect(window.autorecalculatesKeyViewLoop == originalAutorecalculatesKeyViewLoop)
        #expect(boundary.previousKeyView === prelinkPrevious)
        let agentsRoute = keyViewRoute(in: window)
        let agentsIdentifiers = agentsRoute.compactMap(accessibilityIdentifier(in:))
        for identifier in ["uma.main.scan", "uma.main.refresh", "uma.main.settings"] {
            #expect(agentsIdentifiers.contains(identifier))
        }
        #expect(agentsRoute.contains { accessibilityLabel(in: $0) == "UMA navigation" })
        #expect(!agentsIdentifiers.contains { $0.hasPrefix("uma.threados.prompt.role.") })
        #expect(!agentsIdentifiers.contains("uma.threados.prompt.generate-copy"))
    }

    @Test func promptComposerCopyExitsToMainWindowRouteAndReturnsBeforePageSwitchRestoresLinks() throws {
        _ = NSApplication.shared
        let controller = MainWindowController(restoresSavedFrame: false)
        controller.attach(
            store: UsageStore.preview(language: .english),
            openSettings: {},
            scanAll: {},
            refreshAll: {},
            connectCodex: {},
            disconnectCodex: {},
            claudeControlState: { .consentRequired },
            connectClaude: {},
            accuracySyncClaude: {}
        )
        defer { controller.tearDown() }
        let originalAutorecalculatesKeyViewLoop = try #require(controller.window).autorecalculatesKeyViewLoop
        controller.showDestination(.threadOS)
        guard let window = controller.window, let contentView = window.contentView else {
            Issue.record("Main UMA window did not attach its ThreadOS content view")
            return
        }
        contentView.layoutSubtreeIfNeeded()
        let boundaryIdentifier = "uma.threados.prompt.key-view-boundary"
        let prelinkBoundary = try #require(descendants(of: contentView).first {
            $0.accessibilityIdentifier() == boundaryIdentifier
        })
        let boundaryOriginalPrevious = prelinkBoundary.previousKeyView
        settle(contentView)

        let boundary = try #require(descendants(of: contentView).first {
            $0.accessibilityIdentifier() == boundaryIdentifier
        } as? ThreadOSPromptKeyViewLoopBoundaryView)
        let promptIdentifiers = ThreadOSPromptRole.allCases.flatMap { role in
            ["uma.threados.prompt.role.\(role.rawValue).model", "uma.threados.prompt.role.\(role.rawValue).effort"]
        } + ["uma.threados.prompt.generate-copy"]
        let promptViews = Dictionary(uniqueKeysWithValues: descendants(of: contentView).compactMap { view in
            let identifier = view.accessibilityIdentifier()
            return promptIdentifiers.contains(identifier) ? (identifier, view) : nil
        })
        let promptControls = try promptIdentifiers.map { try #require(promptViews[$0]) }
        let copy = try #require(promptViews["uma.threados.prompt.generate-copy"])
        let outerRouteIdentifiers: Set<String> = [
            "uma.main.navigation", "uma.main.scan", "uma.main.refresh", "uma.main.settings"
        ]

        #expect(promptControls.count == 9)
        #expect(promptControls.allSatisfy { $0.window === window && $0.canBecomeKeyView })
        #expect(!window.autorecalculatesKeyViewLoop)
        #expect(window.makeFirstResponder(copy))

        for expected in promptControls.reversed().dropFirst() {
            window.selectPreviousKeyView(nil)
            #expect((window.firstResponder as? NSView) === expected, "Reverse Tab from Copy must traverse every prompt control.")
        }
        for expected in promptControls.dropFirst() {
            window.selectNextKeyView(nil)
            #expect((window.firstResponder as? NSView) === expected, "Forward Tab must traverse every prompt control before leaving Copy.")
        }

        window.selectNextKeyView(nil)
        let afterCopy = window.firstResponder as? NSView
        let afterCopyIdentifier = afterCopy.flatMap(accessibilityIdentifier(in:)) ?? ""
        print("KEYBOARD_REPAIR_ROUTE copy.next=\(String(describing: copy.nextKeyView)) firstResponderAfterCopy=\(String(describing: afterCopy)) id=\(afterCopyIdentifier)")
        #expect(afterCopy !== copy, "Tab from Copy must leave the composer rather than loop or stop on Copy.")
        #expect(outerRouteIdentifiers.contains(afterCopyIdentifier), "Tab from Copy must re-enter the main toolbar navigation route.")

        window.selectPreviousKeyView(nil)
        #expect(window.firstResponder === copy, "Shift-Tab from the outer shell route must return to Copy.")

        controller.showDestination(.agents)
        guard let agentsContentView = window.contentView else {
            Issue.record("Main UMA window lost its content view after leaving ThreadOS")
            return
        }
        settle(agentsContentView)
        #expect(window.autorecalculatesKeyViewLoop == originalAutorecalculatesKeyViewLoop)
        #expect(boundary.previousKeyView === boundaryOriginalPrevious)
        let agentsRoute = keyViewRoute(in: window)
        let agentsIdentifiers = agentsRoute.compactMap(accessibilityIdentifier(in:))
        #expect(agentsIdentifiers.contains("uma.main.navigation"))
        #expect(agentsIdentifiers.contains("uma.main.scan"))
        #expect(agentsIdentifiers.contains("uma.main.settings"))
        #expect(!agentsIdentifiers.contains { $0.hasPrefix("uma.threados.prompt.role.") })
        #expect(!agentsIdentifiers.contains("uma.threados.prompt.generate-copy"))
    }

    @Test func initialMainRouteKeepsStorageOnItsOwnTabAndCopyTraversesToNavigation() throws {
        _ = NSApplication.shared
        let fixture = HESectoriumKeyboardFixture()
        defer { fixture.remove() }
        let clipboard = HESectoriumKeyboardClipboard()
        let controller = MainWindowController(restoresSavedFrame: false)
        controller.attach(
            store: UsageStore.preview(language: .english),
            openSettings: {}, scanAll: {}, refreshAll: {},
            connectCodex: {}, disconnectCodex: {},
            claudeControlState: { .consentRequired }, connectClaude: {}, accuracySyncClaude: {},
            hesectoriumStore: fixture.store, promptClipboard: clipboard
        )
        defer { controller.tearDown() }
        controller.showDestination(.agents)
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        settle(content)

        let navigation = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.main.navigation"
        } as? NSSegmentedControl)
        let initialRoute = keyViewRoute(in: window)
        let initialIDs = initialRoute.compactMap(accessibilityIdentifier(in:))
        #expect(initialIDs.contains("uma.main.navigation"))
        #expect(!initialIDs.contains("uma.hesectorium.quick-actions"))
        #expect(initialIDs.contains("uma.main.scan"))
        #expect(initialIDs.contains("uma.main.refresh"))
        #expect(initialIDs.contains("uma.main.settings"))

        navigation.selectedSegment = 2
        #expect(navigation.sendAction(try #require(navigation.action), to: navigation.target))
        settle(try #require(window.contentView))
        #expect(window.contentView != nil)
        #expect(navigation.selectedSegment == 2)
        #expect(!keyViewRoute(in: window).contains { $0.accessibilityIdentifier() == "uma.hesectorium.quick-actions" })

        navigation.selectedSegment = 1
        #expect(navigation.sendAction(try #require(navigation.action), to: navigation.target))
        settle(try #require(window.contentView))
        let threadContent = try #require(window.contentView)
        let copy = try #require(descendants(of: threadContent).first {
            $0.accessibilityIdentifier() == "uma.threados.prompt.generate-copy"
        } as? NSButton)
        #expect(copy.window === window)
        click(copy, in: window)
        #expect(clipboard.writes.count == 1)
        #expect(copy.nextKeyView === navigation, "Copy must link into the main toolbar route after first-entry composition.")
        #expect(window.makeFirstResponder(copy))
        window.selectNextKeyView(nil)
        #expect(window.firstResponder === navigation)
        window.selectPreviousKeyView(nil)
        #expect(window.firstResponder === copy)
    }

    @Test func attachedMainWindowCopyReceivesNativeTabAndReverseTabEvents() throws {
        _ = NSApplication.shared
        let clipboard = HESectoriumKeyboardClipboard()
        let controller = MainWindowController(restoresSavedFrame: false)
        controller.attach(
            store: UsageStore.preview(language: .simplifiedChinese),
            openSettings: {}, scanAll: {}, refreshAll: {},
            connectCodex: {}, disconnectCodex: {},
            claudeControlState: { .consentRequired }, connectClaude: {}, accuracySyncClaude: {},
            promptClipboard: clipboard
        )
        defer { controller.tearDown() }
        controller.window?.appearance = NSAppearance(named: .darkAqua)
        controller.showDestination(.threadOS)
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        settle(content)
        let copy = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.threados.prompt.generate-copy"
        } as? NSButton)
        let navigation = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.main.navigation"
        } as? NSSegmentedControl)
        let settings = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.main.settings"
        } as? NSButton)
        let boundary = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.threados.prompt.key-view-boundary"
        })
        let leaderModel = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.threados.prompt.role.leader.model"
        })
        click(copy, in: window)
        #expect(clipboard.writes.count == 1)
        #expect(window.firstResponder === copy)

        sendTab(to: window)
        #expect(window.firstResponder === navigation,
                "A native Tab after Copy must enter the attached main toolbar.")
        sendTab(to: window)
        #expect(window.firstResponder === settings,
                "A second native Tab must continue through the toolbar.")
        #expect(navigation.nextKeyView === settings)
        #expect(settings.nextKeyView === boundary,
                "The toolbar must return to the prompt route after Settings.")
        sendTab(to: window)
        #expect(window.firstResponder === leaderModel,
                "Tab from Settings must pass the hidden boundary into the first prompt control.")
        sendTab(to: window, reverse: true)
        #expect(window.firstResponder === settings,
                "Reverse Tab from the first prompt control must leave the composer.")
        sendTab(to: window, reverse: true)
        #expect(window.firstResponder === navigation)
        sendTab(to: window, reverse: true)
        #expect(window.firstResponder === copy,
                "A native reverse Tab must return from the toolbar to Copy.")
    }

    @Test func sectoriumWorkbenchControlsAttachToRealWindowAndFitNarrowContent() throws {
        _ = NSApplication.shared
        let fixture = HESectoriumKeyboardFixture(isExternal: false)
        defer { fixture.remove() }
        fixture.store.selectDevice(fixture.device.id)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)

        let workbenchScroll = try #require(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
        let workbenchDocument = try #require(workbenchScroll.documentView)
        workbenchScroll.contentView.scroll(to: NSPoint(
            x: 0,
            y: max(0, workbenchDocument.frame.height - workbenchScroll.contentView.bounds.height)
        ))
        workbenchScroll.reflectScrolledClipView(workbenchScroll.contentView)
        settle(host)

        let identifiers: Set<String> = [
            "uma.sectorium.refresh", "uma.sectorium.settings",
            "uma.sectorium.create", "uma.sectorium.adopt", "uma.sectorium.start",
            "uma.sectorium.stop", "uma.sectorium.resume", "uma.sectorium.eject-drive",
            "uma.sectorium.local-sampling-consent"
        ]
        let controls = descendants(of: host).filter { identifiers.contains($0.accessibilityIdentifier()) }
        #expect(controls.count == identifiers.count)
        #expect(controls.allSatisfy { $0.window === window })
        let controlFrames = controls.map { $0.convert($0.bounds, to: host) }
        let controlFramesFitNarrowWidth = controlFrames.allSatisfy { $0.minX >= host.bounds.minX && $0.maxX <= host.bounds.maxX }
        #expect(controlFramesFitNarrowWidth,
                "Workbench controls must remain within the narrow attached content width: \(controlFrames)")

        var traversed = Set<String>()
        for _ in 0..<64 {
            window.selectNextKeyView(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            if let responder = window.firstResponder as? NSView,
               let identifier = accessibilityIdentifier(in: responder), identifiers.contains(identifier) {
                traversed.insert(identifier)
            }
        }
        #expect(traversed.contains("uma.sectorium.refresh"))
        #expect(traversed.contains("uma.sectorium.settings"))
        #expect(traversed.contains("uma.sectorium.create"))
        #expect(traversed.contains("uma.sectorium.adopt"))
        #expect(traversed.contains("uma.sectorium.local-sampling-consent"))
    }

    @Test func sectoriumMutationButtonsRequireVerifiedIdentityAndNoPendingOperation() throws {
        _ = NSApplication.shared
        let scenarios: [(identityVerified: Bool, pending: String?)] = [
            (false, nil),
            (true, "start:interrupted")
        ]
        for scenario in scenarios {
            let fixture = HESectoriumKeyboardFixture(isExternal: false,
                                                      identityVerified: scenario.identityVerified)
            defer { fixture.remove() }
            fixture.store.selectDevice(fixture.device.id)
            fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected,
                                pending: scenario.pending)
            let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            settle(host)
            fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected,
                                pending: scenario.pending)
            let scroll = try #require(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
            let document = try #require(scroll.documentView)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(host)

            let buttons = descendants(of: host).compactMap { $0 as? NSButton }
            let create = try #require(buttons.first { $0.accessibilityIdentifier() == "uma.sectorium.create" })
            let adopt = try #require(buttons.first { $0.accessibilityIdentifier() == "uma.sectorium.adopt" })
            let resume = try #require(buttons.first { $0.accessibilityIdentifier() == "uma.sectorium.resume" })
            #expect(fixture.store.workbench.pendingOperation == scenario.pending)
            #expect(create.isEnabled == (scenario.identityVerified && scenario.pending == nil))
            #expect(adopt.isEnabled == (scenario.identityVerified && scenario.pending == nil))
            #expect(resume.isEnabled == (scenario.pending != nil))
            if scenario.pending != nil {
                #expect(fixture.store.workbench.readiness == .operationInProgress("start:interrupted"))
            } else {
                fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected,
                                    pending: "start:interrupted")
                settle(host)
                #expect(resume.isEnabled, "A newly pending operation must enable the same native Resume control.")
                fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected,
                                    pending: nil)
                settle(host)
                #expect(!resume.isEnabled, "Clearing the pending operation must disable the native Resume control again.")
            }
        }
    }

    @Test func sectoriumEnabledStorageActionsParticipateInAttachedWindowTabTraversal() throws {
        _ = NSApplication.shared
        let scenarios: [(action: String, readiness: SectoriumWorkbenchReadiness, pending: String?)] = [
            ("uma.sectorium.start", .notStarted, nil),
            ("uma.sectorium.stop", .ready, nil),
            ("uma.sectorium.resume", .operationInProgress("start:interrupted"), "start:interrupted"),
            ("uma.sectorium.eject-drive", .notStarted, nil),
            ("uma.sectorium.return-to-development", .operationInProgress("eject:pending"), "eject:pending")
        ]
        for scenario in scenarios {
            let fixture = HESectoriumKeyboardFixture(isExternal: true)
            defer { fixture.remove() }
            let profile = SectoriumDevelopmentProfile(id: UUID().uuidString, name: "Fixture",
                deviceID: fixture.device.id, backingVolumeUUID: UUID(), backingMountPoint: "/private/tmp/HE",
                imagePath: "/private/tmp/HE/Fixture.sparsebundle", devVolumeName: "Fixture",
                devMountPoint: "/Volumes/Fixture-DEV", encrypted: false,
                caseSensitive: false, logicalCapacityBytes: 1024, imageFormat: "UDSB")
            fixture.store.selectDevice(fixture.device.id)
            fixture.store.apply(devices: [fixture.device], profiles: [profile], readiness: scenario.readiness,
                                pending: scenario.pending)
            let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            settle(host)
            fixture.store.deactivateWorkbench()
            fixture.store.apply(devices: [fixture.device], profiles: [profile], readiness: scenario.readiness,
                                pending: scenario.pending)
            settle(host)
            let scroll = try #require(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
            let button = try #require(descendants(of: host).compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == scenario.action },
                "Enabled action missing from window fixture: \(scenario.action), readiness=\(scenario.readiness), pending=\(String(describing: scenario.pending))")
            // This fixture has no validated physical eject topology or durable eject
            // journal. Those actions must stay disabled until their real guards pass.
            let requiresMissingEjectEvidence = scenario.action == "uma.sectorium.eject-drive"
                || scenario.action == "uma.sectorium.return-to-development"
            #expect(button.isEnabled == !requiresMissingEjectEvidence,
                    "\(scenario.action) must reflect the evidence available in this fixture")
            #expect(button.window === window)
            func focusRectInViewport(_ view: NSView) -> NSRect {
                view.convert(view.bounds, to: scroll.contentView).insetBy(dx: -6, dy: -6)
            }
            let startsOutsideViewport = !scroll.contentView.bounds.contains(focusRectInViewport(button))
            let originalResponder = try #require(descendants(of: host).compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "uma.sectorium.refresh" })
            #expect(window.makeFirstResponder(originalResponder))
            if requiresMissingEjectEvidence {
                #expect(!button.canBecomeKeyView)
                var reachedUnsafeAction = false
                for _ in 0..<96 {
                    window.selectNextKeyView(nil)
                    if window.firstResponder === button { reachedUnsafeAction = true; break }
                }
                #expect(!reachedUnsafeAction, "An unavailable eject recovery action must not enter the native Tab route.")
                continue
            }
            var traversed = false
            for _ in 0..<96 {
                window.selectNextKeyView(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                if let responder = window.firstResponder as? NSView,
                   accessibilityIdentifier(in: responder) == scenario.action {
                    traversed = true
                    #expect(scroll.contentView.bounds.contains(focusRectInViewport(button)),
                            "Forward focus must bring enabled \(scenario.action) into the viewport from its initial position.")
                    break
                }
            }
            #expect(traversed, "Forward Tab must reach enabled \(scenario.action) in the real attached NSWindow fixture")
            #expect(startsOutsideViewport, "Bottom storage action should begin outside the top viewport to exercise focus-driven scrolling.")
            var restored = false
            for _ in 0..<96 {
                if window.firstResponder === originalResponder { restored = true; break }
                window.selectPreviousKeyView(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                if let responder = window.firstResponder as? NSView {
                    #expect(scroll.contentView.bounds.contains(focusRectInViewport(responder)),
                            "Every reverse-focused responder must remain visible while traversing from \(scenario.action).")
                } else {
                    Issue.record("Reverse traversal left the attached view responder route before restoring Refresh: \(String(describing: window.firstResponder))")
                }
            }
            #expect(restored,
                    "Reverse traversal must restore the original attached-window responder; current=\(String(describing: window.firstResponder)), original=\(String(describing: originalResponder)), initial=\(String(describing: window.initialFirstResponder)).")
        }
    }

    @Test func sectoriumValidatedEjectAndJournaledReturnParticipateInAttachedWindowTabTraversal() async throws {
        _ = NSApplication.shared
        for mode in [HESectoriumKeyboardEjectMode.ready, .journaledReturn] {
            let fixture = HESectoriumKeyboardFixture(ejectMode: mode)
            defer { fixture.remove() }
            fixture.store.selectDevice(fixture.device.id)
            #expect(fixture.store.workbench.selectedDeviceID == fixture.device.id)
            #expect(mode == .ready ? fixture.service.canPrepareWholeDeviceEjectConfirmation()
                    : fixture.service.canReturnFromWholeDeviceEject(),
                    "The isolated service must accept the observed topology or recoverable journal.")
            let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            let action = mode == .ready ? "uma.sectorium.eject-drive" : "uma.sectorium.return-to-development"
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                settle(host)
                if mode == .ready && fixture.store.canBeginWholeDeviceEject { break }
                if mode == .journaledReturn && fixture.store.canReturnFromWholeDeviceEject { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(mode == .ready ? fixture.store.canBeginWholeDeviceEject : fixture.store.canReturnFromWholeDeviceEject,
                    "The service must establish action availability from the injected topology and durable journal.")
            if mode == .journaledReturn {
                #expect(fixture.store.workbench.pendingOperation?.hasPrefix("eject:") == true)
                #expect(try JSONStateStore(url: fixture.paths.state).load().ejectIntent)
            }
            let scroll = try #require(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
            let button = try #require(descendants(of: host).compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == action })
            let refresh = try #require(descendants(of: host).compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "uma.sectorium.refresh" })
            #expect(button.isEnabled)
            #expect(button.canBecomeKeyView)
            #expect(button.window === window)
            let focusRect = { (view: NSView) in
                view.convert(view.bounds, to: scroll.contentView).insetBy(dx: -6, dy: -6)
            }
            let startsOutsideViewport = !scroll.contentView.bounds.contains(focusRect(button))
            #expect(window.makeFirstResponder(refresh))
            var reached = false
            for _ in 0..<96 {
                window.selectNextKeyView(nil)
                try await Task.sleep(nanoseconds: 5_000_000)
                if window.firstResponder === button {
                    reached = true
                    #expect(scroll.contentView.bounds.contains(focusRect(button)),
                            "Forward focus must scroll the validated \(action) into view.")
                    break
                }
            }
            #expect(reached, "Forward attached-window Tab must reach \(action).")
            #expect(startsOutsideViewport, "The bottom action must begin outside the top viewport.")
            var restored = false
            for _ in 0..<96 {
                if window.firstResponder === refresh { restored = true; break }
                window.selectPreviousKeyView(nil)
                try await Task.sleep(nanoseconds: 5_000_000)
                if let responder = window.firstResponder as? NSView {
                    #expect(scroll.contentView.bounds.contains(focusRect(responder)),
                            "Reverse focus must remain visible after \(action).")
                }
            }
            #expect(restored, "Reverse Tab must restore Refresh after \(action).")
        }
    }

    @Test func sectoriumNativeLocalConsentButtonTracksVerifiedDeviceState() throws {
        _ = NSApplication.shared
        let fixture = HESectoriumKeyboardFixture(isExternal: false)
        defer { fixture.remove() }
        fixture.store.selectDevice(fixture.device.id)
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let unverified = SectoriumPhysicalDevice(id: fixture.device.id, bsdName: fixture.device.bsdName,
            name: fixture.device.name, isExternal: false, identityVerified: false,
            wholeDeviceBytes: fixture.device.wholeDeviceBytes, mountedVolumePaths: [], volumeUUIDs: [],
            readBytes: nil, writtenBytes: nil)
        fixture.store.apply(devices: [unverified], profiles: [], readiness: .unknown("Identity unavailable"), pending: nil)
        settle(host)
        let consent = try #require(descendants(of: host).compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "uma.sectorium.local-sampling-consent" })
        let refresh = try #require(descendants(of: host).compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "uma.sectorium.refresh" })
        #expect(!consent.isEnabled)
        #expect(!consent.canBecomeKeyView)
        click(consent, in: window)
        #expect(!fixture.store.isLocalDeviceSamplingConsented(fixture.device.id))
        #expect(fixture.ioSampler.sampledNames.isEmpty)
        #expect(window.makeFirstResponder(refresh))
        for _ in 0..<96 {
            window.selectNextKeyView(nil)
            #expect(window.firstResponder !== consent, "Disabled consent must be absent from the native key route.")
        }

        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        settle(host)
        #expect(consent.isEnabled, "The same native control must enable after identity verification.")
        #expect(consent.canBecomeKeyView)
        #expect(descendants(of: host).contains { $0 === consent })
        #expect(window.makeFirstResponder(refresh))
        var reached = false
        for _ in 0..<96 {
            window.selectNextKeyView(nil)
            if window.firstResponder === consent { reached = true; break }
        }
        #expect(reached, "Tab must reach the enabled native consent control.")
        click(consent, in: window)
        #expect(fixture.store.isLocalDeviceSamplingConsented(fixture.device.id))
        waitForIOCalls(fixture.ioSampler, count: 1)
        #expect(fixture.ioSampler.sampledNames == [fixture.device.bsdName])
        #expect(fixture.runner.targetedInfoNames == [fixture.device.bsdName])
        fixture.store.setLocalDeviceSamplingConsent(false, for: fixture.device.id)
        fixture.store.apply(devices: [unverified], profiles: [], readiness: .unknown("Identity unavailable"), pending: nil)
        settle(host)
        #expect(!consent.isEnabled)
        #expect(!consent.canBecomeKeyView)
        #expect(descendants(of: host).contains { $0 === consent })
        click(consent, in: window)
        #expect(!fixture.store.isLocalDeviceSamplingConsented(fixture.device.id))
        #expect(fixture.ioSampler.sampledNames == [fixture.device.bsdName])
    }

    @Test func sectoriumSamplingRequiresPageSelectionAndLocalConsent() throws {
        let fixture = HESectoriumKeyboardFixture(isExternal: false)
        defer { fixture.remove() }
        fixture.store.selectDevice(fixture.device.id)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        #expect(fixture.store.workbench.selectedDeviceID == fixture.device.id)
        #expect(fixture.store.workbench.devices.first(where: { $0.id == fixture.device.id })?.identityVerified == true)
        fixture.store.setLocalDeviceSamplingConsent(true, for: fixture.device.id)
        #expect(!fixture.store.isLocalDeviceSamplingConsented(fixture.device.id),
                "Local-disk consent cannot be set while the workbench page is inactive.")
        fixture.store.activateWorkbench()

        fixture.store.sampleSelectedDeviceIO()
        #expect(fixture.ioSampler.sampledNames.isEmpty)
        #expect(!fixture.store.isLocalDeviceSamplingConsented(fixture.device.id))

        fixture.store.setLocalDeviceSamplingConsent(true, for: fixture.device.id)
        #expect(fixture.store.isLocalDeviceSamplingConsented(fixture.device.id))
        waitForIOCalls(fixture.ioSampler, count: 1)
        #expect(fixture.ioSampler.sampledNames == [fixture.device.bsdName])
        #expect(fixture.runner.targetedInfoNames == [fixture.device.bsdName])

        fixture.store.setLocalDeviceSamplingConsent(false, for: fixture.device.id)
        #expect(fixture.store.workbench.io.readBytesPerSecond == nil)
        fixture.store.sampleSelectedDeviceIO()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        #expect(fixture.ioSampler.sampledNames == [fixture.device.bsdName])

        fixture.store.setLocalDeviceSamplingConsent(true, for: fixture.device.id)
        waitForIOCalls(fixture.ioSampler, count: 2)
        fixture.store.pauseSamplingForSleep()
        fixture.store.sampleSelectedDeviceIO()
        #expect(fixture.store.workbench.io.isFresh == false)
        #expect(fixture.ioSampler.sampledNames.count == 2)
        fixture.store.resumeSamplingAfterWake()
        fixture.store.deactivateWorkbench()
        #expect(!fixture.store.isLocalDeviceSamplingConsented(fixture.device.id))
        fixture.store.sampleSelectedDeviceIO()
        #expect(fixture.ioSampler.sampledNames.count == 2)
    }

    @Test func sectoriumIORatesBecomeUnknownAcrossCounterResetOrSamplingGap() {
        let baseline = SectoriumDeviceIOCounters(readBytes: 100, writtenBytes: 200)
        let later = SectoriumDeviceIOCounters(readBytes: 600, writtenBytes: 1_200)
        let valid = HESectoriumStore.rateReading(previous: baseline, current: later, elapsed: 1)
        #expect(valid.isFresh)
        #expect(valid.readBytesPerSecond == 500)
        #expect(valid.writtenBytesPerSecond == 1_000)

        #expect(!HESectoriumStore.rateReading(previous: later, current: baseline, elapsed: 1).isFresh)
        #expect(!HESectoriumStore.rateReading(previous: baseline, current: later, elapsed: 0.2).isFresh)
        #expect(!HESectoriumStore.rateReading(previous: baseline, current: later, elapsed: 4).isFresh)
    }

    @Test func sectoriumIOSampleHistoryRetainsOnlyTheLatestSixtySecondsInMemory() {
        let history = (0..<130).map { index in
            SectoriumIOSampleHistoryEntry(deviceID: "selected", counters: .init(readBytes: UInt64(index), writtenBytes: UInt64(index)),
                                          uptime: TimeInterval(index))
        }
        let retained = HESectoriumStore.prunedIOHistory(history, now: 129)
        #expect(retained.count == 61)
        #expect(retained.first?.uptime == 69)
        #expect(retained.last?.uptime == 129)
        #expect(HESectoriumStore.prunedIOHistory(history + [
            .init(deviceID: "selected", counters: .init(readBytes: 200, writtenBytes: 200), uptime: 130)
        ], now: 129).last?.uptime == 129)
    }

    @Test func sectoriumIOHistoryResetsOnDisconnectAndReconnect() throws {
        let fixture = HESectoriumKeyboardFixture(isExternal: true)
        defer { fixture.remove() }
        fixture.store.selectDevice(fixture.device.id)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        fixture.store.activateWorkbench()
        fixture.store.sampleSelectedDeviceIO()
        waitForIOCalls(fixture.ioSampler, count: 1)

        fixture.store.apply(devices: [], profiles: [], readiness: .ejected, pending: nil)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        fixture.store.sampleSelectedDeviceIO()
        waitForIOCalls(fixture.ioSampler, count: 2)
        #expect(!fixture.store.workbench.io.isFresh,
                "A remounted or reappeared device must establish a new counter baseline after disconnect.")
    }

    @Test func sectoriumExternalSamplingRevalidatesAndSamplesOnlyTheSelectedWholeDisk() {
        let fixture = HESectoriumKeyboardFixture(isExternal: true)
        defer { fixture.remove() }
        fixture.store.selectDevice(fixture.device.id)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        fixture.store.activateWorkbench()
        fixture.store.sampleSelectedDeviceIO()
        waitForIOCalls(fixture.ioSampler, count: 1)

        #expect(fixture.ioSampler.sampledNames == [fixture.device.bsdName])
        #expect(fixture.runner.targetedInfoNames == [fixture.device.bsdName])
        fixture.store.deactivateWorkbench()
        fixture.store.sampleSelectedDeviceIO()
        #expect(fixture.ioSampler.sampledNames == [fixture.device.bsdName])
    }

    @Test func staleSamplingCompletionCannotRestoreReadingOrBecomeTheNextBaseline() {
        let fixture = HESectoriumKeyboardFixture(isExternal: true)
        defer { fixture.remove() }
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        fixture.store.selectDevice(fixture.device.id)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        fixture.ioSampler.holdNextSample()
        fixture.store.activateWorkbench()
        fixture.store.sampleSelectedDeviceIO()
        #expect(fixture.ioSampler.waitForHeldSample(), "The controlled sampler did not reach its suspended return point.")

        fixture.store.selectDevice(nil)
        fixture.ioSampler.releaseHeldSample()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(fixture.store.workbench.io.readBytesPerSecond == nil)
        #expect(!fixture.store.workbench.io.isFresh)

        fixture.store.selectDevice(fixture.device.id)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        fixture.store.sampleSelectedDeviceIO()
        waitForIOCalls(fixture.ioSampler, count: 2)
        #expect(!fixture.store.workbench.io.isFresh,
                "A discarded stale completion must not seed the next selected-device rate baseline.")
    }

    @Test func hesSettingsActionsReceiveVisibleForwardAndReverseWindowFocus() throws {
        _ = NSApplication.shared
        let fixture = HESectoriumKeyboardFixture()
        defer { fixture.remove() }
        let host = NSHostingView(rootView: HESectoriumSettingsView(store: fixture.store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 552),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let expected: Set<String> = [
            "uma.settings.hesectorium.install", "uma.settings.hesectorium.repair",
            "uma.settings.hesectorium.automation", "uma.settings.hesectorium.mount",
            "uma.settings.hesectorium.eject", "uma.settings.hesectorium.refresh"
        ]
        var forward: Set<String> = []
        for _ in 0..<48 {
            window.selectNextKeyView(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            if let view = window.firstResponder as? NSView,
               let identifier = accessibilityIdentifier(in: view), expected.contains(identifier) {
                forward.insert(identifier)
                if let control = view as? NSControl { #expect(control.focusRingType != .none) }
            }
        }
        #expect(forward == expected)

        let refresh = try #require(descendants(of: host).first {
            $0.accessibilityIdentifier() == "uma.settings.hesectorium.refresh"
        })
        #expect(window.makeFirstResponder(refresh))
        var reverse: Set<String> = []
        for _ in 0..<24 {
            window.selectPreviousKeyView(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            if let view = window.firstResponder as? NSView,
               let identifier = accessibilityIdentifier(in: view), expected.contains(identifier) {
                reverse.insert(identifier)
            }
        }
        #expect(reverse == expected)
    }

    private func waitForIOCalls(_ sampler: HESectoriumKeyboardIOSampler, count: Int) {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && sampler.sampledNames.count < count {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
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

    private func waitForRetryToStop(_ retry: ThreadOSPromptKeyViewRouteRetryController) {
        let deadline = Date().addingTimeInterval(1)
        while retry.isActive && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
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

    @Test func rawPreviewMatchesCopyUpdatesFromNativeMenusAndExitsByTab() throws {
        _ = NSApplication.shared
        let clipboard = WorkbenchClipboardSpy()
        let host = NSHostingView(rootView: ThreadOSPromptComposerView(
            language: .simplifiedChinese, preferences: .inMemory(), clipboard: clipboard
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 552),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let views = descendants(of: host)
        let preview = try #require(views.first { $0.accessibilityIdentifier() == "uma.threados.prompt.preview.text" } as? NSTextView)
        let previewScroll = try #require(preview.enclosingScrollView)
        let copy = try #require(views.first { $0.accessibilityIdentifier() == "uma.threados.prompt.generate-copy" } as? NSButton)
        let qa = try #require(views.first { $0.accessibilityIdentifier() == "uma.threados.prompt.role.qa.effort" })
        #expect(!preview.isEditable && preview.isSelectable && !preview.canBecomeKeyView)
        #expect(!previewScroll.hasHorizontalScroller)
        #expect(preview.textContainer?.widthTracksTextView == true)
        #expect((preview.textContainer?.containerSize.width ?? 0) > 0)
        #expect(abs(copy.convert(copy.bounds, to: host).midY - qa.convert(qa.bounds, to: host).midY) <= 2)
        for role in ThreadOSPromptRole.allCases {
            for kind in ["model", "effort"] {
                let popup = try #require(views.first { $0.accessibilityIdentifier() == "uma.threados.prompt.role.\(role.rawValue).\(kind)" } as? NSPopUpButton)
                let desired = kind == "model" ? "gpt-5.6-terra" : "xhigh"
                let index = try #require(popup.itemArray.firstIndex { $0.representedObject as? String == desired })
                popup.selectItem(at: index)
                #expect(popup.sendAction(try #require(popup.action), to: popup.target))
                settle(host)
                let command = try #require(JSONSerialization.jsonObject(with: Data(preview.string.utf8)) as? [String: Any])
                let roles = try #require(command["roles"] as? [String: [String: String]])
                #expect(roles[role.rawValue]?[kind == "model" ? "model" : "thinking"] == desired)
                copy.performClick(nil)
                settle(host)
                #expect(clipboard.writes.last?.utf8.elementsEqual(preview.string.utf8) == true)
            }
        }
        for reverse in [false, true] {
            #expect(window.makeFirstResponder(preview))
            let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: reverse ? [.shift] : [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "\t",
                charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
            preview.keyDown(with: tab)
            #expect(window.firstResponder === (reverse ? qa : copy))
        }
    }

    private final class WorkbenchClipboardSpy: ThreadOSSettingsClipboard {
        var writes: [String] = []
        func write(_ text: String) -> Bool { writes.append(text); return true }
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


@MainActor private func sendTab(to window: NSWindow, reverse: Bool = false) {
    guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: reverse ? [.shift] : [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: "\t",
        charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48) else { return }
    window.sendEvent(event)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

@MainActor private func click(_ view: NSView, in window: NSWindow) {
    let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
        window.sendEvent(event)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

@MainActor private final class HESectoriumKeyboardClipboard: ThreadOSSettingsClipboard {
    private(set) var writes: [String] = []
    func write(_ string: String) -> Bool { writes.append(string); return true }
}

private enum HESectoriumKeyboardEjectMode { case none, ready, journaledReturn }

@MainActor private struct HESectoriumKeyboardFixture {
    let root: URL
    let paths: HESectoriumPaths
    let service: HESectoriumService
    let store: HESectoriumStore
    let device: SectoriumPhysicalDevice
    let runner: HESectoriumKeyboardRunner
    let ioSampler: HESectoriumKeyboardIOSampler
    init(isExternal: Bool = true, identityVerified: Bool = true,
         ejectMode: HESectoriumKeyboardEjectMode = .none) {
        root = URL(fileURLWithPath: "/private/tmp/hesectorium-keyboard-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = HESectoriumPaths(root: root.appendingPathComponent("support", isDirectory: true))
        let mediaUUID = UUID()
        device = SectoriumPhysicalDevice(id: identityVerified ? mediaUUID.uuidString : "unverified-disk81",
            bsdName: "disk81", name: "Fixture drive",
            isExternal: isExternal, identityVerified: identityVerified, wholeDeviceBytes: 1024 * 1024 * 1024,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil)
        runner = HESectoriumKeyboardRunner(device: device)
        ioSampler = HESectoriumKeyboardIOSampler()
        let stateStore: DurableStateStore
        let ejectDriver: WholeDeviceEjectDriving?
        if ejectMode == .none {
            stateStore = HESectoriumKeyboardStateStore()
            ejectDriver = nil
        } else {
            let physicalVolume = "\(UUID().uuidString.lowercased())|disk81s1"
            let imageVolume = "\(UUID().uuidString.lowercased())|disk31s1"
            let topology = WholeDeviceTopology(physicalIdentity: device.id, bsdName: device.bsdName,
                isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
                volumes: [.init(identity: physicalVolume, mounted: true)],
                images: [.init(identity: "image:disk30", attached: true,
                    volumeIdentities: [imageVolume], mountedVolumeIdentities: [imageVolume])])
            let durableStore = JSONStateStore(url: paths.state)
            if ejectMode == .journaledReturn {
                let journal = WholeDeviceEjectJournalRecord(operationID: UUID().uuidString,
                    target: topology, phase: .interrupted,
                    completedSteps: ["unmountImageVolumes:image:disk30"],
                    lastReceipt: .busy("fixture busy before detach"), lastIssuedAction: .imageVolumesUnmount)
                let initial = try! durableStore.load()
                let encoded = try! JSONEncoder().encode(journal).base64EncodedString()
                let persisted = try! durableStore.compareAndSwap(expectedRevision: initial.revision,
                    newState: StoragePersistentState(revision: initial.revision + 1, ejectIntent: true,
                        operationID: journal.operationID, workbenchOperation: "eject:\(journal.operationID)",
                        workbenchPhase: "eject:interrupted", workbenchTarget: encoded,
                        workbenchCompletedStep: journal.completedSteps.last))
                precondition(persisted, "The return fixture requires a durable journal")
            }
            stateStore = durableStore
            ejectDriver = HESectoriumKeyboardEjectDriver(topology: topology)
        }
        service = HESectoriumService(paths: paths, backend: HESectoriumKeyboardBackend(),
            store: stateStore, operationLock: HESectoriumKeyboardLock(),
            installer: HESectoriumInstaller(paths: paths, home: root), runner: runner,
            identityPolicy: .expected, agentStatusProvider: UnknownAgentStatusProvider(),
            sectoriumDeviceObserver: HESectoriumKeyboardDeviceObserver(device: device),
            sectoriumDeviceIOSampler: ioSampler, wholeDeviceEjectDriverOverride: ejectDriver)
        store = HESectoriumStore(service: service, sampleIntervalNanoseconds: 60_000_000_000)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class HESectoriumKeyboardEjectDriver: WholeDeviceEjectDriving {
    let topology: WholeDeviceTopology
    init(topology: WholeDeviceTopology) { self.topology = topology }
    func observe(physicalIdentity: String) -> WholeDeviceTopology? {
        physicalIdentity == topology.physicalIdentity ? topology : nil
    }
    func unmountImageVolumesNonForce(_ imageIdentity: String, volumeIdentities: [String],
                                     from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .busy("fixture forbids mutation") }
    func detachImageNonForce(_ imageIdentity: String, from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .busy("fixture forbids mutation") }
    func unmountAllPhysicalVolumesNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .busy("fixture forbids mutation") }
    func ejectWholeDeviceNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt { .busy("fixture forbids mutation") }
    func presence(physicalIdentity: String) -> WholeDevicePresence { .present }
    func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool {
        guard journal.target.matchesPhysicalIdentityAndVolumes(topology),
              topology.volumes.allSatisfy(\.mounted),
              topology.images.count == journal.target.images.count else { return false }
        let expected = Dictionary(uniqueKeysWithValues: journal.target.images.map { ($0.identity, Set($0.volumeIdentities)) })
        return topology.images.allSatisfy { image in
            image.attached && image.mountedVolumeIdentities.map(Set.init) == expected[image.identity]
                && Set(image.volumeIdentities) == expected[image.identity]
        }
    }
}

private final class HESectoriumKeyboardDeviceObserver: SectoriumDeviceObserving {
    let device: SectoriumPhysicalDevice
    init(device: SectoriumPhysicalDevice) { self.device = device }
    func observeDevices() throws -> [SectoriumPhysicalDevice] { [device] }
}

private final class HESectoriumKeyboardStateStore: DurableStateStore {
    private var state = StoragePersistentState(ejectIntent: false)
    func load() throws -> StoragePersistentState { state }
    func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
        guard state.revision == expectedRevision else { return false }
        state = newState
        return true
    }
}

private final class HESectoriumKeyboardLock: OperationLock {
    func acquire() -> Bool { true }
    func release() {}
}

private final class HESectoriumKeyboardBackend: StorageBackend {
    func observeOuter() -> VolumeIdentity? { nil }
    func observe() -> StorageObservation? { nil }
    func attachImage() -> CommandOutcome { .init(exitCode: 97, detail: "fixture forbids storage commands") }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { .incomplete(reason: "fixture has no live occupancy") }
    func perform(_ step: EjectStep) -> CommandOutcome { .init(exitCode: 97, detail: "fixture forbids storage commands") }
    func finalOuterState() -> FinalOuterState { .unknown("fixture forbids storage commands") }
}

private final class HESectoriumKeyboardRunner: HESectoriumCommandRunning {
    let device: SectoriumPhysicalDevice?
    private(set) var targetedInfoNames: [String] = []
    init(device: SectoriumPhysicalDevice? = nil) { self.device = device }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        if executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", "/dev/\(device?.bsdName ?? "")"],
           let device,
           let data = try? PropertyListSerialization.data(fromPropertyList: [
               "DeviceIdentifier": device.bsdName, "MediaUUID": device.id
           ], format: .xml, options: 0) {
            targetedInfoNames.append(device.bsdName)
            return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
        }
        return .init(exitCode: 97, detail: "fixture forbids command execution")
    }
}

private final class HESectoriumKeyboardIOSampler: SectoriumDeviceIOCounterSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    private var holdNext = false
    private let heldSample = DispatchSemaphore(value: 0)
    private let releaseSample = DispatchSemaphore(value: 0)
    var sampledNames: [String] { lock.lock(); defer { lock.unlock() }; return names }
    func holdNextSample() { lock.lock(); holdNext = true; lock.unlock() }
    func waitForHeldSample() -> Bool { heldSample.wait(timeout: .now() + 5) == .success }
    func releaseHeldSample() { releaseSample.signal() }
    func counters(forWholeBSDName bsdName: String, expectedMediaID: UUID) -> SectoriumDeviceIOCounters? {
        lock.lock()
        names.append(bsdName)
        let index = names.count
        let shouldHold = holdNext
        holdNext = false
        lock.unlock()
        if shouldHold { heldSample.signal(); releaseSample.wait() }
        return .init(readBytes: UInt64(index * 1_000), writtenBytes: UInt64(index * 2_000))
    }
}
