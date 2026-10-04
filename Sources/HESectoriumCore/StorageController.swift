import Foundation

public struct VolumeIdentity: Equatable, Sendable {
    public var uuid: UUID?
    public var mountPoint: String
    public var fileSystem: String
    public var writable: Bool
    public var mountedVolume: Bool
    public var name: String
    /// True only when the observed root resolves to the canonical mounted volume root.
    public var rootMatchesExpected: Bool

    public init(uuid: UUID?, mountPoint: String, fileSystem: String, writable: Bool,
                mountedVolume: Bool = true, name: String, rootMatchesExpected: Bool = false) {
        self.uuid = uuid; self.mountPoint = mountPoint; self.fileSystem = fileSystem
        self.writable = writable; self.mountedVolume = mountedVolume; self.name = name
        self.rootMatchesExpected = rootMatchesExpected
    }
}

public struct ImageIdentity: Equatable, Sendable {
    /// Physical volume that stores the sparsebundle image.
    public var backingVolumeUUID: UUID?
    /// UUID exposed by the attached image; DEV must resolve to this volume.
    public var attachedVolumeUUID: UUID?
    public var path: String
    public init(backingVolumeUUID: UUID?, attachedVolumeUUID: UUID?, path: String) {
        self.backingVolumeUUID = backingVolumeUUID; self.attachedVolumeUUID = attachedVolumeUUID; self.path = path
    }
}

public struct StorageObservation: Equatable, Sendable {
    public var outer: VolumeIdentity
    public var dev: VolumeIdentity
    public var image: ImageIdentity
    public init(outer: VolumeIdentity, dev: VolumeIdentity, image: ImageIdentity) {
        self.outer = outer; self.dev = dev; self.image = image
    }

    public static var expectedReady: Self {
        let policy = StorageIdentityPolicy.expected
        return .init(
            outer: .init(uuid: policy.outerUUID, mountPoint: policy.outerMountPoint, fileSystem: "ExFAT",
                         writable: true, name: "HE", rootMatchesExpected: true),
            dev: .init(uuid: policy.devUUID, mountPoint: policy.devMountPoint, fileSystem: "APFS",
                       writable: true, name: policy.devVolumeName, rootMatchesExpected: true),
            image: .init(backingVolumeUUID: policy.outerUUID, attachedVolumeUUID: policy.devUUID,
                         path: policy.imagePath))
    }
}

public struct StorageIdentityPolicy: Sendable {
    public let outerUUID: UUID
    public let devUUID: UUID?
    public let outerMountPoint: String
    public let devMountPoint: String
    public let devVolumeName: String
    public let imagePath: String
    /// Used only for a newly created sparsebundle before its APFS UUID exists.
    /// The observed UUID is accepted only when Runtime proves the exact image/backing/APFS chain.
    public init(outerUUID: UUID, devUUID: UUID?, outerMountPoint: String = "/Volumes/HE",
                devMountPoint: String = "/Volumes/HE/DEV", devVolumeName: String = "DEV_APFS",
                imagePath: String = "/Volumes/HE/.DEV-APFS.sparsebundle") {
        self.outerUUID = outerUUID; self.devUUID = devUUID; self.outerMountPoint = outerMountPoint
        self.devMountPoint = devMountPoint; self.devVolumeName = devVolumeName; self.imagePath = imagePath
    }

    public static let expected = Self(
        outerUUID: UUID(uuidString: "2FE2A779-0DC8-3468-8E3C-E113598C46CE")!,
        devUUID: UUID(uuidString: "0476F9CC-86A3-40D8-A8D4-83D882522CAD")!)

