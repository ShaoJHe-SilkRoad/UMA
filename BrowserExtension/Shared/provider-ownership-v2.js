(function (root) {
  "use strict";

  const markerName = "uma_ot";
  const markerPattern = /^[A-Za-z0-9_-]{43}$/;

  // Each provider page the companion may open, with where its one-shot
  // ownership marker rides. The marker is always in the fragment, which never
  // reaches the provider's server, and the content script removes it at
  // document_start before the provider's router can see it.
  //   claude: https://claude.ai/new#settings/usage?uma_ot=<nonce>
  //   gemini: https://gemini.google.com/usage#uma_ot=<nonce>
  const routes = Object.freeze({
    claude: Object.freeze({
      origin: "https://claude.ai",
      path: "/new",
      route: "settings/usage",
    }),
    gemini: Object.freeze({
      origin: "https://gemini.google.com",
      path: "/usage",
      route: null,
    }),
  });

  function exactURLFor(provider) {
    const spec = routes[provider];
    if (!spec) return null;
    return spec.route ? `${spec.origin}${spec.path}#${spec.route}` : `${spec.origin}${spec.path}`;
  }

  const exactProviderURL = exactURLFor("claude");

  function asURL(value) {
    try { return value instanceof URL ? value : new URL(value); } catch (_) { return null; }
  }

  function providerForLocation(value) {
    const url = asURL(value);
    if (!url) return null;
    for (const [provider, spec] of Object.entries(routes)) {
      if (url.origin === spec.origin && url.pathname === spec.path) return provider;
    }
    return null;
  }

  function markerPrefix(provider) {
    const spec = routes[provider];
    return spec.route ? `#${spec.route}?` : "#";
  }

  function parseProviderMarker(value) {
    const url = asURL(value);
    if (!url) return null;
    const provider = providerForLocation(url);
    if (!provider || url.search) return null;
    const prefix = markerPrefix(provider);
    if (!url.hash.startsWith(prefix)) return null;
    const params = new URLSearchParams(url.hash.slice(prefix.length));
    if ([...params.keys()].length !== 1 || !params.has(markerName)) return null;
    const nonce = params.get(markerName) || "";
    return markerPattern.test(nonce) ? nonce : null;
  }

  function providerURLForNonce(nonce, provider = "claude") {
    const exact = exactURLFor(provider);
    if (!exact || !markerPattern.test(nonce || "")) return null;
    const separator = routes[provider].route ? "?" : "#";
    return `${exact}${separator}${markerName}=${encodeURIComponent(nonce)}`;
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
    const provider = providerForLocation(current);
    if (!provider) return false;
    const exact = exactURLFor(provider);
    if (current.href === exact) return true;
    if (!historyObject?.replaceState
        || !markerPattern.test(expectedNonce || "")
        || parseProviderMarker(current) !== expectedNonce) return false;
    const spec = routes[provider];
    try {
      historyObject.replaceState(
        historyObject.state ?? null, "", spec.route ? `${spec.path}#${spec.route}` : spec.path
      );
      return root.location.href === exact;
    } catch (_) {
      return false;
    }
  }

  root.UMAProviderOwnershipV2 = Object.freeze({
    markerName,
    markerPattern,
    exactProviderURL,
    exactURLFor,
    providerForLocation,
    parseProviderMarker,
    providerURLForNonce,
    nonceDigest,
    finalizeProviderRoute,
  });
})(globalThis);
