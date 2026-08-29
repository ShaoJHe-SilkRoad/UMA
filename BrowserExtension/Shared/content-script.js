(function () {
  "use strict";

  const extractor = globalThis.UMAClaudeUsageExtractor;
  const ownership = globalThis.UMAProviderOwnershipV2;
  const runtime = globalThis.browser?.runtime || globalThis.chrome?.runtime;
  if (!extractor || !ownership || !runtime) return;

  const rawNonce = ownership.parseProviderMarker(globalThis.location);
  const safariOwnedChannel = runtime.getManifest?.().manifest_version === 2;
  const recoveryCandidate = safariOwnedChannel && !rawNonce
    && extractor.exactUsageURL(globalThis.location);
  if (!rawNonce) {
    // Chromium's user-initiated toolbar read remains a separate, non-owned,
    // exact-active-tab path. Safari production never sends this message.
    if (!extractor.exactUsageURL(globalThis.location)) return;
    runtime.onMessage.addListener((message) => {
      if (!message || Object.keys(message).length !== 1
          || message.type !== "umaClaudeExtractUsage") return undefined;
      const result = extractor.extractResult(document, location, new Date());
      const reply = result.status === "success"
        ? { type: "umaClaudeUsageResult", status: result.status, observation: result.observation }
        : { type: "umaClaudeUsageResult", status: result.status };
      runtime.sendMessage(reply).catch?.(() => {});
      return undefined;
    });
    if (!recoveryCandidate) return;
  }

  const readinessTimeoutMilliseconds = 20_000;
  const readinessReasons = Object.freeze({
    routeNotReady: "ROUTE_NOT_READY",
    routeReadinessTimeout: "ROUTE_READINESS_TIMEOUT",
    providerDocumentNotReady: "PROVIDER_DOCUMENT_NOT_READY",
    targetDataNotReady: "TARGET_DATA_NOT_READY",
    targetDataTimeout: "TARGET_DATA_TIMEOUT",
    providerStructureUnsupported: "PROVIDER_STRUCTURE_UNSUPPORTED",
    providerSessionUnavailable: "PROVIDER_SESSION_UNAVAILABLE",
    sitePermissionMissing: "SITE_PERMISSION_MISSING",
    extractionValidationFailed: "EXTRACTION_VALIDATION_FAILED",
    requestCancelled: "REQUEST_CANCELLED",
    providerTabClosed: "PROVIDER_TAB_CLOSED",
  });
  const stateKey = "__umaClaudeOwnedProviderTabV2";
  const portName = rawNonce
    ? "umaClaudeOwnedProviderV2" : "umaClaudeOwnedProviderRecoveryV2";
  const exactKeys = (value, expected) => Boolean(value)
    && typeof value === "object"
    && Object.keys(value).sort().join(",") === expected.slice().sort().join(",");

  // Keep the provider's real hash route valid from document_start onward.
  // Waiting for the asynchronous native ownership acknowledgement left the
  // temporary nonce inside the provider-controlled hash long enough for the
  // SPA router to normalize it away. The isolated content-script world keeps
  // the one-shot nonce in memory for the ownership Port, while history state is
  // sanitized synchronously before provider routing can observe an invalid
  // `settings/usage?...` route. A later full document reload recovers only by
  // the durable request/tab/generation challenge; it never trusts URL state.
  if (rawNonce && !ownership.finalizeProviderRoute(globalThis.history, rawNonce)) return;

  if (globalThis[stateKey]) return;
  const state = {
    rawNonce,
    requestID: null,
    runtimeGenerationID: null,
    port: null,
    ownershipAccepted: false,
    extractionInFlight: false,
    extractionStarted: false,
    resultDelivered: false,
    resultAcknowledged: false,
    resultTransmissionCount: 0,
    pendingResult: null,
    readinessObserver: null,
    readinessTimeoutID: null,
    readinessResolve: null,
    readinessEvaluationScheduled: false,
    readinessEvaluationCount: 0,
    renderTurnConfirmationID: null,
    lastSuccessProjection: null,
    signInConfirmationCount: 0,
    lastReadinessReason: null,
    routeListenersInstalled: false,
    reconnectsRemaining: 1,
    terminal: false,
  };
  Object.defineProperty(globalThis, stateKey, { value: state, configurable: false });

  function providerResultMessage(result) {
    return result.status === "success"
      ? {
          type: "umaClaudeProviderResultV2",
          requestID: state.requestID,
          runtimeGenerationID: state.runtimeGenerationID,
          status: result.status,
          observation: result.observation,
        }
      : {
          type: "umaClaudeProviderResultV2",
          requestID: state.requestID,
          runtimeGenerationID: state.runtimeGenerationID,
          status: result.status,
          providerFailureReason: result.providerFailureReason,
        };
  }

  function flushPendingResult() {
    if (!state.pendingResult || !state.port || !state.ownershipAccepted
        || state.resultAcknowledged || state.resultDelivered
        || state.resultTransmissionCount >= 2) return;
    try {
      state.port.postMessage(providerResultMessage(state.pendingResult));
      state.resultDelivered = true;
      state.resultTransmissionCount += 1;
    } catch (_) {}
  }

  function removeReadinessListeners() {
    if (state.readinessTimeoutID !== null) clearTimeout(state.readinessTimeoutID);
    state.readinessTimeoutID = null;
    state.readinessObserver?.disconnect();
    state.readinessObserver = null;
    cancelRenderTurnConfirmation();
    if (state.routeListenersInstalled) {
      globalThis.removeEventListener("hashchange", routeReadinessChanged);
      globalThis.removeEventListener("popstate", routeReadinessChanged);
      globalThis.removeEventListener("pageshow", routeReadinessChanged);
      globalThis.navigation?.removeEventListener?.("navigatesuccess", routeReadinessChanged);
      document.removeEventListener("DOMContentLoaded", scheduleReadinessEvaluation);
      state.routeListenersInstalled = false;
    }
  }

  function completeReadiness(result) {
    if (state.pendingResult) return;
    removeReadinessListeners();
    state.pendingResult = result.status === "success" ? result : {
      status: result.status,
      providerFailureReason: result.providerFailureReason || state.lastReadinessReason
        || readinessReasons.extractionValidationFailed,
    };
    flushPendingResult();
    const resolve = state.readinessResolve;
    state.readinessResolve = null;
    resolve?.();
  }

  function noteReadiness(reason) {
    if (Object.values(readinessReasons).includes(reason)) state.lastReadinessReason = reason;
  }

  function cancelRenderTurnConfirmation() {
    if (state.renderTurnConfirmationID === null) return;
    globalThis.cancelAnimationFrame?.(state.renderTurnConfirmationID);
    state.renderTurnConfirmationID = null;
  }

  function scheduleRenderTurnConfirmation() {
    if (state.renderTurnConfirmationID !== null
        || typeof globalThis.requestAnimationFrame !== "function") return;
    state.renderTurnConfirmationID = globalThis.requestAnimationFrame(() => {
      state.renderTurnConfirmationID = null;
      scheduleReadinessEvaluation();
    });
  }

  function stableProjection(observation) {
    if (!observation) return null;
    // observedAt is the extraction time, not provider data. Stability is
    // proven from two equivalent sanitized quota/reset projections.
    return JSON.stringify({
      fiveHour: observation.fiveHour,
      weeklyAllModels: observation.weeklyAllModels,
      modelSpecificWeekly: observation.modelSpecificWeekly,
      extractorSchemaVersion: observation.extractorSchemaVersion,
      sourceLayoutVersion: observation.sourceLayoutVersion,
    });
  }

  function armReadinessObserver() {
    if (state.readinessObserver || !document.documentElement) return;
    state.readinessObserver = new MutationObserver(scheduleReadinessEvaluation);
    state.readinessObserver.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["aria-valuenow", "data-used-percentage", "data-reset-at", "datetime"],
    });
  }

  function evaluateProviderReadiness(deadlineReached = false) {
    if (state.pendingResult || state.resultDelivered || !state.ownershipAccepted) return;
    const routeState = extractor.usageRouteState(globalThis.location);
    if (routeState !== "exact") {
      cancelRenderTurnConfirmation();
      state.readinessObserver?.disconnect();
      state.readinessObserver = null;
      state.lastSuccessProjection = null;
      state.signInConfirmationCount = 0;
      noteReadiness(readinessReasons.routeNotReady);
      if (deadlineReached) {
        noteReadiness(readinessReasons.routeReadinessTimeout);
        completeReadiness({ status: "routeRejected" });
      }
      return;
    }
    if (document.readyState === "loading") {
      noteReadiness(readinessReasons.providerDocumentNotReady);
      if (deadlineReached) {
        completeReadiness({
          status: "usageUnavailable",
          providerFailureReason: readinessReasons.providerDocumentNotReady,
        });
      }
      return;
    }

    armReadinessObserver();
    state.readinessEvaluationCount += 1;
    const result = extractor.extractResult(document, location, new Date());
    if (result.status === "success") {
      const projection = stableProjection(result.observation);
      if (projection === state.lastSuccessProjection) {
        completeReadiness(result);
      } else {
        state.lastSuccessProjection = projection;
        noteReadiness(readinessReasons.targetDataNotReady);
        if (deadlineReached) {
          noteReadiness(readinessReasons.targetDataTimeout);
          completeReadiness({ status: "usageUnavailable" });
        } else {
          scheduleRenderTurnConfirmation();
        }
      }
      return;
    }
    state.lastSuccessProjection = null;
    if (result.status === "signInRequired") {
      noteReadiness(readinessReasons.providerSessionUnavailable);
      state.signInConfirmationCount += 1;
      if (state.signInConfirmationCount >= 2) completeReadiness(result);
      else if (deadlineReached) {
        completeReadiness({
          status: "signInRequired",
          providerFailureReason: readinessReasons.providerSessionUnavailable,
        });
      } else {
        scheduleRenderTurnConfirmation();
      }
      return;
    }
    state.signInConfirmationCount = 0;
    if (result.status === "routeRejected") {
      // The extractor revalidates the route after its bounded DOM read. Treat
      // an in-read SPA transition as pending until the event-driven deadline.
      noteReadiness(readinessReasons.routeNotReady);
      if (deadlineReached) {
        noteReadiness(readinessReasons.routeReadinessTimeout);
        completeReadiness({ status: "routeRejected" });
      }
      return;
    }
    const providerFailureReason = result.reasonCode
      === extractor.FAILURE_REASONS?.providerStructureUnsupported
      ? readinessReasons.providerStructureUnsupported
      : readinessReasons.targetDataNotReady;
    noteReadiness(providerFailureReason);
    if (deadlineReached) {
      completeReadiness({
        status: "usageUnavailable",
        providerFailureReason: providerFailureReason === readinessReasons.targetDataNotReady
          ? readinessReasons.targetDataTimeout : providerFailureReason,
      });
    }
  }

  function scheduleReadinessEvaluation() {
    if (state.readinessEvaluationScheduled || state.pendingResult || state.resultDelivered) return;
    state.readinessEvaluationScheduled = true;
    queueMicrotask(() => {
      state.readinessEvaluationScheduled = false;
      evaluateProviderReadiness(false);
    });
  }

  function routeReadinessChanged() {
    if (extractor.usageRouteState(globalThis.location) !== "exact") {
      state.readinessObserver?.disconnect();
      state.readinessObserver = null;
    }
    scheduleReadinessEvaluation();
  }

  function extractAfterUsageLandmarksRender() {
    if (!state.ownershipAccepted || state.extractionStarted) return Promise.resolve();
    state.extractionStarted = true;
    return new Promise((resolve) => {
      state.readinessResolve = resolve;
      globalThis.addEventListener("hashchange", routeReadinessChanged);
      globalThis.addEventListener("popstate", routeReadinessChanged);
      globalThis.addEventListener("pageshow", routeReadinessChanged);
      globalThis.navigation?.addEventListener?.("navigatesuccess", routeReadinessChanged);
      document.addEventListener("DOMContentLoaded", scheduleReadinessEvaluation);
      state.routeListenersInstalled = true;
      state.readinessTimeoutID = setTimeout(
        () => evaluateProviderReadiness(true), readinessTimeoutMilliseconds
      );
      scheduleReadinessEvaluation();
    });
  }

  function handleBackgroundMessage(message) {
    if (exactKeys(message, ["requestID", "runtimeGenerationID", "type"])
        && message.type === "umaClaudeProviderResultAcceptedV2"
        && message.requestID === state.requestID
        && message.runtimeGenerationID === state.runtimeGenerationID) {
      state.resultAcknowledged = true;
      state.pendingResult = null;
      return;
    }

    if (recoveryCandidate
        && exactKeys(message, ["challengeID", "requestID", "runtimeGenerationID", "type"])
        && message.type === "umaClaudeProviderRecoveryChallengeV2") {
      try { state.port?.postMessage({
        type: "umaClaudeProviderRecoveryResponseV2",
        challengeID: message.challengeID,
        requestID: message.requestID,
        runtimeGenerationID: message.runtimeGenerationID,
      }); } catch (_) {}
      return;
    }

    if (recoveryCandidate
        && exactKeys(message, ["requestID", "runtimeGenerationID", "type"])
        && message.type === "umaClaudeProviderRecoveryAcceptedV2") {
      state.requestID = message.requestID;
      state.runtimeGenerationID = message.runtimeGenerationID;
      const routeAccepted = state.rawNonce
        ? ownership.finalizeProviderRoute(globalThis.history, state.rawNonce)
        : extractor.exactUsageURL(globalThis.location);
      if (!routeAccepted) {
        state.terminal = true;
        try { state.port?.postMessage({
          type: "umaClaudeProviderMarkerRemovalFailedV2",
          requestID: state.requestID,
          runtimeGenerationID: state.runtimeGenerationID,
        }); } catch (_) {}
        return;
      }
      state.ownershipAccepted = true;
      flushPendingResult();
      return;
    }

    if (exactKeys(message, ["requestID", "runtimeGenerationID", "type"])
        && message.type === "umaClaudeProviderOwnershipAcceptedV2") {
      if (state.ownershipAccepted
          && (message.requestID !== state.requestID
            || message.runtimeGenerationID !== state.runtimeGenerationID)) {
        state.terminal = true;
        try { state.port?.disconnect(); } catch (_) {}
        return;
      }
      state.requestID = message.requestID;
      state.runtimeGenerationID = message.runtimeGenerationID;
      state.ownershipAccepted = true;
      flushPendingResult();
      try { state.port?.postMessage({
        type: "umaClaudeProviderReadyV2",
        requestID: state.requestID,
        runtimeGenerationID: state.runtimeGenerationID,
      }); } catch (_) {}
      return;
    }

    if (exactKeys(message, ["requestID", "runtimeGenerationID", "type"])
        && message.type === "umaClaudeProviderRouteEventV2"
        && state.ownershipAccepted
        && message.requestID === state.requestID
        && message.runtimeGenerationID === state.runtimeGenerationID) {
      scheduleReadinessEvaluation();
      return;
    }

    if (exactKeys(message, ["requestID", "runtimeGenerationID", "type"])
        && message.type === "umaClaudeExtractProviderUsageV2"
        && state.ownershipAccepted
        && message.requestID === state.requestID
        && message.runtimeGenerationID === state.runtimeGenerationID
        && !state.extractionStarted
        && !state.resultDelivered) {
      state.extractionInFlight = true;
      void extractAfterUsageLandmarksRender().finally(() => {
        state.extractionInFlight = false;
      });
    }
  }

  function connect() {
    if (state.terminal || (!state.rawNonce && !recoveryCandidate)) return;
    let port;
    try { port = runtime.connect({ name: portName }); } catch (_) { return; }
    if (!port?.onMessage?.addListener || !port?.onDisconnect?.addListener) return;
    state.port = port;
    port.onMessage.addListener(handleBackgroundMessage);
    port.onDisconnect.addListener(() => {
      if (state.port !== port) return;
      state.port = null;
      // Keep the sanitized terminal result in isolated memory until the owned
      // tab is closed. A background reload can therefore recover and receive
      // the same correlated projection once; native lifecycle CAS makes that
      // retransmission idempotent.
      if (state.pendingResult && !state.resultAcknowledged
          && state.resultTransmissionCount < 2) state.resultDelivered = false;
      // One event-driven reconnect covers a background reload. There is no
      // polling loop and a reloaded provider document without the marker fails closed.
      if (!state.terminal && state.reconnectsRemaining > 0) {
        state.reconnectsRemaining -= 1;
        queueMicrotask(connect);
      }
    });
    try {
      if (rawNonce) {
        port.postMessage({
          type: "umaClaudeProviderDocumentDiscoveredV2",
          ownershipNonce: state.rawNonce,
        });
      } else {
        port.postMessage({ type: "umaClaudeProviderRecoveryCandidateV2" });
      }
    } catch (_) {}
  }

  connect();
})();
