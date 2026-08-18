import Foundation
import Testing
import ClaudeBrowserBridgeProtocol

@Suite("M5RMX-G1 Claude source and privacy contract")
struct M5RMXG1ClaudeSourceContractTests {
    @Test
    func sourceDecisionPreservesBrowserSyncAndRejectsUnprovenPromotion() throws {
        let dossier = try record("source/UMA M5RMX Claude Source Dossier.md")
        let decision = try record("source/UMA M5RMX Claude Source Decision.md")

        for candidate in [
            "Official Claude local service or IPC",
            "Official hook, event, or status interface",
            "Official read-only CLI or provider-owned local metadata",
            "Safari Browser Sync",
        ] {
            #expect(dossier.contains(candidate))
        }
        #expect(decision.contains("PASS — CURRENT SAFARI BROWSER SYNC PRESERVED"))
        #expect(decision.contains("No official superior source candidate currently passes"))
        #expect(decision.contains("`HISTORICAL / RETIRED`"))
        #expect(dossier.contains("STATUS-LINE ROUTE: HISTORICAL / RETIRED"))
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
    func bridgePacketRemainsClosedVersionedAndBounded() throws {
        #expect(ClaudeBrowserBridgeContract.messageKind == "claudeUsageObservation")
        #expect(ClaudeBrowserBridgeContract.sourceID == "claude-browser-usage")
        #expect(ClaudeBrowserBridgeContract.schemaVersion == 2)
        #expect(ClaudeBrowserBridgeContract.extractorSchemaVersion == 2)
        #expect(ClaudeBrowserBridgeContract.maximumMessageBytes == 4_096)
        #expect(
            ClaudeBrowserBridgeContract.officialUsageURL.absoluteString
                == "https://claude.ai/new#settings/usage"
        )

        let decoder = try source(
            "Sources/ClaudeBrowserNativeHostCore/ClaudeBrowserMessageDecoder.swift"
        )
        #expect(decoder.contains("requireExactKeys"))
        #expect(decoder.contains("throw ClaudeBrowserBridgeError.unexpectedField"))
        #expect(decoder.contains("throw ClaudeBrowserBridgeError.noAccountWindow"))
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
            "nativeMessaging", "storage", "https://claude.ai/new*",
        ]))
        #expect(manifest["content_scripts"] == nil)
        let background = try #require(manifest["background"] as? [String: Any])
        #expect(background["persistent"] as? Bool == true)

        let extractor = try source("BrowserExtension/Shared/claude-usage-extractor.js")
        let resultStart = try #require(extractor.range(of: "function extractResult"))
        let resultBody = String(extractor[resultStart.lowerBound...])
        let routeGate = try #require(resultBody.range(
            of: "if (!exactUsageURL(locationLike)) return { status: \"routeRejected\" };"
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
    func currentPersistentSafariContractSupersedesToolbarOnlyHistory() throws {
        let dossier = try record("source/UMA M5RMX Claude Source Dossier.md")
        let privacy = try record("source/UMA M5RMX Claude Privacy Contract.md")
        let combined = dossier + privacy

        #expect(combined.contains("supersedes historical activeTab/toolbar-only"))
        #expect(combined.contains("persistent exact host scope"))
        #expect(combined.contains("https://claude.ai/new*"))
        #expect(combined.contains("one extension-owned inactive Usage tab"))
        #expect(combined.contains("completion-relative automatic refresh"))
        #expect(combined.contains("unknown routes are rejected before\nDOM inspection"))
        #expect(combined.contains("unrelated leaf text transiently"))
        #expect(combined.contains("does not serialize, retain, or forward"))
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
    func officialStatusLineFieldsRemainRetiredAndCoverageBounded() throws {
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
        #expect(combined.contains("only\nafter the first API response"))
        #expect(combined.contains("timer rerun is not proven"))
        #expect(combined.contains("raw status-line stdin"))
        #expect(combined.contains("sensitive session and workspace\ncontext"))
        #expect(dossier.contains("Pro and Max"))
        #expect(dossier.contains("Team, Enterprise, and\nunknown account modes are not qualified"))
    }

    @Test
    func currentLocalSignatureFailuresBlockOnlyLocalPromotion() throws {
        let dossier = try record("source/UMA M5RMX Claude Source Dossier.md")
        let decision = try record("source/UMA M5RMX Claude Source Decision.md")
        let combined = dossier + decision

        #expect(combined.contains("$HOME/.local/bin/claude"))
        #expect(combined.contains("$HOME/.local/share/claude/versions/2.1.220"))
        #expect(combined.contains("/Applications/Claude.app"))
        #expect(combined.contains("invalid signature (code or signature have been modified)"))
        #expect(combined.contains("In architecture: arm64"))
        #expect(dossier.contains("They do not weaken Safari Browser Sync"))
        #expect(decision.contains("This does not change the accepted Safari Browser Sync decision"))
    }

    @Test
    func retiredCredentialAndStatusLineRoutesRemainNonProduction() throws {
        let package = try source("Package.swift")
        #expect(!package.contains("ClaudeStatusLineCore"))
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
        ] {
            #expect(!production.contains(forbidden))
        }
    }

    @Test
    func deliveryRecordLocksNonOperationAndNextGoal() throws {
        let decision = try record("source/UMA M5RMX Claude Source Decision.md")
        let ledger = try record("source/UMA M5RMX QA Issue Ledger.md")

        for statement in [
            "Sanitized authenticated Claude Usage observations: 0",
            "Claude prompts/tasks: 0",
            "Intentional provider spend: 0",
            "Production runtime/extension changes: 0",
            "sole next task is `M5RMX-SAFARI-G1`",
        ] {
            #expect((decision + ledger).contains(statement))
        }
        #expect(ledger.contains("M5RMXG1-001"))
        #expect(ledger.contains("M5RMXG1-009"))
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
