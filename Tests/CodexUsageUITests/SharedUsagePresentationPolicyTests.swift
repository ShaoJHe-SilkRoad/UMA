import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Shared usage presentation policy")
struct SharedUsagePresentationPolicyTests {
    private let epoch = Date(timeIntervalSince1970: 1_784_332_800)

    @Test
    func conversionPreservesPrecisionAndRejectsInvalidInput() {
        let finite = card(snapshot(fiveHourRemaining: 71.25, sevenDayRemaining: nil))
        #expect(finite.windows[0].remaining == .finite(71.25))
        #expect(finite.windows[0].remaining.displayPercent == 71)
        #expect(finite.windows[0].remaining.tintFraction == 0.7125)

        for invalidUsed in [Double.nan, .infinity, -.infinity, -1, 101] {
            let invalid = card(
                snapshot(
                    fiveHourRemaining: nil,
                    sevenDayRemaining: nil,
                    rawFiveHourUsed: invalidUsed
                )
            )
            #expect(invalid.windows[0].remaining == .unavailable)
        }
    }

    @Test
    func thresholdBoundariesAreCentralized() {
        for value in [0.0, 1, 9, 10] {
            #expect(SharedUsagePresentationPolicy.severity(for: .finite(value)) == .critical)
        }
        for value in [11.0, 25] {
            #expect(SharedUsagePresentationPolicy.severity(for: .finite(value)) == .warning)
        }
        for value in [26.0, 50, 98, 100] {
            #expect(SharedUsagePresentationPolicy.severity(for: .finite(value)) == .normal)
        }
        #expect(SharedUsagePresentationPolicy.severity(for: .unlimited) == .neutral)
        #expect(SharedUsagePresentationPolicy.severity(for: .unavailable) == .neutral)
    }

    // Most-changeable rule: with nothing to compare yet, the shortest window
    // leads, because it moves most for the same use. It used to be the lowest
    // value, which put Claude on seven days after every launch.
    @Test
    func coldStartSelectsTheShortestWindow() {
        let result = card(snapshot(fiveHourRemaining: 71, sevenDayRemaining: 44))
        #expect(result.selectedWindowID == "five-hour")
        #expect(result.remaining == .finite(71))
        let noFiveHour = card(snapshot(fiveHourRemaining: nil, sevenDayRemaining: 44))
        #expect(noFiveHour.selectedWindowID == "seven-day")
    }

    // Claude's own readings, one Accuracy Sync apart: both windows fell by one
    // point. The old tie-break chose the lower value, seven days.
    @Test
    func equalDropsShowTheShortestWindow() {
        let first = card(snapshot(fiveHourRemaining: 88, sevenDayRemaining: 83))
        let next = card(
            snapshot(fiveHourRemaining: 87, sevenDayRemaining: 82, capturedAt: epoch.addingTimeInterval(600)),
            previous: first
        )
        #expect(next.selectedWindowID == "five-hour")
        #expect(next.remaining == .finite(87))
    }

    @Test
    func aResetRestatedWithinTenMinutesIsTheSameEpoch() {
        let first = card(snapshot(fiveHourRemaining: 60, sevenDayRemaining: 50))
        let previous = SharedUsageCardPresentation(
            id: first.id, providerName: first.providerName,
            connectionStatus: first.connectionStatus, freshness: first.freshness,
            windows: first.windows, selectedWindowID: "seven-day",
            remaining: .finite(50), severity: .normal, capturedAt: first.capturedAt
        )
        let drifted = card(
            snapshot(
                fiveHourRemaining: 52,
                sevenDayRemaining: 48,
                fiveHourReset: epoch.addingTimeInterval(3_600 + 90),
                capturedAt: epoch.addingTimeInterval(600)
            ),
            previous: previous
        )
        #expect(drifted.selectedWindowID == "five-hour")
    }

    @Test
    func aSpentWeekLeadsAFullFiveHours() {
        let result = card(snapshot(fiveHourRemaining: 100, sevenDayRemaining: 0))
        #expect(result.selectedWindowID == "seven-day")
        #expect(result.remaining == .finite(0))
    }

    @Test
    func maximumPositiveDecrementWinsAndRefillCannotWin() {
        let initial = card(snapshot(fiveHourRemaining: 30, sevenDayRemaining: 60))
        let refillAndDecrease = card(
            snapshot(
                fiveHourRemaining: 80,
                sevenDayRemaining: 50,
                capturedAt: epoch.addingTimeInterval(60)
            ),
            previous: initial
        )
        #expect(refillAndDecrease.selectedWindowID == "seven-day")

        let maximumDecrease = card(
            snapshot(
                fiveHourRemaining: 40,
                sevenDayRemaining: 45,
                capturedAt: epoch.addingTimeInterval(120)
            ),
            previous: card(snapshot(fiveHourRemaining: 60, sevenDayRemaining: 50))
        )
        #expect(maximumDecrease.selectedWindowID == "five-hour")
    }

