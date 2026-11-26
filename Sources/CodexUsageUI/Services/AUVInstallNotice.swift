import AppKit
import Foundation

/// Tells the person, on launch, whether AUV is actually installed.
///
/// Dragging AUV out of its disk image gives no feedback of its own, and an app
/// opened straight from the disk image looks installed but is not. So:
/// - the first launch of a version from Applications plays a sound and says it
///   is installed, offering to eject the installer disk if it is still mounted;
/// - a launch from the disk image or from a temporary (translocated) location
///   says AUV is not installed yet and how to install it.
/// Anywhere else (a development build, a copy in Downloads) it stays quiet.
public enum AUVInstallNotice: Equatable, Sendable {
    case installed(version: String)
    case notInstalled

    static let noticedKey = "AUVInstallNoticeVersion.v1"

    public enum Location: Equatable, Sendable {
        case applications
        case diskImageOrTemporary
        case elsewhere
    }

    public static func location(
        bundlePath: String,
        homeDirectory: String = NSHomeDirectory(),
        isOnReadOnlyVolume: Bool
    ) -> Location {
        if bundlePath.contains("/AppTranslocation/") || isOnReadOnlyVolume {
            return .diskImageOrTemporary
        }
        if bundlePath.hasPrefix("/Applications/")
            || bundlePath.hasPrefix(homeDirectory + "/Applications/") {
            return .applications
        }
        return .elsewhere
    }

    /// `versionKey` names one build ("0.18.9 (2026111507)"); a notice already
    /// shown for it is not shown again.
    public static func decide(
        location: Location,
        version: String,
        versionKey: String,
        lastNoticedKey: String?
    ) -> AUVInstallNotice? {
        switch location {
        case .diskImageOrTemporary: return .notInstalled
        case .elsewhere: return nil
        case .applications:
            return lastNoticedKey == versionKey ? nil : .installed(version: version)
        }
    }

    public func title(_ language: AppLanguage) -> String {
        let zh = language == .simplifiedChinese
        switch self {
        case let .installed(version):
            return zh ? "AUV \(version) 已安装" : "AUV \(version) is installed"
        case .notInstalled:
            return zh ? "AUV 还没有安装" : "AUV is not installed yet"
        }
    }

    public func message(_ language: AppLanguage, installerMounted: Bool) -> String {
        let zh = language == .simplifiedChinese
        switch self {
        case .installed:
            let base = zh
                ? "AUV 已在“应用程序”中，以后从“应用程序”或启动台打开即可。设置和数据已保留。"
                : "AUV is in Applications. Open it from there or from Launchpad from now on. Your settings and data are kept."
            guard installerMounted else { return base }
            return base + (zh ? "\n\n安装盘可以推出了。" : "\n\nYou can eject the installer disk now.")
        case .notInstalled:
            return zh
                ? "AUV 现在是直接从安装盘或临时位置运行的。请退出 AUV，在安装盘窗口中把 UMA.app 拖到右边的 Applications，再从“应用程序”打开。"
                : "AUV is running straight from the installer disk or a temporary location. Quit AUV, drag UMA.app onto Applications on the right of the installer window, then open it from Applications."
        }
    }
}

/// The first-launch sound. English: the first seven tones of 门楼. Chinese: a
/// drumbeat, the seven tones, then the greeting the owner recorded. Built by
/// script/render_auv_welcome_sounds.py. A drag in the disk image cannot play
/// anything itself, so the sound that marks a successful install is here.
///
/// The Wabi-Sabi and Brutalist looks each have their own sound, the same in
/// every language: 门楼's seven tones in the Japanese 都节 scale on a koto, and
/// the first six notes of the Soviet anthem on low brass, at a brisk march.
@MainActor
public enum AUVWelcomeSound {
    public enum Style: String, CaseIterable, Sendable {
        case standard
        case wabiSabi
        case brutalist
    }

    private static var current: NSSound?

    static func data(_ language: AppLanguage, style: Style) -> Data {
        switch style {
        case .standard:
            return language == .simplifiedChinese ? AUVWelcomeSoundData.zh : AUVWelcomeSoundData.en
        case .wabiSabi: return AUVWelcomeSoundData.wabiSabi
        case .brutalist: return AUVWelcomeSoundData.brutalist
        }
    }

    /// Plays the welcome sound; without a style, the one for the current
    /// appearance pack (Wabi-sabi: 和楽 tones, Brutalist: its fanfare).
    public static func play(_ language: AppLanguage, style: Style? = nil) {
        let style = style ?? Style(rawValue: AUVLook.current.rawValue) ?? .standard
        let data = data(language, style: style)
        if let sound = NSSound(data: data) {
            current = sound   // keep it alive while it plays
            sound.play()
        } else {
            NSSound(named: "Glass")?.play()
        }
    }
}

