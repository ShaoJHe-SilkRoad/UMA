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
            && stablePhysicalVolumeIdentities?.count == volumes.count
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

    /// A terminal Return can see the same media at a new BSD number. Match stable physical
    /// and APFS member identities here; mutating steps deliberately retain the stricter
    /// `matchesPhysicalIdentityAndVolumes` check and dispatch from a fresh observation.
    public func matchesStablePhysicalIdentityAndVolumes(_ other: Self) -> Bool {
        physicalIdentity == other.physicalIdentity
            && isWholeDevice && other.isWholeDevice && isExternal && other.isExternal
            && !isSystemDevice && !other.isSystemDevice
            && inventoryComplete && other.inventoryComplete && hasUniqueMembers && other.hasUniqueMembers
            && stablePhysicalVolumeIdentities == other.stablePhysicalVolumeIdentities
    }

    /// No action was issued after the confirmed snapshot. An explicit cancellation may
    /// accept newly discovered members, but only on a freshly verified, complete target
    /// containing every original stable member and the original attached image inventory.
    public func canCancelUnissuedEject(on current: Self) -> Bool {
        guard physicalIdentity == current.physicalIdentity,
              isWholeDevice && current.isWholeDevice && isExternal && current.isExternal,
              !isSystemDevice && !current.isSystemDevice,
              inventoryComplete && current.inventoryComplete,
              hasUniqueMembers && current.hasUniqueMembers,
              let originalMembers = stablePhysicalVolumeIdentities,
              let currentMembers = current.stablePhysicalVolumeIdentities,
              originalMembers.isSubset(of: currentMembers),
              Set(images) == Set(current.images) else { return false }
        return true
    }

    private var stablePhysicalVolumeIdentities: Set<String>? {
        let identities = volumes.compactMap { Self.stablePhysicalVolumeIdentity($0.identity) }
        guard identities.count == volumes.count else { return nil }
        return Set(identities)
    }

    private static func stablePhysicalVolumeIdentity(_ identity: String) -> String? {
        let components = identity.split(separator: "|", omittingEmptySubsequences: false)
        if components.count == 1 { return identity.isEmpty ? nil : identity }
        guard components.count == 2,
              let uuid = UUID(uuidString: String(components[0])),
              String(components[1]).range(of: #"^disk[0-9]+(?:s[0-9]+)+$"#, options: .regularExpression) != nil
        else { return nil }
        return uuid.uuidString.lowercased()
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

    /// A successful eject callback needs only a fresh identity/absence observation. No disk
    /// action follows, so writer closure and off-target execution are not preconditions here.
    public func permitsReadOnlyRecheck(for target: WholeDeviceTopology, now: Date = Date()) -> Bool {
        guard confirmedExactTargetAndScope,
              confirmedPhysicalIdentity == target.physicalIdentity,
              confirmedMemberKey == target.memberKey,
              target.inventoryComplete, target.hasUniqueMembers,
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
    /// Safety-bearing absence checks carry the original observed target. A missing ID alone
    /// cannot prove that physical media with degraded identity has disappeared.
    func presence(of target: WholeDeviceTopology) -> WholeDevicePresence
    /// Read-only postcondition used only after the exact whole-device eject succeeded.
    /// macOS may keep the USB device node enumerated until the cable is unplugged.
    func successfulEjectHasUnmountedPostcondition(of target: WholeDeviceTopology) -> Bool
    func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool
    func freshPhysicalContinuationMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool
    func freshEjectIssuedRecovery(_ journal: WholeDeviceEjectJournalRecord) -> WholeDeviceEjectIssuedRecovery
}

public extension WholeDeviceEjectDriving {
    func successfulEjectHasUnmountedPostcondition(of target: WholeDeviceTopology) -> Bool { false }
    func presence(of target: WholeDeviceTopology) -> WholeDevicePresence {
        .unknown("target-aware physical presence is unavailable")
    }
    func freshPhysicalContinuationMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool { false }
    func freshEjectIssuedRecovery(_ journal: WholeDeviceEjectJournalRecord) -> WholeDeviceEjectIssuedRecovery { .refused }
}

public struct WholeDeviceEjectJournalRecord: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case prepared, imageVolumesUnmountIssued, imageVolumesUnmounted, imageDetachIssued, imagesDetached
        case physicalVolumesUnmountIssued, physicalVolumesUnmounted
        case ejectIssued, ejectCallbackSucceeded, ejected, verifiedAbsent, disconnected, interrupted
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

    /// Both terminal states carry an OS eject receipt; only verifiedAbsent also proves
    /// the device is no longer enumerated. Ejected media can safely remain plugged in.
    public var safelyEjected: Bool { phase == .ejected || phase == .verifiedAbsent }

    /// The durable journal proves this operation never dispatched a storage action.
    public var canCancelUnissuedEject: Bool {
        (phase == .prepared || phase == .interrupted)
            && lastIssuedAction == nil && lastReceipt == nil
            && completedSteps.isEmpty && recoveryObservation == nil
    }

    /// A durable successful callback with an unresolved final presence probe can only be
    /// rechecked; it must never issue another eject or infer safe removal from the callback alone.
    public var successfulEjectCallbackRequiresRecheck: Bool {
        guard phase == .ejectCallbackSucceeded || phase == .interrupted,
              lastIssuedAction == .ejectWholeDevice,
              case .completed? = lastReceipt,
              completedSteps.contains("ejectWholeDevice") else { return false }
        return completedSteps.contains("unmountAllPhysicalVolumes")
            || target.volumes.allSatisfy { completedSteps.contains("unmountPhysicalVolume:\($0.identity)") }
    }

    /// After every volume was unmounted and the whole-device eject was issued, a
    /// freshly verified mounted instance is a return to use even if the process
    /// lost the eject receipt or missed the disappearance event. This permits
    /// read-only reconciliation, never another mutation or a safe-unplug claim.
    public var issuedEjectCanReconcileRemount: Bool {
        guard lastIssuedAction == .ejectWholeDevice,
              phase == .ejectIssued || phase == .ejectCallbackSucceeded || phase == .interrupted,
              target.images.allSatisfy({ completedSteps.contains("detachImage:\($0.identity)") }) else { return false }
        return completedSteps.contains("unmountAllPhysicalVolumes")
            || target.volumes.allSatisfy { completedSteps.contains("unmountPhysicalVolume:\($0.identity)") }
    }
}

/// Used by StorageController under its existing shared lock and durable state store. The encoded
/// journal is stored in the existing workbench target slot while the eject intent suppresses
/// automation. Verified eject completion moves the journal to a target-scoped terminal slot and frees the
/// active slot. No generic resume path may consume an in-progress journal.
public extension StorageController {
    func ejectWholeExternalDevice(physicalIdentity: String, checkpoint: WholeDeviceEjectCheckpoint,
                                  driver: WholeDeviceEjectDriving,
                                  affectedProfileIDs: Set<String> = []) -> WholeDeviceEjectResult {
        let operationID = UUID().uuidString
        guard checkpoint.confirmedExactTargetAndScope && checkpoint.knownWritersClosed
                && checkpoint.dependenciesCanFinishOffTarget,
              affectedProfileIDs.allSatisfy(StoragePersistentState.validProfileID) else {
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
        guard state.terminalEjectJournals[physicalIdentity] == nil else {
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
        guard persistEjectJournal(journal, state: state, intent: true, phase: "eject:prepared",
                                  additionalSuppressedProfileIDs: affectedProfileIDs) else {
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
        return finalizeSuccessfulEject(journal, driver: driver)
    }

    /// Explicit Return closes an active legacy journal only after fresh exact validation.
    /// A completed target-scoped journal requires the physical-identity overload below.
    func returnFromWholeDeviceEject(driver: WholeDeviceEjectDriving) -> Bool {
        guard lock.acquire() else { return false }
        defer { lock.release() }
        guard let state = try? store.load(), let journal = activeEjectJournal(in: state),
              returnBoundaryIsRecoverable(journal), driver.freshReturnIdentityMatches(journal) else { return false }
        return persistValidatedReturn(journal, state: state)
    }

    /// Completed ejects remain available by exact target after the global active slot is freed.
    /// Return itself never clears per-profile suppression; only a validated manual load may do so.
    func returnFromWholeDeviceEject(physicalIdentity: String, driver: WholeDeviceEjectDriving) -> Bool {
        guard lock.acquire() else { return false }
        defer { lock.release() }
        guard let state = try? store.load() else { return false }
        if let active = activeEjectJournal(in: state) {
            guard active.target.physicalIdentity == physicalIdentity,
                  returnBoundaryIsRecoverable(active), driver.freshReturnIdentityMatches(active) else { return false }
            return persistValidatedReturn(active, state: state)
        }
        guard let terminal = terminalEjectJournal(for: physicalIdentity, in: state),
              driver.freshReturnIdentityMatches(terminal) else { return false }
        return persistValidatedReturn(terminal, state: state, terminalPhysicalIdentity: physicalIdentity)
    }

    /// Read-only availability; the mutating Return path repeats every check under the lock.
    func canReturnFromWholeDeviceEject(driver: WholeDeviceEjectDriving) -> Bool {
        guard lock.acquire() else { return false }
        defer { lock.release() }
        guard let state = try? store.load(), let journal = activeEjectJournal(in: state) else { return false }
        return returnBoundaryIsRecoverable(journal) && driver.freshReturnIdentityMatches(journal)
    }

    func canReturnFromWholeDeviceEject(physicalIdentity: String, driver: WholeDeviceEjectDriving) -> Bool {
        guard lock.acquire() else { return false }
        defer { lock.release() }
        guard let state = try? store.load() else { return false }
        if let active = activeEjectJournal(in: state) {
            return active.target.physicalIdentity == physicalIdentity
                && returnBoundaryIsRecoverable(active) && driver.freshReturnIdentityMatches(active)
        }
        guard let terminal = terminalEjectJournal(for: physicalIdentity, in: state) else { return false }
        return driver.freshReturnIdentityMatches(terminal)
    }

    /// Reconcile native appearance/disappearance without issuing a storage action. An absent
    /// target releases the operation slot even after an interrupted request, but only a
    /// durable successful eject callback earns the safe-to-unplug result. A fresh complete
    /// mounted identity after an issued eject can resume use without proving the earlier
    /// eject succeeded. It never repeats that old eject. Compare-and-swap and the shared lock prevent stale observations
    /// from overwriting a concurrent action.
    func reconcileWholeDeviceEjectRecovery(physicalIdentity: String,
                                           driver: WholeDeviceEjectDriving,
                                           affectedProfileIDs: Set<String> = []) -> Bool {
        guard lock.acquire() else { return false }
        defer { lock.release() }
        guard let state = try? store.load() else { return false }
        if var journal = activeEjectJournal(in: state) {
            guard journal.target.physicalIdentity == physicalIdentity,
                  journal.target.isWholeDevice, journal.target.isExternal, !journal.target.isSystemDevice,
                  journal.target.inventoryComplete, journal.target.hasUniqueMembers else { return false }
            switch driver.presence(of: journal.target) {
            case .unknown: return false
            case .absent:
                let safelyEjected = journal.successfulEjectCallbackRequiresRecheck
                journal.phase = safelyEjected ? .verifiedAbsent : .disconnected
                return archiveTerminalEjectJournal(journal,
                    phase: safelyEjected ? "eject:verified-absent" : "eject:disconnected",
                    disconnectedProfileIDs: affectedProfileIDs)
            case .present:
                if journal.successfulEjectCallbackRequiresRecheck,
                   driver.successfulEjectHasUnmountedPostcondition(of: journal.target) {
                    journal.phase = .ejected
                    return archiveTerminalEjectJournal(journal, phase: "eject:completed",
                        disconnectedProfileIDs: affectedProfileIDs)
                }
                guard journal.issuedEjectCanReconcileRemount,
                      driver.freshReturnIdentityMatches(journal) else { return false }
                return persistValidatedReturn(journal, state: state,
                    reconnectedProfileIDs: affectedProfileIDs)
            }
        }
        if let terminal = terminalEjectJournal(for: physicalIdentity, in: state) {
            guard driver.presence(of: terminal.target) == .present,
                  driver.freshReturnIdentityMatches(terminal) else { return false }
            return persistValidatedReturn(terminal, state: state,
                terminalPhysicalIdentity: physicalIdentity, reconnectedProfileIDs: affectedProfileIDs)
        }
        // Older returns released the operation and removed the terminal journal,
        // but left these profiles disconnected/suppressed. Reconcile that exact
        // retained receipt only after the current disk and profile chain validate.
        guard !state.ejectIntent, state.workbenchOperation == nil,
              state.terminalEjectJournals[physicalIdentity] == nil,
              state.workbenchPhase == "eject:return-validated",
              state.workbenchTerminalResult == "returned-to-development",
              !affectedProfileIDs.isDisjoint(with: state.suppressedProfileIDs.union(state.disconnectedProfileIDs)),
              let returned = decodeEjectJournal(state.workbenchTarget),
              returned.operationID == state.operationID,
              returned.target.physicalIdentity == physicalIdentity,
              returned.target.isWholeDevice, returned.target.isExternal, !returned.target.isSystemDevice,
              returned.target.inventoryComplete, returned.target.hasUniqueMembers,
              returnBoundaryIsRecoverable(returned),
              driver.presence(of: returned.target) == .present,
              driver.freshReturnIdentityMatches(returned) else { return false }
        return persistValidatedReturn(returned, state: state, reconnectedProfileIDs: affectedProfileIDs)
    }

    private func activeEjectJournal(in state: StoragePersistentState) -> WholeDeviceEjectJournalRecord? {
        guard state.ejectIntent, let journal = decodeEjectJournal(state.workbenchTarget),
              state.operationID == journal.operationID,
              state.workbenchOperation == "eject:\(journal.operationID)" else { return nil }
        return journal
    }

    private func terminalEjectJournal(for physicalIdentity: String,
                                      in state: StoragePersistentState) -> WholeDeviceEjectJournalRecord? {
        guard !state.ejectIntent, state.workbenchOperation == nil,
              let encoded = state.terminalEjectJournals[physicalIdentity],
              let journal = decodeEjectJournal(encoded),
              journal.safelyEjected || journal.phase == .disconnected,
              !journal.operationID.isEmpty, journal.target.physicalIdentity == physicalIdentity,
              journal.target.isWholeDevice, journal.target.isExternal, !journal.target.isSystemDevice,
              journal.target.inventoryComplete, journal.target.hasUniqueMembers else { return nil }
        return journal
    }

    private func returnBoundaryIsRecoverable(_ journal: WholeDeviceEjectJournalRecord) -> Bool {
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
        let returnBoundaryIsRecoverable = journal.safelyEjected || journal.phase == .disconnected
            || journal.successfulEjectCallbackRequiresRecheck
            || journal.issuedEjectCanReconcileRemount
            || journal.canCancelUnissuedEject
            || (journal.phase == .imagesDetached && allImagesDurablyDetached
                && journal.lastIssuedAction == .imageDetach)
            || recoverableBusyImageState
        return returnBoundaryIsRecoverable
    }

    private func persistValidatedReturn(_ journal: WholeDeviceEjectJournalRecord,
                                        state: StoragePersistentState,
                                        terminalPhysicalIdentity: String? = nil,
                                        reconnectedProfileIDs: Set<String> = []) -> Bool {
        var returned = state.advancingRevision()
        if let terminalPhysicalIdentity {
            returned.terminalEjectJournals.removeValue(forKey: terminalPhysicalIdentity)
        }
        returned.ejectIntent = false
        returned.operationID = journal.operationID
        returned.outerDisappearedAfterIntent = false
        returned.outerReconnectAttempted = false
        returned.workbenchOperation = nil
        returned.workbenchPhase = "eject:return-validated"
        // Retain the native receipt as history, without retaining an active operation.
        returned.workbenchTarget = (try? JSONEncoder().encode(journal))?.base64EncodedString()
        returned.workbenchCompletedStep = nil
        returned.workbenchTerminalResult = "returned-to-development"
        // A verified new connection is no longer disconnected, and the old
        // connection's eject intent must not disable Load or its auto-load policy.
        // Explicit cancellation on the same connection passes no profile IDs and
        // keeps suppression until an intentional Load succeeds.
        returned.suppressedProfileIDs.subtract(reconnectedProfileIDs)
        returned.disconnectedProfileIDs.subtract(reconnectedProfileIDs)
        returned.reconnectAttemptedProfileIDs.subtract(reconnectedProfileIDs)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: returned)) == true
    }

    /// Continues only a journaled physical-volume unmount after a new exact user checkpoint.
    /// It reobserves the original member identities, skips only durably recorded completions,
    /// and retains eject intent until native eject completion is freshly verified.
    func continueWholeExternalDeviceEject(checkpoint: WholeDeviceEjectCheckpoint,
                                          driver: WholeDeviceEjectDriving) -> WholeDeviceEjectResult {
        let operationID = UUID().uuidString
        guard checkpoint.confirmedExactTargetAndScope else {
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
              journal.target.images.allSatisfy({ journal.completedSteps.contains("detachImage:\($0.identity)") }) else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .returnTargetMismatch)
        }
        let callbackOnlyRecheck = journal.successfulEjectCallbackRequiresRecheck
        guard callbackOnlyRecheck ? checkpoint.permitsReadOnlyRecheck(for: journal.target)
                                  : checkpoint.permitsRequest(for: journal.target) else {
            return .init(operationID: operationID, completedSteps: [], canUnplug: false, failure: .checkpointRequired)
        }
        if journal.safelyEjected {
            guard archiveTerminalEjectJournal(journal, phase: journal.phase == .ejected ? "eject:completed" : "eject:verified-absent") else {
                return .init(operationID: journal.operationID, completedSteps: journal.completedSteps,
                             canUnplug: false, failure: .stateConflict)
            }
            return .init(operationID: journal.operationID, completedSteps: journal.completedSteps, canUnplug: true)
        }
        if callbackOnlyRecheck {
            return finalizeSuccessfulEject(journal, driver: driver)
        }
        let recoveringIssuedEject = journal.phase == .ejectIssued && journal.lastIssuedAction == .ejectWholeDevice
        if recoveringIssuedEject {
            switch driver.freshEjectIssuedRecovery(journal) {
            case .exactTargetAbsent:
                journal.phase = .disconnected
                journal.recoveryObservation = .exactTargetAbsentAfterEjectIssue
                guard archiveTerminalEjectJournal(journal, phase: "eject:disconnected-after-issued-recovery") else {
                    return .init(operationID: journal.operationID, completedSteps: journal.completedSteps,
                                 canUnplug: false, failure: .stateConflict)
                }
                return .init(operationID: journal.operationID,
                             completedSteps: journal.completedSteps + ["observeWholeDeviceAbsentAfterEjectIssue"],
                             canUnplug: false, failure: .absenceUnverified("Drive is disconnected; the interrupted eject has no completion receipt"))
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
        return finalizeSuccessfulEject(journal, driver: driver)
    }

    /// A successful macOS eject does not require the user to physically unplug the cable.
    /// Preserve actual absence separately from a still-enumerated, fully unmounted target.
    private func finalizeSuccessfulEject(_ saved: WholeDeviceEjectJournalRecord,
                                         driver: WholeDeviceEjectDriving) -> WholeDeviceEjectResult {
        var journal = saved
        guard journal.successfulEjectCallbackRequiresRecheck else {
            return .init(operationID: journal.operationID, completedSteps: journal.completedSteps,
                         canUnplug: false, failure: .returnTargetMismatch)
        }
        switch driver.presence(of: journal.target) {
        case .absent:
            journal.phase = .verifiedAbsent
        case .present:
            guard driver.successfulEjectHasUnmountedPostcondition(of: journal.target) else {
                return .init(operationID: journal.operationID, completedSteps: journal.completedSteps,
                             canUnplug: false, failure: .absenceUnverified("ejected target has mounted, attached, changed or unverified members"))
            }
            journal.phase = .ejected
        case .unknown(let detail):
            return .init(operationID: journal.operationID, completedSteps: journal.completedSteps,
                         canUnplug: false, failure: .absenceUnverified(detail))
        }
        guard archiveTerminalEjectJournal(journal,
                phase: journal.phase == .ejected ? "eject:completed" : "eject:verified-absent") else {
            return .init(operationID: journal.operationID, completedSteps: journal.completedSteps,
                         canUnplug: false, failure: .stateConflict)
        }
        return .init(operationID: journal.operationID, completedSteps: journal.completedSteps, canUnplug: true)
    }

    /// A single CAS moves authoritative completion out of the active slot. A failed CAS leaves
    /// the prior in-progress journal intact for explicit recovery; it cannot report success.
    private func archiveTerminalEjectJournal(_ journal: WholeDeviceEjectJournalRecord,
                                                   phase: String,
                                                   disconnectedProfileIDs: Set<String> = []) -> Bool {
        guard journal.safelyEjected || journal.phase == .disconnected,
              journal.target.isWholeDevice, journal.target.isExternal, !journal.target.isSystemDevice,
              journal.target.inventoryComplete, journal.target.hasUniqueMembers,
              let state = try? store.load(), state.ejectIntent,
              state.operationID == journal.operationID,
              state.workbenchOperation == "eject:\(journal.operationID)",
              state.terminalEjectJournals[journal.target.physicalIdentity] == nil,
              let data = try? JSONEncoder().encode(journal), data.count <= 48_000 else { return false }
        var next = state.advancingRevision()
        next.terminalEjectJournals[journal.target.physicalIdentity] = data.base64EncodedString()
        next.ejectIntent = false
        next.operationID = nil
        next.outerDisappearedAfterIntent = false
        next.outerReconnectAttempted = false
        next.workbenchOperation = nil
        next.workbenchPhase = phase
        next.workbenchTarget = nil
        next.workbenchCompletedStep = journal.completedSteps.last
        next.workbenchTerminalResult = journal.safelyEjected
            ? "safe-to-unplug" : "disconnected-without-eject-confirmation"
        next.disconnectedProfileIDs.formUnion(disconnectedProfileIDs)
        next.reconnectAttemptedProfileIDs.subtract(disconnectedProfileIDs)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func persistEjectJournal(_ journal: WholeDeviceEjectJournalRecord,
                                     state supplied: StoragePersistentState? = nil, intent: Bool,
                                     phase: String,
                                     additionalSuppressedProfileIDs: Set<String> = []) -> Bool {
        guard let state = supplied ?? (try? store.load()),
              let data = try? JSONEncoder().encode(journal), data.count <= 48_000 else { return false }
        let encoded = data.base64EncodedString()
        var next = state.advancingRevision()
        next.ejectIntent = intent
        next.operationID = journal.operationID
        next.outerDisappearedAfterIntent = journal.phase == .verifiedAbsent
        next.outerReconnectAttempted = false
        next.suppressedProfileIDs.formUnion(additionalSuppressedProfileIDs)
        next.workbenchOperation = "eject:\(journal.operationID)"
        next.workbenchPhase = phase
        next.workbenchTarget = encoded
        next.workbenchCompletedStep = journal.completedSteps.last
        next.workbenchTerminalResult = nil
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func decodeEjectJournal(_ value: String?) -> WholeDeviceEjectJournalRecord? {
        guard let value, let data = Data(base64Encoded: value), data.count <= 48_000 else { return nil }
        return try? JSONDecoder().decode(WholeDeviceEjectJournalRecord.self, from: data)
    }
}
