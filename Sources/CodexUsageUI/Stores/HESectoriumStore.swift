import Combine
import Foundation
import HESectoriumRuntime

@MainActor
public final class HESectoriumStore: ObservableObject {
    @Published public private(set) var snapshot = HESectoriumRuntimeSnapshot(
        installed: .missing, automationEnabled: false, readiness: .unknown, pendingEject: nil,
        diagnostics: [], latestActionSummary: "Status has not been checked"
    )
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastResult = ""

    private let service: HESectoriumService

    public init(service: HESectoriumService = .shared) { self.service = service }

    public func refresh() {
        guard !isBusy else { return }
        let service = self.service
        Task.detached(priority: .utility) { [weak self] in
            let value = service.refreshStatus()
            await MainActor.run { self?.snapshot = value }
        }
    }

    public func mountDEV() { perform { service in
        let result = service.mountDEV()
        return result.failure.map { "Failed: \($0)" } ?? "Completed"
    } }
    public func safeEjectHE() { perform { service in
        let result = service.safeEjectHE()
        return result.failure.map { "Failed: \($0)" } ?? "Completed"
    } }
    public func installRepair() { performInstall(.repair) }
    public func install() { performInstall(.install) }
    public func setAutomation(_ enabled: Bool) {
        guard !isBusy else { return }
        isBusy = true
        let service = self.service
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = service.setAutomationEnabled(enabled)
            let status = service.refreshStatus()
            await MainActor.run {
                self?.lastResult = result.summary
                self?.snapshot = status
                self?.isBusy = false
            }
        }
    }

    private func perform(_ action: @escaping @Sendable (HESectoriumService) -> String) {
        guard !isBusy else { return }
        isBusy = true
        let service = self.service
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = action(service)
            let status = service.refreshStatus()
            await MainActor.run {
                self?.lastResult = result
                self?.snapshot = status
                self?.isBusy = false
            }
        }
    }

    private func performInstall(_ action: HESectoriumInstallAction) {
        guard !isBusy else { return }
        isBusy = true
        let service = self.service
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = service.installRepair(action)
            let status = service.refreshStatus()
            await MainActor.run {
                self?.lastResult = result.summary
                self?.snapshot = status
                self?.isBusy = false
            }
        }
    }
}
