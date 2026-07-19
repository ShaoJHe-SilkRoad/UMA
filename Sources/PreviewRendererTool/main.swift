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
        let showsMoreInfo = arguments.contains("--expanded")
        let usesDarkAppearance = arguments.contains("--dark")
        let language: AppLanguage = arguments.contains("--english") ? .english : .simplifiedChinese
        let scenario = arguments
            .compactMap { argument -> CodexPreviewScenario? in
                guard argument.hasPrefix("--scenario=") else { return nil }
                return CodexPreviewScenario(
                    rawValue: String(argument.dropFirst("--scenario=".count))
                )
            }
            .first ?? .ready
        let store = UsageStore.preview(scenario: scenario, language: language)
        let tuning = GlassTuning.final
        let content = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.72, green: 0.84, blue: 0.96),
                    Color(red: 0.34, green: 0.45, blue: 0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            UsagePanelView(
                store: store,
                tuning: tuning,
                preferencesEnabled: false,
                settingsInitiallyPresented: showsSettings,
                moreInfoInitiallyPresented: showsMoreInfo
            )
        }
        .environment(\.colorScheme, usesDarkAppearance ? .dark : .light)
        .frame(
            width: UsagePanelMetrics.width,
            height: showsMoreInfo
                ? UsagePanelMetrics.height
                : (showsSettings ? UsagePanelMetrics.settingsMinimumHeight : UsagePanelMetrics.collapsedHeight)
        )
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
