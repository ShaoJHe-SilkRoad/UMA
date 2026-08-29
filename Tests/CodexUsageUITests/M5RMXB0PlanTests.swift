import Foundation
import Testing

@Suite("M5RMX-B0 Claude completion baseline")
struct M5RMXB0PlanTests {
    @Test
    func governingSetLocksExactAcceptedLineageAndDestination() throws {
        let plan = try record("source/M5RMX_Plan.md")
        let goal = try record("source/M5RMX_Goal.md")
        let scope = try record("source/UMA M5RMX Scope Lock.md")

        #expect(plan.contains("**Version:** 3.0"))
        #expect(goal.contains("**Version:** 3.0"))
        #expect(plan.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy {
            !$0.hasSuffix(" ") && !$0.hasSuffix("\t")
        })
        #expect(goal.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy {
            !$0.hasSuffix(" ") && !$0.hasSuffix("\t")
        })
        for required in [
            "/Users/juliushe/Developer/UMA-M8-Kimi",
            "codex/uma-m8-kimi",
            "01b190260da857f55fa5fa9b14da9715cafbc221",
            "49f2af499c86b9b8757da0e9406a0d9e5c24495b",
            "/Users/juliushe/Developer/UMA-M5RMX-Claude",
            "codex/uma-m5rmx-claude",
        ] {
            #expect(scope.contains(required))
        }
        #expect(scope.contains("latest accepted local M8 lineage, not remote"))
        #expect(scope.contains("683/683 PASS"))
    }

    @Test
    func providerTruthAndCurrentCompletionLockRemainBoundedToSmartMode() throws {
        let scope = try record("source/UMA M5RMX Scope Lock.md")

        var previous = scope.startIndex
        for provider in ["1. Codex", "2. Claude Code", "3. WorkBuddy", "4. Google Antigravity"] {
            let range = try #require(scope.range(of: provider, range: previous..<scope.endIndex))
            previous = range.upperBound
        }
        #expect(scope.contains("Cursor and Kimi\nare unsupported/hidden"))
        #expect(scope.contains("**Current task:** `M5RMX Claude root-repair final closeout`"))
        #expect(scope.contains("does not authorize Apple\nsubmission"))
        #expect(scope.contains("provider ordering"))
    }

    @Test
    func currentSmartSourceAndHistoricalBrowserRecordAreUnambiguous() throws {
        let scope = try record("source/UMA M5RMX Scope Lock.md")
        let retrospective = try record("source/UMA M5RMX Retrospective.md")

        #expect(scope.contains("Current source ownership is Local Smart Mode"))
        #expect(scope.contains("Persistent five-minute Safari\ntracking"))
        #expect(scope.contains("are retired"))
        #expect(scope.contains("one-shot Accuracy Sync"))
        #expect(scope.contains("The prior Section 3 remains historical baseline"))
        for required in [
            "ClaudeCodeUsageConnector.swift",
            "ClaudeBrowserProductionIntegration.swift",
            "claude-usage-extractor.js",
            "SafariWebExtensionHandler.swift",
            "ClaudeBrowserNativeHost/main.swift",
            "ClaudeBrowserBridgeProtocol.swift",
            "ClaudeBrowserSanitizedCacheStore.swift",
            "ClaudeLocalActivityReader.swift",
            "script/package_uma_m5_g2.sh",
        ] {
            #expect(retrospective.contains(required))
        }
        for status in [
            "`ACCEPTED CURRENT`",
            "`ACCEPTED BUT NEEDS M5RMX COMPLETION`",
            "`HISTORICAL / RETIRED`",
            "`UNPROVEN / FUTURE`",
        ] {
            #expect(retrospective.contains(status))
        }
        #expect(retrospective.contains("Claude Browser Sync"))
        #expect(retrospective.contains("status-line"))
    }

    @Test
    func privacyAndB0NonOperationBoundaryAreExplicit() throws {
        let scope = try record("source/UMA M5RMX Scope Lock.md")
        let qa = try record("source/UMA M5RMX QA Issue Ledger.md")

        let policy = "Credential existence is not the problem; credential crossing into UMA is the problem."
        #expect(scope.contains(policy))
        #expect(qa.contains(policy))
        for prohibited in [
            "OAuth/access/refresh tokens",
            "cookies",
            "browser profiles",
            "Keychain secrets",
            "raw HTML",
            "broad DOM content",
            "broad process argv or environment inspection",
        ] {
            #expect(scope.contains(prohibited))
        }
        #expect(scope.contains("It performs no production/provider/\nApple/Desktop actions."))
        #expect(qa.contains("B0 performed no production/provider/Apple/Desktop actions."))
        #expect(scope.contains("No raw status-line payload, prompt/session content"))
        #expect(scope.contains("exact private Founder quota"))
    }

    @Test
    func extensionNativeHostAndPackageInventoryStayExact() throws {
        let scope = try record("source/UMA M5RMX Scope Lock.md")
        let retrospective = try record("source/UMA M5RMX Retrospective.md")

        for required in [
            "com.silkrd.uma.ClaudeBrowserCompanion",
            "com.apple.Safari.web-extension",
            "com.silkrd.uma.claude_browser",
            "https://claude.ai/new#settings/usage",
            "Contents/PlugIns/ClaudeBrowserCompanion.appex",
            "maximum message 4096 bytes",
            "ad-hoc default",
            "helper still declares 0.11",
        ] {
            #expect((scope + retrospective).contains(required))
        }
        #expect(scope.contains("requests exactly"))
        for permission in [
            "`nativeMessaging`",
            "`https://claude.ai/new*`",
        ] {
            #expect(scope.contains(permission))
        }
        #expect(!scope.contains("`storage`"))
        #expect(scope.contains("static content scripts or broad host permissions."))
    }

    @Test
    func AppleDesktopAndRemoteDiscrepancyRemainRecordOnly() throws {
        let scope = try record("source/UMA M5RMX Scope Lock.md")

        for required in [
            "C6TUZVJ6SJ",
            "UMA-notary",
            "APPLE-G1 BLOCKED — APPLE NOTARY BACKEND / SUPPORT INVESTIGATION",
            "FB24386147",
            "20000140194585",
            "/private/tmp/uma-apple-g1-smoke-01b1902/UMAAppleG1Smoke.app",
            "/private/tmp/uma-apple-g1-smoke-01b1902/UMAAppleG1Smoke.zip",
            "/Users/juliushe/Desktop/UMA_0.11.app",
            "88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a",
            "https://github.com/ShaoJHe-SilkRoad/UMA.git",
            "https://github.com/ShaoJHe-SilkRoad/CodexUsageMonitor",
        ] {
            #expect(scope.contains(required))
        }
        #expect(scope.contains("No B0 remote URL mutation or remote action is\nallowed."))
    }

    private func record(_ relativePath: String) throws -> String {
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
