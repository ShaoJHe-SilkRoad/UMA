import Foundation
import HESectoriumCore
#if canImport(AppKit)
import AppKit
#endif
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
    private let observationCache = SectoriumReadOnlyObservationCache()
    public init() {}
    func withReadOnlyObservation<T>(_ body: () throws -> T) rethrows -> T {
        try observationCache.withObservation(body)
    }
    public func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        observationCache.run(executable, arguments, cwd: cwd) {
            execute(executable, arguments, cwd: cwd, standardInput: Data(),
                    timeout: Self.defaultTimeout(executable: executable, arguments: arguments))
        }
    }
    public func run(_ executable: String, _ arguments: [String], cwd: URL, standardInput: Data) -> CommandOutcome {
        observationCache.invalidate()
        defer { observationCache.invalidate() }
        return execute(executable, arguments, cwd: cwd, standardInput: standardInput, timeout: nil)
    }
    public func run(_ executable: String, _ arguments: [String], cwd: URL, timeout: TimeInterval) -> CommandOutcome {
        // Timed calls are used by action preflight/execution; never reuse a UI observation.
        observationCache.invalidate()
        defer { observationCache.invalidate() }
        return execute(executable, arguments, cwd: cwd, standardInput: Data(), timeout: timeout)
    }
    private func execute(_ executable: String, _ arguments: [String], cwd: URL, standardInput: Data,
                         timeout: TimeInterval?) -> CommandOutcome {
        if let timeout, !timeout.isFinite || timeout <= 0 {
            return .init(exitCode: -1, detail: "command timeout must be finite and positive")
        }
        let process = Process(); let out = Pipe(); let err = Pipe()
        let input = Pipe()
        guard Self.markCloseOnExec(input), Self.markCloseOnExec(out), Self.markCloseOnExec(err) else {
            return .init(exitCode: -1, detail: "command pipe isolation could not be established")
        }
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.currentDirectoryURL = cwd; process.standardOutput = out; process.standardError = err; process.standardInput = input
        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }
        defer {
            try? input.fileHandleForWriting.close()
            try? input.fileHandleForReading.close()
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
        }
        let group = DispatchGroup()
        let readersReady = DispatchGroup()
        let metadata = Self.isReadOnlyPropertyList(executable: executable, arguments: arguments)
        let captured = CapturedProcessOutput(limit: metadata ? 1_048_576 : 8_192)
        // Blocking command callers can occupy the shared dispatch worker pool.
        // Give each pipe its own reader, and start both before launching a child
        // whose output could otherwise fill a pipe or outlive an unscheduled read.
        group.enter(); readersReady.enter()
        Thread.detachNewThread {
            captured.captureOut(from: out.fileHandleForReading, onReady: { readersReady.leave() })
            group.leave()
        }
        group.enter(); readersReady.enter()
        Thread.detachNewThread {
            captured.captureErr(from: err.fileHandleForReading, onReady: { readersReady.leave() })
            group.leave()
        }
        defer {
            captured.cancel()
            _ = group.wait(timeout: .now() + 1)
        }
        guard readersReady.wait(timeout: .now() + 1) == .success else {
            return .init(exitCode: -1, detail: "command output readers could not start")
        }
        do {
            try process.run()
            var inputError: Error?
            do {
                if !standardInput.isEmpty { try input.fileHandleForWriting.write(contentsOf: standardInput) }
            } catch { inputError = error }
            try? input.fileHandleForWriting.close()
            var timedOut = false
            var terminationConfirmed = true
            if inputError != nil {
                terminationConfirmed = Self.stop(process, completion: completion)
            } else if let timeout {
                if completion.wait(timeout: .now() + max(0.1, timeout)) == .timedOut {
                    timedOut = true
                    terminationConfirmed = Self.stop(process, completion: completion)
                }
            } else {
                completion.wait()
            }
            // A descendant can inherit a pipe after the direct child exits. Do not
            // hold the Service lock forever waiting for that unrelated descriptor.
            let outputClosed = group.wait(timeout: .now() + 1) == .success
            if !outputClosed {
                captured.cancel()
                _ = group.wait(timeout: .now() + 1)
            }
            let (outData, errData, outExceeded, errExceeded) = captured.values()
            let detail = [String(data: outData, encoding: .utf8), String(data: errData, encoding: .utf8)]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            guard terminationConfirmed else {
                return .init(exitCode: -1, detail: "command termination could not be confirmed")
            }
            if timedOut { return .init(exitCode: -1, detail: "command timed out; child process terminated; \(String(detail.prefix(8000)))") }
            if inputError != nil { return .init(exitCode: -1, detail: "command input could not be delivered") }
            guard outputClosed else { return .init(exitCode: -1, detail: "command output did not close after process exit") }
            return Self.result(executable: executable, arguments: arguments, exitCode: process.terminationStatus,
                               stdout: outData, stderr: errData,
                               stdoutExceeded: outExceeded, stderrExceeded: errExceeded)
        } catch { return .init(exitCode: -1, detail: String(describing: error)) }
    }

    static func markCloseOnExec(_ pipe: Pipe) -> Bool {
        #if canImport(Darwin)
        for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
            let descriptor = handle.fileDescriptor
            let flags = fcntl(descriptor, F_GETFD)
            guard flags >= 0, fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) == 0 else { return false }
        }
        #endif
        return true
    }

    private static func stop(_ process: Process, completion: DispatchSemaphore) -> Bool {
        if process.isRunning { process.terminate() }
        if completion.wait(timeout: .now() + 1) == .success { return true }
        #if canImport(Darwin)
        // Only this runner's direct child is signalled. A timeout is still a
        // failed operation; it never establishes an unmount/eject postcondition.
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        #endif
        return completion.wait(timeout: .now() + 1) == .success
    }

    static func defaultTimeout(executable: String, arguments: [String]) -> TimeInterval? {
        if executable == "/bin/ps", arguments.count == 4, arguments[0] == "-p", arguments[2] == "-o", arguments[3] == "ppid=" { return 2 }
        if executable == "/usr/sbin/diskutil", arguments.first == "unmount" || arguments.first == "mount" { return 30 }
        if executable == "/usr/sbin/diskutil", arguments == ["image", "attach", "--help"] { return 5 }
        if executable == "/usr/sbin/diskutil", Array(arguments.prefix(2)) == ["image", "attach"] { return 90 }
        if isReadOnlyPropertyList(executable: executable, arguments: arguments)
            || (executable == "/usr/bin/hdiutil" && arguments.count == 3
                && arguments[0] == "imageinfo" && arguments[1].hasPrefix("/") && arguments[2] == "-format")
            || (executable == "/usr/bin/hdiutil" && arguments.count == 2
                && arguments[0] == "isencrypted" && arguments[1].hasPrefix("/"))
            || (executable == "/bin/df" && arguments.count == 2 && arguments[0] == "-P")
            || (executable == "/usr/sbin/lsof" &&
                ((arguments.count == 4 && Array(arguments.prefix(3)) == ["-nP", "+f", "--"])
                 || (arguments.count == 5 && Array(arguments.prefix(4)) == ["-nP", "-Fpcf", "+f", "--"]))
                && arguments.last?.hasPrefix("/") == true) { return 15 }
        // Mutations retain their existing explicit timeout/recovery contract.
        return nil
    }

    // Only supported read-only plist commands may retain the larger bounded payload.
    static func isReadOnlyPropertyList(executable: String, arguments: [String]) -> Bool {
        (executable == "/usr/sbin/diskutil" &&
            (arguments == ["list", "-plist"] || arguments == ["list", "-plist", "external", "physical"] || arguments == ["apfs", "list", "-plist"] ||
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
        let formatQuery = executable == "/usr/bin/hdiutil" && arguments.count == 3
            && arguments[0] == "imageinfo" && arguments[2] == "-format"
        if (metadata || formatQuery) && exitCode == 0 {
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
    private var cancelled = false

    init(limit: Int) { self.limit = limit }

    func captureOut(from handle: FileHandle, onReady: () -> Void) {
        let result = readAndDrain(handle, onReady: onReady)
        lock.lock(); out = result.data; outExceeded = result.exceeded; lock.unlock()
    }
    func captureErr(from handle: FileHandle, onReady: () -> Void) {
        let result = readAndDrain(handle, onReady: onReady)
        lock.lock(); err = result.data; errExceeded = result.exceeded; lock.unlock()
    }
    func values() -> (Data, Data, Bool, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (out, err, outExceeded, errExceeded)
    }
    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
    private func shouldStop() -> Bool {
        lock.lock(); defer { lock.unlock() }; return cancelled
    }
    private func readAndDrain(_ handle: FileHandle, onReady: () -> Void) -> (data: Data, exceeded: Bool) {
        onReady()
        var retained = Data()
        var exceeded = false
        defer { try? handle.close() }
        #if canImport(Darwin)
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return (retained, true) }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while !shouldStop() {
            var event = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&event, 1, 50)
            if ready == 0 { continue }
            if ready < 0 {
                if errno == EINTR { continue }
                return (retained, true)
            }
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count == 0 { return (retained, exceeded) }
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return (retained, true)
            }
            let remaining = max(0, limit + 1 - retained.count)
            if remaining > 0 { retained.append(contentsOf: buffer.prefix(min(count, remaining))) }
            if count > remaining || retained.count > limit { exceeded = true }
        }
        return (retained, true)
        #else
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
        #endif
    }
}

public enum HESectoriumInstalledStatus: Equatable, Sendable { case installed, missing, conflict(String) }
public enum HESectoriumReadinessStatus: Equatable, Sendable { case ready, notReady(String), unknown }
public enum HESectoriumAgentLoadStatus: Equatable, Sendable { case loaded, notLoaded, unknown }
public enum HESectoriumOperationProgress: Equatable, Sendable { case idle, running(action: String) }
public protocol HESectoriumAgentStatusProviding: AnyObject {
    func loadStatus(label: String) -> HESectoriumAgentLoadStatus
}

enum SectoriumLaunchAgentConfiguration {
    static let label = "com.juliushe.dev-apfs-mounter"

    static func matchesExecutable(_ job: [String: Any], label: String,
                                  controlPath: String) -> Bool {
        guard job["Label"] as? String == label,
              let arguments = job["ProgramArguments"] as? [String],
              arguments == [controlPath, "agent"] else { return false }
        if let program = job["Program"], program as? String != controlPath { return false }
        return true
    }

    static func matchesInstalledPlist(_ data: Data, controlPath: String,
                                      standardOutPath: String, standardErrorPath: String) -> Bool {
        guard let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let job = propertyList as? [String: Any],
              Set(job.keys) == Set(["Label", "ProgramArguments", "RunAtLoad", "ProcessType",
                                    "StandardOutPath", "StandardErrorPath"]),
              matchesExecutable(job, label: label, controlPath: controlPath),
              job["RunAtLoad"] as? Bool == true,
              job["ProcessType"] as? String == "Background",
              job["StandardOutPath"] as? String == standardOutPath,
              job["StandardErrorPath"] as? String == standardErrorPath else { return false }
        return true
    }
}

public final class SystemAgentStatusProvider: HESectoriumAgentStatusProviding {
    private let expectedControlPath: String
    public init(paths: HESectoriumPaths = .user) {
        expectedControlPath = paths.root.appendingPathComponent("HESectoriumControl").path
    }

    static func classify(job: [String: Any], label: String,
                         expectedControlPath: String) -> HESectoriumAgentLoadStatus {
        guard label == SectoriumLaunchAgentConfiguration.label else { return .unknown }
        return SectoriumLaunchAgentConfiguration.matchesExecutable(job, label: label,
            controlPath: expectedControlPath) ? .loaded : .unknown
    }

