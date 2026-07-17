import Foundation

/// Minimal surface required by the store.  It is deliberately injectable so
/// tests never need an installed Codex app or an account.
protocol CodexUsageClient: Sendable {
    /// Performs only the local service setup and credential-free
    /// `account/read` presence check. A false result must not read limits,
    /// usage, threads, or cost data.
    func checkLocalAccountAvailability() async throws -> Bool
    func fetchUsage() async throws -> CodexLiveUsage
    /// Uses the positive, same-session `account/read` result produced by
    /// `checkLocalAccountAvailability()` and must not issue a second account
    /// read. This keeps the provider sequence bounded to one account check.
    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage
    func disconnect() async
    func takeUsageRefreshRequest() async -> Bool
    func connectionState() async -> CodexConnectionState
}

extension CodexUsageClient {
    /// Compatibility default for legacy test doubles. Production supplies the
    /// account-only implementation above. This default deliberately performs
    /// no usage request, so a legacy double cannot consume or expose an extra
    /// usage result before the store's required post-account read. Focused
    /// reconciliation tests provide their own account result and never rely
    /// on this path.
    func checkLocalAccountAvailability() async throws -> Bool {
        return true
    }

    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage {
        try await fetchUsage()
    }
}

/// Owns one retained local app-server process and enforces the account-first
/// sequence. It never reads auth files or returns account identity data.
actor CodexAppServerClient: CodexUsageClient {
    private let resolver: any CodexExecutableResolving
    private let session: CodexAppServerSession
    private var executableURL: URL?
    private var hasVerifiedAccountInCurrentSession = false
    private var state: CodexConnectionState = .idle

    init(
        resolver: any CodexExecutableResolving = CodexExecutableResolver(),
        session: CodexAppServerSession = CodexAppServerSession()
    ) {
        self.resolver = resolver
        self.session = session
    }

    func connectionState() -> CodexConnectionState {
        return state
    }

    func disconnect() async {
        await session.shutdown()
        executableURL = nil
        hasVerifiedAccountInCurrentSession = false
        state = .idle
    }

    func takeUsageRefreshRequest() async -> Bool {
        await session.takeUsageRefreshRequest()
    }

    func checkLocalAccountAvailability() async throws -> Bool {
        do {
            try await prepareSession()
            let available = try await readAccountAvailability()
            hasVerifiedAccountInCurrentSession = available
            return available
        } catch {
            throw record(error)
        }
    }

    func fetchUsage() async throws -> CodexLiveUsage {
        try await fetchUsage(requiresFreshAccountRead: true)
    }

    func fetchUsageAfterVerifiedAccount() async throws -> CodexLiveUsage {
        try await fetchUsage(requiresFreshAccountRead: false)
    }

    private func fetchUsage(requiresFreshAccountRead: Bool) async throws -> CodexLiveUsage {
        do {
            try await prepareSession()
            if requiresFreshAccountRead {
                guard try await readAccountAvailability() else {
                    hasVerifiedAccountInCurrentSession = false
                    throw CodexUsageClientError(.accountAuthorizationRequired)
                }
                hasVerifiedAccountInCurrentSession = true
            } else if !hasVerifiedAccountInCurrentSession {
                throw CodexUsageClientError(.accountAuthorizationRequired)
            }

            state = .loadingRateLimits
            let rateLimitResponse: RateLimitsResult = try await session.requestWithExplicitNullParameters(
                method: "account/rateLimits/read"
            )
            let rateLimits = rateLimitResponse.snapshot

            state = .loadingUsage
            let accountUsage: AccountUsageResult = try await session.requestWithExplicitNullParameters(
                method: "account/usage/read"
            )
            let usage = CodexLiveUsage(
                rateLimits: rateLimits,
                availableResetCount: rateLimitResponse.rateLimitResetCredits?.availableCount,
                lifetimeTokens: accountUsage.summary.lifetimeTokens,
                dailyUsage: accountUsage.dailyUsageBuckets,
                recentActivityCount: 0,
                apiCostEstimate: nil
            )
            state = .ready
            hasVerifiedAccountInCurrentSession = true
            return usage
        } catch {
            hasVerifiedAccountInCurrentSession = false
            throw record(error)
        }
    }

    private func prepareSession() async throws {
        if executableURL == nil {
            state = .resolvingExecutable
            executableURL = try resolver.resolve()
        }
        guard let executableURL else {
            throw CodexUsageClientError(.codexExecutableNotFound)
        }
        state = .startingServer
        try await session.start(executableURL: executableURL)
        state = .initializing
        try await session.initializeIfNeeded()
    }

    /// Retains only an authorization decision.  `AccountReadResult` decodes an
    /// otherwise empty presence marker, so account names, emails, and IDs are
    /// never retained by this client.
    private func readAccountAvailability() async throws -> Bool {
        state = .checkingAccount
        let result: AccountReadResult
        do {
            result = try await session.request(
                method: "account/read",
                params: EmptyParameters(),
                timeout: 10,
                timeoutFailure: .accountCheckTimedOut
            )
        } catch let error as CodexUsageClientError where error.failure == .requestTimedOut(method: "account/read") {
            throw CodexUsageClientError(.accountCheckTimedOut)
        }

        guard result.isAccountAvailable else {
            state = .authorizationRequired
            return false
        }
        state = .accountAvailable
        return true
    }

    private func record(_ error: Error) -> CodexUsageClientError {
        let safeError = (error as? CodexUsageClientError) ?? CodexUsageClientError(.unknownSafeError)
        switch safeError.failure {
        case .accountAuthorizationRequired:
            state = .authorizationRequired
        case .accountAuthorizationCanceled, .accountAuthorizationFailed:
            state = .authorizationRequired
        default:
            state = safeError.failure.blocksConnection
                ? .blockedFailure(safeError.failure)
                : .recoverableFailure(safeError.failure)
        }
        return safeError
    }
}

