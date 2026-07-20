import AppKit
import CoreText
import SwiftUI
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

struct UMAFinalVisualCorrectionTests {
    @Test
    func disclosureCopyAndAccessibilityStateShareOneBoolean() {
        #expect(AppLanguage.english.disclosureLabel(isExpanded: false) == "More info")
        #expect(AppLanguage.english.disclosureLabel(isExpanded: true) == "Less info")
        #expect(AppLanguage.simplifiedChinese.disclosureLabel(isExpanded: false) == "更多信息")
        #expect(AppLanguage.simplifiedChinese.disclosureLabel(isExpanded: true) == "收起信息")
        #expect(AppLanguage.english.collapsedAccessibilityValue == "Collapsed")
        #expect(AppLanguage.english.expandedAccessibilityValue == "Expanded")
        #expect(AppLanguage.simplifiedChinese.collapsedAccessibilityValue == "已折叠")
        #expect(AppLanguage.simplifiedChinese.expandedAccessibilityValue == "已展开")
    }

    @Test @MainActor
    func nativeMaterialOwnsExactlyOneExteriorContour() {
        let host = AdaptivePanelMaterialHostView(
            frame: NSRect(x: 0, y: 0, width: 370, height: 402),
            cornerRadius: 28,
            fallbackMaterialOpacity: 0.44
        )
        host.installContentView(NSView(frame: host.bounds))

        if #available(macOS 26.0, *),
           !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            #expect(host.ownsExteriorContour)
            #expect(
                !UsagePanelExteriorContract.windowShadowEnabled(
                    materialOwnsExteriorContour: host.ownsExteriorContour
                )
            )
            #expect(host.subviews.count == 1)
            #expect(host.subviews.first is NSGlassEffectView)
        } else {
            #expect(!host.ownsExteriorContour)
            #expect(
                UsagePanelExteriorContract.windowShadowEnabled(
                    materialOwnsExteriorContour: host.ownsExteriorContour
                )
            )
        }
    }

    @Test @MainActor
    func bundledRobotoRegistersWithVerifiedPostScriptNames() throws {
        let registered = try UsageTypography.registerBundledFonts()
        #expect(registered == [
            "Roboto-Regular",
            "Roboto-Medium",
            "Roboto-Bold"
        ])
        for name in registered {
            #expect(NSFont(name: name, size: 12)?.fontName == name)
        }
    }

    @Test @MainActor
    func semanticRolesUseRobotoAndExplicitPingFangCascade() throws {
        try UsageTypography.registerBundledFonts()
        #expect(UsageTypography.cjkFallbackFamily == "PingFang SC")

        for role in UsageTypographyRole.allCases {
            let font = UsageTypography.appKitFont(role, language: .english)
            #expect(font.fontName.hasPrefix("Roboto"))
            #expect(UsageTypography.postScriptName(for: role).hasPrefix("Roboto-"))
            #expect(UsageTypography.cjkPostScriptName(for: role).hasPrefix("PingFangSC-"))
        }
    }

    @Test @MainActor
    func mixedLatinNumericAndChineseTextUsesTheDeclaredCascade() throws {
        try UsageTypography.registerBundledFonts()
        let font = UsageTypography.appKitFont(
            .applicationTitle,
            language: .simplifiedChinese
        )
        let attributed = NSAttributedString(
            string: "Codex 用量 79%",
            attributes: [.font: font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let runs = CTLineGetGlyphRuns(line) as NSArray as! [CTRun]
        let names: [String] = runs.map { run in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            return CTFontCopyPostScriptName(runFont) as String
        }

        #expect(names.contains(where: { $0.hasPrefix("Roboto-") }))
        #expect(names.contains(where: { $0.hasPrefix("PingFangSC-") }))
    }

    @Test @MainActor
    func englishAndChineseKeyLayoutsRenderWithoutMissingFonts() throws {
        try UsageTypography.registerBundledFonts()
        for language in AppLanguage.allCases {
            let store = UsageStore.preview(language: language)
            for expanded in [false, true] {
                let height = UsagePanelMetrics.presentedHeight(
                    showsRealData: true,
                    moreInfoExpanded: expanded,
                    recentTaskCount: store.presentedRecentTaskCount,
                    meteredPeriodCount: store.presentedMeteredPeriodCount,
                    settingsPresented: false
                )
                let renderer = ImageRenderer(
                    content: UsagePanelView(
                        store: store,
                        tuning: .final,
                        preferencesEnabled: false,
                        appKitAccessibilityEnabled: false,
                        moreInfoInitiallyPresented: expanded
                    )
                    .frame(width: UsagePanelMetrics.width, height: height)
                )
                #expect(renderer.nsImage?.size.width == UsagePanelMetrics.width)
                #expect(renderer.nsImage?.size.height == height)
            }
        }
    }

    @Test
    func packageCopiesOnlyRequiredRobotoWeightsAndLicense() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fontRoot = root.appendingPathComponent(
            "Sources/CodexUsageUI/Resources/Fonts/Roboto"
        )
        let expected = [
            "Roboto-Regular.ttf",
            "Roboto-Medium.ttf",
            "Roboto-Bold.ttf",
            "OFL.txt",
            "PROVENANCE.md"
        ]
        for resource in expected {
            #expect(
                FileManager.default.fileExists(
                    atPath: fontRoot.appendingPathComponent(resource).path
                )
            )
        }

        let packaged = try String(
            contentsOf: root.appendingPathComponent("script/package_uma_p2.sh"),
            encoding: .utf8
        )
        for resource in expected {
            #expect(packaged.contains(resource))
        }
        #expect(!packaged.contains("Roboto-Light.ttf"))
        #expect(!packaged.contains("Roboto-Black.ttf"))
    }
}
