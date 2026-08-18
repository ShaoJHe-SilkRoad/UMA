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
            "routeState", "observationID", "observation",
        ])
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
            let source = ClaudeBrowserAutomationEvent(
                requestID: requestID,
                status: status,
                occurredAt: "2026-08-02T12:00:00Z"
            )
            let data = try ClaudeBrowserAutomationEventDecoder.encode(source)
            #expect(try ClaudeBrowserAutomationEventDecoder.decode(data) == source)
            let object = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            #expect(Set(object.keys) == [
                "kind", "schemaVersion", "sourceID", "browserFamily",
                "requestID", "status", "occurredAt",
            ])
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
            "storage",
            ClaudeBrowserBridgeContract.exactUsageHostPermission,
        ])
        #expect(safari["host_permissions"] == nil)
        let safariBackground = try #require(safari["background"] as? [String: Any])
        #expect(safariBackground["scripts"] as? [String] == [
            "Shared/claude-usage-extractor.js",
            "Safari/background-loader.js",
            "Shared/background-core.js",
        ])
        #expect(safariBackground["persistent"] as? Bool == true)
        #expect(safariBackground["service_worker"] == nil)
        #expect(safari["content_scripts"] == nil)
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
        #expect(!background.contains("tabs.onUpdated"))
        #expect(!background.contains("tabs.query"))
        #expect(background.contains("api.tabs.create({ url: extractor.CONTRACT.href, active: false })"))
        #expect(background.contains("api.tabs.remove(record.tabID)"))
        #expect(background.contains("await proveOwnedTab(record, tab)"))
        #expect(background.contains("ownedTabOwnershipLost"))
        #expect(background.contains("api.runtime.connectNative(config.nativeApplication)"))

        let content = try String(
            contentsOf: root.appendingPathComponent(
                "BrowserExtension/Shared/content-script.js"
            ),
            encoding: .utf8
        )
        #expect(content.contains("extractor.exactUsageURL(globalThis.location)"))
        #expect(content.contains("result = extractor.extractResult"))
        #expect(content.contains("const readinessTimeoutMilliseconds = 20_000"))
        #expect(content.contains("const readinessPollMilliseconds = 500"))
        #expect(content.contains("result.status !== \"usageUnavailable\""))
        #expect(!content.contains("MutationObserver"))
        #expect(content.contains("setTimeout"))
        #expect(!content.contains("setInterval"))
        #expect(content.contains("runtime.onMessage.addListener"))
        #expect(content.contains("umaClaudeOwnedTabBind"))
        #expect(content.contains("umaClaudeOwnedTabChallenge"))
        #expect(content.contains("umaClaudeOwnedTabProof"))
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
