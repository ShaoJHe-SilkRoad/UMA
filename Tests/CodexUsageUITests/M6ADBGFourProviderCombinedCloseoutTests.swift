import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("M6ADBG four-provider combined closeout", .serialized)
struct M6ADBGFourProviderCombinedCloseoutTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func everyProviderSubsetUsesOneOrderedTruthOnBothSurfaces() throws {
        let providers = M6ADBGProvider.allCases
        let all = try providers.map { try snapshot($0) }

        for mask in 0..<(1 << providers.count) {
            let input = all.enumerated().compactMap { index, value in
                mask & (1 << index) == 0 ? nil : value
            }.reversed()
            let main = SharedUsagePresentationPolicy.makeCards(
                snapshots: Array(input),
                previousCards: [],
                language: .english,
                now: now
            )
            let assistant = SharedUsagePresentationPolicy.assistantCards(from: main)
            let expected = providers.enumerated().compactMap { index, provider in
                mask & (1 << index) == 0 ? nil : provider.id
            }

            #expect(main.map(\.id) == expected)
            #expect(assistant.map(\.id) == expected)
            #expect(Set(main.map(\.id)).count == main.count)
            #expect(Set(assistant.map(\.id)).count == assistant.count)
            #expect(
                DesktopAssistantDensity.automatic.resolvedDensity(
                    visibleProviderCount: main.count
                ) == (main.count > 4 ? .minimalist : .regular)
            )
        }
    }

    @Test
    func selectedAntigravityBucketValueResetFreshnessAndSourceStayIdentical() throws {
        for freshness in [
            AgentConnectorFreshness.fresh,
            .cached,
            .stale,
        ] {
            for reverse in [false, true] {
                for missingReset in [false, true] {
                    let source = antigravitySnapshot(
                        freshness: freshness,
                        reverseBuckets: reverse,
                        missingSelectedReset: missingReset
                    )
                    let main = SharedUsagePresentationPolicy.makeCard(
                        snapshot: source,
                        previous: nil,
                        language: .english,
                        now: now
                    )
                    let shared = try #require(
                        SharedUsagePresentationPolicy.assistantCards(from: [main]).first
                    )
                    let assistant = DesktopAssistantCard(
                        shared: shared,
                        language: .english,
                        now: now.addingTimeInterval(300)
                    )
                    let selected = try #require(main.selectedWindow)

                    #expect(main.id == "antigravity.cli")
                    #expect(main.selectedWindowID == "antigravity-secondary")
                    #expect(main.remaining == .finite(42))
                    #expect(shared == main)
                    #expect(assistant.id == main.id)
                    #expect(assistant.usageValue == .finite(42))
                    #expect(assistant.selectedWindowShortLabel == selected.compactLabel)
                    #expect(assistant.selectedWindowResetAt == selected.resetsAt)
                    #expect(assistant.resetText == selected.resetText)
                    #expect(assistant.sourceDescription == main.sourceDescription)
                    #expect(assistant.freshnessState.rawValue == main.freshness.rawValue)
                    #expect(
                        selected.resetsAt == (missingReset
                            ? nil
                            : now.addingTimeInterval(86_400))
                    )
                }
            }
        }
    }

    @Test
    func failureRemovalRecoveryAndObservationOrderNeverCrossBlankProviders() throws {
        let providers = M6ADBGProvider.allCases
        for failedMask in 0..<(1 << providers.count) {
            let input = try providers.enumerated().map { index, provider in
                failedMask & (1 << index) == 0
                    ? try snapshot(provider)
                    : failedSnapshot(provider)
            }.reversed()
            let main = SharedUsagePresentationPolicy.makeCards(
                snapshots: Array(input),
                previousCards: [],
                language: .english,
                now: now
            )
            let assistant = SharedUsagePresentationPolicy.assistantCards(from: main)
            let expected = providers.enumerated().compactMap { index, provider in
                failedMask & (1 << index) == 0 ? provider.id : nil
            }
            #expect(main.map(\.id) == expected)
            #expect(assistant.map(\.id) == expected)
            #expect(main.allSatisfy { $0.connectionStatus == .connected })
        }

        let unavailableMain = SharedUsagePresentationPolicy.makeCards(
            snapshots: providers.map(unavailableSnapshot),
            previousCards: [],
            language: .english,
            now: now
        )
        #expect(unavailableMain.isEmpty)
        #expect(
            SharedUsagePresentationPolicy.assistantCards(from: unavailableMain).isEmpty
        )

        let orderedInputs = try [
            M6ADBGProvider.allCases,
            Array(M6ADBGProvider.allCases.reversed()),
            [.workBuddy, .antigravity, .codex, .claude],
            [.antigravity, .claude, .workBuddy, .codex],
        ].map { order in try order.map { try snapshot($0) } }
        var previous: [SharedUsageCardPresentation] = []
        for input in orderedInputs {
            previous = SharedUsagePresentationPolicy.makeCards(
                snapshots: input,
                previousCards: previous,
                language: .english,
                now: now
            )
            #expect(previous.map(\.id) == providers.map(\.id))
            #expect(
                SharedUsagePresentationPolicy.assistantCards(from: previous)
                    .map(\.id) == providers.map(\.id)
            )
        }

        let withoutAntigravity = previous.filter { $0.id != "antigravity.cli" }
        #expect(
            SharedUsagePresentationPolicy.assistantCards(from: withoutAntigravity)
                .map(\.id) == providers.dropLast().map(\.id)
        )
        #expect(
            SharedUsagePresentationPolicy.assistantCards(from: previous)
                .map(\.id) == providers.map(\.id)
        )
    }

    @Test
    func missingUnlimitedAndWorkBuddyCreditsRemainSemanticallyDistinct() throws {
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: [
                failedSnapshot(.codex),
                try snapshot(.claude, unlimited: true),
                try snapshot(.workBuddy),
                antigravitySnapshot(freshness: .fresh),
            ],
            previousCards: [],
            language: .english,
            now: now
        )
        #expect(!cards.contains { $0.id == M6ADBGProvider.codex.id })
        let claude = try #require(cards.first { $0.id == M6ADBGProvider.claude.id })
        let workBuddy = try #require(
            cards.first { $0.id == M6ADBGProvider.workBuddy.id }
        )
        let antigravity = try #require(
            cards.first { $0.id == M6ADBGProvider.antigravity.id }
        )

        #expect(claude.remaining == .unlimited)
        #expect(claude.remaining != .finite(100))
        #expect(workBuddy.remaining == .unavailable)
        #expect(workBuddy.availability?.displayUnit == .credits)
        #expect(workBuddy.availability?.exactCreditValue == Decimal(string: "2099.47"))
        #expect(antigravity.remaining == .finite(42))
        #expect(antigravity.remaining != .finite(0))
    }

    @MainActor
    @Test
    func combinedAssistantLifecycleKeepsOneNonactivatingPanelAndNoEmptyShell() throws {
        let suite = "M6ADBGFourProviderCombinedCloseoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let position = DesktopAssistantPosition(
            displayIdentifier: nil,
            horizontalFraction: 0.27,
            verticalFraction: 0.73
        )
        DesktopAssistantPreferences(
            isEnabled: true,
            isAlwaysOnTop: true,
            density: .automatic,
            position: position
        ).save(to: defaults)
        var selected: [String] = []
        let controller = DesktopAssistantPanelController(
            defaults: defaults,
            onSelectProvider: { selected.append($0) }
        )
        let keyBefore = NSApp.keyWindow
        let mainBefore = NSApp.mainWindow
        let shared = SharedUsagePresentationPolicy.makeCards(
            snapshots: try M6ADBGProvider.allCases.map { try snapshot($0) },
            previousCards: [],
            language: .english,
            now: now
        )
        let cards = shared.map { DesktopAssistantCard(shared: $0, now: now) }

        controller.update(cards: cards)
        #expect(controller.isVisible)
        #expect(controller.isAlwaysOnTop)
        #expect(NSApp.keyWindow === keyBefore)
        #expect(NSApp.mainWindow === mainBefore)
        for _ in 0..<50 { controller.toggleVisibility() }
        #expect(controller.isVisible)
        controller.setDensity(.minimalist)
        controller.setDensity(.regular)
        controller.handleSelection(providerID: "antigravity.cli")
        #expect(selected == ["antigravity.cli"])
        controller.update(cards: Array(cards.dropLast()))
        controller.update(cards: cards)
        controller.update(cards: [])
        #expect(!controller.isVisible)
        let restored = try #require(
            DesktopAssistantPreferences.load(from: defaults).position
        )
        #expect(abs(restored.horizontalFraction - position.horizontalFraction) < 0.01)
        #expect(abs(restored.verticalFraction - position.verticalFraction) < 0.01)
        controller.tearDown()
    }

    @Test
    func renderingRefreshPackagingAndPrivacyOwnershipStayBounded() throws {
        let assistant = try source(
            "Sources/CodexUsageUI/Views/DesktopAssistantView.swift"
        )
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let controller = try source(
            "Sources/CodexUsageMonitor/App/DesktopAssistantPanelController.swift"
        )
        let connector = try source(
            "Sources/CodexUsageUI/Connectors/GoogleAntigravityUsageConnector.swift"
        )
        let package = try source("script/package_uma_m6.sh")
        let renderer = try source("Sources/PreviewRendererTool/main.swift")
        let ledger = try source("source/UMA M6 Antigravity QA Issue Ledger.md")
        let combinedViews = assistant + panel + controller

        for forbidden in [
            "AntigravityReadOnlyCLIClient", "AntigravityQuotaDecoder",
            "scheduleNextCycle", "readCurrentQuota", "Process(", "Timer(",
        ] {
            #expect(!combinedViews.contains(forbidden))
        }
        #expect(connector.contains("scheduleNextCycle"))
        #expect(connector.contains("activeRead"))
        #expect(connector.contains("minimumRefreshInterval"))
        for required in [
            "m6adbg-preflight", "m6adbg-final",
            "uma-m6adbg-${phase#m6adbg-}-$commit/UMA.app", "commit-exact",
        ] {
            #expect(package.contains(required))
        }
        for required in [
            "--assistant-antigravity", "--assistant-regular",
            "--assistant-minimalist", "--dark", "--english",
            "--reduce-transparency", "--increase-contrast", "--reduce-motion",
        ] {
            #expect(renderer.contains(required))
        }
        for forbidden in [
            "pgrep -f", "pgrep -l", "ps aux", "ps -ef", "printenv", "env |",
        ] {
            #expect(!package.contains(forbidden))
        }
        #expect(ledger.contains("M6A-R-001"))
        #expect(ledger.contains("Safe process-inspection contract"))
    }

    private func snapshot(
        _ provider: M6ADBGProvider,
        unlimited: Bool = false
    ) throws -> AgentUsageSnapshot {
        if provider == .antigravity {
            return antigravitySnapshot(freshness: .fresh)
        }
        let channel: AgentUsageChannel
        if provider == .workBuddy {
            let balance = try CreditBalance(
                validatingDecimalRemaining: Decimal(string: "2099.47")!,
                scope: .buddyAISharedPersonal,
                planTier: .personal,
                observedAt: now,
                provenance: .authenticatedAccountWeb(observedAt: now)
            )
            channel = AgentUsageChannel(
                id: .account,
                sourceTier: .authorizedReadOnlyRemote,
                sourceVersion: "account-web-1",
                scopes: [.account],
                provenance: .providerReported,
                freshness: .fresh,
                capturedAt: now,
                coverageNote: nil,
                rateLimitWindows: [],
                accountMetrics: nil,
                localActivityMetrics: nil,
                safeFailure: nil,
                availability: .credits(balance)
            )
        } else {
            channel = AgentUsageChannel(
                id: .account,
                sourceTier: .officialLocalService,
                sourceVersion: "combined-fixture-1",
                scopes: [.account],
                provenance: .providerReported,
                freshness: .fresh,
                capturedAt: now,
                coverageNote: nil,
                rateLimitWindows: [
                    AgentRateLimitWindow(
                        id: "\(provider.id).seven-day",
                        kind: .sevenDay,
                        usedPercent: unlimited ? nil : 25,
                        isUnlimited: unlimited,
                        resetsAt: unlimited ? nil : now.addingTimeInterval(7_200)
                    ),
                ],
                accountMetrics: nil,
                localActivityMetrics: nil,
                safeFailure: nil
            )
        }
        return AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: provider.id)!,
            providerName: provider.name,
            state: .ready,
            capturedAt: now,
            lastSuccessfulAt: now,
            freshness: .fresh,
            channels: [channel],
            capabilities: [],
            safeFailure: nil
        )
    }

    private func antigravitySnapshot(
        freshness: AgentConnectorFreshness,
        reverseBuckets: Bool = false,
        missingSelectedReset: Bool = false
    ) -> AgentUsageSnapshot {
        var windows = [
            AgentRateLimitWindow(
                id: "antigravity-primary",
                kind: .other,
                displayLabel: "Primary",
                usedPercent: nil,
                remainingPercent: 58,
                isUnlimited: false,
                resetsAt: now.addingTimeInterval(7_200)
            ),
            AgentRateLimitWindow(
                id: "antigravity-secondary",
                kind: .other,
                displayLabel: "Secondary",
                usedPercent: nil,
                remainingPercent: 42,
                isUnlimited: false,
                resetsAt: missingSelectedReset
                    ? nil
                    : now.addingTimeInterval(86_400)
            ),
        ]
        if reverseBuckets { windows.reverse() }
        let channel = AgentUsageChannel(
            id: .account,
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "agy-1.1.11",
            scopes: [.account],
            provenance: .providerReported,
            freshness: freshness,
            capturedAt: now,
            coverageNote: nil,
            rateLimitWindows: windows,
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: freshness == .fresh ? nil : .timedOut
        )
        return AgentUsageSnapshot(
            id: GoogleAntigravityUsageConnector.connectorID,
            providerName: "Google Antigravity",
            state: freshness == .stale ? .stale : .ready,
            capturedAt: now,
            lastSuccessfulAt: now,
            freshness: freshness,
            channels: [channel],
            capabilities: GoogleAntigravityUsageConnector().descriptor.capabilities,
            safeFailure: freshness == .fresh ? nil : .timedOut
        )
    }

    private func failedSnapshot(_ provider: M6ADBGProvider) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: provider.id)!,
            providerName: provider.name,
            state: .failed,
            capturedAt: now,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: provider == .antigravity
                ? GoogleAntigravityUsageConnector().descriptor.capabilities
                : [],
            safeFailure: .unavailable
        )
    }

    private func unavailableSnapshot(_ provider: M6ADBGProvider) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: provider.id)!,
            providerName: provider.name,
            state: .inactive,
            capturedAt: now,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: provider == .antigravity
                ? GoogleAntigravityUsageConnector().descriptor.capabilities
                : [],
            safeFailure: .unavailable
        )
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(path),
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

private enum M6ADBGProvider: CaseIterable {
    case codex
    case claude
    case workBuddy
    case antigravity

    var id: String {
        switch self {
        case .codex: "codex.local"
        case .claude: "claude.browserSync"
        case .workBuddy: "workbuddy.accountWebCredits"
        case .antigravity: "antigravity.cli"
        }
    }

    var name: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .workBuddy: "WorkBuddy"
        case .antigravity: "Google Antigravity"
        }
    }
}