    @Test
    func obsoleteFiveHourWindowCannotWinMaximumDecrement() {
        let previous = card(
            snapshot(
                fiveHourRemaining: 90,
                sevenDayRemaining: 60,
                fiveHourReset: epoch.addingTimeInterval(-1)
            )
        )
        let result = card(
            snapshot(
                fiveHourRemaining: 1,
                sevenDayRemaining: 55,
                fiveHourReset: epoch.addingTimeInterval(-1),
                capturedAt: epoch.addingTimeInterval(60)
            ),
            previous: previous
        )

        #expect(result.windows.map(\.id).contains("five-hour"))
        #expect(result.selectedWindowID == "seven-day")
        #expect(result.remaining == .finite(55))
    }

    @Test
    func changedResetEpochDoesNotCreateADecrement() {
        let initial = card(snapshot(fiveHourRemaining: 60, sevenDayRemaining: 60))
        let result = card(
            snapshot(
                fiveHourRemaining: 30,
                sevenDayRemaining: 50,
                fiveHourReset: epoch.addingTimeInterval(7_200),
                capturedAt: epoch.addingTimeInterval(60)
            ),
            previous: initial
        )
        #expect(result.selectedWindowID == "seven-day")
    }

    @Test
    func depletedAndCriticalOverridesWin() {
        let initial = card(snapshot(fiveHourRemaining: 90, sevenDayRemaining: 90))
        let depleted = card(
            snapshot(
                fiveHourRemaining: 0,
                sevenDayRemaining: 40,
                capturedAt: epoch.addingTimeInterval(60)
            ),
            previous: initial
        )
        #expect(depleted.selectedWindowID == "five-hour")

        let critical = card(
            snapshot(
                fiveHourRemaining: 30,
                sevenDayRemaining: 10,
                capturedAt: epoch.addingTimeInterval(120)
            ),
            previous: initial
        )
        #expect(critical.selectedWindowID == "seven-day")
    }

    @Test
    func noChangeRetainsPreviousSelection() {
        let initial = card(snapshot(fiveHourRemaining: 60, sevenDayRemaining: 50))
        let previousSelection = SharedUsageCardPresentation(
            id: initial.id,
            providerName: initial.providerName,
            connectionStatus: initial.connectionStatus,
            freshness: initial.freshness,
            windows: initial.windows,
            selectedWindowID: "five-hour",
            remaining: .finite(60),
            severity: .normal,
            capturedAt: initial.capturedAt
        )
        let unchanged = card(
            snapshot(
                fiveHourRemaining: 60,
                sevenDayRemaining: 50,
                capturedAt: epoch.addingTimeInterval(60)
            ),
            previous: previousSelection
        )
        #expect(unchanged.selectedWindowID == "five-hour")
    }

    @Test
    func unlimitedOrUnavailableFiveHourCannotRetainOverFiniteSevenDay() {
        let finite = card(snapshot(fiveHourRemaining: 40, sevenDayRemaining: 55))
        let priorFiveHour = SharedUsageCardPresentation(
            id: finite.id,
            providerName: finite.providerName,
            connectionStatus: finite.connectionStatus,
            freshness: finite.freshness,
            windows: finite.windows,
            selectedWindowID: "five-hour",
            remaining: .finite(40),
            availability: finite.availability,
            availabilityLifecycle: finite.availabilityLifecycle,
            isVisibleInDesktopAssistant: finite.isVisibleInDesktopAssistant,
            severity: finite.severity,
            isRetainingLastValidValue: false,
            capturedAt: finite.capturedAt
        )

        let unlimited = card(
            snapshot(
                fiveHourRemaining: nil,
                sevenDayRemaining: 55,
                fiveHourUnlimited: true,
                capturedAt: epoch.addingTimeInterval(60)
            ),
            previous: priorFiveHour
        )
        #expect(unlimited.selectedWindowID == "seven-day")

        let unavailable = card(
            snapshot(
                fiveHourRemaining: nil,
                sevenDayRemaining: 55,
                capturedAt: epoch.addingTimeInterval(120)
            ),
            previous: priorFiveHour
        )
        #expect(unavailable.selectedWindowID == "seven-day")
    }

