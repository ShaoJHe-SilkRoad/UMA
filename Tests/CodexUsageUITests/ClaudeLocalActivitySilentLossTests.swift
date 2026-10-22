import Foundation
import Testing
@testable import CodexUsageUI

/// Three ways the local activity reader used to drop data without saying so:
/// a file mode that excluded Claude Code's own `journal.jsonl`, a per-line cap
/// that discarded the whole file around one long line, and a file appended to
/// mid-read being indistinguishable from an unreadable one.
///
/// The transactional guarantee is unchanged — nothing from a file that moved
/// while open is published — so `M5RMXCloseSecurityTests` still holds.
@Suite("Claude local activity silent loss", .timeLimit(.minutes(1)))
struct ClaudeLocalActivitySilentLossTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 600 tokens on Opus by default: 500 in at $5/M plus 100 out at $25/M.
    ///
    /// `output` is a parameter because the dedupe digest is built from the
    /// timestamp, model family and counts — never the provider's requestId —
    /// so two records that differ only by requestId collapse into one.
    private func usageLine(_ requestID: String, output: Int64 = 100) -> String {
        let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(now)
        return """
        {"type":"assistant","requestId":"\(requestID)","timestamp":"\(stamp)",\
        "message":{"model":"claude-opus-5","usage":{"input_tokens":500,"output_tokens":\(output)}}}
        """
    }

    @discardableResult
    private func writeFixture(
        lines: [String],
        named name: String = "session.jsonl",
        mode: Int,
        trailingNewline: Bool = true,
        in root: URL
    ) throws -> URL {
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent(name)
        let body = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try Data(body.utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: mode], ofItemAtPath: file.path
        )
        return file
    }

    private func temporaryRoot(_ label: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-claude-silent-loss-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: root.path
        )
        return root
    }

    private func read(_ root: URL) -> ClaudeLocalActivitySnapshot {
        ClaudeLocalActivityReader(rootDirectory: root, calendar: utcCalendar).read(now: now)
    }

    // MARK: - The file mode

    // Claude Code writes `journal.jsonl` as 0644. The old guard required no
    // group or other bits at all, so those files were excluded whole.
    @Test("A 0644 record file is read")
    func groupReadableFileIsRead() throws {
        let root = try temporaryRoot("mode-644")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFixture(lines: [usageLine("a")], named: "journal.jsonl", mode: 0o644, in: root)

        let snapshot = read(root)
        #expect(snapshot.availability == .available)
        #expect(snapshot.apiEquivalentCost?.observedTokens == 600)
        #expect(snapshot.readableFileCount == 1)
        #expect(snapshot.excludedFileCount == 0)
    }

    // Only the write bits bear on whether someone else could have changed the
    // bytes, and those must still fail closed.
    @Test("A group- or other-writable record file is still refused")
    func writableFileIsStillRefused() throws {
        for mode in [0o664, 0o606, 0o666] {
            let root = try temporaryRoot("mode-\(String(mode, radix: 8))")
            defer { try? FileManager.default.removeItem(at: root) }
            try writeFixture(lines: [usageLine("a")], mode: mode, in: root)

            let snapshot = read(root)
            #expect(snapshot.availability == .unavailable)
            #expect(snapshot.apiEquivalentCost == nil)
            #expect(snapshot.readableFileCount == 0)
        }
    }

    @Test("0600 is unaffected")
    func ownerOnlyFileStillReads() throws {
        let root = try temporaryRoot("mode-600")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFixture(lines: [usageLine("a")], mode: 0o600, in: root)
        #expect(read(root).apiEquivalentCost?.observedTokens == 600)
    }

    // MARK: - The per-line cap

    private var overlongLine: String {
        String(repeating: " ", count: ClaudeLocalActivityReader.Bounds.maximumBytesPerLine + 1)
    }

    @Test("An over-long line costs that line, not the file")
    func overlongLineKeepsTheRestOfTheFile() throws {
        let root = try temporaryRoot("line-cap")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeFixture(
            lines: [usageLine("a"), overlongLine, usageLine("b", output: 300)],
            mode: 0o600,
            in: root
        )

        var projected: [ClaudeLocalUsageRecord] = []
        let outcome = ClaudeLocalActivityReader.streamOutcomeForTesting(inFileAt: file) {
            projected.append($0)
            return true
        }
        #expect(outcome.succeeded)
        #expect(outcome.skippedLines == 1)
        #expect(projected.count == 2)

        // Both records count, and coverage must not claim a whole file.
        let snapshot = read(root)
        #expect(snapshot.availability == .available)
        #expect(snapshot.apiEquivalentCost?.observedTokens == 1_400)
        #expect(snapshot.partiallyReadFileCount == 1)
        #expect(snapshot.readableFileCount == 0)
        #expect(snapshot.excludedFileCount == 0)
    }

    // The cap must still bound memory when the over-long line never ends, and
    // the line is counted once however many read chunks it spans.
    @Test("An unterminated over-long tail is skipped once")
    func unterminatedOverlongTailIsSkippedOnce() throws {
        let root = try temporaryRoot("line-tail")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeFixture(
            lines: [usageLine("a"), String(repeating: " ", count: 4 * 1_024 * 1_024)],
            mode: 0o600,
            trailingNewline: false,
            in: root
        )

        var projected: [ClaudeLocalUsageRecord] = []
        let outcome = ClaudeLocalActivityReader.streamOutcomeForTesting(inFileAt: file) {
            projected.append($0)
            return true
        }
        #expect(outcome.succeeded)
        #expect(outcome.skippedLines == 1)
        #expect(projected.count == 1)
    }

    @Test("A file of nothing but one over-long line yields no records and no failure")
    func fileOfOneOverlongLineYieldsNothing() throws {
        let root = try temporaryRoot("line-only")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeFixture(lines: [overlongLine], mode: 0o600, in: root)

        var count = 0
        let outcome = ClaudeLocalActivityReader.streamOutcomeForTesting(inFileAt: file) { _ in
            count += 1
            return true
        }
        #expect(outcome.succeeded)
        #expect(outcome.skippedLines == 1)
        #expect(count == 0)
        // No tokens anywhere, so the snapshot is still unavailable.
        #expect(read(root).availability == .unavailable)
    }

    // MARK: - Changing under the read

    /// Counts invocations so a test can mutate on the first attempt only.
    private final class Attempts: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }

        var total: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    private static func appendByte(to file: URL) {
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("x".utf8))
        try? handle.close()
    }

    // A session transcript is appended to in bursts. One attempt landing in a
    // burst used to discard the file; the retry reads it once it settles.
    @Test("A file that moves once is read on the retry")
    func fileThatMovesOnceIsReadOnRetry() throws {
        let root = try temporaryRoot("moves-once")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeFixture(lines: [usageLine("a")], mode: 0o600, in: root)

        let attempts = Attempts()
        let reader = ClaudeLocalActivityReader(
            sources: [ClaudeLocalActivityReader.Source(
                surface: .claudeCode,
                rootDirectory: root,
                layout: .projectsRoot
            )],
            calendar: utcCalendar,
            afterFileReadForTesting: { changed in
                guard changed == file, attempts.next() == 1 else { return }
                Self.appendByte(to: changed)
            }
        )

        let snapshot = reader.read(now: now)
        #expect(attempts.total == 2)
        #expect(snapshot.availability == .available)
        #expect(snapshot.apiEquivalentCost?.observedTokens == 600)
        #expect(snapshot.readableFileCount == 1)
        #expect(snapshot.changedDuringReadFileCount == 0)
    }

    // The transactional guarantee is untouched: a file still moving on every
    // attempt publishes nothing. It is now reported as such instead of being
    // counted among files that could not be read at all.
    @Test("A file that keeps moving publishes nothing, and says why")
    func fileThatKeepsMovingPublishesNothing() throws {
        let root = try temporaryRoot("keeps-moving")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeFixture(lines: [usageLine("a")], mode: 0o600, in: root)

        let attempts = Attempts()
        let reader = ClaudeLocalActivityReader(
            sources: [ClaudeLocalActivityReader.Source(
                surface: .claudeCode,
                rootDirectory: root,
                layout: .projectsRoot
            )],
            calendar: utcCalendar,
            afterFileReadForTesting: { changed in
                guard changed == file else { return }
                _ = attempts.next()
                Self.appendByte(to: changed)
            }
        )

        let snapshot = reader.read(now: now)
        #expect(attempts.total == ClaudeLocalActivityReader.Bounds.maximumReadAttempts)
        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.apiEquivalentCost == nil)
        #expect(snapshot.readableFileCount == 0)
        #expect(snapshot.changedDuringReadFileCount == 1)
        #expect(snapshot.excludedFileCount == 0)
    }

    // A refusal is a property of the file, so it must not be retried.
    @Test("An unsafe file is refused once, not retried")
    func unsafeFileIsNotRetried() throws {
        let root = try temporaryRoot("no-retry")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeFixture(lines: [usageLine("a")], mode: 0o664, in: root)

        let attempts = Attempts()
        let reader = ClaudeLocalActivityReader(
            sources: [ClaudeLocalActivityReader.Source(
                surface: .claudeCode,
                rootDirectory: root,
                layout: .projectsRoot
            )],
            calendar: utcCalendar,
            afterFileReadForTesting: { changed in
                guard changed == file else { return }
                _ = attempts.next()
            }
        )

        let snapshot = reader.read(now: now)
        // The mode is rejected before the read begins, so the hook never runs.
        #expect(attempts.total == 0)
        #expect(snapshot.excludedFileCount == 1)
        #expect(snapshot.changedDuringReadFileCount == 0)
    }
}
