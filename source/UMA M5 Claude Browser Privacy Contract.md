# UMA M5 Claude Browser Privacy Contract

Date: 2026-08-01
Goal: M5-BROWSER-G1
Status: mandatory production boundary

## Core promise

Claude authentication stays entirely in the user's system default browser.
UMA receives only normalized usage percentages, matching reset times, schema
metadata, observation time, browser family, and a fixed safe extractor state.

UMA does not receive or inspect passwords, passkeys, verification codes, OAuth
tokens, authorization headers, cookies, browser profiles, account identity,
login-page content, raw HTML, broad DOM text, chats, projects, billing, payment,
or task history.

## Permanently forbidden Claude routes

- Keychain or Security.framework credential reads;
- the provider-owned `Claude Code-credentials` item;
- credential-continuity digests or token-derived identifiers;
- bearer-token handling or direct private quota requests;
- `/api/oauth/usage` or another replayed private endpoint;
- a UMA OAuth client, embedded login, WKWebView login, or callback
  impersonation;
- Cookie API, cookie export, browser-profile copying, browser database access,
  request interception, or login-page DOM inspection;
- manual or inferred quota.

No legacy consent is migrated into Browser Sync consent.

## WebExtension permission boundary

The companion uses exactly three permissions: `activeTab`, `scripting`, and
`nativeMessaging`. It has no persistent host permission and declares no static
content script. One explicit toolbar click grants temporary access to the
current tab for one bounded extraction attempt only.

It must not request `<all_urls>`, cookies, history, bookmarks, downloads,
`webRequest`, proxy, debugger, clipboard, file URL, incognito, or broad tab
inventory access. It must not inject into Google authentication, Claude login,
account identity, billing, chats, projects, or unrelated analytics pages. It
does not query, create, enumerate, monitor, or listen for tab or navigation
events.

The background worker first validates the clicked tab as exactly
`https://claude.ai/new#settings/usage` before injection. The fixed packaged
extractor independently repeats HTTPS, origin, pathname, query, and fragment
validation before any DOM access. It then validates expected Usage landmarks,
absence of a login form, and separability
of account-level quota from billing and model-specific sections. Route or
landmark drift, duplicate ambiguous labels, and scope ambiguity fail closed.

The extractor uses the narrowest required landmarks. It never serializes the
document, page body, raw HTML, broad text, scripts, query values, or unrelated
page sections. It performs no mutation observation, timer-driven retry, or
background refresh; another read requires another explicit toolbar click.

## Message boundary

The native message is a bounded, versioned allowlist object. Each quota window
has an explicit scope, one finite `0...100` used-or-remaining value, and its
own optional validated reset. The message may also contain fixed source and
browser enums, observation time, extractor schema version, and a fixed safe
state enum.

The extension, native host, and main app each reject:

- unknown or duplicate keys;
- oversized, truncated, malformed, or invalid-UTF-8 frames;
- wrong schema or source IDs;
- arbitrary strings where a fixed enum is required;
- negative, greater-than-100, or nonfinite percentages;
- both used and remaining for one window;
- an unscoped model-specific window;
- raw DOM, HTML, URL, identity, billing, cookie, token, or login fields.

Raw page content cannot cross the extension boundary, including in diagnostics
or error payloads.

## Chrome host and Safari extension

The Chrome native-host manifest allowlists exactly the packaged extension ID
and exact immutable host binary. The host validates bounded length-prefixed
stdin/stdout messages before allocation. It accepts no arbitrary command,
network operation, secret argument, browser profile, broad filesystem path, or
daemon mode.

The Safari path accepts only the bundled extension and uses the same normalized
schema and bounds. It forwards the validated payload through one exact
owner-only Application Support directory rather than requesting a network
entitlement. The directory is `0700`; the active-listener lock, temporary
observation, and pending observation are `0600`. The writer requires a live
exclusive UMA lock, uses no alternate path, writes atomically, and the reader
removes the observation after one bounded read. A competing listener cannot
replace or unlink the active lock. Wrong extension identity, host path, owner,
signature, file type, mode, symlink state, schema, or source fails closed.

## Consent, retention, and disconnect

- Consent is explicit, versioned, and specific to Browser Sync.
- No current observation means no first admission.
- A safely persisted snapshot contains only normalized quota data and bounded
  provenance metadata.
- Restored data is Cached/Stale, never Fresh.
- Authentication or route uncertainty withdraws Fresh state immediately.
- Disconnect clears consent, primary and backup sanitized Claude snapshots,
  live channels, timers, and UMA-owned host state.
- Disconnect does not sign out Claude, clear cookies, modify history, or alter
  another browser or extension.

## Diagnostics and evidence

Diagnostics use fixed safe categories and counters only. Git, tests, packages,
logs, reports, and screenshots contain no real identity, credential, cookie,
token, URL query, raw page data, exact live percentage, or exact live reset.
Fixtures are synthetic and visibly classified as fixtures.

Static scans must prove that production and packaged artifacts contain no
Claude broker, provider Keychain service, token parser, bearer header, private
quota endpoint, embedded-login implementation, or rejected permission. Earlier
historical records may name rejected designs only when clearly marked as
superseded and non-executable.

The accepted Safari live run retained no exact quota, reset, identity, URL,
raw page content, cookie, credential, or screenshot. Fixed safe log categories
recorded only whether one sanitized observation was forwarded. The owner-only
sanitized cache and handoff metadata were verified, and bounded idle time
produced no background write.
