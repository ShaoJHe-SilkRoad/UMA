import Foundation
import Testing
@testable import HESectoriumCore

private final class EjectTestStore: DurableStateStore {
    var state = StoragePersistentState(ejectIntent: false)
    func load() throws -> StoragePersistentState { state }
    func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
        guard state.revision == expectedRevision else { return false }; state = newState; return true
    }
}
private final class EjectTestLock: OperationLock {
    var held = false
    func acquire() -> Bool { guard !held else { return false }; held = true; return true }
    func release() { held = false }
}
private final class EjectTestStorage: StorageBackend {
    func observeOuter() -> VolumeIdentity? { nil }
    func observe() -> StorageObservation? { nil }
    func attachImage() -> CommandOutcome { .init(exitCode: -1) }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { .incomplete(reason: "unused") }
    func perform(_ step: EjectStep) -> CommandOutcome { .init(exitCode: -1) }
    func finalOuterState() -> FinalOuterState { .unknown("unused") }
}
private final class EjectTestDriver: WholeDeviceEjectDriving {
    var current: WholeDeviceTopology?
    var observations: [WholeDeviceTopology?] = []
    var receipt: WholeDeviceActionReceipt = .completed("fixture")
    var finalPresence: WholeDevicePresence = .absent
    var returnIdentityValid = false
    var continuationIdentityValid = false
    var issuedEjectRecovery: WholeDeviceEjectIssuedRecovery = .refused
    var calls: [String] = []
    init(_ topology: WholeDeviceTopology) { current = topology }
    func observe(physicalIdentity: String) -> WholeDeviceTopology? {
        calls.append("observe")
        if !observations.isEmpty { return observations.removeFirst() }
        return current?.physicalIdentity == physicalIdentity ? current : nil
    }
    func unmountImageVolumesNonForce(_ imageIdentity: String, volumeIdentities: [String], from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { calls.append("unmount-image:" + imageIdentity); return receipt }
    func detachImageNonForce(_ imageIdentity: String, from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { calls.append("detach:" + imageIdentity); return receipt }
    func unmountAllPhysicalVolumesNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt {
        calls.append("unmount-physical")
        if case .completed = receipt {
            current = WholeDeviceTopology(physicalIdentity: target.physicalIdentity, bsdName: target.bsdName,
                isWholeDevice: target.isWholeDevice, isExternal: target.isExternal, isSystemDevice: target.isSystemDevice,
                inventoryComplete: true, volumes: target.volumes.map { .init(identity: $0.identity, mounted: false) }, images: [])
        }
        return receipt
    }
    func ejectWholeDeviceNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt { calls.append("eject"); return receipt }
    func presence(physicalIdentity: String) -> WholeDevicePresence { calls.append("presence"); return finalPresence }
    func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool { calls.append("return-check"); return returnIdentityValid }
    func freshPhysicalContinuationMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool {
        calls.append("continue-check"); return continuationIdentityValid
    }
    func freshEjectIssuedRecovery(_ journal: WholeDeviceEjectJournalRecord) -> WholeDeviceEjectIssuedRecovery {
        calls.append("issued-eject-recovery-check"); return issuedEjectRecovery
    }
}
private let ejectFixture = WholeDeviceTopology(physicalIdentity: "media-uuid", bsdName: "disk88",
    isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
    volumes: [.init(identity: "volume-a", mounted: true), .init(identity: "volume-b", mounted: true)],
    images: [.init(identity: "image-a", attached: true, volumeIdentities: ["image-volume-a"], mountedVolumeIdentities: ["image-volume-a"])])
private let ejectCheckpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true,
    knownWritersClosed: true, dependenciesCanFinishOffTarget: true,
    confirmedPhysicalIdentity: ejectFixture.physicalIdentity, confirmedMemberKey: ejectFixture.memberKey,
    confirmedAt: Date())
private func ejectController(_ store: EjectTestStore, _ lock: EjectTestLock) -> StorageController {
    StorageController(backend: EjectTestStorage(), store: store, lock: lock)
}

@Test func explicitReturnRecoversInterruptedBusyImageBeforeDetach() throws {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    driver.returnIdentityValid = true
    let journal = WholeDeviceEjectJournalRecord(operationID: "busy-image", target: ejectFixture,
        phase: .interrupted, completedSteps: ["unmountImageVolumes:image-a"],
        lastReceipt: .busy("fixture writer remains"), lastIssuedAction: .imageVolumesUnmount)
    store.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:\(journal.operationID)", workbenchPhase: "eject:interrupted",
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())

