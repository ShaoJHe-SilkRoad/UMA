import AppKit
import Foundation
import HESectoriumCore
import HESectoriumRuntime
import Testing
@testable import CodexUsageUI

@Suite("Sectorium visible state freshness", .serialized)
@MainActor
struct SectoriumVisibleStateTests {
    @Test("Unload publishes verified success and Load before unrelated observation; next Load restores actions")
    func unloadThenLoadPublishesTargetCompletion() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.runner.enableLifecycleSimulation()
        fixture.runner.setActivity(.init(exitCode: 1, detail: ""))
        try fixture.recordPendingDocumentation()
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canUnloadOnly == true }
        let unload = fixture.runner.blockNextMutation()
        defer { unload.release() }
        fixture.store.prepareUnloadOnlyConfirmation(profileID: fixture.profile.id)
        try await eventually(diagnostics: fixture.diagnostics) { unload.entered }
        #expect(fixture.store.isBusy && fixture.store.activeWorkbenchAction == .unload)
        #expect(fixture.store.progressNotice.english.contains("Unloading"))
        let observation = fixture.consistency.blockNextRead()
        defer { observation.release() }
        unload.release()
        try await eventually(diagnostics: fixture.diagnostics) { observation.entered && !fixture.store.isBusy }
        let unloaded = try #require(fixture.store.volumeRows.first)
        #expect(unloaded.verifiedLoaded == false && unloaded.parentConnected && unloaded.canLoad && !unloaded.isBusy)
        #expect(!unloaded.canUnloadOnly && !unloaded.canSafeUnloadAndEject)
        #expect(fixture.store.workbench.pendingOperation == nil)
        #expect(fixture.store.userNotice?.english.hasPrefix("Unload successful") == true)
        #expect(unloaded.message(isChinese: false).isEmpty, "Pending documentation must not replace Unloaded")
        fixture.store.deactivateWorkbench()
        fixture.store.activateWorkbench()
        #expect(fixture.store.volumeRows.first?.canLoad == true, "Tab reentry retains the terminal command receipt")
        fixture.diskEvents.emit(.init(kind: .disappeared, volumeUUID: fixture.profile.devUUID))
        await settle()
        #expect(fixture.store.volumeRows.first?.canLoad == true,
            "A delayed native child disappearance agrees with verified Unloaded")
        #expect(fixture.store.userNotice?.english.hasPrefix("Unload successful") == true)
        let reads = fixture.agentStatus.reads
        observation.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canLoad == true
                && fixture.agentStatus.reads > reads
        }
        #expect(fixture.store.userNotice?.english.hasPrefix("Unload successful") == true,
            "An unchanged background observation must retain successful operation feedback")
        let changed = fixture.consistency.blockNextRead()
        defer { changed.release() }
        fixture.diskEvents.emit(.init(kind: .descriptionChanged, wholeDiskBSDName: fixture.device.bsdName))
        try await eventually(diagnostics: fixture.diagnostics) { changed.entered }
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil && fixture.store.volumeRows.first?.canLoad == false,
            "An unknown description change must revoke actions until freshly observed")
        #expect(fixture.store.userNotice?.english.hasPrefix("Unload successful") == true,
            "Requalification retains the completed command receipt as feedback")
        changed.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canLoad == true
        }
        #expect(fixture.store.userNotice?.english.hasPrefix("Unload successful") == true)
        let mount = fixture.runner.blockNextMutation()
        defer { mount.release() }
        fixture.store.loadDevelopmentDisk(profileID: fixture.profile.id)
        try await eventually(diagnostics: fixture.diagnostics) { mount.entered }
        #expect(fixture.store.progressNotice.english.hasPrefix("Loading"))
        mount.release()
        try await eventually(diagnostics: fixture.diagnostics) { !fixture.store.isBusy && fixture.store.volumeRows.first?.verifiedLoaded == true }
        #expect(fixture.store.userNotice?.english.hasPrefix("Load successful") == true)
        #expect(fixture.store.volumeRows.first?.canUnloadOnly == true)
        #expect(fixture.runner.mutationCalls.map { $0[1] } == ["unmount", "mount"])
        #expect(fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Native unload failure keeps real failure and cannot offer a fabricated successful Load")
    func failedUnloadDoesNotPublishSuccess() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.runner.enableLifecycleSimulation(unloadFails: true)
        fixture.runner.setActivity(.init(exitCode: 1, detail: ""))
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canUnloadOnly == true }
        fixture.store.prepareUnloadOnlyConfirmation(profileID: fixture.profile.id)
        try await eventually(diagnostics: fixture.diagnostics) { !fixture.store.isBusy && fixture.store.lastResult.contains("Failed:") }
        #expect(fixture.store.userNotice?.english.contains("did not finish") == true)
        #expect(fixture.store.volumeRows.first?.canLoad != true)
        #expect(!fixture.store.workbench.safeToUnplug)
    }

    @Test("Disconnect success requires authoritative absence and only clears its own drive")
    func disconnectReceiptPublishesTargetOnly() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        let second = try fixture.addInternalProfile()
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let other = try #require(fixture.store.volumeRows.first { $0.id == second.id })
        let receipt = OperationResult(operationID: "fixture-disconnect", mode: .manual, steps: [
            .init(step: "ejectWholeDevice", status: .succeeded),
            .init(step: "verifyPhysicalDeviceAbsent", status: .succeeded)])
        #expect(fixture.store.publishVerifiedCommandCompletion(result: receipt, action: .disconnect,
            profileID: nil, deviceID: fixture.device.id, name: fixture.device.name, pending: nil))
        #expect(fixture.store.workbench.safeToUnplug && fixture.store.userNotice?.english.hasPrefix("Disconnect successful") == true)
        #expect(fixture.store.volumeRows.first { $0.id == fixture.profile.id }?.parentConnected == false)
        #expect(fixture.store.volumeRows.first { $0.id == fixture.profile.id }?.verifiedLoaded == false)
        #expect(fixture.store.volumeRows.first { $0.id == second.id } == other)
        let observation = fixture.consistency.blockNextRead()
        defer { observation.release() }
        fixture.diskEvents.emit(.init(kind: .disappeared, bsdName: fixture.device.bsdName))
        try await eventually(diagnostics: fixture.diagnostics) { observation.entered }
        #expect(fixture.store.workbench.safeToUnplug && fixture.store.safeToUnplugDriveName != nil,
            "The matching delayed disappearance preserves verified Disconnect completion")
        fixture.diskEvents.emit(.init(kind: .appeared, bsdName: fixture.device.bsdName))
        await settle()
        #expect(!fixture.store.workbench.safeToUnplug && fixture.store.safeToUnplugDriveName == nil,
            "Reconnection immediately revokes the previous safe-to-unplug qualification")
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0,
            "This presentation receipt fixture never runs a disk operation")
    }

    @Test("Saved successful eject completes while the USB node remains, survives refresh, and resets on reconnect")
    func logicalEjectRecoverySurvivesRefreshAndReconnect() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        try fixture.recordSuccessfulEjectCallback()
        fixture.ejectDriver.setLogicallyEjected(true)
        fixture.runner.setLoaded(false)
        // The inventory deliberately still contains the same physical device.
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.service.verifiedSafelyEjectedDeviceIDs() == [fixture.device.id])
        #expect(fixture.service.profileReadiness(profileID: fixture.profile.id) == .ejected)
        #expect(fixture.service.verifiedLoadedState(profileID: fixture.profile.id) == false)
        #expect(fixture.store.workbench.pendingOperation == nil)
        #expect(fixture.store.workbench.safeToUnplug)
        #expect(fixture.store.userNotice == SectoriumCommandAction.disconnect.success)
        let disconnected = try #require(fixture.store.volumeRows.first)
        #expect(!disconnected.parentConnected && disconnected.verifiedLoaded == false)
        #expect(!disconnected.canLoad && !disconnected.canUnloadOnly && !disconnected.canSafeUnloadAndEject)
        #expect(!fixture.store.canContinueWholeDeviceEject)

        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.workbench.safeToUnplug)
        #expect(fixture.store.userNotice == SectoriumCommandAction.disconnect.success)
        fixture.store.deactivateWorkbench()
        fixture.store.activateWorkbench()
        await settle()
        #expect(fixture.store.workbench.safeToUnplug)
        #expect(fixture.store.volumeRows.map(\.id) == [fixture.profile.id])

        fixture.ejectDriver.setLogicallyEjected(false)
        fixture.diskEvents.emit(.init(kind: .appeared, bsdName: fixture.device.bsdName))
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canLoad == true
        }
        #expect(fixture.service.verifiedSafelyEjectedDeviceIDs().isEmpty)
        #expect(!fixture.store.workbench.safeToUnplug)
        #expect(fixture.store.workbench.pendingOperation == nil)
        #expect(fixture.store.volumeRows.first?.parentConnected == true)
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == false)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("A fresh unknown identity revokes an earlier safe-eject presentation")
    func unknownAfterLogicalEjectRevokesSafeResult() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        try fixture.recordSuccessfulEjectCallback()
        fixture.ejectDriver.setLogicallyEjected(true)
        fixture.runner.setLoaded(false)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.workbench.safeToUnplug)

        fixture.ejectDriver.setLogicallyEjected(nil)
        fixture.observer.setPresent(false)
        fixture.observer.setAdditionalDevices([.init(id: "unverified-" + fixture.device.bsdName,
            bsdName: fixture.device.bsdName, name: fixture.device.name, isExternal: true,
            identityVerified: false, wholeDeviceBytes: fixture.device.wholeDeviceBytes,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
            topologyComplete: false, isVirtual: false)])
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.service.verifiedSafelyEjectedDeviceIDs().isEmpty)
        #expect(!fixture.store.workbench.safeToUnplug)
        #expect(fixture.store.userNotice != SectoriumCommandAction.disconnect.success)
        #expect(fixture.store.safeToUnplugDriveName == nil)
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("A completed logical-eject receipt qualifies Disconnect but a bare command exit does not")
    func logicalEjectReceiptRequiresPostcondition() {
        let command = OperationStepResult(step: "ejectWholeDevice", status: .succeeded)
        let verified = OperationStepResult(step: "verifyWholeDeviceEjected", status: .succeeded)
        #expect(!SectoriumCommandAction.disconnect.isVerified(
            by: .init(operationID: "bare", mode: .manual, steps: [command]), pending: nil))
        #expect(SectoriumCommandAction.disconnect.isVerified(
            by: .init(operationID: "verified", mode: .manual, steps: [command, verified]), pending: nil))
        #expect(!SectoriumCommandAction.disconnect.isVerified(
            by: .init(operationID: "pending", mode: .manual, steps: [command, verified]), pending: "eject:pending"))
    }

    @Test("Named blockers require explicit quit consent and are freshly checked after a normal quit")
    func namedBlockerQuitAndRetry() async throws {
        let quitter = VisibleStateQuitter()
        let fixture = try VisibleStateFixture(applicationQuitter: quitter)
        defer { fixture.finish() }
        fixture.runner.setActivity(.init(exitCode: 0, detail: "p41001\ncFixtureEditor\nfcwd\np41002\ncOtherTool\nfcwd\n"))
        quitter.onQuit = {
            fixture.runner.setActivity(.init(exitCode: 0, detail: "p41002\ncOtherTool\nfcwd\n"))
        }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canUnloadOnly == true }
        fixture.store.prepareUnloadOnlyConfirmation(profileID: fixture.profile.id)
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.safetyCheck?.processes.count == 2 }
        #expect(fixture.store.safetyCheck?.applications.map(\.name) == ["Fixture Editor"])
        #expect(fixture.store.safetyCheck?.processes.first?.references.first?.descriptor == "cwd")
        #expect(quitter.requests.isEmpty && fixture.runner.mutationCalls.isEmpty,
            "An occupancy report or merely opening the prompt never grants app-quit consent")
        fixture.store.quitBlockingApplicationsAndRetry()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.safetyCheck?.processes.map(\.processID) == [41002] && !fixture.store.isBusy }
        #expect(quitter.requests == [41001])
        #expect(fixture.store.safetyCheck?.canProceed == false && fixture.store.safetyCheck?.applications.isEmpty == true)
        #expect(fixture.runner.mutationCalls.isEmpty,
            "A successful app quit cannot bypass remaining process references")
        fixture.store.cancelSafetyCheck()
        #expect(fixture.store.safetyCheck == nil && !fixture.store.isBusy)
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
    }

    @Test("Cancelling named blockers leaves every app and volume untouched")
    func cancelNamedBlockersDoesNotQuit() async throws {
        let quitter = VisibleStateQuitter()
        let fixture = try VisibleStateFixture(applicationQuitter: quitter)
        defer { fixture.finish() }
        fixture.runner.setActivity(.init(exitCode: 0, detail: "p41001\ncFixtureEditor\nfcwd\n"))
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canUnloadOnly == true }
        fixture.store.prepareUnloadOnlyConfirmation(profileID: fixture.profile.id)
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.safetyCheck != nil }
        fixture.store.cancelSafetyCheck()
        #expect(quitter.requests.isEmpty && fixture.runner.mutationCalls.isEmpty && !fixture.store.isBusy)
    }

    @Test("Cold inventory appears before the consistency probe without granting storage actions")
    func initialInventoryPrecedesConsistencyAndQualification() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let registry = try Data(contentsOf: fixture.service.paths.sectoriumProfiles)
        let gate = fixture.consistency.blockNextRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) {
            gate.entered && fixture.store.inventoryState == .available
        }
        #expect(fixture.store.workbench.devices.map(\.id) == [fixture.device.id])
        #expect(!fixture.store.hasObservedStatus && !fixture.store.hasObservedRegistrations)
        #expect(fixture.store.volumeRows.isEmpty && fixture.store.workbench.readiness != .ready)
        #expect(!fixture.store.canBeginWholeDeviceEject && !fixture.store.canContinueWholeDeviceEject)
        #expect(!fixture.store.canReturnFromWholeDeviceEject && !fixture.store.workbench.safeToUnplug)
        #expect(fixture.agentStatus.reads == 0)
        let calls = fixture.observer.calls
        fixture.store.deactivateWorkbench()
        fixture.store.activateWorkbench()
        await settle()
        #expect(fixture.observer.calls == calls, "Navigation must not restart the display probe")
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canSafeUnloadAndEject == true
        }
        #expect(try Data(contentsOf: fixture.service.paths.sectoriumProfiles) == registry)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Startup automation holding the service lock cannot hide physical inventory")
    func initialInventoryDoesNotWaitForAutomaticOperation() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        var saved = fixture.profile
        saved.autoLoad = true
        saved.autoLoadWasConfigured = true
        try JSONEncoder().encode([saved]).write(to: fixture.service.paths.sectoriumProfiles)
        let gate = fixture.runner.blockInfoRead(at: fixture.profile.backingMountPoint)
        defer { gate.release() }
        let service = fixture.service
        let startup = Task.detached { service.runApplicationAutomationAtStartup() }
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.inventoryState == .available }
        #expect(fixture.store.workbench.devices.map(\.id) == [fixture.device.id])
        #expect(!fixture.store.hasObservedStatus && fixture.store.volumeRows.isEmpty)
        #expect(!fixture.store.canBeginWholeDeviceEject && !fixture.store.workbench.safeToUnplug)
        #expect(fixture.store.workbench.readiness != .ready)
        #expect(fixture.agentStatus.reads == 0, "Full qualification still waits for the owning operation")
        gate.release()
        _ = await startup.value
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canSafeUnloadAndEject == true
        }
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0,
            "The already-loaded fixture must not dispatch host or simulated disk mutations")
    }

    @Test("A superseded initial inventory result cannot restore a physically disappeared drive")
    func staleInitialInventoryIsDiscarded() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        let inventoryGate = fixture.observer.blockNextObservation()
        let consistencyGate = fixture.consistency.blockNextRead()
        defer { inventoryGate.release(); consistencyGate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { inventoryGate.entered }
        fixture.observer.setPresent(false)
        fixture.diskEvents.emit(.init(kind: .disappeared, bsdName: fixture.device.bsdName))
        await settle()
        inventoryGate.release()
        try await eventually(diagnostics: fixture.diagnostics) { consistencyGate.entered }
        await settle()
        #expect(fixture.store.workbench.devices.isEmpty,
            "The delayed display result contains the old drive but its generation is obsolete")
        #expect(!fixture.store.hasObservedStatus && !fixture.store.canBeginWholeDeviceEject)
        consistencyGate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.inventoryState == .empty)
        #expect(fixture.store.volumeRows.first?.parentConnected == false)
        #expect(!fixture.store.workbench.safeToUnplug)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("A superseded consistency probe skips recovery and deep checks before one fresh observation")
    func supersededConsistencyStopsBeforeDeepRead() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let calls = fixture.observer.calls, commands = fixture.runner.commandCount
        let old = fixture.consistency.blockNextRead()
        defer { old.release() }
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { old.entered }
        fixture.observer.setPresent(false)
        fixture.diskEvents.emit(.init(kind: .disappeared, bsdName: fixture.device.bsdName))
        await settle()
        let fresh = fixture.consistency.blockNextRead()
        defer { fresh.release() }
        old.release()
        try await eventually(diagnostics: fixture.diagnostics) { fresh.entered }
        #expect(fixture.observer.calls == calls && fixture.runner.commandCount == commands,
            "An invalidated consistency result must not start recovery, inventory or profile commands")
        #expect(!fixture.store.hasObservedStatus && !fixture.store.canBeginWholeDeviceEject)
        #expect(fixture.store.volumeRows.first?.parentConnected == false)
        fresh.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        await settle()
        #expect(fixture.store.inventoryState == .empty && fixture.consistency.reads == 3)
        #expect(fixture.agentStatus.reads == 2 && !fixture.store.workbench.safeToUnplug)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("An invalidated observation waiting for the service lock skips its queued deep read")
    func supersededLockWaitSkipsQueuedObservation() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let lockGate = VisibleStateGate(), old = fixture.consistency.blockNextRead()
        defer { lockGate.release(); old.release() }
        let service = fixture.service
        let lockOwner = Task.detached { service.withReadOnlyObservation { lockGate.wait() } }
        try await eventually(diagnostics: fixture.diagnostics) { lockGate.entered }
        let calls = fixture.observer.calls, commands = fixture.runner.commandCount
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { old.entered }
        old.release()
        await settle()
        fixture.observer.setPresent(false)
        fixture.diskEvents.emit(.init(kind: .disappeared, bsdName: fixture.device.bsdName))
        await settle()
        let fresh = fixture.consistency.blockNextRead()
        defer { fresh.release() }
        lockGate.release()
        _ = await lockOwner.value
        try await eventually(diagnostics: fixture.diagnostics) { fresh.entered }
        #expect(fixture.observer.calls == calls && fixture.runner.commandCount == commands,
            "Acquiring the service lock must recheck validity before starting the old snapshot")
        #expect(!fixture.store.hasObservedStatus && !fixture.store.canBeginWholeDeviceEject)
        fresh.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.parentConnected == false)
        #expect(fixture.agentStatus.reads == 2 && !fixture.store.workbench.safeToUnplug)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("A superseded inventory read does not continue into profile and service checks")
    func supersededInventoryStopsBeforeProfileRead() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let old = fixture.observer.blockNextObservation()
        defer { old.release() }
        let commands = fixture.runner.commandCount, ejectReads = fixture.ejectDriver.observationCalls
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { old.entered }
        fixture.observer.setPresent(false)
        fixture.diskEvents.emit(.init(kind: .disappeared, bsdName: fixture.device.bsdName))
        await settle()
        let fresh = fixture.consistency.blockNextRead()
        defer { fresh.release() }
        old.release()
        try await eventually(diagnostics: fixture.diagnostics) { fresh.entered }
        #expect(fixture.runner.commandCount == commands && fixture.ejectDriver.observationCalls == ejectReads)
        #expect(fixture.agentStatus.reads == 1 && !fixture.store.hasObservedStatus)
        #expect(fixture.store.workbench.devices.isEmpty && fixture.store.volumeRows.first?.parentConnected == false)
        fresh.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.inventoryState == .empty && !fixture.store.workbench.safeToUnplug)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("A superseded volume qualification skips eject checks and unrelated remaining volumes")
    func supersededProfileStopsBeforeRemainingQualifications() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let second = try fixture.addInternalProfile(internalFirst: true)
        let old = fixture.runner.blockNextDevelopmentRead()
        let internalRead = fixture.runner.blockInfoRead(at: second.backingMountPoint)
        defer { old.release(); internalRead.release() }
        let ejectReads = fixture.ejectDriver.observationCalls
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { old.entered }
        fixture.diskEvents.emit(.init(kind: .descriptionChanged, wholeDiskBSDName: fixture.device.bsdName))
        await settle()
        let fresh = fixture.consistency.blockNextRead()
        defer { fresh.release() }
        old.release()
        try await eventually(diagnostics: fixture.diagnostics) { fresh.entered }
        #expect(!internalRead.entered && fixture.ejectDriver.observationCalls == ejectReads,
            "The outdated profile must not delay the new snapshot with other qualifications")
        #expect(fixture.agentStatus.reads == 1 && !fixture.store.hasObservedStatus)
        #expect(fixture.store.volumeRows.first { $0.id == fixture.profile.id }?.canSafeUnloadAndEject == false)
        fresh.release()
        try await eventually(diagnostics: fixture.diagnostics) { internalRead.entered }
        internalRead.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first { $0.id == fixture.profile.id }?.canSafeUnloadAndEject == true)
        #expect(fixture.consistency.reads == 3 && fixture.agentStatus.reads == 2)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Fresh loaded state and eject eligibility appear before slow service status checks")
    func registeredVolumeAppearsBeforeSlowStatus() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let registry = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        let saved = try Data(contentsOf: registry)
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        await settle()
        #expect(fixture.store.volumeRows.map(\.id) == [fixture.profile.id],
            "A saved registration must be visible while optional status checks are blocked")
        #expect(!fixture.store.hasObservedStatus)
        #expect(fixture.store.volumeRows.allSatisfy {
            $0.verifiedLoaded == true && !$0.isBusy && !$0.canLoad && $0.canUnloadOnly && $0.canSafeUnloadAndEject
                && $0.importantDocumentURL == nil
        }, "Optional service status must not withhold independently verified loading and eject eligibility")
        let row = try #require(fixture.store.volumeRows.first)
        let action = SectoriumVolumeActionPlan.make(verifiedLoaded: row.verifiedLoaded,
            isExternal: row.isExternal, canLoad: row.canLoad, canUnloadOnly: row.canUnloadOnly,
            canSafeUnloadAndEject: row.canSafeUnloadAndEject, busy: fixture.store.isBusy || row.isBusy)
        #expect(action.action == .unloadOnly && action.enabled && action.disconnectEnabled == true,
            "The actual primary-button policy must not wait for optional status completion")
        #expect(try Data(contentsOf: registry) == saved)
        #expect(fixture.runner.mutationCalls.isEmpty)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true
        }
    }

    @Test("Passive refresh skips document reads; explicit history verification does not block eject")
    func loadedStateDoesNotWaitForOptionalDocument() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let gate = fixture.writer.blockNextURLRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.writer.urlReads == 0 && !gate.entered)
        let lookup = Task { await fixture.store.verifiedHistoryDocument(profileID: fixture.profile.id) }
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        let row = try #require(fixture.store.volumeRows.first)
        #expect(row.verifiedLoaded == true && row.canSafeUnloadAndEject && !row.isBusy)
        #expect(!fixture.store.isBusy && row.importantDocumentURL == nil)
        gate.release()
        #expect(await lookup.value != nil)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Read-only volume readiness is retained through the final status snapshot")
    func readOnlyReadinessSurvivesRowProjection() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.runner.setDevelopmentWritable(false)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.workbench.readiness == .readOnly)
        #expect(fixture.store.snapshot.readiness == .notReady("registered development volume is read-only"))
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil)
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Selected readiness keeps exact failures and rejects ambiguous or stale profile selection")
    func detailedReadinessSelectionIsNotCollapsed() throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let first = fixture.profile
        let second = SectoriumDevelopmentProfile(name: "Other", deviceID: first.deviceID,
            backingVolumeUUID: first.backingVolumeUUID, backingMountPoint: first.backingMountPoint,
            imagePath: first.backingMountPoint + "/Other.sparsebundle", devVolumeName: "Other",
            devMountPoint: first.backingMountPoint + "/Other", devUUID: UUID(), encrypted: false,
            caseSensitive: false, logicalCapacityBytes: first.logicalCapacityBytes, imageFormat: "UDSB", validation: .validated)
        func row(_ profile: SectoriumDevelopmentProfile) -> SectoriumVolumeRow {
            .init(profile: profile, parentDeviceID: profile.deviceID, parentName: fixture.device.name,
                isExternal: true, verifiedLoaded: nil, parentConnected: true, canLoad: false,
                canUnloadOnly: false, canSafeUnloadAndEject: false, isBusy: false,
                importantDocumentURL: nil, documentationPending: false, documentHistory: [],
                capacityChangeUnavailableReason: nil)
        }
        let preciseFailure = SectoriumWorkbenchReadiness.unknown("Backing image identity changed")
        func selected(_ selectedID: String?, rows: [SectoriumVolumeRow]) -> SectoriumWorkbenchReadiness {
            HESectoriumStore.observedReadiness(deviceID: fixture.device.id, selectedProfileID: selectedID,
                devices: [fixture.device], rows: rows,
                profileReadiness: [first.id: .readOnly, second.id: preciseFailure], pending: nil, legacy: nil)
        }
        #expect(selected(first.id, rows: [row(first), row(second)]) == .readOnly)
        #expect(selected(second.id, rows: [row(first), row(second)]) == preciseFailure)
        let needsSelection = SectoriumWorkbenchReadiness.unknown("Select a development profile to verify readiness")
        #expect(selected(nil, rows: [row(first), row(second)]) == needsSelection)
        #expect(selected(UUID().uuidString, rows: [row(first)]) == needsSelection,
            "An explicit missing profile must not silently select the remaining profile")
        #expect(HESectoriumStore.observedReadiness(deviceID: fixture.device.id, selectedProfileID: nil,
            devices: [fixture.device], rows: [], profileReadiness: [:], pending: nil,
            legacy: .init(name: "Legacy", mountPoint: first.devMountPoint, logicalCapacityBytes: nil, state: .mounted)) == .connected)
    }

    @Test("Unrelated internal empty state and external eject do not wait for global status")
    func internalRegistrationStateIsIndependent() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let internalDrive = SectoriumPhysicalDevice(id: UUID().uuidString, bsdName: "disk0", name: "Internal fixture",
            isExternal: false, identityVerified: true, wholeDeviceBytes: 256_000_000_000,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
            topologyComplete: true, isVirtual: false)
        fixture.observer.setAdditionalDevices([internalDrive])
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        #expect(fixture.store.hasObservedRegistrations && !fixture.store.hasObservedStatus)
        #expect(fixture.store.workbench.devices.contains { $0.id == internalDrive.id })
        #expect(!fixture.store.volumeRows.contains { $0.parentDeviceID == internalDrive.id })
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == true)
        #expect(!fixture.store.isBusy)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
    }

    @Test("External volumes publish before slow internal volumes regardless of registry order", arguments: [false, true])
    func firstVolumePublishesBeforeSecondVolumeFinishes(internalFirst: Bool) async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let second = try fixture.addInternalProfile(internalFirst: internalFirst)
        let registryURL = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        let registry = try Data(contentsOf: registryURL)
        let savedOrder = try JSONDecoder().decode([SectoriumDevelopmentProfile].self, from: registry).map(\.id)
        #expect(savedOrder == (internalFirst ? [second.id, fixture.profile.id] : [fixture.profile.id, second.id]))
        let gate = fixture.runner.blockInfoRead(at: second.backingMountPoint)
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        await settle()
        let external = try #require(fixture.store.volumeRows.first { $0.id == fixture.profile.id })
        let internalRow = try #require(fixture.store.volumeRows.first { $0.id == second.id })
        #expect(external.verifiedLoaded == true && external.canSafeUnloadAndEject && !external.isBusy)
        #expect(internalRow.verifiedLoaded == nil && internalRow.isBusy)
        #expect(fixture.store.hasObservedRegistrations && !fixture.store.hasObservedStatus)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first { $0.id == second.id }?.canSafeUnloadAndEject == false)
        #expect(try Data(contentsOf: registryURL) == registry, "Observation priority must not rewrite registration order")
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("An invalid registry is an explicit completed failure, retaining known volumes without actions", arguments: [false, true])
    func invalidRegistryPreservesKnownRowsAndRecovers(previouslyObserved: Bool) async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let registryURL = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        let saved = try Data(contentsOf: registryURL)
        if previouslyObserved {
            fixture.store.refresh()
            try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
            #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == true)
        }
        let invalid = Data("{ broken registry".utf8)
        try invalid.write(to: registryURL)
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.registryUnavailable && !fixture.store.hasObservedRegistrations)
        #expect(fixture.store.workbench.readiness == .unknown("Saved volume registrations could not be read"))
        #expect(fixture.store.snapshot.readiness == .unknown)
        #expect(!fixture.store.isBusy && !fixture.store.canBeginWholeDeviceEject)
        #expect(!fixture.store.canContinueWholeDeviceEject && !fixture.store.canReturnFromWholeDeviceEject)
        #expect(fixture.store.creationFilesystems.isEmpty)
        #expect(fixture.store.volumeRows.map(\.id) == (previouslyObserved ? [fixture.profile.id] : []))
        #expect(fixture.store.workbench.profiles.map(\.id) == (previouslyObserved ? [fixture.profile.id] : []))
        if let row = fixture.store.volumeRows.first {
            #expect(row.verifiedLoaded == nil && !row.isBusy)
            #expect(!row.canLoad && !row.canUnloadOnly && !row.canSafeUnloadAndEject)
            let action = SectoriumVolumeActionPlan.make(verifiedLoaded: row.verifiedLoaded,
                isExternal: row.isExternal, canLoad: row.canLoad, canUnloadOnly: row.canUnloadOnly,
                canSafeUnloadAndEject: row.canSafeUnloadAndEject, busy: fixture.store.isBusy || row.isBusy)
            #expect(action.action == .recheck && action.enabled)
            fixture.store.updateDevelopmentDisk(profileID: row.id, change: .displayName("Must not be written"))
            fixture.store.prepareSafeUnloadAndEject(profileID: row.id)
            #expect(!fixture.store.isBusy && fixture.store.safetyCheck == nil)
        }
        #expect(try Data(contentsOf: registryURL) == invalid)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
        try saved.write(to: registryURL)
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(!fixture.store.registryUnavailable && fixture.store.hasObservedRegistrations)
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == true)
        #expect(try Data(contentsOf: registryURL) == saved)
    }

    @Test("Missing and valid empty registries finish with authoritative empty registration state", arguments: [false, true])
    func emptyRegistryIsNotAReadFailure(explicitEmpty: Bool) async throws {
        let fixture = try VisibleStateFixture(registerProfile: false)
        defer { fixture.finish() }
        let registryURL = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        if explicitEmpty { try Data("[]".utf8).write(to: registryURL) }
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.hasObservedRegistrations && !fixture.store.registryUnavailable)
        #expect(fixture.store.volumeRows.isEmpty && fixture.store.workbench.profiles.isEmpty)
        #expect(!fixture.store.isBusy)
        if explicitEmpty { #expect(try Data(contentsOf: registryURL) == Data("[]".utf8)) }
        else { #expect(!FileManager.default.fileExists(atPath: registryURL.path)) }
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Background qualification does not flicker and a fresh negative result revokes eject")
    func backgroundQualificationPublishesCompletedResult() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        try fixture.recordPendingDocumentation()
        let registryURL = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        let registry = try Data(contentsOf: registryURL)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.documentationPending == true)
        for allowed in [true, false, true] {
            let gate = fixture.ejectDriver.blockNextObservation()
            defer { gate.release() }
            let wasEnabled = fixture.store.volumeRows.first?.canSafeUnloadAndEject
            fixture.store.refresh(background: true)
            try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
            await settle()
            #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == wasEnabled,
                "A qualification in flight must not replace a completed result with a fabricated negative")
            #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
            fixture.ejectDriver.setQualificationAvailable(allowed)
            let statusReads = fixture.agentStatus.reads
            gate.release()
            try await eventually(diagnostics: fixture.diagnostics) { fixture.agentStatus.reads > statusReads }
            await settle()
            let row = try #require(fixture.store.volumeRows.first)
            #expect(row.canSafeUnloadAndEject == allowed, "The freshly completed qualification is authoritative")
            #expect(row.documentationPending, "Pending IMPORTANT history is independent of eject eligibility")
            #expect(!fixture.store.isBusy && row.verifiedLoaded == true)
        }
        #expect(fixture.writer.urlReads == 0)
        #expect(try Data(contentsOf: registryURL) == registry)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Relocated display paths do not revoke qualification; changed or invalid saved registrations do")
    func relocatedRegistrationRetainsCompletedQualification() async throws {
        let fixture = try VisibleStateFixture(relocatedBacking: true)
        defer { fixture.finish() }
        let registryURL = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        let saved = try Data(contentsOf: registryURL)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let relocated = try #require(fixture.store.volumeRows.first)
        #expect(relocated.profile.backingMountPoint != fixture.profile.backingMountPoint)
        #expect(relocated.profile.backingMountPoint == fixture.device.mountedVolumePaths.first)
        #expect(relocated.canSafeUnloadAndEject && relocated.verifiedLoaded == true)
        for _ in 0..<3 {
            let gate = fixture.ejectDriver.blockNextObservation()
            defer { gate.release() }
            fixture.store.refresh(background: true)
            try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
            await settle()
            let during = try #require(fixture.store.volumeRows.first)
            #expect(during.profile == relocated.profile && during.canSafeUnloadAndEject && !during.isBusy,
                "The saved registration is unchanged even when its observed mount path differs")
            let reads = fixture.agentStatus.reads
            gate.release()
            try await eventually(diagnostics: fixture.diagnostics) { fixture.agentStatus.reads > reads }
            await settle()
            #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == true)
            #expect(try Data(contentsOf: registryURL) == saved)
        }
        var changed = fixture.profile
        changed.name = "Renamed development"
        let changedBytes = try JSONEncoder().encode([changed])
        try changedBytes.write(to: registryURL)
        let gate = fixture.ejectDriver.blockNextObservation()
        defer { gate.release() }
        fixture.store.refresh(background: true)
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        await settle()
        let pending = try #require(fixture.store.volumeRows.first)
        #expect(pending.profile.name == changed.name)
        #expect(pending.verifiedLoaded == nil && !pending.canSafeUnloadAndEject,
            "A genuine saved registration change must revoke the previous qualification")
        #expect(!pending.canLoad && !pending.canUnloadOnly)
        let reads = fixture.agentStatus.reads
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.agentStatus.reads > reads }
        await settle()
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == true)
        #expect(try Data(contentsOf: registryURL) == changedBytes)
        let invalid = Data("{ invalid registration".utf8)
        try invalid.write(to: registryURL)
        fixture.store.refresh(background: true)
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.registryUnavailable }
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        #expect(fixture.store.volumeRows.first?.isBusy == false)
        #expect(try Data(contentsOf: registryURL) == invalid)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("A slow deep read starts a five-minute quiet interval; unchanged consistency is cheap")
    func slowRefreshDoesNotImmediatelyRestart() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        fixture.clock.advance(600)
        fixture.store.refreshVisibleStatusIfDue()
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let completedReads = fixture.agentStatus.reads
        let consistencyReads = fixture.consistency.reads
        fixture.store.refreshVisibleStatusIfDue()
        fixture.clock.advance(299)
        fixture.store.refreshVisibleStatusIfDue()
        await settle()
        #expect(fixture.agentStatus.reads == completedReads && fixture.consistency.reads == consistencyReads)
        fixture.clock.advance(1)
        fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.consistency.reads == consistencyReads + 1 }
        await settle()
        #expect(fixture.agentStatus.reads == completedReads)
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == true)
    }

    @Test("Explicit history verification is discarded after navigation invalidates its context")
    func historyLookupRejectsNavigationChange() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let gate = fixture.writer.blockNextURLRead()
        defer { gate.release() }
        let lookup = Task { await fixture.store.verifiedHistoryDocument(profileID: fixture.profile.id) }
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        fixture.store.deactivateWorkbench()
        gate.release()
        #expect(await lookup.value == nil)
        #expect(fixture.store.documentReadsInProgress.isEmpty)
    }

    @Test("Loaded truth is shown while eject topology is still checking, without prematurely enabling eject")
    func loadedStatePrecedesFreshEjectQualification() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let gate = fixture.ejectDriver.blockNextObservation()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.volumeRows.first?.verifiedLoaded == true
        }
        let row = try #require(fixture.store.volumeRows.first)
        #expect(row.verifiedLoaded == true && row.canUnloadOnly && !row.isBusy)
        #expect(!row.canSafeUnloadAndEject, "Loaded state alone cannot qualify a whole-device eject")
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canSafeUnloadAndEject == true
        }
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("A late eject-eligibility stage cannot publish across a new operation precheck")
    func preparationRejectsOldEjectEligibilityStage() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.store.apply(devices: [fixture.device], profiles: [fixture.profile], readiness: .ready, pending: nil)
        let gate = fixture.ejectDriver.blockNextObservation()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.volumeRows.first?.verifiedLoaded == true
        }
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        fixture.store.prepareStopDevelopmentDiskConfirmation()
        #expect(fixture.store.isBusy)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            !fixture.store.isBusy && fixture.store.stopConfirmation != nil
        }
        await settle()
        #expect(fixture.agentStatus.reads == 0,
            "The superseded refresh must stop before its optional service-status tail")
        #expect(!fixture.store.hasObservedStatus, "A refresh begun before the operation cannot complete its status publication")
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false,
            "A stale qualification cannot enable eject after an operation superseded it")
        #expect(fixture.store.volumeRows.first?.importantDocumentURL == nil)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
        fixture.store.cancelStopConfirmation()
    }

    @Test("Tab and settings reentry retain a current snapshot and an in-flight observation")
    func rapidTabReentryPreservesRegistration() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let registry = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        let saved = try Data(contentsOf: registry)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let firstRows = fixture.store.volumeRows
        let firstCalls = fixture.observer.calls
        let firstConsistency = fixture.consistency.reads
        for _ in 0..<6 {
            fixture.store.deactivateWorkbench()
            fixture.store.activateSettings()
            #expect(fixture.store.volumeRows == firstRows && fixture.store.hasObservedStatus)
            fixture.store.deactivateSettings()
            fixture.store.activateWorkbench()
        }
        await settle()
        #expect(fixture.observer.calls == firstCalls && fixture.consistency.reads == firstConsistency)
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        let stagedRows = fixture.store.volumeRows
        let calls = fixture.observer.calls
        for _ in 0..<3 {
            fixture.store.deactivateWorkbench()
            fixture.store.activateWorkbench()
            #expect(fixture.store.volumeRows == stagedRows)
        }
        await settle()
        #expect(fixture.observer.calls == calls)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
        #expect(fixture.observer.calls == calls, "Navigation does not enqueue a second deep observation")
        #expect(try Data(contentsOf: registry) == saved)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("An existing loaded legacy volume is visible before optional service checks finish")
    func legacyVolumeIsPublishedBeforeSlowStatus() async throws {
        let fixture = try VisibleStateFixture(registerProfile: false)
        defer { fixture.finish() }
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.state == .mounted
        }
        #expect(fixture.store.inventoryState == .available)
        #expect(fixture.store.workbench.devices.contains { $0.id == fixture.device.id })
        #expect(fixture.store.workbench.profiles.isEmpty && fixture.store.volumeRows.isEmpty)
        #expect(!fixture.store.hasObservedStatus, "The already verified volume must not wait for the service-status stage")
        let legacy = try #require(fixture.store.legacyDevelopmentByDevice[fixture.device.id])
        #expect(legacy.name == fixture.profile.devVolumeName)
        #expect(legacy.mountPoint == fixture.profile.devMountPoint)
        #expect(fixture.runner.mutationCalls.isEmpty)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.state == .mounted)
        #expect(fixture.store.workbench.profiles.isEmpty, "Observing a legacy volume must not register it")
    }

    @Test("A newly registered legacy volume replaces its legacy presentation without duplication")
    func registrationReplacesLegacyPresentation() async throws {
        let fixture = try VisibleStateFixture(registerProfile: false)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.state == .mounted)
        #expect(fixture.store.volumeRows.isEmpty)
        // Represents an accepted registration by the backend in this disposable
        // fixture. No host volume, service or existing user registry is changed.
        let registry = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        try JSONEncoder().encode([fixture.profile]).write(to: registry)
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true
        }
        #expect(fixture.store.legacyDevelopmentByDevice[fixture.device.id] == nil)
        #expect(fixture.store.volumeRows.map(\.id) == [fixture.profile.id])
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Registering an early legacy row retains its parent when adoption fails", arguments: [true, false])
    func earlyAdoptionRetainsObservedParent(configuredLegacy: Bool) async throws {
        let fixture = try VisibleStateFixture(registerProfile: false)
        defer { fixture.finish() }
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.state == .mounted
        }
        #expect(fixture.store.workbench.selectedDeviceID == nil)
        #expect(!fixture.store.hasObservedStatus)
        if configuredLegacy {
            fixture.store.adoptConfiguredLegacyDevelopmentDisk(deviceID: fixture.device.id)
        } else {
            fixture.store.adoptDevelopmentDisk(deviceID: fixture.device.id,
                imageURL: URL(fileURLWithPath: fixture.profile.imagePath))
        }
        // This must return immediately even while refreshStatus holds the service
        // lock. Only local selection is changed before the background operation.
        #expect(fixture.store.workbench.selectedDeviceID == fixture.device.id)
        #expect(fixture.store.isBusy)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            !fixture.store.isBusy && fixture.store.hasObservedStatus && !fixture.store.lastResult.isEmpty
        }
        #expect(fixture.store.workbench.selectedDeviceID == fixture.device.id)
        #expect(fixture.store.lastResult.contains("Failed:"),
            "This fixture deliberately provides no image-format/encryption verification for adoption")
        #expect(fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.state == .mounted)
        #expect(fixture.store.workbench.profiles.isEmpty && fixture.store.volumeRows.isEmpty)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Legacy loading claims are invalidated on sleep and refreshed without registering the volume")
    func legacyStateDoesNotSurviveConnectionInvalidation() async throws {
        let fixture = try VisibleStateFixture(registerProfile: false)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.state == .mounted)
        fixture.store.pauseSamplingForSleep()
        #expect(fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.state == .unknown)
        #expect(fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.mountPoint == nil)
        fixture.runner.setLoaded(false)
        fixture.store.resumeSamplingAfterWake()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.legacyDevelopmentByDevice[fixture.device.id]?.state == .unmounted)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Device and profile selection return immediately while service observation is blocked")
    func selectionDoesNotWaitForServiceLock() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        try await eventually(diagnostics: fixture.diagnostics) { !fixture.store.workbench.profiles.isEmpty }
        let started = ProcessInfo.processInfo.systemUptime
        fixture.store.selectDevice(fixture.device.id)
        fixture.store.selectProfile(fixture.profile.id)
        // What selection must not wait for is the gate above, which holds for
        // two minutes, so any bound far below that catches the regression. One
        // second did not survive a full parallel suite run.
        #expect(ProcessInfo.processInfo.systemUptime - started < 10,
            "Selection must not wait for the service observation gate or perform UI-thread I/O")
        #expect(fixture.store.workbench.selectedDeviceID == fixture.device.id)
        #expect(fixture.store.workbench.selectedProfileID == fixture.profile.id)
        #expect(!fixture.store.hasObservedStatus)
        #expect(!fixture.store.canBeginWholeDeviceEject)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true
        }
        #expect(fixture.store.workbench.selectedProfileID == fixture.profile.id)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Selecting another drive rejects an older refresh and waits for its own qualifications")
    func selectionRejectsPreviousTargetTail() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let other = SectoriumPhysicalDevice(id: UUID().uuidString, bsdName: "disk82", name: "Other fixture drive",
            isExternal: true, identityVerified: true, wholeDeviceBytes: 100_000_000_000,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
            topologyComplete: true, isVirtual: false)
        fixture.observer.setAdditionalDevices([other])
        fixture.store.apply(devices: [fixture.device, other], profiles: [fixture.profile], readiness: .ready, pending: nil)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let oldGate = fixture.agentStatus.blockNextRead()
        defer { oldGate.release() }
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { oldGate.entered }
        let freshGate = fixture.agentStatus.blockNextRead()
        defer { freshGate.release() }
        let started = ProcessInfo.processInfo.systemUptime
        fixture.store.selectDevice(other.id)
        #expect(ProcessInfo.processInfo.systemUptime - started < 10)
        #expect(fixture.store.workbench.selectedDeviceID == other.id)
        #expect(!fixture.store.hasObservedStatus && !fixture.store.canBeginWholeDeviceEject)
        oldGate.release()
        try await eventually(diagnostics: fixture.diagnostics) { freshGate.entered }
        #expect(fixture.store.workbench.selectedDeviceID == other.id)
        #expect(!fixture.store.hasObservedStatus, "The old drive's tail must not count as the new selection's observation")
        #expect(fixture.store.workbench.readiness != .ready)
        #expect(!fixture.store.canBeginWholeDeviceEject)
        #expect(fixture.store.volumeRows.count == 1)
        #expect(fixture.store.volumeRows.allSatisfy {
            $0.parentDeviceID == fixture.device.id && $0.profile.id == fixture.profile.id
                && $0.verifiedLoaded == true && $0.canSafeUnloadAndEject
        }, "Fresh per-volume eligibility belongs to its verified parent, never to the newly selected other drive")
        freshGate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.workbench.selectedDeviceID == other.id)
        #expect(fixture.store.workbench.selectedProfileID == nil)
        #expect(fixture.store.workbench.readiness != .ready)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("An inventory failure retains the actual observation error and is not an empty drive result")
    func inventoryFailurePreservesCause() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.observer.setFailure(true)
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        #expect(fixture.store.inventoryState == .unavailable)
        #expect(fixture.store.inventoryFailureDescription?.contains("fixtureInventoryDenied") == true)
        #expect(fixture.store.workbench.devices.isEmpty)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.inventoryState == .unavailable)
        #expect(fixture.store.inventoryFailureDescription?.contains("fixtureInventoryDenied") == true)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Reconnecting the same drive clears a verified eject before the delayed fresh read")
    func reconnectClearsEjectImmediately() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.observer.setPresent(false)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        fixture.store.recordVerifiedEjection(deviceID: fixture.device.id, name: fixture.device.name)
        fixture.store.apply(devices: [], profiles: [fixture.profile], readiness: .ejected, pending: nil)
        #expect(fixture.store.workbench.safeToUnplug)

        fixture.observer.setPresent(true)
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.notifications.post(name: NSWorkspace.didMountNotification, object: nil)
        #expect(!fixture.store.workbench.safeToUnplug)
        #expect(fixture.store.safeToUnplugDriveName == nil)
        #expect(!fixture.store.hasObservedStatus)
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        #expect(!fixture.store.workbench.safeToUnplug)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true }
        #expect(fixture.store.workbench.devices.map(\.id) == [fixture.device.id])
        #expect(!fixture.store.workbench.safeToUnplug)
        #expect(fixture.store.volumeRows.first?.canUnloadOnly == true)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Five-minute changed or unavailable consistency triggers one deep read", arguments: [false, true])
    func boundedPollingObservesExternalChangesWithoutOverlap(unavailable: Bool) async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let initialReads = fixture.agentStatus.reads
        let consistencyReads = fixture.consistency.reads
        let gate = fixture.consistency.blockNextRead()
        defer { gate.release() }
        fixture.runner.setLoaded(false)
        fixture.consistency.setFingerprint(unavailable ? nil : "changed")
        fixture.clock.advance(299)
        fixture.store.refreshVisibleStatusIfDue()
        await settle()
        #expect(!gate.entered && fixture.consistency.reads == consistencyReads)
        fixture.clock.advance(1)
        fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        for _ in 0..<10 { fixture.store.refreshVisibleStatusIfDue() }
        await settle()
        #expect(fixture.agentStatus.reads == initialReads && fixture.consistency.reads == consistencyReads + 1)
        let deepGate = fixture.agentStatus.blockNextRead()
        defer { deepGate.release() }
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { deepGate.entered }
        for _ in 0..<10 { fixture.store.refreshVisibleStatusIfDue() }
        deepGate.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == false
        }
        await settle()
        #expect(fixture.agentStatus.reads == initialReads + 1)
        #expect(fixture.consistency.maximumConcurrentCalls == 1 && fixture.agentStatus.maximumConcurrentCalls == 1)
        #expect(fixture.store.volumeRows.first?.canLoad == true)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Wake clears cached state, document URL and actions before publishing fresh loading truth")
    func wakeInvalidatesBeforeLateRead() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true }
        let old = try #require(fixture.store.volumeRows.first)
        #expect(old.canUnloadOnly && old.importantDocumentURL == nil)
        #expect(await fixture.store.verifiedHistoryDocument(profileID: fixture.profile.id) != nil)
        fixture.store.pauseSamplingForSleep()
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil)
        fixture.runner.setLoaded(false)
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.resumeSamplingAfterWake()
        #expect(!fixture.store.hasObservedStatus)
        #expect(!fixture.store.workbench.safeToUnplug)
        let invalid = try #require(fixture.store.volumeRows.first)
        #expect(invalid.verifiedLoaded == nil && invalid.importantDocumentURL == nil)
        #expect(!invalid.canLoad && !invalid.canUnloadOnly && !invalid.canSafeUnloadAndEject)
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == false }
        #expect(fixture.store.volumeRows.first?.canLoad == true)
        #expect(fixture.store.volumeRows.first?.importantDocumentURL == nil)
        #expect(await fixture.store.verifiedHistoryDocument(profileID: fixture.profile.id) != nil)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Connection bursts retain one in-flight read and coalesce one fresh follow-up")
    func connectionNotificationsCoalesce() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true }
        let initialReads = fixture.agentStatus.reads
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.notifications.post(name: NSWorkspace.didMountNotification, object: nil)
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        let calls = fixture.agentStatus.reads
        fixture.runner.setLoaded(false)
        for _ in 0..<10 {
            fixture.notifications.post(name: NSWorkspace.didUnmountNotification, object: nil)
        }
        await settle()
        #expect(fixture.agentStatus.reads == calls)
        #expect(fixture.agentStatus.maximumConcurrentCalls == 1)
        #expect(!fixture.store.hasObservedStatus)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == false }
        await settle()
        #expect(fixture.agentStatus.reads == initialReads + 2,
                "One interrupted read and one coalesced follow-up are sufficient for a notification burst")
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("A connection change during an admitted operation is freshly observed after it finishes")
    func operationCompletionDrainsPendingConnectionRefresh() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        // This case begins with an already selected drive; the admitted operation
        // must not race the separate availability read triggered by first selection.
        fixture.store.apply(devices: [fixture.device], profiles: [fixture.profile], readiness: .ready, pending: nil)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true }
        let gate = fixture.writer.blockNextUpdate()
        defer { gate.release() }
        fixture.store.retryDocumentation(profileID: fixture.profile.id)
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        #expect(fixture.store.isBusy)
        fixture.runner.setLoaded(false)
        fixture.notifications.post(name: NSWorkspace.didUnmountNotification, object: nil)
        #expect(fixture.store.isBusy, "A storage notification must not cancel an admitted operation")
        #expect(!fixture.store.hasObservedStatus)
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            !fixture.store.isBusy && fixture.store.hasObservedStatus
                && fixture.store.volumeRows.first?.verifiedLoaded == false
        }
        #expect(fixture.store.volumeRows.first?.canLoad == true)
        #expect(!fixture.store.workbench.safeToUnplug)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Hidden observations finish and lifetime notifications mark state dirty without new reads")
    func deactivationRejectsLateObservation() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let gate = fixture.runner.blockNextDevelopmentRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        fixture.store.deactivateWorkbench()
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
        let count = fixture.observer.calls
        fixture.runner.setLoaded(false)
        fixture.notifications.post(name: NSWorkspace.didUnmountNotification, object: nil)
        #expect(fixture.store.volumeRows.map(\.id) == [fixture.profile.id])
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil)
        await settle()
        #expect(fixture.observer.calls == count)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == false
        }
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Leaving during a read-only unload precheck releases busy state and discards its late confirmation")
    func reactivationRejectsLatePrepareWithoutRemainingBusy() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.store.apply(devices: [fixture.device], profiles: [fixture.profile], readiness: .ready, pending: nil)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true }
        fixture.store.selectProfile(fixture.profile.id)
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true }
        let gate = fixture.observer.blockNextObservation()
        defer { gate.release() }
        fixture.store.prepareStopDevelopmentDiskConfirmation()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        #expect(fixture.store.isBusy)
        fixture.store.deactivateWorkbench()
        fixture.store.activateWorkbench()
        #expect(fixture.store.stopConfirmation == nil)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { !fixture.store.isBusy }
        #expect(fixture.store.stopConfirmation == nil, "A precheck begun before deactivation cannot authorize an unload after reentry")
        fixture.store.refresh()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true }
        #expect(!fixture.store.isBusy)
        #expect(fixture.store.stopConfirmation == nil)
        #expect(fixture.runner.mutationCalls.isEmpty, "Prepare and reentry must never request a storage mutation")
    }

    @Test("Repeated sleep during unload preparation discards late confirmations until fresh wake observations")
    func repeatedSleepRejectsLatePreparation() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let registry = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        let saved = try Data(contentsOf: registry)
        fixture.store.apply(devices: [fixture.device], profiles: [fixture.profile], readiness: .ready, pending: nil)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        for _ in 0..<4 {
            let gate = fixture.observer.blockNextObservation()
            defer { gate.release() }
            fixture.store.prepareStopDevelopmentDiskConfirmation()
            try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
            fixture.store.pauseSamplingForSleep()
            #expect(fixture.store.stopConfirmation == nil)
            gate.release()
            try await eventually(diagnostics: fixture.diagnostics) { !fixture.store.isBusy }
            #expect(fixture.store.stopConfirmation == nil,
                "A pre-sleep observation must never republish an unload confirmation during sleep")
            #expect(!fixture.store.hasObservedStatus)
            #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil)
            let reads = fixture.observer.calls
            fixture.store.refresh()
            fixture.store.refreshVisibleStatusIfDue(now: ProcessInfo.processInfo.systemUptime + 60)
            await settle()
            #expect(fixture.observer.calls == reads, "Sleeping must suppress explicit and automatic refresh")
            fixture.store.resumeSamplingAfterWake()
            try await eventually(diagnostics: fixture.diagnostics) {
                fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true
            }
            #expect(fixture.store.stopConfirmation == nil)
            #expect(try Data(contentsOf: registry) == saved)
        }
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Repeated navigation during document sync ignores stale notices and does not refresh a hidden workbench", arguments: [false, true])
    func repeatedNavigationDuringDocumentSync(reenterBeforeCompletion: Bool) async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let registry = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        let saved = try Data(contentsOf: registry)
        fixture.store.apply(devices: [fixture.device], profiles: [fixture.profile], readiness: .ready, pending: nil)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        for _ in 0..<4 {
            let gate = fixture.writer.blockNextUpdate()
            defer { gate.release() }
            fixture.store.retryDocumentation(profileID: fixture.profile.id)
            try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
            let statusReads = fixture.agentStatus.reads
            fixture.store.deactivateWorkbench()
            if reenterBeforeCompletion { fixture.store.activateWorkbench() }
            gate.release()
            try await eventually(diagnostics: fixture.diagnostics) { !fixture.store.isBusy }
            if reenterBeforeCompletion {
                try await eventually(diagnostics: fixture.diagnostics) {
                    fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == true
                }
            }
            await settle()
            #expect(fixture.store.userNotice == nil, "A result from the previous page lifetime cannot replace current feedback")
            #expect(fixture.agentStatus.reads == statusReads,
                "Document sync and navigation do not require a new device observation")
            #expect(try Data(contentsOf: registry) == saved)
            if !reenterBeforeCompletion {
                fixture.store.activateWorkbench()
                try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
            }
        }
        #expect(fixture.agentStatus.maximumConcurrentCalls == 1)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Repeated inventory failures and notification bursts recover without losing registrations or overlapping refreshes")
    func repeatedInventoryFailureRecovery() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let registry = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        let saved = try Data(contentsOf: registry)
        fixture.store.apply(devices: [fixture.device], profiles: [fixture.profile], readiness: .ready, pending: nil)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        for cycle in 0..<8 {
            fixture.observer.setFailure(true)
            fixture.store.refresh()
            try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
            #expect(fixture.store.inventoryState == .unavailable)
            let row = try #require(fixture.store.volumeRows.first)
            #expect(row.id == fixture.profile.id && row.verifiedLoaded == nil)
            #expect(!row.canLoad && !row.canUnloadOnly && !row.canSafeUnloadAndEject)
            let action = SectoriumVolumeActionPlan.make(verifiedLoaded: row.verifiedLoaded,
                isExternal: row.isExternal, canLoad: row.canLoad, canUnloadOnly: row.canUnloadOnly,
                canSafeUnloadAndEject: row.canSafeUnloadAndEject, busy: fixture.store.isBusy || row.isBusy)
            #expect(action.action == .recheck && action.enabled)
            fixture.observer.setFailure(false)
            let loaded = cycle.isMultiple(of: 2)
            fixture.runner.setLoaded(loaded)
            for _ in 0..<6 { fixture.notifications.post(name: NSWorkspace.didMountNotification, object: nil) }
            try await eventually(diagnostics: fixture.diagnostics) {
                fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == loaded
            }
            #expect(fixture.store.inventoryState == .available)
            #expect(fixture.store.volumeRows.map(\.id) == [fixture.profile.id])
            #expect(try Data(contentsOf: registry) == saved)
        }
        #expect(fixture.agentStatus.maximumConcurrentCalls == 1)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Whole-device disappearance immediately shows saved volumes disconnected, without safe-eject success")
    func physicalDisappearancePublishesBeforeSlowObservation() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let saved = fixture.store.volumeRows.map(\.profile)
        fixture.observer.setPresent(false)
        let gate = fixture.observer.blockNextObservation()
        defer { gate.release() }
        fixture.diskEvents.emit(.init(kind: .disappeared, bsdName: fixture.device.bsdName))
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        let row = try #require(fixture.store.volumeRows.first)
        #expect(!row.parentConnected && row.verifiedLoaded == false && !row.isBusy)
        #expect(row.message(isChinese: false).contains("disconnected"))
        #expect(!row.message(isChinese: false).contains("Checking"))
        #expect(fixture.store.volumeRows.map(\.profile) == saved)
        #expect(!fixture.store.workbench.safeToUnplug)
        #expect(fixture.store.workbench.devices.isEmpty)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.parentConnected == false)
        #expect(!fixture.store.workbench.safeToUnplug)
    }

    @Test("An absent registered parent needs no image or development-path verification")
    func absentRegisteredVolumeSkipsDeepPathChecks() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.observer.setPresent(false)
        let gate = fixture.runner.blockInfoRead(at: fixture.profile.backingMountPoint)
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let row = try #require(fixture.store.volumeRows.first)
        #expect(!gate.entered, "An authoritative absent parent must not trigger image-path reads")
        #expect(row.verifiedLoaded == false && !row.parentConnected && !row.isBusy)
        #expect(!row.canLoad && !row.canUnloadOnly && !row.canSafeUnloadAndEject)
        #expect(!fixture.store.workbench.safeToUnplug)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("An unavailable inventory never claims that the drive is disconnected")
    func inventoryFailureIsNotConfirmedAbsence() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.observer.setFailure(true)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let row = try #require(fixture.store.volumeRows.first)
        #expect(row.verifiedLoaded == nil)
        #expect(!row.message(isChinese: false).contains("Drive disconnected"))
        #expect(!fixture.store.workbench.safeToUnplug)
    }

    @Test("Unresolved external or unknown-location media is unknown, not disconnected", arguments: [true, false])
    func unresolvedExternalIdentityDoesNotClaimAbsence(externalFlag: Bool) async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let unresolved = SectoriumPhysicalDevice(id: "unverified-" + fixture.device.bsdName,
            bsdName: fixture.device.bsdName, name: fixture.device.name, isExternal: externalFlag,
            identityVerified: false, wholeDeviceBytes: fixture.device.wholeDeviceBytes,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
            topologyComplete: false, isVirtual: false)
        fixture.observer.setPresent(false)
        fixture.observer.setAdditionalDevices([unresolved])
        let gate = fixture.runner.blockInfoRead(at: fixture.profile.backingMountPoint)
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let row = try #require(fixture.store.volumeRows.first)
        #expect(row.verifiedLoaded == nil && !row.parentConnected)
        #expect(!row.message(isChinese: false).contains("Drive disconnected"))
        #expect(!row.canLoad && !row.canSafeUnloadAndEject && !fixture.store.workbench.safeToUnplug)
        #expect(!gate.entered, "Unresolved identity must not authorize reads through the saved mount path")
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Confirmed internal media cannot postpone an absent external volume")
    func confirmedInternalIdentityDoesNotDelayExternalAbsence() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        let internalDrive = SectoriumPhysicalDevice(id: "unverified-disk0", bsdName: "disk0",
            name: "Internal fixture", isExternal: false, identityVerified: false,
            wholeDeviceBytes: 256_000_000_000, mountedVolumePaths: [], volumeUUIDs: [],
            readBytes: nil, writtenBytes: nil, topologyComplete: false, isVirtual: false,
            isInternalConfirmed: true)
        fixture.observer.setPresent(false)
        fixture.observer.setAdditionalDevices([internalDrive])
        let gate = fixture.runner.blockInfoRead(at: fixture.profile.backingMountPoint)
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let row = try #require(fixture.store.volumeRows.first)
        #expect(row.verifiedLoaded == false && !row.parentConnected && !row.isBusy)
        #expect(row.message(isChinese: false).contains("Drive disconnected"))
        #expect(!gate.entered && !fixture.store.workbench.safeToUnplug)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Reconnection restores a registered unloaded volume without another registration")
    func reconnectRestoresSavedVolumeLoadAction() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.observer.setPresent(false)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.parentConnected == false)
        fixture.observer.setPresent(true)
        fixture.runner.setLoaded(false)
        fixture.diskEvents.emit(.init(kind: .appeared, bsdName: fixture.device.bsdName))
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canLoad == true
        }
        #expect(fixture.store.volumeRows.map(\.id) == [fixture.profile.id])
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == false)
        #expect(!fixture.store.workbench.safeToUnplug)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("An action receipt survives native disappearance and navigation, without stale connection instructions")
    func operationReceiptSurvivesDisappearanceAndNavigation() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let gate = fixture.writer.blockNextUpdate()
        defer { gate.release() }
        fixture.store.updateDevelopmentDisk(profileID: fixture.profile.id, change: .autoLoad(false))
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        fixture.observer.setPresent(false)
        fixture.diskEvents.emit(.init(kind: .disappeared, bsdName: fixture.device.bsdName))
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.volumeRows.first?.parentConnected == false }
        #expect(fixture.store.isBusy, "A native removal event must not claim to cancel an admitted action")
        fixture.store.deactivateWorkbench()
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { !fixture.store.isBusy }
        #expect(fixture.store.lastResult.contains("Completed"))
        #expect(fixture.store.workbench.operationSteps.contains { $0.step == "settings" && $0.status == .succeeded })
        #expect(fixture.store.userNotice == nil)
        let statusGate = fixture.agentStatus.blockNextRead()
        defer { statusGate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { statusGate.entered }
        #expect(fixture.store.volumeRows.first?.profile.autoLoad == false)
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == false)
        #expect(!fixture.store.workbench.safeToUnplug, "Completing settings and observing absence is not a safe eject")
        #expect(fixture.store.userNotice?.english.contains("disconnected") == true,
            "Confirmed removal does not wait for optional service status to replace stale connection instructions")
        statusGate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Completed actions release global busy before slow post-operation service observation")
    func operationCompletionDoesNotWaitForSlowServiceStatus() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.updateDevelopmentDisk(profileID: fixture.profile.id, change: .autoLoad(false))
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        #expect(!fixture.store.isBusy, "The completed action must not own global busy through passive service checks")
        #expect(fixture.store.volumeRows.first?.profile.autoLoad == false)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Installer completion releases global busy before optional service observation")
    func installerCompletionDoesNotWaitForSlowServiceStatus() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let previousStatus = fixture.store.snapshot
        let reads = fixture.agentStatus.reads
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.install()
        fixture.store.installRepair() // An admitted installer still prevents a second action.
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        #expect(!fixture.store.isBusy, "A terminal installer result must not wait for launch-service/disk observation")
        #expect(!fixture.store.hasObservedStatus, "The previous snapshot must not be presented as a new install observation")
        #expect(fixture.store.snapshot == previousStatus)
        #expect(fixture.store.lastResult.contains("Install assets must be supplied"))
        #expect(fixture.store.userNotice?.english.contains("did not finish") == true,
            "This command-line fixture has no app assets: retain the real failure rather than claim installed")
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        await settle()
        #expect(fixture.agentStatus.reads == reads + 1, "Both install entry points must not dispatch concurrent actions")
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Startup automation completion refreshes an unresolved initial state without a five-minute wait")
    func startupCompletionRefreshesInitialUnknown() async throws {
        let fixture = try VisibleStateFixture()
        defer { fixture.finish() }
        fixture.runner.setDevelopmentReadFailure(true)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil)
        let reads = fixture.agentStatus.reads
        let initialTime = fixture.clock.now
        var saved = fixture.profile
        saved.autoLoad = false
        try JSONEncoder().encode([saved]).write(to: fixture.service.paths.sectoriumProfiles)
        fixture.runner.setDevelopmentReadFailure(false)
        let service = fixture.service
        let completion = await Task.detached { service.runApplicationAutomationAtStartup() }.value
        #expect(completion.succeeded)
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canSafeUnloadAndEject == true
        }
        await settle()
        #expect(fixture.agentStatus.reads == reads + 1)
        #expect(fixture.clock.now == initialTime, "No timer advance or manual refresh should be required")
        fixture.store.deactivateWorkbench()
        fixture.store.activateWorkbench()
        await settle()
        #expect(fixture.agentStatus.reads == reads + 1, "Switching pages still reuses the now-current snapshot")
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Automatic completion bursts coalesce and remain scoped to the owning service")
    func automaticCompletionIsCoalescedAndServiceScoped() async throws {
        let fixture = try VisibleStateFixture()
        let unrelated = try VisibleStateFixture(registerProfile: false)
        defer { fixture.finish(); unrelated.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let reads = fixture.agentStatus.reads
        let otherService = unrelated.service
        _ = await Task.detached { otherService.runApplicationAutomationAtStartup() }.value
        await settle()
        #expect(fixture.agentStatus.reads == reads, "Another service instance must not invalidate this Store")
        fixture.runner.setLoaded(false)
        let service = fixture.service
        _ = await Task.detached {
            // This unrelated event does not select any profile or dispatch storage
            // mutations. It exercises the real automatic-operation completion hook.
            for _ in 0..<8 { _ = service.runApplicationAutomation(.devMounted(uuid: UUID())) }
        }.value
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canLoad == true
        }
        await settle()
        #expect(fixture.agentStatus.reads == reads + 1)
        #expect(fixture.agentStatus.maximumConcurrentCalls == 1)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
        #expect(unrelated.runner.mutationCalls.isEmpty)
    }

    @Test("Native listeners survive hidden navigation and revoke only the related drive")
    func nativeEventsRemainScopedWhileHidden() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        let internalProfile = try fixture.addInternalProfile()
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let external = try #require(fixture.store.volumeRows.first { $0.id == fixture.profile.id })
        #expect(external.canSafeUnloadAndEject)
        fixture.store.deactivateWorkbench()
        let reads = fixture.agentStatus.reads
        fixture.diskEvents.emit(.init(kind: .descriptionChanged, wholeDiskBSDName: "disk0"))
        await settle()
        #expect(fixture.store.volumeRows.first { $0.id == fixture.profile.id } == external,
            "A correlated internal-drive event must not revoke the external drive")
        #expect(fixture.store.volumeRows.first { $0.id == internalProfile.id }?.verifiedLoaded == nil)
        #expect(fixture.agentStatus.reads == reads && fixture.diskEvents.stopCount == 0)
        fixture.runner.setLoaded(false)
        fixture.diskEvents.emit(.init(kind: .disappeared, volumeUUID: fixture.profile.devUUID))
        await settle()
        #expect(fixture.store.volumeRows.first { $0.id == fixture.profile.id }?.canSafeUnloadAndEject == false)
        #expect(fixture.store.volumeRows.count == 2 && fixture.agentStatus.reads == reads)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first { $0.id == fixture.profile.id }?.verifiedLoaded == false
        }
        #expect(fixture.diskEvents.startCount == 1 && fixture.diskEvents.stopCount == 0)
        #expect(fixture.agentStatus.reads == reads + 1)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("Uncorrelated native changes and hidden sleep invalidate without losing registrations")
    func unknownEventsAndHiddenSleepRemainConservative() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        fixture.store.deactivateWorkbench()
        fixture.diskEvents.emit(.init(kind: .descriptionChanged, bsdName: "disk999"))
        await settle()
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil)
        #expect(fixture.store.volumeRows.map(\.id) == [fixture.profile.id])
        fixture.store.activateSettings()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        fixture.store.deactivateSettings()
        let reads = fixture.agentStatus.reads
        fixture.notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        fixture.notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        await settle()
        #expect(fixture.agentStatus.reads == reads)
        fixture.store.activateSettings()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
        #expect(fixture.diskEvents.startCount == 1 && fixture.counters.calls == 0)
    }

    @Test("Standalone settings initializes once and never starts whole-device I/O sampling")
    func settingsInitializesWithoutResetOrIO() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.store.activateSettings()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let rows = fixture.store.volumeRows
        let reads = fixture.agentStatus.reads
        for _ in 0..<4 {
            fixture.store.deactivateSettings()
            fixture.store.activateSettings()
            fixture.store.sampleSelectedDeviceIO()
            #expect(fixture.store.volumeRows == rows && fixture.store.hasObservedStatus)
        }
        await settle()
        #expect(fixture.agentStatus.reads == reads && fixture.diskEvents.startCount == 1)
        #expect(fixture.counters.calls == 0)
    }

    @Test("Initial appeared notifications are absorbed by the first observation")
    func bootstrapEventsDoNotRestartObservation() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.diskEvents.setInitial(Array(repeating: .init(kind: .appeared,
            bsdName: fixture.device.bsdName, mediaUUID: UUID(uuidString: fixture.device.id)), count: 12))
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        await settle()
        #expect(fixture.agentStatus.reads == 1 && fixture.consistency.reads == 1)
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == true)
    }

    @Test("A real appeared event during the first observation is followed up before the five-minute interval")
    func appearedDuringFirstObservationIsNotBootstrap() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.runner.setLoaded(false)
        let oldStatus = fixture.agentStatus.blockNextRead()
        defer { oldStatus.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { oldStatus.entered }
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.volumeRows.first?.verifiedLoaded == false
        }
        #expect(!fixture.store.hasObservedStatus)
        fixture.runner.setLoaded(true)
        for _ in 0..<8 {
            fixture.diskEvents.emit(.init(kind: .appeared, wholeDiskBSDName: fixture.device.bsdName,
                volumeUUID: fixture.profile.devUUID))
        }
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.volumeRows.first?.verifiedLoaded == nil
        }
        #expect(fixture.agentStatus.reads == 1)
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        oldStatus.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.canSafeUnloadAndEject == true
        }
        await settle()
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
        #expect(fixture.agentStatus.reads == 2 && fixture.consistency.reads == 2)
        #expect(fixture.agentStatus.maximumConcurrentCalls == 1)
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("An unchanged stamp retries a failed detailed inventory once at the next five-minute interval")
    func failedDeepObservationRetriesAtConsistencyInterval() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.observer.setFailure(true)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.inventoryState == .unavailable)
        #expect(fixture.store.volumeRows.map(\.id) == [fixture.profile.id])
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        fixture.observer.setFailure(false)
        for _ in 0..<3 {
            fixture.clock.advance(1)
            fixture.store.refreshVisibleStatusIfDue()
        }
        await settle()
        #expect(fixture.agentStatus.reads == 1 && fixture.consistency.reads == 1)
        let retryStatus = fixture.agentStatus.blockNextRead()
        defer { retryStatus.release() }
        fixture.clock.advance(297)
        fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) { retryStatus.entered }
        for _ in 0..<8 { fixture.store.refreshVisibleStatusIfDue() }
        #expect(fixture.agentStatus.reads == 2)
        retryStatus.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.snapshot.readiness == .ready && fixture.store.inventoryState == .available
                && fixture.store.volumeRows.first?.canSafeUnloadAndEject == true
        }
        await settle()
        let commands = fixture.runner.commandCount
        fixture.clock.advance(301)
        fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.consistency.reads == 4 }
        await settle()
        #expect(fixture.agentStatus.reads == 2 && fixture.runner.commandCount == commands)
        #expect(fixture.agentStatus.maximumConcurrentCalls == 1 && fixture.consistency.maximumConcurrentCalls == 1)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Unknown registered-volume state and unavailable eject qualification recover with an unchanged stamp")
    func incompleteRowDetailsRetryAtConsistencyInterval() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.runner.setDevelopmentReadFailure(true)
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == nil)
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        fixture.runner.setDevelopmentReadFailure(false)
        fixture.ejectDriver.setQualificationAvailable(false)
        fixture.clock.advance(300)
        fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.agentStatus.reads == 2 && fixture.store.snapshot.readiness == .ready
                && fixture.store.volumeRows.first?.verifiedLoaded == true
        }
        await settle()
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        fixture.ejectDriver.setQualificationAvailable(true)
        fixture.clock.advance(299)
        fixture.store.refreshVisibleStatusIfDue()
        await settle()
        #expect(fixture.agentStatus.reads == 2)
        fixture.clock.advance(1)
        fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.agentStatus.reads == 3 && fixture.store.volumeRows.first?.canSafeUnloadAndEject == true
        }
        #expect(fixture.runner.mutationCalls.isEmpty && fixture.ejectDriver.mutationCalls == 0)
    }

    @Test("A valid empty registry and unknown I/O do not cause periodic deep retries")
    func emptyRegistryKeepsUnchangedConsistencyLightweight() async throws {
        let fixture = try VisibleStateFixture(registerProfile: false, nativeEvents: true)
        defer { fixture.finish() }
        let local = SectoriumPhysicalDevice(id: UUID().uuidString, bsdName: "disk0", name: "Internal fixture",
            isExternal: false, identityVerified: true, wholeDeviceBytes: 256_000_000_000,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
            topologyComplete: true, isVirtual: false)
        fixture.observer.setAdditionalDevices([local])
        try JSONEncoder().encode([SectoriumDevelopmentProfile]()).write(
            to: fixture.root.appendingPathComponent("support/sectorium-profiles.json"))
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.hasObservedRegistrations && fixture.store.volumeRows.isEmpty)
        #expect(fixture.store.workbench.devices.contains { $0.id == local.id })
        let commands = fixture.runner.commandCount
        for read in 2...4 {
            fixture.clock.advance(300)
            fixture.store.refreshVisibleStatusIfDue()
            try await eventually(diagnostics: fixture.diagnostics) { fixture.consistency.reads == read }
            await settle()
            #expect(fixture.agentStatus.reads == 1 && fixture.runner.commandCount == commands)
        }
    }

    @Test("A native change supersedes an in-flight consistency result and coalesces a fresh read")
    func eventSupersedesLateConsistency() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        let reads = fixture.agentStatus.reads
        let gate = fixture.consistency.blockNextRead()
        defer { gate.release() }
        fixture.clock.advance(301)
        fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        fixture.runner.setLoaded(false)
        for _ in 0..<8 { fixture.diskEvents.emit(.init(kind: .descriptionChanged, wholeDiskBSDName: fixture.device.bsdName)) }
        await settle()
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == false
        }
        await settle()
        #expect(fixture.agentStatus.reads == reads + 1 && fixture.consistency.maximumConcurrentCalls == 1)
        #expect(fixture.runner.mutationCalls.isEmpty)
    }

    @Test("A stamp changing during the deep read cannot become a misleading post-read baseline")
    func consistencyBaselinePrecedesDeepRead() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        let gate = fixture.agentStatus.blockNextRead()
        defer { gate.release() }
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { gate.entered }
        fixture.consistency.setFingerprint("changed-during-observation")
        fixture.runner.setLoaded(false)
        gate.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.verifiedLoaded == true)
        fixture.clock.advance(301)
        fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedStatus && fixture.store.volumeRows.first?.verifiedLoaded == false
        }
        #expect(fixture.agentStatus.reads == 2)
    }

    @Test("A retained eligible row still requires fresh action-time topology")
    func retainedQualificationCannotAuthorizeChangedTarget() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        try fixture.recordPendingDocumentation()
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == true)
        #expect(fixture.store.volumeRows.first?.documentationPending == true)
        fixture.store.deactivateWorkbench()
        fixture.store.activateWorkbench()
        fixture.ejectDriver.setQualificationAvailable(false)
        fixture.store.prepareWholeDeviceEjectConfirmation()
        try await eventually(diagnostics: fixture.diagnostics) { !fixture.store.isBusy }
        #expect(fixture.store.wholeDeviceEjectConfirmation == nil)
        #expect(!fixture.store.lastResult.isEmpty)
        #expect(fixture.ejectDriver.mutationCalls == 0 && fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Five-minute consistency notices registry replacement, corruption, recovery and deletion")
    func consistencyTracksOwnRegistry() async throws {
        let fixture = try VisibleStateFixture(nativeEvents: true)
        defer { fixture.finish() }
        let registry = fixture.root.appendingPathComponent("support/sectorium-profiles.json")
        fixture.store.activateWorkbench()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        var replacement = fixture.profile
        replacement.name = "Renamed volume"
        let saved = try JSONEncoder().encode([replacement])
        try saved.write(to: registry, options: .atomic)
        fixture.clock.advance(301); fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.volumeRows.first?.profile.name == replacement.name && fixture.store.hasObservedStatus
        }
        try Data("invalid".utf8).write(to: registry, options: .atomic)
        fixture.clock.advance(301); fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.registryUnavailable }
        #expect(fixture.store.volumeRows.map(\.id) == [fixture.profile.id])
        #expect(fixture.store.volumeRows.first?.canSafeUnloadAndEject == false)
        try saved.write(to: registry, options: .atomic)
        let recoveryStatus = fixture.agentStatus.blockNextRead()
        defer { recoveryStatus.release() }
        fixture.clock.advance(301); fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) { recoveryStatus.entered }
        try await eventually(diagnostics: fixture.diagnostics) {
            !fixture.store.registryUnavailable && fixture.store.volumeRows.first?.canSafeUnloadAndEject == true
        }
        #expect(!fixture.store.hasObservedStatus,
            "Fresh row qualification is published before the optional final status stage")
        recoveryStatus.release()
        try await eventually(diagnostics: fixture.diagnostics) { fixture.store.hasObservedStatus }
        try FileManager.default.removeItem(at: registry)
        fixture.clock.advance(301); fixture.store.refreshVisibleStatusIfDue()
        try await eventually(diagnostics: fixture.diagnostics) {
            fixture.store.hasObservedRegistrations && fixture.store.volumeRows.isEmpty && fixture.store.hasObservedStatus
        }
        #expect(!fixture.store.registryUnavailable && fixture.runner.mutationCalls.isEmpty)
    }

    @Test("Unrepresentable counter rates remain unknown instead of trapping", arguments: [0.5, 1.0])
    func extremeCounterRatesRemainUnknown(elapsed: Double) {
        let initial = SectoriumDeviceIOCounters(readBytes: 0, writtenBytes: 0)
        let enormous = SectoriumDeviceIOCounters(readBytes: UInt64.max, writtenBytes: UInt64.max)
        let result = HESectoriumStore.rateReading(previous: initial, current: enormous, elapsed: elapsed)
        #expect(!result.isFresh && result.readBytesPerSecond == nil && result.writtenBytesPerSecond == nil)
        let ordinary = HESectoriumStore.rateReading(previous: initial,
            current: .init(readBytes: 100, writtenBytes: 200), elapsed: elapsed)
        #expect(ordinary.isFresh)
        #expect(ordinary.readBytesPerSecond == UInt64(100 / elapsed))
        #expect(ordinary.writtenBytesPerSecond == UInt64(200 / elapsed))
    }

    #if DEBUG
    @Test("The isolated rendered fixture ignores wake, connection and polling lifecycle hooks")
    func previewRemainsInertAcrossFreshnessHooks() async {
        let store = HESectoriumStore.isolatedPreviewFixture()
        let rows = store.volumeRows, devices = store.workbench.devices
        let status = store.snapshot
        store.activateWorkbench()
        store.pauseSamplingForSleep()
        store.resumeSamplingAfterWake()
        store.storageConnectionChanged()
        store.refreshVisibleStatusIfDue(now: ProcessInfo.processInfo.systemUptime + 60)
        store.sampleSelectedDeviceIO()
        await settle()
        #expect(store.volumeRows == rows && store.workbench.devices == devices)
        #expect(store.snapshot == status && store.hasObservedStatus)
        #expect(!store.isBusy && store.safetyCheck == nil)
    }
    #endif

    private func eventually(diagnostics: @autoclosure @MainActor () -> String, _ condition: @MainActor () -> Bool,
                            line: Int = #line) async throws {
        // A hang-guard, not a speed bound. The loop below drives the store by
        // pumping the run loop in 5ms slices, which progresses far slower under
        // a full parallel suite run than in isolation; a 5-second deadline
        // failed there while passing every isolated run.
        let deadline = ProcessInfo.processInfo.systemUptime + 60
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            deliverScheduledObservation()
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(condition(), "Fixture wait at line \(line): \(diagnostics())")
    }

    private func settle() async {
        for _ in 0..<20 {
            deliverScheduledObservation()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Store publishes through a main-run-loop timer. One short synchronous
    /// iteration delivers it without constructing or showing an AppKit window.
    private func deliverScheduledObservation() {
        CFRunLoopRunInMode(.defaultMode, 0.001, true)
    }
}

/// All command responses are in-memory fixtures. There is no Process, shell,
/// mounted test image, real IMPORTANT, login service, or application window.
@MainActor
private final class VisibleStateFixture {
    let root: URL
    let device: SectoriumPhysicalDevice
    let profile: SectoriumDevelopmentProfile
    let notifications = NotificationCenter()
    let observer: VisibleStateObserver
    let runner: VisibleStateRunner
    let writer: VisibleStateDocumentWriter
    let ejectDriver: VisibleStateEjectDriver
    let agentStatus = VisibleStateAgentStatus()
    let clock = VisibleStateClock()
    let diskEvents = VisibleStateDiskEvents()
    let consistency = VisibleStateConsistency()
    let counters = VisibleStateNoCounters()
    let service: HESectoriumService
    let store: HESectoriumStore

    init(registerProfile: Bool = true, relocatedBacking: Bool = false, nativeEvents: Bool = false,
         applicationQuitter: (any SectoriumApplicationQuitting)? = nil) throws {
        let requestedRoot = URL(fileURLWithPath: "/private/tmp/auv-visible-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: requestedRoot, withIntermediateDirectories: true)
        root = requestedRoot.resolvingSymlinksInPath().standardizedFileURL
        let mount = root.appendingPathComponent("parent", isDirectory: true)
        let image = mount.appendingPathComponent("Development.sparsebundle", isDirectory: true)
        let dev = root.appendingPathComponent("development", isDirectory: true)
        let paths = HESectoriumPaths(root: root.appendingPathComponent("support", isDirectory: true))
        for directory in [image, dev, paths.root] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let backingID = UUID(), devID = UUID(), parentID = UUID()
        device = .init(id: parentID.uuidString, bsdName: "disk81", name: "Fixture Drive",
            isExternal: true, identityVerified: true, wholeDeviceBytes: 500_000_000_000,
            mountedVolumePaths: [mount.path], volumeUUIDs: [backingID], readBytes: nil, writtenBytes: nil,
            topologyComplete: true, isVirtual: false)
        let savedMount = relocatedBacking ? root.appendingPathComponent("previous-parent", isDirectory: true) : mount
        profile = .init(name: "Development", deviceID: device.id, backingVolumeUUID: backingID,
            backingMountPoint: savedMount.path, imagePath: savedMount.appendingPathComponent("Development.sparsebundle").path, devVolumeName: "Development",
            devMountPoint: dev.path, devUUID: devID, encrypted: false, caseSensitive: false,
            logicalCapacityBytes: 10_737_418_240, imageFormat: "UDSB", validation: .validated)
        if registerProfile { try JSONEncoder().encode([profile]).write(to: paths.sectoriumProfiles) }
        observer = VisibleStateObserver(device: device)
        var observedProfile = profile
        observedProfile.backingMountPoint = mount.path
        observedProfile.imagePath = image.path
        runner = VisibleStateRunner(profile: observedProfile)
        writer = VisibleStateDocumentWriter()
        ejectDriver = VisibleStateEjectDriver(device: device, profile: observedProfile)
        let policy = StorageIdentityPolicy(outerUUID: backingID, devUUID: devID,
            outerMountPoint: mount.path, devMountPoint: dev.path, devVolumeName: profile.name, imagePath: image.path)
        let service = HESectoriumService(paths: paths,
            installer: HESectoriumInstaller(paths: paths, home: root.appendingPathComponent("home")),
            runner: runner, identityPolicy: policy, agentStatusProvider: agentStatus, sectoriumDeviceObserver: observer,
            sectoriumDeviceIOSampler: counters, wholeDeviceEjectDriverOverride: ejectDriver,
            portableDocumentWriter: writer)
        self.service = service
        try #require(service.registeredProfileConfigurationReady == registerProfile,
            "Fixture registry must be readable: root=\(paths.root.path), resolved=\(paths.root.resolvingSymlinksInPath().path), parent=\(profile.backingMountPoint), normalized=\(URL(fileURLWithPath: profile.backingMountPoint).standardizedFileURL.path), image=\(profile.imagePath), dev=\(profile.devMountPoint)")
        store = HESectoriumStore(service: service, sampleIntervalNanoseconds: 3_600_000_000_000,
            workspaceNotifications: notifications, observationClock: { [clock] in clock.now },
            diskObserverFactory: { [diskEvents] callback in
                guard nativeEvents else { return nil }
                diskEvents.setCallback(callback)
                return diskEvents
            }, consistencyProvider: { [consistency] in consistency.observe(registry: paths.sectoriumProfiles) },
            applicationQuitter: applicationQuitter)
    }

    func addInternalProfile(internalFirst: Bool = false) throws -> SectoriumDevelopmentProfile {
        let mount = root.appendingPathComponent("internal", isDirectory: true)
        let image = mount.appendingPathComponent("Local.sparsebundle", isDirectory: true)
        let dev = root.appendingPathComponent("local-development", isDirectory: true)
        for directory in [image, dev] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let backing = UUID()
        let internalDrive = SectoriumPhysicalDevice(id: UUID().uuidString, bsdName: "disk0", name: "Internal fixture",
            isExternal: false, identityVerified: true, wholeDeviceBytes: 256_000_000_000,
            mountedVolumePaths: [mount.path], volumeUUIDs: [backing], readBytes: nil, writtenBytes: nil,
            topologyComplete: true, isVirtual: false)
        let internalProfile = SectoriumDevelopmentProfile(name: "Local", deviceID: internalDrive.id,
            backingVolumeUUID: backing, backingMountPoint: mount.path, imagePath: image.path,
            devVolumeName: "Local", devMountPoint: dev.path, devUUID: UUID(), encrypted: false,
            caseSensitive: false, logicalCapacityBytes: 10_737_418_240, imageFormat: "UDSB", validation: .validated)
        observer.setAdditionalDevices([internalDrive])
        let profiles = internalFirst ? [internalProfile, profile] : [profile, internalProfile]
        try JSONEncoder().encode(profiles).write(to: root.appendingPathComponent("support/sectorium-profiles.json"))
        return internalProfile
    }

    func recordSuccessfulEjectCallback() throws {
        let journal = WholeDeviceEjectJournalRecord(operationID: "prior-successful-eject",
            target: ejectDriver.originalTopology, phase: .ejectCallbackSucceeded,
            completedSteps: ["unmountImageVolumes:\(profile.imagePath)", "detachImage:\(profile.imagePath)",
                "unmountAllPhysicalVolumes", "ejectWholeDevice"],
            lastReceipt: .completed("Disk /dev/disk81 ejected"), lastIssuedAction: .ejectWholeDevice)
        let state = JSONStateStore(url: service.paths.root.appendingPathComponent("state.json"))
        var saved = try state.load()
        let revision = saved.revision
        saved = saved.advancingRevision()
        saved.ejectIntent = true
        saved.operationID = journal.operationID
        saved.workbenchOperation = "eject:\(journal.operationID)"
        saved.workbenchPhase = "eject:callback-succeeded"
        saved.workbenchTarget = try JSONEncoder().encode(journal).base64EncodedString()
        #expect(try state.compareAndSwap(expectedRevision: revision, newState: saved))
    }

    func recordPendingDocumentation() throws {
        let volume = SectoriumPortableVolumeRecord(profileID: profile.id, name: profile.name,
            volumeUUID: profile.devUUID, filesystem: "APFS", imagePath: profile.imagePath,
            mountPoint: profile.devMountPoint, autoLoad: false)
        let context = SectoriumPortableDocumentContext(parent: .init(physicalID: device.id,
            documentVolumeUUID: profile.backingVolumeUUID, rootPath: profile.backingMountPoint), volumes: [volume])
        let journal = SectoriumPortableDocumentJournal(url: root.appendingPathComponent("support/sectorium-document-journal.json"))
        try journal.record(context: context, event: .init(id: UUID().uuidString, occurredAt: Date(),
            profileID: profile.id, kind: "registered", after: volume))
    }

    var diagnostics: String {
        "observed=\(store.hasObservedStatus), rows=\(store.volumeRows.map { String(describing: $0.verifiedLoaded) }), inventory=\(store.inventoryState), observers=\(observer.calls), statusReads=\(agentStatus.reads), URLReads=\(writer.urlReads), commands=\(runner.commandCount), main=\(Thread.isMainThread), lastResult=\(store.lastResult)"
    }

    func finish() {
        store.deactivateWorkbench()
        store.deactivateSettings()
        consistency.releaseAll()
        observer.releaseAll()
        agentStatus.releaseAll()
        writer.releaseAll()
        runner.releaseAll()
        ejectDriver.releaseAll()
        try? FileManager.default.removeItem(at: root)
    }
}

private final class VisibleStateDiskEvents: SectoriumDiskChangeObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (SectoriumDiskChange) -> Void)?
    private var initial: [SectoriumDiskChange] = []
    private var starts = 0
    private var stops = 0
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    func setCallback(_ value: @escaping @Sendable (SectoriumDiskChange) -> Void) { lock.withLock { callback = value } }
    func setInitial(_ value: [SectoriumDiskChange]) { lock.withLock { initial = value } }
    func start() {
        let values = lock.withLock { starts += 1; return initial }
        values.forEach(emit)
    }
    func stop() { lock.withLock { stops += 1; callback = nil } }
    func emit(_ value: SectoriumDiskChange) { lock.withLock { callback }?(value) }
}

