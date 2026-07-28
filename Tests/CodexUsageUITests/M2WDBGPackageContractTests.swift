import Foundation
import Testing

@Suite("M2WDBG-G1 package contract")
struct M2WDBGPackageContractTests {
    @Test
    func helperBuildsOnlyCommitExactTaskOwnedPackages() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(
            contentsOf: repository
                .appendingPathComponent("script/package_uma_m2wdbg.sh"),
            encoding: .utf8
        )

        #expect(script.contains("MARKETING_VERSION=\"0.10.1\""))
        #expect(script.contains("DEFAULT_BUILD=\"202607240301\""))
        #expect(
            script.contains(
                "/private/tmp/uma-m2wdbg-final-$short_commit/UMA.app"
            )
        )
        #expect(script.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(script.contains("UMASourceState</key><string>commit-exact"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("[[ ! -e \"$output_parent\" && ! -L \"$output_parent\" ]]"))
        #expect(script.contains("canonical_output_parent"))
        #expect(!script.contains("codexusage-m1a-g2-dbg-b-package"))
        #expect(!script.contains("workbuddy-manual-availability.json"))
        #expect(!script.contains("CodexUsageMonitor/"))
        #expect(!script.contains("Desktop/"))
        #expect(!script.contains("xattr -cr"))
        #expect(!script.contains("cp -R"))
    }
}
