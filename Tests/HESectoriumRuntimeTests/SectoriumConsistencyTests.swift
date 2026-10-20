import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

private final class ConsistencyFixtureMounts: SectoriumMountMetadataProviding {
    var records: [SectoriumMountMetadata]? = [
        .init(filesystemID: "1:2", mountPoint: "/fixture/dev", filesystemType: "apfs", flags: 0)]
    var calls = 0
    func observeMountMetadata() -> [SectoriumMountMetadata]? { calls += 1; return records }
}

private final class ConsistencyFixtureRunner: HESectoriumTimedCommandRunning {
    var disks: [String: Any] = ["AllDisksAndPartitions": [["DeviceIdentifier": "disk7",
        "Partitions": [["DeviceIdentifier": "disk7s1", "VolumeUUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "MountPoint": "/fixture/backing", "ReadOnlyVolume": false, "Size": 100]]]]]
    var images: [String: Any] = ["images": [["image-path": "/fixture/backing/dev.sparsebundle",
        "system-entities": [["dev-entry": "/dev/disk8s1", "mount-point": "/fixture/dev"]]]]]
    var calls: [[String]] = []
    var allowances: [TimeInterval] = []
    var malformed = false
    var failed = false
    var time: TimeInterval = 100
    var cost: TimeInterval = 0
    var onCommand: (() -> Void)?
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        Issue.record("Consistency probe must use the timed runner")
        return .init(exitCode: 1)
    }
    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        calls.append([executable] + arguments); allowances.append(timeout)
        time += min(cost, timeout)
        onCommand?()
        guard !failed, cost < timeout else { return .init(exitCode: 1) }
        if malformed { return .init(exitCode: 0, detail: "not a property list") }
        let value: [String: Any]
        switch [executable] + arguments {
        case ["/usr/sbin/diskutil", "list", "-plist"]: value = disks
        case ["/usr/bin/hdiutil", "info", "-plist"]: value = images
        default: Issue.record("Unexpected host command: \(executable) \(arguments)"); return .init(exitCode: 1)
        }
        let data = try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
    }
}

private final class ConsistencyFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sectorium-consistency-" + UUID().uuidString)
    let runner = ConsistencyFixtureRunner()
    let mounts = ConsistencyFixtureMounts()
    var paths: HESectoriumPaths { .init(root: root) }
    var probe: SectoriumConsistencyProbe {
        SectoriumConsistencyProbe(paths: paths, runner: runner, mounts: mounts, now: { self.runner.time })
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func write(_ data: Data, _ name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appendingPathComponent(name), options: .atomic)
    }
    func state(_ value: StoragePersistentState) throws {
        try write(JSONEncoder().encode(StoragePersistentStateCodable(state: value)), "state.json")
    }
    func profile() -> SectoriumDevelopmentProfile {
        .init(name: "DEV", deviceID: "physical:test", backingVolumeUUID: UUID(),
              backingMountPoint: "/fixture/backing", imagePath: "/fixture/backing/dev.sparsebundle",
              devVolumeName: "DEV", devMountPoint: "/fixture/dev", devUUID: UUID(),
              encrypted: false, caseSensitive: false, logicalCapacityBytes: 100)
    }
}

@Suite("Sectorium lightweight consistency")
struct SectoriumConsistencyTests {
    @Test func publicProbeIsFreshAndDoesNotCreateSupportDirectory() throws {
        let fixture = ConsistencyFixture()
        let service = HESectoriumService(paths: fixture.paths, runner: fixture.runner,
            sectoriumMountMetadataProvider: fixture.mounts)
        let first = try #require(service.observeSectoriumConsistency())
        #expect(service.observeSectoriumConsistency() == first)
        #expect(fixture.runner.calls == [
            ["/usr/sbin/diskutil", "list", "-plist"], ["/usr/bin/hdiutil", "info", "-plist"],
            ["/usr/sbin/diskutil", "list", "-plist"], ["/usr/bin/hdiutil", "info", "-plist"]])
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
        fixture.runner.failed = true
        #expect(service.observeSectoriumConsistency() == nil)
    }

