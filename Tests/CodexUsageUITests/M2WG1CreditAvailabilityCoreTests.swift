import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2W-G1 Credit availability core")
struct M2WG1CreditAvailabilityCoreTests {
    private let observedAt = Date(timeIntervalSince1970: 1_784_332_800)

    @Test
    func percentageValidationAndPresentationRemainExplicit() throws {
        for value in [0.0, 1, 9, 10, 11, 25, 26, 50, 98, 100] {
            let availability = AgentAvailabilityValue.validatingPercentage(value)
            guard case let .percentage(percentage) = availability else {
                Issue.record("Valid percentage became invalid: \(value)")
                continue
            }
            #expect(percentage.value == value)
            #expect(availability.normalizedRemainingFraction == value / 100)
            let presentation = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
                value: availability,
                language: .english
            )
            #expect(presentation.compactText == "\(Int(value))%")
            #expect(presentation.displayUnit == nil)
            #expect(presentation.exactCreditValue == nil)
        }

        for value in [Double.nan, .infinity, -.infinity, -1, 101] {
            guard case .invalid = AgentAvailabilityValue.validatingPercentage(value) else {
                Issue.record("Invalid percentage was accepted: \(value)")
                continue
            }
        }

        let legacy = SharedRemainingValue.finite(44)
        let legacyRoundTrip = try JSONDecoder().decode(
            SharedRemainingValue.self,
            from: JSONEncoder().encode(legacy)
        )
        #expect(legacyRoundTrip == legacy)
        #expect(legacyRoundTrip.displayText == "44%")
    }

    @Test
    func absoluteCreditsAndCompactFormattingCoverRequiredValues() throws {
        let expected: [(Int64, String)] = [
            (0, "0"),
            (1, "1"),
            (10, "10"),
            (500, "500"),
            (3_600, "3.6k"),
            (4_000, "4k"),
            (9_000, "9k"),
            (50_000, "50k"),
            (200_000, "200k"),
        ]

        for (remaining, compact) in expected {
            let balance = try balance(remaining: remaining)
            let presentation = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
                value: .credits(balance),
                language: .english
            )
            #expect(CreditFormatter.compact(remaining) == compact)
            #expect(presentation.compactText == compact)
            #expect(presentation.exactCreditValue == remaining)
            #expect(presentation.displayUnit == .credits)
            #expect(!presentation.compactText.contains("%"))
            #expect(presentation.accessibilityText.contains("Credits"))
        }

        let maximum = try balance(remaining: Int64.max)
        #expect(maximum.remaining == Int64.max)
        #expect(maximum.normalizedRemainingFraction == nil)
    }

    @Test
    func creditValidationRejectsInvalidAndOverflowingSourceValues() throws {
        #expect(throws: AgentAvailabilityValidationError.negativeCredits) {
            try balance(remaining: -1)
        }
        #expect(throws: AgentAvailabilityValidationError.totalMustBePositive) {
            try balance(remaining: 0, total: 0)
        }
        #expect(throws: AgentAvailabilityValidationError.remainingExceedsTotal) {
            try balance(remaining: 101, total: 100)
        }
        #expect(throws: AgentAvailabilityValidationError.usedExceedsTotal) {
            try balance(remaining: 10, used: 101, total: 100)
        }
        #expect(throws: AgentAvailabilityValidationError.inconsistentCreditValues) {
            try balance(remaining: 40, used: 50, total: 100)
        }
        #expect(throws: AgentAvailabilityValidationError.arithmeticOverflow) {
            try balance(remaining: Int64.max, used: 1)
        }
        #expect(throws: AgentAvailabilityValidationError.nonFiniteNumber) {
            try doubleBalance(remaining: .infinity)
        }
        #expect(throws: AgentAvailabilityValidationError.nonFiniteNumber) {
            try doubleBalance(remaining: .nan)
        }
        #expect(throws: AgentAvailabilityValidationError.nonIntegralCredits) {
            try doubleBalance(remaining: 3.5)
        }
        #expect(throws: AgentAvailabilityValidationError.creditsOutOfRange) {
            try doubleBalance(remaining: Double(Int64.max))
        }

        let invalidSource = AgentAvailabilityValue.validatingCredits(
            remaining: -1,
            scope: .buddyAISharedPersonal,
            observedAt: observedAt,
            provenance: .manualConfirmed(at: observedAt)
        )
        #expect(invalidSource == .invalid(reason: .negativeCredits))

        let consistent = try balance(remaining: 40, used: 60, total: 100)
        #expect(consistent.normalizedRemainingFraction == 0.4)
    }

    @Test
    func fractionsUseOnlyExplicitOrSameBalanceTotals() throws {
        let explicit = try balance(remaining: 25, total: 100)
        #expect(explicit.derivedTotal == 100)
        #expect(explicit.normalizedRemainingFraction == 0.25)

        let derived = try balance(remaining: 40, used: 60)
        #expect(derived.derivedTotal == 100)
        #expect(derived.normalizedRemainingFraction == 0.4)

        let missing = try balance(remaining: 500)
        #expect(missing.derivedTotal == nil)
        #expect(missing.normalizedRemainingFraction == nil)
        #expect(
            SharedUsagePresentationPolicy.availabilitySeverity(for: .credits(missing))
                == .neutral
        )

        let tierOnly = try CreditBalance(
            validatingRemaining: Int64(500),
            scope: .buddyAIEnterpriseShared,
            planTier: .enterprise,
            observedAt: observedAt,
            provenance: .manualConfirmed(at: observedAt)
        )
        #expect(tierOnly.derivedTotal == nil)
        #expect(tierOnly.normalizedRemainingFraction == nil)

        let exhaustedWithoutTotal = try balance(remaining: 0)
        #expect(exhaustedWithoutTotal.normalizedRemainingFraction == nil)
        #expect(
            SharedUsagePresentationPolicy.availabilitySeverity(for: .credits(exhaustedWithoutTotal))
                == .exhausted
        )
    }

    @Test
    func fractionSeverityReusesCentralBoundaries() throws {
        let matrix: [(Int64, AgentAvailabilitySeverity)] = [
            (100, .available),
            (50, .available),
            (26, .available),
            (25, .warning),
            (11, .warning),
            (10, .critical),
            (1, .critical),
            (0, .exhausted),
        ]

        for (remaining, expected) in matrix {
            let value = AgentAvailabilityValue.credits(
                try balance(remaining: remaining, total: 100)
            )
            #expect(
                SharedUsagePresentationPolicy.availabilitySeverity(for: value) == expected
            )
        }
    }

    @Test
    func provenanceAndSharedPoolIdentityRemainIndependent() throws {
        let manual = AvailabilityProvenance.manualConfirmed(at: observedAt)
        let official = AvailabilityProvenance.officialStructured(observedAt: observedAt)
        #expect(!manual.isLiveStructuredSource)
        #expect(official.isLiveStructuredSource)
        let officialBalance = try CreditBalance(
            validatingRemaining: Int64(500),
            scope: .buddyAISharedPersonal,
            observedAt: observedAt,
            provenance: official
        )
        #expect(AgentAvailabilityValue.credits(officialBalance).sourceState == .officialStructured)

        let personal = CreditScope.buddyAISharedPersonal
        let enterprise = CreditScope.buddyAIEnterpriseShared
        let unknown = CreditScope.buddyAIUnknown
        #expect(personal.kind != enterprise.kind)
        #expect(enterprise.kind != unknown.kind)
        #expect(personal.poolIdentity == .buddyAISharedCredits)
        #expect(enterprise.poolIdentity == .buddyAISharedCredits)
        #expect(unknown.poolIdentity == .buddyAISharedCredits)

        let unrelatedIdentity = try #require(
            CreditPoolIdentity(rawValue: "future.sharedCredits")
        )
        #expect(unrelatedIdentity != .buddyAISharedCredits)
        let unrelated = try #require(
            CreditScope(kind: .other, poolIdentity: unrelatedIdentity)
        )
        #expect(unrelated != unknown)
        #expect(CreditScope(kind: .buddyAIUnknown, poolIdentity: unrelatedIdentity) == nil)
        #expect(CreditScope(kind: .other, poolIdentity: .buddyAISharedCredits) == nil)

        let malformedIdentity = Data(#"{"rawValue":"not valid"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CreditPoolIdentity.self, from: malformedIdentity)
        }
        let oversizedValue = "a." + String(repeating: "b", count: 63)
        #expect(oversizedValue.utf8.count > CreditPoolIdentity.maximumLength)
        let oversizedIdentity = try JSONEncoder().encode(["rawValue": oversizedValue])
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CreditPoolIdentity.self, from: oversizedIdentity)
        }
        let mismatchedScope = Data(
            #"{"kind":"buddyAIUnknown","poolIdentity":{"rawValue":"future.sharedCredits"}}"#.utf8
        )
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CreditScope.self, from: mismatchedScope)
        }
    }

    @Test
    func formattingIsExactAccessibleAndLocaleSafe() throws {
        let value: Int64 = 3_600
        let english = CreditFormatter.accessibilityRemaining(value, language: .english)
        let chinese = CreditFormatter.accessibilityRemaining(value, language: .simplifiedChinese)
        #expect(english == "3,600 Credits remaining")
        #expect(chinese == "剩余 3,600 Credits")
        #expect(!english.contains("%"))
        #expect(!chinese.contains("%"))

        let chinesePresentation = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
            value: .credits(try balance(remaining: value)),
            language: .simplifiedChinese
        )
        #expect(chinesePresentation.compactText == "3.6k")
        #expect(chinesePresentation.accessibilityText == "剩余 3,600 Credits")

        let unavailable = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
            value: .unavailable,
            language: .english
        )
        let invalid = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
            value: .invalid(reason: .inconsistentCreditValues),
            language: .english
        )
        #expect(unavailable.compactText == "—")
        #expect(unavailable.exactCreditValue == nil)
        #expect(invalid.severity == .invalid)
    }

    @Test
    func creditCodableRoundTripsAndFailsClosed() throws {
        let original = AgentAvailabilityValue.credits(
            try CreditBalance(
                validatingRemaining: Int64(3_600),
                used: Int64(400),
                total: Int64(4_000),
                scope: .buddyAISharedPersonal,
                planTier: .personal,
                nextExpiryAt: observedAt.addingTimeInterval(86_400),
                observedAt: observedAt,
                provenance: .manualConfirmed(at: observedAt)
            )
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentAvailabilityValue.self, from: encoded)
        #expect(decoded == original)
        let golden = Data(
            """
            {
              "schemaVersion": 1,
              "kind": "credits",
              "balance": {
                "schemaVersion": 1,
                "remaining": 3600,
                "used": 400,
                "total": 4000,
                "unit": "credits",
                "scope": {
                  "kind": "buddyAISharedPersonal",
                  "poolIdentity": {"rawValue": "buddyAI.sharedCredits"}
                },
                "planTier": "personal",
                "nextExpiryAt": 806112000,
                "observedAt": 806025600,
                "provenance": {"manualConfirmed": {"at": 806025600}}
              }
            }
            """.utf8
        )
        #expect(
            try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
                == JSONSerialization.jsonObject(with: golden) as? NSDictionary
        )

        guard var futureObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        else {
            Issue.record("Availability encoding was not a keyed object")
            return
        }
        futureObject["schemaVersion"] = 2
        let futureData = try JSONSerialization.data(withJSONObject: futureObject)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AgentAvailabilityValue.self, from: futureData)
        }

        guard var availabilityObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var balanceObject = availabilityObject["balance"] as? [String: Any] else {
            Issue.record("Credit encoding did not contain a balance object")
            return
        }
        var futureBalanceObject = balanceObject
        futureBalanceObject["schemaVersion"] = 2
        availabilityObject["balance"] = futureBalanceObject
        let futureBalanceData = try JSONSerialization.data(withJSONObject: availabilityObject)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AgentAvailabilityValue.self, from: futureBalanceData)
        }

        balanceObject["remaining"] = -1
        availabilityObject["balance"] = balanceObject
        let corruptData = try JSONSerialization.data(withJSONObject: availabilityObject)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AgentAvailabilityValue.self, from: corruptData)
        }

        let unavailable = AgentAvailabilityValue.unavailable
        let unavailableRoundTrip = try JSONDecoder().decode(
            AgentAvailabilityValue.self,
            from: JSONEncoder().encode(unavailable)
        )
        #expect(unavailableRoundTrip == .unavailable)
        #expect(unavailableRoundTrip.creditBalance == nil)

        let omittedOptionals = Data(
            """
            {
              "schemaVersion": 1,
              "kind": "credits",
              "balance": {
                "schemaVersion": 1,
                "remaining": 500,
                "unit": "credits",
                "scope": {
                  "kind": "buddyAISharedPersonal",
                  "poolIdentity": {"rawValue": "buddyAI.sharedCredits"}
                },
                "observedAt": 806025600,
                "provenance": {"manualConfirmed": {"at": 806025600}}
              }
            }
            """.utf8
        )
        let sparse = try JSONDecoder().decode(AgentAvailabilityValue.self, from: omittedOptionals)
        #expect(sparse.creditBalance?.remaining == 500)
        #expect(sparse.creditBalance?.used == nil)
        #expect(sparse.creditBalance?.total == nil)
        #expect(sparse.creditBalance?.planTier == nil)
        #expect(sparse.creditBalance?.nextExpiryAt == nil)
        #expect(sparse.normalizedRemainingFraction == nil)
    }

    @Test
    func optionalChannelAvailabilityPreservesLegacyAndNewCodableShapes() throws {
        let legacyChannel = channel(availability: nil)
        let legacyData = try JSONEncoder().encode(legacyChannel)
        let legacyText = String(decoding: legacyData, as: UTF8.self)
        #expect(!legacyText.contains("\"availability\""))
        #expect(try JSONDecoder().decode(AgentUsageChannel.self, from: legacyData) == legacyChannel)

        let creditValue = AgentAvailabilityValue.credits(try balance(remaining: 500))
        let creditChannel = channel(availability: creditValue)
        let creditRoundTrip = try JSONDecoder().decode(
            AgentUsageChannel.self,
            from: JSONEncoder().encode(creditChannel)
        )
        #expect(creditRoundTrip.availability == creditValue)
    }

    @Test
    func sharedCardCarriesCreditsWithoutInventingAPercentageWindow() throws {
        let manualSnapshot = snapshot(
            state: .inactive,
            freshness: .unavailable,
            capturedAt: observedAt,
            availability: .credits(try balance(remaining: 3_600))
        )
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: manualSnapshot,
            previous: nil,
            language: .english,
            now: observedAt
        )
        #expect(card.windows.isEmpty)
        #expect(card.selectedWindowID == nil)
        #expect(card.remaining == .unavailable)
        #expect(card.availability?.compactText == "3.6k")
        #expect(card.availability?.normalizedRemainingFraction == nil)
        #expect(card.availability?.provenance?.isLiveStructuredSource == false)
        #expect(card.availability?.sourceState == .manualConfirmed)
        #expect(card.connectionStatus == .disconnected)
        #expect(card.freshness == .unavailable)
        #expect(manualSnapshot.channels.first?.sourceTier == .manualUserConfirmed)
        #expect(manualSnapshot.channels.first?.provenance == .manualConfirmed)

        let readyManual = snapshot(
            state: .ready,
            freshness: .fresh,
            capturedAt: observedAt.addingTimeInterval(30),
            availability: .credits(try balance(remaining: 3_600))
        )
        let guardedManual = SharedUsagePresentationPolicy.makeCard(
            snapshot: readyManual,
            previous: nil,
            language: .english,
            now: observedAt.addingTimeInterval(30)
        )
        #expect(guardedManual.availability?.sourceState == .manualConfirmed)
        #expect(guardedManual.connectionStatus == .disconnected)
        #expect(guardedManual.freshness == .unavailable)

        let updatedManualSnapshot = snapshot(
            state: .inactive,
            freshness: .unavailable,
            capturedAt: observedAt.addingTimeInterval(45),
            availability: .credits(try balance(remaining: 3_200))
        )
        let updatedManual = SharedUsagePresentationPolicy.makeCard(
            snapshot: updatedManualSnapshot,
            previous: card,
            language: .english,
            now: observedAt.addingTimeInterval(45)
        )
        #expect(updatedManual.availability?.exactCreditValue == 3_200)
        #expect(!updatedManual.isRetainingLastValidValue)
        #expect(updatedManual.connectionStatus == .disconnected)
        #expect(updatedManual.freshness == .unavailable)

        let failed = snapshot(
            state: .failed,
            freshness: .unavailable,
            capturedAt: observedAt.addingTimeInterval(60),
            availability: nil
        )
        let retained = SharedUsagePresentationPolicy.makeCard(
            snapshot: failed,
            previous: updatedManual,
            language: .english,
            now: observedAt.addingTimeInterval(60)
        )
        #expect(retained.availability == updatedManual.availability)
        #expect(retained.isRetainingLastValidValue)
        #expect(retained.connectionStatus == .failed)
    }

    private func balance(
        remaining: Int64,
        used: Int64? = nil,
        total: Int64? = nil
    ) throws -> CreditBalance {
        try CreditBalance(
            validatingRemaining: remaining,
            used: used,
            total: total,
            scope: .buddyAISharedPersonal,
            observedAt: observedAt,
            provenance: .manualConfirmed(at: observedAt)
        )
    }

    private func doubleBalance(
        remaining: Double,
        used: Double? = nil,
        total: Double? = nil
    ) throws -> CreditBalance {
        try CreditBalance(
            validatingRemaining: remaining,
            used: used,
            total: total,
            scope: .buddyAISharedPersonal,
            observedAt: observedAt,
            provenance: .manualConfirmed(at: observedAt)
        )
    }

    private func channel(
        availability: AgentAvailabilityValue?,
        freshness: AgentConnectorFreshness = .fresh
    ) -> AgentUsageChannel {
        let isManual = availability?.sourceState == .manualConfirmed
        return AgentUsageChannel(
            id: .account,
            sourceTier: isManual ? .manualUserConfirmed : .officialStructuredHook,
            sourceVersion: "fixture-v1",
            scopes: [.account],
            provenance: isManual ? .manualConfirmed : .providerReported,
            freshness: freshness,
            capturedAt: observedAt,
            coverageNote: nil,
            rateLimitWindows: [],
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: freshness == .unavailable ? .unavailable : nil,
            availability: availability
        )
    }

    private func snapshot(
        state: AgentConnectorState,
        freshness: AgentConnectorFreshness,
        capturedAt: Date,
        availability: AgentAvailabilityValue?
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: "future.provider")!,
            providerName: "Future",
            state: state,
            capturedAt: capturedAt,
            lastSuccessfulAt: state == .ready ? capturedAt : nil,
            freshness: freshness,
            channels: [channel(availability: availability, freshness: freshness)],
            capabilities: [],
            safeFailure: state == .failed ? .unavailable : nil
        )
    }
}
