(function () {
  "use strict";

  const extractor = globalThis.UMAClaudeUsageExtractor;
  const runtime = globalThis.browser?.runtime || globalThis.chrome?.runtime;
  if (!extractor || !runtime || !extractor.exactUsageURL(globalThis.location)) return;
  const observation = extractor.extract(document, location, new Date());
  if (!observation) return;
  runtime.sendMessage({ type: "umaClaudeUsageObservation", observation }).catch?.(() => {});
})();
