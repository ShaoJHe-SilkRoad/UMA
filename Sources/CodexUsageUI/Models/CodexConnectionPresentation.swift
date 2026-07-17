import Foundation

struct CodexFailureCopy: Equatable {
    let title: String
    let body: String
    let detail: String
    let canRetry: Bool
}

enum CodexConnectionAction: Hashable {
    case connect, notNow
    case checkLocalSession, cancelLocalSessionReconciliation
    case retry, disconnect, reconnect, openCodex, updateCodex, dismiss
}

struct CodexPresentedAction: Equatable {
    let title: String
    let action: CodexConnectionAction
}

struct CodexConnectionPresentation: Equatable {
    let title: String
    let body: String
    let showsProgress: Bool
    let primaryAction: CodexPresentedAction?
    let secondaryAction: CodexPresentedAction?
    let tertiaryAction: CodexPresentedAction?
    let showsRealData: Bool
    let freshnessText: String?
    let technicalDetail: String?
    let accessibilityAnnouncement: String

    init(
        title: String,
        body: String,
        showsProgress: Bool,
        primaryAction: CodexPresentedAction?,
        secondaryAction: CodexPresentedAction?,
        tertiaryAction: CodexPresentedAction? = nil,
        showsRealData: Bool,
        freshnessText: String?,
        technicalDetail: String?,
        accessibilityAnnouncement: String
    ) {
        self.title = title
        self.body = body
        self.showsProgress = showsProgress
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.tertiaryAction = tertiaryAction
        self.showsRealData = showsRealData
        self.freshnessText = freshnessText
        self.technicalDetail = technicalDetail
        self.accessibilityAnnouncement = accessibilityAnnouncement
    }

