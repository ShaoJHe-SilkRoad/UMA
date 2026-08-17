import Foundation
import Testing

@Suite("M8 Kimi browser source admission")
struct M8WEBG1KimiBrowserAdmissionTests {
    @Test
    func mandatorySharedMembershipFailureKeepsProductionLocked() {
        let evidence = KimiBrowserAdmissionEvidence.observed

        #expect(evidence.browserArchitectureViable)
        #expect(evidence.sharedMembership == .noGo)
        #expect(KimiBrowserAdmissionHarness.decide(evidence) == .noGo)
        #expect(!KimiBrowserAdmissionHarness.implementationUnlocked(evidence))
    }

    @Test
    func browserTransportDoesNotSubstituteForQuotaSemantics() {
        var evidence = KimiBrowserAdmissionEvidence.syntheticAdmitted
        evidence.sharedMembership = .noGo
        evidence.sharedSemantic = nil
        evidence.sharedResetPresent = false

        #expect(evidence.exactRouteGate)
        #expect(evidence.sanitizedBeforeNative)
        #expect(KimiBrowserAdmissionHarness.decide(evidence) == .noGo)
    }

    @Test
    func conditionalGoAllowsOnlyOptionalCodeGap() {
        var evidence = KimiBrowserAdmissionEvidence.syntheticAdmitted
        evidence.codeLimits = .missing

        #expect(KimiBrowserAdmissionHarness.decide(evidence) == .conditionalGo)
        #expect(KimiBrowserAdmissionHarness.implementationUnlocked(evidence))

        evidence.extraUsage = .unreadable
        #expect(KimiBrowserAdmissionHarness.decide(evidence) == .noGo)
    }

    @Test
    func normalizationIsExplicitAndAppliedExactlyOnce() {
        #expect(KimiBrowserAdmissionHarness.remaining(fromUsedPercent: 0) == 100)
        #expect(KimiBrowserAdmissionHarness.remaining(fromUsedPercent: 53) == 47)
        #expect(KimiBrowserAdmissionHarness.remaining(fromUsedPercent: 100) == 0)
        #expect(KimiBrowserAdmissionHarness.remaining(fromUsedPercent: -1) == nil)
        #expect(KimiBrowserAdmissionHarness.remaining(fromUsedPercent: 101) == nil)
    }

    @Test
    func extraUsageStateNeverBecomesPercentageOrFalseExhaustion() {
        #expect(KimiBrowserAdmissionHarness.extraAllowsImplementation(.absent))
        #expect(KimiBrowserAdmissionHarness.extraAllowsImplementation(.disabled))
        #expect(KimiBrowserAdmissionHarness.extraAllowsImplementation(.enabledExactNativeBalance))
        #expect(!KimiBrowserAdmissionHarness.extraAllowsImplementation(.unreadable))
        #expect(KimiBrowserAdmissionHarness.percentForExtraUsage(.enabledExactNativeBalance) == nil)
    }

    @Test
    func unknownAccountModeFailsClosed() {
        var evidence = KimiBrowserAdmissionEvidence.syntheticAdmitted
        evidence.accountModeSupported = false

        #expect(KimiBrowserAdmissionHarness.decide(evidence) == .noGo)
    }

    @Test
    func exactRoutePolicyRejectsLookalikesAndBilling() {
        #expect(KimiBrowserAdmissionHarness.routeClass("https://www.kimi.com/membership/subscription?tab=quota") == .membership)
        #expect(KimiBrowserAdmissionHarness.routeClass("https://www.kimi.com/code/console") == .code)
        #expect(KimiBrowserAdmissionHarness.routeClass("http://www.kimi.com/code/console") == .rejected)
        #expect(KimiBrowserAdmissionHarness.routeClass("https://kimi.example/code/console") == .rejected)
        #expect(KimiBrowserAdmissionHarness.routeClass("https://www.kimi.com/membership/subscription?tab=billing") == .rejected)
    }

    @Test
    func privacyProjectionDropsIdentityCredentialsAndRawPageState() {
        let raw: [String: Any] = [
            "routeClass": "MEMBERSHIP_QUOTA",
            "status": "UNSUPPORTED_LAYOUT",
            "email": "synthetic-private@example.invalid",
            "token": "synthetic-token",
            "cookie": "synthetic-cookie",
            "rawDOM": "synthetic-dom",
            "rawHTML": "synthetic-html",
            "quota": "synthetic-exact-value",
        ]

        let projection = KimiBrowserAdmissionHarness.sanitize(raw)
        let reflection = String(reflecting: projection)
        #expect(projection == .init(routeClass: "MEMBERSHIP_QUOTA", status: "UNSUPPORTED_LAYOUT"))
        for forbidden in ["synthetic-private", "synthetic-token", "synthetic-cookie", "synthetic-dom", "synthetic-html", "synthetic-exact-value"] {
            #expect(!reflection.contains(forbidden))
        }
    }

