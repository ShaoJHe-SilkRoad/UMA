import Foundation
import Testing
@testable import CodexUsageUI
import SwiftUI

@Suite(.timeLimit(.minutes(1)))
struct M1AG1ProtocolContractTests {

    @Test(arguments: [
        #"{"userAgent":"protocol-test"}"#,
        #"{"userAgent":"protocol-test","platformFamily":"unix","platformOs":"macos"}"#,
        #"{"userAgent":"protocol-test","codexHome":null,"platformFamily":null,"platformOs":null}"#,
        #"{"userAgent":"protocol-test","codexHome":"/synthetic/.codex","platformFamily":"unix","platformOs":"macos","futureDiagnostic":"ignored"}"#
    ])
    func optionalInitializationMetadataDoesNotBlockVerifiedQuota(resultJSON: String) async throws {
        let result = try #require(JSONSerialization.jsonObject(with: Data(resultJSON.utf8)) as? [String: Any])
        let sequence = providerReadSequence()
        let transport = ProtocolTransport(messages: [response(1, result: result)] + sequence.dropFirst())
        let session = CodexAppServerSession(transportFactory: { transport })
        let client = CodexAppServerClient(resolver: FixedResolver(), session: session)

        let usage = try await client.fetchUsage()
        #expect(usage.rateLimits.primary?.usedPercent == 20)
        #expect(await client.connectionState() == .ready)
        #expect(try transport.sentObjects().map { $0["method"] as? String } == [
            "initialize", "initialized", "account/read", "account/rateLimits/read", "account/usage/read"
        ])
        await client.disconnect()
    }

    @Test(arguments: [
        #"{}"#,
        #"{"userAgent":null}"#,
        #"{"userAgent":42}"#,
        #"{"userAgent":"protocol-test","platformOs":42}"#
    ])
    func malformedInitializationNeverReachesAccountReads(resultJSON: String) async throws {
        let result = try #require(JSONSerialization.jsonObject(with: Data(resultJSON.utf8)) as? [String: Any])
        let transport = ProtocolTransport(messages: [response(1, result: result)])
        let session = CodexAppServerSession(transportFactory: { transport })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        do {
            try await session.initializeIfNeeded()
            Issue.record("Malformed initialization must fail before account reads.")
        } catch let error as CodexUsageClientError {
            #expect(error.failure == .malformedResponse(method: "initialize"))
        }
        #expect(await session.hasUsableInitializedTransport() == false)
        #expect(try transport.sentObjects().map { $0["method"] as? String } == ["initialize"])
        await session.shutdown()
    }

    @Test(arguments: [
        #"{"userAgent":"  "}"#,
        #"{"userAgent":"protocol-test","codexHome":"relative/home"}"#,
        #"{"userAgent":"protocol-test","platformFamily":""}"#,
        #"{"userAgent":"protocol-test","platformOs":"  "}"#
    ])
    func invalidProvidedInitializationMetadataIsStillRejected(resultJSON: String) async throws {
        let result = try #require(JSONSerialization.jsonObject(with: Data(resultJSON.utf8)) as? [String: Any])
        let transport = ProtocolTransport(messages: [response(1, result: result)])
        let session = CodexAppServerSession(transportFactory: { transport })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        do {
            try await session.initializeIfNeeded()
            Issue.record("Invalid metadata must not establish a usable session.")
        } catch let error as CodexUsageClientError {
            #expect(error.failure == .protocolIncompatible)
        }
        #expect(await session.hasUsableInitializedTransport() == false)
        #expect(try transport.sentObjects().map { $0["method"] as? String } == ["initialize"])
        await session.shutdown()
    }

    @Test
    func productionTransportUsesDefaultStdioWithAnIsolatedSyntheticServer() async throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("auv-0172-connection-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("synthetic-app-server")
        // Only shell builtins and synthetic JSON are used: no installed Codex,
        // account files, provider requests, or user storage are accessed.
        let script = #"""
        #!/bin/sh
        [ "$#" -eq 1 ] && [ "$1" = "app-server" ] || exit 61
        [ "$PWD" = "/" ] && [ -d "$HOME" ] || exit 62
        [ -z "${CODEX_HOME+x}" ] || exit 63
        while IFS= read -r request; do
            case "$request" in
                *'"method":"initialize"'*)
                    printf '%s\n' '{"id":1,"result":{"userAgent":"isolated-process-fixture"}}'
                    ;;
            esac
        done
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let transport = ProcessCodexAppServerTransport(launchConfiguration: .init(homeDirectory: root.path))
        defer { transport.stop() }
        let session = CodexAppServerSession(
            transportFactory: { transport },
            requestTimeout: 2,
            initializationTimeout: 2
        )
        try await session.start(executableURL: executable)
        try await session.initializeIfNeeded()
        #expect(await session.hasUsableInitializedTransport())
        await session.shutdown()
    }
    @Test
    func accountWireContractUsesSchemaRequiredShapes() async throws {
        let transport = ProtocolTransport(messages: [
            response(1, result: [
                "codexHome": "/synthetic/.codex",
                "platformFamily": "unix",
                "platformOs": "macos",
                "userAgent": "protocol-test"
            ]),
            response(2, result: [:]),
            response(3, result: [:]),
            response(4, result: [:])
        ])
        let session = CodexAppServerSession(transportFactory: { transport })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        try await session.initializeIfNeeded()
        let _: EmptyResult = try await session.request(method: "account/read", params: EmptyParameters())
        let _: EmptyResult = try await session.requestWithExplicitNullParameters(method: "account/rateLimits/read")
        let _: EmptyResult = try await session.requestWithExplicitNullParameters(method: "account/usage/read")
        await session.shutdown()

        let sent = try transport.sentObjects()
        #expect(sent.count == 5)
        #expect(sent[0]["method"] as? String == "initialize")
        let initialize = try #require(sent[0]["params"] as? [String: Any])
        let clientInfo = try #require(initialize["clientInfo"] as? [String: Any])
        #expect(clientInfo["name"] as? String == "codex-usage-monitor")
        #expect(clientInfo["version"] as? String == "1.0.0")
        #expect(sent[1]["method"] as? String == "initialized")
        #expect(sent[1]["params"] == nil)
        #expect(sent[2]["method"] as? String == "account/read")
        #expect((sent[2]["params"] as? [String: Any])?.isEmpty == true)
        #expect(sent[3]["params"] is NSNull)
        #expect(sent[4]["params"] is NSNull)
    }

    @Test
    func bothSchemaAccountNotificationsRequestOneExplicitRefresh() async throws {
        let transport = ProtocolTransport(messages: [
            response(1, result: [
                "codexHome": "/synthetic/.codex",
                "platformFamily": "unix",
                "platformOs": "macos",
                "userAgent": "protocol-test"
            ]),
            notification("account/updated"),
            response(2, result: [:]),
            notification("account/rateLimits/updated"),
            response(3, result: [:])
        ])
        let session = CodexAppServerSession(transportFactory: { transport })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        try await session.initializeIfNeeded()
        let _: EmptyResult = try await session.request(method: "account/read", params: EmptyParameters())
        #expect(await session.takeUsageRefreshRequest())
        let _: EmptyResult = try await session.requestWithExplicitNullParameters(method: "account/rateLimits/read")
        #expect(await session.takeUsageRefreshRequest())
        await session.shutdown()
    }

    @Test
    func idleSchemaNotificationsPublishOnlySanitizedTypedEvents() async throws {
        let transport = ProtocolTransport(messages: [initializeResponse()])
        let session = CodexAppServerSession(transportFactory: { transport })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        try await session.initializeIfNeeded()

        let stream = await session.eventStream()
        var iterator = stream.makeAsyncIterator()
        transport.sendInbound(notification("account/updated"))
        #expect(await iterator.next() == .accountUpdated)
        #expect(await session.takeUsageRefreshRequest())

        transport.sendInbound(notification("account/rateLimits/updated"))
        #expect(await iterator.next() == .rateLimitsUpdated)
        #expect(await session.takeUsageRefreshRequest())
        await session.shutdown()
    }

    @Test
    func unknownIdleNotificationIsDiscardedBeforeTheNextSerializedResponse() async throws {
        let transport = ProtocolTransport(messages: [
            initializeResponse(),
            response(2, result: [:])
        ])
        let session = CodexAppServerSession(transportFactory: { transport })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        try await session.initializeIfNeeded()

        // Future provider notifications may carry arbitrary fields. The
        // monitor must discard an unsupported method without retaining its
        // payload or scheduling an account read.
        transport.sendInbound(notification("account/futureUpdated"))
        let _: EmptyResult = try await session.request(method: "account/read", params: EmptyParameters())
        #expect(await session.takeUsageRefreshRequest() == false)
        await session.shutdown()
    }

    @Test
    func exitedTransportIsReplacedAndReinitializedByTheLivenessRepair() async throws {
        let first = ProtocolTransport(messages: [
            response(1, result: [
                "codexHome": "/synthetic/.codex",
                "platformFamily": "unix",
                "platformOs": "macos",
                "userAgent": "protocol-test"
            ])
        ])
        let second = ProtocolTransport(messages: [
            response(1, result: [
                "codexHome": "/synthetic/.codex",
                "platformFamily": "unix",
                "platformOs": "macos",
                "userAgent": "protocol-test"
            ])
        ])
        let factory = TransportQueue([first, second])
        let session = CodexAppServerSession(transportFactory: { factory.next() })

        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        try await session.initializeIfNeeded()
        first.markExited()

        try await session.repairExitedTransportIfNeeded()

        #expect(factory.startCount == 2)
        #expect(try first.sentObjects().map { $0["method"] as? String } == ["initialize", "initialized"])
        #expect(try second.sentObjects().map { $0["method"] as? String } == ["initialize", "initialized"])
        await session.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func ownedChildReplacementPublishesOneSanitizedRecoveryInvalidation() async throws {
        let first = ProtocolTransport(messages: providerReadSequence())
        let second = ProtocolTransport(messages: providerReadSequence())
        let factory = TransportQueue([first, second])
        let session = CodexAppServerSession(transportFactory: { factory.next() })
        let client = CodexAppServerClient(
            resolver: FixedResolver(),
            session: session,
            ownedProcessMonitorInterval: .milliseconds(5)
        )

        let stream = await client.eventStream()
        var iterator = stream.makeAsyncIterator()
        _ = try await client.fetchUsage()
        first.markExited()

        // This is the production-owned monitor's cadence, not a readiness
        // delay. Await the actual replacement event; loss may precede it or
        // coalesce with it in the latest-event buffer.
        var observedRecovery = false
        while let event = await iterator.next() {
            if event == .transportRecovered {
                observedRecovery = true
                break
            }
        }
        #expect(observedRecovery)
        #expect(factory.startCount == 2)
        #expect(try second.sentObjects().map { $0["method"] as? String } == [
            "initialize",
            "initialized"
        ])
        await client.disconnect()
    }

    @Test
    func missingOptionalUsageSummaryPreservesVerifiedQuota() async throws {
        let transport = ProtocolTransport(messages: [
            response(1, result: [
                "codexHome": "/synthetic/.codex",
                "platformFamily": "unix",
                "platformOs": "macos",
                "userAgent": "protocol-test"
            ]),
            response(2, result: [
                "account": ["type": "chatgpt"],
                "requiresOpenaiAuth": true
            ]),
            response(3, result: ["rateLimits": [:]]),
            response(4, result: ["dailyUsageBuckets": []])
        ])
        let session = CodexAppServerSession(transportFactory: { transport })
        let client = CodexAppServerClient(
            resolver: FixedResolver(),
            session: session
        )

        let usage = try await client.fetchUsage()
        #expect(usage.lifetimeTokens == nil)
        #expect(usage.dailyUsage == nil)
        #expect(await client.connectionState() == .ready)
        #expect(await session.hasUsableInitializedTransport())
        await client.disconnect()
    }

    @Test(arguments: [-32601, -32000])
    func optionalRPCErrorPreservesQuotaAndNextRefreshDoesNotRetryIt(code: Int) async throws {
        let sequence = providerReadSequence()
        let transport = ProtocolTransport(messages: Array(sequence.prefix(3)) + [
            try JSONSerialization.data(withJSONObject: ["id": 4, "error": [
                "code": code, "message": "synthetic-secret-must-not-be-retained"
            ]]),
            response(5, result: ["account": ["type": "chatgpt"], "requiresOpenaiAuth": true]),
            response(6, result: ["rateLimits": ["primary": ["usedPercent": 35, "windowDurationMins": 300]]])
        ])
        let session = CodexAppServerSession(transportFactory: { transport })
        let client = CodexAppServerClient(resolver: FixedResolver(), session: session)
        let first = try await client.fetchUsage()
        #expect(first.rateLimits.primary?.usedPercent == 20)
        #expect(first.lifetimeTokens == nil)
        let second = try await client.fetchUsage()
        #expect(second.rateLimits.primary?.usedPercent == 35)
        #expect(try transport.sentObjects().filter { $0["method"] as? String == "account/usage/read" }.count == 1)
        #expect(await session.hasUsableInitializedTransport())
        await client.disconnect()
    }

    @Test
    func optionalTimeoutBoundsFirstReadingAndRelaunchRechecksAccount() async throws {
        let firstTransport = ProtocolTransport(messages: Array(providerReadSequence().prefix(3)))
        let secondTransport = ProtocolTransport(messages: [
            initializeResponse(),
            response(2, result: ["account": NSNull(), "requiresOpenaiAuth": true])
        ])
        let queue = TransportQueue([firstTransport, secondTransport])
        // The optional statistics request is never answered, so elapsed time
        // is the only evidence that the optional timeout was applied at all:
        // dropping it falls back to the session's request timeout, pinned here
        // rather than left at its default so the two are far apart. The bound
        // sits between them instead of near either, because a full parallel
        // suite run was measured inflating the 0.03s wait to 4.1 seconds.
        let session = CodexAppServerSession(transportFactory: { queue.next() }, requestTimeout: 60)
        let client = CodexAppServerClient(resolver: FixedResolver(), session: session, optionalUsageTimeout: 0.03)
        let start = ContinuousClock.now
        let usage = try await client.fetchUsage()
        let elapsed = start.duration(to: .now)
        print("FIRST_INSTALL_FIXTURE optional_timeout_first_quota=\(elapsed)")
        #expect(elapsed < .seconds(20))
        #expect(usage.rateLimits.primary?.usedPercent == 20)
        #expect(!firstTransport.isRunning)
        do {
            _ = try await client.fetchUsageAfterVerifiedAccount()
            Issue.record("A replacement session must verify account before returning quota")
        } catch let error as CodexUsageClientError {
            #expect(error.failure == .accountAuthorizationRequired)
        }
        #expect(try secondTransport.sentObjects().map { $0["method"] as? String } == ["initialize", "initialized", "account/read"])
        await client.disconnect()
    }

    @Test
    func requiredQuotaFailureStillRejectsUsageAndDoesNotRequestOptionalStatistics() async throws {
        let transport = ProtocolTransport(messages: Array(providerReadSequence().prefix(2)) + [
            try JSONSerialization.data(withJSONObject: ["id": 3, "error": ["code": -32601, "message": "synthetic"]])
        ])
        let client = CodexAppServerClient(resolver: FixedResolver(), session: CodexAppServerSession(transportFactory: { transport }))
        do {
            _ = try await client.fetchUsage()
            Issue.record("Required quota failure must not become READY")
        } catch let error as CodexUsageClientError {
            #expect(error.failure == .protocolIncompatible)
        }
        #expect(try !transport.sentObjects().contains { $0["method"] as? String == "account/usage/read" })
        await client.disconnect()
    }

    @Test
    func unexpectedSerializedResponseIsRejectedInsteadOfBuffered() async throws {
        let transport = ProtocolTransport(messages: [
            response(1, result: [
                "codexHome": "/synthetic/.codex",
                "platformFamily": "unix",
                "platformOs": "macos",
                "userAgent": "protocol-test"
            ]),
            response(99, result: [:])
        ])
        let session = CodexAppServerSession(transportFactory: { transport })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        try await session.initializeIfNeeded()

        do {
            let _: EmptyResult = try await session.request(method: "account/read", params: EmptyParameters())
            Issue.record("A serialized session cannot retain a response for another request.")
        } catch let error as CodexUsageClientError {
            #expect(error.failure == .malformedResponse(method: "account/read"))
        }
    }

    @Test
    func cleanEOFRejectsTheNextRequestAsAProcessExit() async throws {
        let transport = ProtocolTransport(messages: [initializeResponse()])
        let session = CodexAppServerSession(transportFactory: { transport })
        try await session.start(executableURL: URL(fileURLWithPath: "/synthetic/codex"))
        try await session.initializeIfNeeded()
        transport.finishReading()

        do {
            let _: EmptyResult = try await session.request(method: "account/read", params: EmptyParameters())
            Issue.record("A clean app-server EOF must not leave a usable request lane.")
        } catch let error as CodexUsageClientError {
            #expect(error.failure == .processExited)
        }
    }

    /// This is deliberately opt-in: normal regression runs must never touch a
    /// Human's Codex session.  The Goal runner supplies the real home only for
    /// its authorized, bounded live validation.
    @Test
    @MainActor
    func authorizedLiveStoreRefreshAndReconnectProducesOnlySanitizedEvidence() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["M1A_G1_LIVE_EVIDENCE"] == "1",
              let realHome = environment["M1A_G1_REAL_HOME"],
              let evidencePath = environment["M1A_G1_LIVE_EVIDENCE_PATH"]
        else { return }

        let evidenceURL = URL(fileURLWithPath: evidencePath)
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let ledgerURL = evidenceURL
            .deletingLastPathComponent()
            .appendingPathComponent("live-store-ledger.json")
        let session = CodexAppServerSession(
            transportFactory: {
                ProcessCodexAppServerTransport(
                    launchConfiguration: .init(homeDirectory: realHome)
                )
            }
        )
        let client = CodexAppServerClient(session: session)
        let reader = CodexLocalActivityReader(
            homeDirectory: URL(fileURLWithPath: realHome, isDirectory: true),
            ledgerURL: ledgerURL
        )
        let store = UsageStore(
            autoRefresh: false,
            previewOnly: false,
            language: .english,
            client: client,
            localActivityReader: reader,
            consentDefaults: nil,
            periodicRefreshInterval: .seconds(240)
        )

        do {
            store.grantMonitorConsent()
            await store.connectToLocalSession()
            try assertLiveStoreReady(store)
            let first = sanitizedLiveStoreEvidence(from: store, stage: "initial-connect")

            await store.refresh()
            try assertLiveStoreReady(store)
            let second = sanitizedLiveStoreEvidence(from: store, stage: "first-refresh")

            await store.refresh()
            try assertLiveStoreReady(store)
            let third = sanitizedLiveStoreEvidence(from: store, stage: "second-refresh")

            await store.disconnectMonitor()
            #expect(store.currentState == .idle)
            await store.connectToLocalSession()
            try assertLiveStoreReady(store)
            let recovered = sanitizedLiveStoreEvidence(from: store, stage: "post-reconnect")

            let renderer = ImageRenderer(
                content: UsagePanelView(
                    store: store,
                    tuning: .final,
                    preferencesEnabled: false
                )
                .frame(width: UsagePanelMetrics.width, height: UsagePanelMetrics.height)
            )
            renderer.scale = 1
            #expect(renderer.nsImage != nil)

            let evidence: [String: Any] = [
                "channel": "official-app-server-plus-local-metadata",
                "live_read_count": 12,
                "stages": [first, second, third, recovered]
            ]
            let encoded = try JSONSerialization.data(
                withJSONObject: evidence,
                options: [.sortedKeys]
            )
            try encoded.write(to: evidenceURL, options: .atomic)
        } catch {
            await client.disconnect()
            throw error
        }
        await client.disconnect()
    }
}

