import CoreFoundation
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5-SETUP-G1R Claude status-line activation")
struct M5G1ClaudeSourceAdmissionTests {
    @Test
    func officialAllowlistAcceptsValidSyntheticWindowsAndBoundedVersion() throws {
        let projection = try ClaudeStatusLineAdmissionHarness.decode(
            syntheticPayload(
                """
                {
                  "version": "synthetic-2.1.80",
                  "rate_limits": {
                    "five_hour": {
                      "used_percentage": 0,
                      "resets_at": 1893456000
                    },
                    "seven_day": {
                      "used_percentage": 37.5,
                      "resets_at": 1894060800
                    }
                  }
                }
                """
            )
        )

        #expect(projection.version == "synthetic-2.1.80")
        #expect(projection.fiveHour == .valid(.init(
            remainingPercentage: 100,
            resetsAt: 1_893_456_000
        )))
        #expect(projection.sevenDay == .valid(.init(
            remainingPercentage: 62.5,
            resetsAt: 1_894_060_800
        )))
        #expect(projection.validWindowCount == 2)
        #expect(projection.capability == .twoWindows)
    }

    @Test
    func percentageBoundariesConvertToRemainingExactlyOnce() throws {
        let matrix = [
            (used: 0.0, remaining: 100.0),
            (used: 1.0, remaining: 99.0),
            (used: 36.25, remaining: 63.75),
            (used: 99.9, remaining: 0.1),
            (used: 100.0, remaining: 0.0),
        ]

        for example in matrix {
            let projection = try ClaudeStatusLineAdmissionHarness.decode(
                syntheticWindowPayload(
                    name: "five_hour",
                    usedPercentage: example.used,
                    resetsAt: 1_893_456_000
                )
            )
            let window = try #require(projection.fiveHour.window)
            #expect(
                abs(window.remainingPercentage - example.remaining)
                    < 0.000_000_1
            )
        }
    }

    @Test
    func sharedPresentationConvertsUsedToRemainingAndRetainsResetEpoch() {
        let reset = Date(timeIntervalSince1970: 1_893_456_000)
        let card = SharedUsagePresentationPolicy.makeCard(
            snapshot: sharedSnapshot(
                fiveHourUsed: 36.25,
                sevenDayUsed: 1,
                fiveHourReset: reset
            ),
            previous: nil,
            language: .english,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(card.windows[0].remaining == .finite(63.75))
        #expect(card.windows[0].resetsAt == reset)
        #expect(card.windows[1].remaining == .finite(99))
        #expect(card.selectedWindowID == "five-hour")
    }

    @Test
    func sharedPresentationKeepsWindowsIndependentAndSelectsMaximumDecrement() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = SharedUsagePresentationPolicy.makeCard(
            snapshot: sharedSnapshot(fiveHourUsed: 20, sevenDayUsed: 30),
            previous: nil,
            language: .english,
            now: now
        )
        let current = SharedUsagePresentationPolicy.makeCard(
            snapshot: sharedSnapshot(fiveHourUsed: 40, sevenDayUsed: 35),
            previous: previous,
            language: .english,
            now: now
        )

        #expect(current.windows[0].remaining == .finite(60))
        #expect(current.windows[1].remaining == .finite(65))
        #expect(current.selectedWindowID == "five-hour")
        #expect(current.remaining == .finite(60))
    }

    @Test
    func conversionIsCentralizedAndViewsDoNotRepeatIt() throws {
        let model = try source(
            "Sources/CodexUsageUI/Models/SharedUsagePresentation.swift"
        )
        #expect(model.components(separatedBy: "100 - used").count - 1 == 1)

        let viewRoot = repositoryRoot()
            .appendingPathComponent("Sources/CodexUsageUI/Views")
        let viewSources = try FileManager.default
            .enumerator(at: viewRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n") ?? ""
        #expect(!viewSources.contains("100 -"))

        let selectionStart = try #require(
            model.range(of: "private static func selectedWindowID")
        ).lowerBound
        let selection = String(model[selectionStart...])
        #expect(selection.contains("window.remaining"))
        #expect(!selection.contains("usedPercent"))
    }

    @Test
    func forbiddenAndUnknownFieldsNeverEnterSanitizedProjection() throws {
        let projection = try ClaudeStatusLineAdmissionHarness.decode(
            syntheticPayload(
                """
                {
                  "version": "synthetic-safe",
                  "session_id": "synthetic-forbidden-session",
                  "session_name": "synthetic-forbidden-name",
                  "prompt_id": "synthetic-forbidden-prompt",
                  "transcript_path": "/synthetic/forbidden/transcript",
                  "cwd": "/synthetic/forbidden/cwd",
                  "workspace": {
                    "current_dir": "/synthetic/forbidden/current",
                    "project_dir": "/synthetic/forbidden/project",
                    "repo": {"name": "synthetic-forbidden-repository"}
                  },
                  "account_identity": "synthetic-forbidden-account",
                  "prompt": "synthetic-forbidden-prompt-content",
                  "response": "synthetic-forbidden-response-content",
                  "task": "synthetic-forbidden-task-content",
                  "tool_output": "synthetic-forbidden-tool-content",
                  "future_unknown": {"value": "synthetic-forbidden-unknown"},
                  "rate_limits": {
                    "five_hour": {
                      "used_percentage": 25,
                      "resets_at": 1893456000,
                      "private_extra": "synthetic-forbidden-window-value"
                    }
                  }
                }
                """
            )
        )

        #expect(projection.version == "synthetic-safe")
        #expect(projection.validWindowCount == 1)
        let reflection = String(reflecting: projection)
        #expect(!reflection.contains("synthetic-forbidden"))
        #expect(
            ClaudeStatusLineAdmissionHarness.safeSummary(projection)
                == "valid_windows=1 five_hour=valid seven_day=absent version=present"
        )
    }

    @Test
    func usedPercentageFailsClosedOutsideDocumentedRangeOrType() throws {
        let invalidValues = [
            "-0.01",
            "100.01",
            #""25""#,
            "true",
            "null",
            "{}",
            "[]",
        ]

        for value in invalidValues {
            let projection = try ClaudeStatusLineAdmissionHarness.decode(
                syntheticPayload(
                    """
                    {
                      "rate_limits": {
                        "five_hour": {
                          "used_percentage": \(value),
                          "resets_at": 1893456000
                        }
                      }
                    }
                    """
                )
            )
            #expect(projection.fiveHour == .malformed)
            #expect(projection.validWindowCount == 0)
        }
    }

    @Test
    func nonfinitePercentageTokensFailClosedAsInvalidJSON() {
        for value in ["NaN", "Infinity", "-Infinity"] {
            #expect(throws: Error.self) {
                _ = try ClaudeStatusLineAdmissionHarness.decode(
                    syntheticPayload(
                        """
                        {
                          "rate_limits": {
                            "five_hour": {
                              "used_percentage": \(value),
                              "resets_at": 1893456000
                            }
                          }
                        }
                        """
                    )
                )
            }
        }
    }

    @Test
    func resetTimestampRequiresIntegralUnixSeconds() throws {
        let invalidValues = [
            "-1",
            "1893456000.5",
            #""1893456000""#,
            "true",
            "null",
            "{}",
            "1893456000000",
        ]

        for value in invalidValues {
            let projection = try ClaudeStatusLineAdmissionHarness.decode(
                syntheticPayload(
                    """
                    {
                      "rate_limits": {
                        "five_hour": {
                          "used_percentage": 25,
                          "resets_at": \(value)
                        }
                      }
                    }
                    """
                )
            )
            #expect(projection.fiveHour == .malformed)
        }
    }

    @Test
    func quotaWindowIsAtomicAndNeverInferred() throws {
        let incompletePayloads = [
            """
            {"rate_limits":{"five_hour":{"used_percentage":25}}}
            """,
            """
            {"rate_limits":{"five_hour":{"resets_at":1893456000}}}
            """,
            """
            {"rate_limits":{"five_hour":{}}}
            """,
        ]

        for payload in incompletePayloads {
            let projection = try ClaudeStatusLineAdmissionHarness.decode(
                syntheticPayload(payload)
            )
            #expect(projection.fiveHour == .malformed)
            #expect(projection.fiveHour.window == nil)
            #expect(projection.capability == .unavailable)
        }
    }

    @Test
    func fiveHourAndSevenDayMayBeIndependentlyAbsent() throws {
        let fiveOnly = try ClaudeStatusLineAdmissionHarness.decode(
            syntheticWindowPayload(
                name: "five_hour",
                usedPercentage: 25,
                resetsAt: 1_893_456_000
            )
        )
        #expect(fiveOnly.fiveHour.window != nil)
        #expect(fiveOnly.sevenDay == .absent)
        #expect(fiveOnly.capability == .oneWindow)

        let sevenOnly = try ClaudeStatusLineAdmissionHarness.decode(
            syntheticWindowPayload(
                name: "seven_day",
                usedPercentage: 25,
                resetsAt: 1_894_060_800
            )
        )
        #expect(sevenOnly.fiveHour == .absent)
        #expect(sevenOnly.sevenDay.window != nil)
        #expect(sevenOnly.capability == .oneWindow)
    }

    @Test
    func noValidWindowNeverProducesAdmission() throws {
        let absent = try ClaudeStatusLineAdmissionHarness.decode(
            syntheticPayload(#"{"version":"synthetic"}"#)
        )
        #expect(absent.capability == .unavailable)

        let malformed = try ClaudeStatusLineAdmissionHarness.decode(
            syntheticPayload(
                #"{"rate_limits":{"five_hour":{"used_percentage":25}}}"#
            )
        )
        #expect(malformed.capability == .unavailable)
    }

    @Test
    func installedTrustedButLoggedOutRequiresSetup() {
        #expect(
            ClaudeLocalSourceAdmissionHarness.decide(
                cliTrusted: true,
                authentication: .loggedOut,
                secretOrEnterpriseRoutePresent: false,
                providerEventObserved: false,
                validWindowCount: 0
            ) == .setupRequired
        )
    }

    @Test
    func authenticatedProviderManagedSourceAdmitsOnlyObservedWindows() {
        #expect(
            ClaudeLocalSourceAdmissionHarness.decide(
                cliTrusted: true,
                authentication: .providerManaged,
                secretOrEnterpriseRoutePresent: false,
                providerEventObserved: true,
                validWindowCount: 2
            ) == .go
        )
        #expect(
            ClaudeLocalSourceAdmissionHarness.decide(
                cliTrusted: true,
                authentication: .providerManaged,
                secretOrEnterpriseRoutePresent: false,
                providerEventObserved: true,
                validWindowCount: 1
            ) == .conditionalGo
        )
        #expect(
            ClaudeLocalSourceAdmissionHarness.decide(
                cliTrusted: true,
                authentication: .providerManaged,
                secretOrEnterpriseRoutePresent: false,
                providerEventObserved: true,
                validWindowCount: 0
            ) == .noGo
        )
    }

    @Test
    func authenticatedSourceWithoutObservedStatusLineEventRequiresSetup() {
        #expect(
            ClaudeLocalSourceAdmissionHarness.decide(
                cliTrusted: true,
                authentication: .providerManaged,
                secretOrEnterpriseRoutePresent: false,
                providerEventObserved: false,
                validWindowCount: 0
            ) == .setupRequired
        )
    }

    @Test
    func secretAndEnterpriseRoutesFailClosed() {
        for authentication in [
            ClaudeLocalSourceAdmissionHarness.Authentication.apiKey,
            .bearerToken,
            .bedrock,
            .vertex,
            .foundry,
        ] {
            #expect(
                ClaudeLocalSourceAdmissionHarness.decide(
                    cliTrusted: true,
                    authentication: authentication,
                    secretOrEnterpriseRoutePresent: true,
                    providerEventObserved: true,
                    validWindowCount: 2
                ) == .noGo
            )
        }
    }

    @Test
    func versionIsOptionalBoundedAndNonAuthoritative() throws {
        let absent = try ClaudeStatusLineAdmissionHarness.decode(
            syntheticWindowPayload(
                name: "five_hour",
                usedPercentage: 25,
                resetsAt: 1_893_456_000
            )
        )
        #expect(absent.version == nil)
        #expect(absent.capability == .oneWindow)

        let oversized = String(repeating: "v", count: 65)
        let invalid = try ClaudeStatusLineAdmissionHarness.decode(
            syntheticPayload(
                """
                {
                  "version": "\(oversized)",
                  "rate_limits": {
                    "five_hour": {
                      "used_percentage": 25,
                      "resets_at": 1893456000
                    }
                  }
                }
                """
            )
        )
        #expect(invalid.version == nil)
        #expect(invalid.capability == .oneWindow)
    }

    @Test
    func oversizedAndNonObjectPayloadsFailClosed() {
        let oversized = Data(
            repeating: 0x20,
            count: ClaudeStatusLineAdmissionHarness.maximumPayloadBytes + 1
        )
        #expect(throws: Error.self) {
            _ = try ClaudeStatusLineAdmissionHarness.decode(oversized)
        }
        #expect(throws: Error.self) {
            _ = try ClaudeStatusLineAdmissionHarness.decode(
                syntheticPayload("[]")
            )
        }
    }

    @Test
    func absentSettingsFixtureRequiresNoMutationOrBackup() {
        let state = ClaudeSettingsFixtureHarness.classify(nil)
        #expect(state == .absent)

        let plan = ClaudeSettingsFixtureHarness.probePlan(
            cliInstalled: true,
            providerManagedAuthentication: false,
            serverManagedPolicyKnown: false,
            settings: state
        )
        #expect(!plan.shouldProbe)
        #expect(!plan.shouldMutateSettings)
        #expect(!plan.shouldCreateBackup)
        #expect(plan.blockers.contains(.authenticationUnproven))
        #expect(!plan.blockers.contains(.cliMissing))
    }

    @Test
    func existingStatusLineIsClassifiedWithoutRetainingItsCommand() {
        let data = Data(
            """
            {
              "statusLine": {
                "type": "command",
                "command": "synthetic-existing-command-must-not-be-retained"
              },
              "futureSetting": {"preserve": true}
            }
            """.utf8
        )
        let state = ClaudeSettingsFixtureHarness.classify(data)
        let summary = state.summary

        #expect(summary?.statusLinePresent == true)
        #expect(!String(reflecting: state).contains("must-not-be-retained"))

        let plan = ClaudeSettingsFixtureHarness.probePlan(
            cliInstalled: true,
            providerManagedAuthentication: true,
            serverManagedPolicyKnown: true,
            settings: state
        )
        #expect(!plan.shouldProbe)
        #expect(plan.blockers.contains(.existingStatusLineRequiresPreservation))
    }

    @Test
    func hookAndManagedPolicyFixturesFailClosedHonestly() {
        let hooksDisabled = ClaudeSettingsFixtureHarness.classify(
            Data(#"{"disableAllHooks":true}"#.utf8)
        )
        let disabledPlan = ClaudeSettingsFixtureHarness.probePlan(
            cliInstalled: true,
            providerManagedAuthentication: true,
            serverManagedPolicyKnown: true,
            settings: hooksDisabled
        )
        #expect(disabledPlan.blockers.contains(.hooksDisabled))
        #expect(!disabledPlan.shouldProbe)

        let managedOnly = ClaudeSettingsFixtureHarness.classify(
            Data(#"{"allowManagedHooksOnly":true}"#.utf8)
        )
        let managedPlan = ClaudeSettingsFixtureHarness.probePlan(
            cliInstalled: true,
            providerManagedAuthentication: true,
            serverManagedPolicyKnown: true,
            settings: managedOnly
        )
        #expect(managedPlan.blockers.contains(.managedPolicyReviewRequired))
        #expect(!managedPlan.shouldProbe)

        let enterpriseRoute = ClaudeSettingsFixtureHarness.classify(
            Data(#"{"env":{"CLAUDE_CODE_USE_BEDROCK":"synthetic-present"}}"#.utf8)
        )
        let enterprisePlan = ClaudeSettingsFixtureHarness.probePlan(
            cliInstalled: true,
            providerManagedAuthentication: true,
            serverManagedPolicyKnown: true,
            settings: enterpriseRoute
        )
        #expect(enterprisePlan.blockers.contains(.secretRoutePresent))
        #expect(!enterprisePlan.shouldProbe)
    }

    @Test
    func malformedOrAmbiguousSettingsAreNeverMutated() {
        let malformed = ClaudeSettingsFixtureHarness.classify(
            Data(#"{"statusLine":"#.utf8)
        )
        #expect(malformed == .malformed)

        let plan = ClaudeSettingsFixtureHarness.probePlan(
            cliInstalled: true,
            providerManagedAuthentication: true,
            serverManagedPolicyKnown: false,
            settings: malformed
        )
        #expect(!plan.shouldProbe)
        #expect(!plan.shouldMutateSettings)
        #expect(plan.blockers.contains(.malformedSettings))
        #expect(plan.blockers.contains(.effectivePolicyUnverified))
    }

    @Test
    func syntheticBackupIsOwnerOnlyAndRestoreIsByteExact() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("uma-m5-g1r-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = root.appendingPathComponent("settings.json")
        let backup = root.appendingPathComponent("settings.backup")
        let original = Data(
            """
            {
              "futureUnknown": {"preserve": true},
              "formatting": "synthetic"
            }

            """.utf8
        )

        try original.write(to: settings, options: .atomic)
        try original.write(to: backup, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: backup.path
        )
        try Data(#"{"syntheticProbe":true}"#.utf8)
            .write(to: settings, options: .atomic)

        let backupBytes = try Data(contentsOf: backup)
        try backupBytes.write(to: settings, options: .atomic)

        let restored = try Data(contentsOf: settings)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: backup.path
        )
        let mode = try #require(
            attributes[.posixPermissions] as? NSNumber
        ).intValue

        #expect(mode == 0o600)
        #expect(restored == original)
        #expect(restored.last == 0x0A)
        #expect(
            String(decoding: restored, as: UTF8.self)
                .contains(#""futureUnknown": {"preserve": true}"#)
        )
    }

    @Test
    func durableRecordsAgreeOnCurrentGoAndOnlyNextTask() throws {
        let records = try durableRecords()
        let decision = "GO — CLAUDE STATUS-LINE QUOTA SOURCE PROVEN"

        for record in records {
            #expect(record.contains(decision))
            #expect(record.contains("M5-SETUP-G1R"))
            #expect(record.contains("status-line activation"))
            #expect(record.contains("M5-G2"))
            #expect(!record.contains("/Users/"))
        }
    }

    @Test
    func durableRecordsRecordAuthenticatedTwoWindowProofWithoutLiveValues()
        throws
    {
        let combined = try durableRecords().joined(separator: "\n")

        #expect(combined.contains("official Claude Code status-line"))
        #expect(combined.contains("provider-managed Claude.ai subscription"))
        #expect(combined.contains("Five-hour used percentage | present and valid"))
        #expect(combined.contains("Seven-day used percentage | present and valid"))
        #expect(combined.contains("real percentages"))
        #expect(combined.contains("persistent `statusLine`: absent"))
        #expect(combined.contains("Exactly one next task: M5-G2"))
        #expect(!combined.contains("LIVE CLAUDE SOURCE PROVEN"))
    }

    @Test
    func currentRecordsExplainAuthContextRepairAndCommandLineOnlySettings()
        throws
    {
        let combined = try durableRecords().joined(separator: "\n")

        #expect(combined.contains("build-sandbox visibility error"))
        #expect(combined.contains("real user home"))
        #expect(combined.contains("normal login shell"))
        #expect(combined.contains("command-line `--settings`"))
        #expect(combined.contains("No persistent `statusLine`"))
        #expect(combined.contains("API-key"))
        #expect(combined.contains("account-web"))
    }

    @Test
    func currentRecordsProveBoundedPrivateFieldRejectionAndCleanup() throws {
        let combined = try durableRecords().joined(separator: "\n")

        #expect(combined.contains("64 KiB"))
        #expect(combined.contains("standard input"))
        #expect(combined.contains("raw payload"))
        #expect(combined.contains("task-owned Claude session"))
        #expect(combined.contains("sanitized evidence"))
        #expect(combined.contains("task-owned backup"))
        #expect(!combined.contains("used_percentage\":"))
        #expect(!combined.contains("resets_at\":"))
    }

    @Test
    func currentRecordsPreserveOnlyTheAcceptedProviderOnboardingPreference()
        throws
    {
        let records = try durableRecords()
        let classification =
            "ACCEPTED PROVIDER-OWNED ONBOARDING PREFERENCE — NOT A PROBE ARTIFACT"

        for record in records {
            #expect(record.contains(classification))
            #expect(record.contains("theme"))
            #expect(record.contains("unchanged"))
            #expect(record.contains("`statusLine`"))
        }

        let combined = records.joined(separator: "\n")
        #expect(combined.contains("No other Claude file"))
        #expect(combined.contains("API-key"))
        #expect(combined.contains("enterprise-cloud"))
        #expect(combined.contains("UMA probe configuration"))
    }

    @Test
    func twoValidLiveClassificationsSelectGoWithoutRetainingValues() {
        #expect(
            ClaudeLocalSourceAdmissionHarness.decide(
                cliTrusted: true,
                authentication: .providerManaged,
                secretOrEnterpriseRoutePresent: false,
                providerEventObserved: true,
                validWindowCount: 2
            ) == .go
        )
    }

    @Test
    func scopeLocksExactlyTheSixAuthorizedTrackedFiles() throws {
        let scope = try source("source/UMA M5 Scope Lock.md")
        let expected = [
            "source/UMA M5 Claude Local Source Dossier.md",
            "source/UMA M5 Claude Admission Decision.md",
            "source/UMA M5 Claude Configuration and Restore Contract.md",
            "source/UMA M5 Scope Lock.md",
            "source/UMA M5 Claude QA Issue Ledger.md",
            "Tests/CodexUsageUITests/M5G1ClaudeSourceAdmissionTests.swift",
        ]

        for path in expected {
            #expect(scope.contains(path))
        }
        #expect(scope.contains("No production runtime source"))
    }

    private func durableRecords() throws -> [String] {
        try [
            source("source/UMA M5 Claude Local Source Dossier.md"),
            source("source/UMA M5 Claude Admission Decision.md"),
            source("source/UMA M5 Claude Configuration and Restore Contract.md"),
            source("source/UMA M5 Scope Lock.md"),
            source("source/UMA M5 Claude QA Issue Ledger.md"),
        ]
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

    private func syntheticPayload(_ value: String) -> Data {
        Data(value.utf8)
    }

    private func syntheticWindowPayload(
        name: String,
        usedPercentage: Double,
        resetsAt: Int64
    ) -> Data {
        syntheticPayload(
            """
            {
              "rate_limits": {
                "\(name)": {
                  "used_percentage": \(usedPercentage),
                  "resets_at": \(resetsAt)
                }
              }
            }
            """
        )
    }

    private func sharedSnapshot(
        fiveHourUsed: Double,
        sevenDayUsed: Double,
        fiveHourReset: Date = Date(timeIntervalSince1970: 1_893_456_000)
    ) -> AgentUsageSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        return AgentUsageSnapshot(
            id: AgentConnectorID(rawValue: "claude.local")!,
            providerName: "Claude Code",
            state: .ready,
            capturedAt: capturedAt,
            lastSuccessfulAt: capturedAt,
            freshness: .fresh,
            channels: [
                AgentUsageChannel(
                    id: .account,
                    sourceTier: .officialLocalService,
                    sourceVersion: "synthetic-status-line",
                    scopes: [.account],
                    provenance: .providerReported,
                    freshness: .fresh,
                    capturedAt: capturedAt,
                    coverageNote: nil,
                    rateLimitWindows: [
                        AgentRateLimitWindow(
                            id: "five-hour",
                            kind: .fiveHour,
                            usedPercent: fiveHourUsed,
                            isUnlimited: false,
                            resetsAt: fiveHourReset
                        ),
                        AgentRateLimitWindow(
                            id: "seven-day",
                            kind: .sevenDay,
                            usedPercent: sevenDayUsed,
                            isUnlimited: false,
                            resetsAt: Date(timeIntervalSince1970: 1_894_060_800)
                        ),
                    ],
                    accountMetrics: nil,
                    localActivityMetrics: nil,
                    safeFailure: nil
                ),
            ],
            capabilities: [.connect, .refresh, .disconnect],
            safeFailure: nil
        )
    }
}

private enum ClaudeStatusLineAdmissionHarness {
    static let maximumPayloadBytes = 64 * 1024
    private static let maximumUnixSeconds: Double = 9_999_999_999
    private static let maximumVersionBytes = 64

    struct Window: Equatable {
        let remainingPercentage: Double
        let resetsAt: Int64
    }

    enum WindowState: Equatable {
        case absent
        case malformed
        case valid(Window)

        var window: Window? {
            guard case let .valid(window) = self else { return nil }
            return window
        }

        var label: String {
            switch self {
            case .absent: "absent"
            case .malformed: "malformed"
            case .valid: "valid"
            }
        }
    }

    enum Capability: Equatable {
        case unavailable
        case oneWindow
        case twoWindows
    }

    struct Projection: Equatable {
        let version: String?
        let fiveHour: WindowState
        let sevenDay: WindowState

        var validWindowCount: Int {
            [fiveHour, sevenDay].filter { $0.window != nil }.count
        }

        var capability: Capability {
            switch validWindowCount {
            case 1: .oneWindow
            case 2: .twoWindows
            default: .unavailable
            }
        }
    }

    enum DecodeError: Error {
        case oversized
        case invalidJSON
        case invalidRoot
    }

    static func decode(_ data: Data) throws -> Projection {
        guard data.count <= maximumPayloadBytes else {
            throw DecodeError.oversized
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DecodeError.invalidJSON
        }
        guard let root = object as? [String: Any] else {
            throw DecodeError.invalidRoot
        }

        let rateValue = root["rate_limits"]
        let rateLimits = rateValue as? [String: Any]
        let malformedRateLimits = rateValue != nil && rateLimits == nil

        return Projection(
            version: boundedVersion(root["version"]),
            fiveHour: window(
                rateLimits?["five_hour"],
                parentMalformed: malformedRateLimits
            ),
            sevenDay: window(
                rateLimits?["seven_day"],
                parentMalformed: malformedRateLimits
            )
        )
    }

    static func safeSummary(_ projection: Projection) -> String {
        "valid_windows=\(projection.validWindowCount) "
            + "five_hour=\(projection.fiveHour.label) "
            + "seven_day=\(projection.sevenDay.label) "
            + "version=\(projection.version == nil ? "absent" : "present")"
    }

    private static func window(
        _ value: Any?,
        parentMalformed: Bool
    ) -> WindowState {
        if parentMalformed { return .malformed }
        guard let value else { return .absent }
        guard let object = value as? [String: Any] else {
            return .malformed
        }
        guard
            let percentage = finiteNumber(object["used_percentage"]),
            (0...100).contains(percentage),
            let resetNumber = finiteNumber(object["resets_at"]),
            resetNumber > 0,
            resetNumber <= maximumUnixSeconds,
            resetNumber.rounded(.towardZero) == resetNumber
        else {
            return .malformed
        }
        return .valid(
            Window(
                remainingPercentage: 100 - percentage,
                resetsAt: Int64(resetNumber)
            )
        )
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func boundedVersion(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        guard !value.isEmpty, value.utf8.count <= maximumVersionBytes else {
            return nil
        }
        guard value.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0)
        }) else {
            return nil
        }
        return value
    }
}

