import AppKit
import CodexUsageUI

/// Presents a product-owned alert only after an explicit Connect click. This
/// is ordinary application UI, not a macOS privacy permission.
@MainActor
enum NativeLocalCodexAccessConfirmation {
    static func copy(for language: AppLanguage) -> (title: String, body: String, allow: String, cancel: String) {
        if language == .simplifiedChinese {
            return (
                "允许访问本机 Codex？",
                "Codex Usage Monitor 将连接到这台 Mac 上的 Codex 服务，以读取账户状态和使用限额。它不会读取或保存你的密码或身份验证令牌。",
                "允许",
                "取消"
            )
        }
        return (
            "Allow Local Codex Access?",
            "Codex Usage Monitor will connect to the Codex service on this Mac to read account status and usage limits. It will not read or store your password or authentication tokens.",
            "Allow",
            "Cancel"
        )
    }

    static func action(for store: UsageStore) -> CodexLocalAccessConfirmationAction {
        CodexLocalAccessConfirmationAction { [weak store] in
            let language = store?.language ?? .systemMatch()
            let alertCopy = Self.copy(for: language)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = alertCopy.title
            alert.informativeText = alertCopy.body
            alert.addButton(withTitle: alertCopy.allow)
            alert.addButton(withTitle: alertCopy.cancel)
            return alert.runModal() == .alertFirstButtonReturn
        }
    }
}
