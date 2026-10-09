import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import HESectoriumCore
import HESectoriumRuntime
import SwiftUI
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI


// These types deliberately live outside the @MainActor test suite. Dispatch
// invokes the watchdog on a utility queue; inheriting the suite's isolation
// causes a runtime executor trap before a timeout can be recorded.
private final class NativeKeyNotificationLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func record() { lock.lock(); value += 1; lock.unlock() }
}

private final class NativeEntryRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var fixtureFinished = false
    private var watchdogFired = false
    private var sealed = false
    private var deadlineWriteError: String?
    private var fixtureError: String?
    private var completionClaimed = false
    private var loopStarted = false
    private var callbackOnMainThread: Bool?

    func markLoopStarted() { lock.withLock { loopStarted = true } }
    func hasLoopStarted() -> Bool { lock.withLock { loopStarted } }
    func markFixtureFinished(error: String? = nil) {
        lock.withLock {
            fixtureFinished = true
            fixtureError = error
        }
    }
    func claimCompletion() -> Bool {
        lock.withLock {
            guard !completionClaimed else { return false }
            completionClaimed = true
            return true
        }
    }
    func markWatchdogFired(callbackOnMainThread: Bool? = nil) -> Bool {
        lock.withLock {
            guard !sealed else { return false }
            watchdogFired = true
            self.callbackOnMainThread = callbackOnMainThread
            return true
        }
    }
    func markDeadlineWriteFailure(_ message: String) {
        lock.withLock { deadlineWriteError = message }
    }
    func snapshot() -> (fixtureFinished: Bool, watchdogFired: Bool, callbackOnMainThread: Bool?) {
        lock.withLock { (fixtureFinished, watchdogFired, callbackOnMainThread) }
    }
    func finishAndSnapshot() -> (fixtureFinished: Bool, watchdogFired: Bool,
                                 deadlineWriteError: String?, fixtureError: String?) {
        lock.withLock {
            sealed = true
            return (fixtureFinished, watchdogFired, deadlineWriteError, fixtureError)
        }
    }
}

private struct NativeEntryDeadline: Codable {
    let monotonicUptime: TimeInterval
    let fixtureFinishedAtDeadline: Bool
}

private func makeNativeEntryWatchdog(
    state: NativeEntryRunState, output: URL, delay: DispatchTimeInterval,
    onMainTimeout: @escaping @MainActor @Sendable () -> Void
) -> DispatchSourceTimer {
    let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    watchdog.schedule(deadline: .now() + delay)
    watchdog.setEventHandler {
        guard state.markWatchdogFired(callbackOnMainThread: Thread.isMainThread) else { return }
        let deadline = NativeEntryDeadline(
            monotonicUptime: ProcessInfo.processInfo.systemUptime,
            fixtureFinishedAtDeadline: state.snapshot().fixtureFinished)
        do {
            try JSONEncoder().encode(deadline).write(
                to: output.appendingPathComponent("native-entry-deadline.json"), options: .atomic)
        } catch {
            state.markDeadlineWriteFailure(String(describing: error))
        }
        DispatchQueue.main.async { onMainTimeout() }
    }
    watchdog.resume()
    return watchdog
}

@MainActor
private final class NativeFullscreenTransitionObserver: NSObject, NSWindowDelegate {
    private(set) var events: [String] = []
    private(set) var globalEvents: [String] = []
    private(set) var delegateEvents: [String] = []
    var mainDispatchDelivered = false
    private(set) var failure: String?
    private var tokens: [NSObjectProtocol] = []

    func install(on window: NSWindow, attachDelegate: Bool) throws {
        _ = try #require(window.delegate == nil,
            "Fullscreen probe requires an unclaimed window delegate; preserve the original delegate.")
        let names: [(NSNotification.Name, String)] = [
            (NSWindow.willEnterFullScreenNotification, "willEnter"),
            (NSWindow.didEnterFullScreenNotification, "didEnter"),
            (NSWindow.willExitFullScreenNotification, "willExit"),
            (NSWindow.didExitFullScreenNotification, "didExit")
        ]
        let targetID = ObjectIdentifier(window)
        for (name, label) in names {
            tokens.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?.events.append(label) }
                })
            tokens.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: nil) { [weak self] notification in
                    let observedID = (notification.object as? NSWindow)
                        .map(ObjectIdentifier.init)
                    MainActor.assumeIsolated {
                        self?.globalEvents.append("\(label):\(observedID == targetID)")
                    }
                })
        }
        if attachDelegate { window.delegate = self }
    }

    func remove(from window: NSWindow) {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens.removeAll()
        if window.delegate === self { window.delegate = nil }
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        delegateEvents.append("willEnter")
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        delegateEvents.append("didEnter")
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        delegateEvents.append("willExit")
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        delegateEvents.append("didExit")
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        failure = "didFailToEnter"
        events.append("didFailToEnter")
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        failure = "didFailToExit"
        events.append("didFailToExit")
    }
}

