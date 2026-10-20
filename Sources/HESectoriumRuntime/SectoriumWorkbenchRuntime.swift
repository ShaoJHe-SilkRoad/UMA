import Foundation

public struct SectoriumStopConfirmation: Equatable, Sendable {
    public let profileID: String
    public let deviceID: String
    public let backingVolumeUUID: UUID
    public let devVolumeUUID: UUID
    public let imagePath: String
    public let observedAt: Date

    public func permits(_ profile: SectoriumDevelopmentProfile, _ observation: StorageObservation,
                        knownWritersClosed: Bool, now: Date = Date()) -> Bool {
        knownWritersClosed && profile.id == profileID && profile.deviceID == deviceID
            && profile.backingVolumeUUID == backingVolumeUUID && profile.imagePath == imagePath
            && observation.outer.uuid == backingVolumeUUID && observation.dev.uuid == devVolumeUUID
            && observation.image.path == imagePath && observation.image.attachedVolumeUUID == devVolumeUUID
            && now.timeIntervalSince(observedAt) >= -5 && now.timeIntervalSince(observedAt) <= 120
    }
}
import HESectoriumCore
#if canImport(CoreFoundation)
import CoreFoundation
#endif
#if canImport(IOKit)
import IOKit
#endif

public struct SectoriumDeviceIOCounters: Equatable, Sendable {
    public let readBytes: UInt64
    public let writtenBytes: UInt64
    public init(readBytes: UInt64, writtenBytes: UInt64) {
        self.readBytes = readBytes; self.writtenBytes = writtenBytes
    }
}

/// A statistics-bearing ancestor in the IOService plane, retained in nearest-to-farthest order.
public struct SectoriumIOProviderSnapshot: Equatable, Sendable {
    public let className: String
    public let counters: SectoriumDeviceIOCounters?
    public init(className: String, counters: SectoriumDeviceIOCounters?) {
        self.className = className; self.counters = counters
    }
}

/// A checked relationship from one whole IOMedia node to its IOService ancestors.
public struct SectoriumIOMediaProviderMapping: Equatable, Sendable {
    public let bsdName: String
    /// Persistent IOMedia UUID sampled from the same registry node as these counters.
    public let stableMediaID: UUID?
    public let isWholeMedia: Bool
    public let ancestryIsUnambiguous: Bool
    public let providerAncestors: [SectoriumIOProviderSnapshot]
    public init(bsdName: String, stableMediaID: UUID? = nil, isWholeMedia: Bool, ancestryIsUnambiguous: Bool = true,
                providerAncestors: [SectoriumIOProviderSnapshot]) {
        self.bsdName = bsdName; self.stableMediaID = stableMediaID; self.isWholeMedia = isWholeMedia
        self.ancestryIsUnambiguous = ancestryIsUnambiguous; self.providerAncestors = providerAncestors
    }
}

public protocol SectoriumIORegistryProviding: AnyObject {
    /// Returns only IOMedia entries whose BSD name matches the requested selected device.
    func providerMappings(forWholeBSDName bsdName: String) throws -> [SectoriumIOMediaProviderMapping]
}

public protocol SectoriumDeviceIOCounterSampling: AnyObject {
    func counters(forWholeBSDName bsdName: String, expectedMediaID: UUID) -> SectoriumDeviceIOCounters?
}

/// Accepts counters only from exactly one selected whole-IOMedia node and exactly one
/// IOBlockStorageDriver in that node's checked parent chain. Missing, duplicate, or
/// partial values remain unknown.
public final class SectoriumDeviceIOSampler: SectoriumDeviceIOCounterSampling {
    private let provider: SectoriumIORegistryProviding
    public init(provider: SectoriumIORegistryProviding) { self.provider = provider }

    public func counters(forWholeBSDName bsdName: String, expectedMediaID: UUID) -> SectoriumDeviceIOCounters? {
        guard bsdName.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              let mappings = try? provider.providerMappings(forWholeBSDName: bsdName) else { return nil }
        let exact = mappings.filter { $0.bsdName == bsdName }
        guard exact.count == 1, let media = exact.first, media.stableMediaID == expectedMediaID, media.isWholeMedia,
              media.ancestryIsUnambiguous else { return nil }
        let drivers = media.providerAncestors.filter { $0.className == "IOBlockStorageDriver" }
        guard drivers.count == 1, let counters = drivers.first?.counters else { return nil }
        return counters
    }
}

#if canImport(IOKit)
/// Reads only the selected whole IOMedia's ancestor chain. It never walks children to
/// collect per-volume counters and never samples other whole devices' statistics.
public final class SystemSectoriumIORegistryProvider: SectoriumIORegistryProviding {
    public init() {}

