import Foundation
import Combine
import Testing
@testable import CodexUsageUI

@Suite("M2WADBG-R3 local-live provider admission", .timeLimit(.minutes(1)))
struct M2WADBGLocalLiveAdmissionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func admissionMatrixHidesEveryNonCurrentProviderState() async throws {
        let cases: [
            (
                String,
                AgentConnectorProbe,
                AgentUsageSnapshot,
                ProviderSurfaceAdmission
            )
        ] = [
            (
                "codex.success",
                .init(state: .inactive, safeFailure: nil),
                snapshot(id: "codex.success"),
                .admitted(
                    LocalLiveProviderSnapshot(
                        snapshot: snapshot(id: "codex.success")
                    )
                )
            ),
            (
                "codex.inactive",
                .init(state: .failed, safeFailure: .unavailable),
                snapshot(
                    id: "codex.inactive",
                    state: .inactive,
                    freshness: .unavailable
                ),
                .hiddenNotRunning
            ),
            (
                "codex.loggedOut",
                .init(
                    state: .authenticationRequired,
                    safeFailure: .authorizationRequired
                ),
                snapshot(
                    id: "codex.loggedOut",
                    state: .authenticationRequired,
                    freshness: .unavailable,
                    failure: .authorizationRequired
                ),
                .hiddenNotAuthenticated
            ),
            (
                "codex.failed",
                .init(state: .inactive, safeFailure: nil),
                snapshot(
                    id: "codex.failed",
                    state: .failed,
                    freshness: .unavailable,
                    failure: .timedOut
                ),
                .hiddenCurrentReadFailed
            ),
            (
                "codex.malformed",
                .init(state: .ready, safeFailure: nil),
                snapshot(id: "codex.malformed", usedPercent: 101),
                .hiddenCurrentReadFailed
            ),
        ]

