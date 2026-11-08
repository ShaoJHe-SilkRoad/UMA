(function (root) {
  "use strict";

  const STATES = Object.freeze({
    idle: "IDLE",
    requestIntentPersisted: "REQUEST_INTENT_PERSISTED",
    providerCreationPending: "PROVIDER_CREATION_PENDING",
    providerDocumentDiscovered: "PROVIDER_DOCUMENT_DISCOVERED",
    providerOwnershipProven: "PROVIDER_OWNERSHIP_PROVEN",
    providerReady: "PROVIDER_READY",
    extracting: "EXTRACTING",
    resultReady: "RESULT_READY",
    resultDelivered: "RESULT_DELIVERED",
    cleanupRequested: "CLEANUP_REQUESTED",
    cleanupConfirmed: "CLEANUP_CONFIRMED",
    complete: "COMPLETE",
    cancelled: "CANCELLED",
    expired: "EXPIRED",
    failed: "FAILED",
  });

  const EVENTS = Object.freeze({
    persistIntent: "PERSIST_INTENT",
    beginProviderCreation: "BEGIN_PROVIDER_CREATION",
    discoverProviderDocument: "DISCOVER_PROVIDER_DOCUMENT",
    proveProviderOwnership: "PROVE_PROVIDER_OWNERSHIP",
    providerReady: "PROVIDER_READY",
    beginExtraction: "BEGIN_EXTRACTION",
    captureResult: "CAPTURE_RESULT",
    deliverResult: "DELIVER_RESULT",
    requestCleanup: "REQUEST_CLEANUP",
    confirmCleanup: "CONFIRM_CLEANUP",
    complete: "COMPLETE",
    cancel: "CANCEL",
    expire: "EXPIRE",
    fail: "FAIL",
    replacementRequiresReproof: "REPLACEMENT_REQUIRES_REPROOF",
  });

  const nextByState = Object.freeze({
    [STATES.idle]: Object.freeze({
      [EVENTS.persistIntent]: STATES.requestIntentPersisted,
    }),
    [STATES.requestIntentPersisted]: Object.freeze({
      [EVENTS.beginProviderCreation]: STATES.providerCreationPending,
    }),
    [STATES.providerCreationPending]: Object.freeze({
      [EVENTS.discoverProviderDocument]: STATES.providerDocumentDiscovered,
    }),
    [STATES.providerDocumentDiscovered]: Object.freeze({
      [EVENTS.proveProviderOwnership]: STATES.providerOwnershipProven,
    }),
    [STATES.providerOwnershipProven]: Object.freeze({
      [EVENTS.providerReady]: STATES.providerReady,
      [EVENTS.replacementRequiresReproof]: STATES.providerDocumentDiscovered,
    }),
    [STATES.providerReady]: Object.freeze({
      [EVENTS.beginExtraction]: STATES.extracting,
      [EVENTS.replacementRequiresReproof]: STATES.providerDocumentDiscovered,
    }),
    [STATES.extracting]: Object.freeze({
      [EVENTS.captureResult]: STATES.resultReady,
    }),
    [STATES.resultReady]: Object.freeze({
      [EVENTS.deliverResult]: STATES.resultDelivered,
    }),
    [STATES.resultDelivered]: Object.freeze({
      [EVENTS.requestCleanup]: STATES.cleanupRequested,
    }),
    [STATES.cleanupRequested]: Object.freeze({
      [EVENTS.confirmCleanup]: STATES.cleanupConfirmed,
    }),
    [STATES.cleanupConfirmed]: Object.freeze({
      [EVENTS.complete]: STATES.complete,
      [EVENTS.cancel]: STATES.cancelled,
      [EVENTS.fail]: STATES.failed,
    }),
  });

  const terminalStates = new Set([
    STATES.complete,
    STATES.cancelled,
    STATES.expired,
    STATES.failed,
  ]);

  function transition(state, event) {
    if (!Object.values(STATES).includes(state) || !Object.values(EVENTS).includes(event)) {
      return null;
    }
    const normal = nextByState[state]?.[event];
    if (normal) return normal;
    if (terminalStates.has(state)) return null;
    if (event === EVENTS.requestCleanup) return STATES.cleanupRequested;
    if (event === EVENTS.cancel) return STATES.cancelled;
    if (event === EVENTS.expire) return STATES.expired;
    if (event === EVENTS.fail) return STATES.failed;
    return null;
  }

  // Safari may report a replacement and removal in either order. Keep this
  // event coalescer in the production reducer so the exact listener behavior
  // can be exercised without a browser. A replacement is only a candidate;
  // ownership still requires the normal trusted content-script proof.
  function createTabLifecycleListeners(options) {
    let settlement = 0;
    let replacementCandidate = null;
    const onRemoved = (tabID) => {
      if (!options.isActive() || options.isClosing()
          || tabID !== options.ownedTabID()) return;
      if (replacementCandidate !== null) return;
      const ticket = ++settlement;
      options.defer(() => {
        if (ticket === settlement && replacementCandidate === null
            && options.isActive() && !options.isClosing()) {
          options.onUnreplacedRemoval(tabID);
        }
      });
    };
    const onReplaced = (addedTabID, removedTabID) => {
      if (!options.isActive() || removedTabID !== options.ownedTabID()
          || !Number.isInteger(addedTabID) || addedTabID < 0) return;
      settlement += 1;
      replacementCandidate = addedTabID;
      options.onReplacementCandidate(addedTabID, removedTabID);
    };
    return Object.freeze({onRemoved, onReplaced});
  }

  root.UMAOwnedProviderTabV2Reducer = Object.freeze({
    STATES,
    EVENTS,
    transition,
    createTabLifecycleListeners,
    isTerminal: (state) => terminalStates.has(state),
  });
})(globalThis);
