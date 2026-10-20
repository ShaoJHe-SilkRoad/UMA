import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

private final class PortableMemoryFileSystem: SectoriumPortableDocumentFileSystem {
    var hostVerified = true
    var writeFails = false
    var contents: Data?
    var reads = 0
    var writes = 0
    var lastURL: URL?
    func isVerifiedWritableHost(_ root: URL, volumeUUID: UUID) -> Bool { hostVerified }
    func readRegularFile(_ url: URL, limit: Int) throws -> Data? {
        reads += 1
        return contents
    }
    func commit(_ data: Data, to url: URL, expectedPrior: Data?) throws {
        writes += 1
        lastURL = url
        guard !writeFails, contents == expectedPrior else { throw PortableFixtureError.refused }
        contents = data
    }
}

private enum PortableFixtureError: Error { case refused }

private func portableProfile(
    id: String = "A71E1FC3-0E58-41C3-9F07-21EA7AF24208",
    devUUID: UUID? = UUID(uuidString: "79160516-FD8C-423F-B5BB-BE69A27B92C3")
) -> SectoriumDevelopmentProfile {
    SectoriumDevelopmentProfile(id: id, name: "secret-project-name", deviceID: "fixture-device",
        backingVolumeUUID: UUID(uuidString: "7B305D23-CC44-4A54-96CA-344C984F83F0")!,
        backingMountPoint: "/Volumes/FixtureHost", imagePath: "/Volumes/FixtureHost/private-project.sparsebundle",
        devVolumeName: "DEV", devMountPoint: "/Volumes/FixtureHost/DEV",
        devUUID: devUUID,
        encrypted: true, caseSensitive: true, logicalCapacityBytes: 100_000,
        imageFormat: "UDSB", validation: .validated)
}

private let portableTime = Date(timeIntervalSince1970: 1_760_000_000)

@Test func portableDocumentWritesOnlyForVerifiedManagedProfileAndOmitsPrivatePaths() {
    let fs = PortableMemoryFileSystem()
    let writer = SectoriumPortableDocumentWriter(fileSystem: fs, now: { portableTime })
    #expect(writer.update(profile: portableProfile(), event: "registered") == .updated)
    #expect(fs.lastURL?.path == "/Volumes/FixtureHost/IMPORTANT.md")
    let text = String(decoding: fs.contents ?? Data(), as: UTF8.self)
    #expect(text.contains("Development volume / 开发盘"))
    #expect(text.contains("7B305D23-CC44-4A54-96CA-344C984F83F0"))
    #expect(!text.contains("secret-project-name"))
    #expect(!text.contains("private-project.sparsebundle"))
    #expect(!text.contains("/Volumes/FixtureHost"))
    #expect(writer.update(profile: portableProfile(), event: "registered") == .unchanged)

    fs.hostVerified = false
    let reads = fs.reads
    #expect(writer.update(profile: portableProfile(), event: "loaded") == .pending("Portable document host volume is not verified writable"))
    #expect(fs.reads == reads)
}

@Test func portableDocumentLeavesUnrelatedFileAndMalformedProfileUntouched() {
    let fs = PortableMemoryFileSystem()
    fs.contents = Data("# My own IMPORTANT.md\nkeep this".utf8)
    let writer = SectoriumPortableDocumentWriter(fileSystem: fs, now: { portableTime })
    #expect(writer.update(profile: portableProfile(), event: "registered") == .pending("An unrelated or malformed IMPORTANT.md already exists"))
    #expect(fs.writes == 0)
    #expect(String(decoding: fs.contents ?? Data(), as: UTF8.self).contains("keep this"))
    #expect(writer.update(profile: portableProfile(id: "not-a-uuid"), event: "loaded") == .pending("Portable document requires a valid registered profile"))
    #expect(fs.writes == 0)
}

