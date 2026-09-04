import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M7 Cursor NO-GO closeout")
struct M7CloseCursorSourceAdmissionTests {
    @Test
    func closeoutRecordsExactUnsupportedSourceTruth() throws {
        let closeout = try record("source/UMA M7 Cursor Closeout.md")

        #expect(closeout.contains("M7 CLOSED — CURSOR UNSUPPORTED — SOURCE NOT ADMITTED"))
        #expect(closeout.contains("| Cursor production support | `UNSUPPORTED` |"))
        #expect(closeout.contains("`Unsupported — source not admitted`"))
        #expect(closeout.contains("| Direct local/CLI quota source | `NO-GO` |"))
        #expect(closeout.contains("| Official browser dashboard architecture | `TECHNICALLY VIABLE` |"))
        #expect(closeout.contains("| Provider-controlled Safari authentication | `PROVEN FEASIBLE` |"))
        #expect(closeout.contains("| Sanitized browser extraction | `PROVEN FEASIBLE` |"))
        #expect(closeout.contains("M7-G2 | `PERMANENTLY LOCKED UNDER CURRENT EVIDENCE`"))
    }

    @Test
    func freeDisplayTruthNeverBecomesEnforcementAdmission() throws {
        let closeout = try record("source/UMA M7 Cursor Closeout.md")

        #expect(closeout.contains("| Free-plan percentage semantic | `USED` |"))
        #expect(closeout.contains("`remainingPercent = 100 - usedPercent`"))
        #expect(closeout.contains("| Free-plan enforcement reliability | `NOT ADMITTED` |"))
        #expect(closeout.contains("Dashboard percentage and\nactual IDE usage-limit enforcement disagree"))
        #expect(closeout.contains("not an admitted predictor"))
    }

    @Test
    func paidPlanPoolsRemainDocumentedButUnqualified() throws {
        let closeout = try record("source/UMA M7 Cursor Closeout.md")

        #expect(closeout.contains("| Paid-plan source status | `DOCUMENTED BUT NOT LIVE QUALIFIED` |"))
        #expect(closeout.contains("1. `Cursor Models`"))
        #expect(closeout.contains("2. `Other Models`"))
        #expect(closeout.contains("does not qualify,\nmanufacture, merge, or split the paid-plan contract"))
        #expect(closeout.contains("Paid plans are not\nsupported by this closeout"))
    }

    @Test
    func currentDailyRuntimeRegistersOnlyQualifiedCodexAndClaudeProviders() throws {
        let runtime = try record(
            "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
        )
        let settings = try record(
            "Sources/CodexUsageUI/Stores/AgentSettingsCoordinator.swift"
        )
        let closeout = try record("source/UMA M7 Cursor Closeout.md")

        for connector in [
            "CodexUsageConnector",
            "ClaudeCodeUsageConnector",
        ] {
            #expect(runtime.contains(connector))
        }
        #expect(!runtime.contains("WorkBuddyAvailabilityConnector("))
        #expect(!runtime.contains("WorkBuddyAccountWebCreditsConnector("))
        #expect(!runtime.contains("GoogleAntigravityUsageConnector("))
        #expect(!runtime.contains("CursorUsageConnector"))
        #expect(!settings.contains("\"Cursor\""))
        for provider in ["Codex", "Claude Code", "WorkBuddy", "Google Antigravity"] {
            #expect(settings.contains("\"\(provider)\""))
            #expect(closeout.contains("\(provider) — `Supported`"))
        }
    }

    @Test
    func noProductionCursorSourceOrBrowserArtifactExists() throws {
        let sources = repositoryRoot().appendingPathComponent("Sources")
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: sources,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        )
        let paths = enumerator.compactMap { $0 as? URL }
        #expect(!paths.contains { $0.lastPathComponent.lowercased().contains("cursor") })

        let runtime = try record(
            "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
        )
        let closeout = try record("source/UMA M7 Cursor Closeout.md")
        #expect(!runtime.contains("CursorBrowser"))
        #expect(closeout.contains("production Cursor BrowserExtension: `NONE`"))
        #expect(closeout.contains("No Cursor connector, scheduler, UI,"))
    }

    @Test
    func densityRuleRemainsProviderNeutralWithoutFiveProviderQualification() throws {
        #expect(
            DesktopAssistantDensity.automatic.resolvedDensity(
                visibleProviderCount: 4
            ) == .regular
        )
        #expect(
            DesktopAssistantDensity.automatic.resolvedDensity(
                visibleProviderCount: 5
            ) == .minimalist
        )
        let closeout = try record("source/UMA M7 Cursor Closeout.md")
        #expect(closeout.contains("0–4 visible providers → Regular allowed"))
        #expect(closeout.contains(">4 visible providers → forced Minimalist"))
        #expect(closeout.contains("No five-provider production transition was implemented or live qualified"))
    }

    @Test
    func browserCleanupAndZeroOperationBoundaryRemainExplicit() throws {
        let closeout = try record("source/UMA M7 Cursor Closeout.md")

        #expect(closeout.contains("Allow unsigned extensions` set to `Off`"))
        #expect(closeout.contains("temporary Cursor companions disabled and unregistered"))
        #expect(closeout.contains("task-owned browser probe roots removed"))
        #expect(closeout.contains("Keychain access: `NONE`"))
        #expect(closeout.contains("account identity, and exact quota\n  values: `NONE`"))
        #expect(closeout.contains("Cursor reads/browser login actions/prompts/tasks/intentional spend: 0/0/0/0/0"))
        #expect(closeout.contains("Broad process argv/environment inspection remains forbidden"))
    }

    @Test
    func routeFamilyResearchAndReopenConditionsAreDurable() throws {
        let closeout = try record("source/UMA M7 Cursor Closeout.md")

        for route in ["`/dashboard`", "`/dashboard/usage`", "`/dashboard/spending`"] {
            #expect(closeout.contains(route))
        }
        #expect(closeout.contains("not one permanent hard-coded route contract"))
        #expect(closeout.contains("official structured quota/remaining API or read-only"))
        #expect(closeout.contains("stable enforceable remaining-usage contract"))
        #expect(closeout.contains("officially resolves the Free-plan Dashboard/enforcement mismatch"))
        #expect(closeout.contains("paid-plan account becomes available"))
        #expect(closeout.contains("Founder explicitly changes the current source or privacy policy"))
        #expect(closeout.contains("Until then: `Cursor remains unsupported.`"))
    }

    @Test
    func exactCloseoutScopeAndCompletionLockAreRecorded() throws {
        let closeout = try record("source/UMA M7 Cursor Closeout.md")
        let ledger = try record("source/UMA M7 Cursor QA Issue Ledger.md")

        for path in [
            "Tests/CodexUsageUITests/M7CloseCursorSourceAdmissionTests.swift",
            "source/UMA M7 Cursor Closeout.md",
            "source/UMA M7 Cursor QA Issue Ledger.md",
        ] {
            #expect(ledger.contains(path))
        }
        #expect(closeout.contains("checksum-locked `source/reference/**` file changed"))
        #expect(closeout.contains("Return to Founder for next-provider selection"))
        #expect(ledger.contains("Production source files changed: NO"))
        #expect(ledger.contains("M7-G2 remains locked: YES"))
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
