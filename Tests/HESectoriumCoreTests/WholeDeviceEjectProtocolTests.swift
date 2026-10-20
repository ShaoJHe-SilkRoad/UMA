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
private final class EjectReadyProfileStorage: StorageBackend {
    var attached = false
    var attachCalls = 0
    func observeOuter() -> VolumeIdentity? { StorageObservation.expectedReady.outer }
    func observe() -> StorageObservation? { attached ? StorageObservation.expectedReady : nil }
    func attachImage() -> CommandOutcome { attachCalls += 1; attached = true; return .success }
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
    var unmountedEjectPostcondition = false
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
    func presence(of target: WholeDeviceTopology) -> WholeDevicePresence {
        calls.append("presence")
        return target.physicalIdentity == current?.physicalIdentity ? finalPresence : .unknown("different physical target")
    }
    func successfulEjectHasUnmountedPostcondition(of target: WholeDeviceTopology) -> Bool {
        calls.append("post-eject-check")
        return unmountedEjectPostcondition
    }
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

@Test func passiveEjectRecoveryClosesAbsentCallbackAndAcceptsFreshReconnectWithoutDiskActions() throws {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    let profileID = UUID().uuidString
    let journal = WholeDeviceEjectJournalRecord(operationID: "durable-callback", target: ejectFixture,
        phase: .ejectCallbackSucceeded,
        completedSteps: ["detachImage:image-a", "unmountAllPhysicalVolumes", "ejectWholeDevice"],
        lastReceipt: .completed("native eject succeeded"), lastIssuedAction: .ejectWholeDevice)
    store.state = StoragePersistentState(ejectIntent: true, operationID: journal.operationID,
        suppressedProfileIDs: [profileID], reconnectAttemptedProfileIDs: [profileID],
        workbenchOperation: "eject:" + journal.operationID,
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    let controller = ejectController(store, lock)
    driver.finalPresence = .unknown("inventory temporarily unavailable")
    #expect(!controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]))
    #expect(store.state.ejectIntent)
    driver.finalPresence = .absent
    #expect(controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]))
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.workbenchTerminalResult == "safe-to-unplug")
    #expect(store.state.disconnectedProfileIDs.contains(profileID))
    #expect(!store.state.reconnectAttemptedProfileIDs.contains(profileID))
    driver.finalPresence = .present
    driver.returnIdentityValid = false
    #expect(!controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity, driver: driver))
    driver.returnIdentityValid = true
    #expect(controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]))
    #expect(store.state.terminalEjectJournals.isEmpty)
    #expect(store.state.workbenchTerminalResult == "returned-to-development")
    #expect(!store.state.suppressedProfileIDs.contains(profileID), "A verified reconnect closes the old connection's eject suppression")
    #expect(!store.state.disconnectedProfileIDs.contains(profileID))
    #expect(driver.calls.allSatisfy { ["presence", "return-check"].contains($0) })
    let profileBackend = EjectReadyProfileStorage()
    let automaticLoad = controller.handleRegisteredProfileEvent(
        .outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID), profileID: profileID,
        policy: .expected, backend: profileBackend)
    #expect(automaticLoad.succeeded && profileBackend.attachCalls == 1)
    #expect(!store.state.suppressedProfileIDs.contains(profileID))
    #expect(controller.handleRegisteredProfileEvent(
        .outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID), profileID: profileID,
        policy: .expected, backend: profileBackend).succeeded)
    #expect(profileBackend.attachCalls == 1, "Duplicate arrival cannot attach twice")
}

