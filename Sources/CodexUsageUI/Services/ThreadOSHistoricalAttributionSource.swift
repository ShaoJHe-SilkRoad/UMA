import CryptoKit
import Darwin
import Foundation

/// Deliberately configured by a local UMA settings flow. Export bytes never
/// select these paths, identities, or project scope. Missing/changed files
/// fail closed to SOURCE_GAP.
struct ThreadOSHistoricalAttributionBinding: Codable, Sendable, Equatable {
    let interpreterPath: String
    let helperPath: String
    let runtimeRootPath: String
    let journalPath: String
    let projectKey: String
    let projectRootDigest: String
    let interpreterSHA256: String
    let helperSHA256: String
    let journalID: String?

    func launchIfVerified() -> TrustedThreadOSAttributionLaunch? {
        let interpreter = URL(fileURLWithPath: interpreterPath)
        let helper = URL(fileURLWithPath: helperPath)
        guard [interpreterPath, helperPath, runtimeRootPath, journalPath].allSatisfy({ $0.hasPrefix("/") }),
              Self.fileDigest(interpreter) == interpreterSHA256,
              Self.fileDigest(helper) == helperSHA256
        else { return nil }
        let launch = TrustedThreadOSAttributionLaunch(interpreterURL: interpreter, helperURL: helper, runtimeRootURL: URL(fileURLWithPath: runtimeRootPath), journalURL: URL(fileURLWithPath: journalPath), projectKey: projectKey, projectRootDigest: projectRootDigest, journalID: journalID)
        return launch.isValid ? launch : nil
    }

