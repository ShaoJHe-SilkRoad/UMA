(function () {
  "use strict";

  const extractor = globalThis.UMAClaudeUsageExtractor;
  const runtime = globalThis.browser?.runtime || globalThis.chrome?.runtime;
  if (!extractor || !runtime || !extractor.exactUsageURL(globalThis.location)) return;

  const readinessTimeoutMilliseconds = 20_000;
  const readinessPollMilliseconds = 500;
  const stateKey = "__umaClaudeUsageContentState";
  const ownedTabBindMessage = "umaClaudeOwnedTabBind";
  const ownedTabChallengeMessage = "umaClaudeOwnedTabChallenge";
  const ownedTabProofMessage = "umaClaudeOwnedTabProof";
  const extractUsageMessage = "umaClaudeExtractUsage";
  const tokenPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

  if (globalThis[stateKey]) return;
  const state = { ownershipToken: null, extractionInFlight: false };
  Object.defineProperty(globalThis, stateKey, { value: state, configurable: false });

  async function extractAfterUsageLandmarksRender() {
    const deadline = Date.now() + readinessTimeoutMilliseconds;
    let result;
    do {
      // extractResult repeats the exact-route gate before every DOM query.
      // usageUnavailable is the only retryable state because Claude's Usage
      // landmarks can render after the document load event in the SPA.
      result = extractor.extractResult(document, location, new Date());
      if (result.status !== "usageUnavailable" || Date.now() >= deadline) break;
      await delay(readinessPollMilliseconds);
    } while (true);

    const message = result.status === "success"
      ? { type: "umaClaudeUsageResult", status: result.status, observation: result.observation }
      : { type: "umaClaudeUsageResult", status: result.status };
    runtime.sendMessage(message).catch?.(() => {});
  }

  runtime.onMessage.addListener((message) => {
    if (!extractor.exactUsageURL(globalThis.location)
        || !message || typeof message !== "object") return undefined;
    if (message.type === ownedTabBindMessage
        && Object.keys(message).sort().join(",") === "token,type"
        && tokenPattern.test(message.token)) {
      state.ownershipToken = message.token;
      return Promise.resolve({ type: ownedTabProofMessage, token: message.token });
    }
    if (message.type === ownedTabChallengeMessage
        && Object.keys(message).length === 1
        && state.ownershipToken) {
      return Promise.resolve({ type: ownedTabProofMessage, token: state.ownershipToken });
    }
    if (message.type === extractUsageMessage
        && Object.keys(message).length === 1
        && !state.extractionInFlight) {
      state.extractionInFlight = true;
      void extractAfterUsageLandmarksRender().finally(() => {
        state.extractionInFlight = false;
      });
    }
    return undefined;
  });
})();
