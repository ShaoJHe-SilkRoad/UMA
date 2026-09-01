import Combine
import Foundation

protocol WorkBuddyLoginEligibilityChecking: Sendable {
    func check() async -> WorkBuddyLoginSafeResult
}

struct UnsupportedWorkBuddyLoginEligibilityChecker:
    WorkBuddyLoginEligibilityChecking {
    func check() async -> WorkBuddyLoginSafeResult {
        .unsupportedLocalCreditsSource
    }
}

@MainActor
public final class WorkBuddyLoginCoordinator: ObservableObject {
    @Published public private(set) var installation: WorkBuddyInstallationStatus
    @Published public private(set) var flowState: WorkBuddyLoginFlowState = .idle
    @Published public private(set) var privacyConfirmed: Bool
    @Published public private(set) var officialInstallConfirmed: Bool
    @Published public private(set) var safeResult: WorkBuddyLoginSafeResult?
    @Published public private(set) var completedEligibilityCheckCount = 0
    @Published public var accountMode: WorkBuddyLoginAccountMode {
        didSet {
            guard accountMode != oldValue else { return }
            record.accountMode = accountMode
            persist()
        }
    }

    public var flowWasLaunched: Bool { record.flowStartedAt != nil }
    public var userConfirmedCompleted: Bool { record.userCompletedAt != nil }
    public var machineVerifiedAuthentication: Bool { false }
    public var canOpenOfficialApplication: Bool {
        canOpen && flowState != .opening
    }

    private let applicationAccess: any WorkBuddyApplicationAccessing
    private let persistence: any WorkBuddyLoginPersistenceStoring
    private let eligibilityChecker: any WorkBuddyLoginEligibilityChecking
    private let now: @Sendable () -> Date
    private let timeout: Duration
    private let timeoutSleeper:
        @Sendable (Duration) async throws -> Void
    private var record: WorkBuddyLoginPersistenceRecord
    private var lifecycleObserver: NSObjectProtocol?
    private var timeoutTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?

    init(
        applicationAccess: any WorkBuddyApplicationAccessing,
        persistence: any WorkBuddyLoginPersistenceStoring,
        eligibilityChecker: any WorkBuddyLoginEligibilityChecking =
            UnsupportedWorkBuddyLoginEligibilityChecker(),
        timeout: Duration = .seconds(600),
        timeoutSleeper: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.applicationAccess = applicationAccess
        self.persistence = persistence
        self.eligibilityChecker = eligibilityChecker
        self.timeout = timeout
        self.timeoutSleeper = timeoutSleeper
        self.now = now
        let restored = persistence.load() ?? WorkBuddyLoginPersistenceRecord()
        let discoveredInstallation = applicationAccess.discover()
        record = restored
        accountMode = restored.accountMode
        privacyConfirmed = restored.privacyConfirmedAt != nil
        officialInstallConfirmed = Self.confirmationIsBound(
            record: restored,
            installation: discoveredInstallation
        )
        safeResult = restored.safeResult
        installation = discoveredInstallation
        if !officialInstallConfirmed {
            record.officialInstallConfirmedAt = nil
            record.officialInstallIdentity = nil
            record.warningDismissed = false
        }
        record.installState = installation.persistedState
        persistence.save(record)
        lifecycleObserver = applicationAccess.observeLifecycle { [weak self] in
            self?.refreshInstallation()
        }
    }

    public convenience init() {
        self.init(defaults: .standard)
    }

    convenience init(defaults: UserDefaults) {
        self.init(
            applicationAccess: WorkBuddyApplicationAccess(),
            persistence: WorkBuddyLoginPersistenceStore(defaults: defaults)
        )
    }

    public static func preview(
        signatureTrust: WorkBuddySignatureTrust = .trusted
    ) -> WorkBuddyLoginCoordinator {
        let coordinator = WorkBuddyLoginCoordinator(
            applicationAccess: WorkBuddyLoginPreviewApplicationAccess(
                signatureTrust: signatureTrust
            ),
            persistence: WorkBuddyLoginPreviewPersistenceStore()
        )
        coordinator.startLogin()
        return coordinator
    }

    public func startLogin() {
        refreshInstallation()
        switch installation {
        case .notInstalled:
            flowState = .failed(.applicationNotInstalled)
        case .invalidBundleIdentity:
            flowState = .failed(.invalidBundleIdentity)
        case .available:
            flowState = canOpen ? .readyToOpen : .confirmationRequired
        }
    }

    public func setPrivacyConfirmed(_ isConfirmed: Bool) {
        privacyConfirmed = isConfirmed
        record.privacyConfirmedAt = isConfirmed ? now() : nil
        updateReadyState()
        persist()
    }

    public func setOfficialInstallConfirmed(_ isConfirmed: Bool) {
        let application = installation.application
        let canConfirm = application?.signatureTrust
            .requiresOfficialInstallConfirmation == true
        officialInstallConfirmed = isConfirmed && canConfirm
        record.officialInstallConfirmedAt =
            officialInstallConfirmed ? now() : nil
        record.officialInstallIdentity =
            officialInstallConfirmed ? application?.installationIdentity : nil
        record.warningDismissed = officialInstallConfirmed
        updateReadyState()
        persist()
    }

