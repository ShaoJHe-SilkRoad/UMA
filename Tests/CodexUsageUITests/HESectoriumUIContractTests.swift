import Foundation
import Testing
import HESectoriumRuntime
@testable import CodexUsageUI

@Suite("HESectorium integration UI contract")
struct HESectoriumUIContractTests {
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
        #expect(mountedLegacy.primary == .adopt)
        #expect(mountedLegacy.secondary == [.eject])

        let detachedLegacy = SectoriumWorkbenchActionPlan.make(input(.notStarted, legacy: .detached))
        #expect(detachedLegacy.primary == .adopt)
        #expect(!detachedLegacy.secondary.contains(.create))

        let ready = SectoriumWorkbenchActionPlan.make(input(.ready, profile: true, beginEject: true))
        #expect(ready.primary == .stop)
        #expect(ready.secondary == [.create, .eject])

        let stopped = SectoriumWorkbenchActionPlan.make(input(.notStarted, profile: true))
        #expect(stopped.primary == .start)
        #expect(!stopped.secondary.contains(.adopt))

        let noImage = SectoriumWorkbenchActionPlan.make(input(.noDevelopmentDisk))
        #expect(noImage.primary == .create)
        #expect(noImage.secondary == [.adopt])

        let localDrive = SectoriumWorkbenchActionPlan.make(input(.noDevelopmentDisk, external: false, beginEject: true))
        #expect(localDrive.primary == .create)
        #expect(!localDrive.secondary.contains(.eject))

        let unavailableIdentity = SectoriumWorkbenchActionPlan.make(input(identity: false, beginEject: true))
        #expect(unavailableIdentity.primary == nil && unavailableIdentity.secondary.isEmpty)
        #expect(unavailableIdentity.unavailableReason == .identityUnavailable)

        let busy = SectoriumWorkbenchActionPlan.make(input(.busy, profile: true, beginEject: true))
        #expect(busy.primary == nil && busy.secondary.isEmpty && busy.unavailableReason == .busy)

        let stale = SectoriumWorkbenchActionPlan.make(input(stale: true))
        #expect(stale.primary == nil && stale.secondary.isEmpty && stale.unavailableReason == .stale)

        let unknown = SectoriumWorkbenchActionPlan.make(input(.unknown("identity unavailable"), profile: true, beginEject: true))
        #expect(unknown.primary == nil && unknown.secondary.isEmpty)

        let genericRecovery = SectoriumWorkbenchActionPlan.make(input(.operationInProgress("start:pending"),
            pending: "start:pending"))
        #expect(genericRecovery.recovery == [.resume])

        let ejectRecovery = SectoriumWorkbenchActionPlan.make(input(.operationInProgress("eject:pending"),
            pending: "eject:pending", continueEject: true, returnFromEject: true))
        #expect(ejectRecovery.primary == .continueEject)
        #expect(ejectRecovery.recovery == [.continueEject, .returnToDevelopment])
        #expect(ejectRecovery.secondary.isEmpty)

        let uncertainLegacy = SectoriumWorkbenchActionPlan.make(input(.unknown("partial inventory"), legacy: .unknown))
        #expect(uncertainLegacy.primary == nil && uncertainLegacy.secondary.isEmpty)
        #expect(uncertainLegacy.unavailableReason == .stateUnknown)

        let partialWithoutRecovery = SectoriumWorkbenchActionPlan.make(input(.partialFailure("incomplete stop")))
        #expect(partialWithoutRecovery.primary == nil && partialWithoutRecovery.secondary.isEmpty)
        #expect(partialWithoutRecovery.unavailableReason == .stateUnknown)
        let partialWithRecovery = SectoriumWorkbenchActionPlan.make(input(.partialFailure("interrupted start"),
            pending: "start:interrupted"))
        #expect(partialWithRecovery.recovery == [.resume])

        let busyRecovery = SectoriumWorkbenchActionPlan.make(input(.busy, busy: true, pending: "start:interrupted"))
        #expect(busyRecovery.recovery.isEmpty && busyRecovery.unavailableReason == .busy)

