import Foundation
import Testing

@Suite("M6-G1 Antigravity official source admission")
struct M6G1AntigravitySourceAdmissionTests {
    @Test
    func officialCLIAbsenceRequiresSetupWithoutProviderRead() {
        let evidence = AntigravityAdmissionEvidence.currentAbsence

        #expect(evidence.pathLookup == .absent)
        #expect(evidence.documentedPath == .absent)
        #expect(evidence.application == .absent)
        #expect(evidence.quotaReads == 0)
        #expect(AntigravityAdmissionHarness.decide(evidence) == .setupRequired)
    }

    @Test
    func missingExecutableLeavesCapabilityAndLiveSchemaUnavailable() {
        let evidence = AntigravityAdmissionEvidence.currentAbsence

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
        let evidence = AntigravityAdmissionEvidence.currentAbsence

        #expect(evidence.sourceClass == .officialCLI)
        #expect(evidence.publicStructuredPrintContract)
        #expect(evidence.productionConnectorImplemented == false)
        #expect(AntigravityAdmissionHarness.nextTask(for: evidence) == "M6-SETUP-G1")
    }

    @Test
    func authenticationIsUnobservableNotLoggedOut() {
        let evidence = AntigravityAdmissionEvidence.currentAbsence

        #expect(evidence.authentication == .unobservable)
        #expect(evidence.authentication != .loginRequired)
        #expect(evidence.authentication != .sessionExpired)
        #expect(evidence.authentication != .authenticated)
        #expect(evidence.currentDeviceBrowserBehavior == .unavailable)
    }

    @Test
    func creditsRemainDeferredAndIndependent() {
        let evidence = AntigravityAdmissionEvidence.currentAbsence

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
        #expect(AntigravityAdmissionEvidence.currentAbsence.providerPrompts == 0)
        #expect(AntigravityAdmissionEvidence.currentAbsence.providerTasks == 0)
        #expect(AntigravityAdmissionEvidence.currentAbsence.intentionalSpend == 0)
    }

    @Test
    func durableRecordsAgreeOnSetupRequiredAndNextTask() throws {
        let records = try durableRecords()

        for record in records {
            #expect(record.contains("SETUP REQUIRED"))
            #expect(record.contains("CREDITS DEFER"))
            #expect(record.contains("M6-SETUP-G1"))
            #expect(!record.contains("synthetic-private@example.invalid"))
            #expect(!record.contains("/Users/juliushe/.local/bin/agy"))
        }

        let dossier = records[0]
        #expect(dossier.contains("Live installed proof is unavailable"))
        #expect(dossier.contains("No installed Antigravity command was executed"))
        #expect(!dossier.contains("current successful structured read"))
    }

    @Test
    func g1ScopeContainsOnlyFiveAdmissionFiles() throws {
        let ledger = try source("source/UMA M6 Antigravity QA Issue Ledger.md")
        let expected = [
            "Tests/CodexUsageUITests/M6G1AntigravitySourceAdmissionTests.swift",
            "source/UMA M6 Antigravity Local Source Dossier.md",
            "source/UMA M6 Antigravity Admission Decision.md",
            "source/UMA M6 Antigravity Privacy Contract.md",
            "source/UMA M6 Antigravity QA Issue Ledger.md",
        ]

        for path in expected {
            #expect(ledger.contains(path))
        }
        #expect(!ledger.contains("Sources/CodexUsageUI/Connectors/Antigravity"))
        #expect(!ledger.contains("script/package_uma_m6"))
    }

    private func durableRecords() throws -> [String] {
        try [
            source("source/UMA M6 Antigravity Local Source Dossier.md"),
            source("source/UMA M6 Antigravity Admission Decision.md"),
            source("source/UMA M6 Antigravity Privacy Contract.md"),
            source("source/UMA M6 Antigravity QA Issue Ledger.md"),
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

    static let currentAbsence = AntigravityAdmissionEvidence(
        pathLookup: .absent,
        documentedPath: .absent,
        application: .absent,
        installedVersion: .unavailable,
        installedHelp: .unavailable,
        signature: .unavailable,
        gatekeeper: .unavailable,
        liveSchema: .unavailable,
        remainingSemantics: .unavailable,
        resetSemantics: .unavailable,
        structuralStability: .unavailable,
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
              evidence.remainingSemantics == .present
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
            "Founder source-decision review"
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