@Test func passiveRecoveryDistinguishesPhysicalDisconnectFromSuccessfulEject() throws {
    let store = EjectTestStore(), driver = EjectTestDriver(ejectFixture)
    let journal = WholeDeviceEjectJournalRecord(operationID: "interrupted-unmount", target: ejectFixture,
        phase: .interrupted, lastReceipt: .timedOut, lastIssuedAction: .imageVolumesUnmount)
    store.state = StoragePersistentState(ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:" + journal.operationID,
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    #expect(ejectController(store, EjectTestLock()).reconcileWholeDeviceEjectRecovery(
        physicalIdentity: ejectFixture.physicalIdentity, driver: driver))
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.workbenchTerminalResult == "disconnected-without-eject-confirmation")
    let encoded = try #require(store.state.terminalEjectJournals[ejectFixture.physicalIdentity])
    let retained = try JSONDecoder().decode(WholeDeviceEjectJournalRecord.self, from: #require(Data(base64Encoded: encoded)))
    #expect(retained.phase == .disconnected && retained.lastReceipt == .timedOut)
    #expect(driver.calls == ["presence"])
}

@Test func successfulCallbackAlreadyRemountedReconcilesWithoutNeedingMissingDisappearEvent() throws {
    let store = EjectTestStore(), driver = EjectTestDriver(ejectFixture)
    let journal = WholeDeviceEjectJournalRecord(operationID: "callback-reconnected", target: ejectFixture,
        phase: .ejectCallbackSucceeded,
        completedSteps: ["detachImage:image-a", "unmountAllPhysicalVolumes", "ejectWholeDevice"],
        lastReceipt: .completed("native eject succeeded"), lastIssuedAction: .ejectWholeDevice)
    store.state = StoragePersistentState(ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:" + journal.operationID,
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    driver.finalPresence = .present; driver.returnIdentityValid = true
    #expect(ejectController(store, EjectTestLock()).reconcileWholeDeviceEjectRecovery(
        physicalIdentity: ejectFixture.physicalIdentity, driver: driver))
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.workbenchTerminalResult == "returned-to-development")
    #expect(driver.calls == ["presence", "post-eject-check", "return-check"])
}

@Test func interruptedEjectAlreadyReconnectedReleasesOnlyItsProfilesWithoutInventingReceipt() throws {
    for receipt: WholeDeviceActionReceipt? in [nil, .timedOut, .failed("lost completion")] {
        let store = EjectTestStore(), driver = EjectTestDriver(ejectFixture)
        let profileID = UUID().uuidString, otherID = UUID().uuidString
        let journal = WholeDeviceEjectJournalRecord(operationID: "issued-eject-remounted", target: ejectFixture,
            phase: receipt == nil ? .ejectIssued : .interrupted,
            completedSteps: ["detachImage:image-a", "unmountAllPhysicalVolumes"],
            lastReceipt: receipt, lastIssuedAction: .ejectWholeDevice)
        store.state = StoragePersistentState(ejectIntent: true, operationID: journal.operationID,
            suppressedProfileIDs: [profileID, otherID], disconnectedProfileIDs: [profileID, otherID],
            reconnectAttemptedProfileIDs: [profileID, otherID], workbenchOperation: "eject:" + journal.operationID,
            workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
        driver.finalPresence = .present
        let controller = ejectController(store, EjectTestLock())
        #expect(!controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
            driver: driver, affectedProfileIDs: [profileID]), "An incomplete identity cannot close recovery")
        driver.returnIdentityValid = true
        #expect(controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
            driver: driver, affectedProfileIDs: [profileID]))
        #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
        #expect(store.state.suppressedProfileIDs == [otherID])
        #expect(store.state.disconnectedProfileIDs == [otherID])
        #expect(store.state.reconnectAttemptedProfileIDs == [otherID])
        #expect(store.state.workbenchTerminalResult == "returned-to-development")
        let encodedJournal = try #require(store.state.workbenchTarget)
        let journalData = try #require(Data(base64Encoded: encodedJournal))
        let retained = try JSONDecoder().decode(WholeDeviceEjectJournalRecord.self, from: journalData)
        #expect(retained.lastReceipt == receipt)
        #expect(!retained.completedSteps.contains("ejectWholeDevice"))
        #expect(driver.calls.allSatisfy { ["presence", "return-check"].contains($0) })
    }
}

