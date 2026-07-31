import ClaudeStatusLineCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5-G3 Claude live acceptance contracts")
struct M5G3ClaudeLiveAcceptanceTests {
    @Test
    func disableAfterLiveAdmissionWithdrawsClaudeImmediately() async throws {
        let fixture = G3ConnectorFixture()
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        let registry = try AgentConnectorRegistry(connectors: [connector])

        await registry.startPassiveConnectors()
        _ = await registry.scanSurfaceAdmissions(trigger: .manualRefresh)
        #expect(await registry.orderedSnapshots().isEmpty)

        await connector.receiveEncodedPacket(
            try fixture.packet(
                fiveHourUsed: 24.5,
                sevenDayUsed: 61
            ).encoded()
        )
        for _ in 0..<100
        where (await registry.orderedSnapshots()).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            await registry.orderedSnapshots().map(\.id)
                == [ClaudeCodeUsageConnector.connectorID]
        )

        await fixture.configuration.set(
            .ready(priorStatusLinePresent: false)
        )
        await connector.perform(.disconnect)
        for _ in 0..<100
        where !(await registry.orderedSnapshots()).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await registry.orderedSnapshots().isEmpty)
        #expect(await connector.lifecycleState() == .notInstalled)
        let stopped = await connector.currentSnapshot()
        #expect(stopped.state == .inactive)
        #expect(stopped.channels.isEmpty)
        #expect((await connector.diagnostics()).listenerCount == 0)
        await registry.stopAll()
    }

    @Test
    func deterministicMatrixKeepsWindowsIndependentAndConvertsOnce()
    async throws {
        let fixture = G3ConnectorFixture()
        defer { fixture.cleanup() }
        let connector = fixture.connector()

        for expected in [
            (five: 20.5 as Double?, seven: nil as Double?),
            (five: nil as Double?, seven: 70.25 as Double?),
            (five: 20.5 as Double?, seven: 70.25 as Double?),
        ] {
            await connector.receiveEncodedPacket(
                try fixture.packet(
                    fiveHourUsed: expected.five,
                    sevenDayUsed: expected.seven
                ).encoded()
            )
            let snapshot = await connector.currentSnapshot()
            #expect(snapshot.state == .ready)
            let windows = snapshot.channels[0].rateLimitWindows
            #expect(
                windows.first(where: { $0.kind == .fiveHour })?.usedPercent
                    == expected.five
            )
            #expect(
                windows.first(where: { $0.kind == .sevenDay })?.usedPercent
                    == expected.seven
            )
            let card = SharedUsagePresentationPolicy.makeCard(
                snapshot: snapshot,
                previous: nil,
                language: .english,
                now: fixture.clock.now
            )
            if let five = expected.five {
                #expect(
                    card.windows.first(where: {
                        $0.kind == .fiveHour
                    })?.remaining == .finite(100 - five)
                )
            }
            if let seven = expected.seven {
                #expect(
                    card.windows.first(where: {
                        $0.kind == .sevenDay
                    })?.remaining == .finite(100 - seven)
                )
            }
        }
    }

    @Test
    func malformedFailureRecoversWithoutAnotherListener() async throws {
        let fixture = G3ConnectorFixture()
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.start()

        await connector.receiveEncodedPacket(Data("{".utf8))
        #expect((await connector.currentSnapshot()).state == .failed)
        #expect((await connector.diagnostics()).rejectedPackets == 1)

        await connector.receiveEncodedPacket(
            try fixture.packet(
                fiveHourUsed: 15,
                sevenDayUsed: nil
            ).encoded()
        )
        #expect((await connector.currentSnapshot()).state == .ready)
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.listenerCount == 1)
        #expect(diagnostics.acceptedPackets == 1)
        #expect(diagnostics.rejectedPackets == 1)
        await connector.stop()
    }

    @Test
    func providerOrderAndAssistantBoundaryRemainLocked() {
        let ids = [
            WorkBuddyAccountWebCreditsConnector.connectorID,
            ClaudeCodeUsageConnector.connectorID,
            CodexUsageConnector.connectorID,
        ].sorted(by: AgentProviderOrder.precedes)
        #expect(
            ids.map(\.rawValue)
                == [
                    "codex.local",
                    "claude.statusLine",
                    "workbuddy.accountWebCredits",
                ]
        )
        #expect(
            !ClaudeCodeUsageConnector.production().descriptor.capabilities
                .contains(.hiddenFromDesktopAssistant)
        )
    }

    @Test
    func g3PackagingPhasesAreExactAndPrivacyBounded() throws {
        let script = try source("script/package_uma_m5_g2.sh")
        for required in [
            "g3-preflight",
            "g3-final",
            "uma-m5-g3-preflight-${commit:0:12}",
            "uma-m5-g3-final-$commit",
            "UMA-M5-G3-Provenance.plist",
            "LIVE-VALIDATED-SETTINGS-RESTORED",
            "ClaudeStatusLineRelay",
            "codesign --verify --deep --strict",
        ] {
            #expect(script.contains(required))
        }
        for forbidden in [
            "settings.backup\" \"$output",
            "usage.sock\" \"$output",
            "git add .",
            "xattr -cr",
        ] {
            #expect(!script.contains(forbidden))
        }
    }

    @Test
    func liveAcceptanceRecordContainsClassificationsNotValues() throws {
        let record = try source(
            "source/UMA M5-G3 Live Acceptance.md"
        )
        for required in [
            "Five-hour window: present valid",
            "Five-hour reset: valid",
            "Seven-day window: present valid",
            "Seven-day reset: valid",
            "Used-to-remaining conversion: MATCH",
            "Codex → Claude Code → WorkBuddy",
            "Exact settings restore: PASS",
        ] {
            #expect(record.contains(required))
        }
        for forbidden in [
            "session_id",
            "prompt_id",
            "transcript_path",
            "account identity:",
            "prompt content:",
            "response content:",
            "raw JSON:",
            "original settings SHA-256:",
        ] {
            #expect(!record.contains(forbidden))
        }
        #expect(
            record.range(
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

private actor G3ConfigurationState {
    private var state: ClaudeStatusLineConfigurationState = .installed

    func check() -> ClaudeStatusLineConfigurationCheck {
        ClaudeStatusLineConfigurationCheck(
            state: state,
            priorStatusLinePresent: false
        )
    }

    func set(_ state: ClaudeStatusLineConfigurationState) {
        self.state = state
    }
}

private final class G3Clock: @unchecked Sendable {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
}

private final class G3ConnectorFixture: @unchecked Sendable {
    let root: URL
    let socketURL: URL
    let clock = G3Clock()
    let configuration = G3ConfigurationState()

    init() {
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "m5g3-live-\(UUID().uuidString)",
                isDirectory: true
            )
        socketURL = root.appendingPathComponent("usage.sock")
    }

    func connector() -> ClaudeCodeUsageConnector {
        let configuration = configuration
        let clock = clock
        return ClaudeCodeUsageConnector(
            socketURL: socketURL,
            configurationCheck: {
                await configuration.check()
            },
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
                    resetsAtEpochSeconds: 1_900_010_000
                )
            },
            sevenDay: try sevenDayUsed.map {
                try ClaudeStatusLineWindowPacket(
                    usedPercentage: $0,
                    resetsAtEpochSeconds: 1_900_020_000
                )
            },
            observedAt: clock.now
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
