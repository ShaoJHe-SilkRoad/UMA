@preconcurrency import Foundation

/// Injectable stdio boundary.  Tests supply a deterministic fake transport;
/// the production transport only starts the local executable and never reads
/// authentication material or exposes stderr.
protocol CodexAppServerTransport: AnyObject, Sendable {
    /// True while this transport still owns a usable local child process.
    /// Fixture transports default to true so older protocol tests retain their
    /// deterministic behavior without modelling an OS process.
    var isRunning: Bool { get }
    var needsInitialization: Bool { get }
    func markInitialized()
    func start(executableURL: URL) throws
    func write(_ data: Data) throws
    /// Legacy fixture seam retained for frozen M1 test doubles.
    func readLine() async throws -> Data?
    /// Returns one decoded JSON-RPC message body.  The production transport
    /// owns the app-server's JSON-line framing; fixture transports can
    /// provide the same body directly without simulating a pipe.
    func readMessage() async throws -> Data?
    func stop()
}

extension CodexAppServerTransport {
    var isRunning: Bool { true }
    var needsInitialization: Bool { false }
    func markInitialized() {}
    func readMessage() async throws -> Data? { try await readLine() }
}

private enum CodexAppServerTransportError: Error {
    case notRunning
    case launchFailed
}

/// A schema-defined provider invalidation.  The session intentionally exposes
/// no notification payload: callers need only know which account-scoped read
/// should be coalesced by their refresh coordinator.
enum CodexAppServerEvent: Sendable, Equatable {
    case accountUpdated
    case rateLimitsUpdated
}

/// The retained local app-server receives only the stable GUI environment it
/// needs to locate the current user's managed Codex state.  In particular, a
/// shell `PATH`, `CODEX_HOME`, and caller working directory cannot alter
/// resolver or child-process behavior.
struct CodexAppServerProcessLaunchConfiguration: Sendable, Equatable {
    let environment: [String: String]
    let currentDirectoryURL: URL

    static func production() -> Self {
        Self(homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    init(homeDirectory: String) {
        environment = [
            "HOME": homeDirectory,
            "LANG": "en_US_POSIX"
        ]
        currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
    }
}

final class ProcessCodexAppServerTransport: CodexAppServerTransport, @unchecked Sendable {
    private let launchConfiguration: CodexAppServerProcessLaunchConfiguration
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var retainedExecutableURL: URL?
    private var retainsOwnedProcess = false
    private var restartedProcessNeedsInitialization = false
    private var lastLaunchAt = Date.distantPast

    init(launchConfiguration: CodexAppServerProcessLaunchConfiguration = .production()) {
        self.launchConfiguration = launchConfiguration
    }

    func start(executableURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        if process?.isRunning == true { return }
        closeHandlesLocked()
        process = nil
        retainedExecutableURL = executableURL
        retainsOwnedProcess = true
        try launchLocked(executableURL: executableURL)
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    var needsInitialization: Bool {
        lock.lock()
        defer { lock.unlock() }
        return restartedProcessNeedsInitialization
    }

    func markInitialized() {
        lock.lock()
        restartedProcessNeedsInitialization = false
        lock.unlock()
    }

    private func launchLocked(executableURL: URL) throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.environment = launchConfiguration.environment
        process.currentDirectoryURL = launchConfiguration.currentDirectoryURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        // Stderr can contain local implementation detail.  The monitor only
        // needs its safe failure vocabulary, so deliberately discard it.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CodexAppServerTransportError.launchFailed
        }

        process.terminationHandler = { [weak self, weak process] _ in
            guard let process else { return }
            self?.restartAfterUnexpectedExit(of: process)
        }
        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        lastLaunchAt = Date()
    }

    func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let process, process.isRunning, let input else {
            throw CodexAppServerTransportError.notRunning
        }
        input.write(JSONLineJSONRPCFraming.encode(data))
    }