@Test func interruptedImageStageCannotMasqueradeAsVerifiedReconnect() throws {
    let store = EjectTestStore(), driver = EjectTestDriver(ejectFixture)
    let journal = WholeDeviceEjectJournalRecord(operationID: "image-stage-only", target: ejectFixture,
        phase: .interrupted, completedSteps: ["unmountImageVolumes:image-a"],
        lastReceipt: .timedOut, lastIssuedAction: .imageDetach)
    store.state = StoragePersistentState(ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:" + journal.operationID,
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    driver.finalPresence = .present; driver.returnIdentityValid = true
    #expect(!ejectController(store, EjectTestLock()).reconcileWholeDeviceEjectRecovery(
        physicalIdentity: ejectFixture.physicalIdentity, driver: driver))
    #expect(store.state.ejectIntent)
}

@Test func previouslyReturnedJournalRepairsOnlyFreshlyVerifiedStaleProfileMarkers() throws {
    let store = EjectTestStore(), driver = EjectTestDriver(ejectFixture)
    let profileID = UUID().uuidString, otherID = UUID().uuidString
    let journal = WholeDeviceEjectJournalRecord(operationID: "old-return", target: ejectFixture,
        phase: .verifiedAbsent,
        completedSteps: ["detachImage:image-a", "unmountAllPhysicalVolumes", "ejectWholeDevice"],
        lastReceipt: .completed("Disk /dev/disk81 ejected\n"), lastIssuedAction: .ejectWholeDevice)
    store.state = StoragePersistentState(ejectIntent: false, operationID: journal.operationID,
        suppressedProfileIDs: [profileID, otherID], disconnectedProfileIDs: [profileID, otherID],
        reconnectAttemptedProfileIDs: [profileID], workbenchPhase: "eject:return-validated",
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString(),
        workbenchTerminalResult: "returned-to-development")
    driver.finalPresence = .present
    let controller = ejectController(store, EjectTestLock())
    #expect(!controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]))
    #expect(store.state.disconnectedProfileIDs.contains(profileID))
    driver.returnIdentityValid = true
    #expect(controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]))
    #expect(store.state.suppressedProfileIDs == [otherID])
    #expect(store.state.disconnectedProfileIDs == [otherID])
    #expect(store.state.reconnectAttemptedProfileIDs.isEmpty)
    #expect(!controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]), "A repaired return is not rewritten on every refresh")
    #expect(driver.calls.allSatisfy { ["presence", "return-check"].contains($0) })
}

@Test func stableMemberComparisonAllowsBSDRenumberButRejectsAmbiguousUUIDs() {
    let media = UUID().uuidString, first = UUID().uuidString.lowercased(), other = UUID().uuidString.lowercased()
    let original = WholeDeviceTopology(physicalIdentity: media, bsdName: "disk81",
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "\(first)|disk81s1", mounted: true)], images: [])
    let renumbered = WholeDeviceTopology(physicalIdentity: media, bsdName: "disk82",
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "\(first)|disk82s3", mounted: true)], images: [])
    let changed = WholeDeviceTopology(physicalIdentity: media, bsdName: "disk82",
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "\(other)|disk82s3", mounted: true)], images: [])
    let ambiguous = WholeDeviceTopology(physicalIdentity: media, bsdName: "disk82",
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "\(first)|disk82s1", mounted: true),
                  .init(identity: "\(first)|disk82s2", mounted: true)], images: [])
    #expect(original.matchesStablePhysicalIdentityAndVolumes(renumbered))
    #expect(!original.matchesPhysicalIdentityAndVolumes(renumbered))
    #expect(!original.matchesStablePhysicalIdentityAndVolumes(changed))
    #expect(!ambiguous.hasUniqueMembers)
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

