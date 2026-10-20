import AppKit
import CodexUsageUI
import Darwin
import Foundation
import HESectoriumRuntime

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    typealias RuntimeFactory = @MainActor (Bool) throws -> UsageMonitorRuntime
    private var runtime: UsageMonitorRuntime?
    private let shellCoordinator: AppShellCoordinator?
    private let shellDiagnosticRequested: Bool
    private let runtimeFactory: RuntimeFactory
    private let wakeNotificationCenter: NotificationCenter
    private let terminationReply: @MainActor (NSApplication) -> Void
    private let storageAutomation: (any SectoriumAutomationLifecycle)?
    private var hasStarted = false
    private var isDisconnectingForTermination = false
    private(set) var wakeObserver: CodexWakeRefreshObserver?
    private(set) var launchTask: Task<Void, Never>?
    private(set) var terminationTask: Task<Void, Never>?

    override convenience init() {
        self.init(
            runtimeFactory: { startProviders in
                try UsageMonitorRuntime.live(
                    bundleIdentifier: Bundle.main.bundleIdentifier,
                    environment: ProcessInfo.processInfo.environment,
                    startProviders: startProviders
                )
            },
            wakeNotificationCenter: NSWorkspace.shared.notificationCenter,
            shellCoordinator: AppShellCoordinator(),
            shellDiagnosticRequested: CommandLine.arguments.contains("--diagnose-app-shell"),
            storageAutomation: SectoriumAutomationSession.live()
        )
    }

    /// The injected composition runs the real delegate lifecycle without
    /// constructing windows, production preferences, or live providers.
    init(
        runtimeFactory: @escaping RuntimeFactory,
        wakeNotificationCenter: NotificationCenter,
        shellCoordinator: AppShellCoordinator? = nil,
        shellDiagnosticRequested: Bool = false,
        storageAutomation: (any SectoriumAutomationLifecycle)? = nil,
        terminationReply: @escaping @MainActor (NSApplication) -> Void = {
            $0.reply(toApplicationShouldTerminate: true)
        }
    ) {
        self.runtimeFactory = runtimeFactory
        self.wakeNotificationCenter = wakeNotificationCenter
        self.shellCoordinator = shellCoordinator
        self.shellDiagnosticRequested = shellDiagnosticRequested
        self.terminationReply = terminationReply
        self.storageAutomation = storageAutomation
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !hasStarted, !isDisconnectingForTermination else { return }
        hasStarted = true
        if !shellDiagnosticRequested { storageAutomation?.start() }
        if let shellCoordinator {
            NSApp.setActivationPolicy(.regular)
            NSApp.unhide(nil)
            shellCoordinator.start(presentMainWindow: !shellDiagnosticRequested)
        }
        // The status item exists before provider composition begins. A failed
        // or slow provider construction can never own the macOS shell.
        launchTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled,
                  !self.isDisconnectingForTermination else { return }
            do {
                let runtime = try self.runtimeFactory(!self.shellDiagnosticRequested)
                self.runtime = runtime
                self.wakeObserver = CodexWakeRefreshObserver(
                    store: runtime.store,
                    notificationCenter: self.wakeNotificationCenter
                )
                self.shellCoordinator?.attach(runtime: runtime)
                if self.shellDiagnosticRequested {
                    await self.finishShellDiagnostic(runtimeAttached: true)
                }
            } catch {
                self.shellCoordinator?.recordRuntimeAttachmentFailure()
                if self.shellDiagnosticRequested {
                    await self.finishShellDiagnostic(runtimeAttached: false)
                }
            }
        }
    }

    private func finishShellDiagnostic(runtimeAttached: Bool) async {
        guard let shellCoordinator else { return }
        let result = await shellCoordinator.runMachineDiagnostic(
            toggleCount: 100,
            runtimeAttached: runtimeAttached
        )
        if var data = try? JSONEncoder().encode(result) {
            data.append(0x0A)
            FileHandle.standardOutput.write(data)
            try? FileHandle.standardOutput.synchronize()
        }
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        sender.unhide(nil)
        shellCoordinator?.showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isDisconnectingForTermination else { return .terminateCancel }
        isDisconnectingForTermination = true
        launchTask?.cancel()
        wakeObserver?.invalidate()
        storageAutomation?.stop()
        // The shell-only diagnostic starts no providers and owns no connector
        // shutdown work. Let it exit immediately after emitting its result.
        guard !shellDiagnosticRequested else { return .terminateNow }
        guard runtime != nil || storageAutomation != nil else { return .terminateNow }
        terminationTask = Task { @MainActor [runtime,
                                            storageAutomation,
                                            observer = wakeObserver,
                                            reply = terminationReply] in
            await observer?.waitForPendingWake()
            await storageAutomation?.waitForPendingOperations()
            await runtime?.shutdown()
            reply(sender)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        isDisconnectingForTermination = true
        launchTask?.cancel()
        wakeObserver?.invalidate()
        storageAutomation?.stop()
        shellCoordinator?.tearDown()
    }
}

@main
enum CodexUsageMonitorApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--release-preview") {
            ReleasePreview.run(application: application)
            return
        }
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
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