    public func validate(_ value: StorageObservation) -> Result<Void, ReadinessFailure> {
        if case .failure(let failure) = validateOuter(value.outer) { return .failure(failure) }
        guard value.dev.uuid != nil else { return .failure(.devUUIDMissing) }
        if let devUUID, value.dev.uuid != devUUID { return .failure(.devUUIDMismatch) }
        guard value.dev.mountedVolume else { return .failure(.devNotMountedVolume) }
        guard value.dev.mountPoint == devMountPoint else { return .failure(.devMountMismatch) }
        guard value.dev.rootMatchesExpected else { return .failure(.devRootMismatch) }
        guard value.dev.name == devVolumeName else { return .failure(.devNameMismatch) }
        guard value.dev.fileSystem.uppercased() == "APFS" else { return .failure(.devNotAPFS) }
        guard value.dev.writable else { return .failure(.devReadOnly) }
        guard value.image.path == imagePath, value.image.backingVolumeUUID == outerUUID,
              value.image.attachedVolumeUUID == value.dev.uuid,
              (devUUID == nil || value.image.attachedVolumeUUID == devUUID) else { return .failure(.imageRelationMismatch) }
        return .success(())
    }

    public func validateOuter(_ observed: VolumeIdentity?) -> Result<Void, ReadinessFailure> {
        guard let observed else { return .failure(.outerUnavailable) }
        guard observed.uuid != nil else { return .failure(.outerUUIDMissing) }
        guard observed.uuid == outerUUID else { return .failure(.outerUUIDMismatch) }
        guard observed.mountedVolume, observed.mountPoint == outerMountPoint else { return .failure(.outerMountMismatch) }
        guard observed.rootMatchesExpected else { return .failure(.outerRootMismatch) }
        guard observed.writable else { return .failure(.outerReadOnly) }
        return .success(())
    }
}

public enum ReadinessFailure: String, Error, Equatable, Sendable {
    case outerUnavailable, outerUUIDMissing, outerUUIDMismatch, outerMountMismatch, outerRootMismatch, outerReadOnly
    case devUUIDMissing, devUUIDMismatch, devNotMountedVolume
    case devMountMismatch, devRootMismatch, devNameMismatch, devNotAPFS, devReadOnly, imageRelationMismatch
}

public enum OperationMode: String, Sendable { case manual, automatic }
public enum OccupancyScope: String, Sendable { case dev, outer }
public enum OccupancyAssessment: Equatable, Sendable {
    case noVisibleOccupancy
    case busy(processIDs: [Int32])
    case incomplete(reason: String)
}
public enum EjectStep: String, CaseIterable, Equatable, Sendable { case flush, unmountDEV, detachImage, ejectOuterHE }

public struct CommandOutcome: Equatable, Sendable {
    public let exitCode: Int32
    public let detail: String
    public var succeeded: Bool { exitCode == 0 }
    public init(exitCode: Int32, detail: String = "") { self.exitCode = exitCode; self.detail = detail }
    public static let success = Self(exitCode: 0)
}

public enum FinalOuterState: Equatable, Sendable { case absent, stillPresent, unknown(String) }

public protocol StorageBackend: AnyObject {
    /// A minimal physical-volume probe that works before an image/DEV volume is attached.
    func observeOuter() -> VolumeIdentity?
    func observe() -> StorageObservation?
    func attachImage() -> CommandOutcome
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment
    func perform(_ step: EjectStep) -> CommandOutcome
    func finalOuterState() -> FinalOuterState
}

public struct StoragePersistentState: Equatable, Sendable {
    public let revision: UInt64
    public var ejectIntent: Bool
    public var operationID: String?
    public var outerDisappearedAfterIntent: Bool
    public var outerReconnectAttempted: Bool
    /// Non-automation operation marker shared with the Sectorium workbench.
    public var workbenchOperation: String?
    /// Durable validation/mutation boundary for safe workbench recovery.
    public var workbenchPhase: String?
    public var workbenchTarget: String?
    public var workbenchCompletedStep: String?
    public var workbenchTerminalResult: String?
    public init(revision: UInt64 = 0, ejectIntent: Bool, operationID: String? = nil,
                outerDisappearedAfterIntent: Bool = false, outerReconnectAttempted: Bool = false,
                workbenchOperation: String? = nil, workbenchPhase: String? = nil,
                workbenchTarget: String? = nil, workbenchCompletedStep: String? = nil,
                workbenchTerminalResult: String? = nil) {
        self.revision = revision; self.ejectIntent = ejectIntent; self.operationID = operationID
        self.outerDisappearedAfterIntent = outerDisappearedAfterIntent
        self.outerReconnectAttempted = outerReconnectAttempted
        self.workbenchOperation = workbenchOperation
        self.workbenchPhase = workbenchPhase
        self.workbenchTarget = workbenchTarget
        self.workbenchCompletedStep = workbenchCompletedStep
        self.workbenchTerminalResult = workbenchTerminalResult
    }
}

