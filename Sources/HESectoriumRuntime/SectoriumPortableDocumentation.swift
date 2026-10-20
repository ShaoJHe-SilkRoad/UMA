import Foundation
import HESectoriumCore
#if canImport(Darwin)
import Darwin
#endif

public enum SectoriumPortableDocumentResult: Equatable, Sendable {
    case updated
    case unchanged
    case pending(String)
}

/// The document is an aid for a person moving a registered drive. It is never a
/// source of storage identity, configuration, or executable instructions.
public protocol SectoriumPortableDocumentWriting: AnyObject {
    func update(profile: SectoriumDevelopmentProfile, event: String) -> SectoriumPortableDocumentResult
    func update(profiles: [SectoriumDevelopmentProfile], changedProfileID: String,
                event: String) -> SectoriumPortableDocumentResult
    func update(context: SectoriumPortableDocumentContext,
                events: [SectoriumPortableDocumentEvent]) -> SectoriumPortableDocumentResult
    func verifiedDocumentURL(context: SectoriumPortableDocumentContext) -> URL?
    func preservedHistory(context: SectoriumPortableDocumentContext) -> [SectoriumPortableDocumentEvent]?
}

public extension SectoriumPortableDocumentWriting {
    func update(context: SectoriumPortableDocumentContext,
                events: [SectoriumPortableDocumentEvent]) -> SectoriumPortableDocumentResult {
        .pending("Portable document writer does not support durable parent history")
    }
    func verifiedDocumentURL(context: SectoriumPortableDocumentContext) -> URL? { nil }
    func preservedHistory(context: SectoriumPortableDocumentContext) -> [SectoriumPortableDocumentEvent]? { nil }
    /// Existing fixture writers have a single-profile contract. They must not silently
    /// report success for a parent with multiple registered development volumes.
    func update(profiles: [SectoriumDevelopmentProfile], changedProfileID: String,
                event: String) -> SectoriumPortableDocumentResult {
        guard profiles.count == 1, let profile = profiles.first, profile.id == changedProfileID else {
            return .pending("Portable document writer cannot represent every registered volume")
        }
        return update(profile: profile, event: event)
    }
}

public struct SectoriumPortableHostFacts: Equatable, Sendable {
    public let filesystem: String?
    public let totalBytes: UInt64?
    public let availableBytes: UInt64?
    public init(filesystem: String?, totalBytes: UInt64?, availableBytes: UInt64?) {
        self.filesystem = filesystem; self.totalBytes = totalBytes; self.availableBytes = availableBytes
    }
}

/// Kept separate from the storage controller so fixture tests can refuse a host
/// or a write without calling diskutil or touching a real mounted volume.
public protocol SectoriumPortableDocumentFileSystem: AnyObject {
    func isVerifiedWritableHost(_ root: URL, volumeUUID: UUID) -> Bool
    func isVerifiedReadableHost(_ root: URL, volumeUUID: UUID) -> Bool
    func hostFacts(_ root: URL) -> SectoriumPortableHostFacts?
    func readRegularFile(_ url: URL, limit: Int) throws -> Data?
    func commit(_ data: Data, to url: URL, expectedPrior: Data?) throws
}

public extension SectoriumPortableDocumentFileSystem {
    func hostFacts(_ root: URL) -> SectoriumPortableHostFacts? { nil }
    func isVerifiedReadableHost(_ root: URL, volumeUUID: UUID) -> Bool {
        isVerifiedWritableHost(root, volumeUUID: volumeUUID)
    }
}

public final class SystemSectoriumPortableDocumentFileSystem: SectoriumPortableDocumentFileSystem {
    private let runner: HESectoriumCommandRunning
    private let fileManager: FileManager
    // Test-only hook for a competing replacement at the final commit boundary.
    var beforeAtomicReplace: (() -> Void)?
    var forcePortableCommitForTesting = false
    var afterPortableDisplacement: (() throws -> Void)?
    var afterExclusiveCreate: ((URL) throws -> Void)?

