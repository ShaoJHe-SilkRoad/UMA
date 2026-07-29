# UMA M5 Claude QA Issue Ledger

Date: 2026-07-28

## Decision

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
