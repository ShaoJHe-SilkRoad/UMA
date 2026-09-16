import AppKit
import SwiftUI
import Testing
@testable import CodexUsageUI

@MainActor
@Suite("Codex detail dashboard layout", .serialized)
struct AgentDashboardLayoutTests {
    @Test("fixture hosts keep the compact quota dashboard inside each content size")
    func dashboardFitsFixtureContentSizes() throws {
        _ = NSApplication.shared
        for fixture in Fixture.all {
            let probe = AgentDashboardLayoutProbe()
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
                referenceDate: Date(timeIntervalSince1970: 1_800_000_000), layoutProbe: probe
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
            if fixture.identifier.contains("1040x762") { assertFirstScreen(probe) }
            capture(host: host, fixture: fixture)
        }
    }

    @Test("outer windows reserve sidebar and toolbar space for compact and wide dashboards")
    func sidebarAwareFixtureFitsRecommendedContentSize() throws {
        _ = NSApplication.shared
        for width: CGFloat in [760, 823, 1040] {
            for language: AppLanguage in [.simplifiedChinese, .english] {
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    let fixture = Fixture(
                        identifier: "outer-\(Int(width))-\(language)-\(appearance.rawValue)",
                        contentSize: .init(width: width, height: 714), language: language,
                        appearance: appearance, presentationCards: [Fixture.healthyCodexCard],
                        accountDailyUsage: Fixture.dailyAccountUsage
                    )
                    let store = UsageStore.preview(language: language, presentationCards: fixture.presentationCards,
                                                   accountDailyUsage: fixture.accountDailyUsage)
                    let provider = try #require(store.productInventory.provider(.codex))
                    let probe = AgentDashboardLayoutProbe()
                    let root = VStack(spacing: 0) {
                        Color.clear.frame(height: 49) // Production toolbar and divider.
                        HSplitView {
                            VStack {
                                AgentGlanceRow(provider: provider, style: .mainList, selected: true, language: language)
                                Spacer()
                            }.frame(minWidth: 190, idealWidth: 210, maxWidth: 285)
                            AgentWorkspaceSurface(store: store, providerID: .codex,
                                refresh: {}, connectCodex: {}, disconnectCodex: {},
                                claudeControlState: { .consentRequired }, connectClaude: {}, claudeAccuracySync: {},
                                layoutProbe: probe).frame(minWidth: 550)
                        }
                    }
                    let host = NSHostingView(rootView: root)
                    let window = NSWindow(contentRect: .init(origin: .zero, size: fixture.contentSize),
                                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
                    window.contentView = host
                    window.setFrame(.init(origin: .zero, size: fixture.contentSize), display: false)
                    window.appearance = NSAppearance(named: appearance)
                    window.orderFront(nil)
                    defer { window.orderOut(nil) }
                    settle(host)
                    #expect(window.frame.width == width)
                    #expect(window.frame.height == 714)
                    #expect(host.fittingSize.width <= width)
                    assertFirstScreen(probe)
                    capture(host: host, fixture: fixture)
                }
            }
        }
    }