    public func providerMappings(forWholeBSDName bsdName: String) throws -> [SectoriumIOMediaProviderMapping] {
        guard bsdName.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              let matching = IOServiceMatching("IOMedia") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [SectoriumIOMediaProviderMapping] = []
        while true {
            let media = IOIteratorNext(iterator)
            guard media != 0 else { break }
            if let name = stringProperty(media, key: "BSD Name"), name == bsdName {
                let whole = (numberProperty(media, key: "Whole")?.boolValue) == true
                let stableMediaID = stringProperty(media, key: "UUID").flatMap(UUID.init(uuidString:))
                let ancestors = whole ? providerAncestors(of: media) : []
                result.append(.init(bsdName: name, stableMediaID: stableMediaID, isWholeMedia: whole,
                                    ancestryIsUnambiguous: whole && !ancestors.isEmpty,
                                    providerAncestors: ancestors))
            }
            IOObjectRelease(media)
        }
        return result
    }

    private func providerAncestors(of media: io_registry_entry_t) -> [SectoriumIOProviderSnapshot] {
        var result: [SectoriumIOProviderSnapshot] = []
        var current = media
        var currentIsOwned = false
        var reachedRoot = false
        for _ in 0..<32 {
            var parentIterator: io_iterator_t = 0
            guard IORegistryEntryGetParentIterator(current, kIOServicePlane, &parentIterator) == KERN_SUCCESS else {
                if currentIsOwned { IOObjectRelease(current) }
                return []
            }
            defer { IOObjectRelease(parentIterator) }
            let parent = IOIteratorNext(parentIterator)
            guard parent != 0 else { reachedRoot = true; break }
            let additionalParent = IOIteratorNext(parentIterator)
            guard additionalParent == 0 else {
                IOObjectRelease(parent)
                IOObjectRelease(additionalParent)
                if currentIsOwned { IOObjectRelease(current) }
                return []
            }
            if currentIsOwned { IOObjectRelease(current) }
            current = parent
            currentIsOwned = true
            if IOObjectConformsTo(current, "IOBlockStorageDriver") != 0 {
                let dictionary = dictionaryProperty(current, key: "Statistics")
                let read = (dictionary?["Bytes (Read)"] as? NSNumber)?.uint64Value
                let written = (dictionary?["Bytes (Write)"] as? NSNumber)?.uint64Value
                let counters = (read != nil && written != nil)
                    ? SectoriumDeviceIOCounters(readBytes: read!, writtenBytes: written!) : nil
                result.append(.init(className: "IOBlockStorageDriver", counters: counters))
            }
        }
        if currentIsOwned { IOObjectRelease(current) }
        return reachedRoot ? result : []
    }

    private func property(_ entry: io_registry_entry_t, key: String) -> Any? {
        guard let copied = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else { return nil }
        return copied.takeRetainedValue()
    }
    private func stringProperty(_ entry: io_registry_entry_t, key: String) -> String? { property(entry, key: key) as? String }
    private func numberProperty(_ entry: io_registry_entry_t, key: String) -> NSNumber? { property(entry, key: key) as? NSNumber }
    private func dictionaryProperty(_ entry: io_registry_entry_t, key: String) -> [String: Any]? {
        property(entry, key: key) as? [String: Any]
    }
}
#else
public final class SystemSectoriumIORegistryProvider: SectoriumIORegistryProviding {
    public init() {}
    public func providerMappings(forWholeBSDName bsdName: String) throws -> [SectoriumIOMediaProviderMapping] { [] }
}
#endif

public func makeSystemSectoriumDeviceIOSampler() -> SectoriumDeviceIOCounterSampling {
    SectoriumDeviceIOSampler(provider: SystemSectoriumIORegistryProvider())
}

public struct SectoriumVolumeMember: Equatable, Hashable, Sendable {
    public let volumeUUID: UUID
    public let bsdName: String
    public let mountPoint: String?
    public let name: String?
    public let capacityBytes: UInt64?
    public var mounted: Bool { mountPoint != nil }

    public init(volumeUUID: UUID, bsdName: String, mountPoint: String?, name: String? = nil, capacityBytes: UInt64? = nil) {
        self.volumeUUID = volumeUUID; self.bsdName = bsdName; self.mountPoint = mountPoint
        self.name = name; self.capacityBytes = capacityBytes
    }

    public init(bsdName: String, volumeUUID: UUID, mounted: Bool, mountPoint: String?) {
        self.volumeUUID = volumeUUID; self.bsdName = bsdName
        self.mountPoint = mounted ? mountPoint : nil
        self.name = nil; self.capacityBytes = nil
    }
}

public typealias SectoriumPhysicalVolumeMember = SectoriumVolumeMember

public enum SectoriumDeviceIdentityBasis: String, Equatable, Sendable {
    case wholeMediaUUID, uniqueBackingVolumeUUID, unavailable
}

public struct SectoriumAPFSContainerDetail: Equatable, Sendable {
    public let bsdName: String
    public let partitionContent: String
    public init(bsdName: String, partitionContent: String) {
        self.bsdName = bsdName; self.partitionContent = partitionContent
    }
}

