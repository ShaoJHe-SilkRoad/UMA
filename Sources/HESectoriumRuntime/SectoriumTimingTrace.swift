import Foundation

/// Step timing for one user action (Load, Unload, Disconnect), written to
/// `Logs/sectorium-timing.log`. While an action is traced, every system command
/// AUV runs is recorded with its start offset, duration and exit status, so the
/// time between a click and the result can be attributed to commands, waits for
/// the macOS approval, or AUV's own work in the gaps between them. Commands run
/// outside a traced action are not recorded. Standard input is never logged.
public final class SectoriumTimingTrace: @unchecked Sendable {
    public static let shared = SectoriumTimingTrace()

    private struct Active {
        let name: String
        let startedAt: Date
        let start: UInt64
        var lines: [String] = []
        var commands = 0
        var commandNanos: UInt64 = 0
        var closing = false
    }

    private let lock = NSLock()
    private var active: Active?
    private var logDirectory: URL?
    private let maximumBytes = 1_048_576
    /// Commands from the refresh that follows a result are still attributed to
    /// the action for this long after its result is shown.
    var trailingWindow: TimeInterval = 3

    init() {}

    public func configure(logDirectory: URL) {
        lock.lock(); self.logDirectory = logDirectory; lock.unlock()
    }

    /// Starts a trace. One still open (an action that was cancelled or never
    /// reached a result) is written first, marked as unfinished.
    public func begin(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        if let previous = active {
            if !previous.closing { appendLocked("· not finished: superseded by \(name)") }
            flushLocked(active ?? previous)
        }
        active = Active(name: name, startedAt: Date(), start: DispatchTime.now().uptimeNanoseconds)
    }

    public func mark(_ label: String) {
        lock.lock(); defer { lock.unlock() }
        appendLocked("· \(label)")
    }

    /// Records the visible result, then closes the trace after a short window
    /// so the follow-up refresh is attributed too.
    public func end(_ summary: String) {
        lock.lock()
        guard var current = active, !current.closing else { lock.unlock(); return }
        current.closing = true
        active = current
        appendLocked("= \(summary)")
        let window = trailingWindow
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + window) { [weak self] in
            self?.closeIfStillClosing(startedAt: current.startedAt)
        }
    }

    /// Called by the command runner. Returns a token to pass to `finishCommand`.
    func startCommand() -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        return active == nil ? nil : DispatchTime.now().uptimeNanoseconds
    }

    func finishCommand(_ token: UInt64?, executable: String, arguments: [String], exitCode: Int32) {
        guard let token else { return }
        let end = DispatchTime.now().uptimeNanoseconds
        lock.lock(); defer { lock.unlock() }
        guard var current = active, token >= current.start else { return }
        let duration = end > token ? end - token : 0
        current.commands += 1
        current.commandNanos += duration
        active = current
        let command = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " ")
        let shown = command.count > 220 ? String(command.prefix(220)) + "…" : command
        let status = exitCode == 0 ? "" : "  exit \(exitCode)"
        appendLocked(String(format: "%@ +%@  %@%@", Self.milliseconds(token - current.start),
                            Self.milliseconds(duration), shown, status))
    }

    private func appendLocked(_ text: String) {
        guard var current = active else { return }
        let offset = DispatchTime.now().uptimeNanoseconds - current.start
        // Command lines carry their own start offset; marks are stamped now.
        let line = text.hasPrefix("·") || text.hasPrefix("=") ? "\(Self.milliseconds(offset)) \(text)" : text
        current.lines.append(line)
        active = current
    }

    private func closeIfStillClosing(startedAt: Date) {
        lock.lock(); defer { lock.unlock() }
        guard let current = active, current.closing, current.startedAt == startedAt else { return }
        flushLocked(current)
        active = nil
    }

    private func flushLocked(_ trace: Active) {
        guard let directory = logDirectory else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var text = "\n## \(trace.name) — \(formatter.string(from: trace.startedAt))\n"
        text += "offset(ms) +duration(ms)  command; · mark; = result\n"
        text += trace.lines.joined(separator: "\n") + "\n"
        text += "\(trace.commands) commands, \(Self.milliseconds(trace.commandNanos)) ms in commands (concurrent commands overlap)\n"
        let url = directory.appendingPathComponent("sectorium-timing.log")
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maximumBytes {
            let previous = directory.appendingPathComponent("sectorium-timing.1.log")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: url, to: previous)
        }
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Writes any open trace now. Used by tests and at shutdown.
    func flush() {
        lock.lock(); defer { lock.unlock() }
        if let current = active { flushLocked(current); active = nil }
    }

    static func milliseconds(_ nanos: UInt64) -> String {
        String(format: "%7.0f", Double(nanos) / 1_000_000)
    }
}
