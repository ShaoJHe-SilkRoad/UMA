# M1A-G2_DBG-B Codex Capability and Freshness Decision

## Decision

Use the installed Codex app-server's documented local JSON-RPC service as the
authoritative account source. Keep one owned `app-server --stdio` child and one
session receive loop. Prefer the documented account invalidations when they are
delivered; retain bounded adaptive polling as a health and freshness fallback.
No notification payload, raw account response, identity, credential, browser
state, or prompt content enters the monitor model or persistence.

## Evidence and capability classification

| Capability | Evidence | Decision | Claim state |
| --- | --- | --- | --- |
| `account/read` | Installed `codex-cli 0.145.0-alpha.18` stable/experimental schema bundle and successful temporary-package Connect/Allow outcome | Required account-presence gate before usage reads | Live outcome proven; raw response deliberately not retained |
| `account/rateLimits/read` | Same schema bundle and sanitized candidate panel | Required authoritative limit source | Live sanitized presentation proven: unlimited five-hour plus one 69% seven-day window |
| `account/usage/read` | Same schema bundle and sanitized candidate panel | Required aggregate usage source | Live sanitized aggregate presentation proven; no identity or raw payload retained |
| `account/updated` | Stable and experimental schema notification | Typed invalidation to one `.providerEvent` refresh lane | Fixture-proven; live notification delivery unproven |
| `account/rateLimits/updated` | Stable and experimental schema notification | Typed invalidation to one `.providerEvent` refresh lane | Fixture-proven; live notification delivery unproven |
| Local session metadata | Existing allowlisted metadata reader | Event-driven local-only aggregate update; never a provider refresh | Deterministically proven |

The installed binary metadata and schema hashes are preserved only in the
sanitized Task-B shared evidence packet under `.build/`; they are not release
artifacts.

## Freshness policy

- One client refresh coordinator serializes timer, provider-event, reconnect,
  wake, and manual account reads. Concurrent callers join its result.
- A visible panel requests a fallback freshness check every 120 seconds.
- A hidden panel keeps a conservative 15-minute fallback instead of stopping
  freshness entirely. Closing the panel never creates a new child.
- The app-server event stream is preferred when available. It is buffered to
  newest-one and yields no payload beyond the event kind.
- Provider overload affects only the next explicit request with bounded
  30, 60, 120, 240, then 300 second delay. There is no autonomous retry storm.
- A provider failure preserves prior verified values as stale and exposes the
  existing explicit stale/refresh state rather than representing old values as
  live.
- Local file notifications debounce for 200 ms, update only the allowlisted
  local aggregate, and never invoke account/rate-limit/usage RPC.

## Limitations

The direct sandbox probe's earlier authorization mismatch remains a separate
probe limitation, but it no longer governs the accepted temporary-package UI
outcome. Notification delivery latency, event-stream timing, and raw method
payloads remain unproven because Task B intentionally retains neither protocol
payloads nor credentials. The direct Human-authorized Light/Dark, Reduce
Transparency, and Increase Contrast matrix passed on fresh candidates; the
original global values were restored exactly afterward. No browser, account
mutation, credential, or identity access was used.
