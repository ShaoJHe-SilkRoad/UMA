# UMA M6 Antigravity QA Issue Ledger

**Goals:** M6-G1, M6-SETUP-G1, M6-G1R, M6-G1R2, M6-G2, M6-G3 and M6DBG-G1
**Date:** 2026-08-08
**Historical M6-G1 decision:** `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`
**Historical M6-G1R decision:** `NO-GO — LIVE ADMISSION EVIDENCE INCOMPLETE`
**Current decision:** `GO — OFFICIAL ANTIGRAVITY CLI QUOTA SOURCE ADMITTED`
**Credits:** `CREDITS DEFER`
**Only next task after M6DBG PASS:** M6A-G1

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

This historical M6-G1R2 section ended before M6-G2 began. The completed M6-G2
closure evidence is recorded below.

## M6-G2 connector, scheduler and Settings issue ledger

This section contains no live quota, reset timestamp, pool identity, account
identity, credential, provider response, raw output, conversation, task, prompt,
screenshot or workspace data. All G2 provider inputs were deterministic fixtures.

| ID | Found by | Severity | Evidence / acceptance impact | Repair | Focused retest | Regression retest | Final status |
|---|---|---:|---|---|---|---|---|
| M6G2-001 | Source-boundary review | Blocking | A generic subprocess path could widen the admitted source beyond the exact official executable and `/usage` command | Bind the client to the current-user `$HOME/.local/bin/agy`, admitted SHA/version/arm64 identity and exact argv; no shell, provider input, credential environment or user workspace | CLI client 8/8 PASS | Full suite 552/552 PASS | Closed |
| M6G2-002 | Decoder review | Blocking | Permissive decoding could admit private fields, ambiguous percentage semantics or unstable pool identities | Strict allowlist; explicit remaining conversion once; independent stable buckets; fail closed on ambiguity, invalid range, future schema or duplicate identity | M6-G2 focused matrix PASS | Full suite 552/552 PASS | Closed |
| M6G2-003 | Lifecycle review | Major | Independent triggers could multiply processes, overlap reads or create retry bursts | One source-owned completion-relative five-minute scheduler, one in-flight process, three-minute minimum, coalescing and complete child teardown | Scheduler suite PASS | Full suite 552/552 PASS | Closed |
| M6G2-004 | Authentication/privacy review | Blocking | Routine refresh could trigger/adopt login state, expose provider data or persist raw output | Provider-owned authentication only; suspend on login-required classification; publish normalized quota fields and bounded safe classifications | Privacy and CLI suites PASS | Source/package scans PASS | Closed |
| M6G2-005 | Settings/localization review | Major | Setup and freshness could be unclear or require credential-shaped UI | Injected-operation Settings with Check, official Install/Open, Login Required, Connected/Refreshing/Fresh/Cached/Stale, Auto Refresh, Sync Now, Disable and source/privacy text in EN/zh-CN | Settings suite PASS | Full suite 552/552 PASS | Closed |
| M6G2-006 | Shared-surface review | Blocking | A fourth provider could change existing provider behavior or density | Add Antigravity-only shared branches, preserve order and Maximum Decrement, keep four-provider Regular behavior and exclude provider four from Desktop Assistant | Presentation/package suite PASS | Codex/Claude/WorkBuddy full regressions PASS | Closed |
| M6G2-007 | Toolchain review | Gate | User-level SwiftPM/Clang caches were unavailable and a bare invocation produced misleading SDK drift diagnostics | Keep frozen `script/test.sh`; use current Apple CLT 27.0, its pinned macOS 26.5 SDK and task-owned writable module caches | Complete script entry point PASS | Debug/Release/strict Release PASS | Closed |
| M6G2-008 | Package/privacy review | Gate | Initial helper used an incorrect developer-root ascent and a nonexistent `/usr/bin/chmod`; an earlier preflight also selected an unnecessary beta Xcode path | Correct path/tool usage, then select verified Apple Command Line Tools and pinned SDK by default; preserve M5 companions and enforce provenance/signature/dependency/file/privacy allowlists | Package contract 5/5 PASS | Final-code preflight PASS | Closed |
| M6G2-009 | Process cancellation retest | Blocking | Cancellation could arrive before `Process.run()`, leaving the owned child to run until normal exit; only the 15-second soft timeout existed | Reject pre-launch cancellation, terminate immediately after a launch race, add a separate 20-second force-kill ceiling, and always reap | Cancellation 0.002 s; CLI suite 8/8 PASS | Full suite 552/552 PASS | Closed |
| M6G2-010 | Fixture review | Minor | JSONSerialization cannot encode infinite floating-point test arguments | Test out-of-range finite values through JSONSerialization and feed NaN/Infinity spellings as malformed raw JSON | Decoder suite PASS | Full suite 552/552 PASS | Closed |
| M6G2-011 | Final lifecycle review | Major | A single connector stream continuation let the Settings observer replace the registry observer, while omitting the Settings observer left scheduled Fresh/Cached/Stale state frozen | Support independently owned bounded stream continuations and bind the idle Settings model to the same normalized connector snapshots; also enforce owner and execute-mode checks at the public capability gate | Focused observer and trust tests PASS | Final full suite 552/552 PASS; Release/strict Release PASS | Closed |
| M6G2-012 | Independent staged review | Blocking | The first decoder accepted future/private container fields and recursively traversed rejected response content | Enforce exact root/command/data/group/bucket field allowlists, validate admitted descriptions only as discarded schema types, reject future fields without descending into their values and never access the response value | Decoder and CLI suites PASS; 42/42 focused | Full suite 552/552 PASS | Closed |
| M6G2-013 | Independent staged review | Major | Auto Refresh could stop at a disabled due cycle without a path to reschedule, and Disable could diverge from the persisted preference | Add an explicit connector refresh-control operation; persist and cancel on Disable; reschedule on re-enable | Off→due→on and disable persistence tests PASS | Full suite 552/552; Release/strict Release PASS | Closed |
| M6G2-014 | Independent staged review | Major | Missing CLI capability was collapsed into generic failure, making the required Install/Open Settings state unreachable | Carry a bounded unsupported/unavailable capability classification and map it to `notInstalled` plus `executableMissing` in production Settings | Connector and production-wiring tests PASS | Full suite 552/552 PASS | Closed |

