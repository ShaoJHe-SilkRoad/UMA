(function (root) {
  "use strict";

  const extractor = root.UMAClaudeUsageExtractor;
  const providerOwnership = root.UMAProviderOwnershipV2;
  const ownedProviderReducer = root.UMAOwnedProviderTabV2Reducer;
  const config = root.UMA_BROWSER_CONFIG;
  const api = root.browser || root.chrome;
  if (!extractor || !config || !api?.runtime
      || (config.browserFamily === "safari" && (!providerOwnership || !ownedProviderReducer))) return;

  const usageScriptFiles = Object.freeze([
    "Shared/claude-usage-extractor.js",
    "Shared/provider-ownership-v2.js",
    "Shared/content-script.js",
  ]);
  const resultStatuses = Object.freeze([
    "success",
    "signInRequired",
    "routeRejected",
    "usageUnavailable",
  ]);
  const providerFailureReasons = new Set([
    "ROUTE_NOT_READY", "ROUTE_READINESS_TIMEOUT", "PROVIDER_DOCUMENT_NOT_READY",
    "TARGET_DATA_NOT_READY", "TARGET_DATA_TIMEOUT", "PROVIDER_STRUCTURE_UNSUPPORTED",
    "PROVIDER_SESSION_UNAVAILABLE", "SITE_PERMISSION_MISSING",
    "EXTRACTION_VALIDATION_FAILED", "REQUEST_CANCELLED", "PROVIDER_TAB_CLOSED",
  ]);
  const automaticFailureStatuses = new Set([
    "permissionRequired",
    "signInRequired",
    "routeRejected",
    "usageUnavailable",
    "tabUnavailable",
    "ownedTabClosed",
    "ownedTabOwnershipLost",
  ]);
  const requestIDPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const automaticTimeoutMilliseconds = 30_000;
  const ownedTabReceiptMaximumAgeMilliseconds = 2 * 60 * 1_000;
  const extractUsageMessage = "umaClaudeExtractUsage";
  const runtimeQualificationMessageName = "umaClaudeRuntimeQualification";
  const automaticReadStates = Object.freeze({
    dormant: "DORMANT",
    starting: "STARTING",
    nativeBridgeConnecting: "NATIVE_BRIDGE_CONNECTING",
    nativeBridgeReady: "NATIVE_BRIDGE_READY",
    requestAccepted: "REQUEST_ACCEPTED",
    sitePermissionChecking: "SITE_PERMISSION_CHECKING",
    complete: "COMPLETE",
    cancelled: "CANCELLED",
    failed: "FAILED",
  });

  let injectionInFlight = false;
  let companionLifecycleState = automaticReadStates.dormant;
  let automaticRead = null;
  let containingAppPort = null;
  let containingAppPortState = "disconnected";
  let containingAppPortGeneration = 0;
  let containingAppReconnectTicket = 0;
  let containingAppReconnectBudget = 1;
  let containingAppReconnectScheduled = false;
  const activeQualificationRequests = new Set();
  let nativeQueue = Promise.resolve();
  let ownedTabRecoveryBlocked = false;
  let ownedTabRecoveryPromise = null;
  let pendingV2Receipt = null;
  let ownedTabExpiryTimer = null;
  const activeRuntimeOperations = new Set();

  function retainRuntimeOperation(operation) {
    const retained = Promise.resolve(operation);
    activeRuntimeOperations.add(retained);
    void retained.finally(() => {
      activeRuntimeOperations.delete(retained);
    }).catch(() => {});
  }

  function transitionCompanion(next) {
    const allowed = {
      [automaticReadStates.dormant]: [automaticReadStates.starting],
      [automaticReadStates.starting]: [
        automaticReadStates.nativeBridgeConnecting,
        automaticReadStates.failed,
      ],
      [automaticReadStates.nativeBridgeConnecting]: [
        automaticReadStates.nativeBridgeReady,
        automaticReadStates.starting,
        automaticReadStates.failed,
      ],
      [automaticReadStates.nativeBridgeReady]: [
        automaticReadStates.requestAccepted,
        automaticReadStates.starting,
      ],
      [automaticReadStates.requestAccepted]: [automaticReadStates.sitePermissionChecking],
      [automaticReadStates.sitePermissionChecking]: [
        automaticReadStates.complete,
        automaticReadStates.cancelled,
        automaticReadStates.failed,
        automaticReadStates.nativeBridgeReady,
      ],
      [automaticReadStates.complete]: [automaticReadStates.nativeBridgeReady],
      [automaticReadStates.cancelled]: [automaticReadStates.nativeBridgeReady],
      [automaticReadStates.failed]: [
        automaticReadStates.nativeBridgeReady,
        automaticReadStates.starting,
      ],
    };
    if (!(allowed[companionLifecycleState] || []).includes(next)) return false;
    companionLifecycleState = next;
    return true;
  }

  function isPlainObject(value) {
    return Boolean(value) && Object.getPrototypeOf(value) === Object.prototype;
  }

  function exactKeys(value, expected) {
    return isPlainObject(value) && Object.keys(value).sort().join(",") === expected.slice().sort().join(",");
  }

  function allowedSenderURL(raw) {
    try { return extractor.exactUsageURL(new URL(raw)); } catch (_) { return false; }
  }

  function redirectedTerminalStatusForURL(raw) {
    try {
      const url = new URL(raw);
      if (url.origin !== extractor.CONTRACT.origin) return "signInRequired";
      const normalizedPath = url.pathname.toLowerCase().replace(/\/+$/, "") || "/";
      return /^\/(?:auth(?:\/|$)|login(?:\/|$)|sign-?in(?:\/|$))/.test(normalizedPath)
        ? "signInRequired"
        : "routeRejected";
    } catch (_) {
      return "routeRejected";
    }
  }

  function sendNativeReply(payload) {
    const operation = nativeQueue
      .then(() => api.runtime.sendNativeMessage(config.nativeApplication, payload))
      .then((reply) => isPlainObject(reply) ? reply : null, () => null);
    nativeQueue = operation.then(() => undefined, () => undefined);
    return operation;
  }

  async function sendNative(payload) {
    const reply = await sendNativeReply(payload);
    return exactKeys(reply, ["ok"]) && reply.ok === true;
  }

  function automationEnvelope(requestID, status) {
    const envelope = {
      kind: "claudeBrowserAutomationEvent",
      schemaVersion: 2,
      sourceID: "claude-browser-usage",
      browserFamily: "safari",
      requestID,
      status,
      occurredAt: new Date().toISOString(),
    };
    return envelope;
  }

  function backgroundReadyEnvelope(requestID) {
    return {
      ...automationEnvelope(requestID, "extensionBackgroundReady"),
      companionVersion: config.companionVersion,
      companionBuild: config.companionBuild,
      protocolSchemaVersion: config.protocolSchemaVersion,
      containingApplicationIdentifier: config.containingApplicationIdentifier,
      extensionIdentifier: config.extensionBundleIdentifier,
      teamIdentifier: config.teamIdentifier,
      runtimeGenerationID: config.runtimeGenerationID,
    };
  }

  function runtimeDiagnosticEnvelope(requestID, status) {
    return {
      ...automationEnvelope(requestID, status),
      companionVersion: config.companionVersion,
      companionBuild: config.companionBuild,
      protocolSchemaVersion: config.protocolSchemaVersion,
      containingApplicationIdentifier: config.containingApplicationIdentifier,
      extensionIdentifier: config.extensionBundleIdentifier,
      teamIdentifier: config.teamIdentifier,
      runtimeGenerationID: config.runtimeGenerationID,
    };
  }

  async function announceBackgroundReady(requestID, portGeneration) {
    if (!isCurrentContainingAppPort(portGeneration)
        || !requestIDPattern.test(requestID)) return false;
    return await sendNative(backgroundReadyEnvelope(requestID));
  }

  function runtimeQualificationRequest(requestID) {
    return {
      kind: "claudeBrowserRuntimeQualificationRequest",
      schemaVersion: 2,
      sourceID: "claude-browser-usage",
      browserFamily: "safari",
      requestID,
      runtimeGenerationID: config.runtimeGenerationID,
    };
  }

  function validRuntimeQualificationReply(value, requestID) {
    return exactKeys(value, [
      "accepted", "browserFamily", "companionBuild", "companionVersion",
      "containingApplicationIdentifier", "extensionIdentifier", "kind",
      "protocolSchemaVersion", "reason", "replyID", "requestID",
      "runtimeGenerationID", "schemaVersion", "sourceID", "teamIdentifier",
    ])
      && value.kind === "claudeBrowserRuntimeQualificationReply"
      && value.schemaVersion === 2
      && value.sourceID === "claude-browser-usage"
      && value.browserFamily === "safari"
      && value.requestID === requestID
      && requestIDPattern.test(value.replyID)
      && value.runtimeGenerationID === config.runtimeGenerationID
      && value.companionVersion === config.companionVersion
      && value.companionBuild === config.companionBuild
      && value.protocolSchemaVersion === config.protocolSchemaVersion
      && value.containingApplicationIdentifier === config.containingApplicationIdentifier
      && value.extensionIdentifier === config.extensionBundleIdentifier
      && value.teamIdentifier === config.teamIdentifier
      && value.accepted === true
      && value.reason === "accepted";
  }

  function runtimeQualificationAcknowledgement(reply) {
    return {
      kind: "claudeBrowserRuntimeQualificationAcknowledgement",
      schemaVersion: 2,
      sourceID: "claude-browser-usage",
      browserFamily: "safari",
      requestID: reply.requestID,
      replyID: reply.replyID,
      runtimeGenerationID: reply.runtimeGenerationID,
      accepted: true,
    };
  }

  function isCurrentContainingAppPort(generation) {
    return containingAppPort !== null
      && containingAppPortState === "ready"
      && containingAppPortGeneration === generation;
  }

  async function qualifyRuntime(requestID, portGeneration) {
    if (!isCurrentContainingAppPort(portGeneration)) return false;
    if (activeQualificationRequests.has(requestID)) return false;
    activeQualificationRequests.add(requestID);
    try {
      const reply = await sendNativeReply(runtimeQualificationRequest(requestID));
      if (!isCurrentContainingAppPort(portGeneration)
          || !validRuntimeQualificationReply(reply, requestID)) return false;
      if (!await sendNative(runtimeDiagnosticEnvelope(
        requestID, "extensionResponseReceived"
      ))) return false;
      const acknowledgement = await sendNativeReply(
        runtimeQualificationAcknowledgement(reply)
      );
      return isCurrentContainingAppPort(portGeneration)
        && exactKeys(acknowledgement, ["ok"])
        && acknowledgement.ok === true;
    } finally {
      activeQualificationRequests.delete(requestID);
    }
  }

  function observationEnvelope(requestID, observation) {
    return {
      kind: "claudeUsageObservation",
      schemaVersion: 2,
      sourceID: "claude-browser-usage",
      browserFamily: config.browserFamily,
      routeState: "verifiedUsage",
      requestID,
      observationID: crypto.randomUUID(),
      observation,
    };
  }

  function terminalEnvelope(
    requestID,
    status,
    observation = null,
    targetRequestID = null,
    providerFailureReason = null
  ) {
    return {
      kind: "claudeBrowserTerminalPacket",
      schemaVersion: 2,
      sourceID: "claude-browser-usage",
      browserFamily: "safari",
      requestID,
      targetRequestID,
      runtimeGenerationID: config.runtimeGenerationID,
      status,
      occurredAt: new Date().toISOString(),
      observation,
      providerFailureReason,
    };
  }

  async function injectExactUsageRoute(tabID) {
    if (!Number.isInteger(tabID)) return false;
    if (injectionInFlight) return false;
    injectionInFlight = true;
    try {
      // Safari MV2 declares the exact claude.ai host permission but deliberately
      // does not declare the separate `scripting` permission. Some Safari
      // versions still expose `browser.scripting`; selecting it would therefore
      // fail before the valid MV2 injection path is attempted. Keep one
      // permission-consistent Safari path and reserve `scripting` for Chromium.
      if (config.browserFamily === "safari") {
        if (!api.tabs?.executeScript) return false;
        for (const file of usageScriptFiles) {
          await api.tabs.executeScript(tabID, { file, allFrames: false });
        }
      } else if (api.scripting?.executeScript) {
        await api.scripting.executeScript({
          target: { tabId: tabID, allFrames: false },
          files: usageScriptFiles,
        });
      } else if (api.tabs?.executeScript) {
        for (const file of usageScriptFiles) {
          await api.tabs.executeScript(tabID, { file, allFrames: false });
        }
      } else {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      injectionInFlight = false;
    }
  }

  async function persistentUsageAccessGranted() {
    if (!api.permissions?.contains || typeof config.exactHostPermission !== "string") return false;
    try {
      return await api.permissions.contains({ origins: [config.exactHostPermission] });
    } catch (_) {
      return false;
    }
  }

  async function handleContentResult(message, sender) {
    if (!isPlainObject(message) || message.type !== "umaClaudeUsageResult"
        || !resultStatuses.includes(message.status)) return;
    const expected = message.status === "success"
      ? ["observation", "status", "type"] : ["status", "type"];
    if (!exactKeys(message, expected)
        || !Number.isInteger(sender?.tab?.id)
        || !allowedSenderURL(sender?.url || sender?.tab?.url || "")) return;
    // This receiver is exclusively the Chromium user-initiated active-tab path.
    // Safari Accuracy Sync results arrive only on the correlated V2 Port.
    if (config.browserFamily !== "chromium") return;
    // The existing manual toolbar result remains UI-local; it is never accepted
    // as an unattended Accuracy Sync observation.
  }

  const v2States = ownedProviderReducer?.STATES;
  const v2Events = ownedProviderReducer?.EVENTS;
  const v2PortName = "umaClaudeOwnedProviderV2";
  const v2RecoveryPortName = "umaClaudeOwnedProviderRecoveryV2";

  function v2ReceiptCommand(action, fields = {}) {
    return {
      kind: "claudeOwnedProviderTabV2ReceiptCommand",
      schemaVersion: 3,
      action,
      ...fields,
    };
  }

  function newOwnershipNonce() {
    if (!root.crypto?.getRandomValues) return null;
    const bytes = new Uint8Array(32);
    root.crypto.getRandomValues(bytes);
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return root.btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  function validV2Receipt(record) {
    return isPlainObject(record)
      && requestIDPattern.test(record.requestID || "")
      && requestIDPattern.test(record.runtimeGenerationID || "")
      && /^[0-9a-f]{64}$/.test(record.ownershipNonceDigest || "")
      && Number.isFinite(Date.parse(record.createdAt))
      && Number.isFinite(Date.parse(record.expiresAt))
      && Number.isInteger(record.revision) && record.revision > 0
      && Object.values(v2States).includes(record.state);
  }

  async function saveV2Intent(read) {
    const rawNonce = newOwnershipNonce();
    if (!rawNonce) return false;
    const ownershipNonceDigest = await providerOwnership.nonceDigest(rawNonce);
    if (!ownershipNonceDigest) return false;
    const createdAt = new Date().toISOString();
    const expiresAt = new Date(Date.now() + ownedTabReceiptMaximumAgeMilliseconds).toISOString();
    const reply = await sendNativeReply(v2ReceiptCommand("saveV2", {
      requestID: read.requestID,
      runtimeGenerationID: config.runtimeGenerationID,
      ownershipNonceDigest,
      createdAt,
      expiresAt,
      lifecycleState: v2States.requestIntentPersisted,
      revision: 1,
    }));
    if (!exactKeys(reply, ["ok", "revision"]) || reply.ok !== true || reply.revision !== 1) {
      return false;
    }
    Object.assign(read, {
      rawNonce,
      ownershipNonceDigest,
      createdAt,
      expiresAt,
      revision: 1,
      state: v2States.requestIntentPersisted,
    });
    return true;
  }

  async function transitionV2(read, event, options = {}) {
    if (!read || !validV2Receipt({
      requestID: read.requestID,
      runtimeGenerationID: config.runtimeGenerationID,
      ownershipNonceDigest: read.ownershipNonceDigest,
      createdAt: read.createdAt,
      expiresAt: read.expiresAt,
      revision: read.revision,
      state: read.state,
    })) return false;
    const nextState = ownedProviderReducer.transition(read.state, event);
    if (!nextState) return false;
    const fields = {
      requestID: read.requestID,
      runtimeGenerationID: config.runtimeGenerationID,
      ownershipNonceDigest: read.ownershipNonceDigest,
      expectedRevision: read.revision,
      expectedLifecycleState: read.state,
      nextLifecycleState: nextState,
    };
    if (Number.isInteger(options.providerCandidateTabID)) {
      fields.providerCandidateTabID = options.providerCandidateTabID;
    }
    if (Number.isInteger(options.providerOwnedTabID)) {
      fields.providerOwnedTabID = options.providerOwnedTabID;
    }
    const reply = await sendNativeReply(v2ReceiptCommand("transitionV2", fields));
    if (!exactKeys(reply, ["ok", "revision"])
        || reply.ok !== true || reply.revision !== read.revision + 1) return false;
    read.state = nextState;
    read.revision = reply.revision;
    if (Number.isInteger(options.providerCandidateTabID)) {
      read.providerCandidateTabID = options.providerCandidateTabID;
    }
    if (nextState === v2States.providerDocumentDiscovered) {
      read.providerOwnedTabID = null;
    }
    if (Number.isInteger(options.providerOwnedTabID)) {
      read.providerOwnedTabID = options.providerOwnedTabID;
      read.tabID = options.providerOwnedTabID;
    }
    return true;
  }

  async function bindV2Candidate(read, providerCandidateTabID) {
    if (!read || !Number.isInteger(providerCandidateTabID)
        || providerCandidateTabID < 0) return false;
    // Serialize the tabs.create/document-discovery racers around the native
    // compare-and-swap so a same-ID confirmation never loses to stale local
    // revision state.
    const previous = read.candidateBindingPromise || Promise.resolve();
    const operation = previous.then(async () => {
      if (read.finished) return false;
      if (read.state !== v2States.providerCreationPending
          && read.state !== v2States.providerDocumentDiscovered) {
        return read.providerCandidateTabID === providerCandidateTabID;
      }
      if (Number.isInteger(read.providerCandidateTabID)
          && read.providerCandidateTabID !== providerCandidateTabID) return false;
      const priorRevision = read.revision;
      const wasAlreadyBound = Number.isInteger(read.providerCandidateTabID);
      const reply = await sendNativeReply(v2ReceiptCommand("bindCandidateV2", {
        requestID: read.requestID,
        runtimeGenerationID: config.runtimeGenerationID,
        ownershipNonceDigest: read.ownershipNonceDigest,
        expectedRevision: priorRevision,
        providerCandidateTabID,
      }));
      const expectedRevision = wasAlreadyBound ? priorRevision : priorRevision + 1;
      if (!exactKeys(reply, ["ok", "revision"])
          || reply.ok !== true || reply.revision !== expectedRevision) return false;
      read.providerCandidateTabID = providerCandidateTabID;
      read.revision = reply.revision;
      return true;
    });
    read.candidateBindingPromise = operation.catch(() => false);
    return operation;
  }

  async function removeV2Receipt(read, terminalState) {
    if (!read || !validV2Receipt({
      requestID: read.requestID,
      runtimeGenerationID: config.runtimeGenerationID,
      ownershipNonceDigest: read.ownershipNonceDigest,
      createdAt: read.createdAt,
      expiresAt: read.expiresAt,
      revision: read.revision,
      state: read.state,
    }) || ![v2States.complete, v2States.cancelled, v2States.expired, v2States.failed].includes(terminalState)) {
      return false;
    }
    const reply = await sendNativeReply(v2ReceiptCommand("removeV2", {
      requestID: read.requestID,
      runtimeGenerationID: config.runtimeGenerationID,
      ownershipNonceDigest: read.ownershipNonceDigest,
      expectedRevision: read.revision,
      terminalLifecycleState: terminalState,
    }));
    return exactKeys(reply, ["ok"]) && reply.ok === true;
  }

  function decodeV2Receipt(reply) {
    if (exactKeys(reply, ["found", "ok"]) && reply.ok === true && reply.found === false) {
      return null;
    }
    if (!isPlainObject(reply) || reply.ok !== true || reply.found !== true) return false;
    const allowed = new Set([
      "ok", "found", "schemaVersion", "requestID", "runtimeGenerationID",
      "ownershipNonceDigest", "createdAt", "expiresAt", "lifecycleState",
      "revision", "providerCandidateTabID", "providerOwnedTabID",
    ]);
    if (Object.keys(reply).some((key) => !allowed.has(key)) || reply.schemaVersion !== 3) return false;
    const record = {
      requestID: reply.requestID,
      runtimeGenerationID: reply.runtimeGenerationID,
      ownershipNonceDigest: reply.ownershipNonceDigest,
      createdAt: reply.createdAt,
      expiresAt: reply.expiresAt,
      state: reply.lifecycleState,
      revision: reply.revision,
      providerCandidateTabID: reply.providerCandidateTabID,
      providerOwnedTabID: reply.providerOwnedTabID,
    };
    return validV2Receipt(record) ? record : false;
  }

  function readFromV2Receipt(record) {
    return {
      ...record,
      rawNonce: null,
      tabID: Number.isInteger(record.providerOwnedTabID) ? record.providerOwnedTabID : null,
      createdCandidateTabID: null,
      candidateBindingPromise: Promise.resolve(),
      providerPort: null,
      replacementCandidateTabID: null,
      timeoutID: null,
      removalListener: null,
      replacementListener: null,
      updateListener: null,
      verifiedTab: Number.isInteger(record.providerOwnedTabID)
        ? {id: record.providerOwnedTabID} : null,
      finished: false,
      closingOwnedTab: false,
      removalAlreadyConfirmed: false,
      cleanupOnly: false,
      cleanupTerminalState: v2States.failed,
      resultMessageAccepted: false,
      resultMessageInFlight: false,
      providerFailureReason: null,
      recovered: true,
    };
  }

  function missingTabError(error) {
    const message = typeof error?.message === "string" ? error.message : "";
    return /(?:no|invalid|unknown) tab(?: with id)?|tab .*not found|does not exist/i.test(message);
  }

  async function exactV2TabPresence(tabID) {
    if (!Number.isInteger(tabID) || !api.tabs?.get) return "unknown";
    try {
      const tab = await api.tabs.get(tabID);
      return tab?.id === tabID ? "present" : "unknown";
    } catch (error) {
      return missingTabError(error) ? "absent" : "unknown";
    }
  }

  function terminalEventForV2(state) {
    return state === v2States.complete ? v2Events.complete
      : state === v2States.cancelled ? v2Events.cancel : v2Events.fail;
  }

  async function finalizeAbsentV2Cleanup(read) {
    if (!read || !Number.isInteger(read.providerOwnedTabID)) return false;
    if (read.state !== v2States.cleanupRequested
        && read.state !== v2States.cleanupConfirmed
        && !await transitionV2(read, v2Events.requestCleanup)) return false;
    if (read.state === v2States.cleanupRequested
        && !await transitionV2(read, v2Events.confirmCleanup)) return false;
    const terminalState = read.cleanupTerminalState || v2States.failed;
    if (read.state !== terminalState
        && !await transitionV2(read, terminalEventForV2(terminalState))) return false;
    if (!await removeV2Receipt(read, terminalState)) return false;
    pendingV2Receipt = null;
    ownedTabRecoveryBlocked = false;
    return true;
  }

  async function recoverCleanupOnlyV2(read) {
    read.cleanupOnly = true;
    read.cleanupTerminalState = ownedProviderReducer.isTerminal(read.state)
      ? read.state : v2States.failed;
    const presence = await exactV2TabPresence(read.providerOwnedTabID);
    if (presence === "absent") return await finalizeAbsentV2Cleanup(read);
    pendingV2Receipt = read;
    ownedTabRecoveryBlocked = true;
    if (presence === "present" && Date.now() < Date.parse(read.expiresAt)) {
      scheduleV2Expiry(read);
    }
    return false;
  }

  async function recoverV2Receipt() {
    if (config.browserFamily !== "safari"
        || !requestIDPattern.test(config.runtimeGenerationID || "")) return;
    const reply = await sendNativeReply(v2ReceiptCommand("loadV2", {
      runtimeGenerationID: config.runtimeGenerationID,
    }));
    const record = decodeV2Receipt(reply);
    if (record === null) return;
    if (record === false || record.runtimeGenerationID !== config.runtimeGenerationID) {
      ownedTabRecoveryBlocked = true;
      return;
    }
    const read = readFromV2Receipt(record);
    if (Date.now() >= Date.parse(record.expiresAt)) {
      if (record.state === v2States.requestIntentPersisted
          || record.state === v2States.providerCreationPending
          || record.state === v2States.providerDocumentDiscovered) {
        if (await transitionV2(read, v2Events.expire)
            && await removeV2Receipt(read, v2States.expired)) return;
      }
      if (Number.isInteger(record.providerOwnedTabID)) {
        await recoverCleanupOnlyV2(read);
        return;
      }
      pendingV2Receipt = read;
      ownedTabRecoveryBlocked = true;
      return;
    }
    if (record.state === v2States.cleanupRequested
        || record.state === v2States.cleanupConfirmed) {
      await recoverCleanupOnlyV2(read);
      return;
    }
    pendingV2Receipt = read;
    ownedTabRecoveryBlocked = true;
    scheduleV2Expiry(read);
  }

  function scheduleV2Expiry(read) {
    if (!read || ownedTabExpiryTimer !== null) return;
    const remaining = Math.max(1, Date.parse(read.expiresAt) - Date.now() + 1);
    ownedTabExpiryTimer = setTimeout(() => {
      ownedTabExpiryTimer = null;
      if (pendingV2Receipt?.requestID !== read.requestID) return;
      void (async () => {
        if ([v2States.requestIntentPersisted, v2States.providerCreationPending,
          v2States.providerDocumentDiscovered].includes(read.state)) {
          if (await transitionV2(read, v2Events.expire)
              && await removeV2Receipt(read, v2States.expired)) {
            pendingV2Receipt = null;
            ownedTabRecoveryBlocked = false;
          }
        }
        if (Number.isInteger(read.providerOwnedTabID)) {
          await recoverCleanupOnlyV2(read);
        }
      })();
    }, remaining);
  }

  function exactOwnedProviderSender(port) {
    const sender = port?.sender;
    const senderIDMatches = typeof sender?.id !== "string"
      || typeof api.runtime.id !== "string" || sender.id === api.runtime.id;
    const topFrameMatches = sender?.frameId === 0;
    const declaredOriginMatches = typeof sender?.origin !== "string"
      || sender.origin === extractor.CONTRACT.origin;
    let originMatches = false;
    try {
      const url = new URL(sender?.url || sender?.tab?.url || "");
      originMatches = url.origin === extractor.CONTRACT.origin
        && url.pathname === new URL(extractor.CONTRACT.href).pathname;
    } catch (_) {}
    return senderIDMatches && topFrameMatches && declaredOriginMatches && originMatches
      && Number.isInteger(sender?.tab?.id) && sender.tab.id >= 0;
  }

  function armV2TabLifecycle(read) {
    if (!read || !Number.isInteger(read.providerOwnedTabID)
        || !api.tabs?.onRemoved?.addListener || !api.tabs?.onRemoved?.removeListener) return false;
    const lifecycle = ownedProviderReducer.createTabLifecycleListeners({
      ownedTabID: () => read.providerOwnedTabID,
      isActive: () => automaticRead === read && !read.finished,
      isClosing: () => read.closingOwnedTab,
      defer: (operation) => setTimeout(operation, 0),
      onUnreplacedRemoval: () => {
        read.removalAlreadyConfirmed = true;
        retainRuntimeOperation(finishAutomaticV2(
          read, "tabUnavailable", null, false, "PROVIDER_TAB_CLOSED"
        ));
      },
      onReplacementCandidate: (addedTabID) => {
        read.replacementCandidateTabID = addedTabID;
        read.removalAlreadyConfirmed = false;
        read.providerPort = null;
        read.verifiedTab = null;
      },
    });
    const removalListener = lifecycle.onRemoved;
    const replacementListener = lifecycle.onReplaced;
    const updateListener = (tabID) => {
      if (automaticRead !== read || read.finished
          || tabID !== read.providerOwnedTabID || !read.providerPort) return;
      // Content scripts run in an isolated world and cannot reliably observe a
      // provider SPA's history.pushState/replaceState calls. tabs.onUpdated is
      // used only as a content-free event signal for the already-proven tab;
      // no URL is copied, persisted, or sent across the Port.
      try { read.providerPort.postMessage({
        type: "umaClaudeProviderRouteEventV2",
        requestID: read.requestID,
        runtimeGenerationID: config.runtimeGenerationID,
      }); } catch (_) {}
    };
    read.removalListener = removalListener;
    read.replacementListener = replacementListener;
    read.updateListener = updateListener;
    try {
      api.tabs.onRemoved.addListener(removalListener);
      api.tabs.onReplaced?.addListener?.(replacementListener);
      api.tabs.onUpdated?.addListener?.(updateListener);
      return true;
    } catch (_) {
      try { api.tabs.onRemoved.removeListener(removalListener); } catch (_) {}
      try { api.tabs.onReplaced?.removeListener?.(replacementListener); } catch (_) {}
      try { api.tabs.onUpdated?.removeListener?.(updateListener); } catch (_) {}
      read.removalListener = null;
      read.replacementListener = null;
      read.updateListener = null;
      return false;
    }
  }

  function removeV2Lifecycle(read) {
    if (!read) return;
    try { api.tabs?.onRemoved?.removeListener?.(read.removalListener); } catch (_) {}
    try { api.tabs?.onReplaced?.removeListener?.(read.replacementListener); } catch (_) {}
    try { api.tabs?.onUpdated?.removeListener?.(read.updateListener); } catch (_) {}
    read.removalListener = null;
    read.replacementListener = null;
    read.updateListener = null;
  }

  async function cleanupV2(read, terminalState) {
    if (!read) return false;
    if (!Number.isInteger(read.providerOwnedTabID) || !read.providerPort) {
      // No trusted live content-script proof means no close authority.
      pendingV2Receipt = read;
      ownedTabRecoveryBlocked = true;
      scheduleV2Expiry(read);
      return false;
    }
    if (read.state !== v2States.cleanupRequested
        && read.state !== v2States.cleanupConfirmed
        && !await transitionV2(read, v2Events.requestCleanup)) return false;
    if (!read.removalAlreadyConfirmed) {
      read.closingOwnedTab = true;
      try {
        await api.tabs.remove(read.providerOwnedTabID);
      } catch (_) {
        read.closingOwnedTab = false;
        pendingV2Receipt = read;
        ownedTabRecoveryBlocked = true;
        return false;
      }
    }
    if (read.state === v2States.cleanupRequested
        && !await transitionV2(read, v2Events.confirmCleanup)) return false;
    if (!await transitionV2(read, terminalEventForV2(terminalState))) return false;
    if (!await removeV2Receipt(read, terminalState)) return false;
    pendingV2Receipt = null;
    ownedTabRecoveryBlocked = false;
    return true;
  }

  async function finishAutomaticV2(
    read,
    status,
    observation,
    suppressTerminal = false,
    providerFailureReason = null
  ) {
    if (!read || automaticRead !== read || read.finished) return "ownedTabOwnershipLost";
    read.finished = true;
    if (read.timeoutID !== null) clearTimeout(read.timeoutID);
    let finalStatus = status;
    if (!read.ownershipNonceDigest) {
      if (!suppressTerminal) {
        await sendNative(terminalEnvelope(read.requestID, finalStatus));
      }
      companionLifecycleState = automaticReadStates.failed;
      transitionCompanion(automaticReadStates.nativeBridgeReady);
      if (automaticRead === read) automaticRead = null;
      return finalStatus;
    }
    let retainedObservation = null;
    let retainedProviderFailureReason = status === "refreshCompleted"
      ? null
      : providerFailureReasons.has(providerFailureReason) ? providerFailureReason : null;
    if (status === "refreshCompleted" && extractor.validateObservation(observation)) {
      if (read.state !== v2States.resultReady
          || !await transitionV2(read, v2Events.deliverResult)) {
        finalStatus = "usageUnavailable";
      } else {
        // Keep the sanitized result in extension memory until both the proven
        // provider tab and its durable ownership receipt are gone. Nothing is
        // published to the Host while cleanup can still fail.
        retainedObservation = observationEnvelope(read.requestID, observation);
      }
    } else if (status === "refreshCompleted") {
      finalStatus = "usageUnavailable";
    }
    const terminal = finalStatus === "refreshCompleted" ? v2States.complete
      : finalStatus === "ownedTabClosed" ? v2States.cancelled : v2States.failed;
    const cleaned = await cleanupV2(read, terminal);
    if (!cleaned) {
      finalStatus = "ownedTabOwnershipLost";
      retainedObservation = null;
      // Cleanup integrity outranks the provider classification. Publishing the
      // earlier page reason here would obscure that the proven tab/receipt
      // lifecycle did not complete.
      retainedProviderFailureReason = null;
    }
    removeV2Lifecycle(read);
    try { read.providerPort?.disconnect?.(); } catch (_) {}
    if (!suppressTerminal) {
      await sendNative(terminalEnvelope(
        read.requestID,
        finalStatus,
        finalStatus === "refreshCompleted" ? retainedObservation : null,
        null,
        finalStatus === "refreshCompleted" ? null : retainedProviderFailureReason
      ));
    }
    companionLifecycleState = finalStatus === "refreshCompleted"
      ? automaticReadStates.complete : automaticReadStates.failed;
    transitionCompanion(automaticReadStates.nativeBridgeReady);
    if (automaticRead === read) automaticRead = null;
    return finalStatus;
  }

  async function acceptV2ProviderOwnership(read, port, ownershipNonce) {
    if (!read || read.finished || !exactOwnedProviderSender(port)) return false;
    const senderTabID = port.sender.tab.id;

    // A previously persisted ownership proof survives a background reload.
    // It may reconnect only from the exact same proven tab ID and never causes
    // extraction to restart while EXTRACTING.
    if ([v2States.providerOwnershipProven, v2States.providerReady,
      v2States.extracting, v2States.resultReady, v2States.resultDelivered,
      v2States.cleanupRequested, v2States.cleanupConfirmed].includes(read.state)
        && read.providerOwnedTabID === senderTabID) {
      read.providerPort = port;
      read.rawNonce = ownershipNonce;
      if (!read.removalListener && !armV2TabLifecycle(read)) return false;
      port.postMessage({
        type: "umaClaudeProviderOwnershipAcceptedV2",
        requestID: read.requestID,
        runtimeGenerationID: config.runtimeGenerationID,
      });
      if (read.cleanupOnly) {
        await finishAutomaticV2(read, "ownedTabOwnershipLost");
      }
      return true;
    }

    const expectedCandidate = Number.isInteger(read.replacementCandidateTabID)
      ? read.replacementCandidateTabID : read.providerCandidateTabID;
    // Discovery may beat tabs.create's Promise. Persist DOCUMENT_DISCOVERED,
    // retain the Port in memory, and wait; sender.tab.id is not ownership until
    // the browser-created ID independently matches it.
    if (!Number.isInteger(expectedCandidate)) return false;
    if (!read.recovered && !Number.isInteger(read.replacementCandidateTabID)
        && read.createdCandidateTabID !== expectedCandidate) return false;
    if (expectedCandidate !== senderTabID) {
      await finishAutomaticV2(read, "ownedTabOwnershipLost");
      return false;
    }
    if (read.state !== v2States.providerDocumentDiscovered
        || read.providerCandidateTabID !== senderTabID
        || !await transitionV2(read, v2Events.proveProviderOwnership, {
          providerOwnedTabID: senderTabID,
        })) return false;

    read.rawNonce = ownershipNonce;
    read.providerPort = port;
    read.providerOwnedTabID = senderTabID;
    read.tabID = senderTabID;
    read.verifiedTab = {id: senderTabID};
    read.replacementCandidateTabID = null;
    read.pendingProviderDiscovery = null;
    pendingV2Receipt = null;
    ownedTabRecoveryBlocked = false;
    if (!read.removalListener && !armV2TabLifecycle(read)) return false;
    port.postMessage({
      type: "umaClaudeProviderOwnershipAcceptedV2",
      requestID: read.requestID,
      runtimeGenerationID: config.runtimeGenerationID,
    });
    return true;
  }

  function v2RecoveryStateAllowed(state) {
    return [
      v2States.providerOwnershipProven,
      v2States.providerReady,
      v2States.extracting,
      v2States.resultReady,
      v2States.resultDelivered,
      v2States.cleanupRequested,
      v2States.cleanupConfirmed,
    ].includes(state);
  }

  async function handleV2RecoveryMessage(port, message, context) {
    if (config.browserFamily !== "safari"
        || !exactOwnedProviderSender(port) || !isPlainObject(message)) return;
    if (message.type === "umaClaudeProviderRecoveryCandidateV2") {
      if (!exactKeys(message, ["type"]) || context.challenge !== null) return;
      await ownedTabRecoveryPromise;
      const read = automaticRead || pendingV2Receipt;
      if (!read || read.finished || !v2RecoveryStateAllowed(read.state)
          || read.runtimeGenerationID !== config.runtimeGenerationID
          || read.providerOwnedTabID !== port.sender.tab.id
          || (Date.now() >= Date.parse(read.expiresAt) && !read.cleanupOnly)) return;
      const challengeID = root.crypto?.randomUUID?.();
      if (!requestIDPattern.test(challengeID || "")) return;
      context.challenge = {
        challengeID: challengeID.toLowerCase(),
        requestID: read.requestID,
        runtimeGenerationID: config.runtimeGenerationID,
        revision: read.revision,
        lifecycleState: read.state,
        providerOwnedTabID: read.providerOwnedTabID,
      };
      port.postMessage({
        type: "umaClaudeProviderRecoveryChallengeV2",
        challengeID: context.challenge.challengeID,
        requestID: context.challenge.requestID,
        runtimeGenerationID: context.challenge.runtimeGenerationID,
      });
      return;
    }
    if (message.type !== "umaClaudeProviderRecoveryResponseV2"
        || !exactKeys(message, ["challengeID", "requestID", "runtimeGenerationID", "type"])
        || !context.challenge
        || message.challengeID !== context.challenge.challengeID
        || message.requestID !== context.challenge.requestID
        || message.runtimeGenerationID !== context.challenge.runtimeGenerationID) return;

    const read = automaticRead || pendingV2Receipt;
    if (!read || read.finished || read.requestID !== context.challenge.requestID
        || read.runtimeGenerationID !== context.challenge.runtimeGenerationID
        || read.revision !== context.challenge.revision
        || read.state !== context.challenge.lifecycleState
        || read.providerOwnedTabID !== context.challenge.providerOwnedTabID
        || read.providerOwnedTabID !== port.sender.tab.id
        || !v2RecoveryStateAllowed(read.state)
        || (Date.now() >= Date.parse(read.expiresAt) && !read.cleanupOnly)) return;
    context.challenge = null;
    if (!automaticRead) {
      automaticRead = read;
      read.finished = false;
      read.timeoutID = setTimeout(() => {
        void finishAutomaticV2(read, "tabUnavailable");
      }, automaticTimeoutMilliseconds);
    }
    read.providerPort = port;
    read.verifiedTab = {id: read.providerOwnedTabID};
    pendingV2Receipt = null;
    ownedTabRecoveryBlocked = false;
    if (!read.removalListener && !armV2TabLifecycle(read)) return;
    port.postMessage({
      type: "umaClaudeProviderRecoveryAcceptedV2",
      requestID: read.requestID,
      runtimeGenerationID: config.runtimeGenerationID,
    });

    if (read.cleanupOnly) {
      await finishAutomaticV2(read, "ownedTabOwnershipLost");
      return;
    }

    // Only states before extraction may resume extraction. A reload during or
    // after extraction fails closed rather than issuing a duplicate provider read.
    if (read.state === v2States.providerOwnershipProven
        && !await transitionV2(read, v2Events.providerReady)) {
      await finishAutomaticV2(read, "ownedTabOwnershipLost");
      return;
    }
    if (read.state === v2States.providerReady) {
      if (!await transitionV2(read, v2Events.beginExtraction)) {
        await finishAutomaticV2(read, "ownedTabOwnershipLost");
        return;
      }
      port.postMessage({
        type: "umaClaudeExtractProviderUsageV2",
        requestID: read.requestID,
        runtimeGenerationID: config.runtimeGenerationID,
      });
      return;
    }
    // The isolated content script owns the sole sanitized result projection.
    // After a background reload it may retransmit that exact correlated result
    // once; do not restart extraction and do not classify the reload as failure.
    if (read.state === v2States.extracting || read.state === v2States.resultReady) return;
    await finishAutomaticV2(read, "usageUnavailable");
  }

  async function handleV2ProviderMessage(port, message) {
    if (!exactOwnedProviderSender(port) || !isPlainObject(message)) return;
    if (message.type === "umaClaudeProviderDocumentDiscoveredV2") {
      if (!exactKeys(message, ["ownershipNonce", "type"])
          || !providerOwnership.markerPattern.test(message.ownershipNonce || "")) return;
      await ownedTabRecoveryPromise;
      const digest = await providerOwnership.nonceDigest(message.ownershipNonce);
      let read = automaticRead || pendingV2Receipt;
      if (!read || digest !== read.ownershipNonceDigest
          || read.runtimeGenerationID && read.runtimeGenerationID !== config.runtimeGenerationID) return;
      const senderTabID = port.sender.tab.id;
      if (read.replacementCandidateTabID !== null
          && senderTabID !== read.replacementCandidateTabID) return;
      if (!automaticRead) {
        automaticRead = read;
        read.rawNonce = message.ownershipNonce;
        read.finished = false;
        read.timeoutID = setTimeout(() => {
          void finishAutomaticV2(read, "tabUnavailable");
        }, automaticTimeoutMilliseconds);
      }
      if (read.state === v2States.providerOwnershipProven
          || read.state === v2States.providerReady) {
        if (read.providerOwnedTabID !== senderTabID) {
          // A second Port cannot nominate itself as a replacement. Only the
          // browser's correlated onReplaced event may supply that candidate.
          if (!Number.isInteger(read.replacementCandidateTabID)
              || read.replacementCandidateTabID !== senderTabID) return;
          if (!await transitionV2(read, v2Events.replacementRequiresReproof, {
            providerCandidateTabID: senderTabID,
          })) return;
        }
      }
      if (read.state === v2States.providerCreationPending) {
        if (!await bindV2Candidate(read, senderTabID)) {
          await finishAutomaticV2(read, "ownedTabOwnershipLost");
          return;
        }
      }
      read.pendingProviderDiscovery = {
        port,
        ownershipNonce: message.ownershipNonce,
        senderTabID,
      };
      // A live request requires tabs.create's returned ID to corroborate the
      // trusted Port sender before proof. A recovered pending receipt can use
      // its durable candidate CAS because the old in-memory create result no
      // longer exists.
      const candidateConfirmed = read.recovered
        || Number.isInteger(read.replacementCandidateTabID)
        || read.createdCandidateTabID === senderTabID;
      if (read.state === v2States.providerCreationPending && candidateConfirmed
          && !await transitionV2(read, v2Events.discoverProviderDocument)) return;
      await acceptV2ProviderOwnership(read, port, message.ownershipNonce);
      return;
    }

    const read = automaticRead;
    if (!read || read.finished || read.providerPort !== port
        || port.sender.tab.id !== read.providerOwnedTabID
        || message.requestID !== read.requestID
        || message.runtimeGenerationID !== config.runtimeGenerationID) return;
    if (message.type === "umaClaudeProviderReadyV2"
        && exactKeys(message, ["requestID", "runtimeGenerationID", "type"])) {
      const becameReady = read.state === v2States.providerOwnershipProven
        ? await transitionV2(read, v2Events.providerReady)
        : read.state === v2States.providerReady;
      if (becameReady && await transitionV2(read, v2Events.beginExtraction)) {
        port.postMessage({
          type: "umaClaudeExtractProviderUsageV2",
          requestID: read.requestID,
          runtimeGenerationID: config.runtimeGenerationID,
        });
      }
      return;
    }
    if (message.type === "umaClaudeProviderMarkerRemovalFailedV2"
        && exactKeys(message, ["requestID", "runtimeGenerationID", "type"])) {
      await finishAutomaticV2(read, "ownedTabOwnershipLost");
      return;
    }
    if (message.type === "umaClaudeProviderResultV2"
        && resultStatuses.includes(message.status)) {
      const expected = message.status === "success"
        ? ["observation", "requestID", "runtimeGenerationID", "status", "type"]
        : ["providerFailureReason", "requestID", "runtimeGenerationID", "status", "type"];
      const retransmittable = read.recovered && read.state === v2States.resultReady;
      if (!exactKeys(message, expected)
          || (message.status !== "success"
            && !providerFailureReasons.has(message.providerFailureReason))
          || ![v2States.extracting, v2States.resultReady].includes(read.state)
          || (read.state === v2States.resultReady && !retransmittable)
          || read.resultMessageAccepted || read.resultMessageInFlight) return;
      read.resultMessageInFlight = true;
      const resultCaptured = read.state === v2States.resultReady
        || await transitionV2(read, v2Events.captureResult);
      if (!resultCaptured) {
        read.resultMessageInFlight = false;
        return;
      }
      read.resultMessageAccepted = true;
      read.providerFailureReason = message.status === "success"
        ? null : message.providerFailureReason;
      port.postMessage({
        type: "umaClaudeProviderResultAcceptedV2",
        requestID: read.requestID,
        runtimeGenerationID: config.runtimeGenerationID,
      });
      if (message.status === "success" && extractor.validateObservation(message.observation)) {
        await finishAutomaticV2(read, "refreshCompleted", message.observation);
      } else if (message.status === "success") {
        await finishAutomaticV2(
          read, "usageUnavailable", null, false, "EXTRACTION_VALIDATION_FAILED"
        );
      } else {
        await finishAutomaticV2(
          read, message.status, null, false, message.providerFailureReason
        );
      }
    }
  }

  async function beginAutomaticRead(requestID) {
    if (!requestIDPattern.test(requestID)) return;
    if (automaticRead) {
      await sendNative(automationEnvelope(requestID, "usageUnavailable"));
      return;
    }
    await ownedTabRecoveryPromise;
    if (ownedTabRecoveryBlocked) {
      await sendNative(automationEnvelope(requestID, "ownedTabOwnershipLost"));
      return;
    }
    const read = {
      requestID,
      runtimeGenerationID: config.runtimeGenerationID,
      state: v2States.idle,
      revision: 0,
      rawNonce: null,
      ownershipNonceDigest: null,
      createdAt: null,
      expiresAt: null,
      createdCandidateTabID: null,
      candidateBindingPromise: Promise.resolve(),
      providerCandidateTabID: null,
      providerOwnedTabID: null,
      providerPort: null,
      replacementCandidateTabID: null,
      pendingProviderDiscovery: null,
      timeoutID: null,
      removalListener: null,
      replacementListener: null,
      updateListener: null,
      verifiedTab: null,
      finished: false,
      closingOwnedTab: false,
      removalAlreadyConfirmed: false,
      cleanupOnly: false,
      cleanupTerminalState: v2States.failed,
      resultMessageAccepted: false,
      resultMessageInFlight: false,
      providerFailureReason: null,
      recovered: false,
    };
    automaticRead = read;
    companionLifecycleState = automaticReadStates.requestAccepted;
    if (!(await sendNative(automationEnvelope(requestID, "refreshStarted")))) {
      read.finished = true;
      read.state = automaticReadStates.failed;
      companionLifecycleState = automaticReadStates.failed;
      transitionCompanion(automaticReadStates.nativeBridgeReady);
      automaticRead = null;
      return;
    }

    transitionCompanion(automaticReadStates.sitePermissionChecking);
    if (!(await persistentUsageAccessGranted())) {
      await finishAutomaticV2(
        read, "permissionRequired", null, false, "SITE_PERMISSION_MISSING"
      );
      return;
    }
    if (!api.tabs?.create || !api.tabs?.remove
        || !api.tabs?.onRemoved?.addListener || !api.tabs?.onRemoved?.removeListener) {
      await finishAutomaticV2(read, "tabUnavailable");
      return;
    }
    if (!await saveV2Intent(read)) {
      await finishAutomaticV2(read, "ownedTabOwnershipLost");
      return;
    }
    if (!await transitionV2(read, v2Events.beginProviderCreation)) {
      await finishAutomaticV2(read, "ownedTabOwnershipLost");
      return;
    }
    const providerURL = providerOwnership.providerURLForNonce(read.rawNonce);
    if (!providerURL) {
      await finishAutomaticV2(read, "tabUnavailable");
      return;
    }
    read.timeoutID = setTimeout(() => {
      void finishAutomaticV2(read, "tabUnavailable");
    }, automaticTimeoutMilliseconds);
    try {
      const tab = await api.tabs.create({ url: providerURL, active: false });
      // create() is only advisory lifecycle evidence. Ownership is established
      // exclusively by the provider document Port's trusted sender.tab.id.
      if (!Number.isInteger(tab?.id)) {
        await finishAutomaticV2(read, "ownedTabOwnershipLost");
        return;
      }
      if (!await bindV2Candidate(read, tab.id)) {
        await finishAutomaticV2(read, "ownedTabOwnershipLost");
        return;
      }
      read.createdCandidateTabID = tab.id;
      const pending = read.pendingProviderDiscovery;
      if (pending) {
        if (pending.senderTabID !== tab.id
            || read.providerCandidateTabID !== tab.id
            || (read.state === v2States.providerCreationPending
              && !await transitionV2(read, v2Events.discoverProviderDocument))) {
          await finishAutomaticV2(read, "ownedTabOwnershipLost");
          return;
        }
        await acceptV2ProviderOwnership(read, pending.port, pending.ownershipNonce);
      }
    } catch (_) {
      pendingV2Receipt = read;
      ownedTabRecoveryBlocked = true;
      scheduleV2Expiry(read);
      await finishAutomaticV2(read, "tabUnavailable");
      return;
    }
  }

  async function closeOwnedRead(requestID, targetRequestID) {
    if (!requestIDPattern.test(requestID)
        || !requestIDPattern.test(targetRequestID)
        || requestID === targetRequestID) return;
    const read = automaticRead;
    if (read && !read.finished && read.requestID === targetRequestID) {
      const status = await finishAutomaticV2(read, "ownedTabClosed", null, true);
      await sendNative(terminalEnvelope(
        requestID,
        status === "ownedTabClosed" ? "ownedTabClosed" : "ownedTabOwnershipLost",
        null,
        targetRequestID
      ));
      return;
    }
    await sendNative(terminalEnvelope(
      requestID, "ownedTabOwnershipLost", null, targetRequestID
    ));
  }

  function validatedCommand(value) {
    if (!isPlainObject(value)
        || typeof value.command !== "string"
        || !requestIDPattern.test(value.requestID || "")) return null;
    if (value.command === config.closeOwnedTabMessageName) {
      return exactKeys(value, ["command", "requestID", "targetRequestID"])
        && requestIDPattern.test(value.targetRequestID || "")
        && value.targetRequestID !== value.requestID
        ? value
        : null;
    }
    return exactKeys(value, ["command", "requestID"]) ? value : null;
  }

  function unpackNativeCommand(message) {
    const direct = validatedCommand(message);
    if (direct) return direct;
    if (!exactKeys(message, ["name", "userInfo"])) return null;
    const wrapped = validatedCommand(message.userInfo);
    return wrapped && message.name === wrapped.command ? wrapped : null;
  }

  function handleCommandMessage(message, portGeneration) {
    if (!isCurrentContainingAppPort(portGeneration)) return;
    const command = unpackNativeCommand(message);
    if (!command || !requestIDPattern.test(command.requestID)) return;
    if (command.command === config.wakeMessageName) {
      // Wake and qualification are separate lifecycle phases. On a cold
      // launch Safari may accept this dispatch before the port listener exists;
      // the signed background-ready receipt below causes the Host to dispatch
      // the actual correlated qualification only after the port is ready.
      retainRuntimeOperation(announceBackgroundReady(command.requestID, portGeneration));
    } else if (command.command === runtimeQualificationMessageName) {
      // The signed handler creates the reply from its own Bundle metadata.
      // Only after JavaScript validates and acknowledges that exact correlated
      // reply may the handler publish bridgeReady to the containing app.
      retainRuntimeOperation(qualifyRuntime(command.requestID, portGeneration));
    } else if (command.command === config.automaticRefreshMessageName) {
      retainRuntimeOperation(beginAutomaticRead(command.requestID));
    } else if (command.command === config.closeOwnedTabMessageName) {
      retainRuntimeOperation(closeOwnedRead(command.requestID, command.targetRequestID));
    }
  }

  function scheduleContainingAppPortReconnect(disconnectedGeneration) {
    if (containingAppReconnectScheduled
        || containingAppReconnectBudget <= 0
        || disconnectedGeneration !== containingAppPortGeneration) return;
    containingAppReconnectBudget -= 1;
    containingAppReconnectScheduled = true;
    const ticket = ++containingAppReconnectTicket;
    Promise.resolve().then(() => {
      if (ticket !== containingAppReconnectTicket) return;
      containingAppReconnectScheduled = false;
      if (containingAppPortState === "disconnected") installContainingAppPort();
    });
  }

  function installContainingAppPort() {
    if (config.browserFamily !== "safari"
        || containingAppPortState !== "disconnected"
        || typeof api.runtime.connectNative !== "function") return;
    if (companionLifecycleState === automaticReadStates.dormant) {
      transitionCompanion(automaticReadStates.starting);
    }
    transitionCompanion(automaticReadStates.nativeBridgeConnecting);
    containingAppPortState = "connecting";
    const generation = ++containingAppPortGeneration;
    try {
      const port = api.runtime.connectNative(config.nativeApplication);
      if (!port?.onMessage?.addListener || !port?.onDisconnect?.addListener) {
        containingAppPortState = "disconnected";
        transitionCompanion(automaticReadStates.starting);
        scheduleContainingAppPortReconnect(generation);
        return;
      }
      containingAppPort = port;
      port.onMessage.addListener((message) => {
        if (containingAppPort !== port
            || containingAppPortGeneration !== generation
            || containingAppPortState !== "ready") return;
        containingAppReconnectBudget = 1;
        handleCommandMessage(message, generation);
      });
      port.onDisconnect.addListener(() => {
        if (containingAppPort !== port
            || containingAppPortGeneration !== generation) return;
        containingAppPort = null;
        containingAppPortState = "disconnected";
        const interrupted = automaticRead;
        if (interrupted && !interrupted.finished) {
          void finishAutomaticV2(interrupted, "usageUnavailable").finally(() => {
            transitionCompanion(automaticReadStates.starting);
            scheduleContainingAppPortReconnect(generation);
          });
        } else {
          transitionCompanion(automaticReadStates.starting);
          scheduleContainingAppPortReconnect(generation);
        }
      });
      containingAppPortState = "ready";
      transitionCompanion(automaticReadStates.nativeBridgeReady);
      const startupRequestID = root.crypto?.randomUUID?.();
      if (requestIDPattern.test(startupRequestID || "")) {
        retainRuntimeOperation(
          announceBackgroundReady(startupRequestID.toLowerCase(), generation)
        );
      }
    } catch (_) {
      containingAppPort = null;
      containingAppPortState = "disconnected";
      transitionCompanion(automaticReadStates.starting);
      scheduleContainingAppPortReconnect(generation);
    }
  }

  api.runtime.onMessage.addListener((message, sender) => {
    void handleContentResult(message, sender);
  });

  api.runtime.onConnect?.addListener((port) => {
    if (![v2PortName, v2RecoveryPortName].includes(port?.name)
        || !port.onMessage?.addListener || !port.postMessage) return;
    const recoveryContext = {challenge: null};
    port.onMessage.addListener((message) => {
      retainRuntimeOperation(port.name === v2PortName
        ? handleV2ProviderMessage(port, message)
        : handleV2RecoveryMessage(port, message, recoveryContext));
    });
  });

  if (config.supportsManualAction) {
    api.action?.onClicked?.addListener((tab) => {
      void (async () => {
        if (allowedSenderURL(tab?.url || "") && await injectExactUsageRoute(tab?.id)) {
          try { await api.tabs.sendMessage(tab.id, { type: extractUsageMessage }); } catch (_) {}
        }
      })();
    });
  }

  // Recover only the one content-free V2 receipt. A surviving provider content
  // script must re-present its in-memory nonce through a trusted Port; recovery
  // never enumerates tabs and never closes an unproven tab.
  ownedTabRecoveryPromise = recoverV2Receipt();

  // Safari delivers SFSafariApplication.dispatchMessage payloads only through
  // a containing-app native port. Install exactly one port for the lifetime of
  // this persistent background page; failure remains closed until reload.
  installContainingAppPort();
})(globalThis);