    private static func fileDigest(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum ThreadOSHistoricalAttributionPreferences {
    // Constructed on the caller's actor rather than retained in global state:
    // ApplicationPreferenceKey intentionally carries non-Sendable closures.
    static var binding: ApplicationPreferenceKey<Data?> {
        ApplicationPreferenceKey<Data?>(optionalData: "threadosHistoricalAttributionBinding")
    }
    @MainActor static func source(from preferences: ApplicationPreferences) -> any ThreadOSHistoricalAttributionReading {
        guard let data = preferences.value(for: binding),
              let configured = try? JSONDecoder().decode(ThreadOSHistoricalAttributionBinding.self, from: data),
              let launch = configured.launchIfVerified()
        else { return UnavailableThreadOSHistoricalAttributionSource() }
        return FoundationThreadOSHistoricalAttributionSource(launch: launch)
    }
    /// The supported application-preference setup path. It persists only the
    /// deliberate typed binding; an invalid value is removed rather than
    /// becoming a deferred command or an export-selected configuration.
    @MainActor static func save(_ configured: ThreadOSHistoricalAttributionBinding?, to preferences: ApplicationPreferences) {
        guard let configured else { preferences.remove(binding); return }
        guard let data = try? JSONEncoder().encode(configured) else { return }
        preferences.set(data, for: binding)
    }
}

protocol ThreadOSHistoricalAttributionReading: Sendable { func read(now: Date) -> ThreadOSUsageAnalytics }

/// The normal runtime owns one instance for its lifetime. Preference changes
/// replace only the next read's immutable source under a lock: they neither
/// launch a helper nor create a second connector, timer, or observer.
final class ReloadableThreadOSHistoricalAttributionSource: ThreadOSHistoricalAttributionReading, @unchecked Sendable {
    private let lock = NSLock()
    private var current: any ThreadOSHistoricalAttributionReading

    init(_ source: any ThreadOSHistoricalAttributionReading) {
        current = source
    }

    func replace(with source: any ThreadOSHistoricalAttributionReading) {
        lock.lock()
        current = source
        lock.unlock()
    }

    func read(now: Date) -> ThreadOSUsageAnalytics {
        lock.lock()
        let source = current
        lock.unlock()
        return source.read(now: now)
    }
}

/// Application-owned immutable launch binding. No export payload can replace
/// any selector in this configuration.
struct TrustedThreadOSAttributionLaunch: Sendable, Equatable {
    let interpreterURL: URL
    let helperURL: URL
    let runtimeRootURL: URL
    let journalURL: URL
    let projectKey: String
    let projectRootDigest: String
    let journalID: String?

    var isValid: Bool {
        [interpreterURL, helperURL, runtimeRootURL, journalURL].allSatisfy { $0.isFileURL && $0.path.hasPrefix("/") }
            && ThreadOSHistoricalAttributionDecoder.isToken(projectKey)
            && ThreadOSHistoricalAttributionDecoder.isDigest(projectRootDigest)
            && (journalID.map(ThreadOSHistoricalAttributionDecoder.isToken) ?? true)
    }

    var arguments: [String] {
        var value = [helperURL.path, "--runtime-root", runtimeRootURL.path, "attribution", "export", "--journal-path", journalURL.path]
        if let journalID { value += ["--journal-id", journalID] }
        return value
    }
}

/// A bounded, shell-free reader for a trusted binding. Absence or any process
/// failure remains unavailable; stderr is never retained or presented.
struct FoundationThreadOSHistoricalAttributionSource: ThreadOSHistoricalAttributionReading, @unchecked Sendable {
    let launch: TrustedThreadOSAttributionLaunch
    /// Production callers use the frozen five-second bound. The injected
    /// value exists solely so deterministic process-reader tests do not wait
    /// for the full production deadline.
    let timeout: TimeInterval
    static let defaultTimeout: TimeInterval = 5
    static let stderrLimit = 4_096

    init(launch: TrustedThreadOSAttributionLaunch, timeout: TimeInterval = defaultTimeout) {
        self.launch = launch
        self.timeout = max(0.01, min(timeout, Self.defaultTimeout))
    }

    func read(now: Date) -> ThreadOSUsageAnalytics {
        guard launch.isValid else { return .sourceGap(now: now) }
        // Establish the single monotonic budget before launch. Process setup,
        // launch, stream draining, decoding, and final admission must all fit
        // inside it; no phase is allowed to create a fresh timeout window.
        let deadline = DispatchTime.now() + timeout
        let process = Process(); let stdout = Pipe(); let stderr = Pipe()
        process.executableURL = launch.interpreterURL; process.arguments = launch.arguments
        process.standardOutput = stdout; process.standardError = stderr; process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return .init(sourceStatus: .unavailable, rows: [], unavailableCount: 0, capturedAt: now) }
        // The parent does not write to either pipe. Closing its writer ends
        // makes the reader ownership explicit without affecting child copies.
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        guard DispatchTime.now() < deadline else {
            stop(process, stdout: stdout, stderr: stderr, readers: nil)
            return .init(sourceStatus: .unavailable, rows: [], unavailableCount: 0, capturedAt: now)
        }
        let group = DispatchGroup(); let outputBox = ThreadOSProcessOutputBox()
        group.enter(); DispatchQueue.global(qos: .utility).async { outputBox.read(stdout.fileHandleForReading, limit: ThreadOSHistoricalAttributionDecoder.maximumOutputBytes, stdout: true); group.leave() }
        group.enter(); DispatchQueue.global(qos: .utility).async { outputBox.read(stderr.fileHandleForReading, limit: Self.stderrLimit, stdout: false); group.leave() }
        while process.isRunning && DispatchTime.now() < deadline { Thread.sleep(forTimeInterval: 0.002) }
        if process.isRunning {
            stop(process, stdout: stdout, stderr: stderr, readers: group)
            return .init(sourceStatus: .unavailable, rows: [], unavailableCount: 0, capturedAt: now)
        }
        // A helper can exit while a descendant retains one of its pipe ends.
        // Do not turn that inherited descriptor into an unbounded drain.
        guard group.wait(timeout: deadline) == .success else {
            stop(process, stdout: stdout, stderr: stderr, readers: group)
            return .init(sourceStatus: .unavailable, rows: [], unavailableCount: 0, capturedAt: now)
        }
        let output = outputBox.stdout
        guard !outputBox.stdoutExceeded,
              !outputBox.stderrExceeded,
              process.terminationStatus == 0,
              // Final admission check: an export that completed just after the
              // shared deadline is unavailable, never a late valid sample.
              DispatchTime.now() < deadline
        else { return .init(sourceStatus: .unavailable, rows: [], unavailableCount: 0, capturedAt: now) }
        let decoded = ThreadOSHistoricalAttributionDecoder.decode(output, now: now)
        // Decoding is part of admission too. Do not relabel an expiry as
        // malformed: the bounded reader simply had no timely sample.
        guard DispatchTime.now() < deadline else {
            return .init(sourceStatus: .unavailable, rows: [], unavailableCount: 0, capturedAt: now)
        }
        guard decoded.sourceStatus == .available || decoded.sourceStatus == .truncated,
              decoded.rows.allSatisfy({ $0.projectKey == launch.projectKey && $0.projectRootDigest == launch.projectRootDigest })
        else { return .init(sourceStatus: .malformed, rows: [], unavailableCount: 0, capturedAt: now) }
        return decoded
    }

    private func stop(_ process: Process, stdout: Pipe, stderr: Pipe, readers: DispatchGroup?) {
        if process.isRunning {
            process.terminate()
            let grace = DispatchTime.now() + 0.02
            while process.isRunning && DispatchTime.now() < grace { Thread.sleep(forTimeInterval: 0.001) }
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        }
        // Closing the parent ends releases reads even when a helper descendant
        // inherited stdout/stderr and outlives the directly launched process.
        try? stdout.fileHandleForReading.close()
        try? stderr.fileHandleForReading.close()
        if let readers { _ = readers.wait(timeout: .now() + 0.02) }
    }
}

private final class ThreadOSProcessOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStdout = Data()
    private var didExceedStdout = false
    private var didExceedStderr = false

