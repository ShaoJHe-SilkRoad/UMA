import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2WACCOUNT-G1 WorkBuddy account web sync")
struct M2WAccountWebSyncTests {
    @Test
    func safeStructureDiagnosticsAcceptOnlyTheBoundedBitCode() {
        let data = Data()
        #expect(
            WorkBuddyAccountWebExtractionAttempt(
                data: data,
                failure: .incompletePoolSections,
                safeDiagnosticCode: "T101-D010-Q1"
            ).safeDiagnosticCode == "T101-D010-Q1"
        )
        for rejected in [
            nil,
            "",
            "T101-D010-Q1-extra",
            "T102-D010-Q1",
            "account text",
            "T101-D010-Q1\nidentity"
        ] {
            #expect(
                WorkBuddyAccountWebExtractionAttempt(
                    data: data,
                    failure: .incompletePoolSections,
                    safeDiagnosticCode: rejected
                ).safeDiagnosticCode == nil
            )
        }
    }

    @Test
    func officialOriginAndUsageRouteAreExact() {
        #expect(
            WorkBuddyAccountWebPolicy.usageURL.absoluteString
                == "https://www.workbuddy.cn/profile/plans-usage"
        )
        #expect(
            WorkBuddyAccountWebPolicy.isExactUsagePage(
                URL(string: "https://www.workbuddy.cn/profile/plans-usage")
            )
        )
        #expect(
            !WorkBuddyAccountWebPolicy.isExactUsagePage(
                URL(string: "http://www.workbuddy.cn/profile/plans-usage")
            )
        )
        #expect(
            !WorkBuddyAccountWebPolicy.isExactUsagePage(
                URL(string: "https://workbuddy.cn/profile/plans-usage")
            )
        )
        #expect(
            !WorkBuddyAccountWebPolicy.isExactUsagePage(
                URL(string: "https://www.workbuddy.cn/profile/keys")
            )
        )
        #expect(
            !WorkBuddyAccountWebPolicy.isExactUsagePage(
                URL(
                    string:
                        "https://www.workbuddy.cn/profile/plans-usage?source=unexpected"
                )
            )
        )
        #expect(
            !WorkBuddyAccountWebPolicy.isExactUsagePage(
                URL(
                    string:
                        "https://www.workbuddy.cn/profile/plans-usage#unexpected"
                )
            )
        )
    }

    @Test
    func navigationPolicyAllowsOfficialPagesAndRequiresExactHostConfirmation() {
        #expect(
            WorkBuddyAccountWebPolicy.navigationDecision(
                for: URL(string: "https://www.workbuddy.cn/"),
                isMainFrame: true
            ) == .allow
        )
        #expect(
            WorkBuddyAccountWebPolicy.navigationDecision(
                for: URL(string: "https://workbuddy.cn/profile/plans-usage"),
                isMainFrame: true
            ) == .confirmExternalHost("workbuddy.cn")
        )
        #expect(
            WorkBuddyAccountWebPolicy.navigationDecision(
                for: URL(string: "https://login.example.test/start?secret=ignored"),
                isMainFrame: true
            ) == .confirmExternalHost("login.example.test")
        )
        #expect(
            WorkBuddyAccountWebPolicy.navigationDecision(
                for: URL(string: "https://login.example.test/start"),
                isMainFrame: false
            ) == .confirmExternalHost("login.example.test")
        )
        #expect(
            WorkBuddyAccountWebPolicy.navigationDecision(
                for: URL(string: "https://login.example.test/start"),
                isMainFrame: true
            ) == .confirmExternalHost("login.example.test")
        )
        #expect(
            WorkBuddyAccountWebPolicy.navigationDecision(
                for: URL(string: "javascript:alert(1)"),
                isMainFrame: true
            ) == .cancel
        )
    }

    @Test
    func sanitizedPoolsProduceExactAtomicAccountBalance() throws {
        let observedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let payload = accountPayload(
            subscription: [
                pool(.subscriptionBase, used: "0", total: "4000"),
                pool(.subscriptionBonus, used: "0", total: "5000")
            ],
            benefitGift: [
                pool(.benefitGift, used: "668.94", total: "1500"),
                pool(.benefitGift, used: "0", total: "100", id: "gift-1"),
                pool(.benefitGift, used: "0", total: "100", id: "gift-2"),
                pool(.benefitGift, used: "0", total: "100", id: "gift-3")
            ],
            authoritative: ["10131.06"]
        )

        guard case let .success(reading) = WorkBuddyAccountWebExtractor.validate(
            payload,
            observedAt: observedAt
        ) else {
            Issue.record("Expected an exact sanitized Credit reading")
            return
        }

        #expect(CreditDecimalCodec.canonicalString(reading.balance.remaining) == "10131.06")
        #expect(reading.balance.used == nil)
        #expect(reading.balance.total == nil)
        #expect(reading.balance.normalizedRemainingFraction == nil)
        #expect(reading.creditSnapshot.subscriptionRemaining == 9_000)
        #expect(reading.creditSnapshot.addOnRemaining == 0)
        #expect(
            reading.creditSnapshot.benefitGiftRemaining
                == Decimal(string: "1131.06")
        )
        #expect(
            reading.creditSnapshot.calculatedTotalRemaining
                == Decimal(string: "10131.06")
        )
        #expect(
            reading.creditSnapshot.authoritativePageBalance
                == Decimal(string: "10131.06")
        )
        #expect(reading.balance.scope == .buddyAIUnknown)
        #expect(reading.balance.observedAt == observedAt)
        #expect(
            reading.balance.provenance
                == .authenticatedAccountWeb(observedAt: observedAt)
        )

        let encoded = try JSONEncoder().encode(reading.balance)
        let decoded = try JSONDecoder().decode(CreditBalance.self, from: encoded)
        #expect(decoded == reading.balance)
    }

    @Test
    func malformedAmbiguousAndNoncanonicalCreditsFailClosed() {
        let now = Date()
        let malformed = accountPayload(
            subscription: [
                pool(.subscriptionBase, used: "0", total: "2,099.47")
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(malformed, observedAt: now)
                == .failure(.invalidCreditPool)
        )

        let duplicate = accountPayload(
            subscription: [
                pool(
                    .subscriptionBase,
                    used: "0",
                    total: "500",
                    id: "shared-id"
                ),
                pool(
                    .subscriptionBase,
                    used: "1",
                    total: "500",
                    id: "shared-id"
                )
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(duplicate, observedAt: now)
                == .failure(.duplicateCreditPool)
        )

        let inconsistent = accountPayload(
            subscription: [
                pool(
                    .subscriptionBase,
                    used: "100",
                    total: "2000",
                    displayed: "2099.47"
                )
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(inconsistent, observedAt: now)
                == .failure(.invalidCreditPool)
        )

        let noncanonical = accountPayload(
            subscription: [
                pool(.subscriptionBase, used: "0", total: "01")
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(noncanonical, observedAt: now)
                == .failure(.invalidCreditPool)
        )

        let excessivePrecision = accountPayload(
            subscription: [
                pool(.subscriptionBase, used: "0", total: "0.123")
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(
                excessivePrecision,
                observedAt: now
            ) == .failure(.invalidCreditPool)
        )
    }

    @Test
    func descriptorIsWorkBuddyOnlyAccountWebAndNeverRestorable() {
        let descriptor = WorkBuddyAccountWebCreditsConnector(
            hasConsent: { true },
            reader: { .authenticationRequired },
            disconnectOwnedSession: {}
        ).descriptor

        #expect(descriptor.id.rawValue == "workbuddy.accountWebCredits")
        #expect(descriptor.sourceTier == .authorizedReadOnlyRemote)
        #expect(descriptor.localSourceClass == .authenticatedAccountWeb)
        #expect(
            descriptor.authenticationMethod
                == .umaOwnedAuthenticatedAccountWebSession
        )
        #expect(
            descriptor.usageReadContract == .currentAuthenticatedAccountWebRead
        )
        #expect(descriptor.expectedRuntime == .none)
        #expect(!descriptor.supportsRestore)
        #expect(!descriptor.capabilities.contains(.passiveLocalAvailability))
        #expect(!descriptor.capabilities.contains(.hiddenFromProviderSurfaces))
        #expect(!descriptor.capabilities.contains(.hiddenFromDesktopAssistant))
        #expect(descriptor.officialSource == "Account web sync")
    }

    @Test @MainActor
    func currentSuccessfulReadAdmitsBothSurfacesWithoutWorkBuddyApp() async throws {
        let reading = try makeReading(
            remaining: "2099.47",
            used: "100",
            total: "2199.47"
        )
        let source = ScriptedWorkBuddyAccountReader([.success(reading)])
        let connector = WorkBuddyAccountWebCreditsConnector(
            hasConsent: { true },
            reader: { await source.next() },
            disconnectOwnedSession: {}
        )
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            snapshotStore: nil
        )

        let admission = await registry.scanSurfaceAdmissions(trigger: .syncNow)
        #expect(admission.admittedProviderIDs == [connector.id])
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: admission.admittedSnapshots,
            previousCards: [],
            language: .english
        )
        #expect(cards.count == 1)
        #expect(cards[0].availability?.sourceState == .authenticatedAccountWeb)
        #expect(cards[0].isVisibleInDesktopAssistant)
        #expect(cards[0].tooltipText.contains("2,099.47 Credits"))
        #expect(cards[0].tooltipText.contains("Account web sync"))
        #expect(connector.descriptor.privacyAllowlist.contains("poolKind"))
        #expect(
            connector.descriptor.privacyAllowlist.contains(
                "calculatedTotalRemainingCredits"
            )
        )

        let assistant = DesktopAssistantCard(shared: cards[0], language: .english)
        #expect(assistant.sourceMark == .accountWeb)
        #expect(assistant.detailText == "Account web sync")
        #expect(assistant.regularUsageText == "2,099.47")
        #expect(assistant.usageValue == .credits("2k"))
        #expect(assistant.tintFraction == nil)

        let chineseCards = SharedUsagePresentationPolicy.makeCards(
            snapshots: admission.admittedSnapshots,
            previousCards: [],
            language: .simplifiedChinese
        )
        #expect(chineseCards[0].tooltipText.contains("账号网页同步"))
    }

    @Test @MainActor
    func launchReadRequiresAnEstablishedPersistentIsolatedSession() async throws {
        let reading = try makeReading(
            remaining: "2099.47",
            used: "100",
            total: "2199.47"
        )
        let source = ScriptedWorkBuddyAccountReader([
            .success(reading),
            .success(reading)
        ])
        let launchGate = AccountLaunchGate(false)
        let connector = WorkBuddyAccountWebCreditsConnector(
            hasConsent: { true },
            canReadOnApplicationLaunch: { await launchGate.isOpen },
            reader: { await source.next() },
            disconnectOwnedSession: {}
        )
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            snapshotStore: nil
        )

        let rejected = await registry.scanSurfaceAdmissions(
            trigger: .applicationLaunch
        )
        #expect(rejected.admittedProviderIDs.isEmpty)
        #expect(await source.readCount == 0)

        await launchGate.open()
        let admitted = await registry.scanSurfaceAdmissions(
            trigger: .applicationLaunch
        )
        #expect(admitted.admittedProviderIDs == [connector.id])
        #expect(await source.readCount == 1)
    }

    @Test @MainActor
    func expiryOrExtractionFailureImmediatelyRemovesFormerAdmission() async throws {
        let reading = try makeReading(
            remaining: "500",
            used: nil,
            total: nil
        )
        let source = ScriptedWorkBuddyAccountReader([
            .success(reading),
            .authenticationRequired
        ])
        let connector = WorkBuddyAccountWebCreditsConnector(
            hasConsent: { true },
            reader: { await source.next() },
            disconnectOwnedSession: {}
        )
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            snapshotStore: nil
        )

        let first = await registry.scanSurfaceAdmissions(trigger: .syncNow)
        #expect(first.admittedProviderIDs == [connector.id])
        let second = await registry.scanSurfaceAdmissions(trigger: .manualRefresh)
        #expect(second.admittedProviderIDs.isEmpty)
        #expect((await registry.orderedSnapshots()).isEmpty)
    }

    @Test @MainActor
    func disconnectClearsOnlyAccountWebAdmissionAndNeverUsesManualFallback() async throws {
        let reading = try makeReading(
            remaining: "500",
            used: nil,
            total: nil
        )
        let source = ScriptedWorkBuddyAccountReader([.success(reading)])
        let disconnect = AccountDisconnectRecorder()
        let accountConnector = WorkBuddyAccountWebCreditsConnector(
            hasConsent: { true },
            reader: { await source.next() },
            disconnectOwnedSession: { await disconnect.record() }
        )
        let manualStore = WorkBuddyManualAvailabilityStore(
            fileURL: URL(fileURLWithPath: "/private/tmp/unused-account-web-manual.json")
        )
        let manualConnector = WorkBuddyAvailabilityConnector(
            source: ManualWorkBuddyAvailabilitySource(store: manualStore)
        )
        let registry = try AgentConnectorRegistry(
            connectors: [manualConnector, accountConnector],
            snapshotStore: nil
        )

        let admitted = await registry.scanSurfaceAdmissions(trigger: .syncNow)
        #expect(admitted.admittedProviderIDs == [accountConnector.id])
        try await registry.perform(.disconnect, for: accountConnector.id)
        #expect((await registry.orderedSnapshots()).isEmpty)
        #expect(await disconnect.count == 1)
        #expect(
            manualConnector.descriptor.localSourceClass == .manualOnly
        )
        #expect(
            manualConnector.descriptor.capabilities.contains(
                .hiddenFromProviderSurfaces
            )
        )
    }

    @Test
    func extractorAndControllerContainNoBroadBrowserOrPrivateDataReads() throws {
        let root = packageRoot()
        let controller = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/CodexUsageUI/Services/WorkBuddyAccountWebSessionController.swift"
            ),
            encoding: .utf8
        )
        let extractor = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/CodexUsageUI/Services/WorkBuddyAccountWebExtractorScript.swift"
            ),
            encoding: .utf8
        )
        let combined = controller + extractor

        for forbidden in [
            "httpCookieStore",
            "getAllCookies",
            "localStorage.",
            "sessionStorage.",
            "document.body",
            "document.documentElement",
            "innerHTML",
            "outerHTML",
            "URLSession",
            "Authorization",
            "Keychain",
            "Timer.",
            "scheduledTimer"
        ] {
            #expect(!combined.contains(forbidden))
        }
        #expect(extractor.contains(".plans-usage__quota-row"))
        #expect(extractor.contains(".plans-usage__quota-remain"))
        #expect(controller.contains("WKWebsiteDataStore.allWebsiteDataTypes()"))
        #expect(controller.contains("fetchDataRecords(ofTypes: dataTypes)"))
        #expect(controller.contains("removeData(ofTypes: dataTypes, for: records)"))
        #expect(controller.contains("WorkBuddyOwnedWebsiteDataClearer.clear("))
        #expect(controller.contains("forIdentifier:"))
    }

    @Test @MainActor
    func ownedWebsiteDataClearerSucceedsForEmptyDedicatedStore() async {
        var removed: [[Int]] = []

        let didClear = await WorkBuddyOwnedWebsiteDataClearer.clear(
            fetch: { [] },
            remove: { removed.append($0) }
        )

        #expect(didClear)
        #expect(removed == [[]])
    }

    @Test @MainActor
    func ownedWebsiteDataClearerRemovesFetchedRecordsAndVerifiesEmpty() async {
        var records = [1, 2]
        var removed: [[Int]] = []

        let didClear = await WorkBuddyOwnedWebsiteDataClearer.clear(
            fetch: { records },
            remove: {
                removed.append($0)
                records.removeAll()
            }
        )

        #expect(didClear)
        #expect(removed == [[1, 2]])
        #expect(records.isEmpty)
    }

    @Test @MainActor
    func ownedWebsiteDataClearerFailsClosedWhenRecordsRemain() async {
        let didClear = await WorkBuddyOwnedWebsiteDataClearer.clear(
            fetch: { [1] },
            remove: { _ in }
        )

        #expect(!didClear)
    }

    @Test @MainActor
    func disconnectMapsOwnedWebsiteDataClearFailureToExplicitState() async {
        let suite = "M2WAccountWebSyncTests.clear-failure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = WorkBuddyAccountWebSessionController(
            defaults: defaults,
            websiteDataClearer: { false }
        )
        controller.grantConsent()

        await controller.disconnectAndClearOwnedWebsiteData()

        #expect(!controller.consentGranted)
        #expect(controller.flowState == .failed(.websiteDataClearFailed))
    }

    @Test
    func eligibilityScannerTriggersStayExplicitAndAutoRefreshStaysSourceOwned()
        throws
    {
        #expect(ProviderEligibilityScanTrigger.allCases == [
            .applicationLaunch,
            .manualRefresh,
            .checkAgain,
            .syncNow
        ])
        let controller = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Services/WorkBuddyAccountWebSessionController.swift"
            ),
            encoding: .utf8
        )
        #expect(!controller.contains("poll"))
        #expect(!controller.contains("backgroundRefresh"))
        #expect(!controller.contains("DispatchSourceTimer"))
        #expect(controller.contains("WorkBuddyAccountSyncScheduler"))
        #expect(controller.contains("maximumAttempts = 20"))
        #expect(controller.contains("delay = Duration.milliseconds(250)"))
        #expect(controller.contains("readGeneration &+= 1"))
        let readStart = try #require(
            controller.range(of: "func readCurrentCredits()")
        )
        let disconnectStart = try #require(
            controller.range(
                of: "func disconnectAndClearOwnedWebsiteData()",
                range: readStart.upperBound..<controller.endIndex
            )
        )
        let readImplementation = controller[
            readStart.lowerBound..<disconnectStart.lowerBound
        ]
        #expect(!readImplementation.contains("showWindow()"))
    }

    @Test @MainActor
    func extractionReadinessRecoversAfterBoundedRenderingDelay() async throws {
        var reads = 0
        var waits: [Duration] = []
        let success = try extractionAttempt(
            accountPayload(
                subscription: [
                    pool(
                        .subscriptionBase,
                        used: "0",
                        total: "2099.47"
                    )
                ]
            )
        )

        let result = try await WorkBuddyAccountWebExtractionReadiness.evaluate(
            isCurrent: { true },
            read: {
                reads += 1
                return reads < 3
                    ? try extractionAttempt(failure: .unexpectedPage)
                    : success
            },
            wait: { waits.append($0) }
        )

        #expect(result == success)
        #expect(reads == 3)
        #expect(waits == [.milliseconds(250), .milliseconds(250)])
    }

    @Test @MainActor
    func extractionReadinessWaitsForAllRequiredPoolSections() async throws {
        var reads = 0
        var waits: [Duration] = []
        let success = try extractionAttempt(
            accountPayload(
                subscription: [
                    pool(
                        .subscriptionBase,
                        used: "0",
                        total: "2099.47"
                    )
                ]
            )
        )

        let result = try await WorkBuddyAccountWebExtractionReadiness.evaluate(
            isCurrent: { true },
            read: {
                reads += 1
                return reads < 3
                    ? try extractionAttempt(failure: .incompletePoolSections)
                    : success
            },
            wait: { waits.append($0) }
        )

        #expect(result == success)
        #expect(reads == 3)
        #expect(waits == [.milliseconds(250), .milliseconds(250)])
    }

    @Test @MainActor
    func malformedExtractionFailsClosedWithoutAutomaticRetry() async throws {
        var reads = 0
        var waits = 0
        let failure = try extractionAttempt(failure: .malformedCredits)

        let result = try await WorkBuddyAccountWebExtractionReadiness.evaluate(
            isCurrent: { true },
            read: {
                reads += 1
                return failure
            },
            wait: { _ in waits += 1 }
        )

        #expect(result == failure)
        #expect(reads == 1)
        #expect(waits == 0)
    }

    @Test @MainActor
    func pageStabilizationFailsClosedAfterExactAttemptLimit() async throws {
        var reads = 0
        var waits = 0
        let failure = try extractionAttempt(failure: .pageNotStabilized)

        let result = try await WorkBuddyAccountWebExtractionReadiness.evaluate(
            isCurrent: { true },
            read: {
                reads += 1
                return failure
            },
            wait: { _ in waits += 1 }
        )

        #expect(result == failure)
        #expect(reads == 20)
        #expect(waits == 19)
    }

    @Test @MainActor
    func extractionReadinessStopsWithoutLatePublicationAfterInvalidation() async throws {
        var isCurrent = true
        var reads = 0
        var waits = 0

        let result = try await WorkBuddyAccountWebExtractionReadiness.evaluate(
            isCurrent: { isCurrent },
            read: {
                reads += 1
                return try extractionAttempt(failure: .unexpectedPage)
            },
            wait: { _ in
                waits += 1
                isCurrent = false
            }
        )

        #expect(result == nil)
        #expect(reads == 1)
        #expect(waits == 1)
    }

    @Test
    func rendererProvidesAccountWebMainAssistantAndSettingsEvidence() throws {
        let renderer = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/PreviewRendererTool/main.swift"
            ),
            encoding: .utf8
        )
        #expect(renderer.contains("--workbuddy-account-web"))
        #expect(renderer.contains("--workbuddy-account-web-settings"))
        #expect(renderer.contains("\"10131.06\""))
        #expect(renderer.contains(".authenticatedAccountWeb(observedAt: now)"))
        #expect(renderer.contains("\"workbuddy.accountWebCredits\""))
        #expect(
            renderer.contains(
                "availabilityLifecycle: isAccountWeb ? nil : lifecycle"
            )
        )
        #expect(renderer.contains("--workbuddy-expanded"))

        let panel = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsagePanelView.swift"
            ),
            encoding: .utf8
        )
        #expect(panel.contains("isExpanded: expansionBinding(for: card.id)"))
    }

    @Test
    func accountWebSettingsAndFailuresAreLocalized() {
        #expect(
            AppLanguage.english.workBuddyAccountWebTitle
                == "Experimental Account Web Sync"
        )
        #expect(
            AppLanguage.simplifiedChinese.workBuddyAccountWebTitle
                == "实验性账号网页同步"
        )
        #expect(
            AppLanguage.english.workBuddyAccountWebState(.failed(.timedOut))
                == "Could not read current Credits"
        )
        #expect(
            AppLanguage.simplifiedChinese.workBuddyAccountWebState(
                .failed(.timedOut)
            ) == "无法读取当前积分"
        )
    }

    @Test
    func packageHelperIsCommitExactPathLockedAndFixtureFree() throws {
        let script = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "script/package_uma_workbuddy_account.sh"
            ),
            encoding: .utf8
        )
        #expect(script.contains("MARKETING_VERSION=\"0.10.1\""))
        #expect(script.contains("DEFAULT_BUILD=\"202607260001\""))
        #expect(script.contains("BUNDLE_ID=\"com.kevinchen.CodexUsageMonitor\""))
        #expect(
            script.contains(
                "/private/tmp/uma-workbuddy-autorefresh-final-$short_commit/UMA.app"
            )
        )
        #expect(script.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(script.contains("UMA-WorkBuddy-Account-Provenance.plist"))
        #expect(script.contains("UMASourceState</key><string>commit-exact"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("canonical_output_parent"))
        for forbidden in [
            "workbuddy-manual-availability.json",
            "connector-snapshots.json",
            "PreviewRendererTool",
            "Tests/",
            "source/",
            "Desktop/",
            "xattr -cr",
            "cp -R"
        ] {
            #expect(!script.contains(forbidden))
        }
    }

    @Test @MainActor
    func consentIsVersionedAndSessionChoiceRestoresWithoutAccountIdentity() {
        let suite = "M2WAccountWebSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = WorkBuddyAccountWebSessionController(defaults: defaults)
        first.sessionMode = .persistent
        first.grantConsent()
        #expect(!first.canReadOnApplicationLaunch)
        defaults.set(
            true,
            forKey: WorkBuddyAccountWebSessionController.sessionEstablishedKey
        )

        let restored = WorkBuddyAccountWebSessionController(defaults: defaults)
        #expect(restored.consentGranted)
        #expect(restored.sessionMode == .persistent)
        #expect(restored.canReadOnApplicationLaunch)
        let domain = defaults.persistentDomain(forName: suite) ?? [:]
        let serialized = String(describing: domain)
        for forbidden in [
            "email", "phone", "accountName", "organization", "cookie", "token"
        ] {
            #expect(!serialized.lowercased().contains(forbidden.lowercased()))
        }
    }

    @Test @MainActor
    func obsoleteDisclosureCannotRestoreConsent() throws {
        let suite = "M2WAccountWebSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let obsolete = WorkBuddyAccountWebConsentRecord(
            disclosureVersion:
                WorkBuddyAccountWebConsentRecord.currentDisclosureVersion - 1,
            acceptedAt: Date(),
            sessionMode: .persistent
        )
        defaults.set(
            try JSONEncoder().encode(obsolete),
            forKey: "workbuddy.accountWebSync.consent.v1"
        )

        let controller = WorkBuddyAccountWebSessionController(defaults: defaults)
        #expect(!controller.consentGranted)
        #expect(controller.sessionMode == .nonpersistent)
    }

    private func makeReading(
        remaining: String,
        used: String?,
        total: String?
    ) throws -> WorkBuddyAccountWebReading {
        let payload = accountPayload(
            subscription: [
                pool(
                    .subscriptionBase,
                    used: used ?? "0",
                    total: total ?? remaining,
                    displayed: remaining
                )
            ]
        )
        guard case let .success(reading) = WorkBuddyAccountWebExtractor.validate(
            payload,
            observedAt: Date(timeIntervalSince1970: 2_000_000_000)
        ) else {
            throw WorkBuddyAccountWebFailure.malformedCredits
        }
        return reading
    }

    private func extractionAttempt(
        _ payload: WorkBuddyAccountWebExtractionPayload? = nil,
        failure: WorkBuddyAccountWebFailure? = nil
    ) throws -> WorkBuddyAccountWebExtractionAttempt {
        var dictionary: [String: Any] = [
            "extractorVersion": WorkBuddyAccountWebReading.extractorVersion,
            "discoveredSections": [],
            "subscriptionPools": [],
            "addOnPools": [],
            "benefitGiftPools": [],
            "authoritativePageBalances": []
        ]
        if let payload {
            dictionary = try #require(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(payload)
                ) as? [String: Any]
            )
        }
        if let failure {
            dictionary["failure"] = failure.rawValue
        }
        return WorkBuddyAccountWebExtractionAttempt(
            data: try JSONSerialization.data(
                withJSONObject: dictionary,
                options: [.sortedKeys]
            ),
            failure: failure
        )
    }

    private func accountPayload(
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

private actor ScriptedWorkBuddyAccountReader {
    private var results: [WorkBuddyAccountWebReadResult]
    private(set) var readCount = 0

    init(_ results: [WorkBuddyAccountWebReadResult]) {
        self.results = results
    }

    func next() -> WorkBuddyAccountWebReadResult {
        readCount += 1
        guard !results.isEmpty else {
            return .failure(.webContentUnavailable)
        }
        return results.removeFirst()
    }
}

private actor AccountLaunchGate {
    private(set) var isOpen: Bool

    init(_ isOpen: Bool) {
        self.isOpen = isOpen
    }

    func open() {
        isOpen = true
    }
}

private actor AccountDisconnectRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
