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
            let size = DesktopAssistantMetrics.size(for: density)
            content = AnyView(
                ZStack {
                    background
                    DesktopAssistantView(
                        cards: [DesktopAssistantCard(shared: shared, language: language)],
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
            let store = UsageStore(autoRefresh: false, previewOnly: true, language: language)
            let tuning = GlassTuning.final
            content = AnyView(ZStack {
                background
                UsagePanelView(
                    store: store,
                    tuning: tuning,
                    preferencesEnabled: false,
                    settingsInitiallyPresented: showsSettings
                )
            }
            .frame(width: UsagePanelMetrics.width, height: UsagePanelMetrics.height)
            .environment(\.colorScheme, isDark ? ColorScheme.dark : ColorScheme.light)
            )
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard
            let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw PreviewError.renderFailed
        }

        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }
}

private enum PreviewError: Error {
    case renderFailed
}
