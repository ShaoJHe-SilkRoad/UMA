import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M5RMX Claude independent product-state matrix")
struct M5RMXClaudeProductStateMatrixTests {
    private let now = Date(timeIntervalSince1970: 1_777_777_777)

    @Test
    func machineQualificationDoesNotDependOnProviderConsentOrSitePermission() {
        let state = matrix(
            presentation: .waitingForUsagePage,
            consent: false,
            accuracy: .consentRequired
        )

        #expect(state.companionRuntime == .ready)
        #expect(state.providerConsent == .required)
        #expect(state.safariSitePermission == .unknown)
        #expect(state.providerRead == .blockedByConsent)
        #expect(!state.machineQualificationRequiresProviderConsent)
        #expect(!state.mayRequestProviderRead)
        #expect(state.appShell == .available)
    }

    @Test
    func healthyLocalEstimateDoesNotMaskProtocolMismatch() {
        let state = matrix(
            presentation: .fresh(now),
            consent: true,
            local: .estimated(now),
            accuracy: .error,
            stage: .accuracyProtocolMismatch
        )

        #expect(state.localSmart == .estimated(now))
        #expect(state.companionRuntime == .protocolMismatch)
        #expect(state.providerRead == .failed(.accuracyProtocolMismatch))
        #expect(state.appShell == .available)
    }

    @Test
    func sitePermissionIsIndependentFromConsentAndCompanionReadiness() {
        let state = matrix(
            presentation: .fresh(now),
            consent: true,
            local: .exactLocal(now),
            accuracy: .error,
            stage: .accuracyPermissionRequired
        )

        #expect(state.companionRuntime == .ready)
        #expect(state.providerConsent == .granted)
        #expect(state.safariSitePermission == .required)
        #expect(state.providerRead == .blockedBySitePermission)
        #expect(state.mayRequestProviderRead)
        #expect(!state.providerDataAccessWasProven)
    }

    @Test
    func websiteAccessLifecycleCannotBeCollapsedIntoGenericProviderFailure() {
        let state = matrix(
            presentation: .websiteAccessRequired,
            consent: true,
            local: .estimated(now),
            accuracy: .error
        )

        #expect(state.companionRuntime == .ready)
        #expect(state.safariSitePermission == .required)
        #expect(state.providerRead == .blockedBySitePermission)
        #expect(state.localSmart == .estimated(now))
        #expect(state.appShell == .available)
    }

    @Test
    func exactProviderReadProvesSitePermissionOnlyForThatRead() {
        let state = matrix(
            presentation: .fresh(now),
            consent: true,
            accuracy: .exactAnchorAvailable(now),
            stage: .accuracyExactReceived
        )

        #expect(state.companionRuntime == .ready)
        #expect(state.safariSitePermission == .provenForLatestExactRead(now))
        #expect(state.providerRead == .exact(now))
        #expect(state.providerDataAccessWasProven)
    }

    @Test
    func providerReadInFlightDoesNotImplyWebsitePermissionWasGranted() {
        let state = matrix(
            presentation: .checking,
            consent: true,
            accuracy: .syncing
        )

        #expect(state.companionRuntime == .starting)
        #expect(state.safariSitePermission == .unknown)
        #expect(state.providerRead == .inFlight)
        #expect(!state.providerDataAccessWasProven)
    }

    @Test
    func browserFailureCannotDegradeLocalSmartOrTheAppShell() {
        for stage in [
            ClaudeLiveLinkStageReason.accuracyHandshakeUnavailable,
            .accuracyCompanionUnavailable,
            .accuracyOwnedTabLost,
            .accuracyRouteRejected,
        ] {
            let state = matrix(
                presentation: .cached(now),
                consent: true,
                local: .estimated(now),
                accuracy: .error,
                stage: stage
            )

            #expect(state.localSmart == .estimated(now))
            #expect(state.appShell == .available)
        }
    }

    @Test
    func copyUsesTheIndependentCompanionAxisEvenWithFreshLocalData() {
        #expect(AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .protocolMismatch,
            accuracyState: .error
        ) == "Companion protocol mismatch.")
        #expect(AppLanguage.english.claudeCompanionRuntimeStatus(
            runtime: .ready,
            accuracyState: .consentRequired
        ) == "Companion ready · Claude consent required.")
    }

    private func matrix(
        presentation: ClaudeSettingsPresentationState,
        consent: Bool,
        local: ClaudeLocalSmartState = .unavailable,
        accuracy: ClaudeBrowserAccuracyState,
        stage: ClaudeLiveLinkStageReason? = nil
    ) -> ClaudeProductStateMatrix {
        ClaudeProductStateMatrix.classify(
            presentationState: presentation,
            consentGranted: consent,
            localSmartState: local,
            browserAccuracyState: accuracy,
            browserAccuracyStage: stage
        )
    }
}
