import AppKit
import Foundation
import HESectoriumCore
import HESectoriumRuntime
import SwiftUI
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

/// Opt-in source-hosted evidence. This never composes the live app runtime.
@Suite("UMA 0.15 visual contract", .serialized)
@MainActor
struct UMA015VisualContractTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UMA015_VISUAL_EVIDENCE_DIR"] != nil))
    func productionMainWindowRendersThreeDestinationsWithGeometry() async throws {
        _ = NSApplication.shared
        let path = try #require(ProcessInfo.processInfo.environment["UMA015_VISUAL_EVIDENCE_DIR"])
        #expect(!path.isEmpty)
        let output = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var captures: [Capture] = []
        for language in [AppLanguage.english, .simplifiedChinese] {
            for dark in [false, true] {
                for (sizeName, size) in [("normal", NSSize(width: 1040, height: 760)), ("minimum", NSSize(width: 760, height: 520))] {
                    for destination in MainSurfaceDestination.allCases {
                        captures.append(try await capture(destination: destination, language: language, dark: dark,
                                                           sizeName: sizeName, size: size, output: output))
                    }
                }
            }
        }
        #expect(captures.count == 24)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("geometry-index.json"), options: .atomic)
    }

    @Test func promptDraftMigrationIsConfinedToExplicitInMemoryPreferences() throws {
        let preferences = ApplicationPreferences.inMemory()
        let independentPreferences = ApplicationPreferences.inMemory()
        #expect(preferences.isEphemeral && preferences.persistenceIdentifier == nil)
        var legacy = FactoriumV2SettingsDraft(project: "UMA015_MEMORY_ONLY",
            catalogRevision: "sol-luna-20260922.1", id: "cfg-uma015-memory-only")
        legacy.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .leader)
        legacy.setSelection(.init(model: "gpt-6-sol", effort: "high", speed: "standard"), for: .qa)
        ThreadOSSettingsPreferences.saveFactoriumV2(legacy, to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2SelectedProject(legacy.project, to: preferences)

        let form = FactoriumV2FormState(preferences: preferences)
        #expect(form.draft.catalogRevision == ThreadOSSettingsCodec.latestCatalogRevision)
        #expect(form.draft.roles[.leader]?.selection.model == "gpt-6.1-sol")
        #expect(form.draft.roles[.qa]?.selection.model == "gpt-6.1-sol")
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2(project: legacy.project, from: preferences) == form.draft)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshot(project: legacy.project, from: preferences) == legacy)
        #expect(ThreadOSSettingsPreferences.factoriumV2Projects(from: independentPreferences).isEmpty)
        #expect(ThreadOSSettingsPreferences.loadFactoriumV2LegacySnapshots(project: legacy.project, from: independentPreferences).isEmpty)
        #expect(preferences.isEphemeral && preferences.persistenceIdentifier == nil)
    }

    private func capture(destination: MainSurfaceDestination, language: AppLanguage, dark: Bool,
                         sizeName: String, size: NSSize, output: URL) async throws -> Capture {
        let name = "\(destination.rawValue.lowercased())-\(sizeName)-\(language == .english ? "en" : "zh")-\(dark ? "dark" : "light")"
        let fixture = try StorageFixture(root: output.appendingPathComponent("fixtures/\(name)", isDirectory: true))
        defer { fixture.store.deactivateWorkbench() }
        let navigation = MainSurfaceNavigationState()
        navigation.destination = destination
        let actions = ActionLedger()
        let promptPreferences = ApplicationPreferences.inMemory()
        #expect(promptPreferences.isEphemeral && promptPreferences.persistenceIdentifier == nil,
                "All prompt and legacy-draft keys must use an ephemeral backing, not a key snapshot of standard defaults.")
        let root = MainWindowRootView(
            store: UsageStore.preview(language: language), navigation: navigation,
            openSettings: { actions.record() }, scanAll: { actions.record() }, refreshAll: { actions.record() },
            connectCodex: { actions.record() }, disconnectCodex: { actions.record() },
            claudeControlState: { .consentRequired }, connectClaude: { actions.record() },
            accuracySyncClaude: { actions.record() }, hesectoriumStore: fixture.store, promptClipboard: actions,
            promptPreferences: promptPreferences
        )
        #expect(root.promptPreferences === promptPreferences)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "UMA visual fixture"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setContentSize(size)
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        settle(host)
        if destination == .sectorium {
            for _ in 0..<80 where fixture.store.inventoryState == .loading {
                try await Task.sleep(for: .milliseconds(25))
                settle(host)
            }
            #expect(fixture.store.inventoryState == .available)
        }
        settle(host)
        #expect(host.window === window)
        #expect(abs(host.bounds.width - size.width) <= 1 && abs(host.bounds.height - size.height) <= 1)
        var geometry: [String: Geometry] = [:]
        for view in [host] + descendants(of: host) {
            let id = view.accessibilityIdentifier()
            if !id.isEmpty, view.bounds.width > 0, view.bounds.height > 0 {
                geometry[id] = Geometry(rect: view.convert(view.bounds, to: host), kind: "native-view")
            }
        }
        collectAccessibilityGeometry(from: host, host: host, window: window, into: &geometry)
        if destination == .agents, let split = descendants(of: host).compactMap({ $0 as? NSSplitView }).first {
            for (index, pane) in split.arrangedSubviews.enumerated() {
                geometry["uma015.agent.split-pane.\(index)"] = Geometry(rect: pane.convert(pane.bounds, to: host), kind: "native-split-pane")
            }
        }
        var required = ["uma.main.navigation", "uma.main.settings"]
        if destination == .agents { required += ["uma.main.scan", "uma.main.refresh"] }
        if destination == .threadOS {
            required += ThreadOSPromptRole.allCases.flatMap {
                ["uma.threados.prompt.role.\($0.rawValue).model", "uma.threados.prompt.role.\($0.rawValue).effort"]
            } + ["uma.threados.prompt.generate-copy", "uma.threados.prompt.preview.text"]
        }
        if destination == .sectorium { required += ["uma.sectorium.refresh", "uma.sectorium.settings"] }
        for id in required {
            let frame = try #require(geometry[id], "Missing actual rendered control: \(id), fixture \(name)")
            #expect(host.bounds.insetBy(dx: -1, dy: -1).contains(frame.rect), "Control leaves content bounds: \(id), fixture \(name)")
        }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 100)
        try png.write(to: output.appendingPathComponent("\(name).png"), options: .atomic)
        #expect(actions.count == 0)
        #expect(fixture.backend.mutations == 0)
        #expect(promptPreferences.isEphemeral && promptPreferences.persistenceIdentifier == nil)
        let capture = Capture(fixture: name, phase: output.lastPathComponent, sourceHosted: true,
                              installedRuntime: false, foregroundAcceptance: false,
                              preferences: "explicit ApplicationPreferences.inMemory() per scene; prompt and legacy-draft preferences use ephemeral backing",
                              windowFrame: Geometry(rect: window.frame, kind: "outer-window"),
                              content: Geometry(rect: host.bounds, kind: "content-bounds"),
                              pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh,
                              geometry: geometry, storageCommandExecution: "injected runner; no subprocess execution")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(capture).write(to: output.appendingPathComponent("\(name).json"), options: .atomic)
        return capture
    }

    private func settle(_ host: NSView) {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.window?.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private func collectAccessibilityGeometry(from node: Any, host: NSView, window: NSWindow,
                                              into geometry: inout [String: Geometry], depth: Int = 0) {
        guard depth < 32 else { return }
        let children: [Any]
        if let view = node as? NSView {
            children = view.accessibilityChildren() ?? []
        } else if let element = node as? NSAccessibilityElement {
            if let id = element.accessibilityIdentifier(), !id.isEmpty {
                let frame = host.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
                if frame.width > 0, frame.height > 0, geometry[id] == nil {
                    geometry[id] = Geometry(rect: frame, kind: "accessibility-element")
                }
            }
            children = element.accessibilityChildren() ?? []
        } else { return }
        for child in children {
            collectAccessibilityGeometry(from: child, host: host, window: window, into: &geometry, depth: depth + 1)
        }
    }

    private struct Geometry: Codable {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
        let kind: String
        init(rect: CGRect, kind: String) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height; self.kind = kind }
        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }

    private struct Capture: Codable {
        let fixture: String, phase: String
        let sourceHosted: Bool, installedRuntime: Bool, foregroundAcceptance: Bool
        let preferences: String
        let windowFrame: Geometry, content: Geometry
        let pixelsWide: Int, pixelsHigh: Int
        let geometry: [String: Geometry]
        let storageCommandExecution: String
    }

    private final class ActionLedger: ThreadOSSettingsClipboard {
        private(set) var count = 0
        func record() { count += 1 }
        func write(_ string: String) -> Bool { record(); return false }
    }

    @MainActor private struct StorageFixture {
        let store: HESectoriumStore
        let backend: FixtureBackend
        init(root: URL) throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let paths = HESectoriumPaths(root: root.appendingPathComponent("support", isDirectory: true))
            let device = SectoriumPhysicalDevice(id: "F30A72EE-5BDA-4DEB-8720-508607929301", bsdName: "disk81",
                name: "Visual fixture external drive", isExternal: true, identityVerified: true,
                wholeDeviceBytes: 512 * 1024 * 1024 * 1024, mountedVolumePaths: [], volumeUUIDs: [],
                readBytes: nil, writtenBytes: nil, isVirtual: false)
            backend = FixtureBackend()
            let service = HESectoriumService(paths: paths, backend: backend, store: FixtureStateStore(),
                operationLock: FixtureLock(), installer: HESectoriumInstaller(paths: paths, home: root),
                runner: FixtureRunner(device: device), identityPolicy: .expected,
                agentStatusProvider: UnknownAgentStatusProvider(), sectoriumDeviceObserver: FixtureObserver(device: device),
                sectoriumDeviceIOSampler: FixtureIOSampler())
            store = HESectoriumStore(service: service, sampleIntervalNanoseconds: 60_000_000_000)
        }
    }

    private final class FixtureStateStore: DurableStateStore {
        private var state = StoragePersistentState(ejectIntent: false)
        func load() throws -> StoragePersistentState { state }
        func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
            guard state.revision == expectedRevision else { return false }
            state = newState
            return true
        }
    }
    private final class FixtureLock: OperationLock { func acquire() -> Bool { true }; func release() {} }
    private final class FixtureBackend: StorageBackend {
        private(set) var mutations = 0
        func observeOuter() -> VolumeIdentity? { nil }
        func observe() -> StorageObservation? { nil }
        func attachImage() -> CommandOutcome { mutations += 1; return .init(exitCode: 97, detail: "visual fixture forbids storage") }
        func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { .incomplete(reason: "visual fixture has no live occupancy") }
        func perform(_ step: EjectStep) -> CommandOutcome { mutations += 1; return .init(exitCode: 97, detail: "visual fixture forbids storage") }
        func finalOuterState() -> FinalOuterState { .unknown("visual fixture forbids storage") }
    }
    private final class FixtureRunner: HESectoriumCommandRunning {
        let device: SectoriumPhysicalDevice
        init(device: SectoriumPhysicalDevice) { self.device = device }
        func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
            if executable == "/usr/sbin/diskutil", arguments == ["info", "-plist", "/dev/\(device.bsdName)"],
               let data = try? PropertyListSerialization.data(fromPropertyList: ["DeviceIdentifier": device.bsdName, "MediaUUID": device.id], format: .xml, options: 0) {
                return .init(exitCode: 0, detail: String(decoding: data, as: UTF8.self))
            }
            return .init(exitCode: 97, detail: "visual fixture forbids command execution")
        }
    }
    private final class FixtureObserver: SectoriumDeviceObserving {
        let device: SectoriumPhysicalDevice
        init(device: SectoriumPhysicalDevice) { self.device = device }
        func observeDevices() throws -> [SectoriumPhysicalDevice] { [device] }
    }
    private final class FixtureIOSampler: SectoriumDeviceIOCounterSampling, @unchecked Sendable {
        func counters(forWholeBSDName bsdName: String, expectedMediaID: UUID) -> SectoriumDeviceIOCounters? {
            .init(readBytes: 1000, writtenBytes: 2000)
        }
    }
}
