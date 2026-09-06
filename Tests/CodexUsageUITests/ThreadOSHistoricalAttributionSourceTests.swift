import Foundation
import Testing
@testable import CodexUsageUI

struct ThreadOSHistoricalAttributionSourceTests {

    @Test
    func alreadyCreatedReaderUsesReplacedSourcesWithoutLaunchingAHelper() {
        let now = Date(timeIntervalSince1970: 1)
        let reader = ReloadableThreadOSHistoricalAttributionSource(FixedAttributionSource(status: .sourceGap))
        #expect(reader.read(now: now).sourceStatus == .sourceGap)
        reader.replace(with: FixedAttributionSource(status: .available))
        #expect(reader.read(now: now).sourceStatus == .available)
        reader.replace(with: FixedAttributionSource(status: .unavailable))
        #expect(reader.read(now: now).sourceStatus == .unavailable)
    }
    @Test
    func acceptsOnlyACompleteBoundedTrustedHelperExport() throws {
        let fixture = try HelperFixture(script: "printf '%s' '" + completeEnvelope + "'")
        defer { fixture.remove() }
        let value = fixture.source().read(now: Date(timeIntervalSince1970: 1))
        #expect(value.sourceStatus == .available)
        #expect(value.rows.count == 1)
    }

    @Test(arguments: ["exit 4", "sleep 1", "printf '%s' 'not-json'", "printf '%s' '" + wrongProjectEnvelope + "'"])
    func discardsExitTimeoutMalformedAndWrongProjectResults(_ command: String) throws {
        let fixture = try HelperFixture(script: command)
        defer { fixture.remove() }
        let value = fixture.source(timeout: 0.02).read(now: Date(timeIntervalSince1970: 1))
        #expect(value.sourceStatus != .available)
        #expect(value.rows.isEmpty)
    }

    @Test
    func discardsOutputOrDiagnosticsBeyondTheFrozenBounds() throws {
        let largeOutput = try HelperFixture(script: "head -c 64001 /dev/zero")
        defer { largeOutput.remove() }
        #expect(largeOutput.source().read(now: Date()).sourceStatus != .available)
        let largeError = try HelperFixture(script: "head -c 4097 /dev/zero >&2")
        defer { largeError.remove() }
        #expect(largeError.source().read(now: Date()).sourceStatus != .available)
    }

    @Test
    func acceptsRepeatedShortLivedCompleteExportsUnderTheFrozenProductionBudget() throws {
        let fixture = try HelperFixture(script: "printf '%s' '" + completeEnvelope + "'")
        defer { fixture.remove() }
        #expect(FoundationThreadOSHistoricalAttributionSource.defaultTimeout == 5)
        for _ in 0..<16 {
            // Exercise the same five-second production budget on every
            // success. A shorter test-only positive timeout would conceal a
            // deadline regression by changing the contract under test.
            let value = fixture.source().read(now: Date())
            #expect(value.sourceStatus == .available)
            #expect(value.rows.count == 1)
        }
    }

    @Test
    func rejectsLateAdmissionWithinTheSinglePreLaunchBudget() throws {
        let fixture = try HelperFixture(script: "sleep 0.04; printf '%s' '" + completeEnvelope + "'")
        defer { fixture.remove() }
        let started = Date()
        let value = fixture.source(timeout: 0.02).read(now: Date(timeIntervalSince1970: 1))
        #expect(value.sourceStatus == .unavailable)
        #expect(value.rows.isEmpty)
        // The small injected budget is only for expiry control. The assertion
        // proves process launch plus admission did not create a second window.
        #expect(Date().timeIntervalSince(started) < 0.25)
    }

    @Test
    func ignoresHelperTerminationHandlingAfterDeadline() throws {
        let fixture = try HelperFixture(script: "trap '' TERM; while :; do sleep 1; done")
        defer { fixture.remove() }
        let started = Date()
        let value = fixture.source(timeout: 0.02).read(now: Date(timeIntervalSince1970: 1))
        #expect(value.sourceStatus == .unavailable)
        #expect(value.rows.isEmpty)
        #expect(Date().timeIntervalSince(started) < 0.25)
    }

    @Test
    func rejectsDelayedEOFWithoutExceedingTheReaderDeadline() throws {
        let fixture = try HelperFixture(script: "printf '%s' '" + completeEnvelope + "'; (sleep 1) &")
        defer { fixture.remove() }
        let started = Date()
        let value = fixture.source(timeout: 0.02).read(now: Date(timeIntervalSince1970: 1))
        #expect(value.sourceStatus == .unavailable)
        #expect(value.rows.isEmpty)
        #expect(Date().timeIntervalSince(started) < 0.25)
    }
}

private struct FixedAttributionSource: ThreadOSHistoricalAttributionReading {
    let status: ThreadOSUsageAnalytics.SourceStatus
    func read(now: Date) -> ThreadOSUsageAnalytics {
        .init(sourceStatus: status, rows: [], unavailableCount: 0, capturedAt: now)
    }
}

private struct HelperFixture {
    let root: URL
    let helper: URL

    init(script: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        helper = root.appendingPathComponent("helper.sh")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "#!/bin/sh\n\(script)\n".data(using: .utf8)!.write(to: helper, options: .atomic)
    }

    func source(timeout: TimeInterval = FoundationThreadOSHistoricalAttributionSource.defaultTimeout) -> FoundationThreadOSHistoricalAttributionSource {
        .init(launch: .init(
            interpreterURL: URL(fileURLWithPath: "/bin/sh"),
            helperURL: helper,
            runtimeRootURL: root,
            journalURL: root.appendingPathComponent("journal.jsonl"),
            projectKey: "TOSUMA",
            projectRootDigest: String(repeating: "c", count: 64),
            journalID: nil
        ), timeout: timeout)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private let completeEnvelope = """
{\"schema\":\"threados.usage-attribution-export.v1\",\"historical_only\":true,\"status\":\"COMPLETE\",\"row_count\":1,\"unavailable_count\":0,\"rows\":[{\"schema\":\"threados.usage-attribution-wire.v1\",\"status\":\"ELIGIBLE_HISTORICAL\",\"observation\":\"validated historical journal observation\",\"project_key\":\"TOSUMA\",\"project_root_digest\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"task_id\":\"TU3\",\"local_role\":\"DEVELOPMENT\",\"thread_digest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"turn_digest\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"correlation_digest\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"attempt_digest\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"destination_readback_digest\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"acknowledgement_digest\":\"1111111111111111111111111111111111111111111111111111111111111111\",\"message_digest\":\"2222222222222222222222222222222222222222222222222222222222222222\"}]}
"""

private let wrongProjectEnvelope = completeEnvelope.replacingOccurrences(of: "\"project_key\":\"TOSUMA\"", with: "\"project_key\":\"OTHER\"")
