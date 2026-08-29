import ClaudeBrowserBridgeProtocol
import Darwin
import Dispatch
import Foundation

/// The shared container is a transport for allowlisted, correlated messages;
/// it is not a browser cache and is never an authority for Safari tab state.
public enum ClaudeSafariHostIPCContract {
    public static let schemaVersion = 2
    /// Historical aliases retained for Test-channel fixtures. Runtime code
    /// must select an exact `ClaudeSafariHostRuntimeProfile` from signed bundle
    /// metadata rather than assuming these values.
    public static let appGroupIdentifier =
        ClaudeBrowserBridgeContract.safariHostTestAppGroupIdentifier
    public static let hostApplicationIdentifier =
        ClaudeBrowserBridgeContract.safariHostTestApplicationIdentifier
    public static let hostExtensionIdentifier =
        ClaudeBrowserBridgeContract.safariHostTestExtensionIdentifier
    public static let maximumMessageBytes = 8_192
    public static let maximumQueuedMessages = 16
    public static let maximumMessageAge: TimeInterval = 120

    public static func accepts(
        hostApplicationIdentifier: String,
        extensionIdentifier: String
    ) -> Bool {
        guard let profile = ClaudeSafariHostRuntimeProfile
            .matchingHostApplicationIdentifier(hostApplicationIdentifier)
        else { return false }
        return profile.identity.extensionIdentifier == extensionIdentifier
    }
}

public enum ClaudeSafariHostIPCOperation: String, Codable, CaseIterable, Sendable {
    case verifyCompanion
    case accuracySync
    case automaticRefresh
    case closeOwnedTab
}

public struct ClaudeSafariHostIPCRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestID: String
    public let runtimeGenerationID: String
    public let operation: ClaudeSafariHostIPCOperation
    /// Present only for a close command. The command gets its own request ID;
    /// this field identifies the earlier in-flight operation being cancelled.
    /// Keeping the two IDs distinct prevents a consumed mailbox filename or a
    /// stale close receipt from aliasing the original operation.
    public let targetRequestID: String?
    public let allowSafariLaunch: Bool
    public let createdAt: String

    public init(
        requestID: String = UUID().uuidString.lowercased(),
        runtimeGenerationID: String,
        operation: ClaudeSafariHostIPCOperation,
        targetRequestID: String? = nil,
        allowSafariLaunch: Bool = false,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        schemaVersion = ClaudeSafariHostIPCContract.schemaVersion
        self.requestID = requestID.lowercased()
        self.runtimeGenerationID = runtimeGenerationID.lowercased()
        self.operation = operation
        self.targetRequestID = targetRequestID?.lowercased()
        self.allowSafariLaunch = allowSafariLaunch
        self.createdAt = createdAt
    }

    public var isStructurallyValid: Bool {
        let targetIsValid: Bool
        if operation == .closeOwnedTab {
            targetIsValid = targetRequestID.flatMap(UUID.init(uuidString:)) != nil
                && targetRequestID != requestID
        } else {
            targetIsValid = targetRequestID == nil
        }
        return schemaVersion == ClaudeSafariHostIPCContract.schemaVersion
            && UUID(uuidString: requestID) != nil
            && UUID(uuidString: runtimeGenerationID) != nil
            && ISO8601DateFormatter().date(from: createdAt) != nil
            && (!allowSafariLaunch
                || operation == .verifyCompanion
                || operation == .accuracySync)
            && targetIsValid
    }
}

/// Content-free policy for the Host's first cold-start boundary. A successful
/// SafariServices dispatch callback is not evidence that Safari was running or
/// ready to instantiate the WebExtension background. The Host must establish
/// this process lifecycle first, then dispatch exactly once.
public enum ClaudeSafariHostColdStartAction: String, Equatable, Sendable {
    case dispatch
    case launchSafari
    case failSafariUnavailable
}

public enum ClaudeSafariHostColdStartPolicy {
    public static func action(
        safariProcessPresent: Bool,
        safariFinishedLaunching: Bool,
        allowSafariLaunch: Bool
    ) -> ClaudeSafariHostColdStartAction {
        if safariProcessPresent && safariFinishedLaunching { return .dispatch }
        return allowSafariLaunch ? .launchSafari : .failSafariUnavailable
    }

