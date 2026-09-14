import AppKit
import SwiftUI
import Testing
@testable import CodexUsageUI

@MainActor
@Suite("Codex detail dashboard layout", .serialized)
struct AgentDashboardLayoutTests {
    @Test("fixture hosts keep the two-ring dashboard inside each content size")
    func dashboardFitsFixtureContentSizes() throws {
        _ = NSApplication.shared
        for fixture in Fixture.all {
            let store = UsageStore.preview(
                language: fixture.language,
                presentationCards: fixture.presentationCards,
                accountDailyUsage: fixture.accountDailyUsage
            )
            let view = AgentWorkspaceSurface(
                store: store,
                providerID: .codex,
                refresh: {}, connectCodex: {}, disconnectCodex: {},
                claudeControlState: { .consentRequired },
                connectClaude: {}, claudeAccuracySync: {},
                referenceDate: Date(timeIntervalSince1970: 1_800_000_000)
            )
            let host = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: .init(origin: .zero, size: fixture.contentSize),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.contentView = host
            window.appearance = NSAppearance(named: fixture.appearance)
            window.orderFront(nil)
            defer { window.orderOut(nil) }

            settle(host)
            #expect(host.bounds.size == fixture.contentSize)
            #expect(host.fittingSize.width <= fixture.contentSize.width)
            capture(host: host, fixture: fixture)
        }
    }

    @Test("sidebar-aware fixture reserves the production sidebar width at 1040 by 760 content")
    func sidebarAwareFixtureFitsRecommendedContentSize() throws {
        _ = NSApplication.shared
        let fixture = Fixture.all[0]
        let store = UsageStore.preview(
            language: .english,
            presentationCards: fixture.presentationCards,
            accountDailyUsage: fixture.accountDailyUsage
        )
        let provider = try #require(store.productInventory.provider(.codex))
        let root = HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Agents").font(.headline).padding(.horizontal, 10).padding(.top, 12)
                AgentGlanceRow(provider: provider, style: .mainList, selected: true, language: .english)
                Spacer()
            }
            .frame(minWidth: 210, idealWidth: 240, maxWidth: 285)
            .frame(width: 230)
            AgentWorkspaceSurface(
                store: store, providerID: .codex,
                refresh: {}, connectCodex: {}, disconnectCodex: {},
                claudeControlState: { .consentRequired }, connectClaude: {}, claudeAccuracySync: {}
            )
            .frame(minWidth: 500)
        }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: .init(origin: .zero, size: fixture.contentSize),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.contentView = host
        window.appearance = NSAppearance(named: fixture.appearance)
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        settle(host)
        #expect(host.bounds.size == fixture.contentSize)
        capture(host: host, fixture: fixture, suffix: "sidebar-aware")
    }

    private func settle(_ host: NSView) {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
    }

    private func capture(host: NSView, fixture: Fixture, suffix: String = "") {
        guard let root = ProcessInfo.processInfo.environment["TOSUMA_AGENT_DASHBOARD_EVIDENCE_DIR"], !root.isEmpty else { return }
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else { return }
        let name = suffix.isEmpty ? fixture.identifier : "\(fixture.identifier)-\(suffix)"
        try? png.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }

    private struct Fixture {
        let identifier: String
        let contentSize: NSSize
        let language: AppLanguage
        let appearance: NSAppearance.Name
        let presentationCards: [SharedUsageCardPresentation]
        let accountDailyUsage: [AgentAccountUsageDay]

        static let all = [
            Fixture(identifier: "fixture-agent-1040x760-content-en-light-healthy", contentSize: .init(width: 1_040, height: 760), language: .english, appearance: .aqua, presentationCards: [healthyCodexCard], accountDailyUsage: []),
            Fixture(identifier: "fixture-agent-1280x800-content-en-light-healthy-daily-account", contentSize: .init(width: 1_280, height: 800), language: .english, appearance: .aqua, presentationCards: [healthyCodexCard], accountDailyUsage: dailyAccountUsage),
            Fixture(identifier: "fixture-agent-760x552-content-zh-dark-unavailable", contentSize: .init(width: 760, height: 552), language: .simplifiedChinese, appearance: .darkAqua, presentationCards: [unavailableCodexCard], accountDailyUsage: []),
        ]

        private static let dailyAccountUsage = [
            AgentAccountUsageDay(day: "2026-09-07", tokens: 12),
            AgentAccountUsageDay(day: "2026-09-08", tokens: 18),
            AgentAccountUsageDay(day: "2026-09-09", tokens: 0),
            AgentAccountUsageDay(day: "2026-09-10", tokens: 24),
            AgentAccountUsageDay(day: "2026-09-11", tokens: 16),
            AgentAccountUsageDay(day: "2026-09-12", tokens: 20),
            AgentAccountUsageDay(day: "2026-09-13", tokens: 28),
        ]

        private static let healthyCodexCard = card(
            windows: [
                window(id: "five-hour", kind: .fiveHour, label: "5H", remaining: .finite(0)),
                window(id: "seven-day", kind: .sevenDay, label: "7D", remaining: .finite(74))
            ],
            selected: "seven-day",
            remaining: .finite(74),
            freshness: .fresh
        )

        private static let unavailableCodexCard = card(
            windows: [], selected: nil, remaining: .unavailable, freshness: .unavailable
        )

        private static func window(
            id: String,
            kind: SharedUsageWindowKind,
            label: String,
            remaining: SharedRemainingValue
        ) -> SharedUsageWindowPresentation {
            SharedUsageWindowPresentation(
                id: id, kind: kind, compactLabel: label, accessibilityLabel: label,
                remaining: remaining, resetsAt: Date(timeIntervalSince1970: 1_800_003_600), resetText: "Fixture reset"
            )
        }

        private static func card(
            windows: [SharedUsageWindowPresentation],
            selected: String?,
            remaining: SharedRemainingValue,
            freshness: SharedUsageFreshness
        ) -> SharedUsageCardPresentation {
            SharedUsageCardPresentation(
                id: CodexUsageConnector.connectorID.rawValue, providerName: "Codex", planLabel: "pro",
                connectionStatus: freshness == .unavailable ? .unavailable : .connected,
                freshness: freshness, windows: windows, selectedWindowID: selected, remaining: remaining,
                sourceDescription: "Test-only dashboard fixture", severity: .normal,
                isRetainingLastValidValue: false, capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }
}