public protocol DurableStateStore: AnyObject {
    func load() throws -> StoragePersistentState
    func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool
}
public protocol OperationLock: AnyObject { func acquire() -> Bool; func release() }

public enum StorageEvent: Equatable, Sendable {
    case outerDisappeared(uuid: UUID)
    case outerReappeared(uuid: UUID)
    case devMounted(uuid: UUID)
    case imageChanged
}

public enum OperationFailure: Equatable, Sendable {
    case operationInProgress, ejectAlreadyPending, recoveryRequiresManualMount, noPendingIntent
    case stateUnavailable(String), stateConflict
    case attachFailed(Int32, String), observationUnavailable, readiness(ReadinessFailure)
    case occupancyBusy(OccupancyScope, [Int32]), occupancyIncomplete(OccupancyScope, String)
    case stepFailed(EjectStep, Int32, String), outerStillPresent, finalStateUnknown(String)
    case workbenchFailed(String)
}
public enum StepStatus: String, Equatable, Sendable { case succeeded, failed, skipped }
public struct OperationStepResult: Equatable, Sendable {
    public let step: String
    public let status: StepStatus
    public let detail: String
    public init(step: String, status: StepStatus, detail: String = "") {
        self.step = step; self.status = status; self.detail = detail
    }
}
public struct OperationResult: Equatable, Sendable {
    public let operationID: String
    public let mode: OperationMode
    public let steps: [OperationStepResult]
    public let failure: OperationFailure?
    public var succeeded: Bool { failure == nil }
    public init(operationID: String, mode: OperationMode, steps: [OperationStepResult], failure: OperationFailure? = nil) {
        self.operationID = operationID; self.mode = mode; self.steps = steps; self.failure = failure
    }
}

/// Orchestrates one shared protocol. Platform commands, persistent state and mutual exclusion are injected.
public final class StorageController {
    // Internal so the whole-device protocol reuses this controller's single store and lock.
    let backend: StorageBackend
    let store: DurableStateStore
    let lock: OperationLock
    public let identityPolicy: StorageIdentityPolicy

    public init(backend: StorageBackend, store: DurableStateStore, lock: OperationLock,
                identityPolicy: StorageIdentityPolicy = .expected) {
        self.backend = backend; self.store = store; self.lock = lock; self.identityPolicy = identityPolicy
    }

    public func mountDEV(mode: OperationMode = .manual) -> OperationResult {
        withLock(mode) { id in mountLocked(operationID: id, mode: mode, requirePendingIntent: false) }
    }

    /// Explicit user recovery for pending intent when physical event history is unknown.
    /// No timer or automatic startup path calls this method.
    public func recoverPendingIntentManually() -> OperationResult {
        withLock(.manual) { id in mountLocked(operationID: id, mode: .manual, requirePendingIntent: true) }
    }

