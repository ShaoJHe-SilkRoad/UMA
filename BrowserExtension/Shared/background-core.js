(function (root) {
  "use strict";

  const extractor = root.UMAClaudeUsageExtractor;
  const config = root.UMA_BROWSER_CONFIG;
  const api = root.browser || root.chrome;
  if (!extractor || !config || !api?.runtime) return;

  const usageScriptFiles = Object.freeze([
    "Shared/claude-usage-extractor.js",
    "Shared/content-script.js",
  ]);
  const resultStatuses = Object.freeze([
    "success",
    "signInRequired",
    "routeRejected",
    "usageUnavailable",
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
  const pollingIntervalMilliseconds = 200;
  const navigationSettleMilliseconds = 1_000;
  const automaticTimeoutMilliseconds = 30_000;
  const ownedTabStorageKey = "umaClaudeOwnedUsageTab.v1";
  const ownedTabBindMessage = "umaClaudeOwnedTabBind";
  const ownedTabChallengeMessage = "umaClaudeOwnedTabChallenge";
  const ownedTabProofMessage = "umaClaudeOwnedTabProof";
  const extractUsageMessage = "umaClaudeExtractUsage";

  let injectionInFlight = false;
  let automaticRead = null;
  let nativePort = null;
  let nativeReconnectTimer = null;
  let nativeQueue = Promise.resolve();

  function isPlainObject(value) {
    return Boolean(value) && Object.getPrototypeOf(value) === Object.prototype;
  }

  function exactKeys(value, expected) {
    return isPlainObject(value) && Object.keys(value).sort().join(",") === expected.slice().sort().join(",");
  }

  function allowedSenderURL(raw) {
    try { return extractor.exactUsageURL(new URL(raw)); } catch (_) { return false; }
  }

  function delay(milliseconds) {
    return new Promise((resolve) => setTimeout(resolve, milliseconds));
  }

  function sendNative(payload) {
    nativeQueue = nativeQueue
      .then(() => api.runtime.sendNativeMessage(config.nativeApplication, payload))
      .catch(() => undefined);
    return nativeQueue;
  }

  function automationEnvelope(requestID, status) {
    return {
      kind: "claudeBrowserAutomationEvent",
      schemaVersion: 1,
      sourceID: "claude-browser-usage",
      browserFamily: "safari",
      requestID,
      status,
      occurredAt: new Date().toISOString(),
    };
  }

  function observationEnvelope(observation) {
    return {
      kind: "claudeUsageObservation",
      schemaVersion: 1,
      sourceID: "claude-browser-usage",
      browserFamily: config.browserFamily,
      routeState: "verifiedUsage",
      observation,
    };
  }

  async function injectExactUsageRoute(tab) {
    if (!Number.isInteger(tab?.id) || !allowedSenderURL(tab?.url || "")) return false;
    if (injectionInFlight) return false;
    injectionInFlight = true;
    try {
      if (api.scripting?.executeScript) {
        await api.scripting.executeScript({
          target: { tabId: tab.id, allFrames: false },
          files: usageScriptFiles,
        });
      } else if (api.tabs?.executeScript) {
        for (const file of usageScriptFiles) {
          await api.tabs.executeScript(tab.id, { file, allFrames: false });
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

  function validOwnershipRecord(value) {
    return exactKeys(value, ["tabID", "token"])
      && Number.isInteger(value.tabID)
      && value.tabID >= 0
      && requestIDPattern.test(value.token);
  }

  async function loadOwnershipRecord() {
    if (!api.storage?.local?.get) return null;
    try {
      const stored = await api.storage.local.get(ownedTabStorageKey);
      const record = stored?.[ownedTabStorageKey];
      return validOwnershipRecord(record) ? record : null;
    } catch (_) {
      return null;
    }
  }

  async function storeOwnershipRecord(record) {
    if (!validOwnershipRecord(record) || !api.storage?.local?.set) return false;
    try {
      await api.storage.local.set({ [ownedTabStorageKey]: record });
      return true;
    } catch (_) {
      return false;
    }
  }

  async function clearOwnershipRecord() {
    if (!api.storage?.local?.remove) return;
    try { await api.storage.local.remove(ownedTabStorageKey); } catch (_) {}
  }

  async function proveOwnedTab(record, tab) {
    if (!validOwnershipRecord(record)
        || tab?.id !== record.tabID
        || !allowedSenderURL(tab?.url || "")
        || !api.tabs?.sendMessage) return false;
    try {
      const proof = await api.tabs.sendMessage(record.tabID, {
        type: ownedTabChallengeMessage,
      });
      return exactKeys(proof, ["token", "type"])
        && proof.type === ownedTabProofMessage
        && proof.token === record.token;
    } catch (_) {
      return false;
    }
  }

  async function bindOwnedTab(record) {
    if (!validOwnershipRecord(record) || !api.tabs?.sendMessage) return false;
    try {
      const proof = await api.tabs.sendMessage(record.tabID, {
        type: ownedTabBindMessage,
        token: record.token,
      });
      return exactKeys(proof, ["token", "type"])
        && proof.type === ownedTabProofMessage
        && proof.token === record.token;
    } catch (_) {
      return false;
    }
  }

  async function requestOwnedExtraction(record) {
    if (!validOwnershipRecord(record) || !api.tabs?.sendMessage) return false;
    try {
      await api.tabs.sendMessage(record.tabID, { type: extractUsageMessage });
      return true;
    } catch (_) {
      return false;
    }
  }

  async function closeProvenOwnedTab(record, directlyCreated) {
    if (!validOwnershipRecord(record) || !api.tabs?.get || !api.tabs?.remove) return false;
    let tab;
    try { tab = await api.tabs.get(record.tabID); } catch (_) {
      await clearOwnershipRecord();
      return true;
    }
    const proven = directlyCreated || await proveOwnedTab(record, tab);
    if (!proven) {
      await clearOwnershipRecord();
      return false;
    }
    try { await api.tabs.remove(record.tabID); } catch (_) {}
    await clearOwnershipRecord();
    return true;
  }

  async function finishAutomatic(read, status, observation) {
    if (!read || automaticRead !== read || read.finished) return;
    read.finished = true;
    if (read.timeoutID !== null) clearTimeout(read.timeoutID);

    automaticRead = null;

    if (status === "signInRequired" || status === "routeRejected") {
      await closeProvenOwnedTab(read.record, read.directlyCreated);
    } else if (status === "tabUnavailable" || status === "ownedTabOwnershipLost") {
      await clearOwnershipRecord();
    }

    if (status === "refreshCompleted" && extractor.validateObservation(observation)) {
      await sendNative(observationEnvelope(observation));
    }
    await sendNative(automationEnvelope(read.requestID, status));
  }

  async function handleContentResult(message, sender) {
    if (!isPlainObject(message) || message.type !== "umaClaudeUsageResult") return;
    if (!resultStatuses.includes(message.status)) return;
    const expectedKeys = message.status === "success"
      ? ["observation", "status", "type"]
      : ["status", "type"];
    if (!exactKeys(message, expectedKeys)) return;
    if (!Number.isInteger(sender?.tab?.id) || !allowedSenderURL(sender?.url || sender?.tab?.url || "")) return;

    const read = automaticRead;
    if (read && sender.tab.id === read.tabID) {
      if (message.status === "success" && extractor.validateObservation(message.observation)) {
        await finishAutomatic(read, "refreshCompleted", message.observation);
      } else if (automaticFailureStatuses.has(message.status)) {
        await finishAutomatic(read, message.status);
      }
      return;
    }

    if (message.status === "success" && extractor.validateObservation(message.observation)) {
      await sendNative(observationEnvelope(message.observation));
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

  async function pollOwnedTab(read) {
    const deadline = Date.now() + automaticTimeoutMilliseconds;
    while (automaticRead === read && !read.finished && Date.now() < deadline) {
      let tab;
      try { tab = await api.tabs.get(read.tabID); } catch (_) {
        await finishAutomatic(read, "tabUnavailable");
        return;
      }
      if (!Number.isInteger(tab?.id) || tab.id !== read.tabID) {
        await finishAutomatic(read, "tabUnavailable");
        return;
      }
      if (tab.status === "complete") {
        if (!allowedSenderURL(tab.url || "")) {
          // No DOM access occurs on redirects or login pages. Authentication
          // uncertainty is reported using only the owned tab's route state.
          await finishAutomatic(read, "signInRequired");
          return;
        }
        if (!(await injectExactUsageRoute(tab))) {
          await finishAutomatic(read, "usageUnavailable");
          return;
        }
        if (!(await bindOwnedTab(read.record))) {
          await finishAutomatic(read, "ownedTabOwnershipLost");
          return;
        }
        if (!(await requestOwnedExtraction(read.record))) {
          await finishAutomatic(read, "usageUnavailable");
        }
        return;
      }
      await delay(pollingIntervalMilliseconds);
    }
  }

  async function beginAutomaticRead(requestID) {
    if (!requestIDPattern.test(requestID) || automaticRead) return;
    const read = {
      requestID,
      tabID: null,
      record: null,
      directlyCreated: false,
      timeoutID: null,
      finished: false,
    };
    automaticRead = read;
    await sendNative(automationEnvelope(requestID, "refreshStarted"));

    if (!(await persistentUsageAccessGranted())) {
      await finishAutomatic(read, "permissionRequired");
      return;
    }
    if (!api.tabs?.create || !api.tabs?.get || !api.tabs?.remove
        || !api.tabs?.reload || !api.tabs?.sendMessage || !api.storage?.local) {
      await finishAutomatic(read, "tabUnavailable");
      return;
    }

    let record = await loadOwnershipRecord();
    let tab = null;
    if (record) {
      try { tab = await api.tabs.get(record.tabID); } catch (_) {
        await clearOwnershipRecord();
        record = null;
      }
    }
    if (record && tab) {
      if (!(await proveOwnedTab(record, tab))) {
        await clearOwnershipRecord();
        await finishAutomatic(read, "ownedTabOwnershipLost");
        return;
      }
      read.record = record;
      read.tabID = record.tabID;
      try {
        await api.tabs.reload(record.tabID);
      } catch (_) {
        await finishAutomatic(read, "tabUnavailable");
        return;
      }
    } else {
      try {
        tab = await api.tabs.create({ url: extractor.CONTRACT.href, active: false });
      } catch (_) {
        await finishAutomatic(read, "tabUnavailable");
        return;
      }
      if (!Number.isInteger(tab?.id)) {
        await finishAutomatic(read, "tabUnavailable");
        return;
      }
      record = { tabID: tab.id, token: requestID };
      if (!(await storeOwnershipRecord(record))) {
        try { await api.tabs.remove(tab.id); } catch (_) {}
        await finishAutomatic(read, "tabUnavailable");
        return;
      }
      read.record = record;
      read.tabID = tab.id;
      read.directlyCreated = true;
    }
    read.timeoutID = setTimeout(() => {
      void finishAutomatic(read, "usageUnavailable");
    }, automaticTimeoutMilliseconds);
    // Safari can briefly report the pre-navigation document as complete after
    // creating or reloading an inactive tab. Let the requested navigation
    // commit once before the exact-route poll and isolated script injection.
    await delay(navigationSettleMilliseconds);
    await pollOwnedTab(read);
  }

  async function closeOwnedRead(requestID) {
    if (!requestIDPattern.test(requestID)) return;
    const read = automaticRead;
    if (read) {
      if (read.timeoutID !== null) clearTimeout(read.timeoutID);
      read.finished = true;
      automaticRead = null;
      const closed = await closeProvenOwnedTab(read.record, read.directlyCreated);
      await sendNative(automationEnvelope(
        requestID,
        closed ? "ownedTabClosed" : "ownedTabOwnershipLost"
      ));
      return;
    }
    const record = await loadOwnershipRecord();
    if (!record) return;
    const closed = await closeProvenOwnedTab(record, false);
    await sendNative(automationEnvelope(
      requestID,
      closed ? "ownedTabClosed" : "ownedTabOwnershipLost"
    ));
  }

  function unpackNativeCommand(message) {
    if (exactKeys(message, ["command", "requestID"])) return message;
    if (!exactKeys(message, ["name", "userInfo"])) return null;
    if (!exactKeys(message.userInfo, ["command", "requestID"])) return null;
    if (message.name !== message.userInfo.command) return null;
    return message.userInfo;
  }

  function handleCommandMessage(message) {
    const command = unpackNativeCommand(message);
    if (!command || !requestIDPattern.test(command.requestID)) return;
    if (command.command === config.wakeMessageName) {
      void sendNative(automationEnvelope(command.requestID, "bridgeReady"));
    } else if (command.command === config.automaticRefreshMessageName) {
      void beginAutomaticRead(command.requestID);
    } else if (command.command === config.closeOwnedTabMessageName) {
      void closeOwnedRead(command.requestID);
    }
  }

  function handleNativePortMessage(message) {
    handleCommandMessage(message);
  }

  function connectNativePort() {
    if (!config.supportsAutomaticRefresh || !api.runtime.connectNative || nativePort) return;
    try {
      const port = api.runtime.connectNative(config.nativeApplication);
      nativePort = port;
      port.onMessage.addListener(handleNativePortMessage);
      port.onDisconnect?.addListener(() => {
        if (nativePort !== port) return;
        nativePort = null;
        if (nativeReconnectTimer !== null) clearTimeout(nativeReconnectTimer);
        nativeReconnectTimer = setTimeout(() => {
          nativeReconnectTimer = null;
          connectNativePort();
        }, 1_000);
      });
    } catch (_) {
      nativePort = null;
    }
  }

  api.runtime.onMessage.addListener((message, sender) => {
    if (!sender?.tab && unpackNativeCommand(message)) {
      handleCommandMessage(message);
      return;
    }
    void handleContentResult(message, sender);
  });

  if (config.supportsManualAction) {
    api.action?.onClicked?.addListener((tab) => {
      void (async () => {
        if (await injectExactUsageRoute(tab)) {
          try { await api.tabs.sendMessage(tab.id, { type: extractUsageMessage }); } catch (_) {}
        }
      })();
    });
  }

  connectNativePort();
})(globalThis);