@Test func confirmedWholeDeviceEjectDurablySuppressesOnlyAffectedProfiles() {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    store.state = StoragePersistentState(ejectIntent: false, suppressedProfileIDs: ["unrelated-profile"])
    driver.receipt = .busy("fixture writer remains")
    let result = ejectController(store, lock).ejectWholeExternalDevice(
        physicalIdentity: ejectFixture.physicalIdentity, checkpoint: ejectCheckpoint,
        driver: driver, affectedProfileIDs: ["profile-A", "profile-B"])
    #expect(!result.succeeded)
    #expect(store.state.ejectIntent)
    #expect(store.state.suppressedProfileIDs == ["unrelated-profile", "profile-A", "profile-B"])
    driver.returnIdentityValid = true
    #expect(ejectController(store, lock).returnFromWholeDeviceEject(driver: driver))
    #expect(!store.state.ejectIntent)
    #expect(store.state.suppressedProfileIDs == ["unrelated-profile", "profile-A", "profile-B"],
            "Return alone does not prove an affected development image has been manually loaded")
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
    #expect(driver.calls.last == "presence" && !store.state.ejectIntent)
    #expect(store.state.workbenchOperation == nil)
    #expect(store.state.terminalEjectJournals["media-uuid"] != nil)
}

@Test func completedEjectOfAReleasesBAndRetainsExactAReturnAcrossRestart() throws {
    let target = WholeDeviceTopology(physicalIdentity: "physical-A", bsdName: "disk88",
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "A-volume", mounted: true)], images: [])
    let unmounted = WholeDeviceTopology(physicalIdentity: target.physicalIdentity, bsdName: target.bsdName,
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "A-volume", mounted: false)], images: [])
    let checkpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: true,
        dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: target.physicalIdentity,
        confirmedMemberKey: target.memberKey, confirmedAt: Date())
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(target)
    driver.observations = [target, target, unmounted, unmounted]
    let ejected = ejectController(store, lock).ejectWholeExternalDevice(
        physicalIdentity: target.physicalIdentity, checkpoint: checkpoint, driver: driver,
        affectedProfileIDs: ["profile-A"])
    #expect(ejected.succeeded)
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.suppressedProfileIDs == ["profile-A"])
    #expect(store.state.terminalEjectJournals[target.physicalIdentity] != nil)

    let backendB = EjectReadyProfileStorage()
    let restarted = StorageController(backend: EjectTestStorage(), store: store, lock: lock)
    let loadedB = restarted.mountRegisteredProfileAtStartup(
        profileID: "profile-B", policy: .expected, backend: backendB)
    #expect(loadedB.succeeded && backendB.attachCalls == 1)
    #expect(store.state.terminalEjectJournals[target.physicalIdentity] != nil)
    #expect(store.state.suppressedProfileIDs == ["profile-A"])

    driver.returnIdentityValid = true
    var busyWithB = store.state.advancingRevision()
    busyWithB.workbenchOperation = "workbench:B"
    store.state = busyWithB
    #expect(!restarted.canReturnFromWholeDeviceEject(physicalIdentity: target.physicalIdentity, driver: driver))
    #expect(!restarted.returnFromWholeDeviceEject(physicalIdentity: target.physicalIdentity, driver: driver))
    var idle = store.state.advancingRevision()
    idle.workbenchOperation = nil
    store.state = idle
    #expect(!restarted.canReturnFromWholeDeviceEject(physicalIdentity: "physical-B", driver: driver))
    #expect(!restarted.returnFromWholeDeviceEject(physicalIdentity: "physical-B", driver: driver))
    #expect(restarted.canReturnFromWholeDeviceEject(physicalIdentity: target.physicalIdentity, driver: driver))
    #expect(restarted.returnFromWholeDeviceEject(physicalIdentity: target.physicalIdentity, driver: driver))
    #expect(store.state.terminalEjectJournals[target.physicalIdentity] == nil)
    #expect(store.state.suppressedProfileIDs == ["profile-A"],
            "Return alone never clears the per-profile manual-load gate")
}

