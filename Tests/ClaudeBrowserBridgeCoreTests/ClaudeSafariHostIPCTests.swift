import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import ClaudeSafariHostIPC
import Darwin
import Dispatch
import Foundation
import Testing

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClaudeSafariHostIPCTests {
    @Test
    func dispatchCompletionGateAcceptsTheFirstCausalResultOnly() async {
        let callbackFirst = ClaudeSafariHostDispatchCompletionGate()
        #expect(callbackFirst.resolve(.accepted))
        #expect(!callbackFirst.resolve(.deadlineExpired))
        #expect(await callbackFirst.wait() == .accepted)

        let waiterFirst = ClaudeSafariHostDispatchCompletionGate()
        let waiting = Task { await waiterFirst.wait() }
        #expect(waiterFirst.resolve(.deadlineExpired))
        #expect(!waiterFirst.resolve(.accepted))
        #expect(await waiting.value == .deadlineExpired)
    }

    @Test
    func coldStartPolicyRequiresReadinessBeforeDispatch() {
        #expect(ClaudeSafariHostColdStartPolicy.action(
            safariProcessPresent: true,
            safariFinishedLaunching: true,
            allowSafariLaunch: false
        ) == .dispatch)
        #expect(ClaudeSafariHostColdStartPolicy.action(
            safariProcessPresent: true,
            safariFinishedLaunching: false,
            allowSafariLaunch: false
        ) == .failSafariUnavailable)
        #expect(ClaudeSafariHostColdStartPolicy.action(
            safariProcessPresent: false,
            safariFinishedLaunching: false,
            allowSafariLaunch: false
        ) == .failSafariUnavailable)
    }

    @Test
    func explicitlyAuthorizedColdStartUsesOneLaunchEvent() {
        for state in [(false, false), (true, false)] {
            #expect(ClaudeSafariHostColdStartPolicy.action(
                safariProcessPresent: state.0,
                safariFinishedLaunching: state.1,
                allowSafariLaunch: true
            ) == .launchSafari)
        }
        #expect(ClaudeSafariHostColdStartPolicy.action(
            safariProcessPresent: true,
            safariFinishedLaunching: true,
            allowSafariLaunch: true
        ) == .dispatch)
    }

    @Test
    func workspaceLaunchCallbackWaitsForTheMatchingReadinessEvent() {
        #expect(ClaudeSafariHostColdStartPolicy.openCallbackAction(
            applicationPresent: true,
            applicationTerminated: false,
            applicationFinishedLaunching: false,
            errorPresent: false
        ) == .waitForLaunchEvent)
        #expect(ClaudeSafariHostColdStartPolicy.openCallbackAction(
            applicationPresent: true,
            applicationTerminated: false,
            applicationFinishedLaunching: true,
            errorPresent: false
        ) == .ready)
        #expect(ClaudeSafariHostColdStartPolicy.openCallbackAction(
            applicationPresent: false,
            applicationTerminated: false,
            applicationFinishedLaunching: false,
            errorPresent: false
        ) == .unavailable)
        #expect(ClaudeSafariHostColdStartPolicy.openCallbackAction(
            applicationPresent: true,
            applicationTerminated: true,
            applicationFinishedLaunching: true,
            errorPresent: false
        ) == .unavailable)
        #expect(ClaudeSafariHostColdStartPolicy.openCallbackAction(
            applicationPresent: true,
            applicationTerminated: false,
            applicationFinishedLaunching: true,
            errorPresent: true
        ) == .unavailable)
        #expect(ClaudeSafariHostColdStartPolicy.launchEventMatches(
            expectedBundleIdentifier: "com.apple.Safari",
            observedBundleIdentifier: "com.apple.Safari",
            applicationTerminated: false
        ))
        #expect(!ClaudeSafariHostColdStartPolicy.launchEventMatches(
            expectedBundleIdentifier: "com.apple.Safari",
            observedBundleIdentifier: "com.example.Unrelated",
            applicationTerminated: false
        ))
    }

    @Test
    func workspaceLaunchReadinessGateAcceptsOneCausalTerminalResult() async {
        let eventFirst = ClaudeSafariHostApplicationReadinessGate()
        #expect(eventFirst.resolve(.ready))
        #expect(!eventFirst.resolve(.deadlineExpired))
        #expect(await eventFirst.wait() == .ready)

        let deadlineFirst = ClaudeSafariHostApplicationReadinessGate()
        let waiting = Task { await deadlineFirst.wait() }
        #expect(deadlineFirst.resolve(.deadlineExpired))
        #expect(!deadlineFirst.resolve(.ready))
        #expect(await waiting.value == .deadlineExpired)
    }

    @Test
    func launchAuthorityIsNeverValidForOwnedTabCancellation() {
        #expect(!ClaudeSafariHostIPCRequest(
            runtimeGenerationID: "671a4271-769b-4d85-8e02-2d69c030057a",
            operation: .closeOwnedTab,
            targetRequestID: "ffffffff-ffff-4fff-8fff-ffffffffffff",
            allowSafariLaunch: true
        ).isStructurallyValid)
        #expect(ClaudeSafariHostIPCRequest(
            runtimeGenerationID: "671a4271-769b-4d85-8e02-2d69c030057a",
            operation: .verifyCompanion,
            allowSafariLaunch: true
        ).isStructurallyValid)
    }

    @Test
    func launchAuthorityIsLimitedToExplicitVerificationAndAccuracySync() {
        let generation = "5448e5ab-49a5-4c3f-b2c2-54c5b36d12fa"
        #expect(ClaudeSafariHostIPCRequest(
            runtimeGenerationID: generation,
            operation: .verifyCompanion,
            allowSafariLaunch: true
        ).isStructurallyValid)
        #expect(ClaudeSafariHostIPCRequest(
            runtimeGenerationID: generation,
            operation: .accuracySync,
            allowSafariLaunch: true
        ).isStructurallyValid)
        #expect(!ClaudeSafariHostIPCRequest(
            runtimeGenerationID: generation,
            operation: .automaticRefresh,
            allowSafariLaunch: true
        ).isStructurallyValid)
    }

    @Test
    func dedicatedHostIdentityIsIsolatedFromMutableUMA() {
        let host = ClaudeBrowserRuntimeIdentity.testSafariHost
        #expect(host.channel == .testSafariHost)
        #expect(host.containingApplicationIdentifier
            == "com.silkrd.uma.test.safarihost")
        #expect(host.extensionIdentifier
            == "com.silkrd.uma.test.safarihost.ClaudeBrowserCompanion")
        #expect(host.nativeApplicationIdentifier
            == host.containingApplicationIdentifier)
        #expect(host.containingApplicationIdentifier
            != ClaudeBrowserRuntimeIdentity.test.containingApplicationIdentifier)
        #expect(host.extensionIdentifier
            != ClaudeBrowserRuntimeIdentity.test.extensionIdentifier)
        #expect(ClaudeSafariHostIPCContract.appGroupIdentifier
            == "group.com.silkrd.uma.test.bridge")
        #expect(ClaudeBrowserRuntimeIdentity.matching(
            extensionIdentifier: host.extensionIdentifier
        ) == host)
    }

    @Test
    func productionHostKeepsEstablishedCompanionIdentityAndRejectsMixedChannels() {
        let profile = ClaudeSafariHostRuntimeProfile.production
        #expect(profile.mutableApplicationIdentifier == "com.silkrd.uma")
        #expect(profile.identity.channel == .productionSafariHost)
        #expect(profile.identity.containingApplicationIdentifier
            == "com.silkrd.uma.safarihost")
        #expect(profile.identity.extensionIdentifier
            == "com.silkrd.uma.ClaudeBrowserCompanion")
        #expect(profile.appGroupIdentifier == "group.com.silkrd.uma.bridge")
        #expect(ClaudeSafariHostIPCContract.accepts(
            hostApplicationIdentifier: profile.identity.containingApplicationIdentifier,
            extensionIdentifier: profile.identity.extensionIdentifier
        ))
        #expect(!ClaudeSafariHostIPCContract.accepts(
            hostApplicationIdentifier: profile.identity.containingApplicationIdentifier,
            extensionIdentifier:
                ClaudeSafariHostRuntimeProfile.test.identity.extensionIdentifier
        ))
        #expect(!ClaudeSafariHostIPCContract.accepts(
            hostApplicationIdentifier:
                ClaudeSafariHostRuntimeProfile.test.identity.containingApplicationIdentifier,
            extensionIdentifier: profile.identity.extensionIdentifier
        ))

        let descriptor = ClaudeSafariHostIPCRuntimeDescriptor(
            hostApplicationIdentifier: profile.identity.containingApplicationIdentifier,
            extensionIdentifier: profile.identity.extensionIdentifier,
            teamIdentifier: ClaudeBrowserBridgeContract.expectedTeamIdentifier,
            hostVersion: "1.5.0",
            hostBuild: "202608290001",
            runtimeGenerationID: UUID().uuidString.lowercased(),
            bridgeProtocolVersion: ClaudeBrowserBridgeContract.schemaVersion
        )
        #expect(descriptor.isStructurallyValid)
    }

    @Test
    func requestSchemaContainsOnlyBoundedCorrelationMetadata() throws {
        let request = ClaudeSafariHostIPCRequest(
            requestID: "2534cd98-23ef-4d73-8f78-34421c99c950",
            runtimeGenerationID: "7d75b979-726d-4e60-87f3-6b8ce88d8024",
            operation: .accuracySync
        )
        let data = try JSONEncoder().encode(request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == Set([
            "allowSafariLaunch", "createdAt", "operation", "requestID",
            "runtimeGenerationID", "schemaVersion",
        ]))
        let lower = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in [
            "url", "html", "dom", "cookie", "token", "credential",
            "identity", "account", "prompt", "response", "tabid",
        ] {
            #expect(!lower.contains(forbidden))
        }
        #expect(request.isStructurallyValid)
        #expect(request.schemaVersion == 2)
    }

    @Test
    func closeCommandUsesDistinctCommandAndTargetRequestIDs() throws {
        let command = ClaudeSafariHostIPCRequest(
            requestID: "59ad0283-9b7d-447a-af77-d5df91e8a6df",
            runtimeGenerationID: "7d75b979-726d-4e60-87f3-6b8ce88d8024",
            operation: .closeOwnedTab,
            targetRequestID: "1f255c50-6371-4f8f-a9b4-7bcb5dbbfd67"
        )
        #expect(command.isStructurallyValid)
        let data = try JSONEncoder().encode(command)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["requestID"] as? String == command.requestID)
        #expect(object["targetRequestID"] as? String == command.targetRequestID)

        #expect(!ClaudeSafariHostIPCRequest(
            requestID: command.requestID,
            runtimeGenerationID: command.runtimeGenerationID,
            operation: .closeOwnedTab
        ).isStructurallyValid)
        #expect(!ClaudeSafariHostIPCRequest(
            requestID: command.requestID,
            runtimeGenerationID: command.runtimeGenerationID,
            operation: .closeOwnedTab,
            targetRequestID: command.requestID
        ).isStructurallyValid)
        #expect(!ClaudeSafariHostIPCRequest(
            requestID: command.requestID,
            runtimeGenerationID: command.runtimeGenerationID,
            operation: .accuracySync,
            targetRequestID: command.targetRequestID
        ).isStructurallyValid)
    }

    @Test
    func generationBoundTerminalPacketIsAtomicAndCleanupCorrelated() throws {
        let requestID = "b8340c0a-a046-48a5-8d31-981364652a8b"
        let commandID = "59ad0283-9b7d-447a-af77-d5df91e8a6df"
        let generation = "b9f8d8f9-c844-4ee0-b1df-aef3e22c884f"
        let observation = ClaudeBrowserObservationEnvelope(
            browserFamily: .safari,
            observation: .init(
                fiveHour: .init(usedPercentage: 25),
                weeklyAllModels: nil,
                observedAt: "2026-08-27T12:00:00Z"
            ),
            requestID: requestID
        )
        let success = ClaudeBrowserTerminalPacket(
            requestID: requestID,
            runtimeGenerationID: generation,
            status: .refreshCompleted,
            occurredAt: "2026-08-27T12:00:01Z",
            observation: observation
        )
        #expect(try ClaudeBrowserTerminalPacketDecoder.decode(
            ClaudeBrowserTerminalPacketDecoder.encode(success)
        ) == success)

        let close = ClaudeBrowserTerminalPacket(
            requestID: commandID,
            targetRequestID: requestID,
            runtimeGenerationID: generation,
            status: .ownedTabClosed,
            occurredAt: "2026-08-27T12:00:02Z"
        )
        #expect(try ClaudeBrowserTerminalPacketDecoder.decode(
            ClaudeBrowserTerminalPacketDecoder.encode(close)
        ) == close)

        let providerFailure = ClaudeBrowserTerminalPacket(
            requestID: requestID,
            runtimeGenerationID: generation,
            status: .usageUnavailable,
            occurredAt: "2026-08-27T12:00:03Z",
            providerFailureReason: .providerStructureUnsupported
        )
        #expect(try ClaudeBrowserTerminalPacketDecoder.decode(
            ClaudeBrowserTerminalPacketDecoder.encode(providerFailure)
        ) == providerFailure)

        let permissionFailure = ClaudeBrowserTerminalPacket(
            requestID: requestID,
            runtimeGenerationID: generation,
            status: .permissionRequired,
            occurredAt: "2026-08-27T12:00:04Z",
            providerFailureReason: .sitePermissionMissing
        )
        #expect(try ClaudeBrowserTerminalPacketDecoder.decode(
            ClaudeBrowserTerminalPacketDecoder.encode(permissionFailure)
        ) == permissionFailure)

        let closedTabFailure = ClaudeBrowserTerminalPacket(
            requestID: requestID,
            runtimeGenerationID: generation,
            status: .tabUnavailable,
            occurredAt: "2026-08-27T12:00:05Z",
            providerFailureReason: .providerTabClosed
        )
        #expect(try ClaudeBrowserTerminalPacketDecoder.decode(
            ClaudeBrowserTerminalPacketDecoder.encode(closedTabFailure)
        ) == closedTabFailure)

        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserTerminalPacketDecoder.encode(.init(
                requestID: requestID,
                runtimeGenerationID: generation,
                status: .refreshCompleted,
                occurredAt: "2026-08-27T12:00:01Z"
            ))
        }
        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserTerminalPacketDecoder.encode(.init(
                requestID: requestID,
                runtimeGenerationID: generation,
                status: .refreshCompleted,
                occurredAt: "2026-08-27T12:00:01Z",
                observation: observation,
                providerFailureReason: .targetDataTimeout
            ))
        }
        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserTerminalPacketDecoder.encode(.init(
                requestID: commandID,
                targetRequestID: requestID,
                runtimeGenerationID: generation,
                status: .ownedTabOwnershipLost,
                occurredAt: "2026-08-27T12:00:02Z",
                providerFailureReason: .providerTabClosed
            ))
        }

        var unknownReason = try JSONSerialization.jsonObject(
            with: ClaudeBrowserTerminalPacketDecoder.encode(providerFailure)
        ) as! [String: Any]
        unknownReason["providerFailureReason"] = "RAW_PROVIDER_TEXT"
        let unknownReasonData = try JSONSerialization.data(withJSONObject: unknownReason)
        #expect(throws: ClaudeBrowserBridgeError.malformedJSON) {
            try ClaudeBrowserTerminalPacketDecoder.decode(unknownReasonData)
        }
        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserTerminalPacketDecoder.encode(.init(
                requestID: commandID,
                targetRequestID: requestID,
                runtimeGenerationID: generation,
                status: .ownedTabOwnershipLost,
                occurredAt: "2026-08-27T12:00:02Z",
                observation: observation
            ))
        }
    }

    @Test
    func coldStartDrainsRequestWrittenBeforeHostListenerStarts() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeSafariHostIPCEndpoint(
            rootDirectoryPath: root.appendingPathComponent("IPC").path
        )
        let request = ClaudeSafariHostIPCRequest(
            requestID: "344ec7a2-0aab-47b0-848d-d6ac86eb6c5a",
            runtimeGenerationID: "671a4271-769b-4d85-8e02-2d69c030057a",
            operation: .verifyCompanion
        )
        try ClaudeSafariHostIPCClient(endpoint: endpoint).submit(request)

        let received = LockedValue<ClaudeSafariHostIPCRequest?>(nil)
        let server = ClaudeSafariHostIPCRequestServer(endpoint: endpoint) { value in
            received.withLock { $0 = value }
        }
        try server.start()
        defer { server.stop() }
        try await received.wait { $0 != nil }
        #expect(received.snapshot == request)
    }

    @Test
    func coldStartPreservesCreationOrderRatherThanLexicalUUIDOrder() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeSafariHostIPCEndpoint(
            rootDirectoryPath: root.appendingPathComponent("IPC").path
        )
        let generation = "671a4271-769b-4d85-8e02-2d69c030057a"
        let first = ClaudeSafariHostIPCRequest(
            requestID: "ffffffff-ffff-4fff-8fff-ffffffffffff",
            runtimeGenerationID: generation,
            operation: .verifyCompanion
        )
        let second = ClaudeSafariHostIPCRequest(
            requestID: "00000000-0000-4000-8000-000000000001",
            runtimeGenerationID: generation,
            operation: .verifyCompanion
        )
        let client = ClaudeSafariHostIPCClient(endpoint: endpoint)
        try client.submit(first)
        try client.submit(second)
        // The mailbox orders by modification time, not lexical UUID. Give
        // these owned fixtures explicit times rather than waiting for a clock tick.
        let fixtureTime = Date().timeIntervalSince1970
        for (request, timestamp) in [(first, fixtureTime - 1), (second, fixtureTime)] {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: timestamp)],
                ofItemAtPath: endpoint.requestDirectoryPath + "/" + request.requestID + ".json"
            )
        }

        let received = LockedValue<[String]>([])
        let server = ClaudeSafariHostIPCRequestServer(endpoint: endpoint) { value in
            received.withLock { $0.append(value.requestID) }
        }
        try server.start()
        defer { server.stop() }
        try await received.wait { $0.count == 2 }
        #expect(received.snapshot == [first.requestID, second.requestID])
    }

    @Test
    func nativeHandoffColdStartDrainsExistingTerminalInsteadOfDeletingIt() async throws {
        let root = try makeRoot().appendingPathComponent("Native", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let endpoint = ClaudeBrowserFileHandoffEndpoint(directoryPath: root.path)
        let packet = ClaudeBrowserTerminalPacket(
            requestID: "b8340c0a-a046-48a5-8d31-981364652a8b",
            runtimeGenerationID: "b9f8d8f9-c844-4ee0-b1df-aef3e22c884f",
            status: .usageUnavailable,
            occurredAt: "2026-08-27T12:00:01Z"
        )
        try ClaudeBrowserTerminalPacketDecoder.encode(packet).write(
            to: URL(fileURLWithPath: endpoint.pendingPath),
            options: .withoutOverwriting
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: endpoint.pendingPath
        )

        let received = LockedValue<ClaudeBrowserTerminalPacket?>(nil)
        let server = ClaudeBrowserFileHandoffServer(
            endpoint: endpoint,
            observationHandler: { _ in },
            automationHandler: { _ in },
            terminalHandler: { value in received.withLock { $0 = value } }
        )
        try server.start()
        defer { server.stop() }
        try await received.wait { $0 != nil }
        #expect(received.snapshot == packet)
        #expect(!FileManager.default.fileExists(atPath: endpoint.pendingPath))
    }

    @Test
    func responseListenerAcceptsOneCorrelatedContentFreeVerification() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeSafariHostIPCEndpoint(
            rootDirectoryPath: root.appendingPathComponent("IPC").path
        )
        let requestID = "ae60802e-2d87-4dd3-a2eb-c182c13f980a"
        let generation = "60a06652-5f18-417d-849c-7533a9e28bb3"
        let received = LockedValue<ClaudeSafariHostIPCResponse?>(nil)
        let listener = ClaudeSafariHostIPCClient(endpoint: endpoint)
            .makeResponseListener { response in
                received.withLock { $0 = response }
            }
        try listener.start()
        defer { listener.stop() }
        let response = ClaudeSafariHostIPCResponse(
            requestID: requestID,
            runtimeGenerationID: generation,
            outcome: .companionVerified,
            verificationStage: .companionVerified,
            runtimeDescriptor: .init(
                hostApplicationIdentifier: ClaudeSafariHostIPCContract.hostApplicationIdentifier,
                extensionIdentifier: ClaudeSafariHostIPCContract.hostExtensionIdentifier,
                teamIdentifier: ClaudeBrowserBridgeContract.expectedTeamIdentifier,
                hostVersion: "0.13.0",
                hostBuild: "202608280001",
                runtimeGenerationID: generation,
                bridgeProtocolVersion: ClaudeBrowserBridgeContract.schemaVersion
            )
        )
        try ClaudeSafariHostIPCResponder(endpoint: endpoint).send(response)
        try await received.wait { $0 != nil }
        #expect(received.snapshot == response)
    }

    @Test
    func expiredSuccessfulResponseIsRemovedWithoutDelivery() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeSafariHostIPCEndpoint(
            rootDirectoryPath: root.appendingPathComponent("IPC").path
        )
        let requestID = "b8340c0a-a046-48a5-8d31-981364652a8b"
        let generation = "b9f8d8f9-c844-4ee0-b1df-aef3e22c884f"
        let response = ClaudeSafariHostIPCResponse(
            requestID: requestID,
            runtimeGenerationID: generation,
            outcome: .completed,
            observation: ClaudeBrowserObservationEnvelope(
                browserFamily: .safari,
                observation: ClaudeBrowserObservation(
                    fiveHour: ClaudeBrowserQuotaWindow(usedPercentage: 25),
                    weeklyAllModels: nil,
                    observedAt: "2026-08-27T12:00:00Z"
                ),
                requestID: requestID
            ),
            automationEvent: ClaudeBrowserAutomationEvent(
                requestID: requestID,
                status: .refreshCompleted,
                occurredAt: "2026-08-27T12:00:01Z"
            )
        )
        try ClaudeSafariHostIPCResponder(endpoint: endpoint).send(response)
        let path = endpoint.responseDirectoryPath + "/" + response.responseID + ".json"
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow:
                -(ClaudeSafariHostIPCContract.maximumMessageAge + 1))],
            ofItemAtPath: path
        )

        let delivered = LockedValue<[ClaudeSafariHostIPCResponse]>([])
        let listener = ClaudeSafariHostIPCClient(endpoint: endpoint)
            .makeResponseListener { value in delivered.withLock { $0.append(value) } }
        try await awaitRemoval(at: path) {
            try listener.start()
        }
        listener.stop()

        #expect(delivered.snapshot.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test
    func verificationTerminalCarriesOnlyCausalStageAndSignedRuntimeMetadata() throws {
        let requestID = "ae60802e-2d87-4dd3-a2eb-c182c13f980a"
        let generation = "60a06652-5f18-417d-849c-7533a9e28bb3"
        let response = ClaudeSafariHostIPCResponse(
            requestID: requestID,
            runtimeGenerationID: generation,
            outcome: .failed,
            failureReason: .nativeResponseUnavailable,
            verificationStage: .nativeQualificationDispatched,
            runtimeDescriptor: .init(
                hostApplicationIdentifier: ClaudeSafariHostIPCContract.hostApplicationIdentifier,
                extensionIdentifier: ClaudeSafariHostIPCContract.hostExtensionIdentifier,
                teamIdentifier: ClaudeBrowserBridgeContract.expectedTeamIdentifier,
                hostVersion: "0.13.0",
                hostBuild: "202608280001",
                runtimeGenerationID: generation,
                bridgeProtocolVersion: ClaudeBrowserBridgeContract.schemaVersion
            )
        )
        #expect(response.isStructurallyValid)

        let data = try JSONEncoder().encode(response)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["failureReason"] as? String == "nativeResponseUnavailable")
        #expect(object["verificationStage"] as? String == "nativeQualificationDispatched")
        let descriptor = try #require(object["runtimeDescriptor"] as? [String: Any])
        #expect(descriptor["hostApplicationIdentifier"] as? String
            == ClaudeSafariHostIPCContract.hostApplicationIdentifier)
        #expect(descriptor["extensionIdentifier"] as? String
            == ClaudeSafariHostIPCContract.hostExtensionIdentifier)
        for forbidden in [
            "url", "page", "dom", "html", "quota", "account", "cookie",
            "token", "credential", "payload",
        ] {
            #expect(object[forbidden] == nil)
            #expect(descriptor[forbidden] == nil)
        }
    }

    @Test
    func verificationStagesAreOrderedAndIndependentlyEncodable() throws {
        let stages: [ClaudeSafariHostIPCVerificationStage] = [
            .hostRequestAccepted,
            .wakeDispatchAccepted,
            .extensionBackgroundAcknowledged,
            .nativeQualificationDispatched,
            .nativeHandlerEntered,
            .nativeRequestDecoded,
            .runtimeGenerationValidated,
            .nativeResponseCreated,
            .nativeResponseSent,
            .extensionResponseReceived,
            .nativeQualificationReceived,
            .companionVerified,
        ]
        #expect(ClaudeSafariHostIPCVerificationStage.allCases == stages)

        let requestID = "ae60802e-2d87-4dd3-a2eb-c182c13f980a"
        let generation = "60a06652-5f18-417d-849c-7533a9e28bb3"
        let descriptor = ClaudeSafariHostIPCRuntimeDescriptor(
            hostApplicationIdentifier: ClaudeSafariHostIPCContract.hostApplicationIdentifier,
            extensionIdentifier: ClaudeSafariHostIPCContract.hostExtensionIdentifier,
            teamIdentifier: ClaudeBrowserBridgeContract.expectedTeamIdentifier,
            hostVersion: "0.13.0",
            hostBuild: "202608280001",
            runtimeGenerationID: generation,
            bridgeProtocolVersion: ClaudeBrowserBridgeContract.schemaVersion
        )

        for stage in stages.dropLast() {
            let response = ClaudeSafariHostIPCResponse(
                requestID: requestID,
                runtimeGenerationID: generation,
                outcome: .failed,
                failureReason: .nativeResponseUnavailable,
                verificationStage: stage,
                runtimeDescriptor: descriptor
            )
            #expect(response.isStructurallyValid)
            let object = try #require(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(response))
                    as? [String: Any]
            )
            #expect(object["verificationStage"] as? String == stage.rawValue)
        }
    }

    @Test
    func oneRequestDeliversObservationAndTerminalCleanupInOneCausalResponse() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = ClaudeSafariHostIPCEndpoint(
            rootDirectoryPath: root.appendingPathComponent("IPC").path
        )
        let requestID = "b8340c0a-a046-48a5-8d31-981364652a8b"
        let generation = "b9f8d8f9-c844-4ee0-b1df-aef3e22c884f"
        let values = LockedValue<[ClaudeSafariHostIPCResponse]>([])
        let listener = ClaudeSafariHostIPCClient(endpoint: endpoint)
            .makeResponseListener { response in
                values.withLock { $0.append(response) }
            }
        try listener.start()
        defer { listener.stop() }

        let observation = ClaudeBrowserObservationEnvelope(
            browserFamily: .safari,
            observation: ClaudeBrowserObservation(
                fiveHour: ClaudeBrowserQuotaWindow(usedPercentage: 25),
                weeklyAllModels: nil,
                observedAt: "2026-08-27T12:00:00Z"
            ),
            requestID: requestID
        )
        let terminal = ClaudeBrowserAutomationEvent(
            requestID: requestID,
            status: .refreshCompleted,
            occurredAt: "2026-08-27T12:00:01Z"
        )
        let responder = ClaudeSafariHostIPCResponder(endpoint: endpoint)
        let response = ClaudeSafariHostIPCResponse(
            requestID: requestID,
            runtimeGenerationID: generation,
            outcome: .completed,
            observation: observation,
            automationEvent: terminal
        )
        try responder.send(response)
        try await values.wait { !$0.isEmpty }
        #expect(values.snapshot == [response])
        #expect(values.snapshot.first?.observation == observation)
        #expect(values.snapshot.first?.automationEvent == terminal)
    }

    @Test
    func completedResponseRejectsNonCompletionOrCrossRequestPayloads() {
        let requestID = "b8340c0a-a046-48a5-8d31-981364652a8b"
        let otherRequestID = "2534cd98-23ef-4d73-8f78-34421c99c950"
        let generation = "b9f8d8f9-c844-4ee0-b1df-aef3e22c884f"
        let observation = ClaudeBrowserObservationEnvelope(
            browserFamily: .safari,
            observation: ClaudeBrowserObservation(
                fiveHour: ClaudeBrowserQuotaWindow(usedPercentage: 25),
                weeklyAllModels: nil,
                observedAt: "2026-08-27T12:00:00Z"
            ),
            requestID: requestID
        )
        let failureEvent = ClaudeBrowserAutomationEvent(
            requestID: requestID,
            status: .usageUnavailable,
            occurredAt: "2026-08-27T12:00:01Z"
        )
        let crossRequestCompletion = ClaudeBrowserAutomationEvent(
            requestID: otherRequestID,
            status: .refreshCompleted,
            occurredAt: "2026-08-27T12:00:01Z"
        )
        #expect(!ClaudeSafariHostIPCResponse(
            requestID: requestID,
            runtimeGenerationID: generation,
            outcome: .completed,
            observation: observation,
            automationEvent: failureEvent
        ).isStructurallyValid)

        let providerFailure = ClaudeSafariHostIPCResponse(
            requestID: requestID,
            runtimeGenerationID: generation,
            outcome: .automation,
            automationEvent: failureEvent,
            providerFailureReason: .targetDataTimeout
        )
        #expect(providerFailure.isStructurallyValid)
        #expect(!ClaudeSafariHostIPCResponse(
            requestID: requestID,
            runtimeGenerationID: generation,
            outcome: .completed,
            observation: observation,
            automationEvent: .init(
                requestID: requestID,
                status: .refreshCompleted,
                occurredAt: "2026-08-27T12:00:01Z"
            ),
            providerFailureReason: .targetDataTimeout
        ).isStructurallyValid)
        #expect(!ClaudeSafariHostIPCResponse(
            requestID: requestID,
            runtimeGenerationID: generation,
            outcome: .automation,
            automationEvent: .init(
                requestID: requestID,
                status: .ownedTabOwnershipLost,
                occurredAt: "2026-08-27T12:00:01Z"
            ),
            providerFailureReason: .targetDataTimeout
        ).isStructurallyValid)
        #expect(!ClaudeSafariHostIPCResponse(
            requestID: requestID,
            runtimeGenerationID: generation,
            outcome: .completed,
            observation: observation,
            automationEvent: crossRequestCompletion
        ).isStructurallyValid)
    }

    @Test
    func responseValidationRejectsCrossRequestObservation() {
        let response = ClaudeSafariHostIPCResponse(
            requestID: "c2ff39c9-e69d-4442-80eb-07369fc3e19c",
            runtimeGenerationID: "4e786d54-0150-4302-89d4-8213112c366e",
            outcome: .observation,
            observation: ClaudeBrowserObservationEnvelope(
                browserFamily: .safari,
                observation: ClaudeBrowserObservation(
                    fiveHour: ClaudeBrowserQuotaWindow(usedPercentage: 50),
                    weeklyAllModels: nil,
                    observedAt: "2026-08-27T12:00:00Z"
                ),
                requestID: "327443e3-53d8-4d95-9151-4f9ad26f7f38"
            )
        )
        #expect(!response.isStructurallyValid)
    }

    @Test
    func hostNativeAndOwnedTabEndpointsAreSeparated() {
        let native = ClaudeBrowserFileHandoffEndpoint.safariHostAppGroup(
            containerDirectoryPath: "/private/tmp/group.test"
        )
        let receipt = ClaudeBrowserFileHandoffEndpoint.safariHostOwnedTab(
            containerDirectoryPath: "/private/tmp/group.test"
        )
        #expect(native.directoryPath == "/private/tmp/group.test/ClaudeSafariHost/NativeInbox")
        #expect(receipt.directoryPath == "/private/tmp/group.test/ClaudeSafariHost/OwnedTab")
        #expect(native != receipt)
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("uma-host-ipc-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    private func awaitRemoval(
        at path: String,
        starting operation: () throws -> Void
    ) async throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let descriptor = Darwin.open(directory, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw ClaudeSafariHostIPCError.ioFailure }

        var continuation: AsyncStream<Void>.Continuation!
        let events = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) {
            continuation = $0
        }
        let changes = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        let deadline = DispatchSource.makeTimerSource(
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        changes.setEventHandler { continuation.yield(()) }
        changes.setCancelHandler { Darwin.close(descriptor) }
        deadline.setEventHandler { continuation.finish() }
        deadline.schedule(deadline: .now() + 5)
        changes.resume()
        deadline.resume()
        defer {
            deadline.cancel()
            changes.cancel()
        }

        try operation()
        continuation.yield(())
        for await _ in events {
            if !FileManager.default.fileExists(atPath: path) { return }
        }
        throw ClaudeSafariHostIPCError.ioFailure
    }
}

private final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    private var observers: [UUID: AsyncStream<Value>.Continuation] = [:]

    init(_ value: Value) { self.value = value }

    var snapshot: Value { lock.withLock { value } }

    func withLock(_ body: (inout Value) -> Void) {
        lock.withLock {
            body(&value)
            for observer in observers.values { observer.yield(value) }
        }
    }

    /// Subscribe and replay atomically, so a callback before or during waiter
    /// setup cannot be lost. AsyncStream terminates when its task is cancelled.
    func wait(until predicate: @Sendable (Value) -> Bool) async throws {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        lock.withLock {
            observers[id] = continuation
            continuation.yield(value)
        }
        defer {
            _ = lock.withLock { observers.removeValue(forKey: id) }
            continuation.finish()
        }
        for await snapshot in stream {
            if predicate(snapshot) { return }
        }
        throw CancellationError()
    }
}