    @Test func unchangedPathReadonlyRemountIsDetectedFromMountFlags() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        let first = try #require(probe.observe())
        fixture.mounts.records = [.init(filesystemID: "1:2", mountPoint: "/fixture/dev", filesystemType: "apfs", flags: 1)]
        let readonly = try #require(probe.observe()); #expect(readonly != first)
        #expect(probe.observe() == readonly)
        #expect(fixture.runner.calls.count == 6 && fixture.mounts.calls == 6)
        fixture.mounts.records = nil
        #expect(probe.observe() == nil)
        #expect(fixture.runner.calls.count == 6)
    }

    @Test func mountTableChangesDuringProbeReturnUnknownAndOrderAloneDoesNot() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        let other = SectoriumMountMetadata(filesystemID: "2:3", mountPoint: "/fixture/other", filesystemType: "apfs", flags: 0)
        fixture.mounts.records?.append(other)
        let first = try #require(probe.observe())
        fixture.mounts.records?.reverse()
        #expect(probe.observe() == first)
        fixture.runner.onCommand = { fixture.mounts.records = [other] }
        #expect(probe.observe() == nil)
    }

    @Test func mountIdentityReadonlyAndAttachmentChangesInvalidate() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        let first = try #require(probe.observe())
        fixture.runner.disks = ["AllDisksAndPartitions": [["DeviceIdentifier": "disk7",
            "Partitions": [["DeviceIdentifier": "disk7s1", "MountPoint": "/fixture/moved"]]]]]
        let moved = try #require(probe.observe()); #expect(moved != first)
        fixture.runner.disks = ["AllDisksAndPartitions": [["DeviceIdentifier": "disk7",
            "Partitions": [["DeviceIdentifier": "disk7s1", "MountPoint": "/fixture/moved", "ReadOnlyVolume": true]]]]]
        let readonly = try #require(probe.observe()); #expect(readonly != moved)
        fixture.runner.disks = ["AllDisksAndPartitions": [["DeviceIdentifier": "disk9"]]]
        let replaced = try #require(probe.observe()); #expect(replaced != readonly)
        fixture.runner.images = ["images": []]
        #expect(try #require(probe.observe()) != replaced)
        fixture.runner.disks = ["AllDisksAndPartitions": []]
        #expect(probe.observe() != nil)
    }

    @Test func orderingAndUnrelatedCapacityOrImageTimestampDoNotInvalidate() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        let a: [String: Any] = ["DeviceIdentifier": "disk1", "MountPoint": "/fixture/a"]
        let b: [String: Any] = ["MountPoint": "/fixture/b", "DeviceIdentifier": "disk2"]
        fixture.runner.disks = ["AllDisksAndPartitions": [a, b]]
        let first = try #require(probe.observe())
        fixture.runner.disks = ["AllDisksAndPartitions": [b.merging(["FreeSpace": 12, "Size": 999]) { _, new in new }, a]]
        fixture.runner.images["timestamp"] = Date()
        #expect(probe.observe() == first)
    }

    @Test func registryChangesAndDeletionInvalidateButObservationDatesDoNot() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        let absent = try #require(probe.observe())
        var profile = fixture.profile()
        try fixture.write(JSONEncoder().encode([profile]), "sectorium-profiles.json")
        let registered = try #require(probe.observe()); #expect(registered != absent)
        profile.createdAt = Date(); profile.modifiedAt = Date(); profile.lastVerifiedLoadedAt = Date()
        try fixture.write(JSONEncoder().encode([profile]), "sectorium-profiles.json")
        #expect(probe.observe() == registered)
        profile.autoLoad.toggle()
        try fixture.write(JSONEncoder().encode([profile]), "sectorium-profiles.json")
        #expect(try #require(probe.observe()) != registered)
        try fixture.write(Data("[]".utf8), "sectorium-profiles.json")
        let empty = try #require(probe.observe()); #expect(empty != registered && empty != absent)
        try FileManager.default.removeItem(at: fixture.paths.sectoriumProfiles)
        #expect(probe.observe() == absent)
    }

    @Test func recoveryAndOperationChangesInvalidateButRevisionAndDocumentsDoNot() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        try fixture.state(.init(revision: 1, ejectIntent: false))
        let first = try #require(probe.observe())
        try fixture.state(.init(revision: 99, ejectIntent: false))
        try fixture.write(Data("not even parsed".utf8), "sectorium-document-journal.json")
        try fixture.write(Data("private document text".utf8), "IMPORTANT.md")
        #expect(probe.observe() == first)
        try fixture.state(.init(ejectIntent: true, operationID: "operation"))
        let pending = try #require(probe.observe()); #expect(pending != first)
        try fixture.state(.init(ejectIntent: true, operationID: "operation", workbenchPhase: "detaching"))
        #expect(try #require(probe.observe()) != pending)
        try fixture.state(.init(ejectIntent: false, suppressedProfileIDs: ["profile"]))
        #expect(try #require(probe.observe()) != first)
    }

    @Test func invalidInputsAreUnknownAndNeverAnAuthoritativeEmptyStamp() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        fixture.runner.malformed = true; #expect(probe.observe() == nil)
        fixture.runner.malformed = false; fixture.runner.disks = [:]; #expect(probe.observe() == nil)
        fixture.runner.disks = ["AllDisksAndPartitions": []]
        try fixture.write(Data("{".utf8), "sectorium-profiles.json")
        #expect(probe.observe() == nil)
        try fixture.write(Data("[]".utf8), "sectorium-profiles.json")
        try fixture.write(Data("{}".utf8), "state.json")
        #expect(probe.observe() == nil)
        try FileManager.default.removeItem(at: fixture.paths.state)
        let duplicate = fixture.profile()
        try fixture.write(JSONEncoder().encode([duplicate, duplicate]), "sectorium-profiles.json")
        #expect(probe.observe() == nil)
    }

    @Test func identityConfigurationChangesInvalidateWithoutReadingItsExternalPaths() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        let absent = try #require(probe.observe())
        var identity = ["outerUUID": UUID().uuidString, "devUUID": UUID().uuidString,
            "outerMountPoint": "/fixture/backing", "devMountPoint": "/fixture/dev",
            "devVolumeName": "DEV", "imagePath": "/fixture/backing/dev.sparsebundle"]
        try fixture.write(JSONSerialization.data(withJSONObject: identity), "storage-identity.json")
        let configured = try #require(probe.observe()); #expect(configured != absent)
        identity["imagePath"] = "/fixture/backing/other.sparsebundle"
        try fixture.write(JSONSerialization.data(withJSONObject: identity), "storage-identity.json")
        #expect(try #require(probe.observe()) != configured)
        #expect(fixture.runner.calls.count == 6)
    }

    @Test func unsafeAndOversizeManagedFilesAreUnknown() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        try fixture.write(Data("[]".utf8), "other.json")
        try FileManager.default.createSymbolicLink(at: fixture.paths.sectoriumProfiles,
                                                   withDestinationURL: fixture.root.appendingPathComponent("other.json"))
        #expect(probe.observe() == nil)
        try FileManager.default.removeItem(at: fixture.paths.sectoriumProfiles)
        try fixture.write(Data(repeating: 32, count: 1_048_577), "sectorium-profiles.json")
        #expect(probe.observe() == nil)
        #expect(fixture.runner.calls.isEmpty)
    }

    @Test func changesDuringProbeReturnUnknownAndEachRoundHasNewBudget() throws {
        let fixture = ConsistencyFixture(); let probe = fixture.probe
        fixture.runner.onCommand = { try? fixture.state(.init(ejectIntent: true)) }
        #expect(probe.observe() == nil)
        fixture.runner.onCommand = nil
        fixture.runner.cost = 2
        #expect(probe.observe() == nil)
        #expect(Array(fixture.runner.allowances.suffix(2)) == [3, 1])
        fixture.runner.cost = 0
        #expect(probe.observe() != nil)
        #expect(Array(fixture.runner.allowances.suffix(2)) == [3, 3])
    }
}
