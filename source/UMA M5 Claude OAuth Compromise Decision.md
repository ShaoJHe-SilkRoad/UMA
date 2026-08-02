# UMA M5 Claude OAuth Compromise Decision

> **Historical evidence — superseded 2026-08-01.** The Founder rejected this
> compromise before production admission. No OAuth/Keychain broker route is a
> selectable source or fallback. The only active direction is M5-BROWSER-G1.

Date: 2026-07-31
Goal: M5-OAUTH-G1
Status: production implementation in verification; live acceptance pending

## Founder override

The Founder authorizes Claude to remain an UMA provider through one bounded
provider-managed OAuth quota source. This decision supersedes the former
status-line product direction and the rejected embedded account-web route,
without weakening the bans on API-key input, copied tokens, manual quota,
cookie import, embedded login, credential collection, provider tasks, or
account mutation.

The product source is classified as:

- provider: Claude Code;
- source ID: `claude.providerManagedOAuthQuota`;
- source: Existing Claude login;
- support: Experimental;
- authentication: provider-managed OAuth;
- API key: not required;
- value: provider-reported remaining percentage.

The endpoint is undocumented and version-sensitive. It must never be labeled
an official public API.

## Accepted architecture

One main-app connection controller owns consent, connection state, admission,
refresh scheduling, reconnect, disconnect, and immutable sanitized snapshot
publication. Exactly one packaged, parent-owned broker may remain alive only
while the current UMA process is running and Claude remains connected. It is
the only UMA process permitted to touch the provider-owned credential or raw
quota response. It is not a daemon and cannot survive Disconnect, broker
failure, parent-process loss, or UMA termination.

For each read the broker performs one exact read-only request and returns only
a bounded, versioned observation containing allowlisted five-hour and
seven-day quota fields, their own resets, observation time, and fixed safe
result codes. The Founder explicitly authorizes a random per-broker-session
secret and one HMAC-SHA256 digest of the exact access-credential bytes. Both
remain broker-private and memory-only. Only fixed same, changed, or unknown
continuity classifications may cross IPC. The broker returns no credential,
digest, key, header, Keychain metadata, identity, plan, organization, billing
field, unknown provider field, or raw response.

The main panel and Desktop Assistant consume the same shared presentation.
Neither surface owns transport, authentication, scheduling, caching, or quota
normalization.

## Retired routes

- The Claude `statusLine` relay executable target, socket, settings mutation,
  and passive-event product route are retired from production. Historical core
  source remains only so checksum-backed records and tests stay reviewable.
- The WKWebView account-web prototype remains deleted and rejected.
- UMA does not implement its own OAuth client, intercept callbacks, import
  browser sessions, or instruct the Human to use Terminal.

Accepted historical records remain in Git as evidence; they are not selectable
production sources.

## Fail-closed rules

- A current successful read is required before initial admission.
- One valid account-level window is sufficient; a missing window is unavailable,
  never zero.
- Ambiguous `utilization` scaling is rejected rather than guessed.
- Used percentage is converted exactly once to remaining percentage.
- Authentication uncertainty withdraws admission and the visible observation.
- A successful current read establishes the broker-private continuity baseline.
  Same-process Cached/Stale retention is allowed only when the same broker
  remains alive, the exact currently read access credential matches that
  baseline under the ephemeral keyed digest, and the failure is transient and
  non-authentication-related. Changed or unknown continuity, broker restart,
  permission denial, missing or invalid credentials, logout, authentication
  failure, and Disconnect withdraw the last-good value immediately.
- An autonomous timer changes retained data to Stale after five minutes and
  withdraws it after the hard 30-minute current-session ceiling, even without
  a getter or view access.
- Before Keychain access, the child authenticates its live package-owned parent
  PID, exact host/helper paths, owner UID, bundle identifier, strict nested
  bundle and helper signatures, and equality between the live parent's static
  identifier/CDHash and the exact packaged host's static identifier/CDHash.
- Claude quota is not persisted across launch; a current successful read is
  required in every new UMA process.
- An already-existing sanitized historical connector snapshot may remain for
  predecessor recovery bookkeeping, but Claude restore is disabled so it is
  hidden and unusable until a current successful read creates Fresh state.
- Cached or Stale values do not enter Maximum Decrement or quota alerts.
- Disconnect clears UMA consent, sanitized state, timers, cooldown, and
  admission, but never modifies or deletes provider credentials or sessions.

## Delivery decision

PASS requires the complete offline acceptance matrix, a bounded live quota read,
privacy and package audits, one local commit, and one commit-exact package. If
all gates pass except a real naturally available logged-out Google cycle, the
only allowed qualified verdict is:

`PASS WITH RISKS — LIVE QUOTA SOURCE ACCEPTED; ONE REAL LOGGED-OUT GOOGLE LOGIN CYCLE REMAINS UNVERIFIED`

No push, installation over the Desktop app, release, notarization, deployment,
publication, or next Goal is authorized.
