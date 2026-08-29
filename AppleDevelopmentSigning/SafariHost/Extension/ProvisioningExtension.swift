import Foundation
import SafariServices

// Provisioning-only shell. Packaging replaces this executable with the real
// SafariWebExtensionHandler before final child-first signing.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        context.completeRequest(returningItems: [])
    }
}
