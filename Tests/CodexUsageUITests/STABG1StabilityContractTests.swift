import AppKit
import CoreText
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("STAB-G1 typography, contour, layout, and resource contracts")
struct STABG1StabilityContractTests {
    @Test("Central typography preserves hierarchy and tabular value roles")
    func typographyRoles() {
        #expect(AppTypographyRole.display.size == 25)
        #expect(AppTypographyRole.sectionTitle.size == 15)
        #expect(AppTypographyRole.cardTitle.size == 13)
        #expect(AppTypographyRole.assistantProvider.size == 12)
        #expect(AppTypographyRole.assistantValue.size == 13)
        #expect(AppTypographyRole.assistantValue.weight == .medium)
        #expect(AppTypographyRole.assistantValue.usesTabularDigits)
        #expect(AppTypographyRole.regularValue.usesTabularDigits)
        #expect(AppTypographyRole.menuBarValue.usesTabularDigits)
        #expect(!AppTypographyRole.body.usesTabularDigits)
    }

    @Test("System typography has a package-safe Simplified Chinese cascade")
    func systemCJKFallback() throws {
        let baseFont = AppTypography.nsFont(.body)
        let base = CTFontCreateWithFontDescriptor(
            baseFont.fontDescriptor as CTFontDescriptor,
            baseFont.pointSize,
            nil
        )
        let fallback = CTFontCreateForString(
            base,
            "中文" as CFString,
            CFRange(location: 0, length: 2)
        )
        let fallbackName = CTFontCopyPostScriptName(fallback) as String

        #expect(!fallbackName.isEmpty)
        #expect(!fallbackName.localizedCaseInsensitiveContains("LastResort"))

        let designSystem = try source("Sources/CodexUsageUI/Support/DesignSystem.swift")
        #expect(!designSystem.contains("Font.custom"))
        #expect(!designSystem.contains("STHeitiSC"))
        #expect(!designSystem.contains("Roboto"))
        #expect(!designSystem.contains("\"Anthropic Sans\""))
        #expect(!designSystem.contains("Claude.app"))
    }

