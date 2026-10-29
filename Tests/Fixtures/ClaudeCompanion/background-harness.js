// Test double for the Safari companion's background page. It stands in for
// Safari's extension API, the containing app's native port and receipt store,
// timers and the clock, so the shipped background-core.js can run in
// JavaScriptCore. Load it after the extractor and reducer and before
// background-core.js.
(function (root) {
  "use strict";

  const RealDate = Date;
  let nowMilliseconds = RealDate.parse("2026-10-29T03:00:00.000Z");
  class VirtualDate extends RealDate {
    constructor(...values) {
      if (values.length === 0) super(nowMilliseconds);
      else super(...values);
    }
    static now() { return nowMilliseconds; }
  }
  root.Date = VirtualDate;

  // Timers fire only when the test advances the clock. `suspendTimers` models
  // Safari holding back a background page's timers.
  let timerSequence = 0;
  let timersSuspended = false;
  const timers = new Map();
  root.setTimeout = (callback, delay) => {
    timerSequence += 1;
    timers.set(timerSequence, { callback, due: nowMilliseconds + Math.max(0, delay || 0) });
    return timerSequence;
  };
  root.clearTimeout = (id) => { timers.delete(id); };

  let uuidSequence = 0;
  root.crypto = {
    getRandomValues(bytes) {
      for (let index = 0; index < bytes.length; index += 1) bytes[index] = (index * 7 + 3) % 256;
      return bytes;
    },
    randomUUID() {
      uuidSequence += 1;
      return `00000000-0000-4000-8000-${String(uuidSequence).padStart(12, "0")}`;
    },
  };
  root.btoa = (binary) => {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let output = "";
    for (let index = 0; index < binary.length; index += 3) {
      const a = binary.charCodeAt(index);
      const b = index + 1 < binary.length ? binary.charCodeAt(index + 1) : 0;
      const c = index + 2 < binary.length ? binary.charCodeAt(index + 2) : 0;
      output += alphabet[a >> 2] + alphabet[((a & 3) << 4) | (b >> 4)]
        + (index + 1 < binary.length ? alphabet[((b & 15) << 2) | (c >> 6)] : "=")
        + (index + 2 < binary.length ? alphabet[c & 63] : "=");
    }
    return output;
  };

  // The ownership module needs WebCrypto, which JavaScriptCore lacks. Only the
  // three members the background page reads are provided.
  root.UMAProviderOwnershipV2 = Object.freeze({
    markerPattern: /^uma-v2-[A-Za-z0-9_-]{43}$/,
    nonceDigest: async () => "a".repeat(64),
    providerURLForNonce: (nonce) => nonce
      ? `https://claude.ai/new?uma=${nonce}#settings/usage` : null,
  });

  root.UMA_BROWSER_CONFIG = Object.freeze({
    browserFamily: "safari", nativeApplication: "com.silkrd.uma.safarihost",
    supportsAutomaticRefresh: true, supportsManualAction: false,
    exactHostPermission: "https://claude.ai/new*",
    wakeMessageName: "umaClaudeWakeBridge",
    automaticRefreshMessageName: "umaClaudeAutomaticRefresh",
    closeOwnedTabMessageName: "umaClaudeCloseOwnedUsageTab",
    companionVersion: "0.0.1", companionBuild: "202601010000",
    protocolSchemaVersion: 2,
    containingApplicationIdentifier: "com.silkrd.uma.safarihost",
    extensionBundleIdentifier: "com.silkrd.uma.ClaudeBrowserCompanion",
    teamIdentifier: "C6TUZVJ6SJ",
    runtimeGenerationID: "3828ea01-d15a-47dc-8d2b-9ee20967da71",
  });

  const log = [];
  const ports = [];
  const receipts = new Map();
  let tabSequence = 70;
  let windowSequence = 900;
  const windows = new Map();

  function listenerSet() {
    const listeners = [];
    return {
      listeners,
      addListener: (listener) => { listeners.push(listener); },
      removeListener: (listener) => {
        const index = listeners.indexOf(listener);
        if (index >= 0) listeners.splice(index, 1);
      },
    };
  }

  function receiptReply(payload) {
    const id = payload.requestID;
    switch (payload.action) {
      case "loadV2":
        return { ok: true, found: false };
      case "saveV2":
        receipts.set(id, { revision: 1, state: payload.lifecycleState });
        return { ok: true, revision: 1 };
      case "transitionV2":
      case "bindCandidateV2": {
        const receipt = receipts.get(id);
        if (!receipt || receipt.revision !== payload.expectedRevision) return { ok: false };
        receipt.revision += 1;
        if (payload.nextLifecycleState) receipt.state = payload.nextLifecycleState;
        return { ok: true, revision: receipt.revision };
      }
      case "removeV2":
        receipts.delete(id);
        log.push(`receipt-removed ${payload.terminalLifecycleState}`);
        return { ok: true };
      default:
        return { ok: true };
    }
  }

  root.browser = {
    runtime: {
      id: "com.silkrd.uma.ClaudeBrowserCompanion",
      onMessage: listenerSet(),
      onConnect: listenerSet(),
      async sendNativeMessage(_application, payload) {
        if (payload?.kind === "claudeOwnedProviderTabV2ReceiptCommand") return receiptReply(payload);
        if (payload?.kind === "claudeBrowserAutomationEvent") log.push(`automation ${payload.status}`);
        return { ok: true };
      },
      connectNative() {
        const port = {
          onMessage: listenerSet(),
          onDisconnect: listenerSet(),
          postMessage() {},
        };
        ports.push(port);
        log.push("connect-native");
        return port;
      },
    },
    permissions: { contains: async () => true },
    tabs: {
      onRemoved: listenerSet(),
      onReplaced: listenerSet(),
      onUpdated: listenerSet(),
      async create(properties) {
        tabSequence += 1;
        log.push(`tabs.create ${properties.active === false ? "background" : "active"}`);
        return { id: tabSequence };
      },
      async remove(id) { log.push(`tabs.remove ${id}`); },
      async get(id) { return { id }; },
    },
    windows: {
      async create(properties) {
        windowSequence += 1;
        tabSequence += 1;
        const created = { id: windowSequence, tabs: [{ id: tabSequence }] };
        windows.set(created.id, created);
        log.push(`windows.create focused=${properties.focused} ${properties.width}x${properties.height}`);
        return created;
      },
      async get(id) {
        if (!windows.has(id)) throw new Error("no window");
        return windows.get(id);
      },
      async remove(id) {
        windows.delete(id);
        log.push(`windows.remove ${id}`);
      },
    },
  };

  root.UMACompanionHarness = {
    log,
    entries: () => log.slice(),
    clearLog: () => { log.length = 0; },
    portCount: () => ports.length,
    // Delivers a containing-app command on the newest port, as Safari does
    // for SFSafariApplication.dispatchMessage.
    dispatch(command) {
      const port = ports[ports.length - 1];
      for (const listener of port.onMessage.listeners.slice()) listener(command);
    },
    disconnectNewestPort() {
      const port = ports[ports.length - 1];
      for (const listener of port.onDisconnect.listeners.slice()) listener();
    },
    suspendTimers(value) { timersSuspended = value; },
    // Moves the clock forward, firing every due timer in order unless timers
    // are suspended.
    advance(milliseconds) {
      const target = nowMilliseconds + milliseconds;
      for (;;) {
        if (timersSuspended) break;
        let next = null;
        for (const [id, timer] of timers) {
          if (timer.due <= target && (next === null || timer.due < next[1].due)) next = [id, timer];
        }
        if (!next) break;
        timers.delete(next[0]);
        nowMilliseconds = Math.max(nowMilliseconds, next[1].due);
        next[1].callback();
      }
      nowMilliseconds = target;
    },
  };
})(globalThis);
