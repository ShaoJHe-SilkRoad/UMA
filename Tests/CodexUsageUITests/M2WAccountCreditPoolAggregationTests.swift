import Foundation
import JavaScriptCore
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
    func currentReferenceIsDynamicFixtureAndNotRuntimeOracle() throws {
        let reading = try success(
            validate(
                payload(
                    subscription: [
                        pool(
                            .subscriptionBase,
                            used: "0",
                            total: "4000",
                            id: "current-base"
                        ),
                        pool(
                            .subscriptionBonus,
                            used: "0",
                            total: "4000",
                            id: "current-bonus"
                        )
                    ],
                    addOn: [
                        pool(
                            .addOn,
                            used: "500",
                            total: "1000",
                            id: "current-addon"
                        )
                    ],
                    benefitGift: [
                        pool(
                            .benefitGift,
                            used: "863.1",
                            total: "1000",
                            id: "current-gift"
                        )
                    ]
                )
            )
        )

        #expect(reading.creditSnapshot.subscriptionRemaining == 8_000)
        #expect(reading.creditSnapshot.addOnRemaining == 500)
        #expect(
            reading.creditSnapshot.benefitGiftRemaining
                == Decimal(string: "136.90")
        )
        #expect(
            reading.creditSnapshot.calculatedTotalRemaining
                == Decimal(string: "8636.90")
        )
        #expect(
            CreditFormatter.exactTwoDecimal(
                reading.balance.remaining,
                language: .english
            ) == "8,636.90"
        )
        #expect(CreditFormatter.compact(reading.balance.remaining) == "8.6k")

        for relativePath in [
            "Sources/CodexUsageUI/Models/WorkBuddyAccountWebSync.swift",
            "Sources/CodexUsageUI/Services/WorkBuddyAccountWebExtractorScript.swift"
        ] {
            let runtimeSource = try String(
                contentsOf: packageRoot().appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(!runtimeSource.contains("8636.90"))
            #expect(!runtimeSource.contains("8,636.90"))
        }
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
            "__umaWorkBuddySectionDiscoveryStepV3",
            "rowDerivedSections",
            "deriveSectionFromRow",
            "quotaRowSelector",
            "quotaRowSelectors",
            "visibleCreditRows",
            "owningCreditRow",
            "pairCount",
            ".plans-usage__benefit-row",
            "[data-benefit-id]",
            "h1, h2, h3, h4, h5, h6",
            "[data-section-title]",
            "getClientRects().length === 0",
            "查看全部",
            "pageNotStabilized",
            "stableObservations",
            "sectionIsExplicitlyEmpty",
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
            "fetch(",
            "querySelectorAll(\"*\")"
        ] {
            #expect(!script.contains(forbidden))
        }
    }

    @Test
    func sectionDiscoveryRemainsBoundedAndAllSectionsStayMandatory() throws {
        let script = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Services/WorkBuddyAccountWebExtractorScript.swift"
            ),
            encoding: .utf8
        )

        #expect(script.contains("const maximumDiscoverySteps = Math.max(2,"))
        #expect(script.contains("return fail(\"incompletePoolSections\")"))
        #expect(
            script.contains(
                "new Set(Object.values(sections)).size !== 3"
            )
        )

        var missing = payload(subscription: subscription9000)
        missing = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: missing.extractorVersion,
            discoveredSections: [.subscription, .benefitGift],
            subscriptionPools: missing.subscriptionPools,
            addOnPools: [],
            benefitGiftPools: [],
            authoritativePageBalances: []
        )
        #expect(validate(missing) == .failure(.incompletePoolSections))
    }

    @Test @MainActor
    func extractorRuntimeRecoversAndResetsBoundedDiscoveryState() throws {
        guard let context = JSContext() else {
            Issue.record("JavaScriptCore context unavailable")
            return
        }
        var exceptionText: String?
        context.exceptionHandler = { _, exception in
            exceptionText = exception?.toString()
        }
        context.evaluateScript(Self.extractorRuntimeFixture)
        #expect(exceptionText == nil)

        let first = context.evaluateScript(
            WorkBuddyAccountWebExtractorScript.source
        )?.toDictionary()
        #expect(first?["failure"] as? String == "pageNotStabilized")
        #expect(first?["safeDiagnosticCode"] as? String == "T110-D110-Q1")
        #expect(
            context.objectForKeyedSubscript("fixtureScrollCount")?.toInt32()
                == 1
        )
        #expect(
            context.objectForKeyedSubscript(
                "__umaWorkBuddySectionDiscoveryStepV3"
            )?.toInt32() == 1
        )

        context.evaluateScript("installBenefitGiftSection();")
        let stabilizing = context.evaluateScript(
            WorkBuddyAccountWebExtractorScript.source
        )?.toDictionary()
        #expect(stabilizing?["failure"] as? String == "pageNotStabilized")
        #expect(
            context.objectForKeyedSubscript(
                "__umaWorkBuddySectionDiscoveryStepV3"
            )?.isUndefined == true
        )

        let recovered = context.evaluateScript(
            WorkBuddyAccountWebExtractorScript.source
        )?.toDictionary()
        #expect(recovered?["failure"] == nil)
        #expect(
            (recovered?["discoveredSections"] as? [String])
                == ["subscription", "addOn", "benefitGift"]
        )
        #expect((recovered?["subscriptionPools"] as? [Any])?.count == 1)
        #expect((recovered?["addOnPools"] as? [Any])?.count == 1)
        #expect((recovered?["benefitGiftPools"] as? [Any])?.count == 5)
        #expect(recovered?["safeDiagnosticCode"] == nil)
        let recoveredData = try JSONSerialization.data(
            withJSONObject: try #require(recovered)
        )
        let recoveredPayload = try JSONDecoder().decode(
            WorkBuddyAccountWebExtractionPayload.self,
            from: recoveredData
        )
        let recoveredReading = try success(validate(recoveredPayload))
        #expect(recoveredReading.creditSnapshot.subscriptionRemaining == 9_000)
        #expect(recoveredReading.creditSnapshot.addOnRemaining == 1_000)
        #expect(recoveredReading.creditSnapshot.benefitGiftRemaining == 205)
        #expect(recoveredReading.balance.remaining == 10_205)
        #expect(recoveredReading.creditSnapshot.includedPoolCount == 4)
        #expect(exceptionText == nil)

        context.evaluateScript("installMultiPairBenefitWrapper();")
        let restabilizing = context.evaluateScript(
            WorkBuddyAccountWebExtractorScript.source
        )?.toDictionary()
        #expect(restabilizing?["failure"] as? String == "pageNotStabilized")
        let rejectedWrapper = context.evaluateScript(
            WorkBuddyAccountWebExtractorScript.source
        )?.toDictionary()
        #expect(rejectedWrapper?["failure"] as? String == "malformedCredits")
        #expect(exceptionText == nil)
    }

    private static let extractorRuntimeFixture = #"""
    globalThis.fixtureScrollCount = 0;
    const makeNode = (text, attributes = {}, visible = true) => ({
      textContent: text,
      attributes,
      visible,
      parentElement: null,
      rows: [],
      rowSelector: ".plans-usage__quota-row",
      secondaryRows: [],
      secondaryRowSelector: "",
      headings: [],
      children: [],
      actionButtons: [],
      getAttribute(name) { return this.attributes[name] || null; },
      getClientRects() { return this.visible ? [{}] : []; },
      scrollIntoView() { globalThis.fixtureScrollCount += 1; },
      contains(other) {
        let candidate = other;
        while (candidate) {
          if (candidate === this) return true;
          candidate = candidate.parentElement;
        }
        return false;
      },
      querySelector(selector) {
        if (selector.includes("plans-usage__quota-remain")) return null;
        return this.pageTitle || null;
      },
      querySelectorAll(selector) {
        if (selector === "button, [role='button']") return this.actionButtons;
        if (selector === this.rowSelector) return this.rows;
        if (selector === this.secondaryRowSelector) return this.secondaryRows;
        if (selector.includes(", ") &&
            selector.includes(this.rowSelector)) {
          return this.rows.concat(this.secondaryRows);
        }
        if (selector.includes("data-account-balance")) return [];
        return this.headings;
      }
    });
    const pageTitle = makeNode("套餐与用量");
    const root = makeNode("套餐与用量");
    root.pageTitle = pageTitle;
    const subscription = makeNode("套餐额度 基础 0 / 9000 使用中");
    const addOn = makeNode("加量包 0 / 1000 使用中");
    addOn.rowSelector = ".resource-row";
    const subscriptionHeadingHidden = makeNode("套餐额度", {}, false);
    const subscriptionHeading = makeNode("套餐额度");
    const addOnHeading = makeNode("加量包");
    const subscriptionRowHidden = makeNode(
      "套餐额度 基础 0 / 9000 使用中",
      {},
      false
    );
    const subscriptionRow = makeNode("套餐额度 基础 0 / 9000 使用中");
    const addOnRow = makeNode("加量包 0 / 1000 使用中");
    addOnRow.attributes["data-resource-id"] = "addon-a";
    subscription.parentElement = root;
    addOn.parentElement = root;
    subscriptionHeadingHidden.parentElement = subscription;
    subscriptionHeading.parentElement = subscription;
    addOnHeading.parentElement = addOn;
    subscriptionRowHidden.parentElement = subscription;
    subscriptionRow.parentElement = subscription;
    addOnRow.parentElement = addOn;
    subscription.rows = [subscriptionRowHidden, subscriptionRow];
    subscription.headings = [
      subscriptionHeadingHidden,
      subscriptionHeading
    ];
    addOn.rows = [addOnRow];
    addOn.headings = [addOnHeading];
    root.children = [subscription, addOn];
    root.firstElementChild = subscription;
    root.lastElementChild = addOn;
    root.headings = [
      subscriptionHeadingHidden,
      subscriptionHeading,
      addOnHeading
    ];
    root.rows = [subscriptionRowHidden, subscriptionRow, addOnRow];
    const hiddenBenefitGift = makeNode("权益赠送包 0 / 100", {}, false);
    const hiddenBenefitGiftRow = makeNode("0 / 100", {}, false);
    hiddenBenefitGift.parentElement = root;
    hiddenBenefitGiftRow.parentElement = hiddenBenefitGift;
    root.rows.push(hiddenBenefitGiftRow);
    globalThis.installBenefitGiftSection = () => {
      const benefitGift = makeNode("权益赠送包 0 / 105 使用中");
      benefitGift.rowSelector = ".plans-usage__benefit-row";
      const benefitGiftRow = makeNode("权益赠送包 0 / 105 使用中");
      benefitGiftRow.attributes["data-benefit-id"] = "gift-a";
      const benefitGiftSecondaryRow = makeNode(
        "赠送包 0 / 100 使用中"
      );
      benefitGiftSecondaryRow.attributes["data-benefit-id"] = "gift-b";
      const benefitGiftExpiredTodayOwner = makeNode(
        "赠送包 0 / 100 使用中 到期时间： 2033-05-18 10:00:00"
      );
      benefitGiftExpiredTodayOwner.attributes["data-benefit-id"] =
        "gift-expired-today";
      const benefitGiftUnavailableRow = makeNode(
        "赠送包 400 / 500 无法使用 到期时间： 2033-05-19 10:00:00"
      );
      const benefitGiftClaimAction = makeNode("领取");
      benefitGiftClaimAction.parentElement = benefitGiftUnavailableRow;
      benefitGiftUnavailableRow.actionButtons = [benefitGiftClaimAction];
      benefitGiftUnavailableRow.attributes["data-benefit-id"] =
        "gift-unavailable";
      const benefitGiftDisabledRow = makeNode(
        "赠送包 0 / 50 到期时间： 2033-05-19 10:00:00"
      );
      benefitGiftDisabledRow.attributes["data-benefit-id"] =
        "gift-disabled";
      benefitGiftDisabledRow.attributes["aria-disabled"] = "true";
      const benefitGiftExpiredTodayRow = makeNode("0 / 100");
      let benefitGiftExpiredTodayAncestor = benefitGiftExpiredTodayRow;
      for (let depth = 0; depth < 6; depth += 1) {
        const wrapper = makeNode("0 / 100");
        benefitGiftExpiredTodayAncestor.parentElement = wrapper;
        benefitGiftExpiredTodayAncestor = wrapper;
      }
      benefitGiftExpiredTodayAncestor.parentElement =
        benefitGiftExpiredTodayOwner;
      benefitGift.parentElement = root;
      benefitGiftRow.parentElement = benefitGift;
      benefitGiftSecondaryRow.parentElement = benefitGift;
      benefitGiftExpiredTodayOwner.parentElement = benefitGift;
      benefitGiftUnavailableRow.parentElement = benefitGift;
      benefitGiftDisabledRow.parentElement = benefitGift;
      benefitGift.rows = [benefitGiftRow];
      benefitGift.secondaryRowSelector = ".package-row";
      benefitGift.secondaryRows = [
        benefitGiftSecondaryRow,
        benefitGiftExpiredTodayRow,
        benefitGiftUnavailableRow,
        benefitGiftDisabledRow
      ];
      benefitGift.headings = [];
      root.children.push(benefitGift);
      root.lastElementChild = benefitGift;
      root.rows.push(
        benefitGiftRow,
        benefitGiftSecondaryRow,
        benefitGiftExpiredTodayRow,
        benefitGiftUnavailableRow,
        benefitGiftDisabledRow
      );
      globalThis.fixtureBenefitGiftSection = benefitGift;
    };
    globalThis.installMultiPairBenefitWrapper = () => {
      const wrapper = makeNode(
        "权益赠送包 0 / 100 使用中 赠送包 0 / 200 使用中"
      );
      wrapper.parentElement = globalThis.fixtureBenefitGiftSection;
      globalThis.fixtureBenefitGiftSection.rows = [];
      globalThis.fixtureBenefitGiftSection.secondaryRows = [wrapper];
      root.rows = root.rows.filter(
        (row) => row.parentElement !== globalThis.fixtureBenefitGiftSection
      );
      root.rows.push(wrapper);
    };
    globalThis.location = {
      origin: "https://www.workbuddy.cn",
      pathname: "/profile/plans-usage",
      search: "",
      hash: ""
    };
    globalThis.document = {
      readyState: "complete",
      querySelector(selector) {
        return selector === ".plans-usage" ? root : null;
      },
      querySelectorAll() {
        return [];
      }
    };
    """#

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
