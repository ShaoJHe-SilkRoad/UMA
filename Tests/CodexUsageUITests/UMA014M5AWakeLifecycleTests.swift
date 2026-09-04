import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("UMA014 M5-A application wake lifecycle")
@MainActor
struct UMA014M5AWakeLifecycleTests {
    @Test(.timeLimit(.minutes(1)))
    func delegateOwnsOneObserverThroughRepeatedLaunchAndRelaunch() async throws {
        let fixture = try WakeLifecycleFixture()
        defer { fixture.cleanUp() }
        await fixture.store.searchForAgents()
        let center = NotificationCenter()
        var constructions = 0
        var replies = 0
        let delegate = AppDelegate(
            runtimeFactory: { _ in constructions += 1; return fixture.runtime },
            wakeNotificationCenter: center,
            terminationReply: { _ in replies += 1 }
        )
        let launch = Notification(name: NSApplication.didFinishLaunchingNotification)
        delegate.applicationDidFinishLaunching(launch)
        delegate.applicationDidFinishLaunching(launch)
        await delegate.launchTask?.value
        let observer = try #require(delegate.wakeObserver)
        #expect(observer.isActive)
        #expect(constructions == 1)
        let starts = await fixture.connector.startCount
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await observer.waitForPendingWake()
        #expect(await fixture.connector.wakeCount == 1)
        #expect(await fixture.connector.startCount == starts)
        NotificationCenter().post(name: NSWorkspace.didWakeNotification, object: nil)
        await observer.waitForPendingWake()
        #expect(await fixture.connector.wakeCount == 1)

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        await delegate.terminationTask?.value
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(!observer.isActive)
        #expect(replies == 1)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await observer.waitForPendingWake()
        #expect(await fixture.connector.wakeCount == 1)

        let next = try WakeLifecycleFixture()
        defer { next.cleanUp() }
        await next.store.searchForAgents()
        let relaunched = AppDelegate(
            runtimeFactory: { _ in next.runtime },
            wakeNotificationCenter: center,
            terminationReply: { _ in }
        )
        relaunched.applicationDidFinishLaunching(launch)
        await relaunched.launchTask?.value
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await relaunched.wakeObserver?.waitForPendingWake()
        #expect(await next.connector.wakeCount == 1)
        #expect(await fixture.connector.wakeCount == 1)
        #expect(relaunched.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        await relaunched.terminationTask?.value
        relaunched.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    @Test(.timeLimit(.minutes(1)))
    func terminationBeforeCompositionPreventsLateRuntimeAndObserver() async {
        var constructions = 0
        let delegate = AppDelegate(
            runtimeFactory: { _ in
                constructions += 1
                throw WakeFixtureError.unexpectedConstruction
            },
            wakeNotificationCenter: NotificationCenter(),
            terminationReply: { _ in }
        )
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        await delegate.launchTask?.value
        #expect(constructions == 0)
        #expect(delegate.wakeObserver == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidationRejectsAlreadyQueuedWake() async throws {
        let fixture = try WakeLifecycleFixture()
        defer { fixture.cleanUp() }
        await fixture.store.searchForAgents()
        let center = NotificationCenter()
        let observer = CodexWakeRefreshObserver(store: fixture.store, notificationCenter: center)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        observer.invalidate()
        observer.invalidate()
        await observer.waitForPendingWake()
        #expect(!observer.isActive)
        #expect(await fixture.connector.wakeCount == 0)
        await fixture.runtime.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func wakeBurstCoalescesAndLaterWakeStillRefreshes() async throws {
        let fixture = try WakeLifecycleFixture()
        defer { fixture.cleanUp() }
        await fixture.store.searchForAgents()
        let center = NotificationCenter()
        let observer = CodexWakeRefreshObserver(store: fixture.store, notificationCenter: center)
        await fixture.connector.holdNextWake()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await fixture.connector.waitForWakeStart()
        for _ in 0..<20 { center.post(name: NSWorkspace.didWakeNotification, object: nil) }
        #expect(await fixture.connector.wakeCount == 1)
        await fixture.connector.releaseWake()
        await observer.waitForPendingWake()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await observer.waitForPendingWake()
        #expect(await fixture.connector.wakeCount == 2)
        #expect(await fixture.connector.maximumActiveRefreshes == 1)
        observer.invalidate()
        await fixture.runtime.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func shutdownCancelsActiveWakeBeforeStoppingConnector() async throws {
        let fixture = try WakeLifecycleFixture()
        defer { fixture.cleanUp() }
        await fixture.store.searchForAgents()
        let center = NotificationCenter()
        let delegate = AppDelegate(
            runtimeFactory: { _ in fixture.runtime },
            wakeNotificationCenter: center,
            terminationReply: { _ in }
        )
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate.launchTask?.value
        await fixture.connector.holdNextWake()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await fixture.connector.waitForWakeStart()
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await delegate.terminationTask?.value
        #expect(await fixture.connector.cancelledWakeCount == 1)
        #expect(await fixture.connector.activeRefreshesAtStop == 0)
        #expect(await fixture.connector.wakeCount == 1)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    @Test(.timeLimit(.minutes(1)))
    func terminationDrainsOwnedStartupBeforeConnectorStop() async throws {
        let startup = WakeStartupGate()
        let startupTask = Task { await startup.run() }
        await startup.waitUntilStarted()
        let fixture = try WakeLifecycleFixture(startupTask: startupTask)
        defer { fixture.cleanUp() }
        await fixture.store.searchForAgents()
        let delegate = AppDelegate(
            runtimeFactory: { _ in fixture.runtime },
            wakeNotificationCenter: NotificationCenter(),
            terminationReply: { _ in }
        )
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate.launchTask?.value
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        await startup.waitUntilCancelled()
        #expect(await fixture.connector.activeRefreshesAtStop == -1)
        await startup.release()
        await delegate.terminationTask?.value
        #expect(await startup.finished)
        #expect(await fixture.connector.activeRefreshesAtStop == 0)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    @Test(.timeLimit(.minutes(1)))
    func wakeRespectsPreferenceAndExplicitWindowPause() async throws {
        let fixture = try WakeLifecycleFixture()
        defer { fixture.cleanUp() }
        let center = NotificationCenter()
        let observer = CodexWakeRefreshObserver(store: fixture.store, notificationCenter: center)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await observer.waitForPendingWake()
        #expect(await fixture.connector.wakeCount == 0)
        await fixture.store.searchForAgents()
        fixture.preferences.set(false, for: UMAApplicationPreferenceKeys.refreshOnWake)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await observer.waitForPendingWake()
        #expect(await fixture.connector.wakeCount == 0)
        fixture.preferences.set(true, for: UMAApplicationPreferenceKeys.refreshOnWake)
        fixture.preferences.set(false, for: UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose)
        await fixture.store.suspendMonitoringForWindowClosure()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await observer.waitForPendingWake()
        #expect(await fixture.connector.wakeCount == 0)
        await fixture.store.resumeMonitoringForWindowPresentation()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await observer.waitForPendingWake()
        #expect(await fixture.connector.wakeCount == 1)
        observer.invalidate()
        await fixture.runtime.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func admittedClaudeWakeNeverInvokesAccuracySync() async throws {
        let browser = BrowserConnectorFixture(consent: true)
        let claude = browser.connector(sleep: { _ in throw CancellationError() })
        // Explicit synthetic anchor setup uses only a recording fixture bridge.
        await claude.accuracySync()
        await browser.bridge.send(browserEnvelope(five: 20, seven: 40))
        let fixture = try WakeLifecycleFixture(additionalConnectors: [claude])
        defer { fixture.cleanUp() }
        await fixture.store.searchForAgents()
        #expect(fixture.store.providerSnapshots.contains { $0.id == claude.id })
        let before = await claude.diagnostics()
        let opens = await browser.bridge.openCount
        let requests = await browser.bridge.automaticRequests.count
        let verifications = await browser.bridge.verificationCount
        let center = NotificationCenter()
        let observer = CodexWakeRefreshObserver(store: fixture.store, notificationCenter: center)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        await observer.waitForPendingWake()
        let after = await claude.diagnostics()
        #expect(after.automaticDispatchCount == before.automaticDispatchCount)
        #expect(await browser.bridge.openCount == opens)
        #expect(await browser.bridge.automaticRequests.count == requests)
        #expect(await browser.bridge.verificationCount == verifications)
        #expect(!after.schedulerActive)
        observer.invalidate()
        await fixture.runtime.shutdown()
    }
}

private enum WakeFixtureError: Error { case unexpectedConstruction }

@MainActor
private struct WakeLifecycleFixture {
    let suiteName: String
    let defaults: UserDefaults
    let preferences: ApplicationPreferences
    let connector: WakeFixtureConnector
    let store: UsageStore
    let runtime: UsageMonitorRuntime

    init(
        additionalConnectors: [any AgentUsageConnector] = [],
        startupTask: Task<Void, Never>? = nil
    ) throws {
        suiteName = "uma014-m5a-wake-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        preferences = .inMemory(seed: [
            UMAApplicationPreferenceKeys.automaticBackgroundRefresh.name: false,
            UMAApplicationPreferenceKeys.refreshOnWake.name: true,
        ])
        connector = try WakeFixtureConnector()
        let registry = try AgentConnectorRegistry(connectors: [connector] + additionalConnectors)
        let settings = AgentSettingsCoordinator(store: AgentPreferenceStore(preferences: preferences))
        store = UsageStore(
            autoRefresh: false, previewOnly: false, language: .english,
            registry: registry, primaryConnectorID: nil, consentDefaults: nil,
            preferences: preferences, agentSettings: settings,
            backgroundRefreshSleeper: { _ in throw CancellationError() }
        )
        let settingsConnector = BrowserConnectorFixture(consent: false).connector()
        runtime = UsageMonitorRuntime(
            preferences: preferences,
            store: store,
            claudeSettings: ClaudeBrowserSettingsModel(
                connector: settingsConnector,
                consentStore: ClaudeBrowserConsentStore(defaults: defaults)
            ),
            startupTask: startupTask
        )
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suiteName) }
}

private actor WakeFixtureConnector: AgentUsageConnector {
    nonisolated let id = AgentConnectorID(rawValue: "m5a.wake.fixture")!
    nonisolated let descriptor: AgentConnectorDescriptor
    private let snapshot: AgentUsageSnapshot
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var holdWake = false
    private var wakeRelease: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var startCount = 0
    private(set) var wakeCount = 0
    private(set) var cancelledWakeCount = 0
    private var activeRefreshes = 0
    private(set) var maximumActiveRefreshes = 0
    private(set) var activeRefreshesAtStop = -1

    init() throws {
        descriptor = try #require(AgentConnectorDescriptor(
            id: id, providerName: "Wake fixture", officialSource: "isolated fixture",
            sourceTier: .officialStructuredHook, sourceVersion: "m5a",
            supportedScopes: [.account], capabilities: [.connect, .refresh, .disconnect],
            configurationRequirements: [.userAuthorization], privacyAllowlist: ["aggregate percentage"],
            supportsRestore: false, supportsUninstall: false, unsupportedFields: ["raw payload"],
            localSourceClass: .admittedStructuredLocal, usageReadContract: .currentStructuredLocalRead
        ))
        let date = Date(timeIntervalSince1970: 1_788_134_400)
        snapshot = AgentUsageSnapshot(
            id: id, providerName: "Wake fixture", state: .ready, capturedAt: date,
            lastSuccessfulAt: date, freshness: .fresh,
            channels: [AgentUsageChannel(
                id: .account, sourceTier: .officialStructuredHook, sourceVersion: "m5a",
                scopes: [.account], provenance: .providerReported, freshness: .fresh,
                capturedAt: date, coverageNote: nil,
                rateLimitWindows: [AgentRateLimitWindow(
                    id: "seven-day", kind: .sevenDay, usedPercent: 40, isUnlimited: false, resetsAt: nil
                )], accountMetrics: nil, localActivityMetrics: nil, safeFailure: nil
            )], capabilities: [.connect, .refresh, .disconnect], safeFailure: nil
        )
    }

    func probe() async -> AgentConnectorProbe { .init(state: .ready, safeFailure: nil) }
    func start() async { startCount += 1; continuation?.yield(snapshot) }
    func refresh() async { await refresh(trigger: .manual) }
    func refresh(trigger: CodexRefreshTrigger) async {
        guard trigger == .wake else { return }
        wakeCount += 1
        activeRefreshes += 1
        maximumActiveRefreshes = max(maximumActiveRefreshes, activeRefreshes)
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if holdWake {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled { continuation.resume() }
                    else { wakeRelease = continuation }
                }
            } onCancel: {
                Task { await self.releaseWake() }
            }
        }
        if Task.isCancelled { cancelledWakeCount += 1 }
        activeRefreshes -= 1
        continuation?.yield(snapshot)
    }
    func holdNextWake() { holdWake = true }
    func waitForWakeStart() async {
        if wakeCount > 0 { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func releaseWake() {
        holdWake = false
        wakeRelease?.resume()
        wakeRelease = nil
    }
    func perform(_ command: AgentConnectorCommand) async { if command == .disconnect { await stop() } }
    func stop() async {
        activeRefreshesAtStop = activeRefreshes
        continuation?.finish()
        continuation = nil
    }
    func currentSnapshot() async -> AgentUsageSnapshot { snapshot }
    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(snapshot)
        }
    }
}

private actor WakeStartupGate {
    private var started = false
    private var cancelled = false
    private(set) var finished = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var cancellationWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func run() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                releaseWaiter = continuation
                started = true
                startWaiter?.resume()
                startWaiter = nil
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
        finished = true
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func waitUntilCancelled() async {
        if cancelled { return }
        await withCheckedContinuation { cancellationWaiter = $0 }
    }
    private func recordCancellation() {
        cancelled = true
        cancellationWaiter?.resume()
        cancellationWaiter = nil
    }
    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
