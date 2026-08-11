import Foundation
import Testing

@Suite("M8 G1 Kimi unified source admission")
struct M8G1KimiSourceAdmissionTests {
    @Test
    func currentDeviceRoutesOnlyToOfficialSetup() {
        let evidence = KimiAdmissionEvidence.currentDevice

        #expect(evidence.officialCLICandidate)
        #expect(evidence.cliInstalled == false)
        #expect(evidence.setupPrerequisiteIsOnlyCurrentGate)
        #expect(KimiAdmissionHarness.decide(evidence) == .setupRequired)
        #expect(KimiAdmissionHarness.nextTask(for: evidence) == "M8-SETUP-G1")
    }

    @Test
    func currentChannelsRemainUnadmitted() {
        let evidence = KimiAdmissionEvidence.currentDevice

        #expect(evidence.sharedMembership == .conditional)
        #expect(evidence.kimiCodeLimits == .conditional)
        #expect(evidence.extraUsage == .unreadable)
        #expect(evidence.accountMode == .unknownUnsupported)
    }

    @Test
    func setupRequiredNeedsAnOfficialRecoverableSource() {
        var evidence = KimiAdmissionEvidence.currentDevice
        #expect(KimiAdmissionHarness.decide(evidence) == .setupRequired)

        evidence.officialCLICandidate = false
        #expect(KimiAdmissionHarness.decide(evidence) == .noGo)

        evidence = .currentDevice
        evidence.setupPrerequisiteIsOnlyCurrentGate = false
        #expect(KimiAdmissionHarness.decide(evidence) == .noGo)
    }

    @Test
    func sourceExpansionRequiresAnAdmittedPartialCLI() {
        var evidence = KimiAdmissionEvidence.admissibleSynthetic
        evidence.sharedMembership = .missing
        evidence.extraUsage = .unreadable
        evidence.officialBrowserCandidate = true

        #expect(KimiAdmissionHarness.decide(evidence) == .sourceExpansionRequired)
        #expect(KimiAdmissionHarness.nextTask(for: evidence) == "M8-WEB-G1")

        evidence.cliSourceObserved = false
        #expect(KimiAdmissionHarness.decide(evidence) == .noGo)
    }

    @Test
    func goRequiresUnifiedMembershipAndContinuationTruth() {
        let evidence = KimiAdmissionEvidence.admissibleSynthetic
        #expect(KimiAdmissionHarness.decide(evidence) == .go)
        #expect(KimiAdmissionHarness.nextTask(for: evidence) == "M8-G2")

        var missingShared = evidence
        missingShared.sharedMembership = .missing
        missingShared.officialBrowserCandidate = false
        #expect(KimiAdmissionHarness.decide(missingShared) == .noGo)

        var unreadableContinuation = evidence
        unreadableContinuation.extraUsage = .unreadable
        unreadableContinuation.officialBrowserCandidate = false
        #expect(KimiAdmissionHarness.decide(unreadableContinuation) == .noGo)
    }

    @Test
    func onlyOptionalMetadataCanYieldImplementationReadyConditionalGo() {
        var evidence = KimiAdmissionEvidence.admissibleSynthetic
        evidence.optionalResetMissing = true

        #expect(KimiAdmissionHarness.decide(evidence) == .conditionalGo)
        #expect(KimiAdmissionHarness.nextTask(for: evidence) == "M8-G2")

        evidence.sharedMembership = .missing
        #expect(KimiAdmissionHarness.decide(evidence) == .sourceExpansionRequired)
    }

    @Test
    func credentialsPrivateRoutesAndProviderWorkFailClosed() {
        var credential = KimiAdmissionEvidence.admissibleSynthetic
        credential.prohibitedCredentialRoute = true
        #expect(KimiAdmissionHarness.decide(credential) == .noGo)

        var privateEndpoint = KimiAdmissionEvidence.admissibleSynthetic
        privateEndpoint.privateEndpointRequired = true
        #expect(KimiAdmissionHarness.decide(privateEndpoint) == .noGo)

        var providerWork = KimiAdmissionEvidence.admissibleSynthetic
        providerWork.providerWorkCreated = true
        #expect(KimiAdmissionHarness.decide(providerWork) == .noGo)

        var spend = KimiAdmissionEvidence.admissibleSynthetic
        spend.intentionalSpend = 1
        #expect(KimiAdmissionHarness.decide(spend) == .noGo)
    }

    @Test
    func promptModeIsNeverAcceptedAsUsageControl() {
        let evidence = KimiAdmissionEvidence.currentDevice

        #expect(evidence.usageIsDocumentedInteractiveTUI)
        #expect(evidence.promptModeIsStructuredAgentMode)
        #expect(evidence.documentedStandaloneStructuredUsage == false)
        #expect(KimiAdmissionHarness.acceptsPromptModeAsUsage(evidence) == false)
    }

