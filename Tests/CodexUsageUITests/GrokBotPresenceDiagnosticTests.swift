import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Grok Bot fail-closed presence diagnostic")
struct GrokBotPresenceDiagnosticTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let sentinel = "desktop-secret-token"

    @Test
    func missingAppIsNotInstalledAndIgnoresLeftoverStatus() throws {
        let fixture = try Fixture(name: "missing-app")
        defer { fixture.cleanup() }
        try fixture.writeDesktop(signedIn: true, extra: ["accessToken": sentinel])

        let classification = fixture.probe.diagnose(now: now)
        #expect(classification == .notInstalled)
        #expect(!String(reflecting: classification).contains(sentinel))
    }

    @Test
    func aFileAtTheAppPathIsNotAnInstallation() throws {
        let fixture = try Fixture(name: "app-file")
        defer { fixture.cleanup() }
        try Data("not-a-bundle".utf8).write(to: fixture.locations.applicationURL)
        try fixture.writeDesktop(signedIn: true)

        #expect(fixture.probe.diagnose(now: now) == .notInstalled)
    }

    @Test
    func signedOutStatusStaysSignedOutWithoutReadingTheMeter() throws {
        let fixture = try Fixture(name: "signed-out")
        defer { fixture.cleanup() }
        try fixture.installApp()
        try fixture.writeDesktop(signedIn: false)
        try FileManager.default.createDirectory(
            at: fixture.locations.applicationSupportUsageStatusURL,
            withIntermediateDirectories: true
        )

        #expect(fixture.probe.diagnose(now: now) == .installedSignedOut)
    }

    @Test
    func missingDesktopStatusFailsClosedAsSignedOut() throws {
        let fixture = try Fixture(name: "status-missing")
        defer { fixture.cleanup() }
        try fixture.installApp()

        #expect(fixture.probe.diagnose(now: now) == .installedSignedOut)
    }

    @Test
    func signedInWithoutMeterDoesNotRetainStatusSecrets() throws {
        let fixture = try Fixture(name: "meter-missing")
        defer { fixture.cleanup() }
        try fixture.installApp()
        try fixture.writeDesktop(
            signedIn: true,
            extra: ["accessToken": sentinel, "email": "person@example.com"]
        )

        let classification = fixture.probe.diagnose(now: now)
        #expect(classification == .installedSignedInMeterMissing)
        let reflected = String(reflecting: classification)
        #expect(!reflected.contains(sentinel))
        #expect(!reflected.contains("person@example.com"))
        #expect(!reflected.contains("42"))
        for language in AppLanguage.allCases {
            let summary = classification.settingsSummary(language: language)
            #expect(!summary.contains("%"))
            #expect(!summary.contains(sentinel))
            #expect(!summary.contains("@"))
        }
    }

    @Test
    func malformedDesktopStatusIsRejected() throws {
        let fixture = try Fixture(name: "bad-desktop")
        defer { fixture.cleanup() }
        try fixture.installApp()
        try fixture.writeRaw(
            Data("{".utf8),
            to: fixture.locations.desktopStatusURL,
            permissions: 0o644
        )
        try fixture.writeUsage(meter(capturedAt: now.addingTimeInterval(-30)))

        #expect(fixture.probe.diagnose(now: now) == .installedStatusRejected)
    }

    @Test
    func malformedUsageMeterIsRejected() throws {
        let fixture = try Fixture(name: "bad-meter")
        defer { fixture.cleanup() }
        try fixture.installApp()
        try fixture.writeDesktop(signedIn: true)
        try fixture.writeRaw(
            Data("{".utf8),
            to: fixture.locations.applicationSupportUsageStatusURL,
            permissions: 0o600
        )

        #expect(fixture.probe.diagnose(now: now) == .installedSignedInMeterRejected)
    }

    @Test
    func unsafeOrIncompleteLocalFilesFailClosed() throws {
        let fixture = try Fixture(name: "unsafe-files")
        defer { fixture.cleanup() }
        try fixture.installApp()

        try fixture.writeRaw(
            Data(repeating: 0x7B, count: GrokBotUsageStatusContract.maximumDesktopStatusBytes + 1),
            to: fixture.locations.desktopStatusURL,
            permissions: 0o644
        )
        #expect(fixture.probe.diagnose(now: now) == .installedStatusRejected)

        try fixture.writeDesktop(signedIn: true, permissions: 0o666)
        #expect(fixture.probe.diagnose(now: now) == .installedStatusRejected)

        try fixture.writeDesktop(signedIn: true)
        try fixture.writeUsage(
            meter(capturedAt: now.addingTimeInterval(-30)),
            permissions: 0o644
        )
        #expect(fixture.probe.diagnose(now: now) == .installedSignedInMeterRejected)

        let outside = fixture.root.appendingPathComponent("outside-meter.json")
        try writeJSON(
            meter(capturedAt: now.addingTimeInterval(-30), planLabel: sentinel),
            to: outside,
            permissions: 0o600
        )
        try? FileManager.default.removeItem(at: fixture.locations.applicationSupportUsageStatusURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.locations.applicationSupportUsageStatusURL,
            withDestinationURL: outside
        )
        let classification = fixture.probe.diagnose(now: now)
        #expect(classification == .installedSignedInMeterRejected)
        #expect(!String(reflecting: classification).contains(sentinel))
    }

    @Test
    func validMeterStaysOffTheUsagePanelAndDoesNotInventAMissingPercent() throws {
        let fixture = try Fixture(name: "valid-meter")
        defer { fixture.cleanup() }
        try fixture.installApp()
        try fixture.writeDesktop(signedIn: true, extra: ["pid": 42, "appVersion": "1.2.3"])
        let capturedAt = now.addingTimeInterval(-60)
        try fixture.writeUsage(meter(capturedAt: capturedAt))

        #expect(fixture.probe.diagnose(now: now) == .installedSignedInMeterNotAdmitted)
        let reading = GrokBotUsageStatusReader().read(
            from: fixture.locations.applicationSupportUsageStatusURL,
            now: now
        )
        guard case let .validated(meter) = reading else {
            Issue.record("Expected a validated meter stub, got \(reading)")
            return
        }
        #expect(meter.capturedAt == capturedAt)
        #expect(meter.planLabel == "Grok Pro")
        #expect(meter.usagePercentUsed == 37.5)
        #expect(meter.remainingPercent == 62.5)
        #expect(meter.isUnlimited == false)
        #expect(meter.source == "GetSandUsageStatus")
        #expect(meter.windows.count == 1)
        #expect(meter.windows.first?.id == "primary")
        #expect(meter.windows.first?.remainingPercent == 62.5)

        try fixture.writeUsage(
            meter(capturedAt: capturedAt, used: 40, remaining: nil, includeWindows: false)
        )
        let usedOnly = GrokBotUsageStatusReader().read(
            from: fixture.locations.applicationSupportUsageStatusURL,
            now: now
        )
        guard case let .validated(partial) = usedOnly else {
            Issue.record("Expected a one-sided meter, got \(usedOnly)")
            return
        }
        #expect(partial.usagePercentUsed == 40)
        #expect(partial.remainingPercent == nil)
        #expect(fixture.probe.diagnose(now: now) == .installedSignedInMeterNotAdmitted)

        for classification in GrokBotPresenceClassification.allCases {
            for language in AppLanguage.allCases {
                let summary = classification.settingsSummary(language: language)
                #expect(!summary.contains("%"))
                #expect(!summary.contains("37.5"))
                #expect(!summary.contains("Grok Pro"))
            }
        }
    }

    @Test
    func meterContractRejectionsDoNotBecomeUsage() throws {
        let fixture = try Fixture(name: "contract-rejections")
        defer { fixture.cleanup() }
        try fixture.installApp()
        try fixture.writeDesktop(signedIn: true)
        let reader = GrokBotUsageStatusReader()
        let capturedAt = now.addingTimeInterval(-30)

        let rejected: [[String: Any]] = [
            meter(capturedAt: now.addingTimeInterval(-(20 * 60 + 1))),
            meter(capturedAt: now.addingTimeInterval(31)),
            meter(capturedAt: capturedAt, used: 10, remaining: 10),
            meter(capturedAt: capturedAt, used: nil, remaining: nil, includeWindows: false),
            meter(capturedAt: capturedAt, schemaVersion: 2),
            meter(capturedAt: capturedAt, signedIn: "true"),
            meter(capturedAt: capturedAt, extra: ["email": "person@example.com"]),
            meter(capturedAt: capturedAt, extra: ["accessToken": sentinel]),
            meter(capturedAt: capturedAt, planLabel: "person@example.com"),
            meter(
                capturedAt: capturedAt,
                capturedAtText: "2026-09-22T15:04:05+05:00"
            ),
        ]
        for object in rejected {
            try fixture.writeUsage(object)
            #expect(reader.read(
                from: fixture.locations.applicationSupportUsageStatusURL,
                now: now
            ) == .rejected)
            #expect(fixture.probe.diagnose(now: now) == .installedSignedInMeterRejected)
        }

        try fixture.writeUsage(
            meter(capturedAt: now.addingTimeInterval(-(20 * 60)))
        )
        #expect(fixture.probe.diagnose(now: now) == .installedSignedInMeterNotAdmitted)
        try fixture.writeUsage(
            meter(
                capturedAt: capturedAt,
                capturedAtText: "2026-09-22T15:04:05.000Z"
            )
        )
        let fractionalNow = try #require(iso8601Date("2026-09-22T15:04:05.000Z"))
        guard case .validated = reader.read(
            from: fixture.locations.applicationSupportUsageStatusURL,
            now: fractionalNow
        ) else {
            Issue.record("Fractional UTC meter was not accepted")
            return
        }
    }

    @Test
    func fallbackMeterIsUsedOnlyWhenThePreferredFileIsAbsent() throws {
        let fixture = try Fixture(name: "fallback")
        defer { fixture.cleanup() }
        try fixture.installApp()
        try fixture.writeDesktop(signedIn: true)
        let capturedAt = now.addingTimeInterval(-15)
        try fixture.writeUsage(meter(capturedAt: capturedAt), fallback: true)

        #expect(fixture.probe.diagnose(now: now) == .installedSignedInMeterNotAdmitted)

        try fixture.writeRaw(
            Data("{".utf8),
            to: fixture.locations.applicationSupportUsageStatusURL,
            permissions: 0o600
        )
        #expect(fixture.probe.diagnose(now: now) == .installedSignedInMeterRejected)
    }

    @MainActor
    @Test
    func registryAndMainUsageSurfaceDoNotAdmitGrok() async throws {
        let registry = AgentUsageRuntime.makeCodexRegistry()
        let descriptors = await registry.orderedDescriptors()
        #expect(descriptors.map(\.id) == [CodexUsageConnector.connectorID])
        #expect(!descriptors.contains {
            $0.id.rawValue.localizedCaseInsensitiveContains("grok")
                || $0.providerName.localizedCaseInsensitiveContains("grok")
        })
        #expect(UsageMonitorRuntime.productionConnectorIDs == [
            CodexUsageConnector.connectorID,
            ClaudeCodeUsageConnector.connectorID,
        ])

        let grok = try #require(AgentConnectorID(rawValue: "grok"))
        #expect(ProviderProductStatePolicy.productID(for: grok) == nil)
        #expect(!ProviderProductID.allCases.contains {
            $0.rawValue.localizedCaseInsensitiveContains("grok")
                || $0.displayName.localizedCaseInsensitiveContains("grok")
        })

        let reduction = ProviderProductStatePolicy.reduce(
            snapshots: [],
            admissions: [],
            monitoringEnabledIDs: [],
            previousCards: [],
            language: .english
        )
        #expect(!reduction.presentationCards.contains {
            $0.id.localizedCaseInsensitiveContains("grok")
        })
        #expect(!reduction.inventory.providers.contains {
            $0.id.rawValue.localizedCaseInsensitiveContains("grok")
                || $0.displayName.localizedCaseInsensitiveContains("grok")
        })
        #expect(!reduction.inventory.overviewProviders.contains {
            $0.displayName.localizedCaseInsensitiveContains("grok")
        })

        let coordinator = AgentSettingsCoordinator(
            store: AgentPreferenceStore(preferences: ApplicationPreferences.inMemory())
        )
        #expect(coordinator.entries.map(\.providerID.rawValue) == [
            AgentPreferenceRecord.codexProviderID.rawValue,
            AgentPreferenceRecord.claudeProviderID.rawValue,
            AgentPreferenceRecord.workBuddyProviderID.rawValue,
            AgentPreferenceRecord.antigravityProviderID.rawValue,
        ])
        #expect(!coordinator.entries.contains {
            $0.displayName.localizedCaseInsensitiveContains("grok")
        })
    }

    @MainActor
    @Test
    func settingsPublishesPresenceWithoutAUsageCard() throws {
        let preferences = ApplicationPreferences.inMemory()
        let store = UsageStore.preview(language: .english)
        let model = GlobalSettingsViewModel(
            preferences: preferences,
            store: store,
            grokBotPresenceProbe: FixedGrokBotPresenceProbe(
                classification: .installedSignedInMeterNotAdmitted
            )
        )

        #expect(model.grokBotPresence == .installedSignedInMeterNotAdmitted)
        #expect(
            model.grokBotPresence.settingsSummary(language: .english)
                == "Signed in, local usage meter not on the usage panel"
        )
        #expect(!store.presentationCards.contains {
            $0.id.localizedCaseInsensitiveContains("grok")
        })
        #expect(!store.productInventory.providers.contains {
            $0.displayName.localizedCaseInsensitiveContains("grok")
        })

        let exported = try SettingsDiagnosticsExporter.data(
            activeProviderCount: store.productInventory.providers.filter(\.isActive).count,
            preferences: preferences,
            grokBotPresence: model.grokBotPresence
        )
        let text = String(decoding: exported, as: UTF8.self)
        let object = try #require(
            JSONSerialization.jsonObject(with: exported) as? [String: Any]
        )
        #expect(object["grokBotPresence"] as? String == GrokBotPresenceClassification.installedSignedInMeterNotAdmitted.rawValue)
        #expect(!text.contains("%"))
        #expect(!text.contains("Grok Pro"))
        #expect(!text.contains("37.5"))
        #expect(!text.contains(sentinel))
    }

    @Test
    func contractAndProbeStayOnTheLocalPresencePath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contract = try String(
            contentsOf: root.appendingPathComponent(
                "docs/integrations/grok-bot-usage-status-contract.md"
            ),
            encoding: .utf8
        )
        #expect(contract.contains("usage-status.json"))
        #expect(contract.contains("desktop-status.json"))
        #expect(contract.contains("Fail closed"))
        #expect(contract.contains("main panel stays empty for Grok"))
        #expect(contract.contains("20 minutes"))
        #expect(contract.contains("`0600`"))
        #expect(contract.contains("access tokens"))

        let probe = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/CodexUsageUI/Services/GrokBotPresenceProbe.swift"
            ),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/CodexUsageUI/Views/AgentSurfaceViews.swift"
            ),
            encoding: .utf8
        )
        for forbidden in [
            "URLSession",
            "SecItem",
            "HTTPCookie",
            "contentsOfDirectory",
            "NSWorkspace",
            "statsig",
            "Antigravity",
        ] {
            #expect(!probe.localizedCaseInsensitiveContains(forbidden))
        }
        #expect(probe.contains("installedSignedInMeterNotAdmitted"))
        #expect(probe.contains("not an `AgentUsageSnapshot`"))
        #expect(!probe.contains("AgentUsageSnapshot("))
        #expect(!probe.contains("AgentConnectorRegistry"))
        #expect(settings.contains("uma.settings.privacy.grok-bot-presence"))

        let locations = GrokBotPresenceLocations.production
        #expect(locations.applicationURL.lastPathComponent == "Grok Bot.app")
        #expect(locations.desktopStatusURL.lastPathComponent == "desktop-status.json")
        #expect(locations.applicationSupportUsageStatusURL.path.contains(
            "Library/Application Support/Grok Bot/usage-status.json"
        ))
        #expect(locations.homeUsageStatusURL.path.hasSuffix("/.grokbot/usage-status.json"))
        #expect(
            locations.applicationSupportUsageStatusURL.path
                != locations.homeUsageStatusURL.path
        )
    }

    private func meter(
        capturedAt: Date,
        used: Any? = 37.5,
        remaining: Any? = 62.5,
        signedIn: Any = true,
        schemaVersion: Any = 1,
        planLabel: String? = "Grok Pro",
        includeWindows: Bool = true,
        capturedAtText: String? = nil,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var object: [String: Any] = [
            "schemaVersion": schemaVersion,
            "capturedAt": capturedAtText ?? iso8601(capturedAt),
            "signedIn": signedIn,
            "isUnlimited": false,
            "isTeamSeat": false,
            "onDemandEnabled": false,
            "source": "GetSandUsageStatus",
        ]
        if let used { object["usagePercentUsed"] = used }
        if let remaining { object["remainingPercent"] = remaining }
        if let planLabel { object["planLabel"] = planLabel }
        if includeWindows {
            object["windows"] = [[
                "id": "primary",
                "label": "Primary",
                "usedPercent": 37.5,
                "remainingPercent": 62.5,
                "unlimited": false,
            ]]
        }
        for (key, value) in extra { object[key] = value }
        return object
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func iso8601Date(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractional.timeZone = TimeZone(secondsFromGMT: 0)
        return fractional.date(from: string)
    }
}

