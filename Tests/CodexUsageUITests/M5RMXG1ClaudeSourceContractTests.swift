import ClaudeBrowserBridgeProtocol
import ClaudeStatusLineCore
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5RMX Claude Local Smart source and privacy contract")
struct M5RMXG1ClaudeSourceContractTests {
    @Test
    func currentDecisionSupersedesBrowserFirstHistoricalRecords() throws {
        let dossier = try record("source/UMA M5RMX Claude Source Dossier.md")
        let decision = try record("source/UMA M5RMX Claude Source Decision.md")
        let scope = try record("source/UMA M5RMX Scope Lock.md")

        #expect(decision.contains("M5RMX CLAUDE ROOT REPAIR — FUNDAMENTAL PASS"))
        #expect(decision.contains("The immutable Host/Companion is accepted and locked"))
        #expect(decision.contains("EXACT_LOCAL_STATUSLINE"))
        #expect(decision.contains("> EXACT_SAFARI_ACCURACY"))
        #expect(decision.contains("> ESTIMATED_LOCAL"))
        #expect(dossier.contains("Current source owner — Founder override"))
        #expect(scope.contains("Current Smart Mode scope supersession"))
        #expect(scope.contains("Current source ownership is Local Smart Mode"))
        #expect(scope.contains("The prior Section 3 remains historical baseline where it conflicts"))
    }

