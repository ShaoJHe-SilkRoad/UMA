# UMA M5 Claude QA Issue Ledger

Date: 2026-07-28

## Current M5-G1R2 decision

**SETUP REQUIRED — AUTHENTICATED CLI STATUS-LINE EVENT NOT OBSERVED**

## Historical M5-G1R decision

**SETUP REQUIRED — CLAUDE CODE CLI PRESENT BUT NOT AUTHENTICATED**

## Evidence boundary

The QA program uses current official documentation, sanitized local
presence/type classifications, and synthetic fixtures only. It contains no raw
provider payload, real quota value, credential, account identity, settings
backup, private path, transcript, prompt, response, task, or tool content.

## M5-G1R issue ledger

| ID | First evidence | Severity | Root cause | Repair / decision | Focused retest | Affected retest | Status |
|---|---|---:|---|---|---|---|---|
| M5G1R-001 | Desktop-managed Claude Code 2.1.219 arm64 executable is present | High | Claude Desktop installed a trusted native component without the normal user launcher | Record the exact distribution class; do not install or repair it in M5-G1R | 25/25 PASS | Trust checks PASS | Closed |
| M5G1R-002 | Native signature and Gatekeeper pass while standalone-manifest checksum differs | High | The app-wrapped Desktop artifact is not the standalone release artifact | Trust the notarized Desktop distribution without claiming standalone-manifest equivalence | 25/25 PASS | Temporary manifest artifacts removed | Closed |
| M5G1R-003 | Doctor and auth status both report logged out | Blocker | Provider-managed subscription authentication is inactive | Return `SETUP REQUIRED`; do not open login or install a probe | 25/25 PASS | Secret-route names absent | Open setup condition |
| M5G1R-004 | Local settings sources and `statusLine` are absent | High | No local configuration exists; global policy remains unobservable while logged out | Preserve absence; create no backup and perform no mutation | 25/25 PASS | Exact absence recheck PASS | Closed |
| M5G1R-005 | No provider-generated status-line event is admissible | Blocker | Authentication failed before the event gate | Do not inspect or alter the reported Human task; classify all payload fields unsupported | 25/25 PASS | Payload contract tests PASS | Open setup condition |
| M5G1R-006 | Used values must convert to remaining exactly once | High | Provider semantics and UMA display semantics are opposite | Validate then convert in the shared model; UI and Maximum Decrement consume remaining only | 25/25 PASS | Conversion and affected 48/48 PASS | Closed |
| M5G1R-007 | Delivery must remain documentation/test-only | High | Runtime changes would prematurely begin M5-G2 | Lock the same six paths and independently audit the staged index | 25/25 PASS | Exact-scope and staged-index audits PASS | Closed |

## Required focused coverage

The M5-G1R suite must prove:

- exact allowlist projection;
- trusted-CLI plus logged-out admission returns `SETUP REQUIRED`;
- provider-managed authentication is accepted only when explicitly proven;
- secret and enterprise routes fail closed;
- explicit forbidden and unknown-field rejection;
- exact used-to-remaining examples for 0, 1, 36.25, 99.9, and 100;
- fail-closed negative, over-100, nonnumeric, null, and nonfinite values;
- integral Unix-second reset validation;
- rejection of millisecond-shaped reset values;
- independently absent five-hour and seven-day windows;
- atomic rejection of incomplete windows;
- no inferred zero or full remaining usage;
- conversion occurs once in the shared presentation model;
- UI sources do not repeat the conversion;
- Maximum Decrement consumes remaining values only;
- optional bounded version handling;
- absent, malformed, hook-disabled, managed-policy, and existing-status-line
  settings fixtures;
- owner-only backup fixture permissions;
- byte-exact synthetic restoration preserving formatting and final newline;
- no probe or mutation plan when authentication is absent;
- agreement across all five durable records;
- exactly one next task, M5-SETUP-G1.

## Verification results

Actual pre-staging command evidence:

- Focused source-admission tests: 25/25 PASS
- Affected provider-neutral tests: 48/48 PASS across four suites
- M4 retirement regression: PASS within the affected 48-test run
- Secret-value scan: PASS
- Private-data scan: PASS; private field names occur only in the denylist and
  explicitly synthetic negative fixtures
- Raw-payload/generated-artifact scan: PASS
- Production source/package-configuration unchanged audit: PASS
- Exact settings-absence and temporary-artifact cleanup audit: PASS
- `git diff --check`: PASS
- Independent staged-index review: PASS; no material findings

## Completion rule

M5-G1R may close only when the durable records and focused tests agree on:

**SETUP REQUIRED — CLAUDE CODE CLI PRESENT BUT NOT AUTHENTICATED**

M5-G2 remains locked. The only next task is M5-SETUP-G1.

