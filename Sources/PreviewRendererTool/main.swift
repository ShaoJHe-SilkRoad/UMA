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
        if let recordPathArgument = arguments.first(where: {
            $0.hasPrefix("--write-workbuddy-record=")
        }) {
            let path = String(recordPathArgument.dropFirst("--write-workbuddy-record=".count))
            try writeWorkBuddyRecord(to: URL(fileURLWithPath: path))
            return
        }
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
            let size = DesktopAssistantMetrics.size(for: density)
            renderSize = size
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
            renderSize = CGSize(
                width: UsagePanelMetrics.width,
                height: UsagePanelMetrics.height
            )
            let workBuddyCard = try makeWorkBuddyCard(
                arguments: arguments,
                language: language
            )
            let store = UsageStore.preview(
                language: language,
                presentationCards: workBuddyCard.map { [$0] } ?? []
            )
            let tuning = GlassTuning.final
            content = AnyView(ZStack {
                background
                UsagePanelView(
                    store: store,
                    tuning: tuning,
                    preferencesEnabled: false,
                    settingsInitiallyPresented: showsSettings,
                    expandedProviderIDs: arguments.contains("--workbuddy-expanded")
                        ? ["workbuddy.manualAvailability"]
                        : [],
                    appearanceOverride: UsagePanelAppearanceOverride(
                        reduceTransparency: reduceTransparency,
                        increaseContrast: increaseContrast,
                        reduceMotion: arguments.contains("--reduce-motion")
                    )
                )
            }
            .frame(width: UsagePanelMetrics.width, height: UsagePanelMetrics.height)
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
        window.title = "UMA M2W-G3 Review Candidate"
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

    private static func makeWorkBuddyCard(
        arguments: [String],
        language: AppLanguage
    ) throws -> SharedUsageCardPresentation? {
        guard arguments.contains(where: { $0.hasPrefix("--workbuddy") }) else {
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
        } else {
            lifecycle = .configured
            let remaining: Int64
            if arguments.contains("--workbuddy-exhausted") {
                remaining = 0
            } else if arguments.contains("--workbuddy-critical") {
                remaining = 400
            } else if arguments.contains("--workbuddy-warning") {
                remaining = 1_000
            } else if arguments.contains("--workbuddy-absolute") {
                remaining = 50_000
            } else {
                remaining = 3_600
            }
            let used: Int64? = if arguments.contains("--workbuddy-absolute") {
                nil
            } else if arguments.contains("--workbuddy-exhausted") {
                4_000
            } else if arguments.contains("--workbuddy-critical") {
                3_600
            } else if arguments.contains("--workbuddy-warning") {
                3_000
            } else if arguments.contains("--workbuddy-total") {
                nil
            } else {
                400
            }
            let balance = try CreditBalance(
                validatingRemaining: remaining,
                used: used,
                total: arguments.contains("--workbuddy-absolute") ? nil : 4_000,
                scope: .buddyAISharedPersonal,
                planTier: .personal,
                nextExpiryAt: now.addingTimeInterval(86_400),
                observedAt: now,
                provenance: .manualConfirmed(at: now)
            )
            availability = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
                value: .credits(balance),
                language: language
            )
        }
        return SharedUsageCardPresentation(
            id: "workbuddy.manualAvailability",
            providerName: "WorkBuddy",
            planLabel: lifecycle == .configured
                ? WorkBuddyPlanTier.standard.rawValue
                : nil,
            connectionStatus: .disconnected,
            freshness: .unavailable,
            windows: [],
            selectedWindowID: nil,
            remaining: .unavailable,
            availability: availability,
            availabilityLifecycle: lifecycle,
            isVisibleInDesktopAssistant: false,
            severity: .neutral,
            capturedAt: now
        )
    }

    private static func writeWorkBuddyRecord(to url: URL) throws {
        let observedAt = Date()
        let balance = try CreditBalance(
            validatingRemaining: Int64(3_600),
            used: Int64(400),
            total: Int64(4_000),
            scope: .buddyAISharedPersonal,
            planTier: .personal,
            nextExpiryAt: observedAt.addingTimeInterval(86_400),
            observedAt: observedAt,
            provenance: .manualConfirmed(at: observedAt)
        )
        let observation = try WorkBuddyManualObservation(
            scope: .personalShared,
            tier: .standard,
            balance: balance
        )
        let record = WorkBuddyManualPersistenceRecord(
            enabled: true,
            observation: observation
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(record)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        for destination in [url, url.appendingPathExtension("backup")] {
            try data.write(to: destination, options: Data.WritingOptions.atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        }
    }
}

private enum PreviewError: Error {
    case renderFailed
}
