import Foundation
import Security
import Testing

@Suite("M4-G1 Manus source admission feasibility")
struct M4G1ManusSourceAdmissionTests {
    @Test
    func exactOfficialRequestIsNarrowAndDiagnosticsAreRedacted() throws {
        let request = try ManusAdmissionHarness.makeRequest(
            apiKey: "test-only-placeholder"
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "api.manus.ai")
        #expect(request.url?.path == "/v2/usage.availableCredits")
        #expect(request.url?.query == nil)
        #expect(request.httpBody == nil)
        #expect(request.timeoutInterval == 15)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(
            request.value(forHTTPHeaderField: "x-manus-api-key")
                == "test-only-placeholder"
        )

        let diagnostic = ManusAdmissionHarness.redactedDiagnostic(for: request)
        #expect(diagnostic == "GET https://api.manus.ai/v2/usage.availableCredits credential=present")
        #expect(!diagnostic.contains("test-only-placeholder"))
    }

    @Test
    func totalCreditsIsAuthoritativeAndComponentsNeedNotReconcile() throws {
        let snapshot = try ManusAdmissionHarness.decode(
            Data(
                """
                {
                  "ok": true,
                  "request_id": "safe-test-id",
                  "data": {
                    "total_credits": 42,
                    "free_credits": 1000,
                    "periodic_credits": 2000,
                    "addon_credits": 3000,
                    "pro_monthly_credits": 4000,
                    "event_credits": 5000,
                    "refresh_credits": 6000,
                    "max_refresh_credits": 7000,
                    "next_refresh_time": 1893456000,
                    "refresh_interval": "weekly"
                  }
                }
                """.utf8
            )
        )

        #expect(snapshot.totalCredits == 42)
        #expect(snapshot.freeCredits == 1000)
        #expect(snapshot.proMonthlyCredits == 4000)
        #expect(snapshot.maxRefreshCredits == 7000)
        #expect(snapshot.refreshInterval == .weekly)
    }

    @Test
    func minimalDocumentedSuccessIsAccepted() throws {
        let snapshot = try ManusAdmissionHarness.decode(
            Data(
                """
                {
                  "ok": true,
                  "request_id": "safe-test-id",
                  "data": {"total_credits": 0}
                }
                """.utf8
            )
        )

        #expect(snapshot.totalCredits == 0)
        #expect(snapshot.freeCredits == nil)
        #expect(snapshot.refreshInterval == nil)
    }

    @Test(
        "Malformed, missing-primary, negative, and overflowing responses fail closed",
        arguments: [
            #"{"ok":true,"request_id":"x","data":{}}"#,
            #"{"ok":true,"request_id":"x","data":{"total_credits":-1}}"#,
            #"{"ok":true,"request_id":"x","data":{"total_credits":2147483648}}"#,
            #"{"ok":true,"request_id":"x","data":{"total_credits":1.5}}"#,
            #"{"ok":true,"request_id":"x","data":{"total_credits":"1"}}"#,
            #"{"ok":true,"request_id":"x","data":{"total_credits":1,"free_credits":-1}}"#,
            #"{"ok":true,"request_id":"x","data":{"total_credits":1,"refresh_interval":"monthly"}}"#,
            #"{"ok":false,"request_id":"x","error":{"code":"permission_denied","message":"redacted"}}"#,
            #"not-json"#
        ]
    )
    func invalidResponsesFailClosed(payload: String) {
        #expect(throws: Error.self) {
            _ = try ManusAdmissionHarness.decode(Data(payload.utf8))
        }
    }

    @Test
    func unknownFieldsCannotEnterTheAcceptedSnapshot() throws {
        let snapshot = try ManusAdmissionHarness.decode(
            Data(
                """
                {
                  "ok": true,
                  "request_id": "safe-test-id",
                  "account_identity": "must-not-enter-model",
                  "data": {
                    "total_credits": 17,
                    "task_history": ["must-not-enter-model"]
                  }
                }
                """.utf8
            )
        )

        #expect(snapshot.totalCredits == 17)
        #expect(Mirror(reflecting: snapshot).children.count == 10)
    }

    @Test
    func transportAndCadencePolicyIsFailClosed() {
        #expect(ManusAdmissionHarness.maximumResponseBytes == 16 * 1024)
        #expect(ManusAdmissionHarness.requestTimeout == 15)
        #expect(ManusAdmissionHarness.resourceTimeout == 20)
        #expect(ManusAdmissionHarness.minimumCadenceAfterCompletion == 60)
        #expect(ManusAdmissionHarness.maximumInFlightReads == 1)
        #expect(ManusAdmissionHarness.followsRedirects == false)
        #expect(ManusAdmissionHarness.acceptsCookies == false)
        #expect(ManusAdmissionHarness.persistsResponses == false)
    }

    @Test
    func oversizedBodiesFailBeforeDecode() {
        let body = Data(
            repeating: 0x20,
            count: ManusAdmissionHarness.maximumResponseBytes + 1
        )
        #expect(throws: Error.self) {
            _ = try ManusAdmissionHarness.decode(body)
        }
    }

    @Test
    func providerErrorsCollapseToSafeBoundedCategories() throws {
        let auth = try ManusAdmissionHarness.decodeSafeError(
            Data(
                """
                {
                  "ok": false,
                  "request_id": "must-not-be-retained",
                  "error": {
                    "code": "permission_denied",
                    "message": "must-not-be-retained"
                  }
                }
                """.utf8
            )
        )
        let rateLimit = try ManusAdmissionHarness.decodeSafeError(
            Data(
                """
                {
                  "ok": false,
                  "request_id": "must-not-be-retained",
                  "error": {
                    "code": "rate_limited",
                    "message": "must-not-be-retained"
                  }
                }
                """.utf8
            )
        )
        let unknown = try ManusAdmissionHarness.decodeSafeError(
            Data(
                """
                {
                  "ok": false,
                  "request_id": "must-not-be-retained",
                  "error": {
                    "code": "future_provider_code",
                    "message": "must-not-be-retained"
                  }
                }
                """.utf8
            )
        )

        #expect(auth == .authorizationRequired)
        #expect(rateLimit == .rateLimited)
        #expect(unknown == .providerFailure)
    }

    @Test
    func resetTimestampIsUnixSecondsOrDocumentedZeroNeverMilliseconds() throws {
        let scheduled = try ManusAdmissionHarness.decode(
            Data(
                """
                {
                  "ok": true,
                  "request_id": "safe-test-id",
                  "data": {
                    "total_credits": 1,
                    "next_refresh_time": 1893456000
                  }
                }
                """.utf8
            )
        )
        let noSchedule = try ManusAdmissionHarness.decode(
            Data(
                """
                {
                  "ok": true,
                  "request_id": "safe-test-id",
                  "data": {
                    "total_credits": 1,
                    "next_refresh_time": 0
                  }
                }
                """.utf8
            )
        )

        #expect(scheduled.nextRefreshTime == 1_893_456_000)
        #expect(noSchedule.nextRefreshTime == 0)
        #expect(throws: Error.self) {
            _ = try ManusAdmissionHarness.decode(
                Data(
                    """
                    {
                      "ok": true,
                      "request_id": "safe-test-id",
                      "data": {
                        "total_credits": 1,
                        "next_refresh_time": 1893456000000
                      }
                    }
                    """.utf8
                )
            )
        }
    }

    @Test
    func keychainContractIsDeviceBoundAndDoesNotReadASecret() {
        let query = ManusAdmissionHarness.keychainItemContract

        #expect(
            query[kSecClass as String] as? String
                == kSecClassGenericPassword as String
        )
        #expect(
            query[kSecAttrService as String] as? String
                == "com.kevinchen.CodexUsageMonitor.manus-api-v2"
        )
        #expect(query[kSecAttrAccount as String] as? String == "primary")
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(
            query[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecAttrAccessGroup as String] == nil)
        #expect(query[kSecValueData as String] == nil)
        #expect(query[kSecReturnData as String] == nil)
    }
}

