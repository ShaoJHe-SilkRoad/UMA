import ClaudeBrowserBridgeProtocol
@testable import ClaudeBrowserNativeHostCore
import Darwin
import Foundation
import Testing

@Suite("M5-BROWSER-G1 bridge contract")
struct ClaudeBrowserBridgeCoreTests {
    private func envelope(
        browser: ClaudeBrowserFamily = .chromium,
        fiveHour: Double? = 25,
        weekly: Double? = 40,
        reset: String? = "2026-08-01T18:00:00Z"
    ) -> ClaudeBrowserObservationEnvelope {
        ClaudeBrowserObservationEnvelope(
            browserFamily: browser,
            observation: ClaudeBrowserObservation(
                fiveHour: fiveHour.map { ClaudeBrowserQuotaWindow(usedPercentage: $0, resetAt: reset) },
                weeklyAllModels: weekly.map { ClaudeBrowserQuotaWindow(usedPercentage: $0, resetAt: reset) },
                observedAt: "2026-08-01T14:00:00Z"
            )
        )
    }

    @Test("zero, 100, and fractional usage are admitted without clamping")
    func percentageBoundaries() throws {
        for value in [0.0, 12.5, 100.0] {
            let source = envelope(fiveHour: value, weekly: nil)
            let decoded = try ClaudeBrowserMessageDecoder.decode(
                ClaudeBrowserMessageDecoder.encode(source)
            )
            #expect(decoded.observation.fiveHour?.usedPercentage == value)
        }
    }

