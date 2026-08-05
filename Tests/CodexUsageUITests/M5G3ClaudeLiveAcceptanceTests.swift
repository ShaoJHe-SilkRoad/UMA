import ClaudeBrowserBridgeProtocol
import Foundation
import JavaScriptCore
import Testing
@testable import CodexUsageUI

@Suite("M5-BROWSER-G1 browser-companion acceptance")
struct M5G3ClaudeLiveAcceptanceTests {
    @Test
    func defaultBrowserContractUsesOnlyExactOfficialUsageRoute() {
        #expect(ClaudeBrowserBridgeContract.officialOrigin == "https://claude.ai")
        #expect(ClaudeBrowserBridgeContract.officialUsagePath == "/new")
        #expect(ClaudeBrowserBridgeContract.officialUsageFragment == "settings/usage")
        #expect(
            ClaudeBrowserBridgeContract.officialUsageURL.absoluteString
                == "https://claude.ai/new#settings/usage"
        )
    }

    @Test @MainActor
    func extractorAdmitsOnlyExactLiveUsageFragment() throws {
        guard let context = JSContext() else {
            Issue.record("JavaScriptCore context unavailable")
            return
        }
        var exceptionText: String?
        context.exceptionHandler = { _, exception in
            exceptionText = exception?.toString()
        }
        let source = try String(
            contentsOf: browserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/claude-usage-extractor.js"
            ),
            encoding: .utf8
        )
        context.evaluateScript(source)
        #expect(exceptionText == nil)

        let matrix: [(String, Bool)] = [
            ("{protocol:'https:',origin:'https://claude.ai',pathname:'/new',search:'',hash:'#settings/usage'}", true),
            ("{protocol:'https:',origin:'https://claude.ai',pathname:'/new/',search:'',hash:'#settings/usage'}", false),
            ("{protocol:'https:',origin:'https://claude.ai',pathname:'/new',search:'',hash:''}", false),
            ("{protocol:'https:',origin:'https://claude.ai',pathname:'/new',search:'',hash:'#chat'}", false),
            ("{protocol:'https:',origin:'https://claude.ai',pathname:'/new',search:'',hash:'#settings/account'}", false),
            ("{protocol:'https:',origin:'https://claude.ai',pathname:'/new',search:'?source=test',hash:'#settings/usage'}", false),
            ("{protocol:'https:',origin:'https://claude.ai',pathname:'/settings/usage',search:'',hash:''}", false),
            ("{protocol:'http:',origin:'http://claude.ai',pathname:'/new',search:'',hash:'#settings/usage'}", false),
            ("{protocol:'https:',origin:'https://example.com',pathname:'/new',search:'',hash:'#settings/usage'}", false),
        ]
        for (location, expected) in matrix {
            let actual = context.evaluateScript(
                "UMAClaudeUsageExtractor.exactUsageURL(\(location))"
            )?.toBool()
            #expect(actual == expected)
        }
        #expect(exceptionText == nil)
    }

    @Test @MainActor
    func extractorScopesCurrentSessionLeafLabelWithoutBroadTextOutput() throws {
        let context = try #require(JSContext())
        let source = try String(
            contentsOf: browserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/claude-usage-extractor.js"
            ),
            encoding: .utf8
        )
        context.evaluateScript(source)
        let result = context.evaluateScript(
            """
            (() => {
              const percentage = {
                textContent: "44%",
                getAttribute: () => null,
              };
              const card = {
                querySelectorAll: selector => selector.includes("time[") ? [] : [percentage],
              };
              const label = {
                childElementCount: 0,
                textContent: "Current session",
                closest: () => card,
              };
              const documentLike = {
                querySelector: () => null,
                querySelectorAll: selector => selector.includes("h1, h2") ? [label] : [],
              };
              const locationLike = {
                protocol: "https:",
                origin: "https://claude.ai",
                pathname: "/new",
                search: "",
                hash: "#settings/usage",
              };
              const observation = UMAClaudeUsageExtractor.extract(
                documentLike,
                locationLike,
                new Date("2026-08-01T14:00:00Z")
              );
              return observation !== null
                && observation.fiveHour.usedPercentage === 44
                && observation.weeklyAllModels === null
                && Object.keys(observation).sort().join(",")
                  === "extractorSchemaVersion,fiveHour,modelSpecificWeekly,observedAt,weeklyAllModels";
            })()
            """
        )?.toBool()
        #expect(result == true)
    }

    @Test @MainActor
    func extractorFindsUsageLandmarkAfterStructuralPageNodes() throws {
        let context = try #require(JSContext())
        let source = try String(
            contentsOf: browserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/claude-usage-extractor.js"
            ),
            encoding: .utf8
        )
        context.evaluateScript(source)
        let result = context.evaluateScript(
            """
            (() => {
              const percentage = { textContent: "44%", getAttribute: () => null };
              const card = {
                querySelectorAll: selector => selector.includes("time[") ? [] : [percentage],
              };
              const decoys = Array.from({ length: 48 }, () => ({
                childElementCount: 0,
                textContent: "unrelated structural node",
                closest: () => null,
              }));
              const label = {
                childElementCount: 0,
                textContent: "Current session",
                closest: () => card,
              };
              const documentLike = {
                querySelector: () => null,
                querySelectorAll: selector => selector.includes("h1, h2")
                  ? [...decoys, label]
                  : [],
              };
              const locationLike = {
                protocol: "https:", origin: "https://claude.ai", pathname: "/new",
                search: "", hash: "#settings/usage",
              };
              const observation = UMAClaudeUsageExtractor.extract(
                documentLike,
                locationLike,
                new Date("2026-08-01T14:00:00Z")
              );
              return observation !== null
                && observation.fiveHour.usedPercentage === 44
                && UMAClaudeUsageExtractor.CONTRACT.maximumLabelElementCount === 4096;
            })()
            """
        )?.toBool()
        #expect(result == true)
    }

    @Test @MainActor
    func extractorRevalidatesTheExactRouteAfterReadingThePage() throws {
        let context = try #require(JSContext())
        let source = try String(
            contentsOf: browserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/claude-usage-extractor.js"
            ),
            encoding: .utf8
        )
        context.evaluateScript(source)
        let result = context.evaluateScript(
            """
            (() => {
              const percentage = { textContent: "44%", getAttribute: () => null };
              const card = {
                querySelectorAll: selector => selector.includes("time[") ? [] : [percentage],
              };
              const label = {
                childElementCount: 0,
                textContent: "Current session",
                closest: () => card,
              };
              const documentLike = {
                querySelector: () => null,
                querySelectorAll: selector => selector.includes("h1, h2") ? [label] : [],
              };
              let hashReads = 0;
              const locationLike = {
                protocol: "https:",
                origin: "https://claude.ai",
                pathname: "/new",
                search: "",
                get hash() {
                  hashReads += 1;
                  return hashReads === 1 ? "#settings/usage" : "#settings/account";
                },
              };
              return UMAClaudeUsageExtractor.extract(
                documentLike,
                locationLike,
                new Date("2026-08-01T14:00:00Z")
              ) === null;
            })()
            """
        )?.toBool()
        #expect(result == true)
    }

    @Test @MainActor
    func extractorIgnoresPromotionalNumbersButAcceptsOneExplicitPercentage() throws {
        let context = try #require(JSContext())
        let source = try String(
            contentsOf: browserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/claude-usage-extractor.js"
            ),
            encoding: .utf8
        )
        context.evaluateScript(source)
        let result = context.evaluateScript(
            """
            (() => {
              const percentage = {
                textContent: "44%",
                getAttribute: () => null,
              };
              const promotion = {
                textContent: "100 Credits",
                getAttribute: () => null,
              };
              const multiplier = {
                textContent: "5",
                getAttribute: () => null,
              };
              const card = {
                querySelectorAll: selector => selector.includes("time[")
                  ? []
                  : [percentage, promotion, multiplier],
              };
              const label = {
                childElementCount: 0,
                textContent: "Current session",
                closest: () => card,
              };
              const documentLike = {
                querySelector: () => null,
                querySelectorAll: selector => selector.includes("h1, h2") ? [label] : [],
              };
              const locationLike = {
                protocol: "https:", origin: "https://claude.ai", pathname: "/new",
                search: "", hash: "#settings/usage",
              };
              const observation = UMAClaudeUsageExtractor.extract(
                documentLike,
                locationLike,
                new Date("2026-08-01T14:00:00Z")
              );
              return observation !== null
                && observation.fiveHour.usedPercentage === 44;
            })()
            """
        )?.toBool()
        #expect(result == true)
    }

    @Test @MainActor
    func extractorRejectsMalformedAmbiguousResetsAndDuplicateCards() throws {
        let context = try #require(JSContext())
        let source = try String(
            contentsOf: browserRepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/claude-usage-extractor.js"
            ),
            encoding: .utf8
        )
        context.evaluateScript(source)
        let result = context.evaluateScript(
            """
            (() => {
              const locationLike = {
                protocol: "https:", origin: "https://claude.ai", pathname: "/new",
                search: "", hash: "#settings/usage",
              };
              const percentage = { textContent: "44%", getAttribute: () => null };
              const reset = {
                textContent: "",
                getAttribute: name => name === "datetime"
                  ? "2026-08-01T15:00:00Z"
                  : (name === "data-reset-at" ? "2026-08-01T16:00:00Z" : null),
              };
              const card = {
                querySelectorAll: selector => selector.includes("time[") ? [reset] : [percentage],
              };
              const label = {
                childElementCount: 0,
                textContent: "Current session",
                closest: () => card,
              };
              const ambiguousDocument = {
                querySelector: () => null,
                querySelectorAll: selector => selector.includes("h1, h2") ? [label] : [],
              };
              const duplicateLabel = { ...label, closest: () => ({ ...card }) };
              const duplicateDocument = {
                querySelector: () => null,
                querySelectorAll: selector => selector.includes("h1, h2")
                  ? [label, duplicateLabel]
                  : [],
              };
              return UMAClaudeUsageExtractor.extract(
                ambiguousDocument,
                locationLike,
                new Date("2026-08-01T14:00:00Z")
              ) === null
                && UMAClaudeUsageExtractor.extract(
                  duplicateDocument,
                  locationLike,
                  new Date("2026-08-01T14:00:00Z")
                ) === null;
            })()
            """
        )?.toBool()
        #expect(result == true)
    }

    @Test
    func chromiumKeepsManualActionWhileSafariAutomationOwnsOneInactiveTab() throws {
        let root = browserRepositoryRoot()
        let background = try String(
            contentsOf: root.appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )
        #expect(background.contains("api.action?.onClicked?.addListener((tab)"))
        #expect(background.contains("allowedSenderURL(tab?.url || \"\")"))
        #expect(background.contains("api.scripting.executeScript"))
        #expect(background.contains("api.tabs.create({ url: extractor.CONTRACT.href, active: false })"))
        #expect(background.contains("api.tabs.remove(record.tabID)"))
        #expect(background.contains("await proveOwnedTab(record, tab)"))
        #expect(background.contains("ownedTabOwnershipLost"))
        #expect(background.contains("api.runtime.connectNative(config.nativeApplication)"))
        for forbidden in [
            "tabs.onUpdated",
            "tabs.onCreated",
            "tabs.query",
            "webNavigation",
            "setInterval",
        ] {
            #expect(!background.contains(forbidden))
        }
    }

    @Test
    func healthStatesMapToSafePresentationWithoutQuotaFabrication() async {
        let matrix: [(ClaudeBrowserCompanionHealth, ClaudeConnectorLifecycleState)] = [
            (.disabled, .companionDisabled),
            (.outdated, .companionOutdated),
            (.unsupportedBrowser, .unsupportedBrowser),
            (.browserUnavailable, .browserUnavailable),
            (.nativeHostMissing, .nativeHostMissing),
            (.nativeHostMismatched, .nativeHostMismatched),
        ]
        for (health, expected) in matrix {
            let fixture = BrowserConnectorFixture(consent: true)
            await fixture.bridge.setHealth(health)
            let connector = fixture.connector()
            await connector.checkCompanion()
            #expect(await connector.lifecycleState() == expected)
            #expect(!(await connector.currentSnapshot()).hasValidData)
        }
    }

    @Test
    func browserFamilyDoesNotChangeSharedQuotaSemantics() async {
        for family in ClaudeBrowserFamily.allCases {
            let fixture = BrowserConnectorFixture(consent: true)
            let connector = fixture.connector()
            await connector.start()
            await fixture.bridge.send(
                browserEnvelope(five: 25, seven: 50, browser: family)
            )
            let snapshot = await connector.currentSnapshot()
            #expect(snapshot.channels[0].rateLimitWindows.map(\.normalizedRemainingPercent) == [75, 50])
            #expect(snapshot.channels[0].coverageNote?.contains("Browser Sync") == true)
        }
    }

    @Test
    func optionalModelWindowNeverReplacesAccountSevenDayWindow() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        let envelope = ClaudeBrowserObservationEnvelope(
            browserFamily: .safari,
            observation: ClaudeBrowserObservation(
                fiveHour: ClaudeBrowserQuotaWindow(usedPercentage: 10),
                weeklyAllModels: ClaudeBrowserQuotaWindow(usedPercentage: 20),
                modelSpecificWeekly: ClaudeBrowserModelWindow(
                    modelFamily: .sonnet,
                    window: ClaudeBrowserQuotaWindow(usedPercentage: 30)
                ),
                observedAt: "2030-03-01T12:00:00Z"
            )
        )
        await fixture.bridge.send(envelope)
        let windows = await connector.currentSnapshot().channels[0].rateLimitWindows
        #expect(windows.first { $0.kind == .sevenDay }?.normalizedRemainingPercent == 80)
        #expect(windows.first { $0.kind == .other }?.normalizedRemainingPercent == 70)
        #expect(windows.first { $0.kind == .other }?.id == "weekly-sonnet")
    }

    @Test
    func diagnosticsContainCountsOnly() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.start()
        await fixture.bridge.send(browserEnvelope(five: 20, seven: 40))
        await connector.syncNow()
        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.acceptedObservationCount == 1)
        #expect(diagnostics.rejectedObservationCount == 0)
        #expect(diagnostics.pageOpenCount == 0)
        #expect(diagnostics.automaticDispatchCount == 1)
        #expect(diagnostics.listenerStartCount == 1)
        #expect(!String(reflecting: diagnostics).lowercased().contains("identity"))
    }

    @Test
    func retiredCredentialRoutesAreAbsentFromActiveSources() throws {
        let root = browserRepositoryRoot()
        let active = [
            "Sources/CodexUsageUI",
            "Sources/ClaudeBrowserBridgeProtocol",
            "Sources/ClaudeBrowserNativeHostCore",
            "Sources/ClaudeBrowserNativeHost",
            "BrowserExtension",
        ]
        let forbidden = [
            "ClaudeQuotaBroker",
            "Claude Code-credentials",
            "/api/oauth/usage",
            "Authorization: Bearer",
            "SecItemCopyMatching",
            "kSecClassGenericPassword",
        ]
        for relative in active {
            let text = try sourceTree(root.appendingPathComponent(relative))
            for value in forbidden { #expect(!text.contains(value)) }
        }
    }
}

private func sourceTree(_ root: URL) throws -> String {
    var result = ""
    let enumerator = try #require(FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ))
    for case let url as URL in enumerator {
        guard ["swift", "js", "json", "plist", "entitlements"].contains(url.pathExtension)
        else { continue }
        result += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    return result
}

private func browserRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
