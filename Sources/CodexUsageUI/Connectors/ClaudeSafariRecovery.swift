import AppKit
import Foundation

/// What AUV can ask about Safari when Claude's exact reading cannot get through.
enum ClaudeSafariPrompt: Equatable, Sendable {
    /// Safari is not running.
    case launch
    /// Safari is running, but its companion has stopped answering.
    case restart
}

enum ClaudeSafariPromptTrigger: Equatable, Sendable {
    /// The automatic refresh timer. The person did not just ask for anything.
    case automatic
    /// Refresh All or the Accuracy Sync button.
    case user
}

struct ClaudeSafariPromptAnswer: Equatable, Sendable {
    var accepted: Bool
    var stopAskingDuringAutomaticRefresh = false
}

/// Decides when to ask. A person who pressed something is always answered; the
/// timer asks once per stretch, so a repeating refresh cannot repeat the prompt.
struct ClaudeSafariPromptPolicy: Equatable, Sendable {
    /// The page recovers by itself within about two minutes when it can, so a
    /// companion quiet for longer than this needs Safari restarted.
    static let companionStuckAfter: TimeInterval = 180
    static let silentSyncsBeforeRestartPrompt = 2

    private var firstSilentSyncAt: Date?
    private var silentSyncs = 0
    private var askedToRestart = false
    private var askedToLaunch = false

    mutating func safariWasRunning() {
        askedToLaunch = false
    }

    mutating func safariWasClosed() {
        firstSilentSyncAt = nil
        silentSyncs = 0
        askedToRestart = false
    }

    mutating func companionAnswered() {
        firstSilentSyncAt = nil
        silentSyncs = 0
        askedToRestart = false
    }

    mutating func companionWasSilent(at date: Date) {
        if firstSilentSyncAt == nil { firstSilentSyncAt = date }
        silentSyncs += 1
    }

    mutating func didAsk(_ prompt: ClaudeSafariPrompt) {
        switch prompt {
        case .launch: askedToLaunch = true
        case .restart: askedToRestart = true
        }
    }

    /// A restart is one attempt: its silent syncs start counting again, and the
    /// timer stays quiet until the companion has answered.
    mutating func restartAttempted() {
        firstSilentSyncAt = nil
        silentSyncs = 0
    }

    func asksToLaunch(trigger: ClaudeSafariPromptTrigger, automaticPromptsOff: Bool) -> Bool {
        switch trigger {
        case .user: true
        case .automatic: !automaticPromptsOff && !askedToLaunch
        }
    }

    func asksToRestart(
        at date: Date,
        trigger: ClaudeSafariPromptTrigger,
        automaticPromptsOff: Bool
    ) -> Bool {
        guard let firstSilentSyncAt,
              silentSyncs >= Self.silentSyncsBeforeRestartPrompt,
              date.timeIntervalSince(firstSilentSyncAt) >= Self.companionStuckAfter
        else { return false }
        switch trigger {
        case .user: return true
        case .automatic: return !automaticPromptsOff && !askedToRestart
        }
    }
}

/// The parts of asking about and starting Safari that touch the system.
struct ClaudeSafariRecovery {
    /// How often a sync is tried after Safari starts, and the wait in between,
    /// since its background page takes a moment to come up.
    static let syncAttemptsAfterStart = 3
    static let delayBetweenAttemptsAfterStart: TimeInterval = 5

    var ask: @MainActor (ClaudeSafariPrompt, ClaudeSafariPromptTrigger) -> ClaudeSafariPromptAnswer
    var launch: @MainActor () async -> Bool
    var restart: @MainActor () async -> Bool
    var now: @MainActor () -> Date = { Date() }
    var sleep: @Sendable (TimeInterval) async -> Void = { interval in
        try? await Task.sleep(for: .seconds(interval))
    }
}

extension ClaudeSafariRecovery {
    static func live(language: @escaping @MainActor () -> AppLanguage) -> Self {
        Self(
            ask: { prompt, trigger in
                ClaudeSafariPromptAlert.run(prompt, trigger: trigger, language: language())
            },
            launch: { await ClaudeSafariProcess.launchInBackground() },
            restart: {
                let restarted = await ClaudeSafariProcess.restart()
                if !restarted { ClaudeSafariPromptAlert.showRestartFailed(language: language()) }
                return restarted
            }
        )
    }
}

@MainActor
enum ClaudeSafariPromptCopy {
    struct Text: Equatable {
        let title: String
        let body: String
        let accept: String
        let decline: String
        let stopAsking: String
    }

