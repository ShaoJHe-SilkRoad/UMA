import XCTest
@testable import HESectoriumCore

final class StorageControllerTests: XCTestCase {
    func testWorkbenchIntentBlocksCoreStorageOperations() {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: false, workbenchOperation: "stop:fixture")
        let result = rig.controller.mountDEV()
        XCTAssertEqual(result.failure, .operationInProgress)
        XCTAssertEqual(rig.backend.attachCount, 0)
        XCTAssertTrue(rig.backend.performed.isEmpty)
    }

    func testReadinessRejectsWrongUUIDAndOrdinaryDirectory() {
        let policy = StorageIdentityPolicy.expected
        var observed = StorageObservation.expectedReady
        observed.outer.uuid = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        XCTAssertEqual(readinessFailure(policy.validate(observed)), .outerUUIDMismatch)

        observed = .expectedReady
        observed.outer.uuid = nil
        XCTAssertEqual(readinessFailure(policy.validate(observed)), .outerUUIDMissing)

        observed = .expectedReady
        observed.dev.uuid = nil
        XCTAssertEqual(readinessFailure(policy.validate(observed)), .devUUIDMissing)

        observed = .expectedReady
        observed.dev.fileSystem = "ExFAT"
        observed.dev.mountedVolume = false
        XCTAssertEqual(readinessFailure(policy.validate(observed)), .devNotMountedVolume)
    }

    func testReadinessRejectsReadOnlyAndIncorrectImagePhysicalRelation() {
        var observed = StorageObservation.expectedReady
        observed.dev.writable = false
        XCTAssertEqual(readinessFailure(StorageIdentityPolicy.expected.validate(observed)), .devReadOnly)

        observed = .expectedReady
        observed.image.backingVolumeUUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        XCTAssertEqual(readinessFailure(StorageIdentityPolicy.expected.validate(observed)), .imageRelationMismatch)

        observed = .expectedReady
        observed.image.attachedVolumeUUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        XCTAssertEqual(readinessFailure(StorageIdentityPolicy.expected.validate(observed)), .imageRelationMismatch)
    }

    func testSuccessfulAttachWithFailedVerificationLeavesIntent() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "prior-interruption")
        rig.backend.attachResult = .success
        var observation = StorageObservation.expectedReady
        observation.dev.uuid = UUID()
        rig.backend.observation = observation
        let result = rig.controller.mountDEV()
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.steps.map(\.status), [.succeeded, .succeeded, .failed])
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
    }

    func testOuterPreflightRejectsMissingWrongReadOnlyAndWrongRootBeforeMutation() {
        let cases: [(VolumeIdentity?, ReadinessFailure)] = [
            (nil, .outerUnavailable),
            (outerIdentity { $0.uuid = UUID() }, .outerUUIDMismatch),
            (outerIdentity { $0.writable = false }, .outerReadOnly),
            (outerIdentity { $0.rootMatchesExpected = false }, .outerRootMismatch)
        ]
        for (outer, failure) in cases {
            let rig = ControllerRig()
            rig.backend.outerObservation = outer
            let result = rig.controller.mountDEV()
            XCTAssertEqual(result.failure, .readiness(failure))
            XCTAssertEqual(rig.backend.attachCount, 0)
            XCTAssertEqual(rig.state.writeCount, 0)
            XCTAssertTrue(rig.backend.performed.isEmpty)
        }
    }

    func testEjectRecordsIntentBeforeStepsAndStopsAtBusyOrIncompleteOccupancy() throws {
        for occupancy: OccupancyAssessment in [.busy(processIDs: [11]), .incomplete(reason: "access denied")] {
            let rig = ControllerRig()
            rig.backend.occupancy = occupancy
            let result = rig.controller.safeEjectHE()
            XCTAssertFalse(result.succeeded)
            XCTAssertEqual(result.steps.last?.status, .failed)
            XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
            XCTAssertTrue(rig.backend.performed.isEmpty)
        }
    }

    func testOuterScopeIncompleteOccupancyAlsoBlocks() throws {
        let rig = ControllerRig()
        rig.backend.occupancyByScope[.outer] = .incomplete(reason: "outer scan denied")
        let result = rig.controller.safeEjectHE()
        XCTAssertEqual(result.failure, .occupancyIncomplete(.outer, "outer scan denied"))
        XCTAssertEqual(rig.backend.assessedScopes, [.dev, .outer])
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertTrue(rig.backend.performed.isEmpty)
    }

    func testPartialEjectStopsAfterFailedStepAndKeepsIntent() throws {
        let rig = ControllerRig()
        rig.backend.failStep = .detachImage
        let result = rig.controller.safeEjectHE()
        XCTAssertEqual(Array(result.steps.suffix(3).map(\.step)), ["flush", "unmountDEV", "detachImage"])
        XCTAssertEqual(result.steps.last?.status, .failed)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertFalse(rig.backend.performed.contains(.ejectOuterHE))
    }

    func testEjectRequiresConfirmedOuterAbsenceForSuccess() {
        let rig = ControllerRig()
        rig.backend.finalState = .stillPresent
        XCTAssertEqual(rig.controller.safeEjectHE().failure, .outerStillPresent)
        rig.state.current = .init(revision: 0, ejectIntent: false)
        rig.backend.finalState = .unknown("probe incomplete")
        XCTAssertEqual(rig.controller.safeEjectHE().failure, .finalStateUnknown("probe incomplete"))
    }

    func testSuccessfulEjectReportsEveryStepAndRetainsIntentUntilRecovery() throws {
        let rig = ControllerRig()
        let result = rig.controller.safeEjectHE()
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(rig.backend.assessedScopes, [.dev, .outer])
        XCTAssertEqual(rig.backend.performed, EjectStep.allCases)
        XCTAssertEqual(result.steps.suffix(2).map(\.step), ["verifyOuterAbsent", "recordOuterDisappearance"])
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).outerDisappearedAfterIntent)
    }

    func testLockPreventsDuplicateAndAutomaticConcurrentOperation() {
        let rig = ControllerRig()
        rig.lock.isHeld = true
        let manual = rig.controller.safeEjectHE()
        let automatic = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertEqual(manual.failure, .operationInProgress)
        XCTAssertEqual(automatic.failure, .operationInProgress)
        XCTAssertTrue(rig.backend.performed.isEmpty)
    }

    func testExitDoesNotClearIntentOnlyValidatedRecoveryDoes() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "interrupted")
        XCTAssertTrue(try XCTUnwrap(rig.controller.processExit()).ejectIntent)
        _ = rig.controller.handle(.outerDisappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        _ = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertFalse(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.backend.attachCount, 1)
        _ = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertEqual(rig.backend.attachCount, 1)
    }

    func testReinsertWithoutKnownDisappearanceNeedsExplicitCheckedRecovery() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "interrupted")
        let prematureReinsert = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertTrue(prematureReinsert.steps.contains(where: { $0.status == .skipped }))
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.controller.mountDEV(mode: .automatic).failure, .recoveryRequiresManualMount)
        XCTAssertEqual(rig.backend.attachCount, 0)

        let explicit = rig.controller.recoverPendingIntentManually()
        XCTAssertTrue(explicit.succeeded)
        XCTAssertFalse(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.backend.attachCount, 1)
    }

    func testManualRecoveryRequiresValidatedOuterAndInnerIdentity() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "unknown-history")
        rig.backend.outerObservation = outerIdentity { $0.rootMatchesExpected = false }
        XCTAssertEqual(rig.controller.recoverPendingIntentManually().failure, .readiness(.outerRootMismatch))
        XCTAssertEqual(rig.backend.attachCount, 0)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)

        rig.backend.outerObservation = StorageObservation.expectedReady.outer
        var badInner = StorageObservation.expectedReady
        badInner.dev.fileSystem = "ExFAT"
        badInner.dev.mountedVolume = false
        rig.backend.observation = badInner
        XCTAssertEqual(rig.controller.recoverPendingIntentManually().failure, .readiness(.devNotMountedVolume))
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
    }

    func testOnlyOuterPhysicalReconnectRecoversIntent() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "interrupted")
        _ = rig.controller.handle(.devMounted(uuid: StorageIdentityPolicy.expected.devUUID!))
        _ = rig.controller.handle(.imageChanged)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        _ = rig.controller.handle(.outerDisappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        var invalidReinsert = StorageObservation.expectedReady
        invalidReinsert.dev.uuid = UUID()
        rig.backend.observation = invalidReinsert
        XCTAssertEqual(rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID)).failure,
                       .readiness(.devUUIDMismatch))
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).outerReconnectAttempted)
        let duplicate = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertTrue(duplicate.steps.contains(where: { $0.status == .skipped }))
        XCTAssertEqual(rig.backend.attachCount, 1)
        // Only a new confirmed physical disconnect may permit a subsequent attach attempt.
        _ = rig.controller.handle(.outerDisappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        rig.backend.observation = .expectedReady
        _ = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertFalse(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.backend.attachCount, 2)
    }

    func testDetachedReconnectAttachesBeforeFullObservationAndRetainsIntentOnFailures() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "detached-reconnect",
                                  outerDisappearedAfterIntent: true)
        // While the outer disk is detached, the inner DEV/image chain must not be observable.
        rig.backend.observation = nil

        rig.backend.attachResult = .init(exitCode: 7, detail: "fixture attach failure")
        let attachFailure = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertEqual(attachFailure.failure, .attachFailed(7, "fixture attach failure"))
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.backend.attachCount, 1)
        XCTAssertEqual(rig.backend.observation, nil)

        let repeatedAfterAttachFailure = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertTrue(repeatedAfterAttachFailure.steps.contains(where: { $0.status == .skipped }))
        XCTAssertEqual(rig.backend.attachCount, 1)

        // Only a newly confirmed physical disconnect authorizes another attempt. Attach now
        // succeeds, but a failed full-chain check must still retain durable suppression.
        _ = rig.controller.handle(.outerDisappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        rig.backend.attachResult = .success
        var invalidAttachedChain = StorageObservation.expectedReady
        invalidAttachedChain.dev.uuid = UUID()
        rig.backend.observationAfterAttach = invalidAttachedChain
        let postAttachFailure = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertEqual(postAttachFailure.failure, .readiness(.devUUIDMismatch))
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.backend.attachCount, 2)
        XCTAssertEqual(rig.backend.observation, invalidAttachedChain)

        // A subsequent confirmed detach/reinsert revalidates the outer first, then attach
        // makes the inner chain observable; intent clears only after that full validation.
        _ = rig.controller.handle(.outerDisappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        rig.backend.observationAfterAttach = .expectedReady
        let recovered = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertTrue(recovered.succeeded)
        XCTAssertEqual(recovered.steps.map(\.step), ["verifyOuterIdentity", "attachImage", "verifyReadiness", "clearEjectIntent"])
        XCTAssertFalse(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.backend.attachCount, 3)

        let duplicateAfterRecovery = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertTrue(duplicateAfterRecovery.steps.contains(where: { $0.status == .skipped }))
        XCTAssertEqual(rig.backend.attachCount, 3)
    }

    func testDetachedReinsertRejectsWrongEventOrObservedOuterIdentity() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "detached",
                                  outerDisappearedAfterIntent: true)
        let wrongEvent = rig.controller.handle(.outerReappeared(uuid: UUID()))
        XCTAssertTrue(wrongEvent.steps.contains(where: { $0.status == .skipped }))
        XCTAssertEqual(rig.backend.attachCount, 0)

        rig.backend.outerObservation = outerIdentity { $0.uuid = UUID() }
        let wrongObserved = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertEqual(wrongObserved.failure, .readiness(.outerUUIDMismatch))
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertFalse(try XCTUnwrap(rig.state.current).outerReconnectAttempted)
        XCTAssertEqual(rig.backend.attachCount, 0)
    }

    func testEveryEjectStageFailurePreservesIntentAndStops() throws {
        for failingStep in EjectStep.allCases {
            let rig = ControllerRig()
            rig.backend.failStep = failingStep
            let result = rig.controller.safeEjectHE()
            XCTAssertEqual(result.failure, .stepFailed(failingStep, 9, "fixture failure"))
            XCTAssertEqual(rig.backend.performed.last, failingStep)
            let failedAt = try XCTUnwrap(rig.backend.performed.firstIndex(of: failingStep))
            XCTAssertEqual(Array(rig.backend.performed.suffix(from: failedAt)), [failingStep])
            XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        }
    }

    func testStateCASConflictDoesNotPerformDiskOperation() {
        let rig = ControllerRig()
        rig.state.rejectWrites = true
        let result = rig.controller.safeEjectHE()
        XCTAssertEqual(result.failure, .stateConflict)
        XCTAssertTrue(rig.backend.performed.isEmpty)
    }

    func testMountFailureCannotClearIntentButValidatedManualMountCan() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "interrupted")
        rig.backend.observation?.dev.writable = false
        XCTAssertFalse(rig.controller.mountDEV().succeeded)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        rig.backend.observation = .expectedReady
        XCTAssertTrue(rig.controller.mountDEV().succeeded)
        XCTAssertFalse(try XCTUnwrap(rig.state.current).ejectIntent)
    }

    func testAutomaticMountCannotRecoverPendingIntentOrAttach() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "interrupted")
        let result = rig.controller.mountDEV(mode: .automatic)
        XCTAssertEqual(result.failure, .recoveryRequiresManualMount)
        XCTAssertEqual(rig.backend.attachCount, 0)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
    }

    func testSecondEjectIsRejectedWhileIntentIsPending() {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "interrupted")
        XCTAssertEqual(rig.controller.safeEjectHE().failure, .ejectAlreadyPending)
        XCTAssertTrue(rig.backend.performed.isEmpty)
    }
}

