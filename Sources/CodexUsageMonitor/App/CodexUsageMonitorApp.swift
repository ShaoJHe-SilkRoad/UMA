import AppKit
import CodexUsageUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime: UsageMonitorRuntime
    private var store: UsageStore { runtime.store }
    private var statusBarController: StatusBarController?
    private var isDisconnectingForTermination = false

    override init() {
        do {
            runtime = try UsageMonitorRuntime.live(
                bundleIdentifier: Bundle.main.bundleIdentifier,
                environment: ProcessInfo.processInfo.environment
            )
        } catch {
            fatalError("Invalid task-owned review store configuration")
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(
            store: store,
            workBuddySettings: runtime.workBuddySettings
        )
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
        statusBarController?.tearDown()
    }
}

@main
enum CodexUsageMonitorApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
