import Foundation

/// Immutable identity for a freshly observed physical device and every related mounted or
/// attached member. `inventoryComplete` must be false when any relation cannot be resolved.
public struct WholeDeviceTopology: Codable, Equatable, Sendable {
    public struct Volume: Codable, Equatable, Hashable, Sendable {
        public let identity: String
        public let mounted: Bool
        public init(identity: String, mounted: Bool) { self.identity = identity; self.mounted = mounted }
    }
    public struct Image: Codable, Equatable, Hashable, Sendable {
        public let identity: String
        public let attached: Bool
        public let volumeIdentities: [String]
        /// Nil decodes pre-R2 journals; the runtime treats unknown mount state as mounted.
        public let mountedVolumeIdentities: [String]?
        public init(identity: String, attached: Bool, volumeIdentities: [String] = [],
                    mountedVolumeIdentities: [String]? = nil) {
            self.identity = identity; self.attached = attached; self.volumeIdentities = volumeIdentities
            self.mountedVolumeIdentities = mountedVolumeIdentities
        }
    }
    public let physicalIdentity: String
    public let bsdName: String
    public let isWholeDevice: Bool
    public let isExternal: Bool
    public let isSystemDevice: Bool
    public let inventoryComplete: Bool
    public let volumes: [Volume]
    public let images: [Image]
    public init(physicalIdentity: String, bsdName: String, isWholeDevice: Bool, isExternal: Bool,
                isSystemDevice: Bool, inventoryComplete: Bool, volumes: [Volume], images: [Image]) {
        self.physicalIdentity = physicalIdentity; self.bsdName = bsdName; self.isWholeDevice = isWholeDevice
        self.isExternal = isExternal; self.isSystemDevice = isSystemDevice; self.inventoryComplete = inventoryComplete
        self.volumes = volumes; self.images = images
    }
    public var hasUniqueMembers: Bool {
        !volumes.isEmpty && Set(volumes.map(\.identity)).count == volumes.count
            && Set(images.map(\.identity)).count == images.count
            && images.allSatisfy { Set($0.volumeIdentities).count == $0.volumeIdentities.count }
            && images.allSatisfy { image in
                guard let mounted = image.mountedVolumeIdentities else { return true }
                return Set(mounted).isSubset(of: Set(image.volumeIdentities))
            }
            && volumes.allSatisfy { !$0.identity.isEmpty } && images.allSatisfy { !$0.identity.isEmpty }
    }
    public var memberKey: String {
        let physical = volumes.map { "v:\($0.identity)" }
        let imageRows = images.map { "i:\($0.identity):" + $0.volumeIdentities.sorted().joined(separator: ",") }
        return (physical + imageRows).sorted().joined(separator: "\n")
    }
    public func matchesIdentityAndMembers(_ other: Self) -> Bool {
        matchesPhysicalIdentityAndVolumes(other) && memberKey == other.memberKey
    }
    /// The physical target stays constant while attached images are deliberately removed.
    public func matchesPhysicalIdentityAndVolumes(_ other: Self) -> Bool {
        physicalIdentity == other.physicalIdentity && bsdName == other.bsdName
            && isWholeDevice == other.isWholeDevice && isExternal == other.isExternal
            && isSystemDevice == other.isSystemDevice && inventoryComplete && other.inventoryComplete
            && Set(volumes.map(\.identity)) == Set(other.volumes.map(\.identity))
            && volumes.count == other.volumes.count
            && Set(volumes.map(\.identity)).count == volumes.count
    }
}

