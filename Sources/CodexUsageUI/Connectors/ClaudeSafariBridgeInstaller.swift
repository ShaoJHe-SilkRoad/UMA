import AppKit
import CoreServices
import Foundation
import SafariServices

/// Where the Safari Bridge that Claude's exact sync needs stands on this Mac.
///
/// The Bridge is its own app because Safari only loads a web extension from an
/// app it knows about. AUV carries the exact build it is pinned to and copies
/// it into ~/Applications, where Safari finds it like any installed app.
public enum ClaudeSafariBridgeStatus: Equatable, Sendable {
    /// The installed Bridge is the build this AUV is pinned to.
    case ready
    /// No Bridge is installed.
    case missing
    /// A Bridge is installed, but not the build this AUV is pinned to.
    case outdated
    /// The right build is installed but still carries the download flag, so
    /// macOS runs it from a temporary copy that Safari will not talk to.
    case needsRepair
    /// AUV is running from a quarantined download location; macOS gives it a
    /// temporary path there, so it must be moved to Applications first.
    case appNotInApplications
}

struct ClaudeSafariBridgeIdentity: Equatable, Sendable {
    let build: String
    let generation: String

    init(build: String, generation: String) {
        self.build = build
        self.generation = generation
    }

    init?(info: [String: Any]) {
        guard let build = info["CFBundleVersion"] as? String,
              let generation = info["UMARuntimeGenerationID"] as? String
        else { return nil }
        self.init(build: build, generation: generation)
    }

    static func of(app url: URL) -> Self? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else { return nil }
        return Self(info: info)
    }
}

enum ClaudeSafariBridgeInstallError: Error, Equatable {
    case notBundled
    case appNotInApplications
    case copyFailed
    case launchFailed
}

struct ClaudeSafariBridgeInstaller {
    static let bundledRelativePath = "Contents/Library/SafariBridge/UMA Safari Bridge.app"
    static let applicationName = "UMA Safari Bridge.app"
    static let extensionIdentifier = "com.silkrd.uma.ClaudeBrowserCompanion"

    /// The Bridge inside AUV, copied out on install.
    let bundledBridge: URL
    /// The build and runtime generation AUV is pinned to.
    let expected: ClaudeSafariBridgeIdentity
    /// AUV's own bundle, so a copy inside it is never taken for an install.
    let appBundle: URL
    let runsFromApplications: Bool
    /// Where a new install goes: ~/Applications.
    let installDirectory: URL
    var installedCopies: () -> [URL]
    var identity: (URL) -> ClaudeSafariBridgeIdentity? = ClaudeSafariBridgeIdentity.of(app:)
    var register: (URL) -> Void = { LSRegisterURL($0 as CFURL, true) }
    var quitRunning: @MainActor () async -> Void = {}
    var launch: @MainActor (URL) async -> Bool = { _ in true }
    var openSafariExtensionSettings: @MainActor () async -> Void = {}
    var openClaudeInSafari: @MainActor () async -> Void = {}
    /// Whether the extension is on in Safari, or nil when Safari won't say.
    var extensionEnabled: @MainActor () async -> Bool? = { nil }
    var fileManager: FileManager = .default
    var isQuarantined: (URL) -> Bool = ClaudeSafariBridgeQuarantine.isQuarantined
    var clearQuarantine: (URL) -> Void = ClaudeSafariBridgeQuarantine.clear
    /// Moves an old copy out of the way; the Trash, so nothing is lost.
    var discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    /// Copies that count as installed: not inside AUV, not in the Trash.
    var installed: [URL] {
        installedCopies().filter { url in
            let path = url.standardizedFileURL.path
            return !path.hasPrefix(appBundle.standardizedFileURL.path + "/")
                && !path.contains("/.Trash/")
        }
    }

    func status() -> ClaudeSafariBridgeStatus {
        let copies = installed
        let pinned = copies.filter { identity($0) == expected }
        if pinned.contains(where: { !isQuarantined($0) }) { return .ready }
        if !pinned.isEmpty { return .needsRepair }
        if !copies.isEmpty { return .outdated }
        return runsFromApplications ? .missing : .appNotInApplications
    }

    /// An outdated copy is replaced where it is if that folder can be written;
    /// otherwise, and for a first install, the Bridge goes to ~/Applications.
    func destination() -> URL {
        if let current = installed.first {
            let folder = current.deletingLastPathComponent()
            if fileManager.isWritableFile(atPath: folder.path) { return current }
        }
        return installDirectory.appendingPathComponent(Self.applicationName, isDirectory: true)
    }

