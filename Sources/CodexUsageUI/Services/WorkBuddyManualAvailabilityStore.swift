import Foundation

actor WorkBuddyManualAvailabilityStore {
    enum LoadResult: Equatable, Sendable {
        case missing
        case valid(WorkBuddyManualPersistenceRecord)
        case invalid(WorkBuddyManualValidationError)
    }

    static let maximumRecordBytes = 8 * 1_024

    let fileURL: URL
    let backupURL: URL
    private let fileManager: FileManager
    private(set) var writeCount = 0

    init(
        fileURL: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexUsageMonitor", isDirectory: true)
            .appendingPathComponent("workbuddy-manual-availability.json"),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.backupURL = fileURL.appendingPathExtension("backup")
        self.fileManager = fileManager
    }

    func load() -> LoadResult {
        switch decode(at: fileURL) {
        case let .success(record):
            return .valid(record)
        case let .failure(error as WorkBuddyManualValidationError)
            where error == .unsupportedSchema:
            return .invalid(.unsupportedSchema)
        case .failure:
            switch decode(at: backupURL) {
            case let .success(record):
                return .valid(record)
            case let .failure(error as WorkBuddyManualValidationError)
                where error == .unsupportedSchema:
                return .invalid(.unsupportedSchema)
            case .failure:
                let primaryExists = fileManager.fileExists(atPath: fileURL.path)
                let backupExists = fileManager.fileExists(atPath: backupURL.path)
                return primaryExists || backupExists ? .invalid(.corruptPersistence) : .missing
            }
        }
    }

    @discardableResult
    func save(_ record: WorkBuddyManualPersistenceRecord) throws -> Bool {
        let data = try Self.encoder().encode(record)
        guard data.count <= Self.maximumRecordBytes else {
            throw WorkBuddyManualValidationError.recordTooLarge
        }
        if boundedDataIfPresent(at: fileURL) == data,
           boundedDataIfPresent(at: backupURL) == data {
            return false
        }

        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            try data.write(to: backupURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: backupURL.path
            )
            writeCount += 1
            return true
        } catch {
            throw WorkBuddyManualValidationError.persistenceUnavailable
        }
    }

    @discardableResult
    func clear() throws -> Bool {
        let existingURLs = [fileURL, backupURL].filter {
            fileManager.fileExists(atPath: $0.path)
        }
        guard !existingURLs.isEmpty else { return false }
        do {
            for url in existingURLs {
                try fileManager.removeItem(at: url)
            }
            writeCount += 1
            return true
        } catch {
            throw WorkBuddyManualValidationError.persistenceUnavailable
        }
    }

    func encodedData(for record: WorkBuddyManualPersistenceRecord) throws -> Data {
        try Self.encoder().encode(record)
    }

    private func boundedDataIfPresent(at url: URL) -> Data? {
        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.uint64Value <= UInt64(Self.maximumRecordBytes),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count <= Self.maximumRecordBytes
        else {
            return nil
        }
        return data
    }

    private func decode(at url: URL) -> Result<WorkBuddyManualPersistenceRecord, Error> {
        guard fileManager.fileExists(atPath: url.path) else {
            return .failure(WorkBuddyManualValidationError.corruptPersistence)
        }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? NSNumber,
               fileSize.uint64Value > UInt64(Self.maximumRecordBytes) {
                throw WorkBuddyManualValidationError.recordTooLarge
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= Self.maximumRecordBytes else {
                throw WorkBuddyManualValidationError.recordTooLarge
            }
            return .success(try Self.decoder().decode(
                WorkBuddyManualPersistenceRecord.self,
                from: data
            ))
        } catch {
            return .failure(error)
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
