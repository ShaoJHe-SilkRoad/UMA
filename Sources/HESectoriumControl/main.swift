import Foundation
import HESectoriumCLI
import HESectoriumRuntime
#if canImport(DiskArbitration)
import DiskArbitration
#endif

extension HESectoriumService: HESectoriumCommandServing {
    public func installRepair(_ action: HESectoriumInstallAction) -> HESectoriumInstallResult {
        installRepair(action, assets: nil)
    }

    public func runAgent() -> Int32 {
        let startup = runAutomationAgentAtStartup()
        let startupExit = HESectoriumCommandDispatcher.report(startup, writeStdout: { print($0) }, writeStderr: { fputs($0, stderr) })
        if startupExit != 0 {
            // A failed one-shot startup load is not a successful action. Keep the
            // single installed observer alive so a later verified reconnect can
            // be handled; the startup failure was already reported to stderr.
            fputs("HESectoriumControl: startup load failed; observing for verified device changes\n", stderr)
        }
        #if canImport(DiskArbitration)
        guard let observer = HESectoriumDiskObserver(service: self) else {
            fputs("HESectoriumControl: Disk Arbitration is unavailable\n", stderr)
            return 1
        }
        observer.start()
        RunLoop.main.run()
        return 0
        #else
        fputs("HESectoriumControl: Disk Arbitration is unavailable\n", stderr)
        return 1
        #endif
    }
}

let service = HESectoriumService.shared
let code = HESectoriumCommandDispatcher.run(
    arguments: CommandLine.arguments.dropFirst(),
    service: service,
    writeStdout: { print($0) },
    writeStderr: { fputs($0, stderr) }
)
exit(code)
