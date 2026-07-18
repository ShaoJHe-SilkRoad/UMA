import AppKit

/// Bridges the public workspace wake notification into the same coalesced
/// refresh lane as every other provider-refresh cause. It owns no timer,
/// process, account value, or notification payload.
@MainActor
public final class CodexWakeRefreshObserver {
    private weak var store: UsageStore?
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    public init(
        store: UsageStore,
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak store] _ in
            Task { @MainActor in
                await store?.handleApplicationWake()
            }
        }
    }

    /// The application delegate calls this during termination. Explicit
    /// invalidation avoids retaining an AppKit observer token beyond the
    /// monitor's one app lifecycle.
    public func invalidate() {
        if let observer {
            notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }
}
