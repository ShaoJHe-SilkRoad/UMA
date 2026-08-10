import Foundation
import Testing

@Suite("M7-B0 Cursor source-admission plan")
struct M7B0CursorSourceAdmissionPlanTests {
    @Test
    func lineageAndExactB0ScopeAreLocked() throws {
        let scope = try record("source/UMA M7 Cursor Scope Lock.md")

        #expect(scope.contains("a6b846ea2785448c4d4e51ec0e775ff9220d33f5"))
        #expect(scope.contains("d7f789c3d2fd4e98a43256737b733c37fe5b0c81"))
        #expect(scope.contains("codex/uma-m7-cursor"))
        #expect(scope.contains("/Users/juliushe/Developer/UMA-M7-Cursor"))
        #expect(scope.contains("Tests/CodexUsageUITests/M7B0CursorSourceAdmissionPlanTests.swift"))
        #expect(scope.contains("source/reference/**"))
    }

    @Test
    func sourcePriorityAndDecisionGatesAreExplicit() throws {
        let plan = try record("source/M7_Plan.md")

        let orderedSources = [
            "official local structured Cursor source",
            "official documented local CLI read-only command",
            "official provider-owned hook or status source",
            "provider-controlled account/browser login",
            "unsupported",
        ]
        var prior = plan.startIndex
        for source in orderedSources {
            let range = try #require(plan.range(of: source, range: prior..<plan.endIndex))
            prior = range.upperBound
        }

        for decision in ["`GO`", "`CONDITIONAL GO`", "`SETUP REQUIRED`", "`NO-GO`"] {
            #expect(plan.contains(decision))
        }
        #expect(plan.contains("Source admission is not permission to implement the connector"))
    }

    @Test
    func prohibitedCredentialPrivateAndInferenceRoutesRemainLocked() throws {
        let records = try allRecords()
        let combined = records.joined(separator: "\n")
        let normalized = combined
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()

        for boundary in [
            "user-entered API key",
            "copied token",
            "Keychain secret",
            "browser profile",
            "private endpoint",
            "manual quota",
            "activity, token count, cost",
            "provider prompt/task",
            "Broad process command lines",
        ] {
            #expect(normalized.contains(boundary.lowercased()))
        }
        #expect(combined.contains("Cursor authenticated reads: 0"))
        #expect(combined.contains("Cursor prompts/tasks: 0"))
        #expect(combined.contains("Intentional Cursor quota spend: 0"))
    }

    @Test
    func protectedProvidersAndFiveProviderDensityAreLocked() throws {
        let plan = try record("source/M7_Plan.md")
        let scope = try record("source/UMA M7 Cursor Scope Lock.md")
        let brief = try record("source/UMA M7 Cursor Source-Admission Research Brief.md")

        for provider in ["Codex", "Claude Code", "WorkBuddy", "Google Antigravity"] {
            #expect(plan.contains(provider))
            #expect(scope.contains(provider))
        }
        #expect(plan.contains("0 through 4 visible providers → Regular mode remains permitted"))
        #expect(plan.contains("5 or more visible providers   → Minimalist mode is forced"))
        #expect(brief.contains("Codex → Claude Code → WorkBuddy → Google Antigravity → Cursor"))
    }

    @Test
    func goalOrderAndCompletionLockAllowOnlyM7G1Next() throws {
        let goals = try record("source/M7_Goals.md")
        let expected = [
            "M7-B0", "M7-G1", "M7-SETUP-G1", "M7-G2", "M7-G3",
            "M7DBG-G1", "M7A-G1", "M7ADBG-G1", "M7-CLOSE-G1",
        ]
        var prior = goals.startIndex
        for goal in expected {
            let range = try #require(goals.range(of: goal, range: prior..<goals.endIndex))
            prior = range.upperBound
        }

        #expect(goals.contains("M7-G1 — Cursor Official Source, Authentication, and Schema Admission"))
        #expect(goals.contains("M7-G2 remains locked"))
        #expect(goals.contains("After M7-B0, stop"))
    }

    private func allRecords() throws -> [String] {
        try [
            record("source/M7_Plan.md"),
            record("source/M7_Goals.md"),
            record("source/UMA M7 Cursor Scope Lock.md"),
            record("source/UMA M7 Cursor Source-Admission Research Brief.md"),
        ]
    }

    private func record(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
