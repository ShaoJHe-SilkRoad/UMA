import Foundation
import Testing
import HESectoriumCore
import HESectoriumRuntime
@testable import CodexUsageUI

private final class SectoriumEjectBindingFixtureRunner: HESectoriumCommandRunning {
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        .init(exitCode: 127, detail: "No disk command is allowed in the UI binding fixture")
    }
}

@Suite("HESectorium integration UI contract")
struct HESectoriumUIContractTests {
    #if DEBUG
    @MainActor
    @Test("Rendered preview fixture has multiple states and no enabled host-operation route")
    func isolatedRenderFixtureNeverRunsHostActions() throws {
        let store = HESectoriumStore.isolatedPreviewFixture()
        let profiles = store.volumeRows.map(\.profile)
        let rows = store.volumeRows
        let devices = store.workbench.devices
        #expect(devices.count == 2 && devices.first?.isExternal == true)
        #expect(rows.contains { $0.verifiedLoaded == true })
        #expect(rows.contains { $0.verifiedLoaded == false })
        #expect(rows.contains { $0.verifiedLoaded == nil })
        let loaded = try #require(rows.first { $0.verifiedLoaded == true })
        store.activateWorkbench()
        store.refresh()
        store.install()
        store.installRepair()
        store.setAutomation(false)
        store.loadDevelopmentDisk(profileID: profiles[1].id)
        store.updateDevelopmentDisk(profileID: loaded.id, change: .displayName("Should not change"))
        store.prepareUnloadOnlyConfirmation(profileID: loaded.id)
        store.prepareSafeUnloadAndEject(profileID: loaded.id)
        store.retryDocumentation(profileID: loaded.id)
        #expect(store.volumeRows == rows)
        #expect(store.workbench.devices == devices)
        #expect(!store.isBusy)
        #expect(store.safetyCheck == nil && store.wholeDeviceEjectConfirmation == nil)
        #expect(store.snapshot.latestActionSummary.contains("Synthetic"))
    }
    #endif

    @Test("Volume names accept readable bilingual labels and reject path-like input")
    func bilingualVolumeNames() {
        for name in ["Development", "开发 工作盘", "Research 2026", "测试-一"] {
            #expect(SectoriumVolumeNameInput.isValid(name))
        }
        for name in ["", "../DEV", "/Volumes/DEV", "a:b", " spaced", "line\nnext", String(repeating: "a", count: 81)] {
            #expect(!SectoriumVolumeNameInput.isValid(name))
        }
    }

    @Test("Activity uncertainty and waiting never become an unload permission")
    func activityCheckPresentation() {
        let target = SectoriumSafetyTarget.volume("profile-a")
        #expect(SectoriumSafetyCheck(target: target, name: "A", activity: .noVisibleOccupancy).canProceed)
        #expect(!SectoriumSafetyCheck(target: target, name: "A", activity: .busy(processIDs: [12])).canProceed)
        #expect(!SectoriumSafetyCheck(target: target, name: "A", activity: .incomplete(reason: "unavailable")).canProceed)
        #expect(!SectoriumSafetyCheck(target: target, name: "A", activity: .noVisibleOccupancy, waiting: true).canProceed)
    }

    @Test("Structured errors cannot turn failure text containing Completed into success")
    func structuredOperationNotices() {
        let failure = OperationResult(operationID: "fixture", mode: .manual, steps: [],
                                      failure: .workbenchFailed("Completed stage one; stage two failed"))
        let notice = SectoriumUserNotice.operation(failure, observed: true)
        #expect(notice.english.contains("did not finish"))
        #expect(notice.chinese.contains("操作未完成"))
        let unknown = SectoriumUserNotice.operation(.init(operationID: "fixture", mode: .manual, steps: [], failure: nil), observed: false)
        #expect(unknown.english.contains("could not be verified"))
        let occupied = SectoriumUserNotice.operation(.init(operationID: "fixture", mode: .manual, steps: [],
            failure: .occupancyBusy(.dev, [12])), observed: true)
        #expect(occupied.english.contains("in use"))
        let unloaded = OperationResult(operationID: "unload", mode: .manual,
            steps: [.init(step: "verifyDevelopmentVolumeUnloaded", status: .succeeded, detail: "fixture")], failure: nil)
        #expect(SectoriumUserNotice.operation(unloaded, observed: true).english.contains("parent drive remains connected"))
        #expect(SectoriumUserNotice.operation(unloaded, observed: false).english.contains("could not be verified"))
    }

    @Test("Only terminal target verification publishes lifecycle success")
    func verifiedCommandCompletionContract() {
        func result(_ steps: [String], failure: OperationFailure? = nil) -> OperationResult {
            .init(operationID: "fixture", mode: .manual,
                steps: steps.map { .init(step: $0, status: .succeeded) }, failure: failure)
        }
        #expect(SectoriumCommandAction.unload.isVerified(by: result(["verifyDevelopmentVolumeUnloaded"]), pending: nil))
        #expect(!SectoriumCommandAction.unload.isVerified(by: result(["unmountDEV"]), pending: nil))
        #expect(!SectoriumCommandAction.unload.isVerified(by: result(["verifyDevelopmentVolumeUnloaded"]), pending: "unload:pending"))
        #expect(SectoriumCommandAction.load.isVerified(by: result(["validateImageChain"]), pending: nil))
        #expect(!SectoriumCommandAction.load.isVerified(by: result(["attachImage"]), pending: nil))
        #expect(!SectoriumCommandAction.disconnect.isVerified(by: result(["ejectWholeDevice"]), pending: nil))
        #expect(SectoriumCommandAction.disconnect.isVerified(by: result(["observeWholeDeviceAbsentAfterEjectIssue", "verifyPhysicalDeviceAbsent"]), pending: nil))
        #expect(!SectoriumCommandAction.disconnect.isVerified(by: result(["verifyPhysicalDeviceAbsent"]), pending: nil))
        #expect(SectoriumCommandAction.disconnect.isVerified(by: result(["ejectWholeDevice", "verifyPhysicalDeviceAbsent"]), pending: nil))
        #expect(!SectoriumCommandAction.disconnect.isVerified(by: result(["ejectWholeDevice", "verifyPhysicalDeviceAbsent"], failure: .finalStateUnknown("fixture uncertainty")), pending: nil))
        #expect(SectoriumCommandAction.unload.success.english.hasPrefix("Unload successful"))
        #expect(SectoriumCommandAction.unload.success.chinese.contains("卸载成功"))
    }

