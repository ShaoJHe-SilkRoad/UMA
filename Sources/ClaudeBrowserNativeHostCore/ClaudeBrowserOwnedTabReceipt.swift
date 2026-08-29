import ClaudeBrowserBridgeProtocol
import Darwin
import Foundation

public enum ClaudeBrowserOwnedTabReceiptState: String, Codable, CaseIterable, Sendable {
    case requestIntentPersisted = "REQUEST_INTENT_PERSISTED"
    case providerCreationPending = "PROVIDER_CREATION_PENDING"
    case providerDocumentDiscovered = "PROVIDER_DOCUMENT_DISCOVERED"
    case providerOwnershipProven = "PROVIDER_OWNERSHIP_PROVEN"
    case providerReady = "PROVIDER_READY"
    case extracting = "EXTRACTING"
    case resultReady = "RESULT_READY"
    case resultDelivered = "RESULT_DELIVERED"
    case cleanupRequested = "CLEANUP_REQUESTED"
    case cleanupConfirmed = "CLEANUP_CONFIRMED"
    case complete = "COMPLETE"
    case cancelled = "CANCELLED"
    case expired = "EXPIRED"
    case failed = "FAILED"

    public var isTerminal: Bool {
        [.complete, .cancelled, .expired, .failed].contains(self)
    }

    public var isUnproven: Bool {
        [.requestIntentPersisted, .providerCreationPending,
         .providerDocumentDiscovered].contains(self)
    }

    public func permitsTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.requestIntentPersisted, .providerCreationPending),
             (.providerCreationPending, .providerDocumentDiscovered),
             (.providerDocumentDiscovered, .providerOwnershipProven),
             (.providerOwnershipProven, .providerDocumentDiscovered),
             (.providerReady, .providerDocumentDiscovered),
             (.providerOwnershipProven, .providerReady),
             (.providerReady, .extracting),
             (.extracting, .resultReady),
             (.resultReady, .resultDelivered),
             (.resultDelivered, .cleanupRequested),
             (.providerOwnershipProven, .cleanupRequested),
             (.providerReady, .cleanupRequested),
             (.extracting, .cleanupRequested),
             (.resultReady, .cleanupRequested),
             (.cleanupRequested, .cleanupConfirmed),
             (.cleanupConfirmed, .complete),
             (.cleanupConfirmed, .cancelled),
             (.cleanupConfirmed, .failed):
            true
        case (let current, .cancelled), (let current, .failed):
            current.isUnproven
        case (let current, .expired):
            current.isUnproven
        default:
            false
        }
    }
}

public struct ClaudeBrowserOwnedTabReceipt: Codable, Equatable, Sendable {
    public static let schemaVersion = 3

