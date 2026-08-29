import Foundation
import Testing

@Suite("M5RMX immutable Safari Host packaging boundary")
struct M5RMXImmutableSafariHostPackagingTests {
    @Test("Host migration owns the only Safari bundle and dedicated identities")
    func hostMigrationOwnsSafariRuntime() throws {
        let package = try source("script/package_uma_safari_host_test.sh")
        let installer = try source("script/install_uma_safari_host_test.sh")

        for required in [
            "com.silkrd.uma.test.safarihost",
            "com.silkrd.uma.test.safarihost.ClaudeBrowserCompanion",
            "group.com.silkrd.uma.test.bridge",
            "SAFARI_HOST_MIGRATION",
            "UMA Safari Bridge Test.app",
            "UMASafariBridgeHost",
            "IMMUTABLE_SAFARI_HOST_TEST",
        ] {
            #expect(package.contains(required))
        }
        #expect(installer.contains("/Users/juliushe/Applications/UMA Safari Bridge Test.app") ||
            installer.contains("$HOME/Applications/UMA Safari Bridge Test.app"))
        #expect(installer.contains("/usr/bin/pluginkit -a"))
        #expect(installer.contains("/usr/bin/pluginkit -r"))
        #expect(installer.contains("registration_count=1"))
        #expect(installer.contains("plist \"$OLD_COMBINED_APP/Contents/Info.plist\" CFBundleIdentifier"))
        #expect(installer.contains("plist \"$HOST_PATH/Contents/Info.plist\" CFBundleIdentifier"))
        #expect(!installer.contains("plist \"$OLD_COMBINED_APP\" CFBundleIdentifier"))
        #expect(!installer.contains("plist \"$HOST_PATH\" CFBundleIdentifier"))
        #expect(!package.localizedCaseInsensitiveContains("notary"))
        #expect(!installer.localizedCaseInsensitiveContains("notary"))
    }

    @Test("Later deliberate Host migration atomically replaces only the exact task-owned Host")
    func laterHostMigrationHasBoundedRollback() throws {
        let installer = try source("script/install_uma_safari_host_test.sh")

        #expect(installer.contains("TestChannelAtomicSwap"))
        #expect(installer.contains("SAFARI_HOST_MIGRATION_REQUIRES_NEW_GENERATION"))
        #expect(installer.contains("rollback()"))
        #expect(installer.contains("\"$swap_binary\" \"$staged\" \"$HOST_PATH\""))
        #expect(installer.components(separatedBy: "\"$swap_binary\" \"$staged\" \"$HOST_PATH\"").count >= 3)
        #expect(installer.contains("SAFARI_HOST_MIGRATION_ROLLBACK_FAILED"))
        #expect(installer.contains("rollback_required=false"))
        #expect(installer.contains("codesign --verify --deep --strict --verbose=4 \"$HOST_PATH\""))
        #expect(installer.contains("Contents/PlugIns/ClaudeBrowserCompanion.appex/Contents/Info.plist"))
        #expect(installer.contains("registered_count\" == 1"))
        #expect(installer.contains("registration_count=1"))
    }

    @Test("successful Host migration keeps exit status zero when rollback is disabled")
    func successfulMigrationNoOpRollbackReturnsZero() throws {
        let installer = try source("script/install_uma_safari_host_test.sh")
        let rollbackStart = try #require(installer.range(of: "rollback() {"))
        let cleanupStart = try #require(installer.range(
            of: "\ncleanup() {",
            range: rollbackStart.upperBound..<installer.endIndex
        ))
        let rollbackFunction = installer[
            rollbackStart.lowerBound..<cleanupStart.lowerBound
        ]

        #expect(rollbackFunction.contains(
            "if [[ \"$rollback_required\" != true ]]; then return 0; fi"
        ))

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", """
        set -euo pipefail
        rollback_required=false
        swapped=false
        installed_new=false
        rollback_failed=false
        staged=/private/tmp/not-used
        HOST_PATH=/private/tmp/not-used
        swap_binary=/private/tmp/not-used
        LSREGISTER=/private/tmp/not-used
        \(rollbackFunction)
        cleanup() {
            status=$?
            trap - EXIT HUP INT TERM
            rollback
            exit "$status"
        }
        trap cleanup EXIT
        printf 'migration-success\\n'
        """]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(
            String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                == "migration-success\n"
        )
    }

    @Test("Host migration refuses any active or unsafe owned-tab receipt before registration mutation")
    func hostMigrationGatesOwnedTabReceipt() throws {
        let installer = try source("script/install_uma_safari_host_test.sh")
        let gate = try #require(installer.range(of: "owned_tab_receipt_status \"$OWNED_TAB_RECEIPT\""))
        let firstRegistrationMutation = try #require(installer.range(of: "/usr/bin/pluginkit -r"))

        #expect(gate.lowerBound < firstRegistrationMutation.lowerBound)
        #expect(installer.contains("SAFARI_HOST_MIGRATION_BLOCKED_ACTIVE_OWNED_TAB_RECEIPT"))
        #expect(installer.contains("SAFARI_HOST_MIGRATION_BLOCKED_UNSAFE_OWNED_TAB_RECEIPT"))
        #expect(installer.contains("--audit-owned-tab-receipt"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "uma-owned-tab-migration-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let receipt = root.appendingPathComponent("owned-tab-receipt.plist")

        #expect(try auditOwnedTabReceipt(receipt) == "CLEAR")
        let contentFreeReceipt: [String: Any] = [
            "requestID": UUID().uuidString.lowercased(),
            "tabID": 17,
            "runtimeGenerationID": UUID().uuidString.lowercased(),
            "bootstrapNonce": UUID().uuidString.lowercased(),
            "createdAt": "2026-08-28T12:00:00Z",
            "state": "proven",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: contentFreeReceipt,
            format: .binary,
            options: 0
        )
        try data.write(to: receipt, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receipt.path)
        #expect(try auditOwnedTabReceipt(receipt) == "ACTIVE")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: receipt.path)
        #expect(try auditOwnedTabReceipt(receipt) == "UNSAFE")
    }

    @Test("Host migration signs the nested extension before its container")
    func hostSigningIsChildFirst() throws {
        let package = try source("script/package_uma_safari_host_test.sh")
        let extensionSign = try #require(package.range(of: "--identifier \"$EXTENSION_ID\" --entitlements"))
        let hostSign = try #require(package.range(of: "--identifier \"$HOST_ID\" --entitlements"))

        #expect(extensionSign.lowerBound < hostSign.lowerBound)
        #expect(package.contains("codesign --verify --deep --strict"))
        #expect(package.contains("com.apple.security.get-task-allow"))
        #expect(package.contains("hostProfileSHA256"))
        #expect(package.contains("extensionProfileSHA256"))
        #expect(package.contains("hostInfoPlistSHA256"))
        #expect(package.contains("extensionInfoPlistSHA256"))
        #expect(package.contains("hostCodeSignatureSHA256"))
        #expect(package.contains("extensionCodeSignatureSHA256"))
        #expect(package.contains("hostCDHash"))
        #expect(package.contains("extensionCDHash"))
        #expect(package.contains("schemaVersion -integer 2"))
    }

    @Test("App-only output carries Host generation but no Safari extension")
    func appOnlyHasNoEmbeddedSafariRuntime() throws {
        let package = try source("script/package_uma_app_only_test.sh")
        let installer = try source("script/install_uma_app_only_test.sh")
        let relaunch = try source("AppleDevelopmentSigning/TestChannelRelaunch.swift")

        #expect(package.contains("UMAPackagingMode</key><string>UMA_APP_ONLY"))
        #expect(package.contains("UMASafariHostRuntimeGenerationID"))
        #expect(package.contains("UMASafariHostExtensionVersion"))
        #expect(package.contains("UMASafariHostExtensionBuild"))
        #expect(package.contains("plist \"$host_receipt\" extensionVersion"))
        #expect(package.contains("plist \"$host_receipt\" extensionBuild"))
        #expect(package.contains("UMASafariHostBundleIdentifier"))
        #expect(package.contains("UMASafariHostExtensionBundleIdentifier"))
        #expect(package.contains("[[ ! -e \"$contents/PlugIns\""))
        #expect(package.contains("UNINTENDED_SAFARI_HOST_MUTATION"))
        #expect(package.contains("schemaVersion -integer 5"))
        #expect(package.contains("appBundleSHA256"))
        #expect(package.contains("appCodeSignatureSHA256"))
        #expect(package.contains("immutableSafariCompanionBundleSHA256"))
        #expect(installer.contains("TestChannelAtomicSwap"))
        #expect(installer.contains("--receipt"))
        #expect(installer.contains("archiveSHA256"))
        #expect(installer.contains("verify_mutable_runtime_metadata"))
        for key in [
            "UMASafariHostBundleIdentifier",
            "UMASafariHostExtensionBundleIdentifier",
            "UMASafariHostRuntimeGenerationID",
            "UMASafariHostExtensionVersion",
            "UMASafariHostExtensionBuild",
            "UMAAppGroupIdentifier",
            "UMATeamIdentifier",
        ] {
            #expect(installer.contains(key))
        }
        #expect(installer.components(separatedBy: "verify_host_lock").count >= 4)
        #expect(installer.contains("UNINTENDED_SAFARI_HOST_MUTATION"))
        #expect(installer.contains("TestChannelRelaunch.swift"))
        #expect(installer.contains("-parse-as-library \"$RELAUNCH_SOURCE\""))
        #expect(installer.contains("-framework AppKit -o \"$relaunch_binary\""))
        #expect(installer.contains(
            "\"$relaunch_binary\" \"$CANONICAL\" \"$APP_ID\" \"$expected_build\" \"$expected_generation\""
        ))
        #expect(relaunch.contains("NSRunningApplication.runningApplications("))
        #expect(relaunch.contains("withBundleIdentifier: expectedIdentifier"))
        #expect(relaunch.contains("func runningApplications()"))
        #expect(relaunch.contains("while !runningApplications().isEmpty"))
        #expect(relaunch.contains("application.terminate()"))
        #expect(relaunch.contains("application.forceTerminate()"))
        #expect(relaunch.contains("gracefulDeadline"))
        #expect(relaunch.contains("forcedDeadline"))
        #expect(relaunch.contains("launched.bundleURL?.standardizedFileURL == canonicalURL"))
        #expect(relaunch.contains("CFBundleVersion"))
        #expect(relaunch.contains("UMASafariHostRuntimeGenerationID"))
        #expect(relaunch.contains("UMARuntimeGenerationID"))
        #expect(relaunch.contains("generationInfoKey"))
        #expect(relaunch.contains("configuration.activates = false"))
        #expect(relaunch.contains("configuration.addsToRecentItems = false"))
        #expect(!installer.contains("pluginkit"))
        #expect(!installer.contains("lsregister"))
        #expect(!package.localizedCaseInsensitiveContains("notary"))
        #expect(!installer.localizedCaseInsensitiveContains("notary"))

        let hostInstaller = try source("script/install_uma_safari_host_core_repair.sh")
        #expect(hostInstaller.contains(
            "\"$(plist \"$receipt\" hostBuild)\" UMARuntimeGenerationID"
        ))
    }

    @Test("Host packaging cannot proceed from a stale or compiler-failing module graph")
    func hostPackageRequiresSuccessfulCoherentReleaseCompilation() throws {
        let package = try source("script/package_uma_safari_host_test.sh")
        let build = try #require(package.range(of: "/usr/bin/xcrun swift build"))
        let stage = try #require(package.range(
            of: "readonly stage=\"$scratch/UMA Safari Bridge Test.app\""
        ))

        #expect(build.lowerBound < stage.lowerBound)
        #expect(package.contains("-c release --product \"$HOST_PRODUCT\""))
        #expect(package.contains("readonly host_binary=\"$bin_path/$HOST_PRODUCT\""))
        #expect(package.contains("[[ -x \"$host_binary\" ]]"))
        #expect(package.contains(
            "\"$DEVELOPER_DIR_REQUIRED/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc\""
        ))
        #expect(package.contains("MacOSX27.0.sdk"))
        #expect(!package.contains("swift build || true"))
    }

    @Test("App-only packaging verifies the immutable Host receipt before and after build")
    func appOnlyEnforcesImmutableHostReceipt() throws {
        let package = try source("script/package_uma_app_only_test.sh")

        for required in [
            "hostBundleSHA256",
            "extensionBundleSHA256",
            "hostExecutableSHA256",
            "extensionExecutableSHA256",
            "hostCDHash",
            "extensionCDHash",
            "runtimeGenerationID",
            "verify_host_lock",
        ] {
            #expect(package.contains(required))
        }
        #expect(package.components(separatedBy: "verify_host_lock").count >= 4)
    }

    @Test("Signing harnesses require matching Team and App Group capabilities")
    func signingHarnessesMatchIdentityContract() throws {
        let hostProject = try source("AppleDevelopmentSigning/UMASafariHostSigning.xcodeproj/project.pbxproj")
        let appProject = try source("AppleDevelopmentSigning/UMAMutableAppSigning.xcodeproj/project.pbxproj")
        let hostEntitlements = try source("AppleDevelopmentSigning/SafariHost/App/UMASafariHost.entitlements")
        let extensionEntitlements = try source("AppleDevelopmentSigning/SafariHost/Extension/ClaudeBrowserCompanion.entitlements")
        let appEntitlements = try source("AppleDevelopmentSigning/MutableApp/UMAApp.entitlements")

        #expect(hostProject.contains("DEVELOPMENT_TEAM = C6TUZVJ6SJ"))
        #expect(hostProject.contains("PRODUCT_BUNDLE_IDENTIFIER = com.silkrd.uma.test.safarihost"))
        #expect(hostProject.contains("PRODUCT_BUNDLE_IDENTIFIER = com.silkrd.uma.test.safarihost.ClaudeBrowserCompanion"))
        #expect(appProject.contains("PRODUCT_BUNDLE_IDENTIFIER = com.silkrd.uma.test"))
        for entitlements in [hostEntitlements, extensionEntitlements, appEntitlements] {
            #expect(entitlements.contains("group.com.silkrd.uma.test.bridge"))
            #expect(!entitlements.contains("com.apple.security.get-task-allow"))
        }
    }

    @Test("Legacy entry points delegate explicit app-only mode before combined packaging")
    func legacyEntryPointsDelegateAppOnly() throws {
        let package = try source("script/package_uma_m5_g2.sh")
        let installer = try source("script/install_uma_apple_development_test.sh")

        #expect(package.contains("exec \"$REPO_ROOT/script/package_uma_app_only_test.sh\" \"$@\""))
        #expect(installer.contains("exec \"$REPO_ROOT/script/install_uma_app_only_test.sh\" \"$@\""))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func auditOwnedTabReceipt(_ receipt: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = repositoryRoot()
            .appendingPathComponent("script/install_uma_safari_host_test.sh")
        process.arguments = ["--audit-owned-tab-receipt", receipt.path]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