    @Test
    func equalDecrementsUseFiveHourAsStableTieBreak() {
        let previous = card(snapshot(fiveHourRemaining: 70, sevenDayRemaining: 70))
        let result = card(
            snapshot(
                fiveHourRemaining: 60,
                sevenDayRemaining: 60,
                capturedAt: epoch.addingTimeInterval(60)
            ),
            previous: previous
        )
        #expect(result.selectedWindowID == "five-hour")
    }

    @Test
    func missingUnlimitedAndFiniteHundredRemainDistinct() {
        let oneMissing = card(snapshot(fiveHourRemaining: nil, sevenDayRemaining: 44))
        #expect(oneMissing.selectedWindowID == "seven-day")
        #expect(oneMissing.remaining == .finite(44))

        let bothMissing = card(snapshot(fiveHourRemaining: nil, sevenDayRemaining: nil))
        #expect(bothMissing.remaining == .unavailable)

        let unlimited = card(
            snapshot(
                fiveHourRemaining: nil,
                sevenDayRemaining: nil,
                fiveHourUnlimited: true
            )
        )
        #expect(unlimited.remaining == .unlimited)

        let finiteHundred = card(snapshot(fiveHourRemaining: 100, sevenDayRemaining: nil))
        #expect(finiteHundred.remaining == .finite(100))
        #expect(finiteHundred.remaining != unlimited.remaining)
    }

    @Test
    func staleFailureAndRecoveryRetainOnlyLastValidValues() {
        let fresh = card(snapshot(fiveHourRemaining: 71, sevenDayRemaining: 44))
        let stale = card(
            snapshot(
                fiveHourRemaining: 10,
                sevenDayRemaining: 9,
                state: .stale,
                freshness: .stale,
                capturedAt: epoch.addingTimeInterval(60)
            ),
            previous: fresh
        )
        #expect(stale.remaining == .finite(71))
        #expect(stale.selectedWindowID == fresh.selectedWindowID)
        #expect(stale.isRetainingLastValidValue)

        let failed = card(
            snapshot(
                fiveHourRemaining: nil,
                sevenDayRemaining: nil,
                state: .failed,
                freshness: .unavailable,
                capturedAt: epoch.addingTimeInterval(120)
            ),
            previous: fresh
        )
        #expect(failed.remaining == .finite(71))
        #expect(failed.connectionStatus == .failed)
        #expect(failed.isRetainingLastValidValue)

        let failedWithoutPrior = card(
            snapshot(
                fiveHourRemaining: nil,
                sevenDayRemaining: nil,
                state: .failed,
                freshness: .unavailable
            )
        )
        #expect(failedWithoutPrior.remaining == .unavailable)

        let recovered = card(
            snapshot(
                fiveHourRemaining: 88,
                sevenDayRemaining: 77,
                capturedAt: epoch.addingTimeInterval(180)
            ),
            previous: failed
        )
        #expect(recovered.remaining == .finite(88))
        #expect(recovered.freshness == .fresh)
        #expect(!recovered.isRetainingLastValidValue)
    }

    @Test
    func cachedAndStaleSamplesCannotDriveDecrementSelectionOrAlerts() {
        let fresh = card(snapshot(fiveHourRemaining: 60, sevenDayRemaining: 44))
        let priorFiveHour = SharedUsageCardPresentation(
            id: fresh.id,
            providerName: fresh.providerName,
            connectionStatus: fresh.connectionStatus,
            freshness: fresh.freshness,
            windows: fresh.windows,
            selectedWindowID: "five-hour",
            remaining: .finite(60),
            severity: .normal,
            capturedAt: fresh.capturedAt
        )

        for retainedFreshness in [
            AgentConnectorFreshness.cached,
            AgentConnectorFreshness.stale,
        ] {
            let retained = card(
                snapshot(
                    fiveHourRemaining: 1,
                    sevenDayRemaining: 43,
                    state: .stale,
                    freshness: retainedFreshness,
                    capturedAt: epoch.addingTimeInterval(60)
                ),
                previous: priorFiveHour
            )

            #expect(retained.selectedWindowID == "five-hour")
            #expect(retained.remaining == .finite(60))
            #expect(retained.severity == .neutral)
            #expect(retained.isRetainingLastValidValue)
        }
    }