struct CodexUsageClientError: LocalizedError, Sendable, Equatable {
    let failure: CodexUsageClientFailure
    /// Present only for a decoded JSON-RPC error.  This record contains no
    /// upstream message text or response payload; it is safe for the core to
    /// use when selecting a future UI action.
    let safeJSONRPCError: CodexSafeJSONRPCError?

    init(_ failure: CodexUsageClientFailure, safeJSONRPCError: CodexSafeJSONRPCError? = nil) {
        self.failure = failure
        self.safeJSONRPCError = safeJSONRPCError
    }

    var errorDescription: String? {
        description(language: .systemMatch())
    }

    func description(language: AppLanguage) -> String {
        switch failure {
        case .monitorConsentMissing:
            return language == .simplifiedChinese ? "请先允许应用连接本机 Codex" : "Allow the app to connect to local Codex first"
        case .codexApplicationNotFound, .codexExecutableNotFound:
            return language == .simplifiedChinese ? "未找到本机 Codex 应用" : "Local Codex app was not found"
        case .codexExecutableNotExecutable:
            return language == .simplifiedChinese ? "本机 Codex 无法运行" : "Local Codex executable cannot run"
        case .accountAuthorizationRequired:
            return language == .simplifiedChinese ? "需要 Codex 授权" : "Codex authorization is required"
        case .accountAuthorizationCanceled:
            return language == .simplifiedChinese ? "Codex 授权已取消" : "Codex authorization was canceled"
        case .accountAuthorizationFailed:
            return language == .simplifiedChinese ? "Codex 授权未完成" : "Codex authorization did not complete"
        case .initializationTimedOut, .accountCheckTimedOut, .requestTimedOut:
            return language == .simplifiedChinese ? "本机 Codex 响应超时" : "Local Codex did not respond in time"
        case .serverOverloaded:
            return language == .simplifiedChinese ? "本机 Codex 当前繁忙" : "Local Codex is currently busy"
        case .requiredDataMissing:
            return language == .simplifiedChinese ? "Codex 未返回所需用量数据" : "Codex did not return required usage data"
        case .optionalDataUnavailable:
            return language == .simplifiedChinese ? "可选活动数据暂不可用" : "Optional activity data is unavailable"
        default:
            return language == .simplifiedChinese ? "无法连接本机 Codex" : "Unable to connect to local Codex"
        }
    }
}