    public enum OpenCallbackAction: Equatable, Sendable {
        case ready
        case waitForLaunchEvent
        case unavailable
    }

    /// `NSWorkspace.openApplication` can return a live application before its
    /// launch event. That transient result is not a terminal failure and is not
    /// sufficient to begin SafariServices dispatch.
    public static func openCallbackAction(
        applicationPresent: Bool,
        applicationTerminated: Bool,
        applicationFinishedLaunching: Bool,
        errorPresent: Bool
    ) -> OpenCallbackAction {
        guard !errorPresent, applicationPresent, !applicationTerminated else {
            return .unavailable
        }
        return applicationFinishedLaunching ? .ready : .waitForLaunchEvent
    }

    public static func launchEventMatches(
        expectedBundleIdentifier: String,
        observedBundleIdentifier: String?,
        applicationTerminated: Bool
    ) -> Bool {
        !applicationTerminated && observedBundleIdentifier == expectedBundleIdentifier
    }
}

public enum ClaudeSafariHostApplicationReadiness: Equatable, Sendable {
    case ready
    case unavailable
    case deadlineExpired
}

/// Serializes the NSWorkspace launch event, open callback, and bounded deadline.
/// The first causal terminal result wins; late events cannot revive a request.
public final class ClaudeSafariHostApplicationReadinessGate: @unchecked Sendable {
    private let lock = NSLock()
    private var result: ClaudeSafariHostApplicationReadiness?
    private var continuation: CheckedContinuation<ClaudeSafariHostApplicationReadiness, Never>?

    public init() {}

    @discardableResult
    public func resolve(_ value: ClaudeSafariHostApplicationReadiness) -> Bool {
        let waiting: CheckedContinuation<ClaudeSafariHostApplicationReadiness, Never>?
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return false
        }
        result = value
        waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
        return true
    }

    public func wait() async -> ClaudeSafariHostApplicationReadiness {
        await withCheckedContinuation { next in
            lock.lock()
            if let result {
                lock.unlock()
                next.resume(returning: result)
            } else {
                precondition(continuation == nil)
                continuation = next
                lock.unlock()
            }
        }
    }
}

public enum ClaudeSafariHostIPCOutcome: String, Codable, CaseIterable, Sendable {
    case companionVerified
    /// One causal terminal success: the allowlisted observation and the
    /// post-cleanup completion receipt are transported in the same file.
    case completed
    case observation
    case automation
    case failed
}

public enum ClaudeSafariHostIPCFailureReason: String, Codable, CaseIterable, Sendable {
    case invalidRequest
    case duplicateRequest
    case requestInFlight
    case cancellationTargetUnavailable
    case runtimeGenerationMismatch
    case safariUnavailable
    case extensionUnavailable
    case dispatchRejected
    case dispatchCompletionUnavailable
    case nativeResponseUnavailable
    case protocolMismatch
    case extensionBackgroundNotAcknowledged
    case providerOperationTimedOut
    case observationMissing
    case duplicateNativeResponse
    case unexpectedNativeResponse
    case timedOut
    case cancelled
}

/// Resolves Safari's callback-style dispatch exactly once. The deadline is a
/// terminal failure bound, not lifecycle synchronization: a real callback
/// always wins when it arrives first, while a callback that never arrives can
/// no longer strand the Host transaction indefinitely.
public enum ClaudeSafariHostDispatchCompletion: Equatable, Sendable {
    case accepted
    case rejected
    case deadlineExpired
}

public final class ClaudeSafariHostDispatchCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var terminal: ClaudeSafariHostDispatchCompletion?
    private var waiter: CheckedContinuation<ClaudeSafariHostDispatchCompletion, Never>?

    public init() {}

    public func wait() async -> ClaudeSafariHostDispatchCompletion {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let terminal {
                lock.unlock()
                continuation.resume(returning: terminal)
            } else {
                precondition(waiter == nil, "dispatch completion gate supports one waiter")
                waiter = continuation
                lock.unlock()
            }
        }
    }

    @discardableResult
    public func resolve(_ result: ClaudeSafariHostDispatchCompletion) -> Bool {
        lock.lock()
        guard terminal == nil else {
            lock.unlock()
            return false
        }
        terminal = result
        let continuation = waiter
        waiter = nil
        lock.unlock()
        continuation?.resume(returning: result)
        return true
    }
}

