import ClaudeStatusLineCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5DBG-N1 Claude sanitized startup snapshot")
struct M5DBGN1ClaudeSnapshotTests {
    @Test
    func validEventsAtomicallyReplaceOneRemainingOnlyOwnerRecord() async throws {
        let fixture = N1Fixture()
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.receiveEncodedPacket(
            try fixture.packet(fiveHourUsed: 36.25, sevenDayUsed: 1).encoded()
        )

        let cacheURL = await fixture.store.claudeSnapshotURL
        let first = try Data(contentsOf: cacheURL)
        let firstObject = try #require(
            JSONSerialization.jsonObject(with: first) as? [String: Any]
        )
        #expect(firstObject["schemaVersion"] as? Int == 1)
        #expect(firstObject["sourceIdentifier"] as? String == "claude.statusLine")
        #expect(firstObject["fiveHourRemainingPercent"] as? Double == 63.75)
        #expect(firstObject["sevenDayRemainingPercent"] as? Double == 99)
        #expect(firstObject["fiveHourResetEpoch"] as? Int64 == fixture.fiveReset)
        #expect(firstObject["sevenDayResetEpoch"] as? Int64 == fixture.sevenReset)
        #expect(firstObject["selectedWindowIdentifier"] as? String == "claude-five-hour")
        #expect(Set(firstObject.keys).isSubset(of: Self.allowedKeys))
        let firstText = try #require(String(data: first, encoding: .utf8))
        for forbidden in Self.forbiddenPersistenceTokens {
            #expect(!firstText.localizedCaseInsensitiveContains(forbidden))
        }

