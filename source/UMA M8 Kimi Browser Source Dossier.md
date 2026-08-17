# UMA M8 Kimi Browser Source Dossier

Goal: M8-WEB-G1
Date: 2026-08-12
Status: `NO-GO`
Production runtime: unchanged
Closeout: 2026-08-17
Exactly one next task: `Founder Kimi source-direction / M8 closeout decision`

## Executive finding

The WorkBuddy-style provider-controlled account-web security model is viable
for Kimi, but the current authenticated Kimi Membership surface did not expose
an admissible Shared Membership contract through bounded semantic extraction.
The exact official route was reachable in the normal Safari session, the
temporary companion remained exact-site and classification-only, and repeated
valid receipts failed closed as `UNSUPPORTED_LAYOUT`. No exact quota value,
identity, credential, raw DOM, HTML, URL, cookie, token, or browser state crossed
the browser boundary.

The isolated Kimi web session is separately classified:

`ISOLATED KIMI WEB SESSION: NOT SUITABLE FOR ADMISSION / HUMAN AUTH UX`

It failed to preserve the Human's provider-controlled authentication twice and
did not support the normal Safari and Apple Passwords workflow. It was not
retried. The selected admission architecture was therefore a task-owned Safari
Browser Companion using the provider-owned Safari session.

## Final channel decisions

```text
NO-GO
SHARED MEMBERSHIP: NO-GO
KIMI CODE LIMITS: MISSING
EXTRA USAGE: ABSENT
```

Shared Membership is mandatory. Browser transport feasibility cannot substitute
for a stable explicit pool identity, quantity semantic, and provider cycle. The
current exact membership route produced no safely recognized Shared Membership
channel, so M8-G2 remains locked.

## Repository and scope baseline

| Field | Result |
|---|---|
| Workspace | `$HOME/Developer/UMA-M8-Kimi` |
| Branch | `codex/uma-m8-kimi` |
| Starting HEAD | `ba9f944f8e8abb1e68785c7c812585ff4eb8171e` |
| Starting tree | `3b8dd1ea3438c5834695d08223e78c6257273272` |
| Starting worktree / index | clean / empty |
| Accepted deterministic predecessor | 668 / 668 PASS |
| Production Kimi browser source | absent |
| Production provider registration | absent |
| Production source changes in this Goal | NO |

## WorkBuddy-pattern reuse map

| Accepted architectural piece | Kimi classification | Finding |
|---|---|---|
| Provider controls the login UI and UMA never receives credentials | `REUSABLE AS-IS` | Kimi preserved this boundary in normal Safari. Session storage ownership itself is not reused. |
| Exact official origin and route gate | `REUSABLE WITH KIMI ADAPTER` | Kimi requires its own recognized membership and Code route families. |
| Browser-layer sanitization before native handoff | `REUSABLE AS-IS` | Only fixed semantic classifications crossed the native boundary. |
| Current-read admission and fail-closed withdrawal | `REUSABLE WITH KIMI ADAPTER` | Unknown layout, missing Shared Membership, malformed values, and auth uncertainty must reject publication. |
| Fresh / Cached / Stale / login-required model | `REUSABLE WITH KIMI ADAPTER` | Applicable only after a current successful Kimi read exists. |
| One source-owned refresh coordinator and coalescing | `REUSABLE WITH KIMI ADAPTER` | Feasible in principle, not admitted from this failed source contract. |
| Disconnect leaves external browser login intact | `REUSABLE AS-IS` | A future Kimi disconnect would clear only UMA-owned state and companion permission. |
| UMA-owned isolated WorkBuddy `WKWebView` and dedicated `WKWebsiteDataStore` | `WORKBUDDY-SPECIFIC` | This owns WorkBuddy website state inside UMA; Kimi isolated authentication was unusable, so normal Safari fallback was selected instead. |
| WorkBuddy Credit pool parser and canonical Decimal schema | `WORKBUDDY-SPECIFIC` | Kimi uses membership percentages, Code windows, and native-money Extra Usage semantics. |
| WorkBuddy one-minute cadence | `NOT SUITABLE FOR KIMI` | No Kimi cadence is admitted until a source succeeds and provider behavior is measured. |

No WorkBuddy production file, browser state, parser, cadence, credential,
session, or Credit semantic was changed. A future M8 implementation should
reuse the security and lifecycle boundaries, not WorkBuddy's provider-specific
data model.

## Selected browser architecture

```text
normal Safari
-> Kimi-owned authenticated session
-> task-owned exact-site Safari companion
-> exact route validation before DOM inspection
-> bounded semantic extraction
-> browser-layer sanitization
-> classification-only native receipt
```

The temporary companion was a real embedded Safari Web Extension. Its manifest
requested exactly `activeTab`, `nativeMessaging`, and `scripting`; it declared
no host permissions, static content scripts, cookies, storage, history,
`webRequest`, or broad URL access. Human toolbar activation supplied current-site
access only. The route gate admitted only:

- `https://www.kimi.com/membership/subscription?tab=quota`
- `https://www.kimi.com/code/console`

Lookalike origins, HTTP, different query/hash state, login routes, billing tabs,
and unknown paths were rejected before semantic DOM inspection.

