import ClaudeStatusLineCore
import Darwin
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5-G2 Claude relay protocol")
struct M5G2ClaudeRelayProtocolTests {
    private let observation = Date(timeIntervalSince1970: 1_900_000_000)

    @Test
    func strictDecoderProjectsOnlyBothAcceptedWindows() throws {
        let packet = try decode(
            """
            {
              "version": "synthetic-2.1.220",
              "session_id": "rejected",
              "transcript_path": "/rejected",
              "workspace": {"current_dir": "/rejected"},
              "rate_limits": {
                "five_hour": {
                  "used_percentage": 36.25,
                  "resets_at": 1900001000,
                  "unknown": "rejected"
                },
                "seven_day": {
                  "used_percentage": 1,
                  "resets_at": 1900002000
                }
              },
              "future": {"raw": "rejected"}
            }
            """
        )
        #expect(packet.schemaVersion == 1)
        #expect(packet.claudeVersion == "synthetic-2.1.220")
        #expect(packet.fiveHour?.usedPercentage == 36.25)
        #expect(packet.fiveHour?.resetsAtEpochSeconds == 1_900_001_000)
        #expect(packet.sevenDay?.usedPercentage == 1)
        #expect(packet.sevenDay?.resetsAtEpochSeconds == 1_900_002_000)
        #expect(packet.observedAt == observation)
        let reflection = String(reflecting: packet)
        #expect(!reflection.contains("rejected"))
        #expect(!reflection.contains("session"))
        #expect(!reflection.contains("transcript"))
    }