@Test func failedOrMissingArbitrationReceiptStopsAndRetainsIntent() {
    for receipt: WholeDeviceActionReceipt in [.busy("busy"), .dissenter("claimed"), .timedOut, .missingCallback, .failed("error")] {
        let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture); driver.receipt = receipt
        let result = ejectController(store, lock).ejectWholeExternalDevice(physicalIdentity: "media-uuid", checkpoint: ejectCheckpoint, driver: driver)
        #expect(result.failure != nil && !result.canUnplug && store.state.ejectIntent)
        #expect(!driver.calls.contains("detach:image-a") && !driver.calls.contains("unmount-physical") && !driver.calls.contains("eject"))
    }
}

@Test func interruptedAStillHoldsTheGlobalMutationSlot() {
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    driver.receipt = .busy("fixture writer remains")
    let failedA = ejectController(store, lock).ejectWholeExternalDevice(
        physicalIdentity: ejectFixture.physicalIdentity, checkpoint: ejectCheckpoint,
        driver: driver, affectedProfileIDs: ["profile-A"])
    #expect(!failedA.succeeded && store.state.ejectIntent)
    let backendB = EjectReadyProfileStorage()
    let automaticB = ejectController(store, lock).mountRegisteredProfileAtStartup(
        profileID: "profile-B", policy: .expected, backend: backendB)
    #expect(automaticB.failure == .operationInProgress)
    #expect(backendB.attachCalls == 0)
    #expect(store.state.terminalEjectJournals.isEmpty)
}

@Test func explicitContinuationArchivesLegacyVerifiedAbsentJournal() throws {
    let journal = WholeDeviceEjectJournalRecord(operationID: "legacy-completed-A", target: ejectFixture,
        phase: .verifiedAbsent,
        completedSteps: ["unmountImageVolumes:image-a", "detachImage:image-a",
                         "unmountAllPhysicalVolumes", "ejectWholeDevice"],
        lastReceipt: .completed("fixture"), lastIssuedAction: .ejectWholeDevice)
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(ejectFixture)
    store.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: journal.operationID,
        suppressedProfileIDs: ["profile-A"],
        workbenchOperation: "eject:\(journal.operationID)", workbenchPhase: "eject:verified-absent",
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())

    let migrated = ejectController(store, lock).continueWholeExternalDeviceEject(
        checkpoint: ejectCheckpoint, driver: driver)
    #expect(migrated.succeeded && driver.calls.isEmpty)
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.terminalEjectJournals[ejectFixture.physicalIdentity] != nil)
    #expect(store.state.suppressedProfileIDs == ["profile-A"])
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
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.terminalEjectJournals[ejectFixture.physicalIdentity] != nil)
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
    #expect(store.state.terminalEjectJournals.isEmpty)
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
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.terminalEjectJournals[target.physicalIdentity] != nil)
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
    #expect(!result.succeeded && !result.canUnplug)
    #expect(result.completedSteps.contains("observeWholeDeviceAbsentAfterEjectIssue"))
    #expect(!result.completedSteps.contains("ejectWholeDevice"))
    #expect(!driver.calls.contains("eject"))
    let saved = try JSONDecoder().decode(WholeDeviceEjectJournalRecord.self,
        from: Data(base64Encoded: try #require(store.state.terminalEjectJournals[target.physicalIdentity]))!)
    #expect(saved.phase == .disconnected)
    #expect(saved.lastReceipt == nil)
    #expect(saved.recoveryObservation == .exactTargetAbsentAfterEjectIssue)
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.workbenchTerminalResult == "disconnected-without-eject-confirmation")
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

@Test func unissuedTopologyDriftCanBeCancelledOnlyByExplicitFreshReturn() throws {
    let target = WholeDeviceTopology(physicalIdentity: "physical-A", bsdName: "disk88",
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "original-member", mounted: true)], images: [])
    let changed = WholeDeviceTopology(physicalIdentity: target.physicalIdentity, bsdName: target.bsdName,
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: target.volumes + [.init(identity: "new-member", mounted: true)], images: [])
    func checkpoint(_ topology: WholeDeviceTopology) -> WholeDeviceEjectCheckpoint {
        .init(confirmedExactTargetAndScope: true, knownWritersClosed: true,
              dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: topology.physicalIdentity,
              confirmedMemberKey: topology.memberKey, confirmedAt: Date())
    }
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(target)
    driver.observations = [target, changed]
    let failed = ejectController(store, lock).ejectWholeExternalDevice(
        physicalIdentity: target.physicalIdentity, checkpoint: checkpoint(target), driver: driver)
    #expect(failed.failure == .topologyChanged)
    #expect(store.state.ejectIntent && !driver.calls.contains("unmount-physical") && !driver.calls.contains("eject"))
    let journal = try JSONDecoder().decode(WholeDeviceEjectJournalRecord.self,
        from: Data(base64Encoded: try #require(store.state.workbenchTarget))!)
    #expect(journal.canCancelUnissuedEject)
    #expect(!ejectController(store, lock).continueWholeExternalDeviceEject(
        checkpoint: checkpoint(target), driver: driver).succeeded)

    driver.current = changed
    driver.returnIdentityValid = true
    #expect(ejectController(store, lock).returnFromWholeDeviceEject(
        physicalIdentity: target.physicalIdentity, driver: driver))
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(!driver.calls.contains("unmount-physical") && !driver.calls.contains("eject"),
            "Cancelling an unissued operation must never dispatch disk work")

    let newAttempt = ejectController(store, lock).ejectWholeExternalDevice(
        physicalIdentity: changed.physicalIdentity, checkpoint: checkpoint(changed), driver: driver)
    #expect(newAttempt.succeeded && driver.calls.contains("unmount-physical") && driver.calls.contains("eject"),
            "A new user confirmation can operate on the changed inventory after cancellation")
}

