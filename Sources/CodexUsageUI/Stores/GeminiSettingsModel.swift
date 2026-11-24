import AppKit
import Foundation

/// What Settings says about Gemini. Each case names what, if anything, the
/// person has to do next.
public enum GeminiSettingsState: Equatable, Sendable {
    case off
    case reading
    case fresh(Date)
    case cached(Date)
    case stale(Date)
    case needsSiteAccess
    case needsSignIn
    case bridgeUnavailable
    case versionMismatch
    case pageUnreadable
    case failed
}

/// Gemini is turned on and off by its monitoring switch: turning it on is the
/// person's consent to AUV reading gemini.google.com/usage through the Safari
/// Bridge, and turning it off stops every read and drops the last value.
@MainActor
public final class GeminiSettingsModel: ObservableObject {
    @Published public private(set) var state: GeminiSettingsState = .off

    private let connector: GeminiUsageConnector
    private let agentSettings: AgentSettingsCoordinator
    private let refreshAdmissions: @MainActor () async -> Void
    private var observation: Task<Void, Never>?

    static let usagePageURL = URL(string: "https://gemini.google.com/usage")!

    init(
        connector: GeminiUsageConnector,
        agentSettings: AgentSettingsCoordinator,
        refreshAdmissions: @escaping @MainActor () async -> Void
    ) {
        self.connector = connector
        self.agentSettings = agentSettings
        self.refreshAdmissions = refreshAdmissions
        observe()
    }

    deinit { observation?.cancel() }

    var isEnabled: Bool {
        agentSettings.isMonitoringEnabled(for: AgentPreferenceRecord.geminiProviderID)
    }

    /// Turns Gemini on and reads once now.
    public func enable() {
        agentSettings.setMonitoringEnabled(true, for: AgentPreferenceRecord.geminiProviderID)
        syncNow()
    }

    public func syncNow() {
        guard isEnabled else { return }
        state = .reading
        Task { @MainActor in
            await connector.perform(.connect)
            await refreshAdmissions()
        }
    }

    public func disable() {
        agentSettings.setMonitoringEnabled(false, for: AgentPreferenceRecord.geminiProviderID)
        state = .off
        Task { @MainActor in
            await connector.perform(.disconnect)
            await refreshAdmissions()
        }
    }

    /// Opens the Usage page in Safari for the person to sign in or allow the
    /// site. AUV does nothing in Safari beyond asking it to open this page.
    public func openUsagePageInSafari() {
        let workspace = NSWorkspace.shared
        guard let safari = workspace.urlForApplication(
            withBundleIdentifier: SafariWindowVisibility.bundleIdentifier
        ) else {
            workspace.open(Self.usagePageURL)
            return
        }
        workspace.open(
            [Self.usagePageURL],
            withApplicationAt: safari,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func observe() {
        let connector = connector
        observation = Task { @MainActor [weak self] in
            for await snapshot in await connector.snapshots() {
                guard let self else { return }
                let error = await connector.lastReadError()
                self.state = Self.state(for: snapshot, lastError: error, enabled: self.isEnabled)
            }
        }
    }

    nonisolated static func state(
        for snapshot: AgentUsageSnapshot,
        lastError: GeminiBrowserReadError?,
        enabled: Bool
    ) -> GeminiSettingsState {
        guard enabled else { return .off }
        let observedAt = snapshot.lastSuccessfulAt ?? snapshot.capturedAt
        switch snapshot.state {
        case .inactive: return .off
        case .waitingForFirstResponse: return .reading
        case .authenticationRequired:
            return lastError == .signInRequired ? .needsSignIn : .needsSiteAccess
        case .unsupported: return .versionMismatch
        case .ready, .stale:
            switch snapshot.freshness {
            case .fresh: return .fresh(observedAt)
            case .cached: return .cached(observedAt)
            case .stale: return .stale(observedAt)
            case .unavailable: return .failed
            }
        case .failed:
            switch lastError {
            case .companionUnavailable, .browserUnavailable: return .bridgeUnavailable
            case .usageUnavailable: return .pageUnreadable
            default: return .failed
            }
        }
    }
}
