import AppKit
import CodexUsageUI

enum AppShellDiagnosticStage: String, Codable, Sendable {
    case shellCreated
    case statusItemExists
    case statusItemEnabled
    case statusItemButtonExists
    case mouseDownReceived
    case mouseUpReceived
    case targetPresent
    case actionPresent
    case actionInvoked
    case mainActorEntered
    case toggleRequested
    case panelControllerExists
    case panelWindowExists
    case panelWindowOrderedFront
    case panelWindowKeyState
    case panelVisible
    case hitTestingEnabled
    case panelClosed
    case staleGenerationRejected
    case shellTornDown
    case runtimeAttached
    case runtimeAttachmentFailed
}

struct AppShellDiagnosticReceipt: Codable, Sendable {
    let stage: AppShellDiagnosticStage
    let reached: Bool
    let lifecycleGeneration: String
    let statusItemCount: Int
    let panelWindowCount: Int
    let eventMonitorCount: Int
    let mainThreadStallMilliseconds: Int
    let activeModalWindow: Bool
    let activeSheetWindow: Bool
    let eventMonitorOwners: [String]
    let applicationIsHidden: Bool
    let frontmostApplicationBundleIdentifier: String?
    let panelLevel: Int?
    let panelAlpha: Double?
    let panelFrame: String?
    let panelIgnoresMouseEvents: Bool?
    let detail: String?
    let timestamp: Date
}

struct AppShellMachineDiagnosticResult: Codable, Sendable {
    let requestedToggleCount: Int
    let completedToggleCount: Int
    let statusItemCount: Int
    let panelWindowCount: Int
    let eventMonitorCount: Int
    let applicationIsHidden: Bool
    let finalPanelVisible: Bool
    let providerStartupEnabled: Bool
    let passed: Bool
    let firstFailure: String?
}

/// Content-free shell receipts make one physical menu-bar click diagnosable
/// without coupling the shell to any provider or browser subsystem.
final class AppShellDiagnosticRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.silkrd.uma.shell-diagnostics")
    private let destination: URL?
    private var boundedReceipts: [AppShellDiagnosticReceipt] = []

    init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        guard let bundleIdentifier else {
            destination = nil
            return
        }
        destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("ShellDiagnostics", isDirectory: true)
            .appendingPathComponent("latest.json")
    }

    func record(_ receipt: AppShellDiagnosticReceipt) {
        guard let destination else { return }
        queue.async {
            do {
                let directory = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                self.boundedReceipts.append(receipt)
                self.boundedReceipts = Array(self.boundedReceipts.suffix(64))
                let data = try JSONEncoder().encode(self.boundedReceipts)
                try data.write(to: destination, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: destination.path
                )
            } catch {
                // Diagnostics must never impede the product shell.
            }
        }
    }
}

@MainActor
final class AppShellCoordinator {
    private static weak var activeCoordinator: AppShellCoordinator?

    let lifecycleGeneration = UUID()
    private let diagnostics: AppShellDiagnosticRecorder
    private let statusBarController: StatusBarController
    private var isTornDown = false

    init(
        diagnostics: AppShellDiagnosticRecorder = AppShellDiagnosticRecorder()
    ) {
        precondition(Self.activeCoordinator == nil, "Only one AppShellCoordinator may be active")
        self.diagnostics = diagnostics
        statusBarController = StatusBarController(
            lifecycleGeneration: lifecycleGeneration,
            diagnostics: diagnostics
        )
        Self.activeCoordinator = self
        statusBarController.recordShellCreated()
    }

    func attach(runtime: UsageMonitorRuntime) {
        guard !isTornDown else { return }
        statusBarController.attach(runtime: runtime)
    }

    func recordRuntimeAttachmentFailure() {
        statusBarController.recordRuntimeAttachmentFailure()
    }

    func runMachineDiagnostic(toggleCount: Int) async -> AppShellMachineDiagnosticResult {
        await statusBarController.runMachineDiagnostic(toggleCount: toggleCount)
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        statusBarController.tearDown()
        if Self.activeCoordinator === self {
            Self.activeCoordinator = nil
        }
    }
}
