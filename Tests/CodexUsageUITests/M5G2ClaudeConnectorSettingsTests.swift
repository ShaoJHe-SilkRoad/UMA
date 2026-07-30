import ClaudeStatusLineCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5-G2 Claude connector and Settings")
struct M5G2ClaudeConnectorSettingsTests {
    @Test
    func descriptorLocksPrivacySourceAndSanitizedRestoreBoundary() {
        let descriptor = ClaudeCodeUsageConnector.production().descriptor
        #expect(descriptor.id.rawValue == "claude.statusLine")
        #expect(descriptor.providerName == "Claude Code")
        #expect(descriptor.officialSource == "Official local status line")
        #expect(descriptor.sourceTier == .officialStructuredHook)
        #expect(descriptor.localSourceClass == .admittedStructuredLocal)
        #expect(
            descriptor.usageReadContract
                == .currentStructuredLocalRead
        )
        #expect(!descriptor.supportsRestore)
        #expect(
            descriptor.capabilities.contains(
                .sanitizedLastValidRestore
            )
        )
        #expect(descriptor.supportsUninstall)
        #expect(
            descriptor.capabilities.contains(
                .passiveLocalAvailability
            )
        )
        #expect(
            descriptor.capabilities.contains(
                .hiddenFromDesktopAssistant
            )
        )
        for forbidden in [
            "sessionID",
            "promptID",
            "transcriptPath",
            "accountIdentity",
            "rawJSON",
            "credentials",
            "tokens",
        ] {
            #expect(descriptor.unsupportedFields.contains(forbidden))
        }
    }

    @Test
    func configurationStatesMapToRequiredConnectorLifecycle() async {
        let cases: [(
            ClaudeStatusLineConfigurationState,
            ClaudeConnectorLifecycleState,
            AgentConnectorState
        )] = [
            (.unconfigured, .notInstalled, .inactive),
            (.ready(priorStatusLinePresent: false), .notInstalled, .inactive),
            (.installed, .installedWaiting, .waitingForFirstResponse),
            (.repairRequired, .repairRequired, .failed),
            (.unsupported, .unsupported, .unsupported),
            (.failed, .failed, .failed),
        ]
        for (configuration, lifecycle, connectorState) in cases {
            let fixture = ConnectorFixture(configuration: configuration)
            defer { fixture.cleanup() }
            let connector = fixture.connector()
            let probe = await connector.probe()
            #expect(await connector.lifecycleState() == lifecycle)
            #expect(probe.state == connectorState)
            await connector.stop()
        }
    }

    @Test
    func currentPacketAdmitsClaudeAndConvertsExactlyOnceInSharedModel()
    async throws {
        let fixture = ConnectorFixture(configuration: .installed)
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.start()
        let packet = try fixture.packet(
            fiveHourUsed: 36.25,
            sevenDayUsed: 1
        )
        await connector.receiveEncodedPacket(try packet.encoded())
        let snapshot = await connector.currentSnapshot()
        #expect(snapshot.state == .ready)
        #expect(snapshot.freshness == .fresh)
        #expect(snapshot.channels.count == 1)
        #expect(
            snapshot.channels[0].rateLimitWindows.map(\.usedPercent)
                == [36.25, 1]
        )
        #expect(
            LocalProviderEligibilityScanner.admission(
                for: snapshot,
                descriptor: connector.descriptor
            ).admittedSnapshot == snapshot
        )
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .english,
            now: fixture.clock.now
        )
        #expect(card.windows[0].remaining == .finite(63.75))
        #expect(card.windows[1].remaining == .finite(99))
        #expect(card.selectedWindowID == "claude-five-hour")
        #expect(card.remaining == .finite(63.75))
        #expect(!card.isVisibleInDesktopAssistant)
        await connector.stop()
    }

    @Test
    func invalidPacketRetainsLastValidOnlyAsStale() async throws {
        let fixture = ConnectorFixture(configuration: .installed)
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.receiveEncodedPacket(
            try fixture.packet(
                fiveHourUsed: 10,
                sevenDayUsed: nil
            ).encoded()
        )
        #expect((await connector.currentSnapshot()).state == .ready)
        await connector.receiveEncodedPacket(Data("{".utf8))
        let failed = await connector.currentSnapshot()
        #expect(failed.state == .stale)
        #expect(failed.freshness == .stale)
        #expect(failed.safeFailure == .malformedResponse)
        #expect(!failed.channels.isEmpty)
        #expect(
            LocalProviderEligibilityScanner.admission(
                for: failed,
                descriptor: connector.descriptor
            ).admittedSnapshot == failed
        )
    }

    @Test
    func packetAgesToStaleAndRelaunchRestoresWithoutPrompt() async throws {
        let fixture = ConnectorFixture(configuration: .installed)
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.receiveEncodedPacket(
            try fixture.packet(
                fiveHourUsed: 10,
                sevenDayUsed: nil
            ).encoded()
        )
        fixture.clock.advance(
            by: ClaudeCodeUsageConnector.freshnessInterval + 1
        )
        let stale = await connector.currentSnapshot()
        #expect(stale.state == .stale)
        #expect(stale.freshness == .stale)
        #expect(await connector.lifecycleState() == .stale)

        let relaunched = fixture.connector()
        let probe = await relaunched.probe()
        #expect(probe.state == .stale)
        #expect(await relaunched.lifecycleState() == .stale)
        #expect(!(await relaunched.currentSnapshot()).channels.isEmpty)
        #expect((await relaunched.diagnostics()).acceptedPackets == 0)
    }

    @Test
    func manualRefreshChecksConfigurationWithoutGeneratingProviderData()
    async throws {
        let fixture = ConnectorFixture(configuration: .installed)
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.receiveEncodedPacket(
            try fixture.packet(
                fiveHourUsed: 10,
                sevenDayUsed: nil
            ).encoded()
        )
        let before = await connector.diagnostics()
        await connector.refresh(trigger: .manual)
        let after = await connector.diagnostics()
        #expect(after.acceptedPackets == before.acceptedPackets)
        #expect(after.rejectedPackets == before.rejectedPackets)
        #expect((await connector.currentSnapshot()).state == .ready)
    }

    @Test
    func socketTransportDrivesFreshStateAndRecoversAfterInvalidPacket()
    async throws {
        let fixture = ConnectorFixture(configuration: .installed)
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.start()
        let client = ClaudeStatusLineSocketClient(
            socketURL: fixture.socketURL
        )
        #expect(
            client.send(
                try fixture.packet(
                    fiveHourUsed: 12.5,
                    sevenDayUsed: 40
                )
            )
        )
        for _ in 0..<100
        where (await connector.currentSnapshot()).state != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect((await connector.currentSnapshot()).state == .ready)
        #expect((await connector.diagnostics()).listenerCount == 1)

        await connector.receiveEncodedPacket(Data("{".utf8))
        #expect((await connector.currentSnapshot()).state == .stale)
        #expect(
            client.send(
                try fixture.packet(
                    fiveHourUsed: 13,
                    sevenDayUsed: nil
                )
            )
        )
        for _ in 0..<100
        where (await connector.currentSnapshot()).state != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect((await connector.currentSnapshot()).state == .ready)
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.listenerCount == 1)
        #expect(diagnostics.acceptedPackets == 2)
        #expect(diagnostics.rejectedPackets == 1)
        await connector.stop()
    }

    @Test
    func passiveRegistryRetainsStaleAndRecoversWithoutAnotherListener()
    async throws {
        let fixture = ConnectorFixture(configuration: .installed)
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        let registry = try AgentConnectorRegistry(connectors: [connector])
        await registry.startPassiveConnectors()
        let initial = await registry.scanSurfaceAdmissions(
            trigger: .applicationLaunch
        )
        #expect(initial.admittedProviderIDs.isEmpty)

        let client = ClaudeStatusLineSocketClient(
            socketURL: fixture.socketURL
        )
        #expect(
            client.send(
                try fixture.packet(
                    fiveHourUsed: 18,
                    sevenDayUsed: 32
                )
            )
        )
        for _ in 0..<100
        where (await registry.orderedSnapshots()).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            await registry.orderedSnapshots().map(\.id)
                == [ClaudeCodeUsageConnector.connectorID]
        )

        await connector.receiveEncodedPacket(Data("{".utf8))
        for _ in 0..<100
        where (await registry.orderedSnapshots()).first?.state != .stale {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect((await registry.orderedSnapshots()).first?.state == .stale)

        #expect(
            client.send(
                try fixture.packet(
                    fiveHourUsed: 19,
                    sevenDayUsed: nil
                )
            )
        )
        for _ in 0..<100
        where (await registry.orderedSnapshots()).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            await registry.orderedSnapshots().map(\.id)
                == [ClaudeCodeUsageConnector.connectorID]
        )
        #expect((await connector.diagnostics()).listenerCount == 1)
        await registry.stopAll()
    }

    @Test
    func staleSnapshotSurvivesHealthRefreshUntilACurrentEventArrives()
    async throws {
        let fixture = ConnectorFixture(configuration: .installed)
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.receiveEncodedPacket(
            try fixture.packet(
                fiveHourUsed: 10,
                sevenDayUsed: nil
            ).encoded()
        )
        fixture.clock.advance(
            by: ClaudeCodeUsageConnector.freshnessInterval + 1
        )
        #expect((await connector.currentSnapshot()).state == .stale)
        await connector.refresh(trigger: .manual)
        #expect((await connector.currentSnapshot()).state == .stale)
        #expect(await connector.lifecycleState() == .stale)
    }

    @Test
    func concurrentHealthRefreshesAreCoalesced() async {
        let tracker = ConfigurationCheckTracker()
        let socketRoot = URL(
            fileURLWithPath: "/private/tmp",
            isDirectory: true
        ).appendingPathComponent(
            "m5g2-coalesce-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: socketRoot) }
        let connector = ClaudeCodeUsageConnector(
            socketURL: socketRoot.appendingPathComponent("usage.sock"),
            configurationCheck: {
                await tracker.check()
            }
        )
        async let first: Void = connector.refresh(trigger: .manual)
        async let second: Void = connector.refresh(trigger: .manual)
        async let third: Void = connector.refresh(trigger: .manual)
        _ = await (first, second, third)
        #expect(await tracker.total == 1)
        #expect(await tracker.maximumConcurrent == 1)
    }

    @Test
    func missingOptionalWindowIsNotInvented() async throws {
        let fixture = ConnectorFixture(configuration: .installed)
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.receiveEncodedPacket(
            try fixture.packet(
                fiveHourUsed: nil,
                sevenDayUsed: 25
            ).encoded()
        )
        let windows = (await connector.currentSnapshot())
            .channels[0].rateLimitWindows
        #expect(windows.count == 1)
        #expect(windows[0].kind == .sevenDay)
        #expect(windows[0].usedPercent == 25)
    }

    @Test
    func providerOrderIsCodexClaudeWorkBuddyWithoutPlaceholders() {
        let ids = [
            AgentConnectorID(rawValue: "workbuddy.accountWebCredits")!,
            AgentConnectorID(rawValue: "claude.statusLine")!,
            AgentConnectorID(rawValue: "codex")!,
        ].sorted(by: AgentProviderOrder.precedes)
        #expect(
            ids.map(\.rawValue)
                == ["codex", "claude.statusLine", "workbuddy.accountWebCredits"]
        )
        #expect(
            AgentProviderOrder.priority(
                for: AgentConnectorID(rawValue: "claude.statusLine")!
            ) == 100
        )
    }

    @Test
    @MainActor
    func agentSettingsListsClaudeBetweenCodexAndWorkBuddy() {
        let defaults = UserDefaults(
            suiteName: "uma-m5-g2-agent-settings-\(UUID().uuidString)"
        )!
        defer {
            defaults.removePersistentDomain(
                forName: defaults
                    .volatileDomainNames
                    .first(where: {
                        $0.contains("uma-m5-g2-agent-settings")
                    }) ?? ""
            )
        }
        let coordinator = AgentSettingsCoordinator(
            store: AgentPreferenceStore(defaults: defaults)
        )
        #expect(
            coordinator.entries.map(\.providerID.rawValue)
                == ["codex", "claude", "workbuddy"]
        )
        #expect(
            coordinator.entries.map(\.displayName)
                == ["Codex", "Claude Code", "WorkBuddy"]
        )
    }

    @Test
    @MainActor
    func settingsModelReactsFromWaitingToFreshWithoutAnotherAction()
    async throws {
        let root = URL(
            fileURLWithPath: "/private/tmp",
            isDirectory: true
        ).appendingPathComponent(
            "m5g2-settings-model-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ClaudeStatusLineConfigurationPaths(
            homeDirectory: root.appendingPathComponent("home"),
            applicationSupportDirectory: root.appendingPathComponent(
                "support"
            )
        )
        let manager = ClaudeStatusLineConfigurationManager(
            paths: paths,
            relayCommand:
                "'/synthetic/UMA.app/Contents/Helpers/ClaudeStatusLineRelay'"
        )
        try manager.enable()
        let clock = ConnectorClock()
        let connector = ClaudeCodeUsageConnector(
            socketURL: root.appendingPathComponent("usage.sock"),
            configurationCheck: { manager.check() },
            now: { clock.now }
        )
        let model = ClaudeStatusLineSettingsModel(
            manager: manager,
            connector: connector
        )
        model.checkClaudeCode()
        for _ in 0..<100 where model.state != .waiting {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.state == .waiting)

        let packet = try ClaudeStatusLinePacket(
            claudeVersion: "synthetic",
            fiveHour: ClaudeStatusLineWindowPacket(
                usedPercentage: 20,
                resetsAtEpochSeconds: 1_900_001_000
            ),
            sevenDay: nil,
            observedAt: clock.now
        )
        await connector.receiveEncodedPacket(try packet.encoded())
        for _ in 0..<100 {
            if case .fresh = model.state { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .fresh = model.state else {
            Issue.record("Settings did not react to the connector snapshot")
            return
        }
        await connector.stop()
        try manager.restore()
    }

    @Test
    func settingsSourceHasBoundedActionsTransparencyLocalizationAndNoCredentialControls()
    throws {
        let settings = try source(
            "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
        )
        let language = try source(
            "Sources/CodexUsageUI/Models/AppLanguage+Claude.swift"
        )
        let model = try source(
            "Sources/CodexUsageUI/Stores/ClaudeStatusLineSettingsModel.swift"
        )
        for token in [
            "claude.status-line.check",
            "claude.status-line.enable",
            "claude.status-line.repair",
            "claude.status-line.disable",
            "claude.status-line.source-transparency",
        ] {
            #expect(settings.contains(token))
        }
        for english in [
            "Official local status line",
            "Check Claude Code",
            "Enable Integration",
            "Waiting for Claude activity",
            "Repair Relay",
            "Disable Integration",
            "Credentials accessed by UMA: None",
            "Network requests made by UMA: None",
            "Transcript read: No",
            "Raw provider payload stored: No",
            "Stored locally: Sanitized last-valid quota only",
            "Authentication managed by: Claude Code",
            "Updates automatically the next time Claude Code is used.",
        ] {
            #expect(language.contains(english))
        }
        for chinese in [
            "官方本地状态栏",
            "检查 Claude Code",
            "启用集成",
            "等待 Claude 活动",
            "修复中继",
            "停用集成",
            "本地存储：仅经净化的最后有效额度",
            "下次使用 Claude Code 时会自动更新。",
        ] {
            #expect(language.contains(chinese))
        }
        let combined = settings + language + model
        for forbidden in [
            "SecureField",
            "apiKey",
            "API key",
            "OAuth",
            "password",
            "cookie",
            "login field",
        ] {
            #expect(!combined.contains(forbidden))
        }
        #expect(settings.contains("ScrollView(.vertical)"))
        #expect(settings.contains(".accessibilityIdentifier"))
        #expect(settings.contains(".buttonStyle"))
    }

    @Test
    func desktopAssistantHasNoClaudeOwnedSourceAndFiltersCapability() throws {
        let assistant = try source(
            "Sources/CodexUsageUI/Views/DesktopAssistantView.swift"
        )
        #expect(!assistant.contains("ClaudeStatusLine"))
        #expect(!assistant.contains("ClaudeCodeUsageConnector"))

        let fixture = ConnectorFixture(configuration: .installed)
        defer { fixture.cleanup() }
        let snapshot = AgentUsageSnapshot(
            id: ClaudeCodeUsageConnector.connectorID,
            providerName: "Claude Code",
            state: .ready,
            capturedAt: fixture.clock.now,
            lastSuccessfulAt: fixture.clock.now,
            freshness: .fresh,
            channels: [],
            capabilities: [.hiddenFromDesktopAssistant],
            safeFailure: nil
        )
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .english,
            now: fixture.clock.now
        )
        #expect(
            SharedUsagePresentationPolicy.assistantCards(from: [card])
                .isEmpty
        )
    }

    @Test
    func packageContractIncludesHelperAndExcludesArtifacts() throws {
        let script = try source("script/package_uma_m5_g2.sh")
        for required in [
            "ClaudeStatusLineRelay",
            "Contents/Helpers",
            "commit-exact",
            "UMA-M5-G2-Provenance.plist",
            "codesign --verify --deep --strict",
            "otool -L",
            "arm64",
            "LIVE-CLAUDE-QUOTA-NOT-YET-VALIDATED",
        ] {
            #expect(script.contains(required))
        }
        for forbidden in [
            "cp -R",
            "xattr -cr",
            "git add .",
            "settings.backup",
        ] {
            #expect(!script.contains(forbidden))
        }
        #expect(script.contains("-iname '*.sock'"))
        #expect(script.contains("-iname '*backup*'"))
        #expect(script.contains("umask 077"))
        #expect(script.contains("trap cleanup EXIT"))
    }

    @Test
    func relayAndConnectorSourcesContainNoNetworkOrCredentialPath() throws {
        let sources = try [
            "Sources/ClaudeStatusLineCore/ClaudeStatusLineProtocol.swift",
            "Sources/ClaudeStatusLineCore/ClaudeStatusLineSocket.swift",
            "Sources/ClaudeStatusLineCore/ClaudePriorCommandRunner.swift",
            "Sources/ClaudeStatusLineRelay/main.swift",
            "Sources/CodexUsageUI/Connectors/ClaudeCodeUsageConnector.swift",
            "Sources/CodexUsageUI/Stores/ClaudeStatusLineSettingsModel.swift",
        ].map { try source($0) }.joined(separator: "\n")
        for forbidden in [
            "URLSession",
            "NWConnection",
            "Network.framework",
            "Authorization: Bearer",
            "SecItemCopyMatching",
            "Keychain",
            "WKWebView",
        ] {
            #expect(!sources.contains(forbidden))
        }
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class ConnectorClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_900_000_000)

    var now: Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            value = value.addingTimeInterval(interval)
        }
    }
}

