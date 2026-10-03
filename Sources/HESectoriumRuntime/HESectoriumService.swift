import Foundation
import HESectoriumCore
#if canImport(Darwin)
import Darwin
#endif
#if canImport(DiskArbitration)
import DiskArbitration
import CoreFoundation
#endif
#if canImport(ServiceManagement)
import ServiceManagement
#endif

public struct HESectoriumPaths: Sendable, Equatable {
    public let root: URL
    public var state: URL { root.appendingPathComponent("state.json") }
    public var lock: URL { root.appendingPathComponent("operation.lock") }
    public var config: URL { root.appendingPathComponent("storage-identity.json") }
    public var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public var workingDirectory: URL { root }
    public init(root: URL) { self.root = root.standardizedFileURL }
    public static var user: Self {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return .init(root: support.appendingPathComponent("UMA/HESectorium", isDirectory: true))
    }
}

public protocol HESectoriumCommandRunning: AnyObject {
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome
}
public final class ProcessCommandRunner: HESectoriumCommandRunning {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        let process = Process(); let out = Pipe(); let err = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.currentDirectoryURL = cwd; process.standardOutput = out; process.standardError = err
        do {
            try process.run()
            let group = DispatchGroup(); let captured = CapturedProcessOutput()
            group.enter(); DispatchQueue.global().async { captured.setOut(out.fileHandleForReading.readDataToEndOfFile()); group.leave() }
            group.enter(); DispatchQueue.global().async { captured.setErr(err.fileHandleForReading.readDataToEndOfFile()); group.leave() }
            process.waitUntilExit(); group.wait(); let (outData, errData) = captured.values()
            let detail = [String(data: outData, encoding: .utf8), String(data: errData, encoding: .utf8)]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            return .init(exitCode: process.terminationStatus, detail: String(detail.prefix(8192)))
        } catch { return .init(exitCode: -1, detail: String(describing: error)) }
    }
}
private final class CapturedProcessOutput: @unchecked Sendable {
    private let lock = NSLock(); private var out = Data(); private var err = Data()
    func setOut(_ data: Data) { lock.lock(); out = data; lock.unlock() }
    func setErr(_ data: Data) { lock.lock(); err = data; lock.unlock() }
    func values() -> (Data, Data) { lock.lock(); defer { lock.unlock() }; return (out, err) }
}

