import AppKit
import SwiftUI
import Testing
import Vision
import HESectoriumCore
import HESectoriumRuntime
@testable import CodexUsageUI

// These are real AppKit hosting/layout checks with isolated data and command
// stubs. They do not launch UMA, capture the screen, or operate a real disk.
@Suite("Settings viewport layout", .serialized)
@MainActor
struct SettingsViewportLayoutTests {
    // Sectorium's settings left Global Settings for the Sectorium tab's own
    // sheet; the same reach checks now run on that sheet's content.
    @Test("Sectorium settings actions fit the sheet and remain scrollable",
          arguments: [AppLanguage.english, .simplifiedChinese], [NSSize(width: 560, height: 460), NSSize(width: 560, height: 620), NSSize(width: 760, height: 552)])
    func storagePaneFits(language: AppLanguage, size: NSSize) throws {
        let fixture = try Fixture(language: language, pane: nil, size: size)
        defer { fixture.close() }
        settle(fixture.host)
        let actions = descendants(fixture.host).compactMap { $0 as? NSButton }.filter {
            $0.accessibilityIdentifier().hasPrefix("uma.settings.hesectorium.")
        }
        // Mounting left this pane in 0.17.2, which moved per-volume loading to
        // the Sectorium page; the pane now says so itself in the footer row
        // below. A `mount` button here would be the defect, not its absence —
        // but this set kept naming one, and had been failing unread since.
        let expected: Set<String> = ["install", "repair", "automation", "eject", "refresh"]
        #expect(Set(actions.compactMap { $0.accessibilityIdentifier().split(separator: ".").last.map(String.init) }) == expected)
        var pinned: Set<String> = []
        for action in actions {
            let rect = action.convert(action.bounds, to: fixture.host)
            #expect(rect.minX >= -1 && rect.maxX <= size.width + 1,
                    "Action must stay inside the sheet: \(action.title), \(rect)")
            var scrolls: [NSScrollView] = []
            var ancestor = action.superview
            while let view = ancestor, view !== fixture.host {
                if let scroll = view as? NSScrollView { scrolls.append(scroll) }
                ancestor = view.superview
            }
            guard let scroll = scrolls.first else {
                // Outside the scrolling content: a pinned control, which has to
                // be inside the viewport as it stands, because no amount of
                // scrolling could ever bring it into view.
                pinned.insert(String(action.accessibilityIdentifier().split(separator: ".").last ?? ""))
                #expect(fixture.host.bounds.insetBy(dx: -1, dy: -1).contains(rect),
                        "A pinned action must be visible without scrolling: \(action.title), \(rect)")
                continue
            }
            #expect(scrolls.count == 1, "Storage actions need one scrolling viewport, not a nested form")
            let document = try #require(scroll.documentView)
            let target = action.convert(action.bounds, to: document)
            document.scrollToVisible(target)
            settle(fixture.host)
            #expect(scroll.contentView.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(target),
                    "Every action must be fully reachable by vertical scrolling: \(action.title)")
            #expect(abs(scroll.contentView.bounds.minX) < 1, "No horizontal scrolling is needed")
        }
        // Pinning is the exception, so it is named: an action that quietly left
        // the scrolling content would otherwise stop being checked for reach at
        // all, and this is the assertion that would notice.
        #expect(pinned == ["refresh"])
        #expect(fixture.runner.mutatingCalls == 0)
    }

    // Side by side, the two Privacy & Data actions are wider than the default
    // window gives their English titles, and at the minimum both were cut off
    // ("Clear Retained Loca…", "Export Sanitized Di…"). What reaches the
    // screen is the check, so the rendered titles are read back. Offscreen,
    // the Form's background is transparent and recognition reads it as
    // black, so the dark appearance's light text is what stays legible.
    @Test("Privacy actions keep their full titles at the default and minimum Settings sizes",
          arguments: [AppLanguage.english, .simplifiedChinese],
          [NSSize(width: 640, height: 460), NSSize(width: 560, height: 400)])
    func privacyActionsAreNotTruncated(language: AppLanguage, size: NSSize) throws {
        let fixture = try Fixture(language: language, pane: .privacy, size: size)
        defer { fixture.close() }
        fixture.window.appearance = NSAppearance(named: .darkAqua)
        settle(fixture.host)
        for scroll in descendants(fixture.host).compactMap({ $0 as? NSScrollView }) {
            guard let document = scroll.documentView else { continue }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        settle(fixture.host)
        let rendered = try recognizedText(in: fixture.host, language: language)
        // Chinese is matched on the words a truncation would drop first;
        // recognition reads the full titles reliably but not every particle.
        let titles = language == .english
            ? ["Clear Retained Local Data", "Export Sanitized Diagnostics"]
            : ["本地数据", "诊断信息"]
        for title in titles {
            #expect(rendered.contains { $0.contains(title) },
                    "\(title) must render in full at \(Int(size.width))x\(Int(size.height)): \(rendered)")
        }
    }

    @Test("Every settings pane retains a contained sidebar", arguments: GlobalSettingsPane.allCases)
    func allPanesFit(pane: GlobalSettingsPane) throws {
        let fixture = try Fixture(language: .english, pane: pane, size: NSSize(width: 560, height: 378))
        defer { fixture.close() }
        settle(fixture.host)
        try assertSidebarFits(fixture.host)
    }

    private func assertSidebarFits(_ host: NSView) throws {
        let sidebar = try #require(descendants(host).first { $0 is NSTableView })
        let rect = sidebar.convert(sidebar.bounds, to: host)
        #expect(rect.minX >= -1 && rect.maxX <= 201, "Sidebar must not be pushed beyond the left edge: \(rect)")
        #expect(rect.minY >= -1 && rect.maxY <= host.bounds.height + 1)
        #expect(rect.width >= 160)
    }

    private func settle(_ host: NSView) {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func recognizedText(in host: NSView, language: AppLanguage) throws -> [String] {
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = try #require(rep.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = language == .english ? ["en-US"] : ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private func descendants(_ root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor private final class Fixture {
        let root: URL
        let window: NSWindow
        let host: NSView
        let runner = NoCommands()
        /// `pane: nil` hosts the Sectorium settings sheet's content instead.
        init(language: AppLanguage, pane: GlobalSettingsPane?, size: NSSize) throws {
            _ = NSApplication.shared
            root = FileManager.default.temporaryDirectory.appendingPathComponent("uma-settings-layout-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let paths = HESectoriumPaths(root: root.appendingPathComponent("storage"))
            let service = HESectoriumService(paths: paths, backend: NoStorage(),
                operationLock: FixtureLock(), installer: HESectoriumInstaller(paths: paths, home: root),
                runner: runner, identityPolicy: .expected, agentStatusProvider: UnknownAgentStatusProvider(),
                sectoriumDeviceObserver: NoDevices())
            let preferences = ApplicationPreferences.inMemory()
            preferences.set(language.rawValue, for: UMAApplicationPreferenceKeys.language)
            let surface: AnyView = if let pane {
                AnyView(GlobalSettingsSurface(preferences: preferences,
                    store: UsageStore.preview(language: language), navigation: GlobalSettingsNavigationState(pane: pane),
                    dataPaths: .current(bundleIdentifier: "com.example.layout-fixture", applicationSupportDirectory: root, homeDirectory: root)))
            } else {
                AnyView(HESectoriumSettingsView(isChinese: language == .simplifiedChinese,
                    store: HESectoriumStore(service: service), onClose: {}))
            }
            let controller = NSHostingController(rootView: surface)
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.setContentSize(size)
            host = controller.view
            host.frame = NSRect(origin: .zero, size: size)
            // Hidden window: exercise the native layout without stealing focus.
        }
        func close() {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private final class NoCommands: HESectoriumCommandRunning {
    private let lock = NSLock()
    private var count = 0
    var mutatingCalls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        if executable != "/usr/bin/hdiutil" || arguments.first != "info" {
            lock.lock(); count += 1; lock.unlock()
        }
        return .init(exitCode: 97, detail: "Isolated layout fixture forbids commands")
    }
}
private final class NoDevices: SectoriumDeviceObserving {
    func observeDevices() throws -> [SectoriumPhysicalDevice] { [] }
}
private final class FixtureLock: OperationLock {
    func acquire() -> Bool { true }
    func release() {}
}
private final class NoStorage: StorageBackend {
    func observeOuter() -> VolumeIdentity? { nil }
    func observe() -> StorageObservation? { nil }
    func attachImage() -> CommandOutcome { .init(exitCode: 97, detail: "Fixture forbids attach") }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { .incomplete(reason: "Fixture") }
    func perform(_ step: EjectStep) -> CommandOutcome { .init(exitCode: 97, detail: "Fixture forbids eject") }
    func finalOuterState() -> FinalOuterState { .unknown("Fixture") }
}
