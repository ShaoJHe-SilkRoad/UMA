import Foundation
import HESectoriumCore

/// Development volumes whose parent drive disappeared while their image was
/// still attached: the drive was unplugged (or lost power) without Disconnect.
/// Kept on the internal disk so the next Load checks the volume read-only
/// before mounting it, also after AUV or the Mac restarted.
struct SectoriumUncleanRemovalRegistry {
    struct Entry: Codable, Equatable {
        var detectedAt: Date
        /// The development volume itself was mounted, so writes may have been
        /// cut off; otherwise only the image attachment was left behind.
        var volumeWasMounted: Bool
    }

    let url: URL

    func entries() -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return decoded
    }

    func entry(_ profileID: String) -> Entry? { entries()[profileID] }

    @discardableResult
    func mark(_ profileID: String, volumeWasMounted: Bool, at date: Date = Date()) -> Bool {
        var all = entries()
        let previous = all[profileID]
        all[profileID] = .init(detectedAt: date,
                               volumeWasMounted: volumeWasMounted || previous?.volumeWasMounted == true)
        return write(all)
    }

    @discardableResult
    func clear(_ profileID: String) -> Bool {
        var all = entries()
        guard all.removeValue(forKey: profileID) != nil else { return true }
        return write(all)
    }

    private func write(_ all: [String: Entry]) -> Bool {
        guard let data = try? JSONEncoder().encode(all) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
}

/// What `hdiutil info` still lists for an image whose parent drive is gone.
struct SectoriumOrphanedAttachment: Equatable {
    var wholeDisk: String
    var mountPoints: [String]

    /// The attachment of exactly this image path, if macOS still lists one.
    static func find(imagePath: String, in hdiutilInfo: [String: Any]?) -> SectoriumOrphanedAttachment? {
        guard let images = hdiutilInfo?["images"] as? [[String: Any]] else { return nil }
        let matches = images.filter { ($0["image-path"] as? String) == imagePath }
        guard matches.count == 1, let entities = matches[0]["system-entities"] as? [[String: Any]] else { return nil }
        let devices = entities.compactMap { entity -> String? in
            guard let raw = entity["dev-entry"] as? String else { return nil }
            let value = raw.hasPrefix("/dev/") ? String(raw.dropFirst(5)) : raw
            return value.range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) == nil ? nil : value
        }
        // hdiutil lists the image's own whole disk first; the synthesized APFS
        // container disk follows its partitions and goes away with it.
        guard let first = devices.first, devices.count == entities.count,
              let range = first.range(of: #"^disk[0-9]+"#, options: .regularExpression) else { return nil }
        let whole = String(first[range])
        let mounts = entities.compactMap { ($0["mount-point"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return .init(wholeDisk: whole, mountPoints: mounts)
    }
}

extension MacStorageBackend {
    /// `diskutil verifyVolume` runs `fsck_apfs -n` and reports problems
    /// without repairing. Only exit 0 is a pass; anything else, including a
    /// timeout, is not.
    static func verifyVolumePassed(_ outcome: CommandOutcome) -> Bool { outcome.exitCode == 0 }
}

/// A development volume recorded in a drive's IMPORTANT.md, with its paths
/// moved to where the drive is mounted on this Mac.
public struct SectoriumDocumentedVolume: Equatable, Sendable {
    public let deviceID: String
    public let driveName: String
    public let driveVolumeUUID: UUID
    public let name: String
    public let volumeUUID: UUID?
    public let logicalCapacityBytes: UInt64?
    public let imagePath: String
    public let mountPoint: String
}