private final class ControllerRig {
    let backend = FakeBackend()
    let state = FakeState()
    let lock = FakeLock()
    lazy var controller = StorageController(backend: backend, store: state, lock: lock)
}

private func readinessFailure(_ result: Result<Void, ReadinessFailure>) -> ReadinessFailure? {
    if case .failure(let failure) = result { return failure }
    return nil
}

private func outerIdentity(_ mutate: (inout VolumeIdentity) -> Void) -> VolumeIdentity {
    var value = StorageObservation.expectedReady.outer
    mutate(&value)
    return value
}

private final class FakeBackend: StorageBackend {
    var outerObservation: VolumeIdentity? = StorageObservation.expectedReady.outer
    var observation: StorageObservation? = .expectedReady
    var observationAfterAttach: StorageObservation?
    var attachResult: CommandOutcome = .success
    var attachCount = 0
    var occupancy: OccupancyAssessment = .noVisibleOccupancy
    var occupancyByScope: [OccupancyScope: OccupancyAssessment] = [:]
    var failStep: EjectStep?
    var finalState: FinalOuterState = .absent
    var performed: [EjectStep] = []
    var assessedScopes: [OccupancyScope] = []
    func observeOuter() -> VolumeIdentity? { outerObservation }
    func observe() -> StorageObservation? { observation }
    func attachImage() -> CommandOutcome {
        attachCount += 1
        if attachResult.succeeded, let observationAfterAttach { observation = observationAfterAttach }
        return attachResult
    }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment {
        assessedScopes.append(scope)
        return occupancyByScope[scope] ?? occupancy
    }
    func perform(_ step: EjectStep) -> CommandOutcome {
        performed.append(step)
        return failStep == step ? .init(exitCode: 9, detail: "fixture failure") : .success
    }
    func finalOuterState() -> FinalOuterState { finalState }
}

private final class FakeState: DurableStateStore {
    var current = StoragePersistentState(ejectIntent: false)
    var rejectWrites = false
    var writeCount = 0
    func load() throws -> StoragePersistentState { current }
    func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
        writeCount += 1
        guard !rejectWrites, current.revision == expectedRevision,
              newState.revision == expectedRevision + 1 else { return false }
        current = newState
        return true
    }
}

private final class FakeLock: OperationLock {
    var isHeld = false
    func acquire() -> Bool {
        guard !isHeld else { return false }
        isHeld = true
        return true
    }
    func release() { isHeld = false }
}
