import Foundation

enum AgentConnectorRegistryError: Error, Equatable {
    case duplicateConnector(AgentConnectorID)
    case unknownConnector(AgentConnectorID)
}

actor AgentConnectorRegistry {
    private var connectors: [AgentConnectorID: any AgentUsageConnector] = [:]
    private var orderedIDs: [AgentConnectorID] = []
    private var listeners: [AgentConnectorID: Task<Void, Never>] = [:]
    private var latest: [AgentConnectorID: AgentUsageSnapshot] = [:]
    private var continuation: AsyncStream<[AgentUsageSnapshot]>.Continuation?
    private let snapshotStore: AgentConnectorSnapshotStore?
    private let eligibilityScanner: LocalProviderEligibilityScanner
    private var currentAdmissionSet: ProviderSurfaceAdmissionSet?

    init(
        connectors initialConnectors: [any AgentUsageConnector] = [],
        snapshotStore: AgentConnectorSnapshotStore? = nil,
        eligibilityScanner: LocalProviderEligibilityScanner = LocalProviderEligibilityScanner()
    ) throws {
        self.snapshotStore = snapshotStore
        self.eligibilityScanner = eligibilityScanner
        for connector in initialConnectors {
            let id = connector.id
            guard self.connectors[id] == nil else { throw AgentConnectorRegistryError.duplicateConnector(id) }
            self.connectors[id] = connector
            self.orderedIDs.append(id)
        }
        self.orderedIDs.sort(by: AgentProviderOrder.precedes)
    }

    func register(_ connector: any AgentUsageConnector) throws {
        let id = connector.id
        guard connectors[id] == nil else { throw AgentConnectorRegistryError.duplicateConnector(id) }
        connectors[id] = connector
        orderedIDs.append(id)
        orderedIDs.sort(by: AgentProviderOrder.precedes)
    }

    func orderedDescriptors() -> [AgentConnectorDescriptor] {
        orderedIDs.compactMap { connectors[$0]?.descriptor }
    }

    func hasConfiguredOfficialRemoteConnector() async -> Bool {
        for id in orderedIDs {
            guard let connector = connectors[id],
                  connector.descriptor.localSourceClass
                    == .officialRemoteUsageAPI else {
                continue
            }
            if await connector.permitsRead(for: .applicationLaunch) {
                return true
            }
        }
        return false
    }

    func snapshots() -> AsyncStream<[AgentUsageSnapshot]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation() }
            }
        }
    }

    /// Runs the one launch/manual eligibility scan and atomically replaces the
    /// visible provider set. Persisted snapshots never enter this path.
    func scanSurfaceAdmissions(
        trigger: ProviderEligibilityScanTrigger,
        excludedProviderIDs: Set<AgentConnectorID> = []
    ) async -> ProviderSurfaceAdmissionSet {
        let candidates = orderedIDs.compactMap { id -> RegisteredProviderCandidate? in
            guard let connector = connectors[id] else { return nil }
            return RegisteredProviderCandidate(
                connector: connector,
                descriptor: connector.descriptor
            )
        }
        let result = await eligibilityScanner.scan(
            candidates: candidates,
            excludedProviderIDs: excludedProviderIDs,
            trigger: trigger
        )

        let admittedIDs = Set(result.admittedProviderIDs)
        let hiddenListenerIDs = listeners.keys.filter {
            !admittedIDs.contains($0)
        }
        for id in hiddenListenerIDs {
            listeners[id]?.cancel()
            listeners[id] = nil
        }
        latest = Dictionary(
            uniqueKeysWithValues: result.admittedSnapshots.map { ($0.id, $0) }
        )
        currentAdmissionSet = result

        for id in orderedIDs {
            guard let connector = connectors[id] else { continue }
            if admittedIDs.contains(id) {
                listen(to: connector)
            } else if connector.descriptor.hasSurfaceAdmissibleReadContract {
                if excludedProviderIDs.contains(id)
                    || connector.descriptor.localSourceClass
                        != .officialRemoteUsageAPI {
                    await connector.stop()
                }
            }
        }
        await persistCurrentAdmittedSnapshots()
        publish()
        return result
    }

    func surfaceAdmissionSet() -> ProviderSurfaceAdmissionSet? {
        currentAdmissionSet
    }

    func scannerDiagnostics() async -> LocalProviderEligibilityScannerDiagnostics {
        await eligibilityScanner.diagnostics()
    }

    func restorePersistedSnapshots() async {
        guard let snapshotStore else { return }
        let restored = await snapshotStore.load()
        for snapshot in restored
        where connectors[snapshot.id]?.descriptor.supportsRestore == true {
            latest[snapshot.id] = snapshot
        }
        publish()
    }

    func startPassiveConnectors() async {
        let passive = orderedIDs.compactMap { connectors[$0] }.filter {
            $0.descriptor.capabilities.contains(.passiveLocalAvailability)
                && $0.descriptor.localSourceClass
                    == .admittedStructuredLocal
        }
        for connector in passive { listen(to: connector) }
        await withTaskGroup(of: Void.self) { group in
            for connector in passive {
                group.addTask {
                    _ = await connector.probe()
                    await connector.start()
                    await self.receive(await connector.currentSnapshot())
                }
            }
        }
    }

    func startAll() async {
        let registered = orderedIDs.compactMap { connectors[$0] }
        for connector in registered { listen(to: connector) }
        await withTaskGroup(of: Void.self) { group in
            for connector in registered {
                group.addTask {
                    _ = await connector.probe()
                    await connector.start()
                    await self.receive(await connector.currentSnapshot())
                }
            }
        }
    }

    func refresh(
        _ id: AgentConnectorID,
        trigger: CodexRefreshTrigger = .manual
    ) async throws {
        guard let connector = connectors[id] else { throw AgentConnectorRegistryError.unknownConnector(id) }
        listen(to: connector)
        await connector.refresh(trigger: trigger)
        await receive(await connector.currentSnapshot())
    }

    func perform(_ command: AgentConnectorCommand, for id: AgentConnectorID) async throws {
        guard let connector = connectors[id] else { throw AgentConnectorRegistryError.unknownConnector(id) }
        listen(to: connector)
        await connector.perform(command)
        await receive(await connector.currentSnapshot())
    }

    func stopConnectors(_ ids: Set<AgentConnectorID>) async {
        let selected = ids.compactMap { connectors[$0] }
        for id in ids {
            listeners[id]?.cancel()
            listeners[id] = nil
            latest[id] = nil
        }
        await withTaskGroup(of: Void.self) { group in
            for connector in selected {
                group.addTask { await connector.stop() }
            }
        }
        await persistCurrentAdmittedSnapshots()
        publish()
    }

    func stopAll() async {
        let registered = listeners.keys.compactMap { connectors[$0] }
        listeners.values.forEach { $0.cancel() }
        listeners.removeAll()
        await withTaskGroup(of: Void.self) { group in
            for connector in registered { group.addTask { await connector.stop() } }
        }
        latest.removeAll()
        currentAdmissionSet = nil
        publish()
    }

    func orderedSnapshots() -> [AgentUsageSnapshot] {
        orderedIDs.compactMap { latest[$0] }
    }

    private func listen(to connector: any AgentUsageConnector) {
        let id = connector.id
        guard listeners[id] == nil else { return }
        listeners[id] = Task { [weak self] in
            let stream = await connector.snapshots()
            for await snapshot in stream {
                guard !Task.isCancelled else { return }
                await self?.receive(snapshot)
            }
        }
    }

    private func receive(_ snapshot: AgentUsageSnapshot) async {
        guard let connector = connectors[snapshot.id] else { return }
        guard connector.descriptor.hasSurfaceAdmissibleReadContract else {
            latest[snapshot.id] = nil
            return
        }
        guard let currentAdmissionSet else {
            // Connector lifecycle and restore helpers cannot surface-admit a
            // provider. Only a completed eligibility scan can establish the
            // current admission set.
            return
        }
        do {
            // A current read publishes this transient state before its one
            // completed result. It is not a failed admission and must not
            // terminate the connector that owns the in-flight read.
            if snapshot.state == .waitingForFirstResponse { return }
            let admission = LocalProviderEligibilityScanner.admission(
                for: snapshot,
                descriptor: connector.descriptor
            )
            guard case .admitted = admission else {
                latest[snapshot.id] = nil
                listeners[snapshot.id]?.cancel()
                listeners[snapshot.id] = nil
                self.currentAdmissionSet = ProviderSurfaceAdmissionSet(
                    trigger: currentAdmissionSet.trigger,
                    scanGeneration: currentAdmissionSet.scanGeneration,
                    records: currentAdmissionSet.records.map { record in
                        guard record.id == snapshot.id else { return record }
                        return ProviderSurfaceAdmissionRecord(
                            id: record.id,
                            providerName: record.providerName,
                            priority: record.priority,
                            admission: admission,
                            loginOption: LocalProviderEligibilityScanner.loginOption(
                                for: connector.descriptor,
                                admission: admission
                            )
                        )
                    }
                )
                if snapshot.state != .inactive,
                   connector.descriptor.localSourceClass
                    != .officialRemoteUsageAPI {
                    await connector.stop()
                }
                publish()
                return
            }
            self.currentAdmissionSet = ProviderSurfaceAdmissionSet(
                trigger: currentAdmissionSet.trigger,
                scanGeneration: currentAdmissionSet.scanGeneration,
                records: currentAdmissionSet.records.map { record in
                    guard record.id == snapshot.id else { return record }
                    return ProviderSurfaceAdmissionRecord(
                        id: record.id,
                        providerName: record.providerName,
                        priority: record.priority,
                        admission: admission,
                        loginOption: nil
                    )
                }
            )
        }
        guard latest[snapshot.id] != snapshot else { return }
        latest[snapshot.id] = snapshot
        await persistCurrentAdmittedSnapshots()
        publish()
    }

    private func persistCurrentAdmittedSnapshots() async {
        guard let snapshotStore else { return }
        let restorableSnapshots = orderedSnapshots().filter {
            connectors[$0.id]?.descriptor.supportsRestore == true
        }
        guard !restorableSnapshots.isEmpty else { return }
        try? await snapshotStore.save(restorableSnapshots)
    }

    private func publish() { continuation?.yield(orderedSnapshots()) }
    private func clearContinuation() { continuation = nil }
}