        await connector.receiveEncodedPacket(
            try fixture.packet(fiveHourUsed: 40, sevenDayUsed: 2).encoded()
        )
        let second = try Data(contentsOf: cacheURL)
        #expect(second != first)
        let secondObject = try #require(
            JSONSerialization.jsonObject(with: second) as? [String: Any]
        )
        #expect(secondObject["fiveHourRemainingPercent"] as? Double == 60)
        #expect(secondObject["sevenDayRemainingPercent"] as? Double == 98)

        let entries = try FileManager.default.contentsOfDirectory(
            atPath: fixture.root.path
        )
        #expect(entries == ["claude-last-valid-quota.json"])
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: cacheURL.path
        )
        #expect(
            (fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600
        )
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: fixture.root.path
        )
        #expect(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
                == 0o700
        )
        #expect(
            try cacheURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        )
    }

    @Test
    func relaunchRestoresCachedWithoutProviderReadThenTransitionsFresh() async throws {
        let fixture = N1Fixture()
        defer { fixture.cleanup() }
        let first = fixture.connector()
        await first.receiveEncodedPacket(
            try fixture.packet(fiveHourUsed: 95, sevenDayUsed: 20).encoded()
        )
        let original = await first.currentSnapshot()
        #expect(original.selectedWindowID == "claude-five-hour")

        let relaunched = fixture.connector()
        let probe = await relaunched.probe()
        let cached = await relaunched.currentSnapshot()
        let diagnostics = await relaunched.diagnostics()
        #expect(probe.state == .ready)
        #expect(cached.freshness == .cached)
        #expect(await relaunched.lifecycleState() == .cached)
        #expect(diagnostics.acceptedPackets == 0)
        #expect(diagnostics.restoredSnapshots == 1)
        #expect(cached.selectedWindowID == original.selectedWindowID)
        #expect(cached.channels[0].rateLimitWindows.allSatisfy {
            $0.usedPercent == nil && $0.remainingPercent != nil
        })
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: cached,
            previous: nil,
            language: .english,
            now: fixture.clock.now
        )
        #expect(card.freshness == .cached)
        #expect(card.severity == .neutral)
        #expect(card.isRetainingLastValidValue)
        #expect(card.selectedWindowID == "claude-five-hour")
        #expect(card.remaining == .finite(5))
        #expect(card.tooltipText.contains("cached"))

        await relaunched.receiveEncodedPacket(
            try fixture.packet(fiveHourUsed: 94, sevenDayUsed: 21).encoded()
        )
        let fresh = await relaunched.currentSnapshot()
        #expect(fresh.freshness == .fresh)
        #expect(await relaunched.lifecycleState() == .fresh)
        #expect((await relaunched.diagnostics()).acceptedPackets == 1)
    }

    @Test
    func recentCacheAgesToStaleWithoutPromptOrProviderRead() async throws {
        let fixture = N1Fixture()
        defer { fixture.cleanup() }
        let first = fixture.connector()
        await first.receiveEncodedPacket(
            try fixture.packet(fiveHourUsed: 20, sevenDayUsed: 30).encoded()
        )
        fixture.clock.advance(
            by: ClaudeCodeUsageConnector.freshnessInterval + 1
        )
        let relaunched = fixture.connector()
        _ = await relaunched.probe()
        let stale = await relaunched.currentSnapshot()
        #expect(stale.state == .stale)
        #expect(stale.freshness == .stale)
        #expect(await relaunched.lifecycleState() == .stale)
        #expect((await relaunched.diagnostics()).acceptedPackets == 0)
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: stale,
            previous: nil,
            language: .english,
            now: fixture.clock.now
        )
        #expect(card.severity == .neutral)
        #expect(card.tooltipText.contains("stale"))
    }

    @Test
    func expiryPrunesEachWindowIndependentlyAndBothExpiredDelete() async throws {
        let fixture = N1Fixture()
        defer { fixture.cleanup() }
        let nowEpoch = Int64(fixture.clock.now.timeIntervalSince1970)

        try fixture.writeRawCache([
            "schemaVersion": 1,
            "sourceIdentifier": "claude.statusLine",
            "fiveHourRemainingPercent": 70,
            "fiveHourResetEpoch": nowEpoch,
            "sevenDayRemainingPercent": 80,
            "sevenDayResetEpoch": nowEpoch + 20,
            "selectedWindowIdentifier": "claude-five-hour",
            "observationTimestamp": fixture.clock.now.timeIntervalSince1970 * 1_000,
        ])
        let sevenOnly = try #require(
            await fixture.store.loadClaudeSanitizedSnapshot(now: fixture.clock.now)
        )
        #expect(sevenOnly.fiveHourRemainingPercent == nil)
        #expect(sevenOnly.sevenDayRemainingPercent == 80)
        #expect(sevenOnly.selectedWindowIdentifier == nil)

        try fixture.writeRawCache([
            "schemaVersion": 1,
            "sourceIdentifier": "claude.statusLine",
            "fiveHourRemainingPercent": 70,
            "fiveHourResetEpoch": nowEpoch + 20,
            "sevenDayRemainingPercent": 80,
            "sevenDayResetEpoch": nowEpoch,
            "selectedWindowIdentifier": "claude-five-hour",
            "observationTimestamp": fixture.clock.now.timeIntervalSince1970 * 1_000,
        ])
        let fiveOnly = try #require(
            await fixture.store.loadClaudeSanitizedSnapshot(now: fixture.clock.now)
        )
        #expect(fiveOnly.fiveHourRemainingPercent == 70)
        #expect(fiveOnly.sevenDayRemainingPercent == nil)

        try fixture.writeRawCache([
            "schemaVersion": 1,
            "sourceIdentifier": "claude.statusLine",
            "fiveHourRemainingPercent": 70,
            "sevenDayRemainingPercent": 80,
            "sevenDayResetEpoch": nowEpoch + 20,
            "observationTimestamp": fixture.clock.now.timeIntervalSince1970 * 1_000,
        ])
        let missingReset = try #require(
            await fixture.store.loadClaudeSanitizedSnapshot(now: fixture.clock.now)
        )
        #expect(missingReset.fiveHourRemainingPercent == nil)
        #expect(missingReset.sevenDayRemainingPercent == 80)

        try fixture.writeRawCache([
            "schemaVersion": 1,
            "sourceIdentifier": "claude.statusLine",
            "fiveHourRemainingPercent": 70,
            "fiveHourResetEpoch": "malformed",
            "sevenDayRemainingPercent": 80,
            "sevenDayResetEpoch": nowEpoch + 20,
            "observationTimestamp": fixture.clock.now.timeIntervalSince1970 * 1_000,
        ])
        let malformedReset = try #require(
            await fixture.store.loadClaudeSanitizedSnapshot(now: fixture.clock.now)
        )
        #expect(malformedReset.fiveHourRemainingPercent == nil)
        #expect(malformedReset.sevenDayRemainingPercent == 80)

        try fixture.writeRawCache([
            "schemaVersion": 1,
            "sourceIdentifier": "claude.statusLine",
            "fiveHourRemainingPercent": 70,
            "fiveHourResetEpoch": nowEpoch,
            "sevenDayRemainingPercent": 80,
            "sevenDayResetEpoch": nowEpoch - 1,
            "observationTimestamp": fixture.clock.now.timeIntervalSince1970 * 1_000,
        ])
        #expect(
            await fixture.store.loadClaudeSanitizedSnapshot(now: fixture.clock.now)
                == nil
        )
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheURL.path))
    }

    @Test
    func malformedOversizedUnknownAndFutureRecordsFailClosed() async throws {
        let fixture = N1Fixture()
        defer { fixture.cleanup() }
        let validBase: [String: Any] = [
            "schemaVersion": 1,
            "sourceIdentifier": "claude.statusLine",
            "fiveHourRemainingPercent": 70,
            "fiveHourResetEpoch": fixture.fiveReset,
            "observationTimestamp": fixture.clock.now.timeIntervalSince1970 * 1_000,
        ]
        var rejectedRecords: [[String: Any]] = []
        var unknown = validBase
        unknown["prompt"] = "private"
        rejectedRecords.append(unknown)
        var futureSchema = validBase
        futureSchema["schemaVersion"] = 2
        rejectedRecords.append(futureSchema)
        var booleanSchema = validBase
        booleanSchema["schemaVersion"] = true
        rejectedRecords.append(booleanSchema)
        var futureObservation = validBase
        futureObservation["observationTimestamp"] =
            (fixture.clock.now.timeIntervalSince1970 + 6) * 1_000
        rejectedRecords.append(futureObservation)

        for rejected in rejectedRecords {
            try fixture.writeRawCache(rejected)
            #expect(
                await fixture.store.loadClaudeSanitizedSnapshot(
                    now: fixture.clock.now
                ) == nil
            )
            #expect(!FileManager.default.fileExists(atPath: fixture.cacheURL.path))
        }

        try Data(repeating: 0x20, count: 4_097).write(
            to: fixture.cacheURL,
            options: .atomic
        )
        #expect(
            await fixture.store.loadClaudeSanitizedSnapshot(now: fixture.clock.now)
                == nil
        )
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheURL.path))
    }

    @Test
    func disableRepairAndOwnershipLossInvalidateTheSnapshot() async throws {
        for state in [
            ClaudeStatusLineConfigurationState.unconfigured,
            .ready(priorStatusLinePresent: false),
            .repairRequired,
            .unsupported,
            .failed,
        ] {
            let fixture = N1Fixture()
            defer { fixture.cleanup() }
            try await fixture.saveRecord(
                fiveRemaining: 70,
                fiveReset: fixture.fiveReset,
                sevenRemaining: nil,
                sevenReset: nil
            )
            let connector = fixture.connector(configuration: state)
            _ = await connector.probe()
            #expect(!FileManager.default.fileExists(atPath: fixture.cacheURL.path))
        }

        let fixture = N1Fixture()
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.receiveEncodedPacket(
            try fixture.packet(fiveHourUsed: 20, sevenDayUsed: nil).encoded()
        )
        #expect(FileManager.default.fileExists(atPath: fixture.cacheURL.path))
        await connector.perform(.disconnect)
        #expect(!FileManager.default.fileExists(atPath: fixture.cacheURL.path))
    }

    @Test
    func malformedNewEventRetainsCacheAndRestoreDoesNotCreateDecrementOrAlert()
    async throws {
        let fixture = N1Fixture()
        defer { fixture.cleanup() }
        let connector = fixture.connector()
        await connector.receiveEncodedPacket(
            try fixture.packet(fiveHourUsed: 100, sevenDayUsed: 30).encoded()
        )
        let before = try Data(contentsOf: fixture.cacheURL)
        await connector.receiveEncodedPacket(Data("{".utf8))
        #expect(try Data(contentsOf: fixture.cacheURL) == before)
        #expect((await connector.currentSnapshot()).freshness == .stale)

        let relaunched = fixture.connector()
        _ = await relaunched.probe()
        let cached = await relaunched.currentSnapshot()
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: cached,
            previous: nil,
            language: .english,
            now: fixture.clock.now
        )
        #expect(card.selectedWindowID == cached.selectedWindowID)
        #expect(card.remaining == .finite(0))
        #expect(card.severity == .neutral)
        #expect(card.isRetainingLastValidValue)

        await relaunched.receiveEncodedPacket(
            try fixture.packet(
                fiveHourUsed: 10,
                sevenDayUsed: 31,
                fiveReset: fixture.fiveReset + 500,
                sevenReset: fixture.sevenReset
            ).encoded()
        )
        let fresh = await relaunched.currentSnapshot()
        #expect(fresh.selectedWindowID == "claude-seven-day")
        #expect(fresh.freshness == .fresh)
    }

    @Test
    func copyRendererAndPackageContractsExposeCachedStateWithoutPrivateData()
    throws {
        let language = try source(
            "Sources/CodexUsageUI/Models/AppLanguage+Claude.swift"
        )
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let settings = try source(
            "Sources/CodexUsageUI/Views/UsageSettingsCard.swift"
        )
        let renderer = try source("Sources/PreviewRendererTool/main.swift")
        let package = try source("script/package_uma_m5_g2.sh")
        let combined = language + panel + settings
        #expect(combined.contains("Updates automatically the next time Claude Code is used."))
        #expect(combined.contains("Stored locally: Sanitized last-valid quota only"))
        #expect(renderer.contains("--claude-cached"))
        #expect(renderer.contains(".cached"))
        #expect(package.contains("claude-last-valid-quota.json"))
        #expect(package.contains("-iname '*.json'"))
        for forbidden in [
            "send a prompt to refresh",
            "submit a prompt to refresh",
            "raw status-line JSON",
        ] {
            #expect(!combined.localizedCaseInsensitiveContains(forbidden))
        }
    }

    private static let allowedKeys: Set<String> = [
        "schemaVersion",
        "sourceIdentifier",
        "fiveHourRemainingPercent",
        "fiveHourResetEpoch",
        "sevenDayRemainingPercent",
        "sevenDayResetEpoch",
        "selectedWindowIdentifier",
        "observationTimestamp",
        "sourceVersion",
    ]

    private static let forbiddenPersistenceTokens = [
        "usedPercentage", "session", "prompt", "transcript", "workspace",
        "repository", "branch", "worktree", "response", "task", "tool",
        "token", "accountIdentity", "credential", "authentication", "rawJSON",
    ]

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