private final class VisibleStateConsistency: @unchecked Sendable {
    private let lock = NSLock()
    private var fingerprint: String? = "unchanged"
    private var count = 0
    private var active = 0
    private var maximum = 0
    private var nextGate: VisibleStateGate?
    private var gates: [VisibleStateGate] = []
    var reads: Int { lock.withLock { count } }
    var maximumConcurrentCalls: Int { lock.withLock { maximum } }
    func setFingerprint(_ value: String?) { lock.withLock { fingerprint = value } }
    func blockNextRead() -> VisibleStateGate {
        lock.withLock { let gate = VisibleStateGate(); gates.append(gate); nextGate = gate; return gate }
    }
    func releaseAll() { lock.withLock { gates }.forEach { $0.release() } }
    func observe(registry: URL) -> SectoriumConsistencyStamp? {
        let (value, gate) = lock.withLock {
            count += 1; active += 1; maximum = max(maximum, active)
            let gate = nextGate; nextGate = nil
            return (fingerprint, gate)
        }
        defer { lock.withLock { active -= 1 } }
        gate?.wait()
        guard let value else { return nil }
        guard FileManager.default.fileExists(atPath: registry.path) else {
            return .init(fingerprint: value + ":missing")
        }
        guard let data = try? Data(contentsOf: registry),
              (try? JSONDecoder().decode([SectoriumDevelopmentProfile].self, from: data)) != nil else { return nil }
        return .init(fingerprint: value + ":" + String(decoding: data, as: UTF8.self))
    }
}

