import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M4-G2 Manus strict decoder and client")
struct M4G2ManusSourceTests {
    @Test
    func exactRequestAndRedactedDiagnosticAreLocked() throws {
        let request = try ManusCreditsAPIClient.makeRequest(
            apiKey: "synthetic-non-secret"
        )
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://api.manus.ai/v2/usage.availableCredits"
        )
        #expect(request.url?.query == nil)
        #expect(request.httpBody == nil)
        #expect(request.timeoutInterval == 15)
        #expect(request.httpShouldHandleCookies == false)
        #expect(
            request.value(forHTTPHeaderField: "x-manus-api-key")
                == "synthetic-non-secret"
        )
        let diagnostic = ManusCreditsAPIClient.redactedDiagnostic(for: request)
        #expect(diagnostic.contains("credential=present"))
        #expect(!diagnostic.contains("synthetic-non-secret"))
        #expect(ManusCreditsAPIClient.maximumResponseBytes == 16 * 1_024)
        #expect(ManusCreditsAPIClient.resourceTimeout == 20)
        #expect(throws: Error.self) {
            _ = try ManusCreditsAPIClient.makeRequest(
                apiKey: "synthetic\nheader-injection"
            )
        }
    }

    @Test
    func primaryIsAuthoritativeAndDetailsNeverNeedToSum() throws {
        let result = try ManusCreditsDecoder.decode(
            payload(
                """
                "total_credits":42,
                "free_credits":1000,
                "periodic_credits":2000,
                "addon_credits":3000,
                "pro_monthly_credits":4000,
                "event_credits":5000,
                "refresh_credits":6000,
                "max_refresh_credits":7000,
                "next_refresh_time":1893456000,
                "refresh_interval":"weekly",
                "unknown_future_field":"ignored"
                """
            )
        )
        #expect(result.totalCredits == 42)
        #expect(result.freeCredits == 1_000)
        #expect(result.proMonthlyCredits == 4_000)
        #expect(result.creditDetails.details.count == 7)
        #expect(result.refreshInterval == .weekly)
        #expect(result.nextRefreshAt != nil)
    }

    @Test
    func minimalZeroAndNullOptionalsAreAccepted() throws {
        let minimal = try ManusCreditsDecoder.decode(
            payload(#""total_credits":0"#)
        )
        #expect(minimal.totalCredits == 0)
        #expect(minimal.freeCredits == nil)
        #expect(minimal.nextRefreshAt == nil)

        let nulls = try ManusCreditsDecoder.decode(
            payload(
                """
                "total_credits":1,
                "free_credits":null,
                "next_refresh_time":0,
                "refresh_interval":null
                """
            )
        )
        #expect(nulls.freeCredits == nil)
        #expect(nulls.nextRefreshAt == nil)
        #expect(nulls.refreshInterval == nil)
    }

    @Test
    func maximumDocumentedCreditAndDocumentedIntervalsAreAccepted() throws {
        let maximum = try ManusCreditsDecoder.decode(
            payload(
                """
                "total_credits":2147483647,
                "next_refresh_time":4102444800,
                "refresh_interval":"daily"
                """
            )
        )
        #expect(maximum.totalCredits == Int64(Int32.max))
        #expect(maximum.refreshInterval == .daily)
        #expect(
            maximum.nextRefreshAt
                == ManusCreditsDecoder.latestPlausibleRefresh
        )

        let weekly = try ManusCreditsDecoder.decode(
            payload(
                """
                "total_credits":1,
                "next_refresh_time":1577836800,
                "refresh_interval":"weekly"
                """
            )
        )
        #expect(weekly.refreshInterval == .weekly)
        #expect(
            weekly.nextRefreshAt
                == ManusCreditsDecoder.earliestPlausibleRefresh
        )
    }

    @Test(
        "Strict malformed values fail closed",
        arguments: [
            #"{"ok":true,"data":{}}"#,
            #"{"ok":true,"data":{"total_credits":-1}}"#,
            #"{"ok":true,"data":{"total_credits":2147483648}}"#,
            #"{"ok":true,"data":{"total_credits":1.5}}"#,
            #"{"ok":true,"data":{"total_credits":"1"}}"#,
            #"{"ok":true,"data":{"total_credits":1,"free_credits":-1}}"#,
            #"{"ok":true,"data":{"total_credits":1,"refresh_interval":"monthly"}}"#,
            #"{"ok":true,"data":{"total_credits":1,"next_refresh_time":1893456000000}}"#,
            #"{"ok":false,"data":{"total_credits":1}}"#,
            #"not-json"#
        ]
    )
    func malformedFailsClosed(document: String) {
        #expect(throws: Error.self) {
            _ = try ManusCreditsDecoder.decode(Data(document.utf8))
        }
    }

    @Test
    func clientAcceptsOnlyExactSuccessfulJSONResponse() async throws {
        let transport = RecordingManusTransport(
            response: .success(
                (
                    payload(#""total_credits":17"#),
                    response(status: 200, contentType: "application/json")
                )
            )
        )
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let result = await ManusCreditsAPIClient(
            transport: transport,
            now: { now }
        ).read(apiKey: "synthetic-non-secret")
        guard case let .success(reading) = result else {
            Issue.record("Expected the exact API response to be accepted")
            return
        }
        #expect(reading.snapshot.totalCredits == 17)
        #expect(reading.observedAt == now)
        let request = await transport.lastRequest
        #expect(request?.httpMethod == "GET")
        #expect(request?.httpBody == nil)
    }

    @Test
    func clientMapsStatusesContentAndSizeToBoundedFailures() async {
        let cases: [(Int, String?, Int, ManusCreditsClientFailure)] = [
            (401, "application/json", 8, .authentication),
            (403, "application/json", 8, .authentication),
            (429, "application/json", 8, .rateLimited),
            (500, "application/json", 8, .server),
            (200, "text/html", 8, .unsupportedResponse),
            (
                200,
                "application/json",
                ManusCreditsAPIClient.maximumResponseBytes + 1,
                .unsupportedResponse
            ),
        ]
        for (status, contentType, count, expected) in cases {
            let transport = RecordingManusTransport(
                response: .success(
                    (
                        Data(repeating: 0x20, count: count),
                        response(status: status, contentType: contentType)
                    )
                )
            )
            let result = await ManusCreditsAPIClient(
                transport: transport
            ).read(apiKey: "synthetic-non-secret")
            #expect(result == .failure(expected))
        }
    }

    @Test
    func clientRejectsRedirectedLocationAndMapsProviderCodesSafely() async {
        let redirected = RecordingManusTransport(
            response: .success(
                (
                    payload(#""total_credits":17"#),
                    response(
                        status: 200,
                        contentType: "application/json",
                        url: URL(string: "https://example.com/redirected")!
                    )
                )
            )
        )
        #expect(
            await ManusCreditsAPIClient(transport: redirected)
                .read(apiKey: "synthetic-non-secret")
                == .failure(.unsupportedResponse)
        )

        let providerError = RecordingManusTransport(
            response: .success(
                (
                    Data(
                        """
                        {"ok":false,"error":{"code":"rate_limited",
                        "message":"must-never-be-surfaced"}}
                        """.utf8
                    ),
                    response(status: 200, contentType: "application/json")
                )
            )
        )
        #expect(
            await ManusCreditsAPIClient(transport: providerError)
                .read(apiKey: "synthetic-non-secret")
                == .failure(.rateLimited)
        )
    }

    @Test
    func clientDoesNotRetryCancellationOrNetworkFailure() async {
        let cancelled = RecordingManusTransport(
            response: .failure(URLError(.cancelled))
        )
        #expect(
            await ManusCreditsAPIClient(transport: cancelled)
                .read(apiKey: "synthetic-non-secret")
                == .failure(.cancelled)
        )
        #expect(await cancelled.requestCount == 1)

        let network = RecordingManusTransport(
            response: .failure(URLError(.notConnectedToInternet))
        )
        #expect(
            await ManusCreditsAPIClient(transport: network)
                .read(apiKey: "synthetic-non-secret")
                == .failure(.network)
        )
        #expect(await network.requestCount == 1)

        let boundedTransport = RecordingManusTransport(
            response: .failure(
                ManusCreditsClientFailure.unsupportedResponse
            )
        )
        #expect(
            await ManusCreditsAPIClient(transport: boundedTransport)
                .read(apiKey: "synthetic-non-secret")
                == .failure(.unsupportedResponse)
        )
        #expect(await boundedTransport.requestCount == 1)
    }

    private func payload(_ fields: String) -> Data {
        Data(#"{"ok":true,"request_id":"ignored","data":{"#.utf8)
            + Data(fields.utf8)
            + Data("}}".utf8)
    }

    private func response(
        status: Int,
        contentType: String?,
        url: URL = ManusCreditsAPIClient.endpoint
    ) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let contentType {
            headers["Content-Type"] = contentType
        }
        return HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}

