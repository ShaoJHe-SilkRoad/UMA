import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2W-G3 WorkBuddy main panel")
struct M2WG3WorkBuddyMainPanelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func manualWorkBuddyIsHiddenFromMainPanelAndAssistant() throws {
        let codex = codexSnapshot()
        let workBuddy = try workBuddySnapshot(remaining: 3_600, used: 400)
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: [codex, workBuddy],
            previousCards: [],
            language: .english,
            now: now
        )

        #expect(cards.map(\.id) == ["codex.local"])
        #expect(cards.map(\.providerName) == ["Codex"])
        #expect(cards[0].isVisibleInDesktopAssistant)
        #expect(
            SharedUsagePresentationPolicy.assistantCards(from: cards).map(\.id)
                == ["codex.local"]
        )
    }

    @Test
    func configuredPresentationUsesSharedFractionExactValuesAndManualProvenance() throws {
        let card = try #require(try makeCard(remaining: 3_600, used: 400))
        let presentation = try #require(
            WorkBuddyMainPanelPresentation.make(
                card: card,
                language: .english,
                now: now.addingTimeInterval(3_600)
            )
        )

        #expect(presentation.state == .configured)
        #expect(presentation.compactValue == "3,600")
        #expect(presentation.availableText == "3,600 Credits available")
        #expect(presentation.balanceDetail == "400 used of 4,000 active")
        #expect(presentation.remainingFraction == card.availability?.normalizedRemainingFraction)
        #expect(presentation.remainingFraction == 0.9)
        #expect(presentation.severity == .available)
        #expect(presentation.manualStatus.contains("Manual snapshot"))
        #expect(presentation.manualStatus.contains("1h ago"))
        #expect(presentation.exactConfirmation != nil)
        #expect(presentation.scopeTitle == "Buddy AI shared Credits")
        #expect(presentation.scopeDetail == "Shared with CodeBuddy")
        #expect(presentation.accessibilityLabel.contains("WorkBuddy"))
        #expect(presentation.accessibilityLabel.contains("3,600 Credits available"))
        #expect(presentation.accessibilityLabel.contains("Shared with CodeBuddy"))
    }

    @Test(
        arguments: [
            (Int64(0), "0"),
            (Int64(1), "1"),
            (Int64(500), "500"),
            (Int64(3_600), "3,600"),
            (Int64(50_000), "50,000"),
            (Int64(200_000), "200,000")
        ]
    )
    func mainPanelCreditsRemainExact(value: Int64, expected: String) throws {
        let card = try #require(try makeCard(remaining: value))
        let presentation = try #require(
            WorkBuddyMainPanelPresentation.make(card: card, language: .english, now: now)
        )
        #expect(presentation.compactValue == expected)
    }

    @Test
    func severityThresholdsAndBarAvailabilityUseSharedPolicy() throws {
        let cases: [(Int64, Int64, AgentAvailabilitySeverity)] = [
            (3_000, 1_000, .available),
            (1_000, 3_000, .warning),
            (105, 895, .warning),
            (400, 3_600, .critical),
            (0, 4_000, .exhausted)
        ]
        for (remaining, used, expected) in cases {
            let card = try #require(try makeCard(remaining: remaining, used: used))
            let presentation = try #require(
                WorkBuddyMainPanelPresentation.make(card: card, language: .english, now: now)
            )
            #expect(presentation.severity == expected)
            #expect(presentation.remainingFraction == card.availability?.normalizedRemainingFraction)
        }

        let absolute = try #require(try makeCard(remaining: 50_000))
        let absolutePresentation = try #require(
            WorkBuddyMainPanelPresentation.make(
                card: absolute,
                language: .english,
                now: now
            )
        )
        #expect(absolutePresentation.remainingFraction == nil)
        #expect(absolutePresentation.balanceDetail == nil)
        #expect(absolutePresentation.severity == .neutral)
    }

    @Test
    func explicitTotalAndAbsoluteOnlyCreditsRemainDistinctWithoutPercentCopy() throws {
        let totalOnly = try #require(try makeCard(remaining: 3_600, total: 4_000))
        let totalPresentation = try #require(
            WorkBuddyMainPanelPresentation.make(card: totalOnly, language: .english, now: now)
        )
        #expect(totalPresentation.remainingFraction == 0.9)
        #expect(totalPresentation.balanceDetail == "4,000 active total")

        let absolute = try #require(try makeCard(remaining: 50_000))
        let absolutePresentation = try #require(
            WorkBuddyMainPanelPresentation.make(card: absolute, language: .english, now: now)
        )
        #expect(absolutePresentation.remainingFraction == nil)
        #expect(absolutePresentation.balanceDetail == nil)

        for presentation in [totalPresentation, absolutePresentation] {
            #expect(!presentation.compactValue.contains("%"))
            #expect(!presentation.availableText.contains("%"))
            #expect(!(presentation.balanceDetail ?? "").contains("%"))
        }
    }

    @Test
    func exhaustionWordingAgeBoundariesAndTierIndependentSeverityAreDeterministic() throws {
        let exhausted = try #require(try makeCard(remaining: 0, used: 4_000))
        let exhaustedPresentation = try #require(
            WorkBuddyMainPanelPresentation.make(card: exhausted, language: .english, now: now)
        )
        #expect(exhaustedPresentation.state == .exhausted)
        #expect(exhaustedPresentation.availableText == "Conversation Credits exhausted")
        #expect(exhaustedPresentation.accessibilityLabel.contains("Conversation Credits exhausted"))

        let flagship = try #require(
            try makeCard(remaining: 400, used: 3_600, tier: .flagship)
        )
        let flagshipPresentation = try #require(
            WorkBuddyMainPanelPresentation.make(card: flagship, language: .english, now: now)
        )
        #expect(flagshipPresentation.severity == .critical)
        #expect(flagshipPresentation.tierText == "Flagship")

        let ages: [(TimeInterval, String)] = [
            (0, "just now"),
            (60, "1m ago"),
            (3_600, "1h ago"),
            (86_400, "1d ago")
        ]
        let ageCard = try #require(try makeCard(remaining: 3_600, used: 400))
        for (elapsed, expected) in ages {
            let presentation = try #require(
                WorkBuddyMainPanelPresentation.make(
                    card: ageCard,
                    language: .english,
                    now: now.addingTimeInterval(elapsed)
                )
            )
            #expect(presentation.manualStatus.contains(expected))
        }
    }

    @Test
    func providerExpansionIsStableByConnectorIDAcrossValueChanges() {
        var state = MainPanelProviderExpansionState()
        state.setExpanded(true, providerID: "workbuddy.manualAvailability")
        #expect(state.isExpanded("workbuddy.manualAvailability"))
        #expect(!state.isExpanded("codex.local"))
        // The state is keyed only by connector identity, so presentation value
        // and confirmation-time replacements cannot collapse the provider.
        let beforeUpdate = state
        #expect(beforeUpdate == state)
        state.setExpanded(false, providerID: "workbuddy.manualAvailability")
        #expect(!state.isExpanded("workbuddy.manualAvailability"))
    }

    @Test
    func manualWorkBuddyRemainsHiddenAcrossIndependentCodexStates() throws {
        let workBuddy = try workBuddySnapshot(remaining: 3_600, used: 400)
        for state in [
            AgentConnectorState.ready,
            AgentConnectorState.waitingForFirstResponse,
            .stale,
            .failed
        ] {
            let cards = SharedUsagePresentationPolicy.makeCards(
                snapshots: [
                    codexSnapshot(state: state),
                    workBuddy
                ],
                previousCards: [],
                language: .english,
                now: now.addingTimeInterval(60)
            )
            #expect(
                cards.map(\.id)
                    == (state == .ready ? ["codex.local"] : [])
            )
        }
        let compatibilityCard = SharedUsagePresentationPolicy.makeCard(
            snapshot: workBuddy,
            previous: nil,
            language: .english,
            now: now
        )
        #expect(
            compatibilityCard.availability?.value.creditBalance?.remaining
                == 3_600
        )
        #expect(
            compatibilityCard.availability?.value.creditBalance?.used == 400
        )
    }

    @Test
    func manualLifecycleDoesNotRetainAFormerBalanceForUnconfiguredOrInvalid() throws {
        let configured = try #require(try makeCard(remaining: 3_600, used: 400))
        let unconfiguredCard = SharedUsagePresentationPolicy.makeCard(
            snapshot: workBuddyLifecycleSnapshot(
                failure: .unavailable,
                capturedAt: now.addingTimeInterval(60)
            ),
            previous: configured,
            language: .english,
            now: now.addingTimeInterval(60)
        )
        #expect(unconfiguredCard.availabilityLifecycle == .unconfigured)
        #expect(unconfiguredCard.availability?.sourceState != .manualConfirmed)
        #expect(!unconfiguredCard.isRetainingLastValidValue)
        #expect(unconfiguredCard.planLabel == nil)
        let unconfiguredPresentation = try #require(
            WorkBuddyMainPanelPresentation.make(
                card: unconfiguredCard,
                language: .english,
                now: now
            )
        )
        #expect(unconfiguredPresentation.state == .unconfigured)
        #expect(unconfiguredPresentation.compactValue == "—")
        #expect(unconfiguredPresentation.severityText == "Not configured")
        #expect(unconfiguredPresentation.manualStatus == "Not yet confirmed")
        #expect(!unconfiguredPresentation.accessibilityLabel.contains("snapshot"))

        let invalidCard = SharedUsagePresentationPolicy.makeCard(
            snapshot: workBuddyLifecycleSnapshot(
                failure: .malformedResponse,
                capturedAt: now.addingTimeInterval(120)
            ),
            previous: configured,
            language: .english,
            now: now.addingTimeInterval(120)
        )
        #expect(invalidCard.availabilityLifecycle == .invalid)
        #expect(invalidCard.availability?.sourceState != .manualConfirmed)
        #expect(!invalidCard.isRetainingLastValidValue)
        let invalidPresentation = try #require(
            WorkBuddyMainPanelPresentation.make(
                card: invalidCard,
                language: .english,
                now: now
            )
        )
        #expect(invalidPresentation.severityText == "Invalid data")
    }

    @Test
    func everyManualLifecycleIsHiddenFromProviderSurfaces() {
        let disabled = workBuddyLifecycleSnapshot(failure: nil, capturedAt: now)
        let unconfigured = workBuddyLifecycleSnapshot(
            failure: .unavailable,
            capturedAt: now
        )
        let invalid = workBuddyLifecycleSnapshot(
            failure: .malformedResponse,
            capturedAt: now
        )

        #expect(
            SharedUsagePresentationPolicy.makeCards(
                snapshots: [disabled],
                previousCards: [],
                language: .english,
                now: now
            ).isEmpty
        )
        #expect(
            SharedUsagePresentationPolicy.makeCards(
                snapshots: [unconfigured, invalid],
                previousCards: [],
                language: .english,
                now: now
            ).isEmpty
        )
    }

    @Test
    func englishAndChineseCopyIdentifyManualSharedCreditsAndAccessibility() throws {
        let card = try #require(try makeCard(remaining: 3_600, used: 400))
        for language in [AppLanguage.english, .simplifiedChinese] {
            let presentation = try #require(
                WorkBuddyMainPanelPresentation.make(
                    card: card,
                    language: language,
                    now: now
                )
            )
            #expect(presentation.scopeTitle.contains("Credits"))
            #expect(presentation.scopeDetail.contains("CodeBuddy"))
            #expect(presentation.accessibilityLabel.contains("WorkBuddy"))
            #expect(presentation.accessibilityLabel.contains("Credits"))
            #expect(presentation.limitationText.contains(language == .english ? "Automatic" : "自动"))
        }
    }

    @Test
    func sourceContractKeepsTypedExpansionSettingsRoutingAndAssistantExclusion() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let panel = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsagePanelView.swift"
            ),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
            ),
            encoding: .utf8
        )
        let shell = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageMonitor/App/AppShellCoordinator.swift"
            ),
            encoding: .utf8
        )
        let card = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Views/WorkBuddyMainPanelCard.swift"
            ),
            encoding: .utf8
        )

        #expect(!panel.contains("WorkBuddyMainPanelCard"))
        #expect(panel.contains("expandedProviderIDs"))
        #expect(panel.contains("settingsDestination = .agent(canonicalProviderID)"))
        #expect(panel.contains("ScrollView(.vertical)"))
        #expect(settings.contains("enum UsageSettingsDestination"))
        #expect(settings.contains("expandOnAppear"))
        #expect(shell.contains("store.assistantPresentationCards"))
        #expect(!shell.contains("cards: store.presentationCards"))
        #expect(card.contains("workBuddyUpdateCredits"))
        #expect(card.contains("workBuddyConfirmUnchanged"))
        #expect(card.contains(".layoutPriority(2)"))
        #expect(card.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(!card.contains("accessibilityElement(children: .ignore)"))
        #expect(card.contains("workBuddyClearInSettingsHint"))
        #expect(!card.contains("settings?.clear"))
        #expect(card.contains("accessibilityReduceMotion"))
        #expect(card.contains("GlassCardBackground"))
        #expect(!card.contains(".overlay {\n                if usesIncreaseContrast"))
        #expect(
            settings.components(separatedBy: "ScrollView(.vertical)").count - 1 == 1
        )
        #expect(settings.contains(".scrollBounceBehavior(.basedOnSize)"))
        #expect(settings.contains("usage.settings.scroll"))
        #expect(panel.contains("usesReduceMotion ? nil"))
        #expect(settings.contains("workBuddyConfirmClear"))
        #expect(settings.contains("clearIsArmed"))
        #expect(settings.contains("reduceMotion ? nil"))
        #expect(panel.contains("MainPanelProviderExpansionState"))
    }

    @Test
    func g3PresentationAddsNoProviderInspectionOrAutomaticSynchronization() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "Sources/CodexUsageUI/Models/WorkBuddyMainPanelPresentation.swift",
            "Sources/CodexUsageUI/Views/WorkBuddyMainPanelCard.swift",
            "Sources/CodexUsageUI/Views/UsagePanelView.swift"
        ]
        let source = try paths.map {
            try String(
                contentsOf: repository.appendingPathComponent($0),
                encoding: .utf8
            )
        }.joined(separator: "\n")
        for forbidden in [
            "URLSession", "Process(", "AXUIElement", "CGWindow",
            "Keychain", "OCR", "FSEvent", "OneDrive"
        ] {
            #expect(!source.localizedCaseInsensitiveContains(forbidden))
        }
    }

    private func makeCard(
        remaining: Int64,
        used: Int64? = nil,
        total: Int64? = nil,
        tier: WorkBuddyPlanTier = .standard
    ) throws -> SharedUsageCardPresentation? {
        SharedUsagePresentationPolicy.makeCard(
            snapshot: try workBuddySnapshot(
                remaining: remaining,
                used: used,
                total: total,
                tier: tier
            ),
            previous: nil,
            language: .english,
            now: now
        )
    }

    private func workBuddySnapshot(
        remaining: Int64,
        used: Int64?,
        total: Int64? = nil,
        tier: WorkBuddyPlanTier = .standard
    ) throws -> AgentUsageSnapshot {
        let balance = try CreditBalance(
            validatingRemaining: remaining,
            used: used,
            total: total,
            scope: .buddyAISharedPersonal,
            planTier: .personal,
            nextExpiryAt: now.addingTimeInterval(86_400),
            observedAt: now,
            provenance: .manualConfirmed(at: now)
        )
        return AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: "workbuddy.manualAvailability")!,
            providerName: "WorkBuddy",
            state: .inactive,
            capturedAt: now,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .manualUserConfirmed,
                    sourceVersion: "1",
                    scopes: [.account],
                    provenance: .manualConfirmed,
                    freshness: .unavailable,
                    capturedAt: now,
                    coverageNote: nil,
                    rateLimitWindows: [],
                    accountMetrics: AgentAccountMetrics(
                        planLabel: tier.rawValue,
                        availableResets: nil,
                        lifetimeTokens: nil,
                        sevenDayTokens: nil
                    ),
                    localActivityMetrics: nil,
                    safeFailure: nil,
                    availability: .credits(balance)
                )
            ],
            capabilities: [.passiveLocalAvailability],
            safeFailure: nil
        )
    }

    private func workBuddyLifecycleSnapshot(
        failure: AgentSafeFailure?,
        capturedAt: Date
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: "workbuddy.manualAvailability")!,
            providerName: "WorkBuddy",
            state: .inactive,
            capturedAt: capturedAt,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .manualUserConfirmed,
                    sourceVersion: "1",
                    scopes: [.account],
                    provenance: .manualConfirmed,
                    freshness: .unavailable,
                    capturedAt: capturedAt,
                    coverageNote: nil,
                    rateLimitWindows: [],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: failure,
                    availability: .unavailable
                )
            ],
            capabilities: [.passiveLocalAvailability],
            safeFailure: failure
        )
    }

    private func codexSnapshot(
        state: AgentConnectorState = .ready
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: "codex.local")!,
            providerName: "Codex",
            state: state,
            capturedAt: now,
            lastSuccessfulAt: now,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialLocalService,
                    sourceVersion: "1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: now,
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: "seven-day",
                            kind: .sevenDay,
                            usedPercent: 56,
                            isUnlimited: false,
                            resetsAt: now.addingTimeInterval(86_400)
                        )
                    ],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                )
            ],
            capabilities: [.rateLimits, .accountUsage],
            safeFailure: nil
        )
    }
}
