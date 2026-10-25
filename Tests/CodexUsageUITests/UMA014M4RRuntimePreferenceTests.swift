import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("UMA014 M4R runtime preference contracts", .serialized)
struct UMA014M4RRuntimePreferenceTests {
    @Test("Automatic refresh is preference-driven and targets current admissions only")
    func backgroundRefreshUsesOnlyAdmittedProvidersWithoutDiscovery() throws {
        let source = try sourceText("Sources/CodexUsageUI/Stores/UsageStore.swift")
        let scheduler = try #require(source.range(
            of: "private func reconcileBackgroundRefreshPolicy()"
        ))
        let refresher = try #require(source.range(
            of: "private func refreshAdmittedProviders(trigger: CodexRefreshTrigger)"
        ))
        let applyPreferences = try #require(source.range(
            of: "private func applyMonitoringPreferences()"
        ))
        let schedulerBody = String(source[scheduler.lowerBound..<refresher.lowerBound])
        let refreshBody = String(source[refresher.lowerBound..<applyPreferences.lowerBound])

        #expect(schedulerBody.contains(
            "UMAApplicationPreferenceKeys.automaticBackgroundRefresh"
        ))
        #expect(schedulerBody.contains(
            "UMAApplicationPreferenceKeys.backgroundRefreshInterval"
        ))
        #expect(schedulerBody.contains("refreshAdmittedProviders(trigger: .timer)"))
        #expect(refreshBody.contains("let ids = providerSnapshots.map(\\.id)"))
        #expect(refreshBody.contains("registry.refresh(id, trigger: trigger)"))
        #expect(!refreshBody.contains("performEligibilityScan"))
        #expect(!refreshBody.contains("scanSurfaceAdmissions"))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func refreshOnWakeHonorsPreferenceAndNeverDiscovers() async throws {
        let preferences = ApplicationPreferences.inMemory(seed: [
            UMAApplicationPreferenceKeys.automaticBackgroundRefresh.name: false,
            UMAApplicationPreferenceKeys.refreshOnWake.name: false,
        ])
        let admitted = try RuntimePreferenceFixtureConnector(
            id: "m4r.wake.admitted",
            state: .ready
        )
        let dormant = try RuntimePreferenceFixtureConnector(
            id: "m4r.wake.dormant",
            state: .failed,
            failure: .unavailable
        )
        let scanner = LocalProviderEligibilityScanner()
        let registry = try AgentConnectorRegistry(
            connectors: [admitted, dormant],
            eligibilityScanner: scanner
        )
        let store = makeStore(
            preferences: preferences,
            registry: registry
        )

        await store.searchForAgents()
        await store.handleApplicationWake()
        let disabledWakeTriggers = await admitted.refreshTriggers
        #expect(disabledWakeTriggers == [.manual])

        preferences.set(true, for: UMAApplicationPreferenceKeys.refreshOnWake)
        await store.handleApplicationWake()

        let enabledWakeTriggers = await admitted.refreshTriggers
        let dormantTriggers = await dormant.refreshTriggers
        let wakeScannerDiagnostics = await scanner.diagnostics()
        #expect(enabledWakeTriggers == [.manual, .wake])
        #expect(dormantTriggers.isEmpty)
        #expect(wakeScannerDiagnostics.completedScanCount == 1)
        await store.stopAllConnectors()
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func windowCloseSuspensionPreservesPublicationAndResumesOneSession() async throws {
        let preferences = ApplicationPreferences.inMemory(seed: [
            UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose.name: false,
            UMAApplicationPreferenceKeys.automaticBackgroundRefresh.name: false,
        ])
        let admitted = try RuntimePreferenceFixtureConnector(
            id: "m4r.window.admitted",
            state: .ready
        )
        let scanner = LocalProviderEligibilityScanner()
        let registry = try AgentConnectorRegistry(
            connectors: [admitted],
            eligibilityScanner: scanner
        )
        let store = makeStore(
            preferences: preferences,
            registry: registry
        )

        await store.searchForAgents()
        let publishedBeforeClose = store.providerSnapshots
        let initialStartCount = await admitted.startCount
        let initialMaximumSessions = await admitted.maximumConcurrentSessions
        #expect(initialStartCount == 1)
        #expect(initialMaximumSessions == 1)

        await store.suspendMonitoringForWindowClosure()
        let stopCount = await admitted.stopCount
        #expect(stopCount == 1)
        #expect(store.providerSnapshots == publishedBeforeClose)

        await store.resumeMonitoringForWindowPresentation()
        await store.resumeMonitoringForWindowPresentation()

        let resumedStartCount = await admitted.startCount
        let streamCount = await admitted.snapshotStreamCount
        let maximumSessions = await admitted.maximumConcurrentSessions
        let closeScannerDiagnostics = await scanner.diagnostics()
        #expect(resumedStartCount == 2)
        #expect(streamCount == 2)
        #expect(maximumSessions == 1)
        #expect(store.providerSnapshots == publishedBeforeClose)
        #expect(closeScannerDiagnostics.completedScanCount == 1)
        await store.stopAllConnectors()
    }

    @Test("Only canonical application windows participate in close monitoring")
    func windowCloseObserverRejectsUnrelatedWindows() throws {
        let source = try sourceText(
            "Sources/CodexUsageMonitor/App/AppShellCoordinator.swift"
        )
        #expect(source.contains("mainWindowController.window,"))
        #expect(source.contains("settingsWindowController.window,"))
        #expect(source.contains("object: window"))
        #expect(!source.contains("forName: NSWindow.willCloseNotification,\n            object: nil"))
    }

    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func keepMonitoringEnabledDoesNotSuspendConnectors() async throws {
        let preferences = ApplicationPreferences.inMemory(seed: [
            UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose.name: true,
            UMAApplicationPreferenceKeys.automaticBackgroundRefresh.name: false,
        ])
        let admitted = try RuntimePreferenceFixtureConnector(
            id: "m4r.window.keep-running",
            state: .ready
        )
        let registry = try AgentConnectorRegistry(connectors: [admitted])
        let store = makeStore(
            preferences: preferences,
            registry: registry
        )

        await store.searchForAgents()
        await store.suspendMonitoringForWindowClosure()

        let stopCount = await admitted.stopCount
        let startCount = await admitted.startCount
        #expect(stopCount == 0)
        #expect(startCount == 1)
        await store.stopAllConnectors()
    }

    @MainActor
    @Test("Retained-data clear targets only the three isolated allowlisted stores")
    func retainedDataClearUsesIsolatedStores() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("uma-m4r-clear-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshotURL = root.appendingPathComponent("snapshots.json")
        let browserURL = root.appendingPathComponent("browser/cache.json")
        let anchorURL = root.appendingPathComponent("smart/anchors.json")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let unrelated = root.appendingPathComponent("unrelated.json")
        try Data("preserve-me".utf8).write(to: unrelated)

        let source = try sourceText(
            "Sources/CodexUsageUI/Services/SettingsDataActions.swift"
        )
        #expect(source.contains("try await snapshots.clear()"))
        #expect(source.contains("try await browserCache.clear()"))
        #expect(source.contains("try await smartAnchors.clear()"))

        let service = SettingsRetainedDataService(
            snapshots: AgentConnectorSnapshotStore(url: snapshotURL),
            browserCache: ClaudeBrowserSanitizedCacheStore(url: browserURL),
            smartAnchors: ClaudeSmartAnchorStore(url: anchorURL)
        )
        try await service.clear()

        #expect(!FileManager.default.fileExists(atPath: snapshotURL.path))
        #expect(!FileManager.default.fileExists(atPath: browserURL.path))
        #expect(!FileManager.default.fileExists(atPath: anchorURL.path))
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "preserve-me")
    }

    @MainActor
    @Test("Retained-data clear fails closed for symlinks and unsafe item types")
    func retainedDataClearRejectsUnsafeItems() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("uma-m4r-unsafe-clear-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target.json")
        try Data("must-survive".utf8).write(to: target)
        let symlink = root.appendingPathComponent("snapshots.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        let service = SettingsRetainedDataService(
            snapshots: AgentConnectorSnapshotStore(url: symlink),
            browserCache: ClaudeBrowserSanitizedCacheStore(
                url: root.appendingPathComponent("browser/cache.json")
            ),
            smartAnchors: ClaudeSmartAnchorStore(
                url: root.appendingPathComponent("smart/anchors.json")
            )
        )

        await #expect(throws: AgentConnectorSnapshotStore.StoreError.rejected) {
            try await service.clear()
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "must-survive")

        try FileManager.default.removeItem(at: symlink)
        try FileManager.default.createDirectory(at: symlink, withIntermediateDirectories: false)
        await #expect(throws: AgentConnectorSnapshotStore.StoreError.rejected) {
            try await service.clear()
        }
        #expect(FileManager.default.fileExists(atPath: symlink.path))
    }

    @MainActor
    @Test("Settings diagnostics serialize exactly the content-free allowlist")
    func settingsDiagnosticsAreStrictlyAllowlisted() throws {
        let preferences = ApplicationPreferences.inMemory(seed: [
            UMAApplicationPreferenceKeys.automaticBackgroundRefresh.name: true,
            UMAApplicationPreferenceKeys.refreshOnWake.name: true,
            UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose.name: false,
            UMAApplicationPreferenceKeys.language.name: "private-looking-fixture",
        ])
        let data = try SettingsDiagnosticsExporter.data(
            activeProviderCount: 2,
            preferences: preferences,
            grokBotPresence: .notInstalled
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(object.keys) == [
            "schemaVersion",
            "applicationVersion",
            "applicationBuild",
            "activeProviderCount",
            "automaticBackgroundRefresh",
            "refreshOnWake",
            "keepMonitoringWhenWindowsClose",
            "grokBotPresence",
        ])
        #expect(object["schemaVersion"] as? Int == 2)
        #expect(object["grokBotPresence"] as? String == "notInstalled")
        #expect(object["activeProviderCount"] as? Int == 2)
        #expect(object["automaticBackgroundRefresh"] as? Bool == true)
        #expect(object["refreshOnWake"] as? Bool == true)
        #expect(object["keepMonitoringWhenWindowsClose"] as? Bool == false)
        #expect(!String(decoding: data, as: UTF8.self).contains("private-looking-fixture"))
    }

    @Test("Settings diagnostics export rejects symlinks and unsafe file targets")
    func settingsDiagnosticsExportFailsClosed() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("uma-m4r-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let data = Data("{\"schemaVersion\":1}".utf8)
        let safeDestination = root.appendingPathComponent("diagnostics.json")
        try SettingsDiagnosticsExporter.write(data, to: safeDestination)
        #expect(try Data(contentsOf: safeDestination) == data)
        let attributes = try FileManager.default.attributesOfItem(atPath: safeDestination.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        let protectedTarget = root.appendingPathComponent("protected.json")
        try Data("preserve".utf8).write(to: protectedTarget)
        let symlink = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: protectedTarget)
        #expect(throws: SettingsDataActionError.unsafeExportDestination) {
            try SettingsDiagnosticsExporter.write(data, to: symlink)
        }
        #expect(try String(contentsOf: protectedTarget, encoding: .utf8) == "preserve")

        let directory = root.appendingPathComponent("directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        #expect(throws: SettingsDataActionError.unsafeExportDestination) {
            try SettingsDiagnosticsExporter.write(data, to: directory)
        }
    }

    @MainActor
    @Test("Wizard display preferences rebuild the real hosted view from shared truth")
    func wizardDisplayPreferencesReachControllerAndView() throws {
        let suiteName = "uma-m4r-wizard-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ApplicationPreferences.inMemory(seed: [
            UMAApplicationPreferenceKeys.assistantEnabled.name: true,
            UMAApplicationPreferenceKeys.assistantShowsStatusIndicator.name: false,
            UMAApplicationPreferenceKeys.assistantShowsPercentageRail.name: false,
        ])
        let controller = DesktopAssistantPanelController(defaults: defaults)
        defer { controller.tearDown() }
        controller.bind(preferences: preferences)
        controller.update(cards: [wizardCard])

        var hosted = try #require(
            controller.assistantPanelForTesting.contentView
                as? NSHostingView<DesktopAssistantView>
        )
        #expect(hosted.rootView.showsStatusIndicator == false)
        #expect(hosted.rootView.showsPercentageRail == false)

        preferences.set(
            true,
            for: UMAApplicationPreferenceKeys.assistantShowsStatusIndicator
        )
        preferences.set(
            true,
            for: UMAApplicationPreferenceKeys.assistantShowsPercentageRail
        )

        hosted = try #require(
            controller.assistantPanelForTesting.contentView
                as? NSHostingView<DesktopAssistantView>
        )
        #expect(hosted.rootView.showsStatusIndicator)
        #expect(hosted.rootView.showsPercentageRail)
    }

    @MainActor
    private func makeStore(
        preferences: ApplicationPreferences,
        registry: AgentConnectorRegistry
    ) -> UsageStore {
        let settings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: preferences)
        )
        return UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: nil,
            consentDefaults: nil,
            preferences: preferences,
            agentSettings: settings,
            backgroundRefreshSleeper: { _ in throw CancellationError() }
        )
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var wizardCard: DesktopAssistantCard {
        DesktopAssistantCard(
            id: "codex.local",
            providerName: "Codex",
            planLabel: "Plus",
            connectionState: .connected,
            selectedWindowShortLabel: "7D",
            selectedWindowAccessibilityLabel: "seven-day window",
            resetText: "Resets later",
            usageValue: .estimated(64),
            tintFraction: 0.64,
            severity: .normal,
            isStale: false
        )
    }
}