private struct EmptyParameters: Encodable {}
private struct EmptyResult: Decodable {}

private struct FixedResolver: CodexExecutableResolving {
    func resolve() throws -> URL { URL(fileURLWithPath: "/synthetic/codex") }
}

@MainActor
private func assertLiveStoreReady(_ store: UsageStore) throws {
    try #require(store.currentState == .ready)
    try #require(store.freshness == .fresh || store.freshness == .refreshRequired)
    try #require(store.snapshot.providerSource?.isAvailable == true)
    try #require(store.snapshot.providerSource?.scope == "account/read, account/rateLimits/read, account/usage/read")
    try #require(store.snapshot.metrics.contains(where: { $0.id == "total" && $0.value != "—" }))
}

@MainActor
private func sanitizedLiveStoreEvidence(from store: UsageStore, stage: String) -> [String: Any] {
    let snapshot = store.snapshot
    return [
        "stage": stage,
        "connection_state": String(describing: store.currentState),
        "freshness": String(describing: store.freshness),
        "provider_available": snapshot.providerSource?.isAvailable ?? false,
        "provider_scope": snapshot.providerSource?.scope ?? "unavailable",
        "provider_period_count": snapshot.periods.count,
        "provider_total_metric_present": snapshot.metrics.contains(where: { $0.id == "total" && $0.value != "—" }),
        "local_available": snapshot.localSource?.isAvailable ?? false,
        "local_coverage_percent": snapshot.localSource?.coverage as Any,
        "recent_task_count": snapshot.recentTasks.count,
        "local_cost_estimate_present": snapshot.apiCostEstimate != nil
    ]
}

