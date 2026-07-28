import AppKit
import CoreText
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.11-G2 compact visual system")
struct UMA011G2VisualSystemTests {
    @Test("Compact panel metrics preserve equal provider geometry")
    func compactPanelMetrics() {
        #expect(UsagePanelMetrics.width == 370)
        #expect(UsagePanelMetrics.minimumHeight == 125)
        #expect(UsagePanelMetrics.headerHeight == 64)
        #expect(UsagePanelMetrics.collapsedProviderCardHeight == 74)
        #expect(UsagePanelMetrics.cardSpacing == 8)
        #expect(UsagePanelMetrics.outerTopInset == UsagePanelMetrics.outerBottomInset)
        #expect(UsagePanelMetrics.collapsedProviderContribution == 82)
        #expect(UsagePanelMetrics.resolvedContentHeight(10_000) == UsagePanelMetrics.height)
    }

    @Test("Serif labels and tabular values have separate centralized families")
    func typographyFamilies() {
        for role in [
            AppTypographyRole.display,
            .sectionTitle,
            .cardTitle,
            .body,
            .secondary,
            .caption,
            .action,
            .assistantProvider,
            .assistantDetail
        ] {
            #expect(role.family == .serif)
            #expect(!role.usesTabularDigits)
        }
        for role in [
            AppTypographyRole.largeValue,
            .regularValue,
            .compactValue,
            .menuBarValue,
            .assistantValue
        ] {
            #expect(role.family == .system)
            #expect(role.usesTabularDigits)
        }
        #expect(AppTypographyRole.technicalMono.family == .monospaced)
    }

    @Test("Public system serif resolves safely and CJK has real coverage")
    func serifAndCJKResolution() {
        let body = AppTypography.nsFont(.body)
        let base = CTFontCreateWithFontDescriptor(
            body.fontDescriptor as CTFontDescriptor,
            body.pointSize,
            nil
        )
        let cjk = CTFontCreateForString(
            base,
            "中文，。UMA" as CFString,
            CFRange(location: 0, length: 5)
        )
        let baseName = CTFontCopyPostScriptName(base) as String
        let cjkName = CTFontCopyPostScriptName(cjk) as String

        #expect(!baseName.isEmpty)
        #expect(!cjkName.isEmpty)
        #expect(!baseName.localizedCaseInsensitiveContains("Anthropic"))
        #expect(!cjkName.localizedCaseInsensitiveContains("LastResort"))
    }