    @Test
    func credentialExistenceIsSeparatedFromCredentialCrossing() throws {
        let privacy = try record("source/UMA M5RMX Claude Privacy Contract.md")
        #expect(privacy.contains(
            "Credential existence is not the problem; credential crossing into UMA is the problem."
        ))
        for forbidden in [
            "passwords, passkeys, and verification codes",
            "OAuth access or refresh tokens",
            "cookies, session state, browser profiles",
            "provider-owned Keychain secrets",
            "raw HTML, broad DOM/page text",
            "broad process argv or environment capture",
            "Claude prompts/tasks or intentional spend",
        ] {
            #expect(privacy.contains(forbidden))
        }
    }

    @Test
    func founderAuthorizedLocalSanitizationIsCurrentAndBrowserPersistenceIsRetired() throws {
        let privacy = try record("source/UMA M5RMX Claude Privacy Contract.md")

        for required in [
            "parse one bounded Claude JSONL\nrecord at a time in memory",
            "allowlisted usage/token\ncounts, bounded model-family classification, and activity timestamp",
            "Local Activity is an input to calibrated estimation only",
            "explicit one-shot Accuracy Sync",
            "There is no background\nscheduler",
            "restores the exact preserved prior Claude status-line configuration",
            "bounded pre-UMA\nrelay sanitizer",
        ] {
            #expect(privacy.contains(required))
        }
        for stale in [
            "persistent background owner",
            "completion-relative automatic refresh",
            "CLAUDE LOCAL ACTIVITY — DEFERRED TO M5RMX-G2 PRIVACY REQUALIFICATION",
            "The retired route must remain inactive",
            "Disconnect cancels the Claude scheduler",
        ] {
            #expect(!privacy.contains(stale))
        }
    }

    @Test
    func statusLinePacketIsClosedVersionedAndBounded() throws {
        #expect(ClaudeStatusLinePacket.currentSchemaVersion == 1)
        #expect(ClaudeStatusLineProjection.maximumInputBytes == 64 * 1_024)
        #expect(ClaudeStatusLinePacket.maximumEncodedBytes == 4 * 1_024)

        let raw = Data(#"{"session_id":"private","cwd":"/private/work","rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1898600400},"seven_day":{"used_percentage":40,"resets_at":1899198000}}}"#.utf8)
        let encoded = try ClaudeStatusLineProjection.decode(raw).encoded()
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("session_id"))
        #expect(!text.contains("cwd"))
        #expect(!text.contains("private"))
        #expect(try ClaudeStatusLinePacket.decodePacket(encoded).fiveHour?.usedPercentage == 25)
    }

    @Test
    func safariRouteGatePrecedesDOMAndManifestStaysNarrow() throws {
        let manifestData = try Data(contentsOf: repositoryRoot().appendingPathComponent(
            "BrowserExtension/Safari/manifest.json"
        ))
        let manifest = try #require(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        let permissions = try #require(manifest["permissions"] as? [String])
        #expect(Set(permissions) == Set([
            "nativeMessaging", "https://claude.ai/new*",
        ]))
        let contentScripts = try #require(manifest["content_scripts"] as? [[String: Any]])
        #expect(contentScripts.count == 1)
        #expect(contentScripts[0]["matches"] as? [String] == ["https://claude.ai/new*"])
        #expect(contentScripts[0]["js"] as? [String] == [
            "Shared/claude-usage-extractor.js",
            "Shared/provider-ownership-v2.js",
            "Shared/content-script.js",
        ])
        #expect(contentScripts[0]["run_at"] as? String == "document_start")
        #expect(contentScripts[0]["all_frames"] as? Bool == false)
        let background = try #require(manifest["background"] as? [String: Any])
        #expect(background["persistent"] as? Bool == true)

        let extractor = try source("BrowserExtension/Shared/claude-usage-extractor.js")
        let resultStart = try #require(extractor.range(of: "function extractResult"))
        let resultBody = String(extractor[resultStart.lowerBound...])
        let routeGate = try #require(resultBody.range(
            of: "if (!exactUsageURL(locationLike)) {"
        ))
        #expect(resultBody.contains(
            "status: \"routeRejected\", reasonCode: FAILURE_REASONS.routeNotReady"
        ))
        let firstDOMQuery = try #require(resultBody.range(of: "hasLoginForm(documentLike)"))
        #expect(routeGate.lowerBound < firstDOMQuery.lowerBound)
        let privacy = try record("source/UMA M5RMX Claude Privacy Contract.md")
        #expect(privacy.contains("Only after that route gate may the extractor perform the narrow login-form\nlandmark query"))
        #expect(privacy.contains("before any quota-card selector or bounded leaf-text query"))
        #expect(extractor.contains("maximumLabelElementCount: 4096"))
        #expect(extractor.contains("matchingExplicitCards"))
        #expect(extractor.contains("matchingLabelCards"))
        #expect(extractor.contains("label.childElementCount > 0"))
        #expect(extractor.contains("boundedOwnText(label, 80)"))
        #expect(!extractor.contains("document.documentElement.outerHTML"))
        #expect(!extractor.contains("document.body.innerText"))
        #expect(!extractor.contains("localStorage"))
        #expect(!extractor.contains("sessionStorage"))
        #expect(!extractor.contains("document.cookie"))
    }

    @Test
    func oneShotAccuracyContractSupersedesPersistentSafariHistory() throws {
        let dossier = try record("source/UMA M5RMX Claude Source Dossier.md")
        let privacy = try record("source/UMA M5RMX Claude Privacy Contract.md")
        let combined = dossier + privacy

        #expect(combined.contains("explicit one-shot Accuracy Sync"))
        #expect(combined.contains("inactive extension-owned exact Usage tab"))
        #expect(combined.contains("no background scheduler"))
        #expect(combined.contains("automatic retry, catch-up burst, or permanent owned tab"))
        #expect(combined.contains("exact Usage route"))
        #expect(combined.contains("raw DOM/HTML"))
    }

    @Test
    func accountWindowsAreUsedSemanticsConvertedExactlyOnce() throws {
        let dossier = try record("source/UMA M5RMX Claude Source Dossier.md")
        #expect(dossier.contains("remainingPercent = 100 - usedPercent"))
        #expect(dossier.contains("five-hour used percentage"))
        #expect(dossier.contains("weekly/all-model used percentage"))
        #expect(dossier.contains("Missing, malformed, duplicate, or ambiguous windows are unavailable"))

        let agentModel = try source(
            "Sources/CodexUsageUI/Connectors/AgentUsageConnector.swift"
        )
        #expect(
            agentModel.components(separatedBy: "return 100 - usedPercent").count - 1 == 1
        )
        let presentation = try source(
            "Sources/CodexUsageUI/Models/SharedUsagePresentation.swift"
        )
        #expect(!presentation.contains("100 - used"))
    }

    @Test
    func continuationAndUsageCreditStateFailClosed() throws {
        let dossier = try record("source/UMA M5RMX Claude Source Dossier.md")
        let decision = try record("source/UMA M5RMX Claude Source Decision.md")
        #expect(dossier.contains("CONTINUATION / USAGE-CREDIT STATE: NOT ADMITTED"))
        #expect(decision.contains("Continuation, extra usage, usage credits, billing balance, or purchase state:"))
        #expect(decision.contains("`NOT ADMITTED`"))
        #expect(dossier.contains("must not infer continuation from a\nquota percentage"))
        #expect(dossier.contains("`0%` included-plan remaining does\nnot prove Claude work must stop"))
        #expect(dossier.contains("overall provider unavailability"))
        #expect(decision.contains("overall work availability remains `UNKNOWN`"))
    }

    @Test
    func officialStatusLineFieldsAreAdmittedOnlyThroughImmediateProjection() throws {
        let dossier = try record("source/UMA M5RMX Claude Source Dossier.md")
        let privacy = try record("source/UMA M5RMX Claude Privacy Contract.md")
        let combined = dossier + privacy

        for field in [
            "rate_limits.five_hour.used_percentage",
            "rate_limits.five_hour.resets_at",
            "rate_limits.seven_day.used_percentage",
            "rate_limits.seven_day.resets_at",
        ] {
            #expect(dossier.contains(field))
        }
        #expect(combined.contains("after a first API response"))
        #expect(combined.contains("raw status-line stdin"))
        #expect(combined.contains("session/workspace fields"))
        #expect(combined.contains("immediate allowlist projection"))
        #expect(dossier.contains("Pro/Max"))
        #expect(dossier.contains("Missing exact callbacks therefore do not become\nzero"))
    }

    @Test
    func connectorDescriptorDeclaresSmartTruthAndContentExclusions() {
        let descriptor = ClaudeCodeUsageConnector.production().descriptor
        #expect(descriptor.sourceVersion == "smart-1")
        #expect(descriptor.sourceTier == .officialStructuredHook)
        #expect(descriptor.localSourceClass == .admittedStructuredLocal)
        #expect(descriptor.capabilities.contains(.localActivity))
        #expect(!descriptor.capabilities.contains(.automaticRefresh))
        #expect(descriptor.supportedScopes == [.account, .session])
        for forbidden in [
            "credentials", "tokens", "cookies", "prompt", "response",
            "transcript", "project", "sourceCode", "rawHTML", "rawDOM", "rawJSON",
        ] {
            #expect(descriptor.unsupportedFields.contains(forbidden))
        }
    }

    @Test
    func rejectedCredentialRoutesStayAbsentWhileSmartTargetsArePresent() throws {
        let package = try source("Package.swift")
        #expect(package.contains("ClaudeStatusLineCore"))
        #expect(package.contains("ClaudeStatusLineRelay"))
        #expect(!package.contains("ClaudeQuotaBroker"))

        let sourceRoots = [
            repositoryRoot().appendingPathComponent("Sources"),
            repositoryRoot().appendingPathComponent("BrowserExtension"),
        ]
        let production = try sourceRoots.flatMap { root in
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey]
            )?.compactMap { $0 as? URL }.filter {
                ["swift", "js", "json", "plist"].contains($0.pathExtension)
            } ?? []
        }.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        for forbidden in [
            "Claude Code-credentials",
            "/api/oauth/usage",
            "ClaudeQuotaBroker",
            "ANTHROPIC_API_KEY",
        ] {
            #expect(!production.contains(forbidden))
        }
    }

    @Test
    func smartLedgerLocksNonOperationAndEveryOpenAcceptanceGate() throws {
        let decision = try record("source/UMA M5RMX Claude Source Decision.md")
        let ledger = try record("source/UMA M5RMX QA Issue Ledger.md")

        for statement in [
            "Claude prompts/tasks: 0",
            "Intentional provider spend: 0",
            "Apple actions in this Goal must remain zero",
            "No issue above is CLOSED",
            "IMPLEMENTED / OPEN",
        ] {
            #expect((decision + ledger).contains(statement))
        }
        for issue in 1...12 {
            #expect(ledger.contains(String(format: "SMART-%02d", issue)))
        }
    }

    private func record(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try record(relativePath)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