private final class ConnectorFixture: @unchecked Sendable {
    let root: URL
    let socketURL: URL
    let clock = ConnectorClock()
    let configuration: ClaudeStatusLineConfigurationState
    let snapshotStore: AgentConnectorSnapshotStore

    init(configuration: ClaudeStatusLineConfigurationState) {
        self.configuration = configuration
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "m5g2-connector-\(UUID().uuidString)",
                isDirectory: true
        )
        socketURL = root.appendingPathComponent("usage.sock")
        snapshotStore = AgentConnectorSnapshotStore(
            url: root.appendingPathComponent("connector-snapshots.json")
        )
    }

    func connector() -> ClaudeCodeUsageConnector {
        let configuration = self.configuration
        let clock = self.clock
        return ClaudeCodeUsageConnector(
            socketURL: socketURL,
            configurationCheck: {
                ClaudeStatusLineConfigurationCheck(
                    state: configuration,
                    priorStatusLinePresent: false
                )
            },
            snapshotStore: snapshotStore,
            now: { clock.now }
        )
    }

    func packet(
        fiveHourUsed: Double?,
        sevenDayUsed: Double?
    ) throws -> ClaudeStatusLinePacket {
        try ClaudeStatusLinePacket(
            claudeVersion: "synthetic-2.1.220",
            fiveHour: try fiveHourUsed.map {
                try ClaudeStatusLineWindowPacket(
                    usedPercentage: $0,
                    resetsAtEpochSeconds: 1_900_001_000
                )
            },
            sevenDay: try sevenDayUsed.map {
                try ClaudeStatusLineWindowPacket(
                    usedPercentage: $0,
                    resetsAtEpochSeconds: 1_900_002_000
                )
            },
            observedAt: clock.now
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor ConfigurationCheckTracker {
    private(set) var total = 0
    private(set) var concurrent = 0
    private(set) var maximumConcurrent = 0

    func check() async -> ClaudeStatusLineConfigurationCheck {
        total += 1
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        try? await Task.sleep(for: .milliseconds(50))
        concurrent -= 1
        return ClaudeStatusLineConfigurationCheck(
            state: .installed,
            priorStatusLinePresent: false
        )
    }
}
