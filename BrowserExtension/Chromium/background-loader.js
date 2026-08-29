globalThis.UMA_BROWSER_CONFIG = Object.freeze({
  browserFamily: "chromium",
  nativeApplication: "com.silkrd.uma.claude_browser",
  supportsAutomaticRefresh: false,
  supportsManualAction: true,
});
importScripts(
  "../Shared/claude-usage-extractor.js",
  "../Shared/provider-ownership-v2.js",
  "../Shared/owned-provider-tab-v2-reducer.js",
  "../Shared/background-core.js"
);
