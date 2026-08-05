globalThis.UMA_BROWSER_CONFIG = Object.freeze({
  browserFamily: "chromium",
  nativeApplication: "com.silkrd.uma.claude_browser",
  supportsAutomaticRefresh: false,
  supportsManualAction: true,
});
importScripts("../Shared/claude-usage-extractor.js", "../Shared/background-core.js");
