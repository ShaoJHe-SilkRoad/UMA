# UMA M6 Antigravity Admission Decision

**Goal:** M6-G1R
**Date:** 2026-08-08
**Decision:** `NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE`

## Decision

The installed official Antigravity CLI `1.1.11` produced one current structured
quota document through the exact read-only `/usage` print command. The observed
contract contains explicit `remaining_fraction` values and per-bucket ISO-8601
`reset_time` values under `command.data.groups[].buckets[]`. Provider-owned
authentication succeeded without browser login or credential access, and the
payload can be reduced through a narrow privacy allowlist.

M6-G1R nevertheless returns **`NO-GO`**. The live-read budget ended without the
mandatory proof of repeated detailed structural stability, deterministic
bucket identity stability across the multiple independent quota groups, or an
exact live zero-turn counter. These are core admission gates, not optional
metadata eligible for `CONDITIONAL GO`.

This result does not prove that the official source is unsafe or unusable. It
means the evidence authorized for this Goal is insufficient to admit the source
into production honestly.

## Historical decisions

- M6-G1: `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`
- M6-SETUP-G1: `PASS — OFFICIAL ANTIGRAVITY CLI READY FOR SOURCE RECHECK`
- M6-G1R: `NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE`

## Current gate matrix

| Admission gate | Current evidence | Result |
|---|---|---|
| Official installed source | Manifest-pinned `$HOME/.local/bin/agy` `1.1.11`, exact executable hash unchanged | PASS with previously accepted local trust-service limitation |
| Installed help / exact argv | Print mode, JSON output and slash expansion confirmed | PASS |
| Current structured quota | One successful ordinary-network JSON object | PASS |
| Quota container | `command.data.groups[].buckets[]` | PASS |
| Valid quota bucket | Two groups observed, one valid bucket in each | PASS for one observation |
| Remaining semantics | Explicit `remaining_fraction`, finite and in `0...1` | PASS |
| Normalization | `remainingPercent = remaining_fraction × 100` exactly once | PASS |
| Reset semantics | Per-bucket ISO-8601 `reset_time`; no relative duration observed | PASS |
| Privacy projection | Narrow allowlist feasible; private/unused envelope fields rejectable | PASS |
| Provider-managed authentication | Current read succeeded without browser/login or credential access | PASS |
| Bounded lifecycle | Closed stdin, empty owner-only cwd, byte caps, timeout, owned child teardown | PASS |
| Repeated detailed structure | Only one detailed successful ordinary-network sample | **FAIL / unproven** |
| Stable bucket identity | ID/name/window fields exist, but exact safe identities were not retained across reads | **FAIL / unproven** |
| Exact live no-turn evidence | Empty `conversation_id`; exact `num_turns == 0` was not retained | **FAIL / unproven** |
| No attributable spend | Official read-only contract plus no observable provider work; exact zero is not measurable | Supported with measurement limitation |
| Credits | No read and no admitted schema | `CREDITS DEFER` |

## Live-read accounting

| Operation | Authorized | Consumed |
|---|---:|---:|
| M6-G1R `/usage` or `/quota` executions | 3 | 3 |
| Automatic retries | 0 | 0 |
| `/credits` executions | 0 | 0 |
| Provider prompts/tasks | 0 | 0 |
| Intentional provider work/spend | 0 | 0 |

The first two executions occurred in a network-restricted tool sandbox and
returned no JSON. Their generic stderr was not retained. The third execution
used the approved ordinary network context and returned one structured JSON
object. The environmental distinction explains why the first two failures are
not treated as provider schema instability, but they cannot substitute for a
second successful detailed sample.

## Why this is not CONDITIONAL GO

`CONDITIONAL GO` is reserved for optional missing detail after primary quota,
identity, lifecycle, and ordinary-read stability are proven. Missing reset,
safe display labels, or Credits could be conditional risks. In contrast:

- stable identity is required to keep multiple quota pools independent;
- repeated detailed structure is required to bind an unversioned schema;
- live no-turn evidence is a mandatory source-safety gate.

Deferring those gates to production would redefine the Goal rather than satisfy
it.

## Locked consequences

- Antigravity remains unregistered and hidden in UMA.
- No production connector, scheduler, Settings entry, main-panel card, or
  Desktop Assistant presentation is authorized.
- No status line, API-key route, token route, Keychain route, browser source,
  manual quota, Credits implementation, or inferred balance is admitted.
- Codex, Claude Code, and WorkBuddy mechanisms remain unchanged.
- M5 frozen and shared runtime paths remain unchanged.
- M6-G2 remains locked.

## Next task

The only next task is:

```text
Founder source-direction decision
```

No further live read or alternate source class is implied by this record.