/// Five quick clicks on the AUV menu-bar button play the welcome sound once.
/// Each click must come within `window` seconds of the one before; the count
/// starts over after a play.
public struct AUVWelcomeTapCounter: Equatable, Sendable {
    public static let requiredTaps = 5
    public static let window: TimeInterval = 2

    private var count = 0
    private var lastTap: TimeInterval?

    public init() {}

    /// Records a click at `time` (seconds, any steady clock); true on the fifth.
    public mutating func record(at time: TimeInterval) -> Bool {
        if let lastTap, time - lastTap > Self.window { count = 0 }
        lastTap = time
        count += 1
        guard count >= Self.requiredTaps else { return false }
        count = 0
        lastTap = nil
        return true
    }
}

@MainActor
public enum AUVInstallNoticePresenter {
    /// Shows the notice that fits this launch, if any. `language` is read when
    /// the notice is shown, after the app's settings are loaded.
    public static func presentIfNeeded(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        language: @escaping @MainActor () -> AppLanguage
    ) {
        let url = bundle.bundleURL.resolvingSymlinksInPath()
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?
            .volumeIsReadOnly ?? false
        let location = AUVInstallNotice.location(bundlePath: url.path, isOnReadOnlyVolume: readOnly)
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let versionKey = "\(version) (\(build))"
        guard let notice = AUVInstallNotice.decide(
            location: location,
            version: version,
            versionKey: versionKey,
            lastNoticedKey: defaults.string(forKey: AUVInstallNotice.noticedKey)
        ) else { return }

        // Let the main window come up first, so the notice sits in front of it.
        // A run-loop timer, not a main-queue block: the alert runs modally, and
        // from inside a main-queue block it would hold back every main-actor
        // task while it is open, and Quit would wait forever for the shutdown
        // task (0.18.9 build 2026111507 hung that way).
        let pending = Pending(notice: notice, language: language, defaults: defaults, versionKey: versionKey)
        let timer = Timer(timeInterval: 0.8, repeats: false) { _ in
            MainActor.assumeIsolated {
                show(pending.notice, language: pending.language(),
                     defaults: pending.defaults, versionKey: pending.versionKey)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Carried into the timer, which fires on the main run loop; nothing in it
    /// is touched off the main thread.
    private struct Pending: @unchecked Sendable {
        let notice: AUVInstallNotice
        let language: @MainActor () -> AppLanguage
        let defaults: UserDefaults
        let versionKey: String
    }

    private static func show(
        _ notice: AUVInstallNotice,
        language: AppLanguage,
        defaults: UserDefaults,
        versionKey: String
    ) {
        let zh = language == .simplifiedChinese
        let installer = notice == .notInstalled ? nil : mountedInstallerDisk()
        let alert = NSAlert()
        alert.messageText = notice.title(language)
        alert.informativeText = notice.message(language, installerMounted: installer != nil)
        switch notice {
        case .installed:
            alert.alertStyle = .informational
            if installer != nil {
                alert.addButton(withTitle: zh ? "推出安装盘" : "Eject Installer")
                alert.addButton(withTitle: zh ? "好" : "OK")
            } else {
                alert.addButton(withTitle: zh ? "好" : "OK")
            }
            defaults.set(versionKey, forKey: AUVInstallNotice.noticedKey)
            AUVWelcomeSound.play(language)
        case .notInstalled:
            alert.alertStyle = .warning
            alert.addButton(withTitle: zh ? "退出 AUV" : "Quit AUV")
            alert.addButton(withTitle: zh ? "继续使用" : "Keep Using")
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch notice {
        case .installed:
            if let installer, response == .alertFirstButtonReturn {
                try? NSWorkspace.shared.unmountAndEjectDevice(at: installer)
            }
        case .notInstalled:
            // Quit from the run loop, never from inside this call, so the
            // shutdown work AUV waits for on quitting can run.
            if response == .alertFirstButtonReturn {
                NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
            }
        }
    }

    /// AUV's own installer disk: a mounted volume named "AUV …" that holds
    /// UMA.app next to a link to /Applications.
    static func mountedInstallerDisk() -> URL? {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]
        ) ?? []
        return volumes.first { volume in
            guard volume.lastPathComponent.hasPrefix("AUV ") else { return false }
            let link = volume.appendingPathComponent("Applications").path
            return FileManager.default.fileExists(atPath: volume.appendingPathComponent("UMA.app").path)
                && (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == "/Applications"
        }
    }
}
