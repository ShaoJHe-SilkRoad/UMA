import AppKit
import SwiftUI
import Testing
import Vision
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

    @Test func sectoriumReadyExternalPrioritizesSafeEjectAndKeepsStopSecondary() {
        func plan(external: Bool, readiness: SectoriumWorkbenchReadiness = .ready,
                  identityVerified: Bool = true, pending: String? = nil,
                  canEject: Bool = true) -> SectoriumWorkbenchActionPlan {
            .make(.init(hasDrive: true, identityVerified: identityVerified, external: external,
                stale: false, inventoryAvailable: true, busy: false, readiness: readiness,
                hasProfile: true, profileFormatVerified: true, legacyState: .none,
                pendingOperation: pending, canBeginEject: canEject,
                canContinueEject: false, canReturnFromEject: false))
        }
        let external = plan(external: true)
        #expect(external.primary == .eject)
        #expect(external.secondary.contains(.stop))
        #expect(!external.secondary.contains(.eject))

        let internalDrive = plan(external: false)
        #expect(internalDrive.primary == .recheck)
        #expect(internalDrive.secondary.contains(.stop))
        #expect(!internalDrive.secondary.contains(.eject))

        #expect(plan(external: true, identityVerified: false).primary == .recheck)
        #expect(plan(external: true, readiness: .partialFailure("fixture" )).primary == .recheck)
        #expect(plan(external: true, pending: "start:interrupted").primary == .resume)
        #expect(plan(external: true, canEject: false).primary == .recheck)
    }

    @Test func sectoriumOrderingPrefersExternalThenStableNames() {
        let externalZ = SectoriumPhysicalDevice(id: "z", bsdName: "disk8", name: "Zeta",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [], readBytes: nil, writtenBytes: nil, isVirtual: false)
        let externalA = SectoriumPhysicalDevice(id: "a", bsdName: "disk7", name: "Alpha",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [], readBytes: nil, writtenBytes: nil, isVirtual: false)
        let internalDrive = SectoriumPhysicalDevice(id: "i", bsdName: "disk0", name: "System",
            isExternal: false, identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
            volumeUUIDs: [], readBytes: nil, writtenBytes: nil, isVirtual: false)
        #expect(SectoriumWorkbenchDeviceOrdering.externalFirst([internalDrive, externalZ, externalA]).map(\.id) == ["a", "z", "i"])
    }

    @Test func sectoriumUnsetSelectionPrefersVerifiedExternalAndKeepsDeliberateChoice() {
        let fixture = HESectoriumKeyboardFixture(isExternal: true)
        defer { fixture.remove() }
        let internalDrive = SectoriumPhysicalDevice(id: "internal-fixture", bsdName: "disk0",
            name: "System", isExternal: false, identityVerified: true, wholeDeviceBytes: nil,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil, isVirtual: false)
        fixture.store.apply(devices: [internalDrive, fixture.device], profiles: [], readiness: .connected, pending: nil)
        #expect(fixture.store.workbench.selectedDeviceID == fixture.device.id)
        fixture.store.selectDevice(internalDrive.id)
        fixture.store.deactivateWorkbench()
        fixture.store.apply(devices: [fixture.device, internalDrive], profiles: [], readiness: .connected, pending: nil)
        #expect(fixture.store.workbench.selectedDeviceID == internalDrive.id)
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

    @Test func promptComposerRebuildsKeyViewLoopAfterSameWindowControlReplacement() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 552),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        let firstHost = NSHostingView(rootView: ThreadOSPromptComposerView(
            language: .english, preferences: .inMemory()
        ))
        window.contentView = firstHost
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(firstHost)

        let copyIdentifier = "uma.threados.prompt.generate-copy"
        let oldCopy = try #require(descendants(of: firstHost).first {
            $0.accessibilityIdentifier() == copyIdentifier
        })
        let replacementHost = NSHostingView(rootView: ThreadOSPromptComposerView(
            language: .english, preferences: .inMemory()
        ))
        window.contentView = replacementHost
        settle(replacementHost)

        let identifiers = ThreadOSPromptRole.allCases.flatMap { role in
            ["uma.threados.prompt.role.\(role.rawValue).model", "uma.threados.prompt.role.\(role.rawValue).effort"]
        } + [copyIdentifier]
        let replacementViews = descendants(of: replacementHost)
        let controls = try identifiers.map { identifier in
            try #require(replacementViews.first { $0.accessibilityIdentifier() == identifier })
        }
        #expect(controls.count == 9)
        #expect(controls.last !== oldCopy)
        #expect(oldCopy.window == nil)
        #expect(window.contentView === replacementHost)
        #expect(window.initialFirstResponder === replacementHost)
        #expect(replacementHost.nextKeyView === controls[0])
        #expect(controls.allSatisfy { $0.window === window && $0.canBecomeKeyView })
        for (current, next) in zip(controls, controls.dropFirst()) {
            #expect(current.nextKeyView === next)
        }
        #expect(window.makeFirstResponder(window))
        for control in controls {
            window.selectNextKeyView(nil)
            #expect((window.firstResponder as? NSView) === control)
        }
        #expect(window.makeFirstResponder(controls[controls.count - 1]))
        for control in controls.reversed().dropFirst() {
            window.selectPreviousKeyView(nil)
            #expect((window.firstResponder as? NSView) === control)
        }
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
        #expect(threadOSRoute.contains { accessibilityLabel(in: $0) == "AUV navigation" })

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
        #expect(agentsRoute.contains { accessibilityLabel(in: $0) == "AUV navigation" })
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

    @Test func sectoriumWorkbenchControlsAttachToRealWindowAndFitNarrowContent() async throws {
        _ = NSApplication.shared
        // Since 0.17.2 the workbench's keyboard actions are its native buttons:
        // Refresh and Settings in the header, then each volume's primary action
        // and, for a loaded external volume, Disconnect. Create, the drive menus
        // and Drive details are SwiftUI controls or folded detail, outside the
        // Tab route by design, so they are no longer held to it here. The
        // render-only fixture has a volume in each state and runs no host action.
        let store = HESectoriumStore.isolatedPreviewFixture()
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)

        let rows = store.volumeRows
        let loaded = try #require(rows.first { $0.verifiedLoaded == true && $0.isExternal })
        var identifiers: Set<String> = ["uma.sectorium.refresh", "uma.sectorium.settings",
                                        "uma.sectorium.volume-disconnect.\(loaded.id)"]
        rows.forEach { identifiers.insert("uma.sectorium.volume-primary.\($0.id)") }
        let controls = descendants(of: host).compactMap { $0 as? NSButton }
            .filter { identifiers.contains($0.accessibilityIdentifier()) }
        #expect(Set(controls.map { $0.accessibilityIdentifier() }) == identifiers)
        #expect(controls.allSatisfy { $0.window === window })
        let controlFrames = controls.map { $0.convert($0.bounds, to: host) }
        let controlFramesFitNarrowWidth = controlFrames.allSatisfy { $0.minX >= host.bounds.minX && $0.maxX <= host.bounds.maxX }
        #expect(controlFramesFitNarrowWidth,
                "Workbench controls must remain within the narrow attached content width: \(controlFrames)")
        let refresh = try #require(nativeButton("uma.sectorium.refresh", in: host))
        let firstPrimary = try #require(nativeButton("uma.sectorium.volume-primary.\(rows[0].id)", in: host))
        #expect(refresh.convert(refresh.bounds, to: host).midY < firstPrimary.convert(firstPrimary.bounds, to: host).midY,
                "The header actions must come before the first volume's actions.")

        #expect(window.makeFirstResponder(refresh))
        var traversed = Set<String>()
        for _ in 0..<64 {
            window.selectNextKeyView(nil)
            try await Task.sleep(for: .milliseconds(10))
            if let responder = window.firstResponder as? NSView,
               let identifier = accessibilityIdentifier(in: responder), identifiers.contains(identifier) {
                traversed.insert(identifier)
            }
        }
        #expect(traversed == identifiers,
                "Tab must reach every native workbench action; missing \(identifiers.subtracting(traversed))")
    }

    @Test func sectoriumMutationButtonsRequireVerifiedIdentityAndNoPendingOperation() async throws {
        _ = NSApplication.shared
        // A drive whose identity is unverified is listed, but nothing that would
        // write to it is offered: no inline Create or Register. Those are SwiftUI
        // buttons, so what is checked is what renders; the verified drive is the
        // control case that proves the check can see them at all.
        var registerRendered: [Bool: Bool] = [:]
        for identityVerified in [true, false] {
            let fixture = HESectoriumKeyboardFixture(isExternal: false, identityVerified: identityVerified)
            defer { fixture.remove() }
            let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            try await waitForAvailableInventory(fixture.store)
            settle(host)
            #expect(fixture.store.workbench.devices.contains {
                $0.id == fixture.device.id && $0.identityVerified == identityVerified
            })
            registerRendered[identityVerified] = try recognizedText(in: host)
                .contains { $0.text.localizedCaseInsensitiveContains("Register existing") }
        }
        #expect(registerRendered[true] == true,
                "The verified control case must render the Register route, or the unverified check proves nothing.")
        #expect(registerRendered[false] == false, "An unverified drive must not be offered volume creation or registration.")

        // A pending operation exposes its recovery control, native so that Tab
        // reaches it, and clearing the operation removes it again.
        let observer = HESectoriumHeldDeviceObserver()
        let fixture = HESectoriumKeyboardFixture(observerOverride: observer)
        observer.device = fixture.device
        defer { observer.release(); fixture.remove() }
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await waitForAvailableInventory(fixture.store)
        fixture.store.deactivateWorkbench()
        // Hold later observations and let any already on their way land, so
        // none replaces the injected pending operation with the service's.
        observer.hold()
        settle(host)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: "start:interrupted")
        settle(host)
        let resume = try #require(nativeButton("uma.sectorium.resume", in: host),
                                  "A pending operation must expose its recovery control.")
        #expect(resume.isEnabled && resume.canBecomeKeyView && resume.window === window)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        settle(host)
        #expect(nativeButton("uma.sectorium.resume", in: host) == nil,
                "Clearing the pending operation must remove its recovery control.")
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: "start:interrupted")
        settle(host)
        #expect(nativeButton("uma.sectorium.resume", in: host) != nil,
                "A newly pending operation must expose its recovery control again.")
    }

    @Test func sectoriumMultipleImagesAndStaleSelectionStayBoundToOnePhysicalRoot() async throws {
        _ = NSApplication.shared
        let observer = HESectoriumMultiDeviceObserver(devices: [])
        let fixture = HESectoriumKeyboardFixture(isExternal: true, observerOverride: observer)
        defer { fixture.remove() }
        // A second physical drive with the same display name, so nothing but
        // its identity keeps its volume apart from the first drive's two.
        let sibling = SectoriumPhysicalDevice(id: UUID().uuidString, bsdName: "disk82",
            name: fixture.device.name, isExternal: true, identityVerified: true,
            wholeDeviceBytes: fixture.device.wholeDeviceBytes, mountedVolumePaths: [], volumeUUIDs: [],
            readBytes: nil, writtenBytes: nil, isVirtual: false,
            identityBasis: .uniqueBackingVolumeUUID)
        observer.devices = [fixture.device, sibling]
        func profile(_ name: String, on device: SectoriumPhysicalDevice) -> SectoriumDevelopmentProfile {
            SectoriumDevelopmentProfile(id: UUID().uuidString, name: name, deviceID: device.id,
                backingVolumeUUID: UUID(), backingMountPoint: "/private/tmp/\(device.bsdName)",
                imagePath: "/private/tmp/\(device.bsdName)/\(name).sparsebundle", devVolumeName: name,
                devMountPoint: "/Volumes/\(name)", encrypted: false, caseSensitive: false,
                logicalCapacityBytes: 1024, imageFormat: "UDSB")
        }
        let profiles = [profile("Atlas", on: fixture.device), profile("Borealis", on: fixture.device),
                        profile("Cascade", on: sibling)]
        try FileManager.default.createDirectory(at: fixture.paths.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(profiles).write(to: fixture.paths.sectoriumProfiles, options: .atomic)
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 1100),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await waitForAvailableInventory(fixture.store)
        settle(host)
        #expect(fixture.store.volumeRows.filter { $0.parentDeviceID == fixture.device.id }.count == 2)
        #expect(fixture.store.volumeRows.filter { $0.parentDeviceID == sibling.id }.count == 1)

        // Read top to bottom: each drive's header, then only its own volumes.
        let lines = try recognizedText(in: host).sorted { $0.frame.midY > $1.frame.midY }
        let headers = lines.indices.filter { lines[$0].text.localizedCaseInsensitiveContains(fixture.device.name) }
        #expect(headers.count == 2, "Both same-named drives must render as separate sections: \(lines.map(\.text))")
        let atlas = try #require(lines.firstIndex { $0.text.contains("Atlas") }, "\(lines.map(\.text))")
        let borealis = try #require(lines.firstIndex { $0.text.contains("Borealis") }, "\(lines.map(\.text))")
        let cascade = try #require(lines.firstIndex { $0.text.contains("Cascade") }, "\(lines.map(\.text))")
        func sectionBreaks(between first: Int, and second: Int) -> Int {
            headers.filter { $0 > min(first, second) && $0 < max(first, second) }.count
        }
        #expect(sectionBreaks(between: atlas, and: borealis) == 0,
                "Two images on one drive must render in that drive's section: \(lines.map(\.text))")
        #expect(sectionBreaks(between: atlas, and: cascade) == 1 && sectionBreaks(between: borealis, and: cascade) == 1,
                "The same-named drive's volume must render in its own section: \(lines.map(\.text))")

        // The old test's stale half, no storage action while the topology is
        // being re-checked, needs volumes the service has qualified, and this
        // fixture qualifies none: every action here already reads Recheck. It
        // is covered with real qualification by SectoriumVisibleStateTests
        // ("Selecting another drive rejects an older refresh and waits for its
        // own qualifications", "Uncorrelated native changes and hidden sleep
        // invalidate without losing registrations"), and an unverified row's
        // Recheck by HESectoriumUIContractTests.perVolumePrimaryActionPolicy.
    }

    @Test func sectoriumTwoHardwareOverviewRendersChildCapacityAndSelection() async throws {
        _ = NSApplication.shared
        let observer = HESectoriumMultiDeviceObserver(devices: [])
        let fixture = HESectoriumKeyboardFixture(isExternal: true, observerOverride: observer)
        defer { fixture.remove() }
        let internalDrive = SectoriumPhysicalDevice(id: UUID().uuidString, bsdName: "disk0",
            name: "Internal system drive", isExternal: false, identityVerified: true,
            wholeDeviceBytes: 251_000_193_024, mountedVolumePaths: [], volumeUUIDs: [],
            readBytes: nil, writtenBytes: nil, isVirtual: false)
        observer.devices = [internalDrive, fixture.device]
        let store = fixture.store
        // Saved paths must equal their own standardized form, and Foundation
        // standardizes an existing /private/tmp path to /tmp; this fixture's
        // real temporary root would therefore fail the whole registry closed.
        // A drive's mount point is never under /private, so a /Volumes-style
        // path that does not exist is what a saved registration looks like.
        let profile = SectoriumDevelopmentProfile(id: UUID().uuidString, name: "DEV_APFS",
            deviceID: fixture.device.id, backingVolumeUUID: UUID(), backingMountPoint: "/Volumes/HE-fixture",
            imagePath: "/Volumes/HE-fixture/.DEV_APFS.sparsebundle",
            devVolumeName: "DEV_APFS", devMountPoint: "/Volumes/DEV_APFS", encrypted: false,
            caseSensitive: false, logicalCapacityBytes: 321_912_791_040, imageFormat: "UDSB")
        try FileManager.default.createDirectory(at: fixture.paths.root, withIntermediateDirectories: true)
        try JSONEncoder().encode([profile]).write(to: fixture.paths.sectoriumProfiles, options: .atomic)
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await waitForAvailableInventory(store)
        settle(host)
        #expect(store.workbench.devices.filter { $0.isVirtual == false }.count == 2,
                "The isolated observer must feed both physical roots to the workbench.")
        #expect(store.volumeRows.contains { $0.id == profile.id && $0.parentDeviceID == fixture.device.id })

        // 0.17.2 dropped the "Selected" marker and the per-drive select buttons;
        // a drive is now chosen for activity inside its folded Drive details.
        // The overview itself still has to hold: the external drive first, its
        // volume's name and capacity inside its section, then the internal one.
        func expectOverview(_ when: String) throws {
            let lines = try recognizedText(in: host).sorted { $0.frame.midY > $1.frame.midY }
            let texts = lines.map(\.text)
            let external = try #require(lines.firstIndex { $0.text.localizedCaseInsensitiveContains(fixture.device.name) }, "\(when): \(texts)")
            let child = try #require(lines.firstIndex { $0.text.contains("DEV_APFS") }, "\(when): \(texts)")
            let capacity = try #require(lines.firstIndex { $0.text.contains("299.8 GiB") }, "\(when): \(texts)")
            let internalLine = try #require(lines.firstIndex { $0.text.localizedCaseInsensitiveContains("Internal system drive") }, "\(when): \(texts)")
            #expect(lines[internalLine].text.localizedCaseInsensitiveContains("disk0")
                    || lines[internalLine].text.localizedCaseInsensitiveContains("disko"),
                    "\(when): the internal title must display its disk identity; OCR can confuse zero with O.")
            #expect(external < child && child < capacity && capacity < internalLine,
                    "\(when): the external drive comes first, with its volume's name and capacity in its own section: \(texts)")
        }
        try expectOverview("Initially")
        // Choosing which drive's activity to show must not move a volume out of
        // its parent's section. The UI route sits inside the folded Drive
        // details, so the selection goes through the store call it makes.
        store.selectDevice(internalDrive.id)
        settle(host)
        #expect(store.workbench.selectedDeviceID == internalDrive.id)
        try expectOverview("After selecting the internal drive")
    }

    @Test func sectoriumExistingImagePickerUsesObservedMountShowsHiddenItemsAndCancelsSafely() throws {
        let fixture = HESectoriumKeyboardFixture()
        defer { fixture.remove() }
        let hiddenImage = fixture.root.appendingPathComponent(".DEV_APFS.sparsebundle", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenImage, withIntermediateDirectories: true)
        let panel = SectoriumExistingImagePicker.makePanel(
            mountedVolumePaths: [fixture.root.path], prompt: "Adopt")
        #expect(panel.canChooseDirectories && panel.canChooseFiles)
        #expect(!panel.treatsFilePackagesAsDirectories)
        #expect(!panel.allowsMultipleSelection)
        #expect(panel.showsHiddenFiles)
        #expect(panel.directoryURL?.standardizedFileURL.path == fixture.root.standardizedFileURL.path)
        #expect(FileManager.default.fileExists(atPath: hiddenImage.path))
        #expect(SectoriumExistingImagePicker.selectedURL(from: panel, response: .cancel) == nil)

        let noObservedMount = SectoriumExistingImagePicker.makePanel(mountedVolumePaths: [], prompt: "Adopt")
        #expect(SectoriumExistingImagePicker.suggestedDirectoryURL(mountedVolumePaths: []) == nil,
                "Without a current mount observation UMA must not set a chooser location; AppKit may supply its own default.")
        #expect(SectoriumExistingImagePicker.selectedURL(from: noObservedMount, response: .cancel) == nil)
    }

    @Test func sectoriumCachedLegacyVolumeYieldsToCurrentUnverifiedState() async throws {
        _ = NSApplication.shared
        // Rewritten for 0.17.2, which stopped rendering a workbench readiness
        // headline; the old title and summary checks went with it. A cached
        // legacy volume is now a row of its own, and the old test's point still
        // has to hold there: a cached name must not stand in for a current
        // state that could not be verified.
        let observer = HESectoriumHeldDeviceObserver()
        let fixture = HESectoriumKeyboardFixture(observerOverride: observer)
        observer.device = fixture.device
        defer { observer.release(); fixture.remove() }
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await waitForAvailableInventory(fixture.store)
        fixture.store.deactivateWorkbench()
        // Hold every later observation, and let any result already on its way
        // land first, so nothing replaces the injected legacy state with the
        // fixture service's empty one.
        observer.hold()
        settle(host)
        let legacy = HESectoriumService.LegacyDevelopmentDisplay(name: "DEV_NEBULA",
            mountPoint: "/Volumes/Nebula", logicalCapacityBytes: 321_912_791_040, state: .mounted)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected,
                            pending: nil, discoveredLegacy: true, legacyByDevice: [fixture.device.id: legacy])
        settle(host)
        let verified = try recognizedText(in: host).map(\.text)
        #expect(verified.contains { $0.contains("DEV_NEBULA") }, "\(verified)")
        #expect(verified.contains { $0.localizedCaseInsensitiveContains("Register existing volume") },
                "A verified, mounted legacy volume is offered for registration: \(verified)")

        // The refresh voids every cached legacy state before it observes
        // anything, and the held observer keeps it from landing.
        fixture.store.refresh()
        settle(host)
        #expect(fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.state == .unknown)
        let rechecking = try recognizedText(in: host).map(\.text)
        #expect(rechecking.contains { $0.contains("DEV_NEBULA") }, "The volume stays known while it is re-checked: \(rechecking)")
        #expect(!rechecking.contains { $0.localizedCaseInsensitiveContains("Register existing volume") },
                "An unverified legacy volume must not be offered for registration on its cached state: \(rechecking)")
        #expect(rechecking.contains { $0.localizedCaseInsensitiveContains("Recheck") }, "\(rechecking)")
        observer.release()
    }

    @Test func sectoriumEnabledStorageActionsParticipateInAttachedWindowTabTraversal() async throws {
        _ = NSApplication.shared
        // Rewritten for the 0.17.2 per-volume workbench: Start and Stop became a
        // volume's Load and Unload, Disconnect joined them for a loaded external
        // volume, and Resume became Continue operation.
        let store = HESectoriumStore.isolatedPreviewFixture()
        store.apply(devices: store.workbench.devices, profiles: store.workbench.profiles,
                    readiness: .ready, pending: "start:interrupted")
        let loaded = try #require(store.volumeRows.first { $0.verifiedLoaded == true && $0.isExternal })
        let unloaded = try #require(store.volumeRows.first { $0.verifiedLoaded == false && $0.isExternal })
        let actions = [
            ("Load", "uma.sectorium.volume-primary.\(unloaded.id)"),
            ("Unload", "uma.sectorium.volume-primary.\(loaded.id)"),
            ("Disconnect", "uma.sectorium.volume-disconnect.\(loaded.id)"),
            ("Continue operation", "uma.sectorium.resume"),
        ]
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let scroll = try #require(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
        let refresh = try #require(nativeButton("uma.sectorium.refresh", in: host))
        func focusRectInViewport(_ view: NSView) -> NSRect {
            view.convert(view.bounds, to: scroll.contentView).insetBy(dx: -6, dy: -6)
        }
        for (title, action) in actions {
            let button = try #require(nativeButton(action, in: host), "Enabled \(title) missing from the window fixture")
            #expect(button.title == title)
            #expect(button.isEnabled)
            #expect(button.window === window)
            #expect(window.makeFirstResponder(refresh))
            var traversed = false
            for _ in 0..<96 {
                window.selectNextKeyView(nil)
                try await Task.sleep(for: .milliseconds(5))
                if window.firstResponder === button {
                    traversed = true
                    #expect(scroll.contentView.bounds.contains(focusRectInViewport(button)),
                            "Forward focus must bring enabled \(title) into the viewport.")
                    break
                }
            }
            #expect(traversed, "Forward Tab must reach enabled \(title) in the real attached NSWindow fixture")
            var restored = false
            for _ in 0..<96 {
                if window.firstResponder === refresh { restored = true; break }
                window.selectPreviousKeyView(nil)
                try await Task.sleep(for: .milliseconds(5))
                if let responder = window.firstResponder as? NSView {
                    #expect(scroll.contentView.bounds.contains(focusRectInViewport(responder)),
                            "Every reverse-focused responder must remain visible while traversing from \(title).")
                } else {
                    Issue.record("Reverse traversal left the attached view responder route before restoring Refresh: \(String(describing: window.firstResponder))")
                }
            }
            #expect(restored, "Reverse traversal must restore Refresh after \(title).")
        }
    }

    @Test func sectoriumJournaledReturnParticipatesInAttachedWindowTabTraversal() async throws {
        _ = NSApplication.shared
        // Rewritten for 0.17.2. Its ready-mode half, a whole-drive eject offered
        // with no volume loaded, went with the redesign: the workbench now
        // disconnects a drive through a loaded volume's Disconnect, held to the
        // Tab route by the storage-actions test. The journaled return is the
        // only way back from an interrupted disconnect, and still has to be
        // reachable from the keyboard.
        let fixture = HESectoriumKeyboardFixture(ejectMode: .journaledReturn)
        defer { fixture.remove() }
        fixture.store.selectDevice(fixture.device.id)
        #expect(fixture.service.canReturnFromWholeDeviceEject(physicalIdentity: fixture.device.id),
                "The isolated service must accept the recoverable journal.")
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<200 {
            settle(host)
            if fixture.store.canReturnFromWholeDeviceEject { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fixture.store.canReturnFromWholeDeviceEject,
                "The store must establish the return from the durable journal.")
        #expect(fixture.store.workbench.pendingOperation?.hasPrefix("eject:") == true)
        #expect(try JSONStateStore(url: fixture.paths.state).load().ejectIntent)
        settle(host)
        let scroll = try #require(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
        let button = try #require(nativeButton("uma.sectorium.return-to-development", in: host),
                                  "The journaled return must be a native, focusable control.")
        let refresh = try #require(nativeButton("uma.sectorium.refresh", in: host))
        #expect(button.isEnabled)
        #expect(button.canBecomeKeyView)
        #expect(button.window === window)
        let focusRect = { (view: NSView) in
            view.convert(view.bounds, to: scroll.contentView).insetBy(dx: -6, dy: -6)
        }
        #expect(window.makeFirstResponder(refresh))
        var reached = false
        for _ in 0..<96 {
            window.selectNextKeyView(nil)
            try await Task.sleep(for: .milliseconds(5))
            if window.firstResponder === button {
                reached = true
                #expect(scroll.contentView.bounds.contains(focusRect(button)),
                        "Forward focus must keep the journaled return in view.")
                break
            }
        }
        #expect(reached, "Forward attached-window Tab must reach the journaled return.")
        var restored = false
        for _ in 0..<96 {
            if window.firstResponder === refresh { restored = true; break }
            window.selectPreviousKeyView(nil)
            try await Task.sleep(for: .milliseconds(5))
            if let responder = window.firstResponder as? NSView {
                #expect(scroll.contentView.bounds.contains(focusRect(responder)),
                        "Reverse focus must remain visible after the journaled return.")
            }
        }
        #expect(restored, "Reverse Tab must restore Refresh after the journaled return.")
    }

    @Test func sectoriumLocalSamplingConsentRequiresVerifiedIdentity() async throws {
        // Rewritten for 0.17.2, which moved the consent switch into an internal
        // drive's folded Drive details as a SwiftUI toggle; its old native
        // control and Tab stop went with it. What it guards stays: AUV reads an
        // internal drive's whole-drive I/O only with consent, and only consent
        // given to a drive whose identity is verified.
        let fixture = HESectoriumKeyboardFixture(isExternal: false)
        defer { fixture.remove() }
        fixture.store.selectDevice(fixture.device.id)
        fixture.store.activateWorkbench()
        defer { fixture.store.deactivateWorkbench() }
        try await waitForAvailableInventory(fixture.store)
        let unverified = SectoriumPhysicalDevice(id: fixture.device.id, bsdName: fixture.device.bsdName,
            name: fixture.device.name, isExternal: false, identityVerified: false,
            wholeDeviceBytes: fixture.device.wholeDeviceBytes, mountedVolumePaths: [], volumeUUIDs: [],
            readBytes: nil, writtenBytes: nil, isVirtual: false)
        fixture.store.apply(devices: [unverified], profiles: [], readiness: .unknown("Identity unavailable"), pending: nil)
        #expect(fixture.store.workbench.selectedDeviceID == fixture.device.id)
        fixture.store.setLocalDeviceSamplingConsent(true, for: fixture.device.id)
        waitForIOCalls(fixture.ioSampler, count: 1)
        #expect(!fixture.store.isLocalDeviceSamplingConsented(fixture.device.id),
                "Consent must not be recorded for a drive whose identity is unverified.")
        #expect(fixture.ioSampler.sampledNames.isEmpty, "An unverified internal drive must not be sampled.")

        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .connected, pending: nil)
        fixture.store.setLocalDeviceSamplingConsent(true, for: fixture.device.id)
        #expect(fixture.store.isLocalDeviceSamplingConsented(fixture.device.id))
        waitForIOCalls(fixture.ioSampler, count: 1)
        #expect(fixture.ioSampler.sampledNames.contains(fixture.device.bsdName),
                "Consent to a verified internal drive starts its whole-drive sampling.")
    }

    @Test func sectoriumConsentedInternalBackingAnchorNeverInvokesWholeMediaProvider() async throws {
        let provider = HESectoriumKeyboardIOProviderSpy()
        let fixture = HESectoriumKeyboardFixture(isExternal: false,
            ioSamplerOverride: SectoriumDeviceIOSampler(provider: provider))
        defer { fixture.remove() }
        let backingID = UUID()
        let anchored = SectoriumPhysicalDevice(id: backingID.uuidString, bsdName: fixture.device.bsdName,
            name: fixture.device.name, isExternal: false, identityVerified: true,
            wholeDeviceBytes: fixture.device.wholeDeviceBytes, mountedVolumePaths: [fixture.root.path],
            volumeUUIDs: [backingID], readBytes: nil, writtenBytes: nil,
            volumeMembers: [.init(volumeUUID: backingID, bsdName: "disk81s1", mountPoint: fixture.root.path)],
            topologyComplete: true, isVirtual: false, identityBasis: .uniqueBackingVolumeUUID,
            requiresFreshParentCheck: true)
        #expect(anchored.identityVerified)
        #expect(anchored.wholeMediaUUID == nil)
        fixture.store.apply(devices: [anchored], profiles: [], readiness: .connected, pending: nil)
        fixture.store.selectDevice(anchored.id)
        fixture.store.activateWorkbench()
        try await waitForAvailableInventory(fixture.store)
        fixture.store.apply(devices: [anchored], profiles: [], readiness: .connected, pending: nil)
        #expect(fixture.store.workbench.selectedDeviceID == anchored.id)
        fixture.store.setLocalDeviceSamplingConsent(true, for: anchored.id)
        #expect(fixture.store.isLocalDeviceSamplingConsented(anchored.id))
        fixture.store.sampleSelectedDeviceIO()
        try await Task.sleep(for: .milliseconds(100))
        #expect(provider.requestedNames.isEmpty,
            "An internal backing-volume anchor without whole-media UUID cannot reach the whole-media provider.")
        #expect(fixture.runner.targetedInfoNames.isEmpty)
        #expect(!fixture.store.workbench.io.isFresh)
        fixture.store.deactivateWorkbench()
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

    @Test func sectoriumRefreshInvalidatesReadyAndBlocksIdentityActionsUntilObservation() async throws {
        _ = NSApplication.shared
        let observer = HESectoriumHeldDeviceObserver()
        let fixture = HESectoriumKeyboardFixture(observerOverride: observer)
        observer.device = fixture.device
        defer { observer.release(); fixture.remove() }
        fixture.store.selectDevice(fixture.device.id)
        for _ in 0..<40 {
            if fixture.store.inventoryState == .available { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(fixture.store.inventoryState == .available)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .ready, pending: nil)
        observer.hold()
        fixture.store.refresh()
        #expect(fixture.store.inventoryState == .loading)
        #expect(fixture.store.workbench.readiness != .ready)
        #expect(!fixture.store.discoveredLegacyDisk)
        #expect(observer.waitUntilEntered())
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let identityActions: Set<String> = ["uma.sectorium.create", "uma.sectorium.adopt", "uma.sectorium.start", "uma.sectorium.stop"]
        #expect(!descendants(of: host).compactMap { $0 as? NSButton }
            .contains { identityActions.contains($0.accessibilityIdentifier()) })
        observer.release()
        for _ in 0..<40 {
            if fixture.store.inventoryState == .available { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(fixture.store.inventoryState == .available)
        fixture.store.apply(devices: [fixture.device], profiles: [], readiness: .ready, pending: nil)
        observer.fail()
        fixture.store.refresh()
        #expect(fixture.store.workbench.readiness != .ready)
        for _ in 0..<40 {
            if fixture.store.inventoryState == .unavailable { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(fixture.store.inventoryState == .unavailable)
        #expect(fixture.store.workbench.devices.isEmpty)
        #expect(fixture.store.workbench.readiness != .ready)
    }

    @Test func sectoriumLateFailedRefreshCannotReplaceNewerInventory() async throws {
        let observer = HESectoriumHeldDeviceObserver()
        let fixture = HESectoriumKeyboardFixture(observerOverride: observer)
        observer.device = fixture.device
        defer { observer.release(); fixture.remove() }
        // Since 0.17.2 a visible surface is what loads the inventory; selecting
        // a drive does no I/O of its own.
        fixture.store.activateWorkbench()
        defer { fixture.store.deactivateWorkbench() }
        try await waitForAvailableInventory(fixture.store)
        observer.holdNextOnly()
        fixture.store.refresh()
        #expect(observer.waitUntilEntered())
        #expect(fixture.store.inventoryState != .available,
                "A foreground refresh must drop the earlier inventory until it is observed again.")
        // A second refresh no longer races the first: it is queued behind it.
        // The first then fails late, and the newer request must still run and
        // be what the workbench ends up showing.
        fixture.store.refresh()
        observer.failNextOnly()
        observer.release()
        for _ in 0..<80 {
            if fixture.store.inventoryState == .available { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(fixture.store.inventoryState == .available,
                "The refresh requested after the failing one must replace its failure.")
        #expect(fixture.store.workbench.devices == [fixture.device])
    }

    @Test func sectoriumSettingsSheetClosesAndReturnsFocusInAttachedWindow() async throws {
        _ = NSApplication.shared
        NSApp.activate(ignoringOtherApps: true)
        let fixture = HESectoriumKeyboardFixture()
        defer { fixture.remove() }
        let host = NSHostingView(rootView: SectoriumWorkbenchView(store: fixture.store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let settings = try #require(descendants(of: host).compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "uma.sectorium.settings" })
        let actualButtonWindow = settings.window
        print("SETTINGS_OWNER_OBSERVATION expectedWindow=\(ObjectIdentifier(window)) buttonWindow=\(String(describing: actualButtonWindow.map(ObjectIdentifier.init))) same=\(actualButtonWindow === window)")
        let sheetForTestWindow = { NSApp.windows.first { $0.isSheet && $0.sheetParent === window } }
        #expect(window.makeFirstResponder(settings))
        #expect(settings.isEnabled && settings.action != nil && settings.target != nil)
        settings.performClick(nil)
        for _ in 0..<40 {
            if sheetForTestWindow() != nil { break }
            try await Task.sleep(for: .milliseconds(25))
            settle(host)
        }
        let windowState = NSApp.windows.map {
            "id=\(ObjectIdentifier($0))|title=\($0.title)|visible=\($0.isVisible)|sheet=\($0.isSheet)|parent=\(String(describing: $0.sheetParent.map(ObjectIdentifier.init)))"
        }.joined(separator: "; ")
        print("SETTINGS_SHEET_OBSERVATION expectedWindow=\(ObjectIdentifier(window)) buttonWindow=\(String(describing: actualButtonWindow.map(ObjectIdentifier.init))) attached=\(String(describing: window.attachedSheet.map(ObjectIdentifier.init))) windows={\(windowState)}")
        let sheet = try #require(sheetForTestWindow(),
            "The Settings control activated but no attached sheet appeared. Windows: \(windowState)")
        #expect(sheet.isSheet)
        #expect(sheet.sheetParent === window)
        let content = try #require(sheet.contentView)
        sheet.layoutIfNeeded()
        settle(content)
        let close = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.sectorium.settings.close"
        }, "Sheet identifiers: \(descendants(of: content).map { $0.accessibilityIdentifier() })")
        #expect(close.window === sheet)
        click(close, in: sheet)
        settle(host)
        for _ in 0..<20 {
            if sheetForTestWindow() == nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(window.attachedSheet == nil)
        #expect(sheetForTestWindow() == nil)
        for _ in 0..<20 {
            if (window.firstResponder as? NSView).flatMap(accessibilityIdentifier(in:)) == "uma.sectorium.settings" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect((window.firstResponder as? NSView).flatMap(accessibilityIdentifier(in:)) == "uma.sectorium.settings")

        let reopenedSettings = try #require(descendants(of: host).first {
            $0.accessibilityIdentifier() == "uma.sectorium.settings"
        })
        click(reopenedSettings, in: window)
        for _ in 0..<40 {
            if sheetForTestWindow() != nil { break }
            try await Task.sleep(for: .milliseconds(25))
            settle(host)
        }
        let reopenedSheet = try #require(sheetForTestWindow())
        #expect(reopenedSheet.isSheet)
        #expect(reopenedSheet.sheetParent === window)
        let reopenedContent = try #require(reopenedSheet.contentView)
        settle(reopenedContent)
        let reopenedClose = try #require(descendants(of: reopenedContent).first {
            $0.accessibilityIdentifier() == "uma.sectorium.settings.close"
        })
        #expect(reopenedSheet.makeFirstResponder(reopenedClose))
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: reopenedSheet.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        reopenedSheet.sendEvent(escape)
        for _ in 0..<20 {
            if sheetForTestWindow() == nil,
               (window.firstResponder as? NSView).flatMap(accessibilityIdentifier(in:)) == "uma.sectorium.settings" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(window.attachedSheet == nil)
        #expect(sheetForTestWindow() == nil)
        #expect((window.firstResponder as? NSView).flatMap(accessibilityIdentifier(in:)) == "uma.sectorium.settings")
    }

    @Test func hesSettingsActionsReceiveVisibleForwardAndReverseWindowFocus() async throws {
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
        try await waitForAvailableInventory(fixture.store)
        settle(host)
        let expected: Set<String> = [
            "uma.settings.hesectorium.install", "uma.settings.hesectorium.repair",
            "uma.settings.hesectorium.automation", "uma.settings.hesectorium.refresh"
        ]
        let eject = try #require(descendants(of: host).compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "uma.settings.hesectorium.eject" })
        #expect(!eject.isEnabled, "A drive without a verified eject checkpoint must not expose an active eject control.")
        var forward: Set<String> = []
        for _ in 0..<48 {
            window.selectNextKeyView(nil)
            try await Task.sleep(for: .milliseconds(10))
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
            try await Task.sleep(for: .milliseconds(10))
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

    private func nativeButton(_ identifier: String, in host: NSView) -> NSButton? {
        descendants(of: host).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == identifier }
    }

    private func waitForAvailableInventory(_ store: HESectoriumStore) async throws {
        for _ in 0..<80 {
            if store.inventoryState == .available { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(store.inventoryState == .available, "The fixture inventory must finish before testing enabled native controls.")
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

    private func recognizedText(in host: NSView) throws -> [(text: String, frame: CGRect)] {
        let bounds = host.bounds
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(bounds.width)), pixelsHigh: max(1, Int(bounds.height)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            "Allocate a bitmap for rendered overview verification.")
        host.cacheDisplay(in: bounds, to: bitmap)
        let cgImage = try #require(bitmap.cgImage, "The hosted overview bitmap must expose pixels for visible-text verification; bounds=\(bounds), bytes=\(bitmap.bytesPerRow).")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, observation.boundingBox)
        }
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
         ejectMode: HESectoriumKeyboardEjectMode = .none,
         observerOverride: SectoriumDeviceObserving? = nil,
         ioSamplerOverride: SectoriumDeviceIOCounterSampling? = nil) {
        root = URL(fileURLWithPath: "/private/tmp/hesectorium-keyboard-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = HESectoriumPaths(root: root.appendingPathComponent("support", isDirectory: true))
        let mediaUUID = UUID()
        device = SectoriumPhysicalDevice(id: identityVerified ? mediaUUID.uuidString : "unverified-disk81",
            bsdName: "disk81", name: "Fixture drive",
            isExternal: isExternal, identityVerified: identityVerified, wholeDeviceBytes: 1024 * 1024 * 1024,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
            isVirtual: false)
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
            sectoriumDeviceObserver: observerOverride ?? HESectoriumKeyboardDeviceObserver(device: device),
            sectoriumDeviceIOSampler: ioSamplerOverride ?? ioSampler, wholeDeviceEjectDriverOverride: ejectDriver)
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
    func presence(of target: WholeDeviceTopology) -> WholeDevicePresence {
        target.physicalIdentity == topology.physicalIdentity ? .present : .unknown("fixture target mismatch")
    }
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

private final class HESectoriumHeldDeviceObserver: SectoriumDeviceObserving {
    private let condition = NSCondition()
    var device: SectoriumPhysicalDevice?
    private var holding = false
    private var holdRemaining: Int? = nil
    private var entered = false
    private var failing = false
    private var failRemaining = 0
    func hold() { condition.lock(); holding = true; holdRemaining = nil; entered = false; condition.unlock() }
    func holdNextOnly() { condition.lock(); holding = true; holdRemaining = 1; entered = false; condition.unlock() }
    func fail() { condition.lock(); failing = true; condition.unlock() }
    /// Fails only the observation it is next released into, so a refresh
    /// queued behind a failing one can still succeed.
    func failNextOnly() { condition.lock(); failRemaining = 1; condition.unlock() }
    func release() { condition.lock(); holding = false; condition.broadcast(); condition.unlock() }
    func waitUntilEntered() -> Bool {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(2)
        while !entered && Date() < deadline { _ = condition.wait(until: deadline) }
        return entered
    }
    func observeDevices() throws -> [SectoriumPhysicalDevice] {
        condition.lock()
        let shouldHold = holding && (holdRemaining == nil || holdRemaining! > 0)
        if let remaining = holdRemaining { holdRemaining = max(0, remaining - 1) }
        entered = true
        condition.broadcast()
        while shouldHold && holding { condition.wait() }
        let shouldFail = failing || failRemaining > 0
        failRemaining = max(0, failRemaining - 1)
        let observedDevice = device
        condition.unlock()
        if shouldFail { throw SectoriumDeviceCatalogError.commandFailed("fixture permission denied") }
        return observedDevice.map { [$0] } ?? []
    }
}

private final class HESectoriumKeyboardDeviceObserver: SectoriumDeviceObserving {
    let device: SectoriumPhysicalDevice
    init(device: SectoriumPhysicalDevice) { self.device = device }
    func observeDevices() throws -> [SectoriumPhysicalDevice] { [device] }
}

private final class HESectoriumMultiDeviceObserver: SectoriumDeviceObserving {
    var devices: [SectoriumPhysicalDevice]
    init(devices: [SectoriumPhysicalDevice]) { self.devices = devices }
    func observeDevices() throws -> [SectoriumPhysicalDevice] { devices }
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

private final class HESectoriumKeyboardIOProviderSpy: SectoriumIORegistryProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    var requestedNames: [String] { lock.lock(); defer { lock.unlock() }; return names }
    func providerMappings(forWholeBSDName bsdName: String) throws -> [SectoriumIOMediaProviderMapping] {
        lock.lock(); names.append(bsdName); lock.unlock()
        return []
    }
}
