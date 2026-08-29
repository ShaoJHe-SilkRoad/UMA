import Foundation
import JavaScriptCore
import Testing

@Suite("M5RMX owned provider tab V2 adversarial lifecycle")
struct M5RMXOwnedProviderTabV2Tests {
    private let request = V2Request(
        requestID: "7a7f5e38-70bf-4b1b-81b0-e0903081f981",
        generation: "6e6f5e38-70bf-4b1b-81b0-e0903081f980",
        nonce: "9c9f5e38-70bf-4b1b-81b0-e0903081f983"
    )

    @Test
    func oldModelFailsOnBootstrapSelfNavigationWhileV2EliminatesTheHandoff() {
        var old = RetiredBootstrapModel()
        old.refreshStarted()
        old.saveReceipt()
        old.activateBootstrap(tabID: 91)
        old.onRemoved(tabID: 91)

        #expect(old.events == [
            "refreshStarted", "receiptSaved", "receiptActivated",
            "receiptRemoved", "tabUnavailable",
        ])
        #expect(!old.receiptExists)
        #expect(!old.providerReady)

        var v2Success = OwnedProviderTabV2Model(request: request)
        v2Success.persistIntent()
        v2Success.beginProviderCreation()
        v2Success.providerCreateReturned(tabID: 91)
        v2Success.discover(validAnnouncement(tabID: 91))
        v2Success.proveDiscoveredProvider()
        v2Success.providerReady(tabID: 91)
        v2Success.beginExtraction()

        #expect(v2Success.state == .extracting)
        #expect(v2Success.authoritativeProviderTabID == 91)
        #expect(v2Success.extractionCount == 1)
        #expect(v2Success.closedTabIDs.isEmpty)

        // This is the permanent regression for the exact Safari event that
        // retired the old extension bootstrap during cross-origin navigation.
        // V2 has no bootstrap-to-provider handoff. If the exact direct-created
        // candidate disappears before provider proof, it fails safely and may
        // neither adopt a different tab nor close any unproven tab.
        var v2Failure = OwnedProviderTabV2Model(request: request)
        v2Failure.persistIntent()
        v2Failure.beginProviderCreation()
        v2Failure.providerCreateReturned(tabID: 92)
        v2Failure.onRemoved(tabID: 92)
        v2Failure.discover(validAnnouncement(tabID: 93))
        v2Failure.proveDiscoveredProvider()
        v2Failure.providerReady(tabID: 93)
        v2Failure.beginExtraction()

        #expect(v2Failure.state == .failed)
        #expect(v2Failure.failureReason == "UNPROVEN_PROVIDER_CANDIDATE_REMOVED")
        #expect(v2Failure.authoritativeProviderTabID == nil)
        #expect(v2Failure.closedTabIDs.isEmpty)
        #expect(v2Failure.extractionCount == 0)
        #expect(v2Failure.generalEnumerationCount == 0)
    }

    @Test
    func directProviderProofMayArriveBeforeOrAfterTabsCreateCompletion() {
        for proofFirst in [true, false] {
            var model = OwnedProviderTabV2Model(request: request)
            model.persistIntent()
            model.beginProviderCreation()

            if proofFirst {
                model.discover(validAnnouncement(tabID: 41))
                model.proveDiscoveredProvider()
                #expect(model.authoritativeProviderTabID == nil)
                model.providerCreateReturned(tabID: 41)
                model.discover(validAnnouncement(tabID: 41))
                model.proveDiscoveredProvider()
            } else {
                model.providerCreateReturned(tabID: 41)
                model.discover(validAnnouncement(tabID: 41))
                model.proveDiscoveredProvider()
            }

            model.providerReady(tabID: 41)
            model.beginExtraction()

            #expect(model.state == .extracting)
            #expect(model.authoritativeProviderTabID == 41)
            #expect(model.extractionCount == 1)
            #expect(model.closedTabIDs.isEmpty)
        }
    }

    @Test
    func oldDeferredMarkerRemovalLosesTheProviderRouteWhileV2SanitizesAtDocumentStart() {
        var old = ProviderRouteMarkerRaceModel(removalTiming: .afterNativeOwnership)
        old.documentStarted()
        old.providerRouterNormalizedUnknownHash()
        old.nativeOwnershipAccepted()

        #expect(old.route == .providerDefault)
        #expect(old.failureReason == "PROVIDER_ROUTE_MARKER_LOST")
        #expect(!old.providerReady)

        var v2 = ProviderRouteMarkerRaceModel(removalTiming: .atDocumentStart)
        v2.documentStarted()
        v2.providerRouterNormalizedUnknownHash()
        v2.nativeOwnershipAccepted()

        #expect(v2.route == .usage)
        #expect(v2.failureReason == nil)
        #expect(v2.providerReady)
        #expect(v2.nonceRetainedOnlyInIsolatedMemory)
        #expect(!v2.markerVisibleInLocation)
    }

    @Test
    func transientProviderRoutingNeverReadsDOMAndCanReturnToTheExactUsageRoute() {
        var old = ProviderRouteReadinessModel(oldImmediateRouteRejection: true)
        old.beginExtraction()
        old.observeExactUsageWithoutLandmarks()
        old.observeTransientProviderRoute()
        #expect(old.terminalStatus == "routeRejected")

        var model = ProviderRouteReadinessModel()
        model.beginExtraction()
        model.observeExactUsageWithoutLandmarks()
        model.observeTransientProviderRoute()

        #expect(model.domInspectionCount == 1)
        #expect(model.terminalStatus == nil)

        model.observeExactUsageWithLandmarks()

        #expect(model.domInspectionCount == 2)
        #expect(model.successObservationCount == 0)
        #expect(model.terminalStatus == nil)

        model.observeExactUsageWithLandmarks()
        model.observeExactUsageWithLandmarks()

        #expect(model.domInspectionCount == 3)
        #expect(model.successObservationCount == 1)
        #expect(model.terminalStatus == "success")

        var expired = ProviderRouteReadinessModel()
        expired.beginExtraction()
        expired.observeTransientProviderRoute()
        expired.expireWhileRouteIsTransient()

        #expect(expired.domInspectionCount == 0)
        #expect(expired.successObservationCount == 0)
        #expect(expired.terminalStatus == "routeRejected")
    }

    @Test
    func readinessRequiresStableSuccessAndRepeatedLoginButDeliversOnlyOnce() {
        var model = ProviderRouteReadinessModel()
        model.beginExtraction()
        model.observeTransientLoginLandmark()
        #expect(model.terminalStatus == nil)
        model.observeExactUsageWithoutLandmarks()
        model.observeTransientLoginLandmark()
        model.observeTransientLoginLandmark()
        #expect(model.terminalStatus == "signInRequired")

        var success = ProviderRouteReadinessModel()
        success.beginExtraction()
        success.beginExtraction()
        success.observeExactUsageWithLandmarks()
        success.observeExactUsageWithLandmarks()
        success.observeExactUsageWithLandmarks()
        #expect(success.successObservationCount == 1)
        #expect(success.deliveryCount == 1)
        #expect(success.extractionStartCount == 1)

        var transientLoginThenSuccess = ProviderRouteReadinessModel()
        transientLoginThenSuccess.beginExtraction()
        transientLoginThenSuccess.observeTransientLoginLandmark()
        transientLoginThenSuccess.observeExactUsageWithLandmarks()
        transientLoginThenSuccess.observeExactUsageWithLandmarks()
        #expect(transientLoginThenSuccess.terminalStatus == "success")
    }

    @Test
    func productionContentScriptSPAEventTraceReadsOnlyExactReadyDocumentAndDeliversOnce() throws {
        let content = try String(
            contentsOf: v2RepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/content-script.js"
            ),
            encoding: .utf8
        )
        let context = try #require(JSContext())
        context.exceptionHandler = { _, exception in
            Issue.record("JavaScript exception: \(exception?.toString() ?? "unknown")")
        }
        context.evaluateScript(#"""
          var route = "exact", dataReady = false, domReads = 0, connectCount = 0;
          var portMessageHandler = null, disconnectHandler = null, mutationHandler = null, rafHandler = null;
          var listeners = {}, outbound = [];
          var location = {href:"https://claude.ai/new#settings/usage", protocol:"https:", origin:"https://claude.ai", pathname:"/new", search:"", hash:"#settings/usage"};
          var history = {};
          var document = {
            readyState: "complete", documentElement: {},
            addEventListener:function(n,f){listeners["doc:"+n]=f;},
            removeEventListener:function(n,f){delete listeners["doc:"+n];}
          };
          function MutationObserver(callback){ mutationHandler=callback; this.observe=function(){}; this.disconnect=function(){}; }
          function setTimeout(callback){ listeners.timeout=callback; return 1; }
          function clearTimeout(){ delete listeners.timeout; }
          function requestAnimationFrame(callback){ rafHandler=callback; return 7; }
          function cancelAnimationFrame(){ rafHandler=null; }
          function queueMicrotask(callback){ callback(); }
          globalThis.addEventListener=function(n,f){listeners[n]=f;};
          globalThis.removeEventListener=function(n,f){delete listeners[n];};
          globalThis.UMAProviderOwnershipV2={parseProviderMarker:function(){return "n";},finalizeProviderRoute:function(){return true;}};
          globalThis.UMAClaudeUsageExtractor={
            CONTRACT:{origin:"https://claude.ai",href:"https://claude.ai/new#settings/usage"},
            FAILURE_REASONS:{providerStructureUnsupported:"PROVIDER_STRUCTURE_UNSUPPORTED"},
            exactUsageURL:function(){return route === "exact";},
            usageRouteState:function(){return route === "exact" ? "exact" : "providerRoutePending";},
            extractResult:function(){
              domReads += 1;
              return dataReady ? {status:"success",observation:{fiveHour:{usedPercentage:25,resetAt:null},weeklyAllModels:null,modelSpecificWeekly:null,observedAt:"2026-08-28T00:00:00.000Z",extractorSchemaVersion:2,sourceLayoutVersion:1}} : {status:"usageUnavailable",reasonCode:"TARGET_DATA_NOT_READY"};
            }
          };
          var port={
            onMessage:{addListener:function(f){portMessageHandler=f;}},
            onDisconnect:{addListener:function(f){disconnectHandler=f;}},
            postMessage:function(m){outbound.push(m);}, disconnect:function(){}
          };
          globalThis.browser={runtime:{getManifest:function(){return {manifest_version:2};},connect:function(){connectCount += 1; return port;},onMessage:{addListener:function(){}}}};
        """#)
        context.evaluateScript(content)
        context.evaluateScript(#"""
          portMessageHandler({type:"umaClaudeProviderOwnershipAcceptedV2",requestID:"r",runtimeGenerationID:"g"});
          portMessageHandler({type:"umaClaudeExtractProviderUsageV2",requestID:"r",runtimeGenerationID:"g"});
          route="pending"; listeners.hashchange();
          var readsWhilePending=domReads;
          route="exact"; dataReady=true; listeners.hashchange();
          var finalRenderTurn=rafHandler; finalRenderTurn();
          mutationHandler();
          portMessageHandler({type:"umaClaudeExtractProviderUsageV2",requestID:"r",runtimeGenerationID:"g"});
          var deliveredBeforeDisconnect=outbound.filter(function(m){return m.type==="umaClaudeProviderResultV2";}).length;
          var firstDisconnect=disconnectHandler; firstDisconnect();
          portMessageHandler({type:"umaClaudeProviderOwnershipAcceptedV2",requestID:"r",runtimeGenerationID:"g"});
          var deliveredAfterRecovery=outbound.filter(function(m){return m.type==="umaClaudeProviderResultV2";}).length;
          var secondDisconnect=disconnectHandler; secondDisconnect();
          portMessageHandler({type:"umaClaudeProviderOwnershipAcceptedV2",requestID:"r",runtimeGenerationID:"g"});
          var deliveredAfterSecondDisconnect=outbound.filter(function(m){return m.type==="umaClaudeProviderResultV2";}).length;
          var terminalResultCount=outbound.filter(function(m){return m.type==="umaClaudeProviderTerminalV2";}).length;
        """#)
        #expect(context.exception == nil)
        #expect(context.evaluateScript("readsWhilePending")?.toInt32() == 1)
        #expect(context.evaluateScript("domReads")?.toInt32() == 3)
        #expect(context.evaluateScript("deliveredBeforeDisconnect")?.toInt32() == 1)
        #expect(context.evaluateScript("deliveredAfterRecovery")?.toInt32() == 2)
        #expect(context.evaluateScript("deliveredAfterSecondDisconnect")?.toInt32() == 2)
        #expect(context.evaluateScript("connectCount")?.toInt32() == 2)
        #expect(context.evaluateScript("terminalResultCount")?.toInt32() == 0)
    }

    @Test
    func providerFailureTaxonomyIsAllowlistedAndCleanupFailureDominates() throws {
        let root = v2RepositoryRoot()
        let content = try String(
            contentsOf: root.appendingPathComponent(
                "BrowserExtension/Shared/content-script.js"
            ),
            encoding: .utf8
        )
        let background = try String(
            contentsOf: root.appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )
        let allowed = [
            "ROUTE_NOT_READY", "ROUTE_READINESS_TIMEOUT",
            "PROVIDER_DOCUMENT_NOT_READY", "TARGET_DATA_NOT_READY",
            "TARGET_DATA_TIMEOUT", "PROVIDER_STRUCTURE_UNSUPPORTED",
            "PROVIDER_SESSION_UNAVAILABLE", "SITE_PERMISSION_MISSING",
            "EXTRACTION_VALIDATION_FAILED", "REQUEST_CANCELLED",
            "PROVIDER_TAB_CLOSED",
        ]
        for reason in allowed {
            #expect(content.contains("\"\(reason)\""))
            #expect(background.contains("\"\(reason)\""))
        }
        #expect(content.contains("providerFailureReason: result.providerFailureReason"))
        #expect(background.contains(
            "[\"providerFailureReason\", \"requestID\", \"runtimeGenerationID\", \"status\", \"type\"]"
        ))
        #expect(background.contains(
            "!providerFailureReasons.has(message.providerFailureReason)"
        ))
        #expect(background.contains("retainedProviderFailureReason = null"))
        #expect(background.contains("finalStatus = \"ownedTabOwnershipLost\""))
        #expect(!background.contains("failureReasonCode"))
    }

    @Test
    func everyCreateProofReadyOrderingRequiresFreshProofAndReadyBeforeExtraction() {
        let events: [V2OrderingEvent] = [.createReturned, .proof, .ready]
        for ordering in permutations(of: events) {
            var model = OwnedProviderTabV2Model(request: request)
            model.persistIntent()
            model.beginProviderCreation()

            for event in ordering {
                switch event {
                case .createReturned:
                    model.providerCreateReturned(tabID: 52)
                case .proof:
                    model.discover(validAnnouncement(tabID: 52))
                    model.proveDiscoveredProvider()
                case .ready:
                    model.providerReady(tabID: 52)
                }
                model.beginExtraction()
                if model.extractionCount > 0 {
                    #expect(model.state == .extracting)
                    #expect(model.authoritativeProviderTabID == 52)
                }
            }

            if model.extractionCount == 0 {
                model.discover(validAnnouncement(tabID: 52))
                model.proveDiscoveredProvider()
                model.providerReady(tabID: 52)
                model.beginExtraction()
            }

            #expect(model.extractionCount == 1)
            #expect(model.generalEnumerationCount == 0)
            #expect(model.closedTabIDs.isEmpty)
        }
    }

    @Test
    func backgroundCrashRecoversOnlyFromAReprovenTrustedProviderSender() {
        var model = OwnedProviderTabV2Model(request: request)
        model.persistIntent()
        model.beginProviderCreation()
        model.providerCreateReturned(tabID: 63)
        model.discover(validAnnouncement(tabID: 63))
        model.proveDiscoveredProvider()

        model.backgroundCrashedAndReloaded()
        model.providerReady(tabID: 63)
        model.beginExtraction()
        #expect(model.extractionCount == 0)
        #expect(model.receiptExists)

        model.recoverFromChallenge(validAnnouncement(tabID: 63))
        model.providerReady(tabID: 63)
        model.beginExtraction()

        #expect(model.extractionCount == 1)
        #expect(model.authoritativeProviderTabID == 63)
        #expect(model.generalEnumerationCount == 0)
    }

    @Test
    func onReplacedNeverTransfersOwnershipWithoutNewSenderProof() {
        for announcementBeforeReplacement in [true, false] {
            var model = provenModel(tabID: 71)
            let replacement = validAnnouncement(tabID: 72)

            if announcementBeforeReplacement {
                model.discover(replacement)
                model.proveDiscoveredProvider()
            }
            model.onReplaced(removedTabID: 71, addedTabID: 72)

            model.providerReady(tabID: 72)
            model.beginExtraction()
            #expect(model.extractionCount == 0)
            #expect(model.authoritativeProviderTabID == nil)
            #expect(model.closedTabIDs.isEmpty)

            model.discover(replacement)
            model.proveDiscoveredProvider()
            model.providerReady(tabID: 72)
            model.beginExtraction()

            #expect(model.extractionCount == 1)
            #expect(model.authoritativeProviderTabID == 72)
            #expect(model.closedTabIDs.isEmpty)
        }
    }

    @Test
    func trustedSenderMetadataOutranksCallerSuppliedTabIdentity() {
        var model = OwnedProviderTabV2Model(request: request)
        model.persistIntent()
        model.beginProviderCreation()
        model.providerCreateReturned(tabID: 81)

        var spoof = validAnnouncement(tabID: 82)
        spoof.callerSuppliedTabID = 81
        spoof.trustedExtensionSender = false
        model.discover(spoof)
        model.proveDiscoveredProvider()

        #expect(model.state == .providerCreationPending)
        #expect(model.authoritativeProviderTabID == nil)
        #expect(model.extractionCount == 0)
        #expect(model.closedTabIDs.isEmpty)

        model.discover(validAnnouncement(tabID: 81))
        model.proveDiscoveredProvider()
        #expect(model.authoritativeProviderTabID == 81)
    }

    @Test(arguments: [
        AnnouncementDefect.wrongRequest,
        .wrongGeneration,
        .wrongNonce,
        .untrustedSender,
        .subframe,
        .wrongOrigin,
    ])
    fileprivate func malformedOrUntrustedProviderAnnouncementsCannotMutateOwnership(
        _ defect: AnnouncementDefect
    ) {
        var model = OwnedProviderTabV2Model(request: request)
        model.persistIntent()
        model.beginProviderCreation()
        model.providerCreateReturned(tabID: 90)
        model.discover(defectiveAnnouncement(defect, tabID: 90))
        model.proveDiscoveredProvider()
        model.providerReady(tabID: 90)
        model.beginExtraction()
        model.requestCleanup()

        #expect(model.state == .providerCreationPending)
        #expect(model.authoritativeProviderTabID == nil)
        #expect(model.extractionCount == 0)
        #expect(model.cleanupRequestCount == 0)
        #expect(model.closedTabIDs.isEmpty)
    }

    @Test
    func userCloseNeverBecomesAnExtensionCloseAndCannotResurrectTheRequest() {
        var model = provenModel(tabID: 101)
        model.onRemoved(tabID: 101)

        #expect(model.state == .failed)
        #expect(model.closedTabIDs.isEmpty)
        #expect(model.failureReason == "OWNED_PROVIDER_TAB_REMOVED")

        model.discover(validAnnouncement(tabID: 101))
        model.proveDiscoveredProvider()
        model.providerReady(tabID: 101)
        model.beginExtraction()
        model.requestCleanup()

        #expect(model.state == .failed)
        #expect(model.extractionCount == 0)
        #expect(model.cleanupRequestCount == 0)
        #expect(model.closedTabIDs.isEmpty)
    }

    @Test
    func duplicateMessagesAreIdempotentAndCleanupClosesAtMostOnce() {
        var model = provenModel(tabID: 111)
        model.discover(validAnnouncement(tabID: 111))
        model.proveDiscoveredProvider()
        model.providerReady(tabID: 111)
        model.providerReady(tabID: 111)
        model.beginExtraction()
        model.beginExtraction()
        model.resultReady()
        model.resultReady()
        model.resultDelivered()
        model.resultDelivered()
        model.requestCleanup()
        model.requestCleanup()

        #expect(model.extractionCount == 1)
        #expect(model.cleanupRequestCount == 1)
        #expect(model.closedTabIDs == [111])

        model.cleanupConfirmed()
        model.cleanupConfirmed()
        model.requestCleanup()

        #expect(model.state == .complete)
        #expect(model.cleanupRequestCount == 1)
        #expect(model.closedTabIDs == [111])
        #expect(!model.receiptExists)
    }

    @Test
    func staleGenerationCannotMutateARequestOrCloseItsTab() {
        var model = provenModel(tabID: 121)
        var stale = validAnnouncement(tabID: 122)
        stale.generation = "bd9f5e38-70bf-4b1b-81b0-e0903081f985"

        model.discover(stale)
        model.proveDiscoveredProvider()
        model.providerReady(tabID: 122)
        model.beginExtraction()

        #expect(model.authoritativeProviderTabID == 121)
        #expect(model.extractionCount == 0)
        #expect(model.closedTabIDs.isEmpty)
    }

    @Test
    func permissionDenialAndNavigationRejectionFailClosedWithoutEnumerationOrUnprovenClose() {
        for failure in [V2PreProofFailure.permissionDenied, .navigationRejected] {
            var model = OwnedProviderTabV2Model(request: request)
            model.persistIntent()
            model.beginProviderCreation()
            model.providerCreateReturned(tabID: 131)
            switch failure {
            case .permissionDenied: model.permissionDenied()
            case .navigationRejected: model.navigationRejected()
            }

            #expect(model.state == .failed)
            #expect(model.extractionCount == 0)
            #expect(model.closedTabIDs.isEmpty)
            #expect(model.generalEnumerationCount == 0)
        }
    }

    @Test
    func completeLifecycleVisitsTheExplicitV2ReducerStatesInOrder() {
        var model = OwnedProviderTabV2Model(request: request)
        model.persistIntent()
        model.beginProviderCreation()
        model.providerCreateReturned(tabID: 141)
        model.discover(validAnnouncement(tabID: 141))
        model.proveDiscoveredProvider()
        model.providerReady(tabID: 141)
        model.beginExtraction()
        model.resultReady()
        model.resultDelivered()
        model.requestCleanup()
        model.cleanupConfirmed()

        #expect(model.history == [
            .idle,
            .requestIntentPersisted,
            .providerCreationPending,
            .providerDocumentDiscovered,
            .providerOwnershipProven,
            .providerReady,
            .extracting,
            .resultReady,
            .resultDelivered,
            .cleanupRequested,
            .cleanupConfirmed,
            .complete,
        ])
        #expect(model.extractionCount == 1)
        #expect(model.cleanupRequestCount == 1)
        #expect(model.closedTabIDs == [141])
        #expect(model.generalEnumerationCount == 0)
    }

    @Test(arguments: V2CrashWindow.allCases)
    fileprivate func everyCrashWindowPreservesTheAbsoluteSafetyProperties(
        _ window: V2CrashWindow
    ) {
        var model = OwnedProviderTabV2Model(request: request)
        switch window {
        case .beforeIntent:
            break
        case .afterIntent:
            model.persistIntent()
        case .creationPending:
            model.persistIntent()
            model.beginProviderCreation()
        case .createReturnedBeforeProof:
            model.persistIntent()
            model.beginProviderCreation()
            model.providerCreateReturned(tabID: 151)
        case .discoveredBeforeProof:
            model.persistIntent()
            model.beginProviderCreation()
            model.discover(validAnnouncement(tabID: 151))
        case .ownershipProven:
            model = provenModel(tabID: 151)
        case .providerReady:
            model = provenModel(tabID: 151)
            model.providerReady(tabID: 151)
        case .extracting:
            model = provenModel(tabID: 151)
            model.providerReady(tabID: 151)
            model.beginExtraction()
        case .cleanupRequested:
            model = provenModel(tabID: 151)
            model.providerReady(tabID: 151)
            model.beginExtraction()
            model.resultReady()
            model.resultDelivered()
            model.requestCleanup()
        }

        model.backgroundCrashedAndReloaded()

        #expect(model.extractionCount <= 1)
        #expect(model.cleanupRequestCount <= 1)
        #expect(Set(model.closedTabIDs).count == model.closedTabIDs.count)
        #expect(model.generalEnumerationCount == 0)
        if model.cleanupRequestCount == 0 {
            #expect(model.closedTabIDs.isEmpty)
        }
    }

    @Test
    func cancellationAndExpiryAreTerminalAndCannotCloseAnUnprovenTab() {
        for terminal in [V2TerminalEvent.cancel, .expire] {
            var model = OwnedProviderTabV2Model(request: request)
            model.persistIntent()
            model.beginProviderCreation()
            model.providerCreateReturned(tabID: 161)
            switch terminal {
            case .cancel: model.cancel()
            case .expire: model.expire()
            }

            model.discover(validAnnouncement(tabID: 161))
            model.proveDiscoveredProvider()
            model.providerReady(tabID: 161)
            model.beginExtraction()
            model.requestCleanup()

            #expect(model.state == (terminal == .cancel ? .cancelled : .expired))
            #expect(model.extractionCount == 0)
            #expect(model.cleanupRequestCount == 0)
            #expect(model.closedTabIDs.isEmpty)
            #expect(model.generalEnumerationCount == 0)
        }
    }

    @Test
    func reloadRecoveryChallengeRequiresExactPersistedOwnedTabAndCurrentRequestTuple() {
        var exact = provenModel(tabID: 171)
        exact.backgroundCrashedAndReloaded()
        exact.recoverFromChallenge(validAnnouncement(tabID: 171))
        exact.providerReady(tabID: 171)
        exact.beginExtraction()
        #expect(exact.extractionCount == 1)
        #expect(exact.authoritativeProviderTabID == 171)

        var wrongTab = provenModel(tabID: 171)
        wrongTab.backgroundCrashedAndReloaded()
        wrongTab.recoverFromChallenge(validAnnouncement(tabID: 172))
        wrongTab.providerReady(tabID: 172)
        wrongTab.beginExtraction()
        #expect(wrongTab.extractionCount == 0)
        #expect(wrongTab.closedTabIDs.isEmpty)

        var staleGeneration = provenModel(tabID: 171)
        staleGeneration.backgroundCrashedAndReloaded()
        var stale = validAnnouncement(tabID: 171)
        stale.generation = "bd9f5e38-70bf-4b1b-81b0-e0903081f985"
        staleGeneration.recoverFromChallenge(stale)
        staleGeneration.providerReady(tabID: 171)
        staleGeneration.beginExtraction()
        #expect(staleGeneration.extractionCount == 0)
        #expect(staleGeneration.closedTabIDs.isEmpty)

        var expired = provenModel(tabID: 171)
        expired.expire()
        expired.recoverFromChallenge(validAnnouncement(tabID: 171))
        #expect(expired.state == .expired)
        #expect(expired.extractionCount == 0)

        var cancelled = provenModel(tabID: 171)
        cancelled.cancel()
        cancelled.recoverFromChallenge(validAnnouncement(tabID: 171))
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.extractionCount == 0)

        var terminal = provenModel(tabID: 171)
        terminal.onRemoved(tabID: 171)
        terminal.recoverFromChallenge(validAnnouncement(tabID: 171))
        #expect(terminal.state == .failed)
        #expect(terminal.extractionCount == 0)
    }

    @Test
    func reloadDuringExtractionOrAfterResultCaptureNeverStartsDuplicateExtraction() {
        var extracting = provenModel(tabID: 181)
        extracting.providerReady(tabID: 181)
        extracting.beginExtraction()
        extracting.backgroundCrashedAndReloaded()
        extracting.recoverFromChallenge(validAnnouncement(tabID: 181))
        extracting.providerReady(tabID: 181)
        extracting.beginExtraction()
        #expect(extracting.state == .failed)
        #expect(extracting.extractionCount == 1)

        var resultReady = provenModel(tabID: 182)
        resultReady.providerReady(tabID: 182)
        resultReady.beginExtraction()
        resultReady.resultReady()
        resultReady.backgroundCrashedAndReloaded()
        resultReady.recoverFromChallenge(validAnnouncement(tabID: 182))
        resultReady.providerReady(tabID: 182)
        resultReady.beginExtraction()
        #expect(resultReady.state == .resultReady)
        #expect(resultReady.extractionCount == 1)
        #expect(resultReady.closedTabIDs.isEmpty)
    }

    @Test
    func seededEventPermutationsPreserveOwnershipAndTerminalProperties() {
        let events = V2PropertyEvent.allCases
        var eventCoverage = Dictionary(uniqueKeysWithValues: events.map { ($0, 0) })
        var extractionTransitions = 0
        var cleanupTransitions = 0
        var recoveryTransitions = 0
        var terminalLockChecks = 0

        // 256 independently seeded sequences x 128 events = 32,768 bounded,
        // deterministic lifecycle transitions. This deliberately mixes valid,
        // delayed, duplicated, stale, spoofed, reordered, and terminal events.
        for seed in 1...256 {
            var random = V2SeededGenerator(seed: UInt64(seed))
            var model = OwnedProviderTabV2Model(request: request)
            model.prepareForPropertyPhase(seed % 9, announcement: validAnnouncement(tabID: 201))

            for _ in 0..<128 {
                let event = events[Int(random.next() % UInt64(events.count))]
                eventCoverage[event, default: 0] += 1
                let before = model.auditSnapshot
                let extractionCountBefore = model.extractionCount

                switch event {
                case .persistIntent:
                    model.persistIntent()
                case .beginCreation:
                    model.beginProviderCreation()
                case .createPrimary:
                    model.providerCreateReturned(tabID: 201)
                case .createDuplicate:
                    model.providerCreateReturned(tabID: 201)
                case .discoverPrimary:
                    model.discover(validAnnouncement(tabID: 201))
                case .discoverReplacement:
                    model.discover(validAnnouncement(tabID: 202))
                case .prove:
                    model.proveDiscoveredProvider()
                case .readyPrimary:
                    model.providerReady(tabID: 201)
                case .readyReplacement:
                    model.providerReady(tabID: 202)
                case .beginExtraction:
                    model.beginExtraction()
                case .resultReady:
                    model.resultReady()
                case .resultDelivered:
                    model.resultDelivered()
                case .requestCleanup:
                    model.requestCleanup()
                case .confirmCleanup:
                    model.cleanupConfirmed()
                case .removePrimary:
                    model.onRemoved(tabID: 201)
                case .removeReplacement:
                    model.onRemoved(tabID: 202)
                case .removeUnknown:
                    model.onRemoved(tabID: 999)
                case .replacePrimary:
                    model.onReplaced(removedTabID: 201, addedTabID: 202)
                case .replaceReplacement:
                    model.onReplaced(removedTabID: 202, addedTabID: 203)
                case .backgroundReload:
                    model.backgroundCrashedAndReloaded()
                case .recoverPrimary:
                    model.recoverFromChallenge(validAnnouncement(tabID: 201))
                case .recoverReplacement:
                    model.recoverFromChallenge(validAnnouncement(tabID: 202))
                case .staleGeneration:
                    var stale = validAnnouncement(tabID: 201)
                    stale.generation = "bd9f5e38-70bf-4b1b-81b0-e0903081f985"
                    let staleBefore = model.auditSnapshot
                    model.discover(stale)
                    #expect(model.auditSnapshot == staleBefore)
                case .spoofedSender:
                    var spoof = validAnnouncement(tabID: 201)
                    spoof.trustedExtensionSender = false
                    spoof.callerSuppliedTabID = 201
                    spoof.senderTabID = 999
                    let spoofBefore = model.auditSnapshot
                    model.discover(spoof)
                    #expect(model.auditSnapshot == spoofBefore)
                case .cancel:
                    model.cancel()
                case .expire:
                    model.expire()
                }

                if model.extractionCount > extractionCountBefore {
                    extractionTransitions += 1
                    #expect(before.state == .providerReady)
                    #expect(before.liveSenderProof)
                    #expect(before.authoritativeProviderTabID != nil)
                }
                #expect(model.cleanupRequestCount <= 1)
                #expect(Set(model.closedTabIDs).count == model.closedTabIDs.count)
                #expect(model.closedTabIDs.allSatisfy(model.everProvenTabIDs.contains))
                #expect(model.generalEnumerationCount == 0)
                if model.cleanupRequestCount > before.cleanupRequestCount {
                    cleanupTransitions += 1
                }
                if before.state == .providerCreationPending,
                   !before.liveSenderProof,
                   model.state == .providerOwnershipProven,
                   model.auditSnapshot.liveSenderProof {
                    recoveryTransitions += 1
                }
                if before.state.isTerminal {
                    terminalLockChecks += 1
                    #expect(model.auditSnapshot == before)
                }
            }
        }

        #expect(eventCoverage.values.allSatisfy { $0 >= 1_000 })
        #expect(extractionTransitions > 0)
        #expect(cleanupTransitions > 0)
        #expect(recoveryTransitions > 0)
        #expect(terminalLockChecks > 10_000)
    }

    @Test @MainActor
    func productionReducerImplementsTheExplicitStateMachineAndTerminalLock() throws {
        let context = try #require(JSContext())
        let reducer = try String(
            contentsOf: v2RepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/owned-provider-tab-v2-reducer.js"
            ),
            encoding: .utf8
        )
        context.evaluateScript(reducer)

        #expect(context.exception == nil)
        #expect(context.evaluateScript(
            "Object.values(UMAOwnedProviderTabV2Reducer.STATES).join('|')"
        )?.toString() == [
            "IDLE", "REQUEST_INTENT_PERSISTED", "PROVIDER_CREATION_PENDING",
            "PROVIDER_DOCUMENT_DISCOVERED", "PROVIDER_OWNERSHIP_PROVEN",
            "PROVIDER_READY", "EXTRACTING", "RESULT_READY", "RESULT_DELIVERED",
            "CLEANUP_REQUESTED", "CLEANUP_CONFIRMED", "COMPLETE", "CANCELLED",
            "EXPIRED", "FAILED",
        ].joined(separator: "|"))

        context.evaluateScript(
            """
            const reducer = UMAOwnedProviderTabV2Reducer;
            let state = reducer.STATES.idle;
            const sequence = [
              reducer.EVENTS.persistIntent,
              reducer.EVENTS.beginProviderCreation,
              reducer.EVENTS.discoverProviderDocument,
              reducer.EVENTS.proveProviderOwnership,
              reducer.EVENTS.providerReady,
              reducer.EVENTS.beginExtraction,
              reducer.EVENTS.captureResult,
              reducer.EVENTS.deliverResult,
              reducer.EVENTS.requestCleanup,
              reducer.EVENTS.confirmCleanup,
              reducer.EVENTS.complete,
            ];
            globalThis.productionStates = [state];
            for (const event of sequence) {
              state = reducer.transition(state, event);
              productionStates.push(state);
            }
            globalThis.terminalMutation = reducer.transition(
              state, reducer.EVENTS.discoverProviderDocument
            );
            globalThis.replacementState = reducer.transition(
              reducer.STATES.providerOwnershipProven,
              reducer.EVENTS.replacementRequiresReproof
            );
            """
        )

        #expect(context.exception == nil)
        #expect(context.evaluateScript("productionStates.join('|')")?.toString() == [
            "IDLE", "REQUEST_INTENT_PERSISTED", "PROVIDER_CREATION_PENDING",
            "PROVIDER_DOCUMENT_DISCOVERED", "PROVIDER_OWNERSHIP_PROVEN",
            "PROVIDER_READY", "EXTRACTING", "RESULT_READY", "RESULT_DELIVERED",
            "CLEANUP_REQUESTED", "CLEANUP_CONFIRMED", "COMPLETE",
        ].joined(separator: "|"))
        #expect(context.evaluateScript("terminalMutation === null")?.toBool() == true)
        #expect(context.evaluateScript("replacementState")?.toString()
            == "PROVIDER_DOCUMENT_DISCOVERED")
    }

    @Test @MainActor
    func productionLifecycleListenersCoalesceBothSafariReplacementOrderings() throws {
        let context = try #require(JSContext())
        let reducer = try String(
            contentsOf: v2RepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/owned-provider-tab-v2-reducer.js"
            ),
            encoding: .utf8
        )
        context.evaluateScript(reducer)
        context.evaluateScript(
            """
            function exercise(order) {
              const deferred = [];
              const events = [];
              const listeners = UMAOwnedProviderTabV2Reducer.createTabLifecycleListeners({
                ownedTabID: () => 91,
                isActive: () => true,
                isClosing: () => false,
                defer: (operation) => deferred.push(operation),
                onUnreplacedRemoval: (tabID) => events.push(`removed:${tabID}`),
                onReplacementCandidate: (added, removed) =>
                  events.push(`replaced:${removed}->${added}`),
              });
              for (const event of order) {
                if (event === "removed") listeners.onRemoved(91);
                else listeners.onReplaced(92, 91);
              }
              for (const operation of deferred) operation();
              return events.join("|");
            }
            globalThis.replacedThenRemoved = exercise(["replaced", "removed"]);
            globalThis.removedThenReplaced = exercise(["removed", "replaced"]);
            globalThis.removedOnly = exercise(["removed"]);
            """
        )

        #expect(context.exception == nil)
        #expect(context.evaluateScript("replacedThenRemoved")?.toString()
            == "replaced:91->92")
        #expect(context.evaluateScript("removedThenReplaced")?.toString()
            == "replaced:91->92")
        #expect(context.evaluateScript("removedOnly")?.toString() == "removed:91")
    }

    @Test
    func productionRecoveryCleansCrashGapsAndAcknowledgesOneResultReplay() throws {
        let background = try String(
            contentsOf: v2RepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/background-core.js"
            ),
            encoding: .utf8
        )
        let content = try String(
            contentsOf: v2RepositoryRoot().appendingPathComponent(
                "BrowserExtension/Shared/content-script.js"
            ),
            encoding: .utf8
        )

        #expect(background.contains("async function exactV2TabPresence(tabID)"))
        #expect(background.contains("async function recoverCleanupOnlyV2(read)"))
        #expect(background.contains("async function finalizeAbsentV2Cleanup(read)"))
        #expect(background.contains("record.state === v2States.cleanupRequested"))
        #expect(background.contains("record.state === v2States.cleanupConfirmed"))
        #expect(background.contains("if (presence === \"absent\")"))
        #expect(background.contains("read.cleanupOnly"))
        #expect(background.contains(
            "read.state === v2States.extracting || read.state === v2States.resultReady"
        ))
        #expect(background.contains("umaClaudeProviderResultAcceptedV2"))
        #expect(background.contains("read.resultMessageAccepted"))
        #expect(content.contains("resultTransmissionCount >= 2"))
        #expect(content.contains("state.resultAcknowledged = true"))
        #expect(content.contains("state.pendingResult = null"))
        #expect(!background.contains("api.tabs.query"))
    }

    @Test
    func productionSourcesEliminateBootstrapSelfNavigationAndBroadEnumeration() throws {
        let root = v2RepositoryRoot()
        let background = try String(
            contentsOf: root.appendingPathComponent("BrowserExtension/Shared/background-core.js"),
            encoding: .utf8
        )
        let content = try String(
            contentsOf: root.appendingPathComponent("BrowserExtension/Shared/content-script.js"),
            encoding: .utf8
        )
        let manifest = try String(
            contentsOf: root.appendingPathComponent("BrowserExtension/Safari/manifest.json"),
            encoding: .utf8
        )

        #expect(!background.contains("ownedTabBootstrapURL"))
        #expect(!background.contains("umaClaudeOwnedTabBootstrap"))
        #expect(!background.contains("api.tabs.query"))
        #expect(!content.contains("tabs.query"))
        #expect(!manifest.contains("owned-tab-bootstrap"))
        #expect(background.contains("providerURLForNonce"))
        #expect(background.contains("api.tabs.onRemoved.addListener"))
        #expect(background.contains("api.tabs.onReplaced?.addListener"))
        #expect(background.contains("api.tabs.onUpdated?.addListener"))
        #expect(background.contains("umaClaudeProviderRouteEventV2"))
        #expect(!background.contains("changeInfo.url"))
        #expect(background.contains("sender.tab.id"))
        #expect(background.contains("sender?.frameId"))
        #expect(content.contains("umaClaudeProviderDocumentDiscoveredV2"))
        #expect(content.contains("finalizeProviderRoute"))
        let earlyMarkerRemoval = try #require(content.range(
            of: "if (rawNonce && !ownership.finalizeProviderRoute(globalThis.history, rawNonce)) return;"
        ))
        let providerPortConnect = try #require(content.range(
            of: "try { port = runtime.connect({ name: portName }); }"
        ))
        #expect(earlyMarkerRemoval.lowerBound < providerPortConnect.lowerBound)
        #expect(content.contains("state.rawNonce\n        ? ownership.finalizeProviderRoute"))
        #expect(content.contains(": extractor.exactUsageURL(globalThis.location)"))
        #expect(content.contains("umaClaudeProviderMarkerRemovalFailedV2"))
        #expect(background.contains("umaClaudeProviderMarkerRemovalFailedV2"))
        #expect(content.contains("extractor.usageRouteState(globalThis.location)"))
        #expect(content.contains("new MutationObserver(scheduleReadinessEvaluation)"))
        #expect(content.contains("addEventListener(\"hashchange\""))
        #expect(content.contains("addEventListener(\"popstate\""))
        #expect(content.contains("addEventListener(\"DOMContentLoaded\""))
        #expect(!content.contains("maximumReadinessEvaluations"))
        #expect(content.contains("signInConfirmationCount >= 2"))
        #expect(content.contains("projection === state.lastSuccessProjection"))
        #expect(content.contains("scheduleRenderTurnConfirmation()"))
        #expect(content.contains("requestAnimationFrame"))
        #expect(content.contains("cancelRenderTurnConfirmation()"))
        #expect(!content.contains("readinessPollMilliseconds"))
        #expect(!content.contains("await delay("))
        for reason in [
            "ROUTE_NOT_READY", "ROUTE_READINESS_TIMEOUT", "PROVIDER_DOCUMENT_NOT_READY",
            "TARGET_DATA_NOT_READY", "TARGET_DATA_TIMEOUT", "PROVIDER_STRUCTURE_UNSUPPORTED",
            "PROVIDER_SESSION_UNAVAILABLE", "SITE_PERMISSION_MISSING",
            "EXTRACTION_VALIDATION_FAILED", "REQUEST_CANCELLED", "PROVIDER_TAB_CLOSED",
        ] {
            #expect(content.contains(reason))
        }
        let routeGate = try #require(content.range(
            of: "const routeState = extractor.usageRouteState(globalThis.location);"
        ))
        let domExtraction = try #require(content.range(
            of: "const result = extractor.extractResult(document, location, new Date());",
            range: routeGate.lowerBound..<content.endIndex
        ))
        #expect(routeGate.lowerBound < domExtraction.lowerBound)
        #expect(!content.contains(
            "!state.extractionInFlight\n        && extractor.exactUsageURL(globalThis.location)"
        ))
        #expect(manifest.contains("\"content_scripts\""))
        #expect(manifest.contains("\"run_at\": \"document_start\""))
        #expect(manifest.contains("Shared/provider-ownership-v2.js"))
    }

    private func provenModel(tabID: Int) -> OwnedProviderTabV2Model {
        var model = OwnedProviderTabV2Model(request: request)
        model.persistIntent()
        model.beginProviderCreation()
        model.providerCreateReturned(tabID: tabID)
        model.discover(validAnnouncement(tabID: tabID))
        model.proveDiscoveredProvider()
        return model
    }

    private func validAnnouncement(tabID: Int) -> V2Announcement {
        V2Announcement(
            requestID: request.requestID,
            generation: request.generation,
            nonce: request.nonce,
            senderTabID: tabID,
            callerSuppliedTabID: nil,
            trustedExtensionSender: true,
            topFrame: true,
            origin: "https://claude.ai"
        )
    }

    private func defectiveAnnouncement(
        _ defect: AnnouncementDefect,
        tabID: Int
    ) -> V2Announcement {
        var announcement = validAnnouncement(tabID: tabID)
        switch defect {
        case .wrongRequest:
            announcement.requestID = "ad9f5e38-70bf-4b1b-81b0-e0903081f984"
        case .wrongGeneration:
            announcement.generation = "bd9f5e38-70bf-4b1b-81b0-e0903081f985"
        case .wrongNonce:
            announcement.nonce = "cd9f5e38-70bf-4b1b-81b0-e0903081f986"
        case .untrustedSender:
            announcement.trustedExtensionSender = false
        case .subframe:
            announcement.topFrame = false
        case .wrongOrigin:
            announcement.origin = "https://example.invalid"
        }
        return announcement
    }

    private func permutations<T>(of values: [T]) -> [[T]] {
        guard let first = values.first else { return [[]] }
        return permutations(of: Array(values.dropFirst())).flatMap { suffix in
            (0...suffix.count).map { index in
                var copy = suffix
                copy.insert(first, at: index)
                return copy
            }
        }
    }
}

private struct ProviderRouteReadinessModel {
    let oldImmediateRouteRejection: Bool
    private(set) var domInspectionCount = 0
    private(set) var successObservationCount = 0
    private(set) var deliveryCount = 0
    private(set) var extractionStartCount = 0
    private(set) var terminalStatus: String?
    private var extracting = false
    private var priorSuccessProjection = false
    private var loginConfirmationCount = 0

    init(oldImmediateRouteRejection: Bool = false) {
        self.oldImmediateRouteRejection = oldImmediateRouteRejection
    }

    mutating func beginExtraction() {
        guard !extracting else { return }
        extracting = true
        extractionStartCount += 1
    }

    mutating func observeExactUsageWithoutLandmarks() {
        guard extracting, terminalStatus == nil else { return }
        domInspectionCount += 1
        priorSuccessProjection = false
        loginConfirmationCount = 0
    }

    mutating func observeTransientProviderRoute() {
        guard extracting, terminalStatus == nil else { return }
        // Route classification is content-free. No DOM inspection occurs.
        priorSuccessProjection = false
        loginConfirmationCount = 0
        if oldImmediateRouteRejection {
            terminalStatus = "routeRejected"
            deliveryCount += 1
        }
    }

    mutating func observeExactUsageWithLandmarks() {
        guard extracting, terminalStatus == nil else { return }
        domInspectionCount += 1
        loginConfirmationCount = 0
        if priorSuccessProjection {
            successObservationCount += 1
            terminalStatus = "success"
            deliveryCount += 1
        } else {
            priorSuccessProjection = true
        }
    }

    mutating func observeTransientLoginLandmark() {
        guard extracting, terminalStatus == nil else { return }
        domInspectionCount += 1
        priorSuccessProjection = false
        loginConfirmationCount += 1
        if loginConfirmationCount >= 2 {
            terminalStatus = "signInRequired"
            deliveryCount += 1
        }
    }

    mutating func expireWhileRouteIsTransient() {
        guard extracting, terminalStatus == nil else { return }
        terminalStatus = "routeRejected"
        deliveryCount += 1
    }
}

private struct ProviderRouteMarkerRaceModel {
    enum RemovalTiming {
        case atDocumentStart
        case afterNativeOwnership
    }

    enum Route {
        case markedUsage
        case usage
        case providerDefault
    }

    let removalTiming: RemovalTiming
    private(set) var route: Route = .markedUsage
    private(set) var markerVisibleInLocation = true
    private(set) var nonceRetainedOnlyInIsolatedMemory = false
    private(set) var providerReady = false
    private(set) var failureReason: String?

    mutating func documentStarted() {
        guard removalTiming == .atDocumentStart else { return }
        markerVisibleInLocation = false
        nonceRetainedOnlyInIsolatedMemory = true
        route = .usage
    }

    mutating func providerRouterNormalizedUnknownHash() {
        if markerVisibleInLocation {
            markerVisibleInLocation = false
            route = .providerDefault
        }
    }

    mutating func nativeOwnershipAccepted() {
        if removalTiming == .afterNativeOwnership {
            guard markerVisibleInLocation else {
                failureReason = "PROVIDER_ROUTE_MARKER_LOST"
                return
            }
            markerVisibleInLocation = false
            nonceRetainedOnlyInIsolatedMemory = true
            route = .usage
        }
        providerReady = route == .usage && nonceRetainedOnlyInIsolatedMemory
    }
}

private struct V2Request: Equatable {
    let requestID: String
    let generation: String
    let nonce: String
}

private struct V2Announcement: Equatable {
    var requestID: String
    var generation: String
    var nonce: String
    var senderTabID: Int
    var callerSuppliedTabID: Int?
    var trustedExtensionSender: Bool
    var topFrame: Bool
    var origin: String
}

private enum V2State: String, Equatable {
    case idle = "IDLE"
    case requestIntentPersisted = "REQUEST_INTENT_PERSISTED"
    case providerCreationPending = "PROVIDER_CREATION_PENDING"
    case providerDocumentDiscovered = "PROVIDER_DOCUMENT_DISCOVERED"
    case providerOwnershipProven = "PROVIDER_OWNERSHIP_PROVEN"
    case providerReady = "PROVIDER_READY"
    case extracting = "EXTRACTING"
    case resultReady = "RESULT_READY"
    case resultDelivered = "RESULT_DELIVERED"
    case cleanupRequested = "CLEANUP_REQUESTED"
    case cleanupConfirmed = "CLEANUP_CONFIRMED"
    case complete = "COMPLETE"
    case cancelled = "CANCELLED"
    case expired = "EXPIRED"
    case failed = "FAILED"

    var isTerminal: Bool {
        self == .complete || self == .cancelled || self == .expired || self == .failed
    }
}

private struct OwnedProviderTabV2Model {
    private(set) var state: V2State = .idle
    private(set) var history: [V2State] = [.idle]
    private(set) var receiptExists = false
    private(set) var authoritativeProviderTabID: Int?
    private(set) var closedTabIDs: [Int] = []
    private(set) var extractionCount = 0
    private(set) var cleanupRequestCount = 0
    private(set) var generalEnumerationCount = 0
    private(set) var failureReason: String?
    private(set) var everProvenTabIDs: Set<Int> = []

    private let request: V2Request
    private var createResultTabID: Int?
    private var discovered: V2Announcement?
    private var liveSenderProof = false

    init(request: V2Request) {
        self.request = request
    }

    var auditSnapshot: V2AuditSnapshot {
        V2AuditSnapshot(
            state: state,
            history: history,
            receiptExists: receiptExists,
            authoritativeProviderTabID: authoritativeProviderTabID,
            createResultTabID: createResultTabID,
            discovered: discovered,
            liveSenderProof: liveSenderProof,
            closedTabIDs: closedTabIDs,
            extractionCount: extractionCount,
            cleanupRequestCount: cleanupRequestCount,
            generalEnumerationCount: generalEnumerationCount,
            failureReason: failureReason,
            everProvenTabIDs: everProvenTabIDs
        )
    }

    mutating func prepareForPropertyPhase(_ phase: Int, announcement: V2Announcement) {
        guard phase > 0 else { return }
        persistIntent()
        guard phase > 1 else { return }
        beginProviderCreation()
        guard phase > 2 else { return }
        providerCreateReturned(tabID: announcement.senderTabID)
        guard phase > 3 else { return }
        discover(announcement)
        proveDiscoveredProvider()
        guard phase > 4 else { return }
        providerReady(tabID: announcement.senderTabID)
        guard phase > 5 else { return }
        beginExtraction()
        guard phase > 6 else { return }
        resultReady()
        guard phase > 7 else { return }
        resultDelivered()
        guard phase > 8 else { return }
        requestCleanup()
    }

    mutating func persistIntent() {
        guard state == .idle else { return }
        receiptExists = true
        transition(.requestIntentPersisted)
    }

    mutating func beginProviderCreation() {
        guard state == .requestIntentPersisted else { return }
        transition(.providerCreationPending)
    }

    mutating func providerCreateReturned(tabID: Int) {
        guard !state.isTerminal, receiptExists else { return }
        // The return value cannot prove ownership by itself, but it is an
        // independent candidate identity that trusted sender.tab.id must match.
        createResultTabID = tabID
    }

    mutating func discover(_ announcement: V2Announcement) {
        guard !state.isTerminal,
              receiptExists,
              [.providerCreationPending, .providerDocumentDiscovered,
               .providerOwnershipProven, .providerReady].contains(state),
              announcement.requestID == request.requestID,
              announcement.generation == request.generation,
              announcement.nonce == request.nonce,
              announcement.trustedExtensionSender,
              announcement.topFrame,
              announcement.origin == "https://claude.ai"
        else { return }
        guard createResultTabID == announcement.senderTabID else { return }
        if liveSenderProof,
           let authoritativeProviderTabID,
           authoritativeProviderTabID != announcement.senderTabID {
            return
        }

        // senderTabID is trusted extension metadata. callerSuppliedTabID is
        // ignored; ownership requires agreement with the independent create or
        // explicit replacement candidate.
        discovered = announcement
        liveSenderProof = false
        if state != .providerDocumentDiscovered {
            transition(.providerDocumentDiscovered)
        }
    }

    mutating func proveDiscoveredProvider() {
        guard !state.isTerminal,
              state == .providerDocumentDiscovered,
              let discovered,
              discovered.requestID == request.requestID,
              discovered.generation == request.generation,
              discovered.nonce == request.nonce,
              createResultTabID == discovered.senderTabID
        else { return }

        authoritativeProviderTabID = discovered.senderTabID
        everProvenTabIDs.insert(discovered.senderTabID)
        liveSenderProof = true
        transition(.providerOwnershipProven)
    }

    mutating func providerReady(tabID: Int) {
        guard !state.isTerminal,
              state == .providerOwnershipProven,
              liveSenderProof,
              authoritativeProviderTabID == tabID
        else { return }
        transition(.providerReady)
    }

    mutating func beginExtraction() {
        guard !state.isTerminal,
              state == .providerReady,
              liveSenderProof,
              authoritativeProviderTabID != nil
        else { return }
        extractionCount += 1
        transition(.extracting)
    }

    mutating func resultReady() {
        guard state == .extracting else { return }
        transition(.resultReady)
    }

    mutating func resultDelivered() {
        guard state == .resultReady else { return }
        transition(.resultDelivered)
    }

    mutating func requestCleanup() {
        guard state == .resultDelivered,
              liveSenderProof,
              let authoritativeProviderTabID,
              cleanupRequestCount == 0
        else { return }
        cleanupRequestCount += 1
        closedTabIDs.append(authoritativeProviderTabID)
        transition(.cleanupRequested)
    }

    mutating func cleanupConfirmed() {
        guard state == .cleanupRequested else { return }
        transition(.cleanupConfirmed)
        receiptExists = false
        liveSenderProof = false
        authoritativeProviderTabID = nil
        transition(.complete)
    }

    mutating func onRemoved(tabID: Int) {
        guard !state.isTerminal, receiptExists else { return }
        if authoritativeProviderTabID == tabID, liveSenderProof {
            liveSenderProof = false
            authoritativeProviderTabID = nil
            fail("OWNED_PROVIDER_TAB_REMOVED")
            return
        }
        if createResultTabID == tabID {
            createResultTabID = nil
            discovered = nil
            fail("UNPROVEN_PROVIDER_CANDIDATE_REMOVED")
        }
        // Unknown tabs are user-owned for safety. Never close or mutate them.
    }

    mutating func onReplaced(removedTabID: Int, addedTabID: Int) {
        guard !state.isTerminal,
              createResultTabID == removedTabID
                || (authoritativeProviderTabID == removedTabID && liveSenderProof)
        else { return }

        // onReplaced is a lifecycle hint, never an ownership transfer. The new
        // added ID becomes only the independent candidate. A trusted sender
        // from that exact ID must still prove the durable request tuple.
        liveSenderProof = false
        authoritativeProviderTabID = nil
        createResultTabID = addedTabID
        discovered = nil
        transition(.providerCreationPending)
    }

    mutating func recoverFromChallenge(_ announcement: V2Announcement) {
        guard !state.isTerminal,
              receiptExists,
              state == .providerCreationPending,
              authoritativeProviderTabID == announcement.senderTabID,
              createResultTabID == announcement.senderTabID,
              announcement.requestID == request.requestID,
              announcement.generation == request.generation,
              announcement.nonce == request.nonce,
              announcement.trustedExtensionSender,
              announcement.topFrame,
              announcement.origin == "https://claude.ai"
        else { return }

        discovered = announcement
        transition(.providerDocumentDiscovered)
        proveDiscoveredProvider()
    }

    mutating func backgroundCrashedAndReloaded() {
        guard !state.isTerminal, receiptExists else { return }
        // Durable intent survives; volatile sender trust does not. Reconnection
        // is event-driven and requires the content script to prove itself again.
        liveSenderProof = false
        discovered = nil
        switch state {
        case .idle:
            return
        case .requestIntentPersisted,
             .providerCreationPending,
             .providerDocumentDiscovered,
             .providerOwnershipProven,
             .providerReady:
            transition(.providerCreationPending)
        case .extracting:
            fail("CRASH_DURING_EXTRACTION_REQUIRES_FRESH_REQUEST")
        case .resultReady, .resultDelivered, .cleanupRequested, .cleanupConfirmed:
            // Durable result/cleanup state remains authoritative. It must not
            // regress into a second provider extraction after reload.
            break
        case .complete, .cancelled, .expired, .failed:
            break
        }
    }

    mutating func cancel() {
        guard !state.isTerminal else { return }
        transition(.cancelled)
    }

    mutating func expire() {
        guard !state.isTerminal else { return }
        transition(.expired)
    }

    mutating func permissionDenied() {
        fail("SITE_PERMISSION_DENIED")
    }

    mutating func navigationRejected() {
        fail("PROVIDER_NAVIGATION_REJECTED")
    }

    private mutating func fail(_ reason: String) {
        guard !state.isTerminal else { return }
        failureReason = reason
        transition(.failed)
    }

    private mutating func transition(_ next: V2State) {
        guard state != next else { return }
        state = next
        history.append(next)
    }
}

private struct RetiredBootstrapModel {
    private(set) var events: [String] = []
    private(set) var receiptExists = false
    private(set) var providerReady = false
    private var bootstrapTabID: Int?

    mutating func refreshStarted() { events.append("refreshStarted") }

    mutating func saveReceipt() {
        receiptExists = true
        events.append("receiptSaved")
    }

    mutating func activateBootstrap(tabID: Int) {
        bootstrapTabID = tabID
        events.append("receiptActivated")
    }

    mutating func onRemoved(tabID: Int) {
        guard bootstrapTabID == tabID else { return }
        receiptExists = false
        events.append("receiptRemoved")
        events.append("tabUnavailable")
    }
}

private enum V2OrderingEvent: CaseIterable {
    case createReturned
    case proof
    case ready
}

private enum AnnouncementDefect: CaseIterable {
    case wrongRequest
    case wrongGeneration
    case wrongNonce
    case untrustedSender
    case subframe
    case wrongOrigin
}

private enum V2PreProofFailure {
    case permissionDenied
    case navigationRejected
}

private enum V2CrashWindow: CaseIterable {
    case beforeIntent
    case afterIntent
    case creationPending
    case createReturnedBeforeProof
    case discoveredBeforeProof
    case ownershipProven
    case providerReady
    case extracting
    case cleanupRequested
}

private enum V2TerminalEvent {
    case cancel
    case expire
}

private struct V2AuditSnapshot: Equatable {
    let state: V2State
    let history: [V2State]
    let receiptExists: Bool
    let authoritativeProviderTabID: Int?
    let createResultTabID: Int?
    let discovered: V2Announcement?
    let liveSenderProof: Bool
    let closedTabIDs: [Int]
    let extractionCount: Int
    let cleanupRequestCount: Int
    let generalEnumerationCount: Int
    let failureReason: String?
    let everProvenTabIDs: Set<Int>
}

private enum V2PropertyEvent: CaseIterable {
    case persistIntent
    case beginCreation
    case createPrimary
    case createDuplicate
    case discoverPrimary
    case discoverReplacement
    case prove
    case readyPrimary
    case readyReplacement
    case beginExtraction
    case resultReady
    case resultDelivered
    case requestCleanup
    case confirmCleanup
    case removePrimary
    case removeReplacement
    case removeUnknown
    case replacePrimary
    case replaceReplacement
    case backgroundReload
    case recoverPrimary
    case recoverReplacement
    case staleGeneration
    case spoofedSender
    case cancel
    case expire
}

private struct V2SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed ^ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private func v2RepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
