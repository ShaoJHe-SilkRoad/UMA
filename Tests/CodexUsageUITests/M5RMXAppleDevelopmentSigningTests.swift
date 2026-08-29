import Foundation
import Testing

@Suite("M5RMX Apple Development signed test channel")
struct M5RMXAppleDevelopmentSigningTests {
    @Test
    func signingTrustPreflightSeparatesExecutionContextFromArtifactIntegrity() throws {
        let preflight = try source(
            "script/verify_uma_apple_development_trust_context.sh"
        )
        let packageScripts = try [
            "script/package_uma_app_only_test.sh",
            "script/package_uma_safari_host_test.sh",
        ].map(source)
        let installScripts = try [
            "script/install_uma_app_only_test.sh",
            "script/install_uma_safari_host_test.sh",
        ].map(source)
        let harness = try source("script/verify_uma_apple_development_signing.sh")

        for required in [
            "APPLE_SIGNING_TRUST_CONTEXT_UNAVAILABLE",
            "APPLE_SIGNING_IDENTITY_MISMATCH",
            "APPLE_SIGNING_CERTIFICATE_CHAIN_INVALID",
            "APPLE_SIGNED_ARTIFACT_IDENTITY_MISMATCH",
            "APPLE_PROFILE_SIGNER_MISMATCH",
            "security list-keychains -d user",
            "security find-identity -v -p codesigning",
            "security verify-cert -c \"$leaf\" -p codeSign",
            "530C76742575129DF3F6C5571842337E6323042E51D91685E05D291D1861E200",
            "CN=Apple Worldwide Developer Relations Certification Authority",
            "'OU=G3'",
            "'O=Apple Inc.'",
            "--timestamp=none",
            "codesign --verify --deep --strict",
            "--extract-certificates=",
            "DeveloperCertificates:$index",
        ] {
            #expect(preflight.contains(required))
        }
        #expect(!preflight.contains("retry"))
        #expect(!preflight.contains("security add-trusted-cert"))
        #expect(!preflight.contains("security trust-settings-export"))
        #expect(preflight.components(
            separatedBy: "for profile in ${profiles[@]+\"${profiles[@]}\"}; do"
        ).count == 3)
        #expect(!preflight.contains("for profile in \"${profiles[@]}\"; do"))
        for package in packageScripts {
            #expect(package.contains("$TRUST_PREFLIGHT\" --mode signing"))
            #expect(package.contains("$TRUST_PREFLIGHT\" --mode verification --artifact"))
            #expect(package.contains("--profile"))
        }
        for installer in installScripts {
            #expect(installer.contains(
                "$TRUST_PREFLIGHT\" --mode verification --artifact"
            ))
            #expect(installer.contains("--profile"))
        }
        #expect(harness.contains("$TRUST_PREFLIGHT\" --mode signing"))
        #expect(installScripts[0].contains(
            "--artifact \"$CANONICAL\""
        ))
        #expect(installScripts[0].contains(
            "bundle_tree_sha256 \"$CANONICAL\""
        ))
    }

    @Test
    func hostCoreRepairPreservesFrozenCompanionAndRegistration() throws {
        let package = try source("script/package_uma_safari_host_core_repair.sh")
        let installer = try source("script/install_uma_safari_host_core_repair.sh")
        for required in [
            "SAFARI_HOST_CORE_REPAIR",
            "UNINTENDED_COMPANION_MUTATION",
            "extensionBundleSHA256",
            "extensionExecutableSHA256",
            "extensionCDHash",
            "--mode verification --artifact",
            "--profile",
        ] {
            #expect(package.contains(required))
            #expect(installer.contains(required))
        }
        #expect(!package.contains("SafariWebExtensionHandler.swift"))
        #expect(!package.contains("background-core.js"))
        #expect(!package.contains("manifest.json"))
        #expect(!package.contains("--identifier \"$EXTENSION_ID\""))
        #expect(installer.contains("--preserve-nested-extension"))
        #expect(installer.contains("swap_completed"))
        #expect(installer.contains("qualified"))
        #expect(installer.contains("SAFARI_HOST_CORE_REPAIR_REGISTRATION_CHANGED"))
        #expect(installer.contains("/usr/bin/pluginkit -m"))
        #expect(installer.contains("registration_mutations=0"))
        #expect(!installer.contains("/usr/bin/pluginkit -a"))
        #expect(!installer.contains("/usr/bin/pluginkit -r"))
        #expect(!installer.contains("lsregister"))
    }

    @Test
    func immutableHostAndMutableAppRequireExactAppGroupProfiles() throws {
        let hostProject = try source(
            "AppleDevelopmentSigning/UMASafariHostSigning.xcodeproj/project.pbxproj"
        )
        let mutableProject = try source(
            "AppleDevelopmentSigning/UMAMutableAppSigning.xcodeproj/project.pbxproj"
        )
        let hostPackage = try source("script/package_uma_safari_host_test.sh")
        let appPackage = try source("script/package_uma_app_only_test.sh")

        for required in [
            "PROVISIONING_PROFILE_SPECIFIER = \"UMA Safari Host Test Development v2\"",
            "PROVISIONING_PROFILE_SPECIFIER = \"UMA Claude Companion Test Development v2\"",
            "PRODUCT_BUNDLE_IDENTIFIER = com.silkrd.uma.test.safarihost",
            "PRODUCT_BUNDLE_IDENTIFIER = com.silkrd.uma.test.safarihost.ClaudeBrowserCompanion",
            "DEVELOPMENT_TEAM = C6TUZVJ6SJ",
        ] {
            #expect(hostProject.contains(required))
        }
        #expect(mutableProject.contains(
            "PROVISIONING_PROFILE_SPECIFIER = \"UMA Mutable App Test Development\""
        ))
        #expect(mutableProject.contains("PRODUCT_BUNDLE_IDENTIFIER = com.silkrd.uma.test"))
        #expect(mutableProject.contains("DEVELOPMENT_TEAM = C6TUZVJ6SJ"))
        for source in [hostPackage, appPackage] {
            #expect(source.contains("group.com.silkrd.uma.test.bridge"))
            #expect(source.contains("com.apple.security.application-groups:0"))
            #expect(source.contains("com.apple.security.get-task-allow"))
        }
        #expect(hostPackage.contains("UMA Safari Host Test Development v2"))
        #expect(hostPackage.contains("UMA Claude Companion Test Development v2"))
        #expect(appPackage.contains("UMA Mutable App Test Development"))
    }

    @Test
    func packageModeIsDedicatedAndNeverFallsBackToAdHocOrNotary() throws {
        let package = try source("script/package_uma_m5_g2.sh")
        let block = try #require(package.range(of: "    apple-development-test)"))
        let tail = String(package[block.lowerBound...])
        let end = try #require(tail.range(of: "        ;;"))
        let mode = String(tail[..<end.upperBound])

        #expect(mode.contains("uma-0.13-apple-dev-test-"))
        #expect(mode.contains("Apple Development: SHAOTING HE (5BN4FAQSUF)"))
        #expect(mode.contains("Apple Development via Xcode automatic signing"))
        #expect(mode.contains("Apple Development test mode never submits for notarization."))
        #expect(!mode.contains("signing_identity=\"-\""))
        #expect(package.contains("signing_kind=\"apple-development\""))
        #expect(package.contains("codesign_options+=(--timestamp=none)"))
        #expect(package.contains("Ad-hoc signature forbidden in Apple Development mode"))
        #expect(package.contains(
            "|| \"$phase\" == \"apple-development-test\" ]]; then"
        ))
        #expect(package.contains(
            "\"permissions\": [\"nativeMessaging\", \"https://claude.ai/new*\"]"
        ))
        #expect(package.contains("Identifier=$expected_signed_identifier"))
        for identifier in [
            "$NATIVE_HOST_ID",
            "$STATUS_RELAY_ID",
            "$SAFARI_EXTENSION_ID",
            "$BUNDLE_ID",
        ] {
            #expect(package.contains("expected_signed_identifier=\"\(identifier)\""))
        }
    }

    @Test
    func testChannelUsesDedicatedRuntimeIdentityAndImmutableArchiveDelivery() throws {
        let package = try source("script/package_uma_m5_g2.sh")
        let installer = try source("script/install_uma_apple_development_test.sh")

        for required in [
            "BUNDLE_ID=\"com.silkrd.uma.test\"",
            "SAFARI_EXTENSION_ID=\"$BUNDLE_ID.ClaudeBrowserCompanion\"",
            "NATIVE_HOST_ID=\"$BUNDLE_ID.ClaudeBrowserNativeHost\"",
            "STATUS_RELAY_ID=\"$BUNDLE_ID.ClaudeStatusLineRelay\"",
            "UMA_0.13.0-Test.zip",
            "UMATestRuntimeGenerationID",
            "runtimeGenerationID",
            "ditto -c -k --keepParent",
            "archiveSHA256",
        ] {
            #expect(package.contains(required))
        }
        #expect(package.contains("output=\"$package_root/UMA_0.13.0-Test.app\""))
        #expect(installer.contains("readonly APP_ID=\"com.silkrd.uma.test\""))
        #expect(installer.contains("UMA_0.13.0-Test.zip"))
        #expect(installer.contains("RUNTIME_IDENTITY_AMBIGUOUS"))
        #expect(installer.contains("--retire-historical-development-apps"))
        #expect(!installer.contains("for _ in {1..50}"))
        #expect(!installer.contains("--preferred"))
    }

    @Test
    func installerRequiresExactOwnerSetsAndMatchingGeneration() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")

        #expect(installer.contains("[[ \"$owner_paths\" == \"$CANONICAL_INSTALL_PATH\" ]]"))
        #expect(installer.contains("registered_path_count\" == 1"))
        #expect(installer.contains("appex_generation_id\" == \"$runtime_generation_id\""))
        #expect(installer.contains("receipt_generation_id\" == \"$runtime_generation_id\""))
        #expect(installer.contains("reconcile_canonical_registration_once"))
        #expect(installer.contains(
            "Print :schemaVersion' \"$package_receipt\")\" == 3"
        ))
        #expect(installer.contains("write_inventory_receipt inventoryCurrent false"))
        #expect(installer.contains("launch_canonical_once"))
        #expect(installer.contains("/usr/bin/open -ga \"$CANONICAL_INSTALL_PATH\""))
        #expect(!installer.contains("/usr/bin/open -gja"))
        #expect(!installer.contains("open -gja \"$artifact\""))
    }

    @Test
    func launchServicesClassifierRecognizesCurrentTestArtifactNameAndProtectsReleasePaths() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        #expect(try classifyLaunchServicesPath(
            "\(home)/Applications/UMA_0.13.0-Test.app"
        ) == "CANONICAL_TEST_APP")
        #expect(try classifyLaunchServicesPath(
            "/Volumes/HE/DEV/UMA/Packages/uma-0.13-apple-dev-test-fixture/UMA_0.13.0-Test.app"
        ) == "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION")
        #expect(try classifyLaunchServicesPath(
            "/Volumes/HE/DEV/UMA/Packages/uma-0.13-development-test-fixture/UMA_0.13.0.app"
        ) == "RETIRE_TASK_OWNED_DEVELOPMENT_REGISTRATION")
        #expect(try classifyLaunchServicesPath(
            "/Volumes/HE/DEV/UMA/Packages/uma-0.13-final-fixture/UMA_0.13.0-Test.app"
        ) == "PROTECTED_PACKAGE_ARTIFACT")
        #expect(try classifyLaunchServicesPath(
            "\(home)/Applications/Unrelated.app"
        ) == "PROTECTED_APP")
        #expect(try classifyLaunchServicesPath(
            "/private/tmp/Unrelated.app"
        ) == "UNRELATED")
    }

    @Test
    func canonicalUpdateAvoidsExplicitRegistrationReset() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")

        #expect(!installer.contains(
            "\"$LSREGISTER\" -u \"$CANONICAL_INSTALL_PATH\""
        ))
        #expect(installer.contains("if [[ \"$packaging_mode\" == COMPANION_MIGRATION ]]; then"))
        #expect(installer.contains("require_canonical_launchservices_registration"))
        #expect(installer.contains("require_unique_canonical_registration"))
        #expect(installer.contains("preserve the physical identity"))
        #expect(installer.contains("discard its Human enablement decision"))
        #expect(installer.contains("--preserve-nested-extension"))
    }

    @Test
    func packageMetadataUsesTheBuiltExtensionVersionContract() throws {
        let package = try source("script/package_uma_m5_g2.sh")

        #expect(package.contains(
            "extension_version=\"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \"$safari_info_plist\")\""
        ))
        #expect(package.contains(
            "source_extension_build=\"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \"$safari_info_plist\")\""
        ))
        #expect(package.contains("extension_build=\"$build_number\""))
        #expect(package.contains("Set :CFBundleVersion $extension_build"))
        #expect(package.contains("companionVersion: \"$extension_version\""))
        #expect(package.contains("companionBuild: \"$extension_build\""))
        #expect(package.contains("extensionVersion -string \"$extension_version\""))
        #expect(package.contains("extensionBuild -string \"$extension_build\""))
    }

    @Test
    func packageAllowlistIncludesOwnedProviderV2AndExcludesRetiredBootstrap() throws {
        let package = try source("script/package_uma_m5_g2.sh")

        for resource in [
            "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/provider-ownership-v2.js",
            "Contents/PlugIns/$SAFARI_EXTENSION.appex/Contents/Resources/Shared/owned-provider-tab-v2-reducer.js",
        ] {
            #expect(package.contains(resource))
        }
        #expect(!package.contains("owned-tab-bootstrap.html"))
        #expect(!package.contains("owned-tab-bootstrap.js"))
    }

    @Test
    func appleDevelopmentTestPackageIsSafariOnlyAndProductionKeepsChromium() throws {
        let package = try source("script/package_uma_m5_g2.sh")

        #expect(package.contains("if [[ \"$phase\" != \"apple-development-test\" ]]; then"))
        #expect(package.contains(
            "Apple Development Test package must be Safari-only; Chromium resources are forbidden."
        ))
        #expect(package.contains(
            "[[ ! -e \"$chromium_root\" && ! -e \"$chromium_host_root\" ]]"
        ))
        #expect(package.contains(
            "expected_manifest_entries+=(\n" +
                "        \"Contents/Resources/BrowserCompanion/Chromium/Chromium/background-loader.js\""
        ))
        #expect(package.contains(
            "install -m 644 \"$source_root/BrowserExtension/Chromium/manifest.json\" " +
                "\"$chromium_root/manifest.json\""
        ))
    }

    @Test
    func productionIdentityRemainsTheDefaultOutsideTestMode() throws {
        let package = try source("script/package_uma_m5_g2.sh")
        let testMode = try #require(package.range(of: "    apple-development-test)"))
        let prefix = String(package[..<testMode.lowerBound])

        #expect(prefix.contains("BUNDLE_ID=\"com.silkrd.uma\""))
        #expect(prefix.contains("SAFARI_EXTENSION_ID=\"$BUNDLE_ID.ClaudeBrowserCompanion\""))
    }

    @Test
    func everyPackageMintsMatchingAuthoritativeRuntimeMetadata() throws {
        let package = try source("script/package_uma_m5_g2.sh")

        for required in [
            "app_package_generation_id=\"$(mint_runtime_generation_id)\"",
            "runtime_generation_id=\"$app_package_generation_id\"",
            "runtime_channel=\"production\"",
            "UMARuntimeGenerationID=$runtime_generation_id",
            "UMATeamIdentifier=C6TUZVJ6SJ",
            "UMAContainingApplicationIdentifier=$BUNDLE_ID",
            "UMAExtensionBundleIdentifier=$SAFARI_EXTENSION_ID",
            "UMAAppVersion=$resolved_marketing_version",
            "UMAAppBuild=$build_number",
            "UMAExtensionVersion=$extension_version",
            "UMAExtensionBuild=$extension_build",
            "verify_packaged_runtime_metadata",
            "Package runtime metadata mismatch",
            "Package bundle identity/version metadata mismatch",
            "nativeApplication: \"$BUNDLE_ID\"",
            "protocolSchemaVersion: 2",
            "containingApplicationIdentifier: \"$BUNDLE_ID\"",
            "extensionBundleIdentifier: \"$SAFARI_EXTENSION_ID\"",
            "teamIdentifier: \"C6TUZVJ6SJ\"",
            "runtimeGenerationID: \"$runtime_generation_id\"",
        ] {
            #expect(package.contains(required))
        }
        #expect(!package.contains("runtime_generation_id=\"production\""))
        #expect(!package.contains("UMATeamIdentifier</key><string>production"))
        let loaderStart = try #require(package.range(
            of: "cat > \"$appex_contents/Resources/Safari/background-loader.js\" <<LOADER"
        ))
        let loaderPrefix = String(package[..<loaderStart.lowerBound])
        #expect(!loaderPrefix.hasSuffix("if [[ \"$phase\" == \"apple-development-test\" ]]; then\n"))
    }

    @Test
    func packageGenerationChangesAcrossInvocations() throws {
        let first = try mintGeneration()
        let second = try mintGeneration()

        #expect(UUID(uuidString: first) != nil)
        #expect(UUID(uuidString: second) != nil)
        #expect(first == first.lowercased())
        #expect(second == second.lowercased())
        #expect(first != second)
    }

    @Test
    func appOnlyModeTreatsTheCompanionAsOpaqueFrozenSignedBytes() throws {
        let package = try source("script/package_uma_m5_g2.sh")
        let installer = try source("script/install_uma_apple_development_test.sh")

        for required in [
            "--packaging-mode <UMA_APP_ONLY|APP_ONLY|COMPANION_MIGRATION>",
            "--frozen-companion <exact.appex>",
            "--frozen-companion-receipt <receipt.plist>",
            "bundle_tree_sha256",
            "extensionExecutableSHA256",
            "extensionCDHash",
            "extensionBundleSHA256",
            "UNINTENDED_COMPANION_MUTATION",
            "FAIL PACKAGE — UNINTENDED_COMPANION_MUTATION",
            "if [[ \"$packaging_mode\" != APP_ONLY ]]; then",
            "/usr/bin/ditto \"$frozen_companion\" \"$appex\"",
            "UMAAppPackageGenerationID",
            "appPackageGenerationID",
        ] {
            #expect(package.contains(required))
        }
        #expect(package.contains("packagingMode -string \"$packaging_mode\""))
        #expect(installer.contains("--packaging-mode <UMA_APP_ONLY|APP_ONLY|COMPANION_MIGRATION>"))
        #expect(installer.contains("artifact Companion differs from receipt"))
        #expect(installer.contains("APP_ONLY update changed Companion bytes"))
    }

    @Test
    func appOnlyUpdatesNeverMutateRegistrationAndMigrationOwnsReconciliation() throws {
        let installer = try source("script/install_uma_apple_development_test.sh")

        #expect(installer.contains(
            "if [[ \"$packaging_mode\" == APP_ONLY ]]; then\n" +
                "        require_canonical_launchservices_registration\n" +
                "        require_unique_canonical_registration"
        ))
        #expect(installer.contains(
            "if [[ \"$packaging_mode\" == COMPANION_MIGRATION ]]; then\n" +
                "    \"$LSREGISTER\" -f \"$CANONICAL_INSTALL_PATH\""
        ))
        #expect(installer.contains(
            "App-only updates must not mutate LaunchServices or PlugInKit."
        ))
    }

    @Test
    func frozenCompanionKeepsTestProductionSeparationAndIndependentAppGeneration() throws {
        let package = try source("script/package_uma_m5_g2.sh")

        #expect(package.contains("runtimeChannel -string test"))
        #expect(package.contains(
            "extensionBundleIdentifier' \"$frozen_companion_receipt\")\" == \"$SAFARI_EXTENSION_ID\""
        ))
        #expect(package.contains(
            "runtime_generation_id=\"$(/usr/libexec/PlistBuddy -c 'Print :runtimeGenerationID' \"$frozen_companion_receipt\")\""
        ))
        #expect(package.contains(
            "<key>UMAAppPackageGenerationID</key><string>$app_package_generation_id</string>"
        ))
        #expect(package.contains("BUNDLE_ID=\"com.silkrd.uma\""))
        #expect(package.contains("BUNDLE_ID=\"com.silkrd.uma.test\""))
    }

    @Test
    func automaticSigningHarnessUsesExactIdentityTeamAndBundleIdentifiers() throws {
        let verifier = try source("script/verify_uma_apple_development_signing.sh")
        let project = try source(
            "AppleDevelopmentSigning/UMAAppleDevelopmentSigning.xcodeproj/project.pbxproj"
        )

        for required in [
            "/Applications/Xcode-beta.app/Contents/Developer",
            "Apple Development: SHAOTING HE (5BN4FAQSUF)",
            "C6TUZVJ6SJ",
            "com.silkrd.uma.test",
            "-allowProvisioningUpdates",
            "CODE_SIGN_STYLE=Automatic",
            "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO",
            "codesign --verify --deep --strict",
        ] {
            #expect(verifier.contains(required))
        }
        #expect(verifier.contains("readonly EXTENSION_ID=\"$APP_ID.ClaudeBrowserCompanion\""))
        #expect(project.contains("ProvisioningStyle = Automatic"))
        #expect(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.silkrd.uma.test;"))
        #expect(project.contains(
            "PRODUCT_BUNDLE_IDENTIFIER = com.silkrd.uma.test.ClaudeBrowserCompanion;"
        ))
        #expect(project.contains("DEVELOPMENT_TEAM = C6TUZVJ6SJ"))
    }

    @Test
    func developmentEntitlementsPreserveExtensionBoundaryWithoutDebugInjection() throws {
        let harness = try source(
            "AppleDevelopmentSigning/Extension/ClaudeBrowserCompanion.entitlements"
        )
        let verifier = try source("script/verify_uma_apple_development_signing.sh")

        let harnessData = try #require(harness.data(using: .utf8))
        let harnessPlist = try #require(
            PropertyListSerialization.propertyList(from: harnessData, format: nil)
                as? [String: AnyHashable]
        )
        #expect(harnessPlist["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(
            harnessPlist[
                "com.apple.security.temporary-exception.files.home-relative-path.read-write"
            ] as? [String] == [
                "/Library/Application Support/CodexUsageMonitor/TestChannel/ClaudeBrowserCompanion/"
            ]
        )
        #expect(!harness.contains("get-task-allow"))
        #expect(verifier.contains("Apple Development harness unexpectedly received get-task-allow"))
        #expect(verifier.contains("macos-xcode-managed-no-embedded-profile-required"))
        #expect(verifier.contains(
            "Embedded provisioning profiles are unsupported by this bounded no-profile mode."
        ))
    }

    @Test
    func appleDevelopmentModeUsesOneCoherentXcodeBetaToolchain() throws {
        let package = try source("script/package_uma_m5_g2.sh")

        #expect(package.contains(
            "readonly DEFAULT_SDK=\"/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk\""
        ))
        #expect(package.contains(
            "readonly APPLE_DEVELOPMENT_DEVELOPER_DIR=\"/Applications/Xcode-beta.app/Contents/Developer\""
        ))
        #expect(package.contains(
            "SDK=\"$APPLE_DEVELOPMENT_DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk\""
        ))
        #expect(package.contains(
            "export DEVELOPER_DIR=\"$APPLE_DEVELOPMENT_DEVELOPER_DIR\""
        ))
        #expect(package.contains("swift_driver=(/usr/bin/xcrun swift)"))
        #expect(!package.contains("$APPLE_DEVELOPMENT_DEVELOPER_DIR/usr/bin/xcrun"))
        #expect(package.contains(
            "appex_compiler=\"$APPLE_DEVELOPMENT_DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc\""
        ))
        #expect(package.contains(
            "\"${swift_driver[@]}\" build \"${swift_options[@]}\" -c release --product \"$PRODUCT\""
        ))
        #expect(package.contains("\"$appex_compiler\""))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func mintGeneration() throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = repositoryRoot().appendingPathComponent(
            "script/package_uma_m5_g2.sh"
        )
        process.arguments = ["--print-runtime-generation"]
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

    private func classifyLaunchServicesPath(_ path: String) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = repositoryRoot().appendingPathComponent(
            "script/install_uma_apple_development_test.sh"
        )
        process.arguments = ["--classify-launchservices-path", path]
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
