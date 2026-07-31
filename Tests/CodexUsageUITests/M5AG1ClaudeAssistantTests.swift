import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("M5A-G1 Claude shared Desktop Assistant")
struct M5AG1ClaudeAssistantTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func productionDescriptorAdmitsClaudeAndEveryProviderCountUsesStableOrder() {
        #expect(
            !ClaudeCodeUsageConnector.production().descriptor.capabilities
                .contains(.hiddenFromDesktopAssistant)
        )
        let codex = card(id: "codex.local", provider: "Codex")
        let claude = card(id: "claude.statusLine", provider: "Claude Code")
        let workBuddy = card(
            id: "workbuddy.accountWebCredits",
            provider: "WorkBuddy"
        )
        let cases: [([SharedUsageCardPresentation], [String])] = [
            ([], []),
            ([codex], ["codex.local"]),
            ([claude], ["claude.statusLine"]),
            ([workBuddy], ["workbuddy.accountWebCredits"]),
            ([claude, codex], ["codex.local", "claude.statusLine"]),
            (
                [workBuddy, claude],
                ["claude.statusLine", "workbuddy.accountWebCredits"]
            ),
            (
                [workBuddy, codex],
                ["codex.local", "workbuddy.accountWebCredits"]
            ),
            (
                [workBuddy, claude, codex],
                [
                    "codex.local",
                    "claude.statusLine",
                    "workbuddy.accountWebCredits",
                ]
            ),
        ]
        for (input, expected) in cases {
            #expect(
                SharedUsagePresentationPolicy.assistantCards(from: input)
                    .map(\.id) == expected
            )
        }
    }

    @Test
    func freshCachedStaleWaitingFailedRepairAndUnavailableRemainHonest() {
        let cases: [(
            SharedConnectionStatus,
            SharedUsageFreshness,
            SharedRemainingValue,
            Bool,
            DesktopAssistantFreshnessState
        )] = [
            (.connected, .fresh, .finite(44), false, .fresh),
            (.connected, .cached, .finite(44), true, .cached),
            (.stale, .stale, .finite(44), true, .stale),
            (.transitional, .unavailable, .unavailable, false, .waiting),
            (.failed, .unavailable, .unavailable, false, .failed),
            (.failed, .unavailable, .unavailable, false, .failed),
            (.unavailable, .unavailable, .unavailable, false, .unavailable),
        ]
        for (connection, freshness, remaining, retained, expected) in cases {
            let shared = card(
                id: "claude.statusLine",
                provider: "Claude Code",
                connection: connection,
                freshness: freshness,
                remaining: remaining,
                retaining: retained
            )
            let assistant = DesktopAssistantCard(
                shared: shared,
                language: .english,
                now: now.addingTimeInterval(300)
            )
            #expect(assistant.freshnessState == expected)
            if remaining == .unavailable {
                #expect(assistant.usageValue == .unavailable)
                #expect(assistant.tintFraction == nil)
            } else {
                #expect(assistant.usageValue == .finite(44))
            }
        }
    }

    @Test
    func claudeParityRetainsSharedIDValueWindowResetSourceFreshnessAndAge() {
        let reset = now.addingTimeInterval(7_200)
        let shared = card(
            id: "claude.statusLine",
            provider: "Claude Code",
            freshness: .cached,
            remaining: .finite(38),
            retaining: true,
            reset: reset
        )
        let assistant = DesktopAssistantCard(
            shared: shared,
            language: .english,
            now: now.addingTimeInterval(300)
        )

        #expect(assistant.id == shared.id)
        #expect(assistant.usageValue == .finite(38))
        #expect(
            assistant.selectedWindowShortLabel
                == shared.selectedWindow?.compactLabel
        )
        #expect(
            assistant.selectedWindowResetAt
                == shared.selectedWindow?.resetsAt
        )
        #expect(assistant.resetText == shared.selectedWindow?.resetText)
        #expect(assistant.sourceDescription == shared.sourceDescription)
        #expect(assistant.freshnessState == .cached)
        #expect(assistant.observationAgeText == "Updated 5 min ago")
        #expect(assistant.detailText == "7D · 2h · Cached")
        for required in [
            "Claude Code",
            "Cached",
            "seven-day window",
            "38 percent remaining",
            "Resets in 2 hr",
            "Official local status line",
            "Updated 5 min ago",
        ] {
            #expect(assistant.toolTip.contains(required))
        }
        #expect(!assistant.toolTip.contains("Fresh"))
    }

    @Test
    func minimalistUsesDistinctGenericProviderMarkWithoutAddingVisibleFields() {
        let codex = DesktopAssistantCard(
            shared: card(id: "codex.local", provider: "Codex"),
            now: now
        )
        let claude = DesktopAssistantCard(
            shared: card(id: "claude.statusLine", provider: "Claude Code"),
            now: now
        )
        #expect(codex.providerMarkText == "C")
        #expect(claude.providerMarkText == "CC")
        #expect(
            DesktopAssistantContentContract.visibleFields(for: .minimalist)
                == [.providerConnectionMark, .percentage]
        )
        #expect(DesktopAssistantMetrics.minimalistReservedWindowWidth == 0)
        #expect(DesktopAssistantMetrics.minimalistHeight == 30)
        #expect(DesktopAssistantMetrics.regularHeight == 60)
    }

    @Test
    func englishAndChineseAccessibilityKeepStateSourceResetAndAge() {
        let shared = card(
            id: "claude.statusLine",
            provider: "Claude Code",
            freshness: .stale,
            remaining: .finite(9),
            retaining: true
        )
        let english = DesktopAssistantCard(
            shared: shared,
            language: .english,
            now: now.addingTimeInterval(3_600)
        )
        let chineseShared = card(
            id: "claude.statusLine",
            provider: "Claude Code",
            freshness: .stale,
            remaining: .finite(9),
            retaining: true,
            sourceDescription: "官方本地状态栏"
        )
        let chinese = DesktopAssistantCard(
            shared: chineseShared,
            language: .simplifiedChinese,
            now: now.addingTimeInterval(3_600)
        )
        for required in ["Stale", "9 percent remaining", "Official local status line"] {
            #expect(english.accessibilityLabel.contains(required))
        }
        for required in ["较早数据", "剩余 9%", "官方本地状态栏", "1 小时前更新"] {
            #expect(chinese.accessibilityLabel.contains(required))
        }
        #expect(!english.accessibilityLabel.contains("Fresh"))
        #expect(!chinese.accessibilityLabel.contains("新鲜"))
    }

    @Test
    func windowMatrixPreservesFiveHourSevenDayBothAndNoValidWindow() {
        let fiveHour = window(
            id: "claude-five-hour",
            kind: .fiveHour,
            label: "5H",
            remaining: 73,
            reset: now.addingTimeInterval(3_600)
        )
        let sevenDay = window(
            id: "claude-seven-day",
            kind: .sevenDay,
            label: "7D",
            remaining: 42,
            reset: now.addingTimeInterval(86_400)
        )
        let cases: [([SharedUsageWindowPresentation], String?, DesktopAssistantUsageValue)] = [
            ([fiveHour], fiveHour.id, .finite(73)),
            ([sevenDay], sevenDay.id, .finite(42)),
            ([fiveHour, sevenDay], sevenDay.id, .finite(42)),
            ([sevenDay], sevenDay.id, .finite(42)),
            ([], nil, .unavailable),
        ]
        for (windows, selectedID, expected) in cases {
            let shared = SharedUsageCardPresentation(
                id: "claude.statusLine",
                providerName: "Claude Code",
                connectionStatus: windows.isEmpty ? .transitional : .connected,
                freshness: windows.isEmpty ? .unavailable : .fresh,
                windows: windows,
                selectedWindowID: selectedID,
                remaining: selectedID.flatMap {
                    id in windows.first(where: { $0.id == id })?.remaining
                } ?? .unavailable,
                sourceDescription: "Official local status line",
                severity: .normal,
                capturedAt: now
            )
            let assistant = DesktopAssistantCard(
                shared: shared,
                now: now
            )
            #expect(assistant.usageValue == expected)
            #expect(assistant.selectedWindowResetAt == shared.selectedWindow?.resetsAt)
        }
    }

    @Test
    func crossProviderFailuresNeverReorderOrMutateHealthyRows() {
        let providers = [
            card(id: "codex.local", provider: "Codex"),
            card(id: "claude.statusLine", provider: "Claude Code"),
            card(id: "workbuddy.manualAvailability", provider: "WorkBuddy"),
        ]
        for failedID in providers.map(\.id) {
            let transitioned = providers.map { value in
                value.id == failedID
                    ? card(
                        id: value.id,
                        provider: value.providerName,
                        connection: .failed,
                        freshness: .unavailable,
                        remaining: .unavailable
                    )
                    : value
            }
            let ordered = SharedUsagePresentationPolicy.assistantCards(
                from: transitioned
            )
            #expect(
                ordered.map(\.id) == [
                    "codex.local",
                    "claude.statusLine",
                    "workbuddy.manualAvailability",
                ]
            )
            #expect(
                ordered.filter { $0.id != failedID }
                    .allSatisfy { $0.remaining == .finite(44) }
            )
        }
    }

    @MainActor
    @Test
    func onePanelHandlesOneHundredCyclesAndRoutesStableClaudeID() throws {
        let suite = "M5AG1ClaudeAssistantTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        DesktopAssistantPreferences(
            isEnabled: true,
            isAlwaysOnTop: true,
            density: .automatic,
            position: nil
        ).save(to: defaults)
        var selections: [String] = []
        let controller = DesktopAssistantPanelController(
            defaults: defaults,
            onSelectProvider: { selections.append($0) }
        )
        let cards = [
            DesktopAssistantCard(
                shared: card(id: "codex.local", provider: "Codex"),
                now: now
            ),
            DesktopAssistantCard(
                shared: card(id: "claude.statusLine", provider: "Claude Code"),
                now: now
            ),
            DesktopAssistantCard(
                shared: card(
                    id: "workbuddy.manualAvailability",
                    provider: "WorkBuddy"
                ),
                now: now
            ),
        ]
        controller.update(cards: cards)
        #expect(controller.isVisible)
        for _ in 0..<100 {
            controller.toggleVisibility()
        }
        #expect(controller.isVisible)
        #expect(controller.isAlwaysOnTop)
        #expect(controller.density == .automatic)
        controller.handleSelection(providerID: "claude.statusLine")
        #expect(selections == ["claude.statusLine"])
        controller.update(cards: [])
        #expect(!controller.isVisible)
        controller.tearDown()
    }

    @Test
    func burstUpdatesRemainUniqueOrderedAndMapUnderTarget() {
        let start = Date()
        var finalIDs: [String] = []
        for value in 0..<2_000 {
            let cards = [
                card(
                    id: "workbuddy.manualAvailability",
                    provider: "WorkBuddy",
                    remaining: .finite(Double(value % 101))
                ),
                card(
                    id: "claude.statusLine",
                    provider: "Claude Code",
                    remaining: .finite(Double(value % 101))
                ),
                card(
                    id: "codex.local",
                    provider: "Codex",
                    remaining: .finite(Double(value % 101))
                ),
            ]
            finalIDs = SharedUsagePresentationPolicy.assistantCards(from: cards)
                .map(\.id)
        }
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(
            finalIDs == [
                "codex.local",
                "claude.statusLine",
                "workbuddy.manualAvailability",
            ]
        )
        #expect(Set(finalIDs).count == finalIDs.count)
    }

    @Test
    func assistantSourceOwnsNoProviderTransportOrSelectionAlgorithm() throws {
        let assistant = try source(
            "Sources/CodexUsageUI/Views/DesktopAssistantView.swift"
        )
        let controller = try source(
            "Sources/CodexUsageMonitor/App/DesktopAssistantPanelController.swift"
        )
        let combined = assistant + controller
        for forbidden in [
            "ClaudeCodeUsageConnector",
            "ClaudeStatusLineSocket",
            "ClaudeStatusLineConfigurationManager",
            "AgentConnectorRegistry",
            "selectedWindowID(",
            "100 -",
            "Timer(",
            "Process(",
            "snapshotStore",
            "statusLine",
        ] {
            #expect(!combined.contains(forbidden))
        }
        #expect(controller.contains("self.cards = cards"))
        #expect(controller.contains("onSelectProvider?(providerID)"))
    }

    @Test
    func rendererPackageAndQALedgerCarryM5AContracts() throws {
        let renderer = try source("Sources/PreviewRendererTool/main.swift")
        let package = try source("script/package_uma_m5_g2.sh")
        let ledger = try source("source/UMA M5 Claude QA Issue Ledger.md")
        for required in [
            "--assistant-claude",
            "SharedUsagePresentationPolicy.assistantCards",
            "isVisibleInDesktopAssistant: true",
        ] {
            #expect(renderer.contains(required))
        }
        for required in [
            "m5a-final",
            "uma-m5a-final-$commit",
            "UMA-M5A-Provenance.plist",
            "CLAUDE-SHARED-ASSISTANT-ACCEPTED",
        ] {
            #expect(package.contains(required))
        }
        #expect(ledger.contains("## M5A-G1 issue ledger"))
        #expect(ledger.contains("M5A-001"))
        #expect(ledger.contains("Physical VoiceOver"))
    }

    private func card(
        id: String,
        provider: String,
        connection: SharedConnectionStatus = .connected,
        freshness: SharedUsageFreshness = .fresh,
        remaining: SharedRemainingValue = .finite(44),
        retaining: Bool = false,
        reset: Date? = nil,
        sourceDescription: String? = nil
    ) -> SharedUsageCardPresentation {
        let reset = reset ?? now.addingTimeInterval(7_200)
        let selected = remaining == .unavailable
            ? nil
            : window(
                id: "\(id).seven-day",
                kind: .sevenDay,
                label: "7D",
                remaining: remaining.finitePercent ?? 44,
                reset: reset
            )
        return SharedUsageCardPresentation(
            id: id,
            providerName: provider,
            connectionStatus: connection,
            freshness: freshness,
            windows: selected.map { [$0] } ?? [],
            selectedWindowID: selected?.id,
            remaining: remaining,
            sourceDescription: id == "claude.statusLine"
                ? (sourceDescription ?? "Official local status line")
                : nil,
            isVisibleInDesktopAssistant: true,
            severity: SharedUsagePresentationPolicy.severity(for: remaining),
            isRetainingLastValidValue: retaining,
            capturedAt: now
        )
    }

    private func window(
        id: String,
        kind: SharedUsageWindowKind,
        label: String,
        remaining: Double,
        reset: Date
    ) -> SharedUsageWindowPresentation {
        SharedUsageWindowPresentation(
            id: id,
            kind: kind,
            compactLabel: label,
            accessibilityLabel: kind == .fiveHour
                ? "five-hour window"
                : "seven-day window",
            remaining: .finite(remaining),
            resetsAt: reset,
            resetText: "Resets in 2 hr"
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
