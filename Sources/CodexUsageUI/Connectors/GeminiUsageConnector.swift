import ClaudeBrowserBridgeProtocol
import Foundation

/// Gemini App usage read from the official gemini.google.com Usage page
/// through the Safari Bridge. It is the Gemini App's own quota as Google
/// shows it there. It is not Antigravity's quota: Antigravity counts per
/// model group, and whether the two share a pool is not established, so this
/// connector never stands in for Antigravity.
actor GeminiUsageConnector: AgentUsageConnector {
    typealias UsageReader = @Sendable () async throws -> GeminiBrowserObservation
    typealias PreferenceReader = @Sendable () async -> Bool
    typealias Now = @Sendable () -> Date
    typealias Stopper = @Sendable () async -> Void

    static let connectorID = AgentConnectorID(rawValue: "gemini.browserUsage")!
    static let providerName = "Gemini"
    static let sourceVersion = "gemini-web-usage-1"
    static let freshnessInterval: TimeInterval = 5 * 60
    static let staleInterval: TimeInterval = 30 * 60
    /// Timer reads follow AUV's own automatic refresh; this only keeps them
    /// from opening Safari tabs more often than every five minutes.
    static let minimumTimerReadSpacing: TimeInterval = 5 * 60

    /// The page's "Current usage" row is AUV's five-hour window: the page
    /// does not state the period, but the row shows the GXU_FIVE_HOURLY pool.
    static let currentUsageKind: AgentRateLimitWindow.Kind = .fiveHour

    static let capabilities: Set<AgentConnectorCapability> = [
        .connect,
        .reconnect,
        .refresh,
        .disconnect,
        .rateLimits,
        .sanitizedLastValidRestore,
        .automaticRefresh,
    ]

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: providerName,
        officialSource: "gemini.google.com Usage page · Safari Bridge",
        sourceTier: .authorizedReadOnlyRemote,
        sourceVersion: sourceVersion,
        supportedScopes: [.account],
        capabilities: capabilities,
        configurationRequirements: [.userAuthorization],
        privacyAllowlist: [
            "bucketID",
            "usedPercent",
            "bucketResetAt",
            "planLabel",
            "observedAt",
            "sourceVersion",
            "freshness",
        ],
        supportsRestore: false,
        supportsUninstall: false,
        unsupportedFields: [
            "accountIdentity",
            "credentials",
            "tokens",
            "cookies",
            "conversation",
            "conversationTitle",
            "prompt",
            "response",
            "pageText",
            "url",
        ],
        expectedRuntime: .none,
        localSourceClass: .browserCompanionUsage,
        authenticationMethod: .systemBrowserSession,
        usageReadContract: .currentBrowserCompanionUsageRead,
        loginAssistance: .existingSessionOnly
    )!

    private struct ActiveRead {
        let generation: UInt64
        let task: Task<Result<GeminiBrowserObservation, GeminiBrowserReadError>, Never>
    }

    private let readUsage: UsageReader
    private let hasConsent: PreferenceReader
    private let stopReader: Stopper
    private let now: Now

    private var snapshot: AgentUsageSnapshot
    private var lastGood: AgentUsageSnapshot?
    private var lastError: GeminiBrowserReadError?
    private var continuations: [UUID: AsyncStream<AgentUsageSnapshot>.Continuation] = [:]
    private var started = false
    private var activeRead: ActiveRead?
    private var readGeneration: UInt64 = 0
    private var lastReadStartedAt: Date?
    private var automaticRefreshSuspended = false

    init(
        readUsage: @escaping UsageReader,
        hasConsent: @escaping PreferenceReader,
        stopReader: @escaping Stopper = {},
        now: @escaping Now = Date.init
    ) {
        self.readUsage = readUsage
        self.hasConsent = hasConsent
        self.stopReader = stopReader
        self.now = now
        snapshot = Self.unavailableSnapshot(state: .inactive, failure: nil, capturedAt: now())
    }

    static func production(
        integration: GeminiBrowserIntegration,
        hasConsent: @escaping PreferenceReader
    ) -> GeminiUsageConnector {
        let reader = GeminiBrowserReader(integration: integration)
        return GeminiUsageConnector(
            readUsage: { try await reader.read() },
            hasConsent: hasConsent,
            stopReader: { await reader.stop() }
        )
    }

    func permitsRead(for trigger: ProviderEligibilityScanTrigger) async -> Bool {
        _ = trigger
        return await hasConsent()
    }

    func probe() async -> AgentConnectorProbe {
        guard await hasConsent() else {
            return AgentConnectorProbe(state: .authenticationRequired, safeFailure: .authorizationRequired)
        }
        refreshAge()
        return AgentConnectorProbe(
            state: snapshot.hasValidData ? snapshot.state : .inactive,
            safeFailure: snapshot.safeFailure
        )
    }

    func start() async {
        guard !started else { return }
        started = true
        automaticRefreshSuspended = false
        if !snapshot.hasValidData {
            replace(Self.unavailableSnapshot(
                state: .waitingForFirstResponse, failure: nil, capturedAt: now()
            ))
        }
    }

    func refresh() async {
        await refresh(trigger: .manual)
    }

    func refresh(trigger: CodexRefreshTrigger) async {
        switch trigger {
        case .wake:
            refreshAge()
        case .timer:
            // A page that needs the person to act in Safari is not asked
            // again by the timer, and reads stay spaced out.
            guard !automaticRefreshSuspended else { return }
            if let lastReadStartedAt,
               now().timeIntervalSince(lastReadStartedAt) < Self.minimumTimerReadSpacing {
                refreshAge()
                return
            }
            await requestRead()
        case .providerEvent, .reconnect, .manual:
            automaticRefreshSuspended = false
            await requestRead()
        }
    }

    func perform(_ command: AgentConnectorCommand) async {
        switch command {
        case .connect, .reconnect:
            automaticRefreshSuspended = false
            if !started { await start() }
            await requestRead()
        case .refresh:
            if !started { await start() }
            await requestRead()
        case .disconnect:
            await disconnect()
        }
    }

    func stop() async {
        await disconnect()
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        refreshAge()
        return snapshot
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        let subscriptionID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[subscriptionID] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(subscriptionID) }
            }
        }
    }

    /// The last read's failure, for Settings to say what to do next; nil
    /// after a successful read.
    func lastReadError() -> GeminiBrowserReadError? {
        lastError
    }

    private func requestRead() async {
        guard started, await hasConsent() else { return }
        if let activeRead {
            _ = await activeRead.task.value
            return
        }
        readGeneration &+= 1
        let generation = readGeneration
        let reader = readUsage
        let task = Task<Result<GeminiBrowserObservation, GeminiBrowserReadError>, Never> {
            do {
                return .success(try await reader())
            } catch let error as GeminiBrowserReadError {
                return .failure(error)
            } catch {
                return .failure(.cancelled)
            }
        }
        activeRead = ActiveRead(generation: generation, task: task)
        lastReadStartedAt = now()
        let result = await task.value
        guard activeRead?.generation == generation else { return }
        activeRead = nil
        apply(result)
    }

    private func apply(_ result: Result<GeminiBrowserObservation, GeminiBrowserReadError>) {
        switch result {
        case let .success(observation):
            lastError = nil
            automaticRefreshSuspended = false
            guard let next = Self.makeSnapshot(observation, capturedAt: now()) else {
                apply(.failure(.usageUnavailable))
                return
            }
            lastGood = next
            replace(next)
        case let .failure(error):
            lastError = error
            switch error {
            case .permissionRequired, .signInRequired:
                // Nothing changes until the person acts in Safari, so the
                // timer stops asking; a manual refresh starts it again.
                automaticRefreshSuspended = true
                lastGood = nil
                replace(Self.unavailableSnapshot(
                    state: .authenticationRequired,
                    failure: .authorizationRequired,
                    capturedAt: now()
                ))
            case .protocolMismatch:
                automaticRefreshSuspended = true
                lastGood = nil
                replace(Self.unavailableSnapshot(
                    state: .unsupported, failure: .unsupported, capturedAt: now()
                ))
            default:
                let failure = Self.safeFailure(for: error)
                if let lastGood {
                    replace(Self.retainedSnapshot(lastGood, at: now(), failure: failure))
                } else {
                    replace(Self.unavailableSnapshot(
                        state: .failed, failure: failure, capturedAt: now()
                    ))
                }
            }
        }
    }

    private func refreshAge() {
        guard let lastGood else { return }
        let retained = Self.retainedSnapshot(lastGood, at: now(), failure: snapshot.safeFailure)
        if retained.freshness != snapshot.freshness { replace(retained) }
    }

    private func disconnect() async {
        started = false
        automaticRefreshSuspended = false
        lastReadStartedAt = nil
        activeRead?.task.cancel()
        await stopReader()
        if let task = activeRead?.task { _ = await task.value }
        activeRead = nil
        lastGood = nil
        lastError = nil
        replace(Self.unavailableSnapshot(state: .inactive, failure: nil, capturedAt: now()))
    }

    private func replace(_ next: AgentUsageSnapshot) {
        snapshot = next
        for continuation in continuations.values { continuation.yield(next) }
    }

    private func removeContinuation(_ subscriptionID: UUID) {
        continuations[subscriptionID] = nil
    }

    // MARK: - Snapshots

    /// The page's two rows as AUV windows. Unknown buckets are dropped; a
    /// reading with neither row is no reading.
    static func windows(for observation: GeminiBrowserObservation) -> [AgentRateLimitWindow] {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ raw: String?) -> Date? {
            guard let raw else { return nil }
            return parser.date(from: raw) ?? plain.date(from: raw)
        }
        var windows: [AgentRateLimitWindow] = []
        for bucket in observation.buckets {
            let kind: AgentRateLimitWindow.Kind
            switch bucket.bucketID {
            case "current": kind = currentUsageKind
            case "weekly": kind = .sevenDay
            default: continue
            }
            guard bucket.usedPercentage.isFinite, (0...100).contains(bucket.usedPercentage) else { continue }
            windows.append(AgentRateLimitWindow(
                id: bucket.bucketID,
                kind: kind,
                usedPercent: bucket.usedPercentage,
                isUnlimited: false,
                resetsAt: date(bucket.resetAt)
            ))
        }
        return windows
    }

    static func makeSnapshot(
        _ observation: GeminiBrowserObservation,
        capturedAt: Date
    ) -> AgentUsageSnapshot? {
        let windows = windows(for: observation)
        guard !windows.isEmpty else { return nil }
        let observedAt = ISO8601DateFormatter.geminiObservedAt(observation.observedAt) ?? capturedAt
        let account = AgentUsageChannel(
            id: .account,
            sourceTier: .authorizedReadOnlyRemote,
            sourceVersion: sourceVersion,
            scopes: [.account],
            provenance: .providerReported,
            freshness: .fresh,
            capturedAt: observedAt,
            coverageNote: nil,
            rateLimitWindows: windows,
            accountMetrics: observation.planLabel.map {
                AgentAccountMetrics(
                    planLabel: $0, availableResets: nil, lifetimeTokens: nil, sevenDayTokens: nil
                )
            },
            localActivityMetrics: nil,
            safeFailure: nil
        )
        return AgentUsageSnapshot(
            id: connectorID,
            providerName: providerName,
            state: .ready,
            capturedAt: capturedAt,
            lastSuccessfulAt: observedAt,
            freshness: .fresh,
            channels: [account],
            capabilities: capabilities,
            safeFailure: nil
        )
    }

    private static func retainedSnapshot(
        _ lastGood: AgentUsageSnapshot,
        at now: Date,
        failure: AgentSafeFailure?
    ) -> AgentUsageSnapshot {
        let age = now.timeIntervalSince(lastGood.lastSuccessfulAt ?? .distantPast)
        let freshness: AgentConnectorFreshness
        let state: AgentConnectorState
        if failure != nil, age <= staleInterval {
            // A failed read may keep the last value, never as current.
            freshness = .cached
            state = .ready
        } else if age <= freshnessInterval {
            freshness = .fresh
            state = .ready
        } else if age <= staleInterval {
            freshness = .cached
            state = .ready
        } else {
            freshness = .stale
            state = .stale
        }
        let channels = lastGood.channels.map {
            AgentUsageChannel(
                id: $0.id,
                sourceTier: $0.sourceTier,
                sourceVersion: $0.sourceVersion,
                scopes: $0.scopes,
                provenance: $0.provenance,
                freshness: freshness,
                capturedAt: $0.capturedAt,
                coverageNote: $0.coverageNote,
                rateLimitWindows: $0.rateLimitWindows,
                accountMetrics: $0.accountMetrics,
                localActivityMetrics: nil,
                safeFailure: failure
            )
        }
        return AgentUsageSnapshot(
            id: connectorID,
            providerName: providerName,
            state: state,
            capturedAt: now,
            lastSuccessfulAt: lastGood.lastSuccessfulAt,
            freshness: freshness,
            channels: channels,
            capabilities: capabilities,
            safeFailure: failure,
            selectedWindowID: lastGood.selectedWindowID
        )
    }

    private static func unavailableSnapshot(
        state: AgentConnectorState,
        failure: AgentSafeFailure?,
        capturedAt: Date
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: connectorID,
            providerName: providerName,
            state: state,
            capturedAt: capturedAt,
            lastSuccessfulAt: nil,
            freshness: .unavailable,
            channels: [],
            capabilities: capabilities,
            safeFailure: failure
        )
    }

    private static func safeFailure(for error: GeminiBrowserReadError) -> AgentSafeFailure {
        switch error {
        case .permissionRequired, .signInRequired: .authorizationRequired
        case .timedOut: .timedOut
        case .protocolMismatch: .unsupported
        case .usageUnavailable: .malformedResponse
        case .companionUnavailable, .browserUnavailable, .busy, .tabUnavailable, .cancelled:
            .unavailable
        }
    }
}

private extension ISO8601DateFormatter {
    static func geminiObservedAt(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
