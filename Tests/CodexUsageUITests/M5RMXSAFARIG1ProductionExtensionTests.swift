import ClaudeBrowserBridgeProtocol
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5RMX-SAFARI-G1 production Safari extension")
struct M5RMXSAFARIG1ProductionExtensionTests {
    @Test
    func signedSafariManifestAndBundleIdentityAreExact() throws {
        let manifest = try json("BrowserExtension/Safari/manifest.json")
        #expect(manifest["manifest_version"] as? Int == 2)
        #expect(manifest["permissions"] as? [String] == [
            "nativeMessaging", "storage", "https://claude.ai/new*",
        ])
        #expect(manifest["host_permissions"] == nil)
        #expect(manifest["content_scripts"] == nil)
        #expect(manifest["action"] == nil)

        let info = try plist("BrowserExtension/Safari/Native/Info.plist")
        #expect(info["CFBundleIdentifier"] as? String
            == ClaudeBrowserBridgeContract.safariExtensionIdentifier)
        #expect(info["CFBundleShortVersionString"] as? String
            == ClaudeBrowserBridgeContract.safariExtensionVersion)
        #expect(info["CFBundleVersion"] as? String
            == ClaudeBrowserBridgeContract.safariExtensionBuild)
        let extensionInfo = try #require(info["NSExtension"] as? [String: Any])
        #expect(extensionInfo["NSExtensionPointIdentifier"] as? String
            == "com.apple.Safari.web-extension")
    }

    @Test
    func extensionEntitlementsStaySandboxedAndPathBound() throws {
        let entitlements = try plist(
            "BrowserExtension/Safari/Native/ClaudeBrowserCompanion.entitlements"
        )
        #expect(Set(entitlements.keys) == [
            "com.apple.security.app-sandbox",
            "com.apple.security.temporary-exception.files.home-relative-path.read-write",
        ])
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements[
            "com.apple.security.temporary-exception.files.home-relative-path.read-write"
        ] as? [String] == [
            "/Library/Application Support/CodexUsageMonitor/ClaudeBrowserCompanion/",
        ])
    }

    @Test
    func packetCarriesVersionedLayoutAndReplayNonce() throws {
        #expect(ClaudeBrowserBridgeContract.schemaVersion == 2)
        #expect(ClaudeBrowserBridgeContract.extractorSchemaVersion == 2)
        #expect(ClaudeBrowserBridgeContract.sourceLayoutVersion == 1)

        let envelope = ClaudeBrowserObservationEnvelope(
            browserFamily: .safari,
            observation: ClaudeBrowserObservation(
                fiveHour: ClaudeBrowserQuotaWindow(usedPercentage: 25),
                weeklyAllModels: nil,
                observedAt: "2026-08-17T12:00:00Z"
            )
        )
        #expect(UUID(uuidString: envelope.observationID) != nil)
        #expect(envelope.observation.sourceLayoutVersion == 1)
    }

    @Test
    func ownedTabIsClosedAtEveryTerminalCycleAndLossCannotMultiplyTabs() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        #expect(background.contains(
            "if (read.record && !(await closeProvenOwnedTab(read.record)))"
        ))
        #expect(background.contains("finalStatus = \"ownedTabOwnershipLost\""))
        #expect(!background.contains(
            "if (!proven) {\n      await clearOwnershipRecord();"
        ))
        #expect(!background.contains(
            "if (!(await proveOwnedTab(record, tab))) {\n        await clearOwnershipRecord();"
        ))
        #expect(!background.contains("tabs.query"))
        #expect(!background.contains("active: true"))
        #expect(background.contains("const proven = await proveOwnedTab(record, tab)"))
        #expect(!background.contains("ownershipProven"))
        #expect(background.contains(
            "const closed = !read.record || await closeProvenOwnedTab(read.record)"
        ))
        #expect(background.contains("if (!(await sendNative(observationEnvelope(observation))))"))
        #expect(background.contains("reply.ok !== true"))
    }

    @Test
    func tabUnavailableWithAnOwnershipRecordCannotClearAndMultiply() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        #expect(background.contains(
            "if (read.record && !(await closeProvenOwnedTab(read.record)))"
        ))
        #expect(!background.contains(
            "if (status === \"tabUnavailable\") {\n      await clearOwnershipRecord();"
        ))
        #expect(background.contains(
            "try { tab = await api.tabs.get(record.tabID); } catch (_) {\n"
                + "      await clearOwnershipRecord();\n      return true;"
        ))
        #expect(background.contains("finalStatus = \"ownedTabOwnershipLost\""))
    }

    @Test
    func redirectedTerminalStatusIsPreservedWhileOwnershipRecordFailsClosed() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        let redirectSet = "const redirectedTerminalStatuses = new Set([\n"
            + "    \"signInRequired\",\n"
            + "    \"routeRejected\","
        let preservedStatus = "if (!redirectedTerminalStatuses.has(status)) {\n"
            + "        finalStatus = \"ownedTabOwnershipLost\";"
        #expect(background.contains(redirectSet))
        #expect(background.contains(preservedStatus))
        #expect(background.contains(
            "if (read.record && !(await closeProvenOwnedTab(read.record)))"
        ))
        #expect(!background.contains(
            "if (!redirectedTerminalStatuses.has(status)) {\n"
                + "        await clearOwnershipRecord();"
        ))
    }

    @Test
    func nextCycleStoredRedirectIsClassifiedBeforeExactRouteTokenProof() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        #expect(background.contains("function redirectedTerminalStatusForURL(raw)"))
        #expect(background.contains(
            "if (url.origin !== extractor.CONTRACT.origin) return \"signInRequired\";"
        ))
        #expect(background.contains("? \"signInRequired\"\n        : \"routeRejected\";"))

        let storedRecord = try #require(background.range(of: "if (record && tab) {"))
        let routeClassification = try #require(background.range(
            of: "if (!allowedSenderURL(tab.url || \"\")) {",
            range: storedRecord.lowerBound..<background.endIndex
        ))
        let ownershipProof = try #require(background.range(
            of: "if (!(await proveOwnedTab(record, tab))) {",
            range: storedRecord.lowerBound..<background.endIndex
        ))
        #expect(background[storedRecord.lowerBound..<routeClassification.lowerBound].contains(
            "read.record = record;\n      read.tabID = record.tabID;"
        ))
        #expect(routeClassification.lowerBound < ownershipProof.lowerBound)
        #expect(background[routeClassification.lowerBound..<ownershipProof.lowerBound].contains(
            "finishAutomatic(read, redirectedTerminalStatusForURL(tab.url || \"\"))"
        ))
        #expect(!background[routeClassification.lowerBound..<ownershipProof.lowerBound].contains(
            "clearOwnershipRecord"
        ))
    }

    @Test
    func tabRemovalFailureRetainsOwnershipRecordAndFailsClosed() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        let removalFailureContract = "try {\n"
            + "      await api.tabs.remove(record.tabID);\n"
            + "    } catch (_) {\n"
            + "      return false;\n"
            + "    }\n"
            + "    await clearOwnershipRecord();"
        #expect(background.contains(removalFailureContract))
        #expect(!background.contains(
            "try { await api.tabs.remove(record.tabID); } catch (_) {}"
        ))
    }

    @Test
    func localHandoffSerializesWithoutOverwritingPendingPackets() throws {
        let handoff = try source(
            "Sources/ClaudeBrowserNativeHostCore/ClaudeBrowserFileHandoff.swift"
        )
        #expect(handoff.contains("try waitForPendingSlot(endpoint.pendingPath, uid: uid)"))
        #expect(handoff.contains("for _ in 0..<200"))
        #expect(handoff.contains("usleep(10_000)"))
        #expect(handoff.contains("RENAME_EXCL"))
        #expect(!handoff.contains("RENAME_SWAP"))
    }

    @Test
    func setupHealthDistinguishesMissingMismatchedAndOutdatedCompanions() throws {
        let production = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
        )
        #expect(production.contains("private static var embeddedSafariExtensionHealth"))
        #expect(production.contains("return .nativeHostMissing"))
        #expect(production.contains("return .nativeHostMismatched"))
        #expect(production.contains("return .outdated"))
        #expect(production.contains("ClaudeBrowserBridgeContract.safariExtensionVersion"))
        #expect(production.contains("ClaudeBrowserBridgeContract.safariExtensionBuild"))
    }

    @Test
    func dedicatedPreflightIsCommitExactSignedAndNeverNotarizes() throws {
        let wrapper = try source("script/package_uma_m5rmx_safari.sh")
        let package = try source("script/package_uma_m5_g2.sh")
        #expect(wrapper.contains("--phase m5rmx-safari-preflight"))
        #expect(wrapper.contains("&& \"$identity\" != \"-\""))
        #expect(!wrapper.contains("keychain-profile"))
        #expect(package.contains(
            "uma-m5rmx-safari-preflight-$commit/UMA.app"
        ))
        #expect(package.contains("source_state=\"commit-exact-signed-preflight\""))
        #expect(package.contains("resolved_marketing_version=\"0.12\""))
        #expect(package.contains("TeamIdentifier=C6TUZVJ6SJ"))
        #expect(package.contains("Hardened Runtime missing"))
        #expect(package.contains("Secure timestamp missing"))
        #expect(package.contains("readonly user_home=\"$HOME\""))
        #expect(package.contains("export HOME=\"$home_root\""))
        #expect(package.components(
            separatedBy: "HOME=\"$user_home\" /usr/bin/codesign"
        ).count - 1 == 5)
        #expect(!package.contains("export HOME=\"$user_home\""))
        #expect(!package.contains("security find-identity"))
        #expect(package.contains("M5RMX Safari preflight does not submit for notarization"))
        #expect(package.contains("|| \"$phase\" == m5rmx-safari-*"))
        #expect(package.contains(
            "\"permissions\": [\"nativeMessaging\", \"storage\", \"https://claude.ai/new*\"]"
        ))
        let helper = root().appendingPathComponent("script/package_uma_m5rmx_safari.sh")
        let attributes = try FileManager.default.attributesOfItem(atPath: helper.path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber).intValue
        #expect(mode & 0o111 != 0)

        // Production must not regress to the former version/package/permission contract.
        #expect(!wrapper.contains("0.11"))
        #expect(!wrapper.contains("uma-m5-browser"))
        let manifestSource = try source("BrowserExtension/Safari/manifest.json")
        #expect(!manifestSource.contains("activeTab"))
        #expect(!manifestSource.contains("scripting"))
    }

    @Test
    func currentScopeLockRecordsTheProductionExtensionAndPackageContract() throws {
        let scope = try source("source/UMA M5RMX Scope Lock.md")
        #expect(scope.contains("version `1.3.0` (build `8`)"))
        #expect(scope.contains("requests exactly `nativeMessaging`,"))
        #expect(scope.contains("`storage`, and `https://claude.ai/new*`"))
        #expect(scope.contains("dedicated `m5rmx-safari-preflight` phase"))
        #expect(scope.contains("reports marketing version `0.12`"))
        #expect(scope.contains("verifies Team ID `C6TUZVJ6SJ`"))
        #expect(!scope.contains("current Safari manifest is version `1.2.3`"))
    }
}

private func root() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func source(_ relativePath: String) throws -> String {
    try String(contentsOf: root().appendingPathComponent(relativePath), encoding: .utf8)
}

private func json(_ relativePath: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root().appendingPathComponent(relativePath))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func plist(_ relativePath: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root().appendingPathComponent(relativePath))
    return try #require(PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
    ) as? [String: Any])
}