        for (id, probe, result, expected) in cases {
            let connector = try TestAdmissionConnector(
                id: id,
                probe: probe,
                snapshot: result
            )
            let scanner = LocalProviderEligibilityScanner()
            let set = await scanner.scan(
                candidates: [
                    .init(
                        connector: connector,
                        descriptor: connector.descriptor
                    )
                ],
                trigger: .manualRefresh
            )
            let record = try #require(set.records.first)
            if case .admitted = expected {
                #expect(record.admission.admittedSnapshot?.id.rawValue == id)
            } else {
                #expect(record.admission == expected)
                #expect(set.admittedProviderIDs.isEmpty)
            }
        }
    }

    @Test
    func concurrentRequestsCoalesceIntoOneScan() async throws {
        let connector = try TestAdmissionConnector(
            id: "codex.coalesced",
            probe: .init(state: .inactive, safeFailure: nil),
            snapshot: snapshot(id: "codex.coalesced"),
            blocksProbe: true
        )
        let joined = M5AEventCounter()
        let scanner = LocalProviderEligibilityScanner(onRequestCoalesced: { joined.signal() })
        let candidates = [
            RegisteredProviderCandidate(
                connector: connector,
                descriptor: connector.descriptor
            )
        ]
        async let first = scanner.scan(
            candidates: candidates,
            trigger: .manualRefresh
        )
        await connector.probeStarted.wait()
        async let second = scanner.scan(
            candidates: candidates,
            trigger: .manualRefresh
        )
        await joined.wait()
        await connector.releaseProbe()
        let (firstSet, secondSet) = await (first, second)

        #expect(firstSet == secondSet)
        #expect(await connector.probeCount == 1)
        let diagnostics = await scanner.diagnostics()
        #expect(diagnostics.completedScanCount == 1)
        #expect(diagnostics.coalescedRequestCount == 1)
        #expect(diagnostics.countsByTrigger[.manualRefresh] == 1)
    }

    @Test(arguments: [false, true]) @MainActor
    func stoppedOrPausedStoreRejectsLateNonCooperativeScan(pause: Bool) async throws {
        let connector = try TestAdmissionConnector(
            id: "codex.local",
            probe: .init(state: .ready, safeFailure: nil),
            snapshot: snapshot(id: "codex.local"),
            blocksProbe: true
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let preferences = ApplicationPreferences.inMemory()
        preferences.set(false, for: UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose)
        let store = UsageStore(
            autoRefresh: false,
            language: .english,
            registry: registry,
            primaryConnectorID: connector.id,
            preferences: preferences
        )
        store.grantMonitorConsent()
        await store.waitForInitialObservation()
        let scan = Task { await store.refresh() }
        await connector.probeStarted.wait()

        if pause {
            await store.suspendMonitoringForWindowClosure()
        } else {
            await store.stopAllConnectors()
        }
        // Shutdown/pause returns even while this fixture's probe deliberately
        // ignores cancellation. Its eventual completion must not restart it.
        let stoppedRevision = await registry.latestPublication().revision
        #expect(await connector.stopCount == 1)
        await connector.releaseProbe()
        await scan.value

        #expect(await connector.startCount == 0)
        #expect(await connector.refreshCount == 0)
        #expect(!(await connector.hasListener))
        #expect(await registry.orderedSnapshots().isEmpty)
        #expect(await registry.latestPublication().revision == stoppedRevision)
        #expect(store.providerSnapshots.isEmpty)
        #expect(store.presentationCards.isEmpty)
        #expect(!store.isRefreshing)
        if pause {
            await connector.allowFutureProbes()
            await store.resumeMonitoringForWindowPresentation()
            await store.refresh()
            #expect(await connector.startCount == 1)
            #expect(store.providerSnapshots.count == 1)
            await store.stopAllConnectors()
        } else {
            await store.refresh()
            #expect(await connector.probeCount == 1)
        }
    }

    @Test @MainActor
    func firstManualSearchThenRefreshAreTheOnlyStoreScanTriggers() async throws {
        let connector = try TestAdmissionConnector(
            id: "codex.local",
            probe: .init(state: .ready, safeFailure: nil),
            snapshot: snapshot(id: "codex.local")
        )
        let scanner = LocalProviderEligibilityScanner()
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            eligibilityScanner: scanner
        )
        let suiteName = "r3-scan-timing-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let store = UsageStore(
            autoRefresh: true,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: connector.id,
            consentDefaults: defaults,
            visibleRefreshInterval: .milliseconds(1),
            backgroundRefreshInterval: .milliseconds(1)
        )

        await store.waitForInitialObservation()
        #expect(!store.backgroundRefreshScheduled)
        #expect((await scanner.diagnostics()).completedScanCount == 0)
        await store.searchForAgents()
        #expect((await scanner.diagnostics()).completedScanCount == 1)
        store.setPanelVisible(true)
        store.setLanguage(.simplifiedChinese)
        store.setPanelVisible(false)
        await store.handleApplicationWake()
        await store.waitForInitialObservation()
        #expect(!store.backgroundRefreshScheduled)
        #expect((await scanner.diagnostics()).completedScanCount == 1)

        await store.refresh()
        #expect((await scanner.diagnostics()).completedScanCount == 2)
        #expect(
            (await scanner.diagnostics()).countsByTrigger[.manualSearch]
                == 1
        )
        #expect(
            (await scanner.diagnostics()).countsByTrigger[.manualRefresh] == 1
        )
        await store.stopAllConnectors()
    }

    @Test @MainActor
    func freshUpdatesRetainMaximumDecrementSelectionButNeverFailedCards() async throws {
        let connector = try TestAdmissionConnector(
            id: "codex.local",
            probe: .init(state: .ready, safeFailure: nil),
            snapshot: multiWindowSnapshot(
                fiveHourUsed: 5,
                sevenDayUsed: 30
            )
        )
        let scanner = LocalProviderEligibilityScanner()
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            eligibilityScanner: scanner
        )
        let suiteName = "r3-selection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: connector.id,
            consentDefaults: defaults
        )

        await store.refresh()
        // A first reading shows the shortest window; the window that then
        // falls furthest takes over.
        #expect(store.presentationCards.first?.selectedWindowID == "five-hour")

        await connector.configure(
            probe: .init(state: .ready, safeFailure: nil),
            snapshot: multiWindowSnapshot(
                fiveHourUsed: 6,
                sevenDayUsed: 45,
                capturedAt: now.addingTimeInterval(1)
            )
        )
        await store.refresh()
        #expect(store.presentationCards.first?.selectedWindowID == "seven-day")

        await connector.configure(
            probe: .init(state: .ready, safeFailure: nil),
            snapshot: snapshot(
                id: "codex.local",
                state: .failed,
                freshness: .unavailable,
                failure: .timedOut
            )
        )
        await store.refresh()
        #expect(store.presentationCards.isEmpty)
        #expect(store.providerSnapshots.isEmpty)
        await store.stopAllConnectors()
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func overlappingDifferentTriggersCoalesceUnderOneRefreshOwner() async throws {
        let connector = try TestAdmissionConnector(
            id: "codex.local",
            probe: .init(state: .ready, safeFailure: nil),
            snapshot: snapshot(id: "codex.local"),
            blocksProbe: true
        )
        let scanner = LocalProviderEligibilityScanner()
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            eligibilityScanner: scanner
        )
        let suiteName = "r3-overlap-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: connector.id,
            consentDefaults: defaults
        )

        let manual = Task { await store.refresh() }
        await connector.probeStarted.wait()
        let checkAgain = Task { @MainActor in await store.checkLocalSessionAgain() }
        await m5aWaitForPublished(store.coalescedScanRequests, matching: { $0 == 1 })
        await connector.releaseProbe()
        await manual.value
        await checkAgain.value

        #expect(!store.isRefreshing)
        let diagnostics = await scanner.diagnostics()
        #expect(diagnostics.completedScanCount == 1)
        #expect(await connector.probeCount == 1)
        #expect(diagnostics.countsByTrigger[.manualRefresh] == 1)
        #expect(diagnostics.countsByTrigger[.checkAgain] == nil)
        await store.stopAllConnectors()
    }

    @Test @MainActor
    func persistedSnapshotIsRestoredInternallyButNeverSurfaceAdmitted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("r3-restore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotStore = AgentConnectorSnapshotStore(
            url: directory.appendingPathComponent("snapshots.json")
        )
        try await snapshotStore.save([snapshot(id: "codex.local")])
        let savedSnapshots = await snapshotStore.load()
        #expect(savedSnapshots.count == 1)

        let connector = try TestAdmissionConnector(
            id: "codex.local",
            probe: .init(state: .failed, safeFailure: .unavailable),
            snapshot: snapshot(
                id: "codex.local",
                state: .inactive,
                freshness: .unavailable
            ),
            supportsRestore: true
        )
        let scanner = LocalProviderEligibilityScanner()
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            snapshotStore: snapshotStore,
            eligibilityScanner: scanner
        )
        let suiteName = "r3-restore-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        CodexMonitorConsentDecision.granted.persist(to: defaults)
        let store = UsageStore(
            autoRefresh: true,
            previewOnly: false,
            language: .english,
            registry: registry,
            primaryConnectorID: connector.id,
            consentDefaults: defaults
        )

        await store.waitForInitialObservation()
        let restoredRevision = await registry.latestPublication().revision
        for await inventory in store.$productInventory.values {
            if inventory.publicationRevision == restoredRevision { break }
        }
        #expect((await scanner.diagnostics()).completedScanCount == 0)
        #expect(store.presentationCards.isEmpty)
        #expect(store.providerSnapshots.isEmpty)
        #expect(await registry.orderedSnapshots().count == 1)

        await store.searchForAgents()
        #expect((await scanner.diagnostics()).completedScanCount == 1)
        #expect(await registry.orderedSnapshots().isEmpty)
        let clearedSnapshots = await snapshotStore.load()
        #expect(clearedSnapshots.isEmpty)
        await store.stopAllConnectors()
    }

    @Test
    func chineseLoginAppearsOnlyWhenAuthenticationIsTheSoleBlocker() async throws {
        let url = try #require(URL(string: "agent-cn://login"))
        let connector = try TestAdmissionConnector(
            id: "kimi.local",
            probe: .init(
                state: .authenticationRequired,
                safeFailure: .authorizationRequired
            ),
            snapshot: snapshot(
                id: "kimi.local",
                state: .authenticationRequired,
                freshness: .unavailable,
                failure: .authorizationRequired
            ),
            isChineseAgent: true,
            loginURL: url
        )
        let scanner = LocalProviderEligibilityScanner()
        let candidate = RegisteredProviderCandidate(
            connector: connector,
            descriptor: connector.descriptor
        )
        let beforeLogin = await scanner.scan(
            candidates: [candidate],
            trigger: .manualRefresh
        )
        #expect(beforeLogin.admittedProviderIDs.isEmpty)
        #expect(beforeLogin.loginOptions.map(\.id) == [connector.id])
        #expect(await connector.performCount == 0)

        await connector.configure(
            probe: .init(state: .inactive, safeFailure: nil),
            snapshot: snapshot(id: "kimi.local")
        )
        // Completing a provider-owned login cannot mutate the accepted result.
        #expect(beforeLogin.admittedProviderIDs.isEmpty)
        let afterCheckAgain = await scanner.scan(
            candidates: [candidate],
            trigger: .checkAgain
        )
        #expect(afterCheckAgain.admittedProviderIDs == [connector.id])
        #expect(afterCheckAgain.loginOptions.isEmpty)
        #expect((await scanner.diagnostics()).countsByTrigger[.checkAgain] == 1)

        await connector.configure(
            probe: .init(state: .ready, safeFailure: nil),
            snapshot: snapshot(
                id: "kimi.local",
                state: .failed,
                freshness: .unavailable,
                failure: .malformedResponse
            )
        )
        let failedCheckAgain = await scanner.scan(
            candidates: [candidate],
            trigger: .checkAgain
        )
        #expect(failedCheckAgain.admittedProviderIDs.isEmpty)
        #expect(failedCheckAgain.loginOptions.isEmpty)

        let existingSessionOnly = try TestAdmissionConnector(
            id: "doubao.local",
            probe: .init(
                state: .authenticationRequired,
                safeFailure: .authorizationRequired
            ),
            snapshot: snapshot(
                id: "doubao.local",
                state: .authenticationRequired,
                freshness: .unavailable,
                failure: .authorizationRequired
            )
        )
        let noLogin = await LocalProviderEligibilityScanner().scan(
            candidates: [
                .init(
                    connector: existingSessionOnly,
                    descriptor: existingSessionOnly.descriptor
                )
            ],
            trigger: .manualRefresh
        )
        #expect(noLogin.loginOptions.isEmpty)
    }

    @Test
    func workBuddyManualRecordIsHiddenAndByteStable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("r3-workbuddy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("manual.json")
        let persistence = WorkBuddyManualAvailabilityStore(fileURL: fileURL)
        let source = ManualWorkBuddyAvailabilitySource(store: persistence)
        try await source.setEnabled(true)
        let observation = try WorkBuddyManualDraft(
            scope: .personalShared,
            tier: .experience,
            remainingText: "2099.47",
            companionField: .none,
            companionText: ""
        ).validated(at: now)
        #expect(try await source.save(observation))
        let before = try Data(contentsOf: fileURL)
        let writeCount = await persistence.writeCount

        let connector = WorkBuddyAvailabilityConnector(source: source)
        let registry = try AgentConnectorRegistry(connectors: [connector])
        let result = await registry.scanSurfaceAdmissions(
            trigger: .applicationLaunch
        )

        #expect(result.admittedProviderIDs.isEmpty)
        #expect(result.loginOptions.isEmpty)
        #expect(
            result.records.first?.admission
                == .hiddenNoAdmittedLocalSource
        )
        #expect(await registry.orderedSnapshots().isEmpty)
        #expect(try Data(contentsOf: fileURL) == before)
        #expect(await persistence.writeCount == writeCount)
        #expect(
            (await source.load()).observation?.balance.remaining
                == Decimal(string: "2099.47")
        )
    }

    @Test
    func explicitLogoutEventRemovesProviderAndPersistedSnapshotWithoutScan() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("r3-terminal-withdrawal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotStore = AgentConnectorSnapshotStore(
            url: directory.appendingPathComponent("snapshots.json")
        )
        let connector = try TestAdmissionConnector(
            id: "codex.local",
            probe: .init(state: .ready, safeFailure: nil),
            snapshot: snapshot(id: "codex.local"),
            supportsRestore: true
        )
        let scanner = LocalProviderEligibilityScanner()
        let registry = try AgentConnectorRegistry(
            connectors: [connector],
            snapshotStore: snapshotStore,
            eligibilityScanner: scanner
        )
        let stream = await registry.snapshots()
        let consumer = Task {
            for await _ in stream {
                if Task.isCancelled { return }
            }
        }
        let initial = await registry.scanSurfaceAdmissions(
            trigger: .applicationLaunch
        )
        #expect(initial.admittedProviderIDs == [connector.id])
        #expect(await snapshotStore.load().count == 1)
        let completedScans = (await scanner.diagnostics()).completedScanCount

        let withdrawal = await registry.subscribe()
        await connector.emit(
            snapshot(
                id: "codex.local",
                state: .authenticationRequired,
                freshness: .unavailable,
                failure: .authorizationRequired
            )
        )
        await m5aWaitForPublication(withdrawal.updates) { publication in
            publication.snapshots.isEmpty
                && publication.admissionSet?.records.first?.admission == .hiddenNotAuthenticated
        }
        await registry.detach(withdrawal)
        #expect(await registry.orderedSnapshots().isEmpty)
        #expect(await snapshotStore.load().isEmpty)
        #expect((await scanner.diagnostics()).completedScanCount == completedScans)
        #expect(
            await registry.surfaceAdmissionSet()?.records.first?.admission
                == .hiddenNotAuthenticated
        )
        consumer.cancel()
        await registry.stopAll()
    }

    @Test
    func transientScanFailureCannotWithdrawAdmittedCodexOrCancelItsListener() async throws {
        let admitted = snapshot(id: "codex.local")
        let connector = try TestAdmissionConnector(
            id: "codex.local",
            probe: .init(state: .ready, safeFailure: nil),
            snapshot: admitted
        )
        let registry = try AgentConnectorRegistry(connectors: [connector])

        let initial = await registry.scanSurfaceAdmissions(
            trigger: .applicationLaunch
        )
        #expect(initial.admittedProviderIDs == [connector.id])
        #expect(await connector.hasListener)

        await connector.configure(
            probe: .init(state: .failed, safeFailure: .timedOut),
            snapshot: snapshot(
                id: "codex.local",
                state: .waitingForFirstResponse,
                freshness: .unavailable,
                failure: .timedOut
            )
        )

        let transient = await registry.scanSurfaceAdmissions(
            trigger: .manualRefresh
        )

        #expect(
            transient.records.first?.admission == .hiddenCurrentReadFailed
        )
        #expect(await registry.orderedSnapshots() == [admitted])
        #expect(await connector.hasListener)
        #expect(await connector.stopCount == 0)

        await registry.stopAll()
    }

    @Test
    func admittedIDsDriveBothSurfacesInStableProviderOrder() {
        let snapshots = [
            snapshot(id: "doubao.local"),
            snapshot(id: "cursor.local"),
            snapshot(id: "codex.local"),
            snapshot(id: "manus.local"),
            snapshot(id: "kimi.local"),
            snapshot(id: "claude.local"),
            snapshot(id: "workbuddy.local"),
        ]
        let cards = SharedUsagePresentationPolicy.makeCards(
            snapshots: snapshots,
            previousCards: [],
            language: .english,
            now: now
        )
        let expected = [
            "codex.local",
            "claude.local",
            "workbuddy.local",
            "manus.local",
            "cursor.local",
            "kimi.local",
            "doubao.local",
        ]
        #expect(cards.map(\.id) == expected)
        #expect(
            SharedUsagePresentationPolicy.assistantCards(from: cards).map(\.id)
                == expected
        )
    }

    @Test
    func sourceOwnershipAndZeroStateRemainPrivacyBounded() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scanner = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/LocalProviderEligibilityScanner.swift"
            ),
            encoding: .utf8
        )
        let store = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Stores/UsageStore.swift"
            ),
            encoding: .utf8
        )
        let panel = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsagePanelView.swift"
            ),
            encoding: .utf8
        )
        let assistant = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageMonitor/App/DesktopAssistantPanelController.swift"
            ),
            encoding: .utf8
        )
        let localization = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Models/AppLanguage+LocalLive.swift"
            ),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
            ),
            encoding: .utf8
        )

        #expect(
            localization.contains(
                "No locally accessible signed-in Agents detected."
            )
        )
        #expect(
            localization.contains(
                "Open a supported Agent, ensure it is signed in,\\nthen choose Refresh."
            )
        )
        #expect(localization.contains("Login for Data Sync"))
        #expect(localization.contains("登录以同步数据"))
        #expect(settings.contains("Link(destination: option.officialApplicationURL)"))
        #expect(settings.contains("Button(language.checkAgain"))
        #expect(store.contains("chineseLoginProviderName"))
        #expect(store.contains("agent-preview://login"))
        #expect(panel.contains("LocalLiveEmptyStateView"))
        #expect(assistant.contains("!cards.isEmpty"))
        #expect(!store.contains("periodicRefreshTask"))
        #expect(store.contains("backgroundRefreshSleeper"))
        #expect(store.contains("reconcileBackgroundRefreshPolicy"))
        #expect(store.contains("refreshAdmittedProviders(trigger: .timer)"))
        #expect(!store.contains("startPassiveConnectors"))
        #expect(store.contains("await registry.restorePersistedSnapshots()"))
        #expect(store.contains("previousCards: presentationCards"))
        #expect(!scanner.contains("NSWorkspace"))
        #expect(!scanner.contains("Process("))
        #expect(!scanner.contains("URLSession"))
        for forbidden in [
            "Keychain",
            "cookie",
            "auth database",
            "AXUIElement",
            "OCR",
            "CGWindow",
        ] {
            #expect(
                !scanner.localizedCaseInsensitiveContains(forbidden)
            )
        }
    }

    private func snapshot(
        id: String,
        state: AgentConnectorState = .ready,
        freshness: AgentConnectorFreshness = .fresh,
        failure: AgentSafeFailure? = nil,
        usedPercent: Double = 44
    ) -> AgentUsageSnapshot {
        let accountFreshness: AgentConnectorFreshness =
            state == .ready ? freshness : .unavailable
        return AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: id)!,
            providerName: id,
            state: state,
            capturedAt: now,
            lastSuccessfulAt: state == .ready ? now : nil,
            freshness: freshness,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialStructuredHook,
                    sourceVersion: "r3-fixture-v1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: accountFreshness,
                    capturedAt: state == .ready ? now : nil,
                    coverageNote: nil,
                    rateLimitWindows: state == .ready
                        ? [
                            AgentRateLimitWindow(
                                id: "current",
                                kind: .other,
                                usedPercent: usedPercent,
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
            capabilities: [.refresh, .accountUsage],
            safeFailure: failure
        )
    }

    private func multiWindowSnapshot(
        fiveHourUsed: Double,
        sevenDayUsed: Double,
        capturedAt: Date? = nil
    ) -> AgentUsageSnapshot {
        let capturedAt = capturedAt ?? now
        let fiveHourReset = now.addingTimeInterval(3_600)
        let sevenDayReset = now.addingTimeInterval(7 * 86_400)
        return AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: "codex.local")!,
            providerName: "Codex",
            state: .ready,
            capturedAt: capturedAt,
            lastSuccessfulAt: capturedAt,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialStructuredHook,
                    sourceVersion: "r3-fixture-v1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: capturedAt,
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: "five-hour",
                            kind: .fiveHour,
                            usedPercent: fiveHourUsed,
                            isUnlimited: false,
                            resetsAt: fiveHourReset
                        ),
                        AgentRateLimitWindow(
                            id: "seven-day",
                            kind: .sevenDay,
                            usedPercent: sevenDayUsed,
                            isUnlimited: false,
                            resetsAt: sevenDayReset
                        ),
                    ],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                )
            ],
            capabilities: [.refresh, .accountUsage],
            safeFailure: nil
        )
    }

}

