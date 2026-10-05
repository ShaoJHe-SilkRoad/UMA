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
    public var mounted: Bool { mountPoint != nil }

    public init(volumeUUID: UUID, bsdName: String, mountPoint: String?) {
        self.volumeUUID = volumeUUID; self.bsdName = bsdName; self.mountPoint = mountPoint
    }

    public init(bsdName: String, volumeUUID: UUID, mounted: Bool, mountPoint: String?) {
        self.volumeUUID = volumeUUID; self.bsdName = bsdName
        self.mountPoint = mounted ? mountPoint : nil
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
                hasAmbiguousPhysicalStores: Bool = false) {
        self.id = id; self.bsdName = bsdName; self.name = name; self.isExternal = isExternal
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
            let name = (info["MediaName"] as? String) ?? (info["VolumeName"] as? String) ?? "Unnamed device"
            let bytes = (info["TotalSize"] as? NSNumber)?.uint64Value ?? (info["DiskSize"] as? NSNumber)?.uint64Value
            let partitions = entry["Partitions"] as? [[String: Any]] ?? []
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
                    members.append(.init(volumeUUID: memberUUID, bsdName: partID, mountPoint: memberMount))
                } else {
                    topologyComplete = false
                }
                if let point = partInfo["MountPoint"] as? String, point.hasPrefix("/Volumes/"), !point.contains("/../") {
                    mounts.append(point)
                }
                if let memberUUID { volumes.append(memberUUID) }
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
                    && ((info["APFSPhysicalStores"] as? [[String: Any]])?.count ?? 0) > 1
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
                hasAmbiguousPhysicalStores: device.hasAmbiguousPhysicalStores)
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
        let volumeNodes = inventoryRows.flatMap { row in (row["Partitions"] as? [[String: Any]] ?? []) }
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

public struct SectoriumDevelopmentProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let deviceID: String
    public let backingVolumeUUID: UUID
    public let backingMountPoint: String
    public let imagePath: String
    public var devVolumeName: String
    public var devMountPoint: String
    public var devUUID: UUID?
    /// Nil means the image property was not established by a supported observation.
    /// Optional storage preserves previously encoded concrete values without migration.
    public var encrypted: Bool?
    public let caseSensitive: Bool?
    public let logicalCapacityBytes: UInt64?
    /// `hdiutil imageinfo -format` output. Older profiles decode with an unknown format.
    public let imageFormat: String?
    public var validation: SectoriumProfileValidation

    public init(id: String = UUID().uuidString, name: String, deviceID: String, backingVolumeUUID: UUID,
                backingMountPoint: String, imagePath: String, devVolumeName: String, devMountPoint: String,
                devUUID: UUID? = nil, encrypted: Bool?, caseSensitive: Bool?, logicalCapacityBytes: UInt64?,
                imageFormat: String? = nil,
                validation: SectoriumProfileValidation = .pendingValidation) {
        self.id = id; self.name = name; self.deviceID = deviceID; self.backingVolumeUUID = backingVolumeUUID
        self.backingMountPoint = backingMountPoint; self.imagePath = imagePath; self.devVolumeName = devVolumeName
        self.devMountPoint = devMountPoint; self.devUUID = devUUID; self.encrypted = encrypted
        self.caseSensitive = caseSensitive; self.logicalCapacityBytes = logicalCapacityBytes
        self.imageFormat = imageFormat; self.validation = validation
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