private enum ClaudeLocalSourceAdmissionHarness {
    enum Authentication: Equatable {
        case loggedOut
        case providerManaged
        case apiKey
        case bearerToken
        case bedrock
        case vertex
        case foundry
    }

    enum Decision: Equatable {
        case go
        case conditionalGo
        case setupRequired
        case noGo
    }

    static func decide(
        cliTrusted: Bool,
        authentication: Authentication,
        secretOrEnterpriseRoutePresent: Bool,
        providerEventObserved: Bool,
        validWindowCount: Int
    ) -> Decision {
        guard cliTrusted else { return .setupRequired }
        guard !secretOrEnterpriseRoutePresent else { return .noGo }
        guard authentication == .providerManaged else {
            return authentication == .loggedOut ? .setupRequired : .noGo
        }
        guard providerEventObserved else { return .setupRequired }
        switch validWindowCount {
        case 2: return .go
        case 1: return .conditionalGo
        default: return .noGo
        }
    }
}

private enum ClaudeSettingsFixtureHarness {
    struct Summary: Equatable {
        let statusLinePresent: Bool
        let disableAllHooks: Bool
        let allowManagedHooksOnly: Bool
        let apiKeyHelperPresent: Bool
        let secretRouteNamePresent: Bool
    }

    enum State: Equatable {
        case absent
        case malformed
        case valid(Summary)