    public init(runner: HESectoriumCommandRunning = ProcessCommandRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func isVerifiedWritableHost(_ root: URL, volumeUUID: UUID) -> Bool {
        isVerifiedHost(root, volumeUUID: volumeUUID, requiringWrite: true)
    }
    public func isVerifiedReadableHost(_ root: URL, volumeUUID: UUID) -> Bool {
        isVerifiedHost(root, volumeUUID: volumeUUID, requiringWrite: false)
    }
    private func isVerifiedHost(_ root: URL, volumeUUID: UUID, requiringWrite: Bool) -> Bool {
        guard root.isFileURL, root.standardizedFileURL.path == root.resolvingSymlinksInPath().path,
              !requiringWrite || fileManager.isWritableFile(atPath: root.path),
              let attributes = try? fileManager.attributesOfItem(atPath: root.path),
              (attributes[.type] as? FileAttributeType) == .typeDirectory else { return false }
        let outcome = runner.run("/usr/sbin/diskutil", ["info", "-plist", root.path], cwd: root)
        guard outcome.succeeded, let bytes = outcome.detail.data(using: .utf8),
              let info = (try? PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)) as? [String: Any],
              info["MountPoint"] as? String == root.path,
              let rawUUID = (info["VolumeUUID"] as? String) ?? (info["APFSVolumeUUID"] as? String),
              UUID(uuidString: rawUUID) == volumeUUID,
              !requiringWrite || ((info["WritableVolume"] as? Bool) == true &&
                  (info["ReadOnlyVolume"] as? Bool) != true) else { return false }
        return true
    }

    public func hostFacts(_ root: URL) -> SectoriumPortableHostFacts? {
        guard root.isFileURL, root.standardizedFileURL.path == root.resolvingSymlinksInPath().path,
              let values = try? root.resourceValues(forKeys: [
                  .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey,
                  .volumeAvailableCapacityKey
              ]) else { return nil }
        return .init(filesystem: values.volumeLocalizedFormatDescription,
                     totalBytes: values.volumeTotalCapacity.flatMap { $0 >= 0 ? UInt64($0) : nil },
                     availableBytes: values.volumeAvailableCapacity.flatMap { $0 >= 0 ? UInt64($0) : nil })
    }