@Suite("M4-G2 Manus Keychain lifecycle")
struct M4G2ManusKeychainTests {
    @Test
    func fakeStoreSupportsAddReadReplaceDelete() async throws {
        let store = FakeManusKeyStore()
        #expect(await store.isConfigured() == false)
        try await store.save("synthetic-a")
        #expect(await store.isConfigured())
        #expect(try await store.read() == "synthetic-a")
        try await store.save("synthetic-b")
        #expect(try await store.read() == "synthetic-b")
        try await store.delete()
        #expect(await store.isConfigured() == false)
    }

    @Test
    func actualSecurityFrameworkLifecycleUsesOneTaskOwnedItem() async throws {
        let unique = UUID().uuidString
        let store = ManusAPIKeyStore(
            service: "com.kevinchen.CodexUsageMonitor.tests.manus.\(unique)",
            account: "task-owned-\(unique)",
            usesDataProtectionKeychain: false
        )
        try? await store.delete()
        do {
            try await store.save("synthetic-lifecycle-a")
            #expect(try await store.read() == "synthetic-lifecycle-a")
            try await store.save("synthetic-lifecycle-b")
            #expect(try await store.read() == "synthetic-lifecycle-b")
            try await store.delete()
            #expect(await store.isConfigured() == false)
        } catch {
            try? await store.delete()
            throw error
        }
        try? await store.delete()
    }

