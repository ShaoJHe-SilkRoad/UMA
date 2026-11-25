import AppKit
import ClaudeBrowserBridgeProtocol
import Foundation
import SwiftUI
import Testing
@testable import CodexUsageUI

/// Gemini is web-only: Scan Agents cannot find it and it starts off, so the
/// shipped Settings window must offer its switch. Build 2026112402 had none.
@Suite("Gemini can be turned on from the shipped Settings window", .serialized)
@MainActor
struct GeminiSettingsEntryTests {
    private actor Reads {
        var count = 0
        func next() -> GeminiBrowserObservation {
            count += 1
            return GeminiBrowserObservation(
                buckets: [
                    GeminiBrowserBucket(bucketID: "current", period: .unknown, usedPercentage: 10),
                    GeminiBrowserBucket(bucketID: "weekly", period: .weekly, usedPercentage: 4),
                ],
                planLabel: "pro",
                observedAt: ISO8601DateFormatter().string(from: Date())
            )
        }
    }

    @Test("From fresh preferences, Settings › Agents has an off Gemini switch that turns Gemini on")
    func freshPreferencesFindAndEnable() async throws {
        _ = NSApplication.shared
        let preferences = ApplicationPreferences.inMemory()
        let coordinator = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: preferences)
        )
        #expect(coordinator.isMonitoringEnabled(for: AgentPreferenceRecord.geminiProviderID) == false)

        let reads = Reads()
        let connector = GeminiUsageConnector(
            readUsage: { await reads.next() },
            hasConsent: { @MainActor in
                coordinator.isMonitoringEnabled(for: AgentPreferenceRecord.geminiProviderID)
            }
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: nil,
            preferences: preferences,
            agentSettings: coordinator,
            backgroundRefreshSleeper: { _ in throw CancellationError() }
        )
        let gemini = GeminiSettingsModel(
            connector: connector,
            agentSettings: coordinator,
            refreshAdmissions: { @MainActor in
                let descriptors = await registry.orderedDescriptors()
                _ = await registry.scanSurfaceAdmissions(
                    trigger: .manualRefresh,
                    excludedProviderIDs: coordinator.disabledConnectorIDs(from: descriptors.map(\.id))
                )
            }
        )
        #expect(!store.orderedWorkspaceProviders.contains { $0.id == .gemini })

        let surface = GlobalSettingsSurface(
            preferences: preferences,
            store: store,
            navigation: GlobalSettingsNavigationState(pane: .agents),
            dataPaths: .current(
                bundleIdentifier: "com.example.gemini-entry-fixture",
                applicationSupportDirectory: FileManager.default.temporaryDirectory,
                homeDirectory: FileManager.default.temporaryDirectory
            ),
            geminiSettings: gemini
        )
        let controller = NSHostingController(rootView: surface)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 760, height: 560))
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }
        settle(controller.view)

        // SwiftUI does not carry accessibility identifiers onto AppKit views
        // in a hosted Form, and tests have no accessibility client. The Agents
        // pane has no other switch, and pressing this one must turn Gemini on,
        // which is what proves it is Gemini's.
        let switches = descendants(controller.view).compactMap { $0 as? NSSwitch }
        #expect(switches.count == 1, "Settings › Agents must show one switch, Gemini's")
        let control = try #require(switches.first, "Settings › Agents must show Gemini's switch")
        #expect(control.state == NSControl.StateValue.off)
        #expect(await reads.count == 0, "Nothing is read before the person turns Gemini on")

        control.performClick(nil)
        settle(controller.view)
        try await Task.sleep(for: .milliseconds(100))

        #expect(coordinator.isMonitoringEnabled(for: AgentPreferenceRecord.geminiProviderID))
        #expect(control.state == NSControl.StateValue.on)
        // Turning it on reads once and lists Gemini in the main window.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if await reads.count > 0, store.orderedWorkspaceProviders.contains(where: { $0.id == .gemini }) {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await reads.count >= 1)
        #expect(store.orderedWorkspaceProviders.contains { $0.id == .gemini })
    }

    private func settle(_ host: NSView) {
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
    }

    private func descendants(_ root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants($0) }
    }
}
