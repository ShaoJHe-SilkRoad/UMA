import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

private final class V2MemoryFileSystem: SectoriumPortableDocumentFileSystem {
    var verified = true
    var writable = true
    var failCommit = false
    var verificationResults: [Bool] = []
    var files: [String: Data] = [:]
    var writes = 0
    func isVerifiedWritableHost(_ root: URL, volumeUUID: UUID) -> Bool {
        if !verificationResults.isEmpty { return verificationResults.removeFirst() }
        return verified && writable
    }
    func isVerifiedReadableHost(_ root: URL, volumeUUID: UUID) -> Bool { verified }
    func readRegularFile(_ url: URL, limit: Int) throws -> Data? {
        let data = files[url.path]
        guard (data?.count ?? 0) <= limit else { throw V2FixtureError.refused }
        return data
    }
    func commit(_ data: Data, to url: URL, expectedPrior: Data?) throws {
        guard !failCommit, files[url.path] == expectedPrior else { throw V2FixtureError.refused }
        files[url.path] = data; writes += 1
    }
}
private enum V2FixtureError: Error { case refused }
private final class V2FixtureRunner: HESectoriumCommandRunning {
    let root: URL
    init(root: URL) { self.root = root }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        guard executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", root.path], cwd == root else {
            return .init(exitCode: 127, detail: "fixture command refused")
        }
        let value: [String: Any] = ["MountPoint": root.path, "VolumeUUID": v2Host.uuidString, "WritableVolume": true]
        let data = try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
    }
}
private let v2Date = Date(timeIntervalSince1970: 1_760_000_000)
private let v2Host = UUID(uuidString: "7B305D23-CC44-4A54-96CA-344C984F83F0")!
private let v2Profile = "A71E1FC3-0E58-41C3-9F07-21EA7AF24208"
private let v2OtherProfile = "A71E1FC3-0E58-41C3-9F07-21EA7AF24209"
private func v2Volume(_ id: String = v2Profile, root: String = "/Volumes/FixtureHost") -> SectoriumPortableVolumeRecord {
    .init(profileID: id, name: id == v2Profile ? "Development" : "Second",
        volumeUUID: id == v2Profile ? UUID(uuidString: "79160516-FD8C-423F-B5BB-BE69A27B92C3") : nil,
        filesystem: id == v2Profile ? "APFS" : nil, logicalCapacityBytes: 100_000, allocatedBytes: 4096,
        imagePath: root + "/" + id + ".sparsebundle", mountPoint: root + "/mount-" + id,
        autoLoad: false, createdAt: v2Date, formatMethod: "Sparse disk image / 稀疏磁盘镜像")
}
private func v2Context(_ volumes: [SectoriumPortableVolumeRecord]? = nil) -> SectoriumPortableDocumentContext {
    .init(parent: .init(physicalID: "physical-fixture", name: "Fixture", physicalCapacityBytes: 1_000_000,
        documentVolumeUUID: v2Host, rootPath: "/Volumes/FixtureHost", filesystem: "ExFAT",
        totalBytes: 900_000, availableBytes: 800_000), volumes: volumes ?? [v2Volume()])
}
private func v2Event(_ id: String = "operation-1:completed", kind: String = "registered",
                     index: Int = 0, profileID: String = v2Profile,
                     before: SectoriumPortableVolumeRecord? = nil,
                     after: SectoriumPortableVolumeRecord? = nil) -> SectoriumPortableDocumentEvent {
    .init(id: id, occurredAt: v2Date.addingTimeInterval(Double(index)), profileID: profileID,
        kind: kind, before: before, after: after)
}
private let v2DocumentPath = "/Volumes/FixtureHost/IMPORTANT.md"
private func v2Text(_ fs: V2MemoryFileSystem) -> String { String(decoding: fs.files[v2DocumentPath] ?? Data(), as: UTF8.self) }
private func v2JournalRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sectorium-document-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root.resolvingSymlinksInPath()
}

