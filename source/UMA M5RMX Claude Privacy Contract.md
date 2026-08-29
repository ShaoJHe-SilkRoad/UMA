# UMA M5RMX Claude Privacy Contract

**Version:** 1.7

**Date:** 2026-08-29

**Goal:** M5RMX Claude root-repair final closeout

**Status:** mandatory current credential/data boundary; live Test source admitted

## Current live privacy disposition

One authorized Accuracy Sync completed under this contract. Durable evidence
records only stage/status classifications—not exact private percentages,
reset values, page text, DOM/HTML, identity, credentials, cookies, tokens,
history, prompts, responses, sessions, projects, or billing content. The
provider observation crossed the boundary only as the allowlisted two-window
usage packet with optional resets. Reset absence stayed absent.

The exact anchor is owner-only, atomically replaced, read back before
publication, and bounded to five minutes when resetless. Expiry purges it; it
does not become an estimate or calibration record. Proven temporary-tab and
ownership-receipt cleanup completed, with unrelated tabs untouched. Local
Smart remains independent and may truthfully be `STALE-UNSUPPORTED`.

## Current Local Smart Mode boundary

Claude status-line stdin is broad, provider-owned transient input. The relay
may read at most 64 KiB and must immediately project only:

- bounded Claude version;
- five-hour used percentage and reset epoch;
- seven-day used percentage and reset epoch;
- observation time and protocol version.

Raw stdin, session/workspace fields, paths, model objects, cost objects,
identity, prompts, responses, transcripts, tool data, and environment state may
not be written, logged, forwarded, cached, or exposed to the main UMA process.
The sanitized state packet is capped at 4 KiB and stored atomically with owner-
only directory/file permissions.

Local Activity may examine prompt-bearing Claude session files only to
immediately project allowlisted aggregate token count, bounded model-family
classification, activity time, and parser coverage. Raw lines and decoded
prompt/response objects remain transient and must not be retained. Exact-anchor
state may contain only window kind, used percentage, reset, observation time,
sanitized activity counter, source/schema, bounded model family, and continuity
generation.

Claude Desktop estimation has one separate Founder-authorized input:
`~/Library/Application Support/Claude/plan-usage-history.json`. UMA may read
only that exact current-user-owned, owner-only, regular, non-symlink file. The
version-pinned v2 reader bounds the complete file and sample count, projects
only the newest sample's `fh`, `sd`, and timestamp, type-checks then immediately
discards `org`, and rejects every unrelated or unknown field. Provider
utilization is converted once to remaining percentage. The result is always
estimated and visibly marked `≈`; it has no reset. It is never an official API,
never an exact quota observation, and never an input to token-activity
aggregation or anchor calibration.

Presentation may retain only a bounded confidence enum and last-exact timestamp
for transparency. Exact/estimated status is per window; it cannot be inferred
globally from another window and carries no raw local record or quota history.

Accuracy Sync may use Safari's provider-owned session internally, but cookies,
tokens, identity, raw DOM/HTML, chats, projects, billing, and user-tab ownership
must not cross. Safari is one-shot only: no background scheduler, permanent tab,
silent retry, or automatic launch from ordinary local refresh. This section
supersedes any predecessor requirement for persistent Browser Sync.

The earlier installed Safari Host build `202608281805` remains historical
forensic evidence only and is not a release candidate. The current admitted
Test result is the one-shot transaction described above; it does not admit the
`1805` bytes or authorize reuse of any intermediate generation. A final release
must independently prove the exact signed Host/Companion generation, site scope,
packet allowlist, owned-tab cleanup, and absence of private evidence before it
may inherit this privacy disposition.

### Current Safari Host / Companion privacy addendum

#### Owned Provider Tab V2 capability boundary

The previous bootstrap self-navigation ownership model is rejected. The V2
provider tab is created directly and proves itself through an isolated,
top-frame content-script Port. The provider page is untrusted and cannot become
an authority.

The provider URL may temporarily carry exactly one 32-byte cryptographically
random, base64url, no-padding fragment capability. It is one-time, expires
within two minutes, contains no request ID, generation, account, identity,
quota, reset, prompt, session or reusable secret, and is never placed in a
query parameter. The ownership script captures it at `document_start`, removes
it synchronously with same-document `history.replaceState` before starting the
ownership Port, and retains it only inside the isolated content-script world.
After durable ownership acceptance it revalidates that the current location is
the exact canonical Usage route using that same captured nonce. The raw
capability is never logged or durably stored; the receipt stores only its
lowercase SHA-256 digest.

