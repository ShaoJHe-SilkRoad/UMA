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
        #expect(probe.frames["quota.five-hour"] != nil) // Exact Pro presentation rule survives stale raw data.
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

    @Test("known zero and unknown days retain distinct rendered data targets")
    func accessibleDailySelection() throws {
        let store = UsageStore.preview(presentationCards: [Fixture.healthyCodexCard],
                                       accountDailyUsage: Fixture.dailyAccountUsage)
        let probe = AgentDashboardLayoutProbe()
        let host = NSHostingView(rootView: AgentWorkspaceSurface(store: store, providerID: .codex,
            refresh: {}, connectCodex: {}, disconnectCodex: {}, claudeControlState: { .consentRequired },
            connectClaude: {}, claudeAccuracySync: {}, layoutProbe: probe))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 550, height: 680),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        settle(host)
        let projection = CodexDashboardProjection(snapshot: store.snapshot, provider: store.productInventory.provider(.codex))
        let slots = projection.dailySlots()
        let zero = try #require(slots.first { $0.tokens == 0 })
        let unknown = try #require(slots.first { $0.tokens == nil })
        #expect(probe.frames["day.\(zero.day)"] != nil)
        #expect(probe.frames["day.\(unknown.day)"] == nil)
        #expect(probe.frames["day-detail"] != nil)
        // System AX role, value, activation and Tab traversal are contracted by the
        // independently launched REPAIR07 native fixture. NSHostingView traversal
        // does not represent SwiftUI's system accessibility tree.
    }

    @Test("complete zero and long-value matrices exercise derived columns and shared metric style")
    func completeSeriesAndTypographyMatrix() throws {
        _ = NSApplication.shared
        for scenario in [AnalysisFixture.complete, .allZero, .longValues] {
            for width: CGFloat in [760, 823, 1040, 1280] {
                for language: AppLanguage in [.simplifiedChinese, .english] {
                    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                        let receipt = "scenario=\(scenario.rawValue) width=\(Int(width)) language=\(language) appearance=\(appearance.rawValue)"
                        print("MATRIX \(receipt)")
                        let days = scenario.days
                        let store = UsageStore.preview(language: language, presentationCards: [Fixture.healthyCodexCard],
                                                       accountDailyUsage: days)
                        let provider = try #require(store.productInventory.provider(.codex))
                        var snapshot = store.snapshot
                        if scenario == .longValues {
                            snapshot.metrics = [
                                UsageMetric(id: "week", value: "9,223,372,036,854,775,807", label: "7D"),
                                UsageMetric(id: "total", value: "9,223,372,036,854,775,807", label: "Lifetime")
                            ]
                            snapshot.apiCostEstimate = APICostEstimateSnapshot(sevenDayUSD: 1_234_567_890_123.45,
                                lifetimeUSD: 2_345_678_901_234.56, coveragePercent: 89, modelNames: [])
                        }
                        let projection = CodexDashboardProjection(snapshot: snapshot, provider: provider)
                        let analysis = projection.dailyAnalysis()
                        let summary = try #require(analysis.summary)
                        let probe = AgentDashboardLayoutProbe()
                        let root = VStack(spacing: 0) {
                            Color.clear.frame(height: 49)
                            HSplitView {
                                VStack {
                                    AgentGlanceRow(provider: provider, style: .mainList, selected: true, language: language)
                                    Spacer()
                                }.frame(minWidth: 190, idealWidth: 210, maxWidth: 285)
                                AgentWorkspaceSurface(store: store, providerID: .codex,
                                    refresh: {}, connectCodex: {}, disconnectCodex: {},
                                    claudeControlState: { .consentRequired }, connectClaude: {}, claudeAccuracySync: {},
                                    layoutProbe: probe, fixtureProjection: projection).frame(minWidth: 550)
                            }
                        }
                        let host = NSHostingView(rootView: root)
                        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 714),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
                        window.contentView = host
                        window.setFrame(.init(x: 0, y: 0, width: width, height: 714), display: false)
                        window.appearance = NSAppearance(named: appearance)
                        window.orderFront(nil)
                        defer { window.orderOut(nil) }
                        settle(host)
                        #expect(host.fittingSize.width <= width)
                        assertFirstScreen(probe, expectedDays: analysis.knownSlots.count)
                        #expect(probe.frames["analysis.mean"] != nil)
                        #expect(probe.frames["analysis.peak"] != nil)
                        #expect(probe.frames["analysis.mean-line"] != nil)
                        #expect(probe.frames["table.cumulative-header"] != nil)
                        #expect((probe.frames["table.share-header"] != nil) == (scenario != .allZero))
                        #expect(summary.shares.isEmpty == (scenario == .allZero))
                        if scenario == .allZero {
                            #expect(summary.mean == 0)
                            #expect(summary.cumulative.values.allSatisfy { $0 == 0 })
                        }
                        for metric in projection.metrics.filter({ ["week", "total", "api-cost-seven-days"].contains($0.id) }) {
                            let original = try #require(metric.value)
                            let frame = try #require(probe.frames["metric-value.\(metric.id)"])
                            let viewport = try #require(probe.frames["scroll.viewport"])
                            let display = CodexDashboardMetricTypography.displayValue(metric, fullWidth: viewport.width - 32)
                            #expect(display == original) // These fixtures fit full width without approximating.
                            #expect(!display.contains("\n"))
                            #expect(frame.width + 1 >= CodexDashboardMetricTypography.measuredWidth(display))
                            #expect(frame.height == CodexDashboardMetricTypography.lineHeight)
                            #expect(viewport.contains(frame))
                        }
                        let viewport = try #require(probe.frames["scroll.viewport"])
                        let metricValues = projection.metrics.filter { ["week", "total", "api-cost-seven-days"].contains($0.id) }.compactMap(\.value)
                        let expectedLayout = CodexDashboardMetricTypography.layout(values: metricValues, availableWidth: viewport.width - 32)
                        let metricFrames = try ["week", "total", "api-cost-seven-days"].map { try #require(probe.frames["metric.\($0)"]) }
                        let renderedRows = metricFrames.dropFirst().allSatisfy { abs($0.minX - metricFrames[0].minX) < 1 }
                        #expect(renderedRows == (expectedLayout == .rows))
                        let peak = try #require(probe.frames["analysis.peak"])
                        #expect(viewport.contains(peak))
                        let fixture = Fixture(
                            identifier: "analysis-\(scenario.rawValue)-outer-\(Int(width))-\(language)-\(appearance.rawValue)",
                            contentSize: host.bounds.size, language: language, appearance: appearance,
                            presentationCards: [Fixture.healthyCodexCard], accountDailyUsage: days)
                        if scenario == .longValues {
                            capture(host: host, fixture: fixture, suffix: "initial")
                            let scrollView = try #require(scrollView(in: host))
                            let finalRowIdentifier = "table-row.\(analysis.knownSlots.last!.day)"
                            probe.clearFrame(for: finalRowIdentifier)
                            scrollToBottom(scrollView)
                            probe.requestCurrentFrames()
                            settle(host)
                            let finalRow = try #require(probe.frames[finalRowIdentifier])
                            let finalViewport = try #require(probe.frames["scroll.viewport"])
                            #expect(finalViewport.contains(finalRow), "\(receipt): final daily row must be fully visible after vertical scrolling")
                            capture(host: host, fixture: fixture, suffix: "final")
                        } else {
                            capture(host: host, fixture: fixture)
                        }
                        // 1280 is a wide normal fixture, not native fullscreen evidence.
                        // Frames and style policy are not a glyph-baseline or visual PASS.
                    }
                }
            }
        }
    }

    @Test("metrics use shared single-line columns or common full-width rows without splitting numbers")
    func sharedMetricTypography() {
        #expect(CodexDashboardMetricTypography.pointSize == 18)
        #expect(CodexDashboardMetricTypography.nativeFont.pointSize == 18)
        let ordinary = ["1.41B", "24.07B", "US$57.95"]
        let long = ["9,223,372,036,854,775,807", "9,223,372,036,854,775,807", "US$1,234,567,890,123.45"]
        #expect(CodexDashboardMetricTypography.layout(values: ordinary, availableWidth: 518) == .columns)
        #expect(CodexDashboardMetricTypography.layout(values: long, availableWidth: 518) == .rows)
        #expect(CodexDashboardMetricTypography.layout(values: long, availableWidth: 1200) == .columns)
        for value in ordinary + long + ["US$0.01", "US$100.00", "1\u{202f}234\u{202f}567,89\u{00a0}$US"] {
            let metric = CodexDashboardProjection.Metric(id: "fixture", value: value, period: .sevenDays,
                unit: .tokens, coveragePercent: nil, capturedAt: nil)
            let shown = CodexDashboardMetricTypography.displayValue(metric, fullWidth: 518)
            #expect(shown == value)
            #expect(!shown.contains("\n"))
            #expect(CodexDashboardMetricTypography.measuredWidth(shown) <= 518)
        }
        // Style and width policy checks do not inspect rasterized glyph baselines.
    }

    @Test("axis ticks share their visual and accessible scale for zero odd and Int64 maxima")
    func axisTickScaleIsConsistent() {
        let zero = CodexDashboardAxisTicks.ticks(maximumTokens: 0)
        #expect(zero.map(\.visualText) == ["0", "0", "0"])
        #expect(zero.map(\.accessibilityText) == zero.map(\.visualText))

        let odd = CodexDashboardAxisTicks.ticks(maximumTokens: 7)
        #expect(odd.map(\.visualText) == ["7", "3.5", "0"])
        #expect(odd.map(\.accessibilityText) == odd.map(\.visualText))

        let extreme = CodexDashboardAxisTicks.ticks(maximumTokens: .max)
        #expect(extreme.map(\.visualText) == ["9.2E18", "4.6E18", "0"])
        #expect(extreme.map(\.accessibilityText) == extreme.map(\.visualText))
        #expect(AnalysisFixture.days(values: [.max]).first?.tokens == .max)
    }

    @Test("amount beyond full width is explicitly approximate with the original accessible")
    func extremeAmountPresentation() throws {
        for language: AppLanguage in [.english, .simplifiedChinese] {
            let store = UsageStore.preview(language: language, presentationCards: [Fixture.healthyCodexCard],
                accountDailyUsage: AnalysisFixture.complete.days)
            var snapshot = store.snapshot
            snapshot.apiCostEstimate = APICostEstimateSnapshot(sevenDayUSD: Double.greatestFiniteMagnitude,
                lifetimeUSD: Double.greatestFiniteMagnitude, coveragePercent: 89, modelNames: [])
            let projection = CodexDashboardProjection(snapshot: snapshot, provider: store.productInventory.provider(.codex))
            let metric = try #require(projection.metrics.first { $0.id == "api-cost-seven-days" })
            let original = try #require(metric.value)
            #expect(CodexDashboardMetricTypography.measuredWidth(original) > 518)
            let shown = CodexDashboardMetricTypography.displayValue(metric, fullWidth: 518)
            #expect(shown.hasPrefix("≈ USD "))
            #expect(!shown.contains("\n"))
            #expect(CodexDashboardMetricTypography.measuredWidth(shown) <= 518)
            let probe = AgentDashboardLayoutProbe()
            let host = NSHostingView(rootView: AgentWorkspaceSurface(store: store, providerID: .codex,
                refresh: {}, connectCodex: {}, disconnectCodex: {}, claudeControlState: { .consentRequired },
                connectClaude: {}, claudeAccuracySync: {}, layoutProbe: probe, fixtureProjection: projection))
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 550, height: 800),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            settle(host)
            #expect(probe.frames["metrics.rows"] != nil)
            let frame = try #require(probe.frames["metric-value.api-cost-seven-days"])
            #expect(frame.height == CodexDashboardMetricTypography.lineHeight)
            #expect(frame.width + 1 >= CodexDashboardMetricTypography.measuredWidth(shown))
        }
    }

    @Test("full seven-day overflow is displayed as overflow rather than missing coverage")
    func overflowStatusPresentation() throws {
        for language: AppLanguage in [.english, .simplifiedChinese] {
            let days = AnalysisFixture.days(values: [Int64.max, 1, 0, 0, 0, 0, 0])
            let store = UsageStore.preview(language: language, presentationCards: [Fixture.healthyCodexCard], accountDailyUsage: days)
            let projection = CodexDashboardProjection(snapshot: store.snapshot, provider: store.productInventory.provider(.codex))
            #expect(projection.dailyAnalysis().unavailabilityReason == .overflow)
            #expect(projection.dailyAnalysis().knownSlots.count == 7)
            let probe = AgentDashboardLayoutProbe()
            let host = NSHostingView(rootView: AgentWorkspaceSurface(store: store, providerID: .codex,
                refresh: {}, connectCodex: {}, disconnectCodex: {}, claudeControlState: { .consentRequired },
                connectClaude: {}, claudeAccuracySync: {}, layoutProbe: probe))
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 700, height: 900),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            settle(host)
            let message = CodexDashboardProjection.DailyAnalysis.UnavailabilityReason.overflow.message(isChinese: language == .simplifiedChinese)
            #expect(!message.isEmpty)
            #expect(probe.frames["analysis-status.overflow"] != nil)
            #expect(probe.frames["analysis-status.missingDays"] == nil)
            #expect(probe.frames["analysis.mean-line"] == nil)
            #expect(probe.frames["table.share-header"] == nil)
            #expect(probe.frames["table.cumulative-header"] == nil)
        }
    }

    private enum AnalysisFixture: String {
        case complete, allZero, longValues

        var days: [AgentAccountUsageDay] {
            switch self {
            case .complete: return Self.days(values: [0, 100, 200, 200, 50, 50, 100])
            case .allZero: return Self.days(values: Array(repeating: 0, count: 7))
            case .longValues: return Self.days(values: [0, 123_456_789, 234_567_890, 345_678_901, 456_789_012, 567_890_123, 678_901_234])
            }
        }

        static func days(values: [Int64]) -> [AgentAccountUsageDay] {
            let calendar = Calendar.current
            let anchor = calendar.startOfDay(for: Date())
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return values.enumerated().map { index, value in
                .init(day: formatter.string(from: calendar.date(byAdding: .day, value: index - 6, to: anchor)!), tokens: value)
            }
        }
    }

    private func settle(_ host: NSView) {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
    }

    private func assertFirstScreen(_ probe: AgentDashboardLayoutProbe, expectedDays: Int = 6) {
        let viewport = try! #require(probe.frames["scroll.viewport"])
        let document = try! #require(probe.frames["scroll.document"])
        let quotas = ["quota.seven-day", "quota.five-hour"].map { try! #require(probe.frames[$0]) }
        let metrics = ["metric.week", "metric.total", "metric.api-cost-seven-days"].map { try! #require(probe.frames[$0]) }
        let trend = try! #require(probe.frames["trend"])
        #expect(quotas.allSatisfy(viewport.contains))
        #expect(metrics.allSatisfy(viewport.contains))
        #expect(viewport.contains(trend))
        #expect(quotas.allSatisfy { $0.minY < metrics[0].minY })
        #expect(metrics.prefix(2).allSatisfy { $0.maxY <= trend.minY })
        #expect(metrics.allSatisfy { $0.maxY <= trend.minY })
        let metricRows = metrics.dropFirst().allSatisfy { abs($0.minX - metrics[0].minX) < 1 }
        if metricRows {
            #expect(metrics[0].maxY <= metrics[1].minY)
            #expect(metrics[1].maxY <= metrics[2].minY)
        } else {
            #expect(metrics[0].maxX < metrics[1].minX)
            #expect(metrics[1].maxX < metrics[2].minX)
        }
        let values = ["week", "total", "api-cost-seven-days"].map { try! #require(probe.frames["metric-value.\($0)"]) }
        // Shared cell geometry only. These frames do not measure glyph baselines
        // or prove rasterized font equality; independent visual QA remains open.
        if metricRows {
            #expect(values.allSatisfy { abs($0.maxX - values[0].maxX) < 1 })
        } else {
            #expect(values.allSatisfy { abs($0.minY - values[0].minY) < 1 })
        }
        #expect(values.allSatisfy { abs($0.height - CodexDashboardMetricTypography.lineHeight) < 1 })
        #expect(abs(quotas[0].minY - quotas[1].minY) < 1)
        let quotaTitles = ["quota-title.seven-day", "quota-title.five-hour"].map { try! #require(probe.frames[$0]) }
        let quotaRails = ["quota-rail.seven-day", "quota-rail.five-hour"].map { try! #require(probe.frames[$0]) }
        #expect(abs(quotaTitles[0].minY - quotaTitles[1].minY) < 1)
        #expect(abs(quotaRails[0].minY - quotaRails[1].minY) < 1)
        let details = try! #require(probe.frames["details"])
        let table = try! #require(probe.frames["daily-table"])
        let tableHeader = try! #require(probe.frames["table.header"])
        #expect(document.contains(table))
        #expect(table.minX >= document.minX)
        #expect(table.maxX <= document.maxX)
        #expect(viewport.intersects(tableHeader))
        if metricRows {
            // Full-width original metric values add a vertical row. The table must
            // remain reachable in the document without horizontal overflow.
            #expect(table.minY >= viewport.minY)
        } else {
            #expect(viewport.contains(table))
        }
        #expect(probe.frames["day-detail"] != nil)
        if document.width - 32 >= 900 {
            #expect(trend.maxX < details.minX)
            #expect(abs(trend.minY - details.minY) < 1)
        } else {
            #expect(trend.maxY <= details.minY)
            #expect(abs(trend.width - (document.width - 32)) < 2)
        }
        let visibleDays = probe.frames.keys.filter { $0.hasPrefix("day.") }
        #expect(visibleDays.count == expectedDays) // Derived from each fixture; unknown is never a mark.
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

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = scrollView(in: subview) { return scrollView }
        }
        return nil
    }

    private func scrollToBottom(_ scrollView: NSScrollView) {
        guard let document = scrollView.documentView else { return }
        let y = max(document.bounds.minY, document.bounds.maxY - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: .init(x: scrollView.contentView.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
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
                id: CodexUsageConnector.connectorID.rawValue, providerName: "Codex", planLabel: freshness == .unavailable ? "unknown" : "pro",
                connectionStatus: freshness == .unavailable ? .unavailable : .connected,
                freshness: freshness, windows: windows, selectedWindowID: selected, remaining: remaining,
                sourceDescription: "Test-only dashboard fixture", severity: .normal,
                isRetainingLastValidValue: false, capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }
}