@Suite struct SectoriumPortableDocumentV2Tests {
    @Test func aggregatesPhysicalParentAcrossBackingVolumesAndPreservesUnknownFacts() {
        let fs = V2MemoryFileSystem(); let writer = SectoriumPortableDocumentWriter(fileSystem: fs)
        let other = v2Volume(v2OtherProfile, root: "/Volumes/OtherBacking")
        let context = v2Context([v2Volume(), other])
        #expect(writer.update(context: context, events: [v2Event(after: v2Volume())]) == .updated)
        let text = v2Text(fs)
        #expect(text.contains("Physical identity / 物理身份: physical-fixture"))
        #expect(text.contains("1000000 bytes / 字节"))
        #expect(text.contains("/Volumes/OtherBacking"))
        #expect(text.contains("Filesystem / 文件系统: not verified / 未核实"))
        #expect(text.contains("镜像实际占用: 4096"))
        #expect(text.contains("不是未分区空间"))
        #expect(writer.verifiedDocumentURL(context: context)?.path == v2DocumentPath)
    }

    @Test func removesAnyAndLastRegisteredVolumeWhileRetainingHistory() {
        let fs = V2MemoryFileSystem(); let writer = SectoriumPortableDocumentWriter(fileSystem: fs)
        let a = v2Volume(); let b = v2Volume(v2OtherProfile)
        let created = v2Event(after: a)
        #expect(writer.update(context: v2Context([a, b]), events: [created]) == .updated)
        let removed = v2Event("remove-A:completed", kind: "removed", index: 1, before: a)
        #expect(writer.update(context: v2Context([b]), events: [removed]) == .updated)
        let last = v2Event("remove-B:completed", kind: "removed", index: 2, profileID: b.profileID, before: b)
        #expect(writer.update(context: v2Context([]), events: [last]) == .updated)
        #expect(writer.preservedHistory(context: v2Context([])) == [created, removed, last])
        #expect(v2Text(fs).contains("已无登记开发盘；历史保留"))
    }

    @Test func retainsLongHistoryAndStableEventsAreIdempotent() {
        let fs = V2MemoryFileSystem(); let writer = SectoriumPortableDocumentWriter(fileSystem: fs)
        let history = (0..<100).map { v2Event("operation-\($0):completed", index: $0, after: v2Volume()) }
        #expect(writer.update(context: v2Context(), events: history) == .updated)
        #expect((fs.files[v2DocumentPath]?.count ?? 0) > 65_536)
        #expect(writer.preservedHistory(context: v2Context())?.count == 100)
        let old = fs.files[v2DocumentPath]
        #expect(writer.update(context: v2Context(), events: history.reversed()) == .unchanged)
        #expect(fs.files[v2DocumentPath] == old)
        let conflicting = v2Event(history[0].id, kind: "loaded")
        guard case .pending = writer.update(context: v2Context(), events: [conflicting]) else { Issue.record("Conflicting immutable event accepted"); return }
        #expect(fs.files[v2DocumentPath] == old)
    }

    @Test func preservesExactNotesAndRejectsOutsideEdits() {
        let fs = V2MemoryFileSystem(); let writer = SectoriumPortableDocumentWriter(fileSystem: fs)
        #expect(writer.update(context: v2Context(), events: [v2Event()]) == .updated)
        let notes = "\n  My notes / 我的备注  \n\n"
        let edited = v2Text(fs).replacingOccurrences(of: "Add your own notes here. / 在此填写自己的备注。", with: notes)
        fs.files[v2DocumentPath] = Data(edited.utf8)
        var changed = v2Volume(); changed.mountPoint = "/Volumes/FixtureHost/NewMount"
        let event = v2Event("mount:completed", kind: "mountPointChanged", index: 1, before: v2Volume(), after: changed)
        #expect(writer.update(context: v2Context([changed]), events: [event]) == .updated)
        #expect(v2Text(fs).contains(notes))
        #expect(v2Text(fs).contains("Before / 之前:"))
        #expect(v2Text(fs).contains("/Volumes/FixtureHost/NewMount"))
        fs.files[v2DocumentPath] = Data((v2Text(fs) + "unmanaged text\n").utf8)
        let foreign = fs.files[v2DocumentPath]
        guard case .pending = writer.update(context: v2Context([changed]), events: [event]) else { Issue.record("User edit overwritten"); return }
        #expect(fs.files[v2DocumentPath] == foreign)
        #expect(writer.verifiedDocumentURL(context: v2Context([changed])) == nil)
    }