    public func readRegularFile(_ url: URL, limit: Int) throws -> Data? {
        #if canImport(Darwin)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw PortableDocumentError.unsafeFile
        }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              status.st_size >= 0, status.st_size <= limit else { throw PortableDocumentError.unsafeFile }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 { throw PortableDocumentError.unsafeFile }
            if count == 0 { break }
            guard data.count + count <= limit else { throw PortableDocumentError.unsafeFile }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
        #else
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              let size = attributes[.size] as? Int, size <= limit else { throw PortableDocumentError.unsafeFile }
        return try Data(contentsOf: url)
        #endif
    }

    public func commit(_ data: Data, to url: URL, expectedPrior: Data?) throws {
        #if canImport(Darwin)
        let parent = url.deletingLastPathComponent()
        guard parent.standardizedFileURL.path == parent.resolvingSymlinksInPath().path else {
            throw PortableDocumentError.changedBeforeWrite
        }
        if forcePortableCommitForTesting || !supportsAtomicDocumentCommit(parent) {
            try commitPortable(data, to: url, expectedPrior: expectedPrior)
            return
        }
        let current = try readRegularFile(url, limit: SectoriumPortableDocumentLimits.maximumBytes)
        guard current == expectedPrior else {
            throw PortableDocumentError.changedBeforeWrite
        }
        // A retained exact preimage makes an interrupted replacement recoverable.
        // Creation uses hard-link exclusion, so a newly appearing foreign document is never replaced.
        if let expectedPrior {
            let recovery = parent.appendingPathComponent(".IMPORTANT.md.auv-recovery-\(UUID().uuidString)")
            try writeExclusive(expectedPrior, to: recovery)
            // The preimage's directory entry must be durable before replacing the live file.
            try syncDirectory(parent)
        }
        let staged = parent.appendingPathComponent(".IMPORTANT.md.auv-next-\(UUID().uuidString)")
        try writeExclusive(data, to: staged)
        var removeStaged = true
        defer { if removeStaged { _ = unlink(staged.path) } }
        try syncDirectory(parent)
        let checked = try readRegularFile(url, limit: SectoriumPortableDocumentLimits.maximumBytes)
        guard checked == expectedPrior else {
            throw PortableDocumentError.changedBeforeWrite
        }
        if expectedPrior == nil {
            guard link(staged.path, url.path) == 0 else { throw PortableDocumentError.changedBeforeWrite }
        } else {
            beforeAtomicReplace?()
            // Swap retains whichever inode is actually at the destination. If another
            // writer replaced it after our check, put that inode back rather than
            // silently discarding it with an unconditional rename.
            guard renamex_np(staged.path, url.path, UInt32(RENAME_SWAP)) == 0 else {
                throw PortableDocumentError.changedBeforeWrite
            }
            removeStaged = false
            let displaced = try? readRegularFile(staged, limit: SectoriumPortableDocumentLimits.maximumBytes)
            guard displaced == expectedPrior else {
                if renamex_np(staged.path, url.path, UInt32(RENAME_SWAP)) == 0 {
                    removeStaged = true
                    try syncDirectory(parent)
                }
                // On failed rollback, the displaced file stays in the staged path
                // for manual recovery; never delete bytes we did not create.
                throw PortableDocumentError.changedBeforeWrite
            }
            removeStaged = true
        }
        try syncDirectory(parent)
        guard try readRegularFile(url, limit: SectoriumPortableDocumentLimits.maximumBytes) == data else { throw PortableDocumentError.writeFailed }
        #else
        let current = try readRegularFile(url, limit: SectoriumPortableDocumentLimits.maximumBytes)
        guard current == expectedPrior else {
            throw PortableDocumentError.changedBeforeWrite
        }
        try data.write(to: url, options: .atomic)
        #endif
    }

    #if canImport(Darwin)
    private struct PortableTransaction: Codable {
        let stagedName: String
        let preimageName: String?
        let displacedName: String
    }

    private func supportsAtomicDocumentCommit(_ root: URL) -> Bool {
        struct Capabilities { var length: UInt32 = 0; var value = vol_capabilities_attr_t() }
        var request = attrlist()
        request.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        request.volattr = UInt32(ATTR_VOL_CAPABILITIES)
        var result = Capabilities()
        guard getattrlist(root.path, &request, &result, MemoryLayout<Capabilities>.size, 0) == 0 else { return false }
        let format = UInt32(VOL_CAP_FMT_HARDLINKS), swap = UInt32(VOL_CAP_INT_RENAME_SWAP)
        return result.value.valid.0 & format != 0 && result.value.capabilities.0 & format != 0
            && result.value.valid.1 & swap != 0 && result.value.capabilities.1 & swap != 0
    }

    // ExFAT supports neither hard links nor exclusive/swap rename. Its document
    // transaction keeps exact preimages and only publishes through O_EXCL. There
    // is a short absent-name window during replacement, recoverable on retry;
    // this is deliberately not advertised as an atomic whole-file replacement.
    private func commitPortable(_ data: Data, to target: URL, expectedPrior: Data?) throws {
        let root = target.deletingLastPathComponent()
        // Recovery must not mistake another live writer's journal for a crash.
        // The stable lock name is never unlinked; flock releases on close/crash.
        let lockURL = root.appendingPathComponent(".IMPORTANT.md.auv-lock")
        let lock = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, mode_t(0o600))
        guard lock >= 0 else { throw PortableDocumentError.writeFailed }
        defer { close(lock) }
        var lockStatus = stat()
        guard fstat(lock, &lockStatus) == 0,
              (lockStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw PortableDocumentError.writeFailed }
        let recordURL = root.appendingPathComponent(".IMPORTANT.md.auv-transaction.json")
        try recoverPortableTransaction(target: target, recordURL: recordURL)
        guard try readRegularFile(target, limit: SectoriumPortableDocumentLimits.maximumBytes) == expectedPrior else {
            throw PortableDocumentError.changedBeforeWrite
        }
        let token = UUID().uuidString
        let record = PortableTransaction(stagedName: ".IMPORTANT.md.auv-next-\(token)",
            preimageName: expectedPrior == nil ? nil : ".IMPORTANT.md.auv-recovery-\(token)",
            displacedName: ".IMPORTANT.md.auv-displaced-\(token)")
        if let expectedPrior, let name = record.preimageName {
            try writeExclusive(expectedPrior, to: root.appendingPathComponent(name))
        }
        let staged = root.appendingPathComponent(record.stagedName)
        try writeExclusive(data, to: staged)
        try syncDirectory(root)
        // An existing or competing transaction is never replaced.
        try writeExclusive(try JSONEncoder().encode(record), to: recordURL)
        try syncDirectory(root)
        if let expectedPrior {
            beforeAtomicReplace?()
            let displaced = root.appendingPathComponent(record.displacedName)
            guard !fileManager.fileExists(atPath: displaced.path), rename(target.path, displaced.path) == 0 else {
                throw PortableDocumentError.changedBeforeWrite
            }
            try syncDirectory(root)
            guard try readRegularFile(displaced, limit: SectoriumPortableDocumentLimits.maximumBytes) == expectedPrior else {
                // A racing replacement is retained byte-for-byte and restored
                // only if no further writer has already created the target.
                try recoverPortableTransaction(target: target, recordURL: recordURL)
                throw PortableDocumentError.changedBeforeWrite
            }
        }
        try afterPortableDisplacement?()
        try writeExclusive(data, to: target, removePartialOnFailure: false)
        try syncDirectory(root)
        guard try readRegularFile(target, limit: SectoriumPortableDocumentLimits.maximumBytes) == data else {
            throw PortableDocumentError.changedBeforeWrite
        }
        try finishPortableTransaction(recordURL: recordURL, staged: staged)
    }

    private func recoverPortableTransaction(target: URL, recordURL: URL) throws {
        guard let encoded = try readRegularFile(recordURL, limit: 4_096) else { return }
        let record = try JSONDecoder().decode(PortableTransaction.self, from: encoded)
        func managedName(_ name: String, prefix: String) -> Bool {
            name.hasPrefix(prefix) && UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
        }
        guard managedName(record.stagedName, prefix: ".IMPORTANT.md.auv-next-"),
              managedName(record.displacedName, prefix: ".IMPORTANT.md.auv-displaced-"),
              record.preimageName.map({ managedName($0, prefix: ".IMPORTANT.md.auv-recovery-") }) ?? true else {
            throw PortableDocumentError.unsafeFile
        }
        let root = target.deletingLastPathComponent(), staged = root.appendingPathComponent(record.stagedName)
        guard let next = try readRegularFile(staged, limit: SectoriumPortableDocumentLimits.maximumBytes) else {
            throw PortableDocumentError.unsafeFile
        }
        let original = try record.preimageName.flatMap {
            try readRegularFile(root.appendingPathComponent($0), limit: SectoriumPortableDocumentLimits.maximumBytes)
        }
        let current = try readRegularFile(target, limit: SectoriumPortableDocumentLimits.maximumBytes)
        if current == next || (original != nil && current == original) {
            try finishPortableTransaction(recordURL: recordURL, staged: staged)
            return
        }
        guard current == nil else {
            // A foreign/newer file, including an incomplete write, is kept with
            // its preimage and transaction. Never truncate it to manufacture success.
            throw PortableDocumentError.changedBeforeWrite
        }
        if let displaced = try readRegularFile(root.appendingPathComponent(record.displacedName),
                                              limit: SectoriumPortableDocumentLimits.maximumBytes) {
            try writeExclusive(displaced, to: target, removePartialOnFailure: false)
        } else if record.preimageName == nil {
            try writeExclusive(next, to: target, removePartialOnFailure: false)
        } else {
            // No displaced inode proves that we removed this name.
            throw PortableDocumentError.changedBeforeWrite
        }
        try syncDirectory(root)
        try finishPortableTransaction(recordURL: recordURL, staged: staged)
    }

    private func finishPortableTransaction(recordURL: URL, staged: URL) throws {
        guard unlink(recordURL.path) == 0 else { throw PortableDocumentError.writeFailed }
        try syncDirectory(recordURL.deletingLastPathComponent())
        _ = unlink(staged.path)
    }

    private func writeExclusive(_ data: Data, to url: URL, removePartialOnFailure: Bool = true) throws {
        let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode_t(0o644))
        guard descriptor >= 0 else { throw PortableDocumentError.writeFailed }
        var completed = false
        defer {
            close(descriptor)
            // The public name may already belong to a racing editor. Retain
            // failed public writes with the journal/preimage instead of unlinking.
            if !completed && removePartialOnFailure { _ = unlink(url.path) }
        }
        try afterExclusiveCreate?(url)
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeBytes { raw in
                write(descriptor, raw.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            guard count > 0 else { throw PortableDocumentError.writeFailed }
            offset += count
        }
        guard fsync(descriptor) == 0 else { throw PortableDocumentError.writeFailed }
        completed = true
    }

    private func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw PortableDocumentError.writeFailed }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw PortableDocumentError.writeFailed }
    }
    #endif
}

