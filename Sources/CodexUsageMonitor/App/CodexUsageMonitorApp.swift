import AppKit
import CodexUsageUI
import Darwin
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtime: UsageMonitorRuntime?
    private let shellCoordinator = AppShellCoordinator()
    private let shellDiagnosticRequested = CommandLine.arguments.contains("--diagnose-app-shell")
    private var isDisconnectingForTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.unhide(nil)
        // The status item exists before provider composition begins. A failed
        // or slow provider construction can never own the macOS shell.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            do {
                let runtime = try UsageMonitorRuntime.live(
                    bundleIdentifier: Bundle.main.bundleIdentifier,
                    environment: ProcessInfo.processInfo.environment,
                    startProviders: !self.shellDiagnosticRequested
                )
                self.runtime = runtime
                self.shellCoordinator.attach(runtime: runtime)
                if self.shellDiagnosticRequested {
                    let result = await self.shellCoordinator.runMachineDiagnostic(toggleCount: 50)
                    if let data = try? JSONEncoder().encode(result),
                       let json = String(data: data, encoding: .utf8) {
                        print(json)
                    }
                    NSApp.terminate(nil)
                }
            } catch {
                self.shellCoordinator.recordRuntimeAttachmentFailure()
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        sender.unhide(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // The shell-only diagnostic starts no providers and owns no connector
        // shutdown work. Let it exit immediately after emitting its result.
        guard !shellDiagnosticRequested else { return .terminateNow }
        guard !isDisconnectingForTermination else { return .terminateCancel }
        isDisconnectingForTermination = true
        guard let runtime else { return .terminateNow }
        Task { @MainActor [store = runtime.store] in
            await store.stopAllConnectors()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        shellCoordinator.tearDown()
    }
}

@main
enum CodexUsageMonitorApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.contains(
            ClaudeAccuracySyncMachineVerifier.launchArgument
        ) {
            Task { @MainActor in
                let result = await ClaudeAccuracySyncMachineVerifier.runLive(
                    bundleIdentifier: Bundle.main.bundleIdentifier,
                    environment: ProcessInfo.processInfo.environment
                )
                if let data = try? result.encodedJSONLine() {
                    FileHandle.standardOutput.write(data)
                    try? FileHandle.standardOutput.synchronize()
                }
                Darwin.exit(result.processExitCode)
            }
            application.setActivationPolicy(.accessory)
            application.run()
            return
        }
        if CommandLine.arguments.contains(
            where: ClaudeBrowserCompanionMachineVerifier.recognizesLaunchArgument
        ) {
            Task { @MainActor in
                let allowSafariLaunch = CommandLine.arguments.contains(
                    ClaudeBrowserCompanionMachineVerifier.allowSafariLaunchArgument
                )
                if CommandLine.arguments.contains(
                    ClaudeBrowserCompanionMachineVerifier.diagnosticLaunchArgument
                ) {
                    let result = await ClaudeBrowserCompanionMachineVerifier.runDiagnostic(
                        allowSafariLaunch: allowSafariLaunch
                    )
                    if let data = try? result.encodedJSONLine() {
                        FileHandle.standardOutput.write(data)
                        try? FileHandle.standardOutput.synchronize()
                    }
                    Darwin.exit(result.processExitCode)
                }
                _ = await ClaudeBrowserCompanionMachineVerifier.run(
                    allowSafariLaunch: allowSafariLaunch
                )
                application.terminate(nil)
            }
            application.setActivationPolicy(.accessory)
            application.run()
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
