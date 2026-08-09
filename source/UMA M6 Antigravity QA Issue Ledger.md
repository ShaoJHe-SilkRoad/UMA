# UMA M6 Antigravity QA Issue Ledger

**Goals:** M6-G1, M6-SETUP-G1 and M6-G1R
**Date:** 2026-08-08
**Historical M6-G1 decision:** `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`
**Setup result:** `PASS — OFFICIAL ANTIGRAVITY CLI READY FOR M6-G1R`
**Current decision:** `NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE`

## Scope

The exact M6-G1R repository scope is:

```text
Tests/CodexUsageUITests/M6G1AntigravitySourceAdmissionTests.swift
source/UMA M6 Antigravity Local Source Dossier.md
source/UMA M6 Antigravity Admission Decision.md
source/UMA M6 Antigravity Privacy Contract.md
source/UMA M6 Antigravity QA Issue Ledger.md
```

`source/UMA M6 Antigravity Setup Evidence.md` remains unchanged historical
setup evidence. No runtime, manifest, browser-extension, package-script, M5
record, M5 test, or existing Scope Lock change belongs to M6-G1R.

## Issue ledger

| ID | First evidence | Classification | Root cause | Resolution | Retest | Final status |
|---|---|---|---|---|---|---|
| M6G1-001 | Initial G1 found no standalone CLI | Historical setup gate | Official CLI was not yet installed | Return `SETUP REQUIRED` without live read | Historical deterministic tests | Closed by M6-SETUP-G1 |
| M6SETUP-001 | Official installer produced manifest-exact CLI `1.1.11` | Historical setup result | Separate setup was required | Install, verify help, retain sanitized evidence | Setup tests 10/10 PASS | Closed |
| M6SETUP-002 | Reliable local code-sign/Gatekeeper PASS unavailable | Accepted trust risk | Local trust service also failed Apple control apps | Founder accepted exact installer/manifest/checksum provenance | Post-install identity checks | Closed with disclosed risk |
| M6SETUP-003 | Process inventory exposed one process-local CSRF argument in transient output | Historical privacy incident | Full argv was collected instead of PID/executable identity only | Do not retain/reproduce; prohibit broad argv evidence | Git/temp/log review | Closed with disclosure |
| M6G1R-001 | First two exact `/usage` executions returned exit 1, zero stdout and bounded generic stderr | Execution environment | Both ran inside the tool's network-restricted sandbox | Use the final authorized ambiguity-resolution read in ordinary network context; retain no raw stderr | Third execution returned structured JSON | Closed as environmental limitation |
| M6G1R-002 | One ordinary-network read returned `command.data.groups[].buckets[]` | Schema evidence | Setup retained JSON success only, not field structure | Record field/type/range classifications without live values | Deterministic observed-shape tests | Closed for one observation |
| M6G1R-003 | Bucket contained explicit `remaining_fraction` | Semantic evidence | Remaining semantics were previously unadmitted | Admit only `remainingPercent = remaining_fraction × 100`; finite `0...1`; no clamp | Boundary, invalid, missing and wrong-type tests | Closed |
| M6G1R-004 | Bucket contained ISO-8601 `reset_time`; no duration | Reset evidence | Reset representation was previously unknown | Keep reset bucket-scoped; accept absence; reject malformed present value | Present/absent/malformed reset tests | Closed |
| M6G1R-005 | Envelope contained response, conversation, turn/duration and token-counter fields | Privacy boundary | Structured command output includes fields not needed by quota UI | Discard before projection; allowlist only bounded quota identity/value/reset/version/time | Private/unknown-field projection tests and examiner review | Closed |
| M6G1R-006 | Exact safe bucket identity was not retained across two successful reads | Mandatory admission gap | Only one detailed successful sample remained within the read budget | Do not infer or hard-code identity; return `NO-GO` | Source/protocol and privacy examiner review | Open for future Founder-authorized direction |
| M6G1R-007 | Detailed schema stability was not repeated | Mandatory admission gap | Two sandbox executions produced no JSON; setup retained only JSON-success classification | Do not treat environmental failures as provider instability or as repeatability proof | Independent decision review | Open for future Founder-authorized direction |
| M6G1R-008 | Sanitizer retained only `num_turns` range `0...1` | Mandatory no-turn gap | Exact operational counter was over-sanitized | Preserve official no-turn contract and empty conversation evidence, but do not overclaim live zero-turn proof | Independent decision review | Open for future Founder-authorized direction |
| M6G1R-009 | QA examiner recommended `CONDITIONAL GO`; two examiners recommended `NO-GO` | Decision disagreement | QA treated repeatability/identity/no-turn as later acceptance conditions | Apply governing criteria: those are core GO gates, not optional conditional metadata | Root requirement-by-requirement audit | Closed as `NO-GO` |
| M6G1R-010 | Shared packet initially had mode `0644` inside owner-only directory | Temporary evidence permission | Patch creation used default file mode | Change exact packet to `0600`; preserve directory `0700` | Privacy examiner recheck: PASS | Closed |
| M6G1R-011 | A bare sandboxed `swift build -c debug` could not write the user module cache, then selected an SDK whose SwiftUI macro plugin was unavailable | Verification environment | The repository requires its pinned SDK and isolated module-cache flags | Re-run Debug and Release with the repository's established MacOSX26.5 SDK, isolated task-owned caches and explicit macro compatibility flag | Both product builds completed | Closed |
| M6G1R-012 | Independent cached review found the test harness did not model identity stability separately, retained a positive user-expanded executable path, and did not validate `command.name` | Test-contract and privacy hardening | Structural and identity stability were initially conflated; the exact argv fixture used an expanded path; shape alone accepted another command envelope | Add a mandatory independent identity gate and test, normalize the fixture to `$HOME`, and require `command.name == usage` | Focused 21/21; full 506/506 | Closed |

