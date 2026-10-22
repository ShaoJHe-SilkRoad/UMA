import Foundation
import Testing
@testable import CodexUsageUI

/// A provider that has measured local activity but no exact quota anchor used
/// to be hidden entirely, because admission required an `.account` channel.
/// These cover the narrowed exception and, more importantly, that it cannot
/// admit anything which could be read as a quota.
@Suite("Local-activity-only admission", .timeLimit(.minutes(1)))
struct LocalActivityOnlyAdmissionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func localChannel(
        freshness: AgentConnectorFreshness = .fresh,
        windows: [AgentRateLimitWindow] = [],
        safeFailure: AgentSafeFailure? = nil
    ) -> AgentUsageChannel {
        AgentUsageChannel(
            id: .localActivity,
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "local-sanitized-1",
            scopes: [.session],
            provenance: .locallyEstimated,
            freshness: freshness,
            capturedAt: now,
            coverageNote: nil,
            sourceConfidence: "medium",
            rateLimitWindows: windows,
            accountMetrics: nil,
            localActivityMetrics: AgentLocalActivityMetrics(
                recentTaskCount: nil,
                recentTaskTokens: [],
                recentTaskCapturedAt: [],
                sessionTokens: 1_234_567,
                estimatedSevenDayUSD: 12.34,
                estimatedLifetimeUSD: 56.78,
                coveragePercent: 100,
                recognizedModelCount: 2
            ),
            safeFailure: safeFailure
        )
    }

    private func snapshot(
        channels: [AgentUsageChannel],
        state: AgentConnectorState = .ready,
        freshness: AgentConnectorFreshness = .fresh,
        safeFailure: AgentSafeFailure? = nil
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: ClaudeCodeUsageConnector.connectorID,
            providerName: "Claude Code",
            state: state,
            capturedAt: now,
            lastSuccessfulAt: now,
            freshness: freshness,
            channels: channels,
            capabilities: [],
            safeFailure: safeFailure
        )
    }

    private var claudeDescriptor: AgentConnectorDescriptor {
        ClaudeCodeUsageConnector.production().descriptor
    }

    private func isAdmitted(_ admission: ProviderSurfaceAdmission) -> Bool {
        if case .admitted = admission { return true }
        return false
    }

    @Test("Measured local activity alone is admitted")
    func localActivityOnlyIsAdmitted() {
        let admission = LocalProviderEligibilityScanner.admission(
            for: snapshot(channels: [localChannel()]),
            descriptor: claudeDescriptor
        )
        #expect(isAdmitted(admission))
    }

    // The whole point of the exception is that nothing can be read as a quota.
    // A local channel carrying a rate-limit window must stay out, or the
    // exception becomes a way to surface an unvalidated percentage.
    @Test("A local-only snapshot carrying a quota window is refused")
    func quotaBearingLocalOnlySnapshotIsRefused() {
        let window = AgentRateLimitWindow(
            id: "fiveHour",
            kind: .fiveHour,
            displayLabel: nil,
            usedPercent: 42,
            remainingPercent: 58,
            isEstimated: true,
            isUnlimited: false,
            resetsAt: now.addingTimeInterval(3_600)
        )
        let admission = LocalProviderEligibilityScanner.admission(
            for: snapshot(channels: [localChannel(windows: [window])]),
            descriptor: claudeDescriptor
        )
        #expect(!isAdmitted(admission))
    }

    @Test("A failing or stale local read stays hidden")
    func failedOrStaleLocalOnlyStaysHidden() {
        #expect(!isAdmitted(LocalProviderEligibilityScanner.admission(
            for: snapshot(channels: [localChannel(safeFailure: .unavailable)]),
            descriptor: claudeDescriptor
        )))
        #expect(!isAdmitted(LocalProviderEligibilityScanner.admission(
            for: snapshot(
                channels: [localChannel(freshness: .stale)],
                state: .stale,
                freshness: .stale
            ),
            descriptor: claudeDescriptor
        )))
    }

    // Providers that report an account channel must keep going through the
    // account path unchanged: the exception requires the account channel to be
    // absent, so it can never weaken account validation.
    @Test("An account-bearing snapshot is untouched by the exception")
    func accountBearingSnapshotIsUnaffected() {
        let unvalidatedAccount = AgentUsageChannel(
            id: .account,
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "fixture",
            scopes: [.account],
            provenance: .providerReported,
            freshness: .fresh,
            capturedAt: now,
            coverageNote: nil,
            sourceConfidence: nil,
            rateLimitWindows: [],
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: nil
        )
        // An account channel with no usable usage was refused before this
        // change and must still be refused, even though a local channel is
        // present alongside it.
        let admission = LocalProviderEligibilityScanner.admission(
            for: snapshot(channels: [unvalidatedAccount, localChannel()]),
            descriptor: claudeDescriptor
        )
        #expect(!isAdmitted(admission))
    }
}
