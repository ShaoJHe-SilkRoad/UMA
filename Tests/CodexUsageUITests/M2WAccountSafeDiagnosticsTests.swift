import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2WACCOUNT safe diagnostics")
struct M2WAccountSafeDiagnosticsTests {
    @Test
    func diagnosticsAreFailureOnlyAndStrictlyBounded() {
        let accepted = WorkBuddyAccountWebExtractionAttempt(
            data: Data(),
            failure: .pageNotStabilized,
            safeDiagnosticCode: "T110-D110-Q1"
        )
        #expect(accepted.safeDiagnosticCode == "T110-D110-Q1")

        for rejected in [
            "T210-D110-Q1",
            "T110-D110-Q2",
            "S01-A00-B03-X00-N00-G0-account",
            "S01-A00-B03-X00-N00-G0 9155.52"
        ] {
            let attempt = WorkBuddyAccountWebExtractionAttempt(
                data: Data(),
                failure: .pageNotStabilized,
                safeDiagnosticCode: rejected
            )
            #expect(attempt.safeDiagnosticCode == nil)
        }

        let successfulAttempt = WorkBuddyAccountWebExtractionAttempt(
            data: Data(),
            failure: nil,
            safeDiagnosticCode: "T110-D110-Q1"
        )
        #expect(successfulAttempt.safeDiagnosticCode == nil)
    }

    @Test
    func trackedTaskDiagnosticsNeverRequestFullArgumentsOrEnvironmentDumps()
        throws
    {
        let roots = [
            packageRoot().appendingPathComponent("Sources"),
            packageRoot().appendingPathComponent("script")
        ]
        let forbiddenPatterns = [
            #"\bps[ \t]+[^\n]*(?:command|args)(?:[ \t=,]|$)"#,
            #"\bps[ \t]+e(?:[ \t]|$)"#,
            #"\bprintenv(?:[ \t]|$)"#,
            #"(?:^|[;&|][ \t]*)env[ \t]*(?:[>|]|$)"#
        ]
        let expressions = try forbiddenPatterns.map {
            try NSRegularExpression(
                pattern: $0,
                options: [.anchorsMatchLines]
            )
        }
        var auditedFileCount = 0

        for root in roots {
            let enumerator = try #require(
                FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
            )
            for case let fileURL as URL in enumerator {
                guard
                    try fileURL.resourceValues(
                        forKeys: [.isRegularFileKey]
                    ).isRegularFile == true,
                    var contents = try? String(
                        contentsOf: fileURL,
                        encoding: .utf8
                    )
                else {
                    continue
                }

                auditedFileCount += 1
                if contents.hasPrefix("#!") {
                    contents = contents
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .dropFirst()
                        .joined(separator: "\n")
                }
                contents = contents.replacingOccurrences(
                    of: "\\\n",
                    with: " "
                )
                let range = NSRange(
                    contents.startIndex..<contents.endIndex,
                    in: contents
                )

                for expression in expressions {
                    #expect(
                        expression.firstMatch(
                            in: contents,
                            options: [],
                            range: range
                        ) == nil,
                        "Unsafe diagnostic command in \(fileURL.path)"
                    )
                }
            }
        }

        #expect(auditedFileCount > 0)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