public struct WholeDeviceEjectCheckpoint: Equatable, Sendable {
    public let confirmedExactTargetAndScope: Bool
    public let knownWritersClosed: Bool
    public let dependenciesCanFinishOffTarget: Bool
    public let confirmedPhysicalIdentity: String?
    public let confirmedMemberKey: String?
    public let confirmedAt: Date?
    public init(confirmedExactTargetAndScope: Bool, knownWritersClosed: Bool,
                dependenciesCanFinishOffTarget: Bool,
                confirmedPhysicalIdentity: String? = nil, confirmedMemberKey: String? = nil,
                confirmedAt: Date? = nil) {
        self.confirmedExactTargetAndScope = confirmedExactTargetAndScope
        self.knownWritersClosed = knownWritersClosed
        self.dependenciesCanFinishOffTarget = dependenciesCanFinishOffTarget
        self.confirmedPhysicalIdentity = confirmedPhysicalIdentity
        self.confirmedMemberKey = confirmedMemberKey
        self.confirmedAt = confirmedAt
    }
    public func permitsRequest(for target: WholeDeviceTopology, now: Date = Date()) -> Bool {
        guard confirmedExactTargetAndScope, knownWritersClosed, dependenciesCanFinishOffTarget,
              confirmedPhysicalIdentity == target.physicalIdentity,
              confirmedMemberKey == target.memberKey, target.inventoryComplete, target.hasUniqueMembers,
              let confirmedAt, now.timeIntervalSince(confirmedAt) >= -5,
              now.timeIntervalSince(confirmedAt) <= 120 else { return false }
        return true
    }
}

public enum WholeDeviceActionReceipt: Codable, Equatable, Sendable {
    case completed(String)
    /// A non-force grouped operation may fail after earlier members completed. Persist those
    /// exact member identities so recovery never describes a partial action as all-or-none.
    case partial(String, completedMembers: [String])
    case busy(String)
    case dissenter(String)
    case timedOut
    case missingCallback
    case failed(String)
}
public enum WholeDevicePresence: Equatable, Sendable { case present, absent, unknown(String) }
/// Fresh evidence for a process that stopped after persisting a whole-device eject request.
/// This records an observation only; it never fabricates the missing OS command receipt.
public enum WholeDeviceEjectIssuedRecovery: Equatable, Sendable {
    case exactTargetPresentUnmounted
    case exactTargetAbsent
    case refused
}
public enum WholeDeviceEjectFailure: Equatable, Sendable {
    case targetUnavailable, targetMismatch, unsafeTarget, incompleteTopology, checkpointRequired
    case stateUnavailable(String), stateConflict, operationPending, actionFailed(String)
    case topologyChanged, membersStillMounted, imagesStillAttached, absenceUnverified(String)
    case returnTargetMismatch
}
public struct WholeDeviceEjectResult: Equatable, Sendable {
    public let operationID: String
    public let completedSteps: [String]
    public let canUnplug: Bool
    public let failure: WholeDeviceEjectFailure?
    public var succeeded: Bool { failure == nil && canUnplug }
    public init(operationID: String, completedSteps: [String], canUnplug: Bool,
                failure: WholeDeviceEjectFailure? = nil) {
        self.operationID = operationID; self.completedSteps = completedSteps
        self.canUnplug = canUnplug; self.failure = failure
    }
}

/// Runtime supplies fresh topology and non-forcing Disk Arbitration receipts. This protocol
/// never calls a process/file inventory and never treats an operation as passive occupancy proof.
public protocol WholeDeviceEjectDriving: AnyObject {
    func observe(physicalIdentity: String) -> WholeDeviceTopology?
    func unmountImageVolumesNonForce(_ imageIdentity: String, volumeIdentities: [String],
                                     from target: WholeDeviceTopology) -> WholeDeviceActionReceipt
    func detachImageNonForce(_ imageIdentity: String, from target: WholeDeviceTopology) -> WholeDeviceActionReceipt
    func unmountAllPhysicalVolumesNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt
    func ejectWholeDeviceNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt
    func presence(physicalIdentity: String) -> WholeDevicePresence
    func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool
    func freshPhysicalContinuationMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool
    func freshEjectIssuedRecovery(_ journal: WholeDeviceEjectJournalRecord) -> WholeDeviceEjectIssuedRecovery
}

