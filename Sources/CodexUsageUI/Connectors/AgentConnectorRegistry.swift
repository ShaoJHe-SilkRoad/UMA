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

    init(
        connectors initialConnectors: [any AgentUsageConnector] = [],
        snapshotStore: AgentConnectorSnapshotStore? = nil
    ) throws {
        self.snapshotStore = snapshotStore
        for connector in initialConnectors {
            let id = connector.id
            guard self.connectors[id] == nil else { throw AgentConnectorRegistryError.duplicateConnector(id) }
            self.connectors[id] = connector
            self.orderedIDs.append(id)
        }
        self.orderedIDs.sort()
    }

    func register(_ connector: any AgentUsageConnector) throws {
        let id = connector.id
        guard connectors[id] == nil else { throw AgentConnectorRegistryError.duplicateConnector(id) }
        connectors[id] = connector
        orderedIDs.append(id)
        orderedIDs.sort()
        listen(to: connector)
    }

    func orderedDescriptors() -> [AgentConnectorDescriptor] {
        orderedIDs.compactMap { connectors[$0]?.descriptor }
    }

    func snapshots() -> AsyncStream<[AgentUsageSnapshot]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(self.orderedSnapshots())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation() }
            }
        }
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

    func stopAll() async {
        let registered = orderedIDs.compactMap { connectors[$0] }
        listeners.values.forEach { $0.cancel() }
        listeners.removeAll()
        await withTaskGroup(of: Void.self) { group in
            for connector in registered { group.addTask { await connector.stop() } }
        }
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
        guard connectors[snapshot.id] != nil else { return }
        guard latest[snapshot.id] != snapshot else { return }
        latest[snapshot.id] = snapshot
        if let snapshotStore {
            let restorableSnapshots = orderedSnapshots().filter {
                connectors[$0.id]?.descriptor.supportsRestore == true
            }
            try? await snapshotStore.save(restorableSnapshots)
        }
        publish()
    }

    private func publish() { continuation?.yield(orderedSnapshots()) }
    private func clearContinuation() { continuation = nil }
}
