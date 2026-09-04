import Foundation

enum AgentConnectorRegistryError: Error, Equatable {
    case duplicateConnector(AgentConnectorID)
    case unknownConnector(AgentConnectorID)
}

/// One coherent registry revision. Consumers must never pair snapshots from
/// one revision with admission records from another.
struct AgentConnectorRegistryPublication: Equatable, Sendable {
    let revision: UInt64
    let snapshots: [AgentUsageSnapshot]
    let admissionSet: ProviderSurfaceAdmissionSet?
}

struct AgentConnectorRegistrySubscription: Sendable {
    fileprivate let id: UUID
    let updates: AsyncStream<AgentConnectorRegistryPublication>
}

actor AgentConnectorRegistry {
    private var connectors: [AgentConnectorID: any AgentUsageConnector] = [:]
    private var orderedIDs: [AgentConnectorID] = []
    private var listeners: [AgentConnectorID: Task<Void, Never>] = [:]
    private var latest: [AgentConnectorID: AgentUsageSnapshot] = [:]
    private var snapshotContinuations:
        [UUID: AsyncStream<[AgentUsageSnapshot]>.Continuation] = [:]
    private var publicationContinuations:
        [UUID: AsyncStream<AgentConnectorRegistryPublication>.Continuation] = [:]
    private var publicationRevision: UInt64 = 0
    private let snapshotStore: AgentConnectorSnapshotStore?
    private let eligibilityScanner: LocalProviderEligibilityScanner
    private var currentAdmissionSet: ProviderSurfaceAdmissionSet?
    private var excludedProviderIDs: Set<AgentConnectorID> = []
    private var stoppedSnapshots: [AgentConnectorID: AgentUsageSnapshot] = [:]

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

    func snapshots() -> AsyncStream<[AgentUsageSnapshot]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let subscriptionID = UUID()
            self.snapshotContinuations[subscriptionID] = continuation
            continuation.yield(self.orderedSnapshots())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSnapshotContinuation(subscriptionID) }
            }
        }
    }

    /// The transaction-safe publication boundary used by `UsageStore`.
    /// Every subscriber receives an immediate replay and owns an independent
    /// newest-value buffer.
    func subscribe() -> AgentConnectorRegistrySubscription {
        let subscriptionID = UUID()
        let updates = AsyncStream(
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation in
            self.publicationContinuations[subscriptionID] = continuation
            continuation.yield(self.currentPublication())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removePublicationContinuation(subscriptionID) }
            }
        }
        return AgentConnectorRegistrySubscription(
            id: subscriptionID,
            updates: updates
        )
    }

    func publications() -> AsyncStream<AgentConnectorRegistryPublication> {
        subscribe().updates
    }

    func detach(_ subscription: AgentConnectorRegistrySubscription) {
        guard let continuation = publicationContinuations.removeValue(
            forKey: subscription.id
        ) else { return }
        continuation.finish()
    }

    func publicationObserverCount() -> Int {
        publicationContinuations.count
    }

    func latestPublication() -> AgentConnectorRegistryPublication {
        currentPublication()
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
        self.excludedProviderIDs = excludedProviderIDs

        let admittedIDs = Set(result.admittedProviderIDs)
        var retainedDuringTransientScanIDs: Set<AgentConnectorID> = []
        for record in result.records where record.admission == .hiddenCurrentReadFailed {
            guard !excludedProviderIDs.contains(record.id),
                  let retained = latest[record.id],
                  let connector = connectors[record.id],
                  (await connector.currentSnapshot()).state == .waitingForFirstResponse,
                  LocalProviderEligibilityScanner.admission(
                      for: retained,
                      descriptor: connector.descriptor
                  ).admittedSnapshot != nil
            else { continue }
            retainedDuringTransientScanIDs.insert(record.id)
        }
        let lifecycleOwnedIDs = admittedIDs.union(retainedDuringTransientScanIDs)
        for id in admittedIDs { stoppedSnapshots[id] = nil }
        let previouslyAdmittedIDs = Set(latest.keys)
        let hiddenListenerIDs = listeners.keys.filter {
            !lifecycleOwnedIDs.contains($0)
                && connectors[$0]?.descriptor.capabilities.contains(
                    .passiveLocalAvailability
                ) != true
                && connectors[$0]?.descriptor.localSourceClass
                    != .browserCompanionUsage
        }
        for id in hiddenListenerIDs {
            listeners[id]?.cancel()
            listeners[id] = nil
        }
        var nextLatest = Dictionary(
            uniqueKeysWithValues: result.admittedSnapshots.map { ($0.id, $0) }
        )
        for id in retainedDuringTransientScanIDs { nextLatest[id] = latest[id] }
        latest = nextLatest
        currentAdmissionSet = result

        for id in orderedIDs {
            guard let connector = connectors[id] else { continue }
            if lifecycleOwnedIDs.contains(id) {
                await listen(to: connector)
            } else if connector.descriptor.localSourceClass
                        == .browserCompanionUsage,
                      !excludedProviderIDs.contains(id),
                      await connector.permitsRead(for: trigger) {
                // Browser-companion reads are completed by a later explicit
                // toolbar gesture. Keep the consent-owned listener alive while
                // the provider remains hidden awaiting that first current read.
                stoppedSnapshots[id] = nil
                await listen(to: connector)
            } else if connector.descriptor.hasSurfaceAdmissibleReadContract,
                      !excludedProviderIDs.contains(id)
                        || previouslyAdmittedIDs.contains(id),
                      !connector.descriptor.capabilities.contains(
                        .passiveLocalAvailability
                      ) {
                await stopIfNeeded(connector)
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
        for connector in passive { await listen(to: connector) }
        for connector in passive { stoppedSnapshots[connector.id] = nil }
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
        for connector in registered { await listen(to: connector) }
        for connector in registered { stoppedSnapshots[connector.id] = nil }
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
        stoppedSnapshots[id] = nil
        await listen(to: connector)
        await connector.refresh(trigger: trigger)
        await receive(await connector.currentSnapshot())
    }

    func perform(_ command: AgentConnectorCommand, for id: AgentConnectorID) async throws {
        guard let connector = connectors[id] else { throw AgentConnectorRegistryError.unknownConnector(id) }
        stoppedSnapshots[id] = nil
        await listen(to: connector)
        await connector.perform(command)
        let snapshot = await connector.currentSnapshot()
        if command == .disconnect {
            stoppedSnapshots[id] = snapshot
        }
        await receive(snapshot)
    }

    func stopAll() async {
        // Stop every registered connector, including a consent-owned connector
        // that may have started a helper before it became surface-admitted and
        // therefore never acquired a snapshot listener.
        let registered = orderedIDs.compactMap { connectors[$0] }
        listeners.values.forEach { $0.cancel() }
        listeners.removeAll()
        for connector in registered { await stopIfNeeded(connector) }
        latest.removeAll()
        currentAdmissionSet = nil
        excludedProviderIDs.removeAll()
        publish()
    }

    func orderedSnapshots() -> [AgentUsageSnapshot] {
        orderedIDs.compactMap { latest[$0] }
    }

    private func listen(to connector: any AgentUsageConnector) async {
        let id = connector.id
        guard listeners[id] == nil else { return }
        // Establish the connector-side continuation before returning. The first
        // browser callback can arrive immediately after an admission scan, so a
        // fire-and-forget stream subscription could otherwise lose that one
        // current observation and keep the provider hidden.
        let stream = await connector.snapshots()
        listeners[id] = Task { [weak self] in
            for await snapshot in stream {
                guard !Task.isCancelled else { return }
                await self?.receive(snapshot)
            }
        }
    }

    private func receive(_ snapshot: AgentUsageSnapshot) async {
        guard let connector = connectors[snapshot.id] else { return }
        guard !excludedProviderIDs.contains(snapshot.id) else {
            latest[snapshot.id] = nil
            publish()
            return
        }
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
                let isPassive = connector.descriptor.capabilities.contains(
                    .passiveLocalAvailability
                )
                let browserReadPermitted = await connector.permitsRead(
                    for: currentAdmissionSet.trigger
                )
                let retainsConsentOwnedBrowserListener =
                    connector.descriptor.localSourceClass == .browserCompanionUsage
                    && browserReadPermitted
                if !isPassive && !retainsConsentOwnedBrowserListener {
                    listeners[snapshot.id]?.cancel()
                    listeners[snapshot.id] = nil
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
                            loginOption: LocalProviderEligibilityScanner.loginOption(
                                for: connector.descriptor,
                                admission: admission
                            )
                        )
                    }
                )
                if snapshot.state != .inactive,
                   !isPassive,
                   !retainsConsentOwnedBrowserListener {
                    await stopIfNeeded(connector, observedSnapshot: snapshot)
                }
                // The connector stream is an authoritative current-state
                // boundary. Persist the withdrawal in the same transaction as
                // its in-memory publication so a relaunch cannot resurrect a
                // snapshot that the live connector has already invalidated.
                await persistCurrentAdmittedSnapshots()
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
            stoppedSnapshots[snapshot.id] = nil
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
        try? await snapshotStore.replace(with: restorableSnapshots)
    }

    private func stopIfNeeded(
        _ connector: any AgentUsageConnector,
        observedSnapshot: AgentUsageSnapshot? = nil
    ) async {
        let before: AgentUsageSnapshot
        if let observedSnapshot {
            before = observedSnapshot
        } else {
            before = await connector.currentSnapshot()
        }
        guard stoppedSnapshots[connector.id] != before else { return }
        await connector.stop()
        stoppedSnapshots[connector.id] = await connector.currentSnapshot()
    }

    private func publish() {
        publicationRevision &+= 1
        let snapshots = orderedSnapshots()
        let publication = AgentConnectorRegistryPublication(
            revision: publicationRevision,
            snapshots: snapshots,
            admissionSet: currentAdmissionSet
        )
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshots)
        }
        for continuation in publicationContinuations.values {
            continuation.yield(publication)
        }
    }

    private func currentPublication() -> AgentConnectorRegistryPublication {
        AgentConnectorRegistryPublication(
            revision: publicationRevision,
            snapshots: orderedSnapshots(),
            admissionSet: currentAdmissionSet
        )
    }

    private func removeSnapshotContinuation(_ id: UUID) {
        snapshotContinuations[id] = nil
    }

    private func removePublicationContinuation(_ id: UUID) {
        publicationContinuations[id] = nil
    }
}
