import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5 Local Smart multi-provider acceptance")
struct M5DBGThreeProviderAcceptanceTests {
    @Test
    func providerOrderRemainsCodexClaudeWorkBuddy() {
        let ids = [
            AgentConnectorID(rawValue: "workbuddy.accountWebCredits")!,
            ClaudeCodeUsageConnector.connectorID,
            CodexUsageConnector.connectorID,
        ].sorted(by: AgentProviderOrder.precedes)
        #expect(ids.map(\.rawValue) == [
            "codex.local",
            "claude.browserSync",
            "workbuddy.accountWebCredits",
        ])
    }

    @Test
    func sharedPresentationKeepsClaudeParityAcrossBothSurfaces() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 44, seven: 71))
        let snapshot = await connector.currentSnapshot()
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .english,
            now: fixture.clock.now()
        )
        #expect(card.id == ClaudeCodeUsageConnector.connectorID.rawValue)
        #expect(card.providerName == "Claude Code")
        #expect(card.sourceDescription?.contains("Local Smart Mode") == true)
        #expect(card.isVisibleInDesktopAssistant)
        #expect(card.windows.map(\.remaining) == [.finite(56), .finite(29)])
        #expect(SharedUsagePresentationPolicy.assistantCards(from: [card]) == [card])
    }

    @Test
    func ambiguousAccuracyObservationRetainsCurrentExactWithoutFabrication() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 44, seven: 71))
        await connector.accuracySync()
        await fixture.bridge.reject(.malformedJSON)
        let retained = await connector.currentSnapshot()
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: retained,
            previous: nil,
            language: .english,
            now: fixture.clock.now()
        )
        #expect(card.freshness == .fresh)
        #expect(!card.isRetainingLastValidValue)
        #expect(card.windows.map(\.remaining) == [.finite(56), .finite(29)])
    }
}
