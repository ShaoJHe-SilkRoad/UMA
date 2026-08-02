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
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "com.silkrd.uma.claude-browser.handoff.\(getpid())",
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

        let payload = try ClaudeBrowserMessageDecoder.encode(envelope())
        try ClaudeBrowserFileHandoffWriter.write(payload, endpoint: endpoint)
        #expect(signal.wait(timeout: .now() + 2) == .success)
        #expect(received.value == envelope())
        #expect(!FileManager.default.fileExists(atPath: endpoint.pendingPath))
    }

    @Test("a second listener cannot replace or disrupt the active listener lock")
    func fileHandoffRejectsSecondListener() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "com.silkrd.uma.claude-browser.handoff-lock.\(getpid())",
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

        let payload = try ClaudeBrowserMessageDecoder.encode(envelope())
        try ClaudeBrowserFileHandoffWriter.write(payload, endpoint: endpoint)
        #expect(signal.wait(timeout: .now() + 2) == .success)
        #expect(received.value == envelope())
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

    @Test("bridge manifests require one user gesture and no persistent page access")
    func manifestPermissions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for family in ["Chromium", "Safari"] {
            let data = try Data(contentsOf: root
                .appendingPathComponent("BrowserExtension")
                .appendingPathComponent(family)
                .appendingPathComponent("manifest.json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(manifest["permissions"] as? [String] == [
                "activeTab",
                "nativeMessaging",
                "scripting",
            ])
            #expect(manifest["host_permissions"] == nil)
            #expect(manifest["content_scripts"] == nil)
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
        #expect(background.contains("allowedSenderURL(tab?.url || \"\")"))
        #expect(!background.contains("tabs.onUpdated"))
        #expect(!background.contains("tabs.query"))
        #expect(!background.contains("tabs.create"))

        let content = try String(
            contentsOf: root.appendingPathComponent(
                "BrowserExtension/Shared/content-script.js"
            ),
            encoding: .utf8
        )
        #expect(content.contains("extractor.exactUsageURL(globalThis.location)"))
        #expect(content.contains("const observation = extractor.extract"))
        #expect(!content.contains("MutationObserver"))
        #expect(!content.contains("setTimeout"))
        #expect(!content.contains("runtime.onMessage"))

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