## M6-G3 live acceptance issue ledger

This section retains no exact quota, bucket identifier, label, reset timestamp,
raw provider output, identity, credential, conversation, prompt or task data.

| ID | First evidence | Classification | Root cause | Repair | Focused retest | Live/regression retest | Final status |
|---|---|---:|---|---|---|---|---|
| M6G3-001 | The first bounded production reads exited normally but were rejected before normalization; the narrowed safe class was `invalidBucket` | Blocking live-admission defect | The G2 decoder applied a machine-identifier alphabet to schema-only human-readable group/window text and treated a provider null reset as malformed rather than unavailable | Keep `bucket.id` strict; validate group/window text as bounded non-control schema strings; map null reset to unavailable; preserve exact key/type gates; retain content-free decoder failure classes | Strict decoder and bounded client suites PASS | Final two-read production connector/scheduler gate PASS | Closed |
| M6G3-002 | A direct source assertion matched its own forbidden-literal assertion | Test defect | The self-audit embedded the complete forbidden token | Construct the forbidden token from fragments so only an actual route/payload identifier trips the audit | G3 deterministic contract test PASS | Final full suite 555/555 PASS | Closed |

## M6-G3 live accounting

| Operation class | Authorized | Consumed |
|---|---:|---:|
| Read-only `/usage` operations | 6 | 6 |
| Successful final production observations | 2 | 2 |
| Diagnostic fail-closed observations | 4 | 4 |
| `/credits` operations | 0 | 0 |
| Provider prompts/tasks/conversations | 0 | 0 |
| Intentional provider work/spend | 0 | 0 |

