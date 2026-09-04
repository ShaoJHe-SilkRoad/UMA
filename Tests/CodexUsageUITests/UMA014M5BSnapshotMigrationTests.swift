import Foundation
import Testing
@testable import CodexUsageUI

struct UMA014M5BSnapshotMigrationTests {
    @Test(arguments: ["save", "replace", "remove"])
    func futureMainAndBackupSurviveRoutineMutations(operation: String) async throws {
        let root = try Self.fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // The entries shape deliberately cannot decode using today's model.
        let future = Data(#"{"schemaVersion":2,"entries":{"newRepresentation":true}}"#.utf8)
        for futureIsMain in [true, false] {
            let url = root.appendingPathComponent(futureIsMain ? "future-main.json" : "future-backup.json")
            let backup = url.appendingPathExtension("backup")
            let store = AgentConnectorSnapshotStore(url: url)
            try await store.save([Self.snapshot()])
            let supported = try Data(contentsOf: url)
            try (futureIsMain ? future : supported).write(to: url)
            try (futureIsMain ? supported : future).write(to: backup)
            let originalMain = try Data(contentsOf: url)
            let originalBackup = try Data(contentsOf: backup)

            #expect(await store.load().first?.state == .stale)
            await #expect(throws: AgentConnectorSnapshotStore.StoreError.rejected) {
                try await Self.mutate(store, operation: operation)
            }
            #expect(try Data(contentsOf: url) == originalMain)
            #expect(try Data(contentsOf: backup) == originalBackup)
        }
    }

    @Test(arguments: ["corrupt", "duplicate", "invalid-percent"])
    func invalidMainCannotPolluteValidRecoveryBackup(kind: String) async throws {
        let root = try Self.fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("snapshot.json")
        let backup = url.appendingPathExtension("backup")
        let store = AgentConnectorSnapshotStore(url: url)
        try await store.save([Self.snapshot()])
        let valid = try Data(contentsOf: url)
        try valid.write(to: backup)
        var object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var entries = try #require(object["entries"] as? [[String: Any]])
        if kind == "duplicate" {
            entries.append(entries[0])
        } else if kind == "invalid-percent" {
            var channels = try #require(entries[0]["channels"] as? [[String: Any]])
            var windows = try #require(channels[0]["windows"] as? [[String: Any]])
            windows[0]["remainingPercent"] = 101
            channels[0]["windows"] = windows
            entries[0]["channels"] = channels
        }
        object["entries"] = entries
        let rejected = kind == "corrupt" ? Data("invalid json".utf8) : try JSONSerialization.data(withJSONObject: object)
        try rejected.write(to: url)
        #expect(await store.load().first?.channels.first?.rateLimitWindows.first?.remainingPercent == 82)

        try await store.replace(with: [Self.snapshot(remaining: 70)])
        #expect(try Data(contentsOf: backup) == valid)
        #expect(await store.load().first?.channels.first?.rateLimitWindows.first?.remainingPercent == 70)
        try Data("broken after recovery".utf8).write(to: url)
        #expect(await store.load().first?.channels.first?.rateLimitWindows.first?.remainingPercent == 82)
    }

    @Test
    func legacyMigrationAndRemovalRetainSupportedRollbackShape() async throws {
        let root = try Self.fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("snapshot.json")
        let store = AgentConnectorSnapshotStore(url: url)
        let original = Self.snapshot()
        try await store.save([original])
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["schemaVersion"] = 0
        let legacy = try JSONSerialization.data(withJSONObject: object)
        try legacy.write(to: url)

        let restored = try #require(await store.load().first)
        #expect(restored.state == .stale)
        #expect(restored.channels.first?.freshness == .stale)
        #expect(restored.capturedAt == original.capturedAt)
        #expect(restored.lastSuccessfulAt == original.lastSuccessfulAt)
        #expect(try Data(contentsOf: url) == legacy)
        try await store.save([original])
        #expect(try Data(contentsOf: url.appendingPathExtension("backup")) == legacy)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let migrated = try decoder.decode(AgentConnectorSnapshotStore.Envelope.self, from: Data(contentsOf: url))
        #expect(migrated.schemaVersion == 1)
        #expect(migrated.entries.first?.id == original.id)
        let supported = try Data(contentsOf: url)
        try await store.remove(original.id)
        #expect(await store.load().isEmpty)
        #expect(try Data(contentsOf: url.appendingPathExtension("backup")) == supported)
    }