    @Test
    func productionContractIsDeviceOnlyAndStable() async {
        #expect(
            ManusAPIKeyStore.productionService
                == "com.kevinchen.CodexUsageMonitor.manus-api-v2"
        )
        #expect(ManusAPIKeyStore.productionAccount == "primary")
        #expect(ManusAPIKeyStore().usesDataProtectionKeychain)
        #expect(
            ManusAPIKeyStore.productionAccessibility
                == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        #expect(!ManusAPIKeyStore.productionSynchronizable)
        let query = await ManusAPIKeyStore().queryContract()
        #expect(query.itemClass == kSecClassGenericPassword as String)
        #expect(query.service == ManusAPIKeyStore.productionService)
        #expect(query.account == ManusAPIKeyStore.productionAccount)
        #expect(
            query.accessibility
                == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        #expect(query.synchronizable == false)
        #expect(query.usesDataProtectionKeychain == true)
    }
}

@Suite("M4-G2 Manus connector, admission, and Settings")
struct M4G2ManusConnectorTests {
    @Test
    func currentSuccessfulReadAdmitsMainPanelButNotAssistant() async throws {
        let keyStore = FakeManusKeyStore(initial: "synthetic")
        let client = ScriptedManusClient([
            .success(reading(total: 1_300)),
        ])
        let scheduler = ManusRefreshScheduler(sleeper: { _ in })
        let connector = ManusUsageConnector(
            keyStore: keyStore,
            client: client,
            scheduler: scheduler
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let result = await registry.scanSurfaceAdmissions(
            trigger: .manualRefresh
        )
        #expect(result.admittedProviderIDs == [ManusUsageConnector.connectorID])
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: result.admittedSnapshots,
            previousCards: [],
            language: .english
        )
        #expect(cards.count == 1)
        #expect(cards[0].providerName == "Manus")
        #expect(cards[0].availability?.exactCreditValue == 1_300)
        #expect(cards[0].availability?.normalizedRemainingFraction == nil)
        #expect(cards[0].sourceDescription == "Official API v2")
        let chineseCards = SharedUsagePresentationPolicy.makeCards(
            snapshots: result.admittedSnapshots,
            previousCards: [],
            language: .simplifiedChinese
        )
        #expect(chineseCards[0].sourceDescription == "官方 API v2")
        #expect(
            SharedUsagePresentationPolicy.assistantCards(from: cards).isEmpty
        )
    }

    @Test
    func configuredButUnreadIsNotAdmittedAndFailureWithdrawsCurrentValue()
        async throws
    {
        let keyStore = FakeManusKeyStore(initial: "synthetic")
        let client = ScriptedManusClient([
            .success(reading(total: 10)),
            .failure(.network),
        ])
        let scheduler = ManusRefreshScheduler(sleeper: { _ in })
        let connector = ManusUsageConnector(
            keyStore: keyStore,
            client: client,
            scheduler: scheduler
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let admitted = await registry.scanSurfaceAdmissions(
            trigger: .manualRefresh
        )
        #expect(admitted.admittedProviderIDs.count == 1)
        try await registry.refresh(
            ManusUsageConnector.connectorID,
            trigger: .manual
        )
        #expect(await registry.orderedSnapshots().isEmpty)
        #expect(
            (await connector.currentSnapshot()).state == .failed
        )
    }

    @Test
    func disconnectDeletesOnlyCredentialAndClearsSnapshot() async throws {
        let keyStore = FakeManusKeyStore(initial: "synthetic")
        let scheduler = ManusRefreshScheduler(sleeper: { _ in })
        let connector = ManusUsageConnector(
            keyStore: keyStore,
            client: ScriptedManusClient([
                .success(reading(total: 88)),
            ]),
            scheduler: scheduler
        )
        await connector.refresh()
        #expect((await connector.currentSnapshot()).state == .ready)
        await connector.perform(.disconnect)
        #expect(await keyStore.isConfigured() == false)
        let snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .authenticationRequired)
        #expect(snapshot.channels.isEmpty)
    }

    @Test
    func failedCredentialDeletionRemainsVisibleAsASettingsFailure()
        async throws
    {
        let keyStore = FakeManusKeyStore(
            initial: "synthetic",
            deletionFailure: .accessDenied
        )
        let scheduler = ManusRefreshScheduler(sleeper: { _ in })
        let connector = ManusUsageConnector(
            keyStore: keyStore,
            client: ScriptedManusClient([]),
            scheduler: scheduler
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        await connector.perform(.disconnect)
        #expect(await keyStore.isConfigured())
        #expect(
            await connector.currentSettingsFailure()
                == .credentialUnavailable
        )
        #expect((await connector.currentSnapshot()).state == .failed)

        let suite = "M4G2.DeleteFailure.\(UUID().uuidString)"
        let model = await MainActor.run {
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return ManusSettingsModel(
                keyStore: keyStore,
                connector: connector,
                registry: registry,
                scheduler: scheduler,
                defaults: defaults
            )
        }
        await MainActor.run {
            model.start()
            model.disconnect()
        }
        await waitUntil {
            await MainActor.run {
                model.connectionState == .failed
                    && model.credentialConfigured
            }
        }
        #expect(
            await MainActor.run {
                model.safeFailure == .credentialUnavailable
            }
        )
        await MainActor.run {
            model.tearDown()
            UserDefaults(suiteName: suite)?
                .removePersistentDomain(forName: suite)
        }
    }

    @Test
    func lockedKeychainIsTransientUnavailableNotUnconfigured() async throws {
        let keyStore = FakeManusKeyStore(
            configurationFailure: .keychainLocked
        )
        let scheduler = ManusRefreshScheduler()
        let connector = ManusUsageConnector(
            keyStore: keyStore,
            client: ScriptedManusClient([]),
            scheduler: scheduler
        )
        #expect(await connector.permitsRead(for: .applicationLaunch))
        let probe = await connector.probe()
        #expect(probe.state == .failed)
        #expect(probe.safeFailure == .unavailable)

        let suite = "M4G2.LockedKeychain.\(UUID().uuidString)"
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let model = await MainActor.run {
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return ManusSettingsModel(
                keyStore: keyStore,
                connector: connector,
                registry: registry,
                scheduler: scheduler,
                defaults: defaults
            )
        }
        await MainActor.run { model.start() }
        await waitUntil {
            await MainActor.run {
                model.connectionState == .failed
                    && model.safeFailure == .credentialUnavailable
            }
        }
        #expect(await MainActor.run { model.credentialConfigured })
        await MainActor.run {
            model.tearDown()
            UserDefaults(suiteName: suite)?
                .removePersistentDomain(forName: suite)
        }
    }

    @Test(
        "Credential access failures fail closed without appearing missing",
        arguments: [
            ManusAPIKeyStoreError.keychainLocked,
            ManusAPIKeyStoreError.accessDenied,
            ManusAPIKeyStoreError.unavailable,
        ]
    )
    func credentialAccessFailuresRemainUnavailable(
        error: ManusAPIKeyStoreError
    ) async {
        let connector = ManusUsageConnector(
            keyStore: FakeManusKeyStore(configurationFailure: error),
            client: ScriptedManusClient([]),
            scheduler: ManusRefreshScheduler()
        )
        #expect(await connector.permitsRead(for: .applicationLaunch))
        let probe = await connector.probe()
        #expect(probe.state == .failed)
        #expect(probe.safeFailure == .unavailable)
    }

    @Test
    func configuredRemoteSourceRequiresLaunchAdmissionEvenWithoutAutoSearch()
        async throws
    {
        let configured = ManusUsageConnector(
            keyStore: FakeManusKeyStore(initial: "synthetic"),
            client: ScriptedManusClient([]),
            scheduler: ManusRefreshScheduler()
        )
        let configuredRegistry = try AgentConnectorRegistry(
            connectors: [configured]
        )
        #expect(
            await configuredRegistry.hasConfiguredOfficialRemoteConnector()
        )

        let missing = ManusUsageConnector(
            keyStore: FakeManusKeyStore(),
            client: ScriptedManusClient([]),
            scheduler: ManusRefreshScheduler()
        )
        let missingRegistry = try AgentConnectorRegistry(
            connectors: [missing]
        )
        #expect(
            await missingRegistry.hasConfiguredOfficialRemoteConnector()
                == false
        )
    }

    @Test
    func schedulerClampsCadenceAndOwnsAtMostOneTimer() async {
        let scheduler = ManusRefreshScheduler(cadence: 1)
        await scheduler.configure {}
        await scheduler.setEnabled(true)
        let diagnostics = await scheduler.diagnostics()
        #expect(diagnostics.cadence == 60)
        #expect(diagnostics.timerCount == 1)
        await scheduler.cancel()
        #expect((await scheduler.diagnostics()).timerCount == 0)
    }

    @Test
    func authenticationSuspensionRequiresCredentialChangeToResume() async {
        let scheduler = ManusRefreshScheduler()
        await scheduler.configure {}
        await scheduler.setEnabled(true)
        await scheduler.readDidComplete(
            trigger: .manual,
            authenticationFailed: true
        )
        var diagnostics = await scheduler.diagnostics()
        #expect(diagnostics.authenticationSuspended)
        #expect(diagnostics.timerCount == 0)

        await scheduler.setEnabled(false)
        await scheduler.setEnabled(true)
        diagnostics = await scheduler.diagnostics()
        #expect(diagnostics.authenticationSuspended)
        #expect(diagnostics.timerCount == 0)

        await scheduler.resumeAfterCredentialChange()
        diagnostics = await scheduler.diagnostics()
        #expect(diagnostics.authenticationSuspended == false)
        #expect(diagnostics.timerCount == 1)
        await scheduler.cancel()
    }

    @Test
    func monitoringExclusionStopsOfficialRemoteScheduler() async throws {
        let scheduler = ManusRefreshScheduler()
        await scheduler.configure {}
        await scheduler.setEnabled(true)
        let connector = ManusUsageConnector(
            keyStore: FakeManusKeyStore(initial: "synthetic"),
            client: ScriptedManusClient([]),
            scheduler: scheduler
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        await registry.stopConnectors([ManusUsageConnector.connectorID])
        let diagnostics = await scheduler.diagnostics()
        #expect(diagnostics.enabled == false)
        #expect(diagnostics.timerCount == 0)
    }

    @Test
    func transientFailureWithdrawsWithoutStoppingRecoveryTimer() async throws {
        let clock = LockedTestClock()
        let scheduler = ManusRefreshScheduler(now: clock.now)
        let connector = ManusUsageConnector(
            keyStore: FakeManusKeyStore(initial: "synthetic"),
            client: ScriptedManusClient([
                .success(reading(total: 1_300)),
                .failure(.network),
            ]),
            scheduler: scheduler
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        await scheduler.configure {}
        await scheduler.setEnabled(true)
        let admitted = await registry.scanSurfaceAdmissions(
            trigger: .manualRefresh
        )
        #expect(admitted.admittedProviderIDs == [
            ManusUsageConnector.connectorID,
        ])
        clock.advance(by: 60)

        try await registry.refresh(
            ManusUsageConnector.connectorID,
            trigger: .manual
        )

        #expect(await registry.orderedSnapshots().isEmpty)
        let diagnostics = await scheduler.diagnostics()
        #expect(diagnostics.enabled)
        #expect(diagnostics.authenticationSuspended == false)
        #expect(diagnostics.timerCount == 1)
        await scheduler.cancel()
    }

    @Test
    func registryWithdrawalPreservesAuthenticationSuspension() async throws {
        let clock = LockedTestClock()
        let scheduler = ManusRefreshScheduler(now: clock.now)
        let connector = ManusUsageConnector(
            keyStore: FakeManusKeyStore(initial: "synthetic"),
            client: ScriptedManusClient([
                .success(reading(total: 1_300)),
                .failure(.authentication),
            ]),
            scheduler: scheduler
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        await scheduler.configure {}
        await scheduler.setEnabled(true)
        _ = await registry.scanSurfaceAdmissions(trigger: .manualRefresh)
        clock.advance(by: 60)

        try await registry.refresh(
            ManusUsageConnector.connectorID,
            trigger: .manual
        )

        var diagnostics = await scheduler.diagnostics()
        #expect(diagnostics.enabled)
        #expect(diagnostics.authenticationSuspended)
        #expect(diagnostics.timerCount == 0)
        await scheduler.setEnabled(false)
        await scheduler.setEnabled(true)
        diagnostics = await scheduler.diagnostics()
        #expect(diagnostics.authenticationSuspended)
        #expect(diagnostics.timerCount == 0)
        await scheduler.cancel()
    }

    @Test
    func settingsCadenceCopyDistinguishesAutomaticAndManualModes() {
        #expect(AppLanguage.english.manusEveryMinute !=
            AppLanguage.english.manusManualOnly)
        #expect(AppLanguage.simplifiedChinese.manusEveryMinute !=
            AppLanguage.simplifiedChinese.manusManualOnly)
    }

    @Test
    func overlappingRefreshesCoalesceToOneReadAndOneFollowUp() async {
        let keyStore = FakeManusKeyStore(initial: "synthetic")
        let client = BlockingManusClient()
        let delays = DelayRecorder()
        let scheduler = ManusRefreshScheduler(
            now: { Date(timeIntervalSince1970: 1_000) },
            sleeper: { seconds in await delays.record(seconds) }
        )
        let connector = ManusUsageConnector(
            keyStore: keyStore,
            client: client,
            scheduler: scheduler
        )

        let first = Task { await connector.refresh() }
        await waitUntil { await client.invocationCount == 1 }
        let overlapping = Task { await connector.refresh() }
        await waitUntil {
            (await connector.diagnostics()).coalescedReads == 1
        }
        await client.complete(.success(reading(total: 40)))
        await waitUntil { await client.invocationCount == 2 }
        await client.complete(.success(reading(total: 41)))
        await first.value
        await overlapping.value

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.activeReads == 0)
        #expect(diagnostics.completedReads == 2)
        #expect(diagnostics.coalescedReads == 1)
        #expect(diagnostics.droppedScheduledReads == 0)
        #expect(await client.maximumActiveReads == 1)
        #expect(await delays.values == [60])
        let finalAvailability = (await connector.currentSnapshot())
            .channels.first?.availability
        guard case let .credits(balance) = finalAvailability else {
            Issue.record("Expected the final coalesced Credit snapshot")
            return
        }
        #expect(balance.remaining == 41)
    }

    @Test
    func scheduledOverlapIsDroppedAndFailureOverlapDoesNotRetry() async {
        let keyStore = FakeManusKeyStore(initial: "synthetic")
        let scheduledClient = BlockingManusClient()
        let scheduledConnector = ManusUsageConnector(
            keyStore: keyStore,
            client: scheduledClient,
            scheduler: ManusRefreshScheduler(sleeper: { _ in })
        )
        let first = Task { await scheduledConnector.refresh() }
        await waitUntil { await scheduledClient.invocationCount == 1 }
        let scheduled = Task {
            await scheduledConnector.refresh(trigger: .timer)
        }
        await waitUntil {
            (await scheduledConnector.diagnostics())
                .droppedScheduledReads == 1
        }
        await scheduledClient.complete(.success(reading(total: 50)))
        await first.value
        await scheduled.value
        #expect(await scheduledClient.invocationCount == 1)

        let failureClient = BlockingManusClient()
        let failureConnector = ManusUsageConnector(
            keyStore: keyStore,
            client: failureClient,
            scheduler: ManusRefreshScheduler(sleeper: { _ in })
        )
        let failing = Task { await failureConnector.refresh() }
        await waitUntil { await failureClient.invocationCount == 1 }
        let overlapping = Task { await failureConnector.refresh() }
        await waitUntil {
            (await failureConnector.diagnostics()).coalescedReads == 1
        }
        await failureClient.complete(.failure(.rateLimited))
        await failing.value
        await overlapping.value
        #expect(await failureClient.invocationCount == 1)
        #expect(
            (await failureConnector.diagnostics()).followUpQueued == false
        )
    }

    @Test
    func schedulerCallbackSurvivesDisconnectAndStopCancelsTimer() async {
        let callbacks = Counter()
        let scheduler = ManusRefreshScheduler(sleeper: { _ in })
        await scheduler.configure {
            await callbacks.increment()
        }
        await scheduler.setEnabled(true)
        await waitUntil { await callbacks.value == 1 }
        await scheduler.cancel()
        await scheduler.setEnabled(true)
        await waitUntil { await callbacks.value == 2 }

        let connector = ManusUsageConnector(
            keyStore: FakeManusKeyStore(initial: "synthetic"),
            client: ScriptedManusClient([]),
            scheduler: scheduler
        )
        await connector.stop()
        #expect((await scheduler.diagnostics()).timerCount == 0)
        await scheduler.tearDown()
    }

    @Test @MainActor
    func failedReplacementRestoresPreviousCredential() async throws {
        let suite = "M4G2.Replacement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keyStore = FakeManusKeyStore(initial: "synthetic-old")
        let scheduler = ManusRefreshScheduler(sleeper: { _ in })
        let connector = ManusUsageConnector(
            keyStore: keyStore,
            client: ScriptedManusClient([.failure(.authentication)]),
            scheduler: scheduler
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let model = ManusSettingsModel(
            keyStore: keyStore,
            connector: connector,
            registry: registry,
            scheduler: scheduler,
            defaults: defaults
        )
        model.draftCredential = "synthetic-rejected"
        model.saveAndVerify()
        await waitUntil { model.connectionState == .failed }
        #expect(try await keyStore.read() == "synthetic-old")
        #expect(model.safeFailure == .authentication)
        #expect(
            !defaults.dictionaryRepresentation().description
                .contains("synthetic-rejected")
        )
        model.tearDown()
    }

    @Test @MainActor
    func settingsClearsDraftAndNeverPersistsCredential() async throws {
        let suite = "M4G2.ManusSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keyStore = FakeManusKeyStore()
        let scheduler = ManusRefreshScheduler()
        let connector = ManusUsageConnector(
            keyStore: keyStore,
            client: ScriptedManusClient([
                .success(reading(total: 77)),
            ]),
            scheduler: scheduler
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let model = ManusSettingsModel(
            keyStore: keyStore,
            connector: connector,
            registry: registry,
            scheduler: scheduler,
            defaults: defaults
        )
        model.draftCredential = "synthetic-settings-key"
        model.saveAndVerify()
        #expect(model.draftCredential.isEmpty)
        await waitUntil { model.connectionState == .connected }
        #expect(model.lastUpdatedAt != nil)
        #expect(
            !defaults.dictionaryRepresentation().description
                .contains("synthetic-settings-key")
        )
        model.disconnect()
        await waitUntil { model.connectionState == .disconnected }
        #expect(await keyStore.isConfigured() == false)
    }

    @Test @MainActor
    func settingsDraftIsDiscardedWithoutCredentialMutation() async throws {
        let suite = "M4G2.ManusDraft.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keyStore = FakeManusKeyStore()
        let scheduler = ManusRefreshScheduler()
        let connector = ManusUsageConnector(
            keyStore: keyStore,
            client: ScriptedManusClient([]),
            scheduler: scheduler
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let model = ManusSettingsModel(
            keyStore: keyStore,
            connector: connector,
            registry: registry,
            scheduler: scheduler,
            defaults: defaults
        )
        model.draftCredential = "synthetic-unsaved-draft"
        model.discardDraft()
        #expect(model.draftCredential.isEmpty)
        #expect(await keyStore.isConfigured() == false)
        #expect(
            !defaults.dictionaryRepresentation().description
                .contains("synthetic-unsaved-draft")
        )
    }

    private func reading(total: Int64) -> ManusCreditsReading {
        ManusCreditsReading(
            snapshot: ManusCreditsSnapshot(
                totalCredits: total,
                freeCredits: nil,
                periodicCredits: nil,
                addOnCredits: nil,
                proMonthlyCredits: nil,
                eventCredits: nil,
                refreshCredits: nil,
                maxRefreshCredits: nil,
                nextRefreshAt: nil,
                refreshInterval: nil
            ),
            observedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }

    @MainActor
    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for MainActor state")
    }

    private func waitUntil(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for asynchronous state")
    }
}