public struct SectoriumPhysicalDevice: Identifiable, Equatable, Sendable {
    /// Stable identity from a whole media UUID or a unique, directly owned backing volume.
    /// A BSD name is never a mutation identity.
    public let id: String
    public let bsdName: String
    public let name: String
    public let isExternal: Bool
    /// False includes unknown location; only corroborated internal media can be
    /// excluded when proving that an unrelated external drive disappeared.
    public let isInternalConfirmed: Bool
    public let identityVerified: Bool
    public let identityBasis: SectoriumDeviceIdentityBasis
    /// Only a whole-media UUID may be used to correlate I/O counters.
    public let wholeMediaUUID: UUID?
    /// System observations require a fresh partition-to-whole check before mutation.
    public let requiresFreshParentCheck: Bool
    public let isVirtual: Bool?
    public let topologyComplete: Bool
    public let volumeMembers: [SectoriumVolumeMember]
    public let apfsContainers: [SectoriumAPFSContainerDetail]
    public let hasAmbiguousPhysicalStores: Bool
    public let wholeDeviceBytes: UInt64?
    public let mountedVolumePaths: [String]
    public let volumeUUIDs: [UUID]
    public let readBytes: UInt64?
    public let writtenBytes: UInt64?

    public init(id: String, bsdName: String, name: String, isExternal: Bool, identityVerified: Bool,
                wholeDeviceBytes: UInt64?, mountedVolumePaths: [String], volumeUUIDs: [UUID],
                readBytes: UInt64?, writtenBytes: UInt64?, volumeMembers: [SectoriumVolumeMember] = [],
                topologyComplete: Bool = false, isVirtual: Bool? = nil,
                identityBasis: SectoriumDeviceIdentityBasis? = nil, wholeMediaUUID: UUID? = nil,
                requiresFreshParentCheck: Bool = false,
                apfsContainers: [SectoriumAPFSContainerDetail] = [],
                hasAmbiguousPhysicalStores: Bool = false,
                isInternalConfirmed: Bool = false) {
        self.id = id; self.bsdName = bsdName; self.name = name; self.isExternal = isExternal
        self.isInternalConfirmed = isInternalConfirmed && !isExternal
        self.identityVerified = identityVerified; self.isVirtual = isVirtual
        self.identityBasis = identityBasis ?? (identityVerified ? .wholeMediaUUID : .unavailable)
        self.wholeMediaUUID = wholeMediaUUID ?? (self.identityBasis == .wholeMediaUUID ? UUID(uuidString: id) : nil)
        self.requiresFreshParentCheck = requiresFreshParentCheck
        self.topologyComplete = topologyComplete; self.volumeMembers = volumeMembers
        self.apfsContainers = apfsContainers
        self.hasAmbiguousPhysicalStores = hasAmbiguousPhysicalStores
        self.wholeDeviceBytes = wholeDeviceBytes
        self.mountedVolumePaths = mountedVolumePaths; self.volumeUUIDs = volumeUUIDs
        self.readBytes = readBytes; self.writtenBytes = writtenBytes
    }
}

public enum SectoriumDeviceCatalogError: Error, Equatable, Sendable {
    case commandFailed(String)
    case malformedDeviceInventory
}

/// Parses diskutil device metadata only; physical I/O values remain unknown until their
/// IORegistry-to-whole-device relationship can be verified without guessing.
public struct SectoriumDeviceCatalog {
    public init() {}

    /// Both diskutil ownership fields are claims about the same whole disk. Neither
    /// may take precedence when they disagree or contain malformed metadata.
    public static func verifiedParentWholeDisk(_ info: [String: Any]) -> String? {
        let claims = ["ParentWholeDisk", "PartOfWhole"].compactMap { info[$0] }
        guard !claims.isEmpty, claims.allSatisfy({ $0 is String }),
              let parent = claims.first as? String,
              parent.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              claims.allSatisfy({ ($0 as? String) == parent }) else { return nil }
        return parent
    }