/// Last causally acknowledged verification boundary in the immutable Host.
/// The client may expand this into a monotonic prefix for diagnostics, but it
/// must never infer a later stage from elapsed time alone.
public enum ClaudeSafariHostIPCVerificationStage: String, Codable, CaseIterable, Sendable {
    case hostRequestAccepted
    case wakeDispatchAccepted
    case extensionBackgroundAcknowledged
    case nativeQualificationDispatched
    case nativeHandlerEntered
    case nativeRequestDecoded
    case runtimeGenerationValidated
    case nativeResponseCreated
    case nativeResponseSent
    case extensionResponseReceived
    case nativeQualificationReceived
    case companionVerified
}

/// Content-free identity of the signed Host runtime that emitted a terminal
/// qualification response. This carries package identity only; it has no
/// provider, page, user, credential, or browser-state field.
public struct ClaudeSafariHostIPCRuntimeDescriptor: Codable, Equatable, Sendable {
    public let hostApplicationIdentifier: String
    public let extensionIdentifier: String
    public let teamIdentifier: String
    public let hostVersion: String
    public let hostBuild: String
    public let runtimeGenerationID: String
    public let bridgeProtocolVersion: Int

    public init(
        hostApplicationIdentifier: String,
        extensionIdentifier: String,
        teamIdentifier: String,
        hostVersion: String,
        hostBuild: String,
        runtimeGenerationID: String,
        bridgeProtocolVersion: Int
    ) {
        self.hostApplicationIdentifier = hostApplicationIdentifier
        self.extensionIdentifier = extensionIdentifier
        self.teamIdentifier = teamIdentifier
        self.hostVersion = hostVersion
        self.hostBuild = hostBuild
        self.runtimeGenerationID = runtimeGenerationID.lowercased()
        self.bridgeProtocolVersion = bridgeProtocolVersion
    }

    public var isStructurallyValid: Bool {
        ClaudeSafariHostIPCContract.accepts(
            hostApplicationIdentifier: hostApplicationIdentifier,
            extensionIdentifier: extensionIdentifier
        )
            && teamIdentifier == ClaudeBrowserBridgeContract.expectedTeamIdentifier
            && !hostVersion.isEmpty && hostVersion.utf8.count <= 32
            && !hostBuild.isEmpty && hostBuild.utf8.count <= 32
            && hostBuild.allSatisfy(\.isNumber)
            && UUID(uuidString: runtimeGenerationID) != nil
            && bridgeProtocolVersion == ClaudeBrowserBridgeContract.schemaVersion
    }
}