private enum PortableDocumentError: Error {
    case unsafeFile, changedBeforeWrite, writeFailed
}

public final class SectoriumPortableDocumentWriter: SectoriumPortableDocumentWriting {
    let fileSystem: SectoriumPortableDocumentFileSystem
    let now: () -> Date
    private static let historyBegin = "<!-- AUV-SECTORIUM-HISTORY:BEGIN -->"
    private static let historyEnd = "<!-- AUV-SECTORIUM-HISTORY:END -->"
    private static let notesBegin = "<!-- AUV-SECTORIUM-NOTES:BEGIN -->"
    private static let notesEnd = "<!-- AUV-SECTORIUM-NOTES:END -->"
    private static let allowedEvents: Set<String> = ["registered", "validated", "loaded", "unloaded", "ejected", "reconnected"]

    private struct Fields {
        let profileID: String
        let hostUUID: String
        let devUUID: String
        let imageFormat: String
        let encryption: String
        let caseSensitivity: String
    }

    public init(fileSystem: SectoriumPortableDocumentFileSystem = SystemSectoriumPortableDocumentFileSystem(),
                now: @escaping () -> Date = Date.init) {
        self.fileSystem = fileSystem
        self.now = now
    }

    public func update(profile: SectoriumDevelopmentProfile, event: String) -> SectoriumPortableDocumentResult {
        guard Self.allowedEvents.contains(event), let profileID = UUID(uuidString: profile.id),
              profile.imagePath.hasPrefix(profile.backingMountPoint + "/"),
              !profile.backingMountPoint.isEmpty else {
            return .pending("Portable document requires a valid registered profile")
        }
        let root = URL(fileURLWithPath: profile.backingMountPoint, isDirectory: true).standardizedFileURL
        guard fileSystem.isVerifiedWritableHost(root, volumeUUID: profile.backingVolumeUUID) else {
            return .pending("Portable document host volume is not verified writable")
        }
        let target = root.appendingPathComponent("IMPORTANT.md")
        let marker = "<!-- AUV-SECTORIUM-IMPORTANT:v1 profile=\(profileID.uuidString) -->"
        do {
            let old = try fileSystem.readRegularFile(target, limit: 65_536)
            var priorHistory: [String] = []
            var notes = "Add your own notes here. / 在此填写自己的备注。"
            if let old {
                guard let text = String(data: old, encoding: .utf8),
                      text.hasPrefix(marker + "\n"),
                      let history = Self.section(text, begin: Self.historyBegin, end: Self.historyEnd),
                      let existingNotes = Self.section(text, begin: Self.notesBegin, end: Self.notesEnd) else {
                    return .pending("An unrelated or malformed IMPORTANT.md already exists")
                }
                let lines = history.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                guard lines.count <= 12, lines.allSatisfy(Self.isManagedHistoryLine) else {
                    return .pending("Portable document history requires review")
                }
                guard let previousFields = Self.fields(in: text),
                      previousFields.profileID == profileID.uuidString,
                      previousFields.hostUUID == profile.backingVolumeUUID.uuidString else {
                    return .pending("Portable document identity requires review")
                }
                // Only a byte-exact generated scaffold is ours to replace. In particular,
                // additions after NOTES:END or between managed sections must stay untouched.
                let previousContent = Self.content(marker: marker, fields: previousFields,
                                                   history: history, notes: existingNotes)
                guard Data(previousContent.utf8) == old else {
                    return .pending("Portable document contains edits outside the notes section")
                }
                priorHistory = Array(lines.suffix(12))
                notes = existingNotes
            }
            let stamp = ISO8601DateFormatter().string(from: now())
            let entry = "- \(stamp) \(event)"
            let history = (priorHistory.last == entry
                ? priorHistory : Array((priorHistory + [entry]).suffix(12))).joined(separator: "\n")
            let content = Self.content(marker: marker,
                fields: Self.fields(for: profile, profileID: profileID),
                history: history, notes: notes)
            let output = Data(content.utf8)
            guard output.count <= 65_536 else { return .pending("Portable document exceeds the safe size limit") }
            if output == old { return .unchanged }
            guard fileSystem.isVerifiedWritableHost(root, volumeUUID: profile.backingVolumeUUID) else {
                return .pending("Portable document host volume changed before write")
            }
            try fileSystem.commit(output, to: target, expectedPrior: old)
            return .updated
        } catch {
            return .pending("Portable document write is pending; storage operation is unaffected")
        }
    }