    static func text(for prompt: ClaudeSafariPrompt, language: AppLanguage) -> Text {
        switch (prompt, language) {
        case (.launch, .simplifiedChinese):
            Text(
                title: "打开 Safari 以更新 Claude 用量？",
                body: "AUV 通过 Safari 读取 Claude 的精确用量，但 Safari 现在没有运行。Safari 会在后台打开，用一个小窗口读取用量页，读完后关闭这个窗口。",
                accept: "打开 Safari",
                decline: "暂不",
                stopAsking: "自动刷新时不再询问"
            )
        case (.launch, _):
            Text(
                title: "Open Safari to update Claude's usage?",
                body: "AUV reads Claude's exact usage through Safari, and Safari isn't running. It will open in the background and read the Usage page in a small window that closes afterwards.",
                accept: "Open Safari",
                decline: "Not Now",
                stopAsking: "Don't ask during automatic refresh"
            )
        case (.restart, .simplifiedChinese):
            Text(
                title: "重启 Safari 以恢复 Claude 同步？",
                body: "AUV 的 Safari 伴侣已停止响应，因此读不到 Claude 的精确用量。重启 Safari 可以重新加载它。Safari 会退出并重新打开，当前打开的窗口和标签页可能不会恢复，请先保存正在进行的内容。",
                accept: "重启 Safari",
                decline: "暂不",
                stopAsking: "自动刷新时不再询问"
            )
        case (.restart, _):
            Text(
                title: "Restart Safari to resume Claude sync?",
                body: "AUV's Safari companion has stopped responding, so Claude's exact usage can't be read. Restarting Safari reloads it. Safari will quit and reopen. Your open windows and tabs may not come back, so save your work there first.",
                accept: "Restart Safari",
                decline: "Not Now",
                stopAsking: "Don't ask during automatic refresh"
            )
        }
    }
}

/// A prompt can appear while the person is clicking or typing in another app,
/// and accepting the restart prompt quits Safari. One such click was seen 3.1
/// seconds after the prompt appeared, so its accept button waits longer than
/// that, and Return answers Not Now. Opening Safari costs little, so that
/// prompt only waits out a click already on its way.
enum ClaudeSafariPromptSafety {
    static func acceptButtonDelay(for prompt: ClaudeSafariPrompt) -> TimeInterval {
        switch prompt {
        case .launch: 1
        case .restart: 4
        }
    }

    static func returnKeyAccepts(_ prompt: ClaudeSafariPrompt) -> Bool {
        prompt == .launch
    }
}

@MainActor
private enum ClaudeSafariPromptAlert {
    static func run(
        _ prompt: ClaudeSafariPrompt,
        trigger: ClaudeSafariPromptTrigger,
        language: AppLanguage
    ) -> ClaudeSafariPromptAnswer {
        let copy = ClaudeSafariPromptCopy.text(for: prompt, language: language)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = copy.title
        alert.informativeText = copy.body
        let acceptButton = alert.addButton(withTitle: copy.accept)
        let declineButton = alert.addButton(withTitle: copy.decline)
        if !ClaudeSafariPromptSafety.returnKeyAccepts(prompt) {
            acceptButton.keyEquivalent = ""
            declineButton.keyEquivalent = "\r"
        }
        acceptButton.isEnabled = false
        let enableAccept = Timer(
            timeInterval: ClaudeSafariPromptSafety.acceptButtonDelay(for: prompt),
            repeats: false
        ) { [weak acceptButton] _ in
            MainActor.assumeIsolated { acceptButton?.isEnabled = true }
        }
        RunLoop.main.add(enableAccept, forMode: .modalPanel)
        defer { enableAccept.invalidate() }
        if trigger == .automatic {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = copy.stopAsking
        }
        // AUV has no Dock icon, so the alert must come forward by itself. The
        // app the person was using gets the front back afterwards.
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        let accepted = alert.runModal() == .alertFirstButtonReturn
        if let previous, !previous.isTerminated, previous != NSRunningApplication.current {
            previous.activate()
        }
        return ClaudeSafariPromptAnswer(
            accepted: accepted,
            stopAskingDuringAutomaticRefresh: alert.suppressionButton?.state == .on
        )
    }

    static func showRestartFailed(language: AppLanguage) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if language == .simplifiedChinese {
            alert.messageText = "Safari 没有退出"
            alert.informativeText = "Safari 可能正在等你回复一个对话框。请手动退出并重新打开 Safari。"
        } else {
            alert.messageText = "Safari didn't quit"
            alert.informativeText = "Safari may be waiting for you to answer a dialog. Quit and reopen Safari yourself."
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

@MainActor
private enum ClaudeSafariProcess {
    private static let launchDeadline: Duration = .seconds(20)
    private static let quitDeadline: Duration = .seconds(30)
    private static let pollInterval: Duration = .milliseconds(250)

    private static var running: [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: SafariWindowVisibility.bundleIdentifier
        ).filter { !$0.isTerminated }
    }

    /// Opens Safari without taking the front. The opened app is ready once it
    /// has finished launching, the same boundary the Bridge host uses.
    static func launchInBackground() async -> Bool {
        if running.contains(where: \.isFinishedLaunching) { return true }
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: SafariWindowVisibility.bundleIdentifier
        ) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        guard (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil
        else { return false }
        return await waitUntil(launchDeadline) { running.contains(where: \.isFinishedLaunching) }
    }

    /// Asks Safari to quit the ordinary way, so it can save its windows or ask
    /// about unsent forms, and never forces it.
    static func restart() async -> Bool {
        for application in running { application.terminate() }
        guard await waitUntil(quitDeadline, { running.isEmpty }) else { return false }
        return await launchInBackground()
    }

    private static func waitUntil(_ deadline: Duration, _ condition: () -> Bool) async -> Bool {
        let end = ContinuousClock.now.advanced(by: deadline)
        while ContinuousClock.now < end {
            if condition() { return true }
            try? await Task.sleep(for: pollInterval)
        }
        return condition()
    }
}
