import ClaudeBrowserBridgeProtocol
import Foundation
import JavaScriptCore
import Testing
@testable import CodexUsageUI

@Suite("M5 Local Smart one-shot Accuracy acceptance")
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
                  === "extractorSchemaVersion,fiveHour,modelSpecificWeekly,observedAt,sourceLayoutVersion,weeklyAllModels";
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
    func chromiumKeepsManualActionWhileOneShotAccuracyOwnsOneInactiveTab() throws {
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
        #expect(background.contains("api.tabs.create({ url: providerURL, active: false })"))
        #expect(background.contains("providerURLForNonce(read.rawNonce)"))
        #expect(!background.contains("tabs.query({})"))
        #expect(!background.contains("api.tabs.query("))
        #expect(background.contains("api.tabs.remove(read.providerOwnedTabID)"))
        #expect(background.contains("acceptV2ProviderOwnership"))
        #expect(background.contains("ownedTabOwnershipLost"))
        #expect(background.contains("api.runtime.sendNativeMessage(config.nativeApplication"))
        #expect(background.contains("api.runtime.connectNative(config.nativeApplication)"))
        #expect(background.contains("config.browserFamily !== \"safari\""))
        #expect(!background.contains("nativeReconnectTimer"))
        for forbidden in [
            "tabs.onCreated",
            "webNavigation",
            "setInterval",
        ] {
            #expect(!background.contains(forbidden))
        }
        #expect(background.contains("api.tabs.onRemoved.addListener(removalListener)"))
        #expect(background.contains("api.tabs.onReplaced?.addListener?.(replacementListener)"))
        #expect(!background.contains("api.tabs.get(read.tabID)"))
    }

    @Test
    func browserHealthOnlyBoundsExplicitAccuracyAndNeverFabricatesLocalTruth() async {
        let matrix: [ClaudeBrowserCompanionHealth] = [
            .disabled,
            .outdated,
            .unsupportedBrowser,
            .browserUnavailable,
            .nativeHostMissing,
            .nativeHostMismatched,
        ]
        for health in matrix {
            let fixture = BrowserConnectorFixture(consent: true)
            await fixture.bridge.setHealth(health)
            let connector = fixture.connector()
            await connector.checkCompanion()
            await connector.accuracySync()
            #expect(!(await connector.currentSnapshot()).hasValidData)
            #expect(await fixture.bridge.automaticRequests.isEmpty)
            #expect(!(await connector.diagnostics()).schedulerActive)
        }
    }

    @Test
    func productionHealthAndRepairFailClosedForChromiumDefaults() throws {
        let production = try String(
            contentsOf: browserRepositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
            ),
            encoding: .utf8
        )
        #expect(!production.contains("case .chromium"))
        #expect(production.contains("guard let runtime = ClaudeSafariHostClientAdapter()"))
        #expect(!production.contains(
            "return chromiumNativeHostManifestExists()"
        ))
    }

    @Test
    func browserFamilyDoesNotChangeSharedQuotaSemantics() async {
        for family in ClaudeBrowserFamily.allCases {
            let fixture = BrowserConnectorFixture(consent: true)
            let connector = fixture.connector()
            await connector.accuracySync()
            await fixture.bridge.send(
                browserEnvelope(five: 25, seven: 50, browser: family)
            )
            let snapshot = await connector.currentSnapshot()
            let channel = try? #require(snapshot.channels.first)
            #expect(channel?.rateLimitWindows.map(\.normalizedRemainingPercent) == [75, 50])
            #expect(channel?.coverageNote?.contains("Local Smart") == true)
        }
    }

    @Test
    func duplicateObservationNonceIsRejectedWithoutReplacingLastValidQuota() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.accuracySync()
        let observation = browserEnvelope(five: 25, seven: 50, browser: .safari)

        await fixture.bridge.send(observation)
        await fixture.bridge.send(observation)

        let diagnostics = await connector.diagnostics()
        #expect(diagnostics.acceptedObservationCount == 1)
        #expect(diagnostics.rejectedObservationCount == 1)
        let snapshot = await connector.currentSnapshot()
        #expect(snapshot.hasValidData)
        let channel = try? #require(snapshot.channels.first)
        #expect(channel?.rateLimitWindows.map(\.normalizedRemainingPercent) == [75, 50])
    }

    @Test
    func unsupportedModelWindowIsDiscardedWithoutFabricatingAccountTruth() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.accuracySync()
        let envelope = ClaudeBrowserObservationEnvelope(
            browserFamily: .safari,
            observation: ClaudeBrowserObservation(
                fiveHour: ClaudeBrowserQuotaWindow(
                    usedPercentage: 10,
                    resetAt: "2030-03-01T17:00:00Z"
                ),
                weeklyAllModels: ClaudeBrowserQuotaWindow(
                    usedPercentage: 20,
                    resetAt: "2030-03-08T12:00:00Z"
                ),
                modelSpecificWeekly: ClaudeBrowserModelWindow(
                    modelFamily: .sonnet,
                    window: ClaudeBrowserQuotaWindow(
                        usedPercentage: 30,
                        resetAt: "2030-03-08T12:00:00Z"
                    )
                ),
                observedAt: "2030-03-01T12:00:00Z"
            )
        )
        await fixture.bridge.send(envelope)
        let snapshot = await connector.currentSnapshot()
        let windows = (try? #require(snapshot.channels.first))?.rateLimitWindows ?? []
        #expect(windows.first { $0.kind == .fiveHour }?.normalizedRemainingPercent == 90)
        #expect(windows.first { $0.kind == .sevenDay }?.normalizedRemainingPercent == 80)
        #expect(windows.first { $0.kind == .other } == nil)
        #expect(windows.count == 2)
        #expect((await connector.diagnostics()).acceptedObservationCount == 1)
        #expect((await connector.diagnostics()).rejectedObservationCount == 0)
    }

    @Test
    func diagnosticsContainCountsOnly() async {
        let fixture = BrowserConnectorFixture(consent: true)
        let connector = fixture.connector()
        await connector.accuracySync()
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
    func credentialRoutesStayAbsentWhileSanitizedStatusLineTargetsAreActive() throws {
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
        let package = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        #expect(package.contains("ClaudeStatusLineCore"))
        #expect(package.contains("ClaudeStatusLineRelay"))
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
