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
        if interactive || arguments.contains("--live-review") {
            NSApplication.shared.setActivationPolicy(.regular)
        }
        let outputPath = arguments.first(where: { !$0.hasPrefix("--") })
            ?? "work/codex-usage-panel-preview.png"
        let showsSettings = arguments.contains("--settings")
        let language: AppLanguage = arguments.contains("--english") ? .english : .simplifiedChinese
        let isDark = arguments.contains("--dark")
        let reduceTransparency = arguments.contains("--reduce-transparency")
        let increaseContrast = arguments.contains("--increase-contrast")
        let reduceMotion = arguments.contains("--reduce-motion")
        let renderScale: CGFloat
        if let scaleArgument = arguments.first(where: { $0.hasPrefix("--scale=") }) {
            guard let parsed = Double(scaleArgument.dropFirst("--scale=".count)),
                  parsed == 1 || parsed == 2
            else {
                throw PreviewError.invalidScenario
            }
            renderScale = CGFloat(parsed)
        } else {
            renderScale = 2
        }
        let rendersAlphaMask = arguments.contains("--alpha-mask")
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

        if arguments.contains("--sectorium") {
            #if DEBUG
            // Real production view, synthetic data only. This route never creates
            // the live usage store or starts storage observation/automation.
            let size = arguments.contains("--compact")
                ? CGSize(width: 760, height: 620)
                : CGSize(width: 1120, height: 820)
            let content = AnyView(
                VStack(spacing: 0) {
                    HStack {
                        Text("AUV · Sectorium").font(.headline)
                        Spacer()
                        Text(language == .english ? "Synthetic data · implemented UI" : "模拟数据 · 实际界面实现")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    Divider()
                    SectoriumWorkbenchView(store: .isolatedPreviewFixture(), isChinese: language != .english)
                }
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, isDark ? ColorScheme.dark : ColorScheme.light)
            )
            try renderM3RReview(.init(content: content, size: size), to: outputPath,
                               scale: renderScale, alphaMask: false, liveReview: false)
            return
            #else
            throw PreviewError.invalidScenario
            #endif
        }

        let compactFill = try CompactFillReviewFixture.parse(arguments)
        for provider in ["codex", "claude"] {
            let prefix = "--\(provider)-plan="
            let values = arguments.filter { $0.hasPrefix(prefix) }
            guard values.count <= 1,
                  values.allSatisfy({ ["pro", "plus", "max", "unknown"].contains(String($0.dropFirst(prefix.count)).lowercased()) })
            else { throw PreviewError.invalidScenario }
        }
        let creditFixtures = arguments.filter { $0.hasPrefix("--workbuddy-credits=") }
        guard creditFixtures.count <= 1,
              creditFixtures.allSatisfy({ ["499", "500", "501"].contains(String($0.dropFirst("--workbuddy-credits=".count))) })
        else { throw PreviewError.invalidScenario }
        if let reviewScenario = try M3RReviewScenario.parse(arguments) {
            guard compactFill == nil || reviewScenario.supportsCompactFillFixture else {
                throw PreviewError.invalidScenario
            }
            let review = makeM3RReview(
                scenario: reviewScenario,
                language: language,
                isDark: isDark,
                reduceTransparency: reduceTransparency,
                increaseContrast: increaseContrast,
                reduceMotion: reduceMotion,
                wallpaperStyle: wallpaperStyle,
                compactFill: compactFill,
                arguments: arguments
            )
            try renderM3RReview(
                review,
                to: outputPath,
                scale: renderScale,
                alphaMask: rendersAlphaMask,
                liveReview: arguments.contains("--live-review")
            )
            return
        }

        guard compactFill == nil else { throw PreviewError.invalidScenario }

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
            if arguments.contains("--assistant-antigravity") {
                sharedAssistantCards.append(
                    makeAntigravityCard(
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
            let antigravityCard = arguments.contains("--antigravity")
                ? makeAntigravityCard(
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
                + (antigravityCard.map { [$0] } ?? [])
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
            } else if arguments.contains("--antigravity-expanded") {
                expandedProviderIDs = ["antigravity.cli"]
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
            let antigravitySettings = arguments.contains("--antigravity")
                ? AntigravitySettingsModel(
                    initialState: .fresh(
                        Date(timeIntervalSince1970: 1_800_000_000)
                    ),
                    checkAgain: {
                        AntigravitySettingsObservation(
                            state: .fresh(
                                Date(timeIntervalSince1970: 1_800_000_000)
                            )
                        )
                    },
                    syncNow: {
                        AntigravitySettingsObservation(
                            state: .fresh(
                                Date(timeIntervalSince1970: 1_800_000_000)
                            )
                        )
                    },
                    disable: {}
                )
                : nil
            let panelHeight = measuredPanelHeight(
                store: store,
                tuning: tuning,
                showsSettings: showsSettings,
                settingsDestinationProviderID:
                    settingsDestinationProviderID,
                expandedProviderIDs: expandedProviderIDs,
                antigravitySettings: antigravitySettings,
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
                    antigravitySettings: antigravitySettings,
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

    private static func makeM3RReview(
        scenario: M3RReviewScenario,
        language: AppLanguage,
        isDark: Bool,
        reduceTransparency: Bool,
        increaseContrast: Bool,
        reduceMotion: Bool,
        wallpaperStyle: PreviewWallpaperStyle,
        compactFill: CompactFillReviewFixture?,
        arguments: [String]
    ) -> M3RReviewRender {
        let fixtureKind: M3RFixtureKind = switch scenario {
        case .quickOne:
            .one
        case .quickZero:
            .zero
        case .quickDegraded:
            .degraded
        default:
            .healthy
        }
        let fixture = makeM3RFixture(
            kind: fixtureKind, language: language, compactFill: compactFill, arguments: arguments
        )
        let appearance = isDark ? ColorScheme.dark : ColorScheme.light
        let reviewContent: AnyView
        let size: CGSize

        switch scenario {
        case .quick, .quickOne, .quickZero, .quickDegraded:
            let quickHeight: CGFloat = switch fixtureKind {
            case .zero:
                154
            case .one:
                130
            case .healthy, .degraded:
                196
            }
            size = CGSize(width: 320, height: quickHeight)
            reviewContent = AnyView(
                M3RQuickPanelReviewHost(
                    store: fixture.store,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast,
                    reduceMotion: reduceMotion
                )
                    .frame(width: size.width, height: size.height, alignment: .top)
            )
        case .quickEdge:
            size = CGSize(width: 520, height: 340)
            reviewContent = AnyView(
                ZStack {
                    PreviewWallpaper(style: wallpaperStyle)
                    M3RQuickPanelReviewHost(
                        store: fixture.store,
                        reduceTransparency: reduceTransparency,
                        increaseContrast: increaseContrast,
                        reduceMotion: reduceMotion
                    )
                        .frame(width: 320, height: 196, alignment: .top)
                }
            )
        case .compactRows:
            size = CGSize(width: 600, height: 240)
            reviewContent = AnyView(
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Panel row fixture")
                            .font(.headline)
                        ForEach(fixture.store.productInventory.agentWorkspaceProviders) { provider in
                            AgentGlanceRow(
                                provider: provider,
                                style: .quickPanel,
                                language: language,
                                referenceDate: M3RFixture.fixedNow
                            )
                        }
                    }
                    .frame(width: 300)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Main list row fixture")
                            .font(.headline)
                        ForEach(fixture.store.productInventory.agentWorkspaceProviders) { provider in
                            AgentGlanceRow(
                                provider: provider,
                                style: .mainList,
                                language: language,
                                // Mirrors the shipped rail in NativeShellViews.
                                showsReset: false,
                                referenceDate: M3RFixture.fixedNow
                            )
                        }
                    }
                    .frame(width: 235)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
            )
        case .main:
            size = CGSize(width: 860, height: 590)
            reviewContent = AnyView(
                M3RMainReviewSurface(
                    store: fixture.store,
                    selectedProviderID: .codex
                )
            )
        case .mainNarrow:
            size = CGSize(width: 760, height: 520)
            reviewContent = AnyView(
                M3RMainReviewSurface(
                    store: fixture.store,
                    selectedProviderID: .claude,
                    narrow: true
                )
            )
        case .workspaceCodex:
            size = CGSize(width: 640, height: 620)
            reviewContent = AnyView(
                M3RAgentWorkspaceReview(
                    store: fixture.store,
                    providerID: .codex
                )
            )
        case .workspaceClaude:
            size = CGSize(width: 640, height: 620)
            reviewContent = AnyView(
                M3RAgentWorkspaceReview(
                    store: fixture.store,
                    providerID: .claude
                )
            )
        case .settingsGeneral, .settingsAppearance, .settingsWizard, .settingsPrivacy:
            size = CGSize(width: 680, height: 500)
            let preferences = ApplicationPreferences.inMemory()
            preferences.set(
                language.rawValue,
                for: UMAApplicationPreferenceKeys.language
            )
            preferences.set(true, for: UMAApplicationPreferenceKeys.assistantEnabled)
            preferences.set(
                true,
                for: UMAApplicationPreferenceKeys.assistantAlwaysOnTop
            )
            preferences.set(
                DesktopAssistantDensity.regular.rawValue,
                for: UMAApplicationPreferenceKeys.assistantDensity
            )
            let pane: GlobalSettingsPane = switch scenario {
            case .settingsGeneral: .general
            case .settingsAppearance: .appearance
            case .settingsWizard: .desktopWizard
            case .settingsPrivacy: .privacy
            default: .general
            }
            reviewContent = AnyView(
                GlobalSettingsSurface(
                    preferences: preferences,
                    store: fixture.store,
                    navigation: GlobalSettingsNavigationState(pane: pane)
                )
                .background(Color(nsColor: .windowBackgroundColor))
            )
        case .wizardRegular, .wizardMinimalist, .wizardContextMenu,
             .wizardLogosRegular, .wizardLogosMinimalist:
            let density: DesktopAssistantResolvedDensity = scenario == .wizardMinimalist
                || scenario == .wizardLogosMinimalist
                ? .minimalist
                : .regular
            let cards = scenario == .wizardLogosRegular || scenario == .wizardLogosMinimalist
                ? makeWizardLogoFixture(language: language, compactFill: compactFill, arguments: arguments)
                : SharedUsagePresentationPolicy.assistantCards(from: fixture.cards).map {
                DesktopAssistantCard(
                    shared: $0,
                    language: language,
                    now: M3RFixture.fixedNow
                )
            }
            let wizardSize = DesktopAssistantMetrics.stackSize(
                for: density,
                rowCount: cards.count,
                valueTexts: cards.map { $0.usageText(for: density) }
            )
            if scenario == .wizardContextMenu {
                size = CGSize(width: 430, height: max(188, wizardSize.height + 48))
                reviewContent = AnyView(
                    ZStack {
                        PreviewWallpaper(style: wallpaperStyle)
                        HStack(alignment: .top, spacing: 14) {
                            DesktopAssistantView(
                                cards: cards,
                                density: density,
                                appearanceOverride: DesktopAssistantAppearanceOverride(
                                    reduceTransparency: reduceTransparency,
                                    increaseContrast: increaseContrast
                                )
                            )
                            M3RWizardContextMenuReview(language: language)
                        }
                    }
                )
            } else {
                size = wizardSize
                reviewContent = AnyView(
                    ZStack {
                        PreviewWallpaper(style: wallpaperStyle)
                        DesktopAssistantView(
                            cards: cards,
                            density: density,
                            appearanceOverride: DesktopAssistantAppearanceOverride(
                                reduceTransparency: reduceTransparency,
                                increaseContrast: increaseContrast
                            )
                        )
                    }
                )
            }
        case .threadOS:
            size = CGSize(width: 860, height: 590)
            reviewContent = AnyView(M3RThreadOSReviewSurface(language: language))
        }

        return M3RReviewRender(
            content: AnyView(
                reviewContent
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, appearance)
                    .environment(\.locale, language.locale)
                    .environment(\.dynamicTypeSize, arguments.contains("--large-text") ? .accessibility1 : .medium)
            ),
            size: size
        )
    }

    private static func fixturePlan(_ arguments: [String], provider: String, fallback: String) -> String {
        let prefix = "--\(provider)-plan="
        return arguments.first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)).uppercased() } ?? fallback
    }

    // Render-only identity fixtures. WorkBuddy never enters ProviderProductInventory.
    private static func makeWizardLogoFixture(
        language: AppLanguage,
        compactFill: CompactFillReviewFixture?,
        arguments: [String]
    ) -> [DesktopAssistantCard] {
        let shared = makeM3RFixture(
            kind: .healthy, language: language,
            compactFill: compactFill ?? .percent(77), arguments: arguments
        ).cards
        var cards = shared.map {
            DesktopAssistantCard(shared: $0, language: language, now: M3RFixture.fixedNow)
        }
        let credits = arguments.first(where: { $0.hasPrefix("--workbuddy-credits=") })
            .flatMap { Int($0.dropFirst("--workbuddy-credits=".count)) }
        cards.append(DesktopAssistantCard(
            id: "workbuddy.logoPreview",
            providerName: "WorkBuddy",
            connectionState: .unavailable,
            selectedWindowShortLabel: "",
            selectedWindowAccessibilityLabel: "Synthetic credits, dormant provider; no runtime connection",
            usageValue: credits.map { .credits(String($0)) } ?? .unavailable,
            availableCredits: credits.map { Decimal($0) },
            severity: .neutral,
            isStale: false,
            language: language
        ))
        return cards
    }

    private static func makeM3RFixture(
        kind: M3RFixtureKind,
        language: AppLanguage,
        compactFill: CompactFillReviewFixture?,
        arguments: [String]
    ) -> M3RFixture {
        let cards: [SharedUsageCardPresentation]
        if let compactFill {
            let unavailable = compactFill == .unavailable
            let percent = compactFill.remainingPercent ?? 0
            cards = [
                makeCodexCard(
                    arguments: arguments + (unavailable ? ["--unavailable"] : (compactFill == .infinity ? ["--unlimited"] : [])),
                    language: language,
                    percent: percent,
                    scenario: .ready
                ),
                makeM3RClaudeCard(
                    language: language,
                    fiveHourPercent: percent,
                    sevenDayPercent: percent,
                    estimated: true,
                    freshness: .fresh,
                    connection: .connected,
                    unavailable: unavailable,
                    unlimited: compactFill == .infinity,
                    planLabel: fixturePlan(arguments, provider: "claude", fallback: "PRO")
                ),
            ]
        } else {
            switch kind {
            case .healthy:
                cards = [
                    makeCodexCard(
                        arguments: [],
                        language: language,
                        percent: 64,
                        scenario: .ready
                    ),
                    makeM3RClaudeCard(
                        language: language,
                        fiveHourPercent: 24,
                        sevenDayPercent: 71,
                        estimated: true,
                        freshness: .fresh,
                        connection: .connected
                    ),
                ]
            case .one:
                cards = [
                    makeCodexCard(
                        arguments: [],
                        language: language,
                        percent: 64,
                        scenario: .ready
                    ),
                ]
            case .zero:
                cards = []
            case .degraded:
                cards = [
                    makeCodexCard(
                        arguments: ["--stale"],
                        language: language,
                        percent: 27,
                        scenario: .stale
                    ),
                    makeM3RClaudeCard(
                        language: language,
                        fiveHourPercent: 8,
                        sevenDayPercent: 43,
                        estimated: true,
                        freshness: .cached,
                        connection: .connected
                    ),
                ]
            }
        }
        return M3RFixture(
            store: UsageStore.preview(
                scenario: .ready,
                language: language,
                presentationCards: cards
            ),
            cards: cards
        )
    }

    private static func makeM3RClaudeCard(
        language: AppLanguage,
        fiveHourPercent: Double,
        sevenDayPercent: Double,
        estimated: Bool,
        freshness: SharedUsageFreshness,
        connection: SharedConnectionStatus,
        unavailable: Bool = false,
        unlimited: Bool = false,
        planLabel: String = "LOCAL SMART"
    ) -> SharedUsageCardPresentation {
        let fiveHour = SharedUsageWindowPresentation(
            id: "claude-five-hour",
            kind: .fiveHour,
            compactLabel: "5H",
            accessibilityLabel: language == .english
                ? "five-hour window"
                : "五小时额度窗口",
            remaining: unavailable ? .unavailable : (unlimited ? .unlimited : .finite(fiveHourPercent)),
            isEstimated: estimated,
            resetsAt: M3RFixture.fixedNow.addingTimeInterval(7_200),
            resetText: language == .english ? "Resets in 2 hr" : "2 小时后重置"
        )
        let sevenDay = SharedUsageWindowPresentation(
            id: "claude-seven-day",
            kind: .sevenDay,
            compactLabel: "7D",
            accessibilityLabel: language == .english
                ? "seven-day window"
                : "七天额度窗口",
            remaining: unavailable ? .unavailable : (unlimited ? .unlimited : .finite(sevenDayPercent)),
            isEstimated: estimated,
            resetsAt: M3RFixture.fixedNow.addingTimeInterval(172_800),
            resetText: language == .english ? "Resets in 2 days" : "2 天后重置"
        )
        let selected = fiveHourPercent <= sevenDayPercent ? fiveHour : sevenDay
        return SharedUsageCardPresentation(
            id: "claude.browserSync",
            providerName: "Claude",
            planLabel: planLabel,
            connectionStatus: connection,
            freshness: freshness,
            windows: [fiveHour, sevenDay],
            selectedWindowID: selected.id,
            remaining: selected.remaining,
            isEstimated: estimated,
            sourceDescription: language == .english
                ? "Local Smart estimate · sanitized usage metadata"
                : "本地智能估算 · 脱敏用量元数据",
            isVisibleInDesktopAssistant: true,
            severity: freshness == .fresh
                ? SharedUsagePresentationPolicy.severity(for: selected.remaining)
                : .neutral,
            isRetainingLastValidValue: freshness != .fresh,
            capturedAt: M3RFixture.fixedNow
        )
    }

    private static func renderM3RReview(
        _ review: M3RReviewRender,
        to outputPath: String,
        scale: CGFloat,
        alphaMask: Bool,
        liveReview: Bool
    ) throws {
        let host = NSHostingView(rootView: review.content)
        host.frame = CGRect(origin: .zero, size: review.size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(review.size.width * scale),
            pixelsHigh: Int(review.size.height * scale),
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
        bitmap.size = review.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        window.orderOut(nil)
        let outputBitmap = alphaMask ? try makeAlphaMask(from: bitmap) : bitmap
        guard let png = outputBitmap.representation(using: .png, properties: [:]) else {
            throw PreviewError.renderFailed
        }
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: outputURL, options: .atomic)
        if liveReview {
            let closeDelegate = SyntheticReviewWindowDelegate()
            window.delegate = closeDelegate
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = "UMA synthetic component review — no provider connections"
            window.setFrameOrigin(NSPoint(x: 180, y: 180))
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            withExtendedLifetime(closeDelegate) {
                NSApplication.shared.run()
            }
        }
    }

    private static func makeAlphaMask(from source: NSBitmapImageRep) throws -> NSBitmapImageRep {
        guard let sourceData = source.bitmapData,
              let mask = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: source.pixelsWide,
                pixelsHigh: source.pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let maskData = mask.bitmapData
        else {
            throw PreviewError.renderFailed
        }

        var minimumAlpha = UInt8.max
        var maximumAlpha = UInt8.min
        for y in 0..<source.pixelsHigh {
            for x in 0..<source.pixelsWide {
                let sourceOffset = y * source.bytesPerRow + x * 4
                let maskOffset = y * mask.bytesPerRow + x * 4
                let alpha = sourceData[sourceOffset + 3]
                minimumAlpha = min(minimumAlpha, alpha)
                maximumAlpha = max(maximumAlpha, alpha)
                maskData[maskOffset] = alpha
                maskData[maskOffset + 1] = alpha
                maskData[maskOffset + 2] = alpha
                maskData[maskOffset + 3] = 255
            }
        }
        // A single approved soft system-style shadow may contribute a very low
        // corner alpha. Reject opaque rectangular backing while preserving it.
        guard minimumAlpha <= 16, maximumAlpha == 255 else {
            throw PreviewError.renderFailed
        }
        mask.size = source.size
        return mask
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
            resetsAt: M3RFixture.fixedNow.addingTimeInterval(7_200),
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
            planLabel: fixturePlan(arguments, provider: "codex", fallback: "PRO"),
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
        antigravitySettings: AntigravitySettingsModel?,
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
                antigravitySettings: antigravitySettings,
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

    private static func makeAntigravityCard(
        arguments: [String],
        language: AppLanguage
    ) -> SharedUsageCardPresentation {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let isFailed = arguments.contains("--antigravity-failed")
        let isCached = arguments.contains("--antigravity-cached")
        let isStale = arguments.contains("--antigravity-stale") || isFailed
        let primary = SharedUsageWindowPresentation(
            id: "antigravity-primary",
            kind: .other,
            compactLabel: language == .english ? "Primary" : "主要额度",
            accessibilityLabel: language == .english
                ? "Primary usage window"
                : "主要额度窗口",
            remaining: .finite(58),
            resetsAt: arguments.contains("--antigravity-missing-reset")
                ? nil
                : now.addingTimeInterval(7_200),
            resetText: arguments.contains("--antigravity-missing-reset")
                ? (language == .english ? "Reset unavailable" : "重置时间不可用")
                : (language == .english ? "Resets in 2 hr" : "2 小时后重置")
        )
        let secondary = SharedUsageWindowPresentation(
            id: "antigravity-secondary",
            kind: .other,
            compactLabel: language == .english ? "Secondary" : "次要额度",
            accessibilityLabel: language == .english
                ? "Secondary usage window"
                : "次要额度窗口",
            remaining: .finite(76),
            resetsAt: now.addingTimeInterval(86_400),
            resetText: language == .english ? "Resets in 1 day" : "1 天后重置"
        )
        let selected = arguments.contains("--antigravity-select-secondary")
            ? secondary
            : primary
        return SharedUsageCardPresentation(
            id: "antigravity.cli",
            providerName: "Google Antigravity",
            connectionStatus: isFailed
                ? .failed
                : (isStale ? .stale : .connected),
            freshness: isCached ? .cached : (isStale ? .stale : .fresh),
            windows: [primary, secondary],
            selectedWindowID: selected.id,
            remaining: selected.remaining,
            sourceDescription: language == .english
                ? "Official Antigravity CLI · read-only /usage"
                : "Antigravity 官方 CLI · 只读 /usage",
            isVisibleInDesktopAssistant: true,
            severity: isCached || isStale
                ? .neutral
                : SharedUsagePresentationPolicy.severity(
                    for: selected.remaining
                ),
            isRetainingLastValidValue: isCached || isStale,
            capturedAt: now
        )
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

private struct M3RReviewRender {
    let content: AnyView
    let size: CGSize
}

private enum M3RReviewScenario: String {
    case quick
    case quickOne = "quick-one"
    case quickZero = "quick-zero"
    case quickDegraded = "quick-degraded"
    case quickEdge = "quick-edge"
    case main
    case compactRows = "compact-rows"
    case mainNarrow = "main-narrow"
    case workspaceCodex = "workspace-codex"
    case workspaceClaude = "workspace-claude"
    case settingsGeneral = "settings"
    case settingsAppearance = "settings-appearance"
    case settingsWizard = "settings-wizard"
    case settingsPrivacy = "settings-privacy"
    case wizardRegular = "wizard-regular"
    case wizardMinimalist = "wizard-minimalist"
    case wizardContextMenu = "wizard-context-menu"
    case wizardLogosRegular = "wizard-logos-regular"
    case wizardLogosMinimalist = "wizard-logos-minimalist"
    case threadOS = "threados"

    var supportsCompactFillFixture: Bool {
        switch self {
        case .quick, .quickEdge, .main, .mainNarrow, .compactRows, .wizardRegular, .wizardMinimalist,
             .wizardLogosRegular, .wizardLogosMinimalist, .workspaceCodex, .workspaceClaude:
            true
        default:
            false
        }
    }

    static func parse(_ arguments: [String]) throws -> Self? {
        guard let argument = arguments.first(where: {
            $0.hasPrefix("--m3r-review=")
        }) else {
            return nil
        }
        let rawValue = String(argument.dropFirst("--m3r-review=".count))
        guard let scenario = Self(rawValue: rawValue) else {
            throw PreviewError.invalidScenario
        }
        return scenario
    }
}

private enum CompactFillReviewFixture: Equatable {
    case percent(Double)
    case unavailable
    case infinity

    var remainingPercent: Double? {
        guard case let .percent(value) = self else { return nil }
        return value
    }

    static func parse(_ arguments: [String]) throws -> Self? {
        let values = arguments.filter { $0.hasPrefix("--compact-fill-percent=") }
        let unavailable = arguments.filter { $0 == "--compact-fill-unavailable" }
        let infinity = arguments.filter { $0 == "--compact-fill-infinity" }
        guard values.count + unavailable.count + infinity.count <= 1 else {
            throw PreviewError.invalidScenario
        }
        if !unavailable.isEmpty { return .unavailable }
        if !infinity.isEmpty { return .infinity }
        guard let argument = values.first else { return nil }
        guard let value = Double(argument.dropFirst("--compact-fill-percent=".count)),
              value.isFinite, (0...100).contains(value)
        else {
            throw PreviewError.invalidScenario
        }
        return .percent(value)
    }
}

private enum M3RFixtureKind: Equatable {
    case healthy
    case one
    case zero
    case degraded
}

@MainActor
private struct M3RFixture {
    static let fixedNow = Date(timeIntervalSince1970: 1_788_393_600)
    let store: UsageStore
    let cards: [SharedUsageCardPresentation]
}

private struct M3RWizardContextMenuReview: View {
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuItem(localized("Hide Desktop Wizard", "隐藏桌面向导"))
            menuItem(localized("Enabled", "已启用"), checked: true)
            menuItem(localized("Always on Top", "始终置顶"), checked: true)
            Divider().padding(.vertical, 4)
            menuItem(localized("Density", "密度"), trailing: "›")
            Divider().padding(.vertical, 4)
            menuItem(localized("Automatic", "自动"), checked: true)
            menuItem(localized("Regular", "常规"))
            menuItem(localized("Minimalist", "极简"))
        }
        .padding(6)
        .frame(width: 186)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
        .accessibilityIdentifier("uma.review.desktop-wizard-context-menu")
    }

    private func menuItem(
        _ title: String,
        checked: Bool = false,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(checked ? "✓" : "")
                .frame(width: 12, alignment: .center)
            Text(title)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
            }
        }
        .font(.system(size: 13))
        .frame(height: 22)
        .padding(.horizontal, 5)
        .accessibilityLabel(title)
        .accessibilityValue(checked ? localized("On", "开启") : "")
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}