    @Test("Refreshing a volume clears stale loaded actions while preserving document-pending evidence")
    func staleRowCannotRemainActionable() {
        let profile = SectoriumDevelopmentProfile(name: "开发卷", deviceID: "parent", backingVolumeUUID: UUID(),
            backingMountPoint: "/fixture", imagePath: "/fixture/development.sparsebundle",
            devVolumeName: "开发卷", devMountPoint: "/fixture/dev", encrypted: false,
            caseSensitive: false, logicalCapacityBytes: 100, imageFormat: "UDSB")
        let row = SectoriumVolumeRow(profile: profile, parentDeviceID: "parent", parentName: "External",
            isExternal: true, verifiedLoaded: true, parentConnected: true, canLoad: false,
            canUnloadOnly: true, canSafeUnloadAndEject: true, isBusy: false,
            importantDocumentURL: URL(fileURLWithPath: "/fixture/IMPORTANT.md"), documentationPending: true,
            documentHistory: [], capacityChangeUnavailableReason: nil)
        #expect(row.verifiedLoaded == true)
        #expect(row.message(isChinese: false).isEmpty, "Optional history sync must stay in diagnostics, not replace the lifecycle status")
        let refreshing = HESectoriumStore.unverified(row)
        #expect(refreshing.verifiedLoaded == nil)
        #expect(!refreshing.canLoad && !refreshing.canUnloadOnly && !refreshing.canSafeUnloadAndEject)
        #expect(refreshing.importantDocumentURL == nil && refreshing.documentationPending)
        #expect(refreshing.profile.id == row.profile.id)
        let disconnected = HESectoriumStore.disconnected(row)
        #expect(disconnected.verifiedLoaded == false && !disconnected.parentConnected && !disconnected.isBusy)
        #expect(!disconnected.canLoad && !disconnected.canUnloadOnly && !disconnected.canSafeUnloadAndEject)
        #expect(disconnected.message(isChinese: false).contains("disconnected"))
        #expect(!disconnected.message(isChinese: false).contains("sync"))
        #expect(disconnected.profile == row.profile && disconnected.documentationPending)
    }

