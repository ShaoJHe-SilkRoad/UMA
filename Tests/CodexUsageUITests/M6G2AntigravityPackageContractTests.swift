import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M6-G2 package and shared presentation contract")
struct M6G2AntigravityPackageContractTests {
    @Test
    func dynamicBucketLabelAndProviderOrderReachMainPanelOnly() throws {
        let antigravity = snapshot(
            id: GoogleAntigravityUsageConnector.connectorID,
            name: "Google Antigravity",
            label: "Primary pool",
            capabilities: GoogleAntigravityUsageConnector().descriptor.capabilities
        )
        let snapshots = [
            snapshot(id: AgentConnectorID(rawValue: "workbuddy.accountWeb")!, name: "WorkBuddy"),
            antigravity,
            snapshot(id: AgentConnectorID(rawValue: "claude.browserSync")!, name: "Claude Code"),
            snapshot(id: AgentConnectorID(rawValue: "codex.appServer")!, name: "Codex"),
        ]
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: snapshots,
            previousCards: [],
            language: .english,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(cards.map(\.providerName) == [
            "Codex", "Claude Code", "WorkBuddy", "Google Antigravity",
        ])
        let card = try #require(cards.last)
        #expect(card.windows.first?.compactLabel == "Primary pool")
        #expect(card.windows.first?.accessibilityLabel == "Primary pool usage window")
        #expect(card.remaining == .finite(50))
        #expect(!card.isVisibleInDesktopAssistant)
        #expect(!SharedUsagePresentationPolicy.assistantCards(from: cards)
            .contains(where: { $0.id == "antigravity.cli" }))
    }

    @Test
    func currentReadAdmitsAndRetainedFailureStaysProviderSpecificNeutral() {
        let connector = GoogleAntigravityUsageConnector()
        let fresh = snapshot(
            id: connector.id,
            name: "Google Antigravity",
            label: "Pool",
            capabilities: connector.descriptor.capabilities
        )
        #expect(LocalProviderEligibilityScanner.admission(
            for: fresh,
            descriptor: connector.descriptor
        ).admittedSnapshot != nil)

        let cached = snapshot(
            id: connector.id,
            name: "Google Antigravity",
            label: "Pool",
            state: .ready,
            freshness: .cached,
            failure: .timedOut,
            capabilities: connector.descriptor.capabilities
        )
        #expect(LocalProviderEligibilityScanner.admission(
            for: cached,
            descriptor: connector.descriptor
        ).admittedSnapshot != nil)
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: cached,
            previous: nil,
            language: .english
        )
        #expect(card.freshness == .cached)
        #expect(card.severity == .neutral)
        #expect(card.isRetainingLastValidValue)
    }

    @Test
    func fourProvidersDoNotForceMinimalistAndCreditsRemainDeferred() {
        #expect(DesktopAssistantDensity.automatic.resolvedDensity(
            visibleProviderCount: 4
        ) == .regular)
        #expect(DesktopAssistantDensity.automatic.resolvedDensity(
            visibleProviderCount: 5
        ) == .minimalist)
        let descriptor = GoogleAntigravityUsageConnector().descriptor
        #expect(descriptor.unsupportedFields.contains("credits"))
        #expect(!descriptor.privacyAllowlist.contains("credits"))
    }

    @Test
    func packageHelperIsM6ScopedCommitAwareAndPreservesM5Companions() throws {
        let helper = try source("script/package_uma_m6.sh")
        #expect(helper.contains("$HOME/Developer/UMA-Packages"))
        #expect(helper.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(helper.contains("working-tree-preflight"))
        #expect(helper.contains("commit-exact"))
        #expect(helper.contains("/Library/Developer/CommandLineTools"))
        #expect(helper.contains("MacOSX26.5.sdk"))
        #expect(!helper.contains("/usr/bin/chmod"))
        #expect(helper.contains("$SAFARI_EXTENSION.appex"))
        #expect(helper.contains("BrowserCompanion/Chromium"))
        #expect(helper.contains("UMA-M5-BROWSER-Provenance.plist"))
        #expect(helper.contains("UMA-M6-Provenance.plist"))
        #expect(helper.contains("CreditsStatus"))
        #expect(helper.contains("DEFERRED"))
        #expect(helper.contains("The provider CLI must not be bundled"))
        #expect(!helper.contains("script/package_uma_m5_g2.sh"))
    }

    @Test
    func productionFilesContainNoCreditsCommandCredentialOrBrowserSource() throws {
        let paths = [
            "Sources/CodexUsageUI/Services/AntigravityReadOnlyCLIClient.swift",
            "Sources/CodexUsageUI/Models/AntigravityQuotaSnapshot.swift",
            "Sources/CodexUsageUI/Connectors/GoogleAntigravityUsageConnector.swift",
        ]
        let joined = try paths.map(source).joined(separator: "\n")
        #expect(joined.contains("/usage"))
        for forbidden in [
            "/credits", "API key", "SecItemCopyMatching", "WKWebView",
            "ASWebAuthenticationSession", "Cookie", "Authorization: Bearer",
            "ANTHROPIC_API_KEY", "/Users/",
        ] {
            #expect(!joined.contains(forbidden))
        }
    }

    private func snapshot(
        id: AgentConnectorID,
        name: String,
        label: String? = nil,
        state: AgentConnectorState = .ready,
        freshness: AgentConnectorFreshness = .fresh,
        failure: AgentSafeFailure? = nil,
        capabilities: Set<AgentConnectorCapability> = []
    ) -> AgentUsageSnapshot {
        let observed = Date(timeIntervalSince1970: 1_800_000_000)
        let channel = AgentUsageChannel(
            id: .account,
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "fixture-1",
            scopes: [.account],
            provenance: .providerReported,
            freshness: freshness,
            capturedAt: observed,
            coverageNote: nil,
            rateLimitWindows: [
                AgentRateLimitWindow(
                    id: "pool-a",
                    kind: .other,
                    displayLabel: label,
                    usedPercent: nil,
                    remainingPercent: 50,
                    isUnlimited: false,
                    resetsAt: nil
                ),
            ],
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: failure
        )
        return AgentUsageSnapshot(
            id: id,
            providerName: name,
            state: state,
            capturedAt: observed,
            lastSuccessfulAt: observed,
            freshness: freshness,
            channels: [channel],
            capabilities: capabilities,
            safeFailure: failure
        )
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
