# UMA M7 Cursor QA Issue Ledger

**Goal:** M7-CLOSE-G1
**Date:** 2026-08-11
**Decision:** `M7 CLOSED — CURSOR UNSUPPORTED — SOURCE NOT ADMITTED`
**Only next recommendation:** Return to Founder for next-provider selection

## Current M7 closeout truth

```text
CURSOR BROWSER SOURCE ARCHITECTURE VIABLE
FREE PLAN SEMANTICS RESOLVED
FREE PLAN ENFORCEMENT RELIABILITY NOT ADMITTED
PAID PLAN CONTRACT NOT LIVE QUALIFIED
CURSOR PRODUCTION SUPPORT UNSUPPORTED — SOURCE NOT ADMITTED
```

## Issue ledger

| ID | Severity | Discovery | Evidence / risk | Disposition | Verification | Status |
|---|---:|---|---|---|---|---|
| M7G1-001 | Gate | Current-device inventory | Cursor app and CLI were absent; no admitted structured local quota source | Preserve direct-source `NO-GO` | Historical deterministic admission tests | Closed |
| M7G1-004 | Blocking | Authentication/privacy review | Team Admin API requires credentials and exposes the wrong identity/event scope | Reject credential route | Privacy contract and deterministic route test | Closed |
| M7G1-006 | Privacy | Process/evidence review | Broad argv/environment capture could expose provider metadata | Exact PID/path/count/resource/exit evidence only | Independent privacy review | Closed |
| M7G1B-002 | Privacy | Isolated probe design | Shared browser state or login-page inspection could expose private session data | Dedicated sandbox/store; no login DOM; later reject embedded login | Entitlement/source audit | Closed |
| M7G1B-003 | Gate | Embedded authentication | Provider-controlled Google login failed in embedded WebKit | Reject isolated architecture; no retry/bypass | Sanitized route classification only | Closed |
| M7G1B-004 | Superseded | Free display semantic | G1B lacked evidence to classify the one Free percentage | Superseded by current Cursor-owned Support evidence: percentage is used | M7-G1C semantic/normalization tests | Closed |
| M7G1B-006 | Privacy | Human-supplied screenshot | Identity metadata appeared transiently | Do not reproduce or retain | Retained copies: 0 | Closed |
| M7G1B-008 | Privacy | Safari accessibility inspection | Two filtered reads exposed an exact-quota data class transiently | Prohibit dashboard accessibility reads; sanitized receipt only | Retained copies: 0; cause removed | Closed |
| M7G1C-001 | Correction | Current Cursor-owned Support evidence | Free Overview percentage is explicitly treated as used and its complement as remaining | Admit `USED`; normalize once as `100 - used` | Boundary and no-double-inversion tests | Closed |
| M7G1C-002 | Blocking | Free enforcement reliability | Cursor Support confirms IDE blocking can disagree with dashboard remaining allowance | Dashboard is display truth, not admitted availability predictor | Deterministic separation test and public evidence review | Closed as decision; product remains locked |
| M7G1C-003 | Blocking | Paid-plan coverage | Two pools are documented for Pro/Pro Plus/Ultra but no paid account was observed | `DOCUMENTED BUT NOT LIVE QUALIFIED`; never infer from Free fixture | Account-mode isolation test | Closed as decision; product remains locked |
| M7G1C-004 | Architecture | Browser companion adjudication | G1B architecture gates passed independently of source reliability | Preserve `ARCHITECTURE VIABLE`; no new Safari run | Existing sanitized evidence and cleanup audit | Closed |
| M7G1C-005 | Regression | Scope control | Decision correction could alter runtime or protected providers | Five documentation/test files only | Protected-path audit | Closed |
| M7CLOSE-001 | Gate | Accepted M7-G1C decision | A technically viable dashboard path does not satisfy reliable pause prediction | Record Cursor as `Unsupported — source not admitted` | Closeout truth tests | Closed |
| M7CLOSE-002 | Coverage | Paid-plan documentation | Two paid pools are documented but were not live qualified | Preserve documented structure without inferring from Free | Account-mode closeout tests | Closed |
| M7CLOSE-003 | Product | Runtime/source inventory | Cursor could be mistaken for hidden or experimental support | Verify no Cursor runtime or production browser artifact exists | Four-provider and source-tree tests | Closed |
| M7CLOSE-004 | Security | Browser closeout | Temporary admission tooling must not survive M7 | Preserve accepted Off/unregistered/removed cleanup truth; do not reopen Safari | Closeout privacy test and protected audit | Closed |

## Historical M7-G1C exact authorized edit set

```text
Tests/CodexUsageUITests/M7G1CursorSourceAdmissionTests.swift
source/UMA M7 Cursor Browser Source Dossier.md
source/UMA M7 Cursor Browser Admission Decision.md
source/UMA M7 Cursor Privacy Contract.md
source/UMA M7 Cursor QA Issue Ledger.md
```

```text
Production source files changed: NO
Browser extension files changed: NO
Package scripts changed: NO
M5/M6 records changed: NO
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
Antigravity mechanism changed: NO
Cursor runtime implemented: NO
```

## M7-CLOSE-G1 exact authorized edit set

```text
Tests/CodexUsageUITests/M7CloseCursorSourceAdmissionTests.swift
source/UMA M7 Cursor Closeout.md
source/UMA M7 Cursor QA Issue Ledger.md
```