    #expect(ejectController(store, lock).returnFromWholeDeviceEject(driver: driver))
    #expect(!store.state.ejectIntent)
    #expect(driver.calls == ["return-check"])
}

@Test func missingCheckpointRefusesBeforeIntentOrMutation() {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    let result = ejectController(store, lock).ejectWholeExternalDevice(physicalIdentity: "media-uuid",
        checkpoint: .init(confirmedExactTargetAndScope: true, knownWritersClosed: false, dependenciesCanFinishOffTarget: true,
            confirmedPhysicalIdentity: ejectFixture.physicalIdentity, confirmedMemberKey: ejectFixture.memberKey,
            confirmedAt: Date()), driver: driver)
    #expect(result.failure == .checkpointRequired && !store.state.ejectIntent && driver.calls.isEmpty)
}

@Test func staleOrDifferentMemberCheckpointRefusesBeforeIntentOrMutation() {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    let stale = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: true,
        dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: ejectFixture.physicalIdentity,
        confirmedMemberKey: "different-member-set", confirmedAt: Date().addingTimeInterval(-300))
    let result = ejectController(store, lock).ejectWholeExternalDevice(physicalIdentity: "media-uuid",
        checkpoint: stale, driver: driver)
    #expect(result.failure == .checkpointRequired)
    #expect(!store.state.ejectIntent && driver.calls == ["observe"])
}

@Test func localSystemOrIncompleteTopologyRefusesBeforeUnmount() {
    let unsafe = [
        WholeDeviceTopology(physicalIdentity: "media-uuid", bsdName: "disk88", isWholeDevice: true, isExternal: false, isSystemDevice: false, inventoryComplete: true, volumes: ejectFixture.volumes, images: ejectFixture.images),
        WholeDeviceTopology(physicalIdentity: "media-uuid", bsdName: "disk88", isWholeDevice: true, isExternal: true, isSystemDevice: true, inventoryComplete: true, volumes: ejectFixture.volumes, images: ejectFixture.images),
        WholeDeviceTopology(physicalIdentity: "media-uuid", bsdName: "disk88", isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: false, volumes: ejectFixture.volumes, images: ejectFixture.images)
    ]
    for target in unsafe {
        let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(target)
        let result = ejectController(store, lock).ejectWholeExternalDevice(physicalIdentity: target.physicalIdentity, checkpoint: ejectCheckpoint, driver: driver)
        #expect(result.failure == .unsafeTarget || result.failure == .incompleteTopology)
        #expect(!driver.calls.contains("unmount-image:image-a") && !driver.calls.contains("unmount-physical"))
    }
}

@Test func multipleMembersAreRecheckedAndAllUnmountedBeforeImageDetachAndEject() {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    let imageVolumesUnmounted = WholeDeviceTopology(physicalIdentity: "media-uuid", bsdName: "disk88", isWholeDevice: true,
        isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: ejectFixture.volumes,
        images: [.init(identity: "image-a", attached: true, volumeIdentities: ["image-volume-a"], mountedVolumeIdentities: [])])
    let imagesDetached = WholeDeviceTopology(physicalIdentity: "media-uuid", bsdName: "disk88", isWholeDevice: true,
        isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: ejectFixture.volumes, images: [])
    let unmounted = WholeDeviceTopology(physicalIdentity: "media-uuid", bsdName: "disk88", isWholeDevice: true,
        isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: ejectFixture.volumes.map { .init(identity: $0.identity, mounted: false) },
        images: [])
    driver.observations = [ejectFixture, ejectFixture, imageVolumesUnmounted, imageVolumesUnmounted,
        imagesDetached, imagesDetached, unmounted, unmounted]
    let result = ejectController(store, lock).ejectWholeExternalDevice(physicalIdentity: "media-uuid", checkpoint: ejectCheckpoint, driver: driver)
    #expect(result.succeeded && result.canUnplug)
    #expect(driver.calls.contains("unmount-image:image-a"))
    #expect(driver.calls.contains("unmount-physical"))
    #expect(driver.calls.contains("detach:image-a"))
    #expect(driver.calls.contains("eject"))
    #expect(driver.calls.firstIndex(of: "unmount-image:image-a") ?? .max < driver.calls.firstIndex(of: "detach:image-a") ?? .min)
    #expect(driver.calls.firstIndex(of: "detach:image-a") ?? .max < driver.calls.firstIndex(of: "unmount-physical") ?? .min)
    #expect(driver.calls.firstIndex(of: "unmount-physical") ?? .max < driver.calls.firstIndex(of: "eject") ?? .min)
    #expect(driver.calls.firstIndex(of: "detach:image-a") ?? .max < driver.calls.firstIndex(of: "eject") ?? .min)
    #expect(driver.calls.last == "presence" && store.state.ejectIntent)
}

