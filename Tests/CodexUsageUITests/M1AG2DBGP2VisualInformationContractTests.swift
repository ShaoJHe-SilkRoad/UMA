import AppKit
import SwiftUI
import Testing
@testable import CodexUsageUI

struct M1AG2DBGP2VisualInformationContractTests {
    @Test
    func finderLauncherClearsOnlyFinderDisplayMetadataBeforeOpeningCandidate() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let installer = try String(
            contentsOf: repositoryRoot.appendingPathComponent("script/install_uma_p2_review.sh"),
            encoding: .utf8
        )
        let finderInfoRemoval = try #require(
            installer.range(
                of: #"metadataCleaner.arguments = ["-d", "com.apple.FinderInfo", candidate.path]"#
            )
        )
        let candidateOpen = try #require(
            installer.range(of: #"NSWorkspace.shared.openApplication("#)
        )

        #expect(installer.contains(
            #"metadataCleaner.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")"#
        ))
        #expect(finderInfoRemoval.upperBound <= candidateOpen.lowerBound)
    }

    @Test
    func collapsedCoreCannotFallBelowItsSafePanelHeight() {
        #expect(UsagePanelMetrics.outerInset == 16)
        #expect(UsagePanelMetrics.minimumHeight == 330)
        #expect(UsagePanelMetrics.collapsedHeight == 360)
        #expect(UsagePanelMetrics.height == 740)
        #expect(
            UsagePanelMetrics.presentedHeight(
                showsRealData: false,
                moreInfoExpanded: false,
                recentTaskCount: 0,
                meteredPeriodCount: 0,
                settingsPresented: false
            ) == UsagePanelMetrics.minimumHeight
        )
        #expect(
            UsagePanelMetrics.presentedHeight(
                showsRealData: true,
                moreInfoExpanded: false,
                recentTaskCount: 0,
                meteredPeriodCount: 1,
                settingsPresented: false
            ) == 360
        )
        #expect(
            UsagePanelMetrics.presentedHeight(
                showsRealData: true,
                moreInfoExpanded: true,
                recentTaskCount: 0,
                meteredPeriodCount: 1,
                settingsPresented: false
            ) == 560
        )
        #expect(
            UsagePanelMetrics.presentedHeight(
                showsRealData: true,
                moreInfoExpanded: true,
                recentTaskCount: 3,
                meteredPeriodCount: 1,
                settingsPresented: false
            ) == 710
        )
        #expect(
            UsagePanelMetrics.presentedHeight(
                showsRealData: true,
                moreInfoExpanded: true,
                recentTaskCount: 3,
                meteredPeriodCount: 2,
                settingsPresented: false
            ) == 740
        )
        #expect(
            UsagePanelMetrics.presentedHeight(
                showsRealData: true,
                moreInfoExpanded: false,
                recentTaskCount: 3,
                meteredPeriodCount: 2,
                settingsPresented: false
            ) == 390
        )
        #expect(
            UsagePanelMetrics.preferredHeight(
                showUsageSummary: false,
                showRecentTasks: false,
                showAPICost: false
            ) == UsagePanelMetrics.collapsedHeight
        )
        #expect(UsagePanelMetrics.settingsMinimumHeight >= UsagePanelMetrics.collapsedHeight)
    }

    @Test
    func disclosureAndSyncCopyAreConciseAndLocalized() {
        let time = Date(timeIntervalSince1970: 1_784_332_800)
        #expect(AppLanguage.english.moreInfo == "More info")
        #expect(AppLanguage.english.lessInfo == "Less info")
        #expect(AppLanguage.simplifiedChinese.moreInfo == "更多信息")
        #expect(AppLanguage.simplifiedChinese.lessInfo == "收起信息")
        #expect(AppLanguage.english.syncedAt(time).hasPrefix("Synced "))
        #expect(AppLanguage.english.outdated == "Outdated")
        #expect(AppLanguage.english.connectionRefreshingTitle == "Refreshing")
        #expect(AppLanguage.simplifiedChinese.outdated == "已过期")
        #expect(AppLanguage.simplifiedChinese.connectionRefreshingTitle == "正在刷新")
        #expect(AppLanguage.english.remainingAccessibilityValue(94) == "94% remaining")
        #expect(AppLanguage.simplifiedChinese.remainingAccessibilityValue(94) == "剩余 94%")
        #expect(
            AppLanguage.english.quotaAccessibilityLabel(
                title: "7-Day Limit",
                remainingPercent: 94
            ) == "7-Day Limit, 94% remaining"
        )
        #expect(
            AppLanguage.simplifiedChinese.quotaAccessibilityLabel(
                title: "7 天限额",
                remainingPercent: 94
            ) == "7 天限额, 剩余 94%"
        )
    }

    @Test @MainActor
    func collapsedExpandedAndSettingsFixturesRenderWithoutAStateMigration() {
        let store = UsageStore.preview(language: .english)
        for (expanded, settings) in [
            (false, false),
            (true, false),
            (false, true)
        ] {
            let expectedHeight = UsagePanelMetrics.presentedHeight(
                showsRealData: true,
                moreInfoExpanded: expanded,
                recentTaskCount: store.presentedRecentTaskCount,
                meteredPeriodCount: store.presentedMeteredPeriodCount,
                settingsPresented: settings
            )
            let renderer = ImageRenderer(
                content: UsagePanelView(
                    store: store,
                    tuning: .final,
                    preferencesEnabled: false,
                    appKitAccessibilityEnabled: false,
                    settingsInitiallyPresented: settings,
                    moreInfoInitiallyPresented: expanded
                )
                .frame(width: UsagePanelMetrics.width, height: expectedHeight)
            )
            #expect(renderer.nsImage != nil)
        }
    }

    @Test @MainActor
    func shortScreenViewportKeepsExpandedContentScrollableInsteadOfClippingIt() {
        let store = UsageStore.preview(language: .english)
        let renderer = ImageRenderer(
            content: UsagePanelView(
                store: store,
                tuning: .final,
                preferencesEnabled: false,
                appKitAccessibilityEnabled: false,
                moreInfoInitiallyPresented: true
            )
            .frame(
                width: UsagePanelMetrics.width,
                height: 680,
                alignment: .top
            )
        )

        #expect(renderer.nsImage?.size.height == 680)
    }

    @Test
    func disclosureSettingsLanguageAndRelaunchStressKeepDeterministicGeometry() {
        var expanded = false
        for _ in 0..<100 {
            expanded.toggle()
            #expect(
                UsagePanelMetrics.presentedHeight(
                    showsRealData: true,
                    moreInfoExpanded: expanded,
                    recentTaskCount: 3,
                    meteredPeriodCount: 1,
                    settingsPresented: false
                ) == (expanded ? 710 : UsagePanelMetrics.collapsedHeight)
            )
        }
        #expect(expanded == false)

        var settings = false
        for _ in 0..<50 {
            settings.toggle()
            let height = UsagePanelMetrics.presentedHeight(
                showsRealData: true,
                moreInfoExpanded: false,
                recentTaskCount: 3,
                meteredPeriodCount: 1,
                settingsPresented: settings
            )
            #expect(height >= UsagePanelMetrics.collapsedHeight)
        }
        #expect(settings == false)

        var language = AppLanguage.english
        for _ in 0..<30 {
            language = language == .english ? .simplifiedChinese : .english
            #expect(!language.moreInfo.isEmpty)
        }
        #expect(language == .english)

        for _ in 0..<20 {
            // Disclosure and settings are intentionally session-local. A new
            // panel lifecycle therefore always restores the safe core state.
            #expect(
                UsagePanelMetrics.presentedHeight(
                    showsRealData: true,
                    moreInfoExpanded: false,
                    recentTaskCount: 3,
                    meteredPeriodCount: 1,
                    settingsPresented: false
                ) == UsagePanelMetrics.collapsedHeight
            )
        }
    }
}
