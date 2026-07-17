import Foundation

/// Provider adapter for the accepted G1 Codex implementation. All Codex
/// transport, child-process ownership, and local metadata reading remain here;
/// the registry and shared presentation store see only `AgentUsageSnapshot`.
actor CodexUsageConnector: AgentUsageConnector {
    static let connectorID = AgentConnectorID(rawValue: "codex.local")!

    nonisolated let id = CodexUsageConnector.connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: CodexUsageConnector.connectorID,
        providerName: "Codex",
        officialSource: "Codex app-server and privacy-safe local metadata",
        sourceTier: .officialLocalService,
        sourceVersion: "m1a-g1",
        supportedScopes: [.account, .device, .session, .task],
        capabilities: [.connect, .reconnect, .refresh, .disconnect, .localActivity, .rateLimits, .accountUsage],
        privacyAllowlist: ["account availability", "rate limits", "aggregate account usage", "metadata-only local aggregates"],
        supportsRestore: true,
        supportsUninstall: true,
        unsupportedFields: ["account identity", "credentials", "conversation content", "source code", "raw payload"]
    )!

    private let client: any CodexUsageClient
    private let localActivityReader: any CodexLocalActivityReading
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var latestProvider: CodexLiveUsage?
    private var latestLocal: CodexLocalActivitySnapshot?
    private var latestFailure: AgentSafeFailure?
    private var lastSuccessfulAt: Date?
    private var state: AgentConnectorState = .inactive
    private var activeCommand = false
    private var localReadGeneration = 0

    init(
        client: any CodexUsageClient = CodexAppServerClient(),
        localActivityReader: any CodexLocalActivityReading = CodexLocalActivityReader()
    ) {
        self.client = client
        self.localActivityReader = localActivityReader
    }

    func probe() async -> AgentConnectorProbe {
        let current = await client.connectionState()
        if state == .inactive { state = Self.normalizedState(current) }
        return AgentConnectorProbe(state: state, safeFailure: latestFailure)
    }

    func start() async { publish() }

    func refresh() async { await run(kind: .refresh) }

    func perform(_ command: AgentConnectorCommand) async {
        switch command {
        case .connect: await run(kind: .connect)
        case .reconnect:
            await client.disconnect()
            await run(kind: .connect)
        case .refresh: await run(kind: .refresh)
        case .disconnect: await stop()
        }
    }

    func stop() async {
        await client.disconnect()
        state = .inactive
        latestFailure = nil
        publish()
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(makeSnapshot())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation() }
            }
        }
    }

    func currentSnapshot() async -> AgentUsageSnapshot { makeSnapshot() }

    private enum RunKind { case connect, refresh }

    private func run(kind: RunKind) async {
        guard !activeCommand else { return }
        activeCommand = true
        defer { activeCommand = false }
        state = .waitingForFirstResponse
        publish()

        let reader = localActivityReader
        let now = Date()
        localReadGeneration += 1
        let generation = localReadGeneration
        let local = Task.detached(priority: .utility) {
            reader.read(now: now)
        }

        do {
            let provider: CodexLiveUsage
            switch kind {
            case .connect:
                let available = try await client.checkLocalAccountAvailability()
                guard available else {
                    latestFailure = .authorizationRequired
                    state = .authenticationRequired
                    latestLocal = await local.value
                    publish()
                    return
                }
                provider = try await client.fetchUsageAfterVerifiedAccount()
            case .refresh:
                provider = try await client.fetchUsage()
            }
            latestProvider = provider
            latestFailure = nil
            lastSuccessfulAt = provider.providerCapturedAt
            state = .ready
            publish()
            Task { [weak self] in
                let activity = await local.value
                await self?.acceptLocalActivity(activity, generation: generation)
            }
        } catch {
            latestLocal = await local.value
            latestFailure = Self.safeFailure(from: error)
            state = latestProvider == nil ? Self.normalizedState(await client.connectionState()) : .stale
            if state == .ready { state = .stale }
            publish()
        }
    }

    private func acceptLocalActivity(_ activity: CodexLocalActivitySnapshot, generation: Int) {
        guard generation == localReadGeneration else { return }
        latestLocal = activity
        publish()
    }

    private func makeSnapshot() -> AgentUsageSnapshot {
        let now = Date()
        var channels: [AgentUsageChannel] = []
        if let provider = latestProvider {
            channels.append(Self.accountChannel(from: provider, freshness: state == .stale ? .stale : .fresh, safeFailure: latestFailure))
        } else if latestFailure != nil || state == .authenticationRequired {
            channels.append(AgentUsageChannel(
                id: .account,
                sourceTier: .officialLocalService,
                sourceVersion: descriptor.sourceVersion,
                scopes: [.account],
                provenance: .providerReported,
                freshness: .unavailable,
                capturedAt: nil,
                coverageNote: nil,
                rateLimitWindows: [],
                accountMetrics: nil,
                localActivityMetrics: nil,
                safeFailure: latestFailure
            ))
        }
        if let activity = latestLocal {
            channels.append(Self.localChannel(from: activity, freshness: .fresh))
        }
        let overallFreshness: AgentConnectorFreshness = channels.contains(where: { $0.freshness == .fresh }) ? .fresh
            : (channels.contains(where: { $0.freshness == .stale }) ? .stale : .unavailable)
        return AgentUsageSnapshot(
            id: id,
            providerName: descriptor.providerName,
            state: state,
            capturedAt: now,
            lastSuccessfulAt: lastSuccessfulAt,
            freshness: overallFreshness,
            channels: channels,
            capabilities: descriptor.capabilities,
            safeFailure: latestFailure
        )
    }

    private func publish() { continuation?.yield(makeSnapshot()) }
    private func clearContinuation() { continuation = nil }

    private static func accountChannel(
        from usage: CodexLiveUsage,
        freshness: AgentConnectorFreshness,
        safeFailure: AgentSafeFailure?
    ) -> AgentUsageChannel {
        let windows = usage.rateLimits.displayWindows.map { window in
            AgentRateLimitWindow(
                id: window.kind == .fiveHour ? "five-hour" : (window.kind == .sevenDay ? "seven-day" : "other"),
                kind: window.kind == .fiveHour ? .fiveHour : (window.kind == .sevenDay ? .sevenDay : .other),
                usedPercent: window.usedPercent.isFinite ? window.usedPercent : nil,
                isUnlimited: window.kind == .fiveHour && (window.creditsUnlimited == true || usage.rateLimits.creditsUnlimited == true),
                resetsAt: window.resetsAt
            )
        }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: usage.providerCapturedAt)) ?? usage.providerCapturedAt
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let sevenDayTokens = usage.dailyUsage.map { buckets in
            buckets.reduce(Int64(0)) { total, bucket in
                guard let day = formatter.date(from: bucket.startDate), day >= cutoff else { return total }
                return total + bucket.tokens
            }
        }
        return AgentUsageChannel(
            id: .account,
            sourceTier: .officialLocalService,
            sourceVersion: "app-server",
            scopes: [.account],
            provenance: .providerReported,
            freshness: freshness,
            capturedAt: usage.providerCapturedAt,
            coverageNote: nil,
            rateLimitWindows: windows,
            accountMetrics: AgentAccountMetrics(
                planLabel: usage.rateLimits.planType,
                availableResets: usage.availableResetCount,
                lifetimeTokens: usage.lifetimeTokens,
                sevenDayTokens: sevenDayTokens
            ),
            localActivityMetrics: nil,
            safeFailure: safeFailure
        )
    }

    private static func localChannel(
        from activity: CodexLocalActivitySnapshot,
        freshness: AgentConnectorFreshness
    ) -> AgentUsageChannel {
        let availability = activity.availability == .available
        let estimate = activity.apiEquivalentCost
        let observed = estimate?.observedTokens ?? 0
        let coverage = observed > 0 ? Int((Double(estimate?.pricedTokens ?? 0) / Double(observed) * 100).rounded()) : nil
        return AgentUsageChannel(
            id: .localActivity,
            sourceTier: .officialCLIOrMetadata,
            sourceVersion: "metadata-tail-v1",
            scopes: [.device, .session, .task],
            provenance: .locallyEstimated,
            freshness: availability ? freshness : .unavailable,
            capturedAt: activity.capturedAt,
            coverageNote: availability ? "aggregate metadata coverage" : nil,
            rateLimitWindows: [],
            accountMetrics: nil,
            localActivityMetrics: AgentLocalActivityMetrics(
                recentTaskCount: availability ? activity.tasks.count : nil,
                recentTaskTokens: availability ? activity.tasks.map(\.totalTokens) : [],
                recentTaskCapturedAt: availability ? activity.tasks.map(\.modifiedAt) : [],
                sessionTokens: availability ? activity.tasks.reduce(0) { $0 + $1.totalTokens } : nil,
                estimatedSevenDayUSD: estimate?.sevenDayUSD,
                estimatedLifetimeUSD: estimate?.lifetimeUSD,
                coveragePercent: coverage,
                recognizedModelCount: estimate?.modelNames.count
            ),
            safeFailure: nil
        )
    }

    private static func normalizedState(_ state: CodexConnectionState) -> AgentConnectorState {
        switch state {
        case .notAuthorizedByMonitor, .idle: .inactive
        case .authorizationRequired, .officialCodexSignInRequired: .authenticationRequired
        case .ready: .ready
        case .staleWithPreviousRealData: .stale
        case .recoverableFailure, .blockedFailure: .failed
        default: .waitingForFirstResponse
        }
    }

    private static func safeFailure(from error: Error) -> AgentSafeFailure {
        guard let failure = (error as? CodexUsageClientError)?.failure else { return .unknown }
        switch failure {
        case .accountAuthorizationRequired, .accountAuthorizationCanceled, .accountAuthorizationFailed:
            return .authorizationRequired
        case .processExited: return .processExited
        case .initializationTimedOut, .accountCheckTimedOut, .requestTimedOut: return .timedOut
        case .protocolIncompatible: return .unsupported
        case .malformedResponse: return .malformedResponse
        case .codexApplicationNotFound, .codexExecutableNotFound, .codexExecutableNotExecutable:
            return .unavailable
        default: return .unknown
        }
    }
}