private final class ProtocolTransport: CodexAppServerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var plannedMessages: [Data]
    private var availableMessages: [Data] = []
    private var writes: [Data] = []
    private var running = true
    private var readingFinished = false
    private var waitingReader: CheckedContinuation<Data?, Error>?

    init(messages: [Data]) {
        self.plannedMessages = messages
    }

    func start(executableURL: URL) throws {}

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func write(_ data: Data) throws {
        lock.lock()
        writes.append(data)
        let isRequest = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] != nil
        if isRequest {
            releaseMessagesThroughNextResponseLocked()
        }
        let waitingReader = dequeueReaderIfPossibleLocked()
        lock.unlock()
        if let waitingReader {
            waitingReader.continuation.resume(returning: waitingReader.message)
        }
    }

    func readLine() async throws -> Data? { try await readMessage() }

    func readMessage() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !availableMessages.isEmpty {
                let message = availableMessages.removeFirst()
                lock.unlock()
                continuation.resume(returning: message)
            } else if readingFinished {
                lock.unlock()
                continuation.resume(returning: nil)
            } else {
                waitingReader = continuation
                lock.unlock()
            }
        }
    }

    func stop() { finishReading() }

    func markExited() {
        finishReading()
    }

    func finishReading() {
        lock.lock()
        running = false
        readingFinished = true
        let waitingReader = dequeueReaderIfPossibleLocked()
        lock.unlock()
        if let waitingReader {
            waitingReader.continuation.resume(returning: waitingReader.message)
        }
    }

    func sendInbound(_ message: Data) {
        lock.lock()
        guard !readingFinished else {
            lock.unlock()
            return
        }
        availableMessages.append(message)
        let waitingReader = dequeueReaderIfPossibleLocked()
        lock.unlock()
        if let waitingReader {
            waitingReader.continuation.resume(returning: waitingReader.message)
        }
    }

    func sentObjects() throws -> [[String: Any]] {
        lock.lock()
        let recorded = writes
        lock.unlock()
        return try recorded.map { data in
            try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }

    private func releaseMessagesThroughNextResponseLocked() {
        while !plannedMessages.isEmpty {
            let message = plannedMessages.removeFirst()
            availableMessages.append(message)
            let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any]
            if object?["id"] != nil { return }
        }
    }

    private func dequeueReaderIfPossibleLocked() -> (continuation: CheckedContinuation<Data?, Error>, message: Data?)? {
        guard let waitingReader else { return nil }
        if !availableMessages.isEmpty {
            self.waitingReader = nil
            return (waitingReader, availableMessages.removeFirst())
        }
        if readingFinished {
            self.waitingReader = nil
            return (waitingReader, nil)
        }
        return nil
    }
}

private final class TransportQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [ProtocolTransport]
    private(set) var startCount = 0

    init(_ transports: [ProtocolTransport]) {
        self.transports = transports
    }

    func next() -> any CodexAppServerTransport {
        lock.lock()
        defer { lock.unlock() }
        startCount += 1
        return transports.removeFirst()
    }
}

private func response(_ id: Int, result: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: ["id": id, "result": result])
}

private func initializeResponse() -> Data {
    response(1, result: [
        "codexHome": "/synthetic/.codex",
        "platformFamily": "unix",
        "platformOs": "macos",
        "userAgent": "protocol-test"
    ])
}

private func providerReadSequence() -> [Data] {
    [
        initializeResponse(),
        response(2, result: [
            "account": ["type": "chatgpt"],
            "requiresOpenaiAuth": true
        ]),
        response(3, result: [
            "rateLimits": [
                "planType": "PRO",
                "primary": ["usedPercent": 20, "windowDurationMins": 300]
            ]
        ]),
        response(4, result: [
            "summary": ["lifetimeTokens": 100],
            "dailyUsageBuckets": []
        ])
    ]
}

private func notification(_ method: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["method": method])
}
