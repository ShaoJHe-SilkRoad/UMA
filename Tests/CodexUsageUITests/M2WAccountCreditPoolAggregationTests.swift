import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2WACCOUNT all-pool Credit aggregation")
struct M2WAccountCreditPoolAggregationTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test
    func threeCountableGiftRowsProduceAtomicAllPoolTotal() throws {
        let result = validate(
            payload(
                subscription: subscription9000,
                benefitGift: [
                    pool(
                        .benefitGift,
                        used: "668.94",
                        total: "1500",
                        id: "gift-large"
                    ),
                    pool(.benefitGift, used: "0", total: "100", id: "gift-1"),
                    pool(.benefitGift, used: "0", total: "100", id: "gift-2"),
                    pool(.benefitGift, used: "0", total: "100", id: "gift-3"),
                    pool(
                        .benefitGift,
                        used: "0",
                        total: "100",
                        id: "gift-future",
                        status: .future
                    )
                ],
                authoritative: ["10131.06"]
            )
        )
        let reading = try success(result)

        #expect(reading.creditSnapshot.subscriptionRemaining == 9_000)
        #expect(reading.creditSnapshot.addOnRemaining == 0)
        #expect(
            reading.creditSnapshot.benefitGiftRemaining
                == Decimal(string: "1131.06")
        )
        #expect(reading.balance.remaining == Decimal(string: "10131.06"))
        #expect(reading.creditSnapshot.includedPoolCount == 6)
        #expect(reading.balance.used == nil)
        #expect(reading.balance.total == nil)
        #expect(reading.balance.normalizedRemainingFraction == nil)
    }

    @Test
    func fourDistinctCountableGiftRowsProduceDifferentUnforcedTotal() throws {
        let gifts = [
            pool(
                .benefitGift,
                used: "668.94",
                total: "1500",
                id: "gift-large"
            ),
            pool(.benefitGift, used: "0", total: "100", id: "gift-1"),
            pool(.benefitGift, used: "0", total: "100", id: "gift-2"),
            pool(.benefitGift, used: "0", total: "100", id: "gift-3"),
            pool(.benefitGift, used: "0", total: "100", id: "gift-4")
        ]
        let reading = try success(
            validate(
                payload(
                    subscription: subscription9000,
                    benefitGift: gifts
                )
            )
        )

        #expect(reading.balance.remaining == Decimal(string: "10231.06"))
        let model = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Models/WorkBuddyAccountWebSync.swift"
            ),
            encoding: .utf8
        )
        #expect(!model.contains("10131.06"))
        #expect(!model.contains("10231.06"))
    }

    @Test
    func missingSectionAndWrongSectionKindFailClosed() {
        var missing = payload(subscription: subscription9000)
        missing = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: missing.extractorVersion,
            discoveredSections: [.subscription],
            subscriptionPools: missing.subscriptionPools,
            addOnPools: [],
            benefitGiftPools: [],
            authoritativePageBalances: []
        )
        #expect(validate(missing) == .failure(.incompletePoolSections))

        let wrongKind = payload(
            subscription: subscription9000,
            addOn: [
                pool(.benefitGift, used: "0", total: "100")
            ]
        )
        #expect(validate(wrongKind) == .failure(.invalidCreditPool))
    }

    @Test
    func displayedRemainingUsesExactOneCentTolerance() throws {
        let accepted = payload(
            subscription: [
                pool(
                    .subscriptionBase,
                    used: "100",
                    total: "500",
                    displayed: "400.01"
                )
            ]
        )
        #expect(try success(validate(accepted)).balance.remaining == 400)

        let rejected = payload(
            subscription: [
                pool(
                    .subscriptionBase,
                    used: "100",
                    total: "500",
                    displayed: "400.02"
                )
            ]
        )
        #expect(validate(rejected) == .failure(.invalidCreditPool))
    }

    @Test
    func authoritativeReconciliationUsesOneCentToleranceAndOneCandidate() throws {
        let withinTolerance = payload(
            subscription: [
                pool(.subscriptionBase, used: "100", total: "500")
            ],
            authoritative: ["400.01"]
        )
        #expect(
            try success(validate(withinTolerance))
                .creditSnapshot.authoritativePageBalance
                == Decimal(string: "400.01")
        )

        let mismatch = payload(
            subscription: [
                pool(.subscriptionBase, used: "100", total: "500")
            ],
            authoritative: ["400.02"]
        )
        #expect(
            validate(mismatch)
                == .failure(.accountBalanceReconciliationFailed)
        )

        let exactHundredMismatch = payload(
            subscription: subscription9000,
            benefitGift: [
                pool(
                    .benefitGift,
                    used: "668.94",
                    total: "1500",
                    id: "gift-large"
                ),
                pool(.benefitGift, used: "0", total: "100", id: "gift-1"),
                pool(.benefitGift, used: "0", total: "100", id: "gift-2"),
                pool(.benefitGift, used: "0", total: "100", id: "gift-3"),
                pool(.benefitGift, used: "0", total: "100", id: "gift-4")
            ],
            authoritative: ["10131.06"]
        )
        #expect(
            validate(exactHundredMismatch)
                == .failure(.accountBalanceReconciliationFailed)
        )

        let ambiguous = payload(
            subscription: subscription9000,
            authoritative: ["9000", "9000"]
        )
        #expect(validate(ambiguous) == .failure(.ambiguousAccountBalance))
    }

    @Test
    func everyDuplicateIdentityFailsClosedWhileDistinctPoolsRemainCountable() throws {
        let exact = pool(
            .subscriptionBase,
            used: "0",
            total: "4000",
            id: "base"
        )
        #expect(
            validate(payload(subscription: [exact, exact]))
                == .failure(.duplicateCreditPool)
        )

        let collision = payload(
            subscription: [
                exact,
                pool(
                    .subscriptionBase,
                    used: "1",
                    total: "4000",
                    id: "base"
                )
            ]
        )
        #expect(validate(collision) == .failure(.duplicateCreditPool))

        let distinct = try success(
            validate(
                payload(
                    subscription: [
                        pool(
                            .subscriptionBase,
                            used: "0",
                            total: "100",
                            id: "base-a"
                        ),
                        pool(
                            .subscriptionBase,
                            used: "0",
                            total: "100",
                            id: "base-b"
                        )
                    ]
                )
            )
        )
        #expect(distinct.balance.remaining == 200)
    }

    @Test
    func subscriptionConfigurationsAndChangedOrderingRemainDeterministic() throws {
        let base = pool(
            .subscriptionBase,
            used: "20",
            total: "100",
            id: "base"
        )
        let bonus = pool(
            .subscriptionBonus,
            used: "10",
            total: "70",
            id: "bonus"
        )

        #expect(
            try success(validate(payload(subscription: [base])))
                .creditSnapshot.subscriptionRemaining == 80
        )
        #expect(
            try success(validate(payload(subscription: [bonus])))
                .creditSnapshot.subscriptionRemaining == 60
        )
        let forward = try success(
            validate(payload(subscription: [base, bonus]))
        )
        let reversed = try success(
            validate(payload(subscription: [bonus, base]))
        )
        #expect(forward.balance.remaining == 140)
        #expect(reversed.creditSnapshot == forward.creditSnapshot)
    }

    @Test
    func addOnGiftAndSafeStatusesProduceIndependentSubtotals() throws {
        let reading = try success(
            validate(
                payload(
                    subscription: [
                        pool(
                            .subscriptionBase,
                            used: "100",
                            total: "500",
                            status: .active
                        )
                    ],
                    addOn: [
                        pool(
                            .addOn,
                            used: "25",
                            total: "100",
                            id: "addon-active",
                            status: .active
                        ),
                        pool(
                            .addOn,
                            used: "50",
                            total: "50",
                            id: "addon-exhausted",
                            status: .exhausted
                        ),
                        pool(
                            .addOn,
                            used: "0",
                            total: "20",
                            id: "addon-expired",
                            status: .expired
                        )
                    ],
                    benefitGift: [
                        pool(
                            .benefitGift,
                            used: "5",
                            total: "30",
                            status: .available
                        )
                    ]
                )
            )
        )

        #expect(reading.creditSnapshot.subscriptionRemaining == 400)
        #expect(reading.creditSnapshot.addOnRemaining == 75)
        #expect(reading.creditSnapshot.benefitGiftRemaining == 25)
        #expect(reading.balance.remaining == 500)
        #expect(reading.creditSnapshot.includedPoolCount == 4)
    }

    @Test
    func semanticDuplicatesUseIdentityDatesAndRejectInvalidRows() throws {
        let firstExpiry = Int64(
            now.addingTimeInterval(3_600).timeIntervalSince1970 * 1_000
        )
        let secondExpiry = Int64(
            now.addingTimeInterval(7_200).timeIntervalSince1970 * 1_000
        )
        let distinctByExpiry = try success(
            validate(
                payload(
                    subscription: subscription9000,
                    benefitGift: [
                        pool(
                            .benefitGift,
                            used: "0",
                            total: "100",
                            expiresAtMilliseconds: firstExpiry
                        ),
                        pool(
                            .benefitGift,
                            used: "0",
                            total: "100",
                            expiresAtMilliseconds: secondExpiry
                        )
                    ]
                )
            )
        )
        #expect(distinctByExpiry.balance.remaining == 9_200)

        for invalid in [
            pool(.subscriptionBase, used: "101", total: "100"),
            pool(.subscriptionBase, used: "0", total: "0"),
            pool(
                .subscriptionBase,
                used: "0",
                total: "100",
                id: "NOT SAFE"
            ),
            pool(
                .subscriptionBase,
                used: "0",
                total: "100",
                effectiveAtMilliseconds: secondExpiry,
                expiresAtMilliseconds: firstExpiry
            )
        ] {
            #expect(
                validate(payload(subscription: [invalid]))
                    == .failure(.invalidCreditPool)
            )
        }
    }

    @Test
    func expiredFutureHistoricalAndUnavailablePoolsAreExcluded() throws {
        let future = Int64(now.addingTimeInterval(60).timeIntervalSince1970 * 1_000)
        let past = Int64(now.addingTimeInterval(-60).timeIntervalSince1970 * 1_000)
        let reading = try success(
            validate(
                payload(
                    subscription: [
                        pool(.subscriptionBase, used: "0", total: "100"),
                        pool(
                            .subscriptionBonus,
                            used: "0",
                            total: "20",
                            status: .expired
                        ),
                        pool(
                            .subscriptionBonus,
                            used: "0",
                            total: "30",
                            status: .future
                        ),
                        pool(
                            .subscriptionBonus,
                            used: "0",
                            total: "40",
                            status: .historical
                        ),
                        pool(
                            .subscriptionBonus,
                            used: "0",
                            total: "50",
                            status: .unavailable
                        ),
                        pool(
                            .subscriptionBonus,
                            used: "0",
                            total: "60",
                            effectiveAtMilliseconds: future
                        ),
                        pool(
                            .subscriptionBonus,
                            used: "0",
                            total: "70",
                            expiresAtMilliseconds: past
                        )
                    ]
                )
            )
        )
        #expect(reading.balance.remaining == 100)

        let ambiguous = payload(
            subscription: [
                pool(
                    .subscriptionBase,
                    used: "0",
                    total: "100",
                    status: .ambiguous
                )
            ]
        )
        #expect(validate(ambiguous) == .failure(.invalidCreditPool))
    }

    @Test
    func decimalPrecisionAndMaximumFailClosed() throws {
        let maximum = try success(
            validate(
                payload(
                    subscription: [
                        pool(
                            .subscriptionBase,
                            used: "0",
                            total: "999999999999.99"
                        )
                    ]
                )
            )
        )
        #expect(
            maximum.balance.remaining
                == Decimal(string: "999999999999.99")
        )

        for invalid in [
            "1000000000000",
            "1.001",
            "-1",
            "NaN",
            "1e3"
        ] {
            #expect(
                validate(
                    payload(
                        subscription: [
                            pool(
                                .subscriptionBase,
                                used: "0",
                                total: invalid
                            )
                        ]
                    )
                ) == .failure(.invalidCreditPool)
            )
        }
    }

    @Test
    func subscriptionOrUsedValueCannotMasqueradeAsGlobalBalance() {
        let pools = payload(
            subscription: subscription9000,
            benefitGift: [
                pool(
                    .benefitGift,
                    used: "668.94",
                    total: "1500",
                    id: "gift-large"
                )
            ],
            authoritative: ["9000"]
        )
        #expect(
            validate(pools)
                == .failure(.accountBalanceReconciliationFailed)
        )

        var usedValue = pools
        usedValue = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: usedValue.extractorVersion,
            discoveredSections: usedValue.discoveredSections,
            subscriptionPools: usedValue.subscriptionPools,
            addOnPools: usedValue.addOnPools,
            benefitGiftPools: usedValue.benefitGiftPools,
            authoritativePageBalances: ["668.94"]
        )
        #expect(
            validate(usedValue)
                == .failure(.accountBalanceReconciliationFailed)
        )
    }

    @Test
    func noPageBalanceRetainsExplicitHumanReconciliationPath() throws {
        let reading = try success(
            validate(
                payload(
                    subscription: subscription9000,
                    benefitGift: [
                        pool(
                            .benefitGift,
                            used: "668.94",
                            total: "1500"
                        )
                    ]
                )
            )
        )
        #expect(reading.creditSnapshot.authoritativePageBalance == nil)
        #expect(
            reading.creditSnapshot.calculatedTotalRemaining
                == Decimal(string: "9831.06")
        )
        #expect(reading.creditSnapshot.source == .authenticatedAccountWeb)
    }

    @Test
    func sanitizedSnapshotCodableRetainsCanonicalDecimalStrings() throws {
        let reading = try success(
            validate(
                payload(
                    subscription: subscription9000,
                    benefitGift: [
                        pool(
                            .benefitGift,
                            used: "668.94",
                            total: "1500"
                        )
                    ]
                )
            )
        )
        let encoded = try JSONEncoder().encode(reading.creditSnapshot)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["subscriptionRemaining"] as? String == "9000")
        #expect(object["benefitGiftRemaining"] as? String == "831.06")
        #expect(object["calculatedTotalRemaining"] as? String == "9831.06")
        #expect(
            try JSONDecoder().decode(
                WorkBuddyAccountCreditSnapshot.self,
                from: encoded
            ) == reading.creditSnapshot
        )
    }

    @Test
    func exactTwoDecimalDisplayCoversRequiredValues() throws {
        let values = [
            "500": "500.00",
            "897.32": "897.32",
            "2099.47": "2,099.47",
            "9000": "9,000.00",
            "10131.06": "10,131.06",
            "10231.06": "10,231.06",
            "999999999999.99": "999,999,999,999.99"
        ]
        for (source, expected) in values {
            let value = try #require(Decimal(string: source))
            #expect(
                CreditFormatter.exactTwoDecimal(value, language: .english)
                    == expected
            )
            #expect(
                !CreditFormatter.exactTwoDecimal(value, language: .english)
                    .lowercased().contains("e")
            )
        }
    }

    @Test
    func extractorContractIsBoundedSectionSpecificAndPrivacySafe() throws {
        let script = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Services/WorkBuddyAccountWebExtractorScript.swift"
            ),
            encoding: .utf8
        )
        for required in [
            "subscriptionPools",
            "addOnPools",
            "benefitGiftPools",
            "scrollIntoView",
            "查看全部",
            "pageNotStabilized",
            "stableObservations",
            "authoritativePageBalances",
            "location.pathname !== \"/profile/plans-usage\"",
            "(?:^|[^不])可用"
        ] {
            #expect(script.contains(required))
        }
        for forbidden in [
            "document.body",
            "outerHTML",
            "innerHTML",
            "document.cookie",
            "localStorage",
            "sessionStorage",
            "XMLHttpRequest",
            "fetch("
        ] {
            #expect(!script.contains(forbidden))
        }
    }

    private var subscription9000: [WorkBuddyAccountWebSanitizedPool] {
        [
            pool(.subscriptionBase, used: "0", total: "4000", id: "base"),
            pool(.subscriptionBonus, used: "0", total: "5000", id: "bonus")
        ]
    }

    private func validate(
        _ payload: WorkBuddyAccountWebExtractionPayload
    ) -> WorkBuddyAccountWebReadResult {
        WorkBuddyAccountWebExtractor.validate(payload, observedAt: now)
    }

    private func success(
        _ result: WorkBuddyAccountWebReadResult
    ) throws -> WorkBuddyAccountWebReading {
        guard case let .success(reading) = result else {
            throw WorkBuddyAccountWebFailure.invalidCreditPool
        }
        return reading
    }

    private func payload(
        subscription: [WorkBuddyAccountWebSanitizedPool],
        addOn: [WorkBuddyAccountWebSanitizedPool] = [],
        benefitGift: [WorkBuddyAccountWebSanitizedPool] = [],
        authoritative: [String] = []
    ) -> WorkBuddyAccountWebExtractionPayload {
        WorkBuddyAccountWebExtractionPayload(
            extractorVersion: WorkBuddyAccountWebReading.extractorVersion,
            discoveredSections: WorkBuddyCreditPoolSection.allCases,
            subscriptionPools: subscription,
            addOnPools: addOn,
            benefitGiftPools: benefitGift,
            authoritativePageBalances: authoritative
        )
    }

    private func pool(
        _ kind: WorkBuddyCreditPoolKind,
        used: String,
        total: String,
        displayed: String? = nil,
        id: String? = nil,
        status: WorkBuddyCreditPoolSafeStatus = .available,
        effectiveAtMilliseconds: Int64? = nil,
        expiresAtMilliseconds: Int64? = nil
    ) -> WorkBuddyAccountWebSanitizedPool {
        WorkBuddyAccountWebSanitizedPool(
            stablePageID: id,
            kind: kind,
            used: used,
            total: total,
            displayedRemaining: displayed,
            effectiveAtMilliseconds: effectiveAtMilliseconds,
            expiresAtMilliseconds: expiresAtMilliseconds,
            pageStatus: status
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
