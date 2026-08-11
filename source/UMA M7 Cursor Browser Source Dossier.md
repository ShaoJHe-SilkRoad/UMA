# UMA M7 Cursor Browser Source Dossier

**Goal:** M7-G1B
**Date:** 2026-08-10
**Status:** `NO-GO — FREE-ACCOUNT PERCENTAGE SEMANTIC IS AMBIGUOUS`
**Production runtime:** unchanged

## Purpose

M7-G1 established that Cursor has no admitted official local or CLI quota
source. This dossier evaluates the only remaining Founder-authorized source
class:

```text
official Cursor dashboard
→ provider-controlled authentication
→ bounded browser extraction
→ sanitized quota observation
```

The study does not implement the Cursor provider. M7-G2 remains locked until
this record and the matching admission decision reach one final
`GO`, `CONDITIONAL GO`, `SETUP REQUIRED`, or `NO-GO` verdict.

## Current official contract

Current Cursor-owned documentation establishes:

- Pro, Pro Plus, and Ultra have two independent monthly usage pools:
  `Cursor Models` and `Other Models`.
- `Cursor Models` covers Cursor Grok 4.5 and Composer 2.5.
- `Other Models` covers selected third-party models at their API price.
- Both pools reset with the monthly billing cycle and appear in the Cursor
  editor and usage dashboard.
- The Start plan is a documented exception: it has the Cursor Models pool but
  not the Other Models pool or on-demand usage.
- On-demand use is separate from included plan quota and must not be merged
  into either included pool.

Official sources:

- <https://cursor.com/docs/models-and-pricing>
- <https://cursor.com/help/models-and-usage/usage-limits>
- <https://cursor.com/help/account-and-billing/billing>
- <https://cursor.com/help/account-and-billing/overages>
- <https://cursor.com/terms/pricing>
- <https://cursor.com/blog/teams-pricing-june-2026>

Current Cursor-owned documentation is not consistent on one mandatory route:
the Help article points to the Spending tab, while Models & Pricing links the
usage dashboard at `https://cursor.com/dashboard/usage`. The live study
therefore evaluated `/dashboard`, `/dashboard/usage`, and
`/dashboard/spending` as one official dashboard family. Route alone is not an
admission identity.

The documentation explicitly describes remaining allowance and monthly reset
for its documented two-pool paid-plan surface. It does not define whether the
single percentage labelled `Free Plan usage` on the live Free-account surface
means used or remaining. The paid-plan statement is not applied to that
different one-pool account mode.

## Architecture order

### A. UMA-owned isolated session — rejected

The first test architecture is a task-owned app at:

```text
/private/tmp/uma-m7-g1b-isolated-probe-2cf4b23/UMA-Cursor-Probe.app
```

Verified before launch:

- bundle ID `com.silkrd.uma.m7.cursor-probe`;
- arm64 executable;
- strict deep ad-hoc signature;
- App Sandbox enabled;
- outbound network-client entitlement only;
- one visible `WKWebView`;
- a dedicated persistent `WKWebsiteDataStore(forIdentifier:)`, not the
  default/shared browser store;
- HTTPS-only navigation;
- Cursor-owned hosts allowed and every other provider sign-in host requires a
  visible Human `Allow Once` decision;
- no JavaScript evaluation, script message handler, cookie API, storage API,
  Keychain API, file access, download handler, Accessibility, Screen
  Recording, Apple Events, network server, or broad process inspection.

The probe performed authentication compatibility only. The Human completed one
provider-controlled sign-in attempt, but the embedded authentication flow
reported a provider-side compatibility failure. A normal reopen and one bounded
reload returned to provider-controlled login rather than the exact Spending
route. No login-page DOM or page content was inspected by the probe. The
isolated architecture is therefore rejected; no bypass or repeat login attempt
is allowed.

### B. Safari Browser Companion — evaluated, not admitted

Cursor's authentication provider rejected the isolated WebKit path, so the
authorized Safari fallback is active. It uses only M7-owned temporary
components and does not modify the frozen Claude BrowserExtension. It must
independently prove registration, exact-route validation, bounded extraction,
sanitized native handoff, repeatability, and cleanup.

The temporary arm64 containing app embeds a real Safari Web Extension under
`Contents/PlugIns`. Its second, repaired probe identity is
**UMA Cursor Browser Companion v2**. Its manifest grants only
`nativeMessaging` and these recognized official routes:

- `https://cursor.com/dashboard`
- `https://cursor.com/dashboard/usage*`
- `https://cursor.com/dashboard/spending*`