The fragment is never sufficient proof. Ownership additionally requires one
current durable request, matching generation and digest, a current internal
extension Port, top-frame exact-provider sender metadata and the authoritative
integer `sender.tab.id`. UMA accepts no `window.postMessage`, external page
messaging, caller-supplied tab ID, URL-only claim, create-result-only claim or
replacement-event-only claim.

The owner-only App Group receipt is strictly decoded and limited to request ID,
runtime generation, nonce digest, creation/expiry timestamps, reducer state,
revision, and optional candidate/proven provider tab IDs. It contains no URL,
title, history, DOM/HTML/text, quota value, identity, credential, cookie, token
or unrelated tab ID. A candidate ID is never close or extraction authority.
Unknown, ambiguous, stale-generation, replacement-only and otherwise unproven
tabs are never closed. Recovery never uses `tabs.query({})` or scans user tabs.

The admitted Test channel's mutable UMA app, immutable Safari Host and Companion
share only the exact development App Group
`group.com.silkrd.uma.test.bridge`. Effective signed entitlements must prove
this group independently for all three products. A production package must use
its separately declared, package-consistent production group and must not
silently reuse the Test group or Test identities. Either shared group authorizes
only the bounded, owner-only request, response and ownership-receipt locations;
it does not authorize broad filesystem inspection. The Companion must not
receive arbitrary mutable-app container access, enumerate unrelated files, or
treat the group as a logging directory.

Content-free forensic and runtime diagnostics may contain only:

- fixed lifecycle stage and reached/not-reached classification;
- fixed bounded failure reason;
- request ID and runtime/install generation ID;
- exact package/runtime bundle ID, version/build, protocol version and Team ID;
- native-host available yes/no, callback accepted/rejected and timestamp;
- process executable identity, PID and count only where required for task-owned
  lifecycle proof.

They must not contain a Claude URL, page title, DOM/HTML/text, exact quota or
reset value, account identity, organization, chat/project/session content,
cookie, token, password, Keychain value, browser history, unrelated tab ID,
process arguments, environment, or raw native/browser payload.

Owned-tab persistence is a lifecycle proof, not browser history. Its closed
allowlist is request ID, runtime/install generation, lowercase SHA-256 digest
of the one-time fragment nonce, creation/expiry timestamps, monotonic revision,
the minimum state enum, and optional candidate/proved temporary tab IDs.
It contains no provider URL or content. The intent is persisted before
creation, one tab may attach once, cleanup precedes terminal success, and the
receipt is removed immediately after successful cleanup or a cancellation that
proves no tab exists. Bounded expiry stops active cleanup work; it does not turn
an unproven tab ID into ownership proof. An ambiguous creation intent or
unproven tab therefore remains as the single content-free cleanup tombstone and
blocks another tab until the exact tuple re-proves and closes. This deliberately
prefers no tab multiplication and no user-tab closure over automatic recovery.
Across reload, only an already-bound exact tuple may re-prove the tab. An
unknown, reused, wrong-generation or otherwise unproven tab is never closed,
and no general tab enumeration is permitted.

## 1. Normative rule

`Credential existence is not the problem; credential crossing into UMA is the problem.`

Claude and Safari may own and use their own authentication material inside
their provider-controlled boundaries. UMA must not receive, inspect, copy,
retain, log, hash, fingerprint, package, export, or derive identity from that
material.

## 2. Provider-owned state

The following may exist and be used internally by Claude or Safari without
becoming UMA-retained data:

- passwords, passkeys, and verification codes;
- OAuth access or refresh tokens and authorization headers;
- cookies, session state, browser profiles, and browser storage;
- provider-owned Keychain secrets;
- account identity and organization membership;
- chats, projects, prompts, responses, tasks, and source code;
- plan price, billing, payment, invoice, and purchase state.

UMA neither proves nor monitors credential or identity values.
Provider-controlled use does not authorize credential crossing across the
browser/native boundary. The one narrow local-content exception is the Local
Activity sanitizer described above: it may parse one bounded Claude JSONL
record at a time in memory, immediately project only allowlisted usage/token
counts, bounded model-family classification, and activity timestamp, then
discard the raw record and every prompt, response, session/project-content,
and unrelated-metadata field.

