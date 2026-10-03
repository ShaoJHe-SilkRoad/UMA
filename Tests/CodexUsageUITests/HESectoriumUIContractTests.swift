import Foundation
import Testing

@Suite("HESectorium integration UI contract")
struct HESectoriumUIContractTests {
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

    @Test("Daily status actions appear in both the main toolbar and Quick Panel")
    func compactEntries() throws {
        let toolbar = try source("Sources/CodexUsageMonitor/App/NativeShellViews.swift")
        let panel = try source("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        #expect(toolbar.contains("HESectoriumStatusControl(isChinese:"))
        #expect(panel.contains("HESectoriumStatusControl(isChinese:"))
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