private enum ManusAdmissionHarness {
    static let endpoint = URL(
        string: "https://api.manus.ai/v2/usage.availableCredits"
    )!
    static let maximumResponseBytes = 16 * 1024
    static let requestTimeout: TimeInterval = 15
    static let resourceTimeout: TimeInterval = 20
    static let minimumCadenceAfterCompletion: TimeInterval = 60
    static let maximumInFlightReads = 1
    static let followsRedirects = false
    static let acceptsCookies = false
    static let persistsResponses = false

    static var keychainItemContract: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String:
                "com.kevinchen.CodexUsageMonitor.manus-api-v2",
            kSecAttrAccount as String: "primary",
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
    }

    static func makeRequest(apiKey: String) throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw ManusAdmissionError.missingCredential
        }
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: requestTimeout
        )
        request.httpMethod = "GET"
        request.setValue(
            apiKey,
            forHTTPHeaderField: "x-manus-api-key"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func redactedDiagnostic(for request: URLRequest) -> String {
        let credentialState =
            request.value(forHTTPHeaderField: "x-manus-api-key") == nil
            ? "absent"
            : "present"
        return "\(request.httpMethod ?? "UNKNOWN") \(request.url?.absoluteString ?? "invalid-url") credential=\(credentialState)"
    }

    static func decode(_ body: Data) throws -> ManusAcceptedSnapshot {
        guard body.count <= maximumResponseBytes else {
            throw ManusAdmissionError.responseTooLarge
        }
        let envelope = try JSONDecoder().decode(
            ManusSuccessEnvelope.self,
            from: body
        )
        guard envelope.ok else {
            throw ManusAdmissionError.unsuccessfulEnvelope
        }
        try envelope.data.validate()
        return envelope.data
    }

    static func decodeSafeError(_ body: Data) throws -> ManusSafeError {
        guard body.count <= maximumResponseBytes else {
            throw ManusAdmissionError.responseTooLarge
        }
        let envelope = try JSONDecoder().decode(
            ManusErrorEnvelope.self,
            from: body
        )
        guard !envelope.ok else {
            throw ManusAdmissionError.unsuccessfulEnvelope
        }
        switch envelope.error.code {
        case "permission_denied":
            return .authorizationRequired
        case "rate_limited":
            return .rateLimited
        default:
            return .providerFailure
        }
    }
}