## 3. Allowed browser-native packet

Only the versioned `claudeUsageObservation` allowlist may cross:

- fixed message kind, schema version, and source ID;
- fixed browser-family and verified-route enums;
- observation time and extractor schema version;
- optional five-hour used percentage and matching reset;
- optional weekly/all-model used percentage and matching reset;
- optional one explicitly scoped model-family weekly window and matching reset.

The complete encoded message is limited to 4096 bytes. At least one account
window is required. Unknown or duplicate fields fail closed. Diagnostic events
are content-free fixed enums with a UUID request identifier and occurrence
time.

## 4. DOM and route boundary

The retained Safari extension site permission is limited to
`https://claude.ai/new*` and may be exercised only during a Human-requested
one-shot Accuracy Sync. Before any DOM query and again before returning an
observation, the extractor must prove:

- HTTPS;
- exact origin `https://claude.ai`;
- exact pathname `/new`;
- empty query;
- exact fragment `#settings/usage`.

Only after that route gate may the extractor perform the narrow login-form
landmark query. A login landmark fails closed. Absence of those landmarks must
be established before any quota-card selector or bounded leaf-text query.

On that exact route, explicit provider-owned Usage-card selectors are tried
first. If they are absent, the extractor performs bounded in-browser matching
of exact allowlisted leaf-text landmarks across at most 4096 candidate
elements. This fallback may inspect unrelated leaf text transiently in the
browser while rejecting nonmatches; it does not serialize, retain, or forward
that text. Only matched percentage attributes/text and matching
machine-readable reset fields can enter the normalized observation.

The browser layer must not serialize or return raw HTML, broad DOM/page text,
arbitrary URLs, identity, login content, billing sections, chats, projects, or
scripts. Route or layout drift fails closed before any native handoff.

The retained Safari extension uses exact host scope `https://claude.ai/new*`
solely to support explicit one-shot Accuracy Sync. Each request
creates one inactive extension-owned exact Usage tab, binds it to the current
request nonce, extracts at most one sanitized observation, and closes that
exact proven-owned tab before expiring the request. There is no background
scheduler, completion-relative recurring refresh, permanent owned tab, or
long-lived ownership recovery. Site permission does not relax the exact
hash-route gate; unknown routes are rejected before DOM inspection.

## 5. Forbidden UMA mechanisms

M5RMX forbids:

- Keychain or Security.framework Claude credential reads;
- bearer-token handling or credential-continuity digests;
- Cookie API use, browser-profile copying, or storage extraction;
- direct replay of `/api/oauth/usage` or another private endpoint;
- embedded WKWebView login or a custom UMA OAuth client;
- API-key, token, setup-token, or manual quota input;
- network interception, DevTools/private API inspection, OCR, Accessibility
  scraping, or process injection;
- broad process argv or environment capture;
- raw Claude Code status-line stdin crossing beyond the bounded relay sanitizer,
  or being persisted, logged, displayed, packaged, or forwarded to UMA
  business logic; the relay alone may inspect at most 64 KiB transiently before
  immediate allowlist projection;
- raw Claude JSONL records, prompts, responses, session/project content, or
  unrelated metadata being retained, logged, transmitted, displayed,
  committed, or packaged after bounded local parsing;
- any Claude Desktop local path other than the exact authorized
  `plan-usage-history.json`, any raw cache history or organization value, or
  any replay of the cache's underlying private provider request;
- raw page content in diagnostics, evidence, logs, screenshots, Git, or package;
- identity, billing, payment, or continuation inference;
- Claude prompts/tasks or intentional spend to produce monitoring data.

## 6. Native handoff, cache, and diagnostics

The native decoder revalidates the complete exact-key schema before accepting
an observation. Handoff and sanitized cache files use owner-only directories
and files, reject symlinks and unsafe ownership/modes, use atomic replacement,
and are consumed through one current owner. A restored record can be Cached or
Stale only; it cannot establish first admission or new freshness.

For the current immutable-Host architecture, Mutable UMA is not the Safari
containing app and cannot dispatch directly to the extension. It publishes one
sanitized request to the App Group, then uses a notification only as a wake
hint. The immutable Host is the sole Safari dispatch/native-callback authority.
The Companion uses one retained `runtime.connectNative` Port; no active
fallback native transport may compete with it. The Host establishes its
listener before dispatch, admits one in-flight request, validates exact request,
generation and protocol at every boundary, and atomically publishes at most
one terminal response. Duplicate, stale, future-version, post-cancel and late
responses are rejected. Timeout bounds a stalled explicit phase and must not
act as synchronization.

