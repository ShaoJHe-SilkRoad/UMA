/*
 * AUV Browser Companion for Claude — Chrome/Edge service worker (Windows).
 *
 * This is the Chromium counterpart of the Mac Safari companion's background page
 * (BrowserExtension/Shared/background-core.js). The read itself is unchanged: an
 * owned tab proven by a one-shot nonce, the shared extractor, the same lifecycle
 * reducer and the same timings. What differs is the transport and where the
 * receipt lives:
 *   - one runtime.connectNative port to AUV.BrowserHost.exe carries AUV's commands
 *     in and this companion's events and terminal packets out (it also keeps this
 *     MV3 service worker alive, Chrome 105+);
 *   - the content-free ownership receipt is kept in chrome.storage.session with the
 *     same compare-and-swap rules the Safari native handler applies.
 * Only normalized plan-limit percentages, reset times and the observation time ever
 * leave this worker. No URL, page text, cookie or account data is sent.
 */
(function (root) {
  "use strict";

  const extractor = root.UMAClaudeUsageExtractor;
  const providerOwnership = root.UMAProviderOwnershipV2;
  const ownedProviderReducer = root.UMAOwnedProviderTabV2Reducer;
  const config = root.UMA_BROWSER_CONFIG;
  const api = root.chrome;
  if (!extractor || !providerOwnership || !ownedProviderReducer || !config || !api?.runtime) return;

  const resultStatuses = Object.freeze(["success", "signInRequired", "routeRejected", "usageUnavailable"]);
  const providerFailureReasons = new Set([
    "ROUTE_NOT_READY", "ROUTE_READINESS_TIMEOUT", "PROVIDER_DOCUMENT_NOT_READY",
    "TARGET_DATA_NOT_READY", "TARGET_DATA_TIMEOUT", "PROVIDER_STRUCTURE_UNSUPPORTED",
    "PROVIDER_SESSION_UNAVAILABLE", "SITE_PERMISSION_MISSING",
    "EXTRACTION_VALIDATION_FAILED", "REQUEST_CANCELLED", "PROVIDER_TAB_CLOSED",
  ]);
  const requestIDPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const automaticTimeoutMilliseconds = 30_000;
  const extractionNudgeMilliseconds = 1_000;
  // Mac 0.18.4: a page that has not answered for this long is treated as suspended;
  // the read ends early and AUV retries 20 seconds after the sync started.
  const silentPageMilliseconds = 6_000;
  const pageTraceKind = "umaCompanionPageTraceV1";
  const pageProgressSteps = new Set([
    "extractReceived", "dataSeen", "extractorThrew", "deadlineFired",
    "resultPostedBy-mutation", "resultPostedBy-frame", "resultPostedBy-timer",
    "resultPostedBy-routeEvent", "resultPostedBy-deadline", "resultResent",
  ]);
  const placements = Object.freeze(["backgroundTab", "minimizedWindow"]);
  const temporaryWindowSize = Object.freeze({ width: 480, height: 640 });
  const ownedTabReceiptMaximumAgeMilliseconds = 2 * 60 * 1_000;
  const receiptStorageKey = "auvOwnedTabReceiptV3";
  const selfReloadStampKey = "auvCompanionLastSelfReload";
  const reconnectDelays = Object.freeze([0, 1_000, 5_000, 15_000, 60_000]);
  const livenessAlarm = "auvCompanionLiveness";
  const livenessReplyMilliseconds = 8_000;
  const livenessMissesBeforeReload = 2;
  const hostIdleRenewalMilliseconds = 5 * 60_000;
  const selfReloadMinimumSpacingMilliseconds = 30 * 60_000;
  // 0.18.6: AUV asks a companion from another build to reload itself, which loads the build
  // AUV installed into the same folder. Spaced like AUV's own request, at least 10 minutes.
  const updateReloadStampKey = "auvCompanionLastUpdateReload";
  const updateReloadMinimumSpacingMilliseconds = 10 * 60_000;
  const handledCommandLimit = 64;
  const v2PortName = "umaClaudeOwnedProviderV2";

  const v2States = ownedProviderReducer.STATES;
  const v2Events = ownedProviderReducer.EVENTS;

  let automaticRead = null;
  let ownedTabRecoveryBlocked = false;
  let ownedTabRecoveryPromise = null;
  let pendingV2Receipt = null;
  let ownedTabExpiryTimer = null;
  const handledCommands = new Set();
  const activeRuntimeOperations = new Set();

  function retainRuntimeOperation(operation) {
    const retained = Promise.resolve(operation);
    activeRuntimeOperations.add(retained);
    void retained.finally(() => activeRuntimeOperations.delete(retained)).catch(() => {});
  }
  function isPlainObject(value) {
    return Boolean(value) && Object.getPrototypeOf(value) === Object.prototype;
  }
  function exactKeys(value, expected) {
    return isPlainObject(value) && Object.keys(value).sort().join(",") === expected.slice().sort().join(",");
  }
  function newRequestID() {
    return root.crypto.randomUUID().toLowerCase();
  }

  // ---- Native port to AUV.BrowserHost.exe ----

  let nativePort = null;
  let nativeGeneration = 0;
  let reconnectAttempt = 0;
  let reconnectTicket = 0;
  let reconnectScheduled = false;
  let hostLastHeardAt = Date.now();
  let hostMessages = 0;
  let appConnected = false;
  let livenessMisses = 0;
  let livenessPending = null;

  function postNative(payload) {
    if (!nativePort) return false;
    try { nativePort.postMessage(payload); return true; } catch (_) { return false; }
  }
  // The Safari handler answered every native message with {ok}. Chrome's port has
  // no reply, so a send that reached the port counts as delivered; AUV's own
  // deadlines cover anything lost after that.
  async function sendNative(payload) {
    return postNative(payload);
  }

  function scheduleReconnect(disconnectedGeneration) {
    if (reconnectScheduled || disconnectedGeneration !== nativeGeneration) return;
    const delay = reconnectDelays[Math.min(reconnectAttempt, reconnectDelays.length - 1)];
    reconnectAttempt += 1;
    reconnectScheduled = true;
    const ticket = ++reconnectTicket;
    const reconnect = () => {
      if (ticket !== reconnectTicket) return;
      reconnectScheduled = false;
      if (!nativePort) installNativePort();
    };
    if (delay === 0) Promise.resolve().then(reconnect);
    else setTimeout(reconnect, delay);
  }

  function installNativePort() {
    if (nativePort || typeof api.runtime.connectNative !== "function") return;
    const generation = ++nativeGeneration;
    let port;
    try { port = api.runtime.connectNative(config.nativeApplication); } catch (_) { port = null; }
    if (!port?.onMessage?.addListener || !port?.onDisconnect?.addListener) {
      scheduleReconnect(generation);
      return;
    }
    nativePort = port;
    hostLastHeardAt = Date.now();
    port.onMessage.addListener((message) => {
      if (nativePort !== port || nativeGeneration !== generation) return;
      hostLastHeardAt = Date.now();
      hostMessages += 1;
      reconnectAttempt = 0;
      handleNativeMessage(message);
    });
    port.onDisconnect.addListener(() => {
      void api.runtime.lastError;
      if (nativePort !== port || nativeGeneration !== generation) return;
      nativePort = null;
      appConnected = false;
      const interrupted = automaticRead;
      if (interrupted && !interrupted.finished) {
        void finishAutomaticV2(interrupted, "usageUnavailable").finally(() => scheduleReconnect(generation));
      } else {
        scheduleReconnect(generation);
      }
    });
  }

  function renewNativePort() {
    const idle = nativePort;
    nativePort = null;
    appConnected = false;
    reconnectTicket += 1;
    reconnectScheduled = false;
    try { idle?.disconnect?.(); } catch (_) {}
    installNativePort();
  }

  // Reloading is the last resort, spaced out so a host that stays gone cannot keep
  // restarting the companion. When that is not enough, AUV asks the person to
  // reload the companion or restart the browser.
  async function reloadCompanionIfAllowed() {
    if (typeof api.runtime.reload !== "function" || !api.storage?.local) return;
    try {
      const stored = await api.storage.local.get(selfReloadStampKey);
      const last = Number(stored?.[selfReloadStampKey]);
      const elapsed = Date.now() - last;
      if (last > 0 && elapsed >= 0 && elapsed < selfReloadMinimumSpacingMilliseconds) return;
      await api.storage.local.set({ [selfReloadStampKey]: Date.now() });
    } catch (_) {
      return;
    }
    livenessMisses = 0;
    api.runtime.reload();
  }

  // A read in progress is never interrupted; AUV asks again after its own spacing.
  async function reloadForUpdate() {
    if (automaticRead || typeof api.runtime.reload !== "function" || !api.storage?.local) return;
    try {
      const stored = await api.storage.local.get(updateReloadStampKey);
      const last = Number(stored?.[updateReloadStampKey]);
      const elapsed = Date.now() - last;
      if (last > 0 && elapsed >= 0 && elapsed < updateReloadMinimumSpacingMilliseconds) return;
      if (automaticRead) return;
      await api.storage.local.set({ [updateReloadStampKey]: Date.now() });
    } catch (_) {
      return;
    }
    api.runtime.reload();
  }

  // Once a minute (an alarm also wakes a worker the browser stopped): reconnect a
  // missing port, ask the host whether it is alive, and replace a port that has
  // gone quiet. A read in progress is never interrupted.
  async function checkLiveness() {
    if (!nativePort) { installNativePort(); return; }
    if (automaticRead) return;
    if (Date.now() - hostLastHeardAt >= hostIdleRenewalMilliseconds) {
      livenessMisses += 1;
      if (livenessMisses >= livenessMissesBeforeReload) { await reloadCompanionIfAllowed(); return; }
      renewNativePort();
      return;
    }
    if (livenessPending) return;
    const pingID = newRequestID();
    const before = hostMessages;
    livenessPending = pingID;
    postNative({ kind: "auvCompanionPing", schemaVersion: 1, pingID });
    await new Promise((resolve) => setTimeout(resolve, livenessReplyMilliseconds));
    livenessPending = null;
    if (hostMessages > before) { livenessMisses = 0; return; }
    livenessMisses += 1;
    if (livenessMisses >= livenessMissesBeforeReload) await reloadCompanionIfAllowed();
    else renewNativePort();
  }

  // ---- Envelopes (Mac schema 2, browserFamily "chromium") ----

  function identity() {
    return {
      companionVersion: config.companionVersion,
      companionBuild: config.companionBuild,
      protocolSchemaVersion: config.protocolSchemaVersion,
      containingApplicationIdentifier: config.containingApplicationIdentifier,
      extensionIdentifier: api.runtime.id,
      teamIdentifier: config.teamIdentifier,
      runtimeGenerationID: config.runtimeGenerationID,
    };
  }
  function automationEnvelope(requestID, status, withIdentity = false) {
    const envelope = {
      kind: "claudeBrowserAutomationEvent",
      schemaVersion: 2,
      sourceID: "claude-browser-usage",
      browserFamily: config.browserFamily,
      requestID,
      status,
      occurredAt: new Date().toISOString(),
    };
    return withIdentity ? { ...envelope, ...identity() } : envelope;
  }
  function observationEnvelope(requestID, observation) {
    return {
      kind: "claudeUsageObservation",
      schemaVersion: 2,
      sourceID: "claude-browser-usage",
      browserFamily: config.browserFamily,
      routeState: "verifiedUsage",
      requestID,
      observationID: newRequestID(),
      observation,
    };
  }
  function terminalEnvelope(requestID, status, observation = null, targetRequestID = null, providerFailureReason = null) {
    return {
      kind: "claudeBrowserTerminalPacket",
      schemaVersion: 2,
      sourceID: "claude-browser-usage",
      browserFamily: config.browserFamily,
      requestID,
      targetRequestID,
      runtimeGenerationID: config.runtimeGenerationID,
      status,
      occurredAt: new Date().toISOString(),
      observation,
      providerFailureReason,
    };
  }

  async function persistentUsageAccessGranted() {
    if (!api.permissions?.contains) return false;
    try { return await api.permissions.contains({ origins: [config.exactHostPermission] }); } catch (_) { return false; }
  }

  // ---- Receipt store: chrome.storage.session with the Safari handler's CAS rules ----

  let receiptQueue = Promise.resolve();
  function receiptOperation(operation) {
    const result = receiptQueue.then(operation, operation);
    receiptQueue = result.then(() => undefined, () => undefined);
    return result;
  }
  async function loadStoredReceipt() {
    try {
      const stored = await api.storage.session.get(receiptStorageKey);
      const record = stored?.[receiptStorageKey];
      return isPlainObject(record) ? record : null;
    } catch (_) { return undefined; }
  }
  async function storeReceipt(record) {
    try {
      if (record) await api.storage.session.set({ [receiptStorageKey]: record });
      else await api.storage.session.remove(receiptStorageKey);
      return true;
    } catch (_) { return false; }
  }
  function receiptMatches(record, command) {
    return record && record.requestID === command.requestID
      && record.runtimeGenerationID === command.runtimeGenerationID
      && record.ownershipNonceDigest === command.ownershipNonceDigest
      && record.revision === command.expectedRevision;
  }
  function allowedTransition(from, to) {
    return Object.values(v2Events).some((event) => ownedProviderReducer.transition(from, event) === to);
  }
  // Returns the same reply shapes the Safari native handler returns.
  function receiptCommand(action, fields = {}) {
    return receiptOperation(async () => {
      const command = { action, ...fields };
      if (command.runtimeGenerationID !== config.runtimeGenerationID) return { ok: false };
      const record = await loadStoredReceipt();
      if (record === undefined) return null;
      if (action === "loadV2") {
        if (!record) return { ok: true, found: false };
        const reply = {
          ok: true, found: true, schemaVersion: 3,
          requestID: record.requestID, runtimeGenerationID: record.runtimeGenerationID,
          ownershipNonceDigest: record.ownershipNonceDigest, createdAt: record.createdAt,
          expiresAt: record.expiresAt, lifecycleState: record.state, revision: record.revision,
        };
        if (Number.isInteger(record.providerCandidateTabID)) reply.providerCandidateTabID = record.providerCandidateTabID;
        if (Number.isInteger(record.providerOwnedTabID)) reply.providerOwnedTabID = record.providerOwnedTabID;
        return reply;
      }
      if (action === "saveV2") {
        const created = Date.parse(command.createdAt);
        const expires = Date.parse(command.expiresAt);
        if (record || !requestIDPattern.test(command.requestID || "")
            || !/^[0-9a-f]{64}$/.test(command.ownershipNonceDigest || "")
            || !Number.isFinite(created) || Math.abs(created - Date.now()) > 60_000
            || !Number.isFinite(expires) || expires <= Date.now() || expires - created > 10 * 60_000
            || command.lifecycleState !== v2States.requestIntentPersisted || command.revision !== 1) return { ok: false };
        const saved = {
          requestID: command.requestID, runtimeGenerationID: command.runtimeGenerationID,
          ownershipNonceDigest: command.ownershipNonceDigest, createdAt: command.createdAt,
          expiresAt: command.expiresAt, state: command.lifecycleState, revision: 1,
        };
        return (await storeReceipt(saved)) ? { ok: true, revision: 1 } : { ok: false };
      }
      if (!receiptMatches(record, command)) return { ok: false };
      if (action === "bindCandidateV2") {
        if (!Number.isInteger(command.providerCandidateTabID) || command.providerCandidateTabID < 0) return { ok: false };
        if (Number.isInteger(record.providerCandidateTabID)) {
          return record.providerCandidateTabID === command.providerCandidateTabID
            ? { ok: true, revision: record.revision } : { ok: false };
        }
        const next = { ...record, providerCandidateTabID: command.providerCandidateTabID, revision: record.revision + 1 };
        return (await storeReceipt(next)) ? { ok: true, revision: next.revision } : { ok: false };
      }
      if (action === "transitionV2") {
        if (record.state !== command.expectedLifecycleState
            || !allowedTransition(record.state, command.nextLifecycleState)) return { ok: false };
        const next = { ...record, state: command.nextLifecycleState, revision: record.revision + 1 };
        if (command.nextLifecycleState === v2States.providerOwnershipProven) {
          // Ownership is proven only for the tab the browser created for this read.
          if (command.providerOwnedTabID !== record.providerCandidateTabID) return { ok: false };
          next.providerOwnedTabID = command.providerOwnedTabID;
        } else if (Number.isInteger(command.providerOwnedTabID)) {
          return { ok: false };
        }
        if (command.nextLifecycleState === v2States.providerDocumentDiscovered && Number.isInteger(command.providerCandidateTabID)) {
          next.providerCandidateTabID = command.providerCandidateTabID;
          delete next.providerOwnedTabID;
        }
        return (await storeReceipt(next)) ? { ok: true, revision: next.revision } : { ok: false };
      }
      if (action === "removeV2") {
        if (!ownedProviderReducer.isTerminal(command.terminalLifecycleState)
            || record.state !== command.terminalLifecycleState
            || (record.state === v2States.expired && Number.isInteger(record.providerOwnedTabID))) return { ok: false };
        return { ok: await storeReceipt(null) };
      }
      return { ok: false };
    });
  }

  // ---- Owned provider tab (Mac V2 flow) ----

  function newOwnershipNonce() {
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
  function receiptFields(read) {
    return {
      requestID: read.requestID,
      runtimeGenerationID: config.runtimeGenerationID,
      ownershipNonceDigest: read.ownershipNonceDigest,
      createdAt: read.createdAt,
      expiresAt: read.expiresAt,
      revision: read.revision,
      state: read.state,
    };
  }

  async function saveV2Intent(read) {
    const rawNonce = newOwnershipNonce();
    const ownershipNonceDigest = await providerOwnership.nonceDigest(rawNonce);
    if (!ownershipNonceDigest) return false;
    const createdAt = new Date().toISOString();
    const expiresAt = new Date(Date.now() + ownedTabReceiptMaximumAgeMilliseconds).toISOString();
    const reply = await receiptCommand("saveV2", {
      requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID,
      ownershipNonceDigest, createdAt, expiresAt,
      lifecycleState: v2States.requestIntentPersisted, revision: 1,
    });
    if (!exactKeys(reply, ["ok", "revision"]) || reply.ok !== true || reply.revision !== 1) return false;
    Object.assign(read, { rawNonce, ownershipNonceDigest, createdAt, expiresAt, revision: 1, state: v2States.requestIntentPersisted });
    return true;
  }

  async function transitionV2(read, event, options = {}) {
    if (!read || !validV2Receipt(receiptFields(read))) return false;
    const nextState = ownedProviderReducer.transition(read.state, event);
    if (!nextState) return false;
    const fields = {
      requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID,
      ownershipNonceDigest: read.ownershipNonceDigest, expectedRevision: read.revision,
      expectedLifecycleState: read.state, nextLifecycleState: nextState,
    };
    if (Number.isInteger(options.providerCandidateTabID)) fields.providerCandidateTabID = options.providerCandidateTabID;
    if (Number.isInteger(options.providerOwnedTabID)) fields.providerOwnedTabID = options.providerOwnedTabID;
    const reply = await receiptCommand("transitionV2", fields);
    if (!exactKeys(reply, ["ok", "revision"]) || reply.ok !== true || reply.revision !== read.revision + 1) return false;
    read.state = nextState;
    read.revision = reply.revision;
    if (Number.isInteger(options.providerCandidateTabID)) read.providerCandidateTabID = options.providerCandidateTabID;
    if (nextState === v2States.providerDocumentDiscovered) read.providerOwnedTabID = null;
    if (Number.isInteger(options.providerOwnedTabID)) {
      read.providerOwnedTabID = options.providerOwnedTabID;
      read.tabID = options.providerOwnedTabID;
    }
    return true;
  }

  async function bindV2Candidate(read, providerCandidateTabID) {
    if (!read || !Number.isInteger(providerCandidateTabID) || providerCandidateTabID < 0) return false;
    // Serialize the tabs.create/document-discovery racers around the compare-and-swap.
    const previous = read.candidateBindingPromise || Promise.resolve();
    const operation = previous.then(async () => {
      if (read.finished) return false;
      if (read.state !== v2States.providerCreationPending && read.state !== v2States.providerDocumentDiscovered) {
        return read.providerCandidateTabID === providerCandidateTabID;
      }
      if (Number.isInteger(read.providerCandidateTabID) && read.providerCandidateTabID !== providerCandidateTabID) return false;
      const priorRevision = read.revision;
      const wasAlreadyBound = Number.isInteger(read.providerCandidateTabID);
      const reply = await receiptCommand("bindCandidateV2", {
        requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID,
        ownershipNonceDigest: read.ownershipNonceDigest, expectedRevision: priorRevision, providerCandidateTabID,
      });
      const expectedRevision = wasAlreadyBound ? priorRevision : priorRevision + 1;
      if (!exactKeys(reply, ["ok", "revision"]) || reply.ok !== true || reply.revision !== expectedRevision) return false;
      read.providerCandidateTabID = providerCandidateTabID;
      read.revision = reply.revision;
      return true;
    });
    read.candidateBindingPromise = operation.catch(() => false);
    return operation;
  }

  async function removeV2Receipt(read, terminalState) {
    if (!read || !validV2Receipt(receiptFields(read))
        || ![v2States.complete, v2States.cancelled, v2States.expired, v2States.failed].includes(terminalState)) return false;
    const reply = await receiptCommand("removeV2", {
      requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID,
      ownershipNonceDigest: read.ownershipNonceDigest, expectedRevision: read.revision,
      terminalLifecycleState: terminalState,
    });
    return exactKeys(reply, ["ok"]) && reply.ok === true;
  }

  function decodeV2Receipt(reply) {
    if (exactKeys(reply, ["found", "ok"]) && reply.ok === true && reply.found === false) return null;
    if (!isPlainObject(reply) || reply.ok !== true || reply.found !== true || reply.schemaVersion !== 3) return false;
    const record = {
      requestID: reply.requestID, runtimeGenerationID: reply.runtimeGenerationID,
      ownershipNonceDigest: reply.ownershipNonceDigest, createdAt: reply.createdAt,
      expiresAt: reply.expiresAt, state: reply.lifecycleState, revision: reply.revision,
      providerCandidateTabID: reply.providerCandidateTabID, providerOwnedTabID: reply.providerOwnedTabID,
    };
    return validV2Receipt(record) ? record : false;
  }

  function newRead(requestID) {
    return {
      requestID, runtimeGenerationID: config.runtimeGenerationID, state: v2States.idle, revision: 0,
      rawNonce: null, ownershipNonceDigest: null, createdAt: null, expiresAt: null,
      createdCandidateTabID: null, temporaryWindowID: null, temporaryWindowTabID: null,
      candidateBindingPromise: Promise.resolve(), providerCandidateTabID: null, providerOwnedTabID: null,
      providerPort: null, replacementCandidateTabID: null, pendingProviderDiscovery: null,
      timeoutID: null, extractionNudgeID: null, extractionNudges: 0, pageLastHeardAt: 0, acceptedPorts: 0,
      trace: [], traceStartedAt: null, removalListener: null, replacementListener: null, updateListener: null,
      verifiedTab: null, finished: false, closingOwnedTab: false, removalAlreadyConfirmed: false,
      cleanupOnly: false, cleanupTerminalState: v2States.failed, resultMessageAccepted: false,
      resultMessageInFlight: false, providerFailureReason: null, recovered: false,
    };
  }
  function readFromV2Receipt(record) {
    return {
      ...newRead(record.requestID), ...record,
      tabID: Number.isInteger(record.providerOwnedTabID) ? record.providerOwnedTabID : null,
      verifiedTab: Number.isInteger(record.providerOwnedTabID) ? { id: record.providerOwnedTabID } : null,
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
    return state === v2States.complete ? v2Events.complete : state === v2States.cancelled ? v2Events.cancel : v2Events.fail;
  }

  async function finalizeAbsentV2Cleanup(read) {
    if (!read || !Number.isInteger(read.providerOwnedTabID)) return false;
    if (read.state !== v2States.cleanupRequested && read.state !== v2States.cleanupConfirmed
        && !await transitionV2(read, v2Events.requestCleanup)) return false;
    if (read.state === v2States.cleanupRequested && !await transitionV2(read, v2Events.confirmCleanup)) return false;
    const terminalState = read.cleanupTerminalState || v2States.failed;
    if (read.state !== terminalState && !await transitionV2(read, terminalEventForV2(terminalState))) return false;
    if (!await removeV2Receipt(read, terminalState)) return false;
    pendingV2Receipt = null;
    ownedTabRecoveryBlocked = false;
    return true;
  }

  async function recoverCleanupOnlyV2(read) {
    read.cleanupOnly = true;
    read.cleanupTerminalState = ownedProviderReducer.isTerminal(read.state) ? read.state : v2States.failed;
    const presence = await exactV2TabPresence(read.providerOwnedTabID);
    if (presence === "absent") return await finalizeAbsentV2Cleanup(read);
    pendingV2Receipt = read;
    ownedTabRecoveryBlocked = true;
    if (presence === "present" && Date.now() < Date.parse(read.expiresAt)) scheduleV2Expiry(read);
    return false;
  }

  // After the worker restarts, only the one content-free receipt is looked at. A
  // provider page still holding its nonce must prove itself again over a Port;
  // recovery never enumerates tabs and never closes an unproven tab.
  async function recoverV2Receipt() {
    const reply = await receiptCommand("loadV2", { runtimeGenerationID: config.runtimeGenerationID });
    if (reply === null) { ownedTabRecoveryBlocked = true; return; }
    const record = decodeV2Receipt(reply);
    if (record === null) return;
    if (record === false || record.runtimeGenerationID !== config.runtimeGenerationID) {
      ownedTabRecoveryBlocked = true;
      return;
    }
    const read = readFromV2Receipt(record);
    if (Date.now() >= Date.parse(record.expiresAt)) {
      if ([v2States.requestIntentPersisted, v2States.providerCreationPending, v2States.providerDocumentDiscovered].includes(record.state)) {
        if (await transitionV2(read, v2Events.expire) && await removeV2Receipt(read, v2States.expired)) return;
      }
      if (Number.isInteger(record.providerOwnedTabID)) { await recoverCleanupOnlyV2(read); return; }
      pendingV2Receipt = read;
      ownedTabRecoveryBlocked = true;
      return;
    }
    if (record.state === v2States.cleanupRequested || record.state === v2States.cleanupConfirmed) {
      await recoverCleanupOnlyV2(read);
      return;
    }
    pendingV2Receipt = read;
    ownedTabRecoveryBlocked = true;
    scheduleV2Expiry(read);
  }

  async function expireV2Receipt(read) {
    if ([v2States.requestIntentPersisted, v2States.providerCreationPending, v2States.providerDocumentDiscovered].includes(read.state)) {
      if (await transitionV2(read, v2Events.expire) && await removeV2Receipt(read, v2States.expired)) {
        pendingV2Receipt = null;
        ownedTabRecoveryBlocked = false;
      }
    }
    if (Number.isInteger(read.providerOwnedTabID)) await recoverCleanupOnlyV2(read);
  }
  async function settleDueV2Receipt() {
    const read = pendingV2Receipt;
    if (!read || !read.expiresAt || Date.now() < Date.parse(read.expiresAt)) return;
    if (ownedTabExpiryTimer !== null) { clearTimeout(ownedTabExpiryTimer); ownedTabExpiryTimer = null; }
    await expireV2Receipt(read);
  }
  function scheduleV2Expiry(read) {
    if (!read || ownedTabExpiryTimer !== null) return;
    const remaining = Math.max(1, Date.parse(read.expiresAt) - Date.now() + 1);
    ownedTabExpiryTimer = setTimeout(() => {
      ownedTabExpiryTimer = null;
      if (pendingV2Receipt?.requestID !== read.requestID) return;
      void expireV2Receipt(read);
    }, remaining);
  }

  // D7: with no placement from AUV, a read opens as an inactive tab in a normal
  // browser window that is not minimized, and otherwise in a small minimized
  // window of its own that closes with its only tab. A window this companion
  // kept open (see closeTemporaryProviderWindow) is reused instead of opening
  // another one.
  async function resolvePlacement(requested) {
    if (requested !== "minimizedWindow") {
      try {
        const windows = await api.windows.getAll({ windowTypes: ["normal"] });
        const usable = windows.find((w) => w.state !== "minimized" && !w.incognito);
        if (usable) return { kind: "backgroundTab", windowId: usable.id };
      } catch (_) {}
    }
    const parked = await parkedWindowID();
    if (parked !== null) return { kind: "parkedWindow", windowId: parked };
    return { kind: "minimizedWindow" };
  }

  // On Windows, Chrome and Edge quit when their last window closes, and this
  // companion goes with them. When the read's own minimized window is the
  // browser's last window, it is kept, minimized, with a blank tab, and reused
  // by later reads (user decision, 2026-11-08). Only the window ID is stored,
  // in session storage, which the browser clears when it restarts.
  const parkedWindowKey = "auvParkedWindowV1";
  async function parkedWindowID() {
    try {
      const stored = await api.storage.session.get(parkedWindowKey);
      const id = stored?.[parkedWindowKey];
      if (!Number.isInteger(id)) return null;
      const window = await api.windows.get(id);
      return window?.id === id && !window.incognito ? id : null;
    } catch (_) { return null; }
  }

  async function createTemporaryProviderWindow(read, providerURL) {
    let created;
    try {
      created = await api.windows.create({ url: providerURL, focused: false, state: "minimized" });
    } catch (_) {
      created = await api.windows.create({
        url: providerURL, focused: false, width: temporaryWindowSize.width, height: temporaryWindowSize.height,
      });
    }
    if (!Number.isInteger(created?.id)) return null;
    read.temporaryWindowID = created.id;
    let tab = Array.isArray(created.tabs) && created.tabs.length === 1 ? created.tabs[0] : null;
    if (!Number.isInteger(tab?.id)) {
      try {
        const populated = await api.windows.get(created.id, { populate: true });
        tab = Array.isArray(populated?.tabs) && populated.tabs.length === 1 ? populated.tabs[0] : null;
      } catch (_) { tab = null; }
    }
    if (Number.isInteger(tab?.id)) read.temporaryWindowTabID = tab.id;
    return tab;
  }

  // Closes the temporary window this read created, but only while it still holds
  // nothing except the read's own tab.
  async function closeTemporaryProviderWindow(read) {
    const windowID = read?.temporaryWindowID;
    if (!Number.isInteger(windowID) || !api.windows?.get || !api.windows?.remove) return false;
    const expectedTabID = read.providerOwnedTabID ?? read.createdCandidateTabID ?? read.temporaryWindowTabID;
    if (!Number.isInteger(expectedTabID)) return false;
    try {
      const current = await api.windows.get(windowID, { populate: true });
      const tabs = Array.isArray(current?.tabs) ? current.tabs : [];
      if (tabs.length !== 1 || tabs[0]?.id !== expectedTabID) return false;
      const others = (await api.windows.getAll({ windowTypes: ["normal"] })).filter((w) => w.id !== windowID);
      if (others.length === 0) {
        // The browser's last window: keep it (see parkedWindowID). A blank tab
        // keeps the window open once the caller closes the read's own tab.
        await api.tabs.create({ windowId: windowID, url: "about:blank", active: false });
        await api.storage.session.set({ [parkedWindowKey]: windowID });
        read.temporaryWindowID = null;
        return false;
      }
      await api.windows.remove(windowID);
      read.temporaryWindowID = null;
      return true;
    } catch (_) { return false; }
  }

  function exactOwnedProviderSender(port) {
    const sender = port?.sender;
    const senderIDMatches = typeof sender?.id !== "string" || sender.id === api.runtime.id;
    const topFrameMatches = sender?.frameId === 0;
    const declaredOriginMatches = typeof sender?.origin !== "string" || sender.origin === extractor.CONTRACT.origin;
    let originMatches = false;
    try {
      const url = new URL(sender?.url || sender?.tab?.url || "");
      originMatches = url.origin === extractor.CONTRACT.origin && url.pathname === new URL(extractor.CONTRACT.href).pathname;
    } catch (_) {}
    return senderIDMatches && topFrameMatches && declaredOriginMatches && originMatches
      && Number.isInteger(sender?.tab?.id) && sender.tab.id >= 0;
  }

  function armV2TabLifecycle(read) {
    if (!read || !Number.isInteger(read.providerOwnedTabID) || !api.tabs?.onRemoved?.addListener) return false;
    const lifecycle = ownedProviderReducer.createTabLifecycleListeners({
      ownedTabID: () => read.providerOwnedTabID,
      isActive: () => automaticRead === read && !read.finished,
      isClosing: () => read.closingOwnedTab,
      defer: (operation) => setTimeout(operation, 0),
      onUnreplacedRemoval: () => {
        read.removalAlreadyConfirmed = true;
        retainRuntimeOperation(finishAutomaticV2(read, "tabUnavailable", null, false, "PROVIDER_TAB_CLOSED"));
      },
      onReplacementCandidate: (addedTabID) => {
        read.replacementCandidateTabID = addedTabID;
        read.removalAlreadyConfirmed = false;
        read.providerPort = null;
        read.verifiedTab = null;
      },
    });
    const updateListener = (tabID) => {
      if (automaticRead !== read || read.finished || tabID !== read.providerOwnedTabID || !read.providerPort) return;
      // A content-free event for the proven tab; no URL is copied or sent.
      try { read.providerPort.postMessage({ type: "umaClaudeProviderRouteEventV2", requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID }); } catch (_) {}
    };
    read.removalListener = lifecycle.onRemoved;
    read.replacementListener = lifecycle.onReplaced;
    read.updateListener = updateListener;
    try {
      api.tabs.onRemoved.addListener(read.removalListener);
      api.tabs.onReplaced?.addListener?.(read.replacementListener);
      api.tabs.onUpdated?.addListener?.(read.updateListener);
      return true;
    } catch (_) {
      removeV2Lifecycle(read);
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
      // No live proof means no authority over a tab, except a temporary window this
      // read created that still holds only its own candidate tab.
      await closeTemporaryProviderWindow(read);
      pendingV2Receipt = read;
      ownedTabRecoveryBlocked = true;
      scheduleV2Expiry(read);
      return false;
    }
    if (read.state !== v2States.cleanupRequested && read.state !== v2States.cleanupConfirmed
        && !await transitionV2(read, v2Events.requestCleanup)) return false;
    if (!read.removalAlreadyConfirmed) {
      read.closingOwnedTab = true;
      try {
        if (!await closeTemporaryProviderWindow(read)) await api.tabs.remove(read.providerOwnedTabID);
      } catch (_) {
        read.closingOwnedTab = false;
        pendingV2Receipt = read;
        ownedTabRecoveryBlocked = true;
        return false;
      }
    }
    if (read.state === v2States.cleanupRequested && !await transitionV2(read, v2Events.confirmCleanup)) return false;
    if (!await transitionV2(read, terminalEventForV2(terminalState))) return false;
    if (!await removeV2Receipt(read, terminalState)) return false;
    pendingV2Receipt = null;
    ownedTabRecoveryBlocked = false;
    return true;
  }

  function notePageTrace(read, step) {
    if (!read.traceStartedAt) read.traceStartedAt = Date.now();
    if (read.trace.length < 24) read.trace.push(`${step}+${Date.now() - read.traceStartedAt}`);
  }
  // One content-free line per read for AUV's diagnostics.
  function sendPageTrace(read, status) {
    const trace = `status=${status} nudges=${read.extractionNudges} ports=${read.acceptedPorts} steps=${read.trace.join(",")}`;
    postNative({ kind: pageTraceKind, trace: trace.slice(0, 800) });
  }
  function stopExtractionNudge(read) {
    if (read.extractionNudgeID !== null) clearTimeout(read.extractionNudgeID);
    read.extractionNudgeID = null;
  }
  function postToProviderPort(read, type) {
    try { read.providerPort?.postMessage({ type, requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID }); } catch (_) {}
  }
  function startExtractionNudge(read) {
    stopExtractionNudge(read);
    notePageTrace(read, "extractSent");
    read.pageLastHeardAt = Date.now();
    const nudge = () => {
      read.extractionNudgeID = null;
      if (automaticRead !== read || read.finished || read.state !== v2States.extracting) return;
      if (Date.now() - read.pageLastHeardAt >= silentPageMilliseconds) {
        notePageTrace(read, "pageSilent");
        void finishAutomaticV2(read, "tabUnavailable");
        return;
      }
      read.extractionNudges += 1;
      postToProviderPort(read, "umaClaudeExtractProviderUsageV2");
      postToProviderPort(read, "umaClaudeProviderRouteEventV2");
      postToProviderPort(read, "umaClaudeProviderResendResultV2");
      read.extractionNudgeID = setTimeout(nudge, extractionNudgeMilliseconds);
    };
    read.extractionNudgeID = setTimeout(nudge, extractionNudgeMilliseconds);
  }

  async function finishAutomaticV2(read, status, observation, suppressTerminal = false, providerFailureReason = null) {
    if (!read || automaticRead !== read || read.finished) return "ownedTabOwnershipLost";
    read.finished = true;
    if (read.timeoutID !== null) clearTimeout(read.timeoutID);
    stopExtractionNudge(read);
    sendPageTrace(read, status);
    let finalStatus = status;
    if (!read.ownershipNonceDigest) {
      if (!suppressTerminal) await sendNative(terminalEnvelope(read.requestID, finalStatus));
      if (automaticRead === read) automaticRead = null;
      return finalStatus;
    }
    let retainedObservation = null;
    let retainedProviderFailureReason = status === "refreshCompleted"
      ? null : providerFailureReasons.has(providerFailureReason) ? providerFailureReason : null;
    if (status === "refreshCompleted" && extractor.validateObservation(observation)) {
      if (read.state !== v2States.resultReady || !await transitionV2(read, v2Events.deliverResult)) {
        finalStatus = "usageUnavailable";
      } else {
        // Kept in memory until the proven tab and its receipt are gone; nothing is
        // published while cleanup can still fail.
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
      retainedProviderFailureReason = null;
    }
    removeV2Lifecycle(read);
    try { read.providerPort?.disconnect?.(); } catch (_) {}
    if (!suppressTerminal) {
      await sendNative(terminalEnvelope(
        read.requestID, finalStatus,
        finalStatus === "refreshCompleted" ? retainedObservation : null, null,
        finalStatus === "refreshCompleted" ? null : retainedProviderFailureReason
      ));
    }
    if (automaticRead === read) automaticRead = null;
    return finalStatus;
  }

  async function acceptV2ProviderOwnership(read, port, ownershipNonce) {
    if (!read || read.finished || !exactOwnedProviderSender(port)) return false;
    const senderTabID = port.sender.tab.id;
    if ([v2States.providerOwnershipProven, v2States.providerReady, v2States.extracting, v2States.resultReady,
      v2States.resultDelivered, v2States.cleanupRequested, v2States.cleanupConfirmed].includes(read.state)
        && read.providerOwnedTabID === senderTabID) {
      read.providerPort = port;
      read.acceptedPorts += 1;
      read.rawNonce = ownershipNonce;
      if (!read.removalListener && !armV2TabLifecycle(read)) return false;
      port.postMessage({ type: "umaClaudeProviderOwnershipAcceptedV2", requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID });
      if (read.cleanupOnly) await finishAutomaticV2(read, "ownedTabOwnershipLost");
      return true;
    }
    const expectedCandidate = Number.isInteger(read.replacementCandidateTabID) ? read.replacementCandidateTabID : read.providerCandidateTabID;
    // Discovery may beat tabs.create's promise; sender.tab.id is not ownership
    // until the browser-created ID independently matches it.
    if (!Number.isInteger(expectedCandidate)) return false;
    if (!read.recovered && !Number.isInteger(read.replacementCandidateTabID) && read.createdCandidateTabID !== expectedCandidate) return false;
    if (expectedCandidate !== senderTabID) {
      await finishAutomaticV2(read, "ownedTabOwnershipLost");
      return false;
    }
    if (read.state !== v2States.providerDocumentDiscovered || read.providerCandidateTabID !== senderTabID
        || !await transitionV2(read, v2Events.proveProviderOwnership, { providerOwnedTabID: senderTabID })) return false;
    read.rawNonce = ownershipNonce;
    read.providerPort = port;
    read.acceptedPorts += 1;
    read.providerOwnedTabID = senderTabID;
    read.tabID = senderTabID;
    read.verifiedTab = { id: senderTabID };
    read.replacementCandidateTabID = null;
    read.pendingProviderDiscovery = null;
    pendingV2Receipt = null;
    ownedTabRecoveryBlocked = false;
    if (!read.removalListener && !armV2TabLifecycle(read)) return false;
    port.postMessage({ type: "umaClaudeProviderOwnershipAcceptedV2", requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID });
    return true;
  }

  async function handleV2ProviderMessage(port, message) {
    if (!exactOwnedProviderSender(port) || !isPlainObject(message)) return;
    if (message.type === "umaClaudeProviderDocumentDiscoveredV2") {
      if (!exactKeys(message, ["ownershipNonce", "type"]) || !providerOwnership.markerPattern.test(message.ownershipNonce || "")) return;
      await ownedTabRecoveryPromise;
      const digest = await providerOwnership.nonceDigest(message.ownershipNonce);
      const read = automaticRead || pendingV2Receipt;
      if (!read || digest !== read.ownershipNonceDigest
          || (read.runtimeGenerationID && read.runtimeGenerationID !== config.runtimeGenerationID)) return;
      const senderTabID = port.sender.tab.id;
      if (read.replacementCandidateTabID !== null && senderTabID !== read.replacementCandidateTabID) return;
      if (!automaticRead) {
        automaticRead = read;
        read.rawNonce = message.ownershipNonce;
        read.finished = false;
        read.timeoutID = setTimeout(() => { void finishAutomaticV2(read, "tabUnavailable"); }, automaticTimeoutMilliseconds);
      }
      if ((read.state === v2States.providerOwnershipProven || read.state === v2States.providerReady)
          && read.providerOwnedTabID !== senderTabID) {
        if (!Number.isInteger(read.replacementCandidateTabID) || read.replacementCandidateTabID !== senderTabID) return;
        if (!await transitionV2(read, v2Events.replacementRequiresReproof, { providerCandidateTabID: senderTabID })) return;
      }
      if (read.state === v2States.providerCreationPending && !await bindV2Candidate(read, senderTabID)) {
        await finishAutomaticV2(read, "ownedTabOwnershipLost");
        return;
      }
      read.pendingProviderDiscovery = { port, ownershipNonce: message.ownershipNonce, senderTabID };
      const candidateConfirmed = read.recovered || Number.isInteger(read.replacementCandidateTabID)
        || read.createdCandidateTabID === senderTabID;
      if (read.state === v2States.providerCreationPending && candidateConfirmed
          && !await transitionV2(read, v2Events.discoverProviderDocument)) return;
      await acceptV2ProviderOwnership(read, port, message.ownershipNonce);
      return;
    }

    const read = automaticRead;
    if (!read || read.finished || read.providerPort !== port || port.sender.tab.id !== read.providerOwnedTabID
        || message.requestID !== read.requestID || message.runtimeGenerationID !== config.runtimeGenerationID) return;
    read.pageLastHeardAt = Date.now();
    if (message.type === "umaClaudeProviderAliveV2") return;
    if (message.type === "umaClaudeProviderReadyV2" && exactKeys(message, ["requestID", "runtimeGenerationID", "type"])) {
      const becameReady = read.state === v2States.providerOwnershipProven
        ? await transitionV2(read, v2Events.providerReady) : read.state === v2States.providerReady;
      if (becameReady && await transitionV2(read, v2Events.beginExtraction)) {
        port.postMessage({ type: "umaClaudeExtractProviderUsageV2", requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID });
        startExtractionNudge(read);
      }
      return;
    }
    if (message.type === "umaClaudeProviderProgressV2" && exactKeys(message, ["requestID", "runtimeGenerationID", "step", "type"])) {
      if (pageProgressSteps.has(message.step)) notePageTrace(read, message.step);
      return;
    }
    if (message.type === "umaClaudeProviderMarkerRemovalFailedV2" && exactKeys(message, ["requestID", "runtimeGenerationID", "type"])) {
      await finishAutomaticV2(read, "ownedTabOwnershipLost");
      return;
    }
    if (message.type === "umaClaudeProviderResultV2" && resultStatuses.includes(message.status)) {
      const expected = message.status === "success"
        ? ["observation", "requestID", "runtimeGenerationID", "status", "type"]
        : ["providerFailureReason", "requestID", "runtimeGenerationID", "status", "type"];
      const retransmittable = read.recovered && read.state === v2States.resultReady;
      if (!exactKeys(message, expected)
          || (message.status !== "success" && !providerFailureReasons.has(message.providerFailureReason))
          || ![v2States.extracting, v2States.resultReady].includes(read.state)
          || (read.state === v2States.resultReady && !retransmittable)
          || read.resultMessageAccepted || read.resultMessageInFlight) return;
      read.resultMessageInFlight = true;
      stopExtractionNudge(read);
      const resultCaptured = read.state === v2States.resultReady || await transitionV2(read, v2Events.captureResult);
      if (!resultCaptured) {
        read.resultMessageInFlight = false;
        if (read.state === v2States.extracting) startExtractionNudge(read);
        return;
      }
      read.resultMessageAccepted = true;
      read.providerFailureReason = message.status === "success" ? null : message.providerFailureReason;
      port.postMessage({ type: "umaClaudeProviderResultAcceptedV2", requestID: read.requestID, runtimeGenerationID: config.runtimeGenerationID });
      if (message.status === "success" && extractor.validateObservation(message.observation)) {
        await finishAutomaticV2(read, "refreshCompleted", message.observation);
      } else if (message.status === "success") {
        await finishAutomaticV2(read, "usageUnavailable", null, false, "EXTRACTION_VALIDATION_FAILED");
      } else {
        await finishAutomaticV2(read, message.status, null, false, message.providerFailureReason);
      }
    }
  }

  async function beginAutomaticRead(requestID, requestedPlacement) {
    if (!requestIDPattern.test(requestID)) return;
    if (automaticRead) { await sendNative(automationEnvelope(requestID, "usageUnavailable")); return; }
    await ownedTabRecoveryPromise;
    if (ownedTabRecoveryBlocked) await settleDueV2Receipt();
    if (ownedTabRecoveryBlocked) { await sendNative(automationEnvelope(requestID, "ownedTabOwnershipLost")); return; }
    if (automaticRead) { await sendNative(automationEnvelope(requestID, "usageUnavailable")); return; }
    const read = newRead(requestID);
    automaticRead = read;
    if (!(await sendNative(automationEnvelope(requestID, "refreshStarted")))) {
      read.finished = true;
      automaticRead = null;
      return;
    }
    if (!(await persistentUsageAccessGranted())) {
      await finishAutomaticV2(read, "permissionRequired", null, false, "SITE_PERMISSION_MISSING");
      return;
    }
    if (!api.tabs?.create || !api.tabs?.remove || !api.tabs?.onRemoved?.addListener) {
      await finishAutomaticV2(read, "tabUnavailable");
      return;
    }
    if (!await saveV2Intent(read)) { await finishAutomaticV2(read, "ownedTabOwnershipLost"); return; }
    if (!await transitionV2(read, v2Events.beginProviderCreation)) { await finishAutomaticV2(read, "ownedTabOwnershipLost"); return; }
    const providerURL = providerOwnership.providerURLForNonce(read.rawNonce);
    if (!providerURL) { await finishAutomaticV2(read, "tabUnavailable"); return; }
    read.timeoutID = setTimeout(() => { void finishAutomaticV2(read, "tabUnavailable"); }, automaticTimeoutMilliseconds);
    try {
      const placement = await resolvePlacement(requestedPlacement);
      const tab = placement.kind === "minimizedWindow"
        ? await createTemporaryProviderWindow(read, providerURL)
        : await api.tabs.create({ url: providerURL, active: false, windowId: placement.windowId });
      // create() is only advisory; ownership comes from the provider document's
      // Port and its trusted sender.tab.id.
      if (!Number.isInteger(tab?.id)) { await finishAutomaticV2(read, "ownedTabOwnershipLost"); return; }
      if (!await bindV2Candidate(read, tab.id)) { await finishAutomaticV2(read, "ownedTabOwnershipLost"); return; }
      read.createdCandidateTabID = tab.id;
      // A tab the browser could discard to save memory would end the read.
      try { await api.tabs.update(tab.id, { autoDiscardable: false }); } catch (_) {}
      const pending = read.pendingProviderDiscovery;
      if (pending) {
        if (pending.senderTabID !== tab.id || read.providerCandidateTabID !== tab.id
            || (read.state === v2States.providerCreationPending && !await transitionV2(read, v2Events.discoverProviderDocument))) {
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
    }
  }

  async function closeOwnedRead(requestID, targetRequestID) {
    if (!requestIDPattern.test(requestID) || !requestIDPattern.test(targetRequestID) || requestID === targetRequestID) return;
    const read = automaticRead;
    if (read && !read.finished && read.requestID === targetRequestID) {
      const status = await finishAutomaticV2(read, "ownedTabClosed", null, true);
      await sendNative(terminalEnvelope(requestID, status === "ownedTabClosed" ? "ownedTabClosed" : "ownedTabOwnershipLost", null, targetRequestID));
      return;
    }
    await sendNative(terminalEnvelope(requestID, "ownedTabOwnershipLost", null, targetRequestID));
  }

  // ---- Commands from AUV ----

  function validatedCommand(value) {
    if (!isPlainObject(value) || value.kind !== "auvCompanionCommand" || value.schemaVersion !== 1
        || typeof value.command !== "string" || !requestIDPattern.test(value.requestID || "")) return null;
    const base = ["kind", "schemaVersion", "command", "requestID"];
    if (value.command === "umaClaudeCloseOwnedUsageTab") {
      return exactKeys(value, [...base, "targetRequestID"]) && requestIDPattern.test(value.targetRequestID || "")
        && value.targetRequestID !== value.requestID ? value : null;
    }
    if (value.command === "umaClaudeAutomaticRefresh" && Object.prototype.hasOwnProperty.call(value, "placement")) {
      return exactKeys(value, [...base, "placement"]) && placements.includes(value.placement) ? value : null;
    }
    return ["umaClaudeWakeBridge", "umaClaudeRuntimeQualification", "umaClaudeAutomaticRefresh", "umaClaudeReloadCompanion"].includes(value.command)
      && exactKeys(value, base) ? value : null;
  }

  function handleNativeMessage(message) {
    if (exactKeys(message, ["kind", "schemaVersion", "appConnected"]) && message.kind === "auvHostStatus"
        && message.schemaVersion === 1 && typeof message.appConnected === "boolean") {
      appConnected = message.appConnected;
      livenessMisses = 0;
      return;
    }
    if (exactKeys(message, ["kind", "schemaVersion", "pingID"]) && message.kind === "auvCompanionPing"
        && message.schemaVersion === 1 && requestIDPattern.test(message.pingID || "")) {
      postNative({ kind: "auvCompanionPong", schemaVersion: 1, pingID: message.pingID });
      return;
    }
    const command = validatedCommand(message);
    if (!command) return;
    // A command is run once even if it is delivered twice (Mac 0.18.4).
    const commandKey = `${command.command}:${command.requestID}`;
    if (handledCommands.has(commandKey)) return;
    handledCommands.add(commandKey);
    if (handledCommands.size > handledCommandLimit) handledCommands.delete(handledCommands.values().next().value);
    if (command.command === "umaClaudeWakeBridge") {
      postNative(automationEnvelope(command.requestID, "extensionBackgroundReady", true));
    } else if (command.command === "umaClaudeRuntimeQualification") {
      // The host already checked this extension's origin. The companion confirms
      // the build identity AUV expects before any read is sent.
      postNative(automationEnvelope(command.requestID, "bridgeReady", true));
    } else if (command.command === "umaClaudeAutomaticRefresh") {
      retainRuntimeOperation(beginAutomaticRead(command.requestID, command.placement));
    } else if (command.command === "umaClaudeCloseOwnedUsageTab") {
      retainRuntimeOperation(closeOwnedRead(command.requestID, command.targetRequestID));
    } else if (command.command === "umaClaudeReloadCompanion") {
      retainRuntimeOperation(reloadForUpdate());
    }
  }

  // ---- Wiring ----

  api.runtime.onConnect?.addListener((port) => {
    if (port?.name !== v2PortName || !port.onMessage?.addListener || !port.postMessage) return;
    port.onMessage.addListener((message) => retainRuntimeOperation(handleV2ProviderMessage(port, message)));
  });

  // D13: the toolbar button asks AUV to sync now. Nothing about the current tab is sent.
  api.action?.onClicked?.addListener(() => {
    if (!nativePort) installNativePort();
    postNative({ kind: "auvCompanionSyncRequest", schemaVersion: 1, requestID: newRequestID() });
  });

  api.alarms?.onAlarm?.addListener((alarm) => {
    if (alarm?.name === livenessAlarm) retainRuntimeOperation(checkLiveness());
  });
  api.runtime.onStartup?.addListener(() => installNativePort());
  api.runtime.onInstalled?.addListener(() => installNativePort());

  ownedTabRecoveryPromise = recoverV2Receipt();
  installNativePort();
  try { api.alarms?.create?.(livenessAlarm, { periodInMinutes: 1 }); } catch (_) {}

  // Test hook: the harness reads state through this frozen view only.
  root.AUVCompanionDiagnostics = Object.freeze({
    state: () => ({ connected: Boolean(nativePort), appConnected, reading: Boolean(automaticRead), recoveryBlocked: ownedTabRecoveryBlocked, livenessMisses }),
    checkLiveness: () => checkLiveness(),
  });
})(globalThis);
