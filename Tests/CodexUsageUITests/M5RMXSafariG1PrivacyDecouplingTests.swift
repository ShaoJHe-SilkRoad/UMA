import Foundation
import Testing
import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
@testable import CodexUsageUI

@Suite("M5RMX Local Smart and one-shot Accuracy privacy separation")
struct M5RMXSafariG1PrivacyDecouplingTests {
    @Test
    func productionCallGraphConditionallyProjectsCodeActivityButAccuracyNeverInvokesIt() throws {
        let connector = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeCodeUsageConnector.swift"
        )
        let runtime = try source(
            "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
        )

        #expect(runtime.contains("ClaudeCodeUsageConnector.production("))
        #expect(runtime.contains("claudeSurfaceDetector.statusLineCapableSurfaceInstalled"))
        #expect(runtime.contains("? ClaudeLocalActivityReader()"))
        #expect(runtime.contains(": nil"))
        #expect(runtime.contains("localActivityReader: claudeLocalActivityReader"))
        #expect(connector.contains("ClaudeSanitizedLocalActivity.project("))
        #expect(connector.contains("localActivityReader.read(now: now())"))
        #expect(connector.contains("private func startBrowserListenerIfNeeded() async"))

        for method in ["checkCompanion", "accuracySync", "openUsagePage", "repairCompanion"] {
            let body = try methodBody(named: method, in: connector)
            #expect(body.contains("startBrowserListenerIfNeeded"))
            #expect(!body.contains("refreshLocalInputs"))
            #expect(!body.contains("start()"))
        }
        let connect = try methodBody(named: "connect", in: connector)
        #expect(connect.contains("await start()"))
        #expect(connect.contains("await accuracySync()"))
        #expect(!connect.contains("startBrowserListenerIfNeeded"))

