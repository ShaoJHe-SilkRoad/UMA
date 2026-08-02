import AppKit
import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import SafariServices

private final class ClaudeBrowserBridgeRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var server: ClaudeBrowserFileHandoffServer?

    func start(handler: @escaping ClaudeBrowserProductionIntegration.ObservationHandler) {
        lock.lock()
        defer { lock.unlock() }
        guard server == nil else { return }
        let candidate = ClaudeBrowserFileHandoffServer { envelope in
            Task { await handler(.success(envelope)) }
        }
        do {
            try candidate.start()
            server = candidate
        } catch let error as ClaudeBrowserBridgeError {
            Task { await handler(.failure(error)) }
        } catch {
            Task { await handler(.failure(.socketUnavailable)) }
        }
    }

    func stop() {
        lock.lock()
        let active = server
        server = nil
        lock.unlock()
        active?.stop()
    }
}

extension ClaudeBrowserProductionIntegration {
    private static let safariExtensionIdentifier =
        "com.kevinchen.CodexUsageMonitor.ClaudeBrowserCompanion"

    static func make() -> Self {
        let runtime = ClaudeBrowserBridgeRuntime()
        return Self(
            startListening: { handler in runtime.start(handler: handler) },
            stopListening: { runtime.stop() },
            checkHealth: { await currentHealth() },
            openUsagePage: { await openOfficialUsagePage() },
            repairCompanion: { await repairCurrentCompanion() }
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

private enum DefaultBrowserIdentity: Sendable {
    case safari
    case chromium
    case unsupported
}