    @MainActor
    func install() async throws -> URL {
        guard fileManager.fileExists(atPath: bundledBridge.path) else {
            throw ClaudeSafariBridgeInstallError.notBundled
        }
        guard runsFromApplications else { throw ClaudeSafariBridgeInstallError.appNotInApplications }
        let target = destination()
        await quitRunning()
        do {
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: target.path) { try discard(target) }
            try fileManager.copyItem(at: bundledBridge, to: target)
        } catch {
            throw ClaudeSafariBridgeInstallError.copyFailed
        }
        // The copy keeps the download flag AUV itself arrived with. Launched
        // with it, macOS runs the Bridge from a temporary read-only copy (App
        // Translocation), and Safari never accepts its requests: on a new Mac
        // every read was dropped until the flag was removed. The Bridge is
        // notarized and was checked with AUV when AUV was first opened.
        clearQuarantine(target)
        register(target)
        guard await launch(target) else { throw ClaudeSafariBridgeInstallError.launchFailed }
        return target
    }
}

extension ClaudeSafariBridgeInstaller {
    /// The running app's installer, or nil when AUV carries no Bridge, as in a
    /// development build. Then nothing about the Bridge is shown or checked.
    static func live(bundle: Bundle = .main) -> Self? {
        let bundled = bundle.bundleURL.appendingPathComponent(bundledRelativePath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: bundled.path),
              let hostID = bundle.object(forInfoDictionaryKey: "UMASafariHostBundleIdentifier") as? String,
              let build = bundle.object(forInfoDictionaryKey: "UMASafariHostExtensionBuild") as? String,
              let generation = bundle.object(forInfoDictionaryKey: "UMASafariHostRuntimeGenerationID") as? String
        else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Self(
            bundledBridge: bundled,
            expected: ClaudeSafariBridgeIdentity(build: build, generation: generation),
            appBundle: bundle.bundleURL,
            runsFromApplications: !bundle.bundlePath.contains("/AppTranslocation/"),
            installDirectory: home.appendingPathComponent("Applications", isDirectory: true),
            installedCopies: {
                NSWorkspace.shared.urlsForApplications(withBundleIdentifier: hostID)
            },
            quitRunning: { await ClaudeSafariBridgeProcess.quit(bundleIdentifier: hostID) },
            launch: { await ClaudeSafariBridgeProcess.launch($0) },
            openSafariExtensionSettings: { await ClaudeSafariBridgeProcess.openSafariExtensionSettings() },
            openClaudeInSafari: { await ClaudeSafariBridgeProcess.openClaudeInSafari() },
            extensionEnabled: { await ClaudeSafariBridgeProcess.extensionEnabled() }
        )
    }
}

@MainActor
enum ClaudeSafariBridgeProcess {
    static func quit(bundleIdentifier: String) async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        let end = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < end,
              running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// The Bridge has no window; starting it once is what makes Safari list
    /// its extension.
    static func launch(_ url: URL) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil
    }

    static func openClaudeInSafari() async {
        guard let page = URL(string: "https://claude.ai/settings/usage"),
              let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        else { return }
        _ = try? await NSWorkspace.shared.open([page], withApplicationAt: safari, configuration: .init())
    }

    /// SafariServices answers on its own XPC queue. These two must not be
    /// main-actor isolated: a main-actor reply closure there traps, which is
    /// how 0.18.7 build 2026111502 quit right after updating the Bridge.
    nonisolated static func extensionEnabled() async -> Bool? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            SFSafariExtensionManager.getStateOfSafariExtension(
                withIdentifier: ClaudeSafariBridgeInstaller.extensionIdentifier
            ) { @Sendable state, error in
                continuation.resume(returning: error == nil ? state?.isEnabled : nil)
            }
        }
    }

    nonisolated static func showExtensionPreferences() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSafariApplication.showPreferencesForExtension(
                withIdentifier: ClaudeSafariBridgeInstaller.extensionIdentifier
            ) { @Sendable error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    /// Opens Safari's Extensions settings at the companion. If Safari will not
    /// take the request, Safari is opened so the person can go there.
    static func openSafariExtensionSettings() async {
        let shown = await showExtensionPreferences()
        guard !shown,
              let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        else { return }
        _ = try? await NSWorkspace.shared.openApplication(at: safari, configuration: .init())
    }
}