    @Test(arguments: ["leaf", "ancestor", "backup", "dangling"])
    func symlinkBoundariesRejectReadsMutationsAndClear(kind: String) async throws {
        let root = try Self.fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let inside = root.appendingPathComponent("inside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: false)
        let target = outside.appendingPathComponent("snapshot.json")
        let targetStore = AgentConnectorSnapshotStore(url: target)
        try await targetStore.save([Self.snapshot()])
        let sentinel = try Data(contentsOf: target)
        let outsideBackup = target.appendingPathExtension("backup")
        try sentinel.write(to: outsideBackup)
        var url = inside.appendingPathComponent("snapshot.json")
        if kind == "ancestor" {
            let link = inside.appendingPathComponent("linked")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            url = link.appendingPathComponent("snapshot.json")
        } else if kind == "backup" {
            try sentinel.write(to: url)
            try FileManager.default.createSymbolicLink(at: url.appendingPathExtension("backup"), withDestinationURL: target)
        } else {
            let destination = kind == "dangling" ? outside.appendingPathComponent("missing.json") : target
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
        }
        let store = AgentConnectorSnapshotStore(url: url)
        #expect(await store.load().isEmpty)
        for operation in ["save", "replace", "remove", "clear"] {
            await #expect(throws: AgentConnectorSnapshotStore.StoreError.rejected) {
                try await Self.mutate(store, operation: operation)
            }
            #expect(try Data(contentsOf: target) == sentinel)
            #expect(try Data(contentsOf: outsideBackup) == sentinel)
            #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("missing.json").path))
        }
        if kind == "backup" { #expect(try Data(contentsOf: url) == sentinel) }
    }

    @Test
    func oversizedMainAndBackupArePreserved() async throws {
        let root = try Self.fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let large = Data(repeating: 32, count: AgentConnectorSnapshotStore.maximumEncodedBytes + 1)
        for oversizedIsMain in [true, false] {
            let url = root.appendingPathComponent(oversizedIsMain ? "main.json" : "backup.json")
            let store = AgentConnectorSnapshotStore(url: url)
            try await store.save([Self.snapshot()])
            let largeURL = oversizedIsMain ? url : url.appendingPathExtension("backup")
            try large.write(to: largeURL)
            await #expect(throws: AgentConnectorSnapshotStore.StoreError.oversized) {
                try await store.replace(with: [])
            }
            #expect(try Data(contentsOf: largeURL) == large)
        }
    }

    private static func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-m5b-snapshot-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func mutate(_ store: AgentConnectorSnapshotStore, operation: String) async throws {
        switch operation {
        case "save": try await store.save([snapshot(remaining: 70)])
        case "replace": try await store.replace(with: [])
        case "remove": try await store.remove(snapshot().id)
        case "clear": try await store.clear()
        default: Issue.record("Unknown mutation fixture")
        }
    }

    private static func snapshot(remaining: Double = 82) -> AgentUsageSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_784_332_800)
        return AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: "codex.local")!,
            providerName: "Codex", state: .ready, capturedAt: capturedAt,
            lastSuccessfulAt: capturedAt, freshness: .fresh,
            channels: [AgentUsageChannel(
                id: .account, sourceTier: .officialLocalService, sourceVersion: "app-server",
                scopes: [.account], provenance: .providerReported, freshness: .fresh,
                capturedAt: capturedAt, coverageNote: nil,
                rateLimitWindows: [.init(id: "five-hour", kind: .fiveHour, usedPercent: nil,
                    remainingPercent: remaining, isUnlimited: false, resetsAt: nil)],
                accountMetrics: nil, localActivityMetrics: nil, safeFailure: nil
            )],
            capabilities: [.connect, .refresh, .disconnect], safeFailure: nil
        )
    }
}