        let descriptor = ClaudeCodeUsageConnector.production().descriptor
        #expect(descriptor.supportedScopes == [.account, .session])
        #expect(descriptor.capabilities.contains(.localActivity))
        #expect(!descriptor.capabilities.contains(.automaticRefresh))
        #expect(!descriptor.privacyAllowlist.contains("localActivityTokenCounts"))
        #expect(!descriptor.privacyAllowlist.contains("localActivityModelIdentifier"))
        #expect(!descriptor.privacyAllowlist.contains("localActivityTimestamp"))
        #expect(descriptor.unsupportedFields.contains("prompt"))
        #expect(descriptor.unsupportedFields.contains("transcript"))
        #expect(descriptor.unsupportedFields.contains("project"))
    }

    @Test
    func coldAccuracySyncAndCallbackNeverReadProjectSessions() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let counter = LockedLocalReadCounter()
        let connector = smartConnector(
            fixture,
            localReader: CountingSmartLocalReader(counter: counter)
        )

        await connector.accuracySync()
        #expect(await fixture.bridge.automaticRequests.count == 1)
        #expect(counter.value == 0)
        #expect(counter.observerCreationCount == 0)
        let diagnostics = await deliverAndAwaitProcessing(
            browserEnvelope(five: 25, seven: 45),
            through: fixture.bridge,
            to: connector
        )
        #expect(diagnostics.acceptedObservationCount == 1)
        #expect(diagnostics.localActivityReaderInvocationCount == 0)
        #expect(diagnostics.claudeProjectsAccessCount == 0)
        #expect(counter.value == 0)
        #expect(counter.observerCreationCount == 0)
        #expect(!diagnostics.automaticRefreshInFlight)
    }

    @Test
    func coldBrowserLifecycleNeverStartsLocalSmart() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let counter = LockedLocalReadCounter()
        let connector = smartConnector(
            fixture,
            localReader: CountingSmartLocalReader(counter: counter)
        )

        await connector.checkCompanion()
        await connector.openUsagePage()
        await connector.repairCompanion()
        await connector.perform(.reconnect)

        #expect(await fixture.bridge.startCount == 1)
        #expect(await fixture.bridge.verificationCount == 1)
        #expect(await fixture.bridge.openCount == 1)
        #expect(await fixture.bridge.repairCount == 1)
        #expect(counter.value == 0)
        #expect(counter.observerCreationCount == 0)
        await expectProjectPrivacyZeros(connector)
    }

    @Test
    func browserFailureRecoveryRestartsOnlyTheSanitizedListener() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let counter = LockedLocalReadCounter()
        let connector = smartConnector(
            fixture,
            localReader: CountingSmartLocalReader(counter: counter)
        )

        await connector.accuracySync()
        await fixture.bridge.reject(.socketUnavailable)
        await connector.checkCompanion()
        #expect(await fixture.bridge.startCount == 2)
        #expect(counter.value == 0)
        #expect(counter.observerCreationCount == 0)
        await expectProjectPrivacyZeros(connector)

        await connector.accuracySync()
        let diagnostics = await deliverAndAwaitProcessing(
            browserEnvelope(five: 20, seven: 40),
            through: fixture.bridge,
            to: connector
        )
        #expect(diagnostics.acceptedObservationCount == 1)
        #expect(counter.value == 0)
        #expect(counter.observerCreationCount == 0)
        await expectProjectPrivacyZeros(connector)
    }

    @Test
    func explicitLocalSmartStartStillReadsItsBoundedSource() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let counter = LockedLocalReadCounter()
        let connector = smartConnector(
            fixture,
            localReader: CountingSmartLocalReader(counter: counter)
        )

        await connector.start()
        #expect(counter.value == 1)
        #expect(counter.observerCreationCount == 1)
        #expect((await connector.diagnostics()).localActivityReaderInvocationCount == 1)
        #expect((await connector.diagnostics()).claudeProjectsAccessCount == 1)

        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 30, seven: 50))
        #expect(counter.value == 1)
    }

    @Test
    func localRefreshTriggersNoBrowserSchedulerOrOwnedTab() async {
        let fixture = BrowserConnectorFixture(
            consent: true,
            autoRefresh: true,
            allowSafariLaunch: true
        )
        let connector = smartConnector(fixture, localReader: UnavailableSmartLocalReader())
        await connector.start()
        await connector.refresh(trigger: .timer)
        await connector.refresh(trigger: .wake)
        await connector.syncNow()
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.localActivityReaderInvocationCount >= 4)
        #expect(diagnostics.claudeProjectsAccessCount
            == diagnostics.localActivityReaderInvocationCount)
        #expect(diagnostics.scheduledCycleCount == 0)
        #expect(!diagnostics.schedulerActive)
        #expect(await fixture.bridge.automaticRequests.isEmpty)
        #expect(await fixture.bridge.closedRequestIDs.isEmpty)
    }

    @Test
    func disconnectClearsOnlyOwnedSmartAndAccuracyState() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = smartConnector(fixture, localReader: UnavailableSmartLocalReader())
        await connector.start()
        await connector.accuracySync()
        let requestID = await fixture.bridge.automaticRequests.first?.requestID
        await connector.disconnect()
        #expect(await fixture.cache.clearCount == 1)
        #expect(!(await fixture.consent.get()))
        #expect(!connector.descriptor.capabilities.contains(.sanitizedLastValidRestore))
        #expect((await connector.diagnostics()).scheduledCycleCount == 0)
        let expectedClosed = requestID.map { [$0] } ?? []
        #expect(await fixture.bridge.closedRequestIDs == expectedClosed)
    }

    private func smartConnector(
        _ fixture: BrowserConnectorFixture,
        localReader: any ClaudeLocalActivityReading
    ) -> ClaudeCodeUsageConnector {
        let bridge = fixture.bridge
        let consent = fixture.consent
        let cache = fixture.cache
        return ClaudeCodeUsageConnector(
            integration: ClaudeBrowserProductionIntegration(
                startListening: { handler in await bridge.start(handler) },
                stopListening: { await bridge.stop() },
                checkHealth: { await bridge.currentHealth() },
                openUsagePage: { await bridge.open() },
                repairCompanion: { await bridge.repair() },
                verifyHandshake: { await bridge.verifyHandshake() },
                requestAutomaticRefresh: { requestID, allowLaunch in
                    await bridge.requestAutomaticRefresh(
                        requestID: requestID,
                        allowSafariLaunch: allowLaunch
                    )
                },
                closeOwnedUsageTab: { requestID in
                    await bridge.closeOwnedTab(requestID: requestID)
                }
            ),
            hasConsent: { await consent.get() },
            clearConsent: { await consent.set(false) },
            readCache: { await cache.read() },
            writeCache: { data in await cache.write(data) },
            clearCache: { await cache.clear() },
            now: fixture.clock.now,
            autoRefreshEnabled: { true },
            allowSafariLaunch: { true },
            localActivityReader: localReader,
            anchorStore: BrowserTestAnchorStore()
        )
    }

    /// `BrowserTestBridge.send` awaits the connector's inbound handler, so the
    /// returned diagnostics are causally after durable save/readback and avoid
    /// sleeps or scheduler polling under full-suite concurrency.
    private func deliverAndAwaitProcessing(
        _ envelope: ClaudeBrowserObservationEnvelope,
        through bridge: BrowserTestBridge,
        to connector: ClaudeCodeUsageConnector
    ) async -> ClaudeBrowserConnectorDiagnostics {
        await bridge.send(envelope)
        return await connector.diagnostics()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func methodBody(named name: String, in source: String) throws -> Substring {
        let start = try #require(source.range(of: "func \(name)("))
        let next = source.range(
            of: "\n    func ",
            range: start.upperBound..<source.endIndex
        ) ?? source.range(
            of: "\n    private func ",
            range: start.upperBound..<source.endIndex
        )
        return source[start.lowerBound..<(next?.lowerBound ?? source.endIndex)]
    }

    private func expectProjectPrivacyZeros(
        _ connector: ClaudeCodeUsageConnector
    ) async {
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.localActivityReaderInvocationCount == 0)
        #expect(diagnostics.claudeProjectsAccessCount == 0)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class LockedLocalReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    private var observerStorage = 0

    var value: Int { lock.withLock { storage } }
    var observerCreationCount: Int { lock.withLock { observerStorage } }

    func increment() {
        lock.withLock { storage += 1 }
    }

    func recordObserverCreation() {
        lock.withLock { observerStorage += 1 }
    }
}

private struct CountingSmartLocalReader: ClaudeLocalActivityObservationProviding {
    let counter: LockedLocalReadCounter

    func read(now: Date) -> ClaudeLocalActivitySnapshot {
        counter.increment()
        return .unavailable(capturedAt: now)
    }

    func makeLocalActivityObserver(
        onChange: @escaping @Sendable () -> Void
    ) -> CodexLocalActivityObserver {
        counter.recordObserverCreation()
        return CodexLocalActivityObserver(
            sessionRoots: [URL(fileURLWithPath: "/private/tmp/uma-m5rmx-no-project-reader")],
            onChange: onChange
        )
    }
}

private struct UnavailableSmartLocalReader: ClaudeLocalActivityReading {
    func read(now: Date) -> ClaudeLocalActivitySnapshot {
        .unavailable(capturedAt: now)
    }
}
