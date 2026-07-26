import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2WACCOUNT-G1 WorkBuddy account web sync")
struct M2WAccountWebSyncTests {
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
    func sanitizedRowsProduceExactDecimalAccountBalance() throws {
        let observedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let payload = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: 1,
            rows: [
                WorkBuddyAccountWebSanitizedRow(
                    remaining: "2000",
                    used: "100",
                    total: "2100"
                ),
                WorkBuddyAccountWebSanitizedRow(
                    remaining: "99.47",
                    used: "0",
                    total: "99.47"
                )
            ]
        )

        guard case let .success(reading) = WorkBuddyAccountWebExtractor.validate(
            payload,
            observedAt: observedAt
        ) else {
            Issue.record("Expected an exact sanitized Credit reading")
            return
        }

        #expect(CreditDecimalCodec.canonicalString(reading.balance.remaining) == "2099.47")
        #expect(reading.balance.used.map(CreditDecimalCodec.canonicalString) == "100")
        #expect(reading.balance.total.map(CreditDecimalCodec.canonicalString) == "2199.47")
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
        let malformed = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: 1,
            rows: [
                WorkBuddyAccountWebSanitizedRow(
                    remaining: "2,099.47",
                    used: nil,
                    total: nil
                )
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(malformed, observedAt: now)
                == .failure(.malformedCredits)
        )

        let duplicate = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: 1,
            rows: [
                WorkBuddyAccountWebSanitizedRow(
                    remaining: "500",
                    used: nil,
                    total: nil
                ),
                WorkBuddyAccountWebSanitizedRow(
                    remaining: "500",
                    used: nil,
                    total: nil
                )
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(duplicate, observedAt: now)
                == .failure(.ambiguousCredits)
        )

        let inconsistent = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: 1,
            rows: [
                WorkBuddyAccountWebSanitizedRow(
                    remaining: "2099.47",
                    used: "100",
                    total: "2000"
                )
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(inconsistent, observedAt: now)
                == .failure(.ambiguousCredits)
        )

        let noncanonical = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: 1,
            rows: [
                WorkBuddyAccountWebSanitizedRow(
                    remaining: "01",
                    used: nil,
                    total: nil
                )
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(noncanonical, observedAt: now)
                == .failure(.malformedCredits)
        )

        let excessivePrecision = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: 1,
            rows: [
                WorkBuddyAccountWebSanitizedRow(
                    remaining:
                        "0.123456789012345678901234567890123456789",
                    used: nil,
                    total: nil
                )
            ]
        )
        #expect(
            WorkBuddyAccountWebExtractor.validate(
                excessivePrecision,
                observedAt: now
            ) == .failure(.malformedCredits)
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
        #expect(
            connector.descriptor.privacyAllowlist == [
                "remainingCredits",
                "usedCredits",
                "totalCredits",
                "observedAt",
                "extractorVersion"
            ]
        )

        let assistant = DesktopAssistantCard(shared: cards[0], language: .english)
        #expect(assistant.sourceMark == .accountWeb)
        #expect(assistant.detailText == "Account web sync")
        #expect(assistant.regularUsageText == "2,099.47")
        #expect(assistant.usageValue == .credits("2.1k"))
        #expect(assistant.tintFraction != nil)

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
        #expect(controller.contains("WKWebsiteDataStore.remove("))
        #expect(controller.contains("forIdentifier:"))
    }

    @Test
    func onlyExplicitTriggersCanReadAccountWebCredits() throws {
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
            WorkBuddyAccountWebExtractionPayload(
                extractorVersion: 1,
                rows: [
                    WorkBuddyAccountWebSanitizedRow(
                        remaining: "2099.47",
                        used: nil,
                        total: nil
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
    func extractionReadinessFailsClosedAfterExactAttemptLimit() async throws {
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
        #expect(renderer.contains("\"2099.47\""))
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
                == "Sync unavailable: request timed out"
        )
        #expect(
            AppLanguage.simplifiedChinese.workBuddyAccountWebState(
                .failed(.timedOut)
            ) == "同步不可用：请求超时"
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
        #expect(script.contains("DEFAULT_BUILD=\"202607250006\""))
        #expect(script.contains("BUNDLE_ID=\"com.kevinchen.CodexUsageMonitor\""))
        #expect(
            script.contains(
                "/private/tmp/uma-workbuddy-account-final-$short_commit/UMA.app"
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
        let payload = WorkBuddyAccountWebExtractionPayload(
            extractorVersion: 1,
            rows: [
                WorkBuddyAccountWebSanitizedRow(
                    remaining: remaining,
                    used: used,
                    total: total
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
            "rows": []
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