## Authenticated observation result

| Evidence | Classification |
|---|---|
| Provider-controlled Safari authentication | PASS; credentials remained opaque |
| Official membership route available | YES |
| Valid sanitized membership receipts | 4 |
| One earlier page extraction rejected only by timestamp validator | contained; no payload retained |
| Authenticated page observations used | 5 / 8 |
| Stable route class | `MEMBERSHIP_QUOTA` |
| Stable source result | `UNSUPPORTED_LAYOUT` |
| Shared Membership identity | unavailable |
| Used / remaining semantic | unavailable |
| Same-scope quantity or denominator | unavailable |
| Reset/cycle | unavailable |
| Extra Usage marker on this exact surface | absent |
| Kimi Code route observation | not performed |
| Automatic native reread | not independently qualified |
| Provider prompts / Agent turns / tasks | 0 / 0 / 0 |
| Intentional spend / account changes | 0 / 0 |

The valid observations repeated the same safe failure classification. Repetition
therefore proves stable fail-closed behavior, not a quota schema. The browser
layer never exported the percentage or any exact balance. Numeric direction was
not inferred from color, value, progress-bar direction, DOM order, or historic
documentation.

## Channel adjudication

### Shared Membership: NO-GO

The recognized official membership route was current and authenticated, but the
bounded extractor could not identify one explicit Shared Membership channel with
an explicit quantity semantic and reset/cycle. Broader page text, raw DOM, OCR,
or account-specific selectors were not used to force a result. Missing is not
zero, and the mandatory pool cannot be manufactured from documentation.

### Kimi Code Limits: MISSING

The Code Console route was not consumed after the mandatory Shared Membership
gate failed. No five-hour or weekly/provider-cycle channel is live-qualified.
Public CLI/documentation evidence remains historical contract context only and
cannot replace an authenticated browser observation.

### Extra Usage: ABSENT

All retained receipts classified Extra Usage as absent on the recognized
Membership route. This is a surface-presence classification only; it does not
claim zero balance, disabled state, or universal account-mode absence. Because
Shared Membership itself is unadmitted, no continuation claim is made.

### Account mode

`unknown / unsupported layout`. Authentication presence was confirmed without
retaining identity or plan data. No Free, membership, Code, business, or
enterprise limits are inferred from another account mode.

## Normalization and identity rules

If a future source is separately admitted:

- explicit remaining: retain directly;
- explicit used percentage: `remainingPercent = 100 - usedPercent` once;
- same-pool used plus total: `remaining = total - used`, with percent derived
  only from that same observation and cycle;
- native-money Extra Usage: never convert to percentage;
- missing: unavailable, never zero;
- unlimited: semantic unlimited, never 100 percent.

Stable identity must come from provider semantic labels or bounded provider IDs,
not array order, current value, reset time, CSS position, or plan marketing copy.
Unknown future layouts fail closed.

## Automatic-refresh feasibility

The companion demonstrated exact-site activation and native sanitized handoff.
One source-owned coordinator, one in-flight extraction, bounded route reload,
manual/scheduled coalescing, safe auth-expiry withdrawal, and provider-specific
failure isolation are architecturally feasible. Automatic production reread is
not admitted because no successful source contract exists and the native
programmatic reread path was not independently qualified. No cadence is
recommended until a future source passes live semantic admission.

## Failure model

The proposed adapter must fail closed for: not authenticated, expired session,
official page unavailable, unsupported account mode, unsupported layout,
missing Shared Membership, missing required Code limit, malformed or ambiguous
value, unavailable reset, ambiguous Extra Usage, provider unavailable, duplicate
identity, and extraction-contract mismatch. One Kimi failure must not affect
WorkBuddy or another provider. Cached data cannot be presented as current, and
stale data cannot become a new decrement sample.

## Privacy incident and containment

One broad read-only Safari accessibility inspection during setup transiently
exposed unrelated non-Kimi accessibility metadata. It did not expose Kimi quota,
identity, credentials, cookies, tokens, or account data. Nothing from that
transient output was copied, retained, committed, packaged, screenshotted, or
placed in task evidence. Broad Safari accessibility inspection was retired;
subsequent evidence used only exact task-owned files, bundle identifiers, PIDs,
process counts, and classification-only receipts.

No raw provider payload belongs in Git. No exact Founder quota value or wallet
balance was retained.

## Decision

```text
NO-GO
SHARED MEMBERSHIP: NO-GO
KIMI CODE LIMITS: MISSING
EXTRA USAGE: ABSENT
```

Browser-source architecture viability is preserved as research evidence, but it
does not unlock production. Exactly one next task is
`Founder Kimi source-direction / M8 closeout decision`.

`M8-G2 remains locked.`

## Local delivery closeout

Safari `Allow unsigned extensions` was visibly verified Off. The temporary
companion registration, task-owned processes, M8-WEB-G1 `/private/tmp` roots,
the exact metadata-only app container, and its isolated Trash item are absent.
Safari data and the provider-owned Kimi login were not cleared. Cleanup used
zero Kimi provider operations. Claude-related changes: NONE.