    public func loadStatus(label: String) -> HESectoriumAgentLoadStatus {
        #if canImport(ServiceManagement)
        guard label == SectoriumLaunchAgentConfiguration.label else { return .unknown }
        // SMJobCopyDictionary is the only read-only ServiceManagement lookup for an
        // arbitrary user LaunchAgent label. It returns an unmanaged CFDictionary;
        // taking the retained value is required before bridging to Swift.
        guard let unmanagedJob = SMJobCopyDictionary(kSMDomainUserLaunchd, label as CFString) else { return .notLoaded }
        guard let job = unmanagedJob.takeRetainedValue() as? [String: Any] else { return .unknown }
        return Self.classify(job: job, label: label, expectedControlPath: expectedControlPath)
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
struct StoragePersistentStateCodable: Codable {
    var revision: UInt64; var ejectIntent: Bool; var operationID: String?; var outerDisappearedAfterIntent: Bool
    var outerReconnectAttempted: Bool
    var suppressedProfileIDs: Set<String>
    var disconnectedProfileIDs: Set<String>
    var reconnectAttemptedProfileIDs: Set<String>
    var terminalEjectJournals: [String: String]
    var workbenchOperation: String?
    var workbenchPhase: String?
    var workbenchTarget: String?
    var workbenchCompletedStep: String?
    var workbenchTerminalResult: String?
    init(state: StoragePersistentState) {
        revision = state.revision; ejectIntent = state.ejectIntent; operationID = state.operationID
        outerDisappearedAfterIntent = state.outerDisappearedAfterIntent
        outerReconnectAttempted = state.outerReconnectAttempted
        suppressedProfileIDs = state.suppressedProfileIDs
        disconnectedProfileIDs = state.disconnectedProfileIDs
        reconnectAttemptedProfileIDs = state.reconnectAttemptedProfileIDs
        terminalEjectJournals = state.terminalEjectJournals
        workbenchOperation = state.workbenchOperation; workbenchPhase = state.workbenchPhase
        workbenchTarget = state.workbenchTarget; workbenchCompletedStep = state.workbenchCompletedStep
        workbenchTerminalResult = state.workbenchTerminalResult
    }
    var state: StoragePersistentState {
        .init(revision: revision, ejectIntent: ejectIntent, operationID: operationID,
              outerDisappearedAfterIntent: outerDisappearedAfterIntent,
              outerReconnectAttempted: outerReconnectAttempted,
              suppressedProfileIDs: suppressedProfileIDs,
              disconnectedProfileIDs: disconnectedProfileIDs,
              reconnectAttemptedProfileIDs: reconnectAttemptedProfileIDs,
              terminalEjectJournals: terminalEjectJournals,
              workbenchOperation: workbenchOperation,
              workbenchPhase: workbenchPhase, workbenchTarget: workbenchTarget,
              workbenchCompletedStep: workbenchCompletedStep, workbenchTerminalResult: workbenchTerminalResult)
    }

    private enum CodingKeys: String, CodingKey {
        case revision, ejectIntent, operationID, outerDisappearedAfterIntent, outerReconnectAttempted
        case suppressedProfileIDs, disconnectedProfileIDs, reconnectAttemptedProfileIDs
        case terminalEjectJournals
        case workbenchOperation, workbenchPhase, workbenchTarget, workbenchCompletedStep, workbenchTerminalResult
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        revision = try values.decode(UInt64.self, forKey: .revision)
        ejectIntent = try values.decode(Bool.self, forKey: .ejectIntent)
        operationID = try values.decodeIfPresent(String.self, forKey: .operationID)
        outerDisappearedAfterIntent = try values.decodeIfPresent(Bool.self, forKey: .outerDisappearedAfterIntent) ?? false
        outerReconnectAttempted = try values.decodeIfPresent(Bool.self, forKey: .outerReconnectAttempted) ?? false
        suppressedProfileIDs = try values.decodeIfPresent(Set<String>.self, forKey: .suppressedProfileIDs) ?? []
        disconnectedProfileIDs = try values.decodeIfPresent(Set<String>.self, forKey: .disconnectedProfileIDs) ?? []
        reconnectAttemptedProfileIDs = try values.decodeIfPresent(Set<String>.self, forKey: .reconnectAttemptedProfileIDs) ?? []
        terminalEjectJournals = try values.decodeIfPresent([String: String].self, forKey: .terminalEjectJournals) ?? [:]
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
    private enum DevMountEvidence { case mountedAtTarget, verifiedOuterBacking, unknown }

    private let policy: StorageIdentityPolicy; private let paths: HESectoriumPaths; private let runner: HESectoriumCommandRunning
    var mountPointDirectory = SectoriumMountPointDirectory()
    public init(paths: HESectoriumPaths, runner: HESectoriumCommandRunning = ProcessCommandRunner(), policy: StorageIdentityPolicy = .expected) {
        self.paths = paths; self.runner = runner; self.policy = policy
    }
    private func command(_ path: String, _ args: [String]) -> CommandOutcome { runner.run(path, args, cwd: paths.workingDirectory) }
    func imageEncryptionState() -> Bool? {
        // Already-attached images expose this fact without reopening the image.
        // A duplicate path or a non-Boolean value is never treated as plaintext.
        if let images = plist(command("/usr/bin/hdiutil", ["info", "-plist"]))?["images"] as? [[String: Any]] {
            let matches = images.filter { $0["image-path"] as? String == policy.imagePath }
            if matches.count == 1, let value = matches[0]["image-encrypted"] as? NSNumber,
               CFGetTypeID(value) == CFBooleanGetTypeID() { return value.boolValue }
        }
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
        // df identifies the filesystem containing the image; diskutil confirms
        // its native mount. Preserve spaces in volume names while rejecting
        // contradictory observations rather than trusting either result alone.
        let header = lines[0].split(whereSeparator: \.isWhitespace).map(String.init)
        guard header.suffix(2) == ["Mounted", "on"], let mountIndex = header.firstIndex(of: "Mounted"),
              mountIndex >= 5 else { return nil }
        let columns = row.split(maxSplits: mountIndex, whereSeparator: \.isWhitespace)
        guard columns.count == mountIndex + 1 else { return nil }
        let reportedMount = String(columns[mountIndex]).trimmingCharacters(in: .whitespaces)
        guard let mount = text(diskInfo("/dev/\(device)"), ["MountPoint"]), !mount.isEmpty,
              reportedMount == mount else { return nil }
        return (device, mount)
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
    private func devMountEvidence() -> DevMountEvidence {
        guard canonical(policy.devMountPoint) == policy.devMountPoint else { return .unknown }
        let observed = volume(policy.devMountPoint)
        if observed.mountedVolume, observed.uuid != nil,
           observed.fileSystem != "unknown", observed.name != "unknown" {
            if observed.mountPoint == policy.devMountPoint {
                return observed.rootMatchesExpected ? .mountedAtTarget : .unknown
            }
            if observed.mountPoint == policy.outerMountPoint, observed.uuid == policy.outerUUID {
                return .verifiedOuterBacking
            }
            return .unknown
        }
        // diskutil info accepts devices and mountpoints, not ordinary folders.
        // Resolve the containing filesystem without listing or reading contents,
        // then independently verify its device UUID and exact native mountpoint.
        return directoryIsOnVerifiedOuterVolume(policy.devMountPoint) ? .verifiedOuterBacking : .unknown
    }
    private func directoryIsOnVerifiedOuterVolume(_ path: String) -> Bool {
        guard canonical(path) == path,
              let backing = sourceForFile(path), backing.mount == policy.outerMountPoint,
              let info = diskInfo("/dev/\(backing.device)"),
              text(info, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)) == policy.outerUUID,
              text(info, ["MountPoint"]) == policy.outerMountPoint else { return false }
        return true
    }

    /// Recovery may settle a failed Load only when no mounted volume is hidden
    /// at the target. This is metadata-only and never mounts or erases anything.
    func verifiedUnloadedMountTarget() -> Bool {
        guard canAttemptMount() else { return false }
        if !FileManager.default.fileExists(atPath: policy.devMountPoint) { return true }
        if case .verifiedOuterBacking = devMountEvidence() { return true }
        return false
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
              let outerPhysical = physicalBackingWholeDisk(volumeDevice: backing.device, info: outerInfo, apfsContainers: apfsContainers),
              let physicalInfo = diskInfo("/dev/\(outerPhysical)"),
              text(physicalInfo, ["DeviceIdentifier"]) == outerPhysical,
              text(physicalInfo, ["VirtualOrPhysical"])?.lowercased() == "physical" else { return nil }
        return .init(backingVolumeUUID: policy.outerUUID, attachedVolumeUUID: imageUUID, path: policy.imagePath)
    }
    private func physicalBackingWholeDisk(volumeDevice: String, info: [String: Any],
                                          apfsContainers: [[String: Any]]) -> String? {
        guard let ref = text(info, ["APFSContainerReference"]) else {
            return verifiedWholeDisk(for: volumeDevice, info: info)
        }
        let matches = apfsContainers.filter { text($0, ["ContainerReference"]) == ref }
        guard matches.count == 1, let container = matches.first,
              let volumes = container["Volumes"] as? [[String: Any]],
              volumes.filter({ text($0, ["DeviceIdentifier"]) == volumeDevice &&
                  text($0, ["APFSVolumeUUID"])?.lowercased() == policy.outerUUID.uuidString.lowercased() }).count == 1,
              let stores = physicalStoreDevices(container), stores.count == 1, let store = stores.first,
              let storeInfo = diskInfo("/dev/\(store)") else { return nil }
        return verifiedWholeDisk(for: store, info: storeInfo)
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
        metadataObservation {
            guard canonical(policy.outerMountPoint) == policy.outerMountPoint else { return nil }
            let outer = volume(policy.outerMountPoint)
            guard outer.uuid != nil, outer.mountedVolume, outer.mountPoint == policy.outerMountPoint, outer.rootMatchesExpected else { return nil }
            return outer
        }
    }
    public func observe() -> StorageObservation? {
        metadataObservation {
            guard canonical(policy.outerMountPoint) == policy.outerMountPoint,
                  canonical(policy.devMountPoint) == policy.devMountPoint,
                  canonical(policy.imagePath) == policy.imagePath else { return nil }
            let outer = volume(policy.outerMountPoint); let dev = volume(policy.devMountPoint)
            guard outer.uuid != nil, dev.uuid != nil, let image = imageObservation() else { return nil }
            return .init(outer: outer, dev: dev, image: image)
        }
    }
    /// Each Core read phase is bounded and coherent even outside a UI refresh.
    /// The scope ends before attach/unmount; subsequent postchecks start fresh.
    private func metadataObservation<T>(_ body: () -> T) -> T {
        guard let scoped = runner as? SectoriumObservationCommandRunner else { return body() }
        return scoped.withObservation(body)
    }
    /// Checks only the physical outer volume and configured image path; used for one login-time attach attempt.
    public func canAttemptMount() -> Bool {
        guard canonical(policy.outerMountPoint) == policy.outerMountPoint,
              canonical(policy.imagePath) == policy.imagePath,
              FileManager.default.fileExists(atPath: policy.imagePath),
              canonical(policy.devMountPoint) == policy.devMountPoint else { return false }
        guard let outer = observeOuter(), outer.uuid == policy.outerUUID, outer.writable else { return false }
        if FileManager.default.fileExists(atPath: policy.devMountPoint) { return true }
        // macOS removes a custom mountpoint on normal unmount. Recreating it is
        // valid only beneath the same freshly verified, still-mounted parent.
        guard policy.devMountPoint.hasPrefix(policy.outerMountPoint + "/") else { return false }
        var parent = URL(fileURLWithPath: policy.devMountPoint).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: parent.path) {
            guard parent.path.hasPrefix(policy.outerMountPoint + "/") else { return false }
            parent.deleteLastPathComponent()
        }
        guard canonical(parent.path) == parent.path else { return false }
        return directoryIsOnVerifiedOuterVolume(parent.path)
    }
    public func attachImage() -> CommandOutcome {
        attachImage(password: nil)
    }

    public func attachImage(password: String?) -> CommandOutcome {
        guard canAttemptMount() else {
            return .init(exitCode: -2, detail: "Expected image, parent volume or DEV mountpoint identity is unavailable")
        }
        if let seen = observe(), case .success = policy.validate(seen) { return .success }
        if !FileManager.default.fileExists(atPath: policy.devMountPoint) {
            do { try SecureDirectory.ensure(URL(fileURLWithPath: policy.devMountPoint, isDirectory: true)) }
            catch { return .init(exitCode: -2, detail: "Could not safely restore the development-volume mountpoint") }
            guard canAttemptMount() else { return .init(exitCode: -2, detail: "Parent identity changed while preparing the mountpoint") }
        }
        switch devMountEvidence() {
        case .mountedAtTarget:
            return .init(exitCode: -2,
                detail: "A DEV volume is already mounted at the target but its configured image identity could not be verified; leave it untouched and review the identity before retrying")
        case .unknown:
            return .init(exitCode: -2,
                detail: "Could not verify that the DEV target is an unmounted directory on the selected outer volume; refresh its identity and review the operation details before retrying")
        case .verifiedOuterBacking:
            break
        }
        if let failure = mountPointDirectory.validateForMount(at: policy.devMountPoint) {
            return .init(exitCode: -2, detail: failure)
        }
        // Validate the backing identity again before dispatch. Existing directory
        // contents are left untouched; only macOS performs the actual mount.
        guard case .verifiedOuterBacking = devMountEvidence() else {
            return .init(exitCode: -2, detail: "The mount location changed during preparation; no Load command was run")
        }
        guard let attachedCount = imageInventoryMatchCount(for: policy.imagePath) else {
            return .init(exitCode: -2, detail: "Attached image state is unavailable; no duplicate attach was attempted")
        }
        if attachedCount != 0 {
            guard attachedCount == 1, let info = verifiedUnmountedImageVolumeInfo(),
                  let device = text(info, ["DeviceIdentifier"]), validDiskID(device) else {
                return .init(exitCode: -2, detail: "The attached image does not have one verified unmounted development volume")
            }
            return command("/usr/sbin/diskutil", ["mount", "-mountPoint", policy.devMountPoint, "/dev/\(device)"])
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
        // Newer macOS exposes the system-supported image API used in Terminal.
        // Select before dispatch; an authentication/cancellation/action failure
        // must never trigger a second attach through another executable.
        let capability = command("/usr/sbin/diskutil", ["image", "attach", "--help"])
        let supportsNativeImageAPI = capability.succeeded && capability.detail.contains("diskutil image attach")
        let result = supportsNativeImageAPI
            ? command("/usr/sbin/diskutil", ["image", "attach", "--nobrowse", "--mountPoint", policy.devMountPoint, policy.imagePath])
            : command("/usr/bin/hdiutil", ["attach", "-nobrowse", "-mountpoint", policy.devMountPoint, policy.imagePath])
        return .init(exitCode: result.exitCode, detail: result.detail)
    }
    private func canonical(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path }
    func directoryEntryCount(_ path: String) -> UInt32? {
        SectoriumMountPointDirectory.entryCount(at: path)
    }
    public func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment {
        activityReport(scope: scope).assessment
    }
    func activityReport(scope: OccupancyScope) -> SectoriumActivityReport {
        let mount = scope == .dev ? policy.devMountPoint : policy.outerMountPoint
        guard canonical(mount) == mount, FileManager.default.fileExists(atPath: mount) else {
            return .init(assessment: .incomplete(reason: "verified mount scope unavailable"))
        }
        return .parse(command("/usr/sbin/lsof", ["-nP", "-Fpcf", "+f", "--", mount]))
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
        // hdiutil does not promise volume-uuid on system-entities. Resolve UUID
        // through each returned device's diskutil metadata; if an optional UUID
        // is present it must agree, never override contradictory native facts.
        for entity in entities {
            if let declared = text(entity, ["volume-uuid", "volume-UUID"]) {
                guard let uuid = UUID(uuidString: declared), let device = text(entity, ["dev-entry"]),
                      text(diskInfo(device), ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)) == uuid else { return nil }
            }
        }
        let matchingVolumes: [[String: Any]]
        if let expectedUUID = policy.devUUID {
            matchingVolumes = entities.filter {
                guard let device = text($0, ["dev-entry"]) else { return false }
                return text(diskInfo(device), ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)) == expectedUUID
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
        guard stores.count == 1, let store = stores.first,
              entityDevices.contains(store), let whole = wholeDisk(store),
              entityDevices.contains(whole), imageWholeDevices == Set([whole, containerID]),
              let members = container["Volumes"] as? [[String: Any]], members.count == 1,
              text(members[0], ["APFSVolumeUUID", "VolumeUUID"]).flatMap(UUID.init(uuidString:))
                  == text(info, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)),
              whole.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return whole
    }
    /// For an interrupted verification unload only: prove the original image's
    /// single APFS volume is still attached but no volume on that image is mounted.
    /// This is metadata inspection, not a substitute for a loaded observation.
    func verifiedUnmountedImageVolumeInfo() -> [String: Any]? {
        metadataObservation { observeVerifiedUnmountedImageVolumeInfo() }
    }

    private func observeVerifiedUnmountedImageVolumeInfo() -> [String: Any]? {
        guard let expected = policy.devUUID, let whole = imageWholeDisk(),
              let images = plist(command("/usr/bin/hdiutil", ["info", "-plist"]))?["images"] as? [[String: Any]] else { return nil }
        let matches = images.filter { text($0, ["image-path"]) == policy.imagePath }
        guard matches.count == 1, let image = matches.first,
              let entities = image["system-entities"] as? [[String: Any]], !entities.isEmpty,
              entities.allSatisfy({ text($0, ["mount-point"])?.isEmpty != false }) else { return nil }
        let volumes = entities.filter {
            guard let device = text($0, ["dev-entry"]) else { return false }
            return text(diskInfo(device), ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)) == expected
        }
        guard volumes.count == 1, let entry = volumes.first,
              let device = text(entry, ["dev-entry"]), let info = diskInfo(device),
              Self.explicitlyUnmounted(info),
              text(info, ["VolumeUUID", "APFSVolumeUUID"]).flatMap(UUID.init(uuidString:)) == expected,
              let containerID = text(info, ["APFSContainerReference"]), let allContainers = containers() else { return nil }
        let matchingContainers = allContainers.filter { text($0, ["ContainerReference"]) == containerID }
        guard matchingContainers.count == 1, let container = matchingContainers.first,
              let stores = physicalStoreDevices(container), stores.count == 1,
              stores.first.flatMap({ wholeDisk($0) }) == whole,
              let memberVolumes = container["Volumes"] as? [[String: Any]], memberVolumes.count == 1,
              text(memberVolumes[0], ["APFSVolumeUUID", "VolumeUUID"]).flatMap(UUID.init(uuidString:)) == expected else { return nil }
        return info
    }

    /// Native diskutil info uses an explicit empty MountPoint for an unloaded
    /// APFS volume and may omit Mounted entirely. Missing both fields is unknown.
    /// The image/container/UUID checks above remain required independently.
    private static func explicitlyUnmounted(_ info: [String: Any]) -> Bool {
        if let mounted = info["Mounted"] {
            guard let flag = mounted as? Bool, !flag else { return false }
        }
        if let mount = info["MountPoint"] { return (mount as? String)?.isEmpty == true }
        return info["Mounted"] as? Bool == false
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

private struct SectoriumModificationRecovery: Codable {
    let version: Int
    let operationID: String
    let before: SectoriumDevelopmentProfile
    let change: SectoriumProfileChange
    let wasLoaded: Bool
}

public final class HESectoriumService: @unchecked Sendable {
    public static let shared = HESectoriumService(paths: .user, agentStatusProvider: SystemAgentStatusProvider())
    /// In-process automation has finished, including failures or skipped work.
    /// Observers must obtain fresh state; this signal does not assert readiness.
    public static let automaticOperationDidCompleteNotification = Notification.Name("AUV.Sectorium.automaticOperationDidComplete")
    public let paths: HESectoriumPaths; public let coreController: StorageController
    private let backend: StorageBackend; private let store: DurableStateStore; private let lock: OperationLock
    private let installer: HESectoriumInstaller; private let serial = NSRecursiveLock()
    private let agentStatusProvider: HESectoriumAgentStatusProviding
    private let commandRunner: HESectoriumCommandRunning
    private let observationRunner: SectoriumObservationCommandRunner
    private let consistencyProbe: SectoriumConsistencyProbe
    private let sectoriumDeviceObserver: SectoriumDeviceObserving?
    private let wholeDeviceEjectDriverOverride: WholeDeviceEjectDriving?
    private let sectoriumDeviceIOSampler: SectoriumDeviceIOCounterSampling
    private let portableDocumentWriter: SectoriumPortableDocumentWriting
    private let portableDocumentJournal: SectoriumPortableDocumentJournal
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private let progressLock = NSLock(); private var currentProgress: HESectoriumOperationProgress = .idle
    private let installedStatusLock = NSLock()
    private var lastInstalledStatus: HESectoriumInstalledStatus = .missing
    private var activeProgress: [String: Int] = [:]
    private var acceptingNewOperations = true
    private let operationThreadKey = "AUV.Sectorium.active." + UUID().uuidString
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
                wholeDeviceEjectDriverOverride: WholeDeviceEjectDriving? = nil,
                portableDocumentWriter: SectoriumPortableDocumentWriting? = nil,
                sectoriumMountMetadataProvider: SectoriumMountMetadataProviding? = nil) {
        let observationRunner = SectoriumObservationCommandRunner(runner)
        self.paths = paths; self.commandRunner = observationRunner; self.observationRunner = observationRunner
        self.consistencyProbe = SectoriumConsistencyProbe(paths: paths, runner: runner,
            mounts: sectoriumMountMetadataProvider ?? SystemSectoriumMountMetadataProvider())
        self.portableDocumentJournal = SectoriumPortableDocumentJournal(url: paths.root.appendingPathComponent("sectorium-document-journal.json"))
        self.sectoriumDeviceObserver = sectoriumDeviceObserver
        self.wholeDeviceEjectDriverOverride = wholeDeviceEjectDriverOverride
        self.portableDocumentWriter = portableDocumentWriter ?? SectoriumPortableDocumentWriter(
            fileSystem: SystemSectoriumPortableDocumentFileSystem(runner: observationRunner))
        self.sectoriumDeviceIOSampler = sectoriumDeviceIOSampler ?? makeSystemSectoriumDeviceIOSampler()
        let resolvedStore = store ?? JSONStateStore(url: paths.state); self.store = resolvedStore
        let diskPolicy = identityPolicy ?? Self.readIdentityPolicy(at: paths.config)
        explicitIdentityPolicy = identityPolicy != nil
        configurationValid = explicitIdentityPolicy || Self.readIdentityPolicy(at: paths.config) != nil
        let policy = diskPolicy ?? .expected
        let resolvedLock = operationLock ?? KernelOperationLock(url: paths.lock); self.lock = resolvedLock
        let resolvedBackend = backend ?? MacStorageBackend(paths: paths, runner: observationRunner, policy: policy); self.backend = resolvedBackend
        self.agentStatusProvider = agentStatusProvider
        self.installer = installer ?? HESectoriumInstaller(paths: paths)
        self.coreController = StorageController(backend: resolvedBackend, store: resolvedStore, lock: resolvedLock, identityPolicy: policy)
    }
    /// One passive refresh has one metadata snapshot and one eight-second command
    /// budget. Results, including unavailable observations, never cross scopes.
    public func withReadOnlyObservation<T>(_ body: () throws -> T) rethrows -> T {
        // Startup automation and foreground actions share this recursive lock.
        // Wait for them before starting the observation deadline; otherwise a
        // valid inventory can exhaust its budget waiting for profile access.
        // Holding it for the scope also prevents mutation between cached reads.
        serial.lock(); defer { serial.unlock() }
        return try observationRunner.withObservation(body)
    }
    /// Cheap invalidation evidence, never cached action permission. This probe
    /// does not acquire the Service operation lock or traverse registered images.
    public func observeSectoriumConsistency() -> SectoriumConsistencyStamp? {
        consistencyProbe.observe()
    }
    public func observeSectoriumDevices() throws -> [SectoriumPhysicalDevice] {
        let result: Result<[SectoriumPhysicalDevice], Error> = observationRunner.observationValue("devices") {
            Result {
                if let sectoriumDeviceObserver { return try sectoriumDeviceObserver.observeDevices() }
                // Use the same context as topology/backend queries so their
                // metadata shares this observation's command cache. Before a
                // first install, inventory remains read-only and needs no new
                // support directory just to list available hardware.
                var isDirectory: ObjCBool = false
                let hasWorkingDirectory = FileManager.default.fileExists(atPath: paths.workingDirectory.path,
                    isDirectory: &isDirectory) && isDirectory.boolValue
                let cwd = hasWorkingDirectory ? paths.workingDirectory : FileManager.default.temporaryDirectory
                return try SystemSectoriumDeviceObserver(runner: commandRunner, workingDirectory: cwd)
                    .observeDevices()
            }
        }
        return try result.get()
    }
    /// Early presentation only. This bounded metadata snapshot does not wait for
    /// automation's Service lock and cannot establish readiness or action rights.
    public func observeSectoriumInventoryForDisplay() throws -> [SectoriumPhysicalDevice] {
        try observationRunner.withFreshObservation { try observeSectoriumDevices() }
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
        sectoriumProfilesObservation() ?? []
    }

    /// Nil means the registry could not be trusted or read. An empty array is
    /// authoritative only for an absent or valid empty registry.
    public func sectoriumProfilesObservation(resolvePaths: Bool = true) -> [SectoriumDevelopmentProfile]? {
        serial.lock(); defer { serial.unlock() }
        guard let profiles = readSectoriumProfiles() else { return nil }
        // Registration can be published before slow device observation. These
        // saved paths are display data; per-profile readiness resolves them fresh.
        return resolvePaths ? profiles.map { resolvedProfile($0) ?? $0 } : profiles
    }

    /// Resolve only the row currently being observed, after the caller has
    /// prioritized devices. Missing metadata does not erase its saved identity.
    public func sectoriumProfileObservation(profileID: String) -> SectoriumDevelopmentProfile? {
        serial.lock(); defer { serial.unlock() }
        guard let saved = readSectoriumProfiles()?.first(where: { $0.id == profileID }) else { return nil }
        return resolvedProfile(saved) ?? saved
    }

    private func readSectoriumProfiles() -> [SectoriumDevelopmentProfile]? {
        serial.lock(); defer { serial.unlock() }
        guard paths.root.standardizedFileURL.path == paths.root.resolvingSymlinksInPath().path,
              paths.sectoriumProfiles.standardizedFileURL.path == paths.sectoriumProfiles.resolvingSymlinksInPath().path else { return nil }
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: paths.sectoriumProfiles.path) }
        catch let error as NSError {
            // fileExists also returns false for access errors. Only an actual
            // missing file establishes an empty registry.
            guard error.domain == NSCocoaErrorDomain,
                  [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) else { return nil }
            return []
        }
        guard (attributes[.type] as? FileAttributeType) == .typeRegular,
              let data = try? Data(contentsOf: paths.sectoriumProfiles) else { return nil }
        return Self.decodeSectoriumProfiles(data)
    }

