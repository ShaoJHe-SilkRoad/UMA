import Foundation
import CoreFoundation
import Testing

@Suite("M6 Antigravity official source admission")
struct M6G1AntigravitySourceAdmissionTests {
    @Test
    func officialCLIAbsenceRequiresSetupWithoutProviderRead() {
        let evidence = AntigravityAdmissionEvidence.m6G1Snapshot

        #expect(evidence.pathLookup == .absent)
        #expect(evidence.documentedPath == .absent)
        #expect(evidence.application == .present)
        #expect(evidence.quotaReads == 0)
        #expect(AntigravityAdmissionHarness.decide(evidence) == .setupRequired)
    }

    @Test
    func missingExecutableLeavesCapabilityAndLiveSchemaUnavailable() {
        let evidence = AntigravityAdmissionEvidence.m6G1Snapshot

        #expect(evidence.installedVersion == .unavailable)
        #expect(evidence.installedHelp == .unavailable)
        #expect(evidence.signature == .unavailable)
        #expect(evidence.gatekeeper == .unavailable)
        #expect(evidence.liveSchema == .unavailable)
        #expect(evidence.remainingSemantics == .unavailable)
        #expect(evidence.resetSemantics == .unavailable)
        #expect(evidence.structuralStability == .unavailable)
        #expect(evidence.testedQuotaArgumentVector == nil)
    }

    @Test
    func setupDecisionPreservesOfficialSourceClass() {
        let evidence = AntigravityAdmissionEvidence.m6G1Snapshot

        #expect(evidence.sourceClass == .officialCLI)
        #expect(evidence.publicStructuredPrintContract)
        #expect(evidence.productionConnectorImplemented == false)
        #expect(AntigravityAdmissionHarness.nextTask(for: evidence) == "M6-SETUP-G1")
    }

    @Test
    func authenticationIsUnobservableNotLoggedOut() {
        let evidence = AntigravityAdmissionEvidence.m6G1Snapshot

        #expect(evidence.authentication == .unobservable)
        #expect(evidence.authentication != .loginRequired)
        #expect(evidence.authentication != .sessionExpired)
        #expect(evidence.authentication != .authenticated)
        #expect(evidence.currentDeviceBrowserBehavior == .unavailable)
    }

    @Test
    func creditsRemainDeferredAndIndependent() {
        let evidence = AntigravityAdmissionEvidence.m6G1Snapshot

        #expect(evidence.credits == .defer)
        #expect(evidence.creditReads == 0)
        #expect(evidence.creditValue == nil)
        #expect(evidence.creditPercentage == nil)
        #expect(AntigravityAdmissionHarness.decide(evidence) == .setupRequired)
    }

    @Test
    func privacyAndProbeAccountingRemainZero() {
        let rawFixture: [String: Any] = [
            "installed": false,
            "email": "synthetic-private@example.invalid",
            "account_id": "synthetic-account",
            "workspace": "/synthetic/private/workspace",
            "conversation": "synthetic-conversation",
            "prompt": "synthetic-prompt",
            "response": "synthetic-response",
            "token": "synthetic-token",
        ]

        let projection = AntigravityAdmissionHarness.sanitize(rawFixture)
        let reflection = String(reflecting: projection)

        #expect(projection == .init(installed: false, quotaReads: 0))
        #expect(!reflection.contains("synthetic-private"))
        #expect(!reflection.contains("synthetic-account"))
        #expect(!reflection.contains("synthetic-conversation"))
        #expect(!reflection.contains("synthetic-token"))
        #expect(AntigravityAdmissionEvidence.m6G1Snapshot.providerPrompts == 0)
        #expect(AntigravityAdmissionEvidence.m6G1Snapshot.providerTasks == 0)
        #expect(AntigravityAdmissionEvidence.m6G1Snapshot.intentionalSpend == 0)
    }