@Test func successfulEjectCallbackWithUncertainPresenceRechecksWithoutReissuingActions() throws {
    let target = WholeDeviceTopology(physicalIdentity: "physical-A", bsdName: "disk88",
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "volume-A", mounted: true)], images: [])
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(target)
    let checkpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: true,
        dependenciesCanFinishOffTarget: true, confirmedPhysicalIdentity: target.physicalIdentity,
        confirmedMemberKey: target.memberKey, confirmedAt: Date())
    driver.finalPresence = .unknown("fixture inventory pending")
    let initial = ejectController(store, lock).ejectWholeExternalDevice(
        physicalIdentity: target.physicalIdentity, checkpoint: checkpoint, driver: driver)
    #expect(initial.failure == .absenceUnverified("fixture inventory pending") && !initial.canUnplug)
    let journal = try JSONDecoder().decode(WholeDeviceEjectJournalRecord.self,
        from: Data(base64Encoded: try #require(store.state.workbenchTarget))!)
    #expect(journal.phase == .ejectCallbackSucceeded && journal.successfulEjectCallbackRequiresRecheck)
    let actionCount = driver.calls.filter { $0 == "eject" || $0 == "unmount-physical" }.count

    // This is a read-only recheck. Current writers/off-target execution cannot enable a
    // mutation and do not prevent a truthful present/absent observation.
    let recheck = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: false,
        dependenciesCanFinishOffTarget: false, confirmedPhysicalIdentity: target.physicalIdentity,
        confirmedMemberKey: target.memberKey, confirmedAt: Date())
    driver.finalPresence = .present
    let present = ejectController(store, lock).continueWholeExternalDeviceEject(checkpoint: recheck, driver: driver)
    #expect(present.failure == .absenceUnverified("ejected target has mounted, attached, changed or unverified members"))
    #expect(store.state.ejectIntent && !present.canUnplug)
    #expect(driver.calls.filter { $0 == "eject" || $0 == "unmount-physical" }.count == actionCount)

    driver.finalPresence = .absent
    let absent = ejectController(store, lock).continueWholeExternalDeviceEject(checkpoint: recheck, driver: driver)
    #expect(absent.succeeded && absent.canUnplug)
    #expect(!store.state.ejectIntent && store.state.terminalEjectJournals[target.physicalIdentity] != nil)
    #expect(driver.calls.filter { $0 == "eject" || $0 == "unmount-physical" }.count == actionCount)
}

