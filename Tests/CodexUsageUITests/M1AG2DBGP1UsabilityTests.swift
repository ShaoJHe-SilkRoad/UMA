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

    /// The consent disclosure went several releases naming the product UMA
    /// after everything else had been renamed, because every assertion on it
    /// was about what it promises rather than who is promising it. This is
    /// the missing half: the text a person reads before allowing any local
    /// reading says which product is doing the reading, and gets it right.
    @Test
    func copyThatNamesTheProductNamesAUV() {
        for language in AppLanguage.allCases {
            let disclosure = language.claudeConsentDisclosure
            #expect(disclosure.contains("AUV"))
            // A bare "UMA" is the stale name. The bundle filename and
            // identifier keep it deliberately, but they never appear here.
            #expect(!disclosure.contains("UMA"))
        }
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
