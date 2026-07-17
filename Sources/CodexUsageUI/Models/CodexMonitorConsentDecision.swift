import Foundation

public enum CodexMonitorConsentDecision: String, Sendable {
    case unknown
    case declined
    case granted

    static let storageKey = "monitor.consentDecision"

    static func load(from defaults: UserDefaults?) -> Self {
        guard
            let rawValue = defaults?.string(forKey: storageKey),
            let decision = Self(rawValue: rawValue)
        else {
            return .unknown
        }
        return decision
    }

    func persist(to defaults: UserDefaults?) {
        defaults?.set(rawValue, forKey: Self.storageKey)
    }
}

public enum CodexPreviewScenario: String, CaseIterable, Sendable {
    case permission
    case connecting
    case accountChecking
    case authorization
    case waiting
    case loading
    case ready
    case refreshing
    case stale
    case recoverableFailure
    case blockedFailure
    case settings

    var displaysFixtureData: Bool {
        switch self {
        case .ready, .refreshing, .stale, .settings: true
        default: false
        }
    }

    var connectionState: CodexConnectionState {
        switch self {
        case .permission: .notAuthorizedByMonitor
        case .connecting: .startingServer
        case .accountChecking: .checkingAccount
        case .authorization: .authorizationRequired
        case .waiting: .officialCodexSignInRequired
        case .loading: .loadingUsage
        case .ready, .settings: .ready
        case .refreshing: .refreshingWithPreviousRealData
        case .stale: .staleWithPreviousRealData(.requestTimedOut(method: "preview"))
        case .recoverableFailure: .recoverableFailure(.requestTimedOut(method: "preview"))
        case .blockedFailure: .blockedFailure(.codexApplicationNotFound)
    }
}
}
