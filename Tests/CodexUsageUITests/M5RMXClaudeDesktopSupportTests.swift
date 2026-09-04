import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5RMX Claude Desktop Local Smart support")
struct M5RMXClaudeDesktopSupportTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    @Test
    func surfaceDetectionCoversAbsentDesktopOnlyCodeOnlyBothAndIDE() throws {
        let root = temporaryDirectory("surface-detection")
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        func detector() -> ClaudeLocalSurfaceDetector {
            ClaudeLocalSurfaceDetector(
                homeDirectory: home,
                applicationsDirectory: applications
            )
        }

        #expect(detector().detectedSurfaces.isEmpty)

        try FileManager.default.createDirectory(
            at: applications.appendingPathComponent("Claude.app"),
            withIntermediateDirectories: true
        )
        #expect(detector().detectedSurfaces == [.claudeDesktop])
        #expect(!detector().statusLineCapableSurfaceInstalled)

        let cli = home.appendingPathComponent(".local/bin/claude")
        try FileManager.default.createDirectory(
            at: cli.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        #expect(detector().detectedSurfaces == [.claudeCode, .claudeDesktop])
        #expect(detector().statusLineCapableSurfaceInstalled)

        try FileManager.default.removeItem(at: cli)
        let ide = home.appendingPathComponent(
            ".vscode/extensions/anthropic.claude-code-2.1.234",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: ide, withIntermediateDirectories: true)
        #expect(detector().statusLineCapableSurfaceInstalled)
        #expect(detector().detectedSurfaces == [.claudeCode, .claudeDesktop])
    }

    @Test
    func exactV2CacheProjectsOnlyNewestSampleAsEstimatedRemaining() throws {
        let root = temporaryDirectory("latest-sample")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("plan-usage-history.json")
        try writeCache(to: file, samples: [
            sample(at: now.addingTimeInterval(-600), fiveHourUsed: 10, sevenDayUsed: 20),
            sample(at: now.addingTimeInterval(-30), fiveHourUsed: 25, sevenDayUsed: 40),
        ])

        let snapshot = try #require(ClaudeDesktopPlanUsageReader(fileURL: file).read(now: now))
        #expect(snapshot.observedAt == now.addingTimeInterval(-30))
        #expect(snapshot.fiveHourRemainingPercent == 75)
        #expect(snapshot.sevenDayRemainingPercent == 60)
        let five = try #require(snapshot.value(for: .fiveHour))
        let seven = try #require(snapshot.value(for: .sevenDay))
        #expect(five.source == .estimatedDesktopCache)
        #expect(seven.source == .estimatedDesktopCache)
        #expect(five.confidence == .low)
        #expect(seven.confidence == .low)
        #expect(five.resetsAt == nil)
        #expect(seven.resetsAt == nil)
        #expect(!String(reflecting: snapshot).contains("discard-this-org"))
    }

    @Test
    func newestSampleUsesTimestampInsteadOfProviderArrayOrder() throws {
        let root = temporaryDirectory("out-of-order-samples")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("plan-usage-history.json")
        try writeCache(to: file, samples: [
            sample(at: now.addingTimeInterval(-30), fiveHourUsed: 25, sevenDayUsed: 40),
            sample(at: now.addingTimeInterval(-600), fiveHourUsed: 10, sevenDayUsed: 20),
            sample(at: now.addingTimeInterval(-300), fiveHourUsed: 15, sevenDayUsed: 30),
        ])

        let snapshot = try #require(ClaudeDesktopPlanUsageReader(fileURL: file).read(now: now))
        #expect(snapshot.observedAt == now.addingTimeInterval(-30))
        #expect(snapshot.fiveHourRemainingPercent == 75)
        #expect(snapshot.sevenDayRemainingPercent == 60)
    }

    @Test
    func tiedNewestTimestampFailsClosedInsteadOfDependingOnProviderArrayOrder() throws {
        let root = temporaryDirectory("ambiguous-newest-sample")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("plan-usage-history.json")
        let tiedNewest = now.addingTimeInterval(-30)
        try writeCache(to: file, samples: [
            sample(at: tiedNewest, fiveHourUsed: 25, sevenDayUsed: 40),
            sample(at: now.addingTimeInterval(-600), fiveHourUsed: 10, sevenDayUsed: 20),
            sample(at: tiedNewest, fiveHourUsed: 30, sevenDayUsed: 45),
        ])

        #expect(ClaudeDesktopPlanUsageReader(fileURL: file).read(now: now) == nil)
    }

    @Test
    func cacheContractFailsClosedOnSchemaPermissionsRangeFreshnessAndSymlink() throws {
        let root = temporaryDirectory("fail-closed")
        defer { try? FileManager.default.removeItem(at: root) }

        func rejected(
            _ name: String,
            object: [String: Any],
            permissions: Int = 0o600
        ) throws {
            let file = root.appendingPathComponent("\(name).json")
            try writeJSONObject(object, to: file, permissions: permissions)
            #expect(ClaudeDesktopPlanUsageReader(fileURL: file).read(now: now) == nil)
        }

        let valid = cacheObject()
        try rejected("owner-read-only", object: valid, permissions: 0o400)
        try rejected("world-readable", object: valid, permissions: 0o644)
        try rejected("executable", object: valid, permissions: 0o700)
        try rejected("version-drift", object: cacheObject(version: 3))
        try rejected("unknown-root", object: valid.merging(["identity": "private"]) { $1 })
        try rejected("unknown-sample", object: cacheObject(samples: [[
            "t": milliseconds(now.addingTimeInterval(-30)), "org": "discard-this-org",
            "u": ["fh": 25.0, "sd": 40.0], "billing": true,
        ]]))
        try rejected("unknown-usage", object: cacheObject(samples: [[
            "t": milliseconds(now.addingTimeInterval(-30)), "org": "discard-this-org",
            "u": ["fh": 25.0, "sd": 40.0, "monthly": 1.0],
        ]]))
        try rejected("unknown-history-sample", object: cacheObject(samples: [[
            "t": milliseconds(now.addingTimeInterval(-60)), "org": "discard-this-org",
            "u": ["fh": 25.0, "sd": 40.0], "private": "discard",
        ], sample(
            at: now.addingTimeInterval(-30),
            fiveHourUsed: 25,
            sevenDayUsed: 40
        )]))
        try rejected("malformed", object: cacheObject(samples: [[
            "t": milliseconds(now.addingTimeInterval(-30)), "org": "discard-this-org",
            "u": ["fh": "25", "sd": 40.0],
        ]]))
        try rejected("out-of-range", object: cacheObject(samples: [[
            "t": milliseconds(now.addingTimeInterval(-30)), "org": "discard-this-org",
            "u": ["fh": -1.0, "sd": 101.0],
        ]]))
        try rejected("stale", object: cacheObject(samples: [
            sample(at: now.addingTimeInterval(-1_201), fiveHourUsed: 25, sevenDayUsed: 40),
        ]))
        try rejected("future", object: cacheObject(samples: [
            sample(at: now.addingTimeInterval(31), fiveHourUsed: 25, sevenDayUsed: 40),
        ]))

        let target = root.appendingPathComponent("safe-target.json")
        try writeJSONObject(valid, to: target, permissions: 0o600)
        let symlink = root.appendingPathComponent("symlink.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        #expect(ClaudeDesktopPlanUsageReader(fileURL: symlink).read(now: now) == nil)

        let oversized = root.appendingPathComponent("oversized.json")
        try Data(repeating: 0x20, count: ClaudeDesktopPlanUsageReader.Contract.maximumBytes + 1)
            .write(to: oversized)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: oversized.path)
        #expect(ClaudeDesktopPlanUsageReader(fileURL: oversized).read(now: now) == nil)
    }

    @Test
    func desktopCacheIsIndependentFromClaudeCodeJSONLAndNeverDoubleCounts() throws {
        let home = temporaryDirectory("independent-sources")
        let sources = ClaudeLocalActivityReader.defaultSources(homeDirectory: home)
        #expect(sources.count == 1)
        #expect(sources.first?.surface == .claudeCode)
        #expect(
            sources.first?.rootDirectory.standardizedFileURL.path
                == home.appendingPathComponent(".claude/projects").standardizedFileURL.path
        )

        let source = try String(contentsOf: sourceFile("ClaudeLocalActivityReader.swift"))
        #expect(!source.contains("local-agent-mode-sessions"))
        #expect(!source.contains("plan-usage-history.json"))
    }

    @Test
    func sourcePrecedenceIsFreshSafariThenExactStatusThenNewestEstimateThenStale() throws {
        let reset = now.addingTimeInterval(3_600)
        let status = try #require(anchor(
            source: .exactLocalStatusLine, used: 20,
            at: now.addingTimeInterval(-20), reset: reset
        ))
        let safari = try #require(anchor(
            source: .exactSafariAccuracy, used: 25,
            at: now.addingTimeInterval(-10), reset: reset
        ))
        let calibrated = ClaudeSmartWindowValue(
            windowKind: .fiveHour, remainingPercent: 70, resetsAt: reset,
            observedAt: now.addingTimeInterval(-15), source: .estimatedLocal,
            confidence: .medium
        )
        let desktop = ClaudeSmartWindowValue(
            windowKind: .fiveHour, remainingPercent: 65, resetsAt: nil,
            observedAt: now.addingTimeInterval(-5), source: .estimatedDesktopCache,
            confidence: .low
        )

        #expect(ClaudeSmartSourceSelector.select(
            windowKind: .fiveHour, statusLineAnchors: [status], safariAnchors: [safari],
            estimate: calibrated, desktopEstimate: desktop, staleExact: safari, now: now
        )?.source == .exactLocalStatusLine)
        #expect(ClaudeSmartSourceSelector.select(
            windowKind: .fiveHour, statusLineAnchors: [], safariAnchors: [safari],
            estimate: calibrated, desktopEstimate: desktop, staleExact: status, now: now
        )?.source == .exactSafariAccuracy)
        let selected = try #require(ClaudeSmartSourceSelector.select(
            windowKind: .fiveHour, statusLineAnchors: [], safariAnchors: [],
            estimate: calibrated, desktopEstimate: desktop, staleExact: status, now: now
        ))
        #expect(selected.remainingPercent == 65)
        #expect(selected.resetsAt == nil)
        #expect(selected.isEstimated)
    }

    @Test
    func incompleteCrossSurfaceCoverageCapsEstimateConfidenceLow() throws {
        let reset = now.addingTimeInterval(3_600)
        let first = try #require(anchor(used: 20, tokens: 1_000, at: now.addingTimeInterval(-120), reset: reset))
        let second = try #require(anchor(used: 30, tokens: 2_000, at: now.addingTimeInterval(-60), reset: reset))
        let activity = ClaudeSanitizedLocalActivity(
            observedAt: now,
            totalTokens: 2_500,
            latestActivityAt: now,
            modelFamilyKey: "sonnet",
            coveragePercent: 100,
            observedSurfaces: [.claudeCode, .claudeDesktop],
            deduplicationConfidence: .conservative
        )

        let estimate = try #require(ClaudeSmartUsageEstimator.estimate(
            windowKind: .fiveHour,
            anchors: [first, second],
            activity: activity,
            previousEstimatedRemaining: nil,
            now: now
        ))
        #expect(estimate.remainingPercent == 65)
        #expect(estimate.confidence == .low)
        #expect(estimate.isEstimated)
    }

    @Test
    func desktopEstimatePublishesApproximateWindowsWithoutResetOrProjectsAccess() async throws {
        let plan = ClaudeDesktopPlanUsageSnapshot(
            observedAt: now.addingTimeInterval(-15),
            fiveHourRemainingPercent: 74,
            sevenDayRemainingPercent: 63
        )
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            now: { now },
            desktopPlanUsageReader: StaticDesktopPlanUsageReader(snapshot: plan),
            desktopActivityContract: .estimateOnlyNoActivitySignal
        )

        await connector.start()
        let snapshot = await connector.currentSnapshot()
        let windows = snapshot.channels.first(where: { $0.id == .account })?.rateLimitWindows ?? []
        #expect(windows.count == 2)
        #expect(windows.allSatisfy { $0.isEstimated == true })
        #expect(windows.allSatisfy { $0.resetsAt == nil })
        let account = try #require(snapshot.channels.first(where: { $0.id == .account }))
        #expect(account.sourceTier == .authorizedLocalEstimate)
        #expect(account.coverageNote?.contains("Desktop plan usage") == true)
        #expect(LocalProviderEligibilityScanner.admission(
            for: snapshot,
            descriptor: connector.descriptor
        ).admittedSnapshot == snapshot)
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .english,
            now: now
        )
        #expect(card.sourceDescription == "Claude Desktop plan usage · estimated")
        #expect(card.remainingDisplayText.hasPrefix("≈"))
        #expect(card.windows.allSatisfy { $0.isEstimated == true })
        let chineseCard = SharedUsagePresentationPolicy.makeCard(
            snapshot: snapshot,
            previous: nil,
            language: .simplifiedChinese,
            now: now
        )
        #expect(chineseCard.sourceDescription == "Claude Desktop 计划用量 · 估算")
        #expect(chineseCard.remainingDisplayText.hasPrefix("≈"))
        #expect(snapshot.channels.first(where: { $0.id == .localActivity }) == nil)
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.desktopPlanUsageReadCount >= 1)
        #expect(diagnostics.desktopPlanUsageAcceptedCount >= 1)
        #expect(diagnostics.localActivityReaderInvocationCount == 0)
        #expect(diagnostics.claudeProjectsAccessCount == 0)
    }

    @Test
    func desktopOnlyModeDoesNotMisclassifyPlanCacheAsAnActivitySignal() async throws {
        let plan = ClaudeDesktopPlanUsageSnapshot(
            observedAt: now.addingTimeInterval(-15),
            fiveHourRemainingPercent: 74,
            sevenDayRemainingPercent: 63
        )
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            now: { now },
            desktopPlanUsageReader: StaticDesktopPlanUsageReader(snapshot: plan),
            desktopActivityContract: .estimateOnlyNoActivitySignal
        )

        await connector.start()
        let snapshot = await connector.currentSnapshot()
        let diagnostics = await connector.diagnostics()
        #expect(snapshot.channels.first(where: { $0.id == .account }) != nil)
        #expect(snapshot.channels.first(where: { $0.id == .localActivity }) == nil)
        #expect(diagnostics.lastLiveLinkStage == .desktopActivitySignalUnavailable)
        #expect(diagnostics.desktopPlanUsageAcceptedCount >= 1)
        #expect(diagnostics.localActivityReaderInvocationCount == 0)
        #expect(diagnostics.claudeProjectsAccessCount == 0)
        let english = AppLanguage.english.claudeLiveLinkStatus(
            .desktopActivitySignalUnavailable
        )
        let chinese = AppLanguage.simplifiedChinese.claudeLiveLinkStatus(
            .desktopActivitySignalUnavailable
        )
        #expect(english.contains("does not expose a stable local activity signal"))
        #expect(!english.contains("Waiting for the first"))
        #expect(chinese.contains("未提供稳定的本地活动信号"))
        #expect(AppLanguage.english.claudeConsentDisclosure.contains(
            "On supported Claude Code terminal or IDE surfaces"
        ))
        #expect(AppLanguage.english.claudeConsentDisclosure.contains(
            "Claude Desktop does not expose a stable local activity signal"
        ))
    }

    @Test
    func mixedInstallLabelsCodeActivityAndDesktopUnavailableSeparately() async throws {
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            now: { now },
            localActivityReader: DesktopCodeActivityReader(now: now),
            desktopPlanUsageReader: StaticDesktopPlanUsageReader(snapshot: nil),
            desktopActivityContract: .estimateOnlyNoActivitySignal
        )

        await connector.start()
        let snapshot = await connector.currentSnapshot()
        let diagnostics = await connector.diagnostics()
        let activity = try #require(snapshot.channels.first(where: { $0.id == .localActivity }))
        #expect(activity.coverageNote == "Observed surfaces: Claude Code")
        #expect(diagnostics.lastLiveLinkStage == .localCodeActivityDetectedDesktopUnavailable)
        #expect(diagnostics.localActivityReaderInvocationCount >= 1)
        #expect(diagnostics.claudeProjectsAccessCount >= 1)
        let message = AppLanguage.english.claudeLiveLinkStatus(
            .localCodeActivityDetectedDesktopUnavailable
        )
        #expect(message.contains("Claude Code activity detected"))
        #expect(message.contains("Claude Desktop activity detection is unavailable"))
    }

    @Test
    func desktopOnlyModeFailsHonestlyWhenNoFreshPlanEstimateExists() async {
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            now: { now },
            desktopPlanUsageReader: StaticDesktopPlanUsageReader(snapshot: nil),
            desktopActivityContract: .estimateOnlyNoActivitySignal
        )

        await connector.start()
        let snapshot = await connector.currentSnapshot()
        let diagnostics = await connector.diagnostics()
        #expect(snapshot.state == .unsupported)
        #expect(snapshot.channels.isEmpty)
        #expect(diagnostics.lastLiveLinkStage == .desktopActivitySignalUnavailable)
        #expect(diagnostics.desktopPlanUsageAcceptedCount == 0)
        let probe = await connector.probe()
        #expect(probe.state == .unsupported)
    }

    @Test
    func productionCompositionUsesOnlyTheExactCacheReaderForDesktopEstimate() throws {
        let runtime = try String(contentsOf: sourceFile(
            "AgentUsageRuntime.swift", directory: "Connectors"
        ))
        let reader = try String(contentsOf: sourceFile("ClaudeDesktopPlanUsageReader.swift"))
        #expect(runtime.contains("let claudeDesktopPlanUsageReader: (any ClaudeDesktopPlanUsageReading)?"))
        #expect(runtime.contains("? ClaudeDesktopPlanUsageReader()"))
        #expect(runtime.contains("desktopPlanUsageReader: claudeDesktopPlanUsageReader"))
        #expect(runtime.contains("let claudeLocalActivityReader: (any ClaudeLocalActivityReading)?"))
        #expect(runtime.contains("? ClaudeLocalActivityReader()"))
        #expect(runtime.contains("localActivityReader: claudeLocalActivityReader"))
        #expect(!runtime.contains("localActivityReader: ClaudeLocalActivityReader()"))
        #expect(runtime.contains("let desktopInstalled = startProviders && claudeSurfaceDetector.claudeDesktopInstalled"))
        #expect(runtime.contains("desktopActivityContract: desktopInstalled\n                ? .estimateOnlyNoActivitySignal"))
        #expect(reader.contains("plan-usage-history.json"))
        #expect(!runtime.contains("local-agent-mode-sessions"))
        #expect(!reader.contains("URLSession"))
        #expect(!reader.contains("Keychain"))
        #expect(!reader.contains("Cookie"))
        #expect(!reader.contains("JSONSerialization"))
        #expect(reader.contains("nestedUnkeyedContainer"))
        #expect(reader.contains("O_NOFOLLOW"))
    }

    @Test
    func desktopPlanCacheIsNotReadWhenDesktopSurfaceIsNotQualified() async {
        let counter = LockedDesktopCounter()
        let connector = ClaudeCodeUsageConnector(
            integration: .unavailable(),
            hasConsent: { true },
            now: { now },
            desktopPlanUsageReader: CountingDesktopPlanUsageReader(
                counter: counter,
                snapshot: ClaudeDesktopPlanUsageSnapshot(
                    observedAt: now,
                    fiveHourRemainingPercent: 74,
                    sevenDayRemainingPercent: 63
                )
            ),
            desktopActivityContract: .notApplicable
        )

        await connector.start()
        let diagnostics = await connector.diagnostics()
        let snapshot = await connector.currentSnapshot()
        #expect(counter.value == 0)
        #expect(diagnostics.desktopPlanUsageReadCount == 0)
        #expect(diagnostics.desktopPlanUsageAcceptedCount == 0)
        #expect(snapshot.channels.first(where: { $0.id == .account }) == nil)
    }

    @Test
    func monitorRejectsAnIntermediateDirectorySymlink() throws {
        let root = temporaryDirectory("monitor-intermediate-symlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let realDirectory = root.appendingPathComponent("real", isDirectory: true)
        let aliasDirectory = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realDirectory,
            withIntermediateDirectories: true
        )
        let realFile = realDirectory.appendingPathComponent("plan-usage-history.json")
        try writeCache(to: realFile, samples: [
            sample(at: now.addingTimeInterval(-30), fiveHourUsed: 25, sevenDayUsed: 40),
        ])
        try FileManager.default.createSymbolicLink(
            at: aliasDirectory,
            withDestinationURL: realDirectory
        )
        let aliasedFile = aliasDirectory.appendingPathComponent("plan-usage-history.json")

        #expect(ClaudeDesktopPlanUsageMonitor.acceptsPathForTesting(realFile))
        #expect(!ClaudeDesktopPlanUsageMonitor.acceptsPathForTesting(aliasedFile))
    }

    @Test
    func readerRevalidatesCompleteSafeMetadataAfterTheBoundedRead() throws {
        let reader = try String(contentsOf: sourceFile("ClaudeDesktopPlanUsageReader.swift"))
        #expect(reader.contains("(finalInfo.st_mode & S_IFMT) == S_IFREG"))
        #expect(reader.contains("finalInfo.st_uid == getuid()"))
        #expect(reader.contains("finalInfo.st_nlink == 1"))
        #expect(reader.contains("(finalInfo.st_mode & 0o777) == 0o600"))
        #expect(reader.contains("finalInfo.st_size <= Int64(Contract.maximumBytes)"))
        #expect(reader.contains("finalInfo.st_ino == info.st_ino"))
        #expect(reader.contains("finalInfo.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec"))
        #expect(reader.contains("finalInfo.st_ctimespec.tv_nsec == info.st_ctimespec.tv_nsec"))
    }

    @Test
    func exactPathMonitorEmitsOnlyContentFreeInvalidationAndIsIdempotent() {
        let counter = LockedDesktopCounter()
        let monitor = ClaudeDesktopPlanUsageMonitor(
            fileURL: URL(fileURLWithPath: "/private/tmp/provider-cache-fixture"),
            onChange: { counter.increment() }
        )
        monitor.start()
        monitor.start()
        #expect(monitor.isRunning)
        monitor.notifyForTesting()
        #expect(counter.value == 1)
        monitor.stop()
        monitor.stop()
        #expect(!monitor.isRunning)
    }

    private func cacheObject(
        version: Int = ClaudeDesktopPlanUsageReader.Contract.schemaVersion,
        samples: [[String: Any]]? = nil
    ) -> [String: Any] {
        [
            "version": version,
            "samples": samples ?? [
                sample(at: now.addingTimeInterval(-30), fiveHourUsed: 25, sevenDayUsed: 40),
            ],
        ]
    }

    private func sample(
        at date: Date,
        fiveHourUsed: Double,
        sevenDayUsed: Double
    ) -> [String: Any] {
        [
            "t": milliseconds(date),
            "org": "discard-this-org",
            "u": ["fh": fiveHourUsed, "sd": sevenDayUsed],
        ]
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private func writeCache(to url: URL, samples: [[String: Any]]) throws {
        try writeJSONObject(cacheObject(samples: samples), to: url, permissions: 0o600)
    }

    private func writeJSONObject(
        _ object: [String: Any],
        to url: URL,
        permissions: Int
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }

    private func anchor(
        source: ClaudeSmartSourceKind,
        used: Double,
        at observedAt: Date,
        reset: Date
    ) -> ClaudeSmartWindowAnchor? {
        ClaudeSmartWindowAnchor(
            windowKind: .fiveHour,
            usedPercent: used,
            resetsAt: reset,
            observedAt: observedAt,
            activityTotalTokens: 1_000,
            source: source,
            modelFamilyKey: "sonnet",
            sourceSchema: "test-1",
            continuityGeneration: 0
        )
    }

    private func anchor(
        used: Double,
        tokens: Int64,
        at observedAt: Date,
        reset: Date
    ) -> ClaudeSmartWindowAnchor? {
        ClaudeSmartWindowAnchor(
            windowKind: .fiveHour,
            usedPercent: used,
            resetsAt: reset,
            observedAt: observedAt,
            activityTotalTokens: tokens,
            source: .exactSafariAccuracy,
            modelFamilyKey: "sonnet",
            sourceSchema: "safari-2",
            continuityGeneration: 0
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-m5rmx-desktop-\(name)-\(UUID().uuidString)")
    }

    private func sourceFile(_ name: String, directory: String = "Services") -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexUsageUI/\(directory)/\(name)")
    }
}

