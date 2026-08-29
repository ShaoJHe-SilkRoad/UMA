import ClaudeBrowserBridgeProtocol
import Foundation
import Testing
@testable import ClaudeStatusLineCore
@testable import CodexUsageUI

@Suite("M5RMX Local Smart close security")
struct M5RMXCloseSecurityTests {
    @Test
    func ownedFileReaderRejectsSymlinkReplacementGrowthAndOversize() throws {
        let root = try secureTemporaryDirectory("owned-reader")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("state.json")
        try secureWrite(Data("ok".utf8), to: file)
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: ClaudeOwnedFileReadError.self) {
            _ = try ClaudeOwnedFileReader.read(at: link, maximumBytes: 8)
        }

        #expect(throws: ClaudeOwnedFileReadError.self) {
            _ = try ClaudeOwnedFileReader.read(
                at: file,
                maximumBytes: 8,
                afterOpen: nil,
                afterRead: { try FileHandle(forWritingTo: file).write(contentsOf: Data("x".utf8)) }
            )
        }
        try secureWrite(Data("12345".utf8), to: file)
        #expect(throws: ClaudeOwnedFileReadError.self) {
            _ = try ClaudeOwnedFileReader.read(at: file, maximumBytes: 4)
        }

        try secureWrite(Data("old".utf8), to: file)
        #expect(throws: ClaudeOwnedFileReadError.self) {
            _ = try ClaudeOwnedFileReader.read(
                at: file,
                maximumBytes: 8,
                afterOpen: {
                    try FileManager.default.removeItem(at: file)
                    try secureWrite(Data("new".utf8), to: file)
                },
                afterRead: nil
            )
        }
    }

    @Test
    func localActivityStreamRejectsDescriptorPathMismatchAndPostReadGrowth() throws {
        let root = try secureTemporaryDirectory("local-stream")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("session.jsonl")
        try secureWrite(Data("{}\n".utf8), to: file)
        #expect(!ClaudeLocalActivityReader.streamRecordsForTesting(
            inFileAt: file,
            afterOpen: {
                try? FileManager.default.removeItem(at: file)
                try? secureWrite(Data("{}\n".utf8), to: file)
            },
            consume: { _ in true }
        ))
        try secureWrite(Data("{}\n".utf8), to: file)
        #expect(!ClaudeLocalActivityReader.streamRecordsForTesting(
            inFileAt: file,
            afterRead: {
                if let handle = try? FileHandle(forWritingTo: file) {
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: Data("x".utf8))
                    try? handle.close()
                }
            },
            consume: { _ in true }
        ))
    }

    @Test
    func invalidatedFileCannotLeakAnySanitizedAggregateIntoSnapshot() throws {
        let root = try secureTemporaryDirectory("local-transaction")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("session.jsonl")
        let line = """
        {"type":"assistant","requestId":"transactional-record","timestamp":"2030-03-01T12:00:00Z","message":{"model":"claude-opus-5","usage":{"input_tokens":1200,"output_tokens":300}}}
        """
        try secureWrite(Data((line + "\n").utf8), to: file)
        let reader = ClaudeLocalActivityReader(
            sources: [ClaudeLocalActivityReader.Source(
                surface: .claudeCode,
                rootDirectory: root,
                layout: .projectsRoot
            )],
            afterFileReadForTesting: { changedFile in
                guard changedFile == file,
                      let handle = try? FileHandle(forWritingTo: changedFile)
                else { return }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data("x".utf8))
                try? handle.close()
            }
        )
        let snapshot = reader.read(now: Date(timeIntervalSince1970: 1_898_596_800))
        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.apiEquivalentCost == nil)
        #expect(snapshot.tasks.isEmpty)
        #expect(snapshot.observedSurfaces.isEmpty)
        #expect(snapshot.readableFileCount == 0)
        #expect(snapshot.deduplicationConfidence == .exact)
    }

    @Test
    func browserInboundConsumerPreservesObservationCompletionOrderUnderStress() async {
        let recorder = CloseEventRecorder()
        let consumer = ClaudeBrowserOrderedConsumer { event in
            await recorder.append(event)
        }
        for index in 0..<250 {
            let requestID = "request-\(index)"
            let seed = browserEnvelope(five: 20, seven: 40)
            consumer.submit(.observation(.success(ClaudeBrowserObservationEnvelope(
                browserFamily: seed.browserFamily,
                observation: seed.observation,
                kind: seed.kind,
                schemaVersion: seed.schemaVersion,
                sourceID: seed.sourceID,
                routeState: seed.routeState,
                requestID: requestID,
                observationID: seed.observationID
            ))))
            consumer.submit(.automation(ClaudeBrowserAutomationEvent(
                requestID: requestID,
                status: .refreshCompleted,
                occurredAt: "2030-01-01T00:00:01Z"
            )))
        }
        for _ in 0..<1_000 where await recorder.count < 500 { await Task.yield() }
        let values = await recorder.values
        #expect(values.count == 500)
        for index in 0..<250 {
            #expect(values[index * 2] == "request-\(index):observation")
            #expect(values[index * 2 + 1] == "request-\(index):refreshCompleted")
        }
    }


    @Test
    func accuracyAnchorSaveFailureCannotPublishExactSuccess() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector(anchorStore: FailingCloseAnchorStore())
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 22, seven: 44))
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.acceptedObservationCount == 0)
        #expect(diagnostics.rejectedObservationCount == 1)
        #expect(!diagnostics.currentQuotaIncludesSafariAccuracy)
        #expect(!(await connector.currentSnapshot()).hasValidData)
    }
}

private actor CloseEventRecorder {
    private(set) var values: [String] = []
    var count: Int { values.count }
    func append(_ event: ClaudeBrowserInboundEvent) {
        switch event {
        case let .observation(.success(value)):
            values.append("\(value.requestID):observation")
        case let .automation(value):
            values.append("\(value.requestID):\(value.status.rawValue)")
        case let .dispatchFailure(value):
            values.append("dispatchFailure:\(value)")
        case .observation(.failure):
            values.append("failure")
        }
    }
}

private actor FailingCloseAnchorStore: ClaudeSmartAnchorStoring {
    enum Failure: Error { case refused }
    func load() -> [ClaudeSmartWindowAnchor] { [] }
    func save(_ anchors: [ClaudeSmartWindowAnchor]) throws { throw Failure.refused }
    func clear() throws {}
}

private func secureTemporaryDirectory(_ label: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("uma-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
}

private func secureWrite(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
