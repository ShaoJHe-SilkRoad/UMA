import ClaudeBrowserBridgeProtocol
import Foundation
import JavaScriptCore
import Testing
@testable import CodexUsageUI

@Suite("M5-AUTO-G1 Claude automatic Browser Sync migration", .timeLimit(.minutes(1)))
struct M5AUTOG1ClaudeAutomaticRefreshTests {

    @Test
    func exactRouteExtractionWaitsOnceForClaudeSPAUsageLandmarks() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/content-script.js"
            ),
            encoding: .utf8
        )
        #expect(source.contains("const readinessTimeoutMilliseconds = 20_000"))
        #expect(source.contains("new MutationObserver(scheduleReadinessEvaluation)"))
        #expect(source.contains("requestAnimationFrame"))
        #expect(!source.contains("readinessPollMilliseconds"))
        #expect(source.contains("extractAfterUsageLandmarksRender"))
        #expect(source.contains("ROUTE_READINESS_TIMEOUT"))
        #expect(source.contains("TARGET_DATA_TIMEOUT"))
        #expect(source.contains("const routeState = extractor.usageRouteState"))
        #expect(source.contains("extractor.extractResult(document, location, new Date())"))
        #expect(source.contains("void extractAfterUsageLandmarksRender().finally"))
        #expect(!source.contains("location.reload"))
    }

    @Test
    func immutableHostIPCStartsListenerBeforeWakeAndOneCorrelatedUsageRead() throws {
        let integration = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
            ),
            encoding: .utf8
        )
        let adapter = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
            ),
            encoding: .utf8
        )
        #expect(integration.contains("guard let runtime = ClaudeSafariHostClientAdapter()"))
        #expect(integration.contains("startListening: { handler in _ = await runtime.start(handler) }"))
        #expect(integration.contains("await runtime.submit(requestID: requestID, oneShot: allowSafariLaunch)"))
        #expect(adapter.contains("guard listen() else"))
        #expect(adapter.contains("guard await wakeHost() else"))
        #expect(adapter.contains("waiters[request.requestID] = continuation"))
        #expect(adapter.contains("try client.submit(request)"))
        #expect(adapter.contains("activeWorkRequestIDs.isEmpty"))
        #expect(adapter.contains("activeWorkRequestIDs.insert(normalizedRequestID)"))
        #expect(!integration.contains("SFSafariApplication.dispatchMessage"))

        let background = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )
        #expect(background.contains("command.command === config.wakeMessageName"))
        #expect(background.contains("qualifyRuntime(command.requestID, portGeneration)"))
        #expect(background.contains("runtimeQualificationRequest(requestID)"))
        #expect(background.contains("runtimeQualificationAcknowledgement(reply)"))
        #expect(!background.contains("automationEnvelope(command.requestID, \"bridgeReady\")"))
        #expect(background.contains("command.command === config.automaticRefreshMessageName"))

        let loader = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Safari/background-loader.js"
            ),
            encoding: .utf8
        )
        #expect(loader.contains("wakeMessageName: \"umaClaudeWakeBridge\""))
        #expect(!loader.contains("importScripts"))
    }

    @Test @MainActor
    func wrongRouteRejectsBeforeAnyDOMInspectionAndLoginGuardRunsFirstOnUsageRoute() throws {
        let context = try #require(JSContext())
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/claude-usage-extractor.js"
            ),
            encoding: .utf8
        )
        context.evaluateScript(source)
        let result = context.evaluateScript(
            """
            (() => {
              let wrongRouteQueries = 0;
              const documentLike = {
                querySelector: () => { wrongRouteQueries += 1; return null; },
                querySelectorAll: () => { wrongRouteQueries += 1; return []; },
              };
              const wrong = UMAClaudeUsageExtractor.extractResult(
                documentLike,
                {protocol: "https:", origin: "https://claude.ai", pathname: "/new", search: "", hash: "#chat"},
                new Date("2026-08-02T12:00:00Z")
              );
              let loginQueryCount = 0;
              const login = UMAClaudeUsageExtractor.extractResult(
                {
                  querySelector: () => { loginQueryCount += 1; return {}; },
                  querySelectorAll: () => { throw new Error("Usage scan must not run"); },
                },
                {protocol: "https:", origin: "https://claude.ai", pathname: "/new", search: "", hash: "#settings/usage"},
                new Date("2026-08-02T12:00:00Z")
              );
              return wrong.status === "routeRejected"
                && wrongRouteQueries === 0
                && login.status === "signInRequired"
                && loginQueryCount === 1;
            })()
            """
        )?.toBool()
        #expect(result == true)
    }

    @Test @MainActor
    func priorManualConsentDoesNotSilentlyMigrateToRecurringAutomation() throws {
        let suite = "uma-m5-auto-consent-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ClaudeBrowserSyncConsent.v1")

        let store = ClaudeBrowserConsentStore(defaults: defaults)
        #expect(!store.consentGranted)
        #expect(!store.autoRefreshEnabled)
        #expect(!store.allowSafariLaunch)
    }

    @Test @MainActor
    func explicitContinueEnablesLocalSmartModeWithoutRecurringSafari() async throws {
        let suite = "uma-m5-auto-explicit-consent-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = BrowserConnectorFixture(consent: true)
        let store = ClaudeBrowserConsentStore(defaults: defaults)
        let model = ClaudeBrowserSettingsModel(
            connector: fixture.connector(),
            consentStore: store
        )

        model.connectWithConsent()
        try await waitForClaudeValue(model.$actionInProgress, matching: { !$0 })
        #expect(store.consentGranted)
        #expect(!store.autoRefreshEnabled)
        #expect(!store.allowSafariLaunch)
        #expect(!model.autoRefreshEnabled)
        #expect(!model.allowSafariLaunch)
    }

    @Test
    func applicationLaunchStartsLocalSmartSourceBeforePassiveStartupAndAdmissionScan() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "await claudeConnector.start()"))
        let passive = try #require(source.range(of: "await registry.startPassiveConnectors()"))
        let scan = try #require(source.range(of: "trigger: .applicationLaunch"))
        #expect(start.lowerBound < passive.lowerBound)
        #expect(start.lowerBound < scan.lowerBound)
    }

    @Test
    func legacyAutomationPreferenceCannotStartListenerOrBrowserCycle() async {
        let sleeper = BrowserTestSleeper()
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector { interval in
            try await sleeper.sleep(interval)
        }

        await connector.automationPreferenceChanged()
        #expect(await sleeper.intervals.isEmpty)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect((await connector.diagnostics()).listenerStartCount == 0)
        #expect(!(await connector.diagnostics()).schedulerActive)
        await connector.disconnect()
    }

    @Test
    func localStartCreatesNoBrowserListenerOrSafariScheduler() async {
        let sleeper = BrowserTestSleeper()
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector { interval in
            try await sleeper.sleep(interval)
        }
        await connector.start()
        #expect(await sleeper.intervals.isEmpty)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect((await connector.diagnostics()).listenerStartCount == 0)
        #expect((await connector.diagnostics()).automaticDispatchCount == 0)
        #expect((await connector.diagnostics()).scheduledCycleCount == 0)
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        #expect(!(await connector.diagnostics()).schedulerActive)
        await connector.disconnect()
    }

    @Test
    func manualRefreshIsLocalOnlyAndAccuracySyncIsTheBrowserGate() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.syncNow()
        await connector.syncNow()
        await connector.syncNow()
        #expect(await fixture.bridge.automaticRequests.isEmpty)

        await connector.accuracySync()
        #expect(await fixture.bridge.automaticRequests.count == 1)
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(requestID: requestID, status: .tabUnavailable)
        await connector.disconnect()
    }

    @Test
    func tenManualRefreshesNeverCreateARecurringBrowserCycle() async {
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector()
        for _ in 0..<10 { await connector.syncNow() }
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect((await connector.diagnostics()).automaticDispatchCount == 0)
        #expect((await connector.diagnostics()).scheduledCycleCount == 0)
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        #expect(!(await connector.diagnostics()).schedulerActive)
        await connector.disconnect()
    }

    @Test
    func permissionAndAuthenticationUncertaintySuspendAutomation() async {
        for (status, expected) in [
            (ClaudeBrowserAutomationStatus.permissionRequired, ClaudeConnectorLifecycleState.websiteAccessRequired),
            (.signInRequired, .signInRequired),
        ] {
            let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
            let connector = fixture.connector()
            await connector.accuracySync()
            let requestID = await fixture.bridge.automaticRequests[0].requestID
            await fixture.bridge.sendAutomation(requestID: requestID, status: status)
            _ = expected
            #expect((await connector.diagnostics()).rejectedObservationCount == 0)
            #expect(!(await connector.diagnostics()).schedulerActive)
            #expect(!(await connector.currentSnapshot()).hasValidData)
            await connector.disconnect()
        }
    }

    @Test
    func transientUsageUnavailabilityEndsOneShotWithoutRetry() async {
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector()
        await connector.accuracySync()
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(
            requestID: requestID,
            status: .usageUnavailable
        )

        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect(!(await connector.diagnostics()).schedulerActive)
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        #expect(!(await connector.currentSnapshot()).hasValidData)
        await connector.disconnect()
    }

    @Test
    func ownershipUncertaintyFailsClosedAndSuspendsAutomation() async {
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector()
        await connector.accuracySync()
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(
            requestID: requestID,
            status: .ownedTabOwnershipLost
        )
        #expect((await connector.diagnostics()).automaticDispatchCount == 1)
        #expect(!(await connector.currentSnapshot()).hasValidData)
        #expect(!(await connector.diagnostics()).schedulerActive)
        await connector.disconnect()
    }

    @Test
    func SafariUnavailableAffectsOnlyExplicitAccuracySync() async {
        for allowed in [false, true] {
            let fixture = BrowserConnectorFixture(
                consent: true,
                autoRefresh: true,
                allowSafariLaunch: allowed
            )
            await fixture.bridge.setAutomaticDispatchResult(.browserUnavailable)
            let connector = fixture.connector()
            await connector.accuracySync()
            #expect(await fixture.bridge.automaticRequests.count == 1)
            #expect(await fixture.bridge.automaticRequests[0].allowSafariLaunch)
            #expect((await connector.diagnostics()).automaticDispatchCount == 0)
            #expect(!(await connector.diagnostics()).schedulerActive)
            #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
            await connector.disconnect()
        }
    }

    @Test
    func disconnectClosesOnlyTheCurrentRequestAndCancelsTheScheduler() async {
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector()
        await connector.accuracySync()
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await connector.disconnect()

        #expect(await fixture.bridge.closedRequestIDs == [requestID])
        #expect(!(await fixture.consent.get()))
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        #expect(!(await connector.diagnostics()).schedulerActive)
        #expect(!(await connector.currentSnapshot()).hasValidData)
    }

    @Test
    func twentyAccuracyCollisionsStillProduceOneProviderRead() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        for _ in 0..<20 { await connector.accuracySync() }
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect((await connector.diagnostics()).coalescedActionCount == 19)
        await connector.disconnect()
    }

    @Test
    func tenSuccessfulFixtureReadsRemainSerializedAndWriteOnlySanitizedCache() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()

        for index in 0..<10 {
            await connector.accuracySync()
            #expect(await fixture.bridge.automaticRequests.count == index + 1)
            await fixture.bridge.send(browserEnvelope(
                five: Double(10 + index),
                seven: Double(20 + index)
            ))
            #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        }

        #expect((await connector.diagnostics()).acceptedObservationCount == 10)
        #expect(await fixture.cache.writeCount == 0)
        #expect(await fixture.bridge.startCount == 1)
        await connector.disconnect()
    }

    @Test
    func tenRejectedRouteReadsFailClosedWithoutRetryOrAdmission() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()

        for index in 0..<10 {
            await connector.accuracySync()
            let request = await fixture.bridge.automaticRequests[index]
            await fixture.bridge.sendAutomation(
                requestID: request.requestID,
                status: .routeRejected
            )
            #expect(!(await connector.currentSnapshot()).hasValidData)
            #expect(!(await connector.diagnostics()).schedulerActive)
        }

        #expect(await fixture.bridge.automaticRequests.count == 10)
        #expect(await fixture.cache.writeCount == 0)
        #expect((await connector.diagnostics()).automaticDispatchCount == 10)
        await connector.disconnect()
    }

    @Test
    func tenOwnedTabClosuresRecreateOnlyOnTheNextExplicitCycle() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()

        for index in 0..<10 {
            await connector.accuracySync()
            let request = await fixture.bridge.automaticRequests[index]
            await fixture.bridge.sendAutomation(
                requestID: request.requestID,
                status: .ownedTabClosed
            )
            #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
            #expect(await fixture.bridge.automaticRequests.count == index + 1)
        }

        #expect(await fixture.bridge.automaticRequests.count == 10)
        await connector.disconnect()
    }

    @Test
    func tenConnectDisconnectCyclesLeaveOneListenerAndNoPendingReadPerCycle() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()

        for index in 0..<10 {
            await fixture.consent.set(true)
            await connector.accuracySync()
            #expect(await fixture.bridge.startCount == index + 1)
            await connector.disconnect()
            #expect(await fixture.bridge.stopCount == index + 1)
            #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
            #expect(!(await connector.diagnostics()).schedulerActive)
        }

        #expect(await fixture.bridge.automaticRequests.count == 10)
        #expect(await fixture.bridge.closedRequestIDs.count == 10)
    }

    @Test
    func fiveRelaunchCyclesRemainLocalUntilExplicitAccuracyAndLeaveNoOwnedWork() async {
        let fixture = BrowserConnectorFixture(consent: true)

        for cycle in 0..<5 {
            let connector = fixture.connector()
            await connector.start()
            #expect(!(await connector.currentSnapshot()).hasValidData)

            #expect(await fixture.bridge.automaticRequests.count == cycle)
            await connector.accuracySync()
            #expect(await fixture.bridge.automaticRequests.count == cycle + 1)
            await fixture.bridge.send(browserEnvelope(
                five: Double(20 + cycle),
                seven: Double(40 + cycle)
            ))
            #expect((await connector.diagnostics()).acceptedObservationCount == 1)

            await connector.stop()
            #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
            #expect(!(await connector.diagnostics()).schedulerActive)
        }

        #expect(await fixture.bridge.startCount == 5)
        #expect(await fixture.bridge.stopCount == 5)
        #expect(await fixture.cache.writeCount == 0)
        #expect(await fixture.bridge.closedRequestIDs.isEmpty)
    }

    @Test
    func fiveWakeSignalsRefreshLocalInputsWithoutBrowserReads() async {
        let sleeper = BrowserTestSleeper()
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector { interval in
            try await sleeper.sleep(interval)
        }
        await connector.start()

        for _ in 0..<5 {
            await connector.refresh(trigger: .wake)
        }

        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect(await sleeper.intervals.isEmpty)
        #expect(!(await connector.diagnostics()).schedulerActive)
        await connector.disconnect()
    }

    @Test
    func thirtyMinuteIdleSimulationRetainsStaleExactWithoutRewritingLegacyCache() async {
        let clock = BrowserTestClock()
        let fixture = BrowserConnectorFixture(consent: true, clock: clock)
        let connector = fixture.connector()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 25, seven: 50))
        #expect((await connector.diagnostics()).acceptedObservationCount == 1)
        #expect(await fixture.cache.writeCount == 0)

        clock.advance(30 * 60)
        let retained = await connector.currentSnapshot()
        #expect(retained.hasValidData)
        #expect(retained.freshness == .stale)
        #expect(retained.safeFailure == .unavailable)
        #expect(await fixture.cache.writeCount == 0)
        await connector.disconnect()
        #expect(await fixture.cache.clearCount == 1)
    }

    @Test
    func productionRetainsLegacyConstantsButAdvertisesNoAutomaticRefresh() {
        #expect(ClaudeCodeUsageConnector.automaticRefreshInterval == 5 * 60)
        #expect(ClaudeCodeUsageConnector.minimumAutomaticRefreshInterval == 3 * 60)
        #expect(ClaudeCodeUsageConnector.automaticRefreshInterval
            >= ClaudeCodeUsageConnector.minimumAutomaticRefreshInterval)
        #expect(!ClaudeCodeUsageConnector.production().descriptor.capabilities.contains(.automaticRefresh))
    }

    @Test
    func settingsReplaceRecurringAutomationWithLocalSmartAndAccuracyActions() throws {
        let root = autoBrowserRepositoryRoot()
        let settings = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
            ),
            encoding: .utf8
        )
        let language = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/CodexUsageUI/Models/AppLanguage+Claude.swift"
            ),
            encoding: .utf8
        )
        for required in [
            "Claude Local Smart Mode", "Accuracy Sync",
            "version-pinned plan cache provides only ≈-labeled estimates without reset times",
        ] {
            #expect(settings.contains(required))
        }
        for required in [
            "needs access to claude.ai", "Sign in to Claude in Safari",
            "Accuracy Sync is running",
        ] {
            #expect(language.contains(required))
        }
        #expect(language.contains("Last exact observation"))
        #expect(!settings.contains("Every 5 minutes"))
        #expect(!settings.contains("Allow UMA to launch Safari when needed"))
        #expect(language.contains("Claude 精确同步 · 按需"))
        #expect(!language.contains("toolbar click"))
    }

    @Test
    func packageHelperShipsRelayAndRetiresAutomaticBrowserAcceptance() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "script/package_uma_m5_g2.sh"
            ),
            encoding: .utf8
        )
        #expect(source.contains("readonly DELIVERY_VOLUME=\"/Volumes/HE/DEV\""))
        #expect(source.contains("readonly DELIVERY_BASE=\"$DELIVERY_VOLUME/UMA\""))
        #expect(source.contains("readonly DELIVERY_ROOT=\"$DELIVERY_BASE/Packages\""))
        #expect(!source.contains("readonly DELIVERY_ROOT=\"$HOME/Developer/UMA-Packages\""))
        #expect(source.contains("Required external APFS volume is not mounted"))
        #expect(source.contains("/sbin/mount | /usr/bin/awk -v volume=\"$DELIVERY_VOLUME\""))
        #expect(source.contains("Refusing unsafe or unwritable delivery base"))
        #expect(source.contains("Refusing symlinked delivery root"))
        #expect(source.contains("Refusing unsafe or unwritable delivery root"))

        for required in [
            "ClaudeStatusLineRelay",
            "ClaudeSource",
            "Local Smart Mode with on-demand Accuracy Sync",
            "m5rmx-smart-preflight",
            "working-tree-smart-preflight",
            "LOCAL-SMART-LIVE-PREFLIGHT",
            "m5rmx-smart-live-link-preflight",
            "uma-m5rmx-smart-live-link-preflight-${commit:0:12}-$build_number/UMA.app",
            "working-tree-smart-live-link-preflight",
            "LOCAL-SMART-LIVE-LINK-PREFLIGHT",
            "m5rmx-smart-0.13-preflight",
            "uma-0.13-dev-${commit:0:12}-$build_number/UMA_0.13.0.app",
            "working-tree-smart-0.13-preflight",
            "UMA-0.13-SINGLE-ACTIVE-LOCAL-SMART-PREFLIGHT",
            "resolved_marketing_version=\"0.13.0\"",
            "requires an explicit 12-digit build",
            "requires a Developer ID Application identity",
            "does not submit for notarization",
        ] {
            #expect(source.contains(required))
        }
        #expect(source.contains("readonly STATUS_RELAY=\"ClaudeStatusLineRelay\""))
        #expect(source.contains(
            "uma-m5rmx-smart-package-$phase-$commit-$build_number"
        ))
        #expect(source.contains(
            "|| \"$phase\" == \"m5rmx-smart-live-link-preflight\""
        ))
        #expect(source.contains(
            "|| \"$phase\" == \"m5rmx-smart-0.13-preflight\""
        ))

        let smart013Start = try #require(source.range(
            of: "    m5rmx-smart-0.13-preflight)"
        ))
        let smart013Tail = source[smart013Start.lowerBound...]
        let smart013End = try #require(smart013Tail.range(of: "    *) usage >&2; exit 2 ;;"))
        let smart013Block = String(smart013Tail[..<smart013End.lowerBound])
        #expect(!smart013Block.contains("requires a Developer ID Application identity"))
        #expect(smart013Block.contains("signing_provenance=\"AD-HOC UNSIGNED DEVELOPMENT\""))
        #expect(smart013Block.contains("notarization_eligible=\"false\""))
        #expect(smart013Block.contains("does not submit for notarization"))

        // Ad-hoc signing is a single-phase, unsigned-development exception.
        // Every historical, final, and signed phase is rejected by the phase fence.
        #expect(source.contains(
            "[[ \"$signing_identity\" == \"-\" && \"$phase\" != \"m5rmx-smart-0.13-preflight\" ]]"
        ))
        #expect(source.contains(
            "Ad-hoc signing is allowed only for the M5RMX Smart 0.13 development preflight."
        ))
        #expect(source.contains("^Signature=adhoc$"))
        #expect(source.contains("/usr/bin/codesign --verify --deep --strict --verbose=2 \"$output\""))
        #expect(source.contains("<key>SigningProvenance</key><string>$signing_provenance</string>"))
        #expect(source.contains("<key>NotarizationEligible</key><$notarization_eligible/>"))
        #expect(source.contains("Notarization requires --signing-identity"))
        #expect(source.contains("[[ ! -e \"$output\" && ! -L \"$output\" ]]"))
        #expect(source.contains("Refusing to overwrite"))
        #expect(source.contains("[[ ! -e \"$output_parent\" && ! -L \"$output_parent\" ]]"))
        #expect(source.contains("Refusing existing package parent"))

        let ledger = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "source/UMA M5RMX QA Issue Ledger.md"
            ),
            encoding: .utf8
        )
        #expect(ledger.contains("SMART-19"))
        #expect(ledger.contains("explicit 12-digit build"))
        #expect(ledger.contains("must not be overwritten"))
        #expect(ledger.contains("SMART-23"))

        let scope = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "source/UMA M5RMX Scope Lock.md"
            ),
            encoding: .utf8
        )
        #expect(scope.contains("/Volumes/HE/DEV/UMA/Packages/uma-0.13-dev-"))
        #expect(scope.contains("Only this temporary development phase may use truthfully recorded"))
        #expect(scope.contains("historical, final, and signed phases still require Developer ID"))
    }

    @Test
    func advisorySafariInventoryStateAllowsAuthoritativeHandshakeAndOneShotCallback() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await fixture.bridge.setHealth(.inventoryLoading)

        await connector.start()
        await connector.checkCompanion()
        #expect(await fixture.bridge.verificationCount == 1)

        await connector.accuracySync()
        try await fixture.bridge.waitForAutomaticRequest()
        #expect(await fixture.bridge.automaticRequests.count == 1)
        await fixture.bridge.send(browserEnvelope(five: 25, seven: 50))
        #expect((await connector.currentSnapshot()).hasValidData)
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        #expect(!(await connector.diagnostics()).schedulerActive)
    }

    @Test
    func safariInventoryAPIIsAdvisoryAndImmutableHostHandshakeIsAuthoritative() throws {
        let production = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
            ),
            encoding: .utf8
        )
        #expect(production.contains("Mutable UMA never uses Safari inventory as an authority"))
        #expect(production.contains("var permitsDirectHandshake: Bool { true }"))
        #expect(production.contains("switch await runtime.verify()"))
        #expect(production.contains("case .verified: .ready"))
        #expect(!production.contains("SFSafariExtensionManager"))
        #expect(!production.contains("embeddedSafariExtensionHealth"))
    }


    @Test
    func disabledOrFailedCompanionCannotProduceAnAccuracyAnchor() async throws {
        let disabled = BrowserConnectorFixture(consent: true)
        let disabledConnector = disabled.connector()
        await disabled.bridge.setHealth(.disabled)
        await disabledConnector.accuracySync()
        #expect(await disabled.bridge.automaticRequests.isEmpty)
        #expect(!(await disabledConnector.currentSnapshot()).hasValidData)

        let failed = BrowserConnectorFixture(consent: true)
        let failedConnector = failed.connector()
        await failed.bridge.setHealth(.inventoryRestartRequired)
        await failed.bridge.setAutomaticDispatchResult(.companionUnavailable)
        await failedConnector.accuracySync()
        #expect(await failed.bridge.automaticRequests.count == 1)
        #expect(!(await failedConnector.currentSnapshot()).hasValidData)
        #expect(!(await failedConnector.diagnostics()).automaticRefreshInFlight)
    }
}

private func autoBrowserRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
