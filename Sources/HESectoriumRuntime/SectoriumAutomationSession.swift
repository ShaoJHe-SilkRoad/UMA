import Foundation
import HESectoriumCore

/// Application lifetime only. Storage policy, deduplication and operations stay
/// in the same persistent controller used by the helper and manual UI actions.
@MainActor
public protocol SectoriumAutomationLifecycle: AnyObject {
    func start()
    func stop()
    func waitForPendingOperations() async
}

@MainActor
public protocol SectoriumAutomationObserving: AnyObject {
    func start()
    func stop()
}

@MainActor
public final class SectoriumAutomationSession: SectoriumAutomationLifecycle {
    public typealias ObserverFactory = @MainActor (@escaping @Sendable (StorageEvent) -> Void) -> (any SectoriumAutomationObserving)?
    private let observerFactory: ObserverFactory
    private let work: AutomationWorkQueue
    private let stopStorageOperations: @Sendable () -> Void
    private let drainStorageOperations: @Sendable () async -> Void
    private var observer: (any SectoriumAutomationObserving)?
    private var started = false

    public init(
        observerFactory: @escaping ObserverFactory,
        startup: @escaping @Sendable () -> Void,
        event: @escaping @Sendable (StorageEvent) -> Void,
        stopStorageOperations: @escaping @Sendable () -> Void = {},
        drainStorageOperations: @escaping @Sendable () async -> Void = {}
    ) {
        self.observerFactory = observerFactory
        self.work = AutomationWorkQueue(startup: startup, event: event)
        self.stopStorageOperations = stopStorageOperations
        self.drainStorageOperations = drainStorageOperations
    }

    public static func live(service: HESectoriumService = .shared) -> SectoriumAutomationSession {
        SectoriumAutomationSession(
            observerFactory: { callback in
                #if canImport(DiskArbitration)
                guard let observer = HESectoriumDiskObserver(service: service, eventHandler: callback) else { return nil }
                return ApplicationDiskObserver(observer)
                #else
                return nil
                #endif
            },
            startup: { _ = service.runApplicationAutomationAtStartup() },
            event: { _ = service.runApplicationAutomation($0) },
            stopStorageOperations: { service.stopAcceptingNewOperations() },
            drainStorageOperations: { await service.waitForPendingOperations() }
        )
    }

    public func start() {
        guard !started else { return }
        started = true
        let generation = work.begin()
        observer = observerFactory { [work] in work.enqueue($0, generation: generation) }
        observer?.start()
    }

    public func stop() {
        guard started else { return }
        started = false
        // Stop accepting new work first; let an already running native operation
        // finish normally instead of cancelling a disk command during app quit.
        work.stopAccepting()
        stopStorageOperations()
        observer?.stop()
        observer = nil
    }

    public func waitForPendingOperations() async {
        await work.waitUntilIdle()
        await drainStorageOperations()
    }
}

#if canImport(DiskArbitration)
@MainActor
private final class ApplicationDiskObserver: SectoriumAutomationObserving {
    private let observer: HESectoriumDiskObserver
    init(_ observer: HESectoriumDiskObserver) { self.observer = observer }
    func start() { observer.start() }
    func stop() { observer.stop() }
}
#endif

/// Serializes app callbacks without holding the UI thread or replacing the
/// cross-process operation lease inside the storage controller.
private final class AutomationWorkQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.openai.uma.sectorium.app-automation", qos: .utility)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var accepting = false
    private let startup: @Sendable () -> Void
    private let event: @Sendable (StorageEvent) -> Void

    init(startup: @escaping @Sendable () -> Void, event: @escaping @Sendable (StorageEvent) -> Void) {
        self.startup = startup
        self.event = event
    }

    func begin() -> UInt64 {
        lock.lock()
        generation &+= 1
        accepting = true
        let current = generation
        lock.unlock()
        queue.async { [self] in
            guard permits(current) else { return }
            startup()
        }
        return current
    }

    func enqueue(_ value: StorageEvent, generation expected: UInt64) {
        lock.lock()
        let current = generation
        let allowed = accepting && current == expected
        lock.unlock()
        guard allowed else { return }
        queue.async { [self] in
            guard permits(current) else { return }
            event(value)
        }
    }

    func stopAccepting() {
        lock.lock()
        accepting = false
        lock.unlock()
    }

    private func permits(_ expected: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return accepting && generation == expected
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}
