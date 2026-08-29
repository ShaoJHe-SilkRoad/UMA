import ClaudeBrowserBridgeProtocol
@testable import ClaudeBrowserNativeHostCore
import ClaudeSafariHostIPC
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
            "nativeMessaging", "https://claude.ai/new*",
        ])
        #expect(manifest["host_permissions"] == nil)
        let contentScripts = try #require(manifest["content_scripts"] as? [[String: Any]])
        #expect(contentScripts.count == 1)
        #expect(contentScripts[0]["matches"] as? [String] == ["https://claude.ai/new*"])
        #expect(contentScripts[0]["run_at"] as? String == "document_start")
        #expect(contentScripts[0]["all_frames"] as? Bool == false)
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
        #expect(UUID(uuidString: envelope.requestID) != nil)
        #expect(envelope.observation.sourceLayoutVersion == 1)
    }

    @Test
    func bridgeReadyRequiresBoundedRuntimeIdentityAndGeneration() throws {
        let requestID = UUID().uuidString.lowercased()
        let exact = ClaudeBrowserAutomationEvent(
            requestID: requestID,
            status: .bridgeReady,
            occurredAt: "2026-08-17T12:00:00Z",
            companionVersion: ClaudeBrowserBridgeContract.safariExtensionVersion,
            companionBuild: ClaudeBrowserBridgeContract.safariExtensionBuild,
            protocolSchemaVersion: ClaudeBrowserBridgeContract.schemaVersion,
            containingApplicationIdentifier:
                ClaudeBrowserRuntimeIdentity.test.containingApplicationIdentifier,
            extensionIdentifier: ClaudeBrowserRuntimeIdentity.test.extensionIdentifier,
            teamIdentifier: ClaudeBrowserBridgeContract.expectedTeamIdentifier,
            runtimeGenerationID: UUID().uuidString.lowercased()
        )
        let encoded = try ClaudeBrowserAutomationEventDecoder.encode(exact)
        #expect(try ClaudeBrowserAutomationEventDecoder.decode(encoded) == exact)

        var missing = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        missing.removeValue(forKey: "runtimeGenerationID")
        #expect(throws: ClaudeBrowserBridgeError.missingField("runtimeGenerationID")) {
            try ClaudeBrowserAutomationEventDecoder.decode(
                JSONSerialization.data(withJSONObject: missing)
            )
        }
        var mismatched = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        mismatched["extensionIdentifier"] =
            ClaudeBrowserRuntimeIdentity.production.extensionIdentifier
        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserAutomationEventDecoder.decode(
                JSONSerialization.data(withJSONObject: mismatched)
            )
        }
    }

    @Test
    func canonicalTestRuntimeRejectsStaleOrCrossChannelBridgeReady() {
        let generation = "6e6f5e38-70bf-4b1b-81b0-e0903081f980"
        let context = ClaudeBrowserRuntimeContext(
            identity: .test,
            canonicalAppPath: "/Users/test/Applications/UMA_0.13.0-Test.app",
            appVersion: "0.13.0",
            appBuild: "202608270001",
            extensionVersion: "1.4.0",
            extensionBuild: "10",
            teamIdentifier: ClaudeBrowserBridgeContract.expectedTeamIdentifier,
            runtimeGenerationID: generation,
            appGroupIdentifier: ClaudeBrowserBridgeContract.safariHostTestAppGroupIdentifier
        )
        func event(
            identity: ClaudeBrowserRuntimeIdentity = .test,
            generationID: String = generation
        ) -> ClaudeBrowserAutomationEvent {
            ClaudeBrowserAutomationEvent(
                requestID: UUID().uuidString.lowercased(),
                status: .bridgeReady,
                occurredAt: "2026-08-27T00:01:00Z",
                companionVersion: "1.4.0",
                companionBuild: "10",
                protocolSchemaVersion: ClaudeBrowserBridgeContract.schemaVersion,
                containingApplicationIdentifier:
                    identity.containingApplicationIdentifier,
                extensionIdentifier: identity.extensionIdentifier,
                teamIdentifier: ClaudeBrowserBridgeContract.expectedTeamIdentifier,
                runtimeGenerationID: generationID
            )
        }
        #expect(context.matches(event()))
        #expect(!context.matches(event(generationID: UUID().uuidString.lowercased())))
        #expect(!context.matches(event(identity: .production)))
    }

    @Test
    func mutableTestBundleQualifiesOnlyItsSignedImmutableHostReference() throws {
        let appGeneration = UUID().uuidString.lowercased()
        let hostGeneration = UUID().uuidString.lowercased()
        let exact = try runtimeBundle(
            identity: .test,
            appGeneration: appGeneration,
            extensionGeneration: hostGeneration
        )
        defer { try? FileManager.default.removeItem(at: exact.bundleURL) }
        let context = try #require(ClaudeBrowserRuntimeContext.current(bundle: exact))
        #expect(context.identity == .testSafariHost)
        #expect(context.runtimeGenerationID == hostGeneration)

        let wrongChannel = try runtimeBundle(
            identity: .test,
            appGeneration: appGeneration,
            extensionGeneration: hostGeneration,
            hostProfileOverride: .production
        )
        defer { try? FileManager.default.removeItem(at: wrongChannel.bundleURL) }
        #expect(ClaudeBrowserRuntimeContext.current(bundle: wrongChannel) == nil)
    }

    @Test
    func mutableProductionBundleQualifiesOnlyProductionImmutableHostMetadata() throws {
        let hostGeneration = UUID().uuidString.lowercased()
        let exact = try runtimeBundle(
            identity: .production,
            appGeneration: UUID().uuidString.lowercased(),
            extensionGeneration: hostGeneration
        )
        defer { try? FileManager.default.removeItem(at: exact.bundleURL) }
        let context = try #require(ClaudeBrowserRuntimeContext.current(bundle: exact))
        #expect(context.identity == .productionSafariHost)
        #expect(context.appGroupIdentifier == "group.com.silkrd.uma.bridge")
        #expect(context.runtimeGenerationID == hostGeneration)
    }

    @Test
    func nativeHandlerQualifiesExactSplitHostPairsAndRoutesEachAppGroup() throws {
        let handler = try source(
            "BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift"
        )

        // The production Companion ID is shared with the retired combined app,
        // so the handler must select by the signed containing-app/appex pair.
        #expect(handler.contains(
            ".matchingHostApplicationIdentifier(declaredContainingIdentifier)"
        ))
        #expect(handler.contains(
            "profile.identity.extensionIdentifier == extensionIdentifier"
        ))
        #expect(handler.contains(
            "combinedIdentity.extensionIdentifier == extensionIdentifier"
        ))
        #expect(handler.contains(
            "combinedIdentity.channel == .production"
        ))
        #expect(handler.contains(
            "combinedIdentity.channel == .test"
        ))

        // Split Host IPC is selected by the exact runtime channel and its
        // signed App Group. There is no Test App Group fallback for production.
        #expect(handler.contains(
            "case .productionSafariHost:"
        ))
        #expect(handler.contains(
            "runtime.identity == .productionSafariHost"
        ))
        #expect(handler.contains(
            "ClaudeBrowserBridgeContract.safariHostProductionAppGroupIdentifier"
        ))
        #expect(handler.contains(
            "case .testSafariHost:"
        ))
        #expect(handler.contains(
            "runtime.identity == .testSafariHost"
        ))
        #expect(handler.contains(
            "ClaudeBrowserBridgeContract.safariHostTestAppGroupIdentifier"
        ))
        #expect(handler.contains(
            "forSecurityApplicationGroupIdentifier: profile.appGroupIdentifier"
        ))
        #expect(!handler.contains(
            "forSecurityApplicationGroupIdentifier:\n                ClaudeBrowserBridgeContract.safariHostTestAppGroupIdentifier"
        ))
        #expect(handler.contains(
            "return .safariHostAppGroup(containerDirectoryPath: containerPath)"
        ))
        #expect(handler.contains(
            "return .safariHostOwnedTab(containerDirectoryPath: containerPath)"
        ))

        let production = try #require(
            ClaudeSafariHostRuntimeProfile.matchingHostApplicationIdentifier(
                ClaudeBrowserRuntimeIdentity.productionSafariHost
                    .containingApplicationIdentifier
            )
        )
        #expect(production.identity == .productionSafariHost)
        #expect(production.appGroupIdentifier == "group.com.silkrd.uma.bridge")
        #expect(
            production.identity.extensionIdentifier
                == ClaudeBrowserRuntimeIdentity.production.extensionIdentifier
        )

        let test = try #require(
            ClaudeSafariHostRuntimeProfile.matchingHostApplicationIdentifier(
                ClaudeBrowserRuntimeIdentity.testSafariHost
                    .containingApplicationIdentifier
            )
        )
        #expect(test.identity == .testSafariHost)
        #expect(test.appGroupIdentifier == "group.com.silkrd.uma.test.bridge")
        #expect(test.identity.extensionIdentifier != production.identity.extensionIdentifier)
        #expect(
            ClaudeSafariHostRuntimeProfile.matchingHostApplicationIdentifier(
                ClaudeBrowserRuntimeIdentity.production.containingApplicationIdentifier
            ) == nil
        )
    }

    @Test
    func safariWorkerUsesRequestBoundOneShotNativeMessagingOnly() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        let loader = try source("BrowserExtension/Safari/background-loader.js")
        #expect(background.contains("function observationEnvelope(requestID, observation)"))
        #expect(background.contains("requestID,"))
        #expect(background.contains("function runtimeQualificationRequest(requestID)"))
        #expect(background.contains("runtimeGenerationID: config.runtimeGenerationID"))
        #expect(background.contains("claudeBrowserRuntimeQualificationRequest"))
        #expect(background.contains("runtimeQualificationRequest(requestID)"))
        #expect(background.contains("qualifyRuntime(command.requestID, portGeneration)"))
        #expect(background.contains("claudeBrowserRuntimeQualificationReply"))
        #expect(background.contains("claudeBrowserRuntimeQualificationAcknowledgement"))
        #expect(background.contains("activeQualificationRequests.has(requestID)"))
        #expect(!background.contains("envelope.companionVersion"))
        #expect(background.contains(
            "api.runtime.sendNativeMessage(config.nativeApplication, payload)"
        ))
        #expect(background.contains("function installContainingAppPort()"))
        #expect(background.contains("api.runtime.connectNative(config.nativeApplication)"))
        #expect(background.contains("port.onMessage.addListener((message) =>"))
        #expect(background.contains("port.onDisconnect.addListener(() =>"))
        #expect(background.contains("containingAppPortGeneration !== generation"))
        #expect(background.contains("containingAppReconnectBudget"))
        #expect(background.contains("config.browserFamily !== \"safari\""))
        #expect(!background.contains("nativeReconnectTimer"))
        #expect(!loader.contains("companionVersion"))
        #expect(!loader.contains("runtimeGenerationID"))

        let handler = try source(
            "BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift"
        )
        #expect(handler.contains("private static func signedRuntimeIdentity()"))
        #expect(handler.contains("ClaudeBrowserRuntimeQualificationRequestDecoder.decode"))
        #expect(handler.contains("private static func nativeHandoffEndpoint("))
        #expect(handler.contains("return .safariHostAppGroup(containerDirectoryPath: containerPath)"))
        #expect(handler.contains("runtimeGenerationInfoKey"))
        #expect(handler.contains("teamIdentifierInfoKey"))

        let integration = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
        )
        let adapter = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
        )
        #expect(integration.contains("guard let runtime = ClaudeSafariHostClientAdapter()"))
        #expect(integration.contains("switch await runtime.verify()"))
        #expect(integration.contains("--verify-claude-companion-handshake"))
        #expect(integration.contains("cannot open, read, or inspect a provider page"))
        #expect(adapter.contains("static let verificationTransactionDeadline: Duration = .seconds(23)"))
        #expect(adapter.contains("waiters[request.requestID] = continuation"))
        #expect(adapter.contains("try client.submit(request)"))
        #expect(adapter.contains("case .extensionBackgroundAcknowledged"))
        #expect(adapter.contains("case .nativeQualificationReceived"))
        #expect(adapter.contains("activeWorkRequestIDs.isEmpty"))
    }

    @Test
    func safariOwnedTabReceiptUsesSharedJavaScriptTimestampParser() throws {
        let handler = try source(
            "BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift"
        )

        #expect(handler.contains("let date = receipt.creationDate"))
        #expect(!handler.contains("ISO8601DateFormatter().date(from: createdAt)"))
    }

    @Test
    func ownedTabIsClosedAtEveryTerminalCycleAndLossCannotMultiplyTabs() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        #expect(background.contains("async function cleanupV2(read, terminalState)"))
        #expect(background.contains("await api.tabs.remove(read.providerOwnedTabID)"))
        #expect(background.contains(
            "!Number.isInteger(read.providerOwnedTabID) || !read.providerPort"
        ))
        #expect(background.contains("finalStatus = \"ownedTabOwnershipLost\""))
        #expect(!background.contains("tabs.query({})"))
        #expect(!background.contains("active: true"))
        #expect(background.contains("let retainedObservation = null"))
        #expect(background.contains("const cleaned = await cleanupV2(read, terminal)"))
        #expect(background.contains("await sendNative(terminalEnvelope("))
        #expect(!background.contains(
            "await sendNative(observationEnvelope(read.requestID, observation))"
        ))
        #expect(background.contains("pendingV2Receipt = read"))
    }

    @Test
    func requestOwnershipPersistsOnlyAsAContentFreeNativeReceipt() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        #expect(!background.contains("umaClaudeOwnedUsageTab.v1"))
        #expect(!background.contains("api.storage"))
        #expect(!background.contains("loadOwnershipRecord"))
        #expect(!background.contains("storeOwnershipRecord"))
        #expect(!background.contains("clearOwnershipRecord"))
        #expect(background.contains("v2ReceiptCommand"))
        #expect(background.contains("saveV2Intent"))
        #expect(background.contains("recoverV2Receipt"))
        #expect(background.contains("ownedTabRecoveryPromise"))
        #expect(background.contains("runtimeGenerationID"))
        #expect(background.contains("let automaticRead = null"))
        #expect(background.contains("ownershipNonceDigest"))
        #expect(background.contains("providerOwnedTabID"))
        #expect(background.contains("api.runtime.onConnect?.addListener((port) =>"))
        #expect(background.contains("handleV2RecoveryMessage"))
        #expect(!background.contains("tabs.query"))
    }

    @Test
    func cleanupFailureSuppressesEveryObservationAndFailsClosed() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        #expect(background.contains("if (!cleaned)"))
        #expect(background.contains("finalStatus = \"ownedTabOwnershipLost\""))
        #expect(background.contains("retainedObservation = null"))
        #expect(background.contains("const cleaned = await cleanupV2(read, terminal)"))
        #expect(!background.contains("redirectedTerminalStatuses"))
        #expect(!background.contains("clearOwnershipRecord"))
    }

    @Test
    func eachOneShotCreatesExactlyOneFreshInactiveTab() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        #expect(background.contains("if (automaticRead)"))
        #expect(background.contains("await api.tabs.create({ url: providerURL, active: false })"))
        #expect(background.contains("providerURLForNonce(read.rawNonce)"))
        #expect(background.contains("const senderTabID = port.sender.tab.id"))
        #expect(!background.contains("bootstrapURL"))
    }

    @Test
    func tabRemovalFailureFailsClosedAndMarksTheReceiptCleanupPending() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        let removalFailureContract = "await api.tabs.remove(read.providerOwnedTabID)"
        #expect(background.contains(removalFailureContract))
        #expect(background.contains("finalStatus = \"ownedTabOwnershipLost\""))
        #expect(background.contains("pendingV2Receipt = read"))
        #expect(!background.contains("api.storage"))
        #expect(!background.contains("tabs.query({})"))
    }

    @Test
    func providerV2RecoveryClosesTheAtomicGapWithoutBroadEnumerationOrUnprovenClose() throws {
        let background = try source("BrowserExtension/Shared/background-core.js")
        let content = try source("BrowserExtension/Shared/content-script.js")
        let manifest = try source("BrowserExtension/Safari/manifest.json")

        let persist = try #require(background.range(of: "await saveV2Intent(read)"))
        let create = try #require(background.range(of: "await api.tabs.create({ url: providerURL, active: false })"))
        #expect(persist.lowerBound < create.lowerBound)
        #expect(background.contains("root.crypto?.randomUUID?.()"))
        #expect(background.contains("ownershipNonceDigest"))
        #expect(background.contains("pendingV2Receipt"))
        #expect(background.contains("api.runtime.onConnect?.addListener((port) =>"))
        #expect(background.contains("umaClaudeOwnedProviderV2"))
        #expect(background.contains("umaClaudeOwnedProviderRecoveryV2"))
        #expect(background.contains("umaClaudeProviderRecoveryChallengeV2"))
        #expect(background.contains("umaClaudeProviderRecoveryResponseV2"))
        #expect(background.contains("api.tabs.onRemoved.addListener(removalListener)"))
        #expect(!background.contains("tabs.query"))
        #expect(content.contains("reconnectsRemaining: 1"))
        #expect(content.contains("runtimeGenerationID"))
        #expect(content.contains("umaClaudeProviderDocumentDiscoveredV2"))
        #expect(!content.contains("tabs.remove"))
        #expect(!manifest.contains("\"tabs\""))
        #expect(!manifest.contains("<all_urls>"))
        #expect(!manifest.contains("owned-tab-bootstrap"))
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
    func setupHealthMapsAuthoritativeImmutableHostHandshakeStates() throws {
        let production = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
        )
        #expect(production.contains("case .verified: .ready"))
        #expect(production.contains("case .disabled: .disabled"))
        #expect(production.contains("case .companionStarting: .companionStarting"))
        #expect(production.contains("case .protocolMismatch: .protocolMismatch"))
        #expect(production.contains("case .unavailable: .companionUnavailable"))
        #expect(!production.contains("embeddedSafariExtensionHealth"))
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
        let nativeHostSigning = try #require(package.range(
            of: "--identifier \"$NATIVE_HOST_ID\""
        ))
        let statusRelaySigning = try #require(package.range(
            of: "--identifier \"$STATUS_RELAY_ID\""
        ))
        let extensionSigning = try #require(package.range(
            of: "--identifier \"$SAFARI_EXTENSION_ID\""
        ))
        let containingAppSigning = try #require(package.range(
            of: "\"${codesign_options[@]}\" --identifier \"$BUNDLE_ID\" \"$output\""
        ))
        let deepVerification = try #require(package.range(
            of: "/usr/bin/codesign --verify --deep --strict --verbose=2 \"$output\""
        ))
        #expect(nativeHostSigning.lowerBound < statusRelaySigning.lowerBound)
        #expect(statusRelaySigning.lowerBound < extensionSigning.lowerBound)
        #expect(extensionSigning.lowerBound < containingAppSigning.lowerBound)
        #expect(containingAppSigning.lowerBound < deepVerification.lowerBound)

        // Only these four commands sign code. The remaining codesign invocations
        // inspect signatures/entitlements or verify the assembled app.
        #expect(package.components(
            separatedBy: "\"${codesign_options[@]}\""
        ).count - 1 == 4)
        #expect(package.contains("-d --verbose=4 \"$signed_target\""))
        #expect(package.contains("-d --entitlements :-"))
        #expect(!package.contains("export HOME=\"$user_home\""))
        #expect(!package.contains("security find-identity"))
        #expect(package.contains("M5RMX Safari preflight does not submit for notarization"))
        #expect(package.contains("\"Shared/provider-ownership-v2.js\""))
        #expect(package.contains("\"content_scripts\""))
        #expect(package.contains(
            "\"permissions\": [\"nativeMessaging\", \"https://claude.ai/new*\"]"
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
        #expect(scope.contains("version `1.4.0` (build `10`)"))
        #expect(scope.contains("requests exactly `nativeMessaging` and `https://claude.ai/new*`"))
        #expect(scope.contains("dedicated `m5rmx-safari-preflight` phase"))
        #expect(scope.contains("reports marketing version `0.12`"))
        #expect(scope.contains("UMA `0.13.0` single-active development baseline"))
        #expect(scope.contains("`m5rmx-smart-0.13-preflight`"))
        #expect(scope.contains("verifies Team ID `C6TUZVJ6SJ`"))
        #expect(!scope.contains("current Safari manifest is version `1.2.3`"))
    }
    @Test
    func inventoryReceiptIsExactContentFreeAndVersionBound() throws {
        let dictionary: [String: Any] = [
            "schemaVersion": 2,
            "canonicalAppPath": "/Users/test/Applications/UMA_0.13.0-Test.app",
            "appBundleIdentifier": "com.silkrd.uma.test",
            "appVersion": "0.13.0",
            "appBuild": "202608260010",
            "extensionBundleIdentifier": "com.silkrd.uma.test.ClaudeBrowserCompanion",
            "extensionVersion": "1.4.0",
            "extensionBuild": "10",
            "teamIdentifier": "C6TUZVJ6SJ",
            "runtimeGenerationID": "6e6f5e38-70bf-4b1b-81b0-e0903081f980",
            "lifecycleState": "SAFARI_EXTENSION_UPDATE_PENDING_RESTART",
            "handshakeVerified": false,
            "updatedAt": "2026-08-26T18:00:00Z",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        let receipt = try #require(
            ClaudeBrowserProductionIntegration.decodeInventoryReceipt(data)
        )
        #expect(receipt.extensionBuild == "10")
        #expect(receipt.runtimeGenerationID
            == "6e6f5e38-70bf-4b1b-81b0-e0903081f980")
        #expect(receipt.lifecycleState == .safariRestartRequired)
        #expect(!receipt.handshakeVerified)

        var unknown = dictionary
        unknown["quota"] = 50
        let rejected = try PropertyListSerialization.data(
            fromPropertyList: unknown,
            format: .xml,
            options: 0
        )
        #expect(ClaudeBrowserProductionIntegration.decodeInventoryReceipt(rejected) == nil)
    }

    @Test
    func productDiagnosticsNameInventoryAndProtocolBoundaries() throws {
        let integration = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
        )
        let connector = try source(
            "Sources/CodexUsageUI/Connectors/ClaudeCodeUsageConnector.swift"
        )
        let ipc = try source("Sources/ClaudeSafariHostIPC/ClaudeSafariHostIPC.swift")
        let view = try source("Sources/CodexUsageUI/Views/UsageSettingsCard.swift")
        #expect(integration.contains("ClaudeBrowserCompanionDiagnosticResult"))
        #expect(integration.contains("firstFailureReason"))
        #expect(integration.contains("hostRuntimeGenerationID"))
        #expect(integration.contains(".protocolMismatch"))
        #expect(ipc.contains("O_NOFOLLOW"))
        #expect(ipc.contains("safariHostTestAppGroupIdentifier"))
        #expect(integration.contains(".protocolMismatch"))
        #expect(connector.contains("case companionStarting"))
        #expect(connector.contains("case protocolMismatch"))
        #expect(view.contains(".inventoryRestartRequired"))
        #expect(view.contains(".inventoryLoading"))
        #expect(view.contains(".protocolMismatch"))
        #expect(!view.contains("Check the enabled companion and try again"))
    }

    @Test
    func mismatchedBridgeReadySurfacesOnlyContentFreeReason() throws {
        let requestID = UUID().uuidString.lowercased()
        let payload = try JSONSerialization.data(withJSONObject: [
            "kind": ClaudeBrowserBridgeContract.automationMessageKind,
            "schemaVersion": ClaudeBrowserBridgeContract.schemaVersion,
            "sourceID": ClaudeBrowserBridgeContract.sourceID,
            "browserFamily": "safari",
            "requestID": requestID,
            "status": "bridgeReady",
            "occurredAt": "2026-08-26T18:00:00Z",
            "companionVersion": "1.4.0",
            "companionBuild": "9",
            "protocolSchemaVersion": ClaudeBrowserBridgeContract.schemaVersion,
        ])
        let rejection = try #require(
            ClaudeBrowserFileHandoffServer.protocolMismatchRejection(payload)
        )
        #expect(rejection.requestID == requestID)
        #expect(rejection.reason == .protocolMismatch)
    }

    private func runtimeBundle(
        identity: ClaudeBrowserRuntimeIdentity,
        appGeneration: String,
        extensionGeneration: String,
        hostProfileOverride: ClaudeSafariHostRuntimeProfile? = nil
    ) throws -> Bundle {
        let profile = try #require(hostProfileOverride ??
            ClaudeSafariHostRuntimeProfile.matchingMutableApplicationIdentifier(
                identity.containingApplicationIdentifier
            )
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "uma-runtime-bundle-\(UUID().uuidString).app",
            isDirectory: true
        )
        let appContents = root.appendingPathComponent("Contents", isDirectory: true)
        let extensionContents = appContents.appendingPathComponent(
            "PlugIns/ClaudeBrowserCompanion.appex/Contents",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: extensionContents,
            withIntermediateDirectories: true
        )
        let appVersion = "0.13.0"
        let appBuild = "202608270101"
        let extensionVersion = "1.4.0"
        let extensionBuild = "10"
        let common: [String: Any] = [
            ClaudeBrowserBridgeContract.containingApplicationInfoKey:
                identity.containingApplicationIdentifier,
            ClaudeBrowserBridgeContract.extensionIdentifierInfoKey:
                identity.extensionIdentifier,
            ClaudeBrowserBridgeContract.runtimeChannelInfoKey:
                identity.channel.rawValue,
            ClaudeBrowserBridgeContract.teamIdentifierInfoKey:
                ClaudeBrowserBridgeContract.expectedTeamIdentifier,
            ClaudeBrowserBridgeContract.appVersionInfoKey: appVersion,
            ClaudeBrowserBridgeContract.appBuildInfoKey: appBuild,
            ClaudeBrowserBridgeContract.extensionVersionInfoKey: extensionVersion,
            ClaudeBrowserBridgeContract.extensionBuildInfoKey: extensionBuild,
        ]
        var appInfo = common
        appInfo["CFBundleIdentifier"] = identity.containingApplicationIdentifier
        appInfo["CFBundlePackageType"] = "APPL"
        appInfo["CFBundleShortVersionString"] = appVersion
        appInfo["CFBundleVersion"] = appBuild
        appInfo[ClaudeBrowserBridgeContract.runtimeGenerationInfoKey] = appGeneration
        appInfo["UMASafariHostBundleIdentifier"] =
            profile.identity.containingApplicationIdentifier
        appInfo["UMASafariHostExtensionBundleIdentifier"] =
            profile.identity.extensionIdentifier
        appInfo["UMASafariHostRuntimeGenerationID"] = extensionGeneration
        appInfo["UMASafariHostExtensionVersion"] = extensionVersion
        appInfo["UMASafariHostExtensionBuild"] = extensionBuild
        appInfo[ClaudeBrowserBridgeContract.appGroupIdentifierInfoKey] =
            profile.appGroupIdentifier
        var extensionInfo = common
        extensionInfo["CFBundleIdentifier"] = identity.extensionIdentifier
        extensionInfo["CFBundlePackageType"] = "XPC!"
        extensionInfo["CFBundleShortVersionString"] = extensionVersion
        extensionInfo["CFBundleVersion"] = extensionBuild
        extensionInfo[ClaudeBrowserBridgeContract.runtimeGenerationInfoKey] = extensionGeneration
        try PropertyListSerialization.data(
            fromPropertyList: appInfo,
            format: .xml,
            options: 0
        ).write(to: appContents.appendingPathComponent("Info.plist"))
        try PropertyListSerialization.data(
            fromPropertyList: extensionInfo,
            format: .xml,
            options: 0
        ).write(to: extensionContents.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: root))
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