/// A successful response carries the sanitized observation and its content-free
/// post-cleanup completion receipt together. Failure and qualification responses
/// remain content-free. No URL, page text, tab metadata, account identity,
/// cookie, token, or credential field exists in this schema.
public struct ClaudeSafariHostIPCResponse: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let responseID: String
    public let requestID: String
    public let runtimeGenerationID: String
    public let outcome: ClaudeSafariHostIPCOutcome
    public let observation: ClaudeBrowserObservationEnvelope?
    public let automationEvent: ClaudeBrowserAutomationEvent?
    public let providerFailureReason: ClaudeBrowserProviderFailureReason?
    public let failureReason: ClaudeSafariHostIPCFailureReason?
    public let verificationStage: ClaudeSafariHostIPCVerificationStage?
    public let runtimeDescriptor: ClaudeSafariHostIPCRuntimeDescriptor?
    public let occurredAt: String

    public init(
        responseID: String = UUID().uuidString.lowercased(),
        requestID: String,
        runtimeGenerationID: String,
        outcome: ClaudeSafariHostIPCOutcome,
        observation: ClaudeBrowserObservationEnvelope? = nil,
        automationEvent: ClaudeBrowserAutomationEvent? = nil,
        providerFailureReason: ClaudeBrowserProviderFailureReason? = nil,
        failureReason: ClaudeSafariHostIPCFailureReason? = nil,
        verificationStage: ClaudeSafariHostIPCVerificationStage? = nil,
        runtimeDescriptor: ClaudeSafariHostIPCRuntimeDescriptor? = nil,
        occurredAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        schemaVersion = ClaudeSafariHostIPCContract.schemaVersion
        self.responseID = responseID.lowercased()
        self.requestID = requestID.lowercased()
        self.runtimeGenerationID = runtimeGenerationID.lowercased()
        self.outcome = outcome
        self.observation = observation
        self.automationEvent = automationEvent
        self.providerFailureReason = providerFailureReason
        self.failureReason = failureReason
        self.verificationStage = verificationStage
        self.runtimeDescriptor = runtimeDescriptor
        self.occurredAt = occurredAt
    }

    public var isStructurallyValid: Bool {
        guard schemaVersion == ClaudeSafariHostIPCContract.schemaVersion,
              UUID(uuidString: responseID) != nil,
              UUID(uuidString: requestID) != nil,
              UUID(uuidString: runtimeGenerationID) != nil,
              ISO8601DateFormatter().date(from: occurredAt) != nil
        else { return false }
        if let runtimeDescriptor {
            guard runtimeDescriptor.isStructurallyValid,
                  runtimeDescriptor.runtimeGenerationID == runtimeGenerationID
            else { return false }
        }
        switch outcome {
        case .companionVerified:
            return observation == nil && automationEvent == nil
                && providerFailureReason == nil && failureReason == nil
                && verificationStage == .companionVerified
                && runtimeDescriptor != nil
        case .completed:
            return observation?.requestID.lowercased() == requestID
                && automationEvent?.requestID.lowercased() == requestID
                && automationEvent?.status == .refreshCompleted
                && providerFailureReason == nil && failureReason == nil
                && verificationStage == nil
        case .observation:
            return observation?.requestID.lowercased() == requestID
                && automationEvent == nil && providerFailureReason == nil
                && failureReason == nil
                && verificationStage == nil
        case .automation:
            return automationEvent?.requestID.lowercased() == requestID
                && observation == nil && failureReason == nil
                && verificationStage == nil
                && (providerFailureReason == nil
                    || automationEvent?.status == .permissionRequired
                    || automationEvent?.status == .signInRequired
                    || automationEvent?.status == .routeRejected
                    || automationEvent?.status == .usageUnavailable
                    || automationEvent?.status == .tabUnavailable)
        case .failed:
            return failureReason != nil && observation == nil && automationEvent == nil
                && providerFailureReason == nil
        }
    }
}

public enum ClaudeSafariHostIPCError: Error, Equatable, Sendable {
    case appGroupUnavailable
    case unsafeEndpoint
    case invalidMessage
    case queueFull
    case messageExists
    case ioFailure
}

public struct ClaudeSafariHostIPCEndpoint: Equatable, Sendable {
    public let rootDirectoryPath: String

    public init(rootDirectoryPath: String) {
        self.rootDirectoryPath = rootDirectoryPath
    }

    public static func appGroup(
        identifier: String = ClaudeSafariHostIPCContract.appGroupIdentifier,
        fileManager: FileManager = .default
    ) throws -> Self {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else { throw ClaudeSafariHostIPCError.appGroupUnavailable }
        return Self(
            rootDirectoryPath: container
                .appendingPathComponent("ClaudeSafariHost", isDirectory: true).path
        )
    }

    public var requestDirectoryPath: String { rootDirectoryPath + "/Requests" }
    public var responseDirectoryPath: String { rootDirectoryPath + "/Responses" }
    public var nativeInboxDirectoryPath: String { rootDirectoryPath + "/NativeInbox" }
    public var ownedTabDirectoryPath: String { rootDirectoryPath + "/OwnedTab" }

    public func prepareOwnerOnlyRoot() throws {
        try preparePrivateDirectory(rootDirectoryPath, uid: getuid())
    }
}

public struct ClaudeSafariHostIPCClient: Sendable {
    public let endpoint: ClaudeSafariHostIPCEndpoint

