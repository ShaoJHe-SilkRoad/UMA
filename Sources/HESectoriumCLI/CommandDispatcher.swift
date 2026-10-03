import Foundation
import HESectoriumCore
import HESectoriumRuntime

public protocol HESectoriumCommandServing: AnyObject {
    func refreshStatus() -> HESectoriumRuntimeSnapshot
    func mountDEV() -> OperationResult
    func safeEjectHE() -> OperationResult
    func installRepair(_ action: HESectoriumInstallAction) -> HESectoriumInstallResult
    func setAutomationEnabled(_ enabled: Bool) -> HESectoriumInstallResult
    func runAgent() -> Int32
}

public enum HESectoriumCommandDispatcher {
    public static func report(_ result: OperationResult, writeStdout: (String) -> Void, writeStderr: (String) -> Void) -> Int32 {
        emit([
            "operation_id": result.operationID,
            "mode": result.mode.rawValue,
            "succeeded": result.succeeded,
            "failure": result.failure.map(String.init(describing:)) as Any? ?? NSNull(),
            "steps": result.steps.map { ["step": $0.step, "status": $0.status.rawValue, "detail": $0.detail] }
        ], writeStdout: writeStdout, writeStderr: writeStderr)
        return result.succeeded ? 0 : 1
    }

    @discardableResult
    public static func run(arguments: DropFirstSequence<[String]>, service: HESectoriumCommandServing,
                           writeStdout: (String) -> Void, writeStderr: (String) -> Void) -> Int32 {
        let command = arguments.first(where: { _ in true }) ?? "status"
        switch command {
        case "status":
            let state = service.refreshStatus()
            return emit([
                "installed": String(describing: state.installed),
                "automation_enabled": state.automationEnabled,
                "agent_load_status": String(describing: state.agentLoadStatus),
                "operation_progress": String(describing: state.operationProgress),
                "readiness": String(describing: state.readiness),
                "pending_eject": state.pendingEject.map { $0 as Any } ?? NSNull(),
                "latest_action": state.latestActionSummary,
                "diagnostics": state.diagnostics.map { ["time": ISO8601DateFormatter().string(from: $0.timestamp), "category": $0.category, "summary": $0.summary] }
            ], writeStdout: writeStdout, writeStderr: writeStderr)
        case "mount": return report(service.mountDEV(), writeStdout: writeStdout, writeStderr: writeStderr)
        case "eject": return report(service.safeEjectHE(), writeStdout: writeStdout, writeStderr: writeStderr)
        case "install": return report(service.installRepair(.install), writeStdout: writeStdout, writeStderr: writeStderr)
        case "repair": return report(service.installRepair(.repair), writeStdout: writeStdout, writeStderr: writeStderr)
        case "enable-auto": return report(service.setAutomationEnabled(true), writeStdout: writeStdout, writeStderr: writeStderr)
        case "disable-auto": return report(service.setAutomationEnabled(false), writeStdout: writeStdout, writeStderr: writeStderr)
        case "agent": return service.runAgent()
        case "help", "--help", "-h":
            writeStdout("Usage: HESectoriumControl <status|mount|eject|install|repair|enable-auto|disable-auto|agent>")
            return 0
        default:
            writeStderr("HESectoriumControl: unknown command '\(command)'\n")
            return 2
        }
    }

    @discardableResult
    private static func emit(_ value: Any, writeStdout: (String) -> Void, writeStderr: (String) -> Void) -> Int32 {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            writeStderr("HESectoriumControl: could not encode result\n")
            return 2
        }
        writeStdout(line)
        return 0
    }

    private static func report(_ value: HESectoriumInstallResult, writeStdout: (String) -> Void,
                               writeStderr: (String) -> Void) -> Int32 {
        let code = emit([
            "succeeded": value.succeeded,
            "summary": value.summary,
            "changed_paths": value.changedPaths,
            "file_outcomes": value.fileOutcomes.map { ["file": $0.file, "state": $0.state.rawValue, "detail": $0.detail] }
        ], writeStdout: writeStdout, writeStderr: writeStderr)
        return code == 0 && !value.succeeded ? 1 : code
    }
}