private struct EmptyParameters: Encodable {}

/// Decodes arbitrary response JSON while retaining none of it.  It is used by
/// login operations precisely to avoid leaking login IDs or authorization URLs
/// into the public model.
private struct AccountReadResult: Decodable {
    private let account: AccountPresence?
    private let requiresOpenaiAuth: Bool

    var isAccountAvailable: Bool {
        // The installed app-server reports requiresOpenaiAuth=true for an
        // authenticated ChatGPT account because the service itself requires
        // OpenAI authentication. Account presence, not that capability flag,
        // is the authorization result. The type is deliberately not exposed
        // beyond this private presence check.
        _ = requiresOpenaiAuth
        return account != nil
    }
}

private struct AccountPresence: Decodable {
    let type: String
}

private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitSnapshotResponse
    let rateLimitsByLimitId: [String: RateLimitSnapshotResponse]?
    let rateLimitResetCredits: ResetCreditsResponse?

    var snapshot: CodexRateLimitSnapshot {
        let identifiedSnapshots: [(String, RateLimitSnapshotResponse)]
        if let rateLimitsByLimitId, !rateLimitsByLimitId.isEmpty {
            identifiedSnapshots = rateLimitsByLimitId.map { ($0.key, $0.value) }
        } else {
            identifiedSnapshots = [(rateLimits.limitID ?? "default", rateLimits)]
        }

        let windows = identifiedSnapshots.flatMap { sourceID, snapshot in
            [
                snapshot.primary.map {
                    CodexRateLimitWindow(
                        id: "\(sourceID).primary",
                        sourceLimitID: sourceID,
                        serverLimitID: snapshot.limitID,
                        creditsUnlimited: snapshot.credits?.unlimited,
                        usedPercent: $0.usedPercent,
                        windowDurationMinutes: $0.windowDurationMinutes,
                        resetsAt: $0.resetsAt.map(Date.init(timeIntervalSince1970:))
                    )
                },
                snapshot.secondary.map {
                    CodexRateLimitWindow(
                        id: "\(sourceID).secondary",
                        sourceLimitID: sourceID,
                        serverLimitID: snapshot.limitID,
                        creditsUnlimited: snapshot.credits?.unlimited,
                        usedPercent: $0.usedPercent,
                        windowDurationMinutes: $0.windowDurationMinutes,
                        resetsAt: $0.resetsAt.map(Date.init(timeIntervalSince1970:))
                    )
                }
            ].compactMap { $0 }
        }.sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.id < $1.id
        }
        return CodexRateLimitSnapshot(
            planType: rateLimits.planType,
            windows: windows,
            sourceLimitIDs: identifiedSnapshots.map(\.0).sorted(),
            serverLimitID: rateLimits.limitID,
            creditsUnlimited: rateLimits.credits?.unlimited
        )
    }
}

private struct RateLimitSnapshotResponse: Decodable {
    let primary: RateLimitWindowResponse?
    let secondary: RateLimitWindowResponse?
    let planType: String?
    let limitID: String?
    let credits: CreditsSnapshot?

    private enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case planType
        case limitID = "limitId"
        case credits
    }
}

private struct CreditsSnapshot: Decodable {
    let unlimited: Bool
}

private struct RateLimitWindowResponse: Decodable {
    let usedPercent: Double
    let windowDurationMinutes: Int?
    let resetsAt: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMins
        case windowDurationMinutes
        case resetsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        windowDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .windowDurationMinutes)
            ?? container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
        resetsAt = try container.decodeIfPresent(TimeInterval.self, forKey: .resetsAt)
    }
}

private struct ResetCreditsResponse: Decodable {
    let availableCount: Int
}

private struct AccountUsageResult: Decodable {
    let summary: AccountUsageSummaryResponse
    let dailyUsageBuckets: [CodexDailyUsage]?
}

private struct AccountUsageSummaryResponse: Decodable {
    let lifetimeTokens: Int64?
}