@Test func failedOrMissingArbitrationReceiptStopsAndRetainsIntent() {
    for receipt: WholeDeviceActionReceipt in [.busy("busy"), .dissenter("claimed"), .timedOut, .missingCallback, .failed("error")] {
        let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture); driver.receipt = receipt
        let result = ejectController(store, lock).ejectWholeExternalDevice(physicalIdentity: "media-uuid", checkpoint: ejectCheckpoint, driver: driver)
        #expect(result.failure != nil && !result.canUnplug && store.state.ejectIntent)
        #expect(!driver.calls.contains("detach:image-a") && !driver.calls.contains("unmount-physical") && !driver.calls.contains("eject"))
    }
}

@Test func explicitReturnRecoversOnlyAfterEveryImageDetachWasDurablyRecorded() throws {
    let detached = WholeDeviceTopology(physicalIdentity: ejectFixture.physicalIdentity, bsdName: ejectFixture.bsdName,
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: ejectFixture.volumes, images: [])

    for phase: WholeDeviceEjectJournalRecord.Phase in [.imagesDetached] {
        let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(detached)
        driver.returnIdentityValid = true
        let journal = WholeDeviceEjectJournalRecord(operationID: "fixture-eject", target: ejectFixture,
            phase: phase, completedSteps: ["unmountImageVolumes:image-a", "detachImage:image-a"],
            lastIssuedAction: .imageDetach)
        let data = try JSONEncoder().encode(journal)
        store.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: journal.operationID,
            workbenchOperation: "eject:\(journal.operationID)", workbenchPhase: "eject:\(phase.rawValue)",
            workbenchTarget: data.base64EncodedString())

        let returned = ejectController(store, lock).returnFromWholeDeviceEject(driver: driver)

        #expect(returned)
        #expect(!store.state.ejectIntent)
        #expect(store.state.workbenchTerminalResult == "returned-to-development")
        #expect(driver.calls == ["return-check"])
    }

    let unsafeStore = EjectTestStore(), unsafeLock = EjectTestLock(), unsafeDriver = EjectTestDriver(ejectFixture)
    unsafeDriver.returnIdentityValid = true
    let incomplete = WholeDeviceEjectJournalRecord(operationID: "fixture-eject", target: ejectFixture,
        phase: .interrupted, completedSteps: ["unmountImageVolumes:image-a"])
    unsafeStore.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: incomplete.operationID,
        workbenchOperation: "eject:\(incomplete.operationID)", workbenchPhase: "eject:interrupted",
        workbenchTarget: try JSONEncoder().encode(incomplete).base64EncodedString())

    #expect(!ejectController(unsafeStore, unsafeLock).returnFromWholeDeviceEject(driver: unsafeDriver))
    #expect(unsafeStore.state.ejectIntent)
    #expect(unsafeDriver.calls.isEmpty, "A journal without a recorded action receipt is not a Return boundary")
}

