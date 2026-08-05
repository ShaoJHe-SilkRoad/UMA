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
        "kind", "schemaVersion", "sourceID", "browserFamily", "routeState", "observation",
    ]
    private static let observationKeys: Set<String> = [
        "fiveHour", "weeklyAllModels", "modelSpecificWeekly", "observedAt", "extractorSchemaVersion",
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
            required: ["observedAt", "extractorSchemaVersion"]
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
              envelope.observation.extractorSchemaVersion == ClaudeBrowserBridgeContract.extractorSchemaVersion
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
    private static let eventKeys: Set<String> = [
        "kind", "schemaVersion", "sourceID", "browserFamily", "requestID", "status", "occurredAt",
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
        if let unexpected = Set(dictionary.keys).subtracting(eventKeys).sorted().first {
            throw ClaudeBrowserBridgeError.unexpectedField(unexpected)
        }
        if let missing = eventKeys.subtracting(Set(dictionary.keys)).sorted().first {
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
