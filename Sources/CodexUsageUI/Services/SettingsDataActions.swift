import Darwin
import Foundation

enum SettingsDataActionError: Error, Equatable {
    case unsafeExportDestination
}

/// The Settings data boundary deliberately knows only the three allowlisted
/// usage caches. It never touches provider credentials, browser state, or
/// local conversation/session files.
actor SettingsRetainedDataService {
    private let snapshots: AgentConnectorSnapshotStore
    private let browserCache: ClaudeBrowserSanitizedCacheStore
    private let smartAnchors: ClaudeSmartAnchorStore

    init(
        snapshots: AgentConnectorSnapshotStore = AgentConnectorSnapshotStore(),
        browserCache: ClaudeBrowserSanitizedCacheStore = ClaudeBrowserSanitizedCacheStore(),
        smartAnchors: ClaudeSmartAnchorStore = ClaudeSmartAnchorStore()
    ) {
        self.snapshots = snapshots
        self.browserCache = browserCache
        self.smartAnchors = smartAnchors
    }

    func clear() async throws {
        try await snapshots.clear()
        try await browserCache.clear()
        try await smartAnchors.clear()
    }
}

struct SanitizedSettingsDiagnostics: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let applicationVersion: String
    let applicationBuild: String
    let activeProviderCount: Int
    let automaticBackgroundRefresh: Bool
    let refreshOnWake: Bool
    let keepMonitoringWhenWindowsClose: Bool
}

enum SettingsDiagnosticsExporter {
    @MainActor
    static func data(
        activeProviderCount: Int,
        preferences: ApplicationPreferences,
        bundle: Bundle = .main
    ) throws -> Data {
        let receipt = SanitizedSettingsDiagnostics(
            schemaVersion: SanitizedSettingsDiagnostics.schemaVersion,
            applicationVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "development",
            applicationBuild: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "development",
            activeProviderCount: max(0, activeProviderCount),
            automaticBackgroundRefresh: preferences.value(
                for: UMAApplicationPreferenceKeys.automaticBackgroundRefresh
            ),
            refreshOnWake: preferences.value(
                for: UMAApplicationPreferenceKeys.refreshOnWake
            ),
            keepMonitoringWhenWindowsClose: preferences.value(
                for: UMAApplicationPreferenceKeys.keepMonitoringWhenWindowsClose
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(receipt)
    }

    static func write(_ data: Data, to destination: URL) throws {
        let target = destination
        let fileManager = FileManager.default
        let parent = target.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard target.isFileURL,
              !target.hasDirectoryPath,
              !containsSymlink(inExistingPath: parent),
              fileManager.fileExists(
                  atPath: parent.path,
                  isDirectory: &parentIsDirectory
              ),
              parentIsDirectory.boolValue
        else {
            throw SettingsDataActionError.unsafeExportDestination
        }

        if fileManager.fileExists(atPath: target.path) {
            let values = try target.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard !containsSymlink(inExistingPath: target),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw SettingsDataActionError.unsafeExportDestination
            }
        }

        try data.write(to: target, options: .atomic)
        let committed = try target.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard committed.isRegularFile == true,
              committed.isSymbolicLink != true
        else {
            throw SettingsDataActionError.unsafeExportDestination
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: target.path
        )
    }

    private static func containsSymlink(inExistingPath location: URL) -> Bool {
        let normalizedPath = location.path
        var currentPath = "/"
        for component in (normalizedPath as NSString).pathComponents.dropFirst() {
            currentPath = (currentPath as NSString).appendingPathComponent(component)
            var metadata = stat()
            guard lstat(currentPath, &metadata) == 0 else { return true }
            if metadata.st_mode & S_IFMT == S_IFLNK { return true }
        }
        return false
    }
}
