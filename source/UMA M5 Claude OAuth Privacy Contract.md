# UMA M5 Claude OAuth Privacy Contract

> **Historical evidence — superseded 2026-08-01.** The privacy design below no
> longer authorizes any Keychain, credential, token, broker, bearer-header, or
> private-endpoint behavior. M5-BROWSER-G1 replaces it with the system-browser
> Browser Sync privacy contract.

Date: 2026-07-31
Goal: M5-OAUTH-G1
Status: mandatory acceptance contract

## Trust boundaries

1. The official Claude application and its provider-owned Keychain item own
   authentication.
2. One packaged, parent-owned, session-lived quota broker is the only UMA
   process permitted to access the credential or raw response. It exists only
   after consent while UMA is running and Claude remains connected.
3. The UMA main process receives only one bounded sanitized observation.
4. The provider endpoint receives one read-only bodyless quota request.
5. Git, package, logs, diagnostics, screenshots, and temporary storage receive
   no credential, identity, raw response, or exact live value.

## Allowed flow

Explicit consent permits UMA to verify and activate the signed official Claude
application, then wait while the provider owns any browser login. Once a usable
provider-owned item exists, each quota operation performs exactly one narrow
one-service/one-item two-stage lookup, requiring exactly one persistent
reference for the fixed service/account selector and then reading only that
exact item's data. The broker holds the opaque reference and access credential
only transiently, clears the raw Keychain record after allowlisted projection,
completes one ephemeral quota request, clears the request buffer immediately
after transport, releases the immutable header projection before suspension,
invalidates the ephemeral URL session on every path, and decodes only
allowlisted fields. The broker may retain
only one cryptographically random
per-session key and one fixed HMAC-SHA256 digest of the exact access-credential
bytes after a successful current read.

The main process may retain only the current process generation's sanitized
last-good observation. It receives only fixed continuity classifications and
may persist neither the digest, its key, a token-derived fingerprint, nor
credential or account metadata.

## Prohibited flow

- API keys, setup tokens, copied OAuth tokens, refresh-token handling, or
  provider credential mutation;
- `security -w`, shell credential access, secret argv/environment/stdin/stdout,
  broad Keychain enumeration, or unrelated item access;
- WKWebView, a custom UMA OAuth client, callback interception, cookie or browser
  profile import, DOM/OCR/Accessibility/UI scraping, or private network replay;
- prompt, response, transcript, project, source-code, account identity,
  organization, billing, invoice, payment, or purchase access;
- shared cookies, cache, URL credentials, redirects, raw body/header logging,
  crash telemetry, or provider error-description persistence;
- a helper daemon, orphan helper, overlapping request, rapid retry, or hidden
  provider task.

## Broker controls

- fixed package-relative executable path;
- nested signature and package provenance verification;
- fixed nonsecret arguments and a minimal fixed environment;
- owner-only anonymous-pipe IPC with bounded command and response frames;
- no general shell interface, arbitrary command, listener, socket, or daemon;
- stderr closed and output bounded to the sanitized schema;
- no core dump, no telemetry SDK, no fatal secret-path diagnostics;
- exactly one exact service/account generic-password reference query per quota
  operation that requires one result, followed by one `kSecMatchLimitOne` data
  query by that opaque persistent reference;
- no returned Keychain attributes or account string;
- no Keychain item API in the main target; main-target Security.framework use
  is limited to strict code-signature validation of the official Claude app and
  packaged broker;
- short timeout, cancellation, parent-death detection, termination, and child
  reap on every path.

## Network controls

The broker uses an ephemeral URL session with no cookie storage, URL cache,
credential storage, background mode, or redirect. It verifies the final exact
HTTPS host, path, default port, empty query/fragment/userinfo, JSON content type,
status, and 16-KiB response cap. It invalidates the session and releases raw
bytes on success, failure, cancellation, and timeout.

## State safety

- Initial admission requires consent, a usable current provider session, a
  successful current read, and at least one valid account-level window.
- Disconnect cancels the scheduler and child, invalidates the generation,
  clears consent and sanitized state, and withdraws admission.
- Disconnect does not call Keychain update/delete and does not sign out Claude
  or any browser.
- Late broker results after disconnect, credential change, or reconnect are
  ignored.
- Authentication failure immediately withdraws prior-account values.
- Persisted cross-launch Claude quota is not displayed before a successful
  current-session read.
- The OAuth source writes no new Claude quota snapshot. A sanitized historical
  snapshot already present for predecessor recovery bookkeeping may remain on
  disk, but `supportsRestore == false` keeps it hidden and unusable; it can
  neither admit Claude nor seed Cached/Stale in a new process.
- A successful current read establishes or replaces the broker-private keyed
  continuity baseline. Same-session Cached/Stale retention is permitted only
  for a transient non-authentication failure after the currently read exact
  credential matches that baseline. Changed or unknown continuity, broker
  restart, Keychain denial, missing or invalid credentials, authentication
  failure, Disconnect, and UMA restart immediately withdraw the last-good
  value. An autonomous connector-owned retention timer changes Fresh/Cached to
  Stale after five minutes and withdraws the provider after the hard 30-minute
  same-session ceiling even when no view or getter is accessed. The key and
  digest never persist across launches.

Before constructing the broker session or reading Keychain, the child verifies
its live parent PID, the exact package-relative host and helper paths, current
owner UID, bundle identifier, strict nested bundle signature, strict helper
signature, and equality between the live parent's static code identity and the
exact package host's static identifier plus CDHash. Direct shell/test-runner
execution, copied helpers, symlinked paths, modified packages, and foreign
parents fail closed before credential access.

## Package and evidence controls

The main executable must contain no Keychain query, token parser, endpoint, or
authorization-header implementation. The helper may contain only the exact
protocol constants required for its bounded job. Neither executable may contain
real credentials or fixtures. The package contains no runtime record, raw
response, cookie, cache, log, database, screenshot, settings backup, governing
record, or test evidence.

Diagnostics are fixed enums and counters only. Live durable evidence contains
no exact percentage, reset, identity, plan, URL, token metadata, or screenshot.
