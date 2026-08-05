import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import OSLog
import SafariServices

/// Native-message handler for the bundled Safari Web Extension. Safari owns
/// the authenticated page; this extension receives only the already-normalized
/// allowlisted observation object.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let logger = Logger(
        subsystem: "com.kevinchen.CodexUsageMonitor.ClaudeBrowserCompanion",
        category: "NativeBridge"
    )

    func beginRequest(with context: NSExtensionContext) {
        let replyItem = NSExtensionItem()
        replyItem.userInfo = [SFExtensionMessageKey: ["ok": false]]
        defer { context.completeRequest(returningItems: [replyItem]) }

        guard let input = context.inputItems.first as? NSExtensionItem,
              let object = input.userInfo?[SFExtensionMessageKey],
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return }

        let isObservation = (try? ClaudeBrowserMessageDecoder.decode(data))?.browserFamily == .safari
        let automationStatus = (try? ClaudeBrowserAutomationEventDecoder.decode(data))?.status
        let isAutomationEvent = automationStatus != nil
        guard isObservation || isAutomationEvent else { return }

        do {
            try ClaudeBrowserFileHandoffWriter.write(data)
            replyItem.userInfo = [SFExtensionMessageKey: ["ok": true]]
            if let automationStatus {
                logger.notice(
                    "Forwarded sanitized Claude browser automation status: \(automationStatus.rawValue, privacy: .public)"
                )
            } else {
                logger.notice("Forwarded sanitized Claude browser observation")
            }
        } catch let error as ClaudeBrowserBridgeError {
            logger.error("Sanitized Claude usage forwarding failed: \(Self.safeCode(for: error), privacy: .public)")
        } catch {
            logger.error("Sanitized Claude usage forwarding failed: unknown")
        }
    }

    private static func safeCode(for error: ClaudeBrowserBridgeError) -> String {
        switch error {
        case .messageEmpty: "message-empty"
        case .messageTooLarge: "message-too-large"
        case .malformedJSON: "malformed-json"
        case .invalidTopLevel: "invalid-top-level"
        case .unexpectedField: "unexpected-field"
        case .missingField: "missing-field"
        case .invalidContract: "invalid-contract"
        case .invalidPercentage: "invalid-percentage"
        case .invalidReset: "invalid-reset"
        case .invalidTimestamp: "invalid-timestamp"
        case .noAccountWindow: "no-account-window"
        case .invalidBrowserOrigin: "invalid-browser-origin"
        case .nativeMessagingFrameMalformed: "native-frame-malformed"
        case .socketUnavailable: "local-bridge-unavailable"
        case .socketUnsafe: "local-bridge-unsafe"
        case .socketConnectionFailed: "local-bridge-connect-failed"
        case .socketWriteFailed: "local-bridge-write-failed"
        case .socketReadFailed: "local-bridge-read-failed"
        }
    }
}