    @Test("Tabular menu digits have stable measured widths")
    func tabularDigitWidths() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: AppTypography.menuBarNSFont()
        ]
        let narrow = ("111%" as NSString).size(withAttributes: attributes).width
        let wide = ("888%" as NSString).size(withAttributes: attributes).width
        #expect(abs(narrow - wide) < 0.01)
    }

    @Test("Visible typography is centralized and no rounded-family drift remains")
    func typographySourceOwnership() throws {
        for path in [
            "Sources/CodexUsageUI/Views/UsagePanelView.swift",
            "Sources/CodexUsageUI/Views/UsageSettingsCard.swift",
            "Sources/CodexUsageUI/Views/CodexConnectionBridgeView.swift",
            "Sources/CodexUsageUI/Views/DesktopAssistantView.swift",
            "Sources/CodexUsageUI/Views/WorkBuddyMainPanelCard.swift"
        ] {
            let contents = try source(path)
            #expect(!contents.contains("UsageDesign.font"))
            #expect(!contents.contains("design: .rounded"))
            #expect(!contents.contains("STHeiti"))
            #expect(!contents.contains("Roboto"))
        }
    }

    @Test("Cards and the native host each have one contour owner")
    func contourOwnership() throws {
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let settings = try source("Sources/CodexUsageUI/Views/UsageSettingsCard.swift")
        let legacyWorkBuddy = try source(
            "Sources/CodexUsageUI/Views/WorkBuddyMainPanelCard.swift"
        )
        let host = try source(
            "Sources/CodexUsageMonitor/App/AdaptivePanelMaterialHostView.swift"
        )
        let controller = try source(
            "Sources/CodexUsageMonitor/App/QuickPanelPopoverController.swift"
        )
        let providerCard = try #require(
            panel.slice(
                from: "private struct LocalLiveProviderCard",
                to: "private struct UsagePanelContentHeightPreferenceKey"
            )
        )

        #expect(providerCard.occurrenceCount(of: "GlassCardBackground") == 1)
        #expect(!providerCard.contains(".fill(.thinMaterial)"))
        #expect(!providerCard.contains(".overlay {"))
        #expect(settings.occurrenceCount(of: "GlassCardBackground") == 1)
        #expect(!settings.contains(".fill(.regularMaterial)"))
        #expect(!settings.contains(".stroke(Color.white.opacity(0.28)"))
        #expect(legacyWorkBuddy.occurrenceCount(of: "GlassCardBackground") == 1)
        #expect(!legacyWorkBuddy.contains("usesIncreaseContrast"))
        #expect(host.contains("Owns the Quick Panel's only visible backing surface"))
        #expect(host.contains("layer.masksToBounds = true"))
        #expect(!host.contains("makeRoundedContentClipper"))
        #expect(host.contains("private func configureSurface()"))
        #expect(controller.contains("AdaptivePanelMaterialHostView exclusively owns"))
        #expect(controller.contains("panel.hasShadow = false"))
    }

    @Test("Settings exposes only one bounded native scroll container")
    func settingsScrollOwnership() throws {
        let panel = try source("Sources/CodexUsageUI/Views/UsagePanelView.swift")
        let settings = try source("Sources/CodexUsageUI/Views/UsageSettingsCard.swift")

        #expect(panel.contains("if isShowingSettings"))
        #expect(panel.contains("settingsBackdrop\n                    .frame(maxHeight: displayedHeight"))
        #expect(
            !panel.contains(
                "panelContent\n                    .opacity(0.14)"
            )
        )
        #expect(!settings.contains("ViewThatFits"))
        #expect(settings.occurrenceCount(of: "ScrollView(.vertical)") == 1)
        #expect(settings.contains("height: resolvedViewportHeight"))
        #expect(settings.contains("SettingsContentHeightPreferenceKey"))
        #expect(settings.contains("usage.settings.scroll"))
        #expect(settings.contains(".scrollBounceBehavior(.basedOnSize)"))
    }

    @Test("The panel begins at natural minimum height rather than the height cap")
    func initialPanelGeometry() throws {
        let controller = try source(
            "Sources/CodexUsageMonitor/App/QuickPanelPopoverController.swift"
        )
        #expect(controller.contains("minimumContentHeight: CGFloat = 72"))
        #expect(controller.contains("maximumContentHeight: CGFloat = 640"))
        #expect(controller.contains("updateContentSize(repositionIfVisible:"))
    }

    @MainActor
    @Test("Repeated Assistant selection routes to the canonical Agent workspace")
    func repeatedAssistantSelectionReusesPanelContent() throws {
        let controller = try source(
            "Sources/CodexUsageMonitor/App/AppShellCoordinator.swift"
        )
        #expect(controller.contains("assistantController.setSelectionHandler"))
        #expect(controller.contains("self?.showAgent(providerID)"))
        #expect(!controller.contains("showQuickPanel(expandingProviderID: providerID)"))
    }

    @Test("Local session file descriptors stay bounded and resumed sessions are promoted")
    func boundedSessionWatchSet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stab-watch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        var urls: [URL] = []
        for index in 0..<30 {
            let url = directory.appendingPathComponent(
                String(format: "session-%02d.jsonl", index)
            )
            try Data("{}".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
                ofItemAtPath: url.path
            )
            urls.append(url)
        }

        let initial = SessionMetadataScanner.watchableFileURLs(
            roots: [directory],
            fileManager: .default
        )
        #expect(initial.count == CodexLocalActivityObserver.maximumFileWatchCount)
        #expect(!initial.contains(urls[0]))

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: urls[0].path
        )
        let afterResume = SessionMetadataScanner.watchableFileURLs(
            roots: [directory],
            fileManager: .default
        )
        #expect(afterResume.count == CodexLocalActivityObserver.maximumFileWatchCount)
        #expect(afterResume.first == urls[0])
    }

    @Test("Assistant updates coalesce and unchanged cards do not rebuild content")
    func assistantRedrawOwnership() throws {
        let status = try source(
            "Sources/CodexUsageMonitor/App/StatusBarController.swift"
        )
        let assistant = try source(
            "Sources/CodexUsageMonitor/App/DesktopAssistantPanelController.swift"
        )

        // The status item no longer subscribes to the inventory and language
        // itself: it read the store back inside those sinks, which run before
        // the store holds the new values. It renders the store's reading
        // publisher, which is built from the values being published, adds the
        // user's arrangement and menu bar choice, and delivers a reading only
        // when it changes.
        let store = try source("Sources/CodexUsageUI/Stores/UsageStore.swift")
        #expect(status.contains("store.menuReadingPublisher"))
        #expect(store.contains("Publishers.CombineLatest4($productInventory, $agentOrder, $menuBarAgent, $language)"))
        #expect(store.contains(".removeDuplicates()"))
        #expect(status.contains("self?.updateStatusButton()"))
        #expect(!status.contains("store.objectWillChange"))
        #expect(assistant.contains("let cardsChanged = cards != self.cards"))
        #expect(assistant.contains("if cardsChanged || densityChanged"))
        #expect(assistant.contains("guard !panel.isVisible else { return }"))
        #expect(assistant.contains("guard !NSEqualRects(panel.frame, targetFrame)"))
    }

    @Test("Five display and frame repair simulations remain recoverable")
    func displayAndFrameRepairSimulations() {
        let cases: [(UInt32?, Double, Double, DesktopAssistantResolvedDensity, Int)] = [
            (1, 0.25, 0.75, .regular, 1),
            (2, -0.5, 1.5, .regular, 2),
            (nil, .nan, .infinity, .minimalist, 2),
            (3, 0, 0, .minimalist, 5),
            (4, 1, 1, .regular, 0),
        ]

        for (displayIdentifier, x, y, density, rowCount) in cases {
            let position = DesktopAssistantPosition(
                displayIdentifier: displayIdentifier,
                horizontalFraction: x,
                verticalFraction: y
            )
            let size = DesktopAssistantMetrics.stackSize(
                for: density,
                rowCount: rowCount
            )

            #expect(position.horizontalFraction.isFinite)
            #expect(position.verticalFraction.isFinite)
            #expect((0...1).contains(position.horizontalFraction))
            #expect((0...1).contains(position.verticalFraction))
            #expect(size.width > 0)
            #expect(size.height >= 0)
        }
    }

    @Test("UMA 0.11 manual-test packaging is commit-exact, allowlisted, and privacy-audited")
    func packageContract() throws {
        let relativePath = "script/package_uma_stability.sh"
        let url = repositoryRoot().appendingPathComponent(relativePath)
        let script = try source(relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)

        #expect(permissions.intValue & 0o111 != 0)
        #expect(script.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(script.contains("uma-0.11-manual-$short_commit/UMA.app"))
        #expect(script.contains("MARKETING_VERSION=\"0.11\""))
        #expect(script.contains("DEFAULT_BUILD=\"202607270002\""))
        #expect(script.contains("TypographyDecision"))
        #expect(script.contains("CLAUDE TYPOGRAPHY FALLBACK USED"))
        #expect(script.contains("Package file allowlist mismatch"))
        #expect(script.contains("manifest_sha256"))
        #expect(script.contains("Package contains a prohibited font, fixture, record, log, or evidence file"))
        #expect(script.contains("Package executable contains a non-system dependency"))
        #expect(!script.contains("git checkout"))
        #expect(!script.contains("git reset"))
        #expect(!script.contains("/Users/juliushe/Desktop/UMA_0.10.1.app"))
        #expect(!script.contains("/Users/juliushe/Desktop/UMA_0.11.app"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }

    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound..<endIndex)
        else { return nil }
        return String(self[startRange.lowerBound..<endRange.lowerBound])
    }
}