    @Test
    func durableRecordsPreserveHistoricalDecisionAndCurrentNextTask() throws {
        let records = try durableRecords()

        for record in records {
            #expect(record.contains("CREDITS DEFER"))
            #expect(record.contains("M6-G1R"))
            #expect(!record.contains("synthetic-private@example.invalid"))
            #expect(!record.contains("/Users/juliushe/.local/bin/agy"))
        }

        let admission = records[1]
        #expect(admission.contains("SETUP REQUIRED"))
        #expect(admission.contains("M6-SETUP-G1"))

        let setup = records[4]
        #expect(setup.contains("PASS — OFFICIAL ANTIGRAVITY CLI SETUP READY FOR M6-G1R"))
        #expect(setup.contains("$HOME/.local/bin/agy"))
        #expect(setup.contains("1.1.11"))
        #expect(setup.contains("structured JSON"))
    }

    @Test
    func admissionAndSetupScopeContainsOnlyAuthorizedFiles() throws {
        let ledger = try source("source/UMA M6 Antigravity QA Issue Ledger.md")
        let expected = [
            "Tests/CodexUsageUITests/M6G1AntigravitySourceAdmissionTests.swift",
            "source/UMA M6 Antigravity Local Source Dossier.md",
            "source/UMA M6 Antigravity Admission Decision.md",
            "source/UMA M6 Antigravity Privacy Contract.md",
            "source/UMA M6 Antigravity QA Issue Ledger.md",
            "source/UMA M6 Antigravity Setup Evidence.md",
        ]

        for path in expected {
            #expect(ledger.contains(path))
        }
        #expect(!ledger.contains("Sources/CodexUsageUI/Connectors/Antigravity"))
        #expect(!ledger.contains("script/package_uma_m6"))
    }

    @Test
    func setupEvidenceUsesOneReadWithoutProviderWork() throws {
        let setup = try source("source/UMA M6 Antigravity Setup Evidence.md")

        #expect(setup.contains("| Read-only `/usage` executions | 1 |"))
        #expect(setup.contains("| Retries | 0 |"))
        #expect(setup.contains("| Provider prompts/tasks | 0 |"))
        #expect(setup.contains("| Intentional quota spend | 0 |"))
        #expect(setup.contains("| Browser login actions | 0 |"))
        #expect(setup.contains("M6-G2 and production connector work remain locked"))
    }

    @Test
    func setupEvidenceRetainsNoLiveQuotaOrCredentialMaterial() throws {
        let setup = try source("source/UMA M6 Antigravity Setup Evidence.md")

        #expect(setup.contains("No exact live quota value or account data was retained"))
        #expect(!setup.contains("access_token"))
        #expect(!setup.contains("refresh_token"))
        #expect(!setup.contains("account_id"))
        #expect(!setup.contains("synthetic-private@example.invalid"))
    }

    @Test
    func g1RDoesNotAdmitWithoutRepeatedStructureIdentityAndNoTurnProof() {
        let evidence = AntigravityAdmissionEvidence.m6G1RObservation

        #expect(evidence.pathLookup == .present)
        #expect(evidence.liveSchema == .present)
        #expect(evidence.remainingSemantics == .present)
        #expect(evidence.resetSemantics == .present)
        #expect(evidence.structuralStability == .unavailable)
        #expect(evidence.identityStability == .unavailable)
        #expect(evidence.noProviderWork == .unavailable)
        #expect(evidence.quotaReads == 3)
        #expect(AntigravityAdmissionHarness.decide(evidence) == .noGo)
        #expect(AntigravityAdmissionHarness.nextTask(for: evidence) == "Founder source-direction decision")
    }

    @Test
    func stableIdentityIsAnIndependentMandatoryAdmissionGate() {
        var evidence = AntigravityAdmissionEvidence.m6G1RObservation
        evidence.structuralStability = .present
        evidence.noProviderWork = .present

        #expect(evidence.identityStability == .unavailable)
        #expect(AntigravityAdmissionHarness.decide(evidence) == .noGo)
    }

