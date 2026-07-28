import AppKit
import Foundation

public struct WorkBuddyOfficialUsagePageAction: @unchecked Sendable {
    public static let url = URL(
        string: "https://www.workbuddy.cn/docs/workbuddy/Usage"
    )!

    private let openURL: @MainActor @Sendable (URL) -> Bool

    public init(openURL: @escaping @MainActor @Sendable (URL) -> Bool) {
        self.openURL = openURL
    }

    @MainActor
    @discardableResult
    public func request() -> Bool {
        guard Self.isAllowed(Self.url) else { return false }
        return openURL(Self.url)
    }

    public static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host == "www.workbuddy.cn"
            && url.path == "/docs/workbuddy/Usage"
            && url.user == nil
            && url.password == nil
            && url.query == nil
            && url.fragment == nil
    }

    public static let live = WorkBuddyOfficialUsagePageAction {
        NSWorkspace.shared.open($0)
    }
}
