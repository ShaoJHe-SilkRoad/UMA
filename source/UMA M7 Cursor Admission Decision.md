# UMA M7 Cursor Admission Decision

**Goal:** M7-G1
**Date:** 2026-08-10
**Primary decision:** `CONDITIONAL GO — FALLBACK ARCHITECTURE REQUIRES FOUNDER DECISION`
**Direct local/CLI quota source:** `NO-GO`
**Browser fallback:** `CONDITIONAL GO`
**Only next task:** `Founder provider-controlled browser fallback architecture decision`

## Decision summary

No official documented structured local or CLI source currently proves Cursor
plan quota, unit, stable pool identity, reset/freshness, repeated structure or
no-provider-work behavior. The official `/usage` CLI feature reports activity
streaks and stats rather than plan quota. Structured CLI print output is an
agent execution surface and is not admissible for quota reads.

The official Cursor dashboard is a provider-controlled human-visible Usage
surface. M7-G1 did not access it. A production bridge would require a distinct
browser/account architecture and privacy contract. The active Goal explicitly
classifies that situation as a conditional architecture decision for the
Founder; it does not unlock direct implementation.

## Decision gates

| Gate | Result |
|---|---|
| Official structured local source | FAIL — none proven |
| Official documented CLI plan-quota command | FAIL — `/usage` is activity stats; no quota schema |
| Official quota hook/status source | FAIL — lifecycle/auth only |
| Truthful current primary quota | UNAVAILABLE |
| Native unit and remaining/used semantic | UNAVAILABLE |
| Stable provider-owned pool identity | UNAVAILABLE |
| Repeated structured stability | UNAVAILABLE |
| Provider-owned authentication with opaque credentials | UNPROVEN |
| Strict sanitized projection | UNPROVEN because no schema exists |
| Bounded no-provider-work refresh | UNPROVEN |
| Official provider-controlled human Usage surface | PASS — architecture candidate only |

## Why not GO

`GO` requires a production-usable current quota quantity and all mandatory
identity, semantic, authentication, privacy, stability and lifecycle gates.
None is proven for a direct source.

## Why not SETUP REQUIRED

Cursor and its CLI are absent, but installation cannot repair a missing official
quota contract. `SETUP REQUIRED` is reserved for a proven admissible source with
only a bounded provider-owned prerequisite missing.

## Why not direct NO-GO as the primary plan outcome

The direct source conclusion is `NO-GO`. However, the active M7-G1 Goal also
defines the official provider-controlled dashboard/account surface as a fourth
source tier and requires `CONDITIONAL GO — FALLBACK ARCHITECTURE REQUIRES
FOUNDER DECISION` when that fallback would require custom browser integration
or a new privacy surface. This condition is met.

## Rejected alternatives

- Team Admin API: official but requires an API key, exposes identity/activity
  data and does not prove individual current remaining quota.
- API key, copied token, cookie, Keychain or browser-profile import.
- private endpoint, internal account database/cache or network replay.
- Accessibility, OCR, screenshot or broad DOM extraction.
- manual quota, marketing denominator, task/activity/token/cost estimate.
- provider prompt/task merely to learn quota.

## Operation accounting and privacy

```text
Authenticated quota reads: 0/3
Browser/account actions: 0
Provider prompts/tasks: 0
Intentional quota spend: 0
Credentials/private state accessed: NO
Raw provider payload retained: NO
```

No current value, reset, pool label/ID, account identity or credential was
observed or persisted.

## Product consequence

Cursor stays unsupported and hidden. Production source, registry, scheduler,
Settings, main panel and Desktop Assistant are unchanged. M7-G2 remains locked.
The Founder must first decide whether to authorize a provider-controlled browser
fallback architecture and its separate admission/privacy work.
