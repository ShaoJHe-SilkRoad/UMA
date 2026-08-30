import Foundation
import Testing

@Suite("M5RMX production split-host packaging")
struct M5RMXProductionSplitPackagingTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(path).path, encoding: .utf8)
    }

    private func plist(_ path: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(path)
        return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    }

    @Test("production channel has exact isolated identities and no Test metadata")
    func exactIdentities() throws {
        let package = try source("script/package_uma_0_13_production_split.sh")
        for value in ["com.silkrd.uma", "com.silkrd.uma.safarihost", "com.silkrd.uma.ClaudeBrowserCompanion", "group.com.silkrd.uma.bridge", "C6TUZVJ6SJ", "0.13.0", "production-safari-host"] { #expect(package.contains(value)) }
        #expect(!package.contains("com.silkrd.uma.test")); #expect(!package.contains("Apple Development:"))
    }

    @Test("mutable product is Safari-free and Host signs child first")
    func splitAndSigning() throws {
        let package = try source("script/package_uma_0_13_production_split.sh")
        #expect(package.contains("MUTABLE_APP_CONTAINS_SAFARI_CODE"))
        let extensionSign = try #require(package.range(of: "--identifier \"$EXTENSION_ID\" --entitlements"))
        let hostSign = try #require(package.range(of: "--identifier \"$HOST_ID\" --entitlements"))
        #expect(extensionSign.lowerBound < hostSign.lowerBound)
        #expect(package.contains("--options runtime --timestamp")); #expect(package.contains("codesign --verify --deep --strict"))
        #expect(package.contains("PRODUCTION_GET_TASK_ALLOW_FORBIDDEN")); #expect(package.contains("PRODUCTION_EFFECTIVE_ENTITLEMENTS_MISMATCH"))
    }

    @Test("release fails closed before build when prerequisites are absent")
    func failClosed() throws {
        let package = try source("script/package_uma_0_13_production_split.sh")
        for reason in ["SOURCE_NOT_COMMIT_EXACT", "DEVELOPER_ID_IDENTITY_UNAVAILABLE", "COHERENT_XCODE_TOOLCHAIN_UNAVAILABLE", "PRODUCTION_PROFILE_MISSING", "PRODUCTION_PROFILE_MISMATCH", "PRODUCTION_HANDLER_QUALIFICATION_ABSENT"] { #expect(package.contains(reason)) }
        for contract in ["/Applications/Xcode-beta.app/Contents/Developer", "MacOSX27.0.sdk", "SWIFTPM_MODULECACHE_OVERRIDE", "--disable-keychain", "--manifest-cache"] { #expect(package.contains(contract)) }
        #expect(package.contains("mkdir -p \"$src\""))
        #expect(package.range(of: "PRODUCTION_HANDLER_QUALIFICATION_ABSENT")!.lowerBound < package.range(of: "xcrun swift build")!.lowerBound)
    }

    @Test("production entitlements are exact and never debug-enabled")
    func entitlements() throws {
        let package = try source("script/package_uma_0_13_production_split.sh")
        let expected = [
            "ProductionSigning/MutableApp/UMA.entitlements": "C6TUZVJ6SJ.com.silkrd.uma",
            "ProductionSigning/SafariHost/App/UMA-Safari-Bridge.entitlements": "C6TUZVJ6SJ.com.silkrd.uma.safarihost",
            "ProductionSigning/SafariHost/Extension/ClaudeBrowserCompanion.entitlements": "C6TUZVJ6SJ.com.silkrd.uma.ClaudeBrowserCompanion",
        ]
        for (path, identifier) in expected {
            let value = try plist(path)
            #expect(value["com.apple.application-identifier"] as? String == identifier)
            #expect(value["com.apple.developer.team-identifier"] as? String == "C6TUZVJ6SJ")
            #expect(value["com.apple.security.application-groups"] as? [String] == ["group.com.silkrd.uma.bridge"])
            #expect(value["com.apple.security.get-task-allow"] == nil)
        }
        for value in ["PRODUCTION_SIGNED_IDENTITY_MISMATCH", "PRODUCTION_EFFECTIVE_ENTITLEMENTS_MISMATCH", "com.apple.application-identifier", "com.apple.developer.team-identifier", "com.apple.security.application-groups.0"] {
            #expect(package.contains(value))
        }
    }

    @Test("bundle templates encode one split production authority")
    func bundleTemplates() throws {
        let mutable = try plist("ProductionSigning/MutableApp/Info.plist")
        let host = try plist("ProductionSigning/SafariHost/App/Info.plist")
        let extensionInfo = try plist("ProductionSigning/SafariHost/Extension/Info.plist")
        #expect(mutable["CFBundleIdentifier"] as? String == "com.silkrd.uma")
        #expect(mutable["UMASafariHostBundleIdentifier"] as? String == "com.silkrd.uma.safarihost")
        #expect(host["CFBundleIdentifier"] as? String == "com.silkrd.uma.safarihost")
        #expect(extensionInfo["CFBundleIdentifier"] as? String == "com.silkrd.uma.ClaudeBrowserCompanion")
        let extensionDictionary = try #require(extensionInfo["NSExtension"] as? [String: Any])
        #expect(extensionDictionary["NSExtensionPointIdentifier"] as? String == "com.apple.Safari.web-extension")
    }

    @Test("production loader retains the admitted Host messaging contract")
    func backgroundLoaderContract() throws {
        let package = try source("script/package_uma_0_13_production_split.sh")
        for value in ["supportsAutomaticRefresh: true", "supportsManualAction: false", "umaClaudeWakeBridge", "umaClaudeAutomaticRefresh", "umaClaudeCloseOwnedUsageTab"] { #expect(package.contains(value)) }
        #expect(package.contains("for loader_contract in"))
        #expect(!package.contains("for expected in"))
        #expect(package.contains("PRODUCTION_MANIFEST_PERMISSION_MISMATCH"))
    }

    @Test("one joint notary archive is sealed only after accepted staple evidence")
    func provenanceAndSeal() throws {
        let package = try source("script/package_uma_0_13_production_split.sh"); let seal = try source("script/seal_uma_0_13_production_split.sh")
        #expect(package.contains("UMA-0.13.0-split-notary.zip")); #expect(package.contains("PRODUCTION_SPLIT_PRE_NOTARY"))
        for value in ["appCDHash", "hostCDHash", "extensionCDHash", "mutableProfileSHA256", "hostProfileSHA256", "extensionProfileSHA256"] { #expect(package.contains(value)) }
        #expect(seal.contains("--notary-status")); #expect(seal.contains("Accepted")); #expect(seal.contains("stapler validate")); #expect(seal.contains("PRODUCTION_SPLIT_FINAL")); #expect(!seal.contains("notarytool submit"))
        #expect(seal.contains("SUBMITTED_ARCHIVE_PROVENANCE_MISMATCH"))
        #expect(seal.contains("source=Notarized Developer ID"))
    }

    @Test("installer preserves rollback and installs one Host authority")
    func installerBoundary() throws {
        let install = try source("script/install_uma_0_13_production_split.sh")
        #expect(install.contains("/Users/juliushe/Desktop/UMA_0.11.app")); #expect(install.contains("88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a"))
        #expect(install.contains("/Users/juliushe/Desktop/UMA_0.13.0.app")); #expect(install.contains("UMA Safari Bridge.app")); #expect(install.contains("pluginkit -a")); #expect(install.contains("PROTECTED_ROLLBACK_MUTATED"))
        #expect(install.contains("SEALED_BUNDLE_PROVENANCE_MISMATCH")); #expect(install.contains("finalExtensionBundleSHA256"))
        #expect(install.contains("NONCANONICAL_PRODUCTION_COMPANION_REGISTRATION")); #expect(install.contains("SINGLE_CANONICAL_COMPANION_REGISTRATION_NOT_PROVEN"))
        #expect(install.contains("pluginkit -m -A -D -v -i")); #expect(install.contains("source=Notarized Developer ID"))
        #expect(!install.contains("UMA_0.13.0-Test.app")); #expect(!install.contains("Allow unsigned extensions"))
    }
}