private struct M3RQuickPanelReviewHost: View {
    @ObservedObject var store: UsageStore
    private let preferences = ApplicationPreferences.inMemory()
    let reduceTransparency: Bool
    let increaseContrast: Bool
    let reduceMotion: Bool

    var body: some View {
        QuickPanelSurface(
            store: store,
            preferences: preferences,
            openMain: {},
            scanAll: {},
            refreshAll: {},
            toggleWizard: {},
            openSettings: {},
            selectAgent: { _ in },
            referenceDate: M3RFixture.fixedNow
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if increaseContrast {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.32), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.20), radius: 16, y: 7)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .accessibilityIdentifier("uma.review.quick-panel-host")
    }
}

private struct M3RAgentWorkspaceReview: View {
    @ObservedObject var store: UsageStore
    let providerID: ProviderProductID

    var body: some View {
        AgentWorkspaceSurface(
            store: store,
            providerID: providerID,
            refresh: {},
            connectCodex: {},
            disconnectCodex: {},
            claudeControlState: { .onlineVerificationUnavailable },
            connectClaude: {},
            claudeAccuracySync: {},
            referenceDate: M3RFixture.fixedNow
        )
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct M3RMainReviewSurface: View {
    @ObservedObject var store: UsageStore
    let selectedProviderID: ProviderProductID
    var narrow = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                agentList
                    .frame(
                        minWidth: narrow ? 205 : 220,
                        idealWidth: narrow ? 215 : 235,
                        maxWidth: narrow ? 220 : 260
                    )
                M3RAgentWorkspaceReview(
                    store: store,
                    providerID: selectedProviderID
                )
                .frame(minWidth: 500)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("uma.review.main-two-column")
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker(
                localized("Destination", "导航"),
                selection: .constant(0)
            ) {
                Text(localized("Agents & Settings", "智能体与设置")).tag(0)
                Text("ThreadOS").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
            Spacer()
            toolbarButton(localized("Scan All", "全部扫描"), "sparkle.magnifyingglass")
            toolbarButton(localized("Refresh All", "全部刷新"), "arrow.clockwise")
            toolbarButton(localized("Global Settings", "全局设置"), "gearshape")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var agentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("Agents", "智能体"))
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.top, 12)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.productInventory.agentWorkspaceProviders) { provider in
                        AgentGlanceRow(
                            provider: provider,
                            style: .mainList,
                            selected: provider.id == selectedProviderID,
                            language: store.language,
                            // Mirrors the shipped rail in NativeShellViews.
                            showsReset: false,
                            referenceDate: M3RFixture.fixedNow
                        )
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func toolbarButton(_ label: String, _ symbol: String) -> some View {
        Button(action: {}) { Image(systemName: symbol) }
            .help(label)
            .accessibilityLabel(label)
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        store.language == .simplifiedChinese ? chinese : english
    }
}

private struct M3RThreadOSReviewSurface: View {
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Destination", selection: .constant(1)) {
                    Text(localized("Agents & Settings", "智能体与设置")).tag(0)
                    Text("ThreadOS").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 250)
                Spacer()
                Button(action: {}) { Image(systemName: "gearshape") }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            Divider()
            ContentUnavailableView(
                "ThreadOS",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text(localized(
                    "Reserved for a future release.",
                    "为未来版本预留。"
                ))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("uma.threados.inert")
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
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

// This window hosts synthetic views only. Closing it terminates its dedicated renderer.
@MainActor
private final class SyntheticReviewWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }
}