    func read(_ handle: FileHandle, limit: Int, stdout: Bool) {
        var data = Data()
        var exceeded = false
        while let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty {
            let remaining = limit - data.count
            guard remaining >= chunk.count else {
                if remaining > 0 { data.append(chunk.prefix(remaining)) }
                exceeded = true
                break
            }
            data.append(chunk)
        }
        lock.lock()
        if stdout {
            storedStdout = data
            didExceedStdout = exceeded
        } else {
            didExceedStderr = exceeded
        }
        lock.unlock()
        try? handle.close()
    }
    var stdout: Data { lock.lock(); defer { lock.unlock() }; return storedStdout }
    var stdoutExceeded: Bool { lock.lock(); defer { lock.unlock() }; return didExceedStdout }
    var stderrExceeded: Bool { lock.lock(); defer { lock.unlock() }; return didExceedStderr }
}

struct UnavailableThreadOSHistoricalAttributionSource: ThreadOSHistoricalAttributionReading {
    func read(now: Date) -> ThreadOSUsageAnalytics { .sourceGap(now: now) }
}

extension CodexLocalActivitySnapshot {
    func replacingThreadOSAnalytics(_ analytics: ThreadOSUsageAnalytics) -> Self {
        .init(availability: availability, source: source, scope: scope, capturedAt: capturedAt,
              discoveredFileCount: discoveredFileCount, readableFileCount: readableFileCount,
              excludedFileCount: excludedFileCount, tasks: tasks, apiEquivalentCost: apiEquivalentCost,
              threadOSAnalytics: analytics)
    }
}