    public func safeEjectHE(mode: OperationMode = .manual) -> OperationResult {
        withLock(mode) { id in
            var steps: [OperationStepResult] = []
            let prior: StoragePersistentState
            do { prior = try store.load() } catch { return result(id, mode, steps, .stateUnavailable(String(describing: error))) }
            guard prior.workbenchOperation == nil else { return result(id, mode, steps, .operationInProgress) }
            guard !prior.ejectIntent else { return result(id, mode, steps, .ejectAlreadyPending) }
            let pending = StoragePersistentState(revision: prior.revision + 1, ejectIntent: true, operationID: id,
                workbenchOperation: prior.workbenchOperation, workbenchPhase: prior.workbenchPhase,
                workbenchTarget: prior.workbenchTarget, workbenchCompletedStep: prior.workbenchCompletedStep,
                workbenchTerminalResult: prior.workbenchTerminalResult)
            do {
                guard try store.compareAndSwap(expectedRevision: prior.revision, newState: pending) else {
                    return result(id, mode, steps, .stateConflict)
                }
            } catch { return result(id, mode, steps, .stateUnavailable(String(describing: error))) }
            steps.append(.init(step: "persistEjectIntent", status: .succeeded))
            guard let observation = backend.observe() else {
                steps.append(.init(step: "verifyReadiness", status: .failed, detail: "No observation"))
                return result(id, mode, steps, .observationUnavailable)
            }
            if case .failure(let failure) = identityPolicy.validate(observation) {
                steps.append(.init(step: "verifyReadiness", status: .failed, detail: failure.rawValue))
                return result(id, mode, steps, .readiness(failure))
            }
            steps.append(.init(step: "verifyReadiness", status: .succeeded))
            for scope: OccupancyScope in [.dev, .outer] {
                switch backend.assessOccupancy(scope: scope) {
                case .noVisibleOccupancy:
                    steps.append(.init(step: "occupancy.\(scope.rawValue)", status: .succeeded, detail: "noVisibleOccupancy"))
                case .busy(let pids):
                    steps.append(.init(step: "occupancy.\(scope.rawValue)", status: .failed, detail: "busy"))
                    return result(id, mode, steps, .occupancyBusy(scope, pids))
                case .incomplete(let reason):
                    steps.append(.init(step: "occupancy.\(scope.rawValue)", status: .failed, detail: reason))
                    return result(id, mode, steps, .occupancyIncomplete(scope, reason))
                }
            }
            for step in EjectStep.allCases {
                let outcome = backend.perform(step)
                steps.append(.init(step: step.rawValue, status: outcome.succeeded ? .succeeded : .failed,
                                   detail: outcome.detail.isEmpty ? "exit=\(outcome.exitCode)" : outcome.detail))
                guard outcome.succeeded else {
                    return result(id, mode, steps, .stepFailed(step, outcome.exitCode, outcome.detail))
                }
            }
            switch backend.finalOuterState() {
            case .absent:
                steps.append(.init(step: "verifyOuterAbsent", status: .succeeded))
                do {
                    let current = try store.load()
                    let marked = StoragePersistentState(revision: current.revision + 1, ejectIntent: current.ejectIntent,
                        operationID: current.operationID, outerDisappearedAfterIntent: current.ejectIntent,
                        outerReconnectAttempted: false, workbenchOperation: current.workbenchOperation,
                        workbenchPhase: current.workbenchPhase, workbenchTarget: current.workbenchTarget,
                        workbenchCompletedStep: current.workbenchCompletedStep,
                        workbenchTerminalResult: current.workbenchTerminalResult)
                    guard try store.compareAndSwap(expectedRevision: current.revision, newState: marked) else {
                        steps.append(.init(step: "recordOuterDisappearance", status: .failed, detail: "State revision conflict"))
                        return result(id, mode, steps, .stateConflict)
                    }
                    steps.append(.init(step: "recordOuterDisappearance", status: .succeeded))
                } catch {
                    let detail = String(describing: error)
                    steps.append(.init(step: "recordOuterDisappearance", status: .failed, detail: detail))
                    return result(id, mode, steps, .stateUnavailable(detail))
                }
            case .stillPresent:
                steps.append(.init(step: "verifyOuterAbsent", status: .failed, detail: "Outer HE remains present"))
                return result(id, mode, steps, .outerStillPresent)
            case .unknown(let detail):
                steps.append(.init(step: "verifyOuterAbsent", status: .failed, detail: detail))
                return result(id, mode, steps, .finalStateUnknown(detail))
            }
            return OperationResult(operationID: id, mode: mode, steps: steps)
        }
    }

