import ClaudeBrowserBridgeProtocol
import Foundation

public enum ClaudeBrowserBridgeError: Error, Equatable, Sendable {
    case messageEmpty
    case messageTooLarge
    case malformedJSON
    case invalidTopLevel
    case unexpectedField(String)
    case missingField(String)
    case invalidContract
    case invalidPercentage
    case invalidReset
    case invalidTimestamp
    case noAccountWindow
    case invalidBrowserOrigin
    case nativeMessagingFrameMalformed
    case socketUnavailable
    case socketUnsafe
    case socketConnectionFailed
    case socketWriteFailed
    case socketReadFailed
}

public enum ClaudeBrowserMessageDecoder {
    private static let envelopeKeys: Set<String> = [
        "kind", "schemaVersion", "sourceID", "browserFamily", "routeState", "requestID", "observationID", "observation",
    ]
    private static let observationKeys: Set<String> = [
        "fiveHour", "weeklyAllModels", "modelSpecificWeekly", "observedAt", "extractorSchemaVersion", "sourceLayoutVersion",
    ]
    private static let windowKeys: Set<String> = ["usedPercentage", "resetAt"]
    private static let modelWindowKeys: Set<String> = ["modelFamily", "window"]

    public static func decode(_ data: Data) throws -> ClaudeBrowserObservationEnvelope {
        guard !data.isEmpty else { throw ClaudeBrowserBridgeError.messageEmpty }
        guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }

        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ClaudeBrowserBridgeError.malformedJSON
        }
        guard let dictionary = raw as? [String: Any] else {
            throw ClaudeBrowserBridgeError.invalidTopLevel
        }
        try requireExactKeys(dictionary, allowed: envelopeKeys, required: envelopeKeys)

        guard let observation = dictionary["observation"] as? [String: Any] else {
            throw ClaudeBrowserBridgeError.invalidTopLevel
        }
        try requireExactKeys(
            observation,
            allowed: observationKeys,
            required: ["observedAt", "extractorSchemaVersion", "sourceLayoutVersion"]
        )
        if let fiveHour = nonNullDictionary(observation["fiveHour"]) {
            try requireExactKeys(fiveHour, allowed: windowKeys, required: ["usedPercentage"])
        }
        if let weekly = nonNullDictionary(observation["weeklyAllModels"]) {
            try requireExactKeys(weekly, allowed: windowKeys, required: ["usedPercentage"])
        }
        if let model = nonNullDictionary(observation["modelSpecificWeekly"]) {
            try requireExactKeys(model, allowed: modelWindowKeys, required: modelWindowKeys)
            guard let window = model["window"] as? [String: Any] else {
                throw ClaudeBrowserBridgeError.invalidTopLevel
            }
            try requireExactKeys(window, allowed: windowKeys, required: ["usedPercentage"])
        }

        let envelope: ClaudeBrowserObservationEnvelope
        do {
            envelope = try JSONDecoder().decode(ClaudeBrowserObservationEnvelope.self, from: data)
        } catch {
            throw ClaudeBrowserBridgeError.malformedJSON
        }
        try validate(envelope)
        return envelope
    }

    public static func encode(_ envelope: ClaudeBrowserObservationEnvelope) throws -> Data {
        try validate(envelope)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }
        return data
    }

    public static func validate(_ envelope: ClaudeBrowserObservationEnvelope) throws {
        guard envelope.kind == ClaudeBrowserBridgeContract.messageKind,
              envelope.schemaVersion == ClaudeBrowserBridgeContract.schemaVersion,
              envelope.sourceID == ClaudeBrowserBridgeContract.sourceID,
              envelope.routeState == .verifiedUsage,
              UUID(uuidString: envelope.requestID) != nil,
              UUID(uuidString: envelope.observationID) != nil,
              envelope.observation.extractorSchemaVersion == ClaudeBrowserBridgeContract.extractorSchemaVersion,
              envelope.observation.sourceLayoutVersion == ClaudeBrowserBridgeContract.sourceLayoutVersion
        else {
            throw ClaudeBrowserBridgeError.invalidContract
        }

        guard envelope.observation.fiveHour != nil || envelope.observation.weeklyAllModels != nil else {
            throw ClaudeBrowserBridgeError.noAccountWindow
        }
        try validate(window: envelope.observation.fiveHour)
        try validate(window: envelope.observation.weeklyAllModels)
        try validate(window: envelope.observation.modelSpecificWeekly?.window)
        guard parseTimestamp(envelope.observation.observedAt) != nil else {
            throw ClaudeBrowserBridgeError.invalidTimestamp
        }
    }

    public static func isAllowedChromiumOrigin(_ origin: String) -> Bool {
        origin == ClaudeBrowserBridgeContract.chromiumExtensionOrigin
    }

    private static func validate(window: ClaudeBrowserQuotaWindow?) throws {
        guard let window else { return }
        guard window.usedPercentage.isFinite,
              (0...100).contains(window.usedPercentage)
        else {
            throw ClaudeBrowserBridgeError.invalidPercentage
        }
        if let reset = window.resetAt {
            guard reset.utf8.count <= 64, parseTimestamp(reset) != nil else {
                throw ClaudeBrowserBridgeError.invalidReset
            }
        }
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        guard value.utf8.count <= 64 else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func nonNullDictionary(_ raw: Any?) -> [String: Any]? {
        guard let raw, !(raw is NSNull) else { return nil }
        return raw as? [String: Any]
    }

    private static func requireExactKeys(
        _ dictionary: [String: Any],
        allowed: Set<String>,
        required: Set<String>
    ) throws {
        if let unexpected = Set(dictionary.keys).subtracting(allowed).sorted().first {
            throw ClaudeBrowserBridgeError.unexpectedField(unexpected)
        }
        if let missing = required.subtracting(Set(dictionary.keys)).sorted().first {
            throw ClaudeBrowserBridgeError.missingField(missing)
        }
    }
}