private final class VisibleStateClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ProcessInfo.processInfo.systemUptime
    var now: TimeInterval { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

private final class VisibleStateGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var didEnter = false
    private var didRelease = false
    var entered: Bool { lock.withLock { didEnter } }
    func wait() {
        lock.withLock { didEnter = true }
        // Self-releases only so a failing test cannot hang forever, and must
        // outlast `eventually`'s deadline: a gate that came free on its own
        // mid-test would let blocked work through and prove the opposite of
        // what the test around it asserts.
        _ = semaphore.wait(timeout: .now() + 120)
    }
    func release() {
        let shouldRelease = lock.withLock { if didRelease { return false }; didRelease = true; return true }
        if shouldRelease { semaphore.signal() }
    }
}

private final class VisibleStateObserver: SectoriumDeviceObserving, @unchecked Sendable {
    private let lock = NSLock()
    private let device: SectoriumPhysicalDevice
    private var present = true
    private var additionalDevices: [SectoriumPhysicalDevice] = []
    private var shouldFail = false
    private enum ObservationError: Error { case fixtureInventoryDenied }
    private var count = 0
    private var concurrent = 0
    private var maximum = 0
    private var nextGate: VisibleStateGate?
    private var gates: [VisibleStateGate] = []
    init(device: SectoriumPhysicalDevice) { self.device = device }
    var calls: Int { lock.withLock { count } }
    var maximumConcurrentCalls: Int { lock.withLock { maximum } }
    func setPresent(_ value: Bool) { lock.withLock { present = value } }
    func setAdditionalDevices(_ value: [SectoriumPhysicalDevice]) { lock.withLock { additionalDevices = value } }
    func setFailure(_ value: Bool) { lock.withLock { shouldFail = value } }
    func blockNextObservation() -> VisibleStateGate {
        lock.withLock { let gate = VisibleStateGate(); nextGate = gate; gates.append(gate); return gate }
    }
    func releaseAll() { lock.withLock { gates }.forEach { $0.release() } }
    func observeDevices() throws -> [SectoriumPhysicalDevice] {
        let (gate, result): (VisibleStateGate?, [SectoriumPhysicalDevice]) = lock.withLock {
            count += 1; concurrent += 1; maximum = max(maximum, concurrent)
            let gate = nextGate; nextGate = nil
            return (gate, (present ? [device] : []) + additionalDevices)
        }
        gate?.wait()
        lock.withLock { concurrent -= 1 }
        if lock.withLock({ shouldFail }) { throw ObservationError.fixtureInventoryDenied }
        return result
    }
}