@Test func portableDocumentPreservesNotesAndRetriesAfterWriteFailure() {
    let fs = PortableMemoryFileSystem()
    let writer = SectoriumPortableDocumentWriter(fileSystem: fs, now: { portableTime })
    #expect(writer.update(profile: portableProfile(), event: "registered") == .updated)
    let original = String(decoding: fs.contents ?? Data(), as: UTF8.self)
    fs.contents = Data(original.replacingOccurrences(of: "Add your own notes here. / 在此填写自己的备注。",
                                                     with: "My own note / 我的备注").utf8)
    let prior = fs.contents
    fs.writeFails = true
    #expect(writer.update(profile: portableProfile(), event: "loaded") == .pending("Portable document write is pending; storage operation is unaffected"))
    #expect(fs.contents == prior)
    fs.writeFails = false
    #expect(writer.update(profile: portableProfile(), event: "loaded") == .updated)
    let updated = String(decoding: fs.contents ?? Data(), as: UTF8.self)
    #expect(updated.contains("My own note / 我的备注"))
    #expect(updated.contains("registered"))
    #expect(updated.contains("loaded"))
}

@Test func portableDocumentRefusesUnexpectedUserAdditionsWithoutChangingBytes() {
    let fs = PortableMemoryFileSystem()
    let writer = SectoriumPortableDocumentWriter(fileSystem: fs, now: { portableTime })
    #expect(writer.update(profile: portableProfile(), event: "registered") == .updated)
    let original = String(decoding: fs.contents ?? Data(), as: UTF8.self)
    let variants = [
        original + "My travel note after the managed document.\n",
        original.replacingOccurrences(
            of: "\n<!-- AUV-SECTORIUM-HISTORY:BEGIN -->\n",
            with: "\nMy travel note before the history.\n<!-- AUV-SECTORIUM-HISTORY:BEGIN -->\n"),
        original.replacingOccurrences(
            of: "\n<!-- AUV-SECTORIUM-NOTES:BEGIN -->\n",
            with: "\nMy travel note between managed sections.\n<!-- AUV-SECTORIUM-NOTES:BEGIN -->\n")
    ]
    for changed in variants {
        let exactUserBytes = Data(changed.utf8)
        fs.contents = exactUserBytes
        let priorWrites = fs.writes
        #expect(writer.update(profile: portableProfile(), event: "loaded") ==
            .pending("Portable document contains edits outside the notes section"))
        #expect(fs.contents == exactUserBytes)
        #expect(fs.writes == priorWrites)
    }
}

@Test func portableDocumentPreservesNotesWhitespaceWhileRefreshingManagedFields() {
    let fs = PortableMemoryFileSystem()
    let writer = SectoriumPortableDocumentWriter(fileSystem: fs, now: { portableTime })
    #expect(writer.update(profile: portableProfile(devUUID: nil), event: "registered") == .updated)
    let original = String(decoding: fs.contents ?? Data(), as: UTF8.self)
    let notes = "\nMy note with blank lines.\n\n"
    fs.contents = Data(original.replacingOccurrences(
        of: "Add your own notes here. / 在此填写自己的备注。", with: notes).utf8)
    #expect(writer.update(profile: portableProfile(), event: "validated") == .updated)
    let updated = String(decoding: fs.contents ?? Data(), as: UTF8.self)
    #expect(updated.contains("Development volume UUID / 开发宗卷标识: 79160516-FD8C-423F-B5BB-BE69A27B92C3"))
    #expect(updated.contains("<!-- AUV-SECTORIUM-NOTES:BEGIN -->\n\(notes)\n<!-- AUV-SECTORIUM-NOTES:END -->"))
}

private final class PortableFixtureRunner: HESectoriumCommandRunning {
    let root: URL
    var commands: [[String]] = []
    init(root: URL) { self.root = root }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        commands.append([executable] + arguments)
        guard executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", root.path], cwd == root else {
            return .init(exitCode: 127, detail: "fixture command refused")
        }
        let value: [String: Any] = ["MountPoint": root.path,
                                    "VolumeUUID": portableProfile().backingVolumeUUID.uuidString,
                                    "WritableVolume": true]
        let data = try! PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
    }
}

