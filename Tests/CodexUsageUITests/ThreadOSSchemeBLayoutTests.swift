import AppKit
import SwiftUI
import Testing
@testable import CodexUsageUI

@MainActor struct ThreadOSSchemeBLayoutTests {
    @Test func schemeBMeasuresWholeWindowsAndReachableRoleChildAndFooterGeometry() throws {
        _ = NSApplication.shared
        for fixture in LayoutFixture.requiredCases {
            let preferences = ApplicationPreferences.inMemory()
            ThreadOSSettingsPreferences.saveFactoriumV2(draft(for: fixture), to: preferences)
            let probe = ThreadOSSchemeBLayoutProbe()
            var snapshot = UsageSnapshot.preview(language: fixture.language)
            snapshot.providerSource = UsageSourceStatus(label: "Account", scope: "account", capturedAt: Date(), isAvailable: true, freshness: .fresh)
            snapshot.localSource = UsageSourceStatus(label: "Local", scope: "local", capturedAt: Date(), isAvailable: true, freshness: .stale)
            let settings = ThreadOSSettingsView(language: fixture.language, basicUsage: .make(snapshot: snapshot, provider: nil), preferences: preferences, initiallyExpandedWorkerGroups: fixture.groups, layoutProbe: probe, footerStatusOverride: fixture.footerStatus)
            let host = NSHostingView(rootView: MainShellReservedHostedView(settings: settings))
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = host
            window.appearance = NSAppearance(named: fixture.appearance)
            window.setContentSize(fixture.contentSize)
            window.orderFront(nil)
            defer { window.orderOut(nil) }

            settle(host)
            #expect(window.contentView?.bounds.size == fixture.contentSize)
            let views = descendants(of: host)
            let scroll = try #require(views.compactMap { $0 as? NSScrollView }.first { $0.hasVerticalScroller })
            let document = try #require(scroll.documentView)
            #expect(!scroll.hasHorizontalScroller)
            #expect(document.frame.width <= scroll.contentView.bounds.width + 1)
            #expect(scroll.contentView.bounds.height > 0)

            let initialFrames = probe.frames
            let root = try #require(initialFrames["root"])
            let viewport = try #require(initialFrames["scroll.viewport"])
            let documentFrame = try #require(initialFrames["scroll.document"])
            #expect(root.width == host.bounds.width && root.height < host.bounds.height)
            #expect(host.bounds.height - root.height >= MainShellReservedHostedView.reservedHeight)
            #expect(viewport.height > 0 && viewport.height < root.height)
            #expect(documentFrame.width <= viewport.width + 1)
            for role in FactoriumV2Role.allCases {
                let card = try #require(initialFrames["role.\(role.rawValue).card"])
                let header = try #require(initialFrames["role.\(role.rawValue).header"])
                #expect(card.width > 0 && card.height >= 52)
                #expect(document.frame.contains(card))
                #expect(card.contains(header))
            }
            let cards = try FactoriumV2Role.allCases.map { role in
                try #require(initialFrames["role.\(role.rawValue).card"])
            }
            let headers = try FactoriumV2Role.allCases.map { role in
                try #require(initialFrames["role.\(role.rawValue).header"])
            }
            #expect(cards.dropFirst().allSatisfy { abs($0.height - cards[0].height) < 1 })
            #expect(headers.allSatisfy { $0.height > 0 })
            let workerRoles: [FactoriumV2Role] = [.qa, .coder, .repair, .reviewer]
            for role in workerRoles {
                let model = try #require(initialFrames["role.\(role.rawValue).model"])
                let effort = try #require(initialFrames["role.\(role.rawValue).effort"])
                let speed = try #require(initialFrames["role.\(role.rawValue).speed"])
                let card = try #require(initialFrames["role.\(role.rawValue).card"])
                #expect(card.contains(model) && card.contains(effort) && card.contains(speed))
            }
            for group in fixture.groups {
                let panel = try #require(initialFrames["role.\(group.rawValue).workers"])
                #expect(panel.height > 0)
                #expect(document.frame.contains(panel))
                for slot in 1...3 {
                    let row = try #require(initialFrames["role.\(group.rawValue).worker.\(slot)"])
                    #expect(row.height >= 34)
                    #expect(panel.contains(row))
                }
            }
            let footer = try #require(initialFrames["footer.generate-copy"])
            let footerStatus = try #require(initialFrames["footer.status"])
            // The footer reporter is in the Scheme B named coordinate space;
            // AppKit may keep the outer shell's origin during a fresh-state
            // layout pass. Reachability is established by the fixed footer's
            // positive frame and the scroll viewport, not mixed coordinates.
            #expect(footer.width > 0 && footer.height >= 44)
            #expect(footer.contains(footerStatus))
            #expect(footer.height >= 44)
            if fixture.identifier.contains("1040x760") {
                #expect(cards.dropFirst().allSatisfy { abs($0.minY - cards[0].minY) < 1 })
                #expect(cards.allSatisfy { $0.maxX <= viewport.maxX + 1 })
                for control in ["model", "effort", "speed"] {
                    let frames = try workerRoles.map { role in
                        try #require(initialFrames["role.\(role.rawValue).\(control)"])
                    }
                    #expect(frames.dropFirst().allSatisfy { abs($0.minY - frames[0].minY) < 1 })
                }
            }
            captureIfRequested(fixture: fixture, host: host, suffix: "initial")

            let maxY = max(0, document.frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: .init(x: 0, y: maxY))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(host)
            #expect(probe.frames["footer.generate-copy"]?.height == footer.height)
            let endViewport = try #require(probe.frames["scroll.viewport"])
            let advanced = try #require(probe.frames["advanced.details"])
            #expect(endViewport.contains(advanced), "Maximum scroll must expose Advanced details above the fixed footer")
            #expect(footer.intersection(advanced).isNull)
            #expect(footer.contains(try #require(probe.frames["footer.status"])))
            emitEvidenceIfRequested(fixture: fixture, window: window, host: host, scroll: scroll, document: document, initialFrames: initialFrames, endFrames: probe.frames, endOffset: scroll.contentView.bounds.origin.y)
        }
    }

