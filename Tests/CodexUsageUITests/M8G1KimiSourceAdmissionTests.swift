import Foundation
import Testing

@Suite("M8 G1/G1R Kimi source admission")
struct M8G1KimiSourceAdmissionTests {
    @Test
    func currentDeviceIsNoGoAfterObservationCapExhaustion() {
        let evidence = KimiAdmissionEvidence.currentDevice

        #expect(evidence.officialCLICandidate)
        #expect(evidence.cliInstalled)
        #expect(!evidence.setupPrerequisiteIsOnlyCurrentGate)
        #expect(!evidence.cliSourceObserved)
        #expect(evidence.quotaSourceObservations == evidence.observationCap)
        #expect(evidence.successfulSanitizedObservations == 0)
        #expect(KimiAdmissionHarness.decide(evidence) == .noGo)
        #expect(KimiAdmissionHarness.nextTask(for: evidence) == "Founder source-direction decision")
    }

    @Test
    func currentChannelsRemainUnadmitted() {
        let evidence = KimiAdmissionEvidence.currentDevice

        #expect(evidence.sharedMembership == .missing)
        #expect(evidence.kimiCodeLimits == .noGo)
        #expect(evidence.extraUsage == .unreadable)
        #expect(evidence.accountMode == .unknownUnsupported)
    }

    @Test
    func setupRequiredNeedsAnOfficialRecoverableSource() {
        var evidence = KimiAdmissionEvidence.currentDevice
        evidence.cliInstalled = false
        evidence.setupPrerequisiteIsOnlyCurrentGate = true
        #expect(KimiAdmissionHarness.decide(evidence) == .setupRequired)

        evidence.officialCLICandidate = false
        #expect(KimiAdmissionHarness.decide(evidence) == .noGo)

        evidence = .currentDevice
        evidence.cliInstalled = false
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
        #expect(KimiAdmissionHarness.nextTask(for: evidence) == "Founder source-direction decision")
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
    func promptModeIsRejectedAndBuiltInSubmitRequiresPositiveRecognition() {
        let evidence = KimiAdmissionEvidence.currentDevice

        #expect(evidence.usageIsDocumentedInteractiveTUI)
        #expect(evidence.promptModeIsStructuredAgentMode)
        #expect(!evidence.documentedStandaloneStructuredUsage)
        #expect(evidence.positiveBuiltinGate)
        #expect(!KimiAdmissionHarness.acceptsPromptModeAsUsage(evidence))
    }

    @Test
    func operationAccountingIsExactlyCappedWithNoProviderWork() {
        let evidence = KimiAdmissionEvidence.currentDevice

        #expect(evidence.quotaSourceObservations == 3)
        #expect(evidence.observationCap == 3)
        #expect(evidence.successfulSanitizedObservations == 0)
        #expect(evidence.providerPrompts == 0)
        #expect(evidence.providerTasks == 0)
        #expect(evidence.intentionalSpend == 0)
        #expect(evidence.loginBrowserActions == 0)
        #expect(evidence.credentialReads == 0)
        #expect(evidence.noProviderWork)
        #expect(!evidence.noAttributableDecrement)
    }

    @Test
    func normalizationPreservesProviderSemantics() {
        #expect(KimiAdmissionHarness.remainingPercent(fromUsedPercent: 0) == 100)
        #expect(KimiAdmissionHarness.remainingPercent(fromUsedPercent: 37.5) == 62.5)
        #expect(KimiAdmissionHarness.remainingPercent(fromUsedPercent: 100) == 0)
        #expect(KimiAdmissionHarness.remainingFraction(used: 3, total: 12) == 0.75)
        #expect(KimiAdmissionHarness.remainingFraction(used: 3, total: 0) == nil)
        #expect(KimiAdmissionHarness.normalizesMissingAsZero == false)
        #expect(KimiAdmissionHarness.normalizesUnlimitedAsPercent == false)
        #expect(KimiAdmissionHarness.normalizesNativeMoneyAsPercent == false)
    }

    @Test
    func liveIdentityAndRepeatabilityAreMandatory() {
        var evidence = KimiAdmissionEvidence.admissibleSynthetic
        evidence.stableIdentities = false
        #expect(KimiAdmissionHarness.decide(evidence) == .noGo)

        evidence = .admissibleSynthetic
        evidence.repeatedObservations = false
        #expect(KimiAdmissionHarness.decide(evidence) == .noGo)

        #expect(!KimiAdmissionHarness.acceptsIdentityAuthority("array-order"))
        #expect(!KimiAdmissionHarness.acceptsIdentityAuthority("reset-time"))
        #expect(!KimiAdmissionHarness.acceptsIdentityAuthority("quota-value"))
        #expect(KimiAdmissionHarness.acceptsIdentityAuthority("provider-stable-id"))
    }

    @Test
    func sanitizationProjectsOnlyDurableAllowlist() {
        let raw: [String: Any] = [
            "sourceClass": "official-cli",
            "observations": 3,
            "successfulObservations": 0,
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

        #expect(projection == .init(
            sourceClass: "official-cli",
            observations: 3,
            successfulObservations: 0
        ))
        for rejected in [
            "synthetic-private", "synthetic-account", "synthetic-token",
            "synthetic-cookie", "synthetic-exact-value", "synthetic-reset-date",
            "synthetic/private", "synthetic-prompt", "synthetic-response",
        ] {
            #expect(!reflection.contains(rejected))
        }
    }