@Test func portableDocumentDisposableFilesystemRetainsExactRecoverablePreimage() throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("auv-portable-doc-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    let root = temporaryRoot.resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: root) }
    let runner = PortableFixtureRunner(root: root)
    let fs = SystemSectoriumPortableDocumentFileSystem(runner: runner)
    let base = portableProfile()
    let profile = SectoriumDevelopmentProfile(id: base.id, name: base.name, deviceID: base.deviceID,
        backingVolumeUUID: base.backingVolumeUUID, backingMountPoint: root.path,
        imagePath: root.appendingPathComponent("image.sparsebundle").path,
        devVolumeName: base.devVolumeName, devMountPoint: root.appendingPathComponent("DEV").path,
        devUUID: base.devUUID, encrypted: base.encrypted, caseSensitive: base.caseSensitive,
        logicalCapacityBytes: base.logicalCapacityBytes, imageFormat: base.imageFormat, validation: base.validation)
    let writer = SectoriumPortableDocumentWriter(fileSystem: fs, now: { portableTime })
    #expect(writer.update(profile: profile, event: "registered") == .updated)
    let target = root.appendingPathComponent("IMPORTANT.md")
    let preimage = try Data(contentsOf: target)
    #expect(writer.update(profile: profile, event: "loaded") == .updated)
    let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(".IMPORTANT.md.auv-recovery-") }
    #expect(backups.count == 1)
    #expect(try Data(contentsOf: backups[0]) == preimage)
    #expect(runner.commands.count == 4)

    let after = try Data(contentsOf: target)
    #expect(throws: Error.self) {
        try fs.commit(Data("wrong".utf8), to: target, expectedPrior: preimage)
    }
    #expect(try Data(contentsOf: target) == after)
}

@Test func portableDocumentConcurrentReplacementKeepsTheForeignFile() throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("auv-portable-doc-race-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    let root = temporaryRoot.resolvingSymlinksInPath()
    defer { try? FileManager.default.removeItem(at: root) }
    let fs = SystemSectoriumPortableDocumentFileSystem(runner: PortableFixtureRunner(root: root))
    let base = portableProfile()
    let profile = SectoriumDevelopmentProfile(id: base.id, name: base.name, deviceID: base.deviceID,
        backingVolumeUUID: base.backingVolumeUUID, backingMountPoint: root.path,
        imagePath: root.appendingPathComponent("image.sparsebundle").path,
        devVolumeName: base.devVolumeName, devMountPoint: root.appendingPathComponent("DEV").path,
        devUUID: base.devUUID, encrypted: base.encrypted, caseSensitive: base.caseSensitive,
        logicalCapacityBytes: base.logicalCapacityBytes, imageFormat: base.imageFormat, validation: base.validation)
    let writer = SectoriumPortableDocumentWriter(fileSystem: fs, now: { portableTime })
    #expect(writer.update(profile: profile, event: "registered") == .updated)
    let target = root.appendingPathComponent("IMPORTANT.md")
    let foreign = Data("Someone else's IMPORTANT.md\n".utf8)
    fs.beforeAtomicReplace = { try! foreign.write(to: target, options: .atomic) }
    #expect(writer.update(profile: profile, event: "loaded") ==
        .pending("Portable document write is pending; storage operation is unaffected"))
    #expect(try Data(contentsOf: target) == foreign)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path)
        .filter { $0.hasPrefix(".IMPORTANT.md.auv-next-") }.isEmpty)
    fs.beforeAtomicReplace = nil
    #expect(writer.update(profile: profile, event: "loaded") ==
        .pending("An unrelated or malformed IMPORTANT.md already exists"))
    #expect(try Data(contentsOf: target) == foreign)
}

