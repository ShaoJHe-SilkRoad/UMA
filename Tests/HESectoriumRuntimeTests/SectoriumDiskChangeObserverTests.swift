import Foundation
import Testing
@testable import HESectoriumRuntime

private final class DiskChangeFixtureSource: SectoriumDiskChangeEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [@Sendable (SectoriumDiskChange) -> Void] = []
    private var stopCount = 0
    let didStop = DispatchSemaphore(value: 0)
    var starts: Int { lock.lock(); defer { lock.unlock() }; return callbacks.count }
    var stops: Int { lock.lock(); defer { lock.unlock() }; return stopCount }
    func start(_ receive: @escaping @Sendable (SectoriumDiskChange) -> Void) {
        lock.lock(); callbacks.append(receive); lock.unlock()
    }
    func stop() {
        lock.lock(); stopCount += 1; lock.unlock(); didStop.signal()
    }
    func emit(_ change: SectoriumDiskChange, generation: Int? = nil) {
        lock.lock()
        let callback = callbacks[generation ?? (callbacks.count - 1)]
        lock.unlock(); callback(change)
    }
}

private final class DiskChangeRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SectoriumDiskChange] = []
    let delivered = DispatchSemaphore(value: 0)
    var values: [SectoriumDiskChange] { lock.lock(); defer { lock.unlock() }; return events }
    func append(_ change: SectoriumDiskChange) {
        lock.lock(); events.append(change); lock.unlock(); delivered.signal()
    }
}

private final class DiskChangeObserverReference: @unchecked Sendable {
    var observer: SectoriumDiskChangeObserver?
}

@Suite("Sectorium read-only disk event lifecycle")
struct SectoriumDiskChangeObserverTests {
    @Test func deliversAllKindsWithIdentityAndStartIsIdempotent() {
        let source = DiskChangeFixtureSource(); let record = DiskChangeRecord()
        let observer = SectoriumDiskChangeObserver(source: source) { record.append($0) }
        observer.start(); observer.start()
        let volume = UUID(); let media = UUID()
        let events: [SectoriumDiskChange] = [
            .init(kind: .appeared, bsdName: "disk7s1", wholeDiskBSDName: "disk7", volumeUUID: volume, mediaUUID: media),
            .init(kind: .descriptionChanged, bsdName: "disk7s1", wholeDiskBSDName: "disk7", volumeUUID: volume),
            .init(kind: .disappeared)]
        for event in events { source.emit(event) }
        for _ in events { #expect(record.delivered.wait(timeout: .now() + 3) == .success) }
        observer.stop(); observer.stop()
        #expect(record.values == events)
        #expect(source.starts == 1 && source.stops == 1)
    }

    @Test func stoppedAndPriorGenerationCallbacksCannotPublishAfterRestart() {
        let source = DiskChangeFixtureSource(); let record = DiskChangeRecord()
        let observer = SectoriumDiskChangeObserver(source: source) { record.append($0) }
        observer.start(); observer.stop()
        source.emit(.init(kind: .appeared), generation: 0)
        observer.start()
        source.emit(.init(kind: .disappeared), generation: 0)
        let current = SectoriumDiskChange(kind: .descriptionChanged, bsdName: "disk8")
        source.emit(current, generation: 1)
        #expect(record.delivered.wait(timeout: .now() + 3) == .success)
        observer.stop()
        #expect(record.values == [current])
        #expect(source.starts == 2 && source.stops == 2)
    }

    @Test func stopDrainsExecutingCallbackAndDropsQueuedCallbacks() {
        let source = DiskChangeFixtureSource(); let record = DiskChangeRecord()
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        let observer = SectoriumDiskChangeObserver(source: source) { change in
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
            record.append(change)
        }
        observer.start(); source.emit(.init(kind: .appeared))
        #expect(entered.wait(timeout: .now() + 3) == .success)
        source.emit(.init(kind: .descriptionChanged))
        Thread.detachNewThread { observer.stop(); stopped.signal() }
        #expect(source.didStop.wait(timeout: .now() + 3) == .success)
        #expect(stopped.wait(timeout: .now() + 0.03) == .timedOut)
        release.signal()
        #expect(stopped.wait(timeout: .now() + 3) == .success)
        #expect(record.values == [.init(kind: .appeared)])
    }

    @Test func callbackMayStopItsObserverWithoutDeadlock() {
        let source = DiskChangeFixtureSource(); let record = DiskChangeRecord()
        let reference = DiskChangeObserverReference()
        reference.observer = SectoriumDiskChangeObserver(source: source) { change in
            reference.observer?.stop()
            record.append(change)
        }
        reference.observer?.start(); source.emit(.init(kind: .appeared))
        #expect(record.delivered.wait(timeout: .now() + 3) == .success)
        reference.observer?.stop()
        #expect(source.stops == 1)
        reference.observer = nil
    }

    @Test func deinitStopsSourceAndRetainedOldCallbackCannotResurrectObserver() {
        let source = DiskChangeFixtureSource(); let record = DiskChangeRecord()
        var observer: SectoriumDiskChangeObserver? = SectoriumDiskChangeObserver(source: source) { record.append($0) }
        weak var weakObserver = observer
        observer?.start(); observer = nil
        #expect(weakObserver == nil && source.stops == 1)
        source.emit(.init(kind: .appeared))
        #expect(record.delivered.wait(timeout: .now() + 0.03) == .timedOut)
        #expect(record.values.isEmpty)
    }
}