    public init(endpoint: ClaudeSafariHostIPCEndpoint) {
        self.endpoint = endpoint
    }

    public init() throws {
        endpoint = try .appGroup()
    }

    public func submit(_ request: ClaudeSafariHostIPCRequest) throws {
        guard request.isStructurallyValid else {
            throw ClaudeSafariHostIPCError.invalidMessage
        }
        try ClaudeSafariHostMailbox.write(
            request,
            id: request.requestID,
            directoryPath: endpoint.requestDirectoryPath
        )
    }

    public func makeResponseListener(
        handler: @escaping @Sendable (ClaudeSafariHostIPCResponse) -> Void
    ) -> ClaudeSafariHostIPCResponseListener {
        ClaudeSafariHostIPCResponseListener(endpoint: endpoint, handler: handler)
    }
}

public final class ClaudeSafariHostIPCRequestServer: @unchecked Sendable {
    private let watcher: ClaudeSafariHostMailboxWatcher<ClaudeSafariHostIPCRequest>

    public init(
        endpoint: ClaudeSafariHostIPCEndpoint,
        handler: @escaping @Sendable (ClaudeSafariHostIPCRequest) -> Void
    ) {
        watcher = ClaudeSafariHostMailboxWatcher(
            directoryPath: endpoint.requestDirectoryPath,
            validation: { $0.isStructurallyValid },
            handler: handler
        )
    }

    public func start() throws { try watcher.start() }
    public func stop() { watcher.stop() }
}

public final class ClaudeSafariHostIPCResponseListener: @unchecked Sendable {
    private let watcher: ClaudeSafariHostMailboxWatcher<ClaudeSafariHostIPCResponse>

    public init(
        endpoint: ClaudeSafariHostIPCEndpoint,
        handler: @escaping @Sendable (ClaudeSafariHostIPCResponse) -> Void
    ) {
        watcher = ClaudeSafariHostMailboxWatcher(
            directoryPath: endpoint.responseDirectoryPath,
            validation: { $0.isStructurallyValid },
            handler: handler
        )
    }

    public func start() throws { try watcher.start() }
    public func stop() { watcher.stop() }
}

public struct ClaudeSafariHostIPCResponder: Sendable {
    public let endpoint: ClaudeSafariHostIPCEndpoint

    public init(endpoint: ClaudeSafariHostIPCEndpoint) {
        self.endpoint = endpoint
    }

    public func send(_ response: ClaudeSafariHostIPCResponse) throws {
        guard response.isStructurallyValid else {
            throw ClaudeSafariHostIPCError.invalidMessage
        }
        try ClaudeSafariHostMailbox.write(
            response,
            id: response.responseID,
            directoryPath: endpoint.responseDirectoryPath
        )
    }
}

private enum ClaudeSafariHostMailbox {
    static func write<Value: Encodable>(
        _ value: Value,
        id: String,
        directoryPath: String,
        uid: uid_t = getuid()
    ) throws {
        guard UUID(uuidString: id) != nil else {
            throw ClaudeSafariHostIPCError.invalidMessage
        }
        try prepareMailboxDirectory(directoryPath, uid: uid)
        guard try regularMessageCount(directoryPath, uid: uid)
                < ClaudeSafariHostIPCContract.maximumQueuedMessages
        else { throw ClaudeSafariHostIPCError.queueFull }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard !data.isEmpty,
              data.count <= ClaudeSafariHostIPCContract.maximumMessageBytes
        else { throw ClaudeSafariHostIPCError.invalidMessage }

        let finalPath = directoryPath + "/" + id.lowercased() + ".json"
        let temporaryPath = directoryPath + "/." + id.lowercased()
            + "." + UUID().uuidString.lowercased() + ".tmp"
        let descriptor = open(
            temporaryPath,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw ClaudeSafariHostIPCError.ioFailure }
        var removeTemporary = true
        defer {
            close(descriptor)
            if removeTemporary { unlink(temporaryPath) }
        }
        try validateRegularFile(descriptor: descriptor, uid: uid, expectedSize: 0)
        guard fchmod(descriptor, 0o600) == 0 else {
            throw ClaudeSafariHostIPCError.unsafeEndpoint
        }
        try writeAll(data, descriptor: descriptor)
        guard fsync(descriptor) == 0 else { throw ClaudeSafariHostIPCError.ioFailure }
        guard renamex_np(temporaryPath, finalPath, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw ClaudeSafariHostIPCError.messageExists }
            throw ClaudeSafariHostIPCError.ioFailure
        }
        removeTemporary = false
    }

    private static func regularMessageCount(_ path: String, uid: uid_t) throws -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            throw ClaudeSafariHostIPCError.unsafeEndpoint
        }
        var count = 0
        for name in names where isMessageName(name) {
            var metadata = stat()
            let item = path + "/" + name
            guard lstat(item, &metadata) == 0,
                  (metadata.st_mode & S_IFMT) == S_IFREG,
                  metadata.st_uid == uid,
                  (metadata.st_mode & 0o777) == 0o600
            else { throw ClaudeSafariHostIPCError.unsafeEndpoint }
            count += 1
        }
        return count
    }

    static func isMessageName(_ name: String) -> Bool {
        guard name.hasSuffix(".json") else { return false }
        return UUID(uuidString: String(name.dropLast(5))) != nil
    }
}

