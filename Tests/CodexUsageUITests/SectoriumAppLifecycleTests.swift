import AppKit
import Foundation
import Testing
import HESectoriumRuntime
@testable import CodexUsageMonitor

@Suite("Sectorium app startup and graceful shutdown")
@MainActor
struct SectoriumAppLifecycleTests {
    @Test
    func appStartsAutomationOnceAndWaitsForItEvenIfUsageProviderFails() async {
        let automation = ApplicationAutomationFixture()
        var replied = false
        let delegate = AppDelegate(
            runtimeFactory: { _ in throw ApplicationAutomationError.fixtureProviderUnavailable },
            wakeNotificationCenter: NotificationCenter(),
            storageAutomation: automation,
            terminationReply: { _ in replied = true }
        )
        let launch = Notification(name: NSApplication.didFinishLaunchingNotification)
        delegate.applicationDidFinishLaunching(launch)
        delegate.applicationDidFinishLaunching(launch)
        await delegate.launchTask?.value
        #expect(automation.starts == 1)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        for _ in 0..<1_000 where !automation.waiting { await Task.yield() }
        #expect(automation.waiting)
        #expect(!replied)
        #expect(automation.stops == 1)
        automation.finish()
        await delegate.terminationTask?.value
        #expect(replied)
    }

    @Test
    func shellDiagnosticNeverStartsStorageAutomation() async {
        let automation = ApplicationAutomationFixture()
        let delegate = AppDelegate(
            runtimeFactory: { _ in throw ApplicationAutomationError.fixtureProviderUnavailable },
            wakeNotificationCenter: NotificationCenter(),
            shellDiagnosticRequested: true,
            storageAutomation: automation,
            terminationReply: { _ in }
        )
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate.launchTask?.value
        #expect(automation.starts == 0)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(!automation.waiting)
    }
}

private enum ApplicationAutomationError: Error { case fixtureProviderUnavailable }

@MainActor
private final class ApplicationAutomationFixture: SectoriumAutomationLifecycle {
    var starts = 0
    var stops = 0
    var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func waitForPendingOperations() async {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}