private final class VisibleStateRunner: HESectoriumCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let profile: SectoriumDevelopmentProfile
    private var loaded = true
    private var developmentWritable = true
    private var lifecycleSimulation = false
    private var simulatedUnloadFails = false
    private var nextMutationGate: VisibleStateGate?
    private var developmentReadFails = false
    private var mutations: [[String]] = []
    private var count = 0
    private var activityOutcome = CommandOutcome(exitCode: 127, detail: "Fixture activity not configured")
    private var nextDevelopmentGate: VisibleStateGate?
    private var infoGate: (String, VisibleStateGate)?
    private var gates: [VisibleStateGate] = []
    var commandCount: Int { lock.withLock { count } }
    init(profile: SectoriumDevelopmentProfile) { self.profile = profile }
    var mutationCalls: [[String]] { lock.withLock { mutations } }
    func setLoaded(_ value: Bool) { lock.withLock { loaded = value } }
    func enableLifecycleSimulation(unloadFails: Bool = false) {
        lock.withLock { lifecycleSimulation = true; simulatedUnloadFails = unloadFails }
    }
    func blockNextMutation() -> VisibleStateGate {
        lock.withLock { let gate = VisibleStateGate(); nextMutationGate = gate; gates.append(gate); return gate }
    }
    func setActivity(_ value: CommandOutcome) { lock.withLock { activityOutcome = value } }
    func setDevelopmentWritable(_ value: Bool) { lock.withLock { developmentWritable = value } }
    func setDevelopmentReadFailure(_ value: Bool) { lock.withLock { developmentReadFails = value } }
    func blockNextDevelopmentRead() -> VisibleStateGate {
        lock.withLock { let gate = VisibleStateGate(); nextDevelopmentGate = gate; gates.append(gate); return gate }
    }
    func blockInfoRead(at path: String) -> VisibleStateGate {
        lock.withLock { let gate = VisibleStateGate(); infoGate = (path, gate); gates.append(gate); return gate }
    }
    func releaseAll() { lock.withLock { gates }.forEach { $0.release() } }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        let loaded = lock.withLock { count += 1; return loaded }
        if executable == "/usr/sbin/lsof" { return lock.withLock { activityOutcome } }
        if lock.withLock({ lifecycleSimulation }), executable == "/usr/sbin/diskutil",
           arguments == ["unmount", profile.devMountPoint] || arguments == ["mount", "-mountPoint", profile.devMountPoint, "/dev/disk31s1"] {
            let gate = lock.withLock { () -> VisibleStateGate? in
                mutations.append([executable] + arguments)
                let value = nextMutationGate; nextMutationGate = nil; return value
            }
            gate?.wait()
            if arguments.first == "unmount", lock.withLock({ simulatedUnloadFails }) {
                return .init(exitCode: 1, detail: "Fixture normal unmount refused: volume in use")
            }
            lock.withLock { self.loaded = arguments.first == "mount" }
            return .init(exitCode: 0, detail: "Simulated native lifecycle command completed")
        }
        if executable == "/bin/ps" { return .init(exitCode: 1, detail: "Fixture process metadata unavailable") }
        let parent: [String: Any] = ["VolumeUUID": profile.backingVolumeUUID.uuidString,
            "MountPoint": profile.backingMountPoint, "FilesystemType": "ExFAT", "WritableVolume": true,
            "VolumeName": "Fixture Drive", "DeviceIdentifier": "disk81s1", "PartOfWhole": "disk81"]
        let development: [String: Any] = ["VolumeUUID": profile.devUUID!.uuidString,
            "MountPoint": profile.devMountPoint, "FilesystemType": "APFS", "WritableVolume": lock.withLock { developmentWritable },
            "VolumeName": profile.devVolumeName, "DeviceIdentifier": "disk31s1", "APFSContainerReference": "disk31"]
        if executable == "/usr/sbin/diskutil", arguments.count == 3, arguments.prefix(2) == ["info", "-plist"] {
            let targetedGate = lock.withLock { () -> VisibleStateGate? in
                guard let (path, gate) = infoGate, arguments[2] == path else { return nil }
                infoGate = nil
                return gate
            }
            targetedGate?.wait()
            if [profile.backingMountPoint, "/dev/disk81s1"].contains(arguments[2]) { return plist(parent) }
            if [profile.devMountPoint, "/dev/disk31s1"].contains(arguments[2]) {
                let gate = lock.withLock { let value = nextDevelopmentGate; nextDevelopmentGate = nil; return value }
                gate?.wait()
                if lock.withLock({ developmentReadFails }) {
                    return .init(exitCode: 1, detail: "Synthetic transient volume metadata failure")
                }
                if !loaded, lock.withLock({ lifecycleSimulation }), arguments[2] == "/dev/disk31s1" {
                    var unmounted = development; unmounted["MountPoint"] = ""
                    return plist(unmounted) // Native output omits Mounted on both loaded and unloaded volumes.
                }
                return plist(loaded ? development : parent)
            }
            if arguments[2] == "/dev/disk81" { return plist(["DeviceIdentifier": "disk81", "VirtualOrPhysical": "Physical", "WholeDisk": true]) }
        }
        if executable == "/usr/bin/hdiutil", arguments == ["info", "-plist"] {
            var volumeEntity = ["dev-entry": "/dev/disk31s1", "volume-uuid": profile.devUUID!.uuidString]
            if loaded { volumeEntity["mount-point"] = profile.devMountPoint }
            let images: [[String: Any]] = loaded || lock.withLock({ lifecycleSimulation })
                ? [["image-path": profile.imagePath, "system-entities": [["dev-entry": "/dev/disk30"], volumeEntity]]] : []
            return plist(["images": images])
        }
        if executable == "/usr/sbin/diskutil", arguments == ["apfs", "list", "-plist"] {
            return plist(["Containers": [["ContainerReference": "disk31", "PhysicalStores": [["DeviceIdentifier": "disk30"]],
                "Volumes": [["DeviceIdentifier": "disk31s1", "APFSVolumeUUID": profile.devUUID!.uuidString]]]]])
        }
        if executable == "/bin/df", arguments.first == "-P" {
            return .init(exitCode: 0, detail: "Filesystem 512-blocks Used Available Capacity Mounted on\n/dev/disk81s1 100 10 90 10% \(profile.backingMountPoint)\n")
        }
        let allowedRead = (executable == "/usr/sbin/diskutil" && ["info", "list"].contains(arguments.first ?? ""))
            || (executable == "/usr/bin/hdiutil" && ["imageinfo", "isencrypted"].contains(arguments.first ?? ""))
            || (executable == "/usr/bin/hdiutil" && arguments.contains("-limits"))
            || executable == "/usr/sbin/lsof"
        if !allowedRead { lock.withLock { mutations.append([executable] + arguments) } }
        return .init(exitCode: 127, detail: "No real command is permitted by the visible-state fixture")
    }
    private func plist(_ value: [String: Any]) -> CommandOutcome {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0) else {
            return .init(exitCode: 127, detail: "Invalid fixture plist")
        }
        return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
    }
}