    @Test("unavailable data omits quota, metric, and chart placeholders")
    func unavailableValuesDoNotProduceCards() throws {
        let store = UsageStore.preview(presentationCards: [Fixture.unavailableCodexCard])
        let probe = AgentDashboardLayoutProbe()
        let host = NSHostingView(rootView: AgentWorkspaceSurface(store: store, providerID: .codex,
            refresh: {}, connectCodex: {}, disconnectCodex: {}, claudeControlState: { .consentRequired },
            connectClaude: {}, claudeAccuracySync: {}, layoutProbe: probe))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 550, height: 620),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        #expect(probe.frames.keys.allSatisfy { !$0.hasPrefix("quota.") && !$0.hasPrefix("metric.") })
        #expect(probe.frames["trend"] == nil)
        #expect(probe.frames["estimate-trend"] == nil)
    }

    @Test("known stale quota warnings remain visible without a fabricated current value")
    func staleQuotaStateRemainsVisible() throws {
        let store = UsageStore.preview(presentationCards: [Fixture.staleCodexCard])
        let probe = AgentDashboardLayoutProbe()
        let host = NSHostingView(rootView: AgentWorkspaceSurface(store: store, providerID: .codex,
            refresh: {}, connectCodex: {}, disconnectCodex: {}, claudeControlState: { .consentRequired },
            connectClaude: {}, claudeAccuracySync: {}, layoutProbe: probe))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 550, height: 620),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let viewport = try #require(probe.frames["scroll.viewport"])
        let warning = try #require(probe.frames["quota-state.seven-day"])
        #expect(viewport.contains(warning))
        #expect(probe.frames["quota.seven-day"] != nil)
        #expect(probe.frames["quota.five-hour"] == nil)
        let projection = CodexDashboardProjection(snapshot: store.snapshot, provider: store.productInventory.provider(.codex))
        #expect(projection.sevenDay.state == .stale)
        #expect(projection.sevenDay.state.ringFraction == nil)
    }

    @Test("Codex main sidebar omits unknown usage but retains known zero and quick-panel behavior")
    func sidebarUnknownAndZero() throws {
        for (name, card, expected) in [
            ("unavailable", Fixture.unavailableCodexCard, Optional<String>.none),
            ("zero", Fixture.zeroCodexCard, Optional("0%"))
        ] {
            let store = UsageStore.preview(presentationCards: [card])
            let provider = try #require(store.productInventory.provider(.codex))
            let row = AgentGlanceRow(provider: provider, style: .mainList, selected: true, language: .simplifiedChinese)
            #expect(row.mainListUsageDisplayText == expected)
            if expected == nil {
                #expect(AgentGlanceRow(provider: provider, style: .quickPanel).mainListUsageDisplayText == "—")
            }
            let root = VStack(spacing: 0) {
                Color.clear.frame(height: 49)
                HSplitView {
                    VStack(alignment: .leading) {
                        Text("智能体").font(.headline).padding(.horizontal, 10).padding(.top, 12)
                        row.padding(.horizontal, 6)
                        Spacer()
                    }.frame(minWidth: 190, idealWidth: 210, maxWidth: 285)
                    AgentWorkspaceSurface(store: store, providerID: .codex,
                        refresh: {}, connectCodex: {}, disconnectCodex: {},
                        claudeControlState: { .consentRequired }, connectClaude: {}, claudeAccuracySync: {})
                        .frame(minWidth: 550)
                }
            }
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 760, height: 714),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.setFrame(.init(x: 0, y: 0, width: 760, height: 714), display: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            settle(host)
            #expect(host.fittingSize.width <= 760)
            capture(host: host, fixture: Fixture(identifier: "sidebar-760-\(name)",
                contentSize: host.bounds.size, language: .simplifiedChinese, appearance: .darkAqua,
                presentationCards: [card], accountDailyUsage: []))
        }
    }

    private func settle(_ host: NSView) {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
    }

    private func assertFirstScreen(_ probe: AgentDashboardLayoutProbe) {
        let viewport = try! #require(probe.frames["scroll.viewport"])
        let quotas = ["quota.seven-day", "quota.five-hour"].map { try! #require(probe.frames[$0]) }
        let metrics = ["metric.week", "metric.total", "metric.api-cost-seven-days"].map { try! #require(probe.frames[$0]) }
        let trend = try! #require(probe.frames["trend"])
        #expect(quotas.allSatisfy(viewport.contains))
        #expect(metrics.allSatisfy(viewport.contains))
        #expect(viewport.contains(trend))
        #expect(quotas.allSatisfy { $0.minY < metrics[0].minY })
        #expect(metrics.prefix(2).allSatisfy { $0.maxY <= trend.minY })
        #expect(metrics[2].maxX < trend.minX)
        #expect(abs(metrics[2].minY - trend.minY) < 1)
        let visibleDays = probe.frames.keys.filter { $0.hasPrefix("day.") }
        #expect(visibleDays.count == 6) // One missing day stays blank; reported zero remains present.
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
            Fixture(identifier: "fixture-agent-1040x762-content-en-light-healthy", contentSize: .init(width: 1_040, height: 762), language: .english, appearance: .aqua, presentationCards: [healthyCodexCard], accountDailyUsage: dailyAccountUsage),
            Fixture(identifier: "fixture-agent-1280x800-content-en-light-healthy-daily-account", contentSize: .init(width: 1_280, height: 800), language: .english, appearance: .aqua, presentationCards: [healthyCodexCard], accountDailyUsage: dailyAccountUsage),
            Fixture(identifier: "fixture-agent-760x552-content-zh-dark-unavailable", contentSize: .init(width: 760, height: 552), language: .simplifiedChinese, appearance: .darkAqua, presentationCards: [unavailableCodexCard], accountDailyUsage: []),
        ]

        static var dailyAccountUsage: [AgentAccountUsageDay] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return (-6...0).filter { $0 != -5 }.map { offset in
                AgentAccountUsageDay(day: formatter.string(from: calendar.date(byAdding: .day, value: offset, to: today)!),
                                     tokens: offset == -4 ? 0 : Int64((offset + 7) * 10))
            }
        }

        static let healthyCodexCard = card(
            windows: [
                window(id: "five-hour", kind: .fiveHour, label: "5H", remaining: .finite(0)),
                window(id: "seven-day", kind: .sevenDay, label: "7D", remaining: .finite(74))
            ],
            selected: "seven-day",
            remaining: .finite(74),
            freshness: .fresh
        )

        static let staleCodexCard = card(
            windows: [window(id: "seven-day", kind: .sevenDay, label: "7D", remaining: .finite(74))],
            selected: "seven-day", remaining: .finite(74), freshness: .stale
        )

        static let zeroCodexCard = card(
            windows: [window(id: "seven-day", kind: .sevenDay, label: "7D", remaining: .finite(0))],
            selected: "seven-day", remaining: .finite(0), freshness: .fresh
        )

        static let unavailableCodexCard = card(
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