public enum ClaudeBrowserAutomationEventDecoder {
    private static let baseEventKeys: Set<String> = [
        "kind", "schemaVersion", "sourceID", "browserFamily", "requestID", "status", "occurredAt",
    ]
    private static let handshakeKeys: Set<String> = [
        "companionVersion", "companionBuild", "protocolSchemaVersion",
        "containingApplicationIdentifier", "extensionIdentifier",
        "teamIdentifier", "runtimeGenerationID",
    ]

    public static func decode(_ data: Data) throws -> ClaudeBrowserAutomationEvent {
        guard !data.isEmpty else { throw ClaudeBrowserBridgeError.messageEmpty }
        guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ClaudeBrowserBridgeError.malformedJSON
        }
        guard let dictionary = raw as? [String: Any] else {
            throw ClaudeBrowserBridgeError.invalidTopLevel
        }
        let runtimeIdentityStatuses: Set<String> = [
            ClaudeBrowserAutomationStatus.extensionBackgroundReady.rawValue,
            ClaudeBrowserAutomationStatus.nativeHandlerEntered.rawValue,
            ClaudeBrowserAutomationStatus.nativeRequestDecoded.rawValue,
            ClaudeBrowserAutomationStatus.runtimeGenerationValidated.rawValue,
            ClaudeBrowserAutomationStatus.nativeResponseCreated.rawValue,
            ClaudeBrowserAutomationStatus.nativeResponseSent.rawValue,
            ClaudeBrowserAutomationStatus.extensionResponseReceived.rawValue,
            ClaudeBrowserAutomationStatus.bridgeReady.rawValue,
        ]
        let carriesRuntimeIdentity = (dictionary["status"] as? String)
            .map(runtimeIdentityStatuses.contains) ?? false
        let expectedKeys = carriesRuntimeIdentity
            ? baseEventKeys.union(handshakeKeys)
            : baseEventKeys
        if let unexpected = Set(dictionary.keys).subtracting(expectedKeys).sorted().first {
            throw ClaudeBrowserBridgeError.unexpectedField(unexpected)
        }
        if let missing = expectedKeys.subtracting(Set(dictionary.keys)).sorted().first {
            throw ClaudeBrowserBridgeError.missingField(missing)
        }
        let event: ClaudeBrowserAutomationEvent
        do {
            event = try JSONDecoder().decode(ClaudeBrowserAutomationEvent.self, from: data)
        } catch {
            throw ClaudeBrowserBridgeError.malformedJSON
        }
        try validate(event)
        return event
    }

    public static func encode(_ event: ClaudeBrowserAutomationEvent) throws -> Data {
        try validate(event)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(event)
        guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }
        return data
    }

    public static func validate(_ event: ClaudeBrowserAutomationEvent) throws {
        guard event.kind == ClaudeBrowserBridgeContract.automationMessageKind,
              event.schemaVersion == ClaudeBrowserBridgeContract.schemaVersion,
              event.sourceID == ClaudeBrowserBridgeContract.sourceID,
              event.browserFamily == .safari,
              UUID(uuidString: event.requestID) != nil,
              parseTimestamp(event.occurredAt) != nil
        else {
            throw ClaudeBrowserBridgeError.invalidContract
        }
        let carriesRuntimeIdentity: Bool
        switch event.status {
        case .extensionBackgroundReady, .nativeHandlerEntered,
             .nativeRequestDecoded, .runtimeGenerationValidated,
             .nativeResponseCreated, .nativeResponseSent,
             .extensionResponseReceived, .bridgeReady:
            carriesRuntimeIdentity = true
        default:
            carriesRuntimeIdentity = false
        }
        if carriesRuntimeIdentity {
            guard let companionVersion = event.companionVersion,
                  let companionBuild = event.companionBuild,
                  let containingApplicationIdentifier =
                    event.containingApplicationIdentifier,
                  let extensionIdentifier = event.extensionIdentifier,
                  let teamIdentifier = event.teamIdentifier,
                  let runtimeGenerationID = event.runtimeGenerationID,
                  companionVersion.utf8.count <= 32,
                  !companionVersion.isEmpty,
                  companionBuild.utf8.count <= 32,
                  !companionBuild.isEmpty,
                  companionBuild.allSatisfy(\.isNumber),
                  event.protocolSchemaVersion == ClaudeBrowserBridgeContract.schemaVersion,
                  let runtimeIdentity = ClaudeBrowserRuntimeIdentity.matching(
                    containingApplicationIdentifier: containingApplicationIdentifier
                  ),
                  runtimeIdentity.extensionIdentifier == extensionIdentifier,
                  teamIdentifier == ClaudeBrowserBridgeContract.expectedTeamIdentifier,
                  UUID(uuidString: runtimeGenerationID) != nil
            else { throw ClaudeBrowserBridgeError.invalidContract }
        } else {
            guard event.companionVersion == nil,
                  event.companionBuild == nil,
                  event.protocolSchemaVersion == nil,
                  event.containingApplicationIdentifier == nil,
                  event.extensionIdentifier == nil,
                  event.teamIdentifier == nil,
                  event.runtimeGenerationID == nil
            else { throw ClaudeBrowserBridgeError.invalidContract }
        }
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        guard value.utf8.count <= 64 else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

public enum ClaudeBrowserTerminalPacketDecoder {
    private static let exactKeys: Set<String> = [
        "kind", "schemaVersion", "sourceID", "browserFamily", "requestID",
        "targetRequestID", "runtimeGenerationID", "status", "occurredAt",
        "observation", "providerFailureReason",
    ]
    private static let requiredKeys = exactKeys.subtracting([
        "targetRequestID", "observation", "providerFailureReason",
    ])
    private static let failureStatuses: Set<ClaudeBrowserAutomationStatus> = [
        .permissionRequired, .signInRequired, .routeRejected, .usageUnavailable,
        .tabUnavailable, .ownedTabClosed, .ownedTabOwnershipLost,
    ]

    public static func decode(_ data: Data) throws -> ClaudeBrowserTerminalPacket {
        guard !data.isEmpty else { throw ClaudeBrowserBridgeError.messageEmpty }
        guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let dictionary = raw as? [String: Any],
              Set(dictionary.keys).isSubset(of: exactKeys),
              requiredKeys.isSubset(of: Set(dictionary.keys))
        else { throw ClaudeBrowserBridgeError.invalidContract }
        let packet: ClaudeBrowserTerminalPacket
        do {
            packet = try JSONDecoder().decode(ClaudeBrowserTerminalPacket.self, from: data)
        } catch {
            throw ClaudeBrowserBridgeError.malformedJSON
        }
        try validate(packet)
        return packet
    }

    public static func encode(_ packet: ClaudeBrowserTerminalPacket) throws -> Data {
        try validate(packet)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(packet)
        guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }
        return data
    }

    public static func validate(_ packet: ClaudeBrowserTerminalPacket) throws {
        let standard = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard packet.kind == ClaudeBrowserBridgeContract.terminalMessageKind,
              packet.schemaVersion == ClaudeBrowserBridgeContract.schemaVersion,
              packet.sourceID == ClaudeBrowserBridgeContract.sourceID,
              packet.browserFamily == .safari,
              UUID(uuidString: packet.requestID) != nil,
              UUID(uuidString: packet.runtimeGenerationID) != nil,
              packet.occurredAt.utf8.count <= 64,
              fractional.date(from: packet.occurredAt) != nil
                || standard.date(from: packet.occurredAt) != nil
        else { throw ClaudeBrowserBridgeError.invalidContract }

        if packet.status == .refreshCompleted {
            guard packet.targetRequestID == nil,
                  packet.providerFailureReason == nil,
                  let observation = packet.observation,
                  observation.requestID.lowercased() == packet.requestID
            else { throw ClaudeBrowserBridgeError.invalidContract }
            try ClaudeBrowserMessageDecoder.validate(observation)
            return
        }

        guard failureStatuses.contains(packet.status), packet.observation == nil else {
            throw ClaudeBrowserBridgeError.invalidContract
        }
        if packet.providerFailureReason != nil {
            guard packet.targetRequestID == nil,
                  packet.status == .permissionRequired
                    || packet.status == .signInRequired
                    || packet.status == .routeRejected
                    || packet.status == .usageUnavailable
                    || packet.status == .tabUnavailable
            else { throw ClaudeBrowserBridgeError.invalidContract }
        }
        if let target = packet.targetRequestID {
            guard packet.status == .ownedTabClosed
                    || packet.status == .ownedTabOwnershipLost,
                  UUID(uuidString: target) != nil,
                  target != packet.requestID
            else { throw ClaudeBrowserBridgeError.invalidContract }
        }
    }
}

