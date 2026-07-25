import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M2WDBG-R1 real-data and visual parity repair")
struct M2WDBGR1RepairTests {
    @Test
    func productionDefaultsAndR1ReviewStoreRemainSeparated() throws {
        let fileManager = FileManager.default
        let parent = temporaryDirectory("store-isolation")
        defer { try? fileManager.removeItem(at: parent) }
        let debugRoot = parent.appendingPathComponent("uma-m2wdbg-runtime")
        let reviewRoot = parent.appendingPathComponent("uma-m2wdbg-r1-runtime")
        try fileManager.createDirectory(
            at: debugRoot,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: reviewRoot,
            withIntermediateDirectories: true
        )
        let manual = reviewRoot.appendingPathComponent("manual.json")

        let production = try UsageMonitorRuntime.storeConfiguration(
            bundleIdentifier: "com.kevinchen.CodexUsageMonitor",
            environment: [
                "HOME": "/private/tmp/isolated-home",
                "UMA_M2WDBG_MANUAL_STORE":
                    debugRoot.appendingPathComponent("synthetic.json").path,
                "UMA_M2WDBG_SNAPSHOT_STORE":
                    debugRoot.appendingPathComponent("snapshots.json").path
            ],
            m2wdbgAllowedRoot: debugRoot,
            r1AllowedRoot: reviewRoot
        )
        #expect(production.workBuddyStoreURL == nil)
        #expect(production.snapshotStoreURL == nil)

        let review = try UsageMonitorRuntime.storeConfiguration(
            bundleIdentifier: "com.kevinchen.CodexUsageMonitor",
            environment: [
                "HOME": "/private/tmp/isolated-home",
                "UMA_M2WDBG_R1_MANUAL_STORE": manual.path
            ],
            m2wdbgAllowedRoot: debugRoot,
            r1AllowedRoot: reviewRoot
        )
        #expect(review.workBuddyStoreURL?.path == canonicalPath(manual.path))
        #expect(review.snapshotStoreURL == nil)

        let runtimeSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
            ),
            encoding: .utf8
        )
        #expect(runtimeSource.contains("consentDefaults: .standard"))
    }

    @Test
    func invalidR1OverrideFailsClosed() throws {
        let parent = temporaryDirectory("invalid-review-store")
        defer { try? FileManager.default.removeItem(at: parent) }
        let debugRoot = parent.appendingPathComponent("debug")
        let reviewRoot = parent.appendingPathComponent("review")
        try FileManager.default.createDirectory(
            at: debugRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: reviewRoot,
            withIntermediateDirectories: true
        )

        #expect(throws: UsageMonitorRuntimeError.self) {
            _ = try UsageMonitorRuntime.storeConfiguration(
                bundleIdentifier: "com.kevinchen.CodexUsageMonitor",
                environment: [
                    "UMA_M2WDBG_R1_MANUAL_STORE":
                        parent.appendingPathComponent("outside.json").path
                ],
                m2wdbgAllowedRoot: debugRoot,
                r1AllowedRoot: reviewRoot
            )
        }

        for bundleIdentifier in [
            nil,
            "com.kevinchen.CodexUsageMonitor.unexpected",
        ] {
            #expect(throws: UsageMonitorRuntimeError.self) {
                _ = try UsageMonitorRuntime.storeConfiguration(
                    bundleIdentifier: bundleIdentifier,
                    environment: [
                        "UMA_M2WDBG_R1_MANUAL_STORE":
                            reviewRoot.appendingPathComponent("manual.json").path
                    ],
                    m2wdbgAllowedRoot: debugRoot,
                    r1AllowedRoot: reviewRoot
                )
            }
        }
    }

    @Test
    func absentManualRecordStartsUnconfiguredAndEmpty() async {
        let directory = temporaryDirectory("absent-record")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ManualWorkBuddyAvailabilitySource(
            store: WorkBuddyManualAvailabilityStore(
                fileURL: directory.appendingPathComponent("manual.json")
            )
        )

        let state = await source.load()
        #expect(state.lifecycle == .unconfigured)
        #expect(!state.enabled)
        #expect(state.observation == nil)
        #expect(WorkBuddyManualDraft().remainingText.isEmpty)
        #expect(WorkBuddyManualDraft().companionText.isEmpty)
        #expect(WorkBuddyManualDraft().explicitTotalText.isEmpty)
    }

    @Test @MainActor
    func experienceSuggestionRequiresExplicitActionAndNeverPublishes() async {
        let directory = temporaryDirectory("tier-suggestion")
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WorkBuddyManualAvailabilityStore(
            fileURL: directory.appendingPathComponent("manual.json")
        )
        let source = ManualWorkBuddyAvailabilitySource(store: persistence)
        let model = WorkBuddySettingsModel(source: source)
        model.draft = WorkBuddyManualDraft(
            tier: .standard,
            remainingText: "25",
            companionField: .total,
            companionText: "100"
        )

        model.draft.tier = .experience
        #expect(model.draft.remainingText == "25")
        #expect(model.draft.companionText == "100")
        #expect(model.savedObservation == nil)
        #expect(await persistence.writeCount == 0)
        #expect(await source.publicationCount == 0)

        model.applySelectedTierSuggestion()
        #expect(model.draft.remainingText == "25")
        #expect(model.draft.companionField == .total)
        #expect(model.draft.companionText == "500")
        #expect(model.savedObservation == nil)
        #expect(await persistence.writeCount == 0)
        #expect(await source.publicationCount == 0)
    }

    @Test
    func founderExperienceRecordPresentsExactlyFiveHundred() throws {
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let observation = try WorkBuddyManualDraft(
            scope: .personalShared,
            tier: .experience,
            remainingText: "500",
            companionField: .used,
            companionText: "0"
        ).validated(at: confirmedAt)
        #expect(observation.balance.remaining == 500)
        #expect(observation.balance.used == 0)
        #expect(observation.balance.total == 500)
        #expect(observation.balance.normalizedRemainingFraction == 1)
        #expect(observation.balance.provenance == .manualConfirmed(at: confirmedAt))

        let availability = SharedUsagePresentationPolicy.makeAvailabilityPresentation(
            value: .credits(observation.balance),
            language: .english
        )
        let card = SharedUsageCardPresentation(
            id: WorkBuddyManualPersistenceRecord.connectorID,
            providerName: "WorkBuddy",
            planLabel: observation.tier.rawValue,
            connectionStatus: .disconnected,
            freshness: .unavailable,
            windows: [],
            selectedWindowID: nil,
            remaining: .unavailable,
            availability: availability,
            availabilityLifecycle: .configured,
            isVisibleInDesktopAssistant: true,
            severity: .neutral,
            capturedAt: confirmedAt
        )
        let presentation = try #require(
            WorkBuddyMainPanelPresentation.make(
                card: card,
                language: .english,
                now: confirmedAt
            )
        )
        #expect(presentation.compactValue == "500")
        #expect(presentation.availableText == "500 Credits available")
        #expect(presentation.balanceDetail == "0 used of 500 active")
        #expect(presentation.remainingFraction == 1)
        #expect(presentation.severity == .available)
        #expect(presentation.manualStatus.contains("Manual snapshot"))
        #expect(presentation.tierText == "Experience")
        #expect(presentation.scopeTitle == "Buddy AI shared Credits")
        #expect(!presentation.accessibilityLabel.contains("3,600"))
        #expect(card.isVisibleInDesktopAssistant)
    }

    @Test
    func panelResolvesNaturalHeightWithoutFixedSignInAllocation() throws {
        #expect(UsagePanelMetrics.width == 370)
        #expect(UsagePanelMetrics.height == 776)
        #expect(UsagePanelMetrics.minimumHeight == 135)
        #expect(UsagePanelMetrics.outerHorizontalInset == 16)
        #expect(UsagePanelMetrics.outerTopInset == 14)
        #expect(UsagePanelMetrics.outerBottomInset == 12)
        #expect(UsagePanelMetrics.cardSpacing == 12)
        #expect(UsagePanelMetrics.collapsedProviderCardHeight == 82)
        #expect(UsagePanelMetrics.collapsedProviderContribution == 94)
        #expect(UsagePanelMetrics.resolvedContentHeight(nil) == 135)
        #expect(UsagePanelMetrics.resolvedContentHeight(281.2) == 282)
        #expect(UsagePanelMetrics.resolvedContentHeight(281.2 + 94) == 376)
        #expect(UsagePanelMetrics.resolvedContentHeight(2_000) == 776)

        let repository = repositoryRoot()
        let panel = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/CodexUsageUI/Views/UsagePanelView.swift"
            ),
            encoding: .utf8
        )
        #expect(panel.contains("UsagePanelContentHeightPreferenceKey"))
        #expect(panel.contains("resolvedContentHeight(measuredContentHeight)"))
        #expect(
            panel.contains(
                "@AppStorage(\"display.showRecentTasksCard\") private var storedShowRecentTasks = false"
            )
        )
        #expect(
            panel.contains(
                "@AppStorage(\"display.showAPICostCard\") private var storedShowAPICost = false"
            )
        )
        #expect(!panel.contains("baseHeight = 330"))
        #expect(!panel.contains("? 330 : 94"))
    }

    @Test
    func rendererCannotPersistFixturesAndPackageContainsNoRecord() throws {
        let repository = repositoryRoot()
        let renderer = try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/PreviewRendererTool/main.swift"
            ),
            encoding: .utf8
        )
        #expect(!renderer.contains("--write-workbuddy-record"))
        #expect(!renderer.contains("writeWorkBuddyRecord"))
        #expect(renderer.contains("--workbuddy-synthetic-3600"))
        #expect(renderer.contains("remaining = 500"))

        let package = try String(
            contentsOf: repository.appendingPathComponent(
                "script/package_uma_m2wdbg_r1.sh"
            ),
            encoding: .utf8
        )
        #expect(package.contains("BUNDLE_ID=\"com.kevinchen.CodexUsageMonitor\""))
        #expect(
            package.contains(
                "/private/tmp/uma-m2wdbg-r1-final-$short_commit/UMA.app"
            )
        )
        #expect(package.contains("git -C \"$REPO_ROOT\" archive"))
        #expect(package.contains("codesign --verify --deep --strict"))
        #expect(!package.contains("workbuddy-manual-availability.json"))
        #expect(!package.contains("PreviewRendererTool"))
        #expect(!package.contains("Desktop/"))
        #expect(!package.contains("xattr -cr"))
    }

    private func temporaryDirectory(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "uma-m2wdbg-r1-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func canonicalPath(_ path: String) -> String {
        let lexicalURL = URL(fileURLWithPath: path).standardizedFileURL
        return lexicalURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(lexicalURL.lastPathComponent)
            .path
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
