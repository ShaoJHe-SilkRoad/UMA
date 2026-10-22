import Testing
@testable import CodexUsageUI

struct M1AG2DBGP1UsabilityTests {
    @Test
    func compactHeaderPreservesLocalizedTitlePriority() {
        #expect(UsagePanelMetrics.width == 370)
        #expect(UsagePanelHeaderLayout.titleMinimumScaleFactor == 0.72)
        #expect(UsagePanelHeaderLayout.titleLayoutPriority == 1)
        // One product name in both languages, and it is AUV.
        #expect(AppLanguage.english.appTitle == "AUV")
        #expect(AppLanguage.simplifiedChinese.appTitle == "AUV")
    }

    @Test
    func retainedSnapshotAuthorizationKeepsVisibleDataAndCheckAgainRoute() {
        let presentation = CodexConnectionPresentation.make(
            state: .authorizationRequired,
            decision: .granted,
            hasPriorRealSnapshot: true,
            language: .english
        )
        let recovery = RetainedSnapshotRecoveryPresentation(
            presentation: presentation,
            language: .english
        )

        #expect(presentation.showsRealData)
        #expect(recovery?.primaryAction?.action == .checkLocalSession)
        #expect(recovery?.secondaryAction?.action == .cancelLocalSessionReconciliation)
    }

    @Test
    func retainedSnapshotStaleFailureExposesRetryDisconnectAndSafeDetail() {
        let presentation = CodexConnectionPresentation.make(
            state: .staleWithPreviousRealData(.requestTimedOut(method: "account/usage/read")),
            decision: .granted,
            hasPriorRealSnapshot: true,
            language: .english
        )
        let recovery = RetainedSnapshotRecoveryPresentation(
            presentation: presentation,
            language: .english
        )

        #expect(presentation.showsRealData)
        #expect(recovery?.primaryAction?.action == .retry)
        #expect(recovery?.secondaryAction?.action == .disconnect)
        #expect(recovery?.statusText.contains("request-timeout") == true)
    }

    @Test
    func readyDataDoesNotAddARecoveryControl() {
        let presentation = CodexConnectionPresentation.make(
            state: .ready,
            decision: .granted,
            hasPriorRealSnapshot: true,
            language: .english
        )

        #expect(RetainedSnapshotRecoveryPresentation(presentation: presentation, language: .english) == nil)
    }
}