@MainActor private final class VisibleStateQuitter: SectoriumApplicationQuitting {
    var requests: [Int32] = []
    var onQuit: (() -> Void)?
    func applications(using processes: [SectoriumActivityProcess]) -> [SectoriumQuitApplication] {
        processes.contains { $0.processID == 41001 }
            ? [.init(processID: 41001, bundleIdentifier: "test.fixture.editor", name: "Fixture Editor")] : []
    }
    func requestQuit(_ application: SectoriumQuitApplication) -> Bool {
        requests.append(application.processID); onQuit?(); return true
    }
    func isRunning(_ application: SectoriumQuitApplication) -> Bool { false }
}

private final class VisibleStateDocumentWriter: SectoriumPortableDocumentWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private var nextGate: VisibleStateGate?
    private var nextURLGate: VisibleStateGate?
    private var gates: [VisibleStateGate] = []
    var urlReads: Int { lock.withLock { reads } }
    func update(profile: SectoriumDevelopmentProfile, event: String) -> SectoriumPortableDocumentResult {
        .pending("Read-only fixture forbids document updates")
    }
    func blockNextUpdate() -> VisibleStateGate {
        lock.withLock { let gate = VisibleStateGate(); nextGate = gate; gates.append(gate); return gate }
    }
    func blockNextURLRead() -> VisibleStateGate {
        lock.withLock { let gate = VisibleStateGate(); nextURLGate = gate; gates.append(gate); return gate }
    }
    func releaseAll() { lock.withLock { gates }.forEach { $0.release() } }
    func update(context: SectoriumPortableDocumentContext, events: [SectoriumPortableDocumentEvent]) -> SectoriumPortableDocumentResult {
        let gate = lock.withLock { let value = nextGate; nextGate = nil; return value }
        gate?.wait()
        return .unchanged
    }
    func verifiedDocumentURL(context: SectoriumPortableDocumentContext) -> URL? {
        let gate = lock.withLock { reads += 1; let value = nextURLGate; nextURLGate = nil; return value }
        gate?.wait()
        return URL(fileURLWithPath: context.parent.rootPath).appendingPathComponent("fixture-IMPORTANT.md")
    }
}

