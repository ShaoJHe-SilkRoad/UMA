import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

@Suite("Sectorium application automation lifecycle")
@MainActor
struct SectoriumAutomationSessionTests {
    @Test
    func startupRunsOnceWithoutOpeningAWindowAndArrivalsUseSameQueue() async {
        let recorded = AutomationRecordedCalls()
        let observer = AutomationFixtureObserver()
        let session = SectoriumAutomationSession(
            observerFactory: { observer.callback = $0; return observer },
            startup: { recorded.append("startup") },
            event: { _ in recorded.append("event") }
        )
        session.start()
        session.start()
        observer.callback?(.imageChanged)
        observer.callback?(.imageChanged)
        await session.waitForPendingOperations()
        #expect(recorded.calls == ["startup", "event", "event"])
        #expect(observer.starts == 1)
        session.stop()
        session.stop()
        observer.callback?(.imageChanged)
        await session.waitForPendingOperations()
        #expect(recorded.calls.count == 3)
        #expect(observer.stops == 1)
    }

    @Test
    func restartRejectsAnOldObserverCallback() async {
        let recorded = AutomationRecordedCalls()
        var observers: [AutomationFixtureObserver] = []
        let session = SectoriumAutomationSession(
            observerFactory: { callback in
                let value = AutomationFixtureObserver()
                value.callback = callback
                observers.append(value)
                return value
            },
            startup: { recorded.append("startup") },
            event: { _ in recorded.append("event") }
        )
        session.start()
        await session.waitForPendingOperations()
        session.stop()
        session.start()
        observers[0].callback?(.imageChanged)
        observers[1].callback?(.imageChanged)
        await session.waitForPendingOperations()
        #expect(recorded.calls == ["startup", "startup", "event"])
        session.stop()
    }

    @Test
    func unavailableObserverStillPerformsOneStartupCheck() async {
        let recorded = AutomationRecordedCalls()
        let session = SectoriumAutomationSession(
            observerFactory: { _ in nil },
            startup: { recorded.append("startup") },
            event: { _ in recorded.append("unexpected") }
        )
        session.start()
        await session.waitForPendingOperations()
        session.stop()
        #expect(recorded.calls == ["startup"])
    }

    @Test
    func stoppingDuringAnOperationClosesAdmissionAndDrainsWithoutCancelling() async {
        let recorded = AutomationRecordedCalls()
        let observer = AutomationFixtureObserver()
        let gate = DispatchSemaphore(value: 0)
        let (started, signal) = AsyncStream<Void>.makeStream()
        let session = SectoriumAutomationSession(
            observerFactory: { observer.callback = $0; return observer },
            startup: {
                recorded.append("running")
                signal.yield(())
                gate.wait()
                recorded.append("finished")
            },
            event: { _ in recorded.append("unexpected-event") },
            stopStorageOperations: { recorded.append("admission-closed") },
            drainStorageOperations: { recorded.append("drained") }
        )
        session.start()
        for await _ in started { break }
        observer.callback?(.imageChanged)
        session.stop()
        #expect(recorded.calls == ["running", "admission-closed"])
        observer.callback?(.imageChanged)
        gate.signal()
        await session.waitForPendingOperations()
        #expect(recorded.calls == ["running", "admission-closed", "finished", "drained"])
        signal.finish()
    }

    @Test
    func shutdownAlsoDrainsManualOperationsFromTheSharedService() async {
        let recorded = AutomationRecordedCalls()
        let session = SectoriumAutomationSession(
            observerFactory: { _ in nil },
            startup: { recorded.append("startup") },
            event: { _ in },
            drainStorageOperations: { recorded.append("shared-service-drained") }
        )
        session.start()
        await session.waitForPendingOperations()
        session.stop()
        await session.waitForPendingOperations()
        #expect(recorded.calls == ["startup", "shared-service-drained", "shared-service-drained"])
    }
}

@MainActor
private final class AutomationFixtureObserver: SectoriumAutomationObserving {
    var callback: (@Sendable (StorageEvent) -> Void)?
    var starts = 0
    var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

private final class AutomationRecordedCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var calls: [String] { lock.lock(); defer { lock.unlock() }; return values }
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; values.append(value) }
}
