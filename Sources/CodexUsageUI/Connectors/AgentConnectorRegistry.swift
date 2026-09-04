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
    private struct PendingListener {
        let token: UUID
        let generation: UInt64
        let task: Task<AsyncStream<AgentUsageSnapshot>, Never>
    }
    private var pendingListeners: [AgentConnectorID: PendingListener] = [:]
    private var retiredListenerAcquisitions: [UUID: Task<AsyncStream<AgentUsageSnapshot>, Never>] = [:]
    private var listenerTokens: [AgentConnectorID: UUID] = [:]
    private var suspensionTask: Task<Void, Never>?
    private var suspensionTaskGeneration: UInt64?
    private var suspensionRequested = false
    private var lifecycleRequest: UInt64 = 0
    private let onResumeWaitingForStop: @Sendable () -> Void
    private let afterSuspensionWait: @Sendable () async -> Void
    private let onListenerReservationJoin: @Sendable () -> Void
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
    private var lifecycleGeneration: UInt64 = 0
    private var monitoringSuspended = false
    private var monitoringStopped = false

    private func acceptsPublication(_ generation: UInt64) -> Bool {
        generation == lifecycleGeneration && !monitoringSuspended && !monitoringStopped
    }

    private func acceptsWork(_ generation: UInt64) -> Bool {
        acceptsPublication(generation) && !Task.isCancelled
    }

    private func retainedAdmission(for trigger: ProviderEligibilityScanTrigger) -> ProviderSurfaceAdmissionSet {
        currentAdmissionSet ?? ProviderSurfaceAdmissionSet(
            trigger: trigger, scanGeneration: 0, records: []
        )
    }

    init(
        connectors initialConnectors: [any AgentUsageConnector] = [],
        snapshotStore: AgentConnectorSnapshotStore? = nil,
        eligibilityScanner: LocalProviderEligibilityScanner = LocalProviderEligibilityScanner(),
        onResumeWaitingForStop: @escaping @Sendable () -> Void = {},
        afterSuspensionWait: @escaping @Sendable () async -> Void = {},
        onListenerReservationJoin: @escaping @Sendable () -> Void = {}
    ) throws {
        self.snapshotStore = snapshotStore
        self.onResumeWaitingForStop = onResumeWaitingForStop
        self.afterSuspensionWait = afterSuspensionWait
        self.onListenerReservationJoin = onListenerReservationJoin
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
        let generation = lifecycleGeneration
        guard acceptsWork(generation) else { return retainedAdmission(for: trigger) }
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
        guard acceptsWork(generation) else { return retainedAdmission(for: trigger) }
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
            guard acceptsWork(generation) else { return retainedAdmission(for: trigger) }
            retainedDuringTransientScanIDs.insert(record.id)
        }
        guard acceptsWork(generation) else { return retainedAdmission(for: trigger) }
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
            guard acceptsWork(generation) else { return retainedAdmission(for: trigger) }
            guard let connector = connectors[id] else { continue }
            if lifecycleOwnedIDs.contains(id) {
                await listen(to: connector)
            } else if connector.descriptor.localSourceClass
                        == .browserCompanionUsage,
                      !excludedProviderIDs.contains(id),
                      await connector.permitsRead(for: trigger) {
                guard acceptsWork(generation) else { return retainedAdmission(for: trigger) }
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
        guard acceptsWork(generation) else { return retainedAdmission(for: trigger) }
        await persistCurrentAdmittedSnapshots()
        guard acceptsWork(generation) else { return retainedAdmission(for: trigger) }
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
        let generation = lifecycleGeneration
        guard acceptsWork(generation), let snapshotStore else { return }
        let restored = await snapshotStore.load()
        guard acceptsWork(generation) else { return }
        for snapshot in restored
        where connectors[snapshot.id]?.descriptor.supportsRestore == true {
            latest[snapshot.id] = snapshot
        }
        publish()
    }

    func startPassiveConnectors() async {
        let passive = orderedIDs.compactMap { connectors[$0] }.filter {
            $0.descriptor.capabilities.contains(.passiveLocalAvailability)
                && $0.descriptor.localSourceClass == .admittedStructuredLocal
        }
        await startRegistered(passive)
    }

    func startAll() async {
        await startRegistered(orderedIDs.compactMap { connectors[$0] })
    }

    private func startRegistered(_ registered: [any AgentUsageConnector]) async {
        let generation = lifecycleGeneration
        guard acceptsWork(generation) else { return }
        for connector in registered {
            await listen(to: connector)
            guard acceptsWork(generation) else { return }
            stoppedSnapshots[connector.id] = nil
        }
        await withTaskGroup(of: Void.self) { group in
            for connector in registered {
                group.addTask {
                    guard await self.acceptsWork(generation) else { return }
                    _ = await connector.probe()
                    guard await self.acceptsWork(generation) else { return }
                    await connector.start()
                    guard await self.acceptsWork(generation) else { return }
                    await self.receive(await connector.currentSnapshot(), generation: generation)
                }
            }
        }
    }

    func refresh(
        _ id: AgentConnectorID,
        trigger: CodexRefreshTrigger = .manual
    ) async throws {
        guard let connector = connectors[id] else { throw AgentConnectorRegistryError.unknownConnector(id) }
        let generation = lifecycleGeneration
        guard acceptsWork(generation) else { return }
        stoppedSnapshots[id] = nil
        await listen(to: connector)
        guard acceptsWork(generation) else { return }
        await connector.refresh(trigger: trigger)
        guard acceptsWork(generation) else { return }
        await receive(await connector.currentSnapshot(), generation: generation)
    }

    func perform(_ command: AgentConnectorCommand, for id: AgentConnectorID) async throws {
        guard let connector = connectors[id] else { throw AgentConnectorRegistryError.unknownConnector(id) }
        let generation = lifecycleGeneration
        guard acceptsWork(generation) else { return }
        if command == .disconnect { await eligibilityScanner.cancelOutstandingScan() }
        guard acceptsWork(generation) else { return }
        stoppedSnapshots[id] = nil
        await listen(to: connector)
        guard acceptsWork(generation) else { return }
        await connector.perform(command)
        guard acceptsWork(generation) else { return }
        let snapshot = await connector.currentSnapshot()
        guard acceptsWork(generation) else { return }
        if command == .disconnect {
            stoppedSnapshots[id] = snapshot
        }
        await receive(snapshot, generation: generation)
    }

    func stopAll() async {
        guard !monitoringStopped else { return }
        monitoringStopped = true
        lifecycleRequest &+= 1
        lifecycleGeneration &+= 1
        await eligibilityScanner.cancelOutstandingScan()
        // A stop already entered by suspension must settle before terminal
        // cleanup, so it cannot later overwrite a resumed or terminal session.
        await suspensionTask?.value
        // Stop every registered connector, including a consent-owned connector
        // that may have started a helper before it became surface-admitted and
        // therefore never acquired a snapshot listener.
        let registered = orderedIDs.compactMap { connectors[$0] }
        cancelListeners()
        for connector in registered { await stopIfNeeded(connector) }
        latest.removeAll()
        currentAdmissionSet = nil
        excludedProviderIDs.removeAll()
        publish()
    }

    /// Pauses connector work without erasing the last admitted, allowlisted
    /// publication. This is used only when the user explicitly disables
    /// monitoring after all application windows close.
    func suspendAllPreservingState() async {
        guard !monitoringStopped else { return }
        if !suspensionRequested {
            suspensionRequested = true
            lifecycleRequest &+= 1
        }
        if let suspensionTask {
            await suspensionTask.value
            return
        }
        guard !monitoringSuspended else { return }
        monitoringSuspended = true
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        // Reserve the transition before crossing to scanner/connector actors.
        let task = Task<Void, Never> { [weak self] in
            await self?.finishSuspension(generation: generation)
        }
        suspensionTask = task
        suspensionTaskGeneration = generation
        await task.value
        await afterSuspensionWait()
    }

    private func finishSuspension(generation: UInt64) async {
        // Clear the transition in its own actor turn before releasing waiters.
        // A resumed connector can otherwise be closed again while an already
        // completed task still occupies the suspension slot.
        defer {
            if suspensionTaskGeneration == generation {
                suspensionTask = nil
                suspensionTaskGeneration = nil
            }
        }
        await eligibilityScanner.cancelOutstandingScan()
        guard generation == lifecycleGeneration, !monitoringStopped else { return }
        cancelListeners()
        let registered = orderedIDs.compactMap { connectors[$0] }
        for connector in registered {
            guard generation == lifecycleGeneration, !monitoringStopped else { return }
            await stopIfNeeded(connector, expectedGeneration: generation)
        }
    }

    /// A reopen waits for the existing stop transition before starting a new
    /// session. A later close or shutdown supersedes this pending reopen.
    func resumeCurrentAdmissions() async {
        guard !monitoringStopped, monitoringSuspended else { return }
        if suspensionRequested {
            suspensionRequested = false
            lifecycleRequest &+= 1
        }
        let request = lifecycleRequest
        if let suspensionTask {
            onResumeWaitingForStop()
            await suspensionTask.value
        }
        guard !monitoringStopped, monitoringSuspended, !suspensionRequested,
              request == lifecycleRequest else { return }
        monitoringSuspended = false
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        let admittedIDs = Set(currentAdmissionSet?.admittedProviderIDs ?? [])
            .subtracting(excludedProviderIDs)
        for id in admittedIDs {
            guard acceptsWork(generation) else { return }
            guard let connector = connectors[id] else { continue }
            stoppedSnapshots[id] = nil
            await listen(to: connector)
            guard acceptsWork(generation) else { return }
            await connector.start()
        }
    }

    func orderedSnapshots() -> [AgentUsageSnapshot] {
        orderedIDs.compactMap { latest[$0] }
    }

    private func cancelListeners() {
        listeners.values.forEach { $0.cancel() }
        listeners.removeAll()
        listenerTokens.removeAll()
        for pending in pendingListeners.values {
            pending.task.cancel()
            retiredListenerAcquisitions[pending.token] = pending.task
        }
        pendingListeners.removeAll()
    }

    private func listen(to connector: any AgentUsageConnector) async {
        let id = connector.id
        let generation = lifecycleGeneration
        guard acceptsWork(generation), listeners[id] == nil else { return }
        if let pending = pendingListeners[id], pending.generation == generation {
            onListenerReservationJoin()
            _ = await pending.task.value
            return
        }
        // One reserved acquisition precedes snapshots(). Other same-generation
        // callers await that exact handshake, never create another stream.
        let token = UUID()
        let acquisition = Task { await connector.snapshots() }
        pendingListeners[id] = PendingListener(
            token: token, generation: generation, task: acquisition
        )
        let stream = await acquisition.value
        let ownsReservation = pendingListeners[id]?.token == token
        if ownsReservation { pendingListeners[id] = nil }
        retiredListenerAcquisitions[token] = nil
        guard ownsReservation, acceptsWork(generation), listeners[id] == nil else {
            // A suspended snapshots() may ignore cancellation and return a
            // stream late. Cancel its consumer to deliver onTermination.
            let discarded = Task { for await _ in stream { } }
            discarded.cancel()
            await discarded.value
            return
        }
        listenerTokens[id] = token
        listeners[id] = Task { [weak self] in
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                await self?.receive(snapshot, generation: generation)
            }
            await self?.finishListener(id: id, token: token)
        }
    }

    private func finishListener(id: AgentConnectorID, token: UUID) {
        guard listenerTokens[id] == token else { return }
        listenerTokens[id] = nil
        listeners[id] = nil
    }

    private func receive(_ snapshot: AgentUsageSnapshot, generation: UInt64) async {
        guard acceptsPublication(generation) else { return }
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
                guard acceptsPublication(generation) else { return }
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
                guard acceptsPublication(generation) else { return }
                await persistCurrentAdmittedSnapshots()
                guard acceptsPublication(generation) else { return }
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
        guard acceptsPublication(generation) else { return }
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
        observedSnapshot: AgentUsageSnapshot? = nil,
        expectedGeneration: UInt64? = nil
    ) async {
        let generation = expectedGeneration ?? lifecycleGeneration
        let before: AgentUsageSnapshot
        if let observedSnapshot {
            before = observedSnapshot
        } else {
            before = await connector.currentSnapshot()
        }
        guard generation == lifecycleGeneration,
              stoppedSnapshots[connector.id] != before else { return }
        await connector.stop()
        guard generation == lifecycleGeneration else { return }
        let stopped = await connector.currentSnapshot()
        guard generation == lifecycleGeneration else { return }
        stoppedSnapshots[connector.id] = stopped
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
