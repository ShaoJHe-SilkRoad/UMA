import Foundation
import Testing
@testable import HESectoriumRuntime
#if canImport(Darwin)
import Darwin
#endif

struct SectoriumMountPointDirectoryTests {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("auv-mount-dir-\(UUID())").resolvingSymlinksInPath()
        let target = root.appendingPathComponent("DEV")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return (root, target)
    }

    @Test("Load validation preserves empty and nonempty directory identity and permissions", arguments: [false, true])
    func mountDirectoryIsNeverRecreated(nonempty: Bool) throws {
        let (root, target) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = target.appendingPathComponent("do-not-delete.txt")
        if nonempty { try Data("preserve me".utf8).write(to: file) }
        try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: target.path)
        let before = try FileManager.default.attributesOfItem(atPath: target.path)
        for _ in 0..<3 { #expect(SectoriumMountPointDirectory().validateForMount(at: target.path) == nil) }
        let after = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect(after[.systemFileNumber] as? UInt64 == before[.systemFileNumber] as? UInt64)
        #expect(after[.posixPermissions] as? Int == 0o750)
        if nonempty { #expect(try String(contentsOf: file, encoding: .utf8) == "preserve me") }
    }

    @Test("Symlink target and symlink parent are refused without replacing anything")
    func symlinkRefused() throws {
        let (root, target) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let parentAlias = root.appendingPathComponent("parent-alias")
        try FileManager.default.createSymbolicLink(at: parentAlias, withDestinationURL: root)
        let helper = SectoriumMountPointDirectory()
        #expect(helper.validateForMount(at: alias.path) != nil)
        #expect(helper.validateForMount(at: parentAlias.appendingPathComponent("DEV").path) != nil)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path) == target.path)
    }

    @Test("A regular file or missing target remains a refusal")
    func invalidTargetRefused() throws {
        let (root, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try Data("keep".utf8).write(to: file)
        let helper = SectoriumMountPointDirectory()
        #expect(helper.validateForMount(at: file.path) != nil)
        #expect(helper.validateForMount(at: root.appendingPathComponent("absent").path) != nil)
        #expect(helper.validateForMount(at: "/") != nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
    }

    @Test("Directory count remains available for settings but does not gate Load")
    func nativeCountIsSeparate() throws {
        let (root, target) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(SectoriumMountPointDirectory.entryCount(at: target.path) == 0)
        try Data("keep".utf8).write(to: target.appendingPathComponent("file"))
        #expect(SectoriumMountPointDirectory.entryCount(at: target.path) == 1)
        #expect(SectoriumMountPointDirectory().validateForMount(at: target.path) == nil)
    }

    @Test("Load structural check never enumerates, counts, removes or recreates a directory")
    func validationHasNoContentOrMutationCalls() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/HESectoriumRuntime/SectoriumMountPointDirectory.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let body = try #require(text.components(separatedBy: "func validateForMount").last)
        for forbidden in ["nativeCount(", "entryCount(", "fgetattrlist(", "unlinkat(", "mkdirat(", "fchmod(", "readdir(", "contentsOfDirectory", "enumerator("] {
            #expect(!body.contains(forbidden), "Unexpected Load preflight call: \(forbidden)")
        }
    }
}
