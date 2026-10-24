import Foundation
import Testing
import HESectoriumCore
@testable import HESectoriumRuntime

private final class CompletionCommandFixture: HESectoriumCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return recordedCalls }
    func run(_ executable: String, _ arguments: [String], cwd: URL) -> CommandOutcome {
        lock.lock(); recordedCalls += 1; lock.unlock()
        return .init(exitCode: 1, detail: "Fixture rejects all subprocesses")
    }
}

private final class CompletionSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return recorded }
    func append() { lock.lock(); recorded += 1; lock.unlock() }
}

private final class CompletionServiceFixture {
    let root: URL
    let paths: HESectoriumPaths
    let runner = CompletionCommandFixture()
    let service: HESectoriumService
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sectorium-completion-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = HESectoriumPaths(root: root)
        service = HESectoriumService(paths: paths,
            installer: HESectoriumInstaller(paths: paths, home: root.appendingPathComponent("home")),
            runner: runner)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}

@Suite("Automatic operation completion signals")
struct SectoriumAutomaticOperationCompletionTests {
    @Test("All automatic entry points signal completion after releasing both Service locks")
    func completionAllowsFreshObservationOnAnotherThread() throws {
        let fixture = try CompletionServiceFixture(), service = fixture.service
        let signals = CompletionSignals(), observations = DispatchGroup()
        let token = NotificationCenter.default.addObserver(
            forName: HESectoriumService.automaticOperationDidCompleteNotification,
            object: service, queue: nil
        ) { note in
            #expect(note.object as? HESectoriumService === service)
            signals.append()
            let observed = DispatchSemaphore(value: 0)
            observations.enter()
            DispatchQueue.global().async {
                defer { observations.leave(); observed.signal() }
                service.withReadOnlyObservation {
                    #expect(service.refreshStatus(observedReadiness: .noDevelopmentDisk).operationProgress == .idle)
                }
            }
            // A synchronous observer must be able to take both locks on another
            // thread; recursive same-thread access would hide an early signal.
            // The bound is a deadlock guard rather than a speed claim, and is
            // generous because a full parallel suite run delays this handoff by
            // seconds where an isolated run takes milliseconds.
            #expect(observed.wait(timeout: .now() + 60) == .success)
        }
        defer { NotificationCenter.default.removeObserver(token) }
        #expect(service.runApplicationAutomationAtStartup().succeeded)
        #expect(service.runApplicationAutomation(.imageChanged).succeeded)
        #expect(service.runAutomationAgentAtStartup().succeeded)
        #expect(service.runAutomationAgent(.imageChanged).succeeded)
        #expect(observations.wait(timeout: .now() + 60) == .success)
        #expect(signals.count == 4)
        #expect(fixture.runner.calls == 0)
    }

    @Test("A failed automatic operation emits completion, but manual and rejected operations do not")
    func failureIsCompletionNotSuccess() throws {
        let fixture = try CompletionServiceFixture(), service = fixture.service
        try Data("invalid registry".utf8).write(to: fixture.paths.sectoriumProfiles)
        let signals = CompletionSignals()
        let token = NotificationCenter.default.addObserver(
            forName: HESectoriumService.automaticOperationDidCompleteNotification,
            object: service, queue: nil
        ) { _ in signals.append() }
        defer { NotificationCenter.default.removeObserver(token) }
        #expect(!service.runApplicationAutomationAtStartup().succeeded)
        #expect(!service.runApplicationAutomation(.imageChanged).succeeded)
        #expect(!service.runAutomationAgentAtStartup().succeeded)
        #expect(!service.runAutomationAgent(.imageChanged).succeeded)
        #expect(signals.count == 4)
        #expect(!service.safeEjectHE().succeeded)
        #expect(signals.count == 4)
        service.stopAcceptingNewOperations()
        #expect(!service.runApplicationAutomationAtStartup().succeeded)
        #expect(!service.runApplicationAutomation(.imageChanged).succeeded)
        #expect(signals.count == 4)
        #expect(fixture.runner.calls == 0)
    }

    @Test("Completion is scoped to its Service instance and observer lifetime")
    func observerDoesNotLeakAcrossServicesOrAfterRemoval() throws {
        let first = try CompletionServiceFixture(), second = try CompletionServiceFixture()
        let signals = CompletionSignals()
        let token = NotificationCenter.default.addObserver(
            forName: HESectoriumService.automaticOperationDidCompleteNotification,
            object: first.service, queue: nil
        ) { _ in signals.append() }
        #expect(second.service.runApplicationAutomationAtStartup().succeeded)
        #expect(signals.count == 0)
        #expect(first.service.runApplicationAutomationAtStartup().succeeded)
        #expect(signals.count == 1)
        NotificationCenter.default.removeObserver(token)
        #expect(first.service.runApplicationAutomationAtStartup().succeeded)
        #expect(signals.count == 1)
        #expect(first.runner.calls == 0 && second.runner.calls == 0)
    }
}
