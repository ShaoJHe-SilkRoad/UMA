import Foundation
import Testing

@Suite("M7 Cursor official source admission")
struct M7G1CursorSourceAdmissionTests {
    @Test
    func currentDeviceRequiresFounderFallbackDecision() {
        let evidence = CursorAdmissionEvidence.m7G1Observation

        #expect(evidence.installedApplication == .absent)
        #expect(evidence.installedCLI == .absent)
        #expect(evidence.documentedStructuredQuotaCommand == false)
        #expect(evidence.browserUsageSurface == .officialHumanVisible)
        #expect(CursorAdmissionHarness.decide(evidence) == .conditionalGo)
        #expect(
            CursorAdmissionHarness.nextTask(for: evidence)
                == "Founder provider-controlled browser fallback architecture decision"
        )
    }

    @Test
    func absentCLIAloneDoesNotBecomeSetupRequired() {
        var evidence = CursorAdmissionEvidence.m7G1Observation
        evidence.browserUsageSurface = .absent
        evidence.browserFallbackRequiresNewPrivacySurface = false

        #expect(evidence.installedCLI == .absent)
        #expect(evidence.documentedStructuredQuotaCommand == false)
        #expect(CursorAdmissionHarness.decide(evidence) == .noGo)
    }

    @Test
    func officialCLIUsageIsActivityNotPlanQuota() {
        let evidence = CursorAdmissionEvidence.m7G1Observation

        #expect(evidence.officialCLIExists)
        #expect(evidence.documentedUsageSlashCommand)
        #expect(evidence.usageSlashCommandSemantic == .activityStreaksAndStats)
        #expect(evidence.documentedStructuredQuotaCommand == false)
        #expect(evidence.currentQuota == .unavailable)
        #expect(evidence.nativeUnit == .unavailable)
    }

    @Test
    func structuredPrintModeIsAgentWorkNotQuotaTransport() {
        let evidence = CursorAdmissionEvidence.m7G1Observation

        #expect(evidence.agentPrintJSONExists)
        #expect(evidence.agentPrintModeCanUseTools)
        #expect(evidence.agentPrintModeIsQuotaRead == false)
        #expect(evidence.providerPrompts == 0)
        #expect(evidence.providerTasks == 0)
        #expect(evidence.intentionalSpend == 0)
    }

    @Test
    func statusAndHooksDoNotEstablishQuota() {
        let evidence = CursorAdmissionEvidence.m7G1Observation

        #expect(evidence.statusCommandSemantic == .authenticationOnly)
        #expect(evidence.hookSemantic == .agentLifecycleOnly)
        #expect(evidence.hookQuotaSchema == .unavailable)
    }

    @Test
    func adminAPIIsRejectedForCredentialIdentityAndScope() {
        let evidence = CursorAdmissionEvidence.m7G1Observation

        #expect(evidence.adminAPI == .officialButRejected)
        #expect(evidence.adminAPIRequiresCredential)
        #expect(evidence.adminAPIExposesIdentityAndEvents)
        #expect(evidence.adminAPIIsIndividualCurrentQuota == false)
        #expect(CursorAdmissionHarness.admitsAdminAPI(evidence) == false)
    }

    @Test
    func browserFallbackIsClassificationNotImplementationAdmission() {
        let evidence = CursorAdmissionEvidence.m7G1Observation

        #expect(evidence.browserUsageSurface == .officialHumanVisible)
        #expect(evidence.browserFallbackRequiresNewPrivacySurface)
        #expect(evidence.browserStructuredSchema == .unavailable)
        #expect(CursorAdmissionHarness.decide(evidence) == .conditionalGo)
        #expect(CursorAdmissionHarness.directImplementationUnlocked(evidence) == false)
    }

    @Test
    func setupRequiresAProvenAdmissibleSourceWithOnlySetupMissing() {
        var evidence = CursorAdmissionEvidence.admissibleSynthetic
        evidence.installedCLI = .absent
        evidence.setupPrerequisiteIsOnlyGap = true

        #expect(CursorAdmissionHarness.decide(evidence) == .setupRequired)

        evidence.documentedStructuredQuotaCommand = false
        #expect(CursorAdmissionHarness.decide(evidence) == .noGo)
    }

    @Test
    func goRequiresEveryMandatoryGate() {
        let admitted = CursorAdmissionEvidence.admissibleSynthetic
        #expect(CursorAdmissionHarness.decide(admitted) == .go)

        var missingIdentity = admitted
        missingIdentity.stablePoolIdentity = .unavailable
        #expect(CursorAdmissionHarness.decide(missingIdentity) == .noGo)

        var missingRepeatability = admitted
        missingRepeatability.repeatedStructure = .unavailable
        #expect(CursorAdmissionHarness.decide(missingRepeatability) == .noGo)

        var missingNoWork = admitted
        missingNoWork.noProviderWork = .unavailable
        #expect(CursorAdmissionHarness.decide(missingNoWork) == .noGo)
    }

    @Test
    func optionalMetadataIsTheOnlyDirectConditionalGap() {
        var evidence = CursorAdmissionEvidence.admissibleSynthetic
        evidence.optionalReset = .unavailable

        #expect(CursorAdmissionHarness.decide(evidence) == .conditionalGo)
        #expect(CursorAdmissionHarness.directImplementationUnlocked(evidence))

        evidence.currentQuota = .unavailable
        #expect(CursorAdmissionHarness.decide(evidence) == .noGo)
    }

    @Test
    func prohibitedCredentialRouteAlwaysFailsClosed() {
        var evidence = CursorAdmissionEvidence.admissibleSynthetic
        evidence.prohibitedCredentialRoute = true

        #expect(CursorAdmissionHarness.decide(evidence) == .noGo)
        #expect(CursorAdmissionHarness.directImplementationUnlocked(evidence) == false)
    }

    @Test
    func operationAccountingRemainsZero() {
        let evidence = CursorAdmissionEvidence.m7G1Observation

        #expect(evidence.authenticatedQuotaReads == 0)
        #expect(evidence.providerPrompts == 0)
        #expect(evidence.providerTasks == 0)
        #expect(evidence.intentionalSpend == 0)
        #expect(evidence.browserActions == 0)
        #expect(evidence.credentialReads == 0)
    }

    @Test
    func sanitizedProjectionRetainsNoPrivateMaterial() {
        let raw: [String: Any] = [
            "officialSurface": true,
            "quotaReads": 0,
            "email": "synthetic-private@example.invalid",
            "accountID": "synthetic-account",
            "token": "synthetic-token",
            "cookie": "synthetic-cookie",
            "workspace": "/synthetic/private/workspace",
            "prompt": "synthetic-prompt",
            "response": "synthetic-response",
        ]

        let projection = CursorAdmissionHarness.sanitize(raw)
        let reflection = String(reflecting: projection)

        #expect(projection == .init(officialSurface: true, quotaReads: 0))
        #expect(!reflection.contains("synthetic-private"))
        #expect(!reflection.contains("synthetic-account"))
        #expect(!reflection.contains("synthetic-token"))
        #expect(!reflection.contains("synthetic-cookie"))
        #expect(!reflection.contains("synthetic-prompt"))
        #expect(!reflection.contains("synthetic-response"))
    }

    @Test
    func sourcePriorityRemainsExact() {
        #expect(CursorAdmissionHarness.sourcePriority == [
            .officialStructuredLocal,
            .officialDocumentedCLI,
            .officialLocalHook,
            .providerControlledBrowser,
            .unsupported,
        ])
    }

    @Test
    func durableRecordsAgreeOnDecisionAndNextTask() throws {
        let records = try durableRecords()

        for record in records {
            #expect(record.contains("CONDITIONAL GO — FALLBACK ARCHITECTURE REQUIRES FOUNDER DECISION"))
            #expect(record.contains("Founder provider-controlled browser fallback architecture decision"))
            #expect(record.contains("Authenticated quota reads: 0/3"))
            #expect(!record.contains("synthetic-private@example.invalid"))
            #expect(!record.contains("/Users/"))
        }
    }

    @Test
    func durableRecordsRejectDirectRuntimeAndPrivateRoutes() throws {
        let records = try durableRecords()

        for record in records {
            #expect(record.contains("M7-G2 remains locked"))
            #expect(record.contains("API key"))
            #expect(record.contains("cookie"))
            #expect(record.contains("Keychain"))
            #expect(record.contains("private endpoint"))
        }
    }

    @Test
    func qaLedgerLocksExactFiveFileScope() throws {
        let ledger = try source("source/UMA M7 Cursor QA Issue Ledger.md")
        let expected = [
            "Tests/CodexUsageUITests/M7G1CursorSourceAdmissionTests.swift",
            "source/UMA M7 Cursor Local Source Dossier.md",
            "source/UMA M7 Cursor Admission Decision.md",
            "source/UMA M7 Cursor Privacy Contract.md",
            "source/UMA M7 Cursor QA Issue Ledger.md",
        ]

        for path in expected {
            #expect(ledger.contains(path))
        }
        #expect(ledger.contains("Production source files changed: NO"))
        #expect(ledger.contains("Browser extension files changed: NO"))
        #expect(ledger.contains("Package scripts changed: NO"))
    }

    @Test
    func currentDecisionDoesNotPublishUnobservedSchemaOrUnits() throws {
        let dossier = try source("source/UMA M7 Cursor Local Source Dossier.md")
        let decision = try source("source/UMA M7 Cursor Admission Decision.md")

        #expect(dossier.contains("Live schema: UNAVAILABLE"))
        #expect(dossier.contains("Native quota unit: UNAVAILABLE"))
        #expect(dossier.contains("Stable pool identity: UNAVAILABLE"))
        #expect(decision.contains("Direct local/CLI quota source:** `NO-GO`"))
        #expect(decision.contains("Browser fallback:** `CONDITIONAL GO`"))
    }

    private func durableRecords() throws -> [String] {
        try [
            source("source/UMA M7 Cursor Local Source Dossier.md"),
            source("source/UMA M7 Cursor Admission Decision.md"),
            source("source/UMA M7 Cursor Privacy Contract.md"),
            source("source/UMA M7 Cursor QA Issue Ledger.md"),
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

private enum CursorAdmissionDecision: Equatable {
    case go
    case conditionalGo
    case setupRequired
    case noGo
}

private enum CursorEvidenceState: Equatable {
    case present
    case absent
    case unavailable
}

private enum CursorUsageSemantic: Equatable {
    case activityStreaksAndStats
    case quota
}

private enum CursorStatusSemantic: Equatable {
    case authenticationOnly
    case quota
}

private enum CursorHookSemantic: Equatable {
    case agentLifecycleOnly
    case quota
}

private enum CursorBrowserSurface: Equatable {
    case officialHumanVisible
    case absent
}

private enum CursorAdminAPIClassification: Equatable {
    case officialButRejected
    case admitted
}

private enum CursorSourceTier: Equatable {
    case officialStructuredLocal
    case officialDocumentedCLI
    case officialLocalHook
    case providerControlledBrowser
    case unsupported
}

private struct CursorAdmissionEvidence: Equatable {
    var installedApplication: CursorEvidenceState
    var installedCLI: CursorEvidenceState
    var officialCLIExists: Bool
    var documentedUsageSlashCommand: Bool
    var usageSlashCommandSemantic: CursorUsageSemantic
    var documentedStructuredQuotaCommand: Bool
    var agentPrintJSONExists: Bool
    var agentPrintModeCanUseTools: Bool
    var agentPrintModeIsQuotaRead: Bool
    var statusCommandSemantic: CursorStatusSemantic
    var hookSemantic: CursorHookSemantic
    var hookQuotaSchema: CursorEvidenceState
    var browserUsageSurface: CursorBrowserSurface
    var browserFallbackRequiresNewPrivacySurface: Bool
    var browserStructuredSchema: CursorEvidenceState
    var adminAPI: CursorAdminAPIClassification
    var adminAPIRequiresCredential: Bool
    var adminAPIExposesIdentityAndEvents: Bool
    var adminAPIIsIndividualCurrentQuota: Bool
    var currentQuota: CursorEvidenceState
    var nativeUnit: CursorEvidenceState
    var stablePoolIdentity: CursorEvidenceState
    var repeatedStructure: CursorEvidenceState
    var providerOwnedAuthentication: CursorEvidenceState
    var strictPrivacyProjection: CursorEvidenceState
    var noProviderWork: CursorEvidenceState
    var boundedLifecycle: CursorEvidenceState
    var optionalReset: CursorEvidenceState
    var setupPrerequisiteIsOnlyGap: Bool
    var prohibitedCredentialRoute: Bool
    var authenticatedQuotaReads: Int
    var browserActions: Int
    var credentialReads: Int
    var providerPrompts: Int
    var providerTasks: Int
    var intentionalSpend: Int

    static let m7G1Observation = CursorAdmissionEvidence(
        installedApplication: .absent,
        installedCLI: .absent,
        officialCLIExists: true,
        documentedUsageSlashCommand: true,
        usageSlashCommandSemantic: .activityStreaksAndStats,
        documentedStructuredQuotaCommand: false,
        agentPrintJSONExists: true,
        agentPrintModeCanUseTools: true,
        agentPrintModeIsQuotaRead: false,
        statusCommandSemantic: .authenticationOnly,
        hookSemantic: .agentLifecycleOnly,
        hookQuotaSchema: .unavailable,
        browserUsageSurface: .officialHumanVisible,
        browserFallbackRequiresNewPrivacySurface: true,
        browserStructuredSchema: .unavailable,
        adminAPI: .officialButRejected,
        adminAPIRequiresCredential: true,
        adminAPIExposesIdentityAndEvents: true,
        adminAPIIsIndividualCurrentQuota: false,
        currentQuota: .unavailable,
        nativeUnit: .unavailable,
        stablePoolIdentity: .unavailable,
        repeatedStructure: .unavailable,
        providerOwnedAuthentication: .unavailable,
        strictPrivacyProjection: .unavailable,
        noProviderWork: .unavailable,
        boundedLifecycle: .unavailable,
        optionalReset: .unavailable,
        setupPrerequisiteIsOnlyGap: false,
        prohibitedCredentialRoute: false,
        authenticatedQuotaReads: 0,
        browserActions: 0,
        credentialReads: 0,
        providerPrompts: 0,
        providerTasks: 0,
        intentionalSpend: 0
    )

    static let admissibleSynthetic = CursorAdmissionEvidence(
        installedApplication: .present,
        installedCLI: .present,
        officialCLIExists: true,
        documentedUsageSlashCommand: true,
        usageSlashCommandSemantic: .quota,
        documentedStructuredQuotaCommand: true,
        agentPrintJSONExists: true,
        agentPrintModeCanUseTools: false,
        agentPrintModeIsQuotaRead: true,
        statusCommandSemantic: .quota,
        hookSemantic: .quota,
        hookQuotaSchema: .present,
        browserUsageSurface: .absent,
        browserFallbackRequiresNewPrivacySurface: false,
        browserStructuredSchema: .absent,
        adminAPI: .officialButRejected,
        adminAPIRequiresCredential: true,
        adminAPIExposesIdentityAndEvents: true,
        adminAPIIsIndividualCurrentQuota: false,
        currentQuota: .present,
        nativeUnit: .present,
        stablePoolIdentity: .present,
        repeatedStructure: .present,
        providerOwnedAuthentication: .present,
        strictPrivacyProjection: .present,
        noProviderWork: .present,
        boundedLifecycle: .present,
        optionalReset: .present,
        setupPrerequisiteIsOnlyGap: false,
        prohibitedCredentialRoute: false,
        authenticatedQuotaReads: 2,
        browserActions: 0,
        credentialReads: 0,
        providerPrompts: 0,
        providerTasks: 0,
        intentionalSpend: 0
    )
}

private struct CursorSanitizedProjection: Equatable {
    var officialSurface: Bool
    var quotaReads: Int
}

private enum CursorAdmissionHarness {
    static let sourcePriority: [CursorSourceTier] = [
        .officialStructuredLocal,
        .officialDocumentedCLI,
        .officialLocalHook,
        .providerControlledBrowser,
        .unsupported,
    ]

    static func decide(_ evidence: CursorAdmissionEvidence) -> CursorAdmissionDecision {
        if evidence.prohibitedCredentialRoute {
            return .noGo
        }

        let sourceContract = evidence.documentedStructuredQuotaCommand
        let mandatory = evidence.currentQuota == .present
            && evidence.nativeUnit == .present
            && evidence.stablePoolIdentity == .present
            && evidence.repeatedStructure == .present
            && evidence.providerOwnedAuthentication == .present
            && evidence.strictPrivacyProjection == .present
            && evidence.noProviderWork == .present
            && evidence.boundedLifecycle == .present

        if sourceContract && mandatory {
            if evidence.installedCLI == .absent && evidence.setupPrerequisiteIsOnlyGap {
                return .setupRequired
            }
            return evidence.optionalReset == .present ? .go : .conditionalGo
        }

        if evidence.browserUsageSurface == .officialHumanVisible
            && evidence.browserFallbackRequiresNewPrivacySurface
        {
            return .conditionalGo
        }

        return .noGo
    }

    static func directImplementationUnlocked(_ evidence: CursorAdmissionEvidence) -> Bool {
        guard decide(evidence) == .go || decide(evidence) == .conditionalGo else {
            return false
        }
        return evidence.documentedStructuredQuotaCommand
            && evidence.currentQuota == .present
            && !evidence.browserFallbackRequiresNewPrivacySurface
    }

    static func nextTask(for evidence: CursorAdmissionEvidence) -> String {
        if evidence.browserUsageSurface == .officialHumanVisible
            && evidence.browserFallbackRequiresNewPrivacySurface
            && !directImplementationUnlocked(evidence)
        {
            return "Founder provider-controlled browser fallback architecture decision"
        }
        switch decide(evidence) {
        case .go, .conditionalGo:
            return "M7-G2"
        case .setupRequired:
            return "M7-SETUP-G1"
        case .noGo:
            return "Founder source-direction decision"
        }
    }

    static func admitsAdminAPI(_ evidence: CursorAdmissionEvidence) -> Bool {
        evidence.adminAPI == .admitted
            && !evidence.adminAPIRequiresCredential
            && !evidence.adminAPIExposesIdentityAndEvents
            && evidence.adminAPIIsIndividualCurrentQuota
    }

    static func sanitize(_ raw: [String: Any]) -> CursorSanitizedProjection {
        CursorSanitizedProjection(
            officialSurface: raw["officialSurface"] as? Bool ?? false,
            quotaReads: raw["quotaReads"] as? Int ?? 0
        )
    }
}
