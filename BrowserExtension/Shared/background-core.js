(function (root) {
  "use strict";

  const extractor = root.UMAClaudeUsageExtractor;
  const config = root.UMA_BROWSER_CONFIG;
  const api = root.browser || root.chrome;
  if (!extractor || !config || !api?.runtime) return;

  const allowedSenderURL = (raw) => {
    try { return extractor.exactUsageURL(new URL(raw)); } catch (_) { return false; }
  };

  const usageScriptFiles = Object.freeze([
    "Shared/claude-usage-extractor.js",
    "Shared/content-script.js",
  ]);

  async function injectExactUsageRoute(tab) {
    if (!Number.isInteger(tab?.id) || !allowedSenderURL(tab?.url || "")) return false;
    if (!api.scripting?.executeScript) return false;
    try {
      await api.scripting.executeScript({
        target: { tabId: tab.id, allFrames: false },
        files: usageScriptFiles,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  async function forwardObservation(message, sender) {
    if (!message || Object.keys(message).sort().join(",") !== "observation,type") return;
    if (message.type !== "umaClaudeUsageObservation") return;
    if (!allowedSenderURL(sender?.url || sender?.tab?.url || "")) return;
    if (!extractor.validateObservation(message.observation)) return;

    const envelope = {
      kind: "claudeUsageObservation",
      schemaVersion: 1,
      sourceID: "claude-browser-usage",
      browserFamily: config.browserFamily,
      routeState: "verifiedUsage",
      observation: message.observation,
    };
    try {
      await api.runtime.sendNativeMessage(config.nativeApplication, envelope);
    } catch (_) {
      // UMA not running or the exact native companion is unavailable. No data
      // is persisted in the extension and no alternate destination is tried.
    }
  }

  api.runtime.onMessage.addListener((message, sender) => {
    void forwardObservation(message, sender);
  });

  api.action?.onClicked?.addListener((tab) => {
    void injectExactUsageRoute(tab);
  });
})(globalThis);
