import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum SectoriumPortableDocumentJournalError: Error, Equatable {
    case unsafePath, invalidRecord, conflictingEvent, unreadableJournal, writeFailed
}

/// One small JSON companion beside the existing internal registry. The Service's
/// operation lock owns cross-process coordination; this lock serializes instance use.
/// Completed entries remain here so a missing IMPORTANT can be rebuilt with history.
public final class SectoriumPortableDocumentJournal: @unchecked Sendable {
    private struct Record: Codable {
        let context: SectoriumPortableDocumentContext
        let event: SectoriumPortableDocumentEvent
        var synchronizedVolumeUUID: UUID?
    }
    private struct State: Codable {
        var version = 1
        var records: [Record] = []
    }
    public let url: URL
    private let lock = NSLock()
    public init(url: URL) { self.url = url }

    public func record(context: SectoriumPortableDocumentContext,
                       event: SectoriumPortableDocumentEvent) throws {
        lock.lock(); defer { lock.unlock() }
        guard SectoriumPortableValidation.context(context), SectoriumPortableValidation.event(event) else {
            throw SectoriumPortableDocumentJournalError.invalidRecord
        }
        var state = try read()
        if let existing = state.records.first(where: { $0.event.id == event.id }) {
            guard existing.event == event, existing.context.parent.physicalID == context.parent.physicalID else {
                throw SectoriumPortableDocumentJournalError.conflictingEvent
            }
            return
        }
        state.records.append(.init(context: context, event: event, synchronizedVolumeUUID: nil))
        try write(state)
    }

    public func events(parentID: String) throws -> [SectoriumPortableDocumentEvent] {
        lock.lock(); defer { lock.unlock() }
        return try read().records.filter { $0.context.parent.physicalID == parentID }.map(\.event)
            .sorted(by: SectoriumPortableValidation.precedes)
    }

    public func pendingCount(parentID: String) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return try read().records.filter {
            $0.context.parent.physicalID == parentID && $0.synchronizedVolumeUUID == nil
        }.count
    }

    /// Retains the chosen document-host identity even after all events are synced.
    /// The caller must re-observe its UUID and current root before using this hint.
    public func latestContext(parentID: String) throws -> SectoriumPortableDocumentContext? {
        lock.lock(); defer { lock.unlock() }
        return try read().records.last { $0.context.parent.physicalID == parentID }?.context
    }

    /// Includes parents whose final volume was removed. These are hints for fresh
    /// Service discovery only; persisted paths never authorize a document write.
    public func pendingContexts() throws -> [SectoriumPortableDocumentContext] {
        lock.lock(); defer { lock.unlock() }
        let state = try read()
        let pendingParents = Set(state.records.filter { $0.synchronizedVolumeUUID == nil }.map { $0.context.parent.physicalID })
        var latest: [String: SectoriumPortableDocumentContext] = [:]
        for record in state.records where pendingParents.contains(record.context.parent.physicalID) {
            latest[record.context.parent.physicalID] = record.context
        }
        return latest.values.sorted { $0.parent.physicalID < $1.parent.physicalID }
    }

    public func synchronize(context: SectoriumPortableDocumentContext,
                            writer: SectoriumPortableDocumentWriting) -> SectoriumPortableDocumentResult {
        lock.lock(); defer { lock.unlock() }
        guard SectoriumPortableValidation.context(context) else {
            return .pending("Portable document parent context is invalid")
        }
        do {
            var state = try read()
            // Import validated historical records before replacing the document. This
            // also retains V1 history if IMPORTANT is later lost and rebuilt locally.
            if let preserved = writer.preservedHistory(context: context) {
                var imported = false
                for event in preserved {
                    guard SectoriumPortableValidation.event(event) else {
                        return .pending("Existing portable history contains an invalid event")
                    }
                    if let prior = state.records.first(where: { $0.event.id == event.id }) {
                        guard prior.event == event, prior.context.parent.physicalID == context.parent.physicalID else {
                            return .pending("Existing portable history conflicts with the local immutable event")
                        }
                    } else {
                        state.records.append(.init(context: context, event: event,
                            synchronizedVolumeUUID: context.parent.documentVolumeUUID))
                        imported = true
                    }
                }
                if imported { try write(state) }
            }
            let indices = state.records.indices.filter { state.records[$0].context.parent.physicalID == context.parent.physicalID }
            let events = indices.map { state.records[$0].event }
            let result = writer.update(context: context, events: events)
            switch result {
            case .pending: return result
            case .updated, .unchanged:
                let changed = indices.contains { state.records[$0].synchronizedVolumeUUID != context.parent.documentVolumeUUID }
                if changed {
                    for index in indices { state.records[index].synchronizedVolumeUUID = context.parent.documentVolumeUUID }
                    try write(state)
                }
                return result
            }
        } catch {
            return .pending("Local documentation history could not be read or acknowledged; retry preserves original events")
        }
    }

    private func validatePath() throws {
        guard url.isFileURL, url.standardizedFileURL.path == url.path,
              url.path == url.resolvingSymlinksInPath().path, url.lastPathComponent != ".",
              url.deletingLastPathComponent().path != "/" else { throw SectoriumPortableDocumentJournalError.unsafePath }
    }
    private func read() throws -> State {
        try validatePath()
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return State() }
        guard let attributes = try? manager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size <= SectoriumPortableDocumentLimits.journalMaximumBytes,
              let bytes = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(State.self, from: bytes), state.version == 1,
              Set(state.records.map { $0.event.id }).count == state.records.count,
              state.records.allSatisfy({ SectoriumPortableValidation.context($0.context) && SectoriumPortableValidation.event($0.event) }) else {
            throw SectoriumPortableDocumentJournalError.unreadableJournal
        }
        return state
    }
    private func write(_ state: State) throws {
        try validatePath()
        let parent = url.deletingLastPathComponent()
        try SecureDirectory.ensure(parent)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(state)
        guard bytes.count <= SectoriumPortableDocumentLimits.journalMaximumBytes else {
            throw SectoriumPortableDocumentJournalError.writeFailed
        }
        #if canImport(Darwin)
        let staged = parent.appendingPathComponent(".sectorium-document-journal-\(UUID().uuidString)")
        let descriptor = open(staged.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw SectoriumPortableDocumentJournalError.writeFailed }
        defer { close(descriptor); _ = unlink(staged.path) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw SectoriumPortableDocumentJournalError.writeFailed }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw SectoriumPortableDocumentJournalError.writeFailed }
        try validatePath()
        guard rename(staged.path, url.path) == 0 else { throw SectoriumPortableDocumentJournalError.writeFailed }
        let directory = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw SectoriumPortableDocumentJournalError.writeFailed }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw SectoriumPortableDocumentJournalError.writeFailed }
        #else
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }
}
