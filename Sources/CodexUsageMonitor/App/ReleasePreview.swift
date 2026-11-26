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
        // --preview-look=wabiSabi|brutalist shows an appearance pack.
        if let value = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-look=") })?
            .dropFirst("--preview-look=".count),
           let look = AUVLook(rawValue: String(value)) {
            AUVLookState.shared.apply(look)
        }
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
        if CommandLine.arguments.contains("--preview-agent=claude") { navigation.selectedAgent = .claude }
        // --preview-destination=threados|sectorium opens that workspace.
        if CommandLine.arguments.contains("--preview-destination=threados") { navigation.destination = .threadOS }
        if CommandLine.arguments.contains("--preview-destination=sectorium") { navigation.destination = .sectorium }
        let store = UsageStore.preview(scenario: .ready, language: language,
                                       presentationCards: sampleCards(language: language))
        let view = MainWindowRootView(store: store, navigation: navigation,
            openSettings: {}, scanAll: {}, refreshAll: {}, connectCodex: {}, disconnectCodex: {},
            claudeControlState: { .onlineVerificationUnavailable }, connectClaude: {}, accuracySyncClaude: {},
            hesectoriumStore: storage, promptPreferences: preferences)
        // --preview-window=settings shows Global Settings instead of the main window.
        let showsSettings = CommandLine.arguments.contains("--preview-window=settings")
        preferences.set(AUVLook.current.rawValue, for: UMAApplicationPreferenceKeys.look)
        let size = showsSettings ? NSSize(width:640,height:460)
            : (CommandLine.arguments.contains("--preview-minimum") ? NSSize(width:760,height:488)
               : (CommandLine.arguments.contains("--preview-compact") ? NSSize(width:880,height:600) : NSSize(width:1040,height:760)))
        let window = PreviewWindow(contentRect:NSRect(origin:.zero,size:size), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered,defer:false)
        window.drawsAsActive = CommandLine.arguments.contains(where: { $0.hasPrefix("--preview-snapshot=") })
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Dev"
        window.title = "AUV \(version) — isolated preview (sample data)"
        window.isReleasedWhenClosed = false
        // As the shipped main window: the bar beside the traffic lights.
        AUVWindowChrome.unify(window)
        if showsSettings {
            let settings = AUVWindowChrome.adopt(NSHostingController(rootView: SettingsWindowRootView(
                preferences: preferences, store: store, navigation: GlobalSettingsNavigationState(),
                // Isolated: a throwaway support folder and home, never the user's.
                dataPaths: .current(bundleIdentifier: "auv.release-preview",
                                    applicationSupportDirectory: root.appendingPathComponent("support"),
                                    homeDirectory: root))))
            settings.sizingOptions = []
            window.contentViewController = settings
            window.setContentSize(size)
        } else {
            window.contentMinSize = NSSize(width:760,height:488)
            // Keep the asked size: the hosting controller would otherwise
            // shrink the window to its minimum.
            let main = AUVWindowChrome.adopt(NSHostingController(rootView:view))
            main.sizingOptions = []
            window.contentViewController = main
            window.setContentSize(size)
        }
        window.appearance = NSAppearance(named:CommandLine.arguments.contains("--preview-light") ? .aqua : .darkAqua)
        application.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Isolated Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.mainMenu = menu
        window.center(); window.makeKeyAndOrderFront(nil); application.activate(ignoringOtherApps:true)
        print("RELEASE_PREVIEW_READY: production views; in-memory preferences; synthetic usage; no providers; storage commands denied")
        // --preview-snapshot=<file.png> writes the window, title bar and
        // traffic lights included, as a PNG and quits: release screenshots
        // without screen-recording access, since it draws its own window.
        if let path = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-snapshot=") })?
            .dropFirst("--preview-snapshot=".count) {
            // Drawn as the active window, as people see it while using it.
            window.orderFrontRegardless()
            window.makeKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let ok = snapshot(window, to: URL(fileURLWithPath: String(path)))
                print(ok ? "RELEASE_PREVIEW_SNAPSHOT: \(path)" : "RELEASE_PREVIEW_SNAPSHOT_FAILED")
                application.terminate(nil)
            }
        }
        withExtendedLifetime((window,storage,navigation)) { application.run() }
    }
}
extension ReleasePreview {
    /// Synthetic, exact readings for two agents, for release screenshots.
    static func sampleCards(language: AppLanguage) -> [SharedUsageCardPresentation] {
        let english = language == .english
        let now = Date()
        func window(_ id: String, _ kind: SharedUsageWindowKind, _ percent: Double, in seconds: TimeInterval,
                    _ en: String, _ zh: String) -> SharedUsageWindowPresentation {
            SharedUsageWindowPresentation(
                id: id, kind: kind, compactLabel: kind == .fiveHour ? "5H" : "7D",
                accessibilityLabel: kind == .fiveHour ? (english ? "five-hour window" : "五小时额度窗口")
                                                      : (english ? "seven-day window" : "七天额度窗口"),
                remaining: .finite(percent), resetsAt: now.addingTimeInterval(seconds),
                resetText: english ? en : zh)
        }
        func card(_ id: String, _ name: String, _ plan: String, _ five: Double, _ seven: Double,
                  _ source: String) -> SharedUsageCardPresentation {
            let fiveHour = window(id + "-five-hour", .fiveHour, five, in: 9_000, "Resets in 2 hr", "2 小时后重置")
            let sevenDay = window(id + "-seven-day", .sevenDay, seven, in: 280_000, "Resets in 3 days", "3 天后重置")
            return SharedUsageCardPresentation(
                id: id, providerName: name, planLabel: plan, connectionStatus: .connected, freshness: .fresh,
                windows: [fiveHour, sevenDay], selectedWindowID: fiveHour.id, remaining: fiveHour.remaining,
                sourceDescription: source, severity: SharedUsagePresentationPolicy.severity(for: fiveHour.remaining),
                isRetainingLastValidValue: false, capturedAt: now)
        }
        return [
            card("codex.local", "Codex", "PRO", 82, 64, english ? "Official local Codex usage" : "Codex 官方本机用量"),
            card("claude.browserSync", "Claude", "MAX", 47, 71, english ? "Exact sync" : "精确同步"),
        ]
    }

    /// The window as it appears on screen: its frame view drawn into a
    /// bitmap, clipped to the window's rounded corners, on a soft shadow.
    static func snapshot(_ window: NSWindow, to url: URL) -> Bool {
        guard let frameView = window.contentView?.superview else { return false }
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        frameView.cacheDisplay(in: bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / bounds.width
        let margin: CGFloat = 40
        let size = NSSize(width: bounds.width + margin * 2, height: bounds.height + margin * 2)
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return false }
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        let rect = NSRect(x: margin, y: margin + 6, width: bounds.width, height: bounds.height)
        let radius: CGFloat = 16
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        rep.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.18).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = out.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}

/// A snapshot shows the window as it looks in use, active, even when the
/// preview was started from a shell that keeps another app in front.
private final class PreviewWindow: NSWindow {
    var drawsAsActive = false
    override var isKeyWindow: Bool { drawsAsActive || super.isKeyWindow }
    override var isMainWindow: Bool { drawsAsActive || super.isMainWindow }
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