private final class LockedTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 2_000_000_000)

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private actor FakeManusKeyStore: ManusAPIKeyStoring {
    private var credential: String?
    private let configurationFailure: ManusAPIKeyStoreError?
    private let deletionFailure: ManusAPIKeyStoreError?

    init(
        initial: String? = nil,
        configurationFailure: ManusAPIKeyStoreError? = nil,
        deletionFailure: ManusAPIKeyStoreError? = nil
    ) {
        credential = initial
        self.configurationFailure = configurationFailure
        self.deletionFailure = deletionFailure
    }

    func configurationState() -> ManusCredentialConfigurationState {
        if let configurationFailure {
            return .unavailable(configurationFailure)
        }
        return credential == nil
            ? ManusCredentialConfigurationState.notConfigured
            : ManusCredentialConfigurationState.configured
    }

    func read() throws -> String {
        if let configurationFailure {
            throw configurationFailure
        }
        guard let credential else {
            throw ManusAPIKeyStoreError.missingCredential
        }
        return credential
    }

    func save(_ credential: String) throws {
        guard !credential.isEmpty else {
            throw ManusAPIKeyStoreError.invalidCredential
        }
        self.credential = credential
    }

    func delete() throws {
        if let deletionFailure {
            throw deletionFailure
        }
        credential = nil
    }
}

