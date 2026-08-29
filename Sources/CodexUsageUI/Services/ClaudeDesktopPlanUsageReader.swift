import Darwin
import Dispatch
import Foundation

/// Sanitized projection of Claude Desktop's version-pinned local plan cache.
///
/// This is an estimated source. It deliberately carries no organization,
/// account, reset, history, or raw provider value.
struct ClaudeDesktopPlanUsageSnapshot: Equatable, Sendable {
    let observedAt: Date
    let fiveHourRemainingPercent: Double
    let sevenDayRemainingPercent: Double

    func value(for kind: AgentRateLimitWindow.Kind) -> ClaudeSmartWindowValue? {
        let remaining: Double
        switch kind {
        case .fiveHour:
            remaining = fiveHourRemainingPercent
        case .sevenDay:
            remaining = sevenDayRemainingPercent
        case .other:
            return nil
        }
        return ClaudeSmartWindowValue(
            windowKind: kind,
            remainingPercent: remaining,
            resetsAt: nil,
            observedAt: observedAt,
            source: .estimatedDesktopCache,
            confidence: .low
        )
    }
}

protocol ClaudeDesktopPlanUsageReading: Sendable {
    func read(now: Date) -> ClaudeDesktopPlanUsageSnapshot?
}

protocol ClaudeDesktopPlanUsageObservationProviding: ClaudeDesktopPlanUsageReading {
    func makeMonitor(
        onChange: @escaping @Sendable () -> Void
    ) -> ClaudeDesktopPlanUsageMonitor
}

/// Strict reader for one exact, Founder-authorized provider-owned cache.
///
/// The entire file is bounded before decoding. Only the newest timestamped sample
/// is projected, and `org` is type-checked then discarded without being copied
/// into any UMA model. `fh` and `sd` are provider utilization percentages and
/// are converted exactly once to visibly estimated remaining percentages.
struct ClaudeDesktopPlanUsageReader: ClaudeDesktopPlanUsageObservationProviding {
    enum Contract {
        static let schemaVersion = 2
        static let maximumBytes = 512 * 1_024
        static let maximumSampleCount = 4_096
        static let maximumSampleAge: TimeInterval = 20 * 60
        static let maximumFutureSkew: TimeInterval = 30
    }

