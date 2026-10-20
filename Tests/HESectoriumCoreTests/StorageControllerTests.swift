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

    func testExitAndAutomaticReconnectRetainIntentUntilValidatedManualRecovery() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "interrupted")
        XCTAssertTrue(try XCTUnwrap(rig.controller.processExit()).ejectIntent)
        _ = rig.controller.handle(.outerDisappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        let reconnected = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertEqual(reconnected.failure, .recoveryRequiresManualMount)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.backend.attachCount, 0)
        _ = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertEqual(rig.backend.attachCount, 0)
        XCTAssertTrue(rig.controller.recoverPendingIntentManually().succeeded)
        XCTAssertFalse(try XCTUnwrap(rig.state.current).ejectIntent)
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
        XCTAssertEqual(rig.backend.attachCount, 0, "Verified existing image must be reused")
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

    func testOnlyVerifiedPhysicalReconnectIsRecordedWhileIntentRemainsPending() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "interrupted")
        _ = rig.controller.handle(.devMounted(uuid: StorageIdentityPolicy.expected.devUUID!))
        _ = rig.controller.handle(.imageChanged)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        rig.backend.finalState = .stillPresent
        XCTAssertEqual(rig.controller.handle(.outerDisappeared(uuid: StorageIdentityPolicy.expected.outerUUID)).failure,
                       .outerStillPresent)
        XCTAssertFalse(rig.state.current.outerDisappearedAfterIntent)
        rig.backend.finalState = .absent
        _ = rig.controller.handle(.outerDisappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertEqual(rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID)).failure,
                       .recoveryRequiresManualMount)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertTrue(try XCTUnwrap(rig.state.current).outerReconnectAttempted)
        let duplicate = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertTrue(duplicate.steps.contains(where: { $0.status == .skipped }))
        XCTAssertEqual(rig.backend.attachCount, 0)
    }

    func testDetachedReconnectNeverAutomaticallyAttachesAndManualRecoveryValidates() throws {
        let rig = ControllerRig()
        rig.state.current = .init(ejectIntent: true, operationID: "detached-reconnect",
                                  outerDisappearedAfterIntent: true)
        rig.backend.observation = nil
        let observed = rig.controller.handle(.outerReappeared(uuid: StorageIdentityPolicy.expected.outerUUID))
        XCTAssertEqual(observed.failure, .recoveryRequiresManualMount)
        XCTAssertEqual(rig.backend.attachCount, 0)
        var invalidAttachedChain = StorageObservation.expectedReady
        invalidAttachedChain.dev.uuid = UUID()
        rig.backend.observationAfterAttach = invalidAttachedChain
        XCTAssertEqual(rig.controller.recoverPendingIntentManually().failure, .readiness(.devUUIDMismatch))
        XCTAssertTrue(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.backend.attachCount, 1)
        rig.backend.observationAfterAttach = .expectedReady
        let recovered = rig.controller.recoverPendingIntentManually()
        XCTAssertTrue(recovered.succeeded)
        XCTAssertEqual(recovered.steps.map(\.step), ["verifyOuterIdentity", "attachImage", "verifyReadiness", "clearEjectIntent"])
        XCTAssertFalse(try XCTUnwrap(rig.state.current).ejectIntent)
        XCTAssertEqual(rig.backend.attachCount, 2)
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

    func testTwoRegisteredProfilesKeepSuppressionSeparateAcrossRestart() throws {
        let rig = ControllerRig()
        let (policyA, readyA) = registeredFixture("A")
        let (policyB, readyB) = registeredFixture("B")
        var suppressedState = rig.state.current.advancingRevision()
        XCTAssertTrue(suppressedState.suppressProfile("profile-A"))
        XCTAssertTrue(try rig.state.compareAndSwap(expectedRevision: rig.state.current.revision,
                                                    newState: suppressedState))
        let backendA = FakeBackend()
        backendA.outerObservation = readyA.outer
        backendA.observation = readyA
        let backendB = FakeBackend()
        backendB.outerObservation = readyB.outer
        backendB.observation = nil
        backendB.observationAfterAttach = readyB

        let suppressed = rig.controller.mountRegisteredProfileAtStartup(
            profileID: "profile-A", policy: policyA, backend: backendA)
        XCTAssertTrue(suppressed.steps.contains { $0.step == "profileSuppressed" && $0.status == .skipped })
        XCTAssertEqual(backendA.attachCount, 0)
        XCTAssertEqual(backendA.observation, readyA, "Suppression must not alter observed mounted state")
        XCTAssertTrue(rig.controller.mountRegisteredProfileAtStartup(
            profileID: "profile-B", policy: policyB, backend: backendB).succeeded)
        XCTAssertEqual(backendB.attachCount, 1)
        XCTAssertEqual(rig.state.current.suppressedProfileIDs, ["profile-A"])
        XCTAssertEqual(rig.state.current.reconnectAttemptedProfileIDs, ["profile-B"])

        let restarted = StorageController(backend: rig.backend, store: rig.state, lock: rig.lock)
        let duplicate = restarted.mountRegisteredProfileAtStartup(
            profileID: "profile-B", policy: policyB, backend: backendB)
        XCTAssertTrue(duplicate.steps.contains { $0.step == "reuseVerifiedImage" })
        XCTAssertEqual(backendB.attachCount, 1)
    }

    func testRegisteredFirstArrivalLoadsOnceAndVerifiedReconnectReusesMountedImage() {
        let rig = ControllerRig()
        let (policy, ready) = registeredFixture("A")
        let backend = FakeBackend()
        backend.outerObservation = ready.outer
        backend.observation = nil
        backend.observationAfterAttach = ready
        let event = StorageEvent.outerReappeared(uuid: policy.outerUUID)
        let firstAppear = rig.controller.handleRegisteredProfileEvent(
            event, profileID: "profile-A", policy: policy, backend: backend)
        XCTAssertTrue(firstAppear.succeeded)
        XCTAssertEqual(backend.attachCount, 1, "The first insertion need not have been observed disconnecting")
        XCTAssertTrue(rig.controller.handleRegisteredProfileEvent(
            event, profileID: "profile-A", policy: policy, backend: backend)
            .steps.contains { $0.status == .skipped })
        XCTAssertEqual(backend.attachCount, 1)

        backend.finalState = .unknown("incomplete device inventory")
        XCTAssertEqual(rig.controller.handleRegisteredProfileEvent(
            .outerDisappeared(uuid: policy.outerUUID), profileID: "profile-A", policy: policy,
            backend: backend).failure, .finalStateUnknown("incomplete device inventory"))
        XCTAssertTrue(rig.state.current.disconnectedProfileIDs.isEmpty)
        backend.finalState = .absent
        backend.observation = nil
        XCTAssertTrue(rig.controller.handleRegisteredProfileEvent(
            .outerDisappeared(uuid: policy.outerUUID), profileID: "profile-A", policy: policy,
            backend: backend).succeeded)
        XCTAssertTrue(rig.controller.handleRegisteredProfileEvent(
            event, profileID: "profile-A", policy: policy, backend: backend).succeeded)
        XCTAssertEqual(backend.attachCount, 2)
        XCTAssertFalse(rig.state.current.disconnectedProfileIDs.contains("profile-A"))
        XCTAssertTrue(rig.state.current.reconnectAttemptedProfileIDs.contains("profile-A"))
        XCTAssertTrue(rig.controller.handleRegisteredProfileEvent(
            event, profileID: "profile-A", policy: policy, backend: backend)
            .steps.contains { $0.status == .skipped })
        XCTAssertEqual(backend.attachCount, 2)

        backend.observation = nil
        XCTAssertTrue(rig.controller.handleRegisteredProfileEvent(
            .outerDisappeared(uuid: policy.outerUUID), profileID: "profile-A", policy: policy,
            backend: backend).succeeded)
        backend.observation = ready
        let reused = rig.controller.handleRegisteredProfileEvent(
            event, profileID: "profile-A", policy: policy, backend: backend)
        XCTAssertTrue(reused.succeeded)
        XCTAssertTrue(reused.steps.contains { $0.step == "reuseVerifiedImage" })
        XCTAssertEqual(backend.attachCount, 2)
    }

    func testManualUnloadSurvivesRestartAndNoiseButTrueReconnectResumesAutoload() {
        let rig = ControllerRig()
        let (policy, ready) = registeredFixture("A")
        let backend = FakeBackend()
        backend.outerObservation = ready.outer
        backend.observation = nil
        backend.observationAfterAttach = ready
        rig.state.current = .init(ejectIntent: false,
            suppressedProfileIDs: ["profile-A", "profile-B"],
            reconnectAttemptedProfileIDs: ["profile-A"])
        let restarted = StorageController(backend: rig.backend, store: rig.state, lock: rig.lock)
        XCTAssertTrue(restarted.mountRegisteredProfileAtStartup(profileID: "profile-A", policy: policy,
            backend: backend).steps.contains { $0.step == "profileSuppressed" })
        XCTAssertTrue(restarted.handleRegisteredProfileEvent(.outerReappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend)
            .steps.contains { $0.step == "profileSuppressed" })
        backend.finalState = .stillPresent
        XCTAssertEqual(restarted.handleRegisteredProfileEvent(.outerDisappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend).failure, .outerStillPresent)
        XCTAssertEqual(backend.attachCount, 0)
        XCTAssertEqual(rig.state.current.suppressedProfileIDs, ["profile-A", "profile-B"])

        backend.finalState = .absent
        XCTAssertTrue(restarted.handleRegisteredProfileEvent(.outerDisappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend).succeeded)
        // Disappearance alone does not undo the user's intent. A matching,
        // freshly verified device must return before its load is claimed.
        XCTAssertTrue(rig.state.current.suppressedProfileIDs.contains("profile-A"))
        backend.outerObservation?.uuid = UUID()
        XCTAssertEqual(restarted.handleRegisteredProfileEvent(.outerReappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend).failure, .readiness(.outerUUIDMismatch))
        XCTAssertTrue(rig.state.current.suppressedProfileIDs.contains("profile-A"))
        backend.outerObservation = ready.outer
        XCTAssertTrue(restarted.handleRegisteredProfileEvent(.outerReappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend).succeeded)
        XCTAssertEqual(backend.attachCount, 1)
        XCTAssertEqual(rig.state.current.suppressedProfileIDs, ["profile-B"])
        XCTAssertFalse(rig.state.current.disconnectedProfileIDs.contains("profile-A"))
    }

    func testReconnectNeverOverridesAnUnfinishedEjectOrFailedClaim() {
        let rig = ControllerRig()
        let (policy, ready) = registeredFixture("A")
        let backend = FakeBackend()
        backend.outerObservation = ready.outer
        backend.observation = nil
        backend.observationAfterAttach = ready
        rig.state.current = .init(ejectIntent: true, suppressedProfileIDs: ["profile-A"],
            disconnectedProfileIDs: ["profile-A"])
        XCTAssertEqual(rig.controller.mountRegisteredProfileAtStartup(profileID: "profile-A",
            policy: policy, backend: backend).failure, .recoveryRequiresManualMount)
        rig.state.current.ejectIntent = false
        rig.state.rejectWrites = true
        let before = rig.state.current
        XCTAssertEqual(rig.controller.mountRegisteredProfileAtStartup(profileID: "profile-A",
            policy: policy, backend: backend).failure, .stateConflict)
        XCTAssertEqual(rig.state.current, before)
        XCTAssertEqual(backend.attachCount, 0)
    }

    func testFailedRegisteredAttachRetriesOnlyOnNewStartupOrFreshDisconnect() {
        let rig = ControllerRig()
        let (policy, ready) = registeredFixture("A")
        let backend = FakeBackend()
        backend.outerObservation = ready.outer
        backend.observation = nil
        backend.attachResult = .init(exitCode: 7, detail: "fixture failure")
        _ = rig.controller.handleRegisteredProfileEvent(.outerDisappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend)
        XCTAssertEqual(rig.controller.handleRegisteredProfileEvent(.outerReappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend).failure, .attachFailed(7, "fixture failure"))
        XCTAssertTrue(rig.state.current.reconnectAttemptedProfileIDs.contains("profile-A"))
        let restarted = StorageController(backend: rig.backend, store: rig.state, lock: rig.lock)
        XCTAssertEqual(restarted.mountRegisteredProfileAtStartup(
            profileID: "profile-A", policy: policy, backend: backend).failure, .attachFailed(7, "fixture failure"))
        XCTAssertEqual(backend.attachCount, 2)
        XCTAssertTrue(restarted.mountRegisteredProfileAtStartup(
            profileID: "profile-A", policy: policy, backend: backend).steps.contains { $0.status == .skipped })
        _ = restarted.handleRegisteredProfileEvent(.outerReappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend)
        XCTAssertEqual(backend.attachCount, 2, "Duplicate startup/arrival must not retry a failed attempt")

        _ = restarted.handleRegisteredProfileEvent(.outerDisappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend)
        backend.attachResult = .success
        backend.observationAfterAttach = ready
        XCTAssertTrue(restarted.handleRegisteredProfileEvent(.outerReappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend).succeeded)
        XCTAssertEqual(backend.attachCount, 3)
    }

    func testOnlyFreshManualProfileValidationClearsItsSuppression() {
        let (policyA, readyA) = registeredFixture("A")
        let (_, readyB) = registeredFixture("B")
        var state = StoragePersistentState(ejectIntent: false, suppressedProfileIDs: ["profile-A", "profile-B"],
            disconnectedProfileIDs: ["profile-A", "profile-B"])
        XCTAssertFalse(state.clearProfileSuppressionAfterValidatedLoad(
            "profile-A", policy: policyA, observation: readyB))
        XCTAssertEqual(state.suppressedProfileIDs, ["profile-A", "profile-B"])
        XCTAssertTrue(state.clearProfileSuppressionAfterValidatedLoad(
            "profile-A", policy: policyA, observation: readyA))
        XCTAssertEqual(state.suppressedProfileIDs, ["profile-B"])
        XCTAssertEqual(state.disconnectedProfileIDs, ["profile-B"])
        XCTAssertTrue(state.reconnectAttemptedProfileIDs.contains("profile-A"))
        state.ejectIntent = true
        XCTAssertFalse(state.clearProfileSuppressionAfterValidatedLoad(
            "profile-B", policy: policyA, observation: readyA))
    }

    func testInvalidObservedRegisteredImageRefusesBeforeAnotherAttach() {
        let rig = ControllerRig()
        let (policy, ready) = registeredFixture("A")
        let backend = FakeBackend()
        backend.outerObservation = ready.outer
        var wrong = ready
        wrong.image.attachedVolumeUUID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")
        backend.observation = wrong
        backend.observationAfterAttach = ready
        let result = rig.controller.mountRegisteredProfileAtStartup(
            profileID: "profile-A", policy: policy, backend: backend)
        XCTAssertEqual(result.failure, .readiness(.imageRelationMismatch))
        XCTAssertTrue(result.steps.contains { $0.step == "verifyExistingImage" && $0.status == .failed })
        XCTAssertEqual(backend.attachCount, 0)
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

private func registeredFixture(_ suffix: String) -> (StorageIdentityPolicy, StorageObservation) {
    let outerUUID = UUID(uuidString: suffix == "A" ? "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA" : "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let devUUID = UUID(uuidString: suffix == "A" ? "AAAAAAAA-0000-0000-0000-AAAAAAAAAAAA" : "BBBBBBBB-0000-0000-0000-BBBBBBBBBBBB")!
    let outer = "/Volumes/FIXTURE-\(suffix)"
    let dev = "\(outer)/DEV"
    let image = "\(outer)/.DEV-\(suffix).sparsebundle"
    let policy = StorageIdentityPolicy(outerUUID: outerUUID, devUUID: devUUID,
        outerMountPoint: outer, devMountPoint: dev, devVolumeName: "DEV_\(suffix)", imagePath: image)
    let observation = StorageObservation(
        outer: .init(uuid: outerUUID, mountPoint: outer, fileSystem: "ExFAT", writable: true,
                     name: "FIXTURE-\(suffix)", rootMatchesExpected: true),
        dev: .init(uuid: devUUID, mountPoint: dev, fileSystem: "APFS", writable: true,
                   name: "DEV_\(suffix)", rootMatchesExpected: true),
        image: .init(backingVolumeUUID: outerUUID, attachedVolumeUUID: devUUID, path: image))
    return (policy, observation)
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

// Regression cases supplied by independent review; safe injected backends only.
extension StorageControllerTests {
    func testReview_NewerManualUnloadMustOverrideEarlierDisconnectEvidence() {
        let rig = ControllerRig()
        let (policy, ready) = registeredFixture("A")
        let backend = FakeBackend()
        backend.outerObservation = ready.outer
        backend.finalState = .absent
        XCTAssertTrue(rig.controller.handleRegisteredProfileEvent(.outerDisappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend).succeeded)
        // Device returns with autoLoad disabled. An external/native image attach
        // is verified and then manually stopped through AUV. Service uses this
        // exact Core suppressProfile API before its normal flush/unmount/detach.
        XCTAssertTrue(rig.state.current.suppressProfile("profile-A"))
        backend.observation = nil
        backend.observationAfterAttach = ready
        // A later startup/arrival after enabling autoLoad is still the same
        // physical connection as that newer manual unload.
        _ = rig.controller.handleRegisteredProfileEvent(.outerReappeared(uuid: policy.outerUUID),
            profileID: "profile-A", policy: policy, backend: backend)
        XCTAssertEqual(backend.attachCount, 0, "A disconnect preceding manual unload cannot authorize a later remount")
        XCTAssertTrue(rig.state.current.suppressedProfileIDs.contains("profile-A"))
    }
    func testReview_StartupMustReconcileUnsuppressedLostAttachment() {
        let rig = ControllerRig()
        let (policy, ready) = registeredFixture("A")
        let backend = FakeBackend()
        backend.outerObservation = ready.outer
        backend.observation = nil
        backend.observationAfterAttach = ready
        XCTAssertTrue(rig.controller.mountRegisteredProfileAtStartup(profileID: "profile-A", policy: policy,
            backend: backend).succeeded)
        XCTAssertEqual(backend.attachCount, 1)
        // macOS restarts with the parent still connected. The old process cannot
        // record physical absence, while the image attachment no longer exists.
        backend.observation = nil
        let restarted = StorageController(backend: rig.backend, store: rig.state, lock: rig.lock)
        _ = restarted.mountRegisteredProfileAtStartup(profileID: "profile-A", policy: policy, backend: backend)
        XCTAssertEqual(backend.attachCount, 2, "Startup must reconcile an unsuppressed registered volume, not trust an old attempt")
    }
}
