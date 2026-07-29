import CoreFoundation
import Foundation
import Testing

@Suite("M5-G1 Claude local-source admission")
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
            usedPercentage: 0,
            resetsAt: 1_893_456_000
        )))
        #expect(projection.sevenDay == .valid(.init(
            usedPercentage: 37.5,
            resetsAt: 1_894_060_800
        )))
        #expect(projection.validWindowCount == 2)
        #expect(projection.capability == .twoWindows)
    }

    @Test
    func percentageBoundariesAndRemainingDerivationAreExact() throws {
        for used in [0.0, 9.25, 50.0, 100.0] {
            let projection = try ClaudeStatusLineAdmissionHarness.decode(
                syntheticWindowPayload(
                    name: "five_hour",
                    usedPercentage: used,
                    resetsAt: 1_893_456_000
                )
            )
            let window = try #require(projection.fiveHour.window)
            #expect(window.usedPercentage == used)
            #expect(window.remainingPercentage == 100 - used)
        }
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
            cliInstalled: false,
            providerManagedAuthentication: false,
            serverManagedPolicyKnown: false,
            settings: state
        )
        #expect(!plan.shouldProbe)
        #expect(!plan.shouldMutateSettings)
        #expect(!plan.shouldCreateBackup)
        #expect(plan.blockers.contains(.cliMissing))
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
            .appendingPathComponent("uma-m5-g1-\(UUID().uuidString)")
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
    func durableRecordsAgreeOnSetupRequiredAndOnlyNextTask() throws {
        let records = try durableRecords()
        let decision = "SETUP REQUIRED — CLAUDE CODE CLI NOT INSTALLED"

        for record in records {
            #expect(record.contains(decision))
            #expect(record.contains("M5-SETUP-G1"))
            #expect(record.contains("M5-G2 remains locked"))
            #expect(!record.contains("/Users/"))
        }
    }

    @Test
    func durableRecordsMakeNoLiveOrAuthenticationClaim() throws {
        let combined = try durableRecords().joined(separator: "\n")

        #expect(combined.contains("official Claude Code status-line"))
        #expect(combined.contains("potentially admissible"))
        #expect(combined.contains("Authentication: unknown"))
        #expect(combined.contains("No status-line payload was observed"))
        #expect(combined.contains("No Claude process"))
        #expect(combined.contains("No settings mutation"))
        #expect(!combined.contains("Admission decision: GO"))
        #expect(!combined.contains("LIVE CLAUDE SOURCE PROVEN"))
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
}

private enum ClaudeStatusLineAdmissionHarness {
    static let maximumPayloadBytes = 64 * 1024
    private static let maximumUnixSeconds: Double = 9_999_999_999
    private static let maximumVersionBytes = 64

    struct Window: Equatable {
        let usedPercentage: Double
        let resetsAt: Int64

        var remainingPercentage: Double {
            100 - usedPercentage
        }
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
                usedPercentage: percentage,
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