        var summary: Summary? {
            guard case let .valid(summary) = self else { return nil }
            return summary
        }
    }

    enum Blocker: Hashable {
        case cliMissing
        case authenticationUnproven
        case effectivePolicyUnverified
        case malformedSettings
        case hooksDisabled
        case managedPolicyReviewRequired
        case existingStatusLineRequiresPreservation
        case secretRoutePresent
    }

    struct ProbePlan: Equatable {
        let blockers: Set<Blocker>

        var shouldProbe: Bool { blockers.isEmpty }
        var shouldMutateSettings: Bool { blockers.isEmpty }
        var shouldCreateBackup: Bool { blockers.isEmpty }
    }

    static func classify(_ data: Data?) -> State {
        guard let data else { return .absent }
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            return .malformed
        }

        let environment = root["env"] as? [String: Any] ?? [:]
        let secretNames = [
            "ANTHROPIC_API_KEY",
            "ANTHROPIC_AUTH_TOKEN",
            "CLAUDE_CODE_OAUTH_TOKEN",
            "CLAUDE_CODE_USE_BEDROCK",
            "CLAUDE_CODE_USE_VERTEX",
            "CLAUDE_CODE_USE_FOUNDRY",
        ]
        return .valid(
            Summary(
                statusLinePresent: root["statusLine"] != nil,
                disableAllHooks: root["disableAllHooks"] as? Bool == true,
                allowManagedHooksOnly:
                    root["allowManagedHooksOnly"] as? Bool == true,
                apiKeyHelperPresent: root["apiKeyHelper"] != nil,
                secretRouteNamePresent: secretNames.contains {
                    environment[$0] != nil
                }
            )
        )
    }

    static func probePlan(
        cliInstalled: Bool,
        providerManagedAuthentication: Bool,
        serverManagedPolicyKnown: Bool,
        settings: State
    ) -> ProbePlan {
        var blockers = Set<Blocker>()
        if !cliInstalled { blockers.insert(.cliMissing) }
        if !providerManagedAuthentication {
            blockers.insert(.authenticationUnproven)
        }
        if !serverManagedPolicyKnown {
            blockers.insert(.effectivePolicyUnverified)
        }

        switch settings {
        case .absent:
            break
        case .malformed:
            blockers.insert(.malformedSettings)
        case let .valid(summary):
            if summary.statusLinePresent {
                blockers.insert(.existingStatusLineRequiresPreservation)
            }
            if summary.disableAllHooks {
                blockers.insert(.hooksDisabled)
            }
            if summary.allowManagedHooksOnly {
                blockers.insert(.managedPolicyReviewRequired)
            }
            if summary.apiKeyHelperPresent || summary.secretRouteNamePresent {
                blockers.insert(.secretRoutePresent)
            }
        }
        return ProbePlan(blockers: blockers)
    }
}
