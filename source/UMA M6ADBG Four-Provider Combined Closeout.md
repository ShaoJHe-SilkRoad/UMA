# UMA M6ADBG Four-Provider Combined Closeout

**Goal:** M6ADBG-G1

**Date:** 2026-08-09

**Baseline:** `37512b69feaa8d3048848bcd850b7016e13df67d`

**Credits:** `CREDITS DEFER`

**Physical VoiceOver:** deferred by the governing Goal

## Scope and ownership

M6ADBG qualifies the accepted four-provider product across the Main Panel and
Desktop Assistant. It does not add a provider or source mechanism. Provider
order remains:

```text
Codex → Claude Code → WorkBuddy → Google Antigravity
```

`UsageStore.presentationCards` remains the single accepted shared truth.
Desktop Assistant adapts that immutable presentation and owns no executable,
CLI client, decoder, scheduler, cache, observation, Maximum Decrement
calculation or quota-pool selection.

## Combined acceptance matrix

| Area | Required result | Final evidence |
|---|---|---|
| Provider subsets | 0, each single, every pair/triple and all four | PASS — all 16 subsets through one shared-presentation oracle |
| Failure combinations | zero cross-provider blanking or failure inheritance | PASS — every one/two-provider failure mix, all unavailable and removal/reappearance |
| Antigravity parity | stable bucket ID, selected pool, remaining, reset and freshness match | PASS — exact shared truth across Fresh/Cached/Stale, reordered buckets and missing reset |
| Semantic units | Missing is not zero; Unlimited is not 100%; WorkBuddy remains Credits | PASS |
| Density | four providers Regular; Minimalist only above four | PASS — four-provider Regular and five-provider forced-Minimalist fixtures |
| Appearance | Light/Dark, EN/zh-CN, transparency, contrast and motion | PASS — 15 deterministic captures; no clipping, overlap, double layer or layout jump |
| Lifecycle | panel/Assistant show-hide, Settings, position, Always on Top and teardown | PASS — 50 Assistant visibility transitions / 25 hide-show cycles plus exact-path preflight launch/shutdown |
| Refresh ownership | one Antigravity scheduler/read; no rendering-owned refresh | PASS — scheduled/manual coalescing and maximum one read/process |
| Endurance/resources | bounded CPU, RSS, threads, descriptors, children and writes | PASS — five-minute exact-PID soak showed falling RSS/threads, stable descriptors/files and zero children |
| Privacy | safe exact-PID/count inspection; no broad argv/environment capture | PASS — no recurrence of M6A-R-001 |

## Safe process-inspection contract

Evidence is restricted to the exact task-owned executable path/name, captured
PID, required parent-child ownership, process count, bounded CPU/RSS/thread/file
descriptor counters and exit/absence. Full process command lines, unrelated
arguments, broad environments and provider session metadata are forbidden.
Checks fail closed if these normalized fields are insufficient.

## Live accounting

| Operation | Cap | Used |
|---|---:|---:|
| Antigravity read-only `/usage` | 6 | 2 |
| `/credits` | 0 | 0 |
| Provider prompts/tasks | 0 | 0 |
| Intentional provider work/spend | 0 | 0 |

No exact quota value, bucket label/identity, reset timestamp, raw JSON, stderr,
account identity, credential, conversation or task content may be retained.

## Verification and delivery

| Check | Final result |
|---|---|
| Focused M6ADBG suite | PASS — 6/6 |
| Affected M6 suites | PASS — 91/91 across 12 suites |
| Deterministic serial full suite | PASS — 570 UI plus 18 bridge = 588/588 |
| Debug / Release / strict-concurrency Release | PASS / PASS / PASS with warnings as errors |
| Deterministic renderer matrix | PASS — 15 Light/Dark, EN/zh-CN, accessibility-state and provider-density captures |
| Working-tree preflight package | PASS — build `202608090106`, arm64, strict deep signature, 21-file allowlist |
| Privacy, secret, fixture and identity scans | PASS — zero retained live/private values or prohibited package material |
| Protected M5 52-file manifest | PASS — accepted frozen set unchanged |
| Codex / Claude / WorkBuddy mechanisms | PASS — unchanged; Antigravity source mechanism also unchanged |
| Independent staged-index review | PASS — exact five-file cached scope; source, QA and privacy reviews found no blocking or actionable issue |
| Final commit and tree | Pending authorized local commit |
| Commit-exact package | Pending post-commit build |
| Protected Desktop UMA | PASS — executable SHA-256 remains `88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a` |
| Post-commit worktree and index | Pending |

The live production harness used two of six authorized read-only `/usage`
operations. Both observations were normalized in memory and retained only as
boolean/count evidence. Scheduled refresh, manual-refresh coalescing, stable
bucket identity, remaining normalization, main/Assistant admission and
teardown passed. `/credits`, prompts/tasks and intentional spend remained zero.

The five-minute exact-PID renderer soak recorded CPU `0.0% / 0.0% / 0.0%`,
RSS `88,624 / 80,880 / 69,664 KiB`, threads `10 / 3 / 3`, three file
descriptors throughout, zero Antigravity children and a stable 15-file
task-owned footprint. Clean shutdown left the captured PID absent.

## Completion lock

After PASS, exactly one next task is permitted:

`M6-CLOSE-G1 — Current-source update and Cursor handoff`

M6-CLOSE-G1 and Cursor are not started by this record.
