import AppKit

/// Application-owned bridge into the existing admitted-provider refresh lane.
/// It owns no timer, process, account value, or notification payload.
@MainActor
public final class CodexWakeRefreshObserver {
    private weak var store: UsageStore?
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
    private var pendingWake: Task<Void, Never>?
    public private(set) var isActive = true

    public init(
        store: UsageStore,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.store = store
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.enqueueWake()
            }
        }
    }

    private func enqueueWake() {
        guard isActive, pendingWake == nil else { return }
        pendingWake = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pendingWake = nil }
            guard self.isActive, !Task.isCancelled else { return }
            await self.store?.handleApplicationWake()
        }
    }

    /// Removes registration and rejects queued deliveries before connector
    /// teardown starts. An already-running delivery is cooperatively cancelled.
    public func invalidate() {
        isActive = false
        if let observer {
            notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        pendingWake?.cancel()
    }

    /// Drain an accepted delivery before stopping its provider runtime. Also
    /// provides an observable completion boundary for injected notifications.
    public func waitForPendingWake() async {
        await pendingWake?.value
    }
}
