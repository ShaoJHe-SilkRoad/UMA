import ClaudeStatusLineCore
import Foundation

enum ClaudeConnectorLifecycleState: String, Equatable, Sendable {
    case notInstalled
    case installedWaiting
    case fresh
    case cached
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
        .sanitizedLastValidRestore,
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
    private let snapshotStore: AgentConnectorSnapshotStore?
    private let now: @Sendable () -> Date
    private var snapshot: AgentUsageSnapshot
    private var lifecycle: ClaudeConnectorLifecycleState = .notInstalled
    private var continuation: AsyncStream<AgentUsageSnapshot>.Continuation?
    private var listenerStarted = false
    private var acceptedPacketCount = 0
    private var rejectedPacketCount = 0
    private var publishedSnapshotCount = 0
    private var restoredSnapshotCount = 0
    private var didAttemptCacheRestore = false
    private var configurationRefreshTask:
        Task<ClaudeStatusLineConfigurationCheck, Never>?

    init(
        socketURL: URL = ClaudeStatusLineSocketPaths.socketURL(),
        configurationCheck: @escaping ConfigurationCheck,
        snapshotStore: AgentConnectorSnapshotStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        server = ClaudeStatusLineSocketServer(socketURL: socketURL)
        self.configurationCheck = configurationCheck
        self.snapshotStore = snapshotStore
        self.now = now
        snapshot = Self.unavailableSnapshot(
            state: .inactive,
            failure: .unavailable,
            capturedAt: now()
        )
    }

    static func production(
        snapshotStore: AgentConnectorSnapshotStore = AgentConnectorSnapshotStore()
    ) -> ClaudeCodeUsageConnector {
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
            },
            snapshotStore: snapshotStore
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
        case .connect:
            await start()
            await refreshConfigurationState()
        case .reconnect:
            await invalidateSanitizedSnapshot()
            await start()
            await refreshConfigurationState()
        case .refresh:
            await refreshConfigurationState()
        case .disconnect:
            await invalidateSanitizedSnapshot()
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
        await refreshSnapshotStateIfNeeded()
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

    func lifecycleState() async -> ClaudeConnectorLifecycleState {
        await refreshSnapshotStateIfNeeded()
        return lifecycle
    }

    func diagnostics() -> (
        listenerCount: Int,
        acceptedPackets: Int,
        rejectedPackets: Int,
        publishedSnapshots: Int,
        restoredSnapshots: Int,
        supportsRestore: Bool
    ) {
        (
            listenerStarted ? 1 : 0,
            acceptedPacketCount,
            rejectedPacketCount,
            publishedSnapshotCount,
            restoredSnapshotCount,
            descriptor.supportsRestore
        )
    }

    func receiveEncodedPacket(_ data: Data) async {
        do {
            try await receive(
                ClaudeStatusLinePacket.decodePacket(data)
            )
        } catch {
            await receiveInvalidPacket()
        }
    }

