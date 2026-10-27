import Foundation
import AppKit
import Testing
@testable import CodexUsageUI
@testable import CodexUsageMonitor

@Suite("M5RMX product shell isolation", .timeLimit(.minutes(1)))
struct M5RMXProductShellIsolationTests {
    @Test("Settings and registry subscribers both receive Claude updates", .timeLimit(.minutes(1)))
    func independentSnapshotSubscribersReceiveTheSameUpdate() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let first = await connector.snapshots()
        var firstIterator = first.makeAsyncIterator()
        _ = await firstIterator.next()
        let second = await connector.snapshots()
        var secondIterator = second.makeAsyncIterator()
        _ = await secondIterator.next()

        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 27, seven: 41))
        let secondUpdate = try #require(await secondIterator.next())
        let firstUpdate = try #require(await firstIterator.next())
        #expect(firstUpdate == secondUpdate)
        #expect(firstUpdate.channels.flatMap(\.rateLimitWindows).first?.remainingPercent == 73)
        await connector.stop()
    }

    @Test("Cancelling one Claude subscriber leaves the other and connector active")
    func cancellingOneSnapshotSubscriberDoesNotStopTheOther() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        let first = await connector.snapshots()
        let second = await connector.snapshots()
        var secondIterator = second.makeAsyncIterator()
        _ = await secondIterator.next()
        let detached = M5AEventCounter()
        await connector.observeSnapshotRemoval { detached.signal() }
        let cancelledConsumer = Task {
            for await _ in first {}
        }
        cancelledConsumer.cancel()
        await cancelledConsumer.value
        await detached.wait()

        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 27, seven: 41))
        let update = try #require(await secondIterator.next())
        #expect(update.channels.flatMap(\.rateLimitWindows).first?.remainingPercent == 73)
        #expect(await fixture.bridge.startCount == 1)
        #expect(await fixture.bridge.stopCount == 0)
        await connector.stop()
    }

    @Test("Lifecycle reads do not republish snapshots into the Settings observer")
    func lifecycleReadIsSideEffectFree() async throws {
        let connector = ClaudeCodeUsageConnector.production(hasConsent: { false })
        let stream = await connector.snapshots()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let before = await connector.snapshotPublicationCount()
        for _ in 0..<100 {
            _ = await connector.lifecycleState()
        }
        #expect(await connector.snapshotPublicationCount() == before)
    }

    @Test("Consented Local Smart startup performs no Safari work")
    func consentedLocalStartupIsBrowserFree() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()

        await connector.start()

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.listenerStartCount == 0)
        #expect(await fixture.bridge.startCount == 0)
        #expect(await fixture.bridge.verificationCount == 0)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.repairCount == 0)
    }

    @Test("Safari failure stays isolated from ordinary Local Smart refresh")
    func safariFailureDoesNotOwnLocalRefresh() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()

        await fixture.bridge.setHealth(.browserUnavailable)
        await connector.checkCompanion()
        #expect(await connector.lifecycleState() == .browserUnavailable)
        #expect((await connector.diagnostics()).listenerStartCount == 1)

        await connector.syncNow()
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.listenerStartCount == 1)
        #expect(await fixture.bridge.startCount == 1)
        #expect(await fixture.bridge.verificationCount == 0)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect(await fixture.bridge.openCount == 0)
        #expect(await fixture.bridge.repairCount == 0)
    }

    @Test("Snapshot observation does not feed admission refresh back into itself")
    func settingsObservationHasNoAdmissionFeedbackLoop() throws {
        let settings = try source(
            "Sources/CodexUsageUI/Stores/ClaudeBrowserSettingsModel.swift"
        )
        let observation = try #require(
            settings.slice(
                from: "observationTask = Task",
                through: "deinit {"
            )
        )

        #expect(observation.contains("for await snapshot in stream"))
        #expect(!observation.contains("refreshAdmissions"))
    }

    @Test("Hidden Settings contributes no full-panel hit-testing overlay")
    func hiddenSettingsHasNoOverlayContainer() throws {
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let overlay = try #require(
            panel.slice(
                from: ".overlay(alignment: .topTrailing) {",
                through: ".animation("
            )
        )

        #expect(overlay.contains("if isShowingSettings"))
        #expect(overlay.contains("UsageSettingsCard("))
        #expect(!overlay.contains("ZStack"))
    }

    @Test("Opening Settings never starts a Safari Companion probe")
    func settingsAppearanceDoesNotProbeSafari() throws {
        let settings = try source("Sources/CodexUsageUI/Views/UsageSettingsCard.swift")
        let claudeSection = try #require(
            settings.slice(
                from: "private struct ClaudeBrowserSettingsSection",
                through: "private struct WorkBuddySettingsSection"
            )
        )

        #expect(!claudeSection.contains(".onAppear"))
        #expect(!claudeSection.contains("model.checkCompanion()"))
        #expect(claudeSection.contains("action: model.checkCompanion"))
    }

    @Test("Main toolbar controls remain independent from provider action state")
    func toolbarIsProviderIndependent() throws {
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let header = try #require(
            panel.slice(
                from: "private struct MonitorHeaderView",
                through: "private struct RecoveryActionButton"
            )
        )

        #expect(header.contains("Task { await store.refresh() }"))
        #expect(header.contains("isShowingSettings.toggle()"))
        #expect(!header.contains("claudeSettings"))
        #expect(!header.contains("actionInProgress"))
        #expect(!header.contains(".disabled("))
    }

    @Test("Shell has one root coordinator and no provider-owned presentation")
    func shellHasOneIndependentOwner() throws {
        let app = try source("Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift")
        let shell = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        #expect(app.contains("private let shellCoordinator: AppShellCoordinator?"))
        #expect(app.contains("shellCoordinator: AppShellCoordinator(),"))
        #expect(!app.contains("private var statusBarController"))
        #expect(shell.contains("private static weak var activeCoordinator"))
        for forbidden in ["ClaudeCodeUsageConnector", "Safari", "PlugInKit", "Accuracy Sync"] {
            #expect(!shell.contains(forbidden))
        }
    }

    @Test("Status item action has an independent real-event diagnostic")
    func statusItemActionContractIsObservableWithoutTimingFallback() throws {
        let status = try source("Sources/CodexUsageMonitor/App/StatusBarController.swift")
        #expect(status.contains("installStatusEventMonitor"))
        #expect(status.contains("event.window === self.statusItem.button?.window"))
        #expect(!status.contains("pointerDownHandled"))
        #expect(status.contains("repairStatusButtonContractIfNeeded"))
        #expect(status.contains("button.target = self"))
        #expect(status.contains("button.action = #selector(handleStatusItemAction)"))
    }

    @Test("Quick Panel toggle follows the selected single-surface host")
    func panelStateFollowsActualWindow() throws {
        let panel = try source(
            "Sources/CodexUsageMonitor/App/QuickPanelPopoverController.swift"
        )
        #expect(panel.contains("func toggle() { panel.isVisible ? close() : present() }"))
        #expect(panel.contains("panel.hasShadow = false"))
        #expect(panel.contains("panel.contentView === materialHost"))
        #expect(panel.contains("eventMonitorCount: 0"))
        #expect(panel.contains("AdaptivePanelMaterialHostView exclusively owns"))
    }

    @Test("Shell is created before provider runtime composition")
    func shellFirstStartupCannotBeOwnedByProviders() throws {
        let app = try source("Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift")
        let launch = try #require(app.slice(
            from: "func applicationDidFinishLaunching",
            through: "private func finishShellDiagnostic"
        ))
        let shellStart = try #require(launch.range(of: "shellCoordinator.start(presentMainWindow:"))
        let runtimeCreation = try #require(launch.range(of: "self.runtimeFactory("))
        #expect(shellStart.lowerBound < runtimeCreation.lowerBound)
        #expect(!app.contains("await Task.yield()"))
        #expect(app.contains("NSApp.unhide(nil)"))
        #expect(app.contains("self.shellCoordinator?.attach(runtime: runtime)"))
        #expect(app.contains("applicationShouldHandleReopen"))
        #expect(!app.contains("fatalError("))

        let status = try source("Sources/CodexUsageMonitor/App/StatusBarController.swift")
        let initializer = try #require(
            status.slice(from: "init(", through: "func attach(runtime:")
        )
        #expect(initializer.contains("QuickPanelPopoverController("))
        #expect(!initializer.contains("DesktopAssistantPanelController("))
        #expect(!initializer.contains("UsageMonitorRuntime"))

        let shell = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        #expect(shell.contains("assistantController = DesktopAssistantPanelController("))
    }

    @Test("Physical click diagnostics are content-free and lifecycle-scoped")
    func physicalClickIsMachineObservable() throws {
        let shell = try source("Sources/CodexUsageMonitor/App/AppShellCoordinator.swift")
        for required in [
            "mouseDownReceived", "mouseUpReceived", "actionInvoked", "toggleRequested",
            "panelWindowOrderedFront", "panelVisible", "hitTestingEnabled",
            "lifecycleGeneration", "eventMonitorCount", "eventMonitorOwners",
            "activeSheetWindow", "suffix(64)",
        ] {
            #expect(shell.contains(required))
        }
        for forbidden in ["quota", "cookie", "token", "DOM", "HTML", "prompt"] {
            #expect(!shell.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test("Shell-only machine diagnostic exercises 100 native AppKit toggles")
    func shellOnlyDiagnosticIsProviderInertAndChecksResponsiveness() throws {
        let app = try source("Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift")
        let status = try source("Sources/CodexUsageMonitor/App/StatusBarController.swift")
        let runtime = try source("Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift")
        #expect(app.contains("--diagnose-app-shell"))
        #expect(app.contains("guard !shellDiagnosticRequested else { return .terminateNow }"))
        #expect(app.contains("self.runtimeFactory(!self.shellDiagnosticRequested)"))
        #expect(app.contains("startProviders: startProviders"))
        #expect(app.contains("runMachineDiagnostic("))
        #expect(app.contains("toggleCount: 100"))
        #expect(status.contains("NSApp.sendAction(action, to: button.target, from: button)"))
        #expect(status.contains("state.isEffectivelyOpen && state.isResponsive"))
        #expect(runtime.contains("if startProviders"))
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
