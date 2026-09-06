import Foundation
import Testing
@testable import CodexUsageUI

struct ThreadOSAttributionLedgerTests {
    @Test
    func keepsUnprovenIntervalTransitionsInTheAggregateLane() throws {
        let price = APIModelPrice(
            version: "test-price",
            displayName: "Test Model",
            inputPerMillion: 1,
            cachedInputPerMillion: 0.1,
            outputPerMillion: 6
        )
        var ledger = APICostLedger()

        let first = ledger.observe(
            sessionID: "opaque-session",
            summary: Self.summary(total: 100, interval: "thread-v1:turn-a:0-100"),
            initialUsageDay: "2026-09-06",
            incrementalUsageDay: "2026-09-06",
            price: price
        )
        #expect(first)
        let second = ledger.observe(
            sessionID: "opaque-session",
            summary: Self.summary(total: 250, interval: "thread-v1:turn-b:100-250"),
            initialUsageDay: "2026-09-06",
            incrementalUsageDay: "2026-09-06",
            price: price
        )
        #expect(second)
        let third = ledger.observe(
            sessionID: "opaque-session",
            summary: Self.summary(total: 300, interval: "thread-v1:turn-b:100-250"),
            initialUsageDay: "2026-09-06",
            incrementalUsageDay: "2026-09-06",
            price: price
        )
        #expect(third)

        #expect(ledger.records.count == 1)
        #expect(ledger.records.first?.attributionIntervalID == nil)
        #expect(ledger.records.first?.counts.totalTokens == 300)
    }

    @Test
    func partitionsOnlyMatchedUsageAndConservesTheHighWaterDelta() throws {
        var ledger = APICostLedger()
        let recorded = ledger.observe(sessionID: "partitioned", summary: Self.summary(total: 300, interval: "local-hint"), initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06", price: Self.price, intervalPartitions: [
            Self.partition("matched-a", total: 100),
            Self.partition("matched-b", total: 50, precedingTotal: 100)
        ])
        #expect(recorded)

