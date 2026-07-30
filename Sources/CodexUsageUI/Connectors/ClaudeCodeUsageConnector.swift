import ClaudeStatusLineCore
import Foundation

enum ClaudeConnectorLifecycleState: String, Equatable, Sendable {
    case notInstalled
    case installedWaiting
    case fresh
    case stale
    case unsupported
    case failed
    case repairRequired
}

actor ClaudeCodeUsageConnector: AgentUsageConnector {
    static let connectorID = AgentConnectorID(
        rawValue: "claude.statusLine"
    )!
    static let freshnessInterval: TimeInterval = 5 * 60
    private static let capabilities: Set<AgentConnectorCapability> = [
        .connect,
        .reconnect,
        .refresh,
        .disconnect,
        .rateLimits,
        .passiveLocalAvailability,
        .hiddenFromDesktopAssistant,
    ]

    nonisolated let id = connectorID
    nonisolated let descriptor = AgentConnectorDescriptor(
        id: connectorID,
        providerName: "Claude Code",
        officialSource: "Official local status line",
        sourceTier: .officialStructuredHook,
        sourceVersion: "1",
        supportedScopes: [.account],
        capabilities: capabilities,
        configurationRequirements: [
            .officialManagedSession,
            .privacySafeLocalMetadataAccess,
        ],
        privacyAllowlist: [
            "schemaVersion",
            "claudeVersion",
            "fiveHourUsedPercentage",
            "fiveHourResetEpoch",
            "sevenDayUsedPercentage",
            "sevenDayResetEpoch",
            "observedAt",
        ],
        supportsRestore: false,
        supportsUninstall: true,
        unsupportedFields: [
            "sessionID",
            "sessionName",
            "promptID",
            "transcriptPath",
            "workspacePath",
            "repository",
            "accountIdentity",
            "prompt",
            "response",
            "task",
            "toolData",
            "rawJSON",
            "credentials",
            "tokens",
        ],
        expectedRuntime: .none,
        localSourceClass: .admittedStructuredLocal,
        authenticationMethod: .officialApplicationOwnedSession,
        usageReadContract: .currentStructuredLocalRead,
        loginAssistance: .none
    )!

    typealias ConfigurationCheck =
        @Sendable () async -> ClaudeStatusLineConfigurationCheck

    private let server: ClaudeStatusLineSocketServer
    private let configurationCheck: ConfigurationCheck
    private let now: @Sendable () -> Date
    private var snapshot: AgentUsageSnapshot
    private var lifecycle: ClaudeConnectorLifecycleState = .notInstalled
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var listenerStarted = false
    private var acceptedPacketCount = 0
    private var rejectedPacketCount = 0
    private var configurationRefreshTask:
        Task<ClaudeStatusLineConfigurationCheck, Never>?

    init(
        socketURL: URL = ClaudeStatusLineSocketPaths.socketURL(),
        configurationCheck: @escaping ConfigurationCheck,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        server = ClaudeStatusLineSocketServer(socketURL: socketURL)
        self.configurationCheck = configurationCheck
        self.now = now
        snapshot = Self.unavailableSnapshot(
            state: .inactive,
            failure: .unavailable,
            capturedAt: now()
        )
    }

    static func production() -> ClaudeCodeUsageConnector {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let applicationSupport = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(
                "Application Support",
                isDirectory: true
            )
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(
                "ClaudeStatusLineRelay",
                isDirectory: false
            )
        let command = "'"
            + helper.path.replacingOccurrences(
                of: "'",
                with: "'\"'\"'"
            )
            + "'"
        let manager = ClaudeStatusLineConfigurationManager(
            paths: ClaudeStatusLineConfigurationPaths(
                homeDirectory: home,
                applicationSupportDirectory: applicationSupport
            ),
            relayCommand: command
        )
        return ClaudeCodeUsageConnector(
            configurationCheck: {
                manager.check()
            }
        )
    }

    func permitsRead(for trigger: ProviderEligibilityScanTrigger) async -> Bool {
        _ = trigger
        return true
    }

    func probe() async -> AgentConnectorProbe {
        await refreshConfigurationState()
        return AgentConnectorProbe(
            state: snapshot.state,
            safeFailure: snapshot.safeFailure
        )
    }

    func start() async {
        guard !listenerStarted else { return }
        do {
            try server.start { [weak self] packet in
                await self?.receive(packet)
            } invalidHandler: { [weak self] in
                await self?.receiveInvalidPacket()
            }
            listenerStarted = true
            if lifecycle == .notInstalled {
                await refreshConfigurationState()
            }
        } catch {
            lifecycle = .failed
            replace(
                Self.unavailableSnapshot(
                    state: .failed,
                    failure: .unavailable,
                    capturedAt: now()
                )
            )
        }
    }

    func refresh() async {
        await refreshConfigurationState()
    }

    func refresh(trigger: CodexRefreshTrigger) async {
        _ = trigger
        await refreshConfigurationState()
    }

    func perform(_ command: AgentConnectorCommand) async {
        switch command {
        case .connect, .reconnect:
            await start()
            await refreshConfigurationState()
        case .refresh:
            await refreshConfigurationState()
        case .disconnect:
            await stop()
        }
    }

    func stop() async {
        server.stop()
        listenerStarted = false
        lifecycle = .notInstalled
        replace(
            Self.unavailableSnapshot(
                state: .inactive,
                failure: .unavailable,
                capturedAt: now()
            )
        )
    }

    func currentSnapshot() async -> AgentUsageSnapshot {
        ageSnapshotIfNeeded()
        return snapshot
    }

    func snapshots() async -> AsyncStream<AgentUsageSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation() }
            }
        }
    }

    func lifecycleState() -> ClaudeConnectorLifecycleState {
        ageSnapshotIfNeeded()
        return lifecycle
    }

    func diagnostics() -> (
        listenerCount: Int,
        acceptedPackets: Int,
        rejectedPackets: Int,
        supportsRestore: Bool
    ) {
        (
            listenerStarted ? 1 : 0,
            acceptedPacketCount,
            rejectedPacketCount,
            descriptor.supportsRestore
        )
    }

    func receiveEncodedPacket(_ data: Data) async {
        do {
            try await receive(
                ClaudeStatusLinePacket.decodePacket(data)
            )
        } catch {
            receiveInvalidPacket()
        }
    }

    private func receiveInvalidPacket() {
        rejectedPacketCount += 1
        lifecycle = .failed
        replace(
            Self.unavailableSnapshot(
                state: .failed,
                failure: .malformedResponse,
                capturedAt: now()
            )
        )
    }

    private func receive(_ packet: ClaudeStatusLinePacket) async {
        let current = now()
        guard packet.observedAt <= current.addingTimeInterval(5),
              current.timeIntervalSince(packet.observedAt)
                <= Self.freshnessInterval,
              packet.fiveHour != nil || packet.sevenDay != nil
        else {
            rejectedPacketCount += 1
            lifecycle = .failed
            replace(
                Self.unavailableSnapshot(
                    state: .failed,
                    failure: .malformedResponse,
                    capturedAt: current
                )
            )
            return
        }
        acceptedPacketCount += 1
        lifecycle = .fresh
        replace(Self.snapshot(for: packet))
    }

    private func refreshConfigurationState() async {
        let check = await coalescedConfigurationCheck()
        switch check.state {
        case .unconfigured:
            lifecycle = .notInstalled
            replace(Self.unavailableSnapshot(
                state: .inactive,
                failure: .unavailable,
                capturedAt: now()
            ))
        case .ready:
            lifecycle = .notInstalled
            replace(Self.unavailableSnapshot(
                state: .inactive,
                failure: .unavailable,
                capturedAt: now()
            ))
        case .installed:
            ageSnapshotIfNeeded()
            if snapshot.state != .ready && snapshot.state != .stale {
                lifecycle = .installedWaiting
                replace(Self.unavailableSnapshot(
                    state: .waitingForFirstResponse,
                    failure: nil,
                    capturedAt: now()
                ))
            }
        case .repairRequired:
            lifecycle = .repairRequired
            replace(Self.unavailableSnapshot(
                state: .failed,
                failure: .malformedResponse,
                capturedAt: now()
            ))
        case .unsupported:
            lifecycle = .unsupported
            replace(Self.unavailableSnapshot(
                state: .unsupported,
                failure: .unsupported,
                capturedAt: now()
            ))
        case .failed:
            lifecycle = .failed
            replace(Self.unavailableSnapshot(
                state: .failed,
                failure: .unavailable,
                capturedAt: now()
            ))
        }
    }

    private func coalescedConfigurationCheck()
    async -> ClaudeStatusLineConfigurationCheck {
        if let configurationRefreshTask {
            return await configurationRefreshTask.value
        }
        let configurationCheck = self.configurationCheck
        let task = Task {
            await configurationCheck()
        }
        configurationRefreshTask = task
        let result = await task.value
        configurationRefreshTask = nil
        return result
    }

    private func ageSnapshotIfNeeded() {
        guard snapshot.state == .ready,
              now().timeIntervalSince(snapshot.capturedAt)
                > Self.freshnessInterval
        else {
            return
        }
        lifecycle = .stale
        let staleChannels = snapshot.channels.map {
            AgentUsageChannel(
                id: $0.id,
                sourceTier: $0.sourceTier,
                sourceVersion: $0.sourceVersion,
                scopes: $0.scopes,
                provenance: $0.provenance,
                freshness: .stale,
                capturedAt: $0.capturedAt,
                coverageNote: $0.coverageNote,
                rateLimitWindows: $0.rateLimitWindows,
                accountMetrics: $0.accountMetrics,
                localActivityMetrics: nil,
                safeFailure: nil,
                availability: $0.availability
            )
        }
        replace(
            AgentUsageSnapshot(
                id: snapshot.id,
                providerName: snapshot.providerName,
                state: .stale,
                capturedAt: snapshot.capturedAt,
                lastSuccessfulAt: snapshot.lastSuccessfulAt,
                freshness: .stale,
                channels: staleChannels,
                capabilities: snapshot.capabilities,
                safeFailure: nil
            )
        )
    }

    private func replace(_ next: AgentUsageSnapshot) {
        guard snapshot != next else { return }
        snapshot = next
        continuation?.yield(next)
    }

    private func clearContinuation() {
        continuation = nil
    }

    private static func snapshot(
        for packet: ClaudeStatusLinePacket
    ) -> AgentUsageSnapshot {
        var windows: [AgentRateLimitWindow] = []
        if let fiveHour = packet.fiveHour {
            windows.append(
                AgentRateLimitWindow(
                    id: "claude-five-hour",
                    kind: .fiveHour,
                    usedPercent: fiveHour.usedPercentage,
                    isUnlimited: false,
                    resetsAt: Date(
                        timeIntervalSince1970:
                            TimeInterval(fiveHour.resetsAtEpochSeconds)
                    )
                )
            )
        }
        if let sevenDay = packet.sevenDay {
            windows.append(
                AgentRateLimitWindow(
                    id: "claude-seven-day",
                    kind: .sevenDay,
                    usedPercent: sevenDay.usedPercentage,
                    isUnlimited: false,
                    resetsAt: Date(
                        timeIntervalSince1970:
                            TimeInterval(sevenDay.resetsAtEpochSeconds)
                    )
                )
            )
        }
        let sourceVersion = packet.claudeVersion ?? "schema-1"
        let channel = AgentUsageChannel(
            id: .account,
            sourceTier: .officialStructuredHook,
            sourceVersion: sourceVersion,
            scopes: [.account],
            provenance: .providerReported,
            freshness: .fresh,
            capturedAt: packet.observedAt,
            coverageNote: "Official local status line",
            rateLimitWindows: windows,
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: nil
        )
        return AgentUsageSnapshot(
            id: connectorID,
            providerName: "Claude Code",
            state: .ready,
            capturedAt: packet.observedAt,
            lastSuccessfulAt: packet.observedAt,
            freshness: .fresh,
            channels: [channel],
            capabilities: capabilities,
            safeFailure: nil
        )
    }

    private static func unavailableSnapshot(
        state: AgentConnectorState,
        failure: AgentSafeFailure?,
        capturedAt: Date
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: connectorID,
            providerName: "Claude Code",
            state: state,
            capturedAt: capturedAt,
            lastSuccessfulAt: nil,
            freshness: state == .stale ? .stale : .unavailable,
            channels: [],
            capabilities: capabilities,
            safeFailure: failure
        )
    }
}
