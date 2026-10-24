import ClaudeStatusLineCore
import Foundation
import Testing
@testable import CodexUsageUI

/// File changes under `~/.claude` used to start one full local read each.
/// While Claude Code works it appends many times a second, so the reads ran
/// back to back. These pin the lane that replaced that: a burst collapses,
/// the last change is never lost, the status line does not re-read the
/// projects, and stopping drops a read that was still waiting.
@Suite("Claude observed local read lane", .timeLimit(.minutes(1)))
struct ClaudeObservedLocalReadLaneTests {
    private static let interval: TimeInterval = 0.5

    @Test("A burst of changes collapses into at most two reads, and the last change is read")
    func burstCollapses() async throws {
        let probe = LaneReaderProbe()
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            localActivityReader: LaneCountingReader(probe: probe),
            observedLocalReadInterval: Self.interval
        )
        await connector.start()
        #expect(probe.reads == 1)
        let change = try #require(probe.onChange)

        for version in 1...50 {
            probe.version = version
            change()
        }
        // Every change in the burst arrives within one interval, so the lane
        // owes exactly one more read, and that read must see the last version.
        try await waitUntil { probe.lastReadVersion == 50 }
        try await Task.sleep(for: .seconds(Self.interval * 3))
        #expect(probe.reads >= 2)
        #expect(probe.reads <= 3)
        #expect(probe.lastReadVersion == 50)
    }

    @Test("A change within the interval of the last read waits instead of reading")
    func changeWithinIntervalWaits() async throws {
        let probe = LaneReaderProbe()
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            localActivityReader: LaneCountingReader(probe: probe),
            observedLocalReadInterval: 30
        )
        // The read start() makes counts as the last read, so a change a
        // moment later is inside the interval.
        await connector.start()
        let change = try #require(probe.onChange)
        probe.version = 1
        change()
        try await Task.sleep(for: .seconds(1))
        #expect(probe.reads == 1)
        await connector.stop()
    }

    @Test("Stopping drops a read that was still waiting")
    func stopDropsWaitingRead() async throws {
        let probe = LaneReaderProbe()
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            localActivityReader: LaneCountingReader(probe: probe),
            observedLocalReadInterval: Self.interval
        )
        await connector.start()
        let change = try #require(probe.onChange)
        change()
        // Let the change reach the lane, which is now waiting out the interval.
        try await Task.sleep(for: .seconds(Self.interval / 5))
        await connector.stop()
        try await Task.sleep(for: .seconds(Self.interval * 3))
        #expect(probe.reads == 1)
    }

    @Test("A status-line change applies the status file without re-reading the projects")
    func statusLineChangeDoesNotReadProjects() async throws {
        // The status store refuses any path through a symlink, which rules
        // out the temporary directory (/var -> /private/var), so this uses the
        // package's own build directory, as the Local Smart Mode tests do.
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("uma-claude-lane-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let stateDirectory = root.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let statusURL = stateDirectory.appendingPathComponent("status-line.json")
        let probe = LaneReaderProbe()
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            statusStateStore: ClaudeStatusLineStateStore(stateURL: statusURL),
            statusStateMonitor: ClaudeStatusLineStateMonitor(directoryURL: stateDirectory),
            localActivityReader: LaneCountingReader(probe: probe),
            observedLocalReadInterval: Self.interval
        )
        await connector.start()
        #expect(probe.reads == 1)
        #expect((await connector.diagnostics()).lastLiveLinkStage == .localStatusLinePending)

        let receipt = try ClaudeStatusLinePacket(
            claudeVersion: "2.1.0",
            fiveHour: nil,
            sevenDay: nil,
            observedAt: Date()
        )
        try ClaudeStatusLineStateStore(stateURL: statusURL).write(receipt)
        try await waitUntil {
            await connector.diagnostics().lastLiveLinkStage == .localCallbackWithoutQuotaWindows
        }
        try await Task.sleep(for: .seconds(Self.interval * 2))
        #expect(probe.reads == 1)
        await connector.stop()
    }

    private func waitUntil(
        timeout: TimeInterval = 10,
        _ condition: @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Condition not met within \(timeout)s")
    }
}

private final class LaneReaderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var readCount = 0
    private var currentVersion = 0
    private var versionAtLastRead = 0
    private var change: (@Sendable () -> Void)?

    var reads: Int { lock.withLock { readCount } }
    var lastReadVersion: Int { lock.withLock { versionAtLastRead } }
    var version: Int {
        get { lock.withLock { currentVersion } }
        set { lock.withLock { currentVersion = newValue } }
    }
    var onChange: (@Sendable () -> Void)? { lock.withLock { change } }

    func recordRead() {
        lock.withLock {
            readCount += 1
            versionAtLastRead = currentVersion
        }
    }

    func install(_ onChange: @escaping @Sendable () -> Void) {
        lock.withLock { change = onChange }
    }
}

private struct LaneCountingReader: ClaudeLocalActivityObservationProviding {
    let probe: LaneReaderProbe

    func read(now: Date) -> ClaudeLocalActivitySnapshot {
        probe.recordRead()
        return .unavailable(capturedAt: now)
    }

    func makeLocalActivityObserver(
        onChange: @escaping @Sendable () -> Void
    ) -> CodexLocalActivityObserver {
        probe.install(onChange)
        return CodexLocalActivityObserver(
            sessionRoots: [URL(fileURLWithPath: "/private/tmp/uma-claude-lane-no-project-reader")],
            onChange: {}
        )
    }
}