@Test func physicalUnmountBusyCannotReturnAndCanContinueOnlyWithFreshConfirmation() throws {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    let detached = WholeDeviceTopology(physicalIdentity: ejectFixture.physicalIdentity, bsdName: ejectFixture.bsdName,
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: ejectFixture.volumes, images: [])
    let journal = WholeDeviceEjectJournalRecord(operationID: "partial-physical", target: ejectFixture,
        phase: .interrupted, completedSteps: ["unmountImageVolumes:image-a", "detachImage:image-a"],
        lastReceipt: .busy("physical volume busy"), lastIssuedAction: .physicalVolumesUnmount)
    store.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:\(journal.operationID)", workbenchPhase: "eject:interrupted",
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    driver.current = detached
    driver.returnIdentityValid = true

    #expect(!ejectController(store, lock).returnFromWholeDeviceEject(driver: driver))
    #expect(store.state.ejectIntent)
    #expect(!driver.calls.contains("return-check"))

    driver.calls = []
    driver.continuationIdentityValid = true
    let checkpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: true,
        dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: detached.physicalIdentity,
        confirmedMemberKey: ejectFixture.memberKey, confirmedAt: Date())
    let result = ejectController(store, lock).continueWholeExternalDeviceEject(checkpoint: checkpoint, driver: driver)
    #expect(result.succeeded)
    #expect(driver.calls.contains("continue-check"))
    #expect(driver.calls.contains("unmount-physical"))
    #expect(driver.calls.contains("eject"))
    #expect(driver.calls.last == "presence")
    #expect(store.state.ejectIntent, "The intent remains set after verified physical absence for normal reconnect/Return handling")
    #expect(store.state.workbenchTerminalResult == "safe-to-unplug")
}

@Test func ambiguousOlderPhysicalJournalCannotReturnOrContinue() throws {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    let journal = WholeDeviceEjectJournalRecord(operationID: "legacy-physical", target: ejectFixture,
        phase: .interrupted, completedSteps: ["unmountImageVolumes:image-a", "detachImage:image-a"])
    store.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:\(journal.operationID)", workbenchPhase: "eject:interrupted",
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    driver.returnIdentityValid = true
    driver.continuationIdentityValid = true
    #expect(!ejectController(store, lock).returnFromWholeDeviceEject(driver: driver))
    #expect(store.state.ejectIntent)
    let checkpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: true,
        dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: ejectFixture.physicalIdentity,
        confirmedMemberKey: ejectFixture.memberKey, confirmedAt: Date())
    #expect(!ejectController(store, lock).continueWholeExternalDeviceEject(checkpoint: checkpoint, driver: driver).succeeded)
    #expect(store.state.ejectIntent)
}

@Test func physicalUnmountIssuedCrashAllowsOnlyFreshExplicitContinuation() throws {
    let store = EjectTestStore(), lock = EjectTestLock()
    let target = WholeDeviceTopology(physicalIdentity: ejectFixture.physicalIdentity,
        bsdName: ejectFixture.bsdName, isWholeDevice: true, isExternal: true, isSystemDevice: false,
        inventoryComplete: true, volumes: ejectFixture.volumes, images: [])
    let driver = EjectTestDriver(target)
    let journal = WholeDeviceEjectJournalRecord(operationID: "issued-crash", target: target,
        phase: .physicalVolumesUnmountIssued, completedSteps: [],
        lastIssuedAction: .physicalVolumesUnmount)
    store.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:\(journal.operationID)", workbenchPhase: "eject:physical-unmount-issued",
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    driver.continuationIdentityValid = true
    let checkpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: true,
        dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: target.physicalIdentity,
        confirmedMemberKey: target.memberKey, confirmedAt: Date())

    let result = ejectController(store, lock).continueWholeExternalDeviceEject(checkpoint: checkpoint, driver: driver)
    #expect(result.succeeded)
    #expect(driver.calls.contains("continue-check"))
    #expect(driver.calls.contains("unmount-physical"))
    #expect(driver.calls.contains("eject"))
    #expect(store.state.ejectIntent)
}

