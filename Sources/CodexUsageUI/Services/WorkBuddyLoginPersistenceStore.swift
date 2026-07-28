import Foundation

@MainActor
protocol WorkBuddyLoginPersistenceStoring: AnyObject {
    func load() -> WorkBuddyLoginPersistenceRecord?
    func save(_ record: WorkBuddyLoginPersistenceRecord)
}

@MainActor
final class WorkBuddyLoginPersistenceStore: WorkBuddyLoginPersistenceStoring {
    static let key = "workbuddy.login-assistance.v2"
    static let maximumRecordBytes = 8 * 1_024

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WorkBuddyLoginPersistenceRecord? {
        guard let data = defaults.data(forKey: Self.key),
              data.count <= Self.maximumRecordBytes,
              let record = try? Self.decoder.decode(
                WorkBuddyLoginPersistenceRecord.self,
                from: data
              ),
              record.schemaVersion
                == WorkBuddyLoginPersistenceRecord.currentSchemaVersion
        else {
            return nil
        }
        return record
    }

    func save(_ record: WorkBuddyLoginPersistenceRecord) {
        guard record.schemaVersion
                == WorkBuddyLoginPersistenceRecord.currentSchemaVersion,
              let data = try? Self.encoder.encode(record),
              data.count <= Self.maximumRecordBytes
        else {
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
