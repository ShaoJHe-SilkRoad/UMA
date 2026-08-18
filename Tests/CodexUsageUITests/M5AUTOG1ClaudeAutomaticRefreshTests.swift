import ClaudeBrowserBridgeProtocol
import Foundation
import JavaScriptCore
import Testing
@testable import CodexUsageUI

@Suite("M5-AUTO-G1 Claude automatic Browser Sync")
struct M5AUTOG1ClaudeAutomaticRefreshTests {
    @Test
    func safariManifestUsesOnlyTheExactPersistentUsageScope() throws {
        let root = autoBrowserRepositoryRoot()
        let data = try Data(contentsOf: root.appendingPathComponent(
            "BrowserExtension/Safari/manifest.json"
        ))
        let manifest = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(manifest["manifest_version"] as? Int == 2)
        #expect(manifest["permissions"] as? [String] == [
            "nativeMessaging",
            "storage",
            "https://claude.ai/new*",
        ])
        #expect(manifest["host_permissions"] == nil)
        let background = try #require(manifest["background"] as? [String: Any])
        #expect(background["scripts"] as? [String] == [
            "Shared/claude-usage-extractor.js",
            "Safari/background-loader.js",
            "Shared/background-core.js",
        ])
        #expect(background["persistent"] as? Bool == true)
        #expect(background["service_worker"] == nil)
        #expect(manifest["content_scripts"] == nil)
        #expect(manifest["action"] == nil)

        let text = String(decoding: data, as: UTF8.self)
        for forbidden in [
            "activeTab", "\"tabs\"", "cookies", "history",
            "webRequest", "webNavigation", "<all_urls>", "accounts.google.com",
        ] {
            #expect(!text.contains(forbidden))
        }

        let extensionInfo = try #require(
            NSDictionary(contentsOf: root.appendingPathComponent(
                "BrowserExtension/Safari/Native/Info.plist"
            )) as? [String: Any]
        )
        #expect(extensionInfo["CFBundleShortVersionString"] as? String == "1.3.0")
        #expect(extensionInfo["CFBundleVersion"] as? String == "8")
    }

    @Test @MainActor
    func safariPersistentBackgroundScriptsInstallTheControlListenerWithoutWorkerGlobals() throws {
        let root = autoBrowserRepositoryRoot()
        let context = try #require(JSContext())
        context.evaluateScript(
            """
            globalThis.listenerCount = 0;
            globalThis.nativeMessageCount = 0;
            globalThis.browser = {
              runtime: {
                onMessage: { addListener: () => { listenerCount += 1; } },
                connectNative: () => ({
                  onMessage: { addListener: () => {} },
                  onDisconnect: { addListener: () => {} },
                }),
                sendNativeMessage: () => {
                  nativeMessageCount += 1;
                  return Promise.resolve({ok: true});
                },
              },
            };
            """
        )
        for relativePath in [
            "BrowserExtension/Shared/claude-usage-extractor.js",
            "BrowserExtension/Safari/background-loader.js",
            "BrowserExtension/Shared/background-core.js",
        ] {
            context.exception = nil
            context.evaluateScript(try String(
                contentsOf: root.appendingPathComponent(relativePath),
                encoding: .utf8
            ))
            #expect(context.exception == nil)
        }
        #expect(context.evaluateScript("listenerCount")?.toInt32() == 1)
        #expect(context.evaluateScript("UMA_BROWSER_CONFIG.browserFamily")?.toString() == "safari")
        #expect(context.evaluateScript("typeof importScripts")?.toString() == "undefined")
    }

    @Test
    func safariWorkerClosesEachProvenOwnedTabWithoutEnumeratingOrAdoptingUserTabs() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )
        #expect(source.contains("api.tabs.create({ url: extractor.CONTRACT.href, active: false })"))
        #expect(source.contains("api.tabs.get(read.tabID)"))
        #expect(source.contains("api.tabs.remove(record.tabID)"))
        #expect(source.contains("api.tabs.reload(record.tabID)"))
        #expect(source.contains("const navigationSettleMilliseconds = 1_000"))
        #expect(source.contains("await delay(navigationSettleMilliseconds)"))
        #expect(source.contains("umaClaudeOwnedUsageTab.v1"))
        #expect(source.contains("proveOwnedTab(record, tab)"))
        #expect(source.contains("ownedTabOwnershipLost"))
        #expect(source.contains("automaticRead = null"))
        #expect(source.contains("if (read.record && !(await closeProvenOwnedTab(read.record)))"))
        #expect(source.contains("finalStatus = \"ownedTabOwnershipLost\""))
        #expect(source.contains("if (!redirectedTerminalStatuses.has(status))"))
        #expect(source.contains("function redirectedTerminalStatusForURL(raw)"))
        #expect(source.contains(
            "finishAutomatic(read, redirectedTerminalStatusForURL(tab.url || \"\"))"
        ))
        #expect(source.contains("const proven = await proveOwnedTab(record, tab)"))
        #expect(source.contains(
            "await api.tabs.remove(record.tabID);\n"
                + "    } catch (_) {\n"
                + "      return false;"
        ))
        #expect(!source.contains("ownershipProven"))
        #expect(!source.contains(
            "if (status === \"tabUnavailable\") {\n      await clearOwnershipRecord();"
        ))
        #expect(source.contains("api.permissions.contains({ origins: [config.exactHostPermission] })"))
        #expect(source.contains("api.runtime.connectNative(config.nativeApplication)"))
        #expect(source.contains("api.scripting?.executeScript"))
        #expect(source.contains("api.tabs?.executeScript"))
        #expect(source.contains("await api.tabs.executeScript(tab.id, { file, allFrames: false })"))
        #expect(source.contains("let nativePort = null"))
        #expect(source.contains("nativePort = port"))
        #expect(source.contains("port.onDisconnect?.addListener"))
        #expect(!source.contains("await closeExactOwnedTab(read);"))
        #expect(source.contains("await storeOwnershipRecord(record)"))
        #expect(source.contains("await clearOwnershipRecord()"))
        #expect(!source.contains("if (!proven) {\n      await clearOwnershipRecord();"))
        for forbidden in [
            "tabs.query", "tabs.onUpdated", "tabs.onCreated", "active: true",
            "windowId", "cookie", "localStorage", "sessionStorage", "eval(",
        ] {
            #expect(!source.contains(forbidden))
        }
    }

    @Test
    func containingAppCommandsReachTheAutomaticRuntimeHandler() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )
        #expect(source.contains("if (!sender?.tab && unpackNativeCommand(message))"))
        #expect(source.contains("handleCommandMessage(message)"))
        #expect(source.contains("command.command === config.wakeMessageName"))
        #expect(source.contains("command.command === config.automaticRefreshMessageName"))
        #expect(source.contains("command.command === config.closeOwnedTabMessageName"))
    }

    @Test
    func ownedTabProofIsBoundedToAnIsolatedTokenAndExactRoute() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/content-script.js"
            ),
            encoding: .utf8
        )
        #expect(source.contains("umaClaudeOwnedTabBind"))
        #expect(source.contains("umaClaudeOwnedTabChallenge"))
        #expect(source.contains("umaClaudeOwnedTabProof"))
        #expect(source.contains("extractor.exactUsageURL(globalThis.location)"))
        #expect(source.contains("ownershipToken: null"))
        for forbidden in ["localStorage", "sessionStorage", "document.cookie"] {
            #expect(!source.contains(forbidden))
        }
    }

    @Test
    func exactRouteExtractionWaitsOnceForClaudeSPAUsageLandmarks() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/content-script.js"
            ),
            encoding: .utf8
        )
        #expect(source.contains("const readinessTimeoutMilliseconds = 20_000"))
        #expect(source.contains("const readinessPollMilliseconds = 500"))
        #expect(source.contains("extractAfterUsageLandmarksRender"))
        #expect(source.contains("result.status !== \"usageUnavailable\""))
        #expect(source.contains("extractor.extractResult(document, location, new Date())"))
        #expect(source.contains("void extractAfterUsageLandmarksRender().finally"))
        #expect(!source.contains("location.reload"))
    }

    @Test
    func safariDispatchSettlesOneWakeBeforeOneUsageRead() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
            ),
            encoding: .utf8
        )
        #expect(source.contains("private static let safariWakeMessageName"))
        #expect(source.contains("private static let safariWorkerSettleTimeout: TimeInterval = 5"))
        #expect(source.contains("await runtime.prepareBridgeReady(requestID)"))
        #expect(source.contains("await runtime.waitForBridgeReady("))
        #expect(source.contains("await runtime.cancelBridgeReady(requestID)"))
        #expect(source.contains("There is no wake or refresh retry."))
        #expect(!source.contains("guard await runtime.waitForBridgeReady"))
        #expect(source.contains("DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2)"))
        #expect(source.contains("return delivered ? .dispatched : .companionUnavailable"))
        #expect(source.contains("ensureSafariRunning(allowLaunch: allowSafariLaunch)"))
        #expect(source.contains("configuration.activates = false"))
        #expect(source.contains("configuration.createsNewApplicationInstance = false"))
        #expect(source.contains("Task.sleep(for: .milliseconds(250))"))

        let background = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )
        #expect(background.contains("command.command === config.wakeMessageName"))
        #expect(background.contains("automationEnvelope(command.requestID, \"bridgeReady\")"))
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
    func explicitContinueTurnsAutoRefreshOnButLeavesSafariLaunchOff() async throws {
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
        for _ in 0..<100 where !model.consentGranted { await Task.yield() }
        #expect(store.consentGranted)
        #expect(store.autoRefreshEnabled)
        #expect(!store.allowSafariLaunch)
        #expect(model.autoRefreshEnabled)
        #expect(!model.allowSafariLaunch)
    }

    @Test
    func previouslyConsentedApplicationLaunchStartsBrowserSourceBeforePassiveStartupAndAdmissionScan() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
            ),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "await claudeConnector.start()"))
        let passive = try #require(source.range(of: "await registry.startPassiveConnectors()"))
        let scan = try #require(source.range(
            of: "registry.scanSurfaceAdmissions(\n                trigger: .applicationLaunch"
        ))
        #expect(start.lowerBound < passive.lowerBound)
        #expect(start.lowerBound < scan.lowerBound)
    }

    @Test
    func enablingAutomationBeforeRuntimeStartupCreatesListenerThenOneImmediateCycle() async {
        let sleeper = BrowserTestSleeper()
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector { interval in
            try await sleeper.sleep(interval)
        }

        await connector.automationPreferenceChanged()
        await waitForIntervals(sleeper, count: 1)
        #expect(await sleeper.intervals == [0])
        #expect((await connector.diagnostics()).listenerStartCount == 1)

        await sleeper.resumeNext()
        await waitForRequests(fixture.bridge, count: 1)
        #expect(await fixture.bridge.automaticRequests.count == 1)
        await fixture.bridge.sendAutomation(
            requestID: await fixture.bridge.automaticRequests[0].requestID,
            status: .tabUnavailable
        )
        await connector.disconnect()
    }

    @Test
    func schedulerStartsOnceAndSchedulesFiveMinutesAfterCompletion() async {
        let sleeper = BrowserTestSleeper()
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector { interval in
            try await sleeper.sleep(interval)
        }
        await connector.start()
        await waitForIntervals(sleeper, count: 1)
        #expect(await sleeper.intervals.first == 0)

        await sleeper.resumeNext()
        await waitForRequests(fixture.bridge, count: 1)
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        #expect((await connector.diagnostics()).automaticRefreshInFlight)
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        await waitForIntervals(sleeper, count: 3)

        let intervals = await sleeper.intervals
        #expect(intervals.contains(ClaudeCodeUsageConnector.automaticRefreshTimeout))
        #expect(intervals.last == ClaudeCodeUsageConnector.automaticRefreshInterval)
        #expect((await connector.diagnostics()).automaticDispatchCount == 1)
        #expect((await connector.diagnostics()).scheduledCycleCount == 1)
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        #expect(requestID.count == 36)
        await connector.disconnect()
    }

    @Test
    func manualRefreshCoalescesWithAnAutomaticRead() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.syncNow()
        await connector.syncNow()
        await connector.syncNow()

        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect((await connector.diagnostics()).coalescedActionCount == 2)
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(requestID: requestID, status: .tabUnavailable)
        await connector.disconnect()
    }

    @Test
    func tenManualCollisionsCoalesceWithOneScheduledReadAndResetCadence() async {
        let sleeper = BrowserTestSleeper()
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector { interval in
            try await sleeper.sleep(interval)
        }
        await connector.start()
        await waitForIntervals(sleeper, count: 1)
        await sleeper.resumeNext()
        await waitForRequests(fixture.bridge, count: 1)

        for _ in 0..<10 { await connector.syncNow() }
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect((await connector.diagnostics()).coalescedActionCount == 10)

        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        await waitForIntervals(sleeper, count: 3)
        #expect((await sleeper.intervals).last
            == ClaudeCodeUsageConnector.automaticRefreshInterval)
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
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
            await connector.syncNow()
            let requestID = await fixture.bridge.automaticRequests[0].requestID
            await fixture.bridge.sendAutomation(requestID: requestID, status: status)
            #expect(await connector.lifecycleState() == expected)
            #expect(!(await connector.diagnostics()).schedulerActive)
            #expect(!(await connector.currentSnapshot()).hasValidData)
            await connector.disconnect()
        }
    }

    @Test
    func transientUsageUnavailabilityWaitsOneNormalCadenceWithoutRetry() async {
        let sleeper = BrowserTestSleeper()
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector { interval in
            try await sleeper.sleep(interval)
        }
        await connector.syncNow()
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(
            requestID: requestID,
            status: .usageUnavailable
        )

        await waitForIntervals(sleeper, count: 3)
        let intervals = await sleeper.intervals
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect(intervals.last == ClaudeCodeUsageConnector.automaticRefreshInterval)
        #expect(intervals.filter { $0 == ClaudeCodeUsageConnector.automaticRefreshInterval }.count == 1)
        #expect((await connector.diagnostics()).schedulerActive)
        #expect(!(await connector.currentSnapshot()).hasValidData)
        await connector.disconnect()
    }

    @Test
    func ownershipUncertaintyFailsClosedAndSuspendsAutomation() async {
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector()
        await connector.syncNow()
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await fixture.bridge.sendAutomation(
            requestID: requestID,
            status: .ownedTabOwnershipLost
        )
        #expect(await connector.lifecycleState() == .routeChanged)
        #expect(!(await connector.currentSnapshot()).hasValidData)
        #expect(!(await connector.diagnostics()).schedulerActive)
        await connector.disconnect()
    }

    @Test
    func SafariUnavailablePreservesLaunchPreferenceAndWaitsNormalCadence() async {
        for allowed in [false, true] {
            let sleeper = BrowserTestSleeper()
            let fixture = BrowserConnectorFixture(
                consent: true,
                autoRefresh: true,
                allowSafariLaunch: allowed
            )
            await fixture.bridge.setAutomaticDispatchResult(.browserUnavailable)
            let connector = fixture.connector { interval in
                try await sleeper.sleep(interval)
            }
            await connector.syncNow()
            #expect(await fixture.bridge.automaticRequests.count == 1)
            #expect(await fixture.bridge.automaticRequests[0].allowSafariLaunch == allowed)
            #expect(await connector.lifecycleState() == .waitingForSafari)
            await waitForIntervals(sleeper, count: 1)
            let intervals = await sleeper.intervals
            #expect(intervals.last == ClaudeCodeUsageConnector.automaticRefreshInterval)
            #expect(intervals.allSatisfy {
                $0 == 0 || $0 == ClaudeCodeUsageConnector.automaticRefreshInterval
            })
            await connector.disconnect()
        }
    }

    @Test
    func disconnectClosesOnlyTheCurrentRequestAndCancelsTheScheduler() async {
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector()
        await connector.syncNow()
        let requestID = await fixture.bridge.automaticRequests[0].requestID
        await connector.disconnect()

        #expect(await fixture.bridge.closedRequestIDs == [requestID])
        #expect(!(await fixture.consent.get()))
        #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        #expect(!(await connector.diagnostics()).schedulerActive)
        #expect(await connector.lifecycleState() == .disconnected)
    }

    @Test
    func twentyAutomaticCollisionsStillProduceOneProviderRead() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        for _ in 0..<20 { await connector.syncNow() }
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect((await connector.diagnostics()).coalescedActionCount == 19)
        await connector.disconnect()
    }

    @Test
    func tenSuccessfulFixtureReadsRemainSerializedAndWriteOnlySanitizedCache() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()

        for index in 0..<10 {
            await connector.syncNow()
            #expect(await fixture.bridge.automaticRequests.count == index + 1)
            await fixture.bridge.send(browserEnvelope(
                five: Double(10 + index),
                seven: Double(20 + index)
            ))
            #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
        }

        #expect((await connector.diagnostics()).acceptedObservationCount == 10)
        #expect(await fixture.cache.writeCount == 10)
        #expect(await fixture.bridge.startCount == 1)
        await connector.disconnect()
    }

    @Test
    func tenRejectedRouteReadsFailClosedWithoutRetryOrAdmission() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()

        for index in 0..<10 {
            await connector.syncNow()
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
        #expect(await connector.lifecycleState() == .routeChanged)
        await connector.disconnect()
    }

    @Test
    func tenOwnedTabClosuresRecreateOnlyOnTheNextExplicitCycle() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()

        for index in 0..<10 {
            await connector.syncNow()
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
            await connector.syncNow()
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
    func fiveRelaunchCyclesRequireCurrentReadsAndLeaveNoOwnedWork() async {
        let fixture = BrowserConnectorFixture(consent: true)

        for cycle in 0..<5 {
            let connector = fixture.connector()
            await connector.start()
            #expect(!(await connector.currentSnapshot()).hasValidData)

            await connector.syncNow()
            #expect(await fixture.bridge.automaticRequests.count == cycle + 1)
            await fixture.bridge.send(browserEnvelope(
                five: Double(20 + cycle),
                seven: Double(40 + cycle)
            ))
            #expect((await connector.currentSnapshot()).hasValidData)

            await connector.stop()
            #expect(!(await connector.diagnostics()).automaticRefreshInFlight)
            #expect(!(await connector.diagnostics()).schedulerActive)
        }

        #expect(await fixture.bridge.startCount == 5)
        #expect(await fixture.bridge.stopCount == 5)
        #expect(await fixture.cache.writeCount == 5)
        #expect(await fixture.bridge.closedRequestIDs.count == 5)
    }

    @Test
    func fiveWakeSignalsReplaceTheTimerWithoutImmediateCatchUpReads() async {
        let sleeper = BrowserTestSleeper()
        let fixture = BrowserConnectorFixture(consent: true, autoRefresh: true)
        let connector = fixture.connector { interval in
            try await sleeper.sleep(interval)
        }
        await connector.start()
        await waitForIntervals(sleeper, count: 1)

        for _ in 0..<5 {
            await connector.refresh(trigger: .wake)
        }
        await waitForIntervals(sleeper, count: 6)

        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect((await sleeper.intervals).last == ClaudeCodeUsageConnector.automaticRefreshInterval)
        #expect((await connector.diagnostics()).schedulerActive)
        await connector.disconnect()
    }

    @Test
    func thirtyMinuteIdleSimulationNeverRewritesTheLastValidCache() async {
        let clock = BrowserTestClock()
        let fixture = BrowserConnectorFixture(consent: true, clock: clock)
        let connector = fixture.connector()
        await connector.syncNow()
        await fixture.bridge.send(browserEnvelope(five: 25, seven: 50))
        #expect(await fixture.cache.writeCount == 1)

        clock.advance(30 * 60)
        let expired = await connector.currentSnapshot()
        #expect(!expired.hasValidData)
        #expect(await fixture.cache.writeCount == 1)
        #expect(await fixture.cache.clearCount == 1)
        await connector.disconnect()
    }

    @Test
    func productionIntervalAndCapabilitiesRemainBounded() {
        #expect(ClaudeCodeUsageConnector.automaticRefreshInterval == 5 * 60)
        #expect(ClaudeCodeUsageConnector.minimumAutomaticRefreshInterval == 3 * 60)
        #expect(ClaudeCodeUsageConnector.automaticRefreshInterval
            >= ClaudeCodeUsageConnector.minimumAutomaticRefreshInterval)
        #expect(ClaudeCodeUsageConnector.production().descriptor.capabilities.contains(.automaticRefresh))
    }

    @Test
    func settingsContainLocalizedAutomationDisclosureAndDeterministicActions() throws {
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
            "Auto Refresh", "Every 5 minutes", "Manual only",
            "Allow UMA to launch Safari when needed", "Grant Access",
            "Open Safari Access Settings", "Website access required",
            "Sign in required", "Waiting for Safari",
        ] {
            #expect(settings.contains(required))
        }
        #expect(settings.contains("claude.browser.grant-access"))
        #expect(settings.contains("claude.browser.open-access-settings"))
        #expect(language.contains("每五分钟一次的自动刷新"))
        #expect(language.contains("https://claude.ai/new*"))
        #expect(!language.contains("toolbar click"))
    }

    @Test
    func packageHelperHasExactAutomaticPreflightAndFinalPhases() throws {
        let source = try String(
            contentsOf: autoBrowserRepositoryRoot().appendingPathComponent(
                "script/package_uma_m5_g2.sh"
            ),
            encoding: .utf8
        )
        for required in [
            "m5-auto-preflight",
            "uma-m5-auto-preflight-${commit:0:12}/UMA.app",
            "m5-auto-final",
            "uma-m5-auto-final-$commit/UMA.app",
            "AUTOMATIC-BROWSER-SYNC-ACCEPTED",
            "https://claude.ai/new*",
        ] {
            #expect(source.contains(required))
        }
        #expect(source.contains("working-tree-m5-auto-preflight"))
        #expect(source.contains("commit_exact=1"))
    }
}

private func waitForIntervals(_ sleeper: BrowserTestSleeper, count: Int) async {
    for _ in 0..<200 {
        if await sleeper.intervals.count >= count { return }
        await Task.yield()
    }
}

private func waitForRequests(_ bridge: BrowserTestBridge, count: Int) async {
    for _ in 0..<200 {
        if await bridge.automaticRequests.count >= count { return }
        await Task.yield()
    }
}

private func autoBrowserRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
