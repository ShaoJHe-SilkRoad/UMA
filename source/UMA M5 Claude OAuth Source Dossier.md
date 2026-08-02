# UMA M5 Claude OAuth Source Dossier

> **Historical evidence — superseded 2026-08-01.** M5-BROWSER-G1 permanently
> rejects the Claude Keychain/OAuth broker as a product source. This record is
> retained only to explain the rejected investigation and must not be used as
> runtime, fallback, packaging, consent, or implementation authority.

Date: 2026-07-31
Goal: M5-OAUTH-G1
Status: production implementation in verification; live acceptance pending

## Source decision

UMA is implementing one Experimental Claude quota source using an existing
provider-managed Claude login. The source is not a public Anthropic API, local
status line, account-web scraper, manual source, or inferred balance.

Candidate transport:

- method: `GET`;
- origin: `https://api.anthropic.com`;
- path: `/api/oauth/usage`;
- beta header: `oauth-2025-04-20`;
- request body and query: absent;
- redirects and cookies: rejected;
- response cap: 16 KiB;
- request timeout: 15 seconds;
- resource timeout: 20 seconds.

## Evidence weighting

Current Anthropic documentation proves provider-managed Claude authentication
and encrypted macOS Keychain storage, but does not publish a third-party quota
endpoint, Keychain service/account/schema, or UMA login callback contract.

Reference implementations were used as behavioral evidence only:

- TokenBar: primary current OAuth quota behavior and endpoint evidence;
- Claude-Code-Usage-Monitor: defensive schema and 180-second cache behavior;
- agenttop: local observability architecture only;
- ruby_llm-agents: observability patterns only.

No reference code is copied. TokenBar and Claude-Code-Usage-Monitor are MIT;
agenttop is Apache-2.0; ruby_llm-agents is MIT. Any future copied material would
require license and notice review.

## Credential location boundary

Public evidence consistently names the generic-password service
`Claude Code-credentials`. The current macOS provider item is keyed by that
service and the current local user account. After explicit consent, each quota
operation performs exactly one two-stage exact-item lookup. The first query is constrained by both
the fixed service and current-user account and returns only persistent
references; the broker requires exactly one result. The second query uses that
opaque reference with `kSecMatchLimitOne` and returns only the item data. The
raw record is cleared after allowlisted projection and the transient request
buffer is cleared immediately after transport. It
performs no service-only discovery, attribute return, identity output, or
fallback query. The reference is held only in broker memory, cleared with the
credential data, and never exported to the UMA main process. Item-not-found,
duplicate-item, and permission-denied results fail closed.

The credential JSON is accepted only when the minimum allowlisted OAuth object
contains a nonempty, unexpired access credential. The broker does not read,
refresh, write, or delete a refresh token. The main UMA process never receives
the credential or authorization header.

## Decoder decision

Each account-level window remains independent. The broker accepts:

- explicit finite `used_percentage` in `0...100`; or
- finite `utilization`, with zero treated as zero, values strictly between zero
  and one treated as a fraction, and values above one through 100 treated as a
  percentage.

The literal `utilization == 1` is rejected because fraction and percentage
forms have different meanings for the same literal. Both numeric forms in one
window, nonfinite values, missing or malformed reset metadata, negative values,
and values above 100 fail closed. Unknown and private fields are discarded.

Normalized presentation uses:

`remainingPercent = 100 - usedPercent`

exactly once. Optional model windows require explicit provider scope and are
never relabeled as account-wide weekly usage.

## Refresh and failure contract

- minimum interval: 180 seconds after completion;
- one in-flight request across launch, connection, timer, Sync Now, shared
  Refresh, and Reconnect;
- redundant scheduled triggers are dropped;
- at most one manual follow-up is queued and it cannot bypass the 180-second
  completion-relative boundary;
- no timer runs during interactive login;
- provider login continuation occurs only through Human Check Again, Sync Now,
  or shared Refresh and does not require a second consent action;
- manual completion resets the next interval;
- 429 honors bounded `Retry-After` and suppresses bursts;
- 401 invalidates admission and requires reconnect;
- 403 fails closed as unsupported scope or endpoint denial;
- exactly one parent-owned broker remains alive only during the current UMA
  session while Claude is connected;
- a successful current read establishes one broker-private HMAC-SHA256 baseline
  using a random per-session key and the exact access-credential bytes;
- network, TLS, DNS, timeout, bounded 5xx, and 429 failures may retain the
  current-session last-good quota only after the current credential produces
  the same keyed digest;
- changed or unknown continuity, authentication failure, missing or invalid
  credentials, Keychain denial, broker restart, Disconnect, or UMA restart
  withdraws the value immediately;
- neither the key nor digest crosses IPC or persists;
- an autonomous retention timer marks last-good data Stale after five minutes
  and withdraws it after 30 minutes without requiring any view access;
- the credential expiry field is mandatory and is checked again with a fresh
  clock reading after network completion.

The OAuth source does not write Claude quota to disk. A predecessor-era
sanitized connector snapshot may remain in the generic recovery file, but the
Claude descriptor has restore disabled, so the record stays hidden and cannot
admit Claude or seed a new-session Cached/Stale state.

## Live evidence boundary

No exact live percentage, reset timestamp, account identity, plan, credential,
login URL, provider page, or screenshot may enter Git, a package, logs, tests,
or reports. Durable live comparison is limited to MATCH, NOT AVAILABLE, or
MISMATCH per window plus VALID or INVALID reset semantics.

## Current-device trust evidence

- `/Applications/Claude.app` resolves to bundle
  `com.anthropic.claudefordesktop`, version/build `1.24012.9`;
- architecture: universal `arm64` and `x86_64`;
- Developer ID: Anthropic PBC, Team ID `Q6L2SF6YDW`;
- strict deep code signature, Gatekeeper assessment, and stapler validation:
  PASS;
- UMA pins login activation to that exact path, bundle identifier, Team ID,
  nested-code validity, and all-architectures strict validation;
- before Keychain access, the broker requires the live parent code's identifier
  and CDHash to equal the exact packaged host's static identifier and CDHash;
- the packaged broker receives no command-line or environment credential,
  cookie, or browser state; stdin carries only bounded fixed control frames and
  never credential-bearing data.
