import Foundation
import Testing
@testable import CodexUsageUI

/// The reader keeps what it has parsed from each transcript and reads only
/// the bytes added since. Every test here compares the reader that carries
/// state against a fresh reader of the same files, which reads them whole,
/// so "incremental" can never mean "different".
@Suite("Claude local activity incremental read", .timeLimit(.minutes(1)))
struct ClaudeLocalActivityIncrementalReadTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Distinct `output` values keep records from collapsing in dedupe.
    private func usageLine(_ output: Int, daysAgo: Int = 0) -> String {
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .format(now.addingTimeInterval(-Double(daysAgo) * 86_400))
        return """
        {"type":"assistant","timestamp":"\(stamp)",\
        "message":{"model":"claude-opus-5","usage":{"input_tokens":500,"output_tokens":\(output)}}}
        """
    }

    private struct Fixture {
        let root: URL
        let file: URL

        func append(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }

        func overwriteInPlace(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data(text.utf8))
        }
    }

    private func fixture(_ label: String, mode: Int = 0o600, initial: String = "") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-claude-incremental-\(label)-\(UUID().uuidString)")
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let file = project.appendingPathComponent("session.jsonl")
        try Data(initial.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
        return Fixture(root: root, file: file)
    }

    private func reader(_ fixture: Fixture) -> ClaudeLocalActivityReader {
        ClaudeLocalActivityReader(rootDirectory: fixture.root, calendar: utcCalendar)
    }

    /// Everything a snapshot publishes that the file contents determine.
    private struct Published: Equatable {
        let availability: ClaudeLocalActivitySnapshot.Availability
        let observedTokens: Int64?
        let pricedTokens: Int64?
        let lifetimeUSD: Double?
        let sevenDayUSD: Double?
        let readable: Int
        let excluded: Int
        let partial: Int
        let changed: Int
        let tasks: [ClaudeLocalActivityTask]

        init(_ snapshot: ClaudeLocalActivitySnapshot) {
            availability = snapshot.availability
            observedTokens = snapshot.apiEquivalentCost?.observedTokens
            pricedTokens = snapshot.apiEquivalentCost?.pricedTokens
            lifetimeUSD = snapshot.apiEquivalentCost?.lifetimeUSD
            sevenDayUSD = snapshot.apiEquivalentCost?.sevenDayUSD
            readable = snapshot.readableFileCount
            excluded = snapshot.excludedFileCount
            partial = snapshot.partiallyReadFileCount
            changed = snapshot.changedDuringReadFileCount
            tasks = snapshot.tasks
        }
    }

    /// Reads with the long-lived reader and with a fresh one, and requires
    /// that they publish the same thing.
    @discardableResult
    private func expectMatchesWholeFileRead(
        _ kept: ClaudeLocalActivityReader,
        _ fixture: Fixture,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> ClaudeLocalActivitySnapshot {
        let incremental = kept.read(now: now)
        let whole = reader(fixture).read(now: now)
        #expect(Published(incremental) == Published(whole), sourceLocation: sourceLocation)
        return incremental
    }

    // MARK: - Appending

    @Test("Appending lines one at a time publishes exactly what a whole-file read does")
    func appendsMatchWholeFileRead() throws {
        // 0644 is how Claude Code writes some transcripts; it must stay readable.
        let fixture = try fixture("append", mode: 0o644)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let kept = reader(fixture)
        expectMatchesWholeFileRead(kept, fixture)

        for output in 1...40 {
            try fixture.append(usageLine(output, daysAgo: output % 10) + "\n")
            expectMatchesWholeFileRead(kept, fixture)
        }
        let snapshot = kept.read(now: now)
        let expected: Int64 = 40 * 500 + Int64((1...40).reduce(0, +))
        #expect(snapshot.apiEquivalentCost?.observedTokens == expected)
        // The comparison above is only worth something if the kept reader
        // really continued rather than starting over each time.
        #expect(kept.parseCache.readCountsForTesting.resumed >= 39)
    }

    @Test("A line written in two parts is counted once, after its newline")
    func partialLineIsCountedOnce() throws {
        let fixture = try fixture("partial", initial: usageLine(1) + "\n")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let kept = reader(fixture)
        expectMatchesWholeFileRead(kept, fixture)

        let line = usageLine(2)
        let middle = line.index(line.startIndex, offsetBy: line.count / 2)
        try fixture.append(String(line[..<middle]))
        let half = expectMatchesWholeFileRead(kept, fixture)
        #expect(half.apiEquivalentCost?.observedTokens == 501)

        // A complete record with no newline yet counts, as the whole-file read
        // always counted it, and must not count again once the newline lands.
        try fixture.append(String(line[middle...]))
        let unterminated = expectMatchesWholeFileRead(kept, fixture)
        #expect(unterminated.apiEquivalentCost?.observedTokens == 1_003)
        try fixture.append("\n")
        let terminated = expectMatchesWholeFileRead(kept, fixture)
        #expect(terminated.apiEquivalentCost?.observedTokens == 1_003)
        try fixture.append(usageLine(3) + "\n")
        let next = expectMatchesWholeFileRead(kept, fixture)
        #expect(next.apiEquivalentCost?.observedTokens == 1_506)
    }

    @Test("An over-long line arriving across reads is skipped once and keeps the rest")
    func overlongLineAcrossReads() throws {
        let fixture = try fixture("overlong", initial: usageLine(1) + "\n")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let kept = reader(fixture)
        expectMatchesWholeFileRead(kept, fixture)

        // The dropped line ends in a valid record, written after the drop has
        // begun. A reader that forgot it was mid-drop would read that tail as
        // a line of its own and count the record.
        let padding = String(repeating: " ", count: 1_024 * 1_024 + 10)
        try fixture.append(String(padding.prefix(700 * 1_024)))
        expectMatchesWholeFileRead(kept, fixture)
        try fixture.append(String(padding.dropFirst(700 * 1_024)))
        let mid = expectMatchesWholeFileRead(kept, fixture)
        #expect(mid.partiallyReadFileCount == 1)
        try fixture.append(usageLine(99) + "\n" + usageLine(2) + "\n")
        let done = expectMatchesWholeFileRead(kept, fixture)
        #expect(done.partiallyReadFileCount == 1)
        #expect(done.apiEquivalentCost?.observedTokens == 1_003)
    }

    // MARK: - Files that do not simply grow

    @Test("A file that shrinks is read again from the start")
    func shrinkResets() throws {
        let lines = (1...10).map { usageLine($0) + "\n" }.joined()
        let fixture = try fixture("shrink", initial: lines)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let kept = reader(fixture)
        expectMatchesWholeFileRead(kept, fixture)

        try fixture.overwriteInPlace((1...3).map { usageLine($0) + "\n" }.joined())
        let shrunk = expectMatchesWholeFileRead(kept, fixture)
        let expected: Int64 = 3 * 500 + 6
        #expect(shrunk.apiEquivalentCost?.observedTokens == expected)
    }

    @Test("A file replaced by another is read again from the start")
    func replacementResets() throws {
        let fixture = try fixture("replace", initial: (1...5).map { usageLine($0) + "\n" }.joined())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let kept = reader(fixture)
        expectMatchesWholeFileRead(kept, fixture)

        // A new inode, longer than the old file, with different early bytes.
        let replacement = (101...108).map { usageLine($0) + "\n" }.joined()
        try Data(replacement.utf8).write(to: fixture.file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.file.path)
        let replaced = expectMatchesWholeFileRead(kept, fixture)
        let expected: Int64 = 8 * 500 + Int64((101...108).reduce(0, +))
        #expect(replaced.apiEquivalentCost?.observedTokens == expected)
    }

    @Test("A file rewritten in place, same inode and no shorter, is read again from the start")
    func inPlaceRewriteResets() throws {
        let fixture = try fixture("rewrite", initial: (1...5).map { usageLine(100 + $0) + "\n" }.joined())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let kept = reader(fixture)
        expectMatchesWholeFileRead(kept, fixture)

        // Same length lines with different counts, then one more line, so the
        // file is longer than the point the kept state stopped at.
        let rewritten = (1...5).map { usageLine(200 + $0) + "\n" }.joined() + usageLine(300) + "\n"
        try fixture.overwriteInPlace(rewritten)
        let snapshot = expectMatchesWholeFileRead(kept, fixture)
        let expected: Int64 = 6 * 500 + Int64((201...205).reduce(0, +)) + 300
        #expect(snapshot.apiEquivalentCost?.observedTokens == expected)
    }

    @Test("A deleted file drops out, and comes back from the start")
    func deletionResets() throws {
        let fixture = try fixture("delete", initial: (1...4).map { usageLine($0) + "\n" }.joined())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let kept = reader(fixture)
        expectMatchesWholeFileRead(kept, fixture)

        try FileManager.default.removeItem(at: fixture.file)
        let gone = expectMatchesWholeFileRead(kept, fixture)
        #expect(gone.availability == .unavailable)

        try Data((1...2).map { usageLine($0) + "\n" }.joined().utf8).write(to: fixture.file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.file.path)
        let back = expectMatchesWholeFileRead(kept, fixture)
        let expected: Int64 = 2 * 500 + 3
        #expect(back.apiEquivalentCost?.observedTokens == expected)
    }

    @Test("A file that becomes unsafe is refused, and starts over once safe again")
    func unsafeFileResets() throws {
        let fixture = try fixture("unsafe", initial: (1...3).map { usageLine($0) + "\n" }.joined())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let kept = reader(fixture)
        expectMatchesWholeFileRead(kept, fixture)

        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: fixture.file.path)
        let refused = expectMatchesWholeFileRead(kept, fixture)
        #expect(refused.excludedFileCount == 1)

        try fixture.overwriteInPlace((1...5).map { usageLine($0) + "\n" }.joined())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.file.path)
        let back = expectMatchesWholeFileRead(kept, fixture)
        let expected: Int64 = 5 * 500 + 15
        #expect(back.apiEquivalentCost?.observedTokens == expected)
    }

    // MARK: - A file that moves while it is read

    @Test("A file that keeps moving publishes nothing and keeps the earlier state")
    func movingFileKeepsState() throws {
        let fixture = try fixture("moving", initial: (1...3).map { usageLine($0) + "\n" }.joined())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let moving = MovingSwitch()
        let file = fixture.file
        let kept = ClaudeLocalActivityReader(
            sources: [.init(surface: .claudeCode, rootDirectory: fixture.root, layout: .projectsRoot)],
            calendar: utcCalendar,
            afterFileReadForTesting: { _ in
                guard moving.isOn else { return }
                let handle = try? FileHandle(forWritingTo: file)
                try? handle?.seekToEnd()
                try? handle?.write(contentsOf: Data(" ".utf8))
                try? handle?.close()
            }
        )
        #expect(kept.read(now: now).apiEquivalentCost?.observedTokens == 1_506)

        try fixture.append(usageLine(4) + "\n")
        moving.isOn = true
        let moved = kept.read(now: now)
        #expect(moved.changedDuringReadFileCount == 1)
        #expect(moved.apiEquivalentCost == nil)
        moving.isOn = false

        // The appended spaces leave an unterminated whitespace tail, which
        // parses to nothing; the record before it counts exactly once.
        let settled = expectMatchesWholeFileRead(kept, fixture)
        #expect(settled.apiEquivalentCost?.observedTokens == 2_010)
    }
}

private final class MovingSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isOn: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
