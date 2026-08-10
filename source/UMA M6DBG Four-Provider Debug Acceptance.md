# UMA M6DBG Four-Provider Debug Acceptance

**Goal:** M6DBG-G1 — Four-Provider Main-App Debugging and Defect Closure
**Date:** 2026-08-09
**Starting commit:** `d2d9d87f3b667ed138cfee0a10ec1330f6ef9dac`
**Starting tree:** `3fac77bc177f00b0bc95222148ade053a80887d4`
**Credits:** `CREDITS DEFER`

## Result contract

M6DBG validates the main application with exactly this deterministic order:

1. Codex
2. Claude Code
3. WorkBuddy
4. Google Antigravity

Google Antigravity remains excluded from Desktop Assistant. Four providers do
not force Minimalist mode. Codex app-server, Claude Browser Sync and WorkBuddy
account-web source ownership remain unchanged.

## Repairs

- A completed launch-read task could remain briefly stored and swallow the
  first later manual refresh. The connector now distinguishes an active launch
  read, which is coalesced, from a completed launch task, after which it starts
  the requested read. The launch task also remains cancellation-owned until it
  finishes, and validates the connector lifecycle generation before a read, so
  an immediate refresh followed by Disconnect cannot orphan a delayed launch
  task or republish quota after teardown.
- The production Antigravity Settings observation task was not owned by the
  model that consumed it. The Settings model now owns and cancels the task;
  stream termination removes the connector continuation.
- A transient failed current read could retain the last valid value while still
  labelling it Fresh. Retained last-valid data now becomes Cached immediately
  on failure and becomes Stale at the existing age boundary.
- The first deterministic shuffle helper returned constant zero and could
  stall inside the standard library's bounded random selection. It now uses a
  seeded deterministic generator.
- The privacy contract test initially rejected field names that are required
  solely for no-provider-work validation or are explicitly classified as
  unsupported. The test now rejects active credential/browser/Credits routes
  while affirmatively checking those safe classifications.

## Deterministic matrices

The focused M6DBG harness covers:

- every zero-through-four provider subset;
- every one-failure and two-failure combination, plus all unavailable;
- every 24 provider observation/refresh completion order permutations;
- Antigravity disappearance and reappearance;
- current, transient failure, recovery and fail-closed schema state;
- single and multiple buckets, reordered buckets and missing reset;
- 60 colliding manual/timer/provider-event refresh requests;
- 20 connector runtime cycles;
- immediate-refresh/Disconnect launch-task cancellation;
- wake notification during an active read with no duplicate read or scheduler;
- 50 panel presentation open/close cycles;
- 30 Settings observer creation/teardown cycles;
- unchanged sanitized snapshot persistence.

Required invariant results:

```text
Provider order: Codex -> Claude Code -> WorkBuddy -> Google Antigravity
Cross-provider blanking: NO
Cross-provider error inheritance: NO
Missing converted to zero: NO
Failed current read labelled Fresh: NO
WorkBuddy Credit unit changed: NO
Antigravity Desktop Assistant admission: NO
Maximum concurrent Antigravity read: 1
```

The existing M6-G2 decoder/client/connector suites remain the authoritative
matrix for CLI missing, unsupported version, login required, malformed JSON,
unsupported schema, no valid quota, disconnect during read, exact executable
trust and bounded child teardown.

## Live production acceptance

The final-code live run uses the production client, strict decoder, connector,
registry, UsageStore and shared main-panel presentation. It retains only
boolean/count evidence and no exact live value, bucket identifier, label, reset,
identity, provider response, credential, conversation, prompt or task data.

Final accepted live assertions:

```text
Current production read: PASS
Multiple independent buckets: PASS
Stable bucket identity: PASS
Remaining normalization parity: PASS
Bucket-scoped reset validation: PASS
Main-panel admission: PASS
Provider order: PASS
Desktop Assistant exclusion: PASS
Five-minute scheduled refresh: PASS
Manual/scheduled coalescing: PASS
Maximum concurrent read/process: 1
No attributable quota decrement within provider granularity: PASS
Process and scheduler teardown: PASS
```

M6DBG read accounting is recorded in the QA ledger. `/credits`, provider
prompts/tasks and intentional provider work remain zero.

## Main-panel and Settings evidence

Tightly scoped synthetic renderer evidence covers zero, one, two, three and
four providers; collapsed and expanded cards; healthy/failure mixes; Light and
Dark appearance; and the canonical Google Antigravity Settings destination.