Machine handshake is content-free and does not require Claude consent or site
permission. Consent is required before provider work, and exact-site permission
is required only before the real page read. Local Smart and the app shell are
independent of both. A browser/Host failure must not erase, downgrade or relabel
a valid local estimate; a Local Smart failure must not activate Safari.

Diagnostics may retain only fixed safe classifications and counts. They must
not contain exact Founder percentages or resets, raw URLs, page content,
identity, credential material, or provider-owned process arguments. Durable
live evidence is limited to statements such as window present, reset present,
schema valid, route verified, observation Fresh, or observation repeatable.

### 6.1 Local Smart inputs and Accuracy Sync are separate channels

The production connector retains the compatibility identifier
`claude.browserSync`, but its current owner is Claude Local Smart Mode. It may
consume three independent, locally sanitized inputs:

- exact five-hour/seven-day observations written by the bounded status-line
  relay; and
- aggregate local usage/token count, bounded model-family classification, and
  activity timestamp projected one bounded JSONL record at a time by
  `ClaudeLocalActivityReader`; and
- an estimated-only five-hour/seven-day remaining projection from the newest
  bounded sample in the exact Claude Desktop v2 plan-usage cache.

The reader may access only the local Claude files required for usage accounting
and may retain only those three allowlisted metadata classes. It must never
retain, log, transmit, display, commit, or package a raw JSONL record, prompt,
response, conversation/session body, project content, path, identity, or
unrelated metadata. Local Activity is an input to calibrated estimation only;
it is never official account truth and cannot fabricate an exact quota window.
The Desktop cache estimate is a distinct candidate, never additive with JSONL
activity, never persisted as raw cache/history, and never supplies a reset.

Safari Accuracy Sync is a separate, explicit one-shot account-correction path.
No local-source failure may start Safari automatically, create a recurring
browser schedule, or convert browser extraction into a Local Activity fallback.

## 7. Disconnect and cleanup

Disconnect stops the local status-state monitor, invalidates in-flight
generation, closes only a currently proven one-shot Accuracy tab, clears UMA
consent, sanitized anchors/calibration/cache and temporary handoff state, and
restores the exact preserved prior Claude status-line configuration. It leaves
Claude projects/history and Safari authentication, cookies, history, profiles,
user tabs, and other extensions untouched.

Authentication or permission uncertainty withdraws Safari Accuracy admission
without disabling healthy local inputs. No manual, OAuth, account-web,
credential, or private-endpoint source is activated as a fallback.

## 8. Evidence rule

Fixtures must be synthetic and visibly classified. Tests may prove ranges,
field identities, conversion direction, failure classes, lifecycle, and parity,
but must not contain or preserve current Founder quota values. A live check may
observe only sanitized classifications inside the authorized cap and may never
submit a Claude prompt or task.

Official status-line quota keys are admitted only through the bounded pre-UMA
relay sanitizer. The documented five-hour/seven-day fields share raw stdin with
broader context and appear only after provider activity; they are not a safe
native packet by themselves. The relay must project a closed, versioned packet
before any main-process read, and a timer rerun is not evidence of a fresh
provider observation. Missing exact fields remain missing; qualified local
estimation or stale exact state may be used with explicit provenance, while
one-shot Accuracy Sync remains the only browser correction path.
Owned Provider Tab V2 treats every non-exact route as content-free not-ready state during one bounded readiness window. It performs zero DOM inspection until the exact approved Usage hash is restored and the provider document is ready. A route that does not return, a document that does not become ready, an unsupported structure, a missing site permission, an unavailable session, cancellation or tab closure fails closed with one fixed allowlisted reason; no raw URL crosses the Companion boundary.

After the exact route and document gate, bounded MutationObserver and one render-turn confirmation distinguish partial render from a stable sanitized projection. The content script never publishes on the first partial success. It retains at most one sanitized result in isolated memory, may replay that exact correlated result once after a background reload, and stops after an explicit ACK. The Companion publishes an observation to the Host only after the exact proven provider tab and its owner-only receipt have both been cleaned up. Cleanup failure suppresses the observation and every earlier provider classification.
