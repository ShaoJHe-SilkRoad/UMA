import AppKit
import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import OSLog
import SafariServices

private actor ClaudeBrowserBridgeReadinessGate {
    private var expectedRequestIDs: Set<String> = []
    private var readyRequestIDs: Set<String> = []
    private var waiters: [String: CheckedContinuation<Bool, Never>] = [:]

    func prepare(_ requestID: String) {
        cancel(requestID)
        expectedRequestIDs.insert(requestID)
    }

    func signal(_ requestID: String) {
        guard expectedRequestIDs.remove(requestID) != nil else { return }
        if let continuation = waiters.removeValue(forKey: requestID) {
            continuation.resume(returning: true)
        } else {
            readyRequestIDs.insert(requestID)
        }
    }

    func wait(for requestID: String, timeout: TimeInterval) async -> Bool {
        if readyRequestIDs.remove(requestID) != nil { return true }
        guard expectedRequestIDs.contains(requestID) else { return false }
        return await withCheckedContinuation { continuation in
            waiters[requestID] = continuation
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                self.expire(requestID)
            }
        }
    }

    func cancel(_ requestID: String) {
        expectedRequestIDs.remove(requestID)
        readyRequestIDs.remove(requestID)
        waiters.removeValue(forKey: requestID)?.resume(returning: false)
    }

    func cancelAll() {
        expectedRequestIDs.removeAll()
        readyRequestIDs.removeAll()
        let active = waiters.values
        waiters.removeAll()
        for continuation in active {
            continuation.resume(returning: false)
        }
    }

    private func expire(_ requestID: String) {
        cancel(requestID)
    }
}

private final class ClaudeBrowserBridgeRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private let readinessGate = ClaudeBrowserBridgeReadinessGate()
    private var server: ClaudeBrowserFileHandoffServer?

    func start(handler: @escaping ClaudeBrowserProductionIntegration.MessageHandler) {
        lock.lock()
        defer { lock.unlock() }
        guard server == nil else { return }
        let readinessGate = readinessGate
        let candidate = ClaudeBrowserFileHandoffServer(
            observationHandler: { envelope in
                Task { await handler(.observation(.success(envelope))) }
            },
            automationHandler: { event in
                Task {
                    if event.status == .bridgeReady {
                        await readinessGate.signal(event.requestID)
                    }
                    await handler(.automation(event))
                }
            }
        )
        do {
            try candidate.start()
            server = candidate
        } catch let error as ClaudeBrowserBridgeError {
            Task { await handler(.observation(.failure(error))) }
        } catch {
            Task { await handler(.observation(.failure(.socketUnavailable))) }
        }
    }

    func stop() async {
        let active = lock.withLock {
            let active = server
            server = nil
            return active
        }
        active?.stop()
        await readinessGate.cancelAll()
    }

    func prepareBridgeReady(_ requestID: String) async {
        await readinessGate.prepare(requestID)
    }

    func waitForBridgeReady(_ requestID: String, timeout: TimeInterval) async -> Bool {
        await readinessGate.wait(for: requestID, timeout: timeout)
    }

    func cancelBridgeReady(_ requestID: String) async {
        await readinessGate.cancel(requestID)
    }
}

private final class ClaudeBrowserDispatchCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ delivered: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: delivered)
    }
}

extension ClaudeBrowserProductionIntegration {
    private static let logger = Logger(
        subsystem: "com.kevinchen.CodexUsageMonitor",
        category: "ClaudeAutomaticRefresh"
    )
    private static let safariExtensionIdentifier =
        "com.kevinchen.CodexUsageMonitor.ClaudeBrowserCompanion"
    private static let safariWakeMessageName = "umaClaudeWakeBridge"
    private static let safariWorkerSettleTimeout: TimeInterval = 5

    static func make() -> Self {
        let runtime = ClaudeBrowserBridgeRuntime()
        return Self(
            startListening: { handler in runtime.start(handler: handler) },
            stopListening: { await runtime.stop() },
            checkHealth: { await currentHealth() },
            openUsagePage: { await openOfficialUsagePage() },
            repairCompanion: { await repairCurrentCompanion() },
            requestAutomaticRefresh: { requestID, allowSafariLaunch in
                await dispatchAutomaticRefresh(
                    requestID: requestID,
                    allowSafariLaunch: allowSafariLaunch,
                    runtime: runtime
                )
            },
            closeOwnedUsageTab: { requestID in
                await dispatchCloseOwnedTab(requestID: requestID)
            }
        )
    }

    private static func currentHealth() async -> ClaudeBrowserCompanionHealth {
        guard let browser = await defaultBrowserIdentity() else {
            return .browserUnavailable
        }
        switch browser {
        case .safari:
            return await safariExtensionHealth()
        case .chromium:
            return chromiumNativeHostManifestExists() ? .ready : .nativeHostMissing
        case .unsupported:
            return .unsupportedBrowser
        }
    }

