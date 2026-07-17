import Foundation

/// An application-owned decision boundary for the local Codex connection.
/// Production supplies a native `NSAlert`; tests supply a deterministic
/// closure. It is intentionally not modeled as a macOS privacy permission.
@MainActor
public struct CodexLocalAccessConfirmationAction {
    private let requestDecision: @MainActor () -> Bool

    public init(requestDecision: @escaping @MainActor () -> Bool) {
        self.requestDecision = requestDecision
    }

    public func request() -> Bool {
        requestDecision()
    }
}

/// Stable identity used only to locate the bundled official CLI executable.
public enum CodexOfficialChatGPTApplicationIdentity {
    public static let canonicalPath = "/Applications/ChatGPT.app"
    public static let bundleIdentifier = "com.openai.codex"

    public static func matches(path: String, bundleIdentifier: String?) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path == canonicalPath
            && bundleIdentifier == Self.bundleIdentifier
    }
}
