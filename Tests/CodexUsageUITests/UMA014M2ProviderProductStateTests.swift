import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.14 M2 provider product state")
struct UMA014M2ProviderProductStateTests {
    private let epoch = Date(timeIntervalSince1970: 1_788_134_400)

    @Test
    func catalogIsExactlyFourAdmittedProductsInStableOrder() {
        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: [],
            admissions: [],
            monitoringEnabledIDs: [],
            previousCards: [],
            language: .english,
            publicationRevision: 42,
            now: epoch
        )

        let productIDs: [ProviderProductID] = [
            .codex, .claude, .workBuddy, .antigravity,
        ]
        #expect(reduction.inventory.providers.map { $0.id } == productIDs)
        #expect(reduction.inventory.providers.allSatisfy { $0.inventory.providers })
        #expect(reduction.inventory.overviewProviders.isEmpty)
        #expect(reduction.inventory.publicationRevision == 42)
        #expect(ProviderProductStatePolicy.productID(
            for: AgentConnectorID(rawValue: "cursor.browser")!
        ) == nil)
        #expect(ProviderProductStatePolicy.productID(
            for: AgentConnectorID(rawValue: "kimi.browser")!
        ) == nil)
    }

    @Test
    func exactEstimatedAndMissingRemainDistinct() {
        let exact = usageSnapshot(
            id: CodexUsageConnector.connectorID,
            providerName: "untrusted name",
            remaining: 82,
            estimated: false
        )
        let estimated = usageSnapshot(
            id: ClaudeCodeUsageConnector.connectorID,
            providerName: "untrusted name",
            remaining: 82,
            estimated: true
        )
        let inventory = reduce([exact, estimated]).inventory

        let codex = inventory.provider(.codex)
        let claude = inventory.provider(.claude)
        #expect(codex?.primaryDisplayText == "82%")
        #expect(codex?.precision == .exact)
        #expect(codex?.displayName == "Codex")
        #expect(claude?.primaryDisplayText == "≈82%")
        #expect(claude?.precision == .estimated)
        #expect(inventory.provider(.antigravity)?.primaryDisplayText == "—")
        #expect(inventory.provider(.antigravity)?.primaryDisplayText != "0%")
    }

    @Test
    func axesRemainOrthogonalForStaleExactData() {
        let snapshot = usageSnapshot(
            id: CodexUsageConnector.connectorID,
            providerName: "Codex",
            remaining: 44,
            estimated: false,
            state: .stale,
            freshness: .stale,
            capabilities: [.refresh, .sanitizedLastValidRestore]
        )
        let product = reduce([snapshot]).inventory.provider(.codex)

        #expect(product?.precision == .exact)
        #expect(product?.freshness == .stale)
        #expect(product?.availability == .available)
        #expect(product?.connection == .connected)
        #expect(product?.health == .degraded)
        #expect(product?.primaryQuota?.comparison == .ineligible(.stale))
    }

    @Test
    func creditsStayNativeAndOnlyValidatedDenominatorEnablesComparison() throws {
        let rawCredits = try creditSnapshot(remaining: 30, used: nil, total: nil)
        let normalizedCredits = try creditSnapshot(remaining: 30, used: 70, total: 100)

        let raw = reduce([rawCredits]).inventory.provider(.workBuddy)?.primaryQuota
        let normalized = reduce([normalizedCredits]).inventory.provider(.workBuddy)?.primaryQuota

        guard case .remainingCredits(30, .credits) = raw?.value else {
            Issue.record("Expected native WorkBuddy Credit value")
            return
        }
        #expect(raw?.comparison == .ineligible(.nativeUnit))
        guard case .remainingCredits(30, .credits) = normalized?.value else {
            Issue.record("Expected normalized comparison to preserve native Credit display")
            return
        }
        #expect(normalized?.comparison == .eligibleRemainingPercent(30))
    }

    @Test
    func actionRequiredOutranksNumericQuotaAndStaleNeverWins() {
        let healthy = product(
            id: .codex,
            quota: quota(id: "codex", remaining: 9),
            health: .healthy
        )
        let setup = ProviderProductState(
            id: .claude,
            availability: .setupRequired,
            connection: .authenticationRequired,
            health: .needsAttention,
            requiredAction: .authenticate,
            actions: [.authenticate],
            inventory: .init(overview: true, assistant: true),
            isActive: true
        )
        let stale = product(
            id: .antigravity,
            quota: quota(id: "stale", remaining: 1, freshness: .stale),
            health: .degraded
        )

        let withAction = ProviderProductInventory(providers: [healthy, setup, stale])
        #expect(withAction.attentionPriority == .actionRequired(
            provider: .claude,
            action: .authenticate
        ))
        #expect(withAction.limitingFactor == .quota(
            provider: .codex,
            quotaID: "codex",
            remainingPercent: 9
        ))

        let withoutAction = ProviderProductInventory(providers: [healthy, stale])
        #expect(withoutAction.limitingFactor == .quota(
            provider: .codex,
            quotaID: "codex",
            remainingPercent: 9
        ))
    }

    @Test
    func disabledProviderRemainsInInventoryButCannotLeakLegacyCard() {
        let snapshot = usageSnapshot(
            id: CodexUsageConnector.connectorID,
            providerName: "Codex",
            remaining: 33,
            estimated: false
        )
        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: [snapshot],
            admissions: [],
            monitoringEnabledIDs: [],
            previousCards: [],
            language: .english,
            now: epoch
        )

        #expect(reduction.presentationCards.isEmpty)
        #expect(reduction.inventory.provider(.codex)?.availability == .disabled)
        #expect(reduction.inventory.provider(.codex)?.isActive == false)
        #expect(reduction.inventory.provider(.codex)?.inventory.providers == true)
    }

    @Test
    func authenticationRequiredIsVisibleAttentionButNotActive() {
        let snapshot = usageSnapshot(
            id: ClaudeCodeUsageConnector.connectorID,
            providerName: "Claude",
            remaining: 75,
            estimated: false,
            state: .authenticationRequired,
            freshness: .unavailable
        )
        let product = reduce([snapshot]).inventory.provider(.claude)

        #expect(product?.availability == .setupRequired)
        #expect(product?.connection == .authenticationRequired)
        #expect(product?.health == .needsAttention)
        #expect(product?.requiredAction == .authenticate)
        #expect(product?.inventory.overview == true)
        #expect(product?.isActive == false)
    }

    @Test
    func configuredOrDetectedProviderRemainsDiscoverableWithoutFakeUsage() {
        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: [],
            admissions: [],
            monitoringEnabledIDs: [GoogleAntigravityUsageConnector.connectorID],
            configuredOrDetectedIDs: [GoogleAntigravityUsageConnector.connectorID],
            previousCards: [],
            language: .english,
            now: epoch
        )
        let product = reduction.inventory.provider(.antigravity)

        #expect(product?.inventory.overview == true)
        #expect(product?.primaryDisplayText == "—")
        #expect(product?.primaryDisplayText != "0%")
        #expect(product?.isActive == false)
    }

    @Test
    func activeCountIsNotVisibleCardCountAndPreservesAutoMinimalistBoundary() {
        let invisible = ProviderProductState(
            id: .codex,
            availability: .available,
            connection: .connected,
            health: .healthy,
            inventory: .init(overview: false, assistant: false),
            isActive: true
        )
        let inventory = ProviderProductInventory(
            providers: [invisible],
            activeAgentCount: 5
        )

        #expect(inventory.overviewProviders.isEmpty)
        #expect(inventory.activeAgentCount == 5)
        #expect(inventory.usesAutomaticMinimalistMode)
        #expect(!ProviderProductInventory(
            providers: [invisible],
            activeAgentCount: 4
        ).usesAutomaticMinimalistMode)
    }

    @Test
    func acceptedMaximumDecrementPolicySelectsProductPrimaryQuota() {
        let initial = usageSnapshot(
            id: CodexUsageConnector.connectorID,
            providerName: "Codex",
            remaining: 60,
            secondRemaining: 50,
            estimated: false
        )
        let first = reduce([initial])
        let changed = usageSnapshot(
            id: CodexUsageConnector.connectorID,
            providerName: "Codex",
            remaining: 40,
            secondRemaining: 45,
            estimated: false,
            capturedAt: epoch.addingTimeInterval(60)
        )
        let second = reduce([changed], previousCards: first.presentationCards)

        #expect(second.presentationCards.first?.selectedWindowID == "five-hour")
        #expect(second.inventory.provider(.codex)?.primaryQuotaID == "five-hour-0")
        #expect(second.inventory.provider(.codex)?.primaryDisplayText == "40%")
    }

    @Test
    func projectionRejectsArbitraryProviderPlanWindowAndFailureText() {
        let snapshot = usageSnapshot(
            id: CodexUsageConnector.connectorID,
            providerName: "ACCOUNT PERSON <private@example.com>",
            remaining: 64,
            estimated: false,
            planLabel: "PrivateAccountSecret123",
            otherWindowLabel: "PrivateSessionSecret456"
        )
        let product = reduce([snapshot]).inventory.provider(.codex)

        #expect(product?.displayName == "Codex")
        #expect(product?.planLabel == nil)
        #expect(product?.quotas.last?.compactLabel == "Other")
        #expect(product?.sourceSummary == .officialLocal)
        #expect(product?.diagnosticReason == nil)
    }

    private func reduce(
        _ snapshots: [AgentUsageSnapshot],
        previousCards: [SharedUsageCardPresentation] = []
    ) -> ProviderProductReduction {
        ProviderProductStatePolicy.reduce(
            snapshots: snapshots,
            admissions: [],
            monitoringEnabledIDs: Set([
                CodexUsageConnector.connectorID,
                ClaudeCodeUsageConnector.connectorID,
                WorkBuddyAccountWebCreditsConnector.connectorID,
                GoogleAntigravityUsageConnector.connectorID,
            ]),
            previousCards: previousCards,
            language: .english,
            now: epoch
        )
    }

    private func usageSnapshot(
        id: AgentConnectorID,
        providerName: String,
        remaining: Double,
        secondRemaining: Double? = nil,
        estimated: Bool,
        state: AgentConnectorState = .ready,
        freshness: AgentConnectorFreshness = .fresh,
        capabilities: Set<AgentConnectorCapability> = [.refresh],
        capturedAt: Date? = nil,
        planLabel: String = "PRO",
        otherWindowLabel: String? = nil
    ) -> AgentUsageSnapshot {
        let isClaudeEstimate = id == ClaudeCodeUsageConnector.connectorID && estimated
        var windows = [
            AgentRateLimitWindow(
                id: "five-hour",
                kind: .fiveHour,
                usedPercent: 100 - remaining,
                isEstimated: estimated,
                isUnlimited: false,
                resetsAt: epoch.addingTimeInterval(3_600)
            )
        ]
        if let secondRemaining {
            windows.append(
                AgentRateLimitWindow(
                    id: "seven-day",
                    kind: .sevenDay,
                    usedPercent: 100 - secondRemaining,
                    isEstimated: estimated,
                    isUnlimited: false,
                    resetsAt: epoch.addingTimeInterval(604_800)
                )
            )
        }
        if let otherWindowLabel {
            windows.append(
                AgentRateLimitWindow(
                    id: "provider-private-identifier",
                    kind: .other,
                    displayLabel: otherWindowLabel,
                    usedPercent: 50,
                    isEstimated: estimated,
                    isUnlimited: false,
                    resetsAt: nil
                )
            )
        }
        let capturedAt = capturedAt ?? epoch
        return AgentUsageSnapshot(
            id: id,
            providerName: providerName,
            state: state,
            capturedAt: capturedAt,
            lastSuccessfulAt: capturedAt,
            freshness: freshness,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: isClaudeEstimate ? .authorizedLocalEstimate : .officialLocalService,
                    sourceVersion: isClaudeEstimate ? "smart-1-local-estimate" : "official-v1",
                    scopes: [.account],
                    provenance: isClaudeEstimate ? .locallyEstimated : .providerReported,
                    freshness: freshness,
                    capturedAt: capturedAt,
                    coverageNote: "must not project",
                    sourceConfidence: "must not project",
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
            capabilities: capabilities,
            safeFailure: nil
        )
    }

    private func creditSnapshot(
        remaining: Double,
        used: Double?,
        total: Double?
    ) throws -> AgentUsageSnapshot {
        let balance = try CreditBalance(
            validatingRemaining: remaining,
            used: used,
            total: total,
            scope: .buddyAISharedPersonal,
            observedAt: epoch,
            provenance: .authenticatedAccountWeb(observedAt: epoch)
        )
        return AgentUsageSnapshot(
            id: WorkBuddyAccountWebCreditsConnector.connectorID,
            providerName: "WorkBuddy",
            state: .ready,
            capturedAt: epoch,
            lastSuccessfulAt: epoch,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .authorizedReadOnlyRemote,
                    sourceVersion: "1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: epoch,
                    coverageNote: nil,
                    rateLimitWindows: [],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil,
                    availability: .credits(balance)
                )
            ],
            capabilities: [.refresh],
            safeFailure: nil
        )
    }

    private func quota(
        id: String,
        remaining: Double,
        freshness: ProviderProductFreshness = .fresh
    ) -> ProviderProductQuotaState {
        ProviderProductQuotaState(
            id: id,
            kind: .other,
            compactLabel: id,
            value: .remainingPercent(remaining),
            precision: .exact,
            freshness: freshness,
            comparison: freshness == .stale
                ? .ineligible(.stale)
                : .eligibleRemainingPercent(remaining),
            resetsAt: nil
        )
    }

    private func product(
        id: ProviderProductID,
        quota: ProviderProductQuotaState,
        health: ProviderProductHealth
    ) -> ProviderProductState {
        ProviderProductState(
            id: id,
            quotas: [quota],
            primaryQuotaID: quota.id,
            precision: quota.precision,
            freshness: quota.freshness,
            availability: .available,
            connection: .connected,
            health: health,
            actions: [.refresh],
            inventory: .init(overview: true, assistant: true),
            isActive: true
        )
    }
}
