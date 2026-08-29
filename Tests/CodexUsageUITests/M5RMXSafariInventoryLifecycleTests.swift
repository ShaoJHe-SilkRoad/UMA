import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5RMX Safari signed Test Channel lifecycle")
struct M5RMXSafariInventoryLifecycleTests {
    @Test
    func appOnlyRuntimeQualificationPreservesFrozenCompanionTruth() {
        #expect(ClaudeBrowserRuntimeContext.extensionAppMetadataMatches(
            packagingMode: "APP_ONLY",
            appVersion: "0.13.0",
            appBuild: "202608271566",
            extensionAppVersion: "0.13.0",
            extensionAppBuild: "202608270106",
            extensionBuild: "202608270106"
        ))
        #expect(!ClaudeBrowserRuntimeContext.extensionAppMetadataMatches(
            packagingMode: "APP_ONLY",
            appVersion: "0.13.0",
            appBuild: "202608271566",
            extensionAppVersion: "0.13.0",
            extensionAppBuild: "wrong-build",
            extensionBuild: "202608270106"
        ))
        #expect(!ClaudeBrowserRuntimeContext.extensionAppMetadataMatches(
            packagingMode: "COMPANION_MIGRATION",
            appVersion: "0.13.0",
            appBuild: "202608271566",
            extensionAppVersion: "0.13.0",
            extensionAppBuild: "202608270106",
            extensionBuild: "202608270106"
        ))
    }

    @Test
    func appAndExtensionVersionsAreExplicitlyIndependent() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")

        #expect(installer.contains("--expected-version <app-version>"))
        #expect(installer.contains("--expected-extension-version <extension-version>"))
        #expect(installer.contains("appVersion -string \"$expected_version\""))
        #expect(installer.contains("extensionVersion -string \"$expected_extension_version\""))
        #expect(installer.contains(
            "CFBundleShortVersionString)\" == \"$expected_extension_version\""
        ))
    }

    @Test
    func packageArtifactAndActiveInstallationAreDistinct() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")

        #expect(installer.contains(
            "readonly DELIVERY_ROOT=\"$DELIVERY_VOLUME/UMA/Packages\""
        ))
        #expect(installer.contains(
            "readonly CANONICAL_INSTALL_PATH=\"$HOME/Applications/UMA_0.13.0-Test.app\""
        ))
        #expect(installer.contains("build_artifact=%s active_install=%s"))
        #expect(installer.contains("Artifact is outside the immutable package boundary"))
        #expect(!installer.contains("open -gja \"$artifact\""))
        #expect(installer.contains("open -ga \"$CANONICAL_INSTALL_PATH\""))
        #expect(!installer.contains("open -gja"))
    }

    @Test
    func updateVerifiesThenActivatesWithoutReplacingFrozenCompanionIdentity() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")
        let swap = try source("AppleDevelopmentSigning/TestChannelAtomicSwap.swift")

        #expect(installer.contains("codesign --verify --deep --strict"))
        #expect(installer.contains("Authority=$EXPECTED_AUTHORITY"))
        #expect(installer.contains("TeamIdentifier=$EXPECTED_TEAM"))
        #expect(installer.contains(
            "\"$swap_binary\" --preserve-nested-extension \"$staged_app\" \"$CANONICAL_INSTALL_PATH\""
        ))
        #expect(swap.contains("renameatx_np"))
        #expect(swap.contains("RENAME_SWAP"))
        #expect(swap.contains("preservedExtensionChanged"))
        #expect(swap.contains("originalExtensionMetadata.st_ino == finalExtensionMetadata.st_ino"))
        #expect(swap.contains("for pair in exchanged.reversed()"))
        #expect(installer.contains("canonical_extension_file_id"))
        #expect(installer.contains("stat -f '%d:%i' \"$canonical_appex\""))
        #expect(swap.contains("staged and canonical apps must have the same parent directory"))
        #expect(installer.contains(
            "staged_app=\"$(/usr/bin/mktemp -d \"$HOME/Applications/.UMA_0.13.0-Test.install.XXXXXX\")\""
        ))
        #expect(installer.contains(
            "$(/usr/bin/dirname \"$staged_app\")\" == \"$HOME/Applications"
        ))
        #expect(installer.contains(
            "$(/usr/bin/stat -f %u \"$staged_app\")\" == \"$(/usr/bin/id -u)"
        ))
        #expect(!installer.contains("$staging_directory/UMA_0.13.0-Test.app"))
        #expect(!installer.contains("staging_directory="))
        #expect(installer.contains("Stop only a process whose text image is the canonical Test App"))
        #expect(!installer.contains("kill -KILL"))
    }

    @Test
    func exactExtensionBuildDeterminesSafariInventoryAdoption() throws {
        let current = try run([
            "--classify-inventory",
            "--expected-extension-version", "1.4.0",
            "--expected-extension-build", "10",
            "--safari-running", "yes",
            "--observed-version", "1.4.0",
            "--observed-extension-build", "10",
        ])
        #expect(current.output == "SAFARI_INVENTORY_CURRENT restart_required=false")
        #expect(current.status == 0)

        let stale = try run([
            "--classify-inventory",
            "--expected-extension-version", "1.4.0",
            "--expected-extension-build", "10",
            "--safari-running", "yes",
            "--observed-version", "1.4.0",
            "--observed-extension-build", "9",
        ])
        #expect(stale.output == "SAFARI_INVENTORY_STALE restart_required=true")
        #expect(stale.status == 0)

        let safariClosed = try run([
            "--classify-inventory",
            "--expected-extension-version", "1.4.0",
            "--expected-extension-build", "10",
            "--safari-running", "no",
            "--observed-version", "none",
            "--observed-extension-build", "none",
        ])
        #expect(safariClosed.output ==
            "SAFARI_INVENTORY_REFRESH_ON_LAUNCH restart_required=false")
        #expect(safariClosed.status == 0)
    }

    @Test
    func ownerOnlyReceiptIsAtomicContentFreeAndHandshakeGated() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")

        for required in [
            "SafariTestChannel",
            "schemaVersion",
            "canonicalAppPath",
            "appBundleIdentifier",
            "appVersion",
            "appBuild",
            "extensionBundleIdentifier",
            "extensionVersion",
            "extensionBuild",
            "teamIdentifier",
            "lifecycleState",
            "handshakeVerified",
            "updatedAt",
            "safariRestartRequired",
            "inventoryCurrent",
            "chmod 700",
            "chmod 600",
            "mv -f \"$temporary\" \"$INVENTORY_RECEIPT\"",
        ] {
            #expect(installer.contains(required))
        }
        for forbidden in [
            "quota",
            "cookie",
            "token",
            "credential",
            "page content",
            "DOM",
        ] {
            #expect(!installer.localizedCaseInsensitiveContains(forbidden))
        }

        let rejected = try run([
            "--mark-inventory-current",
            "--expected-version", "0.13.0",
            "--expected-extension-version", "1.4.0",
            "--expected-app-build", "202608260101",
            "--expected-extension-build", "10",
        ])
        #expect(rejected.status == 2)
        #expect(rejected.error.contains(
            "inventoryCurrent requires an explicit machine handshake receipt."
        ))
    }

    @Test
    func alreadyCurrentInstallCannotBypassRegistrationReconciliation() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")
        let start = try #require(installer.range(
            of: "if [[ \"$installed_app_cdhash\" == \"$artifact_app_cdhash\" ]]"
        ))
        let tail = installer[start.lowerBound...]
        let end = try #require(tail.range(of: "    exit 0\nfi"))
        let alreadyCurrent = String(tail[..<end.upperBound])

        let retire = try #require(alreadyCurrent.range(
            of: "retire_task_owned_package_registrations"
        ))
        let retireLaunchServices = try #require(alreadyCurrent.range(
            of: "retire_stale_launchservices_registrations"
        ))
        let reconcile = try #require(alreadyCurrent.range(
            of: "reconcile_canonical_registration_once"
        ))
        let launch = try #require(alreadyCurrent.range(of: "launch_canonical_once"))
        let receipt = try #require(alreadyCurrent.range(
            of: "write_inventory_receipt inventoryCurrent false"
        ))
        let success = try #require(alreadyCurrent.range(of: "TEST_APP_ALREADY_CURRENT"))
        #expect(retire.lowerBound < retireLaunchServices.lowerBound)
        #expect(retireLaunchServices.lowerBound < reconcile.lowerBound)
        #expect(reconcile.lowerBound < launch.lowerBound)
        #expect(launch.lowerBound < receipt.lowerBound)
        #expect(receipt.lowerBound < success.lowerBound)
        #expect(!alreadyCurrent.contains("$swap_binary"))
        #expect(installer.contains("/usr/bin/open -ga \"$CANONICAL_INSTALL_PATH\""))
        #expect(!installer.contains("/usr/bin/open -gja"))
        #expect(!installer.contains("open -gja \"$artifact\""))
        #expect(installer.components(separatedBy: "launch_canonical_once\n").count - 1 == 2)
        #expect(installer.components(
            separatedBy: "retire_task_owned_package_registrations\n"
        ).count - 1 == 2)
        #expect(alreadyCurrent.components(
            separatedBy: "require_unique_canonical_registration\n"
        ).count - 1 == 1)
        let reconcileStart = try #require(installer.range(
            of: "reconcile_canonical_registration_once() {"
        ))
        let launchStart = try #require(installer.range(of: "launch_canonical_once() {"))
        let reconciliation = String(installer[
            reconcileStart.lowerBound..<launchStart.lowerBound
        ])
        #expect(reconciliation.contains("require_canonical_launchservices_registration"))
        #expect(reconciliation.contains("require_unique_canonical_registration"))
    }

    @Test
    func lifecycleHasOneBoundedUpdateAndHandshakePath() throws {
        let contract = try run(["--print-transition-contract"])
        #expect(contract.status == 0)
        for transition in [
            "NO_TEST_APP->INSTALLING",
            "READY_OLD_BUILD->INSTALLING_NEW_BUILD",
            "SIGNED_APP_INSTALLED->EXTENSION_REGISTERED",
            "EXTENSION_REGISTERED->SAFARI_INVENTORY_STALE",
            "SAFARI_INVENTORY_STALE->SAFARI_RESTART_REQUIRED",
            "SAFARI_RESTART_REQUIRED->SAFARI_INVENTORY_CURRENT",
            "SAFARI_INVENTORY_CURRENT->COMPANION_STARTING",
            "COMPANION_STARTING->COMPANION_VERIFIED",
            "COMPANION_VERIFIED->READY",
        ] {
            #expect(contract.output.contains(transition))
        }
    }

    @Test
    func launchServicesReconciliationIsExactProtectedAndIdempotent() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let fixtures: [(String, String)] = [
            ("\(home)/Applications/UMA_0.13.0-Test.app", "CANONICAL_TEST_APP"),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-0.13-apple-dev-test-0001/UMA_0.13.0.app",
                "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-0.13-dev-0001/UMA_0.13.0.app",
                "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
            ),
            (
                "\(home)/Developer/UMA-Packages/uma-0.13-dev-legacy1/UMA_0.13.0.app",
                "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
            ),
            (
                "\(home)/Developer/UMA-Packages/uma-0.13-dev-final-legacy2/UMA_0.13.0.app",
                "PROTECTED_PACKAGE_ARTIFACT"
            ),
            (
                "\(home)/Developer/UMA-Packages/uma-0.13-dev-preflight-legacy3/UMA_0.13.0.app",
                "PROTECTED_PACKAGE_ARTIFACT"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-inventory-test-0002/UMA_0.13.0.app",
                "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-development-test-0002/UMA_0.13.0.app",
                "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-signed-test-0002/UMA_0.13.0.app",
                "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-safari-test-0002/UMA_0.13.0.app",
                "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-final-0003/UMA_0.13.0.app",
                "PROTECTED_PACKAGE_ARTIFACT"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-preflight-0004/UMA_0.13.0.app",
                "PROTECTED_PACKAGE_ARTIFACT"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-release-0005/UMA_0.13.0.app",
                "PROTECTED_PACKAGE_ARTIFACT"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-archive-0006/UMA_0.13.0.app",
                "PROTECTED_PACKAGE_ARTIFACT"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-rollback-0007/UMA_0.13.0.app",
                "PROTECTED_PACKAGE_ARTIFACT"
            ),
            (
                "/Volumes/HE/DEV/UMA/Packages/uma-m5rmx-notary-0008/UMA_0.13.0.app",
                "PROTECTED_PACKAGE_ARTIFACT"
            ),
            ("\(home)/Desktop/UMA_0.12.app", "PROTECTED_APP"),
            ("/Applications/UMA.app", "PROTECTED_APP"),
            ("/private/tmp/unrelated/UMA_0.13.0.app", "UNRELATED"),
        ]
        for (path, expected) in fixtures {
            let result = try run(["--classify-launchservices-path", path])
            #expect(result.status == 0)
            #expect(result.output == expected)
        }
        let retireableAlias = try run([
            "--classify-launchservices-path",
            "\(home)/Developer/UMA-Packages/uma-0.13-dev-alias/UMA_0.13.0.app",
        ])
        let maliciousResolvedTarget = try run([
            "--classify-launchservices-path",
            "/Volumes/HE/DEV/UMA/Packages/uma-0.13-dev-final-target/UMA_0.13.0.app",
        ])
        #expect(retireableAlias.output == "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION")
        #expect(maliciousResolvedTarget.output == "PROTECTED_PACKAGE_ARTIFACT")


        #expect(installer.contains("LSCopyApplicationURLsForBundleIdentifier"))
        #expect(installer.contains("\"com.silkrd.uma.test\" as CFString"))
        #expect(installer.contains("validated_resolved_retirement_path"))
        #expect(installer.contains("CommandLine.arguments[1] == \"--resolve\""))
        #expect(installer.contains(".resolvingSymlinksInPath()"))
        #expect(installer.contains(".standardizedFileURL.path"))
        #expect(installer.contains(
            "resolved_path=\"$(launchservices_resolved_path \"$recorded_path\")\""
        ))
        #expect(!installer.contains("/usr/bin/realpath"))
        #expect(installer.contains(
            "resolved_classification=\"$(classify_launchservices_path \"$resolved_path\")\""
        ))
        #expect(installer.contains(
            "resolved_classification\" == RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
        ))
        #expect(installer.contains("\"$LSREGISTER\" -u \"$app_path\""))
        #expect(installer.contains("\"$LSREGISTER\" -u \"$resolved_path\""))
        let ownerGateStart = try #require(installer.range(
            of: "require_canonical_launchservices_registration() {"
        ))
        let registeredPathsStart = try #require(installer.range(
            of: "registered_extension_paths() {"
        ))
        let ownerGate = String(installer[
            ownerGateStart.lowerBound..<registeredPathsStart.lowerBound
        ])
        #expect(ownerGate.contains("owner_paths=\"$(launchservices_app_paths)\""))
        #expect(ownerGate.contains("\"$owner_paths\" == \"$CANONICAL_INSTALL_PATH\""))
        #expect(!installer.contains(
            "A task-owned stale LaunchServices alias or resolved registration remains."
        ))
        #expect(installer.contains("retire_stale_launchservices_registrations"))
        #expect(installer.contains("require_canonical_launchservices_registration"))
        #expect(installer.components(
            separatedBy: "retire_stale_launchservices_registrations\n"
        ).count - 1 == 2)
        #expect(installer.components(
            separatedBy: "require_canonical_launchservices_registration\n"
        ).count - 1 == 4)
        #expect(installer.contains(
            "for package_root in \"$DELIVERY_ROOT\" \"$LEGACY_DEVELOPMENT_PACKAGE_ROOT\""
        ))
        #expect(installer.contains(
            "\\( -name UMA_0.13.0-Test.app -o -name UMA_0.13.0.app \\) -print"
        ))
        #expect(installer.contains(
            "== RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
        ))
        #expect(installer.contains(
            "classification\" == RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION"
        ))
        #expect(!installer.contains("mdfind"))
    }

    @Test
    func foundationResolveModeCanonicalizesSymlinkAlias() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "uma-ls-resolve-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: fixtureRoot) }
        let target = fixtureRoot.appendingPathComponent("target", isDirectory: true)
        let alias = fixtureRoot.appendingPathComponent("alias", isDirectory: true)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: alias, withDestinationURL: target)

        let resolved = alias.resolvingSymlinksInPath().standardizedFileURL.path

        #expect(resolved == target.standardizedFileURL.path)
    }

    @Test
    func onlyTaskOwnedPackageRegistrationsCanBeRetired() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")

        let currentVerboseFixture = "    Path = /Users/test/Applications/UMA_0.13.0-Test.app/Contents/PlugIns/ClaudeBrowserCompanion.appex"
        let fixturePath = String(currentVerboseFixture.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).dropFirst("Path = ".count))
        #expect(fixturePath == "/Users/test/Applications/UMA_0.13.0-Test.app/Contents/PlugIns/ClaudeBrowserCompanion.appex")
        #expect(installer.contains("pluginkit -m -A -D -vv -i"))
        #expect(installer.contains(
            "Path = (/.*\\.appex)[[:space:]]*$#\\1#p"
        ))
        #expect(installer.contains(
            "s#^.* (/.*\\.appex)[[:space:]]*$#\\1#p"
        ))
        #expect(installer.contains("pluginkit -r \"$registered_appex\""))
        #expect(installer.contains("\"$LSREGISTER\" -u \"$containing_package_app\""))
        #expect(installer.contains(
            "if registered_extension_paths | /usr/bin/grep -F -x -q \"$registered_appex\""
        ))
        #expect(installer.contains("registered_path_count\" == 1"))
        #expect(installer.contains("canonical_path_count\" == 1"))
        #expect(installer.contains(
            "RUNTIME_IDENTITY_AMBIGUOUS: PlugInKit owners"
        ))
        #expect(!installer.contains("grep -F -q \"$canonical_appex\" \"$registration_report\""))
        #expect(installer.contains(
            "classification=\"$(classify_launchservices_path \"$containing_package_app\")\""
        ))
        #expect(!installer.contains("/Users/juliushe/Desktop/UMA_0.12.app"))
        #expect(!installer.contains("mdfind"))
        #expect(!installer.contains("killall Safari"))
        #expect(!installer.contains("osascript"))
    }

    @Test
    func packagingDerivesSafariCompanionVersionAndBuildFromItsInfoPlist() throws {
        let package = try source("script/package_uma_m5_g2.sh")

        #expect(package.contains(
            "grep -F -c 'api.runtime.connectNative(config.nativeApplication)'"
        ))
        #expect(package.contains("config.browserFamily !== \"safari\""))
        #expect(package.contains("port.onMessage.addListener((message) =>"))
        #expect(package.contains("port.onDisconnect.addListener(() =>"))
        #expect(package.contains("containingAppPortGeneration !== generation"))
        #expect(package.contains("claudeBrowserRuntimeQualificationAcknowledgement"))
        #expect(package.contains(
            "\"$source_root/BrowserExtension/Chromium/background-loader.js\""
        ))
        #expect(package.contains("! /usr/bin/grep -F -q 'nativeReconnectTimer'"))
        #expect(package.contains("Print :CFBundleShortVersionString' \"$safari_info_plist\""))
        #expect(package.contains("Print :CFBundleVersion' \"$safari_info_plist\""))
        #expect(package.contains("companionVersion: \"$extension_version\""))
        #expect(package.contains("companionBuild: \"$extension_build\""))
        #expect(package.contains("runtimeGenerationID: \"$runtime_generation_id\""))
        #expect(package.contains("nativeApplication: \"$BUNDLE_ID\""))
        #expect(package.contains(
            "extensionBundleIdentifier: \"$SAFARI_EXTENSION_ID\""
        ))
        #expect(package.contains("extensionVersion -string \"$extension_version\""))
        #expect(package.contains("extensionBuild -string \"$extension_build\""))
        #expect(!package.contains("companionVersion: \"1.4.0\""))
        #expect(!package.contains("companionBuild: \"10\""))
        #expect(package.contains("verify_packaged_runtime_metadata"))
        #expect(package.contains("UMARuntimeGenerationID"))
        #expect(!package.contains("runtime_generation_id=\"production\""))
    }

    private func run(_ arguments: [String]) throws -> (
        output: String,
        error: String,
        status: Int32
    ) {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = repositoryRoot().appendingPathComponent(
            "script/install_uma_apple_development_test.sh"
        )
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        return (
            String(
                decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            process.terminationStatus
        )
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