    func readMessage() async throws -> Data? {
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return nil }
            return self.readMessageSynchronously()
        }.value
    }

    func readLine() async throws -> Data? {
        try await readMessage()
    }

    func stop() {
        lock.lock()
        retainsOwnedProcess = false
        retainedExecutableURL = nil
        restartedProcessNeedsInitialization = false
        let input = self.input
        let output = self.output
        let process = self.process
        self.input = nil
        self.output = nil
        self.process = nil
        lock.unlock()

        try? input?.close()
        if process?.isRunning == true {
            process?.terminate()
        }
        // Closing stdout unblocks any pending bounded read task.  We never
        // wait indefinitely for a child process during shutdown.
        try? output?.close()
    }

    private func restartAfterUnexpectedExit(of terminatedProcess: Process) {
        lock.lock()
        defer { lock.unlock() }
        guard retainsOwnedProcess,
              process === terminatedProcess,
              let retainedExecutableURL,
              Date().timeIntervalSince(lastLaunchAt) >= 1
        else { return }
        closeHandlesLocked()
        process = nil
        do {
            try launchLocked(executableURL: retainedExecutableURL)
            restartedProcessNeedsInitialization = true
        } catch {
            restartedProcessNeedsInitialization = false
        }
    }

    private func closeHandlesLocked() {
        let input = self.input
        let output = self.output
        self.input = nil
        self.output = nil
        try? input?.close()
        try? output?.close()
    }

    private func readMessageSynchronously() -> Data? {
        lock.lock()
        let output = self.output
        lock.unlock()
        guard let output else { return nil }
        return JSONLineJSONRPCFraming.readMessage(from: output)
    }
}

/// The installed Codex app-server exchanges one JSON-RPC message per newline.
/// Keeping the framing code here avoids ever retaining a raw transcript:
/// callers receive exactly one bounded JSON-RPC body for immediate decode.
enum JSONLineJSONRPCFraming {
    static let maximumMessageBytes = 2 * 1_024 * 1_024

    static func encode(_ body: Data) -> Data {
        var framed = body
        framed.append(0x0A)
        return framed
    }

    static func readMessage(from handle: FileHandle) -> Data? {
        var message = Data()
        while message.count <= maximumMessageBytes {
            let byte = handle.readData(ofLength: 1)
            guard !byte.isEmpty else { return nil }
            if byte == Data([0x0A]) {
                if message.last == 0x0D { message.removeLast() }
                return message
            }
            message.append(byte)
        }
        return nil
    }
}

