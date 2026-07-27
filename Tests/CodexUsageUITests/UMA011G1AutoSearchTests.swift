import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.11-G1 controlled Agent Search")
struct UMA011G1AutoSearchTests {
    @Test @MainActor
    func firstLaunchNeverScansAndFirstManualSearchEnablesLaterLaunchSearch()
        async throws
    {
        let defaults = makeDefaults("first-scan")
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        CodexMonitorConsentDecision.granted.persist(to: defaults)

        let firstScanner = LocalProviderEligibilityScanner()
        let firstConnector = try SearchFixtureConnector()
        let firstRegistry = try AgentConnectorRegistry(
            connectors: [firstConnector],
            eligibilityScanner: firstScanner
        )
        let firstSettings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: defaults)
        )
        let firstStore = UsageStore(
            autoRefresh: true,
            previewOnly: false,
            language: .english,
            registry: firstRegistry,
            primaryConnectorID: firstConnector.id,
            consentDefaults: defaults,
            agentSettings: firstSettings
        )

        try await Task.sleep(for: .milliseconds(40))
        #expect((await firstScanner.diagnostics()).completedScanCount == 0)
        #expect(!firstSettings.initialScanCompleted)

        await firstStore.searchForAgents()
        let firstDiagnostics = await firstScanner.diagnostics()
        #expect(firstDiagnostics.completedScanCount == 1)
        #expect(firstDiagnostics.countsByTrigger[.manualSearch] == 1)
        #expect(firstSettings.initialScanCompleted)
        #expect(firstSettings.autoSearchEnabled)
        #expect(
            firstSettings.record(for: firstConnector.id).hasBeenDetected
        )
        await firstStore.stopAllConnectors()

        let launchScanner = LocalProviderEligibilityScanner()
        let launchConnector = try SearchFixtureConnector()
        let launchRegistry = try AgentConnectorRegistry(
            connectors: [launchConnector],
            eligibilityScanner: launchScanner
        )
        let restoredSettings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: defaults)
        )
        let launchStore = UsageStore(
            autoRefresh: true,
            previewOnly: false,
            language: .english,
            registry: launchRegistry,
            primaryConnectorID: launchConnector.id,
            consentDefaults: defaults,
            agentSettings: restoredSettings
        )

        try await waitUntil {
            (await launchScanner.diagnostics()).completedScanCount == 1
        }
        try await Task.sleep(for: .milliseconds(20))
        let launchDiagnostics = await launchScanner.diagnostics()
        #expect(launchDiagnostics.completedScanCount == 1)
        #expect(launchDiagnostics.countsByTrigger[.applicationLaunch] == 1)
        #expect(await launchConnector.probeCount == 1)
        await launchStore.stopAllConnectors()
    }

    @Test @MainActor
    func explicitAutoSearchOffSkipsLaunchButManualSearchStillWorks()
        async throws
    {
        let defaults = makeDefaults("auto-off")
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let settings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: defaults)
        )
        settings.completeFirstManualScan(
            detectedConnectorIDs: [],
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        settings.setAutoSearchEnabled(false)

        let scanner = LocalProviderEligibilityScanner()
        let connector = try SearchFixtureConnector()
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            eligibilityScanner: scanner
        )
        let store = UsageStore(
            autoRefresh: true,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: connector.id,
            consentDefaults: defaults,
            agentSettings: settings
        )

        try await Task.sleep(for: .milliseconds(40))
        #expect((await scanner.diagnostics()).completedScanCount == 0)
        await store.searchForAgents()
        #expect((await scanner.diagnostics()).completedScanCount == 1)
        #expect(
            (await scanner.diagnostics()).countsByTrigger[.manualSearch] == 1
        )
        #expect(!settings.autoSearchEnabled)
        await store.stopAllConnectors()
    }

    @Test @MainActor
    func overlappingManualSearchAndRefreshShareOneRegisteredProviderScan()
        async throws
    {
        let defaults = makeDefaults("coalesce")
        defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let scanner = LocalProviderEligibilityScanner()
        let connector = try SearchFixtureConnector(blocksProbe: true)
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            eligibilityScanner: scanner
        )
        let settings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: defaults)
        )
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: connector.id,
            consentDefaults: defaults,
            agentSettings: settings
        )

        let search = Task { await store.searchForAgents() }
        try await waitUntil { await connector.didEnterProbe }
        let refresh = Task { await store.refresh() }
        await connector.releaseProbe()
        await search.value
        await refresh.value

        let diagnostics = await scanner.diagnostics()
        #expect(diagnostics.completedScanCount == 1)
        #expect(diagnostics.countsByTrigger[.manualSearch] == 1)
        #expect(await connector.probeCount == 1)
        #expect(settings.initialScanCompleted)
        await store.stopAllConnectors()
    }

    @Test @MainActor
    func authOnlyDetectionIsRememberedButDisabledMonitoringIsNotProbed()
        async throws
    {
        let authDefaults = makeDefaults("auth-only")
        defer {
            authDefaults.removePersistentDomain(
                forName: defaultsSuite(authDefaults)
            )
        }
        CodexMonitorConsentDecision.granted.persist(to: authDefaults)
        let authSettings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: authDefaults)
        )
        let authConnector = try SearchFixtureConnector(
            probe: .init(
                state: .authenticationRequired,
                safeFailure: .authorizationRequired
            ),
            snapshotState: .authenticationRequired
        )
        let authRegistry = try AgentConnectorRegistry(
            connectors: [authConnector]
        )
        let authStore = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: authRegistry,
            primaryConnectorID: authConnector.id,
            consentDefaults: authDefaults,
            agentSettings: authSettings
        )

        await authStore.searchForAgents()
        #expect(authSettings.record(for: authConnector.id).hasBeenDetected)
        #expect(authStore.presentationCards.isEmpty)
        #expect(authSettings.activeProviderIDs.isEmpty)
        #expect(
            authSettings.entries.first {
                $0.providerID == AgentPreferenceRecord.codexProviderID
            }?.requiresSetup == true
        )
        await authStore.stopAllConnectors()

        let disabledDefaults = makeDefaults("disabled")
        defer {
            disabledDefaults.removePersistentDomain(
                forName: defaultsSuite(disabledDefaults)
            )
        }
        CodexMonitorConsentDecision.granted.persist(to: disabledDefaults)
        let disabledSettings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: disabledDefaults)
        )
        disabledSettings.completeFirstManualScan(
            detectedConnectorIDs: [],
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        disabledSettings.setMonitoringEnabled(
            false,
            for: AgentPreferenceRecord.codexProviderID
        )
        let disabledConnector = try SearchFixtureConnector()
        let disabledRegistry = try AgentConnectorRegistry(
            connectors: [disabledConnector]
        )
        let disabledStore = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: disabledRegistry,
            primaryConnectorID: disabledConnector.id,
            consentDefaults: disabledDefaults,
            agentSettings: disabledSettings
        )

        await disabledStore.searchForAgents()
        #expect(await disabledConnector.probeCount == 0)
        #expect(
            !disabledSettings.record(for: disabledConnector.id)
                .hasBeenDetected
        )
        #expect(disabledStore.presentationCards.isEmpty)
        #expect(disabledStore.providerLoginOptions.isEmpty)
        #expect(
            disabledSettings.entries.first {
                $0.providerID == AgentPreferenceRecord.codexProviderID
            }?.requiresSetup == false
        )
        await disabledStore.stopAllConnectors()
    }

    @Test @MainActor
    func disablingMonitoringImmediatelyRemovesAnAdmittedProvider() async throws {
        let defaults = makeDefaults("live-disable")
        defer {
            defaults.removePersistentDomain(
                forName: defaultsSuite(defaults)
            )
        }
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let settings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: defaults)
        )
        let connector = try SearchFixtureConnector()
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: connector.id,
            consentDefaults: defaults,
            agentSettings: settings
        )

        await store.searchForAgents()
        #expect(store.presentationCards.count == 1)
        #expect(settings.activeProviderIDs == [
            AgentPreferenceRecord.codexProviderID,
        ])

        settings.setMonitoringEnabled(false, for: connector.id)

        #expect(store.presentationCards.isEmpty)
        #expect(store.providerSnapshots.isEmpty)
        #expect(store.providerLoginOptions.isEmpty)
        #expect(settings.activeProviderIDs.isEmpty)
        #expect(settings.setupRequiredProviderIDs.isEmpty)
        await store.stopAllConnectors()
    }

    @MainActor
    private func makeDefaults(_ label: String) -> UserDefaults {
        let name = "uma-011-g1-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(name, forKey: "test.suite-name")
        return defaults
    }

    @MainActor
    private func defaultsSuite(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "test.suite-name")!
    }

    private func waitUntil(
        attempts: Int = 200,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for controlled Agent Search state.")
    }
}