    /// Schema/path-string checks only, shared with the cheap consistency probe.
    /// This does not resolve backing devices, images or filesystem paths.
    static func decodeSectoriumProfiles(_ data: Data) -> [SectoriumDevelopmentProfile]? {
        guard let profiles = try? JSONDecoder().decode([SectoriumDevelopmentProfile].self, from: data),
              Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map(\.imagePath)).count == profiles.count,
              Set(profiles.map(\.devMountPoint)).count == profiles.count,
              Set(profiles.compactMap(\.devUUID)).count == profiles.compactMap(\.devUUID).count,
              profiles.allSatisfy({ profile in
                  UUID(uuidString: profile.id) != nil && !profile.deviceID.isEmpty
                      && Self.validVolumeName(profile.name)
                      && URL(fileURLWithPath: profile.backingMountPoint).standardizedFileURL.path == profile.backingMountPoint
                      && URL(fileURLWithPath: profile.imagePath).standardizedFileURL.path == profile.imagePath
                      && profile.imagePath.hasPrefix(profile.backingMountPoint + "/")
                      && URL(fileURLWithPath: profile.devMountPoint).standardizedFileURL.path == profile.devMountPoint
                      && !profile.devVolumeName.isEmpty && !profile.devVolumeName.contains("/")
              }) else { return nil }
        return profiles
    }

    public var registeredProfileConfigurationReady: Bool {
        serial.lock(); defer { serial.unlock() }
        return readSectoriumProfiles().map { !$0.isEmpty } ?? false
    }

    /// Read-only compatibility discovery; it never registers or adopts a profile.
    public func discoveredLegacyDevelopmentDisk() -> Bool {
        guard identityConfigurationReady, readSectoriumProfiles()?.isEmpty == true,
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
              readSectoriumProfiles()?.contains(where: { $0.deviceID == deviceID }) == false,
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
        // Completed whole ejects live in terminalEjectJournals and do not occupy this slot.
        return state.workbenchOperation ?? (state.ejectIntent ? "eject:intent-pending" : nil)
    }

    /// Allows a newly opened workbench to present the exact pending eject target even after
    /// the drive disappears. This is display context only; continuation revalidates the journal.
    public func pendingWholeDeviceEjectPhysicalIdentity() -> String? {
        serial.lock(); defer { serial.unlock() }
        guard let state = try? store.load(), state.ejectIntent,
              let journal = decodeEjectJournal(state.workbenchTarget),
              state.operationID == journal.operationID,
              state.workbenchOperation == "eject:\(journal.operationID)",
              journal.target.isWholeDevice, journal.target.isExternal,
              !journal.target.isSystemDevice, journal.target.inventoryComplete,
              journal.target.hasUniqueMembers else { return nil }
        return journal.target.physicalIdentity
    }

    public func sectoriumReadiness(deviceID: String?, selectedProfileID: String? = nil,
                                   devices: [SectoriumPhysicalDevice],
                                   profiles: [SectoriumDevelopmentProfile]) -> SectoriumWorkbenchReadiness {
        guard readSectoriumProfiles() != nil else { return .unknown("Registered profile configuration is unavailable or invalid") }
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
        if case .failure(let failure) = policy.validateOuter(backend.observeOuter()) {
            return failure == .outerReadOnly ? .readOnly : .unknown("Backing volume readiness could not be verified")
        }
        if let observation = backend.observe() {
            if !observation.dev.writable { return .readOnly }
            if case .success = policy.validate(observation) { return .ready }
            return .unknown("Mounted development disk identity or backing relation does not match")
        }
        if backend.imageIsDetached() || backend.verifiedUnmountedImageVolumeInfo() != nil { return .notStarted }
        return .unknown("Development disk state could not be verified")
    }

    /// Independent row assessment. It never relies on whichever profile was
    /// selected in another window, and Loaded is returned only for a fresh,
    /// writable image-to-parent-to-volume observation.
    public func profileReadiness(profileID: String) -> SectoriumWorkbenchReadiness {
        observationRunner.observationValue("readiness:" + profileID) {
            observeProfileReadiness(profileID: profileID)
        }
    }

    private func observeProfileReadiness(profileID: String) -> SectoriumWorkbenchReadiness {
        guard let saved = readSectoriumProfiles()?.first(where: { $0.id == profileID }) else {
            return .unknown("Registered development volume is unavailable")
        }
        guard let devices = try? observeSectoriumDevices() else { return .unknown("Device discovery is unavailable") }
        if verifiedSafelyEjectedDeviceIDs().contains(saved.deviceID)
            || !devices.contains(where: { $0.id == saved.deviceID || $0.volumeUUIDs.contains(saved.backingVolumeUUID) }) { return .ejected }
        guard let profile = resolvedProfile(saved),
              let device = verifiedDevice(profile.deviceID, requiringSelectionAnchor: false), imageIdentityMatches(profile) else {
            return .unknown("Parent drive or development image identity changed")
        }
        guard profile.hasVerifiedImageFormat, let policy = profilePolicy(profile),
              let backing = verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device),
              backing.uuid == profile.backingVolumeUUID else {
            return .unknown("Parent drive or development image identity could not be verified")
        }
        let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
        guard let outer = backend.observeOuter() else { return .unknown("Parent drive state is unavailable") }
        if case .failure(let failure) = policy.validateOuter(outer) {
            return failure == .outerReadOnly ? .readOnly : .unknown("Parent drive identity changed")
        }
        if let observation = backend.observe() {
            if !observation.dev.writable { return .readOnly }
            return (try? policy.validate(observation).get()) != nil ? .ready
                : .unknown("Development image or mounted volume identity changed")
        }
        return backend.imageIsDetached() || backend.verifiedUnmountedImageVolumeInfo() != nil ? .notStarted : .unknown("Development volume state is unavailable")
    }

    /// A missing observation is nil, never a fabricated Not Loaded badge.
    public func verifiedLoadedState(profileID: String) -> Bool? {
        serial.lock(); defer { serial.unlock() }
        switch profileReadiness(profileID: profileID) {
        case .ready: return true
        case .notStarted: return false
        case .ejected:
            guard let raw = readSectoriumProfiles()?.first(where: { $0.id == profileID }),
                  let devices = try? observeSectoriumDevices(),
                  (verifiedSafelyEjectedDeviceIDs().contains(raw.deviceID)
                    || !devices.contains(where: { $0.id == raw.deviceID || $0.volumeUUIDs.contains(raw.backingVolumeUUID) })) else { return nil }
            return false
        default: return nil
        }
    }

    public func profileActivity(profileID: String) -> OccupancyAssessment {
        profileActivityReport(profileID: profileID).assessment
    }
    public func profileActivityReport(profileID: String) -> SectoriumActivityReport {
        observationRunner.withFreshObservation {
            serial.lock(); defer { serial.unlock() }
            guard let profile = registeredProfile(profileID), let policy = profilePolicy(profile), imageIdentityMatches(profile) else {
                return .init(assessment: .incomplete(reason: "Development volume identity is unavailable"))
            }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            guard let seen = backend.observe(), case .success = policy.validate(seen) else {
                return .init(assessment: .incomplete(reason: "Loaded development volume could not be verified"))
            }
            return enrichActivityReport(backend.activityReport(scope: .dev))
        }
    }

    /// Includes every mounted member of the selected physical drive. A working
    /// directory is an open reference even when no writes are in progress.
    public func wholeDeviceActivity(physicalIdentity: String) -> OccupancyAssessment {
        wholeDeviceActivityReport(physicalIdentity: physicalIdentity).assessment
    }
    public func wholeDeviceActivityReport(physicalIdentity: String) -> SectoriumActivityReport {
        observationRunner.withFreshObservation {
            serial.lock(); defer { serial.unlock() }
            guard let device = verifiedDevice(physicalIdentity, requiringSelectionAnchor: false), device.isExternal,
                  let topology = makeWholeDeviceEjectDriver().observe(physicalIdentity: physicalIdentity),
                  topology.bsdName == device.bsdName else {
                return .init(assessment: .incomplete(reason: "Whole-drive membership could not be verified"))
            }
            var disks = Set(topology.volumes.filter(\.mounted).compactMap { $0.identity.split(separator: "|").last.map(String.init) })
            for image in topology.images where image.attached {
                guard let mounted = image.mountedVolumeIdentities else { return .init(assessment: .incomplete(reason: "Image mount state is unavailable")) }
                disks.formUnion(mounted.compactMap { $0.split(separator: "|").last.map(String.init) })
            }
            var processes: [SectoriumActivityProcess] = []
            for disk in disks.sorted() {
                guard disk.range(of: #"^disk[0-9]+(?:s[0-9]+)*$"#, options: .regularExpression) != nil else {
                    return .init(assessment: .incomplete(reason: "A related volume identifier could not be verified"))
                }
                let report = SectoriumActivityReport.parse(commandRunner.run("/usr/sbin/lsof",
                    ["-nP", "-Fpcf", "+f", "--", "/dev/\(disk)"], cwd: paths.workingDirectory))
                if case .incomplete = report.assessment { return report }
                processes += report.processes
            }
            let grouped = Dictionary(grouping: processes, by: \.processID).map { pid, rows in
                SectoriumActivityProcess(processID: pid, command: rows[0].command,
                    executablePath: rows.compactMap(\.executablePath).first, references: rows.flatMap(\.references))
            }.sorted { $0.processID < $1.processID }
            return enrichActivityReport(.init(assessment: grouped.isEmpty ? .noVisibleOccupancy : .busy(processIDs: grouped.map(\.processID)), processes: grouped))
        }
    }

    private func enrichActivityReport(_ report: SectoriumActivityReport) -> SectoriumActivityReport {
        #if canImport(AppKit)
        var owners: [Int32: NSRunningApplication] = [:]
        var parents: [Int32: Int32] = [:]
        var checked = Set<Int32>()
        let ancestryDeadline = Date().addingTimeInterval(2)
        let processes = report.processes.map { process in
            var pid = process.processID, visited = Set<Int32>()
            var owner: NSRunningApplication?
            // Parent attribution is advisory quit-prompt metadata. Unknown
            // ancestry remains a named blocking process and is never killed.
            for _ in 0..<12 {
                guard pid > 1, Date() < ancestryDeadline, visited.insert(pid).inserted else { break }
                if let known = owners[pid] { owner = known; break }
                if let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier != nil {
                    owner = app; owners[pid] = app; break
                }
                if checked.insert(pid).inserted {
                    let arguments = ["-p", String(pid), "-o", "ppid="]
                    let allowance = min(0.5, ancestryDeadline.timeIntervalSinceNow)
                    guard allowance > 0 else { break }
                    let result = (commandRunner as? HESectoriumTimedCommandRunning)?.run(
                        "/bin/ps", arguments, cwd: paths.workingDirectory, timeout: allowance)
                        ?? commandRunner.run("/bin/ps", arguments, cwd: paths.workingDirectory)
                    if result.succeeded, let parent = Int32(result.detail.trimmingCharacters(in: .whitespacesAndNewlines)), parent != pid {
                        parents[pid] = parent
                    }
                }
                guard let parent = parents[pid] else { break }; pid = parent
            }
            if let owner { for pid in visited { owners[pid] = owner } }
            return SectoriumActivityProcess(processID: process.processID, command: process.command,
                executablePath: process.executablePath, bundleIdentifier: owner?.bundleIdentifier,
                applicationName: owner?.localizedName, owningApplicationProcessID: owner?.processIdentifier,
                references: process.references)
        }
        return .init(assessment: report.assessment, processes: processes)
        #else
        return report
        #endif
    }

    private func activityFailure(_ activity: OccupancyAssessment, id: String,
                                 steps: [OperationStepResult]) -> OperationResult? {
        switch activity {
        case .noVisibleOccupancy: return nil
        case .busy: return workbenchFailure(id, steps, "An application or task is using this volume. It remains loaded; cancel or wait and check again.")
        case .incomplete: return workbenchFailure(id, steps, "Activity could not be checked. The volume remains loaded; retry the check before unloading.")
        }
    }

    public func stopDevelopmentDisk(profileID: String, checkpoint: SectoriumStopConfirmation) -> OperationResult {
        // The legacy Boolean is satisfied by the fresh available-signal check,
        // never by asking the user to assert that all external writers are known.
        if let failure = activityFailure(profileActivity(profileID: profileID), id: UUID().uuidString, steps: []) { return failure }
        return stopDevelopmentDisk(profileID: profileID, checkpoint: checkpoint, knownWritersClosed: true)
    }

    public func ejectExternalDevice(physicalIdentity: String,
                                    confirmation: SectoriumWholeDeviceEjectConfirmation) -> OperationResult {
        withProgress("sectorium.wholeDeviceEject") {
            serial.lock(); defer { serial.unlock() }
            return performConfirmedExternalEject(physicalIdentity: physicalIdentity, confirmation: confirmation)
        }
    }

    private func performConfirmedExternalEject(physicalIdentity: String,
                                               confirmation: SectoriumWholeDeviceEjectConfirmation) -> OperationResult {
        guard confirmation.physicalIdentity == physicalIdentity else {
            return workbenchFailure(UUID().uuidString, [], "The selected physical drive changed; review the current drive")
        }
        guard confirmation.isObservationOnly || confirmation.dependenciesCanFinishOffTarget else {
            return workbenchFailure(UUID().uuidString, [], "AUV runtime dependencies cannot safely finish after this drive is ejected")
        }
        // New ejects assess occupancy once in ejectSelectedExternalDevice. Continuations
        // need their own fresh scan; completed callbacks are observation-only.
        if confirmation.isContinuation && !confirmation.isObservationOnly,
           let failure = activityFailure(wholeDeviceActivity(physicalIdentity: physicalIdentity), id: UUID().uuidString, steps: []) { return failure }
        let checkpoint = confirmation.checkpoint(knownWritersClosed: true)
        return confirmation.isContinuation
            ? continueWholeDeviceEject(physicalIdentity: physicalIdentity, checkpoint: checkpoint)
            : ejectSelectedExternalDevice(physicalIdentity: physicalIdentity, checkpoint: checkpoint)
    }

    /// Only the writer's freshly verified managed document can be opened.
    public func portableDocumentURL(profileID: String) -> URL? {
        observationRunner.withFreshDeadline { observePortableDocumentURL(profileID: profileID) }
    }

    private func observePortableDocumentURL(profileID: String) -> URL? {
        serial.lock(); defer { serial.unlock() }
        guard let profile = registeredProfile(profileID),
              let context = portableContext(profile, includeVolumeFacts: false) else { return nil }
        return portableDocumentWriter.verifiedDocumentURL(context: context)
    }

    public func portableDocumentationPending(profileID: String) -> Bool {
        serial.lock(); defer { serial.unlock() }
        guard let profile = readSectoriumProfiles()?.first(where: { $0.id == profileID }) else { return true }
        guard let count = try? portableDocumentJournal.pendingCount(parentID: profile.deviceID) else { return true }
        return count > 0 || diagnostics.contains { $0.category == "portableDocumentPending" && $0.summary.hasPrefix(profileID + ": ") }
    }

    public func portableDocumentHistory(profileID: String) -> [SectoriumPortableDocumentEvent] {
        serial.lock(); defer { serial.unlock() }
        guard let profile = readSectoriumProfiles()?.first(where: { $0.id == profileID }) else { return [] }
        return (try? portableDocumentJournal.events(parentID: profile.deviceID)) ?? []
    }

    public func selectSectoriumDevice(_ id: String?, observedBSDName: String? = nil,
                                      observedDevice: SectoriumPhysicalDevice? = nil) {
        serial.lock(); defer { serial.unlock() }
        selectedSectoriumDeviceID = id
        selectedSectoriumBSDName = id == nil ? nil : observedBSDName
        selectedSectoriumObservedDevice = observedDevice?.id == id ? observedDevice : nil
        let matches = (readSectoriumProfiles() ?? []).filter { $0.deviceID == id }
        selectedSectoriumProfileID = matches.count == 1 ? matches.first?.id : nil
    }

    public func selectSectoriumProfile(_ id: String?) {
        serial.lock(); defer { serial.unlock() }
        guard let id, let profile = readSectoriumProfiles()?.first(where: { $0.id == id }),
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

    private func registeredProfile(_ id: String) -> SectoriumDevelopmentProfile? {
        guard let matches = readSectoriumProfiles()?.filter({ $0.id == id }), matches.count == 1 else { return nil }
        return matches.first.flatMap { resolvedProfile($0) }
    }

    /// A renamed/reconnected parent is resolved from its persistent volume UUID
    /// inside the same verified physical device. Saved absolute paths never pick
    /// a new device by display name or by a recycled BSD number.
    private func resolvedProfile(_ profile: SectoriumDevelopmentProfile) -> SectoriumDevelopmentProfile? {
        guard let device = verifiedDevice(profile.deviceID, requiringSelectionAnchor: false) else { return nil }
        let matches = device.mountedVolumePaths.compactMap { path -> (uuid: UUID, mountPoint: String)? in
            guard let backing = verifiedBackingVolume(URL(fileURLWithPath: path), on: device),
                  backing.uuid == profile.backingVolumeUUID else { return nil }
            return backing
        }
        guard matches.count == 1, let backing = matches.first else { return nil }
        guard profile.imagePath.hasPrefix(profile.backingMountPoint + "/") else { return nil }
        var resolved = profile
        if backing.mountPoint != profile.backingMountPoint {
            resolved.backingMountPoint = backing.mountPoint
            resolved.imagePath = backing.mountPoint + profile.imagePath.dropFirst(profile.backingMountPoint.count)
            if profile.devMountPoint.hasPrefix(profile.backingMountPoint + "/") {
                resolved.devMountPoint = backing.mountPoint + profile.devMountPoint.dropFirst(profile.backingMountPoint.count)
            }
        }
        return resolved
    }

    static func validVolumeName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 80 && !name.hasPrefix(".") && name != "." && name != ".."
            && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
            && !name.contains("/") && !name.contains(":")
            && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func imageFileIdentity(_ path: String) -> String? {
        guard URL(fileURLWithPath: path).standardizedFileURL.path == URL(fileURLWithPath: path).resolvingSymlinksInPath().path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let created = attributes[.creationDate] as? Date else { return nil }
        return "\(inode.uint64Value):\(Int64(created.timeIntervalSince1970 * 1000))"
    }

    private func imageIdentityMatches(_ profile: SectoriumDevelopmentProfile) -> Bool {
        guard let actual = Self.imageFileIdentity(profile.imagePath) else { return false }
        return profile.imageFileIdentity.map { $0 == actual } ?? true
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

    private func verifiedDevice(_ identifier: String,
                                requiringSelectionAnchor: Bool = true) -> SectoriumPhysicalDevice? {
        guard let devices = try? observeSectoriumDevices() else { return nil }
        let matches = devices.filter { $0.id == identifier }
        guard matches.count == 1, let device = matches.first, device.identityVerified else { return nil }
        if device.identityBasis == .uniqueBackingVolumeUUID {
            if requiringSelectionAnchor {
                guard selectedAnchorMatches(device) else { return nil }
            } else {
                // A registered headless agent has no UI selection. Re-establish the
                // single-volume physical identity from a fresh parent/volume probe.
                guard device.isVirtual != true, device.topologyComplete,
                      device.volumeMembers.count == 1,
                      let member = device.volumeMembers.first,
                      UUID(uuidString: identifier) == member.volumeUUID,
                      let mountPoint = member.mountPoint,
                      verifiedBackingVolume(URL(fileURLWithPath: mountPoint), on: device)?.uuid
                          == member.volumeUUID else { return nil }
            }
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
                  verifiedPhysicalParent(info: info, volumeUUID: uuid) == device.bsdName else {
                return nil
            }
        }
        return (uuid, mount)
    }

    private func verifiedPhysicalParent(info: [String: Any], volumeUUID: UUID) -> String? {
        guard let containerID = info["APFSContainerReference"] as? String else {
            return SectoriumDeviceCatalog.verifiedParentWholeDisk(info)
        }
        let outcome = commandRunner.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"], cwd: paths.workingDirectory)
        guard outcome.succeeded, let data = outcome.detail.data(using: .utf8),
              let root = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let containers = (root["Containers"] ?? root["APFSContainers"]) as? [[String: Any]] else { return nil }
        let matches = containers.filter { $0["ContainerReference"] as? String == containerID }
        guard matches.count == 1, let container = matches.first,
              let volumes = container["Volumes"] as? [[String: Any]],
              volumes.filter({ ($0["APFSVolumeUUID"] as? String).flatMap(UUID.init(uuidString:)) == volumeUUID
                  && $0["DeviceIdentifier"] as? String == info["DeviceIdentifier"] as? String }).count == 1,
              let stores = container["PhysicalStores"] as? [[String: Any]], stores.count == 1,
              let store = stores.first?["DeviceIdentifier"] as? String,
              let storeData = verifiedDiskInfoData(for: "/dev/\(store)"),
              let storeInfo = (try? PropertyListSerialization.propertyList(from: storeData, options: [], format: nil)) as? [String: Any]
        else { return nil }
        return SectoriumDeviceCatalog.verifiedParentWholeDisk(storeInfo)
    }

    private func portableVolumeRecord(_ profile: SectoriumDevelopmentProfile) -> SectoriumPortableVolumeRecord {
        var filesystem: String?, logicalCapacity: UInt64?
        if let policy = profilePolicy(profile) {
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            if let observation = backend.observe(), case .success = policy.validate(observation),
               let info = diskInfoDictionary(profile.devMountPoint) {
                filesystem = info["FilesystemName"] as? String ?? info["FileSystemPersonality"] as? String ?? info["FilesystemType"] as? String
                logicalCapacity = Self.byteValue(info, keys: ["VolumeSize", "TotalSize"], allowZero: false)
            }
        }
        // Previously verified facts remain useful while unloaded; unvalidated
        // requested capacity is deliberately not presented as measured capacity.
        if profile.validation == .validated {
            filesystem = filesystem ?? profile.filesystem?.rawValue
            logicalCapacity = logicalCapacity ?? profile.logicalCapacityBytes
        }
        return .init(profileID: profile.id, name: profile.name, volumeUUID: profile.devUUID,
            filesystem: filesystem, logicalCapacityBytes: logicalCapacity, allocatedBytes: nil,
            imagePath: profile.imagePath, mountPoint: profile.devMountPoint,
            autoLoad: profile.autoLoadWasConfigured ? profile.autoLoad : installer.automationEnabled(),
            createdAt: profile.createdAt, modifiedAt: profile.modifiedAt,
            lastVerifiedLoadedAt: profile.lastVerifiedLoadedAt, formatMethod: profile.imageFormat)
    }

    /// Persisted context only selects a document host UUID. Its path and physical
    /// ownership are always observed again before writing to the parent.
    private func portableContext(_ profile: SectoriumDevelopmentProfile, includeVolumeFacts: Bool = true) -> SectoriumPortableDocumentContext? {
        guard let device = verifiedDevice(profile.deviceID, requiringSelectionAnchor: false),
              let existing = readSectoriumProfiles() else { return nil }
        var profiles = existing.filter { $0.deviceID == profile.deviceID }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        let resolved = profiles.compactMap(resolvedProfile)
        guard resolved.count == profiles.count else { return nil }
        let preferred = (try? portableDocumentJournal.latestContext(parentID: profile.deviceID))?.parent.documentVolumeUUID
            ?? resolved.sorted(by: { $0.id < $1.id }).first?.backingVolumeUUID
        guard let hostUUID = preferred else { return nil }
        let candidates = device.mountedVolumePaths.compactMap { path -> (uuid: UUID, mountPoint: String)? in
            guard let backing = verifiedBackingVolume(URL(fileURLWithPath: path), on: device), backing.uuid == hostUUID else { return nil }
            return backing
        }
        guard candidates.count == 1, let backing = candidates.first, backing.mountPoint != "/",
              let info = diskInfoDictionary(backing.mountPoint) else { return nil }
        let parent = SectoriumPortableParentRecord(physicalID: device.id, name: device.name,
            physicalCapacityBytes: device.wholeDeviceBytes, documentVolumeUUID: backing.uuid,
            rootPath: backing.mountPoint,
            filesystem: info["FilesystemName"] as? String ?? info["FilesystemType"] as? String,
            totalBytes: Self.byteValue(info, keys: ["VolumeSize", "TotalSize"], allowZero: false),
            availableBytes: Self.byteValue(info, keys: ["VolumeFreeSpace", "FreeSpace"]))
        // Opening a verified managed file needs its host identity, not a new
        // inventory of every development image. Writes still collect full facts.
        return .init(parent: parent, volumes: includeVolumeFacts ? resolved.map(portableVolumeRecord) : [])
    }

    private func diskInfoDictionary(_ target: String) -> [String: Any]? {
        guard let data = verifiedDiskInfoData(for: target) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
    private static func observedFilesystem(_ info: [String: Any]) -> SectoriumFilesystem? {
        let value = ((info["FileSystemPersonality"] as? String) ?? (info["FilesystemName"] as? String)
            ?? (info["FilesystemType"] as? String) ?? "").lowercased()
        guard value.contains("apfs") else { return nil }
        return value.contains("case-sensitive") || value == "apfsx" || info["CaseSensitive"] as? Bool == true ? .apfsCaseSensitive : .apfs
    }
    private static func byteValue(_ info: [String: Any], keys: [String], allowZero: Bool = true) -> UInt64? {
        // Native APFS metadata can report VolumeSize=0 while TotalSize is known.
        // Zero remains valid for free space, but is not a measured volume capacity.
        for key in keys {
            if let n = info[key] as? NSNumber, n.int64Value >= 0,
               allowZero || n.uint64Value > 0 { return n.uint64Value }
        }
        return nil
    }

    private static func portableIntentKind(_ kind: String) -> String {
        switch kind {
        case "create", "created": return "creationIntended"
        case "modify", "modified": return "modificationIntended"
        case "start": return "loaded"
        case "stop", "unload": return "unloaded"
        case "eject": return "ejected"
        case "adopt": return "registered"
        case "resume": return "validated"
        default: return kind
        }
    }

    @discardableResult
    private func recordPortableIntent(_ profile: SectoriumDevelopmentProfile, operation: String,
                                      kind: String) -> Bool {
        guard let context = portableContext(profile) else { return false }
        let eventID = operation + ":" + profile.id + ":intended"
        do {
            if try portableDocumentJournal.events(parentID: profile.deviceID).contains(where: { $0.id == eventID }) { return true }
            try portableDocumentJournal.record(context: context, event: .init(id: eventID, occurredAt: Date(),
                profileID: profile.id, kind: Self.portableIntentKind(kind), phase: .intended, before: portableVolumeRecord(profile)))
            return true
        } catch { recordPortableDocumentPending(profileID: profile.id, reason: "Operation history could not be durably recorded"); return false }
    }

    @discardableResult
    private func updatePortableDocument(_ profile: SectoriumDevelopmentProfile, event: String,
                                        operation: String, synchronize: Bool = true) -> SectoriumPortableDocumentResult {
        guard let context = portableContext(profile) else {
            let reason = "Fresh parent identity unavailable; documentation remains pending"
            recordPortableDocumentPending(profileID: profile.id, reason: reason)
            return .pending(reason)
        }
        do {
            let history = try portableDocumentJournal.events(parentID: profile.deviceID)
            let eventID = operation + ":" + profile.id + ":completed"
            if !history.contains(where: { $0.id == eventID }) {
                let before = history.first(where: { $0.id == operation + ":" + profile.id + ":intended" })?.before
                try portableDocumentJournal.record(context: context, event: .init(id: eventID, occurredAt: Date(),
                    profileID: profile.id, kind: event, before: before, after: portableVolumeRecord(profile)))
            }
        } catch {
            let reason = "Storage changed, but local documentation history could not be recorded"
            recordPortableDocumentPending(profileID: profile.id, reason: reason)
            return .pending(reason)
        }
        guard synchronize else {
            let reason = "Operation history is saved; external documentation remains pending"
            recordPortableDocumentPending(profileID: profile.id, reason: reason)
            return .pending(reason)
        }
        let result = portableDocumentJournal.synchronize(context: context, writer: portableDocumentWriter)
        recordPortableResult(result, profileID: profile.id)
        return result
    }

    /// The internal completion must survive a crash before we discard the storage
    /// recovery marker. A failed external IMPORTANT write remains independently
    /// retryable and must not turn a verified storage result into failure.
    private func completePortableOperation(_ profile: SectoriumDevelopmentProfile,
                                          event: String, operation: String) -> Bool {
        _ = updatePortableDocument(profile, event: event, operation: operation)
        return (try? portableDocumentJournal.events(parentID: profile.deviceID).contains {
            $0.id == operation + ":" + profile.id + ":completed"
        }) == true
    }

    /// Completing Unload changes no profile facts. Its pre-mutation context is
    /// already durable on the internal disk; avoid a second disk graph traversal
    /// (or an external file write) before publishing the native command result.
    private func recordDeferredPortableCompletion(_ profile: SectoriumDevelopmentProfile,
                                                  event: String, operation: String) {
        do {
            guard let context = try portableDocumentJournal.latestContext(parentID: profile.deviceID) else {
                recordPortableDocumentPending(profileID: profile.id, reason: "Storage operation completed; documentation context is unavailable")
                return
            }
            let events = try portableDocumentJournal.events(parentID: profile.deviceID)
            let eventID = operation + ":" + profile.id + ":completed"
            if !events.contains(where: { $0.id == eventID }) {
                let before = events.first(where: { $0.id == operation + ":" + profile.id + ":intended" })?.before
                    ?? context.volumes.first(where: { $0.profileID == profile.id })
                try portableDocumentJournal.record(context: context, event: .init(id: eventID, occurredAt: Date(),
                    profileID: profile.id, kind: event, before: before, after: before))
            }
            recordPortableDocumentPending(profileID: profile.id, reason: "Operation completed; optional documentation will update later")
        } catch {
            recordPortableDocumentPending(profileID: profile.id, reason: "Storage operation completed; local documentation update is pending")
        }
    }

    private func recordPortableResult(_ result: SectoriumPortableDocumentResult, profileID: String) {
        diagnostics.removeAll { $0.category == "portableDocumentPending" && $0.summary.hasPrefix(profileID + ": ") }
        if case .pending(let reason) = result { recordPortableDocumentPending(profileID: profileID, reason: reason) }
    }
    private func recordPortableDocumentPending(profileID: String, reason: String) {
        diagnostics.removeAll { $0.category == "portableDocumentPending" && $0.summary.hasPrefix(profileID + ": ") }
        diagnostics.append(.init(category: "portableDocumentPending", summary: String("\(profileID): \(reason)".prefix(240))))
        diagnostics = Array(diagnostics.suffix(20))
    }

    /// Retry synchronizes the original immutable event history. It never creates a
    /// fake validation event or repeats a storage action.
    public func retryPortableDocumentation(profileID: String) -> SectoriumPortableDocumentResult {
        performProgress("sectorium.documentation", rejected: .pending("AUV is closing; documentation remains pending")) {
        serial.lock(); defer { serial.unlock() }
        guard lock.acquire() else { return .pending("Another storage operation is running") }
        defer { lock.release() }
        guard let profile = registeredProfile(profileID), let context = portableContext(profile) else {
            return .pending("Registered parent is unavailable; reconnect it before retrying documentation")
        }
        let result = portableDocumentJournal.synchronize(context: context, writer: portableDocumentWriter)
        recordPortableResult(result, profileID: profileID)
        return result
        }
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
        guard var profiles = readSectoriumProfiles() else {
            throw RuntimeError.installConflict("Profile registry is unavailable or invalid; existing bytes preserved")
        }
        // A conflicting image or mount target must never replace another
        // registered profile or poison the entire registry for every disk.
        guard !profiles.contains(where: { $0.id != profile.id &&
            ($0.imagePath == profile.imagePath || $0.devMountPoint == profile.devMountPoint ||
             (profile.devUUID != nil && $0.devUUID == profile.devUUID)) }) else {
            throw RuntimeError.installConflict("Profile image, mount location, or volume identity is already registered")
        }
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        guard Set(profiles.map(\.id)).count == profiles.count,
              Set(profiles.map(\.imagePath)).count == profiles.count,
              Set(profiles.map(\.devMountPoint)).count == profiles.count,
              Set(profiles.compactMap(\.devUUID)).count == profiles.compactMap(\.devUUID).count,
              profiles.allSatisfy({ p in
                  UUID(uuidString: p.id) != nil && !p.deviceID.isEmpty && Self.validVolumeName(p.name)
                      && p.imagePath.hasPrefix(p.backingMountPoint + "/")
                      && URL(fileURLWithPath: p.backingMountPoint).standardizedFileURL.path == p.backingMountPoint
                      && URL(fileURLWithPath: p.imagePath).standardizedFileURL.path == p.imagePath
                      && URL(fileURLWithPath: p.devMountPoint).standardizedFileURL.path == p.devMountPoint
                      && !p.devVolumeName.isEmpty && !p.devVolumeName.contains("/")
              }) else { throw RuntimeError.installConflict("Updated registry conflicts with another registered volume") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: paths.sectoriumProfiles, options: .atomic)
        if selectedSectoriumDeviceID == profile.deviceID { selectedSectoriumProfileID = profile.id }
        #if canImport(Darwin)
        guard chmod(paths.sectoriumProfiles.path, mode_t(0o600)) == 0 else { throw RuntimeError.unsafePath("cannot secure profile registry") }
        #endif
    }

    /// Workbench operations already hold the shared storage lock. Persist these
    /// profile intents directly instead of re-entering a lock-acquiring Core API.
    private func suppressProfile(_ profileID: String) -> Bool {
        guard let state = try? store.load() else { return false }
        var next = state.advancingRevision()
        guard next.suppressProfile(profileID) else { return false }
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func clearSuppressionAfterValidatedLoad(_ profileID: String,
                                                    policy: StorageIdentityPolicy,
                                                    observation: StorageObservation) -> Bool {
        guard let state = try? store.load() else { return false }
        var next = state.advancingRevision()
        guard next.clearProfileSuppressionAfterValidatedLoad(profileID, policy: policy,
                                                             observation: observation) else { return false }
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func setWorkbenchMarker(_ marker: String) -> Bool {
        guard let state = try? store.load(), state.workbenchOperation == nil else { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: marker,
            workbenchPhase: "validating", workbenchTarget: nil, workbenchCompletedStep: nil,
            workbenchTerminalResult: nil)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: updated)) == true
    }

    /// Records an irreversible boundary before invoking any mutating storage/profile operation.
    /// The original central marker remains present throughout the operation.
    private func beginWorkbenchMutation(operation: String, target: String?, step: String) -> Bool {
        guard let state = try? store.load(), let marker = state.workbenchOperation,
              marker == operation || marker.hasSuffix(":\(operation)") else { return false }
        if let target, let profiles = readSectoriumProfiles(),
           let profile = profiles.first(where: { target == $0.imagePath || target.hasSuffix(":" + $0.imagePath) }),
           !recordPortableIntent(profile, operation: operation, kind: String(marker.split(separator: ":").first ?? "storage")) { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: marker,
            workbenchPhase: "mutating:\(step)", workbenchTarget: target ?? state.workbenchTarget,
            workbenchCompletedStep: state.workbenchCompletedStep, workbenchTerminalResult: nil)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: updated)) == true
    }

    private func completeWorkbenchStep(operation: String, step: String) -> Bool {
        guard let state = try? store.load(), let marker = state.workbenchOperation,
              marker == operation || marker.hasSuffix(":\(operation)") else { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: marker,
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
            outerReconnectAttempted: state.outerReconnectAttempted, suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: state.workbenchOperation,
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
            outerReconnectAttempted: state.outerReconnectAttempted, suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: state.workbenchOperation,
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
            outerReconnectAttempted: state.outerReconnectAttempted, suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: nil,
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
            suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: state.workbenchOperation, workbenchPhase: "mutating:persistEjectIntent",
            workbenchTarget: target, workbenchCompletedStep: nil, workbenchTerminalResult: nil)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func markOuterAbsentAfterEject() -> Bool {
        guard let state = try? store.load(), state.ejectIntent else { return false }
        let next = StoragePersistentState(revision: state.revision + 1, ejectIntent: true,
            operationID: state.operationID, outerDisappearedAfterIntent: true, outerReconnectAttempted: false,
            suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: state.workbenchOperation, workbenchPhase: state.workbenchPhase,
            workbenchTarget: state.workbenchTarget, workbenchCompletedStep: state.workbenchCompletedStep,
            workbenchTerminalResult: state.workbenchTerminalResult)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func clearEjectIntent() -> Bool {
        guard let state = try? store.load(), state.ejectIntent else { return false }
        let next = StoragePersistentState(revision: state.revision + 1, ejectIntent: false,
            operationID: state.operationID, outerDisappearedAfterIntent: false, outerReconnectAttempted: false,
            suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: state.workbenchOperation, workbenchPhase: state.workbenchPhase,
            workbenchTarget: state.workbenchTarget, workbenchCompletedStep: state.workbenchCompletedStep,
            workbenchTerminalResult: state.workbenchTerminalResult)
        return (try? store.compareAndSwap(expectedRevision: state.revision, newState: next)) == true
    }

    private func clearWorkbenchMarker(terminal: String = "completed") -> Bool {
        guard let state = try? store.load() else { return false }
        let updated = StoragePersistentState(revision: state.revision + 1, ejectIntent: state.ejectIntent,
            operationID: state.operationID, outerDisappearedAfterIntent: state.outerDisappearedAfterIntent,
            outerReconnectAttempted: state.outerReconnectAttempted, suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
            workbenchOperation: nil,
            workbenchPhase: "completed", workbenchTarget: state.workbenchTarget,
            workbenchCompletedStep: state.workbenchCompletedStep, workbenchTerminalResult: terminal)
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
            suppressedProfileIDs: state.suppressedProfileIDs,
            disconnectedProfileIDs: state.disconnectedProfileIDs,
            reconnectAttemptedProfileIDs: state.reconnectAttemptedProfileIDs,
            terminalEjectJournals: state.terminalEjectJournals,
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
        guard Self.validVolumeName(profile.name),
              profile.imagePath.hasPrefix(profile.backingMountPoint + "/"),
              !profile.devVolumeName.isEmpty, !profile.devVolumeName.contains("/"),
              URL(fileURLWithPath: profile.devMountPoint).standardizedFileURL.path == profile.devMountPoint else { return nil }
        return StorageIdentityPolicy(outerUUID: profile.backingVolumeUUID, devUUID: profile.devUUID,
            outerMountPoint: profile.backingMountPoint, devMountPoint: profile.devMountPoint,
            devVolumeName: profile.devVolumeName, imagePath: profile.imagePath)
    }

    /// Compatibility source API retains creation-only semantics. The focused
    /// new-flow request below also performs a verified initial load.
    public func createDevelopmentDisk(deviceID: String, parentDirectory: URL, name: String, capacityGiB: Int,
                                      caseSensitive: Bool, password: String?) -> OperationResult {
        createDevelopmentDiskOnly(.init(deviceID: deviceID, parentDirectory: parentDirectory,
            name: name, capacityGiB: capacityGiB,
            filesystem: caseSensitive ? .apfsCaseSensitive : .apfs,
            password: password))
    }

    public func supportedCreationFilesystems() -> [SectoriumFilesystem] {
        // These are the native hdiutil writable formats used by this service.
        // A filesystem merely visible in diskutil is not offered for creation.
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil"),
              FileManager.default.isExecutableFile(atPath: "/usr/sbin/diskutil") else { return [] }
        return SectoriumFilesystem.allCases
    }

    public func createDevelopmentDisk(_ request: SectoriumCreateRequest) -> OperationResult {
        withProgress("sectorium.createAndLoad") {
        serial.lock(); defer { serial.unlock() }
        let created = createDevelopmentDiskOnly(request)
        guard created.succeeded else { return created }
        guard let profile = sectoriumProfiles().first(where: { $0.deviceID == request.deviceID && $0.name == request.name &&
            $0.imagePath.hasSuffix("/\(request.name).sparsebundle") }) else {
            return .init(operationID: created.operationID, mode: .manual, steps: created.steps,
                         failure: .workbenchFailed("Image was created, but its exact registered profile could not be recovered"))
        }
        let loaded = startDevelopmentDisk(profileID: profile.id, password: request.password)
        return .init(operationID: created.operationID, mode: .manual,
                     steps: created.steps + loaded.steps, failure: loaded.failure)
        }
    }

    private func createDevelopmentDiskOnly(_ request: SectoriumCreateRequest) -> OperationResult {
        let deviceID = request.deviceID, name = request.name, capacityGiB = request.capacityGiB
        let password = request.password
        let caseSensitive = request.filesystem.caseSensitive
        return workbenchOperation("create") { id, steps in
            guard capacityGiB > 0, capacityGiB <= 16_384,
                  Self.validVolumeName(name) else {
                return workbenchFailure(id, steps, "Invalid name or capacity")
            }
            guard supportedCreationFilesystems().contains(request.filesystem) else {
                return workbenchFailure(id, steps, "Selected filesystem is not available for writable native creation")
            }
            guard password == nil || (hdiutilPassphraseInput(password!) != nil && commandRunner is HESectoriumSecureCommandRunning) else {
                return workbenchFailure(id, steps, "Encrypted creation requires a secure stdin command runner")
            }
            guard let device = verifiedDevice(deviceID) else {
                return workbenchFailure(id, steps, "Selected physical drive identity is unavailable")
            }
            let candidates = request.parentDirectory.map { [$0] } ?? device.mountedVolumePaths.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            let suitable = candidates.compactMap { candidate -> (URL, (uuid: UUID, mountPoint: String))? in
                guard isPlainDirectory(candidate), FileManager.default.isWritableFile(atPath: candidate.path),
                      let backing = verifiedBackingVolume(candidate, on: device),
                      let infoData = verifiedDiskInfoData(for: backing.mountPoint),
                      let info = (try? PropertyListSerialization.propertyList(from: infoData, options: [], format: nil)) as? [String: Any],
                      info["WritableVolume"] as? Bool == true else { return nil }
                return (candidate, backing)
            }
            guard suitable.count == 1, let (parentDirectory, backing) = suitable.first else {
                return workbenchFailure(id, steps, "Select one writable volume on the verified physical drive")
            }
            let free = (try? FileManager.default.attributesOfFileSystem(forPath: parentDirectory.path)[.systemFreeSize]) as? NSNumber
            guard let free, free.uint64Value >= 268_435_456 else {
                return workbenchFailure(id, steps, "Insufficient available parent storage for a new sparse development volume")
            }
            guard recordWorkbenchTarget(operation: id, target: "\(deviceID):\(parentDirectory.path)/\(name)") else {
                return workbenchFailure(id, steps, "Could not persist the selected create target")
            }
            let image = parentDirectory.appendingPathComponent("\(name).sparsebundle", isDirectory: true).standardizedFileURL
            guard let registered = readSectoriumProfiles() else {
                return workbenchFailure(id, steps, "Registered profile configuration is unavailable or invalid")
            }
            guard image.deletingLastPathComponent().resolvingSymlinksInPath().path == parentDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
                  !FileManager.default.fileExists(atPath: image.path),
                  !registered.contains(where: { $0.imagePath == image.path || $0.deviceID == deviceID && $0.name == name }) else {
                return workbenchFailure(id, steps, "Target already exists or is registered")
            }
            let profileID = UUID().uuidString
            // The empty mount target lives on the verified writable backing
            // filesystem. A host /Volumes directory would fail the attach
            // preflight and can collide across unrelated physical drives.
            let mount = request.mountPoint ?? URL(fileURLWithPath: backing.mountPoint, isDirectory: true)
                .appendingPathComponent(".AUV-Sectorium-Mounts", isDirectory: true)
                .appendingPathComponent(profileID, isDirectory: true).path
            guard URL(fileURLWithPath: mount).standardizedFileURL.path == mount,
                  mount.hasPrefix(backing.mountPoint + "/"),
                  !FileManager.default.fileExists(atPath: mount),
                  !registered.contains(where: { $0.devMountPoint == mount }) else {
                return workbenchFailure(id, steps, "Development volume mount point is occupied, unsafe, or already registered")
            }
            let profile = SectoriumDevelopmentProfile(id: profileID, name: name, deviceID: deviceID, backingVolumeUUID: backing.uuid,
                backingMountPoint: backing.mountPoint, imagePath: image.path, devVolumeName: name,
                devMountPoint: mount, encrypted: password != nil, caseSensitive: caseSensitive,
                logicalCapacityBytes: UInt64(capacityGiB) * 1_073_741_824,
                filesystem: request.filesystem, autoLoad: request.autoLoad, createdAt: Date())
            guard recordPortableIntent(profile, operation: id, kind: "created"),
                  beginWorkbenchMutation(operation: id, target: image.path, step: "recordProfile") else {
                return workbenchFailure(id, steps, "Could not persist the profile mutation boundary")
            }
            do { try saveProfile(profile) } catch { return workbenchFailure(id, steps, "Could not durably record operation: \(error.localizedDescription)") }
            steps.append(.init(step: "recordProfile", status: .succeeded))
            guard completeWorkbenchStep(operation: id, step: "recordProfile") else {
                return workbenchFailure(id, steps, "Profile recorded but its recovery step could not be persisted")
            }
            var args = ["create", "-size", "\(capacityGiB)g", "-type", "SPARSEBUNDLE", "-fs", request.filesystem.rawValue, "-volname", name, "-layout", "SPUD"]
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
            var verifiedProfile = profile
            verifiedProfile.imageFormat = imageFormat
            guard let fileID = Self.imageFileIdentity(image.path) else {
                return workbenchFailure(id, steps, "Created image file identity could not be verified")
            }
            verifiedProfile.imageFileIdentity = fileID
            do { try saveProfile(verifiedProfile) }
            catch {
                steps.append(.init(step: "verifyImageFormat", status: .failed, detail: "Verified format could not be durably recorded"))
                return workbenchFailure(id, steps, "Verified image format could not be durably recorded")
            }
            steps.append(.init(step: "verifyImageFormat", status: .succeeded, detail: imageFormat))
            guard completePortableOperation(verifiedProfile, event: "registered", operation: id),
                  clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Image created but its durable completion remains pending") }
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    /// hdiutil's documented `imageinfo -format` output is accepted only as the exact
    /// sparse-bundle format token this workflow creates; no suffix or plist-key inference.
    static func documentedSparsebundleFormat(_ output: String) -> String? {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "UDSB" ? value : nil
    }

    /// A mounted image can refuse `hdiutil imageinfo` with EBUSY. Only callers
    /// that have freshly proved the complete backing/image/APFS chain may use
    /// the fixed bundle metadata instead. This describes format, not identity.
    private func observeSparsebundleFormat(_ imagePath: String, attachedChainVerified: Bool) -> CommandOutcome {
        if attachedChainVerified,
           Self.mountedSparsebundleMetadataFormat(URL(fileURLWithPath: imagePath)) == "UDSB" {
            return .init(exitCode: 0, detail: "UDSB")
        }
        let outcome = commandRunner.run("/usr/bin/hdiutil", ["imageinfo", imagePath, "-format"], cwd: paths.workingDirectory)
        guard outcome.succeeded else {
            return .init(exitCode: outcome.exitCode,
                detail: attachedChainVerified
                    ? "Mounted image format metadata could not be verified; the image is unchanged. \(outcome.detail)"
                    : "Image format inspection failed; the image is unchanged. \(outcome.detail)")
        }
        return outcome
    }

    /// Reads only Info.plist, through no-follow directory descriptors. No bands,
    /// project files, or directory listings are read. Unknown versions fail closed.
    static func mountedSparsebundleMetadataFormat(_ imageURL: URL) -> String? {
        let requestedPath = imageURL.standardizedFileURL.path
        guard imageURL.isFileURL, imageURL.pathExtension == "sparsebundle",
              requestedPath == imageURL.resolvingSymlinksInPath().standardizedFileURL.path else { return nil }
        // Match SecureDirectory's handling of the two documented macOS aliases.
        // Foundation rewrites even resolved /private/tmp and /private/var URLs.
        let physicalPath = requestedPath.hasPrefix("/tmp/") || requestedPath.hasPrefix("/var/")
            ? "/private" + requestedPath : requestedPath
        #if canImport(Darwin)
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { return nil }
        defer { close(directory) }
        for component in physicalPath.split(separator: "/") {
            let next = openat(directory, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { return nil }
            close(directory); directory = next
        }
        let descriptor = openat(directory, "Info.plist", O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var status = stat()
        let limit = 65_536
        guard fstat(descriptor, &status) == 0, (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              status.st_size > 0, status.st_size <= limit else { return nil }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count >= 0, data.count + count <= limit else { return nil }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard let info = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              info["diskimage-bundle-type"] as? String == "com.apple.diskimage.sparsebundle",
              let version = info["bundle-backingstore-version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.stringValue == "2",
              let bandValue = info["band-size"] as? NSNumber, let band = UInt64(bandValue.stringValue),
              band >= 512, band.nonzeroBitCount == 1,
              let sizeValue = info["size"] as? NSNumber, let size = UInt64(sizeValue.stringValue),
              size >= 512 else { return nil }
        return "UDSB"
        #else
        return nil
        #endif
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
            let adoptedProfileID = UUID().uuidString
            let detachedMountPoint = legacyIdentity ? configured.devMountPoint : URL(fileURLWithPath: backing.mountPoint)
                .appendingPathComponent(".AUV-Sectorium-Mounts").appendingPathComponent(adoptedProfileID).path
            guard let registered = readSectoriumProfiles() else {
                return workbenchFailure(id, steps, "Registered profile configuration is unavailable or invalid")
            }
            guard !registered.contains(where: {
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
            guard let formatImageIdentity = Self.imageFileIdentity(imagePath) else {
                return workbenchFailure(id, steps, "Selected image identity is unavailable")
            }
            let formatOutcome = observeSparsebundleFormat(imagePath, attachedChainVerified: isAttached)
            guard formatOutcome.succeeded, let imageFormat = Self.documentedSparsebundleFormat(formatOutcome.detail) else {
                return workbenchFailure(id, steps, "Selected sparsebundle format could not be verified. \(formatOutcome.detail)")
            }
            var mountedFilesystem: SectoriumFilesystem?, mountedCapacity: UInt64?
            if isAttached, let info = diskInfoDictionary(devMountPoint) {
                let uuid = ((info["VolumeUUID"] as? String) ?? (info["APFSVolumeUUID"] as? String))
                    .flatMap(UUID.init(uuidString:))
                guard uuid == verifiedDevUUID, info["MountPoint"] as? String == devMountPoint else {
                    return workbenchFailure(id, steps, "Mounted volume identity changed while reading its display metadata")
                }
                mountedFilesystem = Self.observedFilesystem(info)
                mountedCapacity = Self.byteValue(info, keys: ["VolumeSize", "TotalSize"], allowZero: false)
            }
            var profile = SectoriumDevelopmentProfile(
                id: adoptedProfileID, name: profileName, deviceID: deviceID, backingVolumeUUID: backing.uuid,
                backingMountPoint: backing.mountPoint, imagePath: imagePath,
                devVolumeName: devVolumeName, devMountPoint: devMountPoint,
                devUUID: verifiedDevUUID, encrypted: storageBackend.imageEncryptionState(), caseSensitive: mountedFilesystem?.caseSensitive,
                logicalCapacityBytes: mountedCapacity, imageFormat: imageFormat,
                validation: .pendingValidation, filesystem: mountedFilesystem)
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
            guard Self.imageFileIdentity(imagePath) == formatImageIdentity else {
                return workbenchFailure(id, steps, "Selected image was replaced during adoption; its registration is unchanged")
            }
            profile.imageFileIdentity = formatImageIdentity
            guard recordPortableIntent(profile, operation: id, kind: "registered"),
                  beginWorkbenchMutation(operation: id, target: imagePath, step: "saveVerifiedImageProfile") else {
                return workbenchFailure(id, steps, "Could not persist the profile adoption boundary")
            }
            do { try saveProfile(profile) }
            catch { return workbenchFailure(id, steps, "Could not durably record the verified sparsebundle profile") }
            guard completeWorkbenchStep(operation: id, step: "saveVerifiedImageProfile"),
                  completePortableOperation(profile, event: "registered", operation: id),
                  clearWorkbenchMarker() else {
                return workbenchFailure(id, steps, "Profile was recorded but operation recovery state remains pending")
            }
            steps.append(.init(step: "verifyImageIdentity", status: .succeeded,
                detail: isAttached ? "Selected backing volume, sparsebundle format, and attached APFS chain verified; optional image facts remain unknown"
                                   : "Selected backing volume and sparsebundle format verified; image remains detached and APFS identity is pending Start validation"))
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    /// Registers only the configured legacy image after the ordinary adoption path
    /// revalidates the selected physical device and full image/APFS identity.
    public func adoptConfiguredLegacyDevelopmentDisk(deviceID: String) -> OperationResult {
        adoptDevelopmentDisk(deviceID: deviceID,
            imageURL: URL(fileURLWithPath: coreController.identityPolicy.imagePath, isDirectory: true))
    }

    public func startDevelopmentDisk(password: String? = nil) -> OperationResult {
        startDevelopmentDisk(targetProfileID: nil, password: password)
    }

    public func startDevelopmentDisk(profileID: String, password: String? = nil) -> OperationResult {
        startDevelopmentDisk(targetProfileID: profileID, password: password)
    }

    private func startDevelopmentDisk(targetProfileID: String?, password: String?) -> OperationResult {
        // Fresh native reconnect evidence may settle an interrupted disconnect.
        // A manual Load must not depend on a prior UI refresh doing this first.
        _ = reconcileWholeDeviceEjectRecovery()
        _ = reconcileCompletedUnload()
        _ = reconcileInterruptedLoad()
        return workbenchOperation("start") { id, steps in
        guard var profile = targetProfileID.flatMap(registeredProfile) ??
            (targetProfileID == nil ? selectedProfile() : nil) else {
            return workbenchFailure(id, steps, "No explicitly selected development profile is available")
        }
        let startTarget = "\(profile.deviceID):\(profile.imagePath)"
        guard startTarget.count <= 512,
              recordWorkbenchTarget(operation: id, target: startTarget) else {
            return workbenchFailure(id, steps, "Could not persist the selected start target")
        }
        if profile.imageFormat == nil, profile.encrypted != nil,
           profile.caseSensitive != nil, profile.logicalCapacityBytes != nil {
            guard let device = verifiedDevice(profile.deviceID, requiringSelectionAnchor: targetProfileID == nil),
                  device.volumeUUIDs.contains(profile.backingVolumeUUID),
                  verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid
                      == profile.backingVolumeUUID,
                  profile.imagePath.hasPrefix(profile.backingMountPoint + "/"),
                  isPlainDirectory(URL(fileURLWithPath: profile.imagePath)),
                  URL(fileURLWithPath: profile.imagePath).resolvingSymlinksInPath().path == profile.imagePath else {
                return workbenchFailure(id, steps, "Legacy image format requires a fresh verified backing target")
            }
            let mountedPolicy = profilePolicy(profile)
            let mountedObservation = mountedPolicy.flatMap { MacStorageBackend(paths: paths, runner: commandRunner, policy: $0).observe() }
            let attachedChainVerified = mountedPolicy.flatMap { policy in
                mountedObservation.map { (try? policy.validate($0).get()) != nil }
            } ?? false
            let format = observeSparsebundleFormat(profile.imagePath, attachedChainVerified: attachedChainVerified)
            guard format.succeeded, let imageFormat = Self.documentedSparsebundleFormat(format.detail) else {
                return workbenchFailure(id, steps, "Legacy image format could not be verified")
            }
            var upgraded = profile
            upgraded.imageFormat = imageFormat
            guard beginWorkbenchMutation(operation: id, target: startTarget, step: "saveImageFormat") else {
                return workbenchFailure(id, steps, "Could not persist the legacy image-format registry boundary")
            }
            do { try saveProfile(upgraded) }
            catch { return workbenchFailure(id, steps, "Verified legacy format could not be durably recorded") }
            guard completeWorkbenchStep(operation: id, step: "saveImageFormat") else {
                return workbenchFailure(id, steps, "Legacy image format was saved but its recovery step is pending")
            }
            profile = upgraded
            steps.append(.init(step: "verifyImageFormat", status: .succeeded, detail: imageFormat))
        }
        guard profile.hasVerifiedImageFormat,
              let device = verifiedDevice(profile.deviceID, requiringSelectionAnchor: targetProfileID == nil),
                  device.volumeUUIDs.contains(profile.backingVolumeUUID),
                  verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid == profile.backingVolumeUUID,
                  profile.imagePath.hasPrefix(profile.backingMountPoint + "/"),
                  FileManager.default.fileExists(atPath: profile.imagePath), imageIdentityMatches(profile),
                  URL(fileURLWithPath: profile.imagePath).resolvingSymlinksInPath().path == profile.imagePath else {
                return workbenchFailure(id, steps, "Fresh backing-device and image identity validation failed")
            }
            let policy = profilePolicy(profile)
            guard let policy else { return workbenchFailure(id, steps, "Profile identity is invalid") }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            if let mounted = backend.observe(), case .success = policy.validate(mounted) {
                if profile.devUUID != mounted.dev.uuid || profile.validation != .validated || profile.lastVerifiedLoadedAt == nil {
                    var validated = profile
                    validated.devUUID = mounted.dev.uuid
                    validated.validation = .validated
                    validated.lastVerifiedLoadedAt = Date()
                    guard beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "saveValidatedProfile") else {
                        return workbenchFailure(id, steps, "Could not persist existing mounted profile validation boundary")
                    }
                    do { try saveProfile(validated) }
                    catch { return workbenchFailure(id, steps, "Verified mounted profile could not be saved") }
                    guard completeWorkbenchStep(operation: id, step: "saveValidatedProfile") else {
                        return workbenchFailure(id, steps, "Mounted profile was saved but its recovery step is pending")
                    }
                    profile = validated
                }
                guard completePortableOperation(profile, event: "loaded", operation: id),
                      clearSuppressionAfterValidatedLoad(profile.id, policy: policy, observation: mounted),
                      clearWorkbenchMarker() else {
                    return workbenchFailure(id, steps, "Mounted profile is ready but manual load intent could not be recorded")
                }
                steps.append(.init(step: "reuseVerifiedImage", status: .succeeded,
                                   detail: "Existing mounted image and backing chain verified"))
                return .init(operationID: id, mode: .manual, steps: steps)
            }
            let encryptionState = profile.encrypted ?? backend.imageEncryptionState()
            guard let encryptionState else {
                return workbenchFailure(id, steps, "Image encryption status could not be verified; no attach was attempted")
            }
            if let password, hdiutilPassphraseInput(password) == nil || !(commandRunner is HESectoriumSecureCommandRunning) {
                return workbenchFailure(id, steps, "Unlock requires a secure stdin command runner")
            }
            if encryptionState && backend.verifiedUnmountedImageVolumeInfo() == nil {
                guard let password, hdiutilPassphraseInput(password) != nil,
                      commandRunner is HESectoriumSecureCommandRunning else {
                    return workbenchFailure(id, steps, "Encryption is enabled; unlock requires a passphrase over secure stdin")
                }
            }
            guard beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "prepareMountPoint") else {
                return workbenchFailure(id, steps, "Could not persist the mount-point preparation boundary")
            }
            // Existing mount directories are not private runtime directories.
            // Preserve their contents, ownership and permissions; attachImage
            // validates the target structure and backing volume before dispatch.
            if !FileManager.default.fileExists(atPath: profile.devMountPoint) {
                do { try SecureDirectory.ensure(URL(fileURLWithPath: profile.devMountPoint, isDirectory: true)) }
                catch { return workbenchFailure(id, steps, "Could not prepare safe mount point") }
            }
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
            guard attached.succeeded else {
                return workbenchFailure(id, steps, "Load failed: " + (password == nil ? attached.detail : "Unlock/attach returned \(attached.exitCode)"))
            }
            guard let observation = backend.observe() else {
                return workbenchFailure(id, steps, "Load command completed, but the mounted image could not be verified")
            }
            let validatedPolicy = StorageIdentityPolicy(outerUUID: profile.backingVolumeUUID,
                devUUID: observation.dev.uuid, outerMountPoint: profile.backingMountPoint,
                devMountPoint: observation.dev.mountPoint, devVolumeName: observation.dev.name,
                imagePath: profile.imagePath)
            guard (profile.devUUID == nil || profile.devUUID == observation.dev.uuid),
                  (profile.devUUID == nil && profile.createdAt == nil || observation.dev.name == profile.devVolumeName),
                  case .success = validatedPolicy.validate(observation) else {
                return workbenchFailure(id, steps, "Image-to-backing APFS chain failed post-attach validation")
            }
            guard let actualInfo = diskInfoDictionary(observation.dev.mountPoint),
                  let actualFilesystem = Self.observedFilesystem(actualInfo),
                  profile.filesystem == nil || profile.filesystem == actualFilesystem else {
                return workbenchFailure(id, steps, "The mounted filesystem does not match the requested APFS format")
            }
            let actualCapacity = Self.byteValue(actualInfo, keys: ["VolumeSize", "TotalSize"], allowZero: false)
            if profile.devUUID != observation.dev.uuid || profile.devVolumeName != observation.dev.name
                || profile.devMountPoint != observation.dev.mountPoint || profile.encrypted != encryptionState || profile.validation != .validated
                || profile.lastVerifiedLoadedAt == nil || actualCapacity != profile.logicalCapacityBytes {
                var validated = profile; validated.devUUID = observation.dev.uuid
                validated.devVolumeName = observation.dev.name; validated.devMountPoint = observation.dev.mountPoint
                validated.encrypted = encryptionState; validated.validation = .validated
                validated.lastVerifiedLoadedAt = Date()
                validated.filesystem = actualFilesystem
                validated.logicalCapacityBytes = actualCapacity
                validated.imageFileIdentity = Self.imageFileIdentity(profile.imagePath)
                guard beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "saveValidatedProfile") else {
                    return workbenchFailure(id, steps, "Could not persist the profile-validation boundary")
                }
                do { try saveProfile(validated) } catch { return workbenchFailure(id, steps, "Mounted image validated but profile persistence failed") }
                guard completeWorkbenchStep(operation: id, step: "saveValidatedProfile") else {
                    return workbenchFailure(id, steps, "Validated profile saved but its recovery step could not be persisted")
                }
            }
            steps.append(.init(step: "validateImageChain", status: .succeeded, detail: "Mounted writable APFS chain matches selected backing volume"))
            guard clearSuppressionAfterValidatedLoad(profile.id, policy: validatedPolicy, observation: observation) else {
                return workbenchFailure(id, steps, "Mounted image validated but manual load intent could not be recorded")
            }
            let documentedProfile = readSectoriumProfiles()?.first(where: { $0.id == profile.id }) ?? profile
            guard completePortableOperation(documentedProfile, event: "loaded", operation: id),
                  clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Mounted successfully but its durable completion remains pending") }
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    /// Nil means the native grow operation can be attempted. Its command and
    /// postconditions can still refuse; a requested size is never saved as fact.
    public func capacityChangeAvailability(profileID: String) -> String? {
        observationRunner.withFreshObservation { observeCapacityChangeAvailability(profileID: profileID) }
    }

    private func observeCapacityChangeAvailability(profileID: String) -> String? {
        serial.lock(); defer { serial.unlock() }
        guard let profile = registeredProfile(profileID), imageIdentityMatches(profile),
              let policy = profilePolicy(profile), profile.validation == .validated else {
            return "Load and verify this development volume before changing its capacity."
        }
        let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
        guard backend.imageIsDetached() else { return "Unload this development volume before changing its capacity." }
        guard profile.encrypted == false else { return "Capacity changes for encrypted images are unavailable; the image is preserved." }
        return nil
    }

    public func updateDevelopmentDisk(profileID: String, change: SectoriumProfileChange) -> OperationResult {
        serial.lock(); defer { serial.unlock() }
        // Unsupported filesystem conversion is rejected without opening a storage
        // transaction, so an ordinary settings refusal cannot strand a busy marker.
        if case .filesystem(let filesystem) = change,
           let profile = registeredProfile(profileID), profile.filesystem != filesystem {
            return workbenchFailure(UUID().uuidString, [], "In-place filesystem conversion is unsupported. Create another volume and migrate deliberately; this volume will not be erased or recreated.")
        }
        return workbenchOperation("modify") { id, steps in
            guard var profile = registeredProfile(profileID), imageIdentityMatches(profile),
                  let policy = profilePolicy(profile) else {
                return workbenchFailure(id, steps, "The registered image and physical parent could not be verified")
            }
            let original = profile
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            var temporaryLoad = false
            var changed = false
            let documentEvent: String
            switch change {
            case .displayName: documentEvent = "displayNameChanged"
            case .autoLoad: documentEvent = "autoLoadChanged"
            case .mountPoint: documentEvent = "mountPointChanged"
            case .capacityGiB: documentEvent = "capacityChanged"
            case .filesystem: documentEvent = "filesystemChanged"
            }
            let before = backend.observe()
            let wasLoaded = before.map { observation -> Bool in
                if case .success = policy.validate(observation) { return true }; return false
            } ?? false
            let wasDetached = backend.imageIsDetached()
            guard wasLoaded || wasDetached else {
                return workbenchFailure(id, steps, "The image is attached in an unverified state; settings were not changed")
            }
            let recovery = SectoriumModificationRecovery(version: 1, operationID: id,
                before: original, change: change, wasLoaded: wasLoaded)
            guard let recoveryData = try? JSONEncoder().encode(recovery),
                  let recoveryTarget = String(data: recoveryData, encoding: .utf8) else {
                return workbenchFailure(id, steps, "Could not preserve the exact original settings and requested change")
            }
            func begin(_ step: String) -> Bool {
                self.recordPortableIntent(original, operation: id, kind: "modified")
                    && self.beginWorkbenchMutation(operation: id, target: recoveryTarget, step: step)
            }
            switch change {
            case .autoLoad(let enabled):
                changed = profile.autoLoad != enabled || !profile.autoLoadWasConfigured
                profile.autoLoad = enabled; profile.autoLoadWasConfigured = true
            case .filesystem:
                break // identical, already validated; no storage command
            case .mountPoint(let path):
                guard wasDetached else { return workbenchFailure(id, steps, "Unload the volume before changing its mount location") }
                let target = URL(fileURLWithPath: path, isDirectory: true)
                guard target.standardizedFileURL.path == path, target.resolvingSymlinksInPath().path == path,
                      path.hasPrefix(profile.backingMountPoint + "/"), !path.hasPrefix(profile.imagePath + "/"), path != profile.imagePath,
                      let profiles = readSectoriumProfiles(), !profiles.contains(where: { $0.id != profileID && $0.devMountPoint == path }) else {
                    return workbenchFailure(id, steps, "Choose an unused mount location on the verified parent, outside the image")
                }
                if FileManager.default.fileExists(atPath: path) {
                    guard isPlainDirectory(target), let info = diskInfoDictionary(path),
                          info["MountPoint"] as? String == profile.backingMountPoint,
                          backend.directoryEntryCount(target.path) == 0 else {
                        return workbenchFailure(id, steps, "The mount location is not a verified empty directory on the parent")
                    }
                }
                changed = profile.devMountPoint != path; profile.devMountPoint = path
            case .displayName(let name):
                guard Self.validVolumeName(name) else { return workbenchFailure(id, steps, "Use a nonempty name without slashes, colons, or control characters") }
                if name != profile.devVolumeName {
                    guard wasLoaded || profile.encrypted == false else { return workbenchFailure(id, steps, "Load and unlock the volume before renaming it") }
                    if wasLoaded, let failure = activityFailure(backend.assessOccupancy(scope: .dev), id: id, steps: steps) { return failure }
                    guard begin("renameVolume") else { return workbenchFailure(id, steps, "Could not preserve the rename intent") }
                    if wasDetached {
                        do { try SecureDirectory.ensure(URL(fileURLWithPath: profile.devMountPoint, isDirectory: true)) }
                        catch { return workbenchFailure(id, steps, "Could not prepare the registered mount location") }
                        let attached = backend.attachImage(password: nil)
                        steps.append(.init(step: "attachForRename", status: attached.succeeded ? .succeeded : .failed, detail: attached.detail))
                        guard attached.succeeded, let observation = backend.observe(), case .success = policy.validate(observation) else {
                            return workbenchFailure(id, steps, "Rename could not verify the temporarily loaded volume; inspect the current state")
                        }
                        temporaryLoad = true
                    }
                    let rename = commandRunner.run("/usr/sbin/diskutil", ["renameVolume", profile.devMountPoint, name], cwd: paths.workingDirectory)
                    steps.append(.init(step: "renameVolume", status: rename.succeeded ? .succeeded : .failed, detail: rename.detail))
                    guard rename.succeeded else { return workbenchFailure(id, steps, "macOS refused the rename; the previous registration is retained") }
                    var renamed = profile; renamed.devVolumeName = name; renamed.name = name
                    guard let renamedPolicy = profilePolicy(renamed),
                          let observation = MacStorageBackend(paths: paths, runner: commandRunner, policy: renamedPolicy).observe(),
                          case .success = renamedPolicy.validate(observation) else {
                        return workbenchFailure(id, steps, "The rename command completed but its identity/name postcheck failed; recovery is required")
                    }
                    profile = renamed
                }
                changed = original.name != name || original.devVolumeName != name; profile.name = name
            case .capacityGiB(let gib):
                guard (1...16_384).contains(gib), wasDetached, profile.encrypted == false,
                      profile.validation == .validated, let old = profile.logicalCapacityBytes else {
                    return workbenchFailure(id, steps, "Capacity changes require a verified, unloaded, unencrypted image and a valid size")
                }
                let requested = UInt64(gib) * 1_073_741_824
                guard requested > old else { return workbenchFailure(id, steps, "Only capacity growth is supported; shrinking is not performed") }
                guard begin("growImage") else { return workbenchFailure(id, steps, "Could not preserve the resize intent") }
                // hdiutil is present on the macOS 14 deployment target. A native
                // APFS/image limitation is returned honestly, never hidden by JSON.
                let resized = commandRunner.run("/usr/bin/hdiutil", ["resize", "-size", "\(gib)g", profile.imagePath], cwd: paths.workingDirectory)
                steps.append(.init(step: "growImage", status: resized.succeeded ? .succeeded : .failed, detail: resized.detail))
                guard resized.succeeded else { return workbenchFailure(id, steps, "macOS did not complete this image resize; inspect the retained operation before retrying") }
                guard completeWorkbenchStep(operation: id, step: "growImage") else { return workbenchFailure(id, steps, "Resize completed but its recovery record is pending") }
                do { try SecureDirectory.ensure(URL(fileURLWithPath: profile.devMountPoint, isDirectory: true)) }
                catch { return workbenchFailure(id, steps, "Resize needs a verified load to confirm the actual capacity") }
                let attach = backend.attachImage(password: nil)
                steps.append(.init(step: "verifyResizedImage", status: attach.succeeded ? .succeeded : .failed, detail: attach.detail))
                guard attach.succeeded, let observation = backend.observe(), case .success = policy.validate(observation),
                      let info = diskInfoDictionary(profile.devMountPoint),
                      let actual = Self.byteValue(info, keys: ["VolumeSize", "TotalSize"], allowZero: false),
                      actual > old, actual <= requested, requested - actual <= 268_435_456 else {
                    return workbenchFailure(id, steps, "Resize did not prove the requested writable capacity; the actual volume remains available for inspection")
                }
                temporaryLoad = true; profile.logicalCapacityBytes = actual; changed = true
            }
            if changed {
                guard begin("saveModifiedProfile") else { return workbenchFailure(id, steps, "Could not preserve the settings-update boundary") }
                profile.modifiedAt = Date(); profile.imageFileIdentity = Self.imageFileIdentity(profile.imagePath)
                do { try saveProfile(profile) } catch { return workbenchFailure(id, steps, "The verified change could not be saved to the registry") }
                guard completeWorkbenchStep(operation: id, step: "saveModifiedProfile") else { return workbenchFailure(id, steps, "The change was saved but its recovery record is pending") }
            }
            if temporaryLoad {
                guard let modifiedPolicy = profilePolicy(profile) else { return workbenchFailure(id, steps, "The modified volume identity is unavailable") }
                let modifiedBackend = MacStorageBackend(paths: paths, runner: commandRunner, policy: modifiedPolicy)
                if let failure = activityFailure(modifiedBackend.assessOccupancy(scope: .dev), id: id, steps: steps) { return failure }
                for step in [EjectStep.flush, .unmountDEV, .detachImage] {
                    guard beginWorkbenchMutation(operation: id, target: recoveryTarget, step: "restoreUnloaded") else { return workbenchFailure(id, steps, "Could not preserve the unload boundary") }
                    let result = modifiedBackend.perform(step)
                    steps.append(.init(step: "restoreUnloaded.\(step)", status: result.succeeded ? .succeeded : .failed, detail: result.detail))
                    guard result.succeeded else { return workbenchFailure(id, steps, "Settings changed, but the temporary load could not be fully unloaded") }
                }
                guard modifiedBackend.imageIsDetached() else { return workbenchFailure(id, steps, "Settings changed; detached state is not yet verified") }
            }
            if changed {
                updatePortableDocument(profile, event: documentEvent, operation: id)
                guard (try? portableDocumentJournal.events(parentID: profile.deviceID))?.contains(where: {
                    $0.id == id + ":" + profile.id + ":completed"
                }) == true else { return workbenchFailure(id, steps, "Settings changed but durable history remains pending") }
            }
            guard clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Settings changed but the operation record is pending") }
            steps.append(.init(step: "settings", status: .succeeded, detail: changed ? "Requested change verified and saved" : "Already configured"))
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    public func prepareStopDevelopmentDiskConfirmation() -> SectoriumStopConfirmation? {
        guard let profile = selectedProfile() else { return nil }
        return prepareStopDevelopmentDiskConfirmation(profileID: profile.id)
    }

    public func prepareStopDevelopmentDiskConfirmation(profileID: String) -> SectoriumStopConfirmation? {
        observationRunner.withFreshObservation { observeStopDevelopmentDiskConfirmation(profileID: profileID) }
    }

    private func observeStopDevelopmentDiskConfirmation(profileID: String) -> SectoriumStopConfirmation? {
        serial.lock(); defer { serial.unlock() }
        guard let profile = registeredProfile(profileID), let policy = profilePolicy(profile) else { return nil }
        let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
        guard let observation = backend.observe(), case .success = policy.validate(observation),
              let devUUID = observation.dev.uuid else { return nil }
        return SectoriumStopConfirmation(profileID: profile.id, deviceID: profile.deviceID,
            backingVolumeUUID: profile.backingVolumeUUID, devVolumeUUID: devUUID,
            imagePath: profile.imagePath, observedAt: Date())
    }

    /// Unload only the APFS development volume. The image remains attached and
    /// the physical parent stays connected; Load mounts this exact volume again.
    public func unloadDevelopmentDisk(profileID: String, checkpoint: SectoriumStopConfirmation) -> OperationResult {
        workbenchOperation("unload") { id, steps in
            guard profileID == checkpoint.profileID, let profile = registeredProfile(profileID),
                  let policy = profilePolicy(profile), imageIdentityMatches(profile),
                  recordWorkbenchTarget(operation: id, target: "\(profile.deviceID):\(profile.imagePath)") else {
                return workbenchFailure(id, steps, "The selected development volume identity changed")
            }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            guard let observed = backend.observe(), case .success = policy.validate(observed),
                  checkpoint.permits(profile, observed, knownWritersClosed: true) else {
                return workbenchFailure(id, steps, "Unload requires a fresh matching development volume")
            }
            if let failure = activityFailure(backend.assessOccupancy(scope: .dev), id: id, steps: steps) { return failure }
            guard suppressProfile(profile.id),
                  beginWorkbenchMutation(operation: id, target: profile.imagePath, step: "unmountDEV") else {
                return workbenchFailure(id, steps, "Could not retain the unload intent")
            }
            let result = backend.perform(.unmountDEV)
            steps.append(.init(step: "unmountDEV", status: result.succeeded ? .succeeded : .failed, detail: result.detail))
            if !result.succeeded {
                // A normal busy refusal leaves the same loaded volume safe to
                // retry after closing its owning app; no permanent recovery gate.
                if let stillLoaded = backend.observe(), case .success = policy.validate(stillLoaded) {
                    _ = clearWorkbenchMarker()
                }
                return workbenchFailure(id, steps, "Unload was refused: \(String(result.detail.prefix(180)))")
            }
            guard completeWorkbenchStep(operation: id, step: "unmountDEV") else {
                return workbenchFailure(id, steps, "Unload command completed; its completion record is pending")
            }
            let unloaded = observationRunner.withFreshObservation {
                guard case .success = policy.validateOuter(backend.observeOuter()) else { return false }
                return backend.verifiedUnmountedImageVolumeInfo() != nil || backend.imageIsDetached()
            }
            guard unloaded else {
                return workbenchFailure(id, steps, "Unload command completed; its volume state is not yet verified")
            }
            // Portable documentation is optional and cannot extend a storage
            // operation or recreate its busy state after the OS completed it.
            recordDeferredPortableCompletion(profile, event: "unloaded", operation: id)
            guard clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Unloaded; the internal completion record is still pending") }
            steps.append(.init(step: "verifyDevelopmentVolumeUnloaded", status: .succeeded,
                               detail: profile.id))
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    /// Repairs an interrupted postcheck from older builds without repeating any
    /// storage command. A successful, fresh exact chain must prove the requested
    /// unloaded state. A recorded successful unmount may also be superseded by a
    /// fresh, exact externally reloaded chain. Unknown/partial targets stay pending.
    @discardableResult
    public func reconcileCompletedUnload() -> Bool {
        guard serial.try() else { return false }
        defer { serial.unlock() }
        guard let pending = try? store.load(), !pending.ejectIntent,
              let marker = pending.workbenchOperation, marker.hasPrefix("unload:"),
              pending.workbenchCompletedStep == "unmountDEV" || pending.workbenchPhase == "mutating:unmountDEV",
              let target = pending.workbenchTarget,
              let profiles = readSectoriumProfiles(),
              profiles.filter({ $0.imagePath == target }).count == 1,
              let saved = profiles.first(where: { $0.imagePath == target }),
              lock.acquire() else { return false }
        defer { lock.release() }
        var reloaded: (StorageIdentityPolicy, StorageObservation)?
        let verified = observationRunner.withFreshObservation {
            guard let fresh = try? store.load(), fresh.revision == pending.revision,
                  let profile = resolvedProfile(saved), profile.imagePath == target,
                  imageIdentityMatches(profile), let policy = profilePolicy(profile) else { return false }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            guard case .success = policy.validateOuter(backend.observeOuter()) else { return false }
            if backend.verifiedUnmountedImageVolumeInfo() != nil || backend.imageIsDetached() { return true }
            if pending.workbenchCompletedStep == "unmountDEV",
               let observed = backend.observe(), case .success = policy.validate(observed) {
                reloaded = (policy, observed)
                return true
            }
            return false
        }
        guard verified else { return false }
        if let (policy, observed) = reloaded {
            guard clearSuppressionAfterValidatedLoad(saved.id, policy: policy, observation: observed),
                  clearWorkbenchMarker(terminal: "unload-superseded-by-verified-load") else { return false }
            lastAction = "Development volume is loaded"
            return true
        }
        let operation = String(marker.dropFirst("unload:".count))
        recordDeferredPortableCompletion(saved, event: "unloaded", operation: operation)
        guard clearWorkbenchMarker() else { return false }
        lastAction = "Unload successful"
        return true
    }

    /// Reconcile a prior Load from fresh native evidence, never by clearing an
    /// arbitrary busy flag. Loaded means exact validated completion; unloaded
    /// means the attempt did not complete and a deliberate retry is available.
    @discardableResult
    public func reconcileInterruptedLoad() -> Bool {
        guard serial.try() else { return false }
        defer { serial.unlock() }
        guard let pending = try? store.load(), !pending.ejectIntent,
              let marker = pending.workbenchOperation, marker.hasPrefix("start:"),
              pending.workbenchTerminalResult == nil,
              ["mutating:prepareMountPoint", "mutating:attachImage", "mutating:saveValidatedProfile", "mutating"].contains(pending.workbenchPhase ?? ""),
              pending.workbenchCompletedStep == nil || ["prepareMountPoint", "attachImage", "saveValidatedProfile"].contains(pending.workbenchCompletedStep!),
              let target = pending.workbenchTarget,
              let profiles = readSectoriumProfiles(),
              profiles.filter({ $0.imagePath == target }).count == 1,
              let saved = profiles.first(where: { $0.imagePath == target }),
              saved.hasVerifiedImageFormat, lock.acquire() else { return false }
        defer { lock.release() }
        var loaded: (SectoriumDevelopmentProfile, StorageIdentityPolicy, StorageObservation)?
        let verified = observationRunner.withFreshObservation {
            guard let fresh = try? store.load(), fresh.revision == pending.revision,
                  let profile = resolvedProfile(saved), profile.imagePath == target,
                  imageIdentityMatches(profile), let policy = profilePolicy(profile) else { return false }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            guard case .success = policy.validateOuter(backend.observeOuter()) else { return false }
            if let observed = backend.observe(), case .success = policy.validate(observed) {
                loaded = (profile, policy, observed)
                return true
            }
            return backend.verifiedUnloadedMountTarget()
                && (backend.verifiedUnmountedImageVolumeInfo() != nil || backend.imageIsDetached())
        }
        guard verified else { return false }
        if var (profile, policy, observed) = loaded {
            profile.validation = .validated
            profile.lastVerifiedLoadedAt = Date()
            do { try saveProfile(profile) } catch { return false }
            guard clearSuppressionAfterValidatedLoad(profile.id, policy: policy, observation: observed) else { return false }
            recordDeferredPortableCompletion(profile, event: "loaded", operation: String(marker.dropFirst("start:".count)))
            guard clearWorkbenchMarker(terminal: "load-completed-verified") else { return false }
            lastAction = "Load successful"
        } else {
            // Keep intentional Unload suppression: only a verified successful
            // manual Load may re-enable automatic mounting.
            guard clearWorkbenchMarker(terminal: "load-not-completed-retry-available") else { return false }
            lastAction = "Load did not complete. The volume is unloaded; Load can be retried."
        }
        return true
    }

    /// The compatibility entrypoint cannot synthesize the deliberate known-writer checkpoint.
    public func stopDevelopmentDisk() -> OperationResult {
        workbenchFailure(UUID().uuidString, [], "Stop requires a fresh identity and known-writer confirmation")
    }

    public func stopDevelopmentDisk(checkpoint: SectoriumStopConfirmation,
                                    knownWritersClosed: Bool) -> OperationResult {
        stopDevelopmentDisk(profileID: checkpoint.profileID, checkpoint: checkpoint,
                            knownWritersClosed: knownWritersClosed)
    }

    public func stopDevelopmentDisk(profileID: String, checkpoint: SectoriumStopConfirmation,
                                    knownWritersClosed: Bool) -> OperationResult {
        workbenchOperation("stop") { id, steps in
            guard profileID == checkpoint.profileID,
                  let profile = registeredProfile(profileID), let policy = profilePolicy(profile) else {
                return workbenchFailure(id, steps, "No valid matching development profile selected")
            }
            guard recordWorkbenchTarget(operation: id, target: "\(profile.deviceID):\(profile.imagePath)") else {
                return workbenchFailure(id, steps, "Could not persist the selected stop target")
            }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            guard let observation = backend.observe(), case .success = policy.validate(observation) else {
                return workbenchFailure(id, steps, "Fresh mounted identity validation failed")
            }
            if let failure = activityFailure(backend.assessOccupancy(scope: .dev), id: id, steps: steps) { return failure }
            guard checkpoint.permits(profile, observation, knownWritersClosed: knownWritersClosed) else {
                return workbenchFailure(id, steps, "Stop confirmation is missing, stale, or no longer matches the mounted image")
            }
            guard suppressProfile(profile.id) else {
                return workbenchFailure(id, steps, "Could not durably suppress automatic load before manual stop")
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
            guard completePortableOperation(profile, event: "unloaded", operation: id),
                  clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Stopped, but its durable completion remains pending") }
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
        guard let selectedSectoriumDeviceID else { return nil }
        return prepareWholeDeviceEjectConfirmation(physicalIdentity: selectedSectoriumDeviceID)
    }

    public func prepareWholeDeviceEjectConfirmation(physicalIdentity: String) -> SectoriumWholeDeviceEjectConfirmation? {
        observationRunner.withFreshObservation { observeWholeDeviceEjectConfirmation(physicalIdentity: physicalIdentity) }
    }

    private func observeWholeDeviceEjectTopology(physicalIdentity: String) -> WholeDeviceTopology? {
        guard let bound = verifiedDevice(physicalIdentity, requiringSelectionAnchor: false),
              bound.isExternal, bound.isVirtual != true else { return nil }
        let driver = makeWholeDeviceEjectDriver()
        guard let observed = driver.observe(physicalIdentity: physicalIdentity),
              observed.physicalIdentity == bound.id, observed.bsdName == bound.bsdName else { return nil }
        return observed
    }

    private func observeWholeDeviceEjectConfirmation(physicalIdentity: String) -> SectoriumWholeDeviceEjectConfirmation? {
        guard let observed = observeWholeDeviceEjectTopology(physicalIdentity: physicalIdentity) else { return nil }
        let dependenciesSafe = SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths,
            targetBSDName: observed.bsdName, runner: commandRunner)
        return SectoriumWholeDeviceEjectConfirmation(topology: observed,
            dependenciesCanFinishOffTarget: dependenciesSafe)
    }

    /// Read-only availability used to keep an unsafe/system target from presenting an enabled
    /// whole-device action. The actual click obtains a new confirmation and repeats validation.
    public func canPrepareWholeDeviceEjectConfirmation() -> Bool {
        guard let selectedSectoriumDeviceID else { return false }
        return canPrepareWholeDeviceEjectConfirmation(physicalIdentity: selectedSectoriumDeviceID)
    }

    public func canPrepareWholeDeviceEjectConfirmation(physicalIdentity: String) -> Bool {
        observationRunner.withObservation {
            observationRunner.observationValue("ejectAvailability:" + physicalIdentity) {
                // This boolean never used the confirmation's dependency result.
                // Check its exact target/topology here; inspect runtime paths on
                // the actual click and again before mutation, not every poll.
                observeWholeDeviceEjectTopology(physicalIdentity: physicalIdentity) != nil
            }
        }
    }

    /// Presents a fresh, explicit confirmation for the narrowly recoverable physical-unmount
    /// boundary. The original journal target is retained so the user reconfirms the exact scope.
    public func prepareContinueWholeDeviceEjectConfirmation() -> SectoriumWholeDeviceEjectConfirmation? {
        guard let selectedSectoriumDeviceID else { return nil }
        return prepareContinueWholeDeviceEjectConfirmation(physicalIdentity: selectedSectoriumDeviceID)
    }

    public func prepareContinueWholeDeviceEjectConfirmation(physicalIdentity: String) -> SectoriumWholeDeviceEjectConfirmation? {
        observationRunner.withFreshObservation { observeContinueWholeDeviceEjectConfirmation(physicalIdentity: physicalIdentity) }
    }

    /// Native notifications and ordinary refreshes reconcile durable removal/reconnection
    /// facts. No storage action or portable-document write occurs here. Do not wait behind
    /// an operation: its completion or the next native notification will observe again.
    @discardableResult
    public func reconcileWholeDeviceEjectRecovery() -> Bool {
        guard serial.try() else { return false }
        defer { serial.unlock() }
        guard let state = try? store.load() else { return false }
        var identities = Set(state.terminalEjectJournals.keys)
        if state.ejectIntent, let journal = decodeEjectJournal(state.workbenchTarget),
           state.operationID == journal.operationID,
           state.workbenchOperation == "eject:\(journal.operationID)" {
            identities.insert(journal.target.physicalIdentity)
        }
        // Previous builds cleared the active eject marker after Return but left
        // profile suppression/disconnected flags behind. Revisit only that exact
        // completed-return journal; Core still requires a fresh matching device.
        if !state.ejectIntent, state.workbenchOperation == nil,
           state.workbenchPhase == "eject:return-validated", state.workbenchTerminalResult == "returned-to-development",
           let retained = decodeEjectJournal(state.workbenchTarget) {
            identities.insert(retained.target.physicalIdentity)
        }
        guard !identities.isEmpty else { return false }
        let profiles = readSectoriumProfiles() ?? []
        return observationRunner.withFreshObservation {
            var changed = false
            for identity in identities.sorted() {
                let affected = Set(profiles.filter { $0.deviceID == identity }.map(\.id))
                if coreController.reconcileWholeDeviceEjectRecovery(physicalIdentity: identity,
                    driver: makeWholeDeviceEjectDriver(), affectedProfileIDs: affected) { changed = true }
            }
            return changed
        }
    }

    /// Safe logical eject does not require unplugging the USB cable. Only a terminal
    /// eject journal and a current exact postcondition qualify; mounted reconnects
    /// and unavailable observations revoke the presentation without issuing commands.
    public func verifiedSafelyEjectedDeviceIDs() -> Set<String> {
        observationRunner.observationValue("safely-ejected-identities") {
            guard let state = try? store.load(), state.workbenchOperation == nil else { return [] }
            let driver = makeWholeDeviceEjectDriver()
            return Set(state.terminalEjectJournals.compactMap { identity, encoded in
                guard let journal = decodeEjectJournal(encoded), journal.safelyEjected,
                      journal.target.physicalIdentity == identity else { return nil }
                switch driver.presence(of: journal.target) {
                case .absent: return identity
                case .present:
                    return driver.successfulEjectHasUnmountedPostcondition(of: journal.target) ? identity : nil
                case .unknown: return nil
                }
            })
        }
    }

    private func observeContinueWholeDeviceEjectConfirmation(physicalIdentity: String) -> SectoriumWholeDeviceEjectConfirmation? {
        guard let state = try? store.load(), state.ejectIntent,
              let journal = decodeEjectJournal(state.workbenchTarget),
              state.operationID == journal.operationID,
              state.workbenchOperation == "eject:\(journal.operationID)",
              journal.target.physicalIdentity == physicalIdentity else { return nil }
        let driver = makeWholeDeviceEjectDriver()
        guard continuationRecoveryIsFresh(journal, driver: driver) else { return nil }
        let dependencySafe = !journal.successfulEjectCallbackRequiresRecheck && SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths,
            targetBSDName: journal.target.bsdName, runner: commandRunner)
        return SectoriumWholeDeviceEjectConfirmation(topology: journal.target,
            dependenciesCanFinishOffTarget: dependencySafe, isContinuation: true,
            isObservationOnly: journal.successfulEjectCallbackRequiresRecheck)
    }

    /// Availability is advisory and read-only; Return repeats the checks while holding the
    /// shared operation lock before clearing the durable intent.
    public func canReturnFromWholeDeviceEject() -> Bool {
        guard let selectedSectoriumDeviceID else { return false }
        return canReturnFromWholeDeviceEject(physicalIdentity: selectedSectoriumDeviceID)
    }

    public func canReturnFromWholeDeviceEject(physicalIdentity: String) -> Bool {
        observationRunner.withObservation {
            coreController.canReturnFromWholeDeviceEject(
                physicalIdentity: physicalIdentity, driver: makeWholeDeviceEjectDriver())
        }
    }

    public func ejectSelectedExternalDevice(checkpoint: WholeDeviceEjectCheckpoint) -> OperationResult {
        guard let selectedSectoriumDeviceID else {
            return workbenchFailure(UUID().uuidString, [], "Select an external device before confirming whole-device eject")
        }
        return ejectSelectedExternalDevice(physicalIdentity: selectedSectoriumDeviceID, checkpoint: checkpoint)
    }

    public func ejectSelectedExternalDevice(physicalIdentity: String,
                                            checkpoint: WholeDeviceEjectCheckpoint) -> OperationResult {
        withProgress("sectorium.eject") {
        serial.lock(); defer { serial.unlock() }
        let driver = makeWholeDeviceEjectDriver()
        guard let bound = verifiedDevice(physicalIdentity, requiringSelectionAnchor: false),
              bound.isExternal, bound.isVirtual != true,
              let observed = driver.observe(physicalIdentity: physicalIdentity),
              observed.physicalIdentity == bound.id, observed.bsdName == bound.bsdName else {
            return workbenchFailure(UUID().uuidString, [], "Selected external device identity or complete related-member inventory is unavailable")
        }
        guard checkpoint.confirmedPhysicalIdentity == physicalIdentity,
              checkpoint.confirmedMemberKey == observed.memberKey else {
            return workbenchFailure(UUID().uuidString, [], "Whole-device checkpoint does not match the requested physical target")
        }
        let dependencySafe = SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths,
            targetBSDName: observed.bsdName, runner: commandRunner)
        guard checkpoint.dependenciesCanFinishOffTarget && dependencySafe else {
            return workbenchFailure(UUID().uuidString, [], "AUV runtime dependencies cannot safely finish after this drive is ejected")
        }
        if let failure = activityFailure(wholeDeviceActivity(physicalIdentity: physicalIdentity), id: UUID().uuidString, steps: []) { return failure }
        guard let profiles = readSectoriumProfiles() else {
            return workbenchFailure(UUID().uuidString, [], "Registered profile configuration is unavailable or invalid")
        }
        let affected = profiles.filter { $0.deviceID == physicalIdentity }
        guard affected.allSatisfy({ profile in
            bound.volumeUUIDs.contains(profile.backingVolumeUUID)
                && verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: bound)?.uuid == profile.backingVolumeUUID
        }) else {
            return workbenchFailure(UUID().uuidString, [], "A registered profile's backing volume is not freshly verified on the selected drive")
        }
        let acceptedCheckpoint = WholeDeviceEjectCheckpoint(
            confirmedExactTargetAndScope: checkpoint.confirmedExactTargetAndScope,
            knownWritersClosed: checkpoint.knownWritersClosed,
            dependenciesCanFinishOffTarget: checkpoint.dependenciesCanFinishOffTarget && dependencySafe,
            confirmedPhysicalIdentity: checkpoint.confirmedPhysicalIdentity,
            confirmedMemberKey: checkpoint.confirmedMemberKey, confirmedAt: checkpoint.confirmedAt)
        let result = coreController.ejectWholeExternalDevice(physicalIdentity: physicalIdentity,
            checkpoint: acceptedCheckpoint, driver: documentedEjectDriver(driver, physicalIdentity: physicalIdentity),
            affectedProfileIDs: Set(affected.map(\.id)))
        reconcileCompletedPortableEjects()
        var steps = result.completedSteps.map {
            OperationStepResult(step: $0, status: .succeeded, detail: "Verified by the isolated whole-device protocol")
        }
        if result.canUnplug {
            steps.append(.init(step: "verifyWholeDeviceEjected", status: .succeeded,
                               detail: "Native eject completed; the exact drive is absent or all its volumes and images are unloaded"))
        }
        if let failure = result.failure {
            return workbenchFailure(result.operationID, steps, "Whole-device eject stopped safely: \(failure)")
        }
        return .init(operationID: result.operationID, mode: .manual, steps: steps)
        }
    }

    public func continueWholeDeviceEject(checkpoint: WholeDeviceEjectCheckpoint) -> OperationResult {
        guard let selectedSectoriumDeviceID else {
            return workbenchFailure(UUID().uuidString, [], "Select the exact physical device before continuing whole-device eject")
        }
        return continueWholeDeviceEject(physicalIdentity: selectedSectoriumDeviceID, checkpoint: checkpoint)
    }

    public func continueWholeDeviceEject(physicalIdentity: String,
                                         checkpoint: WholeDeviceEjectCheckpoint) -> OperationResult {
        withProgress("sectorium.continueEject") {
        serial.lock(); defer { serial.unlock() }
        let driver = makeWholeDeviceEjectDriver()
        guard let state = try? store.load(), state.ejectIntent,
              let journal = decodeEjectJournal(state.workbenchTarget),
              state.operationID == journal.operationID,
              state.workbenchOperation == "eject:\(journal.operationID)",
              journal.target.physicalIdentity == physicalIdentity,
              checkpoint.confirmedPhysicalIdentity == physicalIdentity,
              checkpoint.confirmedMemberKey == journal.target.memberKey,
              continuationRecoveryIsFresh(journal, driver: driver) else {
            return workbenchFailure(UUID().uuidString, [], "Physical-eject continuation no longer matches its durable recovery journal")
        }
        let dependencySafe = !journal.successfulEjectCallbackRequiresRecheck && SectoriumOffTargetDependencyCheck.canFinishOffTarget(paths: paths,
            targetBSDName: journal.target.bsdName, runner: commandRunner)
        let acceptedCheckpoint = WholeDeviceEjectCheckpoint(
            confirmedExactTargetAndScope: checkpoint.confirmedExactTargetAndScope,
            knownWritersClosed: checkpoint.knownWritersClosed,
            dependenciesCanFinishOffTarget: checkpoint.dependenciesCanFinishOffTarget && dependencySafe,
            confirmedPhysicalIdentity: checkpoint.confirmedPhysicalIdentity,
            confirmedMemberKey: checkpoint.confirmedMemberKey, confirmedAt: checkpoint.confirmedAt)
        let result = coreController.continueWholeExternalDeviceEject(checkpoint: acceptedCheckpoint,
            driver: documentedEjectDriver(driver, physicalIdentity: physicalIdentity))
        reconcileCompletedPortableEjects()
        var steps = result.completedSteps.map {
            OperationStepResult(step: $0, status: .succeeded, detail: "Verified by the isolated whole-device recovery protocol")
        }
        if result.canUnplug {
            steps.append(.init(step: "verifyWholeDeviceEjected", status: .succeeded,
                               detail: "Native eject completed; the exact drive is absent or all its volumes and images are unloaded"))
        }
        if let failure = result.failure {
            return workbenchFailure(result.operationID, steps, "Whole-device eject continuation stopped safely: \(failure)")
        }
        return .init(operationID: result.operationID, mode: .manual, steps: steps)
        }
    }

    private func documentedEjectDriver(_ base: WholeDeviceEjectDriving,
                                       physicalIdentity: String) -> WholeDeviceEjectDriving {
        SectoriumDocumentedEjectDriver(base: base) { [weak self] in
            guard let self, let state = try? self.store.load(), state.ejectIntent,
                  let operation = state.operationID,
                  let eject = self.decodeEjectJournal(state.workbenchTarget),
                  eject.operationID == operation, eject.target.physicalIdentity == physicalIdentity,
                  let profiles = self.readSectoriumProfiles() else { return false }
            for saved in profiles where saved.deviceID == physicalIdentity {
                let eventID = operation + ":" + saved.id + ":intended"
                if (try? self.portableDocumentJournal.events(parentID: physicalIdentity))?.contains(where: { $0.id == eventID }) == true { continue }
                guard let profile = self.resolvedProfile(saved),
                      self.recordPortableIntent(profile, operation: operation, kind: "eject") else { return false }
                if let context = self.portableContext(profile) {
                    let result = self.portableDocumentJournal.synchronize(context: context, writer: self.portableDocumentWriter)
                    self.recordPortableResult(result, profileID: profile.id)
                }
            }
            return true
        }
    }

    /// The terminal Core journal proves safe eject after the native callback.
    /// Completion is written on the internal disk; IMPORTANT is deliberately pending
    /// until the original parent is freshly verified after reconnect. On process restart
    /// this repairs a crash between Core's terminal write and the history write.
    private func reconcileCompletedPortableEjects() {
        guard lock.acquire() else { return }; defer { lock.release() }
        guard let state = try? store.load() else { return }
        for (parentID, encoded) in state.terminalEjectJournals {
            guard let eject = decodeEjectJournal(encoded), eject.safelyEjected,
                  eject.target.physicalIdentity == parentID,
                  let context = try? portableDocumentJournal.latestContext(parentID: parentID),
                  let events = try? portableDocumentJournal.events(parentID: parentID) else { continue }
            for intent in events where intent.phase == .intended && intent.kind == "ejected"
                && intent.id.hasPrefix(eject.operationID + ":") {
                let eventID = eject.operationID + ":" + intent.profileID + ":completed"
                guard !events.contains(where: { $0.id == eventID }) else { continue }
                do {
                    try portableDocumentJournal.record(context: context, event: .init(id: eventID,
                        occurredAt: Date(), profileID: intent.profileID, kind: "ejected",
                        before: intent.before, after: intent.before,
                        detail: "Safe eject confirmed by the durable whole-device result; synchronize IMPORTANT on reconnect"))
                    recordPortableDocumentPending(profileID: intent.profileID, reason: "Drive safely ejected; IMPORTANT will update after reconnect")
                } catch { recordPortableDocumentPending(profileID: intent.profileID, reason: "Eject completed; operation history awaits recovery") }
            }
        }
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
                let device: SectoriumPhysicalDevice
                if let exact = self.verifiedDevice(journal.target.physicalIdentity,
                                                   requiringSelectionAnchor: false),
                   exact.isExternal, exact.identityVerified {
                    device = exact
                } else if journal.canCancelUnissuedEject,
                          let devices = try? self.observeSectoriumDevices(),
                          let cancellationCandidate = SectoriumWholeDeviceEjectDriver
                            .freshUnissuedCancellationCandidate(journal: journal, devices: devices,
                                runner: self.commandRunner, workingDirectory: self.paths.workingDirectory) {
                    // A confirmed no-action journal may be cancelled after its sole UUID
                    // anchor gains another member. The driver independently proves the
                    // original target, every fresh parent edge, and system disjointness.
                    device = cancellationCandidate
                } else {
                    return false
                }
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
            }, independentLoadedReturnValidator: { [weak self] journal in
                guard let self, let profiles = self.readSectoriumProfiles() else { return false }
                let matches = profiles.filter { $0.deviceID == journal.target.physicalIdentity }
                guard !matches.isEmpty else { return false }
                return matches.allSatisfy { profile in
                    guard let resolved = self.resolvedProfile(profile), self.imageIdentityMatches(resolved),
                          let policy = self.profilePolicy(resolved),
                          let current = MacStorageBackend(paths: self.paths, runner: self.commandRunner,
                              policy: policy).observe(),
                          case .success = policy.validate(current) else { return false }
                    return true
                }
            }, independentContinuationValidator: { [weak self] journal in
                guard let self, let profiles = self.readSectoriumProfiles() else { return false }
                let matches = profiles.filter { $0.deviceID == journal.target.physicalIdentity }
                if matches.isEmpty { return journal.target.images.isEmpty }
                guard Set(matches.map(\.id)).count == matches.count,
                      Set(matches.map(\.imagePath)).count == matches.count,
                      let device = self.verifiedDevice(journal.target.physicalIdentity,
                                                       requiringSelectionAnchor: false),
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
        if journal.successfulEjectCallbackRequiresRecheck {
            // The OS callback is durable, but safe removal still needs a fresh
            // authoritative absence probe. Core's continuation dispatches no action.
            return true
        }
        if journal.lastIssuedAction == .physicalVolumesUnmount,
           journal.phase == .interrupted || journal.phase == .physicalVolumesUnmountIssued
                || journal.phase == .physicalVolumesUnmounted {
            return driver.freshPhysicalContinuationMatches(journal)
        }
        return journal.lastIssuedAction == .ejectWholeDevice && journal.phase == .ejectIssued
            && driver.freshEjectIssuedRecovery(journal) != .refused
    }

    /// Explicit Resume reconciles the recorded request against fresh native facts.
    /// It never repeats rename/resize, and a verification-only load is restored to
    /// the original unloaded state before the durable marker can be cleared.
    private func reconcileModification(_ state: StoragePersistentState, responseID: String,
                                       steps: inout [OperationStepResult]) -> OperationResult {
        guard let target = state.workbenchTarget, let data = target.data(using: .utf8),
              let intent = try? JSONDecoder().decode(SectoriumModificationRecovery.self, from: data),
              intent.version == 1, state.workbenchOperation == "modify:" + intent.operationID,
              let before = resolvedProfile(intent.before), imageIdentityMatches(before),
              let current = registeredProfile(before.id), let policy = profilePolicy(before),
              let events = try? portableDocumentJournal.events(parentID: before.deviceID),
              events.contains(where: { $0.id == intent.operationID + ":" + before.id + ":intended" }) else {
            return workbenchFailure(responseID, steps, "The interrupted change lacks its exact original identity and durable request; no command was replayed")
        }
        var proposed = before
        let event: String
        switch intent.change {
        case .displayName(let name):
            guard Self.validVolumeName(name) else { return workbenchFailure(responseID, steps, "Recorded rename is invalid") }
            proposed.name = name; proposed.devVolumeName = name; event = "displayNameChanged"
        case .capacityGiB(let gib):
            guard (1...16_384).contains(gib), let old = before.logicalCapacityBytes,
                  UInt64(gib) * 1_073_741_824 > old else { return workbenchFailure(responseID, steps, "Recorded capacity change is invalid") }
            proposed.logicalCapacityBytes = UInt64(gib) * 1_073_741_824; event = "capacityChanged"
        case .autoLoad(let enabled):
            proposed.autoLoad = enabled; proposed.autoLoadWasConfigured = true; event = "autoLoadChanged"
        case .mountPoint(let path):
            guard !intent.wasLoaded, path.hasPrefix(intent.before.backingMountPoint + "/") else {
                return workbenchFailure(responseID, steps, "Recorded mount change has an invalid original scope")
            }
            proposed.devMountPoint = before.backingMountPoint + path.dropFirst(intent.before.backingMountPoint.count)
            guard proposed.devMountPoint != before.imagePath, !proposed.devMountPoint.hasPrefix(before.imagePath + "/"),
                  URL(fileURLWithPath: proposed.devMountPoint).standardizedFileURL.path == proposed.devMountPoint,
                  URL(fileURLWithPath: proposed.devMountPoint).resolvingSymlinksInPath().path == proposed.devMountPoint else {
                return workbenchFailure(responseID, steps, "Recorded mount location is no longer safe")
            }
            event = "mountPointChanged"
        case .filesystem:
            return workbenchFailure(responseID, steps, "Filesystem conversion has no supported recovery mutation")
        }
        func sameSavedSettings(_ candidate: SectoriumDevelopmentProfile, _ expected: SectoriumDevelopmentProfile) -> Bool {
            var a = candidate, b = expected
            a.modifiedAt = nil; b.modifiedAt = nil
            if case .capacityGiB = intent.change, let actual = a.logicalCapacityBytes,
               let requested = proposed.logicalCapacityBytes, actual <= requested,
               requested - actual <= 268_435_456, actual > (before.logicalCapacityBytes ?? UInt64.max),
               b.logicalCapacityBytes == requested { a.logicalCapacityBytes = requested }
            return a == b
        }
        let registryBefore = sameSavedSettings(current, before), registryAfter = sameSavedSettings(current, proposed)
        guard registryBefore || registryAfter else {
            return workbenchFailure(responseID, steps, "Registered settings changed outside this interrupted operation; recovery did not overwrite them")
        }
        let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
        guard case .success = policy.validateOuter(backend.observeOuter()) else {
            return workbenchFailure(responseID, steps, "The original physical backing volume is not freshly verified")
        }
        var recovered = current
        var changed = registryAfter && !registryBefore
        let needsNativeVerification: Bool
        switch intent.change { case .displayName, .capacityGiB: needsNativeVerification = true; default: needsNativeVerification = false }
        let restoringUnloaded = !intent.wasLoaded && state.workbenchPhase == "mutating:restoreUnloaded"
        let unmountedVerificationInfo = restoringUnloaded ? backend.verifiedUnmountedImageVolumeInfo() : nil
        if needsNativeVerification {
            if backend.imageIsDetached() {
                guard before.encrypted == false,
                      beginWorkbenchMutation(operation: intent.operationID, target: target, step: "verifyInterruptedModification") else {
                    return workbenchFailure(responseID, steps, "The unloaded image needs an explicit unlocked identity check before recovery")
                }
                do { try SecureDirectory.ensure(URL(fileURLWithPath: before.devMountPoint, isDirectory: true)) }
                catch { return workbenchFailure(responseID, steps, "The registered verification mount location could not be prepared") }
                let attach = backend.attachImage(password: nil)
                steps.append(.init(step: "verifyInterruptedModification", status: attach.succeeded ? .succeeded : .failed, detail: attach.detail))
                guard attach.succeeded else { return workbenchFailure(responseID, steps, "Verification load failed; the original modification was not replayed") }
            }
            let observation = backend.observe()
            guard let proposedPolicy = profilePolicy(proposed),
                  let info = unmountedVerificationInfo ?? diskInfoDictionary(before.devMountPoint),
                  Self.observedFilesystem(info) == before.filesystem,
                  let capacity = Self.byteValue(info, keys: ["VolumeSize", "TotalSize"], allowZero: false) else {
                return workbenchFailure(responseID, steps, "The interrupted change remains unverifiable; its recovery record was retained")
            }
            func nativeIdentityMatches(_ expected: SectoriumDevelopmentProfile, policy expectedPolicy: StorageIdentityPolicy) -> Bool {
                if unmountedVerificationInfo != nil {
                    return (info["VolumeUUID"] as? String).flatMap(UUID.init(uuidString:)) == expected.devUUID
                        && info["VolumeName"] as? String == expected.devVolumeName
                }
                guard let observation else { return false }
                if case .success = expectedPolicy.validate(observation) { return true }
                return false
            }
            let beforeValid = nativeIdentityMatches(before, policy: policy)
            let afterValid = nativeIdentityMatches(proposed, policy: proposedPolicy)
            switch intent.change {
            case .displayName:
                guard capacity == before.logicalCapacityBytes else { return workbenchFailure(responseID, steps, "Capacity changed unexpectedly during rename recovery") }
                if afterValid { recovered = proposed; changed = true }
                else if beforeValid && registryBefore { recovered = before; changed = false }
                else { return workbenchFailure(responseID, steps, "Neither the original nor requested volume name/identity was verified") }
            case .capacityGiB:
                guard beforeValid, let requested = proposed.logicalCapacityBytes, let old = before.logicalCapacityBytes else {
                    return workbenchFailure(responseID, steps, "The original image-to-volume chain changed during resize recovery")
                }
                if capacity > old && capacity <= requested && requested - capacity <= 268_435_456 {
                    recovered = proposed; recovered.logicalCapacityBytes = capacity; changed = true
                } else if capacity == old && registryBefore { recovered = before; changed = false }
                else { return workbenchFailure(responseID, steps, "Actual capacity is neither the original nor verified requested size; no resize was repeated") }
            default: break
            }
        } else {
            guard let currentPolicy = profilePolicy(current) else { return workbenchFailure(responseID, steps, "Current profile identity is unavailable") }
            let currentBackend = MacStorageBackend(paths: paths, runner: commandRunner, policy: currentPolicy)
            if !currentBackend.imageIsDetached() {
                guard let observation = currentBackend.observe(), case .success = currentPolicy.validate(observation) else {
                    return workbenchFailure(responseID, steps, "Current loaded state does not match the saved settings")
                }
            }
        }
        // A completed native change can be persisted, but never copied from the
        // requested value without the observations above. A proven non-change
        // cancels the attempt and retains the original settings.
        if changed {
            recovered.modifiedAt = current.modifiedAt ?? Date()
            guard beginWorkbenchMutation(operation: intent.operationID, target: target, step: "saveRecoveredSettings") else {
                return workbenchFailure(responseID, steps, "Could not preserve the recovered settings boundary")
            }
            do { try saveProfile(recovered) }
            catch { return workbenchFailure(responseID, steps, "Verified settings could not be persisted") }
        }
        if !intent.wasLoaded, let recoveredPolicy = profilePolicy(recovered) {
            let recoveredBackend = MacStorageBackend(paths: paths, runner: commandRunner, policy: recoveredPolicy)
            if !recoveredBackend.imageIsDetached() {
                let remainingSteps: [EjectStep]
                if unmountedVerificationInfo != nil {
                    guard recoveredBackend.verifiedUnmountedImageVolumeInfo() != nil else {
                        return workbenchFailure(responseID, steps, "The unmounted image changed before its remaining detach step")
                    }
                    remainingSteps = [.detachImage]
                } else {
                    guard let observation = recoveredBackend.observe(), case .success = recoveredPolicy.validate(observation) else {
                        return workbenchFailure(responseID, steps, "Verification image remains attached in an unverified state; recovery is still pending")
                    }
                    if let failure = activityFailure(recoveredBackend.assessOccupancy(scope: .dev), id: responseID, steps: steps) { return failure }
                    remainingSteps = [.flush, .unmountDEV, .detachImage]
                }
                for step in remainingSteps {
                    guard beginWorkbenchMutation(operation: intent.operationID, target: target, step: "restoreUnloaded") else {
                        return workbenchFailure(responseID, steps, "Could not retain the verification unload boundary")
                    }
                    let result = recoveredBackend.perform(step)
                    steps.append(.init(step: "restoreUnloaded.\(step)", status: result.succeeded ? .succeeded : .failed, detail: result.detail))
                    guard result.succeeded else { return workbenchFailure(responseID, steps, "Settings are verified, but the verification load is not yet fully unloaded") }
                }
                guard recoveredBackend.imageIsDetached() else { return workbenchFailure(responseID, steps, "Detached state is not verified; recovery remains pending") }
            }
        }
        _ = updatePortableDocument(recovered, event: changed ? event : "validated", operation: intent.operationID)
        guard (try? portableDocumentJournal.events(parentID: before.deviceID))?.contains(where: {
            $0.id == intent.operationID + ":" + before.id + ":completed"
        }) == true, clearWorkbenchMarker() else {
            return workbenchFailure(responseID, steps, "The settings result is verified, but durable completion is still pending")
        }
        steps.append(.init(step: changed ? "reconcileModifiedSettings" : "cancelUnchangedModification", status: .succeeded,
            detail: changed ? "Fresh native facts matched the recorded request; no modification was replayed" : "Fresh native facts and registry matched the preserved preimage; original settings retained"))
        return .init(operationID: responseID, mode: .manual, steps: steps)
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
            let action = state.workbenchOperation?.split(separator: ":", maxSplits: 1).first.map(String.init)
            if action == "modify" { return reconcileModification(state, responseID: id, steps: &steps) }
            if action == "start", state.workbenchPhase == "validating",
               state.workbenchTarget == nil, state.workbenchCompletedStep == nil,
               state.workbenchTerminalResult == nil {
                guard clearWorkbenchMarker() else {
                    return workbenchFailure(id, steps, "Could not clear the unbound start validation marker")
                }
                steps.append(.init(step: "cancelUnmutatedStart", status: .succeeded,
                                   detail: "No target or storage mutation had been recorded"))
                return .init(operationID: id, mode: .manual, steps: steps)
            }
            let recoveryProfile: SectoriumDevelopmentProfile?
            if let target = state.workbenchTarget, let registered = readSectoriumProfiles() {
                let matches = registered.filter { target == "\($0.deviceID):\($0.imagePath)"
                    || target == $0.imagePath }
                recoveryProfile = matches.count == 1 ? matches.first : nil
            } else {
                recoveryProfile = selectedProfile()
            }
            guard let profile = recoveryProfile, let policy = profilePolicy(profile) else {
                return workbenchFailure(id, steps, "Pending profile cannot be identified")
            }
            let backend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            let compositeStartTarget = "\(profile.deviceID):\(profile.imagePath)"
            if action == "start", state.workbenchTarget == compositeStartTarget {
                guard let device = verifiedDevice(profile.deviceID, requiringSelectionAnchor: false),
                      device.identityVerified,
                      device.volumeUUIDs.contains(profile.backingVolumeUUID),
                      verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid
                          == profile.backingVolumeUUID else {
                    return workbenchFailure(id, steps, "Pending start target failed fresh backing-device validation")
                }
                if state.workbenchPhase == "validating", state.workbenchCompletedStep == nil,
                   state.workbenchTerminalResult == nil {
                    guard clearWorkbenchMarker() else {
                        return workbenchFailure(id, steps, "Could not clear the unmutated start validation marker")
                    }
                    steps.append(.init(step: "cancelUnmutatedStart", status: .succeeded,
                                       detail: "The exact start target was checked; no mutation had begun"))
                    return .init(operationID: id, mode: .manual, steps: steps)
                }
                guard (state.workbenchPhase == "mutating:saveImageFormat" && state.workbenchCompletedStep == nil)
                          || (state.workbenchPhase == "mutating" && state.workbenchCompletedStep == "saveImageFormat"),
                      state.workbenchTerminalResult == nil,
                      isPlainDirectory(URL(fileURLWithPath: profile.imagePath)),
                      URL(fileURLWithPath: profile.imagePath).resolvingSymlinksInPath().path == profile.imagePath,
                      profile.encrypted != nil, profile.caseSensitive != nil,
                      profile.logicalCapacityBytes != nil else {
                    return workbenchFailure(id, steps, "Pending image-format registry boundary is not safely reconcilable")
                }
                let mounted = backend.observe()
                let format = observeSparsebundleFormat(profile.imagePath,
                    attachedChainVerified: mounted.map { (try? policy.validate($0).get()) != nil } ?? false)
                guard format.succeeded, let imageFormat = Self.documentedSparsebundleFormat(format.detail),
                      profile.imageFormat == nil || profile.imageFormat == imageFormat else {
                    return workbenchFailure(id, steps, "Pending image-format registry boundary conflicts with fresh image evidence")
                }
                if profile.imageFormat == nil {
                    var upgraded = profile
                    upgraded.imageFormat = imageFormat
                    do { try saveProfile(upgraded) }
                    catch { return workbenchFailure(id, steps, "Pending image-format registry update could not be completed") }
                }
                guard clearWorkbenchMarker() else {
                    return workbenchFailure(id, steps, "Image format was verified but its recovery marker remains")
                }
                steps.append(.init(step: "reconcileImageFormat", status: .succeeded,
                                   detail: "Fresh image format and exact registered target reconciled"))
                return .init(operationID: id, mode: .manual, steps: steps)
            }
            if action == "start", state.workbenchPhase == "validating" {
                return workbenchFailure(id, steps, "Pending start target does not match the registered composite identity")
            }
            guard recordWorkbenchTarget(operation: state.workbenchOperation ?? id,
                                        target: "\(profile.deviceID):\(profile.imagePath)") || state.workbenchPhase != "validating" else {
                return workbenchFailure(id, steps, "Could not persist the recovery target")
            }
            guard state.workbenchTarget == profile.imagePath,
                  let device = verifiedDevice(profile.deviceID, requiringSelectionAnchor: false),
                  device.identityVerified,
                  device.volumeUUIDs.contains(profile.backingVolumeUUID),
                  verifiedBackingVolume(URL(fileURLWithPath: profile.backingMountPoint), on: device)?.uuid == profile.backingVolumeUUID else {
                return workbenchFailure(id, steps, "Pending operation target failed fresh backing-device validation")
            }
            switch action {
            case "start", "adopt":
                guard imageIdentityMatches(profile),
                      let observation = backend.observe(), case .success = policy.validate(observation) else {
                    return workbenchFailure(id, steps, "Interrupted \(action!) operation is not fully revalidated; recovery marker retained")
                }
                if action == "start" {
                    var verified = profile
                    verified.devUUID = observation.dev.uuid
                    verified.validation = .validated
                    verified.lastVerifiedLoadedAt = profile.lastVerifiedLoadedAt ?? Date()
                    do { try saveProfile(verified) }
                    catch { return workbenchFailure(id, steps, "Recovered loaded identity could not be persisted") }
                    guard clearSuppressionAfterValidatedLoad(profile.id, policy: policy, observation: observation) else {
                        return workbenchFailure(id, steps, "Recovered load is verified but its manual load intent remains pending")
                    }
                }
                steps.append(.init(step: "validateMountedChain", status: .succeeded, detail: profile.id))
            case "create":
                guard state.workbenchCompletedStep == "createSparsebundle",
                      isPlainDirectory(URL(fileURLWithPath: profile.imagePath)),
                      imageIdentityMatches(profile) else {
                    return workbenchFailure(id, steps, "Interrupted create lacks a durable completion record and exact image artifact")
                }
                if profile.imageFormat == nil {
                    let format = commandRunner.run("/usr/bin/hdiutil", ["imageinfo", profile.imagePath, "-format"], cwd: paths.workingDirectory)
                    guard format.succeeded, let imageFormat = Self.documentedSparsebundleFormat(format.detail) else {
                        return workbenchFailure(id, steps, "Interrupted create image format is still unknown; recovery marker retained")
                    }
                    var verified = profile
                    verified.imageFormat = imageFormat
                    verified.imageFileIdentity = Self.imageFileIdentity(profile.imagePath)
                    do { try saveProfile(verified) }
                    catch { return workbenchFailure(id, steps, "Interrupted create format was observed but could not be durably saved") }
                    steps.append(.init(step: "verifyImageFormat", status: .succeeded, detail: imageFormat))
                }
                guard profile.imageFormat == nil || profile.imageFormat == "UDSB" else {
                    return workbenchFailure(id, steps, "Interrupted create recorded a conflicting image format")
                }
                steps.append(.init(step: "verifyCreatedImage", status: .succeeded))
            case "unload":
                guard (state.workbenchCompletedStep == "unmountDEV" || state.workbenchPhase == "mutating:unmountDEV"),
                      backend.verifiedUnmountedImageVolumeInfo() != nil || backend.imageIsDetached(),
                      case .success = policy.validateOuter(backend.observeOuter()) else {
                    return workbenchFailure(id, steps, "Interrupted unload needs a verified unmounted development volume and connected parent")
                }
                steps.append(.init(step: "verifyDevelopmentVolumeUnloaded", status: .succeeded, detail: profile.id))
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
            if action == "unload" {
                let originalOperation = state.workbenchOperation?.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id
                recordDeferredPortableCompletion(profile, event: "unloaded", operation: originalOperation)
                guard clearWorkbenchMarker() else { return workbenchFailure(id, steps, "Unloaded; the internal completion record is still pending") }
                return .init(operationID: id, mode: .manual, steps: steps)
            }
            guard let originalOperation = state.workbenchOperation?.split(separator: ":", maxSplits: 1).last.map(String.init),
                  !originalOperation.isEmpty,
                  let recoveredProfile = readSectoriumProfiles()?.first(where: { $0.id == profile.id }),
                  completePortableOperation(recoveredProfile,
                    event: action == "start" ? "loaded" : (action == "stop" || action == "unload") ? "unloaded" : "registered",
                    operation: originalOperation),
                  clearWorkbenchMarker() else {
                return workbenchFailure(id, steps, "Recovered storage is verified but its durable completion remains pending")
            }
            return .init(operationID: id, mode: .manual, steps: steps)
        }
    }

    public func returnToDevelopment(password: String? = nil) -> OperationResult {
        guard let pending = try? store.load() else {
            return startDevelopmentDisk(password: password)
        }
        let selectedPhysicalID = selectedSectoriumDeviceID
        let activeWholeEject = pending.ejectIntent && pending.workbenchOperation?.hasPrefix("eject:") == true
            && decodeEjectJournal(pending.workbenchTarget) != nil
        let selectedTerminalEject = selectedPhysicalID.flatMap { pending.terminalEjectJournals[$0] } != nil
        if activeWholeEject || selectedTerminalEject {
            guard let selectedPhysicalID else {
                return workbenchFailure(UUID().uuidString, [], "Select the exact ejected physical device before Return")
            }
            return returnToDevelopment(physicalIdentity: selectedPhysicalID)
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

    public func returnToDevelopment(physicalIdentity: String) -> OperationResult {
        withProgress("sectorium.returnToDevelopment") {
            serial.lock(); defer { serial.unlock() }
            let id = UUID().uuidString
            guard coreController.returnFromWholeDeviceEject(
                physicalIdentity: physicalIdentity, driver: makeWholeDeviceEjectDriver()) else {
                return workbenchFailure(id, [], "Explicit Return requires a fresh exact physical and image identity check")
            }
            return .init(operationID: id, mode: .manual,
                steps: [.init(step: "returnFromWholeDeviceEject", status: .succeeded,
                              detail: "Fresh physical identity and recovery boundary validated")])
        }
    }
    public func refreshStatus() -> HESectoriumRuntimeSnapshot {
        refreshStatus(observedReadiness: nil)
    }

    /// observedReadiness is presentation data from the same refresh only. It
    /// avoids a second storage traversal; action authorization never reads it.
    public func refreshStatus(observedReadiness: SectoriumWorkbenchReadiness?) -> HESectoriumRuntimeSnapshot {
        let progress = progressSnapshot()
        guard serial.try() else {
            installedStatusLock.lock()
            let installed = lastInstalledStatus
            installedStatusLock.unlock()
            return .init(installed: installed, automationEnabled: installer.automationEnabled(), readiness: .unknown,
                         pendingEject: try? store.load().ejectIntent, diagnostics: [], latestActionSummary: "Operation in progress",
                         agentLoadStatus: agentStatusProvider.loadStatus(label: "com.juliushe.dev-apfs-mounter"), operationProgress: progress)
        }
        defer { serial.unlock() }
        configurationValid = explicitIdentityPolicy || Self.readIdentityPolicy(at: paths.config) != nil
        let registered = readSectoriumProfiles()
        let readiness: HESectoriumReadinessStatus
        if registered == nil {
            readiness = .notReady("registered profile configuration unavailable or invalid")
        } else if let observedReadiness {
            switch observedReadiness {
            case .ready, .connected: readiness = .ready
            case .readOnly: readiness = .notReady("registered development volume is read-only")
            case .notStarted: readiness = .notReady("registered development image is not loaded")
            case .awaitingUnlock: readiness = .notReady("registered development image requires an unlock")
            case .partialFailure(let reason): readiness = .notReady(reason)
            case .busy, .unknown, .operationInProgress: readiness = .unknown
            case .noDevice, .ejected, .noDevelopmentDisk:
                readiness = .notReady("no verified development volume selected")
            }
        } else if let registered, !registered.isEmpty {
            let matching = selectedSectoriumProfileID.flatMap { selected in
                registered.first(where: { $0.id == selected })
            } ?? (registered.count == 1 ? registered[0] : nil)
            if let profile = matching, let devices = try? observeSectoriumDevices() {
                switch sectoriumReadiness(deviceID: profile.deviceID, selectedProfileID: profile.id,
                                         devices: devices, profiles: registered) {
                case .ready, .connected: readiness = .ready
                case .readOnly: readiness = .notReady("registered development volume is read-only")
                case .notStarted: readiness = .notReady("registered development image is not loaded")
                case .awaitingUnlock: readiness = .notReady("registered development image requires an unlock")
                case .partialFailure(let reason): readiness = .notReady(reason)
                case .busy, .unknown, .operationInProgress: readiness = .unknown
                case .noDevice, .ejected, .noDevelopmentDisk:
                    readiness = .notReady("registered development backing volume is unavailable")
                }
            } else { readiness = .unknown }
        } else if !configurationValid {
            readiness = .notReady("identity configuration missing or invalid")
        } else if let observation = backend.observe() {
            switch coreController.identityPolicy.validate(observation) {
            case .success: readiness = .ready
            case .failure(let reason): readiness = .notReady(reason.rawValue)
            }
        } else { readiness = .unknown }
        let pending = try? store.load().ejectIntent
        let installed = installer.status(profileConfigured: registered?.isEmpty == false)
        installedStatusLock.lock()
        lastInstalledStatus = installed
        installedStatusLock.unlock()
        return .init(installed: installed,
                     automationEnabled: installer.automationEnabled(), readiness: readiness, pendingEject: pending,
                     diagnostics: diagnostics, latestActionSummary: lastAction,
                     agentLoadStatus: agentStatusProvider.loadStatus(label: "com.juliushe.dev-apfs-mounter"), operationProgress: progress)
    }
    private func progressSnapshot() -> HESectoriumOperationProgress {
        progressLock.lock(); defer { progressLock.unlock() }; return currentProgress
    }
    private func withProgress(_ action: String, _ body: () -> OperationResult) -> OperationResult {
        performProgress(action, rejected: .init(operationID: UUID().uuidString, mode: .manual,
            steps: [], failure: .workbenchFailed("AUV is closing; no new storage operation was started")), body)
    }
    private func withProgress(_ action: String, _ body: () -> HESectoriumInstallResult) -> HESectoriumInstallResult {
        performProgress(action, rejected: .init(succeeded: false, summary: "AUV is closing; settings remain unchanged"), body)
    }
    private func performProgress<T>(_ action: String, rejected: T, _ body: () -> T) -> T {
        let depth = (Thread.current.threadDictionary[operationThreadKey] as? Int) ?? 0
        progressLock.lock()
        guard acceptingNewOperations || depth > 0 else { progressLock.unlock(); return rejected }
        activeProgress[action, default: 0] += 1; currentProgress = .running(action: action)
        progressLock.unlock()
        Thread.current.threadDictionary[operationThreadKey] = depth + 1
        defer {
            if depth == 0 { Thread.current.threadDictionary.removeObject(forKey: operationThreadKey) }
            else { Thread.current.threadDictionary[operationThreadKey] = depth }
            progressLock.lock()
            if let count = activeProgress[action], count > 1 { activeProgress[action] = count - 1 } else { activeProgress.removeValue(forKey: action) }
            currentProgress = activeProgress.keys.first.map(HESectoriumOperationProgress.running(action:)) ?? .idle
            let finished = activeProgress.isEmpty ? idleWaiters : []
            if activeProgress.isEmpty { idleWaiters.removeAll() }
            progressLock.unlock()
            finished.forEach { $0.resume() }
            if depth == 0, ["applicationAutomationStartup", "applicationAutomation", "automationStartup", "automationEvent"].contains(action) {
                // The operation body's serial lock and progress lock are both
                // released before observers can start a fresh passive refresh.
                NotificationCenter.default.post(name: Self.automaticOperationDidCompleteNotification, object: self)
            }
        }
        return body()
    }
    public func stopAcceptingNewOperations() {
        progressLock.lock(); acceptingNewOperations = false; progressLock.unlock()
    }
    public func waitForPendingOperations() async {
        await withCheckedContinuation { continuation in
            progressLock.lock()
            acceptingNewOperations = false
            if activeProgress.isEmpty { progressLock.unlock(); continuation.resume() }
            else { idleWaiters.append(continuation); progressLock.unlock() }
        }
    }

    public func mountDEV() -> OperationResult {
        withProgress("mount") {
            serial.lock(); defer { serial.unlock() }
            guard let profiles = readSectoriumProfiles() else {
                return workbenchFailure(UUID().uuidString, [], "Development-volume registry cannot be read")
            }
            if profiles.count == 1, let profile = profiles.first { return startDevelopmentDisk(profileID: profile.id) }
            if profiles.count > 1 { return workbenchFailure(UUID().uuidString, [], "Choose a registered development volume in AUV; this compatibility command has no unique target") }
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
            guard let profiles = readSectoriumProfiles() else {
                return .init(succeeded: false, summary: "Registered profile configuration is invalid; installation withheld")
            }
            let result = installer.apply(assets ?? bundledAssets(), action: action, profileConfigured: !profiles.isEmpty)
            if result.succeeded {
                configurationValid = explicitIdentityPolicy || Self.readIdentityPolicy(at: paths.config) != nil
                installedStatusLock.lock()
                lastInstalledStatus = installer.status(profileConfigured: !profiles.isEmpty)
                installedStatusLock.unlock()
            }
            lastAction = result.summary; diagnostics.append(.init(category: "install", summary: result.summary)); diagnostics = Array(diagnostics.suffix(20)); return result
        }
    }
    public func setAutomationEnabled(_ enabled: Bool) -> HESectoriumInstallResult {
        withProgress("automationConfiguration") {
            serial.lock(); defer { serial.unlock() }
            guard let profiles = readSectoriumProfiles() else {
                return .init(succeeded: false, summary: "Registered profile configuration is unavailable or invalid")
            }
            if enabled && !configurationValid && profiles.isEmpty {
                return .init(succeeded: false, summary: "A valid inspected identity configuration or registered profile is required before enabling automation")
            }
            if enabled {
                do { if try store.load().ejectIntent { return .init(succeeded: false, summary: "Pending eject recovery requires explicit manual mount") } }
                catch { return .init(succeeded: false, summary: "Durable storage state is unavailable; automation remains unchanged") }
            }
            let result = installer.setAutomation(enabled); if result.succeeded { lastAction = enabled ? "Automation enabled" : "Automation disabled; no disk action performed" }; return result
        }
    }

    public func managesBackingVolumeUUID(_ uuid: UUID) -> Bool {
        serial.lock(); defer { serial.unlock() }
        guard let profiles = readSectoriumProfiles() else { return false }
        if !profiles.isEmpty { return profiles.contains { $0.backingVolumeUUID == uuid } }
        return configurationValid && coreController.identityPolicy.outerUUID == uuid
    }

    private func runRegisteredAutomation(_ event: StorageEvent?, profiles: [SectoriumDevelopmentProfile]) -> OperationResult {
        reconcileWholeDeviceEjectRecovery()
        let startup = event == nil
        reconcileCompletedPortableEjects()
        var steps: [OperationStepResult] = []
        var firstFailure: OperationFailure?
        for saved in profiles {
            let isDisconnect: Bool
            if case .outerDisappeared = event { isDisconnect = true } else { isDisconnect = false }
            if isDisconnect {
                guard let devices = try? observationRunner.withFreshObservation({ try observeSectoriumDevices() }),
                      !devices.contains(where: { $0.id == saved.deviceID }),
                      !devices.contains(where: { $0.isExternal && !$0.identityVerified }) else {
                    steps.append(.init(step: "profile.\(saved.id).physicalDisconnectUnverified", status: .skipped))
                    continue
                }
            }
            let enabled = saved.autoLoadWasConfigured ? saved.autoLoad : installer.automationEnabled()
            // Startup must not delay storage qualification for an optional
            // external document write. Preserve its durable queue for reconnect
            // or explicit Retry. Check the queue before resolving any context.
            let pendingDocumentation = (try? portableDocumentJournal.pendingCount(parentID: saved.deviceID)) ?? 0 > 0
            // Initial Disk Arbitration appearances are not physical reconnects.
            // They must not undo startup deferral before Core ignores the duplicate.
            let reconnectAfterAbsence = !isDisconnect && !startup
                && (try? store.load().disconnectedProfileIDs.contains(saved.id)) == true
            if reconnectAfterAbsence, pendingDocumentation, lock.acquire() {
                let resolvedContext = observationRunner.withFreshObservation { () -> (SectoriumDevelopmentProfile, SectoriumPortableDocumentContext)? in
                    guard let present = resolvedProfile(saved), let context = portableContext(present) else { return nil }
                    return (present, context)
                }
                if let (present, context) = resolvedContext {
                    let result = portableDocumentJournal.synchronize(context: context, writer: portableDocumentWriter)
                    recordPortableResult(result, profileID: present.id)
                } else {
                    recordPortableDocumentPending(profileID: saved.id, reason: "Fresh document context unavailable; synchronization remains pending")
                }
                lock.release()
            }
            if !isDisconnect && !enabled {
                steps.append(.init(step: "profile.\(saved.id).autoLoadDisabled", status: .skipped))
                continue
            }
            // Disk Arbitration announces existing volumes when observation
            // starts. A previously claimed insertion needs no new image graph
            // or history intent. This is only a no-action fast path: startup,
            // recovery and verified reconnects still run the full checks below.
            if case .outerReappeared = event, lock.acquire() {
                let alreadyAttempted: Bool
                if let state = try? store.load() {
                    alreadyAttempted = state.workbenchOperation == nil && !state.ejectIntent
                        && state.reconnectAttemptedProfileIDs.contains(saved.id)
                        && !state.disconnectedProfileIDs.contains(saved.id)
                } else { alreadyAttempted = false }
                lock.release()
                if alreadyAttempted {
                    steps.append(.init(step: "profile.\(saved.id).ignoreEvent", status: .skipped,
                                       detail: "Automatic load already attempted for this insertion"))
                    continue
                }
            }
            // A disconnect has no mounted path to resolve. Its persisted identity
            // is only bookkeeping; never used to issue a disk mutation.
            // This single bounded resolution verifies physical identity and
            // backing UUID together; do not repeat the same graph immediately.
            guard let profile = isDisconnect ? saved : observationRunner.withFreshObservation({ resolvedProfile(saved) }) else {
                if (try? observationRunner.withFreshObservation({ try observeSectoriumDevices() }))?.contains(where: { $0.id == saved.deviceID }) == true {
                    firstFailure = firstFailure ?? .observationUnavailable
                    steps.append(.init(step: "profile.\(saved.id).verifyPhysicalBacking", status: .failed,
                                       detail: "The connected parent does not match the registered backing identity"))
                } else {
                    steps.append(.init(step: "profile.\(saved.id).parentUnavailable", status: .skipped,
                                       detail: "Connect the registered parent drive to load this volume"))
                }
                continue
            }
            if !isDisconnect && (!imageIdentityMatches(profile) || profile.encrypted == true) {
                firstFailure = firstFailure ?? .workbenchFailed(profile.encrypted == true ? "Authorization required to unlock the development volume" : "Registered image was replaced or is unavailable")
                steps.append(.init(step: "profile.\(profile.id).identityOrAuthorization", status: .failed))
                continue
            }
            guard profile.hasVerifiedImageFormat, let policy = profilePolicy(profile) else {
                let failure = OperationFailure.workbenchFailed("Registered profile identity or image format is invalid")
                firstFailure = firstFailure ?? failure
                steps.append(.init(step: "profile.\(profile.id).configuration", status: .failed,
                                   detail: "Registered profile identity or image format is invalid"))
                continue
            }
            let profileBackend = MacStorageBackend(paths: paths, runner: commandRunner, policy: policy)
            let documentationOperation = UUID().uuidString
            if !isDisconnect {
                guard lock.acquire() else { firstFailure = firstFailure ?? .operationInProgress; continue }
                let recorded = observationRunner.withFreshObservation {
                    recordPortableIntent(profile, operation: documentationOperation, kind: startup ? "loaded" : "reconnected")
                }
                lock.release()
                guard recorded else { firstFailure = firstFailure ?? .workbenchFailed("Automatic-load history could not be preserved"); continue }
            }
            let result: OperationResult
            if let event {
                result = coreController.handleRegisteredProfileEvent(event, profileID: profile.id,
                    policy: policy, backend: profileBackend)
            } else {
                result = coreController.mountRegisteredProfileAtStartup(profileID: profile.id,
                    policy: policy, backend: profileBackend)
            }
            firstFailure = firstFailure ?? result.failure
            steps += result.steps.map { step in
                .init(step: "profile.\(profile.id).\(step.step)", status: step.status, detail: step.detail)
            }
            if result.succeeded, result.steps.contains(where: { $0.step == "recordProfileReady" }) {
                guard lock.acquire() else { firstFailure = firstFailure ?? .operationInProgress; continue }
                var verifiedProfile: SectoriumDevelopmentProfile?
                observationRunner.withFreshObservation {
                    guard let observation = profileBackend.observe(), case .success = policy.validate(observation) else { return }
                    var verified = profile
                    verified.devUUID = observation.dev.uuid; verified.validation = .validated
                    verified.lastVerifiedLoadedAt = Date()
                    verified.imageFileIdentity = Self.imageFileIdentity(profile.imagePath)
                    do {
                        try saveProfile(verified)
                        verifiedProfile = verified
                        if startup {
                            updatePortableDocument(verified, event: "loaded", operation: documentationOperation, synchronize: false)
                        }
                    } catch { firstFailure = firstFailure ?? .workbenchFailed("Loaded volume could not persist its current identity") }
                }
                if !startup, let verified = verifiedProfile {
                    // External document mutation stays outside every metadata
                    // cache; its own identity checks must remain fresh.
                    updatePortableDocument(verified, event: "reconnected", operation: documentationOperation)
                }
                lock.release()
            }
        }
        return .init(operationID: UUID().uuidString, mode: .automatic, steps: steps, failure: firstFailure)
    }
    public func runAutomationAgent(_ event: StorageEvent) -> OperationResult {
        withProgress("automationEvent") {
            serial.lock(); defer { serial.unlock() }
            guard let profiles = readSectoriumProfiles() else {
                return record(.init(operationID: UUID().uuidString, mode: .automatic, steps: [],
                                    failure: .workbenchFailed("Registered profile configuration is invalid")))
            }
            let isDisconnect: Bool
            if case .outerDisappeared = event { isDisconnect = true } else { isDisconnect = false }
            guard (configurationValid || !profiles.isEmpty), isDisconnect || installer.automationEnabled() else {
                return record(.init(operationID: UUID().uuidString, mode: .automatic,
                                    steps: [.init(step: "automationGate", status: .skipped, detail: "Disabled or identity configuration unavailable")]))
            }
            if !profiles.isEmpty {
                let matching = profiles.filter { profile in
                    switch event {
                    case .outerDisappeared(let uuid), .outerReappeared(let uuid): return profile.backingVolumeUUID == uuid
                    case .devMounted, .imageChanged: return false
                    }
                }
                guard !matching.isEmpty else {
                    return record(.init(operationID: UUID().uuidString, mode: .automatic,
                                        steps: [.init(step: "ignoreEvent", status: .skipped,
                                                      detail: "Event does not match a registered development backing volume")]))
                }
                return record(runRegisteredAutomation(event, profiles: matching))
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
    /// The running application is already the explicitly selected owner. Its
    /// per-volume preferences are independent of whether the optional login
    /// LaunchAgent is installed/enabled. Both routes share Core's lock and claims.
    public func runApplicationAutomation(_ event: StorageEvent) -> OperationResult {
        withProgress("applicationAutomation") {
        serial.lock(); defer { serial.unlock() }
        guard let profiles = readSectoriumProfiles() else {
            return .init(operationID: UUID().uuidString, mode: .automatic, steps: [],
                         failure: .workbenchFailed("Registered profile configuration is invalid"))
        }
        let matching = profiles.filter { profile in
            switch event {
            case .outerDisappeared(let uuid), .outerReappeared(let uuid): return profile.backingVolumeUUID == uuid
            case .devMounted, .imageChanged: return false
            }
        }
        guard !matching.isEmpty else {
            return record(.init(operationID: UUID().uuidString, mode: .automatic,
                                steps: [.init(step: "ignoreEvent", status: .skipped,
                                              detail: "Event does not match a registered development backing volume")]))
        }
        return record(runRegisteredAutomation(event, profiles: matching))
        }
    }

    public func runApplicationAutomationAtStartup() -> OperationResult {
        withProgress("applicationAutomationStartup") {
        serial.lock(); defer { serial.unlock() }
        guard let profiles = readSectoriumProfiles() else {
            return .init(operationID: UUID().uuidString, mode: .automatic, steps: [],
                         failure: .workbenchFailed("Registered profile configuration is invalid"))
        }
        return record(runRegisteredAutomation(nil, profiles: profiles))
        }
    }

    /// Called once by the already-installed LaunchAgent at login. This is a single inspected startup action, not polling.
    public func runAutomationAgentAtStartup() -> OperationResult {
        withProgress("automationStartup") {
        serial.lock(); defer { serial.unlock() }
        guard let profiles = readSectoriumProfiles() else {
            return record(.init(operationID: UUID().uuidString, mode: .automatic, steps: [],
                                failure: .workbenchFailed("Registered profile configuration is invalid")))
        }
        guard (configurationValid || !profiles.isEmpty), installer.automationEnabled() else {
            return record(.init(operationID: UUID().uuidString, mode: .automatic,
                                steps: [.init(step: "automationGate", status: .skipped, detail: "Disabled or identity configuration unavailable")]))
        }
        if !profiles.isEmpty { return record(runRegisteredAutomation(nil, profiles: profiles)) }
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
    private let eventHandler: (@Sendable (StorageEvent) -> Void)?
    private let lifecycle = NSLock()
    private var started = false
    private var registered = false
    private let callbackQueueKey = DispatchSpecificKey<UInt8>()
    private let callbackQueue = DispatchQueue(label: "com.openai.uma.hesectorium.disk-arbitration")
    public init?(service: HESectoriumService, eventHandler: (@Sendable (StorageEvent) -> Void)? = nil) {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return nil }
        self.service = service; self.session = session; self.eventHandler = eventHandler
        callbackQueue.setSpecific(key: callbackQueueKey, value: 1)
    }
    public func start() {
        lifecycle.lock(); defer { lifecycle.unlock() }
        guard !started else { return }; started = true
        if !registered {
        registered = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        let appeared: DADiskAppearedCallback = { disk, context in
            guard let context else { return }; Unmanaged<HESectoriumDiskObserver>.fromOpaque(context).takeUnretainedValue().deliver(disk, true)
        }
        let disappeared: DADiskDisappearedCallback = { disk, context in
            guard let context else { return }; Unmanaged<HESectoriumDiskObserver>.fromOpaque(context).takeUnretainedValue().deliver(disk, false)
        }
        DARegisterDiskAppearedCallback(session, nil, appeared, context); DARegisterDiskDisappearedCallback(session, nil, disappeared, context)
        }
        DASessionSetDispatchQueue(session, callbackQueue)
    }
    public func stop() {
        lifecycle.lock()
        guard started else { lifecycle.unlock(); return }
        started = false
        DASessionSetDispatchQueue(session, nil)
        lifecycle.unlock()
        // Drain callbacks before an owner releases this observer. Session teardown
        // itself is handled by Disk Arbitration; no disk command is performed.
        if DispatchQueue.getSpecific(key: callbackQueueKey) == nil { callbackQueue.sync {} }
    }
    deinit { stop() }
    private func deliver(_ disk: DADisk, _ appeared: Bool) {
        lifecycle.lock(); let active = started; lifecycle.unlock()
        guard active else { return }
        guard let desc = DADiskCopyDescription(disk) as NSDictionary?,
              let raw = desc.object(forKey: kDADiskDescriptionVolumeUUIDKey),
              let uuid = (raw as? UUID) ?? (raw as? String).flatMap(UUID.init(uuidString:)) else { return }
        let event: StorageEvent = appeared ? .outerReappeared(uuid: uuid) : .outerDisappeared(uuid: uuid)
        // App routing only enqueues. It must not wait for Service's serial lock on
        // this callback queue: stop() drains that queue while the app is quitting.
        if let eventHandler { eventHandler(event) }
        else if service.managesBackingVolumeUUID(uuid) { _ = service.runAutomationAgent(event) }
    }
}
#endif