    public func parse(diskInventory: Data, ioRegistry: Data,
                      deviceInformation: [String: [String: Any]] = [:]) throws -> [SectoriumPhysicalDevice] {
        guard let plist = try? PropertyListSerialization.propertyList(from: diskInventory, options: [], format: nil),
              let root = plist as? [String: Any],
              let disks = root["AllDisksAndPartitions"] as? [[String: Any]] else {
            throw SectoriumDeviceCatalogError.malformedDeviceInventory
        }
        // A cloned backing UUID cannot identify either physical parent. Count all direct
        // volume occurrences before assigning an anchor; never pick the first match.
        let anchorCounts: [UUID: Int] = disks.reduce(into: [:]) { counts, row in
            guard let bsd = row["DeviceIdentifier"] as? String else { return }
            for partition in row["Partitions"] as? [[String: Any]] ?? [] {
                guard let child = partition["DeviceIdentifier"] as? String,
                      child.hasPrefix(bsd + "s"),
                      let info = deviceInformation[child],
                      Self.verifiedParentWholeDisk(info) == bsd,
                      let raw = (info["VolumeUUID"] as? String) ?? (info["APFSVolumeUUID"] as? String),
                      let uuid = UUID(uuidString: raw) else { continue }
                counts[uuid, default: 0] += 1
            }
        }
        let candidates: [SectoriumPhysicalDevice] = disks.compactMap { entry in
            guard let bsd = entry["DeviceIdentifier"] as? String,
                  bsd.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { return nil }
            let info = deviceInformation[bsd] ?? entry["DeviceInfo"] as? [String: Any] ?? entry
            let stable = ["MediaUUID", "DeviceUUID", "DiskUUID"].compactMap { info[$0] as? String }
                .compactMap(UUID.init(uuidString:)).first
            let explicitKind = (info["VirtualOrPhysical"] as? String)?.lowercased()
            let isVirtual: Bool? = explicitKind == "virtual" ? true : explicitKind == "physical" ? false
                : ((info["Internal"] as? Bool) == true
                    && (info["WholeDisk"] as? Bool) == true
                    && (info["Content"] as? String) == "GUID_partition_scheme"
                    && info["APFSPhysicalStores"] == nil ? false : nil)
            let external = (info["DeviceLocation"] as? String)?.lowercased() == "external"
                || (info["Internal"] as? Bool) == false
            let confirmedInternal = !external && ((info["Internal"] as? Bool) == true
                || (info["DeviceLocation"] as? String)?.lowercased() == "internal")
            let name = (info["MediaName"] as? String) ?? (info["VolumeName"] as? String) ?? "Unnamed device"
            let bytes = (info["TotalSize"] as? NSNumber)?.uint64Value ?? (info["DiskSize"] as? NSNumber)?.uint64Value
            let partitions = entry["Partitions"] as? [[String: Any]] ?? []
            // APFS volumes are listed separately from partitions by diskutil. They are
            // display metadata only; physical parent identity still comes from direct partitions.
            let apfsVolumes = entry["APFSVolumes"] as? [[String: Any]] ?? []
            var mounts: [String] = []
            var volumes: [UUID] = []
            var members: [SectoriumVolumeMember] = []
            var topologyComplete = !partitions.isEmpty
            let invalidOwnershipClaim = partitions.contains { partition in
                guard let child = partition["DeviceIdentifier"] as? String,
                      let claim = deviceInformation[child],
                      claim["ParentWholeDisk"] != nil || claim["PartOfWhole"] != nil else { return false }
                return Self.verifiedParentWholeDisk(claim) != bsd
            }
            if invalidOwnershipClaim { topologyComplete = false }
            for key in ["VolumeUUID", "APFSVolumeUUID"] {
                if let raw = info[key] as? String, let uuid = UUID(uuidString: raw) { volumes.append(uuid) }
            }
            if let point = info["MountPoint"] as? String, point.hasPrefix("/Volumes/"), !point.contains("/../") {
                mounts.append(point)
            }
            for part in partitions {
                let partID = part["DeviceIdentifier"] as? String
                let partInfo = partID.flatMap { deviceInformation[$0] } ?? part
                let memberUUID = ["VolumeUUID", "APFSVolumeUUID"].compactMap { partInfo[$0] as? String }
                    .compactMap(UUID.init(uuidString:)).first
                if let partID, partID.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil,
                   let memberUUID {
                    let memberMount = (partInfo["MountPoint"] as? String).flatMap { point in
                        point.hasPrefix("/Volumes/") && !point.split(separator: "/").contains("..") ? point : nil
                    }
                    members.append(.init(volumeUUID: memberUUID, bsdName: partID, mountPoint: memberMount,
                                         name: partInfo["VolumeName"] as? String,
                                         capacityBytes: (partInfo["TotalSize"] as? NSNumber)?.uint64Value))
                } else {
                    topologyComplete = false
                }
                if let point = partInfo["MountPoint"] as? String, point.hasPrefix("/Volumes/"), !point.contains("/../") {
                    mounts.append(point)
                }
                if let memberUUID { volumes.append(memberUUID) }
            }
            if isVirtual == true {
                for volume in apfsVolumes {
                    guard let volumeID = volume["DeviceIdentifier"] as? String,
                          volumeID.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil,
                          let volumeInfo = deviceInformation[volumeID],
                          Self.verifiedParentWholeDisk(volumeInfo) == bsd,
                          let rawUUID = (volumeInfo["VolumeUUID"] as? String) ?? (volumeInfo["APFSVolumeUUID"] as? String),
                          let uuid = UUID(uuidString: rawUUID) else { continue }
                    let point = (volumeInfo["MountPoint"] as? String).flatMap { value in
                        value.hasPrefix("/Volumes/") && !value.split(separator: "/").contains("..") ? value : nil
                    }
                    members.append(.init(volumeUUID: uuid, bsdName: volumeID, mountPoint: point,
                                         name: volumeInfo["VolumeName"] as? String,
                                         capacityBytes: (volumeInfo["TotalSize"] as? NSNumber)?.uint64Value))
                }
            }
            let uniqueAnchors = members.filter { anchorCounts[$0.volumeUUID] == 1 }
            let anchor = stable == nil && isVirtual == false && members.count == 1
                && uniqueAnchors.count == 1 && topologyComplete ? uniqueAnchors.first?.volumeUUID : nil
            let identity = invalidOwnershipClaim ? nil : (stable ?? anchor)
            let containerDetails: [SectoriumAPFSContainerDetail] = partitions.compactMap { partition in
                guard let partitionID = partition["DeviceIdentifier"] as? String,
                      let content = partition["Content"] as? String,
                      content.hasPrefix("Apple_APFS") else { return nil }
                let matches = disks.compactMap { row -> String? in
                    guard let childID = row["DeviceIdentifier"] as? String,
                          let childInfo = deviceInformation[childID],
                          (childInfo["VirtualOrPhysical"] as? String)?.lowercased() == "virtual",
                          let stores = childInfo["APFSPhysicalStores"] as? [[String: Any]],
                          stores.count == 1,
                          stores[0]["APFSPhysicalStore"] as? String == partitionID else { return nil }
                    return childID
                }
                guard matches.count == 1, let match = matches.first else { return nil }
                return .init(bsdName: match, partitionContent: content)
            }
            let basis: SectoriumDeviceIdentityBasis = identity == nil ? .unavailable
                : stable != nil ? .wholeMediaUUID : .uniqueBackingVolumeUUID
            return SectoriumPhysicalDevice(
                id: identity?.uuidString ?? "unverified-\(bsd)", bsdName: bsd, name: name,
                isExternal: external, identityVerified: identity != nil && isVirtual == false, wholeDeviceBytes: bytes,
                mountedVolumePaths: Array(Set(mounts)).sorted(), volumeUUIDs: Array(Set(volumes)).sorted { $0.uuidString < $1.uuidString },
                readBytes: nil, writtenBytes: nil,
                volumeMembers: members.sorted { $0.bsdName < $1.bsdName },
                topologyComplete: topologyComplete && Set(members.map(\.bsdName)).count == partitions.count
                    && Set(members.map(\.volumeUUID)).count == members.count,
                isVirtual: isVirtual, identityBasis: basis, wholeMediaUUID: stable,
                requiresFreshParentCheck: true,
                apfsContainers: containerDetails.sorted { $0.bsdName < $1.bsdName },
                hasAmbiguousPhysicalStores: isVirtual == true
                    && ((info["APFSPhysicalStores"] as? [[String: Any]])?.count ?? 0) > 1,
                isInternalConfirmed: confirmedInternal
            )
        }
        let identityCounts = candidates.reduce(into: [String: Int]()) { counts, device in
            if device.identityVerified { counts[device.id, default: 0] += 1 }
        }
        return candidates.map { device in
            guard device.identityVerified, identityCounts[device.id, default: 0] > 1 else { return device }
            return SectoriumPhysicalDevice(id: "unverified-\(device.bsdName)", bsdName: device.bsdName,
                name: device.name, isExternal: device.isExternal, identityVerified: false,
                wholeDeviceBytes: device.wholeDeviceBytes, mountedVolumePaths: device.mountedVolumePaths,
                volumeUUIDs: device.volumeUUIDs, readBytes: nil, writtenBytes: nil,
                volumeMembers: device.volumeMembers, topologyComplete: device.topologyComplete,
                isVirtual: device.isVirtual, identityBasis: .unavailable,
                requiresFreshParentCheck: device.requiresFreshParentCheck,
                apfsContainers: device.apfsContainers,
                hasAmbiguousPhysicalStores: device.hasAmbiguousPhysicalStores,
                isInternalConfirmed: device.isInternalConfirmed)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public protocol SectoriumDeviceObserving: AnyObject {
    func observeDevices() throws -> [SectoriumPhysicalDevice]
}

public final class SystemSectoriumDeviceObserver: SectoriumDeviceObserving {
    private let runner: HESectoriumCommandRunning
    private let workingDirectory: URL
    private let catalog = SectoriumDeviceCatalog()

    public init(runner: HESectoriumCommandRunning = ProcessCommandRunner(), workingDirectory: URL = FileManager.default.temporaryDirectory) {
        self.runner = runner; self.workingDirectory = workingDirectory
    }

    public func observeDevices() throws -> [SectoriumPhysicalDevice] {
        let inventory = runner.run("/usr/sbin/diskutil", ["list", "-plist"], cwd: workingDirectory)
        guard inventory.succeeded, let diskData = inventory.detail.data(using: .utf8) else {
            throw SectoriumDeviceCatalogError.commandFailed("disk inventory unavailable")
        }
        guard let root = (try? PropertyListSerialization.propertyList(from: diskData, options: [], format: nil)) as? [String: Any],
              let inventoryRows = root["AllDisksAndPartitions"] as? [[String: Any]] else {
            throw SectoriumDeviceCatalogError.malformedDeviceInventory
        }
        let wholeDisks = inventoryRows
            .compactMap { $0["DeviceIdentifier"] as? String }
            .filter { $0.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil }
        let volumeNodes = inventoryRows.flatMap { row in
            (row["Partitions"] as? [[String: Any]] ?? []) + (row["APFSVolumes"] as? [[String: Any]] ?? [])
        }
            .compactMap { $0["DeviceIdentifier"] as? String }
            .filter { $0.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil }
        var information: [String: [String: Any]] = [:]
        for disk in wholeDisks + volumeNodes {
            let info = runner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(disk)"], cwd: workingDirectory)
            if info.succeeded, let data = info.detail.data(using: .utf8),
               let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
               let dictionary = value as? [String: Any], dictionary["DeviceIdentifier"] as? String == disk {
                information[disk] = dictionary
            }
        }
        return try catalog.parse(diskInventory: diskData, ioRegistry: Data(), deviceInformation: information)
    }
}

/// Read-only evidence for a normal application-quit prompt. Open references
/// include working directories: a process can block unmount without writing.
public struct SectoriumActivityReference: Equatable, Sendable {
    public let descriptor: String
    public let path: String
    public init(descriptor: String, path: String) { self.descriptor = descriptor; self.path = path }
}
public struct SectoriumActivityProcess: Equatable, Sendable {
    public let processID: Int32
    public let command: String
    public let executablePath: String?
    public let bundleIdentifier: String?
    public let applicationName: String?
    public let owningApplicationProcessID: Int32?
    public let references: [SectoriumActivityReference]
    public init(processID: Int32, command: String, executablePath: String? = nil,
                bundleIdentifier: String? = nil, applicationName: String? = nil, owningApplicationProcessID: Int32? = nil,
                references: [SectoriumActivityReference] = []) {
        self.processID = processID; self.command = command; self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier; self.applicationName = applicationName
        self.owningApplicationProcessID = owningApplicationProcessID; self.references = references
    }
}
public struct SectoriumActivityReport: Equatable, Sendable {
    public let assessment: OccupancyAssessment
    public let processes: [SectoriumActivityProcess]
    public init(assessment: OccupancyAssessment, processes: [SectoriumActivityProcess] = []) {
        self.assessment = assessment; self.processes = processes
    }
    /// Supports lsof's field protocol and legacy fixture/table output. Malformed
    /// or failed scans never become "no applications are using the volume".
    static func parse(_ outcome: CommandOutcome) -> SectoriumActivityReport {
        if outcome.exitCode == 1 && outcome.detail.isEmpty { return .init(assessment: .noVisibleOccupancy) }
        guard outcome.succeeded else {
            return .init(assessment: .incomplete(reason: "lsof exit=\(outcome.exitCode): \(String(outcome.detail.prefix(180)))"))
        }
        var processes: [SectoriumActivityProcess] = []
        let lines = outcome.detail.split(whereSeparator: \.isNewline).map(String.init)
        if lines.first?.first == "p", lines.first.flatMap({ Int32($0.dropFirst()) }) != nil {
            var pid: Int32?, command = "", descriptor = "", references: [SectoriumActivityReference] = []
            func append() {
                guard let pid else { return }
                processes.append(.init(processID: pid, command: command.isEmpty ? "PID \(pid)" : command,
                    executablePath: references.first(where: { $0.descriptor == "txt" })?.path, references: references))
            }
            for line in lines {
                guard let key = line.first else { continue }; let value = String(line.dropFirst())
                switch key {
                case "p": append(); pid = Int32(value); command = ""; descriptor = ""; references = []
                case "c": command = value
                case "f":
                    descriptor = value
                    if pid != nil { references.append(.init(descriptor: descriptor, path: "")) }
                case "n":
                    if pid != nil {
                        if references.last?.descriptor == descriptor && references.last?.path == "" { references.removeLast() }
                        references.append(.init(descriptor: descriptor, path: value))
                    }
                default: break
                }
            }
            append()
        } else {
            for line in lines.dropFirst() {
                let fields = line.split(maxSplits: 8, whereSeparator: \.isWhitespace).map(String.init)
                guard fields.count >= 2, let pid = Int32(fields[1]) else { continue }
                let refs: [SectoriumActivityReference] = fields.count >= 9 ? [.init(descriptor: fields[3], path: fields[8])] : []
                processes.append(.init(processID: pid, command: fields[0], references: refs))
            }
        }
        guard !processes.isEmpty else { return .init(assessment: .incomplete(reason: "lsof returned rows without a PID")) }
        let grouped = Dictionary(grouping: processes, by: \.processID).map { pid, rows in
            SectoriumActivityProcess(processID: pid, command: rows[0].command,
                executablePath: rows.compactMap(\.executablePath).first, references: rows.flatMap(\.references))
        }.sorted { $0.processID < $1.processID }
        return .init(assessment: .busy(processIDs: grouped.map(\.processID)), processes: grouped)
    }
}

public enum SectoriumWorkbenchReadiness: Equatable, Sendable {
    case noDevice
    case connected
    case noDevelopmentDisk
    case notStarted
    case awaitingUnlock
    case ready
    case readOnly
    case busy
    case operationInProgress(String)
    case partialFailure(String)
    case ejected
    case unknown(String)
}

public struct SectoriumIOReading: Equatable, Sendable {
    public let readBytesPerSecond: UInt64?
    public let writtenBytesPerSecond: UInt64?
    public let isFresh: Bool
    public init(readBytesPerSecond: UInt64?, writtenBytesPerSecond: UInt64?, isFresh: Bool) {
        self.readBytesPerSecond = readBytesPerSecond; self.writtenBytesPerSecond = writtenBytesPerSecond; self.isFresh = isFresh
    }
}

public enum SectoriumProfileValidation: String, Codable, Equatable, Sendable {
    case pendingValidation, validated, unavailable
}

/// Only formats for which the native sparsebundle creation path has a writable
/// filesystem argument. Detection of a readable filesystem is not permission
/// to offer it for creation.
public enum SectoriumFilesystem: String, Codable, CaseIterable, Equatable, Sendable {
    case apfs = "APFS"
    case apfsCaseSensitive = "APFSX"

    public var caseSensitive: Bool { self == .apfsCaseSensitive }
}

public struct SectoriumCreateRequest: Sendable {
    public let deviceID: String
    public let parentDirectory: URL?
    public let name: String
    public let capacityGiB: Int
    public let filesystem: SectoriumFilesystem
    public let autoLoad: Bool
    public let mountPoint: String?
    public let password: String?

    public init(deviceID: String, parentDirectory: URL? = nil, name: String, capacityGiB: Int,
                filesystem: SectoriumFilesystem = .apfs, autoLoad: Bool = true,
                mountPoint: String? = nil, password: String? = nil) {
        self.deviceID = deviceID; self.parentDirectory = parentDirectory; self.name = name
        self.capacityGiB = capacityGiB; self.filesystem = filesystem; self.autoLoad = autoLoad
        self.mountPoint = mountPoint; self.password = password
    }
}

public enum SectoriumProfileChange: Codable, Equatable, Sendable {
    case displayName(String)
    case autoLoad(Bool)
    case mountPoint(String)
    case capacityGiB(Int)
    case filesystem(SectoriumFilesystem)
}

public struct SectoriumDevelopmentProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public let deviceID: String
    public let backingVolumeUUID: UUID
    public var backingMountPoint: String
    public var imagePath: String
    public var devVolumeName: String
    public var devMountPoint: String
    public var devUUID: UUID?
    /// Nil means the image property was not established by a supported observation.
    /// Optional storage preserves previously encoded concrete values without migration.
    public var encrypted: Bool?
    public let caseSensitive: Bool?
    public var logicalCapacityBytes: UInt64?
    /// `hdiutil imageinfo -format` output. Older profiles decode with an unknown format.
    public var imageFormat: String?
    public var validation: SectoriumProfileValidation
    public var filesystem: SectoriumFilesystem?
    public var autoLoad: Bool
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var lastVerifiedLoadedAt: Date?
    /// File identity is pinned within the verified backing volume; replacement requires explicit re-registration.
    public var imageFileIdentity: String?
    public var autoLoadWasConfigured: Bool

    public init(id: String = UUID().uuidString, name: String, deviceID: String, backingVolumeUUID: UUID,
                backingMountPoint: String, imagePath: String, devVolumeName: String, devMountPoint: String,
                devUUID: UUID? = nil, encrypted: Bool?, caseSensitive: Bool?, logicalCapacityBytes: UInt64?,
                imageFormat: String? = nil,
                validation: SectoriumProfileValidation = .pendingValidation,
                filesystem: SectoriumFilesystem? = nil, autoLoad: Bool = true,
                createdAt: Date? = nil, modifiedAt: Date? = nil, lastVerifiedLoadedAt: Date? = nil,
                imageFileIdentity: String? = nil, autoLoadWasConfigured: Bool = true) {
        self.id = id; self.name = name; self.deviceID = deviceID; self.backingVolumeUUID = backingVolumeUUID
        self.backingMountPoint = backingMountPoint; self.imagePath = imagePath; self.devVolumeName = devVolumeName
        self.devMountPoint = devMountPoint; self.devUUID = devUUID; self.encrypted = encrypted
        self.caseSensitive = caseSensitive; self.logicalCapacityBytes = logicalCapacityBytes
        self.imageFormat = imageFormat; self.validation = validation
        self.filesystem = filesystem ?? caseSensitive.map { $0 ? .apfsCaseSensitive : .apfs }
        self.autoLoad = autoLoad; self.createdAt = createdAt; self.modifiedAt = modifiedAt
        self.lastVerifiedLoadedAt = lastVerifiedLoadedAt
        self.imageFileIdentity = imageFileIdentity; self.autoLoadWasConfigured = autoLoadWasConfigured
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, deviceID, backingVolumeUUID, backingMountPoint, imagePath
        case devVolumeName, devMountPoint, devUUID, encrypted, caseSensitive
        case logicalCapacityBytes, imageFormat, validation, filesystem, autoLoad
        case createdAt, modifiedAt, lastVerifiedLoadedAt, imageFileIdentity, autoLoadWasConfigured
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            deviceID: try c.decode(String.self, forKey: .deviceID),
            backingVolumeUUID: try c.decode(UUID.self, forKey: .backingVolumeUUID),
            backingMountPoint: try c.decode(String.self, forKey: .backingMountPoint),
            imagePath: try c.decode(String.self, forKey: .imagePath),
            devVolumeName: try c.decode(String.self, forKey: .devVolumeName),
            devMountPoint: try c.decode(String.self, forKey: .devMountPoint),
            devUUID: try c.decodeIfPresent(UUID.self, forKey: .devUUID),
            encrypted: try c.decodeIfPresent(Bool.self, forKey: .encrypted),
            caseSensitive: try c.decodeIfPresent(Bool.self, forKey: .caseSensitive),
            logicalCapacityBytes: try c.decodeIfPresent(UInt64.self, forKey: .logicalCapacityBytes),
            imageFormat: try c.decodeIfPresent(String.self, forKey: .imageFormat),
            validation: try c.decode(SectoriumProfileValidation.self, forKey: .validation),
            filesystem: try c.decodeIfPresent(SectoriumFilesystem.self, forKey: .filesystem),
            autoLoad: try c.decodeIfPresent(Bool.self, forKey: .autoLoad) ?? false,
            createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt),
            modifiedAt: try c.decodeIfPresent(Date.self, forKey: .modifiedAt),
            lastVerifiedLoadedAt: try c.decodeIfPresent(Date.self, forKey: .lastVerifiedLoadedAt),
            imageFileIdentity: try c.decodeIfPresent(String.self, forKey: .imageFileIdentity),
            autoLoadWasConfigured: try c.decodeIfPresent(Bool.self, forKey: .autoLoadWasConfigured) ?? c.contains(.autoLoad))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(deviceID, forKey: .deviceID)
        try c.encode(backingVolumeUUID, forKey: .backingVolumeUUID)
        try c.encode(backingMountPoint, forKey: .backingMountPoint)
        try c.encode(imagePath, forKey: .imagePath)
        try c.encode(devVolumeName, forKey: .devVolumeName)
        try c.encode(devMountPoint, forKey: .devMountPoint)
        try c.encodeIfPresent(devUUID, forKey: .devUUID)
        try c.encodeIfPresent(encrypted, forKey: .encrypted)
        try c.encodeIfPresent(caseSensitive, forKey: .caseSensitive)
        try c.encodeIfPresent(logicalCapacityBytes, forKey: .logicalCapacityBytes)
        try c.encodeIfPresent(imageFormat, forKey: .imageFormat)
        try c.encode(validation, forKey: .validation)
        try c.encodeIfPresent(filesystem, forKey: .filesystem)
        try c.encode(autoLoad, forKey: .autoLoad)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(lastVerifiedLoadedAt, forKey: .lastVerifiedLoadedAt)
        try c.encodeIfPresent(imageFileIdentity, forKey: .imageFileIdentity)
        try c.encode(autoLoadWasConfigured, forKey: .autoLoadWasConfigured)
    }