@Test func issuedWholeDeviceEjectRecoveryRecordsAbsenceWithoutForgingReceipt() throws {
    let store = EjectTestStore(), lock = EjectTestLock()
    let target = WholeDeviceTopology(physicalIdentity: ejectFixture.physicalIdentity,
        bsdName: ejectFixture.bsdName, isWholeDevice: true, isExternal: true, isSystemDevice: false,
        inventoryComplete: true, volumes: ejectFixture.volumes.map { .init(identity: $0.identity, mounted: false) }, images: [])
    let driver = EjectTestDriver(target)
    driver.issuedEjectRecovery = .exactTargetAbsent
    let journal = WholeDeviceEjectJournalRecord(operationID: "issued-eject-crash", target: target,
        phase: .ejectIssued, completedSteps: ["unmountAllPhysicalVolumes"],
        lastIssuedAction: .ejectWholeDevice)
    store.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:\(journal.operationID)", workbenchPhase: "eject:whole-device-issued",
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    let checkpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: true,
        dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: target.physicalIdentity,
        confirmedMemberKey: target.memberKey, confirmedAt: Date())

    let result = ejectController(store, lock).continueWholeExternalDeviceEject(checkpoint: checkpoint, driver: driver)
    #expect(result.succeeded)
    #expect(result.completedSteps.contains("observeWholeDeviceAbsentAfterEjectIssue"))
    #expect(!result.completedSteps.contains("ejectWholeDevice"))
    #expect(!driver.calls.contains("eject"))
    let saved = try JSONDecoder().decode(WholeDeviceEjectJournalRecord.self,
        from: Data(base64Encoded: try #require(store.state.workbenchTarget))!)
    #expect(saved.phase == .verifiedAbsent)
    #expect(saved.lastReceipt == nil)
    #expect(saved.recoveryObservation == .exactTargetAbsentAfterEjectIssue)
    #expect(store.state.ejectIntent)
}

@Test func unrecordedImageDisappearanceAfterDetachRequestCannotReturn() throws {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    let journal = WholeDeviceEjectJournalRecord(operationID: "missing-image", target: ejectFixture,
        phase: .interrupted, completedSteps: ["unmountImageVolumes:image-a"],
        lastReceipt: .completed("detach command returned but its completion was not durably recorded"),
        lastIssuedAction: .imageDetach)
    store.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:\(journal.operationID)", workbenchPhase: "eject:interrupted",
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    driver.current = WholeDeviceTopology(physicalIdentity: ejectFixture.physicalIdentity,
        bsdName: ejectFixture.bsdName, isWholeDevice: true, isExternal: true, isSystemDevice: false,
        inventoryComplete: true, volumes: ejectFixture.volumes, images: [])
    driver.returnIdentityValid = true

    #expect(!ejectController(store, lock).returnFromWholeDeviceEject(driver: driver))
    #expect(store.state.ejectIntent)
    #expect(driver.calls.isEmpty, "An unrecorded disappearance cannot be converted into a Return boundary")
}

@Test func newMemberBetweenPhasesAndUnexplainedDisappearanceDoNotBecomeSuccess() {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    let changed = WholeDeviceTopology(physicalIdentity: "media-uuid", bsdName: "disk88", isWholeDevice: true,
        isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: ejectFixture.volumes + [.init(identity: "new-volume", mounted: true)], images: ejectFixture.images)
    driver.observations = [ejectFixture, changed]
    let drift = ejectController(store, lock).ejectWholeExternalDevice(physicalIdentity: "media-uuid", checkpoint: ejectCheckpoint, driver: driver)
    #expect(drift.failure == .topologyChanged && !driver.calls.contains("eject") && store.state.ejectIntent)

    let store2 = EjectTestStore(), lock2 = EjectTestLock(), driver2 = EjectTestDriver(ejectFixture)
    driver2.current = WholeDeviceTopology(physicalIdentity: "media-uuid", bsdName: "disk88", isWholeDevice: true,
        isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: ejectFixture.volumes.map { .init(identity: $0.identity, mounted: false) },
        images: ejectFixture.images.map { .init(identity: $0.identity, attached: false, volumeIdentities: $0.volumeIdentities) })
    driver2.finalPresence = .unknown("unexplained disappearance")
    let absent = ejectController(store2, lock2).ejectWholeExternalDevice(physicalIdentity: "media-uuid", checkpoint: ejectCheckpoint, driver: driver2)
    #expect(!absent.canUnplug && absent.failure != nil)
    #expect(store2.state.ejectIntent)
}