private actor RuntimePreferenceFixtureConnector: AgentUsageConnector {
    nonisolated let id: AgentConnectorID
    nonisolated let descriptor: AgentConnectorDescriptor
    private var snapshot: AgentUsageSnapshot
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var snapshotStreamCount = 0
    private(set) var refreshTriggers: [CodexRefreshTrigger] = []
    private(set) var maximumConcurrentSessions = 0
    private var isRunning = false

    init(
        id rawID: String,
        state: AgentConnectorState,
        failure: AgentSafeFailure? = nil
    ) throws {
        let id = try #require(AgentConnectorID(rawValue: rawID))
        self.id = id
        descriptor = try #require(
            AgentConnectorDescriptor(
                id: id,
                providerName: "Runtime fixture",
                officialSource: "structured deterministic fixture",
                sourceTier: .officialStructuredHook,
                sourceVersion: "m4r-v1",
                supportedScopes: [.account],
                capabilities: [.connect, .refresh, .disconnect],
                configurationRequirements: [.userAuthorization],
                privacyAllowlist: ["aggregate percentage"],
                supportsRestore: false,
                supportsUninstall: false,
                unsupportedFields: ["raw payload"],
                localSourceClass: .admittedStructuredLocal,
                usageReadContract: .currentStructuredLocalRead
            )
        )
        snapshot = AgentUsageSnapshot(
            id: id,
            providerName: "Runtime fixture",
            state: state,
            capturedAt: Date(timeIntervalSince1970: 1_788_134_400),
            lastSuccessfulAt: state == .ready
                ? Date(timeIntervalSince1970: 1_788_134_400)
                : nil,
            freshness: state == .ready ? .fresh : .unavailable,
            channels: state == .ready ? [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialStructuredHook,
                    sourceVersion: "m4r-v1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: Date(timeIntervalSince1970: 1_788_134_400),
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: "seven-day",
                            kind: .sevenDay,
                            usedPercent: 40,
                            isUnlimited: false,
                            resetsAt: nil
                        ),
                    ],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                ),
            ] : [],
            capabilities: [.connect, .refresh, .disconnect],
            safeFailure: failure
        )
    }

    func probe() async -> AgentConnectorProbe {
        AgentConnectorProbe(state: snapshot.state, safeFailure: snapshot.safeFailure)
    }

    func start() async {
        startCount += 1
        if !isRunning { isRunning = true }
        maximumConcurrentSessions = max(maximumConcurrentSessions, isRunning ? 1 : 0)
        continuation?.yield(snapshot)
    }

    func refresh() async {
        await refresh(trigger: .manual)
    }

    func refresh(trigger: CodexRefreshTrigger) async {
        refreshTriggers.append(trigger)
        continuation?.yield(snapshot)
    }

    func perform(_ command: AgentConnectorCommand) async {
        if command == .disconnect { await stop() }
    }

    func stop() async {
        stopCount += 1
        isRunning = false
        continuation?.finish()
        continuation = nil
    }

    func currentSnapshot() async -> AgentUsageSnapshot { snapshot }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        snapshotStreamCount += 1
        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(snapshot)
        }
    }
}
