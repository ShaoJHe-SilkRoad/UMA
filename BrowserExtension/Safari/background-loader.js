globalThis.UMA_BROWSER_CONFIG = Object.freeze({
  browserFamily: "safari",
  nativeApplication: "com.silkrd.uma",
  supportsAutomaticRefresh: true,
  supportsManualAction: false,
  exactHostPermission: "https://claude.ai/new*",
  providerHostPermissions: Object.freeze({
    claude: "https://claude.ai/new*",
    gemini: "https://gemini.google.com/usage*",
  }),
  wakeMessageName: "umaClaudeWakeBridge",
  automaticRefreshMessageName: "umaClaudeAutomaticRefresh",
  closeOwnedTabMessageName: "umaClaudeCloseOwnedUsageTab",
});