    @Test func disposableFilesystemReplacesDocumentsLargerThanLegacyLimitWithoutLosingPreimage() throws {
        let root = try v2JournalRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fs = SystemSectoriumPortableDocumentFileSystem(runner: V2FixtureRunner(root: root))
        let writer = SectoriumPortableDocumentWriter(fileSystem: fs)
        var context = v2Context([v2Volume(root: root.path)]); context.parent.rootPath = root.path
        let history = (0..<100).map { v2Event("large-\($0):completed", index: $0, after: context.volumes[0]) }
        #expect(writer.update(context: context, events: history) == .updated)
        let target = root.appendingPathComponent("IMPORTANT.md")
        let original = try Data(contentsOf: target)
        #expect(original.count > 65_536)
        #expect(writer.update(context: context, events: [v2Event("large-101:completed", index: 101)]) == .updated)
        #expect(writer.preservedHistory(context: context)?.count == 101)
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".IMPORTANT.md.auv-recovery-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == original)
    }

    @Test func readonlyParentCanOpenDocumentButCannotWriteAndIdentityChangesStopCommit() {
        let fs = V2MemoryFileSystem(); let writer = SectoriumPortableDocumentWriter(fileSystem: fs)
        #expect(writer.update(context: v2Context(), events: [v2Event()]) == .updated)
        fs.writable = false
        #expect(writer.verifiedDocumentURL(context: v2Context()) != nil)
        guard case .pending = writer.update(context: v2Context(), events: [v2Event("load:completed", kind: "loaded")]) else { Issue.record("Read-only write accepted"); return }
        fs.writable = true; fs.verificationResults = [true, false]
        let old = fs.files[v2DocumentPath]
        guard case .pending = writer.update(context: v2Context(), events: [v2Event("load:completed", kind: "loaded")]) else { Issue.record("Changed host accepted"); return }
        #expect(fs.files[v2DocumentPath] == old)
    }

    @Test func duplicateIdentityAndForeignDocumentArePreserved() {
        let fs = V2MemoryFileSystem(); let writer = SectoriumPortableDocumentWriter(fileSystem: fs)
        fs.files[v2DocumentPath] = Data("My own IMPORTANT.md\n".utf8)
        let original = fs.files[v2DocumentPath]
        guard case .pending = writer.update(context: v2Context(), events: [v2Event()]) else { Issue.record("Foreign file overwritten"); return }
        #expect(fs.files[v2DocumentPath] == original)
        guard case .pending = writer.update(context: v2Context([v2Volume(), v2Volume()]), events: []) else { Issue.record("Duplicate identity accepted"); return }
        #expect(fs.writes == 0)
    }