```text
Production source files changed: NO
Browser extension files changed: NO
Package scripts changed: NO
M5/M6 records changed: NO
source/reference/** changed: NO
Codex mechanism changed: NO
Claude mechanism changed: NO
WorkBuddy mechanism changed: NO
Antigravity mechanism changed: NO
Cursor runtime implemented: NO
M7-G2 remains locked: YES
```

## Operation accounting

M7-G1B historical browser evidence remains sanitized and unchanged:

```text
Successful sanitized observations: 8
Provider prompts/tasks/spend: 0/0/0
Retained incident identity/screenshot/log/payload copies: 0
Retained exact-quota/DOM/URL copies: 0
```

M7-G1C performed only public-source and repository work:

```text
M7-G1C provider reads/browser logins/prompts/tasks/spend: 0/0/0/0/0
```

Here, `provider reads` means authenticated quota/dashboard reads from the
Human's session. Public Cursor source-document retrieval is not an
authenticated provider read and accessed no account or session data.

Rejected routes remain API key, copied token, cookie, Keychain, private
endpoint, browser-profile import, manual quota, and inferred quota.

M7-CLOSE-G1 performed repository-only closeout work:

```text
Cursor reads/browser login actions/prompts/tasks/intentional spend: 0/0/0/0/0
```

## M7-CLOSE-G1 verification ledger

| Check | Result |
|---|---|
| Focused M7 closeout tests | PASS — 9/9 in one suite |
| Relevant M7 regression | PASS — 43/43 across three M7 suites |
| Deterministic serial full suite | PASS — 619/619 UI tests in 64 suites plus 18/18 bridge tests; 637/637 total |
| Debug/Release/strict builds | Not required — no production/package code changed |
| `git diff --check` | PASS |
| Privacy/identity/secret scan | PASS — no retained identity, credential, token, cookie, raw page data, or exact Founder quota value |
| Existing four-provider protected audit | PASS — no production, M5/M6, or accepted-provider path changed; Desktop UMA unchanged |
| `source/reference/**` audit | PASS — no checksum-locked reference file changed |
| Browser cleanup | Accepted G1B/G1C state preserved; no Safari action in M7-CLOSE-G1 |
| Independent staged-index review | PASS — source, privacy, and QA examiners accepted the exact three-file cached closeout scope after the historical G1C section was explicitly labeled as superseded |
| Post-commit clean worktree/index | Delivery gate — verified after commit and reported in the final handoff |

## Historical M7-G1C verification ledger — superseded by M7-CLOSE-G1

The following ledger is retained only as predecessor evidence. Its task and
support-status language is not the current M7 decision.

| Check | Result |
|---|---|
| Source/protocol examiner | PASS — corrected source decision and exact five-file scope are coherent |
| Privacy/authentication examiner | PASS — public-source/live-read distinction is explicit; containment and zero authenticated reads hold |
| QA/admission runner | PASS — staged logic, test counts, scope, and durable evidence are coherent |
| Focused M7-G1C tests | PASS — 29/29 in one suite |
| Complete deterministic test suite | PASS — 610/610 UI tests in 63 suites plus 18/18 bridge tests in one suite; 628/628 total |
| Debug/Release/strict builds | Not required — no production/package code changed |
| `git diff --check` | PASS |
| Privacy/identity/secret scan | PASS — no retained account identity, credential, token, cookie, raw DOM, or exact Founder quota value |
| Protected M5/M6 and accepted-provider audit | PASS — no protected or production path changed |
| Protected Desktop UMA | PASS — executable SHA-256 remains `88ffbb48de43253f7289fe038dff9d0b195e61398f969439ff5c8729ecbef91a` |
| Browser cleanup | PASS from G1B; Safari unsigned mode `Off`, companions unregistered, task-owned residue absent |
| Independent staged-index review | PASS — three-examiner review found no blocking or actionable issue after the accounting clarification |
| Post-commit clean worktree/index | Delivery gate — verified after this commit and reported in the final M7-G1C handoff |

## Historical M7-G1C completion contract — superseded by M7-CLOSE-G1

The following block records the G1C state at that earlier boundary. The
authoritative current state is the Final M7 closure contract below.

```text
Corrected decision: NO-GO
Free percentage semantic: USED
Normalization: remaining = 100 - used
Free enforcement reliability: NOT ADMITTED
Paid-plan coverage: DOCUMENTED BUT NOT LIVE QUALIFIED
Browser architecture: VIABLE
Cursor production support: LOCKED
M7-G2 remains locked
Only next task: Founder source-direction decision
M7-G1C provider reads/browser logins/prompts/tasks/spend: 0/0/0/0/0
```

## Final M7 closure contract

```text
M7 status: CLOSED — NO-GO
Cursor production support: UNSUPPORTED
Status label: Unsupported — source not admitted
Direct local/CLI source: NO-GO
Browser architecture: TECHNICALLY VIABLE
Free semantic: USED
Normalization: remainingPercent = 100 - usedPercent
Free enforcement reliability: NOT ADMITTED
Paid-plan coverage: DOCUMENTED BUT NOT LIVE QUALIFIED
Current supported providers: Codex, Claude Code, WorkBuddy, Google Antigravity
M7-G2 remains locked
Only next recommendation: Return to Founder for next-provider selection
Cursor reads/browser login actions/prompts/tasks/intentional spend: 0/0/0/0/0
```