Visual inspection passed:

- one card per provider with stable equal collapsed structure;
- no clipping, overlap, duplicate card or off-screen width change;
- WorkBuddy remains an absolute Credit value without percent semantics;
- Antigravity percentage means remaining;
- dynamic Antigravity bucket labels remain provider-scoped;
- Cached/Stale/Reconnecting indicators remain honest;
- expanded content uses the existing bounded panel scroll instead of resizing
  the panel off screen;
- Settings shows `Google Antigravity`, `Official Antigravity CLI`, Fresh state,
  Auto Refresh, Sync Now, Disable and Source and privacy.

## Lifecycle and resource acceptance

The deterministic lifecycle matrix completes 20 connector runtime cycles, 50
panel cycles and 30 Settings cycles. It also validates the wake trigger during
an active read and the immediate-refresh/Disconnect race. Each connector stop
leaves no in-flight read, scheduler or observer. The collision matrix proves
one read in flight and no catch-up burst.

The rebuilt exact working-tree preflight then completed 20 full application
launch/termination cycles using an isolated task-owned preference home. Every
cycle resolved the running executable inside the exact preflight bundle,
retained bundle identifier `com.silkrd.uma`, stayed alive through the launch
check, terminated under task ownership and left zero residual candidate
processes. The isolated run performed no Antigravity provider read and did not
touch the protected Desktop application.

A separate task-owned four-provider renderer soak sampled only its exact PID.
Across initial, midpoint and final samples:

| Metric | Initial | Midpoint | Final |
|---|---:|---:|---:|
| CPU | 0.0% | 0.0% | 0.0% |
| RSS | 101,232 KiB | 91,328 KiB | 91,264 KiB |
| Threads | 4 | 3 | 3 |
| File descriptors | 37 | 37 | 37 |
| Antigravity child processes | 0 | 0 | 0 |

No monotonic RSS, thread or descriptor growth was observed. The unchanged
snapshot test proves that an identical normalized observation does not replace
the sanitized persistence file. All task-owned processes were terminated.

## Privacy and protection

- no credential, token, cookie, Keychain, browser profile or authentication
  database access;
- no raw Antigravity JSON, stderr, exact live value, account identity,
  conversation or task identifier persisted;
- no broad process argv or environment capture;
- no `/credits` read or implementation;
- no bundled `agy`;
- no Desktop Assistant production edit;
- no Codex, Claude or WorkBuddy source-mechanism edit;
- protected M5 manifest and protected Desktop UMA executable remain unchanged.

### Mandatory M6ADBG process-inspection contract

M6ADBG must inspect only the exact task-owned executable path or exact
executable name, exact PID, process count, required parent/child ownership,
bounded resource counters and exit/absence classification. It must not collect
full process command lines, unrelated process arguments or broad process
environments. Raw process output is not retained. Any check that cannot be
completed with these normalized facts fails closed rather than widening the
inspection boundary.

## Final verification and delivery

Final test, build, staged-index, commit and package facts are recorded here only
after they complete:

```text
Focused M6DBG: PASS — 11/11
Affected M6: PASS — 85/85 across 8 suites
Fresh full suite: PASS — 552 UI + 18 bridge = 570/570
Debug: PASS
Release: PASS
Strict-concurrency Release: PASS with Swift warnings as errors
Working-tree preflight package: PASS — build 202608090002
Privacy/identity/secret/package scans: PASS
Protected M5 52-file manifest: unchanged
Protected Desktop executable SHA-256: unchanged
Independent staged-index review: PASS — exact ten-file cached scope; no blocker or actionable issue
Final commit/tree: PASS — `6e15705cf72794e359ac66d8aaa7141353b92ad0` / `f86ee0f79d9d28bbbdf5e480231efc015d7c8302`
Commit-exact package: PASS — build `202608090104`, archive SHA-256 `69cbbb1b38c2d2a7d5ef1065d80627c0eed96e2655e66f694d9bbe5890d38f5a`
Post-commit worktree/index: PASS — clean / empty
```

The package-wide `/credits` substring is the accepted WorkBuddy extraction
regular expression, not an Antigravity command or endpoint. Absolute local
paths are the accepted local native-host registration and compiler provenance
already present in the G3 package; they contain no account/provider identity or
secret. M6DBG adds neither class of string.

## Completion lock

After M6DBG PASS, exactly one next task is permitted:

`M6A-G1 — Google Antigravity in Desktop Assistant`

Do not start it automatically.
