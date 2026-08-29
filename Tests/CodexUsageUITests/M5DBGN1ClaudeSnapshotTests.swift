import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5 Local Smart sanitized Claude snapshots")
struct M5DBGN1ClaudeSnapshotTests {
    @Test
    func strictEnvelopeKeepsOnlyAllowlistedQuotaFields() throws {
        let envelope = browserEnvelope(five: 24.5, seven: 41)
        let data = try ClaudeBrowserMessageDecoder.encode(envelope)
        let decoded = try ClaudeBrowserMessageDecoder.decode(data)

        #expect(decoded == envelope)
        #expect(data.count < ClaudeBrowserBridgeContract.maximumMessageBytes)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in [
            "password", "passkey", "cookie", "token", "identity", "email",
            "billing", "chat", "project", "html", "dom",
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test
    func malformedAmbiguousAndExpandedMessagesFailClosed() throws {
        let valid = try ClaudeBrowserMessageDecoder.encode(
            browserEnvelope(five: 20, seven: 30)
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: valid) as? [String: Any]
        )
        object["identity"] = "must-not-cross"
        let expanded = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ClaudeBrowserBridgeError.unexpectedField("identity")) {
            _ = try ClaudeBrowserMessageDecoder.decode(expanded)
        }

        for percentage in [Double.nan, -0.01, 100.01] {
            #expect(throws: ClaudeBrowserBridgeError.invalidPercentage) {
                try ClaudeBrowserMessageDecoder.validate(
                    browserEnvelope(five: percentage, seven: nil)
                )
            }
        }
        #expect(throws: ClaudeBrowserBridgeError.messageTooLarge) {
            _ = try ClaudeBrowserMessageDecoder.decode(
                Data(repeating: 0x41, count: ClaudeBrowserBridgeContract.maximumMessageBytes + 1)
            )
        }
    }

    @Test
    func usedPercentageConvertsToRemainingExactlyOnce() async throws {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await connector.accuracySync()
        await fixture.bridge.send(browserEnvelope(five: 37.5, seven: 100))

        let snapshot = await connector.currentSnapshot()
        let channel = try #require(snapshot.channels.first)
        let windows = channel.rateLimitWindows
        #expect(windows.first { $0.kind == .fiveHour }?.usedPercent == nil)
        #expect(windows.first { $0.kind == .fiveHour }?.remainingPercent == 62.5)
        #expect(windows.first { $0.kind == .fiveHour }?.normalizedRemainingPercent == 62.5)
        #expect(windows.first { $0.kind == .sevenDay }?.normalizedRemainingPercent == 0)
    }

    @Test
    func ownerOnlySanitizedCacheRoundTripsCanonicalQuotaAndClears() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("uma-m5-browser-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sanitized-quota.json")
        let store = ClaudeBrowserSanitizedCacheStore(url: url)
        let data = try ClaudeBrowserMessageDecoder.encode(
            browserEnvelope(five: 24.5, seven: 41)
        )

        try await store.save(data)
        #expect(await store.load() == data)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.path
        )
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(
            (fileAttributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid()
        )

        try await store.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func sanitizedCacheRejectsExpandedWrongModeAndSymlinkPaths() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("uma-m5-browser-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sanitized-quota.json")
        let store = ClaudeBrowserSanitizedCacheStore(url: url)

        await #expect(throws: ClaudeBrowserSanitizedCacheStore.StoreError.rejectedPayload) {
            try await store.save(Data(#"{"identity":"must-not-cross"}"#.utf8))
        }

        let data = try ClaudeBrowserMessageDecoder.encode(
            browserEnvelope(five: 20, seven: 30)
        )
        try await store.save(data)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: url.path
        )
        #expect(await store.load() == nil)
        await #expect(throws: ClaudeBrowserSanitizedCacheStore.StoreError.wrongPermissions) {
            try await store.clear()
        }

        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(
            at: url,
            withDestinationURL: URL(fileURLWithPath: "/dev/null")
        )
        await #expect(throws: ClaudeBrowserSanitizedCacheStore.StoreError.wrongType) {
            try await store.save(data)
        }
    }
}

