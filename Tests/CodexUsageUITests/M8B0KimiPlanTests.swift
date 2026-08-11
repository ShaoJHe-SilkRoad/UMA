import Foundation
import Testing

@Suite("M8 B0 Kimi plan baseline")
struct M8B0KimiPlanTests {
    @Test
    func governingSetUsesCorrectedTerminalM7Parent() throws {
        for path in ["source/Scroll_3.md", "source/M8_Plan.md", "source/M8_Goal.md"] {
            let record = try text(path)
            #expect(record.contains("e47f7de3e71f80d45a5561dad40e37f37ff11fd1"))
            #expect(record.contains("d836312beb29005e7b5abe882f9919d05a9b49f4"))
            #expect(record.contains("M7 CLOSED — CURSOR UNSUPPORTED — SOURCE NOT ADMITTED"))
        }
    }

    @Test
    func historicalG1CParentIsRetainedButNeverUsedAsBranchPoint() throws {
        let scope = try text("source/UMA M8 Kimi Scope Lock.md")
        #expect(scope.contains("fcb51ab48bb076704431742b7b0300c235975f8e"))
        #expect(scope.contains("43dac9a01be51c3f19b3e510d3ff6923ca4bae57"))
        #expect(scope.contains("historical source-decision predecessor; not the M8 branch point"))
    }

    @Test
    func currentProviderMatrixAndDensityRemainExact() throws {
        let scope = try text("source/UMA M8 Kimi Scope Lock.md")
        #expect(scope.contains("Codex → Claude Code → WorkBuddy → Google Antigravity → Kimi"))
        #expect(scope.contains("0–4 visible providers → Regular allowed"))
        #expect(scope.contains(">4 visible providers → forced Minimalist"))
        #expect(scope.contains("Cursor remains unsupported and hidden"))
        #expect(scope.contains("Kimi is not installed, probed"))
    }

    @Test
    func unifiedKimiContractRequiresSharedMembershipAndAtMostTwoChannels() throws {
        let scope = try text("source/UMA M8 Kimi Scope Lock.md")
        #expect(scope.contains("one provider, stable ID `kimi`, with at most two truthful"))
        #expect(scope.contains("shared Kimi membership usage — mandatory"))
        #expect(scope.contains("Kimi Code-specific limits — separate"))
        #expect(scope.contains("must not be double-counted"))
        #expect(scope.contains("Extra Usage must remain a native continuation state"))
    }

    @Test
    func protectedHistoricalAndProviderBoundariesAreExplicit() throws {
        let scope = try text("source/UMA M8 Kimi Scope Lock.md")
        #expect(scope.contains("cd8cd9623b59cbf03d96b6d92e99b50d833dc4bc1b6bf7479148c4f63df83294"))
        #expect(scope.contains("source/reference/**"))
        #expect(scope.contains("Codex mechanism changed: NO"))
        #expect(scope.contains("Claude mechanism changed: NO"))
        #expect(scope.contains("WorkBuddy mechanism changed: NO"))
        #expect(scope.contains("Google Antigravity mechanism changed: NO"))
    }

    @Test
    func b0PerformsNoProviderOperationAndUnlocksOnlyG1() throws {
        let scope = try text("source/UMA M8 Kimi Scope Lock.md")
        for required in [
            "Kimi quota/source observations: 0",
            "Kimi prompts/tasks: 0",
            "Intentional Kimi spend: 0",
            "Kimi login/browser actions: 0",
            "M8-G1 — Kimi unified source admission",
            "M8-G1 must not start automatically",
        ] {
            #expect(scope.contains(required))
        }
    }

    private func text(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(path),
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
