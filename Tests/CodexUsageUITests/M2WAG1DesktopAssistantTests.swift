import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("M2WA-G1 WorkBuddy Desktop Assistant")
struct M2WAG1DesktopAssistantTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func providerVisibilityOrderAndDensityUseStableIdentity() throws {
        let codex = codexCard()
        let future = placeholderCard(id: "claude.code", providerName: "Future provider")
        let workBuddy = try workBuddyCard(remaining: 500, used: 0, total: 500)
        let hidden = SharedUsageCardPresentation(
            id: "hidden.provider",
            providerName: "Hidden",
            connectionStatus: .unavailable,
            freshness: .unavailable,
            windows: [],
            selectedWindowID: nil,
            remaining: .unavailable,
            isVisibleInDesktopAssistant: false,
            severity: .neutral
        )

        #expect(SharedUsagePresentationPolicy.assistantCards(from: []).isEmpty)
        #expect(
            SharedUsagePresentationPolicy.assistantCards(from: [codex]).map(\.id)
                == ["codex.local"]
        )
        #expect(
            SharedUsagePresentationPolicy.assistantCards(from: [workBuddy]).map(\.id)
                == ["workbuddy.manualAvailability"]
        )
        #expect(
            SharedUsagePresentationPolicy.assistantCards(
                from: [workBuddy, hidden, future, codex]
            ).map(\.id)
                == ["codex.local", "claude.code", "workbuddy.manualAvailability"]
        )
        #expect(DesktopAssistantDensity.automatic.resolvedDensity(visibleProviderCount: 2) == .regular)
        #expect(DesktopAssistantDensity.automatic.resolvedDensity(visibleProviderCount: 4) == .regular)
        #expect(DesktopAssistantDensity.automatic.resolvedDensity(visibleProviderCount: 5) == .minimalist)
    }

    @Test
    func fixedRowAndStackGeometryNeverDependsOnCreditValue() {
        #expect(
            DesktopAssistantMetrics.stackSize(for: .regular, rowCount: 0)
                == CGSize(width: 210, height: 0)
        )
        #expect(
            DesktopAssistantMetrics.stackSize(for: .regular, rowCount: 1)
                == CGSize(width: 210, height: 60)
        )
        #expect(
            DesktopAssistantMetrics.stackSize(for: .regular, rowCount: 2)
                == CGSize(width: 210, height: 124)
        )
        #expect(
            DesktopAssistantMetrics.stackSize(for: .minimalist, rowCount: 2)
                == CGSize(width: 58.333333, height: 64)
        )
        #expect(DesktopAssistantMetrics.rowSpacing == 4)
    }

    @Test(
        arguments: [
            (Int64(0), "0"),
            (Int64(1), "1"),
            (Int64(500), "500"),
            (Int64(3_600), "3.6k"),
            (Int64(50_000), "50k"),
            (Int64(200_000), "200k")
        ]
    )
    func nativeCreditFormattingNeverBecomesPercentage(
        remaining: Int64,
        expected: String
    ) throws {
        let shared = try workBuddyCard(remaining: remaining)
        let card = DesktopAssistantCard(shared: shared)

        #expect(card.usageValue == .credits(expected))
        #expect(card.usageValue.displayText == expected)
        #expect(!card.usageValue.displayText.contains("%"))
        #expect(card.sourceMark == .manual)
        #expect(card.selectedWindowShortLabel.isEmpty)
        #expect(card.resetText.isEmpty)
        #expect(card.detailText == "Manual snapshot")
    }

    @Test
    func founderFiveHundredStateUsesSharedFractionSeverityAndFullAccessibility() throws {
        let confirmedAt = now.addingTimeInterval(-3_600)
        let shared = try workBuddyCard(
            remaining: 500,
            used: 0,
            total: 500,
            observedAt: confirmedAt
        )
        let card = DesktopAssistantCard(shared: shared)

        #expect(card.usageValue == .credits("500"))
        #expect(card.tintFraction == 1)
        #expect(card.severity == .normal)
        #expect(card.sourceMark == .manual)
        #expect(card.accessibilityLabel.contains("WorkBuddy"))
        #expect(card.accessibilityLabel.contains("500 Credits available"))
        #expect(card.accessibilityLabel.contains("0 used of 500 active"))
        #expect(card.accessibilityLabel.contains("Buddy AI shared Credits"))
        #expect(card.accessibilityLabel.contains("Shared with CodeBuddy"))
        #expect(card.accessibilityLabel.contains("Manual snapshot"))
        #expect(card.accessibilityLabel.contains("Experience"))
        #expect(card.accessibilityLabel.contains("Next expiry"))
        #expect(!card.accessibilityLabel.localizedCaseInsensitiveContains("connected"))
    }

    @Test
    func absoluteOnlyCreditsStayNeutralAndHaveNoFill() throws {
        let card = DesktopAssistantCard(
            shared: try workBuddyCard(remaining: 50_000)
        )
        #expect(card.usageValue == .credits("50k"))
        #expect(card.tintFraction == nil)
        #expect(card.severity == .neutral)
        #expect(card.sourceMark == .manual)
        #expect(card.planLabel == WorkBuddyPlanTier.experience.rawValue)
    }

    @Test
    func exhaustedAndUnavailableLifecyclesRemainHonest() throws {
        let exhausted = DesktopAssistantCard(
            shared: try workBuddyCard(remaining: 0, used: 500, total: 500)
        )
        #expect(exhausted.usageValue == .credits("0"))
        #expect(exhausted.sourceMark == .manual)
        #expect(exhausted.severity == .critical)
        #expect(exhausted.accessibilityLabel.contains("Conversation Credits exhausted"))
        #expect(!exhausted.accessibilityLabel.contains("WorkBuddy unavailable"))

        let unconfigured = DesktopAssistantCard(
            shared: lifecycleCard(.unconfigured)
        )
        let invalid = DesktopAssistantCard(
            shared: lifecycleCard(
                .invalid,
                availability: SharedUsagePresentationPolicy.makeAvailabilityPresentation(
                    value: .invalid(reason: .unsupportedSchema),
                    language: .english
                )
            )
        )
        let unavailable = DesktopAssistantCard(
            shared: lifecycleCard(.unavailable)
        )

        for card in [unconfigured, invalid, unavailable] {
            #expect(card.usageValue == .unavailable)
            #expect(card.usageValue.displayText == "—")
            #expect(card.tintFraction == nil)
            #expect(card.severity == .neutral)
            #expect(card.sourceMark == .manual)
            #expect(card.detailText != nil)
            #expect(!card.accessibilityLabel.contains("Manual snapshot"))
            #expect(!card.accessibilityLabel.localizedCaseInsensitiveContains("confirmed"))
        }
        #expect(unconfigured.detailText == "Not configured")
        #expect(invalid.detailText == "Invalid data")
        #expect(unavailable.detailText == "Unavailable")
        #expect(Set([unconfigured.detailText, invalid.detailText, unavailable.detailText]).count == 3)
        #expect(unconfigured.accessibilityLabel.contains("not configured"))
        #expect(invalid.accessibilityLabel.contains("invalid"))
        #expect(unavailable.accessibilityLabel.contains("unavailable"))
        #expect(Set([unconfigured.accessibilityLabel, invalid.accessibilityLabel, unavailable.accessibilityLabel]).count == 3)
    }

    @Test
    func officialStructuredCreditsRemainProviderNeutral() throws {
        let balance = try CreditBalance(
            validatingRemaining: Int64(500),
            used: Int64(0),
            total: Int64(500),
            scope: .buddyAISharedPersonal,
            planTier: .personal,
            observedAt: now,
            provenance: .officialStructured(observedAt: now)
        )
        let shared = SharedUsageCardPresentation(
            id: "future.structuredCredits",
            providerName: "Future provider",
            connectionStatus: .connected,
            freshness: .fresh,
            windows: [],
            selectedWindowID: nil,
            remaining: .unavailable,
            availability: SharedUsagePresentationPolicy.makeAvailabilityPresentation(
                value: .credits(balance),
                language: .english
            ),
            availabilityLifecycle: nil,
            isVisibleInDesktopAssistant: true,
            severity: .neutral,
            capturedAt: now
        )

        let card = DesktopAssistantCard(shared: shared)
        #expect(card.usageValue == DesktopAssistantUsageValue.credits("500"))
        #expect(card.sourceMark == DesktopAssistantSourceMark.connection)
        #expect(card.detailText == nil)
        #expect(card.accessibilityLabel.contains("Future provider"))
        #expect(card.accessibilityLabel.contains("500 Credits remaining"))
        #expect(!card.accessibilityLabel.contains("WorkBuddy"))
        #expect(!card.accessibilityLabel.contains("Manual snapshot"))
        #expect(!card.accessibilityLabel.contains("Buddy AI"))
    }

    @Test
    func warningAndCriticalUseSharedSeverityWithoutChangingManualMark() throws {
        let warning = DesktopAssistantCard(
            shared: try workBuddyCard(remaining: 1_000, used: 3_000, total: 4_000)
        )
        let critical = DesktopAssistantCard(
            shared: try workBuddyCard(remaining: 400, used: 3_600, total: 4_000)
        )
        #expect(warning.severity == .warning)
        #expect(warning.tintFraction == 0.25)
        #expect(critical.severity == .critical)
        #expect(critical.tintFraction == 0.1)
        #expect(warning.sourceMark == .manual)
        #expect(critical.sourceMark == .manual)
    }

    @Test
    func simplifiedChineseAccessibilityRetainsManualCreditMeaning() throws {
        let card = DesktopAssistantCard(
            shared: try workBuddyCard(remaining: 500, used: 0, total: 500),
            language: .simplifiedChinese
        )
        #expect(card.accessibilityLabel.contains("WorkBuddy"))
        #expect(card.accessibilityLabel.contains("手动快照"))
        #expect(card.accessibilityLabel.contains("500"))
        #expect(card.accessibilityLabel.contains("Credits"))
        #expect(card.accessibilityLabel.contains("与 CodeBuddy 共享"))
        #expect(!card.accessibilityLabel.contains("%"))
    }

    @Test
    @MainActor
    func assistantOwnershipAndNavigationWiringStayHostOnly() throws {
        let repository = repositoryRoot()
        let assistant = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Views/DesktopAssistantView.swift"
            ),
            encoding: .utf8
        )
        for forbidden in [
            "ManualWorkBuddyAvailabilitySource",
            "WorkBuddyManualAvailabilityStore",
            "WorkBuddySettingsModel",
            "WorkBuddyAvailabilityConnector",
            "AgentConnectorRegistry",
            "URLSession",
            "Process(",
            "Timer.",
            "FileManager"
        ] {
            #expect(!assistant.contains(forbidden))
        }
        #expect(assistant.contains("onSelectCard"))
        #expect(assistant.contains(".accessibilityAction"))

        let status = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageMonitor/App/StatusBarController.swift"
            ),
            encoding: .utf8
        )
        let panel = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageMonitor/App/TransparentUsagePanelController.swift"
            ),
            encoding: .utf8
        )
        #expect(status.contains("show(expandingProviderID: providerID)"))
        #expect(panel.contains("UsagePanelNavigationRequest.assistantSelection"))
        #expect(!panel.contains("settingsInitiallyPresented: true"))

        let request = UsagePanelNavigationRequest.assistantSelection(
            providerID: "workbuddy.manualAvailability"
        )
        #expect(request.expandedProviderIDs == ["workbuddy.manualAvailability"])
        #expect(request.settingsInitiallyPresented == false)
        #expect(request.requestsRefresh == false)

        let suiteName = "M2WAG1DesktopAssistantTests.navigation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let before = defaults.persistentDomain(forName: suiteName) ?? [:]
        var selectedProviderID: String?
        let controller = DesktopAssistantPanelController(
            defaults: defaults,
            onSelectProvider: { selectedProviderID = $0 }
        )
        controller.handleSelection(providerID: "workbuddy.manualAvailability")
        #expect(selectedProviderID == "workbuddy.manualAvailability")
        #expect(
            NSDictionary(
                dictionary: defaults.persistentDomain(forName: suiteName) ?? [:]
            )
                .isEqual(to: before)
        )
        controller.tearDown()
    }

    @Test
    func rendererScenariosAreInMemoryAndNeverPersistReviewData() throws {
        let renderer = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/PreviewRendererTool/main.swift"
            ),
            encoding: .utf8
        )
        #expect(renderer.contains("--assistant-workbuddy"))
        #expect(renderer.contains("--workbuddy-synthetic-3600"))
        #expect(renderer.contains("remaining = 500"))
        #expect(renderer.contains("stackSize("))
        #expect(!renderer.contains("--write-workbuddy-record"))
        #expect(!renderer.contains("WorkBuddyManualAvailabilityStore"))
    }

    private func codexCard() -> SharedUsageCardPresentation {
        let window = SharedUsageWindowPresentation(
            id: "codex.seven-day",
            kind: .sevenDay,
            compactLabel: "7D",
            accessibilityLabel: "seven-day window",
            remaining: .finite(44),
            resetsAt: nil,
            resetText: "Resets later"
        )
        return SharedUsageCardPresentation(
            id: "codex.local",
            providerName: "Codex",
            connectionStatus: .connected,
            freshness: .fresh,
            windows: [window],
            selectedWindowID: window.id,
            remaining: .finite(44),
            severity: .normal,
            capturedAt: now
        )
    }

    private func placeholderCard(
        id: String,
        providerName: String
    ) -> SharedUsageCardPresentation {
        SharedUsageCardPresentation(
            id: id,
            providerName: providerName,
            connectionStatus: .unavailable,
            freshness: .unavailable,
            windows: [],
            selectedWindowID: nil,
            remaining: .unavailable,
            severity: .neutral,
            capturedAt: now
        )
    }

    private func workBuddyCard(
        remaining: Int64,
        used: Int64? = nil,
        total: Int64? = nil,
        observedAt: Date? = nil
    ) throws -> SharedUsageCardPresentation {
        let observedAt = observedAt ?? now
        let balance = try CreditBalance(
            validatingRemaining: remaining,
            used: used,
            total: total,
            scope: .buddyAISharedPersonal,
            planTier: .personal,
            nextExpiryAt: observedAt.addingTimeInterval(86_400),
            observedAt: observedAt,
            provenance: .manualConfirmed(at: observedAt)
        )
        return SharedUsageCardPresentation(
            id: "workbuddy.manualAvailability",
            providerName: "WorkBuddy",
            planLabel: WorkBuddyPlanTier.experience.rawValue,
            connectionStatus: .disconnected,
            freshness: .unavailable,
            windows: [],
            selectedWindowID: nil,
            remaining: .unavailable,
            availability: SharedUsagePresentationPolicy.makeAvailabilityPresentation(
                value: .credits(balance),
                language: .english
            ),
            availabilityLifecycle: .configured,
            isVisibleInDesktopAssistant: true,
            severity: .neutral,
            capturedAt: observedAt
        )
    }

    private func lifecycleCard(
        _ lifecycle: SharedAvailabilityLifecycle,
        availability: SharedAvailabilityPresentation? = nil
    ) -> SharedUsageCardPresentation {
        SharedUsageCardPresentation(
            id: "workbuddy.manualAvailability",
            providerName: "WorkBuddy",
            connectionStatus: .unavailable,
            freshness: .unavailable,
            windows: [],
            selectedWindowID: nil,
            remaining: .unavailable,
            availability: availability,
            availabilityLifecycle: lifecycle,
            isVisibleInDesktopAssistant: true,
            severity: .neutral,
            capturedAt: now
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