The content script independently rejects query/hash variants and every path
outside the three exact route classes before inspecting any page landmark.
There is no broad host, cookie, storage, Keychain, network-interception, login
page, or static Google-page permission. Strict nested ad-hoc signature
verification passes. LaunchServices and `pluginkit` recognize the exact v2
identifier. Safari listed v2, the Human enabled it, and Safari granted
website access only on `cursor.com`; the older task-owned companion remained disabled.

The authenticated Safari session survived restart. The v2 companion emitted
only schema-2 classifications through a native-message allowlist. Eight
successful sanitized observations covered every recognized route twice,
including the post-restart and exact-site-permission path. Every observation
reported `privateFieldCount: 0`; no raw DOM, HTML, URL, exact quota, reset
value, identity, billing detail, cookie, token, or session value crossed the
native handoff.

The same one-pool identity, `Free Plan usage`, was stable on all observations.
The native unit was a percentage. No bounded visible text, accessibility
semantic, provider-owned test identity, or current official Free-plan contract
classified that percentage as used or remaining. No same-pool denominator was
available. Reset evidence was also unavailable for that one-pool observation.
The Usage route separated an on-demand section; the other two route
classifications did not establish that separation. The Spending route remained
Human-visible as loading, while the v2 probe could still see the shared
Free-plan label; therefore that route is not treated as a completed usage
surface.

## Live admission fields

The authenticated phase must establish, without durable Founder values:

| Field | Current state |
|---|---|
| Isolated authentication compatibility | Rejected — provider-controlled embedded-auth incompatibility |
| Persistent-session reopen | Failed closed — returned to provider login |
| Authenticated official dashboard family | PASS — provider-controlled Safari session survived restart |
| `/dashboard` | Available; one bounded Free-account pool classification |
| `/dashboard/usage` | Available; one bounded Free-account pool classification; on-demand section separate |
| `/dashboard/spending` | Human-visible loading; shared pool label alone does not prove route readiness |
| Live plan/pool count | One Free-account pool; no paid-plan pools manufactured |
| Provider-owned stable pool label | PASS — `Free Plan usage` stable across repeated observations |
| Native unit | PASS — percentage |
| Used-versus-remaining semantic | FAIL — explicit semantic unavailable |
| Complete same-pool denominator, if required | Unavailable |
| Reset date/time and scope | Unavailable for the observed Free-account pool |
| On-demand separation | Present on Usage route only; not merged into the pool |
| Repeated structural identity | PASS — two observations per tested surface |
| Currentness | Structurally repeatable; no quota-consuming delta manufactured |
| Bounded automatic refresh feasibility | PASS structurally — automatic post-navigation observations required no toolbar click |
| Authentication-expiry fail-closed behavior | Contracted — unauthenticated/ambiguous observations do not publish quota |

Exact values may exist transiently in the isolated process solely for
same-time validation. They must not enter Git, files, logs, screenshots,
clipboard, durable evidence, or the final report.

## Operation accounting

```text
Task-owned isolated probe launches: 3
Provider-controlled login session opened: 1
Human login completions: 1
Authenticated dashboard route navigations: 4
Successful sanitized observations: 8
Safari fallback containing-app launches: 3
Credential/cookie/private-state reads: 0
Unexpected Human-supplied identity exposures: 1 transient
Unexpected exact-quota accessibility exposures: 2 transient
Retained incident identity/screenshot/log/payload copies: 0
Retained exact-quota/DOM/URL copies: 0
Provider prompts/tasks: 0
Intentional quota spend: 0
Automatic retries: 0
```

## Final browser cleanup

- The legacy and v2 task-owned companions were disabled and both exact
  extension identifiers were unregistered.
- Safari `Allow unsigned extensions` was verified `Off` before Safari quit.
- The two exact `/private/tmp` probe roots are absent.
- The three exact task-owned app-container records were removed without
  opening or retaining their contents. No Safari profile, history, cookie,
  provider login, or unrelated browser data was cleared.
- No task-owned probe process or extension registration remains.

## Current conclusion

The Safari fallback proved provider-controlled authentication, narrow website
permission, sanitized-before-native extraction, stable one-pool identity,
percentage unit, repeated observation, and automatic read feasibility. It did
not prove the mandatory numeric direction for the Free-account percentage.
Interpreting the number would require guessing from its value, visual direction,
or paid-plan documentation, all of which the Founder prohibited.

**Final browser-source decision: `NO-GO`.** No production architecture is
admitted. Cursor remains unsupported and hidden. M7-G2 remains locked; the only
next task is a Founder source-direction decision.