        #expect(ledger.records.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 300)
        #expect(ledger.records.first(where: { $0.attributionIntervalID == "matched-a" })?.counts.totalTokens == 100)
        #expect(ledger.records.first(where: { $0.attributionIntervalID == "matched-b" })?.counts.totalTokens == 50)
        #expect(ledger.records.first(where: { $0.attributionIntervalID == nil })?.counts.totalTokens == 150)
    }

    @Test
    func keepsLegacyPartitionDefaultsSeparateFromAnExplicitUnknownResidual() throws {
        var ledger = APICostLedger()
        let recorded = ledger.observe(
            sessionID: "legacy-defaults",
            summary: Self.summary(total: 150, interval: "local-hint"),
            initialUsageDay: "2026-09-06",
            incrementalUsageDay: "2026-09-06",
            price: Self.price,
            residualPricing: .init(model: "UNKNOWN", price: nil, hasExplicitPrice: true),
            intervalPartitions: [
                Self.partition("legacy-a", total: 100),
                Self.partition("legacy-b", total: 25, precedingTotal: 100)
            ]
        )

        #expect(recorded)
        #expect(ledger.records.first(where: { $0.attributionIntervalID == "legacy-a" })?.model == "test-model")
        #expect(ledger.records.first(where: { $0.attributionIntervalID == "legacy-a" })?.price == Self.price)
        #expect(ledger.records.first(where: { $0.attributionIntervalID == "legacy-b" })?.model == "test-model")
        let residual = try #require(ledger.records.first(where: { $0.attributionIntervalID == nil }))
        #expect(residual.model == "UNKNOWN")
        #expect(residual.price == nil)
        #expect(residual.counts.totalTokens == 25)
    }

    @Test
    func preservesExplicitNilPriceForKnownUnpricedPartitionAndResidual() throws {
        var ledger = APICostLedger()
        let counts = Self.counts(total: 30)
        let projection = APICostLedger.AccountingProjection(
            projectKey: "TOSUMA", taskID: "TU3", localRole: "Coder",
            model: "unpriced-model", counts: counts,
            observedStart: Date(timeIntervalSince1970: 1), observedEnd: Date(timeIntervalSince1970: 2)
        )
        let recorded = ledger.observe(
            sessionID: "explicit-nil",
            summary: Self.summary(total: 50, interval: "local-hint"),
            initialUsageDay: "2026-09-06",
            incrementalUsageDay: "2026-09-06",
            price: Self.price,
            residualPricing: .init(model: "UNKNOWN", price: nil, hasExplicitPrice: true),
            intervalPartitions: [.init(
                attributionIntervalID: "unpriced-turn", counts: counts,
                preceding: Self.counts(total: 0), ending: counts,
                projection: projection, model: "unpriced-model", price: nil,
                hasValidatedPrice: true
            )]
        )

        #expect(recorded)
        #expect(ledger.records.allSatisfy { $0.price == nil && $0.usd == 0 })
        #expect(ledger.records.first(where: { $0.attributionIntervalID == "unpriced-turn" })?.model == "unpriced-model")
        #expect(ledger.records.first(where: { $0.attributionIntervalID == nil })?.model == "UNKNOWN")
    }

    @Test
    func acceptsValidatedNewModelWhileLeavingAnExplicitTransitionGapUnknown() throws {
        var ledger = APICostLedger()
        let initialRecorded = ledger.observe(
            sessionID: "model-transition",
            summary: Self.summary(total: 30, interval: "initial"),
            initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06",
            price: Self.price,
            residualPricing: .init(model: "test-model", price: Self.price, hasExplicitPrice: true)
        )
        #expect(initialRecorded)

        let newCounts = Self.counts(total: 30)
        let projection = APICostLedger.AccountingProjection(
            projectKey: "TOSUMA", taskID: "TU3", localRole: "Coder",
            model: "second-model", counts: newCounts,
            observedStart: Date(timeIntervalSince1970: 3), observedEnd: Date(timeIntervalSince1970: 4)
        )
        let secondRecorded = ledger.observe(
            sessionID: "model-transition",
            summary: Self.summary(total: 65, interval: "second"),
            initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06",
            price: Self.price,
            residualPricing: .init(model: "UNKNOWN", price: nil, hasExplicitPrice: true),
            intervalPartitions: [.init(
                attributionIntervalID: "second-turn", counts: newCounts,
                preceding: Self.counts(total: 35), ending: Self.counts(total: 65),
                projection: projection, model: "second-model", price: nil,
                hasValidatedPrice: true
            )]
        )
        #expect(secondRecorded)

        #expect(ledger.records.first(where: { $0.attributionIntervalID == "second-turn" })?.counts.totalTokens == 30)
        #expect(ledger.records.first(where: { $0.attributionIntervalID == "second-turn" })?.model == "second-model")
        let unknown = try #require(ledger.records.first(where: { $0.attributionIntervalID == nil && $0.model == "UNKNOWN" }))
        #expect(unknown.counts.totalTokens == 5)
        #expect(unknown.price == nil)
        #expect(ledger.records.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 65)
    }

    @Test
    func keepsSameModelGapInTheCheckpointModelLane() throws {
        var ledger = APICostLedger()
        let initialRecorded = ledger.observe(
            sessionID: "same-model-gap",
            summary: Self.summary(total: 30, interval: "initial", model: "model-a"),
            initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06",
            price: Self.price,
            localTransitionEvidence: .init(models: ["model-a"], hasUnknownOrAmbiguousInterval: false)
        )
        #expect(initialRecorded)
        let counts = Self.counts(total: 30)
        let projection = APICostLedger.AccountingProjection(
            projectKey: "TOSUMA", taskID: "TU3", localRole: "Coder",
            model: "model-a", counts: counts,
            observedStart: Date(timeIntervalSince1970: 3), observedEnd: Date(timeIntervalSince1970: 4)
        )
        let laterRecorded = ledger.observe(
            sessionID: "same-model-gap",
            summary: Self.summary(total: 65, interval: "later", model: "model-a"),
            initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06",
            price: Self.price,
            intervalPartitions: [.init(
                attributionIntervalID: "same-model-turn", counts: counts,
                preceding: Self.counts(total: 35), ending: Self.counts(total: 65),
                projection: projection, model: "model-a", price: Self.price,
                hasValidatedPrice: true
            )],
            localTransitionEvidence: .init(models: ["model-a"], hasUnknownOrAmbiguousInterval: false)
        )
        #expect(laterRecorded)
        #expect(ledger.records.first { $0.attributionIntervalID == nil && $0.model == "model-a" }?.counts.totalTokens == 35)
        #expect(ledger.records.first { $0.attributionIntervalID == nil && $0.model == "model-a" }?.price == Self.price)
        #expect(ledger.records.first { $0.attributionIntervalID == "same-model-turn" }?.counts.totalTokens == 30)
    }

    @Test
    func keepsEachBoundedAToBToATransitionGapUnknown() throws {
        var ledger = APICostLedger()
        let initialRecorded = ledger.observe(
            sessionID: "a-b-a",
            summary: Self.summary(total: 30, interval: "a-initial", model: "model-a"),
            initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06",
            price: Self.price,
            localTransitionEvidence: .init(models: ["model-a"], hasUnknownOrAmbiguousInterval: false)
        )
        #expect(initialRecorded)
        for (model, total, preceding, id) in [("model-b", Int64(65), Int64(35), "b-turn"), ("model-a", Int64(100), Int64(70), "a-return-turn")] {
            let counts = Self.counts(total: 30)
            let projection = APICostLedger.AccountingProjection(
                projectKey: "TOSUMA", taskID: "TU3", localRole: "Coder", model: model,
                counts: counts, observedStart: Date(timeIntervalSince1970: 3), observedEnd: Date(timeIntervalSince1970: 4)
            )
            let transitionRecorded = ledger.observe(
                sessionID: "a-b-a",
                summary: Self.summary(total: total, interval: id, model: model),
                initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06",
                price: Self.price,
                intervalPartitions: [.init(
                    attributionIntervalID: id, counts: counts,
                    preceding: Self.counts(total: preceding), ending: Self.counts(total: total),
                    projection: projection, model: model, price: Self.price,
                    hasValidatedPrice: true
                )],
                localTransitionEvidence: .init(models: [model], hasUnknownOrAmbiguousInterval: false)
            )
            #expect(transitionRecorded)
        }
        #expect(ledger.records.first { $0.attributionIntervalID == nil && $0.model == "UNKNOWN" }?.counts.totalTokens == 10)
        #expect(ledger.records.filter { $0.attributionIntervalID != nil }.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 60)
        #expect(ledger.records.reduce(Int64(0)) { $0 + $1.counts.totalTokens } == 100)
    }

    @Test
    func doesNotAdvanceHighWaterOrDuplicateAnInvalidOrRepeatedPartition() throws {
        var ledger = APICostLedger()
        let invalid = ledger.observe(sessionID: "dedup", summary: Self.summary(total: 100, interval: "local-hint"), initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06", price: Self.price, intervalPartitions: [
            .init(attributionIntervalID: "same", counts: Self.counts(total: 60), preceding: Self.counts(total: 0), ending: Self.counts(total: 60)),
            .init(attributionIntervalID: "same", counts: Self.counts(total: 40), preceding: Self.counts(total: 60), ending: Self.counts(total: 100))
        ])
        #expect(!invalid)
        #expect(ledger.records.isEmpty)
        let accepted = ledger.observe(sessionID: "dedup", summary: Self.summary(total: 100, interval: "local-hint"), initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06", price: Self.price, intervalPartitions: [Self.partition("matched", total: 100)])
        #expect(accepted)
        let repeated = ledger.observe(sessionID: "dedup", summary: Self.summary(total: 100, interval: "local-hint"), initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06", price: Self.price, intervalPartitions: [.init(attributionIntervalID: "matched", counts: Self.counts(total: 100), preceding: Self.counts(total: 0), ending: Self.counts(total: 100))])
        #expect(!repeated)
        #expect(ledger.records.count == 1)
        #expect(ledger.records.first?.counts.totalTokens == 100)
    }

    @Test
    func decodesLegacyRecordsWithoutIntervalIdentity() throws {
        let data = Data("""
        {
          "schemaVersion": 1,
          "checkpoints": {},
          "records": [{
            "sessionID": "legacy",
            "usageDay": "2026-09-06",
            "model": "unknown-model",
            "counts": {
              "inputTokens": 25,
              "cachedInputTokens": 0,
              "outputTokens": 0,
              "totalTokens": 25
            },
            "price": null,
            "usd": 0
          }]
        }
        """.utf8)

        let ledger = try JSONDecoder().decode(APICostLedger.self, from: data)
        let record = try #require(ledger.records.first)
        let estimate = try #require(ledger.estimate(sevenDayKeys: ["2026-09-06"]))

        #expect(record.attributionIntervalID == nil)
        #expect(record.price == nil)
        #expect(estimate.observedTokens == 25)
        #expect(estimate.pricedTokens == 0)
        #expect(estimate.lifetimeUSD == 0)
    }

    @Test
    func preservesUnknownPriceForMatchedAndUnmatchedPartitions() throws {
        var ledger = APICostLedger()
        let recorded = ledger.observe(sessionID: "unknown-price", summary: Self.summary(total: 80, interval: "local-hint"), initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06", price: nil, intervalPartitions: [Self.partition("matched", total: 30)])
        #expect(recorded)
        let estimate = try #require(ledger.estimate(sevenDayKeys: ["2026-09-06"]))
        #expect(ledger.records.allSatisfy { $0.price == nil && $0.usd == 0 })
        #expect(estimate.observedTokens == 80)
        #expect(estimate.pricedTokens == 0)
        #expect(estimate.lifetimeUSD == 0)
    }

    @Test
    func persistsOnlyAcceptedImmutableProjectionAndNeverBackfillsPrice() throws {
        var ledger = APICostLedger()
        let counts = Self.counts(total: 20)
        let projection = APICostLedger.AccountingProjection(projectKey: "TOSUMA", taskID: "TU3", localRole: "Coder", model: "test-model", counts: counts, observedStart: Date(timeIntervalSince1970: 10), observedEnd: Date(timeIntervalSince1970: 20))
        let accepted = ledger.observe(sessionID: "ledger-projection", summary: Self.summary(total: 20, interval: "local"), initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06", price: nil, intervalPartitions: [.init(attributionIntervalID: "accepted", counts: counts, preceding: Self.counts(total: 0), ending: counts, projection: projection)])
        #expect(accepted)
        let laterPrice = ledger.observe(sessionID: "ledger-projection", summary: Self.summary(total: 20, interval: "local"), initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06", price: Self.price)
        #expect(!laterPrice)
        let record = try #require(ledger.records.first)
        #expect(record.projection == projection)
        #expect(record.price == nil)
        #expect(record.usd == 0)
    }

    @Test
    func rejectsAttributedPartitionWithoutImmutableMetadata() {
        var ledger = APICostLedger()
        let accepted = ledger.observe(sessionID: "missing-metadata", summary: Self.summary(total: 10, interval: "local"), initialUsageDay: "2026-09-06", incrementalUsageDay: "2026-09-06", price: Self.price, intervalPartitions: [.init(attributionIntervalID: "missing", counts: Self.counts(total: 10), preceding: Self.counts(total: 0), ending: Self.counts(total: 10))])
        #expect(!accepted)
        #expect(ledger.records.isEmpty)
    }

    private static func summary(total: Int64, interval: String, model: String = "test-model") -> SessionTokenSummary {
        SessionTokenSummary(
            model: model,
            inputTokens: total,
            cachedInputTokens: 0,
            outputTokens: 0,
            totalTokens: total,
            attributionIntervalID: interval
        )
    }

    private static let price = APIModelPrice(version: "test-price", displayName: "Test Model", inputPerMillion: 1, cachedInputPerMillion: 0.1, outputPerMillion: 6)

    private static func counts(total: Int64) -> TokenCounts {
        TokenCounts(inputTokens: total, cachedInputTokens: 0, outputTokens: 0, totalTokens: total)
    }
    private static func partition(_ id: String, total: Int64, precedingTotal: Int64 = 0) -> APICostLedger.IntervalPartition {
        let value = counts(total: total)
        return .init(attributionIntervalID: id, counts: value, preceding: counts(total: precedingTotal), ending: counts(total: precedingTotal + total), projection: .init(projectKey: "TOSUMA", taskID: "TU3", localRole: "Coder", model: "test-model", counts: value, observedStart: Date(timeIntervalSince1970: 1), observedEnd: Date(timeIntervalSince1970: 2)))
    }
}
