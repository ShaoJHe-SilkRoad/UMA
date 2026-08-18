# UMA M5RMX Claude Privacy Contract

**Version:** 1.0

**Date:** 2026-08-17

**Goal:** M5RMX-G1

**Status:** mandatory current credential and data boundary

## 1. Normative rule

`Credential existence is not the problem; credential crossing into UMA is the problem.`

Claude and Safari may own and use their own authentication material inside
their provider-controlled boundaries. UMA must not receive, inspect, copy,
retain, log, hash, fingerprint, package, export, or derive identity from that
material.

## 2. Provider-owned state

The following may exist and be used internally by Claude or Safari without
becoming UMA data:

- passwords, passkeys, and verification codes;
- OAuth access or refresh tokens and authorization headers;
- cookies, session state, browser profiles, and browser storage;
- provider-owned Keychain secrets;
- account identity and organization membership;
- chats, projects, prompts, responses, tasks, and source code;
- plan price, billing, payment, invoice, and purchase state.

UMA neither proves nor monitors those values. Provider-controlled use does not
authorize crossing the browser/native boundary.

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

Persistent Safari site permission is limited to `https://claude.ai/new*`.
Before any DOM query and again before returning an observation, the extractor
must prove:

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

The current Safari runtime uses persistent exact host scope
`https://claude.ai/new*`, `storage`, a persistent background owner, at most one
extension-owned inactive Usage tab, and completion-relative automatic refresh.
It supersedes historical activeTab/toolbar-only designs. Persistent site access
does not relax the exact hash-route gate; unknown routes are rejected before
DOM inspection.

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
- raw Claude Code status-line stdin, which may include sensitive session and
  workspace context before any sanitizer;
- raw page content in diagnostics, evidence, logs, screenshots, Git, or package;
- identity, billing, payment, or continuation inference;
- Claude prompts/tasks or intentional spend to produce monitoring data.

## 6. Native handoff, cache, and diagnostics

The native decoder revalidates the complete exact-key schema before accepting
an observation. Handoff and sanitized cache files use owner-only directories
and files, reject symlinks and unsafe ownership/modes, use atomic replacement,
and are consumed through one current owner. A restored record can be Cached or
Stale only; it cannot establish first admission or new freshness.

Diagnostics may retain only fixed safe classifications and counts. They must
not contain exact Founder percentages or resets, raw URLs, page content,
identity, credential material, or provider-owned process arguments. Durable
live evidence is limited to statements such as window present, reset present,
schema valid, route verified, observation Fresh, or observation repeatable.

## 7. Disconnect and cleanup

Disconnect cancels the Claude scheduler, invalidates in-flight generation,
closes only a proven extension-owned Usage tab, clears UMA consent and
sanitized Claude state, removes UMA-owned handoff/cache state, and leaves
Safari authentication, cookies, history, profiles, and other extensions
untouched.

Authentication or permission uncertainty withdraws Fresh admission. No legacy
status-line, manual, OAuth, account-web, or private-endpoint source is activated
as a fallback.

## 8. Evidence rule

Fixtures must be synthetic and visibly classified. Tests may prove ranges,
field identities, conversion direction, failure classes, lifecycle, and parity,
but must not contain or preserve current Founder quota values. A live check may
observe only sanitized classifications inside the authorized cap and may never
submit a Claude prompt or task.

Official status-line quota keys do not waive this contract. The documented
five-hour/seven-day fields share raw stdin with broader context, appear only
after provider activity, and are not a safe native packet by themselves. A
timer rerun is not evidence of a fresh provider observation. The retired route
must remain inactive unless a future Goal proves a pre-UMA sanitizer, current
trust, no-work freshness, and separately qualified account-mode coverage.
