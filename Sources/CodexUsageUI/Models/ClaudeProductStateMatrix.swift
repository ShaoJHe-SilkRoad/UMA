import Foundation

/// The Claude product has independent trust and availability axes. Keeping
/// these states separate prevents a healthy Local Smart result from making a
/// failed Safari runtime look ready, or a missing provider consent from making
/// the content-free Companion qualification look unavailable.
enum ClaudeCompanionRuntimeState: Equatable, Sendable {
    case notConfigured
    case starting
    case updatePendingSafariRestart
    case ready
    case unavailable
    case protocolMismatch
}

enum ClaudeProviderConsentState: Equatable, Sendable {
    case required
    case granted
}

enum ClaudeSafariSitePermissionState: Equatable, Sendable {
    case unknown
    case required
    case provenForLatestExactRead(Date)
}

enum ClaudeProviderReadState: Equatable, Sendable {
    case idle
    case blockedByConsent
    case blockedBySitePermission
    case ready
    case inFlight
    case exact(Date)
    case failed(ClaudeLiveLinkStageReason?)
}

enum ClaudeAppShellState: Equatable, Sendable {
    case available
}

struct ClaudeProductStateMatrix: Equatable, Sendable {
    let companionRuntime: ClaudeCompanionRuntimeState
    let providerConsent: ClaudeProviderConsentState
    let safariSitePermission: ClaudeSafariSitePermissionState
    let providerRead: ClaudeProviderReadState
    let localSmart: ClaudeLocalSmartState
    let appShell: ClaudeAppShellState

    /// Content-free runtime qualification is intentionally independent from
    /// provider consent and site permission.
    var machineQualificationRequiresProviderConsent: Bool { false }

    /// A provider read request can be initiated only after consent and a
    /// qualified Companion. Safari still enforces website permission at the
    /// privileged browser boundary before page access occurs.
    var mayRequestProviderRead: Bool {
        providerConsent == .granted && companionRuntime == .ready
    }

    /// This is stricter than request admission: provider data access is proven
    /// only by a successful exact read. Unknown is never treated as granted.
    var providerDataAccessWasProven: Bool {
        if case .provenForLatestExactRead = safariSitePermission { return true }
        return false
    }

    static func classify(
        presentationState: ClaudeSettingsPresentationState,
        consentGranted: Bool,
        localSmartState: ClaudeLocalSmartState,
        browserAccuracyState: ClaudeBrowserAccuracyState,
        browserAccuracyStage: ClaudeLiveLinkStageReason?
    ) -> Self {
        let consent: ClaudeProviderConsentState = consentGranted ? .granted : .required
        return Self(
            companionRuntime: companionRuntime(
                presentationState: presentationState,
                accuracyState: browserAccuracyState,
                stage: browserAccuracyStage
            ),
            providerConsent: consent,
            safariSitePermission: sitePermission(
                presentationState: presentationState,
                accuracyState: browserAccuracyState,
                stage: browserAccuracyStage
            ),
            providerRead: providerRead(
                presentationState: presentationState,
                consent: consent,
                accuracyState: browserAccuracyState,
                stage: browserAccuracyStage
            ),
            localSmart: localSmartState,
            appShell: .available
        )
    }

    private static func companionRuntime(
        presentationState: ClaudeSettingsPresentationState,
        accuracyState: ClaudeBrowserAccuracyState,
        stage: ClaudeLiveLinkStageReason?
    ) -> ClaudeCompanionRuntimeState {
        switch stage {
        case .accuracyInventoryRestartRequired:
            return .updatePendingSafariRestart
        case .accuracyInventoryLoading, .accuracyCompanionStarting:
            return .starting
        case .accuracyProtocolMismatch:
            return .protocolMismatch
        case .accuracyHandshakeUnavailable, .accuracyCompanionUnavailable,
             .accuracyBrowserUnavailable:
            return .unavailable
        case .accuracyWorkDispatchFailed, .accuracyRequestMismatch,
             .accuracyPermissionRequired, .accuracySignInRequired,
             .accuracyRouteRejected, .accuracyUsageUnavailable,
             .accuracyTabUnavailable, .accuracyOwnedTabLost,
             .accuracyExactReceived:
            return .ready
        case .none, .localStatusLinePending, .localStatusLineRejected,
             .localActivityDetectedAwaitingExactAnchor,
             .localCodeActivityDetectedDesktopUnavailable,
             .localCallbackWithoutQuotaWindows, .localExactReceived,
             .desktopActivitySignalUnavailable:
            break
        }

        switch presentationState {
        case .inventoryRestartRequired:
            return .updatePendingSafariRestart
        case .checking, .inventoryLoading, .companionStarting:
            return .starting
        case .protocolMismatch, .companionOutdated, .nativeHostMismatched:
            return .protocolMismatch
        case .companionDisabled, .unsupportedBrowser, .browserUnavailable,
             .nativeHostMissing, .extensionNotInstalled, .companionUnavailable:
            return .unavailable
        case .disconnected:
            return accuracyState == .notConfigured ? .notConfigured : .unavailable
        case .waitingForUsagePage, .websiteAccessRequired, .signInRequired,
             .waitingForSafari, .fresh, .cached, .stale, .routeChanged, .failed:
            switch accuracyState {
            case .notConfigured:
                return .notConfigured
            case .companionUnavailable:
                return .unavailable
            case .updatePendingRestart:
                return .updatePendingSafariRestart
            case .consentRequired, .ready, .syncing, .exactAnchorAvailable, .error:
                return .ready
            }
        }
    }

    private static func sitePermission(
        presentationState: ClaudeSettingsPresentationState,
        accuracyState: ClaudeBrowserAccuracyState,
        stage: ClaudeLiveLinkStageReason?
    ) -> ClaudeSafariSitePermissionState {
        if stage == .accuracyPermissionRequired || presentationState == .websiteAccessRequired {
            return .required
        }
        if case let .exactAnchorAvailable(date) = accuracyState {
            return .provenForLatestExactRead(date)
        }
        return .unknown
    }

    private static func providerRead(
        presentationState: ClaudeSettingsPresentationState,
        consent: ClaudeProviderConsentState,
        accuracyState: ClaudeBrowserAccuracyState,
        stage: ClaudeLiveLinkStageReason?
    ) -> ClaudeProviderReadState {
        guard consent == .granted else { return .blockedByConsent }
        if stage == .accuracyPermissionRequired || presentationState == .websiteAccessRequired {
            return .blockedBySitePermission
        }
        switch accuracyState {
        case .notConfigured:
            return .idle
        case .consentRequired:
            return .blockedByConsent
        case .ready:
            return .ready
        case .companionUnavailable, .updatePendingRestart:
            return .idle
        case .syncing:
            return .inFlight
        case let .exactAnchorAvailable(date):
            return .exact(date)
        case .error:
            return .failed(stage)
        }
    }
}