@Test func legacyInterruptedSuccessfulCallbackCanOnlyRecheckPresence() throws {
    let target = WholeDeviceTopology(physicalIdentity: "physical-A", bsdName: "disk88",
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "volume-A", mounted: false)], images: [])
    let journal = WholeDeviceEjectJournalRecord(operationID: "old-callback", target: target,
        phase: .interrupted, completedSteps: ["unmountAllPhysicalVolumes", "ejectWholeDevice"],
        lastReceipt: .completed("fixture callback"), lastIssuedAction: .ejectWholeDevice)
    let store = EjectTestStore(), lock = EjectTestLock(), driver = EjectTestDriver(target)
    store.state = StoragePersistentState(revision: 1, ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:\(journal.operationID)", workbenchPhase: "eject:interrupted",
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    let recheck = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true, knownWritersClosed: false,
        dependenciesCanFinishOffTarget: false, confirmedPhysicalIdentity: target.physicalIdentity,
        confirmedMemberKey: target.memberKey, confirmedAt: Date())
    driver.finalPresence = .absent
    let result = ejectController(store, lock).continueWholeExternalDeviceEject(checkpoint: recheck, driver: driver)
    #expect(result.succeeded && driver.calls == ["presence"])
    #expect(!store.state.ejectIntent && store.state.terminalEjectJournals[target.physicalIdentity] != nil)
}


@Test func successfulLogicalEjectCompletesWhileUSBNodeRemainsEnumerated() throws {
    let target = WholeDeviceTopology(physicalIdentity: "physical-A", bsdName: "disk88",
        isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
        volumes: [.init(identity: "volume-A", mounted: true)], images: [])
    let store = EjectTestStore(), driver = EjectTestDriver(target)
    driver.finalPresence = .present
    driver.unmountedEjectPostcondition = true
    let checkpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true,
        knownWritersClosed: true, dependenciesCanFinishOffTarget: true,
        confirmedPhysicalIdentity: target.physicalIdentity, confirmedMemberKey: target.memberKey,
        confirmedAt: Date())
    let result = ejectController(store, EjectTestLock()).ejectWholeExternalDevice(
        physicalIdentity: target.physicalIdentity, checkpoint: checkpoint, driver: driver)
    #expect(result.succeeded && result.canUnplug)
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.workbenchTerminalResult == "safe-to-unplug")
    let encoded = try #require(store.state.terminalEjectJournals[target.physicalIdentity])
    let terminal = try JSONDecoder().decode(WholeDeviceEjectJournalRecord.self,
        from: try #require(Data(base64Encoded: encoded)))
    #expect(terminal.phase == .ejected && terminal.safelyEjected)
    #expect(terminal.lastReceipt == .completed("fixture"))
    #expect(driver.calls.filter { $0 == "eject" }.count == 1)
}

