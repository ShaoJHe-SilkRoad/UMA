import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Founder Minimalist Credit rounding")
struct M2WMinimalistCreditRoundingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func compactFormatterUsesDeterministicHalfUpBoundaries() throws {
        let cases: [(String, String)] = [
            ("0", "0"),
            ("1", "1"),
            ("500", "500"),
            ("500.49", "500"),
            ("500.50", "501"),
            ("999.49", "999"),
            ("999.50", "1k"),
            ("1000", "1k"),
            ("1500", "1.5k"),
            ("2049.47", "2k"),
            ("2099.47", "2.1k"),
            ("50000", "50k"),
            ("999949", "999.9k"),
            ("999950", "1M"),
            ("1000000", "1M"),
        ]

        for (source, expected) in cases {
            let value = try #require(Decimal(string: source))
            #expect(CreditFormatter.compact(value) == expected)
        }
    }

    @Test
    func exactBalanceSurvivesDraftPersistenceAndDetailedPresentation() throws {
        let exact = try #require(Decimal(string: "2099.47"))
        let used = try #require(Decimal(string: "7900.53"))
        let observation = try WorkBuddyManualDraft(
            scope: .personalShared,
            tier: .standard,
            remainingText: "2099.47",
            companionField: .used,
            companionText: "7900.53"
        ).validated(at: now)

        #expect(observation.balance.remaining == exact)
        #expect(observation.balance.used == used)
        #expect(observation.balance.total == 10_000)
        #expect(
            abs((observation.balance.normalizedRemainingFraction ?? 0) - 0.209947)
                < 0.000_000_001
        )
        #expect(
            SharedUsagePresentationPolicy.availabilitySeverity(
                for: .credits(observation.balance)
            ) == .warning
        )

        let record = WorkBuddyManualPersistenceRecord(
            enabled: true,
            observation: observation
        )
        let decoded = try JSONDecoder().decode(
            WorkBuddyManualPersistenceRecord.self,
            from: JSONEncoder().encode(record)
        )
        #expect(decoded == record)
        #expect(decoded.observation?.balance.remaining == exact)
        #expect(
            WorkBuddyManualDraft.from(observation).remainingText == "2099.47"
        )

        let shared = sharedCard(balance: observation.balance)
        let availability = try #require(shared.availability)
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

        #expect(availability.exactCreditValue == exact)
        #expect(availability.compactText == "2.1k")
        #expect(availability.accessibilityText == "2,099.47 Credits remaining")
        #expect(main.compactValue == "2,099.47")
        #expect(main.availableText == "2,099.47 Credits available")
        #expect(main.balanceDetail == "7,900.53 used of 10,000 active")
        #expect(main.accessibilityLabel.contains("2,099.47 Credits available"))
        #expect(assistant.usageValue == .credits("2.1k"))
        #expect(assistant.usageText(for: .minimalist) == "2.1k")
        #expect(assistant.usageText(for: .regular) == "2,099.47")
        #expect(assistant.toolTip == main.accessibilityLabel)
        #expect(assistant.accessibilityLabel.contains("2,099.47 Credits available"))
        #expect(!assistant.accessibilityLabel.contains("2.1k"))
    }

    @Test
    func versionedPersistenceSeparatesLegacyIntegersFromCanonicalDecimals() throws {
        let exact = try #require(Decimal(string: "2099.47"))
        let balance = try CreditBalance(
            validatingDecimalRemaining: exact,
            scope: .buddyAIUnknown,
            observedAt: now,
            provenance: .manualConfirmed(at: now)
        )
        let encoded = try JSONEncoder().encode(
            AgentAvailabilityValue.credits(balance)
        )
        let decoded = try JSONDecoder().decode(
            AgentAvailabilityValue.self,
            from: encoded
        )
        #expect(decoded.creditBalance?.remaining == exact)

        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let balanceObject = try #require(object["balance"] as? [String: Any])
        #expect(balanceObject["schemaVersion"] as? Int == 2)
        #expect(balanceObject["remaining"] as? String == "2099.47")

        var legacyBalance = balanceObject
        legacyBalance["schemaVersion"] = 1
        legacyBalance["remaining"] = 500
        legacyBalance.removeValue(forKey: "used")
        legacyBalance.removeValue(forKey: "total")
        object["balance"] = legacyBalance
        let legacy = try JSONDecoder().decode(
            AgentAvailabilityValue.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
        #expect(legacy.creditBalance?.remaining == 500)

        var ambiguousLegacy = legacyBalance
        ambiguousLegacy["remaining"] = 2_099.47
        object["balance"] = ambiguousLegacy
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                AgentAvailabilityValue.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        var numericVersionTwo = balanceObject
        numericVersionTwo["remaining"] = 2_099.47
        object["balance"] = numericVersionTwo
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                AgentAvailabilityValue.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        var malformed = balanceObject
        malformed["remaining"] = "2099.47 Credits"
        object["balance"] = malformed
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                AgentAvailabilityValue.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        var excessive = balanceObject
        excessive["remaining"] = "0." + String(repeating: "1", count: 39)
        object["balance"] = excessive
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                AgentAvailabilityValue.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        var future = balanceObject
        future["schemaVersion"] = 3
        object["balance"] = future
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                AgentAvailabilityValue.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test
    func malformedAndExcessivePrecisionDraftsFailClosed() {
        for invalid in [
            "2099.47 Credits",
            "2,099.47",
            "0." + String(repeating: "1", count: 39),
        ] {
            #expect(throws: WorkBuddyManualValidationError.self) {
                try WorkBuddyManualDraft(
                    remainingText: invalid,
                    companionField: .none
                ).validated(at: now)
            }
        }
    }

    @Test
    func compactRoundingCannotCreateFillPercentOrSemanticMutation() throws {
        let exact = try #require(Decimal(string: "2099.47"))
        let balance = try CreditBalance(
            validatingDecimalRemaining: exact,
            scope: .buddyAIUnknown,
            observedAt: now,
            provenance: .manualConfirmed(at: now)
        )
        let shared = sharedCard(balance: balance)
        let assistant = DesktopAssistantCard(shared: shared)

        #expect(balance.remaining == exact)
        #expect(balance.used == nil)
        #expect(balance.total == nil)
        #expect(balance.normalizedRemainingFraction == nil)
        #expect(!balance.isExhausted)
        #expect(assistant.usageText(for: .minimalist) == "2.1k")
        #expect(!assistant.usageText(for: .minimalist).contains("%"))
        #expect(assistant.tintFraction == nil)
        #expect(assistant.severity == .neutral)
        #expect(shared.availability?.provenance == .manualConfirmed(at: now))

        let unavailable = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
            value: .unavailable,
            language: .english
        )
        #expect(unavailable.exactCreditValue == nil)
        #expect(unavailable.compactText == "—")
        #expect(unavailable.normalizedRemainingFraction == nil)
        #expect(unavailable.value == .unavailable)
    }

    private func sharedCard(balance: CreditBalance) -> SharedUsageCardPresentation {
        SharedUsageCardPresentation(
            id: WorkBuddyManualPersistenceRecord.connectorID,
            providerName: "WorkBuddy",
            planLabel: WorkBuddyPlanTier.standard.rawValue,
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
}