public enum HESectoriumInstalledStatus: Equatable, Sendable { case installed, missing, conflict(String) }
public enum HESectoriumReadinessStatus: Equatable, Sendable { case ready, notReady(String), unknown }
public enum HESectoriumAgentLoadStatus: Equatable, Sendable { case loaded, notLoaded, unknown }
public enum HESectoriumOperationProgress: Equatable, Sendable { case idle, running(action: String) }
public protocol HESectoriumAgentStatusProviding: AnyObject {
    func loadStatus(label: String) -> HESectoriumAgentLoadStatus
}
public final class SystemAgentStatusProvider: HESectoriumAgentStatusProviding {
    public init() {}
    public func loadStatus(label: String) -> HESectoriumAgentLoadStatus {
        #if canImport(ServiceManagement)
        guard label == "com.juliushe.dev-apfs-mounter" else { return .unknown }
        // SMJobCopyDictionary is the only read-only ServiceManagement lookup for an
        // arbitrary user LaunchAgent label. It returns an unmanaged CFDictionary;
        // taking the retained value is required before bridging to Swift.
        guard let unmanagedJob = SMJobCopyDictionary(kSMDomainUserLaunchd, label as CFString) else { return .notLoaded }
        guard let job = unmanagedJob.takeRetainedValue() as? [String: Any] else { return .unknown }
        return (job["Label"] as? String) == label ? .loaded : .unknown
        #else
        return .unknown
        #endif
    }
}
public final class UnknownAgentStatusProvider: HESectoriumAgentStatusProviding {
    public init() {}
    public func loadStatus(label: String) -> HESectoriumAgentLoadStatus { .unknown }
}
public enum HESectoriumFileInstallState: String, Equatable, Sendable { case installed, adopted, restored, unchanged, withheld }
public struct HESectoriumFileInstallOutcome: Equatable, Sendable {
    public let file: String; public let state: HESectoriumFileInstallState; public let detail: String
    public init(file: String, state: HESectoriumFileInstallState, detail: String = "") {
        self.file = String(file.prefix(160)); self.state = state; self.detail = String(detail.prefix(240))
    }
}
public struct HESectoriumDiagnostic: Equatable, Sendable {
    public let timestamp: Date; public let category: String; public let summary: String
    public init(timestamp: Date = Date(), category: String, summary: String) {
        self.timestamp = timestamp; self.category = String(category.prefix(48)); self.summary = String(summary.prefix(240))
    }
}
public struct HESectoriumRuntimeSnapshot: Equatable, Sendable {
    public let installed: HESectoriumInstalledStatus
    public let automationEnabled: Bool
    public let agentLoadStatus: HESectoriumAgentLoadStatus
    public let operationProgress: HESectoriumOperationProgress
    public let readiness: HESectoriumReadinessStatus
    public let pendingEject: Bool?
    public let diagnostics: [HESectoriumDiagnostic]
    public let latestActionSummary: String
    public init(installed: HESectoriumInstalledStatus, automationEnabled: Bool, readiness: HESectoriumReadinessStatus,
                pendingEject: Bool?, diagnostics: [HESectoriumDiagnostic], latestActionSummary: String,
                agentLoadStatus: HESectoriumAgentLoadStatus = .unknown,
                operationProgress: HESectoriumOperationProgress = .idle) {
        self.installed = installed; self.automationEnabled = automationEnabled; self.readiness = readiness
        self.agentLoadStatus = agentLoadStatus; self.operationProgress = operationProgress
        self.pendingEject = pendingEject; self.diagnostics = Array(diagnostics.suffix(20)); self.latestActionSummary = String(latestActionSummary.prefix(240))
    }
}
public enum HESectoriumInstallAction: Sendable, Equatable { case install, repair }
public struct HESectoriumAssets: Sendable {
    public let control: URL; public let devMountWrapper: URL; public let ejectWrapper: URL; public let launchAgent: URL
    public let identityConfig: URL?
    public init(control: URL, devMountWrapper: URL, ejectWrapper: URL, launchAgent: URL, identityConfig: URL? = nil) {
        self.control = control; self.devMountWrapper = devMountWrapper; self.ejectWrapper = ejectWrapper
        self.launchAgent = launchAgent; self.identityConfig = identityConfig
    }
}
public struct HESectoriumInstallResult: Equatable, Sendable {
    public let succeeded: Bool; public let summary: String; public let changedPaths: [String]
    public let fileOutcomes: [HESectoriumFileInstallOutcome]
    public init(succeeded: Bool, summary: String, changedPaths: [String] = [], fileOutcomes: [HESectoriumFileInstallOutcome] = []) {
        self.succeeded = succeeded; self.summary = String(summary.prefix(240)); self.changedPaths = changedPaths; self.fileOutcomes = fileOutcomes
    }
}

public final class JSONStateStore: DurableStateStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> StoragePersistentState {
        try secureParent()
        guard FileManager.default.fileExists(atPath: url.path) else { return .init(ejectIntent: false) }
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw RuntimeError.unsafePath("state file is not a plain file")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try JSONDecoder().decode(StoragePersistentStateCodable.self, from: data).state
    }
    public func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
        let old = try load(); guard old.revision == expectedRevision else { return false }
        let data = try JSONEncoder().encode(StoragePersistentStateCodable(state: newState))
        try data.write(to: url, options: .atomic)
        #if canImport(Darwin)
        _ = chmod(url.path, mode_t(0o600))
        #endif
        return true
    }
    private func secureParent() throws {
        let fm = FileManager.default
        try SecureDirectory.ensure(url.deletingLastPathComponent())
        let attrs = try fm.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        guard (attrs[.type] as? FileAttributeType) == .typeDirectory,
              url.deletingLastPathComponent().standardizedFileURL.path == url.deletingLastPathComponent().resolvingSymlinksInPath().path else {
            throw RuntimeError.unsafePath("state parent is not a plain directory")
        }
    }
}
private struct StoragePersistentStateCodable: Codable {
    var revision: UInt64; var ejectIntent: Bool; var operationID: String?; var outerDisappearedAfterIntent: Bool
    init(state: StoragePersistentState) { revision = state.revision; ejectIntent = state.ejectIntent; operationID = state.operationID; outerDisappearedAfterIntent = state.outerDisappearedAfterIntent }
    var state: StoragePersistentState { .init(revision: revision, ejectIntent: ejectIntent, operationID: operationID, outerDisappearedAfterIntent: outerDisappearedAfterIntent) }
}