private final class VisibleStateAgentStatus: HESectoriumAgentStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var concurrent = 0
    private var maximum = 0
    private var nextGate: VisibleStateGate?
    private var gates: [VisibleStateGate] = []
    var reads: Int { lock.withLock { count } }
    var maximumConcurrentCalls: Int { lock.withLock { maximum } }

    /// refreshStatus calls this provider exactly once. Auxiliary eject-availability
    /// reads do not, so this barrier targets the main refresh instead of whichever
    /// underlying device observation happens to be scheduled next.
    func blockNextRead() -> VisibleStateGate {
        lock.withLock { let gate = VisibleStateGate(); nextGate = gate; gates.append(gate); return gate }
    }
    func releaseAll() { lock.withLock { gates }.forEach { $0.release() } }
    func loadStatus(label: String) -> HESectoriumAgentLoadStatus {
        let gate = lock.withLock {
            count += 1; concurrent += 1; maximum = max(maximum, concurrent)
            let value = nextGate; nextGate = nil; return value
        }
        gate?.wait()
        lock.withLock { concurrent -= 1 }
        return .unknown
    }
}

private final class VisibleStateNoCounters: SectoriumDeviceIOCounterSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func counters(forWholeBSDName bsdName: String, expectedMediaID: UUID) -> SectoriumDeviceIOCounters? {
        lock.withLock { count += 1 }
        return nil
    }
}