private final class ClaudeSafariHostMailboxWatcher<Value: Decodable & Sendable>:
    @unchecked Sendable
{
    private let directoryPath: String
    private let validation: @Sendable (Value) -> Bool
    private let handler: @Sendable (Value) -> Void
    private let queue = DispatchQueue(label: "com.silkrd.uma.test.safarihost.ipc")
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var running = false

    init(
        directoryPath: String,
        validation: @escaping @Sendable (Value) -> Bool,
        handler: @escaping @Sendable (Value) -> Void
    ) {
        self.directoryPath = directoryPath
        self.validation = validation
        self.handler = handler
    }

    deinit { stop() }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        try prepareMailboxDirectory(directoryPath, uid: getuid())
        let descriptor = open(directoryPath, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw ClaudeSafariHostIPCError.ioFailure }
        let next = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: queue
        )
        next.setEventHandler { [weak self] in self?.drain() }
        next.setCancelHandler { close(descriptor) }
        source = next
        running = true
        next.resume()
        // Cold-start correctness: a request written before LaunchServices wakes
        // the Host is drained immediately after the listener becomes active.
        queue.async { [weak self] in self?.drain() }
    }

    func stop() {
        lock.lock()
        let active = source
        source = nil
        running = false
        lock.unlock()
        active?.cancel()
    }

    private func drain() {
        lock.lock()
        let shouldDrain = running
        lock.unlock()
        guard shouldDrain,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directoryPath)
        else { return }
        let orderedNames = names
            .filter(ClaudeSafariHostMailbox.isMessageName)
            .sorted { lhs, rhs in
                messageOrder(lhs) < messageOrder(rhs)
            }
        for name in orderedNames {
            guard let value: Value = try? readAndRemove(name: name),
                  validation(value)
            else { continue }
            handler(value)
        }
    }

    /// UUID filenames are correlation identifiers, not sequence numbers. Use
    /// the owner-only file creation/write order so a later cancellation cannot
    /// overtake the request it names when both are present at cold start.
    private func messageOrder(_ name: String) -> (Int64, Int64, String) {
        var metadata = stat()
        let path = directoryPath + "/" + name
        guard lstat(path, &metadata) == 0 else {
            return (Int64.max, Int64.max, name)
        }
        return (
            Int64(metadata.st_mtimespec.tv_sec),
            Int64(metadata.st_mtimespec.tv_nsec),
            name
        )
    }

    private func readAndRemove(name: String) throws -> Value {
        let path = directoryPath + "/" + name
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ClaudeSafariHostIPCError.ioFailure }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == getuid(),
              (metadata.st_mode & 0o777) == 0o600
        else { throw ClaudeSafariHostIPCError.unsafeEndpoint }
        let age = Date().timeIntervalSince(
            Date(timeIntervalSince1970: TimeInterval(metadata.st_mtimespec.tv_sec))
        )
        if age > ClaudeSafariHostIPCContract.maximumMessageAge {
            // A valid UUID name plus this descriptor's owner/mode/type proof
            // is sufficient to retire an expired mailbox message safely. Do
            // not leave a sanitized provider result outside the authoritative
            // anchor store after the consumer has been absent past the bound.
            try unlinkMatching(path: path, descriptor: descriptor, uid: getuid())
            throw ClaudeSafariHostIPCError.unsafeEndpoint
        }
        guard metadata.st_size > 0,
              metadata.st_size <= ClaudeSafariHostIPCContract.maximumMessageBytes
        else { throw ClaudeSafariHostIPCError.unsafeEndpoint }
        let data = try readAll(descriptor: descriptor, count: Int(metadata.st_size))
        try unlinkMatching(path: path, descriptor: descriptor, uid: getuid())
        guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
            throw ClaudeSafariHostIPCError.invalidMessage
        }
        return value
    }
}