/// What AUV tells the person after the Bridge is installed: the one step only
/// they can take, turning the extension on in Safari.
@MainActor
enum ClaudeSafariBridgeCopy {
    struct Text: Equatable {
        let title: String
        let body: String
        let open: String
        let later: String
    }

    static func installed(language: AppLanguage) -> Text {
        if language == .simplifiedChinese {
            return Text(
                title: "在 Safari 中启用 AUV 的伴侣",
                body: "Safari 助手已安装。最后一步需要你在 Safari 中完成：在“设置 → 扩展”中勾选“UMA Browser Companion for Claude”，并允许它访问 claude.ai。然后在 Safari 中登录 claude.ai，AUV 就能读取 Claude 的精确用量。",
                open: "打开 Safari 设置",
                later: "稍后"
            )
        }
        return Text(
            title: "Turn on AUV's companion in Safari",
            body: "The Safari Bridge is installed. One step is left, and only you can take it: in Safari's Settings → Extensions, turn on “UMA Browser Companion for Claude” and allow it on claude.ai. Then sign in to claude.ai in Safari, and AUV can read Claude's exact usage.",
            open: "Open Safari Settings",
            later: "Later"
        )
    }

    static func failed(_ error: ClaudeSafariBridgeInstallError, language: AppLanguage) -> (String, String) {
        let chinese = language == .simplifiedChinese
        switch error {
        case .appNotInApplications:
            return chinese
                ? ("请先把 AUV 移到“应用程序”", "从“下载”直接打开时，macOS 会把 AUV 放在临时位置。请把 AUV 拖进“应用程序”，重新打开后再安装 Safari 助手。")
                : ("Move AUV to Applications first", "Opened straight from Downloads, macOS runs AUV from a temporary place. Drag AUV into Applications, open it again, then install the Safari Bridge.")
        case .launchFailed:
            return chinese
                ? ("Safari 助手没有启动", "已复制到“应用程序”，但没能启动。请在“访达”中打开“UMA Safari Bridge”一次。")
                : ("The Safari Bridge didn't start", "It was copied to Applications but didn't start. Open “UMA Safari Bridge” once in the Finder.")
        case .notBundled, .copyFailed:
            return chinese
                ? ("无法安装 Safari 助手", "AUV 没能把 Safari 助手复制到你的“应用程序”文件夹。请重新下载 AUV 后再试。")
                : ("The Safari Bridge couldn't be installed", "AUV couldn't copy the Safari Bridge into your Applications folder. Download AUV again and retry.")
        }
    }
}

/// The two alerts around installing the Bridge. Only the running app shows
/// them; tests give their own answers.
struct ClaudeSafariBridgeAlerts {
    /// Returns whether to open Safari's Extensions settings.
    var installed: @MainActor () -> Bool
    var failed: @MainActor (ClaudeSafariBridgeInstallError) -> Void
}

extension ClaudeSafariBridgeAlerts {
    static func live(language: @escaping @MainActor () -> AppLanguage) -> Self {
        Self(
            installed: {
                let copy = ClaudeSafariBridgeCopy.installed(language: language())
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = copy.title
                alert.informativeText = copy.body
                alert.addButton(withTitle: copy.open)
                alert.addButton(withTitle: copy.later)
                NSApp.activate(ignoringOtherApps: true)
                return alert.runModal() == .alertFirstButtonReturn
            },
            failed: { error in
                let (title, body) = ClaudeSafariBridgeCopy.failed(error, language: language())
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = title
                alert.informativeText = body
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        )
    }
}

/// The download flag macOS puts on files that came from the internet.
enum ClaudeSafariBridgeQuarantine {
    static let attribute = "com.apple.quarantine"

    static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// Removes the flag from the app and everything inside it.
    static func clear(_ url: URL) {
        removexattr(url.path, attribute, XATTR_NOFOLLOW)
        guard let items = FileManager.default.enumerator(atPath: url.path) else { return }
        for case let item as String in items {
            removexattr(url.appendingPathComponent(item).path, attribute, XATTR_NOFOLLOW)
        }
    }
}

/// The words for each step of setting up Claude's exact sync through Safari,
/// shared by Claude's page and Claude Settings.
enum ClaudeSafariSetupCopy {
    struct Step: Equatable {
        let title: String
        let message: String
        let button: String?
        let symbol: String
        let urgent: Bool
    }

