import Foundation
import HESectoriumCore
import HESectoriumRuntime
import HESectoriumCLI

private final class FixtureStateStore: DurableStateStore {
    private var state = StoragePersistentState(ejectIntent: false)
    func load() throws -> StoragePersistentState { state }
    func compareAndSwap(expectedRevision: UInt64, newState: StoragePersistentState) throws -> Bool {
        guard state.revision == expectedRevision else { return false }
        state = newState
        return true
    }
}

private final class FixtureOperationLock: OperationLock {
    private var held = false
    func acquire() -> Bool { guard !held else { return false }; held = true; return true }
    func release() { held = false }
}

private final class FixtureStorageBackend: StorageBackend {
    var outer: VolumeIdentity? = StorageObservation.expectedReady.outer
    var observation: StorageObservation? = .expectedReady
    var occupancy: [OccupancyScope: OccupancyAssessment] = [.dev: .noVisibleOccupancy, .outer: .noVisibleOccupancy]
    var failFlush = false
    var failPostAttachObservation = false

    func observeOuter() -> VolumeIdentity? { outer }
    func observe() -> StorageObservation? { observation }
    func attachImage() -> CommandOutcome {
        if failPostAttachObservation { observation = nil }
        return .success
    }
    func assessOccupancy(scope: OccupancyScope) -> OccupancyAssessment { occupancy[scope] ?? .incomplete(reason: "fixture not configured") }
    func perform(_ step: EjectStep) -> CommandOutcome {
        step == .flush && failFlush ? .init(exitCode: 73, detail: "fixture flush refused") : .success
    }
    func finalOuterState() -> FinalOuterState { .absent }
}

private final class FixtureCommandService: HESectoriumCommandServing {
    private let controller: StorageController
    private let backend: FixtureStorageBackend

    init(scenario: String) {
        backend = FixtureStorageBackend()
        if scenario == "refused-mount" {
            backend.outer = .init(uuid: UUID(), mountPoint: "/Volumes/HE", fileSystem: "ExFAT", writable: true,
                                  name: "HE", rootMatchesExpected: true)
        }
        backend.failPostAttachObservation = scenario == "postcheck-mount"
        backend.failFlush = scenario == "failed-eject"
        controller = StorageController(backend: backend, store: FixtureStateStore(), lock: FixtureOperationLock())
    }

    func refreshStatus() -> HESectoriumRuntimeSnapshot {
        .init(installed: .missing, automationEnabled: false, readiness: .ready,
              pendingEject: false, diagnostics: [], latestActionSummary: "fixture status")
    }
    func mountDEV() -> OperationResult { controller.mountDEV() }
    func safeEjectHE() -> OperationResult { controller.safeEjectHE() }
    func installRepair(_ action: HESectoriumInstallAction) -> HESectoriumInstallResult {
        .init(succeeded: false, summary: "fixture installer is not configured")
    }
    func setAutomationEnabled(_ enabled: Bool) -> HESectoriumInstallResult {
        .init(succeeded: false, summary: "fixture automation is not configured")
    }
    func runAgent() -> Int32 { 1 }
}

private func writeStdout(_ value: String) { print(value) }
private func writeStderr(_ value: String) { fputs(value, stderr) }

let scenario = CommandLine.arguments.dropFirst().first ?? "status"
let command: String
switch scenario {
case "refused-mount", "postcheck-mount", "successful-mount": command = "mount"
case "failed-eject": command = "eject"
case "status": command = "status"
default:
    fputs("unknown fixture scenario\n", stderr)
    exit(64)
}

private let service = FixtureCommandService(scenario: scenario)
exit(HESectoriumCommandDispatcher.run(arguments: [command].dropFirst(0), service: service,
                                      writeStdout: writeStdout, writeStderr: writeStderr))