public final class KernelOperationLock: OperationLock {
    private let url: URL; private let mutex = NSLock(); private var descriptor: Int32 = -1
    public init(url: URL) { self.url = url }
    public func acquire() -> Bool {
        mutex.lock(); defer { mutex.unlock() }
        do { try SecureDirectory.ensure(url.deletingLastPathComponent()) }
        catch { return false }
        guard url.deletingLastPathComponent().standardizedFileURL.path == url.deletingLastPathComponent().resolvingSymlinksInPath().path else { return false }
        #if canImport(Darwin)
        let fd = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600)); guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        descriptor = fd; return true
        #else
        return false
        #endif
    }
    public func release() {
        mutex.lock(); defer { mutex.unlock() }
        #if canImport(Darwin)
        if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1 }
        #endif
    }
}

public enum RuntimeError: Error, LocalizedError {
    case unsafePath(String), assetsUnavailable, installConflict(String), automationPendingEject
    public var errorDescription: String? { switch self { case .unsafePath(let s), .installConflict(let s): return s; case .assetsUnavailable: return "Install assets are unavailable"; case .automationPendingEject: return "Automation cannot run while eject recovery is pending" } }
}

public final class MacStorageBackend: StorageBackend {
    private let policy: StorageIdentityPolicy; private let paths: HESectoriumPaths; private let runner: HESectoriumCommandRunning
    public init(paths: HESectoriumPaths, runner: HESectoriumCommandRunning = ProcessCommandRunner(), policy: StorageIdentityPolicy = .expected) {
        self.paths = paths; self.runner = runner; self.policy = policy
    }
    private func command(_ path: String, _ args: [String]) -> CommandOutcome { runner.run(path, args, cwd: paths.workingDirectory) }
    private func plist(_ outcome: CommandOutcome) -> [String: Any]? {
        guard outcome.exitCode == 0, let start = outcome.detail.range(of: "<?xml") ?? outcome.detail.range(of: "<plist"),
              let end = outcome.detail.range(of: "</plist>", range: start.lowerBound..<outcome.detail.endIndex),
              let data = String(outcome.detail[start.lowerBound..<end.upperBound]).data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
    private func diskInfo(_ path: String) -> [String: Any]? { plist(command("/usr/sbin/diskutil", ["info", "-plist", path])) }
    private func text(_ dictionary: [String: Any]?, _ keys: [String]) -> String? { for key in keys { if let s = dictionary?[key] as? String { return s } }; return nil }
    private func validDiskID(_ value: String) -> Bool { value.range(of: #"^disk[0-9]+(?:s[0-9]+)?$"#, options: .regularExpression) != nil }
    private func wholeDisk(_ node: String) -> String? {
        let value = node.hasPrefix("/dev/") ? String(node.dropFirst(5)) : node
        guard let match = value.range(of: #"^disk[0-9]+"#, options: .regularExpression) else { return nil }
        let whole = String(value[match]); return validDiskID(whole) ? whole : nil
    }
    private func sourceForFile(_ path: String) -> (device: String, mount: String)? {
        let outcome = command("/bin/df", ["-P", path])
        guard outcome.exitCode == 0 else { return nil }
        let lines = outcome.detail.split(whereSeparator: \.isNewline)
        guard lines.count >= 2, let row = lines.last else { return nil }
        let fields = row.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 6, fields[0].hasPrefix("/dev/"),
              let device = fields[0].split(separator: "/").last.map(String.init), validDiskID(device) else { return nil }
        return (device, fields.last!)
    }
    private func containers() -> [[String: Any]]? {
        guard let value = plist(command("/usr/sbin/diskutil", ["apfs", "list", "-plist"])) else { return nil }
        return value["Containers"] as? [[String: Any]] ?? value["APFSContainers"] as? [[String: Any]]
    }
    private func physicalStoreDevices(_ container: [String: Any]) -> Set<String>? {
        guard let stores = container["PhysicalStores"] as? [[String: Any]], !stores.isEmpty else { return nil }
        let ids = stores.compactMap { text($0, ["DeviceIdentifier", "DeviceNode"]) }.filter(validDiskID)
        return ids.count == stores.count ? Set(ids) : nil
    }
    private func volume(_ path: String) -> VolumeIdentity {
        let info = diskInfo(path); let uuid = text(info, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:))
        let mount = text(info, ["MountPoint"]) ?? path
        let fs = text(info, ["FilesystemType", "FilesystemName", "FileSystemPersonality"]) ?? "unknown"
        let writable = (info?["WritableVolume"] as? Bool) ?? (info?["Writable"] as? Bool) ?? !((info?["VolumeReadOnly"] as? Bool) ?? true)
        let mounted = text(info, ["MountPoint"]) != nil && !mount.isEmpty
        let name = text(info, ["VolumeName", "MediaName"]) ?? "unknown"
        return .init(uuid: uuid, mountPoint: mount, fileSystem: fs, writable: writable, mountedVolume: mounted, name: name,
                     rootMatchesExpected: canonical(path) == path && mount == path)
    }
    private func imageObservation() -> ImageIdentity? {
        guard let images = plist(command("/usr/bin/hdiutil", ["info", "-plist"]))?["images"] as? [[String: Any]],
              let image = images.first(where: { text($0, ["image-path"]) == policy.imagePath }),
              let entities = image["system-entities"] as? [[String: Any]],
              let imageEntityDevices = Optional(entities.compactMap { entity -> String? in
                  guard let raw = text(entity, ["dev-entry"]) else { return nil }
                  let value = raw.hasPrefix("/dev/") ? String(raw.dropFirst(5)) : raw
                  return validDiskID(value) ? value : nil
              }),
              let entity = entities.first(where: { text($0, ["mount-point"]) == policy.devMountPoint }),
              let imageUUID = text(entity, ["volume-uuid", "volume-UUID"]).flatMap(UUID.init(uuidString:)),
              let imageDev = text(entity, ["dev-entry"]), let imageWhole = wholeDisk(imageDev),
              let devInfo = diskInfo(imageDev),
              text(devInfo, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)) == imageUUID,
              text(devInfo, ["FilesystemType", "FilesystemName", "FileSystemPersonality"])?.uppercased().contains("APFS") == true,
              text(devInfo, ["MountPoint"]) == policy.devMountPoint,
              let devContainerRef = text(devInfo, ["APFSContainerReference"]),
              devContainerRef == imageWhole,
              let apfsContainers = containers(),
              let devContainer = apfsContainers.first(where: { text($0, ["ContainerReference"]) == devContainerRef }),
              let imageStores = physicalStoreDevices(devContainer),
              !imageStores.isDisjoint(with: Set(imageEntityDevices.map { wholeDisk($0) ?? $0 })),
              let containerVolumes = devContainer["Volumes"] as? [[String: Any]],
              containerVolumes.contains(where: {
                  text($0, ["APFSVolumeUUID"])?.lowercased() == imageUUID.uuidString.lowercased() &&
                  text($0, ["DeviceIdentifier"]) == String(imageDev.split(separator: "/").last ?? "")
              }),
              let backing = sourceForFile(policy.imagePath), backing.mount == policy.outerMountPoint,
              let outerInfo = diskInfo("/dev/\(backing.device)"),
              text(outerInfo, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)) == policy.outerUUID,
              text(outerInfo, ["MountPoint"]) == policy.outerMountPoint,
              text(outerInfo, ["DeviceIdentifier"]) == backing.device,
              let outerPhysical = text(outerInfo, ["PartOfWhole"]), validDiskID(outerPhysical),
              let physicalInfo = diskInfo("/dev/\(outerPhysical)"),
              text(physicalInfo, ["DeviceIdentifier"]) == outerPhysical else { return nil }
        if let outerContainerRef = text(outerInfo, ["APFSContainerReference"]) {
            guard let outerContainer = apfsContainers.first(where: { text($0, ["ContainerReference"]) == outerContainerRef }),
                  let outerStores = physicalStoreDevices(outerContainer), outerStores.contains(backing.device) else { return nil }
        }
        return .init(backingVolumeUUID: policy.outerUUID, attachedVolumeUUID: imageUUID, path: policy.imagePath)
    }
    public func observeOuter() -> VolumeIdentity? {
        guard canonical(policy.outerMountPoint) == policy.outerMountPoint else { return nil }
        let outer = volume(policy.outerMountPoint)
        guard outer.uuid != nil, outer.mountedVolume, outer.mountPoint == policy.outerMountPoint, outer.rootMatchesExpected else { return nil }
        return outer
    }
    public func observe() -> StorageObservation? {
        guard canonical(policy.outerMountPoint) == policy.outerMountPoint,
              canonical(policy.devMountPoint) == policy.devMountPoint,
              canonical(policy.imagePath) == policy.imagePath else { return nil }
        let outer = volume(policy.outerMountPoint); let dev = volume(policy.devMountPoint)
        guard outer.uuid != nil, dev.uuid != nil, let image = imageObservation() else { return nil }
        return .init(outer: outer, dev: dev, image: image)
    }
    /// Checks only the physical outer volume and configured image path; used for one login-time attach attempt.
    public func canAttemptMount() -> Bool {
        guard canonical(policy.outerMountPoint) == policy.outerMountPoint,
              canonical(policy.imagePath) == policy.imagePath,
              FileManager.default.fileExists(atPath: policy.imagePath),
              FileManager.default.fileExists(atPath: policy.devMountPoint) else { return false }
        guard let outer = observeOuter() else { return false }
        return outer.uuid == policy.outerUUID && outer.writable
    }
    public func attachImage() -> CommandOutcome {
        guard canAttemptMount() else {
            return .init(exitCode: -2, detail: "Expected HE image and existing DEV mountpoint are unavailable")
        }
        if let seen = observe(), case .success = policy.validate(seen) { return .success }
        guard (try? FileManager.default.contentsOfDirectory(atPath: policy.devMountPoint).isEmpty) == true else {
            return .init(exitCode: -2, detail: "Underlying DEV directory is non-empty; refusing to hide files")
        }
        let result = command("/usr/sbin/diskutil", ["image", "attach", "--nobrowse", "--mountPoint", policy.devMountPoint, policy.imagePath])
        return .init(exitCode: result.exitCode, detail: result.detail)
    }
    private func canonical(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path }
    public func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment {
        let mount = scope == .dev ? policy.devMountPoint : policy.outerMountPoint
        guard canonical(mount) == mount, FileManager.default.fileExists(atPath: mount) else { return .incomplete(reason: "verified mount scope unavailable") }
        let outcome = command("/usr/sbin/lsof", ["-nP", "+f", "--", mount])
        if outcome.exitCode == 0 {
            let rows = outcome.detail.split(separator: "\n").dropFirst()
            let pids = rows.compactMap { row -> Int32? in Int32(row.split(whereSeparator: \.isWhitespace).dropFirst().first ?? "") }
            return pids.isEmpty ? .incomplete(reason: "lsof returned rows without a PID") : .busy(processIDs: Array(Set(pids)).sorted())
        }
        if outcome.exitCode == 1 && outcome.detail.isEmpty { return .noVisibleOccupancy }
        return .incomplete(reason: "lsof exit=\(outcome.exitCode): \(String(outcome.detail.prefix(180)))")
    }
    public func perform(_ step: EjectStep) -> CommandOutcome {
        switch step {
        case .flush: return command("/bin/sync", [])
        case .unmountDEV: return command("/usr/sbin/diskutil", ["unmount", policy.devMountPoint])
        case .detachImage:
            guard let disk = imageWholeDisk() else { return .init(exitCode: -2, detail: "Could not verify attached image device") }
            return command("/usr/sbin/diskutil", ["eject", "/dev/\(disk)"])
        case .ejectOuterHE:
            guard let disk = text(diskInfo(policy.outerMountPoint), ["PartOfWhole"]), disk.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else {
                return .init(exitCode: -2, detail: "Could not verify physical HE disk")
            }
            return command("/usr/sbin/diskutil", ["eject", "/dev/\(disk)"])
        }
    }
    private func imageWholeDisk() -> String? {
        guard let images = plist(command("/usr/bin/hdiutil", ["info", "-plist"]))?["images"] as? [[String: Any]],
              let image = images.first(where: { text($0, ["image-path"]) == policy.imagePath }),
              let entities = image["system-entities"] as? [[String: Any]],
              let entry = entities.compactMap({ text($0, ["dev-entry"]) }).first(where: { $0.hasPrefix("/dev/disk") }) else { return nil }
        let name = String(entry.dropFirst("/dev/".count)); let whole = name.split(separator: "s").first.map(String.init) ?? name
        return whole.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil ? whole : nil
    }
    public func finalOuterState() -> FinalOuterState {
        guard let list = plist(command("/usr/sbin/diskutil", ["list", "-plist"])),
              let all = list["AllDisks"] as? [String], !all.isEmpty else { return .unknown("diskutil list failed or did not enumerate devices") }
        var complete = true
        for device in all {
            guard let info = diskInfo("/dev/\(device)") else { complete = false; continue }
            if text(info, ["VolumeUUID", "APFSVolumeUUID", "DiskUUID"]).flatMap(UUID.init(uuidString:)) == policy.outerUUID { return .stillPresent }
        }
        return complete ? .absent : .unknown("one or more listed devices could not be inspected")
    }
}

public final class HESectoriumService: @unchecked Sendable {
    public static let shared = HESectoriumService(paths: .user, agentStatusProvider: SystemAgentStatusProvider())
    public let paths: HESectoriumPaths; public let coreController: StorageController
    private let backend: StorageBackend; private let store: DurableStateStore; private let lock: OperationLock
    private let installer: HESectoriumInstaller; private let serial = NSRecursiveLock()
    private let agentStatusProvider: HESectoriumAgentStatusProviding
    private let progressLock = NSLock(); private var currentProgress: HESectoriumOperationProgress = .idle
    private var activeProgress: [String: Int] = [:]
    private var configurationValid: Bool
    private let explicitIdentityPolicy: Bool
    private var lastAction = "No action recorded"; private var diagnostics: [HESectoriumDiagnostic] = []
    public init(paths: HESectoriumPaths = .user, backend: StorageBackend? = nil, store: DurableStateStore? = nil,
                operationLock: OperationLock? = nil, installer: HESectoriumInstaller? = nil,
                runner: HESectoriumCommandRunning = ProcessCommandRunner(), identityPolicy: StorageIdentityPolicy? = nil,
                agentStatusProvider: HESectoriumAgentStatusProviding = UnknownAgentStatusProvider()) {
        self.paths = paths; let resolvedStore = store ?? JSONStateStore(url: paths.state); self.store = resolvedStore
        let diskPolicy = identityPolicy ?? Self.readIdentityPolicy(at: paths.config)
        explicitIdentityPolicy = identityPolicy != nil
        configurationValid = explicitIdentityPolicy || Self.readIdentityPolicy(at: paths.config) != nil
        let policy = diskPolicy ?? .expected
        let resolvedLock = operationLock ?? KernelOperationLock(url: paths.lock); self.lock = resolvedLock
        let resolvedBackend = backend ?? MacStorageBackend(paths: paths, runner: runner, policy: policy); self.backend = resolvedBackend
        self.agentStatusProvider = agentStatusProvider
        self.installer = installer ?? HESectoriumInstaller(paths: paths)
        self.coreController = StorageController(backend: resolvedBackend, store: resolvedStore, lock: resolvedLock, identityPolicy: policy)
    }
    public func refreshStatus() -> HESectoriumRuntimeSnapshot {
        let progress = progressSnapshot()
        guard serial.try() else {
            return .init(installed: installer.status(), automationEnabled: installer.automationEnabled(), readiness: .unknown,
                         pendingEject: try? store.load().ejectIntent, diagnostics: [], latestActionSummary: "Operation in progress",
                         agentLoadStatus: agentStatusProvider.loadStatus(label: "com.juliushe.dev-apfs-mounter"), operationProgress: progress)
        }
        defer { serial.unlock() }
        configurationValid = explicitIdentityPolicy || Self.readIdentityPolicy(at: paths.config) != nil
        let readiness: HESectoriumReadinessStatus
        if !configurationValid { readiness = .notReady("identity configuration missing or invalid") }
        else if let observation = backend.observe() {
            switch coreController.identityPolicy.validate(observation) { case .success: readiness = .ready; case .failure(let reason): readiness = .notReady(reason.rawValue) }
        } else { readiness = .unknown }
        let pending = try? store.load().ejectIntent
        return .init(installed: installer.status(), automationEnabled: installer.automationEnabled(), readiness: readiness, pendingEject: pending,
                     diagnostics: diagnostics, latestActionSummary: lastAction,
                     agentLoadStatus: agentStatusProvider.loadStatus(label: "com.juliushe.dev-apfs-mounter"), operationProgress: progress)
    }
    private func progressSnapshot() -> HESectoriumOperationProgress {
        progressLock.lock(); defer { progressLock.unlock() }; return currentProgress
    }
    private func withProgress<T>(_ action: String, _ body: () -> T) -> T {
        progressLock.lock(); activeProgress[action, default: 0] += 1; currentProgress = .running(action: action); progressLock.unlock()
        defer {
            progressLock.lock()
            if let count = activeProgress[action], count > 1 { activeProgress[action] = count - 1 } else { activeProgress.removeValue(forKey: action) }
            currentProgress = activeProgress.keys.first.map(HESectoriumOperationProgress.running(action:)) ?? .idle
            progressLock.unlock()
        }
        return body()
    }
    public func mountDEV() -> OperationResult {
        withProgress("mount") {
            serial.lock(); defer { serial.unlock() }
            guard configurationValid else { return record(.init(operationID: UUID().uuidString, mode: .manual, steps: [], failure: .readiness(.outerUUIDMissing))) }
            return record(coreController.mountDEV())
        }
    }
    public func safeEjectHE() -> OperationResult {
        withProgress("eject") {
            serial.lock(); defer { serial.unlock() }
            guard configurationValid else { return record(.init(operationID: UUID().uuidString, mode: .manual, steps: [], failure: .readiness(.outerUUIDMissing))) }
            return record(coreController.safeEjectHE())
        }
    }
    private func record(_ result: OperationResult) -> OperationResult {
        serial.lock(); defer { serial.unlock() }
        lastAction = result.failure.map { "Failed: \($0)" } ?? "Completed with \(result.steps.filter { $0.status == .succeeded }.count) successful steps"
        diagnostics.append(.init(category: "operation", summary: lastAction)); diagnostics = Array(diagnostics.suffix(20))
        installer.appendDiagnostic(lastAction, to: paths.logs); return result
    }
    public func installRepair(_ action: HESectoriumInstallAction = .install, assets: HESectoriumAssets? = nil) -> HESectoriumInstallResult {
        withProgress("install") {
            serial.lock(); defer { serial.unlock() }
            guard lock.acquire() else { return .init(succeeded: false, summary: "Another storage operation is running") }; defer { lock.release() }
            let result = installer.apply(assets ?? bundledAssets(), action: action)
            if result.succeeded { configurationValid = explicitIdentityPolicy || Self.readIdentityPolicy(at: paths.config) != nil }
            lastAction = result.summary; diagnostics.append(.init(category: "install", summary: result.summary)); diagnostics = Array(diagnostics.suffix(20)); return result
        }
    }
    public func setAutomationEnabled(_ enabled: Bool) -> HESectoriumInstallResult {
        withProgress("automationConfiguration") {
            serial.lock(); defer { serial.unlock() }
            if enabled && !configurationValid { return .init(succeeded: false, summary: "A valid inspected identity configuration is required before enabling automation") }
            if enabled {
                do { if try store.load().ejectIntent { return .init(succeeded: false, summary: "Pending eject recovery requires explicit manual mount") } }
                catch { return .init(succeeded: false, summary: "Durable storage state is unavailable; automation remains unchanged") }
            }
            let result = installer.setAutomation(enabled); if result.succeeded { lastAction = enabled ? "Automation enabled" : "Automation disabled; no disk action performed" }; return result
        }
    }
    public func runAutomationAgent(_ event: StorageEvent) -> OperationResult {
        withProgress("automationEvent") {
            serial.lock(); defer { serial.unlock() }
            guard configurationValid, installer.automationEnabled() else {
                return record(.init(operationID: UUID().uuidString, mode: .automatic,
                                    steps: [.init(step: "automationGate", status: .skipped, detail: "Disabled or identity configuration unavailable")]))
            }
            switch event {
            case .outerDisappeared(let uuid):
                return record(coreController.handle(.outerDisappeared(uuid: uuid)))
            case .outerReappeared(let uuid) where uuid == coreController.identityPolicy.outerUUID:
                guard let outer = backend.observeOuter(), case .success = coreController.identityPolicy.validateOuter(outer) else {
                    return record(.init(operationID: UUID().uuidString, mode: .automatic, steps: [.init(step: "verifyOuterIdentity", status: .failed, detail: "Fresh physical HE observation failed")], failure: .observationUnavailable))
                }
                let state = coreController.processExit()
                if state?.ejectIntent == true {
                    // Core owns the pending-intent reconnect transaction (fresh
                    // identity check, one attach attempt, full validation, and CAS).
                    // Return its result directly so this same event cannot attach twice.
                    if state?.outerDisappearedAfterIntent == true {
                        return record(coreController.handle(event))
                    }
                    // Without a persisted physical disconnect, reconnect history is
                    // unknown; Core's automatic mount path reports manual recovery
                    // required and guarantees no attach occurs.
                    return record(coreController.mountDEV(mode: .automatic))
                }
                return record(coreController.mountDEV(mode: .automatic))
            case .devMounted, .imageChanged, .outerReappeared:
                return record(.init(operationID: UUID().uuidString, mode: .automatic,
                                    steps: [.init(step: "ignoreEvent", status: .skipped, detail: "Only the configured physical HE reconnect triggers automatic mount")] ))
            }
        }
    }
    /// Called once by the already-installed LaunchAgent at login. This is a single inspected startup action, not polling.
    public func runAutomationAgentAtStartup() -> OperationResult {
        withProgress("automationStartup") {
        serial.lock(); defer { serial.unlock() }
        guard configurationValid, installer.automationEnabled() else {
            return record(.init(operationID: UUID().uuidString, mode: .automatic,
                                steps: [.init(step: "automationGate", status: .skipped, detail: "Disabled or identity configuration unavailable")]))
        }
        if let macBackend = backend as? MacStorageBackend {
            guard macBackend.canAttemptMount() else {
                return record(.init(operationID: UUID().uuidString, mode: .automatic, steps: [], failure: .observationUnavailable))
            }
        } else {
            guard let observation = backend.observe() else {
                return record(.init(operationID: UUID().uuidString, mode: .automatic, steps: [], failure: .observationUnavailable))
            }
            if case .failure(let failure) = coreController.identityPolicy.validate(observation) {
                return record(.init(operationID: UUID().uuidString, mode: .automatic, steps: [], failure: .readiness(failure)))
            }
        }
        do {
            if try store.load().ejectIntent {
                return record(.init(operationID: UUID().uuidString, mode: .automatic, steps: [], failure: .recoveryRequiresManualMount))
            }
        } catch {
            return record(.init(operationID: UUID().uuidString, mode: .automatic, steps: [], failure: .stateUnavailable(String(describing: error))))
        }
        return record(coreController.mountDEV(mode: .automatic))
        }
    }
    private func bundledAssets() -> HESectoriumAssets? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let root = resources.appendingPathComponent("HESectorium", isDirectory: true)
        let control = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/HESectoriumControl")
        let config = root.appendingPathComponent("storage-identity.json")
        let assets = HESectoriumAssets(control: control,
            devMountWrapper: root.appendingPathComponent("dev-apfs-mount"), ejectWrapper: root.appendingPathComponent("he-eject"),
            launchAgent: root.appendingPathComponent("com.juliushe.dev-apfs-mounter.plist"), identityConfig: config)
        let urls = [assets.control, assets.devMountWrapper, assets.ejectWrapper, assets.launchAgent, config]
        return urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } ? assets : nil
    }
    public var configuredOuterVolumeUUID: UUID { coreController.identityPolicy.outerUUID }
    public var identityConfigurationReady: Bool { serial.lock(); defer { serial.unlock() }; return configurationValid }
    private static func readIdentityPolicy(at url: URL) -> StorageIdentityPolicy? {
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().path,
              url.deletingLastPathComponent().standardizedFileURL.path == url.deletingLastPathComponent().resolvingSymlinksInPath().path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular else { return nil }
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(IdentityConfiguration.self, from: data),
              let outer = UUID(uuidString: value.outerUUID), let dev = UUID(uuidString: value.devUUID),
              outer == StorageIdentityPolicy.expected.outerUUID, dev == StorageIdentityPolicy.expected.devUUID,
              value.outerMountPoint == "/Volumes/HE", value.devMountPoint == "/Volumes/HE/DEV",
              value.imagePath == "/Volumes/HE/.DEV-APFS.sparsebundle", value.devVolumeName == "DEV_APFS" else { return nil }
        return .init(outerUUID: outer, devUUID: dev, outerMountPoint: value.outerMountPoint,
                     devMountPoint: value.devMountPoint, devVolumeName: value.devVolumeName, imagePath: value.imagePath)
    }
}
private struct IdentityConfiguration: Codable {
    let outerUUID: String; let devUUID: String; let outerMountPoint: String; let devMountPoint: String
    let devVolumeName: String; let imagePath: String
}

