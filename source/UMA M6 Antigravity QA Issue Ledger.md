# UMA M6 Antigravity QA Issue Ledger

**Goals:** M6-G1, M6-SETUP-G1, M6-G1R and M6-G1R2
**Date:** 2026-08-08
**Historical M6-G1 decision:** `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`
**Historical M6-G1R decision:** `NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE`
**Current decision:** `GO — OFFICIAL ANTIGRAVITY CLI QUOTA SOURCE ADMITTED`
**Credits:** `CREDITS DEFER`
**Only next task:** M6-G2

## Scope

The exact M6-G1R2 repository scope is:

```text
Tests/CodexUsageUITests/M6G1AntigravitySourceAdmissionTests.swift
source/UMA M6 Antigravity Local Source Dossier.md
source/UMA M6 Antigravity Admission Decision.md
source/UMA M6 Antigravity Privacy Contract.md
source/UMA M6 Antigravity QA Issue Ledger.md
```

`source/UMA M6 Antigravity Setup Evidence.md` remains unchanged historical
setup evidence. No connector source, packaging helper, production runtime,
provider registry, UI, scheduler, package, M5 record or existing Scope Lock
belongs to this Goal.

## Issue ledger

| ID | First evidence | Classification | Root cause | Repair | Retest | Final status |
|---|---|---|---|---|---|---|
| M6G1-001 | Initial G1 found no standalone CLI | Historical setup gate | Official CLI was not installed | Return `SETUP REQUIRED`; run separate authorized setup | Historical admission tests | Closed by M6-SETUP-G1 |
| M6SETUP-001 | Official installer produced manifest-exact CLI `1.1.11` | Historical setup | Separate setup was required | Install and verify official CLI/help/structured capability | Setup tests | Closed |
| M6SETUP-002 | Reliable local code-sign/Gatekeeper PASS unavailable | Accepted trust risk | Local trust service also failed Apple control apps | Founder accepted exact installer/manifest/checksum provenance | Post-install identity checks | Closed with disclosed risk |
| M6SETUP-003 | Broad process inventory exposed process-local metadata transiently | Historical privacy incident | Full argv was collected instead of exact PID/executable facts | Do not retain/reproduce; prohibit broad argv evidence | Git/temp/log review | Closed with disclosure |
| M6G1R-001 | Two sandbox reads failed and one ordinary read succeeded | Historical environment result | Restricted execution prevented provider access | Classify environment failures separately | Ordinary read produced JSON | Closed |
| M6G1R-002 | One detailed successful response lacked repetition proof | Historical mandatory gap | Setup evidence retained only success class | Open bounded M6-G1R2 evidence repair | Two detailed ordinary successes | Closed by M6-G1R2 |
| M6G1R-003 | Exact safe bucket identity was not retained across successful reads | Historical mandatory gap | Only one detailed sample existed | Compare smallest provider-owned identity transiently | Both pools stable by `bucket.id` | Closed by M6-G1R2 |
| M6G1R-004 | `num_turns` was retained only as a range | Historical mandatory gap | Operational evidence was over-sanitized | Retain normalized zero-turn/no-work booleans only | Both successful reads confirmed zero-turn/no-work | Closed by M6-G1R2 |
| M6G1R-005 | Observed envelope contained private/unneeded fields | Privacy boundary | CLI envelope is broader than UMA quota needs | Strict allowlist and early discard | Projection/privacy tests | Closed |
| M6G1R-006 | Test harness initially conflated structure and identity and did not bind command name | Historical test defect | Admission contract was incomplete | Separate identity gate; require `command.name == usage` | Focused/full tests | Closed |
| M6G1R2-001 | First new provider execution completed, then harness process-group teardown returned permission error | Local evidence-harness defect | Process-group signaling was not always permitted after child completion | Wait/reap first; fall back to bounded direct-child termination; count execution conservatively | Two subsequent deliberate reads completed cleanly | Closed |
| M6G1R2-002 | First run created one task-owned provider temp regular file | Temporary resource | Provider used the isolated temp root | Verify exact metadata/open-handle state and delete without reading; automatically clear exact safe future artifacts | Two later artifacts cleared; temp root empty | Closed |
| M6G1R2-003 | Repeated schema was previously unproven | Admission repair | Only one detailed observation existed | Compare two ordinary structured observations | Same root/container/fields/types/counts | Closed |
| M6G1R2-004 | Stable provider-owned pool identity was previously unproven | Admission repair | Exact identity had been over-sanitized | Compare identifiers transiently; retain only stability classes | Two pools stable by global `bucket.id`; order independent | Closed |
| M6G1R2-005 | Exact no-turn behavior was previously unproven | Admission repair | Range-only sanitization lost the decisive fact | Normalize exact operational inputs to booleans | Zero turns/no conversation/no task/all counters zero/no model response | Closed |
| M6G1R2-006 | Quota-consumption attribution required bounded evidence | Admission repair | Exact balances could not be retained | Compare transiently and retain only attribution class | No attributable decrement observed within provider granularity | Closed |
| M6G1R2-007 | Current `script/test.sh` stopped before project compilation | External verification-toolchain drift | Command Line Tools advanced to Swift `6.4`; the checked-in helper remains pinned to the older `MacOSX26.5` SDK, while the matching `MacOSX27` SDK does not ship the SwiftUI macro implementation required by full-product compilation | Do not widen this five-file evidence Goal to modify build infrastructure; compile and run the complete M6 admission file in an isolated task-owned package, and retain the accepted exact-predecessor full-suite/build results for unchanged production sources | Focused M6-G1R2 suite 26/26 PASS; protected production diff empty; predecessor full suite 506/506 and Debug/Release passed | Closed for M6 source admission with disclosed external toolchain risk; full current-suite rerun remains unavailable |