    @Test
    func operationAccountingIsZero() {
        let evidence = KimiAdmissionEvidence.currentDevice

        #expect(evidence.quotaSourceObservations == 0)
        #expect(evidence.providerPrompts == 0)
        #expect(evidence.providerTasks == 0)
        #expect(evidence.intentionalSpend == 0)
        #expect(evidence.loginBrowserActions == 0)
        #expect(evidence.credentialReads == 0)
    }

    @Test
    func sanitizationProjectsOnlyDurableAllowlist() {
        let raw: [String: Any] = [
            "sourceClass": "official-cli",
            "observations": 0,
            "email": "synthetic-private@example.invalid",
            "accountID": "synthetic-account",
            "token": "synthetic-token",
            "cookie": "synthetic-cookie",
            "quotaValue": "synthetic-exact-value",
            "resetDate": "synthetic-reset-date",
            "workspace": "/synthetic/private/workspace",
            "prompt": "synthetic-prompt",
            "response": "synthetic-response",
        ]

        let projection = KimiAdmissionHarness.sanitize(raw)
        let reflection = String(reflecting: projection)

        #expect(projection == .init(sourceClass: "official-cli", observations: 0))
        for rejected in [
            "synthetic-private", "synthetic-account", "synthetic-token",
            "synthetic-cookie", "synthetic-exact-value", "synthetic-reset-date",
            "synthetic/private", "synthetic-prompt", "synthetic-response",
        ] {
            #expect(!reflection.contains(rejected))
        }
    }

    @Test
    func durableRecordsAgreeOnDecisionChannelsAndRouting() throws {
        let records = try durableRecords()

        for record in records {
            #expect(record.contains("SETUP REQUIRED"))
            #expect(record.contains("M8-G2 remains locked"))
            #expect(!record.contains("synthetic-private@example.invalid"))
            #expect(!record.contains("/Users/"))
        }

        let combined = records.joined(separator: "\n")
        #expect(combined.contains("SHARED MEMBERSHIP: CONDITIONAL"))
        #expect(combined.contains("KIMI CODE LIMITS: CONDITIONAL"))
        #expect(combined.contains("EXTRA USAGE: UNREADABLE"))
        #expect(combined.contains("M8-SETUP-G1"))
        #expect(combined.contains("quota/source observations: 0"))
    }

    @Test
    func durableRecordsRejectPrivateAndEstimatedSources() throws {
        let combined = try durableRecords().joined(separator: "\n").lowercased()

        for required in [
            "api key", "oauth", "keychain", "cookie", "browser-profile",
            "private/internal", "manual values", "screenshot/ocr",
            "raw cli/tui output", "full process `argv`",
        ] {
            #expect(combined.contains(required))
        }
    }

    @Test
    func qaLedgerLocksExactFiveFileScope() throws {
        let ledger = try source("source/UMA M8 Kimi QA Issue Ledger.md")
        let expected = [
            "source/UMA M8 Kimi Local Source Dossier.md",
            "source/UMA M8 Kimi Admission Decision.md",
            "source/UMA M8 Kimi Privacy Contract.md",
            "source/UMA M8 Kimi QA Issue Ledger.md",
            "Tests/CodexUsageUITests/M8G1KimiSourceAdmissionTests.swift",
        ]

        for path in expected {
            #expect(ledger.contains(path))
        }
        #expect(ledger.contains("Production source files changed: NO"))
        #expect(ledger.contains("Existing provider mechanisms changed: NO"))
        #expect(ledger.contains("Package scripts changed: NO"))
    }

    @Test
    func publicDocumentationDoesNotBecomeLiveAdmission() throws {
        let dossier = try source("source/UMA M8 Kimi Local Source Dossier.md")

        #expect(dossier.contains("documentation evidence, not an"))
        #expect(dossier.contains("installed version claim"))
        #expect(dossier.contains("No channel is admitted from documentation alone"))
        #expect(dossier.contains("future `/usage` read remains `unproven`"))
    }

