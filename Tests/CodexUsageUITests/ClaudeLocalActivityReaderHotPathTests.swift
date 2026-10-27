import CryptoKit
import Foundation
import Testing
@testable import CodexUsageUI

/// The reader's line splitting and digest encoding were rewritten for speed.
/// These pin that the bytes it hands to the parser, and the digest it builds
/// from them, are exactly what the slower code produced.
@Suite("Claude local activity reader hot path", .timeLimit(.minutes(1)))
struct ClaudeLocalActivityReaderHotPathTests {
    private let stamp = "2027-01-15T08:00:00.000Z"

    private func usageLine(output: Int64, padding: Int = 0) -> String {
        let filler = String(repeating: "x", count: padding)
        return """
        {"type":"assistant","timestamp":"\(stamp)","pad":"\(filler)",\
        "message":{"model":"claude-opus-5","usage":{"input_tokens":500,"output_tokens":\(output)}}}
        """
    }

    private func temporaryFile(_ body: Data) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-claude-hot-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("session.jsonl")
        try body.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }

    @Test("The digest is the lowercase hex of the SHA-256 of the allowlisted fields")
    func digestMatchesReferenceEncoding() throws {
        let record = try #require(ClaudeLocalActivityReader.record(fromLine: usageLine(output: 100)))
        let material = [
            "allowlisted-structural", stamp, "opus", "500", "100", "0", "0", "0",
        ].joined(separator: "\u{0}")
        let reference = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(record.dedupeDigest == reference)
    }

    // A record longer than one 64 KiB read chunk, a CRLF-terminated record and
    // an unterminated final record must each reach the parser whole.
    @Test("Lines spanning many read chunks, CRLF and an unterminated tail all parse")
    func linesAcrossChunksParse() throws {
        let long = usageLine(output: 1, padding: 900 * 1_024)
        let body = long + "\n" + usageLine(output: 2) + "\r\n" + usageLine(output: 3)
        let file = try temporaryFile(Data(body.utf8))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        var outputs: [Int64] = []
        let outcome = ClaudeLocalActivityReader.streamOutcomeForTesting(inFileAt: file) {
            outputs.append($0.counts.outputTokens)
            return true
        }
        #expect(outcome.succeeded)
        #expect(outcome.skippedLines == 0)
        #expect(outputs == [1, 2, 3])
    }

    // Hundreds of lines of uneven length put line ends at every position
    // relative to the read chunks, including lines that start in one chunk
    // and end in the next.
    @Test("Every record of a multi-chunk file is parsed once, in order")
    func manyLinesAcrossChunkBoundaries() throws {
        let lines = (1...600).map { usageLine(output: Int64($0), padding: ($0 * 977) % 4_000) }
        let file = try temporaryFile(Data((lines.joined(separator: "\n") + "\n").utf8))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        var outputs: [Int64] = []
        let outcome = ClaudeLocalActivityReader.streamOutcomeForTesting(inFileAt: file) {
            outputs.append($0.counts.outputTokens)
            return true
        }
        #expect(outcome.succeeded)
        #expect(outputs == (1...600).map { Int64($0) })
    }

    @Test("Blank lines and a newline at a chunk boundary neither merge nor drop records")
    func chunkBoundaryNewline() throws {
        // The first line ends exactly on the 64 KiB chunk boundary.
        let unpadded = usageLine(output: 1).utf8.count
        let boundaryLine = usageLine(output: 1, padding: 64 * 1_024 - 1 - unpadded)
        #expect(boundaryLine.utf8.count + 1 == 64 * 1_024)
        let body = boundaryLine + "\n\n" + usageLine(output: 2) + "\n"
        let file = try temporaryFile(Data(body.utf8))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        var outputs: [Int64] = []
        let outcome = ClaudeLocalActivityReader.streamOutcomeForTesting(inFileAt: file) {
            outputs.append($0.counts.outputTokens)
            return true
        }
        #expect(outcome.succeeded)
        #expect(outputs == [1, 2])
    }
}