private final class VisibleStateEjectDriver: WholeDeviceEjectDriving, @unchecked Sendable {
    private let lock = NSLock()
    private let topology: WholeDeviceTopology
    private var nextGate: VisibleStateGate?
    private var gates: [VisibleStateGate] = []
    private var mutations = 0
    private var observations = 0
    private var qualificationAvailable = true
    private var logicalEject: Bool?
    var originalTopology: WholeDeviceTopology { topology }
    func setLogicallyEjected(_ value: Bool?) { lock.withLock { logicalEject = value } }
    func successfulEjectHasUnmountedPostcondition(of target: WholeDeviceTopology) -> Bool {
        target.physicalIdentity == topology.physicalIdentity && lock.withLock { logicalEject == true }
    }
    func setQualificationAvailable(_ value: Bool) { lock.withLock { qualificationAvailable = value } }
    var mutationCalls: Int { lock.withLock { mutations } }
    var observationCalls: Int { lock.withLock { observations } }

    init(device: SectoriumPhysicalDevice, profile: SectoriumDevelopmentProfile) {
        topology = .init(physicalIdentity: device.id, bsdName: device.bsdName,
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "\(profile.backingVolumeUUID.uuidString)|disk81s1", mounted: true)],
            images: [.init(identity: profile.imagePath, attached: true,
                volumeIdentities: ["\(profile.devUUID!.uuidString)|disk31s1"])])
    }
    func blockNextObservation() -> VisibleStateGate {
        lock.withLock { let gate = VisibleStateGate(); nextGate = gate; gates.append(gate); return gate }
    }
    func releaseAll() { lock.withLock { gates }.forEach { $0.release() } }
    func observe(physicalIdentity: String) -> WholeDeviceTopology? {
        let gate = lock.withLock { observations += 1; let value = nextGate; nextGate = nil; return value }
        gate?.wait()
        return physicalIdentity == topology.physicalIdentity && lock.withLock({ qualificationAvailable }) ? topology : nil
    }
    private func forbidden() -> WholeDeviceActionReceipt {
        lock.withLock { mutations += 1 }
        return .failed("Read-only visible-state fixture forbids storage mutations")
    }
    func unmountImageVolumesNonForce(_ imageIdentity: String, volumeIdentities: [String], from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { forbidden() }
    func detachImageNonForce(_ imageIdentity: String, from target: WholeDeviceTopology) -> WholeDeviceActionReceipt { forbidden() }
    func unmountAllPhysicalVolumesNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt { forbidden() }
    func ejectWholeDeviceNonForce(_ target: WholeDeviceTopology) -> WholeDeviceActionReceipt { forbidden() }
    func presence(physicalIdentity: String) -> WholeDevicePresence {
        lock.withLock { logicalEject != nil ? .present : .unknown("No physical presence observation in fixture") }
    }
    func presence(of target: WholeDeviceTopology) -> WholeDevicePresence {
        presence(physicalIdentity: target.physicalIdentity)
    }
    func freshReturnIdentityMatches(_ journal: WholeDeviceEjectJournalRecord) -> Bool {
        journal.target.physicalIdentity == topology.physicalIdentity && lock.withLock { logicalEject == false }
    }
}
