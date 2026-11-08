(function (root) {
  "use strict";

  const markerName = "uma_ot";
  const markerPattern = /^[A-Za-z0-9_-]{43}$/;
  const providerOrigin = "https://claude.ai";
  const providerPath = "/new";
  const providerRoute = "settings/usage";
  const exactProviderURL = `${providerOrigin}${providerPath}#${providerRoute}`;

  function parseProviderMarker(value) {
    let url;
    try { url = value instanceof URL ? value : new URL(value); } catch (_) { return null; }
    if (url.origin !== providerOrigin || url.pathname !== providerPath) return null;
    const prefix = `#${providerRoute}?`;
    if (!url.hash.startsWith(prefix)) return null;
    const params = new URLSearchParams(url.hash.slice(prefix.length));
    if ([...params.keys()].length !== 1 || !params.has(markerName)) return null;
    const nonce = params.get(markerName) || "";
    return markerPattern.test(nonce) ? nonce : null;
  }

  function providerURLForNonce(nonce) {
    return markerPattern.test(nonce || "")
      ? `${exactProviderURL}?${markerName}=${encodeURIComponent(nonce)}`
      : null;
  }

  async function nonceDigest(nonce) {
    if (!markerPattern.test(nonce || "") || !root.crypto?.subtle) return null;
    const bytes = new TextEncoder().encode(nonce);
    const digest = new Uint8Array(await root.crypto.subtle.digest("SHA-256", bytes));
    return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  }

  function finalizeProviderRoute(historyObject, expectedNonce) {
    let current;
    try { current = new URL(root.location.href); } catch (_) { return false; }
    if (current.href === exactProviderURL) return true;
    if (!historyObject?.replaceState
        || !markerPattern.test(expectedNonce || "")
        || parseProviderMarker(current) !== expectedNonce) return false;
    try {
      historyObject.replaceState(historyObject.state ?? null, "", `${providerPath}#${providerRoute}`);
      return root.location.href === exactProviderURL;
    } catch (_) {
      return false;
    }
  }

  root.UMAProviderOwnershipV2 = Object.freeze({
    markerName,
    markerPattern,
    exactProviderURL,
    parseProviderMarker,
    providerURLForNonce,
    nonceDigest,
    finalizeProviderRoute,
  });
})(globalThis);
