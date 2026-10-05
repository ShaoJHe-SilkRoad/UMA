import Combine
import Foundation
import HESectoriumCore
import HESectoriumRuntime

public enum SectoriumInventoryState: Equatable {
    case loading, available, empty, unavailable, malformed
}

struct SectoriumIOSampleHistoryEntry: Equatable {
    let deviceID: String
    let counters: SectoriumDeviceIOCounters
    let uptime: TimeInterval
}

@MainActor
public final class HESectoriumStore: ObservableObject {
    @Published public private(set) var snapshot = HESectoriumRuntimeSnapshot(
        installed: .missing, automationEnabled: false, readiness: .unknown, pendingEject: nil,
        diagnostics: [], latestActionSummary: "Status has not been checked"
    )
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastResult = ""
    @Published public private(set) var workbench = SectoriumWorkbenchSnapshot()
    @Published public private(set) var inventoryState: SectoriumInventoryState = .loading
    @Published public private(set) var discoveredLegacyDisk = false
    @Published public private(set) var localSamplingConsentDeviceIDs: Set<String> = []
    @Published public private(set) var wholeDeviceEjectConfirmation: SectoriumWholeDeviceEjectConfirmation?
    @Published public private(set) var canBeginWholeDeviceEject = false
    @Published public private(set) var canContinueWholeDeviceEject = false
    @Published public private(set) var canReturnFromWholeDeviceEject = false
    @Published public private(set) var stopConfirmation: SectoriumStopConfirmation?

    private let service: HESectoriumService
    private let sampleIntervalNanoseconds: UInt64
    private var observationGeneration: UInt64 = 0
    private var workbenchIsActive = false
    private var workbenchIsSleeping = false
    private var sampleTask: Task<Void, Never>?
    private var activeSampleToken: UUID?
    /// Ephemeral, selected-device-only history. It is deliberately never persisted.
    private var ioHistory: [SectoriumIOSampleHistoryEntry] = []

    public init(service: HESectoriumService = .shared, sampleIntervalNanoseconds: UInt64 = 1_000_000_000) {
        self.service = service; self.sampleIntervalNanoseconds = max(1, sampleIntervalNanoseconds)
    }