public enum ClaudeBrowserRuntimeQualificationRequestDecoder {
    private static let exactKeys: Set<String> = [
        "kind", "schemaVersion", "sourceID", "browserFamily", "requestID",
        "runtimeGenerationID",
    ]

    public static func decode(
        _ data: Data
    ) throws -> ClaudeBrowserRuntimeQualificationRequest {
        guard !data.isEmpty else { throw ClaudeBrowserBridgeError.messageEmpty }
        guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { throw ClaudeBrowserBridgeError.malformedJSON }
        guard Set(dictionary.keys) == exactKeys else {
            throw ClaudeBrowserBridgeError.invalidContract
        }
        let request: ClaudeBrowserRuntimeQualificationRequest
        do {
            request = try JSONDecoder().decode(
                ClaudeBrowserRuntimeQualificationRequest.self,
                from: data
            )
        } catch {
            throw ClaudeBrowserBridgeError.malformedJSON
        }
        guard request.kind == ClaudeBrowserBridgeContract.runtimeQualificationMessageKind,
              request.schemaVersion == ClaudeBrowserBridgeContract.schemaVersion,
              request.sourceID == ClaudeBrowserBridgeContract.sourceID,
              request.browserFamily == .safari,
              UUID(uuidString: request.requestID) != nil,
              UUID(uuidString: request.runtimeGenerationID) != nil
        else { throw ClaudeBrowserBridgeError.invalidContract }
        return request
    }