private func preparePrivateDirectory(_ path: String, uid: uid_t) throws {
    guard path.hasPrefix("/"), hasNoSymlinkTraversal(path) else {
        throw ClaudeSafariHostIPCError.unsafeEndpoint
    }
    var metadata = stat()
    if lstat(path, &metadata) != 0 {
        guard errno == ENOENT else { throw ClaudeSafariHostIPCError.unsafeEndpoint }
        do {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch { throw ClaudeSafariHostIPCError.ioFailure }
    }
    guard chmod(path, 0o700) == 0,
          lstat(path, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == S_IFDIR,
          metadata.st_uid == uid,
          (metadata.st_mode & 0o777) == 0o700
    else { throw ClaudeSafariHostIPCError.unsafeEndpoint }
}

private func prepareMailboxDirectory(_ path: String, uid: uid_t) throws {
    let root = (path as NSString).deletingLastPathComponent
    try preparePrivateDirectory(root, uid: uid)
    try preparePrivateDirectory(path, uid: uid)
}

private func hasNoSymlinkTraversal(_ path: String) -> Bool {
    var current = "/"
    for component in (path as NSString).pathComponents.dropFirst() {
        current = (current as NSString).appendingPathComponent(component)
        var metadata = stat()
        if lstat(current, &metadata) == 0 {
            if (metadata.st_mode & S_IFMT) == S_IFLNK { return false }
        } else if errno != ENOENT { return false }
    }
    return true
}

private func validateRegularFile(
    descriptor: Int32,
    uid: uid_t,
    expectedSize: off_t
) throws {
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
          (metadata.st_mode & S_IFMT) == S_IFREG,
          metadata.st_uid == uid,
          metadata.st_size == expectedSize
    else { throw ClaudeSafariHostIPCError.unsafeEndpoint }
}

private func writeAll(_ data: Data, descriptor: Int32) throws {
    let okay = data.withUnsafeBytes { bytes -> Bool in
        guard let base = bytes.baseAddress else { return false }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(
                descriptor,
                base.advanced(by: offset),
                bytes.count - offset
            )
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
    guard okay else { throw ClaudeSafariHostIPCError.ioFailure }
}

private func readAll(descriptor: Int32, count: Int) throws -> Data {
    var data = Data(count: count)
    let bytesRead = data.withUnsafeMutableBytes { bytes -> Int in
        guard let base = bytes.baseAddress else { return -1 }
        var offset = 0
        while offset < count {
            let current = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
            guard current > 0 else { return -1 }
            offset += current
        }
        return offset
    }
    guard bytesRead == count else { throw ClaudeSafariHostIPCError.ioFailure }
    return data
}

private func unlinkMatching(path: String, descriptor: Int32, uid: uid_t) throws {
    var opened = stat()
    var current = stat()
    guard fstat(descriptor, &opened) == 0,
          lstat(path, &current) == 0,
          opened.st_dev == current.st_dev,
          opened.st_ino == current.st_ino,
          current.st_uid == uid,
          (current.st_mode & S_IFMT) == S_IFREG,
          unlink(path) == 0
    else { throw ClaudeSafariHostIPCError.unsafeEndpoint }
}