    @Test("negative and above-100 percentages fail closed")
    func invalidPercentages() {
        #expect(throws: ClaudeBrowserBridgeError.invalidPercentage) {
            try ClaudeBrowserMessageDecoder.validate(envelope(fiveHour: -0.01, weekly: nil))
        }
        #expect(throws: ClaudeBrowserBridgeError.invalidPercentage) {
            try ClaudeBrowserMessageDecoder.validate(envelope(fiveHour: 100.01, weekly: nil))
        }
    }

    @Test("five-hour-only and weekly-only messages are valid")
    func singleAccountWindow() throws {
        try ClaudeBrowserMessageDecoder.validate(envelope(fiveHour: 30, weekly: nil))
        try ClaudeBrowserMessageDecoder.validate(envelope(fiveHour: nil, weekly: 30))
        #expect(throws: ClaudeBrowserBridgeError.noAccountWindow) {
            try ClaudeBrowserMessageDecoder.validate(envelope(fiveHour: nil, weekly: nil))
        }
    }

    @Test("missing reset is allowed but malformed reset fails closed")
    func resetSemantics() throws {
        try ClaudeBrowserMessageDecoder.validate(envelope(fiveHour: 30, weekly: nil, reset: nil))
        #expect(throws: ClaudeBrowserBridgeError.invalidReset) {
            try ClaudeBrowserMessageDecoder.validate(
                envelope(fiveHour: 30, weekly: nil, reset: "Resets tomorrow at noon")
            )
        }
    }

    @Test("an explicitly scoped model window remains separate from weekly all-models")
    func modelSpecificWindow() throws {
        let observation = ClaudeBrowserObservation(
            fiveHour: ClaudeBrowserQuotaWindow(usedPercentage: 5),
            weeklyAllModels: ClaudeBrowserQuotaWindow(usedPercentage: 20),
            modelSpecificWeekly: ClaudeBrowserModelWindow(
                modelFamily: .sonnet,
                window: ClaudeBrowserQuotaWindow(usedPercentage: 35)
            ),
            observedAt: "2026-08-01T14:00:00Z"
        )
        let source = ClaudeBrowserObservationEnvelope(browserFamily: .safari, observation: observation)
        let decoded = try ClaudeBrowserMessageDecoder.decode(
            ClaudeBrowserMessageDecoder.encode(source)
        )
        #expect(decoded.observation.weeklyAllModels?.usedPercentage == 20)
        #expect(decoded.observation.modelSpecificWeekly?.modelFamily == .sonnet)
        #expect(decoded.observation.modelSpecificWeekly?.window.usedPercentage == 35)
    }

    @Test("unknown page, identity, credential, and HTML fields cannot cross")
    func unexpectedFields() throws {
        let encoded = try ClaudeBrowserMessageDecoder.encode(envelope())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for forbidden in ["rawHTML", "email", "cookie", "token", "url"] {
            object[forbidden] = "forbidden"
            let mutated = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: ClaudeBrowserBridgeError.unexpectedField(forbidden)) {
                try ClaudeBrowserMessageDecoder.decode(mutated)
            }
            object.removeValue(forKey: forbidden)
        }
    }

    @Test("observation packets require one UUID replay nonce and the current layout")
    func observationIdentityAndLayoutContract() throws {
        let encoded = try ClaudeBrowserMessageDecoder.encode(envelope())
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == [
            "kind", "schemaVersion", "sourceID", "browserFamily",
            "routeState", "requestID", "observationID", "observation",
        ])
        #expect(UUID(uuidString: try #require(object["requestID"] as? String)) != nil)
        #expect(UUID(uuidString: try #require(object["observationID"] as? String)) != nil)

        var invalidID = object
        invalidID["observationID"] = "not-a-uuid"
        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserMessageDecoder.decode(
                JSONSerialization.data(withJSONObject: invalidID)
            )
        }

        var invalidLayout = object
        var observation = try #require(invalidLayout["observation"] as? [String: Any])
        observation["sourceLayoutVersion"] = ClaudeBrowserBridgeContract.sourceLayoutVersion + 1
        invalidLayout["observation"] = observation
        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserMessageDecoder.decode(
                JSONSerialization.data(withJSONObject: invalidLayout)
            )
        }
    }

    @Test("nested unknown fields fail closed")
    func nestedUnexpectedField() throws {
        let encoded = try ClaudeBrowserMessageDecoder.encode(envelope())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var observation = try #require(object["observation"] as? [String: Any])
        observation["accountIdentity"] = "forbidden"
        object["observation"] = observation
        let mutated = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ClaudeBrowserBridgeError.unexpectedField("accountIdentity")) {
            try ClaudeBrowserMessageDecoder.decode(mutated)
        }
    }

    @Test("native-message framing is bounded and exact")
    func nativeFraming() throws {
        let payload = try ClaudeBrowserMessageDecoder.encode(envelope())
        let frame = try ClaudeBrowserNativeMessagingFrame.encode(payload)
        #expect(try ClaudeBrowserNativeMessagingFrame.decode(frame) == payload)

        var trailing = frame
        trailing.append(0)
        #expect(throws: ClaudeBrowserBridgeError.nativeMessagingFrameMalformed) {
            try ClaudeBrowserNativeMessagingFrame.decode(trailing)
        }
        #expect(throws: ClaudeBrowserBridgeError.messageTooLarge) {
            try ClaudeBrowserNativeMessagingFrame.encode(
                Data(repeating: 0, count: ClaudeBrowserBridgeContract.maximumMessageBytes + 1)
            )
        }
    }

    @Test("automatic control events contain only one request ID and safe status")
    func automaticControlEventContract() throws {
        let requestID = "6e6f5e38-70bf-4b1b-81b0-e0903081f980"
        for status in ClaudeBrowserAutomationStatus.allCases {
            let carriesRuntimeIdentity: Bool
            switch status {
            case .extensionBackgroundReady, .nativeHandlerEntered,
                 .nativeRequestDecoded, .runtimeGenerationValidated,
                 .nativeResponseCreated, .nativeResponseSent,
                 .extensionResponseReceived, .bridgeReady:
                carriesRuntimeIdentity = true
            default:
                carriesRuntimeIdentity = false
            }
            let source = ClaudeBrowserAutomationEvent(
                requestID: requestID,
                status: status,
                occurredAt: "2026-08-02T12:00:00Z",
                companionVersion: carriesRuntimeIdentity
                    ? ClaudeBrowserBridgeContract.safariExtensionVersion : nil,
                companionBuild: carriesRuntimeIdentity
                    ? ClaudeBrowserBridgeContract.safariExtensionBuild : nil,
                protocolSchemaVersion: carriesRuntimeIdentity
                    ? ClaudeBrowserBridgeContract.schemaVersion : nil
            )
            let data = try ClaudeBrowserAutomationEventDecoder.encode(source)
            #expect(try ClaudeBrowserAutomationEventDecoder.decode(data) == source)
            let object = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            var expectedKeys: Set<String> = [
                "kind", "schemaVersion", "sourceID", "browserFamily",
                "requestID", "status", "occurredAt",
            ]
            if carriesRuntimeIdentity {
                expectedKeys.formUnion([
                    "companionVersion", "companionBuild", "protocolSchemaVersion",
                    "containingApplicationIdentifier", "extensionIdentifier",
                    "teamIdentifier", "runtimeGenerationID",
                ])
                #expect(object["companionVersion"] as? String
                    == ClaudeBrowserBridgeContract.safariExtensionVersion)
                #expect(object["companionBuild"] as? String
                    == ClaudeBrowserBridgeContract.safariExtensionBuild)
                #expect(object["protocolSchemaVersion"] as? Int
                    == ClaudeBrowserBridgeContract.schemaVersion)
                #expect(object["containingApplicationIdentifier"] as? String
                    == ClaudeBrowserBridgeContract.safariApplicationIdentifier)
                #expect(object["extensionIdentifier"] as? String
                    == ClaudeBrowserBridgeContract.safariExtensionIdentifier)
                #expect(object["teamIdentifier"] as? String
                    == ClaudeBrowserBridgeContract.expectedTeamIdentifier)
                #expect(UUID(uuidString: try #require(
                    object["runtimeGenerationID"] as? String
                )) != nil)
            }
            #expect(Set(object.keys) == expectedKeys)
        }

        let valid = ClaudeBrowserAutomationEvent(
            requestID: requestID,
            status: .permissionRequired,
            occurredAt: "2026-08-02T12:00:00Z"
        )
        var object = try #require(
            JSONSerialization.jsonObject(
                with: ClaudeBrowserAutomationEventDecoder.encode(valid)
            ) as? [String: Any]
        )
        object["url"] = "forbidden"
        #expect(throws: ClaudeBrowserBridgeError.unexpectedField("url")) {
            try ClaudeBrowserAutomationEventDecoder.decode(
                JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test("Test runtime identity is isolated and qualification requests contain no provider data")
    func runtimeIdentityAndQualificationContract() throws {
        #expect(ClaudeBrowserRuntimeIdentity.production.containingApplicationIdentifier
            == "com.silkrd.uma")
        #expect(ClaudeBrowserRuntimeIdentity.production.extensionIdentifier
            == "com.silkrd.uma.ClaudeBrowserCompanion")
        #expect(ClaudeBrowserRuntimeIdentity.test.containingApplicationIdentifier
            == "com.silkrd.uma.test")
        #expect(ClaudeBrowserRuntimeIdentity.test.extensionIdentifier
            == "com.silkrd.uma.test.ClaudeBrowserCompanion")
        #expect(ClaudeBrowserRuntimeIdentity.test.nativeApplicationIdentifier
            == "com.silkrd.uma.test")
        #expect(ClaudeBrowserRuntimeIdentity.test.handoffDirectoryRelativePath
            .contains("/TestChannel/"))
        #expect(ClaudeBrowserRuntimeIdentity.production != .test)

        let request = ClaudeBrowserRuntimeQualificationRequest(
            requestID: "6e6f5e38-70bf-4b1b-81b0-e0903081f980",
            runtimeGenerationID: "3c4f3c8a-6352-4bc7-b982-c5e8662da078"
        )
        let encoded = try ClaudeBrowserRuntimeQualificationRequestDecoder.encode(request)
        #expect(try ClaudeBrowserRuntimeQualificationRequestDecoder.decode(encoded) == request)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "kind", "schemaVersion", "sourceID", "browserFamily", "requestID",
            "runtimeGenerationID",
        ])
        for forbidden in [
            "url", "dom", "html", "quota", "identity", "cookie", "token",
            "credential", "companionVersion",
        ] {
            #expect(object[forbidden] == nil)
        }
    }

    @Test("only the deterministic Chromium extension origin is admitted")
    func chromiumOriginAllowlist() {
        #expect(ClaudeBrowserMessageDecoder.isAllowedChromiumOrigin(
            "chrome-extension://jgoknghcplngcnldmfenkghcbommaalj/"
        ))
        #expect(!ClaudeBrowserMessageDecoder.isAllowedChromiumOrigin(
            "chrome-extension://jgoknghcplngcnldmfenkghcbommaalk/"
        ))
        #expect(!ClaudeBrowserMessageDecoder.isAllowedChromiumOrigin("https://claude.ai/"))
    }

    @Test("owner-only file handoff delivers one normalized observation without network access")
    func fileHandoffRoundTrip() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "uma-m5adbg-bridge-handoff.\(getpid())",
                isDirectory: true
            )
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let endpoint = ClaudeBrowserFileHandoffEndpoint(directoryPath: root.path)
        let received = LockedEnvelope()
        let signal = DispatchSemaphore(value: 0)
        let server = ClaudeBrowserFileHandoffServer(endpoint: endpoint) { value in
            received.set(value)
            signal.signal()
        }
        try server.start()
        defer { server.stop() }

        let expected = envelope()
        let payload = try ClaudeBrowserMessageDecoder.encode(expected)
        try ClaudeBrowserFileHandoffWriter.write(payload, endpoint: endpoint)
        #expect(signal.wait(timeout: .now() + 2) == .success)
        #expect(received.value == expected)
        #expect(!FileManager.default.fileExists(atPath: endpoint.pendingPath))
    }

    @Test("owner-only handoff delivers a content-free automation status")
    func automationStatusHandoffRoundTrip() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "uma-m5-auto-bridge-status.\(getpid())",
                isDirectory: true
            )
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let endpoint = ClaudeBrowserFileHandoffEndpoint(directoryPath: root.path)
        let received = LockedAutomationEvent()
        let signal = DispatchSemaphore(value: 0)
        let server = ClaudeBrowserFileHandoffServer(
            endpoint: endpoint,
            observationHandler: { _ in },
            automationHandler: { value in
                received.set(value)
                signal.signal()
            }
        )
        try server.start()
        defer { server.stop() }

        let event = ClaudeBrowserAutomationEvent(
            requestID: "6e6f5e38-70bf-4b1b-81b0-e0903081f980",
            status: .permissionRequired,
            occurredAt: "2026-08-02T12:00:00Z"
        )
        try ClaudeBrowserFileHandoffWriter.write(
            ClaudeBrowserAutomationEventDecoder.encode(event),
            endpoint: endpoint
        )
        #expect(signal.wait(timeout: .now() + 2) == .success)
        #expect(received.value == event)
        #expect(!FileManager.default.fileExists(atPath: endpoint.pendingPath))
    }

    @Test("a second listener cannot replace or disrupt the active listener lock")
    func fileHandoffRejectsSecondListener() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "uma-m5adbg-bridge-handoff-lock.\(getpid())",
                isDirectory: true
            )
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let endpoint = ClaudeBrowserFileHandoffEndpoint(directoryPath: root.path)
        let received = LockedEnvelope()
        let signal = DispatchSemaphore(value: 0)
        let first = ClaudeBrowserFileHandoffServer(endpoint: endpoint) { value in
            received.set(value)
            signal.signal()
        }
        let second = ClaudeBrowserFileHandoffServer(endpoint: endpoint) { _ in }
        try first.start()
        defer { first.stop() }

        #expect(throws: ClaudeBrowserBridgeError.socketUnavailable) {
            try second.start()
        }

        let expected = envelope()
        let payload = try ClaudeBrowserMessageDecoder.encode(expected)
        try ClaudeBrowserFileHandoffWriter.write(payload, endpoint: endpoint)
        #expect(signal.wait(timeout: .now() + 2) == .success)
        #expect(received.value == expected)
    }

    @Test("pending observations are never replaced before the listener consumes them")
    func fileHandoffRejectsPendingReplacement() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "uma-m5adbg-bridge-pending-exclusion.\(getpid())",
                isDirectory: true
            )
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let endpoint = ClaudeBrowserFileHandoffEndpoint(directoryPath: root.path)
        let lockDescriptor = open(
            endpoint.listenerLockPath,
            O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC,
            mode_t(0o600)
        )
        #expect(lockDescriptor >= 0)
        defer {
            flock(lockDescriptor, LOCK_UN)
            close(lockDescriptor)
        }
        #expect(flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0)

        let first = try ClaudeBrowserMessageDecoder.encode(envelope(fiveHour: 11, weekly: 22))
        try first.write(to: URL(fileURLWithPath: endpoint.pendingPath))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: endpoint.pendingPath
        )
        let second = try ClaudeBrowserMessageDecoder.encode(envelope(fiveHour: 33, weekly: 44))

        #expect(throws: ClaudeBrowserBridgeError.socketWriteFailed) {
            try ClaudeBrowserFileHandoffWriter.write(second, endpoint: endpoint)
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: endpoint.pendingPath)) == first)
        #expect(!FileManager.default.fileExists(atPath: endpoint.temporaryPath))
    }

    @Test("a complete refresh sequence crosses the one-slot handoff without packet loss")
    func fileHandoffDeliversRefreshSequenceInOrder() throws {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "uma-m5rmx-safari-bridge-sequence.\(getpid())",
                isDirectory: true
            )
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let endpoint = ClaudeBrowserFileHandoffEndpoint(directoryPath: root.path)
        let received = LockedPacketKinds()
        let signal = DispatchSemaphore(value: 0)
        let server = ClaudeBrowserFileHandoffServer(
            endpoint: endpoint,
            observationHandler: { _ in
                received.append("observation")
                signal.signal()
            },
            automationHandler: { event in
                received.append(event.status.rawValue)
                signal.signal()
            }
        )
        try server.start()
        defer { server.stop() }

        let requestID = "6e6f5e38-70bf-4b1b-81b0-e0903081f980"
        let started = ClaudeBrowserAutomationEvent(
            requestID: requestID,
            status: .refreshStarted,
            occurredAt: "2026-08-17T12:00:00Z"
        )
        let completed = ClaudeBrowserAutomationEvent(
            requestID: requestID,
            status: .refreshCompleted,
            occurredAt: "2026-08-17T12:00:01Z"
        )
        try ClaudeBrowserFileHandoffWriter.write(
            ClaudeBrowserAutomationEventDecoder.encode(started),
            endpoint: endpoint
        )
        try ClaudeBrowserFileHandoffWriter.write(
            ClaudeBrowserMessageDecoder.encode(envelope()),
            endpoint: endpoint
        )
        try ClaudeBrowserFileHandoffWriter.write(
            ClaudeBrowserAutomationEventDecoder.encode(completed),
            endpoint: endpoint
        )

        for _ in 0..<3 {
            #expect(signal.wait(timeout: .now() + 2) == .success)
        }
        #expect(received.values == ["refreshStarted", "observation", "refreshCompleted"])
        #expect(!FileManager.default.fileExists(atPath: endpoint.pendingPath))
    }

    @Test("handoff rejects a symlink in the task-owned path")
    func fileHandoffRejectsSymlinkTraversal() throws {
        let base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(
                "uma-m5adbg-bridge-symlink.\(getpid())",
                isDirectory: true
            )
        try? FileManager.default.removeItem(at: base)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        let actual = base.appendingPathComponent("actual", isDirectory: true)
        let alias = base.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)

        let server = ClaudeBrowserFileHandoffServer(
            endpoint: ClaudeBrowserFileHandoffEndpoint(directoryPath: alias.path)
        ) { _ in }
        #expect(throws: ClaudeBrowserBridgeError.socketUnsafe) {
            try server.start()
        }
    }

    @Test("production handoff remains inside one user-private Application Support directory")
    func productionFileHandoffPath() {
        let endpoint = ClaudeBrowserFileHandoffEndpoint.production()
        #expect(endpoint.directoryPath.hasSuffix(
            "/Library/Application Support/CodexUsageMonitor/ClaudeBrowserCompanion"
        ))
        #expect(endpoint.pendingPath == endpoint.directoryPath + "/observation.pending")
        #expect(endpoint.listenerLockPath == endpoint.directoryPath + "/listener.lock")
        #expect(endpoint.legacySocketPath == endpoint.directoryPath + "/usage.sock")
        #expect(!endpoint.directoryPath.hasPrefix("/tmp/"))

        let testEndpoint = ClaudeBrowserFileHandoffEndpoint.runtime(.test)
        #expect(testEndpoint.directoryPath.hasSuffix(
            "/Library/Application Support/CodexUsageMonitor/TestChannel/ClaudeBrowserCompanion"
        ))
        #expect(testEndpoint.directoryPath != endpoint.directoryPath)
    }

    @Test("Safari uses exact persistent access while Chromium remains manual")
    func manifestPermissions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestRoot = root.appendingPathComponent("BrowserExtension")
        let safariData = try Data(contentsOf: manifestRoot
            .appendingPathComponent("Safari/manifest.json"))
        let safari = try #require(
            JSONSerialization.jsonObject(with: safariData) as? [String: Any]
        )
        #expect(safari["manifest_version"] as? Int == 2)
        #expect(safari["permissions"] as? [String] == [
            "nativeMessaging",
            ClaudeBrowserBridgeContract.exactUsageHostPermission,
        ])
        #expect(safari["host_permissions"] == nil)
        let safariBackground = try #require(safari["background"] as? [String: Any])
        #expect(safariBackground["scripts"] as? [String] == [
            "Shared/claude-usage-extractor.js",
            "Shared/provider-ownership-v2.js",
            "Shared/owned-provider-tab-v2-reducer.js",
            "Safari/background-loader.js",
            "Shared/background-core.js",
        ])
        #expect(safariBackground["persistent"] as? Bool == true)
        #expect(safariBackground["service_worker"] == nil)
        let safariContentScripts = try #require(safari["content_scripts"] as? [[String: Any]])
        #expect(safariContentScripts.count == 1)
        #expect(safariContentScripts[0]["matches"] as? [String] == [
            ClaudeBrowserBridgeContract.exactUsageHostPermission,
        ])
        #expect(safariContentScripts[0]["run_at"] as? String == "document_start")
        #expect(safariContentScripts[0]["all_frames"] as? Bool == false)
        #expect(safariContentScripts[0]["js"] as? [String] == [
            "Shared/claude-usage-extractor.js",
            "Shared/provider-ownership-v2.js",
            "Shared/content-script.js",
        ])
        #expect(safari["action"] == nil)

        let chromiumData = try Data(contentsOf: manifestRoot
            .appendingPathComponent("Chromium/manifest.json"))
        let chromium = try #require(
            JSONSerialization.jsonObject(with: chromiumData) as? [String: Any]
        )
        #expect(chromium["permissions"] as? [String] == [
            "activeTab", "nativeMessaging", "scripting",
        ])
        #expect(chromium["host_permissions"] == nil)
        #expect(chromium["action"] != nil)

        for data in [safariData, chromiumData] {
            let text = String(decoding: data, as: UTF8.self)
            for forbidden in [
                "\"tabs\"",
                "cookies",
                "<all_urls>",
                "webRequest",
                "webNavigation",
                "history",
                "bookmarks",
                "downloads",
            ] {
                #expect(!text.contains(forbidden))
            }
        }

        let background = try String(
            contentsOf: root.appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )
        #expect(background.contains("api.action?.onClicked?.addListener((tab)"))
        #expect(background.contains("api.scripting.executeScript"))
        #expect(background.contains("api.tabs?.executeScript"))
        #expect(background.contains("allowedSenderURL(tab?.url || \"\")"))
        #expect(!background.contains("api.tabs.get(read.tabID)"))
        #expect(!background.contains("api.tabs.query("))
        #expect(background.contains("api.tabs.create({ url: providerURL, active: false })"))
        #expect(!background.contains("api.tabs.update("))
        #expect(background.contains("sender?.frameId === 0"))
        #expect(background.contains("port.sender.tab.id !== read.providerOwnedTabID"))
        #expect(background.contains("umaClaudeProviderRecoveryChallengeV2"))
        #expect(background.contains("umaClaudeProviderRecoveryResponseV2"))
        #expect(background.contains("api.tabs.remove(read.providerOwnedTabID)"))
        #expect(!background.contains("owned-tab-bootstrap"))
        #expect(!background.contains("location.replace"))
        #expect(background.contains("ownedTabOwnershipLost"))
        #expect(background.contains(
            "api.runtime.sendNativeMessage(config.nativeApplication, payload)"
        ))
        #expect(background.contains("api.runtime.connectNative(config.nativeApplication)"))
        #expect(background.contains("port.onMessage.addListener((message) =>"))
        #expect(background.contains("port.onDisconnect.addListener(() =>"))
        #expect(background.contains("containingAppPortState"))
        #expect(background.contains("containingAppPortGeneration"))
        #expect(background.contains("runtimeQualificationRequest(requestID)"))
        #expect(background.contains("qualifyRuntime(command.requestID, portGeneration)"))
        #expect(background.contains("runtimeQualificationAcknowledgement(reply)"))
        #expect(background.contains("claudeBrowserRuntimeQualificationRequest"))
        #expect(background.contains("claudeBrowserRuntimeQualificationReply"))
        #expect(background.contains("claudeBrowserRuntimeQualificationAcknowledgement"))
        #expect(!background.contains("automationEnvelope(command.requestID, \"bridgeReady\")"))
        #expect(background.contains("config.browserFamily !== \"safari\""))
        #expect(!background.contains("nativeReconnectTimer"))
        #expect(!background.contains("setInterval"))

        let content = try String(
            contentsOf: root.appendingPathComponent(
                "BrowserExtension/Shared/content-script.js"
            ),
            encoding: .utf8
        )
        #expect(content.contains("extractor.exactUsageURL(globalThis.location)"))
        #expect(content.contains("result = extractor.extractResult"))
        #expect(content.contains("const readinessTimeoutMilliseconds = 20_000"))
        #expect(content.contains("new MutationObserver(scheduleReadinessEvaluation)"))
        #expect(content.contains("requestAnimationFrame"))
        #expect(!content.contains("readinessPollMilliseconds"))
        #expect(content.contains("ROUTE_READINESS_TIMEOUT"))
        #expect(content.contains("TARGET_DATA_TIMEOUT"))
        #expect(content.contains("const routeState = extractor.usageRouteState"))
        #expect(content.contains("if (routeState !== \"exact\")"))
        #expect(content.contains("setTimeout"))
        #expect(!content.contains("setInterval"))
        #expect(content.contains("runtime.onMessage.addListener"))
        #expect(content.contains("umaClaudeProviderDocumentDiscoveredV2"))
        #expect(content.contains("umaClaudeProviderRecoveryCandidateV2"))
        #expect(content.contains("umaClaudeProviderRecoveryChallengeV2"))
        #expect(content.contains("umaClaudeProviderRecoveryResponseV2"))
        #expect(content.contains("umaClaudeExtractUsage"))

        let entitlementURL = root.appendingPathComponent(
            "BrowserExtension/Safari/Native/ClaudeBrowserCompanion.entitlements"
        )
        let entitlementData = try Data(contentsOf: entitlementURL)
        let entitlements = try #require(
            PropertyListSerialization.propertyList(
                from: entitlementData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.client"] == nil)
        #expect(
            entitlements[
                "com.apple.security.temporary-exception.files.home-relative-path.read-write"
            ] as? [String] == [
                "/Library/Application Support/CodexUsageMonitor/ClaudeBrowserCompanion/",
            ]
        )
        #expect(Set(entitlements.keys) == [
            "com.apple.security.app-sandbox",
            "com.apple.security.temporary-exception.files.home-relative-path.read-write",
        ])
    }

    @Test("native-host manifest allowlists one exact extension origin")
    func nativeHostManifest() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root
            .appendingPathComponent("BrowserExtension/Chromium/com.silkrd.uma.claude_browser.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(manifest["name"] as? String == ClaudeBrowserBridgeContract.chromiumNativeHostName)
        #expect(manifest["allowed_origins"] as? [String] == [
            ClaudeBrowserBridgeContract.chromiumExtensionOrigin,
        ])
    }

    @Test("owned-tab receipt is owner-only, content-free, and generation-bound")
    func ownedTabReceiptLifecycle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "uma-owned-tab-receipt-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeBrowserFileHandoffEndpoint(directoryPath: root.path)
        let requestID = UUID().uuidString.lowercased()
        let generation = UUID().uuidString.lowercased()
        let digest = String(repeating: "a", count: 64)
        let receipt = ClaudeBrowserOwnedTabReceipt(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            createdAt: "2026-08-27T01:02:03Z",
            expiresAt: "2026-08-27T01:07:03Z",
            lifecycleState: .requestIntentPersisted,
            revision: 1
        )

        try ClaudeBrowserOwnedTabReceiptStore.save(receipt, endpoint: endpoint)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.load(endpoint: endpoint) == receipt)

        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: UUID().uuidString.lowercased(),
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 1,
            expectedState: .requestIntentPersisted,
            nextState: .providerCreationPending,
            endpoint: endpoint
        ) == nil)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: UUID().uuidString.lowercased(),
            ownershipNonceDigest: digest,
            expectedRevision: 1,
            expectedState: .requestIntentPersisted,
            nextState: .providerCreationPending,
            endpoint: endpoint
        ) == nil)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: String(repeating: "b", count: 64),
            expectedRevision: 1,
            expectedState: .requestIntentPersisted,
            nextState: .providerCreationPending,
            endpoint: endpoint
        ) == nil)

        let path = root.appendingPathComponent("owned-tab-receipt.plist")
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let data = try Data(contentsOf: path)
        let object = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "schemaVersion", "requestID", "runtimeGenerationID",
            "ownershipNonceDigest", "createdAt", "expiresAt",
            "lifecycleState", "revision",
        ])
        let semanticText = try #require(String(
            data: PropertyListSerialization.data(
                fromPropertyList: object,
                format: .xml,
                options: 0
            ),
            encoding: .utf8
        )).lowercased()
        for forbidden in [
            "url", "title", "dom", "html", "quota", "identity", "cookie",
            "credential", "history", "claude", "user",
        ] {
            #expect(!semanticText.contains(forbidden))
        }

        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 1,
            expectedState: .requestIntentPersisted,
            nextState: .providerCreationPending,
            endpoint: endpoint
        )?.revision == 2)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.bindCandidate(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 2,
            providerCandidateTabID: 47,
            endpoint: endpoint
        )?.revision == 3)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.bindCandidate(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 2,
            providerCandidateTabID: 47,
            endpoint: endpoint
        ) == nil)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.bindCandidate(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 3,
            providerCandidateTabID: 48,
            endpoint: endpoint
        ) == nil)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.bindCandidate(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 3,
            providerCandidateTabID: 47,
            endpoint: endpoint
        )?.revision == 3)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 3,
            expectedState: .providerCreationPending,
            nextState: .providerDocumentDiscovered,
            endpoint: endpoint
        )?.revision == 4)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 4,
            expectedState: .providerDocumentDiscovered,
            nextState: .providerOwnershipProven,
            providerOwnedTabID: 47,
            endpoint: endpoint
        )?.revision == 5)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 4,
            expectedState: .providerOwnershipProven,
            nextState: .cleanupRequested,
            endpoint: endpoint
        ) == nil)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 5,
            expectedState: .providerOwnershipProven,
            nextState: .cleanupRequested,
            endpoint: endpoint
        )?.revision == 6)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 6,
            expectedState: .cleanupRequested,
            nextState: .cleanupConfirmed,
            endpoint: endpoint
        )?.revision == 7)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 7,
            expectedState: .cleanupConfirmed,
            nextState: .complete,
            endpoint: endpoint
        )?.revision == 8)

        #expect(try !ClaudeBrowserOwnedTabReceiptStore.remove(
            requestID: requestID,
            runtimeGenerationID: UUID().uuidString.lowercased(),
            ownershipNonceDigest: digest,
            expectedRevision: 8,
            terminalState: .complete,
            endpoint: endpoint
        ))
        #expect(try !ClaudeBrowserOwnedTabReceiptStore.remove(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: String(repeating: "b", count: 64),
            expectedRevision: 8,
            terminalState: .complete,
            endpoint: endpoint
        ))
        #expect(try ClaudeBrowserOwnedTabReceiptStore.remove(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 8,
            terminalState: .complete,
            endpoint: endpoint
        ))
        #expect(try ClaudeBrowserOwnedTabReceiptStore.load(endpoint: endpoint) == nil)
        #expect(try !ClaudeBrowserOwnedTabReceiptStore.remove(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 8,
            terminalState: .complete,
            endpoint: endpoint
        ))
    }

    @Test("owned-tab receipt accepts JavaScript fractional-second timestamps")
    func ownedTabReceiptAcceptsJavaScriptTimestamp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "uma-owned-tab-js-time-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeBrowserFileHandoffEndpoint(directoryPath: root.path)
        let receipt = ClaudeBrowserOwnedTabReceipt(
            requestID: UUID().uuidString.lowercased(),
            runtimeGenerationID: UUID().uuidString.lowercased(),
            ownershipNonceDigest: String(repeating: "c", count: 64),
            createdAt: "2026-08-27T01:02:03.456Z",
            expiresAt: "2026-08-27T01:07:03.456Z",
            lifecycleState: .requestIntentPersisted,
            revision: 1
        )

        #expect(receipt.creationDate != nil)
        #expect(receipt.isStructurallyValid)
        try ClaudeBrowserOwnedTabReceiptStore.save(receipt, endpoint: endpoint)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.load(endpoint: endpoint) == receipt)

        let malformed = ClaudeBrowserOwnedTabReceipt(
            requestID: receipt.requestID,
            runtimeGenerationID: receipt.runtimeGenerationID,
            ownershipNonceDigest: receipt.ownershipNonceDigest,
            createdAt: "not-a-timestamp",
            expiresAt: receipt.expiresAt,
            lifecycleState: .requestIntentPersisted,
            revision: 1
        )
        #expect(malformed.creationDate == nil)
        #expect(!malformed.isStructurallyValid)
    }

    @Test("trusted discovery and create-result candidate binding are order independent")
    func ownedTabCandidateInverseOrdering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "uma-owned-tab-inverse-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeBrowserFileHandoffEndpoint(directoryPath: root.path)
        let requestID = UUID().uuidString.lowercased()
        let generation = UUID().uuidString.lowercased()
        let digest = String(repeating: "d", count: 64)
        try ClaudeBrowserOwnedTabReceiptStore.save(
            ClaudeBrowserOwnedTabReceipt(
                requestID: requestID,
                runtimeGenerationID: generation,
                ownershipNonceDigest: digest,
                createdAt: "2026-08-27T01:02:03Z",
                expiresAt: "2026-08-27T01:07:03Z",
                lifecycleState: .requestIntentPersisted,
                revision: 1
            ),
            endpoint: endpoint
        )
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 1,
            expectedState: .requestIntentPersisted,
            nextState: .providerCreationPending,
            endpoint: endpoint
        )?.revision == 2)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 2,
            expectedState: .providerCreationPending,
            nextState: .providerDocumentDiscovered,
            providerCandidateTabID: 91,
            endpoint: endpoint
        )?.revision == 3)
        // A late tabs.create resolution may only confirm the already-discovered ID.
        #expect(try ClaudeBrowserOwnedTabReceiptStore.bindCandidate(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 3,
            providerCandidateTabID: 91,
            endpoint: endpoint
        )?.revision == 3)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.bindCandidate(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 3,
            providerCandidateTabID: 92,
            endpoint: endpoint
        ) == nil)
        #expect(try ClaudeBrowserOwnedTabReceiptStore.transition(
            requestID: requestID,
            runtimeGenerationID: generation,
            ownershipNonceDigest: digest,
            expectedRevision: 3,
            expectedState: .providerDocumentDiscovered,
            nextState: .providerOwnershipProven,
            providerOwnedTabID: 91,
            endpoint: endpoint
        )?.revision == 4)
    }
}

private final class LockedEnvelope: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: ClaudeBrowserObservationEnvelope?

    var value: ClaudeBrowserObservationEnvelope? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: ClaudeBrowserObservationEnvelope) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}

private final class LockedAutomationEvent: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: ClaudeBrowserAutomationEvent?

    var value: ClaudeBrowserAutomationEvent? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: ClaudeBrowserAutomationEvent) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}

private final class LockedPacketKinds: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