@Test func passiveLogicalEjectRecoveryUsesReceiptAndClearsPendingWithoutRepeatingAction() throws {
    let store = EjectTestStore(), driver = EjectTestDriver(ejectFixture)
    let profileID = UUID().uuidString
    let journal = WholeDeviceEjectJournalRecord(operationID: "logical-eject", target: ejectFixture,
        phase: .ejectCallbackSucceeded,
        completedSteps: ["detachImage:image-a", "unmountAllPhysicalVolumes", "ejectWholeDevice"],
        lastReceipt: .completed("Disk ejected"), lastIssuedAction: .ejectWholeDevice)
    store.state = StoragePersistentState(ejectIntent: true, operationID: journal.operationID,
        suppressedProfileIDs: [profileID], workbenchOperation: "eject:" + journal.operationID,
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    let controller = ejectController(store, EjectTestLock())
    driver.finalPresence = .present
    #expect(!controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]))
    driver.unmountedEjectPostcondition = true
    #expect(controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]))
    #expect(!store.state.ejectIntent && store.state.workbenchOperation == nil)
    #expect(store.state.workbenchPhase == "eject:completed")
    #expect(store.state.disconnectedProfileIDs.contains(profileID))
    #expect(!controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]), "An unmounted enumerated node is not a reconnect")
    driver.returnIdentityValid = true
    #expect(controller.reconcileWholeDeviceEjectRecovery(physicalIdentity: ejectFixture.physicalIdentity,
        driver: driver, affectedProfileIDs: [profileID]))
    #expect(store.state.terminalEjectJournals.isEmpty)
    #expect(!store.state.suppressedProfileIDs.contains(profileID))
    #expect(driver.calls.allSatisfy { ["presence", "post-eject-check", "return-check"].contains($0) })
}

@Test func failedEjectReceiptCannotCompleteFromAnUnmountedUSBNode() throws {
    let store = EjectTestStore(), driver = EjectTestDriver(ejectFixture)
    let journal = WholeDeviceEjectJournalRecord(operationID: "failed-eject", target: ejectFixture,
        phase: .interrupted,
        completedSteps: ["detachImage:image-a", "unmountAllPhysicalVolumes"],
        lastReceipt: .failed("native eject failed"), lastIssuedAction: .ejectWholeDevice)
    store.state = StoragePersistentState(ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:" + journal.operationID,
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    driver.finalPresence = .present
    driver.unmountedEjectPostcondition = true
    #expect(!ejectController(store, EjectTestLock()).reconcileWholeDeviceEjectRecovery(
        physicalIdentity: ejectFixture.physicalIdentity, driver: driver))
    #expect(store.state.ejectIntent && store.state.terminalEjectJournals.isEmpty)
    #expect(!driver.calls.contains("post-eject-check"), "A missing successful receipt cannot earn safe removal")
}

@Test func explicitCallbackRecoveryAcceptsFreshLogicalEjectWithoutAnotherMutation() throws {
    let store = EjectTestStore(), driver = EjectTestDriver(ejectFixture)
    let journal = WholeDeviceEjectJournalRecord(operationID: "logical-recheck", target: ejectFixture,
        phase: .ejectCallbackSucceeded,
        completedSteps: ["detachImage:image-a", "unmountAllPhysicalVolumes", "ejectWholeDevice"],
        lastReceipt: .completed("Disk ejected"), lastIssuedAction: .ejectWholeDevice)
    store.state = StoragePersistentState(ejectIntent: true, operationID: journal.operationID,
        workbenchOperation: "eject:" + journal.operationID,
        workbenchTarget: try JSONEncoder().encode(journal).base64EncodedString())
    driver.finalPresence = .present
    driver.unmountedEjectPostcondition = true
    let checkpoint = WholeDeviceEjectCheckpoint(confirmedExactTargetAndScope: true,
        knownWritersClosed: false, dependenciesCanFinishOffTarget: false,
        confirmedPhysicalIdentity: ejectFixture.physicalIdentity, confirmedMemberKey: ejectFixture.memberKey,
        confirmedAt: Date())
    let result = ejectController(store, EjectTestLock()).continueWholeExternalDeviceEject(
        checkpoint: checkpoint, driver: driver)
    #expect(result.succeeded && !store.state.ejectIntent)
    #expect(driver.calls == ["presence", "post-eject-check"])
}
