import Foundation
import Testing
@testable import CodexUsageUI

/// When Claude has no remaining percentage the page used to say "connect or
/// refresh", which cannot produce one: refreshing re-reads the same local
/// sources, and local activity carries no allowance at all. These pin the
/// replacement guidance and keep it truthful about what does produce a figure.
@Suite("Claude missing-quota guidance", .timeLimit(.minutes(1)))
struct ClaudeMissingQuotaGuidanceTests {
    @Test("Both languages explain the two real sources")
    func guidanceNamesWhatProducesAPercentage() {
        for language in [AppLanguage.english, .simplifiedChinese] {
            let copy = language.claudeMissingQuotaGuidance
            #expect(!copy.isEmpty)
            // Must name both routes, or the reader is left without a next step.
            #expect(copy.contains("Claude Code"))
            #expect(copy.contains(language == .english ? "Claude Desktop" : "Claude 桌面版"))
            #expect(copy.contains(language == .english ? "status line" : "状态栏"))
            #expect(copy.contains("20"))
            // It must not promise that refreshing helps.
            #expect(!copy.lowercased().contains("refresh"))
            #expect(!copy.contains("刷新"))
        }
        #expect(
            AppLanguage.english.claudeMissingQuotaGuidance
                != AppLanguage.simplifiedChinese.claudeMissingQuotaGuidance
        )
    }

    private func readSource(_ relativePath: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("The usage module routes Claude to that guidance, others unchanged")
    func usageModuleBranchesOnProvider() throws {
        let surfaces = try readSource("Sources/CodexUsageUI/Views/AgentSurfaceViews.swift")
        #expect(surfaces.contains("providerID == .claude"))
        #expect(surfaces.contains("store.language.claudeMissingQuotaGuidance"))
        // Every other provider keeps the original line.
        #expect(surfaces.contains(
            "Connect or refresh this agent to retrieve qualified usage data."
        ))
    }
}
