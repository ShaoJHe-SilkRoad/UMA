import Foundation
import Testing
@testable import CodexUsageUI

struct UMA014M5CPrivacyProjectionTests {
    private static let sentinel = "synthetic-private-sentinel"

    @Test(arguments: [0, 1])
    func snapshotBackupProjectsEverySupportedLayer(schema: Int) async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("snapshot.json")
        let store = AgentConnectorSnapshotStore(url: url)
        let snapshot = Self.snapshot()
        try await store.save([snapshot])
        var object = try dictionary(Data(contentsOf: url))
        object["schemaVersion"] = schema
        object["prompt"] = Self.sentinel
        var entries = try #require(object["entries"] as? [[String: Any]])
        entries[0]["response"] = Self.sentinel
        var channels = try #require(entries[0]["channels"] as? [[String: Any]])
        channels[0]["cookie"] = Self.sentinel
        var windows = try #require(channels[0]["windows"] as? [[String: Any]])
        windows[0]["credential"] = Self.sentinel
        channels[0]["windows"] = windows
        entries[0]["channels"] = channels
        object["entries"] = entries
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        try await store.save([snapshot])
        for target in [url, url.appendingPathExtension("backup")] {
            #expect(!String(decoding: try Data(contentsOf: target), as: UTF8.self).contains(Self.sentinel))
        }
        let backup = try dictionary(Data(contentsOf: url.appendingPathExtension("backup")))
        #expect(backup["schemaVersion"] as? Int == schema)
        try Data("corrupt".utf8).write(to: url)
        let restored = try #require(await store.load().first)
        #expect(restored.channels.first?.rateLimitWindows.first?.remainingPercent == 82)
        #expect(restored.capturedAt == snapshot.capturedAt)
    }

    @Test(arguments: [false, true])
    func ledgerBackupAndRecoveryProjectUnknownFields(recovery: Bool) throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ledger.json")
        let backup = url.appendingPathExtension("backup")
        let store = APICostLedgerStore(url: url)
        let ledger = Self.ledger()
        try store.save(ledger)
        var object = try dictionary(Data(contentsOf: url))
        object["prompt"] = Self.sentinel
        var records = try #require(object["records"] as? [[String: Any]])
        records[0]["billingBody"] = Self.sentinel
        object["records"] = records
        var checkpoints = try #require(object["checkpoints"] as? [String: [String: Any]])
        checkpoints["fixture-session"]?["credential"] = Self.sentinel
        object["checkpoints"] = checkpoints
        let injected = try JSONSerialization.data(withJSONObject: object)
        if recovery {
            try injected.write(to: backup)
            try Data("corrupt".utf8).write(to: url)
            let restored = try store.load()
            #expect(restored.records.first?.counts.totalTokens == 120)
            #expect(restored.records.first?.sessionID == "fixture-session")
            #expect(restored.records.first?.usd == ledger.records.first?.usd)
            #expect(restored.records.first?.price == ledger.records.first?.price)
            #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains(Self.sentinel))
            // Recovery does not mutate the existing backup; only newly written bytes are projected.
            #expect(try Data(contentsOf: backup) == injected)
        } else {
            try injected.write(to: url)
            try store.save(ledger)
            for target in [url, backup] {
                #expect(!String(decoding: try Data(contentsOf: target), as: UTF8.self).contains(Self.sentinel))
            }
            #expect(try store.load().records.first?.counts.totalTokens == 120)
            #expect(try store.load().records.first?.usd == ledger.records.first?.usd)
            #expect(try store.load().records.first?.price == ledger.records.first?.price)
        }
    }

    @Test(arguments: [false, true])
    func futureLedgerMainAndBackupAreNeverDowngraded(futureIsBackup: Bool) throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ledger.json")
        let backup = url.appendingPathExtension("backup")
        let store = APICostLedgerStore(url: url)
        let ledger = Self.ledger()
        try store.save(ledger)
        let valid = try Data(contentsOf: url)
        var object = try dictionary(valid)
        object["schemaVersion"] = 999
        object["futureRepresentation"] = ["preserve": true]
        let future = try JSONSerialization.data(withJSONObject: object)
        try (futureIsBackup ? valid : future).write(to: url)
        try (futureIsBackup ? future : valid).write(to: backup)
        #expect(throws: APICostLedgerStore.StoreError.unsupportedSchema) { try store.save(ledger) }
        if !futureIsBackup {
            #expect(throws: APICostLedgerStore.StoreError.unsupportedSchema) { try store.load() }
        }
        #expect(try Data(contentsOf: url) == (futureIsBackup ? valid : future))
        #expect(try Data(contentsOf: backup) == (futureIsBackup ? future : valid))
        if futureIsBackup {
            let corrupt = Data("corrupt".utf8)
            try corrupt.write(to: url)
            #expect(throws: APICostLedgerStore.StoreError.unsupportedSchema) { try store.load() }
            #expect(try Data(contentsOf: url) == corrupt)
            #expect(try Data(contentsOf: backup) == future)
        }
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-m5c-projection-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func ledger() -> APICostLedger {
        var ledger = APICostLedger()
        ledger.observe(sessionID: "fixture-session", summary: SessionTokenSummary(
            model: "fixture-model", inputTokens: 100, cachedInputTokens: 0,
            outputTokens: 20, totalTokens: 120
        ), initialUsageDay: "2026-09-04", incrementalUsageDay: "2026-09-04", price: APIModelPrice(
            version: "fixture", displayName: "Fixture", inputPerMillion: 1,
            cachedInputPerMillion: 0.1, outputPerMillion: 2
        ))
        return ledger
    }

    private static func snapshot() -> AgentUsageSnapshot {
        let date = Date(timeIntervalSince1970: 1_784_332_800)
        return AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: "codex.local")!, providerName: "Codex",
            state: .ready, capturedAt: date, lastSuccessfulAt: date, freshness: .fresh,
            channels: [AgentUsageChannel(
                id: .account, sourceTier: .officialLocalService, sourceVersion: "app-server",
                scopes: [.account], provenance: .providerReported, freshness: .fresh,
                capturedAt: date, coverageNote: nil,
                rateLimitWindows: [.init(id: "five-hour", kind: .fiveHour, usedPercent: nil,
                    remainingPercent: 82, isUnlimited: false, resetsAt: nil)],
                accountMetrics: nil, localActivityMetrics: nil, safeFailure: nil
            )], capabilities: [.connect, .refresh, .disconnect], safeFailure: nil
        )
    }
}