    private func durableRecords() throws -> [String] {
        try [
            source("source/UMA M8 Kimi Local Source Dossier.md"),
            source("source/UMA M8 Kimi Admission Decision.md"),
            source("source/UMA M8 Kimi Privacy Contract.md"),
            source("source/UMA M8 Kimi QA Issue Ledger.md"),
        ]
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(path),
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

private enum KimiOverallDecision: Equatable {
    case go
    case conditionalGo
    case setupRequired
    case sourceExpansionRequired
    case noGo
}

private enum KimiChannelDecision: Equatable {
    case go
    case conditional
    case missing
    case disabled
    case absent
    case unreadable
    case noGo
}

private enum KimiAccountMode: Equatable {
    case free
    case mergedMembership
    case splitMembership
    case kimiCodePlan
    case businessEnterprise
    case unknownUnsupported
}

private struct KimiAdmissionEvidence {
    var officialCLICandidate: Bool
    var cliInstalled: Bool
    var setupPrerequisiteIsOnlyCurrentGate: Bool
    var cliSourceObserved: Bool
    var officialBrowserCandidate: Bool
    var sharedMembership: KimiChannelDecision
    var kimiCodeLimits: KimiChannelDecision
    var extraUsage: KimiChannelDecision
    var accountMode: KimiAccountMode
    var stableIdentities: Bool
    var repeatedObservations: Bool
    var noProviderWork: Bool
    var optionalResetMissing: Bool
    var prohibitedCredentialRoute: Bool
    var privateEndpointRequired: Bool
    var providerWorkCreated: Bool
    var usageIsDocumentedInteractiveTUI: Bool
    var promptModeIsStructuredAgentMode: Bool
    var documentedStandaloneStructuredUsage: Bool
    var quotaSourceObservations: Int
    var providerPrompts: Int
    var providerTasks: Int
    var intentionalSpend: Int
    var loginBrowserActions: Int
    var credentialReads: Int

    static let currentDevice = KimiAdmissionEvidence(
        officialCLICandidate: true,
        cliInstalled: false,
        setupPrerequisiteIsOnlyCurrentGate: true,
        cliSourceObserved: false,
        officialBrowserCandidate: true,
        sharedMembership: .conditional,
        kimiCodeLimits: .conditional,
        extraUsage: .unreadable,
        accountMode: .unknownUnsupported,
        stableIdentities: false,
        repeatedObservations: false,
        noProviderWork: false,
        optionalResetMissing: false,
        prohibitedCredentialRoute: false,
        privateEndpointRequired: false,
        providerWorkCreated: false,
        usageIsDocumentedInteractiveTUI: true,
        promptModeIsStructuredAgentMode: true,
        documentedStandaloneStructuredUsage: false,
        quotaSourceObservations: 0,
        providerPrompts: 0,
        providerTasks: 0,
        intentionalSpend: 0,
        loginBrowserActions: 0,
        credentialReads: 0
    )

    static let admissibleSynthetic = KimiAdmissionEvidence(
        officialCLICandidate: true,
        cliInstalled: true,
        setupPrerequisiteIsOnlyCurrentGate: false,
        cliSourceObserved: true,
        officialBrowserCandidate: true,
        sharedMembership: .go,
        kimiCodeLimits: .go,
        extraUsage: .disabled,
        accountMode: .mergedMembership,
        stableIdentities: true,
        repeatedObservations: true,
        noProviderWork: true,
        optionalResetMissing: false,
        prohibitedCredentialRoute: false,
        privateEndpointRequired: false,
        providerWorkCreated: false,
        usageIsDocumentedInteractiveTUI: true,
        promptModeIsStructuredAgentMode: true,
        documentedStandaloneStructuredUsage: false,
        quotaSourceObservations: 2,
        providerPrompts: 0,
        providerTasks: 0,
        intentionalSpend: 0,
        loginBrowserActions: 0,
        credentialReads: 0
    )
}

private struct KimiSanitizedProjection: Equatable {
    let sourceClass: String
    let observations: Int
}

private enum KimiAdmissionHarness {
    static func decide(_ evidence: KimiAdmissionEvidence) -> KimiOverallDecision {
        if evidence.prohibitedCredentialRoute
            || evidence.privateEndpointRequired
            || evidence.providerWorkCreated
            || evidence.intentionalSpend > 0
        {
            return .noGo
        }

        if !evidence.cliInstalled {
            return evidence.officialCLICandidate && evidence.setupPrerequisiteIsOnlyCurrentGate
                ? .setupRequired
                : .noGo
        }

        let sourceCore = evidence.cliSourceObserved
            && evidence.stableIdentities
            && evidence.repeatedObservations
            && evidence.noProviderWork

        guard sourceCore else { return .noGo }

        let sharedReady = evidence.sharedMembership == .go
            || evidence.sharedMembership == .conditional
        let codeReady = evidence.kimiCodeLimits == .go
            || evidence.kimiCodeLimits == .conditional
        let extraReady = evidence.extraUsage == .go
            || evidence.extraUsage == .disabled
            || evidence.extraUsage == .absent

        if !sharedReady || !extraReady {
            return evidence.officialBrowserCandidate
                ? .sourceExpansionRequired
                : .noGo
        }

        guard codeReady else { return .noGo }
        return evidence.optionalResetMissing ? .conditionalGo : .go
    }

    static func nextTask(for evidence: KimiAdmissionEvidence) -> String {
        switch decide(evidence) {
        case .go, .conditionalGo:
            return "M8-G2"
        case .setupRequired:
            return "M8-SETUP-G1"
        case .sourceExpansionRequired:
            return "M8-WEB-G1"
        case .noGo:
            return "Founder source-direction decision"
        }
    }

    static func acceptsPromptModeAsUsage(_ evidence: KimiAdmissionEvidence) -> Bool {
        evidence.documentedStandaloneStructuredUsage
            && !evidence.promptModeIsStructuredAgentMode
    }

    static func sanitize(_ raw: [String: Any]) -> KimiSanitizedProjection {
        KimiSanitizedProjection(
            sourceClass: raw["sourceClass"] as? String ?? "unavailable",
            observations: raw["observations"] as? Int ?? 0
        )
    }
}