No issue was converted into a production runtime workaround.

## M6-G1R2 live accounting

| Operation | Authorized | Consumed |
|---|---:|---:|
| `/usage` executions | 3 | 3 |
| Successful structured observations | at least 2 | 2 |
| Locally unclassified executions | n/a | 1 |
| Automatic retries | 0 | 0 |
| `/credits` executions | 0 | 0 |
| Provider prompts/tasks | 0 | 0 |
| Intentional provider work/spend | 0 | 0 |

The first execution counts against the budget despite the local post-process
harness failure. The second and third executions were the minimum remaining
deliberate observations required by the Goal, not retries.

## Sanitized live evidence

- both successful reads: exit 0, one JSON object, 1,141 stdout bytes, empty stderr;
- identical required container, fields, field types, two groups and one bucket
  per group;
- explicit remaining fraction and bucket-scoped absolute reset semantics;
- `POOL_A_IDENTITY_STABLE: YES` and `POOL_B_IDENTITY_STABLE: YES` using global
  `bucket.id` only;
- one reset changed without changing bucket identity;
- zero turns, no conversation, no task identifier, all provider token counters
  zero and no model response on each successful read;
- no attributable quota decrement observed within provider granularity;
- Safari process count unchanged, no residual `agy`, empty neutral cwd and empty
  isolated provider temp root after cleanup;
- no raw payload, exact live value, exact provider identity, account identity,
  credential, response, conversation or task content persisted.

## Required verification

| Check | Result |
|---|---|
| Focused M6-G1R2 tests | PASS — 26/26 in an isolated task-owned package using the exact repository test and records |
| Full `script/test.sh` suite | Current rerun blocked before project compilation by external Swift `6.4` / pinned SDK / missing SwiftUI macro-toolchain drift; accepted predecessor PASS — 506/506 |
| Debug build | Accepted predecessor PASS; production source diff is empty; current toolchain has the same pre-project SwiftUI macro blocker |
| Release build | Accepted predecessor PASS; production source diff is empty; current toolchain has the same pre-project SwiftUI macro blocker |
| Strict-concurrency Release build | Accepted predecessor PASS; production source diff is empty; current toolchain has the same pre-project SwiftUI macro blocker |
| `git diff --check` | PASS |
| Privacy/identity/secret scan | PASS — reserved `.invalid` synthetic fixture only; no live identity, credential, token, raw payload or user-expanded path |
| M5/Codex/Claude/WorkBuddy protected diff audit | PASS — no production source, protected record or mechanism changed |
| Exact staged-index review | PASS — independent cached review found no blocking or actionable issue |
| Task-owned temporary evidence/build cleanup | PASS — twelve exact M6-G1R2 probe/evidence/build paths removed after verification |

## Mechanism audit

```text
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
Antigravity production runtime implemented: NO
```

## Completion contract

All four current records agree on:

```text
Admission: GO — OFFICIAL ANTIGRAVITY CLI QUOTA SOURCE ADMITTED
Repeated structure: PASS
Stable provider-owned identity: PASS — bucket.id
Zero-turn/no-provider-work: PASS
Credits: CREDITS DEFER
M6-G1R2 reads: 3/3; successful detailed observations: 2; retries: 0
Only next task: M6-G2
```

M6-G2 was not started.
