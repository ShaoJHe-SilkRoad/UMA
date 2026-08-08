# UMA M6 Antigravity Admission Decision

**Goal:** M6-G1
**Date:** 2026-08-08
**Decision:** `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`

## Decision

The current device has no trusted installed `agy` executable and no installed
Antigravity application. M6-G1 cannot admit or reject the installed quota
schema because there is no installed source to probe.

The official CLI source class remains viable: current Google documentation
describes a provider-owned CLI, provider-managed authentication, a `/usage`
command with `/quota` alias, and structured read-only print output. Installation
and authentication require a separate Human-authorized setup Goal.

This outcome is `SETUP REQUIRED`, not `GO`, `CONDITIONAL GO`, or `NO-GO`.

## Gate matrix

| Admission gate | Evidence | Result |
|---|---|---|
| Official source class | Current official Google documentation/repository | Viable |
| Trusted installed CLI | PATH, documented path, app, receipt, Spotlight, and LaunchServices checks found none | Missing |
| Installed help / exact argv | No executable | Unavailable |
| Installed version / provenance | No executable | Unavailable |
| Current structured quota read | Not attempted; CLI absent | Unavailable |
| Valid quota bucket | Not observed | Unavailable |
| Explicit remaining semantics | Not observed | Unavailable |
| Reset semantics | Not observed | Optional and unavailable |
| Privacy projection | Contracted and deterministic; no live payload existed | Ready for later proof |
| Provider-managed authentication | Public contract only; current device unobservable | Setup required |
| No turn/task/conversation/spend | Public contract supports source class; live causality untested | Deferred |
| Credits | No read or schema | `CREDITS DEFER` |

## Why this is not NO-GO

The missing component is an official installation/setup condition. Current
public material describes the underlying structured, read-only source class;
M6-G1 found no requirement for an API key, copied token, Keychain read, browser
profile import, manual quota, private endpoint, or provider task.

The source becomes `NO-GO` later if installed behavior requires a prohibited
route, forces interactive login during routine reads, creates provider work or
spend, exposes ambiguous quota semantics, or cannot be safely reduced.

## Why this is not GO or CONDITIONAL GO

Neither decision is permitted without a current successful structured read and
at least one valid quota bucket with explicit semantics. M6-G1 observed none.
Optional-metadata tolerance cannot compensate for a missing executable and
missing primary quota observation.

## Locked consequences

- Antigravity remains unregistered and hidden in UMA.
- No production connector, scheduler, Settings entry, main-panel card, or
  Desktop Assistant presentation is authorized.
- No status line, API-key route, token route, Keychain route, browser source,
  manual quota, or inferred balance is admitted.
- Codex, Claude Code, and WorkBuddy mechanisms remain unchanged.
- M5 frozen and shared runtime paths remain read-only.

## Next task

Exactly one next task is permitted:

```text
M6-SETUP-G1 — official Antigravity CLI setup and provider-controlled login
```

It requires separate Founder authorization. Do not begin M6-G2 until a later
installed-source admission returns `GO` or `CONDITIONAL GO`.
