# UMA M5 Claude QA Issue Ledger

Date: 2026-07-28

## Decision

**SETUP REQUIRED — CLAUDE CODE CLI NOT INSTALLED**

## Evidence boundary

The QA program uses current official documentation, sanitized local
presence/type classifications, and synthetic fixtures only. It contains no raw
provider payload, real quota value, credential, account identity, settings
backup, private path, transcript, prompt, response, task, or tool content.

## Issue ledger

| ID | First evidence | Severity | Root cause | Repair / decision | Focused retest | Affected retest | Status |
|---|---|---:|---|---|---|---|---|
| M5G1-001 | Normal login-shell and standard installation candidates do not resolve Claude Code | Blocker | Official CLI is not installed | Classify `SETUP REQUIRED`; do not install under M5-G1 | 19/19 PASS | Repository gate PASS | Open setup condition |
| M5G1-002 | Official documentation defines structured five-hour/seven-day fields | High | Historical M3 evidence predates the current documented source contract | Record current official semantics without claiming installed capability | 19/19 PASS | Durable-record consistency PASS | Closed |
| M5G1-003 | Executable is absent | High | No runtime exists to identify or trust | Record path/version/architecture/hash/signature as not applicable | 19/19 PASS | Not applicable | Open setup condition |
| M5G1-004 | Authentication status cannot be queried | High | CLI is absent | Classify authentication as unknown; do not inspect credential stores | 19/19 PASS | Secret/private-data scans PASS | Open setup condition |
| M5G1-005 | Local settings sources are absent; server-managed policy is unobservable | High | Effective global sources require installed authenticated CLI evidence | Record local absence and global policy as unverified | 19/19 PASS | Synthetic restore fixtures PASS | Open setup condition |
| M5G1-006 | No status-line payload can be observed | Blocker | CLI and natural provider event are absent | Classify all fields unsupported on this device; forbid inference | 19/19 PASS | Malformed/missing-window coverage PASS | Open setup condition |
| M5G1-007 | Official payload includes private fields beyond quota data | High | Status-line JSON is broader than UMA’s need | Enforce test-local allowlist and explicit denylist; never retain raw JSON | 19/19 PASS | Artifact scan PASS | Closed |
| M5G1-008 | Existing command preservation cannot be proven globally | High | Server-managed settings are unverified | Prohibit future probe until all loaded sources and exact preservation are proven | 19/19 PASS | Configuration contract review PASS | Open setup condition |
| M5G1-009 | No live settings mutation occurred | Medium | Probe is not feasible with CLI absent | Record restore as not required; use synthetic byte-restore fixtures only | 19/19 PASS | Generated-artifact scan PASS | Closed |
| M5G1-010 | The historical result used NO-GO for an absent CLI | Medium | Earlier policy did not distinguish setup absence from source rejection | Apply current `SETUP REQUIRED` decision without claiming GO | 19/19 PASS | Examiner review PASS | Closed |
| M5G1-011 | Documentation/test scope requires exact delivery isolation | High | Broad staging could contaminate the dossier | Lock six exact paths and independently audit the cached diff | Initial review BLOCKED; two focused findings repaired | Final staged-index review PASS | Closed |

## Required focused coverage

The M5-G1 suite must prove:

- exact allowlist projection;
- explicit forbidden and unknown-field rejection;
- 0, fractional, and 100 percentage boundaries;
- fail-closed negative, over-100, nonnumeric, null, and nonfinite values;
- integral Unix-second reset validation;
- rejection of millisecond-shaped reset values;
- independently absent five-hour and seven-day windows;
- atomic rejection of incomplete windows;
- no inferred zero or full remaining usage;
- optional bounded version handling;
- absent, malformed, hook-disabled, managed-policy, and existing-status-line
  settings fixtures;
- owner-only backup fixture permissions;
- byte-exact synthetic restoration preserving formatting and final newline;
- no probe or mutation plan when the CLI is absent;
- agreement across all five durable records;
- exactly one next task, M5-SETUP-G1.

## Verification results

Actual pre-staging command evidence:

- Focused source-admission tests: 19/19 PASS
- Affected provider-neutral tests: 48/48 PASS across four suites
- M4 retirement regression: PASS within the affected 48-test run
- Secret-value scan: PASS
- Private-data scan: PASS; the test-local absolute-home-path text is a negative
  assertion sentinel, not a captured path
- Raw-payload/generated-artifact scan: PASS
- Production source/package-configuration unchanged audit: PASS
- `git diff --check`: PASS
- Independent staged-index review: initial review BLOCKED on explicit nonfinite
  coverage and pending ledger state; both repairs applied; final review PASS

## Completion rule

M5-G1 may close only when the durable records and focused tests agree on:

**SETUP REQUIRED — CLAUDE CODE CLI NOT INSTALLED**

M5-G2 remains locked. The only next task is M5-SETUP-G1.
