import Foundation
import HESectoriumCore
#if canImport(DiskArbitration)
import DiskArbitration
#endif

/// Advances whenever macOS reports any disk appearing, disappearing or changing
/// its description, and whenever this process runs a command that may change
/// disks. A cached metadata read is only as fresh as the clock it was read at.
protocol SectoriumHostChangeClock: AnyObject {
    /// Nil while change reporting is unavailable; nothing may be reused then.
    var generation: UInt64? { get }
    func noteLocalChange()
}

/// Read-only disk metadata (`diskutil list/info -plist`, `diskutil apfs list
/// -plist`, `hdiutil info -plist`) reused across observations in one process.
///
/// Sectorium reads the whole disk inventory many times around one Load or
/// Unload; each read starts one `diskutil` per disk and partition (27 on a
/// typical Mac, about 3 s). The host did not change between those reads, so
/// they can share one answer. An entry is reused only while macOS has reported
/// no disk change, no possibly mutating command has run in this process, and it
/// is younger than `maximumAge`. Failed reads are never reused.
///
/// The change clock is what keeps answers current; `maximumAge` is only a
/// backstop. It must outlast one full observation (about 3 s of sequential
/// `diskutil info` calls), or the first answers expire before the last arrive.
final class SectoriumHostMetadataCache: @unchecked Sendable {
    static let shared = SectoriumHostMetadataCache(clock: SectoriumDiskArbitrationChangeClock.shared)

    private struct Key: Hashable { let executable: String; let arguments: [String] }
    private struct Entry { let outcome: CommandOutcome; let observedAt: TimeInterval; let generation: UInt64 }

    private let clock: SectoriumHostChangeClock?
    private let now: () -> TimeInterval
    private let maximumAge: TimeInterval
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]

    init(clock: SectoriumHostChangeClock?, maximumAge: TimeInterval = 30,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock; self.maximumAge = maximumAge; self.now = now
    }

    /// Commands known not to change disks. Everything else counts as a change.
    static func isSideEffectFree(_ executable: String, _ arguments: [String]) -> Bool {
        if ProcessCommandRunner.isReadOnlyPropertyList(executable: executable, arguments: arguments) { return true }
        switch executable {
        case "/usr/sbin/lsof", "/bin/ps", "/bin/df": return true
        case "/bin/dd": return arguments.contains("of=/dev/null")
        case "/usr/bin/hdiutil":
            return arguments.first == "imageinfo" || arguments.first == "isencrypted"
        case "/usr/sbin/diskutil":
            return arguments == ["image", "attach", "--help"]
        default: return false
        }
    }

    /// Runs `execute`, reusing a fresh enough answer for read-only metadata and
    /// advancing the change clock around any command that may change disks.
    func run(_ executable: String, _ arguments: [String], execute: () -> CommandOutcome) -> CommandOutcome {
        guard ProcessCommandRunner.isReadOnlyPropertyList(executable: executable, arguments: arguments) else {
            guard Self.isSideEffectFree(executable, arguments) else {
                noteChange()
                defer { noteChange() }
                return execute()
            }
            return execute()
        }
        let key = Key(executable: executable, arguments: arguments)
        guard let generation = clock?.generation else { return execute() }
        let started = now()
        lock.lock()
        if let entry = entries[key], entry.generation == generation,
           started >= entry.observedAt, started - entry.observedAt < maximumAge {
            lock.unlock()
            return entry.outcome
        }
        lock.unlock()
        let outcome = execute()
        // A change reported while the command ran makes its answer unusable.
        guard outcome.succeeded, clock?.generation == generation else { return outcome }
        lock.lock()
        if entries.count >= 256 { entries.removeAll() }
        entries[key] = Entry(outcome: outcome, observedAt: started, generation: generation)
        lock.unlock()
        return outcome
    }

    func noteChange() {
        clock?.noteLocalChange()
        lock.lock(); entries.removeAll(); lock.unlock()
    }
}

/// Process-wide DiskArbitration listener. Its generation advances on every
/// disk appearance, disappearance and description change macOS reports.
final class SectoriumDiskArbitrationChangeClock: SectoriumHostChangeClock, @unchecked Sendable {
    static let shared = SectoriumDiskArbitrationChangeClock()

    private let lock = NSLock()
    private var counter: UInt64 = 0
    private var live = false
    #if canImport(DiskArbitration)
    private var session: DASession?
    private let queue = DispatchQueue(label: "com.silkrd.uma.sectorium.host-change-clock")
    #endif

    private init() {
        #if canImport(DiskArbitration)
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, { _, context in
            guard let context else { return }
            Unmanaged<SectoriumDiskArbitrationChangeClock>.fromOpaque(context).takeUnretainedValue().advance()
        }, context)
        DARegisterDiskDisappearedCallback(session, nil, { _, context in
            guard let context else { return }
            Unmanaged<SectoriumDiskArbitrationChangeClock>.fromOpaque(context).takeUnretainedValue().advance()
        }, context)
        // Nil keys: any description change, including mount points and names.
        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { _, _, context in
            guard let context else { return }
            Unmanaged<SectoriumDiskArbitrationChangeClock>.fromOpaque(context).takeUnretainedValue().advance()
        }, context)
        DASessionSetDispatchQueue(session, queue)
        // DiskArbitration replays an "appeared" for every existing disk once a
        // session is scheduled. Reuse starts only after that replay has drained.
        queue.async { [weak self] in self?.markLive() }
        #endif
    }

    var generation: UInt64? {
        lock.lock(); defer { lock.unlock() }
        return live ? counter : nil
    }

    func noteLocalChange() { advance() }

    private func advance() {
        lock.lock(); counter &+= 1; lock.unlock()
    }

    private func markLive() {
        lock.lock(); live = true; counter &+= 1; lock.unlock()
    }
}

/// Warms the shared metadata cache with independent read-only queries run in
/// parallel. Only the production runner does this; fixtures run sequentially.
protocol SectoriumReadOnlyPrefetching: AnyObject {
    func prefetchReadOnly(_ commands: [(executable: String, arguments: [String])], cwd: URL)
}

extension ProcessCommandRunner: SectoriumReadOnlyPrefetching {
    func prefetchReadOnly(_ commands: [(executable: String, arguments: [String])], cwd: URL) {
        let readOnly = commands.filter {
            ProcessCommandRunner.isReadOnlyPropertyList(executable: $0.executable, arguments: $0.arguments)
        }
        guard hasHostCache, readOnly.count > 1 else { return }
        // Each query is a separate diskutil process; eight at a time keeps the
        // whole inventory near one second instead of about three.
        let gate = DispatchSemaphore(value: 8)
        DispatchQueue.concurrentPerform(iterations: readOnly.count) { index in
            gate.wait(); defer { gate.signal() }
            _ = run(readOnly[index].executable, readOnly[index].arguments, cwd: cwd)
        }
    }
}

extension SectoriumObservationCommandRunner: SectoriumReadOnlyPrefetching {
    func prefetchReadOnly(_ commands: [(executable: String, arguments: [String])], cwd: URL) {
        (baseRunner as? SectoriumReadOnlyPrefetching)?.prefetchReadOnly(commands, cwd: cwd)
    }
}
