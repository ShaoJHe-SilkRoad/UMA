import Foundation
import Testing

@Suite("HESectorium integration UI contract")
struct HESectoriumUIContractTests {
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
        #expect(workbench.contains("action: model.prepareWholeDeviceEjectConfirmation"))
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
        #expect(workbench.contains("isEnabled: model.canContinueWholeDeviceEject && model.inventoryState == .available && !model.isBusy"))
        #expect(workbench.contains("isEnabled: model.canReturnFromWholeDeviceEject && model.inventoryState == .available && !model.isBusy"))
        #expect(workbench.contains("isEnabled: model.canBeginWholeDeviceEject && selectedDevice?.isExternal == true"))
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
        #expect(workbench.contains("model.workbench.pendingOperation.map { !$0.hasPrefix(\"eject:\") } == true"))
        #expect(workbench.contains("case .operationInProgress"))
        #expect(workbench.contains("selectedDeviceProfiles.count > 1"))
        #expect(workbench.contains("model.selectProfile"))
        #expect(workbench.contains("private var storageMutationBlocked"))
        #expect(workbench.contains("model.workbench.pendingOperation != nil"))
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