The final acceptance sequence used the production client, strict decoder,
connector, registry, UsageStore and shared main-panel presentation. One current
read armed the normal completion-relative five-minute scheduler; its scheduled
read completed; a simultaneous manual request coalesced into that single
in-flight operation. Maximum concurrent provider process count was one.

Sanitized final evidence passed: multiple independent buckets, stable
`bucket.id`, remaining normalization parity, bucket-scoped reset validation,
main-panel admission, exact four-provider order, Desktop Assistant exclusion,
scheduled refresh, manual/scheduled coalescing, no duplicate process, no
attributable decrement within provider granularity and complete teardown.

Credits remain `CREDITS DEFER`.

## M6-G3 final verification summary

| Check | Result |
|---|---|
| Focused decoder, client, connector and G3 acceptance tests | PASS — 32/32 on the repaired final edit set |
| Complete fresh suite | PASS — 537 UI tests plus 18 bridge tests, 555/555 total, using isolated task-owned caches and deterministic serial execution |
| Debug / Release / strict-concurrency Release | PASS — Apple Command Line Tools 27.0, Swift 6.4, macOS 26.5 SDK, task-owned caches |
| Rebuilt G3 preflight package | PASS — build `202608090102`, working-tree preflight, strict deep ad-hoc signature, arm64, system dependencies only, exact package-content allowlist and no bundled `agy` |
| Privacy, identity and secret audit | PASS — no retained provider payload, identity, credential or exact quota value; the sole production keyword hit is the explicit environment denylist entry `cookies` |
| Protected M5 files | PASS — accepted 52-file Git-blob manifest unchanged |
| Protected Desktop application | PASS — executable checksum unchanged; no replacement or launch used as G3 evidence |
| Provider processes | PASS — no residual `agy` or task-owned candidate process |
| `git diff --check` | PASS |
| Independent staged-index review | PASS — exact nine-file cached scope; no blocking or actionable issue |
| Credits | `CREDITS DEFER` |

## M6-G2 final verification summary

| Check | Result |
|---|---|
| Focused M6-G2 tests | PASS — 42/42 on the repaired final edit set |
| Complete `script/test.sh` | PASS — 534 UI tests plus 18 bridge tests, 552/552 total, using the supported deterministic `--no-parallel` SwiftPM execution mode |
| Debug / Release / strict-concurrency Release | PASS — Apple Command Line Tools 27.0, Swift 6.4, macOS 26.5 SDK, task-owned caches |
| Preflight package | PASS — working-tree preflight, strict deep ad-hoc signature, arm64, system dependencies only, exact file allowlist, no bundled `agy` |
| `git diff --check` | PASS |
| Independent staged-index review | PASS — repaired 25-file cached scope; no blocking or actionable issue |
| Provider reads and prompts | 0 / 0 |
| Credits | `CREDITS DEFER` |
| Protected M5 files | PASS — 52-file frozen set unchanged from the accepted manifest |
| Existing mechanisms | Codex NO; Claude NO; WorkBuddy NO |

## M6DBG-G1 four-provider defect closure

This section retains no exact quota, bucket identifier, label, reset timestamp,
raw provider output, identity, credential, conversation, prompt or task data.

