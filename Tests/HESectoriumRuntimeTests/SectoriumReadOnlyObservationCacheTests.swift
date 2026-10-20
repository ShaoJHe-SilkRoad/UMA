import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

struct SectoriumReadOnlyObservationCacheTests {
    private let cwd = URL(fileURLWithPath: "/synthetic/observation")
    private let args = ["info", "-plist", "/dev/disk4"]

    @Test func reusesOnlyWithinOneObservationAndExpires() {
        var time: TimeInterval = 10
        let cache = SectoriumReadOnlyObservationCache(now: { time })
        var calls = 0
        func read() -> CommandOutcome {
            cache.run("/usr/sbin/diskutil", args, cwd: cwd) {
                calls += 1; return .init(exitCode: 0, detail: "observation \(calls)")
            }
        }
        cache.withObservation {
            #expect(read().detail == "observation 1")
            cache.withObservation { #expect(read().detail == "observation 1") }
            time += 2
            #expect(read().detail == "observation 2")
        }
        #expect(read().detail == "observation 3")
        cache.withObservation { #expect(read().detail == "observation 4") }
    }

    @Test func failuresAreNotReusedAndTargetsAndWorkingDirectoriesStaySeparate() {
        let cache = SectoriumReadOnlyObservationCache()
        var calls = 0
        func read(_ target: String, _ directory: URL = URL(fileURLWithPath: "/synthetic/observation"), failure: Bool = false) {
            _ = cache.run("/usr/sbin/diskutil", ["info", "-plist", target], cwd: directory) {
                calls += 1; return .init(exitCode: failure ? 1 : 0, detail: "fixture")
            }
        }
        cache.withObservation {
            read("/dev/disk4", failure: true); read("/dev/disk4", failure: true)
            #expect(calls == 2)
            read("/dev/disk4"); read("/dev/disk4")
            read("/dev/disk5"); read("/dev/disk4", URL(fileURLWithPath: "/synthetic/other"))
            #expect(calls == 5)
        }
    }

    @Test func actionsAndUnknownCommandsInvalidateMetadata() {
        let cache = SectoriumReadOnlyObservationCache()
        var metadataCalls = 0
        var otherCalls = 0
        func read() {
            _ = cache.run("/usr/sbin/diskutil", args, cwd: cwd) {
                metadataCalls += 1; return .init(exitCode: 0, detail: "fixture")
            }
        }
        cache.withObservation {
            read(); read()
            for command in [["eject", "/dev/disk4"], ["unmount", "/dev/disk4s1"]] {
                _ = cache.run("/usr/sbin/diskutil", command, cwd: cwd) {
                    otherCalls += 1; return .init(exitCode: 0, detail: "synthetic action only")
                }
                read()
            }
            _ = cache.run("/usr/bin/hdiutil", ["imageinfo", "/synthetic/image", "-format"], cwd: cwd) {
                otherCalls += 1; return .init(exitCode: 0, detail: "synthetic imageinfo only")
            }
            read()
            cache.invalidate() // Secure/timed runner routes explicitly invalidate too.
            read()
            #expect(metadataCalls == 5)
            #expect(otherCalls == 3)
        }
    }

    @Test func throwingScopeDoesNotLeakAndClockRollbackDoesNotReuse() {
        enum FixtureError: Error { case stop }
        var time: TimeInterval = 10
        let cache = SectoriumReadOnlyObservationCache(now: { time })
        var calls = 0
        func read() {
            _ = cache.run("/usr/sbin/diskutil", args, cwd: cwd) {
                calls += 1; return .init(exitCode: 0, detail: "fixture")
            }
        }
        do {
            try cache.withObservation {
                read(); time = 9; read()
                throw FixtureError.stop
            }
        } catch {}
        read(); read()
        #expect(calls == 4)
    }

    @Test func anotherThreadCannotReadAnActiveObservation() {
        let cache = SectoriumReadOnlyObservationCache()
        let done = DispatchSemaphore(value: 0)
        // The cache has immutable ownership; each thread stores entries separately.
        final class Shared: @unchecked Sendable {
            let cache: SectoriumReadOnlyObservationCache
            init(_ cache: SectoriumReadOnlyObservationCache) { self.cache = cache }
        }
        let shared = Shared(cache)
        cache.withObservation {
            let first = cache.run("/usr/sbin/diskutil", args, cwd: cwd) { .init(exitCode: 0, detail: "first thread") }
            #expect(first.detail == "first thread")
            Thread.detachNewThread {
                let second = shared.cache.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/disk4"],
                                       cwd: URL(fileURLWithPath: "/synthetic/observation")) {
                    .init(exitCode: 0, detail: "fresh on second thread")
                }
                #expect(second.detail == "fresh on second thread")
                done.signal()
            }
            #expect(done.wait(timeout: .now() + 5) == .success)
        }
    }
}
