# UMA M5 Claude Browser Source Dossier

Date: 2026-08-01
Goal: M5-BROWSER-G1
Status: Current-Safari live admission passed; secondary distribution pending

## Decision precedence

M5-BROWSER-G1 permanently retires the Claude Keychain/OAuth broker product
route. It does not reopen the rejected embedded account-web prototype. The
only active Claude product-source direction is the system-browser Browser Sync
route documented here.

Earlier local/status-line, Desktop callback, account-web, and OAuth records
remain historical evidence. They are not selectable fallbacks and do not
authorize credential, cookie, private-endpoint, or embedded-login access.

## Selected source

```text
system default browser
→ official Claude authentication controlled by Claude
→ exact current personal Settings → Usage page
→ UMA Browser Companion WebExtension
→ bounded allowlisted extraction
→ bounded native messaging
→ sanitized UMA quota snapshot
```

The browser owns authentication. UMA receives no password, passkey,
verification code, OAuth token, cookie, browser profile, account identity, or
raw page content.

## Contract identifiers

- UMA connector ID: `claude.browserSync`;
- native-message source ID: `claude-browser-usage`;
- native-message kind: `claudeUsageObservation`;
- connector source version: `browser-1`;
- bridge schema version: `1`;
- extractor schema version: `1`;
- maximum native-message payload: `4096` bytes.

Live preflight established that the provider redirects the former
`/settings/usage` path to the SPA route
`https://claude.ai/new#settings/usage`. The former static content-script match
therefore never activated. The repaired companion uses no persistent host
permission or static content script: a Human toolbar click supplies temporary
`activeTab` access, the background worker verifies the exact full route, and
only then may `scripting` inject the fixed packaged extractor for one attempt.

## Browser families

- Safari uses a Safari Web Extension embedded in the signed UMA package.
- Google Chrome uses Manifest V3 and an UMA-owned native-messaging host.
- Another Chromium browser is supported only after its exact extension and
  native-host compatibility is independently verified.
- An unsupported or unavailable default browser fails closed and leaves Claude
  hidden or safely Cached/Stale under the accepted snapshot policy.

UMA detects the default HTTPS browser through public macOS APIs. It never
changes the user's default browser.

## Route and extraction boundary

Connect Claude opens the exact current official personal Usage page in the
system default browser. The current allowlist is HTTPS, exact `claude.ai`
origin, exact `/new` pathname, empty query, and exact `#settings/usage`
fragment. Both the background worker and injected extractor validate that
route independently. A changed route fails closed before DOM inspection.

The companion extracts only:

- five-hour used percentage and its reset when present;
- weekly all-model used percentage and its reset when present;
- an optional explicitly labeled model-specific weekly window;
- observation time;
- extractor schema version;
- a fixed safe route/extractor state.

At least one current valid account-level window is required for initial
admission. Missing fields are unavailable, never zero. Percentages must be
finite and within `0...100`. Used percentage is converted to remaining exactly
once by the shared UMA normalization owner. Weekly all-model and model-specific
windows remain distinct.

The extractor does not collect identity, plan price, billing, payment, invoice,
usage-credit balance, chat, project, task history, raw HTML, broad DOM text,
scripts, or URLs containing private query values.

## Native message and local handoff

Only one bounded, versioned normalized message may cross the extension boundary.
Its allowlisted content is source ID, browser family, schema versions,
observation time, fixed safe state, and optional explicitly scoped quota
windows with their matching resets.

Unknown fields, duplicate fields, oversized or malformed frames, invalid UTF-8,
nonfinite or out-of-range percentages, ambiguous used/remaining values,
unscoped model windows, and mismatched resets fail closed.

The Chrome native host accepts only the exact packaged extension identity and
bounded stdin/stdout messages. It has no network client, command execution,
daemon, broad filesystem access, secret-bearing arguments, or credential
facility. Safari accepts messages only from the bundled extension.

After schema validation, both paths use one owner-only handoff directory at
`~/Library/Application Support/CodexUsageMonitor/ClaudeBrowserCompanion`.
The directory is mode `0700`; its live-listener lock and one atomic pending
observation are mode `0600`. The writer must prove that UMA currently owns the
exclusive listener lock before it may replace the pending observation. UMA
consumes and removes the observation immediately. A second listener cannot
replace the active lock or disrupt the first listener. The Safari extension
has no network-client entitlement and has one exact home-relative read/write
exception for this directory only.

## Lifecycle and presentation

- Explicit Browser Sync consent is required.
- Initial admission requires companion availability, exact-route verification,
  a current valid observation, and at least one account-level window.
- Later launches may show only a safely validated Cached/Stale snapshot.
- A restored snapshot never becomes Fresh and cannot establish first-ever
  admission.
- Sync Now may open or focus the Usage page, but every extraction requires one
  explicit toolbar click and is limited to one attempt.
- Background browser launch, focus theft, repeated tabs, fabricated freshness,
  and unproven polling are prohibited.
- Disconnect clears UMA consent, sanitized Claude state, native messaging, and
  UMA-owned host state. It does not sign out Claude or clear browser data.
- Main panel and Desktop Assistant consume one shared sanitized snapshot.

## Live evidence state

The Human-controlled current-default-browser checkpoint passed on Safari. The
exact verified Usage route produced both account-level windows, each matched
the same-time UMA presentation, and missing reset fields remained honestly
unavailable rather than fabricated. No exact live value or identity was
retained. The normalized observation reached one shared source owner and the
main panel and Desktop Assistant showed the same Fresh state in stable
Codex → Claude Code → WorkBuddy order. Codex and WorkBuddy remained
independent.

The preflight app had one UMA process, one Safari extension process, one
listener lock, and no native-host child proliferation. After the explicit
toolbar read, a bounded idle observation showed no automatic cache rewrite or
background provider polling. The live bridge used no Keychain dialog,
embedded browser, credential, cookie, private endpoint, or network-client
entitlement.

Automatic background refresh is not implemented. The Chromium path and signed
production/store extension distribution remain unverified. The current Safari
path is therefore admitted with those explicit risks.