/// A single retained JSON-RPC session.  Requests are routed by ID, while
/// notifications are consumed without exposing their payload to UI callers.
actor CodexAppServerSession {
    typealias TransportFactory = @Sendable () -> any CodexAppServerTransport

    private let transportFactory: TransportFactory
    private let requestTimeout: TimeInterval
    private let initializationTimeout: TimeInterval
    private var transport: (any CodexAppServerTransport)?
    private var isInitialized = false
    private var nextRequestID = 1
    private var usageRefreshRequested = false
    private var requestInFlight = false
    private var requestWaiters: [RequestWaiter] = []
    /// At most one request can be outstanding, but keeping the continuation
    /// keyed by its normalized JSON-RPC ID makes the ownership rule explicit
    /// and prevents us from buffering any unsolicited response payload.
    private var pendingResponses: [JSONRPCID: PendingResponse] = [:]
    /// One persistent reader owns the stdio receive direction for a session.
    /// It remains active while idle so documented provider notifications are
    /// observed without adding another child, poller, or listener.
    private var receiveTask: Task<Void, Never>?
    private var receiveGeneration: UInt64 = 0
    private var receiverReachedEOF = false
    private var eventContinuation: AsyncStream<CodexAppServerEvent>.Continuation?
    private var eventContinuationID: UUID?
    private var executableURL: URL?

    init(
        transportFactory: @escaping TransportFactory = { ProcessCodexAppServerTransport() },
        requestTimeout: TimeInterval = 10,
        initializationTimeout: TimeInterval = 10
    ) {
        self.transportFactory = transportFactory
        self.requestTimeout = requestTimeout
        self.initializationTimeout = initializationTimeout
    }

    func start(executableURL: URL) throws {
        if let transport {
            if transport.isRunning { return }
            shutdown()
        }
        let transport = transportFactory()
        do {
            try transport.start(executableURL: executableURL)
        } catch {
            throw CodexUsageClientError(.processLaunchFailed)
        }
        self.transport = transport
        self.executableURL = executableURL
        receiverReachedEOF = false
        receiveGeneration &+= 1
    }

    func initializeIfNeeded() async throws {
        guard !isInitialized || transport?.needsInitialization == true else { return }
        if transport?.needsInitialization == true {
            // The process transport may retain itself across an owned-child
            // replacement.  Its old stdout reached EOF, so the replacement
            // requires a new, still-single receive loop before initialize.
            resetReceiveLoopForReplacement()
        }
        isInitialized = false

        struct InitializeParameters: Encodable {
            let clientInfo: ClientInfo
        }
        struct ClientInfo: Encodable {
            let name: String
            let title: String
            let version: String
        }

        do {
            let response: InitializeResponse = try await request(
                method: "initialize",
                params: InitializeParameters(
                    clientInfo: ClientInfo(
                        name: "codex-usage-monitor",
                        title: "Codex Usage Monitor",
                        version: "1.0.0"
                    )
                ),
                timeout: initializationTimeout,
                timeoutFailure: .initializationTimedOut
            )
            guard response.isCompatible else {
                throw CodexUsageClientError(.protocolIncompatible)
            }
            try sendNotification(method: "initialized")
            isInitialized = true
            transport?.markInitialized()
        } catch let error as CodexUsageClientError {
            shutdown()
            if error.failure == .initializationTimedOut {
                throw error
            }
            if case .serverError = error.failure {
                throw CodexUsageClientError(
                    .initializationRejected,
                    safeJSONRPCError: error.safeJSONRPCError
                )
            }
            throw error
        } catch {
            shutdown()
            throw CodexUsageClientError(.protocolIncompatible)
        }
    }

    func request<Result: Decodable>(
        method: String,
        timeout: TimeInterval? = nil,
        timeoutFailure: CodexUsageClientFailure? = nil
    ) async throws -> Result {
        try await request(
            method: method,
            timeout: timeout,
            timeoutFailure: timeoutFailure,
            encode: { id in
                try JSONEncoder().encode(JSONRPCRequestWithoutParameters(id: id, method: method))
            }
        )
    }

    /// The generated app-server schema specifies `params: null` for these
    /// account reads.  Keep that wire shape separate from `initialized`, whose
    /// notification intentionally has no parameters.
    func requestWithExplicitNullParameters<Result: Decodable>(
        method: String,
        timeout: TimeInterval? = nil,
        timeoutFailure: CodexUsageClientFailure? = nil
    ) async throws -> Result {
        try await request(
            method: method,
            timeout: timeout,
            timeoutFailure: timeoutFailure,
            encode: { id in
                try JSONEncoder().encode(JSONRPCRequestWithNullParameters(id: id, method: method))
            }
        )
    }

    func request<Result: Decodable, Parameters: Encodable>(
        method: String,
        params: Parameters,
        timeout: TimeInterval? = nil,
        timeoutFailure: CodexUsageClientFailure? = nil
    ) async throws -> Result {
        try await request(
            method: method,
            timeout: timeout,
            timeoutFailure: timeoutFailure,
            encode: { id in
                try JSONEncoder().encode(JSONRPCRequest(id: id, method: method, params: params))
            }
        )
    }

    private func request<Result: Decodable>(
        method: String,
        timeout: TimeInterval?,
        timeoutFailure: CodexUsageClientFailure?,
        encode: (Int) throws -> Data
    ) async throws -> Result {
        try await acquireRequestSlot()
        defer { releaseRequestSlot() }
        let id = nextRequestID
        nextRequestID += 1
        let expectedID = JSONRPCID.integer(id)

        do {
            guard transport?.isRunning == true, !receiverReachedEOF else {
                throw CodexUsageClientError(.processExited)
            }
            let data = try encode(id)
            let responseData = try await sendAndAwaitResponse(
                for: expectedID,
                method: method,
                requestData: data,
                timeout: timeout ?? requestTimeout,
                timeoutFailure: timeoutFailure ?? .requestTimedOut(method: method)
            )
            let envelope: JSONRPCResponse<Result>
            do {
                envelope = try JSONDecoder().decode(JSONRPCResponse<Result>.self, from: responseData)
            } catch {
                throw CodexUsageClientError(.malformedResponse(method: method))
            }
            guard envelope.id.matches(requestID: id) else {
                throw CodexUsageClientError(.malformedResponse(method: method))
            }
            if let error = envelope.error {
                throw Self.safeServerError(method: method, responseError: error)
            }
            guard let result = envelope.result else {
                throw CodexUsageClientError(.requiredDataMissing)
            }
            return result
        } catch let error as CodexUsageClientError {
            shutdown()
            throw error
        } catch {
            shutdown()
            throw CodexUsageClientError(.unknownSafeError)
        }
    }

    func takeUsageRefreshRequest() -> Bool {
        defer { usageRefreshRequested = false }
        return usageRefreshRequested
    }

    /// A single typed, privacy-safe invalidation stream for the client or its
    /// refresh coordinator.  Replacing an abandoned consumer cannot create a
    /// second transport listener; the session always has exactly one reader.
    func eventStream() -> AsyncStream<CodexAppServerEvent> {
        let continuationID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.eventContinuation?.finish()
            self.eventContinuation = continuation
            self.eventContinuationID = continuationID
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearEventContinuation(id: continuationID) }
            }
        }
    }

    func shutdown() {
        receiveGeneration &+= 1
        receiveTask?.cancel()
        receiveTask = nil
        transport?.stop()
        transport = nil
        executableURL = nil
        isInitialized = false
        nextRequestID = 1
        usageRefreshRequested = false
        receiverReachedEOF = false
        let pendingResponses = self.pendingResponses.values
        self.pendingResponses.removeAll()
        pendingResponses.forEach { pending in
            pending.timeoutTask?.cancel()
            pending.continuation.resume(throwing: CancellationError())
        }
        requestInFlight = false
        let waiters = requestWaiters
        requestWaiters.removeAll()
        waiters.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }

    /// Restores an owned transport after an unexpected exit and reports
    /// whether that restoration created a new initialized session.  The
    /// caller uses that fact to request one immediate account health refresh;
    /// a replacement must never wait for the slower fallback timer.
    @discardableResult
    func maintainTransportIfNeeded() async throws -> Bool {
        guard let transport else { return false }
        if transport.isRunning, transport.needsInitialization {
            try await initializeIfNeeded()
            return true
        }
        guard !transport.isRunning, let executableURL else { return false }
        // A new child is a new JSON-RPC session. Reset request sequencing and
        // any pending session state before its initialization handshake.
        shutdown()
        do {
            try start(executableURL: executableURL)
            try await initializeIfNeeded()
            return true
        } catch {
            shutdown()
            throw error
        }
    }

    func repairExitedTransportIfNeeded() async throws {
        try await maintainTransportIfNeeded()
    }

    private func sendNotification(method: String) throws {
        let data = try JSONEncoder().encode(JSONRPCNotification(method: method))
        try writeLine(data)
    }

    private func writeLine(_ data: Data) throws {
        guard let transport else {
            throw CodexUsageClientError(.processExited)
        }
        do {
            try transport.write(data)
        } catch {
            throw CodexUsageClientError(.processExited)
        }
    }

    private func sendAndAwaitResponse(
        for expectedID: JSONRPCID,
        method: String,
        requestData: Data,
        timeout: TimeInterval,
        timeoutFailure: CodexUsageClientFailure
    ) async throws -> Data {
        let nanoseconds = UInt64(max(0.001, timeout) * 1_000_000_000)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let key = expectedID.normalized
                guard pendingResponses[key] == nil else {
                    continuation.resume(throwing: CodexUsageClientError(.malformedResponse(method: method)))
                    return
                }
                pendingResponses[key] = PendingResponse(method: method, continuation: continuation)
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                    } catch {
                        return
                    }
                    self.timeoutPendingResponse(for: key, failure: timeoutFailure)
                }
                pendingResponses[key]?.timeoutTask = timeoutTask
                do {
                    try writeLine(requestData)
                    startReceiveLoopIfNeeded()
                } catch {
                    timeoutTask.cancel()
                    pendingResponses.removeValue(forKey: key)
                    continuation.resume(throwing: error)
                }
            }
        }, onCancel: {
            Task { await self.cancelPendingResponse(for: expectedID.normalized) }
        })
    }

    private func startReceiveLoopIfNeeded() {
        guard receiveTask == nil, !receiverReachedEOF, let transport else { return }
        let generation = receiveGeneration
        receiveTask = Task { [weak self, transport] in
            await self?.receiveMessages(from: transport, generation: generation)
        }
    }

    private func receiveMessages(
        from transport: any CodexAppServerTransport,
        generation: UInt64
    ) async {
        while !Task.isCancelled {
            do {
                guard let data = try await transport.readMessage() else {
                    receiveLoopEnded(generation: generation)
                    return
                }
                routeInboundMessage(data, generation: generation)
            } catch {
                receiveLoopEnded(generation: generation)
                return
            }
        }
    }

    private func routeInboundMessage(_ data: Data, generation: UInt64) {
        guard generation == receiveGeneration else { return }
        let header: JSONRPCInboundHeader
        do {
            header = try JSONDecoder().decode(JSONRPCInboundHeader.self, from: data)
        } catch {
            rejectSerializedResponseAsMalformed()
            return
        }

        if let notificationMethod = header.method {
            routeNotification(method: notificationMethod)
            return
        }
        guard let responseID = header.id else {
            rejectSerializedResponseAsMalformed()
            return
        }
        let key = responseID.normalized
        guard let pending = pendingResponses.removeValue(forKey: key) else {
            // Idle, uncorrelated responses cannot belong to a monitor request.
            // With serialized requests they are discarded rather than retained.
            rejectSerializedResponseAsMalformed()
            return
        }
        pending.timeoutTask?.cancel()
        pending.continuation.resume(returning: data)
    }

    private func rejectSerializedResponseAsMalformed() {
        guard let (key, pending) = pendingResponses.first else { return }
        pendingResponses.removeValue(forKey: key)
        pending.timeoutTask?.cancel()
        pending.continuation.resume(
            throwing: CodexUsageClientError(.malformedResponse(method: pending.method))
        )
        // A response for a different serialized ID is a protocol fault. Close
        // the transport now so no subsequent inbound payload is retained.
        transport?.stop()
    }

    private func timeoutPendingResponse(
        for key: JSONRPCID,
        failure: CodexUsageClientFailure
    ) {
        guard let pending = pendingResponses.removeValue(forKey: key) else { return }
        pending.timeoutTask?.cancel()
        transport?.stop()
        pending.continuation.resume(throwing: CodexUsageClientError(failure))
    }

    private func cancelPendingResponse(for key: JSONRPCID) {
        guard let pending = pendingResponses.removeValue(forKey: key) else { return }
        pending.timeoutTask?.cancel()
        transport?.stop()
        pending.continuation.resume(throwing: CancellationError())
    }

    private func receiveLoopEnded(generation: UInt64) {
        guard generation == receiveGeneration else { return }
        receiveTask = nil
        receiverReachedEOF = true
        let pendingResponses = self.pendingResponses.values
        self.pendingResponses.removeAll()
        pendingResponses.forEach { pending in
            pending.timeoutTask?.cancel()
            pending.continuation.resume(throwing: CodexUsageClientError(.processExited))
        }
    }

    private func resetReceiveLoopForReplacement() {
        receiveGeneration &+= 1
        receiveTask?.cancel()
        receiveTask = nil
        receiverReachedEOF = false
    }

    private func clearEventContinuation(id: UUID) {
        guard eventContinuationID == id else { return }
        eventContinuation = nil
        eventContinuationID = nil
    }

    private func acquireRequestSlot() async throws {
        guard requestInFlight else {
            requestInFlight = true
            return
        }
        let waiterID = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    requestWaiters.append(.init(id: waiterID, continuation: continuation))
                }
            }
        }, onCancel: {
            Task { await self.cancelRequestWaiter(id: waiterID) }
        })
        try Task.checkCancellation()
    }

    private func releaseRequestSlot() {
        while !requestWaiters.isEmpty {
            let next = requestWaiters.removeFirst()
            next.continuation.resume()
            return
        }
        requestInFlight = false
    }

    private func cancelRequestWaiter(id: UUID) {
        guard let index = requestWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = requestWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func routeNotification(method: String) {
        switch method {
        case "account/updated", "account/rateLimits/updated":
            // The next explicit store action performs one normal account-first
            // refresh.  No notification can create an unbounded polling loop.
            usageRefreshRequested = true
            eventContinuation?.yield(
                method == "account/updated" ? .accountUpdated : .rateLimitsUpdated
            )
        default:
            break
        }
    }

    private struct PendingResponse {
        let method: String
        let continuation: CheckedContinuation<Data, Error>
        var timeoutTask: Task<Void, Never>?
    }

    private struct RequestWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private static func safeServerError(
        method: String,
        responseError: JSONRPCError
    ) -> CodexUsageClientError {
        let category: CodexSafeJSONRPCError.Category
        switch responseError.discriminator {
        case .serverOverloaded:
            category = .serverOverloaded
        case .unauthorized:
            category = .unauthorizedOrAuthorizationRequired
        case .badRequest:
            category = .invalidRequestOrMalformedResponse
        case nil:
            switch responseError.code {
            case -32601:
                category = .methodUnavailableOrProtocolIncompatible
            case -32700, -32600, -32602:
                category = .invalidRequestOrMalformedResponse
            default:
                category = .safeGenericServerError
            }
        }

        let safeMessage: String
        let failure: CodexUsageClientFailure
        let retryable: Bool
        switch category {
        case .serverOverloaded:
            safeMessage = "The local Codex service is currently busy."
            failure = .serverOverloaded
            retryable = true
        case .unauthorizedOrAuthorizationRequired:
            safeMessage = "Codex authorization is required."
            failure = .accountAuthorizationRequired
            retryable = false
        case .methodUnavailableOrProtocolIncompatible:
            safeMessage = "This local Codex version does not support the requested operation."
            failure = .protocolIncompatible
            retryable = false
        case .invalidRequestOrMalformedResponse:
            safeMessage = "The local Codex request was not accepted."
            failure = .malformedResponse(method: method)
            retryable = false
        case .safeGenericServerError:
            safeMessage = "The local Codex service could not complete this request."
            failure = .serverError(method: method, safeMessage: safeMessage)
            retryable = false
        }

        return CodexUsageClientError(
            failure,
            safeJSONRPCError: CodexSafeJSONRPCError(
                code: responseError.code,
                category: category,
                method: method,
                safeMessage: safeMessage,
                isRetryable: retryable
            )
        )
    }
}