    public func activateWorkbench() {
        guard !workbenchIsActive else { return }
        workbenchIsActive = true
        refresh()
        sampleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { try await Task.sleep(nanoseconds: self.sampleIntervalNanoseconds) }
                catch { return }
                guard self.workbenchIsActive else { return }
                self.sampleSelectedDeviceIO()
            }
        }
    }

    public func deactivateWorkbench() {
        workbenchIsActive = false
        sampleTask?.cancel(); sampleTask = nil
        localSamplingConsentDeviceIDs.removeAll()
        invalidateCounterSample(clearReading: true)
        observationGeneration &+= 1
    }

    public func pauseSamplingForSleep() {
        workbenchIsSleeping = true
        invalidateCounterSample(clearReading: true)
    }

    public func resumeSamplingAfterWake() {
        workbenchIsSleeping = false
        invalidateCounterSample(clearReading: true)
    }

    public func isLocalDeviceSamplingConsented(_ deviceID: String) -> Bool {
        localSamplingConsentDeviceIDs.contains(deviceID)
    }

    public func setLocalDeviceSamplingConsent(_ consented: Bool, for deviceID: String) {
        guard workbenchIsActive, !workbenchIsSleeping,
              let device = workbench.devices.first(where: { $0.id == deviceID }),
              workbench.selectedDeviceID == deviceID, !device.isExternal, device.identityVerified else { return }
        if consented { localSamplingConsentDeviceIDs.insert(deviceID) }
        else { localSamplingConsentDeviceIDs.remove(deviceID) }
        invalidateCounterSample(clearReading: true)
        if consented { sampleSelectedDeviceIO() }
    }

    public func refresh() {
        guard !isBusy else { return }
        canBeginWholeDeviceEject = false
        canContinueWholeDeviceEject = false
        canReturnFromWholeDeviceEject = false
        inventoryState = .loading
        discoveredLegacyDisk = false
        invalidateCounterSample(clearReading: true)
        workbench = SectoriumWorkbenchSnapshot(
            devices: workbench.devices, selectedDeviceID: workbench.selectedDeviceID,
            profiles: workbench.profiles, selectedProfileID: workbench.selectedProfileID,
            readiness: .unknown("Refreshing device and development disk identity"),
            pendingOperation: workbench.pendingOperation,
            io: .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false),
            operationSteps: workbench.operationSteps, safeToUnplug: false
        )
        snapshot = HESectoriumRuntimeSnapshot(
            installed: snapshot.installed, automationEnabled: snapshot.automationEnabled,
            readiness: .unknown, pendingEject: snapshot.pendingEject,
            diagnostics: snapshot.diagnostics, latestActionSummary: snapshot.latestActionSummary,
            agentLoadStatus: snapshot.agentLoadStatus, operationProgress: snapshot.operationProgress
        )
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        let selectedID = workbench.selectedDeviceID
        let selectedProfileID = workbench.selectedProfileID
        Task.detached(priority: .utility) { [weak self] in
            let value = service.refreshStatus()
            let observed = Result { try service.observeSectoriumDevices() }
            let devices = try? observed.get()
            let profiles = service.sectoriumProfiles()
            let legacy = service.discoveredLegacyDevelopmentDisk()
            let effectiveID = selectedID
            let readiness = devices.map { service.sectoriumReadiness(deviceID: effectiveID,
                selectedProfileID: selectedProfileID, devices: $0, profiles: profiles) }
            let pending = service.pendingSectoriumOperation()
            let canBeginEject = service.canPrepareWholeDeviceEjectConfirmation()
            let canContinueEject = pending?.hasPrefix("eject:") == true
                && service.prepareContinueWholeDeviceEjectConfirmation() != nil
            let canReturnEject = pending?.hasPrefix("eject:") == true
                && service.canReturnFromWholeDeviceEject()
            await MainActor.run {
                guard let self, self.observationGeneration == generation else { return }
                self.snapshot = value
                self.canBeginWholeDeviceEject = canBeginEject
                self.canContinueWholeDeviceEject = canContinueEject
                self.canReturnFromWholeDeviceEject = canReturnEject
                self.discoveredLegacyDisk = legacy
                switch observed {
                case .success(let devices):
                    self.inventoryState = devices.isEmpty ? .empty : .available
                    self.apply(devices: devices, profiles: profiles, readiness: readiness, pending: pending)
                case .failure(let error):
                    self.inventoryState = (error as? SectoriumDeviceCatalogError) == .malformedDeviceInventory ? .malformed : .unavailable
                    self.apply(devices: [], profiles: profiles,
                               readiness: .unknown("Device inventory observation failed; refresh after checking disk access"), pending: pending)
                }
            }
        }
    }

    public func selectDevice(_ id: String?) {
        canBeginWholeDeviceEject = false
        canContinueWholeDeviceEject = false
        canReturnFromWholeDeviceEject = false
        invalidateCounterSample(clearReading: true)
        service.selectSectoriumDevice(id)
        let selected = workbench.devices.first { $0.id == id }
        let deviceProfiles = workbench.profiles.filter { $0.deviceID == id }
        let selectedProfileID = deviceProfiles.count == 1 ? deviceProfiles.first?.id : nil
        service.selectSectoriumProfile(selectedProfileID)
        let readiness: SectoriumWorkbenchReadiness = workbench.pendingOperation.map(SectoriumWorkbenchReadiness.operationInProgress)
            ?? (id == nil ? .noDevice : selected?.identityVerified == true ? .connected : .unknown("Physical device identity is unavailable"))
        workbench = SectoriumWorkbenchSnapshot(
            devices: workbench.devices, selectedDeviceID: id, profiles: workbench.profiles,
            selectedProfileID: selectedProfileID,
            readiness: readiness,
            pendingOperation: workbench.pendingOperation,
            io: .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false),
            operationSteps: workbench.operationSteps, safeToUnplug: false
        )
        refresh()
    }

    public func selectProfile(_ id: String?) {
        let profile = workbench.profiles.first { $0.id == id && $0.deviceID == workbench.selectedDeviceID }
        service.selectSectoriumProfile(profile?.id)
        workbench = SectoriumWorkbenchSnapshot(
            devices: workbench.devices, selectedDeviceID: workbench.selectedDeviceID, profiles: workbench.profiles,
            selectedProfileID: profile?.id, readiness: workbench.readiness,
            pendingOperation: workbench.pendingOperation, io: workbench.io,
            operationSteps: workbench.operationSteps, safeToUnplug: false
        )
        refresh()
    }

    func apply(devices: [SectoriumPhysicalDevice], profiles: [SectoriumDevelopmentProfile],
               readiness: SectoriumWorkbenchReadiness?, pending: String?) {
        invalidateCounterSample(clearReading: false)
        let selectedID = workbench.selectedDeviceID
        let selectedProfileID = workbench.selectedProfileID
        let selected = devices.first(where: { $0.id == selectedID })
        workbench = SectoriumWorkbenchSnapshot(
            devices: devices, selectedDeviceID: selectedID, profiles: profiles,
            selectedProfileID: profiles.first(where: { $0.id == selectedProfileID && $0.deviceID == selectedID })?.id
                ?? (profiles.filter { $0.deviceID == selectedID }.count == 1 ? profiles.first(where: { $0.deviceID == selectedID })?.id : nil),
            readiness: pending.map(SectoriumWorkbenchReadiness.operationInProgress)
                ?? (readiness ?? workbench.readiness), pendingOperation: pending,
            io: .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false),
            operationSteps: workbench.operationSteps,
            safeToUnplug: workbench.safeToUnplug && selected == nil && pending == nil
        )
    }

    /// Called by the active workbench's bounded sampling loop. Tests may invoke this through
    /// @testable imports; production sampling remains selected-device-only.
    func sampleSelectedDeviceIO() {
        guard workbenchIsActive, !workbenchIsSleeping, !isBusy, activeSampleToken == nil,
              let selectedID = workbench.selectedDeviceID,
              let device = workbench.devices.first(where: { $0.id == selectedID }),
              device.identityVerified,
              device.isExternal || localSamplingConsentDeviceIDs.contains(selectedID) else {
            if workbench.selectedDeviceID == nil || workbench.selectedDeviceID.flatMap({ id in
                workbench.devices.first(where: { $0.id == id })
            }).map({ !$0.identityVerified || (!$0.isExternal && !localSamplingConsentDeviceIDs.contains($0.id)) }) == true {
                invalidateCounterSample(clearReading: true)
            }
            return
        }
        let token = UUID()
        activeSampleToken = token
        let service = self.service
        Task.detached(priority: .utility) { [weak self] in
            let counters = service.sampleSectoriumDeviceCounters(for: device)
            let sampledAt = ProcessInfo.processInfo.systemUptime
            await MainActor.run {
                guard let self, self.activeSampleToken == token else { return }
                self.activeSampleToken = nil
                guard self.workbenchIsActive, !self.workbenchIsSleeping,
                      self.workbench.selectedDeviceID == selectedID,
                      device.isExternal || self.localSamplingConsentDeviceIDs.contains(selectedID),
                      let counters else {
                    self.ioHistory.removeAll(keepingCapacity: false)
                    self.updateIO(.init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false))
                    return
                }
                let reading: SectoriumIOReading
                self.ioHistory = Self.prunedIOHistory(self.ioHistory, now: sampledAt)
                if let previous = self.ioHistory.last, previous.deviceID == selectedID {
                    reading = Self.rateReading(previous: previous.counters, current: counters,
                                               elapsed: sampledAt - previous.uptime)
                } else {
                    reading = .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false)
                }
                self.ioHistory.append(.init(deviceID: selectedID, counters: counters, uptime: sampledAt))
                self.ioHistory = Self.prunedIOHistory(self.ioHistory, now: sampledAt)
                self.updateIO(reading)
            }
        }
    }

    static func rateReading(previous: SectoriumDeviceIOCounters, current: SectoriumDeviceIOCounters,
                            elapsed: TimeInterval) -> SectoriumIOReading {
        guard elapsed >= 0.5, elapsed <= 3.0,
              current.readBytes >= previous.readBytes, current.writtenBytes >= previous.writtenBytes else {
            return .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false)
        }
        let readRate = UInt64(Double(current.readBytes - previous.readBytes) / elapsed)
        let writeRate = UInt64(Double(current.writtenBytes - previous.writtenBytes) / elapsed)
        return .init(readBytesPerSecond: readRate, writtenBytesPerSecond: writeRate, isFresh: true)
    }

    static func prunedIOHistory(_ history: [SectoriumIOSampleHistoryEntry], now: TimeInterval) -> [SectoriumIOSampleHistoryEntry] {
        Array(history.filter { $0.uptime <= now && now - $0.uptime <= 60 }.suffix(120))
    }

    private func invalidateCounterSample(clearReading: Bool) {
        activeSampleToken = nil
        ioHistory.removeAll(keepingCapacity: false)
        if clearReading { updateIO(.init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false)) }
    }

    private func updateIO(_ io: SectoriumIOReading) {
        workbench = SectoriumWorkbenchSnapshot(devices: workbench.devices,
            selectedDeviceID: workbench.selectedDeviceID, profiles: workbench.profiles,
            selectedProfileID: workbench.selectedProfileID, readiness: workbench.readiness,
            pendingOperation: workbench.pendingOperation, io: io,
            operationSteps: workbench.operationSteps, safeToUnplug: workbench.safeToUnplug)
    }

    public func createDevelopmentDisk(deviceID: String, parentDirectory: URL, name: String, capacityGiB: Int,
                                      caseSensitive: Bool, password: String?) {
        performWorkbench({ service in
            service.createDevelopmentDisk(deviceID: deviceID, parentDirectory: parentDirectory, name: name,
                                          capacityGiB: capacityGiB, caseSensitive: caseSensitive, password: password)
        }, successReadiness: .notStarted)
    }

    public func adoptDevelopmentDisk(deviceID: String, imageURL: URL) {
        performWorkbench({ service in service.adoptDevelopmentDisk(deviceID: deviceID, imageURL: imageURL) }, successReadiness: .notStarted)
    }
    public func startDevelopmentDisk(password: String? = nil) {
        performWorkbench({ $0.startDevelopmentDisk(password: password) }, successReadiness: .ready)
    }
    public func prepareStopDevelopmentDiskConfirmation() {
        guard !isBusy else { return }
        isBusy = true
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let confirmation = service.prepareStopDevelopmentDiskConfirmation()
            await MainActor.run {
                guard let self, self.observationGeneration == generation else { return }
                self.isBusy = false
                self.stopConfirmation = confirmation
                if confirmation == nil { self.lastResult = "Mounted image identity could not be verified for Stop" }
            }
        }
    }
    public func cancelStopConfirmation() { stopConfirmation = nil }
    public func stopDevelopmentDisk(knownWritersClosed: Bool) {
        guard let confirmation = stopConfirmation else { return }
        stopConfirmation = nil
        performWorkbench({ $0.stopDevelopmentDisk(checkpoint: confirmation, knownWritersClosed: knownWritersClosed) },
                         successReadiness: .notStarted)
    }
    public func ejectSelectedExternalDevice() { prepareWholeDeviceEjectConfirmation() }
    public func prepareWholeDeviceEjectConfirmation() {
        guard !isBusy else { return }
        isBusy = true
        wholeDeviceEjectConfirmation = nil
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let confirmation = service.prepareWholeDeviceEjectConfirmation()
            await MainActor.run {
                guard let self, self.observationGeneration == generation else { return }
                self.isBusy = false
                self.wholeDeviceEjectConfirmation = confirmation
                if confirmation == nil { self.lastResult = "Target or complete affected-member scope could not be verified" }
            }
        }
    }
    public func prepareContinueWholeDeviceEjectConfirmation() {
        guard !isBusy else { return }
        isBusy = true
        wholeDeviceEjectConfirmation = nil
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let confirmation = service.prepareContinueWholeDeviceEjectConfirmation()
            await MainActor.run {
                guard let self, self.observationGeneration == generation else { return }
                self.isBusy = false
                self.wholeDeviceEjectConfirmation = confirmation
                if confirmation == nil { self.lastResult = "Interrupted physical eject no longer matches its durable recovery journal" }
            }
        }
    }
    public func cancelWholeDeviceEjectConfirmation() { wholeDeviceEjectConfirmation = nil }
    public func confirmWholeDeviceEject(knownWritersClosed: Bool) {
        guard let confirmation = wholeDeviceEjectConfirmation else { return }
        wholeDeviceEjectConfirmation = nil
        let checkpoint = confirmation.checkpoint(knownWritersClosed: knownWritersClosed)
        if confirmation.isContinuation {
            performWorkbench({ $0.continueWholeDeviceEject(checkpoint: checkpoint) },
                             successReadiness: .ejected, safeToUnplug: true)
        } else {
            performWorkbench({ $0.ejectSelectedExternalDevice(checkpoint: checkpoint) },
                             successReadiness: .ejected, safeToUnplug: true)
        }
    }
    public func resumePendingOperation() { performWorkbench({ $0.resumePendingSectoriumOperation() }, successReadiness: .unknown("Operation resumed; refresh to verify")) }
    public func returnToDevelopment() { performWorkbench({ $0.returnToDevelopment() }, successReadiness: .unknown("Return verified; refresh the mounted identity")) }

    private func performWorkbench(_ action: @escaping @Sendable (HESectoriumService) -> OperationResult,
                                  successReadiness: SectoriumWorkbenchReadiness,
                                  safeToUnplug: Bool = false) {
        guard !isBusy else { return }
        isBusy = true
        let service = self.service
        let selectedID = workbench.selectedDeviceID
        let selectedProfileID = workbench.selectedProfileID
        observationGeneration &+= 1
        let generation = observationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = action(service)
            let devices = try? service.observeSectoriumDevices()
            let profiles = service.sectoriumProfiles()
            let status = service.refreshStatus()
            let effectiveID = selectedID
            let readiness = devices.map { service.sectoriumReadiness(deviceID: effectiveID,
                selectedProfileID: selectedProfileID, devices: $0, profiles: profiles) }
            let pending = service.pendingSectoriumOperation()
            await MainActor.run {
                guard let self else { return }
                self.isBusy = false
                guard self.observationGeneration == generation else { return }
                self.snapshot = status
                self.lastResult = result.failure.map { "Failed: \($0)" } ?? "Completed"
                self.workbench = SectoriumWorkbenchSnapshot(
                    devices: devices ?? self.workbench.devices,
                    selectedDeviceID: self.workbench.selectedDeviceID,
                    profiles: profiles,
                    selectedProfileID: profiles.first(where: { $0.id == selectedProfileID && $0.deviceID == self.workbench.selectedDeviceID })?.id
                        ?? (profiles.filter { $0.deviceID == self.workbench.selectedDeviceID }.count == 1
                            ? profiles.first(where: { $0.deviceID == self.workbench.selectedDeviceID })?.id : nil),
                    readiness: pending.map(SectoriumWorkbenchReadiness.operationInProgress)
                        ?? (result.failure == nil ? (readiness ?? successReadiness) : .partialFailure(String(describing: result.failure!))),
                    pendingOperation: pending,
                    io: self.workbench.io, operationSteps: result.steps, safeToUnplug: result.succeeded && safeToUnplug
                )
                self.isBusy = false
            }
        }
    }

    public func mountDEV() { perform { service in
        let result = service.mountDEV()
        return result.failure.map { "Failed: \($0)" } ?? "Completed"
    } }
    public func safeEjectHE() { perform { service in
        let result = service.safeEjectHE()
        return result.failure.map { "Failed: \($0)" } ?? "Completed"
    } }
    public func installRepair() { performInstall(.repair) }
    public func install() { performInstall(.install) }
    public func setAutomation(_ enabled: Bool) {
        guard !isBusy else { return }
        isBusy = true
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = service.setAutomationEnabled(enabled)
            let status = service.refreshStatus()
            await MainActor.run {
                guard let self else { return }
                self.isBusy = false
                guard self.observationGeneration == generation else { return }
                self.lastResult = result.summary
                self.snapshot = status
            }
        }
    }

    private func perform(_ action: @escaping @Sendable (HESectoriumService) -> String) {
        guard !isBusy else { return }
        isBusy = true
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = action(service)
            let status = service.refreshStatus()
            await MainActor.run {
                guard let self else { return }
                self.isBusy = false
                guard self.observationGeneration == generation else { return }
                self.lastResult = result
                self.snapshot = status
            }
        }
    }

    private func performInstall(_ action: HESectoriumInstallAction) {
        guard !isBusy else { return }
        isBusy = true
        let service = self.service
        observationGeneration &+= 1
        let generation = observationGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = service.installRepair(action)
            let status = service.refreshStatus()
            await MainActor.run {
                guard let self else { return }
                self.isBusy = false
                guard self.observationGeneration == generation else { return }
                self.lastResult = result.summary
                self.snapshot = status
            }
        }
    }
}