    public let schemaVersion: Int
    public let requestID: String
    public let runtimeGenerationID: String
    /// SHA-256 of the request-scoped in-memory nonce, encoded as lowercase hex.
    /// The raw nonce is never persisted or returned by the native handler.
    public let ownershipNonceDigest: String
    public let createdAt: String
    public let expiresAt: String
    public let lifecycleState: ClaudeBrowserOwnedTabReceiptState
    public let revision: Int
    public let providerCandidateTabID: Int?
    public let providerOwnedTabID: Int?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        requestID: String,
        runtimeGenerationID: String,
        ownershipNonceDigest: String,
        createdAt: String,
        expiresAt: String,
        lifecycleState: ClaudeBrowserOwnedTabReceiptState,
        revision: Int,
        providerCandidateTabID: Int? = nil,
        providerOwnedTabID: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.runtimeGenerationID = runtimeGenerationID
        self.ownershipNonceDigest = ownershipNonceDigest
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lifecycleState = lifecycleState
        self.revision = revision
        self.providerCandidateTabID = providerCandidateTabID
        self.providerOwnedTabID = providerOwnedTabID
    }

    public var isStructurallyValid: Bool {
        schemaVersion == Self.schemaVersion
            && UUID(uuidString: requestID) != nil
            && UUID(uuidString: runtimeGenerationID) != nil
            && ownershipNonceDigest.count == 64
            && ownershipNonceDigest.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) }
            && creationDate != nil
            && expiryDate != nil
            && expiryDate! > creationDate!
            && revision > 0
            && (providerCandidateTabID == nil || providerCandidateTabID! >= 0)
            && (providerOwnedTabID == nil || providerOwnedTabID! >= 0)
            && tabShapeIsValid
    }

    /// Accepts both Foundation's whole-second ISO-8601 output and the
    /// fractional-second form produced by JavaScript `Date.toISOString()`.
    /// The parsed value is lifecycle metadata only and is never persisted in
    /// addition to the original content-free timestamp.
    public var creationDate: Date? {
        Self.parseTimestamp(createdAt)
    }

    public var expiryDate: Date? {
        Self.parseTimestamp(expiresAt)
    }

    private var tabShapeIsValid: Bool {
        switch lifecycleState {
        case .requestIntentPersisted:
            providerCandidateTabID == nil && providerOwnedTabID == nil
        case .providerCreationPending:
            providerOwnedTabID == nil
        case .providerDocumentDiscovered:
            providerCandidateTabID != nil && providerOwnedTabID == nil
        case .expired:
            providerOwnedTabID == nil
        case .providerOwnershipProven, .providerReady, .extracting,
             .resultReady, .resultDelivered, .cleanupRequested,
             .cleanupConfirmed, .complete:
            providerOwnedTabID != nil
        case .cancelled, .failed:
            // Pre-proof cancellation/failure has no owned ID; after proof it
            // must pass through cleanup-confirmed and retains the proven ID.
            providerCandidateTabID == nil || providerCandidateTabID! >= 0
        }
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

/// A single content-free ownership receipt for the one in-flight Accuracy
/// Sync tab. It is not browser history and cannot describe any page or user.
public enum ClaudeBrowserOwnedTabReceiptStore {
    private static let lock = NSLock()
    private static let maximumBytes = 4_096

    /// The immutable Safari Host creates the owner-only receipt directory at
    /// startup. The extension may then update only the one bounded receipt;
    /// it never creates an arbitrary alternate storage root.
    public static func prepare(
        endpoint: ClaudeBrowserFileHandoffEndpoint,
        uid: uid_t = getuid()
    ) throws {
        var metadata = stat()
        if lstat(endpoint.directoryPath, &metadata) != 0 {
            guard errno == ENOENT else { throw ClaudeBrowserBridgeError.socketUnsafe }
            do {
                try FileManager.default.createDirectory(
                    atPath: endpoint.directoryPath,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch { throw ClaudeBrowserBridgeError.socketUnavailable }
        } else {
            guard (metadata.st_mode & S_IFMT) == S_IFDIR,
                  metadata.st_uid == uid
            else { throw ClaudeBrowserBridgeError.socketUnsafe }
        }
        guard chmod(endpoint.directoryPath, 0o700) == 0 else {
            throw ClaudeBrowserBridgeError.socketUnsafe
        }
        try validateDirectory(endpoint.directoryPath, uid: uid)
    }

    public static func load(
        endpoint: ClaudeBrowserFileHandoffEndpoint,
        uid: uid_t = getuid()
    ) throws -> ClaudeBrowserOwnedTabReceipt? {
        try lock.withLock {
            try validateDirectory(endpoint.directoryPath, uid: uid)
            let path = receiptPath(endpoint)
            let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            if descriptor < 0 {
                guard errno == ENOENT else { throw ClaudeBrowserBridgeError.socketUnsafe }
                return nil
            }
            defer { close(descriptor) }
            let data = try readData(descriptor: descriptor, uid: uid)
            let decoder = PropertyListDecoder()
            guard let receipt = try? decoder.decode(
                ClaudeBrowserOwnedTabReceipt.self,
                from: data
            ), receipt.isStructurallyValid else {
                throw ClaudeBrowserBridgeError.invalidContract
            }
            return receipt
        }
    }

    public static func save(
        _ receipt: ClaudeBrowserOwnedTabReceipt,
        endpoint: ClaudeBrowserFileHandoffEndpoint,
        uid: uid_t = getuid()
    ) throws {
        guard receipt.isStructurallyValid,
              receipt.lifecycleState == .requestIntentPersisted,
              receipt.revision == 1,
              receipt.providerCandidateTabID == nil,
              receipt.providerOwnedTabID == nil
        else {
            throw ClaudeBrowserBridgeError.invalidContract
        }
        try lock.withLock {
            try validateDirectory(endpoint.directoryPath, uid: uid)
            let path = receiptPath(endpoint)
            if let existing = try loadUnlocked(path: path, uid: uid) {
                guard existing == receipt else {
                    throw ClaudeBrowserBridgeError.invalidContract
                }
                return
            }
            try writeUnlocked(receipt, path: path, uid: uid)
        }
    }

    /// Performs one revisioned compare-and-swap. No caller can skip a state,
    /// replace another request/generation, or mutate a tab identity outside the
    /// transition that first proves it.
    @discardableResult
    public static func transition(
        requestID: String,
        runtimeGenerationID: String,
        ownershipNonceDigest: String,
        expectedRevision: Int,
        expectedState: ClaudeBrowserOwnedTabReceiptState,
        nextState: ClaudeBrowserOwnedTabReceiptState,
        providerCandidateTabID: Int? = nil,
        providerOwnedTabID: Int? = nil,
        endpoint: ClaudeBrowserFileHandoffEndpoint,
        uid: uid_t = getuid()
    ) throws -> ClaudeBrowserOwnedTabReceipt? {
        try lock.withLock {
            try validateDirectory(endpoint.directoryPath, uid: uid)
            let path = receiptPath(endpoint)
            guard let existing = try loadUnlocked(path: path, uid: uid),
                  existing.requestID.lowercased() == requestID.lowercased(),
                  existing.runtimeGenerationID.lowercased()
                    == runtimeGenerationID.lowercased(),
                  existing.ownershipNonceDigest == ownershipNonceDigest,
                  existing.revision == expectedRevision,
                  existing.lifecycleState == expectedState,
                  expectedState.permitsTransition(to: nextState)
            else { return nil }

            let candidate: Int?
            let owned: Int?
            switch nextState {
            case .providerDocumentDiscovered:
                let discoveredCandidate = providerCandidateTabID
                    ?? existing.providerCandidateTabID
                guard let discoveredCandidate, discoveredCandidate >= 0,
                      existing.providerCandidateTabID == nil
                        || existing.providerCandidateTabID == discoveredCandidate,
                      providerOwnedTabID == nil
                else { return nil }
                candidate = discoveredCandidate
                owned = nil
            case .providerOwnershipProven:
                guard let providerOwnedTabID, providerOwnedTabID >= 0,
                      existing.providerCandidateTabID == providerOwnedTabID,
                      providerCandidateTabID == nil
                        || providerCandidateTabID == existing.providerCandidateTabID
                else { return nil }
                candidate = existing.providerCandidateTabID
                owned = providerOwnedTabID
            default:
                guard providerCandidateTabID == nil, providerOwnedTabID == nil else {
                    return nil
                }
                candidate = existing.providerCandidateTabID
                owned = existing.providerOwnedTabID
            }

            let next = ClaudeBrowserOwnedTabReceipt(
                requestID: existing.requestID,
                runtimeGenerationID: existing.runtimeGenerationID,
                ownershipNonceDigest: existing.ownershipNonceDigest,
                createdAt: existing.createdAt,
                expiresAt: existing.expiresAt,
                lifecycleState: nextState,
                revision: existing.revision + 1,
                providerCandidateTabID: candidate,
                providerOwnedTabID: owned
            )
            guard next.isStructurallyValid else { return nil }
            try writeUnlocked(next, path: path, uid: uid)
            return next
        }
    }

    /// Binds `tabs.create`'s result without proving ownership or granting close
    /// authority. If trusted discovery won the ordering race, only the same
    /// candidate can be confirmed; a different ID fails closed.
    @discardableResult
    public static func bindCandidate(
        requestID: String,
        runtimeGenerationID: String,
        ownershipNonceDigest: String,
        expectedRevision: Int,
        providerCandidateTabID: Int,
        endpoint: ClaudeBrowserFileHandoffEndpoint,
        uid: uid_t = getuid()
    ) throws -> ClaudeBrowserOwnedTabReceipt? {
        guard providerCandidateTabID >= 0 else { return nil }
        return try lock.withLock {
            try validateDirectory(endpoint.directoryPath, uid: uid)
            let path = receiptPath(endpoint)
            guard let existing = try loadUnlocked(path: path, uid: uid),
                  existing.requestID.lowercased() == requestID.lowercased(),
                  existing.runtimeGenerationID.lowercased()
                    == runtimeGenerationID.lowercased(),
                  existing.ownershipNonceDigest == ownershipNonceDigest,
                  existing.revision == expectedRevision,
                  existing.lifecycleState == .providerCreationPending
                    || existing.lifecycleState == .providerDocumentDiscovered,
                  existing.providerOwnedTabID == nil
            else { return nil }

            if let bound = existing.providerCandidateTabID {
                return bound == providerCandidateTabID ? existing : nil
            }
            guard existing.lifecycleState == .providerCreationPending else {
                return nil
            }
            let next = ClaudeBrowserOwnedTabReceipt(
                requestID: existing.requestID,
                runtimeGenerationID: existing.runtimeGenerationID,
                ownershipNonceDigest: existing.ownershipNonceDigest,
                createdAt: existing.createdAt,
                expiresAt: existing.expiresAt,
                lifecycleState: existing.lifecycleState,
                revision: existing.revision + 1,
                providerCandidateTabID: providerCandidateTabID
            )
            guard next.isStructurallyValid else { return nil }
            try writeUnlocked(next, path: path, uid: uid)
            return next
        }
    }

    @discardableResult
    public static func remove(
        requestID: String,
        runtimeGenerationID: String,
        ownershipNonceDigest: String,
        expectedRevision: Int,
        terminalState: ClaudeBrowserOwnedTabReceiptState,
        endpoint: ClaudeBrowserFileHandoffEndpoint,
        uid: uid_t = getuid()
    ) throws -> Bool {
        try lock.withLock {
            try validateDirectory(endpoint.directoryPath, uid: uid)
            let path = receiptPath(endpoint)
            // Terminal success requires positive proof that this exact receipt
            // existed and was removed by this compare-and-delete. Treating an
            // already-missing file as success would conceal unexpected receipt
            // loss between cleanup confirmation and durable deletion.
            guard let receipt = try loadUnlocked(path: path, uid: uid) else { return false }
            guard receipt.requestID == requestID,
                  receipt.runtimeGenerationID.lowercased()
                    == runtimeGenerationID.lowercased(),
                  receipt.ownershipNonceDigest == ownershipNonceDigest,
                  receipt.revision == expectedRevision,
                  receipt.lifecycleState == terminalState,
                  terminalState.isTerminal
            else { return false }
            if terminalState == .expired {
                guard receipt.providerOwnedTabID == nil else { return false }
            }
            guard unlink(path) == 0 else { throw ClaudeBrowserBridgeError.socketUnsafe }
            return true
        }
    }

    private static func receiptPath(_ endpoint: ClaudeBrowserFileHandoffEndpoint) -> String {
        endpoint.directoryPath + "/owned-tab-receipt.plist"
    }

    private static func validateDirectory(_ path: String, uid: uid_t) throws {
        var metadata = stat()
        guard lstat(path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR,
              metadata.st_uid == uid,
              (metadata.st_mode & 0o777) == 0o700
        else { throw ClaudeBrowserBridgeError.socketUnsafe }
    }

    private static func validateExistingReceipt(_ path: String, uid: uid_t) throws {
        var metadata = stat()
        if lstat(path, &metadata) != 0 {
            guard errno == ENOENT else { throw ClaudeBrowserBridgeError.socketUnsafe }
            return
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == uid,
              (metadata.st_mode & 0o777) == 0o600,
              metadata.st_size > 0,
              metadata.st_size <= maximumBytes
        else { throw ClaudeBrowserBridgeError.socketUnsafe }
    }

    private static func loadUnlocked(
        path: String,
        uid: uid_t
    ) throws -> ClaudeBrowserOwnedTabReceipt? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            guard errno == ENOENT else { throw ClaudeBrowserBridgeError.socketUnsafe }
            return nil
        }
        defer { close(descriptor) }
        let data = try readData(descriptor: descriptor, uid: uid)
        guard let receipt = try? PropertyListDecoder().decode(
            ClaudeBrowserOwnedTabReceipt.self,
            from: data
        ), receipt.isStructurallyValid else {
            throw ClaudeBrowserBridgeError.invalidContract
        }
        return receipt
    }

    private static func writeUnlocked(
        _ receipt: ClaudeBrowserOwnedTabReceipt,
        path: String,
        uid: uid_t
    ) throws {
        let data = try PropertyListEncoder().encode(receipt)
        guard data.count > 0, data.count <= maximumBytes else {
            throw ClaudeBrowserBridgeError.messageTooLarge
        }
        try validateExistingReceipt(path, uid: uid)
        let temporary = path + "." + UUID().uuidString.lowercased() + ".tmp"
        let descriptor = open(
            temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard descriptor >= 0 else { throw ClaudeBrowserBridgeError.socketUnsafe }
        var removeTemporary = true
        defer {
            close(descriptor)
            if removeTemporary { unlink(temporary) }
        }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == uid,
              fchmod(descriptor, 0o600) == 0
        else { throw ClaudeBrowserBridgeError.socketUnsafe }
        try writeAll(data, descriptor: descriptor)
        guard fsync(descriptor) == 0, rename(temporary, path) == 0 else {
            throw ClaudeBrowserBridgeError.socketWriteFailed
        }
        removeTemporary = false
    }

    private static func readData(descriptor: Int32, uid: uid_t) throws -> Data {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == uid,
              (metadata.st_mode & 0o777) == 0o600,
              metadata.st_size > 0,
              metadata.st_size <= maximumBytes
        else { throw ClaudeBrowserBridgeError.socketUnsafe }
        var data = Data(count: Int(metadata.st_size))
        let total = data.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.read(
                    descriptor,
                    base.advanced(by: offset),
                    buffer.count - offset
                )
                guard count > 0 else { return -1 }
                offset += count
            }
            return offset
        }
        guard total == data.count else { throw ClaudeBrowserBridgeError.socketReadFailed }
        return data
    }

    private static func writeAll(_ data: Data, descriptor: Int32) throws {
        let succeeded = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    buffer.count - offset
                )
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        guard succeeded else { throw ClaudeBrowserBridgeError.socketWriteFailed }
    }
}