private struct FixedGrokBotPresenceProbe: GrokBotPresenceProbing {
    let classification: GrokBotPresenceClassification

    func diagnose(now: Date) -> GrokBotPresenceClassification { classification }
}

private struct Fixture {
    let root: URL
    let locations: GrokBotPresenceLocations
    var probe: GrokBotPresenceProbe { GrokBotPresenceProbe(locations: locations) }

    init(name: String) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-grok-\(name)-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        let support = root.appendingPathComponent(
            "Library/Application Support/Grok Bot",
            isDirectory: true
        )
        let dot = root.appendingPathComponent(".grokbot", isDirectory: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dot, withIntermediateDirectories: true)
        locations = GrokBotPresenceLocations(
            applicationURL: applications.appendingPathComponent("Grok Bot.app", isDirectory: true),
            desktopStatusURL: support.appendingPathComponent("desktop-status.json"),
            applicationSupportUsageStatusURL: support.appendingPathComponent("usage-status.json"),
            homeUsageStatusURL: dot.appendingPathComponent("usage-status.json")
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    func installApp() throws {
        try FileManager.default.createDirectory(
            at: locations.applicationURL,
            withIntermediateDirectories: true
        )
    }

    func writeDesktop(
        signedIn: Bool,
        permissions: Int = 0o644,
        extra: [String: Any] = [:]
    ) throws {
        var object: [String: Any] = [
            "signedIn": signedIn,
            "pid": 42,
            "appVersion": "1.2.3",
        ]
        for (key, value) in extra { object[key] = value }
        try writeJSON(object, to: locations.desktopStatusURL, permissions: permissions)
    }

    func writeUsage(
        _ object: [String: Any],
        permissions: Int = 0o600,
        fallback: Bool = false
    ) throws {
        let url = fallback
            ? locations.homeUsageStatusURL
            : locations.applicationSupportUsageStatusURL
        try writeJSON(object, to: url, permissions: permissions)
    }

    func writeRaw(_ data: Data, to url: URL, permissions: Int) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }
}

private func writeJSON(_ object: Any, to url: URL, permissions: Int) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: permissions],
        ofItemAtPath: url.path
    )
}
