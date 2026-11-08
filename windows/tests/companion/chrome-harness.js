// A stand-in for Chrome's extension APIs, the native host port, timers and the clock, so the shipped
// background-chromium.js runs unchanged. The provider page is simulated by the content-script protocol
// (umaClaude*V2 Port messages); the real content script and extractor are covered by extractor-checks.js.
(function (root) {
  "use strict";
  const RealDate = Date;
  const realSetTimeout = root.setTimeout.bind(root);
  const config = Object.freeze({
    browserFamily: "chromium", nativeApplication: "com.silkrd.auv.claude_browser",
    exactHostPermission: "https://claude.ai/new*", companionVersion: "1.0.0", companionBuild: "2026110801",
    protocolSchemaVersion: 2, containingApplicationIdentifier: "com.silkrd.auv.windows", teamIdentifier: "",
    runtimeGenerationID: "5f0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e",
  });
  const extensionID = "jnbjegolfmhehndgimjidefmggpnagji";
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

  // ---- Virtual clock ----
  let now = RealDate.parse("2026-11-08T03:00:00.000Z");
  class VirtualDate extends RealDate {
    constructor(...values) { if (values.length === 0) super(now); else super(...values); }
    static now() { return now; }
  }
  let timerSequence = 0;
  const timers = new Map();
  function installClock() {
    root.Date = VirtualDate;
    root.setTimeout = (callback, delay) => { timerSequence += 1; timers.set(timerSequence, { callback, due: now + Math.max(0, delay || 0) }); return timerSequence; };
    root.clearTimeout = (id) => { timers.delete(id); };
  }
  const realClearTimeout = root.clearTimeout.bind(root);
  function uninstallClock() { root.Date = RealDate; root.setTimeout = realSetTimeout; root.clearTimeout = realClearTimeout; }
  async function flush() { for (let i = 0; i < 30; i += 1) await new Promise((resolve) => realSetTimeout(resolve, 0)); }
  async function advance(milliseconds) {
    const target = now + milliseconds;
    while (true) {
      await flush();
      let next = null;
      for (const [id, timer] of timers) if (timer.due <= target && (!next || timer.due < next[1].due)) next = [id, timer];
      if (!next) break;
      timers.delete(next[0]);
      now = Math.max(now, next[1].due);
      try { next[1].callback(); } catch (_) {}
    }
    now = target;
    await flush();
  }

  // ---- Fake Chrome ----
  function listenerSet() {
    const listeners = [];
    return {
      listeners,
      addListener: (listener) => listeners.push(listener),
      removeListener: (listener) => { const i = listeners.indexOf(listener); if (i >= 0) listeners.splice(i, 1); },
      fire: (...args) => { for (const listener of listeners.slice()) listener(...args); },
    };
  }
  function makeWorld(previous) {
    const world = {
      sessionStorage: previous ? previous.sessionStorage : new Map(),
      localStorage: previous ? previous.localStorage : new Map(),
      tabs: previous ? previous.tabs : new Map(),
      windows: previous ? previous.windows : new Map([[1, { id: 1, state: "normal", incognito: false }]]),
      nextTab: previous ? previous.nextTab : 100,
      nextWindow: previous ? previous.nextWindow : 10,
      nativePorts: [], hostAvailable: true, permission: true, reloads: 0, created: [], removed: [], removedWindows: [], updated: [],
    };
    const onConnect = listenerSet(), onRemoved = listenerSet(), onReplaced = listenerSet(), onUpdated = listenerSet();
    const onAlarm = listenerSet(), onStartup = listenerSet(), onInstalled = listenerSet(), onClicked = listenerSet();
    function store(map) {
      return {
        get: async (key) => (map.has(key) ? { [key]: JSON.parse(JSON.stringify(map.get(key))) } : {}),
        set: async (items) => { for (const [k, v] of Object.entries(items)) map.set(k, JSON.parse(JSON.stringify(v))); },
        remove: async (key) => { map.delete(key); },
      };
    }
    function newTab(url, windowId) {
      const id = world.nextTab++;
      const tab = { id, url, windowId };
      world.tabs.set(id, tab); world.created.push(tab);
      return tab;
    }
    world.onConnect = onConnect; world.onRemoved = onRemoved; world.onAlarm = onAlarm; world.onClicked = onClicked;
    world.chrome = {
      runtime: {
        id: extensionID,
        lastError: undefined,
        connectNative(name) {
          if (name !== config.nativeApplication) throw new Error("unknown host");
          const port = { name, inbox: [], connected: true, onMessage: listenerSet(), onDisconnect: listenerSet() };
          port.postMessage = (message) => { if (!port.connected) throw new Error("disconnected"); port.inbox.push(JSON.parse(JSON.stringify(message))); };
          port.disconnect = () => { port.connected = false; };
          world.nativePorts.push(port);
          if (!world.hostAvailable) { port.connected = false; Promise.resolve().then(() => port.onDisconnect.fire()); }
          return port;
        },
        reload() { world.reloads += 1; },
        onConnect, onStartup, onInstalled, onMessage: listenerSet(),
      },
      storage: { session: store(world.sessionStorage), local: store(world.localStorage) },
      permissions: { contains: async () => world.permission },
      alarms: { create: () => {}, onAlarm },
      action: { onClicked },
      windows: {
        getAll: async () => [...world.windows.values()].map((w) => ({ ...w })),
        get: async (id, options) => {
          const w = world.windows.get(id); if (!w) throw new Error("No window with id: " + id);
          return { ...w, tabs: options?.populate ? [...world.tabs.values()].filter((t) => t.windowId === id).map((t) => ({ id: t.id })) : undefined };
        },
        create: async (options) => {
          const id = world.nextWindow++;
          world.windows.set(id, { id, state: options.state || "normal", incognito: false, temporary: true });
          const tab = newTab(options.url, id);
          return { id, tabs: [{ id: tab.id }] };
        },
        remove: async (id) => {
          world.windows.delete(id); world.removedWindows.push(id);
          for (const tab of [...world.tabs.values()].filter((t) => t.windowId === id)) { world.tabs.delete(tab.id); world.removed.push(tab.id); onRemoved.fire(tab.id, { windowId: id }); }
        },
      },
      tabs: {
        create: async (options) => { if (!world.windows.has(options.windowId)) throw new Error("No window"); return { id: newTab(options.url, options.windowId).id }; },
        get: async (id) => { if (!world.tabs.has(id)) throw new Error("No tab with id: " + id + "."); return { id }; },
        remove: async (id) => { if (!world.tabs.has(id)) throw new Error("No tab with id: " + id + "."); world.tabs.delete(id); world.removed.push(id); onRemoved.fire(id, {}); },
        update: async (id, properties) => { world.updated.push({ id, ...properties }); return { id }; },
        onRemoved, onReplaced, onUpdated,
      },
    };
    return world;
  }

  // ---- AUV and the provider page ----
  function host(world) { return world.nativePorts.filter((p) => p.connected).at(-1); }
  function sendCommand(world, command, extra = {}) {
    const requestID = crypto.randomUUID();
    host(world).onMessage.fire({ kind: "auvCompanionCommand", schemaVersion: 1, command, requestID, ...extra });
    return requestID;
  }
  function messagesFor(world, requestID) {
    return world.nativePorts.flatMap((p) => p.inbox).filter((m) => m.requestID === requestID);
  }
  function terminalFor(world, requestID) {
    return messagesFor(world, requestID).find((m) => m.kind === "claudeBrowserTerminalPacket");
  }
  const observation = () => ({
    fiveHour: { usedPercentage: 8, resetAt: "2026-11-08T05:40:00.000Z" },
    weeklyAllModels: { usedPercentage: 41, resetAt: null },
    modelSpecificWeekly: null, observedAt: new Date().toISOString(), extractorSchemaVersion: 2, sourceLayoutVersion: 1,
  });
  // The content-script side of the owned tab. `answer` decides how the page behaves.
  function openPage(world, tabID, answer = "healthy", nonceOverride = null) {
    const tab = world.tabs.get(tabID);
    const url = new URL(tab.url);
    const nonce = nonceOverride || new URLSearchParams(url.hash.slice("#settings/usage?".length)).get("uma_ot");
    const page = { received: [], connected: true };
    const port = {
      name: "umaClaudeOwnedProviderV2",
      sender: { id: extensionID, frameId: 0, origin: "https://claude.ai", url: "https://claude.ai/new#settings/usage", tab: { id: tabID } },
      onMessage: listenerSet(), onDisconnect: listenerSet(),
      postMessage: (message) => {
        page.received.push(message);
        const reply = (type, more = {}) => Promise.resolve().then(() => page.toBackground({ type, requestID: message.requestID, runtimeGenerationID: message.runtimeGenerationID, ...more }));
        if (message.type === "umaClaudeProviderOwnershipAcceptedV2") reply("umaClaudeProviderReadyV2");
        if (message.type === "umaClaudeExtractProviderUsageV2" && answer === "healthy" && !page.answered) {
          page.answered = true;
          reply("umaClaudeProviderResultV2", { status: "success", observation: observation() });
        }
        if (message.type === "umaClaudeExtractProviderUsageV2" && answer === "signIn" && !page.answered) {
          page.answered = true;
          reply("umaClaudeProviderResultV2", { status: "signInRequired", providerFailureReason: "PROVIDER_SESSION_UNAVAILABLE" });
        }
      },
      disconnect: () => { page.connected = false; },
    };
    page.toBackground = (message) => port.onMessage.fire(message);
    world.onConnect.fire(port);
    page.toBackground({ type: "umaClaudeProviderDocumentDiscoveredV2", ownershipNonce: nonce });
    return page;
  }

  // ---- Loading the worker ----
  let workerSource = null;
  async function startWorker(previous) {
    if (!workerSource) workerSource = await (await fetch("/windows/browser-extension/background-chromium.js", { cache: "no-store" })).text();
    const world = makeWorld(previous);
    root.chrome = world.chrome;
    root.UMA_BROWSER_CONFIG = config;
    (0, eval)(workerSource);
    await flush();
    return world;
  }

  async function run() {
    const results = [];
    const savedChrome = root.chrome;
    installClock();
    const check = async (name, body) => {
      timers.clear();
      try { const detail = await body(); results.push({ name, pass: detail === true, detail: detail === true ? "" : JSON.stringify(detail) }); }
      catch (error) { results.push({ name, pass: false, detail: String(error && error.stack || error) }); }
    };

    await check("cold start connects to the host and answers wake and qualification with its identity", async () => {
      const world = await startWorker();
      if (world.nativePorts.length !== 1) return { ports: world.nativePorts.length };
      const wake = sendCommand(world, "umaClaudeWakeBridge");
      const qualify = sendCommand(world, "umaClaudeRuntimeQualification");
      await flush();
      const [ready] = messagesFor(world, wake); const [bridge] = messagesFor(world, qualify);
      const ok = ready?.status === "extensionBackgroundReady" && bridge?.status === "bridgeReady"
        && ready.browserFamily === "chromium" && ready.extensionIdentifier === extensionID && ready.teamIdentifier === ""
        && ready.runtimeGenerationID === config.runtimeGenerationID && ready.companionBuild === config.companionBuild;
      return ok || { ready, bridge };
    });

    await check("a read opens an inactive tab, proves ownership, reports the reading and closes the tab", async () => {
      const world = await startWorker();
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const tab = world.created.at(-1);
      if (!tab || tab.windowId !== 1 || !/^https:\/\/claude\.ai\/new#settings\/usage\?uma_ot=[A-Za-z0-9_-]{43}$/.test(tab.url)) return { tab };
      openPage(world, tab.id);
      await advance(100);
      const terminal = terminalFor(world, id);
      const started = messagesFor(world, id).find((m) => m.status === "refreshStarted");
      const ok = started && terminal?.status === "refreshCompleted" && terminal.observation?.observation?.fiveHour?.usedPercentage === 8
        && uuid.test(terminal.observation.observationID) && world.removed.includes(tab.id) && world.sessionStorage.size === 0
        && world.updated.some((u) => u.id === tab.id && u.autoDiscardable === false)
        && !JSON.stringify(terminal).includes("uma_ot") && !JSON.stringify(terminal).includes("https://");
      return ok || { terminal, removed: world.removed, receipts: world.sessionStorage.size };
    });

    await check("with no usable window the read uses a minimized window and closes it", async () => {
      const world = await startWorker();
      world.windows.get(1).state = "minimized";
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const tab = world.created.at(-1);
      const temporary = world.windows.get(tab?.windowId);
      if (!temporary?.temporary || temporary.state !== "minimized") return { tab, temporary };
      openPage(world, tab.id);
      await advance(100);
      return (terminalFor(world, id)?.status === "refreshCompleted" && world.removedWindows.includes(tab.windowId)) || { terminal: terminalFor(world, id), windows: world.removedWindows };
    });

    await check("placement minimizedWindow is honoured even with a normal window open", async () => {
      const world = await startWorker();
      sendCommand(world, "umaClaudeAutomaticRefresh", { placement: "minimizedWindow" });
      await flush();
      const tab = world.created.at(-1);
      return (tab && tab.windowId !== 1 && world.windows.get(tab.windowId)?.state === "minimized") || { tab };
    });

    await check("a page that never answers ends the read early as tabUnavailable", async () => {
      const world = await startWorker();
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const tab = world.created.at(-1);
      openPage(world, tab.id, "silent");
      await advance(8_000);
      const terminal = terminalFor(world, id);
      return (terminal?.status === "tabUnavailable" && world.removed.includes(tab.id)) || { terminal };
    });

    await check("a page that never loads ends at the 30-second deadline and its receipt expires later", async () => {
      const world = await startWorker();
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await advance(31_000);
      const terminal = terminalFor(world, id);
      if (terminal?.status !== "ownedTabOwnershipLost") return { terminal };
      // The unproven tab is never closed; the next read waits until the receipt expires (2 minutes).
      const blocked = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const refused = messagesFor(world, blocked).some((m) => m.status === "ownedTabOwnershipLost");
      await advance(2 * 60_000);
      const later = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const accepted = messagesFor(world, later).some((m) => m.status === "refreshStarted");
      return (refused && accepted && !world.removed.includes(world.created[0].id)) || { refused, accepted };
    });

    await check("the user closing the owned tab ends the read with PROVIDER_TAB_CLOSED", async () => {
      const world = await startWorker();
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const tab = world.created.at(-1);
      openPage(world, tab.id, "silent");
      await advance(500);
      await world.chrome.tabs.remove(tab.id);
      await advance(100);
      const terminal = terminalFor(world, id);
      return (terminal?.status === "tabUnavailable" && terminal.providerFailureReason === "PROVIDER_TAB_CLOSED") || { terminal };
    });

    await check("sign-in required is reported with its reason and the tab is closed", async () => {
      const world = await startWorker();
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const tab = world.created.at(-1);
      openPage(world, tab.id, "signIn");
      await advance(100);
      const terminal = terminalFor(world, id);
      return (terminal?.status === "signInRequired" && terminal.providerFailureReason === "PROVIDER_SESSION_UNAVAILABLE" && world.removed.includes(tab.id)) || { terminal };
    });

    await check("without site access the read stops before opening anything", async () => {
      const world = await startWorker();
      world.permission = false;
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const terminal = terminalFor(world, id);
      // As on the Mac, a read that stops before its receipt exists reports the status without a page reason.
      return (terminal?.status === "permissionRequired" && world.created.length === 0 && world.sessionStorage.size === 0) || { terminal };
    });

    await check("a page presenting the wrong nonce is never proven or closed", async () => {
      const world = await startWorker();
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const tab = world.created.at(-1);
      const page = openPage(world, tab.id, "healthy", "A".repeat(43));
      await advance(100);
      return (page.received.length === 0 && !terminalFor(world, id)) || { received: page.received };
    });

    await check("a second read while one is running is refused, and a repeated command runs once", async () => {
      const world = await startWorker();
      const first = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const second = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const busy = messagesFor(world, second).some((m) => m.kind === "claudeBrowserAutomationEvent" && m.status === "usageUnavailable");
      host(world).onMessage.fire({ kind: "auvCompanionCommand", schemaVersion: 1, command: "umaClaudeWakeBridge", requestID: first });
      const repeatedWake = crypto.randomUUID();
      host(world).onMessage.fire({ kind: "auvCompanionCommand", schemaVersion: 1, command: "umaClaudeWakeBridge", requestID: repeatedWake });
      host(world).onMessage.fire({ kind: "auvCompanionCommand", schemaVersion: 1, command: "umaClaudeWakeBridge", requestID: repeatedWake });
      await flush();
      const wakes = messagesFor(world, repeatedWake).length;
      return (busy && wakes === 1 && world.created.length === 1) || { busy, wakes, created: world.created.length };
    });

    await check("malformed commands are ignored", async () => {
      const world = await startWorker();
      const port = host(world);
      port.onMessage.fire({ kind: "auvCompanionCommand", schemaVersion: 1, command: "umaClaudeAutomaticRefresh", requestID: crypto.randomUUID(), placement: "foreground" });
      port.onMessage.fire({ kind: "auvCompanionCommand", schemaVersion: 1, command: "openUrl", requestID: crypto.randomUUID() });
      port.onMessage.fire({ kind: "auvCompanionCommand", schemaVersion: 1, command: "umaClaudeWakeBridge", requestID: crypto.randomUUID(), url: "https://example.com" });
      await flush();
      return (world.created.length === 0 && port.inbox.length === 0) || { created: world.created.length, inbox: port.inbox };
    });

    await check("AUV closing a read that never finished closes the proven tab", async () => {
      const world = await startWorker();
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      const tab = world.created.at(-1);
      openPage(world, tab.id, "silent");
      await advance(300);
      const close = sendCommand(world, "umaClaudeCloseOwnedUsageTab", { targetRequestID: id });
      await advance(100);
      const terminal = terminalFor(world, close);
      return (terminal?.status === "ownedTabClosed" && terminal.targetRequestID === id && world.removed.includes(tab.id)) || { terminal };
    });

    await check("a lost host port is reconnected with backoff and never given up", async () => {
      const world = await startWorker();
      world.hostAvailable = false;
      host(world).connected = false; world.nativePorts[0].onDisconnect.fire();
      await advance(0);
      await advance(1_000); await advance(5_000); await advance(15_000); await advance(60_000); await advance(60_000);
      const attempts = world.nativePorts.length;
      world.hostAvailable = true;
      await advance(60_000);
      return (attempts >= 6 && Boolean(host(world))) || { attempts, connected: Boolean(host(world)) };
    });

    await check("the liveness check renews a quiet port and reloads at most once per 30 minutes", async () => {
      const world = await startWorker();
      const diagnostics = root.AUVCompanionDiagnostics;
      // The host never answers pings.
      await advance(1_000);
      const check1 = diagnostics.checkLiveness(); await advance(9_000); await check1;
      const renewed = world.nativePorts.length === 2;
      const check2 = diagnostics.checkLiveness(); await advance(9_000); await check2;
      const firstReload = world.reloads === 1;
      for (let i = 0; i < 3; i += 1) { const c = diagnostics.checkLiveness(); await advance(9_000); await c; }
      const spaced = world.reloads === 1;
      // An answer from the host clears the count.
      const c3 = diagnostics.checkLiveness(); host(world).onMessage.fire({ kind: "auvHostStatus", schemaVersion: 1, appConnected: true }); await advance(9_000); await c3;
      return (renewed && firstReload && spaced && diagnostics.state().livenessMisses === 0 && diagnostics.state().appConnected) || { renewed, reloads: world.reloads, state: diagnostics.state() };
    });

    await check("a worker restart mid-read recovers the receipt and closes the proven tab", async () => {
      const first = await startWorker();
      const id = sendCommand(first, "umaClaudeAutomaticRefresh");
      await flush();
      const tab = first.created.at(-1);
      const page = openPage(first, tab.id, "silent");
      await advance(300);
      const nonce = new URLSearchParams(new URL(tab.url).hash.slice("#settings/usage?".length)).get("uma_ot");
      // The worker stops (its timers and host port go with it); the page keeps its nonce and reconnects once to the new worker.
      timers.clear(); for (const port of first.nativePorts) port.connected = false;
      const second = await startWorker(first);
      openPage(second, tab.id, "silent", nonce);
      await advance(31_000);
      return (second.removed.includes(tab.id) && second.sessionStorage.size === 0 && !terminalFor(first, id)?.observation) || { removed: second.removed, receipts: [...second.sessionStorage.keys()], page: page.received.length };
    });

    await check("the toolbar button asks AUV to sync and sends nothing about the tab", async () => {
      const world = await startWorker();
      world.onClicked.fire({ id: 5, url: "https://claude.ai/new#settings/usage", title: "Claude" });
      await flush();
      const [request] = host(world).inbox;
      return (request && Object.keys(request).sort().join(",") === "kind,requestID,schemaVersion" && request.kind === "auvCompanionSyncRequest") || { request };
    });

    await check("only allowlisted fields leave the worker", async () => {
      const world = await startWorker();
      const id = sendCommand(world, "umaClaudeAutomaticRefresh");
      await flush();
      openPage(world, world.created.at(-1).id);
      await advance(100);
      const allowed = new Set(["kind", "schemaVersion", "sourceID", "browserFamily", "requestID", "targetRequestID", "runtimeGenerationID", "status",
        "occurredAt", "observation", "providerFailureReason", "routeState", "observationID", "fiveHour", "weeklyAllModels", "modelSpecificWeekly",
        "observedAt", "extractorSchemaVersion", "sourceLayoutVersion", "usedPercentage", "resetAt", "trace", "companionVersion", "companionBuild",
        "protocolSchemaVersion", "containingApplicationIdentifier", "extensionIdentifier", "teamIdentifier", "pingID"]);
      const keys = new Set();
      const walk = (value) => { if (value && typeof value === "object") for (const [k, v] of Object.entries(value)) { keys.add(k); walk(v); } };
      for (const message of world.nativePorts.flatMap((p) => p.inbox)) walk(message);
      const extra = [...keys].filter((k) => !allowed.has(k));
      return (extra.length === 0 && Boolean(terminalFor(world, id))) || { extra };
    });

    uninstallClock();
    root.chrome = savedChrome;
    return results.map((r) => ({ ...r, name: "worker: " + r.name }));
  }

  root.AUVChromeHarness = Object.freeze({ run });
})(globalThis);
