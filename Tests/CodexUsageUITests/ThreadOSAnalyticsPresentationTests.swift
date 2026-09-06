import Foundation
import Testing
@testable import CodexUsageUI

@MainActor struct ThreadOSAnalyticsPresentationTests {
    @Test func filtersOnlyExplicitHistoricalFieldsAndTreatsMissingModelAsUnknown() {
        let unknown = row(task: "TU3", role: "Coder", wave: nil, model: nil)
        let matched = row(task: "TU4", role: "Reviewer", wave: "wave-7", model: "gpt-6-astra")
        let rows = [unknown, matched]

        #expect(ThreadOSAnalyticsPresentation.filteredRows(rows, project: "tos", task: "tu4", role: "review", wave: "WAVE", model: "astra") == [matched])
        #expect(ThreadOSAnalyticsPresentation.filteredRows(rows, project: "", task: "TU3", role: "", wave: "", model: "unknown") == [unknown])
        #expect(ThreadOSAnalyticsPresentation.filteredRows(rows, project: "", task: "", role: "", wave: "missing", model: "") .isEmpty)
    }

    @Test func totalsExcludeUnknownTokenUnitsAndNeverTurnUnknownPriceIntoAValue() {
        let priced = row(task: "TU3", role: "Coder", wave: "wave-1", model: "gpt-6-astra", input: 10, cached: 2, output: 3, total: 15, price: 0.012, priceKnown: true)
        let unpriced = row(task: "TU4", role: "Reviewer", wave: "wave-2", model: "gpt-5.6-terra", input: 20, cached: 4, output: 6, total: 30, price: nil, priceKnown: false)
        let incomplete = row(task: "TU5", role: "QA", wave: "wave-3", model: nil)

        let totals = ThreadOSAnalyticsPresentation.totals([priced, unpriced, incomplete])
        #expect(totals == .init(input: 30, cached: 6, output: 9, total: 45, usd: 0.012, unknownPrice: 30, knownRows: 2, pricedRows: 1))
        #expect(ThreadOSAnalyticsPresentation.totals([]).knownRows == 0)
    }

    @Test func noDataAndEveryFailureStatusRemainExplicitRatherThanUsageClaims() {
        #expect(ThreadOSUsageAnalytics.sourceGap(now: Date(timeIntervalSince1970: 0)).rows.isEmpty)
        #expect(ThreadOSUsageAnalytics.sourceGap(now: Date(timeIntervalSince1970: 0)).sourceStatus == .sourceGap)
        #expect(ThreadOSUsageAnalytics.SourceStatus.allCasesForPresentation == [.available, .sourceGap, .unavailable, .truncated, .malformed])
    }

    @Test func decodesSnapshotsWithoutCoverageAsLegacyUnknownRatherThanZero() throws {
        let legacy = try JSONDecoder().decode(
            ThreadOSUsageAnalytics.self,
            from: Data(#"{"sourceStatus":"AVAILABLE","rows":[],"unavailableCount":3,"capturedAt":0}"#.utf8)
        )
        #expect(legacy.localLedgerCoverage == nil)
        #expect(legacy.unavailableCount == 3)
    }

    @Test func savedBindingIsTheOnlySupportedPreferenceSetupAndClearRemovesIt() {
        let preferences = ApplicationPreferences.inMemory()
        let binding = ThreadOSHistoricalAttributionBinding(
            interpreterPath: "/missing/interpreter",
            helperPath: "/missing/helper",
            runtimeRootPath: "/missing/runtime",
            journalPath: "/missing/journal.jsonl",
            projectKey: "TOSUMA",
            projectRootDigest: String(repeating: "a", count: 64),
            interpreterSHA256: String(repeating: "b", count: 64),
            helperSHA256: String(repeating: "c", count: 64),
            journalID: nil
        )
        ThreadOSHistoricalAttributionPreferences.save(binding, to: preferences)
        #expect(ThreadOSHistoricalAttributionPreferences.source(from: preferences).read(now: .distantPast).sourceStatus == .sourceGap)
        ThreadOSHistoricalAttributionPreferences.save(nil, to: preferences)
        #expect(ThreadOSHistoricalAttributionPreferences.source(from: preferences).read(now: .distantPast).sourceStatus == .sourceGap)
    }

    private func row(task: String, role: String, wave: String?, model: String?, input: Int64? = nil, cached: Int64? = nil, output: Int64? = nil, total: Int64? = nil, price: Double? = nil, priceKnown: Bool = false) -> ThreadOSUsageAnalytics.Row {
        .init(projectKey: "TOSUMA", projectRootDigest: String(repeating: "a", count: 64), taskID: task, localRole: role, threadDigest: String(repeating: "b", count: 64), turnDigest: task.padding(toLength: 64, withPad: "0", startingAt: 0), observation: "historical", waveID: wave, model: model, inputTokens: input, cachedInputTokens: cached, outputTokens: output, totalTokens: total, apiEquivalentUSD: price, isPriceKnown: priceKnown, intervalID: task)
    }
}

private extension ThreadOSUsageAnalytics.SourceStatus {
    static var allCasesForPresentation: [Self] { [.available, .sourceGap, .unavailable, .truncated, .malformed] }
}