private actor ScriptedManusClient: ManusCreditsReadingClient {
    private var results: [
        Result<ManusCreditsReading, ManusCreditsClientFailure>
    ]

    init(
        _ results: [
            Result<ManusCreditsReading, ManusCreditsClientFailure>
        ]
    ) {
        self.results = results
    }

    func read(apiKey: String) -> Result<
        ManusCreditsReading,
        ManusCreditsClientFailure
    > {
        guard !results.isEmpty else { return .failure(.network) }
        return results.removeFirst()
    }
}

private actor RecordingManusTransport: ManusHTTPTransporting {
    let response: Result<(Data, URLResponse), Error>
    private(set) var lastRequest: URLRequest?
    private(set) var requestCount = 0

    init(response: Result<(Data, URLResponse), Error>) {
        self.response = response
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requestCount += 1
        lastRequest = request
        return try response.get()
    }
}

private actor BlockingManusClient: ManusCreditsReadingClient {
    private var continuation: CheckedContinuation<
        Result<ManusCreditsReading, ManusCreditsClientFailure>,
        Never
    >?
    private(set) var invocationCount = 0
    private(set) var maximumActiveReads = 0
    private var activeReads = 0

    func read(apiKey: String) async -> Result<
        ManusCreditsReading,
        ManusCreditsClientFailure
    > {
        invocationCount += 1
        activeReads += 1
        maximumActiveReads = max(maximumActiveReads, activeReads)
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        activeReads -= 1
        return result
    }

    func complete(
        _ result: Result<
            ManusCreditsReading,
            ManusCreditsClientFailure
        >
    ) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor DelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        values.append(value)
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
