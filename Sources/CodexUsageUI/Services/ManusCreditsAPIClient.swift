import Foundation

enum ManusCreditsClientFailure: Error, Equatable, Sendable {
    case missingCredential
    case authentication
    case rateLimited
    case network
    case server
    case schema
    case cancelled
    case unsupportedResponse
}

struct ManusCreditsReading: Equatable, Sendable {
    let snapshot: ManusCreditsSnapshot
    let observedAt: Date
}

protocol ManusCreditsReadingClient: Sendable {
    func read(apiKey: String) async -> Result<
        ManusCreditsReading,
        ManusCreditsClientFailure
    >
}

protocol ManusHTTPTransporting: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

final class ManusRedirectRejectingDelegate:
    NSObject, URLSessionTaskDelegate, @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct URLSessionManusTransport: ManusHTTPTransporting {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest =
            ManusCreditsAPIClient.requestTimeout
        configuration.timeoutIntervalForResource =
            ManusCreditsAPIClient.resourceTimeout
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(
            for: request,
            delegate: ManusRedirectRejectingDelegate()
        )
        if response.expectedContentLength
            > Int64(ManusCreditsAPIClient.maximumResponseBytes) {
            throw ManusCreditsClientFailure.unsupportedResponse
        }
        var body = Data()
        body.reserveCapacity(
            min(
                max(0, Int(response.expectedContentLength)),
                ManusCreditsAPIClient.maximumResponseBytes
            )
        )
        for try await byte in bytes {
            guard body.count < ManusCreditsAPIClient.maximumResponseBytes else {
                throw ManusCreditsClientFailure.unsupportedResponse
            }
            body.append(byte)
        }
        return (body, response)
    }
}

struct ManusCreditsAPIClient: ManusCreditsReadingClient {
    static let endpoint = URL(
        string: "https://api.manus.ai/v2/usage.availableCredits"
    )!
    static let authenticationHeader = "x-manus-api-key"
    static let requestTimeout: TimeInterval = 15
    static let resourceTimeout: TimeInterval = 20
    static let maximumResponseBytes = 16 * 1_024

    private let transport: any ManusHTTPTransporting
    private let now: @Sendable () -> Date

    init(
        transport: any ManusHTTPTransporting = URLSessionManusTransport(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.now = now
    }

    func read(apiKey: String) async -> Result<
        ManusCreditsReading,
        ManusCreditsClientFailure
    > {
        let request: URLRequest
        do {
            request = try Self.makeRequest(apiKey: apiKey)
        } catch {
            return .failure(.missingCredential)
        }

        do {
            let (body, response) = try await transport.data(for: request)
            guard body.count <= Self.maximumResponseBytes else {
                return .failure(.unsupportedResponse)
            }
            guard let http = response as? HTTPURLResponse,
                  http.url?.scheme == "https",
                  http.url?.host == "api.manus.ai",
                  http.url?.path == "/v2/usage.availableCredits",
                  http.url?.query == nil else {
                return .failure(.unsupportedResponse)
            }
            switch http.statusCode {
            case 200:
                break
            case 401, 403:
                return .failure(.authentication)
            case 429:
                return .failure(.rateLimited)
            case 500...599:
                return .failure(.server)
            default:
                return .failure(.unsupportedResponse)
            }
            if let contentType = http.value(
                forHTTPHeaderField: "Content-Type"
            )?.lowercased(),
               !contentType.contains("application/json"),
               !contentType.contains("+json") {
                return .failure(.unsupportedResponse)
            }
            if let providerFailure = ManusCreditsDecoder.safeProviderFailure(
                in: body
            ) {
                return .failure(providerFailure)
            }
            do {
                return .success(
                    ManusCreditsReading(
                        snapshot: try ManusCreditsDecoder.decode(body),
                        observedAt: now()
                    )
                )
            } catch {
                return .failure(.schema)
            }
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let error as URLError {
            return error.code == .cancelled
                ? .failure(.cancelled)
                : .failure(.network)
        } catch let error as ManusCreditsClientFailure {
            return .failure(error)
        } catch {
            return .failure(.network)
        }
    }

    static func makeRequest(apiKey: String) throws -> URLRequest {
        guard !apiKey.isEmpty,
              apiKey.utf8.count <= 4_096,
              !apiKey.contains(where: \.isNewline) else {
            throw ManusCreditsClientFailure.missingCredential
        }
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: requestTimeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(apiKey, forHTTPHeaderField: authenticationHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func redactedDiagnostic(for request: URLRequest) -> String {
        let credential = request.value(
            forHTTPHeaderField: authenticationHeader
        ) == nil ? "absent" : "present"
        return "GET https://api.manus.ai/v2/usage.availableCredits "
            + "credential=\(credential)"
    }
}