    private let fileURL: URL

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
            .appendingPathComponent("plan-usage-history.json")
    ) {
        self.fileURL = fileURL.standardizedFileURL
    }

    func makeMonitor(
        onChange: @escaping @Sendable () -> Void
    ) -> ClaudeDesktopPlanUsageMonitor {
        ClaudeDesktopPlanUsageMonitor(fileURL: fileURL, onChange: onChange)
    }

    func read(now: Date = Date()) -> ClaudeDesktopPlanUsageSnapshot? {
        guard let data = Self.readSafeBoundedData(fileURL),
              let projection = try? JSONDecoder().decode(
                  CacheProjection.self,
                  from: data
              ),
              projection.version == Contract.schemaVersion,
              projection.newestSample.timestampMilliseconds >= 0,
              let fiveHourUsed = Self.finite(projection.newestSample.fiveHourUsed),
              let sevenDayUsed = Self.finite(projection.newestSample.sevenDayUsed),
              (0...100).contains(fiveHourUsed),
              (0...100).contains(sevenDayUsed)
        else { return nil }

        // The provider-owned v2 cache stores epoch milliseconds.
        let observedAt = Date(
            timeIntervalSince1970: projection.newestSample.timestampMilliseconds / 1_000
        )
        let age = now.timeIntervalSince(observedAt)
        guard observedAt.timeIntervalSince1970.isFinite,
              age >= -Contract.maximumFutureSkew,
              age <= Contract.maximumSampleAge
        else { return nil }

        return ClaudeDesktopPlanUsageSnapshot(
            observedAt: observedAt,
            fiveHourRemainingPercent: 100 - fiveHourUsed,
            sevenDayRemainingPercent: 100 - sevenDayUsed
        )
    }

    private struct ExactKey: CodingKey, Hashable {
        let stringValue: String
        let intValue: Int? = nil

        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }

    private struct SampleProjection: Decodable {
        let timestampMilliseconds: Double
        let fiveHourUsed: Double
        let sevenDayUsed: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: ExactKey.self)
            try requireKeys(container.allKeys, exactly: ["t", "org", "u"], decoder: decoder)
            timestampMilliseconds = try container.decode(
                Double.self,
                forKey: ExactKey("t")
            )
            let organizationKey = ExactKey("org")
            if try !container.decodeNil(forKey: organizationKey) {
                // Type-check the provider field, then discard it immediately.
                _ = try container.decode(String.self, forKey: organizationKey)
            }
            let utilization = try container.nestedContainer(
                keyedBy: ExactKey.self,
                forKey: ExactKey("u")
            )
            try requireKeys(
                utilization.allKeys,
                exactly: ["fh", "sd"],
                decoder: decoder
            )
            fiveHourUsed = try utilization.decode(
                Double.self,
                forKey: ExactKey("fh")
            )
            sevenDayUsed = try utilization.decode(
                Double.self,
                forKey: ExactKey("sd")
            )
        }
    }

    private struct CacheProjection: Decodable {
        let version: Int
        let newestSample: SampleProjection

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: ExactKey.self)
            try requireKeys(
                container.allKeys,
                exactly: ["version", "samples"],
                decoder: decoder
            )
            version = try container.decode(Int.self, forKey: ExactKey("version"))
            var samples = try container.nestedUnkeyedContainer(
                forKey: ExactKey("samples")
            )
            var newest: SampleProjection?
            var newestTimestampIsAmbiguous = false
            var count = 0
            while !samples.isAtEnd {
                count += 1
                guard count <= Contract.maximumSampleCount else {
                    throw DecodingError.dataCorruptedError(
                        in: samples,
                        debugDescription: "sample count exceeds contract"
                    )
                }
                // Decode one record at a time and retain only the strict
                // projection with the greatest timestamp. Array order is not
                // an ordering contract.
                let candidate = try samples.decode(SampleProjection.self)
                if let current = newest {
                    if candidate.timestampMilliseconds > current.timestampMilliseconds {
                        newest = candidate
                        newestTimestampIsAmbiguous = false
                    } else if candidate.timestampMilliseconds == current.timestampMilliseconds {
                        newestTimestampIsAmbiguous = true
                    }
                } else {
                    newest = candidate
                }
            }
            guard let newest else {
                throw DecodingError.dataCorruptedError(
                    in: samples,
                    debugDescription: "cache has no samples"
                )
            }
            guard !newestTimestampIsAmbiguous else {
                throw DecodingError.dataCorruptedError(
                    in: samples,
                    debugDescription: "cache newest timestamp is ambiguous"
                )
            }
            newestSample = newest
        }
    }

    private static func requireKeys(
        _ keys: [ExactKey],
        exactly expected: Set<String>,
        decoder: Decoder
    ) throws {
        guard Set(keys.map(\.stringValue)) == expected else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "cache key contract mismatch"
                )
            )
        }
    }

    private static func finite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }

    private static func readSafeBoundedData(_ url: URL) -> Data? {
        let standardized = url.standardizedFileURL
        guard standardized.path == url.path,
              standardized.resolvingSymlinksInPath().path == standardized.path
        else { return nil }

        let descriptor = open(standardized.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1,
              (info.st_mode & 0o777) == 0o600,
              info.st_size > 0,
              info.st_size <= Int64(Contract.maximumBytes)
        else { return nil }

        let expectedSize = Int(info.st_size)
        var data = Data(count: expectedSize)
        let readSucceeded = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < expectedSize {
                let count = Darwin.read(
                    descriptor,
                    base.advanced(by: offset),
                    expectedSize - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            var trailingByte: UInt8 = 0
            let trailingCount = Darwin.read(descriptor, &trailingByte, 1)
            return trailingCount == 0
        }
        guard readSucceeded else { return nil }

        var finalInfo = stat()
        guard fstat(descriptor, &finalInfo) == 0,
              (finalInfo.st_mode & S_IFMT) == S_IFREG,
              finalInfo.st_uid == getuid(),
              finalInfo.st_nlink == 1,
              (finalInfo.st_mode & 0o777) == 0o600,
              finalInfo.st_size > 0,
              finalInfo.st_size <= Int64(Contract.maximumBytes),
              finalInfo.st_ino == info.st_ino,
              finalInfo.st_size == info.st_size,
              finalInfo.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
              finalInfo.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec,
              finalInfo.st_ctimespec.tv_sec == info.st_ctimespec.tv_sec,
              finalInfo.st_ctimespec.tv_nsec == info.st_ctimespec.tv_nsec
        else { return nil }
        return data
    }
}

/// Metadata-only invalidation for the one authorized cache path. It never
/// enumerates the containing directory and never opens the cache itself.
/// Changed metadata refreshes the estimate, but is deliberately not classified
/// as a Claude Desktop response or activity event: the provider does not
/// promise a one-write-per-action cache contract.
final class ClaudeDesktopPlanUsageMonitor: @unchecked Sendable {
    private struct Signature: Equatable {
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
    }

    static let interval: TimeInterval = 15

    private let fileURL: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "uma.claude-desktop-plan-usage")
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var signature: Signature?

    init(fileURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.fileURL = fileURL.standardizedFileURL
        self.onChange = onChange
    }

    func start() {
        lock.lock()
        guard timer == nil else {
            lock.unlock()
            return
        }
        signature = Self.signature(of: fileURL)
        let next = DispatchSource.makeTimerSource(queue: queue)
        next.schedule(
            deadline: .now() + Self.interval,
            repeating: Self.interval,
            leeway: .seconds(2)
        )
        next.setEventHandler { [weak self] in self?.poll() }
        timer = next
        lock.unlock()
        next.resume()
    }

    func stop() {
        lock.lock()
        let current = timer
        timer = nil
        signature = nil
        lock.unlock()
        current?.cancel()
    }

    deinit { stop() }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timer != nil
    }

    func notifyForTesting() { onChange() }

    static func acceptsPathForTesting(_ url: URL) -> Bool {
        signature(of: url) != nil
    }

    private func poll() {
        let next = Self.signature(of: fileURL)
        lock.lock()
        guard timer != nil else {
            lock.unlock()
            return
        }
        let changed = next != signature
        signature = next
        lock.unlock()
        if changed { onChange() }
    }

    private static func signature(of url: URL) -> Signature? {
        let standardized = url.standardizedFileURL
        guard standardized.path == url.path,
              standardized.resolvingSymlinksInPath().path == standardized.path
        else { return nil }

        var info = stat()
        guard lstat(standardized.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_nlink == 1,
              (info.st_mode & 0o777) == 0o600,
              info.st_size > 0,
              info.st_size <= Int64(ClaudeDesktopPlanUsageReader.Contract.maximumBytes)
        else { return nil }
        return Signature(
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec)
        )
    }
}