    @MainActor
    private static func defaultBrowserIdentity() -> DefaultBrowserIdentity? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            toOpen: ClaudeBrowserBridgeContract.officialUsageURL
        ),
              let identifier = Bundle(url: applicationURL)?.bundleIdentifier
        else { return nil }
        if identifier == "com.apple.Safari" {
            return .safari
        }
        if [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "org.chromium.Chromium",
            "com.microsoft.edgemac",
            "com.brave.Browser",
        ].contains(identifier) {
            return .chromium
        }
        return .unsupported
    }

    private static func safariExtensionHealth() async -> ClaudeBrowserCompanionHealth {
        guard let state = try? await SFSafariExtensionManager.stateOfSafariExtension(
            withIdentifier: safariExtensionIdentifier
        ) else { return .nativeHostMissing }
        return state.isEnabled ? .ready : .disabled
    }

    private static func openOfficialUsagePage() async -> Bool {
        await MainActor.run {
            NSWorkspace.shared.open(ClaudeBrowserBridgeContract.officialUsageURL)
        }
    }

    private static func dispatchAutomaticRefresh(
        requestID: String,
        allowSafariLaunch: Bool,
        runtime: ClaudeBrowserBridgeRuntime
    ) async -> ClaudeBrowserAutomaticDispatchResult {
        guard await defaultBrowserIdentity() == .safari else {
            return .unsupportedBrowser
        }
        guard await ensureSafariRunning(allowLaunch: allowSafariLaunch) else {
            return .browserUnavailable
        }
        guard await safariExtensionHealth() == .ready else {
            return .companionUnavailable
        }
        // Safari may terminate the Manifest V3 worker between five-minute
        // cycles. The single content-free wake can start the worker before its
        // runtime listener is installed, so its acknowledgement is advisory.
        // Give that one wake a bounded settle window, then send exactly one
        // work-bearing refresh command. There is no wake or refresh retry.
        await runtime.prepareBridgeReady(requestID)
        let wakeDelivered = await dispatchSafariMessage(
            name: safariWakeMessageName,
            userInfo: ["command": safariWakeMessageName, "requestID": requestID]
        )
        guard wakeDelivered else {
            await runtime.cancelBridgeReady(requestID)
            return .companionUnavailable
        }
        _ = await runtime.waitForBridgeReady(
            requestID,
            timeout: safariWorkerSettleTimeout
        )

        let delivered = await dispatchSafariMessage(
            name: ClaudeBrowserBridgeContract.automaticRefreshMessageName,
            userInfo: [
                "command": ClaudeBrowserBridgeContract.automaticRefreshMessageName,
                "requestID": requestID,
            ]
        )
        return delivered ? .dispatched : .companionUnavailable
    }

    private static func ensureSafariRunning(allowLaunch: Bool) async -> Bool {
        if await MainActor.run(body: { safariIsRunning }) { return true }
        guard allowLaunch, await launchSafariWithoutActivation() else { return false }

        // Launch Services can complete before Safari is visible in the running
        // application registry. Wait a bounded interval without activating it.
        for _ in 0..<20 {
            if await MainActor.run(body: { safariIsRunning }) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    @MainActor
    private static func launchSafariWithoutActivation() async -> Bool {
        guard let safariURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Safari"
        ) else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: safariURL,
                configuration: configuration
            ) { application, error in
                continuation.resume(returning: application != nil && error == nil)
            }
        }
    }

    private static func dispatchCloseOwnedTab(requestID: String) async {
        let isRunning = await MainActor.run { safariIsRunning }
        guard isRunning,
              await safariExtensionHealth() == .ready
        else { return }
        _ = await dispatchSafariMessage(
            name: ClaudeBrowserBridgeContract.closeOwnedTabMessageName,
            userInfo: [
                "command": ClaudeBrowserBridgeContract.closeOwnedTabMessageName,
                "requestID": requestID,
            ]
        )
    }

    private static func dispatchSafariMessage(
        name: String,
        userInfo: [String: Any]
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let completion = ClaudeBrowserDispatchCompletion(continuation)
            SFSafariApplication.dispatchMessage(
                withName: name,
                toExtensionWithIdentifier: safariExtensionIdentifier,
                userInfo: userInfo
            ) { error in
                if let error = error as NSError? {
                    logger.error(
                        "Safari companion dispatch failed for \(name, privacy: .public): \(error.domain, privacy: .public)/\(error.code, privacy: .public)"
                    )
                } else {
                    logger.notice(
                        "Safari companion dispatch accepted for \(name, privacy: .public)"
                    )
                }
                completion.resume(error == nil)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                completion.resume(false)
            }
        }
    }

    @MainActor
    private static var safariIsRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Safari"
        ).isEmpty
    }

    private static func repairCurrentCompanion() async -> ClaudeBrowserCompanionHealth {
        guard let browser = await defaultBrowserIdentity() else {
            return .browserUnavailable
        }
        switch browser {
        case .safari:
            try? await SFSafariApplication.showPreferencesForExtension(
                withIdentifier: safariExtensionIdentifier
            )
            return await safariExtensionHealth()
        case .chromium:
            return chromiumNativeHostManifestExists() ? .ready : .nativeHostMissing
        case .unsupported:
            return .unsupportedBrowser
        }
    }

    private static func chromiumNativeHostManifestExists() -> Bool {
        let name = ClaudeBrowserBridgeContract.chromiumNativeHostName + ".json"
        let roots = [
            "Google/Chrome/NativeMessagingHosts",
            "Chromium/NativeMessagingHosts",
            "Microsoft Edge/NativeMessagingHosts",
            "BraveSoftware/Brave-Browser/NativeMessagingHosts",
        ]
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return false }
        return roots.contains {
            FileManager.default.fileExists(
                atPath: support.appendingPathComponent($0, isDirectory: true)
                    .appendingPathComponent(name)
                    .path
            )
        }
    }
}

private enum DefaultBrowserIdentity: Equatable, Sendable {
    case safari
    case chromium
    case unsupported
}
