import Foundation
import CoreServices
import Security

protocol CodexExecutableResolving: Sendable {
    func resolve() throws -> URL
}

/// Resolves a locally installed Codex executable without touching account data.
/// Production discovers registered and standard installations, then validates
/// the application identity and signature before using a bundled executable.
struct CodexExecutableResolver: CodexExecutableResolving, Sendable {
    static let defaultCandidatePaths = [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
    ]

    static let defaultApplicationPaths = [
        "/Applications/Codex.app", "/Applications/ChatGPT.app",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app").path,
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/ChatGPT.app").path
    ]

    static let bundledExecutablePaths = [
        "Contents/Resources/codex", "Contents/Resources/codex-cli/bin/codex"
    ]

    private let candidatePaths: [String]
    private let applicationPaths: [String]
    private let isExecutable: @Sendable (String) -> Bool
    private let fileExists: @Sendable (String) -> Bool
    private let bundleIdentifier: @Sendable (String) -> String?
    private let requiresOfficialBundleVerification: Bool
    private let registeredApplicationPaths: @Sendable () -> [String]
    private let validSignature: @Sendable (String) -> Bool

    init(
        candidatePaths: [String]? = nil,
        applicationPaths: [String]? = nil,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        bundleIdentifier: @escaping @Sendable (String) -> String? = { Bundle(path: $0)?.bundleIdentifier },
        registeredApplicationPaths: @escaping @Sendable () -> [String] = Self.registeredApplications,
        validSignature: @escaping @Sendable (String) -> Bool = Self.hasValidOfficialSignature
    ) {
        self.candidatePaths = candidatePaths ?? Self.defaultCandidatePaths
        self.applicationPaths = applicationPaths ?? Self.defaultApplicationPaths
        self.fileExists = fileExists
        self.isExecutable = isExecutable
        self.bundleIdentifier = bundleIdentifier
        self.requiresOfficialBundleVerification = candidatePaths == nil
        self.registeredApplicationPaths = registeredApplicationPaths
        self.validSignature = validSignature
    }

    func resolve() throws -> URL {
        if requiresOfficialBundleVerification { return try resolveOfficialApplication() }
        var foundNonExecutableCandidate = false
        for path in candidatePaths {
            guard fileExists(path) else { continue }
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

    private func resolveOfficialApplication() throws -> URL {
        var seen = Set<String>()
        var foundOfficialApplication = false
        var foundNonExecutable = false
        // Explicitly supplied application locations have priority; registered
        // renamed/custom-location apps are found without scanning user files.
        for path in applicationPaths + registeredApplicationPaths() {
            let app = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            guard seen.insert(app.path).inserted, fileExists(app.path),
                  bundleIdentifier(app.path) == CodexOfficialChatGPTApplicationIdentity.bundleIdentifier,
                  validSignature(app.path) else { continue }
            foundOfficialApplication = true
            for relativePath in Self.bundledExecutablePaths {
                let executable = app.appendingPathComponent(relativePath).resolvingSymlinksInPath()
                // A symlink outside the verified bundle is not a bundled CLI.
                guard executable.path.hasPrefix(app.path + "/"), fileExists(executable.path) else { continue }
                if isExecutable(executable.path) { return executable }
                foundNonExecutable = true
            }
        }
        throw CodexUsageClientError(foundNonExecutable ? .codexExecutableNotExecutable
            : foundOfficialApplication ? .codexExecutableNotFound : .codexApplicationNotFound)
    }

    private static func registeredApplications() -> [String] {
        let urls = LSCopyApplicationURLsForBundleIdentifier(
            CodexOfficialChatGPTApplicationIdentity.bundleIdentifier as CFString, nil
        )?.takeRetainedValue() as? [URL] ?? []
        return urls.map(\.path).sorted()
    }

    private static func hasValidOfficialSignature(_ path: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code,
              SecRequirementCreateWithString(
                "anchor apple generic and identifier \"com.openai.codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\"" as CFString,
                [], &requirement
              ) == errSecSuccess else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