    public func handle(_ event: StorageEvent) -> OperationResult {
        let id = UUID().uuidString
        guard lock.acquire() else { return result(id, .automatic, [], .operationInProgress) }
        defer { lock.release() }
        do {
            let state = try store.load()
            if state.workbenchOperation != nil { return result(id, .automatic, [], .operationInProgress) }
            switch event {
            case .outerDisappeared(let uuid) where uuid == identityPolicy.outerUUID && state.ejectIntent:
                let marked = StoragePersistentState(revision: state.revision + 1, ejectIntent: true,
                    operationID: state.operationID, outerDisappearedAfterIntent: true,
                    outerReconnectAttempted: false, workbenchOperation: state.workbenchOperation,
                    workbenchPhase: state.workbenchPhase, workbenchTarget: state.workbenchTarget,
                    workbenchCompletedStep: state.workbenchCompletedStep,
                    workbenchTerminalResult: state.workbenchTerminalResult)
                guard try store.compareAndSwap(expectedRevision: state.revision, newState: marked) else {
                    return result(id, .automatic, [], .stateConflict)
                }
                return OperationResult(operationID: id, mode: .automatic,
                                      steps: [.init(step: "recordOuterDisappearance", status: .succeeded)])
            case .outerReappeared(let uuid) where uuid == identityPolicy.outerUUID && state.ejectIntent
                && state.outerDisappearedAfterIntent && !state.outerReconnectAttempted:
                var steps: [OperationStepResult] = []
                if case .failure(let failure) = identityPolicy.validateOuter(backend.observeOuter()) {
                    steps.append(.init(step: "verifyOuterIdentity", status: .failed, detail: failure.rawValue))
                    return result(id, .automatic, steps, .readiness(failure))
                }
                steps.append(.init(step: "verifyOuterIdentity", status: .succeeded))

                // Claim this physical reinsert sequence before the mutating attach. Duplicate events
                // cannot issue another attach; a later confirmed disconnect resets the claim.
                let claimed = StoragePersistentState(revision: state.revision + 1, ejectIntent: true,
                    operationID: state.operationID, outerDisappearedAfterIntent: true,
                    outerReconnectAttempted: true, workbenchOperation: state.workbenchOperation,
                    workbenchPhase: state.workbenchPhase, workbenchTarget: state.workbenchTarget,
                    workbenchCompletedStep: state.workbenchCompletedStep,
                    workbenchTerminalResult: state.workbenchTerminalResult)
                guard try store.compareAndSwap(expectedRevision: state.revision, newState: claimed) else {
                    return result(id, .automatic, steps, .stateConflict)
                }

                let attach = backend.attachImage()
                steps.append(.init(step: "attachImage", status: attach.succeeded ? .succeeded : .failed, detail: attach.detail))
                guard attach.succeeded else {
                    return result(id, .automatic, steps, .attachFailed(attach.exitCode, attach.detail))
                }
                guard let observation = backend.observe() else {
                    steps.append(.init(step: "verifyReadiness", status: .failed, detail: "No observation"))
                    return result(id, .automatic, steps, .observationUnavailable)
                }
                if case .failure(let failure) = identityPolicy.validate(observation) {
                    steps.append(.init(step: "verifyReadiness", status: .failed, detail: failure.rawValue))
                    return result(id, .automatic, steps, .readiness(failure))
                }
                steps.append(.init(step: "verifyReadiness", status: .succeeded))
                let recovered = StoragePersistentState(revision: claimed.revision + 1, ejectIntent: false,
                    outerReconnectAttempted: claimed.outerReconnectAttempted,
                    workbenchOperation: claimed.workbenchOperation, workbenchPhase: claimed.workbenchPhase,
                    workbenchTarget: claimed.workbenchTarget, workbenchCompletedStep: claimed.workbenchCompletedStep,
                    workbenchTerminalResult: claimed.workbenchTerminalResult)
                guard try store.compareAndSwap(expectedRevision: claimed.revision, newState: recovered) else {
                    return result(id, .automatic, steps, .stateConflict)
                }
                steps.append(.init(step: "clearEjectIntent", status: .succeeded,
                                   detail: "Outer reinsert and complete storage chain validated"))
                return OperationResult(operationID: id, mode: .automatic, steps: steps)
            case .outerReappeared(let uuid) where uuid == identityPolicy.outerUUID && state.ejectIntent
                && state.outerDisappearedAfterIntent && state.outerReconnectAttempted:
                return OperationResult(operationID: id, mode: .automatic,
                    steps: [.init(step: "ignoreEvent", status: .skipped, detail: "Reconnect already attempted for this physical insertion")])
            default:
                return OperationResult(operationID: id, mode: .automatic,
                                       steps: [.init(step: "ignoreEvent", status: .skipped, detail: "Not a verified outer reconnect")])
            }
        } catch { return result(id, .automatic, [], .stateUnavailable(String(describing: error))) }
    }

