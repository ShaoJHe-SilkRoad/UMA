import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M4-G2 Manus package and privacy contract")
struct M4G2ManusPackageContractTests {
    @Test
    func productionSourceContainsOnlyTheAdmittedManusRoute() throws {
        let root = repositoryRoot()
        let sources = root.appendingPathComponent(
            "Sources/CodexUsageUI",
            isDirectory: true
        )
        let enumerator = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil
        )!
        var combined = ""
        for case let url as URL in enumerator
        where url.pathExtension == "swift" {
            combined += try String(contentsOf: url, encoding: .utf8)
        }
        #expect(combined.contains("/v2/usage.availableCredits"))
        #expect(combined.contains("x-manus-api-key"))
        #expect(!combined.contains("/v2/usage.list"))
        #expect(!combined.contains("/v2/tasks"))
        #expect(!combined.contains("/v2/task"))
        #expect(!combined.contains("MANUS_API_KEY"))
        #expect(!combined.contains("kSecAttrAccessGroup"))
    }

    @Test
    func packageHelperIsCommitExactAndNeverInstallsDesktopApp() throws {
        let script = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "script/package_uma_m4.sh"
            ),
            encoding: .utf8
        )
        #expect(script.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(script.contains("/private/tmp/uma-m4-g2-final-"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("Package manifest differs from the exact allowlist."))
        #expect(script.contains("Contents/_CodeSignature/CodeResources"))
        #expect(script.contains("Package contains a symbolic link."))
        #expect(script.contains("lipo -archs"))
        #expect(
            script.contains(
                #"static let authenticationHeader = "x-manus-api-key""#
            )
        )
        #expect(script.contains(#"readonly DEFAULT_BUILD="202607280002""#))
        #expect(script.contains("LIVE MANUS BALANCE NOT YET VALIDATED"))
        #expect(!script.contains("/Users/juliushe/Desktop/UMA_0.11.app"))
        #expect(!script.contains("usage.list"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
