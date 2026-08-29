import Foundation
import SafariServices

// Provisioning-only implementation. The shipped extension executable is built
// from BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        context.completeRequest(returningItems: [])
    }
}