    @Test("Numeric metrics remain tabular and stable across large values")
    func stableNumericWidths() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: AppTypography.nsFont(.assistantValue)
        ]
        let narrow = ("111%" as NSString).size(withAttributes: attributes).width
        let wide = ("888%" as NSString).size(withAttributes: attributes).width
        #expect(abs(narrow - wide) < 0.01)

        let large = ("$999.99B" as NSString).size(withAttributes: attributes).width
        #expect(large.isFinite)
        #expect(large > 0)
    }

    @Test("WorkBuddy exact values use the centralized numeric family")
    func workBuddyNumericTypography() throws {
        let card = try source(
            "Sources/CodexUsageUI/Views/WorkBuddyMainPanelCard.swift"
        )

        #expect(
            card.contains(
                "Text(presentation.compactValue)\n"
                    + "                        .font(AppTypography.numericFont(19, weight: .bold))"
            )
        )
        #expect(
            card.contains(
                "Text(presentation.availableText)\n"
                    + "                    .font(AppTypography.numericFont(17, weight: .bold))"
            )
        )
        #expect(!card.contains("AppTypography.font(19, weight: .bold"))
        #expect(!card.contains("AppTypography.font(17, weight: .bold"))
    }

    @Test("Unlimited five-hour detail never regains dominant styling")
    func unlimitedFiveHourDeemphasis() throws {
        let fiveHour = UsagePeriod(
            id: "provider.unlimited-five-hour",
            title: "5-Hour Limit",
            remainingPercent: 100,
            isFiveHour: true,
            isUnlimited: true,
            resetText: "—"
        )
        let sevenDay = UsagePeriod(
            id: "seven-day",
            title: "7-Day Limit",
            remainingPercent: 71,
            isFiveHour: false,
            resetText: "Resets later"
        )

        #expect(
            !UsageQuotaVisualPolicy.isPrimary(
                period: fiveHour,
                selectedWindowID: fiveHour.id
            )
        )
        #expect(
            UsageQuotaVisualPolicy.isPrimary(
                period: sevenDay,
                selectedWindowID: sevenDay.id
            )
        )

        let legacyJSON = Data(
            """
            {"id":"legacy","title":"Legacy","remainingPercent":42,"isUnlimited":false,"resetText":"—"}
            """.utf8
        )
        let legacy = try JSONDecoder().decode(UsagePeriod.self, from: legacyJSON)
        #expect(legacy.isFiveHour == nil)
    }

    @Test("Zero-priced Token Cost fails closed without fabricating zero dollars")
    func tokenCostRequiresPricedCoverage() {
        let zeroCoverage = APICostEstimateSnapshot(
            sevenDayUSD: 0,
            lifetimeUSD: 0,
            coveragePercent: 0,
            modelNames: []
        )
        let priced = APICostEstimateSnapshot(
            sevenDayUSD: 12.34,
            lifetimeUSD: 56.78,
            coveragePercent: 1,
            modelNames: ["GPT-5.6"]
        )
        let negative = APICostEstimateSnapshot(
            sevenDayUSD: -0.01,
            lifetimeUSD: 56.78,
            coveragePercent: 100,
            modelNames: []
        )
        let nonfinite = APICostEstimateSnapshot(
            sevenDayUSD: .infinity,
            lifetimeUSD: 56.78,
            coveragePercent: 100,
            modelNames: []
        )
        let impossibleCoverage = APICostEstimateSnapshot(
            sevenDayUSD: 12.34,
            lifetimeUSD: 56.78,
            coveragePercent: 101,
            modelNames: []
        )

        #expect(APICostVisualPolicy.displayableEstimate(nil) == nil)
        #expect(
            APICostVisualPolicy.displayableEstimate(zeroCoverage) == nil
        )
        #expect(APICostVisualPolicy.displayableEstimate(negative) == nil)
        #expect(APICostVisualPolicy.displayableEstimate(nonfinite) == nil)
        #expect(
            APICostVisualPolicy.displayableEstimate(impossibleCoverage) == nil
        )
        #expect(
            APICostVisualPolicy.displayableEstimate(priced)?.sevenDayUSD
                == 12.34
        )
    }

    @Test("Adaptive material rebuilds when effective appearance changes")
    func adaptiveMaterialTracksAppearance() throws {
        let source = try source(
            "Sources/CodexUsageMonitor/App/AdaptivePanelMaterialHostView.swift"
        )
        #expect(source.contains("override func viewDidChangeEffectiveAppearance()"))
        #expect(source.contains("super.viewDidChangeEffectiveAppearance()"))
        #expect(source.contains("rebuildMaterial()"))
    }

    @Test("Settings shrink to content and cap long content at panel height")
    func naturalSettingsSizing() {
        let maximumCardHeight =
            UsagePanelMetrics.height
                - UsageSettingsSizing.panelTopOffset
                - UsageSettingsSizing.panelBottomInset
        let compactCard = UsageSettingsSizing.cardHeight(
            contentHeight: 210,
            maximumHeight: maximumCardHeight
        )
        let longCard = UsageSettingsSizing.cardHeight(
            contentHeight: 2_000,
            maximumHeight: maximumCardHeight
        )

        #expect(compactCard == 238)
        #expect(
            UsageSettingsSizing.panelHeight(cardHeight: compactCard)
                == 330
        )
        #expect(longCard == maximumCardHeight)
        #expect(
            UsageSettingsSizing.panelHeight(cardHeight: longCard)
                == UsagePanelMetrics.height
        )
    }

    @Test("Compact WorkBuddy entry-mode labels fit the fixed Settings width")
    func compactWorkBuddyEntryModeLabels() {
        #expect(
            WorkBuddyCreditCompanionField.allCases.map {
                AppLanguage.english.workBuddyCompanionCompactName($0)
            } == ["Available", "Used", "Total", "Both"]
        )
        #expect(
            WorkBuddyCreditCompanionField.allCases.map {
                AppLanguage.simplifiedChinese
                    .workBuddyCompanionCompactName($0)
            } == ["可用", "已用", "总额", "两者"]
        )
    }

    @Test("Medium glass uses one inset contour and restrained edge mass")
    func glassAndContourContract() throws {
        let design = try source("Sources/CodexUsageUI/Support/DesignSystem.swift")
        let tuning = try source("Sources/CodexUsageUI/Models/GlassTuning.swift")
        let assistant = try source("Sources/CodexUsageUI/Views/DesktopAssistantView.swift")
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")

        #expect(tuning.contains("panelTintPercent: 32"))
        #expect(tuning.contains("cardMaterialPercent: 72"))
        #expect(tuning.contains("cardWhiteLayerPercent: 12"))
        #expect(design.contains("AnyShapeStyle(.thinMaterial)"))
        #expect(design.contains(".strokeBorder("))
        #expect(!design.contains("radius: usesReducedTransparency ? 2 : 5"))
        #expect(assistant.contains(".strokeBorder("))
        #expect(panel.contains(".strokeBorder("))
    }

    @Test("Settings never composites provider materials behind its glass")
    func settingsSingleShell() throws {
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let settings = try source("Sources/CodexUsageUI/Views/UsageSettingsCard.swift")

        #expect(panel.contains("private var settingsBackdrop"))
        #expect(panel.contains("if isShowingSettings {\n                settingsBackdrop"))
        #expect(
            !panel.contains(
                "panelContent\n                    .opacity(0.14)"
            )
        )
        #expect(settings.occurrenceCount(of: "GlassCardBackground") == 1)
        #expect(settings.contains("AppGlass.settingsReadabilityFillOpacity"))
        #expect(settings.occurrenceCount(of: "ScrollView(.vertical)") == 1)
    }

    @Test("Expanded provider details keep one continuous card shell")
    func attachedProviderDetails() throws {
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let provider = try #require(
            panel.slice(
                from: "private struct LocalLiveProviderCard",
                to: "private struct UsagePanelContentHeightPreferenceKey"
            )
        )

        #expect(provider.occurrenceCount(of: "GlassCardBackground") == 1)
        #expect(provider.contains("showsBackground: false"))
        #expect(provider.contains("Divider()"))
        #expect(!provider.contains(".fill(.regularMaterial)"))
        #expect(!provider.contains(".fill(.thinMaterial)"))
    }

    @Test("Five-hour secondary treatment is materially smaller")
    func secondaryQuotaTreatment() {
        #expect(
            UsageQuotaVisualMetrics.secondaryTitleSize
                < UsageQuotaVisualMetrics.primaryTitleSize
        )
        #expect(
            UsageQuotaVisualMetrics.secondaryValueSize
                < UsageQuotaVisualMetrics.primaryValueSize
        )
        #expect(
            UsageQuotaVisualMetrics.secondaryBarHeight
                <= UsageQuotaVisualMetrics.primaryBarHeight / 4
        )
        #expect(
            UsageQuotaVisualMetrics.secondaryVerticalInset
                < UsageQuotaVisualMetrics.primaryVerticalInset
        )
    }

    @Test("Token Cost large values have deterministic clipping protection")
    func tokenCostLayoutProtection() throws {
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let cost = try #require(
            panel.slice(
                from: "private struct APICostEstimateCard",
                to: "private struct ProviderExpansionToolbar"
            )
        )
        #expect(cost.contains("AppTypography.numericFont(25, weight: .bold)"))
        #expect(cost.contains("AppTypography.numericFont(15, weight: .bold)"))
        #expect(cost.occurrenceCount(of: ".minimumScaleFactor(") >= 3)
        #expect(cost.contains(".lineLimit(1)"))
        #expect(
            cost.contains(
                "guard let estimate = displayableEstimate else { return \"—\" }"
            )
        )
    }

    @Test("Assistant geometry and Minimalist content remain frozen")
    func assistantGeometry() throws {
        #expect(DesktopAssistantMetrics.regularWidth == 210)
        #expect(DesktopAssistantMetrics.regularHeight == 60)
        #expect(DesktopAssistantMetrics.minimalistWidth == 58.333333)
        #expect(DesktopAssistantMetrics.minimalistHeight == 30)
        #expect(DesktopAssistantMetrics.minimalistReservedWindowWidth == 0)
        #expect(DesktopAssistantMetrics.percentageFontSize == 13)
        #expect(
            DesktopAssistantContentContract.visibleFields(for: .minimalist)
                == [.providerConnectionMark, .percentage]
        )
    }

    @Test("No proprietary font asset or Claude runtime dependency is admitted")
    func fontPackageSafety() throws {
        let root = repositoryRoot()
        let design = try source("Sources/CodexUsageUI/Support/DesignSystem.swift")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        )
        var prohibitedAssets: [String] = []
        for case let url as URL in enumerator {
            if ["ttf", "otf", "ttc", "woff", "woff2"].contains(
                url.pathExtension.lowercased()
            ) {
                prohibitedAssets.append(url.path)
            }
        }

        #expect(prohibitedAssets.isEmpty)
        #expect(!design.contains("Font.custom"))
        #expect(!design.contains("/Applications/Claude.app"))
        #expect(!design.contains("Bundle(path:"))
    }

    @Test("Renderer covers dense provider and expanded-card matrices")
    func rendererMatrixContract() throws {
        let renderer = try source("Sources/PreviewRendererTool/main.swift")

        #expect(renderer.contains("static func main() async {"))
        #expect(!renderer.contains("static func main() async throws"))
        #expect(renderer.contains("try await run()"))
        #expect(renderer.contains("startupDiagnostic(for: error)"))
        #expect(!renderer.contains("\\(error)"))
        #expect(!renderer.contains("localizedDescription"))
        #expect(
            renderer.contains(
                "FileManager.default.createDirectory("
            )
        )
        #expect(
            renderer.contains(
                "at: outputURL.deletingLastPathComponent()"
            )
        )
        #expect(renderer.contains("NSApp.run()"))
        #expect(renderer.contains("--synthetic-providers="))
        #expect(renderer.contains("--all-expanded"))
        #expect(renderer.contains("--workbuddy-only"))
        #expect(renderer.contains("--workbuddy-value="))
        #expect(renderer.contains("--wallpaper="))
        #expect(renderer.contains("--large-text"))
        #expect(
            renderer.contains(
                "AppTypography.configurePreviewPointSizeScale("
            )
        )
        #expect(renderer.contains("percent: percent"))
        #expect(renderer.contains("--settings-agent="))
        #expect(renderer.contains("--workbuddy-account-web-failed"))
        #expect(
            renderer.contains(
                "renderedHeightOverride: interactive ? nil : panelHeight"
            )
        )
        #expect(renderer.contains("Let that bounded layout cycle"))
        #expect(renderer.contains("interactiveHeightUpdate"))
        #expect(renderer.contains("makeSyntheticCards("))
        #expect(renderer.contains("DesktopAssistantMetrics.stackSize("))
        #expect(renderer.contains("UMA 0.11-G2 Visual Review Candidate"))

        let store = try source("Sources/CodexUsageUI/Stores/UsageStore.swift")
        #expect(
            store.contains(
                "PreviewRenderer.AgentSettings.\\(UUID().uuidString)"
            )
        )

        let accountWeb = try source(
            "Sources/CodexUsageUI/Services/WorkBuddyAccountWebSessionController.swift"
        )
        #expect(accountWeb.contains("public static func previewFailed("))
        #expect(
            accountWeb.contains(
                "preview.account-web.\\(UUID().uuidString)"
            )
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }

    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(
                of: end,
                range: startRange.upperBound..<endIndex
              ) else {
            return nil
        }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
