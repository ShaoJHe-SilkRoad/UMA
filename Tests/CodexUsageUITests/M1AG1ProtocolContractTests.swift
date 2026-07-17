import Foundation
import Testing
@testable import CodexUsageUI
import SwiftUI

struct M1AG1ProtocolContractTests {
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
    func missingSchemaRequiredUsageSummaryIsRejected() async throws {
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

        do {
            _ = try await client.fetchUsage()
            Issue.record("A response missing schema-required summary must not be accepted.")
        } catch let error as CodexUsageClientError {
            #expect(error.failure == .malformedResponse(method: "account/usage/read"))
        }
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
    private var messages: [Data]
    private var writes: [Data] = []

    init(messages: [Data]) {
        self.messages = messages
    }

    func start(executableURL: URL) throws {}

    func write(_ data: Data) throws {
        lock.lock()
        writes.append(data)
        lock.unlock()
    }

    func readLine() async throws -> Data? { try await readMessage() }

    func readMessage() async throws -> Data? { takeMessage() }

    private func takeMessage() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }

    func stop() {}

    func sentObjects() throws -> [[String: Any]] {
        lock.lock()
        let recorded = writes
        lock.unlock()
        return try recorded.map { data in
            try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }
}

private func response(_ id: Int, result: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: ["id": id, "result": result])
}

private func notification(_ method: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["method": method])
}
