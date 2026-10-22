import Foundation
import Testing
@testable import ClaudeStatusLineCore
@testable import CodexUsageUI

/// `FileHandle`'s legacy `readData(ofLength:)` and `write(_:)` raise
/// `NSFileHandleOperationException` when the underlying syscall fails. An
/// Objective-C exception unwinding through Swift frames cannot be caught: it
/// reaches `std::terminate` and aborts the process.
///
/// 0.17.4 died that way in the field — a read parked in
/// `JSONLineJSONRPCFraming.readMessage(from:)` on a stdout handle that had
/// been closed under it. These cover the three call sites that could abort.
///
/// Every test here aborts the whole test process if its fix is removed, rather
/// than failing. That is the point: there is no catch to assert against.
@Suite("FileHandle exception aborts", .timeLimit(.minutes(1)))
struct FileHandleExceptionAbortTests {
    // MARK: - The read that crashed

    // `stop()` closes stdout precisely to unblock a read parked in this loop.
    @Test("A read on a closed handle ends the stream instead of aborting")
    func readOnClosedHandleReturnsNil() throws {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        try reader.close()
        #expect(JSONLineJSONRPCFraming.readMessage(from: reader) == nil)
    }

    // A file handle whose descriptor was closed behind Foundation's back fails
    // the read with EBADF, which is what a replaced child leaves behind.
    @Test("A read on an invalidated descriptor ends the stream")
    func readOnInvalidatedDescriptorReturnsNil() throws {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        close(reader.fileDescriptor)
        #expect(JSONLineJSONRPCFraming.readMessage(from: reader) == nil)
        // Foundation would close it again on deinit; keep that out of the test.
        _ = try? pipe.fileHandleForWriting.close()
    }

    @Test("Normal framing is unchanged")
    func framingStillReadsOneMessagePerLine() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data(#"{"id":1}"#.utf8 + [0x0A]))
        try pipe.fileHandleForWriting.write(contentsOf: Data(#"{"id":2}"#.utf8 + [0x0D, 0x0A]))
        try pipe.fileHandleForWriting.close()

        let reader = pipe.fileHandleForReading
        #expect(JSONLineJSONRPCFraming.readMessage(from: reader) == Data(#"{"id":1}"#.utf8))
        // A trailing CR belongs to the framing, not to the body.
        #expect(JSONLineJSONRPCFraming.readMessage(from: reader) == Data(#"{"id":2}"#.utf8))
        // End of stream.
        #expect(JSONLineJSONRPCFraming.readMessage(from: reader) == nil)
    }

    // Backed by a file rather than a pipe: the cap exceeds any pipe buffer,
    // so a pipe would need a writer running alongside the reader and would
    // only muddy what is being asserted.
    @Test("A message over the cap still fails closed")
    func oversizedMessageReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-oversized-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        // No newline anywhere, so the loop runs past the cap.
        try Data(
            repeating: 0x20,
            count: JSONLineJSONRPCFraming.maximumMessageBytes + 2
        ).write(to: url)

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        #expect(JSONLineJSONRPCFraming.readMessage(from: handle) == nil)
    }

    // MARK: - The write to a dead child

    /// A stand-in Codex app-server that closes its stdin and then exits. The
    /// fixed exit delay keeps it under the transport's one-second restart
    /// floor, so no relaunch races the assertion.
    private func scriptClosingItsStdin() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-stdin-closer-\(UUID().uuidString).sh")
        try Data("#!/bin/sh\nexec 0<&-\nsleep 0.2\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: url.path
        )
        return url
    }

    @Test("Writing to a child that closed its stdin throws instead of aborting")
    func writeToDeadPipeThrows() throws {
        let script = try scriptClosingItsStdin()
        defer { try? FileManager.default.removeItem(at: script) }
        let transport = ProcessCodexAppServerTransport()
        defer { transport.stop() }
        try transport.start(executableURL: script)

        // Larger than any pipe buffer, so the write cannot be absorbed and
        // must observe the closed read end however the two races resolve.
        let payload = Data(repeating: 0x20, count: 2 * 1_024 * 1_024)
        #expect(throws: (any Error).self) {
            try transport.write(payload)
        }
    }

    // MARK: - The write to a prior status-line command

    @Test("A prior command that ignores its stdin reports its exit status")
    func priorCommandIgnoringStdinStillReportsExitStatus() throws {
        let result = try ClaudePriorCommandRunner().run(
            command: "exec 0<&-; sleep 0.2; exit 7",
            rawInput: Data(repeating: 0x20, count: 2 * 1_024 * 1_024),
            recursionMarkerPresent: false
        )
        #expect(result == .exited(7))
    }

    @Test("A prior command that does read its stdin is unaffected")
    func priorCommandReadingStdinIsUnaffected() throws {
        let result = try ClaudePriorCommandRunner().run(
            command: "cat > /dev/null; exit 3",
            rawInput: Data(repeating: 0x20, count: 128 * 1_024),
            recursionMarkerPresent: false
        )
        #expect(result == .exited(3))
    }
}
