import Foundation

public enum WorkBuddyLoginAccountMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case personal
    case enterprise

    public var id: String { rawValue }
}

public enum WorkBuddySignatureTrust: String, Codable, Sendable {
    case trusted
    case unverifiable
    case rejected

    var requiresOfficialInstallConfirmation: Bool { self != .trusted }
}

public struct WorkBuddyInstalledApplication: Equatable, Sendable {
    let url: URL
    let bundleIdentifier: String
    let displayName: String
    let version: String?
    let build: String?
    let signatureTrust: WorkBuddySignatureTrust
    let installationIdentity: String
}

public enum WorkBuddyInstallationStatus: Equatable, Sendable {
    case notInstalled
    case invalidBundleIdentity(found: String?)
    case available(WorkBuddyInstalledApplication)

    var application: WorkBuddyInstalledApplication? {
        guard case let .available(application) = self else { return nil }
        return application
    }

    var persistedState: WorkBuddyPersistedInstallState {
        switch self {
        case .notInstalled: .notInstalled
        case .invalidBundleIdentity: .invalidIdentity
        case let .available(application):
            application.signatureTrust == .trusted
                ? .installedTrusted
                : .installedNeedsConfirmation
        }
    }
}

enum WorkBuddyPersistedInstallState: String, Codable, Sendable {
    case unknown
    case notInstalled
    case invalidIdentity
    case installedTrusted
    case installedNeedsConfirmation
}

public enum WorkBuddyLoginFailure: String, Codable, Sendable {
    case applicationNotInstalled
    case invalidBundleIdentity
    case privacyConfirmationRequired
    case officialInstallConfirmationRequired
    case launchDenied
    case launchFailed
    case timedOut
}

public enum WorkBuddyLoginFlowState: Equatable, Sendable {
    case idle
    case confirmationRequired
    case readyToOpen
    case opening
    case awaitingUserCompletion
    case checking
    case completed
    case cancelled
    case failed(WorkBuddyLoginFailure)

    var isActive: Bool {
        switch self {
        case .confirmationRequired, .readyToOpen, .opening,
             .awaitingUserCompletion, .checking:
            true
        case .idle, .completed, .cancelled, .failed:
            false
        }
    }
}

public enum WorkBuddyLoginSafeResult: String, Codable, Sendable {
    case flowLaunched
    case userConfirmedCompleted
    case unsupportedLocalCreditsSource
}

enum WorkBuddyApplicationLaunchResult: Equatable, Sendable {
    case launched
    case activated
    case denied
    case failed
}

struct WorkBuddyLoginPersistenceRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    var accountMode: WorkBuddyLoginAccountMode
    var privacyConfirmedAt: Date?
    var officialInstallConfirmedAt: Date?
    var officialInstallIdentity: String?
    var flowStartedAt: Date?
    var userCompletedAt: Date?
    var safeResult: WorkBuddyLoginSafeResult?
    var installState: WorkBuddyPersistedInstallState
    var warningDismissed: Bool

    init(
        schemaVersion: Int = currentSchemaVersion,
        accountMode: WorkBuddyLoginAccountMode = .personal,
        privacyConfirmedAt: Date? = nil,
        officialInstallConfirmedAt: Date? = nil,
        officialInstallIdentity: String? = nil,
        flowStartedAt: Date? = nil,
        userCompletedAt: Date? = nil,
        safeResult: WorkBuddyLoginSafeResult? = nil,
        installState: WorkBuddyPersistedInstallState = .unknown,
        warningDismissed: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.accountMode = accountMode
        self.privacyConfirmedAt = privacyConfirmedAt
        self.officialInstallConfirmedAt = officialInstallConfirmedAt
        self.officialInstallIdentity = officialInstallIdentity
        self.flowStartedAt = flowStartedAt
        self.userCompletedAt = userCompletedAt
        self.safeResult = safeResult
        self.installState = installState
        self.warningDismissed = warningDismissed
    }
}