private struct InitializeResponse: Decodable {
    private let codexHome: String
    private let platformFamily: String
    private let platformOs: String
    private let userAgent: String

    var isCompatible: Bool {
        codexHome.hasPrefix("/")
            && !platformFamily.isEmpty
            && !platformOs.isEmpty
            && !userAgent.isEmpty
    }
}

private struct JSONRPCRequest<Parameters: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Parameters
}

private struct JSONRPCRequestWithoutParameters: Encodable {
    let id: Int
    let method: String
}

private struct JSONRPCRequestWithNullParameters: Encodable {
    let id: Int
    let method: String

    private enum CodingKeys: String, CodingKey {
        case id
        case method
        case params
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encodeNil(forKey: .params)
    }
}

private struct JSONRPCNotification: Encodable {
    let method: String
}

private struct JSONRPCInboundHeader: Decodable {
    let id: JSONRPCID?
    let method: String?
}

private struct JSONRPCResponse<Result: Decodable>: Decodable {
    let id: JSONRPCID
    let result: Result?
    let error: JSONRPCError?
}

private struct JSONRPCError: Decodable {
    let code: Int
    let discriminator: JSONRPCErrorDiscriminator?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The schema requires a string message, but it is intentionally only
        // validated and then discarded.  It must never reach state or UI.
        code = try container.decode(Int.self, forKey: .code)
        _ = try container.decode(String.self, forKey: .message)
        discriminator = try? container.decodeIfPresent(JSONRPCErrorData.self, forKey: .data)?.discriminator
    }
}

