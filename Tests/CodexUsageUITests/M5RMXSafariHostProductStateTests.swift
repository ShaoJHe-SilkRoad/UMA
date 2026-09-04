import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5RMX immutable Safari Host product-state boundary")
struct M5RMXSafariHostProductStateTests {
    private let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("mutable UMA integration is an IPC client, never a Safari containing app")
    func mutableIntegrationOwnsNoSafariRuntimeAuthority() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("import ClaudeSafariHostIPC"))
        #expect(source.contains("ClaudeSafariHostIPCClient"))
        #expect(!source.contains("import SafariServices"))
        #expect(!source.contains("SFSafariApplication"))
        #expect(!source.contains("SFSafariExtensionManager"))
        #expect(!source.contains("builtInPlugInsURL"))
        #expect(!source.contains("ClaudeBrowserFileHandoff"))
        #expect(!source.contains("ClaudeBrowserOwnedTabReceipt"))
    }

    @Test("mutable UMA routes every browser operation through the immutable Host")
    func browserOperationsUseHostIPC() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
            ),
            encoding: .utf8
        )

        for operation in [
            ".verifyCompanion",
            ".accuracySync",
            ".automaticRefresh",
            ".closeOwnedTab",
        ] {
            #expect(source.contains(operation))
        }
        #expect(source.contains("ClaudeSafariHostIPCEndpoint.appGroup("))
        #expect(source.contains("identifier: context.appGroupIdentifier"))
        #expect(source.contains(
            "hostApplicationIdentifier = context.identity.containingApplicationIdentifier"
        ))
        #expect(!source.contains("ClaudeSafariHostIPCContract.hostApplicationIdentifier"))
    }

    @Test("Local Smart construction remains independent from Safari Host IPC")
    func localSmartRemainsIndependent() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/AgentUsageRuntime.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("ClaudeLocalActivityReader()"))
        #expect(source.contains("ClaudeDesktopPlanUsageReader()"))
        #expect(source.contains("let claudeIntegration: ClaudeBrowserProductionIntegration = startProviders"))
        #expect(source.contains("? .make() : .unavailable()"))
        #expect(!source.contains("ClaudeBrowserFileHandoff"))
        #expect(!source.contains("SafariServices"))
    }

    @Test("machine verifier delegates to the Host IPC integration")
    func machineVerifierUsesRealHostIPC() async {
        let integration = ClaudeBrowserProductionIntegration(
            startListening: { _ in },
            stopListening: {},
            checkHealth: { .ready },
            openUsagePage: { true },
            repairCompanion: { .ready },
            verifyHandshake: { .verified }
        )

        #expect(await ClaudeBrowserCompanionMachineVerifier.run(using: integration) == .verified)
    }

    @Test("machine verifier launches Safari only with an explicit diagnostic flag")
    func machineVerifierSafariLaunchIsExplicit() throws {
        let integration = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
            ),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageMonitor/App/CodexUsageMonitorApp.swift"
            ),
            encoding: .utf8
        )

        #expect(integration.contains("allowSafariLaunch: Bool = false"))
        #expect(!integration.contains("diagnose(allowSafariLaunch: true)"))
        #expect(app.contains("allowSafariLaunchArgument"))
        #expect(app.contains("allowSafariLaunch: allowSafariLaunch"))
    }

    @Test("Host IPC failures retain mutable product-state classification")
    func hostFailureClassificationIsNotCollapsedIntoProviderRouting() throws {
        let adapter = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
            ),
            encoding: .utf8
        )
        let connector = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeCodeUsageConnector.swift"
            ),
            encoding: .utf8
        )

        #expect(adapter.contains(".dispatchFailure(.protocolMismatch)"))
        #expect(adapter.contains(".dispatchFailure(.companionUnavailable)"))
        #expect(!adapter.contains("status = .routeRejected"))
        #expect(connector.contains("case dispatchFailure(ClaudeBrowserAutomaticDispatchResult)"))
        #expect(connector.contains("case let .dispatchFailure(result)"))
        #expect(connector.contains(".accuracyProtocolMismatch"))
    }

    @Test("cold start waits for explicit background readiness before qualification")
    func coldStartUsesReadinessGatedQualification() throws {
        let host = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/UMASafariBridgeHost/UMASafariBridgeHostRuntime.swift"
            ),
            encoding: .utf8
        )
        let background = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )

        #expect(host.contains("case awaitingBackgroundReady"))
        #expect(host.contains("case qualificationDispatched"))
        #expect(host.contains("event.status == .extensionBackgroundReady"))
        #expect(host.contains("item.phase == .awaitingBackgroundReady"))
        #expect(host.contains("name: ClaudeBrowserBridgeContract.runtimeQualificationMessageName"))
        #expect(host.contains("item.phase == .qualificationDispatched"))
        #expect(host.contains("backgroundAcknowledgementDeadline: Duration = .seconds(10)"))
        #expect(host.contains("dispatchCompletionDeadline: Duration = .seconds(5)"))
        #expect(host.contains("ClaudeSafariHostDispatchCompletionGate()"))
        #expect(host.contains("reason: .dispatchCompletionUnavailable"))
        #expect(host.contains("nativeQualificationDeadline: Duration = .seconds(10)"))
        #expect(host.contains("providerOperationDeadline: Duration = .seconds(35)"))
        #expect(host.contains("failureReason: .extensionBackgroundNotAcknowledged"))
        #expect(host.contains("failureReason: .nativeResponseUnavailable"))
        #expect(host.contains("failureReason: .providerOperationTimedOut"))

        #expect(background.contains("const runtimeQualificationMessageName = \"umaClaudeRuntimeQualification\""))
        #expect(background.contains("retainRuntimeOperation(announceBackgroundReady(command.requestID, portGeneration));"))
        #expect(background.contains(
            "retainRuntimeOperation(\n          announceBackgroundReady(startupRequestID.toLowerCase(), generation)\n        );"
        ))
        #expect(background.contains("command.command === runtimeQualificationMessageName"))
        #expect(!background.contains("command.command === config.wakeMessageName) {\n      void qualifyRuntime"))
    }

    @Test("Host requires every native qualification receipt before bridgeReady")
    func hostDoesNotInferNativeStagesFromBridgeReady() throws {
        let host = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/UMASafariBridgeHost/UMASafariBridgeHostRuntime.swift"
            ),
            encoding: .utf8
        )
        let adapter = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
            ),
            encoding: .utf8
        )

        for mapping in [
            "case .nativeHandlerEntered: diagnosticStage = .nativeHandlerEntered",
            "case .nativeRequestDecoded: diagnosticStage = .nativeRequestDecoded",
            "case .runtimeGenerationValidated: diagnosticStage = .runtimeGenerationValidated",
            "case .nativeResponseCreated: diagnosticStage = .nativeResponseCreated",
            "case .nativeResponseSent: diagnosticStage = .nativeResponseSent",
            "case .extensionResponseReceived: diagnosticStage = .extensionResponseReceived",
        ] {
            #expect(host.contains(mapping))
        }
        #expect(host.contains("proposed == current + 1"))
        #expect(host.contains(
            "guard item.verificationStage == .extensionResponseReceived else"
        ))

        for mapping in [
            "case .nativeHandlerEntered:\n                [.nativeHandlerEntered]",
            "case .nativeRequestDecoded:\n                [.nativeRequestDecoded]",
            "case .runtimeGenerationValidated:\n                [.runtimeGenerationValidated]",
            "case .nativeResponseCreated:\n                [.nativeResponseCreated]",
            "case .nativeResponseSent:\n                [.nativeResponseSent]",
            "case .extensionResponseReceived:\n                [.extensionResponseReceived]",
            "case .nativeQualificationReceived:\n                [.nativeQualificationReceived]",
        ] {
            #expect(adapter.contains(mapping))
        }
    }

    @Test("Host serializes work and transports successful cleanup causally")
    func hostSerializesAndCausallyCompletesWork() throws {
        let host = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/UMASafariBridgeHost/UMASafariBridgeHostRuntime.swift"
            ),
            encoding: .utf8
        )
        let ipc = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/ClaudeSafariHostIPC/ClaudeSafariHostIPC.swift"
            ),
            encoding: .utf8
        )

        #expect(host.contains("else if !pending.isEmpty"))
        #expect(host.contains("reason: .requestInFlight"))
        #expect(host.contains("reason: .duplicateRequest"))
        #expect(host.contains("var observation: ClaudeBrowserObservationEnvelope?"))
        #expect(host.contains("var completionEvent: ClaudeBrowserAutomationEvent?"))
        #expect(host.contains("case awaitingObservationAfterCompletion"))
        #expect(host.contains("outcome: .completed"))
        #expect(host.contains("failureReason: .observationMissing"))
        #expect(host.contains("func receive(_ terminal: ClaudeBrowserTerminalPacket)"))
        #expect(host.contains("providerFailureReason: terminal.providerFailureReason"))
        #expect(host.contains("item.phase != .cleanupDispatched"))
        #expect(host.contains("try responder.send(response)"))
        #expect(ipc.contains("automationEvent?.status == .refreshCompleted"))
        #expect(ipc.contains("providerFailureReason == nil"))
    }

    @Test("close command has a distinct correlation ID and exact target")
    func closeCommandCannotAliasTargetOperation() throws {
        let host = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/UMASafariBridgeHost/UMASafariBridgeHostRuntime.swift"
            ),
            encoding: .utf8
        )
        let adapter = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeSafariHostClientAdapter.swift"
            ),
            encoding: .utf8
        )

        #expect(adapter.contains("let commandID = UUID().uuidString.lowercased()"))
        #expect(adapter.contains("targetRequestID: requestID"))
        #expect(adapter.contains("activeWorkRequestIDs.isEmpty"))
        #expect(adapter.contains("activeWorkRequestIDs.contains(response.requestID)"))
        let activeRegistration = try #require(adapter.range(
            of: "activeWorkRequestIDs.insert(normalizedRequestID)"
        ))
        let requestPublication = try #require(adapter.range(
            of: "try client.submit(.init("
        ))
        #expect(activeRegistration.lowerBound < requestPublication.lowerBound)
        #expect(host.contains("pending[targetRequestID] != nil"))
        #expect(host.contains("await beginCleanup("))
        #expect(host.contains("cleanup.targetRequestID == targetRequestID"))
        #expect(host.contains("terminal.status == .ownedTabClosed"))
        #expect(host.contains("userInfo[\"targetRequestID\"] = targetRequestID"))
    }
}
