import ClaudeStatusLineCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5DBG three-provider acceptance")
struct M5DBGThreeProviderAcceptanceTests {
    @Test
    func fiftyEventMatrixHasExactAcceptanceAndPublicationBoundaries()
    async throws {
        let fixture = M5DBGClaudeFixture()
        defer { fixture.cleanup() }
        let connector = fixture.connector()

        for invalid in [
            Data("{".utf8),
            Data(#"{"private":"rejected"}"#.utf8),
            Data(#"{"schemaVersion":1}"#.utf8),
        ] {
            await connector.receiveEncodedPacket(invalid)
        }

        var finalPacket: ClaudeStatusLinePacket?
        for index in 0..<43 {
            let packet = try fixture.packet(
                fiveHourUsed: Double(index),
                sevenDayUsed: Double(100 - index)
            )
            finalPacket = packet
            await connector.receiveEncodedPacket(try packet.encoded())
        }
        let duplicate = try #require(finalPacket)
        await connector.receiveEncodedPacket(try duplicate.encoded())
        await connector.receiveEncodedPacket(try duplicate.encoded())

        #expect(throws: Error.self) {
            _ = try ClaudeStatusLineProjection.decode(Data("{".utf8))
        }
        #expect(throws: ClaudeStatusLineProtocolError.inputTooLarge) {
            _ = try ClaudeStatusLineProjection.decode(
                Data(
                    repeating: 0x20,
                    count: ClaudeStatusLineProjection.maximumInputBytes + 1
                )
            )
        }

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.acceptedPackets == 45)
        #expect(diagnostics.rejectedPackets == 3)
        #expect(diagnostics.publishedSnapshots == 44)
        #expect(diagnostics.listenerCount == 0)
        #expect((await connector.currentSnapshot()).state == .ready)
    }

    @Test
    func thirtyGlobalRefreshesReadCodexAndWorkBuddyOnceAndOnlyHealthCheckClaude()
    async throws {
        let fixture = M5DBGClaudeFixture()
        defer { fixture.cleanup() }
        let tracker = M5DBGConfigurationTracker()
        let claude = fixture.connector(configurationCheck: {
            await tracker.check()
        })
        await claude.receiveEncodedPacket(
            try fixture.packet(fiveHourUsed: 20, sevenDayUsed: 40).encoded()
        )
        let codex = M5DBGReadCountingConnector(
            id: AgentConnectorID(rawValue: "codex.local")!,
            providerName: "Codex"
        )
        let workBuddy = M5DBGReadCountingConnector(
            id: AgentConnectorID(
                rawValue: "workbuddy.accountWebCredits"
            )!,
            providerName: "WorkBuddy"
        )
        let registry = try AgentConnectorRegistry(
            connectors: [workBuddy, claude, codex]
        )

        for _ in 0..<30 {
            _ = await registry.scanSurfaceAdmissions(
                trigger: .manualRefresh
            )
        }

        #expect(await codex.readCount == 30)
        #expect(await workBuddy.readCount == 30)
        #expect(await tracker.count == 30)
        #expect((await claude.diagnostics()).acceptedPackets == 1)
        #expect((await claude.diagnostics()).rejectedPackets == 0)
        #expect(
            await registry.orderedSnapshots().map(\.id.rawValue)
                == [
                    "codex.local",
                    "claude.statusLine",
                    "workbuddy.accountWebCredits",
                ]
        )
        #expect(
            SharedUsagePresentationPolicy.assistantCards(
                from: SharedUsagePresentationPolicy.makeCards(
                    snapshots: await registry.orderedSnapshots(),
                    previousCards: [],
                    language: .english,
                    now: fixture.now
                )
            ).map(\.id)
                == [
                    "codex.local",
                    "claude.statusLine",
                    "workbuddy.accountWebCredits",
                ]
        )
        await registry.stopAll()
    }

    @Test
    func m5dbgPackagingAndDurableRecordsAreExactAndPrivacyBounded()
    throws {
        let packageScript = try source("script/package_uma_m5_g2.sh")
        let renderer = try source("Sources/PreviewRendererTool/main.swift")
        for required in [
            "m5dbg-preflight",
            "m5dbg-final",
            "uma-m5dbg-preflight-${commit:0:12}",
            "uma-m5dbg-final-$commit",
            "UMA-M5DBG-Provenance.plist",
            "THREE-PROVIDER-DEBUG-ACCEPTED-SETTINGS-RESTORED",
        ] {
            #expect(packageScript.contains(required))
        }
        for required in [
            "--claude",
            "--claude-five-hour-only",
            "--claude-seven-day-only",
            "--claude-expanded",
            "--claude-cached",
            "--claude-stale",
            "--claude-failed",
            "claude.statusLine",
            "isVisibleInDesktopAssistant: true",
            "--assistant-claude",
        ] {
            #expect(renderer.contains(required))
        }

        let record = try source("source/UMA M5DBG Acceptance.md")
        let handoff = try source(
            "source/UMA M5A Claude Assistant Handoff.md"
        )
        for required in [
            "Codex → Claude Code → WorkBuddy",
            "exact settings restoration",
            "50-event sanitized matrix",
            "30 global Manual Refresh actions",
            "Claude Code remains excluded from Desktop Assistant",
        ] {
            #expect((record + handoff).contains(required))
        }
        for forbidden in [
            "session_id",
            "prompt_id",
            "transcript_path",
            "account identity:",
            "prompt content:",
            "response content:",
            "raw JSON:",
        ] {
            #expect(!(record + handoff).contains(forbidden))
        }
        #expect(
            (record + handoff).range(
                of: #"\b[0-9a-f]{64}\b"#,
                options: .regularExpression
            ) == nil
        )
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

