import AppKit
import CodexUsageUI
import Foundation
import SwiftUI

@main
@MainActor
struct PreviewRendererTool {
    static func main() async throws {
        _ = NSApplication.shared

        let arguments = Array(CommandLine.arguments.dropFirst())
        let interactive = arguments.contains("--interactive")
        let outputPath = arguments.first(where: { !$0.hasPrefix("--") })
            ?? "work/codex-usage-panel-preview.png"
        let showsSettings = arguments.contains("--settings")
        let language: AppLanguage = arguments.contains("--english") ? .english : .simplifiedChinese
        let isDark = arguments.contains("--dark")
        let reduceTransparency = arguments.contains("--reduce-transparency")
        let increaseContrast = arguments.contains("--increase-contrast")
        let background = LinearGradient(
            colors: [
                Color(red: 0.72, green: 0.84, blue: 0.96),
                Color(red: 0.34, green: 0.45, blue: 0.58)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let content: AnyView
        let renderSize: CGSize
        if arguments.contains("--assistant-regular")
            || arguments.contains("--assistant-minimalist") {
            let density: DesktopAssistantResolvedDensity = arguments.contains("--assistant-minimalist")
                ? .minimalist
                : .regular
            let percent = arguments
                .first(where: { $0.hasPrefix("--percent=") })
                .flatMap { Double($0.dropFirst("--percent=".count)) }
                ?? 44
            let remaining: SharedRemainingValue
            if arguments.contains("--unlimited") {
                remaining = .unlimited
            } else if arguments.contains("--unavailable") {
                remaining = .unavailable
            } else {
                remaining = .finite(min(100, max(0, percent)))
            }
            let window = SharedUsageWindowPresentation(
                id: "seven-day",
                kind: .sevenDay,
                compactLabel: "7D",
                accessibilityLabel: language == .english ? "seven-day window" : "七天额度窗口",
                remaining: remaining,
                resetsAt: Date().addingTimeInterval(7_200),
                resetText: language == .english ? "Resets in 2 hr" : "2 小时后重置"
            )
            let shared = SharedUsageCardPresentation(
                id: "codex.local",
                providerName: "Codex",
                planLabel: "PRO",
                connectionStatus: arguments.contains("--failed")
                    ? .failed
                    : (arguments.contains("--stale") ? .stale : .connected),
                freshness: arguments.contains("--stale") ? .stale : .fresh,
                windows: [window],
                selectedWindowID: window.id,
                remaining: remaining,
                severity: SharedUsagePresentationPolicy.severity(for: remaining),
                isRetainingLastValidValue: arguments.contains("--stale")
            )
            let workBuddyCard = try makeWorkBuddyCard(
                arguments: arguments,
                language: language
            )
            var assistantCards: [DesktopAssistantCard] = []
            if !arguments.contains("--assistant-workbuddy-only") {
                assistantCards.append(
                    DesktopAssistantCard(shared: shared, language: language)
                )
            }
            if let workBuddyCard {
                assistantCards.append(
                    DesktopAssistantCard(shared: workBuddyCard, language: language)
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
            )
        } else {
            let workBuddyCard = try makeWorkBuddyCard(
                arguments: arguments,
                language: language
            )
            let previewScenario = try codexPreviewScenario(arguments)
            let store = UsageStore.preview(
                scenario: previewScenario,
                language: language,
                presentationCards: workBuddyCard.map { [$0] } ?? [],
                chineseLoginProviderName: arguments.contains(
                    "--chinese-login-option"
                ) ? "Kimi" : nil
            )
            let tuning = GlassTuning.final
            let expandedProviderIDs: Set<String> = arguments.contains("--workbuddy-expanded")
                ? [
                    arguments.contains("--workbuddy-account-web")
                        ? "workbuddy.accountWebCredits"
                        : "workbuddy.manualAvailability"
                ]
                : []
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
            ) ? WorkBuddyAccountWebSessionController() : nil
            let workBuddySettings = workBuddyLogin != nil || accountWebSync != nil
                ? WorkBuddySettingsModel.preview()
                : nil
            let panelHeight = measuredPanelHeight(
                store: store,
                tuning: tuning,
                showsSettings: showsSettings,
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
                    expandedProviderIDs: expandedProviderIDs,
                    workBuddySettings: workBuddySettings,
                    workBuddyLogin: workBuddyLogin,
                    workBuddyAccountWebSync: accountWebSync,
                    appearanceOverride: appearanceOverride,
                    renderedHeightOverride: panelHeight,
                    cardVisibilityOverride: cardVisibilityOverride
                )
            }
            .frame(width: UsagePanelMetrics.width, height: panelHeight)
            .environment(\.colorScheme, isDark ? ColorScheme.dark : ColorScheme.light)
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
        window.title = "UMA M2WACCOUNT-G1 Review Candidate"
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        if interactive {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.run()
            return
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

        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
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

    private static func measuredPanelHeight(
        store: UsageStore,
        tuning: GlassTuning,
        showsSettings: Bool,
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
                    validatingDecimalRemaining: Decimal(string: "2099.47")!,
                    used: Decimal(100),
                    total: Decimal(string: "2199.47")!,
                    scope: .buddyAIUnknown,
                    observedAt: now,
                    provenance: .authenticatedAccountWeb(observedAt: now)
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
            providerName: "WorkBuddy",
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
            availabilityLifecycle: isAccountWeb ? nil : lifecycle,
            isVisibleInDesktopAssistant: true,
            severity: .neutral,
            capturedAt: now
        )
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
