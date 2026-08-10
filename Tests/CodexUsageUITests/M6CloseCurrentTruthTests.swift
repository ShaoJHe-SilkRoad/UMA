import Foundation
import Testing

@Suite("M6 closeout current truth")
struct M6CloseCurrentTruthTests {
    @Test
    func closeoutRecordsExactProductAndPackageBaseline() throws {
        let closeout = try text("source/UMA M6 Closeout and Cursor Handoff.md")

        for required in [
            "e72bd92c476e05152b95ccb9ba95c22be78efef1",
            "c1358c5b4176383021e87605afc45ca3e347ab89",
            "uma-m6adbg-final-e72bd92c476e05152b95ccb9ba95c22be78efef1/UMA.app",
            "18046642208106125d2a69120bd2a88931c5af6d7a4dd55620fa9306d3828e97",
            "com.silkrd.uma",
            "0.11 / 202608090106",
            "588/588 PASS",
            "M6 CLOSED — GOOGLE ANTIGRAVITY SUPPORTED — M7 SOURCE ADMISSION NEXT",
        ] {
            #expect(closeout.contains(required))
        }
    }

    @Test
    func providerMatrixAndDensityMatchCurrentProduct() throws {
        let closeout = try text("source/UMA M6 Closeout and Cursor Handoff.md")
        for required in [
            "Codex | `SUPPORTED`",
            "Claude Code | `SUPPORTED`",
            "WorkBuddy | `SUPPORTED`",
            "Google Antigravity | `SUPPORTED — LIVE ACCEPTED`",
            "Cursor | `NOT YET SUPPORTED`",
            "codex.local",
            "claude.browserSync",
            "workbuddy.accountWebCredits",
            "antigravity.cli",
            "visible provider count > 4",
        ] {
            #expect(closeout.contains(required))
        }
        #expect(!closeout.contains("Cursor | `SUPPORTED`"))
    }

    @Test
    func antigravitySourceQuotaAndRefreshContractsAreExact() throws {
        let closeout = try text("source/UMA M6 Closeout and Cursor Handoff.md")
        let client = try text(
            "Sources/CodexUsageUI/Services/AntigravityReadOnlyCLIClient.swift"
        )

        for required in [
            "/Users/juliushe/.local/bin/agy",
            "$HOME/.local/bin/agy",
            "1.1.11",
            "agy --output-format json -p /usage",
            "command.data.groups[].buckets[]",
            "bucket.id",
            "remaining_fraction × 100",
            "`REMAINING`",
            "reset_time",
            "five minutes",
            "Manual and scheduled reads coalesce",
        ] {
            #expect(closeout.contains(required))
        }
        #expect(client.contains("[\"--output-format\", \"json\", \"-p\", \"/usage\"]"))
        #expect(client.contains("Process()"))
        #expect(client.contains("process.executableURL"))
    }

    @Test
    func privacyCreditsCoverageAndCursorBoundariesFailClosed() throws {
        let closeout = try text("source/UMA M6 Closeout and Cursor Handoff.md")
        for required in [
            "UMA credential access is `NONE`",
            "`CREDITS DEFER`",
            "it did not classify the",
            "account as individual or enterprise",
            "every other unclassified",
            "account mode remain unqualified and must fail closed",
            "M7 — Cursor Source Admission",
            "source dossier, not connector implementation",
            "Broad process",
            "command lines, unrelated argv",
            "fail closed",
            "`/usage` 0; `/credits` 0; prompts/tasks 0; intentional spend 0",
        ] {
            #expect(closeout.contains(required))
        }
        #expect(!closeout.contains("Antigravity Credits | `SUPPORTED`"))
        #expect(!closeout.contains("Cursor feasibility is proven"))
    }

    @Test
    func currentTruthIsAdditiveAndRetainedSourcesStayHistorical() throws {
        let plan = try text("source/M6_Plan.md")
        let goals = try text("source/M6_Goals.md")
        let referenceManifest = try text("source/reference/Source_Reference_Manifest.md")
        let providerMatrix = try text("source/reference/Provider_Status_Matrix.md")

        #expect(plan.contains("Status:** Active plan; implementation gated by M6-G1"))
        #expect(goals.contains("Current next Goal:** M6-B0"))
        #expect(referenceManifest.contains("Current milestone:** M4"))
        #expect(providerMatrix.contains("Next provider:** Manus"))
        #expect(try text("source/UMA M6 Closeout and Cursor Handoff.md").contains(
            "this record is the additive current M6 truth"
        ))
    }

    @Test
    func m5FreezeAndDistributionStatusRemainHonest() throws {
        let closeout = try text("source/UMA M6 Closeout and Cursor Handoff.md")
        for required in [
            "c6245f9cc745b3d45f53e115843b3152e84e8c46",
            "52-file protected set",
            "active Developer ID",
            "notarization",
            "local verification evidence",
            "protected Desktop UMA",
        ] {
            #expect(closeout.contains(required))
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