private func portableTransactionFixture(_ suffix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("auv-portable-exfat-\(suffix)-\(UUID().uuidString)", isDirectory: true)
        .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func portableTransactionFileSystem(_ root: URL) -> SystemSectoriumPortableDocumentFileSystem {
    let fs = SystemSectoriumPortableDocumentFileSystem(runner: PortableFixtureRunner(root: root))
    fs.forcePortableCommitForTesting = true
    return fs
}

@Test func portableDocumentExFATCreationAndReplacementRetainPreimage() throws {
    let root = try portableTransactionFixture("replace")
    defer { try? FileManager.default.removeItem(at: root) }
    let fs = portableTransactionFileSystem(root), target = root.appendingPathComponent("IMPORTANT.md")
    let prior = Data("original notes and history".utf8), next = Data("next notes and history".utf8)
    try fs.commit(prior, to: target, expectedPrior: nil)
    try fs.commit(next, to: target, expectedPrior: prior)
    #expect(try Data(contentsOf: target) == next)
    let saved = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(".IMPORTANT.md.auv-recovery-") }
    #expect(saved.count == 1)
    #expect(try Data(contentsOf: saved[0]) == prior)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".IMPORTANT.md.auv-transaction.json").path))
}

@Test func portableDocumentExFATReplacementRestoresConcurrentForeignFile() throws {
    let root = try portableTransactionFixture("foreign")
    defer { try? FileManager.default.removeItem(at: root) }
    let fs = portableTransactionFileSystem(root), target = root.appendingPathComponent("IMPORTANT.md")
    let prior = Data("original".utf8), foreign = Data("user changed the document".utf8)
    try fs.commit(prior, to: target, expectedPrior: nil)
    fs.beforeAtomicReplace = { try! foreign.write(to: target, options: .atomic) }
    #expect(throws: Error.self) { try fs.commit(Data("new".utf8), to: target, expectedPrior: prior) }
    #expect(try Data(contentsOf: target) == foreign)
}

@Test func portableDocumentExFATExclusivePublicationPreservesRacingFile() throws {
    let root = try portableTransactionFixture("publication-race")
    defer { try? FileManager.default.removeItem(at: root) }
    let fs = portableTransactionFileSystem(root), target = root.appendingPathComponent("IMPORTANT.md")
    let prior = Data("original".utf8), foreign = Data("concurrent new document".utf8)
    try fs.commit(prior, to: target, expectedPrior: nil)
    fs.afterPortableDisplacement = { try foreign.write(to: target, options: .atomic) }
    #expect(throws: Error.self) { try fs.commit(Data("new".utf8), to: target, expectedPrior: prior) }
    #expect(try Data(contentsOf: target) == foreign)
    let fresh = portableTransactionFileSystem(root)
    #expect(throws: Error.self) { try fresh.commit(Data("new retry".utf8), to: target, expectedPrior: foreign) }
    #expect(try Data(contentsOf: target) == foreign)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".IMPORTANT.md.auv-transaction.json").path))
}

@Test func portableDocumentExFATInterruptedReplacementRestoresWithFreshWriter() throws {
    let root = try portableTransactionFixture("interrupted")
    defer { try? FileManager.default.removeItem(at: root) }
    let fs = portableTransactionFileSystem(root), target = root.appendingPathComponent("IMPORTANT.md")
    let prior = Data("user notes retained across restart".utf8), next = Data("updated history".utf8)
    try fs.commit(prior, to: target, expectedPrior: nil)
    fs.afterPortableDisplacement = { throw PortableFixtureError.refused }
    #expect(throws: Error.self) { try fs.commit(next, to: target, expectedPrior: prior) }
    #expect(!FileManager.default.fileExists(atPath: target.path))
    let fresh = portableTransactionFileSystem(root)
    // The caller observed an absent name: restore the original, then require
    // another render so its notes cannot be lost to the caller's stale snapshot.
    #expect(throws: Error.self) { try fresh.commit(next, to: target, expectedPrior: nil) }
    #expect(try Data(contentsOf: target) == prior)
    try fresh.commit(next, to: target, expectedPrior: prior)
    #expect(try Data(contentsOf: target) == next)
}