    @Test
    func olderSamplesCannotReplaceNewerPresentation() {
        let newest = card(
            snapshot(
                fiveHourRemaining: 50,
                sevenDayRemaining: 40,
                capturedAt: epoch.addingTimeInterval(60)
            )
        )
        let outOfOrder = card(
            snapshot(
                fiveHourRemaining: 1,
                sevenDayRemaining: 2,
                capturedAt: epoch
            ),
            previous: newest
        )
        #expect(outOfOrder == newest)
    }

    @Test
    func legacyProjectionNeverFabricatesOneHundredForMissingUsage() {
        let projected = UsageSnapshot(
            agentSnapshot: snapshot(fiveHourRemaining: nil, sevenDayRemaining: 44),
            language: .english,
            now: epoch
        )
        #expect(projected.periods.map(\.id) == ["seven-day"])
        #expect(projected.periods[0].remainingPercent == 44)
    }

    @Test
    func sharedCardsRemainRegistryOrderedAndIndependent() {
        let codex = snapshot(
            id: "codex.local",
            provider: "Codex",
            fiveHourRemaining: 71,
            sevenDayRemaining: 44
        )
        let second = snapshot(
            id: "future.provider",
            provider: "Future",
            fiveHourRemaining: 9,
            sevenDayRemaining: 80
        )
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: [codex, second],
            previousCards: [],
            language: .english,
            now: epoch
        )
        #expect(cards.map(\.id) == ["codex.local", "future.provider"])
        #expect(cards[0].remaining == .finite(71))
        #expect(cards[1].remaining == .finite(9))
        #expect(cards[0].severity == .normal)
        #expect(cards[1].severity == .critical)
    }

    @MainActor
    @Test
    func primaryConnectionTransitionsDoNotRewriteOtherProviders() {
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: [
                snapshot(
                    id: "codex.local",
                    provider: "Codex",
                    fiveHourRemaining: 71,
                    sevenDayRemaining: 44
                ),
                snapshot(
                    id: "future.provider",
                    provider: "Future",
                    fiveHourRemaining: 9,
                    sevenDayRemaining: 80
                )
            ],
            previousCards: [],
            language: .english,
            now: epoch
        )

        let updated = UsageStore.cardsByUpdatingPrimaryConnection(
            cards,
            primaryConnectorID: AgentConnectorID(rawValue: "codex.local"),
            status: .transitional,
            freshness: .stale
        )

        #expect(updated[0].connectionStatus == .transitional)
        #expect(updated[0].freshness == .stale)
        #expect(updated[1] == cards[1])
    }

    private func card(
        _ snapshot: AgentUsageSnapshot,
        previous: SharedUsageCardPresentation? = nil
    ) -> SharedUsageCardPresentation {
        SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: previous,
            language: .english,
            now: epoch
        )
    }

    private func snapshot(
        id: String = "codex.local",
        provider: String = "Codex",
        fiveHourRemaining: Double?,
        sevenDayRemaining: Double?,
        rawFiveHourUsed: Double? = nil,
        fiveHourUnlimited: Bool = false,
        state: AgentConnectorState = .ready,
        freshness: AgentConnectorFreshness = .fresh,
        fiveHourReset: Date? = nil,
        capturedAt: Date? = nil
    ) -> AgentUsageSnapshot {
        let capturedAt = capturedAt ?? epoch
        let channelFreshness: AgentConnectorFreshness = freshness
        return AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: id)!,
            providerName: provider,
            state: state,
            capturedAt: capturedAt,
            lastSuccessfulAt: freshness == .fresh ? capturedAt : epoch,
            freshness: freshness,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialLocalService,
                    sourceVersion: "app-server",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: channelFreshness,
                    capturedAt: capturedAt,
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: "five-hour",
                            kind: .fiveHour,
                            usedPercent: rawFiveHourUsed
                                ?? fiveHourRemaining.map { 100 - $0 },
                            isUnlimited: fiveHourUnlimited,
                            resetsAt: fiveHourReset ?? epoch.addingTimeInterval(3_600)
                        ),
                        AgentRateLimitWindow(
                            id: "seven-day",
                            kind: .sevenDay,
                            usedPercent: sevenDayRemaining.map { 100 - $0 },
                            isUnlimited: false,
                            resetsAt: epoch.addingTimeInterval(604_800)
                        )
                    ],
                    accountMetrics: AgentAccountMetrics(
                        planLabel: "PRO",
                        availableResets: 1,
                        lifetimeTokens: 100,
                        sevenDayTokens: 10
                    ),
                    localActivityMetrics: nil,
                    safeFailure: state == .failed ? .unavailable : nil
                )
            ],
            capabilities: [.connect, .refresh, .disconnect],
            safeFailure: state == .failed ? .unavailable : nil
        )
    }
}