    static func step(_ step: ClaudeSafariSetup.Step, language: AppLanguage) -> Step {
        let zh = language == .simplifiedChinese
        switch step {
        case .moveToApplications:
            return Step(
                title: zh ? "把 AUV 移到“应用程序”" : "Move AUV to Applications",
                message: zh ? "要读取 Claude 的精确用量，请把 AUV 拖进“应用程序”后重新打开。"
                    : "To read Claude's exact usage, drag AUV into Applications and open it again.",
                button: nil, symbol: "folder.badge.plus", urgent: true)
        case .installBridge:
            return Step(
                title: zh ? "1. 安装 Safari 助手" : "1. Install the Safari Bridge",
                message: zh ? "第 1 步，共 4 步：Claude 的精确用量通过 Safari 读取。安装 AUV 自带的 Safari 助手。"
                    : "Step 1 of 4: Claude's exact usage is read through Safari. Install the Safari Bridge that comes with AUV.",
                button: zh ? "安装 Safari 助手" : "Install Safari Bridge", symbol: "safari", urgent: false)
        case .updateBridge:
            return Step(
                title: zh ? "1. 更新 Safari 助手" : "1. Update the Safari Bridge",
                message: zh ? "Safari 助手需要更新，才能与这个版本的 AUV 配合。" : "The Safari Bridge needs an update to match this AUV.",
                button: zh ? "更新 Safari 助手" : "Update Safari Bridge", symbol: "arrow.down.circle", urgent: true)
        case .repairBridge:
            return Step(
                title: zh ? "1. 修复 Safari 助手" : "1. Repair the Safari Bridge",
                message: zh ? "Safari 助手需要修复，Safari 才能使用它。" : "The Safari Bridge needs a repair before Safari can use it.",
                button: zh ? "修复 Safari 助手" : "Repair Safari Bridge", symbol: "wrench.and.screwdriver", urgent: true)
        case .enableExtension:
            return Step(
                title: zh ? "2. 在 Safari 中启用扩展" : "2. Turn on the extension in Safari",
                message: zh ? "第 2 步，共 4 步：在 Safari 的“设置 → 扩展”中，勾选“UMA Browser Companion for Claude”。"
                    : "Step 2 of 4: In Safari's Settings → Extensions, tick “UMA Browser Companion for Claude”.",
                button: zh ? "打开 Safari 设置" : "Open Safari Settings", symbol: "puzzlepiece.extension", urgent: false)
        case .allowSite:
            return Step(
                title: zh ? "3. 允许访问 claude.ai" : "3. Allow it on claude.ai",
                message: zh ? "第 3 步，共 4 步：在 Safari 的“设置 → 扩展”中选中该扩展，点“编辑网站…”，把 claude.ai 设为“允许”。"
                    : "Step 3 of 4: In Safari's Settings → Extensions, select the extension, choose Edit Websites…, and set claude.ai to Allow.",
                button: zh ? "打开 Safari 设置" : "Open Safari Settings", symbol: "lock.open", urgent: false)
        case .signIn:
            return Step(
                title: zh ? "3. 在 Safari 中登录 claude.ai" : "3. Sign in to claude.ai in Safari",
                message: zh ? "第 3 步，共 4 步：在 Safari 中登录 claude.ai，AUV 只读取用量页上的数字。"
                    : "Step 3 of 4: Sign in to claude.ai in Safari. AUV reads only the numbers on its Usage page.",
                button: zh ? "打开 claude.ai" : "Open claude.ai", symbol: "person.crop.circle", urgent: false)
        case .syncOnce:
            return Step(
                title: zh ? "4. 同步一次" : "4. Sync once",
                message: zh ? "最后一步：确认 Safari 已打开并登录 claude.ai，然后同步一次。之后会随“全部刷新”和自动刷新更新。"
                    : "Last step: with Safari open and signed in to claude.ai, sync once. After that it updates with Refresh All and automatic refresh.",
                button: zh ? "立即同步" : "Sync Now", symbol: "arrow.triangle.2.circlepath", urgent: false)
        case .done:
            return Step(
                title: zh ? "已完成" : "Done",
                message: zh ? "Claude 精确同步已设置好。" : "Claude's exact sync is set up.",
                button: nil, symbol: "checkmark.circle", urgent: false)
        }
    }
}