#if canImport(DiskArbitration)
public final class HESectoriumDiskObserver {
    private let service: HESectoriumService; private let session: DASession
    public init?(service: HESectoriumService) { guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }; self.service = service; self.session = session }
    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let appeared: DADiskAppearedCallback = { disk, context in
            guard let context else { return }; Unmanaged<HESectoriumDiskObserver>.fromOpaque(context).takeUnretainedValue().deliver(disk, true)
        }
        let disappeared: DADiskDisappearedCallback = { disk, context in
            guard let context else { return }; Unmanaged<HESectoriumDiskObserver>.fromOpaque(context).takeUnretainedValue().deliver(disk, false)
        }
        DARegisterDiskAppearedCallback(session, nil, appeared, context); DARegisterDiskDisappearedCallback(session, nil, disappeared, context)
        DASessionSetDispatchQueue(session, DispatchQueue(label: "com.openai.uma.hesectorium.disk-arbitration"))
    }
    private func deliver(_ disk: DADisk, _ appeared: Bool) {
        guard let desc = DADiskCopyDescription(disk) as NSDictionary?,
              let raw = desc.object(forKey: kDADiskDescriptionVolumeUUIDKey),
              let uuid = (raw as? UUID) ?? (raw as? String).flatMap(UUID.init(uuidString:)),
              uuid == service.configuredOuterVolumeUUID, service.identityConfigurationReady else { return }
        _ = service.runAutomationAgent(appeared ? .outerReappeared(uuid: uuid) : .outerDisappeared(uuid: uuid))
    }
}
#endif
