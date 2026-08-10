import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("M6A-G1 Antigravity shared Desktop Assistant")
struct M6AG1AntigravityAssistantTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func productionDescriptorAdmitsAssistantAndEveryProviderSubsetStaysOrdered() {
        #expect(
            !GoogleAntigravityUsageConnector().descriptor.capabilities
                .contains(.hiddenFromDesktopAssistant)
        )
        let providers = M6AProvider.allCases
        for mask in 0..<(1 << providers.count) {
            let input = providers.enumerated().compactMap { index, provider in
                mask & (1 << index) == 0 ? nil : card(provider)
            }.reversed()
            let result = SharedUsagePresentationPolicy.assistantCards(
                from: Array(input)
            )
            let expected = providers.enumerated().compactMap { index, provider in
                mask & (1 << index) == 0 ? nil : provider.id
            }
            #expect(result.map(\.id) == expected)
            #expect(Set(result.map(\.id)).count == result.count)
        }
    }

    @Test
    func antigravityAdapterUsesTheSharedSelectedWindowWithoutRenormalizing() throws {
        let shared = card(
            .antigravity,
            freshness: .cached,
            remaining: 58,
            retaining: true,
            includeSecondWindow: true
        )
        let selected = try #require(shared.selectedWindow)
        let assistant = DesktopAssistantCard(
            shared: shared,
            language: .english,
            now: now.addingTimeInterval(300)
        )

        #expect(shared.selectedWindowID == "antigravity.cli.primary")
        #expect(selected.remaining == .finite(58))
        #expect(assistant.id == shared.id)
        #expect(assistant.providerName == shared.providerName)
        #expect(assistant.usageValue == .finite(58))
        #expect(assistant.tintFraction == 0.58)
        #expect(assistant.selectedWindowShortLabel == selected.compactLabel)
        #expect(assistant.selectedWindowAccessibilityLabel == selected.accessibilityLabel)
        #expect(assistant.selectedWindowResetAt == selected.resetsAt)
        #expect(assistant.resetText == selected.resetText)
        #expect(assistant.sourceDescription == shared.sourceDescription)
        #expect(assistant.freshnessState == .cached)
        #expect(assistant.severity == .neutral)
        #expect(assistant.providerMarkText == "GA")
        #expect(assistant.usageText(for: .regular) == "58%")
        #expect(assistant.usageText(for: .minimalist) == "58%")
    }

    @Test
    func productionSharedCardAddsLocalizedSourceWithoutChangingSourceOwnership() throws {
        let snapshot = antigravitySnapshot(
            freshness: .fresh,
            remaining: 58,
            includeSecondWindow: true
        )
        let english = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .english,
            now: now
        )
        let chinese = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .simplifiedChinese,
            now: now
        )

        #expect(english.sourceDescription == "Official Antigravity CLI · Read-only Usage")
        #expect(chinese.sourceDescription == "Antigravity 官方 CLI · 只读用量")
        #expect(english.selectedWindowID == chinese.selectedWindowID)
        #expect(english.remaining == chinese.remaining)
        #expect(english.isVisibleInDesktopAssistant)
        #expect(chinese.isVisibleInDesktopAssistant)
        let englishAssistant = DesktopAssistantCard(
            shared: english,
            language: .english,
            now: now.addingTimeInterval(300)
        )
        let chineseAssistant = DesktopAssistantCard(
            shared: chinese,
            language: .simplifiedChinese,
            now: now.addingTimeInterval(300)
        )
        for required in [
            "Google Antigravity", "Fresh", "Secondary usage window",
            "42 percent remaining", "Official Antigravity CLI · Read-only Usage",
        ] {
            #expect(englishAssistant.accessibilityLabel.contains(required))
        }
        for required in [
            "Google Antigravity", "新鲜", "Secondary 额度窗口", "剩余 42%",
            "Antigravity 官方 CLI · 只读用量",
        ] {
            #expect(chineseAssistant.accessibilityLabel.contains(required))
        }
    }

    @Test
    func freshCachedStaleWaitingFailedAndUnavailableRemainHonest() {
        let cases: [(
            SharedConnectionStatus,
            SharedUsageFreshness,
            SharedRemainingValue,
            Bool,
            DesktopAssistantFreshnessState,
            DesktopAssistantConnectionState
        )] = [
            (.connected, .fresh, .finite(58), false, .fresh, .connected),
            (.connected, .cached, .finite(58), true, .cached, .connected),
            (.stale, .stale, .finite(58), true, .stale, .reconnecting),
            (.transitional, .unavailable, .unavailable, false, .waiting, .reconnecting),
            (.failed, .unavailable, .unavailable, false, .failed, .failed),
            (.unavailable, .unavailable, .unavailable, false, .unavailable, .unavailable),
            (.disconnected, .unavailable, .unavailable, false, .unavailable, .disconnected),
        ]
        for (connection, freshness, remaining, retained, state, connectionState) in cases {
            let shared = card(
                .antigravity,
                connection: connection,
                freshness: freshness,
                remainingValue: remaining,
                retaining: retained
            )
            let assistant = DesktopAssistantCard(
                shared: shared,
                language: .english,
                now: now.addingTimeInterval(300)
            )
            #expect(assistant.freshnessState == state)
            #expect(assistant.connectionState == connectionState)
            if remaining == .unavailable {
                #expect(assistant.usageValue == .unavailable)
                #expect(assistant.tintFraction == nil)
                #expect(assistant.usageValue != .finite(0))
            } else {
                #expect(assistant.usageValue == .finite(58))
            }
        }
    }

    @Test
    func multipleBucketsReorderMissingResetAndReappearPreserveSharedTruth() throws {
        let snapshots = [
            antigravitySnapshot(
                freshness: .fresh,
                remaining: 76,
                includeSecondWindow: true,
                reverseWindows: false
            ),
            antigravitySnapshot(
                freshness: .fresh,
                remaining: 76,
                includeSecondWindow: true,
                reverseWindows: true,
                missingReset: true
            ),
        ]
        var previous: SharedUsageCardPresentation?
        for snapshot in snapshots {
            let shared = SharedUsagePresentationPolicy.makeCard(
                snapshot: snapshot,
                previous: previous,
                language: .english,
                now: now
            )
            #expect(shared.selectedWindowID == "antigravity-secondary")
            #expect(shared.remaining == .finite(42))
            previous = shared
        }
        let reappeared = try #require(previous)
        let assistant = DesktopAssistantCard(shared: reappeared, now: now)
        #expect(assistant.usageValue == .finite(42))
        #expect(assistant.selectedWindowShortLabel == "Secondary")
        #expect(assistant.selectedWindowResetAt == nil)
        #expect(assistant.resetText == "Reset time unavailable")
    }

    @Test
    func antigravityFailureOrRemovalNeverBlanksHealthyProviders() {
        let healthy = M6AProvider.allCases.map { card($0) }
        let failed = healthy.map { value in
            value.id == M6AProvider.antigravity.id
                ? card(
                    .antigravity,
                    connection: .failed,
                    freshness: .unavailable,
                    remainingValue: .unavailable
                )
                : value
        }
        let failedCards = SharedUsagePresentationPolicy.assistantCards(from: failed)
        #expect(failedCards.map(\.id) == M6AProvider.allCases.map(\.id))
        #expect(
            failedCards.filter { $0.id != M6AProvider.antigravity.id }
                .allSatisfy { $0.remaining != .unavailable }
        )

        let removed = SharedUsagePresentationPolicy.assistantCards(
            from: healthy.filter { $0.id != M6AProvider.antigravity.id }
        )
        #expect(removed.map(\.id) == [
            M6AProvider.codex.id,
            M6AProvider.claude.id,
            M6AProvider.workBuddy.id,
        ])
        let reappeared = SharedUsagePresentationPolicy.assistantCards(from: healthy)
        #expect(reappeared.map(\.id) == M6AProvider.allCases.map(\.id))
    }

    @Test
    func fourProvidersRemainRegularAndMinimalistShowsOnlyMarkAndRemaining() {
        #expect(
            DesktopAssistantDensity.automatic.resolvedDensity(
                visibleProviderCount: 4
            ) == .regular
        )
        #expect(
            DesktopAssistantDensity.automatic.resolvedDensity(
                visibleProviderCount: 5
            ) == .minimalist
        )
        #expect(
            DesktopAssistantContentContract.visibleFields(for: .regular)
                .contains(.selectedWindow)
        )
        #expect(
            DesktopAssistantContentContract.visibleFields(for: .minimalist)
                == [.providerConnectionMark, .percentage]
        )
        let assistant = DesktopAssistantCard(shared: card(.antigravity), now: now)
        #expect(assistant.providerMarkText == "GA")
        #expect(assistant.usageText(for: .regular) == "58%")
        #expect(assistant.usageText(for: .minimalist) == "58%")
        #expect(DesktopAssistantMetrics.minimalistReservedWindowWidth == 0)
    }

    @MainActor
    @Test
    func onePanelRoutesStableAntigravityIDAndSurvivesLifecycleTransitions() throws {
        let suite = "M6AG1AntigravityAssistantTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let position = DesktopAssistantPosition(
            displayIdentifier: nil,
            horizontalFraction: 0.3,
            verticalFraction: 0.7
        )
        DesktopAssistantPreferences(
            isEnabled: true,
            isAlwaysOnTop: true,
            density: .automatic,
            position: position
        ).save(to: defaults)
        var selections: [String] = []
        let controller = DesktopAssistantPanelController(
            defaults: defaults,
            onSelectProvider: { selections.append($0) }
        )
        let keyWindowBeforePresentation = NSApp.keyWindow
        let mainWindowBeforePresentation = NSApp.mainWindow
        let fourCards = M6AProvider.allCases.map {
            DesktopAssistantCard(shared: card($0), now: now)
        }
        controller.update(cards: fourCards)
        #expect(controller.isVisible)
        #expect(NSApp.keyWindow === keyWindowBeforePresentation)
        #expect(NSApp.mainWindow === mainWindowBeforePresentation)
        #expect(controller.isAlwaysOnTop)
        #expect(controller.density == .automatic)
        for _ in 0..<40 {
            controller.toggleVisibility()
        }
        #expect(controller.isVisible)
        #expect(NSApp.keyWindow === keyWindowBeforePresentation)
        #expect(NSApp.mainWindow === mainWindowBeforePresentation)
        controller.setDensity(.minimalist)
        controller.setDensity(.regular)
        controller.handleSelection(providerID: M6AProvider.antigravity.id)
        #expect(selections == [M6AProvider.antigravity.id])
        controller.update(cards: Array(fourCards.dropLast()))
        #expect(controller.isVisible)
        controller.update(cards: fourCards)
        #expect(controller.isVisible)
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
    func panelIsNonactivatingAndObserverOwnershipIsSingularAndSymmetric() throws {
        let controller = try source(
            "Sources/CodexUsageMonitor/App/DesktopAssistantPanelController.swift"
        )
        for required in [
            "override var canBecomeKey: Bool { false }",
            "override var canBecomeMain: Bool { false }",
            "styleMask: [.borderless, .nonactivatingPanel]",
            "panel.becomesKeyOnlyIfNeeded = false",
            "panel.orderFrontRegardless()",
        ] {
            #expect(controller.contains(required))
        }
        for forbidden in [
            "makeKeyAndOrderFront",
            "makeMain()",
            "NSApp.activate",
        ] {
            #expect(!controller.contains(forbidden))
        }

        #expect(occurrences(of: "installWindowObservers()", in: controller) == 2)
        #expect(occurrences(of: "installDefaultsObserver()", in: controller) == 2)
        #expect(
            occurrences(
                of: "NotificationCenter.default.addObserver(",
                in: controller
            ) == 3
        )
        #expect(
            occurrences(
                of: "NotificationCenter.default.removeObserver(",
                in: controller
            ) == 3
        )
        for observer in ["moveObserver", "screenObserver", "defaultsObserver"] {
            #expect(
                occurrences(
                    of: "NotificationCenter.default.removeObserver(\(observer))",
                    in: controller
                ) == 1
            )
            #expect(
                occurrences(of: "self.\(observer) = nil", in: controller) == 1
            )
        }
    }

    @Test
    func assistantCodeOwnsNoAntigravitySourceOrSelectionMechanism() throws {
        let assistant = try source("Sources/CodexUsageUI/Views/DesktopAssistantView.swift")
        let controller = try source(
            "Sources/CodexUsageMonitor/App/DesktopAssistantPanelController.swift"
        )
        let status = try source("Sources/CodexUsageMonitor/App/StatusBarController.swift")
        let combined = assistant + controller
        for forbidden in [
            "GoogleAntigravityUsageConnector",
            "AntigravityReadOnlyCLIClient",
            "AntigravityQuotaDecoder",
            "AgentConnectorRegistry",
            "URLSession",
            "Process(",
            "Timer(",
            "scheduleNextCycle",
            "readCurrentQuota",
            "selectedWindowID(",
            "snapshotStore",
        ] {
            #expect(!combined.contains(forbidden))
        }
        #expect(status.contains("store.assistantPresentationCards.map"))
        #expect(controller.contains("self.cards = cards"))
        #expect(controller.contains("onSelectProvider?(providerID)"))
        #expect(controller.contains("positionSaveTask"))
    }

    @Test
    func rendererPackageAndLedgerCarryM6AContract() throws {
        let renderer = try source("Sources/PreviewRendererTool/main.swift")
        let package = try source("script/package_uma_m6.sh")
        let ledger = try source("source/UMA M6 Antigravity QA Issue Ledger.md")
        for required in [
            "--assistant-antigravity",
            "--antigravity-missing-reset",
            "--antigravity-select-secondary",
            "isVisibleInDesktopAssistant: true",
        ] {
            #expect(renderer.contains(required))
        }
        for required in [
            "m6a-preflight", "m6a-final",
            "uma-m6a-${phase#m6a-}-$commit/UMA.app", "commit-exact",
        ] {
            #expect(package.contains(required))
        }
        #expect(ledger.contains("## M6A-G1 Desktop Assistant issue ledger"))
        #expect(ledger.contains("M6A-001"))
        #expect(ledger.contains("CREDITS DEFER"))
    }

    @Test
    func m6ProcessInspectionIsBoundedAndM6ADBGConsumesTheSafeContract() throws {
        let package = try source("script/package_uma_m6.sh")
        let liveHarness = try source(
            "Tests/CodexUsageUITests/M6G3AntigravityLiveAcceptanceTests.swift"
        )
        let debugAcceptance = try source(
            "source/UMA M6DBG Four-Provider Debug Acceptance.md"
        )
        let ledger = try source("source/UMA M6 Antigravity QA Issue Ledger.md")
        let repositoryOwnedInspection = package + liveHarness
        let normalizedDebugAcceptance = debugAcceptance
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalizedLedger = ledger
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        for forbidden in [
            "pgrep -f",
            "pgrep -l",
            "ps aux",
            "ps -ef",
            "printenv",
            "env |",
        ] {
            #expect(!repositoryOwnedInspection.contains(forbidden))
        }
        for required in [
            "task-owned executable path or exact executable name",
            "exact PID",
            "process count",
            "parent/child ownership",
            "bounded resource counters",
            "exit/absence classification",
            "fails closed",
        ] {
            #expect(normalizedDebugAcceptance.contains(required))
            #expect(normalizedLedger.contains(required))
        }
        #expect(ledger.contains("M6A-R-001"))
        #expect(ledger.contains("Ad-hoc DEV command"))
        #expect(ledger.contains("Persistence result | NONE"))
    }

    private func card(
        _ provider: M6AProvider,
        connection: SharedConnectionStatus = .connected,
        freshness: SharedUsageFreshness = .fresh,
        remaining: Double = 58,
        remainingValue: SharedRemainingValue? = nil,
        retaining: Bool = false,
        includeSecondWindow: Bool = false
    ) -> SharedUsageCardPresentation {
        let value = remainingValue ?? .finite(remaining)
        let primary = SharedUsageWindowPresentation(
            id: "\(provider.id).primary",
            kind: provider == .antigravity ? .other : .sevenDay,
            compactLabel: provider == .antigravity ? "Primary" : "7D",
            accessibilityLabel: provider == .antigravity
                ? "Primary usage window"
                : "seven-day window",
            remaining: value,
            resetsAt: value == .unavailable ? nil : now.addingTimeInterval(7_200),
            resetText: value == .unavailable ? "Reset unavailable" : "Resets in 2 hr"
        )
        var windows = value == .unavailable ? [] : [primary]
        if includeSecondWindow {
            windows.append(
                SharedUsageWindowPresentation(
                    id: "\(provider.id).secondary",
                    kind: .other,
                    compactLabel: "Secondary",
                    accessibilityLabel: "Secondary usage window",
                    remaining: .finite(76),
                    resetsAt: now.addingTimeInterval(86_400),
                    resetText: "Resets in 1 day"
                )
            )
        }
        return SharedUsageCardPresentation(
            id: provider.id,
            providerName: provider.name,
            connectionStatus: connection,
            freshness: freshness,
            windows: windows,
            selectedWindowID: windows.first?.id,
            remaining: value,
            sourceDescription: provider == .antigravity
                ? "Official Antigravity CLI · Read-only Usage"
                : nil,
            isVisibleInDesktopAssistant: true,
            severity: retaining
                ? .neutral
                : SharedUsagePresentationPolicy.severity(for: value),
            isRetainingLastValidValue: retaining,
            capturedAt: now
        )
    }

    private func antigravitySnapshot(
        freshness: AgentConnectorFreshness,
        remaining: Double,
        includeSecondWindow: Bool,
        reverseWindows: Bool = false,
        missingReset: Bool = false
    ) -> AgentUsageSnapshot {
        var windows = [
            AgentRateLimitWindow(
                id: "antigravity-primary",
                kind: .other,
                displayLabel: "Primary",
                usedPercent: nil,
                remainingPercent: remaining,
                isUnlimited: false,
                resetsAt: now.addingTimeInterval(7_200)
            ),
        ]
        if includeSecondWindow {
            windows.append(
                AgentRateLimitWindow(
                    id: "antigravity-secondary",
                    kind: .other,
                    displayLabel: "Secondary",
                    usedPercent: nil,
                    remainingPercent: 42,
                    isUnlimited: false,
                    resetsAt: missingReset ? nil : now.addingTimeInterval(86_400)
                )
            )
        }
        if reverseWindows { windows.reverse() }
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
            safeFailure: nil
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
            safeFailure: nil
        )
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func occurrences(of needle: String, in value: String) -> Int {
        value.components(separatedBy: needle).count - 1
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum M6AProvider: CaseIterable, Equatable {
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