    @Test
    func observationAccountingRemainsBoundedAndNoSpend() {
        let evidence = KimiBrowserAdmissionEvidence.observed

        #expect(evidence.authenticatedObservations == 5)
        #expect(evidence.maximumObservations == 8)
        #expect(evidence.validSanitizedReceipts == 4)
        #expect(evidence.providerPrompts == 0)
        #expect(evidence.providerTasks == 0)
        #expect(evidence.intentionalSpend == 0)
        #expect(evidence.accountChanges == 0)
    }

    @Test
    func isolatedSessionIsRejectedAndSafariIsTheOnlySelectedFallback() throws {
        let dossier = try source("source/UMA M8 Kimi Browser Source Dossier.md")

        #expect(dossier.contains("ISOLATED KIMI WEB SESSION: NOT SUITABLE FOR ADMISSION / HUMAN AUTH UX"))
        #expect(dossier.contains("task-owned Safari"))
        #expect(dossier.contains("Browser Companion"))
        #expect(dossier.contains("no host permissions, static content scripts, cookies, storage, history"))
    }

    @Test
    func durableRecordsAgreeOnNoGoAndSingleNextTask() throws {
        let records = try durableRecords()
        for record in records {
            #expect(record.contains("M8-G2 remains locked"))
            #expect(record.contains("NO-GO"))
            #expect(!record.contains("synthetic-private@example.invalid"))
            #expect(!record.contains("/Users/"))
        }
        let combined = records.joined(separator: "\n")
        #expect(combined.contains("SHARED MEMBERSHIP: NO-GO"))
        #expect(combined.contains("KIMI CODE LIMITS: MISSING"))
        #expect(combined.contains("EXTRA USAGE: ABSENT"))
        #expect(combined.contains("Founder Kimi source-direction / M8 closeout decision"))
    }

    @Test
    func workBuddyPatternIsReusedWithoutChangingWorkBuddy() throws {
        let dossier = try source("source/UMA M8 Kimi Browser Source Dossier.md")
        let ledger = try source("source/UMA M8 Kimi QA Issue Ledger.md")

        #expect(dossier.contains("REUSABLE AS-IS"))
        #expect(dossier.contains("REUSABLE WITH KIMI ADAPTER"))
        #expect(dossier.contains("WORKBUDDY-SPECIFIC"))
        #expect(dossier.contains("UMA-owned isolated WorkBuddy `WKWebView`"))
        #expect(dossier.contains("Session storage ownership itself is not reused"))
        #expect(dossier.contains("No WorkBuddy production file"))
        #expect(ledger.contains("WorkBuddy mechanism changed: NO"))
    }

    @Test
    func privacyIncidentIsRealContainedAndGuarded() throws {
        let records = try durableRecords()
        let combined = records.joined(separator: "\n")

        #expect(combined.contains("broad read-only Safari accessibility"))
        #expect(combined.contains("retained no payload"))
        #expect(combined.contains("Broad page trees"))
        #expect(combined.contains("process argv"))
    }

