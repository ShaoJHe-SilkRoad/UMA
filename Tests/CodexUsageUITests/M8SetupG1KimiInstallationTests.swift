import Foundation
import Testing

@Suite("M8 SETUP G1 official Kimi preparation")
struct M8SetupG1KimiInstallationTests {
    @Test
    func recordBindsOfficialPinnedInstallation() throws {
        let record = try setupRecord()

        #expect(record.contains("Result: `PASS — READY FOR M8-G1R`"))
        #expect(record.contains("https://code.kimi.com/kimi-code/install.sh"))
        #expect(record.contains("https://code.kimi.com/kimi-code/latest"))
        #expect(record.contains("binaries/0.34.0/manifest.json"))
        #expect(record.contains("KIMI_VERSION=0.34.0"))
        #expect(record.contains("KIMI_NO_MODIFY_PATH=1"))
    }

    @Test
    func executableIdentityIsExactAndNative() throws {
        let record = try setupRecord()

        #expect(record.contains("$HOME/.kimi-code/bin/kimi"))
        #expect(record.contains("Mach-O 64-bit executable"))
        #expect(record.contains("Architecture | arm64"))
        #expect(record.contains("Version | `0.34.0`"))
        #expect(record.contains("Mode | `0755`"))
        #expect(record.contains("9f4337e10da47843f6b550474012a53ba8b30dd665f83b176a5cd479c5f7e859"))
        #expect(record.contains("Team ID | `2J9472RW75`"))
        #expect(record.contains("Strict code-sign verification | PASS"))
    }

    @Test
    func promptModeIsNotMisclassifiedAsUsageControl() throws {
        let record = try setupRecord()

        #expect(record.contains("`/usage` as an\ninteractive information command"))
        #expect(record.contains("did not invoke it"))
        #expect(record.contains("`kimi -p \"/usage\"` remains prohibited"))
        #expect(record.contains("`-p` is Agent prompt mode"))
    }

    @Test
    func authenticationRemainsProviderControlledAndOpaque() throws {
        let record = try setupRecord()

        #expect(record.contains("PROVIDER-CONTROLLED OAUTH SETUP COMPLETED"))
        #expect(record.contains("CREDENTIALS OPAQUE TO UMA/DEV"))
        #expect(record.contains("credential access: NONE"))
        #expect(record.contains("The Human returned only `KIMI LOGIN COMPLETED`"))
        #expect(record.contains("No repeated login was requested"))
    }

    @Test
    func setupUsesNoProviderReadOrWork() throws {
        let record = try setupRecord()

        #expect(record.contains("readiness quota/source observations: 0 / 1"))
        #expect(record.contains("Kimi prompts: 0"))
        #expect(record.contains("Kimi Agent turns: 0"))
        #expect(record.contains("Kimi tasks/conversations: 0"))
        #expect(record.contains("intentional Kimi spend: 0"))
        #expect(record.contains("credential/private-state reads: 0"))
    }

    @Test
    func protectedProvidersAndSurfacesRemainUntouched() throws {
        let record = try setupRecord()

        for provider in ["Codex", "Claude", "WorkBuddy", "Antigravity"] {
            #expect(record.contains("\(provider) mechanism changed: NO"))
        }
        #expect(record.contains("Cursor remains unsupported and hidden"))
        #expect(record.contains("Kimi runtime connector/provider registration: NOT STARTED"))
        #expect(record.contains("Main Panel and Desktop Assistant changes: NONE"))
        #expect(record.contains("`source/reference/**` changes: NONE"))
    }

    @Test
    func durableRecordContainsNoIdentityOrSyntheticSecret() throws {
        let record = try setupRecord()

        #expect(!record.contains("/Users/"))
        #expect(!record.contains("@gmail"))
        #expect(!record.contains("@icloud"))
        #expect(!record.contains("Bearer "))
        #expect(!record.contains("access_token"))
        #expect(!record.contains("refresh_token"))
        #expect(!record.contains("device_code"))
    }

    @Test
    func exactlyOneNextTaskIsRecorded() throws {
        let record = try setupRecord()

        #expect(record.contains("Exactly one next task:"))
        #expect(record.contains("M8-G1R — Live installed Kimi CLI source re-admission"))
        #expect(record.contains("M8-G1R is not started"))
        #expect(record.contains("M8-WEB-G1, M8-G2"))
    }

    private func setupRecord() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("source/UMA M8 Kimi Setup Record.md"),
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