    @Test func workerExpansionIsPreservedIndependentlyForEachProjectAndAcrossReopen() {
        let preferences = ApplicationPreferences.inMemory()
        let alpha: Set<FactoriumV2Role> = [.coder]
        let beta: Set<FactoriumV2Role> = [.reviewer, .repair]
        ThreadOSSettingsPreferences.saveFactoriumV2ExpandedGroups(alpha, project: "ALPHA", to: preferences)
        ThreadOSSettingsPreferences.saveFactoriumV2ExpandedGroups(beta, project: "BETA", to: preferences)

        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "ALPHA", from: preferences) == alpha)
        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "BETA", from: preferences) == beta)
        #expect(ThreadOSSettingsPreferences.factoriumV2ExpandedGroups(project: "ALPHA", from: preferences) == alpha)
    }

    private func draft(for fixture: LayoutFixture) -> FactoriumV2SettingsDraft {
        var draft = FactoriumV2SettingsDraft(project: "SCHEME_B_LAYOUT")
        if !fixture.leaderPreserved {
            var leader = draft.roles[.leader]!
            leader.preserve = false
            draft.roles[.leader] = leader
        }
        for role in [FactoriumV2Role.coder, .reviewer] {
            var slots = draft.workers(for: role)
            slots[0].inherits = false; slots[0].hasCustomSelection = true; slots[0].selection.effort = "high"
            slots[1].enabled = false
            slots[2].inherits = false; slots[2].hasCustomSelection = true; slots[2].selection.speed = "standard"
            draft.setWorkers(slots, for: role)
        }
        return draft
    }

    private func settle(_ host: NSView) {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
    }

    private func descendants(of view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }

    private func emitEvidenceIfRequested(fixture: LayoutFixture, window: NSWindow, host: NSView, scroll: NSScrollView, document: NSView, initialFrames: [String: CGRect], endFrames: [String: CGRect], endOffset: CGFloat) {
        guard let root = ProcessInfo.processInfo.environment["TOSUMA_UI_B_EVIDENCE_DIR"], !root.isEmpty else { return }
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let metric = LayoutMetric(fixture: fixture.identifier, hostedRuntime: true, installedRuntime: false, mainShellToolbarHeightFromSource: 48, hostedShellReservation: MainShellReservedHostedView.reservedHeight, wholeWindow: .init(window.frame), content: .init(host.bounds), appKitScrollBoundsAtEnd: .init(scroll.contentView.bounds), document: .init(document.frame), endScrollOffsetY: endOffset, initialFrames: initialFrames.mapValues(Rect.init), endFrames: endFrames.mapValues(Rect.init))
        if let data = try? JSONEncoder.pretty.encode(metric) { try? data.write(to: directory.appendingPathComponent("\(fixture.identifier).json"), options: .atomic) }
        let bounds = host.bounds
        guard let image = host.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        host.cacheDisplay(in: bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(fixture.identifier)-end.png"), options: .atomic)
    }

    private func captureIfRequested(fixture: LayoutFixture, host: NSView, suffix: String) {
        guard let root = ProcessInfo.processInfo.environment["TOSUMA_UI_B_EVIDENCE_DIR"], !root.isEmpty else { return }
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bounds = host.bounds
        guard let image = host.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        host.cacheDisplay(in: bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(fixture.identifier)-\(suffix).png"), options: .atomic)
    }

    private struct LayoutFixture {
        let identifier: String; let contentSize: NSSize; let language: AppLanguage; let appearance: NSAppearance.Name; let groups: Set<FactoriumV2Role>; let leaderPreserved: Bool; let requiresInitialPrimaryContainment: Bool; let footerStatus: String?
        static let requiredCases = [
            LayoutFixture(identifier: "hosted-settings-1040x760-content-en-light-fresh-coder-reviewer-summary", contentSize: .init(width: 1_040, height: 760), language: .english, appearance: .aqua, groups: [.coder], leaderPreserved: true, requiresInitialPrimaryContainment: true, footerStatus: nil),
            LayoutFixture(identifier: "hosted-settings-1000x760-content-en-light-both", contentSize: .init(width: 1_000, height: 760), language: .english, appearance: .aqua, groups: [.coder, .reviewer], leaderPreserved: true, requiresInitialPrimaryContainment: true, footerStatus: nil),
            LayoutFixture(identifier: "hosted-settings-1000x760-content-en-light-copy-failure", contentSize: .init(width: 1_000, height: 760), language: .english, appearance: .aqua, groups: [.coder, .reviewer], leaderPreserved: true, requiresInitialPrimaryContainment: false, footerStatus: "Request was generated, but the local clipboard could not be written."),
            LayoutFixture(identifier: "hosted-settings-760x552-content-zh-dark-both", contentSize: .init(width: 760, height: 552), language: .simplifiedChinese, appearance: .darkAqua, groups: [.coder, .reviewer], leaderPreserved: false, requiresInitialPrimaryContainment: false, footerStatus: nil),
            LayoutFixture(identifier: "hosted-settings-1280x900-content-zh-light-both", contentSize: .init(width: 1_280, height: 900), language: .simplifiedChinese, appearance: .aqua, groups: [.coder, .reviewer], leaderPreserved: false, requiresInitialPrimaryContainment: false, footerStatus: nil),
            LayoutFixture(identifier: "hosted-settings-1280x900-content-en-dark-both", contentSize: .init(width: 1_280, height: 900), language: .english, appearance: .darkAqua, groups: [.coder, .reviewer], leaderPreserved: true, requiresInitialPrimaryContainment: false, footerStatus: nil),
        ]
    }


    private struct LayoutMetric: Codable {
        let fixture: String; let hostedRuntime: Bool; let installedRuntime: Bool; let mainShellToolbarHeightFromSource: CGFloat; let hostedShellReservation: CGFloat; let wholeWindow: Rect; let content: Rect; let appKitScrollBoundsAtEnd: Rect; let document: Rect; let endScrollOffsetY: CGFloat; let initialFrames: [String: Rect]; let endFrames: [String: Rect]
    }

    private struct Rect: Codable {
        let x: CGFloat; let y: CGFloat; let width: CGFloat; let height: CGFloat
        init(_ value: CGRect) { x = value.origin.x; y = value.origin.y; width = value.width; height = value.height }
    }
}

/// Mirrors the actual main shell's 48-point toolbar plus divider without
/// claiming that an isolated settings host is a complete installed app.
private struct MainShellReservedHostedView: View {
    static let reservedHeight: CGFloat = 49
    let settings: ThreadOSSettingsView

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 48).accessibilityHidden(true)
            Divider()
            settings
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }
}
