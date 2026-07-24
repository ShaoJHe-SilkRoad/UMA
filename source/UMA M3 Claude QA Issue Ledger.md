# UMA M3 Claude QA Issue Ledger

Date: 2026-07-24

## Gate summary

Admission verdict:
**`NO-GO — NOT INSTALLED`**.

The dossier is a privacy-safe negative capability record. It contains no raw
status-line payload, account identity, transcript data, source path, prompt,
response, credential, or authentication material.

## Issue ledger

| Issue ID | Found by | Severity | Evidence | Acceptance impact | In scope | Repair | Focused retest | Regression retest | Status |
|---|---|---:|---|---|---|---|---|---|---|
| M3G1-001 | Source / Protocol Auditor | Blocker | `claude` does not resolve in normal interactive login shell; standard CLI candidates absent | Official installed implementation and payload cannot be proven | Yes, classification only | Record `NO-GO — NOT INSTALLED`; installation requires separate owner choice | Independent command-resolution audit agreed | Repository baseline/diff checks | Open owner condition |
| M3G1-002 | Source / Protocol Auditor | High | Claude Desktop exists but is not Claude Code | Prevents false admission of the desktop bundle | Yes | Distinguish products explicitly; do not use Desktop as source | Bundle identifier/version distinction recorded | Dossier consistency review | Closed |
| M3G1-003 | Configuration Steward | High | User/project/local/system `statusLine` absent; server-managed settings unobservable offline | Global effective command cannot be certified | Yes | Classify local `NO EXISTING STATUS LINE`, global `UNVERIFIED`; require future `/status` | Independent hierarchy inventory agreed | Configuration contract review | Open owner condition |
| M3G1-004 | Primary / Examiner | Blocker | No runtime payload can be observed | Five-hour, seven-day, and model-weekly limits cannot be admitted | Yes | Classify each as `UNSUPPORTED`; forbid inference | Capability table checks independent decisions | Documentation cross-check | Closed for this NO-GO |
| M3G1-005 | Configuration Steward | Medium | No configuration file exists and no write occurred | Backup/probe stages are not applicable | Yes | Preserve absence; document future byte-and-metadata rollback | Pre/post absence audit | Generated-artifact audit | Closed |
| M3G1-006 | Privacy Steward | High | Official schema includes transcript, workspace, repository, and identifier fields | A future permissive serializer could leak private data | Yes | Closed-by-default allowlist and explicit denylist; no raw payload retention | Tracked-diff privacy scan | Generated-artifact audit | Closed for documentation |
| M3G1-007 | QA Runner | Medium | No executable sanitizer/probe helper was added | Compiled focused tests would have no implementation target | Yes | Do not add placeholder tests; record complete future test contract | Exact tracked scope audit | Full suite not applicable | Closed |
| M3G1-008 | Primary | Medium | Latency and duplicate behavior cannot be measured | Under-50-ms wrapper target and health fallback remain unproven | Yes | Record documented triggers only; require later measurements | Dossier measurement table review | Not applicable | Open owner condition |

## QA contract for the next admissible run

When an official CLI is installed and a task-owned sanitizer/probe is justified,
focused tests must cover:

- valid and malformed JSON;
- missing, null, and independently absent plan windows;
- unknown future fields and wrong-path lookalikes;
- nested values and structural limits;
- payloads at and above byte, depth, node, and array limits;
- invalid, out-of-range, and nonfinite numbers;
- transcript-path, identity, workdir, repository, and raw-session-ID rejection;
- allowlist-only output and generic redacted diagnostics;
- proof that supplied filesystem paths are never opened or resolved;
- previous-command output/failure preservation;
- direct, symlinked, and shell-wrapped recursion rejection;
- deterministic restore on success, failure, interruption, and concurrent
  modification;
- restrictive permissions and atomic snapshot replacement;
- no network dependency;
- bounded latency, no fork/process growth, duplicate coalescing, and
  last-valid retention.

Default tests must use synthetic standard input and task-owned temporary
directories only. They must never invoke Claude Code or inspect user
configuration, accounts, sessions, transcripts, WorkBuddy, or OneDrive.

## Verification applicability

- Focused compiled tests: **not applicable**; no helper, sanitizer, or compiled
  product code changed.
- Affected existing tests: **not applicable**; documentation-only scope.
- Debug/Release build: **not applicable**.
- Full suite: **not run**, as no compiled module or shared test infrastructure
  changed.
- Required for this documentation gate: Markdown structure checks,
  `git diff --check`, privacy scan, exact-file scope audit, generated-artifact
  audit, independent Examiner review, and independent staged-index review.

## Generated and raw evidence policy

The only permitted task evidence location is
`/private/tmp/uma-m3-g1-*`. Evidence there must be sanitized and is excluded
from Git. No raw payload exists because no probe ran.

Never stage:

- payloads or snapshots;
- logs, screenshots, or process captures;
- settings/configuration backups;
- account or authentication data;
- `.build`, `.swiftpm`, caches, or binaries.

## Closure conditions

M3-G1 may close with the documentation commit after:

1. all four scoped records agree on `NO-GO — NOT INSTALLED`;
2. privacy and generated-artifact scans pass;
3. the Examiner accepts the negative admission decision;
4. the cached diff contains only the four exact records;
5. independent staged-index review passes;
6. the local commit is created and the worktree/index are clean.

The open owner conditions do not authorize installation or M3-G2. They define
the exact prerequisite for a future capability rerun.
