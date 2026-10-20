import AppKit
import Foundation
import HESectoriumRuntime

public struct SectoriumQuitApplication: Equatable, Sendable, Identifiable {
    public var id: Int32 { processID }
    public let processID: Int32
    public let bundleIdentifier: String
    public let name: String
    public init(processID: Int32, bundleIdentifier: String, name: String) {
        self.processID = processID; self.bundleIdentifier = bundleIdentifier; self.name = name
    }
}

/// Normal application termination only. A save dialog or refused quit leaves
/// the disk connected; the caller always repeats the storage precheck afterward.
@MainActor public protocol SectoriumApplicationQuitting: AnyObject {
    func applications(using processes: [SectoriumActivityProcess]) -> [SectoriumQuitApplication]
    func requestQuit(_ application: SectoriumQuitApplication) -> Bool
    func isRunning(_ application: SectoriumQuitApplication) -> Bool
}

@MainActor public final class SectoriumSystemApplicationQuitter: SectoriumApplicationQuitting {
    public init() {}
    public func applications(using processes: [SectoriumActivityProcess]) -> [SectoriumQuitApplication] {
        let running = NSWorkspace.shared.runningApplications
        var result: [Int32: SectoriumQuitApplication] = [:]
        for process in processes {
            // A helper may own the file reference. Match its actual executable
            // to the containing app, never a display-name substring alone.
            let app = running.first { app in
                guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier,
                      !app.isTerminated, app.activationPolicy != .prohibited else { return false }
                if app.processIdentifier == process.processID { return true }
                if app.processIdentifier == process.owningApplicationProcessID,
                   app.bundleIdentifier == process.bundleIdentifier { return true }
                guard let executable = process.executablePath, let bundle = app.bundleURL?.path else { return false }
                return executable.hasPrefix(bundle + "/")
                    && (process.bundleIdentifier == nil || process.bundleIdentifier == app.bundleIdentifier)
            }
            guard let app, let bundleID = app.bundleIdentifier else { continue }
            result[app.processIdentifier] = .init(processID: app.processIdentifier,
                bundleIdentifier: bundleID, name: app.localizedName ?? process.applicationName ?? process.command)
        }
        return result.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func requestQuit(_ application: SectoriumQuitApplication) -> Bool {
        guard let app = matching(application) else { return true }
        return app.terminate()
    }
    public func isRunning(_ application: SectoriumQuitApplication) -> Bool { matching(application) != nil }
    private func matching(_ application: SectoriumQuitApplication) -> NSRunningApplication? {
        guard application.processID != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: application.processID),
              app.bundleIdentifier == application.bundleIdentifier,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !app.isTerminated, app.activationPolicy != .prohibited else { return nil }
        return app
    }
}

enum SectoriumApplicationQuitResult: Equatable {
    case finished, cancelled, refused([String]), stillRunning([String])
}

@MainActor enum SectoriumApplicationQuitSequence {
    static func run(applications: [SectoriumQuitApplication], quitter: any SectoriumApplicationQuitting,
                    attempts: Int = 40,
                    pause: @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) }) async -> SectoriumApplicationQuitResult {
        guard !Task.isCancelled else { return .cancelled }
        var refused: [String] = []
        for app in applications {
            guard !Task.isCancelled else { return .cancelled }
            if !quitter.requestQuit(app) { refused.append(app.name) }
        }
        if !refused.isEmpty { return .refused(refused) }
        for _ in 0..<max(1, attempts) {
            guard !Task.isCancelled else { return .cancelled }
            if applications.allSatisfy({ !quitter.isRunning($0) }) { return .finished }
            do { try await pause() } catch { return .cancelled }
        }
        let remaining = applications.filter(quitter.isRunning).map(\.name)
        return remaining.isEmpty ? .finished : .stillRunning(remaining)
    }
}