    private func receiveInvalidPacket() async {
        rejectedPacketCount += 1
        await refreshSnapshotStateIfNeeded()
        guard snapshot.hasValidData else {
            lifecycle = .failed
            replace(
                Self.unavailableSnapshot(
                    state: .failed,
                    failure: .malformedResponse,
                    capturedAt: now()
                )
            )
            return
        }
        lifecycle = .failed
        replace(
            Self.withState(
                snapshot,
                state: .stale,
                freshness: .stale,
                failure: .malformedResponse
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
            await receiveInvalidPacket()
            return
        }
        let next = Self.snapshot(
            for: packet,
            now: current,
            previous: snapshot
        )
        guard next.hasValidData,
              next.channels.contains(where: {
                  !$0.rateLimitWindows.isEmpty
              })
        else {
            await receiveInvalidPacket()
            return
        }
        acceptedPacketCount += 1
        lifecycle = .fresh
        replace(next)
        if let snapshotStore,
           let record = Self.sanitizedRecord(from: next) {
            try? await snapshotStore.saveClaudeSanitizedSnapshot(
                record,
                now: current
            )
        }
    }

    private func refreshConfigurationState() async {
        let check = await coalescedConfigurationCheck()
        switch check.state {
        case .unconfigured:
            await invalidateSanitizedSnapshot()
            lifecycle = .notInstalled
            replace(Self.unavailableSnapshot(
                state: .inactive,
                failure: .unavailable,
                capturedAt: now()
            ))
        case .ready:
            await invalidateSanitizedSnapshot()
            lifecycle = .notInstalled
            replace(Self.unavailableSnapshot(
                state: .inactive,
                failure: .unavailable,
                capturedAt: now()
            ))
        case .installed:
            await restoreSanitizedSnapshotIfNeeded()
            await refreshSnapshotStateIfNeeded()
            if snapshot.state != .ready && snapshot.state != .stale {
                lifecycle = .installedWaiting
                replace(Self.unavailableSnapshot(
                    state: .waitingForFirstResponse,
                    failure: nil,
                    capturedAt: now()
                ))
            }
        case .repairRequired:
            await invalidateSanitizedSnapshot()
            lifecycle = .repairRequired
            replace(Self.unavailableSnapshot(
                state: .failed,
                failure: .malformedResponse,
                capturedAt: now()
            ))
        case .unsupported:
            await invalidateSanitizedSnapshot()
            lifecycle = .unsupported
            replace(Self.unavailableSnapshot(
                state: .unsupported,
                failure: .unsupported,
                capturedAt: now()
            ))
        case .failed:
            await invalidateSanitizedSnapshot()
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

    private func restoreSanitizedSnapshotIfNeeded() async {
        guard !didAttemptCacheRestore else { return }
        didAttemptCacheRestore = true
        guard let snapshotStore,
              let record = await snapshotStore.loadClaudeSanitizedSnapshot(
                now: now()
              )
        else {
            return
        }
        let freshness: AgentConnectorFreshness =
            now().timeIntervalSince(record.observationTimestamp)
                <= Self.freshnessInterval ? .cached : .stale
        lifecycle = freshness == .cached ? .cached : .stale
        restoredSnapshotCount += 1
        replace(Self.snapshot(for: record, freshness: freshness))
    }

    private func refreshSnapshotStateIfNeeded() async {
        guard snapshot.hasValidData else { return }
        let current = now()
        let survivingChannels = snapshot.channels.compactMap { channel -> AgentUsageChannel? in
            let windows = channel.rateLimitWindows.filter {
                guard let reset = $0.resetsAt else { return false }
                return reset > current
            }
            guard !windows.isEmpty else { return nil }
            return AgentUsageChannel(
                id: channel.id,
                sourceTier: channel.sourceTier,
                sourceVersion: channel.sourceVersion,
                scopes: channel.scopes,
                provenance: channel.provenance,
                freshness: channel.freshness,
                capturedAt: channel.capturedAt,
                coverageNote: channel.coverageNote,
                rateLimitWindows: windows,
                accountMetrics: channel.accountMetrics,
                localActivityMetrics: nil,
                safeFailure: channel.safeFailure,
                availability: channel.availability
            )
        }
        guard !survivingChannels.isEmpty else {
            try? await snapshotStore?.removeClaudeSanitizedSnapshot()
            lifecycle = .installedWaiting
            replace(Self.unavailableSnapshot(
                state: .waitingForFirstResponse,
                failure: nil,
                capturedAt: current
            ))
            return
        }

        let aged = current.timeIntervalSince(snapshot.capturedAt)
            > Self.freshnessInterval
        let nextFreshness: AgentConnectorFreshness
        if snapshot.freshness == .fresh && !aged {
            nextFreshness = .fresh
        } else if snapshot.freshness == .cached && !aged {
            nextFreshness = .cached
        } else {
            nextFreshness = .stale
        }
        let nextState: AgentConnectorState = nextFreshness == .stale
            ? .stale
            : .ready
        if lifecycle != .failed {
            lifecycle = switch nextFreshness {
            case .fresh: .fresh
            case .cached: .cached
            case .stale: .stale
            case .unavailable: .installedWaiting
            }
        }
        let next = AgentUsageSnapshot(
            id: snapshot.id,
            providerName: snapshot.providerName,
            state: nextState,
            capturedAt: snapshot.capturedAt,
            lastSuccessfulAt: snapshot.lastSuccessfulAt,
            freshness: nextFreshness,
            channels: survivingChannels.map {
                Self.channel($0, freshness: nextFreshness)
            },
            capabilities: snapshot.capabilities,
            safeFailure: snapshot.safeFailure,
            selectedWindowID: survivingChannels
                .flatMap(\.rateLimitWindows)
                .contains(where: { $0.id == snapshot.selectedWindowID })
                ? snapshot.selectedWindowID
                : nil
        )
        let windowsChanged = next.channels.flatMap(\.rateLimitWindows).count
            != snapshot.channels.flatMap(\.rateLimitWindows).count
        replace(next)
        if windowsChanged, let snapshotStore {
            if let record = Self.sanitizedRecord(from: next) {
                try? await snapshotStore.saveClaudeSanitizedSnapshot(
                    record,
                    now: current
                )
            } else {
                try? await snapshotStore.removeClaudeSanitizedSnapshot()
            }
        }
    }

    private func invalidateSanitizedSnapshot() async {
        try? await snapshotStore?.removeClaudeSanitizedSnapshot()
        didAttemptCacheRestore = true
    }

    private func replace(_ next: AgentUsageSnapshot) {
        guard snapshot != next else { return }
        snapshot = next
        publishedSnapshotCount += 1
        continuation?.yield(next)
    }

    private func clearContinuation() {
        continuation = nil
    }

    private static func snapshot(
        for packet: ClaudeStatusLinePacket,
        now: Date,
        previous: AgentUsageSnapshot
    ) -> AgentUsageSnapshot {
        var windows: [AgentRateLimitWindow] = []
        if let fiveHour = packet.fiveHour {
            let reset = Date(
                timeIntervalSince1970:
                    TimeInterval(fiveHour.resetsAtEpochSeconds)
            )
            if reset > now {
                windows.append(
                    AgentRateLimitWindow(
                        id: "claude-five-hour",
                        kind: .fiveHour,
                        usedPercent: fiveHour.usedPercentage,
                        isUnlimited: false,
                        resetsAt: reset
                    )
                )
            }
        }
        if let sevenDay = packet.sevenDay {
            let reset = Date(
                timeIntervalSince1970:
                    TimeInterval(sevenDay.resetsAtEpochSeconds)
            )
            if reset > now {
                windows.append(
                    AgentRateLimitWindow(
                        id: "claude-seven-day",
                        kind: .sevenDay,
                        usedPercent: sevenDay.usedPercentage,
                        isUnlimited: false,
                        resetsAt: reset
                    )
                )
            }
        }
        let sourceVersion = safeSourceVersion(packet.claudeVersion)
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
            safeFailure: nil,
            selectedWindowID: selectedWindowID(
                windows: windows,
                previous: previous,
                now: now
            )
        )
    }

    private static func snapshot(
        for record: AgentConnectorSnapshotStore.ClaudeSanitizedQuotaSnapshot,
        freshness: AgentConnectorFreshness
    ) -> AgentUsageSnapshot {
        var windows: [AgentRateLimitWindow] = []
        if let remaining = record.fiveHourRemainingPercent,
           let reset = record.fiveHourResetEpoch {
            windows.append(
                AgentRateLimitWindow(
                    id: "claude-five-hour",
                    kind: .fiveHour,
                    usedPercent: nil,
                    remainingPercent: remaining,
                    isUnlimited: false,
                    resetsAt: Date(timeIntervalSince1970: TimeInterval(reset))
                )
            )
        }
        if let remaining = record.sevenDayRemainingPercent,
           let reset = record.sevenDayResetEpoch {
            windows.append(
                AgentRateLimitWindow(
                    id: "claude-seven-day",
                    kind: .sevenDay,
                    usedPercent: nil,
                    remainingPercent: remaining,
                    isUnlimited: false,
                    resetsAt: Date(timeIntervalSince1970: TimeInterval(reset))
                )
            )
        }
        let channel = AgentUsageChannel(
            id: .account,
            sourceTier: .officialStructuredHook,
            sourceVersion: record.sourceVersion ?? "schema-1",
            scopes: [.account],
            provenance: .providerReported,
            freshness: freshness,
            capturedAt: record.observationTimestamp,
            coverageNote: "Official local status line",
            rateLimitWindows: windows,
            accountMetrics: nil,
            localActivityMetrics: nil,
            safeFailure: nil
        )
        return AgentUsageSnapshot(
            id: connectorID,
            providerName: "Claude Code",
            state: freshness == .stale ? .stale : .ready,
            capturedAt: record.observationTimestamp,
            lastSuccessfulAt: record.observationTimestamp,
            freshness: freshness,
            channels: [channel],
            capabilities: capabilities,
            safeFailure: nil,
            selectedWindowID: record.selectedWindowIdentifier
        )
    }

    private static func sanitizedRecord(
        from snapshot: AgentUsageSnapshot
    ) -> AgentConnectorSnapshotStore.ClaudeSanitizedQuotaSnapshot? {
        guard let channel = snapshot.channels.first(where: { $0.id == .account })
        else {
            return nil
        }
        let fiveHour = channel.rateLimitWindows.first(where: {
            $0.kind == .fiveHour
        })
        let sevenDay = channel.rateLimitWindows.first(where: {
            $0.kind == .sevenDay
        })
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return AgentConnectorSnapshotStore.ClaudeSanitizedQuotaSnapshot(
            fiveHourRemainingPercent: fiveHour?.normalizedRemainingPercent,
            fiveHourResetEpoch: fiveHour?.resetsAt.map {
                Int64($0.timeIntervalSince1970.rounded(.down))
            },
            sevenDayRemainingPercent: sevenDay?.normalizedRemainingPercent,
            sevenDayResetEpoch: sevenDay?.resetsAt.map {
                Int64($0.timeIntervalSince1970.rounded(.down))
            },
            selectedWindowIdentifier: snapshot.selectedWindowID,
            observationTimestamp: snapshot.capturedAt,
            sourceVersion: safeSourceVersion(channel.sourceVersion)
        )
    }

    private static func channel(
        _ channel: AgentUsageChannel,
        freshness: AgentConnectorFreshness,
        failure: AgentSafeFailure? = nil
    ) -> AgentUsageChannel {
        AgentUsageChannel(
            id: channel.id,
            sourceTier: channel.sourceTier,
            sourceVersion: channel.sourceVersion,
            scopes: channel.scopes,
            provenance: channel.provenance,
            freshness: freshness,
            capturedAt: channel.capturedAt,
            coverageNote: channel.coverageNote,
            rateLimitWindows: channel.rateLimitWindows,
            accountMetrics: channel.accountMetrics,
            localActivityMetrics: nil,
            safeFailure: failure,
            availability: channel.availability
        )
    }

    private static func withState(
        _ snapshot: AgentUsageSnapshot,
        state: AgentConnectorState,
        freshness: AgentConnectorFreshness,
        failure: AgentSafeFailure?
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            id: snapshot.id,
            providerName: snapshot.providerName,
            state: state,
            capturedAt: snapshot.capturedAt,
            lastSuccessfulAt: snapshot.lastSuccessfulAt,
            freshness: freshness,
            channels: snapshot.channels.map {
                channel($0, freshness: freshness, failure: failure)
            },
            capabilities: snapshot.capabilities,
            safeFailure: failure,
            selectedWindowID: snapshot.selectedWindowID
        )
    }

    private static func selectedWindowID(
        windows: [AgentRateLimitWindow],
        previous: AgentUsageSnapshot,
        now: Date
    ) -> String? {
        let eligible = windows.filter { $0.resetsAt.map { $0 > now } ?? false }
        let finite = eligible.compactMap {
            window -> (AgentRateLimitWindow, remaining: Double)? in
            guard let remaining = window.normalizedRemainingPercent else {
                return nil
            }
            return (window, remaining)
        }
        if let depleted = finite.filter({ $0.remaining == 0 })
            .sorted(by: selectionOrder).first {
            return depleted.0.id
        }
        if let critical = finite.filter({
            $0.remaining > 0 && $0.remaining <= 10
        }).sorted(by: {
            $0.remaining == $1.remaining
                ? selectionOrder($0, $1)
                : $0.remaining < $1.remaining
        }).first {
            return critical.0.id
        }

        let previousWindows = previous.channels
            .flatMap(\.rateLimitWindows)
        let previousByID = Dictionary(
            uniqueKeysWithValues: previousWindows.map {
                ($0.id, ($0.normalizedRemainingPercent, $0.resetsAt))
            }
        )
        let decrements = finite.compactMap {
            current -> (AgentRateLimitWindow, remaining: Double, decrement: Double)? in
            guard let old = previousByID[current.0.id],
                  old.1 == current.0.resetsAt,
                  let oldRemaining = old.0
            else {
                return nil
            }
            let decrement = max(0, oldRemaining - current.remaining)
            return decrement > 0 ? (current.0, current.remaining, decrement) : nil
        }
        if let winner = decrements.sorted(by: {
            if $0.decrement != $1.decrement {
                return $0.decrement > $1.decrement
            }
            if $0.remaining != $1.remaining {
                return $0.remaining < $1.remaining
            }
            return selectionOrder(
                ($0.0, $0.remaining),
                ($1.0, $1.remaining)
            )
        }).first {
            return winner.0.id
        }
        if let previousID = previous.selectedWindowID,
           finite.contains(where: { $0.0.id == previousID }) {
            return previousID
        }
        return finite.sorted(by: {
            $0.remaining == $1.remaining
                ? selectionOrder($0, $1)
                : $0.remaining < $1.remaining
        }).first?.0.id
    }

    private static func selectionOrder(
        _ lhs: (AgentRateLimitWindow, remaining: Double),
        _ rhs: (AgentRateLimitWindow, remaining: Double)
    ) -> Bool {
        func rank(_ kind: AgentRateLimitWindow.Kind) -> Int {
            switch kind {
            case .sevenDay: 0
            case .fiveHour: 1
            case .other: 2
            }
        }
        let lhsRank = rank(lhs.0.kind)
        let rhsRank = rank(rhs.0.kind)
        return lhsRank == rhsRank ? lhs.0.id < rhs.0.id : lhsRank < rhsRank
    }

    private static func safeSourceVersion(_ value: String?) -> String {
        guard let value,
              !value.isEmpty,
              value.count <= 32,
              value.range(
                of: "^[A-Za-z0-9 ._-]+$",
                options: .regularExpression
              ) != nil
        else {
            return "schema-1"
        }
        return value
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
