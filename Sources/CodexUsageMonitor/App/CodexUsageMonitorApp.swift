import AppKit
import CodexUsageUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusBarController: StatusBarController?
    private var wakeRefreshObserver: CodexWakeRefreshObserver?
    private var isDisconnectingForTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(store: store)
        wakeRefreshObserver = CodexWakeRefreshObserver(store: store)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isDisconnectingForTermination else { return .terminateCancel }
        isDisconnectingForTermination = true
        Task { @MainActor [store] in
            await store.stopAllConnectors()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        wakeRefreshObserver?.invalidate()
        wakeRefreshObserver = nil
        statusBarController?.tearDown()
    }
}

@main
enum CodexUsageMonitorApp {
    @MainActor
    static func main() {
        do {
            try UsageTypography.registerBundledFonts()
        } catch {
            fatalError("Roboto registration failed: \(error)")
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
