import ClaudeStatusLineCore
import Foundation

/// One file boundary shared by runtime writers and Settings data actions.
/// Production keeps its released paths; development never borrows that root.
public struct ApplicationDataPaths: Equatable, Sendable {
    public let rootURL: URL
    public let homeDirectory: URL
    public let supportsProviderConfiguration: Bool
    private var snapshotOverride: URL? = nil

    public static func current(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        applicationSupportDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Self {
        let production = bundleIdentifier == "com.silkrd.uma"
        let identifier = bundleIdentifier.flatMap { value in
            value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression)
                != nil ? value : nil
        } ?? "unbundled"
        let root = production
            ? applicationSupportDirectory.appendingPathComponent("CodexUsageMonitor", isDirectory: true)
            : applicationSupportDirectory
                .appendingPathComponent("CodexUsageMonitor-Development", isDirectory: true)
                .appendingPathComponent(identifier, isDirectory: true)
        return Self(
            rootURL: root,
            homeDirectory: homeDirectory,
            supportsProviderConfiguration: production
        )
    }

    public var snapshotURL: URL {
        snapshotOverride ?? rootURL.appendingPathComponent("connector-snapshots.json")
    }
    func overridingSnapshotURL(_ url: URL?) -> Self {
        var paths = self
        if let url { paths.snapshotOverride = url }
        return paths
    }
    var codexLedgerURL: URL { rootURL.appendingPathComponent("token-cost-ledger.json") }
    var browserCacheURL: URL {
        rootURL.appendingPathComponent("ClaudeBrowserIntegration", isDirectory: true)
            .appendingPathComponent("sanitized-quota.json")
    }
    var smartAnchorsURL: URL { rootURL.appendingPathComponent("claude-smart-anchors.json") }
    var statusLinePaths: ClaudeStatusLineConfigurationPaths {
        let directory = rootURL.appendingPathComponent("ClaudeLocalSmartMode", isDirectory: true)
        // The development manager is disabled; even its diagnostic paths must
        // not refer to production's provider-owned configuration file.
        let settingsRoot = supportsProviderConfiguration
            ? homeDirectory
            : rootURL.appendingPathComponent("ProviderConfiguration", isDirectory: true)
        return ClaudeStatusLineConfigurationPaths(
            settingsURL: settingsRoot.appendingPathComponent(".claude/settings.json"),
            integrationDirectoryURL: directory,
            backupURL: directory.appendingPathComponent("settings-before-uma.json"),
            metadataURL: directory.appendingPathComponent("restore-metadata.json"),
            stateURL: directory.appendingPathComponent("status-line.json"),
            receiptURL: directory.appendingPathComponent("stop-receipt.json")
        )
    }
}