/// Decodes bounded bytes from an already admitted producer launcher. It does
/// not select a root, journal, message, attempt, or executable.
enum ThreadOSHistoricalAttributionDecoder {
    static let schema = "threados.usage-attribution-export.v1"
    static let rowSchema = "threados.usage-attribution-wire.v1"
    static let canonicalRoles: Set<String> = ["PRODUCT", "DEVELOPMENT", "QA", "DEBUG", "REVIEW"]
    static let maximumOutputBytes = 64_000
    static let maximumRows = 48
    static func isToken(_ value: String) -> Bool { value.range(of: "\\A[A-Za-z][A-Za-z0-9_-]{0,63}\\z", options: .regularExpression) != nil }
    static func isDigest(_ value: String) -> Bool { value.range(of: "\\A[0-9a-f]{64}\\z", options: .regularExpression) != nil }
    static func decode(_ data: Data, now: Date) -> ThreadOSUsageAnalytics {
        guard data.count <= maximumOutputBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schema == schema, envelope.historicalOnly,
              envelope.rows.count <= maximumRows, envelope.rowCount == envelope.rows.count,
              envelope.unavailableCount >= 0
        else { return .init(sourceStatus: .malformed, rows: [], unavailableCount: 0, capturedAt: now) }
        let rows = envelope.rows.compactMap { Row($0)?.value }
        guard rows.count == envelope.rows.count, Set(rows.map(\.id)).count == rows.count
        else { return .init(sourceStatus: .malformed, rows: [], unavailableCount: 0, capturedAt: now) }
        let status: ThreadOSUsageAnalytics.SourceStatus = envelope.status == "COMPLETE" ? .available : (envelope.status == "TRUNCATED" ? .truncated : .malformed)
        guard status != .malformed else { return .init(sourceStatus: status, rows: [], unavailableCount: 0, capturedAt: now) }
        return .init(sourceStatus: status, rows: rows, unavailableCount: envelope.unavailableCount, capturedAt: now)
    }
    private struct Envelope: Decodable {
        let schema: String; let historicalOnly: Bool; let status: String; let rowCount: Int; let unavailableCount: Int; let rows: [WireRow]
        enum CodingKeys: String, CodingKey { case schema, status, rows; case historicalOnly = "historical_only"; case rowCount = "row_count"; case unavailableCount = "unavailable_count" }
    }
    private struct WireRow: Decodable {
        let schema: String; let status: String; let observation: String; let projectKey: String; let projectRootDigest: String; let taskID: String; let localRole: String; let threadDigest: String; let turnDigest: String; let correlationDigest: String; let attemptDigest: String; let destinationReadbackDigest: String; let acknowledgementDigest: String; let messageDigest: String
        enum CodingKeys: String, CodingKey { case schema, status, observation; case projectKey = "project_key"; case projectRootDigest = "project_root_digest"; case taskID = "task_id"; case localRole = "local_role"; case threadDigest = "thread_digest"; case turnDigest = "turn_digest"; case correlationDigest = "correlation_digest"; case attemptDigest = "attempt_digest"; case destinationReadbackDigest = "destination_readback_digest"; case acknowledgementDigest = "acknowledgement_digest"; case messageDigest = "message_digest" }
    }
    private struct Row {
        let value: ThreadOSUsageAnalytics.Row
        init?(_ row: WireRow) {
            guard row.schema == rowSchema, row.status == "ELIGIBLE_HISTORICAL", row.observation == "validated historical journal observation", ThreadOSHistoricalAttributionDecoder.isToken(row.projectKey), ThreadOSHistoricalAttributionDecoder.isToken(row.taskID), ThreadOSHistoricalAttributionDecoder.canonicalRoles.contains(row.localRole), [row.projectRootDigest, row.threadDigest, row.turnDigest, row.correlationDigest, row.attemptDigest, row.destinationReadbackDigest, row.acknowledgementDigest, row.messageDigest].allSatisfy(ThreadOSHistoricalAttributionDecoder.isDigest) else { return nil }
            value = .init(projectKey: row.projectKey, projectRootDigest: row.projectRootDigest, taskID: row.taskID, localRole: row.localRole, threadDigest: row.threadDigest, turnDigest: row.turnDigest, observation: row.observation, waveID: nil)
        }
    }
}

/// The only permitted producer/local correlation: both producer identity
/// digests must agree with one complete local interval and identify exactly
/// one retained historical row. Zero or multiple rows are deliberately
/// unattributed. This helper does not assign economics; that requires a
/// caller to carry the exact interval delta into an accounting record.
enum ThreadOSHistoricalAttributionMatcher {
    static func uniquelyMatchedRow(
        for interval: ThreadOSLocalIntervalCandidate,
        in analytics: ThreadOSUsageAnalytics
    ) -> ThreadOSUsageAnalytics.Row? {
        // A truncated export is useful for visibility only. It cannot prove
        // complete historical coverage, so it must never allocate economics.
        guard analytics.sourceStatus == .available,
              interval.disposition == .candidate,
              let threadDigest = interval.nativeThreadDigest,
              let turnDigest = interval.turnDigest,
              interval.preceding != nil,
              interval.ending != nil
        else { return nil }
        let matches = analytics.rows.filter {
            $0.threadDigest == threadDigest && $0.turnDigest == turnDigest
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
