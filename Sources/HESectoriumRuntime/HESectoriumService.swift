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

/// hdiutil's -stdinpass protocol is terminated by a NUL byte. Reject embedded NULs so
/// the supplied secret cannot be silently truncated before it reaches the utility.
func hdiutilPassphraseInput(_ password: String) -> Data? {
    guard !password.isEmpty else { return nil }
    let bytes = Array(password.utf8)
    guard !bytes.contains(0) else { return nil }
    return Data(bytes + [0])
}

public struct HESectoriumPaths: Sendable, Equatable {
    public let root: URL
    public var state: URL { root.appendingPathComponent("state.json") }
    public var lock: URL { root.appendingPathComponent("operation.lock") }
    public var config: URL { root.appendingPathComponent("storage-identity.json") }
    public var sectoriumProfiles: URL { root.appendingPathComponent("sectorium-profiles.json") }
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
public protocol HESectoriumTimedCommandRunning: HESectoriumCommandRunning {
    func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome
}
public protocol HESectoriumSecureCommandRunning: HESectoriumCommandRunning {
    /// Supplies one-shot secret bytes over stdin; implementations must not retain or log them.
    func run(_ executable: String, _ arguments: [String], cwd: URL, standardInput: Data) -> CommandOutcome
}
public final class ProcessCommandRunner: HESectoriumSecureCommandRunning, HESectoriumTimedCommandRunning {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        run(executable, arguments, cwd: cwd, standardInput: Data())
    }
    public func run(_ executable: String, _ arguments: [String], cwd: URL, standardInput: Data) -> CommandOutcome {
        execute(executable, arguments, cwd: cwd, standardInput: standardInput, timeout: nil)
    }
    public func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        execute(executable, arguments, cwd: cwd, standardInput: Data(), timeout: timeout)
    }
    private func execute(_ executable: String, _ arguments: [String], cwd: URL, standardInput: Data,
                         timeout: TimeInterval?) -> CommandOutcome {
        let process = Process(); let out = Pipe(); let err = Pipe()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.currentDirectoryURL = cwd; process.standardOutput = out; process.standardError = err; process.standardInput = input
        let completion = DispatchSemaphore(value: 0)
        if timeout != nil { process.terminationHandler = { _ in completion.signal() } }
        do {
            try process.run()
            let group = DispatchGroup()
            let metadata = Self.isReadOnlyPropertyList(executable: executable, arguments: arguments)
            let captured = CapturedProcessOutput(limit: metadata ? 1_048_576 : 8_192)
            group.enter(); DispatchQueue.global().async { captured.captureOut(from: out.fileHandleForReading); group.leave() }
            group.enter(); DispatchQueue.global().async { captured.captureErr(from: err.fileHandleForReading); group.leave() }
            if !standardInput.isEmpty { try input.fileHandleForWriting.write(contentsOf: standardInput) }
            try? input.fileHandleForWriting.close()
            var timedOut = false
            if let timeout {
                if completion.wait(timeout: .now() + max(0.1, timeout)) == .timedOut {
                    timedOut = true
                    process.terminate()
                    completion.wait()
                }
            } else {
                process.waitUntilExit()
            }
            group.wait(); let (outData, errData, outExceeded, errExceeded) = captured.values()
            let detail = [String(data: outData, encoding: .utf8), String(data: errData, encoding: .utf8)]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            if timedOut { return .init(exitCode: -1, detail: "command timed out; process terminated; \(String(detail.prefix(8000)))") }
            return Self.result(executable: executable, arguments: arguments, exitCode: process.terminationStatus,
                               stdout: outData, stderr: errData,
                               stdoutExceeded: outExceeded, stderrExceeded: errExceeded)
        } catch { return .init(exitCode: -1, detail: String(describing: error)) }
    }

    // Only supported read-only plist commands may retain the larger bounded payload.
    static func isReadOnlyPropertyList(executable: String, arguments: [String]) -> Bool {
        (executable == "/usr/sbin/diskutil" &&
            (arguments == ["list", "-plist"] || arguments == ["apfs", "list", "-plist"] ||
             (arguments.count == 3 && arguments[0] == "info" && arguments[1] == "-plist"))) ||
            (executable == "/usr/bin/hdiutil" && arguments == ["info", "-plist"])
    }

    static func result(executable: String, arguments: [String], exitCode: Int32,
                       stdout: Data, stderr: Data,
                       stdoutExceeded: Bool = false, stderrExceeded: Bool = false) -> CommandOutcome {
        let metadata = isReadOnlyPropertyList(executable: executable, arguments: arguments)
        if stdoutExceeded || stderrExceeded {
            return .init(exitCode: exitCode == 0 ? -1 : exitCode,
                         detail: "command output exceeded bounded capture limit")
        }
        if metadata && exitCode == 0 {
            guard stdout.count <= 1_048_576, let value = String(data: stdout, encoding: .utf8) else {
                return .init(exitCode: -1, detail: "read-only metadata unavailable or too large")
            }
            return .init(exitCode: 0, detail: value)
        }
        let detail = [String(data: stdout, encoding: .utf8), String(data: stderr, encoding: .utf8)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        return .init(exitCode: exitCode, detail: String(detail.prefix(8192)))
    }
}
private final class CapturedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var out = Data()
    private var err = Data()
    private var outExceeded = false
    private var errExceeded = false

    init(limit: Int) { self.limit = limit }

    func captureOut(from handle: FileHandle) {
        let result = Self.readAndDrain(handle, limit: limit)
        lock.lock(); out = result.data; outExceeded = result.exceeded; lock.unlock()
    }
    func captureErr(from handle: FileHandle) {
        let result = Self.readAndDrain(handle, limit: limit)
        lock.lock(); err = result.data; errExceeded = result.exceeded; lock.unlock()
    }
    func values() -> (Data, Data, Bool, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (out, err, outExceeded, errExceeded)
    }
    private static func readAndDrain(_ handle: FileHandle, limit: Int) -> (data: Data, exceeded: Bool) {
        var retained = Data()
        var exceeded = false
        do {
            while let chunk = try handle.read(upToCount: 16_384), !chunk.isEmpty {
                let remaining = max(0, limit + 1 - retained.count)
                if remaining > 0 { retained.append(contentsOf: chunk.prefix(remaining)) }
                if chunk.count > remaining || retained.count > limit { exceeded = true }
            }
        } catch {
            exceeded = true
            try? handle.close()
        }
        return (retained, exceeded)
    }
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
    var outerReconnectAttempted: Bool
    var workbenchOperation: String?
    var workbenchPhase: String?
    var workbenchTarget: String?
    var workbenchCompletedStep: String?
    var workbenchTerminalResult: String?
    init(state: StoragePersistentState) {
        revision = state.revision; ejectIntent = state.ejectIntent; operationID = state.operationID
        outerDisappearedAfterIntent = state.outerDisappearedAfterIntent
        outerReconnectAttempted = state.outerReconnectAttempted
        workbenchOperation = state.workbenchOperation; workbenchPhase = state.workbenchPhase
        workbenchTarget = state.workbenchTarget; workbenchCompletedStep = state.workbenchCompletedStep
        workbenchTerminalResult = state.workbenchTerminalResult
    }
    var state: StoragePersistentState {
        .init(revision: revision, ejectIntent: ejectIntent, operationID: operationID,
              outerDisappearedAfterIntent: outerDisappearedAfterIntent,
              outerReconnectAttempted: outerReconnectAttempted, workbenchOperation: workbenchOperation,
              workbenchPhase: workbenchPhase, workbenchTarget: workbenchTarget,
              workbenchCompletedStep: workbenchCompletedStep, workbenchTerminalResult: workbenchTerminalResult)
    }

    private enum CodingKeys: String, CodingKey {
        case revision, ejectIntent, operationID, outerDisappearedAfterIntent, outerReconnectAttempted
        case workbenchOperation, workbenchPhase, workbenchTarget, workbenchCompletedStep, workbenchTerminalResult
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        revision = try values.decode(UInt64.self, forKey: .revision)
        ejectIntent = try values.decode(Bool.self, forKey: .ejectIntent)
        operationID = try values.decodeIfPresent(String.self, forKey: .operationID)
        outerDisappearedAfterIntent = try values.decodeIfPresent(Bool.self, forKey: .outerDisappearedAfterIntent) ?? false
        outerReconnectAttempted = try values.decodeIfPresent(Bool.self, forKey: .outerReconnectAttempted) ?? false
        workbenchOperation = try values.decodeIfPresent(String.self, forKey: .workbenchOperation)
        workbenchPhase = try values.decodeIfPresent(String.self, forKey: .workbenchPhase)
        workbenchTarget = try values.decodeIfPresent(String.self, forKey: .workbenchTarget)
        workbenchCompletedStep = try values.decodeIfPresent(String.self, forKey: .workbenchCompletedStep)
        workbenchTerminalResult = try values.decodeIfPresent(String.self, forKey: .workbenchTerminalResult)
    }
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
    func imageEncryptionState() -> Bool? {
        let outcome = command("/usr/bin/hdiutil", ["isencrypted", policy.imagePath])
        guard outcome.succeeded else { return nil }
        return Self.documentedEncryptionState(outcome.detail)
    }
    static func documentedEncryptionState(_ output: String) -> Bool? {
        let stateLines = output.split(whereSeparator: \.isNewline).map {
            $0.split(whereSeparator: \.isWhitespace).map(String.init)
        }.filter { $0.first?.lowercased() == "encrypted:" }
        guard stateLines.count == 1, stateLines[0].count == 2 else { return nil }
        switch stateLines[0][1].uppercased() {
        case "YES": return true
        case "NO": return false
        default: return nil
        }
    }
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
    private func verifiedWholeDisk(for partition: String, info: [String: Any]) -> String? {
        if info["ParentWholeDisk"] != nil || info["PartOfWhole"] != nil {
            guard let reported = SectoriumDeviceCatalog.verifiedParentWholeDisk(info),
                  let whole = wholeDisk(partition), reported == whole else { return nil }
            return reported
        }
        guard let inventory = plist(command("/usr/sbin/diskutil", ["list", "-plist"])),
              let rows = inventory["AllDisksAndPartitions"] as? [[String: Any]] else { return nil }
        let owners = rows.compactMap { row -> String? in
            guard let whole = row["DeviceIdentifier"] as? String, validDiskID(whole), wholeDisk(whole) == whole,
                  let parts = row["Partitions"] as? [[String: Any]],
                  parts.contains(where: { $0["DeviceIdentifier"] as? String == partition }) else { return nil }
            return whole
        }
        return owners.count == 1 ? owners[0] : nil
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
        let unique = Set(ids)
        return ids.count == stores.count && unique.count == ids.count ? unique : nil
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
        guard let images = plist(command("/usr/bin/hdiutil", ["info", "-plist"]))?["images"] as? [[String: Any]] else { return nil }
        let matchingImages = images.filter { text($0, ["image-path"]) == policy.imagePath }
        guard matchingImages.count == 1, let image = matchingImages.first,
              let entities = image["system-entities"] as? [[String: Any]], !entities.isEmpty else { return nil }
        let entityDevices = entities.compactMap { entity -> String? in
            guard let raw = text(entity, ["dev-entry"]) else { return nil }
            let value = raw.hasPrefix("/dev/") ? String(raw.dropFirst(5)) : raw
            return validDiskID(value) ? value : nil
        }
        let imageWholeDevices = Set(entityDevices.compactMap { wholeDisk($0) })
        let matchingEntities = entities.filter { text($0, ["mount-point"]) == policy.devMountPoint }
        guard entityDevices.count == entities.count, Set(entityDevices).count == entityDevices.count,
              matchingEntities.count == 1, let entity = matchingEntities.first,
              let imageDev = text(entity, ["dev-entry"]), let imageWhole = wholeDisk(imageDev),
              let devInfo = diskInfo(imageDev),
              let imageUUID = text(devInfo, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)),
              (text(entity, ["volume-uuid", "volume-UUID"]) == nil ||
               text(entity, ["volume-uuid", "volume-UUID"]).flatMap(UUID.init(uuidString:)) == imageUUID),
              text(devInfo, ["FilesystemType", "FilesystemName", "FileSystemPersonality"])?.uppercased().contains("APFS") == true,
              text(devInfo, ["MountPoint"]) == policy.devMountPoint,
              let devContainerRef = text(devInfo, ["APFSContainerReference"]),
              devContainerRef == imageWhole,
              let apfsContainers = containers() else { return nil }
        let matchingDevContainers = apfsContainers.filter { text($0, ["ContainerReference"]) == devContainerRef }
        guard matchingDevContainers.count == 1, let devContainer = matchingDevContainers.first,
              let imageStores = physicalStoreDevices(devContainer),
              imageWholeDevices.contains(imageWhole), imageStores.isSubset(of: Set(entityDevices)),
              let containerVolumes = devContainer["Volumes"] as? [[String: Any]],
              containerVolumes.filter({
                  text($0, ["APFSVolumeUUID"])?.lowercased() == imageUUID.uuidString.lowercased() &&
                  text($0, ["DeviceIdentifier"]) == String(imageDev.split(separator: "/").last ?? "")
              }).count == 1,
              let backing = sourceForFile(policy.imagePath), backing.mount == policy.outerMountPoint,
              let outerInfo = diskInfo("/dev/\(backing.device)"),
              text(outerInfo, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)) == policy.outerUUID,
              text(outerInfo, ["MountPoint"]) == policy.outerMountPoint,
              text(outerInfo, ["DeviceIdentifier"]) == backing.device,
              let outerPhysical = verifiedWholeDisk(for: backing.device, info: outerInfo),
              let physicalInfo = diskInfo("/dev/\(outerPhysical)"),
              text(physicalInfo, ["DeviceIdentifier"]) == outerPhysical,
              text(physicalInfo, ["VirtualOrPhysical"])?.lowercased() == "physical" else { return nil }
        if let outerContainerRef = text(outerInfo, ["APFSContainerReference"]) {
            let matchingOuterContainers = apfsContainers.filter { text($0, ["ContainerReference"]) == outerContainerRef }
            guard matchingOuterContainers.count == 1, let outerContainer = matchingOuterContainers.first,
                  let outerStores = physicalStoreDevices(outerContainer), outerStores.contains(backing.device) else { return nil }
        }
        return .init(backingVolumeUUID: policy.outerUUID, attachedVolumeUUID: imageUUID, path: policy.imagePath)
    }
    /// Returns the number of exact path matches in hdiutil's current image inventory.
    /// A missing or malformed inventory is unknown, never interpreted as detached.
    func imageInventoryMatchCount(for imagePath: String) -> Int? {
        guard let images = plist(command("/usr/bin/hdiutil", ["info", "-plist"]))?["images"] as? [[String: Any]] else { return nil }
        var matches = 0
        for image in images {
            guard let path = image["image-path"] as? String, !path.isEmpty,
                  path.hasPrefix("/"), URL(fileURLWithPath: path).standardizedFileURL.path == path else { return nil }
            if path == imagePath { matches += 1 }
        }
        return matches
    }
    func attachedImageMountIdentity(for imagePath: String) -> (mountPoint: String, volumeName: String, volumeUUID: UUID)? {
        guard let images = plist(command("/usr/bin/hdiutil", ["info", "-plist"]))?["images"] as? [[String: Any]] else { return nil }
        let matches = images.filter { text($0, ["image-path"]) == imagePath }
        guard matches.count == 1, let entities = matches[0]["system-entities"] as? [[String: Any]], !entities.isEmpty else { return nil }
        let devices = entities.compactMap { text($0, ["dev-entry"]) }.map { $0.hasPrefix("/dev/") ? String($0.dropFirst(5)) : $0 }
        let mountedEntities = entities.filter { text($0, ["mount-point"]) != nil }
        guard devices.count == entities.count, Set(devices).count == devices.count,
              devices.allSatisfy(validDiskID),
              mountedEntities.count == 1, let mounted = mountedEntities.first,
              let mountPoint = text(mounted, ["mount-point"]),
              URL(fileURLWithPath: mountPoint).standardizedFileURL.path == mountPoint,
              let deviceEntry = text(mounted, ["dev-entry"]),
              let info = diskInfo(deviceEntry),
              let volumeUUID = text(info, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)),
              let volumeName = text(info, ["VolumeName", "MediaName"]), !volumeName.isEmpty,
              text(info, ["FilesystemType", "FilesystemName", "FileSystemPersonality"])?.uppercased().contains("APFS") == true,
              text(info, ["MountPoint"]) == mountPoint else { return nil }
        return (mountPoint, volumeName, volumeUUID)
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
        attachImage(password: nil)
    }

    public func attachImage(password: String?) -> CommandOutcome {
        guard canAttemptMount() else {
            return .init(exitCode: -2, detail: "Expected HE image and existing DEV mountpoint are unavailable")
        }
        if let seen = observe(), case .success = policy.validate(seen) { return .success }
        guard directoryEntryCount(policy.devMountPoint) == 0 else {
            return .init(exitCode: -2, detail: "Underlying DEV directory is non-empty or its metadata count is unavailable")
        }
        if let password {
            guard let input = hdiutilPassphraseInput(password),
                  let secureRunner = runner as? HESectoriumSecureCommandRunning else {
                return .init(exitCode: -2, detail: "Unlock requires a secure stdin command runner")
            }
            let outcome = secureRunner.run("/usr/bin/hdiutil",
                ["attach", "-nobrowse", "-mountpoint", policy.devMountPoint, "-stdinpass", policy.imagePath],
                cwd: paths.workingDirectory, standardInput: input)
            return .init(exitCode: outcome.exitCode, detail: "Unlock/attach returned \(outcome.exitCode)")
        }
        let result = command("/usr/sbin/diskutil", ["image", "attach", "--nobrowse", "--mountPoint", policy.devMountPoint, policy.imagePath])
        return .init(exitCode: result.exitCode, detail: result.detail)
    }
    private func canonical(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path }
    private func directoryEntryCount(_ path: String) -> UInt32? {
        #if canImport(Darwin)
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var requested = attrlist()
        requested.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        requested.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)
        var response = (length: UInt32(0), count: UInt32(0))
        let responseSize = MemoryLayout.size(ofValue: response)
        let result = withUnsafeMutablePointer(to: &response) { pointer in
            fgetattrlist(descriptor, &requested, pointer, responseSize, 0)
        }
        guard result == 0, response.length >= UInt32(responseSize) else { return nil }
        return response.count
        #else
        return nil
        #endif
    }
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
            guard let info = diskInfo(policy.outerMountPoint),
                  let disk = SectoriumDeviceCatalog.verifiedParentWholeDisk(info) else {
                return .init(exitCode: -2, detail: "Could not verify physical HE disk")
            }
            return command("/usr/sbin/diskutil", ["eject", "/dev/\(disk)"])
        }
    }
    private func imageWholeDisk() -> String? {
        guard let images = plist(command("/usr/bin/hdiutil", ["info", "-plist"]))?["images"] as? [[String: Any]] else { return nil }
        let matchingImages = images.filter { text($0, ["image-path"]) == policy.imagePath }
        guard matchingImages.count == 1, let image = matchingImages.first,
              let entities = image["system-entities"] as? [[String: Any]], !entities.isEmpty else { return nil }
        let entityDevices = entities.compactMap { entity -> String? in
            guard let raw = text(entity, ["dev-entry"]) else { return nil }
            let value = raw.hasPrefix("/dev/") ? String(raw.dropFirst(5)) : raw
            return validDiskID(value) ? value : nil
        }
        let imageWholeDevices = Set(entityDevices.compactMap { wholeDisk($0) })
        let matchingVolumes: [[String: Any]]
        if let expectedUUID = policy.devUUID {
            matchingVolumes = entities.filter {
                text($0, ["volume-uuid", "volume-UUID"]).flatMap(UUID.init(uuidString:)) == expectedUUID
            }
        } else {
            matchingVolumes = entities.filter { text($0, ["mount-point"]) == policy.devMountPoint }
        }
        guard entityDevices.count == entities.count, Set(entityDevices).count == entityDevices.count,
              matchingVolumes.count == 1, let entity = matchingVolumes.first,
              let device = text(entity, ["dev-entry"]), let info = diskInfo(device),
              let containerID = text(info, ["APFSContainerReference"]),
              text(info, ["FilesystemType", "FilesystemName", "FileSystemPersonality"])?.uppercased().contains("APFS") == true,
              (policy.devUUID == nil || text(info, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)) == policy.devUUID),
              let containers = containers() else { return nil }
        let matchingContainers = containers.filter { text($0, ["ContainerReference"]) == containerID }
        guard matchingContainers.count == 1, let container = matchingContainers.first,
              let stores = physicalStoreDevices(container) else { return nil }
        let matchingStores = stores.intersection(imageWholeDevices)
        guard matchingStores.count == 1, let whole = matchingStores.first,
              whole.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return whole
    }
    public func imageIsDetached() -> Bool {
        imageInventoryMatchCount(for: policy.imagePath) == 0
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
    private let commandRunner: HESectoriumCommandRunning
    private let sectoriumDeviceObserver: SectoriumDeviceObserving?
    private let wholeDeviceEjectDriverOverride: WholeDeviceEjectDriving?
    private let sectoriumDeviceIOSampler: SectoriumDeviceIOCounterSampling
    private let progressLock = NSLock(); private var currentProgress: HESectoriumOperationProgress = .idle
    private var activeProgress: [String: Int] = [:]
    private var selectedSectoriumDeviceID: String?
    private var selectedSectoriumBSDName: String?
    private var selectedSectoriumObservedDevice: SectoriumPhysicalDevice?
    private var selectedSectoriumProfileID: String?
    private var configurationValid: Bool
    private let explicitIdentityPolicy: Bool
    private var lastAction = "No action recorded"; private var diagnostics: [HESectoriumDiagnostic] = []
    public init(paths: HESectoriumPaths = .user, backend: StorageBackend? = nil, store: DurableStateStore? = nil,
                operationLock: OperationLock? = nil, installer: HESectoriumInstaller? = nil,
                runner: HESectoriumCommandRunning = ProcessCommandRunner(), identityPolicy: StorageIdentityPolicy? = nil,
                agentStatusProvider: HESectoriumAgentStatusProviding = UnknownAgentStatusProvider(),
                sectoriumDeviceObserver: SectoriumDeviceObserving? = nil,
                sectoriumDeviceIOSampler: SectoriumDeviceIOCounterSampling? = nil,
                wholeDeviceEjectDriverOverride: WholeDeviceEjectDriving? = nil) {
        self.paths = paths; self.commandRunner = runner
        self.sectoriumDeviceObserver = sectoriumDeviceObserver
        self.wholeDeviceEjectDriverOverride = wholeDeviceEjectDriverOverride
        self.sectoriumDeviceIOSampler = sectoriumDeviceIOSampler ?? makeSystemSectoriumDeviceIOSampler()
        let resolvedStore = store ?? JSONStateStore(url: paths.state); self.store = resolvedStore
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
    public func observeSectoriumDevices() throws -> [SectoriumPhysicalDevice] {
        if let sectoriumDeviceObserver { return try sectoriumDeviceObserver.observeDevices() }
        return try SystemSectoriumDeviceObserver(runner: commandRunner, workingDirectory: FileManager.default.temporaryDirectory)
            .observeDevices()
    }
    /// Samples only a previously selected, identity-verified whole disk. The fresh targeted
    /// diskutil identity check prevents a reused BSD name from redirecting sampling.
    public func sampleSectoriumDeviceCounters(for device: SectoriumPhysicalDevice) -> SectoriumDeviceIOCounters? {
        guard device.identityVerified, let expectedID = device.wholeMediaUUID,
              device.bsdName.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        let outcome = commandRunner.run("/usr/sbin/diskutil", ["info", "-plist", "/dev/\(device.bsdName)"],
                                        cwd: paths.workingDirectory)
        guard outcome.succeeded, let data = outcome.detail.data(using: .utf8),
              let info = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              info["DeviceIdentifier"] as? String == device.bsdName,
              let raw = (info["DiskUUID"] as? String) ?? (info["MediaUUID"] as? String) ?? (info["DeviceUUID"] as? String),
              UUID(uuidString: raw) == expectedID else { return nil }
        return sectoriumDeviceIOSampler.counters(forWholeBSDName: device.bsdName, expectedMediaID: expectedID)
    }
    public func sectoriumProfiles() -> [SectoriumDevelopmentProfile] {
        serial.lock(); defer { serial.unlock() }
        return readSectoriumProfiles() ?? []
    }

    private func readSectoriumProfiles() -> [SectoriumDevelopmentProfile]? {
        guard paths.sectoriumProfiles.standardizedFileURL.path == paths.sectoriumProfiles.resolvingSymlinksInPath().path else { return nil }
        if !FileManager.default.fileExists(atPath: paths.sectoriumProfiles.path) { return [] }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: paths.sectoriumProfiles.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              let data = try? Data(contentsOf: paths.sectoriumProfiles),
              let profiles = try? JSONDecoder().decode([SectoriumDevelopmentProfile].self, from: data) else { return nil }
        return profiles
    }

    /// Read-only compatibility discovery; it never registers or adopts a profile.
    public func discoveredLegacyDevelopmentDisk() -> Bool {
        guard identityConfigurationReady, sectoriumProfiles().isEmpty,
              let observation = backend.observe() else { return false }
        if case .success = coreController.identityPolicy.validate(observation) { return true }
        return false
    }

    /// Read-only presentation facts. A configured child is not an adoption or
    /// mutation credential, and an absent observation is not proof of detach.
    public struct LegacyDevelopmentDisplay: Equatable, Sendable {
        public enum State: Equatable, Sendable { case mounted, unmounted, unknown }
        public let name: String
        public let state: State
        public let mountPoint: String?
        public let logicalCapacityBytes: UInt64?
        public let usedBytes: UInt64?
        public let freeBytes: UInt64?
        public init(name: String, mountPoint: String?, logicalCapacityBytes: UInt64?,
                    state: State = .mounted, usedBytes: UInt64? = nil, freeBytes: UInt64? = nil) {
            self.name = name; self.state = state; self.mountPoint = mountPoint
            self.logicalCapacityBytes = logicalCapacityBytes
            self.usedBytes = usedBytes; self.freeBytes = freeBytes
        }
    }

    /// A configured legacy image may remain visible under its freshly verified
    /// backing parent when detached. Only a complete validated image/APFS chain
    /// supplies mounted state or current logical capacity.
    public func legacyDevelopmentDisplay(deviceID: String?, devices: [SectoriumPhysicalDevice]) -> LegacyDevelopmentDisplay? {
        guard let deviceID, devices.filter({ $0.id == deviceID }).count == 1,
              let device = devices.first(where: { $0.id == deviceID }),
              device.isVirtual == false, device.identityVerified,
              !(device.identityBasis == .uniqueBackingVolumeUUID
                && selectedSectoriumDeviceID == deviceID
                && !selectedAnchorMatches(device)),
              !sectoriumProfiles().contains(where: { $0.deviceID == deviceID }),
              identityConfigurationReady,
              let backing = verifiedBackingVolume(URL(fileURLWithPath: coreController.identityPolicy.outerMountPoint), on: device),
              backing.uuid == coreController.identityPolicy.outerUUID else { return nil }
        let policy = coreController.identityPolicy
        if let observation = backend.observe() {
            if case .success = policy.validate(observation), let devUUID = observation.dev.uuid {
                let matching = devices.filter { $0.isVirtual == true }.flatMap(\.volumeMembers).filter {
                    $0.volumeUUID == devUUID
                }
                let capacity = matching.count == 1 && matching[0].mountPoint == observation.dev.mountPoint
                    ? matching[0].capacityBytes : nil
                return .init(name: observation.dev.name, mountPoint: observation.dev.mountPoint,
                             logicalCapacityBytes: capacity, state: .mounted)
            }
            return .init(name: policy.devVolumeName, mountPoint: nil,
                         logicalCapacityBytes: nil, state: .unknown)
        }
        let inventoryCount = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            .imageInventoryMatchCount(for: policy.imagePath)
        return .init(name: policy.devVolumeName, mountPoint: nil, logicalCapacityBytes: nil,
                     state: inventoryCount == 0 ? .unmounted : .unknown)
    }

    /// Compatibility predicate retains its original strict mounted-chain meaning.
    public func discoveredLegacyDevelopmentDisk(deviceID: String?, devices: [SectoriumPhysicalDevice]) -> Bool {
        legacyDevelopmentDisplay(deviceID: deviceID, devices: devices)?.state == .mounted
    }

    public func pendingSectoriumOperation() -> String? {
        serial.lock(); defer { serial.unlock() }
        guard let state = try? store.load() else { return nil }
        return state.workbenchOperation ?? (state.ejectIntent ? "eject:intent-pending" : nil)
    }

    public func sectoriumReadiness(deviceID: String?, selectedProfileID: String? = nil,
                                   devices: [SectoriumPhysicalDevice],
                                   profiles: [SectoriumDevelopmentProfile]) -> SectoriumWorkbenchReadiness {
        if let pending = pendingSectoriumOperation() { return .operationInProgress(pending) }
        guard let deviceID else { return .noDevice }
        guard let device = devices.first(where: { $0.id == deviceID }) else { return .ejected }
        guard device.identityVerified else { return .unknown("Physical device identity is unavailable") }
        if device.identityBasis == .uniqueBackingVolumeUUID,
           selectedSectoriumDeviceID == deviceID,
           !selectedAnchorMatches(device) {
            return .unknown("Drive attachment or topology changed; reselect the physical drive before management")
        }
        let deviceProfiles = profiles.filter { $0.deviceID == deviceID }
        guard !deviceProfiles.isEmpty else {
            guard let legacy = legacyDevelopmentDisplay(deviceID: deviceID, devices: devices) else {
                return .noDevelopmentDisk
            }
            switch legacy.state {
            case .mounted: return .connected
            case .unmounted: return .notStarted
            case .unknown: return .unknown("Configured development disk state could not be verified")
            }
        }
        let profile = selectedProfileID.flatMap { selectedID in
            deviceProfiles.first(where: { $0.id == selectedID })
        } ?? (selectedProfileID == nil && deviceProfiles.count == 1 ? deviceProfiles[0] : nil)
        guard let profile else { return .unknown("Select a development profile to verify readiness") }
        guard profile.hasVerifiedImageFormat else {
            return .unknown("The selected image format has not been verified")
        }
        guard let policy = profilePolicy(profile), device.volumeUUIDs.contains(profile.backingVolumeUUID),
              verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid == profile.backingVolumeUUID else {
            return .unknown("Backing volume identity could not be freshly verified")
        }
        let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
        if let observation = backend.observe() {
            if !observation.dev.writable { return .readOnly }
            if case .success = policy.validate(observation) { return .ready }
            return .unknown("Mounted development disk identity or backing relation does not match")
        }
        if backend.imageIsDetached() { return .notStarted }
        return .unknown("Development disk state could not be verified")
    }

    public func selectSectoriumDevice(_ id: String?, observedBSDName: String? = nil,
                                      observedDevice: SectoriumPhysicalDevice? = nil) {
        serial.lock(); defer { serial.unlock() }
        selectedSectoriumDeviceID = id
        selectedSectoriumBSDName = id == nil ? nil : observedBSDName
        selectedSectoriumObservedDevice = observedDevice?.id == id ? observedDevice : nil
        let matches = sectoriumProfiles().filter { $0.deviceID == id }
        selectedSectoriumProfileID = matches.count == 1 ? matches.first?.id : nil
    }

    public func selectSectoriumProfile(_ id: String?) {
        serial.lock(); defer { serial.unlock() }
        guard let id, let profile = sectoriumProfiles().first(where: { $0.id == id }),
              profile.deviceID == selectedSectoriumDeviceID else {
            selectedSectoriumProfileID = nil
            return
        }
        selectedSectoriumProfileID = id
    }

    private func workbenchOperation(_ action: String,
                                    _ body: (String, inout [OperationStepResult]) -> OperationResult) -> OperationResult {
        withProgress("sectorium.\(action)") {
            serial.lock(); defer { serial.unlock() }
            let id = UUID().uuidString
            guard lock.acquire() else { return workbenchFailure(id, [], "Another storage operation is running") }
            defer { lock.release() }
            var steps: [OperationStepResult] = []
            guard let state = try? store.load() else { return workbenchFailure(id, steps, "Durable operation state is unavailable") }
            if action != "resume", state.workbenchOperation != nil {
                return workbenchFailure(id, steps, "An interrupted workbench operation must be resumed first")
            }
            if state.workbenchOperation == nil, !setWorkbenchMarker("\(action):\(id)") {
                return workbenchFailure(id, steps, "Could not persist operation intent")
            }
            let result = body(id, &steps)
            if result.failure != nil {
                _ = persistValidationRejectionIfUnmutated(action: action, id: id, result: result)
            }
            lastAction = result.failure.map { "Failed: \($0)" } ?? "Completed \(action)"
            diagnostics.append(.init(category: "sectorium", summary: lastAction))
            diagnostics = Array(diagnostics.suffix(20))
            return result
        }
    }

    private func workbenchFailure(_ id: String, _ steps: [OperationStepResult], _ message: String) -> OperationResult {
        OperationResult(operationID: id, mode: .manual, steps: steps,
                        failure: .workbenchFailed(String(message.prefix(240))))
    }

    private func selectedProfile() -> SectoriumDevelopmentProfile? {
        let profiles = sectoriumProfiles()
        guard let selectedSectoriumDeviceID else { return profiles.count == 1 ? profiles.first : nil }
        let matches = profiles.filter { $0.deviceID == selectedSectoriumDeviceID }
        guard let selectedSectoriumProfileID else { return matches.count == 1 ? matches.first : nil }
        return matches.first { $0.id == selectedSectoriumProfileID }
    }

    private func selectedAnchorMatches(_ device: SectoriumPhysicalDevice) -> Bool {
        guard selectedSectoriumDeviceID == device.id,
              selectedSectoriumBSDName == device.bsdName,
              let selected = selectedSectoriumObservedDevice else { return false }
        return selected.id == device.id && selected.bsdName == device.bsdName
            && selected.identityBasis == device.identityBasis
            && selected.isExternal == device.isExternal && selected.isVirtual == device.isVirtual
            && selected.wholeDeviceBytes == device.wholeDeviceBytes
            && selected.topologyComplete == device.topologyComplete
            && selected.volumeMembers.count == device.volumeMembers.count
            && zip(selected.volumeMembers, device.volumeMembers).allSatisfy { old, fresh in
                old.volumeUUID == fresh.volumeUUID && old.bsdName == fresh.bsdName
                    && old.mountPoint == fresh.mountPoint
            }
            && selected.apfsContainers == device.apfsContainers
    }

    private func verifiedDevice(_ identifier: String) -> SectoriumPhysicalDevice? {
        guard let devices = try? observeSectoriumDevices() else { return nil }
        let matches = devices.filter { $0.id == identifier }
        guard matches.count == 1, let device = matches.first, device.identityVerified else { return nil }
        if device.identityBasis == .uniqueBackingVolumeUUID {
            guard selectedAnchorMatches(device) else { return nil }
        }
        return device
    }

    private func verifiedBackingVolume(_ location: URL, on device: SectoriumPhysicalDevice) -> (uuid: UUID, mountPoint: String)? {
        let standardized = location.standardizedFileURL
        guard standardized.path == standardized.resolvingSymlinksInPath().path,
              let mount = device.mountedVolumePaths.first(where: {
                  standardized.path == $0 || standardized.path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/")
              }),
              let data = verifiedDiskInfoData(for: mount),
              let info = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let raw = (info["VolumeUUID"] as? String) ?? (info["APFSVolumeUUID"] as? String),
              let uuid = UUID(uuidString: raw), device.volumeUUIDs.contains(uuid),
              let observedMount = info["MountPoint"] as? String, observedMount == mount else { return nil }
        if device.requiresFreshParentCheck || device.identityBasis == .uniqueBackingVolumeUUID {
            guard (device.identityBasis != .uniqueBackingVolumeUUID || UUID(uuidString: device.id) == uuid),
                  device.volumeMembers.filter({ $0.volumeUUID == uuid }).count == 1,
                  let member = device.volumeMembers.first(where: { $0.volumeUUID == uuid }),
                  info["DeviceIdentifier"] as? String == member.bsdName,
                  SectoriumDeviceCatalog.verifiedParentWholeDisk(info) == device.bsdName else {
                return nil
            }
        }
        return (uuid, mount)
    }

    private func verifiedDiskInfoData(for mount: String) -> Data? {
        let outcome = commandRunner.run("/usr/sbin/diskutil", ["info", "-plist", mount], cwd: paths.workingDirectory)
        guard outcome.succeeded else { return nil }
        return outcome.detail.data(using: .utf8)
    }

    private func isPlainDirectory(_ url: URL) -> Bool {
        guard url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeDirectory else { return false }
        return true
    }

    private func saveProfile(_ profile: SectoriumDevelopmentProfile) throws {
        try SecureDirectory.ensure(paths.root)
        if FileManager.default.fileExists(atPath: paths.sectoriumProfiles.path) {
            guard paths.sectoriumProfiles.standardizedFileURL.path == paths.sectoriumProfiles.resolvingSymlinksInPath().path,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: paths.sectoriumProfiles.path),
                  (attrs[.type] as? FileAttributeType) == .typeRegular else {
                throw RuntimeError.unsafePath("profile registry is not a plain file")
            }
        }
        var profiles = sectoriumProfiles()
        profiles.removeAll { $0.id == profile.id || $0.imagePath == profile.imagePath }
        profiles.append(profile)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: paths.sectoriumProfiles, options: .atomic)
        if selectedSectoriumDeviceID == profile.deviceID { selectedSectoriumProfileID = profile.id }
        #if canImport(Darwin)
        guard chmod(paths.sectoriumProfiles.path, mode_t(0o600)) == 0 else { throw RuntimeError.unsafePath("cannot secure profile registry") }
        #endif
    }

    private func setWorkbenchMarker(_ marker: String) -> Bool {
        guard let state = try? store.load(), state.workbenchOperation == nil else { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, workbenchOperation: marker,
            workbenchPhase: "validating", workbenchTarget: nil, workbenchCompletedStep: nil,
            workbenchTerminalResult: nil)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: updated)) == true
    }

    /// Records an irreversible boundary before invoking any mutating storage/profile operation.
    /// The original central marker remains present throughout the operation.
    private func beginWorkbenchMutation(operation: String, target: String?, step: String) -> Bool {
        guard let state = try? store.load(), let marker = state.workbenchOperation,
              marker == operation || marker.hasSuffix(":\(operation)") else { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, workbenchOperation: marker,
            workbenchPhase: "mutating:\(step)", workbenchTarget: target ?? state.workbenchTarget,
            workbenchCompletedStep: state.workbenchCompletedStep, workbenchTerminalResult: nil)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: updated)) == true
    }

    private func completeWorkbenchStep(operation: String, step: String) -> Bool {
        guard let state = try? store.load(), let marker = state.workbenchOperation,
              marker == operation || marker.hasSuffix(":\(operation)") else { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, workbenchOperation: marker,
            workbenchPhase: "mutating", workbenchTarget: state.workbenchTarget,
            workbenchCompletedStep: step, workbenchTerminalResult: state.workbenchTerminalResult)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: updated)) == true
    }

    private func recordWorkbenchTarget(operation: String, target: String) -> Bool {
        guard let state = try? store.load(), let marker = state.workbenchOperation,
              marker == operation || marker.hasSuffix(":\(operation)"),
              state.workbenchPhase == "validating" else { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, workbenchOperation: state.workbenchOperation,
            workbenchPhase: state.workbenchPhase, workbenchTarget: String(target.prefix(512)),
            workbenchCompletedStep: nil, workbenchTerminalResult: nil)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: updated)) == true
    }

    /// A failed operation can be marked terminal without mutation only while its durable journal
    /// still says validating. Mutation sites must call beginWorkbenchMutation first.
    private func persistValidationRejectionIfUnmutated(action: String, id: String,
                                                       result: OperationResult) -> Bool {
        guard let state = try? store.load(), state.workbenchOperation == "\(action):\(id)",
              state.workbenchPhase == "validating", state.workbenchCompletedStep == nil else { return false }
        let terminal = String(String(describing: result.failure ?? .workbenchFailed("validation failed")).prefix(180))
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, workbenchOperation: state.workbenchOperation,
            workbenchPhase: "validation-rejected", workbenchTarget: state.workbenchTarget,
            workbenchCompletedStep: nil, workbenchTerminalResult: terminal)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: updated)) == true
    }

    private func resolveValidationRejection(_ marker: String) -> Bool {
        guard let state = try? store.load(), state.workbenchOperation == marker,
              state.workbenchPhase == "validation-rejected", state.workbenchCompletedStep == nil,
              state.workbenchTerminalResult != nil else { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, workbenchOperation: nil,
            workbenchPhase: "validation-rejection-resolved", workbenchTarget: state.workbenchTarget,
            workbenchCompletedStep: nil, workbenchTerminalResult: state.workbenchTerminalResult)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: updated)) == true
    }

    private func beginEjectIntent(operationID: String, target: String) -> Bool {
        guard let state = try? store.load(), !state.ejectIntent,
              state.workbenchOperation == "eject:\(operationID)",
              state.workbenchPhase == "validating", state.workbenchTarget == target,
              state.workbenchCompletedStep == nil else { return false }
        let next = StoragePersistentState(revision: state.revision + 1, ejectIntent: true,
            operationID: operationID, outerDisappearedAfterIntent: false, outerReconnectAttempted: false,
            workbenchOperation: state.workbenchOperation, workbenchPhase: "mutating:persistEjectIntent",
            workbenchTarget: target, workbenchCompletedStep: nil, workbenchTerminalResult: nil)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func markOuterAbsentAfterEject() -> Bool {
        guard let state = try? store.load(), state.ejectIntent else { return false }
        let next = StoragePersistentState(revision: state.revision + 1, ejectIntent: true,
            operationID: state.operationID, outerDisappearedAfterIntent: true, outerReconnectAttempted: false,
            workbenchOperation: state.workbenchOperation, workbenchPhase: state.workbenchPhase,
            workbenchTarget: state.workbenchTarget, workbenchCompletedStep: state.workbenchCompletedStep,
            workbenchTerminalResult: state.workbenchTerminalResult)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func clearEjectIntent() -> Bool {
        guard let state = try? store.load(), state.ejectIntent else { return false }
        let next = StoragePersistentState(revision: state.revision + 1, ejectIntent: false,
            operationID: state.operationID, outerDisappearedAfterIntent: false, outerReconnectAttempted: false,
            workbenchOperation: state.workbenchOperation, workbenchPhase: state.workbenchPhase,
            workbenchTarget: state.workbenchTarget, workbenchCompletedStep: state.workbenchCompletedStep,
            workbenchTerminalResult: state.workbenchTerminalResult)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func clearWorkbenchMarker() -> Bool {
        guard let state = try? store.load() else { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, workbenchOperation: nil,
            workbenchPhase: "completed", workbenchTarget: state.workbenchTarget,
            workbenchCompletedStep: state.workbenchCompletedStep, workbenchTerminalResult: "completed")
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: updated)) == true
    }

    /// Cancels only the durable pre-intent validation marker. In this phase no storage command has
    /// been dispatched; a recorded target is still checked against a fresh external-device identity.
    private func cancelUncommittedEject(_ state: StoragePersistentState) -> Bool {
        guard !state.ejectIntent, state.operationID == nil,
              let marker = state.workbenchOperation, marker.hasPrefix("eject:"),
              UUID(uuidString: String(marker.dropFirst("eject:".count))) != nil,
              state.workbenchPhase == "validating", state.workbenchCompletedStep == nil,
              state.workbenchTerminalResult == nil,
              !state.outerDisappearedAfterIntent, !state.outerReconnectAttempted else { return false }
        if let target = state.workbenchTarget {
            guard !target.isEmpty,
                  let profile = selectedProfile(),
                  let device = verifiedDevice(profile.deviceID),
                  device.isExternal, device.identityVerified, device.id == target,
                  device.volumeUUIDs.contains(profile.backingVolumeUUID),
                  verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid == profile.backingVolumeUUID else {
                return false
            }
        }
        let cancelled = StoragePersistentState(revision: state.revision + 1, ejectIntent: false,
            operationID: nil, outerDisappearedAfterIntent: false, outerReconnectAttempted: false,
            workbenchOperation: nil, workbenchPhase: "pre-intent-eject-cancelled",
            workbenchTarget: state.workbenchTarget, workbenchCompletedStep: nil,
            workbenchTerminalResult: "Cancelled before eject intent; no storage mutation was dispatched")
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: cancelled)) == true
    }

    private func profilePolicy(_ profile: SectoriumDevelopmentProfile) -> StorageIdentityPolicy? {
        let configured = coreController.identityPolicy
        if profile.backingVolumeUUID == configured.outerUUID,
           profile.backingMountPoint == configured.outerMountPoint,
           profile.imagePath == configured.imagePath,
           profile.devUUID == configured.devUUID,
           profile.devMountPoint == configured.devMountPoint,
           profile.devVolumeName == configured.devVolumeName,
           profile.name == configured.devVolumeName {
            return configured
        }
        guard profile.name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$"#, options: .regularExpression) != nil,
              profile.imagePath.hasPrefix(profile.backingMountPoint + "/"),
              !profile.devVolumeName.isEmpty, !profile.devVolumeName.contains("/"),
              URL(fileURLWithPath: profile.devMountPoint).standardizedFileURL.path == profile.devMountPoint else { return nil }
        return StorageIdentityPolicy(outerUUID: profile.backingVolumeUUID, devUUID: profile.devUUID,
            outerMountPoint: profile.backingMountPoint, devMountPoint: profile.devMountPoint,
            devVolumeName: profile.devVolumeName, imagePath: profile.imagePath)
    }

    public func createDevelopmentDisk(deviceID: String, parentDirectory: URL, name: String, capacityGiB: Int,
                                      caseSensitive: Bool, password: String?) -> OperationResult {
        workbenchOperation("create") { id, steps in
            guard recordWorkbenchTarget(operation: id, target: "\(deviceID):\(parentDirectory.path)/\(name)") else {
                return workbenchFailure(id, steps, "Could not persist the selected create target")
            }
            guard capacityGiB > 0, capacityGiB <= 16_384,
                  name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$"#, options: .regularExpression) != nil else {
                return workbenchFailure(id, steps, "Invalid name or capacity")
            }
            guard password == nil || (hdiutilPassphraseInput(password!) != nil && commandRunner is HESectoriumSecureCommandRunning) else {
                return workbenchFailure(id, steps, "Encrypted creation requires a secure stdin command runner")
            }
            guard let device = verifiedDevice(deviceID), let backing = verifiedBackingVolume(parentDirectory, on: device),
                  isPlainDirectory(parentDirectory) else { return workbenchFailure(id, steps, "Selected location is not on the verified drive") }
            let image = parentDirectory.appendingPathComponent("\(name).sparsebundle", isDirectory: true).standardizedFileURL
            guard image.deletingLastPathComponent().resolvingSymlinksInPath().path == parentDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
                  !FileManager.default.fileExists(atPath: image.path),
                  !sectoriumProfiles().contains(where: { $0.imagePath == image.path || $0.deviceID == deviceID && $0.name == name }) else {
                return workbenchFailure(id, steps, "Target already exists or is registered")
            }
            let mount = "/Volumes/\(name)-DEV"
            guard !FileManager.default.fileExists(atPath: mount) else { return workbenchFailure(id, steps, "Development volume mount point is already in use") }
            let profile = SectoriumDevelopmentProfile(name: name, deviceID: deviceID, backingVolumeUUID: backing.uuid,
                backingMountPoint: backing.mountPoint, imagePath: image.path, devVolumeName: name,
                devMountPoint: mount, encrypted: password != nil, caseSensitive: caseSensitive,
                logicalCapacityBytes: UInt64(capacityGiB) * 1_073_741_824)
            guard beginWorkbenchMutation(operation: id, target: image.path, step: "recordProfile") else {
                return workbenchFailure(id, steps, "Could not persist the profile mutation boundary")
            }
            do { try saveProfile(profile) } catch { return workbenchFailure(id, steps, "Could not durably record operation: \(error.localizedDescription)") }
            steps.append(.init(step: "recordProfile", status: .succeeded))
            guard completeWorkbenchStep(operation: id, step: "recordProfile") else {
                return workbenchFailure(id, steps, "Profile recorded but its recovery step could not be persisted")
            }
            var args = ["create", "-size", "\(capacityGiB)g", "-type", "SPARSEBUNDLE", "-fs", caseSensitive ? "APFSX" : "APFS", "-volname", name, "-layout", "SPUD"]
            if password != nil { args += ["-encryption", "AES-256", "-stdinpass"] }
            args.append(image.path)
            guard beginWorkbenchMutation(operation: id, target: image.path, step: "createSparsebundle") else {
                return workbenchFailure(id, steps, "Could not persist the image-creation boundary")
            }
            let outcome: CommandOutcome
            if let password, let secureRunner = commandRunner as? HESectoriumSecureCommandRunning {
                guard let input = hdiutilPassphraseInput(password) else {
                    return workbenchFailure(id, steps, "Encrypted creation requires a valid passphrase")
                }
                outcome = secureRunner.run("/usr/bin/hdiutil", args, cwd: paths.workingDirectory,
                                          standardInput: input)
            } else { outcome = commandRunner.run("/usr/bin/hdiutil", args, cwd: paths.workingDirectory) }
            let succeeded = outcome.succeeded && FileManager.default.fileExists(atPath: image.path)
            steps.append(.init(step: "createSparsebundle", status: succeeded ? .succeeded : .failed,
                               detail: password == nil ? String(outcome.detail.prefix(180)) : "Encrypted image creation returned \(outcome.exitCode)"))
            if succeeded, !completeWorkbenchStep(operation: id, step: "createSparsebundle") {
                return workbenchFailure(id, steps, "Image created but its recovery step could not be persisted")
            }
            guard succeeded else { return workbenchFailure(id, steps, "Image creation failed; profile retained for recovery") }
            let formatOutcome = commandRunner.run("/usr/bin/hdiutil", ["imageinfo", image.path, "-format"], cwd: paths.workingDirectory)
            guard formatOutcome.succeeded, let imageFormat = Self.documentedSparsebundleFormat(formatOutcome.detail) else {
                steps.append(.init(step: "verifyImageFormat", status: .failed,
                                   detail: "Image format observation failed or returned an unsupported format; operation remains recoverable"))
                return workbenchFailure(id, steps, "Created image format could not be verified")
            }
            let verifiedProfile = SectoriumDevelopmentProfile(id: profile.id, name: profile.name, deviceID: profile.deviceID,
                backingVolumeUUID: profile.backingVolumeUUID, backingMountPoint: profile.backingMountPoint,
                imagePath: profile.imagePath, devVolumeName: profile.devVolumeName, devMountPoint: profile.devMountPoint,
                devUUID: profile.devUUID, encrypted: profile.encrypted, caseSensitive: profile.caseSensitive,
                logicalCapacityBytes: profile.logicalCapacityBytes, imageFormat: imageFormat, validation: profile.validation)
            do { try saveProfile(verifiedProfile) }
            catch {
                steps.append(.init(step: "verifyImageFormat", status: .failed, detail: "Verified format could not be durably recorded"))
                return workbenchFailure(id, steps, "Verified image format could not be durably recorded")
            }
            steps.append(.init(step: "verifyImageFormat", status: .succeeded, detail: imageFormat))
            guard clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Image created but operation marker could not be cleared") }
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    /// hdiutil's documented `imageinfo -format` output is accepted only as the exact
    /// sparse-bundle format token this workflow creates; no suffix or plist-key inference.
    static func documentedSparsebundleFormat(_ output: String) -> String? {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "UDSB" ? value : nil
    }

    public func adoptDevelopmentDisk(deviceID: String, imageURL: URL) -> OperationResult {
        workbenchOperation("adopt") { id, steps in
            guard recordWorkbenchTarget(operation: id, target: "\(deviceID):\(imageURL.path)") else {
                return workbenchFailure(id, steps, "Could not persist the selected adoption target")
            }
            let configured = coreController.identityPolicy
            let configuredOuter = URL(fileURLWithPath: configured.outerMountPoint).standardizedFileURL.resolvingSymlinksInPath().path
            let configuredDEV = URL(fileURLWithPath: configured.devMountPoint).standardizedFileURL.resolvingSymlinksInPath().path
            let configuredImage = URL(fileURLWithPath: configured.imagePath).standardizedFileURL.resolvingSymlinksInPath().path
            let legacyTuple = configurationValid
                && URL(fileURLWithPath: configuredOuter).lastPathComponent == "HE"
                && configuredDEV == URL(fileURLWithPath: configuredOuter).appendingPathComponent("DEV", isDirectory: true).standardizedFileURL.path
                && configured.devVolumeName == "DEV_APFS"
                && URL(fileURLWithPath: configuredImage).lastPathComponent == ".DEV-APFS.sparsebundle"
            guard let device = verifiedDevice(deviceID), device.identityVerified else {
                return workbenchFailure(id, steps, "Selected physical device identity is not freshly verified")
            }
            let canonicalImage = imageURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
            guard imageURL.standardizedFileURL.path == canonicalImage.path,
                  isPlainDirectory(imageURL), canonicalImage.pathExtension == "sparsebundle" else {
                return workbenchFailure(id, steps, "Selected image is not a canonical plain sparsebundle directory")
            }
            let imagePath = canonicalImage.path
            let imageParent = canonicalImage.deletingLastPathComponent()
            guard let backing = verifiedBackingVolume(imageParent, on: device),
                  device.volumeUUIDs.contains(backing.uuid),
                  imagePath.hasPrefix(backing.mountPoint.hasSuffix("/") ? backing.mountPoint : backing.mountPoint + "/") else {
                return workbenchFailure(id, steps, "Selected image is not on a freshly verified volume of the selected external device")
            }
            let legacyIdentity = legacyTuple && imagePath == configuredImage
                && backing.uuid == configured.outerUUID && backing.mountPoint == configured.outerMountPoint
            let imageName = canonicalImage.deletingPathExtension().lastPathComponent
            let profileName = legacyIdentity ? "DEV_APFS" : imageName
            guard legacyIdentity || profileName.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$"#, options: .regularExpression) != nil else {
                return workbenchFailure(id, steps, "Sparsebundle name is not a supported development profile identity")
            }
            let detachedMountName = legacyIdentity ? "DEV_APFS" : profileName
            let detachedMountPoint = legacyIdentity ? configured.devMountPoint : "/Volumes/\(detachedMountName)-DEV"
            guard !sectoriumProfiles().contains(where: {
                $0.imagePath == imagePath || ($0.deviceID == deviceID && $0.name == profileName)
            }) else {
                return workbenchFailure(id, steps, "Image or profile identity is already registered")
            }
            let inventoryBackend = MacStorageBackend(paths: paths, runner: commandRunner,
                policy: StorageIdentityPolicy(outerUUID: backing.uuid, devUUID: nil, outerMountPoint: backing.mountPoint,
                    devMountPoint: detachedMountPoint, devVolumeName: detachedMountName, imagePath: imagePath))
            guard let inventoryCount = inventoryBackend.imageInventoryMatchCount(for: imagePath), inventoryCount <= 1 else {
                return workbenchFailure(id, steps, "Image inventory is unavailable or contains an ambiguous duplicate identity")
            }
            let isAttached = inventoryCount == 1
            if !legacyIdentity && !isAttached && FileManager.default.fileExists(atPath: detachedMountPoint) {
                return workbenchFailure(id, steps, "Detached image mount point is already occupied")
            }
            var verifiedDevUUID: UUID?
            var devVolumeName = detachedMountName
            var devMountPoint = detachedMountPoint
            var storageBackend = inventoryBackend
            if legacyIdentity {
                guard isAttached, let observation = backend.observe() else {
                    return workbenchFailure(id, steps, "Configured mounted legacy storage observation is unavailable")
                }
                if case .failure(let failure) = configured.validate(observation) {
                    return workbenchFailure(id, steps, "Mounted legacy storage policy rejected the observation: \(failure.rawValue)")
                }
                guard observation.image.path == configured.imagePath,
                      observation.image.backingVolumeUUID == configured.outerUUID,
                      observation.dev.uuid == configured.devUUID,
                      observation.dev.mountPoint == configured.devMountPoint,
                      observation.dev.name == "DEV_APFS", observation.dev.fileSystem.uppercased() == "APFS",
                      observation.dev.writable, observation.dev.rootMatchesExpected else {
                    return workbenchFailure(id, steps, "Mounted legacy DEV_APFS image relation is mismatched")
                }
                verifiedDevUUID = observation.dev.uuid
            } else if isAttached {
                guard let attached = inventoryBackend.attachedImageMountIdentity(for: imagePath) else {
                    return workbenchFailure(id, steps, "Attached image mount point or APFS volume identity is missing or ambiguous")
                }
                devVolumeName = attached.volumeName
                devMountPoint = attached.mountPoint
                let attachedPolicy = StorageIdentityPolicy(outerUUID: backing.uuid, devUUID: attached.volumeUUID,
                    outerMountPoint: backing.mountPoint, devMountPoint: devMountPoint,
                    devVolumeName: devVolumeName, imagePath: imagePath)
                storageBackend = MacStorageBackend(paths: paths, runner: commandRunner,
                    policy: attachedPolicy)
                guard let observation = storageBackend.observe(), case .success = attachedPolicy.validate(observation) else {
                    return workbenchFailure(id, steps, "Attached sparsebundle does not have a unique verified image-to-APFS chain")
                }
                verifiedDevUUID = observation.dev.uuid
            }
            let formatOutcome = commandRunner.run("/usr/bin/hdiutil", ["imageinfo", imagePath, "-format"], cwd: paths.workingDirectory)
            guard formatOutcome.succeeded, let imageFormat = Self.documentedSparsebundleFormat(formatOutcome.detail) else {
                return workbenchFailure(id, steps, "Selected sparsebundle format is unknown or unsupported")
            }
            let profile = SectoriumDevelopmentProfile(
                name: profileName, deviceID: deviceID, backingVolumeUUID: backing.uuid,
                backingMountPoint: backing.mountPoint, imagePath: imagePath,
                devVolumeName: devVolumeName, devMountPoint: devMountPoint,
                devUUID: verifiedDevUUID, encrypted: storageBackend.imageEncryptionState(), caseSensitive: nil,
                logicalCapacityBytes: nil, imageFormat: imageFormat,
                validation: .pendingValidation)
            guard imageURL.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path == imagePath,
                  isPlainDirectory(imageURL),
                  let freshDevice = verifiedDevice(deviceID), freshDevice.identityVerified,
                  freshDevice.isExternal == device.isExternal,
                  let freshBacking = verifiedBackingVolume(imageParent, on: freshDevice),
                  freshBacking.uuid == backing.uuid, freshBacking.mountPoint == backing.mountPoint,
                  inventoryBackend.imageInventoryMatchCount(for: imagePath) == inventoryCount else {
                return workbenchFailure(id, steps, "Selected device, backing volume, image path, or attachment state changed during adoption")
            }
            if isAttached && legacyIdentity {
                guard let freshObservation = backend.observe(), case .success = configured.validate(freshObservation),
                      freshObservation.dev.uuid == verifiedDevUUID,
                      freshObservation.image.path == imagePath,
                      freshObservation.image.backingVolumeUUID == backing.uuid else {
                    return workbenchFailure(id, steps, "Mounted legacy identity changed during adoption")
                }
            } else if isAttached {
                guard let freshIdentity = inventoryBackend.attachedImageMountIdentity(for: imagePath),
                      freshIdentity.volumeUUID == verifiedDevUUID,
                      freshIdentity.mountPoint == devMountPoint,
                      freshIdentity.volumeName == devVolumeName else {
                    return workbenchFailure(id, steps, "Attached image-to-volume identity changed during adoption")
                }
            }
            guard beginWorkbenchMutation(operation: id, target: imagePath, step: "saveVerifiedImageProfile") else {
                return workbenchFailure(id, steps, "Could not persist the profile adoption boundary")
            }
            do { try saveProfile(profile) }
            catch { return workbenchFailure(id, steps, "Could not durably record the verified sparsebundle profile") }
            guard completeWorkbenchStep(operation: id, step: "saveVerifiedImageProfile"), clearWorkbenchMarker() else {
                return workbenchFailure(id, steps, "Profile was recorded but operation recovery state remains pending")
            }
            steps.append(.init(step: "verifyImageIdentity", status: .succeeded,
                detail: isAttached ? "Selected backing volume, sparsebundle format, and attached APFS chain verified; optional image facts remain unknown"
                                   : "Selected backing volume and sparsebundle format verified; image remains detached and APFS identity is pending Start validation"))
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    public func startDevelopmentDisk(password: String? = nil) -> OperationResult {
        workbenchOperation("start") { id, steps in
        guard var profile = selectedProfile() else {
            return workbenchFailure(id, steps, "No explicitly selected development profile is available")
        }
        if profile.imageFormat == nil, profile.encrypted != nil,
           profile.caseSensitive != nil, profile.logicalCapacityBytes != nil {
            guard recordWorkbenchTarget(operation: id, target: "\(profile.deviceID):\(profile.imagePath)") else {
                return workbenchFailure(id, steps, "Could not persist the profile target before format observation")
            }
            let format = commandRunner.run("/usr/bin/hdiutil", ["imageinfo", profile.imagePath, "-format"], cwd: paths.workingDirectory)
            guard format.succeeded, let imageFormat = Self.documentedSparsebundleFormat(format.detail) else {
                return workbenchFailure(id, steps, "Legacy image format could not be verified")
            }
            let upgraded = SectoriumDevelopmentProfile(id: profile.id, name: profile.name, deviceID: profile.deviceID,
                backingVolumeUUID: profile.backingVolumeUUID, backingMountPoint: profile.backingMountPoint,
                imagePath: profile.imagePath, devVolumeName: profile.devVolumeName, devMountPoint: profile.devMountPoint,
                devUUID: profile.devUUID, encrypted: profile.encrypted, caseSensitive: profile.caseSensitive,
                logicalCapacityBytes: profile.logicalCapacityBytes, imageFormat: imageFormat, validation: profile.validation)
            do { try saveProfile(upgraded) }
            catch { return workbenchFailure(id, steps, "Verified legacy format could not be durably recorded") }
            profile = upgraded
            steps.append(.init(step: "verifyImageFormat", status: .succeeded, detail: imageFormat))
        }
        guard profile.hasVerifiedImageFormat,
              let device = verifiedDevice(profile.deviceID),
                  device.volumeUUIDs.contains(profile.backingVolumeUUID),
                  verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid == profile.backingVolumeUUID,
                  profile.imagePath.hasPrefix(profile.backingMountPoint + "/"),
                  FileManager.default.fileExists(atPath: profile.imagePath),
                  URL(fileURLWithPath: profile.imagePath).resolvingSymlinksInPath().path == profile.imagePath else {
                return workbenchFailure(id, steps, "Fresh backing-device and image identity validation failed")
            }
            guard recordWorkbenchTarget(operation: id, target: "\(profile.deviceID):\(profile.imagePath)") else {
                return workbenchFailure(id, steps, "Could not persist the selected start target")
            }
            let policy = profilePolicy(profile)
            guard let policy else { return workbenchFailure(id, steps, "Profile identity is invalid") }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            let encryptionState = profile.encrypted ?? backend.imageEncryptionState()
            guard let encryptionState else {
                return workbenchFailure(id, steps, "Image encryption status could not be verified; no attach was attempted")
            }
            if let password, hdiutilPassphraseInput(password) == nil || !(commandRunner is HESectoriumSecureCommandRunning) {
                return workbenchFailure(id, steps, "Unlock requires a secure stdin command runner")
            }
            if encryptionState {
                guard let password, hdiutilPassphraseInput(password) != nil,
                      commandRunner is HESectoriumSecureCommandRunning else {
                    return workbenchFailure(id, steps, "Encryption is enabled; unlock requires a passphrase over secure stdin")
                }
            }
            guard beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "prepareMountPoint") else {
                return workbenchFailure(id, steps, "Could not persist the mount-point preparation boundary")
            }
            do { try SecureDirectory.ensure(URL(fileURLWithPath: profile.devMountPoint, isDirectory: true)) }
            catch { return workbenchFailure(id, steps, "Could not prepare safe mount point") }
            guard completeWorkbenchStep(operation: id, step: "prepareMountPoint") else {
                return workbenchFailure(id, steps, "Mount point prepared but its recovery step could not be persisted")
            }
            guard beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "attachImage") else {
                return workbenchFailure(id, steps, "Could not persist the image-attach boundary")
            }
            let attached = backend.attachImage(password: password)
            steps.append(.init(step: "attachImage", status: attached.succeeded ? .succeeded : .failed,
                               detail: password == nil ? attached.detail : "Unlock/attach returned \(attached.exitCode)"))
            if attached.succeeded, !completeWorkbenchStep(operation: id, step: "attachImage") {
                return workbenchFailure(id, steps, "Image attached but its recovery step could not be persisted")
            }
            guard attached.succeeded, let observation = backend.observe() else {
                return workbenchFailure(id, steps, "Image-to-backing APFS chain failed post-attach validation")
            }
            let validatedPolicy = StorageIdentityPolicy(outerUUID: profile.backingVolumeUUID,
                devUUID: observation.dev.uuid, outerMountPoint: profile.backingMountPoint,
                devMountPoint: observation.dev.mountPoint, devVolumeName: observation.dev.name,
                imagePath: profile.imagePath)
            guard case .success = validatedPolicy.validate(observation) else {
                return workbenchFailure(id, steps, "Image-to-backing APFS chain failed post-attach validation")
            }
            if profile.devUUID != observation.dev.uuid || profile.devVolumeName != observation.dev.name
                || profile.devMountPoint != observation.dev.mountPoint || profile.encrypted != encryptionState || profile.validation != .validated {
                var validated = profile; validated.devUUID = observation.dev.uuid
                validated.devVolumeName = observation.dev.name; validated.devMountPoint = observation.dev.mountPoint
                validated.encrypted = encryptionState; validated.validation = .validated
                guard beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "saveValidatedProfile") else {
                    return workbenchFailure(id, steps, "Could not persist the profile-validation boundary")
                }
                do { try saveProfile(validated) } catch { return workbenchFailure(id, steps, "Mounted image validated but profile persistence failed") }
                guard completeWorkbenchStep(operation: id, step: "saveValidatedProfile") else {
                    return workbenchFailure(id, steps, "Validated profile saved but its recovery step could not be persisted")
                }
            }
            steps.append(.init(step: "validateImageChain", status: .succeeded, detail: "Mounted writable APFS chain matches selected backing volume"))
            guard clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Mounted successfully but operation marker could not be cleared") }
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    public func prepareStopDevelopmentDiskConfirmation() -> SectoriumStopConfirmation? {
        guard let profile = selectedProfile(), let policy = profilePolicy(profile) else { return nil }
        let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
        guard let observation = backend.observe(), case .success = policy.validate(observation),
              let devUUID = observation.dev.uuid else { return nil }
        return SectoriumStopConfirmation(profileID: profile.id, deviceID: profile.deviceID,
            backingVolumeUUID: profile.backingVolumeUUID, devVolumeUUID: devUUID,
            imagePath: profile.imagePath, observedAt: Date())
    }

    /// The compatibility entrypoint cannot synthesize the deliberate known-writer checkpoint.
    public func stopDevelopmentDisk() -> OperationResult {
        workbenchFailure(UUID().uuidString, [], "Stop requires a fresh identity and known-writer confirmation")
    }

    public func stopDevelopmentDisk(checkpoint: SectoriumStopConfirmation,
                                    knownWritersClosed: Bool) -> OperationResult {
        workbenchOperation("stop") { id, steps in
            guard let profile = selectedProfile(), let policy = profilePolicy(profile) else { return workbenchFailure(id, steps, "No valid development profile selected") }
            guard recordWorkbenchTarget(operation: id, target: "\(profile.deviceID):\(profile.imagePath)") else {
                return workbenchFailure(id, steps, "Could not persist the selected stop target")
            }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            guard let observation = backend.observe(), case .success = policy.validate(observation) else {
                return workbenchFailure(id, steps, "Fresh mounted identity validation failed")
            }
            guard checkpoint.permits(profile, observation, knownWritersClosed: knownWritersClosed) else {
                return workbenchFailure(id, steps, "Stop confirmation is missing, stale, or no longer matches the mounted image")
            }
            guard beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "flush") else { return workbenchFailure(id, steps, "Could not persist the stop boundary") }
            let flush = backend.perform(.flush); steps.append(.init(step: "flush", status: flush.succeeded ? .succeeded : .failed, detail: flush.detail))
            guard flush.succeeded else { return workbenchFailure(id, steps, "Could not flush development volume") }
            guard completeWorkbenchStep(operation: id, step: "flush"),
                  let beforeUnmount = backend.observe(), case .success = policy.validate(beforeUnmount),
                  checkpoint.permits(profile, beforeUnmount, knownWritersClosed: knownWritersClosed),
                  beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "unmountDEV") else { return workbenchFailure(id, steps, "Fresh identity or durable unmount boundary validation failed") }
            let unmount = backend.perform(.unmountDEV); steps.append(.init(step: "unmountDEV", status: unmount.succeeded ? .succeeded : .failed, detail: unmount.detail))
            guard unmount.succeeded else { return workbenchFailure(id, steps, "Could not unmount development volume") }
            guard completeWorkbenchStep(operation: id, step: "unmountDEV"),
                  case .success = policy.validateOuter(backend.observeOuter()),
                  beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "detachImage") else { return workbenchFailure(id, steps, "Outer identity or durable detach boundary validation failed") }
            let detach = backend.perform(.detachImage); steps.append(.init(step: "detachImage", status: detach.succeeded ? .succeeded : .failed, detail: detach.detail))
            guard detach.succeeded, backend.imageIsDetached() else { return workbenchFailure(id, steps, "Image detach is incomplete; operation marker retained") }
            guard completeWorkbenchStep(operation: id, step: "detachImage") else { return workbenchFailure(id, steps, "Image detached but its recovery step could not be persisted") }
            guard clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Stopped, but operation marker could not be cleared") }
            steps.append(.init(step: "verifyImageDetached", status: .succeeded))
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    /// Compatibility route refuses because whole-device eject requires an explicit
    /// observed target/member checkpoint and a known-writer confirmation.
    public func ejectSelectedExternalDevice() -> OperationResult {
        .init(operationID: UUID().uuidString, mode: .manual, steps: [],
              failure: .workbenchFailed("Whole-device eject requires explicit target and writer confirmation"))
    }

    public func prepareWholeDeviceEjectConfirmation() -> SectoriumWholeDeviceEjectConfirmation? {
        guard let selectedSectoriumDeviceID,
              let bound = verifiedDevice(selectedSectoriumDeviceID) else { return nil }
        let driver = makeWholeDeviceEjectDriver()
        guard let observed = driver.observe(physicalIdentity: selectedSectoriumDeviceID),
              observed.bsdName == bound.bsdName else { return nil }
        let dependenciesSafe = SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths,
            targetBSDName: observed.bsdName, runner: commandRunner)
        return SectoriumWholeDeviceEjectConfirmation(topology: observed,
            dependenciesCanFinishOffTarget: dependenciesSafe)
    }

    /// Read-only availability used to keep an unsafe/system target from presenting an enabled
    /// whole-device action. The actual click obtains a new confirmation and repeats validation.
    public func canPrepareWholeDeviceEjectConfirmation() -> Bool {
        prepareWholeDeviceEjectConfirmation() != nil
    }

    /// Presents a fresh, explicit confirmation for the narrowly recoverable physical-unmount
    /// boundary. The original journal target is retained so the user reconfirms the exact scope.
    public func prepareContinueWholeDeviceEjectConfirmation() -> SectoriumWholeDeviceEjectConfirmation? {
        guard let selectedSectoriumDeviceID,
              let state = try? store.load(), state.ejectIntent,
              let journal = decodeEjectJournal(state.workbenchTarget),
              journal.target.physicalIdentity == selectedSectoriumDeviceID,
              journal.lastIssuedAction == .physicalVolumesUnmount,
              journal.phase == .interrupted || journal.phase == .physicalVolumesUnmountIssued
                || journal.phase == .physicalVolumesUnmounted else {
            guard let selectedSectoriumDeviceID,
                  let state = try? store.load(), state.ejectIntent,
                  let journal = decodeEjectJournal(state.workbenchTarget),
                  journal.target.physicalIdentity == selectedSectoriumDeviceID,
                  journal.lastIssuedAction == .ejectWholeDevice, journal.phase == .ejectIssued else { return nil }
            let driver = makeWholeDeviceEjectDriver()
            guard driver.freshEjectIssuedRecovery(journal) != .refused else { return nil }
            let dependencySafe = SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths,
                targetBSDName: journal.target.bsdName, runner: commandRunner)
            return SectoriumWholeDeviceEjectConfirmation(topology: journal.target,
                dependenciesCanFinishOffTarget: dependencySafe, isContinuation: true)
        }
        let driver = makeWholeDeviceEjectDriver()
        guard driver.freshPhysicalContinuationMatches(journal) else { return nil }
        let dependencySafe = SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths,
            targetBSDName: journal.target.bsdName, runner: commandRunner)
        return SectoriumWholeDeviceEjectConfirmation(topology: journal.target,
            dependenciesCanFinishOffTarget: dependencySafe, isContinuation: true)
    }

    /// Availability is advisory and read-only; Return repeats the checks while holding the
    /// shared operation lock before clearing the durable intent.
    public func canReturnFromWholeDeviceEject() -> Bool {
        guard let selectedSectoriumDeviceID,
              let state = try? store.load(), state.ejectIntent,
              let journal = decodeEjectJournal(state.workbenchTarget),
              journal.target.physicalIdentity == selectedSectoriumDeviceID else { return false }
        return coreController.canReturnFromWholeDeviceEject(driver: makeWholeDeviceEjectDriver())
    }

    public func ejectSelectedExternalDevice(checkpoint: WholeDeviceEjectCheckpoint) -> OperationResult {
        let driver = makeWholeDeviceEjectDriver()
        guard let selectedSectoriumDeviceID,
              let bound = verifiedDevice(selectedSectoriumDeviceID),
              let observed = driver.observe(physicalIdentity: selectedSectoriumDeviceID),
              observed.bsdName == bound.bsdName else {
            return workbenchFailure(UUID().uuidString, [], "Selected external device identity or complete related-member inventory is unavailable")
        }
        let dependencySafe = SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths,
            targetBSDName: observed.bsdName, runner: commandRunner)
        let acceptedCheckpoint = WholeDeviceEjectCheckpoint(
            confirmedExactTargetAndScope: checkpoint.confirmedExactTargetAndScope,
            knownWritersClosed: checkpoint.knownWritersClosed,
            dependenciesCanFinishOffTarget: checkpoint.dependenciesCanFinishOffTarget && dependencySafe,
            confirmedPhysicalIdentity: checkpoint.confirmedPhysicalIdentity,
            confirmedMemberKey: checkpoint.confirmedMemberKey, confirmedAt: checkpoint.confirmedAt)
        let result = coreController.ejectWholeExternalDevice(physicalIdentity: selectedSectoriumDeviceID,
            checkpoint: acceptedCheckpoint, driver: driver)
        let steps = result.completedSteps.map {
            OperationStepResult(step: $0, status: .succeeded, detail: "Verified by the isolated whole-device protocol")
        }
        if let failure = result.failure {
            return workbenchFailure(result.operationID, steps, "Whole-device eject stopped safely: \(failure)")
        }
        return .init(operationID: result.operationID, mode: .manual, steps: steps)
    }

    public func continueWholeDeviceEject(checkpoint: WholeDeviceEjectCheckpoint) -> OperationResult {
        let driver = makeWholeDeviceEjectDriver()
        guard let selectedSectoriumDeviceID,
              let state = try? store.load(), state.ejectIntent,
              let journal = decodeEjectJournal(state.workbenchTarget),
              journal.target.physicalIdentity == selectedSectoriumDeviceID,
              continuationRecoveryIsFresh(journal, driver: driver) else {
            return workbenchFailure(UUID().uuidString, [], "Physical-eject continuation no longer matches its durable recovery journal")
        }
        let dependencySafe = SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths,
            targetBSDName: journal.target.bsdName, runner: commandRunner)
        let acceptedCheckpoint = WholeDeviceEjectCheckpoint(
            confirmedExactTargetAndScope: checkpoint.confirmedExactTargetAndScope,
            knownWritersClosed: checkpoint.knownWritersClosed,
            dependenciesCanFinishOffTarget: checkpoint.dependenciesCanFinishOffTarget && dependencySafe,
            confirmedPhysicalIdentity: checkpoint.confirmedPhysicalIdentity,
            confirmedMemberKey: checkpoint.confirmedMemberKey, confirmedAt: checkpoint.confirmedAt)
        let result = coreController.continueWholeExternalDeviceEject(checkpoint: acceptedCheckpoint, driver: driver)
        let steps = result.completedSteps.map {
            OperationStepResult(step: $0, status: .succeeded, detail: "Verified by the isolated whole-device recovery protocol")
        }
        if let failure = result.failure {
            return workbenchFailure(result.operationID, steps, "Whole-device eject continuation stopped safely: \(failure)")
        }
        return .init(operationID: result.operationID, mode: .manual, steps: steps)
    }

    private func makeWholeDeviceEjectDriver() -> WholeDeviceEjectDriving {
        if let override = wholeDeviceEjectDriverOverride { return override }
        let observer = sectoriumDeviceObserver ?? SystemSectoriumDeviceObserver(runner: commandRunner,
            workingDirectory: paths.workingDirectory)
        return SectoriumWholeDeviceEjectDriver(observer: observer, runner: commandRunner,
            workingDirectory: paths.workingDirectory, independentReturnValidator: { [weak self] journal in
                guard let self, let profiles = self.readSectoriumProfiles() else { return false }
                let matches = profiles.filter { $0.deviceID == journal.target.physicalIdentity }
                if matches.isEmpty { return journal.target.images.isEmpty }
                guard Set(matches.map(\.id)).count == matches.count,
                      Set(matches.map(\.imagePath)).count == matches.count else { return false }
                let targetVolumes = Set(journal.target.volumes.compactMap { row -> UUID? in
                    guard let divider = row.identity.firstIndex(of: "|") else { return nil }
                    return UUID(uuidString: String(row.identity[..<divider]))
                })
                let journalImageVolumes = journal.target.images.flatMap(\.volumeIdentities)
                let journalImageUUIDs = Set(journalImageVolumes.compactMap { identity -> UUID? in
                    guard let divider = identity.firstIndex(of: "|") else { return nil }
                    return UUID(uuidString: String(identity[..<divider]))
                })
                let profileImageUUIDs = Set(matches.compactMap(\.devUUID))
                guard journalImageUUIDs.count == journalImageVolumes.count,
                      profileImageUUIDs == journalImageUUIDs else { return false }
                guard let device = self.verifiedDevice(journal.target.physicalIdentity),
                      device.isExternal, device.identityVerified else { return false }
                return matches.allSatisfy { profile in
                    guard let policy = self.profilePolicy(profile),
                          targetVolumes.contains(profile.backingVolumeUUID),
                          let backing = self.verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device),
                          backing.uuid == profile.backingVolumeUUID,
                          profile.imagePath.hasPrefix(backing.mountPoint.hasSuffix("/") ? backing.mountPoint : backing.mountPoint + "/"),
                          profile.hasVerifiedImageFormat,
                          policy.outerUUID == profile.backingVolumeUUID,
                          policy.imagePath == profile.imagePath else { return false }
                    return true
                }
            }, independentContinuationValidator: { [weak self] journal in
                guard let self, let profiles = self.readSectoriumProfiles() else { return false }
                let matches = profiles.filter { $0.deviceID == journal.target.physicalIdentity }
                if matches.isEmpty { return journal.target.images.isEmpty }
                guard Set(matches.map(\.id)).count == matches.count,
                      Set(matches.map(\.imagePath)).count == matches.count,
                      let device = self.verifiedDevice(journal.target.physicalIdentity),
                      device.isExternal, device.identityVerified else { return false }
                let targetVolumeUUIDs = Set(journal.target.volumes.compactMap { row -> UUID? in
                    guard let divider = row.identity.firstIndex(of: "|") else { return nil }
                    return UUID(uuidString: String(row.identity[..<divider]))
                })
                let imageVolumeUUIDs = journal.target.images.flatMap(\.volumeIdentities).compactMap { identity -> UUID? in
                    guard let divider = identity.firstIndex(of: "|") else { return nil }
                    return UUID(uuidString: String(identity[..<divider]))
                }
                let targetMemberIdentities = Set(journal.target.volumes.map(\.identity))
                let currentMemberIdentities = Set(device.volumeMembers.map {
                    "\($0.volumeUUID.uuidString.lowercased())|\($0.bsdName)"
                })
                guard targetVolumeUUIDs.count == journal.target.volumes.count,
                      currentMemberIdentities == targetMemberIdentities,
                      Set(matches.compactMap(\.devUUID)) == Set(imageVolumeUUIDs),
                      Set(imageVolumeUUIDs).count == imageVolumeUUIDs.count else { return false }
                return matches.allSatisfy { profile in
                    let backingPath = URL(fileURLWithPath: profile.backingMountPoint).standardizedFileURL.path
                    let imagePath = URL(fileURLWithPath: profile.imagePath).standardizedFileURL.path
                    guard let policy = self.profilePolicy(profile),
                          targetVolumeUUIDs.contains(profile.backingVolumeUUID),
                          backingPath == profile.backingMountPoint,
                          imagePath == profile.imagePath,
                          imagePath.hasPrefix(backingPath.hasSuffix("/") ? backingPath : backingPath + "/"),
                          profile.hasVerifiedImageFormat,
                          policy.outerUUID == profile.backingVolumeUUID,
                          policy.imagePath == profile.imagePath else { return false }
                    return true
                }
            })
    }

    private func decodeEjectJournal(_ encoded: String?) -> WholeDeviceEjectJournalRecord? {
        guard let encoded, let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(WholeDeviceEjectJournalRecord.self, from: data)
    }

    private func continuationRecoveryIsFresh(_ journal: WholeDeviceEjectJournalRecord,
                                             driver: WholeDeviceEjectDriving) -> Bool {
        if journal.lastIssuedAction == .physicalVolumesUnmount,
           journal.phase == .interrupted || journal.phase == .physicalVolumesUnmountIssued
                || journal.phase == .physicalVolumesUnmounted {
            return driver.freshPhysicalContinuationMatches(journal)
        }
        return journal.lastIssuedAction == .ejectWholeDevice && journal.phase == .ejectIssued
            && driver.freshEjectIssuedRecovery(journal) != .refused
    }

    public func resumePendingSectoriumOperation() -> OperationResult {
        workbenchOperation("resume") { id, steps in
            let state: StoragePersistentState
            do { state = try store.load() } catch { return workbenchFailure(id, steps, "Durable operation state is unavailable") }
            guard state.workbenchOperation != nil else { return workbenchFailure(id, steps, "No interrupted workbench operation is pending") }
            if !state.ejectIntent, state.workbenchOperation?.hasPrefix("eject:") == true {
                guard cancelUncommittedEject(state) else {
                    return workbenchFailure(id, steps, "Pre-intent eject state is contradictory, drifted, or no longer in its validation-only phase")
                }
                steps.append(.init(step: "cancelUncommittedEject", status: .succeeded,
                                   detail: "The exact validating marker was atomically cancelled before any storage mutation"))
                return .init(operationID: id, mode: .manual, steps: steps)
            }
            guard !state.ejectIntent else {
                return workbenchFailure(id, steps,
                    "Pending eject intent cannot be resumed through the generic workbench recovery route")
            }
            guard state.workbenchOperation?.hasPrefix("eject:") != true else {
                return workbenchFailure(id, steps,
                    "An interrupted eject operation requires its dedicated recovery decision")
            }
            if state.workbenchPhase == "validation-rejected", state.workbenchCompletedStep == nil,
               let marker = state.workbenchOperation, state.workbenchTerminalResult != nil {
                guard resolveValidationRejection(marker) else {
                    return workbenchFailure(id, steps, "Validation rejection is recorded, but its matching marker could not be resolved")
                }
                steps.append(.init(step: "resolveValidationRejection", status: .succeeded,
                                   detail: "No mutation began; terminal validation result remains durably recorded"))
                return .init(operationID: id, mode: .manual, steps: steps)
            }
            guard let profile = selectedProfile(), let policy = profilePolicy(profile) else { return workbenchFailure(id, steps, "Pending profile cannot be identified") }
            guard recordWorkbenchTarget(operation: state.workbenchOperation ?? id,
                                        target: "\(profile.deviceID):\(profile.imagePath)") || state.workbenchPhase != "validating" else {
                return workbenchFailure(id, steps, "Could not persist the recovery target")
            }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            let action = state.workbenchOperation?.split(separator: ":", maxSplits: 1).first.map(String.init)
            guard state.workbenchTarget == profile.imagePath,
                  let device = verifiedDevice(profile.deviceID), device.identityVerified,
                  device.volumeUUIDs.contains(profile.backingVolumeUUID),
                  verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid == profile.backingVolumeUUID else {
                return workbenchFailure(id, steps, "Pending operation target failed fresh backing-device validation")
            }
            switch action {
            case "start", "adopt":
                guard let observation = backend.observe(), case .success = policy.validate(observation) else {
                    return workbenchFailure(id, steps, "Interrupted \(action!) operation is not fully revalidated; recovery marker retained")
                }
                steps.append(.init(step: "validateMountedChain", status: .succeeded))
            case "create":
                guard state.workbenchCompletedStep == "createSparsebundle",
                      isPlainDirectory(URL(fileURLWithPath: profile.imagePath)) else {
                    return workbenchFailure(id, steps, "Interrupted create lacks a durable completion record and exact image artifact")
                }
                if profile.imageFormat == nil {
                    let format = commandRunner.run("/usr/bin/hdiutil", ["imageinfo", profile.imagePath, "-format"], cwd: paths.workingDirectory)
                    guard format.succeeded, let imageFormat = Self.documentedSparsebundleFormat(format.detail) else {
                        return workbenchFailure(id, steps, "Interrupted create image format is still unknown; recovery marker retained")
                    }
                    let verified = SectoriumDevelopmentProfile(id: profile.id, name: profile.name, deviceID: profile.deviceID,
                        backingVolumeUUID: profile.backingVolumeUUID, backingMountPoint: profile.backingMountPoint,
                        imagePath: profile.imagePath, devVolumeName: profile.devVolumeName, devMountPoint: profile.devMountPoint,
                        devUUID: profile.devUUID, encrypted: profile.encrypted, caseSensitive: profile.caseSensitive,
                        logicalCapacityBytes: profile.logicalCapacityBytes, imageFormat: imageFormat, validation: profile.validation)
                    do { try saveProfile(verified) }
                    catch { return workbenchFailure(id, steps, "Interrupted create format was observed but could not be durably saved") }
                    steps.append(.init(step: "verifyImageFormat", status: .succeeded, detail: imageFormat))
                }
                guard profile.imageFormat == nil || profile.imageFormat == "UDSB" else {
                    return workbenchFailure(id, steps, "Interrupted create recorded a conflicting image format")
                }
                steps.append(.init(step: "verifyCreatedImage", status: .succeeded))
            case "stop":
                guard state.workbenchCompletedStep == "detachImage",
                      backend.imageIsDetached(),
                      case .success = policy.validateOuter(backend.observeOuter()) else {
                    return workbenchFailure(id, steps, "Interrupted stop lacks a durable detach completion and fresh outer identity")
                }
                steps.append(.init(step: "verifyImageDetached", status: .succeeded))
            default:
                return workbenchFailure(id, steps, "This interrupted action has no safe automatic reconciliation rule")
            }
            guard clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Could not clear recovered operation marker") }
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    public func returnToDevelopment(password: String? = nil) -> OperationResult {
        guard let pending = try? store.load() else {
            return startDevelopmentDisk(password: password)
        }
        if pending.ejectIntent, pending.workbenchOperation?.hasPrefix("eject:") == true {
            return withProgress("sectorium.returnToDevelopment") {
                serial.lock(); defer { serial.unlock() }
                let id = UUID().uuidString
                let driver = makeWholeDeviceEjectDriver()
                guard coreController.returnFromWholeDeviceEject(driver: driver) else {
                    return workbenchFailure(id, [], "Explicit Return requires a fresh exact physical and image identity check")
                }
                return .init(operationID: id, mode: .manual,
                    steps: [.init(step: "returnFromWholeDeviceEject", status: .succeeded,
                                  detail: "Fresh physical identity and recovery boundary validated")])
            }
        }
        if !pending.ejectIntent, pending.workbenchOperation?.hasPrefix("eject:") == true {
            return withProgress("sectorium.returnToDevelopment") {
                serial.lock(); defer { serial.unlock() }
                let id = UUID().uuidString
                guard lock.acquire() else { return workbenchFailure(id, [], "Another storage operation is running") }
                defer { lock.release() }
                var steps: [OperationStepResult] = []
                guard let state = try? store.load(), !state.ejectIntent,
                      let marker = state.workbenchOperation, marker.hasPrefix("eject:"),
                      state.workbenchCompletedStep == nil else {
                    return workbenchFailure(id, steps, "Uncommitted eject boundary failed exact target or operation-state validation")
                }
                if state.workbenchPhase == "validating" {
                    guard cancelUncommittedEject(state) else {
                        return workbenchFailure(id, steps, "Pre-intent eject state is contradictory, drifted, or no longer in its validation-only phase")
                    }
                    steps.append(.init(step: "cancelUncommittedEject", status: .succeeded,
                                       detail: "Returned without storage mutation; the eject intent had not been committed"))
                    return .init(operationID: id, mode: .manual, steps: steps)
                }
                guard state.workbenchPhase == "mutating:persistEjectIntent",
                      let profile = selectedProfile(),
                      let device = verifiedDevice(profile.deviceID), device.isExternal, device.identityVerified,
                      device.id == state.workbenchTarget,
                      device.volumeUUIDs.contains(profile.backingVolumeUUID),
                      profile.imagePath.hasPrefix(profile.backingMountPoint + "/"),
                      isPlainDirectory(URL(fileURLWithPath: profile.imagePath)),
                      URL(fileURLWithPath: profile.imagePath).standardizedFileURL.resolvingSymlinksInPath().path == profile.imagePath,
                      verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid == profile.backingVolumeUUID,
                      let policy = profilePolicy(profile) else {
                    return workbenchFailure(id, steps, "Uncommitted eject boundary failed exact target or operation-state validation")
                }
                steps.append(.init(step: "verifyUncommittedEjectTarget", status: .succeeded))
                let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
                guard let observation = backend.observe(), case .success = policy.validate(observation) else {
                    return workbenchFailure(id, steps, "Uncommitted eject boundary requires a fresh complete mounted-chain observation")
                }
                steps.append(.init(step: "validateMountedChain", status: .succeeded))
                guard clearWorkbenchMarker() else {
                    return workbenchFailure(id, steps, "Could not clear the verified pre-intent eject marker")
                }
                steps.append(.init(step: "resolveUncommittedEjectIntent", status: .succeeded,
                                   detail: "No eject intent or storage mutation was recorded; mounted identity was freshly validated"))
                return .init(operationID: id, mode: .manual, steps: steps)
            }
        }
        guard pending.ejectIntent else { return startDevelopmentDisk(password: password) }
        if pending.workbenchOperation == nil {
            return coreController.recoverPendingIntentManually()
        }
        return withProgress("sectorium.returnToDevelopment") {
            serial.lock(); defer { serial.unlock() }
            let id = UUID().uuidString
            guard lock.acquire() else { return workbenchFailure(id, [], "Another storage operation is running") }
            defer { lock.release() }
            var steps: [OperationStepResult] = []
            guard let state = try? store.load(), state.ejectIntent,
                  let marker = state.workbenchOperation, marker.hasPrefix("eject:"),
                  let originalID = marker.split(separator: ":", maxSplits: 1).last.map(String.init) else {
                return workbenchFailure(id, steps, "Pending eject has no recoverable workbench operation identity")
            }
            guard let profile = selectedProfile(), profile.hasVerifiedImageFormat,
                  let device = verifiedDevice(profile.deviceID), device.isExternal, device.identityVerified,
                  device.id == state.workbenchTarget,
                  device.volumeUUIDs.contains(profile.backingVolumeUUID),
                  verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid == profile.backingVolumeUUID,
                  let policy = profilePolicy(profile) else {
                return workbenchFailure(id, steps, "Return-to-development target failed fresh physical identity validation")
            }
            steps.append(.init(step: "verifyReturnTarget", status: .succeeded))
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            guard case .success = policy.validateOuter(backend.observeOuter()) else {
                return workbenchFailure(id, steps, "Return-to-development requires a fresh verified backing-volume observation")
            }
            steps.append(.init(step: "verifyBackingVolume", status: .succeeded))
            if let observation = backend.observe(), case .success = policy.validate(observation) {
                steps.append(.init(step: "validateMountedChain", status: .succeeded))
            } else {
                guard backend.imageIsDetached(), backend.canAttemptMount() else {
                    return workbenchFailure(id, steps, "Return-to-development image or mount point is not safely observable")
                }
                guard let encryptionState = profile.encrypted ?? backend.imageEncryptionState() else {
                    return workbenchFailure(id, steps, "Image encryption status could not be verified; no attach was attempted")
                }
                guard !encryptionState || (password != nil && hdiutilPassphraseInput(password!) != nil
                    && commandRunner is HESectoriumSecureCommandRunning) else {
                    return workbenchFailure(id, steps, "Encrypted image return requires a passphrase over secure stdin")
                }
                guard beginWorkbenchMutation(operation: originalID, target: profile.imagePath, step: "returnAttachImage") else {
                    return workbenchFailure(id, steps, "Could not persist the return-to-development attach boundary")
                }
                let attached = backend.attachImage(password: encryptionState ? password : nil)
                steps.append(.init(step: "returnAttachImage", status: attached.succeeded ? .succeeded : .failed,
                                   detail: profile.encrypted == true ? "Unlock/attach returned \(attached.exitCode)" : attached.detail))
                guard attached.succeeded else { return workbenchFailure(id, steps, "Return-to-development attach failed; eject intent retained") }
                guard completeWorkbenchStep(operation: originalID, step: "returnAttachImage") else {
                    return workbenchFailure(id, steps, "Return attach completed but its recovery step could not be recorded")
                }
                guard let fresh = backend.observe(), case .success = policy.validate(fresh) else {
                    return workbenchFailure(id, steps, "Return-to-development failed fresh post-attach chain validation")
                }
                steps.append(.init(step: "validateMountedChain", status: .succeeded))
            }
            guard clearEjectIntent() else { return workbenchFailure(id, steps, "Could not durably resolve eject intent after validated return") }
            steps.append(.init(step: "clearEjectIntent", status: .succeeded))
            guard clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Mounted and validated, but pending eject operation remains recorded") }
            steps.append(.init(step: "clearWorkbenchOperation", status: .succeeded))
            return .init(operationID: id, mode: .manual, steps: steps)
        }
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
            // Compatibility/CLI callers do not carry the fresh, displayed whole-device
            // checkpoint required by the confirmed Workbench route. Refuse here instead of
            // falling back to the older volume-scoped eject path or synthesizing consent.
            return record(.init(operationID: UUID().uuidString, mode: .manual,
                steps: [.init(step: "requireWholeDeviceEjectConfirmation", status: .failed,
                    detail: "Use the whole-device eject flow after reviewing its fresh target and affected scope")],
                failure: .workbenchFailed("whole-device eject requires a fresh user-reviewed confirmation")))
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