## M5-SETUP-G1 completion addendum

The M5-G1R ledger above is retained as historical admission evidence.

| ID | First evidence | Severity | Repair / decision | Verification | Status |
|---|---|---:|---|---|---|
| M5SETUP-001 | Trusted Desktop-managed CLI was logged out | Blocker | Human completed only the official Claude.ai paid-subscription browser login | Sanitized final class: logged in, `claude.ai`, `firstParty` | Closed |
| M5SETUP-002 | Normal shell could not resolve `claude` | Blocker | Ran the official native installer once and added only the documented user PATH line | Fresh login shell resolves `~/.local/bin/claude`; version 2.1.220; doctor PASS | Closed |
| M5SETUP-003 | Setup must not cross into source probing | High | Kept Claude settings absent and performed no prompt, task, status-line, usage, or UMA operation | Secret-route, settings-absence, repository-scope, and privacy checks PASS | Closed |

M5-SETUP-G1 verification:

- official native installer URL and one-attempt limit: PASS;
- installed launcher, arm64 architecture, SHA-256, and strict signature: PASS;
- final provider-managed subscription authentication: PASS;
- API-key, copied-token, setup-token, Bedrock, Vertex, and Foundry routes:
  inactive;
- fresh-shell resolution and version: PASS;
- `claude doctor`: PASS with no installation issues;
- user Claude settings file: absent; no status line created by setup;
- prompt, response, provider task, and quota payload access: none;
- production runtime, tests, package configuration, and UMA application:
  unchanged;
- task-owned backup and temporary setup artifacts: removed;
- independent staged-index and privacy reviews: PASS; no material findings.

M5-G2 remains locked. Exactly one next task is:

**M5-G1R2**

## M5-G1R2 issue ledger

| ID | First evidence | Severity | Root cause / classification | Repair / decision | Focused retest | Affected retest | Status |
|---|---|---:|---|---|---|---|---|
| M5G1R2-001 | Native 2.1.220 launcher, signature, authentication, and doctor checks pass | High | Prior installation and login setup conditions are resolved | Admit trust and authentication only; do not infer quota capability | 26/26 PASS | Trust and auth checks PASS | Closed |
| M5G1R2-002 | User settings and local managed-policy files were absent | High | No existing status line required preservation | Record absence, install one owner-only temporary probe, restore absence exactly | 26/26 PASS | Exact restore PASS | Closed |
| M5G1R2-003 | One normal Human CLI response completed but no probe evidence object appeared | Blocker | Effective official status-line callback was not observed | Return SETUP REQUIRED; classify all quota fields unsupported on current evidence | 26/26 PASS | No provider content accessed | Open setup condition |
| M5G1R2-004 | Used values and reset epochs require strict validation | High | Provider used semantics differ from UMA remaining semantics | Preserve finite range checks, independent windows, and one-time conversion | 26/26 PASS | Affected 48/48 PASS | Closed |
| M5G1R2-005 | Probe received no callback | High | No live object exists to sanitize or classify | Persist no value; retain only the event-absence result in durable records | 26/26 PASS | Raw/private data scan PASS | Closed |
| M5G1R2-006 | Temporary user settings changed original absence state | High | A status-line command was required for the bounded probe | Verify temporary hash, remove the file, prove final absence, delete marker/probe/evidence path | 26/26 PASS | Restoration PASS | Closed |
| M5G1R2-007 | Delivery must remain documentation/test-only | High | Runtime work would prematurely begin M5-G2 | Lock six exact paths and independently audit the staged index | 26/26 PASS | Affected 48/48 PASS | Closed on exact delivery |

Required final verification:

- focused M5-G1R2 admission tests;
- used-to-remaining conversion matrix;
- malformed, missing, nonfinite, and private-field rejection;
- owner-only backup and byte-exact/absence-state restore fixtures;
- affected provider-neutral percentage and Maximum Decrement tests;
- secret, private-data, raw-payload, and generated-artifact scans;
- production runtime and package-configuration unchanged audit;
- `git diff --check`;
- exact staged-index and independent reviews.

The durable result contains no live quota percentage, reset timestamp,
credential, account identity, prompt, response, session, transcript,
workspace path, or raw provider object.

Completed verification:

- focused M5-G1R2 suite: 26/26 PASS;
- affected provider-neutral and retirement suites: 48/48 PASS;
- used-to-remaining, Maximum Decrement, malformed-value, forbidden-field,
  settings, and restoration coverage: PASS;
- exact configuration restoration and temporary-artifact deletion: PASS;
- independent privacy and unstaged-scope audit: PASS, no material findings.

M5-G2 remains locked. Exactly one next task is:

**M5-SETUP-G1**

This is a new status-line activation setup revision under the required task
label. The earlier launcher-installation and subscription-authentication
setup remains closed.