    public var hasVerifiedImageMetadata: Bool {
        encrypted != nil && caseSensitive != nil && logicalCapacityBytes != nil && imageFormat == "UDSB"
    }

    /// Format is required for the supported lifecycle; display-only image facts may remain unknown.
    public var hasVerifiedImageFormat: Bool { imageFormat == "UDSB" }
}

public struct SectoriumWorkbenchSnapshot: Equatable, Sendable {
    public let devices: [SectoriumPhysicalDevice]
    public let selectedDeviceID: String?
    public let profiles: [SectoriumDevelopmentProfile]
    public let selectedProfileID: String?
    public let readiness: SectoriumWorkbenchReadiness
    public let pendingOperation: String?
    public let io: SectoriumIOReading
    public let operationSteps: [OperationStepResult]
    public let safeToUnplug: Bool
    public init(devices: [SectoriumPhysicalDevice] = [], selectedDeviceID: String? = nil,
                profiles: [SectoriumDevelopmentProfile] = [], selectedProfileID: String? = nil,
                readiness: SectoriumWorkbenchReadiness = .unknown("Not observed"),
                pendingOperation: String? = nil,
                io: SectoriumIOReading = .init(readBytesPerSecond: nil, writtenBytesPerSecond: nil, isFresh: false),
                operationSteps: [OperationStepResult] = [], safeToUnplug: Bool = false) {
        self.devices = devices; self.selectedDeviceID = selectedDeviceID; self.profiles = profiles
        self.selectedProfileID = selectedProfileID; self.readiness = readiness; self.pendingOperation = pendingOperation
        self.io = io; self.operationSteps = operationSteps; self.safeToUnplug = safeToUnplug
    }
}
