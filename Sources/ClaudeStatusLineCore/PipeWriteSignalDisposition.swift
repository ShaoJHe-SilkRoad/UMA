import Darwin

/// Writing to a pipe whose reader has gone raises `SIGPIPE`, and its default
/// disposition terminates the process before the write can report anything at
/// all. Every pipe this product writes to belongs to a child it does not
/// control — a Codex app-server free to exit at any moment, a prior
/// status-line command free to ignore its stdin — so that signal is reachable
/// on any such write, however the surrounding liveness checks are ordered.
///
/// Ignoring it makes the same condition arrive as `EPIPE`, which Foundation's
/// throwing `write(contentsOf:)` reports as an ordinary Swift error the caller
/// can handle. Nothing in this product depends on the default disposition, and
/// no pipe it writes to is one whose death should end the process.
///
/// The disposition is process-global, so it is established exactly once,
/// lazily, by the call sites that are about to write to such a pipe.
public enum PipeWriteSignalDisposition {
    /// `static let` initialisation runs once under `swift_once`, which makes
    /// this both thread-safe and idempotent without a lock of its own. The
    /// previous disposition is discarded: there is nothing to restore it to,
    /// since no code here wants SIGPIPE to end the process.
    private static let ignored: Void = {
        _ = signal(SIGPIPE, SIG_IGN)
    }()

    /// Safe to call from any thread, as often as convenient.
    public static func ensureIgnored() {
        _ = ignored
    }
}
