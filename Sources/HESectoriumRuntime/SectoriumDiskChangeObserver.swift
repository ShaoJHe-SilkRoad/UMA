import Foundation
#if canImport(DiskArbitration)
import DiskArbitration
import CoreFoundation
#endif

/// An invalidation hint only. Identifiers may be unavailable during disappearance;
/// consumers must freshly observe state before presenting or executing an action.
public struct SectoriumDiskChange: Equatable, Sendable {
    public enum Kind: String, Sendable { case appeared, disappeared, descriptionChanged }
    public let kind: Kind
    public let bsdName: String?
    public let wholeDiskBSDName: String?
    public let volumeUUID: UUID?
    public let mediaUUID: UUID?
    public init(kind: Kind, bsdName: String? = nil, wholeDiskBSDName: String? = nil,
                volumeUUID: UUID? = nil, mediaUUID: UUID? = nil) {
        self.kind = kind; self.bsdName = bsdName; self.wholeDiskBSDName = wholeDiskBSDName
        self.volumeUUID = volumeUUID; self.mediaUUID = mediaUUID
    }
}

public protocol SectoriumDiskChangeObserving: AnyObject {
    func start()
    func stop()
}

/// Creates an independent, read-only listener. It never enters the automation
/// router. Callbacks arrive serially on a background queue, never the main actor.
public func makeSystemSectoriumDiskChangeObserver(
    onChange: @escaping @Sendable (SectoriumDiskChange) -> Void
) -> (any SectoriumDiskChangeObserving)? {
    #if canImport(DiskArbitration)
    guard let source = SectoriumDADiskChangeSource() else { return nil }
    return SectoriumDiskChangeObserver(source: source, onChange: onChange)
    #else
    return nil
    #endif
}

/// Injectable event boundary: tests supply callbacks without opening a DA session.
protocol SectoriumDiskChangeEventSource: AnyObject {
    func start(_ receive: @escaping @Sendable (SectoriumDiskChange) -> Void)
    func stop()
}

final class SectoriumDiskChangeObserver: SectoriumDiskChangeObserving, @unchecked Sendable {
    private let source: SectoriumDiskChangeEventSource
    private let onChange: @Sendable (SectoriumDiskChange) -> Void
    private let control = NSRecursiveLock()
    private let state = NSLock()
    private var started = false
    private var generation: UInt64 = 0
    private let delivery = DispatchQueue(label: "com.openai.uma.sectorium.disk-changes")
    private let deliveryKey = DispatchSpecificKey<UInt8>()

    init(source: SectoriumDiskChangeEventSource,
         onChange: @escaping @Sendable (SectoriumDiskChange) -> Void) {
        self.source = source; self.onChange = onChange
        delivery.setSpecific(key: deliveryKey, value: 1)
    }
    func start() {
        control.lock(); defer { control.unlock() }
        state.lock()
        guard !started else { state.unlock(); return }
        started = true; generation &+= 1
        let token = generation
        state.unlock()
        source.start { [weak self] change in self?.enqueue(change, token: token) }
    }
    func stop() {
        control.lock()
        state.lock()
        let wasStarted = started
        started = false; generation &+= 1
        state.unlock()
        if wasStarted { source.stop() }
        control.unlock()
        // Do not hold the control lock while waiting: the currently executing
        // client callback is allowed to call stop itself.
        if DispatchQueue.getSpecific(key: deliveryKey) == nil { delivery.sync {} }
    }
    deinit { stop() }

    private func enqueue(_ change: SectoriumDiskChange, token: UInt64) {
        delivery.async { [weak self] in
            guard let self else { return }
            self.state.lock()
            let accepted = self.started && self.generation == token
            self.state.unlock()
            if accepted { self.onChange(change) }
        }
    }
}

#if canImport(DiskArbitration)
private final class SectoriumDADiskChangeSource: SectoriumDiskChangeEventSource, @unchecked Sendable {
    private let session: DASession
    private let queue = DispatchQueue(label: "com.openai.uma.sectorium.disk-change-source")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let lock = NSLock()
    private var receive: (@Sendable (SectoriumDiskChange) -> Void)?
    private var registered = false

    init?() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        self.session = session
        queue.setSpecific(key: queueKey, value: 1)
    }
    func start(_ receive: @escaping @Sendable (SectoriumDiskChange) -> Void) {
        lock.lock(); self.receive = receive; lock.unlock()
        if !registered {
            registered = true
            let context = Unmanaged.passUnretained(self).toOpaque()
            DARegisterDiskAppearedCallback(session, nil, { disk, context in
                guard let context else { return }
                Unmanaged<SectoriumDADiskChangeSource>.fromOpaque(context).takeUnretainedValue()
                    .deliver(disk, kind: .appeared)
            }, context)
            DARegisterDiskDisappearedCallback(session, nil, { disk, context in
                guard let context else { return }
                Unmanaged<SectoriumDADiskChangeSource>.fromOpaque(context).takeUnretainedValue()
                    .deliver(disk, kind: .disappeared)
            }, context)
            let watched = [kDADiskDescriptionVolumePathKey, kDADiskDescriptionVolumeUUIDKey,
                kDADiskDescriptionVolumeNameKey, kDADiskDescriptionVolumeKindKey,
                kDADiskDescriptionVolumeMountableKey, kDADiskDescriptionMediaUUIDKey,
                kDADiskDescriptionMediaBSDNameKey, kDADiskDescriptionMediaWholeKey,
                kDADiskDescriptionMediaWritableKey, kDADiskDescriptionMediaSizeKey, kDADiskDescriptionMediaContentKey,
                kDADiskDescriptionMediaEjectableKey, kDADiskDescriptionDeviceInternalKey] as CFArray
            DARegisterDiskDescriptionChangedCallback(session, nil, watched, { disk, _, context in
                guard let context else { return }
                Unmanaged<SectoriumDADiskChangeSource>.fromOpaque(context).takeUnretainedValue()
                    .deliver(disk, kind: .descriptionChanged)
            }, context)
        }
        DASessionSetDispatchQueue(session, queue)
    }
    func stop() {
        lock.lock(); receive = nil; lock.unlock()
        DASessionSetDispatchQueue(session, nil)
        if DispatchQueue.getSpecific(key: queueKey) == nil { queue.sync {} }
    }
    deinit { stop() }
    private func deliver(_ disk: DADisk, kind: SectoriumDiskChange.Kind) {
        lock.lock(); let callback = receive; lock.unlock()
        guard let callback else { return }
        let description = DADiskCopyDescription(disk) as NSDictionary?
        let whole = DADiskCopyWholeDisk(disk)
        callback(.init(kind: kind, bsdName: DADiskGetBSDName(disk).map { String(cString: $0) },
            wholeDiskBSDName: whole.flatMap { DADiskGetBSDName($0).map { String(cString: $0) } },
            volumeUUID: Self.uuid(description?[kDADiskDescriptionVolumeUUIDKey]),
            mediaUUID: Self.uuid(description?[kDADiskDescriptionMediaUUIDKey])))
    }
    private static func uuid(_ value: Any?) -> UUID? {
        if let uuid = value as? UUID { return uuid }
        if let string = value as? String { return UUID(uuidString: string) }
        guard let value, CFGetTypeID(value as CFTypeRef) == CFUUIDGetTypeID() else { return nil }
        let uuid = unsafeBitCast(value as CFTypeRef, to: CFUUID.self)
        guard let string = CFUUIDCreateString(kCFAllocatorDefault, uuid) else { return nil }
        return UUID(uuidString: string as String)
    }
}
#endif