private final class N1Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_900_000_000)

    var now: Date { lock.withLock { value } }

    func advance(by interval: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(interval) }
    }
}

private final class N1Fixture: @unchecked Sendable {
    let root: URL
    let socketURL: URL
    let store: AgentConnectorSnapshotStore
    let clock = N1Clock()
    let fiveReset: Int64 = 1_900_010_000
    let sevenReset: Int64 = 1_900_020_000

    init() {
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "m5dbg-n1-snapshot-\(UUID().uuidString)",
                isDirectory: true
            )
        socketURL = root.appendingPathComponent("usage.sock")
        store = AgentConnectorSnapshotStore(
            url: root.appendingPathComponent("connector-snapshots.json")
        )
    }

    var cacheURL: URL {
        root.appendingPathComponent("claude-last-valid-quota.json")
    }

    func connector(
        configuration: ClaudeStatusLineConfigurationState = .installed
    ) -> ClaudeCodeUsageConnector {
        let clock = self.clock
        return ClaudeCodeUsageConnector(
            socketURL: socketURL,
            configurationCheck: {
                ClaudeStatusLineConfigurationCheck(
                    state: configuration,
                    priorStatusLinePresent: false
                )
            },
            snapshotStore: store,
            now: { clock.now }
        )
    }

    func packet(
        fiveHourUsed: Double?,
        sevenDayUsed: Double?,
        fiveReset: Int64? = nil,
        sevenReset: Int64? = nil
    ) throws -> ClaudeStatusLinePacket {
        try ClaudeStatusLinePacket(
            claudeVersion: "synthetic-2.1.220",
            fiveHour: try fiveHourUsed.map {
                try ClaudeStatusLineWindowPacket(
                    usedPercentage: $0,
                    resetsAtEpochSeconds: fiveReset ?? self.fiveReset
                )
            },
            sevenDay: try sevenDayUsed.map {
                try ClaudeStatusLineWindowPacket(
                    usedPercentage: $0,
                    resetsAtEpochSeconds: sevenReset ?? self.sevenReset
                )
            },
            observedAt: clock.now
        )
    }

    func saveRecord(
        fiveRemaining: Double?,
        fiveReset: Int64?,
        sevenRemaining: Double?,
        sevenReset: Int64?
    ) async throws {
        try await store.saveClaudeSanitizedSnapshot(
            AgentConnectorSnapshotStore.ClaudeSanitizedQuotaSnapshot(
                fiveHourRemainingPercent: fiveRemaining,
                fiveHourResetEpoch: fiveReset,
                sevenDayRemainingPercent: sevenRemaining,
                sevenDayResetEpoch: sevenReset,
                selectedWindowIdentifier: "claude-five-hour",
                observationTimestamp: clock.now,
                sourceVersion: "synthetic-2.1.220"
            ),
            now: clock.now
        )
    }

    func writeRawCache(_ object: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ).write(to: cacheURL, options: .atomic)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
