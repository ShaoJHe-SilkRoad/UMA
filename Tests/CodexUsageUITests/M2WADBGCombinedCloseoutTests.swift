import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2WADBG-G1 combined closeout")
struct M2WADBGCombinedCloseoutTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func roadmapOrderIsStableAcrossMainAndAssistantPresentation() {
        let identities = [
            "doubao.usage",
            "kimi.plus",
            "cursor.usage",
            "manus.api",
            "workbuddy.manualAvailability",
            "claude.code",
            "codex.local",
        ]
        let expected = [
            "codex.local",
            "claude.code",
            "workbuddy.manualAvailability",
            "manus.api",
            "cursor.usage",
            "kimi.plus",
            "doubao.usage",
        ]
        let snapshots = identities.enumerated().map { index, id in
            placeholderSnapshot(
                id: id,
                capturedAt: now.addingTimeInterval(Double(index))
            )
        }
        let mainCards = SharedUsagePresentationPolicy.makeCards(
            snapshots: snapshots,
            previousCards: [],
            language: .english,
            now: now
        )
        #expect(mainCards.map(\.id) == expected)
        #expect(
            SharedUsagePresentationPolicy.assistantCards(
                from: Array(mainCards.reversed())
            ).map(\.id) == expected
        )

        #expect(
            AgentProviderOrder.priority(
                for: AgentConnectorID(rawValue: "workbuddy.manualAvailability")!
            )
                < AgentProviderOrder.priority(
                    for: AgentConnectorID(rawValue: "manus.api")!
                )
        )
        #expect(
            AgentProviderOrder.priority(
                for: AgentConnectorID(rawValue: "claude.code")!
            )
                < AgentProviderOrder.priority(
                    for: AgentConnectorID(rawValue: "workbuddy.manualAvailability")!
                )
        )
    }

    @Test
    func mainAndAssistantUseOneExactManualPresentationAcrossCreditMatrix() throws {
        let cases: [CreditCase] = [
            .init(remaining: 500, used: 0, total: 500),
            .init(remaining: 500, used: nil, total: nil),
            .init(remaining: 3_600, used: 400, total: 4_000),
            .init(remaining: 4_500, used: 4_500, total: 9_000),
            .init(remaining: 50_000, used: nil, total: 50_000),
            .init(remaining: 200_000, used: nil, total: nil),
            .init(remaining: 100, used: 0, total: 100),
            .init(remaining: 50, used: 50, total: 100),
            .init(remaining: 26, used: 74, total: 100),
            .init(remaining: 25, used: 75, total: 100),
            .init(remaining: 11, used: 89, total: 100),
            .init(remaining: 10, used: 90, total: 100),
            .init(remaining: 1, used: 99, total: 100),
            .init(remaining: 0, used: 100, total: 100),
            .init(
                remaining: 500,
                used: 0,
                total: 500,
                scope: .buddyAIEnterpriseShared,
                planTier: .enterprise,
                planLabel: WorkBuddyPlanTier.enterprise.rawValue
            ),
            .init(
                remaining: 500,
                used: nil,
                total: nil,
                scope: .buddyAIUnknown,
                planTier: nil,
                planLabel: WorkBuddyPlanTier.unknown.rawValue
            ),
        ]

        for testCase in cases {
            let shared = try manualCard(testCase)
            let main = try #require(
                WorkBuddyMainPanelPresentation.make(
                    card: shared,
                    language: .english,
                    now: now
                )
            )
            let assistant = DesktopAssistantCard(
                shared: shared,
                language: .english
            )

            #expect(shared.id == WorkBuddyManualPersistenceRecord.connectorID)
            #expect(assistant.id == shared.id)
            #expect(assistant.usageValue.displayText == main.compactValue)
            #expect(assistant.tintFraction == main.remainingFraction)
            #expect(assistant.sourceMark == .manual)
            #expect(assistant.accessibilityLabel == main.accessibilityLabel)
            #expect(assistant.toolTip == main.accessibilityLabel)
            #expect(!assistant.usageValue.displayText.contains("%"))
            #expect(!main.compactValue.contains("%"))
            if testCase.total == nil {
                #expect(assistant.tintFraction == nil)
                #expect(assistant.severity == .neutral)
            }
        }
    }

    @Test
    func lifecycleStatesRemainSemanticallyIdenticalAcrossBothSurfaces() throws {
        let configured = try manualCard(
            .init(remaining: 500, used: 0, total: 500)
        )
        let exhausted = try manualCard(
            .init(remaining: 0, used: 500, total: 500)
        )
        let unconfigured = lifecycleCard(.unconfigured)
        let invalid = lifecycleCard(
            .invalid,
            availability: SharedUsagePresentationPolicy.makeAvailabilityPresentation(
                value: .invalid(reason: .unsupportedSchema),
                language: .english
            )
        )
        let unavailable = lifecycleCard(.unavailable)

        for shared in [
            configured,
            exhausted,
            unconfigured,
            invalid,
            unavailable,
        ] {
            let main = try #require(
                WorkBuddyMainPanelPresentation.make(
                    card: shared,
                    language: .english,
                    now: now
                )
            )
            let assistant = DesktopAssistantCard(
                shared: shared,
                language: .english
            )
            #expect(assistant.accessibilityLabel == main.accessibilityLabel)
            #expect(assistant.usageValue.displayText == main.compactValue)
            #expect(assistant.tintFraction == main.remainingFraction)
        }

        #expect(
            DesktopAssistantCard(shared: unconfigured).usageValue == .unavailable
        )
        #expect(
            DesktopAssistantCard(shared: invalid).usageValue == .unavailable
        )
        #expect(
            DesktopAssistantCard(shared: unavailable).usageValue == .unavailable
        )
        #expect(
            DesktopAssistantCard(shared: exhausted).usageValue == .credits("0")
        )
    }

    @Test
    func boundedManualOperationAndRefreshMatrixHasExactWriteOwnership() async throws {
        let directory = temporaryDirectory("manual-matrix")
        defer { try? FileManager.default.removeItem(at: directory) }
        let manualURL = directory.appendingPathComponent("manual.json")
        let genericURL = directory.appendingPathComponent("snapshots.json")
        let persistence = WorkBuddyManualAvailabilityStore(fileURL: manualURL)
        let clock = TestClock(now)
        let source = ManualWorkBuddyAvailabilitySource(
            store: persistence,
            now: { clock.value }
        )
        let connector = WorkBuddyAvailabilityConnector(source: source)
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            snapshotStore: AgentConnectorSnapshotStore(url: genericURL)
        )

        _ = await source.load()
        for index in 0..<20 {
            clock.value = now.addingTimeInterval(Double(index + 1))
            #expect(
                try await source.save(
                    observation(
                        remaining: Int64(500 - index),
                        used: Int64(index),
                        at: clock.value
                    )
                )
            )
        }
        for index in 0..<10 {
            clock.value = now.addingTimeInterval(Double(100 + index))
            #expect(try await source.confirmUnchanged(at: clock.value))
        }
        for _ in 0..<5 {
            #expect(try await source.setEnabled(false))
            #expect(try await source.setEnabled(true))
        }
        for index in 0..<5 {
            #expect(try await source.clear())
            clock.value = now.addingTimeInterval(Double(200 + index))
            #expect(
                try await source.save(
                    observation(
                        remaining: Int64(500 - index),
                        used: Int64(index),
                        at: clock.value
                    )
                )
            )
        }

        #expect(await persistence.writeCount == 50)
        #expect(await source.publicationCount == 51)
        let writesBeforeRefresh = await persistence.writeCount
        let publicationsBeforeRefresh = await source.publicationCount
        let confirmedBeforeRefresh = try #require(
            (await source.currentState()).observation?.balance.observedAt
        )

        await registry.startPassiveConnectors()
        for _ in 0..<20 {
            try await registry.refresh(connector.id, trigger: .manual)
        }

        #expect(await persistence.writeCount == writesBeforeRefresh)
        #expect(await source.publicationCount == publicationsBeforeRefresh)
        #expect(
            (await source.currentState()).observation?.balance.observedAt
                == confirmedBeforeRefresh
        )
        #expect(!FileManager.default.fileExists(atPath: genericURL.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: genericURL.appendingPathExtension("backup").path
            )
        )
        await registry.stopAll()
    }

    private struct CreditCase {
        let remaining: Int64
        let used: Int64?
        let total: Int64?
        let scope: CreditScope
        let planTier: CreditPlanTier?
        let planLabel: String

        init(
            remaining: Int64,
            used: Int64?,
            total: Int64?,
            scope: CreditScope = .buddyAISharedPersonal,
            planTier: CreditPlanTier? = .personal,
            planLabel: String = WorkBuddyPlanTier.experience.rawValue
        ) {
            self.remaining = remaining
            self.used = used
            self.total = total
            self.scope = scope
            self.planTier = planTier
            self.planLabel = planLabel
        }
    }

    private final class TestClock: @unchecked Sendable {
        var value: Date
        init(_ value: Date) { self.value = value }
    }

    private func manualCard(
        _ testCase: CreditCase
    ) throws -> SharedUsageCardPresentation {
        let balance = try CreditBalance(
            validatingRemaining: testCase.remaining,
            used: testCase.used,
            total: testCase.total,
            scope: testCase.scope,
            planTier: testCase.planTier,
            nextExpiryAt: now.addingTimeInterval(86_400),
            observedAt: now,
            provenance: .manualConfirmed(at: now)
        )
        return SharedUsageCardPresentation(
            id: WorkBuddyManualPersistenceRecord.connectorID,
            providerName: "WorkBuddy",
            planLabel: testCase.planLabel,
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
            capturedAt: now
        )
    }

    private func lifecycleCard(
        _ lifecycle: SharedAvailabilityLifecycle,
        availability: SharedAvailabilityPresentation? = nil
    ) -> SharedUsageCardPresentation {
        SharedUsageCardPresentation(
            id: WorkBuddyManualPersistenceRecord.connectorID,
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

    private func placeholderSnapshot(
        id: String,
        capturedAt: Date
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: id)!,
            providerName: id,
            state: .inactive,
            capturedAt: capturedAt,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: [],
            safeFailure: nil
        )
    }

    private func observation(
        remaining: Int64,
        used: Int64,
        at date: Date
    ) throws -> WorkBuddyManualObservation {
        try WorkBuddyManualDraft(
            scope: .personalShared,
            tier: .experience,
            remainingText: String(remaining),
            companionField: .used,
            companionText: String(used)
        ).validated(at: date)
    }

    private func temporaryDirectory(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "M2WADBGCombinedCloseoutTests-\(label)-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}