/// Opt-in source-hosted evidence. This never composes the live app runtime.
@Suite("UMA 0.15 visual contract", .serialized)
@MainActor
struct UMA015VisualContractTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UMA015_VISUAL_EVIDENCE_DIR"] != nil))
    func productionMainWindowRendersThreeDestinationsWithGeometry() async throws {
        _ = NSApplication.shared
        let path = try #require(ProcessInfo.processInfo.environment["UMA015_VISUAL_EVIDENCE_DIR"])
        #expect(!path.isEmpty)
        let output = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var captures: [Capture] = []
        for language in [AppLanguage.english, .simplifiedChinese] {
            for dark in [false, true] {
                for (sizeName, size) in [("normal", NSSize(width: 1040, height: 730)),
                                         ("minimum", NSSize(width: 760, height: 520)),
                                         ("strict-minimum", NSSize(width: 760, height: 488))] {
                    for destination in MainSurfaceDestination.allCases {
                        captures.append(try await capture(destination: destination, language: language, dark: dark,
                                                           sizeName: sizeName, size: size, output: output))
                    }
                }
                captures.append(try await capture(destination: .agents, language: language, dark: dark,
                                                   sizeName: "wide", size: NSSize(width: 1280, height: 730),
                                                   output: output))
            }
        }
        #expect(captures.count == 40)
        for capture in captures where capture.fixture.contains("-normal-") {
            #expect(abs(capture.windowFrame.height - 762) <= 1, "Benchmark outer window must be 1040×762")
        }
        for capture in captures where capture.fixture.contains("-strict-minimum-") {
            #expect(abs(capture.windowFrame.width - 760) <= 1 && abs(capture.windowFrame.height - 520) <= 1,
                    "The existing 760×520 outer minimum must actually fit.")
        }
        for capture in captures where capture.fixture.contains("-wide-") {
            #expect(abs(capture.windowFrame.width - 1280) <= 1 && abs(capture.windowFrame.height - 762) <= 1)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("geometry-index.json"), options: .atomic)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["UMA015_VISUAL_EVIDENCE_DIR"] != nil))
    func fixedDataAgentStatesRemainIsolated() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["UMA015_VISUAL_EVIDENCE_DIR"])
        let output = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("fixed-data", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let size = NSSize(width: 1040, height: 730)
        let capturedAt = try #require(ISO8601DateFormatter().date(from: "2026-10-09T12:00:00Z"))
        let days = [AgentAccountUsageDay(day: "2026-10-07", tokens: 0),
                    AgentAccountUsageDay(day: "2026-10-09", tokens: 1200)]
        let cases: [(String, [SharedUsageCardPresentation])] = [
            ("zero", [previewCard(product: .codex, remaining: 0)]),
            ("full", [previewCard(product: .codex, remaining: 100)]),
            ("loading", [previewCard(product: .codex, remaining: 24, loading: true)]),
            ("unavailable", [previewCard(product: .codex, remaining: 0, freshness: .unavailable)]),
            ("long", [previewCard(product: .codex, remaining: 24, manyWindows: true)]),
            ("rail-overflow", [previewCard(product: .codex, remaining: 24, resetRows: 40),
                                previewCard(product: .claude, remaining: 24, resetRows: 40)]),
            ("supported-pair", [ProviderProductID.codex, .claude].map {
                previewCard(product: $0, remaining: 24)
            }),
            ("aggregate-history", [previewCard(product: .codex, remaining: 24)]),
            ("stale-history", [previewCard(product: .codex, remaining: 24)]),
            ("no-history", [previewCard(product: .codex, remaining: 24)]),
            ("activity-stale", [previewCard(product: .codex, remaining: 24)]),
            ("activity-unavailable", [previewCard(product: .codex, remaining: 24)]),
            ("activity-empty", [previewCard(product: .codex, remaining: 24)])
        ]
        for (variant, cards) in cases {
            let scene = try await capture(destination: .agents, language: .english, dark: false,
                sizeName: "normal", size: size, output: output, variant: variant,
                cards: cards, accountDailyUsage: variant.hasSuffix("-history") ? [] : days,
                previewCapturedAt: capturedAt)
            #expect(scene.windowFrame.height == 762)
            #expect(scene.geometry["uma015.agent.split-pane.0"]?.width == 248)
        }
        _ = try await capture(destination: .agents, language: .simplifiedChinese, dark: false,
            sizeName: "normal", size: size, output: output, variant: "supported-pair",
            cards: [ProviderProductID.codex, .claude].map { previewCard(product: $0, remaining: 24) },
            accountDailyUsage: days, previewCapturedAt: capturedAt)
        for language in [AppLanguage.english, .simplifiedChinese] {
            for (sizeName, size) in [("wide", NSSize(width: 1280, height: 730)),
                                     ("minimum", NSSize(width: 760, height: 520))] {
                _ = try await capture(destination: .agents, language: language, dark: false,
                    sizeName: sizeName, size: size, output: output, variant: "supported-pair",
                    cards: [ProviderProductID.codex, .claude].map { previewCard(product: $0, remaining: 24) },
                    accountDailyUsage: days, previewCapturedAt: capturedAt)
            }
        }
        _ = try await capture(destination: .agents, language: .simplifiedChinese, dark: false,
            sizeName: "normal", size: size, output: output, variant: "long",
            cards: [previewCard(product: .codex, remaining: 24, manyWindows: true)],
            accountDailyUsage: days, previewCapturedAt: capturedAt)
        _ = try await capture(destination: .agents, language: .english, dark: false,
            sizeName: "strict-minimum", size: NSSize(width: 760, height: 488), output: output,
            variant: "rail-overflow", cards: [
                previewCard(product: .codex, remaining: 24, resetRows: 40),
                previewCard(product: .claude, remaining: 24, resetRows: 40)],
            accountDailyUsage: days, previewCapturedAt: capturedAt)
    }

    @Test
    func normalContentFitUsesUnclampedPolicyAndTargetScreens() {
        let requested = NSSize(width: 1040, height: 792)
        let large = NSRect(x: 0, y: 0, width: 1470, height: 923)
        let small = NSRect(x: 0, y: 0, width: 760, height: 520)
        #expect(normalContentGap(requestedOuter: requested,
            policyVisibleFrame: large, targetVisibleFrame: large) == nil)
        let clamped = MainWindowFramePolicy.initialFrame(visibleFrames: [small], outerSize: requested)
        #expect(clamped.size == small.size)
        #expect(normalContentGap(requestedOuter: requested,
            policyVisibleFrame: small, targetVisibleFrame: small) == "POLICY_SCREEN_BELOW_REQUESTED_NORMAL_OUTER")
        #expect(normalContentGap(requestedOuter: requested,
            policyVisibleFrame: small, targetVisibleFrame: large) == "POLICY_SCREEN_BELOW_REQUESTED_NORMAL_OUTER")
        #expect(normalContentGap(requestedOuter: requested,
            policyVisibleFrame: large, targetVisibleFrame: small) == "TARGET_SCREEN_BELOW_REQUESTED_NORMAL_OUTER")
        #expect(normalContentGap(requestedOuter: requested,
            policyVisibleFrame: nil, targetVisibleFrame: large) == "NO_POLICY_SCREEN")
        #expect(normalContentGap(requestedOuter: requested,
            policyVisibleFrame: large, targetVisibleFrame: nil) == "NO_TARGET_SCREEN")
    }

    @Test
    func controlledAgentInputStatesUseDistinctRemainingValues() {
        let zero = previewCard(product: .codex, remaining: 0)
        let full = previewCard(product: .codex, remaining: 100)
        let unavailable = previewCard(product: .codex, remaining: 0, freshness: .unavailable)
        let transitional = previewCard(product: .codex, remaining: 24, loading: true)
        #expect(zero.remaining == .finite(0))
        #expect(full.remaining == .finite(100))
        #expect(unavailable.remaining == .unavailable)
        #expect(unavailable.windows.first?.remaining == .unavailable)
        #expect(transitional.remaining == .finite(24))
        #expect(transitional.freshness == .cached)
        #expect(transitional.isRetainingLastValidValue)
    }

    @Test
    func nativeEntryWatchdogNeverAllowsSuccess() {
        #expect(nativeEntrySucceeded(fixtureFinished: true, watchdogFired: false))
        #expect(!nativeEntrySucceeded(fixtureFinished: true, watchdogFired: true))
        #expect(!nativeEntrySucceeded(fixtureFinished: false, watchdogFired: false))
        #expect(!nativeEntrySucceeded(fixtureFinished: false, watchdogFired: true))
    }

    @Test
    func nativeAlreadyRunningEntryIsRejectedBeforeAwaiting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UMA015-AlreadyRunning-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let freshRefused = try rejectAlreadyRunningNativeEntry(false, output: root)
        #expect(!freshRefused)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("native-entry-host-lifecycle.json").path))
        let runningRefused = try rejectAlreadyRunningNativeEntry(true, output: root)
        #expect(runningRefused)
        let refusal = try JSONDecoder().decode(NativeEntryHostLifecycle.self,
            from: Data(contentsOf: root.appendingPathComponent("native-entry-host-lifecycle.json")))
        #expect(refusal.appWasRunningAtEntry && refusal.appRunningAfterFixture)
        #expect(!refusal.fixtureFinished && !refusal.watchdogFired)
        #expect(refusal.fixtureError?.contains("before awaiting") == true)
    }

    @Test
    func nativeEntryStateSealsDeadlineForBothHostBranches() {
        for wasRunning in [false, true] {
            let completed = NativeEntryRunState()
            completed.markFixtureFinished()
            let result = completed.finishAndSnapshot()
            #expect(result.fixtureFinished && !result.watchdogFired,
                "Both AppKit host states require the same completed-fixture result: \(wasRunning)")
            #expect(!completed.markWatchdogFired())
            #expect(completed.claimCompletion())
            #expect(!completed.claimCompletion())

            let timedOut = NativeEntryRunState()
            #expect(timedOut.markWatchdogFired())
            timedOut.markFixtureFinished()
            let timeoutResult = timedOut.finishAndSnapshot()
            #expect(!nativeEntrySucceeded(fixtureFinished: timeoutResult.fixtureFinished,
                watchdogFired: timeoutResult.watchdogFired))
            #expect(timedOut.claimCompletion())
            #expect(!timedOut.claimCompletion())
        }
        let failed = NativeEntryRunState()
        failed.markFixtureFinished(error: "fixture refusal")
        #expect(failed.finishAndSnapshot().fixtureError == "fixture refusal")
    }

    @Test
    func nativeEntryBackgroundWatchdogRecordsDeadlineAndWriteFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UMA015-R11-Watchdog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fired = NativeEntryRunState()
        var timer: DispatchSourceTimer?
        let _: Void = await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            timer = makeNativeEntryWatchdog(state: fired, output: root, delay: .milliseconds(20)) {
                continuation.resume()
            }
        }
        timer?.cancel()
        let deadline = try JSONDecoder().decode(NativeEntryDeadline.self,
            from: Data(contentsOf: root.appendingPathComponent("native-entry-deadline.json")))
        #expect(!deadline.fixtureFinishedAtDeadline)
        #expect(fired.snapshot().watchdogFired)
        #expect(fired.snapshot().callbackOnMainThread == false)
        #expect(fired.claimCompletion() && !fired.claimCompletion())

        let failedWrite = NativeEntryRunState()
        let missingParent = root.appendingPathComponent("missing", isDirectory: true)
        let _: Void = await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            timer = makeNativeEntryWatchdog(state: failedWrite, output: missingParent,
                                            delay: .milliseconds(20)) {
                continuation.resume()
            }
        }
        timer?.cancel()
        let failure = failedWrite.finishAndSnapshot()
        #expect(failure.watchdogFired)
        #expect(failure.deadlineWriteError != nil)
        #expect(!nativeEntrySucceeded(fixtureFinished: failure.fixtureFinished,
                                      watchdogFired: failure.watchdogFired))
    }

    @Test
    func nativeTestHostIdentityReadback() throws {
        let identity = currentNativeHostIdentity()
        #expect(identity.processID > 0)
        if let path = ProcessInfo.processInfo.environment["UMA015_NATIVE_HOST_IDENTITY_DIR"] {
            let output = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(identity).write(to: output.appendingPathComponent("native-host-identity.json"),
                options: .atomic)
        }
    }

    @Test
    func nativeAppHostIdentityGateRequiresExactBundleAndProcess() {
        let bundle = URL(fileURLWithPath: "/private/tmp/uma015-r13-fixture/UMA015NativeTestHost.app")
        let expectedExecutable = bundle.appendingPathComponent("Contents/MacOS/swiftpm-testing-helper").path
        let valid = NativeHostIdentity(
            processID: 73, processName: "swiftpm-testing-helper", bundleURL: bundle.path,
            bundleIdentifier: "com.tosuma.uma015.native-test-host", bundlePackageType: "APPL",
            executableURL: expectedExecutable, runningProcessID: 73,
            runningBundleURL: bundle.path, runningExecutableURL: expectedExecutable,
            runningBundleIdentifier: "com.tosuma.uma015.native-test-host",
            runningActivationPolicy: NSApplication.ActivationPolicy.regular.rawValue,
            runningIsActive: false, runningIsFinishedLaunching: false)
        #expect(nativeAppHostIdentityMatches(valid, expectedBundle: bundle))
        let wrongBundle = NativeHostIdentity(
            processID: 73, processName: "swiftpm-testing-helper", bundleURL: "/Applications/ChatGPT.app",
            bundleIdentifier: "com.openai.codex", bundlePackageType: "APPL",
            executableURL: expectedExecutable, runningProcessID: 73,
            runningBundleURL: "/Applications/ChatGPT.app", runningExecutableURL: expectedExecutable,
            runningBundleIdentifier: "com.openai.codex",
            runningActivationPolicy: NSApplication.ActivationPolicy.regular.rawValue,
            runningIsActive: false, runningIsFinishedLaunching: false)
        #expect(!nativeAppHostIdentityMatches(wrongBundle, expectedBundle: bundle))
        let wrongProcess = NativeHostIdentity(
            processID: 73, processName: "swiftpm-testing-helper", bundleURL: bundle.path,
            bundleIdentifier: "com.tosuma.uma015.native-test-host", bundlePackageType: "APPL",
            executableURL: expectedExecutable, runningProcessID: -1,
            runningBundleURL: bundle.path, runningExecutableURL: expectedExecutable,
            runningBundleIdentifier: "com.tosuma.uma015.native-test-host",
            runningActivationPolicy: NSApplication.ActivationPolicy.regular.rawValue,
            runningIsActive: false, runningIsFinishedLaunching: false)
        #expect(!nativeAppHostIdentityMatches(wrongProcess, expectedBundle: bundle))
    }

    /// Compiled with the regular suite, but never executes unless the original
    /// QA foreground approval path enables this explicit opt-in separately.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UMA015_FOREGROUND_ACCEPTANCE_DIR"] != nil))
    func attachedProductionWindowKeyboardAcceptance() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["UMA015_FOREGROUND_ACCEPTANCE_DIR"])
        let output = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try prepareNativeTestHost(output: output)
        _ = NSApplication.shared
        // The AppKit timer callback runs inside the real application loop.
        // Execute the synchronous fixture there: a MainActor Task queued from
        // a nested NSApplication.run never entered the fixture in R10.
        let runState = NativeEntryRunState()
        let appWasRunning = NSApp.isRunning
        let alreadyRunningRefused = try rejectAlreadyRunningNativeEntry(appWasRunning, output: output)
        _ = try #require(!alreadyRunningRefused,
            "An already-running AppKit host is rejected before awaiting; inspect native-entry-host-lifecycle.json.")
        let probeMode = ProcessInfo.processInfo.environment["UMA015_NATIVE_PROBE"]
        let fullTimerEntry = probeMode == nil || probeMode == "full-timer-entry"
        let timerEntryProbe = fullTimerEntry || probeMode == "fullscreen-timer-entry"
        try writeNativeEntryHostPhase("before-host-ready", to: output)
        var watchdog: DispatchSourceTimer?
        let _: Void = await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            watchdog = makeNativeEntryWatchdog(state: runState, output: output,
                delay: .seconds(fullTimerEntry ? 180 : timerEntryProbe ? 40 : 90)) {
                // The bounded timer-entry experiment can fail before NSApp.run.
                // Its dispatch callback has returned, so resume the test if
                // no app loop began; otherwise its AppKit poller stops the loop.
                if !appWasRunning {
                    if timerEntryProbe && !runState.hasLoopStarted() {
                        if runState.claimCompletion() { continuation.resume() }
                    } else {
                        self.stopNativeEntryLoop()
                    }
                }
            }
            let startFixture: @MainActor () -> Void = {
                guard !runState.snapshot().watchdogFired else {
                    if appWasRunning, runState.claimCompletion() { continuation.resume() }
                    return
                }
                var errorText: String?
                do {
                    try self.writeNativeEntryHostPhase("host-running", to: output)
                    _ = try #require(NSApp.isRunning,
                        "The native fixture requires an executing AppKit application event loop.")
                    try self.writeNativeEntryHostPhase("fixture-start", to: output)
                    if ["fullscreen-two-window", "fullscreen-control-no-delegate",
                        "fullscreen-timer-entry"].contains(
                        ProcessInfo.processInfo.environment["UMA015_NATIVE_PROBE"] ?? "") {
                        try self.startNativeFullscreenTwoWindowProbe(output: output,
                            runState: runState) { error in
                            runState.markFixtureFinished(error: error)
                            if appWasRunning || timerEntryProbe {
                                if runState.claimCompletion() { continuation.resume() }
                            } else {
                                self.stopNativeEntryLoop()
                            }
                        }
                        return
                    }
                    if ProcessInfo.processInfo.environment["UMA015_NATIVE_PROBE"]
                        == "disclosure-axpress" {
                        try self.startNativeDisclosureProbe(output: output, runState: runState) { error in
                            runState.markFixtureFinished(error: error)
                            if appWasRunning || timerEntryProbe {
                                if runState.claimCompletion() { continuation.resume() }
                            } else {
                                self.stopNativeEntryLoop()
                            }
                        }
                        return
                    }
                    try self.exerciseAttachedProductionWindowKeyboardAcceptance(
                        runState: runState)
                } catch {
                    errorText = String(describing: error)
                }
                runState.markFixtureFinished(error: errorText)
                if appWasRunning || timerEntryProbe {
                    if runState.claimCompletion() { continuation.resume() }
                } else {
                    self.stopNativeEntryLoop()
                }
            }
            if appWasRunning {
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
                    MainActor.assumeIsolated { startFixture() }
                }
            } else {
                DispatchQueue.main.async {
                    NSApp.finishLaunching()
                    do {
                        try self.writeNativeEntryHostPhase("host-ready", to: output)
                    } catch {
                        runState.markFixtureFinished(error: String(describing: error))
                        continuation.resume()
                        return
                    }
                    if timerEntryProbe {
                        // Return from the main-queue block before starting the
                        // application loop. A separate AppKit timer owns it,
                        // and another timer can stop it at the watchdog limit.
                        Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
                            MainActor.assumeIsolated {
                                guard !runState.snapshot().watchdogFired else {
                                    if runState.claimCompletion() { continuation.resume() }
                                    return
                                }
                                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
                                    MainActor.assumeIsolated { startFixture() }
                                }
                                let stopPoller = Timer.scheduledTimer(
                                    withTimeInterval: 0.20, repeats: true) { timer in
                                    let timedOut = MainActor.assumeIsolated {
                                        runState.snapshot().watchdogFired
                                    }
                                    if timedOut {
                                        timer.invalidate()
                                        MainActor.assumeIsolated { self.stopNativeEntryLoop() }
                                    }
                                }
                                runState.markLoopStarted()
                                NSApp.run()
                                stopPoller.invalidate()
                                if runState.claimCompletion() { continuation.resume() }
                            }
                        }
                    } else {
                        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in
                            MainActor.assumeIsolated { startFixture() }
                        }
                        if runState.snapshot().watchdogFired {
                            continuation.resume()
                            return
                        }
                        NSApp.run()
                        continuation.resume()
                    }
                }
            }
        }
        watchdog?.cancel()
        let state = runState.finishAndSnapshot()
        let lifecycle = NativeEntryHostLifecycle(
            appWasRunningAtEntry: appWasRunning,
            appRunningAfterFixture: NSApp.isRunning,
            fixtureFinished: state.fixtureFinished,
            watchdogFired: state.watchdogFired,
            deadlineWriteError: state.deadlineWriteError,
            fixtureError: state.fixtureError)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(lifecycle).write(to: output.appendingPathComponent("native-entry-host-lifecycle.json"),
            options: .atomic)
        _ = try #require(nativeEntrySucceeded(fixtureFinished: state.fixtureFinished,
            watchdogFired: state.watchdogFired) && state.deadlineWriteError == nil
            && state.fixtureError == nil,
            "Native fixture failed, timed out, or its deadline record failed; inspect native-entry-host-lifecycle.json.")
    }

    // Test-only differential: a pure AppKit control and the attached production
    // window use the same host and one real application-loop turn per transition.
    private func startNativeFullscreenTwoWindowProbe(
        output: URL, runState: NativeEntryRunState,
        completion: @escaping @MainActor (String?) -> Void
    ) throws {
        try requireNativeFixtureBeforeDeadline(runState)
        let originalPolicy = NSApp.activationPolicy()
        let wasHidden = NSApp.isHidden
        _ = NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        _ = try #require(NSApp.activationPolicy() == .regular,
            "Fullscreen differential requires regular application activation.")
        let defaultsBefore = productionDefaultsSnapshot()
        let storage = try StorageFixture(root: output.appendingPathComponent("storage", isDirectory: true))
        let promptPreferences = ApplicationPreferences.inMemory()
        let agentPreferences = ApplicationPreferences.inMemory()
        let settings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: agentPreferences),
            shippedProviders: [(AgentPreferenceRecord.codexProviderID, "Codex"),
                               (AgentPreferenceRecord.claudeProviderID, "Claude Code")])
        let cards = [previewCard(product: .codex, remaining: 24),
                     previewCard(product: .claude, remaining: 24)]
        let store = UsageStore(autoRefresh: false, previewOnly: true, language: .english,
            registry: nil, primaryConnectorID: nil, consentDefaults: nil,
            preferences: agentPreferences, agentSettings: settings,
            previewPresentationCards: cards)
        let defaultsName = "UMA015.NativeFullscreen.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let frameName = "UMA015.NativeFullscreenFrame.\(UUID().uuidString)"
        let actions = AcceptanceActions()
        let controller = MainWindowController(autosaveName: frameName, restoresSavedFrame: true)
        controller.attach(store: store, openSettings: { actions.record() },
            scanAll: { actions.record() }, refreshAll: { actions.record() },
            connectCodex: { actions.record() }, disconnectCodex: { actions.record() },
            claudeControlState: { .consentRequired }, connectClaude: { actions.record() },
            accuracySyncClaude: { actions.record() }, hesectoriumStore: storage.store,
            promptClipboard: AcceptanceClipboard(), promptPreferences: promptPreferences,
            appStorageDefaults: defaults)
        let production = try #require(controller.window)
        let control = NSWindow(contentRect: NSRect(origin: .zero,
            size: MainWindowFramePolicy.normalContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        control.title = "UMA015 Isolated AppKit Fullscreen Control"
        control.minSize = production.minSize
        control.isReleasedWhenClosed = false
        control.tabbingMode = .disallowed
        control.setFrame(production.frame, display: false)
        let controlOwner = NSWindowController(window: control)
        let finish: @MainActor (String?) -> Void = { error in
            control.orderOut(nil)
            controlOwner.close()
            controller.tearDown()
            storage.store.deactivateWorkbench()
            defaults.removePersistentDomain(forName: defaultsName)
            NSWindow.removeFrame(usingName: frameName)
            if wasHidden { NSApp.hide(nil) }
            NSApp.setActivationPolicy(originalPolicy)
            let mutationError = defaultsBefore == productionDefaultsSnapshot()
                && actions.count == 0 && storage.backend.mutations == 0
                ? nil : "Fullscreen probe changed production defaults or invoked an injected action."
            completion(error ?? mutationError)
        }
        _ = try #require(control.styleMask == production.styleMask
            && control.collectionBehavior == production.collectionBehavior,
            "Pure AppKit control must match production window style and collection behavior.")
        controlOwner.showWindow(nil)
        control.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        _ = NSRunningApplication.current.activate(options: .activateAllWindows)
        let controlScreenID = control.screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let attachDelegate = ProcessInfo.processInfo.environment["UMA015_NATIVE_PROBE"]
            != "fullscreen-control-no-delegate"
        runNativeFullscreenLeg(window: control, owner: "NSWindowController",
            expectedScreenID: controlScreenID, output: output, label: "control",
            attachDelegate: attachDelegate, runState: runState) { error in
            if let error { finish(error); return }
            control.orderOut(nil)
            controller.showDestination(.agents)
            production.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            _ = NSRunningApplication.current.activate(options: .activateAllWindows)
            self.runNativeFullscreenLeg(window: production, owner: "MainWindowController",
                expectedScreenID: controlScreenID, output: output, label: "production",
                attachDelegate: attachDelegate, runState: runState) { error in
                finish(error)
            }
        }
    }

    private func runNativeFullscreenLeg(
        window: NSWindow, owner: String, expectedScreenID: NSNumber?,
        output: URL, label: String, attachDelegate: Bool,
        runState: NativeEntryRunState,
        completion: @escaping @MainActor (String?) -> Void
    ) {
        let observer = NativeFullscreenTransitionObserver()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { observer.mainDispatchDelivered = true }
        }
        let initialFrame = window.frame
        let initialScale = window.backingScaleFactor
        let initialScreenID = window.screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        var phase = "activation"
        var phaseStarted = Date()
        var exitedSince: Date?
        var finished = false
        var timer: Timer?
        func record(_ checkpoint: String) throws {
            let data: [String: String] = [
                "checkpoint": checkpoint, "owner": owner,
                "windowClass": String(describing: type(of: window)),
                "windowID": String(describing: ObjectIdentifier(window)),
                "delegate": String(describing: window.delegate),
                "events": observer.events.joined(separator: ","),
                "globalEvents": observer.globalEvents.joined(separator: ","),
                "delegateEvents": observer.delegateEvents.joined(separator: ","),
                "failure": observer.failure ?? "",
                "failureDelegateAttached": String(attachDelegate),
                "appRunning": String(NSApp.isRunning),
                "mainDispatchDelivered": String(observer.mainDispatchDelivered),
                "runLoopMode": RunLoop.current.currentMode?.rawValue ?? "nil",
                "styleMask": String(window.styleMask.rawValue),
                "collectionBehavior": String(window.collectionBehavior.rawValue),
                "frame": NSStringFromRect(window.frame),
                "scale": String(Double(window.backingScaleFactor)),
                "screen": window.screen?.localizedName ?? "nil",
                "displayID": String(describing: window.screen?.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber),
                "sameScreen": String((window.screen?.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == expectedScreenID),
                "active": String(NSApp.isActive), "key": String(window.isKeyWindow),
                "main": String(window.isMainWindow),
                "firstResponder": String(describing: window.firstResponder)
            ]
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: output.appendingPathComponent(
                "native-fullscreen-\(label)-\(checkpoint).json"), options: .atomic)
        }
        let finish: @MainActor (String?) -> Void = { error in
            guard !finished else { return }
            finished = true
            timer?.invalidate()
            try? record("terminal")
            observer.remove(from: window)
            completion(error)
        }
        try? record("before-activation")
        timer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { _ in
            MainActor.assumeIsolated {
                do {
                    try self.requireNativeFixtureBeforeDeadline(runState)
                    let now = Date()
                    _ = try #require(now.timeIntervalSince(phaseStarted) <= 12,
                        "Fullscreen \(label) \(phase) timed out; inspect transition event records.")
                    _ = try #require(observer.failure == nil,
                        "Fullscreen \(label) delegate reported \(observer.failure ?? "unknown")")
                    if phase == "activation" {
                        if !NSApp.isActive {
                            NSApp.activate(ignoringOtherApps: true)
                            _ = NSRunningApplication.current.activate(options: .activateAllWindows)
                        }
                        guard NSApp.isActive && window.isKeyWindow && window.isMainWindow
                            && NSApp.keyWindow === window else { return }
                        let screenID = window.screen?.deviceDescription[
                            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                        let screenMatches = screenID != nil && screenID == expectedScreenID
                            && screenID == initialScreenID
                        _ = try #require(window.firstResponder != nil && screenMatches,
                            "Fullscreen \(label) requires the expected screen and actual responder.")
                        try observer.install(on: window, attachDelegate: attachDelegate)
                        try record("before-enter")
                        window.toggleFullScreen(nil)
                        phase = "enter"
                        phaseStarted = now
                        return
                    }
                    if phase == "enter" {
                        guard observer.events.contains("didEnter") else { return }
                        _ = try #require(observer.events.starts(with: ["willEnter", "didEnter"])
                            && window.styleMask.contains(.fullScreen)
                            && NSApp.isActive && window.isKeyWindow && window.isMainWindow
                            && window.firstResponder != nil,
                            "Fullscreen \(label) requires completed ordered entry and foreground focus.")
                        try record("did-enter")
                        window.toggleFullScreen(nil)
                        phase = "exit"
                        phaseStarted = now
                        return
                    }
                    guard observer.events.contains("didExit")
                        && !window.styleMask.contains(.fullScreen) else { return }
                    if exitedSince == nil { exitedSince = now; return }
                    guard now.timeIntervalSince(exitedSince!) >= 0.20 else { return }
                    let restoredScreen = (window.screen?.deviceDescription[
                        NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == initialScreenID
                    _ = try #require(observer.events == ["willEnter", "didEnter", "willExit", "didExit"]
                        && NSApp.isActive && window.isKeyWindow && window.isMainWindow
                        && window.firstResponder != nil && restoredScreen
                        && abs(window.frame.minX - initialFrame.minX) <= 2
                        && abs(window.frame.minY - initialFrame.minY) <= 2
                        && abs(window.frame.width - initialFrame.width) <= 2
                        && abs(window.frame.height - initialFrame.height) <= 2
                        && abs(window.backingScaleFactor - initialScale) < 0.01,
                        "Fullscreen \(label) must restore frame, scale, screen and focus after ordered exit.")
                    try record("did-exit")
                    finish(nil)
                } catch {
                    finish(String(describing: error))
                }
            }
        }
    }

    // A focused native probe for the current no-future-reset presentation.
    // The preview still carries reset data so an accidental UI leak is visible.
    private func startNativeDisclosureProbe(
        output: URL, runState: NativeEntryRunState,
        completion: @escaping @MainActor (String?) -> Void
    ) throws {
        try requireNativeFixtureBeforeDeadline(runState)
        let originalPolicy = NSApp.activationPolicy()
        let wasHidden = NSApp.isHidden
        _ = NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        _ = try #require(NSApp.activationPolicy() == .regular,
            "Reset-absence probe requires the native regular activation policy.")
        let productionDefaultsBefore = productionDefaultsSnapshot()
        let storage = try StorageFixture(root: output.appendingPathComponent("storage", isDirectory: true))
        let promptPreferences = ApplicationPreferences.inMemory()
        let agentPreferences = ApplicationPreferences.inMemory()
        let settings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: agentPreferences),
            shippedProviders: [(AgentPreferenceRecord.codexProviderID, "Codex"),
                               (AgentPreferenceRecord.claudeProviderID, "Claude Code")])
        let cards = [previewCard(product: .codex, remaining: 24, resetRows: 40),
                     previewCard(product: .claude, remaining: 24, resetRows: 40)]
        let store = UsageStore(autoRefresh: false, previewOnly: true, language: .english,
            registry: nil, primaryConnectorID: nil, consentDefaults: nil,
            preferences: agentPreferences, agentSettings: settings,
            previewPresentationCards: cards)
        let defaultsName = "UMA015.NativeDisclosure.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let frameName = "UMA015.NativeDisclosureFrame.\(UUID().uuidString)"
        let actions = AcceptanceActions()
        let controller = MainWindowController(autosaveName: frameName, restoresSavedFrame: true)
        controller.attach(store: store, openSettings: { actions.record() },
            scanAll: { actions.record() }, refreshAll: { actions.record() },
            connectCodex: { actions.record() }, disconnectCodex: { actions.record() },
            claudeControlState: { .consentRequired }, connectClaude: { actions.record() },
            accuracySyncClaude: { actions.record() }, hesectoriumStore: storage.store,
            promptClipboard: AcceptanceClipboard(), promptPreferences: promptPreferences,
            appStorageDefaults: defaults)
        controller.showDestination(.agents)
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        NSApp.activate(ignoringOtherApps: true)
        _ = NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        window.makeKeyAndOrderFront(nil)
        window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY,
            width: 760, height: 520), display: true)
        settle(content)
        let deadline = Date().addingTimeInterval(5)
        while (!NSApp.isActive || NSApp.keyWindow !== window || !window.isKeyWindow),
              Date() < deadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        _ = try #require(NSApp.isActive && NSApp.keyWindow === window && window.isKeyWindow
            && window.isMainWindow, "Reset-absence probe requires active/key/main native window.")
        let finish: @MainActor (String?) -> Void = { error in
            controller.tearDown()
            storage.store.deactivateWorkbench()
            defaults.removePersistentDomain(forName: defaultsName)
            NSWindow.removeFrame(usingName: frameName)
            if wasHidden { NSApp.hide(nil) }
            NSApp.setActivationPolicy(originalPolicy)
            #expect(productionDefaultsSnapshot() == productionDefaultsBefore,
                "The reset-absence probe must not mutate production defaults.")
            completion(error)
        }
        do {
            let treeURL = output.appendingPathComponent("reset-absence-accessibility-tree.txt")
            try writeNativeAccessibilityTree(content, to: treeURL)
            let tree = try String(contentsOf: treeURL, encoding: .utf8)
            #expect(!tree.contains("uma.agent.reset-details")
                && !tree.contains("Full reset times")
                && !tree.contains("Resets in ")
                && !tree.contains("Friday, January 15, 2027"),
                "Future reset details must not enter the native accessibility tree.")
            try recordNativeDashboardViewport("probe-minimum", in: content,
                window: window, output: output, runState: runState)
            finish(nil)
        } catch {
            finish(String(describing: error))
        }
    }

    private func recordNativeDisclosureProbe(
        _ phase: String, details: AXUIElement, content: NSView,
        window: NSWindow, output: URL
    ) throws {
        var value: CFTypeRef?
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(details,
            kAXValueAttribute as CFString, &value)
        let positionStatus = AXUIElementCopyAttributeValue(details,
            kAXPositionAttribute as CFString, &positionValue)
        let sizeStatus = AXUIElementCopyAttributeValue(details,
            kAXSizeAttribute as CFString, &sizeValue)
        var axPosition = CGPoint.zero
        var axSize = CGSize.zero
        if let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID() {
            _ = AXValueGetValue(positionValue as! AXValue, .cgPoint, &axPosition)
        }
        if let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            _ = AXValueGetValue(sizeValue as! AXValue, .cgSize, &axSize)
        }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screenFrame = CGRect(x: axPosition.x,
            y: primaryTop - axPosition.y - axSize.height,
            width: axSize.width, height: axSize.height)
        let windowFrame = window.convertFromScreen(screenFrame)
        let clickPoint = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        let hit = content.hitTest(content.convert(clickPoint, from: nil))
        let rail = descendants(of: content).compactMap { $0 as? NSScrollView }.first {
            let pane = $0.convert($0.bounds, to: content)
            return pane.width >= 180 && pane.width <= 250 && pane.minX < 260
        }
        let record: [String: String] = [
            "phase": phase, "pid": String(ProcessInfo.processInfo.processIdentifier),
            "windowNumber": String(window.windowNumber),
            "active": String(NSApp.isActive), "key": String(window.isKeyWindow),
            "main": String(window.isMainWindow),
            "firstResponder": String(describing: window.firstResponder),
            "outer": NSStringFromRect(window.frame),
            "content": NSStringFromRect(window.contentRect(forFrameRect: window.frame)),
            "scale": String(describing: window.backingScaleFactor),
            "axValueStatus": String(valueStatus.rawValue),
            "axValue": String(describing: value),
            "axPositionStatus": String(positionStatus.rawValue),
            "axSizeStatus": String(sizeStatus.rawValue),
            "axPosition": NSStringFromPoint(axPosition),
            "axSize": NSStringFromSize(axSize),
            "clickPoint": NSStringFromPoint(clickPoint),
            "hitView": String(describing: hit),
            "hitIdentifier": hit?.accessibilityIdentifier() ?? "",
            "railDocumentHeight": String(describing: rail?.documentView?.bounds.height ?? -1),
            "railClipHeight": String(describing: rail?.contentView.bounds.height ?? -1)
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: output.appendingPathComponent(
            "native-disclosure-\(phase).json"), options: .atomic)
    }

    private func exerciseAttachedProductionWindowKeyboardAcceptance(
        runState: NativeEntryRunState
    ) throws {
        _ = NSApplication.shared
        let path = try #require(ProcessInfo.processInfo.environment["UMA015_FOREGROUND_ACCEPTANCE_DIR"])
        let output = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try requireNativeFixtureBeforeDeadline(runState)
        let originalActivationPolicy = NSApp.activationPolicy()
        let originallyHidden = NSApp.isHidden
        try writeNativeEntryPreflight("before-activation", to: output, window: nil,
            originalActivationPolicy: originalActivationPolicy, policySetterResult: nil)
        let policySetterResult = NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        defer {
            if originallyHidden { NSApp.hide(nil) }
            NSApp.setActivationPolicy(originalActivationPolicy)
        }
        try writeNativeEntryPreflight("after-activation", to: output, window: nil,
            originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult)
        _ = try #require(NSApp.activationPolicy() == .regular,
            "Native fixture requires the production regular activation policy; inspect native-entry-after-activation.json.")
        let productionDefaultsBefore = productionDefaultsSnapshot()
        let storage = try StorageFixture(root: output.appendingPathComponent("storage", isDirectory: true))
        defer { storage.store.deactivateWorkbench() }
        let promptPreferences = ApplicationPreferences.inMemory()
        let agentPreferences = ApplicationPreferences.inMemory()
        let settings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: agentPreferences),
            shippedProviders: [(AgentPreferenceRecord.codexProviderID, "Codex"),
                               (AgentPreferenceRecord.claudeProviderID, "Claude Code")]
        )
        let matrixScene = ProcessInfo.processInfo.environment["UMA015_NATIVE_MATRIX_SCENE"]
        let matrixParts = matrixScene?.split(separator: "-").map(String.init) ?? []
        if matrixScene != nil {
            _ = try #require(matrixParts.count == 3, "Native matrix scene must have language, theme and state.")
        }
        let sceneLanguage: AppLanguage = matrixParts.first == "zh" ? .simplifiedChinese : .english
        let sceneState = matrixParts.count == 3 ? matrixParts[2] : "normal"
        let sceneRemaining: Double = sceneState == "zero" ? 0 : sceneState == "full" ? 100 : 24
        let sceneFreshness: SharedUsageFreshness = sceneState == "unknown" ? .unavailable : .fresh
        let sceneLoading = sceneState == "loading"
        let sceneResetRows = sceneState == "overflow" || matrixScene == nil ? 40 : nil
        let matchedDate = Date(timeIntervalSince1970: 1_791_547_200.0)
        let matched = sceneState == "normal" ? try matchedInput(language: sceneLanguage, fixedDate: matchedDate) : nil
        let cards = matched?.cards ?? [previewCard(product: .codex, remaining: sceneRemaining,
                         freshness: sceneFreshness, loading: sceneLoading,
                         resetRows: sceneResetRows, longResetText: sceneState == "longreset"),
                     previewCard(product: .claude, remaining: sceneRemaining,
                         freshness: sceneFreshness, loading: sceneLoading,
                         resetRows: sceneResetRows)]
        let store = UsageStore(autoRefresh: false, previewOnly: true, language: sceneLanguage,
            registry: nil, primaryConnectorID: nil, consentDefaults: nil,
            preferences: agentPreferences, agentSettings: settings,
            previewPresentationCards: cards)
        if let matched {
            store.configureMatchedPreviewSnapshot(matched.snapshot)
            let canonicalEncoder = JSONEncoder()
            canonicalEncoder.outputFormatting = [.sortedKeys]
            let bytes = try canonicalEncoder.encode(matched)
            let record = MatchedDisplayedData(
                inputSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                snapshot: matched.snapshot, cards: matched.cards,
                initialRailExpanded: false, sourceHosted: false, foregroundAcceptance: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(record).write(
                to: output.appendingPathComponent("native-matched-data.json"), options: .atomic)
        } else if ProcessInfo.processInfo.environment["UMA015_NATIVE_DAILY_PLOT_FIXTURE"] == "1" {
            // Keep the ordinary no-history host fixture separate. This opt-in
            // uses only the existing preview snapshot and explicit account days.
            var dailySnapshot = store.snapshot
            dailySnapshot.accountDailyUsage = [
                AgentAccountUsageDay(day: "2026-10-07", tokens: 0),
                AgentAccountUsageDay(day: "2026-10-09", tokens: 1200)
            ]
            dailySnapshot.updatedAt = matchedDate
            dailySnapshot.providerSource = UsageSourceStatus(label: "Native daily fixture",
                scope: "preview only", capturedAt: matchedDate, isAvailable: true, freshness: .fresh)
            store.configureMatchedPreviewSnapshot(dailySnapshot)
        }
        let defaultsName = "UMA015.NativeAppStorage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let frameName = "UMA015.NativeFrame.\(UUID().uuidString)"
        defer { NSWindow.removeFrame(usingName: frameName) }
        let clipboard = AcceptanceClipboard()
        let actions = AcceptanceActions()
        let controller = MainWindowController(autosaveName: frameName, restoresSavedFrame: true)
        try writeNativeEntryPreflight("constructed", to: output, window: controller.window,
            originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult)
        controller.attach(store: store,
            openSettings: { actions.record() }, scanAll: { actions.record() },
            refreshAll: { actions.record() }, connectCodex: { actions.record() },
            disconnectCodex: { actions.record() }, claudeControlState: { .consentRequired },
            connectClaude: { actions.record() }, accuracySyncClaude: { actions.record() },
            hesectoriumStore: storage.store, promptClipboard: clipboard,
            promptPreferences: promptPreferences, appStorageDefaults: defaults)
        defer { controller.tearDown() }
        try writeNativeEntryPreflight("attached", to: output, window: controller.window,
            originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult)
        #expect(promptPreferences.isEphemeral && agentPreferences.isEphemeral)
        #expect(store.agentSettings === settings)
        #expect(!store.backgroundRefreshScheduled)
        controller.showDestination(.threadOS)
        try writeNativeEntryHostPhase("after-app-host-presentation", to: output)
        try writeNativeEntryPreflight("shown", to: output, window: controller.window,
            originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult)
        let window = try #require(controller.window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if let matrixScene {
            window.appearance = NSAppearance(named: matrixParts[1] == "dark" ? .darkAqua : .aqua)
            controller.showDestination(.agents)
            let visible = try #require(window.screen?.visibleFrame,
                "Physical matrix requires an identified visible screen.")
            _ = try #require(visible.width >= 1040 && visible.height >= 762,
                "Physical matched matrix needs a screen supporting 1040×762 outer points.")
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY,
                width: 1040, height: 762), display: true)
            let matrixContent = try #require(window.contentView)
            settle(matrixContent)
            let matrixKeyDeadline = Date().addingTimeInterval(2)
            while (!NSApp.isActive || NSApp.keyWindow !== window || !window.isKeyWindow),
                  Date() < matrixKeyDeadline {
                try requireNativeFixtureBeforeDeadline(runState)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            _ = try #require(NSApp.isActive && NSApp.keyWindow === window
                && window.isKeyWindow && window.isMainWindow,
                "Physical matrix requires the active key main window, not a source-hosted view.")
            #expect(abs(window.frame.width - 1040) <= 1 && abs(window.frame.height - 762) <= 1,
                    "Matched native candidate must use 1040×762 outer points.")
            if sceneState == "overflow" {
                window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY,
                    width: 760, height: 520), display: true)
                settle(matrixContent)
            }
            #expect(accessibilityElement(identifier: "uma.agent.reset-details.codex",
                in: matrixContent) == nil,
                "Future reset disclosure must be absent even when source data contains many reset dates.")
            try recordNativeDashboardViewport("agents-initial", in: matrixContent, window: window,
                output: output, runState: runState)
            let matrixRecord: [String: String] = [
                "scene": matrixScene, "fixture": "two supported providers; in-memory preview only",
                "window": "native production MainWindowController", "interactionScope": "visual matrix only"
            ]
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(matrixRecord).write(
                to: output.appendingPathComponent("native-matrix-scene.json"), options: .atomic)
            return
        }
        let normal = window.frame
        let requestedNormalOuter = window.frameRect(forContentRect: NSRect(
            origin: .zero, size: MainWindowFramePolicy.normalContentSize)).size
        let expectedNormalOuter = MainWindowFramePolicy.initialFrame(
            visibleFrames: NSScreen.screens.map(\.visibleFrame), outerSize: requestedNormalOuter)
        #expect(abs(normal.width - expectedNormalOuter.width) <= 1
                    && abs(normal.height - expectedNormalOuter.height) <= 1,
                "The initial native outer frame must follow the 1040×760 content and visible-screen policy.")
        let normalGap = normalContentGap(requestedOuter: requestedNormalOuter,
            policyVisibleFrame: NSScreen.screens.first?.visibleFrame,
            targetVisibleFrame: window.screen?.visibleFrame)
        try writeNativeEntryPreflight("normal-content-gate", to: output, window: window,
            originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult,
            normalContentGap: normalGap)
        if normalGap == nil {
            let nativeContent = window.contentRect(forFrameRect: normal)
            #expect(abs(nativeContent.width - MainWindowFramePolicy.normalContentSize.width) <= 1
                        && abs(nativeContent.height - MainWindowFramePolicy.normalContentSize.height) <= 1,
                    "A policy and target screen that fit the unclamped normal outer frame must retain 1040×760 native content.")
        }
        if let visibleFrame = window.screen?.visibleFrame,
           visibleFrame.width >= MainWindowFramePolicy.titlebarRecommendedOuterSize.width,
           visibleFrame.height >= MainWindowFramePolicy.titlebarRecommendedOuterSize.height {
            let benchmark = MainWindowFramePolicy.initialFrame(
                visibleFrames: [visibleFrame],
                outerSize: MainWindowFramePolicy.titlebarRecommendedOuterSize)
            window.setFrame(benchmark, display: true)
            try writeNativeEntryPreflight("benchmark", to: output, window: window,
                originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult,
                benchmarkExpected: benchmark, benchmarkSupported: true)
            #expect(abs(window.frame.width - benchmark.width) <= 1
                        && abs(window.frame.height - benchmark.height) <= 1,
                    "The visible screen must support the separate 1040×762 native outer benchmark.")
            window.setFrame(normal, display: true)
            try writeNativeEntryPreflight("normal-restored", to: output, window: window,
                originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult)
            #expect(abs(window.frame.width - normal.width) <= 1
                        && abs(window.frame.height - normal.height) <= 1)
        } else {
            try writeNativeEntryPreflight("benchmark-unsupported", to: output, window: window,
                originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult,
                benchmarkSupported: false,
                benchmarkGap: window.screen == nil ? "NO_WINDOW_SCREEN" : "VISIBLE_SCREEN_BELOW_1040x762")
        }
        let deadline = Date().addingTimeInterval(2)
        while (!NSApp.isActive || NSApp.keyWindow !== window || !window.isKeyWindow), Date() < deadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        try writeNativeEntryPreflight("after-key-wait", to: output, window: window,
            originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult)
        let pasteboardChangeCount = NSPasteboard.general.changeCount
        _ = try #require(NSApp.isActive && NSApp.keyWindow === window && window.isKeyWindow,
            "A visible window alone is not foreground keyboard acceptance; inspect native-entry-after-key-wait.json.")
        let content = try #require(window.contentView)
        settle(content)
        let copy = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.threados.prompt.generate-copy"
        } as? NSButton)
        let navigationControl = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.main.navigation"
        } as? NSSegmentedControl)
        let globalSettings = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.main.settings"
        } as? NSButton)
        let leaderModel = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.threados.prompt.role.leader.model"
        })
        for role in ThreadOSPromptRole.allCases {
            let selection = try #require(UMA015OriginalProducerGolden.selections[role])
            let modelControl = try #require(descendants(of: content).first {
                $0.accessibilityIdentifier() == "uma.threados.prompt.role.\(role.rawValue).model"
            } as? NSPopUpButton)
            let effortControl = try #require(descendants(of: content).first {
                $0.accessibilityIdentifier() == "uma.threados.prompt.role.\(role.rawValue).effort"
            } as? NSPopUpButton)
            try selectPromptOption(selection.model, in: modelControl, window: window)
            try selectPromptOption(selection.effort, in: effortControl, window: window)
            settle(content)
            let readback = ThreadOSPromptComposerForm(preferences: promptPreferences)
            #expect(readback.selection(for: role) == selection,
                    "Both real prompt controls must update and persist the selected role.")
        }
        if ProcessInfo.processInfo.environment["UMA015_NATIVE_POPUP_NEGATIVE"] == "1" {
            let leaderPopup = try #require(leaderModel as? NSPopUpButton)
            let original = try #require(leaderPopup.selectedItem?.representedObject as? String)
            let alternate = try #require(leaderPopup.itemArray.compactMap {
                $0.representedObject as? String
            }.first(where: { $0 != original }))
            var outcomes: [String: String] = [:]
            for mode in [PopupQueueTestMode.injectQueueFailure, .exitMenuEarly] {
                let started = Date()
                do {
                    try selectPromptOption(alternate, in: leaderPopup, window: window, testMode: mode)
                    Issue.record("The injected native popup negative path must not report success: \(mode).")
                } catch let error as PopupSelectionFailure {
                    let expected: PopupSelectionFailure = mode == .injectQueueFailure
                        ? .injectedQueueFailure : .notCommitted
                    #expect(error == expected)
                    outcomes[String(describing: mode)] = String(describing: error)
                }
                _ = try #require(leaderPopup.selectedItem?.representedObject as? String == original,
                    "A refused or early-exit popup event must preserve the original selection.")
                #expect(Date().timeIntervalSince(started) < 4,
                    "Each popup error or early exit must finish within its bounded menu deadline.")
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                #expect(leaderPopup.selectedItem?.representedObject as? String == original,
                    "A late queued event must not change a different response chain after menu exit.")
            }
            let data = try JSONSerialization.data(withJSONObject: outcomes,
                options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("native-popup-negative.json"), options: .atomic)
        }
        let goldenPrompt = try UMA015OriginalProducerGolden.load()
        #expect(ThreadOSPromptComposerForm(preferences: promptPreferences).generatedInstruction == goldenPrompt,
                "All eight edited values must match the executed original-producer bytes.")
        _ = try #require(window.makeFirstResponder(copy) && window.firstResponder === copy,
            "Copy must own keyboard focus before native event dispatch.")
        try nativeClick(copy, in: window)
        #expect(clipboard.writes == [goldenPrompt], "The injected clipboard must match the executed original producer.")
        _ = try #require(window.firstResponder === copy)
        try nativeKey(48, characters: "\t", in: window)
        _ = try #require(window.firstResponder === navigationControl)
        try nativeKey(48, characters: "\t", in: window)
        _ = try #require(window.firstResponder === globalSettings)
        try nativeKey(48, characters: "\t", in: window)
        _ = try #require(window.firstResponder === leaderModel)
        try nativeKey(48, characters: "\t", modifiers: [.shift], in: window)
        _ = try #require(window.firstResponder === globalSettings)
        try nativeKey(48, characters: "\t", modifiers: [.shift], in: window)
        _ = try #require(window.firstResponder === navigationControl)
        try nativeKey(48, characters: "\t", modifiers: [.shift], in: window)
        _ = try #require(window.firstResponder === copy)
        try nativeKey(36, characters: "\r", in: window)
        #expect(clipboard.writes == [goldenPrompt, goldenPrompt])
        try nativeKey(36, characters: "\r", modifiers: [.shift], in: window)
        #expect(clipboard.writes == [goldenPrompt, goldenPrompt, goldenPrompt],
                "Focused Shift+Return follows the ordinary enabled button action.")
        for modifier in [NSEvent.ModifierFlags.command, .control, .option] {
            try nativeKey(36, characters: "\r", modifiers: modifier, in: window)
            #expect(clipboard.writes.count == 3,
                    "Modified Return must not invoke the focused Copy action.")
        }

        try nativeNavigate(.agents, using: navigationControl, in: window)
        settle(content)
        try recordNativeDashboardViewport("agents-initial", in: content, window: window,
            output: output, runState: runState)
        try writeNativeAccessibilityTree(content, to: output.appendingPathComponent("agents-accessibility-tree.txt"))
        let claudeRow = try #require(accessibilityElement(
            identifier: "uma.agent.list.claude", in: content))
        try nativeClick(claudeRow, in: window)
        settle(content)
        _ = try #require(controller.selectedAgentForTesting == .claude,
            "A user click on the real rail row must select Claude before opening settings.")
        let gear = try #require(accessibilityElement(
            identifier: "uma.agent.selected-settings", in: content))
        try nativeClick(gear, in: window)
        let sheetDeadline = Date().addingTimeInterval(2)
        while window.attachedSheet == nil, Date() < sheetDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let sheet = try #require(window.attachedSheet)
        let sheetContent = try #require(sheet.contentView)
        try writeNativeAccessibilityTree(sheetContent, to: output.appendingPathComponent("claude-sheet-accessibility-tree.txt"))
        let labels = nativeSheetLabels(in: sheetContent)
        #expect(labels.contains { $0.contains("Claude Code") }, "The selected provider must render its coordinator-backed content.")
        #expect(!labels.contains { $0.contains("Settings for this agent are unavailable") })
        #expect(store.agentSettings?.entries.contains { $0.providerID == AgentPreferenceRecord.claudeProviderID } == true)
        let claudeMonitoring = try #require(accessibilityElement(
            identifier: "uma.agent.settings.monitoring.claude", in: sheetContent))
        #expect(settings.isMonitoringEnabled(for: AgentPreferenceRecord.claudeProviderID))
        try nativeClick(claudeMonitoring, in: sheet)
        #expect(!settings.isMonitoringEnabled(for: AgentPreferenceRecord.claudeProviderID),
                "The selected Claude setting must write to its own in-memory record.")
        #expect(settings.isMonitoringEnabled(for: AgentPreferenceRecord.codexProviderID),
                "Claude's setting must not change Codex.")
        let claudeMonitoringAgain = try #require(accessibilityElement(
            identifier: "uma.agent.settings.monitoring.claude", in: sheetContent))
        try nativeClick(claudeMonitoringAgain, in: sheet)
        #expect(settings.isMonitoringEnabled(for: AgentPreferenceRecord.claudeProviderID),
                "Re-enabling Claude through the same real sheet must restore its rail eligibility.")
        let done = try #require(accessibilityElement(label: "Done", in: sheetContent))
        let delayedKeyRegain = ProcessInfo.processInfo.environment["UMA015_NATIVE_DELAYED_KEY_REGAIN"] == "1"
        let alternateWindow = delayedKeyRegain ? NSWindow(
            contentRect: NSRect(x: window.frame.minX + 40, y: window.frame.minY + 40,
                                width: 320, height: 220),
            styleMask: [.titled, .closable], backing: .buffered, defer: false) : nil
        defer { alternateWindow?.orderOut(nil) }
        let keyLedger = NativeKeyNotificationLedger()
        let keyObserver = delayedKeyRegain ? NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { _ in keyLedger.record() } : nil
        defer { if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) } }
        func writeDelayedKeyState(_ stage: String) throws {
            guard delayedKeyRegain else { return }
            let state = [
                "stage": stage, "appActive": String(NSApp.isActive),
                "mainKey": String(window.isKeyWindow),
                "alternateKey": String(alternateWindow?.isKeyWindow == true),
                "keyWindowIsMain": String(NSApp.keyWindow === window),
                "firstResponder": String(describing: window.firstResponder),
                "focusedIdentifier": nativeFocusedIdentifier() ?? "nil",
                "realDidBecomeKeyCount": String(keyLedger.count)
            ]
            let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("delayed-key-\(stage).json"), options: .atomic)
        }
        try nativeClick(done, in: sheet)
        if let alternateWindow {
            alternateWindow.makeKeyAndOrderFront(nil)
            let alternateDeadline = Date().addingTimeInterval(2)
            while (!alternateWindow.isKeyWindow || NSApp.keyWindow !== alternateWindow),
                  Date() < alternateDeadline {
                try requireNativeFixtureBeforeDeadline(runState)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            try writeDelayedKeyState("alternate-key")
            _ = try #require(NSApp.isActive && alternateWindow.isKeyWindow
                && NSApp.keyWindow === alternateWindow && !window.isKeyWindow,
                "The real alternate test-host window must take key before sheet dismissal completes.")
        }
        let doneDeadline = Date().addingTimeInterval(2)
        while window.attachedSheet != nil, Date() < doneDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        _ = try #require(window.attachedSheet == nil)
        if delayedKeyRegain {
            RunLoop.main.run(until: Date().addingTimeInterval(0.65))
            try writeDelayedKeyState("sheet-closed-main-not-key")
            _ = try #require(NSApp.keyWindow === alternateWindow && !window.isKeyWindow,
                "The owning main window must remain non-key past the immediate focus retry deadline.")
            window.makeKeyAndOrderFront(nil)
            let regainedDeadline = Date().addingTimeInterval(2)
            while (!window.isKeyWindow || NSApp.keyWindow !== window || keyLedger.count == 0),
                  Date() < regainedDeadline {
                try requireNativeFixtureBeforeDeadline(runState)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            try writeDelayedKeyState("main-key-regained")
            _ = try #require(NSApp.isActive && window.isKeyWindow
                && NSApp.keyWindow === window && keyLedger.count > 0,
                "The owning main window must regain key through a real AppKit notification.")
        }
        let applicationForFocus = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var focusedElement: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(applicationForFocus,
            kAXFocusedUIElementAttribute as CFString, &focusedElement)
        var focusedIdentifier: CFTypeRef?
        if let focusedElement, CFGetTypeID(focusedElement) == AXUIElementGetTypeID() {
            _ = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement,
                kAXIdentifierAttribute as CFString, &focusedIdentifier)
        }
        try "firstResponder=\(String(describing: window.firstResponder))\nfocusedStatus=\(focusedStatus.rawValue)\nfocusedIdentifier=\(String(describing: focusedIdentifier))\n".write(
            to: output.appendingPathComponent("post-sheet-focus.txt"), atomically: true, encoding: .utf8)
        let focusDeadline = Date().addingTimeInterval(2)
        while nativeFocusedIdentifier() != "uma.agent.selected-settings", Date() < focusDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        _ = try #require(nativeFocusedIdentifier() == "uma.agent.selected-settings",
            "The real accessibility focus must return to the selected-agent settings control.")
        if delayedKeyRegain {
            try writeDelayedKeyState("focus-restored")
            _ = try #require((window.firstResponder as? NSView)?.accessibilityIdentifier()
                == "uma.agent.selected-settings",
                "The owning window responder must return to the selected-agent settings control after regaining key.")
        }
        let gearAgain = try #require(accessibilityElement(
            identifier: "uma.agent.selected-settings", in: content))
        try nativeClick(gearAgain, in: window)
        let reopenedDeadline = Date().addingTimeInterval(2)
        while window.attachedSheet == nil, Date() < reopenedDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let reopened = try #require(window.attachedSheet)
        try nativeKey(53, characters: "\u{1b}", in: reopened)
        let closeDeadline = Date().addingTimeInterval(2)
        while window.attachedSheet != nil, Date() < closeDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        _ = try #require(window.attachedSheet == nil)
        let escapeFocusDeadline = Date().addingTimeInterval(2)
        while nativeFocusedIdentifier() != "uma.agent.selected-settings", Date() < escapeFocusDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        _ = try #require(nativeFocusedIdentifier() == "uma.agent.selected-settings",
            "Escape closure must return actual AX focus to the selected-agent gear.")
        #expect(settings.isMonitoringEnabled(for: AgentPreferenceRecord.claudeProviderID),
                "Claude's re-enabled setting must survive sheet closure in the isolated coordinator.")
        let codexRow = try #require(accessibilityElement(
            identifier: "uma.agent.list.codex", in: content))
        try nativeClick(codexRow, in: window)
        settle(content)
        _ = try #require(controller.selectedAgentForTesting == .codex)
        let codexGear = try #require(accessibilityElement(
            identifier: "uma.agent.selected-settings", in: content))
        try nativeClick(codexGear, in: window)
        let codexSheetDeadline = Date().addingTimeInterval(2)
        while window.attachedSheet == nil, Date() < codexSheetDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let codexSheet = try #require(window.attachedSheet)
        let codexContent = try #require(codexSheet.contentView)
        let codexMonitoring = try #require(accessibilityElement(
            identifier: "uma.agent.settings.monitoring.codex", in: codexContent))
        try nativeClick(codexMonitoring, in: codexSheet)
        #expect(!settings.isMonitoringEnabled(for: AgentPreferenceRecord.codexProviderID))
        #expect(settings.isMonitoringEnabled(for: AgentPreferenceRecord.claudeProviderID),
                "Codex's monitoring switch must not disable Claude.")
        try nativeClick(codexMonitoring, in: codexSheet)
        #expect(settings.isMonitoringEnabled(for: AgentPreferenceRecord.codexProviderID),
                "The native Codex switch must restore monitoring before later reset checks.")
        let codexDone = try #require(accessibilityElement(label: "Done", in: codexContent))
        try nativeClick(codexDone, in: codexSheet)
        let codexCloseDeadline = Date().addingTimeInterval(2)
        while window.attachedSheet != nil, Date() < codexCloseDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        _ = try #require(window.attachedSheet == nil)
        let railDeadline = Date().addingTimeInterval(2)
        var claudeRowAgain = accessibilityElement(identifier: "uma.agent.list.claude", in: content)
        while claudeRowAgain == nil, Date() < railDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            claudeRowAgain = accessibilityElement(identifier: "uma.agent.list.claude", in: content)
        }
        try writeNativeAccessibilityTree(content, to: output.appendingPathComponent("post-codex-sheet-accessibility-tree.txt"))
        try nativeClick(try #require(claudeRowAgain,
            "The real Claude AX row must return after the Codex sheet closes."), in: window)
        #expect(controller.window === window && !store.backgroundRefreshScheduled)
        #expect(actions.count == 0 && storage.backend.mutations == 0)
        let currentNavigation = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.main.navigation"
        } as? NSSegmentedControl)
        try nativeNavigate(.threadOS, using: currentNavigation, in: window)
        try nativeNavigate(.agents, using: currentNavigation, in: window)
        #expect(controller.selectedAgentForTesting == .claude,
                "Native navigation must preserve the selected provider.")

        var exercisedStorageRoute = false
        for destination in [MainSurfaceDestination.threadOS, .sectorium, .agents,
                            .threadOS, .sectorium, .agents] {
            try nativeNavigate(destination, using: currentNavigation, in: window)
            settle(content)
            #expect(controller.destinationForTesting == destination)
            #expect(controller.attachedStoreIdentityForTesting == ObjectIdentifier(store))
            #expect(controller.selectedAgentForTesting == .claude)
            if destination == .sectorium {
                let sectoriumRefresh = try #require(descendants(of: content).first {
                    $0.accessibilityIdentifier() == "uma.sectorium.refresh"
                } as? NSButton)
                let observationsBeforeRefresh = storage.observer.observationCount
                try nativeClick(sectoriumRefresh, in: window)
                let observationDeadline = Date().addingTimeInterval(2)
                while storage.observer.observationCount == observationsBeforeRefresh,
                      Date() < observationDeadline {
                    try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                }
                #expect(storage.observer.observationCount == observationsBeforeRefresh + 3,
                        "Refresh must perform exactly three isolated identity observations: inventory, verified device, eject topology.")
                if !exercisedStorageRoute {
                    try exerciseIsolatedStorageAction(in: content, window: window, storage: storage, runState: runState)
                    try exerciseSectoriumReadinessAX(in: content, window: window,
                        storage: storage, runState: runState)
                    exercisedStorageRoute = true
                }
                #expect(storage.backend.mutations == 0 && storage.runner.mutationAttempts == 0,
                        "Refresh and guarded create-sheet actions must not dispatch storage mutations.")
            }
        }
        #expect(exercisedStorageRoute)
        do {
        let previousMenu = NSApp.mainMenu
        let shortcuts = AcceptanceShortcutActions()
        let menu = ApplicationMenuController(isolatedRoutes: .init(
            canRefreshAll: { true },
            openSettings: { shortcuts.settings += 1 },
            openMainWindow: { shortcuts.main += 1; controller.showCanonicalWindow() },
            showQuickPanel: { shortcuts.panel += 1 },
            toggleDesktopAssistant: { shortcuts.wizard += 1 },
            refreshAll: { shortcuts.refresh += 1 }
        ))
        menu.installMainMenu()
        defer { menu.tearDown(); NSApp.mainMenu = previousMenu }
        #expect(menu.diagnosticState.requiredRoutesPresent)
        _ = try #require(NSApp.mainMenu)
        _ = try #require(NSApp.isActive && window.isKeyWindow && NSApp.keyWindow === window)
        try nativeShortcut("1", keyCode: 18, in: window)
        try nativeShortcut("2", keyCode: 19, in: window)
        try nativeShortcut("r", keyCode: 15, in: window)
        try nativeShortcut(",", keyCode: 43, in: window)
        #expect(shortcuts.main == 1 && shortcuts.panel == 1 && shortcuts.refresh == 1 && shortcuts.settings == 1)
        #expect(shortcuts.wizard == 0)
        }
        controller.showAgent(.codex)
        settle(content)
        try writeNativeAccessibilityTree(content, to: output.appendingPathComponent("codex-no-reset-accessibility-tree.txt"))
        #expect(accessibilityElement(identifier: "uma.agent.reset-details.codex", in: content) == nil,
            "The native agent rail must not offer future reset disclosure.")
        let railScroll = try #require(descendants(of: content).compactMap { $0 as? NSScrollView }.first {
            let pane = $0.convert($0.bounds, to: content)
            return pane.width >= 180 && pane.width <= 250 && pane.minX < 260
        }, "The actual left rail scroll view must remain present.")
        let railDocument = try #require(railScroll.documentView)
        #expect(railDocument.bounds.height <= railScroll.contentView.bounds.height + 1,
                "Forty retained source reset dates must not inflate the two-provider rail.")
        let initial = window.frame
        window.setFrame(NSRect(x: initial.minX, y: initial.minY, width: 760, height: 520), display: true)
        settle(content)
        #expect(abs(window.frame.width - 760) <= 1 && abs(window.frame.height - 520) <= 1,
            "The preserved actual minimum is 760×520 outer points.")
        try writeNativeEntryPreflight("minimum-outer", to: output, window: window,
            originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult)
        try writeNativeAccessibilityTree(content,
            to: output.appendingPathComponent("minimum-outer-accessibility-tree.txt"))
        try recordNativeDashboardViewport("minimum-outer", in: content, window: window,
            output: output, runState: runState)
        try requireNativeDashboardGroups(in: content)
        if let visibleFrame = window.screen?.visibleFrame,
           visibleFrame.width >= 1040, visibleFrame.height >= 762 {
            window.setFrame(NSRect(x: initial.minX, y: initial.minY, width: 1040, height: 762), display: true)
            settle(content)
            try writeNativeEntryPreflight("resized-benchmark", to: output, window: window,
                originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult,
                benchmarkExpected: NSRect(x: initial.minX, y: initial.minY, width: 1040, height: 762),
                benchmarkSupported: true)
            #expect(abs(window.frame.width - 1040) <= 1 && abs(window.frame.height - 762) <= 1)
            try recordNativeDashboardViewport("benchmark-outer", in: content, window: window,
                output: output, runState: runState)
            try requireNativeDashboardGroups(in: content)
        } else {
            try writeNativeEntryPreflight("resized-benchmark-unsupported", to: output, window: window,
                originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult,
                benchmarkSupported: false, benchmarkGap: "VISIBLE_SCREEN_BELOW_1040x762")
        }
        if let visibleFrame = window.screen?.visibleFrame,
           visibleFrame.width >= 1280, visibleFrame.height >= 762 {
            window.setFrame(NSRect(x: initial.minX, y: initial.minY, width: 1280, height: 762), display: true)
            settle(content)
            try writeNativeEntryPreflight("resized-wide", to: output, window: window,
                originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult,
                benchmarkExpected: NSRect(x: initial.minX, y: initial.minY, width: 1280, height: 762),
                benchmarkSupported: true)
            #expect(abs(window.frame.width - 1280) <= 1 && abs(window.frame.height - 762) <= 1)
            try recordNativeDashboardViewport("wide-outer", in: content, window: window,
                output: output, runState: runState)
            try requireNativeDashboardGroups(in: content)
        } else {
            try writeNativeEntryPreflight("resized-wide-unsupported", to: output, window: window,
                originalActivationPolicy: originalActivationPolicy, policySetterResult: policySetterResult,
                benchmarkSupported: false, benchmarkGap: "VISIBLE_SCREEN_BELOW_1280x762")
        }
        window.setFrame(initial, display: true)
        window.zoom(nil)
        #expect(window.isZoomed || window.frame != initial,
                "Native zoom must visibly change the window state or frame.")
        window.zoom(nil)
        #expect(!window.isZoomed)
        let probeMode = ProcessInfo.processInfo.environment["UMA015_NATIVE_PROBE"]
        let fullTimerEntry = probeMode == nil || probeMode == "full-timer-entry"
        var fullscreenExited = false
        var stableSeconds = "nil"
        if fullTimerEntry {
            // Wait for the actual AppKit enter/exit notifications in the same
            // production window used by the keyboard and layout acceptance.
            var completed = false
            var transitionError: String?
            let screenID = window.screen?.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            runNativeFullscreenLeg(window: window, owner: "MainWindowController",
                expectedScreenID: screenID, output: output, label: "full-production",
                attachDelegate: true, runState: runState) { error in
                transitionError = error
                completed = true
            }
            let completionDeadline = Date().addingTimeInterval(30)
            while !completed && Date() < completionDeadline {
                try requireNativeFixtureBeforeDeadline(runState)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            _ = try #require(completed && transitionError == nil,
                "Native fullscreen must complete ordered enter/exit on the keyboard acceptance window: \(transitionError ?? "timeout").")
            fullscreenExited = !window.styleMask.contains(.fullScreen)
            stableSeconds = "notification-ordered; restored after 0.20s"
        } else {
            window.toggleFullScreen(nil)
            let fullscreenDeadline = Date().addingTimeInterval(4)
            while !window.styleMask.contains(.fullScreen), Date() < fullscreenDeadline {
                try requireNativeFixtureBeforeDeadline(runState)
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            #expect(window.styleMask.contains(.fullScreen), "Native fullscreen transition must complete.")
            window.toggleFullScreen(nil)
            let exitFullscreenDeadline = Date().addingTimeInterval(8)
            var exitedSince: Date?
            while Date() < exitFullscreenDeadline {
                try requireNativeFixtureBeforeDeadline(runState)
                if window.styleMask.contains(.fullScreen) {
                    exitedSince = nil
                } else if let exitedSince, Date().timeIntervalSince(exitedSince) >= 0.15 {
                    break
                } else if exitedSince == nil {
                    exitedSince = Date()
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            fullscreenExited = !window.styleMask.contains(.fullScreen)
                && exitedSince.map { Date().timeIntervalSince($0) >= 0.15 } == true
            stableSeconds = String(describing: exitedSince.map { Date().timeIntervalSince($0) })
        }
        let fullscreenRecord: [String: String] = [
            "exited": String(fullscreenExited),
            "styleMask": String(window.styleMask.rawValue),
            "active": String(NSApp.isActive),
            "key": String(window.isKeyWindow),
            "main": String(window.isMainWindow),
            "stableSeconds": stableSeconds,
            "outer": NSStringFromRect(window.frame)
        ]
        let fullscreenEncoder = JSONEncoder()
        fullscreenEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fullscreenEncoder.encode(fullscreenRecord).write(to: output.appendingPathComponent(
            "native-fullscreen-exit.json"), options: .atomic)
        _ = try #require(fullscreenExited,
            "Native fullscreen exit must remain stable before frame restoration.")
        window.setFrame(initial, display: true)
        window.saveFrame(usingName: frameName)
        let restored = MainWindowController(autosaveName: frameName)
        defer { restored.tearDown() }
        #expect(restored.frameForTesting == initial)
        #expect(controller.attachedStoreIdentityForTesting == ObjectIdentifier(store))
        #expect(store.coalescedScanRequests.value == 0 && !store.backgroundRefreshScheduled)
        #expect(NSPasteboard.general.changeCount == pasteboardChangeCount,
                "The injected Copy route must not mutate the system clipboard.")
        #expect(actions.count == 0 && storage.backend.mutations == 0)
        let previousWindowID = controller.windowIdentityForTesting
        controller.tearDown()
        #expect(!controller.isVisibleForTesting)
        let reattached = MainWindowController(autosaveName: frameName, restoresSavedFrame: true)
        defer { reattached.tearDown() }
        reattached.attach(store: store,
            openSettings: { actions.record() }, scanAll: { actions.record() },
            refreshAll: { actions.record() }, connectCodex: { actions.record() },
            disconnectCodex: { actions.record() }, claudeControlState: { .consentRequired },
            connectClaude: { actions.record() }, accuracySyncClaude: { actions.record() },
            hesectoriumStore: storage.store, promptClipboard: clipboard,
            promptPreferences: promptPreferences, appStorageDefaults: defaults)
        #expect(reattached.attachedStoreIdentityForTesting == ObjectIdentifier(store))
        #expect(reattached.windowIdentityForTesting != previousWindowID)
        #expect(reattached.frameForTesting == initial)
        #expect(store.coalescedScanRequests.value == 0 && !store.backgroundRefreshScheduled)
        #expect(actions.count == 0 && storage.backend.mutations == 0)
        reattached.tearDown()
        NSWindow.removeFrame(usingName: frameName)
        #expect(UserDefaults.standard.object(forKey: "NSWindow Frame \(frameName)") == nil,
                "The disposable native frame key must be removed after the fixture.")
        try requireNativeFixtureBeforeDeadline(runState)
        #expect(productionDefaultsSnapshot() == productionDefaultsBefore,
                "The isolated window must leave production prompt, agent and frame keys unchanged.")
    }

    private struct ProductionDefaultsSnapshot: Equatable {
        let prompt: Data?
        let agents: Data?
        let mainFrame: String?
    }

    private func productionDefaultsSnapshot() -> ProductionDefaultsSnapshot {
        let defaults = UserDefaults.standard
        return ProductionDefaultsSnapshot(
            prompt: defaults.data(forKey: ThreadOSPromptComposerPreferences.selections.name),
            agents: defaults.data(forKey: AgentPreferenceStore.key),
            mainFrame: defaults.string(forKey: "NSWindow Frame UMA014.MainWindow")
        )
    }

    private struct NativeViewportItem: Codable {
        let identifier: String
        let frameInContent: Geometry
        let frameInDocument: Geometry
        let visibleInScroll: Geometry
        let fullyVisibleWithoutScroll: Bool
        let requiredScrollDistance: CGFloat
    }

    private struct NativeViewportRecord: Codable {
        let stage: String
        let processID: Int32
        let windowNumber: Int
        let activeKeyMain: Bool
        let outer: Geometry
        let content: Geometry
        let scale: CGFloat
        let railWidth: CGFloat
        let metricStripHeight: CGFloat?
        let quotaStripHeight: CGFloat?
        let metricCardHeights: [String: CGFloat]
        let plotHeight: CGFloat?
        let plotState: String
        let plotSelector: String?
        let plotObjectIdentity: String?
        let plotFrameInContent: Geometry?
        let scrollOriginRestored: Bool?
        let groups: [NativeViewportItem]
        let missingGroups: [String]
    }

    private func recordNativeDashboardViewport(
        _ stage: String, in content: NSView, window: NSWindow, output: URL,
        runState: NativeEntryRunState
    ) throws {
        let ids = ["uma015.codex.metric-bounds", "uma015.codex.history-bounds",
                   "uma015.codex.source-bounds", "uma015.codex.activity-bounds"]
        var items: [NativeViewportItem] = []
        var missing: [String] = []
        for id in ids {
            guard let anchor = descendants(of: content).first(where: {
                $0.accessibilityIdentifier() == id
            }), let scroll = anchor.enclosingScrollView,
                let document = scroll.documentView else {
                missing.append(id)
                continue
            }
            let frame = anchor.convert(anchor.bounds, to: content)
            let documentFrame = anchor.convert(anchor.bounds, to: document)
            let visible = scroll.contentView.documentVisibleRect
            let overlap = documentFrame.intersection(visible)
            let fullyVisible = visible.insetBy(dx: -1, dy: -1).contains(documentFrame)
            let required = max(0, documentFrame.maxY - visible.maxY,
                               visible.minY - documentFrame.minY)
            items.append(NativeViewportItem(identifier: id,
                frameInContent: Geometry(rect: frame, kind: "content-points"),
                frameInDocument: Geometry(rect: documentFrame, kind: "scroll-document-points"),
                visibleInScroll: Geometry(rect: overlap.isNull ? .zero : overlap,
                    kind: "initial-unscrolled-overlap"),
                fullyVisibleWithoutScroll: fullyVisible,
                requiredScrollDistance: required))
        }
        let split = try #require(descendants(of: content).compactMap { $0 as? NSSplitView }.first,
            "The native agent rail must be measurable before the first scroll.")
        let rail = try #require(split.arrangedSubviews.first)
        let railWidth = rail.frame.width
        let geometryAnchors = descendants(of: content).reduce(into: [String: NSRect]()) { result, view in
            let id = view.accessibilityIdentifier()
            if !id.isEmpty, view.bounds.width > 0, view.bounds.height > 0 {
                result[id] = view.convert(view.bounds, to: content)
            }
        }
        let cardIDs = ["uma015.codex.metric-week", "uma015.codex.metric-total",
                       "uma015.codex.metric-local"]
        var cardHeights: [String: CGFloat] = [:]
        for id in cardIDs {
            if let frame = geometryAnchors[id] { cardHeights[id] = frame.height }
        }
        let metricStripHeight = geometryAnchors["uma015.codex.metric-bounds"]?.height
        let quotaStripHeight = geometryAnchors["uma015.codex.quota-bounds"]?.height
        // This concrete view is created only by the production daily plot's
        // background anchor. SwiftUI may replace its accessibility identifier
        // with the enclosing history module's identifier during re-layout.
        func actualPlot() -> AgentWorkspaceDailyPlotBoundsView? {
            descendants(of: content).compactMap { $0 as? AgentWorkspaceDailyPlotBoundsView }
                .first { $0.window === window && $0.bounds.height > 0 }
        }
        var plot = actualPlot()
        var scrollOriginRestored: Bool?
        if ProcessInfo.processInfo.environment["UMA015_NATIVE_DAILY_PLOT_FIXTURE"] == "1",
           stage == "minimum-outer",
           let historyAnchor = descendants(of: content).first(where: {
               $0.accessibilityIdentifier() == "uma015.codex.history-bounds"
           }), let scroll = historyAnchor.enclosingScrollView,
           let document = scroll.documentView {
            let originalOrigin = scroll.contentView.bounds.origin
            let history = historyAnchor.convert(historyAnchor.bounds, to: document)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: history.maxY))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(content)
            plot = actualPlot() ?? plot
            let probedVisible = scroll.contentView.documentVisibleRect
            scroll.contentView.scroll(to: originalOrigin)
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(content)
            let restoredOrigin = scroll.contentView.bounds.origin
            scrollOriginRestored = abs(restoredOrigin.x - originalOrigin.x) <= 1
                && abs(restoredOrigin.y - originalOrigin.y) <= 1
            #expect(scrollOriginRestored == true,
                "The daily plot probe must restore the original clip origin.")
            try "stage=\(stage) history=\(history) probedVisible=\(probedVisible) plot=\(String(describing: plot)) originalOrigin=\(originalOrigin) restoredOrigin=\(restoredOrigin) restored=\(scrollOriginRestored == true)\n"
                .write(to: output.appendingPathComponent("native-daily-scroll-probe.txt"),
                    atomically: true, encoding: .utf8)
            plot = actualPlot() ?? plot
        }
        let plotFrame = plot.map { $0.convert($0.bounds, to: content) }
        let plotHeight = plotFrame?.height
        let plotState = plot != nil ? "ACTUAL_DAILY_PLOT_NATIVE_ANCHOR"
            : ProcessInfo.processInfo.environment["UMA015_NATIVE_DAILY_PLOT_FIXTURE"] == "1"
                ? "CHART_NATIVE_GEOMETRY_UNAVAILABLE" : "NO_DAILY_BUCKETS_IN_FIXTURE"
        if ProcessInfo.processInfo.environment["UMA015_NATIVE_DAILY_PLOT_FIXTURE"] == "1" {
            try writeNativeAccessibilityTree(content,
                to: output.appendingPathComponent("native-daily-ax-\(stage).txt"))
            _ = try #require(plotHeight, "The explicit native daily fixture must render the actual production plot.")
            for label in ["2026-10-07: 0 tokens", "2026-10-08: unknown tokens",
                          "2026-10-09: 1,200 tokens"] {
                _ = try #require(accessibilityElement(label: label, in: content),
                    "The actual daily plot must expose the supplied zero, missing, and known days: \(label)")
            }
            _ = try #require(accessibilityElement(
                label: "Local calendar days · tokens · source: account history", in: content),
                "The native chart must retain its account source and local-day period label.")
        }
        let record = NativeViewportRecord(stage: stage,
            processID: ProcessInfo.processInfo.processIdentifier,
            windowNumber: window.windowNumber,
            activeKeyMain: NSApp.isActive && window.isKeyWindow && window.isMainWindow,
            outer: Geometry(rect: window.frame, kind: "outer"),
            content: Geometry(rect: window.contentRect(forFrameRect: window.frame), kind: "content"),
            scale: window.backingScaleFactor, railWidth: railWidth,
            metricStripHeight: metricStripHeight, quotaStripHeight: quotaStripHeight,
            metricCardHeights: cardHeights,
            plotHeight: plotHeight, plotState: plotState,
            plotSelector: plot.map { _ in "AgentWorkspaceDailyPlotBoundsView" },
            plotObjectIdentity: plot.map { String(describing: Unmanaged.passUnretained($0).toOpaque()) },
            plotFrameInContent: plotFrame.map { Geometry(rect: $0, kind: "content-points") },
            scrollOriginRestored: scrollOriginRestored,
            groups: items, missingGroups: missing)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(
            to: output.appendingPathComponent("native-viewport-\(stage).json"), options: .atomic)
        let requiredInitiallyVisible = stage == "benchmark-outer"
            ? ["uma015.codex.metric-bounds", "uma015.codex.history-bounds",
               "uma015.codex.source-bounds"] : []
        for id in requiredInitiallyVisible {
            let item = try #require(items.first(where: { $0.identifier == id }),
                "Missing actual native dashboard group: \(id)")
            #expect(item.fullyVisibleWithoutScroll,
                "The benchmark first screen must show \(id) without scrolling.")
        }
        if ProcessInfo.processInfo.environment["UMA015_NATIVE_DAILY_PLOT_FIXTURE"] == "1" {
            _ = try #require(missing.isEmpty,
                "Every actual native dashboard group must remain measurable at \(stage): \(missing)")
            let visibleRequired = stage == "minimum-outer"
                ? ["uma015.codex.metric-bounds"]
                : stage == "wide-outer"
                    ? ["uma015.codex.metric-bounds", "uma015.codex.history-bounds",
                       "uma015.codex.source-bounds"] : []
            for id in visibleRequired {
                let item = try #require(items.first(where: { $0.identifier == id }))
                #expect(item.fullyVisibleWithoutScroll,
                    "The actual chart fixture must preserve first-screen \(id) at \(stage).")
            }
        }
        #expect(railWidth >= 224 && railWidth <= 248,
                "The measured native rail must remain within 224–248 points.")
        if stage == "benchmark-outer" {
            let strip = try #require(metricStripHeight, "Native metric strip was not measurable.")
            #expect(strip >= 64 && strip <= 88,
                    "The initial metric strip must remain within 64–88 points.")
            let quotas = try #require(quotaStripHeight,
                "The real quota comparison must remain measurable.")
            #expect(quotas >= 32 && quotas <= 110,
                "The graphical quota comparison must remain compact at benchmark width.")
            for id in cardIDs {
                let height = try #require(cardHeights[id], "Native metric cell was not measurable: \(id)")
                #expect(height >= 64 && height <= 88,
                        "Native metric cell height must remain within 64–88 points: \(id)")
            }
        }
        if let plotHeight {
            #expect(plotHeight >= 160 && plotHeight <= 210,
                    "An actual daily plot must remain within 160–210 points.")
        }
        if ProcessInfo.processInfo.environment["UMA015_NATIVE_CAPTURE_STAGE"] == stage {
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                try requireNativeFixtureBeforeDeadline(runState)
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
        }
    }

    private func requireNativeDashboardGroups(in content: NSView) throws {
        let groupIDs = ["uma015.codex.metric-bounds", "uma015.codex.history-bounds",
                        "uma015.codex.source-bounds", "uma015.codex.activity-bounds"]
        for id in groupIDs {
            let anchor = try #require(descendants(of: content).first { $0.accessibilityIdentifier() == id })
            let scroll = try #require(anchor.enclosingScrollView)
            let document = try #require(scroll.documentView)
            let clip = scroll.contentView
            let rect = anchor.convert(anchor.bounds, to: document)
            let original = clip.bounds.origin
            let maximum = max(0, document.bounds.height - clip.bounds.height)
            let target = max(0, min(maximum, rect.midY - clip.bounds.height / 2))
            clip.scroll(to: NSPoint(x: original.x, y: target))
            scroll.reflectScrolledClipView(clip)
            settle(content)
            #expect(clip.documentVisibleRect.contains(rect), "Full native group must be reachable: \(id)")
            clip.scroll(to: original)
            scroll.reflectScrolledClipView(clip)
            settle(content)
        }
    }

    private func writeNativeAccessibilityTree(_ root: NSView, to url: URL) throws {
        var lines: [String] = []
        func visit(_ node: Any, depth: Int) {
            guard depth < 32 && lines.count < 3000 else { return }
            if let element = node as? NSAccessibilityElement {
                let frame = element.accessibilityFrame()
                lines.append("\(depth) element id=\(element.accessibilityIdentifier() ?? "") label=\(element.accessibilityLabel() ?? "") role=\(String(describing: element.accessibilityRole())) frame=\(frame)")
                for child in element.accessibilityChildren() ?? [] { visit(child, depth: depth + 1) }
            } else if let view = node as? NSView {
                lines.append("\(depth) view=\(type(of: view)) id=\(view.accessibilityIdentifier()) frame=\(view.frame)")
                for child in view.accessibilityChildren() ?? [] { visit(child, depth: depth + 1) }
                for child in view.subviews { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        func visitAX(_ node: AXUIElement, depth: Int) {
            guard depth < 20 && lines.count < 5000 else { return }
            var id: CFTypeRef?
            var label: CFTypeRef?
            var role: CFTypeRef?
            let idStatus = AXUIElementCopyAttributeValue(node, kAXIdentifierAttribute as CFString, &id)
            _ = AXUIElementCopyAttributeValue(node, kAXTitleAttribute as CFString, &label)
            _ = AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &role)
            var description: CFTypeRef?
            var value: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(node, kAXDescriptionAttribute as CFString, &description)
            _ = AXUIElementCopyAttributeValue(node, kAXValueAttribute as CFString, &value)
            lines.append("AX \(depth) status=\(idStatus.rawValue) id=\(String(describing: id)) title=\(String(describing: label)) description=\(String(describing: description)) value=\(String(describing: value)) role=\(String(describing: role))")
            var children: CFTypeRef?
            let childrenStatus = AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &children)
            if let children = children as? [AXUIElement] {
                for child in children { visitAX(child, depth: depth + 1) }
            } else {
                lines.append("AX children status=\(childrenStatus.rawValue) value=\(String(describing: children))")
            }
        }
        visitAX(application, depth: 0)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func accessibilityElement(
        identifier: String? = nil, label: String? = nil,
        role: String? = nil, in root: NSView
    ) -> AXUIElement? {
        guard root.window != nil else { return nil }
        // SwiftUI row and sheet controls are exposed through the process AX tree,
        // not NSHostingView.accessibilityChildren() in this native test host.
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
        }
        func search(_ node: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 48 else { return nil }
            let nodeID = attribute(node, kAXIdentifierAttribute as CFString) as? String
            let nodeLabel = (attribute(node, kAXTitleAttribute as CFString) as? String)
                ?? (attribute(node, kAXDescriptionAttribute as CFString) as? String)
                ?? (attribute(node, kAXValueAttribute as CFString) as? String)
            let nodeRole = attribute(node, kAXRoleAttribute as CFString) as? String
            if (identifier == nil || nodeID == identifier)
                && (label == nil || nodeLabel == label)
                && (role == nil || nodeRole == role) { return node }
            for child in (attribute(node, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? [] {
                if let match = search(child, depth: depth + 1) { return match }
            }
            return nil
        }
        return search(application, depth: 0)
    }

    private func nativePressDisclosure(_ element: AXUIElement, in window: NSWindow) throws {
        _ = try #require(NSApp.isActive && window.isKeyWindow
            && NSApp.keyWindow === window && window.isMainWindow,
            "Native disclosure action requires the actual active/key/main window.")
        var role: CFTypeRef?
        var value: CFTypeRef?
        _ = try #require(AXUIElementCopyAttributeValue(element,
            kAXRoleAttribute as CFString, &role) == .success
            && (role as? String) == "AXDisclosureTriangle"
            && AXUIElementCopyAttributeValue(element,
                kAXValueAttribute as CFString, &value) == .success
            && (value as? NSNumber)?.intValue == 0,
            "The actual collapsed disclosure triangle must be the action target.")
        _ = try #require(AXUIElementPerformAction(element,
            kAXPressAction as CFString) == .success,
            "The native disclosure triangle must accept Press.")
    }

    private func nativeClick(_ element: AXUIElement, in window: NSWindow) throws {
        _ = try #require(NSApp.isActive && window.isKeyWindow && NSApp.keyWindow === window,
            "Accessibility-target click requires the actual active/key native window.")
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        _ = try #require(AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString,
            &positionValue) == .success && AXUIElementCopyAttributeValue(element,
            kAXSizeAttribute as CFString, &sizeValue) == .success,
            "The actual accessibility target must expose its screen position and size.")
        var position = CGPoint.zero
        var size = CGSize.zero
        let rawPosition = try #require(positionValue)
        let rawSize = try #require(sizeValue)
        _ = try #require(CFGetTypeID(rawPosition) == AXValueGetTypeID()
            && CFGetTypeID(rawSize) == AXValueGetTypeID(),
            "The accessibility target must expose AX position and size values.")
        _ = try #require(AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position)
            && AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
            && size.width > 0 && size.height > 0,
            "The real accessibility target must have a positive onscreen frame.")
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screenFrame = CGRect(x: position.x, y: primaryTop - position.y - size.height,
                                 width: size.width, height: size.height)
        let windowFrame = window.convertFromScreen(screenFrame)
        let point = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        _ = try #require(window.contentView.map { $0.bounds.contains($0.convert(point, from: nil)) } == true,
            "The real accessibility control must lie within the target native window.")
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            window.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func nativeClick(_ view: NSView, at localPoint: NSPoint? = nil, in window: NSWindow) throws {
        _ = try #require(NSApp.isActive && window.isKeyWindow && NSApp.keyWindow === window,
            "Native click requires the actual active/key target window.")
        _ = try #require(view.window === window && window.firstResponder != nil,
            "Native click requires an attached target and actual responder.")
        let local = localPoint ?? NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        let point = view.convert(local, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            window.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func nativeNavigate(_ destination: MainSurfaceDestination,
                                using control: NSSegmentedControl, in window: NSWindow) throws {
        let index = try #require(MainSurfaceDestination.allCases.firstIndex(of: destination))
        let segmentWidth = control.bounds.width / CGFloat(control.segmentCount)
        try nativeClick(control, at: NSPoint(x: (CGFloat(index) + 0.5) * segmentWidth,
                                             y: control.bounds.midY), in: window)
        _ = try #require(control.selectedSegment == index,
            "The destination must be selected by the actual native navigation control.")
    }

    private func exerciseIsolatedStorageAction(in content: NSView, window: NSWindow,
                                                storage: StorageFixture, runState: NativeEntryRunState) throws {
        let selectionDeadline = Date().addingTimeInterval(2)
        while storage.store.inventoryState == .loading, Date() < selectionDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            settle(content)
        }
        _ = try #require(storage.store.inventoryState == .available,
            "Isolated Sectorium inventory did not become available; observations=\(storage.observer.observationCount), state=\(storage.store.inventoryState).")
        _ = try #require(storage.store.workbench.selectedDeviceID == storage.observer.device.id,
            "The fixture's single verified physical drive must be selected by the normal default-selection policy.")
        _ = try #require(accessibilityElement(
            identifier: "uma.sectorium.selected-drive.disk81", in: content),
            "The selected drive must appear in the real native accessibility tree.")
        let create = try #require(descendants(of: content).first {
            $0.accessibilityIdentifier() == "uma.sectorium.create"
        } as? NSButton)
        try nativeClick(create, in: window)
        let sheetDeadline = Date().addingTimeInterval(2)
        while window.attachedSheet == nil, Date() < sheetDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let sheet = try #require(window.attachedSheet)
        let sheetContent = try #require(sheet.contentView)
        if let path = ProcessInfo.processInfo.environment["UMA015_FOREGROUND_ACCEPTANCE_DIR"] {
            try writeNativeAccessibilityTree(sheetContent,
                to: URL(fileURLWithPath: path).appendingPathComponent("storage-create-sheet-tree.txt"))
        }
        let encrypt = try #require(accessibilityElement(label: "Encrypt this disk", in: sheetContent))
        try nativeClick(encrypt, in: sheet)
        settle(sheetContent)
        let guardedCreate = try #require(accessibilityElement(label: "Choose location and create", in: sheetContent))
        var enabled: CFTypeRef?
        _ = try #require(AXUIElementCopyAttributeValue(guardedCreate,
            kAXEnabledAttribute as CFString, &enabled) == .success && (enabled as? Bool) == false,
            "The real create action must be disabled when encryption has no password.")
        try nativeClick(guardedCreate, in: sheet)
        #expect(storage.backend.mutations == 0 && storage.runner.mutationAttempts == 0,
                "A disabled storage operation must never reach its injected backend or runner.")
        let cancel = try #require(accessibilityElement(label: "Cancel", in: sheetContent))
        try nativeClick(cancel, in: sheet)
    }

    private func exerciseSectoriumReadinessAX(in content: NSView, window: NSWindow,
                                              storage: StorageFixture, runState: NativeEntryRunState) throws {
        let closeDeadline = Date().addingTimeInterval(2)
        while window.attachedSheet != nil, Date() < closeDeadline {
            try requireNativeFixtureBeforeDeadline(runState)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        _ = try #require(window.attachedSheet == nil && NSApp.isActive && window.isKeyWindow,
            "Readiness AX validation requires the unobscured active production window.")
        storage.store.deactivateWorkbench()
        let device = storage.observer.device
        let legacy = HESectoriumService.LegacyDevelopmentDisplay(name: "DEV_NEBULA",
            mountPoint: "/Volumes/Nebula", logicalCapacityBytes: 321_912_791_040, state: .mounted)
        let cases: [(SectoriumWorkbenchReadiness, String, String)] = [
            (.connected, "Started, not yet managed", "DEV_NEBULA"),
            (.operationInProgress("start:interrupted"), "In progress", "needs attention"),
            (.partialFailure("partial stop"), "Partially completed", "stopped before completion"),
            (.unknown("inventory topology was not verified"), "Unknown", "could not be verified"),
            (.awaitingUnlock, "Unlock required", "unlock the image explicitly"),
            (.noDevice, "Choose a drive", "select a physical drive"),
            (.readOnly, "Read-only", "read-only"),
            (.ejected, "Ejected", "no longer mounted")
        ]
        func axValue(_ identifier: String) throws -> String {
            let element = try #require(accessibilityElement(identifier: identifier, in: content),
                "The production Sectorium readiness element must exist in the actual app AX tree: \(identifier).")
            var value: CFTypeRef?
            _ = try #require(AXUIElementCopyAttributeValue(element,
                kAXValueAttribute as CFString, &value) == .success)
            return try #require(value as? String)
        }
        for (readiness, expectedTitle, expectedSummary) in cases {
            storage.store.apply(devices: [device], profiles: [], readiness: readiness,
                pending: nil, discoveredLegacy: true, legacyByDevice: [device.id: legacy])
            settle(content)
            let title = try axValue("uma.sectorium.readiness-title")
            let summary = try axValue("uma.sectorium.readiness-summary")
            #expect(title.contains(expectedTitle), "Actual production AX title did not update for \(readiness): \(title)")
            #expect(summary.localizedCaseInsensitiveContains(expectedSummary),
                "Actual production AX summary did not update for \(readiness): \(summary)")
        }
        storage.store.apply(devices: [device], profiles: [], readiness: .noDevelopmentDisk,
            pending: nil, discoveredLegacy: false, legacyByDevice: [:])
        settle(content)
        #expect(storage.backend.mutations == 0 && storage.runner.mutationAttempts == 0)
    }

    private func nativeFocusedIdentifier() -> String? {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application,
            kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var identifier: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement,
            kAXIdentifierAttribute as CFString, &identifier) == .success else { return nil }
        return identifier as? String
    }

    private func nativeSheetLabels(in root: NSView) -> [String] {
        guard root.window != nil else { return [] }
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
        }
        func findSheet(_ node: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 32 else { return nil }
            if (attribute(node, kAXRoleAttribute as CFString) as? String) == "AXSheet" { return node }
            for child in (attribute(node, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? [] {
                if let sheet = findSheet(child, depth: depth + 1) { return sheet }
            }
            return nil
        }
        func labels(_ node: AXUIElement, depth: Int) -> [String] {
            guard depth < 32 else { return [] }
            let own = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
                .compactMap { attribute(node, $0 as CFString) as? String }
            let children = ((attribute(node, kAXChildrenAttribute as CFString) as? [AXUIElement]) ?? [])
                .flatMap { labels($0, depth: depth + 1) }
            return own + children
        }
        guard let sheet = findSheet(application, depth: 0) else { return [] }
        return labels(sheet, depth: 0)
    }

    private func nativeKey(_ keyCode: UInt16, characters: String,
                           modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) throws {
        _ = try #require(NSApp.isActive && window.isKeyWindow && NSApp.keyWindow === window,
            "Native key dispatch requires the actual active/key target window.")
        _ = try #require(window.firstResponder != nil,
            "Native key dispatch requires the actual window responder chain.")
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false,
            keyCode: keyCode) else { return }
        window.sendEvent(event)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private enum PopupQueueTestMode: Equatable, Sendable { case normal, injectQueueFailure, exitMenuEarly }
    private enum PopupSelectionFailure: Error, Equatable {
        case injectedQueueFailure, menuTimedOut, notCommitted
    }

    private func recordNativePopupTrace(_ stage: String, popup: NSPopUpButton,
                                        window: NSWindow, target: String) {
        guard let root = ProcessInfo.processInfo.environment["UMA015_FOREGROUND_ACCEPTANCE_DIR"] else { return }
        let record: [String: Any] = [
            "stage": stage, "uptime": ProcessInfo.processInfo.systemUptime,
            "target": target, "selected": popup.selectedItem?.representedObject as? String ?? "nil",
            "selectedIndex": popup.indexOfSelectedItem, "itemCount": popup.numberOfItems,
            "active": NSApp.isActive, "key": window.isKeyWindow,
            "keyWindowIsTarget": NSApp.keyWindow === window,
            "popupWindowIsTarget": popup.window === window,
            "firstResponder": window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil",
            "popupIsFirstResponder": window.firstResponder === popup,
            "highlightedMenuItem": popup.menu?.highlightedItem?.title ?? "nil",
            "currentEventType": NSApp.currentEvent.map { String(describing: $0.type) } ?? "nil"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record,
                    options: [.sortedKeys, .fragmentsAllowed]),
              let newline = "\n".data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: root).appendingPathComponent("native-popup-events.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.write(newline)
    }

    private func selectPromptOption(_ value: String, in popup: NSPopUpButton, window: NSWindow,
                                    testMode: PopupQueueTestMode = .normal) throws {
        _ = try #require(NSApp.isActive && window.isKeyWindow && NSApp.keyWindow === window,
            "Prompt control edit requires the actual active/key target window.")
        _ = try #require(popup.window === window && popup.isEnabled && window.makeFirstResponder(popup),
            "Prompt control edit requires an attached, enabled first responder.")
        let index = try #require(popup.itemArray.firstIndex { ($0.representedObject as? String) == value })
        let current = try #require(popup.indexOfSelectedItem >= 0 ? popup.indexOfSelectedItem : nil)
        let direction: (UInt16, String) = index >= current ? (125, "\u{F701}") : (126, "\u{F700}")
        recordNativePopupTrace("before-space", popup: popup, window: window, target: value)
        var queuedError: Error?
        var menuTimedOut = false
        let keyboardTimer = Timer(timeInterval: 0.05, repeats: false) { _ in
            recordNativePopupTrace("timer-fired", popup: popup, window: window, target: value)
            do {
                if testMode == .injectQueueFailure { throw PopupSelectionFailure.injectedQueueFailure }
                if testMode == .exitMenuEarly {
                    try queuePopupKey(53, characters: "\u{1B}", in: window)
                    return
                }
                for _ in 0..<abs(index - current) {
                    try queuePopupKey(direction.0, characters: direction.1, in: window)
                }
                recordNativePopupTrace("before-return", popup: popup, window: window, target: value)
                try queuePopupKey(36, characters: "\r", in: window)
            } catch {
                queuedError = error
                try? queuePopupKey(53, characters: "\u{1B}", in: window)
            }
        }
        let menuDeadlineTimer = Timer(timeInterval: 3, repeats: false) { _ in
            menuTimedOut = true
            popup.menu?.cancelTracking()
        }
        RunLoop.main.add(keyboardTimer, forMode: .common)
        RunLoop.main.add(menuDeadlineTimer, forMode: .common)
        defer {
            keyboardTimer.invalidate()
            menuDeadlineTimer.invalidate()
        }
        // Space opens the real popup; queue arrow and Return after its tracking
        // loop starts so AppKit consumes them as keyboard input.
        try nativeKey(49, characters: " ", in: window)
        recordNativePopupTrace("after-space", popup: popup, window: window, target: value)
        if menuTimedOut { throw PopupSelectionFailure.menuTimedOut }
        if let queuedError { throw queuedError }
        let deadline = Date().addingTimeInterval(2)
        while (popup.selectedItem?.representedObject as? String) != value, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        guard (popup.selectedItem?.representedObject as? String) == value else {
            recordNativePopupTrace("not-committed", popup: popup, window: window, target: value)
            throw PopupSelectionFailure.notCommitted
        }
        recordNativePopupTrace("committed", popup: popup, window: window, target: value)
    }

    private func queuePopupKey(_ keyCode: UInt16, characters: String, in window: NSWindow) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
            NSApp.postEvent(event, atStart: false)
        }
    }

    private func nativeShortcut(_ key: String, keyCode: UInt16, in window: NSWindow) throws {
        _ = try #require(NSApp.isActive && window.isKeyWindow && NSApp.keyWindow === window,
            "Shortcut delivery requires the actual key production window.")
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: key,
            charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode))
        NSApp.sendEvent(event)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private final class AcceptanceShortcutActions {
        var settings = 0
        var main = 0
        var panel = 0
        var refresh = 0
        var wizard = 0
    }

    private final class AcceptanceClipboard: ThreadOSSettingsClipboard {
        private(set) var writes: [String] = []
        func write(_ string: String) -> Bool { writes.append(string); return true }
    }

    private final class AcceptanceActions {
        private(set) var count = 0
        func record() { count += 1 }
    }

    private struct MatchedInput: Codable {
        let snapshot: UsageSnapshot
        let cards: [SharedUsageCardPresentation]
    }

    private struct MatchedDisplayedData: Codable {
        let inputSHA256: String
        let snapshot: UsageSnapshot
        let cards: [SharedUsageCardPresentation]
        let initialRailExpanded: Bool
        let sourceHosted: Bool
        let foregroundAcceptance: Bool
    }

    private func matchedInput(language: AppLanguage, fixedDate: Date) throws -> MatchedInput? {
        guard let directory = ProcessInfo.processInfo.environment["UMA015_MATCHED_INPUT_DIR"] else { return nil }
        let location = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(language == .english ? "en.json" : "zh.json")
        if FileManager.default.fileExists(atPath: location.path) {
            return try JSONDecoder().decode(MatchedInput.self, from: Data(contentsOf: location))
        }
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        var snapshot = UsageSnapshot.preview(language: language)
        snapshot.updatedAt = fixedDate
        snapshot.accountDailyUsage = [
            AgentAccountUsageDay(day: "2026-10-07", tokens: 0),
            AgentAccountUsageDay(day: "2026-10-09", tokens: 1200)
        ]
        snapshot.providerSource = UsageSourceStatus(label: "Matched account fixture",
            scope: "preview only", capturedAt: fixedDate, isAvailable: true)
        snapshot.localSource = UsageSourceStatus(label: "Matched local fixture",
            scope: "preview only", capturedAt: fixedDate, isAvailable: true, coverage: 100)
        let input = MatchedInput(snapshot: snapshot, cards: [
            previewCard(product: .codex, remaining: 24),
            previewCard(product: .claude, remaining: 24)
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(input).write(to: location, options: .atomic)
        return input
    }

    private func previewCard(product: ProviderProductID, remaining: Double,
                             freshness: SharedUsageFreshness = .fresh,
                             loading: Bool = false, manyWindows: Bool = false,
                             resetRows: Int? = nil, longResetText: Bool = false)
        -> SharedUsageCardPresentation {
        let id = ProviderProductStatePolicy.connectorID(for: product)!.rawValue
        let value: SharedRemainingValue = freshness == .unavailable ? .unavailable : .finite(remaining)
        let windows = (0..<(resetRows ?? (manyWindows ? 14 : 1))).map { index in
            SharedUsageWindowPresentation(
                id: "\(id)-seven-day-\(index)", kind: .sevenDay,
                compactLabel: "7D",
                accessibilityLabel: "seven-day remaining",
                remaining: value, resetsAt: Date(timeIntervalSince1970: 1_800_003_600 + Double(index * 3600)),
                resetText: longResetText
                    ? "Long reset window description for native text wrapping and disclosure inspection"
                    : "Resets later"
            )
        }
        return SharedUsageCardPresentation(
            id: id, providerName: product.displayName,
            planLabel: "plus", connectionStatus: loading ? .transitional : (freshness == .unavailable ? .unavailable : .connected),
            freshness: loading ? .cached : freshness, windows: windows, selectedWindowID: windows.first?.id,
            remaining: value, sourceDescription: "Synthetic isolated preview fixture",
            severity: .normal, isRetainingLastValidValue: loading,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    @Test("isolated Sectorium native action binding refuses disabled dispatch")
    func disabledSectoriumActionNeverDispatches() throws {
        _ = NSApplication.shared
        let actions = AcceptanceActions()
        let disabled = NSHostingView(rootView: SectoriumWorkbenchButton(
            title: "Disabled fixture action", identifier: "uma.sectorium.fixture.disabled",
            isEnabled: false, action: { actions.record() }))
        disabled.frame = NSRect(x: 0, y: 0, width: 220, height: 42)
        settle(disabled)
        let disabledButton = try #require(descendants(of: disabled).first {
            $0.accessibilityIdentifier() == "uma.sectorium.fixture.disabled"
        } as? NSButton)
        #expect(!disabledButton.isEnabled)
        disabledButton.performClick(nil)
        #expect(actions.count == 0)
        let enabled = NSHostingView(rootView: SectoriumWorkbenchButton(
            title: "Allowed fixture action", identifier: "uma.sectorium.fixture.allowed",
            isEnabled: true, action: { actions.record() }))
        enabled.frame = NSRect(x: 0, y: 0, width: 220, height: 42)
        settle(enabled)
        let allowedButton = try #require(descendants(of: enabled).first {
            $0.accessibilityIdentifier() == "uma.sectorium.fixture.allowed"
        } as? NSButton)
        #expect(allowedButton.isEnabled)
        allowedButton.performClick(nil)
        #expect(actions.count == 1)
    }

    @Test func selectedAgentSettingsUseCanonicalConnectorIdentities() {
        #expect(ProviderProductID.codex.settingsProviderID == "codex")
        #expect(ProviderProductID.claude.settingsProviderID == "claude")
        #expect(ProviderProductID.workBuddy.settingsProviderID == "workbuddy")
        #expect(ProviderProductID.antigravity.settingsProviderID == "antigravity")
        for product in ProviderProductID.allCases {
            #expect(AgentConnectorID(rawValue: product.settingsProviderID) != nil)
        }
    }

    @Test func previewCardsSurviveMonitoringOffOnWithoutConnectorPublication() {
        let preferences = ApplicationPreferences.inMemory()
        let settings = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: preferences),
            shippedProviders: [(AgentPreferenceRecord.codexProviderID, "Codex"),
                               (AgentPreferenceRecord.claudeProviderID, "Claude Code")]
        )
        let cards = [previewCard(product: .codex, remaining: 24),
                     previewCard(product: .claude, remaining: 36)]
        let store = UsageStore(autoRefresh: false, previewOnly: true, language: .english,
            registry: nil, primaryConnectorID: nil, consentDefaults: nil,
            preferences: preferences, agentSettings: settings,
            previewPresentationCards: cards)
        #expect(store.presentationCards == cards)
        settings.setMonitoringEnabled(false, for: AgentPreferenceRecord.codexProviderID)
        #expect(store.presentationCards.map(\.id) == [cards[1].id])
        settings.setMonitoringEnabled(true, for: AgentPreferenceRecord.codexProviderID)
        #expect(store.presentationCards == cards)
        #expect(store.productInventory.provider(.codex)?.quotas.isEmpty == false)
    }

    @Test func promptDraftMigrationIsConfinedToExplicitInMemoryPreferences() throws {
        let preferences = ApplicationPreferences.inMemory()
        let independentPreferences = ApplicationPreferences.inMemory()
        #expect(preferences.isEphemeral && preferences.persistenceIdentifier == nil)
        var legacy = FactoriumV2SettingsDraft(project: "UMA015_MEMORY_ONLY",
            catalogRevision: "sol-luna-20260922.1", id: "cfg-uma015-memory-only")
        legacy.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .leader)
        legacy.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .qa)
        ThreadOSSettingsPreferences.saveFactoriumV2(legacy, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(legacy.project, to: preferences)

        let form = FactoriumV2FormState(preferences: preferences)
        #expect(form.draft.catalogRevision == ThreadOSSettingsCodec.latestCatalogRevision)
        #expect(form.draft.roles[.leader]?.selection.model == "gpt-6.1-sol")
        #expect(form.draft.roles[.qa]?.selection.model == "gpt-6.1-sol")
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: legacy.project, from: preferences) == form.draft)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: legacy.project, from: preferences) == legacy)
        #expect(ThreadOSSettingsPreferences.factoriumV2Projects(from: independentPreferences).isEmpty)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshots(project: legacy.project, from: independentPreferences).isEmpty)
        #expect(preferences.isEphemeral && preferences.persistenceIdentifier == nil)
    }

    private func capture(destination: MainSurfaceDestination, language: AppLanguage, dark: Bool,
                         sizeName: String, size: NSSize, output: URL,
                         variant: String? = nil, cards: [SharedUsageCardPresentation] = [],
                         accountDailyUsage: [AgentAccountUsageDay] = [],
                         previewCapturedAt: Date? = nil) async throws -> Capture {
        let baseName = "\(destination.rawValue.lowercased())-\(sizeName)-\(language == .english ? "en" : "zh")-\(dark ? "dark" : "light")"
        let name = variant.map { "\(baseName)-\($0)" } ?? baseName
        let fixture = try StorageFixture(root: output.appendingPathComponent("fixtures/\(name)", isDirectory: true))
        defer { fixture.store.deactivateWorkbench() }
        let navigation = MainSurfaceNavigationState()
        navigation.destination = destination
        let actions = ActionLedger()
        let promptPreferences = ApplicationPreferences.inMemory()
        #expect(promptPreferences.isEphemeral && promptPreferences.persistenceIdentifier == nil,
                "All prompt and legacy-draft keys must use an ephemeral backing, not a key snapshot of standard defaults.")
        let defaultsName = "uma015-visual-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let matchedEpoch = ProcessInfo.processInfo.environment["UMA015_MATCHED_INPUT_DIR"] == nil
            ? 1_760_000_000.0 : 1_791_547_200.0
        let fixedDate = previewCapturedAt ?? Date(timeIntervalSince1970: matchedEpoch)
        let matched = variant == nil ? try matchedInput(language: language, fixedDate: fixedDate) : nil
        let previewStore = UsageStore.preview(language: language,
            presentationCards: matched?.cards ?? cards,
            accountDailyUsage: accountDailyUsage, previewCapturedAt: fixedDate)
        if let matched {
            previewStore.configureMatchedPreviewSnapshot(matched.snapshot)
            let canonicalEncoder = JSONEncoder()
            canonicalEncoder.outputFormatting = [.sortedKeys]
            let bytes = try canonicalEncoder.encode(matched)
            let record = MatchedDisplayedData(
                inputSHA256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                snapshot: matched.snapshot, cards: matched.cards,
                initialRailExpanded: false,
                sourceHosted: true, foregroundAcceptance: false)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(record).write(
                to: output.appendingPathComponent("\(name).matched-data.json"), options: .atomic)
        }
        if variant == "stale-history" {
            previewStore.configurePreviewHistorySource(freshness: .stale, includeAggregate: true)
        } else if variant == "long" {
            let longTitle = language == .simplifiedChinese
                ? "已隐藏内容的本地线程活动记录，包含较长的辅助描述和多个已确认的时间片段；这里仅展示允许显示的元数据，不显示任务正文、提示词或任何私密项目内容，并检查换行后仍能阅读。"
                : "Long local thread activity description across several recorded intervals; this fixture displays only allowlisted metadata and conceals task bodies, prompts, and private project content while checking two-line readability."
            previewStore.configurePreviewActivitySource(
                freshness: .fresh, isAvailable: true, includeTasks: true, firstTaskTitle: longTitle)
            #expect(previewStore.snapshot.recentTasks.first?.title == longTitle,
                    "The long fixture must populate an existing displayed activity title.")
        } else if variant == "no-history" {
            previewStore.configurePreviewHistorySource(freshness: .fresh, includeAggregate: false)
        } else if variant == "activity-stale" {
            previewStore.configurePreviewActivitySource(freshness: .stale, isAvailable: true, includeTasks: true)
        } else if variant == "activity-unavailable" {
            previewStore.configurePreviewActivitySource(freshness: .stale, isAvailable: false, includeTasks: true)
        } else if variant == "activity-empty" {
            previewStore.configurePreviewActivitySource(freshness: .fresh, isAvailable: true, includeTasks: false)
        }
        if let variant, variant.hasPrefix("activity-") {
            let expected: CodexDashboardActivityState = switch variant {
            case "activity-stale": .stale
            case "activity-unavailable": .unavailable
            default: .empty
            }
            #expect(CodexDashboardPresentation.activityState(snapshot: previewStore.snapshot) == expected)
        }
        if let variant, variant.hasSuffix("-history") {
            let history = CodexDashboardProjection(snapshot: previewStore.snapshot,
                provider: previewStore.productInventory.provider(.codex)).historyAvailability
            switch variant {
            case "aggregate-history":
                guard case .aggregateOnly = history else { Issue.record("Expected an admitted local aggregate"); break }
                #expect(CodexDashboardPresentation.historySourceLine(history, language: language).contains("aggregate available"))
            case "stale-history":
                guard case .staleWithoutDailyBuckets = history else { Issue.record("Expected stale local history"); break }
                #expect(CodexDashboardPresentation.historySourceLine(history, language: language).contains("stale"))
            case "no-history":
                #expect(history == .unavailable)
                #expect(CodexDashboardPresentation.historySourceLine(history, language: language).contains("no local aggregate"))
            default: break
            }
        }
        if variant == "supported-pair" {
            #expect(previewStore.productInventory.agentWorkspaceProviders.count == 2)
        }
        if !accountDailyUsage.isEmpty,
           cards.first?.freshness == .fresh,
           cards.first?.connectionStatus == .connected {
            let slots = CodexDashboardProjection(snapshot: previewStore.snapshot,
                provider: previewStore.productInventory.provider(.codex)).dailySlots()
            let zeroSlot = try #require(slots.first(where: { $0.day == "2026-10-07" }))
            let missingSlot = try #require(slots.first(where: { $0.day == "2026-10-08" }))
            let nonzeroSlot = try #require(slots.first(where: { $0.day == "2026-10-09" }))
            #expect(zeroSlot.tokens == 0)
            #expect(missingSlot.tokens == nil)
            #expect(nonzeroSlot.tokens == 1200)
        }
        let rootContent = MainWindowRootView(
            store: previewStore, navigation: navigation,
            openSettings: { actions.record() }, scanAll: { actions.record() }, refreshAll: { actions.record() },
            connectCodex: { actions.record() }, disconnectCodex: { actions.record() },
            claudeControlState: { .consentRequired }, connectClaude: { actions.record() },
            accuracySyncClaude: { actions.record() }, hesectoriumStore: fixture.store, promptClipboard: actions,
            promptPreferences: promptPreferences,
            referenceDate: fixedDate,
            agentRailDisplayNames: variant == "long" || variant == "rail-overflow"
                ? [.codex: "Codex Developer Workspace With An Extended Provider Label"] : [:],
            initiallyExpandedResetProviderID: variant == "long" || variant == "rail-overflow" ? .codex : nil
        )
        #expect(rootContent.promptPreferences === promptPreferences)
        let root = rootContent.defaultAppStorage(defaults)
        let host = NSHostingView(rootView: root)
        let usesNativeScreenConstraints = ProcessInfo.processInfo.environment["UMA015_NATIVE_HOLD_SECONDS"] != nil
        let window: NSWindow = usesNativeScreenConstraints
            ? NSWindow(contentRect: NSRect(origin: .zero, size: size),
                       styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            : SourceHostedFixtureWindow(contentRect: NSRect(origin: .zero, size: size),
                                        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "UMA visual fixture"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setContentSize(size)
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        settle(host)
        if name == "uma-normal-en-light",
           let hold = Int(ProcessInfo.processInfo.environment["UMA015_NATIVE_HOLD_SECONDS"] ?? ""),
           hold > 0 {
            window.setFrameOrigin(NSPoint(x: 100, y: 150))
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            let identity = NativeSceneWindowIdentity(
                fixture: name, processID: ProcessInfo.processInfo.processIdentifier,
                windowNumber: window.windowNumber, appIsRunning: NSApp.isRunning,
                appIsActive: NSApp.isActive, windowIsKey: window.isKeyWindow,
                outerFrame: Geometry(rect: window.frame, kind: "native-outer-window"))
            try JSONEncoder().encode(identity).write(
                to: output.appendingPathComponent("\(name).window-identity.json"), options: .atomic)
            try await Task.sleep(for: .seconds(min(hold, 90)))
            settle(host)
        }
        if destination == .sectorium {
            for _ in 0..<80 where fixture.store.inventoryState == .loading {
                try await Task.sleep(for: .milliseconds(25))
                settle(host)
            }
            #expect(fixture.store.inventoryState == .available)
        }
        settle(host)
        let preflight = WindowPreflight(
            requestedContent: Geometry(rect: NSRect(origin: .zero, size: size), kind: "requested-content"),
            achievedOuter: Geometry(rect: window.frame, kind: "actual-outer-window"),
            achievedContent: Geometry(rect: window.contentView?.bounds ?? .zero, kind: "actual-content-view"),
            achievedHost: Geometry(rect: host.bounds, kind: "actual-host-view"),
            screenConstraintPolicy: usesNativeScreenConstraints ? "native" : "source-hosted-unconstrained-viewport",
            screens: NSScreen.screens.map { screen in
                ScreenPreflight(frame: Geometry(rect: screen.frame, kind: "screen"),
                                visibleFrame: Geometry(rect: screen.visibleFrame, kind: "visible-screen"),
                                backingScale: screen.backingScaleFactor)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(preflight).write(to: output.appendingPathComponent("\(name).preflight.json"), options: .atomic)
        #expect(host.window === window)
        #expect(abs(host.bounds.width - size.width) <= 1 && abs(host.bounds.height - size.height) <= 1)
        if variant == "supported-pair" {
            let expected = language == .english
                ? "Local API equivalent estimate · 7D"
                : "本地 API 等效估算 · 7天"
            #expect(CodexDashboardPresentation.localEstimateTitle(language: language) == expected,
                    "The populated local money card must visibly identify its estimate in both languages.")
        }
        var geometry: [String: Geometry] = [:]
        for view in [host] + descendants(of: host) {
            let id = view.accessibilityIdentifier()
            if !id.isEmpty, view.bounds.width > 0, view.bounds.height > 0 {
                geometry[id] = Geometry(rect: view.convert(view.bounds, to: host), kind: "native-view")
            }
        }
        collectAccessibilityGeometry(from: host, host: host, window: window, into: &geometry)
        var railScrollEvidence: RailScrollEvidence?
        if destination == .agents, let split = descendants(of: host).compactMap({ $0 as? NSSplitView }).first {
            for (index, pane) in split.arrangedSubviews.enumerated() {
                geometry["uma015.agent.split-pane.\(index)"] = Geometry(rect: pane.convert(pane.bounds, to: host), kind: "native-split-pane")
            }
            let rail = try #require(geometry["uma015.agent.split-pane.0"])
            #expect(rail.width >= 224 && rail.width <= 248,
                    "The native agent rail must stay in the approved narrow range, fixture \(name)")
            if variant == "rail-overflow" {
                // The source still contains forty reset dates per provider;
                // none may create rendered rows or unnecessary rail scrolling.
                #expect(previewStore.productInventory.agentWorkspaceProviders.count == 2)
                let railScroll = try #require(descendants(of: split.arrangedSubviews[0])
                    .compactMap { $0 as? NSScrollView }.first,
                    "The constrained agent rail must expose its own scroll view.")
                let document = try #require(railScroll.documentView)
                let clip = railScroll.contentView
                let maximum = max(0, document.bounds.height - clip.bounds.height)
                #expect(maximum <= 1,
                    "Retained source reset dates must not create rail overflow; document=\(document.bounds), clip=\(clip.bounds).")
                let rightBefore = split.arrangedSubviews[1].frame
                #expect(split.arrangedSubviews[1].frame == rightBefore,
                        "The compact rail must retain the independent right pane.")
                #expect(navigation.selectedAgent == .codex,
                        "The compact rail must retain the selected canonical provider.")
                railScrollEvidence = RailScrollEvidence(
                    supportedProviderCount: previewStore.productInventory.agentWorkspaceProviders.count,
                    paneHeight: rail.height, documentHeight: document.bounds.height,
                    clipHeight: clip.bounds.height, maximumVerticalOffset: maximum,
                    observedScrolledDistance: 0,
                    rightPaneRetained: split.arrangedSubviews[1].frame == rightBefore,
                    selectedProviderID: navigation.selectedAgent.rawValue)
            }
        }
        var required = ["uma.main.navigation", "uma.main.settings"]
        let groupIDs = ["uma015.codex.metric-bounds", "uma015.codex.history-bounds",
                        "uma015.codex.source-bounds", "uma015.codex.activity-bounds"]
        if destination == .agents {
            required += ["uma.main.scan", "uma.main.refresh"] + groupIDs
            let cardIDs = ["uma015.codex.metric-week", "uma015.codex.metric-total", "uma015.codex.metric-local"]
            let cards = try cardIDs.map { id in try #require(geometry[id], "Missing rendered metric card: \(id), \(name)") }
            if ["normal", "wide"].contains(sizeName) {
                let values = try cardIDs.map { id in try #require(geometry["\(id)-value"], "Missing metric value baseline: \(id), \(name)") }
                #expect(values.allSatisfy { abs($0.y - values[0].y) <= 1 },
                        "Metric values must share a baseline at normal and wide widths: \(name)")
                for card in cards {
                    #expect(card.height >= 64 && card.height <= 88,
                            "Metric card must fit the approved 64–88 pt compact target: \(name), height \(card.height)")
                }
                #expect(cards.allSatisfy { abs($0.y - cards[0].y) <= 1 },
                        "Metric card tops must align at normal and wide widths: \(name)")
            }
            for id in groupIDs {
                let frame = try #require(geometry[id], "Missing actual dashboard group bounds: \(id), \(name)")
                #expect(frame.x >= -1 && frame.x + frame.width <= host.bounds.width + 1,
                        "Dashboard group clips horizontally: \(id), \(name)")
            }
        }
        if destination == .threadOS {
            required += ThreadOSPromptRole.allCases.flatMap {
                ["uma.threados.prompt.role.\($0.rawValue).model", "uma.threados.prompt.role.\($0.rawValue).effort"]
            } + ["uma.threados.prompt.generate-copy", "uma.threados.prompt.preview.text"]
        }
        if destination == .sectorium { required += ["uma.sectorium.refresh", "uma.sectorium.settings"] }
        for id in required {
            let frame = try #require(geometry[id], "Missing actual rendered control: \(id), fixture \(name)")
            if !groupIDs.contains(id) {
                #expect(host.bounds.insetBy(dx: -1, dy: -1).contains(frame.rect), "Control leaves content bounds: \(id), fixture \(name)")
            }
        }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 100)
        try png.write(to: output.appendingPathComponent("\(name).png"), options: .atomic)
        #expect(actions.count == 0)
        #expect(fixture.backend.mutations == 0)
        #expect(promptPreferences.isEphemeral && promptPreferences.persistenceIdentifier == nil)
        var groupScroll: [String: ScrollEvidence] = [:]
        if destination == .agents {
            let shouldExerciseScroll = (variant == nil || variant == "long" || variant == "supported-pair")
                && !dark && ["normal", "strict-minimum", "wide"].contains(sizeName)
            for id in groupIDs {
                let anchor = try #require(descendants(of: host).first { $0.accessibilityIdentifier() == id })
                let scroll = try #require(anchor.enclosingScrollView)
                let document = try #require(scroll.documentView)
                let clip = scroll.contentView
                let rect = anchor.convert(anchor.bounds, to: document)
                let original = clip.bounds.origin
                let initialVisible = clip.documentVisibleRect.contains(rect)
                let maximum = max(0, document.bounds.height - clip.bounds.height)
                let target = max(0, min(maximum, rect.midY - clip.bounds.height / 2))
                var didReveal: Bool? = nil
                var observedOffset: CGFloat? = nil
                if shouldExerciseScroll {
                    clip.scroll(to: NSPoint(x: original.x, y: target))
                    scroll.reflectScrolledClipView(clip)
                    settle(host)
                    observedOffset = abs(clip.bounds.origin.y - original.y)
                    didReveal = clip.documentVisibleRect.contains(rect)
                    #expect(didReveal == true, "Entire dashboard group must be reached by scrolling: \(id), \(name)")
                    if variant == "long", id == "uma015.codex.activity-bounds" {
                        let scrolled = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
                            pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                        scrolled.size = host.bounds.size
                        window.effectiveAppearance.performAsCurrentDrawingAppearance {
                            host.cacheDisplay(in: host.bounds, to: scrolled)
                        }
                        let scrolledPNG = try #require(scrolled.representation(using: .png, properties: [:]))
                        try scrolledPNG.write(to: output.appendingPathComponent("\(name)-activity-scroll.png"), options: .atomic)
                    }
                    clip.scroll(to: original)
                    scroll.reflectScrolledClipView(clip)
                    settle(host)
                }
                groupScroll[id] = ScrollEvidence(initialFullyVisible: initialVisible,
                    maximumVerticalOffset: maximum, requiredTargetOffset: abs(target - original.y),
                    observedScrolledDistance: observedOffset, revealedAfterScroll: didReveal)
            }
        }
        let capture = Capture(fixture: name, phase: output.lastPathComponent, sourceHosted: true,
                              installedRuntime: false, foregroundAcceptance: false,
                              preferences: "explicit ApplicationPreferences.inMemory() per scene; prompt and legacy-draft preferences use ephemeral backing",
                              windowFrame: Geometry(rect: window.frame, kind: "outer-window"),
                              content: Geometry(rect: host.bounds, kind: "content-bounds"),
                              pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh,
                              geometry: geometry, groupScroll: groupScroll,
                              railScrollEvidence: railScrollEvidence,
                              storageCommandExecution: "injected runner; no subprocess execution")
        try encoder.encode(capture).write(to: output.appendingPathComponent("\(name).json"), options: .atomic)
        return capture
    }

    private func settle(_ host: NSView) {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.window?.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private func collectAccessibilityGeometry(from node: Any, host: NSView, window: NSWindow,
                                              into geometry: inout [String: Geometry], depth: Int = 0) {
        guard depth < 32 else { return }
        let children: [Any]
        if let view = node as? NSView {
            children = view.accessibilityChildren() ?? []
        } else if let element = node as? NSAccessibilityElement {
            if let id = element.accessibilityIdentifier(), !id.isEmpty {
                let frame = host.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
                if frame.width > 0, frame.height > 0, geometry[id] == nil {
                    geometry[id] = Geometry(rect: frame, kind: "accessibility-element")
                }
            }
            children = element.accessibilityChildren() ?? []
        } else { return }
        for child in children {
            collectAccessibilityGeometry(from: child, host: host, window: window, into: &geometry, depth: depth + 1)
        }
    }

    private struct Geometry: Codable {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
        let kind: String
        init(rect: CGRect, kind: String) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height; self.kind = kind }
        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    private func normalContentGap(requestedOuter: NSSize,
                                  policyVisibleFrame: NSRect?, targetVisibleFrame: NSRect?) -> String? {
        guard let policyVisibleFrame else { return "NO_POLICY_SCREEN" }
        guard let targetVisibleFrame else { return "NO_TARGET_SCREEN" }
        guard policyVisibleFrame.width >= requestedOuter.width,
              policyVisibleFrame.height >= requestedOuter.height else {
            return "POLICY_SCREEN_BELOW_REQUESTED_NORMAL_OUTER"
        }
        guard targetVisibleFrame.width >= requestedOuter.width,
              targetVisibleFrame.height >= requestedOuter.height else {
            return "TARGET_SCREEN_BELOW_REQUESTED_NORMAL_OUTER"
        }
        return nil
    }

    private func requireNativeFixtureBeforeDeadline(_ runState: NativeEntryRunState) throws {
        _ = try #require(!runState.snapshot().watchdogFired,
            "The native fixture must stop after its independent deadline.")
    }

    private func nativeEntrySucceeded(fixtureFinished: Bool, watchdogFired: Bool) -> Bool {
        fixtureFinished && !watchdogFired
    }

    private func writeNativeEntryHostPhase(_ phase: String, to output: URL) throws {
        let record = ["phase": phase, "utc": ISO8601DateFormatter().string(from: Date()),
                      "monotonicUptime": String(ProcessInfo.processInfo.systemUptime),
                      "appIsRunning": String(NSApp.isRunning)]
        try JSONEncoder().encode(record).write(
            to: output.appendingPathComponent("native-entry-host-\(phase).json"), options: .atomic)
    }

    private func stopNativeEntryLoop() {
        NSApp.stop(nil)
        // AppKit documents that stop from a timer/run-loop callback alone is
        // insufficient; enqueue an application event to release its event wait.
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: true)
        }
    }

    private struct NativeEntryHostLifecycle: Codable {
        let appWasRunningAtEntry: Bool
        let appRunningAfterFixture: Bool
        let fixtureFinished: Bool
        let watchdogFired: Bool
        let deadlineWriteError: String?
        let fixtureError: String?
    }

    private func rejectAlreadyRunningNativeEntry(_ appWasRunning: Bool, output: URL) throws -> Bool {
        guard appWasRunning else { return false }
        let refusal = NativeEntryHostLifecycle(
            appWasRunningAtEntry: true, appRunningAfterFixture: true,
            fixtureFinished: false, watchdogFired: false,
            deadlineWriteError: nil,
            fixtureError: "Already-running AppKit host rejected before awaiting a fixture completion.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(refusal).write(
            to: output.appendingPathComponent("native-entry-host-lifecycle.json"), options: .atomic)
        return true
    }

    private func currentNativeHostIdentity() -> NativeHostIdentity {
        let running = NSRunningApplication.current
        return NativeHostIdentity(
            processID: ProcessInfo.processInfo.processIdentifier,
            processName: ProcessInfo.processInfo.processName,
            bundleURL: Bundle.main.bundleURL.path,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            bundlePackageType: Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String,
            executableURL: Bundle.main.executableURL?.path,
            runningProcessID: running.processIdentifier,
            runningBundleURL: running.bundleURL?.path,
            runningExecutableURL: running.executableURL?.path,
            runningBundleIdentifier: running.bundleIdentifier,
            runningActivationPolicy: running.activationPolicy.rawValue,
            runningIsActive: running.isActive,
            runningIsFinishedLaunching: running.isFinishedLaunching)
    }

    private func nativeAppHostIdentityMatches(
        _ identity: NativeHostIdentity, expectedBundle: URL
    ) -> Bool {
        let bundle = expectedBundle.standardizedFileURL.resolvingSymlinksInPath()
        let executable = bundle.appendingPathComponent("Contents/MacOS/swiftpm-testing-helper").path
        let identifier = "com.tosuma.uma015.native-test-host"
        return identity.processID > 0
            && identity.processName == "swiftpm-testing-helper"
            && identity.bundleURL == bundle.path
            && identity.bundleIdentifier == identifier
            && identity.bundlePackageType == "APPL"
            && identity.executableURL == executable
            && identity.runningProcessID == identity.processID
            && identity.runningBundleURL == bundle.path
            && identity.runningExecutableURL == executable
            && identity.runningBundleIdentifier == identifier
            && identity.runningActivationPolicy == NSApplication.ActivationPolicy.regular.rawValue
    }

    private func prepareNativeTestHost(output: URL) throws {
        let expectedPath = try #require(ProcessInfo.processInfo.environment["UMA015_NATIVE_HOST_BUNDLE_PATH"],
            "The foreground test requires an explicit project-owned native app host bundle.")
        let expectedBundle = URL(fileURLWithPath: expectedPath, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let actual = currentNativeHostIdentity()
        let matched = nativeAppHostIdentityMatches(actual, expectedBundle: expectedBundle)
        let record = NativeHostReadiness(
            expectedBundlePath: expectedBundle.path,
            expectedExecutablePath: expectedBundle.appendingPathComponent(
                "Contents/MacOS/swiftpm-testing-helper").path,
            actual: actual, exactIdentityMatched: matched)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(
            to: output.appendingPathComponent("native-entry-host-readiness.json"), options: .atomic)
        _ = try #require(matched,
            "The isolated native app host identity is not exact; inspect native-entry-host-readiness.json.")
    }

    private struct NativeHostReadiness: Codable {
        let expectedBundlePath: String
        let expectedExecutablePath: String
        let actual: NativeHostIdentity
        let exactIdentityMatched: Bool
    }

    private struct NativeHostIdentity: Codable {
        let processID: Int32
        let processName: String
        let bundleURL: String
        let bundleIdentifier: String?
        let bundlePackageType: String?
        let executableURL: String?
        let runningProcessID: Int32
        let runningBundleURL: String?
        let runningExecutableURL: String?
        let runningBundleIdentifier: String?
        let runningActivationPolicy: Int
        let runningIsActive: Bool
        let runningIsFinishedLaunching: Bool
    }

    private struct NativeEntryScreen: Codable {
        let order: Int
        let frame: Geometry
        let visibleFrame: Geometry
        let backingScale: CGFloat
    }

    private struct NativeEntryPreflight: Codable {
        let stage: String
        let processID: Int32
        let windowNumber: Int?
        let requestedNormalContent: Geometry
        let requestedNormalOuter: Geometry?
        let normalContentSupported: Bool?
        let normalContentGap: String?
        let expectedInitialOuter: Geometry?
        let actualOuter: Geometry?
        let actualContent: Geometry?
        let actualContentBounds: Geometry?
        let benchmarkExpectedOuter: Geometry?
        let benchmarkSupported: Bool?
        let benchmarkGap: String?
        let screens: [NativeEntryScreen]
        let windowScreenOrder: Int?
        let originalActivationPolicy: Int
        let currentActivationPolicy: Int
        let policySetterResult: Bool?
        let appIsRunning: Bool
        let appIsHidden: Bool
        let appIsActive: Bool
        let windowIsVisible: Bool?
        let windowCanBecomeKey: Bool?
        let windowIsKey: Bool?
        let windowIsMain: Bool?
        let keyWindowIsTarget: Bool?
        let mainWindowIsTarget: Bool?
        let firstResponderType: String?
        let firstResponderIdentity: String?
        let firstResponderAccessibilityIdentifier: String?
    }

    private func writeNativeEntryPreflight(
        _ stage: String, to output: URL, window: NSWindow?,
        originalActivationPolicy: NSApplication.ActivationPolicy,
        policySetterResult: Bool?, benchmarkExpected: NSRect? = nil,
        benchmarkSupported: Bool? = nil, benchmarkGap: String? = nil,
        normalContentGap: String? = nil
    ) throws {
        let screens = NSScreen.screens
        let expectedOuter = window.map { nativeWindow in
            MainWindowFramePolicy.initialFrame(
                visibleFrames: screens.map(\.visibleFrame),
                outerSize: nativeWindow.frameRect(forContentRect: NSRect(
                    origin: .zero, size: MainWindowFramePolicy.normalContentSize)).size)
        }
        let responder = window?.firstResponder
        let record = NativeEntryPreflight(
            stage: stage,
            processID: ProcessInfo.processInfo.processIdentifier,
            windowNumber: window?.windowNumber,
            requestedNormalContent: Geometry(rect: NSRect(origin: .zero,
                size: MainWindowFramePolicy.normalContentSize), kind: "requested-normal-content"),
            requestedNormalOuter: window.map { nativeWindow in
                Geometry(rect: NSRect(origin: .zero,
                    size: nativeWindow.frameRect(forContentRect: NSRect(origin: .zero,
                        size: MainWindowFramePolicy.normalContentSize)).size),
                    kind: "requested-unclamped-normal-outer")
            },
            normalContentSupported: stage == "normal-content-gate" ? normalContentGap == nil : nil,
            normalContentGap: normalContentGap,
            expectedInitialOuter: expectedOuter.map { Geometry(rect: $0, kind: "expected-policy-outer") },
            actualOuter: window.map { Geometry(rect: $0.frame, kind: "actual-outer") },
            actualContent: window.map { Geometry(rect: $0.contentRect(forFrameRect: $0.frame), kind: "actual-content-rect") },
            actualContentBounds: window?.contentView.map { Geometry(rect: $0.bounds, kind: "actual-content-bounds") },
            benchmarkExpectedOuter: benchmarkExpected.map { Geometry(rect: $0, kind: "requested-benchmark-outer") },
            benchmarkSupported: benchmarkSupported,
            benchmarkGap: benchmarkGap,
            screens: screens.enumerated().map { order, screen in
                NativeEntryScreen(order: order,
                    frame: Geometry(rect: screen.frame, kind: "screen"),
                    visibleFrame: Geometry(rect: screen.visibleFrame, kind: "visible-screen"),
                    backingScale: screen.backingScaleFactor)
            },
            windowScreenOrder: window?.screen.flatMap { selected in
                screens.firstIndex(where: { $0 === selected })
            },
            originalActivationPolicy: originalActivationPolicy.rawValue,
            currentActivationPolicy: NSApp.activationPolicy().rawValue,
            policySetterResult: policySetterResult,
            appIsRunning: NSApp.isRunning,
            appIsHidden: NSApp.isHidden,
            appIsActive: NSApp.isActive,
            windowIsVisible: window?.isVisible,
            windowCanBecomeKey: window?.canBecomeKey,
            windowIsKey: window?.isKeyWindow,
            windowIsMain: window?.isMainWindow,
            keyWindowIsTarget: window.map { NSApp.keyWindow === $0 },
            mainWindowIsTarget: window.map { NSApp.mainWindow === $0 },
            firstResponderType: responder.map { String(reflecting: type(of: $0)) },
            firstResponderIdentity: responder.map { String(describing: ObjectIdentifier($0)) },
            firstResponderAccessibilityIdentifier: (responder as? NSView)?.accessibilityIdentifier()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: output.appendingPathComponent("native-entry-\(stage).json"),
            options: .atomic)
    }

    private struct ScreenPreflight: Codable {
        let frame: Geometry
        let visibleFrame: Geometry
        let backingScale: CGFloat
    }

    private struct WindowPreflight: Codable {
        let requestedContent: Geometry
        let achievedOuter: Geometry
        let achievedContent: Geometry
        let achievedHost: Geometry
        let screenConstraintPolicy: String
        let screens: [ScreenPreflight]
    }

    @MainActor private final class SourceHostedFixtureWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            frameRect
        }
    }

    private struct ScrollEvidence: Codable {
        let initialFullyVisible: Bool
        let maximumVerticalOffset: CGFloat
        let requiredTargetOffset: CGFloat
        let observedScrolledDistance: CGFloat?
        let revealedAfterScroll: Bool?
    }

    private struct RailScrollEvidence: Codable {
        let supportedProviderCount: Int
        let paneHeight: CGFloat
        let documentHeight: CGFloat
        let clipHeight: CGFloat
        let maximumVerticalOffset: CGFloat
        let observedScrolledDistance: CGFloat
        let rightPaneRetained: Bool
        let selectedProviderID: String
    }

    private struct NativeSceneWindowIdentity: Codable {
        let fixture: String
        let processID: Int32
        let windowNumber: Int
        let appIsRunning: Bool
        let appIsActive: Bool
        let windowIsKey: Bool
        let outerFrame: Geometry
    }

    private struct Capture: Codable {
        let fixture: String, phase: String
        let sourceHosted: Bool, installedRuntime: Bool, foregroundAcceptance: Bool
        let preferences: String
        let windowFrame: Geometry, content: Geometry
        let pixelsWide: Int, pixelsHigh: Int
        let geometry: [String: Geometry]
        let groupScroll: [String: ScrollEvidence]
        let railScrollEvidence: RailScrollEvidence?
        let storageCommandExecution: String
    }

    private final class ActionLedger: ThreadOSSettingsClipboard {
        private(set) var count = 0
        func record() { count += 1 }
        func write(_ string: String) -> Bool { record(); return false }
    }

    @MainActor private struct StorageFixture {
        let store: HESectoriumStore
        let backend: FixtureBackend
        let runner: FixtureRunner
        let observer: FixtureObserver
        init(root: URL) throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let paths = HESectoriumPaths(root: root.appendingPathComponent("support", isDirectory: true))
            let device = SectoriumPhysicalDevice(id: "F30A72EE-5BDA-4DEB-8720-508607929301", bsdName: "disk81",
                name: "Visual fixture external drive", isExternal: true, identityVerified: true,
                wholeDeviceBytes: 512 * 1024 * 1024 * 1024, mountedVolumePaths: [], volumeUUIDs: [],
                readBytes: nil, writtenBytes: nil, isVirtual: false)
            backend = FixtureBackend()
            runner = FixtureRunner(device: device)
            observer = FixtureObserver(device: device)
            let service = HESectoriumService(paths: paths, backend: backend, store: FixtureStateStore(),
                operationLock: FixtureLock(), installer: HESectoriumInstaller(paths: paths, home: root),
                runner: runner, identityPolicy: .expected,
                agentStatusProvider: UnknownAgentStatusProvider(), sectoriumDeviceObserver: observer,
                sectoriumDeviceIOSampler: FixtureIOSampler())
            store = HESectoriumStore(service: service, sampleIntervalNanoseconds: 60_000_000_000)
        }
    }

    private final class FixtureStateStore: DurableStateStore {
        private var state = StoragePersistentState(ejectIntent: false)
        func load() throws -> StoragePersistentState { state }
        func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
            guard state.revision == expectedRevision else { return false }
            state = newState
            return true
        }
    }
    private final class FixtureLock: OperationLock { func acquire() -> Bool { true }; func release() {} }
    private final class FixtureBackend: StorageBackend {
        private(set) var mutations = 0
        func observeOuter() -> VolumeIdentity? { nil }
        func observe() -> StorageObservation? { nil }
        func attachImage() -> CommandOutcome { mutations += 1; return .init(exitCode: 97, detail: "visual fixture forbids storage") }
        func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { .incomplete(reason: "visual fixture has no live occupancy") }
        func perform(_ step: EjectStep) -> CommandOutcome { mutations += 1; return .init(exitCode: 97, detail: "visual fixture forbids storage") }
        func finalOuterState() -> FinalOuterState { .unknown("visual fixture forbids storage") }
    }
    private final class FixtureRunner: HESectoriumCommandRunning {
        let device: SectoriumPhysicalDevice
        private(set) var mutationAttempts = 0
        init(device: SectoriumPhysicalDevice) { self.device = device }
        func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
            if executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", "/dev/\(device.bsdName)"],
               let data = try? PropertyListSerialization.data(fromPropertyList: ["DeviceIdentifier": device.bsdName, "MediaUUID": device.id], format: .xml, options: 0) {
                return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
            }
            mutationAttempts += 1
            return .init(exitCode: 97, detail: "visual fixture forbids command execution")
        }
    }
    private final class FixtureObserver: SectoriumDeviceObserving, @unchecked Sendable {
        let device: SectoriumPhysicalDevice
        private let lock = NSLock()
        private var count = 0
        init(device: SectoriumPhysicalDevice) { self.device = device }
        var observationCount: Int { lock.lock(); defer { lock.unlock() }; return count }
        func observeDevices() throws -> [SectoriumPhysicalDevice] {
            lock.lock(); count += 1; lock.unlock()
            return [device]
        }
    }
    private final class FixtureIOSampler: SectoriumDeviceIOCounterSampling, @unchecked Sendable {
        func counters(forWholeBSDName bsdName: String, expectedMediaID: UUID) -> SectoriumDeviceIOCounters? {
            .init(readBytes: 1000, writtenBytes: 2000)
        }
    }
}