private actor SearchFixtureConnector: AgentUsageConnector {
    nonisolated let id = AgentConnectorID(rawValue: "codex.local")!
    nonisolated let descriptor: AgentConnectorDescriptor

    private let probeValue: AgentConnectorProbe
    private let snapshotValue: AgentUsageSnapshot
    private let blocksProbe: Bool
    private var probeContinuation: CheckedContinuation<Void, Never>?
    private(set) var didEnterProbe = false
    private(set) var probeCount = 0

    init(
        probe: AgentConnectorProbe = .init(state: .ready, safeFailure: nil),
        snapshotState: AgentConnectorState = .ready,
        blocksProbe: Bool = false
    ) throws {
        probeValue = probe
        self.blocksProbe = blocksProbe
        descriptor = try #require(
            AgentConnectorDescriptor(
                id: id,
                providerName: "Codex",
                officialSource: "registered fixture",
                sourceTier: .officialStructuredHook,
                sourceVersion: "1",
                supportedScopes: [.account],
                capabilities: [.connect, .refresh, .accountUsage],
                configurationRequirements: [.officialManagedSession],
                privacyAllowlist: ["current structured usage"],
                supportsRestore: false,
                supportsUninstall: false,
                unsupportedFields: ["credentials", "identity"],
                localSourceClass: .admittedStructuredLocal,
                authenticationMethod: .existingLocalSession,
                usageReadContract: .currentStructuredLocalRead,
                loginAssistance: .existingSessionOnly
            )
        )
        let isReady = snapshotState == .ready
        let failure: AgentSafeFailure? = isReady
            ? nil
            : .authorizationRequired
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        snapshotValue = AgentUsageSnapshot(
            id: id,
            providerName: "Codex",
            state: snapshotState,
            capturedAt: capturedAt,
            lastSuccessfulAt: isReady ? capturedAt : nil,
            freshness: isReady ? .fresh : .unavailable,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialStructuredHook,
                    sourceVersion: "1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: isReady ? .fresh : .unavailable,
                    capturedAt: isReady ? capturedAt : nil,
                    coverageNote: nil,
                    rateLimitWindows: isReady
                        ? [
                            AgentRateLimitWindow(
                                id: "seven-day",
                                kind: .sevenDay,
                                usedPercent: 44,
                                isUnlimited: false,
                                resetsAt: nil
                            )
                        ]
                        : [],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: failure
                )
            ],
            capabilities: descriptor.capabilities,
            safeFailure: failure
        )
    }

    func probe() async -> AgentConnectorProbe {
        probeCount += 1
        didEnterProbe = true
        if blocksProbe {
            await withCheckedContinuation { continuation in
                probeContinuation = continuation
            }
        }
        return probeValue
    }

    func releaseProbe() {
        probeContinuation?.resume()
        probeContinuation = nil
    }

    func start() async {}
    func refresh() async {}
    func perform(_ command: AgentConnectorCommand) async {}
    func stop() async {}
    func currentSnapshot() async -> AgentUsageSnapshot { snapshotValue }
    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            continuation.yield(snapshotValue)
        }
    }
}
