import Foundation
import Testing
@testable import CodexUsageUI

@Suite("UMA 0.11-DBG qualification contracts")
struct UMA011DBGQualificationTests {
    @Test("Final DBG packaging is commit-exact, isolated, and build-monotonic")
    func finalPackageContract() throws {
        let script = try source("script/package_uma_stability.sh")

        #expect(script.contains("--profile manual|dbg"))
        #expect(script.contains("DEFAULT_DBG_BUILD=\"202607270003\""))
        #expect(
            script.contains(
                "uma-0.11-dbg-final-$short_commit/UMA.app"
            )
        )
        #expect(script.contains("10#$build_number < 10#$DEFAULT_DBG_BUILD"))
        #expect(script.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(script.contains("Package file allowlist mismatch"))
        #expect(script.contains("Package executable contains a non-system dependency"))
        #expect(!script.contains("git checkout"))
        #expect(!script.contains("git reset"))
        #expect(!script.contains("/Users/juliushe/Desktop/UMA_0.11.app"))
        #expect(!script.contains("/Users/juliushe/Desktop/UMA_0.10.1.app"))
    }

    @Test("DBG durable records lock every required issue identifier")
    func durableIssueInventory() throws {
        let scope = try source("source/UMA 0.11-DBG Scope Lock.md")
        let ledger = try source("source/UMA 0.11-DBG QA Issue Ledger.md")

        for index in 1...9 {
            let identifier = String(format: "F-%03d", index)
            #expect(scope.contains(identifier))
        }
        for index in 1...14 {
            let identifier = String(format: "H-%03d", index)
            #expect(scope.contains(identifier))
        }
        for index in 1...28 {
            let identifier = String(format: "DBG-%03d", index)
            #expect(ledger.contains(identifier))
        }
    }

    private func source(_ relativePath: String) throws -> String {
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
