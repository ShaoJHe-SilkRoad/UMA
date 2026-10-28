import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.14 M4R Codex quota-window truth")
struct UMA014M4RQuotaContractTests {
    private let epoch = Date(timeIntervalSince1970: 1_788_134_400)

    @Test("An explicitly unlimited 5H window is secondary to finite 7D")
    func explicitUnlimitedShortWindow() throws {
        let product = try codex([
            window(id: "provider-5h", kind: .fiveHour, unlimited: true),
            window(id: "provider-7d", kind: .sevenDay, remaining: 74),
        ])

        #expect(product.fiveHourStatus == .unlimited)
        #expect(product.quotas.map(\.kind) == [.sevenDay, .fiveHour])
        #expect(product.quotas.map(\.displayText) == ["74%", "∞"])
        #expect(product.primaryQuota?.kind == .sevenDay)
        #expect(product.compactQuotas.map(\.kind) == [.sevenDay, .fiveHour])
    }

    @Test("A missing 5H window stays absent instead of becoming unlimited")
    func absentShortWindow() throws {
        let product = try codex([
            window(id: "provider-7d", kind: .sevenDay, remaining: 63),
        ])

        #expect(product.fiveHourStatus == .absent)
        #expect(product.quotas.map(\.kind) == [.sevenDay])
        #expect(product.primaryDisplayText == "63%")
        #expect(!product.quotas.contains { $0.value == .unlimited })
    }

    @Test("The retired synthesized 5H sentinel cannot manufacture infinity")
    func inferredUnlimitedSentinelIsRejected() throws {
        let product = try codex([
            window(id: "five-hour-unlimited", kind: .fiveHour, unlimited: true),
            window(id: "provider-7d", kind: .sevenDay, remaining: 58),
        ])

        #expect(product.fiveHourStatus == .absent)
        #expect(product.quotas.map(\.kind) == [.sevenDay])
        #expect(product.primaryQuota?.kind == .sevenDay)
        #expect(product.primaryDisplayText == "58%")
    }

    @Test("Unknown 5H is detail-only while finite 7D remains usable")
    func unknownShortWindow() throws {
        let product = try codex([
            window(id: "provider-5h", kind: .fiveHour),
            window(id: "provider-7d", kind: .sevenDay, remaining: 52),
        ])

        #expect(product.fiveHourStatus == .unknown)
        #expect(product.quotas.map(\.kind) == [.sevenDay, .fiveHour])
        #expect(product.quotas.last?.value == .unavailable)
        #expect(product.quotas.last?.comparison == .ineligible(.missing))
        #expect(product.compactQuotas.map(\.kind) == [.sevenDay])
        #expect(product.primaryQuota?.kind == .sevenDay)
    }

    @Test("A finite 5H window leads when it is the real limiting window")
    func finiteShortWindow() throws {
        let product = try codex([
            window(id: "provider-7d", kind: .sevenDay, remaining: 76),
            window(id: "provider-5h", kind: .fiveHour, remaining: 21),
        ])

        #expect(product.fiveHourStatus == .finite)
        #expect(product.quotas.map(\.kind) == [.fiveHour, .sevenDay])
        #expect(product.quotas.map(\.displayText) == ["21%", "76%"])
        #expect(product.primaryQuota?.kind == .fiveHour)
    }

    @Test("A reported 100 percent 5H window remains finite")
    func hundredPercentIsNotInfinity() throws {
        let product = try codex([
            window(id: "provider-5h", kind: .fiveHour, remaining: 100),
        ])

        #expect(product.fiveHourStatus == .finite)
        #expect(product.quotas.count == 1)
        #expect(product.primaryDisplayText == "100%")
        #expect(product.primaryQuota?.value == .remainingPercent(100))
        #expect(product.primaryQuota?.value != .unlimited)
    }

    // Most-changeable rule: a low seven days no longer leads a five-hour
    // window on a first reading; the detail list still puts the lower first.
    @Test("The 5H window leads a first reading even when 7D is lower")
    func fiveHourLeadsFirstReading() throws {
        let product = try codex([
            window(id: "provider-5h", kind: .fiveHour, remaining: 91),
            window(id: "provider-7d", kind: .sevenDay, remaining: 13),
        ])

        #expect(product.quotas.map(\.kind) == [.sevenDay, .fiveHour])
        #expect(product.primaryQuota?.kind == .fiveHour)
        #expect(product.primaryDisplayText == "91%")
    }

    @Test("A spent 7D window leads")
    func spentSevenDayLeads() throws {
        let product = try codex([
            window(id: "provider-5h", kind: .fiveHour, remaining: 91),
            window(id: "provider-7d", kind: .sevenDay, remaining: 0),
        ])
        #expect(product.primaryQuota?.kind == .sevenDay)
        #expect(product.primaryDisplayText == "0%")
    }

    @Test("Plan labels cannot change quota classification or order")
    func planLabelDoesNotInferQuotaTruth() throws {
        let windows = [
            window(id: "provider-5h", kind: .fiveHour),
            window(id: "provider-7d", kind: .sevenDay, remaining: 44),
        ]
        let first = try codex(windows, planLabel: "Free")
        let renamed = try codex(windows, planLabel: "Renamed Future Plan")

        #expect(first.planLabel == nil)
        #expect(renamed.planLabel == nil)
        #expect(first.fiveHourStatus == .unknown)
        #expect(renamed.fiveHourStatus == .unknown)
        #expect(first.quotas == renamed.quotas)
        #expect(first.primaryQuotaID == renamed.primaryQuotaID)
    }

    @Test("Equal finite windows: weekly-first detail order, five-hour reading")
    func deterministicFiniteTieOrder() throws {
        let product = try codex([
            window(id: "provider-5h", kind: .fiveHour, remaining: 50),
            window(id: "provider-7d", kind: .sevenDay, remaining: 50),
        ])

        #expect(product.quotas.map(\.kind) == [.sevenDay, .fiveHour])
        #expect(product.primaryQuota?.kind == .fiveHour)
    }

    private func codex(
        _ windows: [AgentRateLimitWindow],
        planLabel: String = "Provider Plan"
    ) throws -> ProviderProductState {
        let snapshot = AgentUsageSnapshot(
            id: CodexUsageConnector.connectorID,
            providerName: "Codex",
            state: .ready,
            capturedAt: epoch,
            lastSuccessfulAt: epoch,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialLocalService,
                    sourceVersion: "official-v1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: epoch,
                    coverageNote: nil,
                    rateLimitWindows: windows,
                    accountMetrics: AgentAccountMetrics(
                        planLabel: planLabel,
                        availableResets: nil,
                        lifetimeTokens: nil,
                        sevenDayTokens: nil
                    ),
                    localActivityMetrics: nil,
                    safeFailure: nil
                )
            ],
            capabilities: [.refresh, .rateLimits],
            safeFailure: nil
        )
        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: [snapshot],
            admissions: [],
            monitoringEnabledIDs: [CodexUsageConnector.connectorID],
            configuredOrDetectedIDs: [CodexUsageConnector.connectorID],
            previousCards: [],
            language: .english,
            now: epoch
        )
        return try #require(reduction.inventory.provider(.codex))
    }

    private func window(
        id: String,
        kind: AgentRateLimitWindow.Kind,
        remaining: Double? = nil,
        unlimited: Bool = false
    ) -> AgentRateLimitWindow {
        AgentRateLimitWindow(
            id: id,
            kind: kind,
            usedPercent: remaining.map { 100 - $0 },
            isUnlimited: unlimited,
            resetsAt: nil
        )
    }
}
