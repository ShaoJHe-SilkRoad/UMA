import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.14 M3R review artifacts")
struct UMA014M3RReviewArtifactTests {
    @Test("Preview stores preserve injected product cards for deterministic surface renders")
    @MainActor
    func previewStorePreservesInjectedProductInventory() throws {
        let source = try source("Sources/PreviewRendererTool/main.swift")
        #expect(source.contains("presentationCards: cards"))

        let window = SharedUsageWindowPresentation(
            id: "seven-day",
            kind: .sevenDay,
            compactLabel: "7D",
            accessibilityLabel: "seven-day window",
            remaining: .finite(64),
            resetsAt: nil,
            resetText: ""
        )
        let card = SharedUsageCardPresentation(
            id: CodexUsageConnector.connectorID.rawValue,
            providerName: "Codex",
            planLabel: "PRO",
            connectionStatus: .connected,
            freshness: .fresh,
            windows: [window],
            selectedWindowID: window.id,
            remaining: .finite(64),
            isEstimated: false,
            sourceDescription: "Synthetic review fixture",
            isVisibleInDesktopAssistant: true,
            severity: .normal,
            isRetainingLastValidValue: false,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = UsageStore.preview(
            scenario: .ready,
            language: .english,
            presentationCards: [card]
        )

        #expect(store.presentationCards.map { $0.id } == [card.id])
        #expect(
            store.productInventory.agentWorkspaceProviders.map { $0.id }
                == [ProviderProductID.codex]
        )
        #expect(
            store.productInventory.quickPanelProviders.map { $0.id }
                == [ProviderProductID.codex]
        )
        #expect(store.productInventory.provider(.workBuddy)?.inventory.providers == false)
        #expect(store.productInventory.provider(.antigravity)?.inventory.providers == false)
    }

    @Test("Review matrix renders real public product surfaces from preview-only state")
    func rendererUsesProductSurfacesWithoutLiveSources() throws {
        let renderer = try source("Sources/PreviewRendererTool/main.swift")

        for surface in [
            "QuickPanelSurface(",
            "AgentGlanceRow(",
            "AgentWorkspaceSurface(",
            "GlobalSettingsSurface(",
            "DesktopAssistantView(",
        ] {
            #expect(renderer.contains(surface))
        }
        for scenario in [
            "quick-one",
            "quick-zero",
            "quick-degraded",
            "quick-edge",
            "main-narrow",
            "workspace-codex",
            "workspace-claude",
            "settings-appearance",
            "settings-wizard",
            "settings-privacy",
            "wizard-regular",
            "wizard-minimalist",
            "wizard-context-menu",
            "threados",
        ] {
            #expect(renderer.contains(scenario))
        }

        #expect(renderer.contains("UsageStore.preview("))
        #expect(renderer.contains("ApplicationPreferences.inMemory()"))
        #expect(renderer.contains("M3RFixture.fixedNow"))
        #expect(renderer.contains("--scale="))
        #expect(renderer.contains("--alpha-mask"))
        #expect(renderer.contains("if reduceTransparency"))
        #expect(renderer.contains("if increaseContrast"))
        #expect(renderer.contains("if reduceMotion"))
        #expect(renderer.contains("transaction.animation = nil"))
        #expect(renderer.contains("makeAlphaMask(from:"))
        #expect(renderer.contains("minimumAlpha <= 16"))
        #expect(renderer.contains("maximumAlpha == 255"))
        #expect(!renderer.contains("URLSession.shared"))
    }

    @Test("Packaging produces the complete durable synthetic review contract")
    func packageScriptOwnsCompleteMatrix() throws {
        let script = try source("script/package_uma014_m3r_review.sh")

        #expect(script.contains("UMA014_M3R_REVIEW_ARTIFACTS_DIR"))
        #expect(script.contains("Review Artifacts"))
        #expect(script.contains("REVIEW_FIXTURES=SYNTHETIC_PREVIEW_ONLY"))
        #expect(script.contains("SHA256SUMS"))
        #expect(script.contains("REVIEW-MANIFEST.json"))
        #expect(script.contains("RUNTIME_ENABLED_NO_SYNTHETIC_PROVIDER_DATA"))
        #expect(script.contains("SYNTHETIC_PREVIEW_ONLY"))
        #expect(script.contains("providerReadsDuringArtifactGeneration"))
        #expect(script.components(separatedBy: "render \"").count - 1 == 25)

        for filename in [
            "01-quick-panel-light.png",
            "02-quick-panel-dark.png",
            "03-quick-panel-zero-providers.png",
            "04-quick-panel-degraded.png",
            "05-quick-panel-chinese.png",
            "06-main-codex-light.png",
            "07-main-codex-dark.png",
            "08-main-narrow-claude.png",
            "09-codex-workspace.png",
            "10-claude-workspace.png",
            "11-global-settings.png",
            "12-desktop-wizard-regular.png",
            "13-desktop-wizard-minimalist.png",
            "14-threados-placeholder.png",
            "15-quick-panel-edge-bright-2x.png",
            "16-quick-panel-edge-dark-2x.png",
            "17-quick-panel-one-agent.png",
            "18-quick-panel-reduce-transparency.png",
            "19-quick-panel-increase-contrast.png",
            "20-quick-panel-reduce-motion.png",
            "21-quick-panel-edge-bright-1x.png",
            "22-quick-panel-edge-dark-1x.png",
            "23-quick-panel-alpha-mask-2x.png",
            "24-quick-panel-alpha-mask-1x.png",
            "25-desktop-wizard-context-menu.png",
        ] {
            #expect(script.contains(filename))
        }

        #expect(script.contains("--scale=1"))
        #expect(script.contains("--scale=2"))
        #expect(script.contains("--reduce-transparency"))
        #expect(script.contains("--increase-contrast"))
        #expect(script.contains("--reduce-motion"))
        #expect(script.contains("--alpha-mask"))

        for prohibited in ["curl ", "notarytool", "security find", "osascript"] {
            #expect(!script.contains(prohibited))
        }
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
