import Dispatch
import Foundation
import Darwin

/// A sanitized invalidation from an allowlisted local session root. The value
/// intentionally contains no file content, parsed event, account data, or
/// user-facing identifier.
enum CodexLocalActivityFilesystemChange: Sendable {
    case file(URL)
    case roots
}

/// Watches only declared local Codex session roots. Directory events discover
/// additions/removals; regular-file events identify the one JSONL tail that
/// needs reprocessing. The consumer receives a debounced invalidation only,
/// and must re-read through `CodexLocalActivityReader`'s metadata allowlist.
final class CodexLocalActivityObserver: @unchecked Sendable {
    typealias FilesystemChangeHandler = @Sendable (CodexLocalActivityFilesystemChange) -> Void
    typealias ChangeHandler = @Sendable () -> Void

    private let sessionRoots: [URL]
    private let debounceInterval: TimeInterval
    private let onFilesystemChange: FilesystemChangeHandler
    private let onChange: ChangeHandler
    private let fileManager: FileManager
    private let queue = DispatchQueue(
        label: "com.codexusagemonitor.local-activity-observer",
        qos: .utility
    )
    private let lock = NSLock()
    private var rootSources: [DispatchSourceFileSystemObject] = []
    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingDelivery: DispatchWorkItem?
    private var started = false

    init(
        sessionRoots: [URL],
        debounceInterval: TimeInterval = 0.20,
        fileManager: FileManager = .default,
        onFilesystemChange: @escaping FilesystemChangeHandler = { _ in },
        onChange: @escaping ChangeHandler
    ) {
        self.sessionRoots = sessionRoots.map(\.standardizedFileURL)
        self.debounceInterval = max(0, debounceInterval)
        self.fileManager = fileManager
        self.onFilesystemChange = onFilesystemChange
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        queue.async { [weak self] in self?.installSources() }
    }

    func stop() {
        lock.lock()
        guard started else {
            lock.unlock()
            return
        }
        started = false
        let pending = pendingDelivery
        pendingDelivery = nil
        let roots = rootSources
        rootSources.removeAll()
        let files = Array(fileSources.values)
        fileSources.removeAll()
        lock.unlock()

        pending?.cancel()
        roots.forEach { $0.cancel() }
        files.forEach { $0.cancel() }
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    /// Deterministic test hook. Production changes enter through a Dispatch
    /// file-system source; this hook still exercises the exact recording and
    /// debounce path without depending on kernel delivery timing.
    func notifyForTesting(_ change: CodexLocalActivityFilesystemChange) {
        receive(change)
    }

    private func installSources() {
        guard isRunning else { return }
        for root in sessionRoots { installRootSource(for: root) }
        refreshFileSources()
    }

    private func installRootSource(for root: URL) {
        guard let source = makeSource(
            for: root,
            mask: [.write, .delete, .rename, .attrib, .link, .revoke]
        ) else { return }
        source.setEventHandler { [weak self] in
            self?.receive(.roots)
            self?.queue.async { [weak self] in self?.refreshFileSources() }
        }
        source.resume()
        lock.lock()
        if started {
            rootSources.append(source)
        } else {
            source.cancel()
        }
        lock.unlock()
    }

    private func refreshFileSources() {
        guard isRunning else { return }
        let urls = SessionMetadataScanner.watchableFileURLs(
            roots: sessionRoots,
            fileManager: fileManager
        )
        let newKeys = Set(urls.map { $0.standardizedFileURL.path })

        lock.lock()
        let obsolete = fileSources.keys.filter { !newKeys.contains($0) }
        let obsoleteSources = obsolete.compactMap { fileSources.removeValue(forKey: $0) }
        let existing = Set(fileSources.keys)
        lock.unlock()
        obsoleteSources.forEach { $0.cancel() }

        for url in urls where !existing.contains(url.standardizedFileURL.path) {
            installFileSource(for: url)
        }
    }

    private func installFileSource(for file: URL) {
        guard let source = makeSource(
            for: file,
            mask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke]
        ) else { return }
        source.setEventHandler { [weak self, source] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                self.receive(.roots)
                self.queue.async { [weak self] in self?.refreshFileSources() }
            } else {
                self.receive(.file(file))
            }
        }
        source.resume()
        lock.lock()
        if started {
            fileSources[file.standardizedFileURL.path] = source
        } else {
            source.cancel()
        }
        lock.unlock()
    }

    private func makeSource(
        for url: URL,
        mask: DispatchSource.FileSystemEvent
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: mask,
            queue: queue
        )
        source.setCancelHandler { close(descriptor) }
        return source
    }

    private func receive(_ change: CodexLocalActivityFilesystemChange) {
        onFilesystemChange(change)
        lock.lock()
        guard started else {
            lock.unlock()
            return
        }
        pendingDelivery?.cancel()
        let delivery = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.onChange()
        }
        pendingDelivery = delivery
        lock.unlock()
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: delivery)
    }
}