    static func make(
        state: CodexConnectionState,
        decision: CodexMonitorConsentDecision,
        hasPriorRealSnapshot: Bool,
        language: AppLanguage
    ) -> Self {
        if state == .notAuthorizedByMonitor || decision != .granted {
            return Self(
                title: language.connectionConsentTitle,
                body: language.connectionConsentBody,
                showsProgress: false,
                primaryAction: .init(title: language.connectionConnect, action: .connect),
                secondaryAction: .init(title: language.connectionNotNow, action: .notNow),
                showsRealData: false,
                freshnessText: nil,
                technicalDetail: nil,
                accessibilityAnnouncement: language.connectionConsentAnnouncement
            )
        }

        switch state {
        case .idle:
            return bridge(
                language.connectionReconnectTitle,
                language.connectionDisconnectNote,
                progress: false,
                action: .init(title: language.connectionReconnect, action: .reconnect),
                announcement: language.connectionReconnectAnnouncement
            )
        case .resolvingExecutable:
            return bridge(language.connectionLocatingTitle, language.connectionLocatingBody, progress: true)
        case .startingServer:
            return bridge(language.connectionStartingTitle, language.connectionStartingBody, progress: true)
        case .initializing:
            return bridge(language.connectionConnectingTitle, language.connectionConnectingBody, progress: true)
        case .checkingAccount:
            return bridge(language.connectionCheckingTitle, language.connectionCheckingBody, progress: true)
        case .accountAvailable:
            return bridge(language.connectionAccountConnectedTitle, language.connectionAccountConnectedBody, progress: true)
        case .authorizationRequired, .officialCodexSignInRequired:
            return Self(
                title: language.connectionAuthorizationRequiredTitle,
                body: language.connectionAuthorizationRequiredBody,
                showsProgress: false,
                primaryAction: .init(title: language.connectionCheckAgain, action: .checkLocalSession),
                secondaryAction: nil,
                tertiaryAction: .init(title: language.connectionCancel, action: .cancelLocalSessionReconciliation),
                // The account channel requires official CLI sign-in outside
                // this monitor. The independent This-Mac channel remains
                // available when metadata was already read.
                showsRealData: hasPriorRealSnapshot,
                freshnessText: nil,
                technicalDetail: nil,
                accessibilityAnnouncement: language.connectionAuthorizationRequiredTitle
            )
        case .loadingRateLimits:
            return bridge(language.connectionLoadingLimitsTitle, language.connectionLoadingLimitsBody, progress: true)
        case .loadingUsage:
            return bridge(language.connectionLoadingUsageTitle, language.connectionLoadingUsageBody, progress: true)
        case .loadingOptionalActivity:
            return Self(
                title: language.connectionLoadingActivityTitle,
                body: language.connectionLoadingActivityBody,
                showsProgress: true,
                primaryAction: nil,
                secondaryAction: nil,
                showsRealData: hasPriorRealSnapshot,
                freshnessText: nil,
                technicalDetail: nil,
                accessibilityAnnouncement: language.connectionLoadingActivityTitle
            )
        case .ready:
            return Self(
                title: language.appTitle,
                body: language.connectionReadyBody,
                showsProgress: false,
                primaryAction: nil,
                secondaryAction: nil,
                showsRealData: hasPriorRealSnapshot,
                freshnessText: nil,
                technicalDetail: nil,
                accessibilityAnnouncement: language.connectionReadyBody
            )
        case .refreshingWithPreviousRealData:
            return Self(
                title: language.appTitle,
                body: language.connectionRefreshingBody,
                showsProgress: true,
                primaryAction: nil,
                secondaryAction: nil,
                showsRealData: hasPriorRealSnapshot,
                freshnessText: language.connectionRefreshingTitle,
                technicalDetail: nil,
                accessibilityAnnouncement: language.connectionRefreshingTitle
            )
        case .staleWithPreviousRealData(let failure):
            let failureCopy = language.connectionFailureCopy(for: failure)
            return Self(
                title: language.appTitle,
                body: language.connectionStaleBody,
                showsProgress: false,
                primaryAction: .init(title: language.connectionRetry, action: .retry),
                secondaryAction: .init(title: language.connectionDisconnect, action: .disconnect),
                showsRealData: hasPriorRealSnapshot,
                freshnessText: language.connectionStaleTitle,
                technicalDetail: failureCopy.detail,
                accessibilityAnnouncement: language.connectionStaleAnnouncement
            )
        case .recoverableFailure(let failure), .blockedFailure(let failure):
            return failurePresentation(failure, hasPriorRealSnapshot: hasPriorRealSnapshot, language: language)
        case .notAuthorizedByMonitor:
            preconditionFailure("permission state handled before switch")
        }
    }

    private static func bridge(
        _ title: String,
        _ body: String,
        progress: Bool,
        action: CodexPresentedAction? = nil,
        announcement: String? = nil
    ) -> Self {
        Self(
            title: title,
            body: body,
            showsProgress: progress,
            primaryAction: action,
            secondaryAction: nil,
            showsRealData: false,
            freshnessText: nil,
            technicalDetail: nil,
            accessibilityAnnouncement: announcement ?? title
        )
    }

    private static func failurePresentation(
        _ failure: CodexUsageClientFailure,
        hasPriorRealSnapshot: Bool,
        language: AppLanguage
    ) -> Self {
        let copy = language.connectionFailureCopy(for: failure)
        let primary: CodexPresentedAction?
        switch failure {
        case .monitorConsentMissing:
            primary = .init(title: language.connectionConnect, action: .connect)
        case .accountAuthorizationRequired, .accountAuthorizationCanceled, .accountAuthorizationFailed:
            primary = .init(title: language.connectionCheckAgain, action: .checkLocalSession)
        default:
            primary = copy.canRetry ? .init(title: language.connectionRetry, action: .retry) : nil
        }
        return Self(
            title: copy.title,
            body: copy.body,
            showsProgress: false,
            primaryAction: primary,
            secondaryAction: .init(title: language.connectionDisconnect, action: .disconnect),
            showsRealData: hasPriorRealSnapshot,
            freshnessText: nil,
            technicalDetail: copy.detail,
            accessibilityAnnouncement: copy.title
        )
    }
}
