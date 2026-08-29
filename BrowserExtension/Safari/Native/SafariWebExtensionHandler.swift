import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation
import OSLog
import SafariServices

/// Native-message handler for the bundled Safari Web Extension. Safari owns
/// the authenticated page; this extension receives only the already-normalized
/// allowlisted observation object.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private struct PendingQualification {
        let requestID: String
        let replyID: String
        let runtimeGenerationID: String
        let createdAt: Date
    }

    private static let qualificationLock = NSLock()
    private static var pendingQualifications: [String: PendingQualification] = [:]
    private static let qualificationLifetime: TimeInterval = 30
    private static let maximumPendingQualifications = 8

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier
            ?? ClaudeBrowserBridgeContract.safariExtensionIdentifier,
        category: "NativeBridge"
    )

    func beginRequest(with context: NSExtensionContext) {
        logger.notice("Claude companion diagnostic stage=handlerEntered reached=true")
        let replyItem = NSExtensionItem()
        replyItem.userInfo = [SFExtensionMessageKey: ["ok": false]]
        var completed = false
        defer {
            if !completed { context.completeRequest(returningItems: [replyItem]) }
        }

        guard let input = context.inputItems.first as? NSExtensionItem,
              let object = input.userInfo?[SFExtensionMessageKey],
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        logger.notice("Claude companion diagnostic stage=messageReceived reached=true")

        guard let signedRuntime = Self.signedRuntimeIdentity() else {
            logger.error(
                "Claude companion diagnostic stage=runtimeIdentityValidated reached=false reason=signedMetadataMismatch"
            )
            return
        }
        logger.notice(
            "Claude companion diagnostic stage=runtimeIdentityValidated reached=true generation=\(signedRuntime.runtimeGenerationID, privacy: .public)"
        )
        if let command = Self.ownedTabReceiptCommand(from: object),
           let receiptReply = Self.handleOwnedTabReceiptCommand(
            command,
            runtime: signedRuntime
           ) {
            replyItem.userInfo = [SFExtensionMessageKey: receiptReply]
            return
        }
        if let value = object as? [String: Any],
           value["kind"] as? String
            == ClaudeBrowserBridgeContract.runtimeQualificationMessageKind {
            guard let rawRequestID = value["requestID"] as? String,
                  UUID(uuidString: rawRequestID) != nil,
                  Self.publishDiagnostic(
                    status: .nativeHandlerEntered,
                    requestID: rawRequestID,
                    runtime: signedRuntime
                  )
            else { return }
            let request: ClaudeBrowserRuntimeQualificationRequest
            do {
                request = try ClaudeBrowserRuntimeQualificationRequestDecoder.decode(data)
            } catch let error as ClaudeBrowserBridgeError {
                logger.error(
                    "Claude companion diagnostic stage=nativeRequestDecoded reached=false reason=\(Self.safeCode(for: error), privacy: .public)"
                )
                return
            } catch {
                logger.error(
                    "Claude companion diagnostic stage=nativeRequestDecoded reached=false reason=unknown"
                )
                return
            }
            guard Self.publishDiagnostic(
                status: .nativeRequestDecoded,
                requestID: request.requestID,
                runtime: signedRuntime
            ) else { return }
            guard let reply = Self.qualificationReply(
                request: request,
                runtime: signedRuntime
            ),
                let replyData = try? ClaudeBrowserRuntimeQualificationReplyDecoder.encode(
                    reply
                ),
                let replyObject = try? JSONSerialization.jsonObject(with: replyData)
            else {
                logger.error(
                    "Claude companion diagnostic stage=nativeReplyCreated reached=false reason=invalidContract"
                )
                return
            }
            logger.notice(
                "Claude companion diagnostic stage=nativeRequestDecoded reached=true request=\(request.requestID, privacy: .public) generation=\(request.runtimeGenerationID, privacy: .public)"
            )
            if reply.accepted {
                Self.storePendingQualification(reply)
            }
            guard reply.accepted,
                  Self.publishDiagnostic(
                    status: .runtimeGenerationValidated,
                    requestID: request.requestID,
                    runtime: signedRuntime
                  )
            else { return }
            replyItem.userInfo = [SFExtensionMessageKey: replyObject]
            guard Self.publishDiagnostic(
                status: .nativeResponseCreated,
                requestID: request.requestID,
                runtime: signedRuntime
            ), Self.publishDiagnostic(
                status: .nativeResponseSent,
                requestID: request.requestID,
                runtime: signedRuntime
            ) else { return }
            logger.notice(
                "Claude companion diagnostic stage=runtimeGenerationValidated reached=\(reply.accepted, privacy: .public) request=\(request.requestID, privacy: .public) generation=\(reply.runtimeGenerationID, privacy: .public) reason=\(reply.reason.rawValue, privacy: .public)"
            )
            logger.notice(
                "Claude companion diagnostic stage=nativeReplyCreated reached=true request=\(request.requestID, privacy: .public) reply=\(reply.replyID, privacy: .public)"
            )
            completed = true
            context.completeRequest(returningItems: [replyItem])
            return
        }
        if let acknowledgement = try?
            ClaudeBrowserRuntimeQualificationAcknowledgementDecoder.decode(data),
           Self.consumePendingQualification(
            acknowledgement,
            runtime: signedRuntime
           ),
           let event = Self.bridgeReadyEvent(
            requestID: acknowledgement.requestID,
            runtime: signedRuntime
           ),
           let eventData = try? ClaudeBrowserAutomationEventDecoder.encode(event) {
            do {
                guard let endpoint = Self.nativeHandoffEndpoint(for: signedRuntime) else {
                    throw ClaudeBrowserBridgeError.socketUnavailable
                }
                try ClaudeBrowserFileHandoffWriter.write(
                    eventData,
                    endpoint: endpoint
                )
                replyItem.userInfo = [SFExtensionMessageKey: ["ok": true]]
                logger.notice(
                    "Claude companion diagnostic stage=replyCompleted reached=true request=\(acknowledgement.requestID, privacy: .public) reply=\(acknowledgement.replyID, privacy: .public)"
                )
            } catch let error as ClaudeBrowserBridgeError {
                logger.error(
                    "Claude companion qualification failed: \(Self.safeCode(for: error), privacy: .public)"
                )
            } catch {
                logger.error("Claude companion qualification failed: unknown")
            }
            return
        }

        let isObservation = (try? ClaudeBrowserMessageDecoder.decode(data))?.browserFamily == .safari
        let automationStatus = (try? ClaudeBrowserAutomationEventDecoder.decode(data))?.status
        let isAutomationEvent = automationStatus != nil
        let terminalStatus = (try? ClaudeBrowserTerminalPacketDecoder.decode(data))?.status
        let isTerminalPacket = terminalStatus != nil
        guard isObservation || isAutomationEvent || isTerminalPacket else { return }

        do {
            guard let endpoint = Self.nativeHandoffEndpoint(for: signedRuntime) else {
                throw ClaudeBrowserBridgeError.socketUnavailable
            }
            try ClaudeBrowserFileHandoffWriter.write(
                data,
                endpoint: endpoint
            )
            replyItem.userInfo = [SFExtensionMessageKey: ["ok": true]]
            if let terminalStatus {
                logger.notice(
                    "Forwarded sanitized Claude browser terminal status: \(terminalStatus.rawValue, privacy: .public)"
                )
            } else if let automationStatus {
                logger.notice(
                    "Forwarded sanitized Claude browser automation status: \(automationStatus.rawValue, privacy: .public)"
                )
            } else {
                logger.notice("Forwarded sanitized Claude browser observation")
            }
        } catch let error as ClaudeBrowserBridgeError {
            logger.error("Sanitized Claude usage forwarding failed: \(Self.safeCode(for: error), privacy: .public)")
        } catch {
            logger.error("Sanitized Claude usage forwarding failed: unknown")
        }
    }

    private struct SignedRuntimeIdentity {
        let identity: ClaudeBrowserRuntimeIdentity
        let containingApplicationIdentifier: String
        let extensionIdentifier: String
        let extensionVersion: String
        let extensionBuild: String
        let teamIdentifier: String
        let runtimeGenerationID: String
    }

    private enum OwnedTabReceiptCommand {
        case load(currentGenerationID: String)
        case save(ClaudeBrowserOwnedTabReceipt)
        case bindCandidate(
            requestID: String,
            runtimeGenerationID: String,
            ownershipNonceDigest: String,
            expectedRevision: Int,
            providerCandidateTabID: Int
        )
        case transition(
            requestID: String,
            runtimeGenerationID: String,
            ownershipNonceDigest: String,
            expectedRevision: Int,
            expectedState: ClaudeBrowserOwnedTabReceiptState,
            nextState: ClaudeBrowserOwnedTabReceiptState,
            providerCandidateTabID: Int?,
            providerOwnedTabID: Int?
        )
        case remove(
            requestID: String,
            runtimeGenerationID: String,
            ownershipNonceDigest: String,
            expectedRevision: Int,
            terminalState: ClaudeBrowserOwnedTabReceiptState
        )
    }

    /// Reads only code-signature-covered bundle metadata. No browser, account,
    /// page, credential, or provider state participates in qualification.
    private static func signedRuntimeIdentity() -> SignedRuntimeIdentity? {
        let extensionBundle = Bundle.main
        guard let extensionIdentifier = extensionBundle.bundleIdentifier,
              let identity = ClaudeBrowserRuntimeIdentity.matching(
                extensionIdentifier: extensionIdentifier
              ),
              extensionBundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.runtimeChannelInfoKey
              ) as? String == identity.channel.rawValue,
              let extensionVersion = extensionBundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
              ) as? String,
              let extensionBuild = extensionBundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
              ) as? String,
              extensionBuild.allSatisfy(\.isNumber),
              let declaredContainingIdentifier = extensionBundle.object(
                forInfoDictionaryKey:
                    ClaudeBrowserBridgeContract.containingApplicationInfoKey
              ) as? String,
              let extensionTeamIdentifier = extensionBundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.teamIdentifierInfoKey
              ) as? String,
              extensionTeamIdentifier == ClaudeBrowserBridgeContract.expectedTeamIdentifier,
              let extensionGeneration = extensionBundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.runtimeGenerationInfoKey
              ) as? String,
              UUID(uuidString: extensionGeneration) != nil
        else { return nil }

        // Safari may execute the appex in a sandboxed host whose process can
        // validate its own signed bundle but cannot reliably instantiate the
        // containing application as a Foundation `Bundle`. The package signer
        // writes the complete app/appex ownership tuple into both signed
        // Info.plists. At runtime the handler validates its signed copy here;
        // the containing app supplies its signed generation in the request and
        // rejects the returned tuple independently. Equality of those two
        // signed generations is therefore the cross-bundle ownership proof.
        guard declaredContainingIdentifier
                == identity.containingApplicationIdentifier,
              extensionBundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.extensionIdentifierInfoKey
              ) as? String == extensionIdentifier,
              let appVersion = extensionBundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.appVersionInfoKey
              ) as? String,
              !appVersion.isEmpty,
              let appBuild = extensionBundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.appBuildInfoKey
              ) as? String,
              appBuild.allSatisfy(\.isNumber),
              extensionBundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.extensionVersionInfoKey
              ) as? String == extensionVersion,
              extensionBundle.object(
                forInfoDictionaryKey: ClaudeBrowserBridgeContract.extensionBuildInfoKey
              ) as? String == extensionBuild
        else { return nil }

        return SignedRuntimeIdentity(
            identity: identity,
            containingApplicationIdentifier: identity.containingApplicationIdentifier,
            extensionIdentifier: extensionIdentifier,
            extensionVersion: extensionVersion,
            extensionBuild: extensionBuild,
            teamIdentifier: extensionTeamIdentifier,
            runtimeGenerationID: extensionGeneration.lowercased()
        )
    }

    private static func bridgeReadyEvent(
        requestID: String,
        runtime: SignedRuntimeIdentity
    ) -> ClaudeBrowserAutomationEvent? {
        guard UUID(uuidString: requestID) != nil else { return nil }
        return ClaudeBrowserAutomationEvent(
            requestID: requestID,
            status: .bridgeReady,
            occurredAt: ISO8601DateFormatter().string(from: Date()),
            companionVersion: runtime.extensionVersion,
            companionBuild: runtime.extensionBuild,
            protocolSchemaVersion: ClaudeBrowserBridgeContract.schemaVersion,
            containingApplicationIdentifier: runtime.containingApplicationIdentifier,
            extensionIdentifier: runtime.extensionIdentifier,
            teamIdentifier: runtime.teamIdentifier,
            runtimeGenerationID: runtime.runtimeGenerationID
        )
    }

    private static func publishDiagnostic(
        status: ClaudeBrowserAutomationStatus,
        requestID: String,
        runtime: SignedRuntimeIdentity
    ) -> Bool {
        guard UUID(uuidString: requestID) != nil,
              let endpoint = nativeHandoffEndpoint(for: runtime),
              let data = try? ClaudeBrowserAutomationEventDecoder.encode(
                ClaudeBrowserAutomationEvent(
                    requestID: requestID,
                    status: status,
                    occurredAt: ISO8601DateFormatter().string(from: Date()),
                    companionVersion: runtime.extensionVersion,
                    companionBuild: runtime.extensionBuild,
                    protocolSchemaVersion: ClaudeBrowserBridgeContract.schemaVersion,
                    containingApplicationIdentifier: runtime.containingApplicationIdentifier,
                    extensionIdentifier: runtime.extensionIdentifier,
                    teamIdentifier: runtime.teamIdentifier,
                    runtimeGenerationID: runtime.runtimeGenerationID
                )
              ),
              (try? ClaudeBrowserFileHandoffWriter.write(data, endpoint: endpoint)) != nil
        else { return false }
        return true
    }

    private static func appGroupContainerPath() -> String? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier:
                ClaudeBrowserBridgeContract.safariHostTestAppGroupIdentifier
        )?.path
    }

    private static func nativeHandoffEndpoint(
        for runtime: SignedRuntimeIdentity
    ) -> ClaudeBrowserFileHandoffEndpoint? {
        guard runtime.identity == .testSafariHost else {
            return .runtime(runtime.identity)
        }
        guard let containerPath = appGroupContainerPath() else { return nil }
        return .safariHostAppGroup(containerDirectoryPath: containerPath)
    }

    private static func ownedTabEndpoint(
        for runtime: SignedRuntimeIdentity
    ) -> ClaudeBrowserFileHandoffEndpoint? {
        guard runtime.identity == .testSafariHost else {
            return .runtime(runtime.identity)
        }
        guard let containerPath = appGroupContainerPath() else { return nil }
        return .safariHostOwnedTab(containerDirectoryPath: containerPath)
    }

    private static func qualificationReply(
        request: ClaudeBrowserRuntimeQualificationRequest,
        runtime: SignedRuntimeIdentity
    ) -> ClaudeBrowserRuntimeQualificationReply? {
        guard UUID(uuidString: request.requestID) != nil,
              UUID(uuidString: request.runtimeGenerationID) != nil
        else { return nil }
        let accepted = request.runtimeGenerationID.lowercased()
            == runtime.runtimeGenerationID
        return ClaudeBrowserRuntimeQualificationReply(
            requestID: request.requestID.lowercased(),
            replyID: UUID().uuidString.lowercased(),
            runtimeGenerationID: runtime.runtimeGenerationID,
            companionVersion: runtime.extensionVersion,
            companionBuild: runtime.extensionBuild,
            containingApplicationIdentifier: runtime.containingApplicationIdentifier,
            extensionIdentifier: runtime.extensionIdentifier,
            teamIdentifier: runtime.teamIdentifier,
            accepted: accepted,
            reason: accepted ? .accepted : .runtimeGenerationMismatch
        )
    }

    private static func storePendingQualification(
        _ reply: ClaudeBrowserRuntimeQualificationReply
    ) {
        qualificationLock.withLock {
            purgeExpiredQualifications(now: Date())
            if pendingQualifications.count >= maximumPendingQualifications,
               let oldest = pendingQualifications.values.min(
                by: { $0.createdAt < $1.createdAt }
               ) {
                pendingQualifications.removeValue(forKey: oldest.replyID)
            }
            pendingQualifications[reply.replyID] = PendingQualification(
                requestID: reply.requestID,
                replyID: reply.replyID,
                runtimeGenerationID: reply.runtimeGenerationID,
                createdAt: Date()
            )
        }
    }

    private static func consumePendingQualification(
        _ acknowledgement: ClaudeBrowserRuntimeQualificationAcknowledgement,
        runtime: SignedRuntimeIdentity
    ) -> Bool {
        qualificationLock.withLock {
            purgeExpiredQualifications(now: Date())
            guard let pending = pendingQualifications.removeValue(
                forKey: acknowledgement.replyID
            ),
                pending.requestID == acknowledgement.requestID,
                pending.replyID == acknowledgement.replyID,
                pending.runtimeGenerationID == acknowledgement.runtimeGenerationID,
                acknowledgement.runtimeGenerationID == runtime.runtimeGenerationID
            else { return false }
            return true
        }
    }

    private static func purgeExpiredQualifications(now: Date) {
        pendingQualifications = pendingQualifications.filter {
            now.timeIntervalSince($0.value.createdAt) <= qualificationLifetime
        }
    }

    private static func ownedTabReceiptCommand(from object: Any) -> OwnedTabReceiptCommand? {
        guard let value = object as? [String: Any],
              value["kind"] as? String == "claudeOwnedProviderTabV2ReceiptCommand",
              value["schemaVersion"] as? Int == ClaudeBrowserOwnedTabReceipt.schemaVersion,
              let action = value["action"] as? String
        else { return nil }
        let keys = Set(value.keys)
        switch action {
        case "loadV2":
            guard keys == ["kind", "schemaVersion", "action", "runtimeGenerationID"],
                  let generation = value["runtimeGenerationID"] as? String,
                  UUID(uuidString: generation) != nil
            else { return nil }
            return .load(currentGenerationID: generation.lowercased())
        case "saveV2":
            guard keys == [
                "kind", "schemaVersion", "action", "requestID",
                "runtimeGenerationID", "ownershipNonceDigest", "createdAt",
                "expiresAt", "lifecycleState", "revision",
            ],
                let requestID = value["requestID"] as? String,
                let generation = value["runtimeGenerationID"] as? String,
                let digest = value["ownershipNonceDigest"] as? String,
                let createdAt = value["createdAt"] as? String,
                let expiresAt = value["expiresAt"] as? String,
                let lifecycleRaw = value["lifecycleState"] as? String,
                let lifecycleState = ClaudeBrowserOwnedTabReceiptState(rawValue: lifecycleRaw),
                let revision = value["revision"] as? Int
            else { return nil }
            let receipt = ClaudeBrowserOwnedTabReceipt(
                requestID: requestID,
                runtimeGenerationID: generation.lowercased(),
                ownershipNonceDigest: digest,
                createdAt: createdAt,
                expiresAt: expiresAt,
                lifecycleState: lifecycleState,
                revision: revision
            )
            guard receipt.isStructurallyValid,
                  let date = receipt.creationDate,
                  let expiry = receipt.expiryDate,
                  abs(date.timeIntervalSinceNow) <= 60,
                  expiry.timeIntervalSince(date) <= 10 * 60,
                  expiry.timeIntervalSinceNow > 0
            else { return nil }
            return .save(receipt)
        case "bindCandidateV2":
            guard keys == [
                "kind", "schemaVersion", "action", "requestID",
                "runtimeGenerationID", "ownershipNonceDigest", "expectedRevision",
                "providerCandidateTabID",
            ],
                let requestID = value["requestID"] as? String,
                UUID(uuidString: requestID) != nil,
                let generation = value["runtimeGenerationID"] as? String,
                UUID(uuidString: generation) != nil,
                let digest = value["ownershipNonceDigest"] as? String,
                let expectedRevision = value["expectedRevision"] as? Int,
                expectedRevision > 0,
                let candidateTabID = value["providerCandidateTabID"] as? Int,
                candidateTabID >= 0
            else { return nil }
            return .bindCandidate(
                requestID: requestID.lowercased(),
                runtimeGenerationID: generation.lowercased(),
                ownershipNonceDigest: digest,
                expectedRevision: expectedRevision,
                providerCandidateTabID: candidateTabID
            )
        case "transitionV2":
            let required: Set<String> = [
                "kind", "schemaVersion", "action", "requestID",
                "runtimeGenerationID", "ownershipNonceDigest", "expectedRevision",
                "expectedLifecycleState", "nextLifecycleState",
            ]
            let optional: Set<String> = ["providerCandidateTabID", "providerOwnedTabID"]
            guard keys.isSuperset(of: required),
                keys.isSubset(of: required.union(optional)),
                let requestID = value["requestID"] as? String,
                UUID(uuidString: requestID) != nil,
                let generation = value["runtimeGenerationID"] as? String,
                UUID(uuidString: generation) != nil,
                let digest = value["ownershipNonceDigest"] as? String,
                let expectedRevision = value["expectedRevision"] as? Int,
                expectedRevision > 0,
                let expectedRaw = value["expectedLifecycleState"] as? String,
                let expectedState = ClaudeBrowserOwnedTabReceiptState(rawValue: expectedRaw),
                let nextRaw = value["nextLifecycleState"] as? String,
                let nextState = ClaudeBrowserOwnedTabReceiptState(rawValue: nextRaw),
                validOptionalTabID(value, key: "providerCandidateTabID"),
                validOptionalTabID(value, key: "providerOwnedTabID")
            else { return nil }
            return .transition(
                requestID: requestID.lowercased(),
                runtimeGenerationID: generation.lowercased(),
                ownershipNonceDigest: digest,
                expectedRevision: expectedRevision,
                expectedState: expectedState,
                nextState: nextState,
                providerCandidateTabID: value["providerCandidateTabID"] as? Int,
                providerOwnedTabID: value["providerOwnedTabID"] as? Int
            )
        case "removeV2":
            guard keys == [
                "kind", "schemaVersion", "action", "requestID",
                "runtimeGenerationID", "ownershipNonceDigest", "expectedRevision",
                "terminalLifecycleState",
            ],
                let requestID = value["requestID"] as? String,
                UUID(uuidString: requestID) != nil,
                let generation = value["runtimeGenerationID"] as? String,
                UUID(uuidString: generation) != nil,
                let digest = value["ownershipNonceDigest"] as? String,
                let expectedRevision = value["expectedRevision"] as? Int,
                expectedRevision > 0,
                let terminalRaw = value["terminalLifecycleState"] as? String,
                let terminalState = ClaudeBrowserOwnedTabReceiptState(rawValue: terminalRaw),
                terminalState.isTerminal
            else { return nil }
            return .remove(
                requestID: requestID.lowercased(),
                runtimeGenerationID: generation.lowercased(),
                ownershipNonceDigest: digest,
                expectedRevision: expectedRevision,
                terminalState: terminalState
            )
        default:
            return nil
        }
    }

    private static func validOptionalTabID(
        _ value: [String: Any],
        key: String
    ) -> Bool {
        guard value.keys.contains(key) else { return true }
        guard let tabID = value[key] as? Int else { return false }
        return tabID >= 0
    }

    private static func handleOwnedTabReceiptCommand(
        _ command: OwnedTabReceiptCommand,
        runtime: SignedRuntimeIdentity
    ) -> [String: Any]? {
        guard let endpoint = ownedTabEndpoint(for: runtime) else {
            return ["ok": false]
        }
        do {
            switch command {
            case let .load(currentGenerationID):
                guard currentGenerationID == runtime.runtimeGenerationID else {
                    return ["ok": false]
                }
                guard let receipt = try ClaudeBrowserOwnedTabReceiptStore.load(
                    endpoint: endpoint
                ) else { return ["ok": true, "found": false] }
                return [
                    "ok": true,
                    "found": true,
                    "schemaVersion": receipt.schemaVersion,
                    "requestID": receipt.requestID,
                    "runtimeGenerationID": receipt.runtimeGenerationID,
                    "ownershipNonceDigest": receipt.ownershipNonceDigest,
                    "createdAt": receipt.createdAt,
                    "expiresAt": receipt.expiresAt,
                    "lifecycleState": receipt.lifecycleState.rawValue,
                    "revision": receipt.revision,
                ].merging(
                    receipt.providerCandidateTabID.map {
                        ["providerCandidateTabID": $0]
                    } ?? [:]
                ) { current, _ in current }.merging(
                    receipt.providerOwnedTabID.map { ["providerOwnedTabID": $0] } ?? [:]
                ) { current, _ in current }
            case let .save(receipt):
                guard receipt.runtimeGenerationID == runtime.runtimeGenerationID else {
                    return ["ok": false]
                }
                try ClaudeBrowserOwnedTabReceiptStore.save(receipt, endpoint: endpoint)
                return ["ok": true, "revision": receipt.revision]
            case let .bindCandidate(
                requestID, generation, digest, expectedRevision, candidateTabID
            ):
                guard generation == runtime.runtimeGenerationID,
                      let receipt = try ClaudeBrowserOwnedTabReceiptStore.bindCandidate(
                        requestID: requestID,
                        runtimeGenerationID: generation,
                        ownershipNonceDigest: digest,
                        expectedRevision: expectedRevision,
                        providerCandidateTabID: candidateTabID,
                        endpoint: endpoint
                      )
                else { return ["ok": false] }
                return ["ok": true, "revision": receipt.revision]
            case let .transition(
                requestID, generation, digest, expectedRevision,
                expectedState, nextState, candidateTabID, ownedTabID
            ):
                guard generation == runtime.runtimeGenerationID,
                      let receipt = try ClaudeBrowserOwnedTabReceiptStore.transition(
                        requestID: requestID,
                        runtimeGenerationID: generation,
                        ownershipNonceDigest: digest,
                        expectedRevision: expectedRevision,
                        expectedState: expectedState,
                        nextState: nextState,
                        providerCandidateTabID: candidateTabID,
                        providerOwnedTabID: ownedTabID,
                        endpoint: endpoint
                      )
                else { return ["ok": false] }
                return ["ok": true, "revision": receipt.revision]
            case let .remove(
                requestID, generation, digest, expectedRevision, terminalState
            ):
                guard generation == runtime.runtimeGenerationID else {
                    return ["ok": false]
                }
                return [
                    "ok": try ClaudeBrowserOwnedTabReceiptStore.remove(
                        requestID: requestID,
                        runtimeGenerationID: generation,
                        ownershipNonceDigest: digest,
                        expectedRevision: expectedRevision,
                        terminalState: terminalState,
                        endpoint: endpoint
                    ),
                ]
            }
        } catch {
            return ["ok": false]
        }
    }

    private static func safeCode(for error: ClaudeBrowserBridgeError) -> String {
        switch error {
        case .messageEmpty: "message-empty"
        case .messageTooLarge: "message-too-large"
        case .malformedJSON: "malformed-json"
        case .invalidTopLevel: "invalid-top-level"
        case .unexpectedField: "unexpected-field"
        case .missingField: "missing-field"
        case .invalidContract: "invalid-contract"
        case .invalidPercentage: "invalid-percentage"
        case .invalidReset: "invalid-reset"
        case .invalidTimestamp: "invalid-timestamp"
        case .noAccountWindow: "no-account-window"
        case .invalidBrowserOrigin: "invalid-browser-origin"
        case .nativeMessagingFrameMalformed: "native-frame-malformed"
        case .socketUnavailable: "local-bridge-unavailable"
        case .socketUnsafe: "local-bridge-unsafe"
        case .socketConnectionFailed: "local-bridge-connect-failed"
        case .socketWriteFailed: "local-bridge-write-failed"
        case .socketReadFailed: "local-bridge-read-failed"
        }
    }
}
