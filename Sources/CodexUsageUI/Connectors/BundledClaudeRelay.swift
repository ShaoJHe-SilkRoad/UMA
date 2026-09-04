import ClaudeStatusLineCore
import Foundation

/// A persistent Claude Code command must refer to an installed app's helper.
/// This check performs no installation, configuration write, or provider read.
enum BundledClaudeRelay {
    static func executableURL(
        bundleURL: URL = Bundle.main.bundleURL,
        installedApplicationRoots: [URL]? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = installedApplicationRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            // The accepted direct-distribution installation also uses Desktop.
            home.appendingPathComponent("Desktop", isDirectory: true),
        ]
        let bundle = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let transientComponents: Set<String> = [
            "AppTranslocation", "Worktrees", ".build", "Build", "DerivedData",
        ]
        guard bundleURL.isFileURL, bundle.pathExtension == "app",
              !bundle.pathComponents.contains(where: transientComponents.contains),
              roots.contains(where: {
                  $0.standardizedFileURL.resolvingSymlinksInPath()
                      == bundle.deletingLastPathComponent()
              })
        else { return nil }

        let helper = bundle.appendingPathComponent("Contents/Helpers/ClaudeStatusLineRelay")
        guard helper.resolvingSymlinksInPath() == helper,
              let values = try? helper.resourceValues(forKeys: [
                  .isRegularFileKey, .isSymbolicLinkKey,
              ]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              fileManager.isExecutableFile(atPath: helper.path)
        else { return nil }
        return helper
    }

    static func command(
        executableURL: URL,
        paths: ClaudeStatusLineConfigurationPaths
    ) -> String {
        [executableURL.path, "--state", paths.stateURL.path,
         "--prior-status-line", paths.backupURL.path]
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            .joined(separator: " ")
    }
}