        let unavailableEjectRecovery = SectoriumWorkbenchActionPlan.make(input(
            .operationInProgress("eject:pending"), pending: "eject:pending"))
        #expect(unavailableEjectRecovery.recovery.isEmpty)
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
                #expect(blocked.1.secondary == [.eject], "A separately verified read-only external target may retain gated safe Eject.")
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
        #expect(unknownLegacy.1.primary == nil && unknownLegacy.1.secondary.isEmpty,
                "Unknown legacy state must remain blocking rather than becoming create/adopt success.")
    }

    @Test("Stop requires a fresh identity-bound checkpoint and deliberate UI confirmation")
    func stopConfirmationContract() throws {
        let service = try source("Sources/HESectoriumRuntime/HESectoriumService.swift")
        let runtime = try source("Sources/HESectoriumRuntime/SectoriumWorkbenchRuntime.swift")
        let view = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        let start = try #require(service.range(of: "public func stopDevelopmentDisk(checkpoint:"))
        let stopBody = String(service[start.lowerBound...])
        #expect(service.contains("public func prepareStopDevelopmentDiskConfirmation()"))
        #expect(runtime.contains("public struct SectoriumStopConfirmation"))
        #expect(stopBody.contains("checkpoint.permits(profile, observation"))
        #expect(!stopBody.prefix(5000).contains("assessOccupancy"))
        #expect(view.contains("uma.sectorium.stop-known-writers-closed"))
        #expect(view.contains("uma.sectorium.stop-confirm"))
        #expect(store.contains("stopDevelopmentDisk(knownWritersClosed:"))
    }

    @Test("Create input validates bounded capacity before conversion and interpolates recommendation")
    func capacityInputContract() throws {
        let view = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let action = try #require(view.range(of: "private func createDevelopmentDisk()"))
        let createSource = String(view[action.lowerBound...])
        #expect(createSource.contains("SectoriumCapacityInput.requestedBytes(gib: capacityGiB)"))
        #expect(createSource.contains("\\(recommendedGiB) GiB"))
        #expect(!createSource.contains("Use (recommendedGiB) GiB, 80%"))
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
        #expect(service.contains("coreController.returnFromWholeDeviceEject(driver: driver)"))
        #expect(protocolSource.contains("persistEjectJournal(journal, state: state, intent: true, phase: \"eject:prepared\")"))
        #expect(protocolSource.contains("returnBoundaryIsRecoverable"))
        #expect(protocolSource.contains("func returnFromWholeDeviceEject(driver:"))
        #expect(service.contains("Pending eject intent cannot be resumed through the generic workbench recovery route"))
        #expect(workbench.contains("case .eject: model.prepareWholeDeviceEjectConfirmation()"))
        #expect(workbench.contains("uma.sectorium.continue-eject"))
        #expect(workbench.contains("confirmation.isContinuation"))
        #expect(workbench.contains("ForEach(confirmation.affectedMembers"))
        #expect(workbench.contains("Physical drive: \\(selectedDevice?.name"))
        #expect(workbench.contains("Technical identifiers"))
        #expect(workbench.contains("confirmation.attachedImageIdentities.count"))
        #expect(workbench.contains("ForEach(confirmation.attachedImageIdentities"))
        #expect(workbench.contains("Text(operationSummary).accessibilityIdentifier(\"uma.sectorium.operation-summary\")"))
        #expect(workbench.contains("DisclosureGroup(text(\"Operation details\", \"操作详情\"))"))
        #expect(workbench.contains("其余操作尚未验证；请保持硬盘连接。"))
        #expect(workbench.contains("canContinueEject: model.canContinueWholeDeviceEject"))
        #expect(workbench.contains("canReturnFromEject: model.canReturnFromWholeDeviceEject"))
        #expect(workbench.contains("canBeginEject: model.canBeginWholeDeviceEject"))
        #expect(workbench.contains("uma.sectorium.eject-known-writers-closed"))
        #expect(workbench.contains(".disabled(!knownWritersClosed || !confirmation.dependenciesCanFinishOffTarget"))
        #expect(store.contains("confirmation.checkpoint(knownWritersClosed: knownWritersClosed)"))
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
        for action in ["Mount DEV", "Safe Eject HE", "Install HESectorium", "Repair HESectorium",
                       "Enable mount automation", "Refresh Status", "Diagnostics"] {
            #expect(settings.contains(action))
        }
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
        #expect(panel.contains("HESectoriumStatusControl(isChinese:"))
        let workbench = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(workbench.contains("pendingOperation: model.workbench.pendingOperation"))
        #expect(workbench.contains("case .operationInProgress"))
        #expect(workbench.contains("selectedDeviceProfiles.count > 1"))
        #expect(workbench.contains("model.selectProfile"))
        #expect(workbench.contains("uma.sectorium.local-sampling-consent"))
        #expect(workbench.contains("model.setLocalDeviceSamplingConsent"))
        #expect(workbench.contains("willSleepNotification"))
        #expect(workbench.contains("didWakeNotification"))
        #expect(store.contains("pendingOperation: pending"))
        #expect(store.contains("sampleSelectedDeviceIO"))
        #expect(store.contains("device.isExternal || localSamplingConsentDeviceIDs.contains(selectedID)"))
        #expect(store.contains("deviceProfiles.count == 1"))
        #expect(store.contains("service.sectoriumReadiness"))
        #expect(!settingsOrShellStartsStorageAction(toolbar))
    }

    @Test("Unknown ownership is unassigned and stale attachment hides storage entry actions")
    func physicalSelectionAndStaleActionContract() throws {
        let view = try source("Sources/CodexUsageUI/Views/SectoriumWorkbenchView.swift")
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(view.contains("model.workbench.devices.filter { $0.isVirtual == false }"))
        #expect(view.contains("$0.isVirtual == nil || $0.hasAmbiguousPhysicalStores"))
        #expect(view.contains("uma.sectorium.unassigned-device"))
        #expect(store.contains("workbench.devices.first { $0.id == id && $0.isVirtual == false }"))
        #expect(view.contains("stale: staleAttachment"))
        #expect(view.contains("guard !input.stale"))
        for identifier in ["uma.sectorium.create", "uma.sectorium.adopt",
                           "uma.sectorium.start", "uma.sectorium.stop", "uma.sectorium.eject-drive"] {
            #expect(view.contains("\"\(identifier)\""))
        }
        #expect(view.contains("ForEach(selectedDeviceProfiles)"))
        #expect(view.contains("SectoriumLegacyPresentationPolicy.currentLegacyState("))
        #expect(view.contains("presentationLegacy?.state == .mounted"))
    }

    @Test("Runtime UI actions are asynchronous and guarded against repeat clicks")
    func asynchronousActions() throws {
        let store = try source("Sources/CodexUsageUI/Stores/HESectoriumStore.swift")
        #expect(store.contains("Task.detached(priority: .userInitiated)"))
        #expect(store.components(separatedBy: "guard !isBusy else { return }").count >= 4)
    }

    @Test("Settings keeps preference, observed service, operation, and readiness separate")
    func observedAutomationState() throws {
        let settings = try source("Sources/CodexUsageUI/Views/HESectoriumSettingsView.swift")
        let runtime = try source("Sources/HESectoriumRuntime/HESectoriumService.swift")
        #expect(settings.contains("Automation preference"))
        #expect(settings.contains("Automation service"))
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

    @Test("Action CLI propagates unsuccessful results as nonzero process exits")
    func actionExitPropagation() throws {
        let cli = try source("Sources/HESectoriumControl/main.swift")
        let dispatcher = try source("Sources/HESectoriumCLI/CommandDispatcher.swift")
        #expect(cli.contains("HESectoriumCommandDispatcher.run("))
        #expect(dispatcher.contains("case \"mount\": return report(service.mountDEV()"))
        #expect(dispatcher.contains("case \"eject\": return report(service.safeEjectHE()"))
        #expect(dispatcher.contains("return result.succeeded ? 0 : 1"))
        #expect(dispatcher.contains("return code == 0 && !value.succeeded ? 1 : code"))
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