    @Test
    func qaLedgerLocksExactFiveFileScope() throws {
        let ledger = try source("source/UMA M8 Kimi QA Issue Ledger.md")
        let expected = [
            "source/UMA M8 Kimi Browser Source Dossier.md",
            "source/UMA M8 Kimi Browser Admission Decision.md",
            "source/UMA M8 Kimi Privacy Contract.md",
            "source/UMA M8 Kimi QA Issue Ledger.md",
            "Tests/CodexUsageUITests/M8WEBG1KimiBrowserAdmissionTests.swift",
        ]
        for path in expected { #expect(ledger.contains(path)) }
        #expect(ledger.contains("Production source files changed: NO"))
        #expect(ledger.contains("Existing provider mechanisms changed: NO"))
        #expect(ledger.contains("M5 frozen files changed: NO"))
        #expect(ledger.contains("Package scripts changed: NO"))
    }

    @Test
    func noProductionKimiImplementationIsClaimed() throws {
        let decision = try source("source/UMA M8 Kimi Browser Admission Decision.md")

        #expect(decision.contains("No production connector, provider registration, scheduler"))
        #expect(decision.contains("Desktop Assistant"))
        #expect(decision.contains("M8-G2 remains locked"))
    }

    private func durableRecords() throws -> [String] {
        try [
            source("source/UMA M8 Kimi Browser Source Dossier.md"),
            source("source/UMA M8 Kimi Browser Admission Decision.md"),
            source("source/UMA M8 Kimi Privacy Contract.md"),
            source("source/UMA M8 Kimi QA Issue Ledger.md"),
        ]
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum KimiBrowserDecision: Equatable { case go, conditionalGo, setupRequired, noGo }
private enum KimiChannelDecision: Equatable { case go, conditional, missing, noGo }
private enum KimiExtraState: Equatable { case absent, disabled, enabledExactNativeBalance, unreadable }
private enum KimiRouteClass: Equatable { case membership, code, rejected }

private struct KimiBrowserAdmissionEvidence {
    var browserArchitectureViable: Bool
    var exactRouteGate: Bool
    var sanitizedBeforeNative: Bool
    var accountModeSupported: Bool
    var sharedMembership: KimiChannelDecision
    var sharedSemantic: String?
    var sharedResetPresent: Bool
    var repeatedSuccessfulStructure: Bool
    var codeLimits: KimiChannelDecision
    var extraUsage: KimiExtraState
    var authenticatedObservations: Int
    var maximumObservations: Int
    var validSanitizedReceipts: Int
    var providerPrompts: Int
    var providerTasks: Int
    var intentionalSpend: Int
    var accountChanges: Int

    static let observed = Self(
        browserArchitectureViable: true,
        exactRouteGate: true,
        sanitizedBeforeNative: true,
        accountModeSupported: false,
        sharedMembership: .noGo,
        sharedSemantic: nil,
        sharedResetPresent: false,
        repeatedSuccessfulStructure: false,
        codeLimits: .missing,
        extraUsage: .absent,
        authenticatedObservations: 5,
        maximumObservations: 8,
        validSanitizedReceipts: 4,
        providerPrompts: 0,
        providerTasks: 0,
        intentionalSpend: 0,
        accountChanges: 0
    )

    static let syntheticAdmitted = Self(
        browserArchitectureViable: true,
        exactRouteGate: true,
        sanitizedBeforeNative: true,
        accountModeSupported: true,
        sharedMembership: .go,
        sharedSemantic: "USED_PERCENT",
        sharedResetPresent: true,
        repeatedSuccessfulStructure: true,
        codeLimits: .go,
        extraUsage: .disabled,
        authenticatedObservations: 2,
        maximumObservations: 8,
        validSanitizedReceipts: 2,
        providerPrompts: 0,
        providerTasks: 0,
        intentionalSpend: 0,
        accountChanges: 0
    )
}

private struct KimiSanitizedReceipt: Equatable {
    let routeClass: String
    let status: String
}

private enum KimiBrowserAdmissionHarness {
    static func decide(_ evidence: KimiBrowserAdmissionEvidence) -> KimiBrowserDecision {
        guard evidence.browserArchitectureViable,
              evidence.exactRouteGate,
              evidence.sanitizedBeforeNative,
              evidence.accountModeSupported,
              evidence.sharedMembership == .go,
              evidence.sharedSemantic != nil,
              evidence.sharedResetPresent,
              evidence.repeatedSuccessfulStructure,
              extraAllowsImplementation(evidence.extraUsage)
        else { return .noGo }
        return evidence.codeLimits == .missing ? .conditionalGo : .go
    }

    static func implementationUnlocked(_ evidence: KimiBrowserAdmissionEvidence) -> Bool {
        let decision = decide(evidence)
        return decision == .go || decision == .conditionalGo
    }

    static func remaining(fromUsedPercent used: Double) -> Double? {
        guard used.isFinite, (0 ... 100).contains(used) else { return nil }
        return 100 - used
    }

    static func extraAllowsImplementation(_ state: KimiExtraState) -> Bool {
        state != .unreadable
    }

    static func percentForExtraUsage(_ state: KimiExtraState) -> Double? { nil }

    static func routeClass(_ raw: String) -> KimiRouteClass {
        guard let components = URLComponents(string: raw),
              components.scheme == "https",
              components.host == "www.kimi.com",
              components.fragment == nil
        else { return .rejected }
        if components.path == "/membership/subscription",
           components.percentEncodedQuery == "tab=quota" { return .membership }
        if components.path == "/code/console", components.query == nil { return .code }
        return .rejected
    }

    static func sanitize(_ raw: [String: Any]) -> KimiSanitizedReceipt {
        .init(
            routeClass: raw["routeClass"] as? String ?? "UNRECOGNIZED",
            status: raw["status"] as? String ?? "SOURCE_UNAVAILABLE"
        )
    }
}
