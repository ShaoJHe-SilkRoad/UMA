import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

struct UMAPublicIdentityTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test @MainActor
    func visibleProductIdentityIsUMAInBothLanguages() {
        #expect(AppLanguage.english.appTitle == "UMA")
        #expect(AppLanguage.simplifiedChinese.appTitle == "UMA")
        #expect(AppLanguage.english.quitApplication == "Quit UMA")
        #expect(AppLanguage.simplifiedChinese.quitApplication == "退出 UMA")
        #expect(AppLanguage.english.remainingAccessibilityLabel(percent: 72)
            == "UMA usage, 72% remaining")
        #expect(AppLanguage.simplifiedChinese.remainingAccessibilityLabel(percent: 72)
            == "UMA 剩余额度 72%")

        let englishAlert = NativeLocalCodexAccessConfirmation.copy(for: .english)
        let chineseAlert = NativeLocalCodexAccessConfirmation.copy(for: .simplifiedChinese)
        #expect(englishAlert.body.hasPrefix("UMA will connect"))
        #expect(chineseAlert.body.hasPrefix("UMA 将连接"))
    }

    @Test
    func localBuildCreatesUMAAppWhileRetainingTheInternalExecutable() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("script/build_and_run.sh"),
            encoding: .utf8
        )

        #expect(script.contains(#"INTERNAL_PRODUCT="CodexUsageMonitor""#))
        #expect(script.contains(#"APP_NAME="UMA""#))
        #expect(script.contains(#"FINAL_APP_BUNDLE="$DIST_DIR/$APP_NAME.app""#))
        #expect(script.contains("<string>$INTERNAL_PRODUCT</string>"))
        #expect(script.contains("<string>UMA</string>"))
        #expect(script.contains(#"BUNDLE_ID="com.kevinchen.CodexUsageMonitor""#))
    }

    @Test
    func developmentPackageUsesUMANameAndLegacyCompatibilityDomain() throws {
        let packageScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("script/package_uma_p2.sh"),
            encoding: .utf8
        )
        let installer = try String(
            contentsOf: repositoryRoot.appendingPathComponent("script/install_uma_p2_review.sh"),
            encoding: .utf8
        )

        #expect(packageScript.contains(#"APP_NAME="UMA""#))
        #expect(packageScript.contains(
            #"LEGACY_BUNDLE_ID="com.kevinchen.CodexUsageMonitor""#
        ))
        #expect(packageScript.contains("UMA-Development-Provenance.plist"))
        #expect(packageScript.contains("<key>CFBundleDisplayName</key><string>UMA</string>"))
        #expect(packageScript.contains("<key>CFBundleName</key><string>UMA</string>"))
        #expect(packageScript.contains("UMA-source-$commit.tar"))
        #expect(installer.contains(#"REVIEW_APP="$REVIEW_ROOT/$APP_NAME.app""#))
        #expect(installer.contains("/Users/juliushe/Desktop/UMA0.9_Review/UMA.app"))
    }

    @Test
    func readmePublishesTheRequiredPreviewAndCompatibilityContract() throws {
        let readme = try String(
            contentsOf: repositoryRoot.appendingPathComponent("README.md"),
            encoding: .utf8
        )

        #expect(readme.contains("# UMA"))
        #expect(readme.contains("## Usage Monitor Altoget"))
        #expect(readme.contains(
            "UMA 0.9 is a development preview. The current Codex connector and user interface have passed bounded functional and visual validation. Extended long-duration debugging is scheduled after this source push."
        ))
        #expect(readme.contains("dist/UMA.app"))
        #expect(readme.contains("outputs/UMA-preview-collapsed.png"))
        #expect(readme.contains("outputs/UMA-preview-expanded.png"))
        #expect(readme.contains("com.kevinchen.CodexUsageMonitor"))
        #expect(readme.contains("Application Support/CodexUsageMonitor"))
        #expect(readme.contains("https://github.com/ower93/CodexUsageMonitor"))
        #expect(readme.contains("https://github.com/ShaoJHe-SilkRoad/UMA"))
        #expect(!readme.contains("ower93/CodexUsageMonitor/releases"))
        #expect(!readme.localizedCaseInsensitiveContains("Claude Code"))
    }
}
