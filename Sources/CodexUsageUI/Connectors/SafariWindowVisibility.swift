import AppKit
import ClaudeSafariHostIPC
import CoreGraphics

/// Safari does not load a page in a window that is on another desktop or
/// minimized, so a Usage tab opened there never reports back. Before each read
/// AUV checks whether Safari has a window on the current desktop; when it has
/// none, the read gets a temporary window of its own.
enum SafariWindowVisibility {
    static let bundleIdentifier = "com.apple.Safari"

    /// A window smaller than this is a panel or a popover, not a browser window.
    private static let minimumWindowSize = CGSize(width: 200, height: 150)

    /// `nil` when Safari is not running. A failed window query counts as
    /// visible, which keeps the read in Safari's existing window as before.
    static func hasWindowOnCurrentDesktop() -> Bool? {
        let processes = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .map(\.processIdentifier)
        )
        guard !processes.isEmpty else { return nil }
        // On-screen windows are those on the current desktop, including ones
        // covered by other apps; minimized windows and other desktops are left
        // out. Owner, layer and bounds need no Screen Recording permission.
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return true }
        return containsBrowserWindow(windows, ownedBy: processes)
    }

    static func containsBrowserWindow(
        _ windows: [[String: Any]],
        ownedBy processes: Set<pid_t>
    ) -> Bool {
        windows.contains { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t,
                  processes.contains(owner),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { return false }
            return bounds.width >= minimumWindowSize.width
                && bounds.height >= minimumWindowSize.height
        }
    }

    static func placement(
        hasWindowOnCurrentDesktop: Bool?
    ) -> ClaudeSafariHostIPCProviderPlacement {
        hasWindowOnCurrentDesktop == false ? .temporaryWindow : .existingWindow
    }
}
