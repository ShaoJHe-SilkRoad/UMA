import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import Testing

@Suite("Claude Browser two-phase runtime qualification")
struct ClaudeBrowserRuntimeQualificationContractTests {
    private let requestID = "6e6f5e38-70bf-4b1b-81b0-e0903081f980"
    private let replyID = "66b98d30-7ed7-4994-83ee-b388c081bd72"
    private let runtimeGenerationID = "3c4f3c8a-6352-4bc7-b982-c5e8662da078"

    @Test("request binds the native transaction to the installed runtime generation")
    func requestRoundTrip() throws {
        let request = ClaudeBrowserRuntimeQualificationRequest(
            requestID: requestID,
            runtimeGenerationID: runtimeGenerationID
        )

        let data = try ClaudeBrowserRuntimeQualificationRequestDecoder.encode(request)
        #expect(try ClaudeBrowserRuntimeQualificationRequestDecoder.decode(data) == request)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "browserFamily", "kind", "requestID", "runtimeGenerationID",
            "schemaVersion", "sourceID",
        ])
    }

    @Test("accepted native reply is exact, content-free, and correlated")
    func acceptedReplyRoundTrip() throws {
        let reply = acceptedReply()
        let data = try ClaudeBrowserRuntimeQualificationReplyDecoder.encode(reply)

        #expect(try ClaudeBrowserRuntimeQualificationReplyDecoder.decode(data) == reply)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "accepted", "browserFamily", "companionBuild", "companionVersion",
            "containingApplicationIdentifier", "extensionIdentifier", "kind",
            "protocolSchemaVersion", "reason", "replyID", "requestID",
            "runtimeGenerationID", "schemaVersion", "sourceID", "teamIdentifier",
        ])
        for forbidden in [
            "url", "dom", "html", "quota", "account", "identity", "cookie",
            "token", "credential", "page", "tabID",
        ] {
            #expect(object[forbidden] == nil)
        }
    }

    @Test("generation mismatch is explicit and cannot masquerade as acceptance")
    func generationMismatchReply() throws {
        let reply = ClaudeBrowserRuntimeQualificationReply(
            requestID: requestID,
            replyID: replyID,
            runtimeGenerationID: runtimeGenerationID,
            companionVersion: "1.4.0",
            companionBuild: "10",
            containingApplicationIdentifier: "com.silkrd.uma.test",
            extensionIdentifier: "com.silkrd.uma.test.ClaudeBrowserCompanion",
            teamIdentifier: "C6TUZVJ6SJ",
            accepted: false,
            reason: .runtimeGenerationMismatch
        )

        let data = try ClaudeBrowserRuntimeQualificationReplyDecoder.encode(reply)
        #expect(try ClaudeBrowserRuntimeQualificationReplyDecoder.decode(data) == reply)
    }

    @Test("reply accepted flag and reason must agree")
    func inconsistentReplyIsRejected() throws {
        let reply = ClaudeBrowserRuntimeQualificationReply(
            requestID: requestID,
            replyID: replyID,
            runtimeGenerationID: runtimeGenerationID,
            companionVersion: "1.4.0",
            companionBuild: "10",
            containingApplicationIdentifier: "com.silkrd.uma.test",
            extensionIdentifier: "com.silkrd.uma.test.ClaudeBrowserCompanion",
            teamIdentifier: "C6TUZVJ6SJ",
            accepted: true,
            reason: .runtimeGenerationMismatch
        )

        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserRuntimeQualificationReplyDecoder.encode(reply)
        }
    }

    @Test("acknowledgement binds request, reply, and runtime generation")
    func acknowledgementRoundTrip() throws {
        let acknowledgement = ClaudeBrowserRuntimeQualificationAcknowledgement(
            requestID: requestID,
            replyID: replyID,
            runtimeGenerationID: runtimeGenerationID
        )

        let data = try ClaudeBrowserRuntimeQualificationAcknowledgementDecoder.encode(
            acknowledgement
        )
        #expect(
            try ClaudeBrowserRuntimeQualificationAcknowledgementDecoder.decode(data)
                == acknowledgement
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(Set(object.keys) == [
            "accepted", "browserFamily", "kind", "replyID", "requestID",
            "runtimeGenerationID", "schemaVersion", "sourceID",
        ])
    }

    @Test("negative or extended acknowledgements fail closed")
    func invalidAcknowledgementsAreRejected() throws {
        let negative = ClaudeBrowserRuntimeQualificationAcknowledgement(
            requestID: requestID,
            replyID: replyID,
            runtimeGenerationID: runtimeGenerationID,
            accepted: false
        )
        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserRuntimeQualificationAcknowledgementDecoder.encode(negative)
        }

        let valid = ClaudeBrowserRuntimeQualificationAcknowledgement(
            requestID: requestID,
            replyID: replyID,
            runtimeGenerationID: runtimeGenerationID
        )
        let validData = try ClaudeBrowserRuntimeQualificationAcknowledgementDecoder.encode(valid)
        var object = try #require(
            JSONSerialization.jsonObject(with: validData) as? [String: Any]
        )
        object["page"] = "forbidden"
        let extended = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ClaudeBrowserBridgeError.invalidContract) {
            try ClaudeBrowserRuntimeQualificationAcknowledgementDecoder.decode(extended)
        }
    }

    @Test("native handler publishes bridgeReady only after exact acknowledgement")
    func handlerOrderingContract() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift"
            ),
            encoding: .utf8
        )
        let requestBranch = try #require(source.range(
            of: "ClaudeBrowserRuntimeQualificationRequestDecoder.decode(data)"
        ))
        let acknowledgementBranch = try #require(source.range(
            of: "ClaudeBrowserRuntimeQualificationAcknowledgementDecoder.decode(data)"
        ))
        let bridgePublication = try #require(source.range(
            of: "ClaudeBrowserFileHandoffWriter.write(\n                    eventData"
        ))

        #expect(requestBranch.lowerBound < acknowledgementBranch.lowerBound)
        #expect(acknowledgementBranch.lowerBound < bridgePublication.lowerBound)
        #expect(source.contains("pendingQualifications.removeValue("))
        #expect(source.contains("acknowledgement.replyID"))
        #expect(source.contains("acknowledgement.runtimeGenerationID"))
        #expect(source.contains("stage=runtimeIdentityValidated"))
        #expect(source.contains("reason=signedMetadataMismatch"))
        #expect(!source.contains("Bundle(url: containingAppURL)"))
        #expect(source.contains(
            "the containing app supplies its signed generation in the request"
        ))
        #expect(source.contains("stage=nativeRequestDecoded reached=false"))
    }

    @Test("native qualification stages are independently published in causal order")
    func nativeQualificationDiagnosticOrderingContract() throws {
        let handler = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "BrowserExtension/Safari/Native/SafariWebExtensionHandler.swift"
            ),
            encoding: .utf8
        )
        let background = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )

        let orderedHandlerStages = try [
            "status: .nativeHandlerEntered",
            "status: .nativeRequestDecoded",
            "status: .runtimeGenerationValidated",
            "status: .nativeResponseCreated",
            "status: .nativeResponseSent",
        ].map { token in
            try #require(handler.range(of: token)).lowerBound
        }
        #expect(zip(orderedHandlerStages, orderedHandlerStages.dropFirst()).allSatisfy {
            $0.0 < $0.1
        })

        let responseReceived = try #require(background.range(
            of: "requestID, \"extensionResponseReceived\""
        ))
        let acknowledgement = try #require(background.range(
            of: "const acknowledgement = await sendNativeReply("
        ))
        #expect(responseReceived.lowerBound < acknowledgement.lowerBound)
    }

    @Test("machine diagnostic preserves the legacy verifier and reports causal boundaries")
    func machineDiagnosticContract() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/CodexUsageUI/Connectors/ClaudeBrowserProductionIntegration.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("--verify-claude-companion-handshake"))
        #expect(source.contains("--diagnose-claude-companion-pipeline"))
        #expect(source.contains("case containingAppCallbackReceived"))
        #expect(source.contains("case callbackValidated"))
        #expect(source.contains("case companionVerified"))
        #expect(source.contains("case extensionBackgroundNotAcknowledged"))
        #expect(!source.contains("nativeHostAvailable: false,\n                reason: .extensionBackgroundNotAcknowledged"))
    }

    private func acceptedReply() -> ClaudeBrowserRuntimeQualificationReply {
        ClaudeBrowserRuntimeQualificationReply(
            requestID: requestID,
            replyID: replyID,
            runtimeGenerationID: runtimeGenerationID,
            companionVersion: "1.4.0",
            companionBuild: "10",
            containingApplicationIdentifier: "com.silkrd.uma.test",
            extensionIdentifier: "com.silkrd.uma.test.ClaudeBrowserCompanion",
            teamIdentifier: "C6TUZVJ6SJ",
            accepted: true,
            reason: .accepted
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