No issue was converted into a production connector workaround. No UMA runtime
repair was implemented.

## Shared sanitized evidence

The source/protocol examiner, privacy examiner and QA runner reviewed the same
owner-only packet. It contained:

- installed source and exact command classifications;
- three-read accounting and sanitized execution outcomes;
- field names, types, range classes and byte counts;
- schema, semantic, reset, privacy and authentication classifications;
- explicit evidence gaps and `CREDITS DEFER`.

It contained no raw stdout/stderr/JSON, exact quota/reset value, exact group or
bucket identity, response text, account identity, credential, browser data,
conversation content, task content, provider content, screenshot or raw-payload
hash.

Examiner results:

- source/protocol: `NO-GO`;
- privacy: PASS privacy boundary and `NO-GO` admission recommendation;
- QA: `CONDITIONAL GO` recommendation with later identity/stability/no-turn gates;
- root: `NO-GO`, because those three gates are mandatory under M6-G1R.

## Probe accounting

| Operation | Authorized | Consumed |
|---|---:|---:|
| M6-G1 source reads | 3 | 0 |
| M6-SETUP-G1 readiness reads | 1 | 1 |
| M6-G1R `/usage` or `/quota` executions | 3 | 3 |
| M6-G1R automatic retries | 0 | 0 |
| M6-G1R `/credits` executions | 0 | 0 |
| Provider prompts/tasks | 0 | 0 |
| Intentional provider work/spend | 0 | 0 |

The first two G1R executions produced no JSON inside the network-restricted tool
sandbox. The third produced one current structured JSON object in the approved
ordinary network context. No further live read is authorized.

## Required verification

| Check | Result |
|---|---|
| Focused M6-G1R tests | PASS — 21/21 |
| Full `script/test.sh` suite | PASS — 506/506 (488 main + 18 bridge) |
| Debug build | PASS — pinned SDK, isolated task-owned cache |
| Release build | PASS — pinned SDK, isolated task-owned cache |
| `git diff --check` | PASS |
| Privacy/identity/secret scan | PASS — only reserved `.invalid` synthetic test data and an explicit path-rejection sentinel were present; no live identity or secret material |
| M5/Codex/Claude/WorkBuddy protected diff audit | PASS — no protected runtime or record changed |
| Exact staged-index review | PASS — independent cached review after repair |
| Task-owned temporary evidence/build cleanup | PASS — five exact M6-G1R paths removed after examiner and build completion |

## Mechanism audit

```text
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
Antigravity production runtime implemented: NO
```

## Completion rule

All four current records must agree on:

```text
Admission: NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE
Proven: one current structured quota object with explicit remaining and reset
Unproven: repeated detailed structure, stable pool identity, exact live no-turn
Credits: CREDITS DEFER
M6-G1R reads: 3/3, automatic retries 0
Only next task: Founder source-direction decision
```

M6-G2 remains locked.