    @Test("Loaded external volumes expose distinct Unload and Disconnect; unloaded volumes expose only Load")
    func perVolumePrimaryActionPolicy() {
        func plan(_ loaded: Bool?, external: Bool = true, canLoad: Bool = true,
                  canUnload: Bool = true, canEject: Bool = true, busy: Bool = false) -> SectoriumVolumeActionPlan {
            .make(verifiedLoaded: loaded, isExternal: external, canLoad: canLoad,
                  canUnloadOnly: canUnload, canSafeUnloadAndEject: canEject, busy: busy)
        }
        #expect(plan(false).action == .load && plan(false).enabled)
        #expect(plan(true).action == .unloadOnly && plan(true).enabled)
        #expect(plan(true).disconnectEnabled == true)
        #expect(plan(true, external: false).action == .unloadOnly)
        #expect(plan(true, external: false).disconnectEnabled == nil)
        #expect(plan(true, external: false, canUnload: false).enabled == false)
        #expect(plan(true, canEject: false).enabled == true,
            "Whole-drive eject qualification must not remove an independently verified Unload action")
        #expect(plan(true, canEject: false).disconnectEnabled == false)
        #expect(plan(true, canUnload: false).disconnectEnabled == true)
        #expect(plan(false).disconnectEnabled == nil)
        #expect(plan(nil).disconnectEnabled == nil)
        #expect(plan(true, busy: true).disconnectEnabled == false)
        #expect(plan(false, canLoad: false).enabled == false)
        #expect(plan(false, busy: true).enabled == false)
        #expect(plan(nil).action == .recheck,
                "Unknown observation offers a fresh read without fabricating a third loading state")
    }

    @Test("Sectorium action policy follows observed state without exposing blocked actions")
    func sectoriumActionPolicy() {
        func input(_ readiness: SectoriumWorkbenchReadiness = .connected,
                   identity: Bool = true, external: Bool = true, stale: Bool = false,
                   inventory: Bool = true, busy: Bool = false, profile: Bool = false,
                   format: Bool = true, legacy: SectoriumWorkbenchActionPlan.LegacyState = .none,
                   pending: String? = nil, beginEject: Bool = false,
                   continueEject: Bool = false, returnFromEject: Bool = false) -> SectoriumWorkbenchActionPlan.Input {
            .init(hasDrive: true, identityVerified: identity, external: external, stale: stale,
                  inventoryAvailable: inventory, busy: busy, readiness: readiness,
                  hasProfile: profile, profileFormatVerified: format, legacyState: legacy,
                  pendingOperation: pending, canBeginEject: beginEject,
                  canContinueEject: continueEject, canReturnFromEject: returnFromEject)
        }
        let mountedLegacy = SectoriumWorkbenchActionPlan.make(input(legacy: .mounted, beginEject: true))
        #expect(mountedLegacy.primary == .eject)
        #expect(mountedLegacy.secondary == [.adopt])
        #expect(!mountedLegacy.secondary.contains(.stop))
        let mountedLegacyWithoutEjectCheckpoint = SectoriumWorkbenchActionPlan.make(input(legacy: .mounted))
        #expect(mountedLegacyWithoutEjectCheckpoint.primary == .adopt)
        #expect(!mountedLegacyWithoutEjectCheckpoint.secondary.contains(.stop))
        let mountedLocalLegacy = SectoriumWorkbenchActionPlan.make(input(external: false, legacy: .mounted, beginEject: true))
        #expect(mountedLocalLegacy.primary == .adopt)
        #expect(!mountedLocalLegacy.secondary.contains(.eject))

        let pendingMountedLegacy = SectoriumWorkbenchActionPlan.make(input(
            .operationInProgress("eject:pending"), legacy: .mounted, pending: "eject:pending",
            beginEject: true))
        #expect(pendingMountedLegacy.primary == .recheck && pendingMountedLegacy.secondary.isEmpty)
        let busyMountedLegacy = SectoriumWorkbenchActionPlan.make(input(
            .busy, busy: true, legacy: .mounted, beginEject: true))
        #expect(busyMountedLegacy.primary == nil && busyMountedLegacy.secondary.isEmpty)
        let staleMountedLegacy = SectoriumWorkbenchActionPlan.make(input(
            stale: true, legacy: .mounted, beginEject: true))
        #expect(staleMountedLegacy.primary == .recheck && staleMountedLegacy.secondary.isEmpty)
        let unidentifiedMountedLegacy = SectoriumWorkbenchActionPlan.make(input(
            identity: false, legacy: .mounted, beginEject: true))
        #expect(unidentifiedMountedLegacy.primary == .recheck && unidentifiedMountedLegacy.secondary.isEmpty)

        let detachedLegacy = SectoriumWorkbenchActionPlan.make(input(.notStarted, legacy: .detached))
        #expect(detachedLegacy.primary == .adopt)
        #expect(!detachedLegacy.secondary.contains(.create))
        #expect(SectoriumLegacyPresentationPolicy.currentLegacyState(inventoryAvailable: true, busy: false,
            pending: false, stale: false, identityVerified: true, readiness: .noDevelopmentDisk,
            observed: .detached) == .detached)

        let ready = SectoriumWorkbenchActionPlan.make(input(.ready, profile: true, beginEject: true))
        #expect(ready.primary == .eject)
        #expect(ready.secondary == [.create, .stop])

        let stopped = SectoriumWorkbenchActionPlan.make(input(.notStarted, profile: true))
        #expect(stopped.primary == .start)
        #expect(!stopped.secondary.contains(.adopt))

        let noImage = SectoriumWorkbenchActionPlan.make(input(.noDevelopmentDisk))
        #expect(noImage.primary == .create)
        #expect(noImage.secondary == [.adopt])
        var needsComponents = input(.noDevelopmentDisk)
        needsComponents.componentSetupNeeded = true
        let firstUse = SectoriumWorkbenchActionPlan.make(needsComponents)
        #expect(firstUse.primary == .setupComponents)
        #expect(!firstUse.secondary.contains(.create))

        let readyWithoutEject = SectoriumWorkbenchActionPlan.make(input(.ready, profile: true))
        #expect(readyWithoutEject.primary == .recheck)
        #expect(readyWithoutEject.secondary.contains(.stop))
        let readOnly = SectoriumWorkbenchActionPlan.make(input(.readOnly, profile: true, beginEject: true))
        #expect(readOnly.primary == .eject)
        #expect(readOnly.secondary.contains(.stop))

        let localDrive = SectoriumWorkbenchActionPlan.make(input(.noDevelopmentDisk, external: false, beginEject: true))
        #expect(localDrive.primary == .create)
        #expect(!localDrive.secondary.contains(.eject))

        let unavailableIdentity = SectoriumWorkbenchActionPlan.make(input(identity: false, beginEject: true))
        #expect(unavailableIdentity.primary == .recheck && unavailableIdentity.secondary.isEmpty)
        #expect(unavailableIdentity.unavailableReason == .identityUnavailable)

        let busy = SectoriumWorkbenchActionPlan.make(input(.busy, profile: true, beginEject: true))
        #expect(busy.primary == nil && busy.secondary.isEmpty && busy.unavailableReason == .busy)

        let stale = SectoriumWorkbenchActionPlan.make(input(stale: true))
        #expect(stale.primary == .recheck && stale.secondary.isEmpty && stale.unavailableReason == .stale)

        let unknown = SectoriumWorkbenchActionPlan.make(input(.unknown("identity unavailable"), profile: true, beginEject: true))
        #expect(unknown.primary == .recheck && unknown.secondary.isEmpty)

        let genericRecovery = SectoriumWorkbenchActionPlan.make(input(.operationInProgress("start:pending"),
            pending: "start:pending"))
        #expect(genericRecovery.recovery == [.resume])

        let ejectRecovery = SectoriumWorkbenchActionPlan.make(input(.operationInProgress("eject:pending"),
            pending: "eject:pending", continueEject: true, returnFromEject: true))
        #expect(ejectRecovery.primary == .continueEject)
        #expect(ejectRecovery.recovery == [.continueEject, .returnToDevelopment])
        #expect(ejectRecovery.secondary.isEmpty)
        let archivedEjectReturn = SectoriumWorkbenchActionPlan.make(input(
            .notStarted, profile: true, returnFromEject: true))
        #expect(archivedEjectReturn.primary == .returnToDevelopment)
        #expect(archivedEjectReturn.recovery == [.returnToDevelopment])

        let uncertainLegacy = SectoriumWorkbenchActionPlan.make(input(.unknown("partial inventory"), legacy: .unknown))
        #expect(uncertainLegacy.primary == .recheck && uncertainLegacy.secondary.isEmpty)
        #expect(uncertainLegacy.unavailableReason == .stateUnknown)

        let partialWithoutRecovery = SectoriumWorkbenchActionPlan.make(input(.partialFailure("incomplete stop")))
        #expect(partialWithoutRecovery.primary == .recheck && partialWithoutRecovery.secondary.isEmpty)
        #expect(partialWithoutRecovery.unavailableReason == .stateUnknown)
        let partialWithRecovery = SectoriumWorkbenchActionPlan.make(input(.partialFailure("interrupted start"),
            pending: "start:interrupted"))
        #expect(partialWithRecovery.recovery == [.resume])

        let busyRecovery = SectoriumWorkbenchActionPlan.make(input(.busy, busy: true, pending: "start:interrupted"))
        #expect(busyRecovery.recovery.isEmpty && busyRecovery.unavailableReason == .busy)

        let unavailableEjectRecovery = SectoriumWorkbenchActionPlan.make(input(
            .operationInProgress("eject:pending"), pending: "eject:pending"))
        #expect(unavailableEjectRecovery.recovery.isEmpty)
        #expect(unavailableEjectRecovery.primary == .recheck)
        #expect(unavailableEjectRecovery.unavailableReason == .stateUnknown)

        let safeToUnplug = SectoriumWorkbenchActionPlan.make(input(.ejected))
        #expect(safeToUnplug.primary == nil && safeToUnplug.secondary.isEmpty)
    }

    @Test("Cached legacy labels cannot mask incompatible current state or offer stale adoption")
    func legacyPresentationPolicy() {
        func resolve(_ readiness: SectoriumWorkbenchReadiness,
                     observed: SectoriumWorkbenchActionPlan.LegacyState = .mounted,
                     inventory: Bool = true, busy: Bool = false, pending: Bool = false,
                     stale: Bool = false, identity: Bool = true, canEject: Bool = false)
            -> (SectoriumWorkbenchActionPlan.LegacyState, SectoriumWorkbenchActionPlan) {
            let currentLegacy = SectoriumLegacyPresentationPolicy.currentLegacyState(
                inventoryAvailable: inventory, busy: busy, pending: pending, stale: stale,
                identityVerified: identity, readiness: readiness, observed: observed)
            let actions = SectoriumWorkbenchActionPlan.make(.init(
                hasDrive: true, identityVerified: identity, external: true, stale: stale,
                inventoryAvailable: inventory, busy: busy, readiness: readiness,
                hasProfile: false, profileFormatVerified: true, legacyState: currentLegacy,
                pendingOperation: pending ? "start:pending" : nil, canBeginEject: canEject,
                canContinueEject: false, canReturnFromEject: false))
            return (currentLegacy, actions)
        }
        let mounted = resolve(.connected)
        #expect(mounted.0 == .mounted)
        #expect(mounted.1.primary == .adopt)

        let detached = resolve(.notStarted, observed: .detached)
        #expect(detached.0 == .detached)
        #expect(detached.1.primary == .adopt)

        let incompatibleReadiness: [SectoriumWorkbenchReadiness] = [
            .readOnly, .awaitingUnlock, .noDevice, .operationInProgress("start:interrupted"),
            .partialFailure("partial stop"), .unknown("fresh state unavailable"), .ejected
        ]
        for readiness in incompatibleReadiness {
            let blocked = resolve(readiness, canEject: readiness == .readOnly)
            #expect(blocked.0 == .none, "Current status must be chosen for \(readiness).")
            #expect(blocked.1.primary != .adopt, "Cached legacy metadata must not offer Adopt for \(readiness).")
            if readiness == .readOnly {
                #expect(blocked.1.primary == .eject,
                        "A separately verified read-only external target may retain gated safe Eject.")
            }
        }
        #expect(resolve(.connected, inventory: false).0 == .none)
        #expect(resolve(.connected, busy: true).0 == .none)
        #expect(resolve(.connected, pending: true).0 == .none)
        #expect(resolve(.connected, stale: true).0 == .none)
        #expect(resolve(.connected, identity: false).0 == .none)
        #expect(resolve(.notStarted, observed: .mounted).0 == .none,
                "Mounted legacy state is compatible only with current connected readiness.")
        #expect(resolve(.connected, observed: .detached).0 == .none,
                "Detached legacy state is compatible only with current not-started readiness.")
        let unknownLegacy = resolve(.connected, observed: .unknown)
        #expect(unknownLegacy.0 == .unknown)
        #expect(unknownLegacy.1.primary == .recheck && unknownLegacy.1.secondary.isEmpty,
                "Unknown legacy state must remain blocking rather than becoming create/adopt success.")
    }

    @Test("Unload uses a fresh profile checkpoint and available activity signals, not a user assertion")
    func stopConfirmationContract() throws {
        let service = try source("Sources/HESectoriumRuntime/HESectoriumService.swift")
        let view = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(service.contains("activityFailure(profileActivity(profileID: profileID)"))
        #expect(store.contains("unloadDevelopmentDisk(profileID: id, checkpoint: confirmation)"))
        #expect(store.contains("service.profileActivityReport(profileID: id)"))
        #expect(store.contains("service.wholeDeviceActivityReport(physicalIdentity: id)"))
        #expect(view.contains("SectoriumActivityCheckView"))
        #expect(view.contains("model.waitForSafeUnload()"))
        #expect(view.contains("model.cancelSafetyCheck()"))
        #expect(!view.contains("stop-known-writers-closed"))
        #expect(!view.contains("eject-known-writers-closed"))
    }

    @Test("Four-input creation uses automatic verified parent location and bounded capacity")
    func capacityInputContract() throws {
        let view = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let action = try #require(view.range(of: "private func createDevelopmentDisk()"))
        let createSource = String(view[action.lowerBound...])
        for field in ["uma.sectorium.create.parent", "uma.sectorium.create.name",
                      "uma.sectorium.create.capacity", "uma.sectorium.create.filesystem"] {
            #expect(view.contains(field))
        }
        #expect(createSource.contains("SectoriumCapacityInput.isValid(capacityGiB)"))
        #expect(createSource.contains("parentDirectory: nil"))
        #expect(createSource.contains("autoLoad: creationAutoLoad"))
        #expect(createSource.contains("model.createDevelopmentDisk(request: request)"))
        #expect(!createSource.prefix(1800).contains("NSOpenPanel"))
        #expect(view.contains("multipliedReportingOverflow"))
        #expect(view.contains("static let maximumGiB = 16_384"))
    }

    @Test("Eject intent and mutation boundary are committed in one durable state update")
    func ejectIntentCommitIsAtomic() throws {
        let service = try source("Sources/HESectoriumRuntime/HESectoriumService.swift")
        let protocolSource = try source("Sources/HESectoriumCore/WholeDeviceEjectProtocol.swift")
        let workbench = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(service.contains("public func prepareWholeDeviceEjectConfirmation()"))
        #expect(service.contains("public func ejectSelectedExternalDevice(checkpoint: WholeDeviceEjectCheckpoint)"))
        #expect(service.contains("public func prepareContinueWholeDeviceEjectConfirmation()"))
        #expect(service.contains("public func continueWholeDeviceEject(checkpoint: WholeDeviceEjectCheckpoint)"))
        #expect(service.contains("pending.workbenchOperation?.hasPrefix(\"eject:\") == true"))
        #expect(service.contains("journal.target.images.isEmpty"))
        #expect(service.contains("checkpoint.confirmedPhysicalIdentity"))
        #expect(service.contains("checkpoint.confirmedMemberKey"))
        #expect(service.contains("SectoriumOffTargetDependencyCheck.canFinishOffTarget"))
        #expect(service.contains("coreController.ejectWholeExternalDevice(physicalIdentity:"))
        #expect(service.contains("coreController.returnFromWholeDeviceEject("))
        #expect(service.contains("coreController.ejectWholeExternalDevice(physicalIdentity: physicalIdentity,"))
        #expect(service.contains("checkpoint: acceptedCheckpoint, driver: documentedEjectDriver(driver, physicalIdentity: physicalIdentity),"))
        #expect(protocolSource.contains("persistEjectJournal(journal, state: state, intent: true, phase: \"eject:prepared\","))
        #expect(protocolSource.contains("additionalSuppressedProfileIDs: affectedProfileIDs"))
        #expect(protocolSource.contains("archiveTerminalEjectJournal(journal"))
        #expect(protocolSource.contains("returnBoundaryIsRecoverable"))
        #expect(protocolSource.contains("func returnFromWholeDeviceEject(driver:"))
        #expect(service.contains("Pending eject intent cannot be resumed through the generic workbench recovery route"))
        #expect(workbench.contains("uma.sectorium.continue-eject"))
        #expect(workbench.contains("ForEach(confirmation.affectedMembers"))
        #expect(workbench.contains("confirmation.attachedImageIdentities.count"))
        #expect(workbench.contains("DisclosureGroup(text(\"Latest operation details\", \"最近操作详情\"))"))
        #expect(workbench.contains(".disabled(model.isBusy || (!confirmation.isObservationOnly"))
    }

    @Test("Sectorium sheet owns its close route without adding it to global Settings")
    func sectoriumSheetCloseContract() throws {
        let workbench = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let settings = try source("Sources/CodexUsageUI/Views/HESectoriumSettingsView.swift")
        #expect(workbench.contains(".sheet(isPresented: $showingSettings, onDismiss:"))
        #expect(workbench.contains("restoreSettingsFocus"))
        #expect(settings.contains("if let onClose"))
        #expect(settings.contains("uma.sectorium.settings.close"))
        #expect(settings.contains(".onExitCommand { onClose?() }"))
        #expect(workbench.contains("settingsButtonRef.button = $0"))
    }

    @Test("Global Settings exposes bounded management and explicit storage actions")
    func settingsSurface() throws {
        let settings = try source("Sources/CodexUsageUI/Views/HESectoriumSettingsView.swift")
        let navigation = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        #expect(navigation.contains("case hesectorium = \"HESectorium\""))
        #expect(navigation.contains("case .hesectorium:\n                HESectoriumSettingsView"))
        for action in ["Review safe eject", "Install HESectorium", "Repair HESectorium",
                       "Background loading while AUV is closed", "Refresh Status", "Diagnostics"] {
            #expect(settings.contains(action))
        }
        #expect(settings.contains("model.prepareWholeDeviceEjectConfirmation()"))
        #expect(settings.contains("SectoriumWholeDeviceEjectConfirmationView(model: model"))
        #expect(!settings.contains("action: model.safeEjectHE"))
        #expect(!settings.contains("case \"eject\": model.safeEjectHE()"))
        #expect(settings.contains("uma.settings.hesectorium.operation-result"))
    }

    @Test("Main navigation opens the Sectorium workbench and keeps storage actions off the toolbar")
    func compactEntries() throws {
        let toolbar = try source("Sources/CodexUsageMonitor/App/NativeShellViews.swift")
        let panel = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        #expect(toolbar.contains("case sectorium = \"Sectorium\""))
        #expect(toolbar.contains("SectoriumWorkbenchView("))
        #expect(toolbar.contains("case .sectorium:"))
        #expect(!toolbar.contains("HESectoriumStatusControl("))
        #expect(!panel.contains("HESectoriumStatusControl(isChinese:"))
        for label in ["Scan All", "Refresh All", "Desktop Assistant", "Settings"] {
            #expect(panel.contains("headerButton(localized(\"" + label + "\""))
        }
        let workbench = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(workbench.contains("case .operationInProgress"))
        #expect(workbench.contains("ForEach(parentGroups)"))
        #expect(workbench.contains("ForEach(group.rows)"))
        #expect(workbench.contains("uma.sectorium.local-sampling-consent"))
        #expect(workbench.contains("model.setLocalDeviceSamplingConsent"))
        #expect(!workbench.contains("willSleepNotification"))
        #expect(!workbench.contains("didWakeNotification"))
        #expect(store.contains("willSleepNotification") && store.contains("didWakeNotification"))
        let settings = try source("Sources/CodexUsageUI/Views/HESectoriumSettingsView.swift")
        #expect(settings.contains("model.activateSettings()") && settings.contains("model.deactivateSettings()"))
        #expect(!settings.contains(".onAppear { model.refresh() }"))
        #expect(store.contains("pendingOperation: pending"))
        #expect(store.contains("sampleSelectedDeviceIO"))
        #expect(store.contains("device.isExternal || localSamplingConsentDeviceIDs.contains(selectedID)"))
        #expect(store.contains("deviceProfiles.count == 1"))
        #expect(store.contains("let readiness = Self.observedReadiness"))
        #expect(store.contains("service.profileReadiness(profileID: profile.id)"))
        #expect(store.contains("service.refreshStatus(observedReadiness: readiness)"))
        #expect(!settingsOrShellStartsStorageAction(toolbar))
    }

    @Test("Unknown ownership is unassigned and stale attachment hides storage entry actions")
    func physicalSelectionAndStaleActionContract() throws {
        let view = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(view.contains("model.workbench.devices.filter { $0.isVirtual == false }"))
        #expect(view.contains("$0.isVirtual == nil || $0.hasAmbiguousPhysicalStores"))
        #expect(view.contains("uma.sectorium.unassigned-device"))
        #expect(view.contains("uma.sectorium.registry-unavailable"))
        #expect(view.contains("group.rows.isEmpty && !model.registryUnavailable"),
                "A failed registry read must not display an empty-registry claim or endless checking")
        #expect(store.contains("workbench.devices.first { $0.id == id && $0.isVirtual == false }"))
        #expect(view.contains("guard !input.stale"))
        for identifier in ["uma.sectorium.create", "uma.sectorium.volume-primary.", "uma.sectorium.volume-more."] {
            #expect(view.contains(identifier))
        }
        #expect(view.contains("ForEach(group.rows)"))
        #expect(view.contains("model.volumeRows.filter { $0.parentDeviceID == device.id }"))
        #expect(view.contains("SectoriumLegacyPresentationPolicy.currentLegacyState("))
        #expect(view.contains("presentationLegacy?.state == .mounted"))
    }

    @Test("Per-volume actions bind explicit profile IDs through Store instead of a shared selection")
    func explicitVolumeRoutes() throws {
        let view = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        for route in ["model.loadDevelopmentDisk(profileID: row.id)",
                      "model.prepareUnloadOnlyConfirmation(profileID: row.id)",
                      "model.prepareSafeUnloadAndEject(profileID: row.id)",
                      "model.updateDevelopmentDisk(profileID: row.id,",
                      "model.createDevelopmentDisk(request: request)"] {
            #expect(view.contains(route))
        }
        for route in ["func loadDevelopmentDisk(profileID:", "func prepareUnloadOnlyConfirmation(profileID:",
                      "func prepareSafeUnloadAndEject(profileID:", "func updateDevelopmentDisk(profileID:",
                      "func createDevelopmentDisk(request:"] {
            #expect(store.contains(route))
        }
        #expect(view.contains("disconnectEnabled: verifiedLoaded == true && isExternal ?"))
        #expect(view.contains("case nil:"))
        #expect(view.contains("model.verifiedHistoryDocument(profileID: profileID)"))
    }

    @Test("Runtime UI actions are asynchronous and guarded against repeat clicks")
    func asynchronousActions() throws {
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(store.contains("Task.detached(priority: .userInitiated)"))
        #expect(store.components(separatedBy: "guard !isBusy, !isPreviewFixture else { return }").count >= 4)
    }

    @Test("Settings keeps preference, observed service, operation, and readiness separate")
    func observedAutomationState() throws {
        let settings = try source("Sources/CodexUsageUI/Views/HESectoriumSettingsView.swift")
        let runtime = try source("Sources/HESectoriumRuntime/HESectoriumService.swift")
        #expect(settings.contains("Background loading preference"))
        #expect(settings.contains("Background service"))
        #expect(settings.contains("While AUV is open, each volume follows its own automatic-loading setting."))
        #expect(settings.contains("Storage readiness"))
        #expect(settings.contains("Operation"))
        #expect(settings.contains("case .loaded"))
        #expect(settings.contains("case .notLoaded"))
        #expect(settings.contains("case .unknown"))
        #expect(runtime.contains("agentStatusProvider.loadStatus(label:"))
        #expect(runtime.contains("agentLoadStatus: HESectoriumAgentLoadStatus = .unknown"))
        #expect(runtime.contains("SMJobCopyDictionary"))
        #expect(runtime.contains("UnknownAgentStatusProvider"))
    }

    @Test("Failed post-operation observation stays unknown and eject confirms a fresh target")
    func postOperationObservationAndEjectWarning() throws {
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        let workbench = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        #expect(store.contains("Self.parentPresence(profile: profile, devices: devices) == false"))
        #expect(store.contains("SectoriumCommandAction.disconnect.isVerified(by: completion.result, pending: pending)"))
        #expect(store.contains("(absent || verifiedEjectDeviceID == completion.ejectTarget)"))
        #expect(store.contains("operationSteps: completion.result.steps, safeToUnplug: safe"))
        #expect(store.contains("_ = service.reconcileWholeDeviceEjectRecovery()"))
        #expect(workbench.contains("This check alone does not guarantee that the drive is safe to disconnect"))
        #expect(workbench.contains("model.confirmWholeDeviceEject()"))
        #expect(store.contains("ejectExternalDevice(physicalIdentity: confirmation.physicalIdentity,"))
        #expect(workbench.contains("confirmation.affectedMembers.count"))
    }

    @MainActor
    @Test("Two stores sharing one service cannot accept the other window's eject target")
    func independentStoreEjectTargetBinding() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sectorium-ui-eject-binding-\(UUID().uuidString)")
        let service = HESectoriumService(paths: HESectoriumPaths(root: fixtureRoot),
            runner: SectoriumEjectBindingFixtureRunner(), identityPolicy: .expected)
        let firstID = "C4FAE746-5724-4B1B-8F4B-C6D5EFB73001"
        let secondID = "C4FAE746-5724-4B1B-8F4B-C6D5EFB73002"
        func device(_ id: String, _ bsd: String, _ name: String) -> SectoriumPhysicalDevice {
            .init(id: id, bsdName: bsd, name: name, isExternal: true,
                  identityVerified: true, wholeDeviceBytes: nil, mountedVolumePaths: [],
                  volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
                  topologyComplete: true, isVirtual: false)
        }
        func confirmation(_ id: String, _ bsd: String) -> SectoriumWholeDeviceEjectConfirmation {
            .init(topology: .init(physicalIdentity: id, bsdName: bsd, isWholeDevice: true,
                isExternal: true, isSystemDevice: false, inventoryComplete: true,
                volumes: [.init(identity: "member-\(id)", mounted: true)], images: []),
                dependenciesCanFinishOffTarget: true)
        }
        let settingsStore = HESectoriumStore(service: service)
        let sectoriumStore = HESectoriumStore(service: service)
        settingsStore.apply(devices: [device(firstID, "disk81", "A")], profiles: [],
            readiness: .connected, pending: nil)
        sectoriumStore.apply(devices: [device(secondID, "disk82", "B")], profiles: [],
            readiness: .connected, pending: nil)
        let first = confirmation(firstID, "disk81")
        let second = confirmation(secondID, "disk82")
        #expect(settingsStore.workbench.selectedDeviceID == firstID)
        #expect(sectoriumStore.workbench.selectedDeviceID == secondID)
        #expect(settingsStore.acceptsWholeDeviceEjectConfirmation(first, requestedDeviceID: firstID))
        #expect(!settingsStore.acceptsWholeDeviceEjectConfirmation(second, requestedDeviceID: firstID))
        #expect(sectoriumStore.acceptsWholeDeviceEjectConfirmation(second, requestedDeviceID: secondID))
        #expect(!sectoriumStore.acceptsWholeDeviceEjectConfirmation(first, requestedDeviceID: secondID))
        let reopenedStore = HESectoriumStore(service: service)
        reopenedStore.apply(devices: [], profiles: [], readiness: .ejected,
            pending: "eject:pending", pendingEjectTargetID: firstID)
        #expect(reopenedStore.workbench.selectedDeviceID == firstID,
                "A pending eject target remains available for read-only absence recovery after restart")
        let storeSource = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(storeSource.contains("prepareWholeDeviceEjectConfirmation(physicalIdentity: selectedID)"))
    }

    @MainActor
    @Test("Pending eject recovery remains bound to absent A while another physical drive B is selected")
    func pendingEjectTargetSurvivesOtherDriveSelection() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sectorium-ui-pending-target-\(UUID().uuidString)")
        let service = HESectoriumService(paths: HESectoriumPaths(root: fixtureRoot),
            runner: SectoriumEjectBindingFixtureRunner(), identityPolicy: .expected)
        let targetA = "D2CEB910-B4D2-4C0F-9694-D7C2001B1001"
        let selectedB = "D2CEB910-B4D2-4C0F-9694-D7C2001B1002"
        let deviceB = SectoriumPhysicalDevice(id: selectedB, bsdName: "disk82", name: "B",
            isExternal: true, identityVerified: true, wholeDeviceBytes: nil,
            mountedVolumePaths: [], volumeUUIDs: [], readBytes: nil, writtenBytes: nil,
            topologyComplete: true, isVirtual: false)
        let store = HESectoriumStore(service: service)
        store.apply(devices: [deviceB], profiles: [], readiness: .connected, pending: nil)
        #expect(store.workbench.selectedDeviceID == selectedB)

        // The same state occurs after selecting B while A's journal remains pending.
        store.apply(devices: [deviceB], profiles: [], readiness: .operationInProgress("eject:pending"),
            pending: "eject:pending", pendingEjectTargetID: targetA)
        #expect(store.workbench.selectedDeviceID == selectedB)
        #expect(store.pendingWholeDeviceEjectTargetID == targetA)
        #expect(HESectoriumStore.ejectRecoveryTarget(selectedDeviceID: selectedB,
            pendingOperation: "eject:pending", pendingEjectTargetID: targetA) == targetA)
        #expect(HESectoriumStore.ejectRecoveryTarget(selectedDeviceID: selectedB,
            pendingOperation: "eject:pending", pendingEjectTargetID: nil) == nil,
            "An invalid journal must not redirect recovery to B")
        var availabilityQueries: [String] = []
        let availability = HESectoriumStore.ejectRecoveryAvailability(
            selectedDeviceID: selectedB, pendingOperation: "eject:pending",
            pendingEjectTargetID: targetA,
            canContinue: { availabilityQueries.append($0); return $0 == targetA },
            canReturn: { availabilityQueries.append($0); return $0 == targetA })
        #expect(availability.canContinue && availability.canReturn)
        #expect(availabilityQueries == [targetA, targetA],
            "Refresh must query A's journal even when B remains selected")
        let topologyA = WholeDeviceTopology(physicalIdentity: targetA, bsdName: "disk81",
            isWholeDevice: true, isExternal: true, isSystemDevice: false, inventoryComplete: true,
            volumes: [.init(identity: "member-A", mounted: true)], images: [])
        let continuationA = SectoriumWholeDeviceEjectConfirmation(topology: topologyA,
            dependenciesCanFinishOffTarget: true, isContinuation: true)
        #expect(store.acceptsWholeDeviceEjectConfirmation(continuationA, requestedDeviceID: targetA))
        #expect(!store.acceptsWholeDeviceEjectConfirmation(continuationA, requestedDeviceID: selectedB))
        let selectedAfterPending = HESectoriumStore(service: service)
        selectedAfterPending.apply(devices: [], profiles: [], readiness: .ejected,
            pending: "eject:pending", pendingEjectTargetID: targetA)
        #expect(selectedAfterPending.workbench.selectedDeviceID == targetA)
        selectedAfterPending.apply(devices: [deviceB], profiles: [], readiness: .connected,
            pending: "eject:pending", pendingEjectTargetID: targetA)
        selectedAfterPending.selectDevice(selectedB)
        #expect(selectedAfterPending.workbench.selectedDeviceID == selectedB)
        #expect(selectedAfterPending.pendingWholeDeviceEjectTargetID == targetA)
        #expect(selectedAfterPending.acceptsWholeDeviceEjectConfirmation(
            continuationA, requestedDeviceID: targetA))
        let plan = SectoriumWorkbenchActionPlan.make(.init(hasDrive: true, identityVerified: true,
            external: true, stale: false, inventoryAvailable: true, busy: false,
            readiness: .operationInProgress("eject:pending"), hasProfile: false,
            profileFormatVerified: true, legacyState: .none, pendingOperation: "eject:pending",
            canBeginEject: false, canContinueEject: availability.canContinue,
            canReturnFromEject: availability.canReturn))
        #expect(plan.primary == .continueEject)
        #expect(plan.recovery.contains(.returnToDevelopment))
        let storeSource = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        let viewSource = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let settingsSource = try source("Sources/CodexUsageUI/Views/HESectoriumSettingsView.swift")
        #expect(storeSource.contains("prepareContinueWholeDeviceEjectConfirmation(physicalIdentity: recoveryID)"))
        #expect(storeSource.contains("returnToDevelopment(physicalIdentity: recoveryID)"))
        #expect(viewSource.contains("uma.sectorium.pending-eject-target"))
        #expect(viewSource.contains("$0.id == confirmation.physicalIdentity"))
        #expect(settingsSource.contains("selectedDeviceName: confirmedEjectDeviceName"))
        #expect(settingsSource.contains("$0.id == targetID && $0.isVirtual == false"))
    }

    @Test("Settings recovery remains bound to pending A instead of selected B")
    func settingsPendingEjectRoute() throws {
        let targetA = "pending-physical-A"
        let selectedB = "selected-physical-B"
        let both = HESectoriumSettingsEjectPlan.make(
            pendingOperation: "eject:pending", pendingTargetID: targetA,
            selectedExternalDeviceID: selectedB, inventoryState: .available,
            canBegin: true, canContinue: true, canReturn: true)
        #expect(both.isPending && both.targetID == targetA)
        #expect(!both.canBegin && both.canContinue && both.canReturn,
                "A owns the operation slot; Settings must not offer B's new eject")

        let absent = HESectoriumSettingsEjectPlan.make(
            pendingOperation: "eject:pending", pendingTargetID: targetA,
            selectedExternalDeviceID: nil, inventoryState: .empty,
            canBegin: false, canContinue: true, canReturn: false)
        #expect(absent.isPending && absent.targetID == targetA)
        #expect(absent.canContinue && !absent.canBegin && !absent.canReturn,
                "A's read-only continuation must not require a selected drive")

        let returnOnly = HESectoriumSettingsEjectPlan.make(
            pendingOperation: "eject:pending", pendingTargetID: targetA,
            selectedExternalDeviceID: selectedB, inventoryState: .available,
            canBegin: true, canContinue: false, canReturn: true)
        #expect(returnOnly.isPending && returnOnly.targetID == targetA)
        #expect(!returnOnly.canBegin && !returnOnly.canContinue && returnOnly.canReturn,
                "Return-only A cannot fall through to B's eject preview")

        let invalidJournal = HESectoriumSettingsEjectPlan.make(
            pendingOperation: "eject:pending", pendingTargetID: nil,
            selectedExternalDeviceID: selectedB, inventoryState: .available,
            canBegin: true, canContinue: true, canReturn: true)
        #expect(invalidJournal.isPending && invalidJournal.targetID == nil)
        #expect(!invalidJournal.canBegin && !invalidJournal.canContinue && !invalidJournal.canReturn)

        let ordinary = HESectoriumSettingsEjectPlan.make(
            pendingOperation: nil, pendingTargetID: nil,
            selectedExternalDeviceID: selectedB, inventoryState: .available,
            canBegin: true, canContinue: false, canReturn: false)
        #expect(!ordinary.isPending && ordinary.canBegin)

        let settings = try source("Sources/CodexUsageUI/Views/HESectoriumSettingsView.swift")
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(settings.contains("Pending safe eject target"))
        #expect(settings.contains("action: model.prepareContinueWholeDeviceEjectConfirmation"))
        #expect(settings.contains("action: model.returnToDevelopment"))
        #expect(settings.contains("case \"return-eject\": model.returnToDevelopment()"))
        #expect(store.contains("guard !isBusy, !isPreviewFixture, workbench.pendingOperation == nil,"))
        #expect(store.contains("let canBeginEject = pending == nil"))
    }

    @Test("Action CLI propagates unsuccessful results as nonzero process exits")
    func actionExitPropagation() throws {
        let cli = try source("Sources/HESectoriumControl/main.swift")
        let dispatcher = try source("Sources/HESectoriumCLI/CommandDispatcher.swift")
        #expect(cli.contains("HESectoriumCommandDispatcher.run("))
        #expect(dispatcher.contains("case \"mount\": return report(service.mountDEV()"))
        #expect(dispatcher.contains("case \"eject\": return report(service.safeEjectHE()"))
        #expect(dispatcher.contains("return result.succeeded ? 0 : 1"))
        #expect(dispatcher.contains("writeStderr(\"Sectorium: operation did not complete."))
        #expect(dispatcher.contains("return code == 0 && !value.succeeded ? 1 : code"))
    }

    @Test("Blocking processes group by resolved app while retaining every PID")
    func blockingApplicationGrouping() {
        let processes = (1...17).map { index in
            SectoriumActivityProcess(processID: Int32(index), command: index == 1 ? "ChatGPT" : "node",
                bundleIdentifier: "com.example.chatgpt", applicationName: "ChatGPT",
                references: [.init(descriptor: "cwd", path: "/fixture/dev")])
        }
        let groups = SectoriumBlockingApplicationGroup.make(processes)
        #expect(groups.count == 1)
        #expect(groups.first?.name == "ChatGPT")
        #expect(groups.first?.processes.map(\.processID) == (1...17).map(Int32.init))

        let distinct = SectoriumBlockingApplicationGroup.make(processes + [
            .init(processID: 30, command: "ChatGPT", bundleIdentifier: "com.other.app", applicationName: "ChatGPT"),
            .init(processID: 31, command: "node"),
            .init(processID: 32, command: "node")])
        #expect(distinct.count == 3, "Same display names must not merge different resolved app identities")
        #expect(distinct.first { $0.id == "command:node" }?.processes.count == 2)
        #expect(distinct.reduce(0) { $0 + $1.processes.count } == 20)
        #expect(SectoriumBlockingApplicationGroup.make([]).isEmpty)
    }

    @Test("Compact redesign retains keyboard actions and folds technical detail")
    func compactPresentationContract() throws {
        let view = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        #expect(view.contains("SectoriumBlockingApplicationGroup.make(check.processes)"))
        #expect(view.contains("DisclosureGroup(text(\"Process details\", \"进程详情\"))"))
        #expect(view.contains("model.quitBlockingApplicationsAndRetry()"))
        #expect(view.contains("model.cancelSafetyCheck()"))
        #expect(view.contains("button.focusRingType = .exterior"))
        #expect(view.contains("Unload keeps the drive connected. Disconnect ejects the entire drive."))
        #expect(view.contains("uma.sectorium.parent-options."))
        #expect(!view.contains(".frame(maxWidth: 220)"), "Daily actions must not stretch into button walls")
    }

    private func settingsOrShellStartsStorageAction(_ source: String) -> Bool {
        source.contains(".onAppear { HESectoriumService.shared.mountDEV() }")
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