@Test func portableDocumentExFATFirstCreationDoesNotOverwriteExistingFile() throws {
    let root = try portableTransactionFixture("create-race")
    defer { try? FileManager.default.removeItem(at: root) }
    let fs = portableTransactionFileSystem(root), target = root.appendingPathComponent("IMPORTANT.md")
    let foreign = Data("unrelated user document".utf8)
    fs.afterPortableDisplacement = { try foreign.write(to: target, options: .atomic) }
    #expect(throws: Error.self) { try fs.commit(Data("managed document".utf8), to: target, expectedPrior: nil) }
    #expect(try Data(contentsOf: target) == foreign)
}


@Test func portableDocumentExFATConcurrentWriterCannotRecoverActiveTransaction() throws {
    let root = try portableTransactionFixture("active-writer")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = portableTransactionFileSystem(root), second = portableTransactionFileSystem(root)
    let target = root.appendingPathComponent("IMPORTANT.md")
    let prior = Data("original notes".utf8), next = Data("first writer completed".utf8)
    try first.commit(prior, to: target, expectedPrior: nil)
    first.beforeAtomicReplace = {
        #expect(throws: Error.self) {
            try second.commit(Data("second writer".utf8), to: target, expectedPrior: prior)
        }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".IMPORTANT.md.auv-transaction.json").path))
    }
    try first.commit(next, to: target, expectedPrior: prior)
    #expect(try Data(contentsOf: target) == next)
    // Closing the first writer's descriptor releases the lock without deleting it.
    let later = Data("later writer".utf8)
    try second.commit(later, to: target, expectedPrior: next)
    #expect(try Data(contentsOf: target) == later)
}

@Test func portableDocumentExFATFailedPublishRetainsRacingReplacement() throws {
    let root = try portableTransactionFixture("failed-publication-race")
    defer { try? FileManager.default.removeItem(at: root) }
    let fs = portableTransactionFileSystem(root), target = root.appendingPathComponent("IMPORTANT.md")
    let prior = Data("user notes".utf8), foreign = Data("concurrent editor contents".utf8)
    try fs.commit(prior, to: target, expectedPrior: nil)
    fs.afterExclusiveCreate = { url in
        guard url == target else { return }
        try foreign.write(to: target, options: .atomic)
        throw PortableFixtureError.refused
    }
    #expect(throws: Error.self) { try fs.commit(Data("next".utf8), to: target, expectedPrior: prior) }
    #expect(try Data(contentsOf: target) == foreign)
    let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(".IMPORTANT.md.auv-recovery-") }
    #expect(backups.count == 1)
    #expect(try Data(contentsOf: backups[0]) == prior)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(".IMPORTANT.md.auv-transaction.json").path))
}

@Test func portableDocumentExFATFailedPublishRetainsPartialAndRecovery() throws {
    let root = try portableTransactionFixture("partial-publication")
    defer { try? FileManager.default.removeItem(at: root) }
    let fs = portableTransactionFileSystem(root), target = root.appendingPathComponent("IMPORTANT.md")
    let prior = Data("original notes".utf8)
    try fs.commit(prior, to: target, expectedPrior: nil)
    fs.afterExclusiveCreate = { url in
        if url == target { throw PortableFixtureError.refused }
    }
    #expect(throws: Error.self) { try fs.commit(Data("next".utf8), to: target, expectedPrior: prior) }
    #expect(try Data(contentsOf: target).isEmpty)
    let fresh = portableTransactionFileSystem(root)
    #expect(throws: Error.self) { try fresh.commit(Data("retry".utf8), to: target, expectedPrior: Data()) }
    #expect(try Data(contentsOf: target).isEmpty)
    let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix(".IMPORTANT.md.auv-recovery-") }
    #expect(backups.count == 1)
    #expect(try Data(contentsOf: backups[0]) == prior)
}
