import Foundation
import HESectoriumCore

/// A disk image macOS has attached, as `hdiutil info` reports it.
struct SectoriumAttachedImage: Equatable, Sendable {
    let path: String
    let wholeDisk: String
    /// The `diskimages-helper` process that serves this image. It keeps the
    /// image's own file open, so `lsof` lists it on the drive holding that file,
    /// and it exits when the image is detached.
    let helperPID: Int32?
    let mountPoints: [String]
    let volumeNodes: [String]

    var displayName: String {
        mountPoints.first.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? URL(fileURLWithPath: path).lastPathComponent
    }

    /// The image's file lies inside `root` (a mounted volume or folder).
    func isStored(under root: String) -> Bool {
        let base = SectoriumAttachedImages.canonical(root)
        let file = SectoriumAttachedImages.canonical(path)
        return file != base && file.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}

enum SectoriumAttachedImages {
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func parse(_ info: [String: Any]?) -> [SectoriumAttachedImage]? {
        guard let rows = info?["images"] as? [[String: Any]] else { return nil }
        var images: [SectoriumAttachedImage] = []
        for row in rows {
            guard let path = row["image-path"] as? String, !path.isEmpty,
                  let entities = row["system-entities"] as? [[String: Any]] else { return nil }
            let nodes = entities.compactMap { entity -> String? in
                guard let raw = entity["dev-entry"] as? String else { return nil }
                let node = raw.hasPrefix("/dev/") ? String(raw.dropFirst(5)) : raw
                return node.range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) == nil ? nil : node
            }
            // hdiutil lists the image's own whole disk first.
            guard nodes.count == entities.count, let first = nodes.first,
                  let range = first.range(of: #"^disk[0-9]+"#, options: .regularExpression) else { return nil }
            let mounts = entities.compactMap { ($0["mount-point"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            let pid = (row["hdid-pid"] as? NSNumber).map { Int32(truncating: $0) }
            images.append(.init(path: path, wholeDisk: String(first[range]), helperPID: pid,
                                mountPoints: mounts, volumeNodes: nodes.filter { $0.contains("s") }))
        }
        return images
    }

    static func read(runner: HESectoriumCommandRunning, cwd: URL) -> [SectoriumAttachedImage]? {
        let outcome = runner.run("/usr/bin/hdiutil", ["info", "-plist"], cwd: cwd)
        guard outcome.succeeded, let start = outcome.detail.range(of: "<?xml") ?? outcome.detail.range(of: "<plist"),
              let end = outcome.detail.range(of: "</plist>", range: start.lowerBound..<outcome.detail.endIndex),
              let data = String(outcome.detail[start.lowerBound..<end.upperBound]).data(using: .utf8),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        else { return nil }
        return parse(plist)
    }

    /// Images whose file lies inside another listed image's mounted volume come
    /// before that image: an image cannot be detached while one stored on it is
    /// still attached (macOS's diskimagesiod refuses the unmount).
    static func innermostFirst(_ images: [SectoriumAttachedImage]) -> [SectoriumAttachedImage] {
        var remaining = images.sorted { $0.wholeDisk < $1.wholeDisk }
        var ordered: [SectoriumAttachedImage] = []
        while !remaining.isEmpty {
            // An image can go once nothing still remaining is stored inside it.
            let index = remaining.firstIndex { host in
                !remaining.contains { other in other != host && host.mountPoints.contains { other.isStored(under: $0) } }
            } ?? 0
            ordered.append(remaining.remove(at: index))
        }
        return ordered
    }

    /// Helper processes of the given images. Releasing those images is part of
    /// the operation, so their helpers are not someone else using the drive.
    static func helperPIDs(of images: [SectoriumAttachedImage]) -> Set<Int32> {
        Set(images.compactMap(\.helperPID))
    }
}

extension SectoriumActivityReport {
    /// The report without the given processes; busy only if anyone is left.
    func excluding(_ processIDs: Set<Int32>) -> SectoriumActivityReport {
        guard !processIDs.isEmpty, case .busy = assessment else { return self }
        let kept = processes.filter { !processIDs.contains($0.processID) }
        return .init(assessment: kept.isEmpty ? .noVisibleOccupancy : .busy(processIDs: kept.map(\.processID)),
                     processes: kept)
    }

    /// Both reports' processes; incomplete wins, then busy.
    func merged(with other: SectoriumActivityReport) -> SectoriumActivityReport {
        if case .incomplete = assessment { return self }
        if case .incomplete = other.assessment { return other }
        var byID: [Int32: SectoriumActivityProcess] = [:]
        for process in processes + other.processes where byID[process.processID] == nil { byID[process.processID] = process }
        let all = byID.values.sorted { $0.processID < $1.processID }
        return .init(assessment: all.isEmpty ? .noVisibleOccupancy : .busy(processIDs: all.map(\.processID)), processes: all)
    }
}