public extension WholeDeviceEjectDriving {
    func freshPhysicalContinuationMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool { false }
    func freshEjectIssuedRecovery(_ journal: WholeDeviceEjectJournalRecord) -> WholeDeviceEjectIssuedRecovery { .refused }
}

public struct WholeDeviceEjectJournalRecord: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case prepared, imageVolumesUnmountIssued, imageVolumesUnmounted, imageDetachIssued, imagesDetached
        case physicalVolumesUnmountIssued, physicalVolumesUnmounted
        case ejectIssued, ejectCallbackSucceeded, verifiedAbsent, interrupted
    }
    /// The last mutating request durably issued, including requests whose receipt failed or
    /// whose process stopped before a completion step could be recorded. Optional so older
    /// journals decode, but an absent value never authorizes an ambiguous recovery.
    public enum IssuedAction: String, Codable, Sendable {
        case imageVolumesUnmount, imageDetach, physicalVolumesUnmount, ejectWholeDevice
    }
    public enum RecoveryObservation: String, Codable, Sendable {
        case exactTargetPresentUnmountedAfterEjectIssue
        case exactTargetAbsentAfterEjectIssue
    }
    public let operationID: String
    public let target: WholeDeviceTopology
    public var phase: Phase
    public var completedSteps: [String]
    public var lastReceipt: WholeDeviceActionReceipt?
    public var lastIssuedAction: IssuedAction?
    /// A fresh post-interruption observation, kept distinct from an OS action receipt.
    public var recoveryObservation: RecoveryObservation?
    public init(operationID: String, target: WholeDeviceTopology, phase: Phase = .prepared,
                completedSteps: [String] = [], lastReceipt: WholeDeviceActionReceipt? = nil,
                lastIssuedAction: IssuedAction? = nil, recoveryObservation: RecoveryObservation? = nil) {
        self.operationID = operationID; self.target = target; self.phase = phase
        self.completedSteps = completedSteps; self.lastReceipt = lastReceipt
        self.lastIssuedAction = lastIssuedAction; self.recoveryObservation = recoveryObservation
    }
}