    @Test func journalRetainsOriginalFactsAcrossRestartAndRebuildsMissingDocument() throws {
        let root = try v2JournalRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sectorium-document-journal.json")
        let context = v2Context(); let event = v2Event(after: v2Volume())
        let fs = V2MemoryFileSystem(); fs.failCommit = true
        let writer = SectoriumPortableDocumentWriter(fileSystem: fs)
        let first = SectoriumPortableDocumentJournal(url: url)
        try first.record(context: context, event: event)
        guard case .pending = first.synchronize(context: context, writer: writer) else { Issue.record("Failed document unexpectedly synced"); return }
        let restarted = SectoriumPortableDocumentJournal(url: url)
        #expect(try restarted.pendingCount(parentID: context.parent.physicalID) == 1)
        #expect(try restarted.events(parentID: context.parent.physicalID) == [event])
        try restarted.record(context: context, event: event)
        fs.failCommit = false
        #expect(restarted.synchronize(context: context, writer: writer) == .updated)
        #expect(try restarted.pendingCount(parentID: context.parent.physicalID) == 0)
        #expect(try restarted.latestContext(parentID: context.parent.physicalID) == context)
        #expect(try restarted.latestContext(parentID: "unregistered-parent") == nil)
        let original = fs.files[v2DocumentPath]
        #expect(restarted.synchronize(context: context, writer: writer) == .unchanged)
        fs.files.removeValue(forKey: v2DocumentPath)
        #expect(restarted.synchronize(context: context, writer: writer) == .updated)
        #expect(fs.files[v2DocumentPath] == original)
        #expect(writer.preservedHistory(context: context) == [event])
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o600)
    }

    @Test func intendedAndCompletedEventsRemainDistinctAndFinalRemovalStaysDiscoverable() throws {
        let root = try v2JournalRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = SectoriumPortableDocumentJournal(url: root.appendingPathComponent("history.json"))
        let before = v2Volume()
        let intended = SectoriumPortableDocumentEvent(id: "remove:intended", occurredAt: v2Date,
            profileID: before.profileID, kind: "removed", phase: .intended, before: before)
        let completed = v2Event("remove:completed", kind: "removed", before: before)
        try journal.record(context: v2Context(), event: intended)
        try journal.record(context: v2Context([]), event: completed)
        #expect(try journal.pendingContexts() == [v2Context([])])
        #expect(try journal.events(parentID: v2Context().parent.physicalID) == [intended, completed])
        let fs = V2MemoryFileSystem(); let writer = SectoriumPortableDocumentWriter(fileSystem: fs)
        #expect(journal.synchronize(context: v2Context([]), writer: writer) == .updated)
        #expect(try journal.latestContext(parentID: v2Context().parent.physicalID) == v2Context([]))
        #expect(v2Text(fs).contains("Intended / 拟执行"))
        #expect(v2Text(fs).contains("Completed and verified / 已完成并核验"))
        #expect(writer.preservedHistory(context: v2Context([])) == [intended, completed])
    }

    @Test func journalRefusesConflictsMalformedBytesAndSymlinks() throws {
        let root = try v2JournalRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.json")
        let journal = SectoriumPortableDocumentJournal(url: url)
        try journal.record(context: v2Context(), event: v2Event())
        let original = try Data(contentsOf: url)
        #expect(throws: SectoriumPortableDocumentJournalError.conflictingEvent) {
            try journal.record(context: v2Context(), event: v2Event(kind: "loaded"))
        }
        #expect(try Data(contentsOf: url) == original)
        let malformed = Data("{bad-json}".utf8); try malformed.write(to: url)
        #expect(throws: SectoriumPortableDocumentJournalError.unreadableJournal) {
            try journal.record(context: v2Context(), event: v2Event("new"))
        }
        #expect(try Data(contentsOf: url) == malformed)
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        #expect(throws: SectoriumPortableDocumentJournalError.unsafePath) {
            try SectoriumPortableDocumentJournal(url: link).record(context: v2Context(), event: v2Event())
        }
        #expect(try Data(contentsOf: url) == malformed)
    }

    @Test func migrationPersistsLegacyHistoryAndNotesBeforeRebuilding() throws {
        let root = try v2JournalRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fs = V2MemoryFileSystem(); let writer = SectoriumPortableDocumentWriter(fileSystem: fs, now: { v2Date })
        let profile = SectoriumDevelopmentProfile(id: v2Profile, name: "Development", deviceID: "physical-fixture",
            backingVolumeUUID: v2Host, backingMountPoint: "/Volumes/FixtureHost", imagePath: v2Volume().imagePath,
            devVolumeName: "Development", devMountPoint: v2Volume().mountPoint, devUUID: v2Volume().volumeUUID,
            encrypted: false, caseSensitive: false, logicalCapacityBytes: 100_000, imageFormat: "UDSB")
        #expect(writer.update(profile: profile, event: "registered") == .updated)
        fs.files[v2DocumentPath] = Data(v2Text(fs).replacingOccurrences(of: "Add your own notes here. / 在此填写自己的备注。", with: "Owner notes / 用户备注\n  keep whitespace  ").utf8)
        let journal = SectoriumPortableDocumentJournal(url: root.appendingPathComponent("history.json"))
        try journal.record(context: v2Context(), event: v2Event("loaded:completed", kind: "loaded", index: 1))
        #expect(journal.synchronize(context: v2Context(), writer: writer) == .updated)
        #expect(v2Text(fs).contains("Owner notes / 用户备注\n  keep whitespace  "))
        let history = try journal.events(parentID: v2Context().parent.physicalID)
        #expect(history.count == 2)
        #expect(history[0].id.hasPrefix("legacy-v1:"))
        fs.files.removeValue(forKey: v2DocumentPath)
        #expect(journal.synchronize(context: v2Context(), writer: writer) == .updated)
        #expect(writer.preservedHistory(context: v2Context()) == history)
    }
}