    private static func content(marker: String, fields: Fields, history: String, notes: String) -> String {
        """
            \(marker)
            # Development volume / 开发盘

            This drive contains a managed development image. Use the AUV app to verify identity, load, and safely eject it. Do not detach an image or unplug the drive while writes may be active.
            此磁盘包含已管理的开发盘镜像。请使用 AUV 核验身份、加载并安全弹出；可能仍有写入时，请勿分离镜像或拔出磁盘。

            Profile ID / 配置标识: \(fields.profileID)
            Host volume UUID / 宿主宗卷标识: \(fields.hostUUID)
            Development volume UUID / 开发宗卷标识: \(fields.devUUID)
            Image format / 镜像格式: \(fields.imageFormat)
            Encryption / 加密: \(fields.encryption)
            Case sensitivity / 大小写敏感: \(fields.caseSensitivity)

            The app's registered configuration is authoritative. This file is only a portable guide and never grants permission to mount, eject, or change the disk.
            以应用中的已登记配置为准；本文件仅供随盘阅读，不授予挂载、弹出或修改磁盘的权限。

            \(Self.historyBegin)
            \(history)
            \(Self.historyEnd)

            \(Self.notesBegin)
            \(notes)
            \(Self.notesEnd)
            """ + "\n"
    }

    private static func section(_ text: String, begin: String, end: String) -> String? {
        guard let start = text.range(of: begin + "\n"),
              let finish = text.range(of: "\n" + end, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<finish.lowerBound])
    }

    /// Accept only the exact V1 scaffold we generated. Notes are preserved byte-for-byte.
    func legacyPortableDocument(_ data: Data, hostUUID: UUID)
        -> (events: [SectoriumPortableDocumentEvent], notes: String)? {
        guard let text = String(data: data, encoding: .utf8),
              let fields = Self.fields(in: text),
              UUID(uuidString: fields.profileID)?.uuidString == fields.profileID,
              fields.hostUUID == hostUUID.uuidString,
              let history = Self.section(text, begin: Self.historyBegin, end: Self.historyEnd),
              let notes = Self.section(text, begin: Self.notesBegin, end: Self.notesEnd) else { return nil }
        let marker = "<!-- AUV-SECTORIUM-IMPORTANT:v1 profile=\(fields.profileID) -->"
        guard Self.content(marker: marker, fields: fields, history: history, notes: notes) == text else { return nil }
        let lines = history.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count <= 12, lines.allSatisfy(Self.isManagedHistoryLine) else { return nil }
        let events = lines.enumerated().compactMap { index, line -> SectoriumPortableDocumentEvent? in
            let parts = line.dropFirst(2).split(separator: " ")
            guard parts.count == 2, let date = ISO8601DateFormatter().date(from: String(parts[0])) else { return nil }
            return .init(id: "legacy-v1:\(fields.profileID):\(index):\(parts[0]):\(parts[1])",
                         occurredAt: date, profileID: fields.profileID, kind: String(parts[1]),
                         detail: "Legacy record / 旧记录")
        }
        guard events.count == lines.count else { return nil }
        return (events, notes)
    }
    private static func fields(for profile: SectoriumDevelopmentProfile, profileID: UUID) -> Fields {
        Fields(profileID: profileID.uuidString, hostUUID: profile.backingVolumeUUID.uuidString,
               devUUID: profile.devUUID?.uuidString ?? "pending / 待核验",
               imageFormat: profile.imageFormat == "UDSB" ? "UDSB" : "unknown / 未知",
               encryption: display(profile.encrypted), caseSensitivity: display(profile.caseSensitive))
    }
    private static func fields(in text: String) -> Fields? {
        guard let historyStart = text.range(of: historyBegin) else { return nil }
        let header = String(text[..<historyStart.lowerBound])
        guard let profileID = lineValue("Profile ID / 配置标识", in: header),
              let hostUUID = lineValue("Host volume UUID / 宿主宗卷标识", in: header),
              let devUUID = lineValue("Development volume UUID / 开发宗卷标识", in: header),
              let imageFormat = lineValue("Image format / 镜像格式", in: header),
              let encryption = lineValue("Encryption / 加密", in: header),
              let caseSensitivity = lineValue("Case sensitivity / 大小写敏感", in: header),
              validUUIDOrPending(devUUID),
              ["UDSB", "unknown / 未知"].contains(imageFormat),
              ["yes / 是", "no / 否", "unknown / 未知"].contains(encryption),
              ["yes / 是", "no / 否", "unknown / 未知"].contains(caseSensitivity) else {
            return nil
        }
        return Fields(profileID: profileID, hostUUID: hostUUID, devUUID: devUUID,
                      imageFormat: imageFormat, encryption: encryption,
                      caseSensitivity: caseSensitivity)
    }
    private static func lineValue(_ label: String, in header: String) -> String? {
        let prefix = label + ": "
        let matches = header.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix(prefix) }
        guard matches.count == 1 else { return nil }
        return String(matches[0].dropFirst(prefix.count))
    }
    private static func validUUIDOrPending(_ value: String) -> Bool {
        value == "pending / 待核验" || UUID(uuidString: value)?.uuidString == value
    }
    private static func display(_ value: Bool?) -> String {
        switch value { case .some(true): "yes / 是"; case .some(false): "no / 否"; case .none: "unknown / 未知" }
    }
    private static func isManagedHistoryLine(_ value: String) -> Bool {
        guard value.count <= 120, value.hasPrefix("- ") else { return false }
        let parts = value.dropFirst(2).split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, allowedEvents.contains(String(parts[1])) else { return false }
        return ISO8601DateFormatter().date(from: String(parts[0])) != nil
    }
}
