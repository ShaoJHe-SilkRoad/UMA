import AppKit
import SwiftUI
import Foundation
import CodexUsageUI
import HESectoriumCore
import HESectoriumRuntime

/// Explicit opt-in validation mode. The normal application composition is unchanged.
@MainActor enum ReleasePreview {
    static func run(application: NSApplication) {
        let chinese = CommandLine.arguments.contains("--preview-zh")
        let language: AppLanguage = chinese ? .simplifiedChinese : .english
        let preferences = ApplicationPreferences.inMemory()
        preferences.set(language.rawValue, for: UMAApplicationPreferenceKeys.language)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("auv-release-preview-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = HESectoriumPaths(root: root.appendingPathComponent("storage"))
        let service = HESectoriumService(paths: paths, backend: PreviewStorage(),
            operationLock: PreviewLock(), installer: HESectoriumInstaller(paths: paths, home: root),
            runner: PreviewCommands(), identityPolicy: .expected,
            agentStatusProvider: UnknownAgentStatusProvider(), sectoriumDeviceObserver: PreviewDevices())
        let storage = HESectoriumStore(service: service)
        let navigation = MainSurfaceNavigationState()
        let view = MainWindowRootView(store: UsageStore.preview(language: language), navigation: navigation,
            openSettings: {}, scanAll: {}, refreshAll: {}, connectCodex: {}, disconnectCodex: {},
            claudeControlState: { .onlineVerificationUnavailable }, connectClaude: {}, accuracySyncClaude: {},
            hesectoriumStore: storage, promptPreferences: preferences)
        let size = CommandLine.arguments.contains("--preview-minimum") ? NSSize(width:760,height:488) : NSSize(width:1040,height:760)
        let window = NSWindow(contentRect:NSRect(origin:.zero,size:size), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered,defer:false)
        window.title = "AUV 0.15.1 — isolated preview (sample data)"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width:760,height:488)
        window.contentViewController = NSHostingController(rootView:view)
        window.appearance = NSAppearance(named:CommandLine.arguments.contains("--preview-light") ? .aqua : .darkAqua)
        application.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Isolated Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.mainMenu = menu
        window.center(); window.makeKeyAndOrderFront(nil); application.activate(ignoringOtherApps:true)
        print("RELEASE_PREVIEW_READY: production views; in-memory preferences; synthetic usage; no providers; storage commands denied")
        withExtendedLifetime((window,storage,navigation)) { application.run() }
    }
}
private final class PreviewCommands: HESectoriumCommandRunning {
    func run(_ executable:String,_ arguments:[String],cwd:URL)->CommandOutcome { .init(exitCode:97,detail:"Isolated preview: host commands disabled") }
}
private final class PreviewDevices: SectoriumDeviceObserving { func observeDevices() throws -> [SectoriumPhysicalDevice] { [] } }
private final class PreviewLock: OperationLock { func acquire()->Bool { true }; func release() {} }
private final class PreviewStorage: StorageBackend {
    func observeOuter()->VolumeIdentity? { nil }
    func observe()->StorageObservation? { nil }
    func attachImage()->CommandOutcome { .init(exitCode:97,detail:"Isolated preview: attach disabled") }
    func assessOccupancy(scope:OccupancyScope)->OccupancyAssessment { .incomplete(reason:"Isolated preview") }
    func perform(_ step:EjectStep)->CommandOutcome { .init(exitCode:97,detail:"Isolated preview: eject disabled") }
    func finalOuterState()->FinalOuterState { .unknown("Isolated preview") }
}
