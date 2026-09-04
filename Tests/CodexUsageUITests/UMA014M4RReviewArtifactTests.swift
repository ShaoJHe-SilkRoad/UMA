import Foundation
import Testing

@Suite("UMA 0.14 M4R review package")
struct UMA014M4RReviewArtifactTests {
    @Test("Review app is isolated and the package exercises all correction surfaces")
    func reviewPackageContract() throws {
        let script = try source("script/package_uma014_m4r_review.sh")

        #expect(script.contains("UMA 0.14 M4R Review"))
        #expect(script.contains("com.silkrd.uma.dev.uma014.m4r-review"))
        #expect(script.contains("script/package_uma014_m1_dev.sh"))
        #expect(script.contains("providerReadsDuringArtifactGeneration -integer 0"))
        for artifact in [
            "quick-panel-light",
            "quick-panel-dark",
            "quick-panel-white-background",
            "quick-panel-black-background",
            "quick-panel-saturated-background",
            "quick-panel-reduce-transparency",
            "quick-panel-increase-contrast",
            "quick-panel-alpha-mask-1x",
            "quick-panel-alpha-mask-2x",
            "codex-workspace-light",
            "claude-workspace-light",
            "settings-general",
            "settings-appearance",
            "settings-desktop-wizard",
            "settings-privacy",
            "wizard-minimalist-exact",
            "wizard-minimalist-estimated",
            "main-narrow-chinese",
        ] {
            #expect(script.contains(artifact))
        }
    }

    @Test("Review package never overwrites production UMA")
    func protectedReleasePathsStayAbsent() throws {
        let script = try source("script/package_uma014_m4r_review.sh")

        #expect(!script.contains("/Users/juliushe/Desktop/UMA_0.13.0.app"))
        #expect(!script.contains("/Users/juliushe/Applications/UMA Safari Bridge.app"))
        #expect(!script.contains("notarytool"))
        #expect(!script.contains("codesign"))
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