    @Test
    func durableRecordsAgreeOnDecisionChannelsAccountingAndRouting() throws {
        let records = try durableRecords()

        for record in records {
            #expect(record.contains("NO-GO"))
            #expect(record.contains("M8-G2 remains locked"))
            #expect(!record.contains("synthetic-private@example.invalid"))
            #expect(!record.contains("/Users/"))
        }

        let combined = records.joined(separator: "\n")
        #expect(combined.contains("SHARED MEMBERSHIP: MISSING"))
        #expect(combined.contains("KIMI CODE LIMITS: NO-GO"))
        #expect(combined.contains("EXTRA USAGE: UNREADABLE"))
        #expect(combined.contains("3 / 3"))
        #expect(combined.contains("Successful sanitized observations retained: 0"))
        #expect(combined.contains("Founder source-direction decision"))
        #expect(combined.contains("M8-WEB-G1 remains locked"))
    }

    @Test
    func durableRecordsRejectPrivateEstimatedAndAgentSources() throws {
        let combined = try durableRecords().joined(separator: "\n").lowercased()

        for required in [
            "api key", "oauth", "keychain", "cookies", "browser profiles",
            "private/internal", "manual values", "screenshots/ocr",
            "raw cli/tui output", "process command-line", "prompt mode",
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
        #expect(ledger.contains("M5 frozen files changed: NO"))
        #expect(ledger.contains("Package scripts changed: NO"))
    }

    @Test
    func publicContractDoesNotBecomeLiveAdmissionEvidence() throws {
        let dossier = try source("source/UMA M8 Kimi Local Source Dossier.md")

        #expect(dossier.contains("official contract facts, not current-account live admission"))
        #expect(dossier.contains("No channel is admitted from documentation alone"))
        #expect(dossier.contains("did not retain one successful sanitized"))
        #expect(dossier.contains("could not fall through to an Agent"))
    }

    @Test
    func taskOwnedTrustMarkerHasExactCleanupContract() throws {
        let privacy = try source("source/UMA M8 Kimi Privacy Contract.md")

        #expect(privacy.contains("workspace-trust choice"))
        #expect(privacy.contains("remove only that exact marker"))
        #expect(privacy.contains("No provider-owned authentication or unrelated Kimi state may be modified"))
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
    var noAttributableDecrement: Bool
    var optionalResetMissing: Bool
    var prohibitedCredentialRoute: Bool
    var privateEndpointRequired: Bool
    var providerWorkCreated: Bool
    var usageIsDocumentedInteractiveTUI: Bool
    var promptModeIsStructuredAgentMode: Bool
    var documentedStandaloneStructuredUsage: Bool
    var positiveBuiltinGate: Bool
    var quotaSourceObservations: Int
    var successfulSanitizedObservations: Int
    var observationCap: Int
    var providerPrompts: Int
    var providerTasks: Int
    var intentionalSpend: Int
    var loginBrowserActions: Int
    var credentialReads: Int

    static let currentDevice = KimiAdmissionEvidence(
        officialCLICandidate: true,
        cliInstalled: true,
        setupPrerequisiteIsOnlyCurrentGate: false,
        cliSourceObserved: false,
        officialBrowserCandidate: true,
        sharedMembership: .missing,
        kimiCodeLimits: .noGo,
        extraUsage: .unreadable,
        accountMode: .unknownUnsupported,
        stableIdentities: false,
        repeatedObservations: false,
        noProviderWork: true,
        noAttributableDecrement: false,
        optionalResetMissing: false,
        prohibitedCredentialRoute: false,
        privateEndpointRequired: false,
        providerWorkCreated: false,
        usageIsDocumentedInteractiveTUI: true,
        promptModeIsStructuredAgentMode: true,
        documentedStandaloneStructuredUsage: false,
        positiveBuiltinGate: true,
        quotaSourceObservations: 3,
        successfulSanitizedObservations: 0,
        observationCap: 3,
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
        noAttributableDecrement: true,
        optionalResetMissing: false,
        prohibitedCredentialRoute: false,
        privateEndpointRequired: false,
        providerWorkCreated: false,
        usageIsDocumentedInteractiveTUI: true,
        promptModeIsStructuredAgentMode: true,
        documentedStandaloneStructuredUsage: false,
        positiveBuiltinGate: true,
        quotaSourceObservations: 2,
        successfulSanitizedObservations: 2,
        observationCap: 3,
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
    let successfulObservations: Int
}

private enum KimiAdmissionHarness {
    static let normalizesMissingAsZero = false
    static let normalizesUnlimitedAsPercent = false
    static let normalizesNativeMoneyAsPercent = false

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
            && evidence.successfulSanitizedObservations >= 2

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

    static func remainingPercent(fromUsedPercent usedPercent: Double) -> Double? {
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else { return nil }
        return 100 - usedPercent
    }

    static func remainingFraction(used: Decimal, total: Decimal) -> Decimal? {
        guard total > 0, used >= 0, used <= total else { return nil }
        return (total - used) / total
    }

    static func acceptsIdentityAuthority(_ authority: String) -> Bool {
        authority == "provider-stable-id"
    }

    static func sanitize(_ raw: [String: Any]) -> KimiSanitizedProjection {
        KimiSanitizedProjection(
            sourceClass: raw["sourceClass"] as? String ?? "unavailable",
            observations: raw["observations"] as? Int ?? 0,
            successfulObservations: raw["successfulObservations"] as? Int ?? 0
        )
    }
}
