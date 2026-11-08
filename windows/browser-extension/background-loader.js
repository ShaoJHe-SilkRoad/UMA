// AUV Browser Companion for Claude (Windows). The packaging script fills in the build identity below;
// AUV accepts the companion only when it matches the AUV build that installed it.
globalThis.UMA_BROWSER_CONFIG = Object.freeze({
  browserFamily: "chromium",
  nativeApplication: "com.silkrd.auv.claude_browser",
  exactHostPermission: "https://claude.ai/new*",
  companionVersion: "1.0.0",
  companionBuild: "__AUV_COMPANION_BUILD__",
  protocolSchemaVersion: 2,
  containingApplicationIdentifier: "com.silkrd.auv.windows",
  teamIdentifier: "",
  runtimeGenerationID: "__AUV_RUNTIME_GENERATION_ID__",
});
importScripts(
  "Shared/claude-usage-extractor.js",
  "Shared/provider-ownership-v2.js",
  "Shared/owned-provider-tab-v2-reducer.js",
  "background-chromium.js"
);
