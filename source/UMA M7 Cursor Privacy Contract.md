# UMA M7 Cursor Privacy Contract

**Goal:** M7-G1C
**Date:** 2026-08-11
**Decision:** `NO-GO — CURSOR PRODUCTION SUPPORT REMAINS LOCKED`
**Only next task:** Founder source-direction decision

M7-G1C is a public-evidence source adjudication. It does not reopen provider
authentication, Safari, page extraction, or product implementation. M7-G2
remains locked.

```text
CURSOR BROWSER SOURCE ARCHITECTURE VIABLE
FREE PLAN SEMANTICS RESOLVED
FREE PLAN ENFORCEMENT RELIABILITY NOT ADMITTED
PAID PLAN CONTRACT NOT LIVE QUALIFIED
CURSOR PRODUCTION SUPPORT REMAINS LOCKED
```

## Permanent privacy boundary

Never access or retain:

- password, API key, OAuth/access/refresh token, setup token, authorization
  header, cookie, browser profile/session, Keychain secret, or authentication
  database;
- account identity, email, organization, billing/payment, or team-member data;
- prompt, response, chat, project, repository, source code, or task content;
- raw stdout/stderr, JSON, HTML, broad DOM, private URL, or complete provider
  payload;
- exact live quota/reset values or private provider identifiers in durable
  evidence;
- Cursor private database, cache, preferences, logs, or internal endpoint data.

API key, copied token, cookie, Keychain, private endpoint, browser-profile
import, manual quota, and inferred quota remain rejected.

## Safe browser architecture contract

The rejected isolated probe had App Sandbox enabled, outbound network-client
entitlement only, and a dedicated persistent
`WKWebsiteDataStore(forIdentifier:)`. It does not share Safari, Chrome, Cursor,
or the default WebKit store. Cookies and storage remain opaque. Before exact
authenticated-route validation it must not call `evaluateJavaScript`, register
script handlers, inspect login-page DOM, or read cookie/storage APIs.

The separate Safari fallback proved the viable architecture:

- provider-controlled browser authentication;
- exact Cursor dashboard-site permission;
- exact recognized-route validation before semantic inspection;
- bounded allowlisted projection only;
- repeated sanitized observations;
- no raw DOM, HTML, URL, identity, billing, credential, cookie, or session data
  crossing the native boundary;
- no login-page or Google-page injection;
- fail-closed unknown layouts;
- complete teardown and Safari security restoration.

The content projection may contain only route, availability, account-mode,
bounded pool label, semantic direction, normalized percentage/ratio, reset
presence, on-demand separation, observation ordinal, and private-field count.

Current public provider evidence resolves the Free-plan percentage as
`usedPercent`. The only permitted normalization is:

```text
remainingPercent = 100 - usedPercent
```

This semantic correction comes from public Cursor-owned material, not a new
page read. It creates no new privacy surface. A displayed remaining amount must
remain classified as dashboard observation, never as a guaranteed enforcement
signal.

## Contained incidents

One Human-supplied screenshot unexpectedly exposed account-identity metadata
in transient context. Two filtered Safari accessibility reads also exposed an
exact-quota data class in transient tool output. None of that material was
reproduced, interpreted further, copied, hashed, persisted, committed,
packaged, logged, or retained.

```text
Unexpected Human-supplied identity exposures: 1 transient
Unexpected exact-quota accessibility exposures: 2 transient
Retained incident identity/screenshot/log/payload copies: 0
Retained exact-quota/DOM/URL copies: 0
```

The repeatable cause was removed: dashboard accessibility reads are prohibited.
Subsequent UI work used settings-window-only UI evidence and the sanitized v2
receipt, with no page-state read after final repair. Broad process argv,
environment, page accessibility trees, screenshots, DOM, and private network
inspection remain forbidden.

## Restored security state

Final cleanup disabled and unregistered both task-owned extensions, verified
Safari unsigned-extension mode `Off`, removed the exact task-owned probe roots
and containers, stopped task-owned processes, and left Safari login data and
unrelated browser state untouched. No task-owned probe process or extension
registration remains.

M7-G1C did not change that state:

```text
M7-G1C provider reads/browser logins/prompts/tasks/spend: 0/0/0/0/0
```

Here, `provider reads` means authenticated quota/dashboard reads from the
Human's session. Public Cursor source-document retrieval is not an
authenticated provider read and accessed no account or session data.

## Decision consequence

Browser architecture viability and display semantics are now accepted as
separate facts. Free-plan enforcement reliability is not admitted, and the
paid-plan contract is documented but not live qualified. The final result is
`NO-GO — CURSOR PRODUCTION SUPPORT REMAINS LOCKED`.

Cursor remains unsupported and hidden. M7-G2 remains locked. The only next task
is a Founder source-direction decision.
