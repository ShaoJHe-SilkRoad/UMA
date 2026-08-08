import Foundation
import Testing

@Suite("M2WA-G1 package contract")
struct M2WAG1PackageContractTests {
    @Test
    func helperBuildsOnlyCommitExactTaskOwnedPackage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(
            contentsOf: repository.appendingPathComponent(
                "script/package_uma_m2wa.sh"
            ),
            encoding: .utf8
        )

        #expect(script.contains("MARKETING_VERSION=\"0.10.1\""))
        #expect(script.contains("DEFAULT_BUILD=\"202607242315\""))
        #expect(script.contains("BUNDLE_ID=\"com.silkrd.uma\""))
        #expect(script.contains("/private/tmp/uma-m2wa-final-$short_commit/UMA.app"))
        #expect(script.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(script.contains("UMA-M2WA-Provenance.plist"))
        #expect(script.contains("UMASourceState</key><string>commit-exact"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("[[ ! -e \"$output_parent\" && ! -L \"$output_parent\" ]]"))
        #expect(script.contains("canonical_output_parent"))

        for forbidden in [
            "workbuddy-manual-availability.json",
            "PreviewRendererTool",
            "Tests/",
            "source/",
            "Desktop/",
            "xattr -cr",
            "cp -R"
        ] {
            #expect(!script.contains(forbidden))
        }
    }
}