    @Test
    func observedOneBucketSchemaNormalizesRemainingExactlyOnce() throws {
        let projection = try AntigravityQuotaFixtureDecoder.decode(
            fixture(groups: [
                group("group-a", buckets: [bucket("bucket-a", remaining: 0.425, reset: "2026-08-09T12:00:00Z")]),
            ])
        )

        #expect(projection.buckets == [
            .init(stableID: "group-a|bucket-a|five-hour", remainingPercent: 42.5, hasReset: true),
        ])
    }

    @Test
    func multipleBucketsRemainIndependentAndBoundariesAreExact() throws {
        let projection = try AntigravityQuotaFixtureDecoder.decode(
            fixture(groups: [
                group("group-a", buckets: [bucket("bucket-a", remaining: 0, reset: nil)]),
                group("group-b", buckets: [bucket("bucket-b", remaining: 1, reset: nil)]),
            ])
        )

        #expect(projection.buckets.map(\.stableID) == [
            "group-a|bucket-a|five-hour",
            "group-b|bucket-b|five-hour",
        ])
        #expect(projection.buckets.map(\.remainingPercent) == [0, 100])
        #expect(projection.buckets.allSatisfy { !$0.hasReset })
    }

    @Test(arguments: [-0.01, 1.01])
    func invalidRemainingFractionFailsClosed(_ remaining: Double) {
        #expect(throws: AntigravityQuotaFixtureError.invalidBucket) {
            try AntigravityQuotaFixtureDecoder.decode(
                fixture(groups: [group("group-a", buckets: [bucket("bucket-a", remaining: remaining, reset: nil)])])
            )
        }
    }

    @Test
    func malformedMissingAndWrongTypeQuotaDataFailClosed() {
        #expect(throws: AntigravityQuotaFixtureError.malformedJSON) {
            try AntigravityQuotaFixtureDecoder.decode(Data("{".utf8))
        }
        #expect(throws: AntigravityQuotaFixtureError.malformedJSON) {
            try AntigravityQuotaFixtureDecoder.decode(
                Data(#"{"command":{"data":{"groups":[{"name":"group-a","buckets":[{"id":"bucket-a","window":"five-hour","remaining_fraction":NaN}]}]}}}"#.utf8)
            )
        }
        #expect(throws: AntigravityQuotaFixtureError.missingQuotaContainer) {
            try AntigravityQuotaFixtureDecoder.decode(Data(#"{"command":{"data":{}}}"#.utf8))
        }
        #expect(throws: AntigravityQuotaFixtureError.missingQuotaContainer) {
            try AntigravityQuotaFixtureDecoder.decode(
                Data(#"{"command":{"name":"different-command","data":{"groups":[]}}}"#.utf8)
            )
        }
        #expect(throws: AntigravityQuotaFixtureError.invalidBucket) {
            try AntigravityQuotaFixtureDecoder.decode(
                fixture(groups: [group("group-a", buckets: [[
                    "id": "bucket-a",
                    "name": "Synthetic label",
                    "window": "five-hour",
                    "reset_time": "2026-08-09T12:00:00Z",
                ]])])
            )
        }
        #expect(throws: AntigravityQuotaFixtureError.invalidBucket) {
            try AntigravityQuotaFixtureDecoder.decode(
                fixture(groups: [group("group-a", buckets: [[
                    "id": "bucket-a",
                    "name": "Synthetic label",
                    "window": "five-hour",
                    "remaining_fraction": "0.5",
                ]])])
            )
        }
    }

    @Test
    func resetIsBucketScopedOptionalAndMustBeISO8601() throws {
        let withoutReset = try AntigravityQuotaFixtureDecoder.decode(
            fixture(groups: [group("group-a", buckets: [bucket("bucket-a", remaining: 0.5, reset: nil)])])
        )
        #expect(withoutReset.buckets == [
            .init(stableID: "group-a|bucket-a|five-hour", remainingPercent: 50, hasReset: false),
        ])

        #expect(throws: AntigravityQuotaFixtureError.invalidBucket) {
            try AntigravityQuotaFixtureDecoder.decode(
                fixture(groups: [group("group-a", buckets: [bucket("bucket-a", remaining: 0.5, reset: "tomorrow")])])
            )
        }
    }

    @Test
    func unknownAndPrivateFieldsNeverEnterTheProjection() throws {
        let data = try fixture(
            groups: [group("group-a", buckets: [[
                "id": "bucket-a",
                "name": "synthetic-private@example.invalid",
                "window": "five-hour",
                "remaining_fraction": 0.5,
                "reset_time": "2026-08-09T12:00:00Z",
                "future_private": "synthetic-secret",
            ]])],
            envelopeExtras: [
                "conversation_id": "synthetic-conversation",
                "response": "synthetic-response",
                "account_id": "synthetic-account",
                "usage": ["total_tokens": 999],
            ]
        )

        let projection = try AntigravityQuotaFixtureDecoder.decode(data)
        let reflection = String(reflecting: projection)

        #expect(!reflection.contains("synthetic-private"))
        #expect(!reflection.contains("synthetic-secret"))
        #expect(!reflection.contains("synthetic-conversation"))
        #expect(!reflection.contains("synthetic-response"))
        #expect(!reflection.contains("synthetic-account"))
        #expect(!reflection.contains("999"))
    }

    @Test
    func unsafeOrDuplicateIdentityAndUnsupportedVersionFailClosed() {
        #expect(throws: AntigravityQuotaFixtureError.invalidBucket) {
            try AntigravityQuotaFixtureDecoder.decode(
                fixture(groups: [group("unsafe group", buckets: [bucket("bucket-a", remaining: 0.5, reset: nil)])])
            )
        }
        #expect(throws: AntigravityQuotaFixtureError.duplicateBucketIdentity) {
            try AntigravityQuotaFixtureDecoder.decode(
                fixture(groups: [group("group-a", buckets: [
                    bucket("bucket-a", remaining: 0.5, reset: nil),
                    bucket("bucket-a", remaining: 0.4, reset: nil),
                ])])
            )
        }
        #expect(throws: AntigravityQuotaFixtureError.unsupportedVersion) {
            try AntigravityQuotaFixtureDecoder.decode(
                fixture(groups: [group("group-a", buckets: [bucket("bucket-a", remaining: 0.5, reset: nil)])]),
                cliVersion: "future"
            )
        }
    }

    @Test
    func noValidQuotaFailsClosedAndCreditsRemainDeferred() {
        #expect(throws: AntigravityQuotaFixtureError.noValidQuota) {
            try AntigravityQuotaFixtureDecoder.decode(fixture(groups: []))
        }
        #expect(AntigravityAdmissionEvidence.m6G1RObservation.credits == .defer)
        #expect(AntigravityAdmissionEvidence.m6G1RObservation.creditReads == 0)
    }

    @Test
    func currentRecordsAgreeOnNoGoAndFounderReview() throws {
        let records = try currentDecisionRecords()

        for record in records {
            #expect(record.contains("NO-GO"))
            #expect(record.contains("CREDITS DEFER"))
            #expect(record.contains("Founder source-direction decision"))
            #expect(!record.contains("synthetic-private@example.invalid"))
            #expect(!record.contains("/Users/juliushe/.local/bin/agy"))
        }
    }

    private func durableRecords() throws -> [String] {
        try [
            source("source/UMA M6 Antigravity Local Source Dossier.md"),
            source("source/UMA M6 Antigravity Admission Decision.md"),
            source("source/UMA M6 Antigravity Privacy Contract.md"),
            source("source/UMA M6 Antigravity QA Issue Ledger.md"),
            source("source/UMA M6 Antigravity Setup Evidence.md"),
        ]
    }

    private func currentDecisionRecords() throws -> [String] {
        try [
            source("source/UMA M6 Antigravity Local Source Dossier.md"),
            source("source/UMA M6 Antigravity Admission Decision.md"),
            source("source/UMA M6 Antigravity Privacy Contract.md"),
            source("source/UMA M6 Antigravity QA Issue Ledger.md"),
        ]
    }

    private func fixture(
        groups: [[String: Any]],
        envelopeExtras: [String: Any] = [:]
    ) throws -> Data {
        var envelope = envelopeExtras
        envelope["command"] = [
            "name": "usage",
            "data": [
                "description": "Synthetic quota fixture",
                "groups": groups,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    private func group(
        _ name: String,
        buckets: [[String: Any]]
    ) -> [String: Any] {
        [
            "name": name,
            "description": "Synthetic group",
            "buckets": buckets,
        ]
    }

    private func bucket(
        _ id: String,
        remaining: Double,
        reset: String?
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "name": "Synthetic label",
            "remaining_fraction": remaining,
            "window": "five-hour",
        ]
        if let reset {
            result["reset_time"] = reset
        }
        return result
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

private enum AntigravityAdmissionDecision: Equatable {
    case go
    case conditionalGo
    case setupRequired
    case noGo
}

private enum AntigravityEvidenceState: Equatable {
    case present
    case absent
    case unavailable
}

private enum AntigravitySourceClass: Equatable {
    case officialCLI
}

private enum AntigravityAuthenticationState: Equatable {
    case authenticated
    case loginRequired
    case sessionExpired
    case unobservable
}

private enum AntigravityCreditsState: Equatable {
    case go
    case conditional
    case `defer`
    case noGo
}

private struct AntigravityAdmissionEvidence: Equatable {
    var pathLookup: AntigravityEvidenceState
    var documentedPath: AntigravityEvidenceState
    var application: AntigravityEvidenceState
    var installedVersion: AntigravityEvidenceState
    var installedHelp: AntigravityEvidenceState
    var signature: AntigravityEvidenceState
    var gatekeeper: AntigravityEvidenceState
    var liveSchema: AntigravityEvidenceState
    var remainingSemantics: AntigravityEvidenceState
    var resetSemantics: AntigravityEvidenceState
    var structuralStability: AntigravityEvidenceState
    var identityStability: AntigravityEvidenceState
    var privacyProjection: AntigravityEvidenceState
    var boundedLifecycle: AntigravityEvidenceState
    var noProviderWork: AntigravityEvidenceState
    var currentDeviceBrowserBehavior: AntigravityEvidenceState
    var sourceClass: AntigravitySourceClass
    var publicStructuredPrintContract: Bool
    var authentication: AntigravityAuthenticationState
    var credits: AntigravityCreditsState
    var quotaReads: Int
    var creditReads: Int
    var providerPrompts: Int
    var providerTasks: Int
    var intentionalSpend: Int
    var testedQuotaArgumentVector: [String]?
    var creditValue: Decimal?
    var creditPercentage: Double?
    var productionConnectorImplemented: Bool

    static let m6G1Snapshot = AntigravityAdmissionEvidence(
        pathLookup: .absent,
        documentedPath: .absent,
        application: .present,
        installedVersion: .unavailable,
        installedHelp: .unavailable,
        signature: .unavailable,
        gatekeeper: .unavailable,
        liveSchema: .unavailable,
        remainingSemantics: .unavailable,
        resetSemantics: .unavailable,
        structuralStability: .unavailable,
        identityStability: .unavailable,
        privacyProjection: .unavailable,
        boundedLifecycle: .unavailable,
        noProviderWork: .unavailable,
        currentDeviceBrowserBehavior: .unavailable,
        sourceClass: .officialCLI,
        publicStructuredPrintContract: true,
        authentication: .unobservable,
        credits: .defer,
        quotaReads: 0,
        creditReads: 0,
        providerPrompts: 0,
        providerTasks: 0,
        intentionalSpend: 0,
        testedQuotaArgumentVector: nil,
        creditValue: nil,
        creditPercentage: nil,
        productionConnectorImplemented: false
    )

    static let m6G1RObservation = AntigravityAdmissionEvidence(
        pathLookup: .present,
        documentedPath: .present,
        application: .present,
        installedVersion: .present,
        installedHelp: .present,
        signature: .unavailable,
        gatekeeper: .unavailable,
        liveSchema: .present,
        remainingSemantics: .present,
        resetSemantics: .present,
        structuralStability: .unavailable,
        identityStability: .unavailable,
        privacyProjection: .present,
        boundedLifecycle: .present,
        noProviderWork: .unavailable,
        currentDeviceBrowserBehavior: .present,
        sourceClass: .officialCLI,
        publicStructuredPrintContract: true,
        authentication: .authenticated,
        credits: .defer,
        quotaReads: 3,
        creditReads: 0,
        providerPrompts: 0,
        providerTasks: 0,
        intentionalSpend: 0,
        testedQuotaArgumentVector: [
            "$HOME/.local/bin/agy",
            "--output-format",
            "json",
            "-p",
            "/usage",
        ],
        creditValue: nil,
        creditPercentage: nil,
        productionConnectorImplemented: false
    )
}

private struct AntigravitySanitizedProjection: Equatable {
    var installed: Bool
    var quotaReads: Int
}

private enum AntigravityAdmissionHarness {
    static func decide(
        _ evidence: AntigravityAdmissionEvidence
    ) -> AntigravityAdmissionDecision {
        guard evidence.pathLookup == .present,
              evidence.documentedPath == .present
        else {
            return evidence.sourceClass == .officialCLI
                ? .setupRequired
                : .noGo
        }

        guard evidence.authentication == .authenticated,
              evidence.liveSchema == .present,
              evidence.remainingSemantics == .present,
              evidence.structuralStability == .present,
              evidence.identityStability == .present,
              evidence.privacyProjection == .present,
              evidence.boundedLifecycle == .present,
              evidence.noProviderWork == .present
        else {
            return .noGo
        }

        return evidence.resetSemantics == .present ? .go : .conditionalGo
    }

    static func nextTask(
        for evidence: AntigravityAdmissionEvidence
    ) -> String {
        switch decide(evidence) {
        case .go, .conditionalGo:
            "M6-G2"
        case .setupRequired:
            "M6-SETUP-G1"
        case .noGo:
            "Founder source-direction decision"
        }
    }

    static func sanitize(
        _ raw: [String: Any]
    ) -> AntigravitySanitizedProjection {
        AntigravitySanitizedProjection(
            installed: raw["installed"] as? Bool ?? false,
            quotaReads: 0
        )
    }
}

private struct AntigravityQuotaProjection: Equatable {
    var buckets: [AntigravityQuotaBucketProjection]
}

private struct AntigravityQuotaBucketProjection: Equatable {
    var stableID: String
    var remainingPercent: Double
    var hasReset: Bool
}

private enum AntigravityQuotaFixtureError: Error, Equatable {
    case malformedJSON
    case unsupportedVersion
    case missingQuotaContainer
    case invalidBucket
    case duplicateBucketIdentity
    case noValidQuota
}

private enum AntigravityQuotaFixtureDecoder {
    static func decode(
        _ data: Data,
        cliVersion: String = "1.1.11"
    ) throws -> AntigravityQuotaProjection {
        guard cliVersion == "1.1.11" else {
            throw AntigravityQuotaFixtureError.unsupportedVersion
        }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AntigravityQuotaFixtureError.malformedJSON
        }

        guard let object = root as? [String: Any],
              let command = object["command"] as? [String: Any],
              command["name"] as? String == "usage",
              let commandData = command["data"] as? [String: Any],
              let groups = commandData["groups"] as? [[String: Any]]
        else {
            throw AntigravityQuotaFixtureError.missingQuotaContainer
        }

        var identities = Set<String>()
        var buckets: [AntigravityQuotaBucketProjection] = []

        for group in groups {
            guard let groupName = safeIdentifier(group["name"]),
                  let rawBuckets = group["buckets"] as? [[String: Any]]
            else {
                throw AntigravityQuotaFixtureError.invalidBucket
            }

            for rawBucket in rawBuckets {
                guard let bucketID = safeIdentifier(rawBucket["id"]),
                      let window = safeIdentifier(rawBucket["window"]),
                      let number = rawBucket["remaining_fraction"] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID()
                else {
                    throw AntigravityQuotaFixtureError.invalidBucket
                }

                let remainingFraction = number.doubleValue
                guard remainingFraction.isFinite,
                      (0...1).contains(remainingFraction)
                else {
                    throw AntigravityQuotaFixtureError.invalidBucket
                }

                let hasReset: Bool
                if let reset = rawBucket["reset_time"] {
                    guard let resetString = reset as? String,
                          iso8601Date(resetString) != nil
                    else {
                        throw AntigravityQuotaFixtureError.invalidBucket
                    }
                    hasReset = true
                } else {
                    hasReset = false
                }

                let stableID = "\(groupName)|\(bucketID)|\(window)"
                guard identities.insert(stableID).inserted else {
                    throw AntigravityQuotaFixtureError.duplicateBucketIdentity
                }

                buckets.append(
                    .init(
                        stableID: stableID,
                        remainingPercent: remainingFraction * 100,
                        hasReset: hasReset
                    )
                )
            }
        }

        guard !buckets.isEmpty else {
            throw AntigravityQuotaFixtureError.noValidQuota
        }
        return AntigravityQuotaProjection(buckets: buckets)
    }

    private static func safeIdentifier(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.count <= 64,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && (
                      CharacterSet.alphanumerics.contains(scalar)
                          || "-_.:".unicodeScalars.contains(scalar)
                  )
              })
        else {
            return nil
        }
        return value
    }

    private static func iso8601Date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