    public static func encode(
        _ request: ClaudeBrowserRuntimeQualificationRequest
    ) throws -> Data {
        guard request.kind == ClaudeBrowserBridgeContract.runtimeQualificationMessageKind,
              request.schemaVersion == ClaudeBrowserBridgeContract.schemaVersion,
              request.sourceID == ClaudeBrowserBridgeContract.sourceID,
              request.browserFamily == .safari,
              UUID(uuidString: request.requestID) != nil,
              UUID(uuidString: request.runtimeGenerationID) != nil
        else { throw ClaudeBrowserBridgeError.invalidContract }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(request)
        guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }
        return data
    }
}

public enum ClaudeBrowserRuntimeQualificationReplyDecoder {
    private static let exactKeys: Set<String> = [
        "kind", "schemaVersion", "sourceID", "browserFamily", "requestID",
        "replyID", "runtimeGenerationID", "companionVersion",
        "companionBuild", "protocolSchemaVersion",
        "containingApplicationIdentifier", "extensionIdentifier",
        "teamIdentifier", "accepted", "reason",
    ]

    public static func decode(
        _ data: Data
    ) throws -> ClaudeBrowserRuntimeQualificationReply {
        let reply: ClaudeBrowserRuntimeQualificationReply = try decodeExact(
            data,
            keys: exactKeys
        )
        try validate(reply)
        return reply
    }