func browserEnvelope(
    five: Double?,
    seven: Double?,
    observedAt: String = "2030-03-01T12:00:00Z",
    browser: ClaudeBrowserFamily = .safari
) -> ClaudeBrowserObservationEnvelope {
    ClaudeBrowserObservationEnvelope(
        browserFamily: browser,
        observation: ClaudeBrowserObservation(
            fiveHour: five.map {
                ClaudeBrowserQuotaWindow(
                    usedPercentage: $0,
                    resetAt: "2030-03-01T17:00:00Z"
                )
            },
            weeklyAllModels: seven.map {
                ClaudeBrowserQuotaWindow(
                    usedPercentage: $0,
                    resetAt: "2030-03-08T12:00:00Z"
                )
            },
            observedAt: observedAt
        )
    )
}

actor BrowserTestConsent {
    private var value: Bool
    init(_ value: Bool) { self.value = value }
    func get() -> Bool { value }
    func set(_ next: Bool) { value = next }
}

actor BrowserTestBridge {
    private var handler: ClaudeBrowserProductionIntegration.MessageHandler?
    private(set) var health: ClaudeBrowserCompanionHealth = .ready
    private var startError: ClaudeBrowserBridgeError?
    private(set) var openCount = 0
    private(set) var repairCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var automaticRequests: [(requestID: String, allowSafariLaunch: Bool)] = []
    private var automaticRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var closedRequestIDs: [String] = []
    private var automaticDispatchResult: ClaudeBrowserAutomaticDispatchResult = .dispatched
    private var verificationResult: ClaudeBrowserCompanionVerification = .verified
    private(set) var verificationCount = 0

    func start(
        _ handler: @escaping ClaudeBrowserProductionIntegration.MessageHandler
    ) async {
        self.handler = handler
        startCount += 1
        if let startError {
            self.handler = nil
            await handler(.observation(.failure(startError)))
        }
    }

    func stop() { stopCount += 1; handler = nil }
    func currentHealth() -> ClaudeBrowserCompanionHealth { health }
    func setHealth(_ next: ClaudeBrowserCompanionHealth) { health = next }
    func setStartError(_ next: ClaudeBrowserBridgeError?) { startError = next }
    func open() -> Bool { openCount += 1; return true }
    func repair() -> ClaudeBrowserCompanionHealth { repairCount += 1; return health }
    func setAutomaticDispatchResult(_ result: ClaudeBrowserAutomaticDispatchResult) {
        automaticDispatchResult = result
    }
    func setVerificationResult(_ result: ClaudeBrowserCompanionVerification) {
        verificationResult = result
    }
    func verifyHandshake() -> ClaudeBrowserCompanionVerification {
        verificationCount += 1
        return verificationResult
    }
    func requestAutomaticRefresh(
        requestID: String,
        allowSafariLaunch: Bool
    ) -> ClaudeBrowserAutomaticDispatchResult {
        automaticRequests.append((requestID, allowSafariLaunch))
        let waiters = automaticRequestWaiters
        automaticRequestWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return automaticDispatchResult
    }
    func waitForAutomaticRequest() async {
        if !automaticRequests.isEmpty { return }
        await withCheckedContinuation { continuation in
            automaticRequestWaiters.append(continuation)
        }
    }
    func closeOwnedTab(requestID: String) { closedRequestIDs.append(requestID) }
    func send(_ envelope: ClaudeBrowserObservationEnvelope) async {
        let requestID = automaticRequests.last?.requestID ?? envelope.requestID
        let requestBound = ClaudeBrowserObservationEnvelope(
            browserFamily: envelope.browserFamily,
            observation: envelope.observation,
            kind: envelope.kind,
            schemaVersion: envelope.schemaVersion,
            sourceID: envelope.sourceID,
            routeState: envelope.routeState,
            requestID: requestID,
            observationID: envelope.observationID
        )
        await handler?(.observation(.success(requestBound)))
    }
    func sendUnbound(_ envelope: ClaudeBrowserObservationEnvelope) async {
        await handler?(.observation(.success(envelope)))
    }
    func reject(_ error: ClaudeBrowserBridgeError = .malformedJSON) async {
        await handler?(.observation(.failure(error)))
    }
    func sendAutomation(
        requestID: String,
        status: ClaudeBrowserAutomationStatus,
        occurredAt: String = "2030-03-01T12:00:00Z"
    ) async {
        await handler?(.automation(ClaudeBrowserAutomationEvent(
            requestID: requestID,
            status: status,
            occurredAt: occurredAt,
            companionVersion: status == .bridgeReady
                ? ClaudeBrowserBridgeContract.safariExtensionVersion
                : nil,
            companionBuild: status == .bridgeReady
                ? ClaudeBrowserBridgeContract.safariExtensionBuild
                : nil,
            protocolSchemaVersion: status == .bridgeReady
                ? ClaudeBrowserBridgeContract.schemaVersion
                : nil
        )))
    }
}

