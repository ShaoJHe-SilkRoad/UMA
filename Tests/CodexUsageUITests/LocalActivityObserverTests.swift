import Foundation
import Testing
@testable import CodexUsageUI

@Suite(.timeLimit(.minutes(1)))
struct LocalActivityObserverTests {
    @Test
    func debouncesBurstsAndRefreshesOnlyTheNamedTail() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("active.jsonl")
        let ledger = directory.appendingPathComponent("ledger.json")
        try sessionFixture(total: 140).write(to: session)

        let reader = CodexLocalActivityReader(sessionRoots: [sessions], ledgerURL: ledger)
        #expect(reader.read(now: fixedDate()).apiEquivalentCost?.observedTokens == 140)

        let deliveries = ChangeDeliveries()
        let observer = reader.makeLocalActivityObserver {
            Task { await deliveries.record() }
        }
        observer.start()
        defer { observer.stop() }

        try sessionFixture(total: 210).write(to: session)
        observer.notifyForTesting(.file(session))
        observer.notifyForTesting(.file(session))
        observer.notifyForTesting(.file(session))
        try await deliveries.waitForCount(1)

        let refreshed = reader.read(now: fixedDate())
        #expect(refreshed.apiEquivalentCost?.observedTokens == 210)
        #expect(refreshed.tasks.first?.totalTokens == 210)
        #expect(await deliveries.count == 1)
    }

    @Test
    func rootInvalidationSafelyRecoversAfterRotationAndTruncation() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let session = sessions.appendingPathComponent("active.jsonl")
        let ledger = directory.appendingPathComponent("ledger.json")
        try sessionFixture(total: 250).write(to: session)

        let reader = CodexLocalActivityReader(
            sessionRoots: [sessions],
            ledgerURL: ledger
        )
        #expect(reader.read(now: fixedDate()).apiEquivalentCost?.observedTokens == 250)

        let deliveries = ChangeDeliveries()
        let observer = reader.makeLocalActivityObserver {
            Task { await deliveries.record() }
        }
        observer.start()
        defer { observer.stop() }

        // A rotated/truncated tail cannot subtract previously accepted local
        // counters or turn into a negative local cost.
        try FileManager.default.moveItem(at: session, to: sessions.appendingPathComponent("active.jsonl.rotated"))
        try sessionFixture(total: 100).write(to: session)
        observer.notifyForTesting(.roots)
        try await deliveries.waitForCount(1)
        #expect(reader.read(now: fixedDate()).apiEquivalentCost?.observedTokens == 250)

        // Once the replacement reaches a new high-water mark, only the new
        // delta is recorded; historic tokens are never repriced.
        try sessionFixture(total: 310).write(to: session)
        observer.notifyForTesting(.file(session))
        try await deliveries.waitForCount(2)
        #expect(reader.read(now: fixedDate()).apiEquivalentCost?.observedTokens == 310)
    }
}

private actor ChangeDeliveries {
    private(set) var count = 0
    private let deliveries = M5AEventCounter()

    func record() {
        count += 1
        deliveries.signal()
    }

    func waitForCount(_ expected: Int) async throws {
        await deliveries.wait(for: expected)
    }
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("local-activity-\(UUID().uuidString)", isDirectory: true)
}

private func fixedDate() -> Date {
    Date(timeIntervalSince1970: 1_784_332_800)
}

private func sessionFixture(total: Int64) -> Data {
    let input = max(0, total - 40)
    return Data(
        """
        {"type":"turn_context","payload":{"model":"gpt-5.6-terra","session_id":"fixture-session"}}
        {"type":"event_msg","timestamp":"2026-07-18T00:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":20,"output_tokens":40,"total_tokens":\(total)}}}}
        """.utf8
    )
}