private enum ManusAdmissionError: Error {
    case missingCredential
    case responseTooLarge
    case unsuccessfulEnvelope
    case negativeCredit
    case invalidRefreshInterval
}

private enum ManusRefreshInterval: String, Decodable {
    case daily
    case weekly
    case none = ""
}

private enum ManusSafeError: Equatable {
    case authorizationRequired
    case rateLimited
    case providerFailure
}

private struct ManusErrorEnvelope: Decodable {
    let ok: Bool
    let requestID: String
    let error: ManusErrorPayload

    enum CodingKeys: String, CodingKey {
        case ok
        case requestID = "request_id"
        case error
    }
}

private struct ManusErrorPayload: Decodable {
    let code: String
    let message: String
}

private struct ManusSuccessEnvelope: Decodable {
    let ok: Bool
    let requestID: String
    let data: ManusAcceptedSnapshot

    enum CodingKeys: String, CodingKey {
        case ok
        case requestID = "request_id"
        case data
    }
}

private struct ManusAcceptedSnapshot: Decodable {
    let totalCredits: Int32
    let freeCredits: Int32?
    let periodicCredits: Int32?
    let addonCredits: Int32?
    let proMonthlyCredits: Int32?
    let eventCredits: Int32?
    let refreshCredits: Int32?
    let maxRefreshCredits: Int32?
    let nextRefreshTime: Int64?
    let refreshInterval: ManusRefreshInterval?

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case freeCredits = "free_credits"
        case periodicCredits = "periodic_credits"
        case addonCredits = "addon_credits"
        case proMonthlyCredits = "pro_monthly_credits"
        case eventCredits = "event_credits"
        case refreshCredits = "refresh_credits"
        case maxRefreshCredits = "max_refresh_credits"
        case nextRefreshTime = "next_refresh_time"
        case refreshInterval = "refresh_interval"
    }

    func validate() throws {
        let creditValues = [
            totalCredits,
            freeCredits,
            periodicCredits,
            addonCredits,
            proMonthlyCredits,
            eventCredits,
            refreshCredits,
            maxRefreshCredits
        ].compactMap { $0 }
        guard creditValues.allSatisfy({ $0 >= 0 }) else {
            throw ManusAdmissionError.negativeCredit
        }
        if let nextRefreshTime {
            let plausibleUnixSeconds: ClosedRange<Int64> =
                1_577_836_800...4_102_444_800
            guard nextRefreshTime == 0
                    || plausibleUnixSeconds.contains(nextRefreshTime) else {
                throw ManusAdmissionError.invalidRefreshInterval
            }
        }
    }
}