actor BrowserTestCache {
    private var value: Data?
    private(set) var writeCount = 0
    private(set) var clearCount = 0

    init(_ value: Data? = nil) { self.value = value }
    func read() -> Data? { value }
    func write(_ data: Data) { value = data; writeCount += 1 }
    func clear() { value = nil; clearCount += 1 }
}

final class BrowserTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date = Date(timeIntervalSince1970: 1_898_596_800)) {
        self.value = value
    }
    func now() -> Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}

struct BrowserConnectorFixture {
    let consent: BrowserTestConsent
    let autoRefresh: BrowserTestConsent
    let allowSafariLaunch: BrowserTestConsent
    let bridge = BrowserTestBridge()
    let cache: BrowserTestCache
    let clock: BrowserTestClock

    init(
        consent: Bool,
        autoRefresh: Bool = false,
        allowSafariLaunch: Bool = false,
        clock: BrowserTestClock = BrowserTestClock()
    ) {
        self.init(
            consent: consent,
            autoRefresh: autoRefresh,
            allowSafariLaunch: allowSafariLaunch,
            clock: clock,
            cache: BrowserTestCache()
        )
    }

    init(
        consent: Bool,
        autoRefresh: Bool = false,
        allowSafariLaunch: Bool = false,
        clock: BrowserTestClock,
        cache: BrowserTestCache
    ) {
        self.consent = BrowserTestConsent(consent)
        self.autoRefresh = BrowserTestConsent(autoRefresh)
        self.allowSafariLaunch = BrowserTestConsent(allowSafariLaunch)
        self.clock = clock
        self.cache = cache
    }

    func connector(
        anchorStore: (any ClaudeSmartAnchorStoring)? = nil,
        sleep: @escaping ClaudeCodeUsageConnector.Sleeper = { interval in
            try await Task.sleep(for: .seconds(interval))
        }
    ) -> ClaudeCodeUsageConnector {
        let bridge = bridge
        let consent = consent
        let autoRefresh = autoRefresh
        let allowSafariLaunch = allowSafariLaunch
        let cache = cache
        let effectiveAnchorStore: any ClaudeSmartAnchorStoring =
            anchorStore ?? BrowserTestAnchorStore()
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
            now: clock.now,
            autoRefreshEnabled: { await autoRefresh.get() },
            allowSafariLaunch: { await allowSafariLaunch.get() },
            sleep: sleep,
            anchorStore: effectiveAnchorStore
        )
    }
}

actor BrowserTestAnchorStore: ClaudeSmartAnchorStoring {
    private var anchors: [ClaudeSmartWindowAnchor] = []

    func load() -> [ClaudeSmartWindowAnchor] { anchors }

    func save(_ anchors: [ClaudeSmartWindowAnchor]) {
        self.anchors = anchors
    }

    func clear() {
        anchors.removeAll()
    }
}

actor BrowserTestSleeper {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private(set) var intervals: [TimeInterval] = []
    private var waiters: [Waiter] = []

    func sleep(_ interval: TimeInterval) async throws {
        let id = UUID()
        intervals.append(interval)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func resumeNext() {
        guard !waiters.isEmpty else { return }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume()
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}
