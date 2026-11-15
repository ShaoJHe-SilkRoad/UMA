import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

private final class FakeChangeClock: SectoriumHostChangeClock, @unchecked Sendable {
    var current: UInt64? = 1
    var generation: UInt64? { current }
    func noteLocalChange() { if let value = current { current = value + 1 } }
}

@Suite("Shared disk metadata cache")
struct SectoriumHostMetadataCacheTests {
    private let list = ("/usr/sbin/diskutil", ["list", "-plist"])

    private func make(_ clock: FakeChangeClock, time: @escaping () -> TimeInterval) -> SectoriumHostMetadataCache {
        SectoriumHostMetadataCache(clock: clock, maximumAge: 2, now: time)
    }

    @Test("An unchanged host answers repeated reads from one command")
    func reusesWhileUnchanged() {
        let clock = FakeChangeClock(); var time: TimeInterval = 100; var runs = 0
        let cache = make(clock) { time }
        for _ in 0..<5 {
            #expect(cache.run(list.0, list.1) { runs += 1; return .success }.succeeded)
            time += 0.3
        }
        #expect(runs == 1)
    }

    @Test("A reported disk change, a disk-changing command or age forces a fresh read")
    func freshAfterChangeMutationOrAge() {
        let clock = FakeChangeClock(); var time: TimeInterval = 100; var runs = 0
        let cache = make(clock) { time }
        _ = cache.run(list.0, list.1) { runs += 1; return .success }
        clock.current = 7 // macOS reported a disk change
        _ = cache.run(list.0, list.1) { runs += 1; return .success }
        #expect(runs == 2)
        _ = cache.run("/usr/sbin/diskutil", ["unmount", "/Volumes/X"]) { .success }
        _ = cache.run(list.0, list.1) { runs += 1; return .success }
        #expect(runs == 3)
        time += 2.5
        _ = cache.run(list.0, list.1) { runs += 1; return .success }
        #expect(runs == 4)
    }

    @Test("Occupancy and read probes do not count as disk changes")
    func sideEffectFreeCommandsKeepTheCache() {
        let clock = FakeChangeClock(); let time: TimeInterval = 100; var runs = 0
        let cache = make(clock) { time }
        _ = cache.run(list.0, list.1) { runs += 1; return .success }
        _ = cache.run("/usr/sbin/lsof", ["-nP", "+f", "--", "/Volumes/X"]) { .success }
        _ = cache.run("/bin/dd", ["if=/dev/rdisk5", "of=/dev/null", "bs=4096", "count=1"]) { .success }
        _ = cache.run(list.0, list.1) { runs += 1; return .success }
        #expect(runs == 1)
        #expect(!SectoriumHostMetadataCache.isSideEffectFree("/bin/dd", ["if=/dev/zero", "of=/dev/rdisk5"]))
        #expect(!SectoriumHostMetadataCache.isSideEffectFree("/usr/bin/hdiutil", ["detach", "/dev/disk5"]))
    }

    @Test("Failed reads, reads during a change and an unavailable change feed are never reused")
    func neverReusesUncertainAnswers() {
        let clock = FakeChangeClock(); let time: TimeInterval = 100; var runs = 0
        let cache = make(clock) { time }
        _ = cache.run(list.0, list.1) { runs += 1; return .init(exitCode: 1, detail: "failed") }
        _ = cache.run(list.0, list.1) { runs += 1; return .success }
        #expect(runs == 2)
        // A change reported while the command ran.
        let fresh = make(FakeChangeClock()) { time }
        var freshRuns = 0
        let freshClock = FakeChangeClock()
        let racing = make(freshClock) { time }
        _ = racing.run(list.0, list.1) { freshRuns += 1; freshClock.current = 9; return .success }
        _ = racing.run(list.0, list.1) { freshRuns += 1; return .success }
        #expect(freshRuns == 2)
        _ = fresh
        // No change feed: every read goes to the host.
        let blind = FakeChangeClock(); blind.current = nil
        let uncached = make(blind) { time }
        var blindRuns = 0
        for _ in 0..<3 { _ = uncached.run(list.0, list.1) { blindRuns += 1; return .success } }
        #expect(blindRuns == 3)
    }
}
