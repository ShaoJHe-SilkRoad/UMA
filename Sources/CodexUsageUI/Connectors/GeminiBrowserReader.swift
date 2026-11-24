import ClaudeBrowserBridgeProtocol
import ClaudeBrowserNativeHostCore
import Foundation

/// The one Safari Bridge client of this process, published by the Claude
/// integration that creates it. Gemini reads must share it: its response
/// listener consumes every answer in the App Group mailbox, so a second
/// client would take the other's answers.
enum SafariBridgeSharedClient {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var client: ClaudeSafariHostClientAdapter?

    static func publish(_ adapter: ClaudeSafariHostClientAdapter) {
        lock.withLock { client = adapter }
    }

    static var current: ClaudeSafariHostClientAdapter? {
        lock.withLock { client }
    }
}

/// What the Gemini connector needs from the Safari Bridge, as closures so
/// tests can stand in for Safari.
struct GeminiBrowserIntegration: Sendable {
    typealias Handler = @Sendable (GeminiBrowserInboundEvent) async -> Void

    let startListening: @Sendable (@escaping Handler) async -> Bool
    let stopListening: @Sendable () async -> Void
    let requestRead: @Sendable (_ requestID: String) async -> ClaudeBrowserAutomaticDispatchResult
    let closeOwnedTab: @Sendable (_ requestID: String) async -> Void

    static func unavailable() -> Self {
        Self(
            startListening: { _ in false },
            stopListening: {},
            requestRead: { _ in .companionUnavailable },
            closeOwnedTab: { _ in }
        )
    }

    /// Resolves the shared client when it is used, not when this is built, so
    /// the order the two integrations are made in does not matter.
    static func shared() -> Self {
        Self(
            startListening: { handler in
                guard let client = SafariBridgeSharedClient.current else { return false }
                return await client.startGemini(handler)
            },
            stopListening: {
                await SafariBridgeSharedClient.current?.stopGemini()
            },
            requestRead: { requestID in
                guard let client = SafariBridgeSharedClient.current else {
                    return .companionUnavailable
                }
                // A Gemini read never launches Safari by itself.
                return await client.submit(requestID: requestID, oneShot: false, provider: .gemini)
            },
            closeOwnedTab: { requestID in
                await SafariBridgeSharedClient.current?.close(requestID)
            }
        )
    }
}

enum GeminiBrowserReadError: Error, Equatable, Sendable {
    /// Safari has not been allowed to read gemini.google.com.
    case permissionRequired
    /// The Usage page asked for sign-in.
    case signInRequired
    /// The Bridge or its extension is not installed, enabled or answering.
    case companionUnavailable
    case browserUnavailable
    /// AUV and the Bridge are not the same release.
    case protocolMismatch
    /// The Bridge was busy with another read for too long.
    case busy
    case timedOut
    /// The page loaded but its usage could not be read.
    case usageUnavailable
    /// The temporary tab was closed or could not be proven AUV's own.
    case tabUnavailable
    case cancelled
}

/// One Gemini Usage read through the Safari Bridge: ask for it, wait for the
/// sanitized observation and its terminal event, and give up after a bound,
/// closing the read's own tab.
actor GeminiBrowserReader {
    static let readDeadline: Duration = .seconds(60)

    private let integration: GeminiBrowserIntegration
    private let deadline: Duration
    private var listening = false
    private var pendingRequestID: String?
    private var pendingObservation: GeminiBrowserObservationEnvelope?
    private var pendingContinuation: CheckedContinuation<Result<GeminiBrowserObservation, GeminiBrowserReadError>, Never>?
    /// An answer that arrived while `read()` was still between asking and
    /// waiting; the actor lets events in at every suspension.
    private var earlyResult: Result<GeminiBrowserObservation, GeminiBrowserReadError>?

    init(integration: GeminiBrowserIntegration, deadline: Duration = readDeadline) {
        self.integration = integration
        self.deadline = deadline
    }

    func read() async throws -> GeminiBrowserObservation {
        guard pendingRequestID == nil, pendingContinuation == nil else {
            throw GeminiBrowserReadError.busy
        }
        earlyResult = nil
        if !listening {
            listening = await integration.startListening { [weak self] event in
                await self?.receive(event)
            }
            guard listening else { throw GeminiBrowserReadError.companionUnavailable }
        }
        let requestID = UUID().uuidString.lowercased()
        pendingRequestID = requestID
        pendingObservation = nil
        let dispatch = await integration.requestRead(requestID)
        guard dispatch == .dispatched else {
            clearPending()
            throw Self.error(for: dispatch)
        }
        let bound = deadline
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: bound)
            await self?.expire(requestID)
        }
        let result = await withCheckedContinuation { continuation in
            if let early = earlyResult {
                earlyResult = nil
                continuation.resume(returning: early)
            } else if pendingRequestID == requestID {
                pendingContinuation = continuation
            } else {
                continuation.resume(returning: .failure(.cancelled))
            }
        }
        timeout.cancel()
        return try result.get()
    }

    func stop() async {
        resolve(.failure(.cancelled))
        if listening {
            listening = false
            await integration.stopListening()
        }
    }

    private func receive(_ event: GeminiBrowserInboundEvent) {
        guard let requestID = pendingRequestID else { return }
        switch event {
        case let .observation(envelope):
            guard envelope.requestID.lowercased() == requestID,
                  (try? GeminiBrowserMessageDecoder.validate(envelope)) != nil
            else { return }
            pendingObservation = envelope
        case let .automation(event):
            guard event.requestID.lowercased() == requestID else { return }
            switch event.status {
            case .refreshCompleted:
                if let observation = pendingObservation?.observation {
                    resolve(.success(observation))
                } else {
                    resolve(.failure(.usageUnavailable))
                }
            case .permissionRequired: resolve(.failure(.permissionRequired))
            case .signInRequired: resolve(.failure(.signInRequired))
            case .browserUnavailable: resolve(.failure(.browserUnavailable))
            case .routeRejected, .usageUnavailable: resolve(.failure(.usageUnavailable))
            case .tabUnavailable, .ownedTabClosed, .ownedTabOwnershipLost:
                resolve(.failure(.tabUnavailable))
            default:
                return
            }
        case let .dispatchFailure(result):
            resolve(.failure(Self.error(for: result)))
        }
    }

    private func expire(_ requestID: String) async {
        guard pendingRequestID == requestID else { return }
        resolve(.failure(.timedOut))
        // The read's own tab, if it ever opened, is closed by the companion
        // only on a command naming this read.
        await integration.closeOwnedTab(requestID)
    }

    private func resolve(_ result: Result<GeminiBrowserObservation, GeminiBrowserReadError>) {
        guard pendingRequestID != nil || pendingContinuation != nil else { return }
        let continuation = pendingContinuation
        clearPending()
        if let continuation {
            continuation.resume(returning: result)
        } else {
            earlyResult = result
        }
    }

    private func clearPending() {
        pendingRequestID = nil
        pendingObservation = nil
        pendingContinuation = nil
    }

    private static func error(for dispatch: ClaudeBrowserAutomaticDispatchResult) -> GeminiBrowserReadError {
        switch dispatch {
        case .dispatched, .workDispatchFailed: .busy
        case .browserUnavailable, .unsupportedBrowser: .browserUnavailable
        case .companionUnavailable, .companionStarting: .companionUnavailable
        case .protocolMismatch: .protocolMismatch
        }
    }
}