private actor M5DBGConfigurationTracker {
    private(set) var count = 0

    func check() -> ClaudeStatusLineConfigurationCheck {
        count += 1
        return ClaudeStatusLineConfigurationCheck(
            state: .installed,
            priorStatusLinePresent: false
        )
    }
}

private actor M5DBGReadCountingConnector: AgentUsageConnector {
    nonisolated let id: AgentConnectorID
    nonisolated let descriptor: AgentConnectorDescriptor
    private(set) var readCount = 0

    init(id: AgentConnectorID, providerName: String) {
        self.id = id
        descriptor = AgentConnectorDescriptor(
            id: id,
            providerName: providerName,
            officialSource: "synthetic M5DBG source",
            sourceTier: .officialLocalService,
            sourceVersion: "synthetic-1",
            supportedScopes: [.account],
            capabilities: [.refresh, .rateLimits],
            configurationRequirements: [],
            privacyAllowlist: [],
            supportsRestore: false,
            supportsUninstall: false,
            unsupportedFields: [],
            expectedRuntime: .none,
            localSourceClass: .admittedStructuredLocal,
            authenticationMethod: .none,
            usageReadContract: .currentStructuredLocalRead,
            loginAssistance: .none
        )!
    }

    func probe() async -> AgentConnectorProbe {
        AgentConnectorProbe(state: .ready, safeFailure: nil)
    }

    func start() async {}

    func refresh() async {
        readCount += 1
    }

    func perform(_ command: AgentConnectorCommand) async {
        if command == .refresh || command == .connect {
            readCount += 1
        }
    }

    func stop() async {}

    func currentSnapshot() async -> AgentUsageSnapshot {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        return AgentUsageSnapshot(
            id: id,
            providerName: descriptor.providerName,
            state: .ready,
            capturedAt: now,
            lastSuccessfulAt: now,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialLocalService,
                    sourceVersion: "synthetic-1",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: now,
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: "synthetic-five-hour",
                            kind: .fiveHour,
                            usedPercent: 25,
                            isUnlimited: false,
                            resetsAt: now.addingTimeInterval(3_600)
                        )
                    ],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                )
            ],
            capabilities: [.refresh, .rateLimits],
            safeFailure: nil
        )
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        let snapshot = await currentSnapshot()
        return AsyncStream { continuation in
            continuation.yield(snapshot)
        }
    }
}

private final class M5DBGClaudeFixture: @unchecked Sendable {
    let root: URL
    let socketURL: URL
    let now = Date(timeIntervalSince1970: 1_900_000_000)

    init() {
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "m5dbg-three-provider-\(UUID().uuidString)",
                isDirectory: true
            )
        socketURL = root.appendingPathComponent("usage.sock")
    }

    func connector(
        configurationCheck: @escaping ClaudeCodeUsageConnector.ConfigurationCheck = {
            ClaudeStatusLineConfigurationCheck(
                state: .installed,
                priorStatusLinePresent: false
            )
        }
    ) -> ClaudeCodeUsageConnector {
        ClaudeCodeUsageConnector(
            socketURL: socketURL,
            configurationCheck: configurationCheck,
            now: { self.now }
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
                    resetsAtEpochSeconds: 1_900_010_000
                )
            },
            sevenDay: try sevenDayUsed.map {
                try ClaudeStatusLineWindowPacket(
                    usedPercentage: $0,
                    resetsAtEpochSeconds: 1_900_020_000
                )
            },
            observedAt: now
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
