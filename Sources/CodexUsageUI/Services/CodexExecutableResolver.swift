import Foundation

protocol CodexExecutableResolving: Sendable {
    func resolve() throws -> URL
}

/// Resolves a locally installed Codex executable without touching account data.
/// Production accepts only the locally verified bundled CLI in the official
/// ChatGPT/Codex application. Test instances may inject their own paths
/// without changing that production contract.
struct CodexExecutableResolver: CodexExecutableResolving, Sendable {
    static let defaultCandidatePaths = [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
    ]

    static let defaultApplicationPaths = [
        CodexOfficialChatGPTApplicationIdentity.canonicalPath
    ]

    private let candidatePaths: [String]
    private let applicationPaths: [String]
    private let isExecutable: @Sendable (String) -> Bool
    private let fileExists: @Sendable (String) -> Bool
    private let bundleIdentifier: @Sendable (String) -> String?
    private let requiresOfficialBundleVerification: Bool

    init(
        candidatePaths: [String]? = nil,
        applicationPaths: [String]? = nil,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        bundleIdentifier: @escaping @Sendable (String) -> String? = { Bundle(path: $0)?.bundleIdentifier }
    ) {
        self.candidatePaths = candidatePaths ?? Self.defaultCandidatePaths
        self.applicationPaths = applicationPaths ?? Self.defaultApplicationPaths
        self.fileExists = fileExists
        self.isExecutable = isExecutable
        self.bundleIdentifier = bundleIdentifier
        self.requiresOfficialBundleVerification = candidatePaths == nil && applicationPaths == nil
    }

    func resolve() throws -> URL {
        var foundNonExecutableCandidate = false
        for path in candidatePaths {
            guard fileExists(path) else { continue }
            if requiresOfficialBundleVerification,
               bundleIdentifier(CodexOfficialChatGPTApplicationIdentity.canonicalPath)
                    != CodexOfficialChatGPTApplicationIdentity.bundleIdentifier {
                throw CodexUsageClientError(.codexApplicationNotFound)
            }
            if isExecutable(path) {
                return URL(fileURLWithPath: path)
            }
            // A broken higher-precedence install must not mask a healthy
            // fallback (for example a Homebrew or development CLI).
            foundNonExecutableCandidate = true
        }

        if foundNonExecutableCandidate {
            throw CodexUsageClientError(.codexExecutableNotExecutable)
        }
        if applicationPaths.contains(where: fileExists) {
            // The known application exists, but its bundled resource is absent.
            throw CodexUsageClientError(.codexExecutableNotFound)
        }
        throw CodexUsageClientError(.codexApplicationNotFound)
    }
}
