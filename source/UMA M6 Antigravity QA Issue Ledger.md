# UMA M6 Antigravity QA Issue Ledger

**Goal:** M6-G1
**Date:** 2026-08-08
**Decision:** `SETUP REQUIRED — OFFICIAL ANTIGRAVITY CLI NOT INSTALLED`

## Scope

M6-G1 is an admission-only Goal. It may add exactly these files:

```text
Tests/CodexUsageUITests/M6G1AntigravitySourceAdmissionTests.swift
source/UMA M6 Antigravity Local Source Dossier.md
source/UMA M6 Antigravity Admission Decision.md
source/UMA M6 Antigravity Privacy Contract.md
source/UMA M6 Antigravity QA Issue Ledger.md
```

No runtime, manifest, browser-extension, package-script, M5 record, M5 test, or
existing Scope Lock change belongs to this Goal.

## Issue ledger

| ID | First evidence | Classification | Root cause | Resolution | Retest | Final status |
|---|---|---|---|---|---|---|
| M6G1-001 | PATH, documented path, application, receipt, Spotlight, and LaunchServices discovery found no CLI | Setup gate | Official Antigravity CLI is not installed on this Mac | Return `SETUP REQUIRED`; do not install/update/login in G1 | Deterministic absence/decision tests | Closed as setup condition |
| M6G1-002 | No executable or installed help exists | Capability gate | Exact installed argv and structured print capability cannot be proven | Preserve documented syntax as an untested candidate only | Capability-unavailable test | Deferred to M6-SETUP-G1 |
| M6G1-003 | No provider executable exists | Schema gate | Root, bucket, semantic, reset, and private-field shapes are unavailable | Do not invent decoder fields from planning material | Live-schema-unavailable test | Deferred to renewed admission |
| M6G1-004 | CLI absence prevents provider-state observation | Authentication gate | Authentication cannot be distinguished from missing installation | Record `unobservable`, not logged-out/expired/enterprise | Authentication-classification test | Closed honestly for G1 |
| M6G1-005 | No live read occurred | Proof limitation | Installed no-turn/no-spend behavior cannot be observed | Separate public-contract support from unavailable live causality | Zero-read/no-claim test | Deferred to renewed admission |
| M6G1-006 | Optional `/credits` evidence unavailable | Optional source | No Credit schema or balance was read | Record `CREDITS DEFER`; do not block quota setup decision | Credits-independence test | Closed as deferred optional source |
| M6G1-007 | Initial focused test found that the Privacy Contract omitted the only permitted next task | Record consistency | The privacy boundary documented the setup decision but not its explicit successor lock | Add `M6-SETUP-G1` as the only next task and keep M6-G2 locked | Focused suite rerun: 8/8 PASS | Closed |
| M6G1-008 | Initial cached-diff check found two-space line endings in new records | Staged-diff hygiene | Markdown formatting introduced unintended trailing spaces | Remove the trailing spaces without changing the admission decision | Cached whitespace check and independent staged-index rerun: PASS | Closed |

No issue was converted into a connector workaround. No runtime repair was
required or authorized.

## Shared sanitized evidence

The source/protocol examiner, privacy examiner, and QA runner reviewed one
owner-only sanitized packet. It contained only:

- current-device absence classifications;
- unavailable installed-artifact/schema classifications;
- official public source-contract classifications;
- zero-read/prompt/task/spend accounting;
- `SETUP REQUIRED`, `CREDITS DEFER`, and `M6-SETUP-G1`.

It contained no raw stdout/stderr/JSON, exact quota or reset value, identity,
credential, browser data, conversation, task content, or provider content. The
packet was deleted after all reviews and was not copied into Git.

## Probe accounting

| Operation | Authorized | Consumed |
|---|---:|---:|
| `/usage`, `/quota`, `/credits`, or equivalent source reads | 3 | 0 |
| Provider prompts/tasks | 0 | 0 |
| Intentional quota/USD spend | 0 | 0 |

No retry occurred and no provider process was launched.

## Required verification

| Check | Result |
|---|---|
| Focused M6-G1 tests | 8/8 PASS |
| Full `script/test.sh` suite | 493/493 PASS: 475 CodexUsageUITests + 18 ClaudeBrowserBridgeCoreTests |
| `git diff --check` | PASS |
| Privacy/identity/secret scan | PASS; synthetic `.invalid` fixture only |
| M5/Codex/Claude/WorkBuddy protected diff audit | PASS; byte-identical to M6-B0 |
| Exact staged-index review | PASS after whitespace repair and independent rerun |
| Product Debug/Release builds | Not required: documentation plus isolated test-only harness |

## Mechanism audit

```text
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
Antigravity production runtime implemented: NO
```

## Completion rule

All four records must agree on:

```text
Admission: SETUP REQUIRED
Reason: official CLI not installed
Credits: CREDITS DEFER
Live provider reads: 0/3
Only next task: M6-SETUP-G1 after Founder authorization
```

M6-G2 remains locked.
