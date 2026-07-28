import Foundation
import Testing

struct R0PackageContractTests {
    @Test
    func packageHelperRecordsHonestCommitExactProvenance() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot
            .appendingPathComponent("script")
            .appendingPathComponent("package_uma_r0.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("MARKETING_VERSION=\"0.10.1\""))
        #expect(script.contains("BUNDLE_ID=\"com.kevinchen.CodexUsageMonitor\""))
        #expect(script.contains("DEFAULT_BUILD=\"202607231820\""))
        #expect(script.contains("HISTORICAL_ACCEPTED_REVISION=\"a8c5ff23fdfb4652481b8b4d2447bcfb2d152cbd\""))
        #expect(script.contains("RECONSTRUCTED_PARENT=\"f1da999cf518433d108867d14ea1476678911ebf\""))
        #expect(script.contains("SourceState</key><string>reconstructed-commit"))
        #expect(script.contains("UMASourceState</key><string>reconstructed-commit"))
        #expect(script.contains("/private/tmp/uma-r0-final-$commit/UMA_0.10.1.app"))
        #expect(!script.contains("recovered exact commit"))
        #expect(!script.contains("identical source"))
        #expect(!script.contains("original tree restored"))
    }
}