/// Only schema-defined exact values are decoded. Unknown `data` is ignored
/// rather than retained, logged, or matched by free-form upstream text.
private struct JSONRPCErrorData: Decodable {
    let discriminator: JSONRPCErrorDiscriminator?

    private enum CodingKeys: String, CodingKey {
        case codexErrorInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        discriminator = try container.decodeIfPresent(JSONRPCErrorDiscriminator.self, forKey: .codexErrorInfo)
    }
}

private enum JSONRPCErrorDiscriminator: String, Decodable {
    case serverOverloaded
    case unauthorized
    case badRequest
}

private enum JSONRPCID: Hashable, Decodable {
    case integer(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func matches(requestID: Int) -> Bool {
        switch self {
        case .integer(let value): value == requestID
        case .string(let value): value == String(requestID)
        }
    }

    /// JSON-RPC allows string or numeric IDs.  The monitor emits numeric IDs,
    /// but accepts their decimal-string equivalent so response routing remains
    /// compatible without treating an unrelated opaque string as a match.
    var normalized: JSONRPCID {
        switch self {
        case .integer:
            self
        case .string(let value):
            Int(value).map(JSONRPCID.integer) ?? self
        }
    }
}

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    @discardableResult
    func resume(_ continuation: CheckedContinuation<Value, Error>, returning value: Value) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    func resume(
        _ continuation: CheckedContinuation<Value, Error>,
        throwing error: CodexUsageClientError
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        continuation.resume(throwing: error)
        return true
    }
}

private final class TimeoutTaskCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var responseFinished = false
    private var timeoutTask: Task<Void, Never>?

    func install(_ task: Task<Void, Never>) {
        lock.lock()
        if responseFinished {
            lock.unlock()
            task.cancel()
            return
        }
        timeoutTask = task
        lock.unlock()
    }

    func cancelAfterResponse() {
        lock.lock()
        responseFinished = true
        let task = timeoutTask
        timeoutTask = nil
        lock.unlock()
        task?.cancel()
    }
}