/// Used by StorageController under its existing shared lock and durable state store. The encoded
/// journal is stored in the existing workbench target slot while the eject intent suppresses
/// automation. No generic resume path may consume this journal.
public extension StorageController {
    func ejectWholeExternalDevice(physicalIdentity: String, checkpoint: WholeDeviceEjectCheckpoint,
                                  driver: WholeDeviceEjectDriving) -> WholeDeviceEjectResult {
        let operationID = UUID().uuidString
        guard checkpoint.confirmedExactTargetAndScope && checkpoint.knownWritersClosed
                && checkpoint.dependenciesCanFinishOffTarget else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .checkpointRequired)
        }
        guard lock.acquire() else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .operationPending)
        }
        defer { lock.release() }
        let state: StoragePersistentState
        do { state = try store.load() }
        catch { return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .stateUnavailable(String(describing: error))) }
        guard state.workbenchOperation == nil && !state.ejectIntent else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .operationPending)
        }
        guard let target = driver.observe(physicalIdentity: physicalIdentity) else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .targetUnavailable)
        }
        guard target.physicalIdentity == physicalIdentity else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .targetMismatch)
        }
        guard target.isWholeDevice && target.isExternal && !target.isSystemDevice else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .unsafeTarget)
        }
        guard target.inventoryComplete && target.hasUniqueMembers else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .incompleteTopology)
        }
        guard checkpoint.permitsRequest(for: target) else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .checkpointRequired)
        }
        var journal = WholeDeviceEjectJournalRecord(operationID: operationID, target: target)
        guard persistEjectJournal(journal, state: state, intent: true, phase: "eject:prepared") else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .stateConflict)
        }
        var completed: [String] = []
        var detachedImageIDs: Set<String> = []
        func fail(_ reason: WholeDeviceEjectFailure, _ receipt: WholeDeviceActionReceipt? = nil) -> WholeDeviceEjectResult {
            journal.phase = .interrupted; journal.completedSteps = completed; journal.lastReceipt = receipt
            _ = persistEjectJournal(journal, intent: true, phase: "eject:interrupted")
            return .init(operationID: operationID, completedSteps: completed, canUnplug: false, failure: reason)
        }
        for image in target.images where image.attached {
            let expectedImageIDs = Set(target.images.map(\.identity)).subtracting(detachedImageIDs)
            guard let beforeImageUnmount = driver.observe(physicalIdentity: physicalIdentity),
                  target.matchesPhysicalIdentityAndVolumes(beforeImageUnmount),
                  Set(beforeImageUnmount.images.map(\.identity)) == expectedImageIDs,
                  beforeImageUnmount.images.first(where: { $0.identity == image.identity })?.attached == true else {
                return fail(.topologyChanged)
            }
            journal.phase = .imageVolumesUnmountIssued; journal.completedSteps = completed
            journal.lastIssuedAction = .imageVolumesUnmount
            guard persistEjectJournal(journal, intent: true, phase: "eject:image-volumes-unmount-issued") else { return fail(.stateConflict) }
            let imageUnmount = driver.unmountImageVolumesNonForce(image.identity,
                volumeIdentities: image.volumeIdentities, from: target)
            journal.lastReceipt = imageUnmount
            guard case .completed = imageUnmount else {
                return fail(.actionFailed(String(describing: imageUnmount)), imageUnmount)
            }
            completed.append("unmountImageVolumes:\(image.identity)")
            guard let afterImageUnmount = driver.observe(physicalIdentity: physicalIdentity),
                  target.matchesPhysicalIdentityAndVolumes(afterImageUnmount),
                  Set(afterImageUnmount.images.map(\.identity)) == expectedImageIDs,
                  let imageAfterUnmount = afterImageUnmount.images.first(where: { $0.identity == image.identity }),
                  imageAfterUnmount.attached,
                  (imageAfterUnmount.mountedVolumeIdentities ?? imageAfterUnmount.volumeIdentities).isEmpty else {
                return fail(.membersStillMounted, imageUnmount)
            }
            journal.phase = .imageVolumesUnmounted; journal.completedSteps = completed
            guard persistEjectJournal(journal, intent: true, phase: "eject:image-volumes-unmounted") else {
                return fail(.stateConflict, imageUnmount)
            }
            guard let beforeDetach = driver.observe(physicalIdentity: physicalIdentity),
                  target.matchesPhysicalIdentityAndVolumes(beforeDetach),
                  Set(beforeDetach.images.map(\.identity)) == expectedImageIDs,
                  beforeDetach.images.first(where: { $0.identity == image.identity })?.attached == true else {
                return fail(.topologyChanged, imageUnmount)
            }
            journal.phase = .imageDetachIssued; journal.completedSteps = completed
            journal.lastIssuedAction = .imageDetach
            guard persistEjectJournal(journal, intent: true, phase: "eject:image-detach-issued") else { return fail(.stateConflict) }
            let receipt = driver.detachImageNonForce(image.identity, from: target)
            journal.lastReceipt = receipt
            guard case .completed = receipt else { return fail(.actionFailed(String(describing: receipt)), receipt) }
            completed.append("detachImage:\(image.identity)")
            guard let afterDetach = driver.observe(physicalIdentity: physicalIdentity),
                  target.matchesPhysicalIdentityAndVolumes(afterDetach),
                  Set(afterDetach.images.map(\.identity)) == expectedImageIDs.subtracting(Set([image.identity])) else {
                return fail(.topologyChanged, receipt)
            }
            detachedImageIDs.insert(image.identity)
            journal.phase = .imagesDetached; journal.completedSteps = completed
            guard persistEjectJournal(journal, intent: true, phase: "eject:images-detached") else { return fail(.stateConflict, receipt) }
        }
        guard let beforePhysicalUnmount = driver.observe(physicalIdentity: physicalIdentity),
              target.matchesPhysicalIdentityAndVolumes(beforePhysicalUnmount), beforePhysicalUnmount.images.isEmpty else {
            return fail(.topologyChanged)
        }
        journal.phase = .physicalVolumesUnmountIssued; journal.completedSteps = completed
        journal.lastIssuedAction = .physicalVolumesUnmount
        journal.lastReceipt = nil
        guard persistEjectJournal(journal, intent: true, phase: "eject:physical-unmount-issued") else { return fail(.stateConflict) }
        let physicalUnmount = driver.unmountAllPhysicalVolumesNonForce(target)
        journal.lastReceipt = physicalUnmount
        guard case .completed = physicalUnmount else {
            if case .partial(_, let members) = physicalUnmount {
                let knownMembers = Set(journal.target.volumes.map(\.identity))
                guard Set(members).count == members.count, members.allSatisfy(knownMembers.contains) else {
                    return fail(.actionFailed("partial physical-unmount receipt contains duplicate or unknown member identities"), physicalUnmount)
                }
                completed.append(contentsOf: members.map { "unmountPhysicalVolume:\($0)" })
            }
            return fail(.actionFailed(String(describing: physicalUnmount)), physicalUnmount)
        }
        completed.append("unmountAllPhysicalVolumes")
        guard let afterPhysicalUnmount = driver.observe(physicalIdentity: physicalIdentity),
              target.matchesPhysicalIdentityAndVolumes(afterPhysicalUnmount), afterPhysicalUnmount.images.isEmpty else {
            return fail(.topologyChanged, physicalUnmount)
        }
        guard afterPhysicalUnmount.volumes.allSatisfy({ !$0.mounted }),
              afterPhysicalUnmount.images.allSatisfy({ !$0.attached }) else {
            return fail(.membersStillMounted, physicalUnmount)
        }
        journal.phase = .physicalVolumesUnmounted; journal.completedSteps = completed
        guard persistEjectJournal(journal, intent: true, phase: "eject:physical-volumes-unmounted") else {
            return fail(.stateConflict, physicalUnmount)
        }
        guard let beforeEject = driver.observe(physicalIdentity: physicalIdentity),
              target.matchesPhysicalIdentityAndVolumes(beforeEject), beforeEject.images.isEmpty else {
            return fail(.topologyChanged)
        }
        guard beforeEject.volumes.allSatisfy({ !$0.mounted }), beforeEject.images.allSatisfy({ !$0.attached }) else {
            return fail(.membersStillMounted)
        }
        journal.phase = .ejectIssued; journal.completedSteps = completed
        journal.lastIssuedAction = .ejectWholeDevice
        journal.lastReceipt = nil
        journal.recoveryObservation = nil
        guard persistEjectJournal(journal, intent: true, phase: "eject:whole-device-issued") else { return fail(.stateConflict) }
        let ejectReceipt = driver.ejectWholeDeviceNonForce(target)
        journal.lastReceipt = ejectReceipt
        guard case .completed = ejectReceipt else { return fail(.actionFailed(String(describing: ejectReceipt)), ejectReceipt) }
        completed.append("ejectWholeDevice")
        journal.phase = .ejectCallbackSucceeded; journal.completedSteps = completed
        guard persistEjectJournal(journal, intent: true, phase: "eject:callback-succeeded") else { return fail(.stateConflict, ejectReceipt) }
        switch driver.presence(physicalIdentity: physicalIdentity) {
        case .absent:
            journal.phase = .verifiedAbsent; journal.completedSteps = completed
            guard persistEjectJournal(journal, intent: true, phase: "eject:verified-absent", terminal: "safe-to-unplug") else {
                return fail(.stateConflict, ejectReceipt)
            }
            return .init(operationID: operationID, completedSteps: completed, canUnplug: true)
        case .present: return fail(.absenceUnverified("target remains present"), ejectReceipt)
        case .unknown(let reason): return fail(.absenceUnverified(reason), ejectReceipt)
        }
    }

    /// Explicit Return is separate from eject and clears automation suppression only after a
    /// fresh exact physical/image/APFS validation supplied by the same runtime adapter.
    func returnFromWholeDeviceEject(driver: WholeDeviceEjectDriving) -> Bool {
        guard lock.acquire() else { return false }
        defer { lock.release() }
        guard let state = try? store.load(), state.ejectIntent,
              let journal = decodeEjectJournal(state.workbenchTarget) else { return false }
        let allImagesDurablyDetached = journal.target.images.allSatisfy { image in
            journal.completedSteps.contains("detachImage:\(image.identity)")
        }
        let noPhysicalMutationStarted = journal.lastIssuedAction != .physicalVolumesUnmount
            && journal.lastIssuedAction != .ejectWholeDevice
            && !journal.completedSteps.contains { step in
                step.hasPrefix("unmountPhysicalVolume") || step.hasPrefix("ejectWholeDevice")
            }
        let busyImageReceipt: Bool = {
            guard case .busy? = journal.lastReceipt else { return false }
            return true
        }()
        let recoverableBusyImageState = journal.phase == .interrupted
            && journal.lastIssuedAction == .imageVolumesUnmount && busyImageReceipt
            && !journal.target.images.isEmpty && noPhysicalMutationStarted
            && !journal.completedSteps.contains { $0.hasPrefix("detachImage:") }
        let returnBoundaryIsRecoverable = journal.phase == .verifiedAbsent
            || (journal.phase == .imagesDetached && allImagesDurablyDetached
                && journal.lastIssuedAction == .imageDetach)
            || recoverableBusyImageState
        guard returnBoundaryIsRecoverable, driver.freshReturnIdentityMatches(journal) else { return false }
        let returned = StoragePersistentState(revision: state.revision + 1, ejectIntent: false,
            operationID: journal.operationID, outerDisappearedAfterIntent: false,
            outerReconnectAttempted: false, workbenchOperation: nil, workbenchPhase: "eject:return-validated",
            workbenchTarget: nil, workbenchCompletedStep: nil, workbenchTerminalResult: "returned-to-development")
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: returned)) == true
    }

    /// Read-only counterpart used by UI availability. The mutating Return path repeats every
    /// check under the same lock, so this observation cannot itself authorize a later mutation.
    func canReturnFromWholeDeviceEject(driver: WholeDeviceEjectDriving) -> Bool {
        guard lock.acquire() else { return false }
        defer { lock.release() }
        guard let state = try? store.load(), state.ejectIntent,
              let journal = decodeEjectJournal(state.workbenchTarget) else { return false }
        let allImagesDurablyDetached = journal.target.images.allSatisfy { image in
            journal.completedSteps.contains("detachImage:\(image.identity)")
        }
        let noPhysicalMutationStarted = journal.lastIssuedAction != .physicalVolumesUnmount
            && journal.lastIssuedAction != .ejectWholeDevice
            && !journal.completedSteps.contains { $0.hasPrefix("unmountPhysicalVolume") || $0.hasPrefix("ejectWholeDevice") }
        let busyImageBoundary: Bool = {
            guard journal.phase == .interrupted, journal.lastIssuedAction == .imageVolumesUnmount,
                  case .busy? = journal.lastReceipt else { return false }
            return !journal.target.images.isEmpty && noPhysicalMutationStarted
                && !journal.completedSteps.contains { $0.hasPrefix("detachImage:") }
        }()
        let recoverable = journal.phase == .verifiedAbsent
            || (journal.phase == .imagesDetached && allImagesDurablyDetached && journal.lastIssuedAction == .imageDetach)
            || busyImageBoundary
        return recoverable && driver.freshReturnIdentityMatches(journal)
    }

    /// Continues only a journaled physical-volume unmount after a new exact user checkpoint.
    /// It reobserves the original member identities, skips only durably recorded completions,
    /// and retains eject intent until verified physical absence.
    func continueWholeExternalDeviceEject(checkpoint: WholeDeviceEjectCheckpoint,
                                          driver: WholeDeviceEjectDriving) -> WholeDeviceEjectResult {
        let operationID = UUID().uuidString
        guard checkpoint.confirmedExactTargetAndScope && checkpoint.knownWritersClosed
                && checkpoint.dependenciesCanFinishOffTarget else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .checkpointRequired)
        }
        guard lock.acquire() else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .operationPending)
        }
        defer { lock.release() }
        guard let state = try? store.load(), state.ejectIntent,
              state.workbenchOperation == "eject:\(state.operationID ?? "")",
              var journal = decodeEjectJournal(state.workbenchTarget),
              journal.operationID == state.operationID,
              journal.target.isExternal, journal.target.isWholeDevice, !journal.target.isSystemDevice,
              journal.target.inventoryComplete, journal.target.hasUniqueMembers,
              journal.target.images.allSatisfy({ journal.completedSteps.contains("detachImage:\($0.identity)") }),
              checkpoint.permitsRequest(for: journal.target) else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .returnTargetMismatch)
        }
        let recoveringIssuedEject = journal.phase == .ejectIssued && journal.lastIssuedAction == .ejectWholeDevice
        if recoveringIssuedEject {
            switch driver.freshEjectIssuedRecovery(journal) {
            case .exactTargetAbsent:
                journal.phase = .verifiedAbsent
                journal.recoveryObservation = .exactTargetAbsentAfterEjectIssue
                guard persistEjectJournal(journal, intent: true, phase: "eject:verified-absent-after-issued-recovery", terminal: "safe-to-unplug") else {
                    return .init(operationID: journal.operationID, completedSteps: journal.completedSteps,
                                 canUnplug: false, failure: .stateConflict)
                }
                return .init(operationID: journal.operationID,
                             completedSteps: journal.completedSteps + ["observeWholeDeviceAbsentAfterEjectIssue"],
                             canUnplug: true)
            case .exactTargetPresentUnmounted:
                journal.recoveryObservation = .exactTargetPresentUnmountedAfterEjectIssue
            case .refused:
                return .init(operationID: journal.operationID, completedSteps: [], canUnplug: false,
                             failure: .returnTargetMismatch)
            }
        } else {
            guard journal.lastIssuedAction == .physicalVolumesUnmount,
                  journal.phase == .interrupted || journal.phase == .physicalVolumesUnmountIssued
                    || journal.phase == .physicalVolumesUnmounted,
                  driver.freshPhysicalContinuationMatches(journal) else {
                return .init(operationID: operationID, completedSteps: [], canUnplug: false,
                             failure: .returnTargetMismatch)
            }
        }
        var completed = journal.completedSteps
        func fail(_ reason: WholeDeviceEjectFailure, _ receipt: WholeDeviceActionReceipt? = nil) -> WholeDeviceEjectResult {
            journal.phase = .interrupted
            journal.completedSteps = completed
            if let receipt { journal.lastReceipt = receipt }
            _ = persistEjectJournal(journal, intent: true, phase: "eject:interrupted")
            return .init(operationID: journal.operationID, completedSteps: completed, canUnplug: false, failure: reason)
        }

        let allPhysicalVolumesRecorded = journal.target.volumes.allSatisfy { volume in
            completed.contains("unmountPhysicalVolume:\(volume.identity)")
        } || completed.contains("unmountAllPhysicalVolumes")
        if !allPhysicalVolumesRecorded {
            journal.phase = .physicalVolumesUnmountIssued
            journal.lastIssuedAction = .physicalVolumesUnmount
            journal.lastReceipt = nil
            journal.completedSteps = completed
            guard persistEjectJournal(journal, intent: true, phase: "eject:physical-unmount-issued") else {
                return fail(.stateConflict)
            }
            let receipt = driver.unmountAllPhysicalVolumesNonForce(journal.target)
            journal.lastReceipt = receipt
            guard case .completed = receipt else {
                if case .partial(_, let members) = receipt {
                    let valid = Set(journal.target.volumes.map(\.identity))
                    guard Set(members).count == members.count, members.allSatisfy(valid.contains) else {
                        return fail(.actionFailed("partial physical-unmount receipt contains duplicate or unknown member identities"), receipt)
                    }
                    completed.append(contentsOf: members.filter { !completed.contains("unmountPhysicalVolume:\($0)") }
                        .map { "unmountPhysicalVolume:\($0)" })
                }
                return fail(.actionFailed(String(describing: receipt)), receipt)
            }
            completed.append("unmountAllPhysicalVolumes")
            guard let after = driver.observe(physicalIdentity: journal.target.physicalIdentity),
                  journal.target.matchesPhysicalIdentityAndVolumes(after), after.images.isEmpty,
                  after.volumes.allSatisfy({ !$0.mounted }) else { return fail(.topologyChanged, receipt) }
            journal.phase = .physicalVolumesUnmounted
            journal.completedSteps = completed
            guard persistEjectJournal(journal, intent: true, phase: "eject:physical-volumes-unmounted") else {
                return fail(.stateConflict, receipt)
            }
        }
        guard let beforeEject = driver.observe(physicalIdentity: journal.target.physicalIdentity),
              journal.target.matchesPhysicalIdentityAndVolumes(beforeEject), beforeEject.images.isEmpty,
              beforeEject.volumes.allSatisfy({ !$0.mounted }) else { return fail(.topologyChanged) }
        journal.phase = .ejectIssued
        journal.lastIssuedAction = .ejectWholeDevice
        journal.lastReceipt = nil
        journal.recoveryObservation = nil
        journal.completedSteps = completed
        guard persistEjectJournal(journal, intent: true, phase: "eject:whole-device-issued") else {
            return fail(.stateConflict)
        }
        let receipt = driver.ejectWholeDeviceNonForce(journal.target)
        journal.lastReceipt = receipt
        guard case .completed = receipt else { return fail(.actionFailed(String(describing: receipt)), receipt) }
        completed.append("ejectWholeDevice")
        journal.phase = .ejectCallbackSucceeded
        journal.completedSteps = completed
        guard persistEjectJournal(journal, intent: true, phase: "eject:callback-succeeded") else {
            return fail(.stateConflict, receipt)
        }
        switch driver.presence(physicalIdentity: journal.target.physicalIdentity) {
        case .absent:
            journal.phase = .verifiedAbsent
            guard persistEjectJournal(journal, intent: true, phase: "eject:verified-absent", terminal: "safe-to-unplug") else {
                return fail(.stateConflict, receipt)
            }
            return .init(operationID: journal.operationID, completedSteps: completed, canUnplug: true)
        case .present: return fail(.absenceUnverified("target remains present"), receipt)
        case .unknown(let detail): return fail(.absenceUnverified(detail), receipt)
        }
    }

    private func persistEjectJournal(_ journal: WholeDeviceEjectJournalRecord,
                                     state supplied: StoragePersistentState? = nil, intent: Bool,
                                     phase: String, terminal: String? = nil) -> Bool {
        guard let state = supplied ?? (try? store.load()),
              let data = try? JSONEncoder().encode(journal), data.count <= 48_000 else { return false }
        let encoded = data.base64EncodedString()
        let next = StoragePersistentState(revision: state.revision + 1, ejectIntent: intent,
            operationID: journal.operationID, outerDisappearedAfterIntent: journal.phase == .verifiedAbsent,
            outerReconnectAttempted: false, workbenchOperation: "eject:\(journal.operationID)",
            workbenchPhase: phase, workbenchTarget: encoded,
            workbenchCompletedStep: journal.completedSteps.last, workbenchTerminalResult: terminal)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func decodeEjectJournal(_ value: String?) -> WholeDeviceEjectJournalRecord? {
        guard let value, let data = Data(base64Encoded: value), data.count <= 48_000 else { return nil }
        return try? JSONDecoder().decode(WholeDeviceEjectJournalRecord.self, from: data)
    }
}