    public func openOfficialApplication() {
        guard checkTask == nil else { return }
        guard let application = installation.application else {
            startLogin()
            return
        }
        guard privacyConfirmed else {
            flowState = .failed(.privacyConfirmationRequired)
            return
        }
        guard application.signatureTrust == .trusted
                || confirmationIsBound(to: application)
        else {
            flowState = .failed(.officialInstallConfirmationRequired)
            return
        }
        guard flowState != .opening else { return }
        flowState = .opening
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await applicationAccess.openOrActivate(application)
            switch result {
            case .launched, .activated:
                record.flowStartedAt = now()
                record.safeResult = .flowLaunched
                safeResult = .flowLaunched
                flowState = .awaitingUserCompletion
                persist()
                beginTimeout()
            case .denied:
                flowState = .failed(.launchDenied)
            case .failed:
                flowState = .failed(.launchFailed)
            }
        }
    }

    public func checkAgain() {
        guard checkTask == nil else { return }
        guard flowState == .awaitingUserCompletion || flowState == .completed
        else {
            return
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        flowState = .checking
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await eligibilityChecker.check()
            completedEligibilityCheckCount += 1
            record.userCompletedAt = now()
            record.safeResult = result
            safeResult = result
            flowState = .completed
            persist()
            checkTask = nil
        }
        checkTask = task
    }

    public func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        checkTask?.cancel()
        checkTask = nil
        flowState = .cancelled
    }

    public func refreshInstallation() {
        installation = applicationAccess.discover()
        if !Self.confirmationIsBound(
            record: record,
            installation: installation
        ) {
            officialInstallConfirmed = false
            record.officialInstallConfirmedAt = nil
            record.officialInstallIdentity = nil
            record.warningDismissed = false
        }
        record.installState = installation.persistedState
        persist()
    }

    public func tearDown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        checkTask?.cancel()
        checkTask = nil
        if let lifecycleObserver {
            applicationAccess.removeLifecycleObserver(lifecycleObserver)
            self.lifecycleObserver = nil
        }
    }

    private var canOpen: Bool {
        guard privacyConfirmed,
              let application = installation.application
        else {
            return false
        }
        return application.signatureTrust == .trusted
            || confirmationIsBound(to: application)
    }

    private func confirmationIsBound(
        to application: WorkBuddyInstalledApplication
    ) -> Bool {
        officialInstallConfirmed
            && application.signatureTrust.requiresOfficialInstallConfirmation
            && record.officialInstallConfirmedAt != nil
            && record.officialInstallIdentity == application.installationIdentity
    }

    private static func confirmationIsBound(
        record: WorkBuddyLoginPersistenceRecord,
        installation: WorkBuddyInstallationStatus
    ) -> Bool {
        guard let application = installation.application else { return false }
        return application.signatureTrust.requiresOfficialInstallConfirmation
            && record.officialInstallConfirmedAt != nil
            && record.officialInstallIdentity == application.installationIdentity
    }

    private func updateReadyState() {
        guard flowState == .confirmationRequired
                || flowState == .readyToOpen
                || {
                    if case .failed(.privacyConfirmationRequired) = flowState {
                        return true
                    }
                    if case .failed(.officialInstallConfirmationRequired) = flowState {
                        return true
                    }
                    return false
                }()
        else {
            return
        }
        flowState = canOpen ? .readyToOpen : .confirmationRequired
    }

    private func beginTimeout() {
        timeoutTask?.cancel()
        let timeout = timeout
        let timeoutSleeper = timeoutSleeper
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await timeoutSleeper(timeout)
            } catch {
                return
            }
            guard let self, flowState == .awaitingUserCompletion else { return }
            flowState = .failed(.timedOut)
            timeoutTask = nil
        }
    }

    private func persist() {
        persistence.save(record)
    }
}

@MainActor
private final class WorkBuddyLoginPreviewPersistenceStore:
    WorkBuddyLoginPersistenceStoring {
    private var record: WorkBuddyLoginPersistenceRecord?

    func load() -> WorkBuddyLoginPersistenceRecord? { record }
    func save(_ record: WorkBuddyLoginPersistenceRecord) {
        self.record = record
    }
}

@MainActor
private final class WorkBuddyLoginPreviewApplicationAccess:
    WorkBuddyApplicationAccessing {
    private let status: WorkBuddyInstallationStatus

    init(signatureTrust: WorkBuddySignatureTrust) {
        status = .available(
            WorkBuddyInstalledApplication(
                url: WorkBuddyApplicationAccess.fallbackURL,
                bundleIdentifier:
                    WorkBuddyApplicationAccess.expectedBundleIdentifier,
                displayName: "WorkBuddy",
                version: "5.3.5",
                build: "5.3.5",
                signatureTrust: signatureTrust,
                installationIdentity: "preview-workbuddy-5.3.5"
            )
        )
    }

    func discover() -> WorkBuddyInstallationStatus { status }

    func openOrActivate(
        _ application: WorkBuddyInstalledApplication
    ) async -> WorkBuddyApplicationLaunchResult {
        .launched
    }

    func observeLifecycle(
        _ action: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NSObject()
    }

    func removeLifecycleObserver(_ observer: NSObjectProtocol) {}
}