private actor TestAdmissionConnector: AgentUsageConnector {
    nonisolated let probeStarted = M5AEventCounter()
    nonisolated let id: AgentConnectorID
    nonisolated let descriptor: AgentConnectorDescriptor
    private var probeValue: AgentConnectorProbe
    private var snapshotValue: AgentUsageSnapshot
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var probeContinuation: CheckedContinuation<Void, Never>?
    private var blocksProbe: Bool
    private(set) var didEnterProbe = false
    private(set) var probeCount = 0
    private(set) var startCount = 0
    private(set) var refreshCount = 0
    private(set) var performCount = 0
    private(set) var stopCount = 0

    init(
        id rawID: String,
        probe: AgentConnectorProbe,
        snapshot: AgentUsageSnapshot,
        blocksProbe: Bool = false,
        isChineseAgent: Bool = false,
        loginURL: URL? = nil,
        supportsRestore: Bool = false
    ) throws {
        id = AgentConnectorID(rawValue: rawID)!
        probeValue = probe
        snapshotValue = snapshot
        self.blocksProbe = blocksProbe
        descriptor = try #require(
            AgentConnectorDescriptor(
                id: id,
                providerName: rawID,
                officialSource: "task-owned admitted structured local fixture",
                sourceTier: .officialStructuredHook,
                sourceVersion: "r3-fixture-v1",
                supportedScopes: [.account],
                capabilities: [.connect, .refresh, .accountUsage],
                configurationRequirements: [.officialManagedSession],
                privacyAllowlist: ["current structured usage"],
                supportsRestore: supportsRestore,
                supportsUninstall: false,
                unsupportedFields: [
                    "credentials",
                    "accountIdentity",
                    "rawPayload",
                ],
                expectedRuntime: .activeOfficialApplicationCLIOrService,
                localSourceClass: .admittedStructuredLocal,
                authenticationMethod: isChineseAgent
                    ? .officialApplicationOwnedSession
                    : .existingLocalSession,
                usageReadContract: .currentStructuredLocalRead,
                loginAssistance: isChineseAgent
                    ? .userInitiatedOfficialChineseAppLogin
                    : .existingSessionOnly,
                isRegisteredChineseAgent: isChineseAgent,
                officialLoginApplicationURL: loginURL
            )
        )
    }

    func probe() async -> AgentConnectorProbe {
        probeCount += 1
        didEnterProbe = true
        probeStarted.signal()
        if blocksProbe {
            await withCheckedContinuation { continuation in
                probeContinuation = continuation
            }
        }
        return probeValue
    }

    func allowFutureProbes() { blocksProbe = false }

    func releaseProbe() {
        probeContinuation?.resume()
        probeContinuation = nil
    }

    func configure(
        probe: AgentConnectorProbe,
        snapshot: AgentUsageSnapshot
    ) {
        probeValue = probe
        snapshotValue = snapshot
    }

    func start() async {
        startCount += 1
    }

    func refresh() async {
        refreshCount += 1
    }

    func refresh(trigger: CodexRefreshTrigger) async {
        await refresh()
    }

    func perform(_ command: AgentConnectorCommand) async {
        performCount += 1
    }

    func stop() async {
        stopCount += 1
        continuation = nil
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        snapshotValue
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(snapshotValue)
        }
    }

    func emit(_ snapshot: AgentUsageSnapshot) {
        snapshotValue = snapshot
        continuation?.yield(snapshot)
    }

    var hasListener: Bool { continuation != nil }
}