private struct DesktopCodeActivityReader: ClaudeLocalActivityReading {
    let now: Date

    func read(now _: Date) -> ClaudeLocalActivitySnapshot {
        ClaudeLocalActivitySnapshot(
            availability: .available,
            source: "sanitized-test-fixture",
            scope: "local",
            capturedAt: now,
            discoveredFileCount: 1,
            readableFileCount: 1,
            excludedFileCount: 0,
            tasks: [ClaudeLocalActivityTask(totalTokens: 1_234, modifiedAt: now)],
            apiEquivalentCost: ClaudeAPICostEstimate(
                sevenDayUSD: 0, lifetimeUSD: 0, pricedTokens: 1_234,
                observedTokens: 1_234, recognizedModelCount: 1,
                modelNames: ["Sonnet"]
            ),
            observedSurfaces: [.claudeCode]
        )
    }
}

private struct StaticDesktopPlanUsageReader: ClaudeDesktopPlanUsageReading {
    let snapshot: ClaudeDesktopPlanUsageSnapshot?

    func read(now: Date) -> ClaudeDesktopPlanUsageSnapshot? {
        _ = now
        return snapshot
    }
}

private struct CountingDesktopPlanUsageReader: ClaudeDesktopPlanUsageReading {
    let counter: LockedDesktopCounter
    let snapshot: ClaudeDesktopPlanUsageSnapshot?

    func read(now: Date) -> ClaudeDesktopPlanUsageSnapshot? {
        _ = now
        counter.increment()
        return snapshot
    }
}

private final class LockedDesktopCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
