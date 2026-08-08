import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M4-N Manus API-key product-path retirement")
struct M4NManusRetirementTests {
    @Test
    func productionSourceContainsNoCallableManusRoute() throws {
        let source = try productionSource()
        let forbidden = [
            "ManusUsageConnector",
            "ManusSettingsModel",
            "ManusAPIKeyStore",
            "ManusCreditsAPIClient",
            "ManusRefreshScheduler",
            "officialRemoteUsageAPI",
            "currentOfficialRemoteRead",
            "umaOwnedKeychainCredential",
            "/v2/usage.availableCredits",
            "x-manus-api-key",
            "com.silkrd.uma.manus-api-v2",
            "Connect Manus",
            "Save and Verify",
        ]

        for token in forbidden {
            #expect(!source.contains(token), "Production source retained \(token)")
        }
    }

    @Test
    func rejectedManusOnlySourceFilesAreAbsent() {
        let root = repositoryRoot()
        let removedPaths = [
            "Sources/CodexUsageUI/Connectors/ManusUsageConnector.swift",
            "Sources/CodexUsageUI/Models/AppLanguage+Manus.swift",
            "Sources/CodexUsageUI/Models/ManusCredits.swift",
            "Sources/CodexUsageUI/Services/ManusAPIKeyStore.swift",
            "Sources/CodexUsageUI/Services/ManusCreditsAPIClient.swift",
            "Sources/CodexUsageUI/Services/ManusRefreshScheduler.swift",
            "Sources/CodexUsageUI/Stores/ManusSettingsModel.swift",
        ]

        for path in removedPaths {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "Rejected runtime file remains: \(path)"
            )
        }
    }

    @Test
    func codexAndWorkBuddyRemainRegisteredWithoutManusSettings() throws {
        let root = repositoryRoot()
        let runtime = try text(
            at: root.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
            )
        )
        let settings = try text(
            at: root.appendingPathComponent(
                "Sources/CodexUsageUI/Stores/AgentSettingsCoordinator.swift"
            )
        )

        #expect(runtime.contains("CodexUsageConnector"))
        #expect(runtime.contains("WorkBuddyAvailabilityConnector"))
        #expect(runtime.contains("WorkBuddyAccountWebCreditsConnector"))
        #expect(!runtime.localizedCaseInsensitiveContains("manus"))
        #expect(settings.contains("Codex"))
        #expect(settings.contains("WorkBuddy"))
        #expect(!settings.localizedCaseInsensitiveContains("manus"))
    }

    @Test
    func providerOrderRemainsCodexThenWorkBuddy() {
        let codex = AgentConnectorID(rawValue: "codex.liveUsage")!
        let workBuddy = AgentConnectorID(
            rawValue: "workbuddy.accountWebCredits"
        )!

        #expect(AgentProviderOrder.precedes(codex, workBuddy))
        #expect(!AgentProviderOrder.precedes(workBuddy, codex))
    }

    @Test
    func cancelledG3AcceptanceAndPackagePathsAreAbsent() {
        let root = repositoryRoot()
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Tests/CodexUsageUITests/M4G3ManusLiveAcceptanceTests.swift"
                ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "script/package_uma_m4_g3.sh"
                ).path
            )
        )
    }

    @Test
    func retirementPackageHelperIsCommitExactAndFailClosed() throws {
        let script = try text(
            at: repositoryRoot()
                .appendingPathComponent("script/package_uma_m4_n.sh")
        )

        #expect(script.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(script.contains("uma-m4-n-final-$short_commit"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("Package production source retained"))
        #expect(script.contains("Package executable retained"))
        #expect(script.contains("Package file allowlist mismatch"))
    }

    @Test
    func durableDecisionClosesM4AndKeepsManusUnsupported() throws {
        let closeout = try text(
            at: repositoryRoot().appendingPathComponent(
                "source/UMA M4 Closeout.md"
            )
        )
        let retirement = try text(
            at: repositoryRoot().appendingPathComponent(
                "source/UMA M4 Manus API Route Retirement Decision.md"
            )
        )

        #expect(
            closeout.contains(
                "M4 CLOSED — MANUS UNSUPPORTED — NO API-KEY PRODUCT PATH"
            )
        )
        #expect(retirement.contains("No real Manus key was used"))
        #expect(retirement.contains("No live Manus Credit request completed"))
    }

    private func productionSource() throws -> String {
        let sources = repositoryRoot().appendingPathComponent("Sources")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sources,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        var combined = ""
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            combined += try text(at: url)
        }
        return combined
    }

    private func text(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