    @Test(arguments: [
        ("five_hour", 0.0, 100.0),
        ("five_hour", 1.0, 99.0),
        ("five_hour", 36.25, 63.75),
        ("five_hour", 99.9, 0.1),
        ("five_hour", 100.0, 0.0),
        ("seven_day", 25.5, 74.5),
    ])
    func sharedModelOwnsTheOnlyUsedToRemainingConversion(
        name: String,
        used: Double,
        remaining: Double
    ) throws {
        let packet = try decode(
            """
            {"rate_limits":{"\(name)":{
              "used_percentage":\(used),
              "resets_at":1900001000
            }}}
            """
        )
        let window = try #require(
            name == "five_hour" ? packet.fiveHour : packet.sevenDay
        )
        let snapshot = claudeSnapshot(
            packet: packet,
            window: window,
            kind: name == "five_hour" ? .fiveHour : .sevenDay
        )
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .english,
            now: observation
        )
        guard case let .finite(value) = card.remaining else {
            Issue.record("Expected finite remaining value")
            return
        }
        #expect(abs(value - remaining) < 0.000_000_1)
    }

    @Test
    func optionalWindowsRemainIndependentAndMissingRemainsUnavailable() throws {
        let fiveOnly = try decode(
            """
            {"rate_limits":{"five_hour":{
              "used_percentage":50,"resets_at":1900001000
            }}}
            """
        )
        #expect(fiveOnly.fiveHour != nil)
        #expect(fiveOnly.sevenDay == nil)

        let sevenOnly = try decode(
            """
            {"rate_limits":{"seven_day":{
              "used_percentage":75,"resets_at":1900002000
            }}}
            """
        )
        #expect(sevenOnly.fiveHour == nil)
        #expect(sevenOnly.sevenDay != nil)

        let none = try decode(#"{"rate_limits":null}"#)
        #expect(none.fiveHour == nil)
        #expect(none.sevenDay == nil)
    }

    @Test(arguments: [
        "-0.01",
        "100.01",
        #""50""#,
        "true",
        "null",
        "{}",
        "[]",
        "NaN",
        "Infinity",
        "-Infinity",
    ])
    func invalidPercentageFailsClosed(_ literal: String) {
        #expect(throws: Error.self) {
            _ = try decode(
                """
                {"rate_limits":{"five_hour":{
                  "used_percentage":\(literal),
                  "resets_at":1900001000
                }}}
                """
            )
        }
    }

    @Test(arguments: [
        "-1",
        "1900001000.5",
        #""1900001000""#,
        "true",
        "null",
        "4102444801",
    ])
    func invalidResetFailsClosed(_ literal: String) {
        #expect(throws: Error.self) {
            _ = try decode(
                """
                {"rate_limits":{"five_hour":{
                  "used_percentage":50,
                  "resets_at":\(literal)
                }}}
                """
            )
        }
    }

    @Test
    func malformedWrongTypeAndOversizedInputFailClosed() {
        #expect(throws: Error.self) {
            _ = try decode("{")
        }
        #expect(throws: Error.self) {
            _ = try decode(#"{"rate_limits":"wrong"}"#)
        }
        let oversized = Data(
            repeating: 0x20,
            count: ClaudeStatusLineProjection.maximumInputBytes + 1
        )
        #expect(throws: ClaudeStatusLineProtocolError.inputTooLarge) {
            _ = try ClaudeStatusLineProjection.decode(oversized)
        }
    }

    @Test
    func packetRoundTripIsBoundedVersionedAndContainsNoRawProviderObject()
    throws {
        let packet = try decode(
            """
            {"version":"synthetic","rate_limits":{"five_hour":{
              "used_percentage":10,"resets_at":1900001000
            }}}
            """
        )
        let encoded = try packet.encoded()
        #expect(encoded.count <= ClaudeStatusLinePacket.maximumEncodedBytes)
        #expect(try ClaudeStatusLinePacket.decodePacket(encoded) == packet)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains("rate_limits"))
        #expect(!text.contains("session_id"))
        #expect(!text.contains("transcript_path"))
        #expect(!text.contains("raw"))

        var future = try #require(
            JSONSerialization.jsonObject(with: encoded)
                as? [String: Any]
        )
        future["schemaVersion"] = 2
        #expect(throws: Error.self) {
            _ = try ClaudeStatusLinePacket.decodePacket(
                JSONSerialization.data(withJSONObject: future)
            )
        }
    }

    @Test
    func packetDecoderRejectsInvalidValuesAndPrivateOrUnknownKeys() throws {
        let invalidPercentage = Data(
            """
            {"schemaVersion":1,"fiveHour":{
              "usedPercentage":101,"resetsAtEpochSeconds":1900001000
            },"observedAt":1900000000000}
            """.utf8
        )
        #expect(throws: ClaudeStatusLineProtocolError.self) {
            try ClaudeStatusLinePacket.decodePacket(invalidPercentage)
        }

        let invalidReset = Data(
            """
            {"schemaVersion":1,"fiveHour":{
              "usedPercentage":20,"resetsAtEpochSeconds":4102444801
            },"observedAt":1900000000000}
            """.utf8
        )
        #expect(throws: ClaudeStatusLineProtocolError.self) {
            try ClaudeStatusLinePacket.decodePacket(invalidReset)
        }

        var object = try #require(
            JSONSerialization.jsonObject(
                with: try decode(
                    """
                    {"rate_limits":{"five_hour":{
                      "used_percentage":20,"resets_at":1900001000
                    }}}
                    """
                ).encoded()
            ) as? [String: Any]
        )
        object["sessionID"] = "synthetic-private-field"
        let injected = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ClaudeStatusLineProtocolError.self) {
            try ClaudeStatusLinePacket.decodePacket(injected)
        }
    }

    @Test
    func priorCommandReceivesExactStdinAndPreservesStdoutAndExit() async throws {
        let raw = Data("synthetic payload\n".utf8)
        let success = try await ClaudePriorCommandRunner().runAndPublish(
            command: "/usr/bin/tr a-z A-Z",
            rawInput: raw,
            publication: { true }
        )
        #expect(success.stdout == Data("SYNTHETIC PAYLOAD\n".utf8))
        #expect(success.terminationStatus == 0)
        #expect(success.publicationSucceeded)

        let failure = try await ClaudePriorCommandRunner().runAndPublish(
            command: "printf 'kept output'; exit 7",
            rawInput: raw,
            publication: { true }
        )
        #expect(failure.stdout == Data("kept output".utf8))
        #expect(failure.terminationStatus == 7)
        #expect(failure.publicationSucceeded)

        let noPrior = try await ClaudePriorCommandRunner().runAndPublish(
            command: nil,
            rawInput: raw,
            publication: { false }
        )
        #expect(noPrior.stdout.isEmpty)
        #expect(noPrior.terminationStatus == 0)
        #expect(!noPrior.publicationSucceeded)
    }

    @Test
    func priorCommandSupportsComplexQuotingAndStreamsLargeOutputExactly()
    async throws {
        let quoted = try await ClaudePriorCommandRunner().runAndPublish(
            command: #"IFS= read -r line; printf '<%s>' "$line""#,
            rawInput: Data(#"quote ' and "$HOME" stay data"#.utf8),
            publication: { true }
        )
        #expect(
            quoted.stdout
                == Data(#"<quote ' and "$HOME" stay data>"#.utf8)
        )

        let recorder = LockedDataRecorder()
        let count = ClaudePriorCommandRunner.maximumOutputBytes + 4_096
        let streamed = try await ClaudePriorCommandRunner().runAndPublish(
            command: "/usr/bin/yes x | /usr/bin/head -c \(count)",
            rawInput: Data(),
            outputSink: { recorder.append($0) },
            publication: { true }
        )
        #expect(streamed.stdout.isEmpty)
        #expect(streamed.terminationStatus == 0)
        #expect(streamed.publicationSucceeded)
        #expect(recorder.snapshot().count == count)
    }

    @Test
    func priorCommandCaptureIsBoundedAndCancellationTerminatesPromptly()
    async {
        let oversized = ClaudePriorCommandRunner.maximumOutputBytes + 1
        await #expect(throws: ClaudeStatusLineConfigurationError.recordTooLarge) {
            try await ClaudePriorCommandRunner().runAndPublish(
                command: "/usr/bin/yes x | /usr/bin/head -c \(oversized)",
                rawInput: Data(),
                publication: { true }
            )
        }

        let started = ContinuousClock.now
        let task = Task {
            try await ClaudePriorCommandRunner().runAndPublish(
                command: "exec /bin/sleep 30",
                rawInput: Data(),
                publication: { true }
            )
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(started.duration(to: .now) < .seconds(2))
    }

    @Test
    func priorCommandPolicyRejectsRecursionSecretsAndControlBytes() {
        #expect(
            ClaudePriorCommandPolicy.classify(
                "/synthetic/ClaudeStatusLineRelay"
            ) == .recursive
        )
        #expect(
            ClaudePriorCommandPolicy.classify(
                "export ANTHROPIC_API_KEY=synthetic"
            ) == .unsafeLiteralSecret
        )
        #expect(
            ClaudePriorCommandPolicy.classify("printf 'safe %s'") == .safe
        )
        #expect(
            ClaudePriorCommandPolicy.classify("unsafe\u{0}command")
                == .malformed
        )
    }

    @Test
    func unixSocketIsOwnerOnlyReplacesStaleSocketAndNoOpsWithoutApp()
    async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "m5g2-socket-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("usage.sock")
        let client = ClaudeStatusLineSocketClient(socketURL: socketURL)
        let packet = try decode(
            """
            {"rate_limits":{"five_hour":{
              "used_percentage":42.5,"resets_at":1900001000
            }}}
            """
        )
        #expect(!client.send(packet))

        let server = ClaudeStatusLineSocketServer(socketURL: socketURL)
        let recorder = PacketRecorder()
        try server.start { packet in
            await recorder.append(packet)
        }
        #expect(server.isRunning)
        #expect(client.send(packet))
        for _ in 0..<100 where await recorder.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await recorder.values == [packet])

        let directoryMode = try permissions(of: root)
        let socketMode = try permissions(of: socketURL)
        #expect(directoryMode == 0o700)
        #expect(socketMode == 0o600)
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: socketURL.path))

        try server.start { _ in }
        #expect(client.send(packet))
        server.stop()
    }

    @Test
    func socketBurstIsBoundedAndOneListenerOwnsThePath() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "m5g2-burst-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("usage.sock")
        let server = ClaudeStatusLineSocketServer(socketURL: socketURL)
        let recorder = PacketRecorder()
        try server.start { packet in
            await recorder.append(packet)
        }
        try server.start { _ in
            Issue.record("A second handler must not replace the first")
        }
        let client = ClaudeStatusLineSocketClient(socketURL: socketURL)
        let packet = try decode(
            """
            {"rate_limits":{"seven_day":{
              "used_percentage":7,"resets_at":1900002000
            }}}
            """
        )
        for _ in 0..<16 {
            #expect(client.send(packet))
        }
        for _ in 0..<200 where await recorder.count < 16 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await recorder.count == 16)
        server.stop()
    }

    @Test
    func liveSocketCannotBeReplacedAndStaleSocketCanBeRecovered()
    async throws {
        let root = shortSocketRoot("ownership")
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("usage.sock")
        let first = ClaudeStatusLineSocketServer(socketURL: socketURL)
        let recorder = PacketRecorder()
        try first.start { packet in
            await recorder.append(packet)
        }
        let second = ClaudeStatusLineSocketServer(socketURL: socketURL)
        #expect(throws: ClaudeStatusLineSocketError.socketUnavailable) {
            try second.start { _ in }
        }
        let packet = try decode(
            """
            {"rate_limits":{"five_hour":{
              "used_percentage":12,"resets_at":1900001000
            }}}
            """
        )
        #expect(ClaudeStatusLineSocketClient(socketURL: socketURL).send(packet))
        for _ in 0..<100 where await recorder.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await recorder.count == 1)
        first.stop()

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try makeStaleSocket(at: socketURL)
        let recovered = ClaudeStatusLineSocketServer(socketURL: socketURL)
        try recovered.start { _ in }
        #expect(
            ClaudeStatusLineSocketClient(socketURL: socketURL).send(packet)
        )
        recovered.stop()
    }

    @Test
    func unsafeSocketPathsAreRejectedWithoutDeletion() throws {
        let root = shortSocketRoot("unsafe")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let socketURL = root.appendingPathComponent("usage.sock")
        try Data("preserve".utf8).write(to: socketURL)
        let server = ClaudeStatusLineSocketServer(socketURL: socketURL)
        #expect(throws: ClaudeStatusLineSocketError.unsafeExistingPath) {
            try server.start { _ in }
        }
        #expect(try Data(contentsOf: socketURL) == Data("preserve".utf8))
    }

    @Test
    func stopDoesNotUnlinkAReplacementAtTheOwnedSocketPath() throws {
        let root = shortSocketRoot("replacement")
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("usage.sock")
        let server = ClaudeStatusLineSocketServer(socketURL: socketURL)
        try server.start { _ in }

        #expect(unlink(socketURL.path) == 0)
        let replacement = Data("preserve replacement".utf8)
        try replacement.write(to: socketURL)

        server.stop()
        #expect(try Data(contentsOf: socketURL) == replacement)
    }

    private func decode(_ json: String) throws -> ClaudeStatusLinePacket {
        try ClaudeStatusLineProjection.decode(
            Data(json.utf8),
            observedAt: observation
        )
    }

    private func claudeSnapshot(
        packet: ClaudeStatusLinePacket,
        window: ClaudeStatusLineWindowPacket,
        kind: AgentRateLimitWindow.Kind
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: ClaudeCodeUsageConnector.connectorID,
            providerName: "Claude Code",
            state: .ready,
            capturedAt: packet.observedAt,
            lastSuccessfulAt: packet.observedAt,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialStructuredHook,
                    sourceVersion: "synthetic",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: packet.observedAt,
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: kind.rawValue,
                            kind: kind,
                            usedPercent: window.usedPercentage,
                            isUnlimited: false,
                            resetsAt: Date(
                                timeIntervalSince1970:
                                    TimeInterval(
                                        window.resetsAtEpochSeconds
                                    )
                            )
                        )
                    ],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                )
            ],
            capabilities: [.hiddenFromDesktopAssistant],
            safeFailure: nil
        )
    }

    private func permissions(of url: URL) throws -> UInt16 {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return UInt16(
            try #require(
                attributes[.posixPermissions] as? NSNumber
            ).uint16Value
        )
    }

    private func shortSocketRoot(_ suffix: String) -> URL {
        URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "m5g2-\(suffix)-\(UUID().uuidString)",
                isDirectory: true
            )
    }

    private func makeStaleSocket(at url: URL) throws {
        let pathBytes = Array(url.path.utf8CString)
        var address = sockaddr_un()
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let maximumPathBytes = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= maximumPathBytes else {
            throw ClaudeStatusLineSocketError.pathTooLong
        }
        address.sun_len = UInt8(length)
        address.sun_family = sa_family_t(AF_UNIX)
        url.path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path.0) {
                _ = strlcpy(
                    $0,
                    source,
                    maximumPathBytes
                )
            }
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ClaudeStatusLineSocketError.socketUnavailable
        }
        defer { close(descriptor) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, length)
            }
        }
        guard result == 0, chmod(url.path, 0o600) == 0 else {
            throw ClaudeStatusLineSocketError.socketUnavailable
        }
    }
}

private actor PacketRecorder {
    private(set) var values: [ClaudeStatusLinePacket] = []
    var count: Int { values.count }

    func append(_ packet: ClaudeStatusLinePacket) {
        values.append(packet)
    }
}

private final class LockedDataRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock {
            data.append(chunk)
        }
    }

    func snapshot() -> Data {
        lock.withLock { data }
    }
}
