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

    @Test
    func coldStartSelectsLowestFiniteRemaining() {
        let result = card(snapshot(fiveHourRemaining: 71, sevenDayRemaining: 44))
        #expect(result.selectedWindowID == "seven-day")
        #expect(result.remaining == .finite(44))
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
        #expect(stale.remaining == .finite(44))
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
        #expect(failed.remaining == .finite(44))
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
        #expect(recovered.remaining == .finite(77))
        #expect(recovered.freshness == .fresh)
        #expect(!recovered.isRetainingLastValidValue)
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
        #expect(cards[0].remaining == .finite(44))
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
