import AppKit
import CodexUsageUI
import Darwin
import Foundation
import SwiftUI

@main
@MainActor
struct PreviewRendererTool {
    static func main() async {
        do {
            try await run()
        } catch {
            let diagnostic = startupDiagnostic(for: error)
            FileHandle.standardError.write(
                Data("PreviewRendererTool failed: \(diagnostic)\n".utf8)
            )
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        _ = NSApplication.shared

        let arguments = Array(CommandLine.arguments.dropFirst())
        let interactive = arguments.contains("--interactive")
        if interactive {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        let outputPath = arguments.first(where: { !$0.hasPrefix("--") })
            ?? "work/codex-usage-panel-preview.png"
        let showsSettings = arguments.contains("--settings")
        let language: AppLanguage = arguments.contains("--english") ? .english : .simplifiedChinese
        let isDark = arguments.contains("--dark")
        let reduceTransparency = arguments.contains("--reduce-transparency")
        let increaseContrast = arguments.contains("--increase-contrast")
        let wallpaperStyle = arguments
            .first(where: { $0.hasPrefix("--wallpaper=") })
            .flatMap {
                PreviewWallpaperStyle(
                    rawValue: String($0.dropFirst("--wallpaper=".count))
                )
            }
            ?? .colorful
        let background = PreviewWallpaper(style: wallpaperStyle)
        let dynamicTypeSize: DynamicTypeSize = arguments.contains("--large-text")
            ? .accessibility1
            : .medium
        AppTypography.configurePreviewPointSizeScale(
            arguments.contains("--large-text") ? 1.35 : 1
        )
        let percent = arguments
            .first(where: { $0.hasPrefix("--percent=") })
            .flatMap { Double($0.dropFirst("--percent=".count)) }
            ?? 44

        let content: AnyView
        let renderSize: CGSize
        var interactiveHeightUpdate: ((CGFloat) -> Void)?
        if arguments.contains("--assistant-regular")
            || arguments.contains("--assistant-minimalist") {
            let density: DesktopAssistantResolvedDensity = arguments.contains("--assistant-minimalist")
                ? .minimalist
                : .regular
            let shared = makeCodexCard(
                arguments: arguments,
                language: language,
                percent: percent
            )
            let workBuddyCard = try makeWorkBuddyCard(
                arguments: arguments,
                language: language
            )
            var sharedAssistantCards: [SharedUsageCardPresentation] = []
            if !arguments.contains("--assistant-workbuddy-only") {
                sharedAssistantCards.append(shared)
            }
            if arguments.contains("--assistant-claude") {
                sharedAssistantCards.append(
                    makeClaudeCard(
                        arguments: arguments,
                        language: language
                    )
                )
            }
            if let workBuddyCard {
                sharedAssistantCards.append(workBuddyCard)
            }
            sharedAssistantCards.append(
                contentsOf: makeSyntheticCards(
                    count: syntheticProviderCount(arguments),
                    language: language
                )
            )
            let assistantCards = SharedUsagePresentationPolicy.assistantCards(
                from: sharedAssistantCards
            ).map {
                DesktopAssistantCard(
                    shared: $0,
                    language: language,
                    now: Date(timeIntervalSince1970: 1_800_000_300)
                )
            }
            let size = DesktopAssistantMetrics.stackSize(
                for: density,
                rowCount: assistantCards.count
            )
            renderSize = size
            content = AnyView(
                ZStack {
                    background
                    DesktopAssistantView(
                        cards: assistantCards,
                        density: density,
                        appearanceOverride: DesktopAssistantAppearanceOverride(
                            reduceTransparency: reduceTransparency,
                            increaseContrast: increaseContrast
                        )
                    )
                }
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, isDark ? ColorScheme.dark : ColorScheme.light)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
            )
        } else {
            let workBuddyCard = try makeWorkBuddyCard(
                arguments: arguments,
                language: language
            )
            let claudeCard = arguments.contains("--claude")
                ? makeClaudeCard(
                    arguments: arguments,
                    language: language
                )
                : nil
            let previewScenario = arguments.contains("--workbuddy-only")
                ? CodexPreviewScenario.permission
                : try codexPreviewScenario(arguments)
            let codexCard = shouldIncludeCodexCard(for: previewScenario)
                ? makeCodexCard(
                    arguments: arguments,
                    language: language,
                    percent: percent,
                    scenario: previewScenario
                )
                : nil
            let extraCards = (codexCard.map { [$0] } ?? [])
                + (claudeCard.map { [$0] } ?? [])
                + (workBuddyCard.map { [$0] } ?? [])
                + makeSyntheticCards(
                    count: syntheticProviderCount(arguments),
                    language: language
                )
            let store = UsageStore.preview(
                scenario: previewScenario,
                language: language,
                presentationCards: extraCards,
                chineseLoginProviderName: arguments.contains(
                    "--chinese-login-option"
                ) ? "Kimi" : nil,
                includesAgentSettings: showsSettings || interactive
            )
            let tuning = GlassTuning.final
            let expandedProviderIDs: Set<String>
            if arguments.contains("--all-expanded") {
                expandedProviderIDs = Set(store.presentationCards.map(\.id))
            } else if arguments.contains("--claude-expanded") {
                expandedProviderIDs = ["claude.browserSync"]
            } else if arguments.contains("--workbuddy-expanded") {
                expandedProviderIDs = [
                    arguments.contains("--workbuddy-account-web")
                        ? "workbuddy.accountWebCredits"
                        : "workbuddy.manualAvailability"
                ]
            } else {
                expandedProviderIDs = []
            }
            let appearanceOverride = UsagePanelAppearanceOverride(
                reduceTransparency: reduceTransparency,
                increaseContrast: increaseContrast,
                reduceMotion: arguments.contains("--reduce-motion")
            )
            let cardVisibilityOverride = arguments.contains("--oracle-card-set")
                ? UsagePanelCardVisibility(
                    showUsageSummary: true,
                    showRecentTasks: false,
                    showAPICost: false
                )
                : nil
            let settingsDestinationProviderID = arguments
                .first(where: { $0.hasPrefix("--settings-agent=") })
                .map {
                    String($0.dropFirst("--settings-agent=".count))
                }
            let workBuddyLogin = (
                arguments.contains("--workbuddy-login")
                    || arguments.contains("--workbuddy-login-unverified")
            )
                ? WorkBuddyLoginCoordinator.preview(
                    signatureTrust: arguments.contains(
                        "--workbuddy-login-unverified"
                    ) ? .unverifiable : .trusted
                )
                : nil
            let accountWebSync = arguments.contains(
                "--workbuddy-account-web-settings"
            ) ? (
                arguments.contains("--workbuddy-account-web-failed")
                    ? WorkBuddyAccountWebSessionController.previewFailed()
                    : (
                        arguments.contains("--workbuddy-account-web-connected")
                            ? WorkBuddyAccountWebSessionController.previewConnected(
                                autoRefreshEnabled:
                                    !arguments.contains("--workbuddy-manual-only")
                            )
                            : WorkBuddyAccountWebSessionController()
                    )
            ) : nil
            let workBuddySettings = workBuddyLogin != nil || accountWebSync != nil
                ? WorkBuddySettingsModel.preview()
                : nil
            let panelHeight = measuredPanelHeight(
                store: store,
                tuning: tuning,
                showsSettings: showsSettings,
                settingsDestinationProviderID:
                    settingsDestinationProviderID,
                expandedProviderIDs: expandedProviderIDs,
                workBuddySettings: workBuddySettings,
                workBuddyLogin: workBuddyLogin,
                workBuddyAccountWebSync: accountWebSync,
                appearanceOverride: appearanceOverride,
                cardVisibilityOverride: cardVisibilityOverride
            )
            renderSize = CGSize(
                width: UsagePanelMetrics.width,
                height: panelHeight
            )
            content = AnyView(ZStack {
                background
                UsagePanelView(
                    store: store,
                    tuning: tuning,
                    preferencesEnabled: false,
                    settingsInitiallyPresented: showsSettings,
                    settingsDestinationProviderID:
                        settingsDestinationProviderID,
                    expandedProviderIDs: expandedProviderIDs,
                    onHeightChange: { height in
                        guard interactive else { return }
                        interactiveHeightUpdate?(height)
                    },
                    workBuddySettings: workBuddySettings,
                    workBuddyLogin: workBuddyLogin,
                    workBuddyAccountWebSync: accountWebSync,
                    appearanceOverride: appearanceOverride,
                    renderedHeightOverride: interactive ? nil : panelHeight,
                    cardVisibilityOverride: cardVisibilityOverride
                )
            }
            .frame(
                width: UsagePanelMetrics.width,
                height: interactive ? nil : panelHeight
            )
            .environment(\.colorScheme, isDark ? ColorScheme.dark : ColorScheme.light)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            )
        }

        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: renderSize)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: interactive ? [.titled, .closable] : [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.title = "UMA 0.11-G2 Visual Review Candidate"
        if interactive {
            interactiveHeightUpdate = { height in
                let contentSize = CGSize(
                    width: UsagePanelMetrics.width,
                    height: height
                )
                let oldTop = window.frame.maxY
                var frame = window.frameRect(
                    forContentRect: CGRect(origin: .zero, size: contentSize)
                )
                frame.origin = CGPoint(
                    x: window.frame.origin.x,
                    y: oldTop - frame.height
                )
                window.setFrame(frame, display: true, animate: true)
            }
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.run()
            return
        }
        // Settings destinations and natural-height cards resolve through
        // onAppear and preference propagation. Let that bounded layout cycle
        // settle before capturing so evidence reflects the final hierarchy.
        for _ in 0..<30 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(renderSize.width * 2),
            pixelsHigh: Int(renderSize.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw PreviewError.renderFailed
        }
        bitmap.size = renderSize
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PreviewError.renderFailed
        }

        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: outputURL, options: .atomic)
    }

    private static func startupDiagnostic(for error: Error) -> String {
        if let previewError = error as? PreviewError {
            switch previewError {
            case .renderFailed:
                return "render-failed"
            case .invalidScenario:
                return "invalid-scenario"
            }
        }

        let cocoaError = error as NSError
        return "startup-error domain=\(cocoaError.domain) code=\(cocoaError.code)"
    }

    private static func codexPreviewScenario(
        _ arguments: [String]
    ) throws -> CodexPreviewScenario {
        guard let argument = arguments.first(where: {
            $0.hasPrefix("--codex-scenario=")
        }) else {
            return .ready
        }
        let rawValue = String(argument.dropFirst("--codex-scenario=".count))
        guard let scenario = CodexPreviewScenario(rawValue: rawValue) else {
            throw PreviewError.invalidScenario
        }
        return scenario
    }

    private static func shouldIncludeCodexCard(
        for scenario: CodexPreviewScenario
    ) -> Bool {
        switch scenario {
        case .ready, .refreshing, .stale, .settings:
            true
        default:
            false
        }
    }

    private static func makeCodexCard(
        arguments: [String],
        language: AppLanguage,
        percent: Double = 44,
        scenario: CodexPreviewScenario? = nil
    ) -> SharedUsageCardPresentation {
        let remaining: SharedRemainingValue
        if arguments.contains("--unlimited") {
            remaining = .unlimited
        } else if arguments.contains("--unavailable") {
            remaining = .unavailable
        } else {
            remaining = .finite(min(100, max(0, percent)))
        }
        let isStale = arguments.contains("--stale") || scenario == .stale
        let isRefreshing = scenario == .refreshing
        let window = SharedUsageWindowPresentation(
            id: "seven-day",
            kind: .sevenDay,
            compactLabel: "7D",
            accessibilityLabel: language == .english
                ? "seven-day window"
                : "七天额度窗口",
            remaining: remaining,
            resetsAt: Date(timeIntervalSince1970: 1_800_007_200),
            resetText: language == .english
                ? "Resets in 2 hr"
                : "2 小时后重置"
        )
        return SharedUsageCardPresentation(
            id: "codex.local",
            providerName: arguments.contains("--long-copy")
                ? (
                    language == .english
                        ? "Codex Extended Local Provider"
                        : "Codex 扩展本机服务提供商"
                )
                : "Codex",
            planLabel: "PRO",
            connectionStatus: arguments.contains("--failed")
                ? .failed
                : (isRefreshing ? .transitional : (isStale ? .stale : .connected)),
            freshness: isStale ? .stale : .fresh,
            windows: [window],
            selectedWindowID: window.id,
            remaining: remaining,
            sourceDescription: language == .english
                ? "Official local Codex usage"
                : "Codex 官方本机用量",
            severity: SharedUsagePresentationPolicy.severity(for: remaining),
            isRetainingLastValidValue: isStale
        )
    }

    private static func makeClaudeCard(
        arguments: [String],
        language: AppLanguage
    ) -> SharedUsageCardPresentation {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fiveHourPercent = arguments
            .first(where: { $0.hasPrefix("--claude-five-percent=") })
            .flatMap {
                Double($0.dropFirst("--claude-five-percent=".count))
            }
            .map { min(100, max(0, $0)) }
            ?? 62
        let sevenDayPercent = arguments
            .first(where: { $0.hasPrefix("--claude-seven-percent=") })
            .flatMap {
                Double($0.dropFirst("--claude-seven-percent=".count))
            }
            .map { min(100, max(0, $0)) }
            ?? 74
        let fiveHour = SharedUsageWindowPresentation(
            id: "claude-five-hour",
            kind: .fiveHour,
            compactLabel: "5H",
            accessibilityLabel: language == .english
                ? "five-hour window"
                : "五小时额度窗口",
            remaining: .finite(fiveHourPercent),
            resetsAt: now.addingTimeInterval(7_200),
            resetText: language == .english
                ? "Resets in 2 hr"
                : "2 小时后重置"
        )
        let sevenDay = SharedUsageWindowPresentation(
            id: "claude-seven-day",
            kind: .sevenDay,
            compactLabel: "7D",
            accessibilityLabel: language == .english
                ? "seven-day window"
                : "七天额度窗口",
            remaining: .finite(sevenDayPercent),
            resetsAt: now.addingTimeInterval(172_800),
            resetText: language == .english
                ? "Resets in 2 days"
                : "2 天后重置"
        )
        let windows: [SharedUsageWindowPresentation]
        if arguments.contains("--claude-five-hour-only") {
            windows = [fiveHour]
        } else if arguments.contains("--claude-seven-day-only") {
            windows = [sevenDay]
        } else {
            windows = [fiveHour, sevenDay]
        }
        let selectedWindow = windows.min {
            ($0.remaining.finitePercent ?? .infinity)
                < ($1.remaining.finitePercent ?? .infinity)
        }
        let isFailed = arguments.contains("--claude-failed")
        let isCached = arguments.contains("--claude-cached")
        let isStale = arguments.contains("--claude-stale") || isFailed
        let remaining = selectedWindow?.remaining ?? .unavailable
        return SharedUsageCardPresentation(
            id: "claude.browserSync",
            providerName: "Claude Code",
            planLabel: nil,
            connectionStatus: isFailed
                ? .failed
                : (isStale ? .stale : .connected),
            freshness: isCached ? .cached : (isStale ? .stale : .fresh),
            windows: windows,
            selectedWindowID: selectedWindow?.id,
            remaining: remaining,
            sourceDescription: language == .english
                ? "Claude official Usage page · Browser Sync · Experimental"
                : "Claude 官方使用量页面 · 浏览器同步 · 实验性",
            isVisibleInDesktopAssistant: true,
            severity: isCached || isStale
                ? .neutral
                : SharedUsagePresentationPolicy.severity(for: remaining),
            isRetainingLastValidValue: isCached || isStale,
            capturedAt: now
        )
    }

    private static func measuredPanelHeight(
        store: UsageStore,
        tuning: GlassTuning,
        showsSettings: Bool,
        settingsDestinationProviderID: String?,
        expandedProviderIDs: Set<String>,
        workBuddySettings: WorkBuddySettingsModel?,
        workBuddyLogin: WorkBuddyLoginCoordinator?,
        workBuddyAccountWebSync: WorkBuddyAccountWebSessionController?,
        appearanceOverride: UsagePanelAppearanceOverride,
        cardVisibilityOverride: UsagePanelCardVisibility?
    ) -> CGFloat {
        let measurement = PanelHeightMeasurement()
        let host = NSHostingView(
            rootView: UsagePanelView(
                store: store,
                tuning: tuning,
                preferencesEnabled: false,
                settingsInitiallyPresented: showsSettings,
                settingsDestinationProviderID: settingsDestinationProviderID,
                expandedProviderIDs: expandedProviderIDs,
                onHeightChange: { measurement.height = $0 },
                workBuddySettings: workBuddySettings,
                workBuddyLogin: workBuddyLogin,
                workBuddyAccountWebSync: workBuddyAccountWebSync,
                appearanceOverride: appearanceOverride,
                cardVisibilityOverride: cardVisibilityOverride
            )
        )
        host.frame = CGRect(
            x: 0,
            y: 0,
            width: UsagePanelMetrics.width,
            height: UsagePanelMetrics.height
        )
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        window.orderOut(nil)
        return UsagePanelMetrics.resolvedContentHeight(measurement.height)
    }

    private static func makeWorkBuddyCard(
        arguments: [String],
        language: AppLanguage
    ) throws -> SharedUsageCardPresentation? {
        if arguments.contains("--workbuddy-login")
            || arguments.contains("--workbuddy-login-unverified") {
            return nil
        }
        guard arguments.contains("--assistant-workbuddy")
            || arguments.contains("--assistant-workbuddy-only")
            || arguments.contains(where: { $0.hasPrefix("--workbuddy") }) else {
            return nil
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lifecycle: SharedAvailabilityLifecycle
        let availability: SharedAvailabilityPresentation?
        if arguments.contains("--workbuddy-unconfigured") {
            lifecycle = .unconfigured
            availability = nil
        } else if arguments.contains("--workbuddy-invalid") {
            lifecycle = .invalid
            availability = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
                value: .invalid(reason: .unsupportedSchema),
                language: language
            )
        } else if arguments.contains("--workbuddy-unavailable") {
            lifecycle = .unavailable
            availability = nil
        } else {
            lifecycle = .configured
            let remaining: Int64
            if arguments.contains("--workbuddy-synthetic-3600") {
                remaining = 3_600
            } else if arguments.contains("--workbuddy-exhausted") {
                remaining = 0
            } else if arguments.contains("--workbuddy-critical") {
                remaining = 400
            } else if arguments.contains("--workbuddy-warning") {
                remaining = 1_000
            } else if arguments.contains("--workbuddy-absolute") {
                remaining = 50_000
            } else {
                remaining = 500
            }
            let used: Int64? = if arguments.contains("--workbuddy-absolute") {
                nil
            } else if arguments.contains("--workbuddy-synthetic-3600") {
                400
            } else if arguments.contains("--workbuddy-exhausted") {
                4_000
            } else if arguments.contains("--workbuddy-critical") {
                3_600
            } else if arguments.contains("--workbuddy-warning") {
                3_000
            } else if arguments.contains("--workbuddy-total") {
                nil
            } else {
                0
            }
            let total: Int64? = if arguments.contains("--workbuddy-absolute") {
                nil
            } else if arguments.contains("--workbuddy-synthetic-3600")
                || arguments.contains("--workbuddy-exhausted")
                || arguments.contains("--workbuddy-critical")
                || arguments.contains("--workbuddy-warning") {
                4_000
            } else {
                500
            }
            let scope: CreditScope = if arguments.contains("--workbuddy-enterprise") {
                .buddyAIEnterpriseShared
            } else if arguments.contains("--workbuddy-unknown-scope") {
                .buddyAIUnknown
            } else {
                .buddyAISharedPersonal
            }
            let planTier: CreditPlanTier? = if arguments.contains("--workbuddy-enterprise") {
                .enterprise
            } else if arguments.contains("--workbuddy-unknown-scope") {
                nil
            } else {
                .personal
            }
            let isAccountWeb = arguments.contains("--workbuddy-account-web")
            let balance: CreditBalance
            if isAccountWeb {
                balance = try CreditBalance(
                    validatingDecimalRemaining: Decimal(string: "10131.06")!,
                    scope: .buddyAIUnknown,
                    observedAt: now,
                    provenance: .authenticatedAccountWeb(observedAt: now)
                )
            } else if let customValue = arguments
                .first(where: { $0.hasPrefix("--workbuddy-value=") })
                .flatMap({
                    Decimal(
                        string: String(
                            $0.dropFirst("--workbuddy-value=".count)
                        ),
                        locale: Locale(identifier: "en_US_POSIX")
                    )
                }) {
                balance = try CreditBalance(
                    validatingDecimalRemaining: customValue,
                    scope: scope,
                    planTier: planTier,
                    nextExpiryAt: now.addingTimeInterval(86_400),
                    observedAt: now,
                    provenance: .manualConfirmed(at: now)
                )
            } else {
                balance = try CreditBalance(
                    validatingRemaining: remaining,
                    used: used,
                    total: total,
                    scope: scope,
                    planTier: planTier,
                    nextExpiryAt: now.addingTimeInterval(86_400),
                    observedAt: now,
                    provenance: .manualConfirmed(at: now)
                )
            }
            availability = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
                value: .credits(balance),
                language: language
            )
        }
        let isAccountWeb = arguments.contains("--workbuddy-account-web")
        return SharedUsageCardPresentation(
            id: isAccountWeb
                ? "workbuddy.accountWebCredits"
                : "workbuddy.manualAvailability",
            providerName: arguments.contains("--long-copy")
                ? (
                    language == .english
                        ? "WorkBuddy Extended Credit Provider"
                        : "WorkBuddy 扩展额度服务提供商"
                )
                : "WorkBuddy",
            planLabel: lifecycle == .configured && !isAccountWeb
                ? {
                    if arguments.contains("--workbuddy-enterprise") {
                        return WorkBuddyPlanTier.enterprise.rawValue
                    }
                    if arguments.contains("--workbuddy-unknown-scope") {
                        return WorkBuddyPlanTier.unknown.rawValue
                    }
                    return arguments.contains("--workbuddy-synthetic-3600")
                        ? WorkBuddyPlanTier.standard.rawValue
                        : WorkBuddyPlanTier.experience.rawValue
                }()
                : nil,
            connectionStatus: isAccountWeb ? .connected : .disconnected,
            freshness: isAccountWeb ? .fresh : .unavailable,
            windows: [],
            selectedWindowID: nil,
            remaining: .unavailable,
            availability: availability,
            accountCreditBreakdown: isAccountWeb
                ? SharedAccountCreditBreakdown(
                    subscriptionRemaining: 9_000,
                    addOnRemaining: 0,
                    benefitGiftRemaining: Decimal(string: "1131.06")!,
                    calculatedTotalRemaining: Decimal(string: "10131.06")!,
                    observedAt: now
                )
                : nil,
            availabilityLifecycle: isAccountWeb ? nil : lifecycle,
            isVisibleInDesktopAssistant: true,
            severity: .neutral,
            capturedAt: now
        )
    }

    private static func syntheticProviderCount(_ arguments: [String]) -> Int {
        guard
            let argument = arguments.first(where: {
                $0.hasPrefix("--synthetic-providers=")
            }),
            let count = Int(
                argument.dropFirst("--synthetic-providers=".count)
            )
        else {
            return 0
        }
        return min(8, max(0, count))
    }

    private static func makeSyntheticCards(
        count: Int,
        language: AppLanguage
    ) -> [SharedUsageCardPresentation] {
        (0..<count).map { index in
            let providerNumber = index + 2
            let percent = Double(max(8, 88 - (index * 11)))
            let remaining = SharedRemainingValue.finite(percent)
            let window = SharedUsageWindowPresentation(
                id: "synthetic.\(providerNumber).seven-day",
                kind: .sevenDay,
                compactLabel: "7D",
                accessibilityLabel: language == .english
                    ? "seven-day window"
                    : "七天额度窗口",
                remaining: remaining,
                resetsAt: Date(
                    timeIntervalSince1970: 1_800_000_000
                        + Double(index * 3_600)
                ),
                resetText: language == .english
                    ? "Resets later today"
                    : "今天稍后重置"
            )
            return SharedUsageCardPresentation(
                id: "synthetic.agent.\(providerNumber)",
                providerName: "Agent \(providerNumber)",
                planLabel: index.isMultiple(of: 2) ? "PRO" : "TEAM",
                connectionStatus: index == count - 1 && count > 4
                    ? .stale
                    : .connected,
                freshness: index == count - 1 && count > 4
                    ? .stale
                    : .fresh,
                windows: [window],
                selectedWindowID: window.id,
                remaining: remaining,
                sourceDescription: language == .english
                    ? "Synthetic renderer record"
                    : "合成渲染记录",
                isVisibleInDesktopAssistant: true,
                severity: SharedUsagePresentationPolicy.severity(for: remaining),
                isRetainingLastValidValue: index == count - 1 && count > 4,
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }
}

@MainActor
private final class PanelHeightMeasurement {
    var height: CGFloat?
}

private enum PreviewError: Error {
    case renderFailed
    case invalidScenario
}

private enum PreviewWallpaperStyle: String {
    case bright
    case dark
    case colorful
    case photographic
    case flat
}

private struct PreviewWallpaper: View {
    let style: PreviewWallpaperStyle

    var body: some View {
        switch style {
        case .bright:
            LinearGradient(
                colors: [.white, Color(red: 0.66, green: 0.90, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.14),
                    Color(red: 0.16, green: 0.12, blue: 0.23)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .colorful:
            LinearGradient(
                colors: [
                    Color(red: 0.72, green: 0.84, blue: 0.96),
                    Color(red: 0.34, green: 0.45, blue: 0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .photographic:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.22, blue: 0.34),
                        Color(red: 0.76, green: 0.48, blue: 0.30),
                        Color(red: 0.18, green: 0.42, blue: 0.37)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(Color.orange.opacity(0.62))
                    .frame(width: 180, height: 180)
                    .offset(x: 110, y: -150)
                Ellipse()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: 420, height: 170)
                    .offset(x: -90, y: 220)
            }
        case .flat:
            Color(red: 0.42, green: 0.49, blue: 0.55)
        }
    }
}
