import Foundation
import Testing
@testable import CodexUsageMonitor

@Suite("UMA 0.14 M3R Quick Panel host")
struct UMA014M3RQuickPanelHostTests {
    @Test("One native panel and one material host own the Quick Panel surface")
    func singlePanelOwnsTheSurface() throws {
        let controller = try source(
            "Sources/CodexUsageMonitor/App/QuickPanelPopoverController.swift"
        )
        let status = try source(
            "Sources/CodexUsageMonitor/App/StatusBarController.swift"
        )

        #expect(controller.contains("private let panel = QuickPanelWindow()"))
        #expect(controller.contains("private final class QuickPanelWindow: NSPanel"))
        #expect(controller.contains("private let materialHost = AdaptivePanelMaterialHostView"))
        #expect(controller.contains("panel.contentView = materialHost"))
        #expect(controller.contains("panel.backgroundColor = .clear"))
        #expect(controller.contains("panel.hasShadow = false"))
        #expect(controller.contains("&& panel.hasShadow == false"))
        #expect(!controller.contains("NSPopover"))
        #expect(!controller.contains("NSEvent.add"))
        #expect(!controller.contains(".background(.regularMaterial)"))
        #expect(!controller.contains(".clipShape"))
        #expect(status.contains("QuickPanelPopoverController"))
        #expect(!status.contains("TransparentUsagePanelController"))
        #expect(
            !FileManager.default.fileExists(
                atPath: repositoryRoot()
                    .appendingPathComponent(
                        "Sources/CodexUsageMonitor/App/TransparentUsagePanelController.swift"
                    )
                    .path
            )
        )
    }

    @Test("Quick Panel geometry stays inside the approved glance-surface bounds")
    @MainActor
    func contentGeometryContract() {
        #expect(QuickPanelPopoverController.contentWidth == 320)
        #expect(QuickPanelPopoverController.contentWidth >= 300)
        #expect(QuickPanelPopoverController.contentWidth <= 330)
        #expect(QuickPanelPopoverController.minimumContentHeight == 72)
        #expect(
            QuickPanelPopoverController.maximumContentHeight
                > QuickPanelPopoverController.minimumContentHeight
        )
    }

    @Test("Navigation closes the transient surface and all work routes through app actions")
    func navigationAndCommandsAreCentralized() throws {
        let controller = try source(
            "Sources/CodexUsageMonitor/App/QuickPanelPopoverController.swift"
        )
        let status = try source(
            "Sources/CodexUsageMonitor/App/StatusBarController.swift"
        )

        #expect(controller.contains("self?.close()\n                    actions.openMain()"))
        #expect(controller.contains("self?.close()\n                    actions.openSettings()"))
        #expect(controller.contains("self?.close()\n                    actions.selectAgent(providerID)"))
        #expect(status.contains("quickPanelActions?.refreshAll()"))
        #expect(!status.contains("Task { await store.refresh() }"))
    }

    @Test("Machine diagnostic rejects host, sizing, and interaction regressions")
    func machineDiagnosticCoversHostInvariants() throws {
        let status = try source(
            "Sources/CodexUsageMonitor/App/StatusBarController.swift"
        )

        for reason in [
            "PANEL_NOT_SINGLE_SURFACE_HOST",
            "PANEL_CONTENT_SIZE_OUT_OF_BOUNDS",
            "PANEL_INTERACTION_OWNERSHIP_INVALID",
            "PANEL_OPEN_CONVERGENCE_FAILED",
            "PANEL_CLOSE_CONVERGENCE_FAILED",
        ] {
            #expect(status.contains(reason))
        }
    }

    @Test("Panel focus, escape, and outside-click behavior stay native and bounded")
    func focusAndDismissalContract() throws {
        let controller = try source(
            "Sources/CodexUsageMonitor/App/QuickPanelPopoverController.swift"
        )

        #expect(controller.contains("override var canBecomeKey: Bool { true }"))
        #expect(controller.contains("override var canBecomeMain: Bool { false }"))
        #expect(controller.contains("override func cancelOperation"))
        #expect(controller.contains("func windowDidResignKey"))
        #expect(controller.contains("DispatchQueue.main.async { [weak self]"))
        #expect(controller.contains("self.panel.isVisible, !self.panel.isKeyWindow"))
        #expect(controller.contains("panel.makeKeyAndOrderFront(nil)"))
        #expect(controller.contains("panel.collectionBehavior = [.transient"))
        #expect(!controller.contains("NSEvent.addGlobalMonitorForEvents"))
        #expect(!controller.contains("NSEvent.addLocalMonitorForEvents"))
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