| ID | Finder | Severity | Evidence / acceptance impact | Repair | Focused retest | Regression retest | Final status |
|---|---|---:|---|---|---|---|---|
| M6DBG-001 | Lifecycle review | Major | The completed launch-read task could remain stored briefly and consume the first later manual refresh without starting a new provider read | Distinguish an active launch read from a completed launch task; coalesce only the active operation and execute the later refresh | Launch/manual handoff and collision tests PASS | M6 85/85; full 570/570 | Closed |
| M6DBG-002 | Lifecycle review | Major | The production Settings observer task was unowned, so model/runtime teardown could leave a connector stream continuation alive | Give `AntigravitySettingsModel` sole task ownership; cancel at deinit; verify stream continuation removal | 30 Settings cycles and observer teardown PASS | M6 85/85; full 570/570 | Closed |
| M6DBG-003 | Failure-matrix test | Major | A timeout could retain last-valid quota while continuing to label it Fresh | Mark retained last-valid data Cached immediately on a failed current read; preserve the existing Stale age boundary and recovery to Fresh | Transient failure/recovery test PASS | M6 85/85; full 570/570 | Closed |
| M6DBG-004 | Focused test run | Minor, acceptance-required | A constant-zero deterministic random generator could stall bounded standard-library shuffle selection | Replace it with a seeded deterministic generator | All 24 completion-order permutations PASS | M6DBG 11/11 PASS | Closed |
| M6DBG-005 | Privacy-test review | Minor, acceptance-required | The first self-audit treated required no-work validation and explicit unsupported-field names as active privacy paths | Reject active Credits/credential/browser mechanisms while affirmatively checking safe no-work validation and unsupported-field classification | Privacy contract test PASS | M6DBG 11/11 PASS | Closed |
| M6DBG-006 | Independent staged-index review | Blocking | An immediate refresh cleared cancellation ownership before awaiting a launch task; Disconnect could then miss a delayed task and allow it to read or republish after teardown | Retain launch-task ownership, validate started/generation/cancellation before and after the read, and return fail-closed after lifecycle invalidation | Deterministic barrier race proves zero reads and inactive state after immediate refresh/Disconnect | Scheduler 15/15; M6 85/85; full 570/570 | Closed |
| M6DBG-007 | Independent staged-index review | Blocking | Connector cycles did not prove full application relaunch, and sleep/wake had no explicit M6DBG acceptance evidence | Run the rebuilt exact preflight through 20 isolated full-app launch/termination cycles and add deterministic wake-during-read coverage | 20/20 exact-path app cycles, zero residual process; wake produces no duplicate read and keeps one scheduler | M6 85/85; full 570/570 | Closed |

## M6DBG live accounting

| Operation class | Authorized | Consumed |
|---|---:|---:|
| Read-only `/usage` operations | 6 | 4 |
| Successful structured operations | n/a | 4 |
| Final-code accepted operations | n/a | 2 |
| `/credits` operations | 0 | 0 |
| Provider prompts/tasks/conversations | 0 | 0 |
| Intentional provider work/spend | 0 | 0 |

## M6DBG final verification summary

| Check | Result |
|---|---|
| Four-provider subset/order/failure matrix | PASS — deterministic fixture coverage complete |
| Refresh collision matrix | PASS — 60 colliding requests, one in-flight Antigravity read |
| Lifecycle matrix | PASS — 20 connector runtime, 20 exact-path full-app relaunch, 50 panel, 30 Settings, wake and refresh/Disconnect-race cycles |
| Physical main-panel renderer matrix | PASS — 0–4 providers, collapsed/expanded, failure mix, Light/Dark and Settings |
| Resource trend | PASS — CPU idle; RSS decreased; threads decreased; descriptors stable; child count zero |
| Live final-code production connector | PASS — 2 final-code reads; scheduler/manual coalescing; one process; teardown |
| Focused / affected / complete fresh suite | PASS — 11/11; 85/85; 570/570 |
| Debug / Release / strict Release | PASS / PASS / PASS with Swift warnings as errors |
| Working-tree M6DBG preflight package | PASS — build 202608090002, arm64, strict deep signature, system dependencies, no bundled `agy` |
| Privacy, frozen M5 and protected provider audits | PASS — no secret/account identity/private provider data; accepted M5 52-file manifest and Desktop executable unchanged; direct Codex/Claude/WorkBuddy paths untouched |
| Independent staged-index review | PASS — exact ten-file cached scope; no blocker or actionable issue |
| Commit-exact package | Pending |
| Credits | `CREDITS DEFER` |
