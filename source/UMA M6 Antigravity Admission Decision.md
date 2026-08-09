# UMA M6 Antigravity Admission Decision

**Goal:** M6-G1R2
**Date:** 2026-08-08
**Decision:** `GO — OFFICIAL ANTIGRAVITY CLI QUOTA SOURCE ADMITTED`
**Credits:** `CREDITS DEFER`
**Only next task:** M6-G2

## Decision history

- M6-G1: `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`;
  M6-SETUP-G1 was next.
- M6-SETUP-G1: official manifest-pinned CLI `1.1.11` installed and setup-ready;
  M6-G1R was next.
- M6-G1R: `NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE`; one detailed
  structured result did not prove repetition, stable identity or exact live
  zero-turn behavior.
- M6-G1R2: all three evidence gaps were repaired within the new bounded budget.

## Admission matrix

| Gate | M6-G1R2 evidence | Result |
|---|---|---|
| Official installed source | Manifest-pinned `$HOME/.local/bin/agy`, version `1.1.11`, identity unchanged | PASS |
| Exact read-only command | `--output-format json -p /usage`; official print/read-only contract | PASS |
| Repeated structure | Two ordinary exit-0 reads had the same exact required container, fields, types and pool counts | PASS |
| Stable pool identity | Smallest provider-owned identity is globally unique `bucket.id`; both observed pools matched across reads and independent of order/value/reset | PASS |
| Remaining semantics | Explicit finite `remaining_fraction` in `0...1`; multiply by 100 once | PASS |
| Reset semantics | Optional, bucket-scoped, absolute ISO-8601 `reset_time`; changed reset did not change identity | PASS |
| Zero-turn/no work | Each successful read normalized to zero turns, no conversation, no task identifier, all token counters zero and no model response | PASS |
| No attributable decrement | No attributable decrement observed within provider granularity, consistent with the official read-only contract | PASS |
| Authentication boundary | Existing provider-owned session worked; no credential material or browser login action | PASS |
| Process/lifecycle | One owned child, bounded I/O/time, complete teardown, no residual process | PASS |
| Privacy reduction | Strict allowlist; raw payload and exact live values/identities discarded | PASS |
| Credits | No `/credits` read and no inferred/manual value | `CREDITS DEFER` |

## Read accounting

M6-G1R2 consumed **3/3** authorized `/usage` executions. The first completed but
its local harness failed during teardown before a sanitized result could be
retained, so it is conservatively unclassified. The harness was repaired. The
second and third executions each returned the reproducible structured result.
Automatic retries, `/credits` reads, provider prompts/tasks and intentional spend
were all **0**.

## Decision logic

`GO` is warranted because the primary quota, lifecycle, privacy, repeatability,
provider-owned identity and no-provider-work gates are all proven. No optional
gap remains that would require `CONDITIONAL GO`. The result does not admit a
Credits source and does not authorize a runtime implementation by itself.

## Locked boundary

No production Antigravity connector, registry entry, scheduler, Settings,
main-panel card, Desktop Assistant presentation, package or installed app was
created or changed in M6-G1R2. Codex, Claude, WorkBuddy and M5 remained
unchanged.

Final decision:

`GO — OFFICIAL ANTIGRAVITY CLI QUOTA SOURCE ADMITTED`

Credits remain **`CREDITS DEFER`**. **M6-G2 is the only next task; it was not
started.**