    /// Reads durable state only. Lock lifetime belongs to the injected kernel-backed lock.
    public func processExit() -> StoragePersistentState? { try? store.load() }

    private func withLock(_ mode: OperationMode, _ body: (String) -> OperationResult) -> OperationResult {
        let id = UUID().uuidString
        guard lock.acquire() else { return result(id, mode, [], .operationInProgress) }
        defer { lock.release() }
        return body(id)
    }
    private func mountLocked(operationID id: String, mode: OperationMode,
                             requirePendingIntent: Bool) -> OperationResult {
        var steps: [OperationStepResult] = []
        let state: StoragePersistentState
        do { state = try store.load() } catch { return result(id, mode, steps, .stateUnavailable(String(describing: error))) }
        if state.ejectIntent && mode == .automatic {
            steps.append(.init(step: "checkEjectIntent", status: .failed, detail: "Explicit manual mount required to recover"))
            return result(id, mode, steps, .recoveryRequiresManualMount)
        }
        if requirePendingIntent && !state.ejectIntent {
            return result(id, mode, steps, .noPendingIntent)
        }
        if state.workbenchOperation != nil { return result(id, mode, steps, .operationInProgress) }

        let outer = backend.observeOuter()
        if case .failure(let failure) = identityPolicy.validateOuter(outer) {
            steps.append(.init(step: "verifyOuterIdentity", status: .failed, detail: failure.rawValue))
            return result(id, mode, steps, .readiness(failure))
        }
        steps.append(.init(step: "verifyOuterIdentity", status: .succeeded))

        let attached = backend.attachImage()
        steps.append(.init(step: "attachImage", status: attached.succeeded ? .succeeded : .failed, detail: attached.detail))
        guard attached.succeeded else { return result(id, mode, steps, .attachFailed(attached.exitCode, attached.detail)) }
        guard let observation = backend.observe() else {
            steps.append(.init(step: "verifyReadiness", status: .failed, detail: "No observation"))
            return result(id, mode, steps, .observationUnavailable)
        }
        if case .failure(let failure) = identityPolicy.validate(observation) {
            steps.append(.init(step: "verifyReadiness", status: .failed, detail: failure.rawValue))
            return result(id, mode, steps, .readiness(failure))
        }
        steps.append(.init(step: "verifyReadiness", status: .succeeded))

        if state.ejectIntent && mode == .manual {
            let recovered = StoragePersistentState(revision: state.revision + 1, ejectIntent: false,
                outerReconnectAttempted: state.outerReconnectAttempted,
                workbenchOperation: state.workbenchOperation, workbenchPhase: state.workbenchPhase,
                workbenchTarget: state.workbenchTarget, workbenchCompletedStep: state.workbenchCompletedStep,
                workbenchTerminalResult: state.workbenchTerminalResult)
            do {
                guard try store.compareAndSwap(expectedRevision: state.revision, newState: recovered) else {
                    return result(id, mode, steps, .stateConflict)
                }
            } catch { return result(id, mode, steps, .stateUnavailable(String(describing: error))) }
            steps.append(.init(step: "clearEjectIntent", status: .succeeded, detail: "Validated explicit manual recovery"))
        }
        return OperationResult(operationID: id, mode: mode, steps: steps)
    }
    private func result(_ id: String, _ mode: OperationMode, _ steps: [OperationStepResult],
                        _ failure: OperationFailure) -> OperationResult {
        OperationResult(operationID: id, mode: mode, steps: steps, failure: failure)
    }
}