    public static func encode(
        _ reply: ClaudeBrowserRuntimeQualificationReply
    ) throws -> Data {
        try validate(reply)
        return try encodeBounded(reply)
    }

    public static func validate(
        _ reply: ClaudeBrowserRuntimeQualificationReply
    ) throws {
        guard reply.kind == ClaudeBrowserBridgeContract.runtimeQualificationReplyKind,
              reply.schemaVersion == ClaudeBrowserBridgeContract.schemaVersion,
              reply.sourceID == ClaudeBrowserBridgeContract.sourceID,
              reply.browserFamily == .safari,
              UUID(uuidString: reply.requestID) != nil,
              UUID(uuidString: reply.replyID) != nil,
              UUID(uuidString: reply.runtimeGenerationID) != nil,
              reply.companionVersion.utf8.count <= 32,
              !reply.companionVersion.isEmpty,
              reply.companionBuild.utf8.count <= 32,
              !reply.companionBuild.isEmpty,
              reply.companionBuild.allSatisfy(\.isNumber),
              reply.protocolSchemaVersion == ClaudeBrowserBridgeContract.schemaVersion,
              let identity = ClaudeBrowserRuntimeIdentity.matching(
                containingApplicationIdentifier: reply.containingApplicationIdentifier
              ),
              identity.extensionIdentifier == reply.extensionIdentifier,
              reply.teamIdentifier == ClaudeBrowserBridgeContract.expectedTeamIdentifier,
              reply.accepted == (reply.reason == .accepted)
        else { throw ClaudeBrowserBridgeError.invalidContract }
    }
}

public enum ClaudeBrowserRuntimeQualificationAcknowledgementDecoder {
    private static let exactKeys: Set<String> = [
        "kind", "schemaVersion", "sourceID", "browserFamily", "requestID",
        "replyID", "runtimeGenerationID", "accepted",
    ]

    public static func decode(
        _ data: Data
    ) throws -> ClaudeBrowserRuntimeQualificationAcknowledgement {
        let acknowledgement: ClaudeBrowserRuntimeQualificationAcknowledgement = try decodeExact(
            data,
            keys: exactKeys
        )
        try validate(acknowledgement)
        return acknowledgement
    }

    public static func encode(
        _ acknowledgement: ClaudeBrowserRuntimeQualificationAcknowledgement
    ) throws -> Data {
        try validate(acknowledgement)
        return try encodeBounded(acknowledgement)
    }

    public static func validate(
        _ acknowledgement: ClaudeBrowserRuntimeQualificationAcknowledgement
    ) throws {
        guard acknowledgement.kind
                == ClaudeBrowserBridgeContract.runtimeQualificationAcknowledgementKind,
              acknowledgement.schemaVersion == ClaudeBrowserBridgeContract.schemaVersion,
              acknowledgement.sourceID == ClaudeBrowserBridgeContract.sourceID,
              acknowledgement.browserFamily == .safari,
              UUID(uuidString: acknowledgement.requestID) != nil,
              UUID(uuidString: acknowledgement.replyID) != nil,
              UUID(uuidString: acknowledgement.runtimeGenerationID) != nil,
              acknowledgement.accepted
        else { throw ClaudeBrowserBridgeError.invalidContract }
    }
}

private func decodeExact<Value: Decodable>(
    _ data: Data,
    keys: Set<String>
) throws -> Value {
    guard !data.isEmpty else { throw ClaudeBrowserBridgeError.messageEmpty }
    guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
        throw ClaudeBrowserBridgeError.messageTooLarge
    }
    guard let object = try? JSONSerialization.jsonObject(with: data),
          let dictionary = object as? [String: Any]
    else { throw ClaudeBrowserBridgeError.malformedJSON }
    guard Set(dictionary.keys) == keys else {
        throw ClaudeBrowserBridgeError.invalidContract
    }
    do {
        return try JSONDecoder().decode(Value.self, from: data)
    } catch {
        throw ClaudeBrowserBridgeError.malformedJSON
    }
}

private func encodeBounded<Value: Encodable>(_ value: Value) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    guard data.count <= ClaudeBrowserBridgeContract.maximumMessageBytes else {
        throw ClaudeBrowserBridgeError.messageTooLarge
    }
    return data
}
